#!/bin/bash
# ================================================================
# 01-gitlab-backup.sh — Daily GitLab Backup
# ================================================================
# Runs gitlab-backup create on the GitLab VM and copies the
# resulting .tar archive to a local backup directory.
# Also backs up /etc/gitlab/gitlab-secrets.json separately.
#
# Schedule: daily via crontab (cron-gitlab-backup)
# ================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-env.sh"

echo "=== GitLab Backup: $(date +%Y-%m-%d_%H:%M:%S) ==="
echo ""

# ---------------------------------------------------------------
# Step 1: Run gitlab-backup create
# ---------------------------------------------------------------
echo "[1/4] Ejecutando gitlab-backup create..."

BACKUP_OUTPUT=$(${VM_SSH} "gitlab-backup create SKIP=artifacts,registry 2>&1")
if echo "${BACKUP_OUTPUT}" | grep -q "DONE"; then
    echo "[1/4] ✅ gitlab-backup create completado"
else
    echo "[1/4] ❌ gitlab-backup falló"
    echo "${BACKUP_OUTPUT}" | tail -20
    exit 1
fi

# ---------------------------------------------------------------
# Step 2: Find latest backup file
# ---------------------------------------------------------------
echo ""
echo "[2/4] Identificando backup generado..."

LATEST_BACKUP=$(${VM_SSH} "ls -t ${GITLAB_BACKUP_DIR}/*.tar 2>/dev/null | head -1" || echo "")
if [ -z "${LATEST_BACKUP}" ]; then
    echo "[2/4] ❌ No se encontró archivo .tar en ${GITLAB_BACKUP_DIR}"
    exit 1
fi

BACKUP_NAME=$(basename "${LATEST_BACKUP}")
BACKUP_SIZE=$(${VM_SSH} "stat -c%s ${LATEST_BACKUP} 2>/dev/null || echo 0")
echo "[2/4] ✅ Backup: ${BACKUP_NAME} ($(( BACKUP_SIZE / 1024 / 1024 ))MB)"

# ---------------------------------------------------------------
# Step 3: Backup secrets file
# ---------------------------------------------------------------
echo ""
echo "[3/4] Respaldando secrets (${SECRETS_FILE})..."

SECRETS_OK=$(${VM_SSH} "test -f ${SECRETS_FILE} && cp ${SECRETS_FILE} ${GITLAB_BACKUP_DIR}/gitlab-secrets.json.$(date +%Y%m%d) && echo 'OK' || echo 'MISSING'")
if [ "${SECRETS_OK}" = "OK" ]; then
    echo "[3/4] ✅ Secrets respaldado"
else
    echo "[3/4] ⚠️  ${SECRETS_FILE} no encontrado — se omitirá"
fi

# ---------------------------------------------------------------
# Step 4: Prune old backups
# ---------------------------------------------------------------
echo ""
echo "[4/4] Purgando backups locales con más de ${BACKUP_RETENTION_DAYS} días..."

${VM_SSH} "find ${GITLAB_BACKUP_DIR} -name '*.tar' -mtime +${BACKUP_RETENTION_DAYS} -delete"
${VM_SSH} "find ${GITLAB_BACKUP_DIR} -name 'gitlab-secrets.json.*' -mtime +${BACKUP_RETENTION_DAYS} -delete"

echo "[4/4] ✅ Purga completada"

echo ""
echo "=== Backup complete: ${BACKUP_NAME} ($(( BACKUP_SIZE / 1024 / 1024 ))MB) ==="
