# Identity Management — Sistema de Gestión de Identidades

> Grupo de Investigación Gidas — FRLP UTN
> Arquitectura: AD (VM-DC1) + FreeIPA cross-realm trust

## Resumen

Sistema centralizado de autenticación, autorización y DNS para toda la infraestructura del grupo, combinando Active Directory como fuente de verdad para usuarios y FreeIPA como IDM Linux con políticas nativas (HBAC, sudo, PKI).

## Componentes

| Componente | IP | Rol | SO |
|-----------|-----|-----|-----|
| **VM-DC1 (AD)** | 192.168.1.117 | Domain Controller, DNS secundario | Windows Server |
| **FreeIPA** | 192.168.1.32 | IDM Linux, DNS primario, CA | Rocky Linux 10 |
| **pve-ad** | 192.168.1.31 | Hypervisor de identidad | Proxmox 9.1.1 |

## Dominio

- **DNS**: `gidas.internal`
- **AD NetBIOS**: `GIDAS`
- **AD Realm**: `GIDAS.INTERNAL`
- **FreeIPA Realm**: `GIDAS.INTERNAL`

## Estructura de Red

| Subred | Gateway | DNS Primario | DNS Secundario |
|--------|---------|-------------|----------------|
| 192.168.1.0/24 | 192.168.1.1 (Mikrotik) | 192.168.1.32 (FreeIPA) | 192.168.1.117 (AD) |

### Resolución DNS

```
Host Linux → FreeIPA DNS (192.168.1.32) ── primary ──┐
    ├─ gidas.internal (zona local)                     │
    ├─ ad.gidas.internal ── forward ──▶ AD (192.168.1.117)
    └─ externo ── forward ──▶ AD ──▶ Internet

Host Windows → AD DNS (192.168.1.117) ── primary ──┐
    ├─ ad.gidas.internal (zona local)                │
    └─ externo ──▶ Internet
```

## AD — Unidades Organizativas

```
gidas.internal
├── Users
│   ├── Admins
│   ├── Investigadores
│   └── Estudiantes
├── Groups
│   ├── gidas-admins
│   ├── gidas-rojo
│   ├── gidas-azul
│   ├── gidas-verde
│   ├── gidas-amarillo
│   └── gidas-monitoring
├── Computers
│   ├── Proxmox
│   ├── Containers
│   └── Services
└── Servers
    └── Domain Controllers
```

## Modelo de Acceso (HBAC)

| Grupo AD | Hosts Permitidos | Sudo |
|----------|-----------------|------|
| gidas-admins | Todos los nodos | `ALL=(ALL) ALL` |
| gidas-rojo | sg-rojo, pve-desa01 | systemctl, journalctl, docker |
| gidas-azul | sg-azul, pve-desa02 | systemctl, journalctl, docker |
| gidas-verde | sg-verde, pve-desa03 | systemctl, journalctl, docker |
| gidas-amarillo | sg-amarillo, pve-desa04 | systemctl, journalctl, docker |
| gidas-monitoring | sg-monitoring, todos los PVE (RO) | plugins monitoreo, ping |

## Roles PVE

| Grupo AD | Rol PVE |
|----------|---------|
| gidas-admins | Administrator |
| gidas-pve-admin | PVEAdmin |
| gidas-pve-viewer | PVEViewer |

## Flujo de Autenticación (SSH)

```
Usuario → SSH → SSSD → FreeIPA (HBAC check) → AD (Kerberos auth) → Acceso
```

## Flujo de Autenticación (PVE)

```
Usuario → PVE Web UI → LDAPS (636) → AD (bind) → Rol PVE → Dashboard
```

## Documentos Relacionados

- `../sdd/specs.md` — Especificaciones técnicas
- `../sdd/design.md` — Diseño de arquitectura detallado
- `../tasks/planned/tasks.md` — Plan de implementación
- `identity/onboarding.md` — Alta de usuarios
- `identity/offboarding.md` — Baja de usuarios
