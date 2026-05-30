# Proposal: Gestión de Identidades — Dominio Gidas

> **Change**: identity-management
> **Date**: 2026-05-29
> **Phase**: Proposal (post-exploration)
> **Status**: Draft — requires DC-VM verification before implementation

---

## 1. Intent

Establecer un sistema de gestión de identidades centralizado para el Grupo de Investigación Gidas, unificando la autenticación, autorización y DNS en toda la infraestructura (Proxmox cluster, containers, VMs, servicios), aprovechando el Domain Controller existente en pve-ad y extendiendo con FreeIPA para gobierno Linux nativo.

---

## 2. Scope

### In Scope

- ✅ Verificación del estado actual de **DC-VM** (SO, rol, dominio, DNS, estado de salud)
- ✅ Definición del nombre de dominio (recomendación: `gidas.frlp.utn.edu.ar` o `gidas.internal`)
- ✅ Despliegue de **FreeIPA** en pve-ad como IDM Linux complementario
- ✅ Configuración de **trust cross-realm** AD ↔ FreeIPA
- ✅ Integración de **autenticación Proxmox** contra AD/IPA
- ✅ Configuración de **SSSD** en todos los nodos Linux (pve-desa01-04, containers)
- ✅ Modelado de **grupos y permisos** por subgrupo (rojo, azul, verde, amarillo)
- ✅ Configuración de **DNS** interno (FreeIPA como DNS primary, forwarding a AD)
- ✅ Documentación de procedimientos y arquitectura

### Out of Scope

- ❌ Migración o reemplazo de DC-VM existente (a menos que esté en estado crítico)
- ❌ Configuración del router Mikrotik (se documenta la configuración DNS esperada, no se toca)
- ❌ Gestión de identidades para servicios externos (cloud, email, etc.)
- ❌ Implementación de VPN
- ❌ Monitoreo del sistema de identidad (se documenta como requisito futuro)
- ❌ Sincronización de contraseñas entre AD y FreeIPA (el trust Kerberos las maneja por separado)

---

## 3. Approaches

### Option A: AD Only (mantener DC-VM como único IDM)

**Descripción**: DC-VM sigue siendo el único Identity Provider. FreeIPA NO se instala. SSSD en Linux autentica contra AD directamente.

**Arquitectura**:
```
                     ┌─────────────┐
                     │   DC-VM     │
                     │  (AD+ DNS)  │
                     └──────┬──────┘
                            │
          ┌─────────────────┼─────────────────┐
          │                 │                  │
    ┌─────▼─────┐    ┌─────▼─────┐    ┌──────▼──────┐
    │ PVE Nodes │    │Containers │    │ Servicios   │
    │  (SSSD)   │    │ (SSSD)    │    │ Linux       │
    └───────────┘    └───────────┘    └─────────────┘
```

| Criterio | Evaluación |
|----------|------------|
| Esfuerzo | Bajo — asumiendo AD ya funcional |
| Windows | ✅ Excelente |
| Linux | ⚠️ Funcional pero sin HBAC/sudo nativos |
| Complejidad | Baja |
| Gestión | Windows-only (MMC, PowerShell) |
| Licencias | Requiere Windows Server license |

**Riesgos**:
- Si DC-VM tiene licencia evaluation expirada, el AD puede tener tiempo limitado
- Sin HBAC, cualquier usuario autenticado puede potencialmente acceder a cualquier host
- Sudo rules requieren configuración manual en cada host
- Sin CA integrada para certificados TLS internos

### Option B: AD + FreeIPA Trust (RECOMENDADA)

**Descripción**: AD (DC-VM) como fuente primaria de usuarios. FreeIPA como IDM Linux con trust cross-realm. Usuarios en AD, políticas Linux (HBAC, sudo) en FreeIPA.

