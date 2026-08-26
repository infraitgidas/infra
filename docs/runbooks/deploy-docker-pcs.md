# Runbook: Despliegue de Docker Desktop en las PCs de dominio

> **Ámbito**: PCs Windows 10/11 del dominio GDC01.local
> **Herramientas**: `pcs/docker/install-docker.ps1`, `pcs/docker/enable-winrm.ps1`, `pcs/docker/deploy-docker.sh`
> **Última revisión**: 2026-08

---

## 1. Objetivo

Instalar y configurar Docker Desktop en las PCs de escritorio del dominio GDC01,
de forma automatizada y desde el host de gestión Linux, dejando Docker utilizable
por cualquier usuario de dominio común (sin privilegios de administrador).

El despliegue consta de tres etapas orquestadas (`preflight` → `deploy` → `verify`)
que se ejecutan por WinRM (NTLM, puerto 5985) contra cada PC.

---

## 2. Alcance

| PC        | IP            | Incluida |
|-----------|---------------|----------|
| direccion | 192.168.1.30  | Sí       |
| isla4     | 192.168.1.50  | Sí       |
| isla1     | 192.168.1.51  | Sí       |
| isla2     | 192.168.1.52  | Sí       |
| isla3     | 192.168.1.53  | Sí       |
| gidas-37709 (infra) | 192.168.1.54 | **No** (sin credenciales admin documentadas; excluir siempre) |

La lista por defecto del orquestador ya contiene solo las 5 PCs incluidas.
Para un subconjunto: `PCS="192.168.1.30 192.168.1.51" ./deploy-docker.sh preflight`
o pasando las IPs como argumentos posicionales.

---

## 3. Prerrequisitos

### 3.1 Hardware / SO

- Windows 10 21H2 o superior (build ≥ 19044). El instalador lo valida y aborta si no.
- **Virtualización habilitada en BIOS/UEFI** (VT-x / AMD-V con SLAT).
  Si está deshabilitada, Docker Desktop no podrá levantar su VM WSL2.
- Al menos 10 GB libres en `C:`.

### 3.2 Licenciamiento

Docker Desktop es gratuito para organizaciones con **menos de 250 empleados**
y menos de **USD 10M de facturación anual**. Verificar que GIDAS sigue dentro
de esos límites antes de desplegar; en caso contrario, gestionar suscripción
pagada (Docker Pro/Team/Business).

### 3.3 WinRM habilitado en cada PC

WinRM **no viene habilitado** en los clientes de dominio (solo en el DC).
Habilitarlo de una de estas dos formas:

**Opción A — manual (una vez por PC)**: ejecutar interactivamente en PowerShell
elevado en la PC:

```powershell
.\enable-winrm.ps1 -AllowRemoteLocalAdmin
```

> El switch `-AllowRemoteLocalAdmin` setea `LocalAccountTokenFilterPolicy=1`:
> sin eso, las sesiones remotas con cuentas admin **locales** reciben un token
> filtrado por UAC y todo paso elevado (DISM, instalador, grupos) falla con
> acceso denegado. No hace falta si se opera con una cuenta de dominio admin.
> Rollback: setear el valor en `0`.

**Opción B — GPO (recomendada para escala)**:

> **GPO ya creada y vinculada** (2026-08-26): `Enable-WinRM-ForManagement`
> ID: `11dbb8db-deec-4ecc-b795-33a17b09f7c2`. Configura WinRM, firewall
> HTTP-In LocalSubnet, y `LocalAccountTokenFilterPolicy=1`. Las PCs la
> aplicarán en el próximo ciclo de GPO o tras reinicio.

```text
Configuración del equipo > Plantillas administrativas > Componentes de Windows
  > Administración remota de Windows (WinRM) > Servicio de WinRM
     - "Permitir administración remota del servidor a través de WinRM": Habilitada
       (filtro IPv4: solo la subred local, p. ej. 192.168.1.0/24)
Firewall de Windows Defender > Reglas de entrada
     - "Windows Remote Management (HTTP-In)" (TCP 5985): Habilitada
       Ámbito > Direcciones remotas: Subred local (LocalSubnet)
Servicio: "Administración remota de Windows" -> Automático
```

Verificación rápida desde el host de gestión: el `preflight` del orquestador
reporta `UNREACHABLE` si el puerto 5985 no responde.

---

## 4. Carga de credenciales

Las credenciales admin de las PCs **nunca van hardcodeadas ni en texto plano
en tickets/docs**. Dos formas válidas, en este orden de prioridad:

**Opción 1 — Variables de entorno** (útil para pruebas puntuales):

```bash
export WINRM_USER='<usuario admin>'
export WINRM_PASS='<contraseña>'
# La contraseña queda solo en memoria del proceso; no pegarla en historial ni scripts.
```

**Opción 2 — SOPS** (recomendada). El orquestador descifra automáticamente
`secrets/network.yaml` buscando el mapeo `windows_pcs:`:

```yaml
windows_pcs:
  admin_user: <usuario admin>
  admin_pass: <contraseña>
```

Si esa clave aún no existe, agregarla cifrada:

```bash
sops secrets/network.yaml   # agregar bloque windows_pcs con admin_user/admin_pass
```

