## Exploration: Almacenamiento Compartido Proxmox

### Current State

**Cluster**: 4 nodos (pve-desa01-04) en cluster pve-gidas, Proxmox 8.4.19 sobre Debian 12. Red 1 GbE compartida para todos los tráficos (Corosync, storage, VMs). Sin red dedicada de storage.

**Storage actual**: LVM thin provisioning en cada nodo como storage local. Cada nodo tiene su propio pool `local-lvm`. Sin almacenamiento compartido entre nodos — cada VM/CT está ligada al nodo donde se creó.

**Discos HDD disponibles** (según usuario):
- **pve-desa02**: 2 discos de 1 TB sin usar = 2 TB
- **pve-desa03**: 2 discos de 1 TB sin usar = 2 TB
- **Total**: 4 discos × 1 TB = 4 TB brutos

**⚠️ Discrepancia detectada vs auditoría (2026-05-27)**: La auditoría del cluster reporta que pve-desa02 tiene solo 1 HDD de 932 GB libre, y pve-desa03 tiene 2 HDDs de 932 GB (uno ocupado por NFS, otro por vm-storage VG). Total aproximado de 3 HDDs. **Verificar si hubo cambios de hardware desde la auditoría.**

**Lo que YA existe (F2 completado)**:
- Scripts de migración a ZFS local en `scripts/f2-storage-zfs/` ya escritos
- ZFS local ya implementado: pools `local-zfs` por nodo con `ashift=12`, `compression=zstd`, `atime=off`
- Replicación asíncrona entre pares fijos con RPO 15min/1h
- PBS en pve-ad para backups (directory-based, pendiente ZFS)
- Espec en `openspec/specs/proxmox/storage-zfs/spec.md`

**Lo que NO existe hoy y necesita compartido**:
- Live migration de VMs entre nodos (requiere shared storage para discos)
- Directorios compartidos entre nodos para Kubernetes PVs
- Almacenamiento para GitLab (repos + registry), container registry, backups

---

### Affected Areas

- `openspec/specs/proxmox/storage-zfs/spec.md` — modificar si se agrega esquema compartido
- `scripts/` — nuevos scripts de configuración de shared storage
- `/etc/pve/storage.cfg` — agregar storage compartido (NFS o Ceph)
- `/etc/pve/corosync.conf` — posiblemente link1 para segregar tráfico
- `/etc/network/interfaces` — posible configuración de VLAN para storage
- `openspec/specs/proxmox/network/spec.md` — posible extensión si se agrega VLAN de storage

---

### Alternativas Comparadas

#### 1. Ceph nativo en Proxmox — OSDs en los 4 discos HDD

**Arquitectura**: 2 nodos OSD (pve-desa02 y pve-desa03), 2 OSDs por nodo = 4 OSDs total. Monitores Ceph en cada nodo del cluster (pve-desa01-04). Red 1 GbE compartida.

| Aspecto | Evaluación |
|---------|-----------|
| **Capacidad útil** | 4 TB raw. Con 2-replica (min-rep=2, failure-domain=host): ~2 TB. Con 3-replica: NO posible (solo 2 hosts). |
| **Redundancia** | Con 2-replica y 2 hosts: falla 1 nodo → todas las PGs pierden 1 réplica → IO bloqueado. **Alto riesgo de data unavailability.** |
| **Performance** | HDD 7.2k + 1 GbE = catastrófico. Ceph escribe en paralelo a múltiples OSDs, saturando la red. Recovery de OSD (tras fallo) sobre 1 GbE con HDDs: días. |
| **Live Migration** | ✅ Sí, RBD soporta live migration nativa |
| **Soporte Proxmox GUI** | ✅ Nativo: Ceph integrado en PVE |
| **RAM requerida** | ~4-8 GB extra por nodo para OSDs + monitors (los monitores pueden ir en cualquier nodo) |
| **Complejidad** | **MUY ALTA**. Instalación, tuning, monitoreo continuo. Recovery lento. |
| **Veredicto** | ❌ **NO RECOMENDADO**. Ceph requiere mínimo 3 nodos OSD para operar decentemente. Con 2 hosts + 1 GbE + HDDs, la performance será mala y la confiabilidad baja. El overhead operativo no justifica los beneficios. |

