# Tasks: Dominio gidas.frlp — Integración con sitio institucional

## Fase 0: Exploración — ✅ Completada

- [x] **0.1** Identificar administrador del sitio Drupal → Acceso admin obtenido
- [x] **0.2** Determinar nivel de acceso al Drupal → Admin completo
- [x] **0.3** Evaluar subdominio → No viable sin UTN Sistemas
- [ ] **0.4** Evaluar dominio propio `gidas.com.ar` → Pendiente

## Fase 1: Enlace en Drupal — ✅ COMPLETADA

- [x] **1.1** Crear página explicativa en Drupal (`/node/40`)
  - ✅ Título: "Portal GIDAS - Acceso a Herramientas"
  - ✅ Botón de acceso a `https://portal.gidas.local`
  - ✅ Instrucciones de Twingate
  - ✅ Lista de servicios disponibles
- [x] **1.2** Agregar enlace al menú principal ("Portal GIDAS")
  - ✅ Visible en el menú principal del sitio
  - ✅ Sin necesidad de login en Drupal
- [x] **1.3** Verificar funcionamiento
  - ✅ Página pública accesible
  - ✅ Menú visible en homepage
  - ✅ Enlace funcional

## Fase 2: Documentación — ✅ COMPLETADA

- [x] **2.1** Documentar credenciales en `docs/gidas-frlp-dominio.md`
- [x] **2.2** SDD completo: spec, design, tasks, informe
- [x] **2.3** Plan de rollback documentado

## Fase 3: Análisis de Opciones Futuras — Pendiente

- [ ] **3.1** Evaluar VPS cloud como reverse proxy permanente
- [ ] **3.2** Contactar UTN Sistemas para subdominio o proxy nativo
- [ ] **3.3** Evaluar Twingate como solución definitiva

## Rollback Plan

### Reversión inmediata (2 minutos, desde admin de Drupal)

**Opción A — Eliminar solo el enlace del menú:**
```
/admin/structure/menu/manage/main → Portal GIDAS → Eliminar
```

**Opción B — Despublicar la página (sin eliminar):**
```
/admin/content → Portal GIDAS → Despublicar
```

**Opción C — Eliminar todo:**
```
/admin/content → Portal GIDAS → Eliminar
(El enlace del menú se elimina automáticamente)
```

### Impacto del rollback
- ✅ Solo afecta a la página y enlace creados
- ✅ No hay cambios en servidores, configuraciones ni otros contenidos
- ✅ No requiere acceso SSH ni reinicios
- ✅ Tiempo estimado: 2 minutos
