# Proposal: Portal de Acceso Custom (FastAPI + LDAP)

## Intent

Reemplazar Authentik (IdP) y Homer (dashboard estático) por un portal web liviano hecho a medida que permita login contra AD GDC01 y filtre herramientas según el grupo AD del usuario. Authentik resultó complejo de integrar (OIDC/SAML sobrecargado para 17 usuarios) y Homer no tiene autenticación ni RBAC.

## Scope

### In Scope
- App Python FastAPI con login LDAP contra AD GDC01
- Dashboard con cards filtradas por grupos AD del usuario
- Config YAML para herramientas y mapeo grupos → herramientas
- Sesiones JWT stateless (sin DB)
- Deploy en CT 208 (portal, Rocky 9) vía Docker o systemd

### Out of Scope
- SSO entre herramientas (cada tool autentica AD directo, como ya funciona)
- Base de datos (toda la config está en YAML)
- Gestión de usuarios (se crean en AD, el portal solo lee)
- Permisos dentro de las herramientas (se gestionan en cada tool)

## Capabilities

### New Capabilities
- `portal/acceso`: Portal de acceso con login AD y dashboard filtrado por grupos

## Approach

App Python/FastAPI con Jinja2 (SSR), ldap3 para auth AD, JWT para sesiones. Config YAML versionable. Sin dependencias externas (ni DB, ni Redis, ni IdP). Deploy en CT 208.

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `portal-gidas/` | New | App completa del portal |
| `docs/portal-acceso/` | Modified | Nuevos documentos de diseño |
| CT 208 | Modified | Reemplaza Homer por portal custom |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| AD inaccesible | Low | Error handling graceful, login con mensaje claro |
| JWT secret expuesto | Low | Generado en deploy, configurable via env var |

## Rollback

1. Reemplazar app por Homer: restaurar nginx, copiar Homer de vuelta
2. Revertir config de nginx

## Success Criteria

- [ ] Login AD funciona con usuarios reales (infrait, etc.)
- [ ] Dashboard muestra solo tools segun grupos AD
- [ ] Sin sesion activa redirige a login
- [ ] Nueva tool se agrega editando solo config.yaml
