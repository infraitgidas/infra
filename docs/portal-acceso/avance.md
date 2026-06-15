# Informe de Avance — Portal de Acceso Unificado + SSO

> **Feature**: Portal SSO (Feature #5)
> **Fecha**: 2026-06-14
> **Rama**: `feat/portal-access-remoto`
> **Estado SDD**: 🛠️ Implementación — Fases 1-3 completadas

---

## Resumen

Authentik 2026.5.3 desplegado y operativo como Identity Provider centralizado. LDAP sincronizado con AD GDC01. Providers OIDC/OAuth creados para GitLab, Grafana y Redmine. GitLab ya configurado con SSO. Pendiente: Grafana, Redmine, Proxmox, DNS y publicación.

## Decisión Arquitectónica

| Aspecto | Decisión | Motivo |
|---------|----------|--------|
| **IdP** | Authentik | Dashboard nativo con cards, menor consumo que Keycloak, outposts para apps legacy |
| **Autenticación** | LDAP → AD GDC01.local | Misma fuente de identidad que Redmine y GitLab |
| **SSO** | OIDC (GitLab, Redmine) + OAuth (Grafana) | Estándares abiertos, soporte nativo |
| **Acceso remoto** | Twingate | Ya en uso, zero trust, sin exponer puertos |
| **Portal público** | Drupal gidas.frlp.utn.edu.ar → link | UTN controla el hosting, solo agregamos enlace |

## Estado de Implementación

| Componente | Estado | Detalle |
|------------|--------|---------|
| **Authentik** | ✅ Corriendo | 2026.5.3 en GitLab VM |
| **Admin** | ✅ Configurado | akadmin / hlvs.2025 |
| **Setup** | ✅ Completado | Bypass del initial-setup flow |
| **LDAP con AD** | ✅ Conectado y sincronizado | 17 usuarios AD importados a Authentik (sync vía ak shell, worker Dramatiq requiere fix) |
| **GitLab Provider** | ✅ Creado | OIDC Provider + Application en Authentik |
| **Grafana Provider** | ✅ Creado | OAuth2 Provider + Application en Authentik |
| **Redmine Provider** | ✅ Creado | OAuth2 Provider + Application en Authentik |
| **SSO GitLab** | ✅ Configurado | Omniauth OIDC en gitlab.rb + reconfigure |
| **SSO Grafana** | ⏳ Pendiente | Falta configurar grafana.ini en CT 205 |
| **SSO Redmine** | ⏳ Pendiente | Falta instalar plugin openid_connect |
| **LDAP Proxmox** | ⏳ Pendiente | Realm LDAP en PVE |
| **DNS MikroTik** | ⏳ Pendiente | portal.gidas.local |
| **VM dedicada** | ⚠️ Creada | VM 207 en pve-desa04 — cloud-init fix pendiente |

## Secrets de Integración

| App | Client ID | Client Secret |
|-----|-----------|---------------|
| GitLab | `gitlab` | `0ca3f43271d9d50e1ba4b94e8a29d043b9ae4b5c3a53d49676cfdc718510a407` |
| Grafana | `grafana` | `aecc51050fb80b844f68dd9b10baccd2c975afeed9596e0d71595a1e7a3430de` |
| Redmine | `redmine` | `5abb6e3baadaaca8559029ff48b04af71fd8f094adc9a48929e5a118b871225d` |

## Artefactos SDD Generados

| Artifact | Archivo |
|----------|---------|
| 📋 Propuesta | `openspec/changes/sso-portal-acceso/proposal.md` |
| 📐 Specs (6) | `openspec/specs/sso/{authentik,gitlab,grafana,redmine,proxmox}/spec.md` |
| 📐 Spec | `openspec/specs/networking/public-access/spec.md` |
| 🏗️ Diseño | `openspec/changes/sso-portal-acceso/design.md` |
| 📝 Tareas | `openspec/changes/sso-portal-acceso/tasks.md` |
| 📊 Análisis | `docs/portal-acceso/analisis-alternativas.md` |
| 📊 Avance | `docs/portal-acceso/avance.md` |

## Acceso

| Recurso | URL / Comando |
|---------|--------------|
| **Authentik Admin** | `http://192.168.1.41:9000/if/admin/` |
| **Admin user** | `akadmin` / `hlvs.2025` |
| **Docker Compose** | `/root/portal/` en GitLab VM |
| **API Token** | `bddRcVFkoKzhC3PnqQYH73m04gYgqX3FX9ZYVmGmCTyk76mnqseMLRZvGd71` |

## Pendientes

| # | Tarea | Prioridad | Estado |
|---|-------|-----------|--------|
| 1 | ✅ Authentik desplegado y setup completado | Alta | ✅ |
| 2 | ✅ 17 usuarios AD importados a Authentik (fix sync vía ak shell) | Alta | ✅ |
| 3 | ✅ Providers OIDC/OAuth creados (GitLab, Grafana, Redmine) | Alta | ✅ |
| 4 | ✅ SSO GitLab configurado (omniauth + reconfigure) | Alta | ✅ |
| 5 | Configurar SSO Grafana (grafana.ini en CT 205) | **Alta** | ⏳ |
| 6 | Instalar plugin OIDC en Redmine y configurar | **Alta** | ⏳ |
| 7 | Configurar LDAP realm en Proxmox | Media | ⏳ |
| 8 | DNS MikroTik portal.gidas.local + link en Drupal | Media | ⏳ |
| 9 | Migrar Authentik a VM 207 dedicada | Media | ⏳ |

## Configuración Pendiente — Detalle

### Grafana (CT 205 — 192.168.1.205)
Agregar a `/etc/grafana/grafana.ini`:
```ini
[auth.generic_oauth]
enabled = true
name = Authentik SSO
allow_sign_up = true
client_id = grafana
client_secret = aecc51050fb80b844f68dd9b10baccd2c975afeed9596e0d71595a1e7a3430de
scopes = openid profile email
auth_url = http://192.168.1.41:9000/application/grafana/authorize/
token_url = http://192.168.1.41:9000/application/grafana/token/
api_url = http://192.168.1.41:9000/application/grafana/userinfo/
```
Reiniciar: `systemctl restart grafana-server`

### Proxmox (pve-desa04)
Datacenter → Authentication → Add → LDAP:
```
Host: 192.168.1.117
Base DN: DC=GDC01,DC=local
Bind DN: CN=infrait,OU=ServiceAccounts,DC=GDC01,DC=local
Password: Gidas2026!
User filter: (objectClass=user)
```
