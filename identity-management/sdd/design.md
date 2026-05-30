# Design: Gestión de Identidades — AD + FreeIPA Trust

> **Change**: identity-management
> **Date**: 2026-05-29
> **Status**: Verified (Fase 0-4 partial)
> **Architecture**: AD (DC1-GIDAS) + FreeIPA cross-realm trust on `GDC01.local`
>
> **Fase 4 (2026-05-29)**: SSSD + AD join completado en pve-ad y pve-desa01. `adcli join` con provider `ad` en sssd.conf. Autenticación AD verificada via `getent passwd`. Pendiente: containers sg-*, HBAC rules, sudo rules.
>
> **Fase 0 (2026-05-29)**: VM-DC1 verificada. AD DS instalado, no promocionado. Licencia evaluation → Standard (KMS GVLK). Shutdown automático resuelto. DC-VM eliminado. Renombrada a DC1-GIDAS.
>
> **Fase 1 (2026-05-29)**: FreeIPA desplegado en VM 102 `ipa-gidas` (192.168.1.118). Rocky Linux 10.1 + FreeIPA 4.13.1. DNS Bind con forwarding a AD.
>
> **Fase 2 (2026-05-29)**: Trust cross-realm AD ↔ FreeIPA establecido y verificado. FreeIPA realm: IPA.GDC01.LOCAL. AD realm: GDC01.LOCAL.

## 1. Architecture Overview

```
                    ┌─────────────────────────┐
                    │     VM-DC1 (AD)         │
                    │  192.168.1.117          │
                    │  Users + Groups (source │
                    │  of truth)              │
                    │  DNS (ad.gidas.internal)│
                    │  LDAP/LDAPS, Kerberos   │
                    └───────────┬─────────────┘
                                │ Cross-realm Kerberos Trust
                    ┌───────────▼─────────────┐
                    │   FreeIPA Server        │
                    │  192.168.1.32           │
                    │  HBAC + Sudo Rules      │
                    │  CA (Dogtag PKI)        │
                    │  DNS Primary (Bind)     │
                    │  SSSD provider for      │
                    │  Linux hosts            │
                    └───────────┬─────────────┘
                                │
        ┌───────────────────────┼───────────────────────┐
        │                       │                       │
  ┌─────▼──────┐        ┌──────▼──────┐        ┌───────▼───────┐
  │ PVE Nodes  │        │ Containers  │        │ Services      │
  │ pve-desa*  │        │ sg-{color}  │        │ (various)     │
  │ SSSD→IPA   │        │ SSSD→IPA    │        │               │
  │ PVE AD     │        │ HBAC        │        │               │
  │ Realm      │        │ enforced    │        │               │
  └────────────┘        └─────────────┘        └───────────────┘
```

**Principio**: AD es la fuente de verdad para usuarios y grupos. FreeIPA aplica políticas Linux (HBAC, sudo) y resuelve autenticación contra AD via trust Kerberos. Ningún componente depende de FreeIPA para funcionar — si FreeIPA cae, los hosts Linux usan cache SSSD (≥8 h) y PVE sigue autenticando directo contra AD.

## 2. Network Topology

### IP Assignments
| Component | IP | VM/CT | SO | Rol |
|-----------|-----|-------|-----|-----|
| **FreeIPA** | **192.168.1.32** | Nueva VM (ex-template VM 108 en pve-desa04) | Rocky Linux 10 | IDM Linux, DNS primary, CA |
| **VM-DC1 (AD)** | **192.168.1.117** | Existente (ID 101) | Windows Server 2022 Standard | Domain Controller, DNS secondary — actualmente NO promocionado |
| pve-ad | 192.168.1.31 | — | Proxmox 9.1.1 | Hypervisor de identidad |
| pve-desa01 | TBD | — | Proxmox | Cluster node |
| pve-desa02 | TBD | — | Proxmox | Cluster node |
| pve-desa03 | TBD | — | Proxmox | Cluster node |
| pve-desa04 | TBD | — | Proxmox | Cluster node |
| sg-rojo | 192.168.1.200 | CT 200 | Linux | Subgrupo rojo |
| sg-azul | 192.168.1.204 | CT 201 | Linux | Subgrupo azul |
| sg-verde | 192.168.1.202 | CT 202 | Linux | Subgrupo verde |
| sg-amarillo | 192.168.1.203 | CT 203 | Linux | Subgrupo amarillo |
| sg-monitoring | 192.168.1.205 | CT 205 | Linux | Monitoreo |

