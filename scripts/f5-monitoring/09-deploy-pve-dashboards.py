#!/usr/bin/env python3
"""Deploy PVE dashboards to Grafana with proper PromQL queries.

Usage:
  ./09-deploy-pve-dashboards.py            # via SSH tunnel to CT
  ./09-deploy-pve-dashboards.py --direct   # direct to localhost Grafana
"""

import json
import os
import subprocess
import sys
import tempfile
from datetime import datetime

# --- Config ---
CT_HOST = "192.168.1.31"
CT_ID = "205"
GRAFANA_PORT = 3000
DS_UID = "prometheus"
GRAFANA_USER = "admin"
GRAFANA_PASS = "admin123"
GRAFANA_URL = f"http://localhost:{GRAFANA_PORT}"

DASHBOARDS_DIR = "/var/lib/grafana/dashboards"

# Panel counter (unique IDs)
_panel_id = 100


def next_id():
    global _panel_id
    _panel_id += 1
    return _panel_id


def stat_panel(title, expr, legend, x, y, w=4, h=4, unit="none", decimals=1):
    return {
        "id": next_id(),
        "type": "stat",
        "title": title,
        "gridPos": {"h": h, "w": w, "x": x, "y": y},
        "datasource": {"type": "prometheus", "uid": DS_UID},
        "options": {
            "colorMode": "value",
            "graphMode": "area",
            "justifyMode": "auto",
            "orientation": "auto",
            "reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False},
            "textMode": "auto",
        },
        "fieldConfig": {
            "defaults": {
                "unit": unit,
                "decimals": decimals,
                "min": 0,
                "color": {"mode": "thresholds"},
                "thresholds": {
                    "mode": "absolute",
                    "steps": [
                        {"color": "green", "value": None},
                        {"color": "red", "value": 80},
                    ],
                },
            },
            "overrides": [],
        },
        "targets": [
            {
                "datasource": {"type": "prometheus", "uid": DS_UID},
                "expr": expr,
                "refId": "A",
                "legendFormat": legend,
            }
        ],
    }


def timeseries_panel(title, expr, legend, x, y, w=12, h=8, unit="none"):
    return {
        "id": next_id(),
        "type": "timeseries",
        "title": title,
        "gridPos": {"h": h, "w": w, "x": x, "y": y},
        "datasource": {"type": "prometheus", "uid": DS_UID},
        "options": {
            "legend": {
                "calcs": ["max", "mean", "last"],
                "displayMode": "table",
                "placement": "bottom",
            },
            "tooltip": {"mode": "multi"},
        },
        "fieldConfig": {
            "defaults": {
                "unit": unit,
                "decimals": 1,
                "min": 0,
                "custom": {
                    "drawStyle": "line",
                    "lineInterpolation": "smooth",
                    "fillOpacity": 20,
                    "showPoints": "never",
                },
            },
            "overrides": [],
        },
        "targets": [
            {
                "datasource": {"type": "prometheus", "uid": DS_UID},
                "expr": expr,
                "refId": "A",
                "legendFormat": legend,
            }
        ],
    }


def table_panel(title, expr, legend, x, y):
    return {
        "id": next_id(),
        "type": "table",
        "title": title,
        "gridPos": {"h": 8, "w": 24, "x": x, "y": y},
        "datasource": {"type": "prometheus", "uid": DS_UID},
        "options": {"sortBy": [{"displayName": "Value", "desc": True}]},
        "fieldConfig": {"defaults": {}, "overrides": []},
        "targets": [
            {
                "datasource": {"type": "prometheus", "uid": DS_UID},
                "expr": expr,
                "refId": "A",
                "format": "table",
                "legendFormat": legend,
            }
        ],
    }


def make_dashboard(uid, title, panels, templating=None):
    return {
        "dashboard": {
            "id": None,
            "uid": uid,
            "title": title,
            "tags": ["proxmox", "pve"],
            "timezone": "browser",
            "time": {"from": "now-6h", "to": "now"},
            "refresh": "30s",
            "schemaVersion": 39,
            "version": 0,
            "panels": panels,
            "templating": {"list": templating or []},
        },
        "overwrite": True,
        "folderUid": "",
        "message": "Deployed by pve-dashboards script",
    }


