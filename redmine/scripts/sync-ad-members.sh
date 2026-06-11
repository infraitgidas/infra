#!/bin/bash
# ================================================================
# sync-ad-members.sh — AD → Redmine Project Role Sync
# ================================================================
# Hybrid approach: LDAP Group Sync (nativo) maneja la creación de
# grupos Redmine. Este script asigna roles FINOS por proyecto.
#
# Lógica de mapping (refleja staff.md):
#   G-Direccion           → Director  en TODOS los proyectos
#   G-Coordinadores ∩ PROY-X → Coordinador  en proyecto X
#   G-Becarios     ∩ PROY-X → Becario      en proyecto X
#   G-Coordinadores (todos) → Coordinador  en Dirección y Administración
#
# Dependencias: ldap-utils, curl, jq
#   apt install ldap-utils curl jq
#
# Uso:
#   ./sync-ad-members.sh                    # Sync completo
#   ./sync-ad-members.sh --dry-run          # Solo mostrar cambios
#   ./sync-ad-members.sh --verbose          # Log detallado
#
# Cron (cada 15 minutos):
#   */15 * * * * /opt/infra/redmine/scripts/sync-ad-members.sh
# ================================================================
set -euo pipefail

# ================================================================
# Configuración
# ================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REDMINE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Source environment (AD LDAP creds + Redmine API key)
source "${REDMINE_DIR}/00-env.sh" 2>/dev/null || true

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

# --- Redmine API Settings ---
REDMINE_URL="${REDMINE_URL:-http://localhost}"
REDMINE_API_KEY="${REDMINE_API_KEY:-}"

# --- Role ID mapping (configurable — ajustar según Redmine real) ---
# Estos IDs se obtienen de: curl -s -H "X-Redmine-API-Key: $KEY" $URL/roles.json
ROLE_DIRECTOR_ID="${ROLE_DIRECTOR_ID:-6}"
ROLE_COORDINADOR_ID="${ROLE_COORDINADOR_ID:-7}"
ROLE_BECARIO_ID="${ROLE_BECARIO_ID:-8}"

# --- Projectos Redmine (identifier → nombre) ---
# Los identifiers son lowercase sin acentos
declare -A PROJECTS=(
    ["direccion"]="Dirección"
    ["administracion"]="Administración"
    ["capnee"]="CAPNEE"
    ["infrait"]="INFRAiT"
    ["telepark"]="TELEPARK"
    ["gmet"]="GMET"
    ["gis"]="GIS"
)

# --- Grupos AD de proyectos (PROY-* identifier → proyecto Redmine) ---
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
    log "[ERROR] $*" >&2
    exit 1
}

# ================================================================
# Paso 1: Verificar prerequisitos
# ================================================================

check_prereqs() {
    for cmd in ldapsearch curl jq; do
        if ! command -v "$cmd" &>/dev/null; then
            fail "Requerido: $cmd. Instalar con: apt install ldap-utils curl jq"
        fi
    done

    if [ -z "$AD_BIND_PASS" ]; then
        fail "AD_BIND_PASS no configurado. Verificar secrets/redmine.yaml"
    fi

    if [ -z "$REDMINE_API_KEY" ]; then
        fail "REDMINE_API_KEY no configurado. Verificar secrets/redmine.yaml"
    fi

    verbose "Prerequisitos OK — ldapsearch, curl, jq disponibles"
    verbose "AD: ${AD_HOST}:${AD_PORT} | Redmine: ${REDMINE_URL}"
}

# ================================================================
# Paso 2: Query AD — obtener miembros de grupos
# ================================================================

query_ad_group() {
    local group_cn="$1"
    local ldap_filter="(&(objectClass=group)(cn=${group_cn}))"
    local attrs="member"

    ldapsearch -H "ldap://${AD_HOST}:${AD_PORT}" \
        -x \
        -D "$AD_BIND_DN" \
        -w "$AD_BIND_PASS" \
        -b "$AD_GROUPS_DN" \
        -LLL \
        "$ldap_filter" \
        "$attrs" 2>/dev/null || true
}

extract_members_from_ldap() {
    # Extrae DNs de las entradas member
    grep "^member:" | cut -d' ' -f2- | sort -u
}

