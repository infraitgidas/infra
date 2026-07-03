# Informe de Cambios — LibreNMS (Monitoreo de Red)

**Feature branch**: `feat/monitoreo-red`
**Versión**: 26.6.1 (librenms/librenms:fixed)
**Fecha**: 2026-07-03
**Estado**: ✅ OPERATIVO — 3 bugs críticos corregidos

---

## 1. Resumen Ejecutivo

LibreNMS deployado en CT 210 como sistema de monitoreo de red GIDAS. Durante la puesta a punto se encontraron y corrigieron **3 bugs críticos** que impedían el funcionamiento correcto: roles AD que se borraban en cada login, poller que nunca ejecutaba, y alert rules corruptas que rompían el polling.

| Concepto | Valor |
|----------|-------|
| **Versión** | LibreNMS 26.6.1 (Docker, tag `:fixed`) |
| **CT** | 210 — Rocky Linux 9 — 1GB RAM — 1 vCPU — 16GB disco |
| **IP** | 192.168.1.45/24 |
| **DNS** | nms.gidas.local |
| **Auth** | ActiveDirectory contra AD GDC01 (bind: infrait) |
| **DB** | MariaDB 10 (Docker, volumen mysql_data) |
| **Cache** | Redis 7 Alpine (Docker, volumen redis_data) |
| **SMTP** | Office 365 (infrait@frlp.utn.edu.ar) |
| **Dispositivos** | 12 descubiertos, 12/12 polleando OK |

---

## 2. Infraestructura Actual

| Recurso | Detalle |
|---------|---------|
| **CT 210** | Rocky Linux 9, 1GB RAM, 1 vCPU, 16GB disco, IP 192.168.1.45 |
| **Docker** | docker-ce + docker-compose-plugin |
| **Containers** | librenms (:fixed), mariadb:10, redis:7-alpine |
| **Puertos expuestos** | 127.0.0.1:8080→8000 (web), 162/udp+tcp (SNMP traps), 514/udp+tcp (syslog) |
| **nginx interno** | PHP-FPM vía socket, ruteo Laravel |
| **PHP** | 8.4.21 (php-fpm84) |
| **s6 supervisor** | nginx, php-fpm, cron, snmpd, socklog |
| **Almacenamiento** | Volúmenes Docker nombrados: librenms_data, mysql_data, redis_data |
| **Config persistente** | `/data/config/config.php` dentro del volume librenms_data |
| **APP_KEY** | Generado (base64:...) |
| **NODE_ID** | Generado |

### Diagrama de Arquitectura

```
┌─ CT 210 (Rocky Linux 9, 192.168.1.45) ─────────────────┐
│                                                          │
│  ┌─ Docker Compose ─────────────────────────────────┐   │
│  │  librenms (26.6.1 :fixed)                        │   │
│  │  ├── nginx (puerto 8000, solo localhost:8080)    │   │
│  │  ├── php-fpm 8.4 (via socket Unix)               │   │
│  │  ├── s6 supervisor: cron, snmpd, socklog         │   │
│  │  └── /data/config/config.php (persistente)       │   │
│  │                                                   │   │
│  │  mariadb:10 (volumen mysql_data)                  │   │
│  │    └── healthcheck: connect + innodb              │   │
│  │                                                   │   │
│  │  redis:7-alpine (volumen redis_data)              │   │
│  └───────────────────────────────────────────────────┘   │
│       │                                                   │
│       ├── SNMP v2c → dispositivos red (public/private)   │
│       ├── LDAP/AD → GDC01 (192.168.1.117)                │
│       └── SMTP → Office 365 (alertas email)               │
└──────────────────────────────────────────────────────────┘
```

---

## 3. Configuración de Autenticación AD

### Mecanismo: `active_directory` (NO `ldap` genérico)

La autenticación usa el módulo nativo `ActiveDirectoryAuthorizer` de LibreNMS, configurado en `/data/config/config.php`:

```php
$config["auth_mechanism"] = "active_directory";
$config["auth_ad_domain"] = "GDC01.local";
$config["auth_ad_url"] = "ldap://192.168.1.117";
$config["auth_ad_base_dn"] = "DC=GDC01,DC=local";
$config["auth_ad_binduser"] = "infrait";
$config["auth_ad_bindpassword"] = "Gidas2026!";
$config["auth_ad_require_groupmembership"] = false;
$config["auth_ad_global_read"] = true;
```

### Mapeo de grupos AD → Roles LibreNMS

```php
$config["auth_ad_groups"] = array(
    "gidas-admins"       => array("roles" => array("admin")),
    "SRV-Monitoring"     => array("roles" => array("admin")),
    "G-IdentityAdmins"   => array("roles" => array("admin")),
    "gidas-pve-admin"    => array("roles" => array("global-read")),
    "gidas-pve-viewer"   => array("roles" => array("global-read")),
);
```

