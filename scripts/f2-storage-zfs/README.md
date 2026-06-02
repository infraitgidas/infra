# F2 — Storage ZFS (P1)

## Objetivo

Migrar el almacenamiento de todos los nodos del cluster de LVM thin a ZFS,
incluyendo replicación asíncrona entre pares fijos.

## Arquitectura

```
Antes:                         Después:
  Cada nodo: LVM thin           Cada nodo: Pool ZFS local-zfs
  └── VMs en volúmenes LVM       └── compression=zstd, atime=off
                                  └── ARC limitado a 50% RAM

Replicación:
  pve-desa01 ◄──snap──► pve-desa02    (RPO 15min/1h, bwlimit 500M)
  pve-desa03 ◄──snap──► pve-desa04    (RPO 15min/1h, bwlimit 500M)
```

## Asignación de Discos por Nodo

| Nodo | RAM | Dispositivo ZFS | Detalle |
|------|-----|-----------------|---------|
| pve-desa01 | 15 GB | `/dev/pve/zfs-pool` | LVM-backed (single disk: sda 447G SSD). Se destruye thin pool `data` y se crea LV grueso para ZFS. |
| pve-desa02 | 10 GB | `/dev/sdc` | Disco libre de 932G (WD HDD). No requiere migración de VMs. |
| pve-desa03 | 15 GB | `/dev/sdc` | Se destruye VG `vm-storage` (sdc1) y se crea pool en el disco completo. No requiere migración de VMs. |
| pve-desa04 | 15 GB | `/dev/sdb` | Se destruye thin pool data + se limpia label ZFS antiguo (`rpool` DEGRADED de instalación previa). No se usa sdb3 — se usa disco completo. |

## VMs y Migración Temporal

Durante la conversión, las VMs se mueven temporalmente al nodo vecino:

| VM/CT | Origen | Destino Temporal | Tipo |
|-------|--------|------------------|------|
| CT 105 (connector-twingate) | pve-desa01 | pve-desa02 | Contenedor, running, 512MB |
| VM 100 (BASE-Windows2k22) | pve-desa01 | pve-desa02 | VM, stopped, 3GB |
| VM 109 (gidas-site-desa) | pve-desa04 | pve-desa03 | VM, running, 2GB |

Luego de creado el pool ZFS, las VMs vuelven al nodo original sobre ZFS.

## Orden de Ejecución

Los scripts **deben ejecutarse en orden** en esta máquina (no en los nodos):

```bash
# 0. Cargar configuración de entorno
source 00-env.sh

# 1. Survey pre-vuelo (read-only)
./01-survey.sh

# 2. Migrar VMs a nodo vecino (Task 2.1)
./02-migrate-to-neighbor.sh

# 3. Destruir LVM y crear pools ZFS (Task 2.2)
./03-create-zpool.sh

# 4. Configurar ZFS: compression=zstd, atime=off, ARC (Tasks 2.3 + 2.4)
./04-configure-zfs.sh

# 5. Migrar VMs de vuelta sobre ZFS (Task 2.5)
./05-migrate-back.sh

# 6. Configurar replicación asíncrona (Task 2.6)
./06-replication.sh

# 7. Verificar todo (Task 2.7)
./07-verify.sh
```

## Configuraciones Clave

### ZFS pool
```bash
zpool create -o ashift=12 local-zfs /dev/sdX
zfs set compression=zstd local-zfs
zfs set atime=off local-zfs
```

### ARC (50% RAM)
```bash
# pve-desa01 (15GB): 7.5GB = 8053063680
# pve-desa02 (10GB): 5GB  = 5368709120
# pve-desa03 (15GB): 7.5GB = 8053063680
# pve-desa04 (15GB): 7.5GB = 8053063680
echo "options zfs zfs_arc_max=8053063680" > /etc/modprobe.d/zfs.conf
```

### Replicación
```bash
# VM crítica cada 15 minutos
pvesr create-local-job 105 pve-desa02 --rate 524288000 --schedule "*/15 * * * *"
pvesr create-local-job 109 pve-desa03 --rate 524288000 --schedule "*/15 * * * *"

# VM no crítica cada 1 hora
pvesr create-local-job 100 pve-desa02 --rate 524288000 --schedule "0 * * * *"
```

## Verificación

```bash
# Estado del pool
zpool status local-zfs

# Propiedades ZFS
zfs get compression,atime local-zfs

# ARC
cat /sys/module/zfs/parameters/zfs_arc_max

# Replicación
pvesr list

# Almacenamiento
pvesm status
```

## Rollback

### Restaurar LVM (si algo sale mal)

```bash
# 1. Eliminar pool ZFS
zpool destroy local-zfs

# 2. Si es LVM-backed (pve-desa01):
lvremove pve/zfs-pool

# 3. Si es disco dedicado:
#    Crear nueva tabla de particiones
#    Crear partición LVM
#    Crear VG + thin pool

# 4. Restaurar VMs desde PBS
#    Conectar a PBS, restaurar backup más reciente

# 5. Restaurar storage.cfg
#    Eliminar zfspool entry, restaurar local-lvm
```

### Deshabilitar replicación

```bash
# Listar jobs de replicación
pvesr list

# Eliminar job por ID
pvesr delete <job-id>
```

## Limitaciones Conocidas

1. **pve-desa01 (single disk)**: El pool ZFS está sobre un LV de LVM (capa extra). Esto agrega overhead mínimo pero no es ideal. Si se reinstala el nodo con ZFS root, se puede migrar a ZFS directo en el futuro.
2. **ARC runtime vs config**: `zfs_arc_max` se configura en `/etc/modprobe.d/zfs.conf` pero requiere reboot para aplicar. El valor runtime puede ser diferente hasta el próximo reinicio.
3. **pve-desa02**: Disco ZFS es HDD (Western Digital 932G, 7200 RPM). Para VMs con alta tasa de escritura, considerar `log` (SLOG) en SSD o aumentar `recordsize=1M` para cargas secuenciales.
4. **Snapshots**: La retención de 7 días se maneja via cron. Para gestión más avanzada, instalar `sanoid`.
