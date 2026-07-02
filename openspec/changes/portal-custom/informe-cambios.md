# Informe de Cambios — Portal de Acceso Custom

**Feature branch**: `feat/portal-access-remoto`
**Fecha**: 2026-07-02
**Estado**: IMPLEMENTADO

---

## 1. Resumen Ejecutivo

Se desarrolló e implementó un portal de acceso custom (FastAPI + LDAP) para reemplazar Authentik (IdP) y Homer (dashboard estático). El portal permite a los miembros de GIDAS autenticarse con su usuario de AD y acceder únicamente a las herramientas correspondientes a sus grupos AD.

| Concepto | Antes (Authentik) | Después (Portal Custom) |
|----------|-------------------|------------------------|
| **Autenticación** | SSO vía OIDC/OAuth | LDAP directo contra AD GDC01 |
| **Autorización** | Por IdP | Por grupos AD (memberOf) |
| **Dashboard** | Cards nativas | SSR con Jinja2, Font Awesome |
| **Sesión** | IdP session | JWT stateless, cookie HttpOnly |
| **Config** | UI web + secrets | YAML versionable en git |
| **Dependencias** | 4 containers + PostgreSQL + Redis | FastAPI + ldap3 + PyJWT |
| **Recursos** | 1.5GB RAM | ~40MB RAM |

---

## 2. Lo Construido

### 2.1. Aplicación Web

| Módulo | Archivos | Función |
|--------|----------|---------|
| **Auth** | `app/auth.py`, `app/services/ldap_service.py` | Login AD vía ldap3, JWT creation/validation |
| **Config** | `app/config.py` | Parser Pydantic de config.yaml |
| **Routes** | `app/routers/auth.py`, `app/routers/portal.py` | GET/POST /login, GET /logout, GET / (dashboard) |
| **Frontend** | `app/templates/` (3 Jinja2 templates) | Login, dashboard, layout base |
| **Styles** | `app/static/css/portal.css` | CSS vanilla responsive, colores GIDAS |
| **Config YAML** | `config.yaml` | 11 herramientas con mapeo a grupos AD |

### 2.2. Infraestructura

| Recurso | Detalle |
|---------|---------|
| **CT 208** | Rocky Linux 9, 512MB RAM, 1 vCPU |
| **IP** | 192.168.1.43/24 |
| **DNS** | portal.gidas.local (MikroTik) |
| **Servicio** | portal-gidas.service (systemd, uvicorn, puerto 80) |
| **Código** | `/opt/portal-gidas/` |
| **Dependencias** | AD GDC01 (192.168.1.117:389) |

### 2.3. Documentación

| Documento | Archivo |
|-----------|---------|
| 🏗️ Arquitectura | `docs/portal-acceso/diseno/arquitectura.md` |
| 🔧 Diseño Técnico | `docs/portal-acceso/diseno/diseno-tecnico.md` |
| 📋 Lecciones Aprendidas | `docs/portal-acceso/diseno/lecciones-aprendidas.md` |
| 👤 Guía de Usuario | `docs/portal-acceso/manuales/guia-usuario.md` |
| 🔧 Guía de Admin | `docs/portal-acceso/manuales/guia-admin.md` |
| 🖼️ Capturas | `docs/portal-acceso/img/` |

---

## 3. Decisiones Técnicas

| Decisión | Alternativa | Motivo |
|----------|------------|--------|
| **FastAPI + Jinja2** (SSR) | React/Vue SPA | Sin JS pesado, carga instantánea, accesible sin JS |
| **ldap3 bind directo** | OIDC/SAML | Complejidad innecesaria para 17 usuarios |
| **JWT stateless** | Sesiones en servidor | Escala horizontalmente, sin DB, sin Redis |
| **Config YAML** | UI web | Versionable, revisable en PR, sin estado |
| **Font Awesome icons** | PNGs descargados | Sin assets externos, siempre disponibles |
| **Systemd directo** | Docker | Menor complejidad operativa, logs nativos |

---

## 4. Infraestructura Afectada

| Recurso | Cambio | Impacto |
|---------|--------|---------|
| GitLab VM (192.168.1.41) | Authentik eliminado (puertos 9000/9443 liberados) | Sin impacto en GitLab |
| CT 208 (192.168.1.43) | Homer reemplazado por portal custom | Portal ahora funcional con login |
| VM 207 (192.168.1.42) | Eliminada | 1.5GB RAM, 32GB disco liberados |
| MikroTik (192.168.1.1) | DNS `portal.gidas.local → 192.168.1.43` | Resolución en LAN |

---

## 5. Verificación

| Criterio | Resultado |
|----------|-----------|
| Login AD con credenciales válidas | ✅ `infrait` autenticado, sesión JWT creada |
| Login con credenciales inválidas | ✅ Redirección a `/login?error=1` |
| Dashboard filtrado por grupos | ✅ `infrait` ve solo Identity Dashboard (grupo G-IdentityAdmins) |
| Sin sesión activa redirige a login | ✅ Probado con cookie expirada |
| API `/api/me` devuelve datos del usuario | ✅ `{"username":"infrait","groups":["APP-Redmine","G-IdentityAdmins"]}` |
| Portal responde en puerto 80 | ✅ nginx detenido, uvicorn en puerto 80 |
| GitLab accesible | ✅ System nginx en puerto 80 impedía a GitLab nginx funcionar (loop de reinicios). Solucionado: system nginx detenido, GitLab nginx reiniciado. |

---

## 6. Incidencias Post-Implementación

### GitLab no cargaba por conflicto de puertos

**Síntoma**: `https://gitlab.gidas.local` no cargaba. HTTPS devolvía "Connection reset by peer".

**Causa raíz**: El system nginx de Rocky Linux (que había quedado instalado de la etapa Homer) ocupaba el puerto 80. GitLab nginx intentaba bindear puerto 80 (para el redirect HTTP→HTTPS) pero fallaba porque ya estaba en uso. Esto causaba un loop de reinicios en GitLab nginx que también afectaba al puerto 443.

**Solución**:
```bash
systemctl stop nginx        # detener system nginx
systemctl disable nginx     # evitar que inicie en boot
gitlab-ctl restart nginx    # reiniciar GitLab nginx
```

**Lección**: Al reemplazar Homer, el system nginx (instalado como dependencia) quedó corriendo. Debe siempre verificarse que no haya servicios legacy ocupando puertos necesarios para GitLab.

---

## 7. Lecciones Aprendidas

Ver documento completo en `docs/portal-acceso/diseno/lecciones-aprendidas.md`.

### Principales:
- **Authentik** es overkill para 17 usuarios y 6 herramientas. La complejidad de OIDC/SAML no se justifica.
- **Homer** resuelve el dashboard visual pero no la autenticación ni el control de acceso.
- Un **portal custom** de 200 líneas es más mantenible que un IdP completo cuando el dominio es pequeño.
- **ldap3** con bind directo es simple y efectivo: service account busca, bind como usuario verifica.
- **JWT stateless** elimina la necesidad de base de datos y sesiones en servidor.

---

## 7. Trabajo Futuro

| Tarea | Prioridad |
|-------|-----------|
| Agregar Twingate resource para portal.gidas.local (acceso remoto) | Media |
| Link en Drupal gidas.frlp.utn.edu.ar | Baja |
| Logo GIDAS oficial y tool icons personalizados | Baja |
| Prueba con usuarios reales (verificar grupos AD) | Media |
