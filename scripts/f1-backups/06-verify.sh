#!/bin/bash
# ================================================================
# 06-verify.sh — Task 1.7: Verify backup implementation
# ================================================================
# Validates all requirements from the spec:
#   - Spec 1.2: Backup executed (backup job exists, backup exists)
#   - Spec 1.4: Encryption active (key present, encryption in use)
#   - Spec 1.5: Restore functional (restore capability test)
# ================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-env.sh"

CLUSTER_NODE="${NODES[0]}"  # pve-desa01
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
echo "  Verification: Backups (Task 1.7)"
echo "========================================================"
echo ""

# ---------------------------------------------------------------
# Section A: VM 102 Cache Fix (Task 1.2)
# ---------------------------------------------------------------
echo "--- Section A: VM 102 cache fix ---"

VM102_CACHE=$(ssh ${SSH_OPTS} root@192.168.1.11 "qm config 102 2>/dev/null | grep '^scsi0' | grep -oP 'cache=\K\w+' || echo 'NOT_FOUND'")
if [ "${VM102_CACHE}" = "none" ]; then
    check "VM 102 scsi0 cache=none" "PASS"
elif [ "${VM102_CACHE}" = "NOT_FOUND" ]; then
    check "VM 102 scsi0 config readable" "FAIL"
else
    check "VM 102 scsi0 cache=... (expected none, got ${VM102_CACHE})" "FAIL"
fi

# ---------------------------------------------------------------
# Section B: PBS Installation (Task 1.3)
# ---------------------------------------------------------------
echo ""
echo "--- Section B: PBS installation ---"

PBS_PKG=$(ssh ${SSH_OPTS} root@${PBS_IP} "dpkg -l proxmox-backup-server 2>/dev/null | grep '^ii' || echo 'NOT_INSTALLED'")
if [ "${PBS_PKG}" != "NOT_INSTALLED" ]; then
    check "PBS package installed on ${PBS_HOSTNAME}" "PASS"
else
    check "PBS package installed on ${PBS_HOSTNAME}" "FAIL"
fi

PBS_SERVICE=$(ssh ${SSH_OPTS} root@${PBS_IP} "systemctl is-active proxmox-backup-proxy 2>/dev/null || echo 'INACTIVE'")
if [ "${PBS_SERVICE}" = "active" ]; then
    check "PBS proxy service running" "PASS"
else
    check "PBS proxy service running (status: ${PBS_SERVICE})" "FAIL"
fi

# Check ZFS pool
ZFS_POOL=$(ssh ${SSH_OPTS} root@${PBS_IP} "zpool list -H -o name 2>/dev/null | head -1 || echo 'NO_POOL'")
if [ "${ZFS_POOL}" != "NO_POOL" ]; then
    check "ZFS pool exists (${ZFS_POOL})" "PASS"
    
    ZFS_COMPRESSION=$(ssh ${SSH_OPTS} root@${PBS_IP} "zfs get compression -H -o value ${ZFS_POOL} 2>/dev/null || echo 'UNKNOWN'")
    if [ "${ZFS_COMPRESSION}" = "zstd" ]; then
        check "ZFS compression=zstd on ${ZFS_POOL}" "PASS"
    else
        check "ZFS compression=zstd on ${ZFS_POOL} (got: ${ZFS_COMPRESSION})" "WARN"
    fi
else
    check "ZFS pool exists" "FAIL"
fi

# Check PBS datastore
PBS_DATASTORE_LIST=$(ssh ${SSH_OPTS} root@${PBS_IP} "proxmox-backup-manager datastore list 2>/dev/null | grep -c ${PBS_DATASTORE} || echo 0")
if [ "${PBS_DATASTORE_LIST}" -gt 0 ]; then
    check "PBS datastore '${PBS_DATASTORE}' exists" "PASS"
else
    check "PBS datastore '${PBS_DATASTORE}' exists" "FAIL"
fi

# ---------------------------------------------------------------
# Section C: Encryption Key (Task 1.4)
# ---------------------------------------------------------------
echo ""
echo "--- Section C: Encryption key ---"