# ================================================================
# Dashboard definitions
# ================================================================


def build_cluster_overview():
    return make_dashboard(
        "2ffb81a5-b044-4f69-bae3-87c3583dd7e0",
        "Proxmox Cluster Overview",
        [
            {
                "id": next_id(),
                "type": "stat",
                "title": "Cluster",
                "gridPos": {"h": 3, "w": 4, "x": 0, "y": 0},
                "datasource": {"type": "prometheus", "uid": DS_UID},
                "options": {
                    "colorMode": "value",
                    "graphMode": "none",
                    "reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False},
                    "textMode": "name",
                },
                "fieldConfig": {
                    "defaults": {
                        "color": {"mode": "thresholds"},
                        "thresholds": {
                            "mode": "absolute",
                            "steps": [{"color": "green", "value": None}],
                        },
                    },
                    "overrides": [],
                },
                "targets": [
                    {
                        "datasource": {"type": "prometheus", "uid": DS_UID},
                        "expr": "pve_cluster_info",
                        "refId": "A",
                        "legendFormat": "{{cluster}}",
                    }
                ],
            },
            stat_panel("Nodes", "pve_cluster_info", "{{nodes}} nodes", 4, 0, unit="none"),
            {
                "id": next_id(),
                "type": "stat",
                "title": "Quorate",
                "gridPos": {"h": 3, "w": 4, "x": 8, "y": 0},
                "datasource": {"type": "prometheus", "uid": DS_UID},
                "options": {
                    "colorMode": "value",
                    "graphMode": "none",
                    "reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False},
                    "textMode": "auto",
                },
                "fieldConfig": {
                    "defaults": {
                        "color": {"mode": "thresholds"},
                        "thresholds": {
                            "mode": "absolute",
                            "steps": [
                                {"color": "green", "value": None},
                                {"color": "red", "value": 0},
                            ],
                        },
                    },
                    "overrides": [],
                },
                "targets": [
                    {
                        "datasource": {"type": "prometheus", "uid": DS_UID},
                        "expr": 'pve_cluster_info{quorate="1"}',
                        "refId": "A",
                        "legendFormat": "quorate",
                    }
                ],
            },
            {
                "id": next_id(),
                "type": "stat",
                "title": "Version",
                "gridPos": {"h": 3, "w": 4, "x": 12, "y": 0},
                "datasource": {"type": "prometheus", "uid": DS_UID},
                "options": {
                    "colorMode": "value",
                    "graphMode": "none",
                    "reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False},
                    "textMode": "name",
                },
                "fieldConfig": {
                    "defaults": {
                        "color": {"mode": "thresholds"},
                        "thresholds": {
                            "mode": "absolute",
                            "steps": [{"color": "green", "value": None}],
                        },
                    },
                    "overrides": [],
                },
                "targets": [
                    {
                        "datasource": {"type": "prometheus", "uid": DS_UID},
                        "expr": "pve_version_info",
                        "refId": "A",
                        "legendFormat": "{{release}}",
                    }
                ],
            },
            {
                "id": next_id(),
                "type": "stat",
                "title": "Subscription",
                "gridPos": {"h": 3, "w": 4, "x": 16, "y": 0},
                "datasource": {"type": "prometheus", "uid": DS_UID},
                "options": {
                    "colorMode": "value",
                    "graphMode": "none",
                    "reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False},
                    "textMode": "name",
                },
                "fieldConfig": {
                    "defaults": {
                        "color": {"mode": "thresholds"},
                        "thresholds": {
                            "mode": "absolute",
                            "steps": [
                                {"color": "green", "value": None},
                                {"color": "red", "value": 0},
                            ],
                        },
                    },
                    "overrides": [],
                },
                "targets": [
                    {
                        "datasource": {"type": "prometheus", "uid": DS_UID},
                        "expr": "pve_subscription_info",
                        "refId": "A",
                        "legendFormat": "{{level}}",
                    }
                ],
            },
            stat_panel("Unbacked Up", "pve_not_backed_up_total", "guests", 20, 0, unit="none"),
            table_panel("Nodes", 'count by (node) (pve_node_info)', "{{node}}", 0, 3),
        ],
    )


