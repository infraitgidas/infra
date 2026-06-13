# SSO / Proxmox LDAP Authentication Specification

## Purpose

Autenticación LDAP de Proxmox VE contra AD GDC01.local: permitir a usuarios del grupo GIDAS acceder al panel web de Proxmox con sus credenciales de AD.

## Requirements

### Requirement: LDAP Realm en Proxmox

Proxmox DEBE configurar un dominio de autenticación LDAP contra AD GDC01.local.

#### Scenario: Realm configurado

- GIVEN un nodo Proxmox con acceso al AD
- WHEN se configura un LDAP realm en Proxmox con bind DN `infrait`
- THEN Proxmox DEBA autenticar usuarios contra AD
- AND el realm DEBE aparecer en el selector de login de Proxmox

#### Scenario: Login exitoso

- GIVEN un usuario con cuenta en AD
- WHEN selecciona el realm AD e ingresa su contraseña
- THEN Proxmox DEBE autenticarlo y mostrar el panel principal

### Requirement: Mapeo de grupos

Proxmox DEBE mapear grupos AD a roles de Proxmox (Administration, PVEAdmin, etc.).

#### Scenario: Admin por grupo AD

- GIVEN un usuario del grupo G-Direccion en AD
- WHEN se autentica vía LDAP en Proxmox
- THEN DEBE tener rol de Administrador en Proxmox

#### Scenario: Sin acceso

- GIVEN un usuario que NO pertenece a grupos mapeados
- WHEN intenta autenticarse en Proxmox
- THEN Proxmox DEBE rechazar el acceso
