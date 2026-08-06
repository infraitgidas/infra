# Post-Deploy Configuration — GLPI ITSM

After running `docker compose up -d` and `scripts/install-glpi.sh`, the
following configurations are needed to have a fully operational ITSM.

> **Nota (2026-08-06)**: aplicado sobre GLPI **10.0.26** (imagen oficial
> `glpi/glpi:10.0`). Varios comandos originales de este doc eran de **GLPI 11**
> y no existen en 10 — ver correcciones por sección. Estado: ver checklist.

---

## 1. LDAP Authentication (FreeIPA)

> **⚠️ GLPI 10 NO tiene comando CLI para crear el directorio LDAP**
> (`glpi:ldap:add` es de GLPI 11). Se configura por **Web UI**:
> `Configuration > Authentication > LDAP`, o insertando en `glpi_authldaps`.
> La sync CLI existe: `ldap:synchronize_users` (alias `ldap:sync`).

Configuración documentada (template en `config/ldap-auth.php`):

| Parámetro | Valor |
|-----------|-------|
| Server | `ipa.gidas.local:636` (LDAPS) |
| Base DN | `cn=users,cn=accounts,dc=gidas,dc=local` |
| Bind DN | `cn=glpi-svc,cn=sysaccounts,cn=etc,dc=gidas,dc=local` |

Sync users:
```bash
docker exec glpi-app php bin/console ldap:synchronize_users --all
```

### Profile Mapping

| FreeIPA Group      | GLPI Profile |
|--------------------|--------------|
| `cn=glpi-admin`    | Super-Admin  |
| `cn=glpi-tech`     | Technician   |
| `cn=glpi-users`    | Observer     |

Configure in: Web UI `Configuration > Authentication > LDAP > [Directory] > Groups`.

### 🔴 PENDIENTE — directorio a decidir

`ipa.gidas.local` **NO resuelve en la LAN** (verificado 2026-08-06). La infra
usa AD GDC01 (192.168.1.117, `DC=GDC01,DC=local`). Decidir: ¿GLPI contra AD
GDC01 (patrón del portal) o desplegar FreeIPA primero? Bind password en
`secrets/glpi.yaml` → `PENDIENTE_bind_pass`.

---

## 2. GLPI Cron Job

GLPI requires a periodic cron for background tasks (mailing, alerts, LDAP sync,
purge logs). Add to the host's crontab:

```bash
# GLPI background tasks — every 5 minutes
*/5 * * * * docker exec glpi-app php /var/www/glpi/front/cron.php >/dev/null 2>&1

# LDAP user sync — every hour (solo si hay directorio configurado)
0 * * * * docker exec glpi-app php bin/console ldap:synchronize_users --all >/dev/null 2>&1
```

> ✅ **Aplicado 2026-08-06**: el cron de `front/cron.php` (cada 5 min) está
> instalado en el CT 212. El cron de LDAP sync se agrega cuando se configure el
> directorio (sección 1). Comando corregido: `ldap:synchronize_users` (el
> `glpi:ldap:synchronize` del borrador no existe en GLPI 10).

---

## 3. Plugin Installation (Optional)

Recommended plugins for production:

| Plugin               | Purpose                          | Install                                                       |
|----------------------|----------------------------------|---------------------------------------------------------------|
| **GLPI Inventory**   | Auto-discovery of assets         | Included in GLPI core (FusionInventory)                       |
| **Form Creator**     | Custom forms for ticket creation | Download .tar from marketplace → extract to `plugins/`        |
| **Accounts**         | Password/credential management   | Included in GLPI core                                         |

Install market plugins via CLI:

```bash
docker exec glpi-app php bin/console glpi:plugin:install <plugin-name>
docker exec glpi-app php bin/console glpi:plugin:activate <plugin-name>
```

---

## 4. Session Configuration

> **⚠️ NO APLICA en GLPI 10** (verificado 2026-08-06): las keys
> `session_length` y `login_single_session` **no existen** en `glpi_configs` ni
> en el código de 10.0.26 (son de GLPI 11). La duración de sesión se maneja por
> PHP (`session.gc_maxlifetime`) — no hay config GLPI para esto en 10.

---

## 5. Email Configuration

