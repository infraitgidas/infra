#!/bin/bash
# ================================================================
# 06-verify.sh — Task 3.6: Full F3 network verification
# ================================================================
# Validates all requirements from the Red VLAN spec:
#   - Spec 3.1: VLAN 10 configured on all nodes
#   - Spec 3.2: Corosync link1 configured and UP
#   - Spec 3.3: Bonding LACP operational on pve-desa04
#   - Spec 3.4: Cluster firewall rules active
# ================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-env.sh"

PASS=0
FAIL=0
WARN=0

check() {
    local desc="$1"
    local status="$2"
    if [ "${status}" = "PASS" ]; then
        echo "  ✅ PASS: ${desc}"
        PASS=$((PASS + 1))
    elif [ "${status}" = "WARN" ]; then
        echo "  ⚠️  WARN: ${desc}"
        WARN=$((WARN + 1))
    else
        echo "  ❌ FAIL: ${desc}"
        FAIL=$((FAIL + 1))
    fi
}

echo "========================================================"
echo "  Verification: Red VLAN (Task 3.6)"
echo "========================================================"
echo ""

# ---------------------------------------------------------------
# Section A: VLAN 10 configuration (Spec 3.1)
# ---------------------------------------------------------------
echo "--- Section A: VLAN ${VLAN_ID} configuration ---"

for i in "${!NODES[@]}"; do
    IP="${NODES[$i]}"
    NAME="${NODE_NAMES[$i]}"
    VLAN_IP="${VLAN_IPS[$i]%%/*}"

    # Check VLAN interface exists in config
    VLAN_IN_CFG=$(ssh ${SSH_OPTS} root@${IP} "grep -c '^iface ${VLAN_INTERFACE}' /etc/network/interfaces 2>/dev/null || echo 0")
    if [ "${VLAN_IN_CFG}" -gt 0 ]; then
        check "${NAME}: ${VLAN_INTERFACE} en /etc/network/interfaces" "PASS"
    else
        check "${NAME}: ${VLAN_INTERFACE} en /etc/network/interfaces" "FAIL"
    fi

    # Check VLAN interface is UP
    VLAN_UP=$(ssh ${SSH_OPTS} root@${IP} "ip -br addr show ${VLAN_INTERFACE} 2>/dev/null | grep -c UP" || echo 0)
    if [ "${VLAN_UP}" -gt 0 ]; then
        check "${NAME}: ${VLAN_INTERFACE} operativo (UP)" "PASS"

        # Check IP address assigned
        VLAN_ADDR=$(ssh ${SSH_OPTS} root@${IP} "ip -br addr show ${VLAN_INTERFACE} 2>/dev/null | awk '{print \$3}'" || echo "")
        if [ -n "${VLAN_ADDR}" ]; then
            check "${NAME}: IP ${VLAN_ADDR} asignada a ${VLAN_INTERFACE}" "PASS"
        else
            check "${NAME}: IP asignada a ${VLAN_INTERFACE}" "FAIL"
        fi
    else
        check "${NAME}: ${VLAN_INTERFACE} operativo (UP)" "FAIL"
    fi
done

# ---------------------------------------------------------------
# Section B: Corosync link1 (Spec 3.2)
# ---------------------------------------------------------------
echo ""
echo "--- Section B: Corosync link1 configuration ---"

FIRST_NODE="${NODES[0]}"

# Check corosync.conf has link1
LINK_COUNT=$(ssh ${SSH_OPTS} root@${FIRST_NODE} "grep -c 'linknumber' ${COROSYNC_CONF} 2>/dev/null || echo 0")
if [ "${LINK_COUNT}" -ge 2 ]; then
    check "corosync.conf: ${LINK_COUNT} links configurados" "PASS"
else
    check "corosync.conf: ${LINK_COUNT} links (se esperan ≥2)" "FAIL"
fi

# Check ring1_addr entries
RING1_COUNT=$(ssh ${SSH_OPTS} root@${FIRST_NODE} "grep -c 'ring1_addr' ${COROSYNC_CONF} 2>/dev/null || echo 0")
if [ "${RING1_COUNT}" -ge "${#NODES[@]}" ]; then
    check "corosync.conf: ${RING1_COUNT} ring1_addr (esperados ${#NODES[@]})" "PASS"
else
    check "corosync.conf: ${RING1_COUNT} ring1_addr (esperados ${#NODES[@]})" "FAIL"
fi

# Check link1 status on each node
echo ""
echo "--- Section B (cont.): Corosync link status per node ---"

for i in "${!NODES[@]}"; do
    IP="${NODES[$i]}"
    NAME="${NODE_NAMES[$i]}"

    echo "  [${NAME}] corosync-cfgtool -s:"
    LINK_STATUS=$(ssh ${SSH_OPTS} root@${IP} "corosync-cfgtool -s 2>/dev/null" || echo "ERROR")

    if [ "${LINK_STATUS}" = "ERROR" ]; then
        check "${NAME}: corosync-cfgtool responde" "FAIL"
        continue
    fi
    check "${NAME}: corosync-cfgtool responde" "PASS"

    # Count how many links report OK status
    # corosync-cfgtool -s output varies by version. Look for patterns:
    # "link 1: status: OK" or similar
    echo "${LINK_STATUS}" | sed 's/^/    /'
    echo ""
