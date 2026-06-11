# Estructura de Usuarios, Grupos y Proyectos — Modelo Reutilizable

> **Propósito**: Documentar la estructura de identidad del Grupo GIDAS en un formato
> neutral que cualquier aplicación o herramienta pueda consumir (Redmine, GitLab,
> Keycloak, Proxmox, WiFi hotspot, GLPI, etc.).
>
> **Fuente de verdad**: `staff.md` (raíz del repo)
> **Última actualización**: 2026-06-11

---

## 1. Principios de Diseño

| Principio | Aplicación |
|-----------|------------|
| **AD es fuente de verdad** | Todos los usuarios y grupos se crean primero en AD. Las apps se integran contra AD. |
| **Grupos con prefijos** | El prefijo indica el propósito del grupo: rol, proyecto, servicio, o aplicación. |
| **Herencia por grupos anidados** | Los grupos de rol (`G-*`) contienen usuarios. Los grupos de aplicación (`APP-*`) contienen grupos `G-*`. |
| **Roles aditivos** | Si un usuario pertenece a múltiples grupos, tiene la UNIÓN de permisos de todos ellos. |
| **Deny by default** | Si un usuario no está en ningún grupo mapeado a una aplicación, no tiene acceso. |

---

## 2. Convención de Nomenclatura de Grupos

```
G-*      → Grupos por rol funcional
PROY-*   → Proyectos de investigación  
SRV-*    → Servicios/infraestructura
APP-*    → Acceso a aplicación específica (access gate)
```

| Prefijo | Categoría | Ejemplos | ¿Quién es miembro? |
|---------|-----------|----------|-------------------|
| `G-` | Rol funcional | `G-Direccion`, `G-Coordinadores`, `G-Becarios` | Usuarios directos |
| `PROY-` | Proyecto investigación | `PROY-INFRAiT`, `PROY-CAPNEE` | Usuarios del proyecto (investigadores, becarios) |
| `SRV-` | Servicio | `SRV-PVEAdmin`, `SRV-InfraITAdmin` | Grupos `G-*` (anidados) o usuarios |
| `APP-` | Acceso a aplicación | `APP-Redmine` | Grupos `G-*` anidados + usuarios directos |

---

## 3. Usuarios

### 3.1 Tabla Maestra

```
sAMAccountName   Persona                      Rol          OU                   
──────────────   ──────────────────────────   ──────────── ─────────────────────
lnahuel          Leopoldo Nahuel               Director     OU=Direccion
lrocca           Leandro Rocca                 Vicedirector OU=Direccion
aalvarezf        Agustín Álvarez Ferrando      Coordinador  OU=Direccion/Coordinadores
mbacigalupe      Maria de los Ángeles Bacigalupe Coordinador OU=Direccion/Coordinadores
jmarchesini      Javier Ignacio Marchesini     Coordinador  OU=Direccion/Coordinadores
mpenalva         Mirta Peñalva                 Coordinador  OU=Direccion/Coordinadores
zquiroz          Zoe Quiroz                    Coordinador  OU=Direccion/Coordinadores
errodriguez      Emanuel Rodriguez Rodriguez   Coordinador  OU=Direccion/Coordinadores
rcaceresp        Rafael Cáceres Petckowicz     Becario      OU=Becarios
jetcheverry      Juan Ignacio Etcheverry       Becario      OU=Becarios
rmonfroglio      Romeo Monfroglio              Becario      OU=Becarios
cvalero          Cintia Valero                 Becario      OU=Becarios
fblancocavallero Federico Blanco Cavallero     Becario      OU=Becarios
smontanari       Santiago Montanari            Becario      OU=Becarios
tiago.ibanez     Tiago Ibañez                  Becario      OU=Becarios
infrait          infrait                       Service Acct OU=ServiceAccounts
```

### 3.2 Convención de Nombres de Usuario

| Campo | Formato | Ejemplo |
|-------|---------|---------|
| sAMAccountName | Primer nombre + Inicial segundo nombre + Apellido (lowercase, sin acentos) | `aalvarezf`, `rcaceresp` |
| UPN | `sAMAccountName@GDC01.local` | `aalvarezf@GDC01.local` |
| Mail | Correo institucional UTN o personal | `aaferrando@frlp.utn.edu.ar` |

---

## 4. Grupos por Rol Funcional (`G-*`)

> Estos grupos definen el **rol** de una persona en el grupo de investigación.
> Cada persona pertenece a EXACTAMENTE UN grupo `G-*`.

