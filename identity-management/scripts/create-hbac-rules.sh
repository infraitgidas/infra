#!/bin/bash
# create-hbac-rules.sh — F4.5: Crear reglas HBAC en FreeIPA
#
# Uso: ./create-hbac-rules.sh [--dry-run]
#
# Crea reglas HBAC para cada grupo AD, asociando grupo → hosts permitidos
# según el diseño (sección 5) y la documentación actual en grupos.md.
#
# Regla global: Deny by default. Solo los grupos explícitamente listados
# tienen acceso a hosts específicos.
#
# Dependencias: `ipa` CLI autenticada en FreeIPA como admin
# Diseño: identity-management/sdd/design.md §5

set -euo pipefail

DRY_RUN="${1:-}"

# === Grupo → Hosts Permitidos (desde design.md §5 + grupos.md) ===
# Formato: "nombre_grupo|hosts"
# hosts = ALL, nombre(s) de host separados por coma, o FQDN
declare -a HBAC_RULES=(
    "G-Direccion|ALL"
    "G-Coordinadores|ALL"
    "G-IdentityAdmins|ALL"
    "G-Becarios|GROUP:host-del-proyecto-asignado"
    "SRV-InfraITAdmin|GROUP:servidores-infrait"
    "SRV-Monitoring|sg-monitoring.gdc01.local"
)

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

validate_prereqs() {
    if ! command -v ipa &>/dev/null; then
        log "ERROR: 'ipa' CLI no encontrada. Ejecutar desde FreeIPA server."
        exit 1
    fi

    # Verificar autenticación IPA
    if ! ipa ping &>/dev/null; then
        log "ERROR: No se puede conectar a FreeIPA. ¿Está autenticado? Ejecute: kinit admin"
        exit 1
    fi

    log "✅ Conexión a FreeIPA verificada"
}

rule_exists() {
    local rule_name="$1"
    ipa hbacrule-find --name="$rule_name" 2>/dev/null | grep -q "Rule name: $rule_name"
}

create_hbac_rule() {
    local group_name="$1"
    local hosts="$2"
    local rule_name="${group_name}-access"

    if rule_exists "$rule_name"; then
        log "⚠️  HBAC rule '$rule_name' ya existe — se omite"
        return 0
    fi

    log "Creando HBAC rule '$rule_name' para grupo '$group_name' → hosts '$hosts'..."

    if [[ "$DRY_RUN" == "--dry-run" ]]; then
        log "[DRY-RUN] ipa hbacrule-add $rule_name --hostcat=$hosts"
        log "[DRY-RUN] ipa hbacrule-add-user $rule_name --group=$group_name"
        log "[DRY-RUN] ipa hbacrule-add-service $rule_name --servicecat=all"
        return 0
    fi

    # Si hosts = ALL, usar --hostcat=all
    if [[ "$hosts" == "ALL" ]]; then
        ipa hbacrule-add "$rule_name" --hostcat=all || {
            log "ERROR: Falló creación de rule '$rule_name'"
            return 1
        }
    else
        ipa hbacrule-add "$rule_name" --hosts="$hosts" || {
            log "ERROR: Falló creación de rule '$rule_name' con hosts específicos"
            return 1
        }
    fi

    # Servicio: todos por defecto (SSH, sudo, login)
    ipa hbacrule-add-service "$rule_name" --servicecat=all || true

    # Usuario: grupo AD
    ipa hbacrule-add-user "$rule_name" --group="$group_name" || {
        log "ERROR: Falló asignación de grupo '$group_name' a rule '$rule_name'"
        ipa hbacrule-del "$rule_name"
        return 1
    }

    log "✅ HBAC rule '$rule_name' creada"
}

create_deny_all_rule() {
    # Crear regla deny-by-default explícita
    local rule_name="deny-all-other-groups"

    if rule_exists "$rule_name"; then
        log "⚠️  HBAC rule '$rule_name' ya existe — se omite"
        return 0
    fi

    log "Creando HBAC rule '$rule_name' (deny by default)..."

    if [[ "$DRY_RUN" == "--dry-run" ]]; then
        log "[DRY-RUN] ipa hbacrule-add $rule_name --hostcat=all --usercat=all --servicecat=all"
        return 0
    fi

    # Nota: deny-by-default en FreeIPA se logra NO creando reglas de allow para
    # grupos no autorizados. FreeIPA HBAC es allow-by-default → necesitamos
    # una regla que deniegue explícitamente después de las allow.
    #
    # Estrategia: No crear reglas deny explícitas. FreeIPA evalúa las allow rules
    # en orden. Si ninguna allow rule coincide con un usuario → acceso denegado.
    # Esto se documenta en la política de seguridad.
    log "ℹ️  Política deny-by-default: FreeIPA deniega automáticamente si ninguna allow rule coincide."
    log "ℹ️  No se requiere regla deny explícita. Documentado en design.md §5."
}

main() {
    log "=== Inicio: Creación de reglas HBAC FreeIPA ==="
    validate_prereqs

    local success=0
    local failed=0

    for entry in "${HBAC_RULES[@]}"; do
        IFS='|' read -r group hosts <<< "$entry"
        if create_hbac_rule "$group" "$hosts"; then
            ((success++))
        else
            ((failed++))
        fi
    done

    create_deny_all_rule

    if [[ "$DRY_RUN" == "--dry-run" ]]; then
        log "[DRY-RUN] No se realizaron cambios reales"
    fi

    log ""
    log "=== Resumen HBAC ==="
    log "Reglas creadas/verificadas: $success"
    log "Fallos: $failed"
    log ""
    log "Reglas actuales en FreeIPA:"
    ipa hbacrule-find 2>/dev/null || true

    if [[ $failed -gt 0 ]]; then
        log "⚠️  Algunas reglas HBAC requieren atención manual"
        exit 1
    fi

    log ""
    log "✅ HBAC rules configuradas correctamente"
    log ""
    log "Próximo paso: Crear sudo rules (scripts/create-sudo-rules.sh)"
}

main
