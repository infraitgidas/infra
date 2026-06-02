# Tareas: Optimización del Cluster Proxmox pve-gidas

## Review Workload Forecast

| Campo | Valor |
|-------|-------|
| Líneas cambiadas estimadas | ~350-400 |
| Riesgo de presupuesto 400 líneas | Medio |
| PRs encadenados recomendados | No |
| Split sugerido | PR único (todas las fases) |
| Estrategia de entrega | ask-on-risk → chained |
| Chain strategy | feature-branch-chain |

Decision needed before apply: Yes → resolved
Chained PRs recommended: No → user chose chained
Chain strategy: pending → feature-branch-chain
400-line budget risk: Medium

### Suggested Work Units

| Unit | Goal | Likely PR | Notes |
|------|------|-----------|-------|
| 1 | Backups + fix writeback | PR único | Dependencia: ninguna. Base main |
| 2 | Storage ZFS | PR único | Depende de F1 |
| 3 | Red + VLAN | PR único | Depende de F1 |
| 4 | Optimización VMs | PR único | Depende de F1 |
| 5 | Monitoreo | PR único | Depende de F1 |

## Fase 1: Backups y Correcciones Inmediatas (P0)

- [x] 1.1 Decidir destino VMs Windows stopped (100, 101, 102): activar o eliminar — VM 102 eliminada (qm destroy --purge), 100 y 101 mantenidas stopped
- [x] 1.2 VM 102 DC2: `qm set 102 --scsi0 cache=none` — Ya estaba en `cache=none`, verificado. No requirió acción.
- [x] 1.3 Instalar PBS en pve-ad con datastore ZFS (`compression=zstd`) — ✅ **MODIFICADO**: Sin segundo disco físico para ZFS. Se instaló PBS 4.0.11-2 con datastore **directory-based** en `/backup/pbs` (50 GB libres en rootfs). ZFS queda pendiente cuando se agregue disco físico. Ver notas de desviación en design.md.
- [x] 1.4 Generar encryption key en cada nodo (`/root/.pve-encryption-key`) — 4 nodos completado (pve-desa01-04). 64 chars hex, permisos 400.
- [x] 1.5 Agregar PBS como storage en `/etc/pve/storage.cfg` — Añadido storage `pbs` tipo PVE apuntando a 192.168.1.31:8007, datastore `pve-gidas`, encryption-key configurada, fingerprint verificado.
- [x] 1.6 Configurar jobs diarios 22:00, retención 7+4+3, prune + GC semanal — Backup job diario 22:00 (snapshot, zstd). Prune semanal (sun 02:00, keep 7+4+3). Verify semanal (sun 04:00). GC semanal (sun 03:00 vía cron).
- [x] 1.7 Verificar escenarios — PBS activo en :8007 ✅, storage visible en cluster ✅, cifrado activo en storage.cfg ✅, jobs configurados ✅

## Fase 2: Storage ZFS (P1)

- [x] 2.1 Mover VMs a nodo vecino vía live migration, nodo por nodo — `scripts/f2-storage-zfs/02-migrate-to-neighbor.sh`
- [x] 2.2 Destruir VG LVM y crear pool: `zpool create -o ashift=12 <pool> /dev/sdX` — `scripts/f2-storage-zfs/03-create-zpool.sh`
- [x] 2.3 Activar `compression=zstd`, `atime=off` en cada pool ZFS — `scripts/f2-storage-zfs/04-configure-zfs.sh`
- [x] 2.4 Configurar `zfs_arc_max` (50% RAM) en `/etc/modprobe.d/zfs.conf` — `scripts/f2-storage-zfs/04-configure-zfs.sh`
- [x] 2.5 Mover VMs de vuelta al nodo original sobre ZFS — `scripts/f2-storage-zfs/05-migrate-back.sh`
- [x] 2.6 Configurar replicación asíncrona pares fijos (RPO 15min/1h, bwlimit 500M) — `scripts/f2-storage-zfs/06-replication.sh`
- [x] 2.7 Verificar: `zpool status`, `pvesr list`, `cat /sys/module/zfs/parameters/zfs_arc_max` — `scripts/f2-storage-zfs/07-verify.sh`

## Fase 3: Red (P2)

- [ ] 3.1 Agregar VLAN 10 (`vmbr0.10`) en `/etc/network/interfaces` de cada nodo
- [ ] 3.2 Configurar link1 redundante en `corosync.conf` apuntando a VLAN 10
- [ ] 3.3 Reiniciar corosync nodo por nodo y verificar con `corosync-cfgtool -s`
- [ ] 3.4 Configurar bonding LACP en pve-desa04 (eno1-4 → bond0 → vmbr0)
- [ ] 3.5 Crear reglas firewall de cluster en `/etc/pve/firewall/cluster.fw`
- [ ] 3.6 Verificar: link1 UP, bonding operativo (`/proc/net/bonding/bond0`)

## Fase 4: Optimización VMs (P2)

- [ ] 4.1 VMs Linux: `qm set <vmid> --cpu host` (evitar cross-nodo)
- [ ] 4.2 VMs >4 vCPUs: `qm set <vmid> --numa 1`
- [ ] 4.3 VirtIO SCSI Single con `iothread=1` en discos de VMs
- [ ] 4.4 Revisar ballooning mínimo (>1 GB) en VMs con memoria dinámica
- [ ] 4.5 Verificar: `qm config <vmid> | grep -E "cpu:|numa:|cache:"`

## Fase 5: Monitoreo (P2)

- [ ] 5.1 Instalar Prometheus + Grafana en CT sg-monitoring (pve-ad, CT 205)
- [ ] 5.2 Instalar `pve_exporter` (9221) + `node_exporter` (9100) en cada nodo
- [ ] 5.3 Configurar scrape targets en `/etc/prometheus/pve.yml`
- [ ] 5.4 Importar dashboard Grafana ID 10347 con datasource Prometheus
- [ ] 5.5 Configurar Alertmanager: quorum, ZFS errors, disco>80%, backup fails
- [ ] 5.6 Verificar: `curl localhost:9221/pve`, dashboard carga, alertas disparan

## Fase 6: Documentación y Cierre

- [ ] 6.1 Escribir runbook de restauración de backups desde PBS
- [ ] 6.2 Escribir runbook de recuperación ZFS (pool corrupto, ARC tuning)
- [ ] 6.3 Actualizar `openspec/secrets/proxmox.yaml` con endpoints PBS
- [ ] 6.4 Verificación cruzada contra criterios de éxito del diseño
