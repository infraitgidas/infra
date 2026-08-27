# Informe de Avance — VM de Desarrollo Telepark

> **Proyecto**: Entorno de desarrollo Telepark
> **Rama**: `feat/herramientas-pendientes`
> **VM**: `telepark-dev` (VMID 213)
> **Fecha**: 2026-08-26
> **Estado**: ✅ OPERATIVO — VM desplegada, software instalado, unida a AD, DNS configurado

---

## 1. Resumen Ejecutivo

Se creó y disponibilizó la **VM de desarrollo para el proyecto Telepark**, un entorno Rocky Linux 10 destinado a que todos los integrantes del grupo desarrollen de forma colaborativa. La VM provee Docker + Docker Compose (despliegue de stacks) y Portainer (gestión de contenedores), con acceso autenticado contra Active Directory y escalado a root (sudo) para todos los miembros del grupo `PROY-Telepark`.

| Componente | Estado | Detalle |
|------------|--------|---------|
| **VM** | ✅ Operativa | VMID 213, nodo `pve-desa01`, Rocky Linux 10.2 |
| **Red** | ✅ IP fija | `192.168.1.48/24` — hostname `telepark-dev.gidas.local` |
| **DNS** | ✅ MikroTik | `telepark-dev.gidas.local` → 192.168.1.48 |
| **Docker** | ✅ Operativo | Docker CE 29.7.2 + Compose v5.5.0 |
| **Portainer** | ✅ Operativo | `https://192.168.1.48:9443` (CE, tag `lts`) |
| **Dominio AD** | ✅ Unida | `GDC01.local` (SSSD, kerberos-member) |
| **Sudo Telepark** | ✅ Configurado | grupo `PROY-Telepark` → `ALL=(ALL:ALL) ALL` |

---

## 2. Infraestructura

```
┌─ VM 213 (pve-desa01 / telepark-dev) ─────────────────────────────┐
│  Rocky Linux 10.2 — 4 vCPU — 4 GB RAM — 40 GB — 192.168.1.48     │
│  CPU: x86-64-v3   Hostname: telepark-dev.gidas.local              │
│                                                                    │
│  ┌─ docker.service ─────────────┐  ┌─ cockpit.socket ──────────┐  │
│  │ Docker CE 29.7.2             │  │ Cockpit 356.2  (puerto     │  │
│  │ Compose v5.5.0               │  │  9090)  —  ws/bridge/system│  │
│  └───────────────┬──────────────┘  └────────────────────────────┘  │
│  ┌───────────────▼──────────────┐                                  │
│  │ portainer (contenedor)       │  ┌─ 9443 (HTTPS) ───────────┐  │
│  │ portainer/portainer-ce:lts   │──┤ 8000 (edge agent)         │  │
│  │ vol: portainer_data          │  └───────────────────────────┘  │
│  │ -v /var/run/docker.sock      │                                  │
│  └──────────────────────────────┘                                  │
└────────────────────────────────────────────────────────────────────┘
         │                              │
   SSSD (AD GDC01.local)          vmbr0 (192.168.1.0/24)
         │                              │
   DC1-GIDAS (192.168.1.117)      MikroTik (192.168.1.1) — DNS estático
```

### Especificaciones de la VM

| Atributo | Valor |
|----------|-------|
| VMID | `213` |
| Nombre | `telepark-dev` |
| Nodo | `pve-desa01` (192.168.1.11) |
| SO | Rocky Linux 10.2 (`6.12.0-211.49.1.el10_2`) |
| CPU | `x86-64-v3`, 4 vCPU (1 socket) |
| RAM | 4 GB (balloon, mínimo 1 GB) |
| Disco | 40 GB — `local-lvm` (scsi0, virtio-scsi) |
| Red | `virtio`, bridge `vmbr0`, IP estática `192.168.1.48/24`, gw `192.168.1.1` |
| DNS | `192.168.1.117` (DC) + `192.168.1.1` (MikroTik) |
| Hostname / FQDN | `telepark-dev.gidas.local` |
| Origen | clon del template `rocky-10-standard` (qemu 9000) |

---

## 3. Software instalado

| Paquete | Versión | Notas |
|---------|---------|-------|
| `docker-ce` | 29.7.2 | Repo Docker CE (baseurl `centos`) |
| `docker-ce-cli` | 29.7.2 | |
| `docker-compose-plugin` | 5.5.0 | Compose v2 (`docker compose`) |
| `containerd.io` | 2.3.3 | |
| `docker-buildx-plugin` | 0.36.1 | |
| `cockpit-ws` / `cockpit-bridge` / `cockpit-system` | 356.2 | Vienen en el template Rocky 10 |
| `portainer-ce` | tag `lts` | Contenedor Docker, `restart=always` |
| `code-server` | 4.135.0 | RPM de Coder. IDE en el navegador, launcher on-demand `/usr/local/bin/code-on` |

