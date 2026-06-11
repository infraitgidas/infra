# Proposal: Gestor de Proyecto Open Source — Redmine

## Intent

Redmine como gestor de proyectos open source. Reemplaza seguimiento ad-hoc con issues, roadmaps y docs. Mismo patrón que `sg-monitoring`: Docker Compose en VM Rocky Linux 10 sobre `pve-desa`.

## Scope

### In Scope
- Stack: `redmine:6.1` + `postgres:16` + `nginx:latest`
- VM dedicada (~ID 206) en `pve-desa` — 2 vCPU, 4 GB RAM, 20 GB disco, Rocky Linux 10
- SSL con nginx reverse proxy (puerto 443, red interna)
- Scripts de deploy en `redmine/` (00-env.sh + pasos numerados)
- Auth local (LDAP postergado)
- Pipeline de backup de PostgreSQL (pg_dump diario)
- Secrets via `.env` (gitignored)

### Out of Scope
- Migración de datos externos (Trello, Jira, etc.)
- Integración LDAP (depende de Directory Server, futuro roadmap)
- Plugins de Redmine (evaluación post-deploy)
- CI/CD o integración con Git

## Capabilities

### New Capabilities
- `infra/redmine`: Despliegue y operación del stack Redmine — Docker Compose, configuración, SSL, backups programados

### Modified Capabilities
None

## Approach

Docker Compose en VM Rocky Linux 10 sobre `pve-desa`, adaptado a QEMU:
1. `01-provision-vm.sh`: `qm create` con cloud-init, disco, red
2. `02-bootstrap-vm.sh`: SSH como `infra`, instalar Docker
3. `03-deploy-stack.sh`: scp docker-compose.yml, levantar stack
4. `04-configure-ssl.sh`: certs autofirmados, nginx, firewall
5. `05-backup.sh`: cron pg_dump + rsync a storage
- Secrets en `.env` (gitignored), scp al deploy
- VM user: `infra` / password: `hlsv.2025`

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `redmine/` | New | Scripts de deploy y config del stack |
| `openspec/specs/infra/redmine/spec.md` | New | Especificación del servicio Redmine |
| `pve-desa` (VM ~206) | New | VM dedicada con Docker Compose |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| VM ID conflict | Low | `qm list` para verificar IDs |
| Puerto 443 en uso | Low | Verificar disponibilidad en VLAN |
| Data loss | Low | Backup diario desde día 1 |
| Docker en Rocky Linux 10 | Low | Repos oficiales Docker CE |

## Rollback Plan

- `docker compose down` + `qm stop <ID> && qm destroy <ID>`
- git revert en scripts modificados
- Backup corre antes de cambios destructivos

## Dependencies

- `pve-desa` con recursos disponibles (vCPU, RAM, disco)
- Internet desde la VM para pull de imágenes Docker
- Imagen Rocky Linux 10 disponible en storage Proxmox
- DNS interno opcional (IP directa funciona)

## Success Criteria

- [ ] Redmine accesible vía HTTPS desde la red interna
- [ ] Login con auth local funcionando (admin por defecto reconfigurado)
- [ ] PostgreSQL backup corre diariamente sin errores
- [ ] Scripts de deploy reproducibles desde cero en una VM limpia
