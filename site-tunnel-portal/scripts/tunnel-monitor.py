#!/usr/bin/env python3
"""Monitor integral de tunnel + herramientas + infraestructura GIDAS.
Chequea disponibilidad de cada servicio, detecta cambios de estado,
y envía alertas DOWNTIME / RESOLUTION por Telegram.

Corre cada 5 minutos via cron (/etc/cron.d/tunnel-monitor).
"""
import subprocess, re, time, os, json, socket, ssl
from datetime import datetime, timedelta
import urllib.request, urllib.error

# ── Rutas ──────────────────────────────────────────────────────────
CLOUDFLARED_LOG = "/var/log/cloudflared.log"
LOG_DIR = "/var/log/tunnel-monitor"
NGINX_LOG = "/var/log/nginx/access.log"
STATE_FILE = LOG_DIR + "/state.json"
HEARTBEAT_FILE = LOG_DIR + "/heartbeat.json"
os.makedirs(LOG_DIR, exist_ok=True)

# ── Telegram ───────────────────────────────────────────────────────
# Credenciales desde variables de entorno (nunca hardcodear).
# Formato del secreto: ver secrets/telegram.yaml.template
TELEGRAM_TOKEN = os.environ.get("TELEGRAM_TOKEN", "")
TELEGRAM_CHAT = os.environ.get("TELEGRAM_CHAT", "")

# ── Servicios chequeables via tunnel (subpath en nginx) ───────────
# Cada entrada tiene: subpath, expected_status, alias para mensajes
TOOLS = [
    {"name": "portal",   "path": "/",         "alias": "Portal GIDAS",           "expected": [200, 302]},
    {"name": "grafana",  "path": "/grafana/", "alias": "Grafana",               "expected": [200, 302]},
    {"name": "gitlab",   "path": "/gitlab/",  "alias": "GitLab",                "expected": [200, 302]},
    {"name": "redmine",  "path": "/redmine/", "alias": "Redmine",               "expected": [200, 302]},
    {"name": "librenms", "path": "/librenms/","alias": "LibreNMS",              "expected": [200, 302]},
]

# ── Infraestructura chequeable via red interna (desde CT 208) ────
# Cada entrada tiene: tipo (ping/http), target (IP/URL), alias
INFRA = [
    # ── Hosts Proxmox ──
    {"name": "pve-desa01",    "type": "ping", "target": "192.168.1.11", "alias": "pve-desa01"},
    {"name": "pve-desa02",    "type": "ping", "target": "192.168.1.12", "alias": "pve-desa02"},
    {"name": "pve-desa03",    "type": "ping", "target": "192.168.1.13", "alias": "pve-desa03"},
    {"name": "pve-sistema",   "type": "ping", "target": "192.168.1.14", "alias": "pve-sistema (pve-desa04)"},
    # ── Contenedores críticos ──
    {"name": "ct-208-portal",   "type": "http", "target": "http://127.0.0.1:80/",      "alias": "CT 208 — Portal"},
    {"name": "ct-209-vault",    "type": "http", "target": "https://192.168.1.44/",      "alias": "CT 209 — Vaultwarden"},
    {"name": "ct-210-librenms", "type": "ping", "target": "192.168.1.45",                "alias": "CT 210 — LibreNMS"},
    {"name": "ct-211-freeradius","type": "ping","target": "192.168.1.46",                "alias": "CT 211 — FreeRADIUS"},
    # ── VMs ──
    {"name": "vm-201-gitlab",  "type": "ping", "target": "192.168.1.41",                 "alias": "VM 201 — GitLab"},
    {"name": "vm-205-grafana", "type": "http", "target": "http://192.168.1.205:3000/",  "alias": "VM 205 — Grafana"},
    {"name": "vm-206-redmine", "type": "http", "target": "https://192.168.1.20/",       "alias": "VM 206 — Redmine"},
    # ── Servicios de red ──
    {"name": "ad-gdc01",      "type": "ping", "target": "192.168.1.117", "alias": "AD GDC01"},
    {"name": "mikrotik",       "type": "ping", "target": "192.168.1.1",   "alias": "MikroTik"},
]


# ═══════════════════════════════════════════════════════════════════
#  FUNCIONES AUXILIARES
# ═══════════════════════════════════════════════════════════════════

def log(msg):
    print(f"[{datetime.now().strftime('%H:%M:%S')}] {msg}", flush=True)

def send_telegram(msg):
    """Envía mensaje al bot de Telegram."""
    if not TELEGRAM_TOKEN or not TELEGRAM_CHAT:
        log("Telegram no configurado — definir TELEGRAM_TOKEN y TELEGRAM_CHAT (env)")
        return
    try:
        url = f"https://api.telegram.org/bot{TELEGRAM_TOKEN}/sendMessage"
        data = f"chat_id={TELEGRAM_CHAT}&text={msg}&parse_mode=Markdown".encode()
        urllib.request.urlopen(url, data=data, timeout=10)
        log(f"Telegram enviado: {msg[:60]}...")
    except Exception as e:
        log(f"Telegram error: {e}")

