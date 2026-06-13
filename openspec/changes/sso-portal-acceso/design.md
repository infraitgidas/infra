# Design: SSO + Portal de Acceso Unificado GIDAS

## Technical Approach

Desplegar Authentik (Docker Compose) como Identity Provider centralizado, conectado al AD GDC01.local. Cada herramienta se configura como OIDC/OAuth client. El portal se accede desde LAN por DNS interno y desde internet por Twingate. No se exponen puertos a internet.

## Architecture

```
                    ┌─────────────────────────────────┐
                    │     Authentik (Docker Compose)   │
                    │  portal.gidas.local:443          │
                    │         │                        │
                    │    ┌────┴────┐                   │
                    │    │  LDAP   │ ◄── AD GDC01       │
                    │    └─────────┘                   │
                    │         │                        │
                    │  ┌──────┴──────┐                │
                    │  │  OIDC/OAuth │                │
                    │  │  Providers  │                │
                    │  └──┬──┬──┬───┘                │
                    └─────┼──┼──┼────────────────────┘
                          │  │  │
              ┌───────────┘  │  └──────────┐
              ▼               ▼             ▼
        ┌──────────┐  ┌──────────┐  ┌──────────┐
        │  GitLab  │  │  Grafana │  │  Redmine │
        │ (OIDC)   │  │ (OAuth)  │  │ (OIDC)   │
        └──────────┘  └──────────┘  └──────────┘

LAN:  portal.gidas.local → nginx → Authentik → SSO
WAN:  Twingate → portal.gidas.local → Authentik → SSO
```

## Architecture Decisions

| Decisión | Opción | Alternativa | Rationale |
|----------|--------|-------------|-----------|
| IdP | Authentik | Keycloak | Dashboard nativo con cards, menor consumo de recursos, outposts legacy |
| Exposición | Twingate | Cloudflare/DNAT | Ya está en uso, sin exponer puertos, zero trust |
| Dominio | portal.gidas.local | Sin DNS | Resolución LAN con MikroTik, WAN vía Twingate |
| GitLab SSO | OIDC | SAML | OIDC es más simple, GitLab lo soporta nativamente |
| Redmine SSO | Plugin OIDC | Proxy auth | Plugin openid_connect existe, requiere probar compatibilidad |
| Proxmox | LDAP realm | SSO vía OIDC | Proxmox no soporta OIDC/OAuth, LDAP es la opción directa |

## Data Flow

### Flujo de login + SSO

```
1. Usuario → portal.gidas.local → Authentik login page
2. Authentik valida credenciales contra AD (LDAP bind)
3. Authentik crea sesión, redirige al dashboard "My Applications"
4. Usuario clickea card de GitLab
5. Authentik redirige a GitLab con código OIDC
6. GitLab canjea código por token con Authentik
7. GitLab crea sesión local → usuario autenticado en GitLab
8. (Repetir pasos 4-7 para Grafana, Redmine, etc.)
```

## File Changes

| File | Action | Description |
|------|--------|-------------|
| `portal/docker-compose.yml` | Create | Stack Authentik + PostgreSQL + Redis |
| `portal/.env` | Create | Variables de entorno (secrets en SOPS) |
| `portal/nginx/authentik.conf` | Create | Reverse proxy con HTTPS |
| `portal/docs/deploy.md` | Create | Procedimiento de deploy |
| `portal/docs/sso-gitlab.md` | Create | Configuración OIDC GitLab |
| `portal/docs/sso-grafana.md` | Create | Configuración OAuth Grafana |
| `portal/docs/sso-redmine.md` | Create | Configuración OIDC Redmine |
| `portal/docs/sso-proxmox.md` | Create | Configuración LDAP Proxmox |
| `portal/backup/` | Create | Scripts de backup de Authentik |
| `openspec/specs/sso/authentik/spec.md` | Create | Spec del IdP |
| `openspec/specs/sso/gitlab/spec.md` | Create | Spec SSO GitLab |
| `openspec/specs/sso/grafana/spec.md` | Create | Spec SSO Grafana |
| `openspec/specs/sso/redmine/spec.md` | Create | Spec SSO Redmine |
| `openspec/specs/sso/proxmox/spec.md` | Create | Spec SSO Proxmox |

## Provisioning

Nueva VM en pve-desa04:

| Recurso | Valor |
|---------|-------|
| VM ID | A definir (siguiente disponible) |
| SO | Rocky Linux 10 |
| vCPU | 1 |
| RAM | 1.5 GB |
| Disco | 10 GB |
| IP | 192.168.1.x (siguiente disponible) |
| DNS | portal.gidas.local |
| Stack | Docker Compose (Authentik + Postgres + Redis + nginx) |

## Testing Strategy

| Layer | What | How |
|-------|------|-----|
| Stack | Contenedores funcionando | `docker compose ps` todos up |
| SSO | Login OIDC GitLab | Login en Authentik → card GitLab → ingresa sin otro login |
| SSO | Login OAuth Grafana | Login en Authentik → card Grafana → ingresa sin otro login |
| SSO | Login OIDC Redmine | Login en Authentik → card Redmine → ingresa sin otro login |
| Auth | LDAP Proxmox | Login en Proxmox con realm AD |
| WAN | Acceso remoto | Login vía Twingate desde afuera del laboratorio |

## Rollout

1. Provisionar VM e instalar Docker
2. Desplegar Authentik y verificar login con akadmin
3. Conectar LDAP al AD y verificar sincronización
4. Configurar aplicaciones en Authentik (GitLab, Grafana, Redmine)
5. Configurar OIDC/OAuth en cada herramienta
6. Probar SSO completo
7. Configurar DNS interno
8. Agregar link en Drupal

## Open Questions

- [ ] Plugin openid_connect para Redmine 6.x compatible?
- [ ] IP disponible para la VM de Authentik?
