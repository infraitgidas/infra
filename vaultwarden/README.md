# Vaultwarden — Gestor de Contraseñas GIDAS

## Acceso

| Recurso | URL |
|---------|-----|
| **Web Vault** | `https://vault.gidas.local` |
| **Admin Panel** | `https://vault.gidas.local/admin` |
| **Login** | Email completo (ej: `errodriguez@frlp.utn.edu.ar`) |
| **Master Password** | La primera vez se registra, luego se autentica via LDAP |

## Infraestructura

| Recurso | Detalle |
|---------|---------|
| **CT** | 209 — Rocky Linux 9 — 512MB RAM — 1 vCPU |
| **IP** | 192.168.1.44/24 |
| **DNS** | vault.gidas.local (MikroTik) |
| **Servicio** | Docker container (vaultwarden/server:latest-alpine) |
| **Proxy** | nginx reverse proxy con SSL self-signed |
| **DB** | SQLite en `/opt/vaultwarden/data/db.sqlite3` |
| **Logs** | `docker logs vaultwarden` |

## Deploy

```bash
# 1. Editar .env con las variables reales
cp .env.example .env
nano .env

# 2. Iniciar
docker compose up -d

# 3. Verificar
curl -sk https://127.0.0.1/ -H 'Host: vault.gidas.local'
```

## Administración

### Panel Admin
Andá a `https://vault.gidas.local/admin` e ingresá el ADMIN_TOKEN.

### Crear un usuario (via API)
```bash
python3 << 'PYEOF'
import hashlib, base64, json, urllib.request

EMAIL = "usuario@frlp.utn.edu.ar"
PASSWORD = "PasswordDelUsuario123"
ITERATIONS = 600000

master_key = hashlib.pbkdf2_hmac("sha256", PASSWORD.encode(), EMAIL.encode(), ITERATIONS, dklen=32)
password_hash = hashlib.pbkdf2_hmac("sha256", master_key, PASSWORD.encode(), 1, dklen=32)

# Habilitar SIGNUPS_ALLOWED=true temporalmente antes de crear
data = {
    "email": EMAIL,
    "masterPasswordHash": base64.b64encode(password_hash).decode(),
    "key": base64.b64encode(master_key).decode(),
    "kdf": 0,
    "kdfIterations": ITERATIONS,
}

req = urllib.request.Request(
    "https://127.0.0.1/identity/accounts/register",
    data=json.dumps(data).encode(),
    headers={"Content-Type": "application/json", "Host": "vault.gidas.local"},
    method="POST",
)
ctx = ssl._create_unverified_context()
resp = urllib.request.urlopen(req, context=ctx)
print(f"Usuario creado: {resp.status}")
PYEOF
```

### Logs
```bash
docker logs vaultwarden -f
```

### Backup
```bash
# La DB es SQLite, backup simple:
cp /opt/vaultwarden/data/db.sqlite3 /backup/vaultwarden-$(date +%Y%m%d).sqlite3
```

## Configuración Actual (producción)

Ejecutado en CT 209:

```bash
docker run -d --name vaultwarden \
  --restart unless-stopped \
  -p 127.0.0.1:3012:80 \
  -v /opt/vaultwarden/data:/data \
  -e SIGNUPS_ALLOWED=false \
  -e INVITATIONS_ALLOWED=true \
  -e DOMAIN=https://vault.gidas.local \
  -e ADMIN_TOKEN="<admin-token>" \
  -e LDAP_URL=ldap://192.168.1.117 \
  -e LDAP_START_TLS=false \
  -e LDAP_BIND_DN="CN=infrait,OU=ServiceAccounts,DC=GDC01,DC=local" \
  -e LDAP_BIND_PASSWORD="<password>" \
  -e LDAP_SEARCH_BASE="DC=GDC01,DC=local" \
  -e 'LDAP_SEARCH_FILTER=(|(mail={{username}})(sAMAccountName={{username}}))' \
  -e LDAP_MAIL_ATTRIBUTE=mail \
  -e LDAP_USER_ATTRIBUTE=sAMAccountName \
  vaultwarden/server:latest-alpine
```
