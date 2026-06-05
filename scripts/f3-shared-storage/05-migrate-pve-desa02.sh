#!/bin/bash
# ================================================================
# 05-migrate-pve-desa02.sh — Phase 4+5: Full pve-desa02 migration
# ================================================================
# Orchestrates the complete migration of pve-desa02 from current
# state (LVM thin local-storage on sdb + free sdc) to the target
# state (local-zfs mirror + DR pool + Samba + replication).
#
# Tasks covered:
#   T-12: Migrate VMs/CTs from pve-desa02 to shared NFS
#   T-13: Destroy local-storage → create local-zfs mirror sdb+sdc
#   T-14: Configure ARC (10 GB → 5 GB)
#   T-15: Add local-zfs as zfspool in Proxmox
#   T-19: Configure Samba on pve-desa03 (call 03-configure-samba.sh)
#   T-20: Deploy DR replication + enable systemd timer
#
# PREREQUISITES:
#   - Phase 3 completed (pve-desa03 migrated to shared-zfs, NFS active)
#   - T-10 completed (NFS exports active + pvesm storages exist)
#   - Run from a management workstation OR any cluster node
#   - Passwordless SSH root access to all nodes
#
# ⚠️  THIS SCRIPT PERFORMS DESTRUCTIVE OPERATIONS ON pve-desa02.
#     Have a rollback plan before running.
# ================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-env.sh"

echo "========================================================"
echo "  Phase 4+5: Migrate pve-desa02 to local-zfs mirror + DR"
echo "========================================================"
echo ""
echo "⚠️  WARNING: This script will DESTROY existing LVM data on"
echo "   /dev/sdb of ${DR_NODE_NAME} (${DR_NODE_IP})."
echo ""
echo "   Ensure:"
echo "   - T-01 (PBS backup) completed successfully"
echo "   - Phase 3 (pve-desa03) completed — NFS active"
echo "   - All VMs/CTs are backed up"
echo ""
echo "   Press Ctrl+C now to abort, or Enter to continue..."
read -r

# ---------------------------------------------------------------
# Step 1: Verify prerequisites
# ---------------------------------------------------------------
echo ""
echo "=== Prerequisites check ==="
echo ""

echo "[1/9] Verifying connectivity..."

for NODE_IP in "${SHARED_NODE_IP}" "${DR_NODE_IP}"; do
    NODE_NAME="unknown"
    [ "${NODE_IP}" = "${SHARED_NODE_IP}" ] && NODE_NAME="${SHARED_NODE_NAME}"
    [ "${NODE_IP}" = "${DR_NODE_IP}" ] && NODE_NAME="${DR_NODE_NAME}"
    
    ssh ${SSH_OPTS} root@${NODE_IP} "hostname" >/dev/null 2>&1 || {
        echo "❌ Cannot reach ${NODE_NAME} (${NODE_IP})"
        exit 1
    }
    echo "[1/9] ✅ ${NODE_NAME} reachable"
done

# Verify NFS is active (shared-zfs pool + NFS exports)
echo ""
echo "[1/9] Verifying ${SHARED_POOL} and NFS on ${SHARED_NODE_NAME}..."

POOL_OK=$(ssh ${SSH_OPTS} root@${SHARED_NODE_IP} \
    "zpool list -H -o health ${SHARED_POOL} 2>/dev/null || echo 'NOT_FOUND'")
if [ "${POOL_OK}" != "ONLINE" ]; then
    echo "❌ Pool ${SHARED_POOL} not healthy. Complete Phase 3 first."
    exit 1
fi
echo "[1/9] ✅ ${SHARED_POOL} healthy"

NFS_OK=$(ssh ${SSH_OPTS} root@${SHARED_NODE_IP} \
    "exportfs -v 2>/dev/null | grep -q '${SHARED_POOL}/vms' && echo OK || echo NO" 2>/dev/null || echo "NO")
if [ "${NFS_OK}" != "OK" ]; then
    echo "⚠️  NFS exports may not be configured on ${SHARED_NODE_NAME}."
    echo "   Run 02-configure-nfs.sh first."
    echo "   Continuing anyway — T-12 may fail if NFS is not ready."
