# Grupos de Seguridad — Active Directory

> **OU destino**: `OU=Groups,DC=GDC01,DC=local`
> **Última actualización**: 2026-06-03

## Convención de Nomenclatura

| Prefix | Categoría | Ejemplo |
|--------|-----------|---------|
| `G-` | Grupo por rol funcional | `G-Direccion`, `G-Coordinadores` |
| `PROY-` | Proyecto de investigación | `PROY-Telepark`, `PROY-CAPNEE` |
| `SRV-` | Servicio/aplicación | `SRV-PVEAdmin`, `SRV-InfraITAdmin` |

---

## Grupos por Rol

### G-Direccion
| Atributo | Valor |
|----------|-------|
| Propósito | Director y Vicedirector |
| Sudo (FreeIPA) | `%G-Direccion ALL=(ALL) ALL` |
| HBAC | ALL hosts |
| PVE Role | Administrator |
| Miembros | Leopoldo Nahuel, Leandro Rocca |

### G-Coordinadores
| Atributo | Valor |
|----------|-------|
| Propósito | Coordinadores de proyectos |
| Sudo (FreeIPA) | `%G-Coordinadores ALL=(ALL) ALL` |
| HBAC | ALL hosts |
| PVE Role | PVEAdmin |
| Miembros | Agustín Álvarez Ferrando, Maria de los Ángeles Bacigalupe, Javier Ignacio Marchesini, Mirta Peñalva, Zoe Quiroz, Emanuel Rodriguez Rodriguez |

### G-Becarios
| Atributo | Valor |
|----------|-------|
| Propósito | Becarios y estudiantes |
| Sudo (FreeIPA) | Sin sudo |
| HBAC | Hosts del proyecto asignado |
| PVE Role | PVEViewer |
| Miembros | Rafael Cáceres Petckowicz, Juan Ignacio Etcheverry, Romeo Monfroglio, Cintia Valero |

### G-IdentityAdmins
| Atributo | Valor |
|----------|-------|
| Propósito | Administradores técnicos de identidad (AD + FreeIPA) |
| Sudo (FreeIPA) | `%G-IdentityAdmins ALL=(ALL) ALL` |
| HBAC | ALL hosts |
| PVE Role | Administrator |
| Miembros | Emanuel Rodriguez Rodriguez (coordinador INFRAiT), infrait (service account) |

### G-Graduados
Reservado.

### G-Practicas
Reservado.

---

## Proyectos de Investigación

| Grupo | Miembros |
|-------|----------|
| PROY-Telepark | (a definir) |
| PROY-CAPNEE | (a definir) |
| PROY-INFRAiT | (a definir — incluye miembros con rol sysadmin) |
| PROY-GMET | (a definir) |
| PROY-GIS | (a definir) |

Los miembros se asignan cuando los responsables definen los integrantes de cada proyecto.

---

## Servicios

### SRV-PVEAdmin
| Propósito | Admin de Proxmox |
| Miembros | G-Direccion |

### SRV-InfraITAdmin
| Propósito | Sysadmin de servidores Linux y hosts desktop (proyecto INFRAiT) |
| Sudo (FreeIPA) | `ALL=(ALL) ALL` |
| HBAC | Servidores del proyecto + hosts desktop |
| Miembros | (a definir — integrantes de INFRAiT con rol de sysadmin). Service account: infrait |

### SRV-Monitoring
| Propósito | Monitoreo (solo lectura) |
| Miembros | (a definir — coordinador: Emanuel Rodriguez Rodriguez) |

---

## Mapeo a Roles PVE

| Grupo AD | Role PVE |
|----------|----------|
| G-Direccion | Administrator |
| G-IdentityAdmins | Administrator |
| G-Coordinadores | PVEAdmin |
| G-Becarios | PVEViewer |
| SRV-InfraITAdmin | PVEAdmin |

## Mapeo a HBAC (FreeIPA)

| Grupo AD | Hosts Permitidos | Sudo |
|----------|-----------------|------|
| G-Direccion | ALL | `ALL=(ALL) ALL` |
| G-IdentityAdmins | ALL | `ALL=(ALL) ALL` |
| G-Coordinadores | ALL | `ALL=(ALL) ALL` |
| G-Becarios | Host del proyecto asignado | Sin sudo |
| SRV-InfraITAdmin | Servidores INFRAiT, hosts desktop | `ALL=(ALL) ALL` |
| SRV-Monitoring | ALL (RO) | Plugins monitoreo, ping |

**Regla**: Deny by default.
