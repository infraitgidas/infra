# Análisis de Herramientas Open Source para Gestión de Proyectos

## Contexto

Grupo de Investigación, Desarrollo e Innovación (I+D+i) — GIDAS, FRLP UTN.

### Estructura Organizacional

```
Dirección del Grupo
├── Gestión Administrativa-Financiera
├── Planeación Táctica y Estratégica
├── Equipo 1 (Proyecto A)
│   ├── Sub-proyecto A.1
│   ├── Sub-proyecto A.2
│   └── Iniciativas derivadas
├── Equipo 2 (Proyecto B)
│   ├── Sub-proyecto B.1
│   └── Iniciativas derivadas
└── Equipo N (Proyecto N)
```

### Requerimientos Identificados

| Dimensión | Requerimiento |
|-----------|---------------|
| **Proyectos** | Múltiples proyectos con jerarquía proyecto → sub-proyecto → tarea/iniciativa |
| **Equipos** | ~5 proyectos activos, ~30 desarrolladores/investigadores |
| **Roles** | Director, coordinador, investigador, desarrollador, becario, administrador |
| **Planeación** | Táctica (trimestral/semestral) y estratégica (anual/bienal) |
| **Gestión administrativa** | Presupuestos, costos, recursos, reporting |
| **Gestión financiera** | Seguimiento de gastos por proyecto, facturación, rendiciones |
| **Investigación** | Seguimiento de publicaciones, producción académica, proyectos de investigación |
| **Desarrollo** | Gestión de issues, sprints, milestones, integración con Git |
| **Calidad** | Gestión de riesgos, no conformidades, indicadores |
| **Documentación** | Wiki, repositorio de documentos, actas de reunión |

---

## Alternativas Analizadas

### 1. Redmine (Actual)

| Aspecto | Descripción |
|---------|-------------|
| **Stack** | Ruby on Rails + MySQL/PostgreSQL |
| **Licencia** | GPLv2 |
| **Repo** | https://github.com/redmine/redmine |
| **Última versión** | 5.1.x (2024-2025) |
| **Comunidad** | Muy activa, 25+ años, 5k+ stars |
| **Modelo** | Open source 100% |

**Fortalezas:**
- ✅ Extremadamente maduro y estable
- ✅ Plugin ecosystem enorme (Agile, CRM, Budgeting, Gantt, etc.)
- ✅ Integración nativa con Git/SVN/Mercurial
- ✅ Multi-proyecto con roles y permisos granulares
- ✅ Wiki, foros, time tracking, Gantt integrados
- ✅ Custom fields en issues, time entries, proyectos, usuarios
- ✅ Múltiples autenticaciones LDAP
- ✅ Notificaciones por email

**Debilidades:**
- ❌ UI anticuada (por defecto — mejora con temas/plugins)
- ❌ Setup inicial requiere configuración y plugins para features modernas
- ❌ Sin Agile boards nativas (requiere plugin)
- ❌ Sin gestión financiera nativa robusta
- ❌ Performance puede degradarse con muchos proyectos sin tuning
- ❌ Sin conceptos nativos de "programa" o "portfolio"

**Ideal para:** Equipos técnicos que necesitan personalización total y tienen capacidad de configuración.

---

### 2. OpenProject

| Aspecto | Descripción |
|---------|-------------|
| **Stack** | Ruby on Rails + PostgreSQL |
| **Licencia** | GPLv3 (Community Edition) |
| **Repo** | https://github.com/opf/openproject |
| **Última versión** | 17.4 (Mayo 2026) |
| **Comunidad** | Muy activa, 10k+ stars, release mensual |
| **Modelo** | Open-core (Community gratuita + Enterprise con soporte) |

**Fortalezas:**
- ✅ UI moderna y limpia (mucho mejor que Redmine out of the box)
- ✅ Agile boards nativas (Scrum + Kanban)
- ✅ Gantt charts con planificación por dependencias
- ✅ Time tracking + cost tracking + budget planning
- ✅ Work packages jerárquicos (epic → story → task)
- ✅ Portfolio management con roadmap
- ✅ Gestión de documentos integrada
- ✅ Autenticación LDAP/OIDC/SSO
- ✅ REST API completa + Webhooks
- ✅ Migrador desde Jira
- ✅ Roadmap de producto visible y release frecuente (casi mensual)
- ✅ Usado por universidades (Coburg University, caso documentado)