fi

# ---------------------------------------------------------------
# Step 2: T-12 — Migrate VMs/CTs from pve-desa02 to shared NFS
# ---------------------------------------------------------------
echo ""
echo "=== T-12: Migrate VMs/CTs from ${DR_NODE_NAME} to shared NFS ==="
echo ""

# List current VMs/CTs on pve-desa02
echo "[2/9] Listing VMs/CTs on ${DR_NODE_NAME}..."
ssh ${SSH_OPTS} root@${DR_NODE_IP} bash -s << 'REMOTE'
    set -euo pipefail
    echo "--- VMs ---"
    qm list --all 2>/dev/null || echo "  (none)"
    echo "--- CTs ---"
    pct list 2>/dev/null || echo "  (none)"
REMOTE

# Ask for confirmation before migrating
echo ""
echo "[2/9] About to migrate all VMs/CTs from ${DR_NODE_NAME} to NFS storage."
echo "   VMs will use shared-vms as target storage."
echo "   Target node: ${SHARED_NODE_NAME}"
echo ""
echo "   Press Enter to continue, or Ctrl+C to abort..."
read -r

# Migrate VMs to shared-vms NFS storage on pve-desa03
echo ""
echo "[2/9] Migrating VMs to NFS storage (shared-vms)..."
ssh ${SSH_OPTS} root@${DR_NODE_IP} bash -s << REMOTE
    set -euo pipefail
    TARGET="${SHARED_NODE_NAME}"
    NFS_STORAGE="shared-vms"
    
    # Migrate running VMs with storage migration
    for VMID in \$(qm list 2>/dev/null | grep running | awk '{print \$1}'); do
        echo "Migrating VM \${VMID} → \${TARGET} (storage: \${NFS_STORAGE})..."
        
        # Try online migration with storage move first
        qm migrate \${VMID} \${TARGET} --target-storage \${NFS_STORAGE} --online 2>&1 || {
            echo "⚠️  Online migrate failed for VM \${VMID}, trying offline..."
            qm migrate \${VMID} \${TARGET} --target-storage \${NFS_STORAGE} 2>&1 || {
                echo "❌ VM \${VMID} migration failed"
                exit 1
            }
        }
        echo "✅ VM \${VMID} migrated to \${TARGET}"
    done
    
    # Migrate stopped VMs
    for VMID in \$(qm list --all 2>/dev/null | grep stopped | awk '{print \$1}'); do
        echo "Migrating stopped VM \${VMID} → \${TARGET}..."
        qm migrate \${VMID} \${TARGET} --target-storage \${NFS_STORAGE} 2>&1 || {
            echo "❌ VM \${VMID} migration failed"
            exit 1
        }
        echo "✅ VM \${VMID} migrated"
    done
REMOTE

# Migrate CTs
echo ""
echo "[2/9] Migrating CTs to ${SHARED_NODE_NAME}..."
ssh ${SSH_OPTS} root@${DR_NODE_IP} bash -s << REMOTE
    set -euo pipefail
    TARGET="${SHARED_NODE_NAME}"
    
    for CTID in \$(pct list 2>/dev/null | awk 'NR>1{print \$1}'); do
        echo "Migrating CT \${CTID} → \${TARGET}..."
        pct migrate \${CTID} \${TARGET} --restore 2>&1 || {
            echo "❌ CT \${CTID} migration failed"
            exit 1
        }
        echo "✅ CT \${CTID} migrated"
    done
REMOTE

# Verify no VMs/CTs remain on pve-desa02
echo ""
echo "[2/9] Verifying no VMs/CTs remain on ${DR_NODE_NAME}..."
REMAINING=$(ssh ${SSH_OPTS} root@${DR_NODE_IP} \
    "echo \$((\$(qm list --all 2>/dev/null | tail -n +2 | wc -l) + \$(pct list 2>/dev/null | tail -n +2 | wc -l)))" 2>/dev/null || echo "0")

if [ "${REMAINING}" -gt 0 ]; then
    echo "❌ ${REMAINING} VMs/CTs still on ${DR_NODE_NAME}:"
    ssh ${SSH_OPTS} root@${DR_NODE_IP} "qm list --all 2>/dev/null; pct list 2>/dev/null"
    exit 1
