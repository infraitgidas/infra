"""FastAPI application factory."""

from __future__ import annotations

import os
from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.responses import RedirectResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.status import HTTP_302_FOUND

from app.config import AppConfig, Settings, load_config
from app.routers import auth, portal, proxy
from app.services.rate_limiter import get_stats

BASE_DIR = Path(__file__).resolve().parent
TEMPLATES_DIR = BASE_DIR / "templates"
STATIC_DIR = BASE_DIR / "static"


class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    """Add security headers to all responses."""

    async def dispatch(self, request: Request, call_next):
        response = await call_next(request)
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["X-XSS-Protection"] = "1; mode=block"
        response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
        response.headers["Permissions-Policy"] = "geolocation=(), microphone=(), camera=()"
        response.headers["Cache-Control"] = "no-store"
        return response


def create_app() -> FastAPI:
    settings = Settings()

    config_path = settings.config_path
    if not os.path.isabs(config_path):
        config_path = str(BASE_DIR.parent / config_path)

    app_config = load_config(config_path)

    app = FastAPI(
        title="Portal GIDAS",
        version="2.0.0",
        description="Portal de acceso unificado para herramientas GIDAS",
    )

    # Add security middleware
    app.add_middleware(SecurityHeadersMiddleware)

    # Store config in app state
    app.state.config = app_config
    app.state.settings = settings

    # Mount static files
    app.mount("/static", StaticFiles(directory=str(STATIC_DIR)), name="static")

    # Templates
    templates = Jinja2Templates(directory=str(TEMPLATES_DIR))
    app.state.templates = templates

    # Include routers
    app.include_router(auth.router)
    app.include_router(portal.router)
    app.include_router(proxy.router)

    # Rate limit stats endpoint (for monitoring)
    @app.get("/security/stats")
    async def security_stats():
        return JSONResponse(get_stats())

    @app.exception_handler(401)
    async def unauthorized_handler(request: Request, exc):
        return RedirectResponse(url="/login", status_code=HTTP_302_FOUND)

    return app


app = create_app()
