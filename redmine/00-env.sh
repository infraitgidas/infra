#!/bin/bash
# ================================================================
# 00-env.sh — Redmine Environment Configuration
# ================================================================
# Source this file before running any other scripts:
#   . 00-env.sh   (or source 00-env.sh)
# ================================================================
set -euo pipefail

# --- Proxmox Node ---
PM_NODE="pve-desa04"
PM_IP="192.168.1.14"

# --- VM Specs ---
VM_ID=206
VM_IP="192.168.1.20"
VM_CORES=2
VM_MEMORY=4096          # MB
VM_DISK=20              # GB
VM_USER="infra"
VM_PASS="hlsv.2025"
VM_HOSTNAME="redmine"
VM_DOMAIN="gidas.local"
VM_FQDN="${VM_HOSTNAME}.${VM_DOMAIN}"
VM_TEMPLATE="rocky-10-standard"

# --- Network ---
VM_GATEWAY="192.168.1.1"
VM_NETMASK="24"
VM_BRIDGE="vmbr0"

# --- Versions ---
REDMINE_VERSION="6.1"
POSTGRES_VERSION="16"
NGINX_VERSION="1.27-alpine"

# --- Paths ---
REDMINE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="/var/backups/redmine"
SSL_DIR="${REDMINE_DIR}/nginx/ssl"

# --- SSH Options ---
SSH_OPTS="-o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=accept-new"

# --- Secrets ---
# Priority: 1) sops-decrypted secrets/redmine.yaml, 2) .env file, 3) default/auto-generated
POSTGRES_DB="${POSTGRES_DB:-redmine}"
POSTGRES_USER="${POSTGRES_USER:-redmine}"

if command -v sops &>/dev/null && [ -f "${REDMINE_DIR}/../secrets/redmine.yaml" ]; then
    eval "$(sops -d "${REDMINE_DIR}/../secrets/redmine.yaml" 2>/dev/null | yq eval '.redmine | to_entries | .[] | .key + "=" + .value' - 2>/dev/null || true)"
elif [ -f "${REDMINE_DIR}/.env" ]; then
    set -a; source "${REDMINE_DIR}/.env"; set +a
fi

# Re-map SOPS keys to canonical variable names (yq produces lowercase_keys from yaml)
VM_PASS="${vm_pass:-${VM_PASS:-hlsv.2025}}"
# Auto-generate if still empty
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-${postgres_password:-$(openssl rand -base64 24 2>/dev/null || echo 'changeme')}}"
REDMINE_SECRET_KEY="${REDMINE_SECRET_KEY:-${redmine_secret_key:-$(openssl rand -hex 32 2>/dev/null || echo 'changeme')}}"

# --- Export for child scripts ---
export PM_NODE PM_IP VM_ID VM_IP VM_CORES VM_MEMORY VM_DISK
export VM_USER VM_PASS VM_HOSTNAME VM_DOMAIN VM_FQDN
export VM_GATEWAY VM_NETMASK VM_BRIDGE VM_TEMPLATE
export REDMINE_VERSION POSTGRES_VERSION NGINX_VERSION
export REDMINE_DIR BACKUP_DIR SSL_DIR SSH_OPTS
export POSTGRES_DB POSTGRES_USER POSTGRES_PASSWORD REDMINE_SECRET_KEY

echo "[00-env] Loaded Redmine environment"
echo "[00-env] VM: ${VM_ID} @ ${PM_NODE} (${PM_IP}) → ${VM_FQDN} (${VM_IP})"
echo "[00-env] Storage: shared-vms"
echo "[00-env] Stack: redmine:${REDMINE_VERSION} + postgres:${POSTGRES_VERSION} + nginx:${NGINX_VERSION}"
