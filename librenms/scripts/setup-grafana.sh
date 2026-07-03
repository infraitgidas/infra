#!/bin/bash
# ============================================================
# setup-grafana.sh — Integrar LibreNMS con Grafana
# ============================================================
# Crea API token en LibreNMS y configura datasource en Grafana.
# Ejecutar en CT 210 o desde PVE host via pct exec.
# ============================================================
set -euo pipefail

CT=210
GRAFANA_URL="${1:-http://192.168.1.205:3000}"
GRAFANA_USER="${2:-admin}"
GRAFANA_PASS="${3:-admin}"

echo "=== Integración LibreNMS → Grafana ==="

# ============================================================
# 1. Crear API token en LibreNMS
# ============================================================
echo "[1/3] Creando API token en LibreNMS..."

# Verificar si ya existe un token para Grafana
TOKEN_EXISTS=$(pct exec $CT -- docker exec librenms-db mysql -u librenms -p"${DB_PASSWORD}" librenms -N -e "SELECT COUNT(*) FROM api_tokens WHERE description='Grafana integration';" 2>/dev/null || echo "0")

if [ "$TOKEN_EXISTS" = "0" ]; then
    # Generar token
    API_TOKEN=$(openssl rand -hex 32)
    
    # Insertar en DB (user_id=1 = infrait)
    pct exec $CT -- docker exec librenms-db mysql -u librenms -p"${DB_PASSWORD}" librenms -e \
        "INSERT INTO api_tokens (user_id, token_hash, description) VALUES (1, '${API_TOKEN}', 'Grafana integration');"
    
    echo "  ✅ API Token creado: ${API_TOKEN}"
else
    # Recuperar token existente
    API_TOKEN=$(pct exec $CT -- docker exec librenms-db mysql -u librenms -p"${DB_PASSWORD}" librenms -N -e "SELECT token_hash FROM api_tokens WHERE description='Grafana integration' LIMIT 1;" 2>/dev/null)
    echo "  ℹ️  Token existente: ${API_TOKEN}"
fi

# ============================================================
# 2. Verificar LibreNMS API
# ============================================================
echo "[2/3] Verificando LibreNMS API..."
LNMS_RESPONSE=$(pct exec $CT -- docker exec librenms curl -sk --max-time 5 \
    -H "Authorization: Bearer ${API_TOKEN}" \
    "http://127.0.0.1:8000/api/v0/devices" 2>/dev/null | head -1 || echo "ERROR")

if echo "$LNMS_RESPONSE" | grep -q "devices"; then
    echo "  ✅ API LibreNMS respondiendo correctamente"
else
    echo "  ⚠️  API LibreNMS: respuesta inesperada (verificar)"
fi

# ============================================================
# 3. Configurar datasource en Grafana
# ============================================================
echo "[3/3] Configurando datasource en Grafana..."
GRAFANA_API="${GRAFANA_URL}/api"

# Verificar si Grafana está accesible
GRAFANA_OK=$(curl -sk --max-time 5 "${GRAFANA_API}/health" 2>/dev/null | grep -c "ok" || echo "0")

if [ "$GRAFANA_OK" -gt 0 ]; then
    echo "  ✅ Grafana accesible en ${GRAFANA_URL}"
    
    # Obtener API key de Grafana (o usar user/pass)
    GRAFANA_AUTH="${GRAFANA_USER}:${GRAFANA_PASS}"
    
    # Verificar si datasource ya existe
    DS_EXISTS=$(curl -sk --max-time 5 -u "${GRAFANA_AUTH}" \
        "${GRAFANA_API}/datasources/name/LibreNMS" 2>/dev/null | grep -c "LibreNMS" || echo "0")
    
    if [ "$DS_EXISTS" -eq 0 ]; then
        # Crear datasource
        DS_PAYLOAD=$(cat <<EOF
{
    "name": "LibreNMS",
    "type": "librenms-datasource",
    "url": "https://nms.gidas.local",
    "access": "proxy",
    "basicAuth": false,
    "jsonData": {
        "token": "${API_TOKEN}"
    }
}
EOF
)
        DS_RESULT=$(curl -sk --max-time 10 -X POST -u "${GRAFANA_AUTH}" \
            -H "Content-Type: application/json" \
            -d "${DS_PAYLOAD}" \
            "${GRAFANA_API}/datasources" 2>/dev/null)
        
        echo "  ✅ Datasource LibreNMS creado en Grafana"
    else
        echo "  ℹ️  Datasource LibreNMS ya existe en Grafana"
    fi
else
    echo "  ⚠️  Grafana no accesible en ${GRAFANA_URL}"
    echo "     La configuración del datasource debe hacerse manualmente:"
    echo ""
    echo "  1. Abrir Grafana: ${GRAFANA_URL}"
    echo "  2. Configuration → Data Sources → Add data source"
    echo "  3. Buscar 'LibreNMS' e instalarlo"
    echo "  4. Configurar:"
    echo "     - URL: https://nms.gidas.local"
    echo "     - Access: Proxy"
    echo "     - Token: ${API_TOKEN}"
    echo "  5. Save & Test"
fi

echo ""
echo "=== Resumen de Integración ==="
echo ""
echo "  LibreNMS URL:  https://nms.gidas.local"
echo "  API Token:     ${API_TOKEN}"
echo "  Grafana URL:   ${GRAFANA_URL}"
echo ""
echo "  Para instalar el plugin manualmente en Grafana:"
echo "    grafana-cli plugins install librenms-datasource"
echo ""
echo "  Para probar la API directamente:"
echo "    curl -H \"Authorization: Bearer ${API_TOKEN}\" https://nms.gidas.local/api/v0/devices"
echo ""
