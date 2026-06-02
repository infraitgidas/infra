#!/bin/bash
# ================================================================
# 02-install-grafana.sh — Task 5.1: Install Grafana on CT sg-monitoring
# ================================================================
# Installs Grafana OSS on the monitoring container (pve-ad, CT 205).
# Uses the official Grafana APT repository for easy updates.
# Configures Prometheus as a default datasource.
#
# PREREQUISITE: 01-install-prometheus.sh (Prometheus must be running)
# Rollback: systemctl stop grafana-server && apt-get remove -y grafana
# ================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-env.sh"

echo "=== Task 5.1: Instalar Grafana en CT ${CT_MONITORING_HOST} (${CT_MONITORING_IP}) ==="
echo ""

# ---------------------------------------------------------------
# Step 1: Verify connectivity and prerequisites
# ---------------------------------------------------------------
echo "[1/6] Verificando prerequisitos..."
if ! ssh ${SSH_OPTS} root@${CT_MONITORING_IP} "hostname" 2>/dev/null; then
    echo "❌ No se puede conectar a ${CT_MONITORING_IP}"
    exit 1
fi

# Check if Prometheus is running
if ! ssh ${SSH_OPTS} root@${CT_MONITORING_IP} "systemctl is-active --quiet prometheus" 2>/dev/null; then
    echo "⚠️  Prometheus no está activo. Ejecutar 01-install-prometheus.sh primero."
    echo "   Continuando de todas formas — Grafana se puede configurar después."
fi
echo "[1/6] ✅ Prerequisitos OK"
echo ""

# ---------------------------------------------------------------
# Step 2: Add Grafana APT repository
# ---------------------------------------------------------------
echo "[2/6] Agregando repositorio APT de Grafana..."
ssh ${SSH_OPTS} root@${CT_MONITORING_IP} "
    set -e
    # Install prerequisites
    apt-get update -qq && apt-get install -y -qq software-properties-common gnupg apt-transport-https 2>/dev/null

    # Add Grafana GPG key
    if [ ! -f /etc/apt/keyrings/grafana.gpg ]; then
        mkdir -p /etc/apt/keyrings
        wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor -o /etc/apt/keyrings/grafana.gpg
        echo 'deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main' > /etc/apt/sources.list.d/grafana.list
        apt-get update -qq
        echo '✅ Repositorio Grafana agregado'
    else
        echo 'ℹ️  Repositorio Grafana ya configurado'
    fi
" 2>/dev/null
echo "[2/6] ✅ Repositorio Grafana listo"
echo ""

# ---------------------------------------------------------------
# Step 3: Install Grafana OSS
# ---------------------------------------------------------------
echo "[3/6] Instalando Grafana OSS..."
ssh ${SSH_OPTS} root@${CT_MONITORING_IP} "
    set -e
    if ! dpkg -l grafana 2>/dev/null | grep -q '^ii'; then
        apt-get install -y -qq grafana 2>/dev/null
        echo '✅ Grafana instalado'
    else
        echo 'ℹ️  Grafana ya está instalado'
        # Upgrade to specified version
        apt-get install -y -qq grafana=${GRAFANA_VERSION} 2>/dev/null || true
    fi
" 2>/dev/null
echo "[3/6] ✅ Grafana instalado"
echo ""

# ---------------------------------------------------------------
# Step 4: Configure Grafana (Prometheus datasource)
# ---------------------------------------------------------------
echo "[4/6] Configurando datasource Prometheus..."
ssh ${SSH_OPTS} root@${CT_MONITORING_IP} "
    set -e
    # Ensure provisioning directory exists
    mkdir -p /etc/grafana/provisioning/datasources/
    mkdir -p /etc/grafana/provisioning/dashboards/

    # Create Prometheus datasource provisioning file
    cat > /etc/grafana/provisioning/datasources/prometheus.yml << 'DSOF'
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://localhost:9090
    isDefault: true
    editable: false
DSOF

    # Create dashboard provisioning config
    cat > /etc/grafana/provisioning/dashboards/default.yml << 'DPOF'
apiVersion: 1

providers:
  - name: 'PVE Cluster'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    updateIntervalSeconds: 30
    options:
      path: /var/lib/grafana/dashboards
DPOF

    mkdir -p /var/lib/grafana/dashboards
    chown -R grafana:grafana /etc/grafana/provisioning/
    chown -R grafana:grafana /var/lib/grafana/dashboards/

    # Configure Grafana to listen on all interfaces
    if grep -q '^;http_addr' /etc/grafana/grafana.ini 2>/dev/null; then
        sed -i 's/^;http_addr =/http_addr =/' /etc/grafana/grafana.ini
    fi
    # Ensure port is set
    sed -i 's/^;http_port = 3000/http_port = 3000/' /etc/grafana/grafana.ini 2>/dev/null || true

    echo '✅ Datasource Prometheus configurado'
" 2>/dev/null
echo "[4/6] ✅ Datasource Prometheus configurado"
echo ""

# ---------------------------------------------------------------
# Step 5: Enable and start Grafana
# ---------------------------------------------------------------
echo "[5/6] Iniciando Grafana..."
ssh ${SSH_OPTS} root@${CT_MONITORING_IP} "
    set -e
    systemctl daemon-reload 2>/dev/null
    systemctl enable grafana-server 2>/dev/null
    systemctl restart grafana-server
    sleep 3
    if systemctl is-active --quiet grafana-server; then
        echo '✅ Grafana está activo'
    else
        echo '❌ Grafana no inició — revisar journalctl -u grafana-server'
        systemctl status grafana-server --no-pager
        exit 1
    fi
" 2>/dev/null
echo "[5/6] ✅ Grafana iniciado correctamente"
echo ""

# ---------------------------------------------------------------
# Step 6: Verify Grafana API
# ---------------------------------------------------------------
echo "[6/6] Verificando Grafana API..."
GRAFANA_OK=$(ssh ${SSH_OPTS} root@${CT_MONITORING_IP} "curl -sf http://localhost:3000/api/health 2>/dev/null" || echo "")
if [ -n "${GRAFANA_OK}" ]; then
    echo "[6/6] ✅ Grafana API responde correctamente"
else
    echo "[6/6] ⚠️  Grafana API no responde aún — puede estar arrancando"
fi
echo ""

# ---------------------------------------------------------------
# Summary
# ---------------------------------------------------------------
echo "=== Task 5.1 completada — Grafana instalado ==="
echo "  URL: http://${CT_MONITORING_IP}:${GRAFANA_PORT}"
echo "  Usuario: ${GRAFANA_ADMIN_USER}"
echo "  Password: ${GRAFANA_ADMIN_PASS} (CAMBIAR después del login inicial)"
echo "  Datasource: Prometheus (http://localhost:${PROMETHEUS_PORT})"
echo "  Rollback: systemctl stop grafana-server && apt-get remove -y grafana"
