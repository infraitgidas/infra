# Design: Dashboard Gestión de Identidades — gidas-identity CLI

## Technical Approach

CLI Python (Click) containerizado en Docker sobre pve-ad (192.168.1.31). Operaciones simultáneas sobre AD (vía pywinrm + PowerShell remoto) y FreeIPA (vía SSH + ipa CLI). Notificaciones email vía smtplib. Secretos cifrados con SOPS + age, descifrados en memoria al arrancar. Comandos unificados por dominio (`user`, `group`, `hbac`) que orquestan ambos sistemas.

La CLI no es un daemon — se ejecuta bajo demanda, recibe secrets y conexiones, ejecuta la operación y termina. Sin estado persistente entre invocaciones.

## Architecture Decisions

| Decisión | Opción Elegida | Alternativa | Rationale |
|----------|---------------|-------------|-----------|
| **Lenguaje** | Python 3.12 + Click | Bash + jq, Go | pywinrm es Python; Click es maduro y testeable. La lógica es procedural, no necesita Web UI ni event loop. Bash sería frágil para manejo de errores complejo con dos sistemas remotos |
| **Container base** | python:3.12-slim | alpine, distroless | slim tiene pywinrm wheels precompilados; alpine requeriría compilar. Distroless no tiene shell ni ssh client que necesitamos para depuración inicial |
| **AD protocolo** | pywinrm (WinRM HTTP) | LDAP, PowerShell directo | WinRM ya está habilitado en DC1-GIDAS. pywinrm permite ejecutar PowerShell remoto sin abrir puertos extra. LDAP requeriría habilitar LDAPS y manejar SSL |
| **FreeIPA protocolo** | SSH + ipa CLI (paramiko) | python-freeipa (XMLRPC/JSONRPC) | ipa CLI ya está autenticado vía Kerberos en el host. No necesitamos manejar tickets krb5 en el container. SSH es simple y la API de ipa CLI es estable |
| **Secrets** | SOPS + age, YAML cifrado | HashiCorp Vault, env file | SOPS es el estándar del proyecto. Vault añade dependencia externa. Env file dejaría secrets en `docker inspect` |
| **Orquestación dual** | Python orchestrator: AD → FreeIPA secuencial | async concurrente | Operaciones simples (create, disable, password) toman < 5s cada una. Concurrencia añade complejidad de rollback parcial sin beneficio real |
| **Recipiente email** | Configurable en secrets: `admin_email` + `from` | Por usuario en AD | No todos tienen email en AD. Un único destinatario admin + opción `--notify` es suficiente para el volumen del grupo |

## Module Structure

```
identity-management/cli/
├── gidas_identity/
│   ├── __init__.py              # entry point — Click group
│   ├── cli.py                   # main CLI group: user, group, hbac
│   │
│   ├── ad/
│   │   ├── __init__.py
│   │   ├── client.py            # WinRM connection pool + health check
│   │   ├── user.py              # New-ADUser, Set-ADUser, Remove-ADUser, Enable/Disable
│   │   ├── password.py          # Reset-ADAccountPassword, Set-ADUser -ChangePasswordAtLogon
│   │   └── group.py             # Add-ADGroupMember, Remove-ADGroupMember, Get-ADGroupMember
│   │
│   ├── freeipa/
│   │   ├── __init__.py
│   │   ├── client.py            # SSH connection manager + session pool
│   │   ├── user.py              # ipa user-add, user-mod, user-del, user-disable, user-enable
│   │   ├── password.py          # ipa passwd
│   │   ├── group.py             # ipa group-add-member, group-remove-member
│   │   └── hbac.py              # ipa hbacrule-find, hbacrule-enable, hbacrule-disable
│   │
│   ├── email/
│   │   ├── __init__.py
│   │   ├── sender.py            # smtplib wrapper
│   │   └── templates.py         # Email body templates (user created, password reset)
│   │
│   ├── secrets/
│   │   └── loader.py            # SOPS decrypt + YAML parse
│   │
│   └── config.py                # Pydantic config model (secrets structure)
│
├── Dockerfile                   # Multi-stage: builder → runtime
├── docker-compose.yml           # Service definition + secrets mount
├── requirements.txt             # click, pywinrm, paramiko, pydantic
└── wrapper.sh                   # Entrypoint: decrypt → exec CLI
```

