#!/usr/bin/env bash
# Orchestrator: deploy Docker Desktop to GIDAS domain PCs via WinRM (NTLM, 5985).
#
# Usage:
#   deploy-docker.sh [options] <preflight|deploy|verify> [pc_ip ...]
#
# Options:
#   --dry-run        preflight/verify run read-only as usual; deploy only prints the plan.
#   --auto-reboot    automatically restart PCs that finish with REBOOT_REQUIRED and re-run the installer.
#   --concurrency N  parallel PCs handled at once (default 5).
#
# Credentials (checked in this order):
#   1. Environment variables WINRM_USER and WINRM_PASS.
#   2. SOPS-encrypted secrets/network.yaml -> top-level mapping windows_pcs:
#      keys admin_user / admin_pass (decrypted in memory via sops+python, never printed).
#
# Exit codes: 0 success, 1 some PC failed/unreachable/verify FAIL,
#             2 usage error, 3 credentials/secrets problem.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER_PS="$SCRIPT_DIR/install-docker.ps1"
DEFAULT_PCS=(192.168.1.30 192.168.1.50 192.168.1.51 192.168.1.52 192.168.1.53)

DRY_RUN=0
AUTO_REBOOT=0
CONCURRENCY=5
CONNECT_TIMEOUT=5
REBOOT_WAIT_MAX=600       # seconds to wait for a rebooting PC to come back
REBOOT_POLL_INTERVAL=20   # seconds between reachability polls
WINRM_PORT=5985

SUBCOMMAND=''
TARGETS=()
TMP_DIR=''
JOBS_DIR=''

declare -a RESULT_ROWS=()

log()  { printf '%s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
die()  { local code="$1"; shift; printf 'ERROR: %s\n' "$*" >&2; exit "$code"; }

usage() {
    cat <<'EOF'
Usage: deploy-docker.sh [options] <preflight|deploy|verify> [pc_ip ...]

Subcommands:
  preflight   read-only checks per PC (reachability, OS/build, domain, docker presence,
              docker-users membership count, free space on C:)
  deploy      run install-docker.ps1 remotely on each PC; handles reboot-required state
  verify      confirm docker works, Domain Users is in docker-users, service/process present

Options:
  --dry-run          print planned actions; no state-changing remote calls
                     (preflight reads are still allowed)
  --auto-reboot      with deploy: restart PCs needing a reboot, wait for WinRM, re-run installer
  --concurrency N    number of PCs processed in parallel (default: 5)

Targets: positional IPs > $PCS env var > built-in default list (5 classroom PCs).

Credentials:
  export WINRM_USER='...' WINRM_PASS='...'
  or SOPS key windows_pcs.{admin_user,admin_pass} inside secrets/network.yaml
EOF
}

cleanup() {
    [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]] && rm -rf "$TMP_DIR"
}

