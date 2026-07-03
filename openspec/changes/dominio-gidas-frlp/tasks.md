# Tasks: Dominio gidas.frlp — Integración con sitio institucional

## Fase 0: Exploración y Contacto

- [ ] **0.1** Identificar administrador del sitio Drupal en UTN-FRLP
  - Contactar al Departamento de Sistemas FRLP
  - Preguntar quién maneja `gidas.frlp.utn.edu.ar`
- [ ] **0.2** Determinar nivel de acceso del equipo GIDAS al Drupal
  - ¿Podemos editar el menú? ¿Solo contenido? ¿Nada?
  - ¿Hay usuario GIDAS con rol de editor/administrador?
- [ ] **0.3** Evaluar posibilidad de subdominio `gidas.frlp.utn.edu.ar`
  - ¿Se puede delegar? ¿Quién autoriza?
  - ¿Hay un DNS manejable por GIDAS?
- [ ] **0.4** Evaluar dominio propio `gidas.com.ar`
  - Costo, disponibilidad, gestión

## Fase 1: Enlaces en Drupal

- [ ] **1.1** Solicitar alta de enlaces en menú principal de Drupal
  - Enlace "Portal GIDAS" → `https://portal.gidas.local`
  - Enlace "GitLab" → `https://gitlab.gidas.local`
  - Enlace "Redmine" → `https://redmine.gidas.local`
  - Enlace "LibreNMS" → `https://nms.gidas.local`
  - Enlace "Grafana" → `http://192.168.1.205:3000`
- [ ] **1.2** Agregar página/artículo en Drupal con descripción de cada servicio
  - Qué ofrece cada herramienta
  - Cómo obtener acceso (contactar a admin GIDAS)
  - Requisitos: Twingate instalado para acceso remoto

## Fase 2: Documentación

- [ ] **2.1** Documentar contacto y procedimiento en `docs/gidas-frlp-dominio.md`
- [ ] **2.2** Actualizar `PROJECT.md` con Feature 8
- [ ] **2.3** Actualizar `docs/portal-acceso/avance.md` con estado de dominio

## Fase 3: Presencia Digital Unificada

- [ ] **3.1** Verificar que el portal GIDAS esté accesible via Twingate
- [ ] **3.2** Agregar tarjeta de Twingate/Acceso Remoto en el portal si no existe
- [ ] **3.3** Unificar correo de notificaciones: `gidas@frlp.utn.edu.ar`
  - Identity dashboard ya lo usa
  - LibreNMS: configurar en Global Settings
  - Redmine: ya usa infrait@, evaluar cambiar
  - GitLab: evaluar

## Fase 4: CIerre

- [ ] **4.1** Verificar enlaces funcionando en Drupal
- [ ] **4.2** Documentar resultados en informe-cambios.md
- [ ] **4.3** Merge a main