# Build CN → sAMAccountName mapping from AD in a single query
build_cn_to_sam_map() {
    declare -gA CN_TO_SAM
    local current_cn=""
    while IFS= read -r line; do
        if [[ "$line" =~ ^cn: ]]; then
            current_cn="${line#cn: }"
        elif [[ "$line" =~ ^sAMAccountName: ]]; then
            local sam="${line#sAMAccountName: }"
            if [ -n "$current_cn" ] && [ -n "$sam" ]; then
                CN_TO_SAM["$current_cn"]="$sam"
            fi
            current_cn=""
        fi
    done < <(ldapsearch -H "ldap://${AD_HOST}:${AD_PORT}" -x \
        -D "$AD_BIND_DN" -w "$AD_BIND_PASS" \
        -b "$AD_BASE_DN" -LLL \
        "(&(objectClass=user)(objectCategory=person))" \
        cn sAMAccountName 2>/dev/null)
    verbose "Cargados ${#CN_TO_SAM[@]} usuarios AD"
}

resolve_dn_to_sam() {
    # Extrae el CN del DN y lo busca en CN_TO_SAM
    local dn="$1"
    # Formato: CN=Leandro Rocca,OU=Direccion,DC=GDC01,DC=local
    local cn="${dn#CN=}"
    cn="${cn%%,*}"
    echo "${CN_TO_SAM["$cn"]:-}"
}

get_ad_group_members() {
    local group_cn="$1"
    verbose "Consultando AD: grupo ${group_cn}..."
    local members=""

    # Obtener los DNs de los miembros del grupo y resolverlos
    while IFS= read -r dn; do
        [ -z "$dn" ] && continue
        local sam
        sam=$(resolve_dn_to_sam "$dn")
        if [ -n "$sam" ]; then
            members="${members} ${sam}"
        fi
    done < <(query_ad_group "$group_cn" | extract_members_from_ldap)

    echo "$members" | xargs
}

# ================================================================
# Paso 3: Query Redmine — obtener usuarios, proyectos, roles
# ================================================================

redmine_api_get() {
    local endpoint="$1"
    curl -s -f -H "X-Redmine-API-Key: ${REDMINE_API_KEY}" \
        "${REDMINE_URL}${endpoint}" 2>/dev/null || echo "{}"
}

get_redmine_users() {
    # Retorna: "login1:id1 login2:id2 ..."
    verbose "Consultando Redmine: users..."
    local users_json
    users_json=$(redmine_api_get "/users.json?limit=100")
    echo "$users_json" | jq -r '.users[] | "\(.login):\(.id)"' 2>/dev/null || true
}

get_redmine_projects() {
    # Retorna: "identifier1:id1 identifier2:id2 ..."
    verbose "Consultando Redmine: projects..."
    local projects_json
    projects_json=$(redmine_api_get "/projects.json?limit=100")
    echo "$projects_json" | jq -r '.projects[] | "\(.identifier):\(.id)"' 2>/dev/null || true
}

get_redmine_roles() {
    # Retorna: "name1:id1 name2:id2 ..."
    verbose "Consultando Redmine: roles..."
    local roles_json
    roles_json=$(redmine_api_get "/roles.json?limit=100")
    echo "$roles_json" | jq -r '.roles[] | "\(.name):\(.id)"' 2>/dev/null || true
}

get_project_memberships() {
    local project_id="$1"
    # Retorna: "user_id:role_id1,role_id2 ..." por línea
    local members_json
    members_json=$(redmine_api_get "/projects/${project_id}/memberships.json?limit=100")
    echo "$members_json" | jq -r '.memberships[] | select(.user != null) | "\(.user.id):\(.roles | map(.id) | join(","))"' 2>/dev/null || true
}

# ================================================================
# Paso 4: Construir estado deseado
# ================================================================

# Estructura: desired_state[project_identifier]="user_id:role_id user_id:role_id ..."

