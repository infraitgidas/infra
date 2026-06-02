# proxmox/storage-zfs — Especificación

## Propósito

Proporcionar almacenamiento robusto, eficiente y con integridad de datos mediante pools ZFS en todos los nodos del cluster, reemplazando el esquema actual basado en LVM thin sin protección.

## Requisitos

### Requisito: Configuración de pools ZFS

Cada nodo del cluster DEBE tener al menos un pool ZFS local para almacenamiento de VMs.

#### Escenario: Pool con parámetros óptimos

- DADO un disco disponible en el nodo (sin datos)
- CUANDO se crea el pool ZFS
- ENTONCES el pool DEBE usar `ashift=12`, `compression=zstd`, y `atime=off`

#### Escenario: Pool existente sin datos críticos

- DADO un nodo con discos ocupados por LVM thin
- CUANDO se migra a ZFS
- ENTONCES las VMs DEBEN ser movidas a otro nodo antes de destruir el volumen LVM
- Y el pool ZFS DEBE crearse en el espacio liberado

### Requisito: Límite de ARC

El sistema DEBE permitir configurar un límite máximo de memoria para ARC de ZFS.

#### Escenario: ARC acotado en nodos con poca RAM

- DADO un nodo con memoria limitada (ej: 32 GB)
- CUANDO se configura ZFS
- ENTONCES el ARC DEBE limitarse a un porcentaje configurable (ej: 25% de RAM total)
- Y NO DEBE comprometer la memoria disponible para VMs

### Requisito: Replicación asíncrona entre nodos

El sistema DEBE replicar datos críticos entre nodos del cluster con RPO diferenciado.

#### Escenario: Replicación cada 15 minutos para VMs críticas

- DADO una VM marcada como crítica
- CUANDO transcurren 15 minutos desde la última replicación
- ENTONCES el sistema DEBE iniciar una replicación ZFS incremental al nodo par

#### Escenario: Replicación cada 1 hora para VMs no críticas

- DADO una VM sin marca crítica
- CUANDO transcurre 1 hora desde la última replicación
- ENTONCES el sistema DEBE iniciar una replicación ZFS incremental al nodo par

#### Escenario: Ancho de banda limitado en replicación

- DADO que la red del cluster es 1 GbE
- CUANDO se ejecuta una tarea de replicación
- ENTONCES el ancho de banda DEBE limitarse a un valor configurable (ej: 500 Mbps) para no saturar la red

### Requisito: Snapshots programados

El sistema DEBE tomar snapshots ZFS periódicos de los datasets de VMs.

#### Escenario: Snapshot diario automático

- DADO un dataset ZFS con una VM
- CUANDO se ejecuta el schedule de snapshots
- ENTONCES se DEBE crear un snapshot diario con retención de 7 días
