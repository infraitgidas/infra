"""Auth routes: login, logout."""

from __future__ import annotations

from fastapi import APIRouter, Form, Request, Response
from fastapi.responses import HTMLResponse, RedirectResponse
from starlette.status import HTTP_302_FOUND

from app.auth import COOKIE_NAME, create_token, get_user_from_cookie
from app.services.ldap_service import authenticate, AuthenticationError, ConnectionError
from app.services.rate_limiter import (
    check_rate_limit,
    register_failed_attempt,
    register_successful_attempt,
)

router = APIRouter()


@router.get("/login", response_class=HTMLResponse)
async def login_form(request: Request):
    """Show login form. If already authenticated, redirect to dashboard."""
    config = request.app.state.config
    settings = request.app.state.settings
    templates = request.app.state.templates

    user = get_user_from_cookie(request, settings.jwt_secret)
    if user:
        return RedirectResponse(url="/", status_code=HTTP_302_FOUND)

    error = request.query_params.get("error")
    return templates.TemplateResponse(
        "login.html",
        {"request": request, "config": config, "error": error},
    )


@router.post("/login")
async def login_post(
    request: Request,
    response: Response,
    username: str = Form(...),
    password: str = Form(...),
):
    """Process login credentials with rate limiting."""
    config = request.app.state.config
    settings = request.app.state.settings
    ldap = config.ldap

    # Check rate limit
    is_blocked, error_msg = check_rate_limit(request, username)
    if is_blocked:
        return RedirectResponse(
            url=f"/login?error=3",  # error 3 = blocked
            status_code=HTTP_302_FOUND,
        )

    try:
        user, groups = authenticate(
            host=ldap.host,
            port=ldap.port,
            bind_dn=ldap.bind_dn,
            bind_password=settings.ldap_bind_password,
            base_dn=ldap.base_dn,
            search_filter=ldap.user_search_filter,
            group_attribute=ldap.group_attribute,
            username=username,
            password=password,
            use_ssl=ldap.use_ssl,
        )
    except AuthenticationError:
        register_failed_attempt(request, username)
        return RedirectResponse(url="/login?error=1", status_code=HTTP_302_FOUND)
    except ConnectionError:
        # Connection error is not a login attempt, don't count
        return RedirectResponse(url="/login?error=2", status_code=HTTP_302_FOUND)

    # Successful login — clear failed attempts
    register_successful_attempt(request, username)

    token = create_token(
        username=user,
        groups=groups,
        secret=settings.jwt_secret,
        duration_hours=config.portal.session_duration_hours,
    )

    resp = RedirectResponse(url="/", status_code=HTTP_302_FOUND)
    resp.set_cookie(
        key=COOKIE_NAME,
        value=token,
        max_age=config.portal.session_duration_hours * 3600,
        httponly=True,
        samesite="lax",
        path="/",
    )
    return resp


@router.get("/logout")
async def logout(request: Request):
    """Clear session cookie."""
    resp = RedirectResponse(url="/login", status_code=HTTP_302_FOUND)
    resp.delete_cookie(key=COOKIE_NAME, path="/")
    return resp
