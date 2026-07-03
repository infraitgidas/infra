# Mantenimiento de la Conexión Remota — Cloudflare Tunnel + Drupal

> Cómo funciona, cómo se actualiza y qué hacer si se cae.

---

## 1. Arquitectura de la Conexión

```
USUARIO → Navegador Web
              │
              ▼
    ┌─────────────────────────┐
    │  gidas.frlp.utn.edu.ar  │  ← Sitio Drupal (público, UTN-FRLP)
    │  /node/40               │
    │  "Portal GIDAS"         │
    └─────────┬───────────────┘
              │ click en botón "ACCEDER AL PORTAL GIDAS"
              ▼
    ┌─────────────────────────┐
    │  https://xxx.trycloudflare.com │  ← Cloudflare Tunnel (URL temporal)
    └─────────┬───────────────┘
              │ (túnel cifrado)
              ▼
    ┌─────────────────────────┐
    │  CT 208 (cloudflared)   │  ← Container Rocky Linux 9
    │  192.168.1.43           │
    └─────────┬───────────────┘
              │ proxy reverso
              ▼
    ┌─────────────────────────┐
    │  Portal GIDAS           │
    │  (FastAPI + LDAP)       │
    │  http://192.168.1.43:80 │
    └─────────────────────────┘
```

### Componentes

| Componente | Rol | Quién lo administra |
|-----------|-----|---------------------|
| **Drupal** | Página pública con enlace | Admin Drupal (credenciales en doc sensible) |
| **Cloudflare Tunnel** | Puente HTTPS público → interno | Automático (systemd en CT 208) |
| **CT 208** | Servidor del portal + tunnel | Admin PVE (root@192.168.1.14) |
| **Portal GIDAS** | App web con login AD | Admin del portal |

---

## 2. ¿Cómo se actualiza la URL automáticamente?

### El ciclo completo

```
1. Servidor arranca → systemd inicia gidas-tunnel.service
2. El script /opt/portal-gidas/auto-tunnel.py ejecuta cloudflared
3. cloudflared crea un túnel y genera una URL como:
   https://palabras-aleatorias.trycloudflare.com
4. El script detecta la URL en los logs
5. El script se loguea en Drupal como administrador
6. Obtiene el formulario de edición de /node/40
7. Reemplaza el contenido con la nueva URL
8. Guarda la página
9. El túnel queda corriendo. Si se cae, systemd lo reinicia (paso 1)
```

### ¿Cada cuánto cambia la URL?

| Evento | ¿Cambia la URL? |
|--------|----------------|
| Servicio se reinicia | ✅ Sí (nueva URL aleatoria) |
| CT 208 se reinicia | ✅ Sí |
| Se cae el tunnel | ✅ Sí (systemd reinicia → nueva URL) |
| Script corriendo estable | ❌ No (misma URL mientras viva el proceso) |

### En producción

Cada vez que la URL cambia, la página de Drupal se actualiza **automáticamente en segundos**. No requiere intervención manual.

---

## 3. Verificar que funciona

### Desde el navegador (recomendado)

```
1. Abrir https://gidas.frlp.utn.edu.ar/node/40
2. Verificar que se vea el botón rojo "ACCEDER AL PORTAL GIDAS"
3. Click en el botón → debe redirigir al login del portal
```

### Desde terminal (CT 208)

```bash
# Entrar al CT 208
ssh root@192.168.1.14
pct enter 208

# Ver URL actual publicada en Drupal
curl -sk "https://gidas.frlp.utn.edu.ar/node/40" | grep -oP 'https://[a-z0-9-]+\.trycloudflare\.com'

# Ver servicio
systemctl status gidas-tunnel

# Ver logs recientes
journalctl -u gidas-tunnel -n 20 --no-pager

# Ver tunnel activo
ps aux | grep cloudflared
```

---

## 4. Si el portal no está accesible

### Paso 1: Verificar el servicio

```bash
ssh root@192.168.1.14
pct enter 208

systemctl status gidas-tunnel
# → Debe decir: active (running)
```

### Paso 2: Si el servicio está caído

```bash
# Arrancarlo manualmente
systemctl start gidas-tunnel

# Ver progreso
journalctl -u gidas-tunnel -f
# → Debe mostrar: "Tunnel URL: https://..."
# → Debe mostrar: "Drupal update: OK"
```

### Paso 3: Si el servicio no arranca

```bash
# Ver el error
journalctl -u gidas-tunnel -n 50 --no-pager

# Probar el script manualmente
/opt/portal-gidas/auto-tunnel.py

# Verificar cloudflared
/usr/local/bin/cloudflared version
```

### Paso 4: Si Drupal no se actualiza

```bash
# Verificar que Drupal sea accesible desde CT 208
curl -sk "https://gidas.frlp.utn.edu.ar/node/40"

# Verificar credenciales Drupal (doc sensible)
# Probar login desde CT 208
python3 -c "
import requests
s = requests.Session()
s.verify = False
r = s.get('https://gidas.frlp.utn.edu.ar/user/login')
# ... (usar credenciales del doc sensible)
"
```

### Paso 5: Último recurso — Actualizar Drupal manualmente

Si el script no puede actualizar Drupal automáticamente:

