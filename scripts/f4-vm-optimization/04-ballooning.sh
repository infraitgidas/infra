#!/bin/bash
# ================================================================
# 04-ballooning.sh — Task 4.4: Review ballooning min >1 GB
# ================================================================
# Reviews memory ballooning configuration on all VMs and ensures
# the balloon minimum is ≥ BALLOON_MIN_MB (1024 MB / 1 GB).
#
# Ballooning allows dynamic memory reclamation between VMs, but
# setting the minimum too low can cause guest OS swapping and
# performance degradation. The design mandates a floor of 1 GB.
#
# DESIGN: VMs with ballooning enabled must have --balloon set to
# at least 1024 MB. VMs without ballooning are left untouched.
# ================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-env.sh"

echo "=== Task 4.4: Revisar ballooning mínimo (>${BALLOON_MIN_MB} MB) ==="
echo ""

CHANGED=0
OK=0
SKIPPED=0
FAILED=0

# ---------------------------------------------------------------
# Step 1: Review ballooning on all VMs
# ---------------------------------------------------------------
echo "[1/3] Revisando configuración de ballooning..."
echo ""

for VM_ENTRY in "${VMS[@]}"; do
    IFS='|' read -r VMID VMNAME OSTYPE NODE_IDX RUNNING <<< "${VM_ENTRY}"

    # Check if VM exists
    VM_EXISTS=$(ssh ${SSH_OPTS} root@${DEFAULT_NODE} "qm config ${VMID} &>/dev/null; echo \$?" 2>/dev/null || echo 1)
    if [ "${VM_EXISTS}" -ne 0 ]; then
        echo "[1/3] ⚠️  VM ${VMID} (${VMNAME}): no encontrada — saltando"
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    VM_CONFIG=$(ssh ${SSH_OPTS} root@${DEFAULT_NODE} "qm config ${VMID}" 2>/dev/null || echo "")

    # Extract memory and balloon values
    MEMORY_MB=$(echo "${VM_CONFIG}" | grep '^memory:' | awk '{print $2}' || echo "0")
    BALLOON=$(echo "${VM_CONFIG}" | grep '^balloon:' | awk '{print $2}' || echo "")
    SHARE=$(echo "${VM_CONFIG}" | grep '^shares:' | awk '{print $2}' || echo "")

    echo "[1/3] ℹ️  VM ${VMID} (${VMNAME}): memory=${MEMORY_MB} MB, balloon=${BALLOON:-none}, shares=${SHARE:-default}"

    # Check if ballooning is configured
    if [ -z "${BALLOON}" ]; then
        echo "[1/3] ⏭️  VM ${VMID} (${VMNAME}): ballooning no configurado — sin acción"
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    # Balloon value exists — check if it meets the minimum
    if [ "${BALLOON}" -ge "${BALLOON_MIN_MB}" ]; then
        echo "[1/3] ✅ VM ${VMID} (${VMNAME}): balloon=${BALLOON} MB ≥ ${BALLOON_MIN_MB} MB — OK"
        OK=$((OK + 1))
        continue
    fi

    # Balloon is below minimum — fix it
    echo "[1/3] ⚠️  VM ${VMID} (${VMNAME}): balloon=${BALLOON} MB < ${BALLOON_MIN_MB} MB — corrigiendo..."

    # Set balloon to minimum (or memory, whichever is smaller)
    NEW_BALLOON=$(( MEMORY_MB < BALLOON_MIN_MB ? MEMORY_MB : BALLOON_MIN_MB ))
    echo "[1/3] 🔧 VM ${VMID} (${VMNAME}): estableciendo balloon=${NEW_BALLOON} MB..."

    if ssh ${SSH_OPTS} root@${DEFAULT_NODE} "qm set ${VMID} --balloon ${NEW_BALLOON}" 2>/dev/null; then
        echo "[1/3] ✅ VM ${VMID} (${VMNAME}): balloon actualizado a ${NEW_BALLOON} MB"
        CHANGED=$((CHANGED + 1))
        echo "  Rollback: qm set ${VMID} --balloon ${BALLOON}"
    else
        echo "[1/3] ❌ VM ${VMID} (${VMNAME}): ERROR al actualizar balloon"
        FAILED=$((FAILED + 1))
    fi
done

# ---------------------------------------------------------------
# Step 2: Summary
# ---------------------------------------------------------------
echo ""
echo "[2/3] Resumen de cambios:"
echo "  VMs con balloon OK:        ${OK}"
echo "  VMs modificadas:           ${CHANGED}"
echo "  VMs sin balloon/saltadas:  ${SKIPPED}"
echo "  VMs con error:             ${FAILED}"

if [ "${FAILED}" -gt 0 ]; then
    echo ""
    echo "⚠️  ${FAILED} VM(s) tuvieron errores — revisar arriba"
    exit 1
fi

# ---------------------------------------------------------------
# Step 3: Quick verification
# ---------------------------------------------------------------
echo ""
echo "[3/3] Verificación..."

VERIFY_FAIL=0
for VM_ENTRY in "${VMS[@]}"; do
    IFS='|' read -r VMID VMNAME OSTYPE NODE_IDX RUNNING <<< "${VM_ENTRY}"

    VM_EXISTS=$(ssh ${SSH_OPTS} root@${DEFAULT_NODE} "qm config ${VMID} &>/dev/null; echo \$?" 2>/dev/null || echo 1)
    [ "${VM_EXISTS}" -ne 0 ] && continue

    FINAL_BALLOON=$(ssh ${SSH_OPTS} root@${DEFAULT_NODE} "qm config ${VMID} 2>/dev/null | grep '^balloon:' | awk '{print \$2}'" || echo "")

    if [ -n "${FINAL_BALLOON}" ]; then
        if [ "${FINAL_BALLOON}" -ge "${BALLOON_MIN_MB}" ]; then
            echo "[3/3] ✅ VM ${VMID} (${VMNAME}): balloon=${FINAL_BALLOON} MB ≥ ${BALLOON_MIN_MB} MB"
        else
            echo "[3/3] ❌ VM ${VMID} (${VMNAME}): balloon=${FINAL_BALLOON} MB < ${BALLOON_MIN_MB} MB"
            VERIFY_FAIL=$((VERIFY_FAIL + 1))
        fi
    fi
done

if [ "${VERIFY_FAIL}" -gt 0 ]; then
    echo ""
    echo "⚠️  ${VERIFY_FAIL} VM(s) aún por debajo del mínimo — revisar manualmente"
fi

echo ""
echo "=== Task 4.4 completada ==="
