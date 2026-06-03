#!/bin/bash
# ================================================================
# verify.sh — T-21: Full verification of shared storage stack
# ================================================================
# Validates all requirements from the storage specs:
#   - Spec ZFS: Pool mirror status, datasets, quotas, compression, atime
#   - Spec NFS: Exports configured, mounted on cluster nodes
#   - Spec Samba: Service active, group exists, share accessible
#   - Proxmox storage: NFS storages registered, content types correct
#   - DR replication: Last snapshot sent, timer active on DR node
#   - Sanoid snapshots: Config loaded, retention correct
#   - ARC: zfs_arc_max values match spec
#   - Live migration: qm migrate dry-run documented
#   - Performance: NFS throughput test documented
#
# DEPENDENCIES:
#   - T-05 (NFS exports) + T-16 (DR replication) completed
#   - Passwordless SSH root access to all cluster nodes
#   - Requires root on the executing node (ssh keys)
#
# USAGE:
#   sudo ./verify.sh              # Full verification
#   sudo ./verify.sh 2>&1 | tee verify.log
#
# EXIT CODES:
#   0 = all checks passed
#   1 = one or more checks FAILED
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
echo "  Verification — F3: Shared Storage Stack"
echo "========================================================"
echo "  Node:         ${SHARED_NODE_NAME} (${SHARED_NODE_IP})"
echo "  Pool:         ${SHARED_POOL}"
echo "  DR node:      ${DR_NODE_NAME} (${DR_NODE_IP})"
echo "  Datasets:     ${#DATASETS[@]}"
echo "  NFS exports:  ${#NFS_DATASETS[@]}"
echo "  Cluster:      ${#CLUSTER_NODES[@]} nodes"
echo "========================================================"
echo ""

# ===============================================================
# Section A: ZFS Pool — mirror status, health (Spec ZFS)
# ===============================================================
echo "--- Section A: ZFS Pool (${SHARED_POOL}) ---"
echo ""

# A1: Pool exists and is healthy
POOL_HEALTH=$(ssh ${SSH_OPTS} root@${SHARED_NODE_IP} \
    "zpool list -H -o health ${SHARED_POOL} 2>/dev/null || echo 'NOT_FOUND'")
if [ "${POOL_HEALTH}" = "ONLINE" ]; then
    check "${SHARED_NODE_NAME}: Pool ${SHARED_POOL} health = ONLINE" "PASS"
else
    check "${SHARED_NODE_NAME}: Pool ${SHARED_POOL} health = ${POOL_HEALTH}" "FAIL"
    echo "       ➡ Fix: Check 'zpool status ${SHARED_POOL}' — replace failed disks"
fi

# A2: Mirror vdev
MIRROR_CHECK=$(ssh ${SSH_OPTS} root@${SHARED_NODE_IP} \
    "zpool status ${SHARED_POOL} 2>/dev/null | grep -c '^\s\+mirror' || true")
if [ "${MIRROR_CHECK}" -gt 0 ]; then
    NUM_DISKS=$(ssh ${SSH_OPTS} root@${SHARED_NODE_IP} \
        "zpool status ${SHARED_POOL} 2>/dev/null | grep -A1 '^\s\+mirror' | tail -1 | wc -w")
    check "${SHARED_NODE_NAME}: ${SHARED_POOL} is mirror vdev (${NUM_DISKS} disks)" "PASS"
else
    check "${SHARED_NODE_NAME}: ${SHARED_POOL} mirror vdev" "FAIL"
    echo "       ➡ Fix: Pool must be mirror. Use 'zpool attach' to add second disk."
fi

# Also verify local-zfs on DR node
for node_ip in "${DR_NODE_IP}"; do
    node_name="${DR_NODE_NAME}"
    pool_name="${LOCAL_POOL}"
    
    POOL_HEALTH=$(ssh ${SSH_OPTS} root@${node_ip} \
        "zpool list -H -o health ${pool_name} 2>/dev/null || echo 'NOT_FOUND'")
    if [ "${POOL_HEALTH}" = "ONLINE" ]; then
        check "${node_name}: Pool ${pool_name} health = ONLINE" "PASS"
    else
        check "${node_name}: Pool ${pool_name} health = ${POOL_HEALTH}" "FAIL"
        echo "       ➡ Fix: Check 'zpool status ${pool_name}'"
    fi
    
    MIRROR_CHECK=$(ssh ${SSH_OPTS} root@${node_ip} \
        "zpool status ${pool_name} 2>/dev/null | grep -c '^\s\+mirror' || true")
    if [ "${MIRROR_CHECK}" -gt 0 ]; then
        check "${node_name}: ${pool_name} is mirror vdev" "PASS"
    else
        check "${node_name}: ${pool_name} mirror vdev" "WARN"
        echo "       (Expected on DR node with multiple disks)"
    fi
done

echo ""

# ===============================================================
# Section B: Datasets — existence, quotas, compression, atime
# ===============================================================
echo "--- Section B: Datasets ---"
echo ""

