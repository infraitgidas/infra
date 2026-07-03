# Tasks: LibreNMS — Seguimiento

## Fase 1: CT — ✅ Completada

- [x] 1.1 Crear CT 210 (Rocky 9, 1GB RAM, 16GB disco, IP 192.168.1.45/24)
- [x] 1.2 Instalar Docker + nginx en CT 210

## Fase 2: LibreNMS — ✅ Completada

- [x] 2.1 Deploy LibreNMS con Docker Compose (librenms + mariadb + redis)
- [x] 2.2 Configurar LDAP contra AD GDC01 → Usar `active_directory` auth con `auth_ad_groups`
- [x] 2.3 Configurar nginx reverse proxy con SSL
- [x] 2.4 Verificar login LDAP funcional

## Fase 3: Discovery — ✅ Completada

- [x] 3.1 Configurar comunidades SNMP en dispositivos
- [x] 3.2 Configurar auto-descubrimiento en LibreNMS
- [x] 3.3 Verificar descubrimiento de dispositivos → 12 dispositivos OK

## Fase 4: Alertas — ✅ Completada

- [x] 4.1 Configurar transporte email (SMTP Office 365)
- [x] 4.2 Crear reglas de alerta basicas → 18 rules creadas via builder JSON
- [x] 4.3 Configurar Telegram Bot API → Bot GIDAS Alertas operativo (@GiDAS_alertbot)
- [ ] 4.4 Analizar opcion WhatsApp y documentar → Pendiente (baja prioridad)

## Fase 5: Docs — ✅ Completada

- [x] 5.1 Documentar deploy en `openspec/changes/librenms/`
- [x] 5.2 Crear `librenms/.env.example`
- [x] 5.3 Agregar card en portal GIDAS → LibreNMS visible para 4 grupos

## Fase 6: Fixes Post-Implementación — ✅ Completada

- [x] **Bug #1** — Roles AD borrados en cada login
- [x] **Bug #2** — Poller nunca ejecutaba
- [x] **Bug #3** — Alert rules vacías rompían polling
- [x] Sincronizar `docker-compose.yml` del repo con deployment real
- [x] Actualizar `deploy.sh` con configuración correcta
- [x] Crear `scripts/backup.sh` (DB + config)

## Fase 7: Integración Grafana + Portal — ✅ Completada

- [x] 7.1 Desplegar Grafana en CT 205 (sg-monitoring, pve-ad)
- [x] 7.2 Configurar datasource LibreNMS (built-in, sin plugin externo)
- [x] 7.3 Importar 3 dashboards: Overview, Performance, Network
- [x] 7.4 Setear password admin: hlvs.2025
- [x] 7.5 Agregar LibreNMS al portal GIDAS (config.yaml)
- [x] 7.6 Eliminar Grafana Docker de CT 210 (liberar RAM)

---

## 🔴 Fase 8: Tareas de Monitoreo Pendientes

### 8.1 Gestión de Accesos y Roles AD

| # | Tarea | Prioridad | Esfuerzo | Dependencia |
|---|-------|-----------|----------|-------------|
| 8.1.1 | Agregar usuarios clave (`infrait`, `errodriguez`) a grupo `gidas-admins` o `SRV-Monitoring` en AD | 🔴 Alta | 5 min | Acceso a AD |
| 8.1.2 | Definir política de grupos AD para NMS: qué grupo da qué rol | 🟡 Media | 30 min | Decisión de equipo |
| 8.1.3 | Agregar `gidas-pve-admin` y `gidas-pve-viewer` a `auth_ad_groups` si se necesita (ya configurados en config.php) | 🟢 Baja | 5 min | — |

**Contexto**: Actualmente `G-IdentityAdmins` da admin en LNMS. Lo ideal es usar `gidas-admins` (admin total) y `SRV-Monitoring` (operaciones de monitoreo). La cuenta `infrait` es service account y no debería usarse como personal.

---

### 8.2 Inventario y Discovery

| # | Tarea | Prioridad | Esfuerzo | Dependencia |
|---|-------|-----------|----------|-------------|
| 8.2.1 | Verificar dispositivos 7-12 (status=0, no responden SNMP) | 🔴 Alta | 1h | Acceso a dispositivos |
| 8.2.2 | Configurar SNMP correctamente en dispositivos con status=0 | 🔴 Alta | 2h | Acceso físico/SSH a cada dispositivo |
| 8.2.3 | Agregar impresoras de red (mencionadas por usuario) | 🟡 Media | 30 min | IP/comunidad SNMP |
| 8.2.4 | Agregar switch de acceso (pve-desa03, pve-ad) | 🟡 Media | 30 min | IP/comunidad SNMP |
| 8.2.5 | Configurar reverse DNS en MikroTik o DNS local para resolución de hostnames | 🟡 Media | 1h | Acceso a MikroTik |

