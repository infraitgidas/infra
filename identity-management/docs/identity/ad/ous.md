# Estructura de Unidades Organizacionales (OU) — Active Directory

> **Dominio**: `GDC01.local` (NetBIOS: `GDC01`)
> **DC primario**: DC1-GIDAS (192.168.1.117)
> **Última actualización**: 2026-06-03

## Principios de Diseño

| Principio | Aplicación |
|-----------|------------|
| **Máx 3-4 niveles** | Cada nivel suma un punto de GPO inheritance |
| **OUs por administración, no por org chart** | Las OUs definen quién administra qué |
| **Grupos para membresía** | Proyectos se modelan como OUs + grupos de seguridad |
| **Jerarquía real** | Director → Coordinador → Proyecto → Becarios |

## Árbol de OUs

```
GDC01.local
├── Direccion                              ← Director + Vicedirector
│   └── Coordinadores                      ← Coordinadores (1 proyecto c/u)
│
├── Proyectos                              ← OUs por proyecto
│   ├── PROY-Telepark
│   ├── PROY-CAPNEE
│   ├── PROY-INFRAiT
│   ├── PROY-GMET
│   └── PROY-GIS
│
├── Becarios                               ← Todos los becarios (planos)
│
├── Groups                                 ← Grupos de seguridad (plano)
├── ServiceAccounts                        ← Cuentas de servicio
│
└── Servers
    ├── DomainControllers
    ├── Proxmox
    └── Linux
```

## Detalle por OU

### Direccion
| Atributo | Valor |
|----------|-------|
| Propósito | Director y Vicedirector del grupo |
| Miembros | Leopoldo Nahuel, Leandro Rocca |

### Direccion/Coordinadores
| Atributo | Valor |
|----------|-------|
| Propósito | Coordinadores de proyectos (1 proyecto cada uno) |
| Miembros | Agustín Álvarez Ferrando, Maria de los Ángeles Bacigalupe, Javier Ignacio Marchesini, Mirta Peñalva, Zoe Quiroz, Emanuel Rodriguez Rodriguez |

### Proyectos/*
Un OU por proyecto de investigación. Cada proyecto puede tener usuarios directos (coordinadores asignados viven en Direccion/Coordinadores, pero pueden agregarse objects específicos del proyecto).

| Proyecto | Descripción |
|----------|-------------|
| PROY-Telepark | Proyecto Telepark |
| PROY-CAPNEE | Proyecto CAPNEE |
| PROY-INFRAiT | Proyecto INFRAiT (incluye rol sysadmin) |
| PROY-GMET | Proyecto GMET |
| PROY-GIS | Proyecto GIS |

### Becarios
| Atributo | Valor |
|----------|-------|
| Propósito | Todos los becarios, independientemente del proyecto |
| Nota | Los becarios pueden estar en múltiples proyectos. La membresía se maneja por grupos PROY-*, no por OU |

### Groups
Todos los grupos de seguridad en una OU plana. Ver `grupos.md`.

---

## Mapeo de Delegación

| Grupo | OUs delegadas |
|-------|---------------|
| G-Direccion | Direccion, Coordinadores, Proyectos/*, Becarios |
| G-IdentityAdmins | Direccion, Coordinadores, Proyectos/*, Becarios |
| G-Coordinadores | Becarios, Proyectos/* |
