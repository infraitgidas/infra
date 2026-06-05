#!/bin/bash
# install-sssd-containers.sh — F4.2: Instalar SSSD en containers sg-*
#
# Uso: ./install-sssd-containers.sh [--dry-run]
#
# Instala SSSD + realmd + adcli en cada container sg-{rojo,azul,verde,amarillo,monitoring}
# y prepara la configuración base para el join a FreeIPA.
#
# Dependencias: pve-ad con `pct` disponible, containers en ejecución
#
# Diseño: identity-management/sdd/design.md §3.3
# Especificación: identity-management/sdd/specs.md §R4

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DRY_RUN="${1:-}"
LOG_FILE="/var/log/install-sssd-containers.log"

# Mapa container → IP (fuente: design.md §2)
declare -A CONTAINERS=(
    ["sg-rojo"]="192.168.1.200"
    ["sg-azul"]="192.168.1.204"
    ["sg-verde"]="192.168.1.202"
    ["sg-amarillo"]="192.168.1.203"
    ["sg-monitoring"]="192.168.1.205"
)

SSSD_PACKAGES="sssd sssd-tools realmd adcli"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

validate_prereqs() {
    if ! command -v pct &>/dev/null; then
        log "ERROR: 'pct' no encontrado. Ejecutar este script desde pve-ad."
        exit 1
    fi
}

install_sssd_container() {
    local ct_name="$1"
    local ct_ip="$2"
    local ct_id

    # Buscar CTID por nombre o IP
    ct_id=$(pct list 2>/dev/null | awk -v name="$ct_name" '$NF == name {print $1}')
    if [[ -z "$ct_id" ]]; then
        ct_id=$(pct list 2>/dev/null | awk -v ip="$ct_ip" '$0 ~ ip {print $1}')
    fi

    if [[ -z "$ct_id" ]]; then
        log "WARN: Container $ct_name ($ct_ip) no encontrado en pct list — se saltea"
        return 1
    fi

    local ct_status
    ct_status=$(pct status "$ct_id" 2>/dev/null | awk '{print $2}')
    if [[ "$ct_status" != "running" ]]; then
        log "WARN: Container $ct_name (CT $ct_id) no está running (status=$ct_status) — se saltea"
        return 1
    fi

    log "Instalando SSSD en $ct_name (CT $ct_id, $ct_ip)..."

    if [[ "$DRY_RUN" == "--dry-run" ]]; then
        log "[DRY-RUN] pct exec $ct_id -- apt update -y"
        log "[DRY-RUN] pct exec $ct_id -- apt install -y $SSSD_PACKAGES"
        return 0
    fi

    if pct exec "$ct_id" -- dpkg -l sssd 2>/dev/null | grep -q "^ii"; then
        log "SSSD ya está instalado en $ct_name — se omite"
        return 0
    fi

    pct exec "$ct_id" -- bash -c "apt update -y && apt install -y $SSSD_PACKAGES" || {
        log "ERROR: Falló instalación de SSSD en $ct_name"
        return 1
    }

    # Verificar instalación
    local sssd_ver
    sssd_ver=$(pct exec "$ct_id" -- sssd --version 2>/dev/null || echo "ERROR")
    log "SSSD versión $sssd_ver instalado en $ct_name"

    # Crear directorio para config (sssd.conf se aplica en F4.3 ya completado)
    pct exec "$ct_id" -- mkdir -p /etc/sssd

    log "✅ SSSD instalado en $ct_name"
}

main() {
    log "=== Inicio: Instalación de SSSD en containers sg-* ==="
    validate_prereqs

    local success=0
    local failed=0

    for ct_name in "${!CONTAINERS[@]}"; do
        if install_sssd_container "$ct_name" "${CONTAINERS[$ct_name]}"; then
            ((success++))
        else
            ((failed++))
        fi
        echo ""
    done

    log "=== Resumen: $success containers OK, $failed fallos ==="
    if [[ "$DRY_RUN" == "--dry-run" ]]; then
        log "[DRY-RUN] No se realizaron cambios reales"
    fi

    if [[ $failed -gt 0 ]]; then
        log "⚠️  Algunos containers requieren atención manual"
    fi
}

main
