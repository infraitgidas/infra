# Design: Gestor CMDB — NetBox

## Technical Approach

NetBox v4.x desplegado vía Docker Compose oficial en VM Proxmox dedicada (pve-cmdb). Stack: NetBox (Django/Gunicorn) + PostgreSQL 15 + Redis 7 + Worker. Modelado jerárquico Sites → Racks → Devices → Clusters → VirtualMachines → IPAM. Descubrimiento automático vía scripts Python/Bash que consumen API externa (Proxmox, Mikrotik, LDAP) y escriben en NetBox API REST.

## Architecture Decisions

| Decisión | Opciones | Tradeoff | Decisión |
|----------|----------|----------|----------|
| Deploy target | VM Proxmox vs LXC | LXC más liviano pero Docker-in-LXC tiene overhead; VM aísla mejor | **VM Proxmox** (pve-cmdb, 2 GB RAM, 2 vCPU, 10 GB) |
| Proxmox discovery | NetBox-plugin oficial vs `proxmoxer` + API | Plugin oficial requiere NetBox Cloud/Enterprise; community usa scripting | **proxmoxer + NetBox API** — script Python |
| Secrets mgmt | NetBox native env vars vs SOPS | SOPS es el estándar del proyecto; env vars leak en compose | **SOPS + age** — cifrar API tokens en `secrets/cmdb.yaml` |
| Discovery schedule | Docker sidecar vs cron host | Sidecar añade complejidad; cron host es simple y consistente con el proyecto | **cron host** — scripts en `cmdb/scripts/` ejecutados desde el host |
| IPAM strategy | NetBox IPAM vs spreadsheet | NetBox IPAM es el core value de la CMDB | **NetBox IPAM** — prefixes, VLANs, IP ranges |

## Data Flow

```
┌──────────────────────────────────────────────────────┐
│                    HOST (pve-cmdb)                    │
│                                                       │
│  crontab (weekly)                                     │
│    ├─ cmdb/scripts/discover-proxmox.py  ──┐           │
│    ├─ cmdb/scripts/discover-mikrotik.py ──┤           │
│    └─ cmdb/scripts/sync-directory.py   ───┤           │
│                                           │           │
│    ┌─────────────────────────────────┐     │           │
│    │  Docker Compose                 │     │           │
│    │  ├─ netbox:4.x (Django/Gunicorn)│     │           │
│    │  ├─ postgres:15  ◄── volumen db │     │           │
│    │  ├─ redis:7                     │     │           │
│    │  └─ netbox-worker               │     │           │
│    └─────────────────────────────────┘     │           │
│                      ▲                     │           │
│         NetBox API REST :8000              │           │
│                      ◄─────────────────────┘           │
│                                                       │
│  ┌─────────────┐    ┌─────────────┐    ┌───────────┐  │
│  │ Proxmox API  │    │ Mikrotik API│    │ LDAP      │  │
│  │ (lectura)    │    │ REST (lect.)│    │ (lectura) │  │
│  └─────────────┘    └─────────────┘    └───────────┘  │
└──────────────────────────────────────────────────────┘
```

## File Changes

| File | Action | Description |
|------|--------|-------------|
| `cmdb/deploy/docker-compose.yml` | Create | Stack: netbox, postgres, redis, redis-cache, worker |
| `cmdb/deploy/netbox.env` | Create | Variables de entorno NetBox (secret_key, db, redis) |
| `cmdb/deploy/nginx.conf` | Create | Reverse proxy opcional para TLS |
| `cmdb/scripts/discover-proxmox.py` | Create | Descubrimiento Proxmox vía `proxmoxer` → NetBox API |
| `cmdb/scripts/discover-mikrotik.py` | Create | Descubrimiento Mikrotik vía API REST RouterOS |
| `cmdb/scripts/sync-directory.sh` | Create | Importación AD/FreeIPA vía LDAP |
| `cmdb/scripts/backup.sh` | Create | pg_dump + tar.gz de media |
| `cmdb/scripts/restore.sh` | Create | Restore desde backup |
| `cmdb/scripts/00-env.sh` | Create | Variables compartidas (hosts, tokens, rutas) |
| `cmdb/docs/deploy.md` | Create | Guía de instalación y configuración |
| `cmdb/docs/operations.md` | Create | Backup, restore, upgrade |
| `cmdb/docs/modeling.md` | Create | Modelo de datos NetBox (sites, device types, roles) |
| `secrets/cmdb.yaml` | Create | API tokens Proxmox, Mikrotik, LDAP credentials (SOPS) |
| `.gitignore` | Modify | Agregar `cmdb/deploy/netbox.env` (contiene secret_key) |

## Interfaces / Contracts

### NetBox API v4.x Endpoints Usados

```python
# Endpoints clave para scripts de discovery
NETBOX_API = "http://localhost:8000/api"

# POST /api/dcim/sites/           — crear site
# POST /api/dcim/device-types/   — crear tipo (ej: "Proxmox VE Node")
# POST /api/dcim/device-roles/   — crear rol (ej: "Hypervisor", "Router")
# POST /api/dcim/devices/        — crear device
# POST /api/virtualization/virtual-machines/ — crear VM/LXC
# POST /api/ipam/ip-addresses/   — asignar IP
# PATCH /api/dcim/devices/{id}/  — actualizar device existente
# GET  /api/dcim/devices/        — listar/filtrar (para idempotencia)
```

### Discovery Script Contract

Cada script de discovery sigue esta interfaz:
- Input: `00-env.sh` (API tokens, hostnames)
- Behavior: idempotente — upsert via name/ID match
- Output: log a stdout/stderr; exit code 0 = success
- Error: no modifica NetBox si falla conexión origen

## Testing Strategy

| Layer | What to Test | Approach |
|-------|-------------|----------|
| Deploy | `docker compose up -d` sin errores | Ejecución manual post-deploy. Verificar `docker ps` todos los containers healthy |
| Idempotencia | Ejecutar discovery scripts dos veces | Segunda ejecución no debe crear duplicados (upsert basado en slug/name) |
| Backup/Restore | Backup → drop DB → restore | Script `restore.sh` debe recuperar datos exactos |
| Upgrade | v4.0 → v4.1 en staging | Seguir guía oficial de upgrade NetBox + validar scripts contra nueva API |

Sin test runner disponible (infraestructura pura). Validación manual sobre staging.

## Migration / Rollout

1. **VM provisioning**: Crear VM pve-cmdb (2 GB RAM, 2 vCPU, 10 GB) en cluster Proxmox
2. **Docker Compose deploy**: `docker compose up -d` en la VM
3. **Setup inicial NetBox**: Crear superuser, generar API token
4. **Modelado manual**: Crear Sites, Device Types, Roles en UI
5. **Discovery scripts**: Ejecutar una vez manualmente, luego configurar cron semanal
6. **Backup test**: Ejecutar backup.sh y restaurar en staging
7. **Go live**: Apuntar equipo a `http://pve-cmdb.gidas.local:8000`

No migration de datos previos (no hay nada que migrar).

## Open Questions

- [ ] ¿DNS para `cmdb.gidas.local` o IP directa?
- [ ] ¿Se necesita TLS/SSL desde el día 1 o HTTP plano alcanza?
- [ ] ¿Proxmox API token requiere permisos específicos además de lectura?