> **🔴 PENDIENTE — decisión**: `mail.gidas.local` **NO resuelve en la LAN**
> (verificado 2026-08-06). No setear un SMTP inexistente (GLPI intentaría
> enviar y fallaría). Cuando haya servidor de correo, usar el comando real de
> GLPI 10 (`config:set`, sin prefijo `glpi:`):

For email notifications (ticket assignments, alerts):

```bash
# Set mailer method (SMTP) — comando real de GLPI 10
docker exec glpi-app php bin/console config:set mailer_method SMTP
docker exec glpi-app php bin/console config:set smtp_host mail.gidas.local
docker exec glpi-app php bin/console config:set smtp_port 587
docker exec glpi-app php bin/console config:set smtp_username noreply@gidas.local
docker exec glpi-app php bin/console config:set smtp_password "<password>"
```

---

## 6. Security Hardening

> **Nota (2026-08-06)**: con la imagen oficial `glpi/glpi:10.0`:
> - `install/install.php` **NO se elimina** — decisión de `install-glpi.sh`
>   (la imagen maneja su ciclo: si ya hay instalación, redirige). Eliminarlo
>   dentro del contenedor no persiste recreaciones.
> - `/var/www/glpi/docs` **no existe** en la imagen oficial.
> - `config/` y `files/` viven en `/var/glpi` (volumen `glpi_data`), owner
>   `www-data` con 644 — correcto; no endurecer a 640 (rompería la app).

```bash
# Disable setup wizard — key valida en GLPI 10 (default ya es 1 tras autoinstall)
docker exec glpi-app php bin/console config:set setup_wizard_closed 1
```

---

## 7. Backup Schedule

Add weekly backup to host crontab:

```bash
# Weekly backup — Sunday 03:00 (ruta real del CT: /opt/glpi)
0 3 * * 0 /opt/glpi/scripts/backup.sh >/var/log/glpi-backup.log 2>&1
```

> ✅ **Aplicado 2026-08-06**: cron instalado en CT 212, `zstd` instalado
> (dnf), `backup.sh` probado → SUCCESS (dump 795K → `.sql.zst` 94K + volúmenes
> + MANIFEST). Backup en `/var/backups/glpi/<timestamp>/`, retención 30 días.

---

## 8. Integrations Setup

### Redmine

Configure the webhook script (see `scripts/webhook-redmine.sh`):

1. Set `REDMINE_URL` and `REDMINE_API_KEY` in `config/integrations.env`
2. Add to crontab for polling:
   ```bash
   */5 * * * * /opt/infra/itsm/scripts/webhook-redmine.sh >/dev/null 2>&1
   ```

### GitLab

Configure the webhook script (see `scripts/webhook-gitlab.sh`):

1. Set `GITLAB_URL` and `GITLAB_TOKEN` in `config/integrations.env`
2. Add to crontab for polling:
   ```bash
   */5 * * * * /opt/infra/itsm/scripts/webhook-gitlab.sh >/dev/null 2>&1
   ```

---

## Verification Checklist

- [x] GLPI accessible via HTTPS at configured hostname — `https://glpi.gidas.local` (proxy portal 200)
- [x] Admin login works (non-LDAP break-glass account) — password bcrypt aplicada por SQL
- [ ] LDAP user can log in — **pendiente** (sección 1: decidir AD GDC01 vs FreeIPA)
- [x] API App-Token returns valid session — clientes gidas-lan/gidas-docker, ticket id=1
- [x] Ticket creation, assignment, and resolution works — verificado E2E
- [x] Backup script runs without error — probado 2026-08-06 (SUCCESS, zstd)
- [x] Cron tasks for GLPI background processing active — crontab CT 212 (cron.php cada 5 min)
- [ ] Integrations can reach Redmine and GitLab — **pendiente** (tokens en `secrets/glpi.yaml` → `PENDIENTE`)

Configs core (verificadas 2026-08-06): `enable_api=1`, `enable_api_login_credentials=1`,
`url_base=https://glpi.gidas.local`, `language=es_AR`,
`timezone=America/Argentina/Buenos_Aires` (seteadas por la autoinstall de la imagen oficial
desde las env vars del compose).
