# Tasks: Identity Management — AD + FreeIPA Trust

> **Change**: identity-management
> **Architecture**: AD (VM-DC1) + FreeIPA cross-realm trust
> **Domain**: `gidas.internal` (NetBIOS: `GIDAS`)

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | < 200 (config + docs, no code) |
| 400-line budget risk | Low |
| Chained PRs recommended | No |
| Suggested split | Single PR |
| Delivery strategy | single-pr |

Decision needed before apply: No
Chained PRs recommended: No
Chain strategy: size-exception
400-line budget risk: Low

---

## Fase 0 — Verificación y Diagnóstico (pre-requisito)

Verificar el estado actual de la infraestructura antes de cualquier cambio. **No ejecutar sin acceso SSH confirmado.**

### F0.1 — Verificar pve-ad
- **Desc**: SSH a pve-ad (192.168.1.31). Verificar Proxmox version, almacenamiento disponible, VMs/CTs corriendo.
- **Comando**: `ssh root@pve-ad` → `pveversion`, `df -h`, `qm list`, `pct list`
- **Verif**: Shell obtenido, `pveversion` ≥ 9.1.1, storage suficiente (>20 GB libres)
- **Esfuerzo**: XS | **Riesgo**: Low | **Dep**: None
- **Rollback**: N/A — solo lectura

### F0.2 — Identificar Domain Controller
- **Desc**: Determinar qué VM es el DC real. Exploration reporta DC-VM (VM 100, RUNNING en pve-ad) y VM-DC1 (STOPPED en pve-desa01). Confirmar cuál está activo, su IP, SO, y nombre de dominio.
- **Comando**: `qm config 100` en pve-ad, verificar IP y SO. Consola VNC si es necesario.
- **Verif**: IP documentada, SO confirmado (Windows Server), dominio AD identificado
- **Esfuerzo**: XS | **Riesgo**: Low | **Dep**: F0.1
- **Rollback**: N/A — solo lectura

### F0.3 — Verificar servicios DNS
- **Desc**: Ejecutar `dig` desde pve-ad y desde un CT Linux para ver qué servidor DNS resuelve, qué dominios existen, y si hay SRV records de Kerberos/LDAP.
- **Comando**: `dig gidas.internal`, `dig -x 192.168.1.117`, `dig SRV _kerberos._tcp.gidas.internal`
- **Verif**: Se identifica servidor DNS actual y dominio configurado
- **Esfuerzo**: XS | **Riesgo**: Low | **Dep**: F0.1
- **Rollback**: N/A — solo lectura

### F0.4 — Verificar credenciales AD
- **Desc**: Test SSH a VM-DC1 con `Administrator` / `hlvs.2025`. Verificar que choco esté disponible.
- **Comando**: `ssh Administrator@192.168.1.117`, luego `choco list --local-only`
- **Verif**: Login exitoso, `choco` reconoce el comando
- **Esfuerzo**: XS | **Riesgo**: Low | **Dep**: F0.2
- **Rollback**: N/A — solo lectura

### F0.5 — Verificar licencia Windows Server
- **Desc**: En VM-DC1, ejecutar `slmgr /dli` para ver estado de licencia. Si es evaluation, documentar fecha de expiración.
- **Comando**: `slmgr /dli` desde PowerShell admin en VM-DC1
- **Verif**: Estado de licencia documentado en design decisions
- **Esfuerzo**: XS | **Riesgo**: Medium | **Dep**: F0.4
- **Rollback**: N/A — solo lectura

### F0.6 — Documentar hallazgos
- **Desc**: Actualizar `identity-management/sdd/design.md` con hallazgos de Fase 0. Resolver Open Questions del design. Decidir dominio final.
- **Verif**: Design.md actualizado con IPs, SO, dominio confirmados
- **Esfuerzo**: S | **Riesgo**: Low | **Dep**: F0.1–F0.5
- **Rollback**: `git checkout -- identity-management/sdd/design.md`

---

## Fase 1 — FreeIPA Deployment

Desplegar servidor FreeIPA en pve-ad desde el template Rocky Linux 10 existente.

### F1.1 — Clonar template en pve-desa04
- **Desc**: Clonar VM 108 (rocky-10-template) en pve-desa04 para crear una VM limpia.
- **Comando**: `qm clone 108 <new-vmid> --name ipa-template-clone --full` (en pve-desa04)
- **Verif**: VM clonada aparece en `qm list` con estado STOPPED
- **Esfuerzo**: XS | **Riesgo**: Low | **Dep**: F0.6
- **Rollback**: `qm destroy <new-vmid>`

