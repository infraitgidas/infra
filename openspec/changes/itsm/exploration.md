## Exploration: Gestor ITSM

### Current State

El proyecto **infra** del Grupo de Investigación Gidas no tiene actualmente ningún sistema ITSM. La gestión de incidentes, cambios y problemas se maneja de forma ad-hoc (conversaciones, planillas, correo). Según PROJECT.md, es la **Feature 4** y está marcada como ⏳ Pendiente. El directorio `itsm/` no existe aún.

La infraestructura actual es puramente on-premise:
- **Proxmox** — virtualización (sin contenido en el repo aún)
- **Mikrotik** — redes (sin contenido en el repo aún)
- **Directory Servers** — AD/FreeIPA (estructura creada, vacía)
- **Stack**: Shell, YAML, TOML — infraestructura pura, sin CI, sin tests

### Affected Areas

- `itsm/` — nuevo directorio para la feature (Docker Compose, config, scripts)
- `openspec/changes/itsm/` — artefactos SDD (exploration.md, proposal.md, etc.)
- `directoryServer/freeipa/` — integración LDAP para autenticación del ITSM
- `proxmox/` — VM o LXC donde se aloje el ITSM
- `docs/` — documentación de operación del ITSM
- `scripts/` — scripts de automatización para respaldo, integración con API

### Approaches

1. **iTop (Combodo) — CMDB-first, ITSM nativo**
   - **Stack**: PHP 8.1+ / MariaDB 10.6+ / Apache (LAMP clásico)
   - **Deploy**: Docker (comunidad, multi-imagen), VM/LXC, o manual
   - **CMDB**: Es su **corazón** — modelado de datos extensible con relaciones, análisis de impacto, dependencias entre CIs. Ideal porque Feature 3 (CMDB) y Feature 4 (ITSM) convergen en el mismo stack.
   - **LDAP/FreeIPA**: Sí — extensión oficial "Data collector for LDAP" sincroniza usuarios desde LDAP/AD
   - **API**: REST/JSON completa con autenticación por token y sesión
   - **ITIL**: Incidentes, Problemas, Cambios, Catálogo de Servicios, SLA, Base de Conocimiento, Service Desk multinivel
   - **Comunidad**: GPL v3, sin límites en la versión community. G2: 4.3/5
   - **Recursos mínimos**: 2 vCPU, 4 GB RAM, 10 GB disco (para <200 tickets/mes, <20 usuarios)
   - **Pros**: CMDB como base arquitectónica (no un agregado), UI intuitiva, análisis de impacto visual, extensible vía modelos de datos y módulos, maduro (10+ años)
   - **Cons**: No hay Docker oficial de Combodo (solo imágenes de comunidad), comunidad más chica que GLPI, requiere PHP tuning para producción
   - **Esfuerzo**: Medio