**Debilidades:**
- ❌ Menor ecosistema de plugins que Redmine
- ❌ Community Edition no incluye algunas features avanzadas (ej. baselines, revisiones de código)
- ❌ Más pesado que Redmine en recursos (Ruby on Rails + PostgreSQL)
- ❌ Curva de aprendizaje media (más features que Taiga, menos configurable que Redmine)

**Ideal para:** Organizaciones que necesitan planificación estructurada, gestión de costos y visión portfolio, con buena UX out of the box.

---

### 3. Taiga

| Aspecto | Descripción |
|---------|-------------|
| **Stack** | Python (Django) + Angular + PostgreSQL |
| **Licencia** | MPL 2.0 / Apache 2.0 |
| **Repo** | https://github.com/taigaio |
| **Última versión** | 6.x (2025) |
| **Comunidad** | Activa, 7k+ stars |
| **Modelo** | Open-core (Community gratuita + Premium cloud) |

**Fortalezas:**
- ✅ UI excelente, moderna, intuitiva (la mejor de todas)
- ✅ Scrum y Kanban nativos con swimlanes
- ✅ Épicas, user stories, backlog, sprints, burn-down charts
- ✅ Fácil de adoptar — curva de aprendizaje baja
- ✅ Wiki integrada
- ✅ Buen reporte de issues y bugs
- ✅ REST API
- ✅ Integración con GitHub/GitLab/Bitbucket

**Debilidades:**
- ❌ Sin Gantt chart (no sirve para planificación clásica)
- ❌ Sin time tracking nativo
- ❌ Sin gestión financiera (budget, costos)
- ❌ Sin gestión de riesgos
- ❌ Limitado para gestión tipo waterfall o híbrida
- ❌ Sin portfolio management avanzado
- ❌ Comunidad menos activa que OpenProject/Redmine
- ❌ Funcionalidades limitadas en la versión open source

**Ideal para:** Equipos ágiles que priorizan UX moderna sobre features de planificación clásica.

---

### 4. Leantime

| Aspecto | Descripción |
|---------|-------------|
| **Stack** | PHP (Laravel) + MySQL/PostgreSQL |
| **Licencia** | AGPLv3 |
| **Repo** | https://github.com/Leantime/leantime |
| **Última versión** | 3.8.0 (Mayo 2026) |
| **Comunidad** | Activa, 10k+ stars |
| **Modelo** | Open-core (plugins para features avanzadas) |

**Fortalezas:**
- ✅ Enfoque único: estrategia + ejecución (Research → Ideation → Execution)
- ✅ Program management (visión multi-proyecto con timeline)
- ✅ Canvas boards para research, strategy, lean
- ✅ UX cuidada, diseñada con foco en neurodivergencia (ADHD, dyslexia)
- ✅ Time tracking
- ✅ Milestones con Gantt/timeline
- ✅ Sprint backlog nativo
- ✅ Retrospectives
- ✅ Gestión de ideas
- ✅ Documentación integrada
- ✅ API REST

**Debilidades:**
- ❌ Versión OSS no incluye program management (es plugin de paga)
- ❌ Gestión financiera ausente en OSS
- ❌ Sin gestión de riesgos
- ❌ Sin gestión de calidad (no conformidades, indicadores)
- ❌ Menos maduro que OpenProject/Redmine
- ❌ Plugins avanzados requieren licencia Pro
- ❌ PHP (menos estándar en infraestructura actual)

**Ideal para:** Equipos pequeños que necesitan conectar estrategia con ejecución, con enfoque en innovación.

---

### 5. ProjeQtOr

| Aspecto | Descripción |
|---------|-------------|
| **Stack** | PHP + MySQL/PostgreSQL |
| **Licencia** | GPLv2 / GPLv3 |
| **Repo** | https://sourceforge.net/projects/projectorria/ |
| **Última versión** | 12.5 (2025-2026) |
| **Comunidad** | Mediana, 15+ años, principalmente Europa |
| **Modelo** | Open source 100% |

