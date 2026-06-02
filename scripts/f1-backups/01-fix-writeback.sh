#!/bin/bash
# ================================================================
# 01-fix-writeback.sh — Task 1.2: VM 102 DC2 cache fix
# ================================================================
# Changes VM 102 (DC2) from cache=writeback to cache=none
# on the node where it resides (pve-desa01, 192.168.1.11)
# ================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-env.sh"

VM_ID=102
NODE_IP="192.168.1.11"  # pve-desa01 — VM 102 is on this node
NODE_NAME="pve-desa01"

echo "=== Task 1.2: Fixing VM ${VM_ID} cache=writeback → cache=none ==="

# Check current config on the node
echo "[01] Checking current VM ${VM_ID} config on ${NODE_NAME}..."
CURRENT_CACHE=$(ssh ${SSH_OPTS} root@${NODE_IP} "qm config ${VM_ID} 2>/dev/null | grep '^scsi0' | grep -oP 'cache=\K\w+' || echo 'NOT_FOUND'")

if [ "${CURRENT_CACHE}" = "NOT_FOUND" ]; then
    echo "ERROR: VM ${VM_ID} not found or has no scsi0 disk on ${NODE_NAME}"
    exit 1
fi

echo "[01] Current cache setting: cache=${CURRENT_CACHE}"

if [ "${CURRENT_CACHE}" = "none" ]; then
    echo "[01] Already set to cache=none — nothing to do."
    exit 0
fi

if [ "${CURRENT_CACHE}" != "writeback" ]; then
    echo "WARNING: Expected cache=writeback but found cache=${CURRENT_CACHE}. Proceeding anyway..."
fi

# Check VM status
VM_STATUS=$(ssh ${SSH_OPTS} root@${NODE_IP} "qm status ${VM_ID} 2>/dev/null | awk '{print \$2}'")
echo "[01] VM ${VM_ID} status: ${VM_STATUS}"

if [ "${VM_STATUS}" = "running" ]; then
    echo "WARNING: VM ${VM_ID} is running. Changing cache requires a restart."
    echo "Would you like to stop the VM to apply the change? (yes/no)"
    read -r CONFIRM
    if [ "${CONFIRM}" = "yes" ]; then
        echo "[01] Stopping VM ${VM_ID}..."
        ssh ${SSH_OPTS} root@${NODE_IP} "qm stop ${VM_ID}"
        sleep 3
    else
        echo "[01] Skipping. Note: change will NOT take effect until VM restart."
    fi
fi

# Get current disk config to preserve all parameters
echo "[01] Reading current disk config for VM ${VM_ID}..."
DISK_LINE=$(ssh ${SSH_OPTS} root@${NODE_IP} "qm config ${VM_ID} 2>/dev/null | grep '^scsi0'")
DISK_REF=$(echo "${DISK_LINE}" | awk -F: '{print $2}' | awk -F, '{print $1}' | xargs)
DISK_PARAMS=$(echo "${DISK_LINE}" | grep -oP 'discard=\S+|iothread=\S+|size=\S+')
# Rebuild the full disk string with cache=none
NEW_DISK="${DISK_REF},cache=none,${DISK_PARAMS}"

# Apply the change
echo "[01] Applying cache=none to VM ${VM_ID}..."
echo "[01] New config: scsi0=${NEW_DISK}"
ssh ${SSH_OPTS} root@${NODE_IP} "qm set ${VM_ID} --scsi0 '${NEW_DISK}'"

# Verify
echo "[01] Verifying change..."
NEW_CACHE=$(ssh ${SSH_OPTS} root@${NODE_IP} "qm config ${VM_ID} 2>/dev/null | grep '^scsi0' | grep -oP 'cache=\K\w+' || echo 'NOT_FOUND'")

if [ "${NEW_CACHE}" = "none" ]; then
    echo "✅ SUCCESS: VM ${VM_ID} cache changed to cache=none"
else
    echo "❌ FAILED: VM ${VM_ID} cache is still ${NEW_CACHE}"
    exit 1
fi

# Restart VM if it was running before
if [ "${VM_STATUS}" = "running" ] && [ "${CONFIRM:-}" = "yes" ]; then
    echo "[01] Restarting VM ${VM_ID}..."
    ssh ${SSH_OPTS} root@${NODE_IP} "qm start ${VM_ID}"
fi

echo "=== Task 1.2 completed ==="
