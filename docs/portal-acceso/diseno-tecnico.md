# Diseño Técnico Detallado — Portal de Acceso GIDAS

> **Feature**: Portal de Acceso (Feature #6)
> **Rama**: `feat/portal-access-remoto`
> **Versión**: 1.0
> **Fecha**: 2026-07-02

---

## 1. Rutas HTTP

| Método | Ruta | Auth | Descripción |
|--------|------|------|-------------|
| `GET` | `/login` | No | Muestra formulario de login |
| `POST` | `/login` | No | Procesa credenciales, crea sesión JWT |
| `GET` | `/` | Sí | Dashboard con cards filtradas por grupos |
| `GET` | `/logout` | Sí | Elimina cookie JWT, redirige a `/login` |
| `GET` | `/static/{path}` | No | Archivos estáticos (CSS, imágenes) |
| `GET` | `/api/me` | Sí | JSON con datos del usuario (útil para debugging) |

## 2. Estructura de Archivos

```
portal-gidas/
├── app/
│   ├── __init__.py          # App factory
│   ├── main.py              # FastAPI app, middleware, startup
│   ├── config.py            # Pydantic model para config.yaml
│   ├── auth.py              # LDAP bind + group search + JWT
│   ├── models.py            # Schemas Pydantic (request/response)
│   ├── routers/
│   │   ├── __init__.py
│   │   ├── auth.py          # GET/POST /login, GET /logout
│   │   └── portal.py        # GET / (dashboard), GET /api/me
│   ├── services/
│   │   ├── __init__.py
│   │   └── ldap_service.py  # Conexión y operaciones LDAP
│   ├── templates/
│   │   ├── base.html        # Layout: head, nav, footer, bloque content
│   │   ├── login.html       # Formulario de login con error handling
│   │   └── dashboard.html   # Grid de cards filtradas
│   └── static/
│       ├── css/
│       │   └── portal.css
│       └── img/
│           ├── logo-gidas.png
│           └── tools/
│               ├── gitlab.png
│               ├── redmine.png
│               ├── grafana.png
│               ├── proxmox.png
│               ├── netbox.png
│               ├── glpi.png
│               ├── identity.png
│               ├── drupal.png
│               ├── outlook.png
│               └── twingate.png
├── config.yaml              # Config: LDAP + tools + groups
├── Dockerfile               # Multi-stage: build → runtime
├── Makefile                 # build, run, stop, logs
├── requirements.txt         # FastAPI, uvicorn, ldap3, pyjwt, pyyaml
└── README.md                # Deploy, config, maintenance
```

## 3. Flujo Detallado de Cada Ruta

### 3.1. `GET /login`

```
1. Verificar si el usuario ya tiene cookie JWT válida
   ├─ Sí → redirect 302 → /
   └─ No → renderizar login.html con formulario vacío
```

**login.html**: Formulario con:
- Campo `username` (text, autofocus)
- Campo `password` (password)
- Botón "Ingresar"
- Mensaje de error (si `?error=1`)

### 3.2. `POST /login`

```
1. Validar que username y password no estén vacíos
2. Conectar a AD GDC01:
   a. LDAP bind con cuenta de servicio (infrait)
   b. Buscar usuario por sAMAccountName
   c. Obtener DN del usuario
   d. Hacer bind como el usuario (verifica password)
   e. Buscar atributo memberOf del usuario
   f. Extraer CN de cada grupo (ej: CN=G-Direccion,OU=Groups,...)
3. Si auth falla → redirect /login?error=1
4. Si auth ok:
   a. Crear JWT con: sub=username, groups=[lista de CNs], exp=8h
   b. Setear cookie HttpOnly, SameSite=Lax
   c. Redirect 302 → /
```

### 3.3. `GET /` (Dashboard)

```
1. Leer cookie JWT
   ├─ Sin cookie o inválida → redirect /login
   └─ Válida → decodificar username y groups
2. Cargar config.yaml
3. Filtrar tools donde el usuario tenga al menos UN grupo en común
   └─ (intersection entre groups del user y groups de la tool)
4. Renderizar dashboard.html con:
   - username (para mostrar "Bienvenido, {user}")
   - tools filtradas (name, url, icon, description)
   - link de logout
```

### 3.4. `GET /logout`

```
1. Eliminar cookie JWT (setear con max_age=0)
2. Redirect 302 → /login
```

## 4. Modelo de Configuración (config.yaml)

```yaml
portal:
  title: "Portal GIDAS"
  subtitle: "Grupo de Investigación y Desarrollo Aplicado en Sistemas"
  logo: "logo-gidas.png"
  session_duration_hours: 8

ldap:
  host: "192.168.1.117"
  port: 389
  use_ssl: false
  bind_dn: "CN=infrait,OU=ServiceAccounts,DC=GDC01,DC=local"
  # bind_password: se lee de env var LDAP_BIND_PASSWORD
  base_dn: "DC=GDC01,DC=local"
  user_search_filter: "(sAMAccountName={username})"
  group_attribute: "memberOf"
  group_cn_regex: "^CN=(?P<cn>[^,]+)"

tools:
  - name: "GitLab"
    url: "https://gitlab.gidas.local"
    icon: "gitlab.png"
    description: "Repositorios y CI/CD"
    groups:
      - "G-Direccion"
      - "G-Coordinadores"
      - "G-Becarios"
      - "G-Graduados"
      - "G-Pasantes"
      - "G-Externos"

  - name: "Redmine"
    url: "https://redmine.gidas.local"
    icon: "redmine.png"
    description: "Gestión de proyectos"
    groups:
      - "G-Direccion"
      - "G-Coordinadores"
      - "G-Becarios"
      - "G-Graduados"
      - "G-Pasantes"

  - name: "Grafana"
    url: "http://192.168.1.205:3000"
    icon: "grafana.png"
    description: "Monitoreo y métricas"
    groups:
      - "G-Direccion"
      - "G-Coordinadores"

  - name: "Proxmox VE"
    url: "https://192.168.1.14:8006"
    icon: "proxmox.png"
    description: "Hipervisor"
    groups:
      - "G-Direccion"
      - "G-Coordinadores"

  - name: "NetBox"
    url: "http://netbox.gidas.local"
    icon: "netbox.png"
    description: "CMDB - Inventario"
    groups:
      - "G-Direccion"
      - "G-Coordinadores"
      - "G-Becarios"

  - name: "GLPI"
    url: "http://glpi.gidas.local"
    icon: "glpi.png"
    description: "ITSM - Mesa de ayuda"
    groups:
      - "G-Direccion"
      - "G-Coordinadores"

  - name: "Identity Dashboard"
    url: "https://gitlab.gidas.local/infrait/identity-dashboard"
    icon: "identity.png"
    description: "Gestión de usuarios AD/FreeIPA"
    groups:
      - "G-Direccion"
      - "G-Coordinadores"

  - name: "MikroTik"
    url: "http://192.168.1.1"
    icon: "mikrotik.png"
    description: "Router y firewall"
    groups:
      - "G-Direccion"
      - "G-Coordinadores"
```

## 5. Seguridad Detallada

### 5.1. JWT

```python
# claims del JWT
{
  "sub": "infrait",          # sAMAccountName
  "groups": [                # CN de grupos AD
    "G-Direccion",
    "G-Coordinadores"
  ],
  "exp": 1783012345,         # timestamp expiración (8h)
  "iat": 1782982345          # timestamp emisión
}
```

- Algoritmo: `HS256`
- Secret key: generada al azar en deploy, configurable vía `JWT_SECRET` env var
- Cookie: `gidas_session`, HttpOnly, SameSite=Lax, Path=/, Secure si HTTPS

### 5.2. LDAP

```python
# Conexión (context manager)
with LDAPConnection(host, port) as conn:
    # 1. Bind con service account
    conn.bind(bind_dn, bind_password)
    
    # 2. Buscar DN del usuario
    user_dn = conn.search(base_dn, f"(sAMAccountName={username})")
    
    # 3. Verificar password (bind como el usuario)
    conn.bind(user_dn, password)  # si falla → auth error
    
    # 4. Buscar grupos
    attrs = conn.get_attributes(user_dn, ["memberOf"])
    groups = extract_cn(attrs["memberOf"])
```

### 5.3. Validación de Input

- Username: solo alfanumérico + `.` + `-` (regex: `^[\w\.-]+$`)
- Password: se envía por POST, se procesa en memoria, se descarta
- Todas las respuestas JSON tienen `Content-Type: application/json`

## 6. Frontend

### 6.1. Templates

**base.html** (layout):
```html
<!DOCTYPE html>
<html>
<head>
  <title>{% block title %}{{ config.portal.title }}{% endblock %}</title>
  <link rel="stylesheet" href="/static/css/portal.css">
  <link rel="icon" href="/static/img/logo-gidas.png">
</head>
<body>
  <nav>
    <img src="/static/img/logo-gidas.png" height="40" alt="GIDAS">
    <span>{{ config.portal.title }}</span>
    {% if user %}
      <span class="user-info">{{ user }} | <a href="/logout">Salir</a></span>
    {% endif %}
  </nav>
  <main>{% block content %}{% endblock %}</main>
</body>
</html>
```

**login.html**:
```html
{% extends "base.html" %}
{% block content %}
<div class="login-container">
  <h2>Iniciar Sesión</h2>
  <p>Use su usuario y contraseña de AD GIDAS</p>
  {% if error %}
  <div class="alert alert-error">Usuario o contraseña incorrectos</div>
  {% endif %}
  <form method="POST" action="/login">
    <input type="text" name="username" placeholder="Usuario" required autofocus>
    <input type="password" name="password" placeholder="Contraseña" required>
    <button type="submit">Ingresar</button>
  </form>
</div>
{% endblock %}
```

**dashboard.html**:
```html
{% extends "base.html" %}
{% block content %}
<div class="dashboard">
  <h2>Bienvenido, {{ username }}</h2>
  <div class="card-grid">
    {% for tool in tools %}
    <a href="{{ tool.url }}" target="_blank" rel="noopener" class="card">
      <img src="/static/img/tools/{{ tool.icon }}" alt="{{ tool.name }}">
      <h3>{{ tool.name }}</h3>
      <p>{{ tool.description }}</p>
    </a>
    {% endfor %}
  </div>
</div>
{% endblock %}
```

### 6.2. Estilos

CSS vanilla con:
- Variables CSS para colores institucionales GIDAS/UTN
- Grid responsive (3 columns → 2 → 1 según viewport)
- Cards con hover effect
- Login centrado con sombra
- Sin frameworks CSS externos

### 6.3. Alpine.js (opcional)

Solo si necesitamos interactividad extra:
- Filtro por nombre de herramienta en el dashboard
- Sin Alpine si no se justifica

## 7. Manejo de Errores

| Situación | HTTP | Respuesta |
|-----------|------|-----------|
| Login sin credenciales | 400 | redirect /login?error=1 |
| Credenciales inválidas | 401 | redirect /login?error=1 |
| Usuario no encontrado en AD | 401 | redirect /login?error=1 |
| AD inaccesible | 503 | redirect /login?error=2 |
| JWT inválido/expirado | 401 | redirect /login |
| Tool no encontrada en config | 500 | log + página de error |
| Config mal formada | 500 | log + no arranca |

## 8. Tests

| Tipo | Qué probar |
|------|-----------|
| **Unitarios** | auth.py: parseo de grupos desde DN, validación de JWT, filtrado de tools |
| **Integración** | ldap_service.py: conexión real contra AD, bind, search |
| **E2E** | Login con usuario real AD, ver dashboard filtrado, logout |

No usar pytest? Usar unittest estándar. Priorizar test de lógica de negocio sobre test de infraestructura.

## 9. Deploy

### Opción A: Docker (recomendada)
```bash
docker build -t portal-gidas .
docker run -d --name portal-gidas \
  -p 80:80 \
  -e JWT_SECRET="$(openssl rand -hex 32)" \
  -e LDAP_BIND_PASSWORD="Gidas2026!" \
  -v $(pwd)/config.yaml:/app/config.yaml:ro \
  portal-gidas
```

### Opción B: Directo (sin Docker)
```bash
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
export JWT_SECRET="$(openssl rand -hex 32)"
export LDAP_BIND_PASSWORD="Gidas2026!"
uvicorn app.main:app --host 0.0.0.0 --port 80
```

## 10. Criterios de Aceptación

| # | Criterio | Cómo se verifica |
|---|----------|-----------------|
| 1 | Usuario AD puede loguearse con su usuario y contraseña | Login exitoso, ve dashboard |
| 2 | Usuario ve solo las tools de sus grupos | Comparar con reglas de config.yaml |
| 3 | Sin sesión activa, redirige a login | Cerrar navegador, volver a portal |
| 4 | JWT expirado pide login de nuevo | Esperar 8h o manipular exp |
| 5 | Usuario sin grupo no ve tools | Dashboard vacío (no error) |
| 6 | AD caído muestra error amigable | Detener AD, intentar login |
| 7 | Nueva tool en config aparece para los grupos correctos | Editar YAML, reiniciar app |
