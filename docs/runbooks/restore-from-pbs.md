# Restauración de Backups desde PBS — pve-gidas

Runbook para restaurar VMs, contenedores (CT) y archivos individuales desde
Proxmox Backup Server (PBS) en el cluster pve-gidas.

**Destinatarios**: Administradores del cluster.
**Prerequisito**: PBS operativo en `192.168.1.31:8007`, datastore `pve-gidas`.

## Quick Path — Restaurar VM completa

```bash
# 1. Listar backups disponibles para una VM
pvesh get /cluster/backup  # lista todos los jobs
pvesh get /cluster/backup/<job-id>/snapshots  # snapshots de un job

# 2. Restaurar VM desde backup más reciente
#    Ruta: /storage/pbs/backup/<vmid>/<snapshot>
pvesh create /nodes/<target-node>/qemu/<vmid>/backup/restore \
  --storage pbs \
  --vmid <vmid> \
  --node <target-node>

# 3. Verificar que la VM arranca
qm start <vmid> && qm status <vmid>

# 4. Rollback (si la restauración falla)
qm stop <vmid> --force 2>/dev/null
qm destroy <vmid> --purge
```

## Requisitos Previos

| Requisito | Detalle |
|-----------|---------|
| Encryption key | Archivo `/root/.pve-encryption-key` presente en el nodo donde se ejecuta la restauración |
| PBS accesible | Puerto 8007 abierto desde el nodo PVE al PBS |
| Almacenamiento destino | Storage ZFS local (`local-zfs`) con espacio suficiente |
| Fingerprint PBS | Verificado en `/etc/pve/storage.cfg` |

Si falta la encryption key, regenerarla en el nodo:

```bash
# SOLO si se perdió la key original — los backups existentes quedarán inaccesibles
openssl rand -hex 32 > /root/.pve-encryption-key
chmod 600 /root/.pve-encryption-key
```

> **IMPORTANTE**: La encryption key original se necesita para descifrar backups existentes.
> Si se regenera, los backups anteriores NO podrán restaurarse. La key está almacenada
> en `secrets/proxmox.yaml` (cifrado SOPS) y en `/root/.pve-encryption-key` de cada nodo.

## Listar Backups Disponibles

### Desde la CLI de PVE

```bash
# Listar grupos de backup en PBS
proxmox-backup-client list --repository 192.168.1.31:8007:pve-gidas

# Ver snapshots de una VM específica (ej: VM 105)
pvesh get /nodes/pve-desa01/storage/pbs/content \
  --content backup \
  --vmid 105
```

### Desde la CLI de PBS (en pve-ad)

```bash
ssh root@pve-ad
proxmox-backup-manager snapshot list pve-gidas

# Filtrar por VM
proxmox-backup-manager snapshot list pve-gidas | grep "105"
```

## Restaurar VM Completa

### Paso 1: Elegir nodo destino

Preferir el nodo original de la VM para mantener configuraciones de red y
replicación. Verificar espacio disponible:

```bash
pvesm status | grep local-zfs
```

### Paso 2: Restaurar desde backup (CLI)

```bash
# Formato completo
pvesh create /nodes/<node>/qemu/<vmid>/backup/restore \
  --storage pbs \
  --vmid <vmid> \
  --node <node> \
  --target <node>
```

Ejemplo: restaurar VM 105 en pve-desa01

```bash
pvesh create /nodes/pve-desa01/qemu/105/backup/restore \
  --storage pbs \
  --vmid 105 \
  --node pve-desa01
```

### Paso 3: Restaurar desde backup (Web UI)

1. Acceder a `https://<nodo>:8006` → Datacenter → Storage → `pbs`
2. Seleccionar `Backups` → elegir VM/CT
3. Click en backup deseado → `Restore`
4. Seleccionar nodo destino y storage
5. Confirmar

### Paso 4: Verificar integridad

```bash
# La VM debe aparecer en el nodo destino
qm list

# Verificar configuración
qm config <vmid>

# Iniciar VM y verificar estado
qm start <vmid>
sleep 10
qm status <vmid>  # debe mostrar "running"

# Verificar conectividad (si tiene IP conocida)
ping -c 2 <ip-de-la-vm>
```

### Paso 5: Re-configurar replicación (si aplica)

Si la VM original tenía replicación ZFS configurada, restaurarla:

```bash
# Obtener job original (de la documentación o scripts)
pvesr create-local-job <vmid> <target-node> \
  --rate 524288000 \
  --schedule "*/15 * * * *"
```

## Restaurar Contenedor (CT)

```bash
# Listar backups de CT
pvesh get /nodes/<node>/storage/pbs/content --content backup --vmid <ctid>

# Restaurar
pvesh create /nodes/<node>/lxc/<ctid>/backup/restore \
  --storage pbs \
  --vmid <ctid> \
  --node <node> \
  --target <node> \
  --storage local-zfs
```

## Restaurar Archivos Individuales (Proxmox File Restore)

PBS permite restaurar archivos individuales sin restaurar la VM completa.
Requiere el plugin `proxmox-file-restore` en el nodo PVE.

### Instalar plugin (si no está)

```bash
apt update && apt install -y proxmox-file-restore
```

### Restaurar archivos desde backup

```bash
# Montar backup como filesystem virtual
# (se abre una interfaz TUI o web según la versión)
proxmox-file-restore mount <snapshot-id> /mnt/restore

# Explorar y copiar archivos
ls /mnt/restore/
cp /mnt/restore/ruta/al/archivo /donde/restaurarlo/

# Desmontar al terminar
proxmox-file-restore umount /mnt/restore
```

> **NOTA**: En PBS 4.0.x, la restauración de archivos individuales puede no estar
> disponible para todos los tipos de backup. Usar la Web UI de PBS
> (`https://192.168.1.31:8007`) como alternativa para explorar snapshots.

## Verificación Post-Restauración

| Qué Verificar | Comando | Esperado |
|--------------|---------|----------|
| VM lista | `qm list` | VM visible en nodo destino |
| VM corre | `qm status <vmid>` | `status: running` |
| Disco ZFS | `zfs list` | Dataset con espacio usado correcto |
| Replicación | `pvesr list` | Jobs activos (si aplica) |
| Backup nuevo | `pvesh get /nodes/pve-desa01/storage/pbs/content` | Snapshot reciente |
| Integridad PBS | `proxmox-backup-manager verify <snapshot>` | `verified: true` |

## Rollback — Eliminar VM Restaurada

Si la restauración produce una VM corrupta o no funcional:

```bash
# Detener VM
qm stop <vmid> --force

# Eliminar VM (con purga para remover también snapshots locales)
qm destroy <vmid> --purge

# Verificar que no quedan rastros
qm list | grep <vmid> || echo "VM eliminada correctamente"

# Si era una CT:
pct stop <ctid> --force
pct destroy <ctid> --purge
```

## Referencias

- [PBS Administration Guide](https://pbs.proxmox.com/wiki/index.php/Main_Page)
- Scripts de backup: `scripts/f1-backups/`
- Configuración PBS: `secrets/proxmox.yaml`
- Runbook ZFS: `docs/runbooks/zfs-recovery.md`
