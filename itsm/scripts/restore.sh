#!/bin/bash
# ================================================================
# restore.sh — GLPI Restore from Backup
# ================================================================
# Restores GLPI from a backup bundle created by backup.sh.
#
# Usage:
#   ./restore.sh /var/backups/glpi/20260401T030000Z
#
# This script:
#   1. Verifies the backup bundle integrity
#   2. Stops the Docker Compose stack
#   3. Restores MariaDB from SQL dump
#   4. Restores Docker volumes from tarballs
#   5. Restarts the stack
#   6. Runs a health check
# ================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../00-env.sh"

if [ $# -lt 1 ]; then
    echo "Usage: $0 <backup-timestamp-dir>"
    echo ""
    echo "Available backups:"
    ls -1 "${BACKUP_DIR}/" 2>/dev/null || echo "(no backups found in ${BACKUP_DIR})"
    exit 1
fi

BACKUP_PATH="$1"

if [ ! -d "${BACKUP_PATH}" ]; then
    echo "ERROR: Backup directory not found: ${BACKUP_PATH}" >&2
    exit 1
fi

echo "=== GLPI Restore ==="
echo "Source: ${BACKUP_PATH}"
echo ""

# ---------------------------------------------------------------
# Step 1: Verify backup bundle integrity
# ---------------------------------------------------------------
echo "[1/7] Verifying backup bundle integrity..."

REQUIRED_FILES=(
    "glpi-database.sql.zst"
)

MISSING=0
for f in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "${BACKUP_PATH}/${f}" ]; then
        echo "[1/7] MISSING: ${f}" >&2
        MISSING=$((MISSING + 1))
    else
        echo "[1/7] FOUND: ${f}"
    fi
done

# Check for volume tarballs (at least one)
VOLUME_TARS=$(find "${BACKUP_PATH}" -maxdepth 1 -name 'glpi-*.tar.gz' 2>/dev/null | wc -l)
if [ "${VOLUME_TARS}" -eq 0 ]; then
    echo "[1/7] WARNING: No volume tarballs found — only database will be restored"
else
    echo "[1/7] FOUND ${VOLUME_TARS} volume tarball(s)"
fi

if [ ${MISSING} -gt 0 ]; then
    echo "[1/7] ERROR: ${MISSING} required file(s) missing — aborting" >&2
    exit 1
fi

echo "[1/7] Backup bundle integrity verified"

# Optional: read manifest
if [ -f "${BACKUP_PATH}/MANIFEST.txt" ]; then
    echo "[1/7] Backup manifest:"
    sed 's/^/    /' "${BACKUP_PATH}/MANIFEST.txt"
fi

# ---------------------------------------------------------------
# Step 2: Stop the stack
# ---------------------------------------------------------------
echo "[2/7] Stopping Docker Compose stack..."

docker compose -f "${COMPOSE_FILE}" down --timeout 30
echo "[2/7] Stack stopped"

# ---------------------------------------------------------------
# Step 3: Remove old volumes
# ---------------------------------------------------------------
echo "[3/7] Removing old volumes for clean restore..."

VOLUMES=(
    "${VOLUME_MARIADB}"
    "${VOLUME_GLPI_CONFIG}"
    "${VOLUME_GLPI_PLUGINS}"
    "${VOLUME_GLPI_DOCUMENTS}"
)

for vol in "${VOLUMES[@]}"; do
    if docker volume inspect "${vol}" &>/dev/null; then
        docker volume rm "${vol}"
        echo "[3/7] Removed volume: ${vol}"
    fi
done

echo "[3/7] Old volumes removed"

# ---------------------------------------------------------------
# Step 4: Restore volumes from tarballs
# ---------------------------------------------------------------
echo "[4/7] Restoring Docker volumes..."

restore_volume() {
    local volume_name="$1"
    local tarball_pattern="$2"
    local volume_path="$3"
    
    local tarball
    tarball=$(find "${BACKUP_PATH}" -maxdepth 1 -name "${tarball_pattern}" -print -quit 2>/dev/null || true)
    
    if [ -z "${tarball}" ]; then
        echo "[4/7] SKIP: No tarball found for ${volume_name}"
        return 0
    fi
    
    echo "[4/7] Restoring ${volume_name} from $(basename "${tarball}")..."
    
    # Create volume and extract
    docker volume create "${volume_name}" >/dev/null
    docker run --rm \
        -v "${volume_name}:${volume_path}" \
        -v "${BACKUP_PATH}:/backup:ro" \
        alpine:3.19 \
        tar xzf "/backup/$(basename "${tarball}")" \
        -C "${volume_path}" 2>/dev/null || {
        echo "[4/7] ERROR: Failed to restore volume ${volume_name}" >&2
        return 1
    }
    
    echo "[4/7] Restored: ${volume_name}"
}