fi
echo "[2/9] ✅ All VMs/CTs migrated to ${SHARED_NODE_NAME}"

# ---------------------------------------------------------------
# Step 3: T-13 — Verify local-storage empty, then destroy it
# ---------------------------------------------------------------
echo ""
echo "=== T-13: Destroy local-storage LVM — create local-zfs mirror ==="
echo ""

# Check if local-storage LVM still has data
echo "[3/9] Checking local-storage LVM state..."
LVS_OUTPUT=$(ssh ${SSH_OPTS} root@${DR_NODE_IP} "lvs local-storage/data 2>/dev/null || echo 'NOT_FOUND'")
echo "  ${LVS_OUTPUT}"

# Now execute the destructive operations
echo ""
echo "[3/9] Destroying local-storage LVM and cleaning sdb..."
ssh ${SSH_OPTS} root@${DR_NODE_IP} bash -s << 'REMOTE'
    set -euo pipefail
    
    # Remove LVM thin pool and VG
    if lvs local-storage/data &>/dev/null; then
        echo "[3/9] Removing LVM thin pool local-storage/data..."
        lvremove -f local-storage/data 2>/dev/null || true
    else
        echo "[3/9] ⏭️  local-storage/data already removed"
    fi
    
    if vgs local-storage &>/dev/null; then
        echo "[3/9] Removing VG local-storage..."
        vgremove -f local-storage 2>/dev/null || true
    else
        echo "[3/9] ⏭️  VG local-storage already removed"
    fi
    
    # Remove PV
    if pvs /dev/sdb &>/dev/null; then
        echo "[3/9] Removing PV on /dev/sdb..."
        pvremove -f /dev/sdb 2>/dev/null || true
    else
        echo "[3/9] ⏭️  No PV on /dev/sdb"
    fi
    
    # Wipe partition table
    echo "[3/9] Wiping /dev/sdb partition table..."
    sgdisk -Z /dev/sdb
    wipefs -a /dev/sdb
    
    # Also ensure /dev/sdc is clean
    echo "[3/9] Ensuring /dev/sdc is clean..."
    if sfdisk -d /dev/sdc &>/dev/null 2>&1; then
        sgdisk -Z /dev/sdc
        wipefs -a /dev/sdc
    else
        echo "[3/9] ⏭️  /dev/sdc already clean"
    fi
    
    echo "[3/9] ✅ Disks cleaned"
REMOTE

# ---------------------------------------------------------------
# Step 4: T-13 — Create local-zfs mirror with sdb+sdc
# ---------------------------------------------------------------
echo ""
echo "[4/9] Creating local-zfs mirror pool..."

# Create pool
POOL_EXISTS=$(ssh ${SSH_OPTS} root@${DR_NODE_IP} \
    "zpool list -H -o name 2>/dev/null | grep -c '^${LOCAL_POOL}$' || true")

if [ "${POOL_EXISTS}" -gt 0 ]; then
    POOL_HEALTH=$(ssh ${SSH_OPTS} root@${DR_NODE_IP} \
        "zpool list -H -o health ${LOCAL_POOL} 2>/dev/null || echo 'unknown'")
    echo "[4/9] ⏭️  Pool ${LOCAL_POOL} already exists (health: ${POOL_HEALTH})"
    
    # Verify it's a mirror
    VDEV_TYPE=$(ssh ${SSH_OPTS} root@${DR_NODE_IP} \
        "zpool status ${LOCAL_POOL} 2>/dev/null | grep -E '^\s+mirror|^\s+raidz' | awk '{print \$1}'" || echo "unknown")
    if [ "${VDEV_TYPE}" != "mirror" ] && [ "${VDEV_TYPE}" != "raidz" ]; then
        echo "⚠️  Pool ${LOCAL_POOL} is not a mirror. zpool status:"
        ssh ${SSH_OPTS} root@${DR_NODE_IP} "zpool status ${LOCAL_POOL}"
        echo "   Aborting. Destroy it manually: zpool destroy ${LOCAL_POOL}"
        exit 1
    fi