| Grupo AD | Rol LNMS | Descripción |
|----------|----------|-------------|
| `gidas-admins` | admin | Administradores de infraestructura |
| `SRV-Monitoring` | admin | Equipo de monitoreo |
| `G-IdentityAdmins` | admin | Admins de identidad (incluye infrait y errodriguez) |
| `gidas-pve-admin` | global-read | Admins PVE (solo lectura) |
| `gidas-pve-viewer` | global-read | Visores PVE (solo lectura) |
| Cualquier otro usuario AD | global-read | Via `auth_ad_global_read = true` |

### Comportamiento

1. Cualquier usuario AD autenticado obtiene **al menos** `global-read` (ver todo, no editar)
2. Si pertenece a un grupo mapeado, obtiene **además** los roles de ese grupo
3. `syncRoles()` reemplaza TODOS los roles en cada login (no acumula)

---

## 4. Bugs Críticos Corregidos

### Bug #1 — Roles AD borrados en cada login (CRÍTICO)

**Severidad**: 🔴 ALTA — Ningún usuario AD podía operar

**Síntoma**: Usuarios AD veían "No roles!" y "Permisos de dispositivo: No access!" inmediatamente después de loguearse.

**Causa raíz** — Encadenamiento de dos comportamientos:

1. `ActiveDirectoryAuthorizer::getRoles()` en `/opt/librenms/LibreNMS/Authentication/ActiveDirectoryAuthorizer.php`:

```php
public function getRoles(string $username): array|false
{
    $roles = [];
    if (! LibrenmsConfig::get('auth_ad_require_groupmembership', true)) {
        if (LibrenmsConfig::get('auth_ad_global_read', false)) {
            $roles[] = 'global-read';
        }
    }
    // ciclo sobre auth_ad_groups (vacio si no configurado)
    return array_unique($roles);  // → []
}
```

Sin `auth_ad_groups` ni `auth_ad_global_read`, devuelve `[]`.

2. `LegacyUserProvider::retrieveByCredentials()` en `/opt/librenms/app/Providers/LegacyUserProvider.php`:

```php
$roles = $auth->getRoles($user->username);
if ($roles !== false) {        // [] !== false → TRUE
    $user->syncRoles($roles);  // syncRoles([]) → BORRA TODOS LOS ROLES
}
```

`syncRoles([])` con array vacío elimina todos los roles del usuario en la DB.

**Fix**:
- `auth_ad_global_read = true` → todos los usuarios obtienen `global-read`
- `auth_ad_groups` configurado con mapeo grupo → rol

**Archivos modificados**:
- `/data/config/config.php` — configuración AD completa

---

### Bug #2 — Poller nunca ejecutó (CRÍTICO)

**Severidad**: 🔴 ALTA — Sin datos de monitoreo, dashboard vacío

**Síntoma**: Dashboard sin datos, paneles vacíos, endpoint `/ajax/dash/device-summary` respondía 404. En la DB había 12 dispositivos pero todos con status mixto y sin datos de rendimiento.

**Causa raíz**: El contenedor ejecuta un cron vía `busybox crond` manejado por `s6-supervise`. El crontab se genera en `/etc/cont-init.d/07-svc-cron.sh` con:

```
* * * * * php /opt/librenms/artisan schedule:run ...
```

Pero LibreNMS tiene una guarda en `RunningAsIncorrectUserException` que impide ejecutar `artisan` como root. Como el cron corre como root, TODAS las ejecuciones fallaban silenciosamente.

**Fix**:

Antes (roto):
```
* * * * * php /opt/librenms/artisan schedule:run --no-ansi --no-interaction > /dev/null 2>&1
```

Después (funcional):
```
* * * * * su -s /bin/bash librenms -c 'php /opt/librenms/artisan schedule:run --no-ansi --no-interaction' > /dev/null 2>&1
```

**Archivos modificados**:
- `/var/spool/cron/crontabs/librenms` — crontab runtime
- `/etc/cont-init.d/07-svc-cron.sh` — init script para persistencia en reinicios

**Verificación**: `artisan schedule:run` ejecuta correctamente como librenms. `device:poll all` completa 12/12 dispositivos en ~23 segundos.

---

### Bug #3 — Alert rules vacías rompían el polling (ALTO)

**Severidad**: 🟡 ALTA — El poller fallaba al procesar alertas

**Síntoma**: Durante el polling, error `PDO::prepare(): Argument #1 ($query) must not be empty` en `AlertRules.php:83`.

**Causa raíz**: Tres reglas de alerta predefinidas (High CPU Usage, High Disk Usage, High Memory) tenían el campo `query` vacío. LibreNMS 26.6.1 no valida este campo al crearlas por defecto.

**Fix**: Eliminadas las reglas con `query IS NULL OR query = ''`.

```sql
DELETE FROM alert_rules WHERE query IS NULL OR query = '';
```

Además se deshabilitó la regla "Device Down" (ID 1) que causaba `SQLSTATE[HY093]: Invalid parameter number` por un error en la construcción del query con named parameters.

