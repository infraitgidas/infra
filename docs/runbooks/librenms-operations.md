# Runbook: LibreNMS GIDAS

> **URL**: https://nms.gidas.local
> **CT**: 210 (pve-desa04, 192.168.1.45)
> **Versión**: LibreNMS 26.6.1 (`:fixed`)

---

## 1. Acceso

### Vía SSH (PVE host)

```bash
# Desde máquina con acceso al cluster
ssh root@192.168.1.14

# Acceder al CT 210
pct enter 210

# Dentro del CT, ejecutar comandos Docker
docker ps
docker exec -it librenms bash
```

### Vía Web

```bash
https://nms.gidas.local
# Login con credenciales AD (infrait, errodriguez, etc.)
```

---

## 2. Estado del Sistema

### Verificar containers

```bash
pct enter 210
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'
```

Esperado:
```
NAMES            IMAGE                     STATUS
librenms         librenms/librenms:fixed   Up (healthy)
librenms-db      mariadb:10                Up (healthy)
librenms-redis   redis:7-alpine            Up
```

### Verificar servicios internos (s6)

```bash
docker exec librenms s6-rc -a list
# Debe mostrar: cron, nginx, php-fpm, snmpd, socklog
```

### Verificar poller

```bash
# Última ejecución del poller
docker exec librenms su -s /bin/bash librenms -c \
  'php /opt/librenms/artisan schedule:run --no-ansi --no-interaction'

# Poll manual de todos los dispositivos
docker exec librenms su -s /bin/bash librenms -c \
  'php /opt/librenms/artisan device:poll all'
```

### Verificar estado de dispositivos

```bash
docker exec librenms-db mysql -u librenms -p \
  librenms -e "SELECT COUNT(*) as total, \
  SUM(CASE WHEN status=1 THEN 1 ELSE 0 END) as up, \
  SUM(CASE WHEN status=0 AND disabled=0 THEN 1 ELSE 0 END) as down \
  FROM devices;"
```

---

## 3. Logs

### Logs del container

```bash
# Follow logs de LibreNMS
docker logs -f librenms

# Logs de la aplicación (dentro del container)
docker exec librenms tail -f /data/logs/librenms.log
```

### Logs del cron/poller

```bash
# Logs de cron via socklog
docker exec librenms cat /var/log/socklog/cron/current
```

### Logs de nginx

```bash
docker exec librenms tail -f /var/log/nginx/access.log
docker exec librenms tail -f /var/log/nginx/error.log
```

---

## 4. Administración de Usuarios

### Roles y permisos AD

La autenticación usa ActiveDirectory. Los roles se asignan según grupo AD:

| Grupo AD | Rol LNMS | Permisos |
|----------|----------|----------|
| `gidas-admins` | admin | Full acceso |
| `SRV-Monitoring` | admin | Full acceso |
| `G-IdentityAdmins` | admin | Full acceso |
| Otros usuarios | global-read | Solo lectura |

**Para dar admin a un usuario**: Agregarlo a `gidas-admins` o `SRV-Monitoring` en AD.

### Ver roles de un usuario en DB

```bash
docker exec librenms-db mysql -u librenms -p librenms -e "
  SELECT u.username, r.name as role
  FROM users u
  JOIN model_has_roles mhr ON u.user_id = mhr.model_id
  JOIN roles r ON r.id = mhr.role_id
  WHERE mhr.model_type = 'App\\\\Models\\\\User';
"
```

### Asignar rol manualmente

```bash
docker exec librenms su -s /bin/bash librenms -c \
  'php artisan permission:assign-role admin <user_id>'
```

> **⚠️ ATENCIÓN**: Los roles asignados manualmente se SOBRESCRIBEN en cada login AD por `syncRoles()`.
> Para que persistan, el usuario debe estar en el grupo AD correspondiente.

---

## 5. Configuración

### Archivos de configuración

| Archivo | Ruta (en container) | Propósito |
|---------|---------------------|-----------|
| Config principal | `/data/config/config.php` | AD, SNMP, trusted proxies |
| Base URL | `/data/config/base_url.php` | URL base |
| .env interno | `/data/.env` | APP_KEY, NODE_ID |
| .env Docker | `/opt/librenms/.env` | DB, Redis, SMTP |

### Modificar config.php

```bash
docker exec -it librenms bash
vi /data/config/config.php
# O sobreescribir:
cat > /data/config/config.php << 'EOF'
<?php
// ...
EOF
```

> **⚠️**: El archivo está en un volumen Docker. Sobrevive a `docker compose down`.

---

## 6. Backup y Restore

### Backup manual

```bash
# Desde el CT 210
bash /opt/librenms/scripts/backup.sh

# O especificando directorio
bash /opt/librenms/scripts/backup.sh /ruta/backups/
```

