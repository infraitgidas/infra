#!/bin/bash
# ================================================================
# 00-env.sh — GitLab VM Environment Configuration
# ================================================================
# Source this file before running any other scripts:
#   source 00-env.sh
# ================================================================

# --- VM Configuration ---
VM_ID="201"
VM_NAME="gitlab"
VM_IP="192.168.1.41/24"
VM_GATEWAY="192.168.1.1"
VM_BRIDGE="vmbr0"
VM_STORAGE="local-zfs"

# --- VM Resources ---
VM_CORES=4
VM_SOCKETS=1
VM_MEMORY=8192   # MB
VM_DISK_SIZE="80G"

# --- OS ---
VM_OSTYPE="l26"
VM_TEMPLATE="ubuntu-22.04-standard"  # cloud-init template
VM_CIUSER="root"

# --- GitLab Configuration ---
GITLAB_DOMAIN="gitlab.gidas.local"
GITLAB_HOSTNAME="gitlab"
GITLAB_SSH_PORT=2222
GITLAB_LETSENCRYPT_EMAIL="admin@gidas.local"
GITLAB_ROOT_PASSWORD="$(openssl rand -base64 24 2>/dev/null || echo 'CHANGE_ME')"

# --- Port Mapping ---
HOST_SSH_PORT=2222
VM_GIT_SSH_PORT=22

# --- PVE Host ---
PVE_HOST="pve-desa01"
PVE_HOST_IP="192.168.1.11"

# --- SSH Options ---
SSH_OPTS="-o ConnectTimeout=10 -o BatchMode=yes"

# --- Backup ---
BACKUP_DIR="/var/opt/gitlab/backups"
BACKUP_RETENTION_DAYS=7
PVE_SNAPSHOT_NAME="gitlab-weekly"
SECRETS_FILE="/etc/gitlab/gitlab-secrets.json"

echo "[00-env] GitLab VM Environment loaded"
echo "[00-env] VM ${VM_ID} — ${VM_NAME} — ${VM_IP}"
echo "[00-env] Resources: ${VM_CORES}vCPU / ${VM_MEMORY}MB RAM / ${VM_DISK_SIZE} disk"
echo "[00-env] GitLab domain: ${GITLAB_DOMAIN} | SSH port: ${GITLAB_SSH_PORT}"
