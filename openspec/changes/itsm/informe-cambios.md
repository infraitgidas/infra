# Informe de Cambios — GLPI (Gestor ITSM)

**Feature branch**: `feat/herramientas-pendientes`
**Versión**: GLPI 10.0.26 (imagen oficial `glpi/glpi:10.0`)
**Fecha**: 2026-08-06 (v1 — deploy completado; fase de verificación parcial)
**Estado**: 🟡 OPERATIVO — deployado en CT 212, DNS + portal + API verificados; pendientes LDAP/SMTP/integraciones

---

## 1. Resumen Ejecutivo

El change `itsm` (4 specs SDD: `itsm-core`, `itsm-ldap-auth`, `itsm-backup`, `itsm-integrations`; 18 tareas en 6 fases) pasó de "implementado en repo" a **disponibilizado en producción**. El paso a producción expuso **7 bugs** que se corrigieron en el camino, el más crítico: la imagen `diouxx/glpi:10.0.x` que usaba el stack original **no existe** (imagen muerta, dic-2024, GLPI 9/php7.4), lo que obligó a migrar a la imagen oficial `glpi/glpi:10.0` con cambios de nomenclatura (`GLPI_DB_*`), almacenamiento (volumen único `glpi_data:/var/glpi`) y comandos CLI (varios `glpi:*` del doc eran de GLPI 11).

| Concepto | Valor |
|----------|-------|
| **Versión** | GLPI 10.0.26 (Docker, imagen oficial `glpi/glpi:10.0`) |
| **CT** | 212 — Rocky Linux 9 — 2 vCPU — 4GB RAM — 20GB |
| **IP** | 192.168.1.47/24 |
| **DNS** | `glpi.gidas.local` (MikroTik static + `/etc/hosts` CT 208) |
| **DB** | MariaDB (Docker, volumen `glpi_mariadb_data`) |
| **Datos GLPI** | Volumen `glpi_data` (`/var/glpi`: config + files + logs) |
| **HTTPS** | Cert autofirmado SAN `DNS:glpi.gidas.local,IP:192.168.1.47` |
| **API** | App-Token (SOPS), 2 API clients por IP range, ticket id=1 creado |
| **Portal** | `/proxy/glpi/` reverse proxy server-side (httpx), 200 OK |
| **Backup** | `backup.sh` + zstd → SUCCESS; cron dom 03:00; retención 30d |

---

## 2. Infraestructura Actual

| Recurso | Detalle |
|---------|---------|
| **CT 212** | Rocky Linux 9, 2 vCPU, 4GB RAM, 20GB, IP 192.168.1.47 |
| **Docker** | CE 29.7.1 + Compose plugin v5.4.0 |
| **Contenedores** | `glpi-mariadb`, `glpi-app`, `glpi-nginx` (nombres fijos, healthy) |
| **Imagen** | `glpi/glpi:10.0` — autoinstall al primer arranque (`GLPI_SKIP_AUTOINSTALL=false`) |
| **Volúmenes** | `glpi_mariadb_data`, `glpi_data` (/var/glpi), `glpi_plugins`, `glpi_marketplace` |
| **Config core** | `url_base=https://glpi.gidas.local`, `language=es_AR`, `timezone=America/Argentina/Buenos_Aires`, `enable_api=1` |
| **Certs** | Autogenerados por `scripts/generate-certs.sh` (gitignored en `certs/.gitignore`) |
| **nginx** | `server_name glpi.gidas.local` hardcodeado (nginx no interpola `${}` en conf estática); 301 http→https |

### Diagrama

```
┌─ CT 212 (Rocky 9, 192.168.1.47) ──────────────────────────┐
│  /opt/glpi (docker compose)                                │
│   glpi-mariadb ─ glpi-app (GLPI 10.0.26, /var/glpi)        │
│        │                │                                  │
│        └────────────────┼─ glpi-nginx (HTTPS 443)          │
│                          │                                  │
│  DNS MikroTik: glpi.gidas.local → 192.168.1.47             │
└────────────────────────────────────────────────────────────┘
```

