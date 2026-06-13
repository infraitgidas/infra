# VCS / GitLab Specification

## Purpose

GitLab CE (Omnibus) como VCS on-premise para el Grupo Gidas: repositorios Git privados con Web UI, API REST, HTTPS, autenticación LDAP contra AD, y backups, sin dependencia externa.

## Requirements

### Requirement: VM Provisioning

Proxmox DEBE aprovisionar una VM con 4 vCPU, 8 GB RAM, 80 GB SSD, BIOS OVMF UEFI y Rocky Linux 10 para GitLab CE.

#### Scenario: Recursos correctos

- GIVEN una VM para GitLab CE
- WHEN se verifica la configuración
- THEN la VM MUST tener 4 vCPU, 8 GB RAM, 80 GB disco y OVMF UEFI

#### Scenario: Recursos insuficientes

- GIVEN pve-desa04 sin recursos disponibles
- WHEN se intenta crear la VM
- THEN el aprovisionamiento DEBE fallar con error claro

### Requirement: Instalación Omnibus

GitLab CE DEBE instalarse mediante el paquete Omnibus oficial. Redis y PostgreSQL DEBEN ser bundled (no externos).

#### Scenario: Instalación exitosa

- GIVEN VM con Rocky Linux 10 y acceso a Internet
- WHEN se ejecuta el script de instalación Omnibus
- THEN `gitlab-ctl status` DEBE reportar todos los servicios como "run"
- AND la Web UI DEBE responder en https://<hostname>

#### Scenario: Sin conectividad

- GIVEN una VM sin acceso a Internet
- WHEN se ejecuta el script de instalación
- THEN el script DEBE fallar y registrar error de conectividad

### Requirement: HTTPS Self-Signed

GitLab DEBE servir tráfico HTTPS con certificado self-signed gestionado por Omnibus. No se usa Let's Encrypt porque el dominio `.local` no es un TLD válido para la autoridad certificadora.

#### Scenario: Certificado self-signed

- GIVEN GitLab con dominio `.local` configurado
- WHEN Omnibus ejecuta `nginx['ssl_certificate']` con self-signed
- THEN https://gitlab.gidas.local DEBE responder con HTTPS (advertencia de certificado no confiable)
- AND el servicio DEBE ser accesible vía curl -k

#### Scenario: Acceso HTTPS

- GIVEN un cliente con `git config http.sslVerify=false`
- WHEN ejecuta `git clone https://gitlab.gidas.local/grupo/repo.git`
- THEN el clon DEBE completarse exitosamente

### Requirement: Acceso SSH

GitLab DEBE aceptar conexiones Git SSH en puerto 2222 del host Proxmox, mapeado vía DNAT al puerto 2222 de la VM donde escucha gitlab-sshd.

#### Scenario: Clonar vía SSH

- GIVEN un repo con clave SSH registrada en el perfil del usuario
- WHEN el usuario ejecuta `git clone ssh://git@<pve-host>:2222/grupo/repo.git`
- THEN el clon DEBE completarse exitosamente

#### Scenario: Push vía SSH

- GIVEN un repo clonado vía SSH
- WHEN el usuario hace commit y push
- THEN los cambios DEBEN reflejarse en la Web UI

#### Scenario: Clave SSH no registrada

- GIVEN un repo existente
- WHEN un usuario sin clave SSH registrada intenta clonar vía SSH
- THEN GitLab DEBE rechazar con `Permission denied (publickey)`

### Requirement: Autenticación LDAP con Active Directory

GitLab DEBE autenticar usuarios contra el Active Directory GDC01.local mediante LDAP simple bind, usando la service account `CN=infrait,OU=ServiceAccounts,DC=GDC01,DC=local`.

#### Scenario: Login LDAP exitoso

- GIVEN AD GDC01.local accesible y LDAP bind configurado
- WHEN un usuario AD ingresa su sAMAccountName y contraseña en la Web UI
- THEN GitLab DEBE autenticarlo contra AD
- AND DEBE crear el usuario local automáticamente (primer login)

