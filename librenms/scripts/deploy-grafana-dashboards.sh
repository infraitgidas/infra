#!/bin/bash
# ============================================================
# deploy-grafana-dashboards.sh — Importar dashboards a Grafana
# ============================================================
# Importa los dashboards JSON de librenms/grafana/ a Grafana
# via su API.
#
# Uso: ./deploy-grafana-dashboards.sh [grafana_url] [api_key]
#   - grafana_url: default http://192.168.1.205:3000
#   - api_key: Grafana API token (o usa user:pass si no se provee)
# ============================================================
set -euo pipefail

GRAFANA_URL="${1:-http://192.168.1.205:3000}"
GRAFANA_AUTH="${2:-admin:admin}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DASHBOARDS_DIR="$(dirname "$SCRIPT_DIR")/grafana"

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=== Deploy Dashboards LibreNMS → Grafana ==="
echo "  Grafana: ${GRAFANA_URL}"
echo ""

# Verificar conexión
echo "[1/4] Verificando conexión a Grafana..."
if ! curl -sk --max-time 5 "${GRAFANA_URL}/api/health" -o /dev/null 2>&1; then
    echo -e "  ${RED}✗${NC} Grafana no accesible en ${GRAFANA_URL}"
    echo "  Verificá que Grafana esté corriendo y accesible."
    echo "  Si es necesario, configurá Twingate o VPN para acceder."
    exit 1
fi
echo -e "  ${GREEN}✓${NC} Grafana accesible"
echo ""

# Verificar datasource LibreNMS
echo "[2/4] Verificando datasource LibreNMS..."
DS_CHECK=$(curl -sk --max-time 5 -u "${GRAFANA_AUTH}" \
  "${GRAFANA_URL}/api/datasources/name/LibreNMS" 2>/dev/null)

if echo "$DS_CHECK" | grep -q "LibreNMS"; then
    echo -e "  ${GREEN}✓${NC} Datasource LibreNMS encontrado"
    DS_UID=$(echo "$DS_CHECK" | python3 -c "import sys,json; print(json.load(sys.stdin)['uid'])" 2>/dev/null || echo "")
else
    echo -e "  ${YELLOW}⚠${NC} Datasource LibreNMS no configurado"
    echo "  Ejecutá primero setup-grafana.sh o configuralo manualmente"
    echo "  Continuando con UID temporal..."
    DS_UID="librenms-datasource"
fi
echo ""

# Importar dashboards
echo "[3/4] Importando dashboards..."
IMPORTED=0
FAILED=0

for dashboard_file in "${DASHBOARDS_DIR}"/dashboard-*.json; do
    name=$(basename "$dashboard_file")
    echo -n "  ${name}... "
    
    # Preparar payload de importación
    dashboard_json=$(cat "$dashboard_file")
    
    # Reemplazar placeholder datasource UID
    if [ -n "$DS_UID" ]; then
        dashboard_json=$(echo "$dashboard_json" | sed "s/\"datasource\": \"LibreNMS\"/\"datasource\": {\"uid\": \"${DS_UID}\"}/g")
    fi
    
    payload=$(cat <<EOF
{
    "dashboard": ${dashboard_json},
    "overwrite": true,
    "message": "Deployed by deploy-grafana-dashboards.sh",
    "folderUid": ""
}
EOF
)
    
    # Importar via Grafana API
    response=$(curl -sk --max-time 10 -X POST -u "${GRAFANA_AUTH}" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "${GRAFANA_URL}/api/dashboards/db" 2>/dev/null)
    
    if echo "$response" | grep -q "\"id\":"; then
        dash_url=$(echo "$response" | python3 -c "import sys,json; print(json.load(sys.stdin).get('url',''))" 2>/dev/null)
        echo -e "${GREEN}✓${NC} ${GRAFANA_URL}${dash_url}"
        IMPORTED=$((IMPORTED + 1))
    else
        err_msg=$(echo "$response" | python3 -c "import sys,json; print(json.load(sys.stdin).get('message','unknown error'))" 2>/dev/null || echo "unknown error")
        echo -e "${RED}✗${NC} ${err_msg}"
        FAILED=$((FAILED + 1))
    fi
done

echo ""
echo "[4/4] Resumen:"
echo "  Importados: ${GREEN}${IMPORTED}${NC}"
if [ "${FAILED}" -gt 0 ]; then
    echo "  Fallidos:   ${RED}${FAILED}${NC}"
fi
echo ""
echo "=== Done ==="
