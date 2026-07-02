# Tasks: LibreNMS

## Phase 1: CT

- [ ] 1.1 Crear CT 210 (Rocky 9, 1GB RAM, 16GB disco, IP 192.168.1.45/24)
- [ ] 1.2 Instalar Docker + nginx en CT 210

## Phase 2: LibreNMS

- [ ] 2.1 Deploy LibreNMS con Docker Compose (librenms + mariadb + redis)
- [ ] 2.2 Configurar LDAP contra AD GDC01
- [ ] 2.3 Configurar nginx reverse proxy con SSL
- [ ] 2.4 Verificar login LDAP funcional

## Phase 3: Discovery

- [ ] 3.1 Configurar comunidades SNMP en dispositivos
- [ ] 3.2 Configurar auto-descubrimiento en LibreNMS
- [ ] 3.3 Verificar descubrimiento de dispositivos

## Phase 4: Alertas

- [ ] 4.1 Configurar transporte email (SMTP Office 365)
- [ ] 4.2 Crear reglas de alerta basicas
- [ ] 4.3 Configurar Telegram Bot API
- [ ] 4.4 Analizar opcion WhatsApp y documentar

## Phase 5: Docs

- [ ] 5.1 Documentar deploy en librenms/README.md
- [ ] 5.2 Crear librenms/.env.example
- [ ] 5.3 Agregar card en portal GIDAS (opcional)
