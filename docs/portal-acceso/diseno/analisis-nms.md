# Análisis de Opciones — Sistema de Monitoreo de Red (NMS)

> **Feature**: Monitoreo de Red (Feature propuesta)
> **Rama**: `feat/monitoreo-red`
> **Fecha**: 2026-07-02

---

## 1. Contexto

Actualmente GIDAS tiene:
- **Prometheus + Grafana** en CT 205 (sg-monitoring) para métricas de cluster Proxmox y dispositivos via SNMP
- **Alertmanager** para notificaciones
- Dashboard de métricas de PVE nodes, MikroTik, AD

**Lo que falta**: Un sistema de monitoreo de red dedicado que ofrezca:
- Auto-descubrimiento de dispositivos (LLDP/CDP/SNMP)
- Gestión de fallas con alertas inteligentes
- Mapas de topología de red
- Reportes históricos de disponibilidad
- Interfaz unificada para network operations

---

## 2. Alternativas Analizadas

### Alternativa A: LibreNMS

**Stack**: PHP + MySQL/MariaDB + Redis + SNMP + Docker (o nativo)
**Repo**: [librenms/librenms](https://github.com/librenms/librenms) — 22k ⭐
**Licencia**: GPL-3.0

| Aspecto | Evaluación |
|---------|-----------|
| 🚀 **Recursos** | ~512MB RAM, requiere PHP, MySQL, Redis |
| 🔐 **LDAP/AD** | ✅ Nativo (soporta autenticación LDAP) |
| 🌐 **Auto-descubrimiento** | ✅ SNMP, LLDP, CDP, OSPF, BGP |
| 📊 **Gráficas** | ✅ RRDtool integrado, históricos |
| 🔔 **Alertas** | ✅ Reglas configurables, canales mail/telegram/slack |
| 🗺️ **Mapas** | ✅ Topología automática |
| 🐳 **Deploy** | Docker Compose o nativo |
| 🔧 **Mantenimiento** | Medio (updates via daily.sh, migraciones DB) |
| 👥 **Multi-usuario** | ✅ Roles y permisos |
| 🎯 **Para GIDAS** | **Excelente.** Cobertura completa para red. |

**Lo que ya tenemos vs LibreNMS**:
| Aspecto | Prometheus/Grafana (actual) | LibreNMS |
|---------|---------------------------|----------|
| Métricas PVE | ✅ | ⚠️ Básico (SNMP) |
| Auto-descubrimiento | ❌ Manual (scrape targets) | ✅ Automático |
| Topología de red | ❌ | ✅ Mapas |
| Alertas inteligentes | ⚠️ Básicas (reglas PromQL) | ✅ Thresholds + flapping |
| Reportes disponibilidad | ❌ | ✅ SLA, uptime |
| CDP/LLDP discovery | ❌ | ✅ Nativo |
| Interfaz network-centric | ❌ (Grafana general) | ✅ Dedicada NMS |

### Alternativa B: Zabbix

**Stack**: C (server) + PHP (frontend) + PostgreSQL + nginx
**Repo**: [zabbix/zabbix](https://github.com/zabbix/zabbix) — 12k ⭐
**Licencia**: AGPL-3.0

| Aspecto | Evaluación |
|---------|-----------|
| 🚀 **Recursos** | ~1GB RAM, server + frontend + DB |
| 🔐 **LDAP/AD** | ✅ Nativo |
| 🌐 **Auto-descubrimiento** | ✅ Por red, SNMP, agent, trappers |
| 📊 **Gráficas** | ✅ Templates personalizables |
| 🔔 **Alertas** | ✅ Muy potentes (escalados, acciones) |
| 🐳 **Deploy** | Docker Compose |
| 🔧 **Mantenimiento** | Alto (configuración más compleja) |
| 🎯 **Para GIDAS** | **Buena opción pero más pesada.** |

### Alternativa C: CheckMK Raw

**Stack**: C++ (core) + Python (agentes) + PHP (frontend) + nginx
**Repo**: [checkmk/checkmk](https://github.com/checkmk/checkmk) — 3.5k ⭐
**Licencia**: GPL-2.0 (Raw Edition)

| Aspecto | Evaluación |
|---------|-----------|
| 🚀 **Recursos** | ~1GB RAM |
| 🔐 **LDAP/AD** | ⚠️ Solo en edición Enterprise |
| 🌐 **Auto-descubrimiento** | ✅ Muy bueno |
| 🔧 **Mantenimiento** | Medio |
| 🎯 **Para GIDAS** | ❌ LDAP solo en paga |

### Alternativa D: Prometheus + SNMP exporter (estado actual)

Ya implementado. Cubre métricas pero no NMS features.

---

## 3. Benchmarking

| Criterio | LibreNMS | Zabbix | CheckMK Raw | Prom+Grafana |
|----------|----------|--------|-------------|--------------|
| **RAM total** | ~512MB | ~1GB | ~1GB | ~256MB |
| **LDAP/AD** | ✅ | ✅ | ❌ | ❌ (Grafana sí) |
| **Auto-discovery** | ✅ Excelente | ✅ Muy bueno | ✅ Bueno | ❌ Manual |
| **Alertas** | ✅ Buenas | ✅ Excelentes | ✅ Buenas | ✅ Básicas |
| **Mapas topología** | ✅ | ❌ | ❌ | ❌ |
| **Reportes SLA** | ✅ | ✅ | ✅ | ❌ |
| **Facilidad deploy** | ✅ Media | ⚠️ Compleja | ✅ Media | ✅ Simple |
| **Mantenimiento** | ✅ Medio | ⚠️ Alto | ✅ Medio | ✅ Bajo |
| **Integración Grafana** | ✅ Data source | ✅ Data source | ❌ | ✅ Ya existe |

---

## 4. Recomendación

### 🏆 LibreNMS

Complementa perfectamente a Prometheus + Grafana. Mientras Prometheus se queda con las métricas del cluster PVE, LibreNMS cubre el **monitoreo de red**:

```
                     ┌── Prometheus ──► Grafana (métricas PVE, nodos)
                     │
┌─ Switches ─────────┤
│ Routers  ──────────┤
│ Firewalls ─────────┤
│ APs      ──────────┤
│ Servers  ──────────┤
│ (SNMP)             │
                     └── LibreNMS ───► Dashboard NMS (fallas, topología, SLA)
```

**Integración**: LibreNMS tiene un datasource para Grafana, así que las métricas de red pueden verse en ambos lugares.

### Opciones de deploy

1. **CT propio** — CT 210 (256MB RAM, 1 vCPU) — recomendado para aislar
2. **Mismo CT que monitoreo** — CT 205 (sg-monitoring) — ahorra recursos
3. **Mismo CT que portal** — NO recomendado (mezcla concerns)

---

## 5. Próximos Pasos

| Paso | Descripción |
|------|-------------|
| 1 | ✅ Aprobar elección (LibreNMS) |
| 2 | Crear SDD exploration/proposal/design/tasks |
| 3 | Crear CT 210 o usar CT 205 |
| 4 | Deploy LibreNMS con Docker |
| 5 | Configurar LDAP/AD |
| 6 | Configurar auto-descubrimiento SNMP |
| 7 | Configurar alertas |
| 8 | Integrar con portal GIDAS y Grafana |
