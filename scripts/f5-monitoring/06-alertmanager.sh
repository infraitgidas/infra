#!/bin/bash
# ================================================================
# 06-alertmanager.sh — Task 5.5: Configure Alertmanager + rules
# ================================================================
# Installs and configures Alertmanager on CT sg-monitoring.
# Creates alert rules for:
#   - Quorum loss (<3 nodes healthy)
#   - ZFS errors (checksum, I/O errors on any pool)
#   - Disk usage >80%
#   - Backup failure (PBS job not completed)
#
# DESIGN: Alertmanager is co-located with Prometheus on the monitoring
# CT so it survives cluster failure. Rules are in /etc/prometheus/alerts.yml.
# Rollback: systemctl stop alertmanager, rm -rf /etc/alertmanager
# ================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-env.sh"

echo "=== Task 5.5: Configurar Alertmanager + reglas de alerta ==="
echo ""

# ---------------------------------------------------------------
# Step 1: Install Alertmanager binary
# ---------------------------------------------------------------
echo "[1/6] Instalando Alertmanager ${ALERTMANAGER_VERSION}..."
ssh ${SSH_OPTS} root@${CT_MONITORING_IP} "
    set -e
    if [ ! -f /usr/local/bin/alertmanager ]; then
        cd /tmp
        wget -q https://github.com/prometheus/alertmanager/releases/download/v${ALERTMANAGER_VERSION}/alertmanager-${ALERTMANAGER_VERSION}.linux-amd64.tar.gz
        tar xzf alertmanager-${ALERTMANAGER_VERSION}.linux-amd64.tar.gz
        cp alertmanager-${ALERTMANAGER_VERSION}.linux-amd64/alertmanager /usr/local/bin/
        cp alertmanager-${ALERTMANAGER_VERSION}.linux-amd64/amtool /usr/local/bin/
        chmod 755 /usr/local/bin/alertmanager /usr/local/bin/amtool
        rm -rf /tmp/alertmanager-${ALERTMANAGER_VERSION}.linux-amd64*
        echo '✅ Alertmanager binario instalado'
    else
        echo 'ℹ️  Alertmanager ya instalado'
    fi
" 2>/dev/null
echo "[1/6] ✅ Alertmanager instalado"
echo ""

# ---------------------------------------------------------------
# Step 2: Create alert rules file
# ---------------------------------------------------------------
echo "[2/6] Creando reglas de alerta en /etc/prometheus/alerts.yml..."
ssh ${SSH_OPTS} root@${CT_MONITORING_IP} "
    set -e
    mkdir -p ${PROMETHEUS_HOME}

    cat > ${PROMETHEUS_HOME}/alerts.yml << 'ALERTSEOF'
