# Alta de Usuario — Onboarding

> Procedimiento para crear un nuevo usuario con acceso a la infraestructura del Grupo Gidas.

## Requisitos Previos

- Credenciales de administrador del dominio AD (almacenadas en `secrets/proxmox.yaml` encriptado con SOPS)
- Acceso SSH a VM-DC1 (192.168.1.117) o RDP
- Acceso SSH a FreeIPA (192.168.1.32)

## Paso a Paso

### 1. Crear usuario en AD

```powershell
# Conectar a VM-DC1 via SSH o RDP
ssh Administrator@192.168.1.117

# Crear usuario en la OU correspondiente
New-ADUser -Name "Juan Pérez" `
    -GivenName "Juan" `
    -Surname "Pérez" `
    -SamAccountName "jperez" `
    -UserPrincipalName "jperez@gidas.internal" `
    -Path "OU=Investigadores,OU=Users,DC=gidas,DC=internal" `
    -AccountPassword (ConvertTo-SecureString "TempPass2026!" -AsPlainText -Force) `
    -Enabled $true `
    -ChangePasswordAtLogon $true

# Verificar que se creó
Get-ADUser jperez
```

### 2. Asignar grupo

```powershell
# Según el subgrupo del investigador
Add-ADGroupMember -Identity "gidas-rojo" -Members "jperez"
```

### 3. Forzar sincronización SSSD

En FreeIPA, forzar la caché para que el usuario esté disponible:

```bash
ssh root@ipa.gidas.internal
# El trust AD-FreeIPA replica automáticamente. Forzar sync:
ipa sudocmd-find  # verificar que comandos están disponibles
# O esperar el intervalo de refresh (60 min)
# Para forzar en un host específico:
ssh root@<host>
sss_cache -E  # limpiar y recargar caché
```

### 4. Verificar acceso

```bash
# Desde cualquier host Linux con SSSD
ssh jperez@sg-rojo.gidas.internal
# Debe obtener shell si pertenece al grupo correcto
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
passwd  # o usar smbpasswd
```

O desde Windows: `Ctrl+Alt+Del → Change Password` en RDP.

## Checklist

- [ ] Usuario creado en AD
- [ ] Usuario habilitado
- [ ] Grupo asignado correctamente
- [ ] HBAC rule verifica acceso a hosts correctos
- [ ] Password inicial documentado
- [ ] Usuario informado del procedimiento de cambio de password

## Tiempo Estimado

10-15 minutos.
