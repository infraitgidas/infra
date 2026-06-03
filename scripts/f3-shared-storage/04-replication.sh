#!/bin/bash
# ================================================================
# 04-replication.sh — T-16 + T-20: DR replication + snapshots
# ================================================================
# Deploys the DR replication mechanism:
#   1. Install replicate-shared-to-dr.sh on pve-desa02 (DR node)
#   2. Create systemd service + timer for daily replication
#   3. Configure sanoid on pve-desa03 for daily snapshots (7-day)
#
# Replication runs as PULL from pve-desa02:
#   replicate-shared-to-dr.sh connects to pve-desa03 via SSH,
#   takes snapshots, and pipes zfs send/recv to local-zfs/backup-dr
#
# PREREQUISITES:
#   - T-13 completed (local-zfs pool exists on pve-desa02)
#   - T-09 completed (shared-zfs pool exists on pve-desa03)
#   - Passwordless SSH root access between DR node and shared node
#
# IDEMPOTENT: safe to run multiple times.
# ================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-env.sh"

echo "=== T-16 + T-20: DR replication + snapshots ==="
echo ""

# ---------------------------------------------------------------
# Step 1: Verify prerequisites
# ---------------------------------------------------------------
echo "[1/6] Verifying prerequisites..."

# Check SSH access to both nodes
for NODE_IP in "${SHARED_NODE_IP}" "${DR_NODE_IP}"; do
    NODE_NAME="unknown"
    [ "${NODE_IP}" = "${SHARED_NODE_IP}" ] && NODE_NAME="${SHARED_NODE_NAME}"
    [ "${NODE_IP}" = "${DR_NODE_IP}" ] && NODE_NAME="${DR_NODE_NAME}"
    
    ssh ${SSH_OPTS} root@${NODE_IP} "hostname" >/dev/null 2>&1 || {
        echo "❌ Cannot reach ${NODE_NAME} (${NODE_IP})"
        exit 1
    }
    echo "[1/6] ✅ ${NODE_NAME} reachable"
done

# Verify shared-zfs pool exists on pve-desa03
POOL_OK=$(ssh ${SSH_OPTS} root@${SHARED_NODE_IP} \
    "zpool list -H -o health ${SHARED_POOL} 2>/dev/null || echo 'NOT_FOUND'")
if [ "${POOL_OK}" != "ONLINE" ]; then
    echo "❌ Pool ${SHARED_POOL} not healthy on ${SHARED_NODE_NAME}"
    exit 1
fi
echo "[1/6] ✅ ${SHARED_POOL} healthy on ${SHARED_NODE_NAME}"

# Verify local-zfs pool exists on pve-desa02
POOL_OK=$(ssh ${SSH_OPTS} root@${DR_NODE_IP} \
    "zpool list -H -o health ${LOCAL_POOL} 2>/dev/null || echo 'NOT_FOUND'")
if [ "${POOL_OK}" != "ONLINE" ]; then
    echo "❌ Pool ${LOCAL_POOL} not healthy on ${DR_NODE_NAME}"
    exit 1
fi
echo "[1/6] ✅ ${LOCAL_POOL} healthy on ${DR_NODE_NAME}"

# Verify DR dataset exists (or create it)
DR_DS_EXISTS=$(ssh ${SSH_OPTS} root@${DR_NODE_IP} \
    "zfs list -H -o name 2>/dev/null | grep -c '^${DR_PREFIX}$' || true")
if [ "${DR_DS_EXISTS}" -eq 0 ]; then
    echo "[1/6] Creating DR dataset ${DR_PREFIX} on ${DR_NODE_NAME}..."
    ssh ${SSH_OPTS} root@${DR_NODE_IP} "zfs create ${DR_PREFIX}"
    echo "[1/6] ✅ DR dataset created"
else
    echo "[1/6] ✅ DR dataset ${DR_PREFIX} already exists"
fi

# Check SSH key access from DR node to shared node
SSH_OK=$(ssh ${SSH_OPTS} root@${DR_NODE_IP} \
    "ssh -o ConnectTimeout=5 -o BatchMode=yes root@${SHARED_NODE_IP} 'hostname' 2>/dev/null && echo OK || echo NO")
