#!/bin/bash
# ============================================================
# deploy.sh — Deploy LibreNMS en CT 210
# ============================================================
set -euo pipefail
CT=210
ADMIN_EMAIL="${ADMIN_EMAIL:-admin@gidas.local}"
SNMP_COMMUNITY="${SNMP_COMMUNITY:-public}"

pct exec $CT -- bash -c "
mkdir -p /opt/librenms
cd /opt/librenms

# docker-compose.yml
cat > docker-compose.yml << 'DCEOF'
services:
  librenms:
    image: librenms/librenms:latest
    container_name: librenms
    hostname: librenms
    restart: unless-stopped
    ports:
      - \"127.0.0.1:8080:80\"
    volumes:
      - ./data:/data
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=America/Argentina/Buenos_Aires
    env_file:
      - .env
    depends_on:
      - mariadb
      - redis

  mariadb:
    image: mariadb:10
    container_name: librenms-db
    restart: unless-stopped
    volumes:
      - ./mysql:/var/lib/mysql
    environment:
      - MYSQL_ROOT_PASSWORD=__DB_ROOT_PW__
      - MYSQL_DATABASE=librenms
      - MYSQL_USER=librenms
      - MYSQL_PASSWORD=__DB_PASSWORD__
      - TZ=America/Argentina/Buenos_Aires

  redis:
    image: redis:7-alpine
    container_name: librenms-redis
    restart: unless-stopped
DCEOF

# .env
cat > .env << 'ENVEOF'
# LibreNMS config
APP_URL=https://nms.gidas.local
APP_KEY=__GENERAR_APP_KEY__
NODE_ID=__GENERAR_UUID__

# DB
DB_HOST=mariadb
DB_PORT=3306
DB_DATABASE=librenms
DB_USERNAME=librenms
DB_PASSWORD=__DB_PASSWORD__

# Redis
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_DB=0

# LDAP
AUTH_MECHANISM=ldap
AUTH_LDAP_SERVER=192.168.1.117
AUTH_LDAP_PORT=389
AUTH_LDAP_VERSION=3
AUTH_LDAP_STARTTLS=false
AUTH_LDAP_BASEDN=DC=GDC01,DC=local
AUTH_LDAP_BINDUSER=CN=infrait,OU=ServiceAccounts,DC=GDC01,DC=local
AUTH_LDAP_BINDPASSWORD=__LDAP_BIND_PASSWORD__
AUTH_LDAP_USERFILTER=(sAMAccountName=%u)

# SMTP
MAIL_DRIVER=smtp
MAIL_HOST=smtp.office365.com
MAIL_PORT=587
MAIL_USERNAME=infrait@frlp.utn.edu.ar
MAIL_PASSWORD=__SMTP_PASSWORD__
MAIL_ENCRYPTION=tls
MAIL_FROM_ADDRESS=infrait@frlp.utn.edu.ar
MAIL_FROM_NAME=LibreNMS GIDAS
ENVEOF

echo '=== .env template created ==='
ls -la docker-compose.yml .env
"
