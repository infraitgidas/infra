# F5 — Monitoreo (P2)

## Objetivo

Establecer un stack de monitoreo completo para el cluster Proxmox pve-gidas
que permita detectar fallas de quorum, salud de ZFS, capacidad de almacenamiento,
y estado de backups, con alertas tempranas.

## Arquitectura

```
                     ┌─────────────────────────────┐
                     │  CT sg-monitoring (pve-ad)  │
                     │  192.168.1.31 (CT 205)      │
                     │                             │
                     │  ┌──────────┐ ┌──────────┐  │
                     │  │ Grafana  │ │Prometheus│  │
                     │  │ :3000    │ │ :9090    │  │
                     │  └────┬─────┘ └────┬─────┘  │
                     │       │            │        │
                     │       │    ┌───────┘        │
                     │       │    │  ┌──────────┐  │
                     │       │    │  │Alertmgr  │  │
                     │       │    │  │ :9093    │  │
                     │       │    │  └──────────┘  │
                     └───────┼────┼────────────────┘
                             │    │
       ┌─────────────────────┼────┼─────────────────────┐
       │     Cluster PVE     │    │                     │
       │                     │    │                     │
       │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐
       │  │desa01   │  │desa02   │  │desa03   │  │desa04   │
       │  │:9221    │  │:9221    │  │:9221    │  │:9221    │
       │  │:9100    │  │:9100    │  │:9100    │  │:9100    │
       │  └─────────┘  └─────────┘  └─────────┘  └─────────┘
       └────────────────────────────────────────────────────┘
```

**Stack:**
- **Prometheus**: Recolección y almacenamiento de métricas
- **Grafana**: Visualización con dashboard ID 10347
- **Alertmanager**: Gestión de alertas con enrutamiento e inhibición
- **PVE Exporter** (:9221): Métricas específicas de Proxmox VE por nodo
- **Node Exporter** (:9100): Métricas del sistema operativo por nodo

**Decisión de Arquitectura**: Prometheus + Grafana + Alertmanager corren
en CT sg-monitoring (pve-ad), fuera del cluster PVE. Esto garantiza que
el monitoreo sobrevive a un fallo completo del cluster y puede alertar
cuando más se necesita.

## Requisitos

1. CT sg-monitoring (pve-ad, CT 205) con 2 GB RAM y Debian/Ubuntu
2. Acceso SSH sin contraseña (key-based) desde la máquina de control
3. Conexión de red entre CT sg-monitoring y todos los nodos del cluster
4. `curl` y `python3` en la máquina de control (para verificación)
5. Token PVE API para `root@pam` en cada nodo (para pve_exporter)

## Orden de Ejecución

Los scripts **deben ejecutarse en orden** desde la máquina de control:

```bash
# 0. Cargar configuración de entorno
source 00-env.sh

# 1. Instalar Prometheus en CT sg-monitoring (Task 5.1)
./01-install-prometheus.sh

# 2. Instalar Grafana en CT sg-monitoring (Task 5.1)
./02-install-grafana.sh

# 3. Instalar PVE Exporter + Node Exporter en cada nodo (Task 5.2)
./03-install-exporters.sh

# 4. Configurar scrape targets en Prometheus (Task 5.3)
./04-scrape-config.sh

# 5. Importar dashboard Grafana ID 10347 (Task 5.4)
./05-dashboard.sh

# 6. Configurar Alertmanager + reglas (Task 5.5)
./06-alertmanager.sh

# 7. Verificar todo el stack (Task 5.6)
./07-verify.sh
```

## Configuraciones Clave

### PVE Exporter Auth

El PVE Exporter necesita un token de API para consultar métricas.
Crear en cada nodo:

```bash
pveum user token add root@pam exporter --privsep 0
# Copiar el token_secret
```

Luego editar `/etc/pve_exporter/pve.yml`:

```yaml
default:
  user: root@pam
  token_name: exporter
  token_value: 'el-token-secret-aqui'
  verify_ssl: false
```

Reiniciar el exporter:
```bash
systemctl restart pve_exporter
```

### Grafana

