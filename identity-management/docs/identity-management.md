# Identity Management — Sistema de Gestión de Identidades

> Grupo de Investigación Gidas — FRLP UTN
> Arquitectura: AD (DC1-GIDAS) + FreeIPA cross-realm trust

## Resumen

Sistema centralizado de autenticación, autorización y DNS para toda la infraestructura del grupo.

## Componentes

| Componente | IP | Rol | SO |
|-----------|-----|-----|-----|
| **DC1-GIDAS (AD)** | 192.168.1.117 | Domain Controller | Windows Server 2022 Std |
| **ipa-gidas (FreeIPA)** | 192.168.1.118 | IDM Linux, DNS, CA | Rocky Linux 10 |
| **pve-ad** | 192.168.1.31 | Hypervisor de identidad | Proxmox 9.1.1 |

## Dominio

- **DNS**: `GDC01.local`
- **AD NetBIOS**: `GDC01`
- **AD Realm**: `GDC01.LOCAL`
- **FreeIPA Realm**: `IPA.GDC01.LOCAL`

## Estructura de OUs

```
GDC01.local
├── Direccion                     ← Director + Vicedirector
│   └── Coordinadores             ← Coordinadores (1 proyecto c/u)
├── Proyectos
│   ├── PROY-Telepark
│   ├── PROY-CAPNEE
│   ├── PROY-INFRAiT
│   ├── PROY-GMET
│   └── PROY-GIS
├── Becarios                      ← Becarios (pueden estar en varios proyectos)
├── Groups                        ← Grupos de seguridad
├── ServiceAccounts
└── Servers
    ├── Proxmox
    └── Linux
```

## Nomenclatura de Grupos

| Prefix | Categoría | Ejemplo |
|--------|-----------|---------|
| `G-` | Rol funcional | `G-Direccion`, `G-Coordinadores` |
| `PROY-` | Proyecto | `PROY-Telepark`, `PROY-INFRAiT` |
| `SRV-` | Servicio | `SRV-PVEAdmin`, `SRV-InfraITAdmin` |

## Modelo de Acceso (HBAC)

| Grupo | Hosts | Sudo |
|-------|-------|------|
| G-Direccion | ALL | `ALL=(ALL) ALL` |
| G-IdentityAdmins | ALL | `ALL=(ALL) ALL` |
| G-Coordinadores | ALL | `ALL=(ALL) ALL` |
| G-Becarios | Host del proyecto asignado | Sin sudo |
| SRV-InfraITAdmin | Servidores INFRAiT, hosts desktop | `ALL=(ALL) ALL` |
| SRV-Monitoring | ALL (RO) | Plugins monitoreo |

## Documentos Relacionados

- `docs/identity/ad/ous.md` — Estructura de OUs de AD
- `docs/identity/ad/grupos.md` — Definición de grupos de AD
- `docs/identity/ad/usuarios.md` — Usuarios de AD
- `docs/identity/estructura-grupos-apps.md` — **Modelo reutilizable** para integrar cualquier aplicación (Redmine, GitLab, Proxmox, Keycloak, WiFi, etc.)
- `docs/identity/onboarding.md` — Alta de usuarios
- `docs/identity/offboarding.md` — Baja de usuarios
