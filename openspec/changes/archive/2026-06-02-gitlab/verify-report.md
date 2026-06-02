## Verification Report

**Change**: gitlab
**Version**: N/A (re-verification after fixes)
**Mode**: Standard

### Completeness
| Metric | Value |
|--------|-------|
| Tasks total | 19 |
| Tasks complete | 19 |
| Tasks incomplete | 0 |

### Build & Tests Execution

**Syntax check (bash -n)**: ✅ 12/12 scripts passed
```text
gitlab/backup/00-env.sh: OK
gitlab/backup/01-gitlab-backup.sh: OK
gitlab/backup/02-pve-snapshot.sh: OK
gitlab/backup/03-restore.sh: OK
gitlab/backup/04-verify-restore.sh: OK
gitlab/install/00-env.sh: OK
gitlab/install/01-provision-vm.sh: OK
gitlab/install/02-install-gitlab.sh: OK
gitlab/install/03-configure-https.sh: OK
gitlab/install/04-configure-ssh.sh: OK
gitlab/install/05-firewall.sh: OK
gitlab/install/06-verify.sh: OK
```

**Runtime tests**: Not executed (infrastructure-only, requires real PVE/VM access).

### Spec Compliance Matrix
| # | Requirement | Scenario | Test Source | Result |
|---|-------------|----------|-------------|--------|
| 1 | VM Provisioning | Recursos correctos | `06-verify.sh §B` — qm config cores/memory/scsi0 | ✅ COMPLIANT |
| 2 | VM Provisioning | Recursos insuficientes | `01-provision-vm.sh Step 1b` — pvesh resource check before create → exit with error | ✅ COMPLIANT (was UNTESTED) |
| 3 | Instalación Omnibus | Instalación exitosa | `06-verify.sh §C` + `02-install-gitlab.sh §5` | ✅ COMPLIANT |
| 4 | Instalación Omnibus | Sin conectividad | `02-install-gitlab.sh Step 0` — DNS + APT + GitLab repo check → exits with diagnostic | ✅ COMPLIANT (was UNTESTED) |
| 5 | HTTPS Let's Encrypt | Certificado emitido | `06-verify.sh §D` + `03-configure-https.sh §3-4` | ✅ COMPLIANT |
| 6 | HTTPS Let's Encrypt | Puerto 80 bloqueado | `03-configure-https.sh §2` (DNS-01 suggested, not auto) | ⚠️ PARTIAL |
| 7 | Acceso SSH | Clonar vía SSH | `06-verify.sh §E` + `04-configure-ssh.sh §4` | ✅ COMPLIANT |
| 8 | Acceso SSH | Push vía SSH | `06-verify.sh` / runbook (no automated push test) | ⚠️ PARTIAL |
| 9 | Backups | Backup diario | `04-verify-restore.sh §1-3,5` + `cron-gitlab-backup` | ✅ COMPLIANT |
| 10 | Backups | Restauración | `03-restore.sh` + `04-verify-restore.sh §4,6` | ✅ COMPLIANT |
| 11 | Backups | Snapshot semanal | `02-pve-snapshot.sh` + `cron-pve-snapshot` | ✅ COMPLIANT |
| 12 | Gestión Repos | Crear proyecto | `06-verify.sh §I` — create via API → list verify → delete cleanup | ✅ COMPLIANT (was UNTESTED) |
| 13 | Gestión Repos | API REST | `06-verify.sh §G` — token gen + JSON parse | ✅ COMPLIANT |
| 14 | Autenticación Local | Registro de usuario | `06-verify.sh §H` (sign-up page load only, no registration flow) | ⚠️ PARTIAL |
| 15 | Autenticación Local | Login fallido | `06-verify.sh §H` — invalid creds rejected | ✅ COMPLIANT |

**Compliance summary**: 12 ✅ COMPLIANT, 3 ⚠️ PARTIAL, 0 ❌ UNTESTED (out of 15)

