## Exploration: Mejora de Networking Proxmox

### Current State

**Red actual**: 1 GbE plana compartida para todo el tráfico del cluster pve-gidas. Sin segmentación física entre tráfico de datos, Corosync, NFS storage, replicación DR, backups a PBS, y tráfico de VMs. Throughput práctico ~110 MB/s.

**f3-network (scripts)**: Todos los 6 scripts existen en `scripts/f3-network/` y están diseñados para ser idempotentes (verifican estado antes de aplicar). Implementan:
- VLAN 10 para Corosync heartbeat (link1 redundante)
- Bonding LACP en pve-desa04 (4 NICs → bond0 → vmbr0)
- Firewall de cluster con reglas por segmento
- **NO está confirmado si estos scripts ya se ejecutaron en los nodos o están pendientes**. No hay verify-report de f3-network en el repo.

**storage-proxmox (ya implementado, archived)**:
- shared-zfs mirror en pve-desa03 → NFS exports a todo el cluster (vms, k8s, gitlab, registry, backups)
- local-zfs mirror en pve-desa02 + DR replicación (zfs send/recv diario)
- Live migration habilitada via NFS shared storage
- Bottleneck reconocido en el diseño (sección 12): "1 GbE saturado (NFS + VMs + replicación)"
- Warning W1 del verify-report: replicación DR **sin throttling** de ancho de banda

**Hardware de red por nodo** (de la auditoría de cluster):

| Nodo | NIC(s) | Libre | RAM | Rol relevante |
|------|--------|-------|-----|---------------|
| pve-desa01 | 1x enp2s0 | ❌ | 15 GB | Consumidor NFS |
| pve-desa02 | 1x enp1s0 | ❌ | 10 GB | DR target, consumidor NFS |
| pve-desa03 | 1x enp1s0 | ❌ | 15 GB | **NFS server** + Samba + consumidor |
| pve-desa04 | 4x eno1-4 | 3 libres | 15 GB | Bonding planned, consumidor NFS |
| pve-ad (PBS) | ? | ? | 15 GB | PBS (no en cluster) |

**Switch**: Mikrotik (mencionado en f3-network README). Sin configuración detallada en el repo. Se asume soporte básico VLAN tagging y LACP. Se **desconoce** si tiene puertos 10GbE SFP+.

### Afected Areas

- `scripts/f3-network/` — scripts existentes de VLAN/bonding/firewall (pendientes de ejecución o ya ejecutados)
- `openspec/specs/proxmox/network/spec.md` — spec actual cubre VLAN Corosync + bonding + firewall, NO cubre storage network, QoS, MTU
- `scripts/f3-shared-storage/04-replication.sh` — necesita bandwidth throttle (W1 del verify-report)
- `openspec/specs/proxmox/storage-nfs/spec.md` — requisito de performance NFS ≥80 MB/s, uso de red <70%
- `/etc/network/interfaces` en cada nodo — se modificarían para VLAN storage, bonding, MTU
- Switch Mikrotik — configuración de VLANs, LACP, posible QoS/MTU
- `openspec/specs/proxmox/network/spec.md` — necesitaría extensión para cubrir storage network

### Approaches

1. **Bandwidth Throttling + QoS (inmediato, sin HW)** — Implementar rate limiting en replicación DR y priorizar NFS vía tc
   - Pros: Sin costo de HW, resuelve W1 inmediatamente, implementable con scripts existentes
   - Cons: No aumenta el ancho de banda total, solo gestiona la contención
   - Esfuerzo: Bajo

2. **VLAN dedicada para storage (aislamiento lógico)** — VLAN 20 para NFS + replicación DR sobre el mismo link físico
   - Pros: Segmentación lógica, sin HW adicional, firewall diferenciado, coordina con patrón VLAN 10 existente
   - Cons: Sigue compartiendo 1 GbE físico — no resuelve bottleneck de ancho de banda
   - Esfuerzo: Bajo-Medio

3. **NIC adicional en nodos storage** — Agregar NIC 1 GbE a pve-desa03 (NFS server) y pve-desa02 (DR target) para red de storage dedicada
   - Pros: Aísla tráfico NFS/replicación del tráfico de cluster/VMs. Duplica ancho de banda efectivo para storage
   - Cons: pve-desa01/02/03 necesitan comprar NICs (~$20-50 c/u). pve-desa04 ya tiene 4 NICs (bonding). Requiere verificar slots PCIe libres
   - Esfuerzo: Medio (HW + configuración + verificación)

4. **Upgrade a 2.5GbE / 10GbE** — Reemplazar NICs + agregar switch con puertos de alta velocidad
   - Pros: Aumento significativo de ancho de banda (2.5x-10x). Beneficia NFS, replicación, live migration
   - Cons: Costo alto (NICs + switch). Compatibilidad desconocida del Mikrotik actual con 10GbE. pve-desa02 (AMD A10) puede no tener PCIe 3.0 x8 para 10GbE
   - Esfuerzo: Alto

