# Guía de Administración — Portal GIDAS

> **CT**: 208 — `192.168.1.43` — `portal.gidas.local`
> **Última actualización**: 2026-07-02

---

## 1. Arquitectura

```
┌─ CT 208 (Rocky Linux 9) ─────────────────────────────┐
│                                                       │
│  systemd: portal-gidas.service                        │
│  ┌─────────────────────────────────────────────────┐  │
│  │  uvicorn (Python 3.11) — puerto 80              │  │
│  │  ┌───────────────────────────────────────────┐  │  │
│  │  │  FastAPI app                              │  │  │
│  │  │  ├── /login (GET/POST)                    │  │  │
│  │  │  ├── /logout (GET)                        │  │  │
│  │  │  ├── / (GET — dashboard filtrado)         │  │  │
│  │  │  ├── /api/me (GET — JSON con datos user)  │  │  │
│  │  │  └── /static/* (CSS, imágenes)            │  │  │
│  │  └───────────────────────────────────────────┘  │  │
│  └─────────────────────────────────────────────────┘  │
│                                                       │
│  Dependencias:                                        │
│  • AD GDC01 (192.168.1.117:389)                       │
│  • Config YAML: /opt/portal-gidas/config.yaml         │
│  • Secret JWT: generado en deploy                     │
│                                                       │
└───────────────────────────────────────────────────────┘
```

---

## 2. Acceso al Servidor

```bash
# Via PVE host (recomendado)
ssh root@192.168.1.14
pct enter 208

# O via SSH directo (si se configuró)
ssh root@192.168.1.43
```

---

## 3. Gestión del Servicio

### Estado
```bash
systemctl status portal-gidas
```

### Logs
```bash
journalctl -u portal-gidas -f
journalctl -u portal-gidas --since "1 hour ago"
journalctl -u portal-gidas -p err -n 20  # solo errores
```

### Reiniciar
```bash
systemctl restart portal-gidas
```

### Detener
```bash
systemctl stop portal-gidas
```

---

## 4. Configuración

### 4.1. Archivo principal

`/opt/portal-gidas/config.yaml`

```yaml
portal:
  title: "Portal GIDAS"
  subtitle: "Grupo de Investigación y Desarrollo Aplicado en Sistemas"
  logo: "logo-gidas.png"
  session_duration_hours: 8        # Duración de sesión JWT

ldap:
  host: "192.168.1.117"            # AD GDC01
  port: 389
  use_ssl: false
  bind_dn: "CN=infrait,OU=ServiceAccounts,DC=GDC01,DC=local"
  base_dn: "DC=GDC01,DC=local"
  user_search_filter: "(sAMAccountName={username})"
  group_attribute: "memberOf"

tools:
  - name: "GitLab"
    url: "https://gitlab.gidas.local"
    icon: "fab fa-gitlab"          # Clase Font Awesome
    description: "Repositorios y CI/CD"
    groups: ["G-Direccion", "G-Coordinadores"]
```

### 4.2. Cómo agregar una herramienta nueva

1. Editá `config.yaml`
2. Agregá un nuevo bloque bajo `tools:`:

```yaml
  - name: "Nueva Tool"
    url: "https://nueva-tool.gidas.local"
    icon: "fas fa-cog"
    description: "Descripción breve"
    groups:
      - "G-Direccion"
      - "G-Coordinadores"
```

