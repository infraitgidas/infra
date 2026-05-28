# Auditoría del Cluster Proxmox — pve-gidas

> Fecha: 2026-05-27
> Método: Auditoría remota vía SSH con autenticación por clave

---

## Resumen Ejecutivo

El cluster **pve-gidas** tiene **4 nodos** (pve-desa01 a 04) corriendo Proxmox 8.4.19 sobre Debian 12. Además hay un nodo **pve-ad** (192.168.1.31) con PVE 9.1.1 que **NO pertenece al cluster**.

**Estado general**: Operativo pero con carencias críticas:
- 🔴 **No hay backups** configurados en ningún nodo
- 🔴 **No hay QDevice** configurado — riesgo de quorum
- 🔴 **Sin ZFS** — todos los nodos usan LVM thin (sin checksum, sin compresión nativa)
- 🟡 **Red plana** — Corosync y storage comparten la misma interfaz
- 🟡 **VMs Windows detenidas** sin uso (3 VMs en pve-desa01, 3072MB cada una)

---

## 1. Inventario de Hardware

### pve-desa01 (192.168.1.11)

| Recurso | Detalle |
|---|---|
| CPU | 11th Gen Intel i5-11400, 6C/12T @ 2.6GHz |
| RAM | 15 GB |
| Disco | 447 GB SSD (LVM thin) |
| OS | Debian 12 + PVE 8.4.19 (kernel 6.8.12-23) |
| Uptime | 1h 41min |
| Carga | 0.00 |
| Red | 1x vmbr0 (enp2s0) |

### pve-desa02 (192.168.1.12)

| Recurso | Detalle |
|---|---|
| CPU | AMD A10-7700K Radeon R7, 4C/4T @ 3.4GHz |
| RAM | 10 GB |
| Disco | 224 GB SSD + 932 GB HDD (LVM thin) |
| OS | Debian 12 + PVE 8.4.19 (kernel 6.8.12-20) |
| Uptime | 34 días |
| Carga | 0.16 |
| Red | 1x vmbr0 (enp1s0) |

### pve-desa03 (192.168.1.13)

| Recurso | Detalle |
|---|---|
| CPU | Intel i5-7400, 4C/4T @ 3.0GHz |
| RAM | 15 GB |
| Disco | 224 GB SSD + 932 GB HDD + 932 GB HDD (LVM thin) |
| OS | Debian 12 + PVE 8.4.19 (kernel 6.8.12-15) |
| Uptime | 34 días |
| Carga | 0.10 |
| Red | 1x vmbr0 (enp1s0) |
| **Rol NFS** | Exporta `/mnt/nfs-storage` (787GB) y `/mnt/iso-storage` (129GB) |

### pve-desa04 (192.168.1.14)

| Recurso | Detalle |
|---|---|
| CPU | Intel Xeon E-2434, 4C/8T @ 3.4GHz |
| RAM | 15 GB |
| Disco | 932 GB SSD + 932 GB HDD (LVM thin + ZFS raw) |
| OS | Debian 12 + PVE 8.4.19 (kernel 6.8.12-20) |
| Uptime | 20 días |
| Carga | 0.29 |
| Red | 4x NIC (eno1-4), solo eno1 en uso |

### pve-ad (192.168.1.31) — NO está en el cluster

| Recurso | Detalle |
|---|---|
| CPU | Intel i5-7400, 4C/4T @ 3.0GHz |
| RAM | 15 GB (7.2 GB usada) |
| Disco | 224 GB SSD (LVM thin) |
| OS | Debian + **PVE 9.1.1** (kernel 6.17.2-1) |
| Uptime | 1 día |
| Carga | 0.52 |
| Cluster | **NO pertenece a pve-gidas** (versión incompatible: PVE 9 vs 8) |

---

## 2. Estado del Cluster

```
Nombre:             pve-gidas
Transport:          knet
Auth segura:        on
Nodos:              4
Quorum:             3 (4 votos, 4 esperados)
QDevice:            NO CONFIGURADO
HA:                 NO CONFIGURADO
Corosync links:     1 (link0, red plana)
```

