#!/bin/bash
# ================================================================
# webhook-gitlab.sh — GLPI → GitLab integration
# ================================================================
# Polls GLPI for resolved/closed Incidents and posts a comment
# to the linked GitLab issue via REST API.
#
# Usage:
#   ./webhook-gitlab.sh                    # Run once
#   ./webhook-gitlab.sh --dry-run          # Show what would be done
#   ./webhook-gitlab.sh --force            # Process all, ignoring state
#
# Designed to run via cron every 5 minutes:
#   */5 * * * * /opt/infra/itsm/scripts/webhook-gitlab.sh
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
STATE_FILE="${STATE_DIR}/gitlab-last-poll"

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
        logger -t glpi-gitlab "GLPI authentication failed"
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
# Helper: Call GitLab REST API
# ---------------------------------------------------------------
gitlab_api() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"
    
    curl -sf -X "${method}" \
        -H "Content-Type: application/json" \
        -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
        ${data:+-d "${data}"} \
        "${GITLAB_URL}/api/v4/${endpoint}" 2>/dev/null || echo '{"error":"GitLab API call failed"}'
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
# Main: Poll GLPI Resolved Incidents → Comment on GitLab
# ---------------------------------------------------------------
echo "=== GLPI → GitLab Integration ==="

# Determine last poll timestamp
if [ -f "${STATE_FILE}" ] && [ "${FORCE}" = false ]; then
    LAST_POLL=$(cat "${STATE_FILE}")
else
    LAST_POLL=$(date -u -d "-1 hour" +"%Y-%m-%d %H:%M:%S")
fi

NOW=$(date -u +"%Y-%m-%d %H:%M:%S")
echo "Polling GLPI Incidents resolved from ${LAST_POLL} to ${NOW}..."

# Query GLPI for resolved/closed Incidents since last poll
# GLPI ticket statuses: 1=New, 2=Assigned, 3=In Progress, 4=Resolved, 5=Closed
# Search for status=4 (Resolved) or 5 (Closed) that have been updated recently
INCIDENTS_JSON=$(glpi_api "GET" \
    "Ticket?range=0-50&is_deleted=0&criteria[0][field]=12&criteria[0][searchtype]=morethan&criteria[0][value]=${LAST_POLL// /%20}&criteria[1][field]=2&criteria[1][searchtype]=contains&criteria[1][value]=4&criteria[1][link]=OR&criteria[2][field]=2&criteria[2][value]=5&criteria[2][link]=OR" \
    2>/dev/null || echo '{"data":[]}')

INCIDENT_COUNT=$(echo "${INCIDENTS_JSON}" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    items = data.get('data', []) if isinstance(data, dict) else []
    print(len(items))
except:
    print(0)
" 2>/dev/null || echo 0)

echo "Found ${INCIDENT_COUNT} Incident(s) to process"

if [ "${INCIDENT_COUNT}" -eq 0 ]; then
    echo "${NOW}" > "${STATE_FILE}"
    echo "No Incidents to process — updated state"
    exit 0
fi

# Process each Incident
PROCESSED=0
FAILED=0

echo "${INCIDENTS_JSON}" | python3 -c "
import sys, json, os

data = json.load(sys.stdin)
items = data.get('data', []) if isinstance(data, dict) else data if isinstance(data, list) else []
DRY_RUN = '${DRY_RUN}' == 'true'

for item in items:
    ticket_id = item.get('id', '?')
    name = item.get('name', 'Untitled')
    content = item.get('content', '')
    status = item.get('status', 0)
    
    # Only process resolved (4) or closed (5)
    trigger_statuses = [int(x) for x in os.environ.get('GITLAB_TRIGGER_STATUS', '4,5').split(',')]
    if status not in trigger_statuses:
        print(f'SKIP #{ticket_id}: status={status} not in triggers {trigger_statuses}')
        continue
    
    # Try to extract GitLab issue reference from ticket content or external IDs
    # GLPI stores external IDs as: _external_id or in solution field
    gitlab_issue_id = ''
    
    # Check solution field for GitLab reference
    solution = item.get('solution', '') or ''
    for line in solution.split('\n'):
        if 'gitlab' in line.lower() and '#' in line:
            import re
            match = re.search(r'#(\d+)', line)
            if match:
                gitlab_issue_id = match.group(1)
                break
    
    if not gitlab_issue_id:
        print(f'SKIP #{ticket_id}: No GitLab issue reference found (add \"GitLab #ID\" in solution)')
        continue
    
    glpi_url = f'https://{os.environ.get(\"GLPI_HOSTNAME\", \"glpi.gidas.local\")}/front/ticket.form.php?id={ticket_id}'
    
    status_label = {4: 'Resolved', 5: 'Closed'}.get(status, f'Status {status}')
    
    if DRY_RUN:
        print(f'[DRY-RUN] Would comment on GitLab issue #{gitlab_issue_id} from Incident #{ticket_id}')
        print(f'  Title: {name}')
        print(f'  Status: {status_label}')
        print(f'  GitLab Issue: #{gitlab_issue_id}')
        continue
    
    comment_body = (
        f'**GLPI Incident #{ticket_id}: {name}**\n\n'
        f'Status: {status_label}\n\n'
        f'{content}\n\n'
        f'---\n'
        f'🔗 [Open in GLPI]({glpi_url})'
    )
    
    payload = json.dumps({'body': comment_body})
    
    print(f'PROCESS #{ticket_id}: {name} → GitLab #{gitlab_issue_id}')
    with open('/tmp/glpi-gitlab-payload.json', 'w') as f:
        f.write(payload)
    print(f'GITLAB_ISSUE_ID={gitlab_issue_id}')
    print(f'PAYLOAD_READY')
" 2>/dev/null | while IFS= read -r line; do
    case "${line}" in
        PROCESS*)
            echo "${line}"
            ;;
        GITLAB_ISSUE_ID=*)
            GITLAB_IID="${line#*=}"
            ;;
        PAYLOAD_READY)
            if [ -f /tmp/glpi-gitlab-payload.json ] && [ "${DRY_RUN}" = false ] && [ -n "${GITLAB_IID:-}" ]; then
                echo "  → Posting comment to GitLab issue #${GITLAB_IID}..."
                if retry gitlab_api "POST" \
                    "projects/${GITLAB_PROJECT_ID}/issues/${GITLAB_IID}/notes" \
                    "$(cat /tmp/glpi-gitlab-payload.json)" >/dev/null 2>&1; then
                    echo "  ✅ Comment posted to GitLab"
                    PROCESSED=$((PROCESSED + 1))
                else
                    echo "  ❌ Failed to post comment to GitLab" >&2
                    logger -t glpi-gitlab "ERROR: Failed to post comment to GitLab issue #${GITLAB_IID}"
                    FAILED=$((FAILED + 1))
                fi
                rm -f /tmp/glpi-gitlab-payload.json
            fi
            GITLAB_IID=""
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
echo "Processed: ${PROCESSED} Incidents"
echo "Failed:    ${FAILED}"
echo "Next poll: ${NOW}"

logger -t glpi-gitlab "Completed: ${PROCESSED} processed, ${FAILED} failed"

exit ${FAILED}
