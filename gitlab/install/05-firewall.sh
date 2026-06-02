#!/bin/bash
# ================================================================
# 05-firewall.sh — Firewall rules for GitLab services
# ================================================================
# Configures firewalld/nftables on the PVE host to allow:
#   - Port 80   (HTTP — Let's Encrypt challenge)
#   - Port 443  (HTTPS — GitLab Web UI & API)
#   - Port 2222 (SSH Git)
#
# All ports restricted to LAN (192.168.1.0/24) unless overridden.
# ================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-env.sh"

# LAN subnet for access restriction
LAN_SUBNET="192.168.1.0/24"

echo "=== Configurando firewall para GitLab ==="
echo ""

# ---------------------------------------------------------------
# Detect firewall: firewalld preferred (Rocky default), fallback to iptables/nftables
# ---------------------------------------------------------------
echo "[1/5] Detectando firewall activo..."

FW_TYPE=""
if command -v firewall-cmd &>/dev/null && firewall-cmd --state 2>/dev/null | grep -q "running"; then
    FW_TYPE="firewalld"
elif command -v nft &>/dev/null; then
    FW_TYPE="nftables"
elif command -v iptables &>/dev/null; then
    FW_TYPE="iptables"
fi

if [ -z "${FW_TYPE}" ]; then
    echo "⚠️  No se detectó firewall activo — verificar manualmente"
    echo "  Reglas sugeridas (firewalld):"
    echo "    firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source address=${LAN_SUBNET} port port=80 protocol=tcp accept'"
    echo "    firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source address=${LAN_SUBNET} port port=443 protocol=tcp accept'"
    echo "    firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source address=${LAN_SUBNET} port port=2222 protocol=tcp accept'"
    echo "    firewall-cmd --reload"
    exit 0
fi
echo "[1/5] ✅ Firewall detectado: ${FW_TYPE}"

# ---------------------------------------------------------------
# Configure firewall rules
# ---------------------------------------------------------------
echo ""
echo "[2/5] Agregando reglas de acceso..."

apply_rule() {
    local port="$1"
    local desc="$2"

    if [ "${FW_TYPE}" = "firewalld" ]; then
        ssh ${SSH_OPTS} root@${PVE_HOST_IP} "firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source address=${LAN_SUBNET} port port=${port} protocol=tcp accept' && firewall-cmd --reload" 2>/dev/null
    else
        # iptables/nftables fallback
        ssh ${SSH_OPTS} root@${PVE_HOST_IP} "iptables -A INPUT -p tcp -s ${LAN_SUBNET} --dport ${port} -j ACCEPT -m comment --comment '${desc}'" 2>/dev/null
    fi
    echo "  Puerto ${port} (${desc}) — OK"
}

apply_rule 80   "GitLab HTTP (Let's Encrypt)"
apply_rule 443  "GitLab HTTPS (Web UI + API)"
apply_rule 2222 "GitLab SSH Git"

echo "[2/5] ✅ Reglas de firewall aplicadas"

# ---------------------------------------------------------------
# Verify rules are active
# ---------------------------------------------------------------
echo ""
echo "[3/5] Verificando reglas..."

if [ "${FW_TYPE}" = "firewalld" ]; then
    ssh ${SSH_OPTS} root@${PVE_HOST_IP} "firewall-cmd --list-rich-rules | grep -E '80|443|2222'" || echo "  Reglas no visibles via firewall-cmd (verificar manual)"
else
    ssh ${SSH_OPTS} root@${PVE_HOST_IP} "iptables -L INPUT -n -v | grep -E '80|443|2222'" || echo "  Reglas no visibles (verificar manual)"
fi

# ---------------------------------------------------------------
# Confirm port forwarding DNAT for 2222
# ---------------------------------------------------------------
echo ""
echo "[4/5] Verificando DNAT para SSH Git..."

ssh ${SSH_OPTS} root@${PVE_HOST_IP} "iptables -t nat -L PREROUTING -n -v | grep 2222" && \
    echo "[4/5] ✅ DNAT 2222 → VM activo" || \
    echo "[4/5] ⚠️  DNAT 2222 no encontrado — verificar 04-configure-ssh.sh"

echo ""
echo "=== Firewall configuration complete ==="
echo "  Puertos abiertos desde ${LAN_SUBNET}:"
echo "    80/tcp   — GitLab HTTP (Let's Encrypt challenge)"
echo "    443/tcp  — GitLab HTTPS (Web UI + API)"
echo "    2222/tcp — GitLab SSH Git"
echo ""
echo "Next: run 06-verify.sh"
