# Design: Portal GIDAS desde Drupal — Enlace público

## Arquitectura

```
Usuario en Internet
       │
       ▼
┌─────────────────────────────────────┐
│  Drupal                             │
│  gidas.frlp.utn.edu.ar              │
│                                     │
│  Menú principal:                    │
│  ├── Inicio                         │
│  ├── Investigación                  │
│  ├── Proyectos                      │
│  ├── Integrantes                    │
│  ├── Portal GIDAS ──────────────────┼──→ /node/40 (página explicativa)
│  └── Contacto                       │       │
└─────────────────────────────────────┘       │
                                              ▼
                              ┌────────────────────────────┐
                              │  Página: Portal GIDAS      │
                              │  https://gidas.frlp.utn... │
                              │  Contenido:                │
                              │  ✅ Enlace a portal        │
                              │  ✅ Instrucciones Twingate │
                              │  ✅ Info de contacto       │
                              └────────────┬───────────────┘
                                           │
                                           ▼
                              ┌────────────────────────────┐
                              │  Portal GIDAS (interno)    │
                              │  https://portal.gidas.local│
                              │  Requiere: Twingate        │
                              └────────────────────────────┘
```

## Componentes

| Componente | URL | Acceso |
|------------|-----|--------|
| **Drupal (página)** | `https://gidas.frlp.utn.edu.ar/node/40` | Público |
| **Enlace menú** | `https://gidas.frlp.utn.edu.ar` → "Portal GIDAS" | Público |
| **Portal destino** | `https://portal.gidas.local` | Privado (Twingate) |

## Flujo de acceso

```
Visitante → gidas.frlp.utn.edu.ar → click "Portal GIDAS" →
  Página explicativa con enlace e instrucciones →
    ¿Tiene Twingate? → Sí → portal.gidas.local → login AD
    ¿Tiene Twingate? → No → Instrucciones para obtener acceso
```

## Contenido de la página

La página incluye:
1. **Título**: "Portal GIDAS - Acceso a Herramientas"
2. **Botón**: "🔐 Acceder al Portal GIDAS" → `https://portal.gidas.local`
3. **Instrucciones**: Cómo obtener acceso si no tiene Twingate
4. **Lista de servicios**: GitLab, Redmine, LibreNMS, Grafana

## Rollback Plan

### Reversión inmediata (desde admin de Drupal)

**Opción A: Eliminar solo el enlace del menú**
1. Ir a `/admin/structure/menu/manage/main`
2. Buscar "Portal GIDAS"
3. Click "Eliminar"
4. Confirmar

**Opción B: Despublicar la página**
1. Ir a `/admin/content`
2. Buscar "Portal GIDAS - Acceso a Herramientas"
3. Click "Despublicar" (sin eliminar, para reactivar después)

**Opción C: Eliminar todo**
1. Eliminar la página desde `/admin/content`
2. El enlace del menú se elimina automáticamente con el nodo

### Tiempo estimado de reversión: 2 minutos
### Impacto: Solo afecta a la página y enlace creados. No hay cambios en otros contenidos ni en la configuración del servidor.
