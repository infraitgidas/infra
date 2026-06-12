#!/bin/bash
# ================================================================
# 01-provision-vm.sh — Create GitLab VM in Proxmox
# ================================================================
# Provisions a VM with 4 vCPU / 8GB RAM / 80GB disk on PVE host
# using cloud-init template for Rocky Linux 10.
#
# Prerequisites:
#   - Cloud-init template ${VM_TEMPLATE} exists in VM_STORAGE
#   - IP 192.168.1.41 available in the subnet
# ================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-env.sh"

echo "=== Provisioning GitLab VM (${VM_ID}: ${VM_NAME}) on ${PVE_HOST} ==="
echo ""

# ---------------------------------------------------------------
# Step 1: Check VM does not already exist
# ---------------------------------------------------------------
echo "[1/5] Verificando VM ${VM_ID} no existente..."

VM_EXISTS=$(ssh ${SSH_OPTS} root@${PVE_HOST_IP} "qm config ${VM_ID} &>/dev/null && echo 'yes' || echo 'no'")
if [ "${VM_EXISTS}" = "yes" ]; then
    echo "❌ VM ${VM_ID} ya existe en ${PVE_HOST}. Abortando."
    exit 1
fi
echo "[1/5] ✅ VM ${VM_ID} disponible"

# ---------------------------------------------------------------
# Step 1b: Check PVE has enough resources
# ---------------------------------------------------------------
echo ""
echo "[1b/5] Verificando recursos disponibles en ${PVE_HOST}..."

