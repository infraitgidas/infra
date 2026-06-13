#!/bin/bash
# ================================================================
# 00-env.sh — GitLab VM Environment Configuration
# ================================================================
# Source this file before running any other scripts:
#   source 00-env.sh
# ================================================================
set -euo pipefail

# --- Proxmox Node ---
PM_NODE="pve-desa04"
PM_IP="192.168.1.14"

# --- VM Specs ---
VM_ID=201
VM_IP="192.168.1.41/24"
VM_NETMASK="24"
VM_CORES=4
VM_MEMORY=8192          # MB
VM_DISK=80              # GB
VM_DISK_SIZE="80G"
VM_USER="infra"
VM_PASS="hlvs.2025"
VM_HOSTNAME="gitlab"
VM_DOMAIN="gidas.local"
VM_FQDN="${VM_HOSTNAME}.${VM_DOMAIN}"
VM_TEMPLATE="rocky-10-template"

# --- Network ---
VM_GATEWAY="192.168.1.1"
VM_BRIDGE="vmbr0"

# --- GitLab Configuration ---
GITLAB_DOMAIN="gitlab.gidas.local"
GITLAB_SSH_PORT=2222
GITLAB_LETSENCRYPT_EMAIL="admin@gidas.local"
GITLAB_ROOT_PASSWORD="$(openssl rand -base64 24 2>/dev/null || echo 'CHANGE_ME')"

# --- Port Mapping ---
HOST_SSH_PORT=2222
VM_GIT_SSH_PORT=22

# --- SSH Options ---
SSH_OPTS="-o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=accept-new"

# --- Backup ---
BACKUP_DIR="/var/opt/gitlab/backups"
BACKUP_RETENTION_DAYS=7
PVE_SNAPSHOT_NAME="gitlab-weekly"
SECRETS_FILE="/etc/gitlab/gitlab-secrets.json"

# --- AD LDAP (para scripts de sync) ---
AD_HOST="${AD_HOST:-192.168.1.117}"
AD_PORT="${AD_PORT:-389}"
AD_BIND_DN="${AD_BIND_DN:-CN=infrait,OU=ServiceAccounts,DC=GDC01,DC=local}"
AD_BIND_PASS="${AD_BIND_PASS:-Gidas2026!}"
AD_GROUPS_DN="${AD_GROUPS_DN:-OU=Groups,DC=GDC01,DC=local}"

# --- GitLab API (para scripts de sync) ---
GITLAB_API_URL="https://${GITLAB_DOMAIN}/api/v4"
GITLAB_API_TOKEN="${GITLAB_API_TOKEN:-2d35b533814b8da73a797901eb4d2480b33b0c36}"

echo "[00-env] GitLab VM Environment loaded (Rocky Linux 10)"
echo "[00-env] VM ${VM_ID} on ${PM_NODE} (${PM_IP}) — ${VM_FQDN} (${VM_IP})"
echo "[00-env] Template: ${VM_TEMPLATE} | Resources: ${VM_CORES}vCPU / ${VM_MEMORY}MB RAM / ${VM_DISK}G disk"
echo "[00-env] GitLab domain: ${GITLAB_DOMAIN} | SSH port: ${GITLAB_SSH_PORT}"
