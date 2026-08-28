# Informe de Cambios — Docker Desktop en PCs GIDAS

**Feature branch**: `feat/docker-pcs-gidas`
**Fecha**: 2026-08-26
**Estado**: PARCIAL — 1/5 PCs operativa, 1 pendiente, 2 bloqueadas BIOS, 1 inaccesible

---

## 1. Resumen Ejecutivo

Instalación de Docker Desktop (WSL2 backend) en las 5 PCs del dominio GDC01 del grupo GIDAS, con permisos de Domain Users y documentación operativa.

| Concepto | Valor |
|----------|-------|
| Total PCs objetivo | 5 (.30, .50, .51, .52, .53) |
| Completadas | 1 (.51 GIDAS-002) |
| Pendientes | 1 (.50 gidas-37710) |
| Bloqueadas (BIOS) | 2 (.52, .53) |
| Inaccesibles | 1 (.30) |
| Docker Desktop | v29.7.2 (instalador) / v27.5.1 (pre-existente en .51) |
| Backend | WSL2 |
| Permisos | `GDC01\Domain Users` → grupo local `docker-users` |

---

## 2. Estado por PC

| IP | Hostname | SSH | WinRM | Virtualización | Docker | Estado |
|---|---|---|---|---|---|---|
| 192.168.1.51 | GIDAS-002 | ✅ | ✅ (manual) | ✅ | v27.5.1 + hello-world ✅ | **COMPLETO** |
| 192.168.1.50 | gidas-37710 | ✅ | ✅ (manual) | ✅ | v29.7.2 instalado, daemon no arranca tras reboot | **PENDIENTE** |
| 192.168.1.52 | gidas-desktop-854 | ✅ | ✅ (GPO) | ❌ BIOS OFF | No instalado | **BLOCKED** |
| 192.168.1.53 | GIDAS-003 | ✅ | ✅ (GPO) | ❌ BIOS OFF | No instalado | **BLOCKED** |
| 192.168.1.30 | — | ❌ | ❌ | N/D | N/D | **INACCESIBLE** |

### 192.168.1.51 — GIDAS-002 ✅ COMPLETO

- Docker Desktop v27.5.1 pre-existente, confirmado funcional con `hello-world`
- WSL2 kernel actualizado a v2.7.12 (`wsl --update`)
- WSL2 features habilitadas: `Microsoft-Windows-Subsystem-Linux` + `VirtualMachinePlatform`
- `GDC01\Domain Users` agregado al grupo local `docker-users`
- WinRM habilitado manualmente vía SSH (`winrm quickconfig -force` + `Enable-PSRemoting`)

### 192.168.1.50 — gidas-37710 ⚠️ PENDIENTE

- Docker Desktop v29.7.2 instalado silenciosamente (`DockerDesktopInstaller.exe install --quiet`)
- WSL2 features habilitadas (`dism /online /enable-feature`)
- WSL2 kernel update **falló** (`Error catastrófico`) — pendiente resolución
- `GDC01\Domain Users` agregado al grupo local `docker-users`
- Reboot ejecutado; PC no responde (puede estar en Windows Update / BitLocker)
- **Acción requerida**: Verificar que .50 vuelva online; si está en pantalla de inicio, abrir Docker Desktop una vez para que arranque el daemon WSL2

### 192.168.1.52 — gidas-desktop-854 ❌ BLOCKED

- WinRM habilitado vía GPO `Enable-WinRM-ForManagement`
- SSH funcional
- **Virtualización (VT-x/AMD-V) deshabilitada en BIOS** — Docker Desktop no puede ejecutar WSL2 sin ella
- **Acción requerida**: Habilitar VT-x/AMD-V en BIOS (F2/DEL → Advanced → CPU → Virtualization → Enabled), reboot

### 192.168.1.53 — GIDAS-003 ❌ BLOCKED

- WinRM habilitado vía GPO `Enable-WinRM-ForManagement`
- SSH funcional
- **Virtualización (VT-x/AMD-V) deshabilitada en BIOS**
- **Acción requerida**: Igual que .52

### 192.168.1.30 — ❌ INACCESIBLE

- Sin SSH, sin WinRM, sin ping (ICMP bloqueado por firewall de Windows)
- No se puede gestionar remotamente
- **Acción requerida**: Habilitar SSH o WinRM físicamente, o vía GPO si la PC se conecta a la red

---

## 3. GPO Creada

| Campo | Valor |
|-------|-------|
| Nombre | `Enable-WinRM-ForManagement` |
| ID | `11dbb8db-deec-4ecc-b795-33a17b09f7c2` |
| Ubicación | `CN=Policies,CN=System,DC=GDC01,DC=local` |
| Enlace | Dominio raíz (`DC=GDC01,DC=local`) |
| Server | DC1-GIDAS (192.168.1.117) |

**Contenido de la GPO:**

| Setting | Valor |
|---------|-------|
| WinRM Service\Startup type | Automatic |
| WinRM Service\Allow remote server management | Enabled |
| Windows Firewall\Firewall Rules\WinRM-In-TCP (HTTP) | Enabled, LocalSubnet |
| Registry: `LocalAccountTokenFilterPolicy` | DWORD 1 |