### Análisis de Quorum

| Situación | Quorum | ¿Operativo? |
|---|---|---|
| 4 nodos online | 4 votos ≥ 3 | ✅ Sí |
| 1 nodo caído | 3 votos ≥ 3 | ✅ Sí |
| 2 nodos caídos | 2 votos < 3 | ❌ No (cluster bloqueado) |
| 1 nodo + split | 2 vs 2 | ❌ Split-brain |

**Riesgo**: Con 4 nodos y quorum 3, la pérdida de 2 nodos bloquea todo. Un QDevice externo no cambiaría esto (seguiría siendo 4+1, quorum 3).

**Recomendación**: Para 4 nodos, el quorum actual es aceptable. QDevice sería útil si en el futuro se reduce a 3 nodos (quorum 2) o para entornos donde se garantice disponibilidad 24/7.

---

## 3. Inventario de VMs y Contenedores

### VMs en el cluster pve-gidas

| VMID | Nombre | Nodo | Estado | RAM | vCPU | SO | Discos |
|---|---|---|---|---|---|---|---|
| 100 | BASE-Windows2k22 | pve-desa01 | **STOPPED** | 3 GB | 2 | Windows Server | 32 GB |
| 101 | VM-DC1 | pve-desa01 | **STOPPED** | 3 GB | 2 | Windows Server | 32 GB |
| 102 | DC2 | pve-desa01 | **STOPPED** | 3 GB | 2 | Windows Server | 32 GB |
| 108 | rocky-10-template | pve-desa04 | **STOPPED** | 2 GB | 2 | Rocky Linux | 32 GB (template) |
| 109 | gidas-site-desa | pve-desa04 | **RUNNING** | 2 GB | 2 | Rocky Linux | 32 GB |

**Total RAM asignada**: 13 GB (de 55 GB físicos en el cluster) — 24% utilizado
**Total RAM en VMs stopped**: 9 GB (69% de la RAM asignada está detenida)

### VMs y Contenedores en pve-ad (nodo separado)

| ID | Nombre | Tipo | Estado | RAM | vCPU | IP |
|---|---|---|---|---|---|---|
| 100 | DC-VM | VM | **RUNNING** | 4 GB | - | - |
| 200 | sg-rojo | CT | **RUNNING** | 512 MB | 1 | 192.168.1.200 |
| 201 | sg-azul | CT | **RUNNING** | 512 MB | 1 | 192.168.1.204 |
| 202 | sg-verde | CT | **RUNNING** | 512 MB | 1 | 192.168.1.202 |
| 203 | sg-amarillo | CT | **RUNNING** | 512 MB | 1 | 192.168.1.203 |
| 205 | sg-monitoring | CT | **RUNNING** | 2 GB | 1 | 192.168.1.205 |

**Total RAM asignada**: 8 GB (de 15 GB físicos)

---

## 4. Almacenamiento

### Almacenamiento local (LVM thin)

Todos los nodos del cluster usan **LVM thin provisioning** (NO ZFS):

| Nodo | Pool thin | VG | Tamaño | Tipo |
|---|---|---|---|---|
| pve-desa01 | data | pve | 320 GB | SSD (447 GB) |
| pve-desa02 | data | pve | 131 GB | SSD (224 GB) |
| pve-desa02 | local-storage | local-storage | 913 GB | HDD (932 GB) |
| pve-desa03 | data | pve | 130 GB | SSD (224 GB) |
| pve-desa04 | data | pve | 794 GB | SSD (932 GB) |

### Almacenamiento compartido (NFS)

| Storage ID | Servidor | Export | Path local | Tipo | Uso |
|---|---|---|---|---|---|
| shared-nfs | 192.168.1.13 (pve-desa03) | `/mnt/nfs-storage` | `/mnt/pve/shared-nfs` | NFS v4.2 sync | ISOs, templates, backups |

**⚠️ Riesgo**: El NFS está servido desde pve-desa03. Si ese nodo falla, todos los nodos pierden acceso a ISOs/templates/backups.

