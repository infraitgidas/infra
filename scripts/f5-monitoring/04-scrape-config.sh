#!/bin/bash
# ================================================================
# 04-scrape-config.sh — Task 5.3: Configure Prometheus scrape targets
# ================================================================
# Adds PVE Exporter (9221) and Node Exporter (9100) targets to
# Prometheus scrape configuration on CT sg-monitoring.
#
# PREREQUISITE: 03-install-exporters.sh (exporters running on all nodes)
# DESIGN: Each node exposes pve_exporter(:9221) and node_exporter(:9100).
# Prometheus scrapes both. Rollback: revert prometheus.yml, restart prometheus.
# ================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-env.sh"

echo "=== Task 5.3: Configurar scrape targets en Prometheus ==="
echo ""

# ---------------------------------------------------------------
# Step 1: Verify Prometheus is running on CT
# ---------------------------------------------------------------
echo "[1/4] Verificando Prometheus en CT ${CT_MONITORING_HOST}..."
if ! ssh ${SSH_OPTS} root@${CT_MONITORING_IP} "systemctl is-active --quiet prometheus" 2>/dev/null; then
    echo "❌ Prometheus no está activo en ${CT_MONITORING_IP}. Ejecutar 01-install-prometheus.sh primero."
    exit 1
fi
echo "[1/4] ✅ Prometheus activo"
echo ""

# ---------------------------------------------------------------
# Step 2: Verify exporters on all nodes
# ---------------------------------------------------------------
echo "[2/4] Verificando exporters en nodos del cluster..."
ALL_OK=true
for i in "${!NODES[@]}"; do
    IP="${NODES[$i]}"
    NAME="${NODE_NAMES[$i]}"

    if ssh ${SSH_OPTS} root@${IP} "systemctl is-active --quiet pve_exporter" 2>/dev/null; then
        echo "  ✅ ${NAME}: PVE Exporter activo"
    else
        echo "  ⚠️  ${NAME}: PVE Exporter NO activo (ejecutar 03-install-exporters.sh)"
        ALL_OK=false
    fi

    if ssh ${SSH_OPTS} root@${IP} "systemctl is-active --quiet node_exporter" 2>/dev/null; then
        echo "  ✅ ${NAME}: Node Exporter activo"
    else
        echo "  ⚠️  ${NAME}: Node Exporter NO activo"
        ALL_OK=false
    fi
done

if [ "${ALL_OK}" = false ]; then
    echo "⚠️  Algunos exporters no están activos. Continuando pero puede haber targets DOWN."
fi
echo "[2/4] ✅ Verificación de exporters completada"
echo ""

# ---------------------------------------------------------------
# Step 3: Add scrape targets to Prometheus config
# ---------------------------------------------------------------
echo "[3/4] Agregando targets PVE y Node a prometheus.yml..."

# Build scrape config block
SCRAPE_BLOCK="  - job_name: 'pve'
    metrics_path: '/pve'
    scrape_interval: 30s
    scrape_timeout: 10s
    static_configs:
      - targets:"
for i in "${!NODES[@]}"; do
    SCRAPE_BLOCK="${SCRAPE_BLOCK}
        - '${NODES[$i]}:${PVE_EXPORTER_PORT}'"
done
SCRAPE_BLOCK="${SCRAPE_BLOCK}
        labels:
          cluster: pve-gidas

  - job_name: 'node'
    scrape_interval: 30s
    scrape_timeout: 10s
    static_configs:
      - targets:"
for i in "${!NODES[@]}"; do
    SCRAPE_BLOCK="${SCRAPE_BLOCK}
        - '${NODES[$i]}:${NODE_EXPORTER_PORT}'"
done
SCRAPE_BLOCK="${SCRAPE_BLOCK}
        labels:
          cluster: pve-gidas"

