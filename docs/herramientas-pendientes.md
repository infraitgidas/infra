# Herramientas Pendientes de Disponibilizar

> **Rama**: `feat/herramientas-pendientes`
> **Última verificación**: 2026-08-06
> **Criterio**: "disponibilizada" = deployada en producción, accesible por DNS y operativa (no basta el código versionado).

## Resumen

Tres herramientas están implementadas (o planificadas) en el repo pero **no operan en producción**:

| # | Herramienta | Código | Specs SDD | En producción | Bloqueante principal |
|---|-------------|--------|-----------|---------------|----------------------|
| 1 | **GLPI** (ITSM) | ✅ `itsm/` | ✅ 4 specs | ✅ CT 212 + DNS + portal | Verificación LDAP/backup |
| 2 | **NetBox** (CMDB) | ❌ `cmdb/` vacío | ✅ SDD completo | ❌ | Implementar el stack desde cero |
| 3 | **Ansible** | ❌ — | ❌ | ❌ | SDD: definir alcance y arquitectura |

## Estado verificado por herramienta

### 1. GLPI — Gestor ITSM

- **Código**: `itsm/` (docker-compose glpi+mariadb+nginx, `scripts/install-glpi.sh`, backup/restore, webhooks Redmine/GitLab, LDAP FreeIPA, `docs/post-deploy-config.md`).
- **SDD**: specs `itsm-core`, `itsm-ldap-auth`, `itsm-backup`, `itsm-integrations`; change `openspec/changes/itsm/` con 18 tareas en 6 fases completadas.
- **Producción**: ✅ CT 212 (Rocky, 2c/4G/20G, IP fija `192.168.1.47`) con stack `itsm/` desplegado en `/opt/glpi` (imagen oficial `glpi/glpi:10.0`, contenedores `glpi-mariadb`/`glpi-app`/`glpi-nginx` healthy). `glpi.gidas.local` resuelve a `192.168.1.47` (record static en MikroTik) y el proxy del portal (`/proxy/glpi/`) responde 200.
- **Para disponibilizar** (1-4 completados, 5 en curso — config post-deploy aplicada 2026-08-06):
  1. ✅ Crear CT 212 en pve-desa04 (Rocky Linux, IP fija en la LAN).
  2. ✅ Deploy del stack `itsm/` (docker compose + scripts) en `/opt/glpi`.
  3. ✅ DNS: record static en MikroTik `glpi.gidas.local → 192.168.1.47`; `/etc/hosts` del CT 208 corregido (apuntaba a `.45`).
  4. ✅ Alta en el portal (`config.yaml` de `portal-gidas/` ya tenía GLPI con `proxy: true`; grupos G-Direccion/G-Coordinadores).
  5. 🔲 Verificación LDAP FreeIPA + cron interno + backup.
- **Config post-deploy aplicada (2026-08-06)**: crons CT 212 (cron.php cada 5 min + backup dom 03:00), `zstd` instalado, `backup.sh` probado (SUCCESS), `00-env.sh` carga credenciales reales del `.env`, comandos corregidos a GLPI 10 (`config:set`, `ldap:synchronize_users`). Detalle en `docs/itsm/avance.md`.

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

- **Código**: ❌ No existe (`ansible/` vacío).
- **SDD**: 🔍 Exploration creada — `openspec/changes/ansible/exploration.md` (2026-08-06). Ansible core 2.16.16 ya instalado en el host de trabajo (sin ansible-lint/molecule).
- **Producción**: ❌.
- **Enfoque recomendado** (progresivo por fases, no rompe el patrón Bash probado):
  1. **F1 Config base** (no-destructivo): sync `/etc/hosts` (arregla drift real del CT 208), health checks HTTP de los 7 stacks, verificación de paquetes/utilidades, sync de crontabs.
  2. **F2 Deploy reproducible**: playbook de deploy de UN stack greenfield — NetBox como piloto natural (`cmdb/` vacío, SDD listo).
  3. **F3 Provisioning Proxmox** (API pve) + evaluar MikroTik v6 (limitado) y Windows (fuera de alcance inicial).
- **Decisiones clave**: mantener SOPS+age (NO ansible-vault, formato distinto); no migrar los 7 stacks existentes de una (riesgo de regresión); F1 usa módulos Ansible (lineinfile/cron/uri/package), no `shell:`.
- **Riesgos**: MikroTik v6 no soporta bien los módulos modernos (target v7); Windows usa OpenSSH cmd.exe sin WinRM; sin CI/CD (playbooks manuales como los scripts actuales).
- **Para continuar**: proposal (`sdd-propose`) tras confirmar: (1) control node `.107` vs CT dedicado, (2) NetBox como piloto F2, (3) excluir MikroTik/Windows del alcance inicial, (4) hosts sync + crontabs como entregables mínimos F1.

## Decisiones pendientes (para el equipo)

- [x] ¿GLPI en CT propio (212) o en VM? — resuelto: CT 212, patrón del repo.
- [ ] ¿NetBox en CT o VM? — necesita más recursos que GLPI (PostgreSQL+Redis).
- [ ] ¿Alcance inicial de Ansible: deploy de stacks existentes, config drift, o ambos? — exploration propone **progresivo**: F1 config drift → F2 deploy de NetBox (piloto) → F3 provisioning. Confirmar en proposal.
- [ ] ¿Alta de las 3 en el portal unificado (config.yaml) apenas estén disponibles?

## Siguientes pasos propuestos

1. **GLPI**: ✅ deploy CT 212 + stack `itsm/` + DNS + portal → verificación end-to-end OK. Pendiente: LDAP FreeIPA + cron + backup (fase 5 de verificación).
2. **NetBox**: implementar stack según SDD (es el que más trabajo de código requiere).
3. **Ansible**: exploration SDD en `openspec/changes/ansible/` (arrancar sin código).
