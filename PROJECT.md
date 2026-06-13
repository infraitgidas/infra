# Proyecto Infra — Grupo de Investigación Gidas

## Features

| # | Feature | Herramienta | Directorio | Rama | Estado SDD |
|---|---------|-------------|-----------|------|------------|
| 1 | Gestor de proyecto | Redmine | `redmine/` | `feature/redmine` | 🛠️ Implementación ✅ |
| 2 | VCS onpremise | GitLab | `gitlab/` | `feature/gitlab` | 📦 Archivado ✅ |
| 3 | Gestor CMDB | NetBox | `cmdb/` | `feature/cmdb` | 🛠️ Implementación ✅ |
| 4 | Gestor ITSM | GLPI | `itsm/` | `feature/itsm` | 🛠️ Implementación ✅ |
| 5 | Identidad AD+FreeIPA | identity-dashboard | `identity-dashboard/` | `main` | 🛠️ Implementación ✅ |

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
- **Componentes**: redmine:6.1 + postgres:16 + nginx en Docker Compose, VM en pve-desa04
- **Estado SDD**: 📦 Archivado ✅ — Ciclo completo
- **Tareas Completadas**:
  - Scripts de deploy (00-env a 06-restore), docker-compose.yml, nginx SSL, backups
  - Autenticación LDAP contra AD GDC01 (filtro grupo `redmine`, onthefly_register)
  - 7 proyectos: Dirección, Administración, CAPNEE, INFRAiT, TELEPARK, GMET, GIS
  - 6 roles: Director, Coordinador, Graduado, Becario, Pasante, Externo
  - Workflow: Nueva → Iniciada → En Revisión → En Espera → Terminada → Cerrada
  - SMTP Outlook configurado (infrait@frlp.utn.edu.ar)
  - Notificaciones por mail: nueva issue → todos los miembros, asignación → asignado
  - Dashboard público `/dashboard/` con tabla dinámica, colores y alertas en tiempo real
  - 12 usuarios AD habilitados con password Gidas2026
  - Correos de bienvenida con credenciales de primer login enviados
- **Archivos**: `redmine/`
- **Archivo SDD**: `openspec/changes/redmine/`

---

### Feature 2: VCS On-Premise — GitLab

- **Objetivo**: Instalar y configurar GitLab como sistema de control de versiones on-premise
- **Componentes**: GitLab CE Omnibus en VM dedicada (Rocky Linux 10), pve-desa04, 4vCPU/8GB/80G, OVMF UEFI, IP 192.168.1.41
- **Estado SDD**: 🛠️ Implementación ✅ — GitLab 19.0.2 operativo con integración AD completa
- **Tareas Completadas**:
  - Migración pve-desa01 → pve-desa04
  - VM con OVMF UEFI, 80G, 4vCPU/8GB
  - IP 192.168.1.41/24 estática
  - DNS MikroTik: `gitlab.gidas.local`
  - GitLab CE 19.0.2 Omnibus instalado (17/17 servicios)
  - HTTPS self-signed + SSH Git puerto 2222 DNAT (→ VM:2222, gitlab-sshd)
  - Firewall PVE host (80, 443, 2222)
  - Integración LDAP activada (`infrait / Gidas2026!`)
  - Token API generado (`sync-ad-members`)
  - 17 usuarios AD importados a GitLab
  - 7 grupos GitLab creados con mapeo AD (G-Direccion→Owner, G-Coordinadores→Maintainer, G-Becarios→Developer)
  - Script `gitlab/scripts/sync-ad-members.sh` (sync AD → GitLab)
  - Backup diario (cron 02:00) + snapshot semanal PVE (dom 03:00)
  - Runbook actualizado, informe de avance
- **Pendiente**: Probar restore de backup
- **Archivos**: `gitlab/install/`, `gitlab/backup/`, `gitlab/scripts/`, `gitlab/docs/`
- **Archivo SDD**: `openspec/changes/archive/2026-06-13-gitlab-deploy/`

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

### Feature 5: Identidad AD+FreeIPA — identity-dashboard

- **Objetivo**: Herramienta unificada CLI + TUI para gestión de usuarios en Active Directory y FreeIPA
- **Componentes**: Python/Click (CLI), Python/rich+questionary (TUI), SOPS secrets, Makefile
- **Estado SDD**: 🛠️ Implementación ✅
- **Tareas Completadas**:
  - CLI completo: user CRUD, grupos, HBAC, password reset con rollback
  - TUI interactivo con menú de 7 opciones
  - Creación de usuarios con email, selector de proyectos y grupos desde AD
  - SMTP Outlook configurado (infrait@frlp.utn.edu.ar)
  - Welcome email al nuevo usuario + notificación al admin
  - Makefile para comandos rápidos
  - Documentación en `docs/identity-dashboard.md`
- **Archivos**: `identity-dashboard/`, `secrets/identity.yaml`, `docs/identity-dashboard.md`, `Makefile`

---

*Última actualización: 2026-06-13*
