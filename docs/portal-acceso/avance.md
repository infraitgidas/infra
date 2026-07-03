# Informe de Avance — Portal de Acceso GIDAS

> **Feature**: Portal de Acceso (Feature #6)
> **Fecha**: 2026-07-02 (actualizado 23:59)
> **Rama**: `feat/monitoreo-red` (nueva feature)
> **Estado SDD**: ✅ Implementado

---

## Resumen

Portal web custom desarrollado con FastAPI + LDAP que permite a los miembros de GIDAS autenticarse con su usuario de AD y acceder solo a las herramientas correspondientes a sus grupos.

**Evolución del proyecto**:

1. ❌ Authentik (IdP) — demasiado complejo, SSO incompleto, mantenimiento alto
2. ❌ Homer (dashboard estático) — no tiene login ni RBAC
3. ✅ **Portal custom FastAPI+LDAP** — login AD, dashboard filtrado por grupos, config YAML
4. ✅ **Vaultwarden** — gestor de contraseñas con LDAP y SMTP, integrado al portal
5. ✅ **LibreNMS** — monitoreo de red con auto-discovery, LDAP y alertas multicanal

---

## Decisión Arquitectónica

| Aspecto | Authentik | Homer | Portal Custom (actual) |
|---------|-----------|-------|----------------------|
| **Login** | SSO vía OIDC/OAuth | ❌ No tiene | ✅ LDAP directo contra AD |
| **RBAC** | Por IdP | ❌ No tiene | ✅ Por grupos AD (memberOf) |
| **Dashboard** | Cards nativas | Cards estáticas | ✅ SSR con Jinja2 |
| **Config** | UI web + secrets | YAML | ✅ YAML versionable |
| **Dependencias** | 4 containers + DB | nginx solo | ✅ FastAPI + ldap3 |
| **Mantenimiento** | Alto | Cero | ✅ Bajo (sin DB, sin workers) |
| **Recursos** | 1.5GB RAM | 512MB RAM | ✅ ~40MB RAM |

---

## Documentación Generada

### Diseño (`docs/portal-acceso/diseno/`)

| Documento | Archivo | Contenido |
|-----------|---------|-----------|
| 🏗️ Arquitectura | `docs/portal-acceso/diseno/arquitectura.md` | Stack, principios, componentes, flujo auth, modelo de datos |
| 🔧 Diseño Técnico | `docs/portal-acceso/diseno/diseno-tecnico.md` | Rutas HTTP, templates, config.yaml, seguridad, deploy |
| 📋 Lecciones Aprendidas | `docs/portal-acceso/diseno/lecciones-aprendidas.md` | Por qué Authentik y Homer no funcionaron |
| 📊 Análisis Alternativas | `docs/portal-acceso/diseno/analisis-alternativas.md` | Evaluación original de opciones |
| 🖼️ Capturas | `docs/portal-acceso/img/` | 3 screenshots del portal funcionando |

### Manuales (`docs/portal-acceso/manuales/`)

| Documento | Archivo | Contenido |
|-----------|---------|-----------|
| 👤 Guía de Usuario | `docs/portal-acceso/manuales/guia-usuario.md` | Login, dashboard, errores comunes, FAQ |
| 🔧 Guía de Administración | `docs/portal-acceso/manuales/guia-admin.md` | Config, mantenimiento, debug, rollback |

### Vaultwarden (`vaultwarden/`)

| Documento | Archivo | Contenido |
|-----------|---------|-----------|
| 📋 Deploy | `vaultwarden/deploy.sh` | Script de deploy completo |
| 🐳 Docker | `vaultwarden/docker-compose.yml` | Composición oficial |
| 🔧 Config | `vaultwarden/.env.example` | Variables de entorno documentadas |
| 📖 README | `vaultwarden/README.md` | Documentación de deploy y admin |
| 📄 SDD | `openspec/changes/vaultwarden/` | Propuesta, especificación, diseño, tareas |

| Artefacto | Archivo |
|-----------|---------|
| 📋 Propuesta | `openspec/changes/portal-custom/proposal.md` |
| 📐 Especificación | `openspec/changes/portal-custom/specs/portal/spec.md` |
| 🏗️ Diseño | `openspec/changes/portal-custom/design.md` |
| 📝 Tareas | `openspec/changes/portal-custom/tasks.md` |

---

## Infraestructura

| Recurso | Detalle |
|---------|---------|
| **CT 208** | Rocky Linux 9, 512MB RAM, 1 vCPU, IP `192.168.1.43/24` |
| **Servicio** | `portal-gidas.service` (uvicorn) en puerto 80 |
| **App** | FastAPI + Jinja2 + ldap3 + JWT |
| **Código** | `portal-gidas/` en el repo |
| **Config** | `/opt/portal-gidas/config.yaml` (11 herramientas) |
| **Logs** | `journalctl -u portal-gidas` |
| **CT 209** | Rocky Linux 9, 512MB RAM, 1 vCPU, IP `192.168.1.44/24` |
| **Vaultwarden** | Docker + LDAP + nginx SSL en `https://vault.gidas.local` |
| **CT 210** | Rocky Linux 9, 1GB RAM, 1 vCPU, IP `192.168.1.45/24` |
| **LibreNMS** | Docker Compose (librenms + mariadb + redis) + nginx SSL en `https://nms.gidas.local` |

---

## Estado de Implementación

| Componente | Estado | Detalle |
|------------|--------|---------|
| **Authentik** | ❌ Eliminado | Containers, imágenes, datos borrados |
| **Homer** | ❌ Reemplazado | Reemplazado por portal custom |
| **CT 208** | ✅ Portal custom | FastAPI + LDAP + JWT en puerto 80 |
| **Login AD** | ✅ Funcionando | Bind contra AD GDC01, verificación de password |
| **RBAC** | ✅ Funcionando | Filtra tools según grupos AD del usuario |
| **Dashboard** | ✅ 12 herramientas | + Vaultwarden (gestor de contraseñas) |
| **Grafana** | ✅ AD directo | LDAP configurado y verificado |
| **Proxmox** | ✅ Realm LDAP | `gidas-ldap`, 17 usuarios sincronizados |
| **DNS MikroTik** | ✅ `portal.gidas.local` | Resuelve en LAN |
| **GitLab** | ✅ Restaurado | System nginx ocupaba puerto 80. Solucionado: system nginx detenido, GitLab nginx reiniciado. |
| **Vaultwarden** | ✅ Desplegado | CT 209, Docker, LDAP, SSL. Card en portal. |
| **LibreNMS** | ✅ Desplegado | CT 210, Docker Compose, LDAP, SSL. Alertas email configuradas. |
| **VM 207** | ❌ Eliminada | Ex-Authentik, 1.5GB RAM liberados |

---

## Dashboard — Herramientas por Grupo

| Herramienta | Grupos con acceso |
|------------|------------------|
| GitLab | Todos los grupos GIDAS |
| Redmine | Dirección, Coordinadores, Becarios, Graduados, Pasantes |
| Grafana | Dirección, Coordinadores |
| Proxmox VE | Dirección, Coordinadores |
| NetBox | Dirección, Coordinadores, Becarios |
| GLPI | Dirección, Coordinadores |
| MikroTik | Dirección, Coordinadores |
| Identity Dashboard | Dirección, Coordinadores, IdentityAdmins |
| Vaultwarden | Dirección, Coordinadores, Becarios, Graduados, Pasantes, Externos, IdentityAdmins |
| Drupal GIDAS | Todos |
| Correo UTN | Todos |
| Twingate | Todos |

---

## Acceso

| Recurso | URL / Comando |
|---------|--------------|
| **Portal** | `http://portal.gidas.local` (LAN) o `http://192.168.1.43` |
| **Login** | Usuario y contraseña de AD GIDAS |
| **Dashboard** | Cards filtradas según grupos AD del usuario |
| **Admin SSH portal** | `pct enter 208` (desde pve-desa04) |
| **Admin SSH vault** | `pct enter 209` (desde pve-desa04) |
| **Admin SSH librenms** | `pct enter 210` (desde pve-desa04) |
| **Vaultwarden** | `https://vault.gidas.local` — login con email + master password |
| **Admin panel vault** | `https://vault.gidas.local/admin` — token en secrets |
| **LibreNMS** | `https://nms.gidas.local` — login con usuario AD |
| **Logs portal** | `journalctl -u portal-gidas -f` |
| **Logs vault** | `docker logs vaultwarden -f` |
| **Logs librenms** | `docker compose -f /opt/librenms/docker-compose.yml logs -f` |
| **Telegram** | @GiDAS_alertbot — bot operativo para alertas de red |

---

## Pendientes

| # | Tarea | Prioridad | Estado |
|---|-------|-----------|--------|
| 1 | ✅ Portal custom implementado y deployado | Alta | ✅ |
| 2 | ✅ Login AD funcionando con RBAC | Alta | ✅ |
| 3 | ✅ Documentación completa (diseño + manuales + SDD) | Alta | ✅ |
| 4 | ✅ Vaultwarden desplegado y funcional | Alta | ✅ |
| 5 | ✅ SMTP configurado en Vaultwarden (Office 365) | Media | ✅ |
| 6 | ✅ LibreNMS desplegado y funcional | Alta | ✅ |
| 7 | ✅ Telegram Bot configurado para alertas de LibreNMS | Media | ✅ |
| 8 | Twingate resource para `portal.gidas.local` | Media | ⏳ |
| 9 | Link en Drupal gidas.frlp.utn.edu.ar | Baja | ⏳ |
