# Proposal: Gestor de Proyecto Open Source — Redmine

## Intent

Implementar Redmine como gestor de proyectos open source. Reemplaza el seguimiento ad-hoc con issues, roadmaps y documentación. Sigue el patrón existente de `sg-monitoring`: Docker Compose en LXC en `pve-ad`.

## Scope

### In Scope
- Stack Docker Compose: `redmine:6.1` + `postgres:16` + `nginx:1.29`
- CT dedicado (~ID 206) en `pve-ad` — 2 vCPU, 4 GB RAM, 20 GB disco
- SSL con nginx reverse proxy (puerto 443, red interna 192.168.1.0/24)
- Scripts de deploy en `redmine/` (00-env.sh + pasos numerados)
- Auth local (LDAP postergado)
- Pipeline de backup de PostgreSQL

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

Docker Compose en LXC en `pve-ad`, mismo patrón que `sg-monitoring`:
1. Crear CT con Ubuntu LTS vía API de Proxmox
2. Clonar estructura de scripts desde `scripts/` como plantilla
3. `00-env.sh`: variables de entorno (CT ID, IP, versiones, secrets)
4. `01-create-ct.sh`: crear y configurar CT
5. `02-deploy-stack.sh`: instalar Docker, deploy docker-compose.yml con redmine + postgres + nginx
6. `03-configure-ssl.sh`: certs SSL, nginx virtualhost, firewall
7. `04-backup.sh`: cron de dump PostgreSQL + rsync a storage interno

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `redmine/` | New | Scripts de deploy y config del stack |
| `openspec/specs/infra/redmine/spec.md` | New | Especificación del servicio Redmine |
| `pve-ad` (CT ~206) | New | Container dedicado con Docker Compose |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| CT ID conflict | Low | Usar `pvesh` para verificar IDs disponibles antes de crear |
| Puerto 443 en uso en la red | Low | Verificar disponibilidad en la VLAN de gestión |
| Data loss sin backups | Low | Backup diario de PostgreSQL desde el día 1 |

## Rollback Plan

- `docker compose down` + remove CT via Proxmox (`qm stop && qm destroy`)
- Restaurar cualquier cambio en scripts de otros stacks vía git revert
- Los datos se pierden si no hay backup previo — el backup script corre antes de cualquier cambio destructivo

## Dependencies

- `pve-ad` operativo con recursos disponibles (vCPU, RAM, disco)
- Acceso a Internet desde el CT para pulling de imágenes Docker
- DNS interno (opcional — puede usarse IP directa inicialmente)

## Success Criteria

- [ ] Redmine accesible vía HTTPS desde la red interna
- [ ] Login con auth local funcionando (admin por defecto reconfigurado)
- [ ] PostgreSQL backup corre diariamente sin errores
- [ ] Scripts de deploy reproducibles desde cero en un CT limpio
