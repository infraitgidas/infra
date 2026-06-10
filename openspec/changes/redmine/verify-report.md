# Verify Report: Redmine Implementation

**Date:** 2026-06-10
**Scope:** Code review of all implementation files against spec, design, and tasks
**Method:** Static analysis — no server execution

## Syntax Checks

| File | `bash -n` | YAML Parse |
|------|-----------|------------|
| `redmine/00-env.sh` | ✅ OK | — |
| `redmine/01-provision-vm.sh` | ✅ OK | — |
| `redmine/02-bootstrap-vm.sh` | ✅ OK | — |
| `redmine/03-deploy-stack.sh` | ✅ OK | — |
| `redmine/04-configure-ssl.sh` | ✅ OK | — |
| `redmine/05-backup.sh` | ✅ OK | — |
| `redmine/docker-compose.yml` | — | ✅ OK (`python3 yaml.safe_load`) |

All 6 shell scripts and the Compose file pass basic syntax validation.

---

## Spec Requirement Coverage

### Req 1: VM Infrastructure (01-provision-vm.sh)

| Scenario | Result | Evidence |
|----------|--------|----------|
| Creación de VM desde scripts | ✅ PASS | `qm clone` from `rocky-10-template`, `--cores 2`, `--memory 4096`, `qm resize scsi0 20G`. Cloud-init configures IP/gateway. |
| VM ID libre | ✅ PASS | `qm list \| grep -qw '${VM_ID}'` → exits with error if found, before any creation. |
| Usuario de acceso | ✅ PASS | `--ciuser infra --cipassword ...` via cloud-init. SSH wait loop up to 120s. `authorized_keys` from Proxmox host. |

**Notes:**
- `VM_PASS` is hardcoded in `00-env.sh` (line 21) and bypasses the SOPS/.env secrets mechanism. Unlike `POSTGRES_PASSWORD` and `REDMINE_SECRET_KEY`, there's no override via `secrets/redmine.yaml`. (→ **WARNING**)

---

### Req 2: Stack Redmine (docker-compose.yml + 03-deploy-stack.sh)

| Scenario | Result | Evidence |
|----------|--------|----------|
| Stack completo funcionando | ✅ PASS | `docker compose pull && docker compose up -d`. Wait-for loop checks all services "Up". Validates `http://localhost:3000/login` returns 200/302. |
| Persistencia de datos | ✅ PASS | Named volumes: `redmine_pgdata`, `redmine_files`, `redmine_plugins`, `redmine_themes`. No bind mounts for data. |

**Notes:**
- Redmine healthcheck (`curl -sf http://localhost:3000/`) depends on `curl` being present in the `redmine:6.1` container. The image is based on `ruby:3.3-slim-bookworm`, which typically does **not** include `curl`. This may cause the healthcheck to fail. (→ **WARNING**)
- Healthcheck failure won't break the stack but will affect `depends_on: condition: service_healthy` for nginx and compose status reporting.

---

### Req 3: SSL/TLS (nginx/redmine.conf + 04-configure-ssl.sh)

| Scenario | Result | Evidence |
|----------|--------|----------|
| HTTPS accesible | ✅ PASS | Self-signed cert generated with `openssl req -x509 -days 3650 -newkey rsa:2048`, SAN includes `DNS:${VM_FQDN},IP:${VM_IP}`. nginx reverse proxy to `redmine:3000`. |
| Redirección HTTP → HTTPS | ✅ PASS | `server { listen 80; return 301 https://$host$request_uri; }`. Validated with `curl -w '%{redirect_url}' http://localhost/`. |

**Notes:**
- `04-configure-ssl.sh` generates certs directly on the VM at `~/redmine/nginx/ssl/`, matching the compose volume mount `./nginx/ssl:/etc/nginx/ssl:ro`. ✅
- The HTTPS validation test (`curl -sk https://localhost/login`) works because the 443 server block acts as default for that port. ✅

---

### Req 4: Autenticación local

| Scenario | Result | Evidence |
|----------|--------|----------|
| Login de administrador | ✅ PASS | Default Redmine behavior — no LDAP/OAuth/SAML configured. Admin user `admin`/`admin` with forced password change on first login. |
| Creación de usuario local | ✅ PASS | Standard Redmine admin UI functionality. No custom auth implementation needed. |

**Notes:**
- This is purely Redmine's out-of-box behavior. No implementation gap.
- Task item 4.4 (post-deploy documentation of default credentials) is still **pending** in the task list.

---

### Req 5: Backup PostgreSQL (05-backup.sh)

| Scenario | Result | Evidence |
|----------|--------|----------|
| Dump programado | ✅ PASS | `docker exec ${PG_CONTAINER} pg_dump -U redmine redmine \| gzip > /var/backups/redmine/db/redmine_YYYYMMDD.sql.gz`. Cron via `--install-cron`. Retention: 14 days. |
| Restauración desde dump | ❌ **FAIL** | No restore script or mechanism exists anywhere. The spec explicitly requires this scenario. The design mentions `05-backup.sh --dry-run` for restore drill but it's not implemented. |

