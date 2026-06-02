# cmdb Specification

## Purpose

NetBox como CMDB centralizada del Grupo Gidas. Modela servidores Proxmox, equipos Mikrotik, Directory Servers (AD/FreeIPA) y servicios (Redmine, GitLab, ITSM). Despliegue via Docker Compose con PostgreSQL + Redis.

## Requirements

### Requirement: NetBox Deploy

NetBox MUST desplegarse con Docker Compose usando PostgreSQL 15 + Redis 7. La instancia MUST ser accesible via HTTP en puerto 8000. Los datos MUST persistir en volúmenes Docker separados para DB y media.

| Property | Value |
|----------|-------|
| Stack | NetBox 4.x, PostgreSQL 15, Redis 7 |
| Deploy | Docker Compose oficial |
| Acceso | HTTP :8000, auth local |
| Storage | Volúmenes Docker separados |

#### Scenario: Deploy completo

- GIVEN una VM con Docker Engine + Compose instalados
- WHEN se ejecuta `docker compose up -d`
- THEN los containers netbox, postgres, redis y worker inician sin error
- AND la UI es accesible en `http://<host>:8000`

#### Scenario: Persistencia post-reinicio

- GIVEN NetBox corriendo con sites y devices cargados
- WHEN se ejecuta `docker compose down && docker compose up -d`
- THEN todos los datos previos están presentes en la UI

### Requirement: CI Modeling

NetBox MUST modelar Sites, Racks, Devices, Clusters, VirtualMachines, IPAM (prefixes/IPs), VLANs y Services. La jerarquía MUST ser Site → Rack → Device / Cluster → VirtualMachine.

#### Scenario: Alta de Site con Devices

- GIVEN un Site "GIDAS-DC1" creado en NetBox
- WHEN se registran 3 Devices (proxmox-01, mikrotik-core, directory-01) asignados al Site
- THEN cada Device aparece con estado Active y rol correcto

#### Scenario: IPAM con validación de Prefix

- GIVEN un Prefix 10.0.0.0/8 con VLAN 100
- WHEN se asigna una IP 10.0.1.1/24 a una interfaz
- THEN NetBox valida que la IP está dentro del Prefix padre

### Requirement: Proxmox Discovery

El sistema SHOULD descubrir nodos Proxmox, VMs, LXCs, interfaces, IPs y discos via API. El script MUST usar `proxmoxer` + NetBox API REST. Descubrimiento SHOULD ejecutarse semanalmente via cron.

#### Scenario: Sincronización de cluster

- GIVEN un cluster Proxmox con token API de lectura
- WHEN se ejecuta `cmdb/scripts/discover-proxmox.sh`
- THEN los nodos físicos se crean como Devices tipo "Server"
- AND las VMs/LXCs como VirtualMachines vinculadas al Cluster

#### Scenario: VM migrada entre nodos

- GIVEN una VM corriendo en proxmox-01
- WHEN la VM migra a proxmox-02 y se re-ejecuta discovery
- THEN NetBox actualiza el Cluster asignado de la VirtualMachine

### Requirement: Mikrotik Discovery

El sistema SHOULD descubrir equipos Mikrotik via API REST RouterOS. Cada equipo MUST registrarse como Device con interfaces, IPs y VLANs.

#### Scenario: Registro de router

- GIVEN un Mikrotik RB4011 con API REST y usuario de solo lectura
- WHEN se ejecuta `cmdb/scripts/discover-mikrotik.sh`
- THEN el router se crea como Device tipo "Router" con interfaces, IPs y VLANs

### Requirement: Directory Server Sync

Directory Servers (AD/FreeIPA) SHOULD importarse como Devices con rol "Directory Server". El script MUST consultar via LDAP.

#### Scenario: Importación de AD

- GIVEN un Domain Controller con consulta LDAP permitida
- WHEN se ejecuta `cmdb/scripts/sync-directory.sh`
- THEN el servidor se registra como Device con FQDN, OS y rol "Directory Server"

### Requirement: Maintenance

El sistema MUST tener scripts de backup (PostgreSQL dump + media) y restore documentado. Upgrade SHOULD probarse en staging antes de producción.

#### Scenario: Backup y restore exitoso

- GIVEN NetBox funcionando con datos
- WHEN se ejecuta `cmdb/scripts/backup.sh`
- THEN se genera dump PostgreSQL comprimido + copia de uploads
- WHEN se ejecuta `cmdb/scripts/restore.sh` con ese backup
- THEN NetBox restaura todos los datos sin pérdida

#### Scenario: Upgrade con staging

- GIVEN NetBox v4.0 en producción y v4.1 disponible
- WHEN se despliega v4.1 en staging y se validan scripts de discovery
- THEN si staging es exitoso se procede a producción
- AND los scripts de discovery se versionan contra la API target