---

## 3. Decisión de Arquitectura: Migración a Imagen Oficial

**Contexto**: el stack original (SDD) usaba `diouxx/glpi:10.0.x`. Al verificar en Docker Hub se confirmó que ese tag **no existe** — la imagen está abandonada (último push dic-2024, GLPI 9.x/php7.4, solo 8 tags). Deployar eso habría dado una GLPI vieja e insegura.

**Decisión**: migrar a `glpi/glpi:10.0` (imagen oficial). Cambios asociados:

| Aspecto | Antes (diouxx / planificado) | Después (oficial) |
|---------|------------------------------|-------------------|
| Env vars | `MARIADB_*` | `GLPI_DB_*` |
| Datos | `/var/www/html/glpi/{config,files}` | `glpi_data:/var/glpi` (volumen único) |
| Instalación | Manual con `install/install.php` | Autoinstall al primer arranque |
| Contenedores | `${COMPOSE_PROJECT_NAME}-...-1` | Nombres fijos `glpi-{mariadb,app,nginx}` |
| Volúmenes | `glpi_config`, `glpi_documents` | `glpi_data`, `glpi_plugins`, `glpi_marketplace` |

**Tradeoffs**: la imagen oficial es más simple (un volumen de datos) pero cambia rutas y comandos; la autoinstall tarda ~3 min y el healthcheck se agota en `start_period` (unhealthy transitorio) — hay que re-`docker compose up -d` tras healthy, comportamiento ya incorporado en `install-glpi.sh`.

---

## 4. Bugs Críticos Corregidos

### Bug #1 — Imagen `diouxx/glpi:10.0.x` inexistente (CRÍTICO)

**Severidad**: 🔴 ALTA — el stack no podía deployarse con la versión planificada

**Causa raíz**: la imagen está abandonada; el tag 10.0.x no existe (solo GLPI 9.x/php7.4, 8 tags, último push dic-2024).

**Fix**: migración a `glpi/glpi:10.0` (ver sección 3). Commit `114b81b`.

---

### Bug #2 — nginx sin certificados (CRÍTICO)

**Severidad**: 🔴 ALTA — nginx no arrancaba

**Síntoma**: `[emerg] cannot load certificate /etc/nginx/certs/glpi.crt` — el compose montaba `certs/` pero el directorio estaba vacío (los certs se iban a generar en deploy y no se generaron).

**Fix**: `scripts/generate-certs.sh` (openssl autofirmado con SAN `DNS:glpi.gidas.local,IP:192.168.1.47`), bind mount de `certs/` en el compose, y `certs/.gitignore` (`.crt`/`.key` NUNCA se versionan — repo público). Commit `5db1af3`.

---

### Bug #3 — Comandos CLI de GLPI 11 en doc/scripts (ALTO)

**Severidad**: 🟡 MEDIA — fallos silenciosos

**Causa raíz**: el doc post-deploy y los scripts usaban comandos de GLPI 11 que **no existen en GLPI 10**:

| Comando (GLPI 11) | Real en GLPI 10 |
|-------------------|-----------------|
| `glpi:security:change_password` | No hay CLI → UPDATE SQL bcrypt en `glpi_users` |
| `glpi:ldap:list` / `glpi:ldap:add` | No existen → directorio solo por Web UI (`Configuration > Authentication > LDAP`) |
| `glpi:config:set` | `config:set` |
| `glpi:ldap:synchronize --all` | `ldap:synchronize_users --all` (alias `ldap:sync`) |
| `glpi:system:status` | ✅ existe (usado para esperar autoinstall) |

Además, `install-glpi.sh` usaba `glpi:config:set` con `|| echo WARNING` — fallaba en silencio. Las configs igual quedaron bien porque la **autoinstall de la imagen oficial** las setea desde las env vars del compose. Corregido a `config:set`. Commits `5db1af3`, `f7a7365`.