port_up() {
    timeout 4 bash -c "exec 3<>/dev/tcp/$1/$WINRM_PORT" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Credential loading
# ---------------------------------------------------------------------------

load_credentials() {
    if [[ -n "${WINRM_USER:-}" && -n "${WINRM_PASS:-}" ]]; then
        log "[creds] using WINRM_USER/WINRM_PASS from environment."
        return 0
    fi

    if ! command -v sops >/dev/null 2>&1; then
        die 3 "sops not found in PATH. Either install sops, or export credentials manually:
  export WINRM_USER='<admin user>'
  export WINRM_PASS='<admin pass>'"
    fi

    local repo_root secrets_file out rc=0
    repo_root="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null)" \
        || die 3 "cannot detect repository root via git rev-parse; run from inside the repo or export WINRM_USER/WINRM_PASS."
    secrets_file="$repo_root/secrets/network.yaml"
    [[ -f "$secrets_file" ]] || die 3 "secrets file not found: $secrets_file. Export WINRM_USER/WINRM_PASS instead."

    out="$(sops -d "$secrets_file" 2>/dev/null | python3 -c '
import sys
import yaml

data = yaml.safe_load(sys.stdin)
pcs = data.get("windows_pcs") if isinstance(data, dict) else None
if not isinstance(pcs, dict):
    sys.exit(3)
if "admin_user" not in pcs or "admin_pass" not in pcs:
    sys.exit(4)
print("WINRM_USER=%r" % (pcs["admin_user"],))
print("WINRM_PASS=%r" % (pcs["admin_pass"],))
')" || rc=$?

    case "$rc" in
        0) : ;;
        3) die 3 "key 'windows_pcs' is missing (or not a mapping) in secrets/network.yaml. Fix either way:
  a) export WINRM_USER='<admin user>' and WINRM_PASS='<admin pass>', or
  b) add the mapping (values encrypted):  sops secrets/network.yaml
     windows_pcs:
       admin_user: <admin user>
       admin_pass: <admin pass>" ;;
        4) die 3 "keys admin_user/admin_pass not found under 'windows_pcs' in secrets/network.yaml. Fix either way:
  a) export WINRM_USER='<admin user>' and WINRM_PASS='<admin pass>', or
  b) sops secrets/network.yaml  and add admin_user/admin_pass under windows_pcs:" ;;
        *) die 3 "failed to decrypt $secrets_file (bad/missing age identity?). Check SOPS_AGE_KEY_FILE or your sops config, or export WINRM_USER/WINRM_PASS." ;;
    esac

    eval "$out"
    export WINRM_USER WINRM_PASS
    [[ -n "$WINRM_USER" && -n "$WINRM_PASS" ]] || die 3 "resolved credentials are empty; check windows_pcs values in secrets/network.yaml."
    log "[creds] loaded Windows admin credentials from SOPS ($secrets_file)."
}

# ---------------------------------------------------------------------------
# Remote execution helper (pywinrm)
# ---------------------------------------------------------------------------

write_helper_files() {
    cat > "$TMP_DIR/winrm_exec.py" <<'PYEOF'
import base64
import os
import socket
import sys

import winrm


def fail(code, msg):
    sys.stderr.write("[helper] %s\n" % msg)
    sys.exit(code)


host = os.environ.get("WINRM_HOST") or fail(2, "WINRM_HOST not set")
user = os.environ.get("WINRM_USER") or fail(2, "WINRM_USER not set")
password = os.environ.get("WINRM_PASS") or fail(2, "WINRM_PASS not set")
connect_timeout = float(os.environ.get("WINRM_CONNECT_TIMEOUT", "5"))
read_timeout = int(os.environ.get("WINRM_READ_TIMEOUT", "300"))

script_path = sys.argv[1]
with open(script_path, "rb") as fh:
    raw = fh.read()
encoded = base64.b64encode(raw.decode("utf-8").encode("utf-16-le")).decode("ascii")

try:
    socket.create_connection((host, 5985), timeout=connect_timeout).close()
except OSError as exc:
    fail(4, "tcp connect to %s:5985 failed: %s" % (host, exc))

session = winrm.Session(
    host,
    transport="ntlm",
    username=user,
    password=password,
    read_timeout_sec=read_timeout,
)
try:
    result = session.run_cmd(
        "powershell.exe",
        ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
         "-EncodedCommand", encoded],
    )
except Exception as exc:  # noqa: BLE001 - report any transport failure
    fail(5, "winrm operation failed against %s: %s" % (host, exc))

if result.std_out:
    sys.stdout.write(result.std_out.decode("utf-8", "replace"))
if result.std_err:
    sys.stderr.write(result.std_err.decode("utf-8", "replace"))
sys.exit(0 if result.status_code == 0 else 6)
PYEOF

    cat > "$TMP_DIR/preflight.ps1" <<'PSEOF'
$ErrorActionPreference = 'SilentlyContinue'
$os = Get-CimInstance Win32_OperatingSystem
$cs = Get-CimInstance Win32_ComputerSystem
$dockerExe = Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'
$dockerState = if (Test-Path $dockerExe) { 'yes' } else { 'no' }
$grpCount = @(Get-LocalGroupMember -Group 'docker-users').Count
$freeGb = [math]::Round((Get-PSDrive C).Free / 1GB, 1)
Write-Output ("OS={0}|BUILD={1}|DOMAIN={2}|DOCKER={3}|GRP={4}|FREEGB={5}GB" -f $os.Caption.Trim(), $os.BuildNumber, $cs.Domain, $dockerState, $grpCount, $freeGb)
PSEOF

    cat > "$TMP_DIR/verify.ps1" <<'PSEOF'
