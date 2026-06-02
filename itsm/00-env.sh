#!/bin/bash
# ================================================================
# 00-env.sh — Environment Configuration for GLPI ITSM
# ================================================================
# Source this file before running any other scripts:
#   source 00-env.sh
# ================================================================
# shellcheck disable=SC2034

# --- Project Paths ---
ITSM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${ITSM_DIR}/scripts"
CONFIG_DIR="${ITSM_DIR}/config"
BACKUP_DIR="/var/backups/glpi"

# --- Docker Compose ---
COMPOSE_FILE="${ITSM_DIR}/docker-compose.yml"
COMPOSE_PROJECT_NAME="glpi"

# --- MariaDB ---
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-glpi_root_secret}"
MYSQL_DATABASE="${MYSQL_DATABASE:-glpi}"
MYSQL_USER="${MYSQL_USER:-glpi}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:-glpi_password}"
MYSQL_HOST="${MYSQL_HOST:-mariadb}"
MYSQL_PORT="${MYSQL_PORT:-3306}"

# --- GLPI ---
GLPI_VERSION="${GLPI_VERSION:-10.0.x}"
GLPI_HOSTNAME="${GLPI_HOSTNAME:-glpi.gidas.local}"
GLPI_TIMEZONE="${GLPI_TIMEZONE:-America/Argentina/Buenos_Aires}"
GLPI_ADMIN_EMAIL="${GLPI_ADMIN_EMAIL:-admin@gidas.local}"
GLPI_ADMIN_USER="${GLPI_ADMIN_USER:-glpi}"
GLPI_ADMIN_PASSWORD="${GLPI_ADMIN_PASSWORD:-}"
GLPI_APP_TOKEN="${GLPI_APP_TOKEN:-}"

# --- LDAP ---
LDAP_HOST="${LDAP_HOST:-ipa.gidas.local}"
LDAP_PORT="${LDAP_PORT:-636}"
LDAP_BIND_DN="${LDAP_BIND_DN:-cn=glpi-svc,cn=sysaccounts,cn=etc,dc=gidas,dc=local}"
LDAP_BIND_PASS="${LDAP_BIND_PASS:-}"
LDAP_BASE_DN="${LDAP_BASE_DN:-cn=users,cn=accounts,dc=gidas,dc=local}"
LDAP_USER_FILTER="${LDAP_USER_FILTER:-(&(objectClass=person)(memberOf=cn=glpi-users,cn=groups,cn=accounts,dc=gidas,dc=local))}"
LDAP_TLS="${LDAP_TLS:-true}"

# --- Integrations ---
REDMINE_URL="${REDMINE_URL:-https://redmine.gidas.local}"
REDMINE_API_KEY="${REDMINE_API_KEY:-}"
GITLAB_URL="${GITLAB_URL:-https://gitlab.gidas.local}"
GITLAB_TOKEN="${GITLAB_TOKEN:-}"

# --- Backup ---
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
BACKUP_SCHEDULE="${BACKUP_SCHEDULE:-0 3 * * 0}"  # Weekly Sunday 03:00

# --- Docker Volume Names ---
VOLUME_MARIADB="glpi_mariadb_data"
VOLUME_GLPI_CONFIG="glpi_config"
VOLUME_GLPI_PLUGINS="glpi_plugins"
VOLUME_GLPI_DOCUMENTS="glpi_documents"

# --- Container Names ---
CONTAINER_MARIADB="${COMPOSE_PROJECT_NAME}-mariadb-1"
CONTAINER_GLPI="${COMPOSE_PROJECT_NAME}-glpi-1"
CONTAINER_NGINX="${COMPOSE_PROJECT_NAME}-nginx-1"

# --- Docker ---
DOCKER_NETWORK="${COMPOSE_PROJECT_NAME}_default"

echo "[00-env] GLPI ITSM environment loaded"
echo "[00-env] Hostname: ${GLPI_HOSTNAME} | MariaDB: ${MYSQL_HOST}:${MYSQL_PORT}"
echo "[00-env] LDAP: ${LDAP_HOST}:${LDAP_PORT} | Base DN: ${LDAP_BASE_DN}"
echo "[00-env] Backup dir: ${BACKUP_DIR} | Retention: ${BACKUP_RETENTION_DAYS}d"
echo "[00-env] Redmine: ${REDMINE_URL} | GitLab: ${GITLAB_URL}"
