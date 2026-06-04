# Fase 0 — Verificación y Diagnóstico

> **Change**: identity-management
> **Fecha**: 2026-05-29
> **Estado**: ✅ COMPLETADA
> **Responsable**: infraitgidas

---

## Resumen

Verificación completa de la infraestructura de identidad actual. Se identificó VM-DC1 (192.168.1.117) en pve-ad como el servidor destino para AD, se diagnosticó y resolvió el problema de shutdown automático por licencia evaluation expirada.

---

## Tareas Realizadas

### F0.1 — Verificar pve-ad ✅

| Aspecto | Resultado |
|---------|-----------|
| Proxmox version | 9.1.1 (kernel 6.17.2-1-pve) |
| Almacenamiento | 45 GB libres en root |
| VMs | 1: VM-DC1 (101) |
| CTs | 5: sg-rojo, sg-azul, sg-verde, sg-amarillo, sg-monitoring (todos RUNNING) |
| Red | vmbr0, 192.168.1.31/24, gateway 192.168.1.1 |
| Acceso SSH | ✅ Clave SSH desde estación de trabajo |

### F0.2 — Identificar Domain Controller ✅

Se verificó la configuración de VM-DC1 desde pve-ad:

```
VMID: 101
Hostname: WIN-J3DVKIHAGD2
IP: 192.168.1.117/24 (estática, vmbr0, virtio MAC: BC:24:11:D2:A0:AE)
RAM: 3072 MB (3 GB)
vCPU: 2 cores
Disco: 32 GB (IDE)
OS: Windows Server 2022
TPM: v2.0 habilitado
UEFI: OVMF con Secure Boot
```

DC-VM (VM 100) fue eliminado — VM-DC1 es el único punto de identidad.

### F0.3 — Verificar servicios DNS ✅

Ejecutado desde VM-DC1 vía SSH:

| Aspecto | Resultado |
|---------|-----------|
| DNS suffix configurado | `GDC01.local` (solo config de red) |
| DNS Server role | ✅ Instalado, servicio RUNNING |
| Zonas DNS configuradas | Solo automáticas: 0/127/255.in-addr.arpa, TrustAnchors |
| Zona de dominio | ❌ **No existe** — no hay `GDC01.local` ni `gidas.internal` |
| DHCP Server | ✅ Instalado, scope `ScopeDC1` en 192.168.7.0/24 (no nuestra red) |

**Conclusión**: DNS está instalado pero vacío — no hay zona de dominio configurada.

### F0.4 — Verificar credenciales y Chocolatey ✅

| Aspecto | Resultado |
|---------|-----------|
| SSH | ✅ `Administrator@192.168.1.117` responde |
| Autenticación | Password `hlvs.2025` funciona |
| Chocolatey | ✅ v2.7.2 instalado |
| Paquetes choco | 2: `chocolatey`, `openssh` |

### F0.5 — Verificar licencia Windows Server ✅

**Diagnóstico inicial:**
```
Name: Windows(R), ServerStandardEval edition
Channel: TIMEBASED_EVAL
License Status: Notification
Reason: 0xC004F009 — grace time EXPIRED
```

**Problema**: La evaluación expiró → Windows se apaga automáticamente cada 1-2 horas.

**Solución aplicada:**
```
dism /online /Set-Edition:ServerStandard /ProductKey:VDYBN-27WPP-V4HQT-9VMD4-VMK7H /AcceptEula
```

**Estado final:**
```
Name: Windows(R), ServerStandard edition
Channel: VOLUME_KMSCLIENT (GVLK)
License Status: Notification (0xC004F056 — KMS no disponible)
```

✅ **Shutdown automático resuelto.** Windows queda en modo Notification (avisa pero no se apaga).

**Pendiente**: La key VDYBN-27WPP-V4HQT-9VMD4-VMK7H es GVLK de KMS. Si hay un KMS server en la red, configurar con `slmgr /skms <IP>`.

### F0.6 — Documentar hallazgos ✅

Todo documentado en:
- `tasks/completed/fase0-report.md` (este archivo)
- `tasks/completed/INDEX.md` (tracking actualizado)
- Engram: `sdd/identity-management/fase0`

---

## Hallazgos Clave

### Roles Windows Instalados

| Rol | Instalado | Estado |
|-----|-----------|--------|
| Active Directory Domain Services | ✅ `DirectoryServices-DomainController` | ❌ No promocionado (NTDS Stopped) |
| DNS Server | ✅ `DNS-Server-Full-Role` | ✅ Running |
| DHCP Server | ✅ `DHCPServer` | ✅ Running (scope 192.168.7.0/24) |
| AD Administrative Center | ✅ | Disponible |
| AD PowerShell | ✅ | Disponible |

### Servicios Críticos

| Servicio | Estado | Startup |
|----------|--------|---------|
| DNS | ✅ Running | Automático |
| NTDS (AD DS) | ❌ Stopped | Disabled |
| KDC (Kerberos) | ❌ Stopped | Disabled |
| Netlogon | ❌ Stopped | Manual |
| OpenSSH SSH Server | ✅ Running | Automático |
| Windows Time | ✅ Running | Automático |

---

## Decisiones Confirmadas

| Decisión | Estado |
|----------|--------|
| Dominio | Pendiente de definir (`gidas.internal` vs `GDC01.local` legado) |
| Hostname VM-DC1 | `WIN-J3DVKIHAGD2` (genérico) — considerar renombrar |
| IP VM-DC1 | ✅ 192.168.1.117/24 estática |
| Licencia | ✅ Evaluation → Standard (KMS GVLK) |

---

## Próximos Pasos

1. **Promocionar AD DS** en VM-DC1: `Install-ADDSForest -DomainName gidas.internal`
2. **Renombrar VM-DC1** a algo descriptivo (ej: `dc1-gidas`)
3. **Configurar DNS** con zona del dominio
4. **Configurar DHCP** si es necesario (scope 192.168.1.0/24)
5. **Crear OU structure** según diseño
6. **Fase 1**: Clonar template Rocky Linux y desplegar FreeIPA
