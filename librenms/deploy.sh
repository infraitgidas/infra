#!/bin/bash
# ============================================================
# deploy.sh — Deploy LibreNMS en CT 210 (pve-desa04)
# ============================================================
set -euo pipefail
CT=210

# === Validación ===
echo "=== Verificando CT $CT ==="
pct status $CT | grep -q running || { echo "ERROR: CT $CT no está running"; exit 1; }

# === Crear directorio ===
pct exec $CT -- mkdir -p /opt/librenms

# === Copiar archivos ===
pct push $CT /dev/stdin /opt/librenms/docker-compose.yml << 'DCEOF'
services:
  librenms:
    image: librenms/librenms:fixed
    container_name: librenms
    hostname: librenms
    restart: unless-stopped
    ports:
      - "127.0.0.1:8080:8000"
      - "162:162/udp"
      - "162:162/tcp"
      - "514:514/udp"
      - "514:514/tcp"
    depends_on:
      mariadb:
        condition: service_healthy
      redis:
        condition: service_started
    volumes:
      - librenms_data:/data
    env_file:
      - .env
    networks:
      - librenms

  mariadb:
    image: mariadb:10
    container_name: librenms-db
    restart: unless-stopped
    volumes:
      - mysql_data:/var/lib/mysql
    environment:
      - MYSQL_ROOT_PASSWORD=${DB_ROOT_PASSWORD}
      - MYSQL_DATABASE=librenms
      - MYSQL_USER=librenms
      - MYSQL_PASSWORD=${DB_PASSWORD}
      - TZ=America/Argentina/Buenos_Aires
    healthcheck:
      test: ["CMD", "healthcheck.sh", "--connect", "--innodb_initialized"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - librenms

  redis:
    image: redis:7-alpine
    container_name: librenms-redis
    restart: unless-stopped
    volumes:
      - redis_data:/data
    networks:
      - librenms

volumes:
  librenms_data:
  mysql_data:
  redis_data:

networks:
  librenms:
DCEOF

# === .env ===
# NOTA: La autenticación AD se configura en /data/config/config.php
# (persiste en el volumen librenms_data)
pct push $CT /dev/stdin /opt/librenms/.env << 'ENVEOF'
# ============================================================
# .env — LibreNMS GIDAS
# ============================================================
# NOTA: auth AD configurado en /data/config/config.php
# Usa auth_mechanism=active_directory con grupo G-IdentityAdmins

# Web
APP_URL=https://nms.gidas.local

# DB (generar con: openssl rand -hex 16)
DB_ROOT_PASSWORD=__CAMBIAR_DB_ROOT_PW__
DB_PASSWORD=__CAMBIAR_DB_PASSWORD__

# Redis
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_DB=0

# SMTP — Office 365
MAIL_DRIVER=smtp
MAIL_HOST=smtp.office365.com
MAIL_PORT=587
MAIL_USERNAME=infrait@frlp.utn.edu.ar
MAIL_PASSWORD=__SMTP_PASSWORD__
MAIL_ENCRYPTION=tls
MAIL_FROM_ADDRESS=infrait@frlp.utn.edu.ar
MAIL_FROM_NAME=LibreNMS GIDAS
ENVEOF

echo '=== Archivos copiados ==='
pct exec $CT -- ls -la /opt/librenms/

# === Deploy ===
echo '=== Deploying stack ==='
pct exec $CT -- bash -c '
  cd /opt/librenms
  docker compose up -d
'

echo "=== Waiting for healthy ==="
sleep 10
pct exec $CT -- docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'

echo ""
echo "=== Post-deploy ==="
echo "1. Configurar AD en /data/config/config.php dentro del container"
echo "2. Generar APP_KEY y NODE_ID: docker exec librenms php artisan key:generate"
echo "3. Agregar usuarios AD a grupos: gidas-admins, SRV-Monitoring o G-IdentityAdmins"
echo "4. Acceder a https://nms.gidas.local"
