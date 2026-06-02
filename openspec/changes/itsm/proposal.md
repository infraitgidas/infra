# Proposal: Gestor ITSM

## Intent

Eliminar la gestión ad-hoc de incidentes, cambios y problemas. Implementar GLPI como ITSM unificado con CMDB integrada, autenticación LDAP contra FreeIPA, e integración API con Redmine y GitLab.

## Scope

### In Scope
- GLPI + MariaDB vía Docker Compose en LXC Proxmox (2 vCPU / 4 GB RAM / 20 GB SSD)
- Autenticación LDAP desde FreeIPA (sync programada de usuarios/grupos)
- Estructura `itsm/` con compose, configs, scripts de backup/restore
- Backup automatizado (dump SQL semanal + volúmenes Docker)
- Integración REST API con Redmine y GitLab (webhooks + polling)
- Inventario inicial de activos (servidores, LXCs, servicios)

### Out of Scope
- CMDB NetBox (feature separada — se documenta boundary con GLPI)
- Plugin development custom de GLPI
- Migración de datos históricos (planillas, correos)
- Automatización ITIL compleja (aprobaciones multi-nivel)

## Capabilities

> Contrato proposal→specs. No existen specs ITSM previas en `openspec/specs/`.

### New Capabilities
- `itsm-core`: Procesos ITIL — incidentes, cambios, problemas, SLA, base de conocimiento
- `itsm-ldap-auth`: Autenticación y sincronización de usuarios/grupos desde FreeIPA
- `itsm-integrations`: Integraciones REST API con Redmine y GitLab
- `itsm-backup`: Backup/restore automatizado del sistema GLPI

### Modified Capabilities
None — no hay specs previas que modificar.

## Approach

GLPI en Docker Compose oficial con MariaDB 10.11, nginx como proxy reverso, autenticación LDAP contra FreeIPA. Scripts Shell para backup, restore, y sincronización. Integraciones vía cron (polling API) y webhooks salientes de GLPI.

**CMDB overlap**: GLPI gestiona activos IT internos (servidores, LXCs, servicios). NetBox (futuro) será source of truth de infraestructura DC. Se evita duplicación activa documentando qué vive en cada sistema y usando naming convention consistente.

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `itsm/` | New | Docker Compose, configs GLPI, scripts backup/restore |
| `itsm/scripts/` | New | sync-ldap.sh, webhook-redmine.sh, webhook-gitlab.sh |
| `directoryServer/freeipa/` | Modified | Cuenta de servicio LDAP para GLPI |
| `proxmox/` | Modified | LXC provisionado para GLPI |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| CMDB duplicada con NetBox | Medium | Documentar boundary: GLPI = activos IT, NetBox = infra DC |
| FreeIPA schema LDAP particular | Medium | Probar sincronización en staging antes de producción |
| GLPI Docker image no oficial | Low | Usar imágenes oficiales GLPI Team, fijar versión 10.x |
| Recursos insuficientes en Proxmox | Low | Verificar 4 GB RAM libres antes de provisionar |

## Rollback Plan

```bash
docker compose -f itsm/docker-compose.yml down -v
rm -rf itsm/
# Revertir cambios en FreeIPA (eliminar cuenta de servicio LDAP)
```

## Dependencies

- LXC en Proxmox con 2 vCPU / 4 GB RAM / 20 GB SSD
- FreeIPA operativo con cuenta de servicio para lectura LDAP
- DNS (registro A para glpi.gidas.local)
- GLPI 10.x image (docker.io/glpi/glpi:10)
- MariaDB 10.11 (docker.io/mariadb:10.11)

## Success Criteria

- [ ] GLPI accesible vía HTTPS, login con credenciales LDAP de FreeIPA
- [ ] Ticket de incidente creado → asignado → resuelto end-to-end
- [ ] Backup automatizado funcional (dump SQL + volúmenes) con restore probado
- [ ] Webhook desde GLPI a Redmine al crear un cambio
- [ ] Webhook desde GLPI a GitLab al resolver un incidente
- [ ] Inventario mínimo de activos cargado (>5 servidores/LXCs)
