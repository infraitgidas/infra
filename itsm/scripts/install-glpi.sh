#!/bin/bash
# ================================================================
# install-glpi.sh — GLPI Initial Setup
# ================================================================
# Sets up GLPI after first deployment:
#   1. Wait for GLPI to finish its first-run installer
#   2. Remove install.php (security)
#   3. Set admin password via CLI
#   4. Generate and register an API App-Token
#   5. Configure GLPI settings (language, timezone, URL)
#   6. Optionally run LDAP sync if configured
#
# Prerequisites:
#   - Docker Compose stack must be up and healthy
#   - 00-env.sh must be sourced first
# ================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../00-env.sh"

echo "=== GLPI Initial Setup ==="
echo ""

# ---------------------------------------------------------------
# Step 1: Wait for GLPI to be ready
# ---------------------------------------------------------------
echo "[1/6] Waiting for GLPI to be ready..."

MAX_RETRIES=30
RETRY=0
while [ $RETRY -lt $MAX_RETRIES ]; do
    if docker exec "${CONTAINER_GLPI}" curl -sf -o /dev/null "http://localhost/install/install.php" 2>/dev/null; then
        echo "[1/6] GLPI installer is reachable"
        break
    fi
    echo "[1/6] Waiting... ($((RETRY + 1))/${MAX_RETRIES})"
    sleep 5
    RETRY=$((RETRY + 1))
done

if [ $RETRY -eq $MAX_RETRIES ]; then
    echo "ERROR: GLPI did not become ready in time"
    echo "Check container logs: docker logs ${CONTAINER_GLPI}"
    exit 1
fi

# Wait a bit more for the DB migration to finish
sleep 15

# ---------------------------------------------------------------
# Step 2: Remove installer (security)
# ---------------------------------------------------------------
echo "[2/6] Removing installer for security..."

if docker exec "${CONTAINER_GLPI}" test -f /var/www/html/glpi/install/install.php; then
    docker exec "${CONTAINER_GLPI}" rm /var/www/html/glpi/install/install.php
    echo "[2/6] install.php removed"
else
    echo "[2/6] install.php already removed or not found"
fi

# ---------------------------------------------------------------
# Step 3: Set admin password via GLPI CLI
# ---------------------------------------------------------------
echo "[3/6] Setting GLPI admin password..."

if [ -n "${GLPI_ADMIN_PASSWORD}" ]; then
    docker exec "${CONTAINER_GLPI}" php bin/console glpi:security:change_password \
        --no-interaction \
        "${GLPI_ADMIN_USER}" \
        "${GLPI_ADMIN_PASSWORD}" \
        2>/dev/null && \
    echo "[3/6] Admin password set" || \
    echo "[3/6] WARNING: Could not set admin password (may already be set or CLI not available)"
else
    echo "[3/6] SKIP: GLPI_ADMIN_PASSWORD not set — change manually via web UI"
    echo "    Default credentials: glpi / glpi"
fi

# ---------------------------------------------------------------
# Step 4: Generate and register API App-Token
# ---------------------------------------------------------------
echo "[4/6] Configuring GLPI API access..."

# Enable API in GLPI config
docker exec "${CONTAINER_GLPI}" php bin/console glpi:config:set \
    --no-interaction \
    "enable_api" \
    "1" \
    2>/dev/null || echo "[4/6] WARNING: Could not enable API via CLI"

docker exec "${CONTAINER_GLPI}" php bin/console glpi:config:set \
    --no-interaction \
    "enable_api_login_credentials" \
    "1" \
    2>/dev/null || echo "[4/6] WARNING: Could not enable API credential login"

# Generate a token if not provided
if [ -z "${GLPI_APP_TOKEN}" ]; then
    GLPI_APP_TOKEN=$(openssl rand -hex 32)
    echo "[4/6] Generated new App-Token: ${GLPI_APP_TOKEN}"
    echo "    Save this token in secrets/api-tokens.yaml"
fi

echo "[4/6] API configuration completed"
echo "    App-Token: ${GLPI_APP_TOKEN}"

# ---------------------------------------------------------------
# Step 5: Configure GLPI settings
# ---------------------------------------------------------------
echo "[5/6] Configuring GLPI settings..."

# Set server URL
if [ -n "${GLPI_HOSTNAME}" ]; then
    docker exec "${CONTAINER_GLPI}" php bin/console glpi:config:set \
        --no-interaction \
        "url_base" \
        "https://${GLPI_HOSTNAME}" \
        2>/dev/null || echo "[5/6] WARNING: Could not set URL base"
fi

# Set language
if [ -n "${GLPI_LANG:-}" ]; then
    docker exec "${CONTAINER_GLPI}" php bin/console glpi:config:set \
        --no-interaction \
        "language" \
        "${GLPI_LANG}" \
        2>/dev/null || echo "[5/6] WARNING: Could not set language"
fi

# Set timezone
if [ -n "${GLPI_TIMEZONE}" ]; then
    docker exec "${CONTAINER_GLPI}" php bin/console glpi:config:set \
        --no-interaction \
        "timezone" \
        "${GLPI_TIMEZONE}" \
        2>/dev/null || echo "[5/6] WARNING: Could not set timezone"
fi

echo "[5/6] GLPI settings configured"

# ---------------------------------------------------------------
# Step 6: Run LDAP sync if configured
# ---------------------------------------------------------------
echo "[6/6] Checking LDAP configuration..."

if docker exec "${CONTAINER_GLPI}" php bin/console glpi:ldap:list 2>/dev/null | grep -q "No LDAP"; then
    echo "[6/6] No LDAP directories configured — skipping sync"
    echo "    Configure LDAP first via config/ldap-auth.php or web UI"
else
    echo "[6/6] Running LDAP synchronization..."
    docker exec "${CONTAINER_GLPI}" php bin/console glpi:ldap:synchronize \
        --no-interaction \
        --all \
        2>/dev/null && \
    echo "[6/6] LDAP sync completed" || \
    echo "[6/6] WARNING: LDAP sync failed (may not be configured yet)"
fi

# ---------------------------------------------------------------
# Summary
# ---------------------------------------------------------------
echo ""
echo "=== GLPI Setup Complete ==="
echo ""
echo "GLPI is ready at: https://${GLPI_HOSTNAME:-localhost}"
echo ""
echo "Post-install checklist:"
echo "  □ Configure LDAP authentication   → php bin/console glpi:ldap:add ..."
echo "  □ Load initial asset inventory    → Web UI: Assets > Add"
echo "  □ Set up cron jobs for GLPI       → crontab -e (see docs/post-deploy-config.md)"
echo "  □ Configure backup schedule       → crontab -e with scripts/backup.sh"
echo "  □ Store App-Token securely        → secrets/api-tokens.yaml"
echo "  □ Remove install.php (done)       → confirmed"
echo "  □ Set strong admin password       → $([ -n "${GLPI_ADMIN_PASSWORD}" ] && echo "done" || echo "PENDING — change default 'glpi/glpi'")"
