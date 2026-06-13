# GitLab CE — Runbook Operativo

> **VM**: `gitlab` (ID 201) en `pve-desa01`
> **Dominio**: `https://gitlab.gidas.local`
> **SSH Git**: `ssh://git@pve-desa01:2222/grupo/repo.git`
> **OS**: Rocky Linux 10 — GitLab CE (Omnibus)

## Índice

1. [Deploy](#deploy)
2. [Operación Diaria](#operación-diaria)
3. [Backups](#backups)
4. [Restore](#restore)
5. [Upgrades](#upgrades)
6. [Recovery ante Fallos](#recovery-ante-fallos)

---

## Deploy

### Prerequisitos

- Cloud-init template `rocky-10-standard` en storage `local-zfs`
- IP `192.168.1.41/24` disponible
- DNS: `gitlab.gidas.local` → `192.168.1.41`

### Pasos

```bash
cd gitlab/install
source 00-env.sh

# 1. Crear VM
./01-provision-vm.sh

# 2. Instalar GitLab
./02-install-gitlab.sh

# 3. Configurar HTTPS
./03-configure-https.sh

# 4. Configurar SSH Git
./04-configure-ssh.sh

# 5. Configurar firewall
./05-firewall.sh

# 6. Verificar todo
./06-verify.sh
```

## Operación Diaria

### Verificar estado

```bash
ssh root@192.168.1.41 "gitlab-ctl status"
```

Esperado: todos los servicios `run`.

### Acceder a la Web UI

- URL: `https://gitlab.gidas.local`
- Login con email/contraseña (primer login setea `root` password)
- `GITLAB_ROOT_PASSWORD` definido en `install/00-env.sh`

### Iniciar/detener servicios

```bash
ssh root@192.168.1.41 "gitlab-ctl start"
ssh root@192.168.1.41 "gitlab-ctl stop"
ssh root@192.168.1.41 "gitlab-ctl restart"
```

### Ver logs

```bash
# Todos los logs
ssh root@192.168.1.41 "gitlab-ctl tail"

# Servicio específico
ssh root@192.168.1.41 "gitlab-ctl tail nginx"
ssh root@192.168.1.41 "gitlab-ctl tail postgresql"
```

## Backups

### Backup diario automático

- **Horario**: 02:00 todos los días
- **Comando**: `gitlab-backup create` (omite artifacts y registry)
- **Destino**: `/var/opt/gitlab/backups/` dentro de la VM
- **Retención**: 7 días (purga automática)
- **Secrets**: `/etc/gitlab/gitlab-secrets.json` se respalda junto al backup

### Snapshot semanal PVE

- **Horario**: domingo 03:00
- **Comando**: `qm snapshot 201 gitlab-weekly-YYYYMMDD`
- **Retención**: 4 semanas (las más antiguas se eliminan automáticamente)
- **Propósito**: recovery completo a nivel VM

### Backup manual

```bash
cd gitlab/backup
source 00-env.sh
./01-gitlab-backup.sh
```

### Snapshot manual

```bash
cd gitlab/backup
source 00-env.sh
./02-pve-snapshot.sh
```

## Restore

### Restore desde backup .tar

```bash
cd gitlab/backup
source 00-env.sh

# Listar backups disponibles
ssh root@192.168.1.41 "ls -lh /var/opt/gitlab/backups/*.tar"

# Restaurar (necesita el path completo al .tar)
./03-restore.sh /var/opt/gitlab/backups/123456789_2025_01_01_14.0.0_gitlab_backup.tar
```

### Restore desde snapshot PVE

```bash
# En pve-desa01
qm rollback 201 gitlab-weekly-20250101

# Iniciar VM después del rollback
qm start 201
```

### Post-restore verification

1. Verificar servicios: `gitlab-ctl status`
2. Health check: `curl -I https://gitlab.gidas.local`
3. Clonar un repo de prueba: `git clone ssh://git@pve-desa01:2222/grupo/test.git`
4. Verificar usuarios en Web UI

## Upgrades

### Upgrade GitLab CE

```bash
ssh root@192.168.1.41

# 1. Backup antes de upgrade
gitlab-backup create

# 2. Actualizar paquete
dnf check-update
dnf install -y gitlab-ce

# 3. Reconfigurar
gitlab-ctl reconfigure

# 4. Verificar
gitlab-ctl status
```

### Upgrade de sistema (Rocky Linux)

```bash
ssh root@192.168.1.41

# 1. Backup completo
gitlab-backup create

# 2. Actualizar paquetes del sistema
dnf upgrade -y

# 3. Reboot si kernel se actualizó
reboot

# 4. Verificar después del reboot
gitlab-ctl status
```

## Recovery ante Fallos

### VM no arranca

```bash
# 1. Intentar start
qm start 201

# 2. Si no arranca, hacer rollback al snapshot más reciente
qm rollback 201 gitlab-weekly-20250101
qm start 201

# 3. Verificar
ssh root@192.168.1.41 "gitlab-ctl status"
```

### Pérdida de datos (corrupción)

```bash
# 1. Detener servicios
ssh root@192.168.1.41 "gitlab-ctl stop puma && gitlab-ctl stop sidekiq"

# 2. Restaurar desde backup
cd gitlab/backup
./03-restore.sh /var/opt/gitlab/backups/<backup-más-reciente>.tar

# 3. Verificar
./06-verify.sh
```

### Falla de disco VM

```bash
# 1. Crear nueva VM con mismo IP
cd gitlab/install
./01-provision-vm.sh

# 2. Instalar GitLab (misma versión)
./02-install-gitlab.sh

# 3. Restaurar backup
cd gitlab/backup
./03-restore.sh /path/al/backup.tar

# 4. Re-configurar HTTPS y SSH
cd gitlab/install
./03-configure-https.sh
./04-configure-ssh.sh
./05-firewall.sh
```

### Falla de snapshot/backup

1. Verificar espacio en disco: `df -h /var/opt/gitlab/backups`
2. Verificar crontab: `crontab -l | grep gitlab`
3. Verificar logs:
   - Backup: `tail -50 /var/log/gitlab-backup.log`
   - Snapshot: `tail -50 /var/log/gitlab-pve-snapshot.log`
4. Ejecutar manualmente para ver errores

## Configuración de Red

| Puerto | Protocolo | Uso |
|--------|-----------|-----|
| 80 | TCP | HTTP (Let's Encrypt challenge) |
| 443 | TCP | HTTPS (Web UI + API) |
| 2222 | TCP | SSH Git (DNAT → VM:22) |

### Reglas firewall (PVE host)

```bash
firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source address=192.168.1.0/24 port port=80 protocol=tcp accept'
firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source address=192.168.1.0/24 port port=443 protocol=tcp accept'
firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source address=192.168.1.0/24 port port=2222 protocol=tcp accept'
firewall-cmd --reload
```

## Referencias

- [GitLab Omnibus Documentation](https://docs.gitlab.com/omnibus/)
- [GitLab Backup/Restore](https://docs.gitlab.com/ee/raketasks/backup_restore.html)
- [Proxmox VM Snapshots](https://pve.proxmox.com/pve-docs/chapter-qm.html#_snapshots)
