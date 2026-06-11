#!/bin/bash
# ================================================================
# install-cron.sh — Install AD→Redmine sync cron job
# ================================================================
# Instala el script de sync en cron para ejecución cada 15 minutos.
#
# Uso:
#   ./install-cron.sh              # Instalar cron (dry-run primero)
#   ./install-cron.sh --force      # Instalar sin confirmación
#   ./install-cron.sh --remove     # Remover cron job
# ================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYNC_SCRIPT="${SCRIPT_DIR}/sync-ad-members.sh"
CRON_FILE="/etc/cron.d/redmine-ad-sync"
LOG_FILE="/var/log/redmine-ad-sync.log"

FORCE=false
REMOVE=false

for arg in "$@"; do
    case "$arg" in
        --force) FORCE=true ;;
        --remove) REMOVE=true ;;
    esac
done

if [ "$REMOVE" = true ]; then
    if [ -f "$CRON_FILE" ]; then
        rm -f "$CRON_FILE"
        echo "[OK] Cron job removed: ${CRON_FILE}"
    else
        echo "[OK] No cron job to remove"
    fi
    exit 0
fi

# Verificar que el script de sync existe
if [ ! -f "$SYNC_SCRIPT" ]; then
    echo "[ERROR] Sync script not found: ${SYNC_SCRIPT}" >&2
    exit 1
fi

# Verificar que es ejecutable
if [ ! -x "$SYNC_SCRIPT" ]; then
    chmod +x "$SYNC_SCRIPT"
fi

# Crear entry de cron
CRON_CONTENT="# AD → Redmine Group/Role Sync
# Sincroniza grupos AD y asigna roles finos por proyecto.
# Instalado por: ${SCRIPT_DIR}/install-cron.sh
# Fecha: $(date -I)
*/15 * * * * root ${SYNC_SCRIPT} >> ${LOG_FILE} 2>&1
"

if [ "$FORCE" = false ]; then
    echo "=== Cron Installation Preview ==="
    echo "Script: ${SYNC_SCRIPT}"
    echo "Cron:   ${CRON_FILE}"
    echo "Log:    ${LOG_FILE}"
    echo ""
    echo "Content to install:"
    echo "${CRON_CONTENT}"
    echo ""
    read -rp "Install? [y/N] " CONFIRM
    if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
        echo "Cancelled."
        exit 0
    fi
fi

# Escribir cron file
echo "${CRON_CONTENT}" > "$CRON_FILE"
chmod 644 "$CRON_FILE"

echo "[OK] Cron installed: ${CRON_FILE}"
echo "[OK] Running every 15 minutes"
echo "[OK] Log: ${LOG_FILE}"
echo ""
echo "Test the sync script manually first:"
echo "  ${SYNC_SCRIPT} --dry-run --verbose"
echo ""
echo "View sync log:"
echo "  tail -f ${LOG_FILE}"
