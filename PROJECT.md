# Proyecto Infra — Grupo de Investigación Gidas

## Features

| # | Feature | Herramienta | Directorio | Rama | Estado SDD |
|---|---------|-------------|-----------|------|------------|
| 1 | Gestor de proyecto | Redmine | `redmine/` | `feature/redmine` | 🛠️ Implementación ✅ |
| 2 | VCS onpremise | GitLab | `gitlab/` | `feature/gitlab` | 📦 Archivado ✅ |
| 3 | Gestor CMDB | NetBox | `cmdb/` | `feature/cmdb` | 🛠️ Implementación ✅ |
| 4 | Gestor ITSM | GLPI | `itsm/` | `feature/itsm` | 🛠️ Implementación ✅ |

## Leyenda de Estados SDD

- ⏳ Pendiente — no iniciado
- 🔍 Exploración — analizando requisitos y alternativas
- 📋 Propuesta — definiendo alcance y enfoque
- 📐 Especificación — escribiendo requisitos detallados
- 🏗️ Diseño — definiendo arquitectura
- 📝 Tareas — desglosando implementación
- 🛠️ Implementación — codificando
- ✅ Verificación — validando contra specs
- 📦 Archivado — cambio cerrado

---

## Seguimiento por Feature

### Feature 1: Gestor de Proyecto — Redmine

- **Objetivo**: Instalar y configurar Redmine como gestor de proyectos open source
- **Componentes**: redmine:6.1 + postgres:16 + nginx en Docker Compose, CT en pve-ad
- **Estado SDD**: 🛠️ Implementación ✅ — 14/14 tareas
- **Tareas Completadas**: Scripts de deploy (00-env, 01-create-ct, 02-deploy-stack, 03-configure-ssl, 04-backup, 05-verify), docker-compose.yml, nginx config, .gitignore
- **Archivos**: `redmine/`

---

### Feature 2: VCS On-Premise — GitLab

- **Objetivo**: Instalar y configurar GitLab como sistema de control de versiones on-premise
- **Componentes**: GitLab CE Omnibus en VM dedicada (Rocky Linux 10)
- **Estado SDD**: 📦 Archivado ✅ — 19/19 tareas, PASS verify (12/15 COMPLIANT, 3 PARTIAL)
- **Tareas Completadas**: Scripts de provision VM, instalación, HTTPS, SSH, firewall, backups, snapshot PVE, restore, runbook, verification
- **Archivos**: `gitlab/install/`, `gitlab/backup/`, `gitlab/docs/`
- **Archivo SDD**: `openspec/changes/archive/2026-06-02-gitlab/`

---

### Feature 3: Gestor CMDB

- **Objetivo**: Implementar una CMDB (Configuration Management Database) para inventario de infraestructura
- **Componentes**: NetBox 4.x (Docker Compose), PostgreSQL 15, Redis 7, scripts discovery (Proxmox, Mikrotik, LDAP)
- **Estado SDD**: 🛠️ Implementación
- **Tareas**: 14/14 completadas (apply)
- **Tareas Completadas**: Deploy stack, scripts base, discovery scripts, documentación

---

### Feature 4: Gestor ITSM — GLPI

- **Objetivo**: Implementar un sistema ITSM (IT Service Management) para gestión de incidentes, cambios y problemas
- **Componentes**: GLPI + MariaDB + nginx en Docker Compose, scripts backup/restore/integraciones/LDAP
- **Estado SDD**: 🛠️ Implementación
- **Tareas**: 18 tareas en 6 fases
- **Tareas Completadas**: F1 (stack), F2 (post-deploy), F3 (backup/restore), F4 (integraciones), F5 (LDAP), F6 (verificación)

---

*Última actualización: 2026-06-02*