def build_hardware():
    return make_dashboard(
        "proxmox-hardware",
        "Proxmox Hardware",
        [
            stat_panel("Nodes", "count(pve_node_info)", "nodes", 0, 0, unit="none"),
            stat_panel("VMs", 'count(pve_guest_info{type="qemu"})', "VMs", 4, 0, unit="none"),
            stat_panel("CTs", 'count(pve_guest_info{type="lxc"})', "CTs", 8, 0, unit="none"),
            stat_panel("Templates", 'count(pve_guest_info{template="1"})', "templates", 12, 0, unit="none"),
            stat_panel("Running", "count(pve_up == 1)", "running", 16, 0, unit="none"),
            stat_panel("Stopped", "count(pve_up == 0)", "stopped", 20, 0, unit="none"),
            timeseries_panel("CPU Usage", 'avg by (node) (pve_cpu_usage_ratio * 100)', "{{node}}", 0, 2, unit="percent"),
            timeseries_panel("Memory Usage", 'avg by (node) (pve_memory_usage_bytes)', "{{node}}", 12, 2, unit="bytes"),
            timeseries_panel("Disk Read", 'rate(pve_disk_read_bytes_total[5m])', "{{node}}", 0, 10, unit="Bps"),
            timeseries_panel("Disk Write", 'rate(pve_disk_written_bytes_total[5m])', "{{node}}", 12, 10, unit="Bps"),
        ],
    )


def build_vms():
    return make_dashboard(
        "proxmox-vms", "Proxmox VMs",
        [
            stat_panel("Total VMs", 'count(pve_guest_info{type="qemu",template="0"})', "VMs", 0, 0, unit="none"),
            stat_panel("Running", 'count(pve_up{type="qemu"} == 1)', "running", 4, 0, unit="none"),
            stat_panel("Stopped", 'count(pve_up{type="qemu"} == 0)', "stopped", 8, 0, unit="none"),
            stat_panel("Templates", 'count(pve_guest_info{type="qemu",template="1"})', "templates", 12, 0, unit="none"),
            stat_panel("vCPUs Total", 'sum(pve_cpu_usage_limit{type="qemu"})', "vCPUs", 16, 0, unit="none"),
            stat_panel("Memory Total", 'sum(pve_memory_size_bytes{type="qemu"})', "memory", 20, 0, unit="bytes"),
            table_panel("VM List", 'pve_guest_info{type="qemu",template="0"}', "{{name}} ({{id}})", 0, 1),
            timeseries_panel("VM CPU Usage", 'pve_cpu_usage_ratio{type="qemu"} * 100', "{{id}} {{name}}", 0, 9, unit="percent"),
            timeseries_panel("VM Memory", 'pve_memory_usage_bytes{type="qemu"}', "{{id}} {{name}}", 12, 9, unit="bytes"),
        ],
    )


def build_cts():
    return make_dashboard(
        "proxmox-cts", "Proxmox Containers",
        [
            stat_panel("Total CTs", "count(pve_guest_info{type='lxc'})", "CTs", 0, 0, unit="none"),
            stat_panel("Running", 'count(pve_up{type="lxc"} == 1)', "running", 4, 0, unit="none"),
            stat_panel("Stopped", 'count(pve_up{type="lxc"} == 0)', "stopped", 8, 0, unit="none"),
            stat_panel("On Boot", "count(pve_onboot_status == 1)", "onboot", 12, 0, unit="none"),
            table_panel("Container List", "pve_guest_info{type='lxc'}", "{{name}} ({{id}})", 0, 1),
            timeseries_panel("CT CPU", 'pve_cpu_usage_ratio{type="lxc"} * 100', "{{id}} {{name}}", 0, 9, unit="percent"),
            timeseries_panel("CT Memory", 'pve_memory_usage_bytes{type="lxc"}', "{{id}} {{name}}", 12, 9, unit="bytes"),
        ],
    )


