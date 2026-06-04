# Tareas Completadas

> Registro de tareas finalizadas del cambio identity-management.

## Fase 0 — Verificación y Diagnóstico ✅

| Fecha | Tarea | Resultado |
|-------|-------|-----------|
| 2026-05-29 | F0.1 | ✅ pve-ad: PVE 9.1.1, 45GB libres, 5 CTs |
| 2026-05-29 | F0.2 | ✅ VM-DC1 (101) confirmado. DC-VM eliminado. |
| 2026-05-29 | F0.3 | ✅ DNS Server instalado. Sin zona de dominio. |
| 2026-05-29 | F0.4 | ✅ SSH + Chocolatey OK |
| 2026-05-29 | F0.5 | ✅ Licencia: Evaluation → ServerStandard. Shutdown resuelto. |
| 2026-05-29 | F0.6 | ✅ Documentado |

## Setup AD — Dominio GDC01.local ✅

| Tarea | Resultado |
|-------|-----------|
| Renombrar VM | ✅ WIN-J3DVKIHAGD2 → **DC1-GIDAS** |
| Promocionar AD DS | ✅ `Install-ADDSForest -DomainName GDC01.local` |
| DNS | ✅ Zona GDC01.local + _msdcs |
| FSMO | ✅ Los 5 roles en DC1-GIDAS |
| Grupos AD | ✅ gidas-admins, gidas-pve-admin, gidas-pve-viewer |

## Fase 1 — FreeIPA Deployment ✅

| Tarea | Resultado |
|-------|-----------|
| F1.1 | ✅ Linked clone VM 210 en pve-desa04 |
| F1.2-F1.4 | ✅ Backup → relay → restore en pve-ad |
| F1.5 IP | ✅ 192.168.1.118/24 estática |
| F1.6 Hostname | ✅ `ipa-gidas.gdc01.local` |
| F1.7 FreeIPA | ✅ Rocky Linux 10.1 + FreeIPA 4.13.1 |
| F1.8 DNS | ✅ Bind + forwarder a AD (192.168.1.117) |

## Fase 2 — Trust AD ↔ FreeIPA ✅

| Tarea | Resultado |
|-------|-----------|
| Trust establecido | ✅ `ipa trust-add --type=ad gdc01.local` |
| Estado | ✅ Established and verified |
| FreeIPA Realm | IPA.GDC01.LOCAL |
| AD Realm | GDC01.LOCAL |

## Fase 3 — Integración PVE ✅

| Tarea | Resultado |
|-------|-----------|
| F3.1 Realm AD | ✅ Agregado en pve-ad + cluster |
| F3.2 LDAPS | ⚠️ Puerto 389 sin TLS (por ahora) |
| F3.3 ACLs | ✅ gidas-admins→Admin, gidas-pve-admin→PVEAdmin, gidas-pve-viewer→PVEAuditor |
| F3.4 AC4 | ✅ Login AD exitoso en pve-ad y cluster |

## Fase 4 — SSSD + HBAC (parcial) ✅

| Tarea | Resultado |
|-------|-----------|
| F4.1 SSSD en PVE | ✅ pve-ad (SSSD 2.10.1) + pve-desa01 (SSSD 2.8.2) |
| F4.3 sssd.conf | ✅ Template AD provider |
| F4.4 AD join | ✅ pve-ad + pve-desa01 joined via adcli |
| F4.7 AC3 | ✅ `getent passwd administrator` funciona |
| F4.2 Containers | ⏳ Pendiente |
| F4.5 HBAC rules | ⏳ Pendiente |
| F4.6 Sudo rules | ⏳ Pendiente |

## Progreso General

| Fase | Estado | Tareas |
|------|--------|--------|
| ✅ Fase 0 | COMPLETA | 6/6 |
| ✅ Setup AD | COMPLETO | — |
| ✅ Fase 1 | COMPLETA | 8/8 |
| ✅ Fase 2 | COMPLETA | 4/4 |
| ✅ Fase 3 | COMPLETA | 4/4 |
| 🔶 **Fase 4** | **PARCIAL** | **3/10** |
| ⏳ Fase 5 | Pendiente | 0/6 |