#### Scenario: Login LDAP fallido

- GIVEN AD GDC01.local accesible
- WHEN un usuario AD ingresa una contraseña incorrecta
- THEN GitLab DEBE rechazar el acceso

#### Scenario: LDAP bind verification

- GIVEN `gitlab.rb` con bind DN y password de infrait
- WHEN se ejecuta `gitlab-rake gitlab:ldap:check`
- THEN DEBE mostrar "LDAP authentication... Success"
- AND DEBE listar usuarios AD importables

### Requirement: Sincronización de Grupos AD → GitLab

GitLab DEBE sincronizar la membresía de grupos AD a grupos GitLab mediante el script `sync-ad-members.sh`, reflejando la estructura organizacional del AD.

#### Lógica de mapeo

| Grupo AD | Rol GitLab | Ámbito |
|----------|-----------|--------|
| G-Direccion | Owner (nivel 50) | TODOS los grupos GitLab |
| G-Coordinadores ∩ PROY-X | Maintainer (nivel 40) | Grupo del proyecto X |
| G-Becarios ∩ PROY-X | Developer (nivel 30) | Grupo del proyecto X |

#### Scenario: Sync de grupos

- GIVEN grupos GitLab creados y usuarios AD importados
- WHEN se ejecuta `sync-ad-members.sh`
- THEN los miembros DEBEN reflejar la membresía actual del AD
- AND los roles DEBEN respetar el mapeo definido

#### Scenario: Usuario sin cuenta GitLab

- GIVEN un usuario AD sin cuenta en GitLab
- WHEN se ejecuta `sync-ad-members.sh`
- THEN el script DEBE informar que el usuario se creará en el primer login LDAP
- AND NO DEBE fallar por usuarios faltantes

### Requirement: Token API

GitLab DEBE tener un token de API con alcance `api` para operaciones automatizadas (sync AD, creación de proyectos, gestión de miembros).

#### Scenario: Token generado

- GIVEN el usuario administrador root
- WHEN se genera un PersonalAccessToken
- THEN el token DEBE tener scopes `api`, `read_api`, `read_user`, `write_repository`
- AND DEBE tener expiración configurada (máx 1 año)

### Requirement: Backups

GitLab DEBE realizar backups diarios vía `gitlab-backup` y Proxmox DEBE tomar snapshots semanales de la VM en pve-desa04.

#### Scenario: Backup diario

- GIVEN cron configurado en la VM GitLab para `gitlab-backup`
- WHEN se ejecuta el backup diario a las 02:00
- THEN el archivo .tar DEBE generarse en /var/opt/gitlab/backups/
- AND DEBE incluir repos, PostgreSQL, y metadatos
- AND `/etc/gitlab/gitlab-secrets.json` DEBE respaldarse por separado

#### Scenario: Restauración

- GIVEN un backup existente en /var/opt/gitlab/backups/
- WHEN se ejecuta `gitlab-backup restore BACKUP=<timestamp>`
- THEN todos los repos y usuarios DEBEN restaurarse
- AND los secrets DEBEN restaurarse manualmente

#### Scenario: Snapshot semanal

- GIVEN la VM ID 201 en pve-desa04
- WHEN se ejecuta el snapshot PVE semanal (domingo 03:00)
- THEN Proxmox DEBE crear un snapshot consistente y revertible

### Requirement: Gestión de Repositorios

Usuarios autenticados DEBEN poder crear, clonar y gestionar repositorios Git vía Web UI y API REST.

#### Scenario: Crear proyecto

- GIVEN un usuario autenticado en GitLab
- WHEN crea un nuevo proyecto desde la Web UI
- THEN el repo DEBE aparecer en el panel del usuario
- AND DEBE ser clonable vía HTTPS y SSH

#### Scenario: API REST

- GIVEN un token de API de GitLab
- WHEN se consulta `GET /api/v4/projects`
- THEN la API DEBE retornar proyectos en formato JSON
