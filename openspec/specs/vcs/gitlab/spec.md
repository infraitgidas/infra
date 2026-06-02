# VCS / GitLab Specification

## Purpose

GitLab CE (Omnibus) como VCS on-premise para el Grupo Gidas: repositorios Git privados con Web UI, API REST, HTTPS y backups, sin dependencia externa.

## Requirements

### Requirement: VM Provisioning

Proxmox DEBE aprovisionar una VM con 4 vCPU, 8 GB RAM, 80 GB SSD y Rocky Linux 10 para GitLab CE.

#### Scenario: Recursos correctos

- GIVEN una VM para GitLab CE
- WHEN se verifica la configuración
- THEN la VM MUST tener 4 vCPU, 8 GB RAM y 80 GB disco

#### Scenario: Recursos insuficientes

- GIVEN pve-desa01 sin recursos disponibles
- WHEN se intenta crear la VM
- THEN el aprovisionamiento DEBE fallar con error claro

### Requirement: Instalación Omnibus

GitLab CE DEBE instalarse mediante el paquete Omnibus oficial. Redis y PostgreSQL DEBEN ser bundled (no externos).

#### Scenario: Instalación exitosa

- GIVEN VM con Rocky Linux 10 y acceso a Internet
- WHEN se ejecuta el script de instalación Omnibus
- THEN `gitlab-ctl status` DEBE reportar todos los servicios como "run"
- AND la Web UI DEBE responder en http://<hostname>:80

#### Scenario: Sin conectividad

- GIVEN una VM sin acceso a Internet
- WHEN se ejecuta el script de instalación
- THEN el script DEBE fallar y registrar error de conectividad

### Requirement: HTTPS con Let's Encrypt

GitLab DEBE servir tráfico HTTPS con certificado Let's Encrypt válido gestionado por Omnibus.

#### Scenario: Certificado emitido

- GIVEN GitLab con dominio configurado y puerto 80 accesible
- WHEN Omnibus ejecuta `letsencrypt['enable'] = true`
- THEN https://<gitlab-domain> DEBE responder con certificado válido
- AND la renovación automática DEBE estar configurada

#### Scenario: Puerto 80 bloqueado

- GIVEN un entorno sin puerto 80 público
- WHEN Let's Encrypt intenta challenge HTTP-01
- THEN GitLab DEBE usar DNS-01 challenge
- AND el certificado DEBE emitirse correctamente

### Requirement: Acceso SSH

GitLab DEBE aceptar conexiones Git SSH en puerto 2222 del host (mapeado al puerto 22 de la VM).

#### Scenario: Clonar vía SSH

- GIVEN un repo con clave SSH registrada
- WHEN el usuario ejecuta `git clone ssh://git@<host>:2222/grupo/repo.git`
- THEN el clon DEBE completarse exitosamente

#### Scenario: Push vía SSH

- GIVEN un repo clonado vía SSH
- WHEN el usuario hace commit y push
- THEN los cambios DEBEN reflejarse en la Web UI

### Requirement: Backups

GitLab DEBE realizar backups diarios vía `gitlab-backup` y Proxmox DEBE tomar snapshots semanales de la VM.

#### Scenario: Backup diario

- GIVEN cron configurado para `gitlab-backup`
- WHEN se ejecuta el backup diario
- THEN el archivo .tar DEBE generarse en /var/opt/gitlab/backups/
- AND DEBE incluir repos, PostgreSQL y config

#### Scenario: Restauración

- GIVEN un backup existente
- WHEN se ejecuta `gitlab-backup restore`
- THEN todos los repos y usuarios DEBEN restaurarse

#### Scenario: Snapshot semanal

- GIVEN la VM en pve-desa01
- WHEN se ejecuta el snapshot PVE semanal
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

### Requirement: Autenticación Local

GitLab DEBE soportar autenticación local (registro, login email/contraseña, roles básicos). LDAP/SSO fuera de scope.

#### Scenario: Registro de usuario

- GIVEN GitLab con sign-up habilitado
- WHEN un nuevo usuario se registra con email y contraseña
- THEN el usuario DEBE poder iniciar sesión inmediatamente

#### Scenario: Login fallido

- GIVEN un usuario registrado
- WHEN ingresa una contraseña incorrecta
- THEN GitLab DEBE rechazar el acceso y mostrar error
