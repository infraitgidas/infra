# ADR-001: Redmine como plataforma de gestión de proyectos

**Fecha:** 2026-06-10
**Contexto:** Análisis de herramientas open source para grupo de investigación, desarrollo e innovación (GIDAS, FRLP UTN).

## Decisión

**Continuar con Redmine** como plataforma principal de gestión de proyectos, potenciándolo con plugins estratégicos en lugar de migrar a otra herramienta.

## Alternativas Consideradas

| Alternativa | Descartada por |
|-------------|----------------|
| OpenProject | Mayor consumo de recursos (4-8 GB RAM), PostgreSQL only, sin migrador desde Redmine, más overhead operativo. No justifica la migración versus el valor que aporta. |
| Taiga | Sin Gantt, time tracking, ni gestión financiera. No cubre necesidades de planificación táctica del grupo. |
| Leantime | Gestión financiera ausente, program management es plugin de paga. PHP (stack ajeno al equipo). |
| ProjeQtOr | UI muy densa, setup extenso (43-69 hs), performance no testeada para 30 usuarios. |
| Plane | Proyecto joven, sin time tracking, sin gestión financiera ni de riesgos. Inmaduro para un grupo consolidado. |

## Argumentos a Favor

1. **Eficiencia de recursos:** 2 GB RAM vs 4-8 GB de OpenProject. Disco ~10 GB vs ~20 GB. Crítico para el cluster PVE existente.
2. **Versatilidad:** Custom fields y plugins permiten modelar cualquier necesidad del grupo sin cambiar de herramienta.
3. **Integración Git nativa:** Browser de repos, asociación commits-issues, andando hoy.
4. **Madurez:** 25+ años, comunidad grande, estable, predecible.
5. **Nada que migrar:** Ya está instalado y operativo. El costo de migrar no se justifica.
6. **Stickiness bajo:** Si en el futuro se necesita migrar, Redmine tiene exportación estándar y APIs abiertas. No hay vendor lock-in.

## Riesgos y Mitigaciones

| Riesgo | Mitigación |
|--------|------------|
| UI anticuada | Aplicar tema moderno (CircleCI, A1 u otros). Evaluar Redesign plugin. |
| Mantenimiento de plugins | Limitar plugins a los estratégicos. Documentar cada plugin antes de instalarlo. |
| Sin Agile boards nativas | Instalar Redmine Agile (plugin) solo si los equipos lo piden. |
| Gestión financiera limitada | Evaluar Redmine Budget plugin vs. planillas externas. No mezclar hasta tener el caso de uso claro. |
| Rendimiento con muchos proyectos | Tuning de base de datos, indexes, caching. Monitorear con los recursos actuales antes de optimizar. |

## Próximos Pasos

1. Definir plugins estratégicos a instalar (si hacen falta)
2. Mejorar UI con un tema moderno
3. Revisar workflows y roles actuales
4. Capacitar al equipo en las funcionalidades existentes
5. Evaluar performance actual antes de agregar carga

## Estado

**Aceptada**
