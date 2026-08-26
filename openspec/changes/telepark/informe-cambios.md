# Informe de Cambios — VM de Desarrollo Telepark

**Feature branch**: `feat/herramientas-pendientes`
**Versión**: VM `telepark-dev` (Rocky Linux 10.2, Docker CE 29.7.2, Portainer 2.39.6)
**Fecha**: 2026-08-26
**Estado**: ✅ OPERATIVO — VM desplegada, dominio AD, Docker/Cockpit/Portainer, DNS, y sincronización de usuarios

---

## 1. Resumen Ejecutivo

Se creó y disponibilizó la **VM de desarrollo del proyecto Telepark** (`telepark-dev`, VMID 213 en `pve-desa01`), un entorno Rocky Linux 10 para que todos los integrantes del grupo trabajen de forma colaborativa. Incluye Docker + Compose, Cockpit y Portainer, con autenticación contra Active Directory (`GDC01.local`) y escalado a root (sudo) para el grupo `PROY-Telepark`.

Además se crearon dos usuarios de dominio (`telepark` y `pnepotti`), se corrigió el acceso SSH por contraseña, el acceso a Docker sin sudo, el timeout de seguridad de Portainer, y un problema **preexistente** de resolución DNS (`*.gidas.local` no resolvía desde las workstations).

| Concepto | Valor |
|----------|-------|
| VM | `telepark-dev` (VMID 213, nodo `pve-desa01`) |
| SO | Rocky Linux 10.2 (`6.12.0-211.49.1`) |
| Recursos | 4 vCPU (`x86-64-v3`) / 4 GB RAM / 40 GB disco |
| IP | `192.168.1.48/24` — hostname `telepark-dev.gidas.local` |
| Docker | CE 29.7.2 + Compose v5.5.0 |
| Cockpit | 356.2 (`https://192.168.1.48:9090`) |
| Portainer | CE 2.39.6 (`https://192.168.1.48:9443`) |
| Dominio | AD `GDC01.local` (SSSD, kerberos-member) |
| Sudo | grupo `proy-telepark@GDC01.local` → `ALL=(ALL:ALL) ALL` |

---

## 2. Cambios Realizados

### 2.1 Identidad (Active Directory)

| # | Cambio | Detalle |
|---|--------|---------|
| 1 | Usuario `telepark` creado | OU `Coordinadores`, grupos `G-Coordinadores` + `PROY-Telepark`, email `telepark@frlp.utn.edu.ar`, Title `coordinador`, Department `Telepark` |
| 2 | Usuario `pnepotti` (Paulo Nepotti) creado | OU `Coordinadores`, grupo `PROY-Telepark`, email `pnepotti@frlp.utn.edu.ar`; email de bienvenida enviado |
| 3 | Verificado acceso del grupo | Los 3 miembros originales (`penalvam`, `ebernalcustodio`, `telepark`) ya estaban en `PROY-Telepark` |

> **Nota**: la doc `identity-management/docs/identity/ad/usuarios.md` indica `mpenalva` para Mirta Peñalva; el sAMAccountName **real** es `penalvam`.

### 2.2 VM `telepark-dev`

| # | Cambio | Detalle |
|---|--------|---------|
| 4 | Clonado template `rocky-10-standard` (qemu 9000) | full clone → VMID 213, resize disco 40 GB, cloud-init (IP estática + SSH key root) |
| 5 | Fix CPU `x86-64-v3` | Rocky 10 exige v3; el template no lo tenía → kernel panic al bootear. `qm set --cpu x86-64-v3` (requiere stop completo) |
| 6 | Docker CE + Compose | repo `centos` (el único con paquetes `el10`); reboot para cargar `xt_addrtype` del kernel nuevo |
| 7 | Cockpit | habilitado (`cockpit.socket`, puerto 9090) |
| 8 | Portainer CE | contenedor `portainer/portainer-ce:lts`, puertos 9443/8000 |

### 2.3 Red y DNS

| # | Cambio | Detalle |
|---|--------|---------|
| 9 | IP estática | `192.168.1.48/24`, gw `192.168.1.1` (vía cloud-init) |
| 10 | DNS en MikroTik | `telepark-dev.gidas.local` → 192.168.1.48 |
| 11 | **Forwarder condicional en el DC** | `gidas.local` → MikroTik (`Add-DnsServerConditionalForwarderZone`). **Arregla un problema preexistente**: `*.gidas.local` (glpi, portal, redmine…) no resolvía desde las workstations porque el DC (DNS primario) devolvía `NXDOMAIN` |

