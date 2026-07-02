#!/bin/bash
# ============================================================
# deploy.sh — Deploy Vaultwarden en CT 209
# ============================================================
set -euo pipefail

CT_ID=209
CT_IP="192.168.1.44/24"
CT_GW="192.168.1.1"
CT_MEMORY=512
CT_DISK=8
CT_HOSTNAME=vaultwarden
CT_TEMPLATE="local:vztmpl/rockylinux-9-default_20240912_amd64.tar.xz"
ADMIN_TOKEN="${ADMIN_TOKEN:-$(openssl rand -hex 32)}"

echo "=== Creando CT $CT_ID ==="
pct create $CT_ID $CT_TEMPLATE \
  --hostname $CT_HOSTNAME \
  --rootfs local-lvm:${CT_DISK} \
  --memory $CT_MEMORY \
  --cores 1 \
  --net0 name=eth0,bridge=vmbr0,ip=$CT_IP,gw=$CT_GW \
  --nameserver 192.168.1.117 \
  --password 'hlvs.2025' \
  --unprivileged 1 \
  --features 'nesting=1' \
  --onboot 1 \
  --start 1

echo "=== Instalando Docker y nginx ==="
pct exec $CT_ID -- dnf install -y 'dnf-command(config-manager)'
pct exec $CT_ID -- dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
pct exec $CT_ID -- dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin nginx openssl

echo "=== Iniciando Docker ==="
pct exec $CT_ID -- systemctl enable --now docker

echo "=== Creando SSL self-signed ==="
pct exec $CT_ID -- mkdir -p /etc/nginx/ssl
pct exec $CT_ID -- openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/nginx/ssl/vaultwarden.key \
  -out /etc/nginx/ssl/vaultwarden.crt \
  -subj "/C=AR/ST=BuenosAires/L=LaPlata/O=GIDAS/CN=vault.gidas.local"

echo "=== Configurando nginx ==="
pct exec $CT_ID -- bash -c 'cat > /etc/nginx/conf.d/vaultwarden.conf << '\''EOF'\''
server {
    listen 80;
    server_name vault.gidas.local;
    return 301 https://$server_name$request_uri;
}
server {
    listen 443 ssl http2;
    server_name vault.gidas.local;
    ssl_certificate /etc/nginx/ssl/vaultwarden.crt;
    ssl_certificate_key /etc/nginx/ssl/vaultwarden.key;
    location / {
        proxy_pass http://127.0.0.1:3012;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF'

echo "=== Iniciando nginx ==="
pct exec $CT_ID -- systemctl enable --now nginx

echo "=== Directorio de datos ==="
pct exec $CT_ID -- mkdir -p /opt/vaultwarden/data

echo "=== Corriendo Vaultwarden ==="
pct exec $CT_ID -- env PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin docker run -d --name vaultwarden \
  --restart unless-stopped \
  -p 127.0.0.1:3012:80 \
  -v /opt/vaultwarden/data:/data \
  -e SIGNUPS_ALLOWED=false \
  -e INVITATIONS_ALLOWED=true \
  -e DOMAIN=https://vault.gidas.local \
  -e ADMIN_TOKEN="$ADMIN_TOKEN" \
  -e LDAP_URL=ldap://192.168.1.117 \
  -e LDAP_START_TLS=false \
  -e LDAP_BIND_DN="CN=infrait,OU=ServiceAccounts,DC=GDC01,DC=local" \
  -e LDAP_BIND_PASSWORD="__LDAP_BIND_PASSWORD__" \
  -e LDAP_SEARCH_BASE="DC=GDC01,DC=local" \
  -e 'LDAP_SEARCH_FILTER=(|(mail={{username}})(sAMAccountName={{username}}))' \
  -e LDAP_MAIL_ATTRIBUTE=mail \
  -e LDAP_USER_ATTRIBUTE=sAMAccountName \
  vaultwarden/server:latest-alpine

echo "=== Verificando ==="
sleep 3
pct exec $CT_ID -- curl -sk -o /dev/null -w '%{http_code}' https://127.0.0.1/ -H 'Host: vault.gidas.local'
echo ""

echo "=== Vaultwarden deployado ==="
echo "URL: https://vault.gidas.local"
echo "Admin token: $ADMIN_TOKEN"
echo "Admin panel: https://vault.gidas.local/admin"
echo ""
echo "IMPORTANTE: Reemplazar '__LDAP_BIND_PASSWORD__' en el comando docker run"
echo "con la password real de AD antes de ejecutar este script."
