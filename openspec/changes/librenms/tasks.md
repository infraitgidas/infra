# Tasks: LibreNMS — Seguimiento

## Fase 1: CT

- [x] 1.1 Crear CT 210 (Rocky 9, 1GB RAM, 16GB disco, IP 192.168.1.45/24)
- [x] 1.2 Instalar Docker + nginx en CT 210

## Fase 2: LibreNMS

- [x] 2.1 Deploy LibreNMS con Docker Compose (librenms + mariadb + redis)
- [x] 2.2 Configurar LDAP contra AD GDC01 → Usar `active_directory` auth con `auth_ad_groups`
- [x] 2.3 Configurar nginx reverse proxy con SSL
- [x] 2.4 Verificar login LDAP funcional

## Fase 3: Discovery

- [x] 3.1 Configurar comunidades SNMP en dispositivos
- [x] 3.2 Configurar auto-descubrimiento en LibreNMS
- [x] 3.3 Verificar descubrimiento de dispositivos → 12 dispositivos OK

## Fase 4: Alertas

- [x] 4.1 Configurar transporte email (SMTP Office 365)
- [x] 4.2 Crear reglas de alerta basicas → Creadas por defecto, se limpiaron las vacías
- [ ] 4.3 Configurar Telegram Bot API → Pendiente (guía en `scripts/setup-telegram.sh`)
- [ ] 4.4 Analizar opcion WhatsApp y documentar

## Fase 5: Docs

- [x] 5.1 Documentar deploy en `openspec/changes/librenms/`
- [x] 5.2 Crear `librenms/.env.example`
- [ ] 5.3 Agregar card en portal GIDAS (opcional)

---

## Fase 6: Fixes Post-Implementación (2026-07-03)

- [x] **Bug #1** — Roles AD borrados en cada login:
  - Configurar `auth_ad_global_read = true`
  - Configurar `auth_ad_groups` con mapeo grupo → rol
  - Re-asignar roles admin a infrait y errodriguez
- [x] **Bug #2** — Poller nunca ejecutaba:
  - Fix crontab: `su -s /bin/bash librenms -c 'php artisan schedule:run'`
  - Fix init script `/etc/cont-init.d/07-svc-cron.sh` para persistencia
  - Verificar `device:poll all` → 12/12 dispositivos OK
- [x] **Bug #3** — Alert rules vacías rompían polling:
  - DELETE de reglas con `query` vacío
  - Deshabilitar regla "Device Down" (SQLSTATE[HY093])
- [x] Sincronizar `docker-compose.yml` del repo con deployment real
- [x] Actualizar `deploy.sh` con configuración correcta
- [x] Crear `scripts/backup.sh` (DB + config)

## Fase 7: Trabajo Pendiente

- [ ] Agregar usuarios AD a `gidas-admins` o `SRV-Monitoring` para admin completo
- [ ] Verificar dispositivos 7-12 (status=0, no resuelven hostname)
- [ ] Configurar alertas vía UI (Telegram, email)
- [ ] Activar SNMP trap receiver (puertos 162/514 expuestos)
- [ ] Schedulear backup automático (cron en CT 210 o PVE host)
- [ ] Migrar passwords a secrets Docker o SOPS
- [ ] Agregar card al portal GIDAS
- [ ] Merge rama `gitlab-gidas` → `main`
