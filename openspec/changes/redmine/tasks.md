# Tasks: Gestor de Proyecto — Redmine

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | 350–420 |
| 400-line budget risk | Medium |
| Chained PRs recommended | No |
| Suggested split | Single PR |
| Delivery strategy | ask-on-risk |
| Chain strategy | pending |

Decision needed before apply: No
Chained PRs recommended: No
Chain strategy: pending
400-line budget risk: Medium

### Suggested Work Units

| Unit | Goal | Likely PR | Notes |
|------|------|-----------|-------|
| 1 | Stack Redmine completo + scripts + SSL + backups | PR 1 | Base: `main`. Autónomo, ~400 líneas |

## Planned

> Tasks pendientes de ejecutar — vacío inicialmente, se completa durante sdd-apply.

## Completed

### Phase 1: Infrastructure — VM en pve-desa

- [x] 1.1 Crear `redmine/00-env.sh` con variables: VM_ID=206, IP, versiones redmine/postgres/nginx, credenciales, paths
- [x] 1.2 Crear `redmine/01-provision-vm.sh`: `qm create` con cloud-init, 2 vCPU, 4 GB RAM, 20 GB disco, Rocky Linux 10
- [x] 1.3 Validar VM ID libre vía `qm list` antes de crear, check de conectividad post-creación

### Phase 2: Core — Bootstrap y Stack Docker

- [x] 2.1 Crear `redmine/02-bootstrap-vm.sh`: SSH como `infra`, instalar Docker CE desde repos oficiales, docker compose plugin
- [x] 2.2 Crear `redmine/docker-compose.yml`: servicios redmine:6.1 + postgres:16 + nginx:1.27-alpine con volúmenes nombrados y healthchecks
- [x] 2.3 Crear `redmine/.env.example` con POSTGRES_PASSWORD, REDMINE_SECRET_KEY, POSTGRES_DB=redmine (gitignored)
- [x] 2.4 Crear `redmine/03-deploy-stack.sh`: scp docker-compose.yml + .env a VM, `docker compose up -d`, validar estado

### Phase 3: SSL y Backups

- [x] 3.1 Crear `redmine/nginx/redmine.conf`: reverse proxy nginx a redmine:3000, SSL, redirect HTTP→HTTPS
- [x] 3.2 Crear `redmine/04-configure-ssl.sh`: openssl self-signed certs, configurar nginx, firewall puertos 80/443
- [x] 3.3 Crear `redmine/05-backup.sh`: cron pg_dump vía docker exec → .sql.gz, tarball volúmenes files/plugins/themes
- [x] 3.4 Configurar cron diario en VM host, validar integridad de backup con `gunzip -t`

### Phase 4: Verificación

- [x] 4.1 Syntax check: `bash -n` en cada script (7/7 OK + 06-restore.sh), `docker compose config` valida YAML
- [ ] 4.2 Smoke test: `curl -k https://redmine.gidas.local/login` — requiere deploy real
- [ ] 4.3 Backup integrity: `gunzip -t` dump + `pg_restore --dry-run` — requiere deploy real
- [x] 4.4 Documentar post-deploy: credenciales default admin, cambio de password obligatorio en primer login

### Phase 5: Fixes from verify report (2026-06-10)

- [x] 5.1 C1 — Combined tarball: separate per-volume files instead of `cat a.tar.gz b.tar.gz c.tar.gz`
- [x] 5.2 C2 — Cron path: deploy standalone backup script to VM, reference VM-local path in cron
- [x] 5.3 C3 — Restore: create `redmine/06-restore.sh` with --list, --restore-db, --restore-files, --dry-run
- [x] 5.4 W1 — Healthcheck: use ruby `net/http` instead of `curl` (not available in slim image)
- [x] 5.5 W2 — VM_PASS hardcoded: load from `secrets/redmine.yaml` with fallback to default
- [x] 5.6 W3 — Rollback: add rollback procedure comment to `01-provision-vm.sh`
- [x] 5.7 W4 — NGINX_VERSION mismatch: update design.md (3 refs) from `1.29` → `1.27-alpine`
- [x] 5.8 W5 — PM_NODE inconsistency: normalize `pve-desa01` → `pve-desa` in `00-env.sh`

### Post-deploy Notes

| Item | Value |
|------|-------|
| Default admin user | `admin` |
| Default admin password | `admin` (Redmine default — **cambiar en primer login**) |
| URL acceso interno | `http://localhost:3000` (dentro de la VM) |
| URL acceso red | `https://redmine.gidas.local` (desde red interna) |
| Certificado | Self-signed — distribuir `redmine.crt` a clients |
| Backups DB | `/var/backups/redmine/db/redmine_YYYYMMDD.sql.gz` |
| Backups files | `/var/backups/redmine/files/redmine_files_YYYYMMDD.tar.gz` (individual per volume) |
| Backups plugins | `/var/backups/redmine/files/redmine_plugins_YYYYMMDD.tar.gz` |
| Backups themes | `/var/backups/redmine/files/redmine_themes_YYYYMMDD.tar.gz` |
| Restore | `./06-restore.sh --list` / `--restore-all <DATE>` |
| Cron | `05-backup.sh --install-cron` (deploys script to VM + configures daily 02:00) |