### F1.2 — Backup del clone
- **Desc**: Crear vzdump del clon para transferir a pve-ad.
- **Comando**: `vzdump <new-vmid> --mode snapshot --compress zstd`
- **Verif**: Archivo `.vma.zst` creado en `/var/lib/vz/dump/`
- **Esfuerzo**: S | **Riesgo**: Low | **Dep**: F1.1
- **Rollback**: `rm /var/lib/vz/dump/vzdump-*.vma.zst`

### F1.3 — Transferir backup a pve-ad
- **Desc**: Sincronizar el dump via rsync desde pve-desa04 a pve-ad.
- **Comando**: `rsync -avz /var/lib/vz/dump/vzdump-*.vma.zst root@pve-ad:/var/lib/vz/dump/`
- **Verif**: Archivo presente en pve-ad en `/var/lib/vz/dump/`
- **Esfuerzo**: M | **Riesgo**: Medium | **Dep**: F1.2
- **Rollback**: `rm /var/lib/vz/dump/vzdump-*.vma.zst` en pve-ad

### F1.4 — Restaurar VM en pve-ad
- **Desc**: Restaurar la VM desde el backup en pve-ad con nuevo VMID.
- **Comando**: `qmrestore /var/lib/vz/dump/vzdump-*.vma.zst <new-vmid> --storage local`
- **Verif**: VM visible en `qm list` en pve-ad, estado STOPPED
- **Esfuerzo**: S | **Riesgo**: Medium | **Dep**: F1.3
- **Rollback**: `qm destroy <new-vmid>` en pve-ad

### F1.5 — Configurar red y hostname
- **Desc**: Asignar IP estática 192.168.1.32/24, gateway 192.168.1.1, hostname `ipa.gidas.internal`.
- **Comando**: `hostnamectl set-hostname ipa.gidas.internal`; `nmcli con mod eth0 ipv4.addresses 192.168.1.32/24 ipv4.gateway 192.168.1.1`; `nmcli con up eth0`
- **Verif**: `ping 192.168.1.1`, `hostname -f` → `ipa.gidas.internal`
- **Esfuerzo**: S | **Riesgo**: Low | **Dep**: F1.4
- **Rollback**: Revertir configuración nmcli a DHCP o IP anterior

### F1.6 — Instalar FreeIPA server
- **Desc**: Instalar paquetes FreeIPA con DNS y AD trust. Si Rocky 10 no tiene `ipa-server`, usar Rocky 9.
- **Comando**: `dnf install freeipa-server freeipa-server-dns freeipa-server-trust-ad`; `ipa-server-install --domain=gidas.internal --realm=GIDAS.INTERNAL --setup-dns --setup-adtrust --no-forwarders`
- **Verif**: `ipa-server-install` completa sin errores. `ipactl status` muestra servicios UP.
- **Esfuerzo**: L | **Riesgo**: High | **Dep**: F1.5
- **Rollback**: `ipa-server-install --uninstall` o destruir VM y repetir desde F1.4

### F1.7 — Configurar zonas DNS
- **Desc**: Crear zona reverse (1.168.192.in-addr.arpa) y configurar forwarding condicional a AD (192.168.1.117) para el subdominio `ad.gidas.internal`.
- **Comando**: `ipa dnszone-add 1.168.192.in-addr.arpa`; `ipa dnsforwardzone-add ad.gidas.internal --forwarder=192.168.1.117 --forward-policy=only`
- **Verif**: `ipa dnszone-find`, `dig -x 192.168.1.32` resuelve
- **Esfuerzo**: S | **Riesgo**: Medium | **Dep**: F1.6
- **Rollback**: `ipa dnszone-del 1.168.192.in-addr.arpa`; `ipa dnsforwardzone-del ad.gidas.internal`

### F1.8 — Verificar AC1
- **Desc**: Confirmar que los SRV records de Kerberos son resolubles.
- **Comando**: `dig SRV _kerberos._tcp.gidas.internal @192.168.1.32`
- **Verif**: Respuesta incluye registros del KDC de FreeIPA
- **Esfuerzo**: XS | **Riesgo**: Low | **Dep**: F1.7
- **Rollback**: N/A — verificación

---

## Fase 2 — Trust AD ↔ FreeIPA

Establecer trust Kerberos cross-realm y verificar autenticación.

### F2.1 — Crear trust AD
- **Desc**: En FreeIPA, agregar trust con AD. Usar credenciales de Administrator de AD.
- **Comando**: `ipa trust-add --type=ad gidas.internal --admin Administrator`
- **Verif**: Comando solicita password y retorna trust object con tipo "Active Directory"
- **Esfuerzo**: M | **Riesgo**: High | **Dep**: F1.8, F0.4
- **Rollback**: `ipa trust-del gidas.internal`

