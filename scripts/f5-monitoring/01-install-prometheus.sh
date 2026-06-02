#!/bin/bash
# ================================================================
# 01-install-prometheus.sh — Task 5.1: Install Prometheus on CT sg-monitoring
# ================================================================
# Installs Prometheus server on the monitoring container (pve-ad, CT 205).
# Downloads the official binary from GitHub, creates system user,
# configures directories, and sets up systemd service.
#
# DESIGN: Prometheus runs outside the cluster (CT sg-monitoring) so it
# survives a cluster failure and can still alert when most needed.
# Rollback: systemctl stop prometheus && rm -rf /etc/prometheus /var/lib/prometheus /usr/local/bin/prometheus
# ================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-env.sh"

echo "=== Task 5.1: Instalar Prometheus en CT ${CT_MONITORING_HOST} (${CT_MONITORING_IP}) ==="
echo ""

# ---------------------------------------------------------------
# Step 1: Check connectivity to CT
# ---------------------------------------------------------------
echo "[1/6] Verificando conectividad con CT ${CT_MONITORING_HOST}..."
if ! ssh ${SSH_OPTS} root@${CT_MONITORING_IP} "hostname" 2>/dev/null; then
    echo "❌ No se puede conectar a ${CT_MONITORING_IP}. Verificar que CT ${CT_MONITORING_ID} esté running."
    echo "  Comando: pct start ${CT_MONITORING_ID} (desde un nodo PVE)"
    exit 1
fi
echo "[1/6] ✅ Conexión establecida con ${CT_MONITORING_HOST}"
echo ""

# ---------------------------------------------------------------
# Step 2: Create prometheus user
# ---------------------------------------------------------------
echo "[2/6] Creando usuario 'prometheus'..."
ssh ${SSH_OPTS} root@${CT_MONITORING_IP} "
    id -u prometheus &>/dev/null || useradd --no-create-home --shell /bin/false prometheus
" 2>/dev/null
echo "[2/6] ✅ Usuario prometheus listo"
echo ""

# ---------------------------------------------------------------
# Step 3: Install Prometheus binary
# ---------------------------------------------------------------
echo "[3/6] Descargando e instalando Prometheus ${PROMETHEUS_VERSION}..."
ssh ${SSH_OPTS} root@${CT_MONITORING_IP} "
    set -e
    cd /tmp
    if [ ! -f /usr/local/bin/prometheus ]; then
        wget -q https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz
        tar xzf prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz
        cp prometheus-${PROMETHEUS_VERSION}.linux-amd64/prometheus /usr/local/bin/
        cp prometheus-${PROMETHEUS_VERSION}.linux-amd64/promtool /usr/local/bin/
        chown root:root /usr/local/bin/prometheus /usr/local/bin/promtool
        chmod 755 /usr/local/bin/prometheus /usr/local/bin/promtool
        rm -rf /tmp/prometheus-${PROMETHEUS_VERSION}.linux-amd64*
        echo '✅ Prometheus binario instalado'
    else
        echo 'ℹ️  Prometheus ya está instalado'
    fi
" 2>/dev/null
echo "[3/6] ✅ Binario de Prometheus instalado"
echo ""

# ---------------------------------------------------------------
# Step 4: Create directories and config
# ---------------------------------------------------------------
echo "[4/6] Creando directorios y config básica..."
ssh ${SSH_OPTS} root@${CT_MONITORING_IP} "
    set -e
    mkdir -p ${PROMETHEUS_HOME}
    mkdir -p ${PROMETHEUS_DATA}
    chown prometheus:prometheus ${PROMETHEUS_DATA}

    # Basic config (scrape targets will be added by 04-scrape-config.sh)
    if [ ! -f ${PROMETHEUS_HOME}/prometheus.yml ]; then
        cat > ${PROMETHEUS_HOME}/prometheus.yml << 'PROMEOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    cluster: pve-gidas

# Alertmanager configuration
alerting:
  alertmanagers:
    - static_configs:
        - targets:
          - localhost:9093

# Rule files
rule_files:
  - 'alerts.yml'

# Scrape configuration
scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
PROMEOF
        chown -R prometheus:prometheus ${PROMETHEUS_HOME}
        echo '✅ Config básica creada'
    else
        echo 'ℹ️  Config ya existe'
    fi
" 2>/dev/null
echo "[4/6] ✅ Directorios y config creados"
echo ""

# ---------------------------------------------------------------
# Step 5: Create systemd service
# ---------------------------------------------------------------
echo "[5/6] Creando servicio systemd..."
ssh ${SSH_OPTS} root@${CT_MONITORING_IP} "
    if [ ! -f /etc/systemd/system/prometheus.service ]; then
        cat > /etc/systemd/system/prometheus.service << 'SVCEOF'
[Unit]
Description=Prometheus Time Series Collection and Processing Server
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus \
    --config.file=/etc/prometheus/prometheus.yml \
    --storage.tsdb.path=/var/lib/prometheus/ \
    --web.console.templates=/etc/prometheus/consoles \
    --web.console.libraries=/etc/prometheus/console_libraries \
    --web.listen-address=0.0.0.0:9090 \
    --web.external-url=

ExecReload=/bin/kill -HUP \$MAINPID
Restart=always
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
SVCEOF
        systemctl daemon-reload
        echo '✅ Servicio systemd creado'
    else
        echo 'ℹ️  Servicio ya existe'
    fi
" 2>/dev/null
echo "[5/6] ✅ Servicio systemd listo"
echo ""

# ---------------------------------------------------------------
# Step 6: Enable and start service
# ---------------------------------------------------------------
echo "[6/6] Iniciando Prometheus..."
ssh ${SSH_OPTS} root@${CT_MONITORING_IP} "
    systemctl enable prometheus.service 2>/dev/null
    systemctl restart prometheus.service
    sleep 2
    if systemctl is-active --quiet prometheus; then
        echo '✅ Prometheus está activo'
    else
        echo '❌ Prometheus no inició — revisar journalctl -u prometheus'
        systemctl status prometheus --no-pager
        exit 1
    fi
" 2>/dev/null
echo "[6/6] ✅ Prometheus iniciado correctamente"
echo ""

# ---------------------------------------------------------------
# Verify
# ---------------------------------------------------------------
echo "--- Verificación ---"
curl -sf http://${CT_MONITORING_IP}:${PROMETHEUS_PORT}/api/v1/status/buildinfo 2>/dev/null | head -c 200 || echo "⚠️  Prometheus API no responde (puede estar arrancando)"
echo ""
echo ""
echo "=== Task 5.1 completada — Prometheus instalado ==="
echo "  URL: http://${CT_MONITORING_IP}:${PROMETHEUS_PORT}"
echo "  Config: ${PROMETHEUS_HOME}/prometheus.yml"
echo "  Datos: ${PROMETHEUS_DATA}"
echo "  Rollback: systemctl stop prometheus && rm -rf ${PROMETHEUS_HOME} ${PROMETHEUS_DATA} /usr/local/bin/prometheus"