---

### Bug #4 — App-Token encriptado en la DB (API) (ALTO)

**Severidad**: 🔴 ALTA — la API rechazaba el token

**Síntoma**: `ERROR_WRONG_APP_TOKEN_PARAMETER` + "Unable to decrypt string" al usar el App-Token insertado por SQL.

**Causa raíz**: GLPI guarda `glpi_apiclients.app_token` **ENCRIPTADO** con la clave interna GLPIKey (`src/APIClient.php:247`, `prepareInputForAdd` → `(new GLPIKey())->encrypt(...)`). Un insert directo con plaintext deja un valor que la app no puede desencriptar.

**Fix**: crear los API clients vía la clase global `APIClient::add([... app_token en claro ...])` desde un `docker exec` con PHP — la clase encripta correctamente. Los **rangos IP se pasan como STRING** (la clase hace `ip2long` en `prepareInputForUpdate`; pasar ints deja NULL).

**Gotcha extra**: sin un client cuyo rango cubra la IP del request → `ERROR_NOT_ALLOWED_IP` (GLPI ve `172.18.0.4` = IP del contenedor nginx). Se crearon:
- `gidas-lan` (id=4): 192.168.1.0–192.168.1.255
- `gidas-docker` (id=5): 172.18.0.0–172.18.0.255
- (id=1 preexistente: 127.0.0.1)

---

### Bug #5 — `00-env.sh` sin credenciales reales (ALTO)

**Severidad**: 🔴 ALTA — backup roto

**Síntoma**: `backup.sh` generaba `glpi-database.sql` de **0 bytes** (Status PARTIAL).

**Causa raíz**: `00-env.sh` usaba defaults (`glpi_password`) — no cargaba el `.env` del compose (donde viven las credenciales reales de SOPS). El desajuste vino de la migración a imagen oficial: el `.env` usa `GLPI_DB_*` y el script esperaba `MYSQL_*`.

**Fix**: `00-env.sh` carga el `.env` si existe + mapeo `MYSQL_*` ← `GLPI_DB_*` (con fallback a defaults de desarrollo). Commit `f7a7365`.

---

### Bug #6 — zstd ausente en el CT (MEDIO)

**Causa raíz**: `backup.sh` comprime con `zstd` (y `restore.sh` descomprime `.sql.zst`) pero el CT no tenía el paquete. El fallo del `zstd` en `cmd && rm` **no disparaba `set -e`** (no es el último comando de la lista) → el dump quedaba sin comprimir silenciosamente.

**Fix**: `dnf install -y zstd` (1.5.5). Backup re-probado: 795K → 94K `.sql.zst`, SUCCESS.

---

### Bug #7 — backup dejaba dump de 0 bytes en error (BAJO)

**Causa raíz**: el `else` del dump fallido no limpiaba el archivo (el `>` ya lo había creado).

**Fix**: `rm -f "${DB_FILE}"` en el error path. Commit `f7a7365`.

---

## 5. Verificación

| Criterio | Resultado |
|----------|-----------|
| Stack healthy | ✅ 3 contenedores up/healthy (`glpi-mariadb`, `glpi-app`, `glpi-nginx`) |
| HTTPS | ✅ `https://glpi.gidas.local` → 200 (login page) |
| HTTP→HTTPS | ✅ 301 |
| DNS MikroTik | ✅ `dig @192.168.1.1 glpi.gidas.local` → 192.168.1.47 |
| `/etc/hosts` CT 208 | ✅ corregido `.45` → `.47` (proxy del portal) |
| Proxy portal `/proxy/glpi/` | ✅ sin sesión → 302 `/login`; conexión server-side → 200 |
| API `initSession` | ✅ session_token (len 128) con App-Token + body JSON |
| API `createTicket` | ✅ **ticket id=1 creado** |
| API `killSession` | ✅ (400 solo si falta header App-Token — esperado) |
| Backup | ✅ SUCCESS con zstd (dump 795K → 94K + volúmenes + MANIFEST) |
| Crons CT 212 | ✅ `front/cron.php` cada 5 min + backup dom 03:00 |
| Configs core | ✅ `url_base`, `es_AR`, tz, `enable_api=1` (autoinstall) |

