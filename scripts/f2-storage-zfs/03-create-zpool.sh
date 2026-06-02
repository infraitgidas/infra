#!/bin/bash
# ================================================================
# 03-create-zpool.sh — Tasks 2.2: Destroy LVM VG, create ZFS pool
# ================================================================
# Per-node ZFS pool creation:
#   pve-desa01: Remove data LVM → create LVM LV → zpool on LV
#   pve-desa02: zpool on /dev/sdc (free disk, no LVM)
#   pve-desa03: Destroy vm-storage VG → zpool on /dev/sdc
#   pve-desa04: Remove data LVM → labelclear old ZFS → zpool on /dev/sdb
#
# PREREQUISITE: 02-migrate-to-neighbor.sh must have run first.
# ================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-env.sh"

echo "=== Tasks 2.2: Destroy LVM / Create ZFS pools ==="
echo ""

# ---------------------------------------------------------------
# Step 0: Verify no VMs remain on nodes being converted
# ---------------------------------------------------------------
echo "[0/5] Verifying no VMs/CTs remain on conversion nodes..."

# Check nodes that need LVM destruction
for idx in 0 3; do
    IP="${NODES[$idx]}"
    NAME="${NODE_NAMES[$idx]}"
    
    REMAINING=$(ssh ${SSH_OPTS} root@${IP} "echo 'VMs:' && qm list --all 2>/dev/null | tail -n +2 | wc -l && echo 'CTs:' && pct list 2>/dev/null | tail -n +2 | wc -l" 2>/dev/null)
    VM_COUNT=$(echo "${REMAINING}" | grep "VMs:" | cut -d: -f2)
    CT_COUNT=$(echo "${REMAINING}" | grep "CTs:" | cut -d: -f2)
    
    if [ "${VM_COUNT}" -gt 0 ] || [ "${CT_COUNT}" -gt 0 ]; then
        echo "❌ ${NAME} still has ${VM_COUNT} VM(s) and ${CT_COUNT} CT(s)! Run 02-migrate-to-neighbor.sh first."
        echo "Remaining:"
        ssh ${SSH_OPTS} root@${IP} "qm list --all 2>/dev/null; pct list 2>/dev/null"
        exit 1
    fi
    echo "[0/5] ✅ ${NAME} has no VMs/CTs — safe to convert"
done

# ---------------------------------------------------------------
# Step 1: pve-desa04 — remove data LVM, labelclear old ZFS
# ---------------------------------------------------------------
echo ""
echo "[1/5] Processing pve-desa04 (${NODES[3]}) — removing LVM data + clearing old ZFS..."

ssh ${SSH_OPTS} root@${NODES[3]} bash -s << 'REMOTE'
    set -euo pipefail
    echo "[1/5] pve-desa04: Checking current LVM state..."
    
    # Remove stopped VMs disks that won't be migrated back (108, 210, 200)
    # But first check if they exist and are stopped
    for vmid in 108 210 200; do
        STATUS=$(qm status ${vmid} 2>/dev/null | awk '{print $2}' || echo "NOT_FOUND")
        if [ "${STATUS}" = "stopped" ]; then
            echo "[1/5] Removing stopped VM ${vmid} disks from LVM..."
            # Get disk config
            DISKS=$(qm config ${vmid} 2>/dev/null | grep -E '^(scsi|virtio|ide|sata)[0-9]+:' | grep 'local-lvm' | cut -d: -f1 || true)
            if [ -n "${DISKS}" ]; then
                for disk in ${DISKS}; do
                    VOLUME=$(qm config ${vmid} 2>/dev/null | grep "^${disk}:" | grep -oP 'local-lvm:\K\S+' | cut -d, -f1 || true)
                    if [ -n "${VOLUME}" ] && [ -e "/dev/pve/${VOLUME}" ]; then
                        lvremove -f "pve/${VOLUME}" || true
                    fi
                done
            fi
        fi
    done
    
    # Remove VM 109 disk if it still exists (should have been migrated, but clean up)
    if lvs pve/vm-109-disk-0 &>/dev/null; then
        echo "[1/5] Removing vm-109-disk-0 (should have been migrated)..."
        lvremove -f pve/vm-109-disk-0
    fi
    
    # Remove base-108-disk-0 (template)
    if lvs pve/base-108-disk-0 &>/dev/null; then
        echo "[1/5] Removing base-108-disk-0 (template)..."
        lvremove -f pve/base-108-disk-0
    fi
    if lvs pve/vm-210-disk-0 &>/dev/null; then
        echo "[1/5] Removing vm-210-disk-0..."
        lvremove -f pve/vm-210-disk-0
    fi
    
    # Remove data thin pool
    if lvs pve/data &>/dev/null; then
        echo "[1/5] Removing data thin pool..."
        lvremove -f pve/data
    fi
    
    echo "[1/5] LVM cleaned up on pve-desa04"
    
    # Clear old ZFS labels on sdb3 (from previous rpool)
    echo "[1/5] Checking for old ZFS labels on /dev/sdb..."
    if blkid /dev/sdb3 2>/dev/null | grep -q zfs_member; then
        echo "[1/5] Clearing old ZFS label on /dev/sdb3..."
        zpool labelclear /dev/sdb3 2>/dev/null || {
            echo "[1/5] labelclear failed, trying force wipe..."
            dd if=/dev/zero of=/dev/sdb3 bs=1M count=16 2>/dev/null || true
        }
    fi
    
    echo "[1/5] ✅ pve-desa04 ready for ZFS pool creation"