**Fortalezas:**
- ✅ Feature set más completo de todos (planning, costos, riesgos, calidad, RRHH, documentos)
- ✅ Gestión financiera nativa (costos, presupuestos, facturación, ingresos)
- ✅ Gestión de riesgos (RIDA) integrada
- ✅ Gestión de calidad (no conformidades, indicadores, checklists)
- ✅ Multi-proyecto con consolidación automática
- ✅ Capacity planning cross-proyecto
- ✅ Gestión de requisitos y tests
- ✅ Gestión de habilidades del equipo
- ✅ Baselines de proyecto
- ✅ Import/Export CSV, XLSX, MS-Project XML
- ✅ API REST
- ✅ 100% gratuito sin limitaciones (no open-core)
- ✅ Workflows personalizables
- ✅ Seguimiento de reuniones, decisiones, preguntas

**Debilidades:**
- ❌ UI densa y abrumadora (curva de aprendizaje alta)
- ❌ UX anticuada (similar a ERP tradicional)
- ❌ Stack PHP (no es el fuerte del equipo actual)
- ❌ Comunidad más pequeña, documentación en inglés/francés
- ❌ Sin integración nativa con Git (aunque tiene API)
- ❌ Menor adopción global
- ❌ Performance no testeada para 30+ usuarios concurrentes

**Ideal para:** Organizaciones que necesitan gestión integral (proyectos + finanzas + calidad + riesgos) en una sola herramienta.

---

### 6. Plane

| Aspecto | Descripción |
|---------|-------------|
| **Stack** | Python (Django) + React + PostgreSQL |
| **Licencia** | Apache 2.0 (open-core) |
| **Repo** | https://github.com/makeplane/plane |
| **Última versión** | 0.23.x (2026) |
| **Comunidad** | Muy activa, 40k+ stars (crecimiento explosivo) |
| **Modelo** | Open-core con Cloud + Self-hosted |

**Fortalezas:**
- ✅ UI modernísima, tipo Linear/Jira — la más atractiva
- ✅ Issues, ciclos, módulos, views (Kanban, Gantt, Calendar, Spreadsheet)
- ✅ Proyectos jerárquicos con módulos
- ✅ Analytics integrados
- ✅ Rápido crecimiento y comunidad enorme
- ✅ API REST + Webhooks
- ✅ Integración con GitHub/GitLab
- ✅ Self-hosted con Docker Compose

**Debilidades:**
- ❌ Proyecto joven (menos maduro que Redmine/OpenProject)
- ❌ Sin time tracking (planificado pero no implementado)
- ❌ Sin gestión financiera
- ❌ Sin gestión de riesgos
- ❌ Sin gestión de calidad
- ❌ Sin portfolio management consolidado
- ❌ Roadmap aún en desarrollo — features cambian rápido
- ❌ Open-core: algunas features solo en cloud

**Ideal para:** Startups y equipos de producto que buscan un reemplazo moderno de Jira.

---

## Benchmarking Comparativo

| Feature / Dimensión | Redmine | OpenProject | Taiga | Leantime | ProjeQtOr | Plane |
|---------------------|---------|-------------|-------|----------|-----------|-------|
| **Stack** | Ruby/Rails | Ruby/Rails | Python/Angular | PHP/Laravel | PHP | Python/React |
| **Licencia** | GPLv2 ✅ | GPLv3 ✅ | MPL ✅ | AGPL ⚠️ | GPL ✅ | Apache ✅ |
| **Modelo** | 100% OSS ✅ | Open-core ⚠️ | Open-core ⚠️ | Open-core ⚠️ | 100% OSS ✅ | Open-core ⚠️ |
| **UI/UX** | ⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐⭐⭐ |
| **Multi-proyecto** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Sub-proyectos jerárquicos** | ✅ (plugins) | ✅ | ⚠️ (épicas) | ⚠️ | ✅ | ✅ (módulos) |
| **Agile (Scrum/Kanban)** | ⚠️ (plugin) | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Gantt / Timeline** | ✅ (plugin) | ✅ | ❌ | ✅ | ✅ | ✅ |
| **Time Tracking** | ✅ | ✅ | ❌ | ✅ | ✅ | ❌ |
| **Costos / Budget** | ⚠️ (plugin) | ✅ | ❌ | ❌ | ✅ | ❌ |
| **Gestión de Riesgos** | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ |
| **Gestión de Calidad** | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ |
| **Wiki / Docs** | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| **Foros** | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **Integración Git** | ✅ nativa | ✅ | ✅ (GH/GL) | ⚠️ | ⚠️ (API) | ✅ (GH/GL) |
| **LDAP / SSO** | ✅ | ✅ | ✅ | ✅ | ✅ | ⚠️ |
| **API REST** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Webhooks** | ⚠️ (plugin) | ✅ | ✅ | ✅ | ⚠️ | ✅ |
| **Portfolio Management** | ❌ | ✅ | ❌ | ⚠️ (plugin) | ✅ | ❌ |
| **Capacity Planning** | ❌ | ⚠️ (Enterprise) | ❌ | ❌ | ✅ | ❌ |
| **Reporting / Analytics** | ⚠️ (plugin) | ✅ | ⚠️ | ⚠️ | ✅ | ✅ |
| **Rol granular / RBAC** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Performance (30 users)** | ✅ | ✅ | ✅ | ✅ | ⚠️ (no test) | ✅ |
| **Madurez** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐ |

