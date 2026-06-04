VM-DC1 → DC1-GIDAS (192.168.1.117)
Etapa	Estado
🔧 Hostname	✅ DC1-GIDAS
💾 Licencia	✅ ServerStandard (KMS GVLK) — no más shutdown
🏛️ AD DS	✅ Promocionado — GDC01.local
🌐 DNS	✅ Zona GDC01.local + _msdcs.GDC01.local
🔑 Kerberos	✅ KDC Running
🐹 Chocolatey	✅ v2.7.2
🔐 DSRM Password	Gidas.DSMR.2026!

✅ Estado del Proyecto Identity Management
Fase 0 — Verificación ✅
Componente	Estado
pve-ad	✅ PVE 9.1.1, 5 CTs
VM-DC1 → DC1-GIDAS	✅ Renombrada, AD DS promocionado
Licencia Windows	✅ Evaluation → ServerStandard (KMS GVLK)
Hostname	✅ DC1-GIDAS
Dominio AD: GDC01.local (192.168.1.117) ✅
Servicio	Estado
AD DS (NTDS)	✅ Running
DNS Server	✅ Zona GDC01.local
Kerberos (KDC)	✅ Running
DHCP (192.168.7.0/24)	✅ Scope existente
Fase 1 — FreeIPA Deployment ✅
Tarea	Estado
Template clonado	✅ Linked clone en pve-desa04
Backup vzdump	✅ 4.69GB
Transferencia	✅ 5GB vía SD-WAN relay
VM creada en pve-ad	✅ VM 102 ipa-gidas
Disco importado	✅ 32GB en local-lvm
EFI disk	✅ Agregada (UEFI OVMF)
IP estática	✅ 192.168.1.118/24
FreeIPA Server: ipa.gdc01.local (192.168.1.118) ✅
Componente	Estado
SO	Rocky Linux 10.1
FreeIPA	✅ 4.13.1 instalado
Realm	✅ IPA.GDC01.LOCAL
DNS (Bind)	✅ Forwarding a AD (1.117)
CA (Dogtag)	✅ Self-signed
AD Trust	✅ Established and verified
Contraseñas
Servicio	Usuario	Password
AD (VM-DC1)	Administrator	hlvs.2025
AD DSRM	—	Gidas.DSMR.2026!
FreeIPA admin	admin	Gidas.Admin.2026!
FreeIPA DM	—	Gidas.DM.2026!
FreeIPA VM	infra	hlvs.2025