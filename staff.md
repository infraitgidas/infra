# Staff — Grupo GIDAS

> **Propósito**: Fuente de verdad única del personal del grupo GIDAS.
> **Drive**: La creación/modificación de usuarios en AD, FreeIPA, y servicios (Redmine, GLPI, PVE, GitLab) se deriva de este documento.
> **Última actualización**: 2026-06-11

---

## Convenciones

| Campo | Formato | Ejemplo |
|-------|---------|---------|
| sAMAccountName | Primero + Inicial segundo + Apellido (lowercase, sin acentos) | `aalvarezf`, `rcaceresp` |
| UPN | `sAMAccountName@GDC01.local` | `aalvarezf@GDC01.local` |
| OU | Según rol (ver abajo) | `OU=Coordinadores,OU=Direccion,DC=GDC01,DC=local` |
| Mail | Correo institucional UTN o personal | `aaferrando@frlp.utn.edu.ar` |

---

## Dirección

| Nombre | sAMAccountName | Mail | Teléfono | Rol AD | OU |
|--------|---------------|------|----------|--------|----|
| Leopoldo Nahuel | lnahuel | lnahuel@frlp.utn.edu.ar | 2215225601 | Director | `OU=Direccion,DC=GDC01,DC=local` |
| Leandro Rocca | lrocca | leorocca@frlp.utn.edu.ar | 2215033249 | Vicedirector | `OU=Direccion,DC=GDC01,DC=local` |

### AD
- **Grupos**: `G-Direccion`, `SRV-PVEAdmin`
- **Proyectos Redmine**: Dirección, Administración (rol **Director**), todos los proyectos de investigación (rol **Director**)
- **PVE Role**: Administrator
- **HBAC**: ALL hosts
- **Sudo**: `ALL=(ALL) ALL`

---

## Coordinadores

| Nombre | sAMAccountName | Mail | Teléfono | Proyecto Asignado | OU |
|--------|---------------|------|----------|-------------------|----|
| Agustín Álvarez Ferrando | aalvarezf | aaferrando@frlp.utn.edu.ar | 2216144673 | CAPNEE | `OU=Coordinadores,OU=Direccion,DC=GDC01,DC=local` |
| Maria de los Ángeles Bacigalupe | mbacigalupe | mabacigalupe@frlp.utn.edu.ar | 2213048648 | *(a definir)* | `OU=Coordinadores,OU=Direccion,DC=GDC01,DC=local` |
| Javier Ignacio Marchesini | jmarchesini | jmarchesini@frlp.utn.edu.ar | 2215347670 | GIS | `OU=Coordinadores,OU=Direccion,DC=GDC01,DC=local` |
| Mirta Peñalva | mpenalva | penalvam@frlp.utn.edu.ar | 2216136464 | TELEPARK | `OU=Coordinadores,OU=Direccion,DC=GDC01,DC=local` |
| Zoe Quiroz | zquiroz | zquiroz@alu.frlp.utn.edu.ar | 1126492219 | GMET | `OU=Coordinadores,OU=Direccion,DC=GDC01,DC=local` |
| Emanuel Rodriguez Rodriguez | errodriguez | erodriguezrodriguez@alu.frlp.utn.edu.ar | 2213069974 | INFRAiT | `OU=Coordinadores,OU=Direccion,DC=GDC01,DC=local` |

### AD
- **Grupos**: `G-Coordinadores`, `SRV-PVEAdmin`
- **Grupos adicionales**: `PROY-{proyecto}` correspondiente. `errodriguez` además: `G-IdentityAdmins`, `PROY-INFRAiT`
- **Proyectos Redmine**:
  - Dirección y Administración (rol **Coordinador**)
  - Proyecto asignado (rol **Coordinador**)
  - Los becarios de su proyecto son gestionados por el coordinador
- **PVE Role**: PVEAdmin
- **HBAC**: ALL hosts
- **Sudo**: `ALL=(ALL) ALL`

---

## Becarios

| Nombre | sAMAccountName | Mail | Teléfono | Proyecto Asignado | OU |
|--------|---------------|------|----------|-------------------|----|
| Rafael Cáceres Petckowicz | rcaceresp | rcpetkowicz@gmail.com | 1155983869 | CAPNEE | `OU=Becarios,DC=GDC01,DC=local` |
| Juan Ignacio Etcheverry | jetcheverry | jetcheverry@alu.frlp.utn.edu.ar | 2215617704 | CAPNEE | `OU=Becarios,DC=GDC01,DC=local` |
| Romeo Monfroglio | rmonfroglio | rmonfrolio@alu.frlp.utn.edu.ar | 1173634429 | INFRAiT | `OU=Becarios,DC=GDC01,DC=local` |
| Federico Blanco Cavallero | fblancocavallero | fblancocavallero@alu.frlp.utn.edu.ar | *(a definir)* | INFRAiT | `OU=Becarios,DC=GDC01,DC=local` |
| Santiago Montanari | smontanari | smontanari@alu.frlp.utn.edu.ar | *(a definir)* | INFRAiT | `OU=Becarios,DC=GDC01,DC=local` |
| Tiago Ibañez | tiago.ibanez | tiago.ibanez@alu.frlp.utn.edu.ar | *(a definir)* | INFRAiT | `OU=Becarios,DC=GDC01,DC=local` |
| Cintia Valero | cvalero | cintiavalero@frlp.utn.edu.ar | 2216008031 | CAPNEE | `OU=Becarios,DC=GDC01,DC=local` |

