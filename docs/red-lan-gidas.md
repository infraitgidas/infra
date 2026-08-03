# Red LAN GIDAS — Estado y Acceso SSH

> Documento de operaciones de la red local del Grupo GIDAS (192.168.1.0/24).
> Última verificación: **2026-08-03** — 6/6 máquinas con SSH operativo.

---

## Topología

| Aspecto | Detalle |
|---------|---------|
| **Subred** | `192.168.1.0/24` |
| **Gateway** | `192.168.1.1` (MikroTik) |
| **Conexión** | Cable LAN directo (`enp2s0`, 1 Gbps Full Duplex) |
| **Este host** | `192.168.1.107` |
| **Túnel `sdwan0`** | Interfaz TUN `100.96.0.2/32` (CGNAT 100.96.0.0/12) — presente en el host de trabajo; sus rutas host hacia `192.168.1.x` fueron removidas (secuestraban el tráfico de la LAN física) |

---

## Inventario SSH (6/6 operativas)

| Máquina (archivo) | IP | Hostname real | Usuario SSH | Estado |
|---|---|---|---|---|
| pc infra (Linux Rocky) | `192.168.1.54` | `37709.gidas` | `infra` | ✅ Operativo |
| pc direccion | `192.168.1.30` | `DIRECCION` | `Administrador` | ✅ Operativo |
| pc isla 1 | `192.168.1.51` | `GIDAS-002` | `gidas_admin` | ✅ Operativo |
| pc isla 2 | `192.168.1.52` | `gidas-desktop-854` | `gidas_admin` | ✅ Operativo |
| pc isla 3 | `192.168.1.53` | `GIDAS-003` | `gidas_admin` | ✅ Operativo |
| pc isla 4 | `192.168.1.50` | `gidas-37710` | `gidas_admin` | ✅ Operativo |

> ⚠️ **Nota**: la nomenclatura interna del inventario (`pc isla N`, `pc direccion`) **no coincide** con los hostnames reales. El mapeo local está en `pc-lan.md`.

---

## Dominio Active Directory — GDC01.local

> Todas las máquinas unidas al dominio: **2026-08-03**.

| Aspecto | Detalle |
|---------|---------|
| **Dominio** | `GDC01.local` (AD) |
| **DC** | `192.168.1.117` (LDAP 389) — hostname `dc1-gidas.gdc01.local` |
| **DNS clientes** | Primario `192.168.1.117` (DC), secundario `192.168.1.1` (MikroTik) |
| **Login** | Usuarios activos del dominio autentican contra el DC |

### Estado por máquina

| Máquina | Join | Verificación |
|---|---|---|
| pc infra (Rocky) | `realm join` (sssd) | ✅ Login `Administrator@gdc01.local` OK — `allow-realm-logins` |
| pc direccion (`.30`) | `Add-Computer` | ✅ `PartOfDomain=True` |
| pc isla 1 (`.51`) | `Add-Computer` | ✅ Login `GDC01\Administrator` OK |
| pc isla 2 (`.52`) | `Add-Computer` | ✅ `PartOfDomain=True` |
| pc isla 3 (`.53`) | `Add-Computer` | ✅ `PartOfDomain=True` |
| pc isla 4 (`.50`) | `Add-Computer` | ✅ `PartOfDomain=True` |

### Notas técnicas

- **Windows**: join con `Add-Computer -DomainName GDC01.local -Credential GDC01\Administrator` + reinicio.
- **Linux**: `realm join GDC01.local -U Administrator`. Se aplicó fix `ldap_id_mapping = True`
  en `/etc/sssd/sssd.conf` — el AD no tiene atributos POSIX (RFC2307) y el modo `False`
  (generado por `--automatic-id-mapping=no`) causaba `invalid user`.
- **DNS**: pre-requisito del join — cada cliente debe resolver `GDC01.local` contra el DC
  (el MikroTik no tiene la zona; el DC sí, incluye SRV `_ldap._tcp`).

---

## Guía de conexión

Las credenciales de acceso están en `pc-lan.md` — archivo **local, no versionado**.

```bash
# Linux (pc infra)
ssh infra@192.168.1.54

# Windows — dirección
ssh Administrador@192.168.1.30

# Windows — islas
ssh gidas_admin@192.168.1.51   # GIDAS-002
ssh gidas_admin@192.168.1.52   # gidas-desktop-854
ssh gidas_admin@192.168.1.53   # GIDAS-003
ssh gidas_admin@192.168.1.50   # gidas-37710
```

En las máquinas Windows, OpenSSH Server ejecuta los comandos con `cmd.exe`
(no expande sintaxis de shell POSIX como `$(...)` — usar `hostname`, `whoami`, etc.).

---

## Historial de verificación

| Fecha | Resultado |
|-------|-----------|
| 2026-08-03 (temprano) | Solo `.30` y `.54` con SSH; `.50`, `.51`, `.52`, `.53` sin servicio |
| 2026-08-03 | `.53` suma SSH (hostname `GIDAS-003`) |
| 2026-08-03 | `.50` y `.51` suman SSH — 5/6 |
| 2026-08-03 | `.52` suma SSH — **6/6 operativas** ✅ |

## Referencias

- `pc-lan.md` — inventario de credenciales (local, ignorado en git)
- `PROJECT.md` — seguimiento por feature del proyecto Infra GIDAS
