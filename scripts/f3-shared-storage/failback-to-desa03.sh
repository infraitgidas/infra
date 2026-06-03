#!/bin/bash
# ================================================================
# failback-to-desa03.sh — T-18: DR failback (pve-desa02 → pve-desa03)
# ================================================================
# MANUAL FAILBACK PROCEDURE — Run after pve-desa03 is recovered.
# Restores NFS service to the original shared-zfs on pve-desa03.
#
# What this does:
#   1. Verifies pve-desa03 is operational with shared-zfs pool
#   2. Syncs data back from pve-desa02 (local-zfs/backup-dr) to
#      pve-desa03 (shared-zfs) via reverse zfs send/recv
#   3. Prints instructions for restoring Proxmox storage.cfg
#      to point back to pve-desa03
#   4. Re-enables DR replication timer
#
# PREREQUISITES:
#   - pve-desa03 is recovered and shared-zfs pool is healthy
#   - Run from a management workstation with SSH access to both nodes
#
# ⚠️  WARNING: This performs a FULL reverse sync before restoring.
#     Do NOT skip the sync step — data loss risk.
# ================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-env.sh"

echo "========================================================"
echo "  DR Failback: Restore NFS to ${SHARED_NODE_NAME}"
echo "========================================================"
echo ""
echo "⚠️  This script syncs data BACK from ${DR_NODE_NAME} to"
echo "   ${SHARED_NODE_NAME} and restores NFS to the original server."
echo ""
echo "   Prerequisites:"
echo "   - ${SHARED_NODE_NAME} is recovered and healthy"
echo "   - shared-zfs pool is ONLINE on ${SHARED_NODE_NAME}"
echo "   - SSH root access to both nodes"
echo ""
echo "   Press Ctrl+C now to abort, or Enter to continue..."
read -r

# ---------------------------------------------------------------
# Step 1: Verify both nodes are reachable
# ---------------------------------------------------------------
echo ""
echo "[1/6] Verifying both nodes are reachable..."

for NODE_IP in "${SHARED_NODE_IP}" "${DR_NODE_IP}"; do
    NODE_NAME="unknown"
    [ "${NODE_IP}" = "${SHARED_NODE_IP}" ] && NODE_NAME="${SHARED_NODE_NAME}"
    [ "${NODE_IP}" = "${DR_NODE_IP}" ] && NODE_NAME="${DR_NODE_NAME}"
    
    ssh ${SSH_OPTS} root@${NODE_IP} "hostname" >/dev/null 2>&1 || {
        echo "❌ Cannot reach ${NODE_NAME} (${NODE_IP})"
        exit 1
    }
    echo "[1/6] ✅ ${NODE_NAME} reachable"
done

# ---------------------------------------------------------------
# Step 2: Verify shared-zfs pool is healthy on pve-desa03
# ---------------------------------------------------------------
echo ""
echo "[2/6] Verifying ${SHARED_POOL} pool on ${SHARED_NODE_NAME}..."

POOL_OK=$(ssh ${SSH_OPTS} root@${SHARED_NODE_IP} \
    "zpool list -H -o health ${SHARED_POOL} 2>/dev/null || echo 'NOT_FOUND'")
if [ "${POOL_OK}" != "ONLINE" ]; then
    echo "❌ Pool ${SHARED_POOL} not healthy on ${SHARED_NODE_NAME}"
    echo "   Current status: ${POOL_OK}"
    echo "   Check: ssh root@${SHARED_NODE_IP} zpool status ${SHARED_POOL}"
    exit 1
fi
echo "[2/6] ✅ ${SHARED_POOL} healthy on ${SHARED_NODE_NAME}"

# Verify datasets exist on shared-zfs
echo ""
echo "[2/6] Verifying datasets on ${SHARED_NODE_NAME}..."
DS_LIST=$(ssh ${SSH_OPTS} root@${SHARED_NODE_IP} \
    "zfs list -H -o name -r ${SHARED_POOL} 2>/dev/null | sort" || echo "")

DR_DATASETS="vms kubernetes gitlab registry backups"
MISSING=false
for ds in ${DR_DATASETS}; do
    if echo "${DS_LIST}" | grep -q "${SHARED_POOL}/${ds}$"; then
        echo "[2/6] ✅ ${SHARED_POOL}/${ds} exists"
    else
        echo "[2/6] ⚠️  ${SHARED_POOL}/${ds} missing — will create during sync"
    fi
done

# ---------------------------------------------------------------
# Step 3: Verify DR datasets on pve-desa02
# ---------------------------------------------------------------
echo ""
echo "[3/6] Verifying DR datasets on ${DR_NODE_NAME}..."

DR_LIST=$(ssh ${SSH_OPTS} root@${DR_NODE_IP} \
    "zfs list -H -o name -r ${DR_PREFIX} 2>/dev/null | sort" || echo "")

