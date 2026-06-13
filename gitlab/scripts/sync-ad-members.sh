#!/bin/bash
# ================================================================
# sync-ad-members.sh — AD → GitLab Group Member Sync
# ================================================================
# Sincroniza miembros de grupos AD con grupos de GitLab.
#
# Lógica de mapping (refleja identity-management/docs/identity/estructura-grupos-apps.md):
#   G-Direccion           → Owner en TODOS los grupos GitLab
#   G-Coordinadores ∩ PROY-X → Maintainer en grupo GitLab del proyecto X
#   G-Becarios     ∩ PROY-X → Developer  en grupo GitLab del proyecto X
#
# Dependencias: openldap-clients, curl, jq
#   dnf install openldap-clients curl jq
#
# Uso:
#   ./sync-ad-members.sh                    # Sync completo
#   ./sync-ad-members.sh --dry-run          # Solo mostrar cambios
#   ./sync-ad-members.sh --verbose          # Log detallado
#
# Cron (cada 15 minutos):
#   */15 * * * * /root/gitlab/scripts/sync-ad-members.sh
# ================================================================
set -euo pipefail

# ================================================================
# Configuración
# ================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GITLAB_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Source environment (AD LDAP creds + GitLab API token)
source "${GITLAB_DIR}/install/00-env.sh" 2>/dev/null || true

# --- Flags ---
DRY_RUN=false
VERBOSE=false

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=true ;;
        --verbose) VERBOSE=true ;;
    esac
done

# --- AD LDAP Settings ---
AD_HOST="${AD_HOST:-192.168.1.117}"
AD_PORT="${AD_PORT:-389}"
AD_BIND_DN="${AD_BIND_DN:-CN=infrait,OU=ServiceAccounts,DC=GDC01,DC=local}"
AD_BIND_PASS="${AD_BIND_PASS:-}"
AD_BASE_DN="${AD_BASE_DN:-DC=GDC01,DC=local}"
AD_GROUPS_DN="${AD_GROUPS_DN:-OU=Groups,DC=GDC01,DC=local}"

# --- GitLab API Settings ---
GITLAB_URL="${GITLAB_URL:-https://gitlab.gidas.local}"
GITLAB_API_TOKEN="${GITLAB_API_TOKEN:-}"

# --- GitLab Access Level mapping ---
# 10 => Guest, 20 => Reporter, 30 => Developer, 40 => Maintainer, 50 => Owner
ACCESS_OWNER=50
ACCESS_MAINTAINER=40
ACCESS_DEVELOPER=30

# --- Grupos GitLab (path → nombre) ---
declare -A GITLAB_GROUPS=(
    ["direccion"]="Dirección"
    ["administracion"]="Administración"
    ["capnee"]="CAPNEE"
    ["infrait"]="INFRAiT"
    ["telepark"]="TELEPARK"
    ["gmet"]="GMET"
    ["gis"]="GIS"
)

# --- Grupos AD de proyectos (PROY-* identifier → grupo GitLab) ---
declare -A PROY_GROUPS=(
    ["PROY-CAPNEE"]="capnee"
    ["PROY-INFRAiT"]="infrait"
    ["PROY-Telepark"]="telepark"
    ["PROY-GMET"]="gmet"
    ["PROY-GIS"]="gis"
)

# ================================================================
# Funciones auxiliares
# ================================================================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

verbose() {
    if [ "$VERBOSE" = true ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] $*" >&2
    fi
}

fail() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2
    exit 1
}

# ================================================================
# AD: Consultar miembros de grupo LDAP
# ================================================================

# Retorna lista de sAMAccountName (uno por línea) de un grupo AD
query_ad_group_members() {
    local group_cn="$1"
    local ldap_filter="(&(objectClass=group)(cn=${group_cn}))"

    ldapsearch -H "ldap://${AD_HOST}:${AD_PORT}" -x \
        -D "${AD_BIND_DN}" -w "${AD_BIND_PASS}" \
        -b "${AD_GROUPS_DN}" \
        -LLL "$ldap_filter" member 2>/dev/null | \
        grep '^member:' | sed 's/^member: //' | sort -u
}

# Retorna sAMAccountName dado un CN de un user en AD
get_sam_from_cn() {
    local cn="$1"
    ldapsearch -H "ldap://${AD_HOST}:${AD_PORT}" -x \
        -D "${AD_BIND_DN}" -w "${AD_BIND_PASS}" \
        -b "${AD_BASE_DN}" \
        -LLL "(&(objectClass=user)(cn=${cn}))" \
        sAMAccountName 2>/dev/null | \
        grep '^sAMAccountName:' | sed 's/^sAMAccountName: //' | head -1
}