# ── Estado persistente ────────────────────────────────────────────

def load_state():
    """Carga el último estado conocido de todos los servicios."""
    try:
        if os.path.exists(STATE_FILE):
            with open(STATE_FILE) as f:
                return json.load(f)
    except Exception as e:
        log(f"Error leyendo state.json: {e}")
    return {}

def save_state(state):
    """Persiste el estado actual."""
    with open(STATE_FILE, "w") as f:
        json.dump(state, f, indent=2)

def check_changed(service, current_status, state):
    """Compara estado actual vs anterior. Retorna (cambio_str, nuevo_estado)."""
    previous = state.get(service, {}).get("status", "unknown")
    now = datetime.now().isoformat()

    if previous == "unknown":
        # Primera vez — registrar sin alertar
        state[service] = {"status": current_status, "last_change": now}
        return None, current_status

    if previous == current_status:
        # Mismo estado — sin novedad
        return None, current_status

    # Cambio de estado
    state[service] = {"status": current_status, "last_change": now}
    last_change_prev = state.get(service, {}).get("last_change", "desconocido")

    if current_status == "down":
        return f"🔴 *DOWNTIME* — {service}", "down"
    else:
        return f"🟢 *RESOLUCION* — {service}", "up"


# ═══════════════════════════════════════════════════════════════════
#  CHEQUEOS
# ═══════════════════════════════════════════════════════════════════

def get_tunnel_url():
    """Lee la URL actual del tunnel desde el log de cloudflared."""
    try:
        if not os.path.exists(CLOUDFLARED_LOG):
            log(f"Log no encontrado: {CLOUDFLARED_LOG}")
            return None
        with open(CLOUDFLARED_LOG) as f:
            content = f.read()
        urls = re.findall(r"https://[a-z0-9-]+\.trycloudflare\.com", content)
        if urls:
            url = urls[-1]
            return url
        log("No se encontró URL de trycloudflare en el log")
        return None
    except Exception as e:
        log(f"Error leyendo log de cloudflared: {e}")
        return None

def check_url(url, expected_codes=None, timeout=10):
    """Chequea si una URL responde con código esperado.
    Soporta HTTPS con certificados self-signed (no verifica).
    Retorna (True/False, status_code_o_error)."""
    if expected_codes is None:
        expected_codes = [200]
    # Contexto SSL que no verifica certificados (para internos self-signed)
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    try:
        req = urllib.request.Request(url, method="GET")
        with urllib.request.urlopen(req, timeout=timeout, context=ctx) as r:
            status = r.status
            ok = status in expected_codes
            return ok, status
    except urllib.error.HTTPError as e:
        status = e.code
        ok = status in expected_codes
        return ok, status
    except urllib.error.URLError as e:
        return False, f"timeout ({timeout}s)"
    except Exception as e:
        return False, str(e)[:40]

def check_ping(ip, timeout=5):
    """Chequea si una IP responde a ping.
    Retorna (True/False, 'ok' o mensaje de error)."""
    try:
        result = subprocess.run(
            ["ping", "-c", "1", "-W", str(timeout), ip],
            capture_output=True, text=True, timeout=timeout + 2
        )
        if result.returncode == 0:
            # Extraer tiempo de respuesta
            m = re.search(r"time=([0-9.]+)", result.stdout)
            ms = m.group(1) if m else "?"
            return True, f"{ms}ms"
        else:
            return False, "sin respuesta"
    except subprocess.TimeoutExpired:
        return False, f"timeout ({timeout}s)"
    except Exception as e:
        return False, str(e)[:40]

def check_tunnel(tunnel_url):
    """Chequea el tunnel Cloudflare."""
    if not tunnel_url:
        return False, "sin URL"
    return check_url(tunnel_url, expected_codes=[200, 302])

def check_tool(tunnel_url, tool):
    """Chequea una herramienta via tunnel."""
    url = tunnel_url.rstrip("/") + tool["path"]
    ok, detail = check_url(url, expected_codes=tool["expected"])
    return ok, detail, url

def check_infra_item(item):
    """Chequea un ítem de infraestructura."""
    if item["type"] == "ping":
        return check_ping(item["target"], timeout=5)
    elif item["type"] == "http":
        return check_url(item["target"], expected_codes=[200, 301, 302, 303, 307, 308], timeout=5)
    return False, "tipo desconocido"


# ═══════════════════════════════════════════════════════════════════
#  PARSEO DE LOGS NGINX (métricas)
# ═══════════════════════════════════════════════════════════════════

TOOL_PATTERNS = {
    "portal":   "/ HTTP/",
    "grafana":  "/grafana/",
    "gitlab":   "/gitlab/",
    "redmine":  "/redmine/",
    "librenms": "/librenms/",
}

