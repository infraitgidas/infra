# Manual del Desarrollador — VM Telepark

> **VM**: `telepark-dev` (192.168.1.48)
> **Hostname**: `telepark-dev.gidas.local`
> **Proyecto**: Telepark
> **Última actualización**: 2026-08-26

Este manual explica cómo usar la máquina de desarrollo del proyecto Telepark: qué herramientas tenés disponibles, qué es cada una, y cómo acceder a ellas (SSH y Portainer).

---

## 1. ¿Qué es esta VM?

Es el **entorno de desarrollo compartido** del proyecto Telepark: una máquina Rocky Linux 10 donde todos los integrantes del grupo desarrollan y prueban los servicios del proyecto.

Todos los integrantes del grupo Telepark tienen acceso con su **usuario de dominio** (el mismo con el que te logueás en tu PC) y pueden escalar a **root** con `sudo`.

---

## 2. Herramientas: qué son y cómo acceder

### 2.1 Tabla de acceso rápido

| Herramienta | ¿Qué es? | ¿Cómo accedo? |
|-------------|----------|---------------|
| **SSH** | Conexión segura a la terminal de la VM | `ssh <usuario>@gdc01.local@192.168.1.48` |
| **SSH remoto** | Conectarte desde fuera de la LAN | launcher del Portal GIDAS (ver §3.2) |
| **Docker** | Motor de contenedores | Por terminal (SSH) |
| **Docker Compose** | Orquestador de stacks multi-contenedor | Por terminal (`docker compose`) |
| **Portainer** | Consola web para gestionar **Docker** | `https://192.168.1.48:9443` |
| **Revisar mi app** | Ver un despliegue en el navegador (cualquier puerto) | `https://<portal>/port/<puerto>/` (ver §6.4) |

### 2.2 ¿Qué es cada herramienta?

**🔗 SSH (Secure Shell)**
Protocolo para conectarte de forma **segura y cifrada** a la terminal de la VM desde tu PC. Es como "teletransportarte" a la máquina: escribís comandos como si estuvieras sentado frente a ella. Es la forma principal de trabajar (editar archivos, correr Docker, ver logs).

**🐳 Docker**
Motor de **contenedores**. Un contenedor es como una mini-máquina virtual liviana que empaqueta una aplicación y todas sus dependencias, de modo que corra **igual en cualquier lado**. Docker es el motor que crea y ejecuta esos contenedores. (No lo confundas con Portainer: Docker es el *motor*, Portainer es el *panel de control*.)

**🧩 Docker Compose**
Herramienta para definir y levantar aplicaciones **multi-contenedor**. Con un archivo `docker-compose.yml` describís todos los servicios (web, base de datos, caché…) y sus relaciones, y con **un solo comando** (`docker compose up`) levantás todo el stack.

**🎛️ Portainer**
Interfaz **web** para gestionar **Docker**: ver contenedores, deployar stacks, revisar logs, crear volúmenes y redes. Es el "panel de control" de Docker — la alternativa gráfica a la línea de comandos `docker`. (No usa tu password de dominio; tenés una cuenta local, ver sección 5.)

---

## 3. Cómo entrar por SSH

### 3.1 Conexión

Usás tu **usuario de dominio**. Como la VM usa nombres totalmente calificados, el usuario lleva el sufijo `@gdc01.local`:

```bash
ssh <usuario>@gdc01.local@192.168.1.48
# ejemplos:
ssh penalvam@gdc01.local@192.168.1.48
ssh ebernalcustodio@gdc01.local@192.168.1.48
ssh pnepotti@gdc01.local@192.168.1.48
```

> ⚠️ El nombre corto (`ssh penalvam@192.168.1.48`) **no funciona**; siempre con `@gdc01.local`.
> En el primer login se crea automáticamente tu carpeta `/home/<usuario>@gdc01.local`.

### 3.2 SSH remoto (fuera de la LAN)

Si estás **fuera de la oficina** (en casa), la VM no es alcanzable directamente por IP. Usá el **Portal GIDAS**:

1. Entrá al portal (`https://<portal>.trycloudflare.com` o `portal.gidas.local`).
2. Clic en **"SSH Telepark (Linux/macOS)"** o **"(Windows)"** → se descarga un launcher.
3. Ejecutalo:
   ```bash
   bash ssh-telepark.sh     # Linux/macOS
   ssh-telepark.cmd         # Windows
   ```
4. El launcher descarga `cloudflared` la primera vez (si no lo tenés), te pide tu usuario de dominio, y conecta por SSH vía el **túnel de Cloudflare**.

> La conexión usa `cloudflared access ssh` como proxy — no necesitás configurar nada más. El usuario se ingresa igual que en LAN (`usuario@gdc01.local`).

### 3.3 Hacerse root

Todos los miembros del grupo Telepark tienen sudo total:

```bash
sudo -i          # o sudo <comando>
```

### 3.4 Usuarios con acceso

| Nombre | Usuario |
|--------|---------|
| Mirta Peñalva | `penalvam` |
| Emanuel Bernal | `ebernalcustodio` |
| Paulo Nepotti | `pnepotti` |
| Cuenta funcional Telepark | `telepark` |

> **Admin local**: usuario `infra` (password `hlvs.2025`), con sudo total (`wheel`) y acceso a Docker. Para administración del sistema.

---

## 4. Consolas web (Portainer)

