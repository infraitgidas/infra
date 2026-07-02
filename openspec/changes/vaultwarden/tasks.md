# Tasks: Vaultwarden

## Phase 1: CT

- [ ] 1.1 Crear CT 209 con Rocky Linux 9 (512MB, 1 vCPU, IP 192.168.1.44/24)
- [ ] 1.2 Instalar Docker + nginx en CT 209
- [ ] 1.3 Crear directorios de datos (/opt/vaultwarden/data)

## Phase 2: Vaultwarden

- [ ] 2.1 Crear docker-compose.yml o docker run con config LDAP
- [ ] 2.2 Iniciar Vaultwarden y verificar login LDAP
- [ ] 2.3 Configurar organización y colecciones base

## Phase 3: SSL + DNS

- [ ] 3.1 Configurar nginx reverse proxy con self-signed SSL
- [ ] 3.2 Agregar DNS vault.gidas.local en MikroTik

## Phase 4: Portal

- [ ] 4.1 Agregar card de Vaultwarden en config.yaml del portal
- [ ] 4.2 Verificar acceso desde portal

## Phase 5: Docs

- [ ] 5.1 Documentar deploy en guia-admin
- [ ] 5.2 Agregar a informe de avance
