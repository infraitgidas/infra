#!/bin/bash
# ================================================================
# 06-replication.sh — Task 2.6: Configure async replication
# ================================================================
# Configures asynchronous ZFS replication between fixed pairs:
#   pve-desa01 ↔ pve-desa02
#   pve-desa03 ↔ pve-desa04
#
# Schedule: RPO 15min for critical VMs, 1h for non-critical
# Bandwidth limit: 500 Mbps
#
# PREREQUISITE: ZFS pools created on all nodes, VMs back on ZFS
# ================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-env.sh"

echo "=== Task 2.6: Configure asynchronous replication ==="
echo ""

# ---------------------------------------------------------------
# Step 1: Verify prerequisites
# ---------------------------------------------------------------
echo "[1/4] Verifying prerequisites..."

# Check that pvesr is available (Proxmox VE replication)
FIRST_NODE="${NODES[0]}"
PVESR_OK=$(ssh ${SSH_OPTS} root@${FIRST_NODE} "command -v pvesr 2>/dev/null && echo OK || echo NO" 2>/dev/null || echo "NO")
if [ "${PVESR_OK}" != "OK" ]; then
    echo "❌ pvesr command not found on ${FIRST_NODE}"
    echo "   Is this a Proxmox VE cluster node?"
    exit 1
fi

# Check that ZFS is available on all nodes
for i in "${!NODES[@]}"; do
    IP="${NODES[$i]}"
    NAME="${NODE_NAMES[$i]}"
    
    ZFS_OK=$(ssh ${SSH_OPTS} root@${IP} "zpool list -H -o health ${ZFS_POOL_NAME} 2>/dev/null || echo 'NOT_FOUND'")
    if [ "${ZFS_OK}" != "ONLINE" ]; then
        echo "❌ ZFS pool ${ZFS_POOL_NAME} not healthy on ${NAME}"
        exit 1
    fi
    echo "[1/4] ✅ ${NAME}: ZFS pool OK"
done

# ---------------------------------------------------------------
# Step 2: Create replication jobs
# ---------------------------------------------------------------
echo ""
echo "[2/4] Creating replication jobs..."

# Map VMID -> which source node it belongs to (original node)
declare -A VMID_SOURCE_NODE
VMID_SOURCE_NODE[105]="0"  # CT 105 on pve-desa01
VMID_SOURCE_NODE[100]="0"  # VM 100 on pve-desa01
VMID_SOURCE_NODE[109]="3"  # VM 109 on pve-desa04

for schedule_entry in "${VM_REPLICATION_SCHEDULES[@]}"; do
    VMID="${schedule_entry%%|*}"
    REMAINDER="${schedule_entry#*|}"
    LABEL="${REMAINDER%%|*}"
    SCHEDULE="${REMAINDER#*|}"
    
    # Find which node this VM belongs to (its source/original node)
    VM_SRC_IDX="${VMID_SOURCE_NODE[$VMID]}"
    if [ -z "${VM_SRC_IDX}" ]; then
        echo "[2/4] Unknown source node for VM ${VMID} — skipping"
        continue
    fi
    
    SRC_IP="${NODES[$VM_SRC_IDX]}"
    SRC_NAME="${NODE_NAMES[$VM_SRC_IDX]}"
    
    # Find the replication target (neighbor)
    TARGET_NODE=""
    for pair in "${REPLICATION_PAIRS[@]}"; do
        PAIR_SRC="${pair%%:*}"
        PAIR_TARGET="${pair##*:}"
        if [ "${PAIR_SRC}" = "${VM_SRC_IDX}" ]; then
            TARGET_NODE="${NODE_NAMES[$PAIR_TARGET]}"
            break
        fi
    done
    
    if [ -z "${TARGET_NODE}" ]; then
        echo "[2/4] No replication target for VM ${VMID} on ${SRC_NAME} — skipping"
        continue
    fi
    
    echo "--- Creating replication job for VM ${VMID} (${LABEL}) ---"
    echo "  Source: ${SRC_NAME} (${SRC_IP})"
    echo "  Target: ${TARGET_NODE}"
    echo "  Schedule: ${SCHEDULE}"
    echo "  BW Limit: ${BWLIMIT} bytes/sec ($((BWLIMIT / 1024 / 1024 * 8)) Mbps)"
    
    # Check if job already exists
    JOB_EXISTS=$(ssh ${SSH_OPTS} root@${SRC_IP} "pvesr list 2>/dev/null | grep -c \"${VMID}.*${TARGET_NODE}\"" 2>/dev/null || echo 0)
    if [ "${JOB_EXISTS}" -gt 0 ]; then
        echo "[2/4] Replication job for VM ${VMID} -> ${TARGET_NODE} already exists"
        ssh ${SSH_OPTS} root@${SRC_IP} "pvesr list 2>/dev/null | grep \"${VMID}\""
        continue
    fi
    
    # Create replication job on the source node
    echo "[2/4] Running: pvesr create-local-job ${VMID} ${TARGET_NODE} --rate ${BWLIMIT} --schedule \"${SCHEDULE}\"..."
    ssh ${SSH_OPTS} root@${SRC_IP} "pvesr create-local-job ${VMID} ${TARGET_NODE} --rate ${BWLIMIT} --schedule \"${SCHEDULE}\"" 2>&1 || {
        echo "[2/4] Failed to create replication job for VM ${VMID}"
        echo "   This may be because VM ${VMID} is stopped or uses non-ZFS storage."
        echo "   Continuing with other VMs..."
    }
    
    # Verify
    echo "[2/4] Job created. Current replication state:"
    ssh ${SSH_OPTS} root@${SRC_IP} "pvesr list 2>/dev/null | grep \"${VMID}\""
