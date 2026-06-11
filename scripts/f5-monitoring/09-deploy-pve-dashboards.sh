#!/bin/bash
# ================================================================
# 09-deploy-pve-dashboards.sh — Deploy PVE dashboards with metrics
# ================================================================
# Generates and imports Proxmox VE dashboards with proper PVE
# PromQL queries into Grafana. Replaces empty placeholder dashboards.
#
# PREREQUISITE: Grafana running, Prometheus datasource UID "prometheus"
# Usage: ./09-deploy-pve-dashboards.sh
# ================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-env.sh"

GRAFANA_URL="http://localhost:${GRAFANA_PORT}"
DS_UID="prometheus"  # Must match datasource UID in Grafana
AUTH="${GRAFANA_ADMIN_USER}:admin123"

# ================================================================
# Helper: build a panel
# ================================================================

stat_panel() {
  local TITLE="$1" METRIC="$2" FORMAT="$3" UNIT="${4:-none}" DECIMALS="${5:-1}"
  cat << PANEL
  {
    "id": $(date +%N | cut -c1-6),
    "type": "stat",
    "title": "${TITLE}",
    "gridPos": {"h": 4, "w": 4, "x": $6, "y": $7},
    "datasource": {"type": "prometheus", "uid": "${DS_UID}"},
    "options": {
      "colorMode": "value",
      "graphMode": "area",
      "justifyMode": "auto",
      "orientation": "auto",
      "reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": false},
      "textMode": "auto"
    },
    "fieldConfig": {
      "defaults": {
        "unit": "${UNIT}",
        "decimals": ${DECIMALS},
        "min": 0,
        "color": {"mode": "thresholds"},
        "thresholds": {"mode": "absolute", "steps": [{"color": "green", "value": null}, {"color": "red", "value": 80}]}
      },
      "overrides": []
    },
    "targets": [{"datasource": {"type": "prometheus", "uid": "${DS_UID}"}, "expr": "${METRIC}", "refId": "A", "legendFormat": "${FORMAT}"}]
  }
PANEL
}

timeseries_panel() {
  local TITLE="$1" METRIC="$2" FORMAT="$3" UNIT="${4:-none}" X="$5" Y="$6"
  cat << PANEL
  {
    "id": $(date +%N | cut -c1-6),
    "type": "timeseries",
    "title": "${TITLE}",
    "gridPos": {"h": 8, "w": 12, "x": ${X}, "y": ${Y}},
    "datasource": {"type": "prometheus", "uid": "${DS_UID}"},
    "options": {
      "legend": {"calcs": ["max", "mean", "last"], "displayMode": "table", "placement": "bottom"},
      "tooltip": {"mode": "multi"}
    },
    "fieldConfig": {
      "defaults": {
        "unit": "${UNIT}",
        "decimals": 1,
        "min": 0,
        "custom": {"drawStyle": "line", "lineInterpolation": "smooth", "fillOpacity": 20, "showPoints": "never"}
      },
      "overrides": []
    },
    "targets": [{"datasource": {"type": "prometheus", "uid": "${DS_UID}"}, "expr": "${METRIC}", "refId": "A", "legendFormat": "${FORMAT}"}]
  }
PANEL
}

table_panel() {
  local TITLE="$1" METRIC="$2" FORMAT="$3" X="$4" Y="$5"
  cat << PANEL
  {
    "id": $(date +%N | cut -c1-6),
    "type": "table",
    "title": "${TITLE}",
    "gridPos": {"h": 8, "w": 24, "x": ${X}, "y": ${Y}},
    "datasource": {"type": "prometheus", "uid": "${DS_UID}"},
    "options": {
      "sortBy": [{"displayName": "Value", "desc": true}]
    },
    "fieldConfig": {
      "defaults": {},
      "overrides": []
    },
    "targets": [{"datasource": {"type": "prometheus", "uid": "${DS_UID}"}, "expr": "${METRIC}", "refId": "A", "format": "table", "legendFormat": "${FORMAT}"}]
  }
PANEL
}

# ================================================================
# Dashboard generators
# ================================================================

