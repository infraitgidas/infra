# Design: Gestor de Proyecto — Redmine

## Technical Approach

Stack Docker Compose (`redmine:6.1` + `postgres:16` + `nginx:1.29`) en LXC dedicado (CT 206) en `pve-ad`. A diferencia de `sg-monitoring` (binarios nativos), Redmine se deploya vía Docker Compose porque la imagen oficial de Redmine ya incluye el runtime Ruby + dependencias — evita compilar gems en el CT. Scripts numerados replican el patrón `scripts/` existente.

```
redmine/
├── 00-env.sh              ← vars (CT_ID, IP, versiones, secrets)
├── 01-create-ct.sh        ← crea CT vía API Proxmox
├── 02-deploy-stack.sh     ← instala Docker + deploy compose
├── 03-configure-ssl.sh    ← certs + nginx + firewall
├── 04-backup.sh           ← cron pg_dump + tarball
├── docker-compose.yml     ← servicios redmine + postgres + nginx
├── nginx/
│   ├── redmine.conf       ← reverse proxy virtualhost
│   └── ssl/               ← certs (creados por 03-configure-ssl.sh)
└── .env                   ← secrets (generado por 00-env.sh, gitignored)
```

## Architecture Decisions

### Decision: Docker Compose over native install

| Option | Tradeoff | Decision |
|--------|----------|----------|
| Native (Ruby + gems) | Compilar gems en CT liviano, mantenimiento manual de upgrades | ❌ |
| Docker Compose | Redmine oficial ya incluye runtime, upgrades = cambiar tag, mismo patrón expansión futura (GLPI, GitLab) | ✅ |

**Rationale**: La imagen `redmine:6.1` es oficial, incluye Passenger + gems precompilados. Docker Compose da aislamiento de procesos y upgrades atómicos. El CT con 4GB RAM corre el stack sin swap.

### Decision: Self-signed SSL (inicial) sobre Let's Encrypt

| Option | Tradeoff | Decision |
|--------|----------|----------|
| Let's Encrypt | Requiere dominio público + DNS visible desde Internet | ❌ |
| Self-signed | Red interna 192.168.1.0/24, sin dominio público | ✅ |
| mkcert CA local | Más fácil para trust interno, mismo effort | ❌ (grado extra de complejidad) |

**Rationale**: La red es 192.168.1.0/24 — no hay dominio público. Self-signed con `openssl` en el script de configuración. El cert se distribuye manualmente a clients. Se migra a Let's Encrypt si se expone públicamente.

### Decision: pg_dump sobre backup de volumen PostgreSQL

| Option | Tradeoff | Decision |
|--------|----------|----------|
| Backup volume PostgreSQL | Requiere detener DB o usar pg_start_backup() | ❌ |
| pg_dump via container | Consistente, portable, se restaura en cualquier Postgres | ✅ |
| pgBackRest | Overkill para single instance | ❌ |

**Rationale**: `pg_dump` vía `docker exec` produce backups portables y consistentes sin detener el servicio. Para failover real se evaluaría streaming replication, pero está fuera de scope.

## Data Flow

```
Internet (internal)
    │
    ▼
┌──────────┐    :443    ┌──────────┐    :3000    ┌──────────┐
│  Client  │───────────►│  nginx   │───────────►│  redmine │
└──────────┘            │  :80 ──►│             │  :3000   │
    ▲                   │  301 SSL│             └────┬─────┘
    │                   └──────────┘                 │
    │                                                │
    │                       ┌────────────────────────┤
    │                       │                        │
    │                       ▼                        ▼
    │                 ┌──────────┐            ┌──────────┐
    │                 │ postgres │            │ volumes  │
    │                 │  :5432   │            │ files/   │
    │                 └──────────┘            │ plugins/ │
    │                                         │ themes/  │
    │                                         └──────────┘
    │
    └── backup ──► /var/backups/redmine/ ← cron daily
                     ├── db/redmine_YYYYMMDD.sql.gz
                     └── files/redmine_files_YYYYMMDD.tar.gz
```

