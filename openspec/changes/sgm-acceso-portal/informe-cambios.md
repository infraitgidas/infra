# Informe de Cambios — Habilitación de SGM-GIDAS desde el Portal GIDAS

**Feature branch**: `docs/sgm-portal-runbooks` (antes `hotfix/sgm-portal-tunnel`)
**Fecha**: 2026-08-28
**Estado**: IMPLEMENTADO, VERIFICADO Y FORMALIZADO

---

## 1. Resumen Ejecutivo

Se habilitó el acceso a la app **SGM-GIDAS** desde la **card del Portal GIDAS**
(sistema de gestión de memorias), servida bajo el subpath **`/sgm-gidas/`** a
través del tunnel Cloudflare del portal, **sin modificar el acceso LAN**
(`sgm.gidas.local` → raíz `/`, que sigue intacto).

El problema original era un error de navegador (`Refused to apply style ... MIME
type application/json`) causado por servir una SPA de Vite/React buildada con
base `/` bajo un subpath. Se resolvió construyendo un **segundo build** del
frontend con base `/sgm-gidas/` y enrutando por el nginx del proxy según la ruta.

| Concepto | Antes | Después |
|----------|-------|---------|
| **Acceso LAN** | `sgm.gidas.local` → raíz `/` | **Intacto** (base `/`, página principal) |
| **Acceso Portal** | ❌ No disponible (error MIME/404) | ✅ `/sgm-gidas/` (card del portal) |
| **Frontend** | 1 build (base `/`) | **2 builds**: LAN `/` + portal `/sgm-gidas/` |
| **Contenedor** `frontend_sgm` | `docker run` manual (fuera de compose) | **Formalizado** en `docker-compose.yml` |

---

## 2. Causa Raíz

La SGM es una **SPA de Vite/React**: los paths de assets, rutas y llamadas al API
se generan en **build time** según `VITE_BASE_PATH`. El build original usaba
`base: "/"` → generaba `/assets/...` y `/api/...` en la raíz. Al exponerlo bajo
`/sgm-gidas/` del portal, esos requests caían en rutas inexistentes o en la raíz
del portal → el CSS devolvía otro content type (error de MIME en el navegador).

Una SPA no se puede exponer bajo un subpath con solo `sub_filter` del nginx (eso
reescribe solo el HTML, no el JS ya compilado). La vía correcta es que la app
**conozca su base** (`VITE_BASE_PATH`).

---

## 3. Cambios Aplicados

### 3.1. VM 111 (SGM, repo `/home/infra/gidas`)

| Cambio | Detalle |
|--------|---------|
| **Segundo build del frontend** | `frontend/Dockerfile.portal` con `VITE_BASE_PATH=/sgm-gidas/`, `VITE_API_BASE_URL=/sgm-gidas/api/v1`, `VITE_API_URL=/sgm-gidas/api` |
| **Serve bajo subpath** | `frontend/nginx.portal.conf`: alias `/sgm-gidas/assets/` → `html/assets/` + SPA fallback `try_files` |
| **Proxy extendido** | `nginx/default.conf`: `location /sgm-gidas/` → `frontend_sgm:8080`; `location /sgm-gidas/api/` → `rewrite` + backend. `location /` y `/api/` (LAN) **intactos** |
| **Contenedor formalizado** | Servicio `frontend_sgm` agregado al `docker-compose.yml` (antes `docker run` manual). Imagen `gidas-frontend-sgm`. `read_only`+tmpfs, `cap_drop:ALL`, sin puerto público, alias de red `frontend_sgm` |

### 3.2. CT 208 (Portal, nginx `/etc/nginx/nginx.conf` + config YAML)

| Cambio | Detalle |
|--------|---------|
| **nginx del portal** | `location /sgm-gidas/` → `proxy_pass http://192.168.1.111:8080` (prefijo intacto, sin rewrite/sub_filter) |
| **Config YAML portal** | Entrada `SGM-GIDAS`: `url: "/sgm-gidas/"` + `proxy: false` (patrón Redmine/GitLab/Grafana; `proxy: true` no sirve para esta SPA) |
| **Fix reload de nginx** | Resuelto bloqueo `[emerg] chown /var/lib/nginx/tmp/... Operation not permitted` (dirs temp con dueño `nobody` fuera del rango mapeado del LXC unprivileged). Fix: renombrar a `.bak-<ts>`; nginx los recrea con dueño correcto al recargar |

---

## 4. Verificación

| Criterio | Resultado |
|----------|-----------|
| Portal `/sgm-gidas/` (tunnel Cloudflare) | ✅ `200 text/html` |
| Portal asset JS `/sgm-gidas/assets/index-*.js` | ✅ `200 application/javascript` |
| Portal asset CSS `/sgm-gidas/assets/index-*.css` | ✅ `200 text/css` (error MIME resuelto) |
| Portal API `/sgm-gidas/api/v1/health` | ✅ `200 application/json` |
| LAN `sgm.gidas.local/` (raíz) | ✅ `200` intacta |
| `docker compose ps` lista `frontend_sgm` | ✅ parte del proyecto `gidas` |
| `nginx -t` del portal | ✅ `successful` (reload aplica) |

---

## 5. Decisiones Técnicas

| Decisión | Alternativa | Motivo |
|----------|------------|--------|
| **Dos builds del frontend** | `sub_filter` en nginx | La SPA genera paths en build time; `sub_filter` solo reescribe HTML, no el JS. La app debe conocer su base |
| **`proxy: false` + `url: /sgm-gidas/`** en portal | `proxy: true` (FastAPI proxy) | El proxy FastAPI está deprecated y llevaría a la raíz de `sgm.gidas.local`, que no funciona para la SPA subpath |
| **Formalizar `frontend_sgm` en compose** | Seguir con `docker run` manual | Compose gestiona el contenedor; sobrevive a `docker compose up/down` y queda versionado |

---

## 6. Puntos de Retorno

| Recurso | Ubicación |
|---------|-----------|
| SGM (VM 111) | `/home/infra/gidas/backups/sgm-portal-subpath/` (default.conf, docker-compose, Dockerfile) |
| Portal (CT 208) | `/root/backups/sgm-portal-subpath/` (nginx.conf, config.yaml, nginx-tmp `.bak-<ts>`) |

Rollback paso a paso documentado en el runbook `docs/runbooks/sgm-portal-tunnel-hotfix.md`.

---

## 7. Pendiente

- **Verificación E2E** con un usuario real de grupo `G-Direccion`/`G-Coordinadores`
  logueado en el portal (infraestructura 100% verificada por curl; falta probar el
  render de la card con login AD real, por no disponer de credenciales válidas).

---

## 8. Referencias

- Runbook del hotfix: `docs/runbooks/sgm-portal-tunnel-hotfix.md`
- Cómo está desplegada la app en la VM: `docs/runbooks/sgm-despliegue-vm111.md`