### Leyenda: ✅ nativo · ⚠️ limitado/plugin · ❌ no disponible

---

## Integración con Stack Existente

### Stack actual GIDAS
| Herramienta | Estado |
|-------------|--------|
| **GitLab** | ✅ Instalado y operativo |
| **Redmine** | ✅ Instalado (en CT PVE) |
| **GLPI** | ✅ ITSM |
| **NetBox** | ✅ CMDB |
| **FreeIPA** | ✅ Autenticación centralizada |
| **Active Directory** | ✅ Autenticación centralizada |
| **Proxmox VE** | ✅ Hipervisor |
| **Docker Compose** | ✅ Estándar de deploy |
| **SOPS + age** | ✅ Secrets |

### Matriz de Integración

| Herramienta → ↓ PM | GitLab | FreeIPA/AD LDAP | GLPI | Docker Compose |
|--------------------|--------|-----------------|------|----------------|
| **Redmine** | ✅ Nativo (repos browser) | ✅ LDAP auth | ⚠️ (plugin) | ✅ |
| **OpenProject** | ⚠️ (REST API) | ✅ LDAP/OIDC/SSO | ⚠️ (REST) | ✅ |
| **Taiga** | ✅ (GH/GL hook) | ✅ LDAP | ❌ | ✅ |
| **Leantime** | ⚠️ (webhook) | ✅ LDAP/OIDC | ❌ | ✅ |
| **ProjeQtOr** | ⚠️ (API) | ✅ LDAP | ⚠️ (API) | ✅ |
| **Plane** | ✅ (GH/GL integración) | ⚠️ (no LDAP) | ❌ | ✅ |

---

## Housekeeping Estimado

Para ~5 proyectos activos, ~30 usuarios, operación continua.

### Dimensión de Esfuerzo

| Actividad | Redmine | OpenProject | Taiga | Leantime | ProjeQtOr | Plane |
|-----------|---------|-------------|-------|----------|-----------|-------|
| Instalación inicial | 4-8 hs | 2-4 hs | 2-3 hs | 2-3 hs | 3-5 hs | 1-2 hs |
| Configuración base | 8-16 hs | 4-8 hs | 2-4 hs | 3-6 hs | 8-16 hs | 2-4 hs |
| Creación de proyectos | 4-6 hs | 2-4 hs | 2-3 hs | 2-4 hs | 4-8 hs | 1-2 hs |
| Configuración workflows | 8-16 hs | 4-8 hs | 2-4 hs | 4-8 hs | 8-16 hs | 2-4 hs |
| Custom fields | 4-8 hs | 2-4 hs | 2-3 hs | ❌ (plugin) | 4-8 hs | ❌ |
| Migración desde Redmine | — | 4-8 hs | 8-16 hs | 8-16 hs | 16-24 hs | 4-8 hs |
| **Total setup** | **28-54 hs** | **18-36 hs** | **18-33 hs** | **19-37 hs** | **43-69 hs** | **10-18 hs** |

### Mantenimiento Mensual (recurrente)

