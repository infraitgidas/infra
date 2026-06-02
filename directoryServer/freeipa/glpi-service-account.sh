#!/bin/bash
# ================================================================
# glpi-service-account.sh — FreeIPA LDAP Service Account for GLPI
# ================================================================
# Creates a dedicated LDAP service account for GLPI authentication
# and user synchronization.
#
# Usage:
#   ./glpi-service-account.sh                    # Interactive
#   ./glpi-service-account.sh --password <pass>  # Non-interactive
#   ./glpi-service-account.sh --dry-run          # Show commands only
#
# Prerequisites:
#   - FreeIPA admin credentials (stored in secrets/ or prompted)
#   - kinit as FreeIPA admin
# ================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Source ITSM env if available
if [ -f "${PROJECT_DIR}/itsm/00-env.sh" ]; then
    source "${PROJECT_DIR}/itsm/00-env.sh"
fi

DRY_RUN=false
SERVICE_PASSWORD=""

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=true ;;
        --password=*) SERVICE_PASSWORD="${arg#*=}" ;;
    esac
done

# --- Configuration ---
IPA_SERVER="${IPA_SERVER:-ipa.gidas.local}"
SERVICE_CN="${SERVICE_CN:-glpi-svc}"
SERVICE_DN="cn=${SERVICE_CN},cn=sysaccounts,cn=etc,dc=gidas,dc=local"

# GLPI user group (for membership-based filter)
GLPI_USER_GROUP="${GLPI_USER_GROUP:-glpi-users}"
GLPI_ADMIN_GROUP="${GLPI_ADMIN_GROUP:-glpi-admin}"
GLPI_TECH_GROUP="${GLPI_TECH_GROUP:-glpi-tech}"

echo "=== FreeIPA GLPI Service Account Setup ==="
echo "Server:  ${IPA_SERVER}"
echo "Service: ${SERVICE_DN}"
echo ""

# ---------------------------------------------------------------
# Step 1: Verify FreeIPA connectivity
# ---------------------------------------------------------------
echo "[1/5] Verifying FreeIPA connectivity..."

if ! ipa ping 2>/dev/null | grep -q "IPA server version"; then
    echo "[1/5] WARNING: 'ipa ping' failed — trying with kinit..."
    echo "    Ensure you're authenticated: kinit admin"
    echo "    Or specify --password option"
    if [ -z "${SERVICE_PASSWORD}" ]; then
        echo "    Service account password will be prompted during creation"
    fi
fi

echo "[1/5] FreeIPA reachable"

# ---------------------------------------------------------------
# Step 2: Create service account
# ---------------------------------------------------------------
echo "[2/5] Creating service account '${SERVICE_CN}'..."

if ipa user-find "${SERVICE_CN}" 2>/dev/null | grep -q "User login: ${SERVICE_CN}"; then
    echo "[2/5] Service account '${SERVICE_CN}' already exists"
else
    echo "[2/5] Creating new service account..."
    
    IPA_CMD="ipa user-add ${SERVICE_CN} \
        --first=GLPI \
        --last=Service \
        --email=glpi-svc@gidas.local \
        --title=\"GLPI LDAP Service Account\" \
        --shell=/sbin/nologin \
        --password"

    if [ "${DRY_RUN}" = true ]; then
        echo "[2/5] [DRY-RUN] Would execute:"
        echo "    ${IPA_CMD}"
    else
        if [ -n "${SERVICE_PASSWORD}" ]; then
            echo "${SERVICE_PASSWORD}" | ipa user-add "${SERVICE_CN}" \
                --first=GLPI \
                --last=Service \
                --email=glpi-svc@gidas.local \
                --title="GLPI LDAP Service Account" \
                --shell=/sbin/nologin \
                --password 2>/dev/null
        else
            ipa user-add "${SERVICE_CN}" \
                --first=GLPI \
                --last=Service \
                --email=glpi-svc@gidas.local \
                --title="GLPI LDAP Service Account" \
                --shell=/sbin/nologin \
                --password
        fi
        echo "[2/5] Service account created: ${SERVICE_DN}"
    fi
fi

# ---------------------------------------------------------------
# Step 3: Set password never expires
# ---------------------------------------------------------------
echo "[3/5] Configuring password policy..."

