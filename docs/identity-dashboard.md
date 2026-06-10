# identity-dashboard — AD + FreeIPA identity management

Herramienta unificada para gestionar usuarios en Active Directory (vía WinRM) y FreeIPA (vía SSH) simultáneamente.

## Stack

- **AD**: Windows Server (GDC01.local) — WinRM + PowerShell
- **FreeIPA**: ipa-gidas.gidas.internal — SSH + `ipa` CLI
- **Host**: identity-dashboard (192.168.1.124) — Rocky Linux 10, Python 3.12
- **Secrets**: SOPS-encrypted YAML + age key

## Instalación

```bash
# En el host identity-dashboard
cd /opt/identity-dashboard/identity-dashboard
pip install -r requirements.txt
pip install rich questionary     # para el TUI
```

## CLI

```bash
cd /opt/identity-dashboard/identity-dashboard

# Ver comandos disponibles
python3 -m app --help

# Listar usuarios
python3 -m app --secrets /opt/identity-dashboard/secrets/identity.yaml user list

# Crear usuario
python3 -m app --secrets /opt/identity-dashboard/secrets/identity.yaml \
    user create \
    --name "Juan Pérez" \
    --username jperez \
    --role becario \
    --proyecto InfraIT \
    --email juan.perez@example.com \
    --notify

# Ver detalle de usuario
python3 -m app --secrets /opt/identity-dashboard/secrets/identity.yaml user show jperez

# Deshabilitar / habilitar
python3 -m app --secrets /opt/identity-dashboard/secrets/identity.yaml user modify --username jperez --disable

# Eliminar usuario
python3 -m app --secrets /opt/identity-dashboard/secrets/identity.yaml user delete jperez
```

## TUI (interactivo)

```bash
cd /opt/identity-dashboard/identity-dashboard
python3 -m app.tui --secrets /opt/identity-dashboard/secrets/identity.yaml
```

### Opciones del menú

| Opción | Descripción |
|--------|-------------|
| 👤 Crear usuario | Formulario completo: nombre, username, email, rol, proyecto, grupos |
| 📋 Listar usuarios | Lista todos los usuarios de AD |
| 🔧 Habilitar / Deshabilitar | Activa o desactiva cuenta en AD + FreeIPA |
| ❌ Eliminar usuario | Elimina de AD + FreeIPA con doble confirmación |
| 🔑 Resetear password | Cambia password en AD + FreeIPA con rollback |
| 👥 Grupos | Agregar/quitar miembro, listar grupos (con filtro por prefijo) |
| 🛡️ HBAC | Testear acceso SSH, listar reglas HBAC |

### Flujo de creación de usuario (TUI)

1. **Nombre completo** y **username**
2. **Email del usuario** — se guarda en AD (`-EmailAddress`) y FreeIPA (`--email`)
3. **Rol** — director / vicedirector / coordinador / becario
4. **Proyecto** — selector con proyectos existentes en AD, o _"Crear proyecto nuevo"_
5. **Grupos adicionales** — checkbox con grupos reales de AD, o _"Crear grupo nuevo"_
6. **Resumen** con confirmación
7. El sistema:
   - Crea el usuario en AD + FreeIPA
   - Lo agrega al grupo default del rol y a los grupos seleccionados
   - Si un grupo no existe en AD, lo crea automáticamente
   - Envía email de bienvenida al usuario con su password
   - Envía notificación al admin (gidas@frlp.utn.edu.ar)

## Makefile

```bash
cd /opt/identity-dashboard
make help          # lista todos los targets
make tui           # lanza el TUI
make cli CMD="user list"    # corre un comando CLI
make ssh-tui       # TUI remoto (requiere TTY)
make sync          # git pull en el host
make deps          # instala dependencias Python
```

## Email

- **SMTP**: Outlook (smtp.office365.com:587) — `infrait@frlp.utn.edu.ar`
- **Welcome**: se envía al nuevo usuario con sus credenciales
- **Admin**: notificación a `gidas@frlp.utn.edu.ar`

## Secrets

Los secrets están en `secrets/identity.yaml` (SOPS + age).

```yaml
identity:
  ad:
    endpoint: http://192.168.1.117:5985/wsman
    username: GDC01\Administrator
    password: <sops>
  freeipa:
    host: ipa-gidas.gidas.internal
    ssh_user: root
    ssh_key_path: /secrets/ipa-admin-key
    admin_password: <sops>
  email:
    smtp_host: smtp.office365.com
    smtp_port: 587
    smtp_tls: true
    smtp_user: infrait@frlp.utn.edu.ar
    smtp_password: <sops>
    from_addr: infrait@frlp.utn.edu.ar
    to_addr: gidas@frlp.utn.edu.ar
```

## Arquitectura

```
┌──────────────────────┐     WinRM (5985)     ┌──────────────────┐
│  identity-dashboard  │ ──────────────────→   │  Active Directory │
│  (192.168.1.124)     │                       │  (192.168.1.117)  │
│                      │     SSH (22)          │                   │
│  CLI / TUI / Make    │ ──────────────────→   │  FreeIPA          │
│                      │                       │  (192.168.1.118)  │
└──────────────────────┘                       └──────────────────┘
```

## Rollback

- Si FreeIPA falla durante la creación, se elimina el usuario de AD automáticamente
- Si FreeIPA falla durante el password reset, se revierte AD a un password aleatorio
- Antes de eliminar un usuario, el TUI pide doble confirmación (escribir el username)