| Actividad | Redmine | OpenProject | Taiga | Leantime | ProjeQtOr | Plane |
|-----------|---------|-------------|-------|----------|-----------|-------|
| Actualización de versión | 2-4 hs/mes | 1-2 hs/mes | 1-2 hs/mes | 1-2 hs/mes | 2-4 hs/mes | 1-2 hs/mes |
| Backup/restore test | 1-2 hs/mes | 1-2 hs/mes | 1-2 hs/mes | 1-2 hs/mes | 1-2 hs/mes | 1-2 hs/mes |
| Administración usuarios | 1-2 hs/mes | 1-2 hs/mes | 1-2 hs/mes | 1-2 hs/mes | 1-2 hs/mes | 1-2 hs/mes |
| Tuning/performance | 2-4 hs/mes | 1-2 hs/mes | 0-1 hs/mes | 0-1 hs/mes | 1-2 hs/mes | 0-1 hs/mes |
| Plugin/parche gestión | 2-6 hs/mes | 1-2 hs/mes | 1-2 hs/mes | 1-2 hs/mes | 1-2 hs/mes | 1-2 hs/mes |
| **Total mensual** | **8-18 hs** | **5-10 hs** | **4-9 hs** | **4-8 hs** | **6-12 hs** | **4-8 hs** |

### Infraestructura Mínima Recomendada

| Recurso | Redmine | OpenProject | Taiga | Leantime | ProjeQtOr | Plane |
|---------|---------|-------------|-------|----------|-----------|-------|
| CPU | 2 cores | 4 cores | 2 cores | 2 cores | 2 cores | 2 cores |
| RAM | 4 GB | 8 GB | 4 GB | 4 GB | 4 GB | 4 GB |
| Disco | 20 GB | 20 GB | 20 GB | 10 GB | 20 GB | 20 GB |
| Base de datos | MySQL/Postgres | PostgreSQL | PostgreSQL | MySQL/Postgres | MySQL/Postgres | PostgreSQL |
| Contenedor | ✅ Docker | ✅ Docker | ✅ Docker | ✅ Docker | ⚠️ (manual) | ✅ Docker |

---

## Análisis por Dimensión Organizacional

### 1. Dirección Estratégica

¿Qué necesita? Visión global del portfolio, reportes ejecutivos, seguimiento de objetivos estratégicos.

| Herramienta | Rating | Comentario |
|-------------|--------|------------|
| **OpenProject** | ⭐⭐⭐⭐⭐ | Portfolio management + roadmap + Gantt multi-proyecto + cost tracking |
| **ProjeQtOr** | ⭐⭐⭐⭐⭐ | Consolidación multi-nivel, indicadores, baselines |
| **Redmine** | ⭐⭐ | Sin portfolio nativo — requiere plugins y configuración pesada |
| **Taiga** | ⭐⭐ | Sin portfolio — pensado para equipos, no dirección |
| **Leantime** | ⭐⭐⭐ | Program management (pero es plugin de paga) |
| **Plane** | ⭐⭐⭐ | Analytics, pero joven y sin portfolio consolidado |

### 2. Gestión Administrativa-Financiera

¿Qué necesita? Presupuestos, seguimiento de gastos, rendiciones, facturación.

| Herramienta | Rating | Comentario |
|-------------|--------|------------|
| **ProjeQtOr** | ⭐⭐⭐⭐⭐ | Costos, presupuestos, facturación, ingresos — todo nativo |
| **OpenProject** | ⭐⭐⭐⭐ | Budget planning + cost tracking en Community |
| **Redmine** | ⭐⭐ | Via plugins (Budget plugin) — limitado |
| **Taiga** | ⭐ | No tiene |
| **Leantime** | ⭐⭐ | No tiene gestión financiera real |
| **Plane** | ⭐ | No tiene |

### 3. Gestión de Proyectos de I+D+i

¿Qué necesita? Seguimiento de investigación, publicaciones, propiedad intelectual, producción académica.

| Herramienta | Rating | Comentario |
|-------------|--------|------------|
| **OpenProject** | ⭐⭐⭐⭐ | Work packages jerárquicos, hitos, documentos, calendar |
| **ProjeQtOr** | ⭐⭐⭐⭐ | Requirements management, tests, docs, calidad |
| **Redmine** | ⭐⭐⭐ | Wiki + documents + repos — customizable pero sin estructura I+D |
| **Leantime** | ⭐⭐⭐⭐ | Research canvas + strategy boards + ideation — bien para innovación |
| **Taiga** | ⭐⭐ | Épicas + user stories — limitado para investigación |
| **Plane** | ⭐⭐ | Módulos + issues — muy orientado a producto, no investigación |

