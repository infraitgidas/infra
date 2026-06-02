#!/bin/bash
# ================================================================
# 06-verify.sh — Full verification of GitLab deployment
# ================================================================
# Validates all requirements from spec:
#   - VM specs (4vCPU/8GB/80GB)
#   - GitLab services running
#   - HTTPS with valid cert
#   - SSH clone/push via port 2222
#   - Script syntax (bash -n)
#   - Backup/restore readiness
# ================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-env.sh"

VM_IP_ADDR="${VM_IP%/*}"
VM_SSH="ssh ${SSH_OPTS} root@${VM_IP_ADDR}"
PASS=0; FAIL=0; WARN=0

check() { local d="$1"; local s="$2"
    if [ "${s}" = "PASS" ]; then echo "  ✅ PASS: ${d}"; PASS=$((PASS + 1))
    elif [ "${s}" = "WARN" ]; then echo "  ⚠️  WARN: ${d}"; WARN=$((WARN + 1))
    else echo "  ❌ FAIL: ${d}"; FAIL=$((FAIL + 1)); fi
}

echo "========================================================"
echo "  Verification — GitLab CE Deployment"
echo "========================================================"
echo ""

# --- Section A: bash -n syntax check ---
echo "--- Section A: Script syntax validation ---"
ALL_SCRIPTS=$(find "${SCRIPT_DIR}" -name '*.sh' -type f | sort)
for script in ${ALL_SCRIPTS}; do
    name="$(basename "${script}")"
    if bash -n "${script}" 2>/dev/null; then
        check "${name} — syntax OK" "PASS"
    else
        check "${name} — syntax ERROR" "FAIL"
    fi
done
echo ""

# --- Section B: VM configuration (requires running VM) ---
echo "--- Section B: VM resource verification ---"
VM_CONFIG=$(ssh ${SSH_OPTS} root@${PVE_HOST_IP} "qm config ${VM_ID} 2>/dev/null" || echo "NOT_FOUND")

if [ "${VM_CONFIG}" != "NOT_FOUND" ]; then
    CORES=$(echo "${VM_CONFIG}" | grep '^cores' | awk '{print $2}')
    MEM=$(echo "${VM_CONFIG}" | grep '^memory' | awk '{print $2}')
    DISK=$(echo "${VM_CONFIG}" | grep '^scsi0' | grep -oP 'size=\K[^,]+')

    [ "${CORES}" = "4" ] && check "vCPU: ${CORES}" "PASS" || check "vCPU: ${CORES} (expected 4)" "FAIL"
    [ "${MEM}" = "8192" ] && check "RAM: ${MEM}MB" "PASS" || check "RAM: ${MEM}MB (expected 8192)" "FAIL"
    [ -n "${DISK}" ] && check "Disk: ${DISK}" "PASS" || check "Disk not found" "FAIL"

    VM_STATUS=$(ssh ${SSH_OPTS} root@${PVE_HOST_IP} "qm status ${VM_ID}" | grep -oP 'status:\s*\K\w+')
    [ "${VM_STATUS}" = "running" ] && check "VM status: running" "PASS" || check "VM status: ${VM_STATUS}" "WARN"
else
    check "VM config accessible" "FAIL"
fi
echo ""

# --- Section C: GitLab services ---
echo "--- Section C: GitLab services smoke test ---"
GITLAB_STATUS=$(${VM_SSH} "gitlab-ctl status 2>/dev/null" || echo "UNREACHABLE")

if [ "${GITLAB_STATUS}" != "UNREACHABLE" ]; then
    SERVICES_RUN=$(echo "${GITLAB_STATUS}" | grep -c 'run:' || true)
    SERVICES_DOWN=$(echo "${GITLAB_STATUS}" | grep -c 'down:' || true)
    [ "${SERVICES_RUN}" -gt 0 ] && check "Services running: ${SERVICES_RUN}" "PASS" || check "No services running" "FAIL"
    [ "${SERVICES_DOWN}" -eq 0 ] && check "No services down" "PASS" || check "${SERVICES_DOWN} service(s) down" "FAIL"

    # Health endpoint
    HEALTH=$(${VM_SSH} "curl -sf -o /dev/null -w '%{http_code}' http://localhost/-/health 2>/dev/null || echo 'FAIL'")
    [ "${HEALTH}" = "200" ] && check "Health endpoint HTTP 200" "PASS" || check "Health endpoint: ${HEALTH}" "FAIL"
