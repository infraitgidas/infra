# Arquitectura — Portal de Acceso GIDAS

> **Feature**: Portal de Acceso (Feature #6)
> **Rama**: `feat/portal-access-remoto`
> **Versión**: 1.0
> **Fecha**: 2026-07-02

---

## 1. Visión General

Portal web liviano que permite a los miembros de GIDAS autenticarse con su usuario de AD y acceder únicamente a las herramientas que corresponden a su perfil (según grupos AD).

```
                    ┌──────────────────────────────────┐
                    │        Portal GIDAS              │
                    │  (FastAPI + Jinja2 + LDAP)       │
                    │                                  │
                    │  Login → JWT → Dashboard         │
                    │         ↓                        │
                    │  Filtrado por grupos AD          │
                    └──────────┬───────────────────────┘
                               │
              ┌────────────────┼────────────────┐
              │                │                │
              ▼                ▼                ▼
        ┌──────────┐     ┌──────────┐     ┌──────────┐
        │ GitLab   │     │ Redmine  │     │ Grafana  │  ...
        │ (AD auth)│     │ (AD auth)│     │ (AD auth)│
        └──────────┘     └──────────┘     └──────────┘
```

---

## 2. Principios de Diseño

| Principio | Explicación |
|-----------|-------------|
| **Simplicidad** | Un proceso (FastAPI), sin workers, sin colas, sin DB externa |
| **Configuración declarativa** | Todo el mapeo grupos→herramientas está en YAML versionado |
| **Stateless** | Sesiones vía JWT firmado (sin sesiones en servidor) |
| **Seguridad** | Las credenciales AD nunca se almacenan; solo se usan para el bind LDAP |
| **Portabilidad** | Docker o `systemd` — elige el que prefieras |

---

## 3. Stack Tecnológico

| Capa | Tecnología | Versión | Justificación |
|------|-----------|---------|---------------|
| **Backend** | Python + FastAPI | 3.11+ / 0.115+ | Liviano, async, tipado, excelente DX |
| **Auth** | ldap3 | 2.9+ | Librería LDAP más madura en Python |
| **Sesiones** | PyJWT + itsdangerous | 2.8+ | Tokens firmados, sin estado en servidor |
| **Frontend** | Jinja2 + Alpine.js | 3.1+ / 3.14+ | SSR sin SPA; Alpine para interactividad mínima |
| **Estilos** | CSS vanilla + Font Awesome | — | Sin dependencias CSS, FA para íconos |
| **Config** | YAML + pydantic-settings | 2.0+ | Validación de schema en carga |
| **Container** | Docker (opcional) | — | Multi-stage: build y runtime |
| **Servidor** | uvicorn | 0.30+ | ASGI server para FastAPI |

---

## 4. Componentes

### 4.1. Módulos del Sistema

```
portal-gidas/
├── app/
│   ├── __init__.py
│   ├── main.py              # FastAPI app, middlewares, routers
│   ├── config.py            # Carga y validación de config.yaml
│   ├── auth.py              # Lógica LDAP + JWT
│   ├── models.py            # Pydantic models
│   ├── templates/           # Jinja2 templates
│   │   ├── base.html        # Layout común (head, nav, footer)
│   │   ├── login.html       # Pantalla de login
│   │   └── dashboard.html   # Dashboard con cards
│   └── static/              # CSS, JS, imágenes
│       ├── css/
│       │   └── portal.css
│       └── img/
│           ├── logo-gidas.png
│           └── tools/        # Íconos de herramientas
├── config.yaml              # Configuración de herramientas y grupos
├── Dockerfile               # Multi-stage build
├── Makefile                 # Comandos rápidos
├── requirements.txt         # Dependencias Python
└── README.md                # Documentación operativa
```

### 4.2. Flujo de Autenticación

```
Browser                  FastAPI                   AD GDC01
   │                        │                         │
   │  GET /login            │                         │
   │◄─────── HTML form ─────│                         │
   │                        │                         │
   │  POST /login           │                         │
   │  user + password ─────►│                         │
   │                        │  LDAP bind              │
   │                        │────────────────────────►│
   │                        │◄──── Success/DN ────────│
   │                        │                         │
   │                        │  LDAP search groups      │
   │                        │  (memberOf del usuario)  │
   │                        │────────────────────────►│
   │                        │◄─── lista de grupos ────│
   │                        │                         │
   │                        │  Generar JWT             │
   │                        │  (user + grupos)         │
   │  Set-Cookie: token     │                         │
   │◄─────── redirect / ────│                         │
   │                        │                         │
   │  GET / (con cookie)    │                         │
   │──────────────►         │                         │
   │                        │  Validar JWT             │
   │                        │  Filtrar tools por grupo │
   │◄────── dashboard ──────│                         │
```

### 4.3. Modelo de Datos

```yaml
# config.yaml
portal:
  title: "Portal GIDAS"
  subtitle: "Grupo de Investigación y Desarrollo Aplicado en Sistemas"
  logo: "logo-gidas.png"

ldap:
  host: "192.168.1.117"
  port: 389
  bind_dn: "CN=infrait,OU=ServiceAccounts,DC=GDC01,DC=local"
  bind_password: "Gidas2026!"  # o desde variable de entorno
  base_dn: "DC=GDC01,DC=local"
  user_attr: "sAMAccountName"
  group_attr: "memberOf"

tools:
  - name: "GitLab"
    url: "https://gitlab.gidas.local"
    icon: "gitlab.png"
    description: "Repositorios y CI/CD"
    groups: ["G-Direccion", "G-Coordinadores", "G-Becarios", "G-Graduados", "G-Pasantes", "G-Externos"]

  - name: "Redmine"
    url: "https://redmine.gidas.local"
    icon: "redmine.png"
    description: "Gestión de proyectos"
    groups: ["G-Direccion", "G-Coordinadores", "G-Becarios", "G-Graduados", "G-Pasantes"]

  - name: "Grafana"
    url: "http://192.168.1.205:3000"
    icon: "grafana.png"
    description: "Monitoreo y métricas"
    groups: ["G-Direccion", "G-Coordinadores"]

  - name: "Proxmox VE"
    url: "https://192.168.1.14:8006"
    icon: "proxmox.png"
    description: "Hipervisor"
    groups: ["G-Direccion", "G-Coordinadores"]

  - name: "NetBox"
    url: "http://netbox.gidas.local"
    icon: "netbox.png"
    description: "CMDB - Inventario"
    groups: ["G-Direccion", "G-Coordinadores", "G-Becarios"]

  - name: "GLPI"
    url: "http://glpi.gidas.local"
    icon: "glpi.png"
    description: "ITSM - Mesa de ayuda"
    groups: ["G-Direccion", "G-Coordinadores"]
```

---

## 5. Seguridad

| Aspecto | Implementación |
|---------|---------------|
| **Password AD** | Nunca se almacena. Solo se usa para el LDAP bind en memoria, se descarta al finalizar la request |
| **Sesión** | JWT firmado con HMAC-SHA256. Cookie `HttpOnly`, `Secure` (si HTTPS), `SameSite=Lax` |
| **Expiración** | JWT expira en 8 horas. Sin refresh token (si expira, vuelve a login) |
| **Grupos** | Se obtienen de AD vía `memberOf` en cada login. No se cachean (cambios en AD se reflejan al próximo login) |
| **CSRF** | Las únicas mutaciones son POST a `/login` y `/logout`. No hay formularios que modifiquen datos. |

---

## 6. Restricciones y Trade-offs

| Decisión | Alternativa descartada | Motivo |
|----------|----------------------|--------|
| **Sin DB** | SQLite, PostgreSQL | No hay estado que persistir. El YAML es la fuente de verdad. |
| **JWT stateless** | Sesiones en servidor | Escala horizontalmente sin compartir sesiones. Cero config. |
| **SSR (Jinja2)** | SPA (React/Vue) | Más simple, menos JS, carga instantánea, accesible sin JS. |
| **Alpine.js mínimo** | Vanilla JS | Interactividad sin framework pesado. 14KB comprimido. |
| **Sin CI/CD** | GitHub Actions | No justificado para 1 CT con 1 container. Deploy manual vía Makefile. |

---

## 7. Requisitos de Infraestructura

| Recurso | Valor |
|---------|-------|
| **CPU** | 0.5 vCPU (1 core compartido) |
| **RAM** | 128 MB (256 MB con headroom) |
| **Disco** | 500 MB (app + Python + imágenes) |
| **CT existente** | CT 208 (portal, Rocky 9, 192.168.1.43) |
| **Puertos** | 80 (HTTP) o 443 (HTTPS) |
| **Dependencias** | Acceso a AD GDC01 (192.168.1.117:389) |
| **Runtime** | Python 3.11+ o Docker |

---

## 8. Próximos Pasos

1. ✅ Documentar lecciones aprendidas
2. ✅ Definir arquitectura
3. 🔲 Crear diseño técnico detallado (rutas, templates, config)
4. 🔲 Implementar MVP
5. 🔲 Probar con usuarios reales
6. 🔲 Documentar operación