> **Nota sobre el repo de Docker**: Docker CE **no publica paquetes para RHEL/Rocky 10** en el repo `rhel`. Se usa el repo `centos` (`https://download.docker.com/linux/centos/$releasever/...`), que sí tiene `el10`. Este es el mismo patrón del host FreeIPA (`192.168.1.118`).

---

## 4. Acceso y permisos

### Dominio Active Directory

- Unida a `GDC01.local` mediante `realm join` (SSSD, tipo `kerberos-member`).
- `ldap_id_mapping = True` (el AD no tiene atributos POSIX — RFC2307).
- `access_provider = ad` → todos los usuarios del dominio pueden autenticar por SSH.
- Home automático por `oddjob-mkhomedir` (`/home/%u@%d`).
- SSH sin restricciones (`AllowUsers`/`AllowGroups` no definidos).

### Sudo — grupo Telepark

Archivo `/etc/sudoers.d/telepark-dev`:

```
%proy-telepark@GDC01.local ALL=(ALL:ALL) ALL
```

Todos los miembros del grupo AD `PROY-Telepark` tienen sudo total (equivalente a hacerse root).

### Usuarios con acceso (grupo `PROY-Telepark`)

| Usuario | sAMAccountName | Rol |
|---------|----------------|-----|
| Mirta Peñalva | `penalvam` | Coordinadora Telepark |
| Emanuel Bernal | `ebernalcustodio` | Integrante |
| Paulo Nepotti | `pnepotti` | Coordinador Telepark |
| Telepark (cuenta funcional) | `telepark` | Coordinador (Title) |

> ⚠️ La documentación `identity-management/docs/identity/ad/usuarios.md` indica erróneamente que Mirta Peñalva es `mpenalva`. El sAMAccountName **real** es `penalvam` (verificado en AD).

### URLs de acceso

| Servicio | URL |
|----------|-----|
| SSH | `ssh <usuario>@gdc01.local@192.168.1.48` (ej. `ssh penalvam@gdc01.local@192.168.1.48`) |
| Portainer | `https://192.168.1.48:9443` (edge agent: `8000`) |

> **SSH por password**: el cloud-init del template dejaba `PasswordAuthentication no`; se habilitó para que los usuarios de dominio puedan entrar con su contraseña. El login exige el nombre completo (`usuario@gdc01.local`); el nombre corto no resuelve (`use_fully_qualified_names = True`).

> **SSH remoto (fuera de la LAN)**: vía el Portal GIDAS. Las cards **"SSH Telepark (Linux/macOS)"** y **"(Windows)"** descargan un launcher que conecta por el **túnel de Cloudflare** (`cloudflared access ssh` como ProxyCommand, con auto-descarga de `cloudflared`). El túnel SSH corre como servicio `ssh-tunnel` en el CT 208, y su URL dinámica se captura en `/opt/portal-gidas/ssh-tunnel-url.txt` (el launcher la lee al vuelo).

> **Revisar despliegues en el navegador (cualquier puerto)**: el Portal GIDAS proxea puertos de la VM vía la ruta `/port/{puerto}/`. Por ejemplo, una app en el puerto `8080` se ve en `https://<url-del-portal>/port/8080/`. Requiere login en el Portal y pertenecer a `PROY-Telepark`. Soporta HTTP y WebSockets. Ver manual del desarrollador §6.4.

> **Editor en el navegador (VS Code remoto)**: `code-server` 4.135.0 instalado en la VM + launcher on-demand `/usr/local/bin/code-on`. Cada dev arranca su editor (`code-on <puerto>`) y lo abre vía `https://<portal>/port/<puerto>/`. Corre como el propio usuario, con `--auth none` (autentica el portal). Ver manual del desarrollador §7.

### Acceso a Docker (sin sudo)

El socket `/var/run/docker.sock` pertenece al grupo AD `proy-telepark@GDC01.local` (vía override de `docker.socket`), por lo que los usuarios del grupo Telepark ejecutan `docker` **directamente**, sin `sudo`:

```ini
# /etc/systemd/system/docker.socket.d/override.conf
[Socket]
SocketGroup=proy-telepark@GDC01.local
```

> Docker usa **socket activation** (`docker.socket` de systemd), así que el grupo del socket lo controla la unit de systemd, **no** el `group` de `daemon.json` (que se ignora en este modo).

### Usuario local de administración

