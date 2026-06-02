#!/bin/bash
# ================================================================
# 01-vlan.sh — Task 3.1: Add VLAN 10 on vmbr0 (each node)
# ================================================================
# Creates a tagged VLAN interface (vmbr0.10) on top of the existing
# vmbr0 bridge on every cluster node. This VLAN carries Corosync
# heartbeat traffic (link1) isolated from data traffic.
#
# PREREQUISITE: Switch port must be in trunk mode with VLAN 10 tagged.
# ================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-env.sh"

echo "=== Task 3.1: Agregar VLAN ${VLAN_ID} (${VLAN_INTERFACE}) en cada nodo ==="
echo ""

# ---------------------------------------------------------------
# Step 1: Verify prerequisites
# ---------------------------------------------------------------
echo "[1/4] Verificando prerequisitos..."

for i in "${!NODES[@]}"; do
    IP="${NODES[$i]}"
    NAME="${NODE_NAMES[$i]}"

    # Check connectivity
    if ! ssh ${SSH_OPTS} root@${IP} "hostname" &>/dev/null; then
        echo "❌ ${NAME} (${IP}) no responde"
        exit 1
    fi
    echo "[1/4] ✅ ${NAME}: conectividad OK"

    # Check current vmbr0 exists
    VMBR0_EXISTS=$(ssh ${SSH_OPTS} root@${IP} "grep -c '^iface vmbr0' /etc/network/interfaces 2>/dev/null || echo 0")
    if [ "${VMBR0_EXISTS}" -eq 0 ]; then
        echo "❌ ${NAME}: vmbr0 no encontrado en /etc/network/interfaces"
        exit 1
    fi
    echo "[1/4] ✅ ${NAME}: vmbr0 encontrado"

    # Check VLAN subinterface does NOT already exist
    VLAN_EXISTS=$(ssh ${SSH_OPTS} root@${IP} "grep -c '^iface ${VLAN_INTERFACE}' /etc/network/interfaces 2>/dev/null || echo 0")
    if [ "${VLAN_EXISTS}" -gt 0 ]; then
        echo "[1/4] ⚠️  ${NAME}: ${VLAN_INTERFACE} ya existe — se omitirá"
    else
        echo "[1/4] ✅ ${NAME}: ${VLAN_INTERFACE} no existe (procediendo)"
    fi
done

# ---------------------------------------------------------------
# Step 2: Backup interfaces
# ---------------------------------------------------------------
echo ""
echo "[2/4] Respaldando /etc/network/interfaces en cada nodo..."

BACKUP_SUFFIX=".backup.$(date +%Y%m%d_%H%M%S)"
for i in "${!NODES[@]}"; do
    IP="${NODES[$i]}"
    NAME="${NODE_NAMES[$i]}"

    ssh ${SSH_OPTS} root@${IP} "cp /etc/network/interfaces /etc/network/interfaces${BACKUP_SUFFIX}" 2>/dev/null
    echo "[2/4] ✅ ${NAME}: respaldo creado (interfaces${BACKUP_SUFFIX})"
done

# ---------------------------------------------------------------
# Step 3: Add VLAN interface to each node
# ---------------------------------------------------------------
echo ""
echo "[3/4] Agregando interfaz ${VLAN_INTERFACE} a cada nodo..."

VLAN_IP="${VLAN_IPS[$i]}"

