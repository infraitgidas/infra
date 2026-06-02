# proxmox/vm-optimization — Especificación

## Propósito

Maximizar el rendimiento de las VMs del cluster mediante parámetros óptimos de CPU, memoria y almacenamiento, corrigiendo configuraciones subóptimas detectadas en la auditoría (ej: cache writeback en VM crítica).

## Requisitos

### Requisito: CPU type host en VMs Linux

Las VMs con sistema operativo Linux DEBEN usar CPU type `host` para exponer todas las instrucciones del procesador físico.

#### Escenario: VM Linux con CPU type host

- DADO una VM Linux sin necesidad de migración cross-nodo
- CUANDO se verifica su configuración de CPU
- ENTONCES el CPU type DEBE ser `host`

### Requisito: NUMA habilitado en VMs grandes

Las VMs con más de 4 vCPUs o más de 16 GB de RAM DEBEN tener NUMA habilitado.

#### Escenario: VM con 8 vCPUs

- DADO una VM con 8 vCPUs asignadas
- CUANDO se revisa su configuración
- ENTONCES `numa` DEBE estar habilitado

#### Escenario: VM con 24 GB de RAM

- DADO una VM con 24 GB de RAM
- CUANDO se revisa su configuración
- ENTONCES `numa` DEBE estar habilitado

### Requisito: Modo de cache en discos

Las VMs con discos VirtIO NO DEBEN usar `cache=writeback`. DEBEN usar `cache=none` o `cache=writethrough`.

#### Escenario: Cache none en VMs críticas

- DADO una VM con requisitos de integridad de datos
- CUANDO se verifica su configuración de disco
- ENTONCES `cache` DEBE ser `none`

#### Escenario: Cache writethrough permitido

- DADO una VM donde `cache=none` no es viable
- CUANDO se selecciona un modo alternativo
- ENTONCES `cache=writethrough` DEBERÍA usarse como alternativa segura

### Requisito: VirtIO SCSI Single con IO Thread

Los discos de las VMs DEBEN usar VirtIO SCSI Single con IO Thread habilitado para mejor rendimiento de E/S.

#### Escenario: Controladora SCSI con IO Thread

- DADO una VM con discos SCSI
- CUANDO se configura la controladora
- ENTONCES DEBE usarse VirtIO SCSI Single con `iothread=1`

### Requisito: Memory ballooning con límites

Las VMs PUEDEN usar memory ballooning, pero DEBEN tener configurado un mínimo y máximo.

#### Escenario: Ballooning con límite inferior

- DADO una VM con ballooning habilitado
- CUANDO la memoria se reduce dinámicamente
- ENTONCES la VM NO DEBE bajar de `balloon` mínimo (ej: 1 GB)
- Y el mínimo DEBE ser suficiente para que el SO funcione sin swap excesivo
