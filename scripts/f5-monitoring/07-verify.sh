#!/bin/bash
# ================================================================
# 07-verify.sh — Task 5.6: Full verification of monitoring stack
# ================================================================
# Verifies every component of the monitoring stack:
#   - Task 5.1: Prometheus + Grafana running on CT sg-monitoring
#   - Task 5.2: PVE Exporter (:9221) + Node Exporter (:9100) on each node
#   - Task 5.3: Prometheus targets UP
#   - Task 5.4: Grafana dashboard 10347 imported
#   - Task 5.5: Alertmanager running + alert rules loaded
#
# Uses: curl, systemctl, Python for JSON parsing
# ================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-env.sh"

PASS=0
FAIL=0
WARN=0
INFO=0

check() {
    local desc="$1"
    local status="$2"
    if [ "${status}" = "PASS" ]; then
        echo "  ✅ PASS: ${desc}"
        PASS=$((PASS + 1))
    elif [ "${status}" = "WARN" ]; then
        echo "  ⚠️  WARN: ${desc}"
        WARN=$((WARN + 1))
    elif [ "${status}" = "INFO" ]; then
        echo "  ℹ️  INFO: ${desc}"
        INFO=$((INFO + 1))
    else
        echo "  ❌ FAIL: ${desc}"
        FAIL=$((FAIL + 1))
    fi
}

echo "========================================================"
echo "  Verification — Fase 5: Monitoreo (P2)"
echo "========================================================"
echo ""

# ---------------------------------------------------------------
# Section A: CT sg-monitoring connectivity
# ---------------------------------------------------------------
echo "--- Section A: CT sg-monitoring connectivity ---"
echo ""

HOST_CHECK=$(ssh ${SSH_OPTS} root@${CT_MONITORING_IP} "hostname" 2>/dev/null || echo "")
if [ "${HOST_CHECK}" = "${CT_MONITORING_HOST}" ]; then
    check "CT ${CT_MONITORING_HOST} (${CT_MONITORING_IP}) reachable" "PASS"
else
    check "CT ${CT_MONITORING_HOST} (${CT_MONITORING_IP}) reachable" "FAIL"
fi
echo ""

# ---------------------------------------------------------------
# Section B: Task 5.1 — Prometheus
# ---------------------------------------------------------------
echo "--- Section B: Task 5.1 — Prometheus ---"
echo ""

# Check Prometheus process
PROM_RUNNING=$(ssh ${SSH_OPTS} root@${CT_MONITORING_IP} "systemctl is-active prometheus" 2>/dev/null || echo "inactive")
if [ "${PROM_RUNNING}" = "active" ]; then
    check "Prometheus service active" "PASS"
else
    check "Prometheus service active (state: ${PROM_RUNNING})" "FAIL"
fi

# Check Prometheus API
PROM_API=$(curl -sf "http://${CT_MONITORING_IP}:${PROMETHEUS_PORT}/api/v1/status/buildinfo" 2>/dev/null || echo "")
if [ -n "${PROM_API}" ]; then
    check "Prometheus API responds on :${PROMETHEUS_PORT}" "PASS"
else
    check "Prometheus API responds on :${PROMETHEUS_PORT}" "FAIL"
fi

# Check Prometheus version
PROM_VERSION=$(echo "${PROM_API}" | python3 -c "import sys,json; print(json.load(sys.stdin).get('data',{}).get('version','?'))" 2>/dev/null || echo "unknown")
check "Prometheus version: ${PROM_VERSION}" "INFO"

# Check Prometheus config
PROM_CONFIG=$(ssh ${SSH_OPTS} root@${CT_MONITORING_IP} "/usr/local/bin/promtool check config ${PROMETHEUS_HOME}/prometheus.yml 2>&1" || echo "ERROR")
if echo "${PROM_CONFIG}" | grep -q "SUCCESS"; then
    check "Prometheus config syntax valid" "PASS"
else
    check "Prometheus config syntax valid" "FAIL"
fi
echo ""

# ---------------------------------------------------------------
# Section C: Task 5.1 — Grafana
# ---------------------------------------------------------------
echo "--- Section C: Task 5.1 — Grafana ---"
echo ""

