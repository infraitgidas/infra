#!/bin/bash
# ================================================================
# 05-verify.sh — Task 4.5: Cross-check all VM configurations
# ================================================================
# Verifies every optimization requirement from Fase 4:
#   - Spec 4.1: CPU type 'host' for Linux VMs
#   - Spec 4.2: NUMA enabled for VMs >4 vCPUs
#   - Spec 4.3: VirtIO SCSI Single with iothread=1
#   - Spec 4.4: Balloon minimum >1 GB
#   - Spec 4.5: Disk cache mode = none
#
# Uses: qm config <vmid> | grep -E "cpu:|numa:|cache:"
# ================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-env.sh"

PASS=0
FAIL=0
WARN=0
INFO=0

check() {
    local desc="$1"
    local status="$2"
    if [ "${status}" = "PASS" ]; then
        echo "  ✅ PASS: ${desc}"
        PASS=$((PASS + 1))
    elif [ "${status}" = "WARN" ]; then
        echo "  ⚠️  WARN: ${desc}"
        WARN=$((WARN + 1))
    elif [ "${status}" = "INFO" ]; then
        echo "  ℹ️  INFO: ${desc}"
        INFO=$((INFO + 1))
    else
        echo "  ❌ FAIL: ${desc}"
        FAIL=$((FAIL + 1))
    fi
}

echo "========================================================"
echo "  Verification — Fase 4: Optimización VMs (P2)"
echo "========================================================"
echo ""

# ---------------------------------------------------------------
# Section A: VM config dump (qm config)
# ---------------------------------------------------------------
echo "--- Section A: VM config summary ---"
echo ""

for VM_ENTRY in "${VMS[@]}"; do
    IFS='|' read -r VMID VMNAME OSTYPE NODE_IDX RUNNING <<< "${VM_ENTRY}"

    VM_EXISTS=$(ssh ${SSH_OPTS} root@${DEFAULT_NODE} "qm config ${VMID} &>/dev/null; echo \$?" 2>/dev/null || echo 1)
    if [ "${VM_EXISTS}" -ne 0 ]; then
        check "VM ${VMID} (${VMNAME}): existe" "FAIL"
        continue
    fi
    check "VM ${VMID} (${VMNAME}): existe" "PASS"

    # Show filtered config (cpu:, numa:, cache:)
    echo ""
    echo "  Config VM ${VMID} (${VMNAME}):"
    ssh ${SSH_OPTS} root@${DEFAULT_NODE} "qm config ${VMID} 2>/dev/null | grep -E 'cpu:|numa:|cache:'" | sed 's/^/    /' || echo "    (no relevant fields found)"
    echo ""
done

# ---------------------------------------------------------------
# Section B: CPU type check (Spec 4.1)
# ---------------------------------------------------------------
echo "--- Section B: CPU type 'host' for Linux VMs (Task 4.1) ---"
echo ""

for VM_ENTRY in "${VMS[@]}"; do
    IFS='|' read -r VMID VMNAME OSTYPE NODE_IDX RUNNING <<< "${VM_ENTRY}"

    VM_EXISTS=$(ssh ${SSH_OPTS} root@${DEFAULT_NODE} "qm config ${VMID} &>/dev/null; echo \$?" 2>/dev/null || echo 1)
    [ "${VM_EXISTS}" -ne 0 ] && continue

    CPU_TYPE=$(ssh ${SSH_OPTS} root@${DEFAULT_NODE} "qm config ${VMID} 2>/dev/null | grep '^cpu:' | awk '{print \$2}'" || echo "")

    if [ "${OSTYPE}" = "linux" ]; then
        if [ "${CPU_TYPE}" = "host" ]; then
            check "VM ${VMID} (${VMNAME}): Linux, cpu=${CPU_TYPE}" "PASS"
        elif [ -z "${CPU_TYPE}" ]; then
            check "VM ${VMID} (${VMNAME}): Linux, cpu=default (kvm64)" "FAIL"
        else
            check "VM ${VMID} (${VMNAME}): Linux, cpu=${CPU_TYPE} (se esperaba host)" "FAIL"
        fi
    elif [ "${OSTYPE}" = "windows" ]; then
        check "VM ${VMID} (${VMNAME}): Windows, cpu=${CPU_TYPE:-default} (no se aplica host)" "INFO"
    fi
done

# ---------------------------------------------------------------
# Section C: NUMA check (Spec 4.2)
# ---------------------------------------------------------------
echo ""
echo "--- Section C: NUMA for VMs >${NUMA_VCPU_THRESHOLD} vCPUs (Task 4.2) ---"
echo ""

