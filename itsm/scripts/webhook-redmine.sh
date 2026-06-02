#!/bin/bash
# ================================================================
# webhook-redmine.sh — GLPI → Redmine integration
# ================================================================
# Polls GLPI for new/updated Changes and creates corresponding
# issues in Redmine via REST API.
#
# Usage:
#   ./webhook-redmine.sh                    # Run once
#   ./webhook-redmine.sh --dry-run          # Show what would be done
#   ./webhook-redmine.sh --force            # Process all, ignoring state
#
# Designed to run via cron every 5 minutes:
#   */5 * * * * /opt/infra/itsm/scripts/webhook-redmine.sh
# ================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../00-env.sh"
source "${SCRIPT_DIR}/../config/integrations.env"

DRY_RUN=false
FORCE=false
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=true ;;
        --force) FORCE=true ;;
    esac
done

# Ensure state directory exists
mkdir -p "${STATE_DIR}"
STATE_FILE="${STATE_DIR}/redmine-last-poll"

# ---------------------------------------------------------------
# Helper: Call GLPI REST API
# ---------------------------------------------------------------
glpi_api() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"
    
    local session_token
    session_token=$(curl -sf -X POST \
        -H "Content-Type: application/json" \
        -H "App-Token: ${GLPI_APP_TOKEN}" \
        -d "{\"login\":\"${GLPI_API_USER}\",\"password\":\"${GLPI_API_PASS}\"}" \
        "${GLPI_API_URL}/initSession" 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('session_token',''))" 2>/dev/null || echo "")
    
    if [ -z "${session_token}" ]; then
        echo "ERROR: GLPI authentication failed" >&2
        logger -t glpi-redmine "GLPI authentication failed"
        return 1
    fi
    
    local response
    response=$(curl -sf -X "${method}" \
        -H "Content-Type: application/json" \
        -H "App-Token: ${GLPI_APP_TOKEN}" \
        -H "Session-Token: ${session_token}" \
        ${data:+-d "${data}"} \
        "${GLPI_API_URL}/${endpoint}" 2>/dev/null || echo '{"error":"API call failed"}')
    
    # Kill session
    curl -sf -X POST \
        -H "App-Token: ${GLPI_APP_TOKEN}" \
        -H "Session-Token: ${session_token}" \
        "${GLPI_API_URL}/killSession" >/dev/null 2>&1 || true
    
    echo "${response}"
}

# ---------------------------------------------------------------
# Helper: Call Redmine REST API
# ---------------------------------------------------------------
redmine_api() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"
    
    curl -sf -X "${method}" \
        -H "Content-Type: application/json" \
        -H "X-Redmine-API-Key: ${REDMINE_API_KEY}" \
        ${data:+-d "${data}"} \
        "${REDMINE_URL}/${endpoint}.json" 2>/dev/null || echo '{"error":"Redmine API call failed"}'
}

# ---------------------------------------------------------------
# Helper: Retry with exponential backoff
# ---------------------------------------------------------------
retry() {
    local max_attempts=3
    local attempt=1
    local delay=5
    
    while [ ${attempt} -le ${max_attempts} ]; do
        if "$@" 2>/dev/null; then
            return 0
        fi
        echo "WARNING: Attempt ${attempt}/${max_attempts} failed, retrying in ${delay}s..." >&2
        sleep "${delay}"
        delay=$((delay * 2))
        attempt=$((attempt + 1))
    done
    
    return 1
}

# ---------------------------------------------------------------
# Main: Poll GLPI Changes → Create Redmine Issues
# ---------------------------------------------------------------
echo "=== GLPI → Redmine Integration ==="

# Determine last poll timestamp
if [ -f "${STATE_FILE}" ] && [ "${FORCE}" = false ]; then
    LAST_POLL=$(cat "${STATE_FILE}")
else
    # Default: look back 1 hour
    LAST_POLL=$(date -u -d "-1 hour" +"%Y-%m-%d %H:%M:%S")
fi

NOW=$(date -u +"%Y-%m-%d %H:%M:%S")
echo "Polling GLPI Changes from ${LAST_POLL} to ${NOW}..."