build_desired_state() {
    local -n users_map="$1"      # login → id
    local -n projects_map="$2"   # identifier → id
    local -A state               # identifier → "user_id:role_id ..."

    # Pre-cargar mapping CN → sAMAccountName (una sola query AD)
    build_cn_to_sam_map

    verbose "Consultando grupos AD..."

    # --- Obtener miembros de grupos AD ---
    IFS=' ' read -r -a direccion_members <<< "$(get_ad_group_members "G-Direccion")"
    IFS=' ' read -r -a coordinadores_members <<< "$(get_ad_group_members "G-Coordinadores")"
    IFS=' ' read -r -a becarios_members <<< "$(get_ad_group_members "G-Becarios")"

    verbose "G-Direccion: ${direccion_members[*]:-}"
    verbose "G-Coordinadores: ${coordinadores_members[*]:-}"
    verbose "G-Becarios: ${becarios_members[*]:-}"

    # --- Obtener miembros de cada PROY-* ---
    declare -A proy_members   # group_name → "user1 user2 ..."
    for proy_group in "${!PROY_GROUPS[@]}"; do
        local members
        members=$(get_ad_group_members "$proy_group")
        proy_members["$proy_group"]="$members"
        verbose "${proy_group}: ${members:-}"
    done

    # --- Construir desired state (key = project identifier, ej: "capnee") ---
    for proj_id in "${!PROJECTS[@]}"; do
        local proj_name="${PROJECTS[$proj_id]}"
        local redmine_proj_id="${projects_map[$proj_id]:-}"

        if [ -z "$redmine_proj_id" ]; then
            verbose "Proyecto Redmine no encontrado: ${proj_id} (${proj_name}). Skipeando."
            continue
        fi

        verbose "Procesando proyecto: ${proj_name} (id=${redmine_proj_id})..."
        state["$proj_id"]=""

        # --- Directores → TODOS los proyectos (rol Director) ---
        for user_login in "${direccion_members[@]:-}"; do
            [ -z "$user_login" ] && continue
            local user_id="${users_map[$user_login]:-}"
            if [ -n "$user_id" ]; then
                state["${proj_id}"]="${state[${proj_id}]:-} ${user_id}:${ROLE_DIRECTOR_ID}"
                verbose "  Director ${user_login} → ${proj_name} (Director)"
            else
                verbose "  WARN: Director ${user_login} no existe en Redmine (skip)"
            fi
        done

        # --- Coordinadores/Becarios → proyecto que gestionan (intersección PROY-*) ---
        for proy_group in "${!PROY_GROUPS[@]}"; do
            local target_proj="${PROY_GROUPS[$proy_group]}"
            [ "$target_proj" != "$proj_id" ] && continue

            IFS=' ' read -r -a members <<< "${proy_members[$proy_group]:-}"
            for user_login in "${members[@]:-}"; do
                [ -z "$user_login" ] && continue
                local user_id="${users_map[$user_login]:-}"
                [ -z "$user_id" ] && continue

                # Si ya está asignado (ej: como Director), skip
                local already_done=false
                IFS=' ' read -r -a entries <<< "${state[${proj_id}]:-}"
                for entry in "${entries[@]:-}"; do
                    local existing_uid="${entry%%:*}"
                    [ "$existing_uid" = "$user_id" ] && already_done=true && break
                done
                [ "$already_done" = true ] && continue

                # Verificar si es coordinador o becario
                local is_coord=false; local is_becario=false
                for c in "${coordinadores_members[@]:-}"; do [ "$c" = "$user_login" ] && is_coord=true && break; done
                for b in "${becarios_members[@]:-}"; do [ "$b" = "$user_login" ] && is_becario=true && break; done

                if [ "$is_coord" = true ]; then
                    state["${proj_id}"]="${state[${proj_id}]:-} ${user_id}:${ROLE_COORDINADOR_ID}"
                    verbose "  ${user_login} → ${proj_name} (Coordinador)"
                elif [ "$is_becario" = true ]; then
                    state["${proj_id}"]="${state[${proj_id}]:-} ${user_id}:${ROLE_BECARIO_ID}"
                    verbose "  ${user_login} → ${proj_name} (Becario)"
                fi
            done
        done

        # --- Dirección y Administración: también los coordinadores ---
        if [ "$proj_id" = "direccion" ] || [ "$proj_id" = "administracion" ]; then
            for user_login in "${coordinadores_members[@]:-}"; do
                [ -z "$user_login" ] && continue
                local user_id="${users_map[$user_login]:-}"
                [ -z "$user_id" ] && continue

                # Verificar que no esté ya asignado
                local already_done=false
                IFS=' ' read -r -a entries <<< "${state[${proj_id}]:-}"
                for entry in "${entries[@]:-}"; do
                    local existing_uid="${entry%%:*}"
                    [ "$existing_uid" = "$user_id" ] && already_done=true && break
                done
                [ "$already_done" = true ] && continue

                state["${proj_id}"]="${state[${proj_id}]:-} ${user_id}:${ROLE_COORDINADOR_ID}"
                verbose "  ${user_login} → ${proj_name} (Coordinador — acceso general)"
            done
        fi
    done

    # Retornar estado deseado (key = project identifier)
    for proj_id in "${!state[@]}"; do
        local trimmed
        trimmed="$(echo "${state[$proj_id]}" | xargs)"
        echo "${proj_id}|${trimmed}"
    done
}