### DNS Resolution Flow
```
Linux host resolver (/etc/resolv.conf)
  └→ FreeIPA DNS (192.168.1.32:53) ──primary──┐
       ├─ gidas.internal zone                  │ local resolution
       ├─ 1.168.192.in-addr.arpa (PTR)         │
       ├─ ad.gidas.internal ──forward──▶ AD DNS (192.168.1.117)
       └─ external domains ──forward──▶ AD DNS → Internet (UTN/ISP)

Windows host resolver
  └→ AD DNS (192.168.1.117:53) ──primary──┐
       ├─ ad.gidas.internal zone           │ local resolution  
       ├─ _msdcs.ad.gidas.internal         │ AD-specific
       └─ external domains ──forward──▶ Internet
```

FreeIPA DNS es el resolver primario para todos los hosts Linux. AD DNS es primario para VMs Windows. FreeIPA reenvía consultas del subdominio `ad.gidas.internal` a AD y consultas externas a AD (que reenvía a Internet).

### Port Requirements
| Servicio | Puerto | Tráfico | Origen → Destino |
|----------|--------|---------|-----------------|
| Kerberos | UDP/TCP 88 | Auth | Todos → FreeIPA + AD |
| LDAP | TCP 389 | Consultas | PVE → AD; SSSD → FreeIPA |
| LDAPS | TCP 636 | Consultas seguras | PVE → AD (obligatorio) |
| Global Catalog | TCP 3268/3269 | Consultas extendidas | PVE → AD (opcional) |
| DNS | UDP/TCP 53 | Resolución | Todos → FreeIPA + AD |
| NTP | UDP 123 | Sincronización horaria | Todos → AD/FreeIPA |
| FreeIPA Web UI | TCP 443 | Gestión web | Admin → FreeIPA |
| AD RPC | TCP 135, 49152-65535 | Trust setup | FreeIPA → AD |
| Kerberos pwd | UDP/TCP 464 | Password changes | Todos → AD |
| IPA replication | TCP 7389 | Replicación (futuro) | FreeIPA ↔ FreeIPA |

## 3. Component Design

### 3.1 AD (VM-DC1)
- **Dominio**: `gidas.internal` (NetBIOS: `GIDAS`)
- **DNS subdominio**: `ad.gidas.internal` (delegado en FreeIPA)
- **Role**: FSMO en VM-DC1 (único DC inicial)
- **Servicios**: AD DS, DNS, Kerberos KDC, NTP

#### OU Structure
```
gidas.internal
├── Users
│   ├── Admins            ← Cuentas administrativas (gidas-admins)
│   ├── Investigadores     ← Miembros de investigación
│   └── Estudiantes        ← Becarios y estudiantes
├── Groups
│   ├── gidas-admins
│   ├── gidas-rojo
│   ├── gidas-azul
│   ├── gidas-verde
│   ├── gidas-amarillo
│   └── gidas-monitoring
├── Computers
│   ├── Proxmox            ← Nodos PVE joined
│   ├── Containers         ← CTs joined
│   └── Services           ← Service accounts
└── Servers
    └── Domain Controllers ← DCs del dominio
```

### 3.2 FreeIPA Server
- **Hostname**: `ipa.gidas.internal`
- **IP**: 192.168.1.32 (estática)
- **SO**: Rocky Linux 10 (desde template rocky-10-template, VM 108 en pve-desa04)
- **Recursos**: 2 GB RAM, 2 vCPU, 32 GB disk
> **Nota Fase 0**: VM-DC1 tiene 3 GB RAM, 2 vCPU, 32 GB disk. Hostname actual: `WIN-J3DVKIHAGD2` (a renombrar antes de promocionar AD).
- **Servicios**: IPA server, DNS (Bind), CA (Dogtag), NTP

