# proxmox/storage-samba — Especificación

## Propósito

Proporcionar acceso CIFS/Samba a directorios compartidos del dataset shared-zfs/samba para usuarios de la red interna, permitiendo intercambio de archivos entre sistemas Windows y Linux sin acceso directo al cluster Proxmox.

## Requisitos

### Requisito: Export Samba desde shared-zfs

El dataset shared-zfs/samba DEBE exportarse vía Samba como recurso compartido.

#### Escenario: Recurso compartido operativo

- DADO el dataset shared-zfs/samba montado en pve-desa03
- CUANDO se configura Samba
- ENTONCES el recurso DEBE ser accesible vía `//pve-desa03/shared`
- Y DEBE usar SMB3 como protocolo mínimo

### Requisito: Autenticación y autorización

El acceso al recurso Samba DEBE estar autenticado y autorizado por usuario/grupo.

#### Escenario: Acceso autenticado

- DADO un usuario sin credenciales Samba
- CUANDO intenta acceder a `//pve-desa03/shared`
- ENTONCES el acceso DEBE ser denegado

#### Escenario: Permisos por grupo

- DADO un usuario autenticado miembro de un grupo autorizado (ej: `samba-users`)
- CUANDO accede al recurso compartido
- ENTONCES DEBE tener permisos de lectura/escritura según configuración del grupo
- Y los permisos DEBEN respetar la propiedad de archivos en ZFS

### Requisito: Montaje desde clientes Linux

Clientes Linux DEBEN poder montar el recurso CIFS mediante `mount.cifs`.

#### Escenario: Montaje con credenciales

- DADO un cliente Linux en la red interna
- CUANDO se monta `//pve-desa03/shared`
- ENTONCES DEBE usar SMB3, credenciales en archivo `/etc/samba/credentials`
- Y opciones: `vers=3.0,uid=<usuario>,gid=<grupo>,file_mode=0755,dir_mode=0755`

### Requisito: Aislamiento del storage Proxmox

El servicio Samba NO DEBE comprometer la disponibilidad del storage NFS ni del pool ZFS compartido.

#### Escenario: Samba con recursos limitados

- DADO pve-desa03 sirviendo NFS + Samba simultáneamente
- CUANDO hay alta carga de transferencia Samba
- ENTONCES el IO de NFS NO DEBE degradarse más de un 20%
- Y el ARC DEBE priorizar los datasets NFS sobre samba