done

# ---------------------------------------------------------------
# Step 3: Setup snapshot schedules (daily, 7-day retention)
# ---------------------------------------------------------------
echo ""
echo "[3/4] Setting up daily snapshot schedules..."

# Check if sanoid is available
SANOID_OK=$(ssh ${SSH_OPTS} root@${FIRST_NODE} "command -v sanoid 2>/dev/null && echo OK || echo NO" 2>/dev/null || echo "NO")
if [ "${SANOID_OK}" = "OK" ]; then
    echo "[3/4] sanoid found — checking configuration..."
    for i in "${!NODES[@]}"; do
        IP="${NODES[$i]}"
        NAME="${NODE_NAMES[$i]}"
        
        SANOID_CFG=$(ssh ${SSH_OPTS} root@${IP} "test -f /etc/sanoid/sanoid.conf && echo EXISTS || echo MISSING" 2>/dev/null || echo "MISSING")
        if [ "${SANOID_CFG}" = "MISSING" ]; then
            echo "[3/4] Configuring sanoid on ${NAME} for daily snapshots..."
            ssh ${SSH_OPTS} root@${IP} bash -s << "REMOTE"
                set -euo pipefail
                ZFS_POOL_NAME="${ZFS_POOL_NAME}"
                mkdir -p /etc/sanoid
                cat > /etc/sanoid/sanoid.conf << EOF2
[${ZFS_POOL_NAME}]
        use_template = production
        recursive = yes

[template_production]
        daily = 7
        hourly = 0
        monthly = 0
        yearly = 0
        autosnap = yes
        autoprune = yes
EOF2
                cat > /etc/cron.d/sanoid << EOF2
# Daily snapshot at 23:00
0 23 * * * root /usr/sbin/sanoid --cron
EOF2
                echo "[3/4] sanoid configured for daily snapshots (7-day retention)"
REMOTE
        else
            echo "[3/4] sanoid already configured on ${NAME}"
        fi
    done
else
    echo "[3/4] sanoid not installed — creating manual snapshot cron jobs..."
    for i in "${!NODES[@]}"; do
        IP="${NODES[$i]}"
        NAME="${NODE_NAMES[$i]}"
        
        ssh ${SSH_OPTS} root@${IP} bash -s << "REMOTE"
            set -euo pipefail
            ZFS_POOL_NAME="${ZFS_POOL_NAME}"
            
            # Add daily snapshot cron if not exists
            if ! grep -q "zfs snapshot.*${ZFS_POOL_NAME}" /etc/crontab 2>/dev/null; then
                echo "# Daily ZFS snapshot" >> /etc/crontab
                # Using single quotes for the $(date ...) part to prevent premature
                # expansion: cron evaluates $(date +%Y%m%d) at execution time,
                # not at script-write time. \% escapes % for cron's special handling.
                echo '0 23 * * * root zfs snapshot -r '${ZFS_POOL_NAME}'@daily-$(date +\%Y\%m\%d)' >> /etc/crontab
                # Prune snapshots older than 7 days
                echo "30 23 * * * root zfs list -H -o name -t snapshot | grep ${ZFS_POOL_NAME}@daily | head -n -7 | xargs -r zfs destroy" >> /etc/crontab
                echo "[3/4] Daily snapshot cron added on ${NAME}"
            else
                echo "[3/4] Snapshot cron already exists on ${NAME}"
            fi
REMOTE
    done
fi

# ---------------------------------------------------------------
# Step 4: Verify replication configuration
# ---------------------------------------------------------------
echo ""
echo "[4/4] Verifying replication configuration..."

for i in "${!NODES[@]}"; do
    IP="${NODES[$i]}"
    NAME="${NODE_NAMES[$i]}"
    
    echo "--- ${NAME} replication jobs ---"
    ssh ${SSH_OPTS} root@${IP} "pvesr list 2>/dev/null | tail -n +2" || echo "  (none configured)"
done

echo ""
echo "=== Task 2.6 completed ==="
echo ""
echo "Replication Summary:"
echo "  Pairs: pve-desa01 <-> pve-desa02, pve-desa03 <-> pve-desa04"
echo "  Bandwidth limit: ${BWLIMIT} bytes/sec (~500 Mbps)"
for schedule_entry in "${VM_REPLICATION_SCHEDULES[@]}"; do
    VMID="${schedule_entry%%|*}"
    REMAINDER="${schedule_entry#*|}"
    LABEL="${REMAINDER%%|*}"
    SCHEDULE="${REMAINDER#*|}"
    echo "  VM ${VMID} (${LABEL}): ${SCHEDULE}"
done
echo "  Snapshots: Daily at 23:00, 7-day retention"