## Data Flow

### User Create
```
User (SSH pve-ad)
  │ gidas-identity user create --name "Juan Pérez" --username jperez --role becario --proyecto Telepark --notify
  ▼
gidas-identity CLI
  │
  ├─ 1. Load secrets (SOPS decrypt → memory dict)
  ├─ 2. Validate: username format, role→OU mapping, required fields
  ├─ 3. Pre-check: jperez exists in AD? → if yes, abort
  │
  ├─ 4. AD: Connect WinRM → New-ADUser (OU=Becarios)
  │     ├─ Set-ADUser (title, department, description)
  │     ├─ Add-ADGroupMember G-Becarios
  │     └─ Add-ADGroupMember PROY-Telepark
  │
  ├─ 5. FreeIPA: SSH → ipa user-add jperez --first Juan --last Pérez
  │     ├─ ipa group-add-member G-Becarios --users jperez
  │     └─ ipa group-add-member PROY-Telepark --users jperez
  │
  ├─ 6. Email (if --notify): smtplib → admin email
  │     └─ On failure: log warning, exit 0 (non-blocking)
  │
  └─ 7. Output: JSON summary to stdout
         { "status": "created", "username": "jperez", "ad": "ok", "freeipa": "ok" }
```

### Password Reset
```
User (SSH pve-ad)
  │ gidas-identity user password --username jperez --reset --force-change
  ▼
gidas-identity CLI
  │
  ├─ 1. Load secrets
  ├─ 2. Validate jperez exists in AD → abort if not
  ├─ 3. Generate random password (secrets.token_urlsafe(16))
  │
  ├─ 4. AD: Reset-ADAccountPassword jperez → Set-ADUser -ChangePasswordAtLogon $true
  ├─ 5. FreeIPA: SSH → ipa passwd jperez (via stdin, log excluded)
  │
  ├─ 6. Output password to stdout (only once, not logged)
  └─ 7. Email sent with new password (if --notify)
```

### Group Add Member
```
User (SSH pve-ad)
  │ gidas-identity group add-member --group PROY-Telepark --user jperez
  ▼
gidas-identity CLI
  │
  ├─ 1. Load secrets
  ├─ 2. Validate group AND user exist in AD
  ├─ 3. AD: Add-ADGroupMember PROY-Telepark -Members jperez
  └─ 4. FreeIPA: ipa group-add-member PROY-Telepark --users jperez
```

### HBAC List
```
User (SSH pve-ad)
  │ gidas-identity hbac list --user jperez
  ▼
gidas-identity CLI
  │
  ├─ 1. Load secrets
  └─ 2. FreeIPA (SSH): ipa hbacrule-find --users=jperez
       └─ Parse output → formatted table
       └─ Show: rule name, status (enabled/disabled), hosts
```

## AD Integration

### WinRM Connection

```python
# gidas_identity/ad/client.py
import winrm

class ADClient:
    def __init__(self, endpoint: str, auth: dict):
        # endpoint: http://192.168.1.117:5985/wsman
        self.session = winrm.Session(
            endpoint,
            auth=(auth["username"], auth["password"]),
            transport="ntlm",  # AD domain auth
            server_cert_validation="ignore",  # HTTP, no cert
        )

    def run_ps(self, script: str) -> dict:
        """Execute PowerShell script, return parsed result."""
        for attempt in range(3):
            try:
                r = self.session.run_ps(script)
                if r.status_code == 0:
                    return {"ok": True, "output": r.std_out.decode()}
                return {"ok": False, "error": r.std_err.decode()}
            except (requests.Timeout, ConnectionError) as e:
                if attempt == 2:
                    raise
                continue
```

