# Tasks: Dashboard Gestión de Identidades — gidas-identity CLI

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | ~850 |
| Review budget | 1000 lines (custom) |
| Chained PRs recommended | No |
| Delivery strategy | auto-forecast |

Decision needed before apply: No
Chained PRs recommended: No
Chain strategy: size-exception
400-line budget risk: Low (under 1000-line custom budget)

## F1 — Foundation (7 tasks, ~150 lines)

- [x] F1.1 Create `identity-dashboard/` dir tree + `requirements.txt` (click, pywinrm, paramiko, python-dotenv, PyYAML)
- [x] F1.2 Create `app/__init__.py` + `app/__main__.py` + `app/cli/main.py` (Click group skeleton with user/group/hbac stubs)
- [x] F1.3 Create `app/config.py` (dataclasses config model: AD, FreeIPA, SMTP + OU mapping + sAMAccountName builder)
- [x] F1.4 Create `app/secrets.py` (SOPS decrypt → dict, memory-only lifetime, no env/disk leak)
- [x] F1.5 Create `Dockerfile` (multi-stage: builder → python:3.12-slim, SOPS install, appuser non-root)
- [x] F1.6 Create `docker-compose.yml` (bind mounts for secrets/ssh-key/age) + `Dockerfile` entrypoint (`python -m app`)
- [ ] F1.7 Create `secrets/identity.yaml` (SOPS-encrypted skeleton) — **BLOCKED**: requires actual credentials + SOPS CLI

## F2 — AD Core (4 files, ~250 lines)

- [x] F2.1 Create `app/ad/client.py` (WinRM session with 3-retry, 2s/5s/10s backoff, 30s timeout, `run_ps()` method)
- [x] F2.2 Create `app/ad/user.py` (PS templates: New-ADUser, Set-ADUser, Remove-ADUser, Disable/Enable-ADAccount)
- [x] F2.3 Create `app/ad/password.py` (Set-ADAccountPassword + Set-ADUser ChangePasswordAtLogon + pwdLastSet=0)
- [x] F2.4 Create `app/ad/group.py` (Add/Remove/Get-ADGroupMember PS templates)

## F3 — FreeIPA Core (5 files, ~250 lines)

- [x] F3.1 Create `app/freeipa/client.py` (paramiko SSH + kinit admin via stdin, 2-retry, 3s/6s backoff, `run_ipa()` method)
- [x] F3.2 Create `app/freeipa/user.py` (ipa user-add/mod/find/del/disable/enable wrappers)
- [x] F3.3 Create `app/freeipa/password.py` (ipa passwd via stdin, password excluded from logs)
- [x] F3.4 Create `app/freeipa/group.py` (ipa group-add/remove-member wrappers)
- [x] F3.5 Create `app/freeipa/hbac.py` (ipa hbacrule-find/enable/disable + hbacsvc-find + hbactest) + `app/freeipa/sudo.py` (sudorule-*, sudocmd-*)

## F4 — CLI Commands (wire into Click, ~100 lines)

- [ ] F4.1 Wire `user` group: create, modify(--disable/--enable), list(--ou), show, delete, password(--reset --force-change)
- [ ] F4.2 Wire `group` group: add-member, remove-member, list
- [ ] F4.3 Wire `hbac` group: list(--user), toggle(--rule --enable/--disable)
- [ ] F4.4 Add orchestrator per command: sequential AD→FreeIPA with rollback on partial failure

## F5 — Email (3 files, ~100 lines)

- [ ] F5.1 Create `email/sender.py` (smtplib wrapper, non-blocking, logs warning on failure)
- [ ] F5.2 Create `email/templates.py` (plain-text: user-created with password, password-reset)
- [ ] F5.3 Wire `--notify` flag into user create + password commands, trigger email on success

## F6 — Integration & Verification (2 files, ~100 lines)

- [ ] F6.1 Create `scripts/gidas-identity` (bash wrapper: docker exec gidas-identity on pve-ad)
- [ ] F6.2 Add `--dry-run` mode to all commands (logs intent, skips remote execution)
- [ ] F6.3 Smoke test on pve-ad: build image, `--help`, verify non-root user, secrets not in `docker inspect`

## Implementation Sequence

```
F1 (Foundation)
 ├─► F2 (AD Core) — depends on F1 (config + secrets)
 ├─► F3 (FreeIPA Core) — depends on F1 (config + secrets)
 │
 └─► F4 (CLI Commands) — depends on F2 + F3
      │
      └─► F5 (Email) — depends on F4 for --notify wiring; sender+templates (F5.1+F5.2) can start after F1
           │
           └─► F6 (Integration) — depends on all previous
```

Ordering notes:
- F5.1+F5.2 can be done after F1 (only need config model), but F5.3 needs F4.
- Within each phase, tasks are ordered by dependency (client → operations → wiring).
- F6.3 (smoke test) requires all files created.