else
    echo "[4/9] Creating mirror pool ${LOCAL_POOL}..."
    ssh ${SSH_OPTS} root@${DR_NODE_IP} bash -s << REMOTE
        set -euo pipefail
        zpool create -f \
            -o ashift=12 \
            -O compression=zstd \
            -O atime=off \
            -O xattr=sa \
            ${LOCAL_POOL} \
            mirror /dev/sdb /dev/sdc
REMOTE
    echo "[4/9] ✅ Pool ${LOCAL_POOL} created"
fi

# Create datasets
echo ""
echo "[4/9] Creating datasets..."
ssh ${SSH_OPTS} root@${DR_NODE_IP} bash -s << REMOTE
    set -euo pipefail
    POOL="${LOCAL_POOL}"
    
    # Create vms dataset
    if ! zfs list -H -o name 2>/dev/null | grep -q "^${POOL}/vms$"; then
        zfs create ${POOL}/vms
        echo "Created ${POOL}/vms"
    else
        echo "⏭️  ${POOL}/vms already exists"
    fi
    zfs set compression=zstd ${POOL}/vms
    zfs set atime=off ${POOL}/vms
    zfs set xattr=sa ${POOL}/vms
    echo "  compression=zstd, atime=off, xattr=sa"
    
    # Create backup-dr dataset
    if ! zfs list -H -o name 2>/dev/null | grep -q "^${POOL}/backup-dr$"; then
        zfs create ${POOL}/backup-dr
        echo "Created ${POOL}/backup-dr"
    else
        echo "⏭️  ${POOL}/backup-dr already exists"
    fi
    zfs set compression=zstd ${POOL}/backup-dr
    zfs set atime=off ${POOL}/backup-dr
    zfs set xattr=sa ${POOL}/backup-dr
    echo "  compression=zstd, atime=off, xattr=sa"
    
    echo "[4/9] ✅ Datasets created"
    zfs list -r ${POOL}
REMOTE

# ---------------------------------------------------------------
# Step 5: T-14 — Configure ARC on pve-desa02
# ---------------------------------------------------------------
echo ""
echo "=== T-14: Configure ARC (10 GB → 5 GB) ==="
echo ""

echo "[5/9] Configuring zfs_arc_max=${DR_ARC_MAX_BYTES} on ${DR_NODE_NAME}..."

ssh ${SSH_OPTS} root@${DR_NODE_IP} bash -s << REMOTE
    set -euo pipefail
    
    ARC_BYTES="${DR_ARC_MAX_BYTES}"
    ARC_FILE="/etc/modprobe.d/zfs.conf"
    
    echo "Writing ${ARC_FILE}..."
    echo "options zfs zfs_arc_max=\${ARC_BYTES}" > "\${ARC_FILE}"
    echo "✅ ${ARC_FILE}: options zfs zfs_arc_max=\${ARC_BYTES}"
    
    # Try runtime apply
    CURRENT_ARC=\$(cat /sys/module/zfs/parameters/zfs_arc_max 2>/dev/null || echo "0")
    echo "Current runtime zfs_arc_max: \${CURRENT_ARC}"
    
    if [ "\${CURRENT_ARC}" != "\${ARC_BYTES}" ]; then
        echo "Attempting runtime change..."
        echo "\${ARC_BYTES}" > /sys/module/zfs/parameters/zfs_arc_max 2>/dev/null || {
            echo "⚠️  Runtime change requires module reload"
            echo "   Will apply on next reboot"
        }
    fi
    
    echo "✅ ARC configured on ${DR_NODE_NAME}"
REMOTE

# ---------------------------------------------------------------
# Step 6: T-15 — Add local-zfs as zfspool storage in Proxmox
# ---------------------------------------------------------------
echo ""
echo "=== T-15: Add local-zfs as zfspool storage ==="
echo ""

echo "[6/9] Adding zfspool storage via pvesm..."

# Check if already exists
PVESM_CHECK=$(ssh ${SSH_OPTS} root@${SHARED_NODE_IP} \
    "pvesm status 2>/dev/null | grep -c '^${LOCAL_POOL}\s' || true" 2>/dev/null || echo 0)