**Arquitectura**:
```
                       ┌─────────────────────┐
                       │     DC-VM (AD)      │
                       │  Users & Groups     │
                       │  DNS (AD-integrated)│
                       └──────────┬──────────┘
                                  │ Kerberos Trust
                       ┌──────────▼──────────┐
                       │  FreeIPA Server     │
                       │  HBAC Rules         │
                       │  Sudo Rules         │
                       │  CA (Dogtag)        │
                       │  DNS (Bind)         │
                       └──────────┬──────────┘
                                  │
          ┌───────────────────────┼───────────────────────┐
          │                       │                       │
    ┌─────▼─────┐          ┌─────▼─────┐          ┌──────▼──────┐
    │ PVE Nodes │          │Containers │          │ Servicios   │
    │ SSSD→IPA  │          │ SSSD→IPA  │          │ Linux       │
    │ PVE Auth  │          │           │          │             │
    │ (AD realm)│          │           │          │             │
    └───────────┘          └───────────┘          └─────────────┘
```

Flujo de autenticación (SSH Linux → FreeIPA → AD):
```
Usuario SSH → SSSD → FreeIPA (HBAC check) → AD (Kerberos auth) → Acceso
```

Flujo de autenticación (PVE Web UI → AD):
```
Usuario PVE → PVE realm AD → DC-VM (LDAP bind) → Acceso
```

| Criterio | Evaluación |
|----------|------------|
| Esfuerzo | Medio-Alto (configurar trust lleva tiempo) |
| Windows | ✅ Nativo via AD |
| Linux | ✅ Nativo via FreeIPA + SSSD |
| Complejidad | Media |
| Gestión | AD para users, FreeIPA para policies |
| Licencias | Solo Windows Server (si aplica) |

**Beneficios clave sobre AD-only**:
- HBAC granular para controlar acceso por host/grupo/usuario
- Sudo rules centralizadas desde FreeIPA
- Certificate Authority para TLS interno
- Web UI moderna para gestión Linux
- Proxmox realm AD o IPA (cualquiera funciona)

### Option C: FreeIPA Only (migrar desde AD)

**Descripción**: Migrar todo a FreeIPA. DC-VM se migra o se apaga. No hay AD.

| Criterio | Evaluación |
|----------|------------|
| Esfuerzo | Alto (migración desde AD) |
| Windows | ❌ No soportado sin Samba |
| Linux | ✅ Excelente |
| Complejidad | Alta |
| Gestión | Web UI + CLI |

**Riesgos**:
- Migración desde AD vivo es riesgosa
- Windows clients no pueden unirse a FreeIPA
- Sin Windows Server, se pierde Group Policy para cualquier VM Windows

**No recomendada** porque ya hay AD funcionando y Windows VMs que podrían necesitarlo en el futuro.

---

## 4. Recommended: Option B — AD + FreeIPA Trust

### Justificación

1. **Preserva la inversión existente**: DC-VM está running y presumiblemente funcional. No hay razón para reemplazarlo.
2. **Cubre ambos mundos**: Linux es la plataforma dominante (5 nodos PVE, 5 containers, sitio web), pero Windows está presente (VMs detenidas, potenciales futuras).
3. **Gobierno Linux nativo**: HBAC y sudo rules son críticos para un entorno con múltiples subgrupos de investigación donde cada grupo debe tener acceso solo a sus recursos.
4. **Migración progresiva**: Se implementa FreeIPA sin tocar AD. Si en el futuro AD deja de ser necesario, la migración a FreeIPA standalone es trivial (los clientes ya apuntan a FreeIPA).

### Dominio Recomendado

**Opción primaria**: `gidas.frlp.utn.edu.ar`
- Si FRLP UTN permite gestionar un subdominio delegado
- AD NetBIOS: `GIDAS`
- AD DNS: `ad.gidas.frlp.utn.edu.ar` (o `corp.gidas.frlp.utn.edu.ar`)
- FreeIPA DNS: `ipa.gidas.frlp.utn.edu.ar`

**Opción fallback**: `gidas.internal`
- Si no se puede coordinar con la universidad
- Misma estructura de subdominios

