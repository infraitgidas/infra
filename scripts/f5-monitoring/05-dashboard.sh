#!/bin/bash
# ================================================================
# 05-dashboard.sh — Task 5.4: Import Grafana Dashboard ID 10347
# ================================================================
# Imports the Proxmox VE cluster dashboard (ID 10347) into Grafana
# via the Grafana API. Configures Prometheus as the datasource.
#
# PREREQUISITE: 02-install-grafana.sh (Grafana running)
# Grafana API: http://admin:admin@localhost:3000/api
# Rollback: Delete the dashboard via Grafana UI or API
# ================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-env.sh"

echo "=== Task 5.4: Importar dashboard Grafana ID ${GRAFANA_DASHBOARD_ID} ==="
echo ""

# ---------------------------------------------------------------
# Step 1: Verify Grafana is running
# ---------------------------------------------------------------
echo "[1/5] Verificando Grafana en CT ${CT_MONITORING_HOST}..."
if ! ssh ${SSH_OPTS} root@${CT_MONITORING_IP} "systemctl is-active --quiet grafana-server" 2>/dev/null; then
    echo "❌ Grafana no está activo. Ejecutar 02-install-grafana.sh primero."
    exit 1
fi

# Check if Grafana API is responding
GRAFANA_HEALTH=$(ssh ${SSH_OPTS} root@${CT_MONITORING_IP} "curl -sf http://localhost:${GRAFANA_PORT}/api/health 2>/dev/null" || echo "")
if [ -z "${GRAFANA_HEALTH}" ]; then
    echo "❌ Grafana API no responde en puerto ${GRAFANA_PORT}"
    exit 1
fi
echo "[1/5] ✅ Grafana activo y API responde"
echo ""

# ---------------------------------------------------------------
# Step 2: Ensure Prometheus datasource exists (from provisioning)
# ---------------------------------------------------------------
echo "[2/5] Verificando datasource Prometheus..."
DS_CHECK=$(ssh ${SSH_OPTS} root@${CT_MONITORING_IP} "
    curl -sf -u ${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASS} \
    http://localhost:${GRAFANA_PORT}/api/datasources/name/Prometheus 2>/dev/null | python3 -c \"import sys,json; print(json.load(sys.stdin).get('id',''))\" 2>/dev/null || echo ''
")

if [ -z "${DS_CHECK}" ]; then
    echo "⚠️  Datasource Prometheus no encontrado. Creándolo..."
    ssh ${SSH_OPTS} root@${CT_MONITORING_IP} "
        curl -sf -X POST -u ${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASS} \
        -H 'Content-Type: application/json' \
        -d '{
            \"name\": \"Prometheus\",
            \"type\": \"prometheus\",
            \"url\": \"http://localhost:${PROMETHEUS_PORT}\",
            \"access\": \"proxy\",
            \"isDefault\": true
        }' \
        http://localhost:${GRAFANA_PORT}/api/datasources 2>/dev/null
    " 2>/dev/null
    echo "[2/5] ✅ Datasource Prometheus creado via API"
else
    echo "[2/5] ✅ Datasource Prometheus existe (ID: ${DS_CHECK})"
fi
echo ""

# ---------------------------------------------------------------
# Step 3: Download dashboard JSON from Grafana.com
# ---------------------------------------------------------------
echo "[3/5] Descargando dashboard ID ${GRAFANA_DASHBOARD_ID} desde grafana.com..."

DASHBOARD_JSON=$(ssh ${SSH_OPTS} root@${CT_MONITORING_IP} "
    curl -sf https://grafana.com/api/dashboards/${GRAFANA_DASHBOARD_ID}/revisions/latest/download 2>/dev/null || \
    wget -q -O - https://grafana.com/api/dashboards/${GRAFANA_DASHBOARD_ID}/revisions/latest/download 2>/dev/null
" 2>/dev/null || echo "")

if [ -z "${DASHBOARD_JSON}" ]; then
    echo "⚠️  No se pudo descargar dashboard ID ${GRAFANA_DASHBOARD_ID} desde grafana.com"
    echo "   Se usará una plantilla local mínima de PVE Cluster."
    echo "   Opción: descargar manualmente desde https://grafana.com/grafana/dashboards/${GRAFANA_DASHBOARD_ID}"

    # Create a minimal local dashboard template
    DASHBOARD_JSON='{
        "dashboard": {
            "id": null,
            "uid": "pve-cluster-monitoring",
            "title": "PVE Cluster Monitoring",
            "tags": ["pve", "proxmox", "cluster"],
            "timezone": "browser",
            "panels": [],
            "schemaVersion": 36,
            "version": 0
        },
        "overwrite": true,
        "inputs": [{
            "name": "DS_PROMETHEUS",
            "type": "datasource",
            "pluginId": "prometheus",
            "value": "Prometheus"
        }]
    }'
    echo "[3/5] ⚠️  Usando plantilla local mínima"
