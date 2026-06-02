#!/bin/bash
# ================================================================
# 04-configure-zfs.sh — Tasks 2.3 + 2.4: Configure ZFS properties
# ================================================================
# Applies the following to all nodes:
#   - compression=zstd on pool
#   - atime=off on pool
#   - zfs_arc_max = 50% of RAM in /etc/modprobe.d/zfs.conf
# ================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-env.sh"

echo "=== Tasks 2.3 + 2.4: Configure ZFS (compression, atime, ARC) ==="
echo ""

# ---------------------------------------------------------------
# Step 1: Set compression=zstd and atime=off on all pools
# ---------------------------------------------------------------
echo "[1/4] Setting compression=zstd and atime=off on all pools..."

for i in "${!NODES[@]}"; do
    IP="${NODES[$i]}"
    NAME="${NODE_NAMES[$i]}"
    
    echo "--- ${NAME} (${IP}) ---"
    
    # Check pool exists
    POOL_EXISTS=$(ssh ${SSH_OPTS} root@${IP} "zpool list -H -o name 2>/dev/null | grep -c '^${ZFS_POOL_NAME}$'" 2>/dev/null || echo 0)
    if [ "${POOL_EXISTS}" -eq 0 ]; then
        echo "❌ Pool ${ZFS_POOL_NAME} not found on ${NAME}. Run 03-create-zpool.sh first."
        exit 1
    fi
    
    # Check current settings
    CURRENT_COMPRESSION=$(ssh ${SSH_OPTS} root@${IP} "zfs get compression -H -o value ${ZFS_POOL_NAME} 2>/dev/null || echo 'unknown'")
    CURRENT_ATIME=$(ssh ${SSH_OPTS} root@${IP} "zfs get atime -H -o value ${ZFS_POOL_NAME} 2>/dev/null || echo 'unknown'")
    echo "  Current: compression=${CURRENT_COMPRESSION}, atime=${CURRENT_ATIME}"
    
    # Apply settings
    if [ "${CURRENT_COMPRESSION}" != "zstd" ]; then
        echo "[1/4] Setting compression=zstd on ${ZFS_POOL_NAME}..."
        ssh ${SSH_OPTS} root@${IP} "zfs set compression=zstd ${ZFS_POOL_NAME}"
    fi
    
    if [ "${CURRENT_ATIME}" != "off" ]; then
        echo "[1/4] Setting atime=off on ${ZFS_POOL_NAME}..."
        ssh ${SSH_OPTS} root@${IP} "zfs set atime=off ${ZFS_POOL_NAME}"
    fi
    
    # Verify
    NEW_COMPRESSION=$(ssh ${SSH_OPTS} root@${IP} "zfs get compression -H -o value ${ZFS_POOL_NAME}")
    NEW_ATIME=$(ssh ${SSH_OPTS} root@${IP} "zfs get atime -H -o value ${ZFS_POOL_NAME}")
    echo "  New: compression=${NEW_COMPRESSION}, atime=${NEW_ATIME}"
    
    if [ "${NEW_COMPRESSION}" = "zstd" ] && [ "${NEW_ATIME}" = "off" ]; then
        echo "[1/4] ✅ ${NAME}: ZFS properties configured correctly"
    else
        echo "[1/4] ❌ ${NAME}: Properties not set correctly"
        exit 1
    fi
done

# ---------------------------------------------------------------
# Step 2: Set ashift and other pool-level properties
# ---------------------------------------------------------------
echo ""
echo "[2/4] Verifying pool-level properties..."

for i in "${!NODES[@]}"; do
    IP="${NODES[$i]}"
    NAME="${NODE_NAMES[$i]}"
    
    ASHIFT=$(ssh ${SSH_OPTS} root@${IP} "zpool get ashift -H -o value ${ZFS_POOL_NAME} 2>/dev/null || echo 'unknown'")
    echo "  ${NAME}: ashift=${ASHIFT}"
done

# ---------------------------------------------------------------
# Step 3: Configure zfs_arc_max
# ---------------------------------------------------------------
echo ""
echo "[3/4] Configuring zfs_arc_max on all nodes..."