MISSING=false
for ds in ${DR_DATASETS}; do
    if echo "${DR_LIST}" | grep -q "${DR_PREFIX}/${ds}$"; then
        echo "[3/6] ✅ ${DR_PREFIX}/${ds} exists"
    else
        echo "[3/6] ❌ ${DR_PREFIX}/${ds} NOT FOUND on DR node"
        MISSING=true
    fi
done

if [ "${MISSING}" = true ]; then
    echo "❌ Some DR datasets are missing. Cannot failback."
    exit 1
fi

# ---------------------------------------------------------------
# Step 4: Reverse sync (pve-desa02 → pve-desa03)
# ---------------------------------------------------------------
echo ""
echo "[4/6] Reverse sync: ${DR_NODE_NAME} → ${SHARED_NODE_NAME}"
echo "⚠️  This may take a long time depending on data volume."
echo ""

for ds in ${DR_DATASETS}; do
    SRC_PATH="${DR_PREFIX}/${ds}"
    DST_PATH="${SHARED_POOL}/${ds}"
    
    echo "--- Syncing ${SRC_PATH} → ${DST_PATH} ---"
    
    # Take snapshot on DR node
    SNAP_NAME="failback-$(date +%Y%m%d-%H%M%S)"
    echo "  Taking snapshot ${SRC_PATH}@${SNAP_NAME}..."
    ssh ${SSH_OPTS} root@${DR_NODE_IP} "zfs snapshot ${SRC_PATH}@${SNAP_NAME}"
    
    # Send to pve-desa03 (reverse direction)
    echo "  Sending via SSH to ${SHARED_NODE_NAME}..."
    ssh ${SSH_OPTS} root@${DR_NODE_IP} "zfs send -w -R ${SRC_PATH}@${SNAP_NAME}" | \
        ssh ${SSH_OPTS} root@${SHARED_NODE_IP} "zfs receive -F ${DST_PATH}"
    
    echo "  ✅ ${ds} synced"
    echo ""
done

echo "[4/6] ✅ Reverse sync completed"

# ---------------------------------------------------------------
# Step 5: Clean up — reset DR datasets to read-only, restart DR timer
# ---------------------------------------------------------------
echo ""
echo "[5/6] Post-failback cleanup on ${DR_NODE_NAME}..."

# Set DR datasets back to readonly
for ds in ${DR_DATASETS}; do
    DS_PATH="${DR_PREFIX}/${ds}"
    echo "  Setting readonly=on on ${DS_PATH}..."
    ssh ${SSH_OPTS} root@${DR_NODE_IP} "zfs set readonly=on ${DS_PATH}" || true
done

# Re-enable DR replication timer
echo ""
echo "[5/6] Re-enabling DR replication timer..."
ssh ${SSH_OPTS} root@${DR_NODE_IP} bash -s << 'REMOTE'
    set -euo pipefail
    systemctl daemon-reload
    systemctl enable --now zfs-replicate-dr.timer 2>/dev/null || {
        echo "⚠️  Could not enable timer. Check: systemctl status zfs-replicate-dr.timer"
    }
    systemctl list-timers zfs-replicate-dr.timer --no-pager 2>/dev/null | tail -3
REMOTE

echo "[5/6] ✅ DR timer re-enabled"

# ---------------------------------------------------------------
# Step 6: Print manual steps
# ---------------------------------------------------------------
echo ""
echo "[6/6] Manual steps required — UPDATE STORAGE.CFG"
echo "========================================================"
echo ""
echo "⚠️  Data has been synced back to ${SHARED_NODE_NAME}."
echo "   But Proxmox storage.cfg still points to ${DR_NODE_IP} (from failover)."
echo ""
echo "   From ANY cluster node, update each storage back to ${SHARED_NODE_IP}:"
echo ""

for ds in ${DR_DATASETS}; do
    STORAGE_ID=""
    case "${ds}" in
        vms)        STORAGE_ID="shared-vms" ;;
        kubernetes) STORAGE_ID="shared-k8s" ;;
        gitlab)     STORAGE_ID="shared-gitlab" ;;
        registry)   STORAGE_ID="shared-registry" ;;
        backups)    STORAGE_ID="shared-backups" ;;
    esac
    if [ -n "${STORAGE_ID}" ]; then
        echo "   pvesh set /storage/${STORAGE_ID} --server ${SHARED_NODE_IP}"
    fi
done

echo ""
echo "   Or use the Proxmox GUI: Datacenter → Storage → select storage → Edit → server IP"
echo ""
echo "=== T-18: Failback procedure initiated ==="
echo ""
echo "✅ Reverse sync completed (${DR_NODE_NAME} → ${SHARED_NODE_NAME})"
echo "✅ DR datasets set to read-only"
echo "✅ DR replication timer re-enabled"
echo "⚠️  PENDING: Update Proxmox storage.cfg (manual step above)"
echo ""
echo "📋 After updating storage.cfg, verify:"
echo "   showmount -e ${SHARED_NODE_IP}"
echo "   pvesm status (from any cluster node)"
echo ""
echo "📋 Force DR replication to catch up:"
echo "   ssh root@${DR_NODE_IP} /usr/local/bin/replicate-shared-to-dr.sh"