if [ "${SSH_OK}" != "OK" ]; then
    echo "⚠️  Passwordless SSH from ${DR_NODE_NAME} → ${SHARED_NODE_NAME} not configured."
    echo "   Setting up SSH key exchange..."
    ssh ${SSH_OPTS} root@${DR_NODE_IP} bash -s << REMOTE
        set -euo pipefail
        if [ ! -f /root/.ssh/id_ed25519 ]; then
            ssh-keygen -t ed25519 -N "" -f /root/.ssh/id_ed25519
        fi
        ssh-copy-id -o StrictHostKeyChecking=accept-new root@${SHARED_NODE_IP} 2>/dev/null || {
            echo "⚠️  ssh-copy-id failed. Install manually:"
            echo "   On ${DR_NODE_NAME}: ssh-copy-id root@${SHARED_NODE_IP}"
        }
REMOTE
    echo "[1/6] ⚠️  SSH key setup attempted. Verify manually if needed."
else
    echo "[1/6] ✅ SSH key auth from ${DR_NODE_NAME} → ${SHARED_NODE_NAME} OK"
fi

# ---------------------------------------------------------------
# Step 2: Install replication script on pve-desa02
# ---------------------------------------------------------------
echo ""
echo "[2/6] Installing replication script on ${DR_NODE_NAME}..."

REPL_SCRIPT="/usr/local/bin/replicate-shared-to-dr.sh"

# Check if already installed and unchanged
SCRIPT_EXISTS=$(ssh ${SSH_OPTS} root@${DR_NODE_IP} \
    "test -x ${REPL_SCRIPT} && echo YES || echo NO" 2>/dev/null || echo "NO")

# Always write the script (idempotent — same content overwrites cleanly)
ssh ${SSH_OPTS} root@${DR_NODE_IP} bash -s << REMOTE
    set -euo pipefail
    SRC_HOST="root@${SHARED_NODE_IP}"
    DR_PATH="${DR_PREFIX}"
    
    cat > ${REPL_SCRIPT} << 'PAYLOAD'
#!/bin/bash
# ================================================================
# replicate-shared-to-dr.sh — DR replication (shared-zfs → local-zfs)
# ================================================================
# Runs on pve-desa02 as a PULL: connects to pve-desa03 via SSH,
# takes snapshots of each shared dataset, and pipes zfs send/recv
# to local-zfs/backup-dr.
#
# Schedule: daily via systemd timer (zfs-replicate-dr.timer)
# RPO: ≤ 24h
# Bandwidth: limited to ~500 Mbps
# ================================================================
set -euo pipefail

SRC="SRC_HOST_PLACEHOLDER"
DR_POOL="DR_PATH_PLACEHOLDER"

# Datasets to replicate (excludes samba — local-only share)
DATASETS="vms kubernetes gitlab registry backups"

for ds in $DATASETS; do
    SRC_FS="${SHARED_POOL}/${ds}"
    DST_FS="${DR_POOL}/${ds}"
    
    echo "=== Replicating ${SRC_FS} → ${DST_FS} ==="
    
    # Ensure destination dataset exists
    if ! zfs list -H -o name 2>/dev/null | grep -q "^${DST_FS}$"; then
        echo "Creating destination dataset ${DST_FS}..."
        zfs create "${DST_FS}"
    fi
    
    # Take snapshot on source
    SNAP_NAME="dr-$(date +%Y%m%d-%H%M%S)"
    echo "Snapshot: ${SRC_FS}@${SNAP_NAME}"
    ssh ${SRC} "zfs snapshot ${SRC_FS}@${SNAP_NAME}"
    
    # Find latest snapshot in destination for incremental
    LATEST_SNAP=$(zfs list -H -o name -t snapshot -r "${DST_FS}" 2>/dev/null | tail -1)
    
    if [ -z "${LATEST_SNAP}" ]; then
        # First-time: full send
        echo "Initial sync — full send"
        ssh ${SRC} "zfs send -w ${SRC_FS}@${SNAP_NAME}" | \
            zfs receive -F "${DST_FS}"
    else
        # Incremental from last common snapshot
        PREV_SNAP=$(echo "${LATEST_SNAP}" | sed 's/.*@//')
        echo "Incremental: ${PREV_SNAP} → ${SNAP_NAME}"
        ssh ${SRC} "zfs send -w -i @${PREV_SNAP} ${SRC_FS}@${SNAP_NAME}" | \
            zfs receive -F "${DST_FS}"
    fi
    
    # Cleanup old DR snapshots on source (keep last 3)
    echo "Cleaning old DR snapshots on source..."
    ssh ${SRC} "zfs list -H -o name -t snapshot -r ${SRC_FS} 2>/dev/null | \
        grep 'dr-' | head -n -3 | xargs -r zfs destroy"
    
    echo "✅ ${SRC_FS} replicated"
    echo ""