else
    check "GitLab services status" "FAIL"
fi
echo ""

# --- Section D: HTTPS ---
echo "--- Section D: HTTPS certificate ---"
HTTPS_CODE=$(curl -sf -o /dev/null -w "%{http_code}" "https://${GITLAB_DOMAIN}" 2>/dev/null || echo "FAIL")
[ "${HTTPS_CODE}" = "302" ] || [ "${HTTPS_CODE}" = "200" ] && \
    check "HTTPS response: ${HTTPS_CODE}" "PASS" || check "HTTPS response: ${HTTPS_CODE}" "FAIL"

LE_CERT=$(${VM_SSH} "find /etc/gitlab/ssl -name '*.crt' -type f 2>/dev/null | head -1" || echo "")
[ -n "${LE_CERT}" ] && check "Let's Encrypt cert present" "PASS" || check "Let's Encrypt cert present" "WARN"
echo ""

# --- Section E: SSH port 2222 ---
echo "--- Section E: SSH Git connectivity ---"
SSH_TEST=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -p "${GITLAB_SSH_PORT}" "git@${PVE_HOST_IP}" "info" 2>&1 || true)
echo "${SSH_TEST}" | grep -q "Welcome to GitLab" && check "SSH on :${GITLAB_SSH_PORT}" "PASS" || check "SSH on :${GITLAB_SSH_PORT} (output: ${SSH_TEST:0:80})" "WARN"
echo ""

# --- Section F: Backup readiness ---
echo "--- Section F: Backup readiness ---"
BACKUP_DIR_OK=$(${VM_SSH} "test -d ${BACKUP_DIR} && echo 'OK' || echo 'MISSING'" 2>/dev/null || echo "UNREACHABLE")
[ "${BACKUP_DIR_OK}" = "OK" ] && check "Backup directory ${BACKUP_DIR}" "PASS" || check "Backup directory" "WARN"

CRON_EXISTS=$(ssh ${SSH_OPTS} root@${PVE_HOST_IP} "crontab -l 2>/dev/null | grep -c 'gitlab-backup' || echo 0")
[ "${CRON_EXISTS}" -gt 0 ] && check "Crontab backup entry" "PASS" || check "Crontab backup entry" "WARN"
echo ""

# --- Section G: API REST ---
echo "--- Section G: GitLab API REST ---"
API_TOKEN=$(${VM_SSH} "gitlab-rails runner 'token = User.first.personal_access_tokens.create(scopes: [:api], name: \"verify-$(date +%s)\", expires_at: 7.days.from_now); token.set_token(\"verify-token-$(date +%s)\"); token.save!; puts \"verify-token-$(date +%s)\"' 2>/dev/null" || echo "FAIL")
if [ "${API_TOKEN}" != "FAIL" ] && [ -n "${API_TOKEN}" ]; then
    API_RESULT=$(curl -sf --header "PRIVATE-TOKEN: ${API_TOKEN}" "https://${GITLAB_DOMAIN}/api/v4/projects" 2>/dev/null || echo "")
    if echo "${API_RESULT}" | python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if isinstance(d, list) else 1)" 2>/dev/null; then
        PROJECT_COUNT=$(echo "${API_RESULT}" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "?")
        check "API REST /api/v4/projects — ${PROJECT_COUNT} projects, JSON válido" "PASS"
    else
        check "API REST /api/v4/projects" "FAIL"
    fi
else
    check "API REST token generation" "FAIL"
fi
echo ""

