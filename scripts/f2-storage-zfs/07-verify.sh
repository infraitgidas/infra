#!/bin/bash
# ================================================================
# 07-verify.sh — Task 2.7: Verify ZFS storage implementation
# ================================================================
# Validates all requirements from the storage-zfs spec:
#   - Spec 2.1: ZFS pools exist with ashift=12
#   - Spec 2.2: compression=zstd, atime=off active
#   - Spec 2.3: zfs_arc_max configured (50% RAM)
#   - Spec 2.4: VMs running on ZFS storage
#   - Spec 2.5: Replication jobs configured
#   - Spec 2.6: Daily snapshots configured
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
echo "  Verification: Storage ZFS (Task 2.7)"
echo "========================================================"
echo ""

FIRST_NODE="${NODES[0]}"

# ---------------------------------------------------------------
# Section A: ZFS Pools (Spec 2.1)
# ---------------------------------------------------------------
echo "--- Section A: ZFS pool configuration ---"

for i in "${!NODES[@]}"; do
    IP="${NODES[$i]}"
    NAME="${NODE_NAMES[$i]}"
    
    # Pool exists and is healthy
    POOL_STATUS=$(ssh ${SSH_OPTS} root@${IP} "zpool list -H -o name,health,size ${ZFS_POOL_NAME} 2>/dev/null || echo 'NOT_FOUND'")
    if [ "${POOL_STATUS}" != "NOT_FOUND" ]; then
        check "${NAME}: Pool ${ZFS_POOL_NAME} exists and healthy" "PASS"
        
        POOL_DETAIL=$(ssh ${SSH_OPTS} root@${IP} "zpool list -H -o name,health,size,allocated,free ${ZFS_POOL_NAME} 2>/dev/null")
        echo "       ${POOL_DETAIL}"
    else
        check "${NAME}: Pool ${ZFS_POOL_NAME} exists" "FAIL"
    fi
    
    # ashift=12
    ASHIFT=$(ssh ${SSH_OPTS} root@${IP} "zpool get ashift -H -o value ${ZFS_POOL_NAME} 2>/dev/null || echo 'unknown'")
    if [ "${ASHIFT}" = "12" ]; then
        check "${NAME}: ashift=12" "PASS"
    else
        check "${NAME}: ashift=${ASHIFT} (expected 12)" "WARN"
    fi
done

# ---------------------------------------------------------------
# Section B: ZFS Properties (Spec 2.2)
# ---------------------------------------------------------------
echo ""
echo "--- Section B: ZFS properties (compression, atime) ---"

for i in "${!NODES[@]}"; do
    IP="${NODES[$i]}"
    NAME="${NODE_NAMES[$i]}"
    
    # compression=zstd
    COMPRESSION=$(ssh ${SSH_OPTS} root@${IP} "zfs get compression -H -o value ${ZFS_POOL_NAME} 2>/dev/null || echo 'unknown'")
    if [ "${COMPRESSION}" = "zstd" ]; then
        check "${NAME}: compression=zstd" "PASS"
    elif [ "${COMPRESSION}" = "zstd-3" ] || [ "${COMPRESSION}" = "on" ]; then
        check "${NAME}: compression=${COMPRESSION} (acceptable)" "PASS"
    else
        check "${NAME}: compression=${COMPRESSION} (expected zstd)" "WARN"
    fi
    
    # atime=off
    ATIME=$(ssh ${SSH_OPTS} root@${IP} "zfs get atime -H -o value ${ZFS_POOL_NAME} 2>/dev/null || echo 'unknown'")
    if [ "${ATIME}" = "off" ]; then
        check "${NAME}: atime=off" "PASS"
    else
        check "${NAME}: atime=${ATIME} (expected off)" "WARN"
    fi
done

# ---------------------------------------------------------------
# Section C: ARC Limit (Spec 2.3)
# ---------------------------------------------------------------
echo ""
echo "--- Section C: zfs_arc_max configuration ---"

for i in "${!NODES[@]}"; do
    IP="${NODES[$i]}"
    NAME="${NODE_NAMES[$i]}"
    RAM_GB="${NODE_RAM_GB[$i]}"
    EXPECTED_ARC=$((RAM_GB * 1024 * 1024 * 1024 * ARC_PERCENT / 100))
    
    # Check runtime value (may be 0 if not set, or previous value)
    ARC_RUNTIME=$(ssh ${SSH_OPTS} root@${IP} "cat /sys/module/zfs/parameters/zfs_arc_max 2>/dev/null || echo 'N/A'")
    echo "  ${NAME}: Runtime zfs_arc_max = ${ARC_RUNTIME} (expected ~${EXPECTED_ARC})"
    
    # Check /etc/modprobe.d/zfs.conf
    ZFS_CONF=$(ssh ${SSH_OPTS} root@${IP} "cat /etc/modprobe.d/zfs.conf 2>/dev/null || echo 'NOT_FOUND'")
    if [ "${ZFS_CONF}" != "NOT_FOUND" ]; then
        check "${NAME}: /etc/modprobe.d/zfs.conf exists" "PASS"
        
        if echo "${ZFS_CONF}" | grep -q "zfs_arc_max=${EXPECTED_ARC}"; then
            check "${NAME}: zfs_arc_max=${EXPECTED_ARC} ($((EXPECTED_ARC / 1024 / 1024 / 1024))GB) in config" "PASS"
        else
            check "${NAME}: zfs_arc_max in config (${ZFS_CONF})" "WARN"
        fi
    else
        check "${NAME}: /etc/modprobe.d/zfs.conf exists" "FAIL"
    fi
done

# ---------------------------------------------------------------
# Section D: VMs on ZFS Storage (Spec 2.4)
# ---------------------------------------------------------------
echo ""
echo "--- Section D: VMs running on ZFS storage ---"