**Aplicación:**
- .52 y .53: WinRM habilitado vía GPO (`gpupdate /force`)
- .51 y .50: WinRM habilitado manualmente vía SSH (`winrm quickconfig -force` + `Enable-PSRemoting`)

---

## 4. Problemas Encontrados

### 4.1 Virtualización deshabilitada en BIOS (.52, .53)

Docker Desktop con WSL2 requiere VT-x (Intel) o AMD-V (AMD) habilitado en BIOS. Sin esto, WSL2 no puede crear máquinas virtuales y Docker Desktop falla al iniciar.

**Solución**: Acceder físicamente a cada PC → BIOS → Advanced/CPU → Virtualization → Enabled → reboot.

### 4.2 WSL2 kernel update falló en .50

El comando `wsl --update` produjo `Error catastrófico`. Las features de WSL2 (`Microsoft-Windows-Subsystem-Linux` + `VirtualMachinePlatform`) fueron habilitadas correctamente, pero el kernel no se actualizó.

**Solución alternativa**: Descargar el kernel manualmente desde https://aka.ms/wsl2kernel o ejecutar Windows Update.

### 4.3 .50 no responde tras reboot

La PC fue reiniciada con `Stop-Computer -Force` y no volvió a estar reachable por SSH después de 10+ minutos. Puede estar en pantalla de Windows Update, BitLocker, o pantalla de inicio de sesión.

**Solución**: Verificar físicamente; si está en Windows Update, esperar a que complete.

### 4.4 shutdown /r /t 5 /f /c falla por conflicto de parámetros

El comando `shutdown /r /t 5 /c "mensaje"` falla cuando se ejecuta vía SSH porque `/c` entra en conflicto con el `/c` de cmd.exe.

**Solución alternativa**: `powershell -NoProfile -Command "Stop-Computer -Force"`

### 4.5 Ping (ICMP) bloqueado en todas las PCs

El firewall de Windows bloquea ICMP en todas las PCs del dominio. Ping no es un indicador confiable de disponibilidad.

**Solución**: Usar `nc -zw3 <ip> 22` o `sshpass` para verificar conectividad real.

### 4.6 Docker Desktop daemon no arranca en .50

Docker Desktop fue instalado pero el daemon no arranca porque el kernel WSL2 no se actualizó correctamente (ver 4.2).

**Solución**: Actualizar kernel WSL2 manualmente, o abrir Docker Desktop una vez con sesión interactiva para que complete la configuración.

---

## 5. Archivos Creados

| Archivo | Líneas | Propósito |
|---------|--------|-----------|
| `pcs/docker/install-docker.ps1` | ~200 | Script idempotente de instalación de Docker Desktop (WSL2 backend, preflight checks, docker-users group) |
| `pcs/docker/enable-winrm.ps1` | ~100 | Bootstrap WinRM con `-AllowRemoteLocalAdmin` para `LocalAccountTokenFilterPolicy` |
| `pcs/docker/deploy-docker.sh` | ~300 | Orquestador Linux (preflight/deploy/verify vía WinRM NTLM, concurrente, dry-run) |
| `docs/runbooks/deploy-docker-pcs.md` | ~250 | Runbook en español (prerrequisitos, GPO, credenciales, rollback, advertencias de seguridad) |

---

## 6. Credenciales y Acceso

| Componente | Credenciales | Ubicación |
|------------|-------------|-----------|
| SSH PCs (.50-.53) | `Administrator` / `gidas_admin` (mismo password) | `mikrotik/mac-pc.md` (texto plano, no commiteado) |
| WinRM DC (192.168.1.117) | `GDC01\Administrator` | `secrets/identity.yaml` (SOPS encriptado) |
| GitHub | `infraitgidas` / token SOPS | `~/.git-credentials` |

**⚠️ SEGURIDAD**: Las credenciales SSH de las PCs están en `mikrotik/mac-pc.md` en texto plano. Se recomienda migrarlas a SOPS (`secrets/network.yaml`) con una sección `windows_pcs:`.

---

## 7. Siguientes Pasos

1. **Verificar estado de .50** — Si no responde, intervención física
2. **Habilitar BIOS virtualización en .52 y .53** — VT-x/AMD-V
3. **Instalar Docker en .52 y .53** una vez habilitada la virtualización (mismo patrón que .51)
4. **Habilitar acceso remoto en .30** — SSH o WinRM físicamente
5. **Migrar credenciales SSH a SOPS** — Sección `windows_pcs:` en `secrets/network.yaml`
6. **Archivar cambio** una completadas todas las PCs

---

## 8. Commits

| Hash | Mensaje |
|------|---------|
| `be623ae` | feat(pcs): crear scripts de instalación Docker Desktop para PCs GIDAS |
| `a0c5a14` | feat(pcs): agregar orquestador deploy-docker.sh y runbook en español |
| `38d499a` | feat(pcs): habilitar WinRM en .51/.52/.53/.50 via SSH |
| `07107ac` | docs(pcs): documentar estado del despliegue Docker tras ejecución real |
| `33eb09c` | docs(pcs): documentar estado del despliegue Docker tras ejecución real |

**Rama**: `feat/docker-pcs-gidas` (pusheada a origin)
