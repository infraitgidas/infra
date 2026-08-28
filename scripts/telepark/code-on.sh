#!/usr/bin/env bash
# code-on — launcher on-demand de code-server (VS Code en el navegador) para la VM Telepark.
#
# Uso:
#   code-on [puerto]          # inicia code-server en el puerto (default 8080)
#   code-on [puerto] stop     # detiene la instancia de ese puerto
#   code-on [puerto] status   # muestra estado y URL de acceso
#
# Seguridad: code-server corre con `--auth none` porque la autenticación la hace el
# Portal GIDAS (RBAC: solo el grupo PROY-Telepark accede a /port/{puerto}/).
# Mientras corra, el puerto queda escuchando en 0.0.0.0 dentro de la LAN de confianza.
# Detenelo al terminar: `code-on <puerto> stop`.

set -euo pipefail

PORT="${1:-8080}"
ACTION="${2:-start}"

PIDFILE="$HOME/.code-server-${PORT}.pid"
LOGFILE="$HOME/.code-server-${PORT}.log"

# URL del portal (Cloudflare Quick Tunnel, dinámica). El dev la conoce por las cards
# SSH del portal. Se puede fijar con la variable CODEPORTAL.
PORTAL="${CODEPORTAL:-https://<url-del-portal>}"

_running() {
    [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null
}

start() {
    if _running; then
        echo "✅ code-server ya corre en el puerto $PORT (PID $(cat "$PIDFILE"))"
        echo "   Abrí: ${PORTAL}/port/${PORT}/"
        return 0
    fi

    if command -v ss >/dev/null 2>&1 && ss -ltn 2>/dev/null | grep -Eq ":${PORT}[[:space:]]"; then
        echo "❌ El puerto $PORT ya está en uso. Elegí otro:  code-on <puerto>"
        exit 1
    fi

    # `nohup ... & disown` para que sobreviva al cierre de la sesión SSH.
    nohup code-server --auth none --bind-addr "0.0.0.0:${PORT}" </dev/null >"$LOGFILE" 2>&1 &
    echo $! > "$PIDFILE"
    disown

    sleep 2
    if _running; then
        echo "✅ code-server corriendo como $(whoami) en el puerto $PORT"
        echo "   Abrí en tu navegador:  ${PORTAL}/port/${PORT}/"
        echo "   Para detener:          code-on $PORT stop"
    else
        echo "❌ No arrancó. Revisá el log: $LOGFILE"
        tail -20 "$LOGFILE"
        exit 1
    fi
}

stop() {
    if _running; then
        kill "$(cat "$PIDFILE")" 2>/dev/null || true
        rm -f "$PIDFILE"
        echo "🛑 code-server del puerto $PORT detenido."
    else
        echo "No hay instancia corriendo en el puerto $PORT."
    fi
}

status() {
    if _running; then
        echo "✅ code-server corriendo en el puerto $PORT (PID $(cat "$PIDFILE"))"
        echo "   URL: ${PORTAL}/port/${PORT}/"
    else
        echo "No hay instancia corriendo en el puerto $PORT."
    fi
}

case "$ACTION" in
    stop)   stop ;;
    status) status ;;
    *)      start ;;
esac
