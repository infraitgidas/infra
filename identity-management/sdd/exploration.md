# Exploration: Gestión de Identidades — Dominio Gidas

> **Change**: identity-management
> **Date**: 2026-05-29
> **Source**: Análisis de la auditoría del cluster Proxmox + documentación existente
> **Status**: Sin acceso SSH — conclusiones basadas en evidencia indirecta del audit y mejores prácticas

---

## Current State

### Infraestructura Conocida

#### Nodo pve-ad (192.168.1.31) — Nodo separado de identidad
- **Proxmox 9.1.1** (Debian, kernel 6.17.2-1) — standalone, NO pertenece al cluster pve-gidas
- **15 GB RAM** (7.2 GB usada), **224 GB SSD** (LVM thin)
- **CPU**: Intel i5-7400, 4C/4T @ 3.0GHz
- **Uptime**: 1 día al momento del audit

#### Cargas en pve-ad

| ID | Nombre | Tipo | Estado | RAM | vCPU | IP |
|---|---|---|---|---|---|---|
| 100 | **DC-VM** | VM | **RUNNING** | 4 GB | — | — |
| 200 | sg-rojo | CT | RUNNING | 512 MB | 1 | 192.168.1.200 |
| 201 | sg-azul | CT | RUNNING | 512 MB | 1 | 192.168.1.204 |
| 202 | sg-verde | CT | RUNNING | 512 MB | 1 | 192.168.1.202 |
| 203 | sg-amarillo | CT | RUNNING | 512 MB | 1 | 192.168.1.203 |
| 205 | sg-monitoring | CT | RUNNING | 2 GB | 1 | 192.168.1.205 |

#### Máquinas Windows en cluster pve-gidas (pve-desa01) — todas STOPPED

| VMID | Nombre | Estado | RAM | vCPU | SO |
|---|---|---|---|---|---|
| 100 | BASE-Windows2k22 | **STOPPED** | 3 GB | 2 | Windows Server |
| 101 | VM-DC1 | **STOPPED** | 3 GB | 2 | Windows Server |
| 102 | DC2 | **STOPPED** | 3 GB | 2 | Windows Server |

#### Red
- **Red plana**: 192.168.1.0/24, sin VLANs
- **Gateway**: 192.168.1.1 (Mikrotik presumiblemente)
- **Sin segregación** de tráfico (management, storage, Corosync todo por el mismo bridge)
- No se detectaron servidores DNS/DHCP dedicados visibles desde el audit

#### Estado actual de servicios de identidad
- **DC-VM** (VM 100, 4GB) está RUNNING en pve-ad — casi con certeza es un Domain Controller
- **3 VMs Windows detenidas** en pve-desa01 (BASE-Windows2k22, VM-DC1, DC2) — posiblemente un intento anterior de levantar AD en el cluster o VMs preparadas para pruebas
- El nombre `DC-VM` sugi fuertemente **Active Directory** (no FreeIPA ni Samba standalone)
- Los containers `sg-rojo`, `sg-azul`, `sg-verde`, `sg-amarillo` (512MB cada uno) probablemente son entornos de desarrollo/gestión para subgrupos de investigación
- `sg-monitoring` (2GB) es el nodo de monitoreo — stack desconocido

### Lo que NO sabemos (necesita verificación)

- **¿Qué SO corre DC-VM?** — Windows Server (¿2019? ¿2022?) o Samba AD en Linux
- **¿Cuál es el nombre de dominio actual?** — gidas.local, gidas.frlp.utn.edu.ar, otro
- **¿DNS está integrado en DC-VM o hay otro servidor DNS?**
- **¿DHCP lo da el Mikrotik o el DC?**
- **¿Qué stack de monitoreo corre en sg-monitoring?**
- **¿Qué son los 4 sg-* containers?** — ¿Desarrollo web? ¿Entornos aislados? ¿Bases de datos?
- **¿Hay algún servicio LDAP/Kerberos funcionando además de AD?**
- **¿Hay FreeIPA o algún otro IDM Linux funcionando?**
- **¿Cómo se autentican los usuarios actualmente?** — ¿SSH con claves? ¿Password local? ¿Alguna integración con AD?
- **¿Hay VPN configurada?**
- **¿El dominio `gidas.com.ar` o `gidas.frlp.utn.edu.ar` existe y es gestionable?**

---

## Affected Areas

- `identity-management/` — todo el cambio está en esta carpeta
- `secrets/proxmox.yaml` — puede necesitar credenciales de AD/FreeIPA
- `docs/` — documentación de autenticación y procedimientos
- Potencialmente: configuración de PVE realms, SSSD en nodos Linux, DNS en el Mikrotik

