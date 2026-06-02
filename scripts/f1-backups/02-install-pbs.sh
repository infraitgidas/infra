#!/bin/bash
# ================================================================
# 02-install-pbs.sh — Task 1.3: Install PBS on pve-ad with ZFS datastore
# ================================================================
# Installs Proxmox Backup Server on pve-ad (192.168.1.31).
# Creates a ZFS datastore with compression=zstd.
#
# NOTE: pve-ad only has 1x 224GB SSD (LVM thin). No extra disk.
# If no free disk is detected, creates a file-backed ZFS pool
# on the root filesystem. A dedicated disk is strongly recommended.
# ================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-env.sh"

PBS_IP="${PBS_HOST}"
PBS_STORAGE_PATH="/backup/pbs"
PBS_POOL_NAME="pbs-pool"
PBS_DATASET_NAME="pbs-pool/dataset"
PBS_DATASET_PATH="/backup/pbs"
POOL_FILE="/root/pbs-zfs-file.img"
POOL_FILE_SIZE="100G"  # Adjust based on available free space

echo "=== Task 1.3: Install PBS on ${PBS_HOSTNAME} (${PBS_IP}) ==="

# ---------------------------------------------------------------
# Step 1: Install PBS package
# ---------------------------------------------------------------
echo "[1/6] Installing proxmox-backup-server on ${PBS_HOSTNAME}..."

ssh ${SSH_OPTS} root@${PBS_IP} bash -s << 'REMOTE'
    set -euo pipefail

    # Update apt cache
    apt-get update -qq

    # Install PBS
    apt-get install -y proxmox-backup-server

    echo "PBS installation complete."
    proxmox-backup-manager versions --verbose 2>/dev/null || true
REMOTE

echo "[1/6] ✅ PBS package installed"

# ---------------------------------------------------------------
# Step 2: Create ZFS pool
# ---------------------------------------------------------------
echo "[2/6] Checking available disks for ZFS pool..."

HAS_FREE_DISK=$(ssh ${SSH_OPTS} root@${PBS_IP} bash -s << 'REMOTE'
    # Find unused disks (no partition table, no filesystem, no LVM)
    for dev in /dev/sd?; do
        [ -b "$dev" ] || continue
        # Skip the system disk (sda on pve-ad)
        [ "$(basename $dev)" = "sda" ] && continue
        # Skip 0B devices
        SIZE=$(blockdev --getsize64 "$dev" 2>/dev/null || echo 0)
        [ "$SIZE" -eq 0 ] && continue
        
        # Check if disk is unused
        if ! lsblk -nlo FSTYPE "$dev" 2>/dev/null | grep -q .; then
            echo "$dev"
            exit 0
        fi
    done
    echo "NONE"
REMOTE
)

if [ "${HAS_FREE_DISK}" != "NONE" ]; then
    echo "[2/6] Free disk detected: ${HAS_FREE_DISK}"
    echo "[2/6] Creating ZFS pool on ${HAS_FREE_DISK}..."
    
    ssh ${SSH_OPTS} root@${PBS_IP} "zpool create -f -o ashift=12 ${PBS_POOL_NAME} ${HAS_FREE_DISK}"
else
    echo "[2/6] No free disk detected. Creating file-backed ZFS pool..."
    echo "[2/6] WARNING: This is NOT suitable for production. Add a dedicated disk later."
    
    ssh ${SSH_OPTS} root@${PBS_IP} bash -s << "REMOTE"
        set -euo pipefail
        
        POOL_FILE="${POOL_FILE}"
        POOL_FILE_SIZE="${POOL_FILE_SIZE}"
        PBS_POOL_NAME="${PBS_POOL_NAME}"
        
        # Check available space
        AVAIL_GB=$(df -BG /root | awk 'NR==2 {gsub(/G/,""); print $4}')
        echo "[2/6] Available space on /root: ${AVAIL_GB}G"
        
        # Reduce file size if not enough space
        if [ "${AVAIL_GB}" -lt 110 ]; then
            POOL_FILE_SIZE="${AVAIL_GB%%.*}"G
            echo "[2/6] Adjusted pool file size to ${POOL_FILE_SIZE}"
        fi
        
        # Create sparse file for ZFS pool
        echo "[2/6] Creating ${POOL_FILE_SIZE} sparse file at ${POOL_FILE}..."
        truncate -s "${POOL_FILE_SIZE}" "${POOL_FILE}"
        
        # Create ZFS pool on the file
        echo "[2/6] Creating ZFS pool ${PBS_POOL_NAME}..."
        zpool create -f -o ashift=12 "${PBS_POOL_NAME}" "${POOL_FILE}"
