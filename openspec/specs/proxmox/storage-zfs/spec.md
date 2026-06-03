# proxmox/storage-zfs — Especificación

## Propósito

Proporcionar almacenamiento ZFS local y compartido con redundancia (mirror vdev), datasets jerárquicos por carga de trabajo, replicación asíncrona cross-pool para DR, y snapshots programados.

## Requisitos

### Requisito: Pools ZFS con mirror vdev

Cada nodo con discos DEBE tener pools ZFS configurados como mirror vdev para tolerancia a fallos. Pools single-disk SOLO se permiten en nodos sin discos redundantes.

#### Escenario: Pool mirror creado desde cero

- DADO dos discos del mismo tamaño en un nodo
- CUANDO se crea el pool ZFS
- ENTONCES DEBE usarse mirror vdev con `ashift=12`, `compression=zstd`, `atime=off`

#### Escenario: Pool single-disk migrado a mirror

- DADO un pool ZFS single-disk existente
- CUANDO se adjunta un segundo disco
- ENTONCES el pool DEBE convertirse a mirror vdev sin recreación

#### Escenario: Pool temporal single-disk

- DADO un nodo con un solo disco disponible
- CUANDO se crea el pool ZFS
- ENTONCES DEBE crearse como single-disk
- Y DEBE documentarse como no redundante

### Requisito: Límite de ARC

El sistema DEBE limitar el ARC de ZFS según la RAM disponible de cada nodo.

#### Escenario: ARC acotado en nodos con poca RAM

- DADO un nodo con ≤ 16 GB de RAM (ej: pve-desa02 con 10 GB)
- CUANDO se configura ZFS
- ENTONCES el ARC DEBE limitarse al 50% de RAM
- Y NO DEBE comprometer memoria para VMs

### Requisito: Datasets compartidos jerárquicos

El pool shared-zfs DEBE organizar datasets separados por carga de trabajo con recordsize y cuota específicos.

#### Escenario: Creación de datasets funcionales

- DADO el pool shared-zfs en pve-desa03
- CUANDO se crean los datasets
- ENTONCES DEBEN existir datasets para: vms, kubernetes, gitlab, registry, backups, samba
- Y CADA UNO DEBE tener `compression=zstd`, `atime=off`, `xattr=sa`
- Y recordsize DEBE ser 128K para vms, 1M para backups, default para el resto

### Requisito: Replicación asíncrona cross-pool para DR

El sistema DEBE replicar datasets críticos de shared-zfs (pve-desa03) a local-zfs (pve-desa02) con RPO ≤ 24h.

#### Escenario: Replicación diaria de datasets compartidos

- DADO datasets críticos en shared-zfs
- CUANDO se ejecuta replicación programada (diaria)
- ENTONCES DEBE transferir cambios incrementales vía `zfs send/recv`
- Y DEBE limitar ancho de banda a 500 Mbps

### Requisito: Replicación asíncrona entre pares locales

El sistema DEBE replicar datos críticos entre nodos del cluster con RPO diferenciado para VMs en storage local (no compartido).

#### Escenario: Replicación frecuente para VMs críticas

- DADO una VM marcada como crítica en storage local
- CUANDO transcurren 15 minutos desde la última replicación
- ENTONCES DEBE iniciar replicación ZFS incremental al nodo par
- Y DEBE limitar ancho de banda a 500 Mbps

#### Escenario: Replicación con ancho de banda limitado

- DADO la red del cluster es 1 GbE compartida
- CUANDO se ejecuta cualquier tarea de replicación
- ENTONCES el ancho de banda DEBE limitarse a 500 Mbps

### Requisito: Snapshots programados

El sistema DEBE tomar snapshots ZFS diarios de los datasets de VMs y compartidos con retención mínima de 7 días.

#### Escenario: Snapshot diario automático

- DADO un dataset ZFS con datos de VMs o compartidos
- CUANDO se ejecuta el schedule de snapshots
- ENTONCES DEBE crearse un snapshot diario
- Y DEBE retenerse por al menos 7 días
