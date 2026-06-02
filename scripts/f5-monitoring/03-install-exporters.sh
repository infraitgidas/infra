#!/bin/bash
# ================================================================
# 03-install-exporters.sh — Task 5.2: Install pve_exporter + node_exporter
# ================================================================
# Installs Prometheus exporters on each PVE cluster node:
#   - pve_exporter (:9221) — exposes Proxmox VE metrics via PVE API
#   - node_exporter (:9100) — exposes OS/hardware metrics
#
# Each exporter runs as a systemd service on the node.
# DESIGN: Exporters on each node allow Prometheus to scrape independently.
# Rollback: systemctl stop pve_exporter node_exporter && rm binary + service
# ================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-env.sh"

TOTAL_NODES=${#NODES[@]}

echo "=== Task 5.2: Instalar PVE Exporter + Node Exporter en cada nodo ==="
echo ""

# ---------------------------------------------------------------
# Step 1: Install PVE Exporter (Go binary) on each node
# ---------------------------------------------------------------
echo "[1/2] Instalando PVE Exporter (puerto ${PVE_EXPORTER_PORT}) en cada nodo..."
echo ""

for i in "${!NODES[@]}"; do
    IP="${NODES[$i]}"
    NAME="${NODE_NAMES[$i]}"
    echo "--- Nodo ${NAME} (${IP}) ---"

    ssh ${SSH_OPTS} root@${IP} "
        set -e

        # --- Install PVE Exporter binary ---
        if [ ! -f /usr/local/bin/pve_exporter ]; then
            cd /tmp
            # Download pve_exporter from GitHub releases
            wget -q https://github.com/prometheus-pve/pve_exporter/releases/download/v${PVE_EXPORTER_VERSION}/pve_exporter-${PVE_EXPORTER_VERSION}.linux-amd64.tar.gz
            tar xzf pve_exporter-${PVE_EXPORTER_VERSION}.linux-amd64.tar.gz
            cp pve_exporter-${PVE_EXPORTER_VERSION}.linux-amd64/pve_exporter /usr/local/bin/
            chmod 755 /usr/local/bin/pve_exporter
            rm -rf /tmp/pve_exporter-${PVE_EXPORTER_VERSION}.linux-amd64*
            echo '  ✅ PVE Exporter binario instalado'
        else
            echo '  ℹ️  PVE Exporter ya instalado'
        fi

        # --- Create PVE Exporter config ---
        mkdir -p /etc/pve_exporter
        if [ ! -f /etc/pve_exporter/pve.yml ]; then
            # Use the PVE API token or root@pam with password
            # For security, prefer token-based auth
            cat > /etc/pve_exporter/pve.yml << PVEEOF
default:
  user: root@pam
  token_name: exporter
  token_value: ''  # Set via pveum token
  # Alternative: password authentication
  # password: ''
  verify_ssl: false
PVEEOF
            echo '  ⚠️  CONFIG: Editar /etc/pve_exporter/pve.yml con credenciales PVE'
            echo '  ⚠️  Crear token: pveum user token add root@pam exporter --privsep 0'
        else
            echo '  ℹ️  Config PVE Exporter ya existe'
        fi

        # --- Create systemd service ---
        if [ ! -f /etc/systemd/system/pve_exporter.service ]; then
            cat > /etc/systemd/system/pve_exporter.service << 'SVC'
[Unit]
Description=Prometheus PVE Exporter
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/pve_exporter --config.file=/etc/pve_exporter/pve.yml --web.listen-address=:9221
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SVC
            systemctl daemon-reload
            echo '  ✅ Servicio systemd pve_exporter creado'
        else
            echo '  ℹ️  Servicio pve_exporter ya existe'
        fi

        # --- Start the service ---
        systemctl enable pve_exporter.service 2>/dev/null
        systemctl restart pve_exporter.service
        sleep 1
        if systemctl is-active --quiet pve_exporter; then
            echo '  ✅ PVE Exporter activo'
        else
            echo '  ❌ PVE Exporter no inició'
            systemctl status pve_exporter --no-pager 2>&1 | tail -5
        fi
    " 2>/dev/null

    echo ""
done

echo "[1/2] ✅ PVE Exporter instalado en todos los nodos"
echo ""

# ---------------------------------------------------------------
# Step 2: Install Node Exporter on each node
# ---------------------------------------------------------------
echo "[2/2] Instalando Node Exporter (puerto ${NODE_EXPORTER_PORT}) en cada nodo..."
echo ""

for i in "${!NODES[@]}"; do
    IP="${NODES[$i]}"
    NAME="${NODE_NAMES[$i]}"
    echo "--- Nodo ${NAME} (${IP}) ---"

    ssh ${SSH_OPTS} root@${IP} "
        set -e

        # --- Install Node Exporter binary ---
        if [ ! -f /usr/local/bin/node_exporter ]; then
            cd /tmp
            wget -q https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
            tar xzf node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
            cp node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter /usr/local/bin/
            chmod 755 /usr/local/bin/node_exporter
            rm -rf /tmp/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64*
            echo '  ✅ Node Exporter binario instalado'
        else
            echo '  ℹ️  Node Exporter ya instalado'
        fi

        # --- Create systemd service ---
        if [ ! -f /etc/systemd/system/node_exporter.service ]; then
            cat > /etc/systemd/system/node_exporter.service << 'SVC'
[Unit]
Description=Prometheus Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/node_exporter \
    --web.listen-address=:9100 \
    --collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($|/)
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SVC
            systemctl daemon-reload
            echo '  ✅ Servicio systemd node_exporter creado'
        else
            echo '  ℹ️  Servicio node_exporter ya existe'
        fi

        # --- Start the service ---
        systemctl enable node_exporter.service 2>/dev/null
        systemctl restart node_exporter.service
        sleep 1
        if systemctl is-active --quiet node_exporter; then
            echo '  ✅ Node Exporter activo'
        else
            echo '  ❌ Node Exporter no inició'
            systemctl status node_exporter --no-pager 2>&1 | tail -5
        fi
    " 2>/dev/null

    echo ""
done

echo "[2/2] ✅ Node Exporter instalado en todos los nodos"
echo ""

# ---------------------------------------------------------------
# Summary
# ---------------------------------------------------------------
echo "=== Task 5.2 completada ==="
echo "  Exporters instalados en ${TOTAL_NODES} nodos:"
for i in "${!NODES[@]}"; do
    echo "    ${NODE_NAMES[$i]} (${NODES[$i]}):"
    echo "      - PVE Exporter: http://${NODES[$i]}:${PVE_EXPORTER_PORT}/pve"
    echo "      - Node Exporter: http://${NODES[$i]}:${NODE_EXPORTER_PORT}/metrics"
done
echo ""
echo "  ⚠️  IMPORTANTE: Configurar token API PVE en cada nodo:"
echo "    pveum user token add root@pam exporter --privsep 0"
echo "    (copiar el token_secret a /etc/pve_exporter/pve.yml)"
echo ""
echo "  Rollback por nodo:"
echo "    systemctl stop pve_exporter node_exporter"
echo "    rm /usr/local/bin/pve_exporter /usr/local/bin/node_exporter"
echo "    rm /etc/systemd/system/pve_exporter.service /etc/systemd/system/node_exporter.service"
