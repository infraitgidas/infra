#!/bin/bash
# create-sudo-rules.sh — F4.6: Crear sudo rules en FreeIPA
#
# Uso: ./create-sudo-rules.sh [--dry-run]
#
# Configura sudo rules en FreeIPA según el diseño (sección 5):
#   - G-Direccion → ALL con NOPASSWD
#   - G-Coordinadores → ALL con NOPASSWD
#   - G-IdentityAdmins → ALL con NOPASSWD
#   - G-Becarios → Sin sudo
#   - SRV-InfraITAdmin → ALL con NOPASSWD
#   - SRV-Monitoring → Comandos específicos (plugins monitoreo, ping)
#
# Dependencias: `ipa` CLI autenticada en FreeIPA como admin
# Diseño: identity-management/sdd/design.md §5
# Grupos: identity-management/docs/identity/ad/grupos.md

set -euo pipefail

DRY_RUN="${1:-}"

# === Grupo → Sudo Rule (desde design.md §5) ===
# Formato: "nombre_grupo|comandos|opciones"
# comandos = ALL o lista de comandos específicos
# opciones = !authenticate (NOPASSWD) o vacío
declare -a SUDO_RULES=(
    "G-Direccion|ALL|!authenticate"
    "G-Coordinadores|ALL|!authenticate"
    "G-IdentityAdmins|ALL|!authenticate"
    "SRV-InfraITAdmin|ALL|!authenticate"
    "SRV-Monitoring|/usr/lib/nagios/plugins/*,/usr/bin/ping|!authenticate"
)

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

validate_prereqs() {
    if ! command -v ipa &>/dev/null; then
        log "ERROR: 'ipa' CLI no encontrada. Ejecutar desde FreeIPA server."
        exit 1
    fi

    if ! ipa ping &>/dev/null; then
        log "ERROR: No se puede conectar a FreeIPA. ¿Está autenticado? Ejecute: kinit admin"
        exit 1
    fi

    log "✅ Conexión a FreeIPA verificada"
}

rule_exists() {
    local rule_name="$1"
    ipa sudorule-find --name="$rule_name" 2>/dev/null | grep -q "Rule name: $rule_name"
}

create_sudo_rule() {
    local group_name="$1"
    local commands="$2"
    local sudo_options="${3:-}"
    local rule_name="${group_name}-sudo"

    if rule_exists "$rule_name"; then
        log "⚠️  Sudo rule '$rule_name' ya existe — se omite"
        return 0
    fi

    log "Creando sudo rule '$rule_name' para grupo '$group_name'..."

    if [[ "$DRY_RUN" == "--dry-run" ]]; then
        log "[DRY-RUN] ipa sudorule-add $rule_name --cmdcat=$commands"
        log "[DRY-RUN] ipa sudorule-add-user $rule_name --group=$group_name"
        log "[DRY-RUN] ipa sudorule-add-option $rule_name --sudooption='$sudo_options'"
        return 0
    fi

    # Crear regla
    if [[ "$commands" == "ALL" ]]; then
        ipa sudorule-add "$rule_name" --cmdcat=all || {
            log "ERROR: Falló creación de sudo rule '$rule_name'"
            return 1
        }
    else
        # Comandos específicos — agregar cada uno
        ipa sudorule-add "$rule_name" || {
            log "ERROR: Falló creación de sudo rule '$rule_name'"
            return 1
        }
        IFS=',' read -ra cmd_list <<< "$commands"
        for cmd in "${cmd_list[@]}"; do
            cmd=$(echo "$cmd" | xargs)  # trim
            ipa sudorule-add-allow-command "$rule_name" --command="$cmd" || {
                log "WARN: Falló agregar comando '$cmd' a '$rule_name'"
            }
        done
    fi

    # Asignar grupo de usuarios
    ipa sudorule-add-user "$rule_name" --group="$group_name" || {
        log "ERROR: Falló asignación de grupo '$group_name' a sudo rule '$rule_name'"
        ipa sudorule-del "$rule_name"
        return 1
    }

    # Opciones sudo (NOPASSWD)
    if [[ -n "$sudo_options" ]]; then
        ipa sudorule-add-option "$rule_name" --sudooption="$sudo_options" || {
            log "WARN: Falló agregar sudooption '$sudo_options' a '$rule_name'"
        }
    fi

    log "✅ Sudo rule '$rule_name' creada"
}

main() {
    log "=== Inicio: Creación de sudo rules FreeIPA ==="
    validate_prereqs

    local success=0
    local failed=0

    for entry in "${SUDO_RULES[@]}"; do
        IFS='|' read -r group commands options <<< "$entry"
        if create_sudo_rule "$group" "$commands" "$options"; then
            ((success++))
        else
            ((failed++))
        fi
    done

    # G-Becarios explícitamente sin sudo
    log "ℹ️  G-Becarios: sin sudo rule (acceso restringido por diseño)"

    if [[ "$DRY_RUN" == "--dry-run" ]]; then
        log "[DRY-RUN] No se realizaron cambios reales"
    fi

    log ""
    log "=== Resumen Sudo Rules ==="
    log "Reglas creadas/verificadas: $success"
    log "Fallos: $failed"
    log ""
    log "Reglas actuales en FreeIPA:"
    ipa sudorule-find 2>/dev/null || true

    if [[ $failed -gt 0 ]]; then
        log "⚠️  Algunas sudo rules requieren atención manual"
        exit 1
    fi

    log ""
    log "✅ Sudo rules configuradas correctamente"
}

main
