# Proposal: Dominio gidas.frlp — Integración con sitio institucional

## Intent

Integrar los servicios GIDAS con el dominio institucional `gidas.frlp.utn.edu.ar` (sitio Drupal de UTN-FRLP), estableciendo un puente entre la infraestructura interna de GIDAS y el sitio público del grupo de investigación.

## Problem

Actualmente los servicios GIDAS operan en el dominio interno `gidas.local` y son accesibles solo via LAN o Twingate. El sitio institucional `gidas.frlp.utn.edu.ar` (Drupal) es la cara pública del grupo pero no tiene enlaces a las herramientas internas. Tampoco hay una estrategia clara de subdominio público, correo institucional unificado, o presencia web de los servicios.

## Scope

### In Scope
- Agregar enlaces en Drupal a servicios GIDAS (portal, GitLab, Redmine, LibreNMS, Grafana)
- Evaluar subdominio `gidas.frlp.utn.edu.ar` para servicios (ej: portal.gidas.frlp.utn.edu.ar)
- Documentar contacto y procedimiento para gestión del dominio
- Unificar presencia digital: portal como punto de entrada, Drupal como vidriera

### Out of Scope
- Migrar Drupal a infraestructura GIDAS (sigue siendo administrado por UTN-FRLP)
- Autenticación AD en Drupal (requiere coordinación externa)
- Reemplazar Drupal como sitio institucional
- SSL/TLS público para servicios internos (se usa Twingate)

## Capabilities

### New Capabilities
- `drupal/enlaces`: Sitio Drupal con enlaces a servicios GIDAS
- `dominio/estrategia`: Documentación de dominio y subdominio
- `presencia/publica`: Portal público como entrada unificada via Twingate

## Approach

1. **Coordinar con administradores de Drupal UTN-FRLP** para agregar enlaces
2. **Evaluar viabilidad de subdominio** `gidas.frlp.utn.edu.ar`
3. **Documentar arquitectura de presencia digital**: Drupal (público) → Portal GIDAS (privado, via Twingate) → Servicios internos
4. **Unificar mailings**: usar `gidas@frlp.utn.edu.ar` como contacto institucional

## Rollback

- Los enlaces en Drupal son fáciles de remover (cambios en menú del CMS)
- No hay cambios en infraestructura crítica que requieran rollback complejo
