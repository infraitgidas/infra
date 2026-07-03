# Spec: Portal GIDAS desde Drupal — Enlace público

## Purpose

Publicar un enlace en el sitio institucional `gidas.frlp.utn.edu.ar` que permita a los miembros del grupo acceder al Portal GIDAS y sus herramientas internas.

## Requirements

### R1: Enlace visible en el menú principal

El sitio DEBE mostrar un enlace "Portal GIDAS" en el menú principal de navegación.

#### Scenario: Enlace visible para todos los visitantes
- GIVEN un visitante del sitio `gidas.frlp.utn.edu.ar`
- WHEN navega la página principal
- THEN DEBE ver un enlace con el texto "Portal GIDAS" en el menú principal
- AND el enlace DEBE ser visible sin necesidad de iniciar sesión en Drupal

#### Scenario: Click en el enlace
- GIVEN un visitante en `gidas.frlp.utn.edu.ar`
- WHEN hace click en "Portal GIDAS"
- THEN DEBE ser redirigido a una página explicativa
- AND la página DEBE contener el enlace a `https://portal.gidas.local`
- AND DEBE incluir instrucciones sobre Twingate

### R2: Página explicativa

La página DEBE contener información clara sobre cómo acceder a las herramientas.

#### Scenario: Usuario sin Twingate
- GIVEN un visitante sin Twingate instalado
- WHEN lee la página de Portal GIDAS
- THEN DEBE encontrar instrucciones para solicitar acceso
- AND DEBE saber a quién contactar

### R3: Contenido auto-administrable

La página DEBE ser editable desde el admin de Drupal (sin acceso al servidor).

#### Scenario: Modificación de contenido
- GIVEN un administrador de Drupal
- WHEN necesita actualizar la página
- THEN DEBE poder hacerlo desde `/admin/content`
- AND los cambios DEBEN publicarse inmediatamente

### R4: Rollback

El cambio DEBE poder revertirse sin impacto en otras partes del sitio.

#### Scenario: Reversión
- GIVEN que se necesita eliminar el enlace
- WHEN un administrador accede a la estructura de menús
- THEN DEBE poder eliminar el elemento del menú sin afectar otros contenidos
- AND la página DEBE poder despublicarse o eliminarse