| Usuario | Password | Grupos | Uso |
|---------|----------|--------|-----|
| `infra` | `hlvs.2025` | `wheel` (sudo) + `docker` | Administración local — full root con `sudo -i` |

### Portainer (acceso y cuentas)

| Campo | Valor |
|-------|-------|
| URL | `https://192.168.1.48:9443` |
| Admin | `admin` / `Hlvs.2025!hlvs` |

> **Portainer CE no tiene integración AD/LDAP** (es de Business Edition). Por eso el acceso de los usuarios de dominio se resuelve con **cuentas locales espejadas del grupo AD**, sincronizadas por el script `identity-management/scripts/sync-portainer-users.sh` (crea/deshabilita cuentas según la membresía de `PROY-Telepark`).

**Cuentas locales de Portainer** (sincronizadas con `PROY-Telepark`, password inicial `Telepark.2026!`):

| Usuario | Rol |
|---------|-----|
| `penalvam` | standard (2) |
| `ebernalcustodio` | standard (2) |
| `pnepotti` | standard (2) |
| `telepark` | standard (2) |
| `admin` | admin (1) |

> El admin se inicializó vía API para resolver el **timeout de seguridad** de Portainer (ocurre si no se crea el admin en los 5 minutos del primer arranque). La password de Portainer exige **12+ caracteres** (aplica también a usuarios comunes).

---

## 5. Procedimiento de creación (reproducible)

### 5.1 Clonado y recursos

```bash
# Desde un nodo Proxmox (pve-desa01)
qm clone 9000 213 --name telepark-dev --full 1
qm resize 213 scsi0 40G
qm set 213 --cores 4 --memory 4096 --balloon 1024
qm set 213 --cpu x86-64-v3          # ¡crítico! Rocky 10 exige x86-64-v3
```

### 5.2 Cloud-init (IP estática + acceso SSH)

```bash
qm set 213 \
  --ipconfig0 "ip=192.168.1.48/24,gw=192.168.1.1" \
  --nameserver "192.168.1.117 192.168.1.1" \
  --searchdomain "gidas.local" \
  --ciuser root \
  --sshkeys /tmp/ema.pub            # archivo con la clave pública
qm start 213
```

> `--sshkeys` espera una **ruta de archivo**, no la clave inline.

### 5.3 Software

```bash
# Docker CE (repo centos, el único con paquetes el10)
cat > /etc/yum.repos.d/docker-ce.repo <<'REPO'
[docker-ce-stable]
name=Docker CE Stable - $basearch
baseurl=https://download.docker.com/linux/centos/$releasever/$basearch/stable
enabled=1
gpgcheck=1
gpgkey=https://download.docker.com/linux/centos/gpg
REPO
dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker

# Cockpit (ya viene en el template)
systemctl enable --now cockpit.socket

# Portainer
docker volume create portainer_data
docker run -d --name portainer --restart=always \
  -p 8000:8000 -p 9443:9443 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v portainer_data:/data \
  portainer/portainer-ce:lts

# code-server (IDE en el navegador)
curl -fsSL -o /tmp/code-server.rpm https://github.com/coder/code-server/releases/download/v4.135.0/code-server-4.135.0-amd64.rpm
rpm -i /tmp/code-server.rpm
install -m 0755 scripts/telepark/code-on.sh /usr/local/bin/code-on
```

### 5.4 Dominio AD + sudo

```bash
dnf install -y realmd oddjob oddjob-mkhomedir sssd sssd-ad sssd-tools adcli samba-common-tools krb5-workstation
echo '<password-administrator>' | realm join GDC01.local -U Administrator

cat > /etc/sudoers.d/telepark-dev <<'SUDO'
%proy-telepark@GDC01.local ALL=(ALL:ALL) ALL
SUDO
chmod 440 /etc/sudoers.d/telepark-dev
visudo -c
```

### 5.5 DNS (MikroTik)

```bash
# RouterOS (SSH infra@192.168.1.1)
/ip dns static add name="telepark-dev.gidas.local" address=192.168.1.48 ttl=1d comment="Telepark Dev VM"
```

> **Forwarder condicional en el DC** (necesario para que las workstations resuelvan `*.gidas.local`): el DC (`192.168.1.117`) es el DNS primario de los clientes, pero no conocía la zona `gidas.local` (que vive en el MikroTik). Se agregó:
>
> ```powershell
> # En el DC (GDC01), PowerShell:
> Add-DnsServerConditionalForwarderZone -Name "gidas.local" -MasterServers 192.168.1.1
> ```
>
> Con esto, workstation → DC → MikroTik → resuelve. Arregla `telepark-dev` **y** todos los `.gidas.local` existentes (glpi, portal, redmine, etc.) que antes no resolvían.