### F2.2 — Verificar AC2
- **Desc**: Confirmar trust establecido.
- **Comando**: `ipa trust-find`
- **Verif**: Dominio AD `gidas.internal` listado con trust type "Active Directory"
- **Esfuerzo**: XS | **Riesgo**: Low | **Dep**: F2.1
- **Rollback**: N/A — verificación

### F2.3 — Test Kerberos cross-realm
- **Desc**: Obtener ticket Kerberos usando credenciales de AD contra el realm AD.
- **Comando**: `kinit Administrator@GIDAS.INTERNAL` en FreeIPA; luego `klist`
- **Verif**: `klist` muestra TGT emitido para `Administrator@GIDAS.INTERNAL`
- **Esfuerzo**: S | **Riesgo**: Medium | **Dep**: F2.2
- **Rollback**: `kdestroy`

### F2.4 — Configurar DNS forwarding condicional
- **Desc**: Asegurar que consultas a `ad.gidas.internal` se reenvíen a AD DNS.
- **Comando**: `ipa dnsforwardzone-add ad.gidas.internal --forwarder=192.168.1.117 --forward-policy=only`
- **Verif**: `dig ad.gidas.internal @192.168.1.32` resuelve IPs de AD
- **Esfuerzo**: XS | **Riesgo**: Low | **Dep**: F2.2
- **Rollback**: `ipa dnsforwardzone-del ad.gidas.internal`

---

## Fase 3 — Integración PVE

Configurar autenticación centralizada en Proxmox VE contra AD.

### F3.1 — Agregar realm AD en PVE
- **Desc**: Configurar realm AD en cada nodo PVE (pve-desa01–04, pve-ad) para login via LDAPS.
- **Comando**: `pvesh create /access/domains --type ad --realm gidas-ad --domain gidas.internal --server1 192.168.1.117 --port 636 --secure 1 --default 0`
- **Verif**: `pvesh get /access/domains` muestra `gidas-ad` con type `ad`
- **Esfuerzo**: S | **Riesgo**: Low | **Dep**: F2.4
- **Rollback**: `pvesh delete /access/domains/gidas-ad` en cada nodo

### F3.2 — Verificar AC8 (LDAPS)
- **Desc**: Confirmar que LDAPS (puerto 636) está habilitado en AD.
- **Comando**: `openssl s_client -connect 192.168.1.117:636`
- **Verif**: Handshake TLS completo. Si falla, generar self-signed cert en AD.
- **Esfuerzo**: S | **Riesgo**: Medium | **Dep**: F3.1
- **Rollback**: N/A — verificación. Si no hay cert, generarlo en AD.

### F3.3 — Mapear grupos AD a roles PVE
- **Desc**: Asignar roles PVE a grupos AD (`gidas-admins` → Administrator, etc.).
- **Comando**: `pvesh set /access/acl --path / --groups gidas-admins --role Administrator`
- **Verif**: `pvesh get /access/acl` muestra las ACLs configuradas
- **Esfuerzo**: S | **Riesgo**: Low | **Dep**: F3.1
- **Rollback**: `pvesh delete /access/acl --path / --groups gidas-admins --role Administrator`

### F3.4 — Verificar AC4
- **Desc**: Probar login PVE web UI con credenciales AD.
- **Comando**: Login en `https://pve-ad:8006` con `gidas-ad\<user>` y password AD
- **Verif**: Acceso a dashboard PVE con permisos del rol mapeado
- **Esfuerzo**: XS | **Riesgo**: Low | **Dep**: F3.3
- **Rollback**: N/A — verificación

---

## Fase 4 — SSSD + HBAC

Configurar autenticación Linux nativa con políticas de acceso.

### F4.1 — Instalar SSSD en nodos PVE
- **Desc**: Instalar paquetes SSSD en todos los nodos Proxmox (pve-desa01–04, pve-ad).
- **Comando**: `apt install sssd sssd-tools realmd adcli` en cada nodo
- **Verif**: `sssd --version` retorna versión instalada
- **Esfuerzo**: S | **Riesgo**: Low | **Dep**: F2.4
- **Rollback**: `apt remove --purge sssd sssd-tools realmd adcli`

### F4.2 — Instalar SSSD en containers
- **Desc**: Instalar SSSD en cada container sg-* (sg-rojo, sg-azul, sg-verde, sg-amarillo, sg-monitoring).
- **Comando**: `pct enter <ctid>` → `apt install sssd sssd-tools realmd adcli`
- **Verif**: `sssd --version` en cada container
- **Esfuerzo**: M | **Riesgo**: Medium | **Dep**: F2.4
- **Rollback**: `apt remove --purge sssd sssd-tools realmd adcli` en cada container

