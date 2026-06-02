#!/bin/bash
# ================================================================
# 02-migrate-to-neighbor.sh — Task 2.1: Move VMs to neighbor node
# ================================================================
# For each node that has running VMs/CTs, migrate them to the
# neighbor node before ZFS conversion.
#
# Migration plan:
#   pve-desa01 (CT 105 + VM 100) → pve-desa02
#   pve-desa04 (VM 109)          → pve-desa03
# ================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-env.sh"

echo "=== Task 2.1: Migrate VMs to neighbor nodes ==="
echo ""

# ---------------------------------------------------------------
# Step 1: Validate prerequisites
# ---------------------------------------------------------------
echo "[1/5] Checking prerequisites..."

# Ensure PBS backups exist before destructive operations
FIRST_NODE="${NODES[0]}"
BACKUP_JOBS=$(ssh ${SSH_OPTS} root@${FIRST_NODE} "pvesh get /cluster/backup --noborder --output-format json 2>/dev/null | python3 -c 'import sys,json; print(len(json.load(sys.stdin)))' 2>/dev/null || echo 0")
if [ "${BACKUP_JOBS}" -eq 0 ]; then
    echo "❌ No backup jobs configured! Run F1 first."
    exit 1
fi
echo "[1/5] ✅ Backup jobs exist — safety net confirmed"

# Check destination nodes
for ip in "${NODES[1]}" "${NODES[2]}"; do
    if ! ssh ${SSH_OPTS} root@${ip} "hostname" &>/dev/null; then
        echo "❌ Destination node ${ip} not reachable"
        exit 1
    fi
done
echo "[1/5] ✅ Destination nodes reachable"

# ---------------------------------------------------------------
# Step 2: Remove snapshot on CT 105
# ---------------------------------------------------------------
echo ""
echo "[2/5] Removing snapshots on source nodes..."

CT105_SNAP=$(ssh ${SSH_OPTS} root@${NODES[0]} "pct listsnapshot 105 2>/dev/null | grep -v 'current' | grep -oP '[\w.-]+' | head -1" 2>/dev/null || echo "")
if [ -n "${CT105_SNAP}" ]; then
    echo "[2/5] Removing snapshot '${CT105_SNAP}' from CT 105..."
    ssh ${SSH_OPTS} root@${NODES[0]} "pct delsnapshot 105 ${CT105_SNAP}"
    echo "[2/5] ✅ Snapshot removed from CT 105"
else
    echo "[2/5] No snapshots to remove on CT 105"
fi

# ---------------------------------------------------------------
# Step 3: Migrate CT 105 from pve-desa01 → pve-desa02
# ---------------------------------------------------------------
echo ""
echo "[3/5] Migrating CT 105 from pve-desa01 → pve-desa02..."

# Check if already migrated
CT_ON_DST=$(ssh ${SSH_OPTS} root@${NODES[1]} "pct list 2>/dev/null | grep -c '^105 '" 2>/dev/null || echo 0)
if [ "${CT_ON_DST}" -gt 0 ]; then
    echo "[3/5] ⏭️  CT 105 already on pve-desa02 — checking status..."
    CT_STATUS=$(ssh ${SSH_OPTS} root@${NODES[1]} "pct status 105 2>/dev/null | awk '{print \$2}'" 2>/dev/null || echo "unknown")
    echo "[3/5]     CT 105 status on pve-desa02: ${CT_STATUS}"
else
    echo "[3/5] Running: pct migrate 105 pve-desa02 --restart..."
    ssh ${SSH_OPTS} root@${NODES[0]} "pct migrate 105 pve-desa02 --restart" 2>&1 || {
        echo "❌ Failed to migrate CT 105"
        exit 1
    }
    echo "[3/5] ✅ CT 105 migrated to pve-desa02"
fi

# ---------------------------------------------------------------
# Step 4: Migrate VM 100 from pve-desa01 → pve-desa02
# ---------------------------------------------------------------
echo ""
echo "[4/5] Migrating VM 100 from pve-desa01 → pve-desa02..."