# Retorna todos los sAMAccountName de un grupo AD
get_ad_group_sams() {
    local group_cn="$1"
    local sams=()

    while IFS= read -r dn; do
        [ -z "$dn" ] && continue
        local cn_part
        cn_part=$(echo "$dn" | grep -oP 'CN=[^,]+' | head -1 | sed 's/^CN=//')
        local sam
        sam=$(get_sam_from_cn "$cn_part")
        if [ -n "$sam" ]; then
            sams+=("$sam")
            verbose "  Miembro AD: ${sam} (${cn_part})"
        fi
    done < <(query_ad_group_members "$group_cn")

    echo "${sams[@]}"
}

# ================================================================
# GitLab API Helpers
# ================================================================

gitlab_api() {
    local method="$1" endpoint="$2" data="${3:-}"

    if [ "$DRY_RUN" = true ]; then
        echo "[DRY-RUN] curl -X ${method} ${GITLAB_URL}/api/v4${endpoint}"
        [ -n "$data" ] && echo "[DRY-RUN] data: ${data}"
        return
    fi

    curl -sfk --connect-timeout 10 \
        --header "PRIVATE-TOKEN: ${GITLAB_API_TOKEN}" \
        --header "Content-Type: application/json" \
        --request "${method}" \
        ${data:+--data "${data}"} \
        "${GITLAB_URL}/api/v4${endpoint}" 2>/dev/null || true
}

get_group_id() {
    local path="$1"
    gitlab_api GET "/groups?search=${path}" | \
        jq -r ".[] | select(.path == \"${path}\") | .id // empty" 2>/dev/null || echo ""
}

get_user_id() {
    local username="$1"
    gitlab_api GET "/users?username=${username}" | \
        jq -r '.[0].id // empty' 2>/dev/null || echo ""
}

add_group_member() {
    local gid="$1" uid="$2" level="$3" name="$4" username="$5"
    log "  Agregando ${username} (level ${level}) a ${name}"
    if [ "$DRY_RUN" = false ]; then
        gitlab_api POST "/groups/${gid}/members" \
            "{\"user_id\": ${uid}, \"access_level\": ${level}}" > /dev/null || \
        log "  ⚠️  Error agregando ${username} a ${name} (puede ya existir)"
    fi
}

# ================================================================
# Main
# ================================================================

