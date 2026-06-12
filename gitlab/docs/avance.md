# Informe de Avance — GitLab CE

> **Feature**: VCS On-Premise — GitLab (Feature #2)
> **Fecha**: 2026-06-12
> **Sprint**: Deploy en pve-desa04 + migración desde pve-desa01
> **Rama**: `gitlab-gidas`

---

## Resumen Ejecutivo

GitLab CE 19.0.2 se encuentra instalado y operativo en el nodo `pve-desa04` del cluster Proxmox, con almacenamiento local (80G LVM-thin), BIOS OVMF UEFI, 4vCPU/8GB RAM, IP estática 192.168.1.41, HTTPS self-signed, y SSH Git por puerto 2222 con DNAT. La VM anterior en `pve-desa01` fue destruida por configuración incorrecta (SeaBIOS, disco 10G, display serial0).

**Estado**: Pendiente password de service account `infrait` para completar integración LDAP con AD.

---

## 1. VM GitLab — Estado Actual

| Atributo | Valor |
|----------|-------|
| **Nodo** | `pve-desa04` (192.168.1.14) |
| **VM ID** | 201 |
| **Hostname** | `gitlab.gidas.local` |
| **IP** | `192.168.1.41/24` (estática) |
| **vCPU** | 4 |
| **RAM** | 8192 MB |
| **Disco** | 80G (LVM-thin, local-lvm) |
| **BIOS** | OVMF (UEFI) |
| **SO** | Rocky Linux 10 |
| **Usuario VM** | `infra` / `hlvs.2025` |
| **GitLab CE** | 19.0.2 (Omnibus) |
| **Servicios** | 17/17 activos |
| **HTTPS** | Self-signed (`.local` no soporta Let's Encrypt) |
| **SSH Git** | `ssh://git@192.168.1.14:2222/grupo/repo.git` (DNAT) |
| **Firewall** | Puertos 80, 443, 2222 abiertos desde LAN |
| **DNS** | `gitlab.gidas.local` → 192.168.1.41 (MikroTik) |
| **LDAP** | Configurado en `gitlab.rb`, pendiente password bind |

---

## 2. Cambios Realizados

### 2.1 Infraestructura

- **Destrucción** de VM 201 en `pve-desa01` (SeaBIOS, 10G, `gitlab-test`)
- **Clonación** de template `rocky-10-template` (ID 108, OVMF UEFI) en `pve-desa04`
- **Redimensionamiento** de disco: 32G → 80G (partición + LVM + XFS)
- **Recursos**: 2 cores / 4GB RAM → 4 cores / 8GB RAM
- **IP estática**: 192.168.1.133 (DHCP) → 192.168.1.41/24 (nmcli)
- **Hostname**: `gidas-template` → `gitlab`
- **SELinux**: permissive (conflicto equivalencia `/var/opt` → `/opt`)
- **Firewall PVE host**: reglas iptables para puertos 80, 443, 2222 desde LAN
- **DNAT**: puerto 2222 → VM:22 (iptables PREROUTING + OUTPUT)

### 2.2 GitLab

- Instalación GitLab CE 19.0.2 vía Omnibus (RPM) con `--nogpgcheck`
- Configuración: HTTPS self-signed, PostgreSQL/Redis bundled, Puma 2 workers
- SSH Git: `gitlab-sshd` habilitado, puerto 2222
- LDAP configurado en `gitlab.rb` (AD GDC01, bind DN `infrait`), pendiente password
- Script `sync-ad-members.sh` creado (`gitlab/scripts/`) para sincronizar grupos AD → GitLab
- Backups: `/var/opt/gitlab/backups/`, retención 7 días

### 2.3 DNS

- Entrada A en MikroTik: `gitlab.gidas.local` → `192.168.1.41` (TTL 1d)

---

## 3. Problemas Encontrados y Soluciones

| Problema | Causa | Solución |
|----------|-------|----------|
| Cloud-init no genera ISO | Template 108 sin `ide2` cloudinit | Forzar `qm set --ide2 local-lvm:cloudinit` ANTES del primer boot |
| Interfaz no es `eth0` | Rocky Linux 10 usa nombres predecibles (`ens18`) | Configurar IP con `nmcli` |
| SELinux bloquea reconfigure | Equivalencia `/var/opt` → `/opt` conflictúa con fcontext de GitLab | `setenforce 0` + eliminar equivalencia + fcontext manual |
| Let's Encrypt falla | Dominio `.local` no es TLD válido | Cert self-signed |
| GPG key expired | Certificado GitLab RPM vencido | `dnf install --nogpgcheck` |
| SSH root denegado | Template bloquea root | `PermitRootLogin yes` en sshd_config |
| Ruta sdwan0 interfiere | VPN SD-WAN en estación de trabajo | Acceder vía PVE host |
| LDAP bind fails | Password de `infrait` no disponible | Pendiente — requiere password del service account |

---

## 4. Pendientes (Priorizados)

| # | Tarea | Prioridad | Estado |
|---|-------|-----------|--------|
| 1 | Configurar password de `infrait` en gitlab.rb + reconfigure | **Alta** | ⏳ Pendiente |
| 2 | Probar login LDAP con usuarios AD (`errodriguez`, etc.) | **Alta** | ⏳ Pendiente |
| 3 | Generar token API de GitLab + configurar `GITLAB_API_TOKEN` | **Alta** | ⏳ Pendiente |
| 4 | Ejecutar `sync-ad-members.sh` para mapear grupos AD | **Alta** | ⏳ Pendiente |
| 5 | Configurar backup diario (cron) | Media | ⏳ Pendiente |
| 6 | Configurar snapshot semanal PVE | Media | ⏳ Pendiente |
| 7 | Probar restore | Media | ⏳ Pendiente |
| 8 | Probar clone SSH vía puerto 2222 | Media | ⏳ Pendiente |
| 9 | Crear grupos y proyectos iniciales en GitLab | Media | ⏳ Pendiente |

---

## 5. Acceso

| Recurso | URL / Comando |
|---------|--------------|
| **GitLab Web UI** | `https://192.168.1.41` |
| **GitLab admin** | `root` / `WcxTlihTaQmMiKnbX5JfXzzqEiKYOl4JdfMyegHXi2s=` |
| **SSH Git** | `ssh://git@192.168.1.14:2222/grupo/repo.git` |
| **SSH VM** | `ssh infra@192.168.1.41` (pass: `hlvs.2025`) |
| **SSH root VM** | `ssh root@192.168.1.41` |

---

## 6. Referencias

- [GitLab Omnibus Documentation](https://docs.gitlab.com/omnibus/)
- [Runbook GitLab](../docs/runbook.md)
- [Estructura de grupos identity-management](../../identity-management/docs/identity/estructura-grupos-apps.md)
- [Proyecto Infra](../../PROJECT.md)
- [Change tasks](../../openspec/changes/gitlab-deploy/tasks.md)