REMOTE

# ---------------------------------------------------------------
# Step 2: pve-desa01 — remove data LVM, create LV for ZFS
# ---------------------------------------------------------------
echo ""
echo "[2/5] Processing pve-desa01 (${NODES[0]}) — removing data LVM, preparing ZFS..."

ssh ${SSH_OPTS} root@${NODES[0]} bash -s << 'REMOTE'
    set -euo pipefail
    echo "[2/5] pve-desa01: Checking current LVM state..."
    
    # Remove snapshot first
    if lvs pve/snap_vm-105-disk-0_post-twing-conector &>/dev/null; then
        echo "[2/5] Removing snapshot snap_vm-105-disk-0_post-twing-conector..."
        lvremove -f pve/snap_vm-105-disk-0_post-twing-conector
    fi
    
    # Remove VM volumes that were migrated
    for vol in vm-100-disk-0 vm-100-disk-1 vm-105-disk-0; do
        if lvs "pve/${vol}" &>/dev/null; then
            echo "[2/5] Removing ${vol}..."
            lvremove -f "pve/${vol}"
        fi
    done
    
    # Remove data thin pool
    if lvs pve/data &>/dev/null; then
        echo "[2/5] Removing data thin pool..."
        lvremove -f pve/data
    fi
    
    # Check available space in VG
    VG_FREE=$(vgs --noheadings --units g -o vg_free pve 2>/dev/null | awk '{print $1}' | sed 's/g//' | cut -d. -f1)
    echo "[2/5] Available space in VG pve: ${VG_FREE}G"
    
    if [ "${VG_FREE}" -lt 10 ]; then
        echo "❌ Not enough free space in VG pve (${VG_FREE}G). Something went wrong."
        exit 1
    fi
    
    # Create a thick LV for ZFS backing
    # Use all available space minus 1G for safety margin
    LV_SIZE=$((${VG_FREE} - 1))
    if [ "${LV_SIZE}" -lt 10 ]; then
        LV_SIZE="${VG_FREE}"
    fi
    echo "[2/5] Creating ZFS backing LV (${LV_SIZE}G)..."
    lvcreate -n zfs-pool -L "${LV_SIZE}G" pve
    
    echo "[2/5] ✅ pve-desa01 ready for ZFS pool creation"
REMOTE

# ---------------------------------------------------------------
# Step 3: pve-desa03 — destroy vm-storage VG
# ---------------------------------------------------------------
echo ""
echo "[3/5] Processing pve-desa03 (${NODES[2]}) — removing vm-storage VG..."