### F4.3 — Configurar sssd.conf
- **Desc**: Copiar template de `/etc/sssd/sssd.conf` en cada host con valores del design (sección 3.3). Asegurar permisos 600.
- **Comando**: Editar `/etc/sssd/sssd.conf` con ipa_server, cache_credentials, offline_credentials_expiration, krb5_ticket_lifetime
- **Verif**: `chmod 600 /etc/sssd/sssd.conf`; `systemctl restart sssd`; `journalctl -u sssd` sin errores
- **Esfuerzo**: M | **Riesgo**: Medium | **Dep**: F4.1, F4.2
- **Rollback**: Restaurar `/etc/sssd/sssd.conf` desde backup

### F4.4 — Unir hosts a FreeIPA
- **Desc**: Ejecutar `ipa-client-install` en cada host para unirlo al dominio FreeIPA.
- **Comando**: `ipa-client-install --domain=gidas.internal --server=ipa.gidas.internal --enable-dns-updates`
- **Verif**: `getent passwd` muestra usuarios del dominio; `realm list` muestra el dominio
- **Esfuerzo**: M | **Riesgo**: High | **Dep**: F4.3, F2.2
- **Rollback**: `ipa-client-install --uninstall`

### F4.5 — Crear HBAC rules
- **Desc**: En FreeIPA, crear reglas HBAC para cada grupo AD: asociar grupo → hosts permitidos.
- **Comando**: `ipa hbacrule-add --hostcat=all gidas-admins-access`; `ipa hbacrule-add-user gidas-admins-access --group=gidas-admins`; repetir para cada grupo con hosts específicos
- **Verif**: `ipa hbacrule-find` lista todas las reglas
- **Esfuerzo**: M | **Riesgo**: Medium | **Dep**: F4.4
- **Rollback**: `ipa hbacrule-del <rule-name>` por cada regla

### F4.6 — Crear sudo rules en FreeIPA
- **Desc**: Configurar sudo rules: `gidas-admins` → ALL; grupos de subgrupos → comandos específicos.
- **Comando**: `ipa sudorule-add --cmdcat=all gidas-admins-sudo`; `ipa sudorule-add-user gidas-admins-sudo --group=gidas-admins`; `ipa sudorule-add-option gidas-admins-sudo --sudooption='!authenticate'`
- **Verif**: `ipa sudorule-find` lista todas las reglas
- **Esfuerzo**: S | **Riesgo**: Low | **Dep**: F4.4
- **Rollback**: `ipa sudorule-del <rule-name>` por cada regla

### F4.7 — Verificar AC3
- **Desc**: Probar SSH con credenciales AD desde un cliente Linux.
- **Comando**: `ssh <ad-user>@<host>` con password AD
- **Verif**: Shell obtenido. `id` muestra grupos AD. `sudo -l` muestra sudo rules.
- **Esfuerzo**: XS | **Riesgo**: Low | **Dep**: F4.6
- **Rollback**: N/A — verificación

### F4.8 — Verificar AC5 (HBAC enforcement)
- **Desc**: Crear usuario test en `gidas-azul` e intentar SSH a `sg-rojo`. Debe ser denegado.
- **Comando**: `ssh <gidas-azul-user>@sg-rojo` → debe fallar con "Access denied"
- **Verif**: Conexión rechazada antes del prompt de password
- **Esfuerzo**: S | **Riesgo**: Low | **Dep**: F4.7
- **Rollback**: Eliminar usuario test de AD

### F4.9 — Verificar AC6 (offline cache)
- **Desc**: Desconectar AD temporalmente (o simular caída), verificar login con cache ≥ 8 h.
- **Comando**: `iptables -A OUTPUT -d 192.168.1.117 -j DROP` en host Linux; luego `ssh <ad-user>@localhost`
- **Verif**: Login exitoso con credenciales cacheadas
- **Esfuerzo**: S | **Riesgo**: Medium | **Dep**: F4.7
- **Rollback**: `iptables -D OUTPUT -d 192.168.1.117 -j DROP`

### F4.10 — Verificar AC9 (ticket TTL)
- **Desc**: Confirmar que Kerberos ticket lifetime ≤ 24 h.
- **Comando**: `klist -l` o `klist -v` después de `kinit`
- **Verif**: Ticket lifetime ≤ 24h como configurado en `krb5_ticket_lifetime`
- **Esfuerzo**: XS | **Riesgo**: Low | **Dep**: F4.7
- **Rollback**: N/A — verificación. Ajustar en sssd.conf si es necesario.

