# Capacitación — Gestión de Identidades Gidas

> Plan de capacitación para el equipo de administración del Grupo de Investigación Gidas.

## Módulos

| Módulo | Tema | Duración | Público |
|--------|------|----------|---------|
| **M01** | Introducción al sistema de identidad | 1 h | Todos |
| **M02** | Administración de Active Directory | 2 h | Administradores |
| **M03** | FreeIPA: gestión de políticas Linux | 2 h | Administradores |
| **M04** | HBAC y control de acceso | 1 h | Administradores |
| **M05** | Resolución de problemas comunes | 1 h | Administradores |

## M01 — Introducción al Sistema de Identidad

### Temas
- ¿Qué es un sistema de gestión de identidades?
- Arquitectura del Grupo Gidas: AD + FreeIPA Trust
- Dominio `gidas.internal` y estructura de red
- ¿Qué es un realm Kerberos? ¿Cómo funciona el trust?
- Flujo de autenticación SSH: usuario → SSSD → FreeIPA → AD
- Flujo de autenticación PVE: usuario → LDAPS → AD

### Material
- `docs/identity-management.md` (visión general)
- `sdd/design.md` (diagramas de flujo)

### Ejercicio Práctico
1. SSH a un nodo PVE con credenciales AD
2. Verificar identidad con `id`
3. Verificar sudo rules con `sudo -l`

---

## M02 — Administración de Active Directory

### Temas
- Estructura de OU: Users, Groups, Computers, Servers
- Creación y gestión de usuarios (New-ADUser)
- Gestión de grupos (New-ADGroup, Add-ADGroupMember)
- Políticas de contraseñas
- DNS integrado en AD
- Windows Server Backup

### Comandos Clave
```powershell
# Usuarios
New-ADUser, Get-ADUser, Set-ADUser, Disable-ADAccount, Enable-ADAccount
# Grupos
New-ADGroup, Add-ADGroupMember, Remove-ADGroupMember, Get-ADGroupMember
# DNS
Get-DnsServerZone, Add-DnsServerResourceRecord
# Backup
wbadmin start backup
```

### Material
- `docs/identity/onboarding.md`
- `docs/identity/offboarding.md`

---

## M03 — FreeIPA: Gestión de Políticas Linux

### Temas
- Acceso a FreeIPA: Web UI, CLI (`ipa *`)
- HBAC rules: crear, modificar, verificar
- Sudo rules: integración con AD groups
- Certificate Authority (Dogtag)
- DNS management en FreeIPA (Bind)
- Backups: `ipa-backup`

### Comandos Clave
```bash
# HBAC
ipa hbacrule-add, ipa hbacrule-find, ipa hbacrule-del
ipa hbacrule-add-user, ipa hbacrule-add-host
# Sudo
ipa sudorule-add, ipa sudorule-find, ipa sudorule-add-option
# DNS
ipa dnszone-add, ipa dnsforwardzone-add, ipa dnsrecord-add
# Trust
ipa trust-find, ipa trust-add, ipa trust-del
# Backup
ipa-backup --online --data
```

### Material
- `sdd/design.md` (secciones 3.2, 4, 5)
- `sdd/specs.md` (escenarios S1-S6)

---

## M04 — HBAC y Control de Acceso

### Temas
- ¿Qué es HBAC y por qué es necesario?
- Modelo de grupos y hosts del Grupo Gidas
- Creación de reglas HBAC en FreeIPA
- Pruebas de enforcement
- Troubleshooting de HBAC

### Mapa de Acceso
| Grupo | Hosts Permitidos | Sudo |
|-------|-----------------|------|
| gidas-admins | ALL | ALL=(ALL) ALL |
| gidas-rojo | sg-rojo, pve-desa01 | systemctl, journalctl |
| gidas-azul | sg-azul, pve-desa02 | systemctl, journalctl |
| ... | ... | ... |

### Ejercicio Práctico
1. Crear un usuario test en AD
2. Asignarlo a un grupo
3. Verificar que solo accede a hosts autorizados
4. Intentar acceso no autorizado → debe fallar

---

## M05 — Resolución de Problemas Comunes

### Problemas y Soluciones

| Problema | Causa Probable | Solución |
|----------|---------------|----------|
| SSH falla con "Access denied" | HBAC bloquea | Verificar grupo en AD, regla en FreeIPA |
| PVE login falla | LDAP bind incorrecto | Verificar realm, credenciales, puerto 636 |
| `kinit` falla | DNS no resuelve KDC | Verificar `dig SRV _kerberos._tcp.gidas.internal` |
| SSSD no arranca | Config errónea | `journalctl -u sssd`, verificar permisos 600 |
| Trust roto | Cambio de password AD | Re-ejecutar `ipa trust-add` |
| Backup FreeIPA falla | Disco lleno | Verificar espacio, limpiar backups viejos |

### Comandos de Diagnóstico
```bash
# Verificar resolución DNS
dig SRV _kerberos._tcp.gidas.internal

# Verificar trust
ipa trust-find

# Verificar SSSD
sssctl domain-status gidas.internal
journalctl -u sssd -n 50

# Verificar Kerberos
klist -l
kinit user@GIDAS.INTERNAL

# Verificar HBAC
ipa hbacrule-find --all
```
