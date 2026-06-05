#!/bin/bash
# verify-ac7-secrets.sh — F5.4: Verificar AC7 (secrets encriptados con SOPS)
#
# Uso: ./verify-ac7-secrets.sh
#
# Verifica que secrets/proxmox.yaml existe y está correctamente encriptado
# con SOPS (Mozilla SOPS), y que se puede desencriptar correctamente.
#
# Especificación: identity-management/sdd/specs.md §AC7, §R7
# Diseño: identity-management/sdd/design.md §8

set -euo pipefail

LOG_FILE="/var/log/verify-ac7-secrets.log"
REPO_DIR="/home/infra/infra"
SECRETS_FILE="$REPO_DIR/secrets/proxmox.yaml"

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

check_sops_installed() {
    if command -v sops &>/dev/null; then
        pass "SOPS CLI disponible ($(sops --version 2>&1 | head -1))"
        return 0
    fi

    # Verificar alternativa: sops via go, pip, etc.
    if [[ -f /usr/local/bin/sops ]]; then
        pass "SOPS encontrado en /usr/local/bin/sops"
        return 0
    fi

    fail "SOPS no está instalado"
    log "  Instalar: https://github.com/getsops/sops/releases"
    return 1
}

check_secrets_exist() {
    if [[ -f "$SECRETS_FILE" ]]; then
        pass "Archivo $SECRETS_FILE existe"
        ls -la "$SECRETS_FILE" >> "$LOG_FILE"

        # Verificar permisos — debe ser 600 o 400
        local perms
        perms=$(stat -c "%a" "$SECRETS_FILE" 2>/dev/null || echo "unknown")
        if [[ "$perms" == "600" ]] || [[ "$perms" == "400" ]]; then
            pass "Permisos: $perms (seguro)"
        else
            warn "Permisos: $perms (se recomienda 600)"
        fi

        return 0
    fi

    fail "Archivo $SECRETS_FILE NO existe"
    log "  Crear: sops $SECRETS_FILE"
    return 1
}

check_sops_encryption() {
    log "Verificando encriptación SOPS..."

    # Método 1: sops filestamp (más confiable)
    if head -5 "$SECRETS_FILE" 2>/dev/null | grep -q "sops"; then
        pass "Archivo tiene cabecera SOPS (encriptado)"
    else
        fail "Archivo NO parece estar encriptado con SOPS (sin cabecera sops)"
        return 1
    fi

    # Método 2: Intentar decript
    log "Intentando desencriptar con sops..."
    if sops -d "$SECRETS_FILE" > /dev/null 2>&1; then
        pass "sops -d exitoso — archivo correctamente encriptado"
        # Verificar que contiene campos esperados
        local decrypted
        decrypted=$(sops -d "$SECRETS_FILE" 2>/dev/null || true)
        if echo "$decrypted" | grep -qi "password\|secret\|admin\|credential"; then
            pass "Secrets contienen campos de credenciales esperados"
        else
            warn "No se detectaron campos de credenciales típicos en secrets"
            log "  Contenido (ocultando valores):"
            echo "$decrypted" | sed 's/: .*/: ***/' >> "$LOG_FILE"
        fi
    else
        fail "sops -d FALLÓ — archivo corrupto o clave de encriptación no disponible"
        log "  Posibles causas:"
        log "  - Clave GPG/Age no disponible en este host"
        log "  - Archivo dañado"
        log "  - Formato no compatible"
        return 1
    fi
}

check_git_tracked() {
    if [[ ! -d "$REPO_DIR/.git" ]]; then
        warn "No es un repo git — no se puede verificar seguimiento"
        return 0
    fi

    local rel_path
    rel_path=$(realpath --relative-to="$REPO_DIR" "$SECRETS_FILE" 2>/dev/null || echo "")

    if git -C "$REPO_DIR" ls-files --error-unmatch "$rel_path" &>/dev/null; then
        pass "Archivo está versionado en git"
    else
        warn "Archivo NO está versionado en git — debería agregarse"
    fi
}

main() {
    log "=== Verificación AC7: Secrets encriptados con SOPS ==="
    log "Secrets file: $SECRETS_FILE"
    log ""

    local exit_code=0

    # 1. Verificar SOPS CLI
    if ! check_sops_installed; then
        log "SOPS no disponible — no se puede verificar encriptación"
        exit_code=1
    else
        echo ""
        # 2. Verificar que el archivo existe
        if check_secrets_exist; then
            echo ""
            # 3. Verificar encriptación
            if ! check_sops_encryption; then
                exit_code=1
            fi
            echo ""
            # 4. Verificar git tracking
            check_git_tracked
        else
            exit_code=1
        fi
    fi

    echo ""
    log "=== Resumen AC7 ==="
    if [[ $exit_code -eq 0 ]]; then
        log "✅ AC7: Secrets correctamente encriptados con SOPS"
        log ""
        log "Resumen:"
        log "  - Archivo: $SECRETS_FILE"
        log "  - Encriptación: SOPS (verificada)"
        log "  - Longitud: $(wc -c < "$SECRETS_FILE" 2>/dev/null || echo 0) bytes"
        log "  - Git: $(git -C "$REPO_DIR" ls-files --error-unmatch secrets/proxmox.yaml &>/dev/null && echo sí || echo 'no (requiere git add)')"
    else
        log "⚠️  AC7 requiere acción correctiva"
    fi

    exit $exit_code
}

main