### 5.6 Sincronización de usuarios AD → Portainer

Como Portainer CE no soporta AD/LDAP, los usuarios de dominio se mapean a **cuentas locales** con el script `identity-management/scripts/sync-portainer-users.sh` (idempotente, corre en el host de Portainer):

```bash
# sincronizar (crea los usuarios del grupo AD que falten)
./sync-portainer-users.sh

# previsualizar sin ejecutar
./sync-portainer-users.sh --dry-run

# además deshabilitar usuarios que ya no están en el grupo AD
./sync-portainer-users.sh --remove
```

El script: lee los miembros de `PROY-Telepark` (vía `getent group`/SSSD) → loguea en Portainer → crea cuentas locales con password inicial (configurable, `DEFAULT_PASSWORD`) y rol `2` (standard). No toca las cuentas existentes (preserva cambios de password).

---

## 6. Gotchas / lecciones aprendidas

| # | Problema | Causa | Solución |
|---|----------|-------|----------|
| 1 | **Kernel panic al bootear** (`Attempted to kill init!`, `Fatal glibc error: CPU does not support x86-64-v3`) | Rocky 10 exige CPU `x86-64-v3`; el template `rocky-10-standard` no tenía `--cpu` seteado (default `kvm64` = v1) | `qm set --cpu x86-64-v3` (requiere **STOP completo**, no `reset`) |
| 2 | `docker.service` falla (`addrtype ... missing kernel module`) | El `dnf` actualizó el kernel pero la VM seguía con el kernel viejo | **Reboot** para cargar el kernel nuevo con `xt_addrtype` |
| 3 | Docker CE no disponible en Rocky 10 | El repo `rhel` de Docker solo llega a `el9` | Usar repo `centos` (tiene `el10`) |
| 4 | `qm set --cpu` no aplicaba | El QEMU en ejecución no re-leyó el tipo de CPU con `reset` | `qm stop` → `qm set --cpu` → `qm start` |
| 5 | Usuarios de dominio no podían entrar por SSH con contraseña | cloud-init dejó `PasswordAuthentication no` en `50-cloud-init.conf` | `PasswordAuthentication yes` + `restart sshd` |
| 6 | `*.gidas.local` no resolvía desde las workstations | El DC (DNS primario) devolvía `NXDOMAIN` para la zona `gidas.local` (solo estaba en el MikroTik) y los resolvers no fallbackean | Forwarder condicional `gidas.local` → MikroTik en el DNS del DC |
| 7 | Usuarios de dominio con `permission denied` al ejecutar `docker` | El grupo anidado (grupo local `docker` → grupo AD) **no lo resuelve** SSSD/nsswitch; y Docker usa socket activation | Override `docker.socket` con `SocketGroup=proy-telepark@GDC01.local` (el `group` de `daemon.json` se ignora) |
| 8 | Portainer redirige a `/timeout` | El admin no se creó en los 5 minutos del primer arranque (timeout de seguridad) | Inicializar admin vía API con el `X-Setup-Token` (`POST /api/users/admin/init`) |

> **Sin firewall**: el template Rocky 10 no incluye `firewalld`. Para un entorno de desarrollo en la LAN de confianza es aceptable, pero **no exponer** esta VM a la LAN de invitados sin agregar reglas.

---

## 7. Pendientes

- 🔲 **FreeIPA**: crear el usuario `telepark` en FreeIPA (realm `IPA.GDC01.LOCAL`, host `192.168.1.118`). **Bloqueado** — la password de admin está perdida (`PREAUTH_FAILED`), `infra` es solo un user SSH local (no principal IPA), y el reset del Directory Manager (hash PBKDF2 no recuperable) no prosperó por las vías probadas (`pwdhash -s` falló el bind, texto plano rechazado por 389-DS). FreeIPA **no lo usa nada** en la infra (sin trust AD, SSSD solo con `ipa.gdc01.local`); recomendado dejarlo fuera o reinstalarlo limpio.
- 🔲 **Emanuel Bernal** (`ebernalcustodio`): no tiene `Title` seteado en AD (no afecta el acceso).
- 🔲 **Firewall**: evaluar si se agrega `firewalld` con reglas mínimas (SSH 22, Portainer 9443).
- ✅ **Cockpit fuera del portal**: los desarrolladores no necesitan Cockpit, así que se quitó la card del portal (ya desplegada). Cockpit **se mantiene activo en la VM** (`https://192.168.1.48:9090`) para uso local/administrativo; no se deshabilita.
