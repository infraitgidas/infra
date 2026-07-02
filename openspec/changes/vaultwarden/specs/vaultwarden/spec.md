# Vaultwarden — Specification

## Purpose

Gestor de contraseñas compatible con Bitwarden, con autenticación LDAP contra AD GDC01, deployado en CT Rocky Linux 9.

## Requirements

### Requirement: Autenticación LDAP

El sistema DEBE autenticar usuarios contra AD GDC01 mediante LDAP.

#### Scenario: Login exitoso con credenciales AD

- GIVEN un usuario activo en AD GDC01 con credenciales válidas
- WHEN ingresa en la página de login de Vaultwarden con su usuario y contraseña AD
- THEN el sistema le otorga acceso a su vault personal

#### Scenario: Login fallido

- GIVEN un usuario con credenciales incorrectas
- WHEN intenta autenticarse
- THEN el sistema rechaza el acceso y muestra mensaje de error

### Requirement: Gestión de contraseñas

El sistema DEBE permitir a los usuarios crear, almacenar, editar y eliminar items de credenciales (logins, tarjetas, notas, identidades).

#### Scenario: Creación de item

- GIVEN un usuario autenticado en Vaultwarden
- WHEN agrega un nuevo login con sitio, usuario y contraseña
- THEN el item se almacena cifrado y aparece en su vault

### Requirement: Organización y colecciones

El sistema DEBE permitir crear organizaciones con colecciones para compartir credenciales entre miembros.

#### Scenario: Compartir credencial por grupo

- GIVEN un usuario con permisos de Owner en una organización
- WHEN agrega un item a una colección y asigna usuarios/grupos
- THEN los usuarios asignados pueden ver y usar la credencial

### Requirement: Acceso HTTPS

El sistema DEBE servirse exclusivamente por HTTPS.

#### Scenario: Redirección HTTP a HTTPS

- GIVEN un usuario que accede por HTTP
- WHEN intenta cargar la página
- THEN es redirigido automáticamente a HTTPS
