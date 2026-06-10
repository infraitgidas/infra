# identity-dashboard — Release Notes

## 2026-06-10 — v1.0.0

Primera versión estable con TUI interactivo, email transaccional y Makefile.

### Nuevo

- **TUI interactivo** (`app/tui.py`): menú con 7 opciones usando `rich` + `questionary`
  - 👤 Crear usuario (con email, selector de grupos y proyectos desde AD)
  - 📋 Listar usuarios AD
  - 🔧 Habilitar / Deshabilitar (AD + FreeIPA)
  - ❌ Eliminar usuario (doble confirmación)
  - 🔑 Resetear password (con rollback AD si FreeIPA falla)
  - 👥 Grupos (agregar/quitar miembro, listar con filtro)
  - 🛡️ HBAC (test SSH, listar reglas)
- **Email transaccional** vía Outlook SMTP (`infrait@frlp.utn.edu.ar`)
  - Welcome email al nuevo usuario con credenciales
  - Notificación al admin (`gidas@frlp.utn.edu.ar`)
  - Soporte para `to_addr` dinámico en `EmailSender.send()`
- **Selector de proyectos**: consulta Departments existentes en AD, permite crear nuevo
- **Selector de grupos**: consulta grupos AD reales (multi-select), permite crear grupo nuevo
- **Makefile** con targets: `tui`, `cli`, `ssh-tui`, `list-users`, `list-groups`, `sync`, `deps`
- **Documentación**: `docs/identity-dashboard.md`

### Corregido

- `ad/user.py`: eliminado `-ChangePasswordAtLogon` de `New-ADUser` — conflictaba con `-PasswordNeverExpires $true` (error `ArgumentException` en AD)
- `app.tui` imports: corregidos nombres de funciones (`create_user`, `disable_user`, etc.)
- `app.tui` rollback: corregida llamada a `ad_remove_user` en fallo de FreeIPA

### Modificado

- `app/ad/user.py`: agregado parámetro `email` al template `create_user` (setea `-EmailAddress`)
- `app/freeipa/user.py`: agregado parámetro `email` a `user_add` (setea `--email`)
- `app/cli/user.py`: pasa email a AD/FreeIPA, envía welcome + admin notification
- `app/notify/sender.py`: `send()` ahora acepta `to_addr` opcional
- `app/notify/templates.py`: nueva función `user_welcome()` para email de bienvenida
- `secrets/identity.yaml`: SMTP migrado de mail.gidas.local → smtp.office365.com

### Commits

```
2deedf8 feat: email capture, group/project selector, SMTP Outlook
37854df fix: remove -ChangePasswordAtLogon from New-ADUser template
b99aacc feat: add Makefile for identity-dashboard CLI/TUI
c1d236c feat: add interactive TUI for identity-dashboard
63fe193 fix(ad): decode PowerShell output con fallback cp850 para español
```
