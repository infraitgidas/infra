# Proyecto Infra — Grupo de Investigación Gidas

## Features

| # | Feature | Herramienta | Directorio | Rama | Estado SDD |
|---|---------|-------------|-----------|------|------------|
| 1 | Gestor de proyecto | Redmine | `redmine/` | `feature/redmine` | 📦 Archivado ✅ |
| 2 | VCS onpremise | GitLab | `gitlab/` | `feature/gitlab` | 📦 Archivado ✅ |
| 3 | Gestor CMDB | NetBox | `cmdb/` | `feature/cmdb` | 🛠️ Implementación ✅ |
| 4 | Gestor ITSM | GLPI | `itsm/` | `feature/itsm` | 🛠️ Implementación ✅ |
| 5 | Identidad AD+FreeIPA | identity-dashboard | `identity-dashboard/` | `main` | 🛠️ Implementación ✅ |
| 6 | Portal de Acceso Unificado | Portal custom (FastAPI+LDAP) | `portal-gidas/` | `feat/portal-access-remoto` | ✅ Implementado |
| 7 | Monitor de Red | LibreNMS | `librenms/` | `main` | 🛠️ Operativo con fixes |

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
  - 12 usuarios AD habilitados (password inicial documentado en secrets)
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
  - Integración LDAP activada (bind service account configurado)
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

### Feature 6: Portal de Acceso Unificado — Portal Custom

- **Objetivo**: Proveer un punto único de acceso con login AD y dashboard filtrado por grupos
- **Componentes**: FastAPI + Jinja2 + ldap3 + JWT. CT Rocky Linux 9 en pve-desa04. Sin IdP, sin DB, sin SSO.
- **Estado SDD**: ✅ Implementado
- **Evolución**:
  - ❌ Authentik (IdP) — eliminado por complejidad excesiva
  - ❌ Homer (dashboard estático) — reemplazado por no tener login ni RBAC
  - ✅ **Portal custom** — login AD, dashboard filtrado por grupos, config YAML
- **Tareas Completadas**:
  - Portal custom FastAPI+LDAP desarrollado y deployado en CT 208
  - Login AD contra GDC01 con verificación de password (ldap3)
  - Dashboard SSR con Jinja2 y CSS vanilla responsive
  - RBAC: filtra herramientas según grupos AD del usuario (intersección memberOf)
  - 11 herramientas configuradas en YAML con mapeo a grupos AD
  - Sesión JWT stateless (cookie HttpOnly, 8h expiración)
  - Branding GIDAS: logo, colores rojos institucionales, UTN en footer
  - DNS MikroTik: `portal.gidas.local → 192.168.1.43`
  - Guías de usuario y administración con capturas de pantalla
  - Documentación completa: arquitectura, diseño técnico, SDD
  - Grafana AD directo (LDAP configurado y verificado)
  - Proxmox realm LDAP (`gidas-ldap`, 17 usuarios sincronizados)
  - Authentik eliminado, Homer reemplazado, VM 207 destruida
- **Pendientes**:
  - Twingate resource para `portal.gidas.local` (acceso remoto)
  - Link en Drupal gidas.frlp.utn.edu.ar
- **Archivos**: `portal-gidas/` (código), `docs/portal-acceso/` (documentación)
- **Archivos SDD**: `openspec/changes/portal-custom/`
- **Archivos**: `docs/portal-acceso/`
- **Archivos SDD**: `openspec/changes/archive/2026-06-14-sso-portal-acceso/` (histórico Authentik)

---

### Rama: `gitlab-gidas` — Optimización del Cluster pve-gidas (en paralelo)

> **Nota**: El trabajo de optimización del cluster Proxmox `pve-gidas` se desarrolla en la rama `gitlab-gidas` (divergida de `main`). No está mergeado aún.

