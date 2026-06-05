#!/bin/bash
# verify-ac6-offline-cache.sh — F4.9: Verificar AC6 (offline cache ≥ 8h)
#
# Uso: ./verify-ac6-offline-cache.sh [--destructive]
#
# ADVERTENCIA: Por defecto es NO DESTRUCTIVO. Solo verifica la configuración
# de cache SSSD sin desconectar AD realmente.
#
# Modo --destructive:
#   IGNORA esta opción — NO se debe ejecutar en producción sin autorización.
#   El procedimiento real de verificación requiere cortar tráfico a AD y
#   probar login con cache. Ver el archivo docs/identity/offline-cache-test.md
#   para el procedimiento paso a paso.
#
# Especificación: identity-management/sdd/specs.md §AC6, §R4, §S5
# Diseño: identity-management/sdd/design.md §3.3

set -euo pipefail

LOG_FILE="/var/log/verify-ac6-offline-cache.log"

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

check_sssd_config() {
    local sssd_conf="/etc/sssd/sssd.conf"

    if [[ ! -f "$sssd_conf" ]]; then
        fail "No se encontró $sssd_conf"
        return 1
    fi

    log "Verificando configuración SSSD en $sssd_conf..."

    # Verificar cache_credentials = True
    if grep -q "^cache_credentials\s*=\s*True" "$sssd_conf"; then
        pass "cache_credentials = True"
    else
        fail "cache_credentials no está configurado como True"
    fi

    # Verificar offline_credentials_expiration ≥ 8
    local offline_expire
    offline_expire=$(grep "^offline_credentials_expiration" "$sssd_conf" | awk '{print $3}')
    if [[ -n "$offline_expire" ]] && [[ "$offline_expire" -ge 8 ]]; then
        pass "offline_credentials_expiration = $offline_expire h (≥ 8 h)"
    else
        fail "offline_credentials_expiration = ${offline_expire:-NO CONFIGURADO} (debe ser ≥ 8)"
    fi

    # Verificar entry_cache_timeout
    local cache_timeout
    cache_timeout=$(grep "^entry_cache_timeout" "$sssd_conf" | awk '{print $3}')
    if [[ -n "$cache_timeout" ]]; then
        pass "entry_cache_timeout = $cache_timeout s"
    else
        warn "entry_cache_timeout no configurado — se usará default 5400 s"
    fi
}

check_sssd_running() {
    if systemctl is-active sssd &>/dev/null; then
        pass "SSSD service está activo"
        return 0
    fi

    fail "SSSD service NO está corriendo"
    return 1
}

check_cache_exists() {
    log "Verificando que existan usuarios cacheados en SSSD..."

    # sss_cache puede listar estadísticas de cache
    if command -v sssctl &>/dev/null; then
        local cache_stats
        cache_stats=$(sssctl cache-stats 2>/dev/null || true)
        if echo "$cache_stats" | grep -q "Users"; then
            pass "Cache SSSD contiene usuarios:"
            log "$cache_stats"
        else
            warn "Cache SSSD parece vacío o no se pudieron leer estadísticas"
            log "ℹ️  Es normal si ningún usuario AD ha hecho login aún en este host"
        fi
    else
        warn "sssctl no disponible — no se puede leer estadísticas de cache"
    fi
}

show_procedure() {
    echo ""
    log "=== Procedimiento de Verificación Destructiva ==="
    log ""
    log "Para verificar AC6 completamente (cache ≥ 8h), siga estos pasos:"
    log ""
    log "PASO 1: Asegurar que un usuario AD haya hecho login previamente"
    log "  ssh $USER@localhost"
    log "  # Login exitoso → SSSD cachea credenciales"
    log ""
    log "PASO 2: Programar la prueba en horario de mantenimiento"
    log "  El corte de AD afectará a todos los servicios que dependen de AD."
    log "  PVE realm AD sigue funcionando (autentica directo contra AD)."
    log ""
    log "PASO 3: Cortar tráfico a AD desde el host a probar"
    log "  iptables -A OUTPUT -d 192.168.1.117 -j DROP"
    log "  # Verificar: ping 192.168.1.117 → debe fallar"
    log ""
    log "PASO 4: Intentar login SSH con usuario AD (debe usar cache)"
    log "  ssh usuario-ad@localhost"
    log "  # Debe ser exitoso si cache está funcionando"
    log ""
    log "PASO 5: Restaurar conectividad"
    log "  iptables -D OUTPUT -d 192.168.1.117 -j DROP"
    log ""
    log "PASO 6: Verificar timeout de cache"
    log "  El valor offline_credentials_expiration controla cuánto tiempo"
    log "  (en horas) se mantienen las credenciales cacheadas."
    log "  Configurado actualmente en: ${offline_expire:-8}h"
    log "  Para probar el límite exacto, esperar las horas configuradas + 1."
}

main() {
    log "=== Verificación AC6: SSSD Offline Cache ≥ 8h ==="
    log "Modo: NO DESTRUCTIVO (solo verificación de configuración)"
    log ""

    # Verificar que estamos en un host Linux, no en PVE
    if command -v pveversion &>/dev/null; then
        warn "Este script se ejecuta en un nodo PVE — SSSD usa provider AD para PVE realm"
        log "La verificación offline debe hacerse en containers Linux con SSSD→IPA"
    fi

    check_sssd_running || true
    echo ""
    check_sssd_config || true
    echo ""
    check_cache_exists || true
    echo ""

    show_procedure

    echo ""
    log "=== Resumen AC6 ==="
    log ""
    log "Configuración SSSD: $(systemctl is-active sssd 2>/dev/null || echo 'inactivo')"
    log "Cache credentials: $(grep '^cache_credentials' /etc/sssd/sssd.conf 2>/dev/null || echo 'no configurado')"
    log "Offline expiration: $(grep '^offline_credentials_expiration' /etc/sssd/sssd.conf 2>/dev/null || echo 'no configurado')"
    log ""
    log "La verificación destructiva requiere planificación (PASO 2 del procedimiento)."
    log "Documentación completa: docs/identity/offline-cache-test.md"
}

main