$ErrorActionPreference = 'SilentlyContinue'
$ver = ''
try { $out = (& docker --version) 2>$null } catch { $out = $null }
if ($LASTEXITCODE -eq 0 -and $out) { $ver = (@($out)[0]).ToString().Trim() }
$svc = Get-Service -Name com.docker.service
$svcState = if ($svc) { 'yes' } else { 'no' }
$proc = Get-Process -Name 'Docker Desktop', 'com.docker.backend'
$procState = if ($proc) { 'yes' } else { 'no' }
$grpEntry = Get-LocalGroupMember -Group 'docker-users' |
    Where-Object { $_.Name -like '*Domain Users*' } |
    Select-Object -First 1 -ExpandProperty Name
if (-not $grpEntry) { $grpEntry = 'none' }
Write-Output ("VER={0}|SVC={1}|PROC={2}|GRP={3}" -f $ver, $svcState, $procState, $grpEntry)
PSEOF

    printf 'Restart-Computer -Force\n' > "$TMP_DIR/restart.ps1"
}

run_remote_ps() {
    # $1 = pc ip, $2 = path to PowerShell script; stdout/stderr passthrough.
    local pc="$1" script="$2" rc=0
    WINRM_HOST="$pc" \
    WINRM_CONNECT_TIMEOUT="$CONNECT_TIMEOUT" \
    python3 "$TMP_DIR/winrm_exec.py" "$script" || rc=$?
    return "$rc"
}

parse_result_line() {
    # $1 = combined output; sets RESULT_STATE / RESULT_DETAIL.
    RESULT_STATE='UNKNOWN'
    RESULT_DETAIL='no [RESULT] STATE= line found in installer output'
    local line
    line="$(printf '%s\n' "$1" | grep -E '^\[RESULT\] STATE=' | tail -n 1 || true)"
    [[ -n "$line" ]] || return 0
    RESULT_STATE="$(sed -E 's/^\[RESULT\] STATE=([^ ]+).*/\1/' <<<"$line")"
    RESULT_DETAIL="$(sed -E 's/^.* detail=(.*)$/\1/' <<<"$line")"
}

write_pc_state() {
    # $1 pc, $2 state, $3 detail -> consumed by parent after parallel jobs end.
    printf '%s\t%s\n' "$2" "$3" > "$JOBS_DIR/$1.state"
}

# ---------------------------------------------------------------------------
# Per-PC workers
# ---------------------------------------------------------------------------

preflight_one() {
    local pc="$1" out rc=0 fields field key val
    declare -A F=()
    out="$(run_remote_ps "$pc" "$TMP_DIR/preflight.ps1")" || rc=$?
    if (( rc == 4 )); then
        printf '%-15s %-12s\n' "$pc" 'UNREACHABLE'
        write_pc_state "$pc" 'UNREACHABLE' 'tcp connect to port 5985 failed'
        return 0
    elif (( rc != 0 )); then
        printf '%-15s %-12s %s\n' "$pc" 'WINRM-ERROR' "(rc=$rc, see stderr above)"
        write_pc_state "$pc" 'WINRM_ERROR' "pywinrm returned rc=$rc"
        return 0
    fi
    while IFS= read -r field; do
        key="${field%%=*}"
        val="${field#*=}"
        [[ -n "$field" && "$val" != "$field" ]] && F["$key"]="$val"
    done < <(tr '|' '\n' <<<"$(printf '%s\n' "$out" | grep -E '^OS=' | tail -n 1)")
    if [[ -z "${F[OS]:-}" ]]; then
        printf '%-15s %-12s %s\n' "$pc" 'NO-DATA' 'preflight snippet produced no data'
        write_pc_state "$pc" 'NO_DATA' 'empty preflight response'
        return 0
    fi
    printf '%-15s %-12s %-28s %-6s %-11s %-7s %-8s %s\n' \
        "$pc" 'OK' "${F[OS]}" "${F[BUILD]}" "${F[DOMAIN]}" "${F[DOCKER]}" "${F[GRP]}" "${F[FREEGB]}"
    write_pc_state "$pc" 'OK' "os=${F[OS]} build=${F[BUILD]} domain=${F[DOMAIN]} docker=${F[DOCKER]} grp_members=${F[GRP]} free=${F[FREEGB]}"
}