cluster_overview() {
cat << JSON
{
  "dashboard": {
    "id": null,
    "uid": "2ffb81a5-b044-4f69-bae3-87c3583dd7e0",
    "title": "Proxmox Cluster Overview",
    "tags": ["proxmox", "pve", "cluster"],
    "timezone": "browser",
    "time": {"from": "now-6h", "to": "now"},
    "refresh": "30s",
    "schemaVersion": 39,
    "version": 0,
    "panels": [
      {
        "id": $(date +%N | cut -c1-6),
        "type": "stat",
        "title": "Cluster",
        "gridPos": {"h": 3, "w": 4, "x": 0, "y": 0},
        "datasource": {"type": "prometheus", "uid": "${DS_UID}"},
        "options": {"colorMode": "value", "graphMode": "none", "reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": false}, "textMode": "name"},
        "fieldConfig": {"defaults": {"color": {"mode": "thresholds"}, "thresholds": {"mode": "absolute", "steps": [{"color": "green", "value": null}]}}, "overrides": []},
        "targets": [{"datasource": {"type": "prometheus", "uid": "${DS_UID}"}, "expr": "pve_cluster_info", "refId": "A", "legendFormat": "{{cluster}}"}]
      },
      {
        "id": $(date +%N | cut -c1-6),
        "type": "stat",
        "title": "Nodes",
        "gridPos": {"h": 3, "w": 4, "x": 4, "y": 0},
        "datasource": {"type": "prometheus", "uid": "${DS_UID}"},
        "options": {"colorMode": "value", "graphMode": "none", "reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": false}, "textMode": "auto"},
        "fieldConfig": {"defaults": {"unit": "none", "color": {"mode": "thresholds"}, "thresholds": {"mode": "absolute", "steps": [{"color": "green", "value": null}]}}, "overrides": []},
        "targets": [{"datasource": {"type": "prometheus", "uid": "${DS_UID}"}, "expr": "pve_cluster_info", "refId": "A", "legendFormat": "{{nodes}} nodes"}]
      },
      {
        "id": $(date +%N | cut -c1-6),
        "type": "stat",
        "title": "Quorate",
        "gridPos": {"h": 3, "w": 4, "x": 8, "y": 0},
        "datasource": {"type": "prometheus", "uid": "${DS_UID}"},
        "options": {"colorMode": "value", "graphMode": "none", "reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": false}, "textMode": "auto"},
        "fieldConfig": {"defaults": {"color": {"mode": "thresholds"}, "thresholds": {"mode": "absolute", "steps": [{"color": "green", "value": null}, {"color": "red", "value": 0}]}}, "overrides": []},
        "targets": [{"datasource": {"type": "prometheus", "uid": "${DS_UID}"}, "expr": "pve_cluster_info{quorate=\"1\"}", "refId": "A", "legendFormat": "quorate"}]
      },
      {
        "id": $(date +%N | cut -c1-6),
        "type": "stat",
        "title": "Version",
        "gridPos": {"h": 3, "w": 4, "x": 12, "y": 0},
        "datasource": {"type": "prometheus", "uid": "${DS_UID}"},
        "options": {"colorMode": "value", "graphMode": "none", "reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": false}, "textMode": "name"},
        "fieldConfig": {"defaults": {"color": {"mode": "thresholds"}, "thresholds": {"mode": "absolute", "steps": [{"color": "green", "value": null}]}}, "overrides": []},
        "targets": [{"datasource": {"type": "prometheus", "uid": "${DS_UID}"}, "expr": "pve_version_info", "refId": "A", "legendFormat": "{{release}}"}]
      },
      {
        "id": $(date +%N | cut -c1-6),
        "type": "stat",
        "title": "Subscription",
        "gridPos": {"h": 3, "w": 4, "x": 16, "y": 0},
        "datasource": {"type": "prometheus", "uid": "${DS_UID}"},
        "options": {"colorMode": "value", "graphMode": "none", "reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": false}, "textMode": "name"},
        "fieldConfig": {"defaults": {"color": {"mode": "thresholds"}, "thresholds": {"mode": "absolute", "steps": [{"color": "green", "value": null}, {"color": "red", "value": 0}]}}, "overrides": []},
        "targets": [{"datasource": {"type": "prometheus", "uid": "${DS_UID}"}, "expr": "pve_subscription_info", "refId": "A", "legendFormat": "{{level}}"}]
      },
      {
        "id": $(date +%N | cut -c1-6),
        "type": "stat",
        "title": "Unbacked Up Guests",
        "gridPos": {"h": 3, "w": 4, "x": 20, "y": 0},
        "datasource": {"type": "prometheus", "uid": "${DS_UID}"},
        "options": {"colorMode": "value", "graphMode": "none", "reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": false}, "textMode": "auto"},
        "fieldConfig": {"defaults": {"unit": "none", "color": {"mode": "thresholds"}, "thresholds": {"mode": "absolute", "steps": [{"color": "green", "value": null}, {"color": "orange", "value": 1}, {"color": "red", "value": 5}]}}, "overrides": []},
        "targets": [{"datasource": {"type": "prometheus", "uid": "${DS_UID}"}, "expr": "pve_not_backed_up_total", "refId": "A", "legendFormat": "not backed up"}]
      },
      $(table_panel "Nodes" 'count by (node) (pve_node_info)' '{{node}}' 0 3)
    ],
    "templating": {"list": []}
  },
  "overwrite": true,
  "folderUid": "",
  "message": "Deployed by 09-deploy-pve-dashboards.sh"
}
JSON
}

