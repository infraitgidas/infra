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
VM_STORAGE="shared-gitlab"   # NFS shared storage (f3-shared-storage)
VM_STORAGE_LOCAL="local-zfs"  # Local storage for snippets/ISOs

# --- VM Resources ---
VM_CORES=4
VM_SOCKETS=1
VM_MEMORY=8192   # MB
VM_DISK_SIZE="80G"

# --- OS ---
VM_OSTYPE="l26"
VM_TEMPLATE="rocky-10-standard"  # cloud-init template name en pve-desa01
VM_TEMPLATE_ID=9000              # Template VM ID (verificar en PVE)
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

echo "[00-env] GitLab VM Environment loaded (Rocky Linux 10)"
echo "[00-env] VM ${VM_ID} — ${VM_NAME} — ${VM_IP}"
echo "[00-env] Template: ${VM_TEMPLATE} | Resources: ${VM_CORES}vCPU / ${VM_MEMORY}MB RAM / ${VM_DISK_SIZE} disk"
echo "[00-env] GitLab domain: ${GITLAB_DOMAIN} | SSH port: ${GITLAB_SSH_PORT}"