El script genera:
- `librenms-db_YYYYMMDD_HHMMSS.sql.gz` — dump MySQL
- `librenms-config_YYYYMMDD_HHMMSS.tar.gz` — config + .env

### Restore

```bash
# 1. Restaurar DB
gunzip -c librenms-db_*.sql.gz | \
  docker exec -i librenms-db mysql -u librenms -p librenms

# 2. Restaurar config
docker exec -i librenms tar xzf - -C /data < librenms-config_*.tar.gz

# 3. Recrear APP_KEY si es necesario
docker exec librenms php artisan key:generate

# 4. Restart
docker compose restart
```

---

## 7. Troubleshooting

### Síntoma: "No roles!" o "No access!"

**Causa**: El usuario no está en ningún grupo AD mapeado, o `syncRoles()` borró sus roles.

**Verificar**:
```bash
# Revisar grupos AD del usuario
docker exec librenms php -r '
  $ldap = ldap_connect("ldap://192.168.1.117");
  ldap_set_option($ldap, LDAP_OPT_PROTOCOL_VERSION, 3);
  ldap_set_option($ldap, LDAP_OPT_REFERRALS, 0);
  ldap_bind($ldap, "cn=infrait,ou=ServiceAccounts,dc=GDC01,dc=local", "Gidas2026!");
  $s = ldap_search($ldap, "dc=GDC01,dc=local", "(samaccountname=<usuario>)", ["memberOf"]);
  $e = ldap_get_entries($ldap, $s);
  for ($i = 0; $i < $e[0]["memberof"]["count"]; $i++) {
    $parts = explode(",", $e[0]["memberof"][$i]);
    echo "  - " . str_replace("CN=", "", $parts[0]) . "\n";
  }
'
```

**Solución**: Agregar el usuario a `gidas-admins`, `SRV-Monitoring` o `G-IdentityAdmins` en AD.

### Síntoma: Dashboard vacío, sin datos

**Causa**: Poller no está corriendo.

**Verificar**:
```bash
docker exec librenms su -s /bin/bash librenms -c \
  'php /opt/librenms/artisan schedule:run --no-ansi --no-interaction'
docker exec librenms su -s /bin/bash librenms -c \
  'php /opt/librenms/artisan device:poll all'
```

**Solución**: Verificar que el cron esté corriendo (`ps aux | grep crond`) y que el crontab tenga la línea correcta (ver Sección 2).

### Síntoma: 404 en endpoints API

**Causa**: Generalmente falta de datos (el endpoint devuelve 404 cuando no hay datos que mostrar, no porque la ruta no exista).

**Verificar**: Ejecutar poller manual y revisar logs.

### Síntoma: Error "SQLSTATE[HY093]"

**Causa**: Alerts rule con query mal formado.

**Solución**:
```sql
DELETE FROM alert_rules WHERE query IS NULL OR query = '';
```

### Síntoma: Container no arranca

```bash
# Ver logs del container
docker logs librenms

# Ver configuración de nginx
docker exec librenms nginx -t
```

---

## 8. Referencia Rápida

```bash
# === DOCKER ===
docker compose up -d                    # Iniciar stack
docker compose down                     # Detener stack (preserva volúmenes)
docker compose restart                  # Reiniciar stack
docker logs -f librenms                 # Logs en tiempo real

# === POLLER ===
docker exec librenms su -s /bin/bash librenms -c \
  'php artisan device:poll all'         # Poll manual (todos)
docker exec librenms su -s /bin/bash librenms -c \
  'php artisan device:poll <id>'        # Poll manual (un dispositivo)

# === DISCOVERY ===
docker exec librenms su -s /bin/bash librenms -c \
  'php artisan device:discover all'     # Rediscovery manual
docker exec librenms su -s /bin/bash librenms -c \
  'php artisan device:add --help'       # Agregar dispositivo

# === USUARIOS ===
docker exec librenms su -s /bin/bash librenms -c \
  'php artisan user:add --help'         # Agregar usuario local
docker exec librenms su -s /bin/bash librenms -c \
  'php artisan permission:assign-role admin <id>'  # Asignar rol

# === MANTENIMIENTO ===
docker exec librenms su -s /bin/bash librenms -c \
  'php artisan schedule:list'           # Ver tareas programadas
docker exec librenms su -s /bin/bash librenms -c \
  'php artisan about'                   # Info del sistema
```

---

## 9. Credenciales

> Las credenciales están documentadas en los secrets del proyecto.

| Recurso | Ubicación |
|---------|-----------|
| AD bind | `secrets/` — cn=infrait |
| DB MySQL | `.env` en CT 210 (solo en el server) |
| SMTP | `.env` en CT 210 (solo en el server) |
| Admin AD | Contactar al administrador de AD GDC01 |

---

*Última actualización: 2026-07-03*