proxmox_hardware() {
cat << JSON
{
  "dashboard": {
    "id": null,
    "uid": "proxmox-hardware",
    "title": "Proxmox Hardware",
    "tags": ["proxmox", "pve", "hardware"],
    "timezone": "browser",
    "time": {"from": "now-6h", "to": "now"},
    "refresh": "30s",
    "schemaVersion": 39,
    "version": 0,
    "panels": [
      $(stat_panel "Nodes" 'count(pve_node_info)' 'nodes' 'none' 0 0 0 0),
      $(stat_panel "VMs" 'count(pve_guest_info{type="qemu"})' 'VMs' 'none' 0 4 0 1),
      $(stat_panel "Containers" 'count(pve_guest_info{type="lxc"})' 'CTs' 'none' 0 8 0 1),
      $(stat_panel "Templates" 'count(pve_guest_info{template="1"})' 'templates' 'none' 0 12 0 1),
      $(stat_panel "Running" 'count(pve_up == 1)' 'running' 'none' 0 16 0 1),
      $(stat_panel "Stopped" 'count(pve_up == 0)' 'stopped' 'none' 0 20 0 1),
      $(timeseries_panel "CPU Usage Ratio (Guests)" 'avg by (node) (pve_cpu_usage_ratio * 100)' '{{node}}' 'percent' 0 2),
      $(timeseries_panel "Memory Usage" 'avg by (node) (pve_memory_usage_bytes)' '{{node}}' 'bytes' 12 2),
      $(timeseries_panel "Disk Read" 'rate(pve_disk_read_bytes_total[5m])' '{{node}}' 'Bps' 0 10),
      $(timeseries_panel "Disk Write" 'rate(pve_disk_written_bytes_total[5m])' '{{node}}' 'Bps' 12 10)
    ],
    "templating": {"list": []}
  },
  "overwrite": true,
  "folderUid": "",
  "message": "Deployed by 09-deploy-pve-dashboards.sh"
}
JSON
}

