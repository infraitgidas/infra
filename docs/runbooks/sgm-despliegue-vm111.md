# Despliegue de SGM-GIDAS en la VM 192.168.1.111

> **Última actualización**: 2026-08-28 (v2 — `frontend_sgm` formalizado en el compose)
> **Rama (repo infra)**: `hotfix/sgm-portal-tunnel`
> Este documento describe **cómo está desplegada** la app SGM-GIDAS en la VM,
> con el estado real verificado. No es una guía de primera vez (para eso está el
> `docker-compose.yml` de la app), sino la fotografía del deploy actual.

## Máquina

| | |
|---|---|
| **IP / alias LAN** | `192.168.1.111` / `sgm.gidas.local` (resuelve en `/etc/hosts` del CT 208 y DNS) |
| **Usuario SSH** | `infra` |
| **Repo de la app** | `/home/infra/gidas` |
| **Compose** | `/home/infra/gidas/docker-compose.yml` + `.env.production` |
| **Stack** | Docker Compose `gidas_prod_*` |

## Puertos y entrada

- **Entrada pública (única)**: el contenedor `gidas_prod_proxy` (nginx)
  publica **`0.0.0.0:8080 -> 8080`** en el host. **Es el único contenedor con
  puerto expuesto** (verificado: `ss -tlnp` solo muestra `0.0.0.0:8080`).
- Los demás contenedores (`frontend`, `frontend_sgm`, `backend`, `db`, `redis`)
  usan el puerto `8080`/`5000`/etc. **solo internos** (red Docker), sin
  publicación al host.

Toda entrada (LAN o portal) pasa primero por el nginx del **proxy**
(`gidas_prod_proxy`), que decide según la ruta.

## Contenedores (estado verificado)

| Contenedor | Imagen | Puerto | Exposed | Rol |
|------------|--------|--------|---------|-----|
| `gidas_prod_proxy` | `nginxinc/nginx-unprivileged:1.27-alpine` | 8080 | **sí → host 8080** | proxy público / router |
| `gidas_prod_frontend` | `gidas-frontend` | 8080 (interno) | no | frontend **LAN** (base `/`) |
| `gidas_prod_frontend_sgm` | `gidas-frontend-sgm` | 8080 (interno) | no | frontend **portal `/sgm-gidas/`** |
| `gidas_prod_backend` | `gidas-backend` | 5000 (interno) | no | API FastAPI |
| `gidas_prod_migrate` | `gidas-migrate` | — | no | migraciones (exit 0) |
| `gidas_prod_db` | `postgres:16.15` | 5432 (interno) | no | PostgreSQL |
| `gidas_prod_redis` | `redis:7.4-alpine` | 6379 (interno) | no | Redis |

### Red Docker `gidas_prod_network` (mapping DNS verificado)

| Alias DNS | Contenedor | IP |
|-----------|-----------|----|
| `frontend` | `gidas_prod_frontend` | 172.18.0.5 |
| `nginx` | `gidas_prod_proxy` | 172.18.0.6 |
| `frontend_sgm` | `gidas_prod_frontend_sgm` | 172.18.0.7 |
| (`backend`, etc.) | `gidas_prod_backend` | 172.18.0.4 |

El proxy referencia a los frontends por estos aliases: `frontend` (LAN) y
`frontend_sgm` (subpath).

## Cómo decide el proxy (nginx `gidas_prod_proxy`)

Config: `/home/infra/gidas/nginx/default.conf`, montado `:ro` en
`/etc/nginx/conf.d/default.conf` del contenedor `gidas_prod_proxy`.

```
8080 (host) ──> gidas_prod_proxy
   ├── location /              →  $frontend_upstream (frontend LAN, base "/")
   ├── location /api/          →  $backend_upstream  (backend)
   ├── location /sgm-gidas/    →  http://frontend_sgm:8080   (prefijo intacto)
   └── location /sgm-gidas/api/→  rewrite ^/sgm-gidas(/.*)$ $1 break + $backend_upstream
```

Es decir, la app se sirve con **dos bases** a la vez, elegidas por el proxy:

1. **LAN** (como siempre): `sgm.gidas.local` en la raíz `/` → `location /` →
   `frontend` (frontend buildado con `base: "/"`). Assets `/assets/...`, API
   `/api/...`. **No se tocó.**
2. **Portal** (nuevo): `/sgm-gidas/` → `location /sgm-gidas/` →
   `frontend_sgm` (frontend buildado con `base: "/sgm-gidas/"`). Assets
   `/sgm-gidas/assets/...`, API `/sgm-gidas/api/...`.

## Los DOS builds del frontend (clave)

