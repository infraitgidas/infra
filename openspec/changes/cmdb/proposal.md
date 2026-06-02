# Proposal: Gestor CMDB — Configuration Management Database

## Intent

Centralizar el inventario de infraestructura del Grupo Gidas en una CMDB que modele servidores Proxmox, equipos Mikrotik, Directory Servers (AD/FreeIPA) y servicios (Redmine, GitLab, ITSM). Hoy no existe inventario — todo es conocimiento tribal. NetBox es la herramienta recomendada por la exploración.

## Scope

### In Scope
- Deploy de NetBox (Docker Compose) en VM dedicada — PostgreSQL + Redis + NetBox + Worker
- Modelado de CIs: Sites, Racks, Devices, Clusters, VirtualMachines, IPAM, VLANs, Services, Contacts
- Integración con Proxmox VE: descubrimiento automático de nodos, VMs, LXCs, interfaces, IPs, discos
- Scripts de descubrimiento para Mikrotik RouterOS (via API REST → NetBox API)
- Scripts de importación para Directory Servers (LDAP query → NetBox API)
- Registro manual inicial de servicios (Redmine, GitLab, ITSM) como CIs tipo Service
- Documentación de deploy, modelado y operación en `cmdb/docs/`
- Scripts de backup/restore de la base NetBox

### Out of Scope
- Integración ITSM (puente n8n/webhooks) — se hará cuando el feature #4 (ITSM) esté en marcha
- Descubrimiento automático de servicios (Redmine/GitLab) — registro manual inicial
- Migración desde otra CMDB (no hay nada que migrar)
- Helpdesk o ticketing (NetBox no tiene — es CMDB pura)

## Capabilities

> Investigación de `openspec/specs/` completada. El dominio CMDB es nuevo — no hay specs existentes que modificar.

### New Capabilities
- `cmdb/netbox-deploy`: Deploy y configuración de NetBox con Docker Compose
- `cmdb/proxmox-discovery`: Integración y sincronización con Proxmox VE
- `cmdb/mikrotik-discovery`: Scripts de descubrimiento para equipos Mikrotik RouterOS
- `cmdb/directory-sync`: Importación de Directory Servers (AD/FreeIPA)
- `cmdb/ci-modeling`: Modelado de CIs (Sites, Devices, Clusters, IPAM, VLANs, Services)
- `cmdb/maintenance`: Backup, restore y upgrades de NetBox

### Modified Capabilities
None — dominio nuevo, sin specs existentes que modificar.

## Approach

NetBox desplegado vía Docker Compose oficial en VM Proxmox (2 GB RAM, 2 vCPU, 10 GB disco). Stack: NetBox (Python/Django) + PostgreSQL 15 + Redis 7. El modelado sigue la jerarquía Sites → Racks → Devices → VirtualMachines → IPAM. La integración Proxmox usa la NetBox API oficial + scripting con `proxmoxer` para extraer datos del cluster. Mikrotik via API REST RouterOS. Directory Servers via LDAP queries. Todos los scripts de descubrimiento se almacenan en `cmdb/scripts/` y se ejecutan vía cron.

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `cmdb/` | New | Directorio raíz del feature: deploy, scripts, docs |
| `cmdb/deploy/` | New | Docker Compose + config de NetBox |
| `cmdb/scripts/` | New | Scripts de descubrimiento (Proxmox, Mikrotik, LDAP) |
| `cmdb/docs/` | New | Documentación de deploy y operación |
| `cmdb/backups/` | New | Scripts de backup/restore |
| `openspec/specs/cmdb/` | New | Nuevo dominio de specs para CMDB |
| Proxmox cluster | Read | Integración via API — solo lectura, sin cambios |
| Equipos Mikrotik | Read | Scripts via API REST — solo lectura |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Integración Proxmox usa NetBox Labs Cloud (enterprise) | Medium | Usar API community + `proxmoxer` como alternativa — scripting manual |
| Mikrotik sin integración oficial | Medium | Scripts custom via API REST de RouterOS + NetBox API |
| Over-engineering para infra chica | Low | NetBox corre en 2 GB RAM — costo aceptable. Alternativa: Snipe-IT si escala mal |
| Desactualización por falta de uso | Medium | Automatizar descubrimiento vía cron semanal + check en dashboard |
| Upgrade de NetBox rompe scripts | Low | Versionar scripts con NetBox API version, test en staging antes de prod |

## Rollback Plan

1. Detener containers: `docker compose -f cmdb/deploy/docker-compose.yml down`
2. Backup de PostgreSQL existe antes del deploy (`pg_dump`)
3. Para revertir completo: eliminar `cmdb/` directory y drops de schemas
4. Los scripts de descubrimiento son READ-ONLY — no afectan equipos reales

## Dependencies

- Docker + Docker Compose en VM objetivo (PostgreSQL 15 + Redis 7)
- VM Proxmox con 2 GB RAM, 2 vCPU, 10 GB disco disponible
- Acceso API a cluster Proxmox (token API con permisos de lectura)
- Acceso API a equipos Mikrotik (usuario con permisos de lectura RouterOS)
- Acceso LDAP a Directory Servers (consulta de solo lectura)
- Puertos abiertos: NetBox (8000/tcp), PostgreSQL (5432/tcp — interno Docker)

## Success Criteria

- [ ] NetBox deployado y accesible via web en `http://cmdb.gidas.local:8000`
- [ ] Proxmox cluster sincronizado: nodos como Devices, VMs/LXCs como VirtualMachines con IPs y discos
- [ ] Equipos Mikrotik registrados como Devices con interfaces, IPs y VLANs
- [ ] Directory Servers (AD/FreeIPA) registrados como Devices con rol y OS
- [ ] Servicios (Redmine, GitLab, ITSM) registrados como CIs tipo Service con relaciones
- [ ] Scripts de descubrimiento automatizados vía cron semanal
- [ ] Backup/restore probado: backup de PostgreSQL + restore exitoso
- [ ] Documentación de deploy y operación en `cmdb/docs/`