proxmox_vms() {
cat << JSON
{
  "dashboard": {
    "id": null,
    "uid": "proxmox-vms",
    "title": "Proxmox VMs",
    "tags": ["proxmox", "pve", "vms"],
    "timezone": "browser",
    "time": {"from": "now-6h", "to": "now"},
    "refresh": "30s",
    "schemaVersion": 39,
    "version": 0,
    "panels": [
      $(stat_panel "Total VMs" 'count(pve_guest_info{type="qemu",template="0"})' 'VMs' 'none' 0 0 0 0),
      $(stat_panel "Running" 'count(pve_up{type="qemu"} == 1)' 'running' 'none' 0 4 0 0),
      $(stat_panel "Stopped" 'count(pve_up{type="qemu"} == 0)' 'stopped' 'none' 0 8 0 0),
      $(stat_panel "Templates" 'count(pve_guest_info{type="qemu",template="1"})' 'templates' 'none' 0 12 0 0),
      $(stat_panel "vCPUs Total" 'sum(pve_cpu_usage_limit{type="qemu"})' 'vCPUs' 'none' 0 16 0 0),
      $(stat_panel "Memory Total" 'sum(pve_memory_size_bytes{type="qemu"})' 'memory' 'bytes' 0 20 0 0),
      $(table_panel "VM List" 'pve_guest_info{type="qemu",template="0"}' '{{name}} ({{id}})' 0 1),
      $(timeseries_panel "VM CPU Usage" 'pve_cpu_usage_ratio{type="qemu"} * 100' '{{id}} {{name}}' 'percent' 0 9),
      $(timeseries_panel "VM Memory" 'pve_memory_usage_bytes{type="qemu"}' '{{id}} {{name}}' 'bytes' 12 9)
    ],
    "templating": {"list": []}
  },
  "overwrite": true,
  "folderUid": "",
  "message": "Deployed by 09-deploy-pve-dashboards.sh"
}
JSON
}

proxmox_cts() {
cat << JSON
{
  "dashboard": {
    "id": null,
    "uid": "proxmox-cts",
    "title": "Proxmox Containers",
    "tags": ["proxmox", "pve", "containers"],
    "timezone": "browser",
    "time": {"from": "now-6h", "to": "now"},
    "refresh": "30s",
    "schemaVersion": 39,
    "version": 0,
    "panels": [
      $(stat_panel "Total CTs" 'count(pve_guest_info{type="lxc"})' 'CTs' 'none' 0 0 0 0),
      $(stat_panel "Running" 'count(pve_up{type="lxc"} == 1)' 'running' 'none' 0 4 0 0),
      $(stat_panel "Stopped" 'count(pve_up{type="lxc"} == 0)' 'stopped' 'none' 0 8 0 0),
      $(stat_panel "On Boot" 'count(pve_onboot_status == 1)' 'onboot' 'none' 0 12 0 0),
      $(table_panel "Container List" 'pve_guest_info{type="lxc"}' '{{name}} ({{id}})' 0 1),
      $(timeseries_panel "CT CPU" 'pve_cpu_usage_ratio{type="lxc"} * 100' '{{id}} {{name}}' 'percent' 0 9),
      $(timeseries_panel "CT Memory" 'pve_memory_usage_bytes{type="lxc"}' '{{id}} {{name}}' 'bytes' 12 9)
    ],
    "templating": {"list": []}
  },
  "overwrite": true,
  "folderUid": "",
  "message": "Deployed by 09-deploy-pve-dashboards.sh"
}
JSON
}

proxmox_storage() {
cat << JSON
{
  "dashboard": {
    "id": null,
    "uid": "proxmox-backups",
    "title": "Proxmox Backups",
    "tags": ["proxmox", "pve", "storage", "backups"],
    "timezone": "browser",
    "time": {"from": "now-6h", "to": "now"},
    "refresh": "30s",
    "schemaVersion": 39,
    "version": 0,
    "panels": [
      $(stat_panel "Total Storage" 'count(pve_storage_info)' 'targets' 'none' 0 0 0 0),
      $(stat_panel "Shared" 'count(pve_storage_shared == 1)' 'shared' 'none' 0 4 0 0),
      $(stat_panel "Unbacked Up" 'pve_not_backed_up_total' 'guests' 'none' 0 8 0 0),
      $(stat_panel "Unique Types" 'count(count by (plugintype) (pve_storage_info))' 'types' 'none' 0 12 0 0),
      $(table_panel "Storage Inventory" 'pve_storage_info' '{{storage}} ({{plugintype}})' 0 1),
      $(table_panel "Disk Usage by Guest" 'pve_disk_usage_bytes / pve_disk_size_bytes * 100' '{{id}}' 0 9)
    ],
    "templating": {"list": []}
  },
  "overwrite": true,
  "folderUid": "",
  "message": "Deployed by 09-deploy-pve-dashboards.sh"
}
JSON
}