groups:
  - name: pve-cluster
    interval: 30s
    rules:

      # --- Quorum alert ---
      - alert: PVEQuorumLoss
        expr: count(pve_node_status_online == 1) < 3
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: 'Pérdida de quorum en cluster pve-gidas'
          description: 'Solo {{ \$value }} nodo(s) online (mínimo 3 para quorum). Cluster puede estar degradado o particionado.'
          runbook: 'Verificar corosync: corosync-cfgtool -s. Revisar link0 y link1 en cada nodo. Si es necesario, reiniciar corosync nodo por nodo.'

      # --- ZFS health alert ---
      - alert: ZFSPoolDegraded
        expr: zfs_pool_health_status{pve_node=~\"pve-desa0[1-4]\"} != 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: 'Pool ZFS degradado en {{ \$labels.pve_node }}'
          description: 'El pool ZFS {{ \$labels.pool }} reporta estado anormal. Ejecutar: zpool status -v. Revisar checksum e I/O errors.'
          runbook: 'ssh {{ \$labels.pve_node }} \"zpool status -v\" para diagnosticar. Si hay checksum errors: zpool clear <pool>. Si hay I/O errors: verificar disco físico.'

      # --- Disk usage >80% ---
      - alert: DiskUsageHigh
        expr: |
          (node_filesystem_avail_bytes{mountpoint=\"/\",fstype!=\"\"} / node_filesystem_size_bytes{mountpoint=\"/\",fstype!=\"\"}) * 100 < 20
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: 'Disco {{ \$labels.mountpoint }} en {{ \$labels.instance }} al {{ \"%.0f\" | printf (100 - ((\$value / 100) * 100)) }}%'
          description: 'Uso de disco {{ \$labels.mountpoint }} supera 80% en {{ \$labels.instance }}. Espacio libre: {{ \$value | humanizePercentage }}'
          runbook: 'ssh {{ \$labels.instance }} \"df -h\" para verificar. Limpiar logs viejos, snapshots temporales, o imágenes de backup no necesarias.'

      # --- Disk usage >90% (critical threshold) ---
      - alert: DiskUsageCritical
        expr: |
          (node_filesystem_avail_bytes{mountpoint=\"/\",fstype!=\"\"} / node_filesystem_size_bytes{mountpoint=\"/\",fstype!=\"\"}) * 100 < 10
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: '⚠️ Disco {{ \$labels.mountpoint }} CRÍTICO en {{ \$labels.instance }}'
          description: 'Uso de disco supera 90%. Riesgo de fallo de VMs y servicios. Liberar espacio URGENTE.'
          runbook: 'ssh {{ \$labels.instance }} \"du -sh /* | sort -rh | head -10\" para identificar más usados.'

      # --- Backup failure alert ---
      - alert: BackupJobFailed
        expr: time() - pve_backup_last_finish_timestamp > 90000
        for: 1h
        labels:
          severity: warning
        annotations:
          summary: 'Backup no completó en las últimas 25 horas'
          description: 'El último backup finalizó hace {{ \"%.0f\" | printf ((\$value / 3600)) }} horas. Verificar estado del job de backup y PBS.'
          runbook: 'Verificar PBS: proxmox-backup-manager snapshot list. Revisar job: cat /etc/pve/jobs.cfg. Verificar storage: pvesh get /storage.'

      # --- Node offline ---
      - alert: PVENodeDown
        expr: pve_node_status_online == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: 'Nodo {{ \$labels.pve_node }} OFFLINE'
          description: 'El nodo {{ \$labels.pve_node }} no responde desde hace más de 2 minutos.'
          runbook: 'ssh al nodo o verificar console IPMI/KVM. Revisar estado de servicios PVE: systemctl status pveproxy.'
ALERTSEOF

    chown prometheus:prometheus ${PROMETHEUS_HOME}/alerts.yml
    chmod 644 ${PROMETHEUS_HOME}/alerts.yml
    echo '✅ Reglas de alerta creadas'
" 2>/dev/null
echo "[2/6] ✅ Reglas de alerta creadas"
echo ""

# ---------------------------------------------------------------
# Step 3: Create Alertmanager config
# ---------------------------------------------------------------
echo "[3/6] Creando configuración de Alertmanager..."
ssh ${SSH_OPTS} root@${CT_MONITORING_IP} "
    set -e
    mkdir -p ${ALERTMANAGER_HOME}

    cat > ${ALERTMANAGER_HOME}/alertmanager.yml << 'AMEOF'
global:
  resolve_timeout: 5m
  smtp_smarthost: 'localhost:25'
  smtp_from: 'alertmanager@pve-gidas.local'
  smtp_require_tls: false

route:
  group_by: ['alertname', 'cluster']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
  receiver: 'default'

receivers:
  - name: 'default'
    email_configs:
      - to: 'admin@pve-gidas.local'
        send_resolved: true

  - name: 'critical'
    email_configs:
      - to: 'admin@pve-gidas.local'
        send_resolved: true

inhibit_rules:
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['pve_node', 'cluster']
AMEOF

    chown -R prometheus:prometheus ${ALERTMANAGER_HOME}
    chmod 644 ${ALERTMANAGER_HOME}/alertmanager.yml
    echo '✅ Config Alertmanager creada'
" 2>/dev/null
echo "[3/6] ✅ Config Alertmanager creada"
echo ""

# ---------------------------------------------------------------
# Step 4: Create Alertmanager systemd service
# ---------------------------------------------------------------
echo "[4/6] Creando servicio systemd de Alertmanager..."
ssh ${SSH_OPTS} root@${CT_MONITORING_IP} "
    if [ ! -f /etc/systemd/system/alertmanager.service ]; then
        cat > /etc/systemd/system/alertmanager.service << 'SVC'
[Unit]
Description=Prometheus Alertmanager
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=prometheus
Group=prometheus
ExecStart=/usr/local/bin/alertmanager \
    --config.file=/etc/alertmanager/alertmanager.yml \
    --storage.path=/var/lib/alertmanager \
    --web.listen-address=:9093

Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SVC
        systemctl daemon-reload
        echo '✅ Servicio systemd creado'
    else
        echo 'ℹ️  Servicio ya existe'
    fi
" 2>/dev/null
echo "[4/6] ✅ Servicio Alertmanager listo"
echo ""

# ---------------------------------------------------------------
# Step 5: Start Alertmanager and reload Prometheus
# ---------------------------------------------------------------
echo "[5/6] Iniciando Alertmanager y recargando Prometheus..."
ssh ${SSH_OPTS} root@${CT_MONITORING_IP} "
    set -e

    # Create data directory
    mkdir -p /var/lib/alertmanager
    chown prometheus:prometheus /var/lib/alertmanager

    # Start Alertmanager
    systemctl enable alertmanager.service 2>/dev/null
    systemctl restart alertmanager.service
    sleep 2
    if systemctl is-active --quiet alertmanager; then
        echo '✅ Alertmanager activo'
    else
        echo '❌ Alertmanager no inició'
        systemctl status alertmanager --no-pager 2>&1 | tail -10
        exit 1
    fi

    # Reload Prometheus to pick up alert rules
    systemctl reload prometheus 2>/dev/null || systemctl restart prometheus
    sleep 1
    echo '✅ Prometheus recargado con reglas de alerta'
" 2>/dev/null
echo "[5/6] ✅ Alertmanager iniciado y Prometheus recargado"
echo ""

# ---------------------------------------------------------------
# Step 6: Verify alerts are loaded
# ---------------------------------------------------------------
echo "[6/6] Verificando reglas de alerta en Prometheus..."
ALERTS=$(curl -sf "http://${CT_MONITORING_IP}:${PROMETHEUS_PORT}/api/v1/rules" 2>/dev/null || echo "")
if [ -n "${ALERTS}" ]; then
    echo "${ALERTS}" | python3 -c "
import sys, json
data = json.load(sys.stdin)
groups = data.get('data', {}).get('groups', [])
for g in groups:
    print(f\"  Grupo: {g.get('name','?')}\")
    for r in g.get('rules', []):
        state = r.get('state', r.get('health', '?'))
        name = r.get('name', '?')
        print(f\"    {'✅' if state=='ok' else 'ℹ️'} {name} ({state})\")
    print('')
" 2>/dev/null || echo "  (no se pudieron parsear reglas)"
else
    echo "  ⚠️  No se pudo consultar API de reglas"
fi

echo ""
echo "=== Task 5.5 completada ==="
echo "  Alertmanager: http://${CT_MONITORING_IP}:${ALERTMANAGER_PORT}"
echo "  Reglas de alerta: ${PROMETHEUS_HOME}/alerts.yml"
echo "  Config Alertmanager: ${ALERTMANAGER_HOME}/alertmanager.yml"
echo ""
echo "  Reglas configuradas:"
echo "    - PVEQuorumLoss: <3 nodos online (critical)"
echo "    - ZFSPoolDegraded: Pool ZFS con errores (critical)"
echo "    - DiskUsageHigh: Disco >80% (warning)"
echo "    - DiskUsageCritical: Disco >90% (critical)"
echo "    - BackupJobFailed: >25h sin backup (warning)"
echo "    - PVENodeDown: Nodo offline >2min (critical)"
echo ""
echo "  Verificar alertas:"
echo "    curl http://${CT_MONITORING_IP}:${PROMETHEUS_PORT}/api/v1/rules"
echo "    curl http://${CT_MONITORING_IP}:${ALERTMANAGER_PORT}/api/v2/alerts"
echo ""
echo "  Rollback:"
echo "    systemctl stop alertmanager"
echo "    rm /etc/prometheus/alerts.yml"
echo "    rm /etc/alertmanager/"
echo "    rm /usr/local/bin/alertmanager /usr/local/bin/amtool"
