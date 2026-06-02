#!/bin/bash
# ================================================================
# 02-corosync-link1.sh — Task 3.2: Configure corosync link1
# ================================================================
# Adds a redundant link (link1) to corosync.conf pointing to VLAN 10.
# link0: vmbr0 (192.168.1.0/24) — data traffic
# link1: vmbr0.10 (10.0.10.0/24) — heartbeat redundancy
#
# PREREQUISITE: Task 3.1 — VLAN 10 configured and active on all nodes
# ================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-env.sh"

echo "=== Task 3.2: Agregar link1 redundante a corosync.conf ==="
echo ""

# We'll use the first node as the one we edit (corosync.conf syncs via pmxcfs)
MASTER_NODE="${NODES[0]}"
MASTER_NAME="${NODE_NAMES[0]}"

# ---------------------------------------------------------------
# Step 1: Verify current corosync.conf
# ---------------------------------------------------------------
echo "[1/4] Verificando corosync.conf en ${MASTER_NAME}..."

# Check corosync.conf exists
COROSYNC_EXISTS=$(ssh ${SSH_OPTS} root@${MASTER_NODE} "test -f ${COROSYNC_CONF} && echo OK || echo NO" 2>/dev/null || echo "NO")
if [ "${COROSYNC_EXISTS}" != "OK" ]; then
    echo "❌ ${COROSYNC_CONF} no encontrado en ${MASTER_NAME}"
    echo "   ¿Es este nodo parte de un cluster Proxmox?"
    exit 1
fi
echo "[1/4] ✅ corosync.conf encontrado"

# Check current links configured
CURRENT_LINKS=$(ssh ${SSH_OPTS} root@${MASTER_NODE} "grep -c 'linknumber' ${COROSYNC_CONF} 2>/dev/null || echo 0")
echo "[1/4] Linknumbers actuales: ${CURRENT_LINKS}"

if [ "${CURRENT_LINKS}" -ge 2 ]; then
    echo "[1/4] ⚠️  Ya hay 2 links configurados — verificando link1..."
    LINK1_BIND=$(ssh ${SSH_OPTS} root@${MASTER_NODE} "grep -A2 'linknumber: 1' ${COROSYNC_CONF} | grep bindnetaddr | awk '{print \$2}'" 2>/dev/null || echo "")
    if [ -n "${LINK1_BIND}" ]; then
        echo "[1/4] ⚠️  link1 ya configurado con bindnetaddr=${LINK1_BIND}"
        echo "   Saltando configuración — usar 03-restart-corosync.sh si necesita reinicio"
        exit 0
    fi
fi

# ---------------------------------------------------------------
# Step 2: Backup corosync.conf
# ---------------------------------------------------------------
echo ""
echo "[2/4] Respaldando corosync.conf..."

BACKUP="${COROSYNC_CONF}.backup.$(date +%Y%m%d_%H%M%S)"
ssh ${SSH_OPTS} root@${MASTER_NODE} "cp ${COROSYNC_CONF} ${BACKUP}"
echo "[2/4] ✅ Respaldo: ${BACKUP}"

# ---------------------------------------------------------------
# Step 3: Add link1 to corosync.conf
# ---------------------------------------------------------------
echo ""
echo "[3/4] Agregando link1 a corosync.conf..."

# Build a sed script to add the second interface section and ring1_addr entries.
# The corosync.conf format is YAML-like. We need to:
#   1. Add a second `interface` block under `totem` with linknumber: 1
#   2. Add `ring1_addr` to each `node` entry under `nodelist`
#
# Strategy: Use a heredoc-based replacement via a Python script on the remote node
# for reliable YAML-like manipulation.

ssh ${SSH_OPTS} root@${MASTER_NODE} bash -s -- "${VLAN_SUBNET}" "${VLAN_ID}" << 'REMOTE'
    set -euo pipefail
    VLAN_SUBNET="$1"
    VLAN_ID="$2"
    CONF="${COROSYNC_CONF}"

    # Use python3 to parse and modify corosync.conf (PVE uses YAML-like syntax)
    python3 << 'PYEOF'