for i in "${!NODES[@]}"; do
    IP="${NODES[$i]}"
    NAME="${NODE_NAMES[$i]}"
    RAM_GB="${NODE_RAM_GB[$i]}"
    
    # Calculate ARC size: 50% of RAM in bytes
    ARC_BYTES=$((RAM_GB * 1024 * 1024 * 1024 * ARC_PERCENT / 100))
    echo "--- ${NAME} (${IP}) — ${RAM_GB}GB RAM → ARC: ${ARC_BYTES} bytes ($((ARC_BYTES / 1024 / 1024 / 1024))GB) ---"
    
    # Check if already configured
    CURRENT_ARC=$(ssh ${SSH_OPTS} root@${IP} "cat /sys/module/zfs/parameters/zfs_arc_max 2>/dev/null || echo 'N/A'")
    echo "  Current zfs_arc_max: ${CURRENT_ARC}"
    
    # Create /etc/modprobe.d/zfs.conf
    echo "[3/4] Writing /etc/modprobe.d/zfs.conf with zfs_arc_max=${ARC_BYTES}..."
    ssh ${SSH_OPTS} root@${IP} "echo 'options zfs zfs_arc_max=${ARC_BYTES}' > /etc/modprobe.d/zfs.conf"
    
    # Also set it runtime (immediate effect)
    echo "[3/4] Applying runtime value (immediate, non-persistent)..."
    ssh ${SSH_OPTS} root@${IP} "echo ${ARC_BYTES} 2>/dev/null > /sys/module/zfs/parameters/zfs_arc_max" 2>/dev/null || {
        echo "[3/4] ⚠️  Runtime change requires root — will apply after reboot"
        echo "[3/4] The /etc/modprobe.d/zfs.conf will take effect on next reboot"
    }
    
    # Verify file was written
    FILE_CONTENT=$(ssh ${SSH_OPTS} root@${IP} "cat /etc/modprobe.d/zfs.conf 2>/dev/null || echo 'NOT_FOUND'")
    if [ "${FILE_CONTENT}" != "NOT_FOUND" ]; then
        echo "[3/4] ✅ ${NAME}: zfs_arc_max configured (${FILE_CONTENT})"
    else
        echo "[3/4] ❌ ${NAME}: Failed to write /etc/modprobe.d/zfs.conf"
        exit 1
    fi
done

# ---------------------------------------------------------------
# Step 4: Add ZFS to storage.cfg (Proxmox integration)
# ---------------------------------------------------------------
echo ""
echo "[4/4] Adding ZFS storage to /etc/pve/storage.cfg..."

FIRST_NODE="${NODES[0]}"

# Check if zfspool entry already exists
ZFS_STORAGE_EXISTS=$(ssh ${SSH_OPTS} root@${FIRST_NODE} "grep -c '^zfspool: local-zfs' /etc/pve/storage.cfg 2>/dev/null || echo 0")
if [ "${ZFS_STORAGE_EXISTS}" -gt 0 ]; then
    echo "[4/4] ⏭️  ZFS storage 'local-zfs' already in storage.cfg"
else
    echo "[4/4] Adding zfspool entry to storage.cfg..."
    ssh ${SSH_OPTS} root@${FIRST_NODE} bash -s << "REMOTE"
        set -euo pipefail
        cat >> /etc/pve/storage.cfg << EOF

zfspool: local-zfs
	pool local-zfs
	content images,rootdir
	sparse 1

EOF
        echo "storage.cfg updated. New entry:"
        grep -A 4 "^zfspool: local-zfs" /etc/pve/storage.cfg
REMOTE
    echo "[4/4] ✅ ZFS storage added to storage.cfg"
fi

# Also update local-lvm to be restricted to nodes that still have it
echo "[4/4] Updating local-lvm to restrict to nodes with LVM data pool..."
LOCAL_LVM_NODES=$(ssh ${SSH_OPTS} root@${FIRST_NODE} "grep -A5 '^lvmthin: local-lvm' /etc/pve/storage.cfg | grep 'nodes' || echo ''")
if [ -z "${LOCAL_LVM_NODES}" ]; then
    # Add nodes restriction to local-lvm
    # pve-desa02 and pve-desa03 still have LVM thin pools
    ssh ${SSH_OPTS} root@${FIRST_NODE} bash -s << 'REMOTE'
        set -euo pipefail
        # Insert nodes line after the vgname line in local-lvm section
        sed -i '/^lvmthin: local-lvm$/,/^[a-z]/ s|^\(	vgname pve\)$|\1\n\tnodes pve-desa02,pve-desa03|' /etc/pve/storage.cfg
        echo "Updated local-lvm section:"
        grep -A6 '^lvmthin: local-lvm' /etc/pve/storage.cfg
REMOTE
    echo "[4/4] ✅ local-lvm restricted to pve-desa02,pve-desa03"
fi

echo ""
echo "=== Tasks 2.3 + 2.4 completed ==="
echo ""
echo "⚠️  NOTE: zfs_arc_max changes require a reboot to take full effect."
echo "   The runtime value was set if possible, but /etc/modprobe.d/zfs.conf"
echo "   will apply on next boot."
echo "   To verify after reboot: cat /sys/module/zfs/parameters/zfs_arc_max"
