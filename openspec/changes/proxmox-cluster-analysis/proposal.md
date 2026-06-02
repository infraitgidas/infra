# Propuesta: Optimización del Cluster Proxmox — pve-gidas

## Intención

Resolver deficiencias críticas del cluster pve-gidas detectadas en la auditoría: sin backups, riesgo de corrupción (cache writeback en VM 102), 3 VMs Windows stopped sin uso (9 GB RAM ocupados), storage sin integridad (100% LVM thin), red plana sin redundancia, y cero monitoreo.

## Alcance

### In Scope

**F1 (P0) — Correcciones inmediatas**
- Cambiar cache writeback → none en VM 102
- Decidir destino de 3 VMs Windows stopped (activar o eliminar)
- Instalar PBS + configurar jobs diarios con retención 7+4+3

**F2 (P1) — Storage**
- Migrar LVM thin → ZFS (ashift=12, compression=zstd, atime=off)
- Replicación asíncrona entre nodos (RPO 15 min críticas, 1h resto)

**F3 (P2) — Red**
- VLAN 10 para Corosync, link1 redundante en corosync.conf
- Bonding/LACP en pve-desa04 (4 NICs disponibles)

**F4 (P2) — Optimización VMs**
- CPU type host en VMs Linux sin migración cross-nodo
- NUMA en VMs con >4 vCPUs
- Prometheus + PVE Exporter + Grafana con alertas

### Out of Scope
Unificación pve-ad (PVE 9 vs 8 incompatible), Ceph (requiere 3 nodos+10GbE), HA live migration (requiere shared storage), QDevice (quorum 3/4 aceptable), migración NFS compartido.

## Capacidades

No existen specs previos en `openspec/specs/`. Todas son nuevas.

### Nuevas Capacidades
- `proxmox/backup`: PBS, políticas de retención, restauración
- `proxmox/storage-zfs`: pools ZFS, replicación asíncrona, snapshots
- `proxmox/network`: VLAN Corosync, bonding, link1 redundante
- `proxmox/vm-optimization`: CPU host, NUMA, ballooning, parámetros de rendimiento
- `infra/monitoring`: Prometheus + Grafana + PVE Exporter, alertas de cluster

### Capacidades Modificadas
None.

## Enfoque

Fases ordenadas y ejecución secuencial estricta: P0 (riesgo inmediato) → P1 (storage) → P2 (red + optimización). Cada fase es independiente y reversible. Backups primero, antes de cualquier cambio estructural. Migración ZFS nodo por nodo moviendo VMs al vecino. PBS instalado en pve-ad o VM separada (evita SPOF del NFS actual en pve-desa03).

## Áreas Afectadas

| Área | Impacto | Descripción |
|------|---------|-------------|
| `/etc/pve/storage.cfg` | Modificado | +ZFS pools, +PBS datastore |
| `proxmox/pbs/` | Nuevo | Configuración de PBS |
| `/etc/network/interfaces` | Modificado | VLAN 10, bonding pve-desa04 |
| `/etc/pve/corosync.conf` | Modificado | +link1 redundante |
| `proxmox/monitoring/` | Nuevo | Dashboards Grafana, alertas |
| `secrets/proxmox.yaml` | Modificado | Nuevos endpoints PBS |

## Riesgos

| Riesgo | Prob | Mitigación |
|--------|------|------------|
| Migración ZFS causa downtime | Media | Mover VMs a otro nodo antes de migrar |
| PBS sin HW dedicado | Media | Evaluar VM en el cluster o pve-ad |
| Bonding mal configurado | Baja | Probar en pve-desa04 antes de replicar |
| Replicación satura red 1GbE | Media | Limitar ancho de banda en schedule |

## Plan de Rollback

- **F1**: revertir cache writeback a original; restaurar VMs desde PBS si es necesario
- **F2**: eliminar pools ZFS, restaurar LVM thin desde backups de VMs; deshabilitar replicación
- **F3**: restaurar `/etc/network/interfaces` original; revertir corosync.conf
- **F4**: revertir CPU type y NUMA por VM; detener stack de monitoreo

## Dependencias

- Acceso SSH a todos los nodos (ya operativo)
- PBS instalado (HW separado o VM)
- Discos libres en pve-desa03 (sdc 932GB) y pve-desa04 (sdb 932GB) para migración ZFS

## Criterios de Éxito

- [ ] VM 102 verificado con `cache=none` en `qm config 102`
- [ ] Backups diarios configurados para todas las VMs con retención verificada
- [ ] Todos los nodos con pool ZFS local, `compression=zstd` activo
- [ ] Replicación asíncrona activa entre pares de nodos
- [ ] Corosync con link1 redundante, tráfico por VLAN 10
- [ ] Bonding operativo en pve-desa04
- [ ] CPU type `host` y NUMA habilitado en VMs seleccionadas
- [ ] Prometheus recolectando métricas, Grafana con dashboard de cluster PVE