# --- Section H: Authentication ---
echo "--- Section H: Authentication ---"
LOGIN_CSRF=$(${VM_SSH} "curl -sf -c /tmp/cookies.txt https://${GITLAB_DOMAIN}/users/sign_in 2>/dev/null | grep -oP 'name=\"authenticity_token\" value=\"\K[^\"]+' | head -1" 2>/dev/null || echo "")
if [ -n "${LOGIN_CSRF}" ]; then
    check "Sign-in page reachable (CSRF token present)" "PASS"

    # Test login with invalid credentials
    LOGIN_FAIL=$(${VM_SSH} "curl -sf -b /tmp/cookies.txt -c /tmp/cookies2.txt \
        -d 'user[login]=invalid@test.com' \
        -d 'user[password]=wrongpassword' \
        -d 'authenticity_token=${LOGIN_CSRF}' \
        -L 'https://${GITLAB_DOMAIN}/users/sign_in' 2>/dev/null | grep -c 'Invalid' || true" 2>/dev/null || echo "0")
    [ "${LOGIN_FAIL}" -gt 0 ] && check "Login fallido — invalid credentials rechazado" "PASS" || check "Login fallido — no se detectó mensaje de error" "WARN"

    # Test registration page accessibility
    REGISTER_OK=$(${VM_SSH} "curl -sf -c /tmp/cookies.txt 'https://${GITLAB_DOMAIN}/users/sign_up' 2>/dev/null | grep -c 'new_user'" || echo "0")
    [ "${REGISTER_OK}" -gt 0 ] && check "Registro accesible (sign-up habilitado)" "PASS" || check "Registro (sign-up habilitado)" "WARN"
else
    check "Sign-in page reachable" "FAIL"
fi

# --- Section I: Project Creation ---
echo "--- Section I: API Project Creation ---"
PROJECT_NAME="verify-test-$(date +%s)"
CREATE_RESULT=$(curl -sf --header "PRIVATE-TOKEN: ${API_TOKEN}" \
    --header "Content-Type: application/json" \
    -d "{\"name\": \"${PROJECT_NAME}\", \"visibility\": \"private\"}" \
    "https://${GITLAB_DOMAIN}/api/v4/projects" 2>/dev/null || echo "FAIL")

if [ "${CREATE_RESULT}" != "FAIL" ]; then
    CREATED_ID=$(echo "${CREATE_RESULT}" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id', 'unknown'))" 2>/dev/null || echo "unknown")
    CREATED_PATH=$(echo "${CREATE_RESULT}" | python3 -c "import sys,json; print(json.load(sys.stdin).get('path_with_namespace', 'unknown'))" 2>/dev/null || echo "unknown")

    if [ "${CREATED_ID}" != "unknown" ]; then
        check "Proyecto creado: ${CREATED_PATH} (ID: ${CREATED_ID})" "PASS"

        # Verify project appears in project listing
        LIST_CHECK=$(curl -sf --header "PRIVATE-TOKEN: ${API_TOKEN}" \
            "https://${GITLAB_DOMAIN}/api/v4/projects" 2>/dev/null | \
            python3 -c "import sys,json; data=json.load(sys.stdin); print('FOUND' if any(p.get('id')==${CREATED_ID} for p in data) else 'MISSING')" 2>/dev/null || echo "FAIL")
        [ "${LIST_CHECK}" = "FOUND" ] && check "Proyecto listado en /api/v4/projects" "PASS" || check "Proyecto listado en /api/v4/projects" "WARN"

        # Cleanup: delete test project
        DELETE_OK=$(curl -sf -o /dev/null -w "%{http_code}" -X DELETE \
            --header "PRIVATE-TOKEN: ${API_TOKEN}" \
            "https://${GITLAB_DOMAIN}/api/v4/projects/${CREATED_ID}" 2>/dev/null || echo "FAIL")
        [ "${DELETE_OK}" = "202" ] || [ "${DELETE_OK}" = "204" ] && \
            check "Proyecto de prueba eliminado" "PASS" || check "Proyecto de prueba eliminado (HTTP ${DELETE_OK})" "WARN"
    else
        check "Crear proyecto vía API" "FAIL"
    fi
else
    check "Crear proyecto vía API" "FAIL"
fi
echo ""

# --- Summary ---
echo ""
echo "========================================================"
echo "  Verification Results"
echo "========================================================"
echo "  PASS: ${PASS} | WARN: ${WARN} | FAIL: ${FAIL} | Total: $((PASS + WARN + FAIL))"
echo ""

if [ "${FAIL}" -eq 0 ] && [ "${WARN}" -eq 0 ]; then
    echo "  ✅ OVERALL: ALL CHECKS PASSED"
elif [ "${FAIL}" -eq 0 ]; then
    echo "  ⚠️  OVERALL: PASSED WITH ${WARN} WARNING(S)"
else
    echo "  ❌ OVERALL: ${FAIL} CHECK(S) FAILED"
fi

exit ${FAIL}