Requiere la identidad age configurada localmente (`SOPS_AGE_KEY_FILE` o
`~/.config/sops/age/keys.txt`). Si falta algo, el script falla con un mensaje
indicando exactamente qué exportar o qué clave crear.

---

## 5. Procedimiento paso a paso

Desde el host de gestión Linux, dentro del repo:

```bash
cd pcs/docker

# 1) Diagnóstico inicial (solo lectura): alcanzabilidad, SO/build, dominio,
#    presencia de Docker, miembros de docker-users, espacio libre en C:
./deploy-docker.sh preflight

# 2) Despliegue (instala features WSL2, Docker Desktop, grupo docker-users):
./deploy-docker.sh deploy

# 2-alt) Con reinicio automático de las PCs que lo requieran:
./deploy-docker.sh deploy --auto-reboot

# 3) Verificación post-despliegue:
./deploy-docker.sh verify
```

Comportamiento ante reinicio: si el instalador termina con estado
`REBOOT_REQUIRED` (típico tras habilitar Hyper-V/VirtualMachinePlatform), sin
`--auto-reboot` la PC queda marcada `NEEDS_REBOOT` en el resumen: reiniciarla
manualmente y volver a correr `deploy` (es idempotente). Con `--auto-reboot`,
el orquestador reinicia, espera hasta 10 minutos a que WinRM vuelva, y reejecuta
el instalador una vez más.

Otros flags útiles: `--dry-run` (muestra el plan sin hacer cambios), 
`--concurrency N` (paralelismo, default 5).

---

## 6. Verificación final como usuario de dominio común

En una PC cualquiera, iniciar sesión con una cuenta de dominio **sin
privilegios de admin** y ejecutar:

```powershell
docker --version
docker run hello-world
```

Esperado: `hello-world` corre sin errores de permisos (el usuario accede al
daemon vía membresía en `docker-users`). Cerrar sesión y reingresar si el
grupo recién se asignó (la membresía se evalúa al logon).

---

## 7. ADVERTENCIA DE SEGURIDAD

> **Pertenecer a `docker-users` equivale, en la práctica, a control root del
> host**: montar el raíz del disco en un contenedor (`-v C:\:C:\vm`) permite
> leer/modificar cualquier archivo, crear usuarios, etc.
>
> Dar acceso a `GDC01\Domain Users` (todas las cuentas del dominio) es una
> **decisión de riesgo aceptado**: cualquier credencial de dominio comprometida
> compromete también la PC donde inicie sesión.
>
> Alternativa más segura: crear un grupo de AD dedicado (p. ej. `GG-DockerUsers`)
> y usar ese grupo en el instalador (`$domainGroup = 'GDC01\GG-DockerUsers'`),
> otorgando membresía solo a quienes necesiten contenedores. Documentar la
> decisión en `docs/decisions/`.

---

## 8. Rollback

Por PC, con sesión admin:

```powershell
# 1) Quitar membresía del grupo local
Remove-LocalGroupMember -Group 'docker-users' -Member 'GDC01\Domain Users'

# 2) Desinstalar Docker Desktop (Configuración > Aplicaciones, o:)
Get-Package -Name 'Docker Desktop' | Uninstall-Package
#    (o winget uninstall Docker.DockerDesktop)

# 3) Opcional: revertir features de Windows
dism.exe /Online /Disable-Feature /FeatureName:Microsoft-Windows-Subsystem-Linux
dism.exe /Online /Disable-Feature /FeatureName:VirtualMachinePlatform

# 4) Opcional (si se habilitó solo para esto): cerrar WinRM
Disable-PSRemoting -Force
Stop-Service WinRM; Set-Service WinRM -StartupType Disabled
```

---

## 9. Troubleshooting

| Síntoma | Causa probable | Acción |
|---|---|---|
| Instalador reporta `3010` / `REBOOT_REQUIRED` | Features de Windows recién habilitadas | Reiniciar y reejecutar `deploy` (o usar `--auto-reboot`) |
| `[WARN] Firmware virtualization not reported enabled` y Docker no arranca su VM | VT-x/AMD-V deshabilitada en BIOS | Habilitar virtualización en firmware y reiniciar |
| `UNREACHABLE` en preflight | WinRM deshabilitado o puerto 5985 bloqueado | Ejecutar `enable-winrm.ps1` en la PC o aplicar la GPO; verificar regla HTTP-In con ámbito LocalSubnet |
| Tareas admin fallan con acceso denegado por WinRM | Token filtrado por UAC al usar cuenta admin **local** | Reejecutar `enable-winrm.ps1 -AllowRemoteLocalAdmin` en la PC, o usar cuenta de **dominio** con privilegios admin |
| `ERROR: failed to decrypt ...` | Identidad age ausente o clave SOPS incorrecta | Revisar `SOPS_AGE_KEY_FILE` / `~/.config/sops/age/keys.txt`; alternativamente exportar `WINRM_USER`/`WINRM_PASS` |

---

## Referencias

- Script instalador (idempotente): `pcs/docker/install-docker.ps1`
- Bootstrap WinRM: `pcs/docker/enable-winrm.ps1`
- Orquestador: `pcs/docker/deploy-docker.sh`
- Inventario de PCs: `mikrotik/mac-pc.md`
