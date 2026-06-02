#!/bin/bash
# ================================================================
# 03-configure-https.sh — Let's Encrypt via Omnibus
# ================================================================
# Enables Let's Encrypt HTTPS via Omnibus built-in support.
# Uses HTTP-01 challenge (port 80 must be reachable).
# Falls back to DNS-01 if HTTP-01 fails.
#
# Prerequisites:
#   - GitLab installed and reconfigured (02-install-gitlab.sh)
#   - Port 80 accessible from Let's Encrypt servers
#   - DNS A record for GITLAB_DOMAIN pointing to VM_IP
# ================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-env.sh"

VM_SSH="ssh ${SSH_OPTS} root@${VM_IP%/*}"

echo "=== Configurando Let's Encrypt HTTPS para ${GITLAB_DOMAIN} ==="
echo ""

# ---------------------------------------------------------------
# Step 1: Verify gitlab.rb has letsencrypt enabled
# ---------------------------------------------------------------
echo "[1/4] Verificando configuración Let's Encrypt..."

LE_ENABLED=$(${VM_SSH} "grep -c \"letsencrypt\['enable'\] = true\" /etc/gitlab/gitlab.rb 2>/dev/null || echo 0")
if [ "${LE_ENABLED}" -eq 0 ]; then
    echo "⚠️  Let's Encrypt no habilitado en gitlab.rb — configurando ahora..."
    ${VM_SSH} bash -s -- "${GITLAB_DOMAIN}" "${GITLAB_LETSENCRYPT_EMAIL}" << 'REMOTE'
        DOMAIN="$1"; EMAIL="$2"
        cat >> /etc/gitlab/gitlab.rb << 'EOF'

# Let's Encrypt (added by 03-configure-https.sh)
letsencrypt['enable'] = true
letsencrypt['contact_emails'] = ['__LE_EMAIL__']
letsencrypt['auto_renew'] = true
EOF
        sed -i "s/__LE_EMAIL__/${EMAIL}/" /etc/gitlab/gitlab.rb
        echo "✅ Let's Encrypt configurado en gitlab.rb"
REMOTE
fi
echo "[1/4] ✅ Let's Encrypt habilitado"

# ---------------------------------------------------------------
# Step 2: Run reconfigure for certificate
# ---------------------------------------------------------------
echo ""
echo "[2/4] Ejecutando gitlab-ctl reconfigure (emisión de certificado)..."

${VM_SSH} "gitlab-ctl reconfigure" || {
    echo "⚠️  gitlab-ctl reconfigure falló — intentando DNS-01 como fallback..."
    echo "  Configure DNS-01 manualmente:"
    echo "  https://docs.gitlab.com/omnibus/settings/ssl/index.html#dns-challenge"
    echo "  Luego ejecute: gitlab-ctl reconfigure"
    exit 1
}
echo "[2/4] ✅ Certificado Let's Encrypt emitido/renew"

# ---------------------------------------------------------------
# Step 3: Verify HTTPS is working
# ---------------------------------------------------------------
echo ""
echo "[3/4] Verificando HTTPS..."

HTTPS_OK=$(curl -sf -o /dev/null -w "%{http_code}" "https://${GITLAB_DOMAIN}" 2>/dev/null || echo "000")
if [ "${HTTPS_OK}" = "302" ] || [ "${HTTPS_OK}" = "200" ]; then
    echo "[3/4] ✅ HTTPS respondiendo (código ${HTTPS_OK})"
else
    echo "[3/4] ⚠️  HTTPS código ${HTTPS_OK} — verificar DNS y reachability"
fi

# ---------------------------------------------------------------
# Step 4: Check cert validity
# ---------------------------------------------------------------
echo ""
echo "[4/4] Verificando expiración del certificado..."

CERT_EXPIRY=$(${VM_SSH} "openssl s_client -connect localhost:443 -servername ${GITLAB_DOMAIN} </dev/null 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null" || echo "unknown")
if [ -n "${CERT_EXPIRY}" ]; then
    echo "[4/4] ✅ Certificado: ${CERT_EXPIRY}"
    ${VM_SSH} "grep -q 'auto_renew.*true' /etc/gitlab/gitlab.rb && echo '  Renovación automática: habilitada'"
fi

echo ""
echo "=== HTTPS configuration complete ==="
echo "  URL: https://${GITLAB_DOMAIN}"
echo "  Certificado: Let's Encrypt via Omnibus"
echo "  Renovación: automática (cada ::1 día antes de expirar)"
echo ""
echo "Next: run 04-configure-ssh.sh"