---

## Analysis: Identity Needs for Grupo Gidas

### Perfil del Grupo de Investigación
- **Universidad**: FRLP UTN (Facultad Regional La Plata, Universidad Tecnológica Nacional)
- **Estructura**: Subgrupos de investigación (rojo, azul, verde, amarillo)
- **Mixto**: Miembros docentes, investigadores, becarios, estudiantes — roles con rotación frecuente
- **Infraestructura**: Proxmox cluster + contenedores Linux mayoritariamente, algunas VMs Windows

### Necesidades de Identidad

1. **Autenticación centralizada** para:
   - Proxmox VE web UI y API (todos los nodos)
   - Proxmox Backup Server (futuro)
   - SSH a nodos Linux y containers
   - Acceso a servicios internos (gidas-site-desa, monitoreo)
   - VPN (si aplica)

2. **Gestión de grupos** para:
   - Separar permisos por subgrupo (rojo, azul, verde, amarillo)
   - Roles diferenciados: admin, developer, viewer
   - Altas y bajas rápidas para estudiantes/temporarios

3. **DNS interno** para:
   - Resolución de nombres de nodos, VMs, containers
   - Integración con AD (SRV records para Kerberos/LDAP)

4. **Auditoría** de accesos (quién hizo qué y cuándo)

---

## Approaches

### Approach 1: Active Directory Only (Windows Server)

**Qué es**: DC-VM ya corre AD. Extenderlo como única fuente de identidad. Linux clients autentican via SSSD + realm join.

**Componentes**:
- DC-VM como Domain Controller (Windows Server 2019/2022)
- Posible 2do DC para redundancia (una de las VMs Windows detenidas)
- DNS integrado en AD
- SSSD en todos los nodos Linux para autenticación
- Realm de tipo AD en Proxmox

| Aspecto | Detalle |
|---------|---------|
| Esfuerzo | Bajo si DC-VM ya está funcional |
| Windows | ✅ Nativo, integración perfecta |
| Linux | ⚠️ Funcional via SSSD pero sin HBAC granular ni sudo rules nativas |
| Complejidad | Baja — una sola fuente de verdad |
| Gestión | Windows tools (ADUC, GPMC) — requiere máquina Windows para admin |

- **Pros**:
  - Ya hay un DC corriendo (DC-VM) — aprovechar lo existente
  - AD es maduro, documentado, soportado por Proxmox nativamente
  - DNS integrado sin configurar servidores separados
  - Las VMs Windows detenidas pueden servir como DCs secundarios
  - SSSD + `realm join` funciona bien con AD en Linux moderno

- **Cons**:
  - Gestión Windows-only (ADUC, PowerShell) — overhead operativo
  - HBAC (Host-Based Access Control) no es nativo en AD — requiere soluciones como Centrify o extending schema
  - Sudo rules no se gestionan desde AD sin extensiones (sudo-ldap)
  - La licencia de Windows Server puede ser un problema (evaluación vencida?)
  - Sin interfaz web moderna para admin (todo es MMC o PowerShell)

- **Esfuerzo**: Bajo-Medio

### Approach 2: FreeIPA Only

**Qué es**: Servidor FreeIPA en Linux (Rocky/Alma/RHEL) gestiona toda la identidad. DC-VM podría migrarse o mantenerse como AD legacy.

**Componentes**:
- Servidor FreeIPA (Rocky Linux container o VM en pve-ad)
- DNS integrado en FreeIPA (Bind)
- Certificate Authority (Dogtag PKI)
- HBAC + sudo rules nativas
- Web UI moderna

| Aspecto | Detalle |
|---------|---------|
| Esfuerzo | Medio-Alto (setup desde cero o migración) |
| Windows | ⚠️ No tiene integración directa con AD — require trust o Samba |
| Linux | ✅ Nativo, HBAC, sudo, certs, todo integrado |
| Complejidad | Media — FreeIPA es más complejo que AD básico |
| Gestión | Web UI + CLI — todo desde Linux |

- **Pros**:
  - 100% Linux native — sin dependencia de Windows Server
  - **HBAC** nativo: control granular de qué usuarios acceden a qué hosts
  - **sudo rules** integradas: quién puede hacer qué como root
  - **Certificate Authority** integrada (Dogtag) — útil para TLS interno
  - **Web UI** moderna y funcional
  - Sin licencias de Windows Server
  - Integración perfecta con SSSD (es su origen)
  - Proxmox soporta realm IPA nativamente (tipo `ipa`)

