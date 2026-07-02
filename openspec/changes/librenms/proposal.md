# Proposal: LibreNMS — Monitoreo de Red GIDAS

## Intent

Implementar LibreNMS como sistema de monitoreo de red dedicado para dispositivos de red GIDAS (switches, routers, APs, firewalls, servidores). Complementa el stack Prometheus+Grafana existente con features NMS: auto-discovery, mapas de topología, alertas inteligentes, reportes SLA.

## Scope

### In Scope
- Deploy LibreNMS en CT Rocky Linux 9 con Docker
- Integración LDAP contra AD GDC01
- Auto-descubrimiento SNMP de dispositivos de red
- Alertas por email (SMTP Office 365)
- Sistema de alertas configurable para añadir destinatarios

### Out of Scope
- Migración de métricas existentes (Prometheus sigue igual)
- Monitoreo de aplicaciones (solo capa de red/infra)

## Capabilities

### New Capabilities
- `librenms/deploy`: NMS LibreNMS con LDAP + auto-discovery SNMP
- `librenms/alerts`: Sistema de alertas multicanal (email + Telegram + WhatsApp)

## Approach
LibreNMS en Docker Compose dentro de CT Rocky Linux 9 dedicado. LDAP contra AD GDC01. Alertas por email via Office 365. Canales adicionales via Telegram Bot API y WhatsApp Business API (o gateway).
