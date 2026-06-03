# Propuesta: Almacenamiento Compartido Proxmox

## Resumen Ejecutivo

Migrar de LVM thin + NFS improvisado a **ZFS mirror en cada nodo** con almacenamiento compartido vía NFS desde pve-desa03 para habilitar live migration, Kubernetes PVs, GitLab, registry, y backups con redundancia local y DR replicado.

**Arquitectura**: 2 pools ZFS mirror (~1 TB usable cada uno), uno local y otro compartido. Replicación asíncrona del pool compartido a pve-desa02 para DR. PBS como respaldo externo.

---

## Hardware y Topología

```
                ┌────────── Cluster Proxmox pve-gidas ──────────┐
                │                                                 │
  pve-desa01    │  pve-desa02           pve-desa03     pve-desa04 │
  SSD 224G      │  SSD 224G             SSD 224G       SSD 932G  │
  ZFS local     │  ┌─────────────────┐  ┌──────────────────┐     │
                │  │ sdb 932G  ◀──┐  │  │ sda 932G  ◀──┐   │     │
                │  │               │  │  │ (part: NFS)  │   │     │
                │  │ sdc 932G  ◀──┤  │  │ sdc 932G  ◀──┤   │     │
                │  └─────mirror────┘  │  └─────mirror────┘   │     │
                │       local-zfs     │       shared-zfs      │     │
                │        1 TB         │        1 TB           │     │
                │       (DR target)   │    (NFS source) 🔥    │     │
                └─────────┬───────────┴──────────┬────────────┘     │
                          │                      │                  │
                          └──────── 1 GbE ───────┘                  │
                                     │                              │
                            ┌────────▼────────┐                    │
                            │  PBS (pve-ad)    │                    │
                            │  192.168.1.31   │                    │
                            │  Backups diarios │                    │
                            └─────────────────┘                    │
                └──────────────────────────────────────────────────┘
```

**Red**: 1 GbE compartida (Corosync + storage + VMs). Sin red dedicada de storage — limitación conocida, mitigada con QoS en replicación.

---

## Layout Propuesto

| Nodo | Pool | Discos | Layout | Capacidad | Rol |
|------|------|--------|--------|-----------|-----|
| pve-desa02 | `local-zfs` | sdb + sdc | **mirror** | ~932 GB | Local redundante + DR target de shared-zfs |
| pve-desa03 | `shared-zfs` | sda + sdc | **mirror** | ~932 GB | NFS compartido + storage VMs live migration |

**Total usable**: ~1.86 TB (3.7 TB raw, mirror 50% eficiencia). Tolerancia a 1 fallo de disco por nodo.

**Cambios vs F2 actual**: F2 dejó pools single-disk (`local-zfs` en cada nodo). Esta propuesta los convierte a mirror y agrega `shared-zfs` en pve-desa03.

---

## Datasets / Filesystems

**Pool `shared-zfs` en pve-desa03** — exportado vía NFS:

| Dataset | Mount | NFS Export | Quota | Uso |
|---------|-------|------------|-------|-----|
| `shared-zfs/vms` | `/shared-zfs/vms` | Sí | ~600 GB | Discos de VMs con live migration |
| `shared-zfs/kubernetes` | `/shared-zfs/kubernetes` | Sí | ~100 GB | PVs dinámicos para K8s |
| `shared-zfs/gitlab` | `/shared-zfs/gitlab` | Sí | ~100 GB | Repositorios + registry GitLab |
| `shared-zfs/registry` | `/shared-zfs/registry` | Sí | ~50 GB | Container registry |
| `shared-zfs/backups` | `/shared-zfs/backups` | Sí | ~50 GB | Backups de infraestructura |
| `shared-zfs/samba` | `/shared-zfs/samba` | Sí (Samba) | ~32 GB | Archivos compartidos por CIFS |

**Parámetros ZFS**: `compression=zstd`, `atime=off`, `recordsize=1M` (o 128K para vms), `xattr=sa`.

**ARC**: Limitado a 50% RAM (~7.5 GB en pve-desa03, ~5 GB en pve-desa02).

**Replicación**: Datasets críticos de `shared-zfs` → `local-zfs` en pve-desa02 vía `zfs send` incremental (cron diario o sanoid). RPO ~24h.

**Snapshots programados**: Diarios vía sanoid con retención de 7 días (mismo esquema que F2).

**Pool `local-zfs` en pve-desa02** — storage local (no exportado):

| Dataset | Uso |
|---------|-----|
| `local-zfs/vms` | VMs locales (no migrables sin shared) |
| `local-zfs/backup-dr` | Réplica DR de datasets compartidos |

---

## Funcionalidades Soportadas

| Funcionalidad | Storage | Cómo |
|---------------|---------|------|
| **VMs live migration** | NFS `shared-zfs/vms` | Storage compartido NFS en Proxmox → live migration vía GUI/CLI |
| **CTs (contenedores)** | NFS o local | CTs pueden usar NFS (shared) o local-zfs según criticidad |
| **Directorios compartidos** | NFS `shared-zfs/kubernetes` | Montaje NFS en nodos, bind mount a pods via PV/PVC |
| **Kubernetes PVs** | NFS `shared-zfs/kubernetes` | NFS provisioner dinámico o PVs estáticos |
| **GitLab repos + registry** | NFS `shared-zfs/gitlab` | Volumen montado en container/VM de GitLab |
| **Container registry** | NFS `shared-zfs/registry` | Almacenamiento de imágenes Docker vía NFS |
| **Backups infra** | NFS `shared-zfs/backups` | Backup de configs, scripts, dumps |
| **Snapshots ZFS** | Ambos pools | sanoid / cron → snapshots diarios + retención 7 días |
| **DR** | local-zfs (pve-desa02) | Replicación ZFS asíncrona de shared-zfs → local-zfs |
| **Samba/CIFS** | NFS `shared-zfs/samba` | Samba export desde pve-desa03 o CT separado con mount NFS |

