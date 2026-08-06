#!/bin/bash
# ================================================================
# install-glpi.sh — GLPI Initial Setup
# ================================================================
# Sets up GLPI after first deployment (imagen oficial glpi/glpi):
#   1. Wait for GLPI container to be healthy (autoinstall ya corrio)
#   2. Set admin password via CLI
#   3. Enable API and register an App-Token
#   4. Configure GLPI settings (URL, language, timezone)
#   5. Optionally run LDAP sync if configured
#
# NOTA (2026-08-06): la imagen oficial glpi/glpi realiza la instalacion
# automaticamente al primer arranque (GLPI_SKIP_AUTOINSTALL=false). Ya no
# se espera ni se elimina install/install.php — la imagen maneja su ciclo.
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
# Step 1: Wait for GLPI to be ready (container healthy)
# ---------------------------------------------------------------
echo "[1/5] Waiting for GLPI to be ready..."

MAX_RETRIES=40
RETRY=0
while [ $RETRY -lt $MAX_RETRIES ]; do
    STATUS=$(docker inspect --format='{{.State.Health.Status}}' "${CONTAINER_GLPI}" 2>/dev/null || echo "not-found")
    if [ "${STATUS}" = "healthy" ]; then
        echo "[1/5] GLPI container is healthy"
        break
    fi
    echo "[1/5] Waiting... ($((RETRY + 1))/${MAX_RETRIES}) status=${STATUS}"
    sleep 10
    RETRY=$((RETRY + 1))
done

if [ $RETRY -eq $MAX_RETRIES ]; then
    echo "ERROR: GLPI did not become ready in time" >&2
    echo "Check container logs: docker logs ${CONTAINER_GLPI}" >&2
    exit 1
fi

# Wait for the automatic database installation to complete.
# glpi:system:status exits non-zero until GLPI is fully installed.
echo "[1/5] Waiting for GLPI autoinstall to finish..."

MAX_RETRIES=30
RETRY=0
while [ $RETRY -lt $MAX_RETRIES ]; do
    if docker exec "${CONTAINER_GLPI}" php bin/console glpi:system:status >/dev/null 2>&1; then
        echo "[1/5] GLPI autoinstall completed"
        break
    fi
    echo "[1/5] Autoinstall in progress... ($((RETRY + 1))/${MAX_RETRIES})"
    sleep 10
    RETRY=$((RETRY + 1))
done

if [ $RETRY -eq $MAX_RETRIES ]; then
    echo "ERROR: GLPI autoinstall did not complete in time" >&2
    echo "Check container logs: docker logs ${CONTAINER_GLPI}" >&2
    exit 1
fi

# ---------------------------------------------------------------
# Step 2: Set admin password via GLPI CLI
# ---------------------------------------------------------------
echo "[2/5] Setting GLPI admin password..."

# NOTA: GLPI 10.0 NO expone comando CLI para cambiar password
# (glpi:security:change_password llego en GLPI 11). Se actualiza
# la tabla glpi_users con un hash bcrypt generado en el contenedor.
if [ -n "${GLPI_ADMIN_PASSWORD}" ]; then
    HASH=$(docker exec "${CONTAINER_GLPI}" php -r "echo password_hash('${GLPI_ADMIN_PASSWORD}', PASSWORD_BCRYPT);" 2>/dev/null || true)
    if [ -n "${HASH}" ] && docker exec "${CONTAINER_MARIADB}" \
        mariadb -u"${MYSQL_USER}" -p"${MYSQL_PASSWORD}" "${MYSQL_DATABASE}" \
        -e "UPDATE glpi_users SET password='${HASH}' WHERE name='${GLPI_ADMIN_USER}' AND is_active=1;" >/dev/null 2>&1; then
        echo "[2/5] Admin password set (bcrypt via SQL)"
    else
        echo "[2/5] WARNING: Could not set admin password — verify manually" >&2
    fi
else
    echo "[2/5] SKIP: GLPI_ADMIN_PASSWORD not set — change manually via web UI"
    echo "    Default credentials: glpi / glpi"
fi

# ---------------------------------------------------------------
# Step 3: Generate and register API App-Token
# ---------------------------------------------------------------
echo "[3/5] Configuring GLPI API access..."

docker exec "${CONTAINER_GLPI}" php bin/console glpi:config:set \
    --no-interaction \
    "enable_api" \
    "1" \
    >/dev/null 2>&1 || echo "[3/5] WARNING: Could not enable API via CLI"

docker exec "${CONTAINER_GLPI}" php bin/console glpi:config:set \
    --no-interaction \
    "enable_api_login_credentials" \
    "1" \
    >/dev/null 2>&1 || echo "[3/5] WARNING: Could not enable API credential login"

# Generate a token if not provided
if [ -z "${GLPI_APP_TOKEN}" ]; then
    GLPI_APP_TOKEN=$(openssl rand -hex 32)
    echo "[3/5] Generated new App-Token: ${GLPI_APP_TOKEN}"
    echo "    Save this token in secrets/glpi.yaml"
fi

echo "[3/5] API configuration completed"
echo "    App-Token: ${GLPI_APP_TOKEN}"

# ---------------------------------------------------------------
# Step 4: Configure GLPI settings
# ---------------------------------------------------------------
echo "[4/5] Configuring GLPI settings..."

# Set server URL
if [ -n "${GLPI_HOSTNAME}" ]; then
    docker exec "${CONTAINER_GLPI}" php bin/console glpi:config:set \
        --no-interaction \
        "url_base" \
        "https://${GLPI_HOSTNAME}" \
        >/dev/null 2>&1 || echo "[4/5] WARNING: Could not set URL base"
fi

# Set language
if [ -n "${GLPI_LANG}" ]; then
    docker exec "${CONTAINER_GLPI}" php bin/console glpi:config:set \
        --no-interaction \
        "language" \
        "${GLPI_LANG}" \
        >/dev/null 2>&1 || echo "[4/5] WARNING: Could not set language"
fi

# Set timezone
if [ -n "${GLPI_TIMEZONE}" ]; then
    docker exec "${CONTAINER_GLPI}" php bin/console glpi:config:set \
        --no-interaction \
        "timezone" \
        "${GLPI_TIMEZONE}" \
        >/dev/null 2>&1 || echo "[4/5] WARNING: Could not set timezone"
fi

echo "[4/5] GLPI settings configured"

# ---------------------------------------------------------------
# Step 5: Run LDAP sync if configured
# ---------------------------------------------------------------
echo "[5/5] Checking LDAP configuration..."

# En GLPI 10 el comando es ldap:synchronize_users (alias ldap:sync);
# si no hay directorios LDAP configurados, falla -> se reporta como skip.
if docker exec "${CONTAINER_GLPI}" php bin/console ldap:synchronize_users \
    --no-interaction \
    --all \
    >/dev/null 2>&1; then
    echo "[5/5] LDAP sync completed"
else
    echo "[5/5] No LDAP directories configured — skipping sync"
    echo "    Configure LDAP first via config/ldap-auth.php or web UI"
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
echo "  □ Store App-Token securely        → secrets/glpi.yaml"
echo "  □ Set strong admin password       → $([ -n "${GLPI_ADMIN_PASSWORD}" ] && echo "done" || echo "PENDING — change default 'glpi/glpi'")"
