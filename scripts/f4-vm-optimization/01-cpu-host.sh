#!/bin/bash
# ================================================================
# 01-cpu-host.sh — Task 4.1: Set CPU type to 'host' for Linux VMs
# ================================================================
# Changes the CPU emulation type from the default (kvm64/kvm32) to
# 'host' for all Linux VMs, exposing all host CPU instruction sets.
# Not applied to Windows VMs to avoid instability.
#
# DESIGN: Cross-node migration is not needed (no shared storage),
# so CPU type 'host' is safe. Rollback: qm set <vmid> --cpu kvm64.
# ================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-env.sh"

echo "=== Task 4.1: Configurar CPU type 'host' en VMs Linux ==="
echo ""

CHANGED=0
SKIPPED=0
FAILED=0

# ---------------------------------------------------------------
# Step 1: Identify Linux VMs and set CPU to host
# ---------------------------------------------------------------
echo "[1/2] Procesando VMs Linux..."

for VM_ENTRY in "${VMS[@]}"; do
    IFS='|' read -r VMID VMNAME OSTYPE NODE_IDX RUNNING <<< "${VM_ENTRY}"

    # Only Linux VMs get CPU host
    if [ "${OSTYPE}" != "linux" ]; then
        echo "[1/2] ⏭️  VM ${VMID} (${VMNAME}): OS=${OSTYPE} — saltando (solo Linux)"
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    # Check if VM exists
    VM_EXISTS=$(ssh ${SSH_OPTS} root@${DEFAULT_NODE} "qm config ${VMID} &>/dev/null; echo \$?" 2>/dev/null || echo 1)
    if [ "${VM_EXISTS}" -ne 0 ]; then
        echo "[1/2] ⚠️  VM ${VMID} (${VMNAME}): no encontrada — saltando"
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    # Get current CPU type
    CURRENT_CPU=$(ssh ${SSH_OPTS} root@${DEFAULT_NODE} "qm config ${VMID} 2>/dev/null | grep '^cpu:' | awk '{print \$2}'" || echo "")
    echo "[1/2] ℹ️  VM ${VMID} (${VMNAME}): CPU actual = '${CURRENT_CPU:-default}'"

    # Skip if already 'host'
    if [ "${CURRENT_CPU}" = "host" ]; then
        echo "[1/2] ✅ VM ${VMID} (${VMNAME}): ya tiene cpu=host — omitiendo"
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    # Apply cpu=host
    echo "[1/2] 🔧 VM ${VMID} (${VMNAME}): estableciendo cpu=host..."
    if ssh ${SSH_OPTS} root@${DEFAULT_NODE} "qm set ${VMID} --cpu host" 2>/dev/null; then
        echo "[1/2] ✅ VM ${VMID} (${VMNAME}): cpu=host aplicado"
        CHANGED=$((CHANGED + 1))

        # Log rollback command
        echo "  Rollback: qm set ${VMID} --cpu ${CURRENT_CPU:-kvm64}"
    else
        echo "[1/2] ❌ VM ${VMID} (${VMNAME}): ERROR al aplicar cpu=host"
        FAILED=$((FAILED + 1))
    fi
done

# ---------------------------------------------------------------
# Step 2: Summary
# ---------------------------------------------------------------
echo ""
echo "[2/2] Resumen de cambios:"
echo "  VMs modificadas:           ${CHANGED}"
echo "  VMs saltadas (ya ok/no aplica): ${SKIPPED}"
echo "  VMs con error:             ${FAILED}"

# Show rollback commands
if [ "${CHANGED}" -gt 0 ]; then
    echo ""
    echo "Comandos de rollback (revertir CPU type):"
    for VM_ENTRY in "${VMS[@]}"; do
        IFS='|' read -r VMID VMNAME OSTYPE NODE_IDX RUNNING <<< "${VM_ENTRY}"
        if [ "${OSTYPE}" = "linux" ]; then
            echo "  qm set ${VMID} --cpu kvm64    # ${VMNAME}"
        fi
    done
fi

if [ "${FAILED}" -gt 0 ]; then
    echo ""
    echo "⚠️  ${FAILED} VM(s) tuvieron errores — revisar arriba"
    exit 1
fi

echo ""
echo "=== Task 4.1 completada ==="