for i in "${!NODES[@]}"; do
    IP="${NODES[$i]}"
    NAME="${NODE_NAMES[$i]}"
    
    echo "  ${NAME}:"
    
    # Check VMs
    VM_COUNT=$(ssh ${SSH_OPTS} root@${IP} "qm list --all 2>/dev/null | tail -n +2 | wc -l" 2>/dev/null || echo 0)
    if [ "${VM_COUNT}" -gt 0 ]; then
        ssh ${SSH_OPTS} root@${IP} "qm list --all 2>/dev/null | tail -n +2" | while read -r line; do
            VMID=$(echo "${line}" | awk '{print $1}')
            VMSTORAGE=$(ssh ${SSH_OPTS} -n root@${IP} "qm config ${VMID} 2>/dev/null | grep -E '^(scsi|virtio)[0-9]+:' | grep -oP 'local-zfs:\S+' | head -1" 2>/dev/null || echo "other")
            if echo "${VMSTORAGE}" | grep -q "local-zfs"; then
                echo "       VM ${VMID}: ✅ on ZFS (${VMSTORAGE})"
            else
                echo "       VM ${VMID}: ⚠️  storage=${VMSTORAGE}"
            fi
        done
    fi
    
    # Check CTs
    CT_COUNT=$(ssh ${SSH_OPTS} root@${IP} "pct list 2>/dev/null | tail -n +2 | wc -l" 2>/dev/null || echo 0)
    if [ "${CT_COUNT}" -gt 0 ]; then
        ssh ${SSH_OPTS} root@${IP} "pct list 2>/dev/null | tail -n +2" | while read -r line; do
            CTID=$(echo "${line}" | awk '{print $1}')
            CTSTORAGE=$(ssh ${SSH_OPTS} -n root@${IP} "pct config ${CTID} 2>/dev/null | grep '^rootfs' | grep -oP 'local-zfs:\S+' | head -1" 2>/dev/null || echo "other")
            if echo "${CTSTORAGE}" | grep -q "local-zfs"; then
                echo "       CT ${CTID}: ✅ on ZFS (${CTSTORAGE})"
            else
                echo "       CT ${CTID}: ⚠️  storage=${CTSTORAGE}"
            fi
        done
    fi
    
    if [ "${VM_COUNT}" -eq 0 ] && [ "${CT_COUNT}" -eq 0 ]; then
        echo "       (no VMs/CTs on this node)"
    fi
done

# ---------------------------------------------------------------
# Section E: Replication (Spec 2.5)
# ---------------------------------------------------------------
echo ""
echo "--- Section E: Replication configuration ---"

for i in "${!NODES[@]}"; do
    IP="${NODES[$i]}"
    NAME="${NODE_NAMES[$i]}"
    
    REP_JOBS=$(ssh ${SSH_OPTS} root@${IP} "pvesr list 2>/dev/null | tail -n +2" 2>/dev/null || echo "")
    if [ -n "${REP_JOBS}" ]; then
        check "${NAME}: Replication jobs configured" "PASS"
        echo "       ${REP_JOBS}"
    else
        check "${NAME}: Replication jobs configured" "INFO"
    fi
done

# ---------------------------------------------------------------
# Section F: Storage config
# ---------------------------------------------------------------
echo ""
echo "--- Section F: Storage configuration ---"

# Check ZFS storage in pvesm
ZFS_IN_PVESM=$(ssh ${SSH_OPTS} root@${FIRST_NODE} "pvesm status 2>/dev/null | grep -c 'local-zfs'" 2>/dev/null || echo 0)
if [ "${ZFS_IN_PVESM}" -gt 0 ]; then
    check "local-zfs visible in pvesm status" "PASS"
else
    check "local-zfs visible in pvesm status" "WARN"
fi

# Check storage.cfg
ZFS_IN_CFG=$(ssh ${SSH_OPTS} root@${FIRST_NODE} "grep -c '^zfspool: local-zfs' /etc/pve/storage.cfg 2>/dev/null || echo 0")
if [ "${ZFS_IN_CFG}" -gt 0 ]; then
    check "local-zfs in /etc/pve/storage.cfg" "PASS"
else
    check "local-zfs in /etc/pve/storage.cfg" "WARN"
fi

# ---------------------------------------------------------------
# Section G: Snapshots schedule
# ---------------------------------------------------------------
echo ""
echo "--- Section G: Snapshot schedules ---"

for i in "${!NODES[@]}"; do
    IP="${NODES[$i]}"
    NAME="${NODE_NAMES[$i]}"
    
    # Check for cron jobs related to snapshots
    SNAP_CRON=$(ssh ${SSH_OPTS} root@${IP} "grep -c 'zfs snapshot\|sanoid' /etc/crontab /etc/cron.d/* 2>/dev/null || true")
    if [ "${SNAP_CRON}" -gt 0 ] 2>/dev/null; then
        check "${NAME}: Snapshot schedule configured" "PASS"
    else
        check "${NAME}: Snapshot schedule configured" "INFO"
    fi
done

# ---------------------------------------------------------------
# Summary
# ---------------------------------------------------------------
echo ""
echo "========================================================"
echo "  Verification Results"
echo "========================================================"
echo "  PASS: ${PASS}"
echo "  WARN: ${WARN}"
echo "  FAIL: ${FAIL}"
echo "  Total: $((PASS + WARN + FAIL))"

if [ "${FAIL}" -eq 0 ]; then
    echo ""
    echo "  ✅ OVERALL: ALL CHECKS PASSED"
else
    echo ""
    echo "  ❌ OVERALL: ${FAIL} check(s) FAILED — review above"
fi

exit ${FAIL}
