# 🔧 Fixes — Site Tunnel Portal

> Registro de problemas y soluciones del portal de acceso via Cloudflare Tunnel.
> Última actualización: 2026-07-03

---

## [✅] Fix #1: Botón en Drupal no responsive / mobile first

**Problema**: El botón "ACCEDER AL PORTAL GIDAS" en la página de Drupal no se adaptaba a pantallas chicas.

**Solución**: Actualizado el contenido de `/node/40` en Drupal con CSS responsive:
- `display:inline-block` + `width:80%` + `max-width:350px`
- Padding y font-size ajustados para mobile

**Archivo**: Contenido de `/node/40` en Drupal (editado via admin)

---

## [✅] Fix #2: Redmine no carga bien / redirect loop al hacer login

**Problema**: Redmine cargaba vía tunnel pero con assets rotos. El formulario de login tenía `action="/search"` sin el prefijo `/redmine/`.

**Solución**: 
1. Agregado `location /redmine/` en el nginx de Redmine (`redmine/nginx/redmine.conf`):
   - `rewrite ^/redmine(/.*)$ $1 break;` — quita el prefijo al pasar al backend
   - `sub_filter` para reescribir `href="/` → `href="/redmine/"`, `src="/` → `src="/redmine/"`, `action="/search` → `action="/redmine/search"`
2. Configurado el nginx de CT 208 para que pase `Host: redmine.gidas.local`

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

## [🔄] Fix #5: Tunnel URL cambia al reiniciar (pendiente)

**Problema**: La URL de trycloudflare cambia cada vez que se reinicia el tunnel.

**Solución parcial**: Script `auto-tunnel.py` actualiza la página de Drupal automáticamente con la nueva URL.

**Pendiente**: Migrar a Cloudflare Named Tunnel (gratis) para URL estable, o comprar dominio propio.

---

## Estado Actual (2026-07-03)

| Tool | URL | Estado |
|------|-----|--------|
| Portal (login AD) | `/` | ✅ Login + dashboard |
| Grafana | `/grafana/` | ✅ Full, `root_url` config |
| GitLab | `/gitlab/` | ✅ Login + assets, `external_url` config |
| Redmine | `/redmine/` | ✅ Login + assets, `sub_filter` nginx |
| LibreNMS | `/librenms/` | ⚠️ Sigue mostrando portal (proxy a portal) |

### Herramientas NO expuestas via tunnel
- **Vaultwarden**: Gestor de contraseñas, solo via Twingate
- **MikroTik**: No accesible desde CT 208
- **Identity Dashboard**: Subpath de GitLab, accesible via GitLab proxy

---

[ ] boton drupal de acceso a portal da error en drupal "Pagina no encontrada"