# Check if already migrated
VM_ON_DST=$(ssh ${SSH_OPTS} root@${NODES[1]} "qm list --all 2>/dev/null | grep -c '^100 '" 2>/dev/null || echo 0)
if [ "${VM_ON_DST}" -gt 0 ]; then
    echo "[4/5] ⏭️  VM 100 already on pve-desa02 — checking status..."
    VM_STATUS=$(ssh ${SSH_OPTS} root@${NODES[1]} "qm status 100 2>/dev/null | awk '{print \$2}'" 2>/dev/null || echo "unknown")
    echo "[4/5]     VM 100 status on pve-desa02: ${VM_STATUS}"
else
    # VM 100 is stopped, cold migrate
    echo "[4/5] Running: qm migrate 100 pve-desa02..."
    ssh ${SSH_OPTS} root@${NODES[0]} "qm migrate 100 pve-desa02" 2>&1 || {
        echo "❌ Failed to migrate VM 100"
        exit 1
    }
    echo "[4/5] ✅ VM 100 migrated to pve-desa02"
fi

# ---------------------------------------------------------------
# Step 5: Migrate VM 109 from pve-desa04 → pve-desa03
# ---------------------------------------------------------------
echo ""
echo "[5/5] Migrating VM 109 from pve-desa04 → pve-desa03..."

# Check if already migrated
VM109_ON_DST=$(ssh ${SSH_OPTS} root@${NODES[2]} "qm list --all 2>/dev/null | grep -c '^109 '" 2>/dev/null || echo 0)
if [ "${VM109_ON_DST}" -gt 0 ]; then
    echo "[5/5] ⏭️  VM 109 already on pve-desa03 — checking status..."
    VM109_STATUS=$(ssh ${SSH_OPTS} root@${NODES[2]} "qm status 109 2>/dev/null | awk '{print \$2}'" 2>/dev/null || echo "unknown")
    echo "[5/5]     VM 109 status on pve-desa03: ${VM109_STATUS}"
else
    # Check if VM 109 is running
    VM109_RUNNING=$(ssh ${SSH_OPTS} root@${NODES[3]} "qm status 109 2>/dev/null | grep -c 'running'" 2>/dev/null || echo 0)
    if [ "${VM109_RUNNING}" -gt 0 ]; then
        echo "[5/5] VM 109 is running — attempting live migration..."
        ssh ${SSH_OPTS} root@${NODES[3]} "qm migrate 109 pve-desa03" 2>&1 || {
            echo "❌ Live migration of VM 109 failed"
            exit 1
        }
    else
        echo "[5/5] VM 109 is stopped — cold migration..."
        ssh ${SSH_OPTS} root@${NODES[3]} "qm migrate 109 pve-desa03" 2>&1 || {
            echo "❌ Cold migration of VM 109 failed"
            exit 1
        }
    fi
    echo "[5/5] ✅ VM 109 migrated to pve-desa03"
fi

# ---------------------------------------------------------------
# Final Verification
# ---------------------------------------------------------------
echo ""
echo "=== Verifying migration results ==="

echo "--- pve-desa01 (source) ---"
echo "VMs:"
ssh ${SSH_OPTS} root@${NODES[0]} "qm list --all 2>/dev/null | tail -n +2" || echo "  (none)"
echo "CTs:"
ssh ${SSH_OPTS} root@${NODES[0]} "pct list 2>/dev/null | tail -n +2" || echo "  (none)"

echo "--- pve-desa04 (source) ---"
echo "VMs:"
ssh ${SSH_OPTS} root@${NODES[3]} "qm list --all 2>/dev/null | tail -n +2" || echo "  (none)"

echo "--- pve-desa02 (destination for CT 105 + VM 100) ---"
echo "VMs:"
ssh ${SSH_OPTS} root@${NODES[1]} "qm list --all 2>/dev/null | tail -n +2" || echo "  (none)"
echo "CTs:"
ssh ${SSH_OPTS} root@${NODES[1]} "pct list 2>/dev/null | tail -n +2" || echo "  (none)"

echo "--- pve-desa03 (destination for VM 109) ---"
echo "VMs:"
ssh ${SSH_OPTS} root@${NODES[2]} "qm list --all 2>/dev/null | tail -n +2" || echo "  (none)"
echo "CTs:"
ssh ${SSH_OPTS} root@${NODES[2]} "pct list 2>/dev/null | tail -n +2" || echo "  (none)"

echo ""
echo "=== Task 2.1 completed ==="
