# Design: Dominio gidas.frlp — Integración con sitio institucional

## Arquitectura de Presencia Digital

```
                    Público (Internet)                     |   Privado (LAN/Twingate)
                                                           |
  ┌─────────────────────────────────────┐                  |   ┌──────────────────────┐
  │  Drupal                             │                  |   │  Portal GIDAS        │
  │  gidas.frlp.utn.edu.ar              │                  |   │  portal.gidas.local  │
  │                                     │                  |   │                      │
  │  Menú principal:                    │  Enlace →        |   │  Login AD + RBAC     │
  │  ├── Presentación                   │                  |   │                      │
  │  ├── Investigación                  │                  |   │  Tools internas:     │
  │  ├── Integrantes                    │                  |   │  ├── GitLab          │
  │  ├── Publicaciones                  │                  |   │  ├── Redmine         │
  │  ├───── Acceso a Herramientas ──────┼──────────────────|──>│  ├── LibreNMS        │
  │  └── Contacto                       │                  |   │  ├── Grafana         │
  │                                     │                  |   │  └── ...             │
  │  Administrado por: UTN-FRLP         │                  |   └──────────────────────┘
  │  (sin acceso directo GIDAS)         │                  |
  └─────────────────────────────────────┘                  |   ┌──────────────────────┐
                                                           |   │  Twingate Connector  │
                                                           |   │  (acceso remoto)     │
                                                           |   └──────────────────────┘
```

## Componentes

| Componente | Dominio | Acceso | Administrado por |
|------------|---------|--------|------------------|
| **Drupal** | `gidas.frlp.utn.edu.ar` | Público (Internet) | UTN-FRLP |
| **Portal GIDAS** | `portal.gidas.local` | Privado (LAN + Twingate) | Equipo GIDAS |
| **Servicios internos** | `*.gidas.local` | Privado (LAN + Twingate) | Equipo GIDAS |
| **Twingate** | `portal.twingate.com` | Privado (conector local) | Equipo GIDAS |

## Flujo de acceso para un usuario externo

```
1. Usuario visita gidas.frlp.utn.edu.ar
2. Ve enlace "Acceso a Herramientas" en el menú
3. Click → instrucciones para acceder via Twingate (o link directo si tiene Twingate)
4. Accede a portal.gidas.local → login AD → dashboard con tools según su grupo
```

## Enlaces a agregar en Drupal

| Texto del enlace | URL destino | Descripción |
|-----------------|-------------|-------------|
| Portal GIDAS | `https://portal.gidas.local` (Twingate) | Acceso a herramientas internas |
| GitLab | `https://gitlab.gidas.local` (Twingate) | Repositorios y CI/CD |
| Redmine | `https://redmine.gidas.local` (Twingate) | Gestión de proyectos |
| LibreNMS | `https://nms.gidas.local` (Twingate) | Monitoreo de red |
| Grafana | `http://192.168.1.205:3000` (Twingate) | Métricas y dashboards |

## Contacto para gestión de Drupal

> **PENDIENTE**: Identificar administrador del sitio Drupal en UTN-FRLP.
> Posibles contactos: Departamento de Sistemas FRLP, Secretaría de Ciencia y Técnica.

## Decisiones de diseño

| Decisión | Opción | Fundamento |
|----------|--------|------------|
| Drupal sigue externo | No migrar a infra GIDAS | Es el sitio institucional de UTN, no nos pertenece |
| Portal como puerta de entrada | Unificar acceso | Single sign-on via AD, RBAC por grupos |
| Twingate para externos | No exponer puertos | Seguridad: sin puertos abiertos en firewall |
| gidas.local para interno | Dominio interno | No depende de coordinación externa |

## Pendientes de exploración

- [ ] ¿Quién administra el sitio Drupal en UTN-FRLP?
- [ ] ¿Qué permisos de edición tiene el equipo GIDAS sobre el Drupal?
- [ ] ¿Se puede delegar un subdominio `gidas.frlp.utn.edu.ar`?
- [ ] ¿Hay presupuesto/recursos para un dominio propio (gidas.com.ar)?
- [ ] ¿El Drupal soporta menú con enlaces externos?