- URL: http://192.168.1.31:3000
- Usuario: `admin`
- Password: `admin` (cambiar después del login inicial)
- Datasource: Prometheus (http://localhost:9090)

### Alertmanager

Alertmanager se auto-configura con:
- Reglas de alerta en `/etc/prometheus/alerts.yml`
- Configuración en `/etc/alertmanager/alertmanager.yml`
- Por defecto envía alertas por email a `admin@pve-gidas.local`

Para cambiar el canal de notificaciones, editar `alertmanager.yml` y
agregar Slack, Telegram, webhook, etc.

## Reglas de Alerta

| Alerta | Severidad | Condición | Acción |
|--------|-----------|-----------|--------|
| PVEQuorumLoss | critical | <3 nodos online por 1m | Verificar Corosync |
| ZFSPoolDegraded | critical | Pool ZFS con errores por 5m | Ejecutar `zpool status -v` |
| DiskUsageHigh | warning | Disco >80% por 10m | Limpiar espacio |
| DiskUsageCritical | critical | Disco >90% por 5m | Liberar espacio URGENTE |
| BackupJobFailed | warning | >25h sin backup completado | Verificar PBS y jobs |
| PVENodeDown | critical | Nodo offline >2m | Verificar console/KVM |

## Verificación

```bash
# Verificación completa
source 00-env.sh && ./07-verify.sh

# Verificaciones manuales rápidas
curl http://192.168.1.31:9090/api/v1/targets     # Targets Prometheus
curl http://192.168.1.31:3000/api/health          # Grafana health
curl http://192.168.1.31:9093/api/v2/alerts       # Alertmanager alerts
curl http://192.168.1.11:9221/pve                 # PVE metrics nodo 1
curl http://192.168.1.11:9100/metrics             # Node metrics nodo 1
```

## Rollback

### Desinstalar monitoreo completo

```bash
# En CT sg-monitoring
systemctl stop prometheus grafana-server alertmanager
apt-get remove -y grafana
rm /usr/local/bin/prometheus /usr/local/bin/alertmanager /usr/local/bin/amtool
rm -rf /etc/prometheus /var/lib/prometheus /etc/grafana /var/lib/grafana /etc/alertmanager /var/lib/alertmanager

# En cada nodo del cluster
for node in 192.168.1.11 192.168.1.12 192.168.1.13 192.168.1.14; do
    ssh root@$node "
        systemctl stop pve_exporter node_exporter
        rm /usr/local/bin/pve_exporter /usr/local/bin/node_exporter
        rm /etc/systemd/system/pve_exporter.service
        rm /etc/systemd/system/node_exporter.service
        rm /etc/pve_exporter/pve.yml
        systemctl daemon-reload
    "
done
```

### Rollback parcial

| Componente | Comando |
|------------|---------|
| Prometheus | `systemctl stop prometheus && rm -rf /etc/prometheus /var/lib/prometheus` |
| Grafana | `systemctl stop grafana-server && apt-get remove -y grafana` |
| Alertmanager | `systemctl stop alertmanager && rm -rf /etc/alertmanager /var/lib/alertmanager` |
| PVE Exporter | `systemctl stop pve_exporter && rm /usr/local/bin/pve_exporter` |
| Node Exporter | `systemctl stop node_exporter && rm /usr/local/bin/node_exporter` |
| Scrape targets | Restaurar `prometheus.yml` original, reiniciar Prometheus |

## Limitaciones Conocidas

1. **PVE Exporter auth**: Requiere token API creado manualmente en cada nodo.
   El script instala el binario pero la configuración de credenciales es manual.
2. **Alertmanager email**: Por defecto usa SMTP localhost:25 sin TLS.
   Para entornos productivos, configurar un relay SMTP real.
3. **Dashboard ID 10347**: Depende de disponibilidad de grafana.com para
   descarga. Si no hay internet, crear dashboard manualmente desde la UI.
4. **Monitoreo fuera del cluster**: Ventaja de supervivencia a fallo del
   cluster, pero si pve-ad falla, se pierde el monitoreo.
5. **Sin dashboards adicionales**: Solo se importa el dashboard ID 10347.
   Se pueden agregar más dashboards de node_exporter, etc.

## Prerequisitos

1. CT sg-monitoring (pve-ad, CT 205) operativo con Debian/Ubuntu
2. Acceso SSH sin contraseña (key-based) como root a CT y nodos
3. Cluster Proxmox funcional (pvecm status OK en al menos 3 nodos)
4. `jq` instalado en máquina de control (recomendado para parsing JSON)
5. 2 GB RAM libre en CT sg-monitoring (Prometheus + Grafana + Alertmanager)
6. Conexión a internet para descargar binarios de GitHub (o mirror local)

## Archivos del Script

| Script | Task | Descripción |
|--------|------|-------------|
| `00-env.sh` | — | Variables de entorno del stack de monitoreo |
| `01-install-prometheus.sh` | 5.1 | Instala Prometheus en CT sg-monitoring |
| `02-install-grafana.sh` | 5.1 | Instala Grafana en CT sg-monitoring |
| `03-install-exporters.sh` | 5.2 | Instala pve_exporter + node_exporter en cada nodo |
| `04-scrape-config.sh` | 5.3 | Configura targets de scrape en Prometheus |
| `05-dashboard.sh` | 5.4 | Importa dashboard Grafana ID 10347 |
| `06-alertmanager.sh` | 5.5 | Instala y configura Alertmanager |
| `07-verify.sh` | 5.6 | Verificación completa del stack |
