# Proyecto Infra — Grupo de Investigación Gidas

## Features

| # | Feature | Herramienta | Directorio | Rama | Estado SDD |
|---|---------|-------------|-----------|------|------------|
| 1 | Gestor de proyecto | Redmine | `redmine/` | `feature/redmine` | 📦 Archivado ✅ |
| 2 | VCS onpremise | GitLab | `gitlab/` | `feature/gitlab` | 📦 Archivado ✅ |
| 3 | Gestor CMDB | NetBox | `cmdb/` | `feat/herramientas-pendientes` | 📋 Planificado — SDD ✅, código NO implementado (`cmdb/` vacío) |
| 4 | Gestor ITSM | GLPI | `itsm/` | `feat/herramientas-pendientes` | ✅ Operativo — CT 212 + DNS + portal (LDAP/email pendientes) |
| 5 | Identidad AD+FreeIPA | identity-dashboard | `identity-dashboard/` | `main` | 🛠️ Implementación ✅ |
| 6 | Portal de Acceso Unificado | Portal custom (FastAPI+LDAP) | `portal-gidas/` | `feat/portal-access-remoto` | ✅ Implementado |
| 7 | Monitor de Red | LibreNMS | `librenms/` | — | 🛠️ Operativo con fixes |
| 8 | Dominio gidas.frlp | Acceso Remoto + Portal | `site-tunnel-portal/` | `feat/dominio-gidas-frlp` + `fix/tunnel-monitor-url-dinamica` | 🛠️ Implementado — Tunnel + nginx + 3 tools + Fix falsos positivos |
| 9 | Docker Desktop PCs GIDAS | Docker Desktop (WSL2) | `pcs/docker/` | `feat/docker-pcs-gidas` | 🛠️ Implementación ⚠️ PARCIAL (1/5) |
| 10 | Automatización | Ansible | `ansible/` | `feat/herramientas-pendientes` | 🔍 Exploración — alcance recomendado: progresivo por fases (config base → deploy NetBox → provisioning) |

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

### Feature 3: Gestor CMDB — NetBox

- **Objetivo**: Implementar una CMDB (Configuration Management Database) para inventario de infraestructura
- **Componentes**: NetBox 4.x (Docker Compose), PostgreSQL 15, Redis 7, scripts discovery (Proxmox, Mikrotik, LDAP)
- **Estado SDD**: 📋 Planificado — SDD completo (exploration/proposal/design/specs), código **NO implementado** (`cmdb/` vacío, verificado 2026-08-05)
- **Pendiente**: Implementar el stack según `openspec/changes/cmdb/design.md` (rama `feat/herramientas-pendientes`)

---

### Feature 4: Gestor ITSM — GLPI

- **Objetivo**: Implementar un sistema ITSM (IT Service Management) para gestión de incidentes, cambios y problemas
- **Componentes**: GLPI 10.0.26 (imagen oficial `glpi/glpi:10.0`) + MariaDB + nginx en Docker Compose, scripts backup/restore/integraciones/LDAP
- **Estado SDD**: ✅ **OPERATIVO** — deployado en CT 212 (192.168.1.47), DNS MikroTik, portal y API verificados E2E (ticket id=1). SDD completo (4 specs, 18 tareas). Actualizado 2026-08-06
- **Tareas Completadas**:
  - Migración a imagen oficial `glpi/glpi:10.0` (la imagen `diouxx/glpi` no existe)
  - CT 212 Rocky 9 (2c/4G/20G), Docker CE + Compose, stack en `/opt/glpi`, 3 contenedores healthy
  - DNS MikroTik `glpi.gidas.local → 192.168.1.47` + `/etc/hosts` CT 208 corregido
  - HTTPS con cert autofirmado SAN DNS+IP, nginx 301 http→https
  - API habilitada: App-Token (SOPS), 2 API clients por IP range, E2E verificado
  - Alta en portal (`proxy: true`, G-Direccion/G-Coordinadores), reverse proxy 200
  - Backup `backup.sh` + zstd probado (SUCCESS) + crons CT 212 (cron.php 5min, backup dom 03:00)
  - Config core: `url_base`, `es_AR`, tz Buenos Aires, `enable_api=1`
  - 7 bugs corregidos documentados en `docs/itsm/avance.md` e `openspec/changes/itsm/informe-cambios.md`