### 2.4 Acceso y permisos

| # | Cambio | Detalle |
|---|--------|---------|
| 12 | Unión a AD | `realm join GDC01.local` (SSSD, `ldap_id_mapping = True`) |
| 13 | Sudo para Telepark | `/etc/sudoers.d/telepark-dev` → `%proy-telepark@GDC01.local ALL=(ALL:ALL) ALL` |
| 14 | **Fix SSH por contraseña** | cloud-init dejó `PasswordAuthentication no`; habilitado en `50-cloud-init.conf`. El login exige nombre completo (`usuario@gdc01.local`) |
| 15 | **Fix Docker sin sudo** | el socket pasó al grupo AD vía override `docker.socket` (`SocketGroup=proy-telepark@GDC01.local`). El grupo anidado (local→AD) no lo resuelve SSSD |
| 16 | Usuario local `infra` | `wheel` (sudo) + `docker`, password `hlvs.2025` — administración |
| 17 | **Fix timeout de Portainer** | admin inicializado vía API (`POST /api/users/admin/init` con `X-Setup-Token`) |
| 18 | **Sincronización AD→Portainer** | script `identity-management/scripts/sync-portainer-users.sh` — crea cuentas locales en Portainer espejando `PROY-Telepark` (Portainer CE no tiene LDAP/AD) |
| 19 | **Cambio password Portainer** | password de las cuentas locales actualizada a `Telepark.2026!` (el `PUT /api/users/{id}/passwd` dio "Invalid new password"; se resolvió con delete+recreate) |
| 20 | **Admin en Cockpit para dominio** | usuarios del grupo Telepark agregados al grupo local `wheel` (Cockpit gating del modo privilegiado por `wheel`, no por sudoers) |
| 21 | **Acceso vía Portal GIDAS** | agregadas las cards "Cockpit Telepark" y "Portainer Telepark" a `portal-gidas/config.yaml` (grupo `PROY-Telepark`, proxeadas `proxy: true`) |
| 22 | **Proxy WebSocket en el portal** | `portal-gidas/app/routers/proxy.py` reescrito para soportar WebSockets (ruta `WebSocket` + reenvío bidireccional con `websockets`) |
| 23 | **nginx con WebSocket** | nginx del CT 208 actualizado (`proxy_http_version 1.1` + headers `Upgrade`/`Connection`) para permitir el handshake WebSocket al portal |
| 24 | **Terminal SSH (ttyd)** | desplegado `ttyd` en la VM (puerto 7681, HTTPS con cert autofirmado, login AD vía PAM/SSSD) + card "SSH Telepark" en el portal |

---

## 3. Modelo de Acceso

| Recurso | Usuarios de dominio (grupo Telepark) |
|---------|--------------------------------------|
| SSH | ✅ con `usuario@gdc01.local` + password de dominio |
| Sudo (root) | ✅ vía grupo `proy-telepark` |
| Docker CLI | ✅ sin sudo (socket del grupo AD) |
| Cockpit | ✅ con credenciales de dominio (PAM/SSSD) + admin vía `wheel` |
| Portainer | ⚠️ cuentas locales sincronizadas (password inicial `Telepark.2026!`), **no** la de dominio (limitación CE) |

### Usuarios del grupo Telepark

| Usuario | AD | Portainer (local) |
|---------|----|-------------------|
| Mirta Peñalva | `penalvam` | `penalvam` (standard) |
| Emanuel Bernal | `ebernalcustodio` | `ebernalcustodio` (standard) |
| Paulo Nepotti | `pnepotti` | `pnepotti` (standard) |
| Cuenta funcional | `telepark` | `telepark` (standard) |
| — | — | `admin` (admin) |

### Acceso vía Portal GIDAS

Se agregaron dos cards al Portal GIDAS (visible solo para el grupo `PROY-Telepark`), **proxeadas** a través del portal para que funcionen también en acceso remoto (el nombre local `telepark-dev.gidas.local` no resuelve fuera de la LAN):

| Card | Backend interno (vía proxy) |
|------|-----------------------------|
| **Cockpit Telepark** | `https://192.168.1.48:9090` (`/proxy/telepark-cockpit/`) |
| **Portainer Telepark** | `https://192.168.1.48:9443` (`/proxy/telepark-portainer/`) |
| **SSH Telepark** | `https://192.168.1.48:7681` (`/proxy/telepark-ssh/`) — terminal web (ttyd) con login AD |

