# 🔧 Fixes — Site Tunnel Portal

> Registro de problemas y soluciones del portal de acceso via Cloudflare Tunnel.
> Última actualización: 2026-07-29

---

## [✅] Fix #1: Botón en Drupal no responsive / mobile first

**Problema**: El botón "ACCEDER AL PORTAL GIDAS" en la página de Drupal no se adaptaba a pantallas chicas.

**Solución**: Actualizado el contenido de `/node/40` en Drupal con CSS responsive:
- `display:inline-block` + `width:80%` + `max-width:350px`
- Padding y font-size ajustados para mobile

**Archivo**: Contenido de `/node/40` en Drupal (editado via admin)

---

## [✅] Fix #2: Redmine no carga bien / redirect loop al hacer login

**Problema**: Redmine cargaba vía tunnel pero con assets rotos. El formulario de login tenía `action="/search"` sin el prefijo `/redmine/`. Además, después del login redirigía a `https://redmine.gidas.local/my/page` (URL interna, no accesible desde el tunnel).

**Solución**: 
1. Agregado `location /redmine/` en el nginx de Redmine (`redmine/nginx/redmine.conf`):
   - `rewrite ^/redmine(/.*)$ $1 break;` — quita el prefijo al pasar al backend
   - `sub_filter` para reescribir `href="/` → `href="/redmine/"`, `src="/` → `src="/redmine/"`, `action="/login` → `action="/redmine/login"`, etc.
2. En CT 208 nginx:
   - `proxy_set_header Host redmine.gidas.local;`
   - `proxy_redirect https://redmine.gidas.local/ /redmine/;` — reescribe redirects post-login

**Archivos**: `redmine/nginx/redmine.conf`, `/etc/nginx/nginx.conf` (CT 208)

---

## [✅] Fix #3: GitLab error "Not found /"

**Problema**: GitLab redirigía a URLs incorrectas con doble subpath (`/gitlab/gitlab/users/sign_in`) o a `https://127.0.0.1/`.

**Solución**:
1. Configurado `external_url` en GitLab: `http://gitlab.gidas.local/gitlab` (vía `gitlab-ctl reconfigure`)
2. En CT 208 nginx:
   - `proxy_set_header Host gitlab.gidas.local;`
   - `proxy_set_header X-Forwarded-Proto http;`
   - `proxy_redirect https://gitlab.gidas.local/gitlab/ /gitlab/;`
   - `proxy_redirect http://gitlab.gidas.local/gitlab/ /gitlab/;`

**Archivos**: `/etc/gitlab/gitlab.rb` (GitLab VM 201), `/etc/nginx/nginx.conf` (CT 208)

---

## [✅] Fix #4: `{url}` literal en Drupal — botón "Pagina no encontrada"

**Problema**: Al actualizar el contenido de Drupal para el botón responsive, se escribió literalmente `{url}` en vez de la URL real del tunnel. El botón apuntaba a `{url}` que Drupal interpretaba como ruta relativa → página no encontrada.

**Solución**: Reemplazar `{url}` por la URL real del tunnel en el contenido de `/node/40`. El script `auto-tunnel.py` hace esto automáticamente, pero la edición manual rompió el placeholder.

**Archivo**: Contenido de `/node/40` en Drupal

---

## [✅] Fix #5: Tunnel URL cambia al reiniciar (parcial)

**Problema**: La URL de trycloudflare cambia cada vez que se reinicia el tunnel.

**Solución parcial**: Script `auto-tunnel.py` actualiza la página de Drupal automáticamente con la nueva URL.

**Pendiente**: Migrar a Cloudflare Named Tunnel (gratis) para URL estable, o comprar dominio propio.

---

## [✅] Fix #9: Falsos positivos del monitor + chequeo integral de servicios

**Problema**: `tunnel-monitor.py` tenía la URL del Quick Tunnel hardcodeada y solo checkeaba el tunnel, sin verificar herramientas ni infraestructura individualmente.

**Solución**: Rediseño completo del monitor:
1. **URL dinámica**: Lee la URL del tunnel desde `/var/log/cloudflared.log` (misma regex que `auto-tunnel.py`)
2. **Chequeo de herramientas**: Verifica cada tool via tunnel (Portal, Grafana, GitLab, Redmine, LibreNMS) con HTTP 200/302
3. **Chequeo de infraestructura**: Verifica 13 componentes via ping/HTTP (hosts PVE, CTs, VMs, AD, MikroTik)
4. **Detección de cambios**: Persiste estado en `state.json`, compara vs chequeo actual
5. **Alertas DOWNTIME / RESOLUCIÓN**: Solo envía Telegram cuando hay cambio de estado:
   - `🔴 DOWNTIME — Redmine (timeout)` cuando se cae
   - `🟢 RESOLUCION — Redmine (200)` cuando se recupera
6. **Métricas**: Parseo de nginx access log + heartbeat JSON

**Servicios monitoreados (19 total)**:
| Categoría | Items |
|-----------|-------|
| 🌐 Tunnel | Cloudflare Quick Tunnel |
| 🧰 Tools (5) | Portal, Grafana, GitLab, Redmine, LibreNMS |
| 🖥️ Infra (13) | 4x PVE hosts, 4x CTs (208-211), 3x VMs (201,205,206), AD GDC01, MikroTik |

**Archivo**: `site-tunnel-portal/scripts/tunnel-monitor.py` (versionado en repo) + `/opt/portal-gidas/tunnel-monitor.py` (CT 208)

**Verificación**:
```
Tunnel: ✅ OK (200)     Tools: 5/5 ✅      Infra: 13/13 ✅      Alertas: 0
```
✅ Sin falsos positivos. Alertas solo ante cambios de estado reales.

---

## Estado Actual (2026-07-30)

| Tool | URL | Estado |
|------|-----|--------|
| Portal (login AD) | `/` | ✅ Login + dashboard |
| Grafana | `/grafana/` | ✅ Full, `root_url` config |
| GitLab | `/gitlab/` | ✅ Login + assets, `external_url` config |
| Redmine | `/redmine/` | ✅ Login + 33 assets OK, `proxy_redirect` post-login |
| LibreNMS | `/librenms/` | ⚠️ Sigue con `proxy: true` (FastAPI) |

### Herramientas NO expuestas via tunnel
- **Vaultwarden**: Gestor de contraseñas, solo via Twingate
- **MikroTik**: No accesible desde CT 208
- **Identity Dashboard**: Subpath de GitLab, accesible via GitLab proxy

---
