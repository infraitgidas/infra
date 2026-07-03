#!/bin/bash
# ============================================================
# backup.sh — Backup LibreNMS (DB + config) desde CT 210
# ============================================================
# Uso: sudo ./backup.sh [output_dir]
# Por defecto guarda en /var/backups/librenms/
# ============================================================
set -euo pipefail

CT=210
BACKUP_DIR="${1:-/var/backups/librenms}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RETENTION_DAYS=30

mkdir -p "$BACKUP_DIR"

echo "=== Backup LibreNMS — $TIMESTAMP ==="

# 1. Backup DB
echo "[1/3] Dumping MySQL..."
docker exec librenms-db \
  mysqldump -u librenms -p"${DB_PASSWORD}" \
  --single-transaction \
  --routines \
  --triggers \
  librenms \
  > "$BACKUP_DIR/librenms-db_$TIMESTAMP.sql" \
  2>&1 || { echo "ERROR: DB backup failed"; exit 1; }

# 2. Backup config
echo "[2/3] Backing up config..."
docker exec librenms \
  tar czf - \
  -C /data config/ .env \
  > "$BACKUP_DIR/librenms-config_$TIMESTAMP.tar.gz" \
  2>&1 || { echo "ERROR: Config backup failed"; exit 1; }

# 3. Backup RRD data (opcional, ocupa más espacio)
# echo "[3/3] Backing up RRD files..."
# docker exec librenms \
#   tar czf - -C /data rrd/ \
#   > "$BACKUP_DIR/librenms-rrd_$TIMESTAMP.tar.gz" \
#   2>&1 || echo "WARN: RRD backup failed (non-fatal)"

# 4. Compress DB dump
echo "[3/3] Compressing DB dump..."
gzip -f "$BACKUP_DIR/librenms-db_$TIMESTAMP.sql"

# 5. Cleanup old backups
echo "Cleaning backups older than $RETENTION_DAYS days..."
find "$BACKUP_DIR" -name "librenms-*" -type f -mtime +$RETENTION_DAYS -delete

# Summary
echo ""
echo "=== Backup complete ==="
ls -lh "$BACKUP_DIR/librenms-*_$TIMESTAMP*" 2>/dev/null
echo "Location: $BACKUP_DIR"
