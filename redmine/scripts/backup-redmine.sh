#!/bin/bash
# ================================================================
# backup-redmine.sh — Redmine Backup with Email Delivery
# ================================================================
# Creates daily backup of PostgreSQL database and files, then sends
# the backup archive via email using SMTP.
#
# Config (via .env):
#   BACKUP_RETENTION_DAYS    Days to keep local backups (default: 7)
#   SMTP_SERVER              SMTP host (default: smtp.office365.com)
#   SMTP_PORT                SMTP port (default: 587)
#   SMTP_USER                SMTP username
#   SMTP_PASSWORD            SMTP password
#   SMTP_FROM                From address (default: infrait@frlp.utn.edu.ar)
#   SMTP_TO                  Recipient address
#
# Cron: 0 3 * * * /opt/infra/redmine/scripts/backup-redmine.sh
# ================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REDMINE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BACKUP_DIR="/var/backups/redmine"
DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/redmine-${DATE}.tar.gz"
LOG_FILE="/var/log/redmine-backup.log"

# Load environment
if [ -f "${REDMINE_DIR}/.env" ]; then
    set -a
    source "${REDMINE_DIR}/.env"
    set +a
fi

# --- Settings ---
RETENTION="${BACKUP_RETENTION_DAYS:-7}"
SMTP_SERVER="${SMTP_SERVER:-smtp.office365.com}"
SMTP_PORT="${SMTP_PORT:-587}"
SMTP_USER="${SMTP_USER:-infrait@frlp.utn.edu.ar}"
SMTP_PASSWORD="${SMTP_PASSWORD:-}"
SMTP_FROM="${SMTP_FROM:-infrait@frlp.utn.edu.ar}"
SMTP_TO="${SMTP_TO:-infrait@frlp.utn.edu.ar}"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

fail() {
    log "[ERROR] $*" >&2
    exit 1
}

# ================================================================
# Step 1: Ensure backup directory exists
# ================================================================
mkdir -p "$BACKUP_DIR"
log "=== Redmine Backup ==="
log "Date: ${DATE}"
log "Retention: ${RETENTION} days"

# ================================================================
# Step 2: Dump PostgreSQL database
# ================================================================
log "[1/4] Dumping PostgreSQL database..."

DB_DUMP="${BACKUP_DIR}/redmine-db-${DATE}.sql"
if docker exec redmine-postgres pg_dump -U "${POSTGRES_USER:-redmine}" -d "${POSTGRES_DB:-redmine}" \
    --clean --if-exists --no-owner > "$DB_DUMP" 2>/dev/null; then
    DB_SIZE=$(wc -c < "$DB_DUMP" 2>/dev/null || echo 0)
    log "  DB dump: ${DB_DUMP} ($(numfmt --to=iec-i $DB_SIZE 2>/dev/null || echo "${DB_SIZE} bytes"))"
else
    fail "pg_dump failed"
fi

# ================================================================
# Step 3: Archive DB dump + files
# ================================================================
log "[2/4] Creating archive..."

FILES_VOLUME="/var/lib/docker/volumes/redmine_files/_data"
if [ -d "$FILES_VOLUME" ]; then
    tar -czf "$BACKUP_FILE" \
        -C "$BACKUP_DIR" "redmine-db-${DATE}.sql" \
        -C /var/lib/docker/volumes "redmine_files/_data" \
        -C "$REDMINE_DIR" "plugins" "themes" 2>/dev/null || {
        tar -czf "$BACKUP_FILE" -C "$BACKUP_DIR" "redmine-db-${DATE}.sql"
    }
else
    tar -czf "$BACKUP_FILE" -C "$BACKUP_DIR" "redmine-db-${DATE}.sql"
fi

BACKUP_SIZE=$(stat --format=%s "$BACKUP_FILE" 2>/dev/null || echo 0)
log "  Archive: ${BACKUP_FILE} ($(numfmt --to=iec-i $BACKUP_SIZE 2>/dev/null || echo "${BACKUP_SIZE} bytes"))"

# Clean up temp SQL dump
rm -f "$DB_DUMP"

# ================================================================
# Step 4: Send via email
# ================================================================
log "[3/4] Sending backup via email..."

if [ -n "$SMTP_PASSWORD" ] && [ "$SMTP_PASSWORD" != "CHANGE_ME_ADD_SMTP_PASSWORD" ]; then
    if [ -f "$BACKUP_FILE" ]; then
        python3 /dev/stdin << PYEOF
import smtplib, email.mime.text, email.mime.base, email.mime.multipart, os
from email import encoders

msg = email.mime.multipart.MIMEMultipart()
msg['Subject'] = 'Redmine Backup - ${DATE}'
msg['From'] = '${SMTP_FROM}'
msg['To'] = '${SMTP_TO}'

body = email.mime.text.MIMEText('Redmine daily backup attached.\n\nDate: ${DATE}\nSize: ${BACKUP_SIZE} bytes')
msg.attach(body)

backup_file = '${BACKUP_FILE}'
with open(backup_file, 'rb') as f:
    part = email.mime.base.MIMEBase('application', 'gzip')
    part.set_payload(f.read())
    encoders.encode_base64(part)
    part.add_header('Content-Disposition', 'attachment', filename='redmine-${DATE}.tar.gz')
    msg.attach(part)

s = smtplib.SMTP('${SMTP_SERVER}', ${SMTP_PORT})
s.starttls()
s.login('${SMTP_USER}', '${SMTP_PASSWORD}')
s.send_message(msg)
s.quit()
print('Backup sent to ${SMTP_TO}')
PYEOF
        log "  Backup sent to ${SMTP_TO}"
    else
        log "  [ERROR] Backup file not found for email"
    fi
else
    log "  [SKIP] No SMTP_PASSWORD configured. Backup saved locally only."
fi

# ================================================================
# Step 5: Clean old backups
# ================================================================
log "[4/4] Cleaning backups older than ${RETENTION} days..."
find "$BACKUP_DIR" -name "redmine-*.tar.gz" -type f -mtime "+${RETENTION}" -delete 2>/dev/null || true

# Summary
BACKUP_SIZE=$(stat --format=%s "$BACKUP_FILE" 2>/dev/null || echo 0)
log "=== Backup Complete ==="
log "File: ${BACKUP_FILE} ($(numfmt --to=iec-i $BACKUP_SIZE 2>/dev/null || echo "${BACKUP_SIZE} bytes"))"
log "Email: $([ -n "$SMTP_PASSWORD" ] && [ "$SMTP_PASSWORD" != "CHANGE_ME_ADD_SMTP_PASSWORD" ] && echo 'yes' || echo 'no (no SMTP_PASSWORD)')"
log "Retention: ${RETENTION} days"
