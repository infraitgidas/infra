#!/bin/bash
# ================================================================
# 01-provision-vm.sh — Create GitLab VM in Proxmox (shared storage)
# ================================================================
# Clona un template cloud-init Rocky Linux 10 en el shared storage NFS
# y configura cloud-init para la VM GitLab.
#
# Prerequisitos:
#   - Template cloud-init ${VM_TEMPLATE} (ID ${VM_TEMPLATE_ID}) en pve-desa01
#   - Storage NFS ${VM_STORAGE} accesible desde el cluster (f3-shared-storage)
#   - IP 192.168.1.41 disponible en la subnet
#   - Snippet subido: scp gitlab/snippets/gitlab-cloudinit.yml root@pve-desa01:/var/lib/vz/snippets/
# ================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-env.sh"

echo "=== Provisioning GitLab VM (${VM_ID}: ${VM_NAME}) on ${PVE_HOST} ==="
echo ""

# ---------------------------------------------------------------
# Step 1: Check VM does not already exist
# ---------------------------------------------------------------
echo "[1/6] Verificando VM ${VM_ID} no existente..."

VM_EXISTS=$(ssh ${SSH_OPTS} root@${PVE_HOST_IP} "qm config ${VM_ID} &>/dev/null && echo 'yes' || echo 'no'")
if [ "${VM_EXISTS}" = "yes" ]; then
    echo "❌ VM ${VM_ID} ya existe. Abortando."
    exit 1
fi
echo "[1/6] ✅ VM ${VM_ID} disponible"

# ---------------------------------------------------------------
# Step 1b: Check PVE host resources
# ---------------------------------------------------------------
echo ""
echo "[1b/6] Verificando recursos disponibles en ${PVE_HOST}..."

