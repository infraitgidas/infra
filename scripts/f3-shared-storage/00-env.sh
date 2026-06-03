#!/bin/bash
# ================================================================
# 00-env.sh — F3 Shared Storage Environment Configuration
# ================================================================
# Source this file before running any other scripts:
#   source 00-env.sh
#
# This file is sourced by all F3 scripts. Edit once to change
# cluster-wide settings.
# ================================================================

# --- Shared Storage Node ---
SHARED_NODE_IP="192.168.1.13"
SHARED_NODE_NAME="pve-desa03"

# --- Local ZFS Pool (pve-desa02) ---
LOCAL_POOL="local-zfs"
DR_PREFIX="${LOCAL_POOL}/backup-dr"

# --- Cluster Nodes (consumers of NFS) ---
declare -a CLUSTER_NODES=(
    "192.168.1.11"  # pve-desa01
    "192.168.1.12"  # pve-desa02
    "192.168.1.13"  # pve-desa03
    "192.168.1.14"  # pve-desa04
)

declare -a CLUSTER_NODE_NAMES=(
    "pve-desa01"
    "pve-desa02"
    "pve-desa03"
    "pve-desa04"
)

# --- DR Node (pve-desa02) ---
DR_NODE_IP="192.168.1.12"
DR_NODE_NAME="pve-desa02"

# --- ZFS Pool Configuration ---
SHARED_POOL="shared-zfs"
# Mirror disks for shared-zfs (sda + sdc on pve-desa03)
SHARED_POOL_DISKS=(
    "/dev/sda"
    "/dev/sdc"
)

# --- Dataset Definitions ---
# Format: NAME:MOUNTPOINT:RECORDSIZE:QUOTA
# recordsize default (128K) if omitted; quota 0 = no quota
declare -a DATASETS=(
    "vms:/${SHARED_POOL}/vms:128K:600G"
    "kubernetes:/${SHARED_POOL}/kubernetes::100G"
    "gitlab:/${SHARED_POOL}/gitlab::100G"
    "registry:/${SHARED_POOL}/registry::50G"
    "backups:/${SHARED_POOL}/backups:1M:50G"
    "samba:/${SHARED_POOL}/samba::32G"
)

# --- NFS Export Subnets ---
NFS_SUBNET="192.168.1.0/24"
NFS_OPTIONS="rw,async,no_subtree_check,no_wdelay,crossmnt"

# Only shared-zfs/samba is NOT exported via NFS (served via Samba)
declare -a NFS_DATASETS=(
    "vms"
    "kubernetes"
    "gitlab"
    "registry"
    "backups"
)

# --- Proxmox NFS Storage IDs ---
# These match the dataset names with a "shared-" prefix
declare -A NFS_STORAGE_IDS
NFS_STORAGE_IDS[vms]="shared-vms"
NFS_STORAGE_IDS[kubernetes]="shared-k8s"
NFS_STORAGE_IDS[gitlab]="shared-gitlab"
NFS_STORAGE_IDS[registry]="shared-registry"
NFS_STORAGE_IDS[backups]="shared-backups"

# --- NFS Content Types per storage ---
declare -A NFS_CONTENT
NFS_CONTENT[vms]="images,rootdir"
NFS_CONTENT[kubernetes]="images,rootdir"
NFS_CONTENT[gitlab]="images,rootdir"
NFS_CONTENT[registry]="images,rootdir"
NFS_CONTENT[backups]="backup"

# --- ARC Configuration ---
# pve-desa03: 15 GB RAM → 50% = 7.5 GB = 8053063680
ARC_PERCENT=50
NODE_RAM_GB=15
ARC_MAX_BYTES=$((NODE_RAM_GB * 1024 * 1024 * 1024 * ARC_PERCENT / 100))
# Pre-calculated: 8053063680

# pve-desa02 (DR node): 10 GB RAM → 50% = 5 GB = 5368709120
DR_NODE_RAM_GB=10
DR_ARC_MAX_BYTES=$((DR_NODE_RAM_GB * 1024 * 1024 * 1024 * ARC_PERCENT / 100))
# Pre-calculated: 5368709120

# --- Samba Configuration ---
SAMBA_WORKGROUP="WORKGROUP"
SAMBA_SERVER_STRING="pve-desa03 Samba"
SAMBA_SHARE_NAME="shared"
SAMBA_SHARE_PATH="/${SHARED_POOL}/samba"
SAMBA_GROUP="samba-users"
SAMBA_USER="samba-shared"

# --- NFS Kernel Tuning ---
NFS_SYSCTL_CONF="/etc/sysctl.d/90-nfs.conf"

# --- SSH Options ---
SSH_OPTS="-o ConnectTimeout=10 -o BatchMode=yes"

# --- Paths ---
EXPORTS_FILE="/etc/exports"
SMB_CONF="/etc/samba/smb.conf"

echo "[00-env] Loaded F3 shared storage environment"
echo "[00-env] Shared pool: ${SHARED_POOL} on ${SHARED_NODE_NAME} (${SHARED_NODE_IP})"
echo "[00-env] Datasets: ${#DATASETS[@]} (${DATASETS[*]})"
echo "[00-env] NFS exports: ${NFS_DATASETS[*]}"
echo "[00-env] ARC ${SHARED_NODE_NAME}: ${ARC_PERCENT}% RAM (${ARC_MAX_BYTES} bytes = $((ARC_MAX_BYTES / 1024 / 1024 / 1024)) GB)"
echo "[00-env] ARC ${DR_NODE_NAME}: ${ARC_PERCENT}% RAM (${DR_ARC_MAX_BYTES} bytes = $((DR_ARC_MAX_BYTES / 1024 / 1024 / 1024)) GB)"
