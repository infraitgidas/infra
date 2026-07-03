# Cómo conectar un servicio local al portal GIDAS via Cloudflare Tunnel

> Guía paso a paso para exponer un servicio interno (GitLab, Redmine, etc.)
> a través del tunnel Cloudflare + nginx, visible desde el portal GIDAS.
> 
> **Aplica a**: Servicios en la red GIDAS (192.168.1.x)
> **No aplica a**: Servicios externos (Outlook, Drupal UTN, Twingate)

---

## Índice

1. [Arquitectura](#1-arquitectura)
2. [Requisitos](#2-requisitos)
3. [Paso 1: Conectar al servicio](#3-paso-1-conectar-al-servicio)
4. [Paso 2: Configurar nginx en CT 208](#4-paso-2-configurar-nginx-en-ct-208)
5. [Paso 3: Configurar el servicio para subpath](#5-paso-3-configurar-el-servicio-para-subpath)
6. [Paso 4: Agregar al portal](#6-paso-4-agregar-al-portal)
7. [Paso 5: Probar](#7-paso-5-probar)
8. [Referencia: lo que funcionó para cada tool](#8-referencia-lo-que-funcionó-para-cada-tool)
9. [Troubleshooting](#9-troubleshooting)

---

## 1. Arquitectura

```
Usuario → Drupal (gidas.frlp.utn.edu.ar/node/40)
              ↓
       Tunnel Cloudflare → CT 208 (nginx:80)
              ├── / → Portal (login AD + dashboard)
              ├── /nuevatool/ → 🔧 Tu servicio aquí
              └── /otrastool/ → ...

Internamente:
  CT 208 (nginx) → proxy_pass → IP interna del servicio
```

### Flujo de una petición

```
1. Usuario accede a https://xxx.trycloudflare.com/nuevatool/
2. Cloudflare edge recibe y reenvía al tunnel
3. CT 208 (cloudflared) recibe y pasa a nginx (127.0.0.1:80)
4. nginx hace proxy_pass a https://192.168.1.X/
5. Servidor responde con HTML + assets
6. Si el servicio tiene sub_filter configurado, se reescriben las URLs de assets
7. nginx devuelve la respuesta al usuario via tunnel
```

---

## 2. Requisitos

### Tener acceso a:

| Recurso | Cómo |
|---------|------|
| **Servicio interno** | IP y puerto del servicio (ej: 192.168.1.41:443) |
| **CT 208 (portal)** | Via PVE host: `pct enter 208` |
| **nginx en CT 208** | Config en `/etc/nginx/nginx.conf` |
| **Drupal admin** | `https://gidas.frlp.utn.edu.ar/user/login` |
| **Portal config** | `/opt/portal-gidas/config.yaml` en CT 208 |

### El servicio debe:

- Ser accesible desde CT 208 (probá con `curl` desde el CT)
- Tener interfaz web (HTTP/HTTPS)
- Idealmente, soportar configuración de subpath (root_url, external_url, etc.)

---

## 3. Paso 1: Conectar al servicio

### 3.1 Verificar acceso desde CT 208

```bash
# Entrar al CT 208
ssh root@192.168.1.14
pct enter 208

# Probar conexión al servicio (reemplazar IP y puerto)
curl -sk --max-time 5 https://192.168.1.X/
# Debería responder con HTML (200) o redirect (301/302)
```

### 3.2 Verificar resolución DNS

```bash
# Si el servicio usa hostname, verificar que resuelva
getent hosts servicio.gidas.local
# Si no resuelve, usar IP directa o agregar a /etc/hosts
echo "192.168.1.X servicio.gidas.local" >> /etc/hosts
```

---

## 4. Paso 2: Configurar nginx en CT 208

Editar `/etc/nginx/nginx.conf` y agregar un nuevo location block.

### 4.1 Location básico

```nginx
location /nuevatool/ {
    proxy_pass https://192.168.1.X;
    proxy_set_header Host $host;
}
```

Importante:
- **Sin trailing slash** en `proxy_pass` → preserva el subpath al upstream
- **Con trailing slash** → elimina el subpath (ej: `/nuevatool/login` → `/login`)

### 4.2 Location con sub_filter (para asset rewriting)

Si el servicio genera HTML con rutas absolutas (`/assets/...`), necesitás sub_filter:

```nginx
location /nuevatool/ {
    proxy_pass https://192.168.1.X;
    proxy_set_header Host $host;

    # Reescribir assets en HTML
    sub_filter_once off;
    sub_filter_types text/html text/css application/javascript;
    sub_filter 'href="/' 'href="/nuevatool/';
    sub_filter 'src="/' 'src="/nuevatool/';
    sub_filter 'action="/login' 'action="/nuevatool/login';
}
```

### 4.3 Location con proxy_redirect (para redirects post-login)

Si después de login el servicio redirige a su URL interna:

```nginx
location /nuevatool/ {
    proxy_pass https://192.168.1.X;
    proxy_set_header Host $host;
    proxy_redirect https://servicio.gidas.local/ /nuevatool/;
    proxy_redirect http://servicio.gidas.local/ /nuevatool/;
}
```

### 4.4 Recargar nginx

```bash
nginx -t                    # Verificar sintaxis
nginx -s reload             # Recargar sin cortar conexiones
# o
systemctl restart nginx     # Reiniciar completo
```

---

## 5. Paso 3: Configurar el servicio para subpath

Cada servicio necesita conocer su subpath para generar URLs correctas. Si no se configura, los assets (CSS, JS) van a pedirse en la raíz (`/`) en vez de `/nuevatool/`.

### 5.1 Grafana

```ini
[server]
root_url = http://localhost/grafana/
serve_from_sub_path = true
```

### 5.2 GitLab

En `/etc/gitlab/gitlab.rb`:
```ruby
external_url "http://gitlab.gidas.local/gitlab"
```

Luego:
```bash
gitlab-ctl reconfigure
```

### 5.3 Redmine

No necesita configuración de subpath porque usamos `sub_filter` en nginx para reescribir los assets. El nginx de Redmine tiene un `location /redmine/` que rewritea al backend.

### 5.4 LibreNMS

```php
$config["base_url"] = "https://nms.gidas.local/librenms";
```

### 5.5 Vaultwarden

```bash
DOMAIN=https://vault.gidas.local
```

No recomendado exponer via tunnel (gestor de passwords).

---

## 6. Paso 4: Agregar al portal

### 6.1 Editar config.yaml

En CT 208, editar `/opt/portal-gidas/config.yaml`:

```yaml
  - name: "Mi Tool"
    url: "/nuevatool/"
    icon: "fas fa-star"
    description: "Descripción de la tool"
    proxy: false
    groups:
      - "G-Direccion"
      - "G-Coordinadores"
```

Campos:
| Campo | Descripción |
|-------|-------------|
| `name` | Nombre visible en el dashboard |
| `url` | Ruta del nginx (`/nuevatool/`) o URL completa si es externo |
| `icon` | Clase de FontAwesome (`fas fa-...`) |
| `description` | Texto descriptivo |
| `proxy` | `false` si usa nginx, `true` si usa el FastAPI proxy (deprecated) |
| `groups` | Grupos AD que pueden ver la tool |

### 6.2 Reiniciar portal

```bash
systemctl restart portal-gidas
```

---

## 7. Paso 5: Probar

### 7.1 Test local desde CT 208

```bash
# Probar que nginx sirve la tool
curl -sk --max-time 10 http://127.0.0.1/nuevatool/ | head -10
```

### 7.2 Test via tunnel

```bash
# Obtener URL del tunnel
TUNNEL_URL=$(curl -sk https://gidas.frlp.utn.edu.ar/node/40 | grep -oP 'https://[a-z0-9-]+\.trycloudflare\.com' | head -1)

# Probar tool
curl -sk --max-time 15 $TUNNEL_URL/nuevatool/ | head -10
```

### 7.3 Test de assets

```bash
# Verificar que los assets tengan el prefijo correcto
TUNNEL_URL=$(curl -sk https://gidas.frlp.utn.edu.ar/node/40 | grep -oP 'https://[a-z0-9-]+\.trycloudflare\.com' | head -1)

python3 -c "
import requests, urllib3, re
urllib3.disable_warnings()
s = requests.Session()
s.verify = False
s.post('$TUNNEL_URL/login', data={'username':'errodriguez','password':'Gidas2026!'}, timeout=15)
r = s.get('$TUNNEL_URL/nuevatool/', timeout=15)
assets = re.findall(r'(?:src|href)=\"(/[^\"]*)\"', r.text)
broken = [a for a in assets if not a.startswith('/nuevatool/') and not a.startswith('http')]
print(f'Assets: {len(assets)}, broken: {len(broken)}')
if broken:
    for b in broken[:5]:
        print(f'  BROKEN: {b}')
"
```

### 7.4 Test de login

```bash
# Obtener CSRF token y probar login
python3 -c "
import requests, urllib3, re
urllib3.disable_warnings()
s = requests.Session()
s.verify = False
s.post('$TUNNEL_URL/login', data={'username':'errodriguez','password':'Gidas2026!'}, timeout=15)
r = s.get('$TUNNEL_URL/nuevatool/login', timeout=15)
csrf = re.search(r'name=\"authenticity_token\" value=\"([^\"]+)\"', r.text)
if csrf:
    r2 = s.post('$TUNNEL_URL/nuevatool/login', data={
        'authenticity_token': csrf.group(1),
        'username': 'errodriguez',
        'password': 'Gidas2026!',
    }, timeout=15, allow_redirects=False)
    loc = r2.headers.get('location', 'none')
    print(f'Login: {r2.status_code} -> {loc[:80]}')
    print(f'{\"OK\" if \"/nuevatool/\" in loc else \"REVISAR\" }')
"
```

---

## 8. Referencia: lo que funcionó para cada tool

| Tool | IP | Subpath | Configuración necesaria | sub_filter | proxy_redirect |
|------|-----|---------|------------------------|------------|----------------|
| **Grafana** | 192.168.1.205:3000 | `/grafana/` | `root_url` + `serve_from_sub_path` | No | No |
| **GitLab** | 192.168.1.41 | `/gitlab/` | `external_url` | No | Sí |
| **Redmine** | 192.168.1.20 | `/redmine/` | location en nginx de Redmine | Sí | Sí |
| **LibreNMS** | 192.168.1.45 | `/librenms/` | `base_url` + nginx location | No | No |

### Checklist de integración

- [ ] Servicio reachable desde CT 208
- [ ] Location en nginx de CT 208
- [ ] Tool configurada con subpath (si aplica)
- [ ] sub_filter configurado (si tiene assets absolutos)
- [ ] proxy_redirect configurado (si redirect post-login)
- [ ] Entry en config.yaml del portal
- [ ] Portal restart
- [ ] Test local (127.0.0.1)
- [ ] Test via tunnel
- [ ] Test en navegador (limpiar caché)

---

## 9. Troubleshooting

### 9.1 502 Bad Gateway

El servicio no está accesible desde CT 208.

```bash
# Verificar conectividad
curl -sk --max-time 5 https://192.168.1.X/
```

**Posibles causas**: Puerto incorrecto, IP incorrecta, firewall bloqueando, servicio caído.

### 9.2 404 Not Found

El location en nginx no coincide con la URL.

```bash
# Verificar que nginx tenga el location
grep -A5 "nuevatool" /etc/nginx/nginx.conf
```

**Posible causa**: El location no fue recargado después de editarlo.

### 9.3 Assets rotos (CSS sin estilo, JS no carga)

Los assets se piden en la raíz (`/assets/...`) en vez del subpath.

```bash
# Verificar assets en el HTML
curl -sk http://127.0.0.1/nuevatool/ | grep -oP '(?:src|href)="/[^"]*"' | head -10
```

**Solución**: Agregar `sub_filter` en nginx o configurar el `root_url` del servicio.

### 9.4 Redirect loop después de login

El servicio redirige a su URL interna (`https://servicio.gidas.local/...`).

**Solución**: Agregar `proxy_redirect` en nginx.

### 9.5 "nombre de host no resuelve" desde CT 208

El CT 208 no puede resolver `*.gidas.local`.

```bash
# Verificar DNS
cat /etc/resolv.conf
# Debe tener: nameserver 192.168.1.1 (MikroTik)
```

**Solución**: Agregar nameserver del MikroTik o usar IP directa en `proxy_pass`.

---

## Anexo: Comandos rápidos

```bash
# === CT 208 ===
pct enter 208                                          # Entrar al CT
systemctl restart portal-gidas                         # Reiniciar portal
systemctl restart gidas-tunnel                          # Reiniciar tunnel
nginx -t && nginx -s reload                             # Recargar nginx
journalctl -u portal-gidas -n 20 --no-pager             # Ver logs del portal

# === TEST ===
TUNNEL_URL=$(curl -sk https://gidas.frlp.utn.edu.ar/node/40 | grep -oP 'https://[a-z0-9-]+\.trycloudflare\.com' | head -1)
curl -sk --max-time 10 $TUNNEL_URL/nuevatool/           # Test tool via tunnel
curl -sk --max-time 10 http://127.0.0.1/nuevatool/      # Test tool local

# === DRUPAL ===
# URL: https://gidas.frlp.utn.edu.ar/user/login
# Usuario: administrador / Password: Urbano2022*$

# === PORTAL ===
# Config: /opt/portal-gidas/config.yaml
# Logs: journalctl -u portal-gidas -f
```

---

*Última actualización: 2026-07-03*