**Cross-cutting issues:**

1. **Combined tarball is broken** (→ **CRITICAL**)
   ```bash
   # 05-backup.sh lines 61-65
   cat redmine_files.tar.gz redmine_plugins.tar.gz redmine_themes.tar.gz > combined.tar.gz
   ```
   Concatenating gzip files with `cat` produces a multi-member gzip stream. Standard `tar xzf combined.tar.gz` **only extracts the first member** (redmine_files). Plugins and themes data is present in the file but **unreachable** via normal tar extraction.

2. **Cron path mismatch** (→ **CRITICAL**)
   ```bash
   # 05-backup.sh line 101
   CRON_LINE="0 2 * * * infra cd ${SCRIPT_DIR} && ./05-backup.sh ..."
   ```
   `SCRIPT_DIR` expands to the **local machine path** (e.g., `/home/user/infra/redmine`), but the cron is installed on the **remote VM** via SSH. The directory doesn't exist on the VM. The cron job will always fail.

   **Root cause:** The backup script is designed to run from the development machine (SSHes into the VM), but `--install-cron` installs the cron on the VM expecting the script to be present there.

---

### Req 6: Backup de archivos (05-backup.sh)

| Scenario | Result | Evidence |
|----------|--------|----------|
| Backup de volúmenes | ✅ PASS (with bug) | `docker run --rm -v ${VOLUME}:/data alpine tar czf ...` for each of the 3 volumes. |

**Notes:**
- The combined tarball bug described above affects this scenario. Individual volume files are created correctly but the final concatenation corrupts access to 2 of 3 volumes.
- "Copiar al storage interno de backups" — backup stays on the VM at `/var/backups/redmine/files/`. No off-host copy is implemented. (→ **SUGGESTION**)

---

### Req 7: Scripts reproducibles

| Scenario | Result | Evidence |
|----------|--------|----------|
| Deploy desde cero | ✅ PASS | Scripts numbered 00→05, each sources `00-env.sh`, prints next steps at the end. 02-bootstrap handles hello-world failure gracefully. 03-deploy creates remote directories. |
| Rollback completo | ⚠️ WARNING | No rollback script exists. The design describes manual steps (`docker compose down -v` + `qm stop/destroy`) but no automation. The spec says "el script DEBE liberar el VM ID" — no script implements this. |

**Notes:**
- The rollback scenario requires manual intervention. While the rollback procedure is documented in `design.md` (line 162), there's no executable artifact.
- VM ID availability check exists (Step 1 of 01-provision-vm.sh), so re-provisioning won't conflict.

---

## Design vs Implementation Consistency

| Item | Design Says | Implementation Says | Verdict |
|------|------------|-------------------|---------|
| nginx version | `1.29` (×3 in design.md) | `1.27-alpine` (00-env.sh + compose) | ❌ **MISMATCH** — update design or align implementation. |
| Proxmox node | `pve-desa` (spec + design) | `pve-desa01` (00-env.sh) | ⚠️ **INCONSISTENT** — `PM_NODE` is only used in log messages (actual SSH targets use `PM_IP`), but the mismatch causes confusion. |
| Secrets handling | `VM_PASS` should be overridable via secrets | `VM_PASS` is hardcoded, not in secrets loading block | ⚠️ **GAP** — unlike DB secrets. |
| Restore drill | `05-backup.sh --dry-run` mentioned | Not implemented | ❌ **MISSING** — task 4.3 also pending. |

---

## Consistency Across Scripts

| Check | Result |
|-------|--------|
| Variable names: all scripts source `00-env.sh` first | ✅ `SCRIPT_DIR=$(cd .../00-env.sh` pattern used everywhere |
| Volume names in compose match backup script | ✅ `redmine_files`, `redmine_plugins`, `redmine_themes` referenced in both |
| SSH target address | ✅ All use `${VM_USER}@${VM_IP}` or `root@${PM_IP}` consistently |
| Docker compose paths on VM | ✅ All scripts use `~/redmine/` as base dir on VM |
| SSL cert paths match compose mount | ✅ Generated at `~/redmine/nginx/ssl/`, compose mounts `./nginx/ssl:/etc/nginx/ssl:ro` |
| .env secrets: SOPS → .env → auto-gen | ✅ Implemented in 00-env.sh lines 46–58 |

---

## Task Completion Status

| Task | Status | Notes |
|------|--------|-------|
| 1.1 00-env.sh | ✅ Done | — |
| 1.2 01-provision-vm.sh | ✅ Done | — |
| 1.3 VM ID check + connectivity | ✅ Done | — |
| 2.1 02-bootstrap-vm.sh | ✅ Done | — |
| 2.2 docker-compose.yml | ✅ Done | — |
| 2.3 .env.example | ✅ Done | — |
| 2.4 03-deploy-stack.sh | ✅ Done | — |
| 3.1 nginx/redmine.conf | ✅ Done | — |
| 3.2 04-configure-ssl.sh | ✅ Done | — |
| 3.3 05-backup.sh | ✅ Done | Has bugs (see critical issues) |
| 3.4 Cron + gunzip -t | ✅ Done | Cron path broken (see critical issues) |
| 4.1 Syntax check (6/6 + YAML) | ✅ Done | Re-verified, all pass |
| 4.2 Smoke test | ❌ Pending | Requires deploy |
| 4.3 Backup integrity | ❌ Pending | Requires deploy |
| 4.4 Post-deploy docs | ❌ Pending | Not documented yet |