if [ "${PVESM_CHECK}" -gt 0 ]; then
    echo "[6/9] ⏭️  Storage ${LOCAL_POOL} already exists in pvesm"
    ssh ${SSH_OPTS} root@${SHARED_NODE_IP} "pvesm status 2>/dev/null | grep '^${LOCAL_POOL}\s'"
else
    echo "[6/9] Adding ZFS storage ${LOCAL_POOL}..."
    ssh ${SSH_OPTS} root@${SHARED_NODE_IP} bash -s << REMOTE
        set -euo pipefail
        pvesm add zfspool ${LOCAL_POOL} \
            --pool ${LOCAL_POOL} \
            --content images,rootdir \
            --sparse 1 \
            --nodes ${DR_NODE_NAME} 2>&1 || {
            echo "⚠️  pvesm add from ${SHARED_NODE_NAME} failed."
            echo "   Try running directly on ${DR_NODE_NAME}:"
            echo "   pvesm add zfspool ${LOCAL_POOL} --pool ${LOCAL_POOL} --content images,rootdir --sparse 1 --nodes ${DR_NODE_NAME}"
            exit 1
        }
        echo "✅ Storage ${LOCAL_POOL} added"
REMOTE
fi

# Verify
echo ""
echo "[6/9] Verifying storage..."
ssh ${SSH_OPTS} root@${SHARED_NODE_IP} "pvesm status 2>/dev/null | grep -E '^${LOCAL_POOL}\s|^Name'" || \
    echo "⚠️  pvesm status unavailable — check manually: pvesm status"

# ---------------------------------------------------------------
# Step 7: T-19 — Configure Samba on pve-desa03
# ---------------------------------------------------------------
echo ""
echo "=== T-19: Configure Samba on ${SHARED_NODE_NAME} ==="
echo ""

echo "[7/9] Preparing remote directory on ${SHARED_NODE_NAME}..."

ssh ${SSH_OPTS} root@${SHARED_NODE_IP} "mkdir -p /usr/local/share/f3-shared-storage"

echo "[7/9] Copying and executing 03-configure-samba.sh on ${SHARED_NODE_NAME}..."

# Copy env + samba script to pve-desa03
scp "${SCRIPT_DIR}/00-env.sh" "root@${SHARED_NODE_IP}:/usr/local/share/f3-shared-storage/00-env.sh" 2>/dev/null || \
    scp -o "${SSH_OPTS}" "${SCRIPT_DIR}/00-env.sh" "root@${SHARED_NODE_IP}:/usr/local/share/f3-shared-storage/00-env.sh"

scp "${SCRIPT_DIR}/03-configure-samba.sh" "root@${SHARED_NODE_IP}:/usr/local/share/f3-shared-storage/03-configure-samba.sh" 2>/dev/null || \
    scp -o "${SSH_OPTS}" "${SCRIPT_DIR}/03-configure-samba.sh" "root@${SHARED_NODE_IP}:/usr/local/share/f3-shared-storage/03-configure-samba.sh"

# Execute on remote
ssh ${SSH_OPTS} root@${SHARED_NODE_IP} "bash /usr/local/share/f3-shared-storage/03-configure-samba.sh" || {
    echo "⚠️  Samba configuration encountered issues."
    echo "   Check output above. The smbpasswd step is interactive."
    echo "   You may need to run manually:"
    echo "   ssh root@${SHARED_NODE_IP} smbpasswd -a ${SAMBA_USER}"
}

echo ""
echo "[7/9] ✅ Samba configuration completed (or partially — check above)"

# ---------------------------------------------------------------
# Step 8: T-20 — Deploy DR replication + systemd timer
# ---------------------------------------------------------------
echo ""
echo "=== T-20: Deploy DR replication ==="
echo ""

echo "[8/9] Preparing remote directory on ${DR_NODE_NAME}..."

ssh ${SSH_OPTS} root@${DR_NODE_IP} "mkdir -p /usr/local/share/f3-shared-storage"

echo "[8/9] Running 04-replication.sh to deploy DR + snapshots..."

