# Informe de Cambios — Vaultwarden (Gestor de Contraseñas)

**Feature branch**: `main` (directo, sin branch separada)
**Fecha**: 2026-07-02
**Estado**: IMPLEMENTADO

---

## 1. Resumen Ejecutivo

Se desplegó Vaultwarden 1.36.0 como gestor de contraseñas para los miembros de GIDAS. Compatible con Bitwarden, con autenticación LDAP contra AD GDC01, SSL, y SMTP para invitaciones.

| Concepto | Valor |
|----------|-------|
| **Versión** | Vaultwarden 1.36.0 (Bitwarden-compatible) |
| **CT** | 209 — Rocky Linux 9 — 512MB RAM — 1 vCPU |
| **IP** | 192.168.1.44/24 |
| **DNS** | vault.gidas.local |
| **Auth** | LDAP contra AD GDC01 (sAMAccountName o mail) |
| **SMTP** | Office 365 (infrait@frlp.utn.edu.ar) |
| **SSL** | Self-signed via nginx reverse proxy |

---

## 2. Infraestructura

### CT 209
| Recurso | Detalle |
|---------|---------|
| **SO** | Rocky Linux 9 (template 20240912) |
| **RAM** | 512 MB |
| **vCPU** | 1 |
| **Disco** | 8 GB |
| **IP** | 192.168.1.44/24 |
| **Gateway** | 192.168.1.1 |
| **DNS** | 192.168.1.117 (AD GDC01) |

### Servicios
| Servicio | Puerto | Rol |
|----------|--------|-----|
| nginx | 443 (SSL) | Reverse proxy a Vaultwarden |
| docker | - | Runtime para Vaultwarden |
| vaultwarden | 3012 (localhost) | Bitwarden-compatible password manager |

### Almacenamiento
- Datos: `/opt/vaultwarden/data/` (SQLite + attachments)
- Backup: copiar `db.sqlite3` del directorio data

---

## 3. Configuración

### LDAP
| Variable | Valor |
|----------|-------|
| LDAP_URL | ldap://192.168.1.117 |
| LDAP_BIND_DN | CN=infrait,OU=ServiceAccounts,DC=GDC01,DC=local |
| LDAP_SEARCH_BASE | DC=GDC01,DC=local |
| LDAP_SEARCH_FILTER | (\|(mail={{username}})(sAMAccountName={{username}})) |
| LDAP_MAIL_ATTRIBUTE | mail |
| LDAP_USER_ATTRIBUTE | sAMAccountName |

### SMTP
| Variable | Valor |
|----------|-------|
| SMTP_HOST | smtp.office365.com |
| SMTP_PORT | 587 |
| SMTP_SSL | true |
| SMTP_EXPLICIT_TLS | true |
| SMTP_USERNAME | infrait@frlp.utn.edu.ar |
| SMTP_FROM | infrait@frlp.utn.edu.ar |

### Seguridad
| Variable | Valor |
|----------|-------|
| SIGNUPS_ALLOWED | false (solo invitaciones) |
| INVITATIONS_ALLOWED | true |
| ADMIN_TOKEN | Generado en deploy, stored en secrets local |

---

## 4. Portal — Card Integrada

Se agregó Vaultwarden al `config.yaml` del portal GIDAS:

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
      - "G-Pasantes"
      - "G-Externos"
      - "G-IdentityAdmins"
```

---

## 5. Verificación

| Criterio | Resultado |
|----------|-----------|
| Login LDAP con credenciales AD | ✅ Probado con errodriguez@frlp.utn.edu.ar |
| Web Vault responde HTTPS | ✅ 200 OK |
| Admin panel accesible | ✅ Con token |
| SMTP configurado | ✅ Sin errores en logs |
| Card en portal | ✅ Visible para grupos asignados |

---

## 6. Lecciones Aprendidas

- **Vaultwarden LDAP** no auto-crea usuarios en el primer login si `SIGNUPS_ALLOWED=false`. Hay que crear el usuario via API (con KDF correcto) o via admin panel con invitación.
- **Bitwarden KDF** es complejo: requiere PBKDF2(password, email, 600000 iteraciones) para master key, y otra iteración para password hash.
- **SMTP_USERNAME** (no SMTP_USER) es el nombre correcto de la env var.
- **config.json** persistido en el volumen sobreescribe env vars de Docker. Si se cambia una env var, hay que borrar config.json.

---

## 7. Trabajo Futuro

| Tarea | Prioridad |
|-------|-----------|
| Configurar backup automático de SQLite | Media |
| Agregar CT 209 a Twingate (vault.gidas.local) | Baja |
| Probar invitación por email de extremo a extremo | Media |
