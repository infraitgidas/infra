# Tasks: Portal de Acceso Custom

## Phase 1: Foundation

- [ ] 1.1 Crear estructura de directorios `portal-gidas/app/`
- [ ] 1.2 Crear `requirements.txt` con dependencias
- [ ] 1.3 Crear `config.yaml` con herramientas y grupos AD
- [ ] 1.4 Crear `app/config.py` — loader Pydantic del YAML

## Phase 2: Auth Layer

- [ ] 2.1 Crear `app/services/ldap_service.py` — conexión AD + search + group extraction
- [ ] 2.2 Crear `app/auth.py` — JWT creation/validation + cookie management
- [ ] 2.3 Crear `app/models.py` — Pydantic schemas

## Phase 3: Web Layer

- [ ] 3.1 Crear `app/main.py` — FastAPI app + middleware + startup
- [ ] 3.2 Crear `app/routers/auth.py` — GET/POST /login, GET /logout
- [ ] 3.3 Crear `app/routers/portal.py` — GET / (dashboard) + GET /api/me

## Phase 4: Frontend

- [ ] 4.1 Crear `app/templates/base.html` — layout común
- [ ] 4.2 Crear `app/templates/login.html` — formulario de login
- [ ] 4.3 Crear `app/templates/dashboard.html` — grid de cards
- [ ] 4.4 Crear `app/static/css/portal.css` — estilos responsive
- [ ] 4.5 Descargar íconos de herramientas en `app/static/img/tools/`

## Phase 5: Deploy

- [ ] 5.1 Crear `Dockerfile` multi-stage
- [ ] 5.2 Crear `Makefile` con comandos build/run/stop/logs
- [ ] 5.3 Deploy en CT 208, reemplazar nginx/Homer

## Phase 6: Documents

- [ ] 6.1 Actualizar `docs/portal-acceso/avance.md`
- [ ] 6.2 Actualizar `PROJECT.md`