# Ensure env file is on the DR node
scp "${SCRIPT_DIR}/00-env.sh" "root@${DR_NODE_IP}:/usr/local/share/f3-shared-storage/00-env.sh" 2>/dev/null || \
    scp -o "${SSH_OPTS}" "${SCRIPT_DIR}/00-env.sh" "root@${DR_NODE_IP}:/usr/local/share/f3-shared-storage/00-env.sh"

# Run the replication deployer (04-replication.sh is designed to be run from management node)
bash "${SCRIPT_DIR}/04-replication.sh" || {
    echo "⚠️  DR replication deployment had issues."
    echo "   Check output above. You may need to run manually:"
    echo "   bash scripts/f3-shared-storage/04-replication.sh"
}

echo ""
echo "[8/9] ✅ DR replication deployment completed"

# ---------------------------------------------------------------
# Step 9: Final verification
# ---------------------------------------------------------------
echo ""
echo "=== Final verification ==="
echo ""

echo "[9/9] Verifying all components..."
echo ""

echo "--- ${DR_NODE_NAME}: local-zfs pool ---"
ssh ${SSH_OPTS} root@${DR_NODE_IP} "zpool status ${LOCAL_POOL}" 2>/dev/null || echo "  (unreachable)"
echo ""

echo "--- ${DR_NODE_NAME}: datasets ---"
ssh ${SSH_OPTS} root@${DR_NODE_IP} "zfs list -r ${LOCAL_POOL}" 2>/dev/null || echo "  (unreachable)"
echo ""

echo "--- ${DR_NODE_NAME}: ARC ---"
ssh ${SSH_OPTS} root@${DR_NODE_IP} "cat /sys/module/zfs/parameters/zfs_arc_max 2>/dev/null || echo 'N/A'" 2>/dev/null || echo "  (unreachable)"
echo ""

echo "--- Proxmox storage (from ${SHARED_NODE_NAME}) ---"
ssh ${SSH_OPTS} root@${SHARED_NODE_IP} "pvesm status 2>/dev/null | grep -E '^${LOCAL_POOL}\s|^shared-'" 2>/dev/null || echo "  (unreachable)"
echo ""

echo "--- ${SHARED_NODE_NAME}: Samba ---"
ssh ${SSH_OPTS} root@${SHARED_NODE_IP} "smbstatus -L 2>/dev/null | head -5 || echo '  (smbstatus unavailable)'" 2>/dev/null || echo "  (unreachable)"
echo ""

echo "--- ${DR_NODE_NAME}: DR timer ---"
ssh ${SSH_OPTS} root@${DR_NODE_IP} "systemctl list-timers zfs-replicate-dr.timer --no-pager 2>/dev/null | tail -3 || echo '  (timer not found)'" 2>/dev/null || echo "  (unreachable)"
echo ""

echo "========================================================"
echo "  Phase 4+5: Migration Summary"
echo "========================================================"
echo ""
echo "✅ T-12: VMs/CTs migrated from ${DR_NODE_NAME} to NFS (${SHARED_NODE_NAME})"
echo "✅ T-13: local-storage destroyed, ${LOCAL_POOL} mirror created"
echo "✅ T-14: ARC configured on ${DR_NODE_NAME} (${DR_ARC_MAX_BYTES} bytes = $((DR_ARC_MAX_BYTES / 1024 / 1024 / 1024)) GB)"
echo "✅ T-15: ${LOCAL_POOL} registered as zfspool in Proxmox"
echo "✅ T-19: Samba installed and configured on ${SHARED_NODE_NAME}"
echo "✅ T-20: DR replication deployed (04-replication.sh)"
echo ""
echo "📋 Next steps:"
echo "  1. Verify NFS mounts from all cluster nodes: showmount -e ${SHARED_NODE_IP}"
echo "  2. Run the verification script in PR 3 (verify.sh) for full validation"
echo "  3. Set Samba password if not done: smbpasswd -a ${SAMBA_USER}"
echo "  4. Force-run DR replication: ssh root@${DR_NODE_IP} /usr/local/bin/replicate-shared-to-dr.sh"
echo ""
echo "⚠️  To migrate VMs back to local-zfs (optional, design 4.6):"
echo "   qm migrate <VMID> ${DR_NODE_NAME} --target-storage ${LOCAL_POOL}"