for VM_ENTRY in "${VMS[@]}"; do
    IFS='|' read -r VMID VMNAME OSTYPE NODE_IDX RUNNING <<< "${VM_ENTRY}"

    VM_EXISTS=$(ssh ${SSH_OPTS} root@${DEFAULT_NODE} "qm config ${VMID} &>/dev/null; echo \$?" 2>/dev/null || echo 1)
    [ "${VM_EXISTS}" -ne 0 ] && continue

    VM_CONFIG=$(ssh ${SSH_OPTS} root@${DEFAULT_NODE} "qm config ${VMID}" 2>/dev/null || echo "")
    SOCKETS=$(echo "${VM_CONFIG}" | grep '^sockets:' | awk '{print $2}' || echo "1")
    CORES=$(echo "${VM_CONFIG}" | grep '^cores:' | awk '{print $2}' || echo "1")
    VCPUS=$((SOCKETS * CORES))
    MEMORY_MB=$(echo "${VM_CONFIG}" | grep '^memory:' | awk '{print $2}' || echo "0")
    NUMA=$(echo "${VM_CONFIG}" | grep '^numa:' | awk '{print $2}' || echo "0")

    if [ "${VCPUS}" -gt "${NUMA_VCPU_THRESHOLD}" ] || [ "${MEMORY_MB}" -gt 16384 ]; then
        if [ "${NUMA}" = "1" ]; then
            check "VM ${VMID} (${VMNAME}): ${VCPUS} vCPUs, ${MEMORY_MB} MB, numa=${NUMA}" "PASS"
        else
            check "VM ${VMID} (${VMNAME}): ${VCPUS} vCPUs, ${MEMORY_MB} MB, numa=${NUMA}" "FAIL"
        fi
    else
        check "VM ${VMID} (${VMNAME}): ${VCPUS} vCPUs — bajo umbral NUMA" "INFO"
    fi
done

# ---------------------------------------------------------------
# Section D: VirtIO SCSI Single + iothread (Spec 4.3)
# ---------------------------------------------------------------
echo ""
echo "--- Section D: VirtIO SCSI Single + iothread=1 (Task 4.3) ---"
echo ""

for VM_ENTRY in "${VMS[@]}"; do
    IFS='|' read -r VMID VMNAME OSTYPE NODE_IDX RUNNING <<< "${VM_ENTRY}"

    VM_EXISTS=$(ssh ${SSH_OPTS} root@${DEFAULT_NODE} "qm config ${VMID} &>/dev/null; echo \$?" 2>/dev/null || echo 1)
    [ "${VM_EXISTS}" -ne 0 ] && continue

    VM_CONFIG=$(ssh ${SSH_OPTS} root@${DEFAULT_NODE} "qm config ${VMID}" 2>/dev/null || echo "")
    SCSIHW=$(echo "${VM_CONFIG}" | grep '^scsihw:' | awk '{print $2}' || echo "none")
    IOTHREAD=$(echo "${VM_CONFIG}" | grep '^iothread:' | awk '{print $2}' || echo "0")

    if [ "${SCSIHW}" = "virtio-scsi-single" ]; then
        if [ "${IOTHREAD}" = "1" ]; then
            check "VM ${VMID} (${VMNAME}): scsihw=${SCSIHW}, iothread=${IOTHREAD}" "PASS"
        else
            check "VM ${VMID} (${VMNAME}): scsihw=${SCSIHW}, iothread=${IOTHREAD}" "WARN"
        fi
    elif [ "${SCSIHW}" = "none" ] || [ "${SCSIHW}" = "lsi" ]; then
        check "VM ${VMID} (${VMNAME}): scsihw=${SCSIHW} (sin SCSI)" "INFO"
    else
        check "VM ${VMID} (${VMNAME}): scsihw=${SCSIHW}" "WARN"
    fi

    # Check disk cache mode
    for DISK_LINE in $(echo "${VM_CONFIG}" | grep -oP '^(scsi|virtio|ide|sata)[0-9]+:.*'); do
        DISK_ID=$(echo "${DISK_LINE}" | cut -d: -f1)
        DISK_CACHE=$(echo "${DISK_LINE}" | grep -oP 'cache=[^,]+' | cut -d= -f2 || echo "none")
        if [ "${DISK_CACHE}" != "${DISK_CACHE_MODE}" ] && [ "${DISK_CACHE}" != "none" ]; then
            check "VM ${VMID} (${VMNAME}): ${DISK_ID} cache=${DISK_CACHE} (se espera ${DISK_CACHE_MODE})" "WARN"
        fi
    done
done

