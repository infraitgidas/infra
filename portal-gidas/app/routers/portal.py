"""Portal routes: dashboard, API."""

from __future__ import annotations

from typing import List

from fastapi import APIRouter, Request
from fastapi.responses import HTMLResponse, JSONResponse, RedirectResponse
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
