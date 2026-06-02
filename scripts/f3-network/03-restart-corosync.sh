#!/bin/bash
# ================================================================
# 03-restart-corosync.sh — Task 3.3: Restart corosync per-node
# ================================================================
# Restarts corosync on each node one by one, waiting for cluster
# quorum to stabilize before moving to the next node.
#
# PREREQUISITE: Task 3.2 — corosync.conf updated with link1
# ================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-env.sh"

echo "=== Task 3.3: Reiniciar corosync nodo por nodo ==="
echo ""

# ---------------------------------------------------------------
# Step 1: Pre-flight check — verify cluster state
# ---------------------------------------------------------------
echo "[1/6] Verificando estado del cluster antes del reinicio..."

FIRST_NODE="${NODES[0]}"
FIRST_NAME="${NODE_NAMES[0]}"

# Get current cluster health
CLUSTER_INFO=$(ssh ${SSH_OPTS} root@${FIRST_NODE} "pvecm status 2>/dev/null" || echo "ERROR")
if [ "${CLUSTER_INFO}" = "ERROR" ]; then
    echo "❌ No se puede obtener estado del cluster desde ${FIRST_NAME}"
    exit 1
fi

echo "[1/6] Estado actual del cluster:"
echo "${CLUSTER_INFO}" | head -20
echo ""

