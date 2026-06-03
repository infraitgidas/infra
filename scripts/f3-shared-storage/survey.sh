#!/bin/bash
# ================================================================
# survey.sh — Tasks T-01, T-02: Backup + Pre-Migration Inventory
# ================================================================
# Phase 1: Backup y Preparación.
#
#   T-01: Backup PBS full cluster — safety net before destructive ops
#   T-02: Full inventory of disks, pools, VMs, CTs on pve-desa02/03
#
# This script is READ-ONLY. It does NOT modify any node.
# Run from your management workstation or any cluster node.
# ================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-env.sh"

echo "=== Phase 1: Backup + Pre-Migration Inventory ==="
echo ""

# ---------------------------------------------------------------
# Step 1: Trigger PBS backup for all VMs (T-01)
# ---------------------------------------------------------------
echo "[1/3] T-01: Triggering PBS full cluster backup..."
echo ""
echo "  Run the following on any cluster node:"
echo ""
echo "    pvesh create /cluster/backup --all 1 --mode snapshot --storage pbs-datastore"
echo ""
echo "  Verify backup progress:"
echo ""
echo "    pvesh get /cluster/backup"
echo "    pvesm list backup"
echo ""
echo "  ⚠️  WAIT for backup to complete before proceeding."
echo "     Check PBS datastore or task logs:"
echo "     journalctl -u pveproxy -f | grep backup"
echo ""

# ---------------------------------------------------------------
# Step 2: Inventory pve-desa02 (T-02)
# ---------------------------------------------------------------
echo "[2/3] T-02: Inventory on pve-desa02 (${DR_NODE_IP})..."
echo ""

echo "--- pve-desa02: Block devices ---"
ssh ${SSH_OPTS} root@${DR_NODE_IP} "lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE 2>/dev/null" || echo "  (unreachable)"
echo ""

echo "--- pve-desa02: Filesystem UUIDs ---"
ssh ${SSH_OPTS} root@${DR_NODE_IP} "blkid 2>/dev/null" || echo "  (unreachable)"
echo ""

echo "--- pve-desa02: LVM state ---"
ssh ${SSH_OPTS} root@${DR_NODE_IP} "lvs 2>/dev/null; vgs 2>/dev/null; pvs 2>/dev/null" || echo "  (unreachable)"
echo ""

echo "--- pve-desa02: ZFS pools ---"
ssh ${SSH_OPTS} root@${DR_NODE_IP} "zpool list 2>/dev/null; zpool status 2>/dev/null" || echo "  (no ZFS pools)"
echo ""

# ---------------------------------------------------------------
# Step 3: Inventory pve-desa03 (T-02)
# ---------------------------------------------------------------
echo "[3/3] T-02: Inventory on pve-desa03 (${SHARED_NODE_IP})..."
echo ""

echo "--- pve-desa03: Block devices ---"
ssh ${SSH_OPTS} root@${SHARED_NODE_IP} "lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE 2>/dev/null" || echo "  (unreachable)"
echo ""

echo "--- pve-desa03: Filesystem UUIDs ---"
ssh ${SSH_OPTS} root@${SHARED_NODE_IP} "blkid 2>/dev/null" || echo "  (unreachable)"
echo ""

echo "--- pve-desa03: Partitions (sfdisk) ---"
ssh ${SSH_OPTS} root@${SHARED_NODE_IP} "sfdisk -l /dev/sda 2>/dev/null | head -20" || echo "  (unreachable)"
ssh ${SSH_OPTS} root@${SHARED_NODE_IP} "sfdisk -l /dev/sdc 2>/dev/null | head -20" || echo "  (unreachable)"
echo ""

echo "--- pve-desa03: LVM state ---"
ssh ${SSH_OPTS} root@${SHARED_NODE_IP} "lvs 2>/dev/null; vgs 2>/dev/null; pvs 2>/dev/null" || echo "  (unreachable)"
echo ""

echo "--- pve-desa03: NFS exports (current) ---"
ssh ${SSH_OPTS} root@${SHARED_NODE_IP} "cat /etc/exports 2>/dev/null || echo '  (no exports)'"
echo ""

echo "--- pve-desa03: NFS mounts ---"
ssh ${SSH_OPTS} root@${SHARED_NODE_IP} "df -h | grep nfs 2>/dev/null || echo '  (no NFS mounts)'"
echo ""

# ---------------------------------------------------------------
# Step 4: Inventory VMs and CTs on both nodes
# ---------------------------------------------------------------
echo "--- pve-desa02: VMs and CTs ---"
ssh ${SSH_OPTS} root@${DR_NODE_IP} "echo 'VMs:' && qm list --all 2>/dev/null && echo '' && echo 'CTs:' && pct list 2>/dev/null" || echo "  (unreachable)"
echo ""

echo "--- pve-desa03: VMs and CTs ---"
ssh ${SSH_OPTS} root@${SHARED_NODE_IP} "echo 'VMs:' && qm list --all 2>/dev/null && echo '' && echo 'CTs:' && pct list 2>/dev/null" || echo "  (unreachable)"
echo ""

# ---------------------------------------------------------------
# Summary
# ---------------------------------------------------------------
echo "=== Survey completed ==="
echo ""
echo "📋 Save the output above to a file for reference before proceeding."
echo "   Recommended: survey.sh | tee /root/f3-survey-$(date +%Y%m%d).log"
echo ""
echo "✅ T-01: Run PBS backup manually (see step [1/3] above)"
echo "✅ T-02: Inventory documented above"
echo ""
echo "Next steps:"
echo "  1. Verify PBS backup completed successfully"
echo "  2. Run: 04-migrate-pve-desa03.sh  (Phase 3 — migrate VMs + prep disks)"
echo "  3. Run: 01-create-datasets.sh     (Phase 2 — create pool + datasets)"
echo "  4. Run: 02-configure-nfs.sh       (Phase 2 — NFS exports + pvesm)"
echo "  5. Run: 03-configure-samba.sh     (Phase 2 — Samba config)"