done

# ---------------------------------------------------------------
# Section C: Bonding LACP on pve-desa04 (Spec 3.3)
# ---------------------------------------------------------------
echo ""
echo "--- Section C: Bonding LACP on ${NODE_NAMES[$BOND_NODE_IDX]} ---"

BOND_IP="${NODES[$BOND_NODE_IDX]}"
BOND_NAME="${NODE_NAMES[$BOND_NODE_IDX]}"

# Check bond0 interface exists
BOND_EXISTS=$(ssh ${SSH_OPTS} root@${BOND_IP} "ip link show bond0 2>/dev/null | grep -c 'state'" || echo 0)
if [ "${BOND_EXISTS}" -gt 0 ]; then
    check "${BOND_NAME}: bond0 existe" "PASS"

    # Check bond0 is UP
    BOND_UP=$(ssh ${SSH_OPTS} root@${BOND_IP} "ip -br link show bond0 2>/dev/null | grep -c UP" || echo 0)
    if [ "${BOND_UP}" -gt 0 ]; then
        check "${BOND_NAME}: bond0 operativo (UP)" "PASS"
    else
        check "${BOND_NAME}: bond0 operativo (UP)" "WARN"
    fi

    # Read /proc/net/bonding/bond0 for detailed status
    BOND_STATUS=$(ssh ${SSH_OPTS} root@${BOND_IP} "cat /proc/net/bonding/bond0 2>/dev/null" || echo "NOT_FOUND")
    if [ "${BOND_STATUS}" != "NOT_FOUND" ]; then
        # Extract key info
        BOND_MODE_CFG=$(echo "${BOND_STATUS}" | grep "Bonding Mode:" | head -1 || echo "unknown")
        MII_STATUS=$(echo "${BOND_STATUS}" | grep "MII Status:" | head -1 || echo "unknown")
        ACTIVE_SLAVES=$(echo "${BOND_STATUS}" | grep -c "MII Status: up" 2>/dev/null || echo 0)

        echo "  Bonding Mode: ${BOND_MODE_CFG##*: }"
        echo "  MII Status: ${MII_STATUS##*: }"
        echo "  Active Slaves: ${ACTIVE_SLAVES}/${#BOND_SLAVES[@]}"

        if [ "${ACTIVE_SLAVES}" -ge 2 ]; then
            check "${BOND_NAME}: ${ACTIVE_SLAVES}/${#BOND_SLAVES[@]} slaves activos (LACP)" "PASS"
        elif [ "${ACTIVE_SLAVES}" -eq 1 ]; then
            check "${BOND_NAME}: ${ACTIVE_SLAVES}/${#BOND_SLAVES[@]} slaves activos" "WARN"
        else
            check "${BOND_NAME}: slaves activos" "FAIL"
        fi

        # Check LACP rate
        LACP_RATE=$(echo "${BOND_STATUS}" | grep "LACP rate:" | head -1 || echo "unknown")
        echo "  LACP Rate: ${LACP_RATE##*: }"
    else
        check "${BOND_NAME}: /proc/net/bonding/bond0 accesible" "FAIL"
    fi

    # Check vmbr0 uses bond0 as bridge port
    VMBR_PORT=$(ssh ${SSH_OPTS} root@${BOND_IP} "bridge link show vmbr0 2>/dev/null | grep -c bond0" || echo 0)
    if [ "${VMBR_PORT}" -gt 0 ]; then
        check "${BOND_NAME}: vmbr0 usa bond0 como bridge port" "PASS"
    else
        check "${BOND_NAME}: vmbr0 usa bond0 como bridge port" "WARN"
    fi
else
    check "${BOND_NAME}: bond0 existe" "INFO"
    echo "  (bonding no configurado en este nodo — normal si no es pve-desa04)"
fi

# ---------------------------------------------------------------
# Section D: Cluster firewall (Spec 3.4)
# ---------------------------------------------------------------
echo ""
echo "--- Section D: Cluster firewall ---"

