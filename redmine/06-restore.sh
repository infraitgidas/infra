#!/bin/bash
# ================================================================
# 06-restore.sh — Restore Redmine from backups
# ================================================================
# Lists available backups, restores PostgreSQL from .sql.gz dump,
# and/or restores volume tarballs for files/plugins/themes.
# Use --dry-run to validate without making changes.
#
# Usage:
#   ./06-restore.sh --list                           # show available backups
#   ./06-restore.sh --dry-run --restore-all <DATE>   # validate restore
#   ./06-restore.sh --restore-db <DATE>              # restore DB only
#   ./06-restore.sh --restore-files <DATE>           # restore volumes only
#   ./06-restore.sh --restore-all <DATE>             # restore everything
# ================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=00-env.sh
. "${SCRIPT_DIR}/00-env.sh"

DRY_RUN=false
RESTORE_DB=false
RESTORE_FILES=false
LIST=false
RESTORE_DATE=""
BACKUP_DIR_REMOTE="${BACKUP_DIR}"

usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --list                    List available backups"
    echo "  --restore-db DATE         Restore database from backup (YYYYMMDD_HHMMSS)"
    echo "  --restore-files DATE      Restore volumes from backup (YYYYMMDD_HHMMSS)"
    echo "  --restore-all DATE        Restore DB + volumes from backup"
    echo "  --dry-run                 Validate without making changes"
    echo "  --help, -h                Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 --list"
    echo "  $0 --dry-run --restore-all 20250610_020001"
    echo "  $0 --restore-db 20250610_020001"
    echo ""
    echo "Backup paths (on ${VM_FQDN}):"
    echo "  DB:     ${BACKUP_DIR_REMOTE}/db/redmine_<DATE>.sql.gz"
    echo "  Files:  ${BACKUP_DIR_REMOTE}/files/redmine_files_<DATE>.tar.gz"
    echo "  Volume backups include: redmine_files, redmine_plugins, redmine_themes"
    exit 0
}

# --- Parse arguments ---
while [ $# -gt 0 ]; do
    case "$1" in
        --list) LIST=true; shift ;;
        --restore-db) RESTORE_DB=true; RESTORE_DATE="$2"; shift 2 ;;
        --restore-files) RESTORE_FILES=true; RESTORE_DATE="$2"; shift 2 ;;
        --restore-all) RESTORE_DB=true; RESTORE_FILES=true; RESTORE_DATE="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        --help|-h) usage ;;
        *) echo "ERROR: Unknown option: $1"; usage ;;
    esac
done

# --- Display header ---
echo "=== Redmine Restore Tool ==="
if [ "${DRY_RUN}" = true ]; then
    echo "  *** DRY RUN — no changes will be made ***"
fi
echo ""

# --- List backups ---
if [ "${LIST}" = true ]; then
    echo "Available backups on ${VM_FQDN} (${VM_IP}):"
    echo ""
    echo "--- Database backups ---"
    ssh ${SSH_OPTS} "${VM_USER}@${VM_IP}" \
        "ls -lh ${BACKUP_DIR_REMOTE}/db/ 2>/dev/null || echo '(none)'"
    echo ""
    echo "--- Volume backups (files/plugins/themes) ---"
    ssh ${SSH_OPTS} "${VM_USER}@${VM_IP}" \
        "ls -lh ${BACKUP_DIR_REMOTE}/files/ 2>/dev/null || echo '(none)'"
    echo ""
    echo "To restore, use: $0 --restore-all <DATE>"
    echo "  (DATE is the YYYYMMDD_HHMMSS from the filename, e.g. 20250610_020001)"
    exit 0
fi

# Validate DATE
if [ -z "${RESTORE_DATE}" ]; then
    echo "ERROR: Specify a backup DATE with --restore-db, --restore-files, or --restore-all"
    echo "       Use --list to see available backups."
    exit 1
fi

# --- Restore database ---
if [ "${RESTORE_DB}" = true ]; then
    DB_DUMP="${BACKUP_DIR_REMOTE}/db/redmine_${RESTORE_DATE}.sql.gz"
    echo "[DB] Restoring from: ${DB_DUMP}"

    # Check file exists
    if ! ssh ${SSH_OPTS} "${VM_USER}@${VM_IP}" "test -f '${DB_DUMP}'"; then
        echo "ERROR: Backup file not found: ${DB_DUMP}"
        echo "       Run --list to see available backups."
        exit 1
    fi

    # Validate integrity
    if [ "${DRY_RUN}" = false ]; then
        echo "[DB] Validating dump integrity..."
        ssh ${SSH_OPTS} "${VM_USER}@${VM_IP}" "gunzip -t '${DB_DUMP}'"
        echo "[DB] Integrity check passed ✓"
    else
        echo "[DB] DRY RUN: Would validate: gunzip -t ${DB_DUMP}"
    fi

    if [ "${DRY_RUN}" = true ]; then
        echo "[DB] DRY RUN: Would restore database from: ${DB_DUMP}"
    else
        echo "[DB] Restoring database (this may take a while)..."
        ssh ${SSH_OPTS} "${VM_USER}@${VM_IP}" \
            "gunzip -c '${DB_DUMP}' | docker exec -i redmine-postgres psql -U ${POSTGRES_USER:-redmine} ${POSTGRES_DB:-redmine}"
        echo "[DB] Database restore complete ✓"
    fi
fi

# --- Restore volumes ---
if [ "${RESTORE_FILES}" = true ]; then
    for VOLUME in redmine_files redmine_plugins redmine_themes; do
        TARBALL="${BACKUP_DIR_REMOTE}/files/${VOLUME}_${RESTORE_DATE}.tar.gz"
        echo "[VOL] Restoring ${VOLUME} from: ${TARBALL}"

        # Check file exists
        if ! ssh ${SSH_OPTS} "${VM_USER}@${VM_IP}" "test -f '${TARBALL}'"; then
            echo "WARNING: Backup file not found for ${VOLUME}: ${TARBALL}"
            echo "         Skipping ${VOLUME}."
            continue
        fi

        if [ "${DRY_RUN}" = true ]; then
            echo "[VOL] DRY RUN: Would restore ${VOLUME} from ${TARBALL}"
        else
            echo "[VOL] Restoring ${VOLUME}..."
            ssh ${SSH_OPTS} "${VM_USER}@${VM_IP}" \
                "docker run --rm -v ${VOLUME}:/data -v ${BACKUP_DIR_REMOTE}/files:/backup alpine tar xzf /backup/${VOLUME}_${RESTORE_DATE}.tar.gz -C /data"
            echo "[VOL] ${VOLUME} restore complete ✓"
        fi
    done
fi

# --- Final message ---
if [ "${DRY_RUN}" = true ]; then
    echo ""
    echo "=== Dry run complete. No changes made. ==="
else
    echo ""
    echo "=== Restore complete ==="
fi