La SPA se compila de **dos formas** porque es una SPA de Vite+React (React
Router + llamadas al API en runtime JS): los paths de assets, rutas y fetch se
generan en build time según `VITE_BASE_PATH`. Un único build no puede servir
bien la raíz Y un subpath a la vez.

### `gidas_prod_frontend` (LAN) — base `/`

- Built por `docker-compose.yml` (servicio `frontend`, `Dockerfile` normal).
- Build args: `VITE_BASE_PATH` NO está en `.env.production` → default `/`.
- Archivos: `dist/assets/...` con hrefs `/assets/...`.

### `gidas_prod_frontend_sgm` (portal) — base `/sgm-gidas/`

- **Está formalizado en el `docker-compose.yml`** como servicio `frontend_sgm`
  (desde 2026-08-28). Antes era un `docker run` manual (ver histórico al final).
- Imagen: `gidas-frontend-sgm` (buildado con `frontend/Dockerfile.portal`).
- Build args (hardcodeados en el compose / Dockerfile):
  - `VITE_BASE_PATH=/sgm-gidas/`
  - `VITE_API_BASE_URL=/sgm-gidas/api/v1`
  - `VITE_API_URL=/sgm-gidas/api`
- Sirve con `frontend/nginx.portal.conf`:
  - `location /sgm-gidas/assets/ { alias /usr/share/nginx/html/assets/; ... }`
  - `location /sgm-gidas/ { try_files $uri $uri/ /index.html; }` (SPA fallback)
- El servicio recrea el contenedor vía compose:

```bash
cd /home/infra/gidas
docker compose --env-file .env.production up -d --no-deps frontend_sgm
```

> **Nota de hardening**: el servicio replica el patrón de los demás contenedores
> del stack: `read_only: true` + `tmpfs` (`/var/cache/nginx`, `/var/run`, `/tmp`),
> `cap_drop: ALL`, `security_opt no-new-privileges`, `pids_limit`, `init: true`,
> `mem_limit 256m`, `cpus 0.5`, `restart: unless-stopped`. No expone puerto
> público (solo `expose: "8080"` interno + alias de red `frontend_sgm`).

## Volumen persistente

- `gidas_prod_postgres_data` → datos de PostgreSQL (`db`).

## Archivos relevantes en `/home/infra/gidas`

| Ruta | Qué es |
|------|--------|
| `docker-compose.yml` | define `db, redis, migrate, backend, frontend, nginx` y **`frontend_sgm`** (formalizado) |
| `.env.production` | variables de entorno/compose (no define `VITE_BASE_PATH` → LAN = `/`) |
| `nginx/default.conf` | config del proxy (router LAN + subpath) — modificado para `/sgm-gidas/` |
| `frontend/Dockerfile` | build normal (base `/`) |
| `frontend/Dockerfile.portal` | build del frontend subpath (nuevo) |
| `frontend/nginx.portal.conf` | nginx interno del frontend subpath (nuevo) |
| `backups/sgm-portal-subpath/` | puntos de retorno del hotfix (default.conf, compose, Dockerfile) |

## Verificación rápida del estado

```bash
# ¿Está arriba el stack?
docker ps --filter name=gidas

# ¿Sirve la LAN (raíz)?
curl -sk -o /dev/null -w "%{http_code}\n" -H "Host: sgm.gidas.local" http://127.0.0.1:8080/

# ¿Sirve el subpath (portal)?
curl -sk -o /dev/null -w "%{http_code} %{content_type}\n" http://127.0.0.1:8080/sgm-gidas/
curl -sk -o /dev/null -w "%{http_code} %{content_type}\n" http://127.0.0.1:8080/sgm-gidas/api/v1/health
```

## Referencias

- Runbook del hotfix: `docs/runbooks/sgm-portal-tunnel-hotfix.md`
- Cómo agregar un servicio al portal: `docs/runbooks/howto-add-service-tunnel.md`
- Portal (CT 208): nginx `/etc/nginx/nginx.conf` + `/opt/portal-gidas/config.yaml`

## Histórico (trazabilidad)

- **2026-08-28 (v2)**: el contenedor `gidas_prod_frontend_sgm` se **formalizó**
  en el `docker-compose.yml` como servicio `frontend_sgm` (con la imagen
  `gidas-frontend-sgm` buildada desde `frontend/Dockerfile.portal` y hardening
  igual al resto). Se removió el contenedor manual (`docker run`) y se recreó
  vía compose, quedando **gestiónado por compose** (`compose ps` lo lista).
  Backup previo: `backups/sgm-portal-subpath/docker-compose.presgm.20260828101501.bak`.
- **2026-08-28 (v1)**: el contenedor se creó de forma manual (`docker run`) fuera
  del compose (pendiente de formalizar).