ssh ${SSH_OPTS} root@${CT_MONITORING_IP} "
    set -e

    # Read current config
    CURRENT=\$(cat ${PROMETHEUS_HOME}/prometheus.yml)

    # Check if pve job already configured
    if echo \"\$CURRENT\" | grep -q \"job_name: 'pve'\"; then
        echo 'ℹ️  PVE scrape job ya configurado — actualizando configuración'
    fi

    if echo \"\$CURRENT\" | grep -q \"job_name: 'node'\"; then
        echo 'ℹ️  Node scrape job ya configurado — actualizando configuración'
    fi

    # Build new config: write the full prometheus.yml
    cat > ${PROMETHEUS_HOME}/prometheus.yml << 'PROMEOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    cluster: pve-gidas

alerting:
  alertmanagers:
    - static_configs:
        - targets:
          - localhost:9093

rule_files:
  - 'alerts.yml'

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

$(echo "${SCRAPE_BLOCK}")

PROMEOF

    chown prometheus:prometheus ${PROMETHEUS_HOME}/prometheus.yml
    chmod 644 ${PROMETHEUS_HOME}/prometheus.yml
    echo '✅ prometheus.yml actualizado con scrape targets'
" 2>/dev/null
echo "[3/4] ✅ Scrape targets configurados"
echo ""

# ---------------------------------------------------------------
# Step 4: Reload Prometheus and verify
# ---------------------------------------------------------------
echo "[4/4] Recargando Prometheus y verificando targets..."

ssh ${SSH_OPTS} root@${CT_MONITORING_IP} "
    set -e
    # Check config syntax first
    if /usr/local/bin/promtool check config ${PROMETHEUS_HOME}/prometheus.yml 2>/dev/null; then
        echo '✅ Config syntax OK'
        # Reload (SIGHUP) — more graceful than restart
        systemctl reload prometheus 2>/dev/null || systemctl restart prometheus
        sleep 2
        if systemctl is-active --quiet prometheus; then
            echo '✅ Prometheus recargado correctamente'
        else
            echo '❌ Prometheus falló al recargar'
            systemctl status prometheus --no-pager 2>&1 | tail -10
            exit 1
        fi
    else
        echo '❌ Config syntax ERROR — revisar ${PROMETHEUS_HOME}/prometheus.yml'
        /usr/local/bin/promtool check config ${PROMETHEUS_HOME}/prometheus.yml 2>&1
        exit 1
    fi
" 2>/dev/null

# Verify targets via API
echo ""
echo "Verificando targets via API..."
TARGETS=$(curl -sf "http://${CT_MONITORING_IP}:${PROMETHEUS_PORT}/api/v1/targets" 2>/dev/null || echo "")
if [ -n "${TARGETS}" ]; then
    echo "${TARGETS}" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for t in data.get('data', {}).get('activeTargets', []):
    print(f\"  {'✅' if t.get('health')=='up' else '❌'} {t.get('labels',{}).get('job','?')}: {t.get('labels',{}).get('instance','?')} — {t.get('health','?')}\")
" 2>/dev/null || echo "  (no se pudieron parsear targets — revisar manualmente)"
else
    echo "  ⚠️  No se pudo consultar API de Prometheus"
fi

echo ""
echo "=== Task 5.3 completada ==="
echo "  Targets configurados:"
for i in "${!NODES[@]}"; do
    echo "    - ${NODE_NAMES[$i]}: PVE Exporter :${PVE_EXPORTER_PORT}, Node Exporter :${NODE_EXPORTER_PORT}"
done
echo ""
echo "  Verificar:"
echo "    curl http://${CT_MONITORING_IP}:${PROMETHEUS_PORT}/api/v1/targets"
echo "    curl http://${NODES[0]}:${PVE_EXPORTER_PORT}/pve"
echo "    curl http://${NODES[0]}:${NODE_EXPORTER_PORT}/metrics"
echo ""
echo "  Rollback: restaurar prometheus.yml original, systemctl restart prometheus"
