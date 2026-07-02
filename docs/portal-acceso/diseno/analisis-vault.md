# Análisis de Opciones — Gestor de Contraseñas para GIDAS

> **Feature**: Gestor de Contraseñas (Feature #7, propuesta)
> **Rama**: A definir
> **Fecha**: 2026-07-02

---

## 1. Contexto

Actualmente los miembros de GIDAS tienen que recordar y gestionar contraseñas para múltiples herramientas:
- AD (login de PC y portal)
- GitLab, Redmine, Grafana, Proxmox, NetBox, GLPI, MikroTik
- Correo UTN (Outlook)
- Twingate, Drupal

Un gestor de contraseñas centralizado resuelve: almacenamiento seguro, auto-completado, y (opcionalmente) uso compartido de credenciales entre miembros del equipo.

---

## 2. Alternativas Analizadas

### Alternativa A: Vaultwarden

**Stack**: Rust + SQLite/PostgreSQL + Docker
**Repo**: [dani-garcia/vaultwarden](https://github.com/dani-garcia/vaultwarden) — 42k ⭐
**Licencia**: GPL-3.0

| Aspecto | Evaluación |
|---------|-----------|
| 🚀 **Recursos** | ~30MB RAM, binario único. **Livianísimo.** |
| 🔐 **Seguridad** | Encriptación AES-256 Bitwarden-compatible. Auditado. |
| 🔗 **LDAP/AD** | ✅ Soporte nativo vía variable de entorno |
| 🌐 **Acceso** | Web UI + browser extensions (Chrome, Firefox, Edge) + apps mobile + CLI |
| 🐳 **Deploy** | 1 container Docker con SQLite. Sin dependencias externas. |
| 👥 **Team sharing** | Organizaciones, colecciones, uso compartido |
| 🔧 **Mantenimiento** | Mínimo. Updates: re-pull y restart. |
| 🎯 **Para GIDAS** | **Excelente.** El peso justo para 17 usuarios. |

**Integración con portal**: Link directo desde el dashboard hacia Vaultwarden.

### Alternativa B: Passbolt

**Stack**: PHP + MySQL/MariaDB + Redis + Docker Compose
**Repo**: [passbolt/passbolt](https://github.com/passbolt/passbolt) — 5k ⭐
**Licencia**: AGPL-3.0 (Community Edition)

| Aspecto | Evaluación |
|---------|-----------|
| 🚀 **Recursos** | ~256MB RAM, requiere PHP-FPM + MySQL + Redis + nginx |
| 🔐 **Seguridad** | OpenPGP, cifrado extremo a extremo. Auditado. |
| 🔗 **LDAP/AD** | ✅ Soporte nativo (plugin) |
| 🌐 **Acceso** | Web UI + browser extension **obligatoria** |
| 🐳 **Deploy** | Docker Compose (4+ containers). Más complejo. |
| 👥 **Team sharing** | Excelente. Permisos granulares por recurso. |
| 🔧 **Mantenimiento** | Medio. Updates requieren migraciones de DB. |
| 🎯 **Para GIDAS** | **Buena opción** pero más pesada que Vaultwarden. |

**Puntos en contra vs Vaultwarden**:
- Requiere browser extension (sin web UI completa sin extensión)
- Más recursos y dependencias
- Más complejo de mantener

### Alternativa C: Teampass

**Stack**: PHP + MySQL/MariaDB + LDAP
**Repo**: [nilsmela/teampass](https://github.com/nilsteampassnet/TeamPass) — 1.7k ⭐
**Licencia**: GPL-3.0

| Aspecto | Evaluación |
|---------|-----------|
| 🚀 **Recursos** | ~128MB RAM, requiere PHP + MySQL |
| 🔐 **Seguridad** | Encriptación AES-256 con keys compartidas |
| 🔗 **LDAP/AD** | ✅ Soporte nativo |
| 🌐 **Acceso** | Web UI (no requiere extensión) |
| 🐳 **Deploy** | Docker o directo con PHP-FPM |
| 👥 **Team sharing** | Sí, por carpetas y roles |
| 🔧 **Mantenimiento** | Medio |
| 🎯 **Para GIDAS** | **Opción válida** pero menos pulida que Vaultwarden/Passbolt |

### Alternativa D: Custom (desarrollar en el portal)

**Stack**: FastAPI + SQLite + encriptación Fernet/PyCryptodome

| Aspecto | Evaluación |
|---------|-----------|
| 🚀 **Recursos** | Mínimo (se suma al portal existente) |
| 🔐 **Seguridad** | Depende de implementación. **Riesgo alto.** |
| 🔗 **LDAP/AD** | ✅ Ya lo tenemos |
| 🌐 **Acceso** | Web UI en el mismo portal |
| 🐳 **Deploy** | No requiere nada nuevo |
| 👥 **Team sharing** | Habría que desarrollarlo |
| 🔧 **Mantenimiento** | Alto (somos responsables de la seguridad) |
| 🎯 **Para GIDAS** | **No recomendado.** Gestión de contraseñas es crítica. Mejor usar software auditado. |

**Riesgo**: Cifrado mal implementado → credenciales expuestas.

### Alternativa E: Keycloak

Se mencionó en la consulta inicial. Aclaremos: **Keycloak NO es un gestor de contraseñas.** Es un Identity Provider (IdP) para SSO. Similar a Authentik, que ya evaluamos y descartamos por:

| Problema | Detalle |
|----------|---------|
| **No almacena contraseñas de otras herramientas** | Keycloak solo maneja autenticación de usuarios contra AD. No es un vault. |
| **Complejidad** | Java/Quarkus, requiere DB, Redis. >1GB RAM. |
| **Ya evaluado** | Authentik (misma categoría) fue descartado por ser overkill para 17 usuarios. |

**Conclusión**: Keycloak no aplica para este feature.

---

## 3. Benchmarking

| Criterio | Vaultwarden | Passbolt | Teampass | Custom |
|----------|-------------|----------|---------|--------|
| **RAM** | ~30MB | ~256MB | ~128MB | +~10MB |
| **Containers** | 1 | 4+ | 1-2 | 0 |
| **Deploy inicial** | 5 min | 30 min | 20 min | 2 semanas (dev) |
| **Mantenimiento** | Mínimo | Medio | Medio | Alto |
| **Browser extension** | ✅ Sí (opcional) | ✅ Sí (obligatoria) | ❌ No necesita | ❌ No |
| **Mobile app** | ✅ Bitwarden apps | ✅ Passbolt app | ❌ No | ❌ No |
| **LDAP/AD** | ✅ Nativo | ✅ Plugin | ✅ Nativo | ✅ Ya existe |
| **Team sharing** | ✅ Organizaciones | ✅ Permisos granulares | ✅ Carpetas | Habría que hacerlo |
| **Web UI standalone** | ✅ Completa | ⚠️ Parcial | ✅ Completa | ✅ Completa |
| **Seguridad auditada** | ✅ Bitwarden audits | ✅ Yes | ⚠️ Parcial | ❌ No |
| **Dificultad** | Baja | Media | Media | Alta |

---

## 4. Recomendación

### 🏆 Vaultwarden

Es la opción que mejor se ajusta a GIDAS:

1. **Liviano**: 30MB RAM, 1 container, SQLite. Lo corre cualquier CT.
2. **Bitwarden-compatible**: Los usuarios pueden usar las apps de Bitwarden (mobile, browser, CLI) que ya conocen.
3. **LDAP nativo**: Integración directa con AD GDC01.
4. **Sin deuda técnica**: Software maduro, auditado, 42k ⭐ en GitHub.
5. **Fácil integración**: Agregamos una card en el portal y listo.

**Opciones de deploy:**
- **Opción A**: Nuevo CT liviano (CT 209, 256MB RAM, 1 vCPU) — recomendado
- **Opción B**: Mismo CT del portal (CT 208) como container adicional
- **Opción C**: VM existente (GitLab VM o similar)

### Flujo propuesto

```
                    ┌─────────────────────────────────────┐
                    │         Portal GIDAS                │
                    │  (FastAPI — login AD + dashboard)   │
                    └────────┬────────────┬──────────────┘
                             │            │
                             ▼            ▼
                    ┌────────────┐  ┌────────────┐
                    │ Herramientas│  │ Vaultwarden│
                    │ (GitLab,   │  │ Gestor de  │
                    │  Redmine,  │  │ Contraseñas│
                    │  ...)      │  │ (login AD) │
                    └────────────┘  └────────────┘
```

---

## 5. Próximos Pasos Propuestos

| Paso | Descripción |
|------|-------------|
| 1 | ✅ Aprobar la elección de Vaultwarden |
| 2 | Crear SDD: exploration, proposal, spec, design, tasks |
| 3 | Crear CT/VM para Vaultwarden |
| 4 | Deployar Vaultwarden con Docker |
| 5 | Configurar integración LDAP con AD GDC01 |
| 6 | Agregar card en el portal |
| 7 | Documentar y entregar |
