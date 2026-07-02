# Networking / Public Access Specification

## Purpose

Exponer el portal Authentik a los miembros de GIDAS desde internet vía Twingate, sin exponer puertos a internet.

## Requirements

### Requirement: Acceso vía Twingate

El portal Authentik DEBE ser accesible desde internet exclusivamente a través de Twingate, sin puertos abiertos en el firewall.

#### Scenario: Acceso remoto

- GIVEN Twingate configurado y con acceso al cluster Proxmox
- WHEN un miembro de GIDAS con Twingate instalado accede a la URL del portal
- THEN DEBE ver la página de login de Authentik
- AND la conexión DEBE ser cifrada de extremo a extremo

#### Scenario: Sin Twingate

- GIVEN un usuario sin Twingate instalado
- WHEN intenta acceder al portal desde internet
- THEN NO DEBE poder establecer conexión

### Requirement: DNS Interno

El portal DEBE tener una entrada DNS interna `portal.gidas.local` en MikroTik.

#### Scenario: Resolución interna

- GIVEN MikroTik con DNS habilitado
- WHEN un dispositivo en la LAN consulta `portal.gidas.local`
- THEN DEBE resolver a la IP interna de Authentik

### Requirement: Integración con Drupal

El sitio Drupal `gidas.frlp.utn.edu.ar` DEBE tener un enlace al portal Authentik.

#### Scenario: Enlace visible

- GIVEN el sitio Drupal con acceso admin
- WHEN se agrega un link en el menú principal "Acceso a Herramientas"
- THEN el link DEBE apuntar a la URL pública del portal vía Twingate
- AND DEBE ser visible para todos los visitantes del sitio