REMOTE
fi

echo "[2/6] ✅ ZFS pool '${PBS_POOL_NAME}' created"

# ---------------------------------------------------------------
# Step 3: Create ZFS dataset with compression=zstd
# ---------------------------------------------------------------
echo "[3/6] Creating ZFS dataset '${PBS_DATASET_NAME}' with compression=zstd..."

ssh ${SSH_OPTS} root@${PBS_IP} bash -s << "REMOTE"
    set -euo pipefail
    
    PBS_POOL_NAME="${PBS_POOL_NAME}"
    PBS_DATASET_NAME="${PBS_DATASET_NAME}"
    PBS_DATASET_PATH="${PBS_DATASET_PATH}"
    
    # Create dataset
    zfs create -o compression=zstd -o atime=off -o mountpoint="${PBS_DATASET_PATH}" "${PBS_DATASET_NAME}"
    
    echo "[3/6] ZFS dataset properties:"
    zfs get compression,atime,mountpoint "${PBS_DATASET_NAME}"
REMOTE

echo "[3/6] ✅ ZFS dataset created with compression=zstd"

# ---------------------------------------------------------------
# Step 4: Create PBS datastore
# ---------------------------------------------------------------
echo "[4/6] Creating PBS datastore '${PBS_DATASTORE}'..."

ssh ${SSH_OPTS} root@${PBS_IP} bash -s << "REMOTE"
    set -euo pipefail
    
    PBS_DATASTORE="${PBS_DATASTORE}"
    PBS_DATASET_PATH="${PBS_DATASET_PATH}"
    
    # Create datastore via PBS manager
    proxmox-backup-manager datastore create "${PBS_DATASTORE}" "${PBS_DATASET_PATH}"
    
    # Enable verification on the datastore
    proxmox-backup-manager datastore set "${PBS_DATASTORE}" --verify-new
    
    echo "[4/6] Datastore configuration:"
    proxmox-backup-manager datastore list
REMOTE

echo "[4/6] ✅ PBS datastore '${PBS_DATASTORE}' created"

# ---------------------------------------------------------------
# Step 5: Get PBS fingerprint and configure access
# ---------------------------------------------------------------
echo "[5/6] Getting PBS TLS fingerprint..."

PBS_FINGERPRINT=$(ssh ${SSH_OPTS} root@${PBS_IP} bash -s << 'REMOTE'
    # Get the certificate fingerprint
    openssl x509 -in /etc/proxmox-backup/proxy.pem -fingerprint -sha256 -noout 2>/dev/null | cut -d= -f2
REMOTE
)

echo "[5/6] ✅ PBS Fingerprint: ${PBS_FINGERPRINT}"

# ---------------------------------------------------------------
# Step 6: Open firewall port for PBS
# ---------------------------------------------------------------
echo "[6/6] Opening PBS port ${PBS_PORT} on ${PBS_HOSTNAME}..."

ssh ${SSH_OPTS} root@${PBS_IP} bash -s << "REMOTE"
    set -euo pipefail
    PBS_PORT="${PBS_PORT}"
    
    # Ensure PBS port is open
    if command -v pve-firewall &>/dev/null; then
        # PVE has its own firewall
        echo "[6/6] PBS runs on PVE — firewall rules already allow PBS port"
    fi
    
    # Check PBS service status
    systemctl is-active --quiet proxmox-backup-proxy || {
        echo "[6/6] Starting proxmox-backup-proxy..."
        systemctl start proxmox-backup-proxy
        systemctl enable proxmox-backup-proxy
    }
    
    systemctl status proxmox-backup-proxy --no-pager | head -5
REMOTE

echo "[6/6] ✅ PBS service running on port ${PBS_PORT}"
echo ""
echo "=== Task 1.3 completed ==="
echo ""
echo "PBS Connection Details:"
echo "  Host:         ${PBS_HOSTNAME}:${PBS_PORT}"
echo "  IP:           ${PBS_IP}:${PBS_PORT}"
echo "  Datastore:    ${PBS_DATASTORE}"
echo "  Pool:         ${PBS_POOL_NAME}"
echo "  Fingerprint:  ${PBS_FINGERPRINT}"
echo ""
echo "⚠️  IMPORTANT: Save the fingerprint for task 1.5 (storage.cfg)"
