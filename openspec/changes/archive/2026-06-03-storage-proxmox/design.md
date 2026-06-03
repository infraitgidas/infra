# Diseño Técnico — Almacenamiento Compartido Proxmox

## 1. Topología Final

```
                  Cluster Proxmox pve-gidas — 1 GbE plana

pve-desa02 (10 GB RAM)               pve-desa03 (15 GB RAM)
┌────────────────────────┐           ┌────────────────────────┐
│ local-zfs (mirror)     │           │ shared-zfs (mirror)    │
│ ├── sdb (932G) ←──┐    │           │ ├── sda (932G) ←──┐    │
│ ├── sdc (932G) ←──┤    │           │ ├── sdc (932G) ←──┤    │
│ └── 932G usable    │    │           │ └── 932G usable    │    │
│                    │    │           │                    │    │
│ Datasets:          │    │           │ Datasets+NFS:     │    │
│ ├── local-zfs/vms  │    │           │ ├── vms/    (600G) │    │
│ └── local-zfs/     │    │           │ ├── kubernetes(100G)│    │
│     backup-dr      │    │           │ ├── gitlab/  (100G)│    │
│        ↑           │    │           │ ├── registry/ (50G)│    │
│        │ DR replica│    │           │ ├── backups/  (50G)│    │
│        └─── desde ─┘    │           │ └── samba/    (32G)│    │
└────────────────────────┘           └────────┬───────────┘
                                               │
                               ┌───────────────┴──────────────┐
                               │  NFS exports                │
                               │  ─────────────────────────── │
                               │  /shared-zfs/{dataset}       │
                               │  → pve-desa01,02,03,04      │
                               └──────────────────────────────┘
```

**Red**: 1 GbE compartida (Corosync + NFS + replicación + VMs). Sin red dedicada.

---

## 2. Decisiones de Arquitectura

| Opción | Alternativa | Tradeoff | Decisión |
|--------|------------|----------|----------|
| **Mirror vdev** vs stripe | Stripe da 2 TB sin redundancia | Mirror tolera 1 fallo de disco, stripe no | **Mirror** — redundancia sobre capacidad |
| **NFS async** vs sync | Sync es seguro pero mata performance en 1 GbE | async da ~5x más throughput, riesgo mínimo (UPS + ZFS previene corrupción) | **async** — bottleneck es red, no discos |
| **Replicación zfs send/recv** vs pvesr | pvesr replica a nivel VM, send/recv a nivel dataset | Para DR de datasets compartidos, send/recv es la herramienta correcta | **zfs send/recv** — replica datasets completos |
| **Samba en host** vs CT separado | CT aísla, host es más simple | Solo 32 GB, un solo recurso, overhead de CT no justifica | **Samba en pve-desa03 host** |
| **ARC 50% RAM** vs default (50%) | Default ya es 50% | Solo aplicar si cambia por tuning | **50%** — confirmar con `zfs_arc_max` |

---

## 3. Migración — pve-desa03 (shared-zfs)

### Estado actual
```
sda: particionado (sda1=800G NFS, sda2=131.5G ISO) → datos NFS existentes
sdc: LVM thin vm-storage → VMs/CTs de pve-desa03
```

### Paso a paso

