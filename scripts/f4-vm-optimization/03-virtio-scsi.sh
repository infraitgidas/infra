#!/bin/bash
# ================================================================
# 03-virtio-scsi.sh — Task 4.3: Configure VirtIO SCSI Single + iothread
# ================================================================
# Sets the SCSI controller to VirtIO SCSI Single with iothread=1
# for improved I/O performance on all VMs with SCSI disks.
#
# VirtIO SCSI Single provides a dedicated vCPU queue per disk,
# reducing lock contention. IO Thread offloads disk I/O to a
# dedicated thread, reducing host CPU steal.
#
# DESIGN: Cache mode is set to 'none' for data integrity over
# writethrough/writeback (see design.md F4 decisions).
# ================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-env.sh"

echo "=== Task 4.3: Configurar VirtIO SCSI Single + iothread=1 ==="
echo ""

CHANGED=0
SKIPPED=0
FAILED=0

# ---------------------------------------------------------------
# Step 1: Set VirtIO SCSI Single controller on all VMs
# ---------------------------------------------------------------
echo "[1/3] Configurando controladora SCSI VirtIO SCSI Single..."
echo "  (Target: scsihw=virtio-scsi-single, iothread=1)"
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

    # Check current scsihw
    CURRENT_SCSIHW=$(echo "${VM_CONFIG}" | grep '^scsihw:' | awk '{print $2}' || echo "lsi")
    CURRENT_IOTHREAD=$(echo "${VM_CONFIG}" | grep '^iothread:' | awk '{print $2}' || echo "0")

    echo "[1/3] ℹ️  VM ${VMID} (${VMNAME}): scsihw=${CURRENT_SCSIHW}, iothread=${CURRENT_IOTHREAD}"

    # Skip if already virtio-scsi-single with iothread=1
    if [ "${CURRENT_SCSIHW}" = "virtio-scsi-single" ] && [ "${CURRENT_IOTHREAD}" = "1" ]; then
        echo "[1/3] ✅ VM ${VMID} (${VMNAME}): ya configurado — omitiendo"
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    # Check if VM has SCSI disks
    HAS_SCSI=$(echo "${VM_CONFIG}" | grep -cP '^scsi[0-9]+:' 2>/dev/null || echo 0)

    # Apply SCSI controller change
    echo "[1/3] 🔧 VM ${VMID} (${VMNAME}): estableciendo scsihw=virtio-scsi-single..."

    # Build set args
    SET_ARGS="--scsihw virtio-scsi-single"

    # Only set iothread if scsihw changes (iothread requires scsihw=virtio-scsi-single)
    if [ "${CURRENT_SCSIHW}" != "virtio-scsi-single" ]; then
        SET_ARGS="${SET_ARGS} --iothread 1"
    elif [ "${CURRENT_IOTHREAD}" != "1" ]; then
        SET_ARGS="${SET_ARGS} --iothread 1"
    fi

    # Also set cache=none on SCSI disks (writeback integrity fix)
    if [ "${HAS_SCSI}" -gt 0 ]; then
        echo "[1/3] ℹ️  VM ${VMID}: revisando cache en discos SCSI..."
        for DISK_LINE in $(echo "${VM_CONFIG}" | grep -oP '^scsi[0-9]+:.*'); do
            DISK_ID=$(echo "${DISK_LINE}" | cut -d: -f1)
            CURRENT_CACHE=$(echo "${DISK_LINE}" | grep -oP 'cache=[^,]+' | cut -d= -f2 || echo "")
            if [ -n "${CURRENT_CACHE}" ] && [ "${CURRENT_CACHE}" != "${DISK_CACHE_MODE}" ]; then
                echo "  ↳ ${DISK_ID}: cache=${CURRENT_CACHE} → ${DISK_CACHE_MODE}"
                SET_ARGS="${SET_ARGS} --${DISK_ID} cache=${DISK_CACHE_MODE}"
            fi
        done
    fi

    if ssh ${SSH_OPTS} root@${DEFAULT_NODE} "qm set ${VMID} ${SET_ARGS}" 2>/dev/null; then
        echo "[1/3] ✅ VM ${VMID} (${VMNAME}): configurado"
        CHANGED=$((CHANGED + 1))
        echo "  Rollback: qm set ${VMID} --scsihw ${CURRENT_SCSIHW} --iothread ${CURRENT_IOTHREAD}"
    else
        echo "[1/3] ❌ VM ${VMID} (${VMNAME}): ERROR"
        FAILED=$((FAILED + 1))
    fi
done

# ---------------------------------------------------------------
# Step 2: Summary
# ---------------------------------------------------------------
echo ""
echo "[2/3] Resumen de cambios VirtIO SCSI:"
echo "  VMs modificadas:           ${CHANGED}"
echo "  VMs saltadas:              ${SKIPPED}"
echo "  VMs con error:             ${FAILED}"

if [ "${FAILED}" -gt 0 ]; then
    echo ""
    echo "⚠️  ${FAILED} VM(s) tuvieron errores — revisar arriba"
    exit 1
fi

# ---------------------------------------------------------------
# Step 3: Verify final config
# ---------------------------------------------------------------
echo ""
echo "[3/3] Verificación rápida..."

VERIFY_FAIL=0
for VM_ENTRY in "${VMS[@]}"; do
    IFS='|' read -r VMID VMNAME OSTYPE NODE_IDX RUNNING <<< "${VM_ENTRY}"

    VM_EXISTS=$(ssh ${SSH_OPTS} root@${DEFAULT_NODE} "qm config ${VMID} &>/dev/null; echo \$?" 2>/dev/null || echo 1)
    [ "${VM_EXISTS}" -ne 0 ] && continue

    FINAL_SCSIHW=$(ssh ${SSH_OPTS} root@${DEFAULT_NODE} "qm config ${VMID} 2>/dev/null | grep '^scsihw:' | awk '{print \$2}'" || echo "")
    FINAL_IOTHREAD=$(ssh ${SSH_OPTS} root@${DEFAULT_NODE} "qm config ${VMID} 2>/dev/null | grep '^iothread:' | awk '{print \$2}'" || echo "")

    if [ "${FINAL_SCSIHW}" = "virtio-scsi-single" ] && [ "${FINAL_IOTHREAD}" = "1" ]; then
        echo "[3/3] ✅ VM ${VMID} (${VMNAME}): scsihw=${FINAL_SCSIHW}, iothread=${FINAL_IOTHREAD}"
    elif [ "${FINAL_SCSIHW}" = "virtio-scsi-single" ]; then
        echo "[3/3] ⚠️  VM ${VMID} (${VMNAME}): scsihw=${FINAL_SCSIHW}, iothread=${FINAL_IOTHREAD:-0} (sin iothread)"
        VERIFY_FAIL=$((VERIFY_FAIL + 1))
    else
        echo "[3/3] ⚠️  VM ${VMID} (${VMNAME}): scsihw=${FINAL_SCSIHW} (no es virtio-scsi-single)"
        VERIFY_FAIL=$((VERIFY_FAIL + 1))
    fi
done

if [ "${VERIFY_FAIL}" -gt 0 ]; then
    echo ""
    echo "⚠️  ${VERIFY_FAIL} VM(s) no cumplen con VirtIO SCSI Single — revisar manualmente"
fi

echo ""
echo "=== Task 4.3 completada ==="
