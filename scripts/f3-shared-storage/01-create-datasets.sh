#!/bin/bash
# ================================================================
# 01-create-datasets.sh — Task T-04: Create mirror pool + datasets
# ================================================================
# Creates the shared-zfs mirror pool and all 6 datasets.
#
# Prerequisites:
#   1. T-01 (PBS backup) — completed and verified
#   2. T-07 (VMs migrated) — no VMs/CTs running on pve-desa03
#   3. T-08 (disks cleaned) — sda partitions destroyed, sdc LVM removed
#   4. Run on pve-desa03 as root
#
# This script is IDEMPOTENT. Safe to run multiple times.
# If the pool already exists, it skips creation and only
# verifies/creates datasets.
# ================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-env.sh"

echo "=== Task T-04: Create ZFS mirror pool + datasets ==="
echo ""

# ---------------------------------------------------------------
# Prerequisite check: running on pve-desa03
# ---------------------------------------------------------------
echo "[1/8] Verifying execution context..."

CURRENT_HOST=$(hostname -s 2>/dev/null || echo "unknown")
if [ "${CURRENT_HOST}" != "${SHARED_NODE_NAME}" ]; then
    echo "❌ This script must run on ${SHARED_NODE_NAME} (${SHARED_NODE_IP})."
    echo "   Current host: ${CURRENT_HOST}"
    echo ""
    echo "   If running remotely from a management workstation, execute:"
    echo "   ssh root@${SHARED_NODE_IP} \"bash -s\" < \${SCRIPT_DIR}/01-create-datasets.sh"
    exit 1
fi
echo "[1/8] ✅ Running on ${CURRENT_HOST}"

# ---------------------------------------------------------------
# Step 2: Verify no VMs/CTs remain on this node (T-08 prerequisite)
# ---------------------------------------------------------------
echo ""
echo "[2/8] Verifying no VMs/CTs remain on ${SHARED_NODE_NAME}..."

VM_COUNT=$(qm list --all 2>/dev/null | tail -n +2 | wc -l)
CT_COUNT=$(pct list 2>/dev/null | tail -n +2 | wc -l)

if [ "${VM_COUNT}" -gt 0 ] || [ "${CT_COUNT}" -gt 0 ]; then
    echo "❌ ${VM_COUNT} VM(s) and ${CT_COUNT} CT(s) still on this node."
    echo "   Run T-07 (migrate VMs to pve-desa02) first."
    echo "   Remaining:"
    qm list --all 2>/dev/null
    pct list 2>/dev/null
    exit 1
fi
echo "[2/8] ✅ No VMs/CTs — safe to destroy storage"

# ---------------------------------------------------------------
# Step 3: Destroy LVM vm-storage VG on sdc (T-08)
# ---------------------------------------------------------------
echo ""
echo "[3/8] Destroying LVM vm-storage on /dev/sdc..."

if vgs vm-storage &>/dev/null; then
    echo "[3/8] Removing vm-storage/data thin pool..."
    lvremove -f vm-storage/data 2>/dev/null || true
    echo "[3/8] Removing VG vm-storage..."
    vgremove -f vm-storage 2>/dev/null || true
    # Clean up PV label if any remains
    pvs --noheadings -o pv_name 2>/dev/null | grep -q vm-storage && pvremove -f /dev/sdc1 2>/dev/null || true
    echo "[3/8] ✅ vm-storage destroyed"
else
    echo "[3/8] ⏭️  No vm-storage VG found — already clean"
fi

# ---------------------------------------------------------------
# Step 4: Destroy partitions on sdc
# ---------------------------------------------------------------
echo ""
echo "[4/8] Cleaning /dev/sdc partition table..."

if blkid /dev/sdc &>/dev/null || sfdisk -d /dev/sdc &>/dev/null 2>&1; then
    echo "[4/8] Wiping /dev/sdc..."
    sgdisk -Z /dev/sdc
    wipefs -a /dev/sdc
    echo "[4/8] ✅ /dev/sdc cleaned"
else
    echo "[4/8] ⏭️  /dev/sdc already clean — no partition table found"
fi

# ---------------------------------------------------------------
# Step 5: Backup existing NFS data + stop NFS + clean sda (T-08)
# ---------------------------------------------------------------
echo ""
echo "[5/8] Backing up NFS exports and cleaning /dev/sda..."

# Backup current /etc/exports if not already backed up
EXPORTS_BACKUP="/etc/exports.bak.$(date +%Y%m%d)"
if [ -f /etc/exports ] && [ ! -f "${EXPORTS_BACKUP}" ]; then
    cp /etc/exports "${EXPORTS_BACKUP}"
    echo "[5/8] ✅ /etc/exports backed up to ${EXPORTS_BACKUP}"
fi

# Check if sda has partitions
if sfdisk -d /dev/sda &>/dev/null 2>&1 && [ "$(sfdisk -d /dev/sda 2>/dev/null | grep -c 'start=')" -gt 0 ]; then
    echo "[5/8] Stopping NFS services..."
    systemctl stop nfs-server nfs-kernel-server 2>/dev/null || true
    
    # Unmount any existing NFS mount points
    umount -l /mnt/nfs-storage 2>/dev/null || true
    umount -l /mnt/iso-storage 2>/dev/null || true
    
    echo "[5/8] Destroying partitions on /dev/sda..."
    sgdisk -Z /dev/sda
    wipefs -a /dev/sda
    partprobe /dev/sda
    echo "[5/8] ✅ /dev/sda cleaned"
else
    echo "[5/8] ⏭️  /dev/sda already has no partitions — skipping"
