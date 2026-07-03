"""Proxy routes: forward requests to internal tools (authenticated)."""

from __future__ import annotations

import httpx
from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import RedirectResponse, Response
from starlette.status import HTTP_302_FOUND

from app.auth import get_user_from_cookie

router = APIRouter()

# HTTP client: no verify SSL (self-signed certs internal), follow redirects
client = httpx.AsyncClient(verify=False, follow_redirects=False, timeout=30.0)


def _find_tool(request: Request, tool_name: str):
    config = request.app.state.config
    for tool in config.tools:
        if tool.name.lower() == tool_name.lower():
            return tool
    return None


def _rewrite_url(url: str, base_url: str, tool_name: str) -> str:
    """Rewrite redirect URLs from internal to proxy paths."""
    from urllib.parse import urlparse
    parsed = urlparse(url)
    if parsed.hostname and (parsed.hostname.endswith(".gidas.local") or parsed.hostname in ("192.168.1.205", "192.168.1.14", "192.168.1.1")):
        # Rewrite to proxy path
        original_base = f"{parsed.scheme}://{parsed.hostname}"
        if parsed.port:
            original_base += f":{parsed.port}"
        old_path = parsed.path
        # Make sure we don't double up
        if old_path.startswith(f"/proxy/{tool_name.lower()}"):
            return url
        new_path = f"/proxy/{tool_name.lower()}{old_path}"
        if parsed.query:
            new_path += f"?{parsed.query}"
        return new_path
    return url


async def _proxy(tool, request: Request, path: str):
    """Core proxy logic."""
    settings = request.app.state.settings
    user = get_user_from_cookie(request, settings.jwt_secret)
    if not user:
        return RedirectResponse(url="/login", status_code=HTTP_302_FOUND)

    base = tool.url.rstrip("/")
    target_url = f"{base}/{path}" if path else base
    query = request.url.query
    if query:
        target_url += f"?{query}"

    body = await request.body()
    headers = {}
    for key, value in request.headers.items():
        kl = key.lower()
        if kl not in ("host", "connection", "transfer-encoding", "content-length"):
            headers[key] = value
    headers.pop("cookie", None)

    try:
        response = await client.request(
            method=request.method, url=target_url,
            headers=headers, content=body or None,
        )
    except httpx.ConnectError:
        raise HTTPException(status_code=502, detail=f"Conexión rechazada a {tool.name}")
    except httpx.TimeoutException:
        raise HTTPException(status_code=504, detail=f"Timeout de {tool.name}")
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"Error proxy {tool.name}: {e}")

    resp_headers = {}
    for k, v in response.headers.items():
        kl = k.lower()
        if kl not in ("content-encoding", "transfer-encoding", "connection", "keep-alive"):
            # Rewrite Location headers for redirects
            if kl == "location":
                v = _rewrite_url(v, base, tool.name)
            # Rewrite Content-Security-Policy if present
            if kl == "content-security-policy":
                v = v.replace(base, "")
            resp_headers[k] = v

    return Response(
        content=response.content,
        status_code=response.status_code,
        headers=resp_headers,
    )


@router.api_route("/proxy/{tool_name}/{path:path}",
                  methods=["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"])
async def proxy_path(request: Request, tool_name: str, path: str):
    tool = _find_tool(request, tool_name)
    if not tool:
        raise HTTPException(status_code=404, detail=f"Tool '{tool_name}' no encontrada")
    if not tool.proxy:
        raise HTTPException(status_code=403, detail=f"Proxy no habilitado para {tool_name}")
    return await _proxy(tool, request, path)


@router.api_route("/proxy/{tool_name}",
                  methods=["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"])
async def proxy_root(request: Request, tool_name: str):
    tool = _find_tool(request, tool_name)
    if not tool:
        raise HTTPException(status_code=404, detail=f"Tool '{tool_name}' no encontrada")
    if not tool.proxy:
        raise HTTPException(status_code=403, detail=f"Proxy no habilitado para {tool_name}")
    return await _proxy(tool, request, "")
