"""Proxy routes: forward requests to internal tools (authenticated).

Supports both HTTP (httpx) and WebSocket (websockets) forwarding.
"""

from __future__ import annotations

import asyncio
import ssl

import httpx
import websockets
from fastapi import APIRouter, HTTPException, Request, WebSocket, WebSocketDisconnect
from fastapi.responses import HTMLResponse, RedirectResponse, Response
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


def _rewrite_url(url: str, prefix: str) -> str:
    """Rewrite redirect URLs from internal to proxy paths."""
    from urllib.parse import urlparse
    if not url:
        return ""
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

    # Reescribir Origin al del backend (Cockpit exige Origin == Host también en HTTP)
    from urllib.parse import urlparse
    _p = urlparse(tool.url)
    headers["Origin"] = f"{_p.scheme}://{_p.netloc}"

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
                v = _rewrite_url(v, getattr(tool, "proxy_prefix", None) or f"/proxy/{tool.slug or tool.name.lower()}")
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

    # Subprotocol negotiation (Cockpit/ttyd requieren uno)
    subprotocols = []
    sec = websocket.headers.get("sec-websocket-protocol", "")
    if sec:
        subprotocols = [s.strip() for s in sec.split(",") if s.strip()]

    # Origin del backend (Cockpit exige Origin == Host; sin él devuelve 403)
    from urllib.parse import urlparse
    _p = urlparse(tool.url)
    backend_origin = f"{_p.scheme}://{_p.netloc}"

    # Conectar al backend PRIMERO para negociar el subprotocolo
    # `ssl` solo aplica a wss:// (websockets 14+ lo rechaza en ws://).
    try:
        ssl_ctx = _ws_ssl_context() if ws_url.startswith("wss://") else None
        backend = await websockets.connect(
            ws_url, ssl=ssl_ctx,
            subprotocols=subprotocols or None,
            additional_headers={"Origin": backend_origin},
        )
    except Exception:
        await websocket.close(code=4402)
        return

    negotiated = getattr(backend, "subprotocol", None)
    await websocket.accept(subprotocol=negotiated)

    try:
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
            await backend.close()
        except Exception:
            pass
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


# ── Proxy dinámico de puertos (VM Telepark) ─────────────────────────────
# Permite revisar despliegues en cualquier puerto de la VM de desarrollo:
#   https://<portal>/port/3000/  →  http://192.168.1.48:3000/

VM_PORT_HOST = "192.168.1.48"   # VM de desarrollo Telepark
TELEPARK_GROUP = "PROY-Telepark"


def _port_tool(port: int):
    """Tool virtual para proxear un puerto de la VM."""
    from types import SimpleNamespace
    return SimpleNamespace(
        url=f"http://{VM_PORT_HOST}:{port}",
        name=f"Port {port}",
        slug=f"port-{port}",
        proxy_prefix=f"/port/{port}",
    )


def _telepark_user(request):
    settings = request.app.state.settings
    user = get_user_from_cookie(request, settings.jwt_secret)
    if not user or TELEPARK_GROUP not in user.get("groups", []):
        return None
    return user


@router.api_route("/port/{port}/{path:path}",
                  methods=["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"])
async def proxy_port(request: Request, port: int, path: str):
    if not _telepark_user(request):
        return RedirectResponse(url="/login", status_code=HTTP_302_FOUND)
    if not (1 <= port <= 65535):
        raise HTTPException(status_code=400, detail="Puerto inválido")
    return await _proxy(_port_tool(port), request, path)


@router.websocket("/port/{port}/{path:path}")
async def proxy_port_ws(websocket: WebSocket, port: int, path: str):
    settings = websocket.app.state.settings
    token = websocket.cookies.get(COOKIE_NAME)
    if not token:
        await websocket.close(code=4401)
        return
    try:
        user = decode_token(token, settings.jwt_secret)
    except Exception:
        await websocket.close(code=4401)
        return
    if TELEPARK_GROUP not in user.get("groups", []):
        await websocket.close(code=4403)
        return
    if not (1 <= port <= 65535):
        await websocket.close(code=4400)
        return
    await _ws_proxy(_port_tool(port), websocket, path)


# ── Raíz sin path y launcher ────────────────────────────────────────────
# `/port/8080` (sin trailing slash) y `/port/` (página para ingresar el puerto).

@router.api_route("/port/{port}",
                  methods=["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"])
async def proxy_port_root(request: Request, port: int):
    return await proxy_port(request, port, "")


@router.websocket("/port/{port}")
async def proxy_port_ws_root(websocket: WebSocket, port: int):
    await proxy_port_ws(websocket, port, "")


_PORT_LAUNCHER_HTML = """<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Navegador — VM Telepark</title>
<style>
  body { font-family: system-ui, sans-serif; background:#0f172a; color:#e2e8f0;
         display:flex; align-items:center; justify-content:center; min-height:100vh; margin:0; }
  .box { background:#1e293b; padding:2rem 2.5rem; border-radius:1rem; text-align:center;
         box-shadow:0 10px 30px rgba(0,0,0,.4); max-width:420px; }
  h1 { font-size:1.4rem; margin:0 0 .5rem; }
  p { color:#94a3b8; margin:0 0 1.2rem; }
  input { font-size:1.1rem; padding:.6rem .8rem; border-radius:.5rem; border:1px solid #334155;
          background:#0f172a; color:#e2e8f0; width:150px; text-align:center; }
  button { font-size:1.1rem; padding:.6rem 1.4rem; border-radius:.5rem; border:none;
           background:#2563eb; color:#fff; cursor:pointer; margin-left:.5rem; }
  button:hover { background:#1d4ed8; }
  .tip { margin-top:1.5rem; font-size:.82rem; }
</style>
</head>
<body>
  <div class="box">
    <h1>Navegador de la VM Telepark</h1>
    <p>Ingresá el puerto de tu app para abrirla en el navegador:</p>
    <input type="number" id="port" placeholder="ej. 3000" min="1" max="65535" autofocus>
    <button onclick="abrir()">Abrir</button>
    <p class="tip">El editor (VS Code) se abre igual: puerto 8080 con <code>code-on 8080</code>.</p>
  </div>
  <script>
    function abrir() {
      const p = document.getElementById('port').value.trim();
      if (p) window.location.href = '/port/' + p + '/';
    }
    document.getElementById('port').addEventListener('keydown', function (e) {
      if (e.key === 'Enter') abrir();
    });
  </script>
</body>
</html>
"""


@router.get("/port/", response_class=HTMLResponse)
async def port_launcher(request: Request):
    if not _telepark_user(request):
        return RedirectResponse(url="/login", status_code=HTTP_302_FOUND)
    return HTMLResponse(_PORT_LAUNCHER_HTML)