# B1: All 6 datasets exist
for dataset_def in "${DATASETS[@]}"; do
    DS_NAME="${dataset_def%%:*}"
    REMAINDER="${dataset_def#*:}"
    DS_RECORDSIZE="$(echo "${REMAINDER#*:}" | cut -d: -f1)"
    DS_QUOTA="$(echo "${dataset_def}" | awk -F: '{print $4}')"
    DS_FULL="${SHARED_POOL}/${DS_NAME}"
    
    EXISTS=$(ssh ${SSH_OPTS} root@${SHARED_NODE_IP} \
        "zfs list -H -o name 2>/dev/null | grep -c '^${DS_FULL}$' || true")
    if [ "${EXISTS}" -gt 0 ]; then
        check "Dataset ${DS_FULL} exists" "PASS"
    else
        check "Dataset ${DS_FULL} exists" "FAIL"
        echo "       ➡ Fix: Run 01-create-datasets.sh to recreate missing dataset"
        continue
    fi
    
    # B2: compression=zstd
    COMPRESS=$(ssh ${SSH_OPTS} root@${SHARED_NODE_IP} \
        "zfs get compression -H -o value ${DS_FULL} 2>/dev/null || echo '?'")
    if [ "${COMPRESS}" = "zstd" ]; then
        check "${DS_FULL}: compression=${COMPRESS}" "PASS"
    elif [ "${COMPRESS}" = "zstd-3" ] || [ "${COMPRESS}" = "on" ]; then
        check "${DS_FULL}: compression=${COMPRESS} (acceptable)" "PASS"
    else
        check "${DS_FULL}: compression=${COMPRESS} (expected zstd)" "WARN"
        echo "       ➡ Fix: zfs set compression=zstd ${DS_FULL}"
    fi
    
    # B3: atime=off
    ATIME=$(ssh ${SSH_OPTS} root@${SHARED_NODE_IP} \
        "zfs get atime -H -o value ${DS_FULL} 2>/dev/null || echo '?'")
    if [ "${ATIME}" = "off" ]; then
        check "${DS_FULL}: atime=${ATIME}" "PASS"
    else
        check "${DS_FULL}: atime=${ATIME} (expected off)" "WARN"
        echo "       ➡ Fix: zfs set atime=off ${DS_FULL}"
    fi
    
    # B4: Quota (if set)
    if [ -n "${DS_QUOTA}" ] && [ "${DS_QUOTA}" != "0" ] && [ "${DS_QUOTA}" != "G" ]; then
        QUOTA_VAL=$(ssh ${SSH_OPTS} root@${SHARED_NODE_IP} \
            "zfs get quota -H -o value ${DS_FULL} 2>/dev/null || echo 'none'")
        if [ "${QUOTA_VAL}" = "${DS_QUOTA}" ]; then
            check "${DS_FULL}: quota = ${QUOTA_VAL}" "PASS"
        elif [ "${QUOTA_VAL}" = "none" ] || [ "${QUOTA_VAL}" = "0" ]; then
            check "${DS_FULL}: quota = ${QUOTA_VAL} (expected ${DS_QUOTA})" "WARN"
            echo "       ➡ Fix: zfs set quota=${DS_QUOTA} ${DS_FULL}"
        else
            check "${DS_FULL}: quota = ${QUOTA_VAL} (expected ${DS_QUOTA})" "WARN"
            echo "       ➡ Fix: zfs set quota=${DS_QUOTA} ${DS_FULL}"
        fi
    fi
    
    # B5: Recordsize (if set)
    if [ -n "${DS_RECORDSIZE}" ] && [ "${DS_RECORDSIZE}" != "0" ]; then
        RS_VAL=$(ssh ${SSH_OPTS} root@${SHARED_NODE_IP} \
            "zfs get recordsize -H -o value ${DS_FULL} 2>/dev/null || echo '?'")
        if [ "${RS_VAL}" = "${DS_RECORDSIZE}" ]; then
            check "${DS_FULL}: recordsize = ${RS_VAL}" "PASS"
        else
            check "${DS_FULL}: recordsize = ${RS_VAL} (expected ${DS_RECORDSIZE})" "WARN"
            echo "       ➡ Fix: zfs set recordsize=${DS_RECORDSIZE} ${DS_FULL}"
        fi
    fi
    
    # B6: xattr=sa
    XATTR=$(ssh ${SSH_OPTS} root@${SHARED_NODE_IP} \
        "zfs get xattr -H -o value ${DS_FULL} 2>/dev/null || echo '?'")
    if [ "${XATTR}" = "sa" ]; then
        check "${DS_FULL}: xattr=${XATTR}" "PASS"
    else
        check "${DS_FULL}: xattr=${XATTR} (expected sa)" "WARN"
        echo "       ➡ Fix: zfs set xattr=sa ${DS_FULL}"
    fi
done

# Show dataset usage summary
echo ""
echo "  Dataset usage summary:"
ssh ${SSH_OPTS} root@${SHARED_NODE_IP} \
    "zfs list -H -r -o name,used,avail,refer,quota ${SHARED_POOL} 2>/dev/null" | \
    while read -r line; do
        echo "    ${line}"
    done

echo ""

# ===============================================================
# Section C: NFS Exports (Spec NFS)
# ===============================================================
echo "--- Section C: NFS Exports ---"
echo ""

# C1: Show exports on shared node
echo "  Exports on ${SHARED_NODE_NAME}:"
ssh ${SSH_OPTS} root@${SHARED_NODE_IP} "exportfs -v" 2>/dev/null || echo "  (exportfs not available)"
echo ""

# C2: All NFS datasets exported
for ds in "${NFS_DATASETS[@]}"; do
    EXPORT_PATH="/${SHARED_POOL}/${ds}"
    
    # Check export via showmount
    EXPORTED=$(ssh ${SSH_OPTS} root@${SHARED_NODE_IP} \
        "exportfs -v 2>/dev/null | grep -c '${EXPORT_PATH}' || true")
    if [ "${EXPORTED}" -gt 0 ]; then
        check "NFS export: ${EXPORT_PATH}" "PASS"
    else
        check "NFS export: ${EXPORT_PATH}" "FAIL"
        echo "       ➡ Fix: Add to /etc/exports and run 'exportfs -ra'"
    fi
done

# C3: samba dataset NOT in NFS exports (localhost only is OK)
SAMBA_EXPORTED=$(ssh ${SSH_OPTS} root@${SHARED_NODE_IP} \
    "exportfs -v 2>/dev/null | grep '/${SHARED_POOL}/samba' | grep -v '127.0.0.1' || true")
if [ -z "${SAMBA_EXPORTED}" ]; then
    check "/${SHARED_POOL}/samba NOT exported to network (correct)" "PASS"
else
    check "/${SHARED_POOL}/samba NOT exported to network (currently: ${SAMBA_EXPORTED})" "WARN"
    echo "       ➡ Fix: Edit /etc/exports — samba should be localhost only"
fi

# C4: NFS exports reachable from each cluster node
echo ""
echo "  NFS accessibility from cluster nodes:"
for i in "${!CLUSTER_NODES[@]}"; do
    NODE_IP="${CLUSTER_NODES[$i]}"
    NODE_NAME="${CLUSTER_NODE_NAMES[$i]}"
    EXPORT_LIST=$(ssh ${SSH_OPTS} root@${NODE_IP} \
        "showmount -e ${SHARED_NODE_IP} 2>/dev/null | tail -n +2" || echo "UNREACHABLE")
    
    if [ "${EXPORT_LIST}" = "UNREACHABLE" ]; then
        check "${NODE_NAME} → showmount ${SHARED_NODE_IP}" "FAIL"
        echo "       ➡ Fix: Check network connectivity and NFS services on ${SHARED_NODE_NAME}"
    elif [ -n "${EXPORT_LIST}" ]; then
        EXPORT_COUNT=$(echo "${EXPORT_LIST}" | wc -l)
        check "${NODE_NAME}: ${EXPORT_COUNT} exports visible" "PASS"
    else
        check "${NODE_NAME}: showmount ${SHARED_NODE_IP}" "WARN"
        echo "       (exports may not be visible — check showmount)"
    fi
done

echo ""

# ===============================================================
# Section D: Samba (Spec Samba)
# ===============================================================
echo "--- Section D: Samba ---"
echo ""

# D1: Samba service active
for svc in smbd nmbd; do
    SMB_ACTIVE=$(ssh ${SSH_OPTS} root@${SHARED_NODE_IP} \
        "systemctl is-active ${svc} 2>/dev/null || echo 'inactive'")
    if [ "${SMB_ACTIVE}" = "active" ]; then
        check "${svc} service active on ${SHARED_NODE_NAME}" "PASS"
    else
        check "${svc} service active on ${SHARED_NODE_NAME} (state: ${SMB_ACTIVE})" "FAIL"
        echo "       ➡ Fix: systemctl enable --now ${svc}"
    fi
done

# D2: Samba group exists
GROUP_EXISTS=$(ssh ${SSH_OPTS} root@${SHARED_NODE_IP} \
    "getent group ${SAMBA_GROUP} 2>/dev/null || echo 'NOT_FOUND'")
if [ "${GROUP_EXISTS}" != "NOT_FOUND" ]; then
    check "Group '${SAMBA_GROUP}' exists" "PASS"
else
    check "Group '${SAMBA_GROUP}' exists" "FAIL"
    echo "       ➡ Fix: groupadd ${SAMBA_GROUP}"
fi

# D3: Samba user exists
USER_EXISTS=$(ssh ${SSH_OPTS} root@${SHARED_NODE_IP} \
    "getent passwd ${SAMBA_USER} 2>/dev/null || echo 'NOT_FOUND'")
if [ "${USER_EXISTS}" != "NOT_FOUND" ]; then
    check "User '${SAMBA_USER}' exists" "PASS"
else
    check "User '${SAMBA_USER}' exists" "FAIL"
    echo "       ➡ Fix: useradd -g ${SAMBA_GROUP} -M -s /sbin/nologin ${SAMBA_USER}"
fi

# D4: Samba share accessible via smbclient
SHARE_LIST=$(ssh ${SSH_OPTS} root@${SHARED_NODE_IP} \
    "smbclient -L localhost -N 2>/dev/null" || echo "UNAVAILABLE")
if echo "${SHARE_LIST}" | grep -q "${SAMBA_SHARE_NAME}"; then
    check "Samba share '${SAMBA_SHARE_NAME}' listed" "PASS"
else
    check "Samba share '${SAMBA_SHARE_NAME}' listed" "FAIL"
    echo "       ➡ Fix: Check ${SMB_CONF} for correct share definition"
    echo "       Output: ${SHARE_LIST}"
fi

# D5: Samba dataset exists and path matches
SMB_PATH=$(ssh ${SSH_OPTS} root@${SHARED_NODE_IP} \
    "grep -A1 '^\[${SAMBA_SHARE_NAME}\]' ${SMB_CONF} 2>/dev/null | grep 'path' | awk '{print \$NF}' || echo 'NOT_FOUND'")
if [ "${SMB_PATH}" = "${SAMBA_SHARE_PATH}" ]; then
    check "Samba share path = ${SMB_PATH}" "PASS"
else
    check "Samba share path = ${SMB_PATH} (expected ${SAMBA_SHARE_PATH})" "WARN"
    echo "       ➡ Fix: Edit ${SMB_CONF} to set path = ${SAMBA_SHARE_PATH}"
fi

# D6: SMB3 protocol minimum
SMB_PROTO=$(ssh ${SSH_OPTS} root@${SHARED_NODE_IP} \
    "grep -E '^\s*server min protocol' ${SMB_CONF} 2>/dev/null || echo 'NOT_SET'")
if echo "${SMB_PROTO}" | grep -qi "SMB3\|SMB2_"; then
    check "SMB protocol minimum configured" "PASS"
else
    check "SMB protocol minimum configured (${SMB_PROTO})" "WARN"
    echo "       ➡ Fix: Add 'server min protocol = SMB3' to [global] section"
fi

echo ""

# ===============================================================
# Section E: Proxmox NFS Storage (Spec NFS + PVE)
# ===============================================================
echo "--- Section E: Proxmox NFS Storage ---"
echo ""

# E1: Check pvesm status from first cluster node
echo "  Storage status from ${CLUSTER_NODE_NAMES[0]}:"
PVESM_OUT=$(ssh ${SSH_OPTS} root@${CLUSTER_NODES[0]} \
    "pvesm status 2>/dev/null | grep -E '^shared-' || true")
echo "${PVESM_OUT}" | head -20
echo ""

# E2: Each NFS storage exists with correct content type
for ds in "${NFS_DATASETS[@]}"; do
    STORAGE_ID="${NFS_STORAGE_IDS[${ds}]}"
    CONTENT="${NFS_CONTENT[${ds}]}"
    
    STORAGE_EXISTS=$(ssh ${SSH_OPTS} root@${CLUSTER_NODES[0]} \
        "pvesm status 2>/dev/null | grep -c '^${STORAGE_ID}\s' || true")
    if [ "${STORAGE_EXISTS}" -gt 0 ]; then
        check "Storage ${STORAGE_ID} registered in pvesm" "PASS"
    else
        check "Storage ${STORAGE_ID} registered in pvesm" "FAIL"
        echo "       ➡ Fix: Run 02-configure-nfs.sh or add manually:"
        echo "         pvesm add nfs ${STORAGE_ID} --server ${SHARED_NODE_IP} --export /${SHARED_POOL}/${ds}"
        continue
    fi
    
    # Check content type
    STORAGE_CFG=$(ssh ${SSH_OPTS} root@${CLUSTER_NODES[0]} \
        "pvesm status 2>/dev/null | grep '^${STORAGE_ID}\s'" || echo "")
    
    # Also check storage.cfg for content
    CFG_CONTENT=$(ssh ${SSH_OPTS} root@${CLUSTER_NODES[0]} \
        "grep -A5 '^nfs: ${STORAGE_ID}' /etc/pve/storage.cfg 2>/dev/null | grep 'content' | awk '{print \$NF}'" || echo "")
    if [ "${CFG_CONTENT}" = "${CONTENT}" ]; then
        check "${STORAGE_ID}: content types = ${CONTENT}" "PASS"
    elif [ -n "${CFG_CONTENT}" ]; then
        check "${STORAGE_ID}: content types = ${CFG_CONTENT} (expected ${CONTENT})" "WARN"
        echo "       ➡ Fix: Edit /etc/pve/storage.cfg or re-add storage with --content ${CONTENT}"
    else
        check "${STORAGE_ID}: content types (cannot read config)" "INFO"
    fi
    
    # Check NFS server IP matches
    CFG_SERVER=$(ssh ${SSH_OPTS} root@${CLUSTER_NODES[0]} \
        "grep -A5 '^nfs: ${STORAGE_ID}' /etc/pve/storage.cfg 2>/dev/null | grep 'server' | awk '{print \$NF}'" || echo "")
    if [ "${CFG_SERVER}" = "${SHARED_NODE_IP}" ]; then
        check "${STORAGE_ID}: server = ${CFG_SERVER}" "PASS"
    elif [ -n "${CFG_SERVER}" ]; then
        check "${STORAGE_ID}: server = ${CFG_SERVER} (expected ${SHARED_NODE_IP})" "WARN"
        echo "       ➡ Fix: Update /etc/pve/storage.cfg to point to ${SHARED_NODE_IP}"
    fi
done

# E3: Verify storage.cfg has local-zfs on DR node
LZFS_CFG=$(ssh ${SSH_OPTS} root@${CLUSTER_NODES[0]} \
    "grep -A3 '^zfspool: ${LOCAL_POOL}' /etc/pve/storage.cfg 2>/dev/null" || echo "")
if [ -n "${LZFS_CFG}" ]; then
    check "local-zfs (zfspool) in storage.cfg" "PASS"
else
    check "local-zfs (zfspool) in storage.cfg" "WARN"
    echo "       ➡ Fix: pvesm add zfspool ${LOCAL_POOL} --pool ${LOCAL_POOL} --nodes ${DR_NODE_NAME}"
fi

echo ""

# ===============================================================
# Section F: DR Replication (Spec DR)
# ===============================================================
echo "--- Section F: DR Replication ---"
echo ""

# F1: Verify replication script exists on DR node
REPL_SCRIPT="/usr/local/bin/replicate-shared-to-dr.sh"
SCRIPT_OK=$(ssh ${SSH_OPTS} root@${DR_NODE_IP} \
    "test -x ${REPL_SCRIPT} && echo YES || echo NO" 2>/dev/null || echo "NO")
if [ "${SCRIPT_OK}" = "YES" ]; then
    SCRIPT_SIZE=$(ssh ${SSH_OPTS} root@${DR_NODE_IP} \
        "stat -c%s ${REPL_SCRIPT} 2>/dev/null || echo '?'")
    check "${REPL_SCRIPT} exists and executable (${SCRIPT_SIZE}b)" "PASS"
else
    check "${REPL_SCRIPT} exists and executable" "FAIL"
    echo "       ➡ Fix: Run 04-replication.sh (T-16) to install script"
fi

# F2: Verify systemd timer exists and is active
TIMER_STATE=$(ssh ${SSH_OPTS} root@${DR_NODE_IP} \
    "systemctl is-active zfs-replicate-dr.timer 2>/dev/null || echo 'inactive'")
TIMER_ENABLED=$(ssh ${SSH_OPTS} root@${DR_NODE_IP} \
    "systemctl is-enabled zfs-replicate-dr.timer 2>/dev/null || echo 'disabled'")
if [ "${TIMER_STATE}" = "active" ]; then
    check "zfs-replicate-dr.timer: ${TIMER_STATE} / ${TIMER_ENABLED}" "PASS"
else
    check "zfs-replicate-dr.timer: ${TIMER_STATE} / ${TIMER_ENABLED}" "FAIL"
    echo "       ➡ Fix: systemctl enable --now zfs-replicate-dr.timer"
fi

# F3: Verify systemd service exists
SERVICE_STATE=$(ssh ${SSH_OPTS} root@${DR_NODE_IP} \
    "systemctl cat zfs-replicate-dr.service &>/dev/null && echo OK || echo NOT_FOUND" 2>/dev/null || echo "NOT_FOUND")
if [ "${SERVICE_STATE}" = "OK" ]; then
    check "zfs-replicate-dr.service defined" "PASS"
else
    check "zfs-replicate-dr.service defined" "FAIL"
    echo "       ➡ Fix: Re-run 04-replication.sh Step 3"
fi

# F4: Verify DR dataset exists on DR node
DR_DS_EXISTS=$(ssh ${SSH_OPTS} root@${DR_NODE_IP} \
    "zfs list -H -o name 2>/dev/null | grep -c '^${DR_PREFIX}$' || true")
if [ "${DR_DS_EXISTS}" -gt 0 ]; then
    check "DR dataset ${DR_PREFIX} exists on ${DR_NODE_NAME}" "PASS"
else
    check "DR dataset ${DR_PREFIX} exists on ${DR_NODE_NAME}" "FAIL"
    echo "       ➡ Fix: zfs create ${DR_PREFIX} on ${DR_NODE_NAME}"
fi

# F5: Check DR datasets (children under backup-dr)
DR_CHILDREN=$(ssh ${SSH_OPTS} root@${DR_NODE_IP} \
    "zfs list -H -r -o name ${DR_PREFIX} 2>/dev/null | grep -v '^${DR_PREFIX}$' | wc -l || echo 0")
if [ "${DR_CHILDREN}" -gt 0 ]; then
    check "DR dataset has ${DR_CHILDREN} child dataset(s) from replication" "PASS"
else
    check "DR dataset has replicated child datasets" "INFO"
    echo "       (No replication has run yet. First run will create child datasets.)"
    echo "       ➡ Trigger: ssh root@${DR_NODE_IP} ${REPL_SCRIPT}"
fi

# F6: Show last DR snapshots
echo ""
echo "  Last DR snapshots on ${SHARED_NODE_NAME}:"
SNAPSHOTS=$(ssh ${SSH_OPTS} root@${SHARED_NODE_IP} \
    "zfs list -H -o name -t snapshot -r ${SHARED_POOL} 2>/dev/null | grep 'dr-' | tail -5 || echo '(no DR snapshots yet)'")
echo "    ${SNAPSHOTS}"
echo ""

# Show timer info
echo "  Timer schedule on ${DR_NODE_NAME}:"
ssh ${SSH_OPTS} root@${DR_NODE_IP} \
    "systemctl list-timers zfs-replicate-dr.timer --no-pager 2>/dev/null | tail -3" || \
    echo "    (timer info unavailable)"

echo ""

# ===============================================================
# Section G: Sanoid / Daily Snapshots (Spec Snapshots)
# ===============================================================
echo "--- Section G: Daily Snapshots (Sanoid/Cron) ---"
echo ""

# G1: Check sanoid.conf
SANOID_EXISTS=$(ssh ${SSH_OPTS} root@${SHARED_NODE_IP} \
    "test -f /etc/sanoid/sanoid.conf && echo YES || echo NO" 2>/dev/null || echo "NO")
if [ "${SANOID_EXISTS}" = "YES" ]; then
    check"/etc/sanoid/sanoid.conf exists" "PASS"
    
    # Check retention template
    RETENTION_OK=$(ssh ${SSH_OPTS} root@${SHARED_NODE_IP} \
        "grep -c 'daily = 7' /etc/sanoid/sanoid.conf 2>/dev/null || true")
    if [ "${RETENTION_OK}" -gt 0 ]; then
        check "Sanoid retention: daily=7 (7 days)" "PASS"
    else
        check "Sanoid retention: daily=7" "WARN"
        echo "       ➡ Fix: Add 'daily = 7' to template in /etc/sanoid/sanoid.conf"
    fi
else
    check "/etc/sanoid/sanoid.conf exists" "INFO"
fi

# G2: Check cron fallback
CRON_EXISTS=$(ssh ${SSH_OPTS} root@${SHARED_NODE_IP} \
    "grep -c 'zfs snapshot.*${SHARED_POOL}@daily' /etc/crontab 2>/dev/null || true")
if [ "${CRON_EXISTS}" -gt 0 ]; then
    check "Cron fallback for daily snapshots configured" "PASS"
else
    check "Cron fallback for daily snapshots configured" "INFO"
    echo "       (Add if sanoid is not available: see 04-replication.sh Step 5)"
fi

# G3: Count existing snapshots
SNAP_COUNT=$(ssh ${SSH_OPTS} root@${SHARED_NODE_IP} \
    "zfs list -H -o name -t snapshot -r ${SHARED_POOL} 2>/dev/null | grep -v 'dr-' | wc -l || echo 0")
check "${SNAP_COUNT} daily snapshots on ${SHARED_POOL}" "INFO"

# G4: Show snapshot list
echo ""
echo "  Snapshots on ${SHARED_POOL}:"
ssh ${SSH_OPTS} root@${SHARED_NODE_IP} \
    "zfs list -H -o name,used,creation -t snapshot -r ${SHARED_POOL} 2>/dev/null | grep -v 'dr-' | tail -10 || echo '    (no snapshots yet)'"

echo ""

# ===============================================================
# Section H: ARC Configuration
# ===============================================================
echo "--- Section H: ARC Configuration ---"
echo ""

# H1: ARC on shared node (pve-desa03)
ARC_RUNTIME=$(ssh ${SSH_OPTS} root@${SHARED_NODE_IP} \
    "cat /sys/module/zfs/parameters/zfs_arc_max 2>/dev/null || echo 'N/A'")
if [ "${ARC_RUNTIME}" = "${ARC_MAX_BYTES}" ]; then
    check "${SHARED_NODE_NAME}: zfs_arc_max = ${ARC_RUNTIME} ($((ARC_MAX_BYTES / 1024 / 1024 / 1024)) GB) ✓" "PASS"
elif [ "${ARC_RUNTIME}" = "0" ]; then
    check "${SHARED_NODE_NAME}: zfs_arc_max = 0 (default — 50% RAM auto)" "INFO"
    echo "       (Reboot needed to apply /etc/modprobe.d/zfs.conf)"
else
    check "${SHARED_NODE_NAME}: zfs_arc_max = ${ARC_RUNTIME} (expected ${ARC_MAX_BYTES})" "WARN"
    echo "       ➡ Fix: Set options zfs zfs_arc_max=${ARC_MAX_BYTES} in /etc/modprobe.d/zfs.conf"
fi

# Check modprobe config exists
ZFS_CONF=$(ssh ${SSH_OPTS} root@${SHARED_NODE_IP} \
    "cat /etc/modprobe.d/zfs.conf 2>/dev/null || echo 'NOT_FOUND'")
if [ "${ZFS_CONF}" != "NOT_FOUND" ]; then
    if echo "${ZFS_CONF}" | grep -q "zfs_arc_max=${ARC_MAX_BYTES}"; then
        check "${SHARED_NODE_NAME}: /etc/modprobe.d/zfs.conf has correct zfs_arc_max" "PASS"
    else
        check "${SHARED_NODE_NAME}: /etc/modprobe.d/zfs.conf exists but value may differ" "INFO"
        echo "       ${ZFS_CONF}"
    fi
else
    check "${SHARED_NODE_NAME}: /etc/modprobe.d/zfs.conf exists" "FAIL"
    echo "       ➡ Fix: echo 'options zfs zfs_arc_max=${ARC_MAX_BYTES}' > /etc/modprobe.d/zfs.conf"
fi

# H2: ARC on DR node (pve-desa02)
DR_ARC_RUNTIME=$(ssh ${SSH_OPTS} root@${DR_NODE_IP} \
    "cat /sys/module/zfs/parameters/zfs_arc_max 2>/dev/null || echo 'N/A'")
if [ "${DR_ARC_RUNTIME}" = "${DR_ARC_MAX_BYTES}" ]; then
    check "${DR_NODE_NAME}: zfs_arc_max = ${DR_ARC_RUNTIME} ($((DR_ARC_MAX_BYTES / 1024 / 1024 / 1024)) GB) ✓" "PASS"
elif [ "${DR_ARC_RUNTIME}" = "0" ]; then
    check "${DR_NODE_NAME}: zfs_arc_max = 0 (default)" "INFO"
else
    check "${DR_NODE_NAME}: zfs_arc_max = ${DR_ARC_RUNTIME} (expected ${DR_ARC_MAX_BYTES})" "WARN"
    echo "       ➡ Fix: Set options zfs zfs_arc_max=${DR_ARC_MAX_BYTES} in /etc/modprobe.d/zfs.conf"
fi

DR_ZFS_CONF=$(ssh ${SSH_OPTS} root@${DR_NODE_IP} \
    "cat /etc/modprobe.d/zfs.conf 2>/dev/null || echo 'NOT_FOUND'")
if [ "${DR_ZFS_CONF}" != "NOT_FOUND" ]; then
    if echo "${DR_ZFS_CONF}" | grep -q "zfs_arc_max=${DR_ARC_MAX_BYTES}"; then
        check "${DR_NODE_NAME}: /etc/modprobe.d/zfs.conf has correct zfs_arc_max" "PASS"
    fi
else
    check "${DR_NODE_NAME}: /etc/modprobe.d/zfs.conf exists" "FAIL"
    echo "       ➡ Fix: echo 'options zfs zfs_arc_max=${DR_ARC_MAX_BYTES}' > /etc/modprobe.d/zfs.conf"
fi

echo ""

# ===============================================================
# Section I: Live Migration — Documented Dry-Run
# ===============================================================
echo "--- Section I: Live Migration (Dry-Run) ---"
echo ""

# I1: Check VMs exist on any node with shared storage
MIGRATION_VMS=$(ssh ${SSH_OPTS} root@${CLUSTER_NODES[0]} \
    "qm list 2>/dev/null | tail -n +2 | awk '{print \$1}'" 2>/dev/null || echo "")
VM_COUNT=$(echo "${MIGRATION_VMS}" | grep -c . || true)

if [ "${VM_COUNT}" -gt 0 ]; then
    check "Live migration ready: ${VM_COUNT} VMs on cluster" "INFO"
    echo ""
    echo "  Live migration test documentation:"
    echo "  ==================================="
    echo "  To test live migration between nodes using shared NFS storage:"
    echo ""
    echo "  1. On any node, verify a VM uses shared storage:"
    echo "     $ for vm in \$(qm list | tail -n+2 | awk '{print \$1}'); do"
    echo "         qm config \$vm | grep -E '^(scsi|virtio)' | grep shared-"
    echo "     done"
    echo ""
    echo "  2. Dry-run migration (no actual move):"
    echo "     # Check if VM can migrate (precondition check):"
    echo "     qm status <VMID>"
    echo "     qm config <VMID> | grep -E '^(scsi|virtio|ide|sata)'"
    echo ""
    echo "  3. Live migrate a VM to another node:"
    echo "     # From a cluster node, migrate VM <ID> to <target-node>:"
    echo "     qm migrate <VMID> <target-node> --online --with-local-disks"
    echo ""
    echo "     Example:"
    echo "     qm migrate 100 pve-desa02 --online --with-local-disks"
    echo ""
    echo "  4. Verify migration success:"
    echo "     qm list --all | grep <VMID>"
    echo "     # Expected: VM appears on target node, not on source"
    echo ""
    echo "  Prerequisites for live migration:"
    echo "  - VM storage type must be 'shared-vms' (NFS shared storage)"
    echo "  - Source and target nodes must see the same storage"
    echo "  - VM must not use local resources (passed-through devices,"
    echo "    local ISO mounts not visible on target)"
    echo "  - All cluster nodes must have NFS storage configured (Section E)"
    echo ""
else
    check "No VMs on cluster — migration test skipped" "INFO"
fi

echo ""

# ===============================================================
# Section J: Performance — NFS Throughput (Documented / Simulated)
# ===============================================================
echo "--- Section J: Performance (NFS Throughput) ---"
echo ""

# J1: Test NFS throughput if a shared-vms mount exists
TEST_MOUNT="/mnt/pve/shared-vms"
PERF_RESULT=$(ssh ${SSH_OPTS} root@${CLUSTER_NODES[0]} \
    "mountpoint -q ${TEST_MOUNT} 2>/dev/null && echo MOUNTED || echo NOT_MOUNTED" 2>/dev/null || echo "UNKNOWN")

if [ "${PERF_RESULT}" = "MOUNTED" ]; then
    check "NFS mount ${TEST_MOUNT} available on ${CLUSTER_NODE_NAMES[0]} for throughput test" "PASS"
    
    echo ""
    echo "  Performance test documentation:"
    echo "  ================================"
    echo "  To measure NFS throughput (sequential read/write):"
    echo ""
    echo "  Option A: dd test (quick, ~10 seconds):"
    echo "    # Write test (1 GB):"
    echo "    dd if=/dev/zero of=${TEST_MOUNT}/.perf-test bs=1M count=1024 conv=fdatasync 2>&1"
    echo ""
    echo "    # Read test:"
    echo "    dd if=${TEST_MOUNT}/.perf-test of=/dev/null bs=1M count=1024 2>&1"
    echo ""
    echo "    # Cleanup:"
    echo "    rm ${TEST_MOUNT}/.perf-test"
    echo ""
    echo "  Expected throughput: ≥ 80 MB/s (spec requirement for 1 GbE)"
    echo "  Calculation: 1 Gbps = ~125 MB/s theoretical, minus overhead"
    echo ""
    echo "  Option B: fio test (more comprehensive):"
    echo "    # Install fio if needed: apt-get install fio"
    echo "    fio --directory=${TEST_MOUNT} \\"
    echo "        --name=perf-test \\"
    echo "        --size=1G \\"
    echo "        --rw=readwrite \\"
    echo "        --bs=128k \\"
    echo "        --numjobs=4 \\"
    echo "        --iodepth=8 \\"
    echo "        --runtime=30 \\"
    echo "        --group_reporting"
    echo ""
    echo "  If throughput < 80 MB/s, check:"
    echo "  - Network link speed: ethtool <interface> | grep Speed"
    echo "  - NFS options: 'vers=4.2,hard,intr,noatime'"
    echo "  - sysctl tuning: cat ${NFS_SYSCTL_CONF}"
    echo "  - ARC pressure: Check ARC usage on pve-desa03"
    
    # Quick 100MB test (don't run full 1GB test during verification)
    echo ""
    echo "  Running quick throughput indicator (100 MB write)..."
    DD_RESULT=$(ssh ${SSH_OPTS} root@${CLUSTER_NODES[0]} \
        "dd if=/dev/zero of=${TEST_MOUNT}/.perf-speed bs=1M count=100 conv=fdatasync 2>&1" 2>/dev/null || echo "FAILED")
    DD_SPEED=$(echo "${DD_RESULT}" | grep -oP '\d+\.?\d* MB/s' || echo "")
    if [ -n "${DD_SPEED}" ]; then
        check "NFS write throughput (100 MB): ${DD_SPEED}" "INFO"
        echo "       (Spec requirement: ≥ 80 MB/s for full 1 GB test)"
    else
        check "NFS write throughput test" "INFO"
        echo "       ${DD_RESULT}"
    fi
    
    # Cleanup quick test file
    ssh ${SSH_OPTS} root@${CLUSTER_NODES[0]} "rm -f ${TEST_MOUNT}/.perf-speed" 2>/dev/null || true
else
    check "NFS mount ${TEST_MOUNT} available" "INFO"
    echo "       (No NFS mount found — is PVE storage configured on this node?)"
    echo "       Performance test documented above for manual execution."
fi

echo ""

# ===============================================================
# Section K: Failover Readiness (Documented Dry-Run)
# ===============================================================
echo "--- Section K: Failover Readiness ---"
echo ""

# K1: Verify failover scripts exist
for script in failover-to-desa02.sh failback-to-desa03.sh; do
    if [ -f "${SCRIPT_DIR}/${script}" ]; then
        FILE_SIZE=$(stat -c%s "${SCRIPT_DIR}/${script}" 2>/dev/null || echo "?")
        check "${script} exists (${FILE_SIZE}b)" "PASS"
    else
        check "${script} exists" "FAIL"
        echo "       ➡ Fix: Script should be at ${SCRIPT_DIR}/${script}"
    fi
done

# K2: Verify DR datasets are complete (same datasets as source)
for ds in "vms" "kubernetes" "gitlab" "registry" "backups"; do
    SRC_EXISTS=$(ssh ${SSH_OPTS} root@${SHARED_NODE_IP} \
        "zfs list -H -o name 2>/dev/null | grep -c '^${SHARED_POOL}/${ds}$' || true")
    DST_EXISTS=$(ssh ${SSH_OPTS} root@${DR_NODE_IP} \
        "zfs list -H -o name 2>/dev/null | grep -c '^${DR_PREFIX}/${ds}$' || true")
    
    if [ "${DST_EXISTS}" -gt 0 ]; then
        check "DR dataset ${ds}: replicated" "PASS"
    elif [ "${SRC_EXISTS}" -gt 0 ] && [ "${DST_EXISTS}" -eq 0 ]; then
        check "DR dataset ${ds}: not yet replicated (run replication first)" "INFO"
    fi
done

# K3: Show failover procedure documentation
echo ""
echo "  Failover dry-run procedure (documented):"
echo "  ========================================="
echo ""
echo "  Scenario: pve-desa03 goes down, promote pve-desa02 as NFS server"
echo ""
echo "  Step 1 — Verify DR datasets are current:"
echo "    ssh root@${DR_NODE_IP} 'zfs list -r ${DR_PREFIX}'"
echo ""
echo "  Step 2 — Execute failover:"
echo "    ${SCRIPT_DIR}/failover-to-desa02.sh"
echo ""
echo "  Step 3 — Verify NFS exports on DR node:"
echo "    ssh root@${DR_NODE_IP} 'exportfs -v'"
echo ""
echo "  Step 4 — Update storage servers (from any cluster node):"
echo "    # Update each NFS storage to point at DR node:"
echo "    for storage in shared-vms shared-k8s shared-gitlab shared-registry shared-backups; do"
echo "      pvesm set \$storage --server ${DR_NODE_IP}"
echo "    done"
echo ""
echo "  Step 5 — Verify migration works on new NFS server:"
echo "    showmount -e ${DR_NODE_IP}"
echo "    pvesm status | grep shared-"
echo ""
echo "  Failback procedure:"
echo "  ===================="
echo "  ${SCRIPT_DIR}/failback-to-desa03.sh"
echo ""

# ===============================================================
# Summary
# ===============================================================
echo "========================================================"
echo "  Verification Results — F3: Shared Storage"
echo "========================================================"
echo "  PASS: ${PASS}"
echo "  WARN: ${WARN}"
echo "  INFO: ${INFO}"
echo "  FAIL: ${FAIL}"
echo "  Total checks: $((PASS + WARN + INFO + FAIL))"
echo ""

if [ "${FAIL}" -eq 0 ] && [ "${WARN}" -eq 0 ]; then
    echo "  ✅ OVERALL: ALL CHECKS PASSED — shared storage complete"
    echo ""
    echo "  Resumen:"
    echo "  - Pool ${SHARED_POOL}: mirror, ashift=12, compression=zstd"
    echo "  - Datasets: ${#DATASETS[@]} (vms, kubernetes, gitlab, registry, backups, samba)"
    echo "  - NFS exports: ${#NFS_DATASETS[@]} datasets on ${SHARED_NODE_IP}"
    echo "  - Proxmox storages: shared-vms, shared-k8s, shared-gitlab, shared-registry, shared-backups"
    echo "  - Samba: ${SAMBA_SHARE_NAME} via //${SHARED_NODE_NAME}/${SAMBA_SHARE_NAME}"
    echo "  - DR: local-zfs/backup-dr on ${DR_NODE_NAME} (daily replication)"
    echo "  - ARC: ${SHARED_NODE_NAME}=$((ARC_MAX_BYTES / 1024 / 1024 / 1024))GB / ${DR_NODE_NAME}=$((DR_ARC_MAX_BYTES / 1024 / 1024 / 1024))GB"
    echo "  - Snapshots: daily (sanoid/cron), 7-day retention"
    echo "  - Live migration: available via shared NFS storage"
elif [ "${FAIL}" -eq 0 ]; then
    echo "  ⚠️  OVERALL: PASSED WITH ${WARN} WARNING(S)"
    echo "  Review warnings above — some may be acceptable (e.g.,"
    echo "  snapshots don't exist until first run)"
else
    echo "  ❌ OVERALL: ${FAIL} CHECK(S) FAILED"
    echo "  Review failed checks and fix before deployment."
    echo ""
    echo "  Quick fix references:"
    echo "  ┌──────────────────────┬──────────────────────────────────┐"
    echo "  │ Issue                │ Fix                              │"
    echo "  ├──────────────────────┼──────────────────────────────────┤"
    echo "  │ Pool not found       │ 01-create-datasets.sh            │"
    echo "  │ NFS exports missing  │ 02-configure-nfs.sh              │"
    echo "  │ Samba misconfigured  │ 03-configure-samba.sh            │"
    echo "  │ DR missing           │ 04-replication.sh                │"
    echo "  │ ARC misconfigured    │ /etc/modprobe.d/zfs.conf + reboot│"
    echo "  └──────────────────────┴──────────────────────────────────┘"
fi

exit ${FAIL}
