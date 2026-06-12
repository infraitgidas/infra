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
# Dependencias: ldap-utils, curl, jq
#   dnf install ldap-utils curl jq
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
# Los paths coinciden con los identifiers de proyectos en Redmine
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

api() {
    local method="$1" endpoint="$2" data="${3:-}"
    local curl_cmd="curl -sf --connect-timeout 10"
    curl_cmd="$curl_cmd --header \"PRIVATE-TOKEN: ${GITLAB_API_TOKEN}\""
    curl_cmd="$curl_cmd --header \"Content-Type: application/json\""
    curl_cmd="$curl_cmd --request ${method}"
    [ -n "$data" ] && curl_cmd="$curl_cmd --data '${data}'"
    curl_cmd="$curl_cmd \"${GITLAB_URL}/api/v4${endpoint}\""
    
    if [ "$DRY_RUN" = true ]; then
        echo "[DRY-RUN] curl -X ${method} ${GITLAB_URL}/api/v4${endpoint}"
        [ -n "$data" ] && echo "[DRY-RUN] data: ${data}"
        return
    fi
    
    eval "$curl_cmd" 2>/dev/null || return 1
}

# ================================================================
# Prerequisitos
# ================================================================

check_prereqs() {
    for cmd in ldapsearch curl jq; do
        if ! command -v "$cmd" &>/dev/null; then
            fail "Requerido: $cmd. Instalar con: dnf install ldap-utils curl jq"
        fi
    done
    verbose "Prerequisitos OK — ldapsearch, curl, jq disponibles"

    if [ -z "$GITLAB_API_TOKEN" ]; then
        fail "GITLAB_API_TOKEN no configurado. Generar token en GitLab Web UI: User → Preferences → Access Tokens"
    fi
    
    if [ -z "$AD_BIND_PASS" ]; then
        fail "AD_BIND_PASS no configurado. Configurar AD_BIND_PASS en 00-env.sh o variable de entorno"
    fi
}

# ================================================================
# AD: Consultar miembros de grupo
# ================================================================

query_ad_group() {
    local group_cn="$1"
    local ldap_filter="(&(objectClass=group)(cn=${group_cn}))"
    
    ldapsearch -H "ldap://${AD_HOST}:${AD_PORT}" -x \
        -D "${AD_BIND_DN}" -w "${AD_BIND_PASS}" \
        -b "${AD_GROUPS_DN}" \
        -LLL \
        "$ldap_filter" \
        member 2>/dev/null || echo ""
}

extract_members_from_ldap() {
    grep '^member:' | sed 's/^member: //' | sort -u
}

get_ad_group_members() {
    local group_cn="$1"
    local members=()
    
    while IFS= read -r dn; do
        [ -z "$dn" ] && continue
        # Extraer sAMAccountName del DN
        # Formato: CN=Leandro Rocca,OU=Direccion,DC=GDC01,DC=local
        local cn_part
        cn_part=$(echo "$dn" | grep -oP 'CN=[^,]+' | head -1 | sed 's/^CN=//')
        
        # Buscar sAMAccountName por CN
        local sam
        sam=$(ldapsearch -H "ldap://${AD_HOST}:${AD_PORT}" -x \
            -D "${AD_BIND_DN}" -w "${AD_BIND_PASS}" \
            -b "${AD_BASE_DN}" \
            -LLL \
            "(&(objectClass=user)(cn=${cn_part}))" \
            sAMAccountName 2>/dev/null | grep '^sAMAccountName:' | sed 's/^sAMAccountName: //' | head -1)
        
        if [ -n "$sam" ]; then
            members+=("$sam")
            verbose "  Miembro AD: ${sam} (${cn_part})"
        fi
    done < <(query_ad_group "$group_cn" | extract_members_from_ldap)
    
    echo "${members[@]}"
}

# ================================================================
# GitLab: Gestionar miembros de grupo
# ================================================================

get_gitlab_group_id() {
    local group_path="$1"
    api GET "/groups?search=${group_path}" 2>/dev/null | \
        jq -r ".[] | select(.path == \"${group_path}\") | .id" 2>/dev/null || echo ""
}

get_gitlab_user_id() {
    local username="$1"
    api GET "/users?username=${username}" 2>/dev/null | \
        jq -r ".[0].id" 2>/dev/null || echo ""
}

get_gitlab_group_members() {
    local group_id="$1"
    api GET "/groups/${group_id}/members" 2>/dev/null | \
        jq -r '.[] | "\(.id) \(.username) \(.access_level)"' 2>/dev/null || true
}

add_gitlab_member() {
    local group_id="$1" user_id="$2" access_level="$3" username="$4" group_name="$5"
    log "  Agregando ${username} (level ${access_level}) a grupo ${group_name}"
    
    if [ "$DRY_RUN" = false ]; then
        api POST "/groups/${group_id}/members" \
            "{\"user_id\": ${user_id}, \"access_level\": ${access_level}}" || \
        log "  ⚠️  Error agregando ${username} a ${group_name} (puede ya existir)"
    fi
}

remove_gitlab_member() {
    local group_id="$1" user_id="$2" username="$3" group_name="$4"
    log "  Eliminando ${username} de grupo ${group_name}"
    
    if [ "$DRY_RUN" = false ]; then
        api DELETE "/groups/${group_id}/members/${user_id}" || true
    fi
}