restore_volume "${VOLUME_GLPI_CONFIG}" "glpi-config-*.tar.gz" "/var/www/html/glpi/config"
restore_volume "${VOLUME_GLPI_PLUGINS}" "glpi-plugins-*.tar.gz" "/var/www/html/glpi/plugins"
restore_volume "${VOLUME_GLPI_DOCUMENTS}" "glpi-documents-*.tar.gz" "/var/www/html/glpi/files"
restore_volume "${VOLUME_GLPI_MARKETPLACE}" "glpi-marketplace-*.tar.gz" "/var/www/html/glpi/marketplace" 2>/dev/null || true

echo "[4/7] Volume restore completed"

# ---------------------------------------------------------------
# Step 5: Restore MariaDB from dump
# ---------------------------------------------------------------
echo "[5/7] Restoring MariaDB database..."

# Create MariaDB volume
docker volume create "${VOLUME_MARIADB}" >/dev/null

# Start a temporary MariaDB container to restore
docker run -d \
    --name glpi-restore-mysql \
    -v "${VOLUME_MARIADB}:/var/lib/mysql" \
    -e MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD}" \
    -e MYSQL_DATABASE="${MYSQL_DATABASE}" \
    -e MYSQL_USER="${MYSQL_USER}" \
    -e MYSQL_PASSWORD="${MYSQL_PASSWORD}" \
    mariadb:10.11 \
    --skip-log-bin \
    2>/dev/null

echo "[5/7] Waiting for MariaDB to start..."
sleep 15

# Decompress and restore
echo "[5/7] Decompressing and importing SQL dump..."
zstd -d --quiet "${BACKUP_PATH}/glpi-database.sql.zst" -o /tmp/glpi-restore.sql 2>/dev/null

if docker exec -i glpi-restore-mysql \
    mysql -u root -p"${MYSQL_ROOT_PASSWORD}" "${MYSQL_DATABASE}" \
    < /tmp/glpi-restore.sql 2>/dev/null; then
    echo "[5/7] Database restore completed"
else
    echo "[5/7] ERROR: Database restore FAILED" >&2
    docker stop glpi-restore-mysql >/dev/null 2>&1
    docker rm glpi-restore-mysql >/dev/null 2>&1
    rm -f /tmp/glpi-restore.sql
    exit 1
fi

rm -f /tmp/glpi-restore.sql

# Stop the temporary container
docker stop glpi-restore-mysql >/dev/null 2>&1
docker rm glpi-restore-mysql >/dev/null 2>&1

echo "[5/7] Database restored to volume"

# ---------------------------------------------------------------
# Step 6: Start the stack
# ---------------------------------------------------------------
echo "[6/7] Starting Docker Compose stack..."

docker compose -f "${COMPOSE_FILE}" up -d --wait 2>/dev/null || {
    echo "[6/7] Starting stack (without --wait)..."
    docker compose -f "${COMPOSE_FILE}" up -d
}

echo "[6/7] Stack started"

# ---------------------------------------------------------------
# Step 7: Health check
# ---------------------------------------------------------------
echo "[7/7] Running health check..."

sleep 15

if docker exec "${CONTAINER_GLPI}" curl -sf -o /dev/null "http://localhost/" 2>/dev/null; then
    echo "[7/7] GLPI is responding"
else
    echo "[7/7] WARNING: GLPI health check failed — check container logs" >&2
fi

# Verify database connection
if docker exec "${CONTAINER_GLPI}" php -r "
    \$db = new mysqli('${MYSQL_HOST}', '${MYSQL_USER}', '${MYSQL_PASSWORD}', '${MYSQL_DATABASE}');
    echo \$db->connect_error ? 'FAILED: ' . \$db->connect_error : 'OK';
    \$db->close();
" 2>/dev/null | grep -q "OK"; then
    echo "[7/7] Database connection verified"
else
    echo "[7/7] WARNING: Database connection check failed" >&2
fi

# ---------------------------------------------------------------
# Summary
# ---------------------------------------------------------------
echo ""
echo "=== Restore Complete ==="
echo "Source:    ${BACKUP_PATH}"
echo "Status:    ✅ Restore completed"
echo ""
echo "Next steps:"
echo "  1. Verify data: open https://${GLPI_HOSTNAME} in browser"
echo "  2. Check for any missing plugins or configuration"
echo "  3. Run a test ticket lifecycle"
echo ""

logger -t glpi-restore "Restore completed from ${BACKUP_PATH}"