- **Fase 1** — Backups y PBS: scripts de backup automatizado, integración con Proxmox Backup Server
- **Fase 2** — Storage ZFS: migración a ZFS con ashift=12, compression=zstd, atime=off, replicación asíncrona entre pares fijos
- **Fase 3** — Red VLAN: bonding LACP, VLAN 10, corosync link1 redundante, reglas firewall de cluster, reinicio nodo por nodo
- **Fase 4** — Optimización VMs: CPU host, NUMA, VirtIO SCSI Single con iothread, ballooning mínimo
- **Fase 5** — Monitoreo: stack Prometheus + Grafana + Alertmanager
- **Archivos**: `openspec/changes/network-proxmox/`, `scripts/f5-monitoring/`
- **Commits**: 30+ commits con fases documentadas
- **Pendiente**: Merge a `main` una vez completada la validación cruzada

---

---

### Feature 7: Monitor de Red — LibreNMS

- **Objetivo**: Monitoreo de infraestructura de red y servidores vía SNMP con alertas
- **Componentes**: LibreNMS 26.6.1 (Docker), MariaDB 10, Redis 7, Alpine. CT 210 en pve-desa04.
- **Estado**: 🛠️ Operativo — fixes aplicados Julio 2026
- **URL**: `https://nms.gidas.local`
- **Infra**: CT 210 (pve-desa04), Docker compose, nginx + php-fpm internos

### Alert Rules Configuradas (18 reglas)
- 🔴 Device Down, Device Not Polled, High CPU/Memory/Disk (critical), SNMP Disabled, Port Down
- 🟡 Device Rebooted, High CPU/Memory/Disk (warning), High Latency, Slow Polling, Bandwidth Saturation, High Interface Errors, Unclassified Device, High Temperature
- Todas mapeadas a Telegram Bot GIDAS Alertas (@GiDAS_alertbot)

### Tareas Completadas
- ✅ Deploy Docker con volúmenes nombrados (librenms_data, mysql_data, redis_data)
- ✅ APP_KEY y NODE_ID generados
- ✅ 12 dispositivos descubiertos y polleando (PVE hosts, MikroTik, AD DC, servicios)
- ✅ Autenticación AD activada (ActiveDirectory auth mechanism)
- ✅ Mapeo de grupos AD a roles: `gidas-admins`, `SRV-Monitoring`, `G-IdentityAdmins` → admin
- ✅ `auth_ad_global_read = true` — todos los usuarios AD autenticados ven (global-read)
- ✅ Crontab fixeado: `schedule:run` corre como `librenms` (no root)
- ✅ Alert rules vacías eliminadas (causaban error PDO)
- ✅ Script de backup (DB + config)

### Pendientes
- ⏳ Agregar usuarios AD a `gidas-admins` o `SRV-Monitoring` para acceso admin completo
- ⏳ Configurar alertas vía UI (Telegram, email)
- ⏳ Activar SNMP trap receiver (puertos 162/514 ya expuestos)
- ⏳ Agregar monitoreo a los 7 dispositivos con status=0 (IPs sin resolver/responsive)
- ⏳ Backup automatizado (cron en CT 210 o PVE host)
- ⏳ Merge rama `gitlab-gidas` a `main`

### Bugs Fixeados (críticos)
1. **Roles AD borrados en cada login**: `getRoles()` devolvía `[]` sin `auth_ad_groups` configurado, `syncRoles([])` borraba todos los roles. Fix: configurar `auth_ad_groups` + `auth_ad_global_read=true`
2. **Poller nunca ejecutaba**: Cron corría como root pero `artisan schedule:run` rechaza ejecutarse como root. Fix: `su -s /bin/bash librenms -c 'php artisan schedule:run'` en crontab
3. **Alert rules vacías**: Reglas predefinidas con `query` vacío causaban `PDO::prepare() error`. Fix: eliminadas

### Archivos
- `librenms/docker-compose.yml` — stack Docker
- `librenms/deploy.sh` — script de deploy actualizado
- `librenms/scripts/backup.sh` — backup DB + config
- `librenms/scripts/setup-telegram.sh` — guía Telegram (no implementado)

---

*Última actualización: 2026-07-03 (14:30)*