#### Template Migration Procedure
| Paso | Acción | Comando / Detalle |
|------|--------|------------------|
| 1 | Clonar VM 108 en pve-desa04 | `qm clone 108 <new-vmid> --name ipa-template-clone --full` |
| 2 | Backup via vzdump | `vzdump <new-vmid> --mode snapshot --compress zstd` |
| 3 | Transferir a pve-ad | `rsync -avz /var/lib/vz/dump/ root@pve-ad:/var/lib/vz/dump/` |
| 4 | Restaurar en pve-ad | `qmrestore /var/lib/vz/dump/vzdump-*.vma.zst <new-vmid> --storage local` |
| 5 | Configurar red | hostnamectl set-hostname ipa.gidas.internal; nmcli con mod eth0 ipv4.addresses 192.168.1.32/24 |
| 6 | Instalar FreeIPA | `ipa-server-install --domain=gidas.internal --realm=GIDAS.INTERNAL --setup-dns --setup-adtrust` |

**Riesgo**: Rocky Linux 10 es reciente (lanzado ~2025). Verificar disponibilidad de `ipa-server` via `dnf module install idm:DL1` o `dnf install freeipa-server`. Si no está disponible, cambiar a Rocky Linux 9.

#### FreeIPA DNS Zones
| Zone | Tipo | Detalle |
|------|------|---------|
| `gidas.internal` | Master (Bind) | Todos los hosts Linux, PVE nodes, CTs |
| `1.168.192.in-addr.arpa` | Master (Bind) | Reverse DNS para 192.168.1.0/24 |
| `ad.gidas.internal` | Forward zone | Forward queries → AD DNS (192.168.1.117) |

### 3.3 SSSD Configuration Template
```ini
[sssd]
domains = gidas.internal
services = nss, pam, sudo, ssh
config_file_version = 2

[domain/gidas.internal]
id_provider = ipa
auth_provider = ipa
ipa_domain = gidas.internal
ipa_server = _srv_, ipa.gidas.internal
ipa_hostname = ${HOSTNAME}.gidas.internal
ldap_id_mapping = True
# Offline cache ≥ 8 h (R4, R9)
cache_credentials = True
entry_cache_timeout = 3600
offline_credentials_expiration = 8
# Kerberos ticket TTL ≤ 24 h (R7)
krb5_ticket_lifetime = 24h
krb5_renewable_lifetime = 7d
# HBAC integration
enumerate = False
# Sudo integration
sudo_provider = ipa

[nss]
filter_users = root,daemon,bin,sys
filter_groups = root,daemon,bin,sys

[pam]
offline_failed_login_attempts = 3
offline_failed_login_delay = 5

[ssh]
ssh_known_hosts_timeout = 180
```

### 3.4 PVE Realm (AD)
```bash
# Agregar realm AD en PVE
pvesh create /access/domains \
  --type ad \
  --realm gidas-ad \
  --domain gidas.internal \
  --server1 192.168.1.117 \
  --port 636 \
  --secure 1 \
  --default 0

# Mapear grupos AD a roles PVE
pvesh set /access/acl \
  --path / \
  --groups gidas-admins \
  --role Administrator

pvesh set /access/acl \
  --path / \
  --groups gidas-pve-admin \
  --role PVEAdmin

pvesh set /access/acl \
  --path / \
  --groups gidas-pve-viewer \
  --role PVEViewer
```

## 4. Authentication Flows

### 4.1 SSH Login (Linux → SSSD → FreeIPA → AD)
```
User                  Linux Host            SSSD              FreeIPA              AD
 │                       │                   │                  │                  │
 │─────ssh user@host────▶│                   │                  │                  │
 │                       │───PAM auth───────▶│                  │                  │
 │                       │                   │───KRB AS-REQ────▶│                  │
 │                       │                   │                  │───TGT request───▶│
 │                       │                   │                  │ (cross-realm     │
 │                       │                   │                  │  referral)       │
 │                       │                   │                  │◀──TGT + PAC──────│
 │                       │                   │◀──TGT + PAC──────│                  │
 │                       │                   │───HBAC check────▶│                  │
 │                       │                   │  (host in        │                  │
 │                       │                   │   allow list?)   │                  │
 │                       │                   │◀──access OK──────│                  │
 │                       │◀──PAM success─────│                  │                  │
 │◀────shell granted─────│                   │                  │                  │
```

### 4.2 PVE Web UI Login
```
User                  Browser              PVE Web UI          AD (VM-DC1)
 │                       │                   │                  │
 │───login(gidas-ad\    ─▶                   │                  │
 │    user, pass)        │                   │                  │
 │                       │───LDAP bind──────▶│                  │
 │                       │   (636, TLS)      │                  │
 │                       │                   │◀──auth OK + SID──│
 │                       │                   │                  │
 │                       │                   │───map SID →──────│
 │                       │                   │   PVE role       │
 │                       │◀──session token───│                  │
 │◀────Dashboard─────────│                   │                  │
```