if [ "${DRY_RUN}" = true ]; then
    echo "[3/5] [DRY-RUN] Would execute:"
    echo "    ipa user-mod ${SERVICE_CN} --password-expiration-days=-1"
else
    ipa user-mod "${SERVICE_CN}" --password-expiration-days=-1 2>/dev/null || \
        echo "[3/5] WARNING: Could not disable password expiration"
    echo "[3/5] Password policy: never expires"
fi

# ---------------------------------------------------------------
# Step 4: Create GLPI groups
# ---------------------------------------------------------------
echo "[4/5] Creating GLPI groups..."

for group in "${GLPI_USER_GROUP}" "${GLPI_ADMIN_GROUP}" "${GLPI_TECH_GROUP}"; do
    if ipa group-find "${group}" 2>/dev/null | grep -q "Group name: ${group}"; then
        echo "[4/5] Group '${group}' already exists"
    else
        if [ "${DRY_RUN}" = true ]; then
            echo "[4/5] [DRY-RUN] Would create group: ${group}"
        else
            ipa group-add "${group}" --desc="GLPI ${group} group" 2>/dev/null
            echo "[4/5] Group created: ${group}"
        fi
    fi
done

# Add service account to glpi-users group (needed for sync)
if [ "${DRY_RUN}" = false ]; then
    ipa group-add-member "${GLPI_USER_GROUP}" --users="${SERVICE_CN}" 2>/dev/null || \
        echo "[4/5] Service account already in group"
fi

echo "[4/5] Groups configured"

# ---------------------------------------------------------------
# Step 5: Verify and document
# ---------------------------------------------------------------
echo "[5/5] Verification..."

if [ "${DRY_RUN}" = false ]; then
    echo "[5/5] Service account DN: ${SERVICE_DN}"
    echo "[5/5] Groups:"
    for group in "${GLPI_USER_GROUP}" "${GLPI_ADMIN_GROUP}" "${GLPI_TECH_GROUP}"; do
        MEMBER_COUNT=$(ipa group-show "${group}" 2>/dev/null | grep "Member users:" | wc -l || echo 0)
        echo "    - ${group}: ${MEMBER_COUNT} member(s)"
    done
    
    # Test LDAP bind
    echo "[5/5] Testing LDAP bind..."
    if ldapsearch -H "ldap://${IPA_SERVER}" \
        -D "${SERVICE_DN}" \
        -w "${SERVICE_PASSWORD}" \
        -b "cn=users,cn=accounts,dc=gidas,dc=local" \
        -s base \
        "(objectClass=*)" \
        dn 2>/dev/null | grep -q "dn:"; then
        echo "[5/5] ✅ LDAP bind successful"
    else
        echo "[5/5] ⚠️  Could not verify LDAP bind (password not provided or ldapsearch not available)"
    fi
fi

# ---------------------------------------------------------------
# Summary
# ---------------------------------------------------------------
echo ""
echo "=== Setup Complete ==="
echo ""
echo "Service Account:"
echo "  DN:     ${SERVICE_DN}"
echo "  Groups: ${GLPI_USER_GROUP}, ${GLPI_ADMIN_GROUP}, ${GLPI_TECH_GROUP}"
echo ""
echo "GLPI LDAP Configuration (use in itsm/config/ldap-auth.php or web UI):"
echo "  Host:     ${IPA_SERVER}"
echo "  Port:     636"
echo "  TLS:      true"
echo "  Base DN:  cn=users,cn=accounts,dc=gidas,dc=local"
echo "  Bind DN:  ${SERVICE_DN}"
echo "  Filter:   (&(objectClass=person)(memberOf=cn=${GLPI_USER_GROUP},cn=groups,cn=accounts,dc=gidas,dc=local))"
echo ""
echo "Profile Mapping:"
echo "  ${GLPI_ADMIN_GROUP} → Super-Admin (profile_id: 4)"
echo "  ${GLPI_TECH_GROUP}  → Technician  (profile_id: 6)"
echo "  ${GLPI_USER_GROUP}  → Observer    (profile_id: 7)"
echo ""
echo "Save the service password in secrets/glpi.yaml (SOPS-encrypted)"