5. **Jumbo Frames (MTU 9000)** — Configurar MTU 9000 en toda la cadena (NICs, switch, interfaces bridge, NFS)
   - Pros: Mejora throughput secuencial ~5-15% en 1 GbE. Reduce overhead de CPU en transfers grandes. Sin costo
   - Cons: Requiere verificación end-to-end. Si un segmento no soporta MTU 9000, causa fragmentación. Conflictos conocidos con Corosync (que espera MTU 1500). No recomendado para tráfico de cluster
   - Esfuerzo: Bajo (pero riesgo si no se verifica toda la cadena)

6. **Combinado: Throttling + VLAN storage + NIC en nodo NFS** — Enfoque híbrido: inmediato (throttling) + corto plazo (VLAN) + mediano plazo (NIC)
   - Pros: Aborda el problema en múltiples capas. Progresivo, sin bloqueo. Máximo beneficio por inversión
   - Cons: Más tiempo de implementación. Requiere planificación de fases
   - Esfuerzo: Medio (faseable)

### Recommendation

**Enfoque recomendado: Combinado por fases (Opción 6)**

La red 1 GbE compartida es el bottleneck estructural. La solución definitiva requiere ancho de banda adicional, pero hay mejoras inmediatas que no cuestan HW.

**Fase 1 — Inmediato (esta session)**: Implementar bandwidth throttling en replicación DR y priorización de NFS
- Corregir W1 del verify-report: agregar `pv -L 500m` o `bwlimit=500M` en `replicate-shared-to-dr.sh`
- Configurar QoS en pve-desa03 con `tc` para priorizar tráfico NFS (puerto 2049) sobre replicación y otros tráficos
- Sin costo, implementable desde scripts existentes

**Fase 2 — Corto plazo**: VLAN storage (aislamiento lógico) + verificar estado de f3-network
- Determinar si f3-network se ejecutó; si no, ejecutarlo (VLAN 10 Corosync + bonding + firewall)
- Crear VLAN 20 para NFS + replicación DR con firewall rules específicas
- La VLAN no agrega ancho de banda pero permite QoS y firewall más precisos

**Fase 3 — Mediano plazo**: NIC 1 GbE adicional en nodo NFS (pve-desa03)
- Agregar NIC PCIe 1 GbE a pve-desa03 para red de storage dedicada
- Opcional: NIC similar en pve-desa02 para tráfico de replicación DR
- Costo estimado: ~$20-50 por NIC usada (HP NC365T, Intel PRO/1000, etc.)

**No recomendado para este momento**:
- **10GbE**: Inversión alta, compatibilidad incierta con Mikrotik actual. Re-evaluar si se cambia switch.
- **Jumbo Frames**: Riesgo de impacto en Corosync. No justificado para el beneficio marginal en 1 GbE.
- **Upgrade de NICs en todos los nodos**: pve-desa01 es consumidor NFS puro — no necesita más ancho de banda.

### Dependencia con storage-proxmox

- **Crítica**: El bandwidth throttle en replicación DR (W1) debe implementarse SÍ o SÍ — es deuda técnica del cambio storage-proxmox que impacta directamente la red. Sin esto, la replicación saturará el 1 GbE compartido.
- **Media**: Los scripts NFS en pve-desa03 (`02-configure-nfs.sh`) no tienen QoS. Si se implementa VLAN storage, los exports NFS deben actualizarse para bind a la interfaz/IP correcta.
- **Baja**: Live migration (vía shared NFS) se beneficia de cualquier mejora de red pero no requiere cambios en los scripts de storage.
- **Sin dependencia**: La VLAN 10 de Corosync (f3-network) es independiente del storage. Puede ejecutarse en paralelo.

### Risks

- **R1 — Mikrotik desconocido**: No tenemos la configuración actual del switch. Se asume soporte VLAN tagging y LACP, pero QoS, MTU 9000, y disponibilidad de puertos 10GbE no están verificados. **Requerimiento**: inspeccionar/configurar Mikrotik antes de Fase 2.
- **R2 — Slots PCIe**: No sabemos si pve-desa03 (i5-7400, placa probablemente H110/B250) tiene slots PCIe x4/x8 libres para NIC adicional. Puede requerir riser o cambiar a USB 2.5GbE como alternativa.
- **R3 — f3-network sin ejecutar**: Si los scripts f3-network no se ejecutaron, hay que ejecutarlos primero (VLAN 10 + bonding + firewall) antes de agregar VLAN storage.
- **R4 — QoS mal configurado**: Un tc mal configurado puede degradar todo el tráfico. Probar en ventana de mantenimiento.
- **R5 — Costo de NIC**: Si se requieren NICs, hay que comprarlas. Tiempo de entrega puede retrasar Fase 3.

### Ready for Proposal

**Yes** — El análisis está completo. Las alternativas son claras y faseables. Recomiendo `sdd-propose` para formalizar el cambio `network-proxmox` con:

1. Corrección inmediata: bandwidth throttle en replicación DR (W1 de storage-proxmox)
2. QoS para NFS en pve-desa03
3. Verificación de estado de f3-network
4. Evaluación de HW (switch Mikrotik + slots PCIe)
5. Diseño de VLAN storage (VLAN 20)