```bash
# ── 3.1 Backup total a PBS (PRE-REQUISITO) ──
pvesh create /cluster/backup --all 1 --mode snapshot --storage pbs-datastore

# ── 3.2 Migrar VMs/CTs de pve-desa03 a pve-desa02 ──
# Identificar VMs/CTs en pve-desa03
ssh root@pve-desa03 "qm list --all && pct list"

# Live migrate VMs (si están running)
for VMID in $(ssh root@pve-desa03 "qm list 2>/dev/null | grep running | awk '{print \$1}'"); do
    ssh root@pve-desa03 "qm migrate ${VMID} pve-desa02"
done

# Migrar CTs
for CTID in $(ssh root@pve-desa03 "pct list 2>/dev/null | awk 'NR>1{print \$1}'"); do
    ssh root@pve-desa03 "pct migrate ${CTID} pve-desa02 --restart"
done

# ── 3.3 Backup datos NFS existentes ──
ssh root@pve-desa03 "tar czf /root/nfs-data-$(date +%Y%m%d).tar.gz -C /mnt/nfs-storage ."
scp root@pve-desa03:/root/nfs-data-*.tar.gz /tmp/
# Opcional: copiar a PBS

# ── 3.4 Destruir vm-storage VG y limpiar sdc ──
ssh root@pve-desa03 bash -c '
    set -e
    # Verificar que no haya VMs/CTs remanentes
    if [ "$(qm list --all 2>/dev/null | tail -n +2 | wc -l)" -gt 0 ] || \
       [ "$(pct list 2>/dev/null | tail -n +2 | wc -l)" -gt 0 ]; then
        echo "ERROR: Aún hay VMs/CTs en pve-desa03"
        exit 1
    fi
    # Destruir VG
    vgremove -f vm-storage 2>/dev/null || true
    sgdisk -Z /dev/sdc
    wipefs -a /dev/sdc
'

# ── 3.5 Limpiar sda (parar NFS, destruir particiones) ──
ssh root@pve-desa03 bash -c '
    set -e
    systemctl stop nfs-server nfs-kernel-server
    umount -l /mnt/nfs-storage 2>/dev/null || true
    umount -l /mnt/iso-storage 2>/dev/null || true
    cp /etc/exports /etc/exports.bak.$(date +%Y%m%d)
    sgdisk -Z /dev/sda
    wipefs -a /dev/sda
    partprobe /dev/sda
'

# ── 3.6 Crear pool ZFS mirror shared-zfs ──
ssh root@pve-desa03 \
  "zpool create -f -o ashift=12 \
     -O compression=zstd -O atime=off -O xattr=sa \
     shared-zfs mirror /dev/sda /dev/sdc"

# Verificar
ssh root@pve-desa03 "zpool status shared-zfs"

# ── 3.7 Crear datasets ──
ssh root@pve-desa03 bash -c '
    zfs create -o recordsize=128K  -o quota=600G shared-zfs/vms
    zfs create -o quota=100G shared-zfs/kubernetes
    zfs create -o quota=100G shared-zfs/gitlab
    zfs create -o quota=50G  shared-zfs/registry
    zfs create -o quota=50G  -o recordsize=1M shared-zfs/backups
    zfs create -o quota=32G  shared-zfs/samba
    zfs list -r shared-zfs
'

# ── 3.8 Configurar ARC (15 GB RAM → 7.5 GB) ──
ssh root@pve-desa03 \
  "echo 'options zfs zfs_arc_max=8053063680' > /etc/modprobe.d/zfs.conf"
```

---

## 4. Migración — pve-desa02 (local-zfs mirror + DR)

### Estado actual
```
sdb: LVM thin local-storage → VMs/CTs
sdc: LIBRE
```

### Paso a paso

```bash
# ── 4.1 Migrar VMs/CTs de local-storage (sdb) a shared-zfs (NFS) ──
# Pre-requisito: shared-zfs NFS ya agregado en Proxmox (paso 6)
for VMID in $(ssh root@pve-desa02 "qm list 2>/dev/null | grep -v stopped | awk 'NR>1{print \$1}'"); do
    ssh root@pve-desa02 "qm migrate ${VMID} pve-desa03 --target-storage shared-vms"
done

# ── 4.2 Verificar que local-storage está vacío ──
ssh root@pve-desa02 "lvs local-storage/"

# ── 4.3 Destruir LVM thin local-storage en sdb ──
ssh root@pve-desa02 bash -c '
    set -e
    lvremove -f local-storage/data 2>/dev/null || true
    vgremove -f local-storage 2>/dev/null || true
    pvremove -f /dev/sdb 2>/dev/null || true
    sgdisk -Z /dev/sdb
    wipefs -a /dev/sdb
'

# ── 4.4 Crear pool ZFS mirror local-zfs con sdb + sdc ──
ssh root@pve-desa02 \
  "zpool create -f -o ashift=12 \
     -O compression=zstd -O atime=off -O xattr=sa \
     local-zfs mirror /dev/sdb /dev/sdc"

# Crear datasets locales
ssh root@pve-desa02 bash -c '
    zfs create local-zfs/vms
    zfs create local-zfs/backup-dr
    zfs list -r local-zfs
'

# ── 4.5 Configurar ARC (10 GB RAM → 5 GB) ──
ssh root@pve-desa02 \
  "echo 'options zfs zfs_arc_max=5368709120' > /etc/modprobe.d/zfs.conf"

# ── 4.6 Migrar VMs de vuelta (opcional — pueden quedar en shared) ──
```