#### 2. NFS + ZFS desde pve-desa03

**Arquitectura**: Pool ZFS en pve-desa03 con sus 2 discos, datasets exportados vía NFS al cluster. Posible replicación ZFS a pve-desa02 como standby.

| Aspecto | Evaluación |
|---------|-----------|
| **Capacidad útil** | Mirror 2 × 1TB = 1 TB usable (con redundancia). RAID0 striped = 2 TB (sin redundancia). |
| **Redundancia** | Mirror: tolera fallo de 1 disco. NFS server es SPOF. Se mitiga con replicación ZFS a pve-desa02 + failover manual. |
| **Performance** | 1 GbE = ~125 MB/s teórico. NFS overhead bajo (~5-10%). HDDs en mirror ~150 MB/s secuencial. **Cuello de botella: red**, no discos. Para ~160 GB de VMs actuales y directorios compartidos, es suficiente. |
| **Live Migration** | ✅ Sí, con NFS como storage compartido |
| **Soporte Proxmox GUI** | ✅ Nativo: Add → NFS, soporte en GUI |
| **RAM requerida** | Solo ZFS ARC en el nodo servidor (~7.5 GB para pve-desa03) |
| **Complejidad** | **BAJA**. NFS es probado, simple. `exportfs`, `/etc/exports`. ZFS ya está instalado. |
| **Veredicto** | ✅ **RECOMENDADO**. La opción más pragmática con los recursos disponibles. Bajo costo operativo, soporte nativo, performance adecuada. |

#### 3. GlusterFS distribuido sobre los 4 discos

**Arquitectura**: Brick en cada disco (4 bricks), replica 2 entre nodos. Cliente GlusterFS montado via FUSE en todos los nodos.

| Aspecto | Evaluación |
|---------|-----------|
| **Capacidad útil** | 4 TB raw. Replica 2 (cross-host): ~2 TB. |
| **Redundancia** | Replica 2: tolera fallo de disco, pero healing sobre 1 GbE es lento. Split-brain recovery es complejo. |
| **Performance** | GlusterFS tiene overhead significativo. Con FUSE + HDD + 1 GbE, rendimiento pobre para VMs. Metadata operations son particularmente lentas. |
| **Live Migration** | ⚠️ Posible si se monta como shared storage directory, pero no recomendado para VMs productivas |
| **Soporte Proxmox GUI** | ❌ No nativo. Se puede agregar como "Directory" (FUSE mount), pero sin integración GUI. |
| **Complejidad** | **MEDIA-ALTA**. Configuración de bricks, volumen options, healing. GlusterFS está en modo mantenimiento (Red Hat lo deprecó en favor de Ceph). |
| **Veredicto** | ❌ **NO RECOMENDADO**. GlusterFS está en declive, la performance sobre FUSE + HDD + 1 GbE es pobre, y no tiene soporte nativo en Proxmox. |

#### 4. DRBD + ZFS

**Arquitectura**: DRBD9 en modo Primary/Primary sobre los 4 discos (replicación síncrona block-level entre nodos), ZFS sobre los dispositivos DRBD.

| Aspecto | Evaluación |
|---------|-----------|
| **Capacidad útil** | 4 TB raw, DRBD replica síncrona cross-host = ~2 TB usable |
| **Redundancia** | DRBD replica síncrona: datos idénticos en ambos nodos. Tolerancia a fallo de nodo. |
| **Performance** | DRBD síncrono sobre 1 GbE: cada escritura espera ACK remoto → latencia alta. ~1-5 ms adicional por IO. Con HDDs, bottleneck mixto. |
| **Live Migration** | ✅ Sí con DRBD9 Primary/Primary |
| **Soporte Proxmox GUI** | ❌ No nativo. DRBD se configura manualmente. |
| **Complejidad** | **MUY ALTA**. DRBD necesita kernel module compilation, configuración de recursos, Pacemaker/Corosync para failover. Stack complejo: DRBD → LVM → ZFS → Pacemaker. |
| **Veredicto** | ❌ **NO RECOMENDADO**. Overhead operativo enorme. DRBD pierde sentido cuando ZFS replicación asíncrona logra RPO aceptable sin la complejidad. |