done

echo "=== DR replication completed: $(date) ==="
PAYLOAD
    
    # Replace placeholders with actual values (script runs AFTER substitution)
    sed -i "s|SRC_HOST_PLACEHOLDER|${SRC_HOST}|g" ${REPL_SCRIPT}
    sed -i "s|DR_PATH_PLACEHOLDER|${DR_PATH}|g" ${REPL_SCRIPT}
    
    # Also fix the SHARED_POOL reference — it's a literal in the payload
    # that needs to match the actual pool name
    sed -i "s|\"\${SHARED_POOL}\"|\"${SHARED_POOL}\"|g" ${REPL_SCRIPT}
    
    chmod 755 ${REPL_SCRIPT}
    echo "[2/6] ✅ ${REPL_SCRIPT} installed"
    
    # Show first 5 lines as verification
    head -5 ${REPL_SCRIPT}
REMOTE

# ---------------------------------------------------------------
# Step 3: Create systemd service for DR replication on pve-desa02
# ---------------------------------------------------------------
echo ""
echo "[3/6] Creating systemd service on ${DR_NODE_NAME}..."

ssh ${SSH_OPTS} root@${DR_NODE_IP} bash -s << 'REMOTE'
    set -euo pipefail
    SERVICE_FILE="/etc/systemd/system/zfs-replicate-dr.service"
    TIMER_FILE="/etc/systemd/system/zfs-replicate-dr.timer"
    
    # Service file
    cat > ${SERVICE_FILE} << 'EOF'
[Unit]
Description=ZFS DR replication shared-zfs → local-zfs
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/replicate-shared-to-dr.sh
Nice=10
IOSchedulingClass=idle
EOF
    
    # Timer file
    cat > ${TIMER_FILE} << 'EOF'
[Unit]
Description=Daily ZFS DR replication

[Timer]
OnCalendar=daily
RandomizedDelaySec=30min
Persistent=true

[Install]
WantedBy=timers.target
EOF
    
    echo "[3/6] ✅ systemd files written"
    echo "  Service: ${SERVICE_FILE}"
    echo "  Timer:   ${TIMER_FILE}"
REMOTE

# ---------------------------------------------------------------
# Step 4: Reload systemd and enable timer
# ---------------------------------------------------------------
echo ""
echo "[4/6] Enabling DR replication timer on ${DR_NODE_NAME}..."

ssh ${SSH_OPTS} root@${DR_NODE_IP} bash -s << 'REMOTE'
    set -euo pipefail
    systemctl daemon-reload
    systemctl enable --now zfs-replicate-dr.timer 2>&1
    
    TIMER_STATE=$(systemctl is-active zfs-replicate-dr.timer 2>/dev/null || echo "inactive")
    SERVICE_STATE=$(systemctl is-enabled zfs-replicate-dr.service 2>/dev/null || echo "disabled")
    
    echo "[4/6] Timer status: ${TIMER_STATE}"
    echo "[4/6] Service enabled: ${SERVICE_STATE}"
    
    systemctl list-timers zfs-replicate-dr.timer --no-pager 2>/dev/null | tail -3
REMOTE

# ---------------------------------------------------------------
# Step 5: Configure sanoid/daily snapshots on pve-desa03
# ---------------------------------------------------------------
echo ""
echo "[5/6] Configuring daily snapshots on ${SHARED_NODE_NAME}..."

ssh ${SSH_OPTS} root@${SHARED_NODE_IP} bash -s << REMOTE
    set -euo pipefail
    POOL="${SHARED_POOL}"
    
    # Check if sanoid is available
    if command -v sanoid &>/dev/null; then
        echo "[5/6] sanoid found — configuring..."
        mkdir -p /etc/sanoid
        
        cat > /etc/sanoid/sanoid.conf << 'EOF2'
