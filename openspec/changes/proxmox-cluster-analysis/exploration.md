# Exploration: Análisis del Cluster Proxmox

> **⚠️ ACTUALIZADO**: La auditoría remota se realizó el 2026-05-27.
> Ver `auditoria-cluster.md` para el diagnóstico completo con datos reales.

## Current State

### Infrastructure Known
- **Cluster pve-desa**: IP `192.168.1.11`, port 8006, user root
- **Nodo DC + Observability**: IP `192.168.1.31`, port 8006, user root
- **2 nodos** -- ambos con el mismo password
- Todos los directorios de configuración (`proxmox/`, `mikrotik/`, `directoryServer/`) están **vacíos**
- Sin monitoring stack implementado
- Sin backup server configurado
- Sin scripts de automatización (Ansible, Terraform)
- Repositorio no es git (aún)

### Estado del Cluster
Ambos nodos existen pero no sabemos si forman un cluster activo. La configuración actual NO está documentada en el repo. Se necesita auditarlos para determinar:
- ¿Ya están clusterizados o son nodos independientes?
- ¿Qué versión de Proxmox corre cada uno?
- ¿Qué tipo de almacenamiento usan (ZFS, ext4, LVM, etc.)?
- ¿Qué cargas de trabajo están corriendo?
- ¿Hay algún backup funcionando?

## Affected Areas
- `proxmox/` — almacenar configuraciones, scripts, playbooks de Ansible
- `docs/` — documentar setup actual, arquitectura, procedimientos
- `secrets/proxmox.yaml` — ya existe con SOPS, mantener actualizado
- `openspec/specs/proxmox/` — specs futuros para el dominio Proxmox
- `openspec/changes/proxmox-cluster-analysis/` — este exploration

## Approaches

### 1. **QDevice + ZFS Replication** (RECOMENDADO para 2 nodos)
La combinación recomendada por la comunidad y documentación oficial para clusters de 2 nodos.

**Componentes**:
- **QDevice** (corosync-qnetd): tercer voto externo para quorum. Puede correr en una Raspberry Pi, VM liviana (512MB RAM), o incluso en el nodo DC + Observability si está en infraestructura separada.
- **ZFS local** en cada nodo con pools mirror/raidz según discos disponibles.
- **Replicación nativa de Proxmox** via ZFS snapshots entre nodos (cada 5-15 min).
- **Proxmox Backup Server** dedicado para backups con deduplicación.

**Storage**: ZFS local + replicación asíncrona (RPO ~ minutos).
**HA limitado**: failover manual o semi-automático (sin live migration, pero VMs pueden restartear).
**Red**: Corosync necesita <2ms latencia, idealmente VLAN dedicada.

- **Pros**:
  - Sin dependencia de storage compartido externo
  - ZFS da integridad de datos, compresión, snapshots nativos
  - QDevice evita split-brain y mantiene quorum (~$50 en HW)
  - PBS resuelve backup con deduplicación 5-10x
  - Menor complejidad operativa que Ceph
  - Cada nodo mantiene su propio storage -- sin SPOF compartido
  
- **Cons**:
  - NO hay live migration (necesita shared storage)
  - Con replicación asíncrona, RPO de minutos (no segundos)
  - Failover no es instantáneo -- requiere restart de VMs
  - Si un nodo falla, el otro necesita capacidad para todas las VMs
  - 2 nodos + QDevice da disponibilidad, no HA enterprise

- **Effort**: Low-Medium
  - QDevice: ~30 min setup
  - ZFS + replicación: ~1-2 horas
  - PBS: ~1-2 horas instalación y configuración
  - Monitoreo: ~1-2 horas

### 2. **Ceph + 3er Nodo** (NO RECOMENDADO para 2 nodos)
Ceph requiere **mínimo 3 nodos** para monitores y quorum. Intentarlo en 2 nodos es una trampa conocida.

**Storage compartido**: Ceph RBD como pool compartido entre nodos.
**HA completo**: live migration, failover automático.
**Red**: requiere mínimo 10GbE para rendimiento aceptable.

- **Pros**:
  - Live migration entre nodos
  - HA real con failover automático
  - Storage compartido -- cualquier nodo corre cualquier VM
  - Self-healing del storage
  
- **Cons**:
  - **NO funciona en 2 nodos** -- necesita 3 nodos mínimo para monitores Ceph
  - Altamente demandante de red: 10GbE mínimo, 25GbE recomendado
  - Consume CPU/RAM extra (4-8GB RAM + 1-2 cores por nodo para OSDs)
  - Complejidad operativa alta
  - Recovery en redes 1GbE es extremadamente lento
  - Si no se tienen 3 nodos + 10GbE, el overhead supera los beneficios

- **Effort**: High (requiere HW adicional: 3er nodo, red 10GbE)

### 3. **DRBD + Pacemaker** (OPCIÓN LEGACY)
Solución tradicional de storage replicado a nivel de bloque con cluster manager.