#### 5. ZFS sobre iSCSI (LIO/SCST)

**Arquitectura**: Pool ZFS en pve-desa03, volúmenes ZFS exportados como targets iSCSI (LIO target), los demás nodos conectan como initiators.

| Aspecto | Evaluación |
|---------|-----------|
| **Capacidad útil** | Igual que NFS + ZFS: 1-2 TB según mirror/stripe |
| **Redundancia** | SPOF: target node. Igual que NFS. |
| **Performance** | iSCSI overhead ligeramente mayor que NFS. Block-level (no filesystem), mejor para VMs. Pero 1 GbE sigue siendo bottleneck. |
| **Live Migration** | ✅ Sí, iSCSI LUN compartido como storage |
| **Soporte Proxmox GUI** | ✅ Soporte iSCSI nativo en GUI |
| **Complejidad** | **MEDIA**. Configuración de LIO target. Moderadamente más complejo que NFS. |
| **Veredicto** | ⚠️ **POSIBLE pero no mejor que NFS**. iSCSI da control block-level, pero para el caso de uso actual NFS es más simple y probado. No hay ventaja decisiva. |

---

### Tabla Comparativa

| Alternativa | Capacidad útil | Redundancia | Performance (1 GbE) | Live Migrate | Soporte GUI | Complejidad | Veredicto |
|---|---|---|---|---|---|---|---|
| **Ceph** | ~2 TB (2-rep) | Media (riesgo 2 hosts) | Mala | ✅ | ✅ Nativo | 🔴 Muy Alta | ❌ Inviable |
| **NFS + ZFS** | 1-2 TB | Media (SPOF, mitigable) | Aceptable | ✅ | ✅ Nativo | 🟢 Baja | ✅ **RECOMENDADO** |
| **GlusterFS** | ~2 TB (rep 2) | Media (healing lento) | Pobre | ⚠️ Limitado | ❌ No | 🟡 Media-Alta | ❌ No recomendado |
| **DRBD + ZFS** | ~2 TB | Alta (síncrono) | Lenta (sync) | ✅ | ❌ No | 🔴 Muy Alta | ❌ No recomendado |
| **iSCSI + ZFS** | 1-2 TB | Media (SPOF) | Aceptable | ✅ | ✅ Nativo | 🟡 Media | ⚠️ Alternativa a NFS |

---

### Recomendación

#### Arquitectura Híbrida: ZFS Local + NFS Compartido desde pve-desa03

**No hay una solución perfecta con 2 nodos OSD**. Ceph requiere 3+, DRBD es complejo, GlusterFS está deprecado. La opción más pragmática es:

```
┌──────────────────────────────────────────────────────────────┐
│                    Cluster Proxmox pve-gidas                   │
│                                                              │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐   │
│  │desa01    │  │desa02    │  │desa03    │  │desa04    │   │
│  │SSD 447GB │  │SSD 224GB │  │SSD 224GB │  │SSD 932GB │   │
│  │ZFS local │  │ZFS local │  │ZFS local │  │ZFS local │   │
│  │          │  │+2×1TB    │  │+2×1TB 🔥 │  │          │   │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘   │
│       │              │             │              │         │
│       └──────────────┴─────────────┴──────────────┘         │
│                         │ 1 GbE                             │
│                    ┌────▼────┐                              │
│                    │  NFS    │  pve-desa03 sirve NFS:       │
│                    │  shared │  └─ VMs con live migration   │
│                    │  storage│  └─ Kubernetes PVs           │
│                    └─────────┘  └─ GitLab repos/registry    │
│                                                              │
│  ┌──────────────────────────────────────────────┐           │
│  │  PBS (pve-ad, 192.168.1.31)                  │           │
│  │  └─ Backups diarios, retención 7+4+3         │           │
│  └──────────────────────────────────────────────┘           │
└──────────────────────────────────────────────────────────────┘
```

**Propuesta de distribución de discos**:

| Nodo | Discos HDD | Configuración | Capacidad | Uso |
|------|-----------|---------------|-----------|-----|
| **pve-desa03** | 2 × 1 TB | ZFS mirror | **1 TB** | **NFS shared** — VMs live migration, Kubernetes, GitLab, registry |
| **pve-desa02** | 2 × 1 TB | ZFS mirror | **1 TB** | Storage local redundante + **réplica ZFS asíncrona** de pve-desa03 (DR) |

