# Change: GitLab CE — Deploy en pve-desa04 + Migración

## Intent

Migrar GitLab del nodo `pve-desa01` (config incorrecta) a `pve-desa04` con OVMF UEFI, disco 80G, y configuración correcta de red. Dejar operativa la herramienta con HTTPS, SSH Git, autenticación LDAP contra AD, sincronización de grupos, y backups automáticos.

## Scope

### In Scope
- ✅ Destrucción de VM 201 en `pve-desa01` (SeaBIOS, 10G, display serial0)
- ✅ Clonación de template `rocky-10-template` (ID 108, OVMF UEFI) en `pve-desa04`
- ✅ Redimensionamiento a 80G, 4vCPU/8GB
- ✅ IP estática 192.168.1.41/24
- ✅ DNS en MikroTik: `gitlab.gidas.local`
- ✅ Instalación GitLab CE 19.0.2 (Omnibus) con HTTPS self-signed
- ✅ SSH Git puerto 2222 DNAT → VM:2222 (gitlab-sshd)
- ✅ Integración LDAP con AD GDC01 (bind infrait/Gidas2026!)
- ✅ Token API para automatización
- ✅ Importación de 17 usuarios AD a GitLab
- ✅ Creación de 7 grupos GitLab con mapeo AD
- ✅ Script sync AD → GitLab (grupos y roles)
- ✅ Backup diario (cron 02:00) + snapshot semanal PVE (dom 03:00)
- ✅ Firewall PVE host (80, 443, 2222)
- ✅ Documentación de avance, runbook, y SDD

### Out of Scope
- Let's Encrypt (dominio `.local` no soportado — se usa self-signed)
- Migración de datos (no había datos previos)
- CI/CD o integración con herramientas externas
- Prueba de restore de backup

## Capabilities

### New Capabilities
- `gitlab/install/00-env.sh`: Configuración apuntando a `pve-desa04` con credenciales AD y token API
- `gitlab/docs/avance.md`: Informe de avance del deploy
- `gitlab/scripts/sync-ad-members.sh`: Sincronización AD → GitLab (Owner/Maintainer/Developer)
- `gitlab/backup/01-gitlab-backup.sh`, `02-pve-snapshot.sh`, `03-restore.sh`, `04-verify-restore.sh`
- Backup wrapper `/root/gitlab-backup.sh` en VM
- Snapshot wrapper `/root/pve-gitlab-snapshot.sh` en PVE host
- Crontabs: `/etc/cron.d/gitlab-backup` (diario), `/etc/cron.d/gitlab-pve-snapshot` (semanal)

### Modified Capabilities
- `gitlab/install/01-provision-vm.sh`: Actualizado para usar `qm clone` desde template 108 con `--ide2 local-lvm:cloudinit`
- `gitlab/install/02-install-gitlab.sh`: Fix `VM_NAME` → `VM_HOSTNAME`
- `/etc/gitlab/gitlab.rb` en VM: LDAP bind, gitlab-sshd en 0.0.0.0:2222, HTTPS self-signed
- Reglas iptables en PVE host: DNAT puerto 2222 → VM:2222, firewall 80/443/2222
- Main spec actualizada: `openspec/specs/vcs/gitlab/spec.md`

## Approach

1. Destruir VM 201 en pve-desa01
2. Clonar template ID 108 (OVMF UEFI) en pve-desa04
3. Configurar cloud-init con `--ide2 local-lvm:cloudinit` forzado
4. Resize disco a 80G, ajustar vCPU y RAM
5. Configurar IP estática y hostname vía nmcli (cloud-init no aplicó por primer boot sin ISO)
6. Ajustar SELinux (equivalencia `/var/opt` → `/opt` conflictúa con GitLab)
7. Instalar GitLab CE 19.0.2 vía Omnibus
8. Configurar HTTPS self-signed, Puma, Sidekiq, gitlab-sshd
9. Agregar DNS en MikroTik
10. Configurar DNAT 2222 → VM:2222 y firewall
11. Activar LDAP bind con infrait/Gidas2026!
12. Generar token API y crear script `sync-ad-members.sh`
13. Importar usuarios AD y crear grupos GitLab
14. Configurar backups (cron diario + snapshot semanal)
15. Documentar y archivar cambio
