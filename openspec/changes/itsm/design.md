# Design: Gestor ITSM — GLPI

## Technical Approach

GLPI 10.x + MariaDB 10.11 + nginx en Docker Compose, desplegado en LXC Proxmox (2 vCPU / 4 GB RAM / 20 GB SSD). Autenticación LDAP nativa contra FreeIPA. Integraciones por polling vía cron + GLPI REST API. Backups semanales: `mysqldump` + tarball de volúmenes Docker.

## Architecture Decisions

| Decisión | Opción Elegida | Alternativa | Rationale |
|----------|---------------|-------------|-----------|
| **Stack Docker** | GLPI oficial + MariaDB + nginx | Apache + PHP nativo | Docker oficial GLPI Team reduce mantenimiento. MariaDB 10.11 por compatibilidad probada con GLPI 10.x |
| **Autenticación** | LDAP nativo de GLPI contra FreeIPA | Internal users + proxy auth | GLPI sincroniza usuarios/grupos sin plugins extra. Cuenta de servicio dedicada con bind read-only |
| **Webhooks salientes** | Cron polling via Shell + GLPI API | Plugin Webhook GLPI (PHP) | Stack del equipo es Shell. Sin dependencias PHP custom. Polling cada 5 min es suficiente para grupo chico |
| **Backup** | `mysqldump` + `tar` volúmenes | Docker volume driver backup | Portable, sin vendor lock-in. Restorable en cualquier Docker host |
| **Secrets** | SOPS + age (mismo patrón que `secrets/proxmox.yaml`) | ENV file plano | Consistente con el proyecto. API tokens cifrados en repo |
| **CMDB Boundary** | GLPI: activos IT (servidores, LXCs, contratos, licencias) | GLPI como única CMDB | NetBox (futuro Feature 3) será source of truth de infraestructura DC (racks, puertos, power). Sin sincronización activa entre ambos |

## Data Flow

```
                     ┌──────────────┐
                     │   FreeIPA    │
                     │   (LDAP)     │
                     └──────┬───────┘
                            │ LDAP bind (sincronización)
                            ▼
  ┌──────┐       ┌──────────────────┐       ┌──────────┐
  │ User │──────▶│  nginx:443       │──────▶│  GLPI    │──────▶│ MariaDB  │
  │      │       │  (HTTPS)         │       │  PHP-FPM │       │ :3306    │
  └──────┘       └──────────────────┘       └─────┬────┘       └──────────┘
                                                   │
                                     ┌─────────────┼─────────────┐
                                     │             │             │
                                     ▼             ▼             ▼
                              ┌──────────┐  ┌──────────┐  ┌──────────┐
                              │ Redmine  │  │  GitLab  │  │  Backup  │
                              │   API    │  │   API    │  │  Script  │
                              └──────────┘  └──────────┘  └──────────┘
```

**LDAP flow**: GLPI cron → `ldap:synchronize` → bind como `cn=glpi-svc,cn=sysaccounts,...` → importa usuarios en `cn=glpi-users` → asigna perfil según grupo.

**Webhook flow**: Cron cada 5 min → script `poll-redmine.sh` consulta `/issues.json?updated_on=>...` → POST a GLPI API (`/apirest.php/Ticket`). Flujo inverso para GitLab.

**Backup flow**: Cron semanal → `backup.sh` → `docker exec` mysqldump + `docker run --volumes-from` tar → `/var/backups/glpi/` comprimido con timestamp ISO.

## File Changes

| File | Acción | Descripción |
|------|--------|-------------|
| `itsm/docker-compose.yml` | Crear | Servicios glpi, mariadb, nginx con volúmenes nombrados |
| `itsm/.env` | Crear | Variables de entorno (DB, timezone, GLPI config) |
| `itsm/nginx/glpi.conf` | Crear | VirtualHost nginx con proxy pass a GLPI y SSL |
| `itsm/nginx/Dockerfile` | Crear | nginx image con certs autofirmados (dev) o path a certs reales |
| `itsm/scripts/backup.sh` | Crear | Dump SQL + tarball volúmenes con timestamp |
| `itsm/scripts/restore.sh` | Crear | Restore desde backup (detiene stack, restaura DB y volúmenes) |
| `itsm/scripts/poll-redmine.sh` | Crear | Polling Redmine API → creación de tickets GLPI |
| `itsm/scripts/poll-gitlab.sh` | Crear | Polling GitLab → comentarios en incidentes GLPI |
| `itsm/scripts/sync-ldap.sh` | Crear | Wrapper para `php bin/console ldap:synchronize` |
| `itsm/secrets/api-tokens.yaml` | Crear | SOPS-encrypted con tokens Redmine/GitLab |
| `directoryServer/freeipa/glpi-service-account.sh` | Crear | Script de creación del servicio LDAP |

## Interfaces / Contracts

### GLPI REST API
```bash
# Autenticación: App-Token (header) + Session-Token (login)
POST /apirest.php/initSession
Header: Content-Type: application/json
Header: App-Token: ${GLPI_APP_TOKEN}
Body: { "login": "...", "password": "..." }
# Response: { "session_token": "..." }
```

### Redmine → GLPI mapping
| Campo Redmine | GLPI Ticket field |
|---------------|------------------|
| `issue.subject` | `name` |
| `issue.description` | `content` |
| `issue.id` | `custom_fields[redmine_id]` |
| `project.id` | `itilcategories_id` (mapeo 1:1) |

### Secrets structure (SOPS)
```yaml
itsm:
  glpi:
    app_token: "xxx"
    admin_password: "xxx"
  integrations:
    redmine:
      url: "https://redmine.gidas.local"
      api_key: "xxx"
    gitlab:
      url: "https://gitlab.gidas.local"
      token: "xxx"
  ldap:
    bind_dn: "cn=glpi-svc,cn=sysaccounts,cn=etc,dc=gidas,dc=local"
    base_dn: "cn=users,cn=accounts,dc=gidas,dc=local"
```

## Testing Strategy

| Capa | Qué probar | Cómo |
|------|-----------|------|
| Deploy | Stack levanta en <120s | `docker compose up -d` + `docker compose ps` |
| Persistencia | Datos sobreviven restart | Crear ticket → `docker compose down` → `up -d` → verificar |
| LDAP | Login con credencial FreeIPA | `docker compose exec glpi php bin/console ldap:synchronize` |
| Backup | Dump + restore válido | backup.sh → destroy stack → restore.sh → verify |
| Webhook | POST a servicios | `curl` contra mock endpoint local |
| CMDB | Asset no replica | Crear en GLPI → verificar que NetBox no existe/ignora |

## Migration / Rollout

1. **Provisionar LXC** en Proxmox (2 vCPU / 4 GB RAM / 20 GB)
2. **Deploy base** — Docker Compose con credenciales internas (sin LDAP)
3. **Configurar LDAP** — cuenta de servicio en FreeIPA, sincronización inicial
4. **Activar integraciones** — webhooks/cron, registrar API tokens
5. **Backup + restore** — probar ciclo completo antes de producción
6. **Go live** — DNS glpi.gidas.local, certs, acceso al equipo

## Open Questions

- [ ] FreeIPA: ¿cuál es el DN base del grupo `glpi-users`? Se resuelve en implementación