RESOURCE_CHECK=$(ssh ${SSH_OPTS} root@${PVE_HOST_IP} bash -s -- "${VM_CORES}" "${VM_MEMORY}" << 'REMOTE'
    set -euo pipefail
    REQ_CORES="$1"; REQ_MEM="$2"

    # Get node resources via pvesh
    NODE_NAME=$(hostname)
    RESOURCES=$(pvesh get /cluster/resources --type node --output-format json 2>/dev/null || echo "")

    if [ -z "${RESOURCES}" ]; then
        echo "UNKNOWN: pvesh no disponible — skipping check"
        exit 0
    fi

    # Parse CPU and memory from the specific node
    NODE_CPU=$(echo "${RESOURCES}" | python3 -c "
import sys,json
data=json.load(sys.stdin)
for n in data:
    if n.get('node') == '${NODE_NAME}':
        print(n.get('cpu', 0))
        sys.exit(0)
print(0)
" 2>/dev/null || echo "0")

    NODE_MAXCPU=$(echo "${RESOURCES}" | python3 -c "
import sys,json
data=json.load(sys.stdin)
for n in data:
    if n.get('node') == '${NODE_NAME}':
        print(n.get('maxcpu', 0))
        sys.exit(0)
print(0)
" 2>/dev/null || echo "0")

    NODE_MEM=$(echo "${RESOURCES}" | python3 -c "
import sys,json
data=json.load(sys.stdin)
for n in data:
    if n.get('node') == '${NODE_NAME}':
        print(n.get('mem', 0))
        sys.exit(0)
print(0)
" 2>/dev/null || echo "0")

    NODE_MAXMEM=$(echo "${RESOURCES}" | python3 -c "
import sys,json
data=json.load(sys.stdin)
for n in data:
    if n.get('node') == '${NODE_NAME}':
        print(n.get('maxmem', 0))
        sys.exit(0)
print(0)
" 2>/dev/null || echo "0")

    if [ "${NODE_MAXCPU}" -eq 0 ] || [ "${NODE_MAXMEM}" -eq 0 ]; then
        echo "UNKNOWN: unable to read node resources"
        exit 0
    fi

    FREE_CPU=$(( NODE_MAXCPU - $(echo "${NODE_CPU} * ${NODE_MAXCPU}" | bc -l 2>/dev/null | cut -d. -f1 || echo 0) ))
    FREE_MEM_MB=$(( (NODE_MAXMEM - NODE_MEM) / 1024 / 1024 ))

    # Compare with requested resources
    ERRORS=""
    [ "${FREE_CPU}" -lt "${REQ_CORES}" ] && ERRORS="${ERRORS} INSUFFICIENT_CPU"
    [ "${FREE_MEM_MB}" -lt "${REQ_MEM}" ] && ERRORS="${ERRORS} INSUFFICIENT_MEM"

    echo "CPU: free=${FREE_CPU} req=${REQ_CORES}"
    echo "MEM: free=${FREE_MEM_MB}MB req=${REQ_MEM}MB"

    if [ -n "${ERRORS}" ]; then
        echo "FAIL${ERRORS}"
        exit 1
    else
        echo "OK"
    fi
REMOTE
)

RC_OK=$(echo "${RESOURCE_CHECK}" | grep -c "OK" || true)
RC_FAIL=$(echo "${RESOURCE_CHECK}" | grep -c "FAIL" || true)
RC_UNKNOWN=$(echo "${RESOURCE_CHECK}" | grep -c "UNKNOWN" || true)

if [ "${RC_FAIL}" -gt 0 ]; then
    echo "❌ Recursos insuficientes en ${PVE_HOST}:"
    echo "${RESOURCE_CHECK}" | grep -E "CPU:|MEM:" | while read -r line; do echo "   ${line}"; done
    echo "  Recursos requeridos: ${VM_CORES} vCPU / ${VM_MEMORY}MB RAM"
    echo "  Abortando. Libere recursos en ${PVE_HOST} o reduzca las specs de la VM."
    exit 1
elif [ "${RC_OK}" -gt 0 ]; then
    echo "[1b/6] ✅ Recursos suficientes en ${PVE_HOST}:"
    echo "${RESOURCE_CHECK}" | grep -E "CPU:|MEM:" | while read -r line; do echo "   ${line}"; done
elif [ "${RC_UNKNOWN}" -gt 0 ]; then
    echo "[1b/6] ⚠️  No se pudo verificar recursos (pvesh no disponible). Continuando..."
else
    echo "[1b/6] ⚠️  No se pudo verificar recursos. Continuando..."
fi

# ---------------------------------------------------------------
# Step 2: Create VM with qm create
# ---------------------------------------------------------------
echo ""
echo "[2/6] Creando VM ${VM_ID} (${VM_CORES}vCPU / ${VM_MEMORY}MB RAM / ${VM_DISK_SIZE})..."

ssh ${SSH_OPTS} root@${PVE_HOST_IP} bash -s -- "${VM_ID}" "${VM_NAME}" << 'REMOTE'
    set -euo pipefail
    VM_ID="$1"; VM_NAME="$2"
    qm create "${VM_ID}" \
        --name "${VM_NAME}" \
        --cores 4 \
        --sockets 1 \
        --memory 8192 \
        --ostype l26 \
        --net0 virtio,bridge=vmbr0 \
        --scsihw virtio-scsi-pci \
        --agent 1
    echo "✅ VM ${VM_ID} creada"
REMOTE

# ---------------------------------------------------------------
# Step 3: Attach disk
# ---------------------------------------------------------------
echo ""
echo "[3/6] Agregando disco (80G en ${VM_STORAGE})..."

ssh ${SSH_OPTS} root@${PVE_HOST_IP} bash -s -- "${VM_ID}" "${VM_STORAGE}" << 'REMOTE'
    set -euo pipefail
    VM_ID="$1"; STORAGE="$2"
    qm set "${VM_ID}" \
        --scsi0 "${STORAGE}:${VM_DISK_SIZE},format=qcow2,cache=writeback,discard=on"
    echo "✅ Disco 80G agregado"
REMOTE

# ---------------------------------------------------------------
# Step 4: Configure cloud-init
# ---------------------------------------------------------------
echo ""
echo "[4/6] Configurando cloud-init..."

ssh ${SSH_OPTS} root@${PVE_HOST_IP} bash -s -- \
    "${VM_ID}" "${VM_IP}" "${VM_GATEWAY}" "${GITLAB_DOMAIN}" << 'REMOTE'
    set -euo pipefail
    VM_ID="$1"; IP="$2"; GW="$3"; DOMAIN="$4"
    qm set "${VM_ID}" \
        --cicustom "user=local:snippets/gitlab-cloudinit.yml" \
        --ipconfig0 "ip=${IP},gw=${GW}" \
        --searchdomain "gidas.local" \
        --nameserver "192.168.1.1"
    echo "✅ Cloud-init configurado"
REMOTE

# ---------------------------------------------------------------
# Step 5: Start VM and wait for cloud-init
# ---------------------------------------------------------------
echo ""
echo "[5/6] Iniciando VM y esperando cloud-init..."

ssh ${SSH_OPTS} root@${PVE_HOST_IP} "qm start ${VM_ID}"
echo "  Esperando 60s para cloud-init..."
sleep 60

# Verify VM is running
VM_STATUS=$(ssh ${SSH_OPTS} root@${PVE_HOST_IP} "qm status ${VM_ID}" | grep -oP 'status:\s*\K\w+')
if [ "${VM_STATUS}" = "running" ]; then
    echo "[6/6] ✅ VM ${VM_ID} corriendo — IP: ${VM_IP}"
else
    echo "[6/6] ⚠️  VM status: ${VM_STATUS} — verificar manualmente"
fi

echo ""
echo "=== VM provisioning complete ==="
echo "  VM ID: ${VM_ID}"
echo "  Name: ${VM_NAME}"
echo "  IP: ${VM_IP}"
echo "  Resources: ${VM_CORES}vCPU / ${VM_MEMORY}MB / ${VM_DISK_SIZE}"
echo ""
echo "Next: run 02-install-gitlab.sh"
