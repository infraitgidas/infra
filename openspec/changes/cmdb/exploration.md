## Exploration: Gestor CMDB — Configuration Management Database

### Current State

El proyecto **Grupo de Investigación Gidas** usa el stack: Proxmox (virtualización), Mikrotik (redes), Directory Servers (AD/FreeIPA). Actualmente no existe ningún sistema de inventario — todo es conocimiento tribal o planillas informales. El repositorio refleja esto con directorios vacíos (`proxmox/`, `mikrotik/`) y solo documentación suelta.

No hay CI/CD, no hay tests, no hay aplicación — es infraestructura pura en Shell/YAML/TOML.

### Affected Areas

- `cmdb/` — nuevo directorio para la feature
- `openspec/changes/cmdb/` — artefactos SDD de este cambio
- Eventualmente: scripts de descubrimiento, configuración de deploy, integraciones API
- Plan maestro (`openspec/specs/`) para agregar dominio CMDB

---

### Approaches

#### Approach A: **NetBox** — RECOMENDADO

NetBox es el estándar de-facto open source para CMDB/IPAM/DCIM. Originalmente creado en DigitalOcean, ahora mantenido por NetBox Labs.

| Aspecto | Detalle |
|---------|---------|
| **Stack** | Python/Django + PostgreSQL + Redis |
| **Deploy** | Docker Compose oficial — 5 servicios (netbox, postgres, redis, redis-cache, worker) |
| **Recursos** | ~2 GB RAM, 2 CPUs, ~10 GB disco — perfecto para infraestructura pequeña |
| **Licencia** | Apache 2.0 — sin restricciones |
| **API** | REST API completa + GraphQL |
| **Descubrimiento** | Manual + via script/API. NetBoxLabs tiene **integración oficial con Proxmox VE** que descubre automáticamente nodos, VMs, LXCs, interfaces, IPs, discos y VLANs |
| **Modelado de CI** | Sites → Racks → Devices (servidores físicos), VirtualMachines (VMs/LXCs), IPAM completo, VLANs, Clusters, Contacts. Custom fields para extender |
| **Integración Proxmox** | ✅ **Oficial**. Sincroniza: clusters, nodos como Devices, VMs/LXC como VirtualMachines, interfaces, IPs, discos, VLANs, tags. Bootstrap mode para setup inicial |
| **Integración ITSM** | ✅ Integración oficial con ServiceNow. También Ansible, Terraform/OpenTofu, n8n, webhooks |
| **Autenticación** | LDAP, Active Directory, SSO |
| **Mikrotik** | No hay integración oficial, pero API REST permite scripts para importar dispositivos RouterOS via API de Mikrotik |
| **Directory Servers** | LDAP/AD sync para usuarios |

**Pros:**
- Integración **oficial y mantenida** con Proxmox VE (descubrimiento automático)
- API de primera clase (REST + GraphQL)
- Ecosistema maduro: Ansible Collection, Terraform provider, Helm chart
- Modelo de datos flexible con custom fields, tags, relaciones entre objetos
- Comunidad enorme y activa
- Ideal como "source of truth" para IaC
- Camino claro hacia ITSM vía ServiceNow o n8n

**Cons:**
- No tiene helpdesk/ticketing nativo (es CMDB pura, no ITSM)
- Curva de aprendizaje media-alta para modelar correctamente
- No tiene descubrimiento automático de red (Mikrotik) — hay que scriptearlo
- La integración Proxmox es via NetBoxLabs Cloud/Enterprise (con limitaciones en community)

**Esfuerzo: Medio** (deploy Docker ~1h, modelado inicial ~4h, scripts de descubrimiento Mikrotik ~4h)

---

#### Approach B: **GLPI**

GLPI es un ITSM completo con módulo CMDB integrado. PHP/MySQL.

| Aspecto | Detalle |
|---------|---------|
| **Stack** | PHP + MySQL/MariaDB |
| **Deploy** | Docker disponible (no oficial, community). Instalación manual en LAMP/LEMP |
| **Recursos** | ~1 GB RAM, 1-2 CPUs — liviano |
| **Licencia** | GPL v3 |
| **API** | REST API (v9+), HL API (v11+) |
| **Descubrimiento** | GLPI Inventory + FusionInventory (agente a instalar en equipos) |
| **Modelado de CI** | Assets (computadoras, redes, software), CMDB con relaciones. Más orientado a parque informático que a DCIM |
| **Integración Proxmox** | No oficial. Se puede via plugin o scripts custom usando la API REST de Proxmox |
| **Integración ITSM** | ✅ **Nativo** — GLPI *es* un ITSM: helpdesk, cambios, incidentes, problemas, SLAs |
| **Autenticación** | LDAP, AD, OAuth, SSO |

**Pros:**
- ITSM completo + CMDB en un solo producto
- Helpdesk, ticketing, SLAs incluidos sin plugins extra
- Más liviano que NetBox en recursos
- Interfaz web familiar para helpdesk
- Soporta agentes de inventario (FusionInventory) para endpoints

**Cons:**
- **Sin integración oficial con Proxmox** — no descubre VMs automáticamente
- Modelo de datos orientado a desktops/endpoints, no a DCIM/infraestructura
- Sin IPAM nativo
- Descubrimiento requiere instalar agentes
- Interfaz menos moderna
- PHP stack — menos popular en infraestructura moderna

