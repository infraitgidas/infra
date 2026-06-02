# Diseño: Optimización del Cluster Proxmox pve-gidas

## Enfoque Técnico

Ejecución secuencial en 5 fases independientes y reversibles. F1 (backups) primero por ser el riesgo más crítico — sin backups, cualquier cambio estructural es irrecuperable. Cada fase transforma el cluster de un estado "operativo pero frágil" a uno robusto con redundancia, integridad y monitoreo.

## Decisiones de Arquitectura

### F1 — Backups

| Opción | Tradeoff | Decisión |
|--------|----------|----------|
| PBS en pve-ad (nodo separado — 192.168.1.31, no 192.168.1.15 como indicaba la documentación original) | No consume recursos del cluster; PVE 9 incompatible para unirse pero OK para PBS standalone | ✅ **Elegido** — datastore directory-based temporal (PBS 4.0.11-2, /backup/pbs). Pendiente agregar disco para ZFS. |
| PBS en VM dentro del cluster | Compite por recursos; si falla el nodo anfitrión, pierdo backups y VMs | ❌ Descartado |
| PBS en VM en pve-desa03 (NFS) | Mismo SPOF del NFS actual | ❌ Descartado |

### F2 — Storage ZFS

| Opción | Tradeoff | Decisión |
|--------|----------|----------|
| Migración nodo por nodo: mover VMs → destruir LVM → crear ZFS | Downtime por VM durante migración; requiere storage temporal en nodo vecino | ✅ **Elegido** |
| Agregar discos nuevos ZFS + copiar datos | Requiere HW adicional | ❌ Descartado |
| ZFS sobre LVM (loopahead) | Pérdida de integridad ZFS (no accede directo al disco) | ❌ Descartado |

### F3 — Red

| Opción | Tradeoff | Decisión |
|--------|----------|----------|
| VLAN 10 over vmbr0 (tagged) para Corosync | Sin NIC extra necesaria; comparte medio físico pero segrega lógicamente | ✅ **Elegido** |
| NIC física dedicada para Corosync | Solo pve-desa04 tiene NICs libres; los demás tienen 1 sola | ❌ Inviable |
| Bond LACP en pve-desa04 | Agrega 4 NICs; requiere switch configurado (puertos en LACP) | ✅ **Elegido** |

### F4 — Optimización VMs

| Opción | Tradeoff | Decisión |
|--------|----------|----------|
| CPU type `host` en VMs Linux | Pierde compatibilidad migración cross-nodo (no aplica — sin shared storage) | ✅ **Elegido** |
| NUMA habilitado en VMs >4 vCPUs | Mejora rendimiento memoria en hosts multi-socket | ✅ **Elegido** |
| Cache `none` sobre `writethrough` | writeback=none: integridad garantizada; writethrough: seguro pero más lento | ✅ **none** para VM 102 DC2 |

### F4 — Monitoreo

| Opción | Tradeoff | Decisión |
|--------|----------|----------|
| Prometheus + PVE Exporter en CT sg-monitoring (pve-ad) | Reutiliza CT 205 existente (2 GB RAM); fuera del cluster, sobrevive a fallo del cluster | ✅ **Elegido** |
| Prometheus dentro del cluster | Cae con el cluster — no puede alertar cuando más se necesita | ❌ Descartado |

## Flujo de Datos

```
F1 — Backups:
  Nodo PVE ──cifrado client-side──→ PBS (pve-ad:8007)
    │                                    │
    └── encryption key (secrets/)        └── Datastore ZFS (zstd)

F2 — Replicación ZFS:
  pve-desa01 ──snap──→ pve-desa02  (RPO 15min/1h, bwlimit 500M)
  pve-desa03 ──snap──→ pve-desa04

F3 — Corosync redundante:
  link0: vmbr0 (192.168.1.0/24) ── datos
  link1: vmbr0.10 (VLAN 10)     ── heartbeat

F4 — Monitoreo:
  pve-desa0[1-4]:9221 ──scrape──→ sg-monitoring:9090 ──query──→ Grafana:3000
  pve-desa0[1-4]:9100 ──scrape──→ (node_exporter)             ID 10347
```

## Cambios de Archivos

| Archivo | Acción | Descripción |
|---------|--------|-------------|
| `/etc/pve/storage.cfg` | Modificar | +datastore PBS, +pools ZFS locales |
| `/etc/network/interfaces` (c/nodo) | Modificar | +vmbr0.10 VLAN 10; bond en pve-desa04 |
| `/etc/pve/corosync.conf` | Modificar | +link1 (VLAN 10) redundante |
| `/etc/pve/firewall/cluster.fw` | Crear | Reglas por segmento (VLAN 10, mgmt) |
| `/etc/modprobe.d/zfs.conf` | Crear | `zfs_arc_max` = 50% RAM |
| `/etc/pve/jobs.cfg` | Modificar | +jobs backup diarios, retención 7+4+3 |
| `/etc/pve/datacenter.cfg` | Modificar | +fronter director PBS |
| `/root/.pve-encryption-key` | Crear | Clave de cifrado client-side |
| `/etc/prometheus/pve.yml` | Crear | Targets PVE Exporter por nodo |
| `openspec/secrets/proxmox.yaml` | Modificar | Endpoints PBS, encryption key ref |

## Configuraciones Clave

```bash
# ARC: 50% de RAM (ej: pve-desa01 con 15GB → ~7.5GB)
echo "options zfs zfs_arc_max=8053063680" > /etc/modprobe.d/zfs.conf

# Replicación (ejecutar en nodo origen)
pvesr create-local-job <vmid> pve-desa0X --rate 524288000 --schedule "*/15 * * * *"

# Backup job (vía API o UI)
pvesh create /cluster/backup --vmid <list> --storage pbs \
  --schedule "0 22 * * *" --compress zstd --mode snapshot \
  --prune-backup-daily 7 --prune-backup-weekly 4 --prune-backup-monthly 3
```