def build_storage():
    return make_dashboard(
        "proxmox-backups", "Proxmox Backups",
        [
            stat_panel("Total Storage", "count(pve_storage_info)", "targets", 0, 0, unit="none"),
            stat_panel("Shared", "count(pve_storage_shared == 1)", "shared", 4, 0, unit="none"),
            stat_panel("Unbacked Up", "pve_not_backed_up_total", "guests", 8, 0, unit="none"),
            stat_panel("Storage Types", "count(count by (plugintype) (pve_storage_info))", "types", 12, 0, unit="none"),
            table_panel("Storage Inventory", "pve_storage_info", "{{storage}} ({{plugintype}})", 0, 1),
            table_panel("Disk Usage by Guest", "pve_disk_usage_bytes / pve_disk_size_bytes * 100", "{{id}}", 0, 9),
        ],
    )


def build_networking():
    return make_dashboard(
        "proxmox-networking", "Proxmox Networking",
        [
            stat_panel("Interfaces", "count(count by (iface) (pve_network_receive_bytes_total))", "interfaces", 0, 0, unit="none"),
            timeseries_panel("Network Receive", 'rate(pve_network_receive_bytes_total[5m])', "{{iface}}", 0, 1, unit="Bps"),
            timeseries_panel("Network Transmit", 'rate(pve_network_transmit_bytes_total[5m])', "{{iface}}", 12, 1, unit="Bps"),
            timeseries_panel("Total Receive", "sum(rate(pve_network_receive_bytes_total[5m]))", "all", 0, 9, unit="Bps"),
            timeseries_panel("Total Transmit", "sum(rate(pve_network_transmit_bytes_total[5m]))", "all", 12, 9, unit="Bps"),
        ],
    )


def build_incidents():
    return make_dashboard(
        "proxmox-incidents", "Proxmox Incidents & Recovery",
        [
            stat_panel("Locked Guests", "count(pve_lock_state == 1)", "locked", 0, 0, unit="none"),
            stat_panel("HA Managed", "count(pve_ha_state == 1)", "managed", 4, 0, unit="none"),
            stat_panel("HA Stopped", 'count(pve_ha_state{state="stopped"} == 1)', "stopped", 8, 0, unit="none"),
            stat_panel("Unknown Sub", 'count(pve_subscription_info{level="unknown"})', "unknown", 12, 0, unit="none"),
            table_panel("Guests with Locks", "pve_lock_state == 1", "{{id}} ({{state}})", 0, 1),
            table_panel("HA State Overview", "pve_ha_state == 1", "{{id}} ({{state}})", 0, 9),
        ],
    )