---

## 6. Integración con Portal GIDAS

GLPI ya estaba en `portal-gidas/config.yaml` (G-Direccion/G-Coordinadores, `proxy: true`) — solo faltaba que el CT 208 resolviera el hostname.

**Descubrimiento clave**: el portal no es un dashboard pasivo — hace **reverse proxy server-side** (`app/routers/proxy.py`, `httpx.AsyncClient(verify=False)`, reescribe redirects internos a `/proxy/<tool>/`). Por eso el CT 208 debe resolver `glpi.gidas.local` él mismo; su único nameserver es el DC (`.117`, sin zona `gidas.local`) → se resolvió con `/etc/hosts` (patrón existente en el CT para "Proxied tools").

**Nota**: el `/etc/hosts` del CT 208 también tiene `netbox.gidas.local → 192.168.1.45` (apunta a LibreNMS, incorrecto) — corregir cuando NetBox se despliegue.

---

## 7. Scripts y Archivos

| Archivo | Propósito | Cambio |
|---------|-----------|--------|
| `itsm/docker-compose.yml` | Stack Docker (imagen oficial) | Migrado |
| `itsm/00-env.sh` | Env para scripts | Carga `.env` + mapeo GLPI_DB_* |
| `itsm/scripts/install-glpi.sh` | Setup inicial | `config:set` (GLPI 10), espera autoinstall |
| `itsm/scripts/backup.sh` | Backup DB + volúmenes | Fix dump 0 bytes |
| `itsm/scripts/restore.sh` | Restore | Sin cambios |
| `itsm/scripts/generate-certs.sh` | Certs autofirmados | Nuevo |
| `itsm/scripts/verify.sh` | Verificación | Sin cambios |
| `itsm/scripts/webhook-{redmine,gitlab}.sh` | Integraciones | Sin cambios (tokens PENDIENTE) |
| `itsm/nginx/default.conf` | nginx | `server_name` hardcodeado |
| `itsm/docs/post-deploy-config.md` | Config post-deploy | Actualizado a GLPI 10 |
| `secrets/glpi.yaml` | Credenciales (SOPS) | Nuevo |
| `docs/herramientas-pendientes.md` | Inventario | GLPI ✅ |
| `docs/itsm/avance.md` | Informe de avance | Nuevo |
| `docs/runbooks/howto-add-service-tunnel.md` | Runbook portal | Referencia |

---

## 8. Trabajo Futuro

| Prioridad | Tarea | Estado |
|-----------|-------|--------|
| 🔴 Alta | **LDAP**: FreeIPA (`ipa.gidas.local`) no existe en la LAN → decidir: AD GDC01 (patrón portal) o desplegar FreeIPA. Bind password `PENDIENTE_bind_pass` | ⏳ |
| 🔴 Alta | **SMTP**: `mail.gidas.local` no existe → decidir servidor de correo | ⏳ |
| 🔴 Alta | **Integraciones**: tokens Redmine/GitLab `PENDIENTE` en secrets | ⏳ |
| 🟡 Media | Login real con usuario AD desde navegador (G-Direccion/G-Coordinadores) | ⏳ |
| 🟡 Media | Cron LDAP sync (agregar al crontab cuando exista directorio) | ⏳ |
| 🟡 Media | Plugins opcionales (Form Creator, marketplace vacío) | ⏳ |
| 🟢 Baja | Merge `feat/herramientas-pendientes` → `main` cuando NetBox/Ansible se resuelvan | ⏳ |