### Topología de Red Propuesta

```
Subnet:        192.168.1.0/24 (existente, red plana)
Gateway:       192.168.1.1 (Mikrotik)
DNS Primary:   192.168.1.31/100 (FreeIPA, reenvía a AD)
DNS Secondary: 192.168.1.31/100 (AD)
DHCP:          Mikrotik (entrega DNS de FreeIPA/AD)
```

Nota: Si DC-VM y FreeIPA están en el mismo host (pve-ad) con IPs diferentes (p.ej., DC-VM en 192.168.1.10 via bridge, FreeIPA en 192.168.1.32 via container), se pueden asignar IPs separadas para cada servicio.

---

## 5. Plan de Implementación

### Fase 0 — Verificación y Diagnóstico (1 sesión)

```yaml
# Acciones REQUERIDAS antes de tocar nada
- Verificar SO de DC-VM (SSH al host o consola)
- Verificar nombre de dominio actual
- Verificar servicios DNS (dónde y cómo)
- Verificar DHCP (Mikrotik o AD)
- Verificar si hay trust o integración existente
- Verificar estado de licencia Windows Server (si aplica)
- Decidir dominio final
```

### Fase 1 — FreeIPA Setup (1-2 sesiones)

1. Crear container/VM para FreeIPA en pve-ad
   - SO: Rocky Linux 9 (o AlmaLinux 9)
   - RAM: 2 GB mínimo
   - Disco: 20 GB
   - IP: fija en 192.168.1.x (asignar una)
   - Hostname: `ipa.gidas.internal` (o el dominio elegido)

2. Instalar FreeIPA server:
   ```bash
   dnf module enable idm:DL1
   dnf install ipa-server
   ipa-server-install
   ```

3. Configurar DNS en FreeIPA (Bind integrado)

4. Verificar replicación DNS

### Fase 2 — Trust AD ↔ FreeIPA (1-2 sesiones)

1. En FreeIPA:
   ```bash
   ipa trust-add --type=ad <AD.DOMAIN> --admin <AD Admin>
   ```

2. Configurar DNS forwarding (FreeIPA → AD → Internet)

3. Verificar Kerberos cross-realm:
   ```bash
   kinit <user>@<AD.REALM>
   klist
   ```

4. Probar autenticación:

### Fase 3 — Integración Proxmox (1 sesión)

1. Agregar realm AD en PVE:
   ```bash
   pvesh create /access/domains \
     --type ad \
     --realm gidas-ad \
     --domain gidas.internal \
     --server1 <DC-VM-IP> \
     --port 389
   ```

2. Agregar realm IPA como alternativa si se prefiere

3. Mapear grupos AD a roles PVE:
   - `gidas-admins` → `Administrator`
   - `gidas-pve-admin` → `PVEAdmin`
   - `gidas-pve-viewer` → `PVEViewer`

### Fase 4 — SSSD en Nodos Linux (1 sesión)

1. Instalar SSSD en todos los nodos Proxmox y containers críticos:
   ```bash
   apt install sssd sssd-tools realmd adcli  # Debian/Proxmox
   ```

2. Unir al dominio FreeIPA:
   ```bash
   ipa-client-install
   ```

3. Configurar autenticación SSH:
   - `sssd.conf` con `id_provider = ipa`, `auth_provider = ipa`
   - `pam_sss.so` en PAM configuration
   - `sudoers` integrado con FreeIPA

### Fase 5 — Modelado de Acceso (1 sesión)

1. Crear grupos en AD:
   - `gidas-admins`
   - `gidas-rojo`
   - `gidas-azul`
   - `gidas-verde`
   - `gidas-amarillo`
   - `gidas-monitoring`

2. Crear HBAC rules en FreeIPA para cada grupo → hosts permitidos

3. Crear sudo rules en FreeIPA:
   - `%gidas-admins` → ALL (ALL) ALL
   - `%gidas-rojo` → /bin/systemctl, /bin/journalctl en hosts del grupo rojo

