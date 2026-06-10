#!/bin/bash
# ================================================================
# 01-provision-vm.sh — Phase 1: Crear VM en pve-desa
# ================================================================
# Crea VM con Rocky Linux 10, 2 vCPU, 4 GB RAM, 20 GB disco.
# Usa cloud-init con usuario infra.
# ================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=00-env.sh
. "${SCRIPT_DIR}/00-env.sh"

echo "=== Phase 1: Provision VM ${VM_ID} on ${PM_NODE} (${PM_IP}) ==="

# --- Step 1: Verify VM ID is available ---
echo "[Step 1] Checking VM ID ${VM_ID} availability on ${PM_NODE}..."
if ssh ${SSH_OPTS} "root@${PM_IP}" "qm list 2>/dev/null | grep -qw '${VM_ID}'"; then
    echo "ERROR: VM ID ${VM_ID} is already in use on ${PM_NODE}."
    echo "       Run 'ssh root@${PM_IP} qm list' to see existing VMs."
    echo "       Update VM_ID in 00-env.sh and retry."
    exit 1
fi
echo "[Step 1] VM ID ${VM_ID} is available. ✓"

# --- Step 2: Check template exists ---
echo "[Step 2] Checking template ${VM_TEMPLATE}..."
TEMPLATE_ID=$(ssh ${SSH_OPTS} "root@${PM_IP}" "qm list 2>/dev/null | grep '${VM_TEMPLATE}' | awk '{print \$1}' | head -1 || true")
if [ -z "${TEMPLATE_ID}" ]; then
    echo "WARNING: Template '${VM_TEMPLATE}' not found. Searching for any Rocky Linux 10 template..."
    TEMPLATE_ID=$(ssh ${SSH_OPTS} "root@${PM_IP}" "qm list 2>/dev/null | grep -i 'rocky.*10' | awk '{print \$1}' | head -1 || true")
fi

if [ -z "${TEMPLATE_ID}" ]; then
    echo "ERROR: No Rocky Linux 10 template found. Available templates:"
    ssh ${SSH_OPTS} "root@${PM_IP}" "qm list 2>/dev/null | head -20"
    exit 1
fi
echo "[Step 2] Using template ID: ${TEMPLATE_ID} ✓"

# --- Step 3: Clone template and configure ---
echo "[Step 3] Creating VM ${VM_ID} from template ${TEMPLATE_ID}..."
ssh ${SSH_OPTS} "root@${PM_IP}" \
    "qm clone ${TEMPLATE_ID} ${VM_ID} --name ${VM_HOSTNAME} --full --storage shared-vms"

echo "[Step 3] Configuring VM ${VM_ID}..."
ssh ${SSH_OPTS} "root@${PM_IP}" \
    "qm set ${VM_ID} \
        --cores ${VM_CORES} \
        --memory ${VM_MEMORY} \
        --net0 virtio,bridge=${VM_BRIDGE} \
        --scsihw virtio-scsi-pci \
        --agent enabled=1"

echo "[Step 3] Resizing disk to ${VM_DISK}G..."
ssh ${SSH_OPTS} "root@${PM_IP}" \
    "qm resize ${VM_ID} scsi0 ${VM_DISK}G"

# --- Step 4: Cloud-init configuration ---
echo "[Step 4] Configuring cloud-init for user ${VM_USER}..."
ssh ${SSH_OPTS} "root@${PM_IP}" \
    "qm set ${VM_ID} \
        --ciuser ${VM_USER} \
        --cipassword '${VM_PASS}' \
        --ipconfig0 ip=${VM_IP}/${VM_NETMASK},gw=${VM_GATEWAY} \
        --sshkeys /root/.ssh/authorized_keys"

# Set DNS
ssh ${SSH_OPTS} "root@${PM_IP}" \
    "qm set ${VM_ID} \
        --nameserver 192.168.1.1 \
        --searchdomain ${VM_DOMAIN}"

# --- Step 5: Start VM ---
echo "[Step 5] Starting VM ${VM_ID}..."
ssh ${SSH_OPTS} "root@${PM_IP}" "qm start ${VM_ID}"
echo "[Step 5] VM start command issued. Waiting for boot..."

# --- Step 6: Wait for SSH connectivity ---
echo "[Step 6] Waiting for SSH on ${VM_IP} (max 120s)..."
ssh ${SSH_OPTS} "${VM_USER}@${VM_IP}" "exit" 2>/dev/null || true
for i in $(seq 1 24); do
    sleep 5
    if ssh ${SSH_OPTS} "${VM_USER}@${VM_IP}" "exit" 2>/dev/null; then
        echo "[Step 6] SSH reachable after $((i * 5)) seconds ✓"
        break
    fi
    if [ "$i" -eq 24 ]; then
        echo "ERROR: VM ${VM_ID} not reachable via SSH after 120s."
        echo "       Check console: ssh root@${PM_IP} qm terminal ${VM_ID}"
        exit 1
    fi
done

# --- Step 7: Verify OS ---
echo "[Step 7] Verifying OS and connectivity..."
ssh ${SSH_OPTS} "${VM_USER}@${VM_IP}" "cat /etc/rocky-release 2>/dev/null || cat /etc/os-release 2>/dev/null | head -5"
echo ""

echo "=== Phase 1 complete: VM ${VM_ID} (${VM_FQDN}) is ready ==="
echo "    SSH: ssh ${VM_USER}@${VM_IP}"
echo "    Next: ./02-bootstrap-vm.sh"
echo ""
echo "# ================================================================"
echo "# Rollback procedure (if needed):"
echo "#   1. ssh root@${PM_IP} qm stop ${VM_ID}"
echo "#   2. ssh root@${PM_IP} qm destroy ${VM_ID}"
echo "#   3. git revert the changes in this directory"
echo "#   Or run: ./rollback.sh (if created)"
echo "# ================================================================"
