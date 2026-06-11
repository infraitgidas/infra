#!/bin/bash
# ================================================================
# 08-backup-grafana.sh — Backup grafana.db with rotation
# ================================================================
# Backs up the Grafana SQLite database to a local directory with
# timestamp, compresses it, and keeps N daily backups.
#
# Usage:
#   ./08-backup-grafana.sh                 # manual run
#   ./08-backup-grafana.sh --install-cron  # install daily cron
# ================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-env.sh"

BACKUP_DIR="${BACKUP_DIR:-${SCRIPT_DIR}/backups/grafana}"
RETENTION_DAYS=${BACKUP_RETENTION_DAYS:-7}
GRAFANA_DB="${GRAFANA_DATA}/grafana.db"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/grafana-${TIMESTAMP}.db.gz"

# --- Functions ---

run_backup() {
    echo "[$(date '+%H:%M:%S')] Iniciando backup de Grafana DB..."

    mkdir -p "${BACKUP_DIR}"

    # The CT sg-monitoring lives behind pve-ad (.31).
    # We connect through pve-ad and use pct exec/pull for the container.
    SSH_CT="ssh ${SSH_OPTS} root@${CT_MONITORING_IP} pct exec ${CT_MONITORING_ID} --"

    # Check if DB exists in the container
    if ! ${SSH_CT} "[ -f '${GRAFANA_DB}' ]" 2>/dev/null; then
        echo "❌ grafana.db no encontrado en CT ${CT_MONITORING_ID}:${GRAFANA_DB}"
        exit 1
    fi

    # Backup — stream via pct exec + pct pull for transactional safety.
    # Use sqlite3 .backup to get a consistent snapshot even during writes.
    echo "[$(date '+%H:%M:%S')] Respaldando ${CT_MONITORING_HOST}:${GRAFANA_DB} → ${BACKUP_FILE}..."

    # Step 1: create a consistent snapshot inside the container
    ssh ${SSH_OPTS} root@${CT_MONITORING_IP} \
        "pct exec ${CT_MONITORING_ID} -- sqlite3 '${GRAFANA_DB}' '.backup /tmp/grafana-backup-ct.db'" \
        2>/dev/null

    # Step 2: pull the snapshot to the host, then to local
    ssh ${SSH_OPTS} root@${CT_MONITORING_IP} \
        "pct pull ${CT_MONITORING_ID} /tmp/grafana-backup-ct.db /tmp/grafana-backup-host.db" \
        2>/dev/null

    # Step 3: fetch locally and compress
    ssh ${SSH_OPTS} root@${CT_MONITORING_IP} \
        "cat /tmp/grafana-backup-host.db" 2>/dev/null | gzip > "${BACKUP_FILE}"

    # Step 4: clean up temp files
    ssh ${SSH_OPTS} root@${CT_MONITORING_IP} \
        "rm -f /tmp/grafana-backup-host.db && pct exec ${CT_MONITORING_ID} -- rm -f /tmp/grafana-backup-ct.db" \
        2>/dev/null

    # Verify
    if [ -f "${BACKUP_FILE}" ] && [ -s "${BACKUP_FILE}" ]; then
        SIZE=$(du -h "${BACKUP_FILE}" | cut -f1)
        echo "[$(date '+%H:%M:%S')] ✅ Backup creado: ${BACKUP_FILE} (${SIZE})"
    else
        echo "❌ Error: archivo de backup vacío o no creado"
        exit 1
    fi

    # Rotate old backups
    echo "[$(date '+%H:%M:%S')] Rotando backups con más de ${RETENTION_DAYS} días..."
    find "${BACKUP_DIR}" -name "grafana-*.db.gz" -type f -mtime "+${RETENTION_DAYS}" -delete 2>/dev/null || true
    REMAINING=$(find "${BACKUP_DIR}" -name "grafana-*.db.gz" -type f | wc -l)
    echo "[$(date '+%H:%M:%S')] ✅ Backup completado — ${REMAINING} backups retenidos en ${BACKUP_DIR}"
}

install_cron() {
    CRON_SCHEDULE="${BACKUP_CRON_SCHEDULE:-0 3 * * *}"
    SCRIPT_PATH="$(readlink -f "$0")"
    CRON_JOB="${CRON_SCHEDULE} ${SCRIPT_PATH}"

    # Check if already installed
    if crontab -l 2>/dev/null | grep -qF "${SCRIPT_PATH}"; then
        echo "ℹ️  Cron job ya existe para ${SCRIPT_PATH}"
        crontab -l | grep -F "${SCRIPT_PATH}"
        return
    fi

    (crontab -l 2>/dev/null; echo "${CRON_JOB}") | crontab -
    echo "✅ Cron job instalado: ${CRON_SCHEDULE} ${SCRIPT_PATH}"
    echo "   Para cambiar: crontab -e"
    echo "   Para remover: crontab -l | grep -v '${SCRIPT_PATH}' | crontab -"
}

# --- Main ---

case "${1:-}" in
    --install-cron)
        install_cron
        ;;
    --help|-h)
        echo "Uso: $0 [--install-cron]"
        echo ""
        echo "  (sin args)    Ejecuta backup manual"
        echo "  --install-cron Instala cron diario a las 3 AM"
        echo ""
        echo "Variables de entorno:"
        echo "  BACKUP_RETENTION_DAYS  Días a retener (default: 7)"
        echo "  BACKUP_CRON_SCHEDULE   Schedule cron (default: '0 3 * * *')"
        ;;
    *)
        run_backup
        ;;
esac
