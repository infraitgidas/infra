# F3 — Red VLAN (P2)

## Objetivo

Segmentar la red del cluster agregando una VLAN dedicada para Corosync,
redundancia de enlaces en el anillo de quorum, y bonding LACP en nodos
con múltiples NICs disponibles.

## Arquitectura

```
Antes:                          Después:
  Red plana                      Segmentación VLAN
  └── Corosync + datos           ├── link0: vmbr0  (192.168.1.0/24) — datos
      comparten mismo link       └── link1: vmbr0.10 (10.0.10.0/24) — heartbeat

pve-desa04:
  eno1 → vmbr0                   eno1-4 ──LACP──→ bond0 ──→ vmbr0
  (single NIC sin redundancia)    └── vmbr0.10 (VLAN 10) sobre bridge
```

## Topología por Nodo

| Nodo | RAM | Bridge | VLAN 10 IP | Bonding | 
|------|-----|--------|------------|---------|
| pve-desa01 | 15 GB | vmbr0 → eno1 | 10.0.10.11/24 | No |
| pve-desa02 | 10 GB | vmbr0 → eno1 | 10.0.10.12/24 | No |
| pve-desa03 | 15 GB | vmbr0 → eno1 | 10.0.10.13/24 | No |
| pve-desa04 | 15 GB | vmbr0 → bond0 → eno1-4 | 10.0.10.14/24 | Sí (LACP) |

## Corosync Links

| Link | Red | Interfaz | Propósito |
|------|-----|----------|-----------|
| link0 | 192.168.1.0/24 | vmbr0 | Tráfico de datos, migración, API |
| link1 | 10.0.10.0/24 | vmbr0.10 | Heartbeat Corosync, redundancia |

## Orden de Ejecución

Los scripts **deben ejecutarse en orden** en esta máquina (no en los nodos):

```bash
# 0. Cargar configuración de entorno
source 00-env.sh

# 1. Configurar VLAN 10 en cada nodo (Task 3.1)
./01-vlan.sh

# 2. Agregar link1 redundante a corosync.conf (Task 3.2)
./02-corosync-link1.sh

# 3. Reiniciar corosync nodo por nodo (Task 3.3)
./03-restart-corosync.sh

# 4. Configurar bonding LACP en pve-desa04 (Task 3.4)
./04-bonding.sh

# 5. Crear reglas firewall de cluster (Task 3.5)
./05-firewall.sh

# 6. Verificar todo (Task 3.6)
./06-verify.sh
```

## Configuraciones Clave

### VLAN 10 en /etc/network/interfaces

```bash
# En cada nodo del cluster
auto vmbr0.10
iface vmbr0.10 inet static
    address 10.0.10.1X/24
    vlan-raw-device vmbr0
```

### Bonding LACP en /etc/network/interfaces (pve-desa04)

```bash
auto bond0
iface bond0 inet manual
    bond-slaves eno1 eno2 eno3 eno4
    bond-mode 802.3ad
    bond-miimon 100
    bond-lacp-rate fast
    bond-xmit-hash-policy layer2+3

auto vmbr0
iface vmbr0 inet static
    address 192.168.1.14/24
    gateway 192.168.1.1
    bridge-ports bond0
    bridge-stp off
    bridge-fd 0
```

### Corosync link1

```yaml
# En /etc/pve/corosync.conf (se sincroniza vía pmxcfs)
totem {
    interface {
        linknumber: 0
        bindnetaddr: 192.168.1.0
    }
    interface {
        linknumber: 1
        bindnetaddr: 10.0.10.0
    }
}

nodelist {
    node {
        name: pve-desa01
        ring0_addr: 192.168.1.11
        ring1_addr: 10.0.10.11
    }
    # ... resto de nodos
}
```

## Verificación

```bash
# Estado de Corosync (ambos links)
corosync-cfgtool -s

# Estado del bonding
cat /proc/net/bonding/bond0

# Estado del cluster
pvecm status

# Conectividad VLAN 10
ping -c 3 10.0.10.12

# Firewall activo
pve-firewall status
```

## Rollback

### Revertir VLAN 10

```bash
# Restaurar interfaces originales (en cada nodo)
cp /etc/network/interfaces.backup.<fecha> /etc/network/interfaces

# O eliminar solo la VLAN
sed -i '/^auto vmbr0\.10/,/^$/d' /etc/network/interfaces

# Desactivar interfaz
ip link set vmbr0.10 down
ip link delete vmbr0.10

# Aplicar cambios
ifreload -a
```

### Revertir corosync.conf

```bash
# Restaurar backup
cp /etc/pve/corosync.conf.backup.<fecha> /etc/pve/corosync.conf

# Reiniciar corosync en cada nodo
systemctl restart corosync

# Verificar quorum
pvecm status
```

### Revertir bonding (pve-desa04)

```bash
# Restaurar interfaces originales
cp /etc/network/interfaces.bonding.backup.<fecha> /etc/network/interfaces

# O desde consola local:
# Reemplazar bridge ports de bond0 a eno1
# y eliminar configuración bond0

# Reiniciar red o nodo
reboot
```

### Revertir firewall

```bash
# Eliminar archivo de reglas
rm /etc/pve/firewall/cluster.fw

# Deshabilitar firewall de datacenter
pvesh set /cluster/options --firewall 0

# O restaurar backup
cp /etc/pve/firewall/cluster.fw.backup.<fecha> /etc/pve/firewall/cluster.fw
```

## Limitaciones Conocidas

1. **Switch requerido**: VLAN 10 tagging y LACP requieren configuración en el switch Mikrotik. Los scripts asumen que los puertos están en modo trunk con VLAN 10 tagged, y que los puertos de pve-desa04 están configurados como LACP bond.
2. **Sin NIC extra**: VLAN 10 comparte el mismo medio físico que los datos. Si el link físico se cae, ambos links de Corosync se pierden. La redundancia protege contra fallo de NIC individual (en bonding) pero no contra fallo de cable o switch.
3. **Bonding en caliente limitado**: El script 04-bonding.sh intenta configurar el bonding en caliente, pero algunos cambios (esclavizar NICs que ya están en el bridge) pueden requerir un reinicio completo de red o del nodo.
4. **Corosync restart**: El reinicio de corosync puede causar una breve pérdida de quorum. El script 03-restart-corosync.sh maneja la espera de quorum entre nodos.
5. **Firewall**: El firewall de Proxmox puede afectar la migración en vivo y la replicación si las reglas no están correctamente definidas. Verificar después de aplicar.
6. **pve-desa01 (single disk)**: Usa LVM-backed ZFS, lo que limita la redundancia de I/O pero es aceptable para el entorno de desarrollo.

## Prerequisitos

1. Acceso SSH sin contraseña (key-based) a todos los nodos como root
2. Switch con VLAN 10 configurada como tagged en puertos de todos los nodos
3. Switch con LACP configurado en los puertos de pve-desa04 (eno1-4)
4. Paquetes instalados: `ifenslave` (para bonding), `vlan` (para VLAN)
5. Cluster Proxmox funcional (pvecm status OK)

### Instalación de paquetes necesarios (si no están)

```bash
for node in pve-desa01 pve-desa02 pve-desa03 pve-desa04; do
    ssh root@$node "apt-get update && apt-get install -y ifenslave vlan"
done
```
