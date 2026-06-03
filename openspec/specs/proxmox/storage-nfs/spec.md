# proxmox/storage-nfs — Especificación

## Propósito

Exportar datasets del pool shared-zfs (pve-desa03) vía NFS para storage compartido del cluster, habilitando live migration de VMs, PVs de Kubernetes, repositorios GitLab, registry, backups centralizados y failover manual a pve-desa02.

## Requisitos

### Requisito: Exports NFS desde datasets ZFS

Cada dataset funcional en shared-zfs DEBE exportarse vía NFS con opciones estandarizadas.

#### Escenario: Export de dataset con opciones adecuadas

- DADO un dataset funcional en shared-zfs (vms, kubernetes, gitlab, registry, backups)
- CUANDO se configura el export NFS en `/etc/exports`
- ENTONCES el export DEBE usar: `rw,async,no_subtree_check,no_wdelay,crossmnt`
- Y DEBE ser accesible desde todos los nodos del cluster (pve-desa01-04)

#### Escenario: Dataset sin export configurado

- DADO el dataset shared-zfs/samba (servido por Samba, no NFS)
- CUANDO se listan los exports NFS
- ENTONCES NO DEBE aparecer en los exports de NFS

### Requisito: Montaje NFS en nodos consumidores

Todos los nodos del cluster DEBEN montar los exports NFS como storage Proxmox.

#### Escenario: Storage NFS agregado en Proxmox

- DADO un nodo del cluster distinto de pve-desa03
- CUANDO se agrega storage tipo NFS en Proxmox GUI
- ENTONCES el nodo DEBE montar el export en `/mnt/pve/{dataset-name}`
- Y DEBE estar disponible para VMs, CTs y templates

#### Escenario: Montaje manual en nodo sin GUI

- DADO un nodo sin Proxmox o con GUI no disponible
- CUANDO se monta el export manualmente
- ENTONCES DEBE usar `mount -t nfs4 -o rw,hard,intr,noatime,vers=4.2`

### Requisito: Performance dentro del ancho de banda disponible

El tráfico NFS DEBE operar dentro del límite de 1 GbE sin degradar otros servicios del cluster.

#### Escenario: Throughput secuencial en NFS

- DADO un cliente NFS en la red 1 GbE
- CUANDO se transfiere un archivo grande (>1 GB) sobre NFS
- ENTONCES el throughput DEBE ser ≥ 80 MB/s

#### Escenario: Uso de red compartida

- DADO tráfico NFS + replicación + Corosync en la misma red 1 GbE
- CUANDO la replicación está activa
- ENTONCES NFS NO DEBE exceder el 70% de ancho de banda disponible

### Requisito: Failover manual del servidor NFS

El sistema DEBE soportar failover manual del servidor NFS a pve-desa02 si pve-desa03 falla.

#### Escenario: Promoción de DR target a NFS server

- DADO pve-desa03 caído y datasets replicados en local-zfs/backup-dr (pve-desa02)
- CUANDO se activa failover manual
- ENTONCES pve-desa02 DEBE exportar los datasets replicados vía NFS
- Y los nodos consumidores DEBEN re-montar desde pve-desa02

#### Escenario: Failback tras recuperación de pve-desa03

- DADO pve-desa03 recuperado y replicación sincronizada
- CUANDO se realiza failback
- ENTONCES NFS DEBE volver a servirse desde pve-desa03
- Y los nodos consumidores DEBEN re-montar al servidor original
