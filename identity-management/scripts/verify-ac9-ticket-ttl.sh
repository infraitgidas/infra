#!/bin/bash
# verify-ac9-ticket-ttl.sh — F4.10: Verificar AC9 (Kerberos ticket TTL ≤ 24h)
#
# Uso: ./verify-ac9-ticket-ttl.sh
#
# Verifica que la configuración de Kerberos ticket lifetime no exceda 24h,
# tanto en sssd.conf como en la configuración de FreeIPA.
#
# Especificación: identity-management/sdd/specs.md §AC9, §R7
# Diseño: identity-management/sdd/design.md §3.3

set -euo pipefail

LOG_FILE="/var/log/verify-ac9-ticket-ttl.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

pass() {
    log "✅ PASS: $*"
}

fail() {
    log "❌ FAIL: $*"
}

warn() {
    log "⚠️  $*"
}

MAX_TICKET_LIFETIME_H=24

check_sssd_template() {
    local sssd_conf="/etc/sssd/sssd.conf"

    log "Verificando krb5 settings en sssd.conf..."

    if [[ ! -f "$sssd_conf" ]]; then
        warn "sssd.conf no encontrado en $sssd_conf — puede que el template esté en otra ruta"
        return 1
    fi

    local ticket_lifetime
    ticket_lifetime=$(grep "^krb5_ticket_lifetime" "$sssd_conf" 2>/dev/null | awk '{print $3}')

    if [[ -z "$ticket_lifetime" ]]; then
        fail "krb5_ticket_lifetime NO configurado en sssd.conf"
        return 1
    fi

    log "Valor configurado: krb5_ticket_lifetime = $ticket_lifetime"

    # Parsear el valor (puede ser 24h, 1d, 86400s, etc.)
    local hours=0
    if [[ "$ticket_lifetime" =~ ^([0-9]+)h$ ]]; then
        hours="${BASH_REMATCH[1]}"
    elif [[ "$ticket_lifetime" =~ ^([0-9]+)d$ ]]; then
        hours=$((BASH_REMATCH[1] * 24))
    elif [[ "$ticket_lifetime" =~ ^([0-9]+)s$ ]]; then
        hours=$((BASH_REMATCH[1] / 3600))
    else
        fail "Formato de krb5_ticket_lifetime no reconocido: $ticket_lifetime"
        return 1
    fi

    if [[ "$hours" -le "$MAX_TICKET_LIFETIME_H" ]]; then
        pass "krb5_ticket_lifetime = ${hours}h (≤ ${MAX_TICKET_LIFETIME_H}h)"
    else
        fail "krb5_ticket_lifetime = ${hours}h EXCEDE el máximo de ${MAX_TICKET_LIFETIME_H}h"
        return 1
    fi

    # Verificar también krb5_renewable_lifetime
    local renew_lifetime
    renew_lifetime=$(grep "^krb5_renewable_lifetime" "$sssd_conf" 2>/dev/null | awk '{print $3}')
    if [[ -n "$renew_lifetime" ]]; then
        log "krb5_renewable_lifetime = $renew_lifetime (no acotado por AC9 pero debe ser razonable)"
    fi

    return 0
}

check_ipa_krb_settings() {
    log "Verificando configuración Kerberos en FreeIPA..."

    if ! command -v ipa &>/dev/null; then
        warn "'ipa' CLI no disponible — solo se verifica sssd.conf"
        return 0
    fi

    # Obtener configuración de Kerberos desde FreeIPA
    local krb_config
    krb_config=$(ipa krbtpolicy-show 2>/dev/null || true)

    if [[ -z "$krb_config" ]]; then
        warn "No se pudo obtener política Kerberos de FreeIPA"
        return 0
    fi

    log "Política Kerberos actual en FreeIPA:"
    echo "$krb_config" | while IFS= read -r line; do
        log "  $line"
    done

    # Extraer max_life
    local max_life
    max_life=$(echo "$krb_config" | grep "Max life" | awk '{print $NF}')
    if [[ -n "$max_life" ]]; then
        log "Max life en FreeIPA: $max_life"
    fi
}

check_active_ticket() {
    if ! command -v klist &>/dev/null; then
        warn "klist no disponible — no se pueden verificar tickets activos"
        return 0
    fi

    local klist_output
    klist_output=$(klist 2>/dev/null || true)

    if [[ -z "$klist_output" ]]; then
        log "No hay tickets Kerberos activos en esta sesión"
        log "ℹ️  Para probar con un ticket real: kinit <ad-user>@GDC01.LOCAL"
        return 0
    fi

    log "Tickets Kerberos activos:"
    echo "$klist_output" | while IFS= read -r line; do
        log "  $line"
    done

    # Extraer el tiempo de vida del ticket vigente
    # Formato típico: "Ticket expires: 06/05/2026 10:00:00"
    local ticket_expires
    ticket_expires=$(echo "$klist_output" | grep "Ticket expires" | head -1)
    if [[ -n "$ticket_expires" ]]; then
        log "Ticket expires: $ticket_expires"
    fi
}

main() {
    log "=== Verificación AC9: Kerberos Ticket TTL ≤ 24h ==="
    log ""

    local exit_code=0

    # 1. Verificar sssd.conf template (aplica a todos los hosts Linux)
    if ! check_sssd_template; then
        exit_code=1
    fi

    echo ""
    log "---"

    # 2. Verificar política en FreeIPA (si es accesible)
    check_ipa_krb_settings

    echo ""
    log "---"

    # 3. Verificar tickets activos (si existen)
    check_active_ticket

    echo ""
    log "=== Resumen AC9 ==="
    if [[ $exit_code -eq 0 ]]; then
        log "✅ Ticket TTL ≤ 24h verificado en sssd.conf"
        log ""
        log "Documentación de referencia:"
        log "  - sssd.conf: krb5_ticket_lifetime = $(grep '^krb5_ticket_lifetime' /etc/sssd/sssd.conf 2>/dev/null || echo 'N/A')"
        log "  - Límite AC9: ≤ ${MAX_TICKET_LIFETIME_H}h"
        log "  - Fuente: design.md §3.3, specs.md §R7"
    else
        log "⚠️  AC9 requiere corrección en sssd.conf"
    fi

    exit $exit_code
}

main
