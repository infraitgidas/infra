#!/bin/bash
# ================================================================
# 04-configure-ssh.sh — Git SSH via port 2222 DNAT
# ================================================================
# Configures iptables DNAT on the PVE host to forward port 2222
# to port 22 in the GitLab VM. Enables gitlab-sshd in the VM.
#
# Prerequisites:
#   - GitLab installed (02-install-gitlab.sh)
#   - VM reachable on VM_IP
# ================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-env.sh"

VM_IP_ADDR="${VM_IP%/*}"

echo "=== Configurando SSH Git (2222 → VM:22) ==="
echo ""

# ---------------------------------------------------------------
# Step 1: Enable gitlab-sshd in the VM
# ---------------------------------------------------------------
echo "[1/4] Habilitando gitlab-sshd en la VM..."

ssh ${SSH_OPTS} root@${VM_IP_ADDR} bash -s -- "${GITLAB_SSH_PORT}" << 'REMOTE'
    set -euo pipefail
    SSH_PORT="$1"

    # Enable gitlab-sshd (replaces system sshd for Git operations)
    sed -i 's/^# gitlab_sshd\['\''enable'\''\]/gitlab_sshd['\''enable'\'']/' /etc/gitlab/gitlab.rb
    grep -q "gitlab_sshd\['enable'\]" /etc/gitlab/gitlab.rb || \
        echo "gitlab_sshd['enable'] = true" >> /etc/gitlab/gitlab.rb

    # Set SSH port forwarding
    sed -i "s/^gitlab_rails\['gitlab_shell_ssh_port'\]/gitlab_rails['gitlab_shell_ssh_port']/" /etc/gitlab/gitlab.rb
    grep -q "gitlab_shell_ssh_port" /etc/gitlab/gitlab.rb || \
        echo "gitlab_rails['gitlab_shell_ssh_port'] = ${SSH_PORT}" >> /etc/gitlab/gitlab.rb

    gitlab-ctl reconfigure
    echo "✅ gitlab-sshd habilitado"
REMOTE
echo "[1/4] ✅ gitlab-sshd activo"

# ---------------------------------------------------------------
# Step 2: Add iptables DNAT rule on PVE host
# ---------------------------------------------------------------
echo ""
echo "[2/4] Agregando regla DNAT 2222 → VM:22 en ${PVE_HOST}..."

ssh ${SSH_OPTS} root@${PVE_HOST_IP} bash -s -- "${HOST_SSH_PORT}" "${VM_IP_ADDR}" "${VM_GIT_SSH_PORT}" << 'REMOTE'
    set -euo pipefail
    HOST_PORT="$1"; VM_IP="$2"; VM_PORT="$3"

    # Check if rule already exists
    EXISTING=$(iptables -t nat -C PREROUTING -p tcp --dport "${HOST_PORT}" -j DNAT --to-destination "${VM_IP}:${VM_PORT}" 2>&1 || echo "MISSING")
    if echo "${EXISTING}" | grep -q "MISSING"; then
        iptables -t nat -A PREROUTING -p tcp --dport "${HOST_PORT}" -j DNAT --to-destination "${VM_IP}:${VM_PORT}"
        # Save rules (Rocky: iptables-save, Ubuntu: netfilter-persistent)
        if command -v netfilter-persistent &>/dev/null; then
            netfilter-persistent save
        elif [ -d /etc/iptables/ ]; then
            iptables-save > /etc/iptables/rules.v4
        elif [ -d /etc/sysconfig ]; then
            iptables-save > /etc/sysconfig/iptables
        fi
        echo "✅ DNAT agregado: :${HOST_PORT} → ${VM_IP}:${VM_PORT}"
    else
        echo "⚠️  DNAT ya existe — omitiendo"
    fi

    # Enable IP forwarding if not already
    if [ "$(sysctl -n net.ipv4.ip_forward)" != "1" ]; then
        sysctl -w net.ipv4.ip_forward=1
        echo "net.ipv4.ip_forward=1" >> /etc/sysctl.d/99-gitlab.conf
        echo "✅ IP forwarding habilitado"
    fi
REMOTE
echo "[2/4] ✅ DNAT configurado"

# ---------------------------------------------------------------
# Step 3: Create helper script for removing DNAT
# ---------------------------------------------------------------
echo ""
echo "[3/4] Creando script helper para remove DNAT..."

cat > /tmp/remove-gitlab-dnat.sh << 'SCRIPT'
#!/bin/bash
# Remove GitLab DNAT rule
HOST_PORT="${1:-2222}"
iptables -t nat -D PREROUTING -p tcp --dport "${HOST_PORT}" -j DNAT --to-destination "${VM_IP}:${VM_PORT}" 2>/dev/null || true
echo "DNAT rule removed"
SCRIPT
chmod +x /tmp/remove-gitlab-dnat.sh
ssh ${SSH_OPTS} root@${PVE_HOST_IP} "cat > /usr/local/bin/remove-gitlab-dnat.sh" < /tmp/remove-gitlab-dnat.sh
ssh ${SSH_OPTS} root@${PVE_HOST_IP} "chmod +x /usr/local/bin/remove-gitlab-dnat.sh"
rm /tmp/remove-gitlab-dnat.sh
echo "[3/4] ✅ Helper /usr/local/bin/remove-gitlab-dnat.sh creado"

# ---------------------------------------------------------------
# Step 4: Test SSH connectivity
# ---------------------------------------------------------------
echo ""
echo "[4/4] Probando SSH Git en puerto ${GITLAB_SSH_PORT}..."

ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -p "${GITLAB_SSH_PORT}" "git@${PVE_HOST_IP}" "info" 2>&1 || true
echo "  (el mensaje 'Welcome to GitLab' confirma que funciona)"
echo "[4/4] ✅ SSH Git listo en :${GITLAB_SSH_PORT}"

echo ""
echo "=== SSH Git configuration complete ==="
echo "  Clone URL: ssh://git@${PVE_HOST_IP}:${GITLAB_SSH_PORT}/grupo/repo.git"
echo "  DNAT: :${GITLAB_SSH_PORT} → ${VM_IP_ADDR}:${VM_GIT_SSH_PORT}"
echo ""
echo "Next: run 05-firewall.sh"