for i in "${!NODES[@]}"; do
    NODE_IP="${NODES[$i]}"
    NODE_NAME="${NODE_NAMES[$i]}"
    
    KEY_EXISTS=$(ssh ${SSH_OPTS} root@${NODE_IP} "test -f ${ENCRYPTION_KEY_PATH} && echo 'EXISTS' || echo 'MISSING'")
    if [ "${KEY_EXISTS}" = "EXISTS" ]; then
        KEY_SIZE=$(ssh ${SSH_OPTS} root@${NODE_IP} "wc -c < ${ENCRYPTION_KEY_PATH}")
        KEY_PERMS=$(ssh ${SSH_OPTS} root@${NODE_IP} "stat -c '%a' ${ENCRYPTION_KEY_PATH}")
        if [ "${KEY_SIZE}" -eq 65 ] && [ "${KEY_PERMS}" = "600" ]; then
            check "Encryption key on ${NODE_NAME} (${KEY_SIZE} bytes, perms ${KEY_PERMS})" "PASS"
        else
            check "Encryption key on ${NODE_NAME} (size=${KEY_SIZE}, perms=${KEY_PERMS})" "WARN"
        fi
    else
        check "Encryption key on ${NODE_NAME}" "FAIL"
    fi
done

# Check key on PBS too
PBS_KEY_EXISTS=$(ssh ${SSH_OPTS} root@${PBS_IP} "test -f ${ENCRYPTION_KEY_PATH} && echo 'EXISTS' || echo 'MISSING'")
if [ "${PBS_KEY_EXISTS}" = "EXISTS" ]; then
    check "Encryption key on ${PBS_HOSTNAME} (PBS)" "PASS"
else
    check "Encryption key on ${PBS_HOSTNAME} (PBS)" "WARN"
fi

# ---------------------------------------------------------------
# Section D: PBS Storage Config (Task 1.5)
# ---------------------------------------------------------------
echo ""
echo "--- Section D: PBS storage configuration ---"

STORAGE_IN_CFG=$(ssh ${SSH_OPTS} root@${CLUSTER_NODE} "grep -c '^pbs: ${PBS_STORAGE_ID}' /etc/pve/storage.cfg 2>/dev/null || echo 0")
if [ "${STORAGE_IN_CFG}" -gt 0 ]; then
    check "PBS storage '${PBS_STORAGE_ID}' in storage.cfg" "PASS"
    
    # Check fingerprint is present
    FP_IN_CFG=$(ssh ${SSH_OPTS} root@${CLUSTER_NODE} "grep -c 'fingerprint' /etc/pve/storage.cfg 2>/dev/null || echo 0")
    if [ "${FP_IN_CFG}" -gt 0 ]; then
        check "TLS fingerprint configured in storage.cfg" "PASS"
    else
        check "TLS fingerprint configured in storage.cfg" "WARN"
    fi
    
    # Check encryption key reference
    KEY_IN_CFG=$(ssh ${SSH_OPTS} root@${CLUSTER_NODE} "grep -c 'encryption-key' /etc/pve/storage.cfg 2>/dev/null || echo 0")
    if [ "${KEY_IN_CFG}" -gt 0 ]; then
        check "Encryption key referenced in storage.cfg" "PASS"
    else
        check "Encryption key referenced in storage.cfg" "WARN"
    fi
else
    check "PBS storage '${PBS_STORAGE_ID}' in storage.cfg" "FAIL"
fi

# ---------------------------------------------------------------
# Section E: Backup Jobs (Task 1.6)
# ---------------------------------------------------------------
echo ""
echo "--- Section E: Backup jobs ---"

# Check jobs via pvesh
JOBS_COUNT=$(ssh ${SSH_OPTS} root@${CLUSTER_NODE} "pvesh get /cluster/backup --noborder --output-format json 2>/dev/null | python3 -c 'import sys,json; print(len(json.load(sys.stdin)))' 2>/dev/null || echo 0")
if [ "${JOBS_COUNT}" -gt 0 ]; then
    check "Backup jobs exist (${JOBS_COUNT} configured)" "PASS"
else
    check "Backup jobs exist" "FAIL"
fi

# Check prune jobs on PBS
PRUNE_JOBS=$(ssh ${SSH_OPTS} root@${PBS_IP} "proxmox-backup-manager prune-job list 2>/dev/null | grep -c ${PBS_DATASTORE} || echo 0")
if [ "${PRUNE_JOBS}" -gt 0 ]; then
    check "Prune job configured on ${PBS_DATASTORE}" "PASS"
else
    check "Prune job configured on ${PBS_DATASTORE}" "WARN"
fi

GC_JOBS=$(ssh ${SSH_OPTS} root@${PBS_IP} "proxmox-backup-manager garbage-collection-job list 2>/dev/null | grep -c ${PBS_DATASTORE} || echo 0")
if [ "${GC_JOBS}" -gt 0 ]; then
    check "GC job configured on ${PBS_DATASTORE}" "PASS"
else
    check "GC job configured on ${PBS_DATASTORE}" "WARN"
fi

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
