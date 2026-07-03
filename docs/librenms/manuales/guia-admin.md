# Guía de Administración — LibreNMS GIDAS

> **URL**: https://nms.gidas.local
> **CT**: 210 (pve-desa04, 192.168.1.45)
> **Versión**: LibreNMS 26.6.1 / Grafana 13.0.1

---

## 1. Acceso al Servidor

```bash
# Desde máquina con acceso al cluster
ssh root@192.168.1.14            # PVE host (pve-desa04)
pct enter 210                    # CT 210 (LibreNMS)

# Dentro del CT, comandos Docker
docker ps
docker exec -it librenms bash    # Shell en el container
```

Para CT 205 (Grafana):
```bash
ssh root@192.168.1.31            # PVE host (pve-ad)
pct enter 205                    # CT 205 (sg-monitoring)
systemctl status grafana-server   # Grafana
```

---

## 2. Estado del Sistema

```bash
# Ver containers
pct exec 210 -- docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'

# LibreNMS debe estar: Up, MariaDB: healthy
# Esperado:
#   librenms       librenms/librenms:fixed   Up
#   librenms-db    mariadb:10                Up (healthy)
#   librenms-redis redis:7-alpine            Up

# Ver servicios internos (s6 supervisor)
pct exec 210 -- docker exec librenms s6-rc -a list
# Debe mostrar: cron, nginx, php-fpm, snmpd, socklog
```

---

## 3. Administración de Usuarios

### Roles por grupo AD

Los roles se asignan automáticamente según membresía en AD:

| Grupo AD | Rol LNMS | Permisos |
|----------|----------|----------|
| `gidas-admins` | admin | Full acceso |
| `SRV-Monitoring` | admin | Full acceso |
| `G-IdentityAdmins` | admin | Full acceso |
| `gidas-pve-admin` | global-read | Solo lectura |
| `gidas-pve-viewer` | global-read | Solo lectura |
| Cualquier otro AD | global-read | Solo lectura |

### Para dar admin a un usuario

Agregarlo a `gidas-admins` o `SRV-Monitoring` en AD, no en la UI de LibreNMS.

### Ver roles actuales en DB

```bash
pct exec 210 -- docker exec librenms-db mysql -u librenms -p librenms -e "
  SELECT u.username, r.name as role
  FROM users u
  JOIN model_has_roles mhr ON u.user_id = mhr.model_id
  JOIN roles r ON r.id = mhr.role_id
  WHERE mhr.model_type = 'App\Models\User';
"
```

> ⚠️ Los roles asignados manualmente se sobrescriben en cada login AD por `syncRoles()`.

---

## 4. Gestión de Dispositivos

### Agregar dispositivo manualmente

```bash
pct exec 210 -- docker exec librenms su -s /bin/bash librenms -c \
  'php artisan device:add --help'
```

### Agregar por SNMP
```bash
pct exec 210 -- docker exec librenms su -s /bin/bash librenms -c \
  "php artisan device:add --v2c -c public 192.168.1.x"
```

### Rediscovery manual
```bash
pct exec 210 -- docker exec librenms su -s /bin/bash librenms -c \
  'php artisan device:discover all'
```

### Polling manual
```bash
# Todos los dispositivos
pct exec 210 -- docker exec librenms su -s /bin/bash librenms -c \
  'php artisan device:poll all'

# Un dispositivo específico
pct exec 210 -- docker exec librenms su -s /bin/bash librenms -c \
  'php artisan device:poll 1'
```

---

## 5. Alertas

### Configurar canal Telegram

Ya configurado con el bot @GiDAS_alertbot. Para agregar otro chat:

1. Crear bot con @BotFather en Telegram
2. Obtener token y chat ID
3. En LibreNMS: Global Settings → Alerting → Transports → Add Telegram Transport
4. Ingresar token, chat ID y formato (Markdown)

### Agregar transporte email

Ya configurado SMTP Office 365. Verificar en:
Global Settings → Alerting → Transports → Mail

### Silenciar alertas temporariamente

Desde la UI: Alerts → Alert Rules → Edit → Mute (delay en segundos)

---

## 6. Grafana

### Acceso
- **URL**: `http://192.168.1.205:3000`
- **Usuario**: `admin`
- **Password**: `hlvs.2025`

### Dashboards disponibles

| Dashboard | Descripción |
|-----------|-------------|
| **Overview** | Visión general: dispositivos, alertas, top CPU |
| **Performance** | CPU/RAM/disco/temperatura por dispositivo |
| **Network** | Tráfico, errores, ancho de banda por puerto |

### Agregar usuario a Grafana

```bash
pct exec 205 -- grafana cli --homepath /usr/share/grafana admin reset-admin-password <password>
```

O desde la UI: Configuration → Users → Invite

---

## 7. Backup y Restore

### Backup manual
```bash
pct exec 210 -- bash /opt/librenms/scripts/backup.sh
```

Genera en `/var/backups/librenms/`:
- `librenms-db_YYYYMMDD_HHMMSS.sql.gz` — dump MySQL
- `librenms-config_YYYYMMDD_HHMMSS.tar.gz` — config.php + .env

### Restore
```bash
# 1. Restaurar DB
gunzip -c librenms-db_*.sql.gz | \
  pct exec 210 -- docker exec -i librenms-db mysql -u librenms -p librenms

# 2. Restaurar config
gunzip -c librenms-config_*.tar.gz | \
  pct exec 210 -- docker exec -i librenms tar xzf - -C /data

# 3. Restart
pct exec 210 -- docker compose -f /opt/librenms/docker-compose.yml restart
```

---

## 8. Logs

```bash
# Logs del container LibreNMS
pct exec 210 -- docker logs -f librenms

# Logs de la aplicación
pct exec 210 -- docker exec librenms tail -f /data/logs/librenms.log

# Logs de nginx (dentro del container)
pct exec 210 -- docker exec librenms tail -f /var/log/nginx/error.log

# Logs de Grafana
ssh root@192.168.1.31 "pct exec 205 -- journalctl -u grafana-server -f"
```

---

## 9. Troubleshooting

### "No roles!" o "No access!"
El usuario no está en ningún grupo AD mapeado. Verificar:
```bash
pct exec 210 -- docker exec librenms php -r '
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

### Dashboard vacío, sin datos
El poller no está corriendo:
```bash
pct exec 210 -- docker exec librenms su -s /bin/bash librenms -c \
  'php /opt/librenms/artisan device:poll all'
```

### Container no arranca
```bash
pct exec 210 -- docker logs librenms
pct exec 210 -- docker exec librenms nginx -t
```

---

## 10. Referencia Rápida

```bash
# === DOCKER ===
pct exec 210 -- docker compose -f /opt/librenms/docker-compose.yml up -d
pct exec 210 -- docker compose -f /opt/librenms/docker-compose.yml down
pct exec 210 -- docker compose -f /opt/librenms/docker-compose.yml logs -f

# === POLLER ===
pct exec 210 -- docker exec librenms su -s /bin/bash librenms -c \
  'php artisan device:poll all'

# === DISCOVERY ===
pct exec 210 -- docker exec librenms su -s /bin/bash librenms -c \
  'php artisan device:discover all'

# === USUARIOS ===
pct exec 210 -- docker exec librenms su -s /bin/bash librenms -c \
  'php artisan permission:assign-role admin <user_id>'

# === API ===
pct exec 210 -- docker exec librenms-db mysql -u librenms -p librenms -e \
  "SELECT token_hash FROM api_tokens;"

# === GRAFANA ===
ssh root@192.168.1.31 "pct exec 205 -- systemctl restart grafana-server"
```

---

*Última actualización: 2026-07-03*
