# SSO / Grafana OAuth Integration Specification

## Purpose

Integración OAuth de Grafana con Authentik como IdP: SSO para dashboards de monitoreo.

## Requirements

### Requirement: OAuth Provider en Authentik

Authentik DEBE configurarse como proveedor OAuth2 para Grafana.

#### Scenario: Provider configurado

- GIVEN Authentik funcionando
- WHEN se crea un OAuth2 Provider para Grafana
- THEN Authentik DEBE generar Client ID, Client Secret y endpoints de autenticación

### Requirement: OAuth Client en Grafana

Grafana DEBE configurarse con autenticación OAuth contra Authentik.

#### Scenario: SSO login exitoso

- GIVEN Grafana con OAuth configurado contra Authentik
- WHEN el usuario autenticado en Authentik clickea la card de Grafana
- THEN Grafana DEBE aceptar el token de Authentik
- AND el usuario DEBE ver sus dashboards sin login adicional

#### Scenario: Asignación de roles

- GIVEN un usuario autenticado vía SSO en Grafana
- WHEN el usuario pertenece al grupo G-Direccion en AD
- THEN Grafana DEBE asignarle rol de Admin (mapeado por grupo)