run_installer_once() {
    # Shared by deploy_one; sets RESULT_STATE/RESULT_DETAIL from output.
    local pc="$1" out rc=0
    out="$(run_remote_ps "$pc" "$INSTALLER_PS")" || rc=$?
    parse_result_line "$out"
    printf '%s\n' "$out"
    if (( rc == 4 )); then
        RESULT_STATE='UNREACHABLE'
        RESULT_DETAIL='tcp connect to port 5985 failed'
        return 0
    elif (( rc != 0 )) && [[ "$RESULT_STATE" == 'UNKNOWN' ]]; then
        RESULT_STATE='REMOTE_ERROR'
        RESULT_DETAIL="installer run failed with pywinrm rc=$rc"
    fi
}

reboot_and_wait() {
    local pc="$1" waited=0 down_seen=0
    log "[$pc] issuing Restart-Computer -Force..."
    run_remote_ps "$pc" "$TMP_DIR/restart.ps1" >/dev/null 2>&1 || true
    while (( waited < REBOOT_WAIT_MAX )); do
        if port_up "$pc"; then
            if (( down_seen )); then
                sleep 15   # let WinRM/services settle before re-running installer
                log "[$pc] back online after ${waited}s."
                return 0
            fi
        else
            down_seen=1
        fi
        sleep "$REBOOT_POLL_INTERVAL"
        waited=$((waited + REBOOT_POLL_INTERVAL))
    done
    warn "[$pc] did not come back within ${REBOOT_WAIT_MAX}s."
    return 1
}

deploy_one() {
    local pc="$1"
    log "[$pc] running install-docker.ps1 remotely (this can take several minutes)..."
    run_installer_once "$pc"

    if [[ "$RESULT_STATE" == 'REBOOT_REQUIRED' ]]; then
        if (( AUTO_REBOOT )); then
            if ! reboot_and_wait "$pc"; then
                write_pc_state "$pc" 'FAILED' 'did not come back after automatic reboot'
                return 0
            fi
            log "[$pc] re-running installer after reboot..."
            run_installer_once "$pc"
        else
            write_pc_state "$pc" 'NEEDS_REBOOT' "$RESULT_DETAIL"
            log "[$pc] NEEDS_REBOOT: $RESULT_DETAIL (use --auto-reboot to automate)"
            return 0
        fi
    fi
    write_pc_state "$pc" "$RESULT_STATE" "$RESULT_DETAIL"
}

verify_one() {
    local pc="$1" out rc=0 line verdict
    declare -A F=()
    out="$(run_remote_ps "$pc" "$TMP_DIR/verify.ps1")" || rc=$?
    if (( rc == 4 )); then
        printf '%-15s %-6s %s\n' "$pc" 'FAIL' 'unreachable (tcp 5985)'
        write_pc_state "$pc" 'FAIL' 'unreachable'
        return 0
    elif (( rc != 0 )); then
        printf '%-15s %-6s %s\n' "$pc" 'FAIL' "winrm error (rc=$rc)"
        write_pc_state "$pc" 'FAIL' "pywinrm rc=$rc"
        return 0
    fi
    line="$(printf '%s\n' "$out" | grep -E '^VER=' | tail -n 1)"
    while IFS= read -r pair; do
        [[ -n "$pair" ]] && F["${pair%%=*}"]="${pair#*=}"
    done < <(tr '|' '\n' <<<"$line")
    if [[ -n "${F[VER]:-}" && "${F[GRP]:-}" != '' && "${F[GRP]}" != 'none' \
          && ( "${F[SVC]:-}" == 'yes' || "${F[PROC]:-}" == 'yes' ) ]]; then
        verdict='PASS'
    else
        verdict='FAIL'
    fi
    printf '%-15s %-6s docker=%-24s svc=%-4s proc=%-4s domain_users_in_group=%s\n' \
        "$pc" "$verdict" "${F[VER]:-none}" "${F[SVC]:-?}" "${F[PROC]:-?}" "${F[GRP]:-?}"
    write_pc_state "$pc" "$verdict" "ver=${F[VER]:-} svc=${F[SVC]:-} proc=${F[PROC]:-} grp=${F[GRP]:-}"
}

