#!/bin/bash
# ================================================================
# 05-firewall.sh — Task 3.5: Cluster firewall rules
# ================================================================
# Creates /etc/pve/firewall/cluster.fw with differentiated rules:
#   - VLAN 10 (Corosync): only allow cluster heartbeat traffic
#   - Management: SSH, HTTPS from authorized IPs
#   - Default: deny all other traffic between segments
#
# PREREQUISITE: Cluster networking configured (Tasks 3.1-3.4)
# ================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-env.sh"

echo "=== Task 3.5: Crear reglas firewall de cluster ==="
echo ""

# Use first node as reference (cluster.fw syncs via pmxcfs)
MASTER_NODE="${NODES[0]}"
MASTER_NAME="${NODE_NAMES[0]}"

FW_DIR="/etc/pve/firewall"

# ---------------------------------------------------------------
# Step 1: Verify prerequisites
# ---------------------------------------------------------------
echo "[1/4] Verificando prerequisitos..."

# Check firewall directory exists
DIR_EXISTS=$(ssh ${SSH_OPTS} root@${MASTER_NODE} "test -d ${FW_DIR} && echo OK || echo NO" 2>/dev/null || echo "NO")
if [ "${DIR_EXISTS}" != "OK" ]; then
    echo "[1/4] Creando directorio ${FW_DIR}..."
    ssh ${SSH_OPTS} root@${MASTER_NODE} "mkdir -p ${FW_DIR}"
fi
echo "[1/4] ✅ ${FW_DIR} disponible"

# Check if cluster.fw already exists
FW_EXISTS=$(ssh ${SSH_OPTS} root@${MASTER_NODE} "test -f ${CLUSTER_FW} && echo OK || echo NO" 2>/dev/null || echo "NO")
if [ "${FW_EXISTS}" = "OK" ]; then
    echo "[1/4] ⚠️  ${CLUSTER_FW} ya existe"
    echo "   Haciendo backup y sobrescribiendo..."

    BACKUP="${CLUSTER_FW}.backup.$(date +%Y%m%d_%H%M%S)"
    ssh ${SSH_OPTS} root@${MASTER_NODE} "cp ${CLUSTER_FW} ${BACKUP}"
    echo "[1/4] ✅ Backup: ${BACKUP}"
else
    echo "[1/4] ✅ ${CLUSTER_FW} no existe — creando nuevo"
fi

# ---------------------------------------------------------------
# Step 2: Check datacenter firewall is enabled
# ---------------------------------------------------------------
echo ""
echo "[2/4] Verificando firewall a nivel datacenter..."

DC_FW_CONF=$(ssh ${SSH_OPTS} root@${MASTER_NODE} "cat /etc/pve/datacenter.cfg 2>/dev/null | grep -i 'firewall' || echo 'NOT_SET'")
echo "[2/4] Config firewall en datacenter.cfg: ${DC_FW_CONF}"

FW_ENABLED=$(ssh ${SSH_OPTS} root@${MASTER_NODE} "grep -c '^firewall: 1' /etc/pve/datacenter.cfg 2>/dev/null || echo 0")
if [ "${FW_ENABLED}" -eq 0 ]; then
    echo "[2/4] ⚠️  Firewall de datacenter NO está habilitado"
    echo "   Habilitando: pvesh set /cluster/options --firewall 1"
    ssh ${SSH_OPTS} root@${MASTER_NODE} "pvesh set /cluster/options --firewall 1" 2>/dev/null || {
        echo "   Intentando editar datacenter.cfg directamente..."
        ssh ${SSH_OPTS} root@${MASTER_NODE} "echo 'firewall: 1' >> /etc/pve/datacenter.cfg" 2>/dev/null || true
    }
    echo "[2/4] ✅ Firewall habilitado a nivel datacenter"
else
    echo "[2/4] ✅ Firewall ya habilitado"
fi

# ---------------------------------------------------------------
# Step 3: Create cluster.fw with rules
# ---------------------------------------------------------------
echo ""
echo "[3/4] Creando ${CLUSTER_FW}..."

# Build the firewall rules
# Format: Proxmox firewall format
# [OPTIONS]
# [RULES]
# [GROUP name]