### PowerShell Templates

**User Create:**
```powershell
$sec = ConvertTo-SecureString "{password}" -AsPlainText -Force
New-ADUser -Name "{name}" `
    -GivenName "{first}" `
    -Surname "{last}" `
    -SamAccountName "{username}" `
    -UserPrincipalName "{username}@GDC01.local" `
    -Path "{ou_path}" `
    -AccountPassword $sec `
    -Enabled $true `
    -ChangePasswordAtLogon ${force_change} `
    -Title "{role}" `
    -Department "{proyecto}" `
    -Description "Creado via gidas-identity CLI"
```

**User Disable:**
```powershell
Disable-ADAccount -Identity "{username}"
```

**Password Reset:**
```powershell
$sec = ConvertTo-SecureString "{password}" -AsPlainText -Force
Set-ADAccountPassword -Identity "{username}" -NewPassword $sec -Reset
Set-ADUser -Identity "{username}" -ChangePasswordAtLogon $true
```

**Group Operations:**
```powershell
Add-ADGroupMember -Identity "{group}" -Members "{username}"
Remove-ADGroupMember -Identity "{group}" -Members "{username}" -Confirm:$false
Get-ADGroupMember -Identity "{group}" | Select-Object -ExpandProperty SamAccountName
```

### OU Mapping (Role → AD Path)

| Role | OU Path | Default Group |
|------|---------|---------------|
| `director` | `OU=Direccion,DC=GDC01,DC=local` | G-Direccion |
| `vicedirector` | `OU=Direccion,DC=GDC01,DC=local` | G-Direccion |
| `coordinador` | `OU=Coordinadores,OU=Direccion,DC=GDC01,DC=local` | G-Coordinadores |
| `becario` | `OU=Becarios,DC=GDC01,DC=local` | G-Becarios |

## FreeIPA Integration

### SSH Connection

```python
# gidas_identity/freeipa/client.py
import paramiko

class FreeIPAClient:
    def __init__(self, host: str, ssh_key_path: str, user: str):
        self.client = paramiko.SSHClient()
        self.client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        self.client.connect(
            hostname=host,
            username=user,
            key_filename=ssh_key_path,
        )

    def run(self, command: str) -> dict:
        """Run ipa CLI command, return parsed output."""
        stdin, stdout, stderr = self.client.exec_command(
            f"echo '{self._password}' | kinit admin && {command}"
        )
        exit_code = stdout.channel.recv_exit_status()
        return {
            "ok": exit_code == 0,
            "output": stdout.read().decode(),
            "error": stderr.read().decode(),
        }
```

**Note on Kerberos**: The FreeIPA admin credentials are used to obtain a Kerberos ticket at the start of each operation (`kinit`), not persisted between invocations. The admin password is decrypted from SOPS in memory and passed only via stdin to `kinit`.

### ipa CLI Templates

**User Create:**
```bash
ipa user-add jperez \
    --first="Juan" \
    --last="Pérez" \
    --title="Becario" \
    --orgunit="PROY-Telepark" \
    --shell=/bin/bash \
    --homedir=/home/jperez
```

**User Disable:**
```bash
ipa user-disable jperez
```

**User Enable:**
```bash
ipa user-enable jperez
```

**Password Reset:**
```bash
echo "newpassword" | ipa passwd jperez
```

**Group Operations:**
```bash
ipa group-add-member G-Becarios --users=jperez
ipa group-remove-member G-Becarios --users=jperez
```

**HBAC List:**
```bash
ipa hbacrule-find --users=jperez --all
```

**HBAC Toggle:**
```bash
ipa hbacrule-enable allow-telepark-ssh
ipa hbacrule-disable allow-telepark-ssh
```

## Email Integration

### smtplib Usage

```python
# gidas_identity/email/sender.py
import smtplib
from email.mime.text import MIMEText