# ---------------------------------------------------------------
# Section E: Ballooning min (Spec 4.4)
# ---------------------------------------------------------------
echo ""
echo "--- Section E: Balloon minimum >${BALLOON_MIN_MB} MB (Task 4.4) ---"
echo ""

for VM_ENTRY in "${VMS[@]}"; do
    IFS='|' read -r VMID VMNAME OSTYPE NODE_IDX RUNNING <<< "${VM_ENTRY}"

    VM_EXISTS=$(ssh ${SSH_OPTS} root@${DEFAULT_NODE} "qm config ${VMID} &>/dev/null; echo \$?" 2>/dev/null || echo 1)
    [ "${VM_EXISTS}" -ne 0 ] && continue

    VM_CONFIG=$(ssh ${SSH_OPTS} root@${DEFAULT_NODE} "qm config ${VMID}" 2>/dev/null || echo "")
    BALLOON=$(echo "${VM_CONFIG}" | grep '^balloon:' | awk '{print $2}' || echo "")
    MEMORY_MB=$(echo "${VM_CONFIG}" | grep '^memory:' | awk '{print $2}' || echo "0")

    if [ -n "${BALLOON}" ]; then
        if [ "${BALLOON}" -ge "${BALLOON_MIN_MB}" ]; then
            check "VM ${VMID} (${VMNAME}): balloon=${BALLOON} MB ≥ ${BALLOON_MIN_MB} MB" "PASS"
        elif [ "${BALLOON}" -eq "${MEMORY_MB}" ]; then
            check "VM ${VMID} (${VMNAME}): balloon=${BALLOON} MB = memory (sin dinámica)" "INFO"
        else
            check "VM ${VMID} (${VMNAME}): balloon=${BALLOON} MB < ${BALLOON_MIN_MB} MB" "FAIL"
        fi
    else
        check "VM ${VMID} (${VMNAME}): sin ballooning configurado" "INFO"
    fi
done

# ---------------------------------------------------------------
# Section F: grepqm — grep patterns from task description
# ---------------------------------------------------------------
echo ""
echo "--- Section F: qm config | grep -E \"cpu:|numa:|cache:\" ---"
echo ""

for VM_ENTRY in "${VMS[@]}"; do
    IFS='|' read -r VMID VMNAME OSTYPE NODE_IDX RUNNING <<< "${VM_ENTRY}"

    VM_EXISTS=$(ssh ${SSH_OPTS} root@${DEFAULT_NODE} "qm config ${VMID} &>/dev/null; echo \$?" 2>/dev/null || echo 1)
    [ "${VM_EXISTS}" -ne 0 ] && continue

    echo "  [${VMID}] ${VMNAME}:"
    GREP_OUTPUT=$(ssh ${SSH_OPTS} root@${DEFAULT_NODE} "qm config ${VMID} 2>/dev/null | grep -E 'cpu:|numa:|cache:'" || echo "(no matches)")
    echo "${GREP_OUTPUT}" | sed 's/^/    /'
    echo ""
done

# ---------------------------------------------------------------
# Summary
# ---------------------------------------------------------------
echo "========================================================"
echo "  Verification Results — Fase 4: Optimización VMs (P2)"
echo "========================================================"
echo "  PASS: ${PASS}"
echo "  WARN: ${WARN}"
echo "  INFO: ${INFO}"
echo "  FAIL: ${FAIL}"
echo "  Total: $((PASS + WARN + INFO + FAIL))"
echo ""

TOTAL_CHECKS=$((PASS + WARN + FAIL))

if [ "${FAIL}" -eq 0 ] && [ "${WARN}" -eq 0 ]; then
    echo "  ✅ OVERALL: ALL CHECKS PASSED — VM optimization complete"
    echo ""
    echo "  Resumen:"
    echo "  - CPU type host: Configurado en VMs Linux"
    echo "  - NUMA: Habilitado en VMs >${NUMA_VCPU_THRESHOLD} vCPUs"
    echo "  - VirtIO SCSI Single: scsihw configurado con iothread=1"
    echo "  - Ballooning: Mínimo ≥ ${BALLOON_MIN_MB} MB"
    echo "  - Cache: Modo ${DISK_CACHE_MODE} en discos SCSI"
elif [ "${FAIL}" -eq 0 ]; then
    echo "  ⚠️  OVERALL: PASSED WITH ${WARN} WARNING(S)"
    echo "  Revisar advertencias antes de continuar a Fase 5"
else
    echo "  ❌ OVERALL: ${FAIL} CHECK(S) FAILED — review above"
    echo "  Ejecutar scripts 01-04 para corregir configuraciones"
fi

exit ${FAIL}
