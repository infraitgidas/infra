# Portal de Acceso — Specification

## Purpose

Portal web que permite a los miembros de GIDAS autenticarse con credenciales de Active Directory y acceder a un dashboard con las herramientas correspondientes a sus grupos AD.

## Requirements

### Requirement: Autenticación LDAP

El sistema DEBE autenticar usuarios contra AD GDC01.local usando bind LDAP.

#### Scenario: Login exitoso con credenciales válidas

- GIVEN un usuario activo en AD GDC01 con sAMAccountName y password válidos
- WHEN el usuario ingresa sus credenciales en el formulario de login
- THEN el sistema crea una sesión JWT y redirige al dashboard

#### Scenario: Login fallido con credenciales inválidas

- GIVEN un usuario existente en AD
- WHEN ingresa una contraseña incorrecta
- THEN el sistema muestra un mensaje de error y no crea sesión

#### Scenario: AD inaccesible

- GIVEN el servidor AD (192.168.1.117) no responde
- WHEN cualquier usuario intenta loguearse
- THEN el sistema muestra un mensaje de error de servicio no disponible

### Requirement: Dashboard filtrado por grupos

El sistema DEBE mostrar solo las herramientas cuyos grupos coincidan con los grupos AD del usuario autenticado.

#### Scenario: Usuario con grupo específico ve herramientas correspondientes

- GIVEN un usuario con grupo AD "G-Becarios"
- WHEN accede al dashboard
- THEN ve las herramientas configuradas para "G-Becarios"
- AND NO ve herramientas restringidas a "G-Direccion"

#### Scenario: Usuario sin grupos asignados no ve herramientas

- GIVEN un usuario AD sin grupos memberOf
- WHEN accede al dashboard
- THEN ve un dashboard vacío sin herramientas

### Requirement: Sesión stateless con JWT

El sistema DEBE manejar sesiones mediante JWT firmado almacenado en cookie HttpOnly.

#### Scenario: Acceso sin sesión activa redirige a login

- GIVEN un navegador sin cookie de sesión
- WHEN intenta acceder al dashboard
- THEN es redirigido a /login

#### Scenario: JWT expirado redirige a login

- GIVEN una cookie con JWT expirado (más de 8 horas)
- WHEN intenta acceder al dashboard
- THEN es redirigido a /login

### Requirement: Configuración declarativa

El sistema DEBE leer la lista de herramientas y el mapeo grupos → herramientas desde un archivo YAML.

#### Scenario: Agregar nueva herramienta

- GIVEN un archivo config.yaml con una herramienta nueva
- WHEN se reinicia la aplicación
- THEN la herramienta aparece en el dashboard para los grupos configurados

#### Scenario: Config inválida impide inicio

- GIVEN un config.yaml con formato inválido
- WHEN se inicia la aplicación
- THEN la aplicación no arranca y muestra un error descriptivo
