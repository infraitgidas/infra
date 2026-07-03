# Design: LibreNMS GIDAS

## Arquitectura

```
┌─ CT 210 (Rocky Linux 9) ───────────────────────────────┐
│                                                          │
│  ┌─ Docker Compose ─────────────────────────────────┐   │
│  │  librenms (librenms/librenms:fixed, tag 26.6.1)   │   │
│  │  ├── nginx interno (puerto 8000)                  │   │
│  │  │   └── disponible solo como 127.0.0.1:8080      │   │
│  │  ├── php-fpm 8.4 (via socket Unix)                │   │
│  │  ├── s6 supervisor:                               │   │
│  │  │   ├── nginx     → s6-supervise                │   │
│  │  │   ├── php-fpm   → s6-supervise                │   │
│  │  │   ├── cron      → busybox crond               │   │
│  │  │   ├── snmpd     → snmpd                       │   │
│  │  │   └── socklog   → syslog                      │   │
│  │  ├── /data/ → librenms_data (volumen persistente): │   │
│  │  │   ├── config/config.php   ← AD + SNMP config   │   │
│  │  │   ├── config/base_url.php                       │   │
│  │  │   ├── .env                ← APP_KEY, NODE_ID   │   │
│  │  │   ├── rrd/                ← bases RRD           │   │
│  │  │   └── logs/               ← logs de aplicación  │   │
│  │  └── puertos expuestos:                            │   │
│  │      ├── 162/udp+tcp  (SNMP traps)                │   │
│  │      └── 514/udp+tcp  (syslog)                    │   │
│  │                                                   │   │
│  │  mariadb:10 (volumen mysql_data)                   │   │
│  │  ├── healthcheck: connect + innodb_initialized     │   │
│  │  └── base de datos: librenms                       │   │
│  │                                                   │   │
│  │  redis:7-alpine (volumen redis_data)               │   │
│  │  └── cache + sesiones                              │   │
│  └───────────────────────────────────────────────────┘   │
│       │                                                   │
│       ├── SNMP v2c → switches, routers, servers          │
│       ├── LDAP/AD → GDC01 (192.168.1.117)                │
│       └── SMTP  → Office 365 (alertas email)             │
└──────────────────────────────────────────────────────────┘
```

## Componentes

| Componente | Imagen | Propósito |
|------------|--------|-----------|
| librenms | `librenms/librenms:fixed` | App principal (PHP 8.4 + nginx + s6) |
| mariadb | `mariadb:10` | Base de datos (datos de monitoreo) |
| redis | `redis:7-alpine` | Cache de sesiones y consultas |

## Configuración

### Ubicación de archivos

| Archivo | Ruta en container | Propósito |
|---------|------------------|-----------|
| `docker-compose.yml` | `/opt/librenms/docker-compose.yml` | Stack Docker |
| `.env` | `/opt/librenms/.env` | Variables Docker (DB, Redis, SMTP) |
| `.env interno` | `/data/.env` | APP_KEY + NODE_ID (persistente) |
| `config.php` | `/data/config/config.php` | Config AD + SNMP (persistente) |
| `base_url.php` | `/data/config/base_url.php` | URL base (persistente) |

### Autenticación AD

- **Mecanismo**: `active_directory` (nativo de LibreNMS, NO `ldap` genérico)
- **Bind**: `CN=infrait,OU=ServiceAccounts,DC=GDC01,DC=local`
- **Dominio**: `GDC01.local`
- **Base DN**: `DC=GDC01,DC=local`
- **Política**: Cualquier usuario AD puede loguearse (`require_groupmembership = false`)
- **Roles**:
  - Todos los usuarios autenticados: `global-read` (`auth_ad_global_read = true`)
  - Grupos mapeados otorgan roles adicionales:

| Grupo AD | Rol |
|----------|-----|
| `gidas-admins` | admin |
| `SRV-Monitoring` | admin |
| `G-IdentityAdmins` | admin |
| `gidas-pve-admin` | global-read |
| `gidas-pve-viewer` | global-read |

### Sistema de Polling

- **Mecanismo**: Laravel Scheduler via cron (`artisan schedule:run`)
- **Frecuencia**: Cada minuto (cron ejecuta el scheduler, que determina qué comandos ejecutar según su schedule)
- **Usuario**: `librenms` (UID 1000) — se ejecuta via `su -s /bin/bash librenms -c '...'`
- **Comando**: `device:poll all` corre según schedule interno (cada 5 minutos para checks operativos)
- **Cron init**: `/etc/cont-init.d/07-svc-cron.sh` — persistente en la imagen `:fixed`

### Alertas

- **Email**: SMTP Office 365 (transport nativo configurado en .env)
- **Telegram**: No configurado aún (guía en `scripts/setup-telegram.sh`)
- **Reglas**: Solo "Device Down" disponible (deshabilitada temporalmente por error PDO)

## Bugs Conocidos Corregidos

### 1. syncRoles([]) borra roles AD en cada login

**Archivo**: `LegacyUserProvider.php:141`
```php
$roles = $auth->getRoles($user->username);
if ($roles !== false) {        // [] es !== false
    $user->syncRoles($roles);  // syncRoles([]) → BORRA TODO
}
```

**Fix**: `auth_ad_global_read = true` + `auth_ad_groups` configurado.

### 2. artisan schedule:run no puede correr como root

**Guard**: `RunningAsIncorrectUserException`
```php
if (Posix::getpwuid(Posix::geteuid())['name'] === 'root') {
    throw new RunningAsIncorrectUserException('artisan must not run as root');
}
```

**Fix**: `su -s /bin/bash librenms -c 'php artisan schedule:run'` en crontab.

### 3. Alert rules con query vacío

**Síntoma**: `PDO::prepare(): Argument #1 ($query) must not be empty`

**Fix**: `DELETE FROM alert_rules WHERE query IS NULL OR query = ''`

## Dispositivos

12 dispositivos descubiertos vía SNMP scan inicial. 5 con polling activo (status=1), 7 con status=0 (requieren verificación de conectividad SNMP).

## Backup

Script en `scripts/backup.sh`:
- Dump MySQL (`mysqldump --single-transaction`)
- Backup config (`/data/config/` + `/data/.env`)
- Compresión gzip
- Cleanup de backups > 30 días
- RRD backup desactivado por defecto (opcional)