---

## 5. Configuración NFS

### `/etc/exports` en pve-desa03

```bash
ssh root@pve-desa03 bash -c "
cat > /etc/exports << 'EOF'
/shared-zfs/vms        192.168.1.0/24(rw,async,no_subtree_check,no_wdelay,crossmnt,fsid=100)
/shared-zfs/kubernetes 192.168.1.0/24(rw,async,no_subtree_check,no_wdelay,crossmnt,fsid=101)
/shared-zfs/gitlab     192.168.1.0/24(rw,async,no_subtree_check,no_wdelay,crossmnt,fsid=102)
/shared-zfs/registry   192.168.1.0/24(rw,async,no_subtree_check,no_wdelay,crossmnt,fsid=103)
/shared-zfs/backups    192.168.1.0/24(rw,async,no_subtree_check,no_wdelay,crossmnt,fsid=104)
/shared-zfs/samba      127.0.0.1(rw,async,no_subtree_check)   # solo localhost para Samba
EOF
exportfs -ra
showmount -e
"
```

### NFS kernel tuning

```bash
ssh root@pve-desa03 bash -c '
cat >> /etc/sysctl.d/90-nfs.conf << EOF
# NFS tuning for async exports over 1 GbE
sunrpc.tcp_slot_table_entries=128
sunrpc.tcp_max_slot_table_entries=128
EOF
sysctl -p /etc/sysctl.d/90-nfs.conf
'
```

---

## 6. Integración Proxmox (pvesm)

Ejecutar **desde un nodo del cluster** (PMXCFS replica a todos):

```bash
# Agregar storage NFS para VMs (live migration habilitada)
pvesm add nfs shared-vms \
  --server 192.168.1.13 \
  --export /shared-zfs/vms \
  --path /mnt/pve/shared-vms \
  --content images,rootdir \
  --options vers=4.2,hard,intr,noatime

# Kubernetes PVs
pvesm add nfs shared-k8s \
  --server 192.168.1.13 \
  --export /shared-zfs/kubernetes \
  --path /mnt/pve/shared-k8s \
  --content images,rootdir

# GitLab
pvesm add nfs shared-gitlab \
  --server 192.168.1.13 \
  --export /shared-zfs/gitlab \
  --path /mnt/pve/shared-gitlab \
  --content images,rootdir

# Registry
pvesm add nfs shared-registry \
  --server 192.168.1.13 \
  --export /shared-zfs/registry \
  --path /mnt/pve/shared-registry \
  --content images,rootdir

# Backups
pvesm add nfs shared-backups \
  --server 192.168.1.13 \
  --export /shared-zfs/backups \
  --path /mnt/pve/shared-backups \
  --content backup

# Agregar local-zfs como zfspool storage (pve-desa02)
pvesm add zfspool local-zfs \
  --pool local-zfs \
  --content images,rootdir \
  --sparse 1 \
  --nodes pve-desa02

# Verificar
pvesm status
```

---

## 7. Configuración Samba