proxmox_networking() {
cat << JSON
{
  "dashboard": {
    "id": null,
    "uid": "proxmox-networking",
    "title": "Proxmox Networking",
    "tags": ["proxmox", "pve", "networking"],
    "timezone": "browser",
    "time": {"from": "now-6h", "to": "now"},
    "refresh": "30s",
    "schemaVersion": 39,
    "version": 0,
    "panels": [
      $(stat_panel "Network Interfaces" 'count(count by (iface) (pve_network_receive_bytes_total))' 'interfaces' 'none' 0 0 0 0),
      $(timeseries_panel "Network Receive" 'rate(pve_network_receive_bytes_total[5m])' '{{iface}}' 'Bps' 0 1),
      $(timeseries_panel "Network Transmit" 'rate(pve_network_transmit_bytes_total[5m])' '{{iface}}' 'Bps' 12 1),
      $(timeseries_panel "Total Receive" 'sum(rate(pve_network_receive_bytes_total[5m]))' 'all interfaces' 'Bps' 0 9),
      $(timeseries_panel "Total Transmit" 'sum(rate(pve_network_transmit_bytes_total[5m]))' 'all interfaces' 'Bps' 12 9)
    ],
    "templating": {"list": []}
  },
  "overwrite": true,
  "folderUid": "",
  "message": "Deployed by 09-deploy-pve-dashboards.sh"
}
JSON
}

proxmox_incidents() {
cat << JSON
{
  "dashboard": {
    "id": null,
    "uid": "proxmox-incidents",
    "title": "Proxmox Incidents & Recovery",
    "tags": ["proxmox", "pve", "incidents", "ha"],
    "timezone": "browser",
    "time": {"from": "now-24h", "to": "now"},
    "refresh": "60s",
    "schemaVersion": 39,
    "version": 0,
    "panels": [
      $(stat_panel "Locked Guests" 'count(pve_lock_state == 1)' 'locked' 'none' 0 0 0 0),
      $(stat_panel "HA Managed" 'count(pve_ha_state == 1)' 'managed' 'none' 0 4 0 0),
      $(stat_panel "HA Inactive" 'count(pve_ha_state{state="stopped"} == 1)' 'stopped' 'none' 0 8 0 0),
      $(stat_panel "Subscriptions" 'count(pve_subscription_info{level="unknown"})' 'unknown' 'none' 0 12 0 0),
      $(table_panel "Guests with Locks" 'pve_lock_state == 1' '{{id}} ({{state}})' 0 1),
      $(table_panel "HA State Overview" 'pve_ha_state == 1' '{{id}} ({{state}})' 0 9)
    ],
    "templating": {"list": []}
  },
  "overwrite": true,
  "folderUid": "",
  "message": "Deployed by 09-deploy-pve-dashboards.sh"
}
JSON
}

