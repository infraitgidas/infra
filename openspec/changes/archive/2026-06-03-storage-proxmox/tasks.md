# Tareas — Almacenamiento Compartido Proxmox

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | ~720 (6 scripts + tasks) |
| 400-line budget risk | High |
| Chained PRs recommended | Yes |
| Suggested split | PR 1 (foundation) → PR 2 (DR) → PR 3 (verify) |
| Delivery strategy | ask-on-risk |
| Chain strategy | feature-branch-chain |

Decision needed before apply: Yes — resolved: feature-branch-chain (PR 1 foundation → PR 2 DR → PR 3 verify)
Chained PRs recommended: Yes
Chain strategy: feature-branch-chain
400-line budget risk: High

### Suggested Work Units

| Unit | Goal | Likely PR | Notes |
|------|------|-----------|-------|
| 1 | Foundation scripts (env, datasets, NFS, Samba) | PR 1 | Base: `feature/storage-proxmox`. Crea 00-env, 01-create-datasets, 02-configure-nfs, 03-configure-samba |
| 2 | DR scripts (replication, snapshots, failover/back) | PR 2 | Base: PR 1 branch. Crea 04-replication, failover-to-desa02, failback-to-desa03 |
| 3 | Verification script | PR 3 | Base: PR 2 branch. Crea verify.sh |

## Phase 1: Backup y Preparación (PR 1) ✅

- [x] **T-01**: Backup PBS full cluster — `pvesh create /cluster/backup --all 1 --mode snapshot`
  Dep: — | Verif: `pvesm list backup` | Root: todos los nodos
  **Script**: `survey.sh` documenta comando + verificación

- [x] **T-02**: Inventario discos — `lsblk`, `blkid`, `zpool status`, `lvs` en pve-desa02/03
  Dep: — | Verif: documentar estado actual | Root: pve-desa02/03
  **Script**: `survey.sh` ejecuta inventario en ambos nodos

## Phase 2: Scripts Foundation (PR 1) ✅

- [x] **T-03**: `00-env.sh` — variables de entorno (IPs, discos, pool names, ARC) siguiendo patrón `scripts/f2-storage-zfs/00-env.sh`
  Dep: — | Archivos: `scripts/f3-shared-storage/00-env.sh`

- [x] **T-04**: `01-create-datasets.sh` — pool shared-zfs mirror + 6 datasets (vms, kubernetes, gitlab, registry, backups, samba) con compression=zstd, atime=off, recordsize por dataset
  Dep: T-03 | Archivos: `scripts/f3-shared-storage/01-create-datasets.sh`

- [x] **T-05**: `02-configure-nfs.sh` — `/etc/exports` con rw,async,no_subtree_check; sysctl 90-nfs.conf; `exportfs -ra`; pvesm add nfs para cada dataset
  Dep: T-04 | Archivos: `scripts/f3-shared-storage/02-configure-nfs.sh`

- [x] **T-06**: `03-configure-samba.sh` — instalar samba, smb.conf SMB3, grupo samba-users, systemctl enable smbd
  Dep: T-03 | Archivos: `scripts/f3-shared-storage/03-configure-samba.sh`

## Phase 3: Migración pve-desa03 (PR 1) ✅

- [x] **T-07**: Migrar VMs/CTs de pve-desa03 → pve-desa02 — `qm migrate` + `pct migrate` de todo lo running
  Dep: T-01, T-02 | Verif: `qm list --all` vacío en pve-desa03 | Root: pve-desa03
  **Script**: `04-migrate-pve-desa03.sh` — orquesta migración + llama resto de scripts

- [x] **T-08**: Destruir vm-storage + limpiar sda/sdc — vgremove vm-storage, sgdisk -Z, wipefs, backup /etc/exports
  Dep: T-07 | Verif: `lsblk` sin particiones | Root: pve-desa03
  **Script**: `01-create-datasets.sh` (steps 3-5) + orquestado por `04-migrate-pve-desa03.sh`

- [x] **T-09**: Ejecutar T-04 en pve-desa03 — `zpool create shared-zfs mirror sda sdc` + datasets
  Dep: T-08 | Verif: `zpool status` mirror ONLINE, `zfs list -r` 6 datasets | Root: pve-desa03
  **Script**: `01-create-datasets.sh` (steps 6-7) + orquestado por `04-migrate-pve-desa03.sh`