# ---------------------------------------------------------------------------
# Parallel runner + collectors
# ---------------------------------------------------------------------------

run_all() {
    # $1 = worker function name; runs TARGETS in parallel bounded by CONCURRENCY.
    local fn="$1" pc
    mkdir -p "$JOBS_DIR"
    for pc in "${TARGETS[@]}"; do
        (
            "$fn" "$pc" >"$JOBS_DIR/$pc.out" 2>"$JOBS_DIR/$pc.err"
            echo $? >"$JOBS_DIR/$pc.rc"
        ) &
        while (( $(jobs -rp | wc -l) >= CONCURRENCY )); do
            sleep 0.2
        done
    done
    wait
}

collect_states() {
    # Echoes "<state>\t<detail>" lines in target order; returns count of bad states.
    local pc bad=0 state detail
    for pc in "${TARGETS[@]}"; do
        if [[ -f "$JOBS_DIR/$pc.state" ]]; then
            state="$(cut -f1 "$JOBS_DIR/$pc.state")"
            detail="$(cut -f2 "$JOBS_DIR/$pc.state")"
        else
            state='CRASHED'
            detail="worker crashed (see $JOBS_DIR/$pc.err)"
        fi
        log "$state"$'\t'"$pc"$'\t'"$detail"
        case "$state" in
            OK|PASS|NEEDS_REBOOT) : ;;
            *) bad=$((bad + 1)) ;;
        esac
    done
    return "$bad"
}

show_pc_output() {
    # Print each PC's captured stdout (rows/installer logs) in target order,
    # plus stderr excerpt when the worker recorded a failure.
    local pc
    for pc in "${TARGETS[@]}"; do
        [[ -s "$JOBS_DIR/$pc.out" ]] && cat "$JOBS_DIR/$pc.out"
        if [[ -f "$JOBS_DIR/$pc.rc" ]] && [[ "$(cat "$JOBS_DIR/$pc.rc")" != '0' ]]; then
            [[ -s "$JOBS_DIR/$pc.err" ]] && sed 's/^/[stderr] /' "$JOBS_DIR/$pc.err"
        fi
    done
}

# ---------------------------------------------------------------------------
# Subcommand drivers
# ---------------------------------------------------------------------------

do_preflight() {
    if (( DRY_RUN )); then
        log "[dry-run] preflight performs read-only checks; executing them for real now."
    fi
    log "Preflight (read-only) against ${#TARGETS[@]} PC(s):"
    printf '%-15s %-12s %-28s %-6s %-11s %-7s %-8s %s\n' \
        'PC' 'STATUS' 'OS' 'BUILD' 'DOMAIN' 'DOCKER' 'D-USERS' 'FREE-C'
    run_all preflight_one
    show_pc_output
    local bad=0
    collect_states || bad=$?
    if (( bad > 0 )); then
        warn "$bad PC(s) unreachable or errored during preflight."
        exit 1
    fi
    exit 0
}

plan_deploy() {
    local pc
    for pc in "${TARGETS[@]}"; do
        log "[$pc] (dry-run) would execute install-docker.ps1 remotely:"
        log "[$pc] (dry-run)   transport: WinRM NTLM :$WINRM_PORT, powershell -EncodedCommand (base64 UTF16LE)"
        log "[$pc] (dry-run)   on REBOOT_REQUIRED: $( ((AUTO_REBOOT)) && echo 'restart + wait (max 10 min) + re-run installer' || echo 'mark as needs-reboot (no auto-reboot)' )"
    done
    log "[dry-run] no state-changing remote calls were made."
    exit 0
}

