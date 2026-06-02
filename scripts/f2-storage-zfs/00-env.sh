#!/bin/bash
# ================================================================
# 00-env.sh — F2 Environment Configuration (Storage ZFS)
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

# --- RAM per node (for ARC calculation) ---
# pve-desa01: 15 GB → 50% = 7.5 GB = 8053063680
# pve-desa02: 10 GB → 50% = 5 GB = 5368709120
# pve-desa03: 15 GB → 50% = 7.5 GB = 8053063680
# pve-desa04: 15 GB → 50% = 7.5 GB = 8053063680
declare -a NODE_RAM_GB=(
    15
    10
    15
    15
)
ARC_PERCENT=50  # 50% of total RAM

# --- ZFS Pool Configuration ---
# Which disk/device to use for the ZFS pool on each node
declare -a ZFS_DEVICES=(
    "/dev/pve/zfs-pool"   # pve-desa01: LVM-backed (single disk node)
    "/dev/sdc"            # pve-desa02: free 932G HDD
    "/dev/sdc"            # pve-desa03: after removing vm-storage VG
    "/dev/sdb"            # pve-desa04: after labelclear old ZFS on sdb3
)

ZFS_POOL_NAME="local-zfs"

# --- Replication Pairs ---
# Format: SOURCE_IDX:TARGET_IDX (index in NODES/NODE_NAMES arrays)
declare -a REPLICATION_PAIRS=(
    "0:1"   # pve-desa01 → pve-desa02
    "1:0"   # pve-desa02 → pve-desa01
    "2:3"   # pve-desa03 → pve-desa04
    "3:2"   # pve-desa04 → pve-desa03
)

# --- VM/CT Inventory ---
# VMs/CTs on each node that need migration during ZFS conversion
# Format for migration targets: SOURCE_NODE_IDX:TARGET_NODE_IDX
declare -a MIGRATION_PAIRS=(
    "0:1"   # pve-desa01 VMs → pve-desa02
    "3:2"   # pve-desa04 VMs → pve-desa03
)

# VM IDs per source node
# pve-desa01: CT 105 (connector-twingate, running), VM 100 (BASE-Windows2k22, stopped)
# pve-desa04: VM 109 (gidas-site-desa, running)
declare -A NODE_VMS
NODE_VMS[0]="105,100"   # pve-desa01: CT 105 + VM 100
NODE_VMS[3]="109"       # pve-desa04: VM 109

# Which VMs are containers vs. VMs (CT migration uses pct, VM uses qm)
declare -A CT_VMS
CT_VMS[105]="1"  # CT 105 is a container

# --- Replication Schedules ---
# Critical VMs: RPO 15 min
# Non-critical VMs: RPO 1h
# Format: VMID|critical|1h
declare -a VM_REPLICATION_SCHEDULES=(
    "105|critical|*/15 * * * *"   # connector-twingate — every 15 min
    "109|critical|*/15 * * * *"   # gidas-site-desa — every 15 min
    "100|1h|0 * * * *"            # BASE-Windows2k22 — every hour
)
BWLIMIT=524288000  # 500 MiB/s in bytes/sec (500 * 1024 * 1024 ≈ 4 Gbps — design decision)

# --- SSH Options ---
SSH_OPTS="-o ConnectTimeout=10 -o BatchMode=yes"

echo "[00-env] Loaded F2 environment for ${#NODES[@]} cluster nodes"
echo "[00-env] ZFS pool: ${ZFS_POOL_NAME}"
echo "[00-env] ARC: ${ARC_PERCENT}% of RAM"
echo "[00-env] Replication pairs: ${REPLICATION_PAIRS[*]}"
echo "[00-env] Migration pairs: ${MIGRATION_PAIRS[*]}"