### Discos sin usar

- **pve-desa04**: Tiene sdb (932 GB) con `zfs_member` detectado en la partición sdb3 pero **NO hay pool ZFS activo**. Parece un disco preparado pero no configurado.
- **pve-desa03**: sdc (932 GB) está particionado como LVM member con VG `vm-storage` — parece preparado pero sin uso visible en storage.cfg.

---

## 5. Red

### Configuración actual

- **Red plana**: Todos los nodos en 192.168.1.0/24, mismo bridge vmbr0
- **Gateway**: 192.168.1.1
- **Corosync**: Usa link0 (interfaz única), sin link1 redundante
- **Latencia**: 0.2ms entre nodos (excelente para Corosync)
- **NICs libres**:
  - pve-desa04: eno2, eno3, eno4 sin configurar
  - pve-desa01: enp2s0 única disponible

### Diagnóstico

| Aspecto | Estado | Riesgo |
|---|---|---|
| Red dedicada Corosync | ❌ No | Tráfico de storage/VMs puede causar latencia |
| Red dedicada storage | ❌ No | Sin segregación de tráfico |
| Bonding/LACP | ❌ No | Sin redundancia de enlace |
| VLANs | ❌ No | Sin segmentación de red |
| Firewall cluster | ✅ Sí (firewall=1 en VMs) | |

---

## 6. Backups

### Estado actual

| Componente | Estado |
|---|---|
| Jobs de backup | ❌ **NINGUNO CONFIGURADO** |
| Proxmox Backup Server | ❌ No instalado |
| Dumps locales | ❌ Vacío |
| Almacenamiento para backups | Solo NFS compartido (desde pve-desa03) |

**CRÍTICO**: No hay backups de ninguna VM ni contenedor en toda la infraestructura.

---

## 7. Monitoreo

- **pve-ad** tiene un container `sg-monitoring` (CT 205) con 2 GB RAM, IP 192.168.1.205
- No se pudo determinar el stack de monitoreo desde afuera
- Sin Prometheus/Grafana visibles
- Sin alertas configuradas

---

## 8. Análisis de Configuraciones de VMs

### Aciertos ✅
- **VirtIO SCSI Single** con IO Thread en casi todas las VMs
- **Discard** habilitado en discos que lo soportan
- **OVMF (UEFI)** con Secure Boot en todas
- **Firewall** habilitado en interfaces de red

### Problemas ❌
- **VM DC2** usa `cache=writeback` — **peligroso**, puede causar corrupción en caso de corte eléctrico. Debería ser `cache=none` o `writethrough`
- **CPU type `x86-64-v2-AES`** en VMs de pve-desa01 — pierden optimizaciones del hardware real
- **NUMA deshabilitado** en todas (`numa: 0`) — relevante para VMs con >4 vCPUs
- **Memory ballooning**: sin configuración visible

---

## 9. Resumen de Hallazgos y Prioridades

### 🔴 Críticos (riesgo inmediato)

| # | Hallazgo | Impacto | Acción |
|---|---|---|---|
| C1 | **Sin backups** | Pérdida total de datos ante fallo de disco | Instalar PBS + configurar jobs |
| C2 | **Sin QDevice** (4 nodos, riesgo medio) | 2 nodos caídos = cluster bloqueado | Evaluar si aplica |
| C3 | **Cache writeback en DC2** | Corrupción de datos en corte eléctrico | Cambiar a `cache=none` |

### 🟡 Altos (deben resolverse pronto)

| # | Hallazgo | Impacto | Acción |
|---|---|---|---|
| H1 | **Sin ZFS** en ningún nodo | Sin checksum, sin compresión, sin snapshots eficientes | Migrar a ZFS con replicación |
| H2 | **Red plana** sin segregación | Latencia en Corosync, sin redundancia | Agregar link1, VLANs |
| H3 | **3 VMs Windows detenidas** en pve-desa01 | 9 GB RAM ocupados sin uso | Decidir: activar o eliminar |
| H4 | **NFS desde pve-desa03** | SPOF: si cae, storage compartido caído | Migrar a PBS o storage replicado |
| H5 | **pve-ad fuera del cluster** | Gestión separada, versión PVE 9 vs 8 | Evaluar migración o mantener separado |