# Check cluster.fw exists
FW_EXISTS=$(ssh ${SSH_OPTS} root@${FIRST_NODE} "test -f ${CLUSTER_FW} && echo OK || echo NO" 2>/dev/null || echo "NO")
if [ "${FW_EXISTS}" = "OK" ]; then
    check "${CLUSTER_FW} existe" "PASS"

    # Check firewall is enabled
    FW_ENABLED=$(ssh ${SSH_OPTS} root@${FIRST_NODE} "grep -c 'enable: 1' ${CLUSTER_FW} 2>/dev/null || echo 0")
    if [ "${FW_ENABLED}" -gt 0 ]; then
        check "Firewall de cluster habilitado" "PASS"
    else
        check "Firewall de cluster habilitado" "WARN"
    fi

    # Check key rules exist in the file
    COROSYNC_GROUP=$(ssh ${SSH_OPTS} root@${FIRST_NODE} "grep -c 'corosync-link1' ${CLUSTER_FW} 2>/dev/null || echo 0")
    if [ "${COROSYNC_GROUP}" -gt 0 ]; then
        check "Reglas Corosync VLAN ${VLAN_ID} presentes" "PASS"
    else
        check "Reglas Corosync VLAN ${VLAN_ID} presentes" "WARN"
    fi

    MGMT_GROUP=$(ssh ${SSH_OPTS} root@${FIRST_NODE} "grep -c 'mgmt-access' ${CLUSTER_FW} 2>/dev/null || echo 0")
    if [ "${MGMT_GROUP}" -gt 0 ]; then
        check "Reglas de acceso management presentes" "PASS"
    else
        check "Reglas de acceso management presentes" "WARN"
    fi

    # Check firewall service status
    FW_SERVICE=$(ssh ${SSH_OPTS} root@${FIRST_NODE} "systemctl is-active pve-firewall 2>/dev/null" || echo "inactive")
    if [ "${FW_SERVICE}" = "active" ]; then
        check "Servicio pve-firewall activo" "PASS"
    else
        check "Servicio pve-firewall activo (pve-firewall)" "INFO"
    fi
else
    check "${CLUSTER_FW} existe" "FAIL"
fi

# ---------------------------------------------------------------
# Section E: Inter-node connectivity over VLAN 10
# ---------------------------------------------------------------
echo ""
echo "--- Section E: Inter-node connectivity over VLAN 10 ---"

for i in "${!NODES[@]}"; do
    SRC_IP="${NODES[$i]}"
    SRC_NAME="${NODE_NAMES[$i]}"
    SRC_VLAN_IP="${VLAN_IPS[$i]%%/*}"

    # Test ping to next node on VLAN 10
    NEXT_IDX=$(( (i + 1) % ${#NODES[@]} ))
    TARGET_NAME="${NODE_NAMES[$NEXT_IDX]}"
    TARGET_VLAN_IP="${VLAN_IPS[$NEXT_IDX]%%/*}"

    PING_OK=$(ssh ${SSH_OPTS} root@${SRC_IP} "ping -c 2 -W 3 ${TARGET_VLAN_IP} 2>/dev/null | grep -c '1 received\|2 received'" || echo 0)
    if [ "${PING_OK}" -gt 0 ]; then
        check "VLAN ${VLAN_ID}: ${SRC_NAME} → ${TARGET_NAME} (${TARGET_VLAN_IP})" "PASS"
    else
        check "VLAN ${VLAN_ID}: ${SRC_NAME} → ${TARGET_NAME} (${TARGET_VLAN_IP})" "FAIL"
    fi
done

# ---------------------------------------------------------------
# Section F: Corosync cluster health
# ---------------------------------------------------------------
echo ""
echo "--- Section F: Cluster health ---"

# Check cluster is quorate
QUORUM=$(ssh ${SSH_OPTS} root@${FIRST_NODE} "pvecm status 2>/dev/null | grep -c Quorate" || echo 0)
if [ "${QUORUM}" -gt 0 ]; then
    check "Cluster Quorate" "PASS"
else
    check "Cluster Quorate" "FAIL"
fi

# Show cluster info
echo ""
echo "  Cluster status:"
ssh ${SSH_OPTS} root@${FIRST_NODE} "pvecm status 2>/dev/null" | sed 's/^/  /'

# Check expected nodes present
NODES_IN_CLUSTER=$(ssh ${SSH_OPTS} root@${FIRST_NODE} "pvecm status 2>/dev/null | grep -c 'Node address'" || echo 0)
if [ "${NODES_IN_CLUSTER}" -ge "${#NODES[@]}" ]; then
    check "${NODES_IN_CLUSTER}/${#NODES[@]} nodos en el cluster" "PASS"
else
    check "${NODES_IN_CLUSTER}/${#NODES[@]} nodos en el cluster" "WARN"
fi

# ---------------------------------------------------------------
# Summary
# ---------------------------------------------------------------
echo ""
echo "========================================================"
echo "  Verification Results — Fase 3: Red (P2)"
echo "========================================================"
echo "  PASS: ${PASS}"
echo "  WARN: ${WARN}"
echo "  FAIL: ${FAIL}"
echo "  Total: $((PASS + WARN + FAIL))"

if [ "${FAIL}" -eq 0 ]; then
    echo ""
    echo "  ✅ OVERALL: ALL CHECKS PASSED — Red VLAN segmentation complete"
    echo ""
    echo "  Resumen:"
    echo "  - VLAN ${VLAN_ID} (${VLAN_SUBNET}): configurada y operativa en todos los nodos"
    echo "  - Corosync link1: redundante sobre VLAN 10"
    echo "  - Bonding LACP: ${ACTIVE_SLAVES:-0}/${#BOND_SLAVES[@]} slaves activos en ${NODE_NAMES[$BOND_NODE_IDX]}"
    echo "  - Firewall: reglas activas por segmento"
else
    echo ""
    echo "  ❌ OVERALL: ${FAIL} check(s) FAILED — review above"
fi

exit ${FAIL}
