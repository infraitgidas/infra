#!/bin/bash
# ================================================================
# 03-restore.sh — GitLab Restore Procedure
# ================================================================
# Restores GitLab from a gitlab-backup .tar archive.
# Also restores gitlab-secrets.json from backup retention.
#
# Usage:
#   ./03-restore.sh <backup-tar-path>
#   ./03-restore.sh /var/opt/gitlab/backups/123456789_2025_01_01_14.0.0_gitlab_backup.tar
# ================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-env.sh"

# --- Validate argument ---
BACKUP_FILE="${1:-}"
if [ -z "${BACKUP_FILE}" ]; then
    echo "❌ Uso: $0 <backup-tar-path>"
    echo "  Ejemplo: $0 /var/opt/gitlab/backups/123456789_2025_01_01_14.0.0_gitlab_backup.tar"
    echo ""
    echo "Backups disponibles en la VM:"
    ${VM_SSH} "ls -lh ${GITLAB_BACKUP_DIR}/*.tar 2>/dev/null || echo '(ninguno)'"
    exit 1
fi

BACKUP_NAME=$(basename "${BACKUP_FILE}")
BACKUP_TIMESTAMP=$(echo "${BACKUP_NAME}" | sed 's/_gitlab_backup\.tar$//')

echo "=== Restoring GitLab from: ${BACKUP_NAME} ==="
echo ""

# ---------------------------------------------------------------
# Step 1: Verify backup file exists
# ---------------------------------------------------------------
echo "[1/6] Verificando archivo de backup..."

FILE_OK=$(${VM_SSH} "test -f ${BACKUP_FILE} && echo 'OK' || echo 'MISSING'")
if [ "${FILE_OK}" != "OK" ]; then
    echo "[1/6] ❌ Backup file ${BACKUP_FILE} no encontrado en la VM"
    echo "  Copie el archivo a la VM primero:"
    echo "  scp /ruta/local/${BACKUP_NAME} root@${VM_IP}:${GITLAB_BACKUP_DIR}/"
    exit 1
fi
echo "[1/6] ✅ Backup file verificado ($(${VM_SSH} "stat -c%s ${BACKUP_FILE}" 2>/dev/null | numfmt --to=iec 2>/dev/null || echo '?')"

# ---------------------------------------------------------------
# Step 2: Stop services that connect to the database
# ---------------------------------------------------------------
echo ""
echo "[2/6] Deteniendo servicios que conectan a la DB..."

${VM_SSH} "gitlab-ctl stop puma"
${VM_SSH} "gitlab-ctl stop sidekiq"
echo "[2/6] ✅ Servicios detenidos (puma, sidekiq)"

# ---------------------------------------------------------------
# Step 3: Confirm restore
# ---------------------------------------------------------------
echo ""
echo "[3/6] Verificando estado de servicios restantes..."

${VM_SSH} "gitlab-ctl status"
echo ""
echo "⚠️  IMPORTANTE: La restauración SOBREESCRIBIRÁ la base de datos actual."
echo "  Backup: ${BACKUP_NAME}"
echo "  Fecha: $(date -d "@$(echo ${BACKUP_TIMESTAMP} | cut -c1-10)" 2>/dev/null || echo 'desconocida')"
echo -n "  ¿Continuar? (yes/no): "

# ---------------------------------------------------------------
# Step 4: Restore backup
# ---------------------------------------------------------------
echo ""
echo "[4/6] Ejecutando gitlab-backup restore..."

${VM_SSH} "gitlab-backup restore BACKUP=${BACKUP_TIMESTAMP} force=yes" || {
    echo "[4/6] ❌ Restauración falló"
    echo "  Verificar: ${VM_SSH} 'tail -50 /var/log/gitlab/gitlab-backup/current'"
    exit 1
}
echo "[4/6] ✅ Restauración completada"

# ---------------------------------------------------------------
# Step 5: Restore secrets
# ---------------------------------------------------------------
echo ""
echo "[5/6] Restaurando gitlab-secrets.json..."

# Find latest secrets backup
LATEST_SECRETS=$(${VM_SSH} "ls -t ${GITLAB_BACKUP_DIR}/gitlab-secrets.json.* 2>/dev/null | head -1" || echo "")
if [ -n "${LATEST_SECRETS}" ]; then
    ${VM_SSH} "cp ${LATEST_SECRETS} /etc/gitlab/gitlab-secrets.json"
    ${VM_SSH} "chmod 600 /etc/gitlab/gitlab-secrets.json"
    echo "[5/6] ✅ Secrets restaurados desde ${LATEST_SECRETS}"
else
    echo "[5/6] ⚠️  No se encontró backup de secrets — usar copia manual si existe"
fi

# ---------------------------------------------------------------
# Step 6: Reconfigure and restart
# ---------------------------------------------------------------
echo ""
echo "[6/6] Reconfigurando e iniciando servicios..."

${VM_SSH} "gitlab-ctl reconfigure" && \
    ${VM_SSH} "gitlab-ctl restart" && \
    echo "[6/6] ✅ GitLab reconfigured y servicios iniciados"

echo ""
echo "=== Restore complete: ${BACKUP_NAME} ==="
echo "  Verifique: https://${GITLAB_DOMAIN}"
echo "  Verifique repos vía SSH puerto ${GITLAB_SSH_PORT}"