sync_group_members() {
    local group_path="$1" group_name="$2"
    local expected_users="$3" expected_access="$4"
    
    log "Procesando grupo: ${group_name} (${group_path})"
    
    # Obtener ID del grupo en GitLab
    local group_id
    group_id=$(get_gitlab_group_id "$group_path")
    if [ -z "$group_id" ]; then
        log "  ⚠️  Grupo ${group_path} no existe en GitLab — saltando"
        return
    fi
    log "  GitLab Group ID: ${group_id}"
    
    # Obtener miembros actuales en GitLab
    local current_members
    current_members=$(get_gitlab_group_members "$group_id")
    
    # Convertir miembros actuales a array asociativo: username → access_level
    declare -A current_map
    while IFS= read -r member_line; do
        [ -z "$member_line" ] && continue
        local uid uname level
        read -r uid uname level <<< "$member_line"
        current_map["$uname"]="$level"
    done <<< "$current_members"
    
    # Agregar o actualizar miembros esperados
    local added=0 removed=0
    for username in $expected_users; do
        local user_id
        user_id=$(get_gitlab_user_id "$username")
        if [ -z "$user_id" ]; then
            log "  ⚠️  Usuario ${username} no existe en GitLab — saltando"
            continue
        fi
        
        if [ -z "${current_map[$username]:-}" ]; then
            # Usuario no está en el grupo — agregar
            add_gitlab_member "$group_id" "$user_id" "$expected_access" "$username" "$group_name"
            added=$((added + 1))
        elif [ "${current_map[$username]}" != "$expected_access" ]; then
            # Usuario tiene nivel de acceso incorrecto — actualizar
            log "  Actualizando ${username}: level ${current_map[$username]} → ${expected_access}"
            if [ "$DRY_RUN" = false ]; then
                api PUT "/groups/${group_id}/members/${user_id}" \
                    "{\"access_level\": ${expected_access}}" || true
            fi
            added=$((added + 1))
        fi
        # Marcar como procesado
        unset current_map["$username"]
    done
    
    # Eliminar miembros que ya no deberían estar
    for username in "${!current_map[@]}"; do
        remove_gitlab_member "$group_id" "$(get_gitlab_user_id "$username")" "$username" "$group_name"
        removed=$((removed + 1))
    done
    
    log "  Resultado: +${added} agregados, -${removed} eliminados"
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
    
    check_prereqs
    
    # --- 1. Sincronizar Dirección (Owner en todos los grupos) ---
    log "[1/3] Procesando G-Direccion (Owner en todos los grupos)..."
    local direccion_members
    direccion_members=$(get_ad_group_members "G-Direccion")
    
    for group_path in "${!GITLAB_GROUPS[@]}"; do
        sync_group_members "$group_path" "${GITLAB_GROUPS[$group_path]}" \
            "$direccion_members" "$ACCESS_OWNER"
    done
    echo ""
    
    # --- 2. Sincronizar Coordinadores (Maintainer en su proyecto) ---
    log "[2/3] Procesando G-Coordinadores (Maintainer por proyecto)..."
    local coordinadores_all
    coordinadores_all=$(get_ad_group_members "G-Coordinadores")
    
    for proy_group in "${!PROY_GROUPS[@]}"; do
        local gitlab_group="${PROY_GROUPS[$proy_group]}"
        log "  Proyecto AD ${proy_group} → GitLab ${gitlab_group}"
        
        # Obtener miembros del grupo AD del proyecto
        local proy_members
        proy_members=$(get_ad_group_members "$proy_group")
        
        # Los coordinadores del proyecto son los que están en AMBOS grupos
        local coord_proy=()
        for coord in $coordinadores_all; do
            for member in $proy_members; do
                if [ "$coord" = "$member" ]; then
                    coord_proy+=("$coord")
                fi
            done
        done
        
        verbose "  Coordinadores en ${proy_group}: ${coord_proy[*]:-ninguno}"
        sync_group_members "$gitlab_group" "${GITLAB_GROUPS[$gitlab_group]}" \
            "${coord_proy[*]}" "$ACCESS_MAINTAINER"
    done
    echo ""
    
    # --- 3. Sincronizar Becarios (Developer en su proyecto) ---
    log "[3/3] Procesando G-Becarios (Developer por proyecto)..."
    local becarios_all
    becarios_all=$(get_ad_group_members "G-Becarios")
    
    for proy_group in "${!PROY_GROUPS[@]}"; do
        local gitlab_group="${PROY_GROUPS[$proy_group]}"
        log "  Proyecto AD ${proy_group} → GitLab ${gitlab_group}"
        
        local proy_members
        proy_members=$(get_ad_group_members "$proy_group")
        
        local beca_proy=()
        for beca in $becarios_all; do
            for member in $proy_members; do
                if [ "$beca" = "$member" ]; then
                    beca_proy+=("$beca")
                fi
            done
        done
        
        verbose "  Becarios en ${proy_group}: ${beca_proy[*]:-ninguno}"
        sync_group_members "$gitlab_group" "${GITLAB_GROUPS[$gitlab_group]}" \
            "${beca_proy[*]}" "$ACCESS_DEVELOPER"
    done
    
    echo ""
    log "=== Sync completado ==="
    [ "$DRY_RUN" = true ] && log "*** DRY-RUN — no se realizaron cambios ***"
}

main "$@"
