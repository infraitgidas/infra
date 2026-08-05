# Herramientas Pendientes de Disponibilizar

> **Rama**: `feat/herramientas-pendientes`
> **Última verificación**: 2026-08-05
> **Criterio**: "disponibilizada" = deployada en producción, accesible por DNS y operativa (no basta el código versionado).

## Resumen

Tres herramientas están implementadas (o planificadas) en el repo pero **no operan en producción**:

| # | Herramienta | Código | Specs SDD | En producción | Bloqueante principal |
|---|-------------|--------|-----------|---------------|----------------------|
| 1 | **GLPI** (ITSM) | ✅ `itsm/` | ✅ 4 specs | ❌ | Deploy + DNS + portal |
| 2 | **NetBox** (CMDB) | ❌ `cmdb/` vacío | ✅ SDD completo | ❌ | Implementar el stack desde cero |
| 3 | **Ansible** | ❌ — | ❌ | ❌ | SDD: definir alcance y arquitectura |

## Estado verificado por herramienta

### 1. GLPI — Gestor ITSM

- **Código**: `itsm/` (docker-compose glpi+mariadb+nginx, `scripts/install-glpi.sh`, backup/restore, webhooks Redmine/GitLab, LDAP FreeIPA, `docs/post-deploy-config.md`).
- **SDD**: specs `itsm-core`, `itsm-ldap-auth`, `itsm-backup`, `itsm-integrations`; change `openspec/changes/itsm/` con 18 tareas en 6 fases completadas.
- **Producción**: ❌ No existe CT/VM de GLPI en pve-desa04 (CTs activos: 208 portal, 209 vaultwarden, 210 librenms, 211 freeradius; VMs: 201 gitlab, 206 redmine). `glpi.gidas.local` no resuelve en DNS.
- **Para disponibilizar**:
  1. Crear CT nuevo en pve-desa04 (patrón: CT 212, Rocky Linux, IP fija en la LAN).
  2. Deploy del stack `itsm/` (docker compose + scripts).
  3. DNS en MikroTik: `glpi.gidas.local` → IP del CT.
  4. Alta en el portal (config.yaml de `portal-gidas/`) con grupo AD.
  5. Verificación LDAP FreeIPA + cron interno + backup.

### 2. NetBox — Gestor CMDB

- **Código**: ❌ `cmdb/` está VACÍO (nunca se commiteó código).
- **SDD**: change `openspec/changes/cmdb/` completo (exploration, proposal, design, `specs/cmdb/`). PROJECT.md reportaba "14/14 tareas" — **incorrecto**: las tareas no tienen implementación.
- **Producción**: ❌ `netbox.gidas.local` no resuelve; no hay CT/VM.
- **Para disponibilizar**:
  1. Implementar el stack NetBox 4.x (Docker Compose + PostgreSQL 15 + Redis 7) según `openspec/changes/cmdb/design.md`.
  2. Scripts de discovery (Proxmox, MikroTik, LDAP) planificados en el SDD.
  3. DNS MikroTik + alta en portal.
  4. Verificar límite de alcance: NetBox = SSoT de infra; GLPI-managed se marca como nota de límite (spec `itsm-core`).

### 3. Ansible — Automatización

- **Código**: ❌ No existe.
- **SDD**: ❌ No existe (`openspec/changes/ansible/` a crear).
- **Producción**: ❌.
- **Contexto previo**: mencionado en `openspec/changes/cmdb/exploration.md` (integración con NetBox) y `openspec/changes/archive/2026-06-02-gitlab/design.md` (alternativa al patrón scripting Bash+SSH).
- **Para iniciar**:
  1. SDD exploration: definir alcance (¿orquestación de deploys existentes? ¿gestión de configs? ¿provisioning de CTs/VMs?).
  2. Decidir rol vs el patrón actual del repo (scripts `00-env.sh` + numerados).
  3. Proposal con inventario de tareas automatizables en la infra actual.

## Decisiones pendientes (para el equipo)

- [ ] ¿GLPI en CT propio (212) o en VM? — CT es el patrón del repo (208/210/211).
- [ ] ¿NetBox en CT o VM? — necesita más recursos que GLPI (PostgreSQL+Redis).
- [ ] ¿Alcance inicial de Ansible: deploy de stacks existentes, config drift, o ambos?
- [ ] ¿Alta de las 3 en el portal unificado (config.yaml) apenas estén disponibles?

## Siguientes pasos propuestos

1. **GLPI**: deploy CT 212 + stack `itsm/` + DNS + portal → verificación end-to-end.
2. **NetBox**: implementar stack según SDD (es el que más trabajo de código requiere).
3. **Ansible**: exploration SDD en `openspec/changes/ansible/` (arrancar sin código).