```yaml
G-Direccion:
  proposito: "Director y Vicedirector del grupo"
  miembros: [lnahuel, lrocca]
  herencia: "Miembro de APP-Redmine via nested group + directo"
  sudo: "ALL=(ALL) ALL"
  hbac: "ALL hosts"

G-Coordinadores:
  proposito: "Coordinadores de proyectos de investigación"
  miembros: [aalvarezf, mbacigalupe, jmarchesini, mpenalva, zquiroz, errodriguez]
  herencia: "Miembro de APP-Redmine via nested group + directo"
  sudo: "ALL=(ALL) ALL"
  hbac: "ALL hosts"

G-Becarios:
  proposito: "Becarios y estudiantes del grupo"
  miembros: [rcaceresp, jetcheverry, rmonfroglio, cvalero, 
             fblancocavallero, smontanari, tiago.ibanez]
  herencia: "Miembro de APP-Redmine via nested group + directo"
  sudo: "Sin sudo"
  hbac: "Hosts del proyecto asignado"

G-IdentityAdmins:
  proposito: "Administradores técnicos de identidad (AD + FreeIPA)"
  miembros: [errodriguez, infrait]
  sudo: "ALL=(ALL) ALL"
  hbac: "ALL hosts"

G-Graduados:
  proposito: "RESERVADO — Graduados del grupo"
  miembros: []
  estado: "Futuro"

G-Practicas:
  proposito: "RESERVADO — Pasantes/Practicantes"
  miembros: []
  estado: "Futuro"
```

**Regla**: Un `G-*` NUNCA contiene otro `G-*`. Solo usuarios directos.

---

## 5. Proyectos de Investigación (`PROY-*`)

> Estos grupos definen a qué **proyecto de investigación** pertenece una persona.
> Una persona puede pertenecer a MÚLTIPLES proyectos.

```yaml
PROY-CAPNEE:
  proposito: "Proyecto CAPNEE"
  coordinador: aalvarezf
  becarios: [rcaceresp, jetcheverry, cvalero]
  miembros: [aalvarezf, rcaceresp, jetcheverry, cvalero]

PROY-INFRAiT:
  proposito: "Proyecto INFRAiT (infraestructura informática)"
  coordinador: errodriguez
  becarios: [rmonfroglio, fblancocavallero, smontanari, tiago.ibanez]
  miembros: [errodriguez, rmonfroglio, fblancocavallero, smontanari, tiago.ibanez]

PROY-Telepark:
  proposito: "Proyecto TELEPARK"
  coordinador: mpenalva
  becarios: []  # (a definir)
  miembros: [mpenalva]

PROY-GMET:
  proposito: "Proyecto GMET"
  coordinador: zquiroz
  becarios: []  # (a definir)
  miembros: [zquiroz]

PROY-GIS:
  proposito: "Proyecto GIS"
  coordinador: jmarchesini
  becarios: []  # (a definir)
  miembros: [jmarchesini]
```

---

## 6. Servicios (`SRV-*`)

> Grupos para acceso a servicios de infraestructura. Pueden contener
> grupos `G-*` anidados o usuarios directos.

```yaml
SRV-PVEAdmin:
  proposito: "Administración de Proxmox VE"
  miembros: [G-Direccion]   # Grupo anidado
  rol_pve: "Administrator"

SRV-InfraITAdmin:
  proposito: "Sysadmin de servidores Linux y hosts desktop (proyecto INFRAiT)"
  miembros: []  # (a definir — integrantes INFRAiT con rol sysadmin)
  sudo: "ALL=(ALL) ALL"
  hbac: "Servidores INFRAiT + hosts desktop"

SRV-Monitoring:
  proposito: "Monitoreo (solo lectura)"
  miembros: []  # (a definir)
  permisos: "Plugins monitoreo, ping"
```

---

## 7. Acceso a Aplicaciones (`APP-*`)

> **Access gates**. Cada aplicación tiene su propio grupo `APP-*` que
> contiene a los usuarios/grupos que pueden autenticarse en ella.
>
> Usar grupos anidados para rol + usuarios directos para compatibilidad
> máxima con LDAP.

```yaml
APP-Redmine:
  proposito: "Access gate para Redmine"
  miembros_anidados: [G-Direccion, G-Coordinadores, G-Becarios, G-IdentityAdmins]
  miembros_directos: [TODOS los usuarios AD]  # Para compatibilidad LDAP simple
  filtro_ldap: "(memberOf=CN=APP-Redmine,OU=Groups,DC=GDC01,DC=local)"
```

