# Proposal: Automatización de Infraestructura — Ansible

## Intent

Automatizar la gestión de infraestructura del Grupo Gidas de forma idempotente y declarativa, sin romper el patrón actual (scripts Bash por fase, decisión documentada en gitlab design). La exploración recomienda un enfoque **progresivo por fases**: primero config drift no-destructivo (arregla drift real conocido), luego deploy reproducible de un stack greenfield (NetBox como piloto), dejando provisioning Proxmox para una fase posterior.

## Scope

### In Scope
- **F1 — Control node + Config base**: inventario YAML por grupos, `ansible.cfg`, integración SOPS (consumir `secrets/*.yaml` existente, NO ansible-vault). Playbooks no-destructivos: sync `/etc/hosts` (arregla drift CT 208), sync de crontabs, verificación de paquetes/utilidades, health checks HTTP de los 7 stacks.
- **F2 — Deploy reproducible**: playbook de deploy completo de **NetBox** (greenfield, `cmdb/` vacío, SDD listo) — patrón reutilizable para futuros stacks.
- Documentación en `ansible/README.md` + runbook de ejecución.

### Out of Scope
- Migración de los 7 stacks existentes a playbooks (riesgo de regresión sin valor inmediato — scripts Bash siguen siendo el patrón de deploy de stacks ya operativos).
- F3 provisioning Proxmox vía API (futuro, tras validar F1/F2).
- MikroTik (RouterOS v6 — soporte Ansible pobre, seguir con SSH directo).
- Windows/AD (sin WinRM; `identity-dashboard` ya cubre gestión de usuarios).

## Capabilities

> Investigación de `openspec/specs/` completada. No existe dominio de automatización; ningún spec existente (proxmox, networking, infra) cambia a nivel de requisitos — los playbooks son tooling, no comportamiento de los servicios especificados.

### New Capabilities
- `ansible/control-node`: Setup del control node, inventario por grupos y ansible.cfg
- `ansible/config-base`: Playbooks de config drift no-destructivos (hosts, crontabs, paquetes, health checks)
- `ansible/deploy-stack`: Playbook reproducible de deploy de stack Docker Compose (piloto NetBox)

### Modified Capabilities
None — dominio nuevo.

## Approach

```
[Host trabajo .107]  ←── Ansible core 2.16.16 (control node, ya instalado)
      │  SSH (key ed25519 existente) + SOPS (age) para secrets
      ▼
┌─────────────────────────┬─────────────────────────────┐
│ F1: pve-desa01-04,      │ F2: CT/VM NetBox (nuevo)    │
│ pve-ad, CTs 205/208/    │ deploy reproducible del     │
│ 210/212 (+ hosts Linux) │ stack cmdb (PostgreSQL +    │
│  - /etc/hosts (backup)  │ Redis + NetBox)             │
│  - crontabs             │                             │
│  - packages             │                             │
│  - health checks HTTP   │                             │
└─────────────────────────┴─────────────────────────────┘
```

F1 usa módulos Ansible (`lineinfile`, `cron`, `package`, `uri`), NO `shell:` — idempotencia real. F2 sigue el stack ya diseñado en `openspec/changes/cmdb/design.md`.

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `ansible/` | New | Inventario (`inventory/`), playbooks (`playbooks/`), `ansible.cfg`, `README.md` |
| `ansible/secrets/` | New | Lectura de `secrets/*.yaml` (SOPS) — no se duplican secretos |
| CTs + nodos PVE (LAN) | Modified | `/etc/hosts` y crontabs gestionados por playbook (con backup `.bak`) |
| `openspec/specs/ansible/` | New | Nuevo dominio de specs |
| `openspec/changes/ansible/` | New | Artefactos SDD (proposal, design, tasks, specs) |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Playbook rompe `/etc/hosts` de CTs | Low | `backup: yes` en `lineinfile` + `--check` antes de aplicar + playbook de health checks posterior |
| Secretos: ansible-vault vs SOPS | Medium | Consumir SOPS existente; `ansible.cfg` NO define vault; documentar en README |
| Crontabs sobreescritos | Low | Módulo `cron` (idempotente) + `--check`; crontabs actuales documentados antes de migrar |
| F2 NetBox en CT sin recursos | Medium | Requisito SDD cmdb: 2 GB RAM / 2 vCPU — verificar CT antes de deploy |
| Sin CI/CD — playbooks manuales | Low | Runbook en `ansible/README.md` (patrón de los runbooks existentes) |

## Rollback Plan

- **F1**: cada playbook corre con `--check` primero. `/etc/hosts` con `backup: yes` → revertir restaurando `.bak`. Crontabs: se documentan los existentes ANTES del primer run; revertir con el módulo `cron` o el dump documentado. Health checks y packages: no-destructivos por diseño.
- **F2**: stack greenfield en CT nuevo — rollback = `docker compose down` + borrar volúmenes. No toca servicios existentes.
- **Control node**: nada se instala en hosts remotos más allá de paquetes declarados; el node `.107` ya tiene Ansible.

## Dependencies

- Ansible core 2.16.16 (instalado en `.107`) + `ansible-lint` (instalar para validar playbooks).
- SSH key ed25519 existente (ya usada por los scripts actuales).
- SOPS + age (setup existente) para leer `secrets/*.yaml`.
- F2: CT/VM con 2 GB RAM / 2 vCPU y Docker Compose (requisito del SDD cmdb).

## Success Criteria

- [ ] `ansible-playbook -i inventory/ playbooks/check.yml --check` pasa sin cambios en TODOS los hosts (idempotencia verificada)
- [ ] F1 aplicado: `/etc/hosts` del CT 208 sin drift (netbox no apunta a `.45`), crontabs documentados y consistentes, health checks de los 7 stacks = 200/OK
- [ ] `ansible-lint` sin errores en todos los playbooks
- [ ] F2: NetBox desplegado vía playbook único desde cero (idempotente — re-run no cambia nada)
- [ ] Runbook en `ansible/README.md` documenta ejecución, `--check`, y rollback
- [ ] Secretos: cero valores en texto plano en `ansible/` — todo vía SOPS
