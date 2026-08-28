# SGM-GIDAS vía el Portal GIDAS en `/sgm-gidas/` (sin tocar la LAN)

> **Fecha**: 2026-08-28
> **Autor**: Infraestructura GDC01
> **Estado**: IMPLEMENTADO, VERIFICADO Y FORMALIZADO (frontend_sgm en compose)
> **Rama (repo infra)**: `hotfix/sgm-portal-tunnel`

## Objetivo

Que la app **SGM-GIDAS** (`192.168.1.111:8080`) se pueda abrir desde la **card
del Portal GIDAS** (a través del tunnel Cloudflare) bajo **`/sgm-gidas/`**,
**SIN cambiar el acceso LAN** (que sigue usando el alias `sgm.gidas.local` ->
raíz `/` y la página principal).

## Resultado final (verificado con curl)

| Acceso | Ruta | Estado |
|--------|------|--------|
| **LAN (intacto)** | `sgm.gidas.local/` (raíz) | 200 `text/html`, assets `/assets/...` y `/api/v1/health` OK |
| **Portal (nuevo)** | `{tunnel}/sgm-gidas/` | 200 `text/html`, assets `/sgm-gidas/assets/...` OK |
| **Portal (nuevo)** | `{tunnel}/sgm-gidas/assets/index-*.css` | 200 `text/css` |
| **Portal (nuevo)** | `{tunnel}/sgm-gidas/assets/index-*.js` | 200 `application/javascript` |
| **Portal (nuevo)** | `{tunnel}/sgm-gidas/api/v1/health` | 200 `application/json` |

El error original del navegador
(`Refused to apply style ... MIME type ('application/json') ...`) quedó resuelto:
el CSS ahora se sirve como `text/css`.

## Causa raíz

La app es una **SPA de Vite/React** (React Router + llamadas al API en **runtime
JS**). Estaba buildada con `base: "/"`, por lo que generaba assets `/assets/...`
y fetches `/api/...` en la RAÍZ del origin. Al exponerla bajo `/sgm-gidas/` del
portal, esos requests caían en `/sgm-gidas/assets/...` (404) o en la raíz del
portal — el CSS devolvía otra cosa → el error de MIME.

Una SPA no se puede exponer bajo un subpath con solo `sub_filter` del nginx
(eso solo reescribe el HTML, no el JS ya compilado). La vía correcta es que la
app **conozca su base** (`VITE_BASE_PATH`).

### Requisito respetado: LAN intacta

Para no cambiar la LAN, la SGM sirve **dos bases** a la vez, decididas por el
`nginx` del proxy SGM según la ruta:

- `location /`          → frontend LAN (base `/`) — como siempre.
- `location /sgm-gidas/`→ frontend extendido (base `/sgm-gidas/`) — para el portal.

## Cambios aplicados

### VM 111 (SGM, repo `/home/infra/gidas`, user `infra`)

**1. Build de un segundo frontend con base `/sgm-gidas/` (no toca el LAN build)**

Archivos nuevos en `frontend/`:

- `frontend/nginx.portal.conf` — sirve la SPA bajo `/sgm-gidas/`:
  - `location /sgm-gidas/assets/ { alias /usr/share/nginx/html/assets/; try_files $uri =404; }`
  - `location /sgm-gidas/ { try_files $uri $uri/ /index.html; }` (SPA fallback)
  - `location = / { return 301 /sgm-gidas/; }`
- `frontend/Dockerfile.portal` — build con:
  - `VITE_BASE_PATH=/sgm-gidas/`
  - `VITE_API_BASE_URL=/sgm-gidas/api/v1`
  - `VITE_API_URL=/sgm-gidas/api`

Formalizado en el compose como servicio `frontend_sgm`:

```bash
cd /home/infra/gidas
docker compose --env-file .env.production up -d --no-deps frontend_sgm
```

> El contenedor queda en la red interna con alias `frontend_sgm`, puerto `8080`
> interno (sin puerto público), `read_only: true` + tmpfs y hardening igual al
> resto del stack. Ya NO es un `docker run` manual: desde 2026-08-28 es parte del
> `docker-compose.yml` (ver `sgm-despliegue-vm111.md`).

**2. Extendido `nginx/default.conf` del proxy SGM** (con backup) — agregado
antes de `location /`:

```nginx
# Portal: API de la SGM bajo /sgm-gidas/api/ -> backend (quita el prefijo)
location /sgm-gidas/api/ {
    rewrite ^/sgm-gidas(/.*)$ $1 break;
    proxy_pass $backend_upstream;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Request-ID $request_id;
}

# Portal: SPA de la SGM bajo /sgm-gidas/ -> frontend buildado con base /sgm-gidas/
location /sgm-gidas/ {
    proxy_pass http://frontend_sgm:8080;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Request-ID $request_id;
}
```

Reload:

```bash
docker exec gidas_prod_proxy nginx -t && docker exec gidas_prod_proxy nginx -s reload
```

### CT 208 (Portal, nginx en `/etc/nginx/nginx.conf`)

`location /sgm-gidas/` ya pasa el prefijo intacto al SGM (sin rewrite ni
sub_filter):