proxmox_node_detail() {
cat << JSON
{
  "dashboard": {
    "id": null,
    "uid": "proxmox-node-detail",
    "title": "Proxmox Node Detail",
    "tags": ["proxmox", "pve", "node"],
    "timezone": "browser",
    "time": {"from": "now-6h", "to": "now"},
    "refresh": "30s",
    "schemaVersion": 39,
    "version": 0,
    "templating": {
      "list": [
        {
          "name": "node",
          "type": "query",
          "datasource": {"type": "prometheus", "uid": "${DS_UID}"},
          "query": "label_values(pve_node_info, node)",
          "refresh": 1,
          "sort": 1,
          "includeAll": false,
          "multi": false
        }
      ]
    },
    "panels": [
      $(stat_panel "Guest VMs" 'count(pve_guest_info{type="qemu",exported_node=~"$node"})' 'VMs' 'none' 0 0 0 0),
      $(stat_panel "Guest CTs" 'count(pve_guest_info{type="lxc",exported_node=~"$node"})' 'CTs' 'none' 0 4 0 0),
      $(stat_panel "Running" 'count(pve_up{exported_node=~"$node"} == 1)' 'running' 'none' 0 8 0 0),
      $(stat_panel "Stopped" 'count(pve_up{exported_node=~"$node"} == 0)' 'stopped' 'none' 0 12 0 0),
      $(stat_panel "Uptime (node)" 'avg(pve_uptime_seconds{type="node",node=~"$node"})' 'seconds' 'seconds' 0 16 0 0),
      $(stat_panel "Version" 'pve_version_info{node=~"$node"}' '{{release}}' 'none' 0 20 0 0),
      $(timeseries_panel "CPU Usage" 'avg(pve_cpu_usage_ratio{exported_node=~"$node"}) * 100' 'avg guest CPU' 'percent' 0 1),
      $(timeseries_panel "Guest Memory" 'sum(pve_memory_usage_bytes{exported_node=~"$node"})' 'used' 'bytes' 12 1),
      $(timeseries_panel "Disk Read" 'sum(rate(pve_disk_read_bytes_total{exported_node=~"$node"}[5m]))' 'total read' 'Bps' 0 9),
      $(timeseries_panel "Disk Write" 'sum(rate(pve_disk_written_bytes_total{exported_node=~"$node"}[5m]))' 'total write' 'Bps' 12 9),
      $(table_panel "Guests on Node" 'pve_guest_info{exported_node=~"$node"}' '{{name}} ({{type}}/{{id}})' 0 17)
    ]
  },
  "overwrite": true,
  "folderUid": "",
  "message": "Deployed by 09-deploy-pve-dashboards.sh"
}
JSON
}

proxmox_vm_ct_detail() {
cat << JSON
{
  "dashboard": {
    "id": null,
    "uid": "proxmox-vm-detail",
    "title": "Proxmox VM/CT Detail",
    "tags": ["proxmox", "pve", "guests", "vms", "containers"],
    "timezone": "browser",
    "time": {"from": "now-6h", "to": "now"},
    "refresh": "30s",
    "schemaVersion": 39,
    "version": 0,
    "templating": {
      "list": [
        {
          "name": "guest",
          "type": "query",
          "datasource": {"type": "prometheus", "uid": "${DS_UID}"},
          "query": "label_values(pve_guest_info, name)",
          "refresh": 1,
          "sort": 1,
          "includeAll": true,
          "multi": false
        }
      ]
    },
    "panels": [
      $(stat_panel "Status" 'pve_up{name=~"$guest"}' '{{name}}' 'none' 0 0 0 0),
      $(stat_panel "Type" 'pve_guest_info{name=~"$guest"}' '{{type}}' 'none' 0 4 0 0),
      $(stat_panel "Node" 'pve_guest_info{name=~"$guest"}' '{{exported_node}}' 'none' 0 8 0 0),
      $(stat_panel "vCPUs" 'pve_cpu_usage_limit{name=~"$guest"}' '{{name}}' 'none' 0 12 0 0),
      $(stat_panel "Memory" 'pve_memory_size_bytes{name=~"$guest"}' '{{name}}' 'bytes' 0 16 0 0),
      $(stat_panel "Uptime" 'pve_uptime_seconds{name=~"$guest"}' 'seconds' 'seconds' 0 20 0 0),
      $(timeseries_panel "CPU Usage" 'pve_cpu_usage_ratio{name=~"$guest"} * 100' 'CPU %' 'percent' 0 1),
      $(timeseries_panel "Memory Usage" 'pve_memory_usage_bytes{name=~"$guest"}' 'used' 'bytes' 12 1),
      $(timeseries_panel "Disk Read" 'rate(pve_disk_read_bytes_total{name=~"$guest"}[5m])' 'read' 'Bps' 0 9),
      $(timeseries_panel "Disk Write" 'rate(pve_disk_written_bytes_total{name=~"$guest"}[5m])' 'write' 'Bps' 12 9),
      $(timeseries_panel "Network Receive" 'rate(pve_network_receive_bytes_total{name=~"$guest"}[5m])' 'rx' 'Bps' 0 17),
      $(timeseries_panel "Network Transmit" 'rate(pve_network_transmit_bytes_total{name=~"$guest"}[5m])' 'tx' 'Bps' 12 17)
    ]
  },
  "overwrite": true,
  "folderUid": "",
  "message": "Deployed by 09-deploy-pve-dashboards.sh"
}
JSON
}

