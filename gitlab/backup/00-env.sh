#!/bin/bash
# ================================================================
# 00-env.sh — GitLab Backup Environment Configuration
# ================================================================
# Source this file before running backup scripts:
#   source 00-env.sh
# ================================================================

# --- VM Configuration ---
VM_ID="201"
VM_IP="192.168.1.41"
PVE_HOST_IP="192.168.1.11"

# --- SSH ---
SSH_OPTS="-o ConnectTimeout=10 -o BatchMode=yes"
VM_SSH="ssh ${SSH_OPTS} root@${VM_IP}"

# --- Backup Paths ---
GITLAB_BACKUP_DIR="/var/opt/gitlab/backups"
SECRETS_FILE="/etc/gitlab/gitlab-secrets.json"
LOCAL_BACKUP_DIR="/root/gitlab-backups"
BACKUP_RETENTION_DAYS=7

# --- PVE Snapshot ---
PVE_SNAPSHOT_PREFIX="gitlab-weekly"
PVE_SNAPSHOT_RETENTION=4  # keep last 4 weekly snapshots

# --- GitLab Config ---
GITLAB_DOMAIN="gitlab.gidas.local"
GITLAB_SSH_PORT=2222

echo "[00-env] GitLab Backup Environment loaded"
echo "[00-env] VM ${VM_ID} at ${VM_IP} | Backups: ${GITLAB_BACKUP_DIR}"
echo "[00-env] Retention: ${BACKUP_RETENTION_DAYS}d | Snapshots: ${PVE_SNAPSHOT_RETENTION} weeks"