| Herramienta | URL | Para qué |
|-------------|-----|----------|
| **Portainer** | `https://192.168.1.48:9443` | Gestionar **Docker** (contenedores, imágenes, volúmenes, stacks) |

> 💡 **También desde el Portal GIDAS**: si tenés acceso al portal (`portal.gidas.local`), vas a ver las cards **"Portainer Telepark"** y **"SSH Telepark"** — aparecen solo para los del grupo Telepark.

> **Portainer**: cada usuario del grupo Telepark tiene una **cuenta local** (Portainer CE no usa el password de dominio). Password inicial: `Telepark.2026!` — cambiala al primer ingreso.
> Son certificados autofirmados → el navegador va a mostrar advertencia de seguridad la primera vez; aceptala.

---

## 5. Usar Portainer

1. Entrá a `https://192.168.1.48:9443`.
2. Logeate con **tu cuenta local** de Portainer (mismo nombre que tu usuario de dominio, ej. `pnepotti`).
   - Password inicial: `Telepark.2026!`. Cambiala en **My account → Change password** la primera vez.
3. La primera vez que entres, elegí **"Get Started" → Local** para conectar el Docker de esta VM.

> Si no tenés cuenta en Portainer, avisale al administrador (que corre el script `sync-portainer-users.sh` para espejar el grupo AD).

Con Portainer podés:

- Ver el estado de todos los contenedores.
- **Deployar stacks** (equivalente a `docker compose` pero desde la web).
- Ver logs y entrar a la consola de un contenedor.
- Crear volúmenes y redes.

> Portainer ya está corriendo como contenedor (`portainer/portainer-ce:lts`) con los puertos `9443` (HTTPS) y `8000` (edge agent).

---

## 6. Trabajar con Docker (por terminal)

### 6.1 Comandos básicos

```bash
docker ps                 # contenedores corriendo
docker ps -a              # todos (incluidos los detenidos)
docker images             # imágenes descargadas
docker logs <contenedor>  # ver logs
docker exec -it <contenedor> bash   # entrar a un contenedor
docker volume ls          # volúmenes
```

### 6.2 Docker Compose

La VM ya trae Compose v2 (`docker compose`, sin guion):

```bash
# dentro de la carpeta del proyecto (donde está docker-compose.yml)
docker compose up -d          # levantar el stack en background
docker compose down           # bajar el stack
docker compose ps             # estado del stack
docker compose logs -f        # ver logs en tiempo real
docker compose pull && docker compose up -d   # actualizar imágenes
```

### 6.3 Ejemplo completo: levantar un stack

```bash
mkdir -p /srv/mi-app && cd /srv/mi-app
cat > docker-compose.yml <<'YML'
services:
  web:
    image: nginx:alpine
    ports:
      - "8080:80"
YML
docker compose up -d
curl http://localhost:8080
```

### 6.4 Revisar tu app en el navegador (cualquier puerto)

Cuando levantes una app (por ejemplo en el puerto `8080`), podés revisarla desde
tu navegador **sin estar en la red de la empresa**. El Portal GIDAS proxea
cualquier puerto de la VM de desarrollo:

```
https://<url-del-portal>/port/8080/
```

Reglas:
- Reemplazá `8080` por el puerto de tu app (por ejemplo `/port/3000/` para un
  frontend en React).
- Tenés que **estar logueado** en el Portal y pertenecer al grupo
  `PROY-Telepark`.
- El puerto debe estar escuchando en la VM (`0.0.0.0` o `localhost`); verificá
  con `curl http://localhost:8080`.
- Si la app usa WebSockets (hot-reload, chat, etc.) también funciona.

Esto es ideal para mostrar avances o revisar un despliegue en una reunión.

---

## 7. Buenas prácticas

- **No trabajes como root por defecto**: usá tu usuario de dominio y `sudo` cuando lo necesites.
- **Datos persistentes con volúmenes**: no guardes datos importantes dentro del contenedor; usá volúmenes (`docker volume`) o bind mounts (`/srv/...`).
- **Nombra los contenedores/stacks** para saber de quién es cada cosa.
- **Actualizá periódicamente**: `sudo dnf upgrade -y` y `docker compose pull` en tus stacks.
- La VM **no tiene firewall activo**: no expongas servicios sensibles sin avisar.

---

## 8. Troubleshooting rápido

| Problema | Qué hacer |
|----------|-----------|
| No puedo entrar por SSH | Usá el formato completo `ssh <usuario>@gdc01.local@192.168.1.48` (el nombre corto no anda) y verificá que la VM responde (`ping 192.168.1.48`) |
| `sudo` me pide password y no me deja | Tu usuario debe estar en el grupo `PROY-Telepark` de AD. Verificá con `id` |
| `docker` dice "permission denied" | El socket pertenece al grupo `proy-telepark@GDC01.local`. Si estás en ese grupo, salí y volvé a entrar (los grupos se cargan al login). Verificá con `id` que aparezca `proy-telepark` |
| Un puerto ya está en uso | `sudo ss -tlnp | grep <puerto>` para ver quién lo usa |
| No resuelve `telepark-dev.gidas.local` | Está en el DNS del MikroTik. Si tu DNS primario no es `192.168.1.1` o `192.168.1.117`, usá la IP directa |
| Portainer no carga | `sudo systemctl status docker` y `docker ps --filter name=portainer` |
