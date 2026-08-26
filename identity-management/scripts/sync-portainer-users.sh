#!/usr/bin/env bash
# ============================================================
# sync-portainer-users.sh — sincroniza usuarios de Portainer
# con los miembros de un grupo AD.
#
# Portainer CE NO tiene integración AD/LDAP (es de Business
# Edition). Este script crea/deshabilita cuentas locales en
# Portainer espejando la membresía del grupo AD, de forma
# idempotente. Se ejecuta en el host donde corre Portainer
# (por defecto apunta a https://localhost:9443).
#
# Uso:
#   ./sync-portainer-users.sh              # sincronizar (crear faltantes)
#   ./sync-portainer-users.sh --dry-run    # mostrar sin ejecutar
#   ./sync-portainer-users.sh --remove     # además deshabilitar los que ya no están en AD
#
# Variables de entorno (todas opcionales):
#   PORTAINER_URL             (default https://localhost:9443)
#   PORTAINER_ADMIN_USER      (default admin)
#   PORTAINER_ADMIN_PASSWORD  (default Hlvs.2025!hlvs)
#   AD_GROUP                  (default proy-telepark@GDC01.local)
#   DEFAULT_PASSWORD          password inicial para cuentas nuevas (default Telepark.2026!)
#   ROLE                      rol Portainer: 1=admin, 2=standard user (default 2)
# ============================================================
set -euo pipefail

PORTAINER_URL="${PORTAINER_URL:-https://localhost:9443}"
PORTAINER_ADMIN_USER="${PORTAINER_ADMIN_USER:-admin}"
PORTAINER_ADMIN_PASSWORD="${PORTAINER_ADMIN_PASSWORD:-Hlvs.2025!hlvs}"
AD_GROUP="${AD_GROUP:-proy-telepark@GDC01.local}"
DEFAULT_PASSWORD="${DEFAULT_PASSWORD:-Telepark.2026!}"
ROLE="${ROLE:-2}"

DRY_RUN=false
REMOVE=false
for a in "$@"; do
  case "$a" in
    --dry-run) DRY_RUN=true ;;
    --remove)  REMOVE=true ;;
    -h|--help) echo "uso: $0 [--dry-run] [--remove]"; exit 0 ;;
  esac
done

# helper: parsea JSON con python3 (siempre disponible en Rocky)
jget() { python3 -c "import sys,json;d=json.load(sys.stdin);print($1)"; }

log() { echo "  [$1] $2"; }

# --- 1. login a Portainer ---
JWT=$(curl -sk -X POST "$PORTAINER_URL/api/auth" \
  -H 'Content-Type: application/json' \
  -d "{\"Username\":\"$PORTAINER_ADMIN_USER\",\"Password\":\"$PORTAINER_ADMIN_PASSWORD\"}" \
  | jget "d.get('jwt','')")
[ -z "$JWT" ] && { echo "ERROR: no se pudo autenticar en Portainer"; exit 1; }

# --- 2. miembros del grupo AD (nombres cortos, sin @dominio) ---
AD_MEMBERS=$(getent group "$AD_GROUP" 2>/dev/null | cut -d: -f4 | tr ',' '\n' \
  | sed -E 's/@(GDC01|gdc01)\.local$//I' | sort -u | grep -v '^$')
[ -z "$AD_MEMBERS" ] && { echo "ERROR: el grupo AD '$AD_GROUP' no tiene miembros o no resuelve"; exit 1; }

# --- 3. usuarios existentes en Portainer ---
EXISTING=$(curl -sk "$PORTAINER_URL/api/users" -H "Authorization: Bearer $JWT" \
  | jget "'\n'.join(u['Username'] for u in d if isinstance(d,list))")

echo "Grupo AD: $AD_GROUP"
echo "Miembros AD: $(echo "$AD_MEMBERS" | tr '\n' ' ')"
echo ""

# --- 4. crear usuarios faltantes ---
created=0
while IFS= read -r u; do
  if echo "$EXISTING" | grep -qx "$u"; then
    log "ok"     "$u (ya existe)"
  else
    log "nuevo"  "$u"
    if [ "$DRY_RUN" = false ]; then
      resp=$(curl -sk -X POST "$PORTAINER_URL/api/users" \
        -H "Authorization: Bearer $JWT" -H 'Content-Type: application/json' \
        -d "{\"Username\":\"$u\",\"Password\":\"$DEFAULT_PASSWORD\",\"Role\":$ROLE}")
      msg=$(echo "$resp" | jget "d.get('Username', d.get('message','?'))")
      echo "         -> $msg"
    fi
    created=$((created+1))
  fi
done <<< "$AD_MEMBERS"

# --- 5. (opcional) deshabilitar usuarios que ya no están en AD ---
if [ "$REMOVE" = true ]; then
  echo ""
  while IFS= read -r u; do
    [ "$u" = "admin" ] && continue
    if ! echo "$AD_MEMBERS" | grep -qx "$u"; then
      log "fuera" "$u (ya no está en AD)"
      if [ "$DRY_RUN" = false ]; then
        ID=$(curl -sk "$PORTAINER_URL/api/users" -H "Authorization: Bearer $JWT" \
          | jget "[x['Id'] for x in d if x.get('Username')=='$u'][0]")
        curl -sk -X DELETE "$PORTAINER_URL/api/users/$ID" -H "Authorization: Bearer $JWT" >/dev/null
        echo "         -> deshabilitado (id $ID)"
      fi
    fi
  done <<< "$EXISTING"
fi

echo ""
echo "Sincronización completa: $(echo "$AD_MEMBERS" | wc -l) usuarios en AD, $created creados."
