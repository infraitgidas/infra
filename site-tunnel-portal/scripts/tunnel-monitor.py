#!/usr/bin/env python3
"""Monitoreo del tunnel Cloudflare + accesos a herramientas.
Lee la URL del tunnel dinámicamente desde el log de cloudflared.
"""
import subprocess, re, time, os, json
from datetime import datetime, timedelta
import urllib.request, urllib.error

CLOUDFLARED_LOG = "/var/log/cloudflared.log"
LOG_DIR = "/var/log/tunnel-monitor"
NGINX_LOG = "/var/log/nginx/access.log"
HEARTBEAT_FILE = LOG_DIR + "/heartbeat.json"
METRICS_FILE = LOG_DIR + "/metrics.json"
os.makedirs(LOG_DIR, exist_ok=True)

TELEGRAM_TOKEN = "8965268173:AAFOqin05EmL7bMSqQkJmgu4uo5GrAwxC-o"
TELEGRAM_CHAT = "1773145563"

TOOLS = {
    "portal":   "/ HTTP/",
    "grafana":  "/grafana/",
    "gitlab":   "/gitlab/",
    "redmine":  "/redmine/",
    "librenms": "/librenms/",
}

def log(msg):
    print(f"[{datetime.now().strftime('%H:%M:%S')}] {msg}", flush=True)

def send_telegram(msg):
    try:
        url = f"https://api.telegram.org/bot{TELEGRAM_TOKEN}/sendMessage"
        data = f"chat_id={TELEGRAM_CHAT}&text={msg}&parse_mode=Markdown".encode()
        urllib.request.urlopen(url, data=data, timeout=10)
    except Exception as e:
        log(f"Telegram error: {e}")

def get_tunnel_url():
    """Lee la URL actual del tunnel desde el log de cloudflared."""
    try:
        if not os.path.exists(CLOUDFLARED_LOG):
            log(f"Log no encontrado: {CLOUDFLARED_LOG}")
            return None
        with open(CLOUDFLARED_LOG) as f:
            content = f.read()
        # Busca la última URL de trycloudflare en el log
        urls = re.findall(r"https://[a-z0-9-]+\.trycloudflare\.com", content)
        if urls:
            # Devuelve la última (más reciente)
            url = urls[-1]
            log(f"URL del tunnel: {url}")
            return url
        log("No se encontró URL de trycloudflare en el log")
        return None
    except Exception as e:
        log(f"Error leyendo log de cloudflared: {e}")
        return None

def check_tunnel():
    """Check tunnel is alive usando la URL actual del log."""
    tunnel_url = get_tunnel_url()
    if not tunnel_url:
        log("No hay URL de tunnel — tunnel caído o iniciando")
        return False
    
    try:
        req = urllib.request.Request(tunnel_url, method="GET")
        with urllib.request.urlopen(req, timeout=15) as r:
            status = r.status
            ok = status == 200 or status == 302
            log(f"Tunnel responde: HTTP {status} {'OK' if ok else 'RARO'}")
            return ok
    except Exception as e:
        log(f"Tunnel DOWN: {e}")
        return False

def parse_nginx_log():
    """Count requests per tool from nginx access log."""
    if not os.path.exists(NGINX_LOG):
        return {}
    
    with open(NGINX_LOG) as f:
        content = f.read()
    
    counts = {}
    for tool, pattern in TOOLS.items():
        counts[tool] = len(re.findall(pattern, content))
    
    counts["total"] = len(content.split("\n")) - 1
    counts["errors_4xx"] = len(re.findall(r'" (4\d\d) ', content))
    counts["errors_5xx"] = len(re.findall(r'" (5\d\d) ', content))
    
    return counts

def save_heartbeat(up, counts, tunnel_url):
    """Save current state with the actual tunnel URL."""
    data = {
        "timestamp": datetime.now().isoformat(),
        "tunnel_up": up,
        "tunnel_url": tunnel_url,
        "metrics": counts,
    }
    with open(HEARTBEAT_FILE, "w") as f:
        json.dump(data, f)
    
    daily = LOG_DIR + "/" + datetime.now().strftime("%Y-%m-%d") + ".jsonl"
    with open(daily, "a") as f:
        json.dump(data, f)
        f.write("\n")

def get_daily_summary():
    """Get today's summary."""
    daily = LOG_DIR + "/" + datetime.now().strftime("%Y-%m-%d") + ".jsonl"
    if not os.path.exists(daily):
        return None
    
    entries = []
    with open(daily) as f:
        for line in f:
            try:
                entries.append(json.loads(line))
            except:
                pass
    
    if not entries:
        return None
    
    total_tools = {}
    for e in entries:
        for tool, count in e.get("metrics", {}).items():
            total_tools[tool] = total_tools.get(tool, count) + count
    
    return {
        "checks": len(entries),
        "downtime": sum(1 for e in entries if not e.get("tunnel_up")),
        "tool_requests": total_tools,
    }

def main():
    log("=== Tunnel Monitor iniciado ===")
    
    tunnel_up = check_tunnel()
    tunnel_url = get_tunnel_url()
    counts = parse_nginx_log()
    save_heartbeat(tunnel_up, counts, tunnel_url)
    
    if not tunnel_up:
        url_msg = tunnel_url if tunnel_url else "sin URL detectada"
        send_telegram("🔴 *TUNNEL CAIDO* - " + url_msg)
        log("ALERTA: Tunnel caido - Telegram enviado")
    else:
        log(f"Tunnel OK - {counts.get('total',0)} requests, {len(counts)-4} tools")
    
    # Clean old logs (>30 days)
    for f in os.listdir(LOG_DIR):
        path = os.path.join(LOG_DIR, f)
        if os.path.isfile(path):
            mtime = os.path.getmtime(path)
            if time.time() - mtime > 30 * 86400:
                os.remove(path)
    
    log("Monitor OK")

if __name__ == "__main__":
    main()