```nginx
location /sgm-gidas/ {
    proxy_pass http://192.168.1.111:8080;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

**Carga del portal** (`/opt/portal-gidas/config.yaml`), entrada `SGM-GIDAS`:

```yaml
- name: "SGM-GIDAS"
  url: "/sgm-gidas/"
  icon: "fas fa-network-wired"
  description: "Sistema de Gestión de Memorias"
  proxy: false
  groups:
    - "G-Direccion"
    - "G-Coordinadores"
```

> `proxy: false` + `url: "/sgm-gidas/"` hace que la card apunte directo al
> location de nginx (patrón igual a Redmine/GitLab/Grafana). Con `proxy: true`
> la card iría por el FastAPI proxy (deprecated) a la RAÍZ de `sgm.gidas.local`,
> que NO funciona para esta SPA.

Reinicio del portal:

```bash
systemctl restart portal-gidas && systemctl is-active portal-gidas
```

## Bloqueo resuelto: reload de nginx del portal (CT 208)

### Síntoma

`nginx -s reload` devolvía rc=0 pero el master **no aplicaba** la config nueva;
`nginx -t` fallaba con:

```
[emerg] chown("/var/lib/nginx/tmp/client_body", 998) failed (1: Operation not permitted)
```

### Causa raíz

En el LXC unprivileged, los directorios `/var/lib/nginx/tmp/*` (`client_body`,
`proxy`, `fastcgi`, `scgi`, `uwsgi`) tenían dueño `nobody` cuyo UID del HOST
**está fuera del rango mapeado** del CT → ni `root` del CT podía leerlos/
chownearlos (`Permission denied`). Por eso nginx no podía recargar y seguía con
la config anterior (el `location /sgm-gidas/` con rewrite viejo → bucle).

### Fix aplicado

Renombrar (no borrar) los subdirs temp para preservar el punto de retorno, y
dejar que nginx los **recreé** con el dueño correcto al recargar:

```bash
TS=$(date +%Y%m%d%H%M%S)
for d in client_body proxy fastcgi scgi uwsgi; do
  [ -d /var/lib/nginx/tmp/$d ] && mv /var/lib/nginx/tmp/$d /var/lib/nginx/tmp/$d.bak-$TS
done
nginx -t && nginx -s reload
```

Después de esto: `nginx -t` → **successful**, reload aplica la config nueva.

> Verificar SIEMPRE la config que realmente quedó activa con `nginx -T`
> (no solo el rc=0 del reload), porque el `etime` del master **NO se resetea en
> un reload** (solo en restart).

## Puntos de retorno (backups)

### En VM 111 (SGM) — `/home/infra/gidas/backups/sgm-portal-subpath/`

| Archivo | Contenido |
|---------|-----------|
| `default.conf.presgm.<ts>.bak` | `nginx/default.conf` antes de extender con `/sgm-gidas/` |
| `default.conf.<ts>.bak` | `nginx/default.conf` original de referencia |
| `docker-compose.yml.<ts>.bak` | compose original |
| `frontend.Dockerfile.<ts>.bak` | Dockerfile original |

### En CT 208 (Portal) — `/root/backups/sgm-portal-subpath/`

| Archivo | Contenido |
|---------|-----------|
| `nginx.conf.presgm.<ts>.bak` | nginx.conf antes del cambio |
| `config.yaml.presgm.<ts>.bak` | config del portal antes del cambio |
| `nginx-tmp/` | los dirs temp viejos renombrados `.bak-<ts>` |

## Rollback

Si algo falla o se quiere deshacer:

1. **Portal (card)**: restaurar `config.yaml.presgm.*.bak` y reiniciar
   `portal-gidas`.
2. **nginx del portal**: restaurar `nginx.conf.presgm.*.bak` + `nginx -t && nginx -s reload`.
3. **SGM**: restaurar `default.conf.presgm.*.bak` del proxy y recargarlo; parar
   y quitar el contenedor con compose (`cd /home/infra/gidas && docker compose \
   --env-file .env.production stop frontend_sgm`); la LAN queda igual porque
   el `location /` y `/api/` nunca se tocaron.

## Verificación

```bash
# LAN (debe seguir OK)
curl -sk -o /dev/null -w "%{http_code}\n" -H "Host: sgm.gidas.local" http://192.168.1.111:8080/
curl -sk -o /dev/null -w "%{http_code}\n" -H "Host: sgm.gidas.local" http://192.168.1.111:8080/api/v1/health

# Portal / subpath (desde CT 208)
T=$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' /var/log/cloudflared.log | tail -1)
curl -sk -o /dev/null -w "%{http_code} %{content_type}\n" "$T/sgm-gidas/"
curl -sk -o /dev/null -w "%{http_code} %{content_type}\n" "$T/sgm-gidas/api/v1/health"
```

## Pendiente

- Verificación E2E con un usuario real de grupo `G-Direccion` o
  `G-Coordinadores` logueado en el portal (la infraestructura está 100%
  verificada por curl; no se probó el render de la card con login en esta
  sesión por falta de credenciales AD válidas).

## Referencias

- **Cómo está desplegada la app en la VM (estado actual)**: ver
  `docs/runbooks/sgm-despliegue-vm111.md` — contenedores, red, DNS aliases,
  los dos builds del frontend, y la formalización del servicio `frontend_sgm`
  en el compose (v2).
