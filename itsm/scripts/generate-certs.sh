#!/bin/bash
# ================================================================
# generate-certs.sh — GLPI Self-Signed Certificates
# ================================================================
# Genera certs autofirmados para nginx (glpi.gidas.local).
# Uso en dev / instalacion inicial; reemplazar por certs reales
# en produccion (misma ruta: itsm/certs/glpi.crt + glpi.key).
#
# Idempotente: si los certs ya existen, no los regenera.
# ================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CERTS_DIR="${SCRIPT_DIR}/../certs"
CERT="${CERTS_DIR}/glpi.crt"
KEY="${CERTS_DIR}/glpi.key"

mkdir -p "${CERTS_DIR}"

if [ -f "${CERT}" ] && [ -f "${KEY}" ]; then
    echo "Certs ya existen — no se regeneran:"
    echo "  ${CERT}"
    echo "  ${KEY}"
    exit 0
fi

echo "Generando cert autofirmado para glpi.gidas.local..."
openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
    -keyout "${KEY}" \
    -out "${CERT}" \
    -subj "/C=AR/ST=Buenos Aires/L=La Plata/O=GIDAS/OU=IT/CN=glpi.gidas.local" \
    -addext "subjectAltName=DNS:glpi.gidas.local,IP:192.168.1.47"

chmod 600 "${KEY}"
chmod 644 "${CERT}"

echo "Certs generados:"
echo "  ${CERT}"
echo "  ${KEY}"
echo "Montados por nginx en /etc/nginx/certs/"