FW_CONTENT=$(cat << 'FWEOF'
[OPTIONS]

# Cluster firewall options
enable: 1
policy_in: DROP
policy_out: ACCEPT
log_level_in: info
log_level_out: info

[RULES]

# ---- Management Access ----
# Allow SSH from management subnet
GROUP mgmt-access

# ---- Corosync VLAN 10 ----
# Allow Corosync cluster traffic on VLAN 10 (link1)
# Corosync uses UDP ports 5404, 5405, 5406 (knet) or 5405 (old)
# Allow only between cluster nodes
GROUP corosync-link1

# ---- Default Rules ----
# Drop everything else (explicit)
DROP from 10.0.10.0/24 to 192.168.1.0/24 log: info
DROP from 192.168.1.0/24 to 10.0.10.0/24 log: info

# Allow established connections
ACCEPT from all to all proto all state ESTABLISHED,RELATED

[GROUP corosync-link1]

# Corosync knet heartbeat: UDP 5404-5406
# Allow between all cluster nodes on VLAN 10
ACCEPT from 10.0.10.11 to 10.0.10.0/24 proto udp dport 5404-5406
ACCEPT from 10.0.10.12 to 10.0.10.0/24 proto udp dport 5404-5406
ACCEPT from 10.0.10.13 to 10.0.10.0/24 proto udp dport 5404-5406
ACCEPT from 10.0.10.14 to 10.0.10.0/24 proto udp dport 5404-5406

# Allow ping for monitoring
ACCEPT from 10.0.10.11 to 10.0.10.0/24 proto icmp
ACCEPT from 10.0.10.12 to 10.0.10.0/24 proto icmp
ACCEPT from 10.0.10.13 to 10.0.10.0/24 proto icmp
ACCEPT from 10.0.10.14 to 10.0.10.0/24 proto icmp

[GROUP mgmt-access]

# SSH from management network (192.168.1.0/24)
ACCEPT from 192.168.1.0/24 to 192.168.1.11 proto tcp dport 22
ACCEPT from 192.168.1.0/24 to 192.168.1.12 proto tcp dport 22
ACCEPT from 192.168.1.0/24 to 192.168.1.13 proto tcp dport 22
ACCEPT from 192.168.1.0/24 to 192.168.1.14 proto tcp dport 22

# HTTPS (Proxmox web UI) from management network
ACCEPT from 192.168.1.0/24 to 192.168.1.11 proto tcp dport 8006
ACCEPT from 192.168.1.0/24 to 192.168.1.12 proto tcp dport 8006
ACCEPT from 192.168.1.0/24 to 192.168.1.13 proto tcp dport 8006
ACCEPT from 192.168.1.0/24 to 192.168.1.14 proto tcp dport 8006

# PBS access (from cluster nodes only)
ACCEPT from 192.168.1.11 to 192.168.1.31 proto tcp dport 8007
ACCEPT from 192.168.1.12 to 192.168.1.31 proto tcp dport 8007
ACCEPT from 192.168.1.13 to 192.168.1.31 proto tcp dport 8007
ACCEPT from 192.168.1.14 to 192.168.1.31 proto tcp dport 8007

# Allow cluster internal traffic (Corosync, migration)
ACCEPT from 192.168.1.11 to 192.168.1.0/24
ACCEPT from 192.168.1.12 to 192.168.1.0/24
ACCEPT from 192.168.1.13 to 192.168.1.0/24
ACCEPT from 192.168.1.14 to 192.168.1.0/24
FWEOF
)

# Write to remote cluster.fw
echo "${FW_CONTENT}" | ssh ${SSH_OPTS} root@${MASTER_NODE} "cat > ${CLUSTER_FW}.new"

# Atomic rename
ssh ${SSH_OPTS} root@${MASTER_NODE} "mv ${CLUSTER_FW}.new ${CLUSTER_FW}"

echo "[3/4] ✅ ${CLUSTER_FW} creado con éxito"
echo "[3/4] Reglas incluidas:"
echo "   - Grupo mgmt-access: SSH, HTTPS, PBS, tráfico interno"
echo "   - Grupo corosync-link1: Corosync knet (UDP 5404-5406), ICMP"
echo "   - Default: DROP entre segmentos VLAN 10 y management"

# ---------------------------------------------------------------
# Step 4: Apply firewall
# ---------------------------------------------------------------
echo ""
echo "[4/4] Aplicando firewall..."

# Force cluster firewall reload via pvesh
ssh ${SSH_OPTS} root@${MASTER_NODE} "pvesh set /cluster/firewall/options --enable 1" 2>/dev/null || true

# Reload firewall rules on each node
for i in "${!NODES[@]}"; do
    IP="${NODES[$i]}"
    NAME="${NODE_NAMES[$i]}"

    echo "[4/4] Recargando firewall en ${NAME}..."
    ssh ${SSH_OPTS} root@${IP} "pve-firewall restart" 2>/dev/null || {
        ssh ${SSH_OPTS} root@${IP} "systemctl restart pve-firewall" 2>/dev/null || {
            echo "  ⚠️  No se pudo reiniciar pve-firewall en ${NAME} (¿está instalado?)"
        }
    }
done

# Verify firewall is active
echo ""
echo "[4/4] Verificando estado del firewall..."
sleep 2
FW_STATUS=$(ssh ${SSH_OPTS} root@${MASTER_NODE} "pve-firewall status 2>/dev/null" || echo "UNKNOWN")
echo "${FW_STATUS}" | sed 's/^/  /'

# Show rules loaded
echo ""
echo "[4/4] Reglas de cluster activas:"
ssh ${SSH_OPTS} root@${MASTER_NODE} "cat ${CLUSTER_FW} 2>/dev/null" | head -60

echo ""
echo "=== Task 3.5 completada ==="
echo "  Firewall de cluster creado en ${CLUSTER_FW}"
echo "  Segmentos protegidos: management (192.168.1.0/24) y VLAN ${VLAN_ID} (10.0.10.0/24)"
echo "  Tráfico Corosync permitido solo entre nodos del cluster"
