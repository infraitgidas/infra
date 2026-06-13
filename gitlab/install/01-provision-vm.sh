#!/bin/bash
# ================================================================
# 01-provision-vm.sh — Create GitLab VM from template
# ================================================================
# Clones template 108 (rocky-10-template, OVMF UEFI) on
# pve-desa04, configures 4vCPU/8GB/80G + cloud-init.
#
# Prerequisites:
#   - Template ID 108 (rocky-10-template) exists on pve-desa04
#   - IP 192.168.1.41/24 available
# ================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-env.sh"

echo "=== Phase 1: Provision VM ${VM_ID} on ${PM_NODE} (${PM_IP}) ==="

# --- Step 1: Verify VM ID is available ---
echo "[Step 1] Checking VM ID ${VM_ID} availability on ${PM_NODE}..."
if ssh ${SSH_OPTS} "root@${PM_IP}" "qm list 2>/dev/null | grep -qw '${VM_ID}'"; then
    echo "❌ VM ID ${VM_ID} ya está en uso en ${PM_NODE}."
    echo "   Ejecute 'ssh root@${PM_IP} qm list' para ver VMs existentes."
    echo "   Actualice VM_ID en 00-env.sh y reintente."
    exit 1
fi
echo "[Step 1] ✅ VM ID ${VM_ID} disponible"

# --- Step 2: Find template ---
echo "[Step 2] Buscando template ${VM_TEMPLATE}..."
TEMPLATE_ID=$(ssh ${SSH_OPTS} "root@${PM_IP}" \
    "qm list 2>/dev/null | grep '${VM_TEMPLATE}' | grep -v 'redmine' | awk '{print \$1}' | head -1 || true")

if [ -z "${TEMPLATE_ID}" ]; then
    echo "⚠️  Template '${VM_TEMPLATE}' no encontrado. Buscando Rocky Linux 10..."
    TEMPLATE_ID=$(ssh ${SSH_OPTS} "root@${PM_IP}" \
        "qm list 2>/dev/null | grep -i 'rocky.*10' | awk '{print \$1}' | head -1 || true")
fi

if [ -z "${TEMPLATE_ID}" ]; then
    echo "❌ No se encontró template Rocky Linux 10. Templates disponibles:"
    ssh ${SSH_OPTS} "root@${PM_IP}" "qm list 2>/dev/null | head -20"
    exit 1
fi
echo "[Step 2] ✅ Template encontrado: ID ${TEMPLATE_ID} (${VM_TEMPLATE})"

# --- Step 3: Clone template and configure ---
echo "[Step 3] Clonando template ${TEMPLATE_ID} → VM ${VM_ID}..."
ssh ${SSH_OPTS} "root@${PM_IP}" \
    "qm clone ${TEMPLATE_ID} ${VM_ID} --name ${VM_HOSTNAME} --full --storage local-lvm"

echo "[Step 3] Configurando VM ${VM_ID}..."
ssh ${SSH_OPTS} "root@${PM_IP}" \
    "qm set ${VM_ID} \
        --cores ${VM_CORES} \
        --memory ${VM_MEMORY} \
        --net0 virtio,bridge=${VM_BRIDGE} \
        --agent enabled=1"

echo "[Step 3] Redimensionando disco a ${VM_DISK}G..."
ssh ${SSH_OPTS} "root@${PM_IP}" \
    "qm resize ${VM_ID} scsi0 ${VM_DISK}G"

# --- Step 4: Cloud-init configuration ---
echo "[Step 4] Configurando cloud-init (usuario: ${VM_USER})..."
ssh ${SSH_OPTS} "root@${PM_IP}" \
    "qm set ${VM_ID} \
        --ciuser ${VM_USER} \
        --cipassword '${VM_PASS}' \
        --ipconfig0 ip=${VM_IP},gw=${VM_GATEWAY} \
        --sshkeys /root/.ssh/authorized_keys"

# Set DNS
ssh ${SSH_OPTS} "root@${PM_IP}" \
    "qm set ${VM_ID} \
        --nameserver 192.168.1.1 \
        --searchdomain ${VM_DOMAIN}"

# --- Step 5: Start VM ---
echo "[Step 5] Iniciando VM ${VM_ID}..."
ssh ${SSH_OPTS} "root@${PM_IP}" "qm start ${VM_ID}"
echo "[Step 5] ✅ VM start enviado. Esperando boot..."

# --- Step 6: Wait for SSH connectivity ---
echo "[Step 6] Esperando SSH en ${VM_IP%/*} (máx 120s)..."
ssh ${SSH_OPTS} "${VM_USER}@${VM_IP%/*}" "exit" 2>/dev/null || true
for i in $(seq 1 24); do
    sleep 5
    if ssh ${SSH_OPTS} "${VM_USER}@${VM_IP%/*}" "exit" 2>/dev/null; then
        echo "[Step 6] ✅ SSH reachable after $((i * 5)) seconds"
        break
    fi
    if [ "$i" -eq 24 ]; then
        echo "❌ VM ${VM_ID} no reachable via SSH after 120s."
        echo "   Check console: ssh root@${PM_IP} qm terminal ${VM_ID}"
        exit 1
    fi
done

# --- Step 7: Verify OS ---
echo "[Step 7] Verificando OS y conectividad..."
ssh ${SSH_OPTS} "${VM_USER}@${VM_IP%/*}" \
    "cat /etc/rocky-release 2>/dev/null || cat /etc/os-release 2>/dev/null | head -5"
echo ""

echo "=== Phase 1 complete: VM ${VM_ID} (${VM_FQDN}) is ready ==="
echo "    SSH: ssh ${VM_USER}@${VM_IP%/*}"
echo "    Next: ./02-install-gitlab.sh"
echo ""
echo "# ================================================================"
echo "# Rollback:"
echo "#   1. ssh root@${PM_IP} qm stop ${VM_ID}"
echo "#   2. ssh root@${PM_IP} qm destroy ${VM_ID}"
echo "# ================================================================"