3. Los íconos válidos son clases de [Font Awesome](https://fontawesome.com/icons):
   - `fas fa-*` — íconos sólidos
   - `fab fa-*` — íconos de marcas (gitlab, github, etc.)
   - `far fa-*` — íconos regulares

4. Reiniciá el servicio:
```bash
systemctl restart portal-gidas
```

### 4.3. Cómo cambiar grupos de acceso

Editá el campo `groups` de la herramienta correspondiente en `config.yaml`. Usá los nombres de grupo AD **exactos** (case-sensitive):

Grupos AD disponibles en GDC01:
- `G-Direccion`
- `G-Coordinadores`
- `G-Becarios`
- `G-Graduados`
- `G-Pasantes`
- `G-Externos`
- `G-IdentityAdmins`
- `G-Practicas`
- `APP-Redmine`
- `PROY-INFRAiT`, `PROY-CAPNEE`, `PROY-GIS`, `PROY-GMET`, `PROY-Telepark`

### 4.4. Cómo cambiar la duración de la sesión

Modificá `session_duration_hours` en `config.yaml`. El valor está en horas. Cambios requieren reinicio del servicio.

---

## 5. Variables de Entorno

Definidas en `/etc/systemd/system/portal-gidas.service`:

| Variable | Descripción | Dónde obtenerla |
|----------|-------------|-----------------|
| `JWT_SECRET` | Clave para firmar tokens de sesión | Generar con `openssl rand -hex 32` |
| `LDAP_BIND_PASSWORD` | Password del bind DN (infrait) | Secretos del proyecto |
| `CONFIG_PATH` | Ruta al archivo config.yaml | `/opt/portal-gidas/config.yaml` |
| `DEBUG` | Modo debug (true/false) | Solo desarrollo |

Para cambiar una variable:
```bash
systemctl edit portal-gidas
# Agregar:
[Service]
Environment=JWT_SECRET=nuevo-valor
systemctl daemon-reload
systemctl restart portal-gidas
```

**⚠️ Cambiar JWT_SECRET invalida todas las sesiones activas.**

---

## 6. Grupos AD y Permisos

### Cómo verificar los grupos de un usuario

```bash
# Desde el CT
ldapsearch -x -H ldap://192.168.1.117 \
  -D 'CN=infrait,OU=ServiceAccounts,DC=GDC01,DC=local' \
  -w 'Gidas2026!' \
  -b 'DC=GDC01,DC=local' \
  "(sAMAccountName=infrait)" memberOf
```

### Cómo listar todos los grupos AD

```bash
ldapsearch -x -H ldap://192.168.1.117 \
  -D 'CN=infrait,OU=ServiceAccounts,DC=GDC01,DC=local' \
  -w 'Gidas2026!' \
  -b 'DC=GDC01,DC=local' \
  "(objectClass=group)" cn | grep '^cn:'
```

---

## 7. Logs y Debugging

### Verificar que el portal responde
```bash
curl -s http://127.0.0.1/login | head -5
```

### Probar login contra AD manualmente
```bash
python3 -c "
from app.services.ldap_service import authenticate
try:
    user, groups = authenticate(
        host='192.168.1.117', port=389,
        bind_dn='CN=infrait,OU=ServiceAccounts,DC=GDC01,DC=local',
        bind_password='Gidas2026!',
        base_dn='DC=GDC01,DC=local',
        search_filter='(sAMAccountName={username})',
        group_attribute='memberOf',
        username='infrait', password='Gidas2026!'
    )
    print(f'OK: {user}, groups: {groups}')
except Exception as e:
    print(f'ERROR: {e}')
"
```

### Probar sesión JWT
```bash
python3 -c "
from app.auth import create_token, decode_token
token = create_token('testuser', ['G-Direccion'], 'test-secret', duration_hours=1)
payload = decode_token(token, 'test-secret')
print(f'Token válido: {payload}')
"
```

### Forzar renovación de secret
```bash
# Generar nuevo JWT_SECRET
openssl rand -hex 32
# Actualizar en systemd y reiniciar
systemctl edit portal-gidas
systemctl daemon-reload
systemctl restart portal-gidas
```

---

## 8. Actualización del Portal

```bash
cd /opt/portal-gidas
git pull origin feat/portal-access-remoto

# Si cambian dependencias
pip install -r requirements.txt

# Si cambian assets estáticos (CSS, imágenes) o templates
# solo reiniciar
systemctl restart portal-gidas
```

---

## 9. Rollback

### Revertir a Homer (portal anterior)

```bash
# 1. Detener portal custom
systemctl stop portal-gidas
systemctl disable portal-gidas

# 2. Restaurar nginx + Homer
systemctl enable --now nginx

# 3. Verificar
curl -s http://127.0.0.1/ | head -5
```

### Revertir cambios de configuración

```bash
# Restaurar config.yaml de backup
cp /opt/portal-gidas/config.yaml.backup.$(date +%Y%m%d) /opt/portal-gidas/config.yaml
systemctl restart portal-gidas
```

---

## 10. Actualizar JWT_SECRET (rotación programada)

```bash
# 1. Generar nuevo secret
NEW_SECRET=$(openssl rand -hex 32)

# 2. Actualizar en systemd
systemctl set-environment JWT_SECRET=$NEW_SECRET

# 3. Reiniciar (invalida sesiones activas)
systemctl restart portal-gidas

# 4. Verificar
journalctl -u portal-gidas -n 5
```

---

## 11. Troubleshooting

| Problema | Causa posible | Solución |
|----------|---------------|----------|
| Portal no responde | Servicio caído | `systemctl restart portal-gidas` |
| Login falla con "AD inaccesible" | AD GDC01 caído o no reachable | Verificar conectividad: `ping 192.168.1.117` |
| Login falla con "credenciales inválidas" | Password incorrecto o usuario no existe | Verificar con `ldapsearch` |
| Usuario ve dashboard vacío | El usuario no tiene grupos configurados | Verificar `memberOf` del usuario en AD |
| Nueva tool no aparece | Config no reloaded | `systemctl restart portal-gidas` |
| Error 500 en dashboard | Config YAML inválido | Verificar sintaxis: `python3 -c "import yaml; yaml.safe_load(open('config.yaml'))"` |
| Sesiones expiran muy rápido | `session_duration_hours` muy bajo | Modificar en config.yaml |

---

## 12. Archivos del Proyecto

| Archivo | Ruta en el CT | Propósito |
|---------|---------------|-----------|
| App principal | `/opt/portal-gidas/app/` | Código Python |
| Config | `/opt/portal-gidas/config.yaml` | Configuración |
| Templates | `/opt/portal-gidas/app/templates/` | HTML Jinja2 |
| Estáticos | `/opt/portal-gidas/app/static/` | CSS, imágenes |
| Service | `/etc/systemd/system/portal-gidas.service` | Systemd unit |
| Logs | `journalctl -u portal-gidas` | Logs del servicio |