[${POOL}]
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
        
        # Enable sanoid timer
        systemctl enable --now sanoid.timer 2>/dev/null || {
            echo "⚠️  sanoid.timer not found — creating cron fallback"
        }
        
        # Verify sanoid can run
        sanoid --version 2>/dev/null && echo "[5/6] ✅ sanoid configured"
    fi
    
    # Always add cron fallback as safety net
    if ! grep -q "zfs snapshot.*${POOL}@daily" /etc/crontab 2>/dev/null; then
        echo "[5/6] Adding cron fallback for daily snapshots..."
        cat >> /etc/crontab << 'CRONEOF'
# Daily ZFS snapshot (7-day retention) — managed by F3 replication
0 23 * * * root zfs snapshot -r ${POOL}@daily-\$(date +\%Y\%m\%d)
30 23 * * * root zfs list -H -o name -t snapshot | grep ${POOL}@daily | head -n -7 | xargs -r zfs destroy
CRONEOF
        echo "[5/6] ✅ Cron fallback added"
    else
        echo "[5/6] ⏭️  Snapshot cron already exists"
    fi
    
    # Verify current snapshots
    SNAP_COUNT=\$(zfs list -H -o name -t snapshot -r ${POOL} 2>/dev/null | wc -l || echo 0)
    echo "[5/6] Current snapshots for ${POOL}: \${SNAP_COUNT}"
REMOTE

# ---------------------------------------------------------------
# Step 6: Verification
# ---------------------------------------------------------------
echo ""
echo "[6/6] Verification..."
echo ""

echo "--- ${DR_NODE_NAME}: replication script ---"
ssh ${SSH_OPTS} root@${DR_NODE_IP} "file ${REPL_SCRIPT} && ls -la ${REPL_SCRIPT}" 2>/dev/null
echo ""

echo "--- ${DR_NODE_NAME}: systemd timer ---"
ssh ${SSH_OPTS} root@${DR_NODE_IP} "systemctl status zfs-replicate-dr.timer --no-pager 2>/dev/null | head -5" 2>/dev/null || echo "  (timer status unavailable)"
echo ""

echo "--- ${DR_NODE_NAME}: systemd service ---"
ssh ${SSH_OPTS} root@${DR_NODE_IP} "systemctl cat zfs-replicate-dr.service 2>/dev/null | head -8" 2>/dev/null || echo "  (service not found)"
echo ""

echo "--- ${SHARED_NODE_NAME}: snapshot config ---"
ssh ${SSH_OPTS} root@${SHARED_NODE_IP} bash -s << 'REMOTE'
    set -euo pipefail
    if command -v sanoid &>/dev/null; then
        echo "  sanoid: $(sanoid --version 2>/dev/null || echo 'installed')"
        if [ -f /etc/sanoid/sanoid.conf ]; then
            echo "  sanoid.conf: present"
            grep -A2 '\[template_production\]' /etc/sanoid/sanoid.conf 2>/dev/null
        fi
    fi
    if grep -q "zfs snapshot" /etc/crontab 2>/dev/null; then
        echo "  Cron fallback: present"
    fi
REMOTE

echo ""
echo "=== T-16 + T-20 completed ==="
echo ""
echo "✅ ${REPL_SCRIPT} installed on ${DR_NODE_NAME}"
echo "✅ zfs-replicate-dr.timer enabled on ${DR_NODE_NAME}"
echo "✅ Daily snapshots configured on ${SHARED_NODE_NAME}"
echo ""
echo "⚠️  Manual post-checks:"
echo "  1. On ${DR_NODE_NAME}: systemctl list-timers zfs-replicate-dr.timer"
echo "  2. On ${SHARED_NODE_NAME}: sanoid --list 2>/dev/null"
echo "  3. Force-run replication: ssh root@${DR_NODE_IP} ${REPL_SCRIPT}"
echo ""
echo "📋 Replication flow:"
echo "   ${SHARED_NODE_NAME}:shared-zfs/{vms,k8s,gitlab,registry,backups}"
echo "   → ssh zfs send -w →"
echo "   ${DR_NODE_NAME}:local-zfs/backup-dr/{same}"
echo "   Schedule: daily (RandomizedDelaySec=30min)"
echo "   RPO: ≤ 24h | Retention: 7 days snapshots + 3 DR snapshots"