class EmailSender:
    def __init__(self, config: dict):
        self.server = config["smtp_host"]
        self.port = config["smtp_port"]
        self.from_addr = config["from_addr"]
        self.to_addr = config["to_addr"]
        self.use_tls = config.get("smtp_tls", True)
        if self.use_tls:
            self.port = config.get("smtp_tls_port", 587)

    def send(self, subject: str, body: str) -> bool:
        msg = MIMEText(body, "plain", "utf-8")
        msg["Subject"] = subject
        msg["From"] = self.from_addr
        msg["To"] = self.to_addr
        try:
            with smtplib.SMTP(self.server, self.port, timeout=10) as s:
                if self.use_tls:
                    s.starttls()
                s.send_message(msg)
            return True
        except Exception as e:
            logging.warning(f"Email failed: {e}")
            return False  # Non-blocking
```

### Email Templates

**User Created:**
```
Subject: [Gidas Identity] Alta de usuario — jperez

Se ha creado el usuario jperez (Juan Pérez) en AD y FreeIPA.

Rol: Becario
Proyecto: PROY-Telepark
Usuario: jperez
Password: {password}
Dominio: GDC01.local

El usuario debe cambiar la contraseña en el primer login.

Acceso Linux: ssh jperez@<host-asignado>
Acceso Windows: RDP a VM del proyecto
```

**Password Reset:**
```
Subject: [Gidas Identity] Password reseteado — jperez

Se ha reseteado la contraseña del usuario jperez (Juan Pérez).

Nuevo password: {password}
Debe cambiarla en el próximo inicio de sesión.

Acceso Linux: ssh jperez@<host-asignado>
```

## Secrets Management

### Secrets Structure

```yaml
# secrets/identity.yaml (SOPS-encrypted)
identity:
  ad:
    endpoint: "http://192.168.1.117:5985/wsman"
    username: "GDC01\\Administrator"
    password: "..."  # encrypted
  freeipa:
    host: "ipa-gidas.gidas.internal"
    ssh_user: "root"
    ssh_key_path: "/secrets/ipa-admin-key"  # bind-mounted
    admin_password: "..."  # for kinit
  email:
    smtp_host: "mail.gidas.local"
    smtp_port: 587
    smtp_tls: true
    from_addr: "admin-identity@gidas.local"
    to_addr: "admin-identity@gidas.local"
```

### SOPS Loading

```python
# gidas_identity/secrets/loader.py
import subprocess, yaml

def load_secrets(path: str = "/secrets/identity.yaml") -> dict:
    """Decrypt SOPS-encrypted YAML, return dict."""
    result = subprocess.run(
        ["sops", "-d", path],
        capture_output=True, text=True, check=True
    )
    return yaml.safe_load(result.stdout)["identity"]
```

### Credential Lifetime

- Secrets descifrados en memoria al arrancar el entrypoint
- NO persisten en variables de entorno
- NO persisten en archivos temporales
- El proceso CLI termina → memoria liberada
- SSH key montada como bind mount readonly (`ro`)
- Logging filtra explícitamente campos `password`

## Dockerfile

```dockerfile
# Stage 1: Builder
FROM python:3.12-slim AS builder

WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

# Stage 2: Runtime
FROM python:3.12-slim

RUN groupadd -r appuser && useradd -r -g appuser -d /app -s /sbin/nologin appuser \
    && mkdir -p /app && chown appuser:appuser /app

# Copy Python dependencies from builder
COPY --from=builder /root/.local /home/appuser/.local

# Install SOPS
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    && curl -LO https://github.com/getsops/sops/releases/download/v3.10.2/sops-v3.10.2.linux.amd64 \
    && mv sops-v3.10.2.linux.amd64 /usr/local/bin/sops \
    && chmod +x /usr/local/bin/sops \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Copy application
COPY gidas_identity/ /app/gidas_identity/
COPY requirements.txt /app/
COPY wrapper.sh /app/

