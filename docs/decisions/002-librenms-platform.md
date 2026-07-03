# ADR-002: LibreNMS como sistema de monitoreo de red

**Fecha:** 2026-07-03
**Contexto:** El grupo GIDAS necesitaba un sistema de monitoreo de red dedicado que complementara el stack Prometheus+Grafana existente (orientado a métricas del cluster PVE). Se requería auto-descubrimiento SNMP, alertas multicanal, mapas de topología y reportes de disponibilidad.

## Decisión

**Implementar LibreNMS 26.6.1** en Docker Compose dentro de un CT dedicado (CT 210, pve-desa04), con MariaDB + Redis, autenticación contra AD GDC01, y alertas por Telegram + SMTP.

## Alternativas Consideradas

| Alternativa | Descartada por |
|-------------|----------------|
| **Zabbix** | Mayor consumo de recursos (~1GB RAM), configuración más compleja, sin mapas de topología automáticos. |
| **CheckMK Raw** | LDAP solo en edición Enterprise (paga). Sin integración AD posible. |
| **Prometheus + SNMP exporter** | Ya existente. Cubre métricas pero no features NMS: auto-descubrimiento, mapas, alertas inteligentes, reportes SLA. |

## Argumentos a Favor

1. **Recursos ajustados:** ~512MB RAM + PHP + MySQL + Redis. Funciona en CT con 1GB RAM y 1 vCPU.
2. **AD/LDAP nativo:** Soporta autenticación y mapeo de roles por grupos AD. Mecanismo `active_directory` built-in.
3. **Auto-descubrimiento:** SNMP, LLDP, CDP, OSPF, BGP. Descubrimiento automático de dispositivos.
4. **Alertas multicanal:** Email + Telegram verificados. Slack, Discord, WhatsApp también disponibles.
5. **Gráficas históricas:** RRDtool integrado con históricos por dispositivo, puerto, sensor.
6. **Datasource Grafana:** Plugin nativo `librenms-datasource` (built-in en Grafana 13+). Permite dashboards unificados.
7. **Mapas de topología:** Automáticos basados en descubrimiento de red.
8. **Deploy simple:** Docker Compose con 3 servicios (app + db + cache).

## Riesgos y Mitigaciones

| Riesgo | Mitigación |
|--------|------------|
| Bug en syncRoles() borra roles AD en cada login | `auth_ad_global_read=true` + `auth_ad_groups` mapeado |
| Poller no ejecuta (artisan no corre como root) | `su -s /bin/bash librenms -c` en crontab + fix en init script |
| CT 210 con 1GB RAM puede ser escaso | Monitorear. Si la flota crece, migrar MariaDB a CT separado o ampliar RAM. |
| Tag `:fixed` puede quedarse sin updates | Evaluar migración a `:latest` con pruebas en staging. |

## Configuración

- **Stack**: Docker Compose (librenms:fixed + mariadb:10 + redis:7-alpine)
- **Ubicación**: CT 210, pve-desa04, 192.168.1.45
- **URL**: `https://nms.gidas.local`
- **Auth**: ActiveDirectory contra AD GDC01
- **Dispositivos**: 12 descubiertos, 12/12 polleando
- **Alertas**: 18 reglas (CPU, RAM, disco, uptime, latencia, puertos, temperatura, seguridad)

## Próximos Pasos

1. Agregar usuarios AD a `gidas-admins` o `SRV-Monitoring` para admin completo
2. Verificar 7 dispositivos con status=0
3. Activar SNMP traps + syslog
4. Schedulear backup automático

## Estado

**Aceptada e Implementada**