- **Cons**:
  - No hay nada instalado hoy — hay que construir desde cero
  - Si DC-VM ya es AD funcional, hay que migrar o convivir
  - Windows clients no pueden unirse a FreeIPA nativamente
  - Curva de aprendizaje del equipo si vienen de AD
  - DNS de FreeIPA es Bind — más configurable pero menos "magia" que AD DNS

- **Esfuerzo**: Medio-Alto

### Approach 3: AD + FreeIPA Coexistencia con Trust (RECOMENDADO)

**Qué es**: AD (DC-VM) como fuente primaria de identidad para Windows y servicios existentes. FreeIPA como IDM Linux con trust cross-realm con AD. Usuarios gestionados desde AD, políticas Linux desde FreeIPA.

**Componentes**:
- **AD**: DC-VM (existente) + posible 2do DC
- **FreeIPA**: Servidor en Linux (Rocky/Alma, container o VM en pve-ad)
- **Trust AD↔FreeIPA**: Cross-realm Kerberos trust
- **Proxmox**: Realm tipo AD (u IPA) para autenticación
- **SSSD** en todos los nodos Linux, configurado contra FreeIPA (que trustea AD)

| Aspecto | Detalle |
|---------|---------|
| Esfuerzo | Alto (configurar trust, sincronización) |
| Windows | ✅ Nativo via AD |
| Linux | ✅ Nativo via FreeIPA + SSSD |
| Complejidad | Alta — dos stacks de identidad que deben coexistir |
| Gestión | AD para usuarios/grupos, FreeIPA para políticas Linux |

Flujo de autenticación típico:

```
Usuario Linux SSH
  → SSSD consulta FreeIPA
    → FreeIPA verifica trust con AD
      → AD autentica (Kerberos)
        → FreeIPA aplica HBAC + sudo rules
          → Acceso concedido/denegado
```

- **Pros**:
  - Lo mejor de ambos mundos: gestión Windows existente + políticas Linux nativas
  - Migración progresiva: no hay que tirar AD existente
  - HBAC + sudo rules para entornos Linux
  - PKI integrada via FreeIPA (Dogtag)
  - Los subgrupos (rojo, azul, verde, amarillo) se modelan como grupos en AD + HBAC rules en FreeIPA
  - Proxmox puede autenticar contra cualquiera de los dos

- **Cons**:
  - Complejidad operativa: mantener dos sistemas de identidad
  - Trust cross-realm no es trivial de configurar
  - La latencia de autenticación aumenta (AD → FreeIPA → SSSD → host)
  - Si AD cae, FreeIPA puede tener usuarios cacheados pero no nuevos logins
  - Documentación y troubleshooting es más complejo
  - Requiere comprensión sólida de Kerberos

- **Esfuerzo**: Alto

### Approach 4: Samba AD + FreeIPA (alternativa mixta open-source)

**Qué es**: DC-VM migrado a Samba 4 como Domain Controller compatible con AD. FreeIPA como IDM Linux. Samba y FreeIPA comparten el mismo Kerberos realm o usan trust.

**Componentes**:
- **Samba AD DC** (reemplazando potencialmente Windows Server en DC-VM)
- **FreeIPA** como IDM Linux
- Trust o sincronización entre ambos

- **Pros**:
  - 100% open-source, sin licencias
  - Samba AD es compatible con AD nativo (mismo protocolo)
  - Flexibilidad total de configuración

- **Cons**:
  - Samba AD no es 100% feature-par con Windows Server AD
  - Migrar de Windows Server a Samba es riesgoso
  - Menos herramientas de gestión
  - Documentación más limitada para edge cases

- **Esfuerzo**: Alto (migración riesgosa)

---

## Recommendation

### Recommended Approach: Approach 3 — AD + FreeIPA Coexistence with Trust

**Razones**:
1. **Ya hay un AD funcionando** (DC-VM, RUNNING) — no tiene sentido migrar o reemplazar algo que funciona
2. **La infraestructura Linux es mayoritaria** — los 5 nodos Proxmox + 5 containers + VMs Linux necesitan gestión de identidad Linux-native
3. **Subgrupos de investigación** — HBAC + sudo rules de FreeIPA permiten modelar rojo/azul/verde/amarillo de forma granular sin depender de extensiones AD
4. **Migración progresiva** — AD sigue siendo el source of truth para usuarios, FreeIPA se suma para gestión Linux
5. **Proxmox soporta ambos realms** — se puede probar contra AD primero, migrar a IPA después

### Plan de Acción Recomendado

