#!/bin/bash
# ================================================================
# 04-migrate-pve-desa03.sh — Phase 3: Full pve-desa03 migration
# ================================================================
# Orchestrates the complete migration of pve-desa03 from current
# state (sda partitioned NFS + sdc LVM vm-storage) to the target
# state (shared-zfs mirror pool).
#
# Tasks covered:
#   T-07: Migrate VMs/CTs from pve-desa03 → pve-desa02
#   T-08: Destroy vm-storage + clean sda/sdc (calls 01-create-datasets.sh)
#   T-09: Create pool + datasets (calls 01-create-datasets.sh)
#   T-10: Configure NFS + pvesm (calls 02-configure-nfs.sh)
#   T-11: Configure ARC
#
# PREREQUISITES:
#   - T-01 (PBS backup) completed and verified
#   - T-02 (survey) documented for rollback reference
#   - Run from a management workstation OR any cluster node
#   - Passwordless SSH root access to all nodes
#
# ⚠️  THIS SCRIPT PERFORMS DESTRUCTIVE OPERATIONS.
#     Have a rollback plan before running.
# ================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-env.sh"

echo "========================================================"
echo "  Phase 3: Migrate pve-desa03 to shared-zfs mirror"
echo "========================================================"
echo ""
echo "⚠️  WARNING: This script will DESTROY existing data on"
echo "   /dev/sda and /dev/sdc of ${SHARED_NODE_NAME}."
echo "   Ensure T-01 (PBS backup) completed successfully."
echo ""
echo "   Press Ctrl+C now to abort, or Enter to continue..."
read -r

# ---------------------------------------------------------------
# Step 1: T-07 — Migrate VMs/CTs from pve-desa03 to pve-desa02
# ---------------------------------------------------------------
echo ""
echo "=== T-07: Migrate VMs/CTs from pve-desa03 → pve-desa02 ==="
echo ""

# Check connectivity to both nodes
echo "[1/6] Checking node connectivity..."
ssh ${SSH_OPTS} root@${SHARED_NODE_IP} "hostname" >/dev/null 2>&1 || {
    echo "❌ Cannot reach ${SHARED_NODE_NAME} (${SHARED_NODE_IP})"
    exit 1
}
ssh ${SSH_OPTS} root@${DR_NODE_IP} "hostname" >/dev/null 2>&1 || {
    echo "❌ Cannot reach ${DR_NODE_NAME} (${DR_NODE_IP})"
    exit 1
}
echo "[1/6] ✅ Both nodes reachable"

# List VMs/CTs on pve-desa03
echo ""
echo "[2/6] Listing VMs/CTs on ${SHARED_NODE_NAME}..."

ssh ${SSH_OPTS} root@${SHARED_NODE_IP} bash -s << 'REMOTE'
    set -euo pipefail
    echo "--- VMs ---"
    qm list --all 2>/dev/null || echo "  (none)"
    echo "--- CTs ---"
    pct list 2>/dev/null || echo "  (none)"
REMOTE

# Migrate running VMs
echo ""
echo "[2/6] Live-migrating VMs from ${SHARED_NODE_NAME} → ${DR_NODE_NAME}..."

ssh ${SSH_OPTS} root@${SHARED_NODE_IP} bash -s << REMOTE
    set -euo pipefail
    TARGET="${DR_NODE_NAME}"
    
    # Migrate running VMs
    for VMID in \$(qm list 2>/dev/null | grep running | awk '{print \$1}'); do
        echo "Migrating VM \${VMID} → \${TARGET}..."
        qm migrate \${VMID} \${TARGET} --online 2>&1 || {
            echo "⚠️  Online migrate failed for VM \${VMID}, trying offline..."
            qm migrate \${VMID} \${TARGET} 2>&1 || {
                echo "❌ VM \${VMID} migration failed"
                exit 1
            }
        }
        echo "✅ VM \${VMID} migrated"
    done
    
    # Migrate stopped VMs
    for VMID in \$(qm list --all 2>/dev/null | grep stopped | awk '{print \$1}'); do
        echo "Migrating stopped VM \${VMID} → \${TARGET}..."
        qm migrate \${VMID} \${TARGET} 2>&1 || {
            echo "❌ VM \${VMID} migration failed"
            exit 1
        }
        echo "✅ VM \${VMID} migrated"
    done
REMOTE

# Migrate CTs
echo ""
echo "[2/6] Migrating CTs from ${SHARED_NODE_NAME} → ${DR_NODE_NAME}..."

ssh ${SSH_OPTS} root@${SHARED_NODE_IP} bash -s << REMOTE
    set -euo pipefail
    TARGET="${DR_NODE_NAME}"
    
    for CTID in \$(pct list 2>/dev/null | awk 'NR>1{print \$1}'); do
        echo "Migrating CT \${CTID} → \${TARGET}..."
        pct migrate \${CTID} \${TARGET} --restart 2>&1 || {
            echo "❌ CT \${CTID} migration failed"
            exit 1
        }
        echo "✅ CT \${CTID} migrated"
    done