```bash
# ── Instalar ──
ssh root@pve-desa03 "apt-get install -y samba"

# ── smb.conf ──
ssh root@pve-desa03 bash -c "
cat > /etc/samba/smb.conf << 'EOF'
[global]
   workgroup = WORKGROUP
   server string = pve-desa03 Samba
   server role = standalone server
   security = user
   map to guest = bad user
   min protocol = SMB3
   max protocol = SMB3
   socket options = TCP_NODELAY IPTOS_LOWDELAY
   load printers = no
   printing = bsd
   printcap name = /dev/null
   disable spoolss = yes

[shared]
   path = /shared-zfs/samba
   browseable = yes
   read only = no
   guest ok = no
   valid users = @samba-users
   create mask = 0755
   directory mask = 0755
   force user = root
   force group = samba-users
EOF
"

# ── Crear grupo y usuario ──
ssh root@pve-desa03 bash -c '
    groupadd --force samba-users
    # Crear usuario samba-shared (cambiar password)
    useradd -M -s /usr/sbin/nologin -g samba-users samba-shared 2>/dev/null || true
    smbpasswd -a samba-shared
    chown root:samba-users /shared-zfs/samba
    chmod 0775 /shared-zfs/samba
    systemctl restart smbd
    systemctl enable smbd
    smbstatus
'

# ── Montaje desde clientes Linux ──
# /etc/fstab:
# //192.168.1.13/shared /mnt/shared cifs vers=3.0,credentials=/etc/samba/credentials,uid=1000,gid=1000,file_mode=0755,dir_mode=0755,noauto 0 0
```

---

## 8. Replicación DR (shared-zfs → local-zfs)

Script de replicación que corre **en pve-desa02** (pull desde pve-desa03):

```bash
#!/bin/bash
# /usr/local/bin/replicate-shared-to-dr.sh
# Ejecutar como: root@ pve-desa02

SRC="root@192.168.1.13"
DR_POOL="local-zfs/backup-dr"
BW_LIMIT=$((500 * 1024 * 1024))  # 500 Mbps en bytes/s

# Datasets a replicar
DATASETS="vms kubernetes gitlab registry backups"

for ds in $DATASETS; do
    SRC_FS="shared-zfs/${ds}"
    DST_FS="${DR_POOL}/${ds}"
    
    # Tomar snapshot en origen
    SNAP_NAME="dr-$(date +%Y%m%d-%H%M%S)"
    ssh ${SRC} "zfs snapshot ${SRC_FS}@${SNAP_NAME}"
    
    # Determinar si es inicial o incremental
    LATEST_SNAP=$(zfs list -H -o name -t snapshot -r ${DST_FS} 2>/dev/null | tail -1)
    
    if [ -z "${LATEST_SNAP}" ]; then
        # Primera vez: full send
        echo "Initial sync: ${SRC_FS} → ${DST_FS}"
        ssh ${SRC} "zfs send -w ${SRC_FS}@${SNAP_NAME}" | \
            zfs receive -F ${DST_FS}
    else
        # Incremental
        PREV_SNAP=$(echo ${LATEST_SNAP} | sed 's/.*@//')
        echo "Incremental: ${SRC_FS}@${PREV_SNAP} → ${SNAP_NAME}"
        ssh ${SRC} "zfs send -w -i @${PREV_SNAP} ${SRC_FS}@${SNAP_NAME}" | \
            zfs receive -F ${DST_FS}
    fi
    
    # Limpiar snapshots DR en origen (solo retener últimos 3)
    ssh ${SRC} "zfs list -H -o name -t snapshot -r ${SRC_FS} | grep 'dr-' | head -n -3 | xargs -r zfs destroy"
done
```

### Systemd timer (diario a las 02:00)

```bash
# /etc/systemd/system/zfs-replicate-dr.service
cat > /etc/systemd/system/zfs-replicate-dr.service << 'EOF'
[Unit]
Description=ZFS DR replication shared-zfs → local-zfs
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/replicate-shared-to-dr.sh
Nice=10
IOSchedulingClass=idle
EOF

# /etc/systemd/system/zfs-replicate-dr.timer
cat > /etc/systemd/system/zfs-replicate-dr.timer << 'EOF'
[Unit]
Description=Daily ZFS DR replication

[Timer]
OnCalendar=daily
RandomizedDelaySec=30min
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now zfs-replicate-dr.timer
```