for i in "${!NODES[@]}"; do
    IP="${NODES[$i]}"
    NAME="${NODE_NAMES[$i]}"
    VLAN_IP="${VLAN_IPS[$i]}"

    # Check if already exists — skip if so
    VLAN_EXISTS=$(ssh ${SSH_OPTS} root@${IP} "grep -c '^iface ${VLAN_INTERFACE}' /etc/network/interfaces 2>/dev/null || echo 0")
    if [ "${VLAN_EXISTS}" -gt 0 ]; then
        echo "[3/4] ⚠️  ${NAME}: ${VLAN_INTERFACE} ya configurado — omitiendo"
        continue
    fi

    echo "[3/4] Configurando ${VLAN_INTERFACE} en ${NAME} (IP: ${VLAN_IP})..."

    # Append VLAN interface config BELOW the existing vmbr0 block
    # We need to find the end of the vmbr0 stanza and insert after it.
    # Uses sed to find the vmbr0 stanza and append the VLAN interface after its closing.
    ssh ${SSH_OPTS} root@${IP} bash -s -- "${VLAN_INTERFACE}" "${VLAN_IP}" << 'REMOTE'
        set -euo pipefail
        IFACE="$1"
        IPADDR="$2"

        # Find line number where vmbr0 stanza ENDS (next auto/iface or EOF)
        START_LINE=$(grep -n "^iface vmbr0" /etc/network/interfaces | head -1 | cut -d: -f1)
        if [ -z "${START_LINE}" ]; then
            echo "❌ No se encontró iface vmbr0"
            exit 1
        fi

        # Find the end of the vmbr0 stanza (next ^auto or ^iface or EOF)
        tail -n +$((START_LINE + 1)) /etc/network/interfaces | grep -n "^auto\|^iface\|^$" | head -1 | read -r BLANK_LINE
        # Alternative: find next line that starts with "auto " or "iface " after vmbr0
        END_LINE=$(awk 'NR>='"${START_LINE}"' && !/^#/ && /^(auto |iface )/{if(NR>='"${START_LINE}"') print NR}' /etc/network/interfaces | head -2 | tail -1)
        if [ -z "${END_LINE}" ]; then
            # No more interfaces after vmbr0 — append at end
            END_LINE=$(wc -l < /etc/network/interfaces)
            END_LINE=$((END_LINE + 1))
        else
            END_LINE=$((END_LINE - 1))
        fi

        # Insert VLAN interface after vmbr0 block
        sed -i "${END_LINE}a\\
\\
auto ${IFACE}\\
iface ${IFACE} inet static\\
    address ${IPADDR}\\
    # VLAN ${VLAN_ID} — Corosync heartbeat (link1)\\
" /etc/network/interfaces

        echo "✅ ${IFACE} agregado con IP ${IPADDR}"
REMOTE

    echo "[3/4] ✅ ${NAME}: ${VLAN_INTERFACE} configurado"
done

# ---------------------------------------------------------------
# Step 4: Apply VLAN interface (activate without reboot)
# ---------------------------------------------------------------
echo ""
echo "[4/4] Activando interfaz ${VLAN_INTERFACE} en cada nodo..."

for i in "${!NODES[@]}"; do
    IP="${NODES[$i]}"
    NAME="${NODE_NAMES[$i]}"
    VLAN_IP="${VLAN_IPS[$i]}"

    # Extract IP without CIDR for ping check
    IP_CIDR="${VLAN_IP%%/*}"
    VLAN_NETMASK="${VLAN_IP#*/}"

    echo "[4/4] Activando ${VLAN_INTERFACE} en ${NAME}..."

    # Bring up the VLAN interface (won't affect vmbr0 or running VMs)
    ssh ${SSH_OPTS} root@${IP} "ip link add link vmbr0 name ${VLAN_INTERFACE} type vlan id ${VLAN_ID} 2>/dev/null || true" 2>/dev/null || true
    ssh ${SSH_OPTS} root@${IP} "ip addr add ${VLAN_IP} dev ${VLAN_INTERFACE} 2>/dev/null || true" 2>/dev/null || true
    ssh ${SSH_OPTS} root@${IP} "ip link set ${VLAN_INTERFACE} up" 2>/dev/null

    # Verify
    sleep 1
    LINK_OK=$(ssh ${SSH_OPTS} root@${IP} "ip -br addr show ${VLAN_INTERFACE} 2>/dev/null | grep -c UP" || echo 0)
    if [ "${LINK_OK}" -gt 0 ]; then
        echo "[4/4] ✅ ${NAME}: ${VLAN_INTERFACE} UP with IP ${VLAN_IP}"
    else
        echo "[4/4] ⚠️  ${NAME}: ${VLAN_INTERFACE} no está UP — verificar conectividad física y switch"
    fi
done

echo ""
echo "=== Task 3.1 completada ==="
echo "  VLAN ${VLAN_ID} (${VLAN_INTERFACE}) configurada en todos los nodos"
echo "  Rango IP: ${VLAN_SUBNET}"
echo "  Backups: interfaces.backup.$(date +%Y%m%d)* en cada nodo"
echo ""
echo "⚠️  IMPORTANTE: Verifique que el switch tenga VLAN ${VLAN_ID} como tagged"
echo "   en los puertos de todos los nodos antes de continuar."