---

## Migración desde estado actual

**Estado actual (post-F2)**:
- pve-desa02: pool `local-zfs` single-disk en `/dev/sdc` (932G HDD libre original)
- pve-desa03: sda particionado (sda1=800G NFS, sda2=131.5G iso-storage) + sdc ocupado por LVM thin `vm-storage`

**Pasos de alto nivel**:

```
Fase 1: Preparación (read-only)
├── Verificar hardware actual (lsblk, blkid en ambos nodos)
├── Hacer backup completo a PBS de todas las VMs en pve-desa02 y pve-desa03
└── Verificar que no hay VMs/CTs críticas en storage a modificar

Fase 2: pve-desa03 — migrar a mirror
├── Migrar VMs/CTs de pve-desa03 a pve-desa02 (live si están running)
├── Destruir VG `vm-storage` + liberar sdc
├── Hacer backup de datos NFS actuales (ISOs/templates)
├── Limpiar particiones de sda (mover ISOs a storage temporal)
├── Crear pool `shared-zfs` mirror con sda + sdc
├── Crear datasets (vms, kubernetes, gitlab, registry, backups, samba)
├── Configurar NFS exports en cada dataset
├── Configurar ARC, compression, atime, recordsize
├── Restaurar ISOs/templates en dataset dedicado
├── Migrar VMs de vuelta a shared-zfs
└── Agregar NFS storage en Proxmox GUI en todos los nodos

Fase 3: pve-desa02 — migrar a mirror
├── Migrar VMs/CTs de pve-desa02 a pve-desa03 (shared NFS disponible)
├── Agregar sdb al pool `local-zfs` como mirror (o recrear pool)
├── Migrar VMs de vuelta a local-zfs
└── Verificar que pve-desa02 puede montar shared NFS

Fase 4: Replicación + DR
├── Configurar replicación ZFS de shared-zfs → local-zfs datasets
├── Configurar sanoid/cron para snapshots diarios
├── Documentar procedimiento de failover NFS
└── Probar failover (simular caída de pve-desa03)

Fase 5: Verificación
├── Probar live migration de VM entre nodos
├── Verificar montaje NFS desde todos los nodos
├── Verificar snapshots y replicación
└── Verificar backups a PBS
```

---

## Riesgos y Mitigaciones

| Riesgo | Probabilidad | Impacto | Mitigación |
|--------|-------------|---------|------------|
| **SPOF NFS** (pve-desa03 caído) | Media | 🔴 Toda VM en shared storage pierde acceso | Réplica ZFS a pve-desa02 + backups PBS + documentación de failover manual |
| **1 GbE saturado** (NFS + replicación + VMs) | Media | 🟡 Performance degradada | QoS en replicación (500Mbps), monitorear uso de red. Evaluar VLAN de storage si necesario |
| **HDD 7.2k lento** para VMs | Baja (workload liviano ~160GB) | 🟡 IOPS reducida | Mirror mejora IOPS de lectura. Evaluar SLOG en SSD si performance insuficiente |
| **sda particionado** en pve-desa03 | Alta | 🟡 Requiere mover datos NFS existentes antes de crear mirror | Backup a PBS + storage temporal en pve-desa02 durante migración |
| **pve-desa02 RAM baja** (10 GB) | Media | 🟡 ARC limitado a 5GB, presión de memoria | ARC 50% (5GB). Monitorear con `arc_summary` |
| **Discrepancia discos** (audit mayo vs hoy) | Alta | 🟡 Capacidad puede diferir | Verificado por usuario: 4 HDDs confirmados (2 por nodo) |

---

## Próximos Pasos

1. ✅ **Esta propuesta** — lista para spec/design
2. `sdd-spec` — actualizar spec `proxmox/storage-zfs` (mirror vdev, shared datasets) + nueva spec `proxmox/storage-nfs` (NFS exports, failover)
3. `sdd-design` — diseño detallado de migración, comandos exactos, validaciones
4. `sdd-tasks` — desglose en tareas ejecutables
5. Ejecutar migración en orden Fase 1→5
6. Probar live migration y failover antes de dar por terminado

---

## Criterios de Éxito

- [ ] **Live migration funcional**: VM migrada entre pve-desa02 y pve-desa03 sin downtime visible via NFS shared storage
- [ ] **Mirror ZFS operativo**: `zpool status` muestra ambos pools como ONLINE con mirror vdev
- [ ] **NFS accesible desde todos los nodos**: `showmount -e pve-desa03` desde c/nodo lista los exports esperados
- [ ] **Snapshots diarios automáticos**: sanoid o cron crean snapshots con retención de 7 días
- [ ] **Replicación DR funcional**: datasets de shared-zfs replicados a local-zfs en pve-desa02
- [ ] **Backups PBS**: todas las VMs tienen backup configurado y verificado después de la migración
- [ ] **Performance aceptable**: `dd` secuencial sobre NFS ≥ 80 MB/s (1 GbE bottleneck ~112 MB/s teórico)
- [ ] **No hay regresión**: VMs existentes funcionan igual o mejor que con LVM thin