# ================================================================
# Deploy
# ================================================================

echo "=== Desplegando dashboards PVE en Grafana ==="
echo ""

DASHBOARDS=(
  "Proxmox Cluster Overview:cluster_overview"
  "Proxmox Hardware:proxmox_hardware"
  "Proxmox VMs:proxmox_vms"
  "Proxmox Containers:proxmox_cts"
  "Proxmox Backups:proxmox_storage"
  "Proxmox Networking:proxmox_networking"
  "Proxmox Incidents:proxmox_incidents"
  "Proxmox Node Detail:proxmox_node_detail"
  "Proxmox VM/CT Detail:proxmox_vm_ct_detail"
)

for ENTRY in "${DASHBOARDS[@]}"; do
  NAME="${ENTRY%%:*}"
  FUNC="${ENTRY##*:}"
  echo "[→] ${NAME}..."

  # Generate JSON and escape Grafana template vars ($node, $guest) from bash
  JSON=$($FUNC | sed 's/\$node/\\$node/g; s/\$guest/\\$guest/g')
  if [ -z "$JSON" ]; then
    echo "  ❌ Error generando JSON para ${NAME}"
    continue
  fi

  # Write JSON to a temp file in the container and post via API
  # We write to /tmp to avoid shell quoting issues
  TMP_FILE="/tmp/pve-dash-$(echo "$NAME" | md5sum | cut -c1-8).json"
  echo "$JSON" > "/tmp/$(basename $TMP_FILE)"

  # Copy to host, then to container
  scp ${SSH_OPTS} "/tmp/$(basename $TMP_FILE)" "root@${CT_MONITORING_IP}:/tmp/$(basename $TMP_FILE)" 2>/dev/null
  ssh ${SSH_OPTS} root@${CT_MONITORING_IP} \
    "pct push ${CT_MONITORING_ID} /tmp/$(basename $TMP_FILE) ${TMP_FILE}" 2>/dev/null

  # Import via API
  RESULT=$(ssh ${SSH_OPTS} root@${CT_MONITORING_IP} \
    "pct exec ${CT_MONITORING_ID} -- curl -sf -X POST -H 'Content-Type: application/json' \
      -u ${AUTH} -d @${TMP_FILE} \
      http://localhost:${GRAFANA_PORT}/api/dashboards/db" 2>/dev/null || echo "")

  if echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if d.get('status')=='success' else 1)" 2>/dev/null; then
    echo "  ✅ ${NAME} — importado"
    # Save to provisioning for persistence
    ssh ${SSH_OPTS} root@${CT_MONITORING_IP} \
      "pct exec ${CT_MONITORING_ID} -- cp ${TMP_FILE} /var/lib/grafana/dashboards/$(echo "$NAME" | tr ' ' '-' | tr '[:upper:]' '[:lower:]').json" 2>/dev/null && \
      echo "   💾 Persistido en provisioning"
  else
    echo "  ❌ Error: $(echo "$RESULT" | head -c 200)"
  fi

  # Cleanup
  ssh ${SSH_OPTS} root@${CT_MONITORING_IP} \
    "pct exec ${CT_MONITORING_ID} -- rm -f ${TMP_FILE}" 2>/dev/null || true
  rm -f "/tmp/$(basename $TMP_FILE)"
  ssh root@${CT_MONITORING_IP} "rm -f /tmp/$(basename $TMP_FILE)" 2>/dev/null || true

  echo ""
done

echo "=== Despliegue completado ==="
echo "Revisar dashboards en http://${CT_MONITORING_IP}:${GRAFANA_PORT}"