---

## Fase 5 — Backups + Documentación

Asegurar continuidad operativa y procedimientos documentados.

### F5.1 — Configurar backup FreeIPA
- **Desc**: Crear script `/usr/local/bin/ipa-backup-cron.sh` y cron diario para `ipa-backup --online --data`.
- **Comando**: `crontab -e` → `0 2 * * * /usr/local/bin/ipa-backup-cron.sh`
- **Verif**: Ejecutar script manualmente; verificar archivo `.tar.gz` en `/var/lib/ipa/backup/`
- **Esfuerzo**: S | **Riesgo**: Low | **Dep**: F2.2
- **Rollback**: Remover cron job y script

### F5.2 — Configurar backup AD
- **Desc**: En VM-DC1, configurar Windows Server Backup schedule diario. Tomar snapshot PVE de ambas VMs.
- **Comando**: `wbadmin enable backup -addtarget:\\<network-share> -schedule:02:00 -include:C: -allCritical -quiet`; en pve-ad: `qm snapshot <ipa-vmid> pre-cambio`
- **Verif**: `wbadmin get versions` muestra backup. Snapshot visible en PVE.
- **Esfuerzo**: S | **Riesgo**: Low | **Dep**: F0.4
- **Rollback**: `wbadmin delete backup`; `qm delsnapshot <vmid> pre-cambio`

### F5.3 — Rotar password AD admin
- **Desc**: Cambiar password del admin de VM-DC1 desde `hlvs.2025` a un nuevo password seguro. Documentar en SOPS.
- **Comando**: En AD: `net user Administrator <new-password>`; en Linux: `sops secrets/proxmox.yaml`
- **Verif**: `ssh Administrator@192.168.1.117` con nuevo password funciona
- **Esfuerzo**: S | **Riesgo**: High | **Dep**: F5.2
- **Rollback**: Restaurar password anterior desde SOPS backup

### F5.4 — Verificar AC7
- **Desc**: Confirmar que `secrets/proxmox.yaml` está encriptado con SOPS y contiene credenciales AD.
- **Comando**: `sops -d secrets/proxmox.yaml`
- **Verif**: Output muestra passwords en texto plano (sin error de decrypt)
- **Esfuerzo**: XS | **Riesgo**: Low | **Dep**: F5.3
- **Rollback**: N/A — verificación

### F5.5 — Verificar AC10
- **Desc**: Ejecutar backup FreeIPA manual y verificar que AD backup job existe.
- **Comando**: En FreeIPA: `ipa-backup --online --data`; en AD: `wbadmin get versions`
- **Verif**: Ambos comandos retornan éxito
- **Esfuerzo**: XS | **Riesgo**: Low | **Dep**: F5.1, F5.2
- **Rollback**: N/A — verificación

### F5.6 — Documentar procedimientos (AC11)
- **Desc**: Crear `docs/identity/onboarding.md` y `docs/identity/offboarding.md` con procedimientos paso a paso.
- **Verif**: Archivos existen en `docs/identity/` con contenido completo
- **Esfuerzo**: M | **Riesgo**: Low | **Dep**: F5.5
- **Rollback**: `git rm docs/identity/onboarding.md docs/identity/offboarding.md`

---

## Resumen de Dependencias

```
F0.1 ─► F0.2 ─► F0.4 ─► F0.5
  │        │
  └──► F0.3    └──► F0.6 ─► F1.1 ─► F1.2 ─► F1.3 ─► F1.4 ─► F1.5 ─► F1.6 ─► F1.7 ─► F1.8
                                                                            │
                                                                            └► F2.1 ─► F2.2 ─► F2.3 ─► F2.4
                                                                                                    │
                                                                                     ┌────────────────┤
                                                                                     ▼                ▼
                                                                              F3.1 ─► F3.2 ─► F3.3    F4.1
                                                                                      │         │      │
                                                                                      ▼         ▼      ▼
                                                                                   F3.4       F4.2    F4.3 ─► F4.4 ─► F4.5 ─► F4.6 ─► F4.7
                                                                                                                │         │         │
                                                                                                                ▼         ▼         ▼
                                                                                                            F4.8       F4.9      F4.10
                                                                    F5.1 ◄──────────────────── F2.2 ──┐
                                                                    F5.2 ◄──── F0.4 ──┐               │
                                                                      │                │               │
                                                                      ▼                ▼               ▼
                                                                    F5.3 ─► F5.4    F5.5 ◄────────────┘
                                                                      │
                                                                      ▼
                                                                    F5.6
```