# Query GLPI for Changes updated since last poll
CHANGES_JSON=$(glpi_api "GET" \
    "Change?range=0-50&is_deleted=0&criteria[0][field]=12&criteria[0][searchtype]=morethan&criteria[0][value]=${LAST_POLL// /%20}" \
    2>/dev/null || echo '{"data":[]}')

CHANGE_COUNT=$(echo "${CHANGES_JSON}" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    items = data.get('data', []) if isinstance(data, dict) else []
    print(len(items))
except:
    print(0)
" 2>/dev/null || echo 0)

echo "Found ${CHANGE_COUNT} Change(s) to process"

if [ "${CHANGE_COUNT}" -eq 0 ]; then
    # Update state file even with no changes
    echo "${NOW}" > "${STATE_FILE}"
    echo "No Changes to process — updated state"
    exit 0
fi

# Process each Change
PROCESSED=0
FAILED=0

echo "${CHANGES_JSON}" | python3 -c "
import sys, json, os

data = json.load(sys.stdin)
items = data.get('data', []) if isinstance(data, dict) else data if isinstance(data, list) else []

DRY_RUN = '${DRY_RUN}' == 'true'

for item in items:
    change_id = item.get('id', '?')
    name = item.get('name', 'Untitled')
    content = item.get('content', '')
    status = item.get('status', 0)
    
    # Check if status triggers Redmine creation
    trigger_statuses = [int(x) for x in os.environ.get('REDMINE_TRIGGER_STATUS', '1,2').split(',')]
    
    if status not in trigger_statuses:
        print(f'SKIP Change #{change_id}: status={status} not in triggers {trigger_statuses}')
        continue
    
    glpi_url = f'https://{os.environ.get(\"GLPI_HOSTNAME\", \"glpi.gidas.local\")}/front/change.form.php?id={change_id}'
    
    if DRY_RUN:
        print(f'[DRY-RUN] Would create Redmine issue for Change #{change_id}: {name}')
        print(f'  Title: {name}')
        print(f'  URL: {glpi_url}')
        print(f'  Status: {status}')
        continue
    
    payload = json.dumps({
        'issue': {
            'project_id': os.environ.get('REDMINE_PROJECT_ID', 'glpi-integration'),
            'subject': f'[GLPI Change #{change_id}] {name}',
            'description': f'{content}\n\n---\nGLPI URL: {glpi_url}\nGLPI Status: {status}',
            'custom_fields': [
                {'id': 'glpi_change_id', 'value': str(change_id)}
            ]
        }
    })
    
    print(f'PROCESS Change #{change_id}: {name}')
    # Write payload for shell processing
    with open('/tmp/glpi-redmine-payload.json', 'w') as f:
        f.write(payload)
    print(f'PAYLOAD_READY')
" 2>/dev/null | while IFS= read -r line; do
    case "${line}" in
        PROCESS*)
            PROC_COUNT=$((PROCESSED + 1))
            echo "${line}"
            ;;
        PAYLOAD_READY)
            if [ -f /tmp/glpi-redmine-payload.json ] && [ "${DRY_RUN}" = false ]; then
                echo "  → Sending to Redmine..."
                if retry redmine_api "POST" "issues" "$(cat /tmp/glpi-redmine-payload.json)" >/dev/null 2>&1; then
                    echo "  ✅ Redmine issue created"
                    PROCESSED=$((PROCESSED + 1))
                else
                    echo "  ❌ Failed to create Redmine issue" >&2
                    logger -t glpi-redmine "ERROR: Failed to create Redmine issue"
                    FAILED=$((FAILED + 1))
                fi
                rm -f /tmp/glpi-redmine-payload.json
            fi
            ;;
        SKIP*|*)
            echo "${line}"
            ;;
    esac
done

# Update state file
echo "${NOW}" > "${STATE_FILE}"

PROCESSED=$(echo "${PROCESSED:-0}")
FAILED=$(echo "${FAILED:-0}")

echo ""
echo "=== Integration Complete ==="
echo "Processed: ${PROCESSED} Changes"
echo "Failed:    ${FAILED}"
echo "Next poll: ${NOW}"

logger -t glpi-redmine "Completed: ${PROCESSED} processed, ${FAILED} failed"

exit ${FAILED}