### 4.3 AD User Creation → Linux Access
```
Admin                  AD (VM-DC1)        FreeIPA            SSSD          Linux Host
 │                       │                  │                 │               │
 │───create user────────▶│                  │                 │               │
 │───add to gidas-azul──▶│                  │                 │               │
 │                       │                  │                 │               │
 │                       │    SSSD cache refresh (60 min / sss_cache -E)      │
 │                       │                  │◀──id request────│               │
 │                       │◀──trust query────│                 │               │
 │                       │───user info─────▶│                 │               │
 │                       │                  │───user info────▶│               │
 │                       │                  │                 │───cache──────▶│
 │                       │                  │                 │               │
 │                       │    User SSH to sg-azul → OK (HBAC permite)        │
 │                       │    User SSH to sg-rojo → DENIED (HBAC bloquea)    │
```

### 4.4 Kerberos Trust Validation
```
FreeIPA                           AD KDC
 │                                 │
 │───kinit admin@GIDAS.INTERNAL───▶│
 │                                 │───TGT issued──────▶│
 │◀──TGT + cross-realm key─────────│                    │
 │                                 │                    │
 │───ipa trust-add────────────────▶│ (AD admin creds)   │
 │  --type=ad gidas.internal       │                    │
 │                                 │───trust object────▶│
 │◀──trust established─────────────│                    │
 │                                 │                    │
 │───ipa trust-find───────────────▶│ (verification)     │
 │◀──AD domain: gidas.internal────│                    │
 │    Trust type: Active Directory │                    │
 │    Direction: Two-way          │                    │
```

## 5. HBAC Model

| Grupo AD | Hosts Permitidos | Sudo Rule | Justificación |
|----------|-----------------|-----------|---------------|
| gidas-admins | ALL (todos nodos PVE, CTs, VMs) | `%gidas-admins ALL=(ALL) ALL` | Admin full |
| gidas-rojo | sg-rojo, pve-desa01 | systemctl, journalctl, docker | Investigadores rojo |
| gidas-azul | sg-azul, pve-desa02 | systemctl, journalctl, docker | Investigadores azul |
| gidas-verde | sg-verde, pve-desa03 | systemctl, journalctl, docker | Investigadores verde |
| gidas-amarillo | sg-amarillo, pve-desa04 | systemctl, journalctl, docker | Investigadores amarillo |
| gidas-monitoring | sg-monitoring, ALL PVE nodes | `/usr/lib/nagios/plugins/*`, `ping` | Monitoreo RO |

**Deny by default**: cualquier grupo NO listado → acceso denegado a cualquier host.

## 6. Implementation Sequence

### Fase 0 — Verificación (pre-requisito)
- [ ] Verificar SO/rol de VM-DC1 (SSH o consola)
- [ ] Confirmar nombre de dominio actual en AD
- [ ] Verificar DNS actual (quién resuelve qué)
- [ ] Verificar credenciales admin AD
- [ ] Verificar licencia Windows Server
- [ ] Decidir dominio final (`gidas.internal` vs `gidas.frlp.utn.edu.ar`)

### Fase 1 — FreeIPA Deployment
1. Clonar VM 108 (rocky-10-template) en pve-desa04 → `qm clone`
2. Backup → `vzdump` modo snapshot
3. Transferir dump a pve-ad → `rsync`
4. Restaurar en pve-ad → `qmrestore`
5. Configurar red: IP 192.168.1.32/24, hostname ipa.gidas.internal
6. Instalar FreeIPA → `ipa-server-install --setup-dns --setup-adtrust`
7. Crear zonas DNS forward + reverse
8. Configurar forwarding DNS a AD (192.168.1.117)
9. Verificar AC1: `dig SRV _kerberos._tcp.gidas.internal`

### Fase 2 — Trust AD ↔ FreeIPA
1. En FreeIPA: `ipa trust-add --type=ad gidas.internal --admin Administrator`
2. Ingresar password admin AD cuando se solicite
3. Verificar AC2: `ipa trust-find`
4. Probar autenticación: `kinit admin@GIDAS.INTERNAL` en FreeIPA
5. Configurar DNS forwarding condicional: `ad.gidas.internal` → 192.168.1.117