---

## 8. Matriz de Permisos por Aplicación

### 8.1 Redmine

| Grupo AD | Proyecto(s) Redmine | Rol Redmine |
|----------|--------------------|-------------|
| `G-Direccion` | TODOS | Director |
| `G-Coordinadores ∩ PROY-CAPNEE` | CAPNEE | Coordinador |
| `G-Coordinadores ∩ PROY-INFRAiT` | INFRAiT | Coordinador |
| `G-Coordinadores ∩ PROY-Telepark` | TELEPARK | Coordinador |
| `G-Coordinadores ∩ PROY-GMET` | GMET | Coordinador |
| `G-Coordinadores ∩ PROY-GIS` | GIS | Coordinador |
| `G-Coordinadores` | Dirección, Administración | Coordinador |
| `G-Becarios ∩ PROY-CAPNEE` | CAPNEE | Becario |
| `G-Becarios ∩ PROY-INFRAiT` | INFRAiT | Becario |

### 8.2 Proxmox VE

| Grupo AD | Role PVE | Pool |
|----------|----------|------|
| `G-Direccion` | Administrator | `/` |
| `G-IdentityAdmins` | Administrator | `/` |
| `G-Coordinadores` | PVEAdmin | `/` |
| `G-Becarios` | PVEViewer | Pool del proyecto |
| `SRV-InfraITAdmin` | PVEAdmin | `/` |

### 8.3 GitLab (futuro)

| Grupo AD | GitLab Role | Proyecto |
|----------|-------------|----------|
| `G-Direccion` | Owner | Todos los grupos/grupos |
| `G-Coordinadores` | Maintainer | Grupo de su proyecto |
| `G-Becarios` | Developer | Grupo de su proyecto |
| Miembro de `PROY-*` | — | Miembro del grupo GitLab correspondiente |

### 8.4 GLPI

| Grupo AD | GLPI Profile | Entidad |
|----------|-------------|---------|
| `G-Direccion` | Super-admin | Todas |
| `G-Coordinadores` | Admin | Su entidad |
| `G-Becarios` | Technician | Su entidad |

### 8.5 WiFi Hotspot / Captive Portal (futuro)

| Grupo AD | Acceso |
|----------|--------|
| Cualquier usuario AD autenticado | Acceso a WiFi |
| `G-Direccion` | Ancho de banda prioritario |
| `G-Becarios` | Ancho de banda limitado |

### 8.6 Keycloak (futuro)

| Grupo AD | Keycloak Role | Client |
|----------|---------------|--------|
| `G-Direccion` | admin | `*` |
| `G-Coordinadores` | manager | `proyecto-*` |
| `G-Becarios` | user | `proyecto-*` |

---

## 9. Lógica de Mapping (para implementar en scripts)

### 9.1 Pseudocódigo Genérico

```
# Para cualquier aplicación que soporte grupos y roles:

INPUT: usuario U, aplicación APP

# 1. Obtener grupos AD del usuario
grupos_ad = LDAP.query(memberOf=U.dn)

# 2. Determinar rol funcional (G-*)
rol = grupos_ad.match(/G-(.*)/)

# 3. Determinar proyectos (PROY-*)
proyectos = grupos_ad.match(/PROY-(.*)/)

# 4. Para cada aplicación, aplicar mapping específico
if APP == "redmine":
    for each proyecto in proyectos:
        if rol == "Direccion":
            APP.assign(U, proyecto, "Director")
        elif rol == "Coordinadores":
            APP.assign(U, proyecto, "Coordinador")
        elif rol == "Becarios":
            APP.assign(U, proyecto, "Becario")

if APP == "proxmox":
    if "G-Direccion" in grupos_ad:
        APP.assign(U, "Administrator")
    elif "G-Coordinadores" in grupos_ad:
        APP.assign(U, "PVEAdmin")
    elif "G-Becarios" in grupos_ad:
        APP.assign(U, "PVEViewer")
```

### 9.2 Reglas de Negocio (aplican a TODAS las integraciones)