**Overall task progress:** 12/15 complete (80%), 3 tasks pending (deploy-dependent). 2 completed tasks have bugs.

---

## Findings Summary

### 🔴 CRITICAL (must fix before deployment)

| ID | File | Issue |
|----|------|-------|
| C1 | `05-backup.sh:61-65` | **Combined backup tarball is broken.** `cat a.tar.gz b.tar.gz c.tar.gz > combined.tar.gz` produces a multi-member gzip file where only the first member (redmine_files) is accessible via `tar xzf`. Plugins and themes data is lost on restore. Fix: keep separate per-volume files or use a staging directory with proper multi-directory tar. |
| C2 | `05-backup.sh:101` | **Cron path points to local machine, not VM.** `SCRIPT_DIR` expands to the local developer's path (e.g., `/home/user/infra/redmine`), but the cron entry is installed on the remote VM where this path doesn't exist. The cron will silently fail every night. Fix: deploy the backup script to the VM, or install cron on the local/CI machine. |
| C3 | *(entire project)* | **No restore mechanism exists.** Spec scenario "Restauración desde dump" requires the ability to restore from `.sql.gz` dumps. No script, no procedure, no `--dry-run` restore drill. Fix: add a `06-restore.sh` script or a `--restore` flag to `05-backup.sh`. |

### 🟡 WARNING (should fix, not blocking)

| ID | File | Issue |
|----|------|-------|
| W1 | `docker-compose.yml:47` | **Redmine healthcheck may not work.** The healthcheck uses `curl -sf http://localhost:3000/`, but the `redmine:6.1` image (based on `ruby:3.3-slim-bookworm`) may not include `curl`. Verify on deploy and replace with `wget` or a Ruby-based check if needed. |
| W2 | `00-env.sh:21` | **VM_PASS is hardcoded.** Unlike DB secrets, `VM_PASS` is not overridable via SOPS or `.env`. The `hlsv.2025` password is always used for cloud-init unless the file is manually edited. |
| W3 | *(entire project)* | **No rollback script.** Spec Escenario "Rollback completo" describes VM teardown, but no automation exists. |
| W4 | `design.md:5,99,131` vs `00-env.sh:35` | **NGINX_VERSION mismatch.** Design specifies `nginx:1.29` in three places. Implementation uses `1.27-alpine`. One of them is wrong — the design doesn't pin 1.29 with a reason, so likely the implementation is correct and the design needs updating. |
| W5 | `00-env.sh:11` vs spec/design | **PM_NODE inconsistency.** Spec and design say `pve-desa`, implementation uses `pve-desa01`. Low impact (IP is used for SSH), but causes confusion on first read. |

### 🔵 SUGGESTION (nice to have)

| ID | File | Issue |
|----|------|-------|
| S1 | `05-backup.sh` | Restore functionality: add `06-restore.sh` covering both DB (`gunzip -c \| docker exec -i pg_container psql`) and files (`tar xzf`). |
| S2 | `05-backup.sh:101` | Fix cron by making `--install-cron` deploy the backup script to the VM (e.g., `scp 05-backup.sh VM:~/redmine/`) and use a VM-local path in the cron entry. |
| S3 | `05-backup.sh:80-84` | Add log rotation for `/var/backups/redmine/backup.log` or use `logger` to syslog. |
| S4 | `05-backup.sh:52-70` | Fix combined tarball by using a staging dir approach or keep individual per-volume tarballs. |
| S5 | `tasks.md:54-56` | Update task list: mark 4.1 as re-verified, add new tasks for C1, C2, C3 fixes. |
| S6 | *(pre-commit)* | Add `bash -n` to pre-commit hooks as the design testing strategy suggests (currently manual). |

---

## Overall Assessment

```
Status: ❌ CHANGES REQUIRED
Next:   fixes-required
```

The implementation is **well-structured** — all scripts pass syntax checks, follow a consistent numbered pattern, source environment variables correctly, and cover most of the spec scenarios.

**However, 3 critical bugs** prevent this from being deployment-ready:

1. **Backup tarball corruption** (C1): Restoring from combined backups loses plugins and themes data silently.
2. **Cron job pointing to wrong machine** (C2): Automated daily backups will never run.
3. **No restore capability** (C3): A core spec requirement is completely unimplemented.

**Recommended action:** Fix C1, C2, and C3 before any deployment attempt. Address W1 during deployment testing (verify `curl` in redmine container). The remaining warnings are documentation/consistency issues that should be resolved for maintainability but won't block deployment.
