#!/bin/bash
# ================================================================
# 02-bootstrap-vm.sh — Phase 2: Instalar Docker Engine
# ================================================================
# SSH a la VM como infra, instala Docker CE desde repos oficiales
# y docker compose plugin.
# ================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=00-env.sh
. "${SCRIPT_DIR}/00-env.sh"

echo "=== Phase 2: Bootstrap Docker Engine on ${VM_FQDN} ==="

# --- Step 1: Verify connectivity ---
echo "[Step 1] Checking SSH connectivity to ${VM_USER}@${VM_IP}..."
ssh ${SSH_OPTS} "${VM_USER}@${VM_IP}" "exit"
echo "[Step 1] Connected ✓"

# --- Step 2: Install Docker CE from official repos ---
echo "[Step 2] Installing Docker CE prerequisites..."
ssh ${SSH_OPTS} "${VM_USER}@${VM_IP}" \
    "sudo dnf install -y dnf-plugins-core"

echo "[Step 2] Adding Docker CE repository..."
ssh ${SSH_OPTS} "${VM_USER}@${VM_IP}" \
    "sudo dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo"

echo "[Step 2] Installing Docker CE + docker compose plugin..."
ssh ${SSH_OPTS} "${VM_USER}@${VM_IP}" \
    "sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"

# --- Step 3: Enable and start Docker ---
echo "[Step 3] Enabling and starting Docker..."
ssh ${SSH_OPTS} "${VM_USER}@${VM_IP}" \
    "sudo systemctl enable docker && sudo systemctl start docker"

# --- Step 4: Add user to docker group ---
echo "[Step 4] Adding user ${VM_USER} to docker group..."
ssh ${SSH_OPTS} "${VM_USER}@${VM_IP}" \
    "sudo usermod -aG docker ${VM_USER}"

# --- Step 5: Verify installation ---
echo "[Step 5] Verifying Docker installation..."
DOCKER_VERSION=$(ssh ${SSH_OPTS} "${VM_USER}@${VM_IP}" "docker --version 2>/dev/null")
COMPOSE_VERSION=$(ssh ${SSH_OPTS} "${VM_USER}@${VM_IP}" "docker compose version 2>/dev/null")
echo "[Step 5] ${DOCKER_VERSION}"
echo "[Step 5] ${COMPOSE_VERSION}"

# Verify compose plugin works
ssh ${SSH_OPTS} "${VM_USER}@${VM_IP}" "docker compose version" >/dev/null 2>&1
echo "[Step 5] Docker Compose plugin functional ✓"

# --- Step 6: Test hello-world (optional, network-dependent) ---
echo "[Step 6] Running hello-world container to verify..."
ssh ${SSH_OPTS} "${VM_USER}@${VM_IP}" "docker run --rm hello-world 2>/dev/null | head -5 || echo 'Note: hello-world pull failed (network). Proceeding anyway.'"

echo ""
echo "=== Phase 2 complete: Docker Engine installed on ${VM_FQDN} ==="
echo "    Next: ./03-deploy-stack.sh"