**RPO objetivo**: 24h (diario). Ancho de banda limitado por `pv -L 500m` si se necesita throttling adicional.

---

## 9. Snapshots

Usar **sanoid** (mismo enfoque que F2). Config en pve-desa03:

```bash
# /etc/sanoid/sanoid.conf en pve-desa03
[shared-zfs]
    use_template = production
    recursive = yes

[template_production]
    daily = 7
    hourly = 0
    monthly = 0
    yearly = 0
    autosnap = yes
    autoprune = yes
```

```bash
# Instalar sanoid
ssh root@pve-desa03 "apt-get install -y sanoid"

# Configurar
ssh root@pve-desa03 bash -c '
mkdir -p /etc/sanoid
cat > /etc/sanoid/sanoid.conf << "EOF"
[shared-zfs]
    use_template = production
    recursive = yes
[template_production]
    daily = 7
    hourly = 0
    monthly = 0
    yearly = 0
    autosnap = yes
    autoprune = yes
EOF
systemctl enable --now sanoid.timer 2>/dev/null || true
'

# Si sanoid no está disponible, cron alternativo:
# 0 23 * * * root zfs snapshot -r shared-zfs@daily-$(date +\%Y\%m\%d)
# 30 23 * * * root zfs list -H -o name -t snapshot | grep shared-zfs@daily | head -n -7 | xargs -r zfs destroy
```

**Nomenclatura**: `shared-zfs@daily-YYYYMMDD` (o `auto-` prefix si usa sanoid). Retención: 7 días.

---

## 10. Plan de Failover (pve-desa03 caído)

### Detección
```bash
# Verificar desde pve-desa02
ssh -o ConnectTimeout=5 root@192.168.1.13 "hostname" || echo "pve-desa03 DOWN"
```

### Promover DR (pve-desa02 asume NFS)

```bash
#!/bin/bash
# /usr/local/bin/failover-to-desa02.sh
# Ejecutar en pve-desa02 cuando pve-desa03 está caído

DR_POOL="local-zfs/backup-dr"
NFS_IP="192.168.1.12"  # IP de pve-desa02

# 1. Promover datasets del DR pool (hacerlos writable)
for ds in vms kubernetes gitlab registry backups; do
    zfs set readonly=off ${DR_POOL}/${ds}
done

# 2. Exportar vía NFS desde pve-desa02
systemctl start nfs-server 2>/dev/null || apt-get install -y nfs-kernel-server

cat > /etc/exports << EOF
/${DR_POOL}/vms        192.168.1.0/24(rw,async,no_subtree_check,no_wdelay,crossmnt,fsid=100)
/${DR_POOL}/kubernetes 192.168.1.0/24(rw,async,no_subtree_check,no_wdelay,crossmnt,fsid=101)
/${DR_POOL}/gitlab     192.168.1.0/24(rw,async,no_subtree_check,no_wdelay,crossmnt,fsid=102)
/${DR_POOL}/registry   192.168.1.0/24(rw,async,no_subtree_check,no_wdelay,crossmnt,fsid=103)
/${DR_POOL}/backups    192.168.1.0/24(rw,async,no_subtree_check,no_wdelay,crossmnt,fsid=104)
EOF
exportfs -ra

# 3. Actualizar storage.cfg en el cluster — cambiar IP de servidor NFS
# ESTO SE HACE MANUALMENTE:
# pvesh set /storage/shared-vms --server 192.168.1.12
# pvesh set /storage/shared-k8s --server 192.168.1.12
# ... (por cada storage NFS)
```

### Failback (pve-desa03 recuperado)

