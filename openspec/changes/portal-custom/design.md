# Design: Portal de Acceso Custom

El diseño completo está documentado en:

| Documento | Archivo |
|-----------|---------|
| **Arquitectura** | `docs/portal-acceso/arquitectura.md` |
| **Diseño Técnico Detallado** | `docs/portal-acceso/diseno-tecnico.md` |
| **Lecciones Aprendidas** | `docs/portal-acceso/lecciones-aprendidas.md` |

## Resumen

| Aspecto | Decisión |
|---------|----------|
| **Backend** | Python 3.11+ / FastAPI 0.115+ |
| **Auth** | ldap3 contra AD GDC01 (bind directo) |
| **Sesiones** | JWT (PyJWT) en cookie HttpOnly, 8h expiración |
| **Frontend** | Jinja2 SSR + CSS vanilla + Font Awesome |
| **Config** | YAML con pydantic-settings |
| **Deploy** | Docker (multi-stage) o systemd directo |
| **CT destino** | CT 208 (portal, 192.168.1.43) |
