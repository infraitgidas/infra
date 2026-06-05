#!/bin/bash
# ipa-backup-cron.sh — F5.1: Backup automático de FreeIPA
#
# Ubicación objetivo: /usr/local/bin/ipa-backup-cron.sh
#
# Realiza backup online de FreeIPA con retención de 7 días.
# Diseñado para ejecutarse diariamente via cron.
#
# Uso:
#   /usr/local/bin/ipa-backup-cron.sh           # Ejecución normal
#   /usr/local/bin/ipa-backup-cron.sh --force    # Forzar backup aunque exista uno reciente
#   /usr/local/bin/ipa-backup-cron.sh --dry-run  # Solo mostrar qué haría
#
# Instalación en cron (como root en FreeIPA server):
#   crontab -e
#   0 2 * * * /usr/local/bin/ipa-backup-cron.sh >> /var/log/ipa-backup-cron.log 2>&1
#
# Diseño: identity-management/sdd/design.md §8

set -euo pipefail

BACKUP_DIR="/var/lib/ipa/backup"
RETENTION_DAYS=7
LOG_FILE="/var/log/ipa-backup-cron.log"
LOCK_FILE="/var/run/ipa-backup-cron.lock"
MIN_INTERVAL_HOURS=23  # Evitar backups duplicados en < 23h

MODE="${1:-normal}"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

error() {
    log "ERROR: $*"
}

cleanup() {
    rm -f "$LOCK_FILE"
}
trap cleanup EXIT

# Prevenir ejecución simultánea
check_lock() {
    if [[ -f "$LOCK_FILE" ]]; then
        local lock_age
        lock_age=$(($(date +%s) - $(stat -c %Y "$LOCK_FILE" 2>/dev/null || echo 0)))
        if [[ $lock_age -lt 3600 ]]; then  # Lock más de 1h → stale
            error "Ya hay un backup en ejecución (lock: $LOCK_FILE, age: ${lock_age}s)"
            exit 1
        else
            log "Lock stale detectado (age: ${lock_age}s) — removiendo y continuando"
            rm -f "$LOCK_FILE"
        fi
    fi
    touch "$LOCK_FILE"
}

check_prereqs() {
    if [[ ! -d "$BACKUP_DIR" ]]; then
        mkdir -p "$BACKUP_DIR"
        log "Directorio $BACKUP_DIR creado"
    fi

    if ! command -v ipa-backup &>/dev/null; then
        error "ipa-backup no encontrado — ¿es este un servidor FreeIPA?"
        exit 1
    fi
}

check_recent_backup() {
    if [[ "$MODE" == "--force" ]]; then
        return 1  # Forzar backup
    fi

    # Buscar backup más reciente
    local latest
    latest=$(find "$BACKUP_DIR" -name "ipa-*.tar.gz" -type f 2>/dev/null | sort -r | head -1)

    if [[ -z "$latest" ]]; then
        return 1  # No hay backups previos
    fi

    local latest_time
    latest_time=$(stat -c %Y "$latest" 2>/dev/null || echo 0)
    local now
    now=$(date +%s)
    local age_hours=$(( (now - latest_time) / 3600 ))

    if [[ $age_hours -lt $MIN_INTERVAL_HOURS ]]; then
        log "Backup reciente encontrado: $(basename "$latest") (${age_hours}h atrás, mínimo ${MIN_INTERVAL_HOURS}h)"
        log "Saltando backup de hoy. Use --force para forzar."
        return 0  # Backup reciente existe → no hacer
    fi

    return 1  # Backup antiguo → hacer nuevo
}

run_backup() {
    log "Iniciando ipa-backup --online --data..."

    if [[ "$MODE" == "--dry-run" ]]; then
        log "[DRY-RUN] ipa-backup --online --data"
        log "[DRY-RUN] Backup simulado — no se realizaron cambios"
        return 0
    fi

    local start_time
    start_time=$(date +%s)

    if ipa-backup --online --data; then
        local end_time
        end_time=$(date +%s)
        local duration=$((end_time - start_time))
        log "✅ Backup completado en ${duration}s"
    else
        error "Falló ipa-backup --online --data"
        return 1
    fi
}

cleanup_old_backups() {
    if [[ "$MODE" == "--dry-run" ]]; then
        log "[DRY-RUN] Limpiaría backups más antiguos que ${RETENTION_DAYS} días:"
        find "$BACKUP_DIR" -name "ipa-*.tar.gz" -mtime +$RETENTION_DAYS -print 2>/dev/null \
            | while IFS= read -r f; do
                log "[DRY-RUN]   Eliminaría: $f"
            done
        return 0
    fi

    log "Limpiando backups más antiguos que $RETENTION_DAYS días..."
    local count=0
    find "$BACKUP_DIR" -name "ipa-*.tar.gz" -mtime +$RETENTION_DAYS -delete 2>/dev/null \
        && count=$(find "$BACKUP_DIR" -name "ipa-*.tar.gz" -mtime +$RETENTION_DAYS 2>/dev/null | wc -l)

    log "Backups eliminados: $count"
}

list_backups() {
    log "Backups actuales en $BACKUP_DIR:"
    find "$BACKUP_DIR" -name "ipa-*.tar.gz" -type f 2>/dev/null | sort | while IFS= read -r f; do
        local size
        size=$(du -h "$f" | cut -f1)
        local date_str
        date_str=$(stat -c '%y' "$f" 2>/dev/null | cut -d. -f1)
        log "  $date_str  $size  $(basename "$f")"
    done
}

main() {
    log "=== ipa-backup-cron.sh ==="
    log "Modo: $MODE"
    log "Backup dir: $BACKUP_DIR"
    log "Retención: $RETENTION_DAYS días"
    log ""

    check_lock
    check_prereqs

    # Verificar si ya hay backup reciente
    if check_recent_backup; then
        # Hay backup reciente — solo limpiar y mostrar
        cleanup_old_backups
        echo ""
        list_backups
        log "=== Completado (sin nuevo backup) ==="
        exit 0
    fi

    # Ejecutar backup
    if ! run_backup; then
        error "Backup falló — revisar /var/log/ipa-backup.log"
        exit 1
    fi

    echo ""
    cleanup_old_backups

    echo ""
    list_backups

    log "=== Backup completado exitosamente ==="
}

main