**Esfuerzo: Bajo-Medio** (deploy ~1h, modelado ~3h. Pero la falta de integración Proxmox suma trabajo manual)

---

### Recommendation

**NetBox es la opción recomendada.** Motivos clave:

1. **Stack tecnológico alineado**: Python/Django (más moderno, mejor API) vs PHP
2. **Integración Proxmox oficial**: descubrimiento automático de nodos, VMs, LXCs, IPs, discos, VLANs. Esto es el 80% del valor de la CMDB
3. **Modelo de datos pensado para infraestructura**: Sites → Racks → Devices → VirtualMachines → IPAM → VLANs. Calza perfecto con nuestro stack
4. **IPAM nativo**: gestionar el subneteo IP de Mikrotik y redes Proxmox
5. **Camino claro a ITSM**: vía n8n (workflow automation) conectado a un ITSM como iTop o el feature #4 planeado
6. **REST + GraphQL API**: permite scriptear en Bash/python la importación de equipos Mikrotik y servidores de directorio
7. **Estandar industrial**: NetBox es el SSoT (Single Source of Truth) más usado en infraestructura. Ansible, Terraform, todo el ecosistema lo soporta

GLPI quedaría mejor si se prioriza ITSM (helpdesk) sobre CMDB pura, pero como el feature ITSM está planificado por separado (feature #4), es mejor tener NetBox como CMDB dedicada.

---

### CI Modeling (Configuration Items)

```
┌─────────────────────────────────────────────────────┐
│                   NETBOX CMDB                        │
├─────────────────────────────────────────────────────┤
│  Sites                                               │
│  ├── Proxmox Datacenter                              │
│  │   ├── Racks (servidores físicos)                  │
│  │   │   ├── Devices: pve1, pve2, pve3 (Proxmox VE) │
│  │   │   │   └── Interfaces, IPs, Power              │
│  │   ├── Clusters (Proxmox Cluster)                  │
│  │   │   └── VirtualMachines (VMs + LXC)             │
│  │   │       ├── Redmine VM                         │
│  │   │       ├── GitLab VM                          │
│  │   │       └── ITSM VM (futuro)                   │
│  │   └── VirtualDisks                                │
│  │                                                    │
│  ├── Network Site (Mikrotik)                         │
│  │   ├── Devices: Mikrotik RB/CCR routers            │
│  │   │   └── Interfaces, IPs, VLANs                  │
│  │   ├── Prefixes (subnets)                          │
│  │   ├── IP Addresses                                │
│  │   └── VLANs                                       │
│  │                                                    │
│  └── Directory Services Site                         │
│      ├── Devices: AD Servers, FreeIPA Servers        │
│      └── Services (custom CI type)                   │
│                                                        │
│  Contacts / Roles (equipo Gidas)                     │
│  Custom Fields: proxmox_vmid, ha_state, etc.         │
│  Tags: production, development, discovered, proxmox  │
└─────────────────────────────────────────────────────┘
```

---

### Descubrimiento: Manual vs Automático

| Fuente | Método | Prioridad |
|--------|--------|-----------|
| Proxmox VE | **Automático** (integración oficial NetBox) | Alta |
| Mikrotik RouterOS | Script vía API REST de Mikrotik → NetBox API | Alta |
| AD/FreeIPA | Script de importación (LDAP query → NetBox API) | Media |
| Servicios (Redmine, GitLab) | Manual + API discovery | Baja (posterior) |

---

### Stack para Deploy

```
NetBox Docker Compose:
├── netbox (Python/Django + Gunicorn)
├── postgres:15 (base de datos)
├── redis:7 (caché + tareas async)
├── redis-cache:7 (caché de sesión)
└── netbox-worker (tareas background)

Requerimientos mínimos:
├── 2 GB RAM
├── 2 vCPU
├── 10 GB disco
└── Docker + Docker Compose
```

---

### Integración con ITSM (Feature #4)

NetBox tiene integración oficial con ServiceNow. Para un stack on-premise sin ServiceNow:

1. **n8n** (open source workflow automation) como puente NetBox → ITSM
2. **Webhooks** de NetBox: eventos de cambio en CIs → ITSM
3. **GraphQL API**: el ITSM puede consultar NetBox en tiempo real

Esto permite que cuando el feature #4 (ITSM) se implemente, ya tenga una fuente de datos estructurada.

---

### Risks

1. **NetBox Labs Cloud/Enterprise features**: la integración oficial de Proxmox usa NetBox Labs Cloud. La community edition requiere scripting manual usando la NetBox API y el endpoint `/cluster/resources` de Proxmox
2. **Mikrotik sin integración oficial**: habrá que desarrollar scripts de sincronización
3. **Over-engineering**: para infraestructura muy pequeña (1-2 servidores), NetBox puede ser excesivo. Alternativa: Snipe-IT (más simple) o planilla + documentación en Markdown
4. **Mantenimiento**: requiere upgrades periódicos de Docker images y PostgreSQL (como cualquier servicio)
5. **Adopción del equipo**: requiere que el equipo use y mantenga la CMDB actualizada

### Ready for Proposal
**Yes** — la exploración está completa. Recomiendo NetBox como CMDB. El siguiente paso es `sdd-propose` para formalizar alcance, enfoque y plan de implementación.
