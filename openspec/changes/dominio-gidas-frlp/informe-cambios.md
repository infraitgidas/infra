# Informe de Cambios — Dominio gidas.frlp — Integración con sitio institucional

**Feature branch**: `feat/dominio-gidas-frlp`
**Fecha**: 2026-07-30 (v3)
**Estado**: ✅ COMPLETO — Tunnel + nginx + 3 tools + Monitor integral 19 servicios + DOWNTIME/RESOLUCION

---

## 1. Resumen Ejecutivo

Se implementó un sistema de acceso remoto al portal GIDAS y sus herramientas internas utilizando Cloudflare Tunnel + nginx como reverse proxy, eliminando la dependencia de Twingate (cuenta personal free limitada). El punto de entrada es el sitio institucional Drupal `gidas.frlp.utn.edu.ar`, desde donde los usuarios acceden al portal y desde allí a las tools via subpath proxy.

| Concepto | Valor |
|----------|-------|
| **Tunnel** | Cloudflare Quick Tunnel (trycloudflare.com) |
| **Proxy** | nginx en CT 208 (portal) |
| **Dominio** | `gidas.frlp.utn.edu.ar/node/40` (página Drupal) |
| **Auth** | AD GDC01 via portal FastAPI |
| **Tools via tunnel** | Grafana, GitLab, Redmine (3/5 funcionales) |

---

## 2. Arquitectura

```
Usuario → Drupal (gidas.frlp.utn.edu.ar/node/40)
              ↓
       Tunnel Cloudflare → CT 208 (nginx:80)
              ├── / → Portal (login AD + dashboard)
              ├── /grafana/ → Grafana (192.168.1.205:3000) ✅
              ├── /gitlab/ → GitLab (192.168.1.41) ✅
              ├── /redmine/ → Redmine (192.168.1.20) ✅
              └── [tools restantes: via Twingate/red interna]
```

| Componente | Tecnología | Propósito |
|-----------|-----------|-----------|
| **Drupal** | CMS (UTN-FRLP) | Página pública con botón de acceso |
| **Cloudflare Tunnel** | cloudflared | Tunel HTTPS público → CT 208 |
| **nginx** | nginx 1.x | Reverse proxy frontal (puerto 80) |
| **Portal** | FastAPI + LDAP | Login AD + dashboard de tools |
| **auto-tunnel.py** | Python + systemd | Crea tunnel, actualiza Drupal automáticamente |

---

## 3. Tools configuradas

### Via tunnel (subpath nginx)

| Tool | Subpath | Configuración | Estado |
|------|---------|--------------|--------|
| **Grafana** | `/grafana/` | `root_url` + `serve_from_sub_path` | ✅ Full |
| **GitLab** | `/gitlab/` | `external_url` + `proxy_redirect` | ✅ Login + assets |
| **Redmine** | `/redmine/` | `sub_filter` + `proxy_redirect` | ✅ Login + 33 assets |

### Solo via Twingate/red interna

| Tool | Motivo |
|------|--------|
| **LibreNMS** | Redirecciona a `/login` sin subpath (requiere config adicional) |
| **Vaultwarden** | Gestor de contraseñas, no expuesto públicamente |
| **Proxmox** | Requiere puerto 8006 y WebSocket |
| **MikroTik** | No accesible desde CT 208 |
| **NetBox/GLPI** | DNS no resuelve desde CT 208 |

---

## 4. Bugs Corregidos

### Bug #1: Roles AD borrados en cada login (LibreNMS)
No relacionado con tunnel. Ver ADR-003.

### Bug #2: Botón Drupal no responsive
- **Fix**: CSS mobile-first (width:80%, max-width:350px)

### Bug #3: Redmine assets rotos + login redirect
- **Fix**: `sub_filter` en nginx para reescribir href/src/action → `/redmine/...`
- **Fix**: `proxy_redirect` para redirect post-login → `/redmine/my/page`

### Bug #4: GitLab "Not found /"
- **Fix**: `external_url` con subpath `/gitlab`, `proxy_redirect` en nginx

### Bug #5: `{url}` literal en Drupal
- **Fix**: Reemplazar placeholder por URL real del tunnel

### Bug #9: Falsos positivos del monitor + rediseño a chequeo integral

**Problema**: `tunnel-monitor.py` tenía la URL del Quick Tunnel hardcodeada y solo checkeaba el tunnel. No detectaba caídas individuales de herramientas ni infraestructura.

