#!/bin/bash
# ================================================================
# sync-ldap.sh — LDAP User Synchronization
# ================================================================
# Wrapper for GLPI's built-in LDAP synchronizer.
# Imports FreeIPA users and groups into GLPI based on the
# configured LDAP directory.
#
# Usage:
#   ./sync-ldap.sh                          # Sync all directories
#   ./sync-ldap.sh --dry-run                # Show what would sync
#   ./sync-ldap.sh --dir 1                  # Sync specific directory ID
#   ./sync-ldap.sh --force                  # Force full re-sync
#
# Designed to run via cron every hour:
#   0 * * * * /opt/infra/itsm/scripts/sync-ldap.sh
# ================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../00-env.sh"

DRY_RUN=false
FORCE=false
DIR_ID="--all"

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=true ;;
        --force) FORCE=true ;;
        --dir=*) DIR_ID="${arg#*=}" ;;
        --dir) echo "Usage: --dir=<ID> (e.g., --dir=1)" >&2; exit 1 ;;
    esac
done

echo "=== LDAP Synchronization ==="

# ---------------------------------------------------------------
# Step 1: Check GLPI container is running
# ---------------------------------------------------------------
echo "[1/4] Checking GLPI container..."

if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_GLPI}$"; then
    echo "ERROR: GLPI container '${CONTAINER_GLPI}' is not running" >&2
    exit 1
fi

echo "[1/4] Container ${CONTAINER_GLPI} is running"

# ---------------------------------------------------------------
# Step 2: Check LDAP directories are configured
# ---------------------------------------------------------------
echo "[2/4] Checking LDAP directories in GLPI..."

LDAP_LIST=$(docker exec "${CONTAINER_GLPI}" php bin/console glpi:ldap:list 2>/dev/null || echo "")

if echo "${LDAP_LIST}" | grep -q "No LDAP directory"; then
    echo "[2/4] No LDAP directories configured"
    echo ""
    echo "Configure one first via CLI:"
    echo "  docker exec ${CONTAINER_GLPI} php bin/console glpi:ldap:add \\"
    echo "    --name=\"FreeIPA - Gidas\" \\"
    echo "    --host=\"${LDAP_HOST}\" \\"
    echo "    --port=${LDAP_PORT} \\"
    echo "    --basedn=\"${LDAP_BASE_DN}\" \\"
    echo "    --rootdn=\"${LDAP_BIND_DN}\" \\"
    echo "    --use-tls=${LDAP_TLS} \\"
    echo "    --rootdn-passwd=\"<password>\""
    echo ""
    echo "See config/ldap-auth.php for all values."
    exit 1
fi

echo "[2/4] LDAP directories found:"
echo "${LDAP_LIST}" | sed 's/^/  /'

# ---------------------------------------------------------------
# Step 3: Run LDAP synchronization
# ---------------------------------------------------------------
echo "[3/4] Running LDAP synchronization..."

if [ "${DRY_RUN}" = true ]; then
    echo "[3/4] [DRY-RUN] Would execute:"
    echo "    docker exec ${CONTAINER_GLPI} php bin/console glpi:ldap:synchronize \\"
    echo "      --no-interaction ${DIR_ID}"
    echo ""
    echo "[3/4] [DRY-RUN] No changes were made"
    exit 0
fi

SYNC_ARGS="--no-interaction"
if [ "${FORCE}" = true ]; then
    SYNC_ARGS="${SYNC_ARGS} --force"
fi

echo "[3/4] Syncing LDAP directories (${DIR_ID})..."

if docker exec "${CONTAINER_GLPI}" \
    php bin/console glpi:ldap:synchronize \
    ${SYNC_ARGS} \
    ${DIR_ID} 2>&1; then
    
    echo "[3/4] ✅ LDAP synchronization completed"
    logger -t glpi-ldap "LDAP sync completed successfully"
else
    RC=$?
    echo "[3/4] ❌ LDAP synchronization FAILED (exit code: ${RC})" >&2
    logger -t glpi-ldap "ERROR: LDAP sync failed with exit code ${RC}"
    exit ${RC}
fi

# ---------------------------------------------------------------
# Step 4: Verify sync results
# ---------------------------------------------------------------
echo "[4/4] Verifying sync results..."

# Count GLPI users
USER_COUNT=$(docker exec "${CONTAINER_GLPI}" \
    php bin/console glpi:user:list 2>/dev/null | wc -l || echo 0)

echo "[4/4] Users in GLPI: approximately ${USER_COUNT}"
echo "[4/4] Sync verification completed"

# ---------------------------------------------------------------
# Summary
# ---------------------------------------------------------------
echo ""
echo "=== LDAP Sync Complete ==="
echo "Synced at: $(date -u)"
echo "Status:    ✅ Success"
echo ""
echo "Next: verify by logging in as an LDAP user"
echo "  e.g., docker exec ${CONTAINER_GLPI} php bin/console glpi:ldap:test --username=jdoe"
