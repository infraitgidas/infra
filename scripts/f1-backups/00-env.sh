#!/bin/bash
# ================================================================
# 00-env.sh — Environment Configuration
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

# --- PBS Node (standalone, outside cluster) ---
PBS_HOST="192.168.1.31"
PBS_HOSTNAME="pve-ad"
PBS_PORT="8007"
PBS_STORAGE_ID="pbs"
PBS_DATASTORE="gidas-backups"

# --- SSH Options ---
SSH_OPTS="-o ConnectTimeout=5 -o BatchMode=yes"

# --- Encryption Key ---
ENCRYPTION_KEY_PATH="/root/.pve-encryption-key"

# --- Retention Settings ---
RETENTION_DAILY=7
RETENTION_WEEKLY=4
RETENTION_MONTHLY=3

# --- Backup Schedule ---
BACKUP_SCHEDULE="0 22 * * *"      # Daily at 22:00
PRUNE_SCHEDULE="sun 23:00"         # Weekly prune + GC on Sunday 23:00
GC_SCHEDULE="sun 23:30"            # GC 30 min after prune

# --- VM IDs that need backing up ---
# Running VMs: 105 (connector-twingate), 109 (gidas-site-desa)
# Stopped VMs: 100 (BASE-Windows2k22), 101 (VM-DC1), 102 (DC2), 108 (rocky-10-template)
# NOTE: VMs 100, 101, 102 are pending decision (task 1.1) — include them for now
declare -a VM_IDS=(
    "100"   # BASE-Windows2k22  (stopped — pending decision)
    "101"   # VM-DC1            (stopped — pending decision)
    "102"   # DC2               (stopped — pending decision, currently cache=writeback)
    "105"   # connector-twingate (running)
    "108"   # rocky-10-template (stopped)
    "109"   # gidas-site-desa   (running)
)

echo "[00-env] Loaded environment for ${#NODES[@]} cluster nodes + PBS at ${PBS_HOSTNAME}"
echo "[00-env] PBS datastore: ${PBS_DATASTORE} | Port: ${PBS_PORT}"
echo "[00-env] ${#VM_IDS[@]} VMs configured for backup"
echo "[00-env] Retention: ${RETENTION_DAILY}d ${RETENTION_WEEKLY}w ${RETENTION_MONTHLY}m"
echo "[00-env] Schedule: ${BACKUP_SCHEDULE} | Prune: ${PRUNE_SCHEDULE} | GC: ${GC_SCHEDULE}"