**Contexto**: 7 dispositivos tienen `status=0` porque no responden SNMP o no tienen reverse DNS. La tabla completa:

| IP | Hostname actual | Posible | Estado |
|-----|-----------------|---------|--------|
| 192.168.1.13 | pve-desa03 | PVE node desa03 | ❌ No responde |
| 192.168.1.20 | (sin resolver) | ¿Switch? | ❌ Sin SNMP |
| 192.168.1.41 | (sin resolver) | GitLab VM | ❌ SNMP deshabilitado |
| 192.168.1.205 | (sin resolver) | CT 205 Grafana | ❌ SNMP deshabilitado |
| 192.168.1.43 | (sin resolver) | CT 208 Portal | ❌ SNMP deshabilitado |
| 192.168.1.44 | (sin resolver) | CT 209 Vaultwarden | ❌ SNMP deshabilitado |
| 192.168.1.45 | (sin resolver) | CT 210 LibreNMS | ❌ SNMP deshabilitado (loop) |

**Recomendación**: Los CTs (41, 43, 44, 45) son contenedores LXC y tiene sentido monitorearlos via agente o librerias del host PVE, no via SNMP directo. La IP 20 habría que identificar qué dispositivo es.

---

### 8.3 Alertas y Notificaciones

| # | Tarea | Prioridad | Esfuerzo | Dependencia |
|---|-------|-----------|----------|-------------|
| 8.3.1 | Revisar 2 alertas activas (High Temperature en pve-desa01) | 🟡 Media | 15 min | — |
| 8.3.2 | Ajustar thresholds de reglas según necesidad operativa | 🟡 Media | 1h | Decisión de equipo |
| 8.3.3 | Configurar alerta de heartbeat: si LibreNMS deja de reportar, notificar | 🟡 Media | 30 min | Script externo o servicio |
| 8.3.4 | Analizar y documentar opción WhatsApp (CallMeBot) | 🟢 Baja | 30 min | — |

**Contexto**: Ya hay 18 reglas creadas con thresholds genéricos. Cada equipo puede necesitar thresholds distintos (ej: un servidor con 90% RAM sostenido puede ser normal, en otro es crítico). Las alertas activas deben revisarse para confirmar que no son falsos positivos.

---

### 8.4 SNMP Traps y Syslog

| # | Tarea | Prioridad | Esfuerzo | Dependencia |
|---|-------|-----------|----------|-------------|
| 8.4.1 | Activar SNMP trap receiver en LibreNMS (puertos 162/udp+tcp ya expuestos) | 🟡 Media | 30 min | Configurar dispositivos para enviar traps |
| 8.4.2 | Configurar dispositivos de red (MikroTik, switches) para enviar traps a 192.168.1.45 | 🟡 Media | 1h | Acceso a cada dispositivo |
| 8.4.3 | Activar syslog receiver en LibreNMS (puerto 514/udp+tcp ya expuesto) | 🟡 Media | 30 min | Configurar dispositivos para enviar syslog |
| 8.4.4 | Crear reglas de alerta basadas en traps/syslog recibidos | 🟡 Media | 1h | Depende de 8.4.1 y 8.4.3 |

**Contexto**: Los puertos 162 (SNMP traps) y 514 (syslog) ya están expuestos en el docker-compose.yml pero no hay procesos escuchando adentro del container. LibreNMS puede procesar traps via `snmpd` interno y syslog via `socklog`.

**Configuración necesaria**:
```bash
# Verificar que snmpd esté corriendo
pct exec 210 -- docker exec librenms ps aux | grep snmpd

# Configurar dispositivos MikroTik para enviar traps:
# /snmp-community set public address=192.168.1.45
# /system logging add action=remote remote=192.168.1.45 topics=info
```

---

### 8.5 Backup y Recovery

| # | Tarea | Prioridad | Esfuerzo | Dependencia |
|---|-------|-----------|----------|-------------|
| 8.5.1 | Schedulear backup automático diario (DB + config) | 🟡 Media | 15 min | — |
| 8.5.2 | Verificar restore del backup | 🟡 Media | 30 min | Depende de 8.5.1 |
| 8.5.3 | Agregar backup de RRDs (datos históricos) — opcional | 🟢 Baja | 15 min | — |

**Script disponible**: `librenms/scripts/backup.sh` — hace dump MySQL + config. Falta schedulearlo.

