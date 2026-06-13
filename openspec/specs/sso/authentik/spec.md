# SSO / Authentik Identity Provider Specification

## Purpose

Authentik como Identity Provider (IdP) centralizado para el grupo GIDAS: autenticación contra AD GDC01.local, dashboard de aplicaciones con cards, y SSO vía OIDC/OAuth para herramientas del ecosistema.

## Requirements

### Requirement: Despliegue

Authentik DEBE desplegarse en Docker Compose en una VM del cluster Proxmox, con PostgreSQL y Redis como dependencias.

#### Scenario: Stack funcionando

- GIVEN una VM con Docker Compose y los puertos 443 y 9000 expuestos
- WHEN se ejecuta `docker compose up -d`
- THEN la Web UI DEBE responder en https://portal.gidas.local
- AND el panel admin DEBE ser accesible en /if/admin/

#### Scenario: Persistencia

- GIVEN el stack de Authentik funcionando
- WHEN se reinicia el contenedor
- THEN las configuraciones de aplicaciones y usuarios DEBEN persistir

### Requirement: Integración LDAP con AD

Authentik DEBE conectarse al Active Directory GDC01.local vía LDAP como fuente de identidad primaria.

#### Scenario: Conexión exitosa

- GIVEN AD GDC01.local accesible desde la VM
- WHEN se configura el LDAP Source en Authentik con bind DN `infrait`
- THEN Authentik DEBE sincronizar usuarios y grupos desde AD
- AND los usuarios AD DEBEN poder loguearse en Authentik

#### Scenario: Login con AD

- GIVEN un usuario existente en AD (ej: errodriguez)
- WHEN ingresa su contraseña de AD en el login de Authentik
- THEN Authentik DEBE autenticarlo y redirigirlo al dashboard

### Requirement: Dashboard de Aplicaciones

Authentik DEBE mostrar un dashboard "My Applications" con cards para cada herramienta configurada.

#### Scenario: Dashboard con herramientas

- GIVEN un usuario autenticado en Authentik
- WHEN accede al dashboard post-login
- THEN DEBE ver cards con íconos y nombres de: GitLab, Redmine, Grafana
- AND las cards DEBEN estar visibles según los grupos del usuario en AD

### Requirement: Administración

Authentik DEBE tener un panel admin accesible para gestionar aplicaciones, fuentes y usuarios.

#### Scenario: Acceso admin

- GIVEN el usuario administrador de Authentik (akadmin)
- WHEN accede a /if/admin/
- THEN DEBE poder crear/modificar aplicaciones, proveedores y fuentes LDAP
