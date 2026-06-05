# Procedimiento: Rotación de Password del Administrador de AD — F5.3

> **Objetivo**: Cambiar la contraseña del usuario `Administrator` del dominio
> `GDC01.local` en DC1-GIDAS (192.168.1.117) y almacenar la nueva credencial
> de forma segura en SOPS.
>
> **Frecuencia recomendada**: Cada 180 días o inmediatamente después de
> un incidente de seguridad.
>
> **Riesgo**: HIGH — si la rotación falla o la nueva contraseña se pierde,
> se pierde acceso administrativo a AD.

## Prerequisitos

- Acceso SSH a DC1-GIDAS con la contraseña actual del Administrator
- Acceso al repo de infraestructura con SOPS configurado
- Herramientas: `ssh`, `sops`, `git`

## Paso a Paso

### 1. Generar nueva contraseña

En una máquina Linux con acceso al repo:

```bash
# Generar contraseña segura de 24 caracteres
NEW_PASS=$(openssl rand -base64 18)
echo "Nueva contraseña AD Administrator: $NEW_PASS"

# Guardarla temporalmente (se borrará al final)
echo "$NEW_PASS" > /tmp/ad-admin-newpass.tmp
chmod 600 /tmp/ad-admin-newpass.tmp
```

> La contraseña generada contiene caracteres especiales compatibles con AD.
> Longitud: 24 caracteres (suficiente para cumplir políticas de complejidad).

### 2. Cambiar contraseña en AD

```powershell
# Conectar a DC1-GIDAS
ssh Administrator@192.168.1.117

# En PowerShell como Administrator:
$newPass = Read-Host -AsSecureString "Nueva contraseña"
net user Administrator $newPass /domain

# Verificar que el cambio fue exitoso
net user Administrator | findstr /i "Password"
```

Alternativa con `ssh` + comando directo:

```bash
ssh Administrator@192.168.1.117 \
  "net user Administrator $(cat /tmp/ad-admin-newpass.tmp) /domain"
```

### 3. Verificar nuevo acceso

```bash
# En una NUEVA sesión (no usar la sesión actual que puede tener cache)
ssh Administrator@192.168.1.117
# Usar la nueva contraseña → debe ser exitoso
```

### 4. Actualizar secrets en SOPS

```bash
# Ir al repo
cd /home/infra/infra

# Desencriptar secrets existente
sops secrets/proxmox.yaml

# Actualizar el password de AD Administrator
# Buscar el campo: ad.admin.password o equivalente
# Reemplazar con la nueva contraseña

# Si secrets/proxmox.yaml no existe, crearlo:
cat > /tmp/proxmox-secrets-template.yaml << 'EOF'
ad:
  domain: GDC01.local
  server: 192.168.1.117
  admin_user: Administrator
  admin_password: "${NEW_PASS}"
  netbios: GDC01

freeipa:
  server: 192.168.1.118
  domain: gdc01.local
  realm: IPA.GDC01.LOCAL

pve:
  host: pve-ad.local
  realm: gidas-ad
EOF

# Reemplazar placeholder y encriptar
sed "s|\${NEW_PASS}|$(cat /tmp/ad-admin-newpass.tmp)|g" \
  /tmp/proxmox-secrets-template.yaml | \
  sops -e /dev/stdin > secrets/proxmox.yaml
```

### 5. Verificar encriptación AC7

```bash
sops -d secrets/proxmox.yaml | grep admin_password
# Debe mostrar la nueva contraseña en texto plano
```

### 6. Commit y push

```bash
git add secrets/proxmox.yaml
git commit -m "chore: rotate AD Administrator password"
git push
```

### 7. Limpiar rastros

```bash
# Eliminar archivo temporal con la contraseña
shred -u /tmp/ad-admin-newpass.tmp

# Limpiar historial de bash
history -c
history -w
```

## Rollback

Si la rotación falla o la nueva contraseña se pierde:

```bash
# Restaurar secrets anterior desde git
git checkout HEAD~1 -- secrets/proxmox.yaml

# Obtener contraseña anterior
sops -d secrets/proxmox.yaml | grep admin_password

# Cambiar contraseña en AD de vuelta a la anterior
# (requiere otro administrador o consola local)
```

## Verificación Post-Rotación

- [ ] `ssh Administrator@192.168.1.117` funciona con nueva contraseña
- [ ] `sops -d secrets/proxmox.yaml` muestra nueva contraseña
- [ ] `ipa trust-find` desde FreeIPA sigue mostrando trust válido
- [ ] Login PVE con `gidas-ad\Administrator` sigue funcionando
- [ ] `getent passwd administrator` en hosts SSSD funciona
- [ ] Archivo temporal `/tmp/ad-admin-newpass.tmp` eliminado

## Notas

- El trust AD-FreeIPA NO depende del password del Administrator.
  El trust usa objetos de confianza Kerberos, no contraseñas de usuario.
- Si el password del Administrator cambia, los servicios que usan
  autenticación directa contra AD con esas credenciales deben actualizarse
  (ej: PVE realm, SOPS).
- La cuenta `Administrator` del dominio es diferente de la cuenta
  `Administrator` local de DC1-GIDAS (post-promoción, la cuenta de dominio
  es la autoritativa).

## Referencias

- Diseño: `identity-management/sdd/design.md §7, §8`
- Especificación: `identity-management/sdd/specs.md §R7, §AC7`
- Secrets: `secrets/proxmox.yaml` (encriptado con SOPS)
