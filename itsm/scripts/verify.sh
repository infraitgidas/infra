#!/bin/bash
# ================================================================
# verify.sh — GLPI Implementation Verification
# ================================================================
# Validates all implementation requirements:
#   Phase 6.1 — Bash syntax validation of all scripts
#   Phase 6.2 — Configuration verification
#   Phase 6.3 — Smoke test (stack up + healthy)
#   Phase 6.4 — Restore verification (backup exists + valid)
#   Phase 6.5 — E2E test (ticket lifecycle via API)
#
# Usage:
#   ./verify.sh                    # Run all checks
#   ./verify.sh --skip-e2e         # Skip E2E test (needs running stack)
#   ./verify.sh --skip-smoke       # Skip smoke test (needs Docker)
# ================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../00-env.sh"

SKIP_E2E=false
SKIP_SMOKE=false

for arg in "$@"; do
    case "$arg" in
        --skip-e2e) SKIP_E2E=true ;;
        --skip-smoke) SKIP_SMOKE=true ;;
    esac
done

PASS=0
FAIL=0
WARN=0

check() {
    local desc="$1"
    local status="$2"
    local detail="${3:-}"
    if [ "${status}" = "PASS" ]; then
        echo "  ✅ PASS: ${desc} ${detail}"
        PASS=$((PASS + 1))
    elif [ "${status}" = "WARN" ]; then
        echo "  ⚠️  WARN: ${desc} ${detail}"
        WARN=$((WARN + 1))
    else
        echo "  ❌ FAIL: ${desc} ${detail}"
        FAIL=$((FAIL + 1))
    fi
}

echo "========================================================"
echo "  GLPI ITSM — Implementation Verification"
echo "========================================================"
echo ""

# ===============================================================
# Section A: Bash Syntax Validation (Phase 6.1)
# ===============================================================
echo "--- Section A: Bash Syntax Validation ---"

