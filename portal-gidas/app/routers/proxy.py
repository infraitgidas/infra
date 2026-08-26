"""Proxy routes: forward requests to internal tools (authenticated).

Supports both HTTP (httpx) and WebSocket (websockets) forwarding.
"""

from __future__ import annotations

import asyncio
import ssl

import httpx
import websockets
from fastapi import APIRouter, HTTPException, Request, WebSocket, WebSocketDisconnect
from fastapi.responses import RedirectResponse, Response
from starlette.status import HTTP_302_FOUND

from app.auth import COOKIE_NAME, decode_token, get_user_from_cookie

router = APIRouter()

client = httpx.AsyncClient(verify=False, follow_redirects=True, timeout=30.0)


def _find_tool(request: Request, tool_name: str):
    config = request.app.state.config
    for tool in config.tools:
        if tool.slug and tool.slug.lower() == tool_name.lower():
            return tool
        if tool.name.lower() == tool_name.lower():
            return tool
    return None


def _rewrite_url(url: str, slug: str) -> str:
    """Rewrite redirect URLs from internal to proxy paths."""
    from urllib.parse import urlparse
    if not url:
        return ""
    prefix = f"/proxy/{slug.lower()}"
    if url.startswith("/"):
        if url.startswith(prefix):
            return url.rstrip("/") or "/"
        return f"{prefix}{url}".rstrip("/") or "/"
    parsed = urlparse(url)
    internal_domains = (".gidas.local", "192.168.1.205", "192.168.1.14", "192.168.1.1", "192.168.1.48")
    if parsed.hostname and any(h in str(parsed.hostname) for h in internal_domains):
        old_path = parsed.path
        new_path = f"{prefix}{old_path}"
        new_path = new_path.rstrip("/") or "/"
        if parsed.query:
            new_path += f"?{parsed.query}"
        return new_path
    return url


# ── HTTP proxy ──────────────────────────────────────────────────────────


async def _proxy(tool, request: Request, path: str):
    settings = request.app.state.settings
    user = get_user_from_cookie(request, settings.jwt_secret)
    if not user:
        return RedirectResponse(url="/login", status_code=HTTP_302_FOUND)

    base = tool.url.rstrip("/")
    target_url = f"{base}/{path}" if path else base + "/"
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
        if kl not in ("content-encoding", "transfer-encoding", "connection", "keep-alive", "content-length"):
            if kl == "location":
                v = _rewrite_url(v, tool.slug or tool.name.lower())
            if v:
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


# ── WebSocket proxy ─────────────────────────────────────────────────────


def _ws_backend_url(tool, path: str, query: str = "") -> str:
    """Build ws:// or wss:// backend URL from the tool's http(s) URL."""
    base = tool.url.rstrip("/")
    if base.startswith("https://"):
        scheme, host = "wss", base[len("https://"):]
    elif base.startswith("http://"):
        scheme, host = "ws", base[len("http://"):]
    else:
        scheme, host = "wss", base
    url = f"{scheme}://{host}/{path}" if path else f"{scheme}://{host}"
    if query:
        url += f"?{query}"
    return url


def _ws_ssl_context() -> ssl.SSLContext:
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    return ctx


async def _ws_proxy(tool, websocket: WebSocket, path: str):
    settings = websocket.app.state.settings

    # Auth: reuse the portal session cookie (JWT)
    token = websocket.cookies.get(COOKIE_NAME)
    if not token:
        await websocket.close(code=4401)
        return
    try:
        decode_token(token, settings.jwt_secret)
    except Exception:
        await websocket.close(code=4401)
        return

    query = websocket.url.query if hasattr(websocket, "url") else ""
    ws_url = _ws_backend_url(tool, path, query)

    await websocket.accept()

    try:
        async with websockets.connect(ws_url, ssl=_ws_ssl_context()) as backend:
            async def client_to_backend():
                try:
                    while True:
                        msg = await websocket.receive()
                        if msg["type"] == "websocket.receive":
                            if msg.get("text") is not None:
                                await backend.send(msg["text"])
                            elif msg.get("bytes") is not None:
                                await backend.send(msg["bytes"])
                        elif msg["type"] == "websocket.disconnect":
                            break
                except WebSocketDisconnect:
                    pass
                except Exception:
                    pass

            async def backend_to_client():
                try:
                    async for m in backend:
                        if isinstance(m, str):
                            await websocket.send_text(m)
                        else:
                            await websocket.send_bytes(m)
                except Exception:
                    pass

            await asyncio.gather(client_to_backend(), backend_to_client())
    except Exception:
        pass
    finally:
        try:
            await websocket.close()
        except Exception:
            pass


@router.websocket("/proxy/{tool_name}/{path:path}")
async def proxy_ws_path(websocket: WebSocket, tool_name: str, path: str):
    tool = _find_tool(websocket, tool_name)  # type: ignore[arg-type]
    if not tool or not tool.proxy:
        await websocket.close(code=4404)
        return
    await _ws_proxy(tool, websocket, path)


@router.websocket("/proxy/{tool_name}")
async def proxy_ws_root(websocket: WebSocket, tool_name: str):
    tool = _find_tool(websocket, tool_name)  # type: ignore[arg-type]
    if not tool or not tool.proxy:
        await websocket.close(code=4404)
        return
    await _ws_proxy(tool, websocket, "")