REMOTE

# Verify no VMs/CTs remain
echo ""
echo "[2/6] Verifying no VMs/CTs remain on ${SHARED_NODE_NAME}..."

REMAINING=$(ssh ${SSH_OPTS} root@${SHARED_NODE_IP} "echo \$((\$(qm list --all 2>/dev/null | tail -n +2 | wc -l) + \$(pct list 2>/dev/null | tail -n +2 | wc -l)))" 2>/dev/null || echo "0")
if [ "${REMAINING}" -gt 0 ]; then
    echo "❌ ${REMAINING} VMs/CTs still on ${SHARED_NODE_NAME}:"
    ssh ${SSH_OPTS} root@${SHARED_NODE_IP} "qm list --all 2>/dev/null; pct list 2>/dev/null"
    exit 1
fi
echo "[2/6] ✅ All VMs/CTs migrated to ${DR_NODE_NAME}"

# ---------------------------------------------------------------
# Step 3: Backup existing NFS data on sda (ISOs/templates)
# ---------------------------------------------------------------
echo ""
echo "=== T-07: Backup existing NFS data from sda ==="

echo "[3/6] Backing up existing NFS data to /root/..."
ssh ${SSH_OPTS} root@${SHARED_NODE_IP} bash -s << 'REMOTE'
    set -euo pipefail
    
    # Find any existing NFS mount points with data
    NFS_DIRS=$(findmnt -t nfs,nfs4 -o TARGET 2>/dev/null | tail -n +2 || echo "")
    if [ -n "${NFS_DIRS}" ]; then
        for dir in ${NFS_DIRS}; do
            if [ -d "${dir}" ] && [ "$(ls -A "${dir}" 2>/dev/null | wc -l)" -gt 0 ]; then
                BACKUP_FILE="/root/nfs-data-$(basename ${dir})-$(date +%Y%m%d).tar.gz"
                echo "Backing up ${dir} → ${BACKUP_FILE}..."
                tar czf "${BACKUP_FILE}" -C "${dir}" . 2>/dev/null && \
                    echo "✅ Backup: ${BACKUP_FILE}"
            fi
        done
    else
        echo "No NFS mounts found — nothing to backup"
    fi
    
    # Also check for ISO storage
    if [ -d /var/lib/vz/template/iso ] && [ "$(ls -A /var/lib/vz/template/iso 2>/dev/null | wc -l)" -gt 0 ]; then
        BACKUP_FILE="/root/iso-data-$(date +%Y%m%d).tar.gz"
        echo "Backing up ISOs → ${BACKUP_FILE}..."
        tar czf "${BACKUP_FILE}" -C /var/lib/vz/template/iso . 2>/dev/null && \
            echo "✅ Backup: ${BACKUP_FILE}"
    fi
REMOTE

# ---------------------------------------------------------------
# Step 4: T-08, T-09 — Run 01-create-datasets.sh on pve-desa03
# ---------------------------------------------------------------
echo ""
echo "=== T-08 + T-09: Create pool + datasets ==="
echo ""
echo "Running 01-create-datasets.sh on ${SHARED_NODE_NAME}..."
echo ""

# Copy and execute the script on pve-desa03
ssh ${SSH_OPTS} root@${SHARED_NODE_IP} bash -s < "${SCRIPT_DIR}/00-env.sh" << 'REMOTE'
    set -euo pipefail
REMOTE

# Actually, pipe the script to ssh
echo "Copying and executing 01-create-datasets.sh on ${SHARED_NODE_NAME}..."
ssh ${SSH_OPTS} root@${SHARED_NODE_IP} "mkdir -p /usr/local/share/f3-shared-storage"

# SCP the env and datasets script
scp "${SCRIPT_DIR}/00-env.sh" "root@${SHARED_NODE_IP}:/usr/local/share/f3-shared-storage/00-env.sh" 2>/dev/null || \
    scp -o "${SSH_OPTS}" "${SCRIPT_DIR}/00-env.sh" "root@${SHARED_NODE_IP}:/usr/local/share/f3-shared-storage/00-env.sh"

scp "${SCRIPT_DIR}/01-create-datasets.sh" "root@${SHARED_NODE_IP}:/usr/local/share/f3-shared-storage/01-create-datasets.sh" 2>/dev/null || \
    scp -o "${SSH_OPTS}" "${SCRIPT_DIR}/01-create-datasets.sh" "root@${SHARED_NODE_IP}:/usr/local/share/f3-shared-storage/01-create-datasets.sh"

