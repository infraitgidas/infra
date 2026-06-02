# Recuperación ZFS — pve-gidas

Runbook para detectar y recuperar pools ZFS corruptos, ajustar ARC, reemplazar
discos fallados y restaurar desde replicación en el cluster pve-gidas.

**Destinatarios**: Administradores del cluster.
**Pools ZFS locales**: Cada nodo tiene un pool `local-zfs`.

## Quick Path — Pool Degradado

```bash
# 1. Detectar corrupción
zpool status -x

# 2. Iniciar scrub para evaluar daño
zpool scrub local-zfs

# 3. Monitorear progreso
zpool status local-zfs

# 4. Si hay discos fallados, reemplazar
zpool replace local-zfs <old-device> <new-device>

# 5. Verificar recuperación
zpool status local-zfs  # todos ONLINE, sin errores
```

## Prerequisitos

| Requisito | Detalle |
|-----------|---------|
| Acceso SSH | A todos los nodos del cluster |
| Backup reciente | Verificar backups PBS antes de cualquier operación destructiva |
| Disco de repuesto | Mismo tamaño o mayor que el disco fallado |
| ARC configurado | `/etc/modprobe.d/zfs.conf` con `zfs_arc_max` definido |

## Detección de Corrupción

### Comandos de diagnóstico

```bash
# Ver estado resumido de todos los pools
zpool status -x

# Estado detallado de un pool específico
zpool status local-zfs

# Ver errores de integridad (checksum, read, write)
zpool status -v local-zfs

# Ver propiedades del pool
zpool get all local-zfs | grep -E "health|errors"

# Ver estado de datasets
zfs list -t filesystem -r local-zfs
```

### Señales de alerta

| Síntoma | Comando | Acción |
|---------|---------|--------|
| Pool DEGRADED | `zpool status -x` | Revisar discos, iniciar scrub |
| Pool FAULTED | `zpool status -x` | Pool inaccesible — restaurar desde replicación |
| Errores checksum | `zpool status -v` | Reemplazar disco sospechoso |
| I/O errors | `dmesg \| tail -20` | Posible fallo de disco o cable |
| ARC no aplica | `cat /sys/module/zfs/parameters/zfs_arc_max` | Verificar módulo cargado |

## Recuperación de Pool

### 1. Pool Degradado (disco fallado pero pool operativo)

```bash
# Paso 1: Identificar disco fallado
zpool status local-zfs
# Buscar línea con estado DEGRADED o FAULTED, ej:
#   sdc  DEGRADED  0  0  0

# Paso 2: Iniciar scrub para evaluar daño completo
zpool scrub local-zfs

# Paso 3: Monitorear scrub (puede tomar horas)
watch -n 60 'zpool status local-zfs'

# Paso 4: Si el disco falló, offlinearlo
zpool offline local-zfs /dev/sdc

# Paso 5: Reemplazar disco físicamente, luego:
zpool replace local-zfs <old-device> <new-device>

# Paso 6: Monitorear resilver
zpool status local-zfs
# El resilver ocurre automáticamente post-replace

# Paso 7: Verificar pool saludable
zpool status -x  # debe decir "all pools are healthy"
```

### 2. Pool Faulted (pool completamente inaccesible)

Si el pool no se puede importar:

```bash
# Paso 1: Intentar importar (-f para forzar)
zpool import -f local-zfs

# Paso 2: Si falla, verificar dispositivos disponibles
zpool import -D  # mostrar dispositivos destruidos/disponibles

# Paso 3: Intentar importar omitiendo dispositivo fallado
zpool import -f -m local-zfs

# Paso 4: Si el pool arranca, hacer scrub inmediato
zpool scrub local-zfs
zpool status local-zfs

# Paso 5: Si el pool no arranca — restaurar desde replicación (ver sección)
```

### 3. Export/Import (para mover pool entre nodos o recovery)

```bash
# Exportar pool (todas las VMs deben estar apagadas)
zpool export local-zfs

# Verificar que el pool ya no está visible
zpool status

# Importar en otro nodo (o el mismo)
zpool import -d /dev/disk/by-id/ local-zfs

# Verificar
zpool status local-zfs
```

## ARC Tuning

### Verificar ARC actual

```bash
# Tamaño ARC máximo configurado (bytes)
cat /sys/module/zfs/parameters/zfs_arc_max

# Uso actual de ARC
arc_summary.py | head -20
# o
cat /proc/spl/kstat/zfs/arcstats | head -30

# Hit rate de ARC
arcstat.pl -f time,read,hits,miss,hit%,arcsz,l2hits,l2miss 1 5
```

### Ajustar ARC temporalmente (runtime, no persiste reboot)

```bash
# Ejemplo: reducir ARC a 4 GB (4294967296 bytes)
echo 4294967296 > /sys/module/zfs/parameters/zfs_arc_max

# Verificar cambio
cat /sys/module/zfs/parameters/zfs_arc_max
```

### Ajustar ARC permanentemente

```bash
# Editar configuración del módulo ZFS
vim /etc/modprobe.d/zfs.conf

# Valores por nodo (50% de RAM):
# pve-desa01 (15GB RAM): options zfs zfs_arc_max=8053063680
# pve-desa02 (10GB RAM): options zfs zfs_arc_max=5368709120
# pve-desa03 (15GB RAM): options zfs zfs_arc_max=8053063680
# pve-desa04 (15GB RAM): options zfs zfs_arc_max=8053063680

# Aplicar cambio (requiere reboot)
reboot

# Verificar post-reboot
cat /sys/module/zfs/parameters/zfs_arc_max
```