- **Pros**:
  - Live migration posible con DRBD9
  - Sin dependencia de storage externo
  
- **Cons**:
  - Configuración significativamente más compleja
  - Pacemaker añade otra capa de orquestración
  - Menos integrado con Proxmox que ZFS replicación
  - DRBD no tiene el ecosistema de herramientas que ZFS
  - Comunidad reduciendo uso en favor de ZFS+Ceph

- **Effort**: High

### 4. **NFS/iSCSI externo** (ALTERNATIVA)
Usar storage externo (NAS/SAN) como backend compartido.

**Storage**: NFS desde NAS o iSCSI desde SAN.
**HA**: live migration posible, failover con fencing.
**Red**: depende del backend, típicamente 1-10GbE.

- **Pros**:
  - Live migration posible
  - Storage compartido simple
  - Fácil de implementar si ya hay NAS
  
- **Cons**:
  - El NAS/SAN es **single point of failure**
  - NFS introduce latencia adicional
  - Dependencia de infraestructura externa al cluster
  - Costo de HW adicional
  - Para 2 nodos, la replicación local es más confiable

- **Effort**: Medium (depende de si ya existe NAS)

## Recommendation

### Arquitectura Recomendada: QDevice + ZFS + Replicación + PBS

Para este cluster de 2 nodos (pve-desa y DC+Observability), la combinación óptima es:

```
┌─────────────────────────────────────────────────────────┐
│                    Cluster Proxmox                       │
│                                                         │
│  ┌──────────────┐          ┌──────────────────┐        │
│  │  pve-desa    │◄────────►│  DC+Observability│        │
│  │  192.168.1.11│ Corosync │  192.168.1.31    │        │
│  │              │ 2 rings  │                  │        │
│  │  ┌────────┐  │◄────────►│  ┌────────────┐  │        │
│  │  │ ZFS    │  │  Repl.   │  │ ZFS        │  │        │
│  │  │ pool A │  │  async   │  │ pool B     │  │        │
│  │  └────────┘  │          │  └────────────┘  │        │
│  └──────┬───────┘          └────────┬─────────┘        │
│         │                          │                   │
│         └──────────┬───────────────┘                   │
│                    │ QDevice vote                       │
│           ┌────────▼────────┐                          │
│           │   QDevice       │                          │
│           │ (Pi / VM /      │                          │
│           │  nodo externo)  │                          │
│           └────────┬────────┘                          │
│                    │                                    │
└────────────────────┼────────────────────────────────────┘
                     │
                     │ backups
            ┌────────▼────────┐
            │  PBS Dedicado   │
            │ (bare metal o   │
            │  VM separada)   │
            └─────────────────┘
```

### Plan de Implementación por Fases

**Fase 0 — Auditoría (URGENTE, 1 sesión)**:
Antes de tocar nada, auditar el estado actual de ambos nodos:
- `pveversion` en cada nodo
- `pvecm status` para ver si ya hay cluster
- `zpool status` / `lsblk` para almacenamiento
- `qm list` para inventario de VMs
- `cat /etc/network/interfaces` para red
- Verificar conectividad y latencia entre nodos

**Fase 1 — Fundación (2-3 sesiones)**:
1. Clusterizar nodos (o verificar cluster existente)
2. Configurar QDevice en el nodo DC+Observability (o Raspberry Pi separada)
   - `apt install corosync-qnetd` en el QDevice host
   - `apt install corosync-qdevice` en cada nodo PVE
   - `pvecm qdevice setup <QDEVICE_IP>`
3. Configurar Corosync con dual link redundancy (link0 y link1)
   - Ideal: link0 por red management, link1 por red de storage
4. Configurar firewalls (puertos UDP 5405-5412, TCP 5403)

**Fase 2 — Storage (2-3 sesiones)**:
1. Configurar ZFS pools en cada nodo (mirror si hay pares de discos, RAIDZ si más de 3)
   - `ashift=12`, `compression=zstd`, `atime=off`
   - Separar OS (mirror SSD) de datos (pool ZFS)
2. Configurar replicación Proxmox entre nodos
   - Schedule cada 15 minutos para VMs críticas
   - Schedule cada 1 hora para VMs no críticas
3. Ajustar ARC: por defecto 50% de RAM, puede limitarse si hay presión de memoria

**Fase 3 — Backup (1-2 sesiones)**:
1. Instalar Proxmox Backup Server
   - Ideal: bare metal separado pero no crítico -- VM en el cluster es OK inicialmente
   - ZFS para datastore con compresión zstd
   - Mínimo: 4 cores, 16GB RAM, 2xSSD mirror para OS
2. Configurar jobs de backup diarios con retención: 7 daily, 4 weekly, 3 monthly
3. Configurar client-side encryption
4. Configurar prune + garbage collection
5. Replication remota a un segundo PBS (futuro, para 3-2-1)