2. **GLPI (Teclib') — Asset management + ITSM**
   - **Stack**: PHP + MySQL/MariaDB (LAMP)
   - **Deploy**: Docker **oficial** (GLPI Team mantiene imágenes en Docker Hub), VM, LXC
   - **CMDB**: Sí — muy fuerte en inventario de hardware/software, contratos, licencias. Gestión de activos superior a iTop.
   - **LDAP/FreeIPA**: Sí — soporte nativo de LDAP con sincronización de usuarios y grupos
   - **API**: REST API documentada (`apirest.php`) con autenticación por token de sesión + App-Token
   - **ITIL**: Incidentes, Problemas, Cambios, Activos, Contratos, Base de Conocimiento, SLA
   - **Comunidad**: GPL v3, 11M+ usuarios, 5.9K estrellas GitHub, comunidad enorme. G2: 4.6/5
   - **Recursos mínimos**: 2 vCPU, 4 GB RAM, 10 GB disco
   - **Pros**: Docker oficial, comunidad enorme (más plugins, más soporte), asset management superior, maduro (15+ años), usado en +180 países
   - **Cons**: UI menos moderna que iTop, la CMDB es un módulo más no el núcleo arquitectónico, la sobrecarga de features puede ser abrumadora para equipo chico
   - **Esfuerzo**: Bajo-Medio

3. **Zammad — Helpdesk moderno multicanal**
   - **Stack**: Ruby on Rails / PostgreSQL / Elasticsearch (opcional)
   - **Deploy**: Docker Compose oficial (Zammad GmbH mantiene imágenes)
   - **CMDB**: **NO** — Zammad es un helpdesk/ticketing, no tiene CMDB nativa. Requeriría herramienta separada.
   - **LDAP/FreeIPA**: Sí
   - **API**: REST + GraphQL
   - **Comunidad**: AGPL v3. G2: 4.5/5
   - **Recursos mínimos**: 4 GB RAM (con ES), 2 vCPU
   - **Pros**: UI moderna, multicanal (email, chat, teléfono, redes sociales), Docker oficial impecable, ideal para customer support
   - **Cons**: **Sin CMDB** (obliga a Feature 3 separada), ITIL débil (change/problem management básico), más helpdesk que ITSM, mayor consumo de RAM
   - **Esfuerzo**: Bajo (pero incompleto — no cubre CMDB)

### Comparativa Rápida

| Característica | iTop | GLPI | Zammad |
|---|---|---|---|
| CMDB nativa | ✅ Centro arquitectónico | ✅ Módulo robusto | ❌ No tiene |
| Incidentes/Cambios/Problemas | ✅ ITIL completo | ✅ ITIL completo | ⚠️ Parcial |
| SLA | ✅ | ✅ | ⚠️ Básico |
| Base de Conocimiento | ✅ | ✅ | ✅ |
| Docker oficial | ❌ (comunidad) | ✅ (GLPI Team) | ✅ (Zammad GmbH) |
| LDAP/FreeIPA | ✅ Extensión oficial | ✅ Nativo | ✅ Nativo |
| API REST | ✅ | ✅ | ✅ + GraphQL |
| Comunidad | Grande | **Enorme** | Grande |
| Stack | PHP/MariaDB | PHP/MariaDB | Rails/PostgreSQL/ES |
| RAM mínima | 4 GB | 4 GB | 4 GB+ |

### Recommendation

**GLPI** es la opción recomendada para este equipo de investigación por estas razones:

1. **Docker oficial mantenido por GLPI Team** — despliegue simple y actualizaciones seguras en LXC
2. **CMDB + ITSM en un solo producto** — cubre Feature 3 y Feature 4, ahorrando recursos
3. **LDAP nativo** — integración directa con FreeIPA/AD sin extensiones extra
4. **API REST documentada** — automatizable desde scripts Shell (el stack del equipo)
5. **Comunidad enorme** — 11M+ usuarios, muchos plugins, foros activos, documentación extensa
6. **Recursos moderados** — funciona en 2 vCPU / 4 GB RAM, ideal para ambiente on-premise chico
7. **GLPI 10.x+** tiene UI renovada y PHP 8.x, performance mejorada
8. **Asset management** — el inventario de hardware/software es un plus para el grupo de investigación

iTop queda como **alternativa sólida** si el equipo prioriza tener la CMDB como eje arquitectónico y prefiere una herramienta más enfocada en procesos ITIL que en gestión de activos.

Zammad se descarta por la ausencia de CMDB y ITIL débil — obligaría a mantener dos sistemas (uno para CMDB + otro para ITSM), duplicando la complejidad.

### Stack Técnico Propuesto

- **Base de datos**: MariaDB 10.11+ (en Docker, misma compose)
- **Servidor web**: Apache/Nginx con PHP 8.1+
- **Despliegue**: Docker Compose en un LXC de Proxmox (2 vCPU, 4 GB RAM, 20 GB SSD)
- **Autenticación**: FreeIPA vía LDAP (sincronización programada de usuarios/grupos)
- **Respaldos**: Volúmenes Docker + dump semanal de MariaDB
- **Proxy reverso**: nginx proxy manager o similar

### Risks

- **Docker no oficial de GLPI**: Aunque GLPI team publica imágenes oficiales, no todas las versiones tienen el mismo nivel de soporte que la instalación tradicional
- **Carga de sintaxis LDAP**: FreeIPA tiene un schema LDAP particular — probar la integración antes de pasar a producción
- **Recursos en Proxmox**: Confirmar que el host tiene 4 GB RAM disponibles para el LXC
- **Mantenimiento a largo plazo**: GLPI requiere actualizaciones periódicas (PHP, base de datos, plugins) — considerar cron para backups y upgrades
- **Sobrecarga de features**: GLPI tiene muchas funcionalidades que el equipo quizás no use — riesgo de complejidad innecesaria al principio

### Ready for Proposal

**Yes** — la exploración está completa. Tengo suficiente información para pasar a la fase de propuesta. El equipo debería confirmar:

1. Si prefiere GLPI o iTop (mi recomendación es GLPI)
2. Si la CMDB compartida con Feature 3 es aceptable (converger features 3 y 4)
3. Disponibilidad de recursos (vCPU/RAM/disk) en el cluster Proxmox
