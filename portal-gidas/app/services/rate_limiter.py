"""Rate limiter para el portal GIDAS.

Almacena intentos fallidos por IP y username.
Bloquea tras 4 intentos fallidos por 15 minutos.
Notifica comportamiento sospechoso via Telegram.
"""

from __future__ import annotations

import time
import urllib.request
import urllib.error
from threading import Lock

# Config
MAX_ATTEMPTS = 4
BLOCK_MINUTES = 15
BLOCK_SECONDS = BLOCK_MINUTES * 60

TELEGRAM_TOKEN = "8965268173:AAFOqin05EmL7bMSqQkJmgu4uo5GrAwxC-o"
TELEGRAM_CHAT = "1773145563"

# In-memory store: {key: {"attempts": int, "first_attempt": float, "blocked_until": float}}
_attempts: dict = {}
_lock = Lock()


def _get_key(ip: str, username: str) -> str:
    return f"{ip}:{username}"


def _get_ip(request) -> str:
    forwarded = request.headers.get("X-Forwarded-For", "")
    if forwarded:
        return forwarded.split(",")[0].strip()
    return request.client.host if request.client else "unknown"


def _send_telegram(msg: str):
    """Send alert via Telegram (best effort, no raise)."""
    try:
        url = f"https://api.telegram.org/bot{TELEGRAM_TOKEN}/sendMessage"
        data = f"chat_id={TELEGRAM_CHAT}&text={msg}&parse_mode=Markdown".encode()
        urllib.request.urlopen(url, data=data, timeout=10)
    except Exception:
        pass  # Silently fail, don't block the login


def check_rate_limit(request, username: str) -> tuple[bool, str | None]:
    """Check if this request is rate-limited.
    
    Returns:
        (is_blocked, error_message)
    """
    ip = _get_ip(request)
    key = _get_key(ip, username)
    now = time.time()

    with _lock:
        entry = _attempts.get(key)

        # If blocked, check if block expired
        if entry and entry.get("blocked_until"):
            if now < entry["blocked_until"]:
                remaining = int(entry["blocked_until"] - now)
                return True, f"Demasiados intentos. Intente nuevamente en {remaining} segundos."
            else:
                # Block expired, clean up
                del _attempts[key]
                entry = None

    return False, None


def register_failed_attempt(request, username: str):
    """Register a failed login attempt.
    
    Returns True if this attempt triggered a block.
    """
    global _attempts
    ip = _get_ip(request)
    key = _get_key(ip, username)
    now = time.time()

    with _lock:
        entry = _attempts.get(key)

        if not entry:
            entry = {"attempts": 0, "first_attempt": now, "blocked_until": 0}
            _attempts[key] = entry

        entry["attempts"] += 1

        # If exceeded max attempts, block
        if entry["attempts"] >= MAX_ATTEMPTS:
            entry["blocked_until"] = now + BLOCK_SECONDS
            msg = (
                f"🚨 *ALERTA DE SEGURIDAD*\n"
                f"Usuario: `{username}`\n"
                f"IP: `{ip}`\n"
                f"Intentos: {entry['attempts']}\n"
                f"Bloqueado hasta: {time.strftime('%H:%M:%S', time.localtime(entry['blocked_until']))}\n"
                f"Duracion: {BLOCK_MINUTES} min"
            )
            _send_telegram(msg)
            
            # Clean up old entries (keep max 1000)
            if len(_attempts) > 1000:
                cutoff = now - 3600
                _attempts = {k: v for k, v in _attempts.items() 
                           if v.get("blocked_until", 0) > cutoff or v["first_attempt"] > cutoff}
            return True

    return False


def register_successful_attempt(request, username: str):
    """Clear failed attempt counter on successful login."""
    ip = _get_ip(request)
    key = _get_key(ip, username)

    with _lock:
        _attempts.pop(key, None)


def get_stats() -> dict:
    """Get current rate limit stats (for monitoring)."""
    global _attempts
    now = time.time()
    with _lock:
        total = len(_attempts)
        blocked = sum(1 for v in _attempts.values() if v.get("blocked_until", 0) > now)
        return {"total_tracked": total, "blocked_ips": blocked}
