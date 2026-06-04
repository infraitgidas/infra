#!/bin/bash
# ================================================================
# run.sh — Wrapper for gidas-identity CLI on pve-ad
# ================================================================
# Usage:
#   ./run.sh --help
#   ./run.sh user create --name "Juan Pérez" --username jperez --role becario --proyecto Telepark
#   ./run.sh user list
#   ./run.sh group list --prefix G-
#
# SSHes into pve-ad and runs the command via docker-compose exec.
#
# Environment variables:
#   PVE_AD_HOST  — SSH target (default: pve-ad)
#   COMPOSE_DIR  — docker-compose directory (default: /opt/identity-dashboard)
# ================================================================

set -e

PVE_AD_HOST="${PVE_AD_HOST:-pve-ad}"
COMPOSE_DIR="${COMPOSE_DIR:-/opt/identity-dashboard}"

if [ $# -eq 0 ]; then
    echo "Usage: $0 <command> [args...]"
    echo ""
    echo "Runs gidas-identity commands on ${PVE_AD_HOST}."
    echo ""
    echo "Examples:"
    echo "  $0 --help"
    echo "  $0 user create --name 'Juan Pérez' --username jperez --role becario --proyecto Telepark"
    echo "  $0 user list"
    echo "  $0 group list --prefix G-"
    echo "  $0 hbac list --user jperez"
    echo ""
    echo "Environment:"
    echo "  PVE_AD_HOST=${PVE_AD_HOST}  (set to change target)"
    echo "  COMPOSE_DIR=${COMPOSE_DIR}  (set to change working dir)"
    exit 1
fi

exec ssh "${PVE_AD_HOST}" \
    "cd ${COMPOSE_DIR} && docker-compose exec -T gidas-identity python -m app $*"