import re, socket, struct

def netmask_from_cidr(cidr):
    """Convert CIDR prefix to netmask (e.g. 24 -> 255.255.255.0)"""
    prefix = int(cidr.split('/')[1]) if '/' in cidr else 24
    mask = (0xffffffff << (32 - prefix)) & 0xffffffff
    return socket.inet_ntoa(struct.pack('!I', mask))

with open('/etc/pve/corosync.conf', 'r') as f:
    content = f.read()

lines = content.split('\n')

# --- Step 1: Find the totem section and add a second interface block ---
totem_start = None
totem_end = None
interface_count = 0
nodelist_start = None
nodelist_end = None

for i, line in enumerate(lines):
    stripped = line.strip()
    if stripped == 'totem:' and totem_start is None:
        totem_start = i
    elif totem_start is not None and totem_end is None:
        # Count interface blocks inside totem
        if stripped.startswith('interface:'):
            interface_count += 1
    elif stripped == 'nodelist:' and nodelist_start is None:
        totem_end = i - 1 if totem_end is None else totem_end
        nodelist_start = i
    elif nodelist_start is not None and nodelist_end is None:
        # nodelist ends at next top-level key or EOF
        if stripped and not stripped.startswith(' ') and not stripped.startswith('\t') and i > nodelist_start:
            nodelist_end = i - 1
            break

if totem_end is None:
    totem_end = nodelist_start - 1 if nodelist_start else len(lines) - 1
if nodelist_end is None:
    nodelist_end = len(lines) - 1

# --- Add second interface block if needed ---
if interface_count < 2:
    # Find the indentation of the existing interface block
    iface_indent = None
    for i in range(totem_start, totem_end + 1):
        if lines[i].strip().startswith('interface:'):
            iface_indent = len(lines[i]) - len(lines[i].lstrip())
            break

    if iface_indent is None:
        iface_indent = 4  # default

    # Find where to insert — after the last interface block
    insert_after = totem_start
    for i in range(totem_start, totem_end + 1):
        stripped_line = lines[i].strip()
        if stripped_line.startswith('interface:') or stripped_line.startswith('linknumber:') or \
           stripped_line.startswith('bindnetaddr:') or stripped_line.startswith('ip_version:') or \
           stripped_line.startswith('hwmcast:') or stripped_line.startswith('mcastport:'):
            insert_after = i

    new_interface = [
        '',
        ' ' * iface_indent + 'interface:',
        ' ' * (iface_indent + 4) + 'linknumber: 1',
        ' ' * (iface_indent + 4) + 'bindnetaddr: 10.0.10.0',
        ' ' * (iface_indent + 4) + 'ip_version: ipv4',
    ]
    for j, nl in enumerate(new_interface):
        lines.insert(insert_after + 1 + j, nl)

    with open('/etc/pve/corosync.conf', 'w') as f:
        f.write('\n'.join(lines))

    print('✅ Segundo interface (linknumber: 1) agregado a totem')
else:
    print('⚠️  Segundo interface ya existe — omitiendo')

# --- Step 2: Add ring1_addr to each node in nodelist ---
re_read = re.sub('\n'.join(lines[:nodelist_start]), '', '\n'.join(lines[nodelist_start:]))
# Let's re-read the file since it may have changed
with open('/etc/pve/corosync.conf', 'r') as f:
    content = f.read()

lines = content.split('\n')

# Find nodelist section again
nodelist_start = None
nodelist_end = None
for i, line in enumerate(lines):
    stripped = line.strip()
    if stripped == 'nodelist:':
        nodelist_start = i
    elif nodelist_start is not None and nodelist_end is None:
        if stripped and not stripped.startswith(' ') and not stripped.startswith('\t') and i > nodelist_start:
            nodelist_end = i - 1
            break
if nodelist_end is None:
    nodelist_end = len(lines) - 1

# Node IP mapping for ring1_addr
# Map node names to VLAN 10 IPs
from collections import OrderedDict
NODE_IPS = OrderedDict([
    ('pve-desa01', '10.0.10.11'),
    ('pve-desa02', '10.0.10.12'),
    ('pve-desa03', '10.0.10.13'),
    ('pve-desa04', '10.0.10.14'),
])