RESOURCE_CHECK=$(ssh ${SSH_OPTS} root@${PVE_HOST_IP} bash -s -- "${VM_CORES}" "${VM_MEMORY}" << 'REMOTE'
    set -euo pipefail
    REQ_CORES="$1"; REQ_MEM="$2"
    NODE_NAME=$(hostname)
    RESOURCES=$(pvesh get /cluster/resources --type node --output-format json 2>/dev/null || echo "")

    if [ -z "${RESOURCES}" ]; then
        echo "UNKNOWN: pvesh no disponible"
        exit 0
    fi

    NODE_CPU=$(echo "${RESOURCES}" | python3 -c "
import sys,json
data=json.load(sys.stdin)
for n in data:
    if n.get('node') == '${NODE_NAME}':
        print(n.get('cpu', 0)); sys.exit(0)
print(0)" 2>/dev/null || echo "0")

    NODE_MAXCPU=$(echo "${RESOURCES}" | python3 -c "
import sys,json
data=json.load(sys.stdin)
for n in data:
    if n.get('node') == '${NODE_NAME}':
        print(n.get('maxcpu', 0)); sys.exit(0)
print(0)" 2>/dev/null || echo "0")

    NODE_MEM=$(echo "${RESOURCES}" | python3 -c "
import sys,json
data=json.load(sys.stdin)
for n in data:
    if n.get('node') == '${NODE_NAME}':
        print(n.get('mem', 0)); sys.exit(0)
print(0)" 2>/dev/null || echo "0")

    NODE_MAXMEM=$(echo "${RESOURCES}" | python3 -c "
import sys,json
data=json.load(sys.stdin)
for n in data:
    if n.get('node') == '${NODE_NAME}':
        print(n.get('maxmem', 0)); sys.exit(0)
print(0)" 2>/dev/null || echo "0")

    if [ "${NODE_MAXCPU}" -eq 0 ] || [ "${NODE_MAXMEM}" -eq 0 ]; then
        echo "UNKNOWN: unable to read node resources"
        exit 0
    fi

    FREE_CPU=$(( NODE_MAXCPU - $(echo "${NODE_CPU} * ${NODE_MAXCPU}" | bc -l 2>/dev/null | cut -d. -f1 || echo 0) ))
    FREE_MEM_MB=$(( (NODE_MAXMEM - NODE_MEM) / 1024 / 1024 ))

    ERRORS=""
    [ "${FREE_CPU}" -lt "${REQ_CORES}" ] && ERRORS="${ERRORS} INSUFFICIENT_CPU"
    [ "${FREE_MEM_MB}" -lt "${REQ_MEM}" ] && ERRORS="${ERRORS} INSUFFICIENT_MEM"

    echo "CPU: free=${FREE_CPU} req=${REQ_CORES}"
    echo "MEM: free=${FREE_MEM_MB}MB req=${REQ_MEM}MB"
    [ -n "${ERRORS}" ] && { echo "FAIL${ERRORS}"; exit 1; } || echo "OK"
REMOTE
)

if echo "${RESOURCE_CHECK}" | grep -q "FAIL"; then
    echo "❌ Recursos insuficientes en ${PVE_HOST}:"
    echo "${RESOURCE_CHECK}" | grep -E "CPU:|MEM:" | while read -r line; do echo "   ${line}"; done
    exit 1
elif echo "${RESOURCE_CHECK}" | grep -q "OK"; then
    echo "[1b/6] ✅ Recursos suficientes en ${PVE_HOST}:"
    echo "${RESOURCE_CHECK}" | grep -E "CPU:|MEM:" | while read -r line; do echo "   ${line}"; done
else
    echo "[1b/6] ⚠️  No se pudo verificar recursos. Continuando..."
fi

# ---------------------------------------------------------------
# Step 1c: Check template exists
# ---------------------------------------------------------------
echo ""
echo "[1c/6] Verificando template ${VM_TEMPLATE} (ID ${VM_TEMPLATE_ID})..."

TEMPLATE_EXISTS=$(ssh ${SSH_OPTS} root@${PVE_HOST_IP} \
    "qm config ${VM_TEMPLATE_ID} &>/dev/null && echo 'yes' || echo 'no'")
if [ "${TEMPLATE_EXISTS}" != "yes" ]; then
    echo "❌ Template ${VM_TEMPLATE} (ID ${VM_TEMPLATE_ID}) no encontrado en ${PVE_HOST}"
    echo "   Crear template cloud-init Rocky Linux 10 o ajustar VM_TEMPLATE_ID en 00-env.sh"
    exit 1
fi
echo "[1c/6] ✅ Template ${VM_TEMPLATE} (ID ${VM_TEMPLATE_ID}) encontrado"

# ---------------------------------------------------------------
# Step 1d: Check shared storage exists
# ---------------------------------------------------------------
echo ""
echo "[1d/6] Verificando storage ${VM_STORAGE}..."

STORAGE_EXISTS=$(ssh ${SSH_OPTS} root@${PVE_HOST_IP} \
    "pvesm status 2>/dev/null | grep -q '^${VM_STORAGE}\s' && echo 'yes' || echo 'no'")
if [ "${STORAGE_EXISTS}" != "yes" ]; then
    echo "⚠️  Storage ${VM_STORAGE} no encontrado en el cluster"
    echo "   Asegurarse de que f3-shared-storage esté desplegado"
    echo "   Continuando con storage local ${VM_STORAGE_LOCAL} como fallback..."
    VM_STORAGE="${VM_STORAGE_LOCAL}"
fi
echo "[1d/6] ✅ Usando storage: ${VM_STORAGE}"

# ---------------------------------------------------------------
# Step 2: Clone VM from template
# ---------------------------------------------------------------
echo ""
echo "[2/6] Clonando VM ${VM_ID} desde template ${VM_TEMPLATE} (ID ${VM_TEMPLATE_ID})..."
echo "  Storage destino: ${VM_STORAGE}"

ssh ${SSH_OPTS} root@${PVE_HOST_IP} bash -s -- \
    "${VM_TEMPLATE_ID}" "${VM_ID}" "${VM_NAME}" "${VM_STORAGE}" << 'REMOTE'
    set -euo pipefail
    TPL_ID="$1"; VM_ID="$2"; NAME="$3"; STORAGE="$4"

    qm clone "${TPL_ID}" "${VM_ID}" \
        --name "${NAME}" \
        --storage "${STORAGE}" \
        --full 1

    # Ajustar recursos post-clone
    qm set "${VM_ID}" \
        --cores 4 \
        --sockets 1 \
        --memory 8192 \
        --scsihw virtio-scsi-pci \
        --net0 virtio,bridge=vmbr0 \
        --agent 1

    echo "✅ VM ${VM_ID} clonada y configurada"
REMOTE

# ---------------------------------------------------------------
# Step 3: Resize disk
# ---------------------------------------------------------------
echo ""
echo "[3/6] Redimensionando disco a ${VM_DISK_SIZE}..."

ssh ${SSH_OPTS} root@${PVE_HOST_IP} "qm resize ${VM_ID} scsi0 ${VM_DISK_SIZE}"
echo "[3/6] ✅ Disco redimensionado a ${VM_DISK_SIZE}"

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
echo "  Esperando 90s para cloud-init..."
sleep 90

VM_STATUS=$(ssh ${SSH_OPTS} root@${PVE_HOST_IP} "qm status ${VM_ID}" | grep -oP 'status:\s*\K\w+')
if [ "${VM_STATUS}" = "running" ]; then
    echo "[5/6] ✅ VM ${VM_ID} corriendo — IP: ${VM_IP%/*}"
else
    echo "[5/6] ⚠️  VM status: ${VM_STATUS} — verificar manualmente"
fi

# ---------------------------------------------------------------
# Step 6: Verify SSH access to VM
# ---------------------------------------------------------------
echo ""
echo "[6/6] Verificando acceso SSH a la VM..."

sleep 10
if ssh ${SSH_OPTS} -o StrictHostKeyChecking=accept-new root@${VM_IP%/*} "hostname && echo 'SSH_OK'" &>/dev/null; then
    echo "[6/6] ✅ Acceso SSH a ${VM_IP%/*} verificado"
else
    echo "[6/6] ⚠️  No se pudo conectar por SSH — verificar manualmente"
    echo "   IP: ${VM_IP%/*}"
    echo "   Posible causa: cloud-init aún ejecutándose o SSH key no configurada"
fi

echo ""
echo "=== VM provisioning complete ==="
echo "  VM ID: ${VM_ID}"
echo "  Name: ${VM_NAME}"
echo "  IP: ${VM_IP%/*}"
echo "  Storage: ${VM_STORAGE}"
echo "  Resources: ${VM_CORES}vCPU / ${VM_MEMORY}MB / ${VM_DISK_SIZE}"
echo ""
echo "Next: run 02-install-gitlab.sh"
echo ""
echo "NOTA: Si se usó VM_STORAGE_LOCAL como fallback, migrar a shared storage:"
echo "  # Detener VM, migrar disco:"
echo "  qm stop ${VM_ID}"
echo "  qm move_disk ${VM_ID} scsi0 shared-gitlab"
echo "  qm start ${VM_ID}"