fi

# ---------------------------------------------------------------
# Step 6: Create ZFS mirror pool (T-04)
# ---------------------------------------------------------------
echo ""
echo "[6/8] Creating zpool ${SHARED_POOL}..."

# Check if pool already exists
if zpool list -H -o name 2>/dev/null | grep -q "^${SHARED_POOL}$"; then
    POOL_HEALTH=$(zpool list -H -o health "${SHARED_POOL}" 2>/dev/null)
    echo "[6/8] ⏭️  Pool ${SHARED_POOL} already exists (health: ${POOL_HEALTH})"
    
    # Verify it's a mirror
    VDEV_TYPE=$(zpool status "${SHARED_POOL}" 2>/dev/null | grep -E '^\s+mirror|^\s+raidz' | awk '{print $1}')
    if [ "${VDEV_TYPE}" != "mirror" ] && [ "${VDEV_TYPE}" != "raidz" ]; then
        echo "⚠️  Pool ${SHARED_POOL} is NOT a mirror/raidz vdev. Current config:"
        zpool status "${SHARED_POOL}"
        echo "   If this is a single-disk pool from a previous attempt,"
        echo "   destroy it first with: zpool destroy ${SHARED_POOL}"
        echo "   Then re-run this script."
        exit 1
    fi
    echo "[6/8] ✅ Pool is a mirror — continuing"
else
    echo "[6/8] Creating mirror pool with /dev/sda + /dev/sdc..."
    
    # Verify both disks exist
    for disk in "${SHARED_POOL_DISKS[@]}"; do
        if [ ! -b "${disk}" ]; then
            echo "❌ Block device ${disk} not found!"
            exit 1
        fi
    done
    
    zpool create -f \
        -o ashift=12 \
        -O compression=zstd \
        -O atime=off \
        -O xattr=sa \
        "${SHARED_POOL}" \
        mirror "${SHARED_POOL_DISKS[@]}"
    
    echo "[6/8] ✅ Pool ${SHARED_POOL} created"
    zpool status "${SHARED_POOL}" | head -10
fi

# ---------------------------------------------------------------
# Step 7: Create datasets (T-04)
# ---------------------------------------------------------------
echo ""
echo "[7/8] Creating datasets..."

for dataset_def in "${DATASETS[@]}"; do
    # Parse: NAME:MOUNTPOINT:RECORDSIZE:QUOTA
    DS_NAME="${dataset_def%%:*}"
    REMAINDER="${dataset_def#*:}"
    DS_MOUNT="${REMAINDER%%:*}"
    REMAINDER2="${REMAINDER#*:}"
    DS_RECORDSIZE="${REMAINDER2%%:*}"
    DS_QUOTA="${REMAINDER2#*:}"
    
    DS_FULL="${SHARED_POOL}/${DS_NAME}"
    
    echo "--- Dataset: ${DS_FULL} ---"
    
    # Check if dataset already exists
    if zfs list -H -o name 2>/dev/null | grep -q "^${DS_FULL}$"; then
        echo "  ⏭️  ${DS_FULL} already exists — verifying properties"
    else
        echo "  Creating ${DS_FULL}..."
        zfs create "${DS_FULL}"
    fi
    
    # Apply properties idempotently
    zfs set compression=zstd "${DS_FULL}"
    zfs set atime=off "${DS_FULL}"
    zfs set xattr=sa "${DS_FULL}"
    
    # Set recordsize if specified
    if [ -n "${DS_RECORDSIZE}" ] && [ "${DS_RECORDSIZE}" != "0" ]; then
        CURRENT_RS=$(zfs get recordsize -H -o value "${DS_FULL}" 2>/dev/null || echo "")
        if [ "${CURRENT_RS}" != "${DS_RECORDSIZE}" ]; then
            zfs set recordsize="${DS_RECORDSIZE}" "${DS_FULL}"
            echo "  recordsize → ${DS_RECORDSIZE}"
        fi
    fi
    
    # Set quota if specified
    if [ -n "${DS_QUOTA}" ] && [ "${DS_QUOTA}" != "0" ] && [ "${DS_QUOTA}" != "G" ]; then
        CURRENT_QUOTA=$(zfs get quota -H -o value "${DS_FULL}" 2>/dev/null || echo "none")
        EXPECTED_QUOTA="${DS_QUOTA}"
        if [ "${CURRENT_QUOTA}" != "${EXPECTED_QUOTA}" ]; then
            zfs set quota="${EXPECTED_QUOTA}" "${DS_FULL}"
            echo "  quota → ${EXPECTED_QUOTA}"
        fi
    fi
    
    # Show properties
    zfs get compression,atime,recordsize,quota -H "${DS_FULL}" 2>/dev/null | \
        awk '{printf "  %s = %s\n", $2, $3}'
done

# ---------------------------------------------------------------
# Step 8: Verify everything
# ---------------------------------------------------------------
echo ""
echo "[8/8] Verification..."
echo ""

echo "--- Pool status ---"
zpool status "${SHARED_POOL}"
echo ""

echo "--- All datasets ---"
zfs list -r "${SHARED_POOL}"
echo ""

echo "=== Task T-04 completed ==="
echo ""
echo "✅ Pool: ${SHARED_POOL} (mirror, ashift=12)"
echo "✅ Datasets: $(zfs list -H -r -o name "${SHARED_POOL}" 2>/dev/null | grep -c "${SHARED_POOL}/") datasets created"
echo "✅ Compression: zstd | atime: off | xattr: sa"
echo ""
echo "Next step: Run 02-configure-nfs.sh to configure NFS exports"