> **NOTA**: `zfs_arc_max` se define en bytes. Para RAM de 15 GB → 7.5 GB → 8053063680.
> ARC no debe exceder el 50% de la RAM total para dejar espacio a VMs y servicios.

## Reemplazar Disco Fallado

### Identificar disco por ID (recomendado sobre `/dev/sdX`)

```bash
# Listar discos con información de serie/modelo
ls -la /dev/disk/by-id/
# Identificar el disco fallado por su ID, ej: ata-WDC_WD10EZEX-00WN4A0_XXXXX

# Verificar la relación entre /dev/sdX y by-id
ls -la /dev/disk/by-id/ | grep $(readlink -f /dev/sdc | cut -d/ -f3)
```

### Reemplazo en caliente (hot spare)

```bash
# 1. Marcar disco como offline
zpool offline local-zfs /dev/disk/by-id/ata-<OLD-DISK>

# 2. Reemplazar físicamente el disco

# 3. Verificar que el nuevo disco es detectado
lsblk | grep sd

# 4. Reemplazar en el pool
zpool replace local-zfs /dev/disk/by-id/ata-<OLD-DISK> /dev/disk/by-id/ata-<NEW-DISK>

# 5. Monitorear resilver
zpool status local-zfs
# El resilver copia datos al nuevo disco automáticamente
```

### Reemplazo con disco diferente

Si el nuevo disco tiene distinto ID:

```bash
# Obtener ID del nuevo disco
ls -la /dev/disk/by-id/

# Reemplazar usando ID nuevo
zpool replace local-zfs /dev/disk/by-id/ata-<OLD-DISK> /dev/disk/by-id/ata-<NEW-DISK>
```

## Restaurar Pool Desde Replicación (pérdida total)

Si el pool `local-zfs` se pierde completamente y no puede recuperarse, restaurar
desde el nodo de replicación:

### Paso 1: Verificar replicación disponible

```bash
# Desde el nodo remoto (ej: pve-desa02 replica a pve-desa01)
ssh root@pve-desa02 "pvesr list"
# Verificar que los snapshots de replicación existen
ssh root@pve-desa02 "zfs list -t snapshot -r local-zfs"
```

### Paso 2: Re-crear pool en nodo fallado

```bash
# Identificar disco disponible
lsblk

# Crear pool (mismo nombre que original)
zpool create -o ashift=12 local-zfs /dev/sdX

# Configurar propiedades
zfs set compression=zstd local-zfs
zfs set atime=off local-zfs

# Configurar ARC (ver sección ARC Tuning)
echo "options zfs zfs_arc_max=8053063680" > /etc/modprobe.d/zfs.conf
```

### Paso 3: Enviar snapshots desde replicación

```bash
# En el nodo remoto (el que tiene la réplica), enviar cada dataset:
ssh root@pve-desa02
zfs send -R local-zfs/vm-105-disk-0@replic-<timestamp> | \
  ssh root@pve-desa01 "zfs receive -F local-zfs/vm-105-disk-0"
```

### Paso 4: Re-configurar replicación

```bash
# Una vez restaurado el nodo, re-crear jobs de replicación
# Ejecutar en el nodo restaurado
pvesr create-local-job <vmid> <target-node> \
  --rate 524288000 \
  --schedule "*/15 * * * *"
```

### Paso 5: Verificar VMs

```bash
# Las VMs deben estar visibles en PVE
qm list

# Verificar que pueden iniciar
qm start <vmid> && qm status <vmid>

# Si los discos no aparecen, re-escanear storage
pvesm scan local-zfs
```

## Rollback — Deshacer Operaciones

| Operación | Rollback |
|-----------|----------|
| Scrub en progreso | `zpool scrub -s local-zfs` (cancela scrub) |
| Replace en progreso | Esperar a que termine; si falla, `zpool detach local-zfs <new-device>` |
| Replace completado | `zpool detach local-zfs <device>` (solo si hay mirror/redundancia) |
| Pool re-creado | No hay rollback — restaurar desde PBS (ver `restore-from-pbs.md`) |
| ARC cambiado runtime | `echo <valor-original> > /sys/module/zfs/parameters/zfs_arc_max` |
| Migración por export/import | `zpool export local-zfs && zpool import local-zfs` en nodo original |

## Prevención

### Scrub programado

```bash
# Ejecutar scrub cada mes (recomendado)
# Agregar a cron de root en cada nodo:
echo "0 3 1 * * /sbin/zpool scrub local-zfs" >> /var/spool/cron/crontabs/root
```

### Monitoreo de salud ZFS

```bash
# Script para verificar diariamente (usar en cron)
cat > /usr/local/bin/check-zfs.sh << 'EOF'
#!/bin/bash
HEALTH=$(zpool status -x local-zfs | tail -1)
if [ "$HEALTH" != "all pools are healthy" ]; then
    echo "ALERTA: $HEALTH" | mail -s "ZFS Health Alert" root
fi
EOF
chmod +x /usr/local/bin/check-zfs.sh
```

### Backups

Siempre mantener backups en PBS antes de cualquier operación en ZFS.
Ver `docs/runbooks/restore-from-pbs.md`.

## Referencias

- Scripts de configuración ZFS: `scripts/f2-storage-zfs/`
- Script de verificación: `scripts/f2-storage-zfs/07-verify.sh`
- Runbook PBS restore: `docs/runbooks/restore-from-pbs.md`
- [OpenZFS Documentation](https://openzfs.github.io/openzfs-docs/)
- [Proxmox ZFS Best Practices](https://pve.proxmox.com/wiki/ZFS_on_Linux)
