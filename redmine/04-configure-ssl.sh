#!/bin/bash
# ================================================================
# 04-configure-ssl.sh — Phase 4: SSL + nginx + Firewall
# ================================================================
# Genera certificados self-signed, configura nginx reverse proxy
# con SSL, y habilita puertos 80/443 en firewalld.
# ================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=00-env.sh
. "${SCRIPT_DIR}/00-env.sh"

echo "=== Phase 4: Configure SSL + nginx on ${VM_FQDN} ==="

# --- Step 1: Generate self-signed certificate ---
echo "[Step 1] Generating self-signed SSL certificate..."
ssh ${SSH_OPTS} "${VM_USER}@${VM_IP}" \
    "mkdir -p ~/redmine/nginx/ssl && \
     openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -keyout ~/redmine/nginx/ssl/redmine.key \
        -out ~/redmine/nginx/ssl/redmine.crt \
        -subj '/C=AR/ST=Buenos Aires/L=Desa/O=GIDAS/CN=${VM_FQDN}' \
        -addext 'subjectAltName=DNS:${VM_FQDN},IP:${VM_IP}' 2>/dev/null"

echo "[Step 1] Certificate generated:"
ssh ${SSH_OPTS} "${VM_USER}@${VM_IP}" \
    "openssl x509 -in ~/redmine/nginx/ssl/redmine.crt -noout -subject -dates 2>/dev/null || true"

# --- Step 2: Copy nginx config ---
echo "[Step 2] Copying nginx configuration..."
scp ${SSH_OPTS} "${SCRIPT_DIR}/nginx/redmine.conf" "${VM_USER}@${VM_IP}:~/redmine/nginx/redmine.conf"

# --- Step 3: Restart nginx container ---
echo "[Step 3] Restarting nginx to apply SSL config..."
ssh ${SSH_OPTS} "${VM_USER}@${VM_IP}" \
    "cd ~/redmine && docker compose restart nginx"
sleep 3

# --- Step 4: Open firewall ports ---
echo "[Step 4] Opening firewall ports 80/tcp and 443/tcp..."
ssh ${SSH_OPTS} "${VM_USER}@${VM_IP}" \
    "sudo firewall-cmd --permanent --add-service=http --add-service=https 2>/dev/null && \
     sudo firewall-cmd --reload 2>/dev/null && \
     echo 'Firewall rules applied.' || \
     echo 'Note: firewalld not available or not running. Manual check needed.'"

# Show current firewall state
ssh ${SSH_OPTS} "${VM_USER}@${VM_IP}" \
    "sudo firewall-cmd --list-services 2>/dev/null || echo 'firewalld not active'"

# --- Step 5: Validate HTTPS ---
echo "[Step 5] Validating HTTPS endpoint..."
HTTPS_CODE=$(ssh ${SSH_OPTS} "${VM_USER}@${VM_IP}" \
    "curl -sk -o /dev/null -w '%{http_code}' https://localhost/login 2>/dev/null || echo '000'")
if [ "${HTTPS_CODE}" = "200" ]; then
    echo "[Step 5] HTTPS responds HTTP ${HTTPS_CODE} ✓"
    echo "[Step 5] curl -k https://${VM_FQDN}/login — should work from internal network"
elif [ "${HTTPS_CODE}" = "302" ]; then
    echo "[Step 5] HTTPS responds HTTP ${HTTPS_CODE} (redirect to login) ✓"
else
    echo "WARNING: HTTPS status: ${HTTPS_CODE}. Check with: docker compose logs nginx"
fi

# Also validate HTTP → HTTPS redirect
HTTP_CODE=$(ssh ${SSH_OPTS} "${VM_USER}@${VM_IP}" \
    "curl -s -o /dev/null -w '%{redirect_url}' http://localhost/ 2>/dev/null || echo '000'")
if echo "${HTTP_CODE}" | grep -q "^https://"; then
    echo "[Step 5] HTTP → HTTPS redirect working ✓ (→ ${HTTP_CODE})"
else
    echo "NOTE: HTTP redirect check: ${HTTP_CODE}"
fi

echo ""
echo "=== Phase 4 complete: SSL + nginx configured ==="
echo "    Access: https://${VM_FQDN}/login"
echo "    Cert:   Self-signed (distribute redmine.crt to clients)"
echo "    Next:   ./05-backup.sh"