**Fase 4 — Monitoreo (1-2 sesiones)**:
1. Desplegar Prometheus + Grafana + PVE Exporter en el nodo DC+Observability
   - Opción: Docker Compose para gestión simple
   - Dashboard Grafana ID 10347
2. Configurar Node Exporter en ambos nodos PVE
3. Configurar alertas:
   - Quorum status (pvecm status)
   - ZFS pool health (zpool status)
   - Disk SMART health
   - Backup failures
   - Disk usage > 80%
4. Proxmox Metric Server → InfluxDB o directamente OTLP (PVE 9+)

**Fase 5 — Optimización (continua)**:
1. **CPU**: cambiar tipo CPU en VMs de `kvm64` a `host` (si no hay migración cross-generacional)
2. **Memory ballooning**: deshabilitar para VMs críticas (DBs, servicios core)
3. **NUMA**: habilitar NUMA en VMs con >4 vCPUs o >16GB RAM en hardware dual-socket
4. **Oversubscription CPU**: mantener ratio vCPU:pCPU <= 4:1
5. **I/O**: usar VirtIO SCSI Single con IO Thread y Discard
6. **Power management**: configurar CPU governor a `performance` para cores activos

### Migración desde Estado Actual

1. **Si los nodos NO están clusterizados**:
   - Elegir un nodo como primario (recomendado: pve-desa)
   - `pvecm create <cluster-name>` en primario
   - `pvecm add <PRIMARY_IP>` en secundario
   - Configurar QDevice inmediatamente

2. **Si los nodos YA están clusterizados**:
   - Verificar quorum con `pvecm status`
   - Si usa `two_node: 1` en corosync.conf, migrar a QDevice
   - Verificar configuración de red del cluster

3. **Riesgo de migración**: no hay migración destructiva de datos -- ZFS pools locales no se tocan. La replicación es adicional.

## Risks

### QUORUM — Risk: CRITICAL
- **Sin QDevice**, la pérdida de un nodo deja al otro sin quorum → todas las operaciones de cluster se bloquean
- La configuración `two_node: 1` existe pero puede causar split-brain si los nodos pierden comunicación
- **Solución**: instalar QDevice ANTES de declarar el cluster productivo
- Probar escenario de fallo: desconectar un nodo y verificar quorum

### STORAGE — Risk: MEDIUM
- ZFS replicación es asíncrona → RPO de minutos, no segundos
- Si ambos nodos fallan simultáneamente, la data más reciente puede perderse
- **Mitigación**: PBS con backups diarios cerrar la brecha
- ZFS ARC puede consumir 50% de RAM → monitorear presión de memoria

### CAPACITY — Risk: MEDIUM
- Si un nodo falla, el otro debe correr TODAS las VMs
- **Calcular**: suma de RAM asignada a VMs vs RAM física del nodo sobreviviente
- Oversubscription de RAM sin headroom causa swapping brutal
- **Regla**: mantener 25-30% de headroom de RAM en cada nodo

### NETWORK — Risk: MEDIUM
- Corosync es sensible a latencia >5ms y jitter
- Si storage y cluster comparten el mismo switch, una VM ruidosa puede afectar quorum
- **Solución**: VLAN separada para Corosync, o idealmente NIC dedicada
- Probar latencia: `ping -c 100 <other-node-ip>` y verificar <1ms

### BACKUP — Risk: HIGH
- **No hay backup conocido** en este momento
- Sin PBS, cualquier falla de disco = pérdida de datos
- Instalar PBS es la prioridad MÁS ALTA después del quorum

### Ceph — Risk: NOT APPLICABLE (pero documentado)
- Ceph en 2 nodos no funciona. Quien lo intente va a sufrir.
- Si en el futuro se agrega un 3er nodo, re-evaluar.
- Para 2 nodos, ZFS + replicación es el estándar de la industria y la recomendación oficial de Proxmox.

## Ready for Proposal
**Yes** — La arquitectura está clara. Recomiendo siguiente paso: `sdd-propose` para formalizar el cambio "Cluster Proxmox — QDevice + ZFS + PBS + Monitoreo" con alcance, entregables y plan de rollback.

### Resumen de Prioridades

| Prioridad | Acción | Dependencia | Esfuerzo |
|-----------|--------|-------------|----------|
| 🔴 P0 | Auditoría de estado actual | Ninguna | 1 sesión |
| 🔴 P0 | QDevice para quorum | Cluster existente | 30 min |
| 🔴 P0 | PBS para backups | N/A | 1-2 sesiones |
| 🟡 P1 | ZFS pools + replicación | QDevice + auditoría | 2-3 sesiones |
| 🟡 P1 | Monitoreo (Prometheus+Grafana) | PBS instalado | 1-2 sesiones |
| 🟢 P2 | Corosync dual link redundancy | Cluster configurado | 30 min |
| 🟢 P2 | Optimización VMs (CPU, NUMA, balloon) | Post-implementación | Continua |
