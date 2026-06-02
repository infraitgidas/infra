#!/bin/bash
# ================================================================
# 00-env.sh — F3 Network Environment Configuration (Red VLAN)
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

# --- VLAN Configuration ---
VLAN_ID=10
VLAN_SUBNET="10.0.10.0/24"
VLAN_INTERFACE="vmbr0.${VLAN_ID}"

# VLAN 10 IPs per node (ring1_addr for Corosync)
declare -a VLAN_IPS=(
    "10.0.10.11/24"   # pve-desa01
    "10.0.10.12/24"   # pve-desa02
    "10.0.10.13/24"   # pve-desa03
    "10.0.10.14/24"   # pve-desa04
)

# --- Primary Network ---
# vmbr0 bridge ports per node (before bonding)
# eno1 for single-NIC nodes, eno1-4 for bonding node
declare -a BRIDGE_PORTS=(
    "eno1"        # pve-desa01
    "eno1"        # pve-desa02
    "eno1"        # pve-desa03
    "bond0"       # pve-desa04 (after bonding — Task 3.4)
)

# --- Bonding (pve-desa04 only) ---
BOND_NODE_IDX=3    # Index of pve-desa04 in NODES/NODE_NAMES arrays
BOND_NODE_IP="192.168.1.14/24"
BOND_GATEWAY="192.168.1.1"
declare -a BOND_SLAVES=(
    "eno1"
    "eno2"
    "eno3"
    "eno4"
)
BOND_MODE="802.3ad"     # LACP
BOND_MIIMON=100
BOND_LACP_RATE="fast"
BOND_XMIT_HASH="layer2+3"

# --- Corosync Configuration ---
# Current corosync.conf path (managed by pmxcfs, syncs cluster-wide)
COROSYNC_CONF="/etc/pve/corosync.conf"
# Bind addresses for Corosync links
LINK0_BIND="192.168.1.0"    # Data network
LINK1_BIND="10.0.10.0"      # Heartbeat VLAN

# --- Firewall ---
CLUSTER_FW="/etc/pve/firewall/cluster.fw"

# --- SSH Options ---
SSH_OPTS="-o ConnectTimeout=10 -o BatchMode=yes"

echo "[00-env] Loaded F3 network environment for ${#NODES[@]} cluster nodes"
echo "[00-env] VLAN ${VLAN_ID}: ${VLAN_SUBNET} — ${VLAN_INTERFACE}"
echo "[00-env] Corosync link1 bind: ${LINK1_BIND}"
echo "[00-env] Bond node: ${NODE_NAMES[$BOND_NODE_IDX]} (mode: ${BOND_MODE})"
