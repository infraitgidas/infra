# Proposal: Dashboard Gestión de Identidades

## Intent

Eliminar la gestión fragmentada de identidades entre AD (RSAT/ADUC) y FreeIPA (ipa CLI/Web UI). Proveer un CLI unificado para operaciones diarias (altas, bajas, contraseñas, permisos) con notificaciones por email, ejecutable desde pve-ad sin depender de estaciones Windows con RSAT.

## Scope

### In Scope
- Python Click CLI containerizado (Docker) en pve-ad
- CRUD usuarios: crear, modificar, deshabilitar en AD + FreeIPA simultáneamente
- Password management: reset, force-change en próximo login
- Group membership: agregar/remover de grupos AD y FreeIPA
- HBAC rules: listar, habilitar/deshabilitar reglas en FreeIPA
- Email notifications vía smtplib para cada operación
- Secretos cifrados con SOPS + age

### Out of Scope
- Web UI / Dashboard gráfico
- Self-service password reset (portal para usuarios finales)
- Sincronización bidireccional AD↔FreeIPA (operan via trust, no sync)
- Provisioning automático de cuentas (ON/OFF boarding)
- Integración con servicios externos (Redmine, GitLab, VPN)
- Monitoreo de salud del sistema de identidad

## Capabilities

> Contrato proposal→specs. No existen specs previas de gestión de identidades en `openspec/specs/`.

### New Capabilities
- `identity-cli`: CLI unificado para operaciones CRUD sobre AD + FreeIPA, password management, grupos, HBAC, con notificaciones email.

### Modified Capabilities
None — capability nueva, no modifica specs existentes.

## Approach

Python Click CLI dentro de un container Docker que se ejecuta en pve-ad. Se conecta a AD vía pywinrm (ya instalado en el host) y a FreeIPA vía SSH + ipa CLI. Email vía smtplib (stdlib, sin MTA). Secretos descifrados con SOPS + age desde `secrets/`.

**Por qué Python Click**: pywinrm ya existe en pve-ad, Click es maduro y testeable, la lógica es procedural (no necesita Web UI ni event loop).

### Arquitectura

```
┌────────────────────────────────────────────────────────────┐
│                      pve-ad (192.168.1.31)                  │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  gidas-identity (Docker container)                   │  │
│  │  ┌─────────────┐  ┌────────────┐  ┌──────────────┐  │  │
│  │  │ AD Module   │  │ FreeIPA    │  │ Email Module │  │  │
│  │  │ (pywinrm)   │  │ Module     │  │ (smtplib)    │  │  │
│  │  │ PowerShell  │  │ SSH+ipa CLI│  │              │  │  │
│  │  └──────┬──────┘  └─────┬──────┘  └──────┬───────┘  │  │
│  └─────────┼───────────────┼─────────────────┼──────────┘  │
└────────────┼───────────────┼─────────────────┼──────────────┘
             │ WinRM         │ SSH              │ SMTP
             ▼               ▼                  ▼
   ┌────────────────┐ ┌──────────────┐  ┌──────────────┐
   │ AD DC1-GIDAS   │ │ FreeIPA      │  │ SMTP Relay   │
   │ 192.168.1.117  │ │ ipa-gidas    │  │ (configurable)│
   │ WinSrv 2022    │ │ 192.168.1.118│  │              │
   └────────────────┘ └──────────────┘  └──────────────┘
```

### Comandos

```bash
gidas-identity user create --name "Juan Pérez" --username jperez \
    --role becario --proyecto Telepark --notify

gidas-identity user modify --username jperez --disable

gidas-identity user list [--ou Direccion|Becarios|Coordinadores]

gidas-identity user password --username jperez --reset --force-change

gidas-identity group add-member --group PROY-Telepark --user jperez

gidas-identity group remove-member --group PROY-Telepark --user jperez

gidas-identity hbac list --user jperez

gidas-identity hbac toggle --rule allow-telepark-ssh --enable
```

### Integraciones

| Sistema | Protocolo | Autenticación | Librería |
|---------|-----------|---------------|----------|
| AD DC1-GIDAS (.117) | WinRM HTTP/HTTPS | credenciales SOPS | pywinrm |
| FreeIPA ipa-gidas (.118) | SSH | clave privada + krb5 | paramiko |
| Email | SMTP | configurable | smtplib (stdlib) |
| Secrets | SOPS + age + YAML | age key local | sops CLI |

### Seguridad

- Container corre como `appuser` no-root
- Credenciales descifradas en memoria al arrancar, no persisten en env
- SSH key para FreeIPA montada como bind mount readonly
- Logs sensibles (passwords) excluídos explícitamente
- SOPS cifra secrets/identity.yaml con age key del admin

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `identity-management/cli/` | New | Código fuente Python Dockerizado |
| `identity-management/cli/Dockerfile` | New | Multi-stage Docker build |
| `identity-management/cli/docker-compose.yml` | New | Compose con secrets mount |
| `secrets/identity.yaml` | New | Credenciales AD + FreeIPA + email (SOPS) |
| `scripts/` | New | Script `gidas-identity` wrapper (bash → docker) |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| WinRM timeout/inestable | Medium | Retry logic (3 intentos) + health check pre-ejecución |
| Cambio de API FreeIPA IPA CLI | Low | Pin versión FreeIPA, tests de integración |
| Email delivery fail (SMTP caído) | Medium | Log + cola local, reintento configurable |
| Error humano (deshabilitar admin) | Low | Confirmación forzada en operaciones destructivas |
| Container sin acceso a secrets | Low | Health check en entrypoint que verifica descifrado SOPS |

## Rollback Plan

```bash
# Deshacer operación individual (ej: user create)
gidas-identity user delete --username jperez

# Desinstalar completamente
docker compose -f identity-management/cli/docker-compose.yml down -v
rm -rf identity-management/cli/
git checkout -- secrets/identity.yaml  # restaurar vacío cifrado
```

## Dependencies

- pve-ad con Docker Engine y pywinrm instalado
- SOPS + age key operativa (verificar con `sops -d secrets/proxmox.yaml`)
- WinRM habilitado en DC1-GIDAS (192.168.1.117)
- SSH key del admin con acceso a ipa-gidas (192.168.1.118)
- SMTP relay reachable desde pve-ad

## Effort Estimate

| Phase | Descripción | Estimado | Líneas |
|-------|-------------|----------|--------|
| 1 | Scaffold: Docker + Click entrypoint + secrets | 2h | ~150 |
| 2 | AD module: CRUD + password via pywinrm | 4h | ~250 |
| 3 | FreeIPA module: CRUD + group + HBAC via SSH | 4h | ~250 |
| 4 | Email notifications + templates | 2h | ~100 |
| 5 | Testing + docs + wrapper script | 2h | ~100 |
| **Total** | | **14h** | **~850** |

## Success Criteria

- [ ] `gidas-identity user create --username test --notify` crea user en AD y FreeIPA, envía email
- [ ] `gidas-identity user modify --username test --disable` deshabilita en ambos sistemas
- [ ] `gidas-identity user password --username test --reset --force-change` resetea password
- [ ] `gidas-identity group add-member` refleja en AD y FreeIPA
- [ ] `gidas-identity hbac list --user test` muestra reglas aplicables
- [ ] Container corre como no-root, secrets no visibles en `docker inspect`
- [ ] Rollback probado: `user delete` + `docker compose down -v` no deja residuos
