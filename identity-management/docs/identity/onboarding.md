# Alta de Usuario — Onboarding

> Procedimiento para crear un nuevo usuario con acceso a la infraestructura del Grupo Gidas.

## Requisitos Previos

- Credenciales de administrador del dominio AD (almacenadas en `secrets/proxmox.yaml` encriptado con SOPS)
- Acceso SSH a DC1-GIDAS (192.168.1.117) o RDP
- Acceso SSH a FreeIPA (192.168.1.118)

## Paso a Paso

### 1. Crear usuario en AD

Determinar la OU según el rol del usuario:

| Rol | OU Path |
|-----|---------|
| Director/Vicedirector | `OU=Direccion,DC=GDC01,DC=local` |
| Coordinador | `OU=Coordinadores,OU=Direccion,DC=GDC01,DC=local` |
| Becario/Estudiante | `OU=Becarios,DC=GDC01,DC=local` |

```powershell
# Conectar a DC1-GIDAS via SSH o RDP
ssh Administrator@192.168.1.117

# Crear usuario — ajustar OU y sAMAccountName según el caso
New-ADUser -Name "Juan Pérez" `
    -GivenName "Juan" `
    -Surname "Pérez" `
    -SamAccountName "jperez" `
    -UserPrincipalName "jperez@GDC01.local" `
    -Path "OU=Coordinadores,OU=Direccion,DC=GDC01,DC=local" `
    -AccountPassword (ConvertTo-SecureString "TempPass2026!" -AsPlainText -Force) `
    -Enabled $true `
    -ChangePasswordAtLogon $true

# Verificar que se creó
Get-ADUser jperez
```

### 2. Asignar grupos

Según el rol y proyecto del usuario:

```powershell
# Grupo por rol (siempre)
Add-ADGroupMember -Identity "G-Coordinadores" -Members "jperez"

# Proyecto (si aplica)
Add-ADGroupMember -Identity "PROY-Telepark" -Members "jperez"
```

**Regla**: Un usuario puede pertenecer a múltiples grupos `PROY-*`. Siempre debe pertenecer a al menos un grupo `G-*` (rol).

### 3. Forzar sincronización SSSD

```bash
ssh root@ipa.gidas.internal
# El trust AD-FreeIPA replica automáticamente
# Para forzar en un host específico:
ssh root@<host>
sss_cache -E  # limpiar y recargar caché
```

### 4. Verificar acceso

```bash
# Desde cualquier host Linux con SSSD
ssh jperez@sg-rojo.gidas.internal
# Debe obtener shell si el grupo G-Becarios/PROY-* tiene HBAC rule para ese host

id  # debe mostrar jperez y grupos AD

# Verificar que NO puede acceder a hosts no autorizados
ssh jperez@sg-azul.gidas.internal
# Debe fallar: "Access denied" (HBAC enforcement)
```

### 5. Configurar password inicial

El usuario debe cambiar su contraseña en el primer login. Si necesita hacerlo desde Linux:

```bash
# Cambiar contraseña AD desde Linux
kinit jperez@GIDAS.INTERNAL
passwd
```

O desde Windows: `Ctrl+Alt+Del → Change Password` en RDP.

## Convención de Nombres

| Campo | Formato | Ejemplo |
|-------|---------|---------|
| sAMAccountName | Primero + Inicial segundo + Apellido (lowercase) | `jperez`, `aalvarezf` |
| UPN | `sAMAccountName@gidas.internal` | `jperez@gidas.internal` |

## Checklist

- [ ] Usuario creado en AD (OU correcta según rol)
- [ ] Usuario habilitado
- [ ] Grupo de rol asignado (`G-*`)
- [ ] Grupo(s) de proyecto asignado (`PROY-*`) si aplica
- [ ] Grupo de servicio asignado (`SRV-*`) si aplica (ej: SRV-InfraITAdmin para sysadmin de INFRAiT)
- [ ] HBAC rule verifica acceso a hosts correctos
- [ ] Password inicial documentado
- [ ] Usuario informado del procedimiento de cambio de password

## Tiempo Estimado

10-15 minutos.

---

> 📄 Referencias: `ad/usuarios.md` (usuarios existentes), `ad/grupos.md` (definición de grupos)