WORKDIR /app
USER appuser

ENV PATH="/home/appuser/.local/bin:${PATH}" \
    PYTHONPATH="/app:${PYTHONPATH}" \
    PYTHONUNBUFFERED=1

ENTRYPOINT ["/app/wrapper.sh"]
```

### requirements.txt

```
click>=8.1,<9.0
pywinrm>=0.5,<1.0
paramiko>=3.5,<4.0
pydantic>=2.0,<3.0
PyYAML>=6.0,<7.0
```

## docker-compose.yml

```yaml
# identity-management/cli/docker-compose.yml
services:
  gidas-identity:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: gidas-identity
    image: gidas-identity:latest
    volumes:
      # SSH key for FreeIPA (readonly)
      - ~/.ssh/ipa-admin-key:/secrets/ipa-admin-key:ro
      # SOPS-encrypted secrets
      - ../../secrets/identity.yaml:/secrets/identity.yaml:ro
      # Age key for SOPS decryption
      - ~/.config/sops/age/keys.txt:/home/appuser/.config/sops/age/keys.txt:ro
    environment:
      - SOPS_AGE_KEY_FILE=/home/appuser/.config/sops/age/keys.txt
      - GIDAS_SECRETS_PATH=/secrets/identity.yaml
      - TZ=America/Argentina/Buenos_Aires
    # Interactive terminal for password output
    stdin_open: true
    tty: true
    # Non-privileged — no capabilities needed
    cap_drop:
      - ALL
```

### Wrapper Script Entrypoint

```bash
#!/bin/bash
# wrapper.sh — entrypoint for gidas-identity Docker container
set -e

# Verify SOPS decryption works before accepting commands
if ! sops -d "$GIDAS_SECRETS_PATH" > /dev/null 2>&1; then
    echo "ERROR: Cannot decrypt secrets. Check age key and secrets file." >&2
    exit 1
fi

# Execute CLI with all passed arguments
exec python -m gidas_identity "$@"
```

## Error Handling Strategy

### Retry Logic

| Capa | Operación | Retries | Backoff | Timeout |
|------|-----------|---------|---------|---------|
| WinRM | All PS commands | 3 | 2s, 5s, 10s | 30s |
| SSH (paramiko) | ipa commands | 2 | 3s, 6s | 15s |
| Email (smtplib) | send | 1 (no retry) | — | 10s |

### Rollback Strategy

| Operation | Step fails | Rollback Action |
|-----------|-----------|-----------------|
| `user create` | AD succeeds, FreeIPA fails | Remove user from AD via `Remove-ADUser` |
| `user create` | Pre-check succeeds, AD fails | No changes made — safe to retry |
| `group add-member` | AD succeeds, FreeIPA fails | Remove from AD via `Remove-ADGroupMember` |
| `user password` | AD succeeds, FreeIPA fails | Reset AD password back to random; log error; abort |
| `hbac toggle` (only FreeIPA) | Operation fails | No rollback needed — no cross-system change |

### Logging

```python
import logging

logging.basicConfig(
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    level=logging.INFO,
)

# Sanitize sensitive fields
class SanitizingFilter(logging.Filter):
    def filter(self, record):
        msg = record.getMessage()
        # Replace password values in log messages
        if "password" in msg.lower():
            record.msg = re.sub(r'(password["\s:=]+\w+["\s]*)', 'password=***', record.msg, flags=re.IGNORECASE)
        return True