Para que funcionara el proxy con Cockpit/Portainer se hicieron **tres cambios**:

1. **Proxy del portal con soporte WebSocket** (`portal-gidas/app/routers/proxy.py`): el proxy original (httpx) no soportaba WebSockets, imprescindibles para Cockpit (terminal) y Portainer (logs/consola). Se agregó una ruta `WebSocket` que reenvía bidireccionalmente (texto + binario) con la librería `websockets`.
2. **nginx del CT 208**: el proxy frontal usaba HTTP/1.0 y no reenviaba los headers `Upgrade`/`Connection`, rompiendo el handshake WebSocket. Se agregó `proxy_http_version 1.1` + `proxy_set_header Upgrade`/`Connection` (map `$connection_upgrade`) + timeouts largos.
3. **Config**: las cards pasaron de `proxy: false` (enlace directo) a `proxy: true` con la IP interna.

El RBAC sigue funcionando: la card solo aparece si el usuario pertenece a `PROY-Telepark`, y el proxy valida la sesión (cookie JWT) también en la conexión WebSocket.

---

## 4. Sincronización AD → Portainer

Portainer CE **no soporta autenticación LDAP/AD** (es de Business Edition). Para dar acceso a los usuarios de dominio se usa un script de sincronización que espeja la membresía del grupo AD en cuentas locales de Portainer.

**Script**: `identity-management/scripts/sync-portainer-users.sh` (idempotente, Bash + `curl` + `python3` para JSON).

```bash
./sync-portainer-users.sh              # crea los usuarios del grupo AD que falten
./sync-portainer-users.sh --dry-run    # previsualiza sin ejecutar
./sync-portainer-users.sh --remove     # además deshabilita los que ya no están en AD
```

Flujo: lee `getent group proy-telepark@GDC01.local` → loguea en Portainer (admin) → `POST /api/users` para los faltantes (password inicial configurable, rol `2`). No modifica usuarios existentes (preserva cambios de password). Para ejecutarlo periódicamente, agregar a cron en la VM.

---

## 5. Lecciones Aprendidas

| # | Problema | Causa | Solución |
|---|----------|-------|----------|
| 1 | Kernel panic al bootear Rocky 10 | CPU `x86-64-v3` requerida; template sin `--cpu` | `qm set --cpu x86-64-v3` (stop, no reset) |
| 2 | `docker.service` falla (`addrtype`) | kernel viejo tras update | reboot |
| 3 | Docker CE no en Rocky 10 | repo `rhel` llega a `el9` | repo `centos` |
| 4 | SSH sin password para dominio | cloud-init `PasswordAuthentication no` | habilitar |
| 5 | `*.gidas.local` no resolvía | DC no conoce la zona (NXDOMAIN) | forwarder condicional → MikroTik |
| 6 | `docker` permission denied para AD | grupo anidado no lo resuelve SSSD; socket activation | override `docker.socket` |
| 7 | Portainer `/timeout` | admin no creado en 5 min | init vía API + setup token |

---

## 6. Pendientes

- 🔲 **FreeIPA**: crear el usuario `telepark` en FreeIPA (`IPA.GDC01.LOCAL`, `.118`). **Bloqueado** — password de admin perdida (`PREAUTH_FAILED`), `infra` es solo user SSH local, y el reset del Directory Manager (hash PBKDF2) no prosperó. FreeIPA no lo usa nada en la infra; recomendado dejarlo fuera o reinstalarlo limpio.
- 🔲 **Firewall**: la VM no tiene `firewalld`. Evaluar reglas mínimas (SSH 22, Cockpit 9090, Portainer 9443) si se expone fuera de la LAN de confianza.
- 🔲 **Cron del sync**: agendar `sync-portainer-users.sh` para que la membresía de Portainer siga a AD automáticamente.

---

## 7. Archivos Relevantes

| Archivo | Descripción |
|---------|-------------|
| `docs/telepark/avance.md` | Informe de avance de la VM |
| `docs/telepark/manuales/manual-desarrollador.md` | Manual para desarrolladores |
| `identity-management/scripts/sync-portainer-users.sh` | Sync AD → Portainer |
| `/etc/sudoers.d/telepark-dev` (en la VM) | Sudo para el grupo Telepark |
| `/etc/systemd/system/docker.socket.d/override.conf` (en la VM) | Docker socket para el grupo AD |
