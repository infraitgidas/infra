# Spec: Dominio gidas.frlp — Integración con sitio institucional

## Purpose

Establecer la integración entre los servicios GIDAS (portal, herramientas) y el sitio institucional Drupal `gidas.frlp.utn.edu.ar`, creando un puente visible entre la infraestructura interna y la presencia pública del grupo de investigación.

## Requirements

### R1: Enlaces en Drupal

El sitio Drupal `gidas.frlp.utn.edu.ar` DEBE tener enlaces visibles a los servicios GIDAS.

#### Scenario: Enlace al Portal GIDAS
- GIVEN un visitante del sitio Drupal
- WHEN navega el menú principal
- THEN DEBE ver un enlace "Acceso a Herramientas" o "Portal GIDAS"
- AND el enlace DEBE apuntar a `https://portal.gidas.local` (vía Twingate) o la URL pública que corresponda

#### Scenario: Enlace a servicios específicos
- GIVEN un visitante del sitio Drupal
- WHEN está en la sección de enlaces
- THEN DEBE ver enlaces a: GitLab, Redmine, LibreNMS, Grafana
- AND cada enlace DEBE incluir una breve descripción del servicio

### R2: Documentación de dominio

El equipo GIDAS DEBE tener documentación clara sobre la gestión del dominio `gidas.frlp.utn.edu.ar`.

#### Scenario: Contacto de dominio
- GIVEN un miembro de GIDAS que necesita modificar el sitio Drupal
- WHEN consulta la documentación del dominio
- THEN DEBE encontrar quién administra el sitio en UTN-FRLP
- AND el procedimiento para solicitar cambios

### R3: Presencia digital unificada

La presencia digital de GIDAS DEBE tener una arquitectura clara con dos caras: pública (Drupal) y privada (Portal).

#### Scenario: Arquitectura documentada
- GIVEN un nuevo miembro de GIDAS
- WHEN consulta la documentación de infraestructura
- THEN DEBE entender la separación: Drupal como vidriera pública, Portal como acceso a herramientas internas
- AND DEBE saber cómo acceder a cada servicio

### R4: Correo institucional

Las notificaciones del sistema DEBERÍAN usar direcciones `@frlp.utn.edu.ar`.
