#!/bin/bash
# ================================================================
# 04-configure-storage.sh — Task 1.5: Add PBS as storage in storage.cfg
# ================================================================
# Adds the PBS datastore to /etc/pve/storage.cfg so all cluster
# nodes can use it as a backup target.
#
# /etc/pve/ is a PMXCFS (shared filesystem) — changes propagate
# to all cluster nodes automatically.
# ================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-env.sh"

# Pick the first cluster node to make changes (pve-desa01)
CLUSTER_NODE="${NODES[0]}"

echo "=== Task 1.5: Add PBS to /etc/pve/storage.cfg ==="

# Check if PBS storage entry already exists
echo "[1/4] Checking if PBS storage already configured..."
PBS_EXISTS=$(ssh ${SSH_OPTS} root@${CLUSTER_NODE} "grep -c '^pbs: ${PBS_STORAGE_ID}\|^    datastore ${PBS_DATASTORE}' /etc/pve/storage.cfg 2>/dev/null || true")

if [ "${PBS_EXISTS}" -gt 0 ]; then
    echo "[1/4] ✅ PBS storage '${PBS_STORAGE_ID}' already configured in storage.cfg"
    echo "Current storage.cfg:"
    ssh ${SSH_OPTS} root@${CLUSTER_NODE} "cat /etc/pve/storage.cfg"
    exit 0
fi

# Verify PBS is reachable from cluster node
echo "[2/4] Verifying PBS connectivity from cluster..."
if ssh ${SSH_OPTS} root@${CLUSTER_NODE} "curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 https://${PBS_IP}:${PBS_PORT} 2>/dev/null || echo 'UNREACHABLE'"; then
    HTTP_CODE=$(ssh ${SSH_OPTS} root@${CLUSTER_NODE} "curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 https://${PBS_IP}:${PBS_PORT} 2>/dev/null || echo 'UNREACHABLE'")
    if [ "${HTTP_CODE}" = "UNREACHABLE" ] || [ -z "${HTTP_CODE}" ]; then
        echo "WARNING: PBS at ${PBS_IP}:${PBS_PORT} is not reachable from cluster."
        echo "This is expected if PBS is still being set up or firewall is blocking."
        echo "The storage config will be added but will show as 'offline' until PBS is accessible."
    else
        echo "[2/4] ✅ PBS reachable (HTTP ${HTTP_CODE})"
    fi
fi

# Get the PBS fingerprint from the PBS node
echo "[3/4] Getting PBS TLS fingerprint..."
PBS_FINGERPRINT=$(ssh ${SSH_OPTS} root@${PBS_IP} \
    "openssl x509 -in /etc/proxmox-backup/proxy.pem -fingerprint -sha256 -noout 2>/dev/null | cut -d= -f2" \
    2>/dev/null || echo "")

if [ -z "${PBS_FINGERPRINT}" ]; then
    echo "ERROR: Could not get PBS fingerprint. Is PBS installed on ${PBS_HOSTNAME}?"
    echo "Run 02-install-pbs.sh first."
    exit 1
fi

echo "[3/4] Fingerprint: ${PBS_FINGERPRINT}"

# Add PBS to storage.cfg on the cluster
echo "[4/4] Adding PBS storage to /etc/pve/storage.cfg..."

ssh ${SSH_OPTS} root@${CLUSTER_NODE} bash -s << "REMOTE"
    set -euo pipefail
    
    PBS_STORAGE_ID="${PBS_STORAGE_ID}"
    PBS_HOST="${PBS_IP}"
    PBS_PORT="${PBS_PORT}"
    PBS_DATASTORE="${PBS_DATASTORE}"
    PBS_FINGERPRINT="${PBS_FINGERPRINT}"
    
    # Append PBS storage entry
    cat >> /etc/pve/storage.cfg << EOF

pbs: ${PBS_STORAGE_ID}
	server ${PBS_HOST}
	port ${PBS_PORT}
	datastore ${PBS_DATASTORE}
	encryption-key ${ENCRYPTION_KEY_PATH}
	fingerprint ${PBS_FINGERPRINT}
	content backup
	prune-backups keep-all=1
	max-protected-backups 5

EOF

    echo "storage.cfg updated:"
    grep -A 6 "^pbs: ${PBS_STORAGE_ID}" /etc/pve/storage.cfg
REMOTE

echo "[4/4] ✅ PBS storage '${PBS_STORAGE_ID}' added to storage.cfg"

# Verify storage is visible in PVE
echo ""
echo "=== Verifying storage visibility ==="
sleep 2  # Give PMXCFS time to sync
ssh ${SSH_OPTS} root@${CLUSTER_NODE} "pvesh get /storage/${PBS_STORAGE_ID} --noborder 2>&1 || pvesm status 2>&1 | grep ${PBS_STORAGE_ID} || echo 'Storage may take a moment to appear — run: pvesm status'"

echo ""
echo "=== Task 1.5 completed ==="
echo ""
echo "Storage Configuration:"
echo "  Storage ID:     ${PBS_STORAGE_ID}"
echo "  Server:         ${PBS_IP}:${PBS_PORT}"
echo "  Datastore:      ${PBS_DATASTORE}"
echo "  Encryption Key: ${ENCRYPTION_KEY_PATH}"
echo "  Fingerprint:    ${PBS_FINGERPRINT}"
