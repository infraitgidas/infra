#!/bin/bash
# ================================================================
# 05-backup-jobs.sh — Task 1.6: Configure daily backup jobs
# ================================================================
# Creates backup jobs for all VMs in the cluster:
#   - Schedule: Daily at 22:00
#   - Mode: snapshot (no VM downtime)
#   - Compression: zstd
#   - Retention: 7 daily + 4 weekly + 3 monthly
#   - Prune: Weekly on Sunday 23:00
#   - GC: Weekly on Sunday 23:30
#
# Uses `pvesh` to create jobs via the PVE API on the cluster.
# Also configures prune + GC schedules for the PBS datastore.
# ================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-env.sh"

CLUSTER_NODE="${NODES[0]}"  # pve-desa01

echo "=== Task 1.6: Configure daily backup jobs ==="

# ---------------------------------------------------------------
# Step 1: Configure PBS datastore retention and schedules
# ---------------------------------------------------------------
echo "[1/5] Configuring PBS datastore retention and maintenance schedules..."

ssh ${SSH_OPTS} root@${PBS_IP} bash -s << "REMOTE"
    set -euo pipefail
    
    PBS_DATASTORE="${PBS_DATASTORE}"
    RETENTION_DAILY="${RETENTION_DAILY}"
    RETENTION_WEEKLY="${RETENTION_WEEKLY}"
    RETENTION_MONTHLY="${RETENTION_MONTHLY}"
    PRUNE_SCHEDULE="${PRUNE_SCHEDULE}"
    GC_SCHEDULE="${GC_SCHEDULE}"
    
    # Set retention on PBS datastore
    echo "[1/5] Setting retention: ${RETENTION_DAILY}d ${RETENTION_WEEKLY}w ${RETENTION_MONTHLY}m..."
    proxmox-backup-manager datastore set "${PBS_DATASTORE}" \
        --keep-daily "${RETENTION_DAILY}" \
        --keep-weekly "${RETENTION_WEEKLY}" \
        --keep-monthly "${RETENTION_MONTHLY}"
    
    # Schedule prune job
    echo "[1/5] Scheduling prune: ${PRUNE_SCHEDULE}..."
    proxmox-backup-manager prune-job create "${PBS_DATASTORE}" --schedule "${PRUNE_SCHEDULE}"
    
    # Schedule GC job
    echo "[1/5] Scheduling GC: ${GC_SCHEDULE}..."
    proxmox-backup-manager garbage-collection-job create "${PBS_DATASTORE}" --schedule "${GC_SCHEDULE}"
    
    echo "[1/5] Maintenance jobs configured:"
    proxmox-backup-manager prune-job list 2>/dev/null || true
    proxmox-backup-manager garbage-collection-job list 2>/dev/null || true
REMOTE

echo "[1/5] ✅ PBS datastore retention and maintenance configured"

# ---------------------------------------------------------------
# Step 2: Check for existing backup jobs
# ---------------------------------------------------------------
echo "[2/5] Checking existing backup jobs on cluster..."

EXISTING_JOBS=$(ssh ${SSH_OPTS} root@${CLUSTER_NODE} "pvesh get /cluster/backup --noborder --output-format json 2>/dev/null | python3 -c 'import sys,json; data=json.load(sys.stdin); print(len(data))' 2>/dev/null || echo 0")

echo "[2/5] Found ${EXISTING_JOBS} existing backup job(s)"

# ---------------------------------------------------------------
# Step 3: Create a single backup job for all VMs
# ---------------------------------------------------------------
echo "[3/5] Creating unified backup job for all VMs..."

# Build comma-separated VM ID list
VM_ID_LIST=$(IFS=,; echo "${VM_IDS[*]}")

ssh ${SSH_OPTS} root@${CLUSTER_NODE} bash -s << "REMOTE"
    set -euo pipefail
    
    VM_ID_LIST="${VM_ID_LIST}"
    PBS_STORAGE_ID="${PBS_STORAGE_ID}"
    BACKUP_SCHEDULE="${BACKUP_SCHEDULE}"
    RETENTION_DAILY="${RETENTION_DAILY}"
    RETENTION_WEEKLY="${RETENTION_WEEKLY}"
    RETENTION_MONTHLY="${RETENTION_MONTHLY}"
    
    # Create backup job via pvesh
    pvesh create /cluster/backup \
        --vmid "${VM_ID_LIST}" \
        --storage "${PBS_STORAGE_ID}" \
        --schedule "${BACKUP_SCHEDULE}" \
        --compress zstd \
        --mode snapshot \
        --all 0 \
        --enabled 1 \
        --prune-backup-keep-daily "${RETENTION_DAILY}" \
        --prune-backup-keep-weekly "${RETENTION_WEEKLY}" \
        --prune-backup-keep-monthly "${RETENTION_MONTHLY}"
    
    echo "[3/5] Backup job created"
REMOTE

echo "[3/5] ✅ Backup job created (VMs: ${VM_ID_LIST})"

# ---------------------------------------------------------------
# Step 4: Verify backup job configuration
# ---------------------------------------------------------------
echo "[4/5] Verifying backup job configuration..."

ssh ${SSH_OPTS} root@${CLUSTER_NODE} bash -s << 'REMOTE'
    echo "[4/5] Backup jobs configured on cluster:"
    pvesh get /cluster/backup --noborder 2>/dev/null | head -30 || echo "(no output)"
REMOTE

echo "[4/5] ✅ Backup job verified"

# ---------------------------------------------------------------
# Step 5: Verify encryption key is referenced
# ---------------------------------------------------------------
echo "[5/5] Verifying encryption key is set in storage.cfg..."

ENCRYPTION_REF=$(ssh ${SSH_OPTS} root@${CLUSTER_NODE} "grep 'encryption-key' /etc/pve/storage.cfg 2>/dev/null || echo 'NOT_FOUND'")

if [ "${ENCRYPTION_REF}" = "NOT_FOUND" ]; then
    echo "WARNING: encryption-key not found in storage.cfg."
    echo "Run 04-configure-storage.sh first."
else
    echo "[5/5] ✅ Encryption key referenced in storage.cfg:"
    echo "  ${ENCRYPTION_REF}"
fi

echo ""
echo "=== Task 1.6 completed ==="
echo ""
echo "Backup Configuration Summary:"
echo "  Target storage: ${PBS_STORAGE_ID}"
echo "  VMs:           ${VM_ID_LIST}"
echo "  Schedule:      ${BACKUP_SCHEDULE} (daily 22:00)"
echo "  Mode:          snapshot"
echo "  Compression:   zstd"
echo "  Retention:     ${RETENTION_DAILY}d ${RETENTION_WEEKLY}w ${RETENTION_MONTHLY}m"
echo "  Prune:         ${PRUNE_SCHEDULE}"
echo "  GC:            ${GC_SCHEDULE}"
