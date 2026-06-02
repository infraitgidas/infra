# proxmox/backup — Especificación

## Propósito

Garantizar la recuperabilidad del cluster pve-gidas mediante backups automáticos con Proxmox Backup Server (PBS), retención rotativa, cifrado client-side y restauración granular de VMs.

## Requisitos

### Requisito: Instalación y almacenamiento PBS

El sistema DEBE contar con un servidor PBS con datastore sobre ZFS.

#### Escenario: Datastore con compresión zstd

- DADO un servidor PBS instalado en el cluster
- CUANDO se configura un datastore en el PBS
- ENTONCES el datastore DEBE residir en un pool ZFS con `compression=zstd`

### Requisito: Programación de backups

El sistema DEBE ejecutar jobs de backup diarios para todas las VMs del cluster.

#### Escenario: Job diario automático

- DADO un nodo del cluster con VMs activas
- CUANDO se ejecuta el job de backup diario programado
- ENTONCES cada VM DEBE ser respaldada completa en el datastore PBS

#### Escenario: Backup nocturno fuera de horario laboral

- DADO que el job de backup está configurado
- CUANDO se revisa la ventana de ejecución
- ENTONCES el job DEBE ejecutarse fuera del horario laboral (ej: 22:00-06:00)

### Requisito: Política de retención

El sistema DEBE aplicar retención rotativa 7+4+3: 7 daily, 4 weekly, 3 monthly.

#### Escenario: Prune automático post-backup

- DADO un datastore PBS con backups acumulados
- CUANDO se ejecuta el prune schedule
- ENTONCES se DEBEN conservar únicamente los últimos 7 daily, 4 weekly y 3 monthly
- Y los backups fuera de esa ventana DEBEN ser eliminados

#### Escenario: Garbage collection periódico

- DADO un datastore PBS con chunks huérfanos tras prune
- CUANDO se ejecuta el garbage collection schedule (ej: semanal)
- ENTONCES los chunks no referenciados DEBEN ser liberados del datastore

### Requisito: Cifrado client-side

Los backups DEBEN ser cifrados en origen antes de transmitirse al PBS.

#### Escenario: Cifrado con clave de encryption key

- DADO un job de backup configurado
- CUANDO el backup se ejecuta
- ENTONCES los datos DEBEN ser cifrados con encryption key antes de salir del nodo Proxmox
- Y el PBS NO DEBE poder leer los datos sin la clave

### Requisito: Restauración de VMs

El sistema DEBE permitir restaurar VMs individuales desde cualquier backup disponible.

#### Escenario: Restauración completa de VM

- DADO un backup válido en el datastore PBS
- CUANDO se inicia una restauración desde la UI de Proxmox
- ENTONCES la VM DEBE ser restaurada con su configuración original y datos completos

#### Escenario: Restauración de archivo individual

- DADO un backup de VM con el contenido a recuperar
- CUANDO se utiliza el explorador de backups del PBS
- ENTONCES el usuario PUEDE descargar archivos individuales sin restaurar la VM completa