## File Changes

| File | Action | Description |
|------|--------|-------------|
| `redmine/00-env.sh` | Create | Variables de entorno: CT_ID=206, IP, versiones, credenciales |
| `redmine/01-create-ct.sh` | Create | Crea CT via `pvesh` en `pve-ad`, configura red + SSH |
| `redmine/02-deploy-stack.sh` | Create | Instala Docker Engine + deploy `docker compose up -d` |
| `redmine/03-configure-ssl.sh` | Create | Genera certs self-signed, configura nginx + firewall |
| `redmine/04-backup.sh` | Create | Cron: pg_dump + tarball de volúmenes |
| `redmine/docker-compose.yml` | Create | Servicios: redmine:6.1, postgres:16, nginx:1.29 |
| `redmine/nginx/redmine.conf` | Create | Virtualhost nginx reverse proxy + SSL |
| `redmine/.env` | Create | Secrets (gitignored): POSTGRES_PASSWORD, REDMINE_SECRET_KEY |
| `openspec/changes/redmine/design.md` | Create | Este documento |

## Interfaces / Contracts

```yaml
# docker-compose.yml
services:
  postgres:
    image: postgres:16
    volumes: [ pgdata:/var/lib/postgresql/data ]
    env_file: .env              # POSTGRES_PASSWORD, POSTGRES_DB=redmine
    healthcheck:
      test: ["CMD", "pg_isready", "-U", "redmine"]

  redmine:
    image: redmine:6.1
    depends_on: [ postgres ]
    volumes:
      - redmine_data:/usr/src/redmine/files
      - redmine_plugins:/usr/src/redmine/plugins
      - redmine_themes:/usr/src/redmine/public/themes
    environment:
      REDMINE_DB_POSTGRES: postgres
      REDMINE_DB_DATABASE: redmine
      REDMINE_DB_USER: redmine
      REDMINE_DB_PASSWORD: ${POSTGRES_PASSWORD}
      REDMINE_SECRET_KEY: ${REDMINE_SECRET_KEY}

  nginx:
    image: nginx:1.29
    ports: [ "443:443", "80:80" ]
    volumes:
      - ./nginx/redmine.conf:/etc/nginx/conf.d/redmine.conf:ro
      - ./nginx/ssl:/etc/nginx/ssl:ro
    depends_on: [ redmine ]
```

Volúmenes Docker nombrados — no bind mounts (los bind mounts del CT host complican permisos con el usuario `redmine` del container, uid 999).

## Testing Strategy

| Layer | What to Test | Approach |
|-------|-------------|----------|
| Script syntax | Cada `.sh` | `bash -n <script>` en CI/pre-commit |
| Deploy dry-run | `docker compose config` valida YAML | Ejecutar post-commit |
| Smoke test | HTTPS + login admin | `curl -k https://redmine.gidas.local/login` + grep admin |
| Backup integrity | `.sql.gz` | `gunzip -t` + `pg_restore --dry-run` |
| Restore drill | DB restore en contenedor temporal | Script `04-backup.sh --dry-run` valida sin escribir |

No hay test runner en el proyecto — validación vía shell scripts.

## Migration / Rollout

```
CT creado  →  Docker Engine  →  compose up  →  SSL config  →  backup cron
    1               2               3               4              5
```

Cada paso es idempotente y puede re-ejecutarse. Rollout en una tarde, sin ventana de mantenimiento porque es servicio nuevo.

**Rollback**: `docker compose down -v` (pierde datos) + `pvesh delete CT 206`. Los scripts se revierten con `git revert`. Backups existen pre-rollback si se ejecutó `04-backup.sh`.

## Open Questions

- [ ] Hostname DNS interno de Redmine (`redmine.gidas.local` o IP directa)? — depende de si DNS interno está operativo.
- [ ] Timing de `REDMINE_SECRET_KEY` — se genera con `openssl rand -hex 32` en `00-env.sh` o se pasa como variable manual?