- **Pendiente**: LDAP (decidir AD GDC01 vs FreeIPA — FreeIPA no existe en la LAN), SMTP (no hay servidor de correo), integraciones Redmine/GitLab (tokens PENDIENTE)
- **Archivos**: `itsm/`, `secrets/glpi.yaml`, `docs/itsm/avance.md`
- **Archivo SDD**: `openspec/changes/itsm/`

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
  - **Acceso a SGM-GIDAS desde el portal**: card → `/sgm-gidas/` (tunnel Cloudflare),
    sin tocar la LAN (`sgm.gidas.local`). Segundo build del frontend (base `/sgm-gidas/`)
    + contenedor `frontend_sgm` formalizado en el compose. Ver
    `docs/runbooks/sgm-portal-tunnel-hotfix.md` y `docs/runbooks/sgm-despliegue-vm111.md`
    (Cambio: `openspec/changes/sgm-acceso-portal/`). 2026-08-28
- **Pendientes**:
  - Twingate resource para `portal.gidas.local` (acceso remoto)
  - Link en Drupal gidas.frlp.utn.edu.ar
- **Archivos**: `portal-gidas/` (código), `docs/portal-acceso/` (documentación)
- **Archivos SDD**: `openspec/changes/portal-custom/`
- **Archivos**: `docs/portal-acceso/`
- **Archivos SDD**: `openspec/changes/archive/2026-06-14-sso-portal-acceso/` (histórico Authentik)
- **Tools totales**: 13 (incluye LibreNMS incorporado en esta sesión)

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

### Integración Grafana (Pendiente)
- Script `librenms/scripts/setup-grafana.sh` listo para crear API token y datasource
- Plugin `librenms-datasource` para Grafana (instalar vía grafana-cli)
- Queries disponibles: devices, ports, cpu, memory, storage, uptime, traffic

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

### Pendientes (30 tareas — detalle en `tasks.md` Fase 8)
- 🔴 **Alta**: Agregar usuarios AD a `gidas-admins`/`SRV-Monitoring`
- 🔴 **Alta**: Verificar 7 dispositivos con status=0
- 🟡 **Media**: Activar SNMP traps + syslog (puertos expuestos)
- 🟡 **Media**: Schedulear backup automático
- 🟡 **Media**: Heartbeat / monitoreo del monitoreo
- 🟡 **Media**: Merge rama `feat/monitoreo-red` → `main`

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

### Feature 9: Docker Desktop en PCs del Dominio GIDAS

- **Objetivo**: Instalar Docker Desktop (WSL2 backend) en las 5 PCs del dominio GDC01 (.30, .50, .51, .52, .53), con permisos de Domain Users
- **Componentes**: Docker Desktop v29.7.2, WSL2 backend, GPO WinRM, scripts PowerShell/Bash
- **Estado SDD**: 🛠️ Implementación ⚠️ PARCIAL — 1/5 completa
- **Estado por PC**:
  - .51 (GIDAS-002): ✅ Docker v27.5.1 + hello-world OK + Domain Users
  - .50 (gidas-37710): ⚠️ Docker instalado, daemon no arranca (WSL2 kernel update falló)
  - .52 (gidas-desktop-854): ❌ BLOCKED — virtualización deshabilitada en BIOS
  - .53 (GIDAS-003): ❌ BLOCKED — virtualización deshabilitada en BIOS
  - .30 (direccion): ❌ INACCESIBLE — sin SSH/WinRM
- **Tareas Completadas**:
  - Scripts de instalación idempotentes (`pcs/docker/install-docker.ps1`, `enable-winrm.ps1`, `deploy-docker.sh`)
  - Runbook en español (`docs/runbooks/deploy-docker-pcs.md`)
  - GPO `Enable-WinRM-ForManagement` creada en DC1-GIDAS
  - WinRM habilitado en .51, .52, .53, .50
  - Docker Desktop instalado y verificado en .51 (hello-world OK)
  - Domain Users agregado a docker-users en .51 y .50
