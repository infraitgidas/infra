#!/bin/bash
# ================================================================
# 00-env.sh — F5 Environment Configuration (Monitoreo)
# ================================================================
# Source this file before running any other scripts:
#   source 00-env.sh
# ================================================================

# --- Cluster Nodes ---
declare -a NODES=(
    "192.168.1.11"  # pve-desa01
    "192.168.1.12"  # pve-desa02
    "192.168.1.13"  # pve-desa03
    "192.168.1.14"  # pve-desa04
)

declare -a NODE_NAMES=(
    "pve-desa01"
    "pve-desa02"
    "pve-desa03"
    "pve-desa04"
)

# --- CT sg-monitoring (pve-ad) ---
CT_MONITORING_IP="192.168.1.31"
CT_MONITORING_HOST="sg-monitoring"
CT_MONITORING_ID="205"

# --- Ports ---
PROMETHEUS_PORT="9090"
GRAFANA_PORT="3000"
ALERTMANAGER_PORT="9093"
PVE_EXPORTER_PORT="9221"
NODE_EXPORTER_PORT="9100"

# --- Versions ---
PROMETHEUS_VERSION="2.53.0"
GRAFANA_VERSION="10.4.2"
NODE_EXPORTER_VERSION="1.8.0"
PVE_EXPORTER_VERSION="1.3.0"
ALERTMANAGER_VERSION="0.27.0"

# --- Paths (on CT sg-monitoring) ---
PROMETHEUS_HOME="/etc/prometheus"
PROMETHEUS_DATA="/var/lib/prometheus"
PROMETHEUS_BIN="/usr/local/bin/prometheus"
GRAFANA_HOME="/etc/grafana"
GRAFANA_DATA="/var/lib/grafana"
ALERTMANAGER_HOME="/etc/alertmanager"
ALERTMANAGER_BIN="/usr/local/bin/alertmanager"

# --- Grafana ---
GRAFANA_DASHBOARD_ID="10347"
GRAFANA_ADMIN_USER="admin"
GRAFANA_ADMIN_PASS="admin"  # CHANGE AFTER INITIAL LOGIN

# --- Alertmanager Receiver ---
# Default: email. Change to slack/telegram/webhook as needed.
ALERTMANAGER_RECEIVER="email"
ALERTMANAGER_EMAIL_TO="admin@pve-gidas.local"
ALERTMANAGER_EMAIL_FROM="alertmanager@pve-gidas.local"
ALERTMANAGER_SMTP_HOST="localhost"
ALERTMANAGER_SMTP_PORT="25"

# --- Thresholds ---
DISK_USAGE_WARN=80   # Alert when disk usage exceeds this percent

# --- SSH Options ---
SSH_OPTS="-o ConnectTimeout=10 -o BatchMode=yes"

# --- Architecture ---
# Prometheus + Grafana + Alertmanager on CT sg-monitoring (pve-ad, CT 205)
# PVE Exporter (:9221) + Node Exporter (:9100) on each PVE node
# Outside the cluster — survives cluster failure

echo "[00-env] Loaded F5 monitoring environment"
echo "[00-env] CT sg-monitoring: ${CT_MONITORING_IP} (${CT_MONITORING_HOST})"
echo "[00-env] Cluster nodes: ${#NODES[@]}"
echo "[00-env] Prometheus ${PROMETHEUS_VERSION} :${PROMETHEUS_PORT}"
echo "[00-env] Grafana ${GRAFANA_VERSION} :${GRAFANA_PORT}"
echo "[00-env] Alertmanager ${ALERTMANAGER_VERSION} :${ALERTMANAGER_PORT}"
echo "[00-env] PVE Exporter :${PVE_EXPORTER_PORT} + Node Exporter :${NODE_EXPORTER_PORT} por nodo"