```
1. Abrir https://gidas.frlp.utn.edu.ar/user/login
2. Usuario: administrador / Password: (ver doc sensible)
3. Ir a: Contenido → Portal GIDAS - Acceso a Herramientas → Editar
4. Reemplazar la URL del túnel en el enlace
5. Guardar
```

Para obtener la URL actual del túnel:

```bash
ssh root@192.168.1.14
pct enter 208

# Si el tunnel está activo, la URL está en el log
grep trycloudflare /var/log/cloudflared.log

# Si no hay tunnel activo, iniciar uno de prueba
cloudflared tunnel --url http://192.168.1.43 --no-autoupdate
# → Copiar la URL que aparece
```

---

## 5. Actualización manual de la URL (sin automation)

Si necesitás cambiar la URL manualmente (ej: porque el script no funciona):

### Opción A: Desde el admin de Drupal (más fácil)

```
1. https://gidas.frlp.utn.edu.ar/user/login
2. Usuario: administrador / Password: (doc sensible)
3. Ir a Contenido → Buscar "Portal GIDAS - Acceso a Herramientas" → Editar
4. En el editor de texto, buscar la URL del túnel
5. Reemplazar con la nueva URL
6. Guardar
```

### Opción B: Desde terminal (script manual)

```bash
ssh root@192.168.1.14
pct enter 208

# Obtener nueva URL
NUEVA_URL=$(cloudflared tunnel --url http://192.168.1.43 --no-autoupdate 2>&1 | grep -oP 'https://[a-z0-9-]+\.trycloudflare\.com')
echo "Nueva URL: $NUEVA_URL"

# Actualizar Drupal
python3 -c "
import requests, re
s = requests.Session()
s.verify = False

# Login Drupal
r = s.get('https://gidas.frlp.utn.edu.ar/user/login')
fb = re.search(r'name=\"form_build_id\" value=\"([^\"]+)\"', r.text)
s.post('https://gidas.frlp.utn.edu.ar/user/login', data={
    'name': 'administrador', 'pass': 'Urbano2022*\$',
    'form_build_id': fb.group(1), 'form_id': 'user_login_form', 'op': 'Iniciar sesion'
})

# Editar página
r = s.get('https://gidas.frlp.utn.edu.ar/node/40/edit')
inputs = re.findall(r'<input[^>]*name=\"([^\"]+)\"[^>]*value=\"([^\"]*)\"', r.text)
data = {n:v for n,v in inputs}
ft = re.search(r'name=\"form_token\" value=\"([^\"]+)\"', r.text)
fi = re.search(r'name=\"form_id\" value=\"([^\"]+)\"', r.text)
fb = re.search(r'name=\"form_build_id\" value=\"([^\"]+)\"', r.text)
if ft: data['form_token'] = ft.group(1)
if fi: data['form_id'] = fi.group(1)
if fb: data['form_build_id'] = fb.group(1)

data['title[0][value]'] = 'Portal GIDAS - Acceso a Herramientas'
data['body[0][value]'] = '... (contenido con la nueva URL) ...'
data['body[0][format]'] = 'full_html'
data['op'] = 'Guardar'
r = s.post('https://gidas.frlp.utn.edu.ar/node/40/edit', data=data)
print('OK' if 'been updated' in r.text.lower() else 'FAIL')
"
```

---

## 6. Migración a URL definitiva (futuro)

Cuando se tenga un dominio propio (ej: `portal.gidas.com.ar` o `portal.gidas.frlp.utn.edu.ar` delegado):

### Con Cloudflare Named Tunnel (recomendado)

```bash
# 1. Crear cuenta Cloudflare (gratis)
# 2. Agregar el dominio a Cloudflare
# 3. En CT 208:
cloudflared tunnel login
cloudflared tunnel create gidas-portal
cloudflared tunnel route dns gidas-portal portal.gidas.com.ar

# 4. Crear config.yml
cat > ~/.cloudflared/config.yml << EOF
tunnel: gidas-portal
credentials-file: /root/.cloudflared/gidas-portal.json
ingress:
  - hostname: portal.gidas.com.ar
    service: http://192.168.1.43
  - service: http_status:404
EOF

# 5. Instalar como servicio
cloudflared service install

# 6. La URL definitiva será: https://portal.gidas.com.ar
```

### Sin Cloudflare, solo cambiar en Drupal

```
1. Editar la página /node/40 en Drupal
2. Cambiar la URL del enlace
3. Guardar
```

---

## 7. Referencia rápida

```bash
# === ESTADO ===
systemctl status gidas-tunnel                    # Estado del servicio
journalctl -u gidas-tunnel -n 20 --no-pager      # Últimos logs

# === VER URL ACTUAL ===
curl -sk "https://gidas.frlp.utn.edu.ar/node/40" | grep -oP 'https://[a-z0-9-]+\.trycloudflare\.com'

# === REINICIAR TUNNEL ===
systemctl restart gidas-tunnel                   # Nueva URL, Drupal se actualiza solo

# === PRUEBA MANUAL ===
/opt/portal-gidas/auto-tunnel.py                 # Ejecutar y monitorear output

# === ACCESO AL CT ===
ssh root@192.168.1.14
pct enter 208
```

---

*Documento mantenible — actualizado: 2026-07-03*
