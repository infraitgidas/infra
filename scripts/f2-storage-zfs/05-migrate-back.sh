#!/bin/bash
# ================================================================
# 05-migrate-back.sh — Task 2.5: Move VMs back to original node
# ================================================================
# After ZFS pools are created on the original nodes, migrate
# VMs/CTs back so they land on ZFS storage.
#
# Migration back:
#   pve-desa02 (CT 105 + VM 100) → pve-desa01 (now with ZFS)
#   pve-desa03 (VM 109)          → pve-desa04 (now with ZFS)
#
# PREREQUISITE: 03-create-zpool.sh and 04-configure-zfs.sh done
# ================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-env.sh"

echo "=== Task 2.5: Move VMs back to original nodes (on ZFS) ==="
echo ""

# ---------------------------------------------------------------
# Step 1: Verify ZFS pools exist on original nodes
# ---------------------------------------------------------------
echo "[1/4] Verifying ZFS pools on original nodes..."

for i in 0 3; do
    IP="${NODES[$i]}"
    NAME="${NODE_NAMES[$i]}"
    
    POOL_OK=$(ssh ${SSH_OPTS} root@${IP} "zpool list -H -o health ${ZFS_POOL_NAME} 2>/dev/null || echo 'NOT_FOUND'")
    if [ "${POOL_OK}" = "ONLINE" ]; then
        echo "[1/4] ✅ ${NAME}: Pool ${ZFS_POOL_NAME} is ONLINE"
    else
        echo "❌ ${NAME}: Pool ${ZFS_POOL_NAME} NOT healthy (${POOL_OK})"
        echo "Run 03-create-zpool.sh first."
        exit 1
    fi
done

# Also check that destination storage is configured
FIRST_NODE="${NODES[0]}"
ZFS_STORAGE=$(ssh ${SSH_OPTS} root@${FIRST_NODE} "pvesm status 2>/dev/null | grep -c 'local-zfs'" 2>/dev/null || echo 0)
if [ "${ZFS_STORAGE}" -eq 0 ]; then
    echo "⚠️  local-zfs storage not visible in pvesm. Checking storage.cfg..."
    ssh ${SSH_OPTS} root@${FIRST_NODE} "grep -A4 '^zfspool: local-zfs' /etc/pve/storage.cfg" || {
        echo "❌ local-zfs not in storage.cfg. Run 04-configure-zfs.sh first."
        exit 1
    }
fi

# ---------------------------------------------------------------
# Step 2: Migrate VMs back to original nodes (now with ZFS)
# ---------------------------------------------------------------
echo ""
echo "[2/4] Migrating VMs/CTs back to original nodes..."

# Build reverse migration pairs
declare -a REVERSE_PAIRS=(
    "1:0"   # pve-desa02 → pve-desa01
    "2:3"   # pve-desa03 → pve-desa04
)

migrate_back() {
    local VMID="$1"
    local SRC_IP="$2"
    local DST_NODE="$3"
    local IS_CT="$4"
    local DST_IDX="$5"
    
    echo "[2/4] Migrating ${IS_CT} ${VMID} from ${SRC_IP} → ${DST_NODE} (target: local-zfs)..."
    
    if [ "${IS_CT}" = "CT" ]; then
        # Container migration with target storage
        echo "[2/4]   Running: pct migrate ${VMID} ${DST_NODE} --storage local-zfs --restart..."
        ssh ${SSH_OPTS} root@${SRC_IP} "pct migrate ${VMID} ${DST_NODE} --storage local-zfs --restart" 2>&1 || {
            echo "❌ Failed to migrate CT ${VMID} back"
            return 1
        }
    else
        # VM migration
        VM_STATUS=$(ssh ${SSH_OPTS} root@${SRC_IP} "qm status ${VMID} 2>/dev/null | awk '{print \$2}'")
        
        if [ "${VM_STATUS}" = "running" ]; then
            echo "[2/4]   VM ${VMID} is running — live migration to ZFS storage..."
            ssh ${SSH_OPTS} root@${SRC_IP} "qm migrate ${VMID} ${DST_NODE} --target-storage local-zfs" 2>&1 || {
                echo "❌ Live migration of VM ${VMID} failed"
                return 1
            }
        else
            echo "[2/4]   VM ${VMID} is ${VM_STATUS} — cold migration..."
            ssh ${SSH_OPTS} root@${SRC_IP} "qm migrate ${VMID} ${DST_NODE} --target-storage local-zfs --online 0" 2>&1 || {
                echo "❌ Cold migration of VM ${VMID} failed"
                return 1
            }
        fi
    fi
    
    echo "[2/4] ✅ ${IS_CT} ${VMID} migrated back to ${DST_NODE}"
    return 0
}

