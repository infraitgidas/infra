# infra/redmine — Especificación

## Propósito

Desplegar y operar Redmine como gestor de proyectos open source en un LXC de
`pve-ad`, siguiendo el patrón Docker Compose del stack `sg-monitoring`.

## Requisitos

### Requisito: Infraestructura del contenedor

El sistema DEBE crear un contenedor LXC dedicado (CT ~206) en `pve-ad` con
2 vCPU, 4 GB RAM y 20 GB disco.

#### Escenario: Creación de CT desde scripts

- DADO `pve-ad` operativo con recursos disponibles
- CUANDO se ejecuta el script de creación del CT
- ENTONCES el CT DEBE crearse con Ubuntu LTS, 2 vCPU, 4 GB RAM y 20 GB disco
- Y el CT DEBE tener conectividad a Internet para pulling de imágenes Docker

#### Escenario: CT ID libre

- DADO un CT ID propuesto (ej: 206)
- CUANDO se verifica disponibilidad en `pve-ad`
- ENTONCES el script DEBE confirmar que el ID no está en uso antes de crear

### Requisito: Despliegue del stack Redmine

El sistema DEBE desplegar `redmine:6.1`, `postgres:16` y `nginx` mediante
Docker Compose.

#### Escenario: Stack completo funcionando

- DADO el CT creado con Docker Engine instalado
- CUANDO se ejecuta `docker compose up -d`
- ENTONCES los tres servicios DEBEN estar en estado running
- Y Redmine DEBE ser accesible en `http://localhost:3000` dentro del CT

#### Escenario: Persistencia de datos

- DADO el stack desplegado
- CUANDO se reinicia el CT o los contenedores
- ENTONCES las bases de datos y archivos subidos DEBEN persistir en volúmenes
  Docker

### Requisito: SSL/TLS con nginx

El sistema DEBE exponer Redmine vía HTTPS mediante nginx reverse proxy.

#### Escenario: HTTPS accesible

- DADO nginx configurado como reverse proxy hacia `redmine:3000`
- CUANDO se accede a `https://redmine.gidas.local` desde la red interna
- ENTONCES nginx DEBE responder con certificado válido (auto-firmado o
  Let's Encrypt)

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

- DADO un cron configurado en el CT host
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

- DADO el contenedor con volúmenes Docker de Redmine
- CUANDO se ejecuta el script de backup
- ENTONCES los directorios DEBEN comprimirse en un tarball
- Y el tarball DEBE copiarse al storage interno de backups

### Requisito: Scripts reproducibles

Los scripts de deploy DEBEN ser ejecutables en orden numerado desde un CT
limpio.

#### Escenario: Deploy desde cero

- DADO un CT Ubuntu LTS recién creado sin Docker
- CUANDO se ejecutan los scripts en orden (`00-env.sh`, `01-create-ct.sh`,
  `02-deploy-stack.sh`, `03-configure-ssl.sh`)
- ENTONCES el stack DEBE quedar operativo sin intervención manual

#### Escenario: Rollback completo

- DADO el stack desplegado
- CUANDO se ejecuta `docker compose down` y se destruye el CT
- ENTONCES el script DEBE liberar el CT ID y los recursos asociados
- Y los backups previos DEBEN estar disponibles para restauración futura