def parse_nginx_log():
    """Cuenta requests por herramienta desde el log de nginx."""
    if not os.path.exists(NGINX_LOG):
        return {}
    with open(NGINX_LOG) as f:
        content = f.read()
    counts = {}
    for tool, pattern in TOOL_PATTERNS.items():
        counts[tool] = len(re.findall(pattern, content))
    counts["total"] = len(content.split("\n")) - 1
    counts["errors_4xx"] = len(re.findall(r'" (4\d\d) ', content))
    counts["errors_5xx"] = len(re.findall(r'" (5\d\d) ', content))
    return counts


# ═══════════════════════════════════════════════════════════════════
#  MAIN
# ═══════════════════════════════════════════════════════════════════

def main():
    log("=" * 50)
    log("Monitor GIDAS iniciado")
    log("=" * 50)

    # ── 1. Obtener URL actual del tunnel ──
    tunnel_url = get_tunnel_url()
    log(f"Tunnel URL: {tunnel_url or 'NO DETECTADA'}")

    # ── 2. Cargar estado anterior ──
    state = load_state()
    alerts = []        # mensajes a enviar por Telegram
    tool_status = {}   # estado individual de cada tool
    infra_status = {}  # estado individual de cada infra

    # ── 3. Chequear tunnel ──
    tunnel_ok = False
    if tunnel_url:
        tunnel_ok, tunnel_detail = check_tunnel(tunnel_url)
        log(f"Tunnel: {'✅ OK' if tunnel_ok else '❌ DOWN'} ({tunnel_detail})")
    else:
        tunnel_detail = "sin URL"
        log("Tunnel: ❌ DOWN (no hay URL)")

    msg, new_st = check_changed("tunnel", "up" if tunnel_ok else "down", state)
    if msg:
        detail = f" ({tunnel_detail})" if tunnel_detail else ""
        alerts.append(f"{msg}{detail}")

    # ── 4. Chequear herramientas (solo si tunnel OK, si no es ruido) ──
    if tunnel_ok and tunnel_url:
        for tool in TOOLS:
            ok, detail, url = check_tool(tunnel_url, tool)
            s = "up" if ok else "down"
            tool_status[tool["name"]] = s
            log(f"  {tool['alias']}: {'✅' if ok else '❌'} {detail}")

            msg, new_st = check_changed("tool:" + tool["name"], s, state)
            if msg:
                alerts.append(f"{msg} — {tool['alias']} ({detail})")
    else:
        log("  Tools: salteado (tunnel no disponible)")
        for tool in TOOLS:
            tool_status[tool["name"]] = "unknown"

    # ── 5. Chequear infraestructura (siempre, desde red interna) ──
    for item in INFRA:
        ok, detail = check_infra_item(item)
        s = "up" if ok else "down"
        infra_status[item["name"]] = s
        log(f"  {item['alias']}: {'✅' if ok else '❌'} {detail}")

        msg, new_st = check_changed("infra:" + item["name"], s, state)
        if msg:
            alerts.append(f"{msg} — {item['alias']} ({detail})")

    # ── 6. Enviar alertas por Telegram ──
    for alert in alerts:
        send_telegram(alert)
        time.sleep(0.5)  # pausa entre mensajes para no rate-limit

    if not alerts:
        log("Sin cambios de estado — no se enviaron alertas")

    # ── 7. Parsear métricas de nginx ──
    counts = parse_nginx_log()

    # ── 8. Guardar heartbeat ──
    heartbeat = {
        "timestamp": datetime.now().isoformat(),
        "tunnel_url": tunnel_url,
        "tunnel_up": tunnel_ok,
        "tools": tool_status,
        "infra": infra_status,
        "metrics": counts,
        "alerts_sent": len(alerts),
    }
    with open(HEARTBEAT_FILE, "w") as f:
        json.dump(heartbeat, f)

    # Append a log diario
    daily = LOG_DIR + "/" + datetime.now().strftime("%Y-%m-%d") + ".jsonl"
    with open(daily, "a") as f:
        json.dump(heartbeat, f)
        f.write("\n")

    # ── 9. Persistir estado ──
    save_state(state)

    # ── 10. Limpiar logs viejos (>30 días) ──
    for f in os.listdir(LOG_DIR):
        path = os.path.join(LOG_DIR, f)
        if os.path.isfile(path) and f != "state.json":
            mtime = os.path.getmtime(path)
            if time.time() - mtime > 30 * 86400:
                os.remove(path)

    # ── 11. Resumen ──
    tools_up = sum(1 for s in tool_status.values() if s == "up")
    tools_total = len(tool_status)
    infra_up = sum(1 for s in infra_status.values() if s == "up")
    infra_total = len(infra_status)
    log(f"Resumen: Tunnel {'OK' if tunnel_ok else 'DOWN'} | "
        f"Tools {tools_up}/{tools_total} | Infra {infra_up}/{infra_total} | "
        f"Alertas: {len(alerts)}")
    log("Monitor OK")


if __name__ == "__main__":
    main()