```bash
#!/bin/bash
# /usr/local/bin/failback-to-desa03.sh

# 1. Verificar que pve-desa03 está operativo
ssh root@192.168.1.13 "zpool status shared-zfs" || exit 1

# 2. Sincronizar datos de vuelta (pve-desa02 → pve-desa03)
#    Replicación inversa de los datasets modificados durante failover
DR_POOL="local-zfs/backup-dr"
for ds in vms kubernetes gitlab registry backups; do
    SNAP="failback-$(date +%Y%m%d-%H%M%S)"
    zfs snapshot ${DR_POOL}/${ds}@${SNAP}
    zfs send -w -R ${DR_POOL}/${ds}@${SNAP} | \
        ssh root@192.168.1.13 "zfs receive -F shared-zfs/${ds}"
done

# 3. Re-montar NFS desde pve-desa03
# pvesh set /storage/shared-vms --server 192.168.1.13
# ... (por cada storage)

# 4. Reanudar replicación DR normal
systemctl start zfs-replicate-dr.timer
```

---

## 11. Scripts de Soporte

| Script | Ruta | Propósito |
|--------|------|-----------|
| `create-datasets.sh` | `scripts/f3-shared-storage/01-create-datasets.sh` | Crea pool shared-zfs + datasets |
| `configure-nfs.sh` | `scripts/f3-shared-storage/02-configure-nfs.sh` | NFS exports + pvesm storage |
| `configure-samba.sh` | `scripts/f3-shared-storage/03-configure-samba.sh` | Samba install + config |
| `setup-replication.sh` | `scripts/f3-shared-storage/04-replication.sh` | Replication script + systemd timer + sanoid |
| `failover-to-desa02.sh` | `scripts/f3-shared-storage/failover-to-desa02.sh` | DR failover procedure |
| `failback-to-desa03.sh` | `scripts/f3-shared-storage/failback-to-desa03.sh` | DR failback procedure |

Todos los scripts instalan su contenido en `/usr/local/bin/` en el nodo correspondiente.

---

## 12. Riesgos Técnicos y Mitigaciones

| Riesgo | Probabilidad | Impacto | Mitigación |
|--------|-------------|---------|------------|
| **NFS SPOF** (pve-desa03 caído) | Media | 🔴 Toda VM en shared sin acceso | Failover script a pve-desa02 + backups PBS |
| **sda con particiones NFS** se niega a crear mirror | Alta | 🟡 Data loss si no se backupéa | Backup a PBS ANTES de sgdisk -Z |
| **1 GbE saturado** (NFS + VMs + replicación) | Media | 🟡 Performance reducida | Replicación nocturna (02:00), monitorear con `bmon` |
| **ARC compite con VMs** en pve-desa02 (10 GB RAM) | Media | 🟡 Presión de memoria | ARC 50% (5 GB). `arc_summary` para monitorear |
| **Split-brain en failback** | Baja | 🟡 Datos inconsistentes | Replicación full antes de failback, no asumir sync parcial |

---

## 13. Plan de Rollback

### Deshacer pve-desa02 (volver a local-storage LVM)

```bash
# 1. Migrar VMs a pve-desa03 (shared-zfs)
# 2. Destruir pool local-zfs
zpool destroy local-zfs
# 3. Re-crear LVM thin local-storage
sgdisk -n 0:0:0 /dev/sdb
pvcreate /dev/sdb1
vgcreate local-storage /dev/sdb1
lvcreate -L 900G -T local-storage/data
# 4. Restaurar storage.cfg — local-lvm con LVM thin
# 5. Migrar VMs de vuelta
```

### Deshacer pve-desa03 (volver a NFS raw + vm-storage LVM)

```bash
# 1. Migrar VMs a pve-desa02 (local-zfs)
# 2. Destruir pool shared-zfs
zpool destroy shared-zfs
# 3. Re-crear NFS raw + vm-storage (desde backups)
# 4. Restaurar datos NFS desde backup tar.gz
# 5. Restaurar storage.cfg
```

### En ambos casos: restaurar VMs desde PBS si la migración falla
