# Design: Vaultwarden

## Resumen

Deploy de Vaultwarden 1.36.0 con Docker en CT Rocky Linux 9. Autenticación LDAP contra AD GDC01. nginx reverse proxy con SSL. Integración via card en portal GIDAS.

## Arquitectura

```
┌─ CT 209 (Rocky Linux 9) ──────────────────────────┐
│                                                     │
│  nginx (reverse proxy, SSL)                        │
│  │  puerto 443 → Vaultwarden:80                    │
│  │                                                 │
│  ┌──────────┐  ┌──────────────┐                    │
│  │ Vaultward│  │   Config     │                    │
│  │ en Docker│  │   vaultwarden│                    │
│  │ :3012    │  │   .env       │                    │
│  └────┬─────┘  └──────────────┘                    │
│       │                                            │
│       ├── SQLite (data/db.sqlite3)                  │
│       ├── AD GDC01 (LDAP auth)                     │
│       └── Attachments (data/attachments/)           │
└─────────────────────────────────────────────────────┘
```

## Config LDAP

Vaultwarden usa variables de entorno para LDAP:

```bash
SIGNUPS_ALLOWED=false          # Solo login AD (admin crea usuarios)
INVITATIONS_ALLOWED=true       # Admins invitan usuarios
DOMAIN=https://vault.gidas.local
ADMIN_TOKEN=****               # Token para panel /admin

# LDAP
LDAP_URL=ldap://192.168.1.117
LDAP_START_TLS=false
LDAP_BIND_DN=CN=infrait,OU=ServiceAccounts,DC=GDC01,DC=local
LDAP_BIND_PASSWORD=****
LDAP_SEARCH_BASE=DC=GDC01,DC=local
LDAP_SEARCH_FILTER=(|(mail={{username}})(sAMAccountName={{username}}))
LDAP_MAIL_ATTRIBUTE=mail
LDAP_USER_ATTRIBUTE=sAMAccountName
```

**Importante**: El search filter acepta tanto email como sAMAccountName. El usuario puede loguearse con `email@frlp.utn.edu.ar` o con su nombre de usuario AD.

**Creación de usuarios**: Un admin debe crear el usuario via API o panel `/admin` la primera vez. La password inicial es la del AD. Luego el usuario puede loguearse con su email y esa misma password.

## Admin token

El admin token se genera en deploy y permite acceder a `https://vault.gidas.local/admin`. Desde ahí se pueden invitar usuarios y gestionar configuración.

## Datos técnicos

| Aspecto | Valor |
|---------|-------|
| **CT** | 209, Rocky Linux 9, 512MB RAM, 1 vCPU |
| **IP** | 192.168.1.44/24 |
| **DNS** | vault.gidas.local |
| **Puerto** | 443 (HTTPS), reverse proxy nginx |
| **Almacenamiento** | SQLite en /opt/vaultwarden/data |

## Portal

Agregar al config.yaml del portal:

```yaml
  - name: "Vaultwarden"
    url: "https://vault.gidas.local"
    icon: "fas fa-key"
    description: "Gestor de contraseñas"
    groups:
      - "G-Direccion"
      - "G-Coordinadores"
      - "G-Becarios"
      - "G-Graduados"
```