do_deploy() {
    (( DRY_RUN )) && plan_deploy
    log "Deploying Docker Desktop to ${#TARGETS[@]} PC(s), concurrency=$CONCURRENCY, auto-reboot=$( ((AUTO_REBOOT)) && echo on || echo off ):"
    run_all deploy_one
    log ''
    log '=== Per-PC installer output ==='
    show_pc_output
    local bad=0 needs_reboot=0 state pc detail ok_count=0
    log ''
    log '=== Deploy summary ==='
    while IFS=$'\t' read -r st pc dtl; do
        case "$st" in
            OK)           log "  [OK]            $pc"; ok_count=$((ok_count + 1)) ;;
            NEEDS_REBOOT) log "  [NEEDS-REBOOT]  $pc  ($dtl)"; needs_reboot=$((needs_reboot + 1)) ;;
            *)            log "  [$st]  $pc  ($dtl)"; bad=$((bad + 1)) ;;
        esac
    done < <(collect_states || true)
    (( needs_reboot > 0 )) && log "NOTE: $needs_reboot PC(s) need a manual reboot to finish installation."
    if (( bad > 0 )); then
        warn "$bad PC(s) FAILED during deploy."
        exit 1
    fi
    log "Deploy finished: $ok_count OK, $needs_reboot pending reboot, 0 failures."
    exit 0
}

do_verify() {
    if (( DRY_RUN )); then
        local pc
        for pc in "${TARGETS[@]}"; do
            log "[$pc] (dry-run) would check: docker --version, 'Domain Users' in docker-users group, Docker Desktop service/process."
        done
        log "[dry-run] no remote calls were made."
        exit 0
    fi
    log "Verifying Docker Desktop on ${#TARGETS[@]} PC(s):"
    printf '%-15s %-6s %s\n' 'PC' 'RESULT' 'CHECKS (docker version / service / process / Domain Users in group)'
    run_all verify_one
    show_pc_output
    local bad=0
    collect_states || bad=$?
    if (( bad > 0 )); then
        warn "VERIFY FAILED on $bad PC(s)."
        exit 1
    fi
    log "VERIFY PASS on all ${#TARGETS[@]} PC(s)."
    exit 0
}

# ---------------------------------------------------------------------------
# Argument parsing + main
# ---------------------------------------------------------------------------

resolve_targets() {
    if (( ${#@} > 0 )); then
        TARGETS=("$@")
    elif [[ -n "${PCS:-}" ]]; then
        read -r -a TARGETS <<<"$PCS"
    else
        TARGETS=("${DEFAULT_PCS[@]}")
    fi
    local pc
    for pc in "${TARGETS[@]}"; do
        [[ "$pc" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || die 2 "'$pc' does not look like an IPv4 address."
    done
}

main() {
    local args=()
    while (( $# > 0 )); do
        case "$1" in
            --dry-run)      DRY_RUN=1 ;;
            --auto-reboot)  AUTO_REBOOT=1 ;;
            --concurrency)
                shift
                [[ "${1:-}" =~ ^[0-9]+$ && "$1" -ge 1 ]] || die 2 "--concurrency expects a positive integer."
                CONCURRENCY="$1"
                ;;
            --help|-h) usage; exit 0 ;;
            -*)
                warn "unknown option: $1"
                usage
                exit 2
                ;;
            *)
                if [[ -z "$SUBCOMMAND" ]]; then SUBCOMMAND="$1"; else args+=("$1"); fi
                ;;
        esac
        shift
    done

    case "$SUBCOMMAND" in
        preflight|deploy|verify) : ;;
        *) usage >&2; die 2 "subcommand required: preflight | deploy | verify" ;;
    esac

    resolve_targets "${args[@]+"${args[@]}"}"

    TMP_DIR="$(mktemp -d)"
    trap cleanup EXIT
    JOBS_DIR="$TMP_DIR/jobs"

    load_credentials

    if [[ "$SUBCOMMAND" == 'deploy' && ! -f "$INSTALLER_PS" ]]; then
        die 2 "installer script not found next to this script: $INSTALLER_PS"
    fi

    write_helper_files

    case "$SUBCOMMAND" in
        preflight) do_preflight ;;
        deploy)    do_deploy ;;
        verify)    do_verify ;;
    esac
}

main "$@"