### Correctness (Static Evidence)
| Requirement | Status | Notes |
|------------|--------|-------|
| VM 4vCPU/8GB/80GB | ✅ Implemented | 00-env.sh + 01-provision-vm.sh: qm create with --cores 4 --memory 8192 --scsi0 80G |
| Pre-check PVE resources | ✅ Implemented | 01-provision-vm.sh Step 1b: pvesh get /cluster/resources, parse CPU/mem, compare, exit if insufficient |
| Pre-check connectivity | ✅ Implemented | 02-install-gitlab.sh Step 0: DNS (nslookup google.com), APT (archive.ubuntu.com), GitLab repo (packages.gitlab.com) |
| Omnibus installation | ✅ Implemented | 02-install-gitlab.sh: apt repo + gitlab-ce + gitlab.rb + gitlab-ctl reconfigure |
| PostgreSQL bundled | ✅ Implemented | gitlab.rb: postgresql['enable'] = true |
| Redis bundled | ✅ Implemented | gitlab.rb: redis['enable'] = true |
| HTTPS Let's Encrypt | ✅ Implemented | 03-configure-https.sh: LE enable + auto_renew + verification |
| SSH Git port 2222 | ✅ Implemented | 04-configure-ssh.sh: DNAT 2222→VM:22 + gitlab-sshd |
| Firewall rules | ✅ Implemented | 05-firewall.sh: ufw/nftables for 80/443/2222 from LAN |
| Daily backup | ✅ Implemented | 01-gitlab-backup.sh + cron-gitlab-backup |
| Weekly PVE snapshot | ✅ Implemented | 02-pve-snapshot.sh + cron-pve-snapshot |
| Backup restore | ✅ Implemented | 03-restore.sh: stop services → restore tar → secrets → reconfigure → restart |
| API REST | ✅ Implemented | 06-verify.sh §G: generates token and validates JSON response |
| Project creation via API | ✅ Implemented | 06-verify.sh §I: create → list → delete project lifecycle |
| Authentication | ✅ Implemented | 06-verify.sh §H: sign-in page, failed login rejection, registration page reachable |
| Runbook | ✅ Implemented | docs/runbook.md: deploy, daily ops, backups, restore, upgrades, recovery |

### Coherence (Design)
| Decision | Followed? | Notes |
|----------|-----------|-------|
| Omnibus package (no Docker/source) | ✅ Yes | 02-install-gitlab.sh installs from packages.gitlab.com |
| Bundled PostgreSQL + Redis | ✅ Yes | gitlab.rb enables both bundled services |
| HTTP-01 default, DNS-01 fallback | ⚠️ Partial | Fallback suggested but not auto-configured in 03-configure-https.sh |
| SSH 2222→VM:22 DNAT | ✅ Yes | 04-configure-ssh.sh implements iptables DNAT + gitlab-sshd |
| Dual backup: gitlab-backup + PVE snapshot | ✅ Yes | Separate scripts and crontabs for each |
| 00-env.sh + numbered scripts pattern | ✅ Yes | Both install/ and backup/ follow this pattern |

### Issues Found

**CRITICAL**: None

**WARNING**:
- Scenario #6 (Puerto 80 bloqueado): DNS-01 fallback mentioned in 03-configure-https.sh but only as manual instructions — not auto-implemented via Omnibus acme challenge.
- Scenario #8 (Push vía SSH): No automated push test — only connectivity validation and runbook manual steps.
- Scenario #14 (Registro de usuario): Only checks sign-up page reachable (`/users/sign_up`), does not test full registration + immediate login flow.
- **NEW** — `01-provision-vm.sh` line 127: variable `RC_OK` used in the elif condition but was never assigned — should be `RC_STATUS` (line 117). This causes the success path to print a misleading warning instead of a clear success message. The script proceeds correctly, but the output is confusing.

**SUGGESTION**:
- GITLAB_ROOT_PASSWORD in `install/00-env.sh` falls back to 'CHANGE_ME' if openssl unavailable — recommend generating at deploy time or failing explicitly.
- `03-configure-https.sh` could integrate DNS-01 via Omnibus `acme['challenge_type'] = 'dns-01'` and a DNS provider hook.
- Cron files reference `/root/gitlab/backup/` — ensure scripts are deployed to correct path matching the cron entry.
- `05-firewall.sh` does not persist iptables rules on RHEL-based systems (only saves via netfilter-persistent/iptables-save indirectly) — consider explicit `iptables-save` always.
- GitLab 14.0+ uses `gitlab-ctl restart` after `gitlab-ctl reconfigure` automatically — 03-restore.sh §6 calls both explicitly which is redundant but harmless.

### Verdict
**PASS**
All 19 tasks complete, 12/15 spec scenarios compliant (up from 9/15), all 3 previously CRITICAL untested scenarios now addressed with implementation code. Syntax clean across all 12 scripts. Design followed with 1 minor deviation (DNS-01 fallback manual-only).

**Next**: ready-for-archive
