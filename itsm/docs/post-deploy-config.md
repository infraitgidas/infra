# Post-Deploy Configuration — GLPI ITSM

After running `docker compose up -d` and `scripts/install-glpi.sh`, the
following configurations are needed to have a fully operational ITSM.

---

## 1. LDAP Authentication (FreeIPA)

Configure GLPI to authenticate against FreeIPA:

```bash
# Via GLPI CLI
docker exec glpi-app php bin/console glpi:ldap:add \
    --name="FreeIPA - Gidas" \
    --host="ipa.gidas.local" \
    --port=636 \
    --basedn="cn=users,cn=accounts,dc=gidas,dc=local" \
    --rootdn="cn=glpi-svc,cn=sysaccounts,cn=etc,dc=gidas,dc=local" \
    --use-tls=1 \
    --rootdn-passwd="<service-account-password>"

# Sync users
docker exec glpi-app php bin/console glpi:ldap:synchronize --all
```

Alternatively, configure via **Web UI**: `Configuration > Authentication > LDAP`.

See `config/ldap-auth.php` for template values.

### Profile Mapping

Map FreeIPA groups to GLPI profiles:

| FreeIPA Group      | GLPI Profile |
|--------------------|--------------|
| `cn=glpi-admin`    | Super-Admin  |
| `cn=glpi-tech`     | Technician   |
| `cn=glpi-users`    | Observer     |

Configure in: Web UI `Configuration > Authentication > LDAP > [Directory] > Groups`.

---

## 2. GLPI Cron Job

GLPI requires a periodic cron for background tasks (mailing, alerts, LDAP sync,
purge logs). Add to the host's crontab:

```bash
# GLPI background tasks — every 5 minutes
*/5 * * * * docker exec glpi-app php /var/www/html/glpi/front/cron.php >/dev/null 2>&1

# LDAP user sync — every hour
0 * * * * docker exec glpi-app php bin/console glpi:ldap:synchronize --all >/dev/null 2>&1
```

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

Adjust session lifetime for production:

```bash
# Set session timeout to 8 hours (28800 seconds)
docker exec glpi-app php bin/console glpi:config:set session_length 28800

# Set max simultaneous sessions per user
docker exec glpi-app php bin/console glpi:config:set login_single_session 0
```

---

## 5. Email Configuration

For email notifications (ticket assignments, alerts):

```bash
# Set mailer method (SMTP)
docker exec glpi-app php bin/console glpi:config:set mailer_method SMTP
docker exec glpi-app php bin/console glpi:config:set smtp_host mail.gidas.local
docker exec glpi-app php bin/console glpi:config:set smtp_port 587
docker exec glpi-app php bin/console glpi:config:set smtp_username noreply@gidas.local
docker exec glpi-app php bin/console glpi:config:set smtp_password "<password>"
```

---

## 6. Security Hardening

```bash
# Remove install.php (done by install-glpi.sh)
docker exec glpi-app rm -f /var/www/html/glpi/install/install.php

# Remove documentation from webroot
docker exec glpi-app rm -rf /var/www/html/glpi/docs

# Restrict files permissions
docker exec glpi-app chmod -R 640 /var/www/html/glpi/config/*
docker exec glpi-app chmod -R 640 /var/www/html/glpi/files/_log/*

# Disable setup wizard
docker exec glpi-app php bin/console glpi:config:set setup_wizard_closed 1
```

---

## 7. Backup Schedule

Add weekly backup to host crontab:

```bash
# Weekly backup — Sunday 03:00
0 3 * * 0 /opt/infra/itsm/scripts/backup.sh >/var/log/glpi-backup.log 2>&1
```

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

- [ ] GLPI accessible via HTTPS at configured hostname
- [ ] Admin login works (non-LDAP break-glass account)
- [ ] LDAP user can log in with FreeIPA credentials
- [ ] API App-Token returns valid session
- [ ] Ticket creation, assignment, and resolution works
- [ ] Backup script runs without error
- [ ] Cron tasks for GLPI background processing active
- [ ] Integrations can reach Redmine and GitLab