### 4. Gestión de Desarrollo de Software

¿Qué necesita? Issues, sprints, milestones, integración Git, code review.

| Herramienta | Rating | Comentario |
|-------------|--------|------------|
| **Redmine** | ⭐⭐⭐⭐⭐ | Integración nativa Git + repos browser + commits ↔ issues |
| **Plane** | ⭐⭐⭐⭐ | Issues + ciclos + módulos + GH/GL integración |
| **Taiga** | ⭐⭐⭐⭐ | Scrum + Kanban + GH/GL integración |
| **OpenProject** | ⭐⭐⭐⭐ | Agile boards + trabajo por paquetes + milestones |
| **Leantime** | ⭐⭐⭐ | Kanban + sprints + milestones |
| **ProjeQtOr** | ⭐⭐⭐ | Tickets + planificación — menos orientado a desarrollo ágil |

### 5. Gestión de Calidad y Riesgos

¿Qué necesita? Gestión de riesgos, no conformidades, indicadores, auditoría.

| Herramienta | Rating | Comentario |
|-------------|--------|------------|
| **ProjeQtOr** | ⭐⭐⭐⭐⭐ | RIDA, calidad, indicadores, checklists, workflows — el mejor |
| **OpenProject** | ⭐⭐ | Sin gestión de riesgos nativa |
| **Redmine** | ⭐⭐ | Sin gestión de riesgos |
| **Taiga** | ⭐ | No tiene |
| **Leantime** | ⭐⭐ | Research canvas — no es gestión de calidad formal |
| **Plane** | ⭐ | No tiene |

---

## Recomendaciones por Perfil

### Escenario A: Quedarse con Redmine + Potenciarlo

✅ **Cuándo elegirlo:** El equipo ya conoce Redmine, hay plugins instalados, la personalización es crítica, y hay capacidad técnica para mantenerlo.

**Inversión estimada:** 20-30 hs setup + 8-18 hs/mes mantenimiento.
**Plugins recomendados:**
- Redmine Agile (plugin) — boards Scrum/Kanban
- Redmine Budget — gestión financiera básica
- Redmine Risk Management
- Redmine CRM
- Temas UI modernos (CircleCI, A1)

**Pros:** Sin migración, aprovecha lo existente.
**Contras:** UI obsoleta, mantenimiento alto, gestión financiera limitada.

### Escenario B: Migrar a OpenProject

✅ **Cuándo elegirlo:** Se necesita mejor UX, planificación estructurada, portfolio management, y cost tracking sin depender de plugins.

**Inversión estimada:** 18-36 hs setup + 5-10 hs/mes mantenimiento.
**Incluye migrador desde Jira** (no desde Redmine — migración manual vía API).

**Pros:** Mejor relación features/simplicidad, release frecuente, comunidad grande.
**Contras:** No maneja riesgos ni calidad (se complementaría con GLPI).

### Escenario C: Migrar a ProjeQtOr

✅ **Cuándo elegirlo:** La prioridad es tener gestión integral (proyectos + finanzas + calidad + riesgos) en UNA sola herramienta.

**Inversión estimada:** 43-69 hs setup + 6-12 hs/mes mantenimiento.
**Requiere:** Evaluar performance con 30 usuarios concurrentes.

**Pros:** Feature set más completo, 100% gratuito.
**Contras:** UI densa, setup más largo, comunidad más chica.

### Escenario D: Usar Taiga o Plane para Desarrollo + OpenProject para Gestión

✅ **Cuándo elegirlo:** Cuando se quiere lo mejor de ambos mundos: UX moderna para desarrollo y planificación estructurada para dirección.

**Inversión estimada:** 30-50 hs setup + 10-20 hs/mes (dos sistemas).
**Requiere:** Integración vía API/webhooks o doble ingreso de datos.

**Pros:** Cada equipo usa la herramienta óptima para su perfil.
**Contras:** Dos sistemas que mantener, posible duplicación de datos.

### Escenario E: Leantime para Innovación + Investigación

