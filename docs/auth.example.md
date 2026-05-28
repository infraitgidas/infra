# Proxmox — ejemplo de configuración

> Los valores reales están en `secrets/proxmox.yaml` encriptados con SOPS + age.
> Editarlos: `sops secrets/proxmox.yaml`

## cluster pve-desa
- ip: <ip_del_cluster>
- port: 8006
- user: root

## nodo DC + Observability
- ip: <ip_del_nodo_dc>
- port: 8006
- user: root
