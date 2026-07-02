# SSO / Redmine OIDC Integration Specification

## Purpose

Integración OIDC de Redmine con Authentik como IdP: SSO para gestión de proyectos.

## Requirements

### Requirement: Plugin openid_connect

Redmine DEBE instalar y configurar el plugin `openid_connect` para soportar autenticación OIDC.

#### Scenario: Plugin instalado

- GIVEN Redmine funcionando con autenticación LDAP
- WHEN se instala el plugin openid_connect
- THEN el plugin DEBE estar visible en el panel de administración de Redmine
- AND DEBE aceptar configuración de OIDC provider

### Requirement: OIDC Provider en Authentik

Authentik DEBE configurarse como proveedor OIDC para Redmine.

#### Scenario: SSO login exitoso

- GIVEN Redmine con OIDC configurado contra Authentik
- WHEN el usuario autenticado en Authentik clickea la card de Redmine
- THEN Redmine DEBE aceptar el token de Authentik
- AND el usuario DEBE acceder a sus proyectos sin otro login

#### Scenario: Coexistencia con LDAP

- GIVEN Redmine con LDAP y OIDC configurados
- WHEN un usuario ingresa por cualquiera de los dos métodos
- THEN DEBE identificarse como el mismo usuario en Redmine