✅ **Cuándo elegirlo:** El foco está en I+D+i con procesos de innovación, research boards, y conexión estrategia-ejecución.

**Inversión estimada:** 19-37 hs setup + 4-8 hs/mes.
**Limitación:** Gestión financiera ausente, program management es plugin de paga.

**Pros:** Enfoque único en investigación + innovación.
**Contras:** No cubre aspectos financieros ni de calidad.

---

## Veredicto Final

| Criterio | Ganador | Por qué |
|----------|---------|---------|
| Mejor integral (todo en uno) | **ProjeQtOr** | Único que cubre proyectos + finanzas + calidad + riesgos |
| Mejor balance features/simplicidad | **OpenProject** | Portfolio, costos, agile, Gantt, time tracking — todo nativo |
| Mejor UX para desarrollo ágil | **Taiga / Plane** | UX moderna, ideal para equipos de desarrollo |
| Mejor para I+D+i | **Leantime** | Research canvas + strategy + execution |
| Mejor si ya tenés Redmine | **Redmine + plugins** | Sin migración, aprovecha inversión existente |
| Menor mantenimiento | **Plane** | Docker compose, actualizaciones simples |
| Mayor madurez | **Redmine** | 25+ años de desarrollo |

### Recomendación para GIDAS

Considerando que GIDAS es un grupo de **investigación, desarrollo e innovación** con:
- Necesidad de **gestión financiera** (presupuestos, rendiciones)
- Equipos de **desarrollo de software** que usan GitLab
- **Multi-proyecto** con sub-proyectos e iniciativas
- **Dirección estratégica** que requiere visibilidad del portfolio
- Infraestructura existente con **Docker Compose** y **FreeIPA/AD** para autenticación

**Opción recomendada: OpenProject**

Fundamento:
1. **Portfolio management** nativo con roadmap → visibilidad estratégica
2. **Cost tracking** nativo → gestión financiera básica sin tool extra
3. **Agile boards** nativas → equipos de desarrollo ágil
4. **Gantt + milestones** → planificación táctica
5. **LDAP/OIDC** → integración con FreeIPA
6. **Docker Compose** → deploy simple como el stack actual
7. **UI moderna** → adopción por el equipo
8. **Comunidad grande + release frecuente** → longevidad asegurada
9. **Migrador desde Jira** → si en futuro migran desde Jira

**Complemento recomendado:** GLPI (ya instalado) para aspectos de calidad, riesgos y servicio al usuario. La dupla OpenProject (planificación + seguimiento) + GLPI (incidentes + service desk) cubre todo el espectro.

**No recomendado:** ProjeQtOr por su UI densa y esfuerzo de setup, a pesar de ser el más completo. Redmine por su UI anticuada y mantenimiento creciente. Plane por inmadurez para un grupo de investigación consolidado.

---

## Decisión Final

**2026-06-10 — Decidido: Redmine.**

Después de evaluar las alternativas, se opta por **continuar con Redmine** como plataforma principal. Las razones concretas:

1. **Ya funciona y el equipo lo conoce** — migrar tiene costo real y beneficio marginal.
2. **Menor consumo de recursos** — 2 GB RAM vs 4-8 GB de OpenProject. En un PVE con recursos acotados, importa.
3. **Versatilidad vía custom fields + plugins** — podemos modelar lo que necesitemos sin cambiar de herramienta.
4. **Integración Git nativa** — ya anda con GitLab.
5. **La migración a OpenProject no es trivial** — no tiene migrador desde Redmine. Si algún día queremos migrar, mejor hacerlo con datos limpios y mínima dependencia de plugins.

Ver ADR-001 en `docs/decisions/001-redmine-platform.md` para el registro completo de la decisión.

## Próximos Pasos

1. ✅ **Decidir herramienta** (este documento + ADR-001)
2. ⬜ Inventariar plugins instalados y evaluar cuáles vale la pena agregar
3. ⬜ Aplicar tema UI moderno si la adopción del equipo lo requiere
4. ⬜ Revisar workflows y roles actuales
5. ⬜ Evaluar performance actual antes de agregar carga
6. ⬜ Documentar configuración y procedimientos

---

*Documento generado: 2026-06-10*
*Próxima revisión sugerida: 2026-09-10*