- [x] **T-10**: Ejecutar T-05 — exports + sysctl + pvesm add nfs en todos los nodos
  Dep: T-09 | Verif: `showmount -e pve-desa03` desde c/nodo exports listados | Root: todos
  **Script**: `02-configure-nfs.sh` + orquestado por `04-migrate-pve-desa03.sh`

- [x] **T-11**: ARC pve-desa03 (15GB→7.5GB) — zfs_arc_max=8053063680 en `/etc/modprobe.d/zfs.conf`
  Dep: T-09 | Verif: `cat /sys/module/zfs/parameters/zfs_arc_max` | Root: pve-desa03
  **Script**: `04-migrate-pve-desa03.sh` (step 6)

## Phase 4: Migración pve-desa02 (PR 2) ✅

- [x] **T-12**: Migrar VMs pve-desa02 → shared NFS — `qm migrate --target-storage shared-vms`
  Dep: T-10 | Verif: VMs en pve-desa02 usan shared-vms | Root: pve-desa02
  **Script**: `05-migrate-pve-desa02.sh` (step 2)

- [x] **T-13**: Destruir LVM local-storage → crear local-zfs mirror sdb+sdc + datasets vms y backup-dr
  Dep: T-12 | Verif: `zpool status local-zfs` mirror ONLINE | Root: pve-desa02
  **Script**: `05-migrate-pve-desa02.sh` (steps 3-4)

- [x] **T-14**: ARC pve-desa02 (10GB→5GB) — zfs_arc_max=5368709120
  Dep: T-13 | Verif: `cat /sys/module/zfs/parameters/zfs_arc_max` | Root: pve-desa02
  **Script**: `05-migrate-pve-desa02.sh` (step 5)

- [x] **T-15**: Agregar local-zfs como zfspool — `pvesm add zfspool local-zfs --pool local-zfs --nodes pve-desa02`
  Dep: T-13 | Verif: `pvesm status` local-zfs activo | Root: cualquier nodo
  **Script**: `05-migrate-pve-desa02.sh` (step 6)

## Phase 5: DR, Snapshots, Samba (PR 2) ✅

- [x] **T-16**: `04-replication.sh` — replicate-shared-to-dr.sh (zfs send/recv incremental) + systemd service/timer + sanoid.conf retención 7 días
  Dep: T-03 | Archivos: `scripts/f3-shared-storage/04-replication.sh`

- [x] **T-17**: `failover-to-desa02.sh` — promover DR pool, export NFS desde pve-desa02, actualizar server en storages
  Dep: T-03 | Archivos: `scripts/f3-shared-storage/failover-to-desa02.sh`

- [x] **T-18**: `failback-to-desa03.sh` — sincronizar datos de vuelta (send inverso), re-montar NFS original, reanudar replicación
  Dep: T-03 | Archivos: `scripts/f3-shared-storage/failback-to-desa03.sh`

- [x] **T-19**: Configurar Samba pve-desa03 — ejecutar T-06, `smbpasswd -a samba-shared`, chown dataset
  Dep: T-09 | Verif: `smbclient -L //localhost` lista recurso shared | Root: pve-desa03
  **Script**: `05-migrate-pve-desa02.sh` (step 7)

- [x] **T-20**: Configurar replicación + sanoid — copiar T-16 scripts a pve-desa02/03, habilitar timer, sanoid.timer
  Dep: T-13, T-19 | Verif: timer activo, sanoid --list muestra snapshots | Root: pve-desa02/03
  **Script**: `05-migrate-pve-desa02.sh` (step 8)

## Phase 6: Verificación (PR 3)

- [x] **T-21**: `verify.sh` — full check: pools, datasets, NFS, Samba, ARC, snapshots, replicación (patrón `07-verify.sh` de F2)
  Dep: T-05, T-16 | Archivos: `scripts/f3-shared-storage/verify.sh`

- [x] **T-22**: Ejecutar verify.sh completo + live migration test + throughput ≥ 80 MB/s + DR failover dry-run
  Dep: T-11, T-14, T-15, T-20, T-21 | Verif: todos PASS | Root: todos los nodos
