# Informe de Avance — Portal de Acceso Unificado + SSO

> **Feature**: Portal SSO (Feature #5)
> **Fecha**: 2026-06-13
> **Rama**: `feat/portal-access-remoto`
> **Estado SDD**: 🛠️ Implementación

---

## Resumen

Se implementó Authentik 2026.5.3 como Identity Provider centralizado para el grupo GIDAS, desplegado en Docker Compose sobre la VM de GitLab (192.168.1.41). Pendiente: integración LDAP con AD, configuración de OIDC/OAuth providers, DNS y publicación.

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
| **Authentik** | ✅ Corriendo | 2026.5.3 en GitLab VM (temporal) |
| **Admin** | ✅ Configurado | akadmin / hlvs.2025 |
| **VM dedicada** | ⚠️ Creada | VM 207 en pve-desa04 — cloud-init no aplicó IP (fix pendiente) |
| **LDAP con AD** | ⏳ Pendiente | Conectar Authentik → AD GDC01 |
| **SSO GitLab** | ⏳ Pendiente | OIDC provider + config gitlab.rb |
| **SSO Grafana** | ⏳ Pendiente | OAuth provider + config grafana.ini |
| **SSO Redmine** | ⏳ Pendiente | Plugin openid_connect |
| **DNS MikroTik** | ⏳ Pendiente | portal.gidas.local |
| **Drupal** | ⏳ Pendiente | Link al portal |

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

| Recurso | URL |
|---------|-----|
| **Authentik Admin** | `http://192.168.1.41:9000/if/admin/` |
| **Admin user** | akadmin / hlvs.2025 |
| **Docker Compose** | `/root/portal/` en GitLab VM |

## Pendientes

| # | Tarea | Prioridad | Estado |
|---|-------|-----------|--------|
| 1 | ✅ VM Authentik creada (ID 207, pve-desa04) | Alta | ✅ Completado |
| 2 | ✅ Authentik Docker Compose desplegado | Alta | ✅ Completado |
| 3 | Integrar LDAP con AD | **Alta** | ⏳ Pendiente |
| 4 | Configurar SSO GitLab (OIDC) | **Alta** | ⏳ Pendiente |
| 5 | Configurar SSO Grafana (OAuth) | **Alta** | ⏳ Pendiente |
| 6 | Configurar SSO Redmine (OIDC) | **Alta** | ⏳ Pendiente |
| 7 | Configurar LDAP Proxmox | Media | ⏳ Pendiente |
| 8 | DNS MikroTik + link en Drupal | Media | ⏳ Pendiente |
| 9 | Verificación y archivado SDD | Media | ⏳ Pendiente |