echo "Executing on ${SHARED_NODE_NAME}..."
ssh ${SSH_OPTS} root@${SHARED_NODE_IP} "bash /usr/local/share/f3-shared-storage/01-create-datasets.sh"

echo ""
echo "✅ T-08 + T-09 completed on ${SHARED_NODE_NAME}"

# ---------------------------------------------------------------
# Step 5: T-10 — Run 02-configure-nfs.sh on pve-desa03
# ---------------------------------------------------------------
echo ""
echo "=== T-10: Configure NFS exports + pvesm ==="
echo ""

# Copy and execute NFS script
scp "${SCRIPT_DIR}/02-configure-nfs.sh" "root@${SHARED_NODE_IP}:/usr/local/share/f3-shared-storage/02-configure-nfs.sh" 2>/dev/null || \
    scp -o "${SSH_OPTS}" "${SCRIPT_DIR}/02-configure-nfs.sh" "root@${SHARED_NODE_IP}:/usr/local/share/f3-shared-storage/02-configure-nfs.sh"

echo "Executing on ${SHARED_NODE_NAME}..."
ssh ${SSH_OPTS} root@${SHARED_NODE_IP} "bash /usr/local/share/f3-shared-storage/02-configure-nfs.sh"

echo ""
echo "✅ T-10 completed on ${SHARED_NODE_NAME}"

# ---------------------------------------------------------------
# Step 6: T-11 — Configure ARC on pve-desa03
# ---------------------------------------------------------------
echo ""
echo "=== T-11: Configure ARC (15 GB → 7.5 GB) ==="

echo "[6/6] Configuring zfs_arc_max=${ARC_MAX_BYTES} on ${SHARED_NODE_NAME}..."

ssh ${SSH_OPTS} root@${SHARED_NODE_IP} bash -s << REMOTE
    set -euo pipefail
    
    ARC_BYTES="${ARC_MAX_BYTES}"
    ARC_FILE="/etc/modprobe.d/zfs.conf"
    
    echo "Writing ${ARC_FILE}..."
    echo "options zfs zfs_arc_max=${ARC_BYTES}" > "${ARC_FILE}"
    echo "✅ ${ARC_FILE}: options zfs zfs_arc_max=${ARC_BYTES}"
    
    # Apply runtime value
    CURRENT_ARC=\$(cat /sys/module/zfs/parameters/zfs_arc_max 2>/dev/null || echo "0")
    echo "Current runtime zfs_arc_max: \${CURRENT_ARC}"
    
    if [ "\${CURRENT_ARC}" != "${ARC_MAX_BYTES}" ]; then
        echo "Setting runtime value..."
        echo ${ARC_MAX_BYTES} > /sys/module/zfs/parameters/zfs_arc_max 2>/dev/null || {
            echo "⚠️  Runtime change requires module reload"
            echo "   Will apply on next reboot"
        }
    fi
    
    echo "✅ ARC configured"
REMOTE

echo ""
echo "=== Phase 3: Migration completed ==="
echo ""
echo "========================================================"
echo "  Migration Summary"
echo "========================================================"
echo ""
echo "✅ T-07: VMs/CTs migrated to ${DR_NODE_NAME}"
echo "✅ T-08: Disks cleaned (sda + sdc)"
echo "✅ T-09: Pool ${SHARED_POOL} created (mirror) + 6 datasets"
echo "✅ T-10: NFS exports + Proxmox storages configured"
echo "✅ T-11: ARC configured (${ARC_MAX_BYTES} bytes)"
echo ""

echo "--- Pool status ---"
ssh ${SSH_OPTS} root@${SHARED_NODE_IP} "zpool status ${SHARED_POOL}" 2>/dev/null || echo "  (unreachable)"
echo ""

echo "--- Datasets ---"
ssh ${SSH_OPTS} root@${SHARED_NODE_IP} "zfs list -r ${SHARED_POOL}" 2>/dev/null || echo "  (unreachable)"
echo ""

echo "--- NFS exports ---"
ssh ${SSH_OPTS} root@${SHARED_NODE_IP} "exportfs -v" 2>/dev/null || echo "  (unreachable)"
echo ""

echo "--- ARC ---"
ssh ${SSH_OPTS} root@${SHARED_NODE_IP} "cat /sys/module/zfs/parameters/zfs_arc_max 2>/dev/null || echo 'N/A'" 2>/dev/null || echo "  (unreachable)"
echo ""

echo "⚠️  Next steps:"
echo "  1. Verify NFS mounts from other nodes: showmount -e ${SHARED_NODE_IP}"
echo "  2. Run 03-configure-samba.sh for Samba/CIFS"
echo "  3. Proceed to Phase 4 (pve-desa02 migration) in PR 2"
echo ""
echo "📋 Run the verification script in PR 3 for full validation"