- **Pendiente**:
  - Habilitar BIOS virtualización en .52 y .53
  - Instalar Docker en .52 y .53 tras habilitar BIOS
  - Verificar estado de .50 (puede estar en Windows Update)
  - Habilitar acceso remoto en .30
- **Archivos**: `pcs/docker/`, `docs/runbooks/deploy-docker-pcs.md`
- **Informe de cambios**: `openspec/changes/docker-pcs/informe-cambios.md`

---

### Feature 10: Automatización — Ansible

- **Objetivo**: Automatización de la infraestructura (deploy de stacks, config drift, orquestación)
- **Componentes**: Inventario YAML por grupos, ansible.cfg, playbooks de config base + deploy reproducible (NetBox como piloto), SOPS integrado
- **Estado SDD**: 🔍 Exploración — exploration en `openspec/changes/ansible/exploration.md` (2026-08-06). Ansible core 2.16.16 ya instalado en host de trabajo
- **Enfoque recomendado (progresivo por fases)**:
  - **F1 Config base**: sync `/etc/hosts` (arregla drift real del CT 208), health checks de los 7 stacks, verificación de paquetes/utilidades, sync de crontabs — todo no-destructivo
  - **F2 Deploy reproducible**: playbook de deploy de UN stack greenfield — NetBox (Feature 3) como piloto natural (`cmdb/` vacío, SDD listo)
  - **F3 Provisioning Proxmox** (API) + evaluar MikroTik v6/Windows (probablemente fuera de alcance)
- **Decisiones clave**: mantener SOPS+age (NO ansible-vault); no migrar los 7 stacks existentes de una (riesgo de regresión); Windows/AD fuera del alcance inicial
- **Pendiente**: Proposal (`sdd-propose`) tras confirmar control node (.107 vs CT dedicado), NetBox como piloto F2, y alcance MikroTik/Windows

---

## Pendientes y Especificaciones (consolidado 2026-08-28)

> Este documento conserva TODA la información de las 10 features (Portal, LibreNMS,
> Dominio gidas.frlp, cluster pve-gidas, Docker Desktop PCs, GLPI, NetBox y Ansible).
> Los pendientes abiertos se listan aquí para no perder nada; el detalle queda en los
> respectivos `openspec/changes/` y en `docs/herramientas-pendientes.md`.

- **Portal GIDAS (efecto SGM)**: verificación E2E con usuario AD real de grupo
  `G-Direccion`/`G-Coordinadores` logueado en el portal (infra 100% verificada por
  curl; falta probar el render de la card con login). Runbook:
  `docs/runbooks/sgm-portal-tunnel-hotfix.md`.
- **LibreNMS**: tabular pendientes Fase 8 (usuarios AD, dispositivos status=0,
  SNMP traps/syslog, backup scheduleado, heartbeat) y merge de `feat/monitoreo-red`.
- **Cluster pve-gidas**: merge de la rama `gitlab-gidas` una vez completada la
  validación cruzada.
- **Docker Desktop PCs**: habilitar virtualización en BIOS de .52/.53, instalar
  Docker en ellas, verificar .50 y habilitar acceso remoto en .30.
- **GLPI (Feature 4)**: verificar LDAP (decidir AD GDC01 vs FreeIPA — FreeIPA no
  existe en la LAN), SMTP (no hay servidor de correo), integraciones Redmine/GitLab
  (tokens PENDIENTES). Detalle: `docs/itsm/avance.md` y `openspec/changes/itsm/`.
- **NetBox (Feature 3, CMDB)**: implementar el stack NetBox 4.x según
  `openspec/changes/cmdb/design.md` (`cmdb/` está vacío; solo existe el SDD). Pasa a
  ser el piloto natural de Ansible F2.
- **Ansible (Feature 10)**: escribir la `proposal` (`sdd-propose`) tras confirmar:
  control node (.107 vs CT dedicado), NetBox como piloto F2, y alcance MikroTik/Windows.
  Exploration: `openspec/changes/ansible/exploration.md`.

---

*Última actualización: 2026-08-28* — Merge a `main` de la rama `feat/herramientas-pendientes`
(herramientas pendientes: GLPI operativo, NetBox planificado, Ansible exploración) + conservación
de las 10 features previas. Pendientes persistidos como especificación para continuar luego.