### Fase 3 — Integración PVE
1. Agregar realm AD en cada nodo PVE (pve-desa01-04, pve-ad)
2. Configurar LDAPS (puerto 636) — verificar AC8
3. Mapear grupos AD → roles PVE
4. Verificar AC4: login PVE web UI con credenciales AD

### Fase 4 — SSSD + HBAC
1. Instalar SSSD en nodos PVE y containers
2. Configurar `sssd.conf` con template (sección 3.3)
3. Unir hosts al dominio FreeIPA: `ipa-client-install`
4. Crear HBAC rules en FreeIPA por grupo → hosts (sección 5)
5. Crear sudo rules en FreeIPA
6. Verificar AC3: SSH con credenciales AD
7. Verificar AC5: SSH denegado a host no permitido
8. Verificar AC6: desconectar AD, probar login cache ≥ 8 h
9. Configurar ticket lifetime ≤ 24 h (AC9)

### Fase 5 — Backups + Documentación
1. Configurar `ipa-backup --online` diario en FreeIPA
2. Configurar Windows Server Backup en VM-DC1
3. Tomar snapshot PVE de ambas VMs
4. Documentar procedimientos: `docs/identity/onboarding.md`, `docs/identity/offboarding.md`
5. Verificar AC10: backups funcionales
6. Verificar AC11: docs existen
7. Rotar password VM-DC1 admin (hlvs.2025 → nuevo)
8. Almacenar credenciales en `secrets/proxmox.yaml` con SOPS

## 7. Rollback Plan

| Componente | Pasos de Rollback | Tiempo Est. | Impacto |
|-----------|-------------------|-------------|---------|
| **FreeIPA** | 1. `virsh destroy <ipa-vm>` en pve-ad<br>2. SSSD clients detectan caída → auth local/cache<br>3. PVE realm AD sigue funcionando (no depende de FreeIPA)<br>4. DNS: cambiar resolvers a AD (192.168.1.117) | 5 min | Ninguno — AD intacto, auth local funciona |
| **Trust AD↔FreeIPA** | 1. `ipa trust-del gidas.internal` en FreeIPA (si FreeIPA está up)<br>2. Remover DNS forwarding condicional en FreeIPA<br>3. AD no requiere cambios — trust object se invalida solo | 2 min | Ninguno — AD no fue modificado |
| **PVE Realm AD** | 1. `pvesh delete /access/domains/gidas-ad`<br>2. Auth PVE vuelve a usuarios locales (`root@pam`)<br>3. ACLs de grupo se eliminan automáticamente | 1 min | Admin debe usar root local |
| **SSSD en hosts** | 1. `apt remove sssd adcli realmd`<br>2. Restaurar `/etc/nsswitch.conf`, `/etc/pam.d/*`, `/etc/ssh/sshd_config` de backup<br>3. `systemctl restart sshd`<br>4. Verificar que `getent passwd` no muestra usuarios del dominio | 5 min | Auth local pura |
| **DNS changes** | 1. En FreeIPA: remover forwarding zones<br>2. En Mikrotik (DHCP): restaurar DNS server original<br>3. Nada se rompe — DNS sigue funcionando con AD | 2 min | Nameservers originales |

**Regla de oro**: AD no se toca hasta que todo lo demás esté verificado. FreeIPA es completamente removible sin afectar AD ni la autenticación PVE.

## 8. Backup Strategy

| Componente | Método | Comando / Configuración | Frecuencia | Retención |
|-----------|--------|------------------------|------------|-----------|
| **FreeIPA** | ipa-backup online | `ipa-backup --online --data` | Diaria (cron) | 7 días |
| **FreeIPA VM** | PVE vzdump | `vzdump <ipa-vmid> --mode snapshot --compress zstd` | Semanal | 4 semanas |
| **AD (VM-DC1)** | Windows Server Backup | `wbadmin start backup -backupTarget:E: -include:C: -allCritical -quiet` | Diaria | 7 días |
| **AD VM** | PVE snapshot | `qm snapshot <ad-vmid> pre-cambio` | Antes de cada cambio | Hasta próximo cambio |
| **Secrets** | SOPS + git | `sops -e secrets/proxmox.yaml` | En cada cambio de credencial | Git history |