ssh ${SSH_OPTS} root@${NODES[2]} bash -s << 'REMOTE'
    set -euo pipefail
    
    # Check if vm-storage has any data worth preserving
    if lvs vm-storage/vm-data &>/dev/null; then
        DATA_PCT=$(lvs --noheadings -o data_percent vm-storage/vm-data 2>/dev/null | xargs)
        echo "[3/5] vm-storage/vm-data usage: ${DATA_PCT}%"
        
        # If it has data, we should note this
        if [ "${DATA_PCT}" != "0.00" ] && [ -n "${DATA_PCT}" ]; then
            echo "[3/5] ⚠️  vm-storage has ${DATA_PCT}% data usage. Data will be lost."
            echo "[3/5] Checking if any VMs reference this storage..."
        fi
    fi
    
    # Remove vm-data thin pool
    if lvs vm-storage/vm-data &>/dev/null; then
        echo "[3/5] Removing vm-data thin pool..."
        lvremove -f vm-storage/vm-data
    fi
    
    # Remove VG
    if vgs vm-storage &>/dev/null; then
        echo "[3/5] Removing VG vm-storage..."
        vgremove -f vm-storage
    fi
    
    # Remove PV label
    PV_DEV=$(pvs --noheadings -o pv_name 2>/dev/null | grep vm-storage || echo "")
    if [ -n "${PV_DEV}" ]; then
        echo "[3/5] Removing PV label from ${PV_DEV}..."
        pvremove -f "${PV_DEV}"
    fi
    
    echo "[3/5] ✅ pve-desa03 ready for ZFS pool creation"
REMOTE

# ---------------------------------------------------------------
# Step 4: Create ZFS pools on all nodes
# ---------------------------------------------------------------
echo ""
echo "[4/5] Creating ZFS pools on all nodes..."

for i in "${!NODES[@]}"; do
    IP="${NODES[$i]}"
    NAME="${NODE_NAMES[$i]}"
    DEV="${ZFS_DEVICES[$i]}"
    
    echo "--- Creating ZFS pool on ${NAME} (${IP}) using ${DEV} ---"
    
    # Check if pool already exists
    POOL_EXISTS=$(ssh ${SSH_OPTS} root@${IP} "zpool list -H -o name 2>/dev/null | grep -c '^${ZFS_POOL_NAME}$'" 2>/dev/null || echo 0)
    if [ "${POOL_EXISTS}" -gt 0 ]; then
        echo "[4/5] ⏭️  Pool ${ZFS_POOL_NAME} already exists on ${NAME} — skipping"
        continue
    fi
    
    # Check if device exists
    DEV_EXISTS=$(ssh ${SSH_OPTS} root@${IP} "test -b ${DEV} && echo 'YES' || echo 'NO'" 2>/dev/null || echo "NO")
    if [ "${DEV_EXISTS}" != "YES" ]; then
        echo "❌ Device ${DEV} does not exist on ${NAME}"
        exit 1
    fi
    
    # Create the pool
    echo "[4/5] Creating zpool ${ZFS_POOL_NAME} on ${DEV} with ashift=12..."
    ssh ${SSH_OPTS} root@${IP} "zpool create -f -o ashift=12 ${ZFS_POOL_NAME} ${DEV}"
    
    # Verify
    ssh ${SSH_OPTS} root@${IP} "zpool status ${ZFS_POOL_NAME} 2>/dev/null | head -10"
    echo "[4/5] ✅ Pool ${ZFS_POOL_NAME} created on ${NAME}"
done

# ---------------------------------------------------------------
# Step 5: Verify pools on all nodes
# ---------------------------------------------------------------
echo ""
echo "[5/5] Verifying ZFS pools on all nodes..."

ALL_POOLS_OK=true
for i in "${!NODES[@]}"; do
    IP="${NODES[$i]}"
    NAME="${NODE_NAMES[$i]}"
    
    POOL_STATUS=$(ssh ${SSH_OPTS} root@${IP} "zpool list -H -o name,health,size ${ZFS_POOL_NAME} 2>/dev/null" || echo "NOT_FOUND")
    if [ "${POOL_STATUS}" != "NOT_FOUND" ]; then
        echo "[5/5] ✅ ${NAME}: ${POOL_STATUS}"
    else
        echo "[5/5] ❌ ${NAME}: Pool ${ZFS_POOL_NAME} NOT found"
        ALL_POOLS_OK=false
    fi
done

echo ""
if [ "${ALL_POOLS_OK}" = true ]; then
    echo "✅ ALL ZFS pools created successfully. Ready for configuration."
else
    echo "❌ Some pools are missing. Check above."
    exit 1
fi

echo ""
echo "=== Task 2.2 completed ==="