else
    # Wrap in Grafana import format
    DASHBOARD_JSON=$(cat << EOF
{
    "dashboard": ${DASHBOARD_JSON},
    "overwrite": true,
    "inputs": [{
        "name": "DS_PROMETHEUS",
        "type": "datasource",
        "pluginId": "prometheus",
        "value": "Prometheus"
    }]
}
EOF
)
    echo "[3/5] ✅ Dashboard descargado de grafana.com"
fi
echo ""

# ---------------------------------------------------------------
# Step 4: Import dashboard via Grafana API
# ---------------------------------------------------------------
echo "[4/5] Importando dashboard en Grafana..."
IMPORT_RESULT=$(ssh ${SSH_OPTS} root@${CT_MONITORING_IP} "
    curl -sf -X POST -u ${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASS} \
    -H 'Content-Type: application/json' \
    -d '$(echo "${DASHBOARD_JSON}" | tr '\n' ' ' | sed "s/'/\\\\'/g")' \
    http://localhost:${GRAFANA_PORT}/api/dashboards/db 2>/dev/null
" 2>/dev/null || echo "")

if echo "${IMPORT_RESULT}" | python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if d.get('title') else 1)" 2>/dev/null; then
    DASH_URL=$(echo "${IMPORT_RESULT}" | python3 -c "import sys,json; print(json.load(sys.stdin).get('url',''))" 2>/dev/null || echo "")
    echo "[4/5] ✅ Dashboard importado correctamente: http://${CT_MONITORING_IP}:${GRAFANA_PORT}${DASH_URL}"
else
    echo "[4/5] ❌ Error al importar dashboard"
    echo "   Respuesta: ${IMPORT_RESULT}"
    echo "   Intentar importación manual:"
    echo "     1. Abrir http://${CT_MONITORING_IP}:${GRAFANA_PORT}"
    echo "     2. Login: ${GRAFANA_ADMIN_USER} / ${GRAFANA_ADMIN_PASS}"
    echo "     3. Dashboards → Import → ID ${GRAFANA_DASHBOARD_ID}"
fi
echo ""

# ---------------------------------------------------------------
# Step 5: Save dashboard to provisioning folder for persistence
# ---------------------------------------------------------------
echo "[5/5] Guardando dashboard en provisioning para persistencia..."

# Save the downloaded/created JSON as a provisioning file
ssh ${SSH_OPTS} root@${CT_MONITORING_IP} "
    mkdir -p /var/lib/grafana/dashboards
    cat > /var/lib/grafana/dashboards/pve-cluster.json << 'DEOF'
$(echo "${DASHBOARD_JSON}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(json.dumps(d.get('dashboard',d), indent=2))" 2>/dev/null || echo "${DASHBOARD_JSON}")
DEOF
    chown grafana:grafana /var/lib/grafana/dashboards/pve-cluster.json
    echo '✅ Dashboard guardado en provisioning'
" 2>/dev/null
echo "[5/5] ✅ Dashboard persistido"
echo ""

# ---------------------------------------------------------------
# Summary
# ---------------------------------------------------------------
echo "=== Task 5.4 completada ==="
echo "  Dashboard ID: ${GRAFANA_DASHBOARD_ID}"
echo "  URL: http://${CT_MONITORING_IP}:${GRAFANA_PORT}"
echo "  Usuario: ${GRAFANA_ADMIN_USER}"
echo "  Password: ${GRAFANA_ADMIN_PASS}"
echo ""
echo "  Ver dashboard importados:"
echo "    curl -u ${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASS} \\"
echo "      http://${CT_MONITORING_IP}:${GRAFANA_PORT}/api/search?type=dash-db"
echo ""
echo "  Rollback: Eliminar dashboard desde UI de Grafana"
echo "    Dashboard Settings → Delete Dashboard"