```

### Log Schema (stdout)

Each operation logs a structured JSON line at the end:

```json
{"event": "user.create", "username": "jperez", "ad": "ok", "freeipa": "ok", "email": "sent", "duration_s": 4.2}
{"event": "user.create", "username": "jperez", "ad": "ok", "freeipa": "failed", "rolled_back": true, "error": "SSH timeout"}
```

## Security Model

### Who Can Run the CLI

- El container corre en **pve-ad** y solo usuarios con SSH + sudo en pve-ad pueden ejecutarlo
- El wrapper script `gidas-identity` (en `$PATH` del host) hace `ssh pve-ad "docker exec ..."`
- Credenciales AD y FreeIPA están cifradas con SOPS — solo quien tenga la age key puede descifrarlas
- La age key del admin está en `~/.config/sops/age/keys.txt` de pve-ad

### Credential Protection

| Recurso | Protección |
|---------|-----------|
| AD password | Cifrado SOPS, descifrado en memoria, nunca en env/disk |
| FreeIPA admin password | Cifrado SOPS, pasado por stdin a `kinit`, no loggeado |
| SSH key | Bind mount readonly (`:ro`), container no-root |
| Age key | Bind mount readonly, solo lectura |
| API output | Passwords mostrados 1 vez en stdout, no en logs |

### Container Security

- **User**: `appuser` (no-root)
- **Capabilities**: `--cap-drop ALL` (sin privileged)
- **Network**: Solo acceso saliente a .117 (AD), .118 (FreeIPA), SMTP relay
- **No shell**: Python es el entrypoint, no hay bash interactivo en runtime normal
- **Read-only root filesystem**: `--read-only` (opcional, verificar compatibilidad con SOPS temp)

## HBAC Integration

FreeIPA HBAC (Host-Based Access Control) rules control qué usuarios pueden acceder a qué hosts Linux.

### How HBAC Interacts with the CLI

| Group | HBAC Rule | CLI Binding |
|-------|-----------|-------------|
| G-Direccion | `allow-direccion-all` — ALL hosts | `hbac list --user` muestra esta regla como "enabled" |
| G-Coordinadores | `allow-coordinadores-all` — ALL hosts | Ídem |
| G-Becarios | `allow-becarios-<proyecto>` — hosts del proyecto | `group add-member --group PROY-Telepark --user jperez` + `hbac toggle --rule allow-becarios-telepark --enable` (manual) |
| SRV-InfraITAdmin | `allow-srv-infraitadmin` — servidores INFRAiT | Asignación manual vía `hbac toggle` |

### HBAC Commands in the CLI

```bash
# List all HBAC rules applicable to a user
gidas-identity hbac list --user jperez

# Output example:
# Rule                    Status    Hosts
# allow-becarios-all      Enabled   sg-rojo.gidas.internal
# allow-all-coordinadores Disabled  (all hosts)

