#!/bin/bash
# verify-ac5-hbac-enforcement.sh — F4.8: Verificar AC5 (HBAC enforcement)
#
# Uso: ./verify-ac5-hbac-enforcement.sh
#
# Verifica que un usuario de un grupo restringido NO pueda acceder via SSH
# a un host no permitido por las reglas HBAC de FreeIPA.
#
# Prueba principal:
#   Usuario de G-Becarios → SSH a sg-rojo → debe ser DENEGADO
#
# Prueba secundaria:
#   Usuario de G-Direccion → SSH a sg-rojo → debe ser PERMITIDO
#
# Especificación: identity-management/sdd/specs.md §AC5, §S4
# Diseño: identity-management/sdd/design.md §5

set -euo pipefail

LOG_FILE="/var/log/verify-ac5-hbac.log"
TEST_USER="rcaceresp"       # Rafael Cáceres Petckowicz — G-Becarios
ALLOWED_USER="lnahuel"       # Leopoldo Nahuel — G-Direccion (acceso a todo)
RESTRICTED_HOST="sg-rojo.gdc01.local"
SSH_TIMEOUT=10

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

pass() {
    log "✅ PASS: $*"
}

fail() {
    log "❌ FAIL: $*"
}

check_host_reachable() {
    local host="$1"
    if ping -c 1 -W 2 "$host" &>/dev/null; then
        return 0
    fi
    return 1
}

test_hbac_deny() {
    local user="$1"
    local host="$2"
    local expected="$3"  # "deny" o "allow"

    log "Probando: $user → $host (esperado: $expected)..."

    # Intentar SSH con BatchMode (no interactivo) y ConnectTimeout
    # Debe fallar con "Access denied" si HBAC bloquea, o conectar si permite
    local ssh_output
    ssh_output=$(ssh -o BatchMode=yes -o ConnectTimeout="$SSH_TIMEOUT" \
        -o StrictHostKeyChecking=no \
        "$user@$host" "echo AUTH_OK" 2>&1 || true)

    if [[ "$expected" == "deny" ]]; then
        if echo "$ssh_output" | grep -qi "access denied\|permission denied\|authentication failed"; then
            pass "HBAC denegó acceso a $user → $host (esperado)"
            return 0
        elif echo "$ssh_output" | grep -q "AUTH_OK"; then
            fail "HBAC DEBIÓ denegar pero PERMITIÓ acceso a $user → $host"
            return 1
        else
            log "ℹ️  Output SSH: $ssh_output"
            fail "No se pudo determinar resultado (posible error de red o config)"
            return 1
        fi
    else
        if echo "$ssh_output" | grep -q "AUTH_OK"; then
            pass "Acceso permitido a $user → $host (esperado)"
            return 0
        elif echo "$ssh_output" | grep -qi "access denied\|permission denied"; then
            fail "HBAC DEBIÓ permitir pero DENEGÓ acceso a $user → $host"
            return 1
        else
            log "ℹ️  Output SSH: $ssh_output"
            fail "No se pudo determinar resultado"
            return 1
        fi
    fi
}

main() {
    log "=== Verificación AC5: HBAC Enforcement ==="
    log "Host FreeIPA: ipa-gidas.gdc01.local (192.168.1.118)"
    log ""
    log "Escenario S4: Usuario G-Becarios SSH a sg-rojo → debe fallar"
    log ""

    # Verificar prerequisitos
    if ! command -v ssh &>/dev/null; then
        fail "Comando 'ssh' no encontrado"
        exit 1
    fi

    # Verificar reachabilidad de hosts
    if ! check_host_reachable "$RESTRICTED_HOST"; then
        fail "Host $RESTRICTED_HOST no es reachable — abortando verificación HBAC"
        log "ℹ️  Esto puede ser normal si el host está apagado. Verificar manualmente."
        exit 1
    fi

    local exit_code=0

    # Prueba 1: G-Becarios → sg-rojo → DENY (esperado)
    echo ""
    log "--- Prueba 1: G-Becarios → sg-rojo (debe denegar) ---"
    if ! test_hbac_deny "$TEST_USER" "$RESTRICTED_HOST" "deny"; then
        exit_code=1
    fi

    # Prueba 2: G-Direccion → sg-rojo → ALLOW (esperado)
    echo ""
    log "--- Prueba 2: G-Direccion → sg-rojo (debe permitir) ---"
    if ! test_hbac_deny "$ALLOWED_USER" "$RESTRICTED_HOST" "allow"; then
        exit_code=1
    fi

    echo ""
    log "=== Resumen AC5 ==="
    if [[ $exit_code -eq 0 ]]; then
        log "✅ HBAC enforcement verificado correctamente"
    else
        log "⚠️  AC5 tiene fallos — revisar reglas HBAC en FreeIPA"
        log "  Comando: ipa hbacrule-find"
    fi

    exit $exit_code
}

main