def build_node_detail():
    return make_dashboard(
        "proxmox-node-detail", "Proxmox Node Detail",
        [
            stat_panel("Guest VMs", 'count(pve_guest_info{type="qemu",exported_node=~"$node"})', "VMs", 0, 0, unit="none"),
            stat_panel("Guest CTs", 'count(pve_guest_info{type="lxc",exported_node=~"$node"})', "CTs", 4, 0, unit="none"),
            stat_panel("Running", 'count(pve_up{exported_node=~"$node"} == 1)', "running", 8, 0, unit="none"),
            stat_panel("Stopped", 'count(pve_up{exported_node=~"$node"} == 0)', "stopped", 12, 0, unit="none"),
            stat_panel("Uptime", 'avg(pve_uptime_seconds{type="node",node=~"$node"})', "seconds", 16, 0, unit="seconds"),
            stat_panel("Version", 'pve_version_info{node=~"$node"}', "{{release}}", 20, 0, unit="none"),
            timeseries_panel("CPU Usage", 'avg(pve_cpu_usage_ratio{exported_node=~"$node"}) * 100', "avg guest CPU", 0, 1, unit="percent"),
            timeseries_panel("Guest Memory", 'sum(pve_memory_usage_bytes{exported_node=~"$node"})', "used", 12, 1, unit="bytes"),
            timeseries_panel("Disk Read", 'sum(rate(pve_disk_read_bytes_total{exported_node=~"$node"}[5m]))', "total", 0, 9, unit="Bps"),
            timeseries_panel("Disk Write", 'sum(rate(pve_disk_written_bytes_total{exported_node=~"$node"}[5m]))', "total", 12, 9, unit="Bps"),
            table_panel("Guests", 'pve_guest_info{exported_node=~"$node"}', "{{name}} ({{type}}/{{id}})", 0, 17),
        ],
        templating=[
            {
                "name": "node",
                "type": "query",
                "datasource": {"type": "prometheus", "uid": DS_UID},
                "query": "label_values(pve_node_info, node)",
                "refresh": 1,
                "sort": 1,
                "includeAll": False,
                "multi": False,
            }
        ],
    )


def build_vm_ct_detail():
    return make_dashboard(
        "proxmox-vm-detail", "Proxmox VM/CT Detail",
        [
            stat_panel("Status", 'pve_up{name=~"$guest"}', "{{name}}", 0, 0, unit="none"),
            stat_panel("Type", 'pve_guest_info{name=~"$guest"}', "{{type}}", 4, 0, unit="none"),
            stat_panel("Node", 'pve_guest_info{name=~"$guest"}', "{{exported_node}}", 8, 0, unit="none"),
            stat_panel("vCPUs", 'pve_cpu_usage_limit{name=~"$guest"}', "vCPUs", 12, 0, unit="none"),
            stat_panel("Memory", 'pve_memory_size_bytes{name=~"$guest"}', "{{name}}", 16, 0, unit="bytes"),
            stat_panel("Uptime", 'pve_uptime_seconds{name=~"$guest"}', "seconds", 20, 0, unit="seconds"),
            timeseries_panel("CPU Usage", 'pve_cpu_usage_ratio{name=~"$guest"} * 100', "CPU %", 0, 1, unit="percent"),
            timeseries_panel("Memory Usage", 'pve_memory_usage_bytes{name=~"$guest"}', "used", 12, 1, unit="bytes"),
            timeseries_panel("Disk Read", 'rate(pve_disk_read_bytes_total{name=~"$guest"}[5m])', "read", 0, 9, unit="Bps"),
            timeseries_panel("Disk Write", 'rate(pve_disk_written_bytes_total{name=~"$guest"}[5m])', "write", 12, 9, unit="Bps"),
            timeseries_panel("Network RX", 'rate(pve_network_receive_bytes_total{name=~"$guest"}[5m])', "rx", 0, 17, unit="Bps"),
            timeseries_panel("Network TX", 'rate(pve_network_transmit_bytes_total{name=~"$guest"}[5m])', "tx", 12, 17, unit="Bps"),
        ],
        templating=[
            {
                "name": "guest",
                "type": "query",
                "datasource": {"type": "prometheus", "uid": DS_UID},
                "query": "label_values(pve_guest_info, name)",
                "refresh": 1,
                "sort": 1,
                "includeAll": True,
                "multi": False,
            }
        ],
    )


# ================================================================
# Deploy
# ================================================================


