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

Redmine DEBE usar autenticación local como mecanismo de respaldo.

#### Escenario: Login de administrador

- DADO Redmine desplegado con configuración por defecto
- CUANDO se accede a `/login` con credenciales admin
- ENTONCES el sistema DEBE permitir el ingreso
- Y DEBE solicitar cambio de contraseña en el primer login

### Requisito: Autenticación LDAP contra AD

Redmine DEBE autenticar usuarios contra Active Directory (GDC01.local) mediante LDAP.

#### Escenario: Configuración del servidor LDAP

- DADO un servidor AD accesible (192.168.1.117, puerto 389)
- CUANDO se configura un AuthSource LDAP en Redmine
- ENTONCES el servidor DEBE ser `192.168.1.117`
- Y DEBE usar filtro `(memberOf=CN=redmine,OU=Groups,DC=GDC01,DC=local)`
- Y DEBE tener `onthefly_register` habilitado

#### Escenario: Login con usuario AD

- DADO un usuario miembro del grupo `redmine` en AD
- CUANDO ingresa a Redmine con su usuario AD y contraseña
- ENTONCES el sistema DEBE autenticarlo
- Y DEBE crear su cuenta local automáticamente (onthefly_register)

#### Escenario: Restricción por grupo

- DADO un usuario NO miembro del grupo `redmine` en AD
- CUANDO intenta autenticarse en Redmine
- ENTONCES el sistema DEBE rechazar el acceso

### Requisito: Estructura de proyectos

Redmine DEBE contener los proyectos del laboratorio con roles y workflow definidos.

#### Escenario: Proyectos creados

- DADO Redmine operativo
- CUANDO se listan los proyectos
- ENTONCES DEBEN existir: Dirección, Administración, CAPNEE, INFRAiT, TELEPARK, GMET, GIS
- Y todos DEBEN ser privados

#### Escenario: Roles definidos

- DADO la administración de roles
- CUANDO se listan los roles disponibles
- ENTONCES DEBEN existir: Director, Coordinador, Graduado, Becario, Pasante, Externo
- Y Director DEBE tener permisos totales (9 permisos)
- Y Coordinador DEBE tener permisos de gestión (7 permisos)
- Y Becario DEBE tener permisos limitados (crear/ver issues)

#### Escenario: Workflow de issues

- DADO la configuración de workflow
- CUANDO se crea una issue
- ENTONCES los estados DEBEN ser: Nueva → Iniciada → En Revisión → En Espera → Terminada → Cerrada
- Y cada rol DEBE poder avanzar la issue hacia adelante en el flujo
- Y DEBE haber 126 transiciones configuradas

#### Escenario: Asignación de miembros

- DADO los grupos de AD
- CUANDO se asignan miembros a proyectos
- ENTONCES CAPNEE DEBE tener a aalvarezf (Coordinador), rcaceresp, jetcheverry, cvalero (Becarios)
- Y TELEPARK DEBE tener a mpenalva (Coordinador)
- Y GMET DEBE tener a zquiroz (Coordinador)
- Y GIS DEBE tener a jmarchesini (Coordinador)
- Y INFRAiT DEBE tener a errodriguez (Coordinador), rmonfroglio (Becario)
- Y Dirección y Administración DEBEN tener a Directores + Coordinadores

### Requisito: Correo electrónico SMTP

Redmine DEBE enviar notificaciones por correo electrónico vía SMTP Outlook.

#### Escenario: Configuración SMTP

- DADO el servidor SMTP de Outlook
- CUANDO se envía un correo desde Redmine
- ENTONCES DEBE usar `smtp.office365.com:587` con STARTTLS
- Y DEBE autenticar como `infrait@frlp.utn.edu.ar`
- Y DEBE poder enviar correos a cualquier destinatario

### Requisito: Notificaciones por evento

Redmine DEBE notificar a los usuarios según eventos en las issues.

#### Escenario: Nueva issue notifica a todos los miembros

- DADO una issue creada en un proyecto
- CUANDO se guarda la issue
- ENTONCES TODOS los miembros del proyecto DEBEN recibir un mail de notificación
- Y los usuarios DEBEN tener `mail_notification = "all"`

#### Escenario: Asignación notifica al usuario

- DADO una issue asignada a un usuario
- CUANDO se guarda la asignación
- ENTONCES el usuario asignado DEBE recibir notificación por mail
- Y el evento `issue_assigned_to_changed` DEBE estar en la lista de notificables

### Requisito: Dashboard público

Redmine DEBE exponer un dashboard público con el estado de las peticiones.

#### Escenario: Acceso al dashboard

- DADO un navegador sin autenticación
- CUANDO se accede a `http://redmine.gidas.local/dashboard/`
- ENTONCES DEBE mostrar una tabla con todas las issues
- Y DEBE tener código de colores por estado (azul, naranja, púrpura, gris, verde, oscuro)
- Y DEBE actualizarse automáticamente cada 10 segundos
- Y DEBE mostrar alertas visuales cuando ocurren cambios de estado
- Y DEBE permitir filtrar por proyecto, estado y búsqueda textual

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

### Requisito: Personalización de interfaz

Redmine DEBE tener una interfaz personalizada con la imagen institucional de GIDAS y UTN.

#### Escenario: Tema GIDAS seleccionable

- DADO el theme `gidas` instalado en `/usr/src/redmine/themes/gidas/`
- CUANDO se accede a Administración > Configuración > Pantalla > Tema
- ENTONCES DEBE aparecer "Gidas" como opción seleccionable
- Y DEBE aplicar colores rojos suaves (#c0392b, #e74c3c) en header, menú y botones
- Y DEBE mostrar el logo de GIDAS en el header

#### Escenario: Dashboard público con branding

- DADO nginx sirviendo el dashboard estático
- CUANDO se accede a `https://redmine.gidas.local/dashboard/`
- ENTONCES DEBE mostrar el header con el logo de GIDAS
- Y DEBE mostrar el footer con el logo de UTN La Plata
- Y DEBE tener una paleta de colores rojo suave

#### Escenario: Favicon institucional

- DADO nginx configurado para servir assets estáticos
- CUANDO se solicita `/favicon.ico`
- ENTONCES DEBE redirigir a `/theme-assets/favicon_utn.png`

#### Escenario: Resolución DNS

- DADO la entrada DNS configurada en MikroTik (192.168.1.1)
- CUANDO se consulta `redmine.gidas.local`
- ENTONCES DEBE resolver a `192.168.1.20`

### Requisito: Plugins instalados

Redmine DEBE tener plugins para tablero Kanban y gestión de presupuesto.

#### Escenario: Plugin Kanban instalado

- DADO el plugin `kanban` instalado en `/usr/src/redmine/plugins/kanban/`
- CUANDO se accede a Administración > Plugins
- ENTONCES DEBE listar "Kanban plugin v0.0.12"
- Y los proyectos DEBEN poder habilitar el módulo "Kanban" en sus módulos

#### Escenario: Plugin Budget instalado

- DADO el plugin `redmineup_projects_time_tracking` instalado
- CUANDO se accede a Administración > Plugins
- ENTONCES DEBE listar "Projects Time Tracking v0.8.0"
- Y DEBE mostrar métricas de presupuesto (CPI, EAC, Variance) en la lista de proyectos
- Y DEBE requerir migraciones de base de datos (6 migraciones ejecutadas)
