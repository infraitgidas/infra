# Informe de Avance — Portal de Acceso Unificado

> **Feature**: Portal de Acceso (Feature #6)
> **Fecha**: 2026-07-01
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
| **Authentik** | ❌ Eliminado | Containers bajados, imágenes borradas (448MB liberados en GitLab VM), directorio `/root/portal/` eliminado |
| **CT 208** | ✅ Creado y operativo | Rocky 9, 512MB, IP `192.168.1.43` |
| **Homer** | ✅ Instalado y sirviendo | v26.4.2 en `http://192.168.1.43/` |
| **Dashboard** | ✅ Configurado | 11 cards con Font Awesome icons |
| **SSO GitLab** | ⚠️ Ya no aplica | GitLab autentica contra AD directo (sigue funcionando) |
| **SSO Grafana** | ⏳ Pendiente | Configurar AD directo en Grafana (ya no vía Authentik) |
| **LDAP Proxmox** | ⏳ Pendiente | Realm LDAP en PVE (misma config, sin Authentik de por medio) |
| **DNS MikroTik** | ⏳ Pendiente | `portal.gidas.local → 192.168.1.43` (necesita password admin) |
| **VM 207 portal** | ⚠️ Detenida | Ex-Authentik VM, no responde. Decidir si eliminar |

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
| 4 | Configurar AD directo en Grafana (CT 205) | **Alta** | ⏳ |
| 5 | Configurar realm LDAP en Proxmox | Media | ⏳ |
| 6 | DNS MikroTik `portal.gidas.local` | Media | ⏳ |
| 7 | Link en Drupal gidas.frlp.utn.edu.ar | Media | ⏳ |
| 8 | Decidir qué hacer con VM 207 (ex-Authentik) | Baja | ⏳ |

---

## Configuración Pendiente — Detalle

### Grafana (CT 205 — 192.168.1.205)
Configurar autenticación LDAP directa contra AD GDC01 (sin Authentik):
```ini
[auth.ldap]
enabled = true
config_file = /etc/grafana/ldap.toml
```

### Proxmox (pve-desa04)
Datacenter → Authentication → Add → LDAP:
```
Host: 192.168.1.117
Base DN: DC=GDC01,DC=local
Bind DN: CN=infrait,OU=ServiceAccounts,DC=GDC01,DC=local
Password: Gidas2026!
User filter: (objectClass=user)
```
