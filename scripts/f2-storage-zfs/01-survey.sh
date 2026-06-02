#!/bin/bash
# ================================================================
# 01-survey.sh — Pre-flight survey: current state of all nodes
# ================================================================
# Executes a read-only survey of all nodes to verify connectivity,
# disk layout, VMs, and current storage before making changes.
# ================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-env.sh"

echo "========================================================"
echo "  F2 Survey: Current State of Cluster pve-gidas"
echo "========================================================"
echo ""

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

# ---------------------------------------------------------------
# Section 1: Connectivity
# ---------------------------------------------------------------
echo "--- 1. Connectivity ---"

for i in "${!NODES[@]}"; do
    IP="${NODES[$i]}"
    NAME="${NODE_NAMES[$i]}"
    if ssh ${SSH_OPTS} root@${IP} "hostname" &>/dev/null; then
        check "${NAME} (${IP}) reachable" "PASS"
    else
        check "${NAME} (${IP}) reachable" "FAIL"
    fi
done

# ---------------------------------------------------------------
# Section 2: Current OS + ZFS status
# ---------------------------------------------------------------
echo ""
echo "--- 2. ZFS and LVM Status ---"

for i in "${!NODES[@]}"; do
    IP="${NODES[$i]}"
    NAME="${NODE_NAMES[$i]}"
    
    # ZFS
    ZFS_POOLS=$(ssh ${SSH_OPTS} root@${IP} "zpool list -H -o name 2>/dev/null || echo 'NONE'")
    if [ "${ZFS_POOLS}" != "NONE" ]; then
        check "${NAME}: ZFS pool(s) exist: ${ZFS_POOLS}" "WARN"
    else
        check "${NAME}: No ZFS pools (expected)" "PASS"
    fi
    
    # ZFS ARC
    ARC_CUR=$(ssh ${SSH_OPTS} root@${IP} "cat /sys/module/zfs/parameters/zfs_arc_max 2>/dev/null || echo 'N/A'")
    check "${NAME}: Current zfs_arc_max = ${ARC_CUR}" "INFO"
done

# ---------------------------------------------------------------
# Section 3: VMs/CTs per node
# ---------------------------------------------------------------
echo ""
echo "--- 3. VM and CT Inventory ---"

for i in "${!NODES[@]}"; do
    IP="${NODES[$i]}"
    NAME="${NODE_NAMES[$i]}"
    
    echo "  [${NAME}] VMs:"
    ssh ${SSH_OPTS} root@${IP} "qm list --all 2>/dev/null | tail -n +2" || echo "  (none)"
    echo "  [${NAME}] CTs:"
    ssh ${SSH_OPTS} root@${IP} "pct list 2>/dev/null | tail -n +2" || echo "  (none)"
done

# ---------------------------------------------------------------
# Section 4: Disk layout for ZFS targets
# ---------------------------------------------------------------
echo ""
echo "--- 4. ZFS Target Device Verification ---"

for i in "${!NODES[@]}"; do
    IP="${NODES[$i]}"
    NAME="${NODE_NAMES[$i]}"
    DEV="${ZFS_DEVICES[$i]}"
    
    echo "  [${NAME}] Target device: ${DEV}"
    
    if ssh ${SSH_OPTS} root@${IP} "test -b ${DEV} 2>/dev/null || test -e ${DEV} 2>/dev/null"; then
        check "${NAME}: Device ${DEV} exists" "PASS"
    else
        # Check if path doesn't exist yet (e.g. LVM LV needs to be created)
        if [[ "${DEV}" == /dev/pve/* ]]; then
            check "${NAME}: LVM device ${DEV} — will be created during conversion" "INFO"
        else
            check "${NAME}: Device ${DEV} NOT found" "FAIL"
        fi
    fi
    
    # Check if device is already used by ZFS
    if ssh ${SSH_OPTS} root@${IP} "blkid ${DEV} 2>/dev/null | grep -q zfs_member" 2>/dev/null; then
        check "${NAME}: ${DEV} has ZFS label (needs labelclear)" "WARN"
    fi
done

# ---------------------------------------------------------------
# Section 5: Storage configuration
# ---------------------------------------------------------------
echo ""
echo "--- 5. Storage Configuration ---"

for i in "${!NODES[@]}"; do
    IP="${NODES[$i]}"
    NAME="${NODE_NAMES[$i]}"
    
    echo "  [${NAME}] pvesm status:"
    ssh ${SSH_OPTS} root@${IP} "pvesm status 2>/dev/null | grep -v inactive" || echo "  (no output)"
done

# ---------------------------------------------------------------
# Section 6: LVM thin pool details
# ---------------------------------------------------------------
echo ""
echo "--- 6. LVM Thin Pool Usage ---"

for i in "${!NODES[@]}"; do
    IP="${NODES[$i]}"
    NAME="${NODE_NAMES[$i]}"
    
    echo "  [${NAME}] LVM thin pools:"
    ssh ${SSH_OPTS} root@${IP} "lvs -o lv_name,lv_attr,pool_lv,origin,data_percent,lv_size 2>/dev/null | grep -iE 'twi|Vwi|tzo' || echo '  (none)'"
done

# ---------------------------------------------------------------
# Section 7: PBS Backups Status
# ---------------------------------------------------------------
echo ""
echo "--- 7. PBS Backup Verification ---"

FIRST_NODE="${NODES[0]}"
JOBS_COUNT=$(ssh ${SSH_OPTS} root@${FIRST_NODE} "pvesh get /cluster/backup --noborder --output-format json 2>/dev/null | python3 -c 'import sys,json; print(len(json.load(sys.stdin)))' 2>/dev/null || echo 0")
if [ "${JOBS_COUNT}" -gt 0 ]; then
    check "Backup jobs exist (${JOBS_COUNT} configured)" "PASS"
else
    check "Backup jobs exist" "WARN"
fi

# ---------------------------------------------------------------
# Summary
# ---------------------------------------------------------------
echo ""
echo "========================================================"
echo "  Survey Results"
echo "========================================================"
echo "  PASS: ${PASS}"
echo "  WARN: ${WARN}"
echo "  FAIL: ${FAIL}"
echo "  Total: $((PASS + WARN + FAIL))"
echo ""

if [ "${FAIL}" -gt 0 ]; then
    echo "  ❌ ${FAIL} check(s) FAILED — review above before proceeding"
    exit 1
else
    echo "  ✅ Survey complete — ready for F2 implementation"
fi
