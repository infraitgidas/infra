# Tasks: GitLab CE — Deploy en pve-desa04 + Migración

## Phase 1: Preparación

- [x] 1.1 Destruir VM 201 (`gitlab-test`) en pve-desa01
- [x] 1.2 Actualizar `gitlab/install/00-env.sh` para pve-desa04 (PM_NODE, PM_IP, template)
- [x] 1.3 Actualizar `gitlab/install/01-provision-vm.sh` para usar `qm clone` desde template

## Phase 2: VM Provisioning

- [x] 2.1 Clonar template ID 108 (`rocky-10-template`) → VM ID 201 en pve-desa04
- [x] 2.2 Configurar 4 vCPU / 8GB RAM / OVMF UEFI / efidisk0
- [x] 2.3 Redimensionar disco: 32G → 80G (partición + LVM + XFS)
- [x] 2.4 Configurar cloud-init con `--ide2 local-lvm:cloudinit` (forzar generación ISO)
- [x] 2.5 Configurar IP estática 192.168.1.41/24 (nmcli)
- [x] 2.6 Configurar hostname `gitlab.gidas.local`
- [x] 2.7 Habilitar SSH root y copiar claves

## Phase 3: DNS

- [x] 3.1 Agregar entrada A en MikroTik: `gitlab.gidas.local` → 192.168.1.41

## Phase 4: Instalación GitLab

- [x] 4.1 Instalar dependencias (epel, curl, policycoreutils, perl)
- [x] 4.2 Agregar repo Omnibus GitLab
- [x] 4.3 Instalar GitLab CE 19.0.2
- [x] 4.4 Configurar `/etc/gitlab/gitlab.rb` (HTTPS self-signed, Puma, Sidekiq, SSH port)
- [x] 4.5 Ejecutar `gitlab-ctl reconfigure`
- [x] 4.6 Verificar 17 servicios activos (gitlab-ctl status)
- [x] 4.7 Verificar Web UI HTTPS (HTTP 200)

## Phase 5: Configuración de Red (Pendiente)

- [ ] 5.1 Configurar DNAT 2222 → VM:22 en pve-desa04 (iptables)
- [ ] 5.2 Configurar firewall PVE host (puertos 80, 443, 2222)
- [ ] 5.3 Probar clone SSH via puerto 2222

## Phase 6: Integración AD (Pendiente)

- [ ] 6.1 Activar LDAP en `/etc/gitlab/gitlab.rb` (config AD)
- [ ] 6.2 Crear script `sync-ad-members.sh` para GitLab (basado en Redmine)
- [ ] 6.3 Configurar mapeo grupos AD → roles GitLab
- [ ] 6.4 Probar sincronización y acceso

## Phase 7: Documentación

- [x] 7.1 Crear informe de avance (`gitlab/docs/avance.md`)
- [x] 7.2 Crear change proposal (`openspec/changes/gitlab-deploy/proposal.md`)
- [x] 7.3 Actualizar `PROJECT.md` con estado actual

## Phase 8: Backups (Pendiente)

- [ ] 8.1 Configurar cron de backup diario (`gitlab-backup create`)
- [ ] 8.2 Configurar snapshot semanal PVE
- [ ] 8.3 Probar restore
