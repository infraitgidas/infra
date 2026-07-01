# Informe de Cambios — Portal de Acceso Unificado

**Feature branch**: `feat/portal-access-remoto`
**Fecha**: 2026-07-01
**Estado**: EN IMPLEMENTACIÓN (Authentik eliminado → reemplazado por Homer)

---

## 1. Resumen Ejecutivo

Se reemplazó **Authentik 2026.5.3** (Identity Provider con SSO) por **Homer v26.4.2** (dashboard estático) como portal de acceso unificado a las herramientas GIDAS. El cambio se debió a la complejidad de integración OIDC/OAuth de Authentik con las herramientas del grupo, particularmente Redmine (requería plugin externo) y Proxmox (sin soporte directo).

| Concepto | Antes | Después |
|----------|-------|---------|
| **Solución** | Authentik (IdP + SSO + dashboard) | Homer (dashboard estático) |
| **Autenticación** | SSO vía OIDC/OAuth con AD como fuente | AD directo en cada herramienta |
| **Componentes** | 5 containers Docker (server, worker, postgres, redis) | 1 CT + nginx (archivos estáticos) |
| **Recursos** | ~1.5GB RAM | 512MB RAM |
| **Mantenimiento** | Updates, DB migrations, workers | Cero mantenimiento |
| **Dashboard** | Cards nativas de Authentik | Cards con Font Awesome icons |

---

## 2. Cambios Realizados

### 2.1. Eliminación de Authentik

- **Contenedores**: Detenidos y eliminados (`docker compose down`)
- **Imágenes Docker**: Limpiadas (`docker system prune -af`, 448MB liberados)
- **Datos**: Directorio `/root/portal/` eliminado de la GitLab VM (192.168.1.41)
- **Puertos**: 9000 y 9443 liberados en la GitLab VM

### 2.2. Creación de CT para Homer

- **ID**: 208
- **Host**: pve-desa04 (192.168.1.14)
- **SO**: Rocky Linux 9 (template: rockylinux-9-default_20240912)
- **Recursos**: 512MB RAM, 1 vCPU, 8GB disco
- **Red**: IP estática `192.168.1.43/24`, gateway `192.168.1.1`
- **DNS**: `192.168.1.117` (AD GDC01)

### 2.3. Instalación de Homer

- **Versión**: v26.4.2
- **Servidor**: nginx 1.20.1 en puerto 80
- **Ubicación**: `/usr/share/nginx/homer/`
- **Acceso**: `http://192.168.1.43/`

### 2.4. Dashboard Configurado

| Grupo | Cards |
|-------|-------|
| **Herramientas** | GitLab, Redmine, Grafana, Proxmox VE, NetBox, GLPI |
| **Administración** | Identity Dashboard, MikroTik |
| **Enlaces** | Drupal GIDAS, Correo UTN (Outlook), Twingate |

Los íconos usan Font Awesome incluido en Homer (sin descargas externas).

---

## 3. Infraestructura Afectada

| Recurso | Cambio | Impacto |
|---------|--------|---------|
| GitLab VM (192.168.1.41) | Puerto 9000/9443 liberados | Sin impacto en GitLab |
| CT 208 (192.168.1.43) | Nuevo | Portal Homer |
| VM 207 (192.168.1.42) | Sin cambios (no responde) | Pendiente decisión |
| MikroTik (192.168.1.1) | Pendiente: DNS `portal.gidas.local` | Sin cambios aún |

---

## 4. Decisiones Técnicas

| Decisión | Opción descartada | Motivo |
|----------|------------------|--------|
| Dashboard estático en vez de IdP | Authentik, Keycloak | Authentik no conectaba bien con herramientas; SSO agrega complejidad innecesaria para 17 usuarios |
| Homer vs Dashy | Dashy (más pesado) | Homer es más simple, 1 YAML, 0 backend |
| CT (contenedor) vs VM | VM 207 existente (no respondía) | CT es más liviano, template disponible, deploy inmediato |
| Font Awesome vs PNGs | PNGs descargados | FA viene incluido en Homer, no requiere assets extra |

---

## 5. Pendientes

| # | Tarea | Prioridad |
|---|-------|-----------|
| 1 | Configurar AD directo en Grafana (CT 205) | Alta |
| 2 | Configurar realm LDAP en Proxmox | Media |
| 3 | DNS MikroTik `portal.gidas.local → 192.168.1.43` | Media |
| 4 | Link en Drupal gidas.frlp.utn.edu.ar | Media |
| 5 | Decidir qué hacer con VM 207 (ex-Authentik) | Baja |

---

## 6. Acceso

| Recurso | URL/Comando |
|---------|-------------|
| **Portal** | `http://192.168.1.43/` |
| **CT 208** | `ssh root@192.168.1.43` (vía PVE host `pct enter 208`) |
| **PVE host** | `ssh root@192.168.1.14` |
| **AD GDC01** | `192.168.1.117`, bind: `CN=infrait,OU=ServiceAccounts,DC=GDC01,DC=local` |
