#!/bin/bash
# ================================================================
# backup.sh — GLPI Backup (mysqldump + Docker Volumes)
# ================================================================
# Creates a timestamped backup bundle containing:
#   - MariaDB SQL dump (compressed with zstd)
#   - GLPI config, plugins, documents, and marketplace tarballs
#
# Usage:
#   ./backup.sh                    # Default backup
#   ./backup.sh /custom/path      # Custom backup directory
#
# Idempotent: re-running overwrites existing archives with the
# same timestamp — no duplicate files.
# ================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../00-env.sh"

BACKUP_TARGET="${1:-${BACKUP_DIR}}"
TIMESTAMP=$(date -u +"%Y%m%dT%H%M%SZ")
BACKUP_PATH="${BACKUP_TARGET}/${TIMESTAMP}"
MYSQLDUMP_OPTS="--single-transaction --routines --triggers --events --quick"

# Ensure backup directory exists
mkdir -p "${BACKUP_PATH}"

echo "=== GLPI Backup — ${TIMESTAMP} ==="
echo "Target: ${BACKUP_PATH}"
echo ""

RC=0

# ---------------------------------------------------------------
# Step 1: MariaDB dump
# ---------------------------------------------------------------
echo "[1/4] Dumping MariaDB database..."
DB_FILE="${BACKUP_PATH}/glpi-database.sql"

if docker exec "${CONTAINER_MARIADB}" \
    mysqldump ${MYSQLDUMP_OPTS} \
    -u "${MYSQL_USER}" \
    -p"${MYSQL_PASSWORD}" \
    "${MYSQL_DATABASE}" \
    > "${DB_FILE}" 2>/dev/null; then
    
    # Compress the dump
    zstd -f --quiet "${DB_FILE}" && rm -f "${DB_FILE}"
    echo "[1/4] Database dump saved: glpi-database.sql.zst ($(stat -c%s "${DB_FILE}.zst" 2>/dev/null || echo "0") bytes)"
else
    echo "[1/4] ERROR: Database dump FAILED" >&2
    echo "[1/4] Check: MariaDB container running? Credentials valid?" >&2
    RC=1
    logger -t glpi-backup "ERROR: MariaDB dump failed"
fi

# ---------------------------------------------------------------
# Step 2: Backup Docker volumes
# ---------------------------------------------------------------
echo "[2/4] Archiving Docker volumes..."

backup_volume() {
    local volume_name="$1"
    local archive_name="$2"
    local volume_path="$3"
    
    echo "[2/4] Archiving volume: ${volume_name}..."
    
    docker run --rm \
        -v "${volume_name}:${volume_path}:ro" \
        -v "${BACKUP_PATH}:/backup" \
        alpine:3.19 \
        tar czf "/backup/${archive_name}-${TIMESTAMP}.tar.gz" \
        -C "${volume_path}" \
        . 2>/dev/null || {
        echo "[2/4] WARNING: Failed to archive volume ${volume_name}" >&2
        logger -t glpi-backup "WARNING: Volume backup failed for ${volume_name}"
        return 1
    }
}

backup_volume "${VOLUME_GLPI_CONFIG}" "glpi-config" "/var/www/html/glpi/config"
backup_volume "${VOLUME_GLPI_PLUGINS}" "glpi-plugins" "/var/www/html/glpi/plugins"
backup_volume "${VOLUME_GLPI_DOCUMENTS}" "glpi-documents" "/var/www/html/glpi/files"
backup_volume "${VOLUME_GLPI_MARKETPLACE}" "glpi-marketplace" "/var/www/html/glpi/marketplace" 2>/dev/null || true

echo "[2/4] Volumes archived"

# ---------------------------------------------------------------
# Step 3: Create backup manifest
# ---------------------------------------------------------------
echo "[3/4] Creating backup manifest..."

MANIFEST="${BACKUP_PATH}/MANIFEST.txt"
{
    echo "GLPI Backup Manifest"
    echo "====================="
    echo "Timestamp: ${TIMESTAMP}"
    echo "GLPI Hostname: ${GLPI_HOSTNAME}"
    echo "MariaDB Database: ${MYSQL_DATABASE}"
    echo ""
    echo "Contents:"
    echo "  - glpi-database.sql.zst (MariaDB dump, zstd-compressed)"
    echo "  - glpi-config-${TIMESTAMP}.tar.gz (GLPI config)"
    echo "  - glpi-plugins-${TIMESTAMP}.tar.gz (GLPI plugins)"
    echo "  - glpi-documents-${TIMESTAMP}.tar.gz (GLPI files/documents)"
    echo "  - glpi-marketplace-${TIMESTAMP}.tar.gz (GLPI marketplace)"
    echo ""
    echo "Restore: scripts/restore.sh ${BACKUP_TARGET}/${TIMESTAMP}"
} > "${MANIFEST}"

echo "[3/4] Manifest created: MANIFEST.txt"

# ---------------------------------------------------------------
# Step 4: Cleanup old backups (retention)
# ---------------------------------------------------------------
echo "[4/4] Cleaning backups older than ${BACKUP_RETENTION_DAYS} days..."

find "${BACKUP_TARGET}" -maxdepth 1 -type d -mtime "+${BACKUP_RETENTION_DAYS}" \
    -exec rm -rf {} \; \
    -print 2>/dev/null || true

echo "[4/4] Cleanup completed"

# ---------------------------------------------------------------
# Summary
# ---------------------------------------------------------------
echo ""
echo "=== Backup Complete ==="
echo "Timestamp: ${TIMESTAMP}"
echo "Location:  ${BACKUP_PATH}"
echo "Status:    $([ ${RC} -eq 0 ] && echo "SUCCESS" || echo "PARTIAL (check errors above)")"

# Log result
if [ ${RC} -eq 0 ]; then
    logger -t glpi-backup "Backup completed successfully: ${BACKUP_PATH}"
else
    logger -t glpi-backup "Backup completed with errors: ${BACKUP_PATH}"
fi

exit ${RC}
