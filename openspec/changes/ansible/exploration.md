## Exploration: Automatización de Infraestructura — Ansible

### Current State

La infraestructura del Grupo Gidas se gestiona hoy con **scripts Bash numerados por fase** (`00-env.sh` → `0N-verify.sh`), ejecutados manualmente vía SSH (BatchMode) desde el host de trabajo (`192.168.1.107`). Este patrón se decidió explícitamente en `openspec/changes/archive/2026-06-02-gitlab/design.md` (AD: *"Scripting pattern | 00-env.sh + scripts numerados | Ansible, Terraform | Consistente con scripts/ existente. Bash + SSH es el patrón del proyecto"*).

Características del estado actual:

- **7 stacks desplegados** vía Docker Compose en CTs/VMs: Redmine (VM), GitLab (VM Omnibus), LibreNMS (CT 210), GLPI (CT 212), Portal (CT 208), Vaultwarden, Monitoreo (CT 205). Cada uno con su set de scripts (`itsm/scripts/`, `librenms/scripts/`, etc.).
- **Cluster Proxmox** pve-gidas: pve-desa01 (.11), pve-desa02 (.12), pve-desa03 (.13), pve-desa04 (.14) + pve-ad (.31 standalone).
- **Red**: MikroTik `192.168.1.1` corriendo **RouterOS v6.49.19** (no v7). Se gestiona por SSH con comandos directos; el shell interactivo con pty no captura salida.
- **Directorios**: AD GDC01 (.117, Windows) + PCs de laboratorio unidas al dominio (.30, .50-.54). Login AD vía sssd/realm en las máquinas Linux.
- **Secretos**: SOPS + age en `secrets/*.yaml` (solo `path_regex: secrets/.*\.yaml`). Nunca texto plano.
- **Sin CI/CD, sin test runner**: infraestructura pura (Shell/YAML). `openspec/config.yaml` confirma `testing.runner.available: false`.
- **Ansible ya instalado localmente**: `ansible [core 2.16.16]` (Python 3.12) en el host de trabajo. Sin `ansible-lint` ni `molecule`.
- **Drift conocido**: `/etc/hosts` de los CTs que proxean se editan a mano — el CT 208 apuntaba `netbox.gidas.local → .45` (LibreNMS) en vez de un host real de NetBox. Un playbook de sync de hosts es una ganancia inmediata verificable.

Contexto previo que justifica la feature:

- `openspec/changes/proxmox-cluster-analysis/exploration.md`: *"Sin scripts de automatización (Ansible, Terraform)"* + propuesta de `proxmox/` para playbooks.
- `openspec/changes/cmdb/exploration.md`: NetBox como SSoT — *"Ansible, Terraform, todo el ecosistema lo soporta"*. NetBox tiene integración oficial con Ansible (collection `netbox.netbox`).
- `docs/herramientas-pendientes.md`: decisión abierta — *"¿Alcance inicial de Ansible: deploy de stacks existentes, config drift, o ambos?"*

### Affected Areas

- `ansible/` — directorio nuevo para la feature (inventario, playbooks, roles, ansible.cfg).
- `openspec/changes/ansible/` — artefactos SDD del cambio (exploration → proposal → design → tasks).
- `scripts/` — fases existentes (f1-f5): referencia/legacy, NO se migran en el alcance inicial (evitar romper el patrón probado).
- `secrets/` — los secretos SOPS actuales deben ser consumibles por Ansible (ansible-vault NO es compatible con el setup age existente; evaluar plugin SOPS o delegar).
- `docs/runbooks/` — documentar cómo ejecutar playbooks (patrón de los runbooks existentes).
- `PROJECT.md` — actualizar estado de la Feature 9 al avanzar fases.

---

### Approaches

#### Approach A: Ansible como orquestador de deploys existentes (migrar stacks)

Playbooks que repliquen el deploy de los 7 stacks actuales (Docker Compose + config) para hacerlos reproducible y declarativo.

| Aspecto | Detalle |
|---------|---------|
| **Pros** | Deploy reproducible desde cero; idempotencia; el objetivo largo de la feature |
| **Cons** | Los stacks YA están desplegados y operativos (migrar = rehacer trabajo con riesgo de regresión); los scripts Bash funcionan; costo alto para valor marginal inmediato |
| **Esfuerzo** | Alto (7 stacks + configs + secrets + verificación por stack) |

#### Approach B: Ansible como gestor de config drift + mantenimiento (primera ganancia)

Playbooks no-destructivos sobre el inventario actual: sync de `/etc/hosts`, health checks HTTP de los stacks (curl a endpoints), verificación de versión de paquetes, instalación de utilidades (zstd, docker), sync de crontabs, validación de backups.

| Aspecto | Detalle |
|---------|---------|
| **Pros** | Valor inmediato y verificable; bajo riesgo (no migra nada); testea el flujo completo (inventario, conectividad, SOPS, idempotencia) |
| **Cons** | No resuelve por sí solo el "deploy reproducible desde cero" |
| **Esfuerzo** | Bajo-Medio |

#### Approach C: Ansible como provisioning de CTs/VMs nuevos (Proxmox)

Usar Ansible para el ciclo de vida de contenedores/VMs: crear el CT en PVE (community.general.proxmox/proxmoxer vía API), instalar Docker, deploy del stack. Complementa NetBox como SSoT.

