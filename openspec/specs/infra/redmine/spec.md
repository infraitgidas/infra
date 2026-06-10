# infra/redmine — Especificación

## Propósito

Desplegar y operar Redmine como gestor de proyectos open source en una VM de
`pve-desa`, siguiendo el patrón Docker Compose del stack `sg-monitoring`.

## Requisitos

### Requisito: Infraestructura de la VM

El sistema DEBE crear una VM QEMU/KVM dedicada (ID ~206) en `pve-desa` con
2 vCPU, 4 GB RAM, 20 GB disco y Rocky Linux 10 como sistema operativo.

#### Escenario: Creación de VM desde scripts

- DADO `pve-desa` operativo con recursos disponibles
- CUANDO se ejecuta el script de aprovisionamiento (`qm create`)
- ENTONCES la VM DEBE crearse con Rocky Linux 10, 2 vCPU, 4 GB RAM y 20 GB disco
- Y la VM DEBE tener conectividad a Internet para pulling de imágenes Docker

#### Escenario: VM ID libre

- DADO un VM ID propuesto (ej: 206)
- CUANDO se verifica disponibilidad en `pve-desa` vía `qm list`
- ENTONCES el script DEBE confirmar que el ID no está en uso antes de crear

#### Escenario: Usuario de acceso

- DADO la VM creada con Rocky Linux 10
- CUANDO se completa el primer boot con cloud-init
- ENTONCES el usuario `infra` DEBE existir con contraseña configurada
- Y DEBE permitir acceso SSH para los pasos de bootstrap

### Requisito: Despliegue del stack Redmine

El sistema DEBE desplegar `redmine:6.1`, `postgres:16` y `nginx` mediante
Docker Compose.

#### Escenario: Stack completo funcionando

- DADO la VM con Docker Engine instalado (repos oficiales Rocky Linux)
- CUANDO se ejecuta `docker compose up -d`
- ENTONCES los tres servicios DEBEN estar en estado running
- Y Redmine DEBE ser accesible en `http://localhost:3000` dentro de la VM

#### Escenario: Persistencia de datos

- DADO el stack desplegado
- CUANDO se reinicia la VM o los contenedores
- ENTONCES las bases de datos y archivos subidos DEBEN persistir en volúmenes
  Docker

### Requisito: SSL/TLS con nginx

El sistema DEBE exponer Redmine vía HTTPS mediante nginx reverse proxy.

#### Escenario: HTTPS accesible

- DADO nginx configurado como reverse proxy hacia `redmine:3000`
- CUANDO se accede a `https://redmine.gidas.local` desde la red interna
- ENTONCES nginx DEBE responder con certificado válido (auto-firmado)

#### Escenario: Redirección HTTP a HTTPS

- DADO nginx configurado con SSL
- CUANDO se accede vía HTTP (puerto 80)
- ENTONCES nginx DEBE redirigir a HTTPS

### Requisito: Autenticación local

Redmine DEBE usar autenticación local como mecanismo primario.

#### Escenario: Login de administrador

- DADO Redmine desplegado con configuración por defecto
- CUANDO se accede a `/login` con credenciales admin por defecto
- ENTONCES el sistema DEBE permitir el ingreso
- Y DEBE solicitar cambio de contraseña en el primer login

#### Escenario: Creación de usuario local

- DADO un administrador autenticado en la interfaz de Redmine
- CUANDO crea un nuevo usuario con email y contraseña
- ENTONCES el usuario DEBE poder iniciar sesión con sus credenciales

### Requisito: Backup de PostgreSQL

El sistema DEBE ejecutar backups diarios de la base PostgreSQL.

#### Escenario: Dump programado

- DADO un cron configurado en la VM host
- CUANDO se ejecuta diariamente el script de backup
- ENTONCES `pg_dump` DEBE generar un archivo `.sql.gz` en `/var/backups/redmine/`

#### Escenario: Restauración desde dump

- DADO un dump `.sql.gz` existente
- CUANDO se ejecuta el script de restauración
- ENTONCES PostgreSQL DEBE restaurar la base sin errores

### Requisito: Backup de archivos

El sistema DEBE respaldar los volúmenes de archivos de Redmine (files,
plugins, themes).

#### Escenario: Backup de volúmenes

- DADO la VM con volúmenes Docker de Redmine
- CUANDO se ejecuta el script de backup
- ENTONCES los directorios DEBEN comprimirse en un tarball
- Y el tarball DEBE copiarse al storage interno de backups

### Requisito: Scripts reproducibles

Los scripts de deploy DEBEN ser ejecutables en orden numerado desde una VM
limpia.

#### Escenario: Deploy desde cero

- DADO una VM Rocky Linux 10 recién creada sin Docker
- CUANDO se ejecutan los scripts en orden (`01-provision-vm.sh`,
  `02-bootstrap-vm.sh`, `03-deploy-stack.sh`, `04-configure-ssl.sh`)
- ENTONCES el stack DEBE quedar operativo sin intervención manual

#### Escenario: Rollback completo

- DADO el stack desplegado
- CUANDO se ejecuta `docker compose down` y se destruye la VM (`qm stop && qm
  destroy`)
- ENTONCES el script DEBE liberar el VM ID y los recursos asociados
- Y los backups previos DEBEN estar disponibles para restauración futura