## Estrategia de Verificación (post-aplicación manual)

| Componente | Qué Verificar | Comando / Método |
|------------|--------------|------------------|
| PBS | Datastore accesible desde todos los nodos | `pvesh get /storage` — PBS listado |
| Backups | Job ejecutado, backup existente | `proxmox-backup-manager snapshot list` |
| Retención | Prune conserva 7+4+3 | Verificar conteo de snapshots post-prune |
| ZFS pool | compression=zstd, ashift=12 | `zpool get all <pool> \| grep -E "ashift|compression"` |
| ZFS ARC | Límite aplicado | `cat /sys/module/zfs/parameters/zfs_arc_max` |
| Replicación | Job activo, snap replicados | `pvesr list` |
| Corosync link1 | Segundo link operativo | `corosync-cfgtool -s` — link 1 en estado UP |
| Bonding | LACP activo en pve-desa04 | `cat /proc/net/bonding/bond0` |
| CPU host | VM config con `cpu: host` | `qm config <vmid> \| grep cpu` |
| NUMA | VM config con `numa: 1` | `qm config <vmid> \| grep numa` |
| Cache=0 | VM 102 con `cache=none` | `qm config 102 \| grep cache` |
| PVE Exporter | Métricas en Prometheus | `curl http://<nodo>:9221/pve` |
| Dashboard | Grafana ID 10347 cargado | Verificar datasource + panels |

## Plan de Migración / Rollout

### Fase 1 — Backups (P0)
1. Instalar PBS en pve-ad: `dpkg -i proxmox-backup-server_4.0.11-2_amd64.deb` (desde repos trixie)
2. Crear datastore directory-based en `/backup/pbs` — **DESVIACIÓN TEMPORAL**: El diseño original especifica ZFS con `compression=zstd`, pero pve-ad no tiene un segundo disco físico disponible. Se optó por datastore directory-based (PBS maneja compresión y deduplicación a nivel de chunk). Se agregará disco ZFS en el futuro.
3. Generar encryption key en cada nodo → `/root/.pve-encryption-key`
4. Agregar PBS como storage en `/etc/pve/storage.cfg`
5. Configurar jobs diarios 22:00, retención 7+4+3, prune + GC semanal
6. **Rollback**: eliminar datastore PBS, remover storage de storage.cfg

### Fase 2 — Storage ZFS (P1)
1. Por cada nodo: mover VMs a nodo vecino via live migration
2. Destruir VG LVM, crear pool ZFS: `zpool create -o ashift=12 <pool> /dev/sdX`
3. Activar `compression=zstd`, `atime=off`
4. Configurar `zfs_arc_max` en `/etc/modprobe.d/zfs.conf`
5. Mover VMs de vuelta al nodo original sobre ZFS
6. Configurar replicación asíncrona entre pares (pares fijos)
7. **Rollback**: eliminar pool, restaurar LVM desde backup de VMs

### Fase 3 — Red (P2)
1. Agregar VLAN 10 en `/etc/network/interfaces` de cada nodo
2. Configurar link1 en `corosync.conf` → reiniciar corosync nodo por nodo
3. Configurar bonding LACP en pve-desa04 (eno1-4 → bond0 → vmbr0)
4. Crear reglas de firewall de cluster en `/etc/pve/firewall/cluster.fw`
5. **Rollback**: restaurar interfaces originales, revertir corosync.conf

### Fase 4 — Optimización VMs (P2)
1. VM 102: `qm set 102 --scsi0 cache=none` (crítico, hacer primero)
2. VMs Linux con `cpu: host` — verificar que no necesitan migración cross-nodo
3. VMs >4 vCPUs: `qm set <vmid> --numa 1`
4. Decidir destino de VMs Windows stopped (activar o `qm destroy`)
5. **Rollback**: revertir CPU type, NUMA, cache por VM

### Fase 4 bis — Monitoreo (P2)
1. En CT sg-monitoring (pve-ad, CT 205): instalar Prometheus + Grafana
2. En cada nodo del cluster: instalar `pve_exporter` + `node_exporter`
3. Configurar scrape targets en Prometheus
4. Importar dashboard Grafana ID 10347
5. Configurar Alertmanager con reglas (quorum, ZFS, disk>80%, backup fails)
6. **Rollback**: detener exporters, remover targets de Prometheus

## Preguntas Abiertas

- [ ] **VMs Windows stopped (100, 101, 102)**: ¿activar o eliminar? Ocupan 9 GB RAM sin uso. VM 102 (DC2) tiene cache writeback — si se elimina, el riesgo C3 desaparece. Decidir antes de F1 para incluir en backups o no.
- [ ] **Ancho de banda replicación**: 500 Mbps sobre 1 GbE compartido con tráfico de VMs — ¿se necesita QoS en el switch Mikrotik?
- [ ] **pve-desa02 HDD (932 GB)**: ZFS sobre HDD sin ashift=12 puede ser lento en writes. ¿Usar solo para datos fríos con `recordsize=1M`?
- [x] **IP de pve-ad**: Documentación indicaba 192.168.1.15, IP real es **192.168.1.31**. Corregido.
- [x] **Disco para PBS ZFS**: pve-ad tiene 1 solo SSD de 223 GB. Se resolvió con datastore directory-based temporal `/backup/pbs`. PBS 4.0.11-2 maneja compresión/dedup nativa. Pendiente agregar disco SSD para migrar a ZFS.
- [ ] **Canales de alerta**: ¿email, Slack, Telegram? Definir antes de configurar Alertmanager en F4.
