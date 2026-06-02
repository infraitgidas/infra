# F4 — Optimización VMs (P2)

## Objetivo

Maximizar el rendimiento de las VMs del cluster mediante parámetros óptimos
de CPU, memoria y almacenamiento, corrigiendo configuraciones subóptimas
detectadas en la auditoría.

## Arquitectura

```
Antes:                              Después:
  CPU: kvm64 (genérico)              CPU: host (instrucciones nativas)
  NUMA: deshabilitado                NUMA: habilitado (>4 vCPUs)
  SCSI: lsi/virtio (sin iothread)    SCSI: virtio-scsi-single + iothread=1
  Balloon: sin mínimo fijo           Balloon: mínimo ≥ 1 GB
  Cache: writeback (riesgoso)        Cache: none (integridad)
```

## Inventario de VMs

| VMID | Nombre | SO | Estado | Nodo | vCPUs | RAM |
|------|--------|----|--------|------|-------|-----|
| 100 | BASE-Windows2k22 | Windows | Stopped | pve-desa01 | 2-4 | 4-8 GB |
| 101 | VM-DC1 | Windows | Stopped | pve-desa02 | 2-4 | 4-8 GB |
| 105 | connector-twingate | Linux | Running | pve-desa01 | 1-2 | 1-2 GB |
| 108 | rocky-10-template | Linux | Stopped | pve-desa01 | 1-2 | 1-2 GB |
| 109 | gidas-site-desa | Linux | Running | pve-desa04 | 2-4 | 4-8 GB |

> **Nota**: VM 102 (DC2) fue destruida en Fase 1. Solo VMs 100, 101 están
> stopped pendientes de decisión.

## Decisiones de Diseño

| Decisión | Justificación |
|----------|---------------|
| CPU `host` solo en VMs Linux | Windows puede tener inestabilidad con CPU host en migración |
| NUMA si >4 vCPUs | Mejora rendimiento memoria en hosts multi-socket |
| Cache `none` en lugar de `writethrough` | Integridad garantizada; writethrough es seguro pero más lento |
| Sin migración cross-nodo | No hay shared storage — CPU host no bloquea operaciones |
| Balloon mínimo 1 GB | Evita swap excesivo en el SO huésped |

## Orden de Ejecución

Los scripts **deben ejecutarse en orden** en esta máquina (no en los nodos):

```bash
# 0. Cargar configuración de entorno
source 00-env.sh

# 1. Configurar CPU type 'host' en VMs Linux (Task 4.1)
./01-cpu-host.sh

# 2. Habilitar NUMA en VMs >4 vCPUs (Task 4.2)
./02-numa.sh

# 3. Configurar VirtIO SCSI Single + iothread=1 (Task 4.3)
./03-virtio-scsi.sh

# 4. Revisar ballooning mínimo >1 GB (Task 4.4)
./04-ballooning.sh

# 5. Verificar todas las configuraciones (Task 4.5)
./05-verify.sh
```

## Configuraciones Clave

### CPU type host

```bash
# En cualquier nodo del cluster
qm set <vmid> --cpu host
```

### NUMA

```bash
qm set <vmid> --numa 1
```

### VirtIO SCSI Single

```bash
# Cambiar controladora SCSI
qm set <vmid> --scsihw virtio-scsi-single --iothread 1

# Cambiar cache en discos existentes
qm set <vmid> --scsi0 cache=none
```

### Ballooning

```bash
# Establecer mínimo de balloon (1 GB)
qm set <vmid> --balloon 1024
```

## Verificación

```bash
# Ver configuración completa de una VM
qm config <vmid> | grep -E "cpu:|numa:|cache:"

# Ejecutar script de verificación
source 00-env.sh && ./05-verify.sh
```

## Rollback

### Revertir CPU type

```bash
# Revertir a kvm64 (default de Proxmox)
qm set 105 --cpu kvm64
qm set 108 --cpu kvm64
qm set 109 --cpu kvm64
```

### Revertir NUMA

```bash
qm set 100 --numa 0
qm set 101 --numa 0
qm set 105 --numa 0
qm set 108 --numa 0
qm set 109 --numa 0
```

### Revertir SCSI controller

```bash
# Para cada VM, registrar el scsihw original antes de cambiar
# (el script 03-virtio-scsi.sh muestra el comando de rollback)
qm set <vmid> --scsihw <original> --iothread 0

# Revertir cache de disco a valor original
qm set <vmid> --scsi0 cache=<original>
```

### Revertir ballooning

```bash
# Deshabilitar ballooning (vuelve a memory estática)
qm set 105 --balloon 0
# O establecer valor original
qm set 105 --balloon <original_value>
```

### Rollback completo (reset a configuración original)

```bash
# Si se documentaron los valores originales:
for vmid in 100 101 105 108 109; do
    qm set $vmid --cpu kvm64
    qm set $vmid --numa 0
    qm set $vmid --scsihw lsi --iothread 0
    qm set $vmid --balloon 0
done
```

## Limitaciones Conocidas

1. **VMs Windows**: CPU type `host` no se aplica a VMs Windows (100, 101)
   para evitar inestabilidad. Si se requiere, probar primero en entorno no
   productivo.
2. **VM 108 (template)**: rocky-10-template puede no tener SCSI configurado.
   VirtIO SCSI Single solo aplica si la VM usa discos SCSI.
3. **VM 102 destruida**: No se requiere ninguna acción para DC2.
4. **Rollback manual**: Los scripts no guardan los valores originales en un
   archivo de backup. Se recomienda ejecutar `05-verify.sh` antes y después
   para documentar el estado.
5. **Sin downtime planificado**: Si alguna VM está running (105, 109), los
   cambios de CPU/NUMA requieren reinicio. Los scripts aplican la
   configuración pero la VM necesita un reboot para que surta efecto.

## Prerequisitos

1. Acceso SSH sin contraseña (key-based) al cluster como root
2. Cluster Proxmox funcional (pvecm status OK)
3. `jq` instalado en el nodo de control (opcional, para parseo JSON)
4. Scripts ejecutados desde una máquina con acceso SSH a los nodos
