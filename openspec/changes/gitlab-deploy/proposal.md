# Change: GitLab CE — Deploy en pve-desa04 + Migración

## Intent

Migrar GitLab del nodo `pve-desa01` (config incorrecta) a `pve-desa04` con OVMF UEFI, disco 80G, y configuración correcta de red. Dejar operativa la herramienta con HTTPS, SSH Git, e integración con AD.

## Scope

### In Scope
- Destrucción de VM 201 en `pve-desa01` (SeaBIOS, 10G, display serial0)
- Clonación de template `rocky-10-template` (ID 108, OVMF UEFI) en `pve-desa04`
- Redimensionamiento a 80G, 4vCPU/8GB
- IP estática 192.168.1.41/24
- DNS en MikroTik: `gitlab.gidas.local`
- Instalación GitLab CE 19.0.2 (Omnibus) con HTTPS self-signed
- SSH Git puerto 2222 DNAT
- Script sync AD → GitLab (grupos y roles)
- Documentación de avance y cambios

### Out of Scope
- Let's Encrypt (dominio `.local` no soportado)
- Migración de datos (no había datos previos)
- CI/CD o integración con herramientas externas

## Capabilities

### New Capabilities
- `gitlab/install/00-env.sh`: Configuración apuntando a `pve-desa04`
- `gitlab/docs/avance.md`: Informe de avance del deploy

### Modified Capabilities
- `gitlab/install/01-provision-vm.sh`: Actualizado para usar `qm clone` desde template 108 con `--ide2 local-lvm:cloudinit`
- `gitlab/install/02-install-gitlab.sh`: Fix `VM_NAME` → `VM_HOSTNAME`

## Approach

1. Destruir VM 201 en pve-desa01
2. Clonar template ID 108 (OVMF UEFI) en pve-desa04
3. Configurar cloud-init con `--ide2 local-lvm:cloudinit` forzado
4. Resize disco a 80G, ajustar vCPU y RAM
5. Configurar IP estática y hostname vía nmcli (cloud-init no aplicó por primer boot sin ISO)
6. Ajustar SELinux (equivalencia `/var/opt` → `/opt` conflictúa con GitLab)
7. Instalar GitLab CE 19.0.2 vía Omnibus
8. Configurar HTTPS self-signed, Puma, Sidekiq, backups
9. Agregar DNS en MikroTik
10. Configurar DNAT 2222 → VM:22 y firewall
11. Crear script de sincronización AD → GitLab