# Enable/disable a specific HBAC rule
gidas-identity hbac toggle --rule allow-becarios-telepark --enable
gidas-identity hbac toggle --rule allow-becarios-telepark --disable
```

**Design note**: HBAC rule creation is OUT OF SCOPE for the CLI (rules are pre-defined). The CLI only lists existing rules and toggles them on/off. Creating new HBAC rules is a one-time FreeIPA configuration task.

## File Changes

| File | Action | Description |
|------|--------|-------------|
| `identity-management/cli/Dockerfile` | Create | Multi-stage Docker build |
| `identity-management/cli/docker-compose.yml` | Create | Service definition with bind mounts |
| `identity-management/cli/requirements.txt` | Create | Python dependencies |
| `identity-management/cli/wrapper.sh` | Create | Entrypoint: decrypt secrets → exec CLI |
| `identity-management/cli/gidas_identity/__init__.py` | Create | Package init + Click group definition |
| `identity-management/cli/gidas_identity/cli.py` | Create | Main CLI: `user`, `group`, `hbac` commands |
| `identity-management/cli/gidas_identity/config.py` | Create | Pydantic config/secrets model |
| `identity-management/cli/gidas_identity/ad/__init__.py` | Create | AD package |
| `identity-management/cli/gidas_identity/ad/client.py` | Create | WinRM session manager |
| `identity-management/cli/gidas_identity/ad/user.py` | Create | AD user CRUD operations |
| `identity-management/cli/gidas_identity/ad/password.py` | Create | AD password reset |
| `identity-management/cli/gidas_identity/ad/group.py` | Create | AD group membership |
| `identity-management/cli/gidas_identity/freeipa/__init__.py` | Create | FreeIPA package |
| `identity-management/cli/gidas_identity/freeipa/client.py` | Create | SSH session manager |
| `identity-management/cli/gidas_identity/freeipa/user.py` | Create | FreeIPA user CRUD |
| `identity-management/cli/gidas_identity/freeipa/password.py` | Create | FreeIPA password reset |
| `identity-management/cli/gidas_identity/freeipa/group.py` | Create | FreeIPA group membership |
| `identity-management/cli/gidas_identity/freeipa/hbac.py` | Create | FreeIPA HBAC list/toggle |
| `identity-management/cli/gidas_identity/email/__init__.py` | Create | Email package |
| `identity-management/cli/gidas_identity/email/sender.py` | Create | smtplib wrapper |
| `identity-management/cli/gidas_identity/email/templates.py` | Create | Email templates |
| `identity-management/cli/gidas_identity/secrets/__init__.py` | Create | Secrets package |
| `identity-management/cli/gidas_identity/secrets/loader.py` | Create | SOPS decrypt + YAML load |
| `secrets/identity.yaml` | Create | Credentials AD + FreeIPA + email (SOPS) |
| `scripts/gidas-identity` | Create | Host wrapper: `ssh pve-ad "docker exec ..."` |

## Testing Strategy

| Layer | What to Test | Approach |
|-------|-------------|----------|
| Unit | SOPS loader, OU mapping, email templates, password generation | Manual inspection; no test runner available |
| Integration | WinRM connection, PowerShell command templates | Dry-run on staging DC; validate PS syntax with `-WhatIf` |
| Integration | SSH + ipa CLI commands | Dry-run on IPA staging; validate output parsing |
| Integration | Email sending | Point to local SMTP capture (e.g. MailHog) |
| E2E | Full `user create` pipeline on staging | Create test user → verify in AD + FreeIPA → delete |
| E2E | Password reset | Reset → verify force-change flag in both systems |
| E2E | Rollback | Simulate FreeIPA failure → verify AD rollback executed |
| Security | Container no-root, secrets not in env | `docker inspect` + `docker exec` verify |

Sin test runner disponible (infraestructura pura). Validación manual sobre staging siguiendo los scripts de verify del proyecto.

## Migration / Rollout

1. **Create secrets**: `sops secrets/identity.yaml` con credenciales AD + FreeIPA + email
2. **Build image**: `docker compose build` en pve-ad
3. **Deploy**: `docker compose up -d` — verificar container healthy
4. **Smoke test**: `docker compose run --rm gidas-identity --help`
5. **Pre-check**: `docker compose run --rm gidas-identity user list` (debe listar usuarios AD)
6. **Create test user**: `gidas-identity user create --username testcli --name "Test CLI" --role becario --notify`
7. **Verify dual creation**: Check AD (Get-ADUser) + FreeIPA (ipa user-show)
8. **Test rollback**: `gidas-identity user delete --username testcli` + confirm
9. **Wrapper script**: Crear `scripts/gidas-identity` en el host para acceso directo
10. **Go live**: Comunicar al equipo que `gidas-identity` está disponible

## Open Questions

- [ ] ¿WinRM requiere HTTP o HTTPS? Asumo HTTP por ahora (puerto 5985), pero verificar config de DC1-GIDAS
- [ ] ¿La age key de SOPS está en pve-ad o solo local? Necesario verificar antes del deploy

## Rollback Plan

```bash
# Deshacer operación individual (ej: user create erróneo)
gidas-identity user delete --username jperez

# Rollback completo: eliminar container + imágenes + secrets
docker compose -f identity-management/cli/docker-compose.yml down --rmi all -v
rm -rf identity-management/cli/
git checkout -- secrets/identity.yaml  # restaurar vacío cifrado
rm scripts/gidas-identity
```
