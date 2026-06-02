# F1 — Backups y Correcciones Inmediatas (P0)

## Objetivo

Implementar backups automáticos con Proxmox Backup Server (PBS) en el cluster
pve-gidas, incluyendo:
- Instalación de PBS en pve-ad (nodo standalone)
- Datastore ZFS con compresión zstd
- Cifrado client-side con encryption key
- Jobs diarios a las 22:00 con retención 7+4+3
- Limpieza (prune + GC) semanal
- Corrección de cache writeback → none en VM 102

## Arquitectura

```
Nodo PVE (cada nodo del cluster)
  │  Backup via job programado (22:00)
  │  Cifrado con /root/.pve-encryption-key
  ▼
PBS (pve-ad:8007)
  └── Datastore: gidas-backups (ZFS, zstd)
      ├── Prune: Sun 23:00 (keep 7d, 4w, 3m)
      └── GC:    Sun 23:30
```

## Requisitos

1. **Acceso SSH** desde esta máquina a todos los nodos del cluster y a pve-ad
2. **Claves SSH** cargadas en `~/.ssh/authorized_keys` de root en cada nodo
3. **Nodos alcanzables** por IP directa (no requiere DNS)
4. PBS repo configurado en pve-ad (PVE 9 no-subscription)

## Orden de Ejecución

Los scripts **deben ejecutarse en orden** en esta máquina (no en los nodos):

```bash
# 0. Cargar configuración de entorno
source 00-env.sh

# 1. Corregir cache writeback en VM 102 (P0 crítica)
#    Nodo: pve-desa01, VM 102 DC2
./01-fix-writeback.sh

# 2. Instalar PBS en pve-ad con datastore ZFS
#    NOTA: pve-ad solo tiene 1 SSD de 224GB.
#    Si no hay disco dedicado, crea un pool ZFS sobre archivo (loopback).
#    ⚠️ Se recomienda agregar un disco dedicado para producción.
./02-install-pbs.sh

# 3. Generar y distribuir encryption key a todos los nodos
#    Key: /root/.pve-encryption-key (256-bit hex, chmod 600)
./03-encryption-key.sh

# 4. Agregar PBS como storage en /etc/pve/storage.cfg
#    /etc/pve/ es PMXCFS compartido → cambios se replican a todos los nodos
./04-configure-storage.sh

# 5. Configurar jobs de backup (diarios 22:00) + prune + GC
./05-backup-jobs.sh

# 6. Verificar todo
./06-verify.sh
```

## Ejecución Manual Alternativa

Si los scripts fallan por conectividad, los comandos clave pueden ejecutarse
manualmente en cada nodo:

### Fix writeback VM 102
```bash
ssh root@pve-desa01 "qm set 102 --scsi0 cache=none"
```

### Instalar PBS
```bash
ssh root@pve-ad "apt update && apt install -y proxmox-backup-server"
# Crear pool ZFS (con disco libre):
ssh root@pve-ad "zpool create -f -o ashift=12 backup /dev/sdX"
# Crear dataset:
ssh root@pve-ad "zfs create -o compression=zstd -o atime=off -o mountpoint=/backup/pbs backup/dataset"
# Crear datastore:
ssh root@pve-ad "proxmox-backup-manager datastore create gidas-backups /backup/pbs"
```

### Encryption key
```bash
KEY=$(openssl rand -hex 32)
for node in pve-desa01 pve-desa02 pve-desa03 pve-desa04 pve-ad; do
    echo "$KEY" | ssh root@$node "cat > /root/.pve-encryption-key && chmod 600 /root/.pve-encryption-key"
done
```

## Rollback

### Eliminar PBS storage de storage.cfg
```bash
cp /etc/pve/storage.cfg /etc/pve/storage.cfg.bak
# Editar y remover la sección PBS manualmente
```

### Eliminar backup jobs
```bash
# Listar jobs:
pvesh get /cluster/backup
# Eliminar job por ID:
pvesh delete /cluster/backup/<id>
```

### Desinstalar PBS (si es necesario)
```bash
ssh root@pve-ad "apt remove --purge proxmox-backup-server"
ssh root@pve-ad "zpool destroy pbs-pool"
```

## Limitaciones Conocidas

1. **pve-ad sin disco extra**: El datastore ZFS se crea sobre archivo (loopback)
   si no hay disco dedicado. Esto afecta rendimiento y resiliencia. Agregar disco
   dedicado lo antes posible.
2. **VMs Windows stopped (100, 101, 102)**: Pendiente decisión (task 1.1).
   Incluidas en backup job por ahora. Si se destruyen, actualizar job.
3. **PBS fuera del cluster**: pve-ad ejecuta PVE 9.1.1 vs cluster PVE 8.4.
   No es posible unirlo al cluster. Funciona como PBS standalone.