### 🟢 Mejoras (optimización)

| # | Hallazgo | Acción |
|---|---|---|
| M1 | CPU type `x86-64-v2-AES` en vez de `host` | Cambiar a `host` si no hay migración cross-nodo |
| M2 | NUMA deshabilitado | Habilitar para VMs con recursos grandes |
| M3 | Discos preparados sin uso (pve-desa04 sdb, pve-desa03 sdc) | Incorporar a pools ZFS |
| M4 | Sin monitoreo visible | Configurar Prometheus + Grafana en sg-monitoring o PBS |
| M5 | 4 NICs en pve-desa04, 1 sola en uso | Bonding + VLANs para storage y Corosync |

---

## 10. Plan de Acción Recomendado

### Fase 0 — Correcciones inmediatas (esta sesión)
1. ✅ Auditoría completada (esta documentación)
2. ⬜ Cambiar cache writeback → none en VM 102 (DC2)
3. ⬜ Decidir qué hacer con las 3 VMs Windows detenidas
4. ⬜ Actualizar `secrets/proxmox.yaml` con los nodos reales

### Fase 1 — Backup (prioridad máxima)
1. ⬜ Instalar Proxmox Backup Server (ideal: HW separado o VM en pve-ad)
2. ⬜ Configurar jobs de backup diarios para TODAS las VMs
3. ⬜ Configurar retención: 7 daily + 4 weekly + 3 monthly

### Fase 2 — Storage (mediano plazo)
1. ⬜ Evaluar migración de LVM thin a ZFS
2. ⬜ Configurar replicación ZFS entre nodos (RPO 15 min)
3. ⬜ Ajustar ARC: 50% de RAM por defecto

### Fase 3 — Red (mediano plazo)
1. ⬜ Agregar link1 redundante para Corosync (usar 2da NIC donde disponible)
2. ⬜ Configurar VLAN separada para Corosync (ej. VLAN 10)
3. ⬜ Evaluar bonding (LACP) en pve-desa04

### Fase 4 — Optimización (continuo)
1. ⬜ Cambiar CPU type a `host` en VMs Linux
2. ⬜ Habilitar NUMA en VMs con >4 vCPUs o >16 GB
3. ⬜ Configurar Prometheus + PVE Exporter + Grafana
4. ⬜ Documentar procedimientos en este repo

---

## Notas de Aprendizaje

### Sobre la auditoría SSH
- Todos los nodos tienen autenticación por clave SSH desde esta máquina
- No se necesita password para acceder (verificar `~/.ssh/authorized_keys`)
- La latencia entre nodos es excelente (< 0.3ms)

### Sobre el cluster
- Proxmox 8.4.19 permite `pveversion --verbose` para ver versión detallada
- `pvecm status` da información completa de quorum
- `cat /etc/pve/storage.cfg` muestra configuración de storage compartido (accesible desde cualquier nodo)
- `cat /etc/pve/corosync.conf` muestra configuración de cluster (también desde cualquier nodo)
- `/etc/pve/` es un filesystem compartido (PMXCFS) — los cambios se replican a todos los nodos

### Sobre almacenamiento
- LVM thin vs ZFS: ZFS ofrece checksum, compresión (zstd), snapshots eficientes, cloning
- Para migrar de LVM a ZFS: se necesita storage temporal o mover VMs entre nodos
- ZFS ARC consume 50% de RAM por defecto — ajustable con `zfs_arc_max`

### Sobre pve-ad
- PVE 9.1.1 NO es compatible con cluster PVE 8.4 — no se puede unir al cluster
- Si se quiere unificar, ambos deben estar en la misma versión mayor
- Tiene 5 contenedores livianos + 1 VM (DC-VM) — podría funcionar como QDevice o PBS