```
1. Un usuario pertenece a EXACTAMENTE UN grupo G-* (rol funcional)
2. Un usuario puede pertenecer a MÚLTIPLES grupos PROY-* (proyectos)
3. Si un usuario está en G-Direccion, tiene acceso a TODO
4. Si un usuario está en G-Coordinadores ∩ PROY-X, tiene rol de gestión en X
5. Si un usuario está en G-Becarios ∩ PROY-X, tiene rol de lectura/contribución en X
6. Roles son ADITIVOS: si un usuario tiene múltiples roles, tiene la UNIÓN de permisos
7. Deny by default: si no hay match, no tiene acceso
```

---

## 10. Cómo Integrar una Nueva Aplicación

Para integrar una nueva aplicación/ herramienta al ecosistema GIDAS:

### Paso 1: Elegir el método de autenticación

```
┌──────────────────────────────────────────────────────────────┐
│ ¿La app soporta LDAP/S?                                       │
│   ├── Sí → Usar AD como fuente LDAP directa                  │
│   │         Host: 192.168.1.117 (DC1-GIDAS)                  │
│   │         Puerto: 389 (LDAP) o 636 (LDAPS)                 │
│   │         Base DN: DC=GDC01,DC=local                       │
│   │                                                          │
│   └── No → Usar FreeIPA como proxy LDAP o SAML               │
│             Host: 192.168.1.118 (ipa-gidas)                  │
│             (vía trust Kerberos AD ↔ FreeIPA)                │
└──────────────────────────────────────────────────────────────┘
```

### Paso 2: Crear el access gate

```powershell
# En AD, crear grupo APP-{nombre}
New-ADGroup -Name "APP-MiApp" -GroupScope Global -Path "OU=Groups,DC=GDC01,DC=local"

# Agregar los grupos G-* que deben tener acceso
Add-ADGroupMember -Identity "APP-MiApp" -Members "G-Direccion","G-Coordinadores","G-Becarios"

# Agregar usuarios directos (para compatibilidad con LDAP simple)
Add-ADGroupMember -Identity "APP-MiApp" -Members "lnahuel","lrocca",...
```

### Paso 3: Configurar el filtro LDAP en la app

```
Filter: (memberOf=CN=APP-MiApp,OU=Groups,DC=GDC01,DC=local)
```

### Paso 4 (avanzado): Sincronizar grupos y roles

Implementar el mismo patrón que `redmine/scripts/sync-ad-members.sh`:

```
1. Consultar AD para obtener grupos y miembros
2. Aplicar lógica de mapping (sección 9)
3. Llamar a la API de la app para crear/asignar usuarios y roles
4. Ejecutar vía cron cada N minutos
```

---

## 11. Diagrama de Arquitectura

```
                           ┌─────────────────────┐
                           │   ACTIVE DIRECTORY   │
                           │    (DC1-GIDAS)       │
                           │   192.168.1.117      │
                           │                     │
                           │  G-Direccion ─────┐ │
                           │  G-Coordinadores ─┤ │
                           │  G-Becarios ──────┤ │
                           │  G-IdentityAdmins ─┤ │
                           │  PROY-* ──────────┤ │
                           │  SRV-* ───────────┤ │
                           │                   │ │
                           │  APP-Redmine ◄────┘ │
                           │  APP-{next}    ───┐ │
                           └───────────────────┼─┘
                                               │
          ┌──────────────┬──────────────┬──────┼──────────────┐
          │              │              │      │              │
          ▼              ▼              ▼      ▼              ▼
   ┌──────────┐  ┌──────────┐  ┌──────────┐ ┌──────────┐  ┌──────────┐
   │ Redmine  │  │ Proxmox  │  │  GitLab  │ │   WiFi   │  │ Keycloak │
   │ (APP-RM) │  │ (SRV-PVE)│  │ (futuro) │ │ (futuro) │  │ (futuro) │
   └──────────┘  └──────────┘  └──────────┘ └──────────┘  └──────────┘
```

---

## 12. Referencias

| Documento | Descripción |
|-----------|-------------|
| `staff.md` | Fuente de verdad: todos los usuarios y sus asignaciones |
| `identity-management/docs/identity/ad/ous.md` | Estructura de OUs de AD |
| `identity-management/docs/identity/ad/grupos.md` | Definición de grupos de AD |
| `identity-management/docs/identity/ad/usuarios.md` | Usuarios AD con grupos y OUs |
| `identity-management/docs/identity/onboarding.md` | Procedimiento de alta de usuarios |
| `identity-management/docs/identity/offboarding.md` | Procedimiento de baja de usuarios |
| `redmine/scripts/sync-ad-members.sh` | Ejemplo de script de sync (implementación de referencia) |