### AD
- **Grupos**: `G-Becarios`
- **Grupos adicionales**: `PROY-{proyecto}` correspondiente
- **Proyectos Redmine**: Proyecto asignado (rol **Becario**). Pueden tener múltiples proyectos.
- **PVE Role**: PVEViewer
- **HBAC**: Hosts del proyecto asignado
- **Sudo**: Sin sudo

> **Nuevos (2026-06-11)**: Federico Blanco Cavallero, Santiago Montanari, Tiago Ibañez se incorporan como becarios del proyecto INFRAiT. Deben crearse en AD con OU `Becarios`, grupos `G-Becarios` y `PROY-INFRAiT`.

---

## Service Accounts

| Nombre | sAMAccountName | Propósito | Grupos | OU |
|--------|---------------|-----------|--------|----|
| infrait | infrait | Administración de identidad (AD + FreeIPA) | `G-IdentityAdmins` | `OU=ServiceAccounts,DC=GDC01,DC=local` |

---

## Mapa de Proyectos de Investigación

| Proyecto | Grupo AD | Coordinador | Becarios |
|----------|----------|-------------|----------|
| **CAPNEE** | `PROY-CAPNEE` | aalvarezf | rcaceresp, jetcheverry, cvalero |
| **TELEPARK** | `PROY-Telepark` | mpenalva | *(a definir)* |
| **GMET** | `PROY-GMET` | zquiroz | *(a definir)* |
| **GIS** | `PROY-GIS` | jmarchesini | *(a definir)* |
| **INFRAiT** | `PROY-INFRAiT` | errodriguez | rmonfroglio, fblancocavallero, smontanari, tiago.ibanez |

---

## Mapa de Roles — Servicios

Aplican en: **Redmine**, **PVE**, **GitLab**, **GLPI** (según cobertura de cada servicio).

| Rol AD | Redmine | PVE | HBAC | Sudo |
|--------|---------|-----|------|------|
| **G-Direccion** | Director (todo) | Administrator | ALL | `ALL=(ALL) ALL` |
| **G-Coordinadores** | Coordinador (proyecto asignado) + Coordinador (Dirección/Administración) | PVEAdmin | ALL | `ALL=(ALL) ALL` |
| **G-Becarios** | Becario (proyecto asignado) | PVEViewer | Hosts del proyecto | Sin sudo |
| **G-IdentityAdmins** | *(según necesidad)* | Administrator | ALL | `ALL=(ALL) ALL` |
| **SRV-InfraITAdmin** | *(según necesidad)* | PVEAdmin | Servidores INFRAiT + hosts desktop | `ALL=(ALL) ALL` |

---

## Reglas de Negocio

1. **Unidad organizativa**: cada persona pertenece a EXACTAMENTE UNA OU (Direccion, Coordinadores, Becarios, ServiceAccounts).
2. **Grupo de rol**: cada persona pertenece a EXACTAMENTE UN grupo `G-*` (rol funcional).
3. **Grupo de proyecto**: cada persona puede pertenecer a MÚLTIPLES grupos `PROY-*` (proyectos).
4. **Herencia de permisos**: los roles son ADITIVOS. Si alguien está en múltiples grupos, tiene la UNIÓN de permisos.
5. **Nested groups**: un grupo `G-*` NUNCA contiene otro grupo `G-*`. Los `PROY-*` contienen usuarios directos. Los `SRV-*` pueden contener grupos `G-*`.

---

## Servicios con Integración AD

| Servicio | URL | Auth | Sync |
|----------|-----|------|------|
| **Redmine** | `https://redmine.gidas.local` | LDAP (AD) | Group Sync + Script mapping |
| **PVE** | `https://pve-ad:8006` | Realm AD | Manual group→role mapping |
| **GitLab** | *(a definir)* | LDAP/LDAPS (AD/FreeIPA) | *(pendiente)* |
| **GLPI** | *(a definir)* | LDAP (FreeIPA) | GLPI LDAP sync |

---

## Historial de Cambios

| Fecha | Cambio | Responsable |
|-------|--------|-------------|
| 2026-06-11 | Creación inicial del documento | INFRAiT |
