#!/bin/bash
# ================================================================
# 02-pve-snapshot.sh — PVE Weekly Snapshot for GitLab VM
# ================================================================
# Creates a Proxmox VM snapshot for fast VM-level recovery.
# Automatically removes snapshots older than retention period.
#
# Schedule: weekly via crontab (cron-pve-snapshot)
# ================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-env.sh"

SNAPSHOT_DATE=$(date +%Y%m%d)
SNAPSHOT_NAME="${PVE_SNAPSHOT_PREFIX}-${SNAPSHOT_DATE}"

echo "=== PVE Snapshot: ${SNAPSHOT_NAME} for VM ${VM_ID} ==="
echo ""

# ---------------------------------------------------------------
# Step 1: Check VM exists and is running
# ---------------------------------------------------------------
echo "[1/4] Verificando VM ${VM_ID}..."

VM_EXISTS=$(ssh ${SSH_OPTS} root@${PVE_HOST_IP} "qm config ${VM_ID} &>/dev/null && echo 'yes' || echo 'no'")
if [ "${VM_EXISTS}" != "yes" ]; then
    echo "[1/4] ❌ VM ${VM_ID} no existe en ${PVE_HOST_IP}"
    exit 1
fi

VM_STATUS=$(ssh ${SSH_OPTS} root@${PVE_HOST_IP} "qm status ${VM_ID}" | grep -oP 'status:\s*\K\w+')
echo "[1/4] ✅ VM ${VM_ID} — status: ${VM_STATUS}"

# ---------------------------------------------------------------
# Step 2: Remove old snapshots beyond retention
# ---------------------------------------------------------------
echo ""
echo "[2/4] Purgando snapshots anteriores (retención: ${PVE_SNAPSHOT_RETENTION})..."

OLD_SNAPSHOTS=$(ssh ${SSH_OPTS} root@${PVE_HOST_IP} "qm listsnapshot ${VM_ID} 2>/dev/null | grep '${PVE_SNAPSHOT_PREFIX}' | tail -n +${PVE_SNAPSHOT_RETENTION} | awk '{print \$2}'" || echo "")
for snap in ${OLD_SNAPSHOTS}; do
    ssh ${SSH_OPTS} root@${PVE_HOST_IP} "qm delsnapshot ${VM_ID} ${snap}" && \
        echo "  Eliminado: ${snap}"
done
echo "[2/4] ✅ Purga de snapshots completada"

# ---------------------------------------------------------------
# Step 3: Create new snapshot
# ---------------------------------------------------------------
echo ""
echo "[3/4] Creando snapshot ${SNAPSHOT_NAME}..."

ssh ${SSH_OPTS} root@${PVE_HOST_IP} "qm snapshot ${VM_ID} ${SNAPSHOT_NAME} --description 'GitLab weekly snapshot ${SNAPSHOT_DATE}'" && \
    echo "[3/4] ✅ Snapshot ${SNAPSHOT_NAME} creado"

# ---------------------------------------------------------------
# Step 4: Verify snapshot
# ---------------------------------------------------------------
echo ""
echo "[4/4] Verificando snapshot..."

SNAP_OK=$(ssh ${SSH_OPTS} root@${PVE_HOST_IP} "qm listsnapshot ${VM_ID} 2>/dev/null | grep -c ${SNAPSHOT_NAME}" || echo 0)
if [ "${SNAP_OK}" -gt 0 ]; then
    echo "[4/4] ✅ Snapshot ${SNAPSHOT_NAME} verificado"
else
    echo "[4/4] ❌ Snapshot no encontrado en lista"
    exit 1
fi

echo ""
echo "=== PVE Snapshot complete: ${SNAPSHOT_NAME} ==="
