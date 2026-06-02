# infra/monitoring — Especificación

## Propósito

Establecer un stack de monitoreo para el cluster Proxmox que permita detectar fallas de quorum, salud de ZFS, capacidad de almacenamiento, y estado de backups, con alertas tempranas.

## Requisitos

### Requisito: Recolección de métricas con Prometheus

Cada nodo del cluster DEBE ejecutar un Prometheus PVE Exporter para exponer métricas del entorno Proxmox.

#### Escenario: PVE Exporter en cada nodo

- DADO un nodo del cluster pve-gidas
- CUANDO se despliega el stack de monitoreo
- ENTONCES el nodo DEBE ejecutar `pve_exporter` exponiendo métricas en un puerto configurable (ej: 9221)

#### Escenario: Node Exporter en cada nodo

- DADO un nodo del cluster
- CUANDO se despliega el stack de monitoreo
- ENTONCES el nodo DEBE ejecutar `node_exporter` exponiendo métricas del sistema operativo

### Requisito: Dashboard Grafana

El sistema DEBE tener un dashboard Grafana con las métricas clave del cluster.

#### Escenario: Dashboard de cluster PVE

- DADO Prometheus configurado como datasource en Grafana
- CUANDO se abre el dashboard de cluster
- ENTONCES DEBE mostrar estado de nodos, VMs, uso de CPU/RAM/disco, y estado de ZFS

### Requisito: Alertas de cluster

El sistema DEBE generar alertas para condiciones críticas del cluster.

#### Escenario: Pérdida de quorum

- DADO que un nodo pierde conectividad Corosync
- CUANDO el quorum cae por debajo de mayoría (2/3 nodos)
- ENTONCES el sistema DEBE disparar una alerta de pérdida de quorum

#### Escenario: Salud de ZFS comprometida

- DADO un pool ZFS con errores de integridad (checksum, I/O)
- CUANDO `zpool status` reporta estado distinto a ONLINE
- ENTONCES el sistema DEBE disparar una alerta de salud ZFS

#### Escenario: Disco por encima del 80% de uso

- DADO un datastore o pool ZFS con capacidad superando el 80%
- CUANDO se verifica el umbral de almacenamiento
- ENTONCES el sistema DEBE disparar una alerta de capacidad

#### Escenario: Falla en backup programado

- DADO un job de backup que no completó exitosamente
- CUANDO finaliza la ventana de backup programada
- ENTONCES el sistema DEBE disparar una alerta de backup fallido

### Requisito: Notificaciones de alertas

El sistema DEBE enviar notificaciones de alertas a los administradores del cluster.

#### Escenario: Alerta enviada por el canal configurado

- DADO una alerta disparada por cualquiera de las condiciones críticas
- CUANDO se procesa la alerta en Prometheus/Alertmanager
- ENTONCES la notificación DEBE ser enviada al canal configurado (email, Slack, Telegram, etc.)