**Por qué NFS gana sobre las alternativas**:
1. **Ya hay NFS funcionando** en pve-desa03 exportando ISOs/templates — es extender lo que existe
2. **Live migration funciona** con shared storage NFS en Proxmox (probado, documentado)
3. **1 GbE es suficiente** para el workload actual (~160 GB de VMs, pocas IOPS)
4. **ZFS + NFS da checksum, compresión, snapshots** — no se pierden los beneficios de ZFS
5. **Complejidad casi nula** — no requiere software nuevo, ni monitores, ni daemons extra
6. **Soporte nativo en GUI** de Proxmox para NFS storage

**Mitigaciones para SPOF del NFS**:
- ZFS replicación asíncrona de datasets críticos de pve-desa03 → pve-desa02 (mismo mecanismo que F2)
- Si pve-desa03 falla: montar NFS desde pve-desa02 (swap del export)
- PBS ya protege los datos con backups diarios

---

### Riesgos

| Riesgo | Probabilidad | Impacto | Mitigación |
|--------|-------------|---------|------------|
| **NFS SPOF** (pve-desa03 caído) | Media | 🔴 Toda VM en shared storage pierde acceso | Réplica ZFS a pve-desa02 + backup PBS |
| **1 GbE saturado** con NFS + replicación + tráfico VMs | Media | 🟡 Performance degradada para todos | QoS en el switch + limitar bw de replicación (500 Mbps ya configurado) |
| **HDD 7.2k lento** para VMs con escritura intensiva | Baja (workload actual liviano) | 🟡 IOPS baja | Usar mirror (mejor IOPS que parity). Evaluar SLOG en SSD si necesario. |
| **Discrepancia discos** (auditoría reporta 3 discos, no 4) | Alta | 🟡 Capacidad disponible puede ser menor | Verificar hardware actual ANTES de spec/design |
| **ZFS ARC + NFS cache** compiten por RAM | Media | 🟡 Presión de memoria en pve-desa03 | ARC ya limitado a 50%, monitorear con `arc_summary` |
| **Split-brain en failover NFS** si pve-desa03 vuelve sin sync completo | Baja | 🟡 Datos inconsistentes | Replicación ZFS asíncrona + verificación manual antes de failback |

---

### Próximos pasos (high-level)

1. **Verificar hardware actual** — ¿Cuántos discos HDD hay realmente en pve-desa02 y pve-desa03? La auditoría de mayo difiere de los 4×1TB mencionados.
2. **Elegir esquema de discos para pve-desa03** — ¿mirror (1TB, redundante) o stripe (2TB, sin redundancia)? Recomiendo mirror para datos compartidos.
3. **Diseñar datasets ZFS en pve-desa03** — separar por tipo: `shared-vms`, `shared-kubernetes`, `shared-gitlab`, `shared-registry`
4. **Configurar NFS exports** con opciones adecuadas: `async` (performance), `no_subtree_check`, `sec=sys`
5. **Configurar replicación ZFS** del pool compartido de pve-desa03 → pve-desa02 para DR
6. **Migrar VMs seleccionadas** a shared storage NFS para habilitar live migration
7. **Documentar procedimiento de failover** si pve-desa03 cae

---

### Ready for Proposal

**Yes** — La arquitectura está clara:
- **Unica opción viable**: NFS + ZFS desde pve-desa03
- Las demás (Ceph, GlusterFS, DRBD) no son factibles con 1 GbE + 2 nodos + HDDs
- La implementación es incremental sobre lo que F2 ya dejó instalado (ZFS, replicación)

El orchestrator debería decir al usuario:
> "La exploración confirma que NFS + ZFS desde pve-desa03 es la única alternativa viable con los recursos actuales. Ceph requeriría 3+ nodos y 10 GbE, DRBD y GlusterFS agregan complejidad sin ventajas reales. La propuesta detallará la distribución de datasets ZFS, configuración NFS, replicación a pve-desa02 como DR, y plan de migración para VMs con live migration."
