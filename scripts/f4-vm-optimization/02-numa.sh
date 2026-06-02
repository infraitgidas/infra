#!/bin/bash
# ================================================================
# 02-numa.sh — Task 4.2: Enable NUMA for VMs >4 vCPUs
# ================================================================
# Enables NUMA (Non-Uniform Memory Access) on VMs with more than
# NUMA_VCPU_THRESHOLD vCPUs. NUMA improves memory bandwidth on
# multi-socket hosts by allowing the guest OS to optimize memory
# access patterns.
#
# DESIGN: Threshold is >4 vCPUs (configurable via 00-env.sh).
# VMs with 4 or fewer vCPUs typically don't benefit from NUMA.
#
# NOTE: NUMA requires the VM to have a topology-aware guest OS.
# Linux and modern Windows Server (2012+) support NUMA.
# ================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-env.sh"

echo "=== Task 4.2: Habilitar NUMA en VMs con >${NUMA_VCPU_THRESHOLD} vCPUs ==="
echo ""

CHANGED=0
SKIPPED=0
FAILED=0

# ---------------------------------------------------------------
# Step 1: Query VM configs and enable NUMA where applicable
# ---------------------------------------------------------------
echo "[1/2] Analizando VMs..."

for VM_ENTRY in "${VMS[@]}"; do
    IFS='|' read -r VMID VMNAME OSTYPE NODE_IDX RUNNING <<< "${VM_ENTRY}"

    # Check if VM exists
    VM_EXISTS=$(ssh ${SSH_OPTS} root@${DEFAULT_NODE} "qm config ${VMID} &>/dev/null; echo \$?" 2>/dev/null || echo 1)
    if [ "${VM_EXISTS}" -ne 0 ]; then
        echo "[1/2] ⚠️  VM ${VMID} (${VMNAME}): no encontrada — saltando"
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    # Get current config
    VM_CONFIG=$(ssh ${SSH_OPTS} root@${DEFAULT_NODE} "qm config ${VMID}" 2>/dev/null || echo "")

    # Extract vCPUs (sockets * cores) and memory
    SOCKETS=$(echo "${VM_CONFIG}" | grep '^sockets:' | awk '{print $2}' || echo "1")
    CORES=$(echo "${VM_CONFIG}" | grep '^cores:' | awk '{print $2}' || echo "1")
    VCPUS=$((SOCKETS * CORES))
    MEMORY_MB=$(echo "${VM_CONFIG}" | grep '^memory:' | awk '{print $2}' || echo "0")
    CURRENT_NUMA=$(echo "${VM_CONFIG}" | grep '^numa:' | awk '{print $2}' || echo "0")

    echo "[1/2] ℹ️  VM ${VMID} (${VMNAME}): ${VCPUS} vCPUs, ${MEMORY_MB} MB RAM, numa=${CURRENT_NUMA}"

    # Check threshold: > NUMA_VCPU_THRESHOLD vCPUs (spec says >4)
    if [ "${VCPUS}" -le "${NUMA_VCPU_THRESHOLD}" ]; then
        echo "[1/2] ⏭️  VM ${VMID} (${VMNAME}): ${VCPUS} vCPUs ≤ ${NUMA_VCPU_THRESHOLD} — no aplica NUMA"
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    # Also check RAM threshold: >16 GB RAM is another trigger per spec
    # Even with <=4 vCPUs, large memory VMs benefit from NUMA
    if [ "${VCPUS}" -le "${NUMA_VCPU_THRESHOLD}" ] && [ "${MEMORY_MB}" -le 16384 ]; then
        echo "[1/2] ⏭️  VM ${VMID} (${VMNAME}): bajo ambos umbrales (${VCPUS} vCPUs, ${MEMORY_MB} MB)"
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    # Skip if NUMA already enabled
    if [ "${CURRENT_NUMA}" = "1" ]; then
        echo "[1/2] ✅ VM ${VMID} (${VMNAME}): NUMA ya habilitado — omitiendo"
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    # Enable NUMA
    echo "[1/2] 🔧 VM ${VMID} (${VMNAME}): habilitando NUMA..."
    if ssh ${SSH_OPTS} root@${DEFAULT_NODE} "qm set ${VMID} --numa 1" 2>/dev/null; then
        echo "[1/2] ✅ VM ${VMID} (${VMNAME}): NUMA habilitado"
        CHANGED=$((CHANGED + 1))
        echo "  Rollback: qm set ${VMID} --numa 0"
    else
        echo "[1/2] ❌ VM ${VMID} (${VMNAME}): ERROR al habilitar NUMA"
        FAILED=$((FAILED + 1))
    fi
done

# ---------------------------------------------------------------
# Step 2: Summary
# ---------------------------------------------------------------
echo ""
echo "[2/2] Resumen de cambios:"
echo "  VMs modificadas:           ${CHANGED}"
echo "  VMs saltadas:              ${SKIPPED}"
echo "  VMs con error:             ${FAILED}"

if [ "${FAILED}" -gt 0 ]; then
    echo ""
    echo "⚠️  ${FAILED} VM(s) tuvieron errores — revisar arriba"
    exit 1
fi

echo ""
echo "=== Task 4.2 completada ==="
