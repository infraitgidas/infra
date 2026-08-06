# Informe de Avance — GLPI (Gestor ITSM GIDAS)

> **Feature**: Gestor ITSM (Feature #4)
> **Rama**: `feat/herramientas-pendientes`
> **Versión**: GLPI 10.0.26 (imagen oficial `glpi/glpi:10.0`)
> **Fecha**: 2026-08-06
> **Estado**: ✅ OPERATIVO — deployado, DNS, portal y API verificados

---

## 1. Resumen Ejecutivo

Se implementó y **disponibilizó** GLPI como sistema ITSM (incidentes, cambios, problemas) para GIDAS. El deploy en producción requirió una **migración crítica**: el stack original usaba la imagen `diouxx/glpi:10.0.x`, que **no existe** (imagen muerta, último push dic-2024, GLPI 9/php7.4). Se migró a la imagen oficial `glpi/glpi:10.0`, que autoinstala al primer arranque. Durante la puesta a punto se corrigieron **7 bugs**, se configuró el DNS (MikroTik + `/etc/hosts` del portal), la API (verificada E2E con creación de ticket) y el acceso vía portal.

| Componente | Estado | Detalle |
|------------|--------|---------|
| **GLPI** | ✅ Operativo | CT 212, 3 contenedores healthy, HTTPS 200 |
| **API** | ✅ Verificada | App-Token, 2 API clients, ticket id=1 creado |
| **DNS** | ✅ MikroTik | `glpi.gidas.local` → 192.168.1.47 |
| **Portal GIDAS** | ✅ Integrado | Card visible (G-Direccion/G-Coordinadores), proxy server-side 200 |
| **Backup** | ✅ Probado | zstd, dump 795K→94K, retención 30d |
| **LDAP** | 🔴 Pendiente | FreeIPA no existe en la LAN — decidir AD vs FreeIPA |

---

## 2. Infraestructura

```
┌─ CT 212 (pve-desa04 / glpi) ─────────────────────────────┐
│  Rocky Linux 9 — 2 vCPU — 4GB RAM — 20GB — 192.168.1.47  │
│  Docker CE 29.7.1 + Compose v5.4.0 — stack en /opt/glpi  │
│                                                            │
│  ┌─ glpi-mariadb ─┐  ┌─ glpi-app ───────────┐             │
│  │ MariaDB (vol    │  │ GLPI 10.0.26         │             │
│  │  glpi_mariadb_  │  │  /var/glpi (vol       │             │
│  │  data)          │  │  glpi_data)           │             │
│  └────────────────┘  │  plugins+marketplace   │             │
│                      └───────────┬────────────┘             │
│                      ┌───────────▼────────────┐             │
│                      │ glpi-nginx (HTTPS,     │             │
│                      │  cert autofirmado)     │             │
│                      └────────────────────────┘             │
└────────────────────────────────────────────────────────────┘
        │ DNS MikroTik: glpi.gidas.local → .47
        ▼
┌─ CT 208 (pve-desa04 / portal) ────────────────────────────┐
│  Portal FastAPI+LDAP — card GLPI → /proxy/glpi/ → GLPI    │
│  (reverse proxy server-side httpx)                         │
└────────────────────────────────────────────────────────────┘
```

| Recurso | Detalle |
|---------|---------|
| **CT 212** | Rocky Linux 9, 2 vCPU, 4GB RAM, 20GB, IP 192.168.1.47 |
| **Contenedores** | `glpi-mariadb`, `glpi-app`, `glpi-nginx` (nombres fijos, no `-1` sufijo) |
| **Volúmenes** | `glpi_mariadb_data`, `glpi_data` (/var/glpi: config+files+logs), `glpi_plugins`, `glpi_marketplace` |
| **Imagen** | `glpi/glpi:10.0` (oficial, GLPI 10.0.26, autoinstall al primer arranque) |
| **Docker** | CE 29.7.1 + Compose plugin v5.4.0 (instalados previamente) |
| **Certs** | Autofirmados, SAN `DNS:glpi.gidas.local,IP:192.168.1.47` (`scripts/generate-certs.sh`) |
| **DNS** | `glpi.gidas.local` → 192.168.1.47 (MikroTik static, TTL 1d) |

---

## 3. Configuración Core

| Config | Valor | Fuente |
|--------|-------|--------|
| `url_base` | `https://glpi.gidas.local` | Autoinstall (env vars del compose) |
| `language` | `es_AR` | Autoinstall (`GLPI_LANG`) |
| `timezone` | `America/Argentina/Buenos_Aires` | Autoinstall (`GLPI_TIMEZONE`) |
| `enable_api` | `1` | Autoinstall |
| `enable_api_login_credentials` | `1` | Autoinstall |
| Admin password | bcrypt vía UPDATE SQL | `install-glpi.sh` (GLPI 10 no tiene CLI) |

> **Nota**: la autoinstall de la imagen oficial setea estas configs desde las
> env vars del compose (`.env` real). El comando `glpi:config:set` del script
> era de GLPI 11 y fallaba en silencio — corregido a `config:set`.

---

## 4. Acceso y Autenticación

| Aspecto | Configuración |
|---------|--------------|
| **HTTPS** | `https://glpi.gidas.local` (cert autofirmado — warning en navegador) |
| **HTTP→HTTPS** | 301 (nginx) |
| **Admin** | `glpi` / password en `secrets/glpi.yaml` (bcrypt aplicado por SQL) |
| **LDAP** | 🔴 PENDIENTE — ver sección 10 |

### API REST

| Item | Valor |
|------|-------|
| **Endpoint** | `https://glpi.gidas.local/apirest.php` |
| **App-Token** | `secrets/glpi.yaml` (se guarda ENCRIPTADO en la DB — ver Bug #4) |
| **Client `gidas-lan`** | IP range 192.168.1.0–192.168.1.255 (id=4) |
| **Client `gidas-docker`** | IP range 172.18.0.0–172.18.0.255 (id=5) |
| **Client preexistente** | 127.0.0.1 localhost (id=1) |

**Flujo verificado E2E**: `initSession` (App-Token + JSON body) → session_token (len 128) → `createTicket` → **ticket id=1 creado** → `killSession` (requiere header App-Token, 400 sin él — comportamiento esperado).

---

## 5. Integración Portal GIDAS

GLPI ya estaba pre-configurado en `portal-gidas/config.yaml` (desde el SDD):

```yaml
- name: "GLPI"
  url: "http://glpi.gidas.local"
  icon: "fas fa-life-ring"
  description: "ITSM - Mesa de ayuda"
  proxy: true
  groups:
    - "G-Direccion"
    - "G-Coordinadores"
```

> **Importante**: el portal hace **reverse proxy server-side** (`httpx`, `verify=False`)
> en `/proxy/glpi/` — por eso el CT 208 necesita resolver `glpi.gidas.local`
> desde sí mismo (vía `/etc/hosts`, corregido de `.45` a `.47`), no desde el
> navegador del usuario. Verificado: conexión interna 200 (login page GLPI).

---

## 6. Backup y Cron

| Item | Valor |
|------|-------|
| **Cron GLPI** | `*/5 * * * * docker exec glpi-app php /var/www/glpi/front/cron.php` (instalado) |
| **Cron backup** | `0 3 * * 0 /opt/glpi/scripts/backup.sh` dom 03:00 (instalado) |
| **Backup probado** | ✅ SUCCESS 2026-08-06: `glpi-database.sql.zst` (94K) + volúmenes + MANIFEST |
| **Destino** | `/var/backups/glpi/<timestamp>/` |
| **Retención** | 30 días |
| **zstd** | Instalado en CT 212 (requisito del backup) |

---

## 7. Bugs Corregidos

### Bug #1: Imagen `diouxx/glpi:10.0.x` inexistente (CRÍTICO)
- **Causa**: el tag no existe (imagen muerta, dic-2024, GLPI 9/php7.4, solo 8 tags)
- **Fix**: migración a imagen oficial `glpi/glpi:10.0` — `GLPI_DB_*` env vars, volumen único `glpi_data:/var/glpi`, autoinstall, nombres de contenedores fijos

### Bug #2: nginx sin certificados (CRÍTICO)
- **Causa**: `[emerg] cannot load certificate /etc/nginx/certs/glpi.crt` — no existían certs
- **Fix**: `scripts/generate-certs.sh` (autofirmado SAN DNS+IP) + bind mount `certs/` (gitignored)

### Bug #3: Comandos CLI de GLPI 11 en doc/scripts
- **Causa**: `glpi:security:change_password`, `glpi:ldap:list`, `glpi:config:set`, `glpi:ldap:synchronize`, `glpi:ldap:add` no existen en GLPI 10
- **Fix**: password por SQL bcrypt; sync por `ldap:synchronize_users`; config por `config:set`; directorio LDAP solo por Web UI

### Bug #4: App-Token encriptado en la DB (API)
- **Causa**: `glpi_apiclients.app_token` se guarda ENCRIPTADO con GLPIKey interno (`src/APIClient.php:247`); insert por SQL con plaintext → `ERROR_WRONG_APP_TOKEN_PARAMETER` / "Unable to decrypt string"
- **Fix**: crear los clients vía clase global `APIClient::add()` con el token en claro; rangos IP como STRING (la clase hace `ip2long`)
- **Gotcha extra**: sin client para la IP del request → `ERROR_NOT_ALLOWED_IP` (GLPI ve la IP de nginx 172.18.0.4)

### Bug #5: `00-env.sh` sin credenciales reales
- **Causa**: usaba defaults (`glpi_password`) — no cargaba el `.env`; el backup hacía dump de **0 bytes**
- **Fix**: carga `.env` si existe + mapeo `GLPI_DB_*` → `MYSQL_*` (nomenclatura de la imagen oficial)

### Bug #6: zstd ausente
- **Causa**: el CT no tenía `zstd` → el dump quedaba sin comprimir (y `restore.sh` espera `.sql.zst`)
- **Fix**: `dnf install -y zstd`

### Bug #7: backup dejaba `.sql` de 0 bytes en error
- **Causa**: el `else` del dump no borraba el archivo fallido
- **Fix**: `rm -f "${DB_FILE}"` en el error path

---

## 8. Archivos del Proyecto

| Archivo | Propósito |
|---------|-----------|
| `itsm/docker-compose.yml` | Stack Docker (glpi + mariadb + nginx, imagen oficial) |
| `itsm/00-env.sh` | Env para scripts (carga `.env`, mapeo GLPI_DB_* → MYSQL_*) |
| `itsm/.env.example` | Template de variables (secrets NO van al repo) |
| `itsm/scripts/install-glpi.sh` | Setup inicial (wait healthy, admin password, API) |
| `itsm/scripts/backup.sh` | Backup DB + volúmenes (zstd, retención 30d) |
| `itsm/scripts/restore.sh` | Restore de backup |
| `itsm/scripts/sync-ldap.sh` | Sync LDAP (pendiente de directorio) |
| `itsm/scripts/verify.sh` | Verificación del stack |
| `itsm/scripts/generate-certs.sh` | Certs autofirmados (SAN glpi.gidas.local + IP) |
| `itsm/scripts/webhook-redmine.sh` / `webhook-gitlab.sh` | Integraciones (tokens PENDIENTE) |
| `itsm/nginx/default.conf` | nginx (server_name hardcodeado `glpi.gidas.local`) |
| `itsm/docs/post-deploy-config.md` | Config post-deploy (actualizado a GLPI 10) |
| `docs/runbooks/howto-add-service-tunnel.md` | Runbook portal/tunnel |
| `docs/herramientas-pendientes.md` | Inventario de herramientas pendientes (GLPI ✅) |
| `openspec/changes/itsm/` | SDD completo (proposal, design, tasks, informe-cambios) |

---

## 9. Commits (rama `feat/herramientas-pendientes`)

| Commit | Contenido |
|--------|-----------|
| `38c1554` | docs(herramientas-pendientes): inventario inicial |
| `80a20d8` | chore(security): secrets/glpi.yaml con credenciales (SOPS) |
| `114b81b` | refactor(itsm): migrar stack a imagen oficial glpi/glpi:10.0 |
| `5db1af3` | fix(itsm): certs autofirmados para nginx y comandos GLPI 10 |
| `5c854b9` | docs(herramientas-pendientes): GLPI operativo — CT 212, DNS MikroTik y portal |
| `f7a7365` | fix(itsm): credenciales reales en 00-env.sh, comando config:set y backup con zstd |

---

## 10. Tareas Pendientes

| Prioridad | Tarea | Estado |
|-----------|-------|--------|
| 🔴 Alta | **LDAP**: decidir directorio — FreeIPA (`ipa.gidas.local`) **no existe en la LAN**; la infra usa AD GDC01 (192.168.1.117, mismo que el portal). Bind password en `PENDIENTE_bind_pass` | ⏳ |
| 🔴 Alta | **SMTP**: `mail.gidas.local` no existe — decidir servidor de correo (no setear SMTP inexistente) | ⏳ |
| 🔴 Alta | **Integraciones Redmine/GitLab**: tokens en `PENDIENTE` en `secrets/glpi.yaml`; webhooks ya escritos | ⏳ |
| 🟡 Media | Probar login real con usuario AD (G-Direccion/G-Coordinadores) desde el navegador | ⏳ |
| 🟡 Media | Plugins (Form Creator opcional — marketplace vacío) | ⏳ |
| 🟢 Baja | NetBox en `/etc/hosts` del CT 208 apunta a `.45` (LibreNMS) — corregir al desplegar NetBox | ⏳ |

---

*Última actualización: 2026-08-06*