**Fase 0 — Verificación (urgente, sin acceso físico)**:
1. Determinar SO de DC-VM (¿Windows Server? ¿Samba?)
2. Determinar nombre de dominio actual
3. Verificar estado de DNS (¿en AD? ¿en Mikrotik?)
4. Verificar estado de las VMs Windows detenidas (¿eran DCs secundarios?)
5. Confirmar stack de sg-monitoring

**Fase 1 — Fundación**:
1. Desplegar FreeIPA server en un container o VM en pve-ad
   - Recomendación: Rocky Linux 9, 2GB RAM, 20GB disco
2. Configurar DNS integrado en FreeIPA
3. Establecer trust cross-realm AD ↔ FreeIPA
4. Configurar SSSD en nodos Proxmox y containers
5. Agregar realm AD (o IPA) en PVE para autenticación centralizada

**Fase 2 — Modelado de Acceso**:
1. Crear grupos en AD: `gidas-admins`, `gidas-rojo`, `gidas-azul`, `gidas-verde`, `gidas-amarillo`, `gidas-monitoring`
2. Crear HBAC rules en FreeIPA para cada grupo
3. Configurar sudo rules en FreeIPA
4. Definir roles en Proxmox (Admin, PVEAdmin, PVEViewer) y mapear a grupos AD

**Fase 3 — DNS y Redes**:
1. Definir el dominio (ver recomendación abajo)
2. Configurar resolución DNS forward (FreeIPA → AD → Internet)
3. Evaluar segmentación de red (VLANs)
4. Configurar DHCP en Mikrotik para entregar DNS correcto

### Recomendación de Dominio

Basado en las mejores prácticas actuales:

| Opción | Recomendación |
|--------|---------------|
| `gidas.local` | ❌ No recomendado — conflicto con mDNS (Bonjour/Avahi) |
| `gidas.internal` | ✅ Bueno si NO hay dominio público |
| `gidas.frlp.utn.edu.ar` | ✅ Ideal si la UTN/FRLP permite gestionar subdominio |
| `gidas.com.ar` | ✅ Bueno si el grupo posee el dominio y quiere resolución externa |
| `gidas.lan` | ⚠️ Posible pero no estándar |

**Recomendación primaria**: `gidas.frlp.utn.edu.ar` si se puede coordinar con la FRLP. Alternativa: `gidas.internal`.

Para AD, el dominio NetBIOS sería `GIDAS`. El dominio DNS completo dependerá de la opción elegida arriba, con un subdominio específico para AD como `ad.gidas.internal` o `corp.gidas.frlp.utn.edu.ar`.

---

## Risks

| Riesgo | Severidad | Descripción | Mitigación |
|--------|-----------|-------------|------------|
| **No sabemos qué corre en DC-VM** | 🔴 Alto | Podría ser Samba, Windows Server evaluation (expirada), o incluso otro servicio no-AD | Verificar con acceso SSH antes de cualquier acción |
| **Licencia Windows Server** | 🟡 Medio | Si es evaluation, caduca; si no hay licencia, el AD se cae | Tener plan de migración a Samba AD o FreeIPA full |
| **Complejidad del trust** | 🟡 Medio | AD↔FreeIPA trust falla fácil si DNS/Kerberos no está perfecto | Documentar paso a paso, probar en aislado |
| **Dependencia de dominio externo** | 🟡 Medio | Si eligen `gidas.frlp.utn.edu.ar`, dependen de la UTN | Tener `gidas.internal` como fallback |
| **Sin backups de AD** | 🔴 Alto | DC-VM sin backup = pérdida del dominio completo | Backups del DC (Veeam, Windows Server Backup, o snapshot de PVE) |
| **Las sg-VMs no se reinician desde el audit** | 🟢 Bajo | 9GB RAM comprometida sin uso en pve-desa01 | Decidir si reactivar o liberar recursos |

---

## Ready for Proposal

**Yes** — El análisis es suficiente para armar un proposal. Sin embargo, la **verificación del estado actual de DC-VM** debe hacerse antes de ejecutar cualquier implementación. El proposal debe incluir esa verificación como primer paso obligatorio.

### Información crítica faltante (necesaria para diseño)
1. Sistema operativo y rol exacto de DC-VM
2. Nombre de dominio actual
3. Servicios DNS/DHCP actuales
4. Stack de sg-monitoring
5. Propósito de los sg- containers
6. Licenciamiento de Windows Server (si aplica)

---

## Referencias

- **Auditoría de cluster**: `openspec/changes/proxmox-cluster-analysis/auditoria-cluster.md`
- **Documentación auth ejemplo**: `docs/auth.example.md`
- **Secretos**: `secrets/proxmox.yaml` (SOPS-encrypted)
- **Repositorio**: Git `main` — 3 commits, último: `1436a3d` (auditoría cluster)