**Causa raíz**: El servicio `gidas-tunnel.service` se reinició y cloudflared generó una nueva URL. El monitor no la detectó porque tenía la anterior hardcodeada → falso positivo cada 5 min.

**Fix**: Rediseño completo del monitor:
1. **URL dinámica**: Lee la URL del tunnel desde `/var/log/cloudflared.log`
2. **Chequeo de herramientas (5)**: Portal, Grafana, GitLab, Redmine, LibreNMS via tunnel
3. **Chequeo de infraestructura (13)**: PVE hosts, CTs, VMs, AD, MikroTik via ping/HTTP
4. **Detección de cambios**: Persiste estado en `state.json`, alerta solo en transiciones
5. **Alertas**: `🔴 DOWNTIME — Servicio (detalle)` / `🟢 RESOLUCION — Servicio (detalle)`

**Archivos afectados**:
- `site-tunnel-portal/scripts/tunnel-monitor.py` (versión versionada en repo)
- `/opt/portal-gidas/tunnel-monitor.py` (CT 208, deployado)

**Verificación**:
```
Tunnel: ✅ OK (200)     Tools: 5/5 ✅      Infra: 13/13 ✅      Alertas: 0
```
✅ 19 servicios monitoreados. Alertas solo ante cambios de estado reales.
✅ DOWNTIME y RESOLUCIÓN verificados (test con Redmine: RESOLUCION enviado a Telegram).

**Lecciones**:
1. Los scripts críticos NO estaban versionados en el repo — solo existían en CT 208
2. El Quick Tunnel es inherentemente volátil (cambia URL en cada reinicio)
3. Para Named Tunnel se necesita cuenta Cloudflare con un dominio agregado

---

## 5. Credenciales

> 📋 Ver documento sensible `~/Documentos/gidas-credenciales/CREDENCIALES.md`

| Recurso | Ubicación |
|---------|-----------|
| Drupal admin | `administrador` / `Urbano2022*$` |
| Portal AD | Usuarios AD del dominio GDC01.local |
| CT 208 | Via PVE host (root@192.168.1.14) |
| PC GIDAS | `infra@192.168.1.54` / `hlvs.2025` |

---

## 6. Scripts y Archivos

| Archivo | Propósito |
|---------|-----------|
| `/opt/portal-gidas/auto-tunnel.py` | Script auto-tunnel + Drupal update |
| `/etc/systemd/system/gidas-tunnel.service` | Service systemd |
| `/etc/nginx/nginx.conf` | Reverse proxy (CT 208) |
| `redmine/nginx/redmine.conf` | Subpath /redmine/ + sub_filter |
| `portal-gidas/config.yaml` | Tools URLs (nginx subpath) |
| `docs/gidas-frlp-dominio.md` | Documentación del dominio |
| `site-tunnel-portal/fixes.md` | Registro de fixes |
| `site-tunnel-portal/feats.md` | Próximas features planificadas |
| `docs/runbooks/gidas-tunnel-maintenance.md` | Mantenimiento del tunnel |
| `docs/runbooks/howto-add-service-tunnel.md` | Guía para agregar servicios al tunnel |
| `docs/runbooks/tunnel-migration-roadmap.md` | Roadmap de migración a soluciones estables |
| `docs/runbooks/cloudflare-tunnel-analysis.md` | Análisis de Cloudflare Tunnel y limitaciones |
| `docs/portal-acceso/propuesta-direccion.md` | Propuesta ejecutiva para dirección |
| `/opt/portal-gidas/tunnel-monitor.py` | Heartbeat + parseo de logs (cron) — URL dinámica desde log |
| `/opt/portal-gidas/metrics-server.py` | Endpoint Prometheus en puerto 9100 |
| `site-tunnel-portal/scripts/tunnel-monitor.py` | ✅ Versionado en repo (nuevo) — URL dinámica |
| `site-tunnel-portal/scripts/tunnel-monitor.py.quick-tunnel.bak` | Backup del monitor original (URL hardcodeada) |
| `site-tunnel-portal/scripts/auto-tunnel.py.quick-tunnel.bak` | Backup del auto-tunnel original |
| `site-tunnel-portal/scripts/metrics-server.py.quick-tunnel.bak` | Backup del metrics server |
| `site-tunnel-portal/scripts/gidas-tunnel.service.quick-tunnel.bak` | Backup del systemd service |
| `site-tunnel-portal/scripts/auto-tunnel.service.quick-tunnel.bak` | Backup del auto-tunnel service alternativo |
| `site-tunnel-portal/scripts/tunnel-monitor.cron.quick-tunnel.bak` | Backup del cron original |

