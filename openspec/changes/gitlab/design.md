# Design: GitLab CE — VCS On-Premise

## Technical Approach

Omnibus GitLab CE en VM Ubuntu 22.04 dedicada en pve-desa01. La VM se provisiona vía `qm` desde un script local; la instalación de GitLab se ejecuta dentro de la VM vía SSH. Tres fases: (1) crear VM, (2) instalar/configurar Omnibus, (3) habilitar backups. Consistente con spec — cubre provisioning, Omnibus, HTTPS, SSH, backups, autenticación local.

## Architecture Decisions

| Decisión | Opción elegida | Alternativas | Rationale |
|---|---|---|---|
| Método instalación | Omnibus package | Docker, source, Helm | Omnibus = single package, bundled PostgreSQL/Redis, mantenimiento mínimo. Docker añade capa innecesaria para 1 VM. |
| DB y cache | Bundled (Omnibus default) | PostgreSQL/Redis externos | Omnibus gestiona upgrades y snapshots coherentes. Externalizar = más piezas sin beneficio para single-node. |
| HTTPS challenge | HTTP-01 (default), DNS-01 fallback | Solo DNS-01 | HTTP-01 más simple si puerto 80 alcanzable. Omnibus soporta ambos nativamente. |
| SSH Git port | 2222 host → 22 VM | Port 22 directo | 2222 evita conflicto con SSHD host, NAT limpio con DNAT. |
| Backup strategy | Dual: gitlab-backup diario + snapshot PVE semanal | Solo uno u otro | gitlab-backup = data-level (repos, DB, config). Snapshot = VM-level (restore completo inmediato). Defensa en profundidad. |
| Scripting pattern | 00-env.sh + scripts numerados | Ansible, Terraform | Consistente con `scripts/` existente. Bash + SSH es el patrón del proyecto. |

## Data Flow

```
Usuario ──443──→ Host (pve-desa01)
   │                 │
   │          iptables PREROUTING DNAT
   │                 │
   ├──443──→ VM:443 (NGINX → Puma → GitLab Rails)
   │
   └──2222──→ Host ──DNAT──→ VM:22 (gitlab-sshd)
```

Backup flow:
```
VM cron ──→ gitlab-backup create ──→ /var/opt/gitlab/backups/*.tar
PVE cron ──→ qm snapshot <vmid> ──→ snapshot en storage
```

## File Changes

| File | Action | Description |
|---|---|---|
| `gitlab/install/00-env.sh` | Create | Variables: VMID, IP, hostname, disk, resources, GitLab domain |
| `gitlab/install/01-provision-vm.sh` | Create | `qm create` con specs 4vCPU/8GB/80GB + cloud-init Ubuntu 22.04 |
| `gitlab/install/02-install-gitlab.sh` | Create | SSH+apt: install Omnibus, escribir `gitlab.rb`, reconfigure, test status |
| `gitlab/install/03-configure-https.sh` | Create | Let's Encrypt: `letsencrypt['enable'] = true`, cert renew check |
| `gitlab/install/04-configure-ssh.sh` | Create | Host iptables DNAT 2222→VM:22, gitlab-sshd config, test clone |
| `gitlab/install/05-firewall.sh` | Create | Host ufw/nftables: allow 80, 443, 2222 desde LAN |
| `gitlab/backup/00-env.sh` | Create | Backup paths, retention, PVE snapshot schedule |
| `gitlab/backup/01-gitlab-backup.sh` | Create | `gitlab-backup create` via SSH, copia a backup storage |
| `gitlab/backup/02-pve-snapshot.sh` | Create | `qm snapshot <vmid> gitlab-weekly-<date>` |
| `gitlab/backup/03-restore.sh` | Create | Restore procedure: stop services, restore tar, reconfigure, start |
| `gitlab/backup/cron-gitlab-backup` | Create | Crontab: daily backup entry |
| `gitlab/backup/cron-pve-snapshot` | Create | Crontab: weekly snapshot entry |
| `gitlab/docs/runbook.md` | Create | Operational runbook: start/stop, backup verify, restore, upgrades |

## Interfaces / Contracts

**VM Spec**: 4 vCPU, 8 GB RAM, 80 GB SSD, Ubuntu 22.04 LTS, IP 192.168.1.41/24

**Port mapping**:
| Puerto host | Puerto VM | Uso |
|---|---|---|
| 80 | 80 | HTTP (Let's Encrypt challenge) |
| 443 | 443 | HTTPS (GitLab Web UI + API) |
| 2222 | 22 | SSH Git |

**gitlab.rb keys**:
```ruby
external_url 'https://gitlab.gidas.local'
letsencrypt['enable'] = true
gitlab_rails['gitlab_shell_ssh_port'] = 2222
nginx['listen_port'] = 80
nginx['listen_https'] = false
```

## Testing Strategy

| Layer | What to Test | Approach |
|---|---|---|
| Sintaxis | Todos los .sh | `bash -n` en cada script |
| Provision | VM creada con specs correctas | `qm config <vmid>` verifica vCPU, RAM, disk |
| Smoke | GitLab funcionando | `gitlab-ctl status` + curl health endpoint |
| Backup | Restauración funcional | Restaurar tar en VM temporal, clonar repo, comparar |
| E2E | Flujo completo | `git clone ssh://git@host:2222/grupo/test.git` + push + Web UI |

## Migration / Rollout

**Rollback**:
1. `qm stop <vmid> && qm destroy <vmid>`
2. Restaurar snapshot PVE previo si existe
3. Revertir reglas firewall/iptables (DNAT 2222, 80, 443)
4. Sin cambios en sistemas existentes — rollback limpio

**No data migration required** — instalación greenfield.

## Open Questions

- [ ] Confirmar IP estática: ¿192.168.1.41 disponible en la subred?
- [ ] ¿Se prefiere DNS-01 desde el inicio o probar HTTP-01 primero?
- [ ] ¿Existe template cloud-init Ubuntu 22.04 en PVE o crear desde ISO?
- [ ] Retention de snapshots PVE semanales — ¿mantener 4 semanas?