### FreeIPA Backup Script (sugerido: `/usr/local/bin/ipa-backup-cron.sh`)
```bash
#!/bin/bash
BACKUP_DIR="/var/lib/ipa/backup"
RETENTION_DAYS=7
ipa-backup --online --data
# Limpiar backups viejos
find "$BACKUP_DIR" -name "ipa-*.tar.gz" -mtime +$RETENTION_DAYS -delete
```

## 9. Design Decisions Summary

| # | Decisión | Alternativas | Decisión | Rationale |
|---|----------|-------------|----------|-----------|
| D1 | SO FreeIPA | Rocky 9 (propuesta original) vs Rocky 10 (template) | **Rocky 10** (template existente) | Usar template ya disponible. Verificar compatibilidad FreeIPA en Fase 0. |
| D2 | Dominio | `gidas.internal` vs `gidas.frlp.utn.edu.ar` | **`gidas.internal`** (fallback) | No depende de coordinación externa. Migrable a público si UTN delega. |
| D3 | Realm Kerberos | Mismo realm AD vs separado | **Separado**: AD=`GIDAS.INTERNAL`, FreeIPA=`IPA.GIDAS.INTERNAL` | Evita conflictos KDC. Trust cross-realm maneja la resolución. |
| D4 | DNS forwarding | FreeIPA→AD→Internet vs FreeIPA→Internet directo | **FreeIPA→AD→Internet** | AD necesita resolver nombres internos. Un solo punto de forwarding. |
| D5 | PVE realm | AD realm vs IPA realm | **AD realm** | Login directo contra AD sin depender de FreeIPA para PVE. |
| D6 | HBAC enforcement | AD-only groups vs FreeIPA HBAC | **FreeIPA HBAC** (nativo) | AD no tiene HBAC granular sin extensiones. FreeIPA HBAC es maduro. |
| D7 | SSSD id_provider | `ipa` vs `ad` | **`ipa`** | Integración más profunda (HBAC, sudo, certs) con FreeIPA. |

## 10. Acceptance Criteria Mapping

| ID | Criterio | Verificación | Fase |
|----|----------|-------------|------|
| AC1 | SRV _kerberos records | `dig SRV _kerberos._tcp.gidas.internal` → AD + FreeIPA | F1 |
| AC2 | Trust established | `ipa trust-find` → AD domain listed | F2 |
| AC3 | SSH auth with AD | `ssh user@host` con credenciales AD → acceso | F4 |
| AC4 | PVE login with AD | PVE web UI login con AD → dashboard | F3 |
| AC5 | HBAC enforced | `gidas-azul` SSH a `sg-rojo` → denied | F4 |
| AC6 | Offline cache ≥ 8h | Desconectar AD → login con cache | F4 |
| AC7 | Secrets encrypted | `sops -d secrets/proxmox.yaml` → AD passwords | F5 |
| AC8 | LDAPS enabled | `openssl s_client -connect 192.168.1.117:636` → TLS handshake | F3 |
| AC9 | Ticket TTL ≤ 24h | `klist -l` → ticket lifetime ≤ 24h | F4 |
| AC10 | Backups configured | `ipa-backup --online` succeeds; AD backup scheduled | F5 |
| AC11 | Docs exist | `docs/identity/onboarding.md` + `docs/identity/offboarding.md` | F5 |

## Open Questions (resueltas en Fase 0 ✅)

- [x] ¿Rocky Linux 10 tiene `ipa-server` disponible? Si no → usar Rocky Linux 9.
- [x] ¿VM-DC1 está en pve-ad o en pve-desa01? **En pve-ad (ID 101), STOPPED en la exploration ahora RUNNING**.
- [x] ¿DC-VM (VM 100 en pve-ad) y VM-DC1 son la misma o diferentes? **Eliminado — solo VM-DC1**.
- [x] ¿Qué dominio AD está configurado actualmente? **Ninguno funcional. AD DS instalado pero NO promocionado. DNS suffix `GDC01.local` es solo config de red.**
- [ ] ¿El Mikrotik tiene DHCP entregando DNS? ¿Se puede configurar? Pendiente de verificar.
- [ ] ¿Hay certificados TLS disponibles o se auto-firman? Se auto-firmarán en AD o FreeIPA.
- [x] **Licencia Windows**: Evaluation EXPIRADA → Convertida a ServerStandard (KMS GVLK). Shutdown resuelto.
- [x] **Hostname VM-DC1**: `WIN-J3DVKIHAGD2` — a renombrar antes de promocionar AD.
