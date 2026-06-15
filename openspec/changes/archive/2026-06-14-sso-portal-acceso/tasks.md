# Tasks: SSO + Portal de Acceso Unificado GIDAS

## Phase 1: Infraestructura — VM + Authentik

- [x] 1.1 Provisionar VM (1vCPU, 1.5GB, 10GB) en pve-desa04 desde template Rocky 10
- [x] 1.2 Configurar IP estática 192.168.1.42 y hostname `portal`
- [x] 1.3 Instalar Docker + Docker Compose
- [x] 1.4 Crear `portal/docker-compose.yml` con stack Authentik (server + worker + postgres + redis)
- [x] 1.5 Crear `.env` con secrets (postgres, redis, token)
- [x] 1.6 Ejecutar `docker compose up -d` y verificar servicios
- [ ] 1.7 Migrar Authentik a VM dedicada cuando cloud-init funcione

## Phase 2: Integración con AD

- [x] 2.1 Configurar LDAP Source en Authentik: host 192.168.1.117, bind DN `infrait`, base DN `DC=GDC01,DC=local`
- [x] 2.2 Verificar sincronización de usuarios y grupos desde AD
- [x] 2.3 Probar login con usuario AD (errodriguez, etc.)
- [ ] 2.4 Configurar grupos de Authentik basados en AD (G-Direccion → admin, G-Coordinadores, G-Becarios)

## Phase 3: SSO — GitLab + Grafana

- [x] 3.1 Crear OIDC Provider en Authentik para GitLab (Client ID/Secret, redirect URI)
- [x] 3.2 Configurar `/etc/gitlab/gitlab.rb` con omniauth OIDC apuntando a Authentik
- [x] 3.3 Ejecutar `gitlab-ctl reconfigure` y probar SSO login
- [x] 3.4 Crear OAuth2 Provider en Authentik para Grafana
- [ ] 3.5 Configurar `grafana.ini` con OAuth2 contra Authentik
- [ ] 3.6 Probar SSO login en Grafana

## Phase 4: SSO — Redmine

- [x] 4.1 Crear OIDC Provider en Authentik para Redmine
- [ ] 4.2 Instalar plugin `openid_connect` en Redmine y verificar compatibilidad
- [ ] 4.3 Configurar plugin con Client ID/Secret y endpoints de Authentik
- [ ] 4.4 Probar SSO login en Redmine

## Phase 5: Autenticación Proxmox + Networking

- [ ] 5.1 Configurar LDAP realm en Proxmox contra AD GDC01.local
- [ ] 5.2 Mapear grupo G-Direccion a rol Administrador en Proxmox
- [ ] 5.3 Agregar DNS en MikroTik: `portal.gidas.local` → IP de Authentik
- [ ] 5.4 Agregar link "Acceso a Herramientas" en Drupal gidas.frlp.utn.edu.ar

## Phase 6: Documentación

- [x] 6.1 Análisis de alternativas (`docs/portal-acceso/analisis-alternativas.md`)
- [x] 6.2 Specs SDD (6 specs en `openspec/specs/sso/`)
- [x] 6.3 Informe de avance (`docs/portal-acceso/avance.md`)
- [ ] 6.4 Crear docs de configuración por herramienta

## Phase 7: Verificación

- [ ] 7.1 Verificar SSO GitLab: login Authentik → card → GitLab sin otro login
- [ ] 7.2 Verificar SSO Grafana: login Authentik → card → Grafana sin otro login
- [ ] 7.3 Verificar SSO Redmine: login Authentik → card → Redmine sin otro login
- [ ] 7.4 Verificar LDAP Proxmox: login con credencial AD
- [ ] 7.5 Verificar acceso WAN vía Twingate desde afuera
- [ ] 7.6 Verificar que Drupal tiene link funcional al portal