| Aspecto | Detalle |
|---------|---------|
| **Pros** | Es donde el patrón Bash más sufre (cada CT nuevo = copiar scripts + editar IPs); escalable; se integra con NetBox |
| **Cons** | Los CTs existentes no se benefician (ya hechos); requiere setup de API PVE + credenciales; más piezas móviles al inicio |
| **Esfuerzo** | Medio-Alto |

#### Approach D: Enfoque progresivo por fases — RECOMENDADO

Combinar B → A → C en fases con entregables verificables:

- **Fase 1 (Config base)**: setup del control node + inventario YAML por grupos + `ansible.cfg` + SOPS integrado. Playbooks no-destructivos: sync `/etc/hosts` (arregla el drift real del CT 208), health checks de los 7 stacks, chequeo de paquetes/utilidades, sync de crontabs. Todo idempotente y verificable en la LAN real.
- **Fase 2 (Deploy reproducible)**: un playbook de deploy completo de UN stack nuevo — NetBox (Feature 3) como piloto natural, ya que es greenfield (`cmdb/` vacío) y el SDD está listo. Probar el patrón sin tocar nada existente.
- **Fase 3 (Provisioning + scope ampliado)**: crear CTs con API Proxmox + deploy Ansible; evaluar MikroTik (RouterOS v6 — limitado, probablemente seguir con SSH directo) y Windows (OpenSSH cmd.exe — fuera del alcance inicial; AD ya lo cubre identity-dashboard).

| Aspecto | Detalle |
|---------|---------|
| **Pros** | Ganancia rápida verificable (F1) sin romper el patrón actual; F2 valida el patrón en greenfield (NetBox) sin riesgo de regresión; F3 opcional según resultado; el repo pasa de "scripts" a "scripts + playbooks" sin fricción |
| **Cons** | No hay deploy reproducible de los 7 stacks existentes al final de F1 (depende de si se elige migrar en fases posteriores); la decisión de "control node" queda abierta (host .107 vs CT dedicado) |
| **Esfuerzo** | Medio (progresivo, cada fase cierra sola) |

---

### Recommendation

**Approach D — Enfoque progresivo.** Razones:

1. **No rompe lo que funciona**: los scripts Bash por fase son el patrón probado del repo (decisión documentada en gitlab design). Migrar los 7 stacks de una (Approach A) es riesgo de regresión sin valor inmediato.
2. **El drift real se arregla primero**: `/etc/hosts` del CT 208 ya causó un bug real (netbox → .45). Fase 1 da valor tangible con playbooks no-destructivos.
3. **NetBox como piloto natural**: es greenfield, el SDD está completo y NetBox es el SSoT que Ansible consulta como fuente de verdad. Fase 2 valida el patrón "deploy reproducible" con riesgo cero sobre lo existente.
4. **Alineación con el ecosistema**: Ansible + NetBox + Proxmox es el trío estándar de IaC on-premise; la exploration de cmdb ya lo planteó.
5. **Secretos sin fricción**: mantener SOPS+age (setup existente) en lugar de introducir ansible-vault; el control node lee los `.yaml` de `secrets/` (posiblemente vía plugin SOPS o exportando vars en el playbook).

---

### Risks

1. **MikroTik RouterOS v6.49**: los módulos `community.routeros` modernos apuntan a v7 (API). En v6 hay que seguir con SSH directo (`routeros_command` con SSH funciona, pero con limitaciones — verificar en fase 3 antes de prometer automatización de MikroTik).
2. **Windows/AD fuera del alcance inicial**: las PCs usan OpenSSH con `cmd.exe` (sin PowerShell remoto garantizado) y WinRM no está configurado. La gestión de usuarios AD ya la cubre `identity-dashboard`. No incluir Windows en F1/F2.
3. **Secretos**: ansible-vault es un formato distinto al setup age existente. Mezclar ambos crea confusión y superficie de fuga. Decisión: consumir SOPS existente; NO duplicar secretos en vault.
4. **Idempotencia parcial con stacks existentes**: los scripts Bash actuales no son declarativos; un playbook que los invoque no gana idempotencia real. Por eso F1 usa módulos (lineinfile, cron, uri, package), no `shell:`.
5. **Control node**: correr playbooks desde el host de trabajo (.107) es el camino de menor fricción (Ansible 2.16 ya instalado), pero un CT dedicado (ej. en pve-ad) sería más robusto para el largo plazo. Dejar para el proposal.
6. **Sin CI/CD**: los playbooks se ejecutan manualmente como los scripts actuales; documentar en runbook (patrón existente).

### Ready for Proposal

**Yes** — la exploración está completa. Para el `sdd-propose` el orquestador debe confirmar con el equipo:

1. ¿Control node: host de trabajo `.107` (rápido) o CT dedicado (robusto)?
2. ¿Fase 2 con NetBox como piloto de "deploy reproducible" (recomendado) o se prefiere otro stack?
3. ¿Alcance inicial excluye MikroTik/Windows (recomendado) o hay algún caso que los requiera?
4. ¿La Fase 1 debe incluir sync de crontabs y `/etc/hosts` como entregables mínimos verificables (recomendado)?