# For each node section (starting with "node {"), check if ring1_addr exists
# If not, add it after ring0_addr
node_depth = 0
in_node = False
node_start = None
has_ring1 = False
add_after_line = None

for i in range(nodelist_start, nodelist_end + 1):
    stripped = lines[i].strip()
    indent = len(lines[i]) - len(lines[i].lstrip()) if lines[i].strip() else 0

    if stripped == 'node {':
        in_node = True
        node_start = i
        has_ring1 = False
        add_after_line = None
    elif in_node and stripped.startswith('name:'):
        # Extract name
        node_name = stripped.split(':', 1)[1].strip()
        if node_name in NODE_IPS:
            add_after_line = i  # will add after ring0_addr, but track name for later
    elif in_node and stripped.startswith('ring0_addr:'):
        add_after_line = i  # track where ring0_addr is to add ring1 after it
    elif in_node and stripped.startswith('ring1_addr:'):
        has_ring1 = True
    elif in_node and stripped == '}':
        if not has_ring1 and add_after_line is not None:
            # Find the node name from the node section
            node_name = None
            for j in range(node_start, i):
                s = lines[j].strip()
                if s.startswith('name:'):
                    node_name = s.split(':', 1)[1].strip()
                    break
            if node_name and node_name in NODE_IPS:
                ring1_ip = NODE_IPS[node_name]
                indent = len(lines[add_after_line]) - len(lines[add_after_line].lstrip())
                # Clamp indent to at least 8
                if indent < 8:
                    indent = 8
                lines.insert(add_after_line + 1, ' ' * indent + 'ring1_addr: ' + ring1_ip)
                # Adjust indices since we inserted
                nodelist_end += 1
                print(f'✅ ring1_addr {ring1_ip} agregado a {node_name}')
        in_node = False

with open('/etc/pve/corosync.conf', 'w') as f:
    f.write('\n'.join(lines))

print('✅ Configuración de corosync.conf completada')
PYEOF
REMOTE

echo "[3/4] ✅ Link1 agregado a corosync.conf"
echo "[3/4]    bindnetaddr: ${LINK1_BIND}"
echo "[3/4]    ring1_addr: VLAN 10 IPs por nodo"

# ---------------------------------------------------------------
# Step 4: Verify configuration
# ---------------------------------------------------------------
echo ""
echo "[4/4] Verificando corosync.conf..."
ssh ${SSH_OPTS} root@${MASTER_NODE} "cat ${COROSYNC_CONF}" | head -80
echo ""
echo "[4/4] Verificación:"
# Check linknumber count
LINK_COUNT=$(ssh ${SSH_OPTS} root@${MASTER_NODE} "grep -c 'linknumber' ${COROSYNC_CONF} 2>/dev/null || echo 0")
RING1_COUNT=$(ssh ${SSH_OPTS} root@${MASTER_NODE} "grep -c 'ring1_addr' ${COROSYNC_CONF} 2>/dev/null || echo 0")

if [ "${LINK_COUNT}" -ge 2 ] && [ "${RING1_COUNT}" -ge 2 ]; then
    echo "[4/4] ✅ ${LINK_COUNT} links configurados, ${RING1_COUNT} ring1_addr definidos"
else
    echo "[4/4] ❌ Configuración incompleta: ${LINK_COUNT} links, ${RING1_COUNT} ring1_addr"
    echo "   Revise ${COROSYNC_CONF} manualmente"
fi

echo ""
echo "=== Task 3.2 completada ==="
echo "  corosync.conf actualizado con link1 redundante"
echo "  link0: vmbr0 (192.168.1.0/24) — datos"
echo "  link1: ${VLAN_INTERFACE} (${LINK1_BIND}) — heartbeat"
echo ""
echo "⚠️  EJECUTAR AHORA: 03-restart-corosync.sh para aplicar los cambios"
echo "   (reinicio nodo por nodo requerido)"
