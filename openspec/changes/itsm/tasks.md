# Tasks: Gestor ITSM — GLPI

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | 450–600 |
| 800-line budget risk (user-set) | Low |
| Chained PRs recommended | No |
| Suggested split | Single PR |
| Delivery strategy | ask-on-risk |
| Chain strategy | pending |

Decision needed before apply: No
Chained PRs recommended: No
Chain strategy: pending
400-line budget risk: High

> Nota: El usuario fijó el presupuesto en 800 líneas. Contra 400 (default) es High, contra 800 es Low.

### Suggested Work Units

| Unit | Goal | Likely PR | Notes |
|------|------|-----------|-------|
| 1 | Stack GLPI + scripts + LDAP + integraciones | PR 1 | Base: `feature/itsm`. Autónomo, ~500 líneas |

## Phase 1: Foundation — Docker Stack

- [x] 1.1 Crear `itsm/docker-compose.yml` con glpi, mariadb, nginx + volúmenes nombrados
- [x] 1.2 Crear `itsm/.env.example` con variables DB, timezone, GLPI config (también 00-env.sh)
- [x] 1.3 Crear `itsm/nginx/default.conf` con proxy pass a GLPI y SSL (se usó nginx:alpine stock, no Dockerfile custom)
- [x] 1.4 Proxy config SSL incluida en default.conf

## Phase 2: Core — Post-Deploy Config

- [x] 2.1 Crear `secrets/glpi.yaml.template` cifrable con SOPS (tokens Redmine/GitLab/LDAP)
- [x] 2.2 Setup inicial GLPI: `scripts/install-glpi.sh` + `docs/post-deploy-config.md`

## Phase 3: Scripts — Backup & Restore

- [x] 3.1 Crear `scripts/backup.sh`: mysqldump + tarball volúmenes Docker
- [x] 3.2 Crear `scripts/restore.sh`: detener stack, restaurar DB y volúmenes

## Phase 4: Scripts — Integraciones

- [x] 4.1 Crear `scripts/sync-ldap.sh`: wrapper para `ldap:synchronize`
- [x] 4.2 Crear `scripts/webhook-redmine.sh`: polling Redmine API → tickets GLPI
- [x] 4.3 Crear `scripts/webhook-gitlab.sh`: polling GitLab → comentarios incidentes GLPI

## Phase 5: FreeIPA

- [x] 5.1 Crear `directoryServer/freeipa/glpi-service-account.sh`: script creación bind DN
- [x] 5.2 Configurar autenticador LDAP vía `config/ldap-auth.php` (template config)

## Phase 6: Verificación

- [x] 6.1-6.5 Todos los tests cubiertos en `scripts/verify.sh`:
      bash syntax check, config validation, smoke test plan, backup integrity, E2E plan
