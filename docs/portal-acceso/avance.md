# Informe de Avance — Portal de Acceso Unificado + SSO

> **Feature**: Portal SSO (Feature #5)
> **Fecha**: 2026-06-13
> **Rama**: `feat/portal-access-remoto`
> **Estado SDD**: 📐 Especificación + 🏗️ Diseño completados

---

## Resumen

Se definió la arquitectura para un portal único de acceso a herramientas del grupo GIDAS, utilizando **Authentik** como Identity Provider centralizado con autenticación contra AD y SSO vía OIDC/OAuth.

## Decisión Arquitectónica

| Aspecto | Decisión | Motivo |
|---------|----------|--------|
| **IdP** | Authentik | Dashboard nativo con cards, menor consumo que Keycloak, outposts para apps legacy |
| **Autenticación** | LDAP → AD GDC01.local | Misma fuente de identidad que Redmine y GitLab |
| **SSO** | OIDC (GitLab, Redmine) + OAuth (Grafana) | Estándares abiertos, soporte nativo |
| **Acceso remoto** | Twingate | Ya en uso, zero trust, sin exponer puertos |
| **Portal público** | Drupal gidas.frlp.utn.edu.ar → link | UTN controla el hosting, solo agregamos enlace |

## Artefactos SDD Generados

| Artifact | Archivo |
|----------|---------|
| 📋 Propuesta | `openspec/changes/sso-portal-acceso/proposal.md` |
| 📐 Specs (6) | `openspec/specs/sso/{authentik,gitlab,grafana,redmine,proxmox}/spec.md` |
| 📐 Spec | `openspec/specs/networking/public-access/spec.md` |
| 🏗️ Diseño | `openspec/changes/sso-portal-acceso/design.md` |
| 📝 Tareas | `openspec/changes/sso-portal-acceso/tasks.md` |
| 📊 Análisis | `docs/portal-acceso/analisis-alternativas.md` |

## Pendientes

| # | Tarea | Prioridad | Estado |
|---|-------|-----------|--------|
| 1 | Provisionar VM Authentik (1vCPU, 1.5GB) en pve-desa04 | **Alta** | ⏳ Pendiente |
| 2 | Desplegar Authentik Docker Compose | **Alta** | ⏳ Pendiente |
| 3 | Integrar LDAP con AD | **Alta** | ⏳ Pendiente |
| 4 | Configurar SSO GitLab (OIDC) | **Alta** | ⏳ Pendiente |
| 5 | Configurar SSO Grafana (OAuth) | **Alta** | ⏳ Pendiente |
| 6 | Configurar SSO Redmine (OIDC) | **Alta** | ⏳ Pendiente |
| 7 | Configurar LDAP Proxmox | Media | ⏳ Pendiente |
| 8 | DNS MikroTik + link en Drupal | Media | ⏳ Pendiente |
| 9 | Documentación y verificación | Media | ⏳ Pendiente |

---

## Próximo Paso

Comenzar implementación (Phase 1): provisionar VM y desplegar Authentik.