main() {
    log "=== AD → GitLab Group Sync ==="
    log "AD: ${AD_HOST}:${AD_PORT}"
    log "GitLab: ${GITLAB_URL}"
    [ "$DRY_RUN" = true ] && log "*** MODO DRY-RUN — no se realizarán cambios ***"
    echo ""

    # --- Prerequisitos ---
    for cmd in ldapsearch curl jq; do
        if ! command -v "$cmd" &>/dev/null; then
            fail "Requerido: $cmd. Instalar con: dnf install openldap-clients curl jq"
        fi
    done
    if [ -z "$GITLAB_API_TOKEN" ]; then
        fail "GITLAB_API_TOKEN no configurado"
    fi
    if [ -z "$AD_BIND_PASS" ]; then
        fail "AD_BIND_PASS no configurado"
    fi
    verbose "Prerequisitos OK"

    # --- Obtener miembros de AD ---
    log "Consultando grupos en AD..."
    local direccion_sams=()
    while IFS= read -r m; do [ -n "$m" ] && direccion_sams+=("$m"); done < <(echo "$(get_ad_group_sams 'G-Direccion')" | tr ' ' '\n')
    log "  G-Direccion: ${direccion_sams[*]:-ninguno}"

    local coordinadores_sams=()
    while IFS= read -r m; do [ -n "$m" ] && coordinadores_sams+=("$m"); done < <(echo "$(get_ad_group_sams 'G-Coordinadores')" | tr ' ' '\n')
    log "  G-Coordinadores: ${coordinadores_sams[*]:-ninguno}"

    local becarios_sams=()
    while IFS= read -r m; do [ -n "$m" ] && becarios_sams+=("$m"); done < <(echo "$(get_ad_group_sams 'G-Becarios')" | tr ' ' '\n')
    log "  G-Becarios: ${becarios_sams[*]:-ninguno}"
    echo ""

    # --- Obtener IDs de usuarios GitLab ---
    log "Obteniendo IDs de usuarios GitLab..."
    declare -A USER_IDS
    for u in "${direccion_sams[@]}" "${coordinadores_sams[@]}" "${becarios_sams[@]}"; do
        [ -z "${USER_IDS[$u]:-}" ] || continue
        local uid
        uid=$(get_user_id "$u")
        if [ -n "$uid" ]; then
            USER_IDS["$u"]=$uid
            verbose "  ${u} → ID ${uid}"
        else
            log "  ⚠️  Usuario ${u} no existe en GitLab — se creará en el primer login LDAP"
        fi
    done
    echo ""

    # --- Fase 1: Dirección como Owner en TODOS los grupos ---
    log "[Fase 1] Sincronizando G-Direccion como Owner..."
    for group_path in "${!GITLAB_GROUPS[@]}"; do
        local group_name="${GITLAB_GROUPS[$group_path]}"
        local gid
        gid=$(get_group_id "$group_path")
        if [ -z "$gid" ]; then
            log "  ⚠️  Grupo ${group_path} no existe en GitLab — saltando"
            continue
        fi
        for sam in "${direccion_sams[@]}"; do
            local uid="${USER_IDS[$sam]:-}"
            [ -n "$uid" ] && add_group_member "$gid" "$uid" "$ACCESS_OWNER" "$group_name" "$sam"
        done
    done
    echo ""

    # --- Fase 2: Coordinadores como Maintainer por proyecto ---
    log "[Fase 2] Sincronizando G-Coordinadores como Maintainer..."
    for proy_group in "${!PROY_GROUPS[@]}"; do
        local gitlab_group="${PROY_GROUPS[$proy_group]}"
        local group_name="${GITLAB_GROUPS[$gitlab_group]}"

        # Obtener miembros del grupo AD del proyecto
        local proy_members=()
        while IFS= read -r m; do [ -n "$m" ] && proy_members+=("$m"); done < <(echo "$(get_ad_group_sams "$proy_group")" | tr ' ' '\n')

        # Coordinadores del proyecto = en G-Coordinadores ∩ PROY-X
        local coord_proy=()
        for coord in "${coordinadores_sams[@]}"; do
            for pm in "${proy_members[@]}"; do
                if [ "$coord" = "$pm" ]; then
                    coord_proy+=("$coord")
                    verbose "  ${coord} → ${gitlab_group} (Maintainer)"
                fi
            done
        done

        if [ ${#coord_proy[@]} -gt 0 ]; then
            local gid
            gid=$(get_group_id "$gitlab_group")
            if [ -n "$gid" ]; then
                for sam in "${coord_proy[@]}"; do
                    local uid="${USER_IDS[$sam]:-}"
                    [ -n "$uid" ] && add_group_member "$gid" "$uid" "$ACCESS_MAINTAINER" "$group_name" "$sam"
                done
            fi
        fi
    done
    echo ""

    # --- Fase 3: Becarios como Developer por proyecto ---
    log "[Fase 3] Sincronizando G-Becarios como Developer..."
    for proy_group in "${!PROY_GROUPS[@]}"; do
        local gitlab_group="${PROY_GROUPS[$proy_group]}"
        local group_name="${GITLAB_GROUPS[$gitlab_group]}"

        local proy_members=()
        while IFS= read -r m; do [ -n "$m" ] && proy_members+=("$m"); done < <(echo "$(get_ad_group_sams "$proy_group")" | tr ' ' '\n')

        local beca_proy=()
        for beca in "${becarios_sams[@]}"; do
            for pm in "${proy_members[@]}"; do
                if [ "$beca" = "$pm" ]; then
                    beca_proy+=("$beca")
                    verbose "  ${beca} → ${gitlab_group} (Developer)"
                fi
            done
        done

        if [ ${#beca_proy[@]} -gt 0 ]; then
            local gid
            gid=$(get_group_id "$gitlab_group")
            if [ -n "$gid" ]; then
                for sam in "${beca_proy[@]}"; do
                    local uid="${USER_IDS[$sam]:-}"
                    [ -n "$uid" ] && add_group_member "$gid" "$uid" "$ACCESS_DEVELOPER" "$group_name" "$sam"
                done
            fi
        fi
    done
    echo ""

    log "=== Sync completado ==="
    [ "$DRY_RUN" = true ] && log "*** DRY-RUN — no se realizaron cambios ***"
}

main "$@"
