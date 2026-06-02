#!/bin/bash
# ================================================================
# 03-encryption-key.sh — Task 1.4: Generate encryption key on each node
# ================================================================
# Generates a random 256-bit encryption key at /root/.pve-encryption-key
# on each cluster node AND on the PBS node.
#
# The key is used for client-side encryption:
#   - Data is encrypted on the PVE node BEFORE transmission
#   - PBS cannot decrypt data without the key
# ================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-env.sh"

echo "=== Task 1.4: Generate encryption key on all nodes ==="

# Generate the key on this management machine first
KEY_FILE="/tmp/pve-encryption-key"
echo "[generate] Generating 256-bit encryption key..."
openssl rand -hex 32 > "${KEY_FILE}"
chmod 600 "${KEY_FILE}"
echo "[generate] Key generated: $(wc -c < "${KEY_FILE}") bytes"

# Deploy to each cluster node
for i in "${!NODES[@]}"; do
    NODE_IP="${NODES[$i]}"
    NODE_NAME="${NODE_NAMES[$i]}"
    
    echo "[node] ${NODE_NAME} (${NODE_IP})..."
    
    # Check if key already exists
    KEY_EXISTS=$(ssh ${SSH_OPTS} root@${NODE_IP} "test -f ${ENCRYPTION_KEY_PATH} && echo 'EXISTS' || echo 'MISSING'")
    
    if [ "${KEY_EXISTS}" = "EXISTS" ]; then
        echo "[node] ${NODE_NAME}: Key already exists at ${ENCRYPTION_KEY_PATH}"
        echo "[node] ${NODE_NAME}: Skipping (remove key manually to regenerate)"
        continue
    fi
    
    # Copy key to node
    scp ${SSH_OPTS} "${KEY_FILE}" "root@${NODE_IP}:${ENCRYPTION_KEY_PATH}"
    ssh ${SSH_OPTS} root@${NODE_IP} "chmod 600 ${ENCRYPTION_KEY_PATH}"
    
    # Verify
    NODE_KEY=$(ssh ${SSH_OPTS} root@${NODE_IP} "cat ${ENCRYPTION_KEY_PATH} | wc -c")
    echo "[node] ${NODE_NAME}: ✅ Key deployed (${NODE_KEY} bytes)"
done

# Also deploy to PBS node (needed for restore operations)
echo "[pbs] ${PBS_HOSTNAME} (${PBS_IP})..."
PBS_KEY_EXISTS=$(ssh ${SSH_OPTS} root@${PBS_IP} "test -f ${ENCRYPTION_KEY_PATH} && echo 'EXISTS' || echo 'MISSING'")

if [ "${PBS_KEY_EXISTS}" = "EXISTS" ]; then
    echo "[pbs] ${PBS_HOSTNAME}: Key already exists — skipping"
else
    scp ${SSH_OPTS} "${KEY_FILE}" "root@${PBS_IP}:${ENCRYPTION_KEY_PATH}"
    ssh ${SSH_OPTS} root@${PBS_IP} "chmod 600 ${ENCRYPTION_KEY_PATH}"
    echo "[pbs] ${PBS_HOSTNAME}: ✅ Key deployed"
fi

# Cleanup temp file
rm -f "${KEY_FILE}"

echo ""
echo "=== Task 1.4 completed ==="
echo ""
echo "✅ Encryption key deployed to all ${#NODES[@]} cluster nodes + ${PBS_HOSTNAME}"
echo "⚠️  IMPORTANT: This key is ESSENTIAL for data recovery."
echo "   Store it securely (e.g., in a password manager)."
echo "   Key path: ${ENCRYPTION_KEY_PATH} on each node"
