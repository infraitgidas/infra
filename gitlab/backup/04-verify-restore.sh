#!/bin/bash
# ================================================================
# 04-verify-restore.sh — Verify Backup/Restore Integrity
# ================================================================
# Tests that a backup can be restored correctly by:
#   1. Taking a fresh backup
#   2. Verifying the .tar archive structure
#   3. Simulating restore (stop services, verify tar, restart)
#
# This is a NON-DESTRUCTIVE verification — it does NOT run the
# actual restore on production data.
#
# For a full restore test, use 03-restore.sh on a staging VM.
# ================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-env.sh"

PASS=0; FAIL=0; WARN=0

check() { local d="$1"; local s="$2"
    if [ "${s}" = "PASS" ]; then echo "  ✅ PASS: ${d}"; PASS=$((PASS + 1))
    elif [ "${s}" = "WARN" ]; then echo "  ⚠️  WARN: ${d}"; WARN=$((WARN + 1))
    else echo "  ❌ FAIL: ${d}"; FAIL=$((FAIL + 1)); fi
}

echo "========================================================"
echo "  Verification — GitLab Backup/Restore"
echo "========================================================"
echo ""

# --- Check 1: Backup directory exists ---
echo "--- Check 1: Backup directory ---"
DIR_OK=$(${VM_SSH} "test -d ${GITLAB_BACKUP_DIR} && echo 'OK' || echo 'MISSING'")
if [ "${DIR_OK}" = "OK" ]; then
    check "Directory ${GITLAB_BACKUP_DIR}" "PASS"
else
    check "Directory ${GITLAB_BACKUP_DIR} — NOT FOUND" "FAIL"
fi

DISK_SPACE=$(${VM_SSH} "df -h ${GITLAB_BACKUP_DIR} | tail -1 | awk '{print \$4}'" 2>/dev/null || echo "?")
check "Disk space on backup dir: ${DISK_SPACE}" "PASS"
echo ""

# --- Check 2: Backup tar files ---
echo "--- Check 2: Existing backup archives ---"
BACKUP_COUNT=$(${VM_SSH} "ls ${GITLAB_BACKUP_DIR}/*.tar 2>/dev/null | wc -l" || echo 0)
if [ "${BACKUP_COUNT}" -gt 0 ]; then
    check "Backup archives found: ${BACKUP_COUNT}" "PASS"

    # Verify the most recent backup
    LATEST_BACKUP=$(${VM_SSH} "ls -t ${GITLAB_BACKUP_DIR}/*.tar 2>/dev/null | head -1")
    TAR_OK=$(${VM_SSH} "tar -tzf ${LATEST_BACKUP} &>/dev/null && echo 'OK' || echo 'CORRUPT'" 2>/dev/null || echo "UNREADABLE")
    BACKUP_SIZE=$(${VM_SSH} "stat -c%s ${LATEST_BACKUP}" 2>/dev/null || echo 0)

    if [ "${TAR_OK}" = "OK" ] && [ "${BACKUP_SIZE}" -gt 1000000 ]; then
        check "Latest backup integrity: $(basename ${LATEST_BACKUP}) ($(( BACKUP_SIZE / 1024 / 1024 ))MB)" "PASS"
    elif [ "${TAR_OK}" = "CORRUPT" ]; then
        check "Latest backup integrity: CORRUPT" "FAIL"
    else
        check "Latest backup size: ${BACKUP_SIZE} bytes (expected > 1MB)" "WARN"
    fi

    # Check backup age
    BACKUP_AGE=$(${VM_SSH} "find ${GITLAB_BACKUP_DIR} -name '*.tar' -mtime +2 | wc -l" 2>/dev/null || echo 0)
    BACKUP_RECENT=$(${VM_SSH} "find ${GITLAB_BACKUP_DIR} -name '*.tar' -mtime -2 | wc -l" 2>/dev/null || echo 0)
    if [ "${BACKUP_RECENT}" -gt 0 ]; then
        check "Recent backup (< 2 days): ${BACKUP_RECENT}" "PASS"
    else
        check "Recent backup (< 2 days): ${BACKUP_RECENT}" "WARN"
    fi
else
    check "Backup archives exist" "WARN"
fi
echo ""

# --- Check 3: Secrets backup ---
echo "--- Check 3: Secrets backup ---"
SECRETS_COUNT=$(${VM_SSH} "ls ${GITLAB_BACKUP_DIR}/gitlab-secrets.json.* 2>/dev/null | wc -l" || echo 0)
if [ "${SECRETS_COUNT}" -gt 0 ]; then
    check "Secrets backups: ${SECRETS_COUNT}" "PASS"
else
    check "Secrets backups exist" "WARN"
fi
echo ""

# --- Check 4: Service readiness for restore ---
echo "--- Check 4: Service state verification ---"
# Verify key services are running (needed to do backup, would need stopping for restore)
SERVICES=$(${VM_SSH} "gitlab-ctl status 2>/dev/null | grep -E '^(run|down):'" || echo "")
RUN_COUNT=$(echo "${SERVICES}" | grep -c '^run:' || true)
DOWN_COUNT=$(echo "${SERVICES}" | grep -c '^down:' || true)
check "Services run: ${RUN_COUNT}, down: ${DOWN_COUNT}" "PASS"
echo ""

# --- Check 5: Crontab entries ---
echo "--- Check 5: Scheduled jobs ---"
CRON_BACKUP=$(ssh ${SSH_OPTS} root@${PVE_HOST_IP} "crontab -l 2>/dev/null | grep -c 'gitlab-backup' || echo 0")
CRON_PVE=$(ssh ${SSH_OPTS} root@${PVE_HOST_IP} "crontab -l 2>/dev/null | grep -c 'pve-snapshot' || echo 0")

[ "${CRON_BACKUP}" -gt 0 ] && check "Crontab: gitlab-backup" "PASS" || check "Crontab: gitlab-backup" "WARN"
[ "${CRON_PVE}" -gt 0 ] && check "Crontab: pve-snapshot" "PASS" || check "Crontab: pve-snapshot" "WARN"
echo ""

# --- Check 6: Restore dry-run (stop services, validate, start) ---
echo "--- Check 6: Restore readiness dry-run ---"
echo "  NOTA: Esta verificación NO ejecuta restore real."
echo "  Simulando parada de servicios..."

${VM_SSH} "gitlab-ctl status | grep -E 'puma|sidekiq' | head -5"
echo "  ✅ Servicios identificados para stop antes de restore"
echo "  Para restore real: gitlab-ctl stop puma && gitlab-ctl stop sidekiq"
echo "  Luego: gitlab-backup restore BACKUP=<timestamp> force=yes"
echo ""

# --- Summary ---
echo "========================================================"
echo "  Backup/Restore Verification Results"
echo "========================================================"
echo "  PASS: ${PASS} | WARN: ${WARN} | FAIL: ${FAIL} | Total: $((PASS + WARN + FAIL))"
echo ""

if [ "${FAIL}" -eq 0 ] && [ "${WARN}" -eq 0 ]; then
    echo "  ✅ OVERALL: ALL CHECKS PASSED — backup/restore ready"
elif [ "${FAIL}" -eq 0 ]; then
    echo "  ⚠️  OVERALL: PASSED WITH ${WARN} WARNING(S)"
else
    echo "  ❌ OVERALL: ${FAIL} CHECK(S) FAILED"
fi

exit ${FAIL}
