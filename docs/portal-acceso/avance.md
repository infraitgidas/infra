# Informe de Avance — Portal de Acceso Unificado

> **Feature**: Portal de Acceso (Feature #6)
> **Fecha**: 2026-07-02
> **Rama**: `feat/portal-access-remoto`
> **Estado SDD**: 🛠️ Implementación

---

## Resumen

Se eliminó Authentik 2026.5.3 como Identity Provider por resultar complejo de integrar con las herramientas GIDAS (problemas de sync LDAP, SSO incompleto). Reemplazado por **Homer** v26.4.2, un dashboard estático liviano que ofrece un punto único de acceso con cards visuales a todas las herramientas, sin depender de un IdP central. Cada herramienta sigue autenticando contra AD GDC01 directo, como ya venía funcionando.

---

## Decisión Arquitectónica

| Aspecto | Antes (Authentik) | Ahora (Homer) |
|---------|-------------------|---------------|
| **Portal** | Authentik IdP + dashboard nativo + SSO | Homer (Vue.js estático) servido por nginx |
| **Autenticación** | LDAP → AD + OIDC/OAuth (SSO) | AD directo en cada herramienta |
| **Complejidad** | 5 containers (server, worker, postgres, redis) | 1 CT + nginx (archivos estáticos) |
| **Mantenimiento** | Alto (updates de seguridad, DB, workers) | Cero (no hay backend) |
| **SSO** | Sí (vía OIDC/OAuth) | No (cada tool pide login AD) |
| **Riesgo** | Single point of failure (si Authentik cae, no se accede a nada) | Ninguno (las tools andan independientes) |
| **Recursos** | 1.5GB RAM + PostgreSQL + Redis | 512MB RAM, nada más |
| **Acceso remoto** | Twingate | Twingate (sin cambios) |

**Motivo del cambio**: Authentik requería configuración OIDC/OAuth específica por herramienta, algunas con soporte incompleto (Redmine requería plugin, Proxmox no es compatible directamente). Homer es Plug & Play — un YAML, 5 minutos, y listo.

---

## Infraestructura

| Recurso | Detalle |
|---------|---------|
| **CT 208** | Rocky Linux 9, 512MB RAM, 1 vCPU, IP `192.168.1.43/24` |
| **Servicio** | nginx 1.20.1 sirviendo Homer en `http://192.168.1.43/` |
| **Dashboard** | Homer v26.4.2 con 11 cards (Font Awesome icons) |

## Dashboard — Cards

| Categoría | Herramientas |
|-----------|-------------|
| **Herramientas** | GitLab, Redmine, Grafana, Proxmox VE, NetBox, GLPI |
| **Administración** | Identity Dashboard, MikroTik |
| **Enlaces** | Drupal GIDAS, Correo UTN, Twingate |

---

## Estado de Implementación

| Componente | Estado | Detalle |
|------------|--------|---------|
| **Authentik** | ❌ Reemplazado | Containers bajados, imágenes borradas (448MB liberados en GitLab VM), directorio `/root/portal/` eliminado. Reemplazado por Homer |
| **CT 208** | ✅ Creado y operativo | Rocky 9, 512MB, IP `192.168.1.43` |
| **Homer** | ✅ Instalado y sirviendo | v26.4.2 en `http://192.168.1.43/` |
| **Dashboard** | ✅ Configurado | 11 cards con Font Awesome icons |
| **SSO GitLab** | ⚠️ Ya no aplica | GitLab autentica contra AD directo (sigue funcionando) |
| **Grafana** | ✅ AD directo | LDAP configurado, login verificado con `infrait` |
| **Proxmox** | ✅ Realm LDAP | `gidas-ldap` creado, 17 usuarios sincronizados |
| **DNS MikroTik** | ✅ Configurado | `portal.gidas.local → 192.168.1.43` en MikroTik (LAN). Twingate: pendiente agregar recurso |
| **VM 207 portal** | ❌ Eliminada | Ex-Authentik VM, destruida de pve-desa04. Liberados 1.5GB RAM, 32GB disco |

---

## Acceso

| Recurso | URL |
|---------|-----|
| **Portal Homer** | `http://192.168.1.43/` |
| **CT 208 SSH** | `root@192.168.1.43` (vía PVE host) |

---

## Pendientes

| # | Tarea | Prioridad | Estado |
|---|-------|-----------|--------|
| 1 | ✅ Authentik eliminado y reemplazado por Homer | Alta | ✅ |
| 2 | ✅ CT 208 creado con Rocky 9, Homer instalado y sirviendo | Alta | ✅ |
| 3 | ✅ Dashboard con 11 cards configurado | Alta | ✅ |
| 4 | ✅ AD directo en Grafana configurado (LDAP) | **Alta** | ✅ |
| 5 | ✅ Realm LDAP en Proxmox creado y usuarios sincronizados | **Alta** | ✅ |
| 6 | ✅ DNS MikroTik `portal.gidas.local` | Alta | ✅ |
| 7 | Link en Drupal gidas.frlp.utn.edu.ar | Media | ⏳ |
| 8 | ✅ VM 207 ex-Authentik eliminada de pve-desa04 | Baja | ✅ |

---

## Configuración Completada — Detalle

### Grafana (CT 205 — 192.168.1.205)
Autenticación LDAP contra AD GDC01 configurada:
- `/etc/grafana/grafana.ini` — `[auth.ldap]` habilitado (backup: `grafana.ini.backup.20260702`)
- `/etc/grafana/ldap.toml` — servidor 192.168.1.117, bind `CN=infrait,...`, search `sAMAccountName`
- Admin password reseteado a `hlvs.2025`
- ✅ Login LDAP verificado: `infrait / Gidas2026!` → sesión creada con label `LDAP`
- **Rollback**: restaurar `grafana.ini.backup.20260702`, borrar `ldap.toml`, reiniciar grafana-server

### Proxmox (pve-desa04)
Realm LDAP `gidas-ldap` creado en pve-desa04:
- Tipo: `ldap`, server: `192.168.1.117`, base DN: `DC=GDC01,DC=local`
- Bind: `CN=infrait,OU=ServiceAccounts,DC=GDC01,DC=local`
- Filtro sync: `(&(objectCategory=person)(objectClass=user))` — excluye cuentas de sistema
- Realm seteado como default (`default 1`)
- 17 usuarios AD sincronizados (excluidos: Administrator, Guest, krbtgt, IPA$, pvetest)
- ✅ Login verificado: `infrait@gidas-ldap / Gidas2026!`
- Nota: usuarios existentes en PVE pueden agregarse manualmente; la sincronización automática se ejecutó con `pveum realm sync`
- **Rollback**: `pveum realm delete gidas-ldap`
