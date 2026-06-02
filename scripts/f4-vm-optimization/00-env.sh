#!/bin/bash
# ================================================================
# 00-env.sh — F4 Environment Configuration (Optimización VMs)
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

# --- VM Inventory ---
# Format: "VMID|NAME|OS_TYPE|NODE_IDX|RUNNING"
# OS_TYPE: linux|windows|unknown
# RUNNING: 1=running, 0=stopped
# NOTE: VM 102 (DC2) fue destruida en F1
declare -a VMS=(
    "100|BASE-Windows2k22|windows|0|0"
    "101|VM-DC1|windows|1|0"
    "105|connector-twingate|linux|0|1"
    "108|rocky-10-template|linux|0|0"
    "109|gidas-site-desa|linux|3|1"
)

# --- Thresholds ---
# VMs with more than this many vCPUs should have NUMA enabled
NUMA_VCPU_THRESHOLD=4

# Minimum balloon memory in MB (1 GB = 1024 MB)
BALLOON_MIN_MB=1024

# Disk cache mode for integrity (none > writethrough > writeback)
DISK_CACHE_MODE="none"

# --- SSH Options ---
SSH_OPTS="-o ConnectTimeout=10 -o BatchMode=yes"

# --- Default node (where to run qm commands) ---
# Any node can be used since VM configs sync via pmxcfs
DEFAULT_NODE="${NODES[0]}"

echo "[00-env] Loaded F4 environment for ${#NODES[@]} cluster nodes"
echo "[00-env] ${#VMS[@]} VMs registered for optimization"
echo "[00-env] NUMA threshold: >${NUMA_VCPU_THRESHOLD} vCPUs"
echo "[00-env] Balloon minimum: ${BALLOON_MIN_MB} MB"
echo "[00-env] Disk cache mode: ${DISK_CACHE_MODE}"