for pair in "${REVERSE_PAIRS[@]}"; do
    SRC_IDX="${pair%%:*}"
    DST_IDX="${pair##*:*}"
    SRC_IP="${NODES[$SRC_IDX]}"
    SRC_NAME="${NODE_NAMES[$SRC_IDX]}"
    DST_NODE="${NODE_NAMES[$DST_IDX]}"
    
    echo "--- Migrating back from ${SRC_NAME} → ${DST_NODE} ---"
    
    # Get VMs from the original source node (now on the neighbor)
    VMS="${NODE_VMS[$DST_IDX]}"  # Original VMs originally on DST_IDX
    if [ -z "${VMS}" ]; then
        echo "No VMs to migrate back from ${SRC_NAME}"
        continue
    fi
    
    IFS=',' read -ra VM_LIST <<< "${VMS}"
    for VMID in "${VM_LIST[@]}"; do
        VMID=$(echo "${VMID}" | xargs)
        IS_CT="VM"
        [ "${CT_VMS[$VMID]:-0}" = "1" ] && IS_CT="CT"
        
        # Check if VM/CT is on the source node
        echo "[2/4] Checking if ${IS_CT} ${VMID} is on ${SRC_NAME}..."
        if [ "${IS_CT}" = "CT" ]; then
            ON_SRC=$(ssh ${SSH_OPTS} root@${SRC_IP} "pct list 2>/dev/null | grep -c \"^${VMID}\"" 2>/dev/null || echo 0)
        else
            ON_SRC=$(ssh ${SSH_OPTS} root@${SRC_IP} "qm list --all 2>/dev/null | grep -c \"^${VMID}\"" 2>/dev/null || echo 0)
        fi
        
        if [ "${ON_SRC}" -eq 0 ]; then
            echo "[2/4] ⏭️  ${IS_CT} ${VMID} NOT on ${SRC_NAME} — checking if already back on ${DST_NODE}..."
            if [ "${IS_CT}" = "CT" ]; then
                ON_DST=$(ssh ${SSH_OPTS} root@${NODES[$DST_IDX]} "pct list 2>/dev/null | grep -c \"^${VMID}\"" 2>/dev/null || echo 0)
            else
                ON_DST=$(ssh ${SSH_OPTS} root@${NODES[$DST_IDX]} "qm list --all 2>/dev/null | grep -c \"^${VMID}\"" 2>/dev/null || echo 0)
            fi
            if [ "${ON_DST}" -gt 0 ]; then
                echo "[2/4] ✅ ${IS_CT} ${VMID} already back on ${DST_NODE}"
            fi
            continue
        fi
        
        migrate_back "${VMID}" "${SRC_IP}" "${DST_NODE}" "${IS_CT}" "${DST_IDX}" || {
            echo "❌ Back-migration failed for ${IS_CT} ${VMID}"
            echo "It remains on ${SRC_NAME} with local-lvm storage"
            exit 1
        }
    done
done

# ---------------------------------------------------------------
# Step 3: Update VM storage references
# ---------------------------------------------------------------
echo ""
echo "[3/4] Verifying VM storage references..."

for pair in "${REVERSE_PAIRS[@]}"; do
    DST_IDX="${pair##*:*}"
    DST_IP="${NODES[$DST_IDX]}"
    DST_NAME="${NODE_NAMES[$DST_IDX]}"
    
    VMS="${NODE_VMS[$DST_IDX]}"
    if [ -z "${VMS}" ]; then
        continue
    fi
    
    IFS=',' read -ra VM_LIST <<< "${VMS}"
    for VMID in "${VM_LIST[@]}"; do
        VMID=$(echo "${VMID}" | xargs)
        
        echo "[3/4] ${DST_NAME}: Checking storage for ${VMID}..."
        
        # For CTs
        if [ "${CT_VMS[$VMID]:-0}" = "1" ]; then
            CT_STORAGE=$(ssh ${SSH_OPTS} root@${DST_IP} "pct config ${VMID} 2>/dev/null | grep '^rootfs' | grep -oP '^rootfs: \K\S+' | cut -d, -f1" 2>/dev/null || echo "")
            echo "[3/4]   CT ${VMID} rootfs: ${CT_STORAGE}"
            if echo "${CT_STORAGE}" | grep -q "local-zfs"; then
                echo "[3/4]   ✅ CT ${VMID} on ZFS"
            else
                echo "[3/4]   ⚠️  CT ${VMID} NOT on ZFS (${CT_STORAGE})"
            fi
        else
            # For VMs
            VM_STORAGE=$(ssh ${SSH_OPTS} root@${DST_IP} "qm config ${VMID} 2>/dev/null | grep -E '^(scsi|virtio)[0-9]+:' | grep -oP 'local-zfs:\S+' | head -1" 2>/dev/null || echo "")
            if [ -n "${VM_STORAGE}" ]; then
                echo "[3/4]   ✅ VM ${VMID} on ZFS (${VM_STORAGE})"
            else
                ALL_DISKS=$(ssh ${SSH_OPTS} root@${DST_IP} "qm config ${VMID} 2>/dev/null | grep -E '^(scsi|virtio|ide|sata)[0-9]+:' | grep -oP '\S+:' | tr -d ':'" 2>/dev/null || echo "")
                echo "[3/4]   ⚠️  VM ${VMID} storage: ${ALL_DISKS}"
            fi
        fi
    done
done

# ---------------------------------------------------------------
# Step 4: Final verification
# ---------------------------------------------------------------
echo ""
echo "[4/4] Final verification of migrated VMs..."

for pair in "${MIGRATION_PAIRS[@]}"; do
    SRC_IDX="${pair%%:*}"
    # Original VMs should now be back on the source node
    IP="${NODES[$SRC_IDX]}"
    NAME="${NODE_NAMES[$SRC_IDX]}"
    
    VMS="${NODE_VMS[$SRC_IDX]}"
    if [ -z "${VMS}" ]; then
        continue
    fi
    
    echo "--- ${NAME} (${IP}) ---"
    echo "VMs:"
    ssh ${SSH_OPTS} root@${IP} "qm list --all 2>/dev/null | tail -n +2" || echo "  (none)"
    echo "CTs:"
    ssh ${SSH_OPTS} root@${IP} "pct list 2>/dev/null | tail -n +2" || echo "  (none)"
done

echo ""
echo "=== Task 2.5 completed ==="
echo ""
echo "⚠️  If any VM shows 'NOT on ZFS' above, you may need to move it manually:"
echo "   For VMs:  qm move-disk <vmid> <disk> local-zfs --delete"
echo "   For CTs:  pct migrate <vmid> <node> --storage local-zfs"