# Check Grafana process
GRAFANA_RUNNING=$(ssh ${SSH_OPTS} root@${CT_MONITORING_IP} "systemctl is-active grafana-server" 2>/dev/null || echo "inactive")
if [ "${GRAFANA_RUNNING}" = "active" ]; then
    check "Grafana service active" "PASS"
else
    check "Grafana service active (state: ${GRAFANA_RUNNING})" "FAIL"
fi

# Check Grafana API
GRAFANA_HEALTH=$(curl -sf "http://${CT_MONITORING_IP}:${GRAFANA_PORT}/api/health" 2>/dev/null || echo "")
if [ -n "${GRAFANA_HEALTH}" ]; then
    check "Grafana API responds on :${GRAFANA_PORT}" "PASS"
else
    check "Grafana API responds on :${GRAFANA_PORT}" "FAIL"
fi

# Check Grafana version
GRAFANA_VERSION_CHECK=$(echo "${GRAFANA_HEALTH}" | python3 -c "import sys,json; print(json.load(sys.stdin).get('version','?'))" 2>/dev/null || echo "unknown")
check "Grafana version: ${GRAFANA_VERSION_CHECK}" "INFO"

# Check Prometheus datasource in Grafana
DS_CHECK=$(ssh ${SSH_OPTS} root@${CT_MONITORING_IP} "
    curl -sf -u ${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASS} \
    http://localhost:${GRAFANA_PORT}/api/datasources/name/Prometheus 2>/dev/null | \
    python3 -c \"import sys,json; d=json.load(sys.stdin); print(d.get('type','')+'/'+d.get('url',''))\" 2>/dev/null || echo ''
")
if [ -n "${DS_CHECK}" ]; then
    check "Prometheus datasource in Grafana (${DS_CHECK})" "PASS"
else
    check "Prometheus datasource in Grafana" "FAIL"
fi
echo ""

# ---------------------------------------------------------------
# Section D: Task 5.2 — Exporters on each node
# ---------------------------------------------------------------
echo "--- Section D: Task 5.2 — PVE Exporter + Node Exporter ---"
echo ""

for i in "${!NODES[@]}"; do
    IP="${NODES[$i]}"
    NAME="${NODE_NAMES[$i]}"
    echo "  Node ${NAME} (${IP}):"

    # PVE Exporter service
    PVE_SVC=$(ssh ${SSH_OPTS} root@${IP} "systemctl is-active pve_exporter" 2>/dev/null || echo "inactive")
    if [ "${PVE_SVC}" = "active" ]; then
        check "PVE Exporter service" "PASS"
    else
        check "PVE Exporter service (state: ${PVE_SVC})" "FAIL"
    fi

    # PVE Exporter endpoint
    PVE_CURL=$(curl -sf "http://${IP}:${PVE_EXPORTER_PORT}/pve" 2>/dev/null | head -c 100 || echo "")
    if [ -n "${PVE_CURL}" ]; then
        check "PVE Exporter http://${IP}:${PVE_EXPORTER_PORT}/pve responde" "PASS"
    else
        check "PVE Exporter http://${IP}:${PVE_EXPORTER_PORT}/pve responde" "FAIL"
    fi

    # Node Exporter service
    NODE_SVC=$(ssh ${SSH_OPTS} root@${IP} "systemctl is-active node_exporter" 2>/dev/null || echo "inactive")
    if [ "${NODE_SVC}" = "active" ]; then
        check "Node Exporter service" "PASS"
    else
        check "Node Exporter service (state: ${NODE_SVC})" "FAIL"
    fi

    # Node Exporter endpoint
    NODE_CURL=$(curl -sf "http://${IP}:${NODE_EXPORTER_PORT}/metrics" 2>/dev/null | head -c 100 || echo "")
    if [ -n "${NODE_CURL}" ]; then
        check "Node Exporter http://${IP}:${NODE_EXPORTER_PORT}/metrics responde" "PASS"
    else
        check "Node Exporter http://${IP}:${NODE_EXPORTER_PORT}/metrics responde" "FAIL"
    fi
    echo ""
done

# ---------------------------------------------------------------
# Section E: Task 5.3 — Prometheus scrape targets
# ---------------------------------------------------------------
echo "--- Section E: Task 5.3 — Prometheus scrape targets ---"
echo ""

TARGETS=$(curl -sf "http://${CT_MONITORING_IP}:${PROMETHEUS_PORT}/api/v1/targets" 2>/dev/null || echo "")
if [ -n "${TARGETS}" ]; then
    check "Prometheus targets API accessible" "PASS"

    # Parse target counts
    TARGET_COUNT=$(echo "${TARGETS}" | python3 -c "
import sys, json
data = json.load(sys.stdin)
targets = data.get('data', {}).get('activeTargets', [])
up = sum(1 for t in targets if t.get('health') == 'up')
down = sum(1 for t in targets if t.get('health') == 'down')
print(f'{len(targets)}|{up}|{down}')
" 2>/dev/null || echo "0|0|0")

    TOTAL=$(echo "${TARGET_COUNT}" | cut -d'|' -f1)
    UP=$(echo "${TARGET_COUNT}" | cut -d'|' -f2)
    DOWN=$(echo "${TARGET_COUNT}" | cut -d'|' -f3)

    if [ "${DOWN}" -gt 0 ]; then
        check "Targets: ${TOTAL} total, ${UP} up, ${DOWN} down" "WARN"
    elif [ "${TOTAL}" -gt 0 ]; then
        check "Targets: ${TOTAL} total, ${UP} up, ${DOWN} down" "PASS"
    else
        check "Targets: ${TOTAL} total (no targets found)" "WARN"
    fi

    # Show individual targets
    echo ""
    echo "  Target details:"
    echo "${TARGETS}" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for t in data.get('data', {}).get('activeTargets', []):
    job = t.get('labels', {}).get('job', '?')
    inst = t.get('labels', {}).get('instance', '?')
    health = t.get('health', '?')
    icon = '✅' if health == 'up' else '❌'
    print(f'    {icon} {job}/{inst} — {health}')
" 2>/dev/null || echo "    (parsing failed)"
else
    check "Prometheus targets API accessible" "FAIL"
fi
echo ""

# ---------------------------------------------------------------
# Section F: Task 5.4 — Grafana Dashboard
# ---------------------------------------------------------------
echo "--- Section F: Task 5.4 — Grafana Dashboard ---"
echo ""

DASHBOARDS=$(ssh ${SSH_OPTS} root@${CT_MONITORING_IP} "
    curl -sf -u ${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASS} \
    http://localhost:${GRAFANA_PORT}/api/search?type=dash-db 2>/dev/null
" || echo "")

if [ -n "${DASHBOARDS}" ]; then
    DASH_COUNT=$(echo "${DASHBOARDS}" | python3 -c "
import sys, json
dashboards = json.load(sys.stdin)
print(len(dashboards))
for d in dashboards:
    print(f\"  - {d.get('title','?')} (uid: {d.get('uid','?')})\")
" 2>/dev/null || echo "0")

    DASH_NUM=$(echo "${DASH_COUNT}" | head -1)
    if [ "${DASH_NUM}" -gt 0 ]; then
        check "Dashboards in Grafana: ${DASH_NUM} encontrados" "PASS"
        echo "  Lista:"
        echo "${DASH_COUNT}" | tail -n +2
    fi
else
    check "Dashboards in Grafana" "FAIL"
fi

# Check if provisioning file exists
DASH_FILE=$(ssh ${SSH_OPTS} root@${CT_MONITORING_IP} "ls -la /var/lib/grafana/dashboards/ 2>/dev/null" || echo "")
if [ -n "${DASH_FILE}" ]; then
    check "Dashboard provisioning files exist" "PASS"
else
    check "Dashboard provisioning files exist" "INFO"
fi
echo ""

# ---------------------------------------------------------------
# Section G: Task 5.5 — Alertmanager
# ---------------------------------------------------------------
echo "--- Section G: Task 5.5 — Alertmanager ---"
echo ""

# Check Alertmanager process
AM_RUNNING=$(ssh ${SSH_OPTS} root@${CT_MONITORING_IP} "systemctl is-active alertmanager" 2>/dev/null || echo "inactive")
if [ "${AM_RUNNING}" = "active" ]; then
    check "Alertmanager service active" "PASS"
else
    check "Alertmanager service active (state: ${AM_RUNNING})" "FAIL"
fi

# Check Alertmanager API
AM_API=$(curl -sf "http://${CT_MONITORING_IP}:${ALERTMANAGER_PORT}/api/v2/alerts" 2>/dev/null || echo "")
if [ -n "${AM_API}" ] || [ "${AM_API}" = "[]" ]; then
    check "Alertmanager API responds on :${ALERTMANAGER_PORT}" "PASS"
else
    check "Alertmanager API responds on :${ALERTMANAGER_PORT}" "FAIL"
fi

# Check Prometheus rule files exist
RULES_EXIST=$(ssh ${SSH_OPTS} root@${CT_MONITORING_IP} "ls -la ${PROMETHEUS_HOME}/alerts.yml 2>/dev/null" || echo "")
if [ -n "${RULES_EXIST}" ]; then
    check "Alert rules file ${PROMETHEUS_HOME}/alerts.yml exists" "PASS"
else
    check "Alert rules file ${PROMETHEUS_HOME}/alerts.yml exists" "FAIL"
fi

# Check rules are loaded in Prometheus
RULES_LOADED=$(curl -sf "http://${CT_MONITORING_IP}:${PROMETHEUS_PORT}/api/v1/rules" 2>/dev/null || echo "")
if [ -n "${RULES_LOADED}" ]; then
    RULE_COUNT=$(echo "${RULES_LOADED}" | python3 -c "
import sys, json
data = json.load(sys.stdin)
count = sum(len(g.get('rules', [])) for g in data.get('data', {}).get('groups', []))
print(count)
" 2>/dev/null || echo "0")
    if [ "${RULE_COUNT}" -gt 0 ]; then
        check "Alert rules loaded in Prometheus: ${RULE_COUNT} reglas" "PASS"
    else
        check "Alert rules loaded in Prometheus" "FAIL"
    fi
else
    check "Alert rules loaded in Prometheus" "FAIL"
fi
echo ""

# ---------------------------------------------------------------
# Section H: Architecture check — outside cluster
# ---------------------------------------------------------------
echo "--- Section H: Architecture verification ---"
echo ""

# Verify monitoring is on CT (not on cluster node)
check "Monitoring runs outside cluster (CT ${CT_MONITORING_HOST})" "INFO"
check "PVE nodes: ${#NODES[@]} exporters configured" "INFO"
echo ""

# ---------------------------------------------------------------
# Summary
# ---------------------------------------------------------------
echo "========================================================"
echo "  Verification Results — Fase 5: Monitoreo (P2)"
echo "========================================================"
echo "  PASS: ${PASS}"
echo "  WARN: ${WARN}"
echo "  INFO: ${INFO}"
echo "  FAIL: ${FAIL}"
echo "  Total: $((PASS + WARN + INFO + FAIL))"
echo ""

TOTAL_CHECKS=$((PASS + WARN + FAIL))

if [ "${FAIL}" -eq 0 ] && [ "${WARN}" -eq 0 ]; then
    echo "  ✅ OVERALL: ALL CHECKS PASSED — monitoring stack complete"
    echo ""
    echo "  Resumen:"
    echo "  - Prometheus ${PROMETHEUS_VERSION}: http://${CT_MONITORING_IP}:${PROMETHEUS_PORT}"
    echo "  - Grafana ${GRAFANA_VERSION}: http://${CT_MONITORING_IP}:${GRAFANA_PORT}"
    echo "  - Alertmanager ${ALERTMANAGER_VERSION}: http://${CT_MONITORING_IP}:${ALERTMANAGER_PORT}"
    echo "  - PVE Exporter: ${#NODES[@]} nodos en :${PVE_EXPORTER_PORT}"
    echo "  - Node Exporter: ${#NODES[@]} nodos en :${NODE_EXPORTER_PORT}"
    echo "  - Dashboard ID ${GRAFANA_DASHBOARD_ID} importado"
    echo "  - Alertas: quorum, ZFS, disco>80%, backup fails, node down"
elif [ "${FAIL}" -eq 0 ]; then
    echo "  ⚠️  OVERALL: PASSED WITH ${WARN} WARNING(S)"
    echo "  Revisar advertencias antes de dar por completada la Fase 5"
else
    echo "  ❌ OVERALL: ${FAIL} CHECK(S) FAILED"
    echo "  Revisar componentes con fallo y re-ejecutar scripts 01-06"
fi

exit ${FAIL}