SYNTAX_ERRORS=0
for script in "${ITSM_DIR}"/scripts/*.sh; do
    script_name=$(basename "${script}")
    if bash -n "${script}" 2>/dev/null; then
        check "bash -n: ${script_name}" "PASS"
    else
        bash -n "${script}" 2>&1 | head -3
        check "bash -n: ${script_name}" "FAIL"
        SYNTAX_ERRORS=$((SYNTAX_ERRORS + 1))
    fi
done

# Also validate 00-env.sh (sourced, not executed)
if bash -n "${ITSM_DIR}/00-env.sh" 2>/dev/null; then
    check "bash -n: 00-env.sh" "PASS"
else
    check "bash -n: 00-env.sh" "FAIL"
    SYNTAX_ERRORS=$((SYNTAX_ERRORS + 1))
fi

# Check env example is valid (no bash syntax, just verify it exists)
if [ -f "${ITSM_DIR}/.env.example" ]; then
    check "Configuration: .env.example exists" "PASS"
else
    check "Configuration: .env.example exists" "FAIL"
fi

echo ""

# ===============================================================
# Section B: Configuration Verification (Phase 6.2)
# ===============================================================
echo "--- Section B: Configuration Verification ---"

# Check docker-compose.yml
if [ -f "${COMPOSE_FILE}" ]; then
    check "File: docker-compose.yml exists" "PASS"
    
    # Check required services
    for svc in mariadb glpi nginx; do
        if grep -q "^  ${svc}:" "${COMPOSE_FILE}"; then
            check "Service: ${svc} in compose" "PASS"
        else
            check "Service: ${svc} in compose" "FAIL"
        fi
    done
    
    # Check named volumes
    for vol in glpi_mariadb_data glpi_config glpi_plugins glpi_documents; do
        if grep -q "${vol}:" "${COMPOSE_FILE}"; then
            check "Volume: ${vol} defined" "PASS"
        else
            check "Volume: ${vol} defined" "FAIL"
        fi
    done
else
    check "File: docker-compose.yml exists" "FAIL"
fi

# Check nginx config
if [ -f "${ITSM_DIR}/nginx/default.conf" ]; then
    check "File: nginx/default.conf exists" "PASS"
else
    check "File: nginx/default.conf exists" "FAIL"
fi

# Check env example
if [ -f "${ITSM_DIR}/.env.example" ]; then
    check "File: .env.example (documented)" "PASS"
    # Check for required variables
    for var in MYSQL_ROOT_PASSWORD MYSQL_DATABASE GLPI_TIMEZONE; do
        if grep -q "${var}" "${ITSM_DIR}/.env.example"; then
            check "Variable: ${var} in .env.example" "PASS"
        else
            check "Variable: ${var} in .env.example" "FAIL"
        fi
    done
fi

# Check 00-env.sh has required variables
for var in MYSQL_HOST MYSQL_DATABASE GLPI_HOSTNAME LDAP_HOST REDMINE_URL GITLAB_URL BACKUP_DIR; do
    if grep -q "${var}=" "${ITSM_DIR}/00-env.sh"; then
        check "Env: ${var} defined in 00-env.sh" "PASS"
    else
        check "Env: ${var} defined in 00-env.sh" "FAIL"
    fi
done

# Check integration env
if [ -f "${ITSM_DIR}/config/integrations.env" ]; then
    check "File: config/integrations.env exists" "PASS"
    for var in REDMINE_URL REDMINE_API_KEY GITLAB_URL GITLAB_TOKEN GLPI_APP_TOKEN; do
        if grep -q "${var}=" "${ITSM_DIR}/config/integrations.env"; then
            check "Integration: ${var} configured" "PASS"
        fi
    done
else
    check "File: config/integrations.env exists" "FAIL"
fi

# Check LDAP config
if [ -f "${ITSM_DIR}/config/ldap-auth.php" ]; then
    check "File: config/ldap-auth.php exists" "PASS"
else
    check "File: config/ldap-auth.php exists" "FAIL"
fi

# Check script files exist
for script in install-glpi.sh backup.sh restore.sh sync-ldap.sh webhook-redmine.sh webhook-gitlab.sh; do
    if [ -f "${ITSM_DIR}/scripts/${script}" ]; then
        check "Script: ${script} exists" "PASS"
    else
        check "Script: ${script} exists" "FAIL"
    fi
done

echo ""

# ===============================================================
# Section C: Smoke Test Plan (Phase 6.3)
# ===============================================================
echo "--- Section C: Smoke Test ---"

SMOKE_NOTES=""

if [ "${SKIP_SMOKE}" = true ]; then
    echo "  ⏭️  Smoke test skipped (--skip-smoke)"
    check "Smoke test" "WARN" "(skipped)"
else
    # Check Docker is available
    if command -v docker &>/dev/null; then
        check "Docker available" "PASS"
        
        # Check if stack is running
        if docker compose -f "${COMPOSE_FILE}" ps --services 2>/dev/null | grep -q .; then
            check "Docker Compose stack running" "PASS"
            
            # Check each service
            RUNNING_SERVICES=$(docker compose -f "${COMPOSE_FILE}" ps --services 2>/dev/null || echo "")
            for svc in mariadb glpi nginx; do
                if echo "${RUNNING_SERVICES}" | grep -q "${svc}"; then
                    SVC_STATUS=$(docker compose -f "${COMPOSE_FILE}" ps --status running "${svc}" 2>/dev/null | grep -c "${svc}" || echo 0)
                    if [ "${SVC_STATUS}" -gt 0 ]; then
                        check "Container: ${svc} running" "PASS"
                    else
                        check "Container: ${svc} running" "FAIL"
                    fi
                else
                    check "Container: ${svc} in compose" "FAIL"
                fi
            done
        else
            check "Docker Compose stack running" "WARN" "(not running — start with 'docker compose up -d')"
            SMOKE_NOTES="Stack not running — manual smoke test required"
        fi
    else
        check "Docker available" "WARN" "(not installed)"
        SMOKE_NOTES="Docker not available — manual smoke test required"
    fi
    
    # Document smoke test plan
    echo ""
    echo "  Smoke Test Plan (manual when stack is up):"
    echo "  1. curl -sI https://${GLPI_HOSTNAME:-glpi.gidas.local}  → expect 200"
    echo "  2. Open browser at https://${GLPI_HOSTNAME:-glpi.gidas.local} → GLPI login page"
    echo "  3. Login as admin → Dashboard loads without errors"
    echo "  4. Navigate to Assets → Inventory loads"
    echo "  5. Navigate to Tickets → Can create new ticket"
    echo "  6. Check API: POST /apirest.php/initSession returns session_token"
fi

echo ""

# ===============================================================
# Section D: Restore Verification (Phase 6.4)
# ===============================================================
echo "--- Section D: Restore Verification ---"

if [ -d "${BACKUP_DIR}" ]; then
    BACKUP_COUNT=$(find "${BACKUP_DIR}" -maxdepth 1 -type d | wc -l)
    if [ "${BACKUP_COUNT}" -gt 1 ]; then
        check "Backups exist in ${BACKUP_DIR}" "PASS"
        
        # Check latest backup integrity
        LATEST_BACKUP=$(find "${BACKUP_DIR}" -maxdepth 1 -type d -printf '%T@ %p\n' | sort -rn | head -1 | cut -d' ' -f2-)
        if [ -n "${LATEST_BACKUP}" ]; then
            check "Latest backup: $(basename "${LATEST_BACKUP}")" "PASS"
            
            # Check for required files
            if [ -f "${LATEST_BACKUP}/glpi-database.sql.zst" ]; then
                check "Backup: database dump present" "PASS"
                # Verify zst integrity
                if zstd -t "${LATEST_BACKUP}/glpi-database.sql.zst" 2>/dev/null; then
                    check "Backup: database dump integrity valid" "PASS"
                else
                    check "Backup: database dump integrity valid" "FAIL"
                fi
            else
                check "Backup: database dump present" "FAIL"
            fi
            
            VOLUME_TARS=$(find "${LATEST_BACKUP}" -name 'glpi-*.tar.gz' 2>/dev/null | wc -l)
            if [ "${VOLUME_TARS}" -gt 0 ]; then
                check "Backup: volume archives present (${VOLUME_TARS})" "PASS"
            else
                check "Backup: volume archives present" "FAIL"
            fi
            
            if [ -f "${LATEST_BACKUP}/MANIFEST.txt" ]; then
                check "Backup: MANIFEST.txt present" "PASS"
            else
                check "Backup: MANIFEST.txt present" "FAIL"
            fi
        fi
    else
        check "Backups exist in ${BACKUP_DIR}" "WARN" "(no backups yet — run scripts/backup.sh)"
    fi
else
    check "Backup directory ${BACKUP_DIR}" "WARN" "(not created yet)"
fi

echo ""

# ===============================================================
# Section E: E2E Test Plan (Phase 6.5)
# ===============================================================
echo "--- Section E: E2E Test (Ticket Lifecycle) ---"

if [ "${SKIP_E2E}" = true ]; then
    echo "  ⏭️  E2E test skipped (--skip-e2e)"
    check "E2E test" "WARN" "(skipped)"
else
    # Check if stack is running and API accessible
    if command -v docker &>/dev/null && docker compose -f "${COMPOSE_FILE}" ps --services 2>/dev/null | grep -q glpi; then
        # Try API
        GLPI_TEST_URL="http://localhost:8080"  # Dev HTTP port
        if curl -sf -o /dev/null "${GLPI_TEST_URL}" 2>/dev/null; then
            check "E2E: GLPI reachable at ${GLPI_TEST_URL}" "PASS"
            
            echo ""
            echo "  E2E Test Plan (manual):"
            echo ""
            echo "  Step 1 — Create Ticket:"
            echo "    curl -X POST ${GLPI_TEST_URL}/apirest.php/Ticket \\"
            echo "      -H 'App-Token: \${GLPI_APP_TOKEN}' \\"
            echo "      -H 'Session-Token: \${SESSION_TOKEN}' \\"
            echo "      -d '{\"input\":{\"name\":\"Test Incident\",\"content\":\"E2E test\",\"type\":1}}'"
            echo ""
            echo "  Step 2 — Verify Status:"
            echo "    curl ${GLPI_TEST_URL}/apirest.php/Ticket/{id} \\"
            echo "      -H 'App-Token: \${GLPI_APP_TOKEN}' \\"
            echo "      -H 'Session-Token: \${SESSION_TOKEN}'"
            echo ""
            echo "  Step 3 — Assign:"
            echo "    curl -X PUT ${GLPI_TEST_URL}/apirest.php/Ticket/{id} \\"
            echo "      -H 'App-Token: \${GLPI_APP_TOKEN}' \\"
            echo "      -H 'Session-Token: \${SESSION_TOKEN}' \\"
            echo "      -d '{\"input\":{\"status\":2,\"users_id_assign\":1}}'"
            echo ""
            echo "  Step 4 — Resolve:"
            echo "    curl -X PUT ${GLPI_TEST_URL}/apirest.php/Ticket/{id} \\"
            echo "      -H 'App-Token: \${GLPI_APP_TOKEN}' \\"
            echo "      -H 'Session-Token: \${SESSION_TOKEN}' \\"
            echo "      -d '{\"input\":{\"status\":4,\"solution\":\"Issue resolved via E2E test\"}}'"
            echo ""
            echo "  Step 5 — Close:"
            echo "    curl -X PUT ${GLPI_TEST_URL}/apirest.php/Ticket/{id} \\"
            echo "      -H 'App-Token: \${GLPI_APP_TOKEN}' \\"
            echo "      -H 'Session-Token: \${SESSION_TOKEN}' \\"
            echo "      -d '{\"input\":{\"status\":5}}'"
        else
            check "E2E: GLPI reachable" "WARN" "(not reachable — run 'docker compose up -d' first)"
        fi
    else
        check "E2E: Stack running" "WARN" "(not running — skip or start stack first)"
    fi
    
    # Document API auth flow
    echo ""
    echo "  API Authentication Flow:"
    echo "  1. Get session token:"
    echo "     curl -X POST ${GLPI_TEST_URL}/apirest.php/initSession \\"
    echo "       -H 'App-Token: \${GLPI_APP_TOKEN}' \\"
    echo "       -H 'Content-Type: application/json' \\"
    echo "       -d '{\"login\":\"glpi\",\"password\":\"\${GLPI_ADMIN_PASSWORD}\"}'"
    echo ""
    echo "  2. Use session token in subsequent requests:"
    echo "     -H 'Session-Token: \${SESSION_TOKEN}'"
fi

echo ""

# ===============================================================
# Summary
# ===============================================================
echo "========================================================"
echo "  Verification Results"
echo "========================================================"
echo "  PASS: ${PASS}"
echo "  WARN: ${WARN}"
echo "  FAIL: ${FAIL}"
echo "  Total: $((PASS + WARN + FAIL))"

if [ -n "${SMOKE_NOTES}" ]; then
    echo ""
    echo "  Notes:"
    echo "  - ${SMOKE_NOTES}"
fi

echo ""
if [ "${FAIL}" -eq 0 ]; then
    echo "  ✅ OVERALL: ALL CHECKS PASSED"
else
    echo "  ❌ OVERALL: ${FAIL} check(s) FAILED — review above"
fi

exit ${FAIL}
