# Proposal: Mejora de Networking Proxmox

## Intent

El cluster pve-gidas comparte un único link 1 GbE (RB951G, 5 puertos, sin libres) para NFS, replicación DR, Corosync, live migration y VMs. La replicación DR satura el link (W1 de storage-proxmox). Sin puertos ni switch nuevo, resolvemos contención vía throttling + QoS, ejecutamos segmentación VLAN/bonding/firewall existente (f3-network), y diferimos red dedicada a rama aparte.

## Scope

### In Scope
- F1: Bandwidth throttle en replicación DR (pve-desa02 → pve-desa03)
- F1: QoS `tc` en pve-desa03 para priorizar NFS (puerto 2049)
- F2: Ejecutar f3-network (VLAN 10 → Corosync link1 → bonding pve-desa04 → firewall)
- F2: Configuración switch Mikrotik para VLAN 10 tagged + LACP

### Out of Scope
- Switch de storage dedicado (rama `feature/mikrotik-switch`)
- NIC PCIe adicional en nodos (post-switch)
- Jumbo frames (MTU 9000 — riesgo con Corosync)
- Upgrade 10GbE

## Capabilities

### New Capabilities
- `network-qos`: Bandwidth throttling y QoS para NFS y replicación DR
- `network-storage`: VLAN 20 para storage NFS (futuro, post-switch)

### Modified Capabilities
- `proxmox/network`: Se ejecuta f3-network existente (VLAN 10, Corosync link1, bonding, firewall). No cambian requisitos del spec, solo se implementa lo ya especificado.

## Approach

**F1 — Inmediato**: Agregar `bwlimit=500M` al `zfs send` en `04-replication.sh` (script `replicate-shared-to-dr.sh`). Configurar qdisc `htb` con `tc` en pve-desa03: prioridad alta para src port 2049, baja para replicación, best-effort para resto.

**F2 — Corto plazo**: Ejecutar f3-network en orden: 01-vlan → 02-corosync-link1 → 03-restart-corosync → 04-bonding → 05-firewall → 06-verify. Verificar switch Mikrotik antes (lado-a-lado con nodos).

**F3 — Diferido**: Crear rama `feature/mikrotik-switch`. Agregar switch gerenciable + NICs para red storage dedicada.

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `scripts/f3-shared-storage/04-replication.sh` | Modified | Bandwidth throttle en zfs send |
| `scripts/f3-network/*` | Executed | Ejecutar scripts existentes |
| `/etc/network/interfaces` (4 nodos) | Modified | VLAN 10 + bonding pve-desa04 |
| `/etc/pve/corosync.conf` | Modified | link1 (10.0.10.0/24) |
| `/etc/pve/firewall/cluster.fw` | Created | Reglas por segmento |
| switch Mikrotik RB951G | Configured | VLAN 10 tagged + LACP |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Switch sin soporte VLAN/LACP | Med | Inspeccionar antes de F2; si no soporta, abortar bonding |
| f3-network ya ejecutado | Med | Scripts idempotentes: verifican antes de aplicar |
| QoS mal configurado satura NFS | Bajo | Probar en ventana de mantenimiento; rollback via `tc qdisc del` |
| Corosync restart pierde quorum | Bajo | Script maneja espera entre nodos |

## Rollback Plan

- **F1 throttle**: Revertir cambios en `replicate-shared-to-dr.sh` y re-ejecutar `04-replication.sh`
- **F1 QoS**: `tc qdisc del dev vmbr0 root` en pve-desa03
- **F2 VLAN**: Restaurar `/etc/network/interfaces.backup.*` → `ifreload -a`
- **F2 bonding**: Restaurar interfaces + reboot nodo
- **F2 firewall**: `rm /etc/pve/firewall/cluster.fw` + `pvesh set /cluster/options --firewall 0`
- **F2 Corosync**: Restaurar `/etc/pve/corosync.conf.backup.*` → restart corosync

## Dependencies

- **storage-proxmox** (archive): throttle necesario para no saturar 1 GbE
- **f3-network base**: VLAN + bonding deben ejecutarse antes de agregar red storage
- **Switch Mikrotik**: Configuración VLAN/LACP debe verificarse antes de F2

## Success Criteria

- [ ] Replicación DR no supera 500 Mbps en horario pico NFS
- [ ] NFS throughput ≥80 MB/s durante replicación concurrente
- [ ] Corosync link1 activo en VLAN 10 con ping <1ms entre nodos
- [ ] Bonding LACP activo en pve-desa04 (4 NICs agregadas)
- [ ] Firewall bloquea tráfico entre VLAN 10 y datos (excepto Corosync)
- [ ] Rollback completo en <15 min si algo falla