# Count nodes
NODE_COUNT=$(echo "${CLUSTER_INFO}" | grep -c "Nodes:" 2>/dev/null || echo "${#NODES[@]}")
EXPECTED_QUORUM=$(( (${#NODES[@]} / 2) + 1 ))
echo "[1/6] Nodos esperados: ${#NODES[@]}, Quorum necesario: ${EXPECTED_QUORUM}"
echo ""

# ---------------------------------------------------------------
# Step 2: Verify corosync.conf has link1 configured
# ---------------------------------------------------------------
echo "[2/6] Verificando link1 en corosync.conf..."

LINK_COUNT=$(ssh ${SSH_OPTS} root@${FIRST_NODE} "grep -c 'linknumber' ${COROSYNC_CONF} 2>/dev/null || echo 0")
if [ "${LINK_COUNT}" -lt 2 ]; then
    echo "❌ Se requieren al menos 2 links configurados (actual: ${LINK_COUNT})"
    echo "   Ejecute primero 02-corosync-link1.sh"
    exit 1
fi
echo "[2/6] ✅ ${LINK_COUNT} links configurados"

# Check ring1_addr
RING1_COUNT=$(ssh ${SSH_OPTS} root@${FIRST_NODE} "grep -c 'ring1_addr' ${COROSYNC_CONF} 2>/dev/null || echo 0")
if [ "${RING1_COUNT}" -lt "${#NODES[@]}" ]; then
    echo "❌ Se requieren ${#NODES[@]} ring1_addr (actual: ${RING1_COUNT})"
    echo "   Ejecute primero 02-corosync-link1.sh"
    exit 1
fi
echo "[2/6] ✅ ${RING1_COUNT} ring1_addr configurados"

# ---------------------------------------------------------------
# Step 3: Check VLAN 10 connectivity between nodes
# ---------------------------------------------------------------
echo ""
echo "[3/6] Verificando conectividad VLAN 10 entre nodos..."

ALL_VLAN_OK=true
for i in "${!NODES[@]}"; do
    SRC_IP="${NODES[$i]}"
    SRC_NAME="${NODE_NAMES[$i]}"
    SRC_VLAN_IP="${VLAN_IPS[$i]%%/*}"

    # Check VLAN interface is UP
    VLAN_STATUS=$(ssh ${SSH_OPTS} root@${SRC_IP} "ip -br addr show ${VLAN_INTERFACE} 2>/dev/null | head -1" || echo "NOT_FOUND")
    if echo "${VLAN_STATUS}" | grep -qv "NOT_FOUND"; then
        echo "[3/6] ✅ ${SRC_NAME}: ${VLAN_INTERFACE} presente"
    else
        echo "[3/6] ❌ ${SRC_NAME}: ${VLAN_INTERFACE} NO encontrado"
        echo "   Ejecute primero 01-vlan.sh"
        ALL_VLAN_OK=false
    fi
done

if [ "${ALL_VLAN_OK}" = false ]; then
    exit 1
fi

# Ping each node's VLAN 10 IP from the first node
echo "[3/6] Probando reachabilidad VLAN 10 entre nodos..."
for i in "${!NODES[@]}"; do
    TARGET_NAME="${NODE_NAMES[$i]}"
    TARGET_VLAN_IP="${VLAN_IPS[$i]%%/*}"

    PING_OK=$(ssh ${SSH_OPTS} root@${FIRST_NODE} "ping -c 2 -W 2 ${TARGET_VLAN_IP} 2>/dev/null | grep -c '1 received\|2 received'" || echo 0)
    if [ "${PING_OK}" -gt 0 ]; then
        echo "[3/6] ✅ ${FIRST_NAME} → ${TARGET_NAME} (${TARGET_VLAN_IP}): OK"
    else
        echo "[3/6] ⚠️  ${FIRST_NAME} → ${TARGET_NAME} (${TARGET_VLAN_IP}): SIN RESPUESTA"
        echo "   Verifique que el switch tenga VLAN ${VLAN_ID} como tagged en todos los puertos"
    fi
done

# ---------------------------------------------------------------
# Step 4: Restart corosync node by node
# ---------------------------------------------------------------
echo ""
echo "[4/6] Reiniciando corosync nodo por nodo..."
echo "  ⚠️  Se reinicia UN nodo a la vez, esperando quorum entre cada uno"
echo ""

for i in "${!NODES[@]}"; do
    IP="${NODES[$i]}"
    NAME="${NODE_NAMES[$i]}"

    echo "--- Reiniciando corosync en ${NAME} (${IP}) ---"

    # Before restart, check current state
    BEFORE_STATE=$(ssh ${SSH_OPTS} root@${IP} "corosync-cfgtool -s 2>/dev/null | head -10" || echo "UNKNOWN")
    echo "  Estado antes:"
    echo "${BEFORE_STATE}" | sed 's/^/    /'

    # Restart corosync
    echo "  Ejecutando: systemctl restart corosync..."
    ssh ${SSH_OPTS} root@${IP} "systemctl restart corosync" 2>&1 || {
        echo "  ❌ Falló reinicio de corosync en ${NAME}"
        echo "  Revise: journalctl -u corosync -n 50"
        exit 1
    }

    # Wait for service to start
    sleep 3

    # Verify service is running
    COROSYNC_ACTIVE=$(ssh ${SSH_OPTS} root@${IP} "systemctl is-active corosync 2>/dev/null" || echo "unknown")
    if [ "${COROSYNC_ACTIVE}" != "active" ]; then
        echo "  ❌ corosync no está activo en ${NAME} después del reinicio"
        ssh ${SSH_OPTS} root@${IP} "journalctl -u corosync -n 30 --no-pager" 2>/dev/null || true
        exit 1
    fi
    echo "  ✅ ${NAME}: corosync activo"

    # Wait for quorum
    echo "  Esperando quorum (hasta 30s)..."
    QUORUM_OK=false
    for attempt in $(seq 1 15); do
        sleep 2
        QUORUM=$(ssh ${SSH_OPTS} root@${IP} "pvecm status 2>/dev/null | grep -c Quorate" || echo 0)
        if [ "${QUORUM}" -gt 0 ]; then
            QUORUM_OK=true
            echo "  ✅ ${NAME}: quorum estable después de $((attempt * 2))s"
            break
        fi
        echo -n "."
    done
    echo ""

    if [ "${QUORUM_OK}" = false ]; then
        echo "  ❌ ${NAME}: no se alcanzó quorum después de 30s"
        echo "  Estado:"
        ssh ${SSH_OPTS} root@${IP} "pvecm status 2>/dev/null" || true
        exit 1
    fi

    # Show link status
    sleep 2
    AFTER_STATE=$(ssh ${SSH_OPTS} root@${IP} "corosync-cfgtool -s 2>/dev/null" || echo "UNKNOWN")
    echo "  Estado después:"
    echo "${AFTER_STATE}" | sed 's/^/    /'
    echo ""

    echo "[4/6] ✅ ${NAME}: corosync reiniciado y quorum estable"
    echo ""
done

# ---------------------------------------------------------------
# Step 5: Verify all nodes show link1 UP
# ---------------------------------------------------------------
echo ""
echo "[5/6] Verificando link1 en todos los nodos..."

ALL_LINKS_OK=true
for i in "${!NODES[@]}"; do
    IP="${NODES[$i]}"
    NAME="${NODE_NAMES[$i]}"

    echo "--- ${NAME} ---"
    LINK_STATUS=$(ssh ${SSH_OPTS} root@${IP} "corosync-cfgtool -s 2>/dev/null" || echo "ERROR")

    if [ "${LINK_STATUS}" = "ERROR" ]; then
        echo "  ❌ No se puede obtener estado de corosync en ${NAME}"
        ALL_LINKS_OK=false
        continue
    fi

    echo "${LINK_STATUS}" | sed 's/^/  /'

    # Count links that show "status: UP" or similar
    LINK_UP_COUNT=$(echo "${LINK_STATUS}" | grep -c -i "UP\|ESTABLISHED\|connected" 2>/dev/null || echo 0)
    if [ "${LINK_UP_COUNT}" -ge 2 ]; then
        echo "  ✅ ${NAME}: ${LINK_UP_COUNT} links UP"
    else
        echo "  ⚠️  ${NAME}: solo ${LINK_UP_COUNT} link(s) UP (se esperan 2)"
        ALL_LINKS_OK=false
    fi
    echo ""
done

# ---------------------------------------------------------------
# Step 6: Summary
# ---------------------------------------------------------------
echo ""
echo "[6/6] Resumen final del cluster..."

ssh ${SSH_OPTS} root@${FIRST_NODE} "pvecm status 2>/dev/null" | head -20

echo ""
echo "=== Task 3.3 completada ==="
if [ "${ALL_LINKS_OK}" = true ]; then
    echo "  ✅ Corosync reiniciado en todos los nodos — link1 redundante operativo"
else
    echo "  ⚠️  Algunos nodos no muestran link1 UP — revise configuración y conectividad"
fi
echo ""
echo "Link0: vmbr0 (192.168.1.0/24) — datos"
echo "Link1: ${VLAN_INTERFACE} (${LINK1_BIND}) — heartbeat"
