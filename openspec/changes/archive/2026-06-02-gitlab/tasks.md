# Tasks: GitLab CE — VCS On-Premise

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | ~460 (13 files, all new) |
| 800-line budget risk | Low |
| Chained PRs recommended | No |
| Suggested split | Single PR |
| Delivery strategy | auto-chain |
| Chain strategy | size-exception |

Decision needed before apply: No
Chained PRs recommended: No
Chain strategy: size-exception
800-line budget risk: Low

> Presupuesto 800 líneas — estimación ~460 muy por debajo. Single PR directo.

### Suggested Work Units

| Unit | Goal | Likely PR | Notes |
|------|------|-----------|-------|
| 1 | Full GitLab CE: VM + Omnibus + HTTPS + SSH + backups + docs + tests | PR 1 | base: `feature/gitlab`; incluye tests y docs |

## Phase 1: Foundation — Environment

- [x] 1.1 Crear `gitlab/install/00-env.sh` con VMID, IP, hostname, disk, resources, GitLab domain
- [x] 1.2 Crear `gitlab/backup/00-env.sh` con rutas backup, retention, schedule PVE

## Phase 2: VM Provisioning

- [x] 2.1 Crear `gitlab/install/01-provision-vm.sh`: `qm create` 4vCPU/8GB/80GB + cloud-init Ubuntu 22.04. Error si recursos PVE insuficientes

## Phase 3: Instalación GitLab

- [x] 3.1 Crear `gitlab/install/02-install-gitlab.sh`: SSH + apt Omnibus, escribir `gitlab.rb`, reconfigure, `gitlab-ctl status`. Error si sin Internet
- [x] 3.2 Crear `gitlab/install/03-configure-https.sh`: Let's Encrypt enable + DNS-01 fallback si HTTP-01 falla
- [x] 3.3 Crear `gitlab/install/04-configure-ssh.sh`: iptables DNAT 2222→VM:22, gitlab-sshd, test clone SSH
- [x] 3.4 Crear `gitlab/install/05-firewall.sh`: ufw/nftables permitir 80, 443, 2222 desde LAN

## Phase 4: Backup System

- [x] 4.1 Crear `gitlab/backup/01-gitlab-backup.sh`: `gitlab-backup create` vía SSH + copia a backup storage
- [x] 4.2 Crear `gitlab/backup/02-pve-snapshot.sh`: `qm snapshot <vmid> gitlab-weekly-<date>`
- [x] 4.3 Crear `gitlab/backup/03-restore.sh`: stop services, restore tar, reconfigure, start
- [x] 4.4 Crear crontabs: `cron-gitlab-backup` (daily) + `cron-pve-snapshot` (weekly)

## Phase 5: Testing / Verification

- [x] 5.1 Syntax: `bash -n` en todos los .sh (validado en `06-verify.sh` Section A)
- [x] 5.2 Spec "Recursos correctos": `qm config <vmid>` confirma 4vCPU/8GB/80GB (`06-verify.sh` Section B)
- [x] 5.3 Spec "Instalación": `gitlab-ctl status` all "run" + HTTPS health endpoint 200 (`06-verify.sh` Sections C-D)
- [x] 5.4 Spec "Clonar/Push SSH": clone + push vía puerto 2222 + Web UI refleja cambios (`06-verify.sh` Section E + runbook.md)
- [x] 5.5 Spec "API REST": `GET /api/v4/projects` con token retorna JSON válido (`06-verify.sh` Section G)
- [x] 5.6 Spec "Autenticación": registro + login correcto + login fallido rechazado (`06-verify.sh` Section H)
- [x] 5.7 Spec "Restauración": restore tar en VM temporal + clonar repo + comparar (`04-verify-restore.sh`)

## Phase 6: Documentación

- [x] 6.1 Crear `gitlab/docs/runbook.md`: start/stop, backup verify, restore, upgrades
