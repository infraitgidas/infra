# proxmox/network — Especificación

## Propósito

Eliminar la red plana del cluster y establecer segmentación VLAN para Corosync, redundancia de enlaces en el anillo de quorum, y bonding en nodos con múltiples NICs disponibles.

## Requisitos

### Requisito: VLAN dedicada para Corosync

El tráfico de Corosync DEBE circular por una VLAN separada del tráfico de datos.

#### Escenario: Configuración de VLAN 10 en interfaces

- DADO un nodo del cluster con interfaz de red disponible
- CUANDO se configura la red del nodo
- ENTONCES se DEBE crear una interfaz VLAN 10 para tráfico de cluster
- Y el tráfico de datos DEBE permanecer en la VLAN nativa o distinta

### Requisito: Link redundante en corosync.conf

El anillo de Corosync DEBE tener un link1 redundante para tolerar fallos de NIC.

#### Escenario: Segundo link configurado

- DADO el archivo `/etc/pve/corosync.conf`
- CUANDO se verifica la configuración del anillo
- ENTONCES DEBE existir una sección `link` con `linknumber=1` apuntando a la VLAN 10
- Y el tráfico DEBE conmutar al link1 si el link0 falla

### Requisito: Bonding LACP en pve-desa04

El nodo pve-desa04 DEBE utilizar bonding modo LACP para agregar sus 4 NICs.

#### Escenario: Bond activo con LACP

- DADO pve-desa04 con 4 interfaces físicas
- CUANDO se configura `/etc/network/interfaces`
- ENTONCES las 4 NICs DEBEN agruparse en un bond modo 802.3ad (LACP)
- Y el switch DEBE tener el LACP configurado en los puertos correspondientes

### Requisito: Firewall de cluster con reglas por segmento

El firewall del cluster DEBE tener reglas diferenciadas por segmento de red.

#### Escenario: Reglas para tráfico de cluster

- DADO el firewall de cluster habilitado en `/etc/pve/firewall/`
- CUANDO se define una regla para la VLAN 10
- ENTONCES solo el tráfico Corosync DEBE estar permitido en esa VLAN
- Y el tráfico no autorizado DEBE ser denegado

#### Escenario: Reglas para tráfico de gestión

- DADO una IP de gestión en el cluster
- CUANDO se define el segmento de management
- ENTONCES el acceso SSH y HTTPS DEBE estar permitido solo desde IPs autorizadas