### Fase 6 — DNS y Documentación (1 sesión)

1. Configurar FreeIPA DNS como primary, forwarding a AD

2. Configurar DHCP en Mikrotik para entregar IPs de FreeIPA/AD como DNS

3. Documentar:
   - Arquitectura del sistema de identidad
   - Procedimiento de alta/baja de usuario
   - Procedimiento de recuperación ante fallos
   - Backup del DC y FreeIPA

---

## 6. Rollback Plan

| Componente | Rollback |
|-----------|----------|
| **FreeIPA** | Detener container/VM. SSSD clients vuelven a auth local. PVE realm AD sigue funcionando. |
| **Trust AD↔FreeIPA** | `ipa trust-del` y DNS forwarding se revierte. AD sigue intacto. |
| **PVE realm** | `pvesh delete /access/domains/<realm>` — los usuarios vuelven a auth local PVE. |
| **SSSD en nodos** | `apt remove sssd` y restaurar `/etc/nsswitch.conf`, `/etc/pam.d/`, `/etc/ssh/sshd_config` desde backup. |
| **DNS changes** | Revertir forwarding en FreeIPA. DHCP del Mikrotik vuelve a DNS original. |

**Regla de oro**: AD no se toca hasta que FreeIPA + Trust estén 100% funcionales y probados. Todo cambio es reversible.

---

## 7. Dependencies & Prerequisites

### Software
- FreeIPA server: Rocky Linux 9 / AlmaLinux 9 container o VM
- SSSD client en nodos Linux (apt/dnf package)
- realm AD en PVE (built-in, no extra package)
- Kerberos client tools (para troubleshooting)

### HW Resources
- FreeIPA: 2 GB RAM, 20 GB disk (pve-ad tiene 7.2 GB usada de 15 GB — hay capacidad)
- Espacio en pve-ad: 224 GB SSD total, aprox 130-150 GB usado (LVM thin) — verificar espacio disponible

### Network
- DNS resolution entre DC-VM y FreeIPA
- Puertos abiertos:
  - Kerberos: UDP/TCP 88
  - LDAP: TCP 389, 636 (LDAPS)
  - Global Catalog: TCP 3268, 3269
  - DNS: UDP/TCP 53
  - NTP: UDP 123
  - FreeIPA web UI: TCP 443

### Information Required
- [ ] Nombre de dominio actual en DC-VM
- [ ] IP de DC-VM
- [ ] Credenciales de administrador del dominio
- [ ] Estado de licencia Windows Server
- [ ] Rango de IPs disponibles en 192.168.1.0/24
- [ ] Hostname elegido para FreeIPA

---

## 8. Delivery Strategy

**Review budget forecast**: Low-Medium (< 400 lines of config/code)

Este cambio es predominantemente **configuración y documentación**:
- Scripts de instalación (shell, ~50-100 líneas)
- Configuración de SSSD (templates YAML, ~30 líneas)
- Configuración de PVE realm (comandos, ~10 líneas)
- Documentación (~200 líneas)

Single PR es suficiente. No se requiere chained PRs.

---

## 9. Open Questions (para resolver en Fase 0)

1. **¿Windows Server con licencia o evaluation?** — Si es evaluation, puede expirar. Plan de contingencia necesario.
2. **¿El Mikrotik es gestionable?** — Quién tiene acceso, contraseñas en SOPS?
3. **¿Hay algún FreeIPA o LDAM ya instalado en sg-?** — No se detectó en el audit, pero vale confirmar.
4. **¿Los becarios/estudiantes necesitan acceso a qué específicamente?** — Para diseñar HBAC rules correctas.
5. **¿Dominio público propio?** — gidas.com.ar, gidas.frlp.utn.edu.ar — quién lo gestiona?
6. **¿Hay preferencia por Windows vs Linux para gestión?** — Determina si Option A o B tiene más sentido para el equipo.
