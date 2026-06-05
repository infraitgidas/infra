#!/bin/bash
# verify-ac10-backups.sh — F5.5: Verificar AC10 (backups funcionales)
#
# Uso:
#   ./verify-ac10-backups.sh              # Verificar backups FreeIPA + AD
#   ./verify-ac10-backups.sh --freeipa    # Solo FreeIPA
#   ./verify-ac10-backups.sh --ad         # Solo AD
#
# Verifica que ambos sistemas de backup estén configurados y funcionales:
#   1. FreeIPA: ipa-backup --online (backup de datos IPA)
#   2. AD: Windows Server Backup + snapshot PVE
#
# Especificación: identity-management/sdd/specs.md §AC10, §R10
# Diseño: identity-management/sdd/design.md §8

set -euo pipefail

LOG_FILE="/var/log/verify-ac10-backups.log"
AD_HOST="192.168.1.117"
FREEIPA_BACKUP_DIR="/var/lib/ipa/backup"
MODE="${1:-all}"

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

check_freeipa_backup() {
    log "--- Verificando backup FreeIPA ---"

    if [[ ! -d "$FREEIPA_BACKUP_DIR" ]]; then
        warn "Directorio de backup FreeIPA no encontrado: $FREEIPA_BACKUP_DIR"
        log "  ¿Es este el servidor FreeIPA?"
        return 1
    fi

    # Verificar que ipa-backup está disponible
    if ! command -v ipa-backup &>/dev/null; then
        fail "ipa-backup no está disponible en este host"
        return 1
    fi

    # Verificar backups existentes
    local backups
    backups=$(find "$FREEIPA_BACKUP_DIR" -name "ipa-*.tar.gz" -type f 2>/dev/null | sort -r)

    if [[ -z "$backups" ]]; then
        warn "No se encontraron backups FreeIPA previos"
        log "  Ejecutar: ipa-backup --online --data"
        has_freeipa_backup=1
    else
        pass "Backups FreeIPA encontrados:"
        echo "$backups" | head -5 | while IFS= read -r f; do
            local size
            size=$(du -h "$f" 2>/dev/null | cut -f1)
            local date_str
            date_str=$(stat -c '%y' "$f" 2>/dev/null | cut -d. -f1)
            log "  $date_str  $size  $(basename "$f")"
        done

        local count
        count=$(echo "$backups" | wc -l)
        if [[ $count -gt 0 ]]; then
            pass "Total: $count backup(s) disponible(s)"
            # Verificar que el más reciente no esté corrupto
            local latest
            latest=$(echo "$backups" | head -1)
            if tar -tzf "$latest" &>/dev/null; then
                pass "Backup más reciente válido (verificación de integridad)"
            else
                fail "Backup más reciente parece corrupto (tar -t falló): $latest"
            fi
        fi
    fi

    # Verificar cron job
    local cron_job
    cron_job=$(crontab -l 2>/dev/null | grep "ipa-backup-cron" || true)
    if [[ -n "$cron_job" ]]; then
        pass "Cron job para backup FreeIPA configurado:"
        log "  $cron_job"
    else
        warn "No hay cron job configurado para ipa-backup-cron.sh"
        log "  Agregar: 0 2 * * * /usr/local/bin/ipa-backup-cron.sh"
    fi

    echo ""
    return 0
}

check_ad_backup() {
    log "--- Verificando backup AD (DC1-GIDAS) ---"

    # Verificar conectividad SSH
    if ! ping -c 1 -W 2 "$AD_HOST" &>/dev/null; then
        warn "AD host $AD_HOST no responde ping — ¿está encendido?"
        log "  La verificación AD backup requiere conectividad"
        has_ad_backup=1
        return 1
    fi

    log "Conectividad AD verificada (ping OK)"

    # Verificar wbadmin via SSH
    local wbadmin_output
    wbadmin_output=$(ssh -o BatchMode=yes -o ConnectTimeout=5 \
        "Administrator@$AD_HOST" "wbadmin get versions" 2>&1 || true)

    if echo "$wbadmin_output" | grep -qi "no backups\|no versions\|WBADMIN NOT FOUND\|command not found"; then
        warn "No se detectaron backups AD o wbadmin no está disponible"
        log "  Output: $wbadmin_output"
        has_ad_backup=1
    elif echo "$wbadmin_output" | grep -qi "version\|backup"; then
        pass "Backup AD detectado (wbadmin get versions exitoso)"
        has_ad_backup=0
    else
        warn "No se pudo determinar estado de backup AD"
        log "  Output: $wbadmin_output"
        has_ad_backup=1
    fi

    # Intentar verificar PVE snapshot via pct
    if command -v qm &>/dev/null; then
        log "Verificando snapshots PVE..."
        for vmid in 101 102; do
            local snapshots
            snapshots=$(qm listsnapshot "$vmid" 2>/dev/null | grep -v "current" || true)
            if [[ -n "$snapshots" ]]; then
                log "  VM $vmid: snapshots encontrados"
            else
                log "  VM $vmid: sin snapshots (no crítico — PVE vzdump puede estar configurado aparte)"
            fi
        done
    else
        warn "qm no disponible — no se pueden verificar snapshots PVE desde este host"
        log "  Ejecutar verificación desde pve-ad"
    fi

    echo ""
    return 0
}

check_backup_scripts() {
    log "--- Verificando scripts de backup ---"

    # FreeIPA backup script
    if [[ -x /usr/local/bin/ipa-backup-cron.sh ]]; then
        pass "Script FreeIPA backup: /usr/local/bin/ipa-backup-cron.sh"
    else
        warn "Script FreeIPA backup no encontrado o no ejecutable"
        log "  Instalar desde: identity-management/scripts/ipa-backup-cron.sh"
    fi

    echo ""
}

show_summary_table() {
    log ""
    log "=== Resumen AC10: Estado de Backups ==="
    log ""
    log "Componente       | Estado       | Fuente"
    log "-----------------|--------------|-----------------------------"
    if [[ -z "${has_freeipa_backup:-}" ]]; then
        log "FreeIPA backup   | ✅ Configurado | ipa-backup --online --data"
    else
        log "FreeIPA backup   | ⚠️  Pendiente   | Ejecutar ipa-backup --online"
    fi
    if [[ -z "${has_ad_backup:-}" ]]; then
        log "AD backup        | ❓ No verificado | Verificar en DC1-GIDAS"
    elif [[ "$has_ad_backup" -eq 0 ]]; then
        log "AD backup        | ✅ Detectado   | wbadmin en DC1-GIDAS"
    else
        log "AD backup        | ⚠️  Pendiente   | Configurar wbadmin"
    fi
    if command -v qm &>/dev/null; then
        log "PVE snapshots    | ⚠️  Manual       | qm snapshot en pve-ad"
    fi
    log ""
    log "Especificación: specs.md §AC10"
    log "Diseño: design.md §8"
}

main() {
    log "=== Verificación AC10: Backups Funcionales ==="
    log "Modo: $MODE"
    log ""

    local has_freeipa_backup=""
    local has_ad_backup=""

    # FreeIPA backup check
    if [[ "$MODE" == "all" ]] || [[ "$MODE" == "--freeipa" ]]; then
        check_freeipa_backup || true
        has_freeipa_backup=${has_freeipa_backup:-0}
    fi

    # AD backup check
    if [[ "$MODE" == "all" ]] || [[ "$MODE" == "--ad" ]]; then
        check_ad_backup || true
    fi

    # Scripts check
    if [[ "$MODE" == "all" ]]; then
        check_backup_scripts || true
    fi

    show_summary_table

    log ""
    log "=== Verificación AC10 completada ==="
}

main
