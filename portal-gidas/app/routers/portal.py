"""Portal routes: dashboard, API."""

from __future__ import annotations

from typing import List

from fastapi import APIRouter, Request
from fastapi.responses import HTMLResponse, JSONResponse, RedirectResponse, Response
from starlette.status import HTTP_302_FOUND, HTTP_401_UNAUTHORIZED

from app.auth import get_user_from_cookie
from app.config import AppConfig
from app.models import ToolResponse, UserInfo

router = APIRouter()


def _filter_tools(config: AppConfig, user_groups: List[str]) -> list:
    """Return only tools that match user's groups."""
    result = []
    for tool in config.tools:
        user_set = set(user_groups)
        tool_set = set(tool.groups)
        if user_set & tool_set:
            result.append(tool)
    return result


@router.get("/", response_class=HTMLResponse)
async def dashboard(request: Request):
    """Render dashboard with tools filtered by user groups."""
    config = request.app.state.config
    settings = request.app.state.settings
    templates = request.app.state.templates

    user = get_user_from_cookie(request, settings.jwt_secret)
    if not user:
        return RedirectResponse(url="/login", status_code=HTTP_302_FOUND)

    username = user.get("sub", "")
    groups = user.get("groups", [])
    tools = _filter_tools(config, groups)

    return templates.TemplateResponse(
        "dashboard.html",
        {
            "request": request,
            "config": config,
            "username": username,
            "groups": groups,
            "tools": tools,
        },
    )


@router.get("/api/me")
async def api_me(request: Request):
    """Return authenticated user info as JSON."""
    settings = request.app.state.settings
    user = get_user_from_cookie(request, settings.jwt_secret)
    if not user:
        return JSONResponse(
            status_code=HTTP_401_UNAUTHORIZED,
            content={"detail": "Not authenticated"},
        )
    return UserInfo(
        username=user.get("sub", ""),
        groups=user.get("groups", []),
    )


# ── Launchers SSH descargables (acceso vía túnel Cloudflare) ─────────────

_SSH_SH = """#!/bin/bash
# =============================================
# VM de desarrollo Telepark — SSH remoto
# (vía túnel Cloudflare + cloudflared)
# =============================================
HOST="__SSH_HOST__"

CF="cloudflared"
if ! command -v cloudflared &> /dev/null; then
    echo ">> Descargando cloudflared (una sola vez)..."
    ARCH="$(uname -m)"
    case "$ARCH" in
        x86_64) BIN="cloudflared-linux-amd64" ;;
        aarch64|arm64) BIN="cloudflared-linux-arm64" ;;
        *) echo "Arquitectura no soportada: $ARCH"; exit 1 ;;
    esac
    CF="$HOME/.local/bin/cloudflared"
    mkdir -p "$HOME/.local/bin"
    curl -L -o "$CF" "https://github.com/cloudflare/cloudflared/releases/latest/download/$BIN"
    chmod +x "$CF"
fi

read -p "Usuario de dominio (ej. penalvam): " USUARIO
ssh -o ProxyCommand="$CF access ssh --hostname $HOST" "${USUARIO}@$HOST"
"""

_SSH_CMD = """@echo off
rem =============================================
rem VM de desarrollo Telepark — SSH remoto
rem (vía túnel Cloudflare + cloudflared)
rem =============================================
set HOST=__SSH_HOST__
set CF=%TEMP%\\cloudflared.exe

where cloudflared >nul 2>nul
if errorlevel 1 (
    if not exist "%CF%" (
        echo >> Descargando cloudflared...
        curl -L -o "%CF%" https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe
    )
) else (
    set CF=cloudflared
)

set /p USUARIO=Usuario de dominio (ej. penalvam): 
ssh -o "ProxyCommand=%CF% access ssh --hostname %HOST%" %USUARIO%@%HOST%
pause
"""

_SSH_TUNNEL_URL_FILE = "/opt/portal-gidas/ssh-tunnel-url.txt"


def _current_ssh_host() -> str:
    """Leer el hostname actual del túnel SSH (archivo escrito por el servicio)."""
    try:
        with open(_SSH_TUNNEL_URL_FILE) as f:
            url = f.read().strip()
        return url.replace("https://", "").rstrip("/")
    except Exception:
        return ""


def _require_login(request: Request):
    settings = request.app.state.settings
    user = get_user_from_cookie(request, settings.jwt_secret)
    if not user:
        return None
    return user


@router.get("/download/ssh-telepark")
async def download_ssh_sh(request: Request):
    """Descargar launcher SSH (Linux/macOS) con el hostname actual del túnel."""
    if not _require_login(request):
        return RedirectResponse(url="/login", status_code=HTTP_302_FOUND)
    host = _current_ssh_host()
    if not host:
        return JSONResponse(status_code=503, content={"detail": "Túnel SSH no disponible"})
    return Response(
        content=_SSH_SH.replace("__SSH_HOST__", host),
        media_type="application/x-sh",
        headers={"Content-Disposition": "attachment; filename=ssh-telepark.sh"},
    )


@router.get("/download/ssh-telepark-win")
async def download_ssh_cmd(request: Request):
    """Descargar launcher SSH (Windows) con el hostname actual del túnel."""
    if not _require_login(request):
        return RedirectResponse(url="/login", status_code=HTTP_302_FOUND)
    host = _current_ssh_host()
    if not host:
        return JSONResponse(status_code=503, content={"detail": "Túnel SSH no disponible"})
    return Response(
        content=_SSH_CMD.replace("__SSH_HOST__", host),
        media_type="application/octet-stream",
        headers={"Content-Disposition": "attachment; filename=ssh-telepark.cmd"},
    )
