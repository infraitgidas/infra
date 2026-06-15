# Proposal: SSO + Portal de Acceso Unificado GIDAS

## Intent

Proveer un punto único de acceso (portal) con autenticación centralizada vía AD para todos los miembros de GIDAS, desde internet y LAN, permitiendo SSO entre herramientas actuales y futuras.

## Scope

### In Scope
- Desplegar Authentik como Identity Provider (Docker Compose, VM en pve-desa04)
- Conectar Authentik al AD GDC01.local (LDAP bind)
- Dashboard "My Applications" con cards para cada herramienta
- SSO OIDC para GitLab y Grafana
- SSO OIDC para Redmine (plugin openid_connect)
- Autenticación LDAP para Proxmox VE (vía PAM)
- Portal publicado internamente en `portal.gidas.local`
- Acceso remoto vía Twingate (ya disponible, no requiere exposición pública)
- Agregar link de acceso en Drupal gidas.frlp.utn.edu.ar apuntando a la URL pública de Twingate
- DNS interno portal.gidas.local en MikroTik

### Out of Scope
- Migrar usuarios Drupal a AD (UTN controla el site)
- SSO para herramientas sin soporte OIDC/SAML (se deja para fase 2)
- MFA/TOTP (se agrega en fase 2)
- Reemplazar Drupal como sitio institucional

## Capabilities

### New Capabilities
- `sso/authentik`: Despliegue y configuración de Authentik IdP con AD
- `sso/gitlab`: Integración OIDC de GitLab con Authentik
- `sso/grafana`: Integración OAuth de Grafana con Authentik
- `sso/redmine`: Integración OIDC de Redmine con Authentik
- `sso/proxmox`: Autenticación LDAP de Proxmox contra AD
- `networking/public-access`: Exposición del portal vía Twingate para acceso remoto

### Modified Capabilities
- `vcs/gitlab`: Nueva configuración OIDC (no reemplaza LDAP existente)
- `infra/redmine`: Nueva configuración OIDC

## Approach

1. Provisionar VM liviana (1vCPU, 1.5GB, 10GB) en pve-desa04 con Docker
2. Desplegar Authentik stack (server + worker + postgres + redis)
3. Configurar LDAP bind contra AD GDC01.local
4. Crear Applications en Authentik: GitLab, Grafana, Redmine
5. Configurar OIDC/OAuth en cada herramienta
6. Configurar Proxmox para auth LDAP contra AD
7. Exponer portal vía Twingate para acceso remoto
8. Agregar link en Drupal apuntando a la URL de Twingate del portal

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `portal/` | New | Stack Authentik (Docker Compose + config) |
| `portal/docs/` | New | Documentación de deploy, SSO, mantenimiento |
| `openspec/specs/sso/authentik/` | New | Spec del IdP |
| `openspec/specs/sso/gitlab/` | New | Spec integración OIDC GitLab |
| `openspec/specs/sso/grafana/` | New | Spec integración OAuth Grafana |
| `openspec/specs/sso/redmine/` | New | Spec integración OIDC Redmine |
| `openspec/specs/sso/proxmox/` | New | Spec auth LDAP Proxmox |
| `openspec/specs/networking/public-access/` | New | Spec exposición pública |
| `openspec/specs/vcs/gitlab/spec.md` | Modified | Agregar config OIDC |
| `openspec/specs/infra/redmine/spec.md` | Modified | Agregar config OIDC |
| Drupal (externo) | Modified | Agregar link al portal |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Redmine plugin OIDC incompatible | Media | Probar en staging, alternativa proxy auth |
| Proxmox no soporta SSO real | Alta | LDAP bind direct (sin SSO, misma credencial) |
| Drupal no puede agregar link externo | Baja | Siempre se puede, es contenido web |

## Rollback Plan

- Deshabilitar OIDC en cada herramienta → vuelve a login directo
- Detener Authentik → portal offline pero herramientas siguen funcionando
- Eliminar VM de Authentik → sin pérdida de datos de herramientas

## Dependencies

- Docker + Docker Compose en VM Rocky Linux 10
- Twingate ya configurado para acceso remoto
- DNS interno portal.gidas.local en MikroTik

## Success Criteria

- [ ] Usuario AD puede loguearse en Authentik y ver dashboard con cards
- [ ] Usuario clickea card de GitLab → ingresa sin otro login (SSO)
- [ ] Usuario clickea card de Grafana → ingresa sin otro login (SSO)
- [ ] Usuario clickea card de Redmine → ingresa sin otro login (SSO)
- [ ] Usuario accede desde internet (no solo LAN)
- [ ] Drupal tiene link visible al portal