---

## 7. Verificación Final

| Criterio | Resultado |
|----------|-----------|
| Drupal page accesible | ✅ 200 OK |
| Botón responsive | ✅ width:80%, max-width:350px |
| Tunnel activo (systemd) | ✅ active |
| Drupal auto-update | ✅ Se actualiza con nueva URL |
| Login via tunnel | ✅ 200 OK |
| Grafana via tunnel | ✅ 200 (58899b) assets OK |
| GitLab via tunnel | ✅ 200 (14365b) assets OK |
| Redmine via tunnel | ✅ 200 (9930b) 33/33 assets OK |
| Portal en navbar Drupal | ✅ Visible en menú principal (Inicio → Portal GIDAS) |
| Redmine redirect post-login | ✅ `proxy_redirect` → `/redmine/my/page` |
| GitLab redirect loop | ✅ `external_url` + `proxy_redirect` corregido |
| Solicitud de acceso nuevos usuarios | ✅ Sección en Drupal con mailto e instrucciones |
| Monitoreo del tunnel | ✅ Heartbeat cada 5 min + Telegram alert |
| Métricas por tool | ✅ Endpoint Prometheus en puerto 9100 |
| Rate limiting (4 intentos → bloqueo 15 min) | ✅ Probado: error=1 → error=3 |
| Security headers OWASP | ✅ 6 headers implementados |
| Alerta fuerza bruta | ✅ Telegram a @GiDAS_alertbot |
| Endpoint /security/stats | ✅ Monitoreo de IPs bloqueadas |
| Monitor URL dinámica | ✅ Lee URL del log de cloudflared |
| Chequeo de herramientas (5) | ✅ Portal, Grafana, GitLab, Redmine, LibreNMS via tunnel |
| Chequeo de infraestructura (13) | ✅ 4 PVE hosts, 4 CTs, 3 VMs, AD GDC01, MikroTik |
| Detección de cambios de estado | ✅ state.json persistido con timestamp |
| Alerta DOWNTIME | ✅ 🔴 DOWNTIME — Redmine (timeout) |
| Alerta RESOLUCIÓN | ✅ 🟢 RESOLUCION — Redmine (200) — verificado |
| Sin falsos positivos cada 5 min | ✅ Verificado: HTTP 200 OK sin alerta |

---

## 8. Trabajo Futuro

| Tarea | Prioridad | Estado |
|-------|-----------|--------|
| ✅ Fix #1: Botón Drupal responsive | 🟡 Media | ✅ |
| ✅ Fix #2: Redmine subpath + redirect | 🔴 Alta | ✅ |
| ✅ Fix #3: GitLab "Not found /" | 🔴 Alta | ✅ |
| ✅ Fix #4: `{url}` literal en Drupal | 🔴 Alta | ✅ |
| ✅ Fix #5: Portal GIDAS en navbar | 🟡 Media | ✅ |
| ✅ Fix #6: Página solicitud acceso becarios | 🟢 Baja | ✅ |
| ✅ Fix #7: Monitoreo tunnel + métricas por tool | 🟡 Media | ✅ |
| ✅ Fix #8: Seguridad — rate limiting + headers OWASP | 🔴 Alta | ✅ |
| ✅ Fix #9: Monitor integral — URL dinámica + tools + infra + DOWNTIME/RESOLUCION | 🔴 Alta | ✅ |
| 🔄 Fix #5: Tunnel URL cambia al reiniciar — migrar a Named Tunnel | 🟡 Media | ✅ Parcial |
| Migrar a Cloudflare Named Tunnel (URL estable) | 🟡 Media | ⏳ (sin dominio) |
| Comprar dominio propio (gidas.com.ar) | 🟢 Baja | ⏳ |
| Agregar HTTPS a nginx CT 208 (Let's Encrypt) | 🟢 Baja | ⏳ |
| Versionar scripts críticos del CT en el repo | 🟡 Media | ✅ Parcial |
| Mover credenciales hardcodeadas a variables de entorno/vault | 🔴 Alta | ⏳ |

| Seguridad: bloquear tras 4 intentos fallidos | 🟡 Media | ✅ |