# ================================================================
# Paso 5: Aplicar sync — Redmine API
# ================================================================

apply_sync() {
    local -n users_map="$1"
    local -n projects_map="$2"
    local desired_state_str="$3"

    local total_changes=0

    # Parse desired state into a proper array (key = project identifier)
    declare -A desired
    while IFS='|' read -r proj_id entries; do
        [ -z "$proj_id" ] && continue
        desired["$proj_id"]="$entries"
    done <<< "$desired_state_str"

    # Construir reverse mapping: numeric_id → identifier (para logging)
    declare -A ID_TO_IDENTIFIER
    for ident in "${!projects_map[@]}"; do
        ID_TO_IDENTIFIER["${projects_map[$ident]}"]="$ident"
    done

    for proj_id in "${!PROJECTS[@]}"; do
        local redmine_proj_id="${projects_map[$proj_id]:-}"
        [ -z "$redmine_proj_id" ] && continue

        local proj_name="${PROJECTS[$proj_id]}"
        verbose "Syncing project: ${proj_name} (id=${redmine_proj_id})..."

        # Parse current members: user_id → membership_id:role_ids
        # NOTA: declare -A NO limpia el array si ya existe de iteración anterior.
        # Hay que vaciarlo explícitamente.
        declare -A current_members
        current_members=()
        local memberships_json
        memberships_json=$(redmine_api_get "/projects/${redmine_proj_id}/memberships.json?limit=100")
        while IFS='|' read -r membership_id user_id role_ids; do
            [ -z "$user_id" ] && continue
            current_members["$user_id"]="${membership_id}:${role_ids}"
        done < <(echo "$memberships_json" | jq -r '.memberships[] | select(.user != null) | "\(.id)|\(.user.id)|\(.roles | map(.id) | join(","))"' 2>/dev/null || true)

        # Parse desired members: user_id:role_id pairs (lookup by identifier)
        declare -A desired_members
        desired_members=()
        IFS=' ' read -r -a pairs <<< "${desired[$proj_id]:-}"
        for pair in "${pairs[@]:-}"; do
            [ -z "$pair" ] && continue
            local uid="${pair%%:*}"
            local rid="${pair##*:}"
            desired_members["$uid"]="$rid"
        done

        # --- REMOVER miembros que no deberían estar ---
        for user_id in "${!current_members[@]}"; do
            if [ -z "${desired_members[$user_id]:-}" ]; then
                local mem_info="${current_members[$user_id]}"
                local membership_id="${mem_info%%:*}"
                log "  [REMOVER] ${proj_name}: user_id=${user_id} (membership=${membership_id})"

                if [ "$DRY_RUN" = false ]; then
                    curl -s -o /dev/null -w "%{http_code}" \
                        -X DELETE \
                        -H "X-Redmine-API-Key: ${REDMINE_API_KEY}" \
                        "${REDMINE_URL}/memberships/${membership_id}.json" || true
                fi
                total_changes=$((total_changes + 1))
            fi
        done

        # --- AGREGAR/ACTUALIZAR miembros ---
        for user_id in "${!desired_members[@]}"; do
            local desired_role="${desired_members[$user_id]}"
            local current="${current_members[$user_id]:-}"

            if [ -z "$current" ]; then
                # No existe → CREAR
                log "  [CREAR] ${proj_name}: user_id=${user_id} → role=${desired_role}"

                if [ "$DRY_RUN" = false ]; then
                    local http_code
                    http_code=$(curl -s -o /dev/null -w "%{http_code}" \
                        -X POST \
                        -H "Content-Type: application/json" \
                        -H "X-Redmine-API-Key: ${REDMINE_API_KEY}" \
                        -d "{\"membership\": {\"user_id\": ${user_id}, \"role_ids\": [${desired_role}]}}" \
                        "${REDMINE_URL}/projects/${redmine_proj_id}/memberships.json" || true)
                    if [ "$http_code" != "201" ]; then
                        log "  [ERROR] Crear membresía falló (HTTP ${http_code})"
                    fi
                fi
                total_changes=$((total_changes + 1))
            else
                # Existe → verificar si el rol cambió
                local mem_info="$current"
                local membership_id="${mem_info%%:*}"
                local current_roles="${mem_info##*:}"

                # Normalizar: si el rol actual es el mismo, skip
                # current_roles puede ser "6,7" (multi-rol), comparar si desired_role está incluido
                if ! echo "$current_roles" | grep -q "\b${desired_role}\b"; then
                    log "  [ACTUALIZAR] ${proj_name}: user_id=${user_id} roles=${current_roles}→${desired_role}"

                    if [ "$DRY_RUN" = false ]; then
                        local http_code
                        http_code=$(curl -s -o /dev/null -w "%{http_code}" \
                            -X PUT \
                            -H "Content-Type: application/json" \
                            -H "X-Redmine-API-Key: ${REDMINE_API_KEY}" \
                            -d "{\"membership\": {\"role_ids\": [${desired_role}]}}" \
                            "${REDMINE_URL}/memberships/${membership_id}.json" || true)
                        if [ "$http_code" != "200" ] && [ "$http_code" != "204" ]; then
                            log "  [ERROR] Actualizar membresía falló (HTTP ${http_code})"
                        fi
                    fi
                    total_changes=$((total_changes + 1))
                fi
            fi
        done
    done

    echo "$total_changes"
}

