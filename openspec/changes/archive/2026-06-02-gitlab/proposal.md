# Propuesta: GitLab CE — VCS On-Premise

## Intent

El grupo Gidas no tiene VCS on-premise para repos internos o datos sensibles. Sin GitLab no hay trazabilidad de código privado, ni CI/CD posible. Implementar GitLab CE como plataforma de control de versiones, independiente de cualquier otro sistema.

## Scope

### In Scope
- VM Debian/Ubuntu con GitLab CE (Omnibus) en pve-desa01
- HTTPS (Let's Encrypt) + backup diario (cron) + snapshot PVE semanal
- Script de instalación automatizado (`gitlab/install/`)
- Migración selectiva de repos (GitHub mirror)

### Out of Scope
- GitLab Runner, LDAP/SSO, CI/CD, Container Registry, HA multi-nodo
- Migración masiva automática

## Capabilities

### New
- `vcs/gitlab`: GitLab CE — repos, usuarios, web UI, API, HTTPS, backups

### Modified
None

## Approach

Omnibus package en VM dedicada en pve-desa01. VM: 4vCPU, 8GB RAM, 80GB SSD. IP 192.168.1.0/24. Puertos: 80/443 web, 2222 host→22 VM (SSH Git). PostgreSQL + Redis bundled. Let's Encrypt vía Omnibus. Backups: `gitlab-backup` diario + snapshot PVE semanal.

**Redmine**: Independiente. Sin dependencia ni integración requerida.

## Árbol propuesto

```
gitlab/
├── install/        # Scripts: provisioning VM + Omnibus
├── backup/         # Scripts backup/restore
└── docs/           # Runbooks operativos
```

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `gitlab/` | New | Scripts + config de GitLab |
| `openspec/specs/vcs/gitlab/` | New | Spec VCS on-premise |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Recursos insuficientes en pve-desa01 | Low | 6C/12T + 15GB RAM; 4vCPU/8GB factible |
| Let's Encrypt requiere puerto 80 público | Med | Usar DNS-01 challenge si 80 no accesible |
| Pérdida de datos | Low | Backup diario + snapshot + restauración verificada |

## Rollback

1. `qm stop <vmid>` + `qm destroy <vmid>`
2. Restaurar snapshot PVE previo
3. Revertir reglas firewall (2222, 80, 443)
4. Sin cambios en sistemas existentes

## Dependencies

- pve-desa01 con recursos disponibles
- IP estática en 192.168.1.0/24
- Acceso Internet para Omnibus package
- DNS interno o `/etc/hosts`

## Success Criteria

- [ ] VM 4vCPU/8GB/80GB creada en pve-desa01
- [ ] GitLab CE accesible vía HTTPS con cert Let's Encrypt
- [ ] Repo de prueba clonado y pusheado vía SSH (puerto 2222)
- [ ] Backup diario funcional verificado con restauración
- [ ] Snapshot PVE semanal configurado
