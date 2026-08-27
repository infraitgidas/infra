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


# ── Launchers SSH descargables (acceso vía Twingate/VPN) ────────────────

_SSH_SH = """#!/bin/bash
# =============================================
# VM de desarrollo Telepark — acceso SSH
# Requiere Twingate (acceso remoto) o LAN GIDAS
# =============================================
HOST="192.168.1.48"
echo "=== VM Telepark (SSH) ==="
read -p "Usuario de dominio (ej. penalvam): " USUARIO
ssh -o StrictHostKeyChecking=accept-new "${USUARIO}@gdc01.local@${HOST}"
"""

_SSH_CMD = """@echo off
rem =============================================
rem VM de desarrollo Telepark — acceso SSH
rem Requiere Twingate (acceso remoto) o LAN GIDAS
rem =============================================
echo === VM Telepark (SSH) ===
set /p USUARIO=Usuario de dominio (ej. penalvam):
ssh %USUARIO%@gdc01.local@192.168.1.48
pause
"""


def _require_login(request: Request):
    settings = request.app.state.settings
    user = get_user_from_cookie(request, settings.jwt_secret)
    if not user:
        return None
    return user


@router.get("/download/ssh-telepark")
async def download_ssh_sh(request: Request):
    """Descargar launcher SSH (Linux/macOS)."""
    if not _require_login(request):
        return RedirectResponse(url="/login", status_code=HTTP_302_FOUND)
    return Response(
        content=_SSH_SH,
        media_type="application/x-sh",
        headers={"Content-Disposition": "attachment; filename=ssh-telepark.sh"},
    )


@router.get("/download/ssh-telepark-win")
async def download_ssh_cmd(request: Request):
    """Descargar launcher SSH (Windows)."""
    if not _require_login(request):
        return RedirectResponse(url="/login", status_code=HTTP_302_FOUND)
    return Response(
        content=_SSH_CMD,
        media_type="application/octet-stream",
        headers={"Content-Disposition": "attachment; filename=ssh-telepark.cmd"},
    )