# ================================================================
# Main
# ================================================================

main() {
    log "=== AD → Redmine Sync ==="
    log "Mode: $([ "$DRY_RUN" = true ] && echo "DRY-RUN" || echo "LIVE")"

    # 1. Verificar prerequisitos
    check_prereqs

    # 2. Obtener datos de Redmine
    verbose "Obteniendo datos de Redmine..."

    # Usuarios: login → id (global para nameref en subshells)
    declare -gA USERS
    while IFS=':' read -r login uid; do
        [ -z "$login" ] && continue
        USERS["$login"]="$uid"
    done < <(get_redmine_users)

    if [ ${#USERS[@]} -eq 0 ]; then
        fail "No se pudieron obtener usuarios de Redmine. Verificar URL y API key."
    fi
    verbose "Usuarios Redmine: ${#USERS[@]}"

    # Proyectos: identifier → id (global)
    declare -gA PROJECTS_MAP
    while IFS=':' read -r identifier pid; do
        [ -z "$identifier" ] && continue
        PROJECTS_MAP["$identifier"]="$pid"
    done < <(get_redmine_projects)

    if [ ${#PROJECTS_MAP[@]} -eq 0 ]; then
        fail "No se pudieron obtener proyectos de Redmine."
    fi
    verbose "Proyectos Redmine: ${#PROJECTS_MAP[@]}"

    # Roles: name → id
    declare -A ROLES_MAP
    while IFS=':' read -r name rid; do
        [ -z "$name" ] && continue
        ROLES_MAP["$name"]="$rid"
    done < <(get_redmine_roles)
    verbose "Roles Redmine: ${#ROLES_MAP[@]}"

    # 3. Construir estado deseado desde AD
    log "Consultando AD (${AD_HOST}:${AD_PORT})..."
    local desired_state
    desired_state=$(build_desired_state USERS PROJECTS_MAP)

    # 4. Mostrar resumen del estado deseado
    log "Estado deseado construido."
    while IFS='|' read -r proj_id entries; do
        [ -z "$proj_id" ] && continue
        local proj_name="${PROJECTS[$proj_id]:-${proj_id}}"
        local count=0
        [ -n "$entries" ] && count=$(echo "$entries" | wc -w | xargs)
        log "  ${proj_name}: ${count} miembros deseados"
    done <<< "$desired_state"

    # 5. Aplicar sync
    log "Aplicando sync..."
    local changes
    changes=$(apply_sync USERS PROJECTS_MAP "$desired_state")

    # 6. Resumen final
    if [ "$DRY_RUN" = true ]; then
        log "=== DRY-RUN Complete — ${changes} cambios detectados (no aplicados) ==="
    else
        log "=== Sync Complete — ${changes} cambios aplicados ==="
    fi
}

main "$@"
