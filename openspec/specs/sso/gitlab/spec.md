# SSO / GitLab OIDC Integration Specification

## Purpose

Integración OIDC de GitLab con Authentik como IdP: permitir a usuarios autenticados en Authentik acceder a GitLab sin otro login (SSO).

## Requirements

### Requirement: OIDC Provider en Authentik

Authentik DEBE configurarse como proveedor OIDC para GitLab, emitiendo tokens de autenticación.

#### Scenario: Provider configurado

- GIVEN Authentik funcionando con LDAP conectado
- WHEN se crea un OIDC Provider apuntando a GitLab
- THEN Authentik DEBE generar Client ID y Client Secret
- AND DEBE configurarse la redirect URI de GitLab

### Requirement: OIDC Client en GitLab

GitLab DEBE configurarse como cliente OIDC de Authentik en `/etc/gitlab/gitlab.rb`.

#### Scenario: SSO login exitoso

- GIVEN Authentik como OIDC provider y GitLab como cliente configurado
- WHEN un usuario autenticado en Authentik clickea la card de GitLab
- THEN GitLab DEBE redirigir a Authentik para verificar la sesión
- AND el usuario DEBE ingresar a GitLab sin credenciales adicionales

#### Scenario: Auto-creación de usuario

- GIVEN un usuario AD sin cuenta previa en GitLab
- WHEN ingresa vía SSO por primera vez
- THEN GitLab DEBE crear el usuario automáticamente con datos de Authentik
- AND DEBE asignarlo al grupo GitLab correspondiente según su grupo AD

### Requirement: Coexistencia con LDAP

La autenticación OIDC DEBE coexistir con la autenticación LDAP existente en GitLab.

#### Scenario: Ambos métodos activos

- GIVEN GitLab con LDAP y OIDC configurados
- WHEN un usuario existente ingresa por cualquiera de los dos métodos
- THEN DEBE identificarse como el mismo usuario en GitLab