**Cron sugerido** (en CT 210 o PVE host):
```bash
# Diario a las 03:00
0 3 * * * /opt/librenms/scripts/backup.sh /var/backups/librenms
```

---

### 8.6 Monitoreo del Monitoreo (Heartbeat)

| # | Tarea | Prioridad | Esfuerzo | Dependencia |
|---|-------|-----------|----------|-------------|
| 8.6.1 | Crear healthcheck externo que verifique que LibreNMS responde | 🟡 Media | 30 min | — |
| 8.6.2 | Configurar alerta si LibreNMS no responde (vía Telegram) | 🟡 Media | 30 min | Depende de 8.6.1 |

**Idea**: Un script simple que corre cada 5 minutos desde otro host (CT 208 o PVE host) que haga `curl https://nms.gidas.local` y si no responde, envíe un mensaje Telegram.

```bash
#!/bin/bash
# heartbeat-lnms.sh
curl -skf --max-time 10 https://nms.gidas.local/api/v0 > /dev/null 2>&1 || \
  curl -s "https://api.telegram.org/bot8965268173:AAFOqin05EmL7bMSqQkJmgu4uo5GrAwxC-o/sendMessage" \
    -d "chat_id=1773145563" \
    -d "text=🔴 *ALERTA* LibreNMS no responde - $(date)" \
    -d "parse_mode=Markdown"
```

---

### 8.7 Performance y Estabilidad

| # | Tarea | Prioridad | Esfuerzo | Dependencia |
|---|-------|-----------|----------|-------------|
| 8.7.1 | Monitorear uso de RAM/CPU del CT 210 (1GB puede ser escaso) | 🟡 Media | 15 min | — |
| 8.7.2 | Evaluar si conviene migrar MariaDB a CT separado | 🟢 Baja | 2h | Decisión de equipo |
| 8.7.3 | Configurar `poller-wrapper.py` con 2 hilos si la carga lo requiere | 🟢 Baja | 15 min | — |

**Contexto**: CT 210 tiene 1GB RAM. LibreNMS + MariaDB + Redis consumen ~700MB. Con 12 dispositivos está bien, pero si crece la flota, va a necesitar más RAM.

---

### 8.8 Seguridad

| # | Tarea | Prioridad | Esfuerzo | Dependencia |
|---|-------|-----------|----------|-------------|
| 8.8.1 | Migrar passwords del .env y config.php a Docker secrets o archivo cifrado | 🟡 Media | 1h | — |
| 8.8.2 | Revisar que el container no corra como root (entrypoint issue) | 🟢 Baja | 1h | — |
| 8.8.3 | Configurar HTTPS con certificado válido (Let's Encrypt o interno) | 🟢 Baja | 1h | — |

---

### 8.9 Documentación

| # | Tarea | Prioridad | Esfuerzo | Dependencia |
|---|-------|-----------|----------|-------------|
| 8.9.1 | Merge rama `feat/monitoreo-red` → `main` | 🟡 Media | 15 min | Revisión de cambios |
| 8.9.2 | Merge rama `gitlab-gidas` → `main` (contiene optimizaciones PVE) | 🟢 Baja | 15 min | Revisión de cambios |

---

### 8.10 Dashboard y Visualización

| # | Tarea | Prioridad | Esfuerzo | Dependencia |
|---|-------|-----------|----------|-------------|
| 8.10.1 | Crear dashboard de disponibilidad mensual (SLA) | 🟢 Baja | 30 min | Datos en LibreNMS |
| 8.10.2 | Crear dashboard de alertas histórico | 🟢 Baja | 30 min | Datos en LibreNMS |
| 8.10.3 | Crear dashboard de topología/red física | 🟢 Baja | 1h | Mapa de red |

---

## Resumen de Prioridades

| Prioridad | Cantidad | Tareas |
|-----------|----------|--------|
| 🔴 Alta | 3 | 8.1.1 (roles AD), 8.2.1 + 8.2.2 (dispositivos caídos) |
| 🟡 Media | 16 | 8.1.2, 8.2.3-5 (discovery), 8.3.1-3 (alertas), 8.4.1-4 (traps/syslog), 8.5.1-2 (backup), 8.6.1-2 (heartbeat), 8.7.1 (performance), 8.8.1 (secrets), 8.9.1 (merge) |
| 🟢 Baja | 11 | 8.1.3, 8.3.4, 8.5.3, 8.7.2-3, 8.8.2-3, 8.9.2, 8.10.1-3 |

**Total tareas pendientes: 30** (3 altas, 16 medias, 11 bajas)
