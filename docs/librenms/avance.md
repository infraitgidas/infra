# Informe de Avance — LibreNMS (Monitoreo de Red GIDAS)

> **Feature**: Monitoreo de Red (Feature #7)
> **Rama**: `feat/monitoreo-red`
> **Versión**: LibreNMS 26.6.1 / Grafana 13.0.1
> **Fecha**: 2026-07-03
> **Estado**: ✅ OPERATIVO

---

## 1. Resumen Ejecutivo

Se implementó LibreNMS como sistema de monitoreo de red dedicado para GIDAS, complementando el stack Prometheus+Grafana existente. Durante la puesta a punto se corrigieron 3 bugs críticos que impedían el funcionamiento: roles AD borrados en cada login, poller que nunca ejecutaba, y alert rules corruptas.

| Componente | Estado | Detalle |
|------------|--------|---------|
| **LibreNMS** | ✅ Operativo | 12 dispositivos, 18 alertas, AD, Telegram, SMTP |
| **Grafana** | ✅ Integrado | CT 205, 3 dashboards, datasource LibreNMS |
| **Portal GIDAS** | ✅ Integrado | Card visible para 4 grupos AD |
| **Alertas** | ✅ 18 reglas | Telegram + SMTP verificados |

---

## 2. Infraestructura

```
┌─ CT 210 (pve-desa04 / librenms) ──────────────────────────┐
│  LibreNMS 26.6.1 (Docker)      MariaDB 10    Redis 7     │
│  12 dispositivos monitoreados  18 alert rules              │
│  API: 192.168.1.45:8080                                   │
└────────────────────────────────────────────────────────────┘
                            │ (HTTP API, token auth)
                            ▼
┌─ CT 205 (pve-ad / sg-monitoring) ─────────────────────────┐
│  Grafana 13.0.1              Prometheus                    │
│  3 dashboards LibreNMS       Métricas PVE                  │
│  http://192.168.1.205:3000                                 │
└────────────────────────────────────────────────────────────┘

┌─ CT 208 (pve-desa04 / portal) ────────────────────────────┐
│  Portal FastAPI+LDAP          Card LibreNMS visible        │
│  https://portal.gidas.local                                 │
└────────────────────────────────────────────────────────────┘
```

| Recurso | Detalle |
|---------|---------|
| **CT 210** | Rocky Linux 9, 1GB RAM, 1 vCPU, 16GB, IP 192.168.1.45 |
| **LibreNMS** | Docker, imagen `:fixed` (26.6.1), nginx + php-fpm 8.4 |
| **MariaDB** | Docker, volumen `mysql_data`, healthcheck |
| **Redis** | Docker, volumen `redis_data`, cache + sesiones |
| **Grafana** | CT 205, 2GB RAM, `admin` / `hlvs.2025` |
| **DNS** | `nms.gidas.local` → 192.168.1.45 |

---

## 3. Autenticación

| Aspecto | Configuración |
|---------|--------------|
| **Mecanismo** | `active_directory` (nativo) |
| **Dominio** | `GDC01.local` |
| **Servidor** | `ldap://192.168.1.117` |
| **Bind** | `cn=infrait,ou=ServiceAccounts,dc=GDC01,dc=local` |
| **Base DN** | `DC=GDC01,DC=local` |
| **Acceso mínimo** | Todos los usuarios AD autenticados → `global-read` |

### Roles por grupo AD

| Grupo AD | Rol LNMS |
|----------|----------|
| `gidas-admins` | admin |
| `SRV-Monitoring` | admin |
| `G-IdentityAdmins` | admin |
| `gidas-pve-admin` | global-read |
| `gidas-pve-viewer` | global-read |
| Otros | global-read (por defecto) |

---

## 4. Dispositivos Monitoreados

| # | IP | Hostname | Tipo | Estado |
|---|-----|----------|------|--------|
| 1 | 192.168.1.14 | pve-desa04 | server | ✅ |
| 2 | 192.168.1.11 | pve-desa01 | server | ✅ |
| 3 | 192.168.1.12 | pve-desa02 | server | ✅ |
| 4 | 192.168.1.1 | mikrotik-gidas | network | ✅ |
| 5 | 192.168.1.117 | dc1-gidas | server | ✅ |
| 6 | 192.168.1.31 | pve-ad | server | ✅ |
| 7-12 | Varias | (sin resolver) | — | ⚠️ status=0 |

> **Total**: 12 dispositivos descubiertos, 6 polleando activamente, 6 con status=0 (requieren verificación SNMP).

---

## 5. Alertas

### Canales configurados

| Canal | Estado | Detalle |
|-------|--------|---------|
| **📧 Email** | ✅ Verificado | SMTP Office 365 (infrait@frlp.utn.edu.ar) |
| **🤖 Telegram** | ✅ Verificado | Bot @GiDAS_alertbot → chat @sistEma_lp |

### Reglas activas (18)

| # | Regla | Severidad | Condición |
|---|-------|-----------|-----------|
| 1 | Device Down | 🔴 critical | status=0 + ignore=0 |
| 2 | Device Rebooted | 🟡 warning | uptime < 10min |
| 3 | High CPU (Critical) | 🔴 critical | > 95% |
| 4 | High CPU (Warning) | 🟡 warning | > 85% |
| 5 | High Memory (Critical) | 🔴 critical | > 95% |
| 6 | High Memory (Warning) | 🟡 warning | > 85% |
| 7 | High Disk (Critical) | 🔴 critical | > 95% |
| 8 | High Disk (Warning) | 🟡 warning | > 85% |
| 9 | High Latency (Warning) | 🟡 warning | ping > 500ms |
| 10 | High Latency (Critical) | 🔴 critical | ping > 2000ms |
| 11 | Slow SNMP Polling | 🟡 warning | poll > 30s |
| 12 | Port Down | 🔴 critical | ifOperStatus=down |
| 13 | High Interface Errors | 🟡 warning | errors > 100/s |
| 14 | Bandwidth Saturation | 🟡 warning | tráfico > 900Mbps |
| 15 | SNMP Disabled | 🔴 critical | snmp_disable=1 |
| 16 | Unclassified Device | 🟡 warning | type="" |
| 17 | High Temperature | 🟡 warning | > 45°C |
| 18 | Device Not Polled | 🔴 critical | nunca polleado |

---

## 6. Bugs Corregidos

### Bug #1: Roles AD borrados en cada login
- **Causa**: `ActiveDirectoryAuthorizer::getRoles()` devolvía `[]` → `syncRoles([])` borraba todos los roles
- **Fix**: `auth_ad_global_read=true` + `auth_ad_groups` mapeado

### Bug #2: Poller nunca ejecutó
- **Causa**: Cron corría como root, `artisan schedule:run` rechaza root
- **Fix**: `su -s /bin/bash librenms -c 'php artisan schedule:run'` en crontab

### Bug #3: Alert rules vacías
- **Causa**: Reglas predefinidas con `query` vacío → `PDO::prepare()` error
- **Fix**: DELETE de reglas vacías

---

## 7. Integración Grafana

| Item | Valor |
|------|-------|
| **Grafana URL** | `http://192.168.1.205:3000` |
| **Login** | `admin` / `hlvs.2025` |
| **Datasource** | LibreNMS (tipo built-in, sin plugin externo) |
| **API Token** | `ec82d9e6a79031378428652b4ab4cdaabba9fde50dc0d17675b21bce650903d6` |

### Dashboards

| Dashboard | Descripción | Paneles |
|-----------|-------------|---------|
| **Overview** | Visión general | Stats dispositivos, alertas, top CPU, uptime |
| **Performance** | Rendimiento x dispositivo | CPU, RAM, disco, temperatura, uptime (templated) |
| **Network** | Red y tráfico | Tráfico bps, errores, bandwidth, top puertos (templated) |

---

## 8. Integración Portal GIDAS

LibreNMS agregado al portal en `portal-gidas/config.yaml`:

```yaml
- name: "LibreNMS"
  url: "https://nms.gidas.local"
  icon: "fas fa-eye"
  description: "Monitoreo de red"
  groups:
    - "G-Direccion"
    - "G-Coordinadores"
    - "G-Becarios"
    - "G-Graduados"
```

---

## 9. Archivos del Proyecto

| Archivo | Propósito |
|---------|-----------|
| `librenms/docker-compose.yml` | Stack Docker (librenms + mariadb + redis) |
| `librenms/deploy.sh` | Script de deploy |
| `librenms/.env.example` | Variables de entorno (template) |
| `librenms/scripts/backup.sh` | Backup DB + config |
| `librenms/scripts/setup-telegram.sh` | Guía Telegram Bot |
| `librenms/scripts/setup-grafana.sh` | Script integración Grafana |
| `librenms/grafana/dashboard-*.json` | 3 dashboards como código |
| `openspec/changes/librenms/` | SDD completo (proposal, design, tasks, informe) |
| `docs/runbooks/librenms-operations.md` | Runbook operativo |
| `docs/librenms/avance.md` | Este documento |
| `docs/portal-acceso/diseno/analisis-nms.md` | Análisis de alternativas |

---

## 10. Tareas Pendientes (30)

Detalle completo en `openspec/changes/librenms/tasks.md` (Fase 8).

| Prioridad | Cantidad | Principales |
|-----------|----------|-------------|
| 🔴 Alta | 3 | Roles AD, dispositivos status=0, SNMP en caídos |
| 🟡 Media | 16 | Traps, syslog, backup, heartbeat, discovery, merge |
| 🟢 Baja | 11 | Dashboards extra, WhatsApp, Let's Encrypt, tuning |

---

*Última actualización: 2026-07-03*