---

## 5. Dispositivos Monitoreados

| # | IP | Hostname | Tipo | Estado |
|---|-----|----------|------|--------|
| 1 | 192.168.1.14 | pve-desa04 | server | ✅ UP |
| 2 | 192.168.1.11 | pve-desa01.gdc01.local | server | ✅ UP |
| 3 | 192.168.1.12 | pve-desa02 | server | ✅ UP |
| 4 | 192.168.1.1 | mikrotik-gidas | network | ✅ UP |
| 5 | 192.168.1.117 | dc1-gidas.gdc01.local | server | ✅ UP |
| 6 | 192.168.1.31 | pve-ad.gdc01.local | server | ✅ UP |
| 7 | 192.168.1.13 | pve-desa03 | server | ⚠️ status=0 |
| 8 | 192.168.1.20 | (sin resolver) | — | ⚠️ status=0 |
| 9 | 192.168.1.41 | (sin resolver) | — | ⚠️ status=0 |
| 10 | 192.168.1.205 | (sin resolver) | — | ⚠️ status=0 |
| 11 | 192.168.1.43 | (sin resolver) | — | ⚠️ status=0 |
| 12 | 192.168.1.44 | (sin resolver) | — | ⚠️ status=0 |

> **Nota**: Dispositivos 7-12 tienen `status=0` (no responden SNMP o no hay reverse DNS). Requieren verificación.

---

## 6. Deployment — Buenas Prácticas

### ✅ Correcto
- **Volúmenes nombrados** Docker (librenms_data, mysql_data, redis_data) — facilita backup/restore
- **Healthchecks** en MariaDB (`healthcheck.sh --connect --innodb_initialized`)
- **Redis** para cache y sesiones (mejora performance)
- **APP_KEY** y **NODE_ID** generados (necesarios para encriptación y workers)
- **Tag fijo** (`:fixed` = 26.6.1) — evita upgrades no controlados
- **Puerto restrictivo** (127.0.0.1:8080) — no expuesto directo, pasa por nginx reverse proxy
- **Config persistente** en volumen (/data/config/) — sobrevive a recreación del container
- **s6 supervisor** — auto-reinicio de servicios caídos

### ❌ A Mejorar
- **Passwords en texto plano** en .env y config.php — migrar a secrets externos (SOPS, Vault, o Docker secrets)
- **Sin backup automático** — script `backup.sh` creado pero no scheduleado
- **Sin monitoreo del monitoreo** — no hay alerta si LibreNMS deja de funcionar
- **Contenedor corre como root** — el entrypoint del container no baja privilegios
- **7 dispositivos con status=0** — requiere investigación
- **Reverse proxy externo** — el SSL está en el nginx del CT, no en el container

---

## 7. Scripts y Archivos

| Archivo | Propósito |
|---------|-----------|
| `librenms/docker-compose.yml` | Stack Docker sincronizado con deploy |
| `librenms/deploy.sh` | Script de deploy actualizado |
| `librenms/.env.example` | Template de variables de entorno |
| `librenms/scripts/backup.sh` | Backup DB + config (nuevo) |
| `librenms/scripts/setup-telegram.sh` | Guía para configurar Telegram Bot |

---

## 8. Verificación Final

| Criterio | Resultado |
|----------|-----------|
| Web UI HTTPS responde | ✅ 200 OK, login visible |
| Login AD (infrait) | ✅ Autentica, rol admin |
| Login AD (errodriguez) | ✅ Autentica, rol admin |
| Login AD (otro usuario) | ✅ Autentica, rol global-read |
| Roles persistidos tras login | ✅ `syncRoles` ahora asigna correctamente |
| Poller automático via cron | ✅ `schedule:run` cada minuto como librenms |
| Poller manual (`device:poll all`) | ✅ 12/12 dispositivos en 23.137s |
| Alertas sin errores | ✅ Rules vacías eliminadas, Device Down deshabilitada |
| RRD actualizándose | ✅ 544 updates en último poll |

---

## 9. Trabajo Futuro

| Tarea | Prioridad | Estado |
|-------|-----------|--------|
| Agregar usuarios AD a `gidas-admins` o `SRV-Monitoring` para admin completo | 🔴 Alta | ⏳ |
| Verificar dispositivos 7-12 (status=0, sin reverse DNS) | 🟡 Media | ⏳ |
| Configurar alertas vía UI (Telegram, email) | 🟡 Media | ⏳ |
| Activar SNMP trap receiver (puertos 162/514 ya expuestos) | 🟡 Media | ⏳ |
| Schedulear backup automático (cron CT o PVE host) | 🟡 Media | ⏳ |
| Migrar passwords a secrets Docker o SOPS | 🟢 Baja | ⏳ |
| Agregar card al portal GIDAS | 🟢 Baja | ⏳ |
| Merge rama `gitlab-gidas` → `main` | 🟢 Baja | ⏳ |