def deploy_via_ssh(dashboard_json, save_path=None):
    """Deploy a dashboard JSON to Grafana via provisioning file write."""
    # Extract just the inner dashboard object for file provisioning
    dashboard = dashboard_json.get("dashboard", dashboard_json)

    # Write to temp file locally
    with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as f:
        json.dump(dashboard, f, indent=2)
        local_path = f.name

    try:
        host_tmp = f"/tmp/pve-dash-{os.path.basename(local_path)}"
        ct_tmp = save_path  # Write directly to provisioning path

        # Copy to host
        subprocess.run(
            ["scp", "-o", "ConnectTimeout=10", "-o", "BatchMode=yes",
             local_path, f"root@{CT_HOST}:{host_tmp}"],
            capture_output=True, check=True, timeout=30,
        )

        # Push to container at the provisioning path directly
        subprocess.run(
            ["ssh", "-o", "ConnectTimeout=10", "-o", "BatchMode=yes",
             f"root@{CT_HOST}",
             f"pct push {CT_ID} {host_tmp} {ct_tmp} && "
             f"pct exec {CT_ID} -- chown grafana:grafana {ct_tmp}"],
            capture_output=True, check=True, timeout=30,
        )

        # Cleanup host temp
        subprocess.run(
            ["ssh", "-o", "ConnectTimeout=10", "-o", "BatchMode=yes",
             f"root@{CT_HOST}", f"rm -f {host_tmp}"],
            capture_output=True, timeout=10,
        )

        title = dashboard.get("title", "?")
        uid = dashboard.get("uid", "?")
        print(f"  ✅ {title} (uid={uid})")
        print(f"   💾 Escrito en {ct_tmp}")
        return True

    except subprocess.CalledProcessError as e:
        err = e.stderr.decode() if e.stderr else str(e)
        print(f"  ❌ Error copiando archivo: {err[:200]}")
        return False
    except Exception as e:
        print(f"  ❌ Error: {e}")
        return False
    finally:
        os.unlink(local_path)


def main():
    # All dashboards to deploy
    builders = [
        ("Proxmox Cluster Overview", build_cluster_overview, "proxmox-cluster-overview.json"),
        ("Proxmox Hardware", build_hardware, "proxmox-hardware.json"),
        ("Proxmox VMs", build_vms, "proxmox-vms.json"),
        ("Proxmox Containers", build_cts, "proxmox-cts.json"),
        ("Proxmox Backups", build_storage, "proxmox-backups.json"),
        ("Proxmox Networking", build_networking, "proxmox-networking.json"),
        ("Proxmox Incidents & Recovery", build_incidents, "proxmox-incidents.json"),
        ("Proxmox Node Detail", build_node_detail, "proxmox-node-detail.json"),
        ("Proxmox VM/CT Detail", build_vm_ct_detail, "proxmox-vm-detail.json"),
    ]

    print("=== Desplegando dashboards PVE en Grafana ===")
    print()

    success = 0
    failed = 0

    for name, builder, filename in builders:
        print(f"[→] {name}...")
        try:
            dashboard = builder()
            save_path = f"{DASHBOARDS_DIR}/{filename}"
            if deploy_via_ssh(dashboard, save_path):
                success += 1
            else:
                failed += 1
        except Exception as e:
            print(f"  ❌ Error generando dashboard: {e}")
            failed += 1
        print()

    print(f"=== Resultado: {success} OK, {failed} fallos ===")

    if success > 0:
        print()
        print("Recargando configuración de Grafana...")
        result = subprocess.run(
            [
                "ssh", "-o", "ConnectTimeout=10", "-o", "BatchMode=yes",
                f"root@{CT_HOST}",
                f"pct exec {CT_ID} -- systemctl reload grafana-server",
            ],
            capture_output=True, text=True, timeout=30,
        )
        if result.returncode == 0:
            print("✅ Grafana recargado — los dashboards deberían aparecer en segundos")
        else:
            # fallback: just restart
            print("⚠️  Reload falló, reiniciando Grafana...")
            subprocess.run(
                [
                    "ssh", "-o", "ConnectTimeout=10", "-o", "BatchMode=yes",
                    f"root@{CT_HOST}",
                    f"pct exec {CT_ID} -- systemctl restart grafana-server",
                ],
                capture_output=True, timeout=60,
            )
            print("✅ Grafana reiniciado")
        print(f"   Revisar: http://{CT_HOST}:{GRAFANA_PORT}")

    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
