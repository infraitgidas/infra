# Proposal: Gestor de Contraseñas Vaultwarden

## Intent

Proveer a los miembros de GIDAS un gestor de contraseñas centralizado, liviano y autogestionado, que permita almacenar, compartir y autocompletar credenciales de forma segura. Integrado con AD GDC01 y accesible desde el portal GIDAS.

## Scope

### In Scope
- Deploy de Vaultwarden 1.36.0 en CT dedicado con Docker
- Integración LDAP contra AD GDC01 (login con credenciales AD)
- Organización y colecciones para compartir credenciales por grupo
- HTTPS con self-signed certificate via nginx reverse proxy
- Card en el portal GIDAS para acceso directo

### Out of Scope
- Migración de contraseñas existentes (las crean los usuarios)
- SSO con otras herramientas (Vaultwarden usa su propio login AD)
- Backup automático (se documenta cómo hacerlo)

## Capabilities

### New Capabilities
- `vaultwarden/deploy`: Gestor de contraseñas Vaultwarden con LDAP

## Approach

Vaultwarden en Docker dentro de un CT Rocky Linux 9 dedicado (CT 209). LDAP contra AD GDC01 para autenticación. nginx como reverse proxy con SSL. Integración via card en portal GIDAS.

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `portal-gidas/config.yaml` | Modified | Agregar card para Vaultwarden |
| CT 209 (new) | New | CT dedicado para Vaultwarden |

## Rollback
1. Detener container Vaultwarden: `docker stop vaultwarden`
2. Remover CT 209: `pct stop 209 && pct destroy 209`
3. Remover card del portal

## Success Criteria
- [ ] Login AD funciona en Vaultwarden
- [ ] Usuario puede crear/almacenar/recuperar contraseñas
- [ ] Organización configurada con colecciones por grupo
- [ ] Card en portal redirige a Vaultwarden
