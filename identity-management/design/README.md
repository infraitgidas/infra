# Diseño — Gestión de Identidades Gidas

> Documento de diseño resumen. Para el diseño completo con diagramas, flujos y decisiones detalladas, ver `../sdd/design.md`.

## Arquitectura

**AD (VM-DC1) + FreeIPA cross-realm trust**

| Componente | IP | Propósito |
|-----------|-----|-----------|
| VM-DC1 (AD) | 192.168.1.117 | Domain Controller, fuente de verdad de usuarios |
| FreeIPA | 192.168.1.32 | IDM Linux, HBAC, sudo, DNS primario, CA |

## Decisiones Clave

| # | Decisión | Opción Elegida |
|---|----------|---------------|
| D1 | SO FreeIPA | Rocky Linux 10 (desde template VM 108) |
| D2 | Dominio | `gidas.internal` |
| D3 | Realm Kerberos | Separado: AD=`GIDAS.INTERNAL` |
| D4 | DNS forwarding | FreeIPA → AD → Internet |
| D5 | PVE realm | AD realm (login directo contra AD) |
| D6 | HBAC | FreeIPA HBAC (nativo Linux) |
| D7 | SSSD provider | `ipa` (integración más profunda) |

## Diagrama de Contexto

```
AD (VM-DC1) ◄── trust Kerberos ──► FreeIPA
                                        │
                        ┌───────────────┼───────────────┐
                    PVE Nodes       Containers      Servicios
                    (SSSD→IPA)     (SSSD→IPA)        Linux
                    PVE Realm AD     HBAC
```

## Enlaces

- [Diseño detallado (SDD)](../sdd/design.md) — diagramas de secuencia, configuraciones, plan de rollback
- [Especificaciones](../sdd/specs.md) — requisitos, escenarios, criterios de aceptación
- [Propuesta](../proposal/proposal.md) — enfoques, justificación, plan inicial
- [Exploración](../sdd/exploration.md) — análisis del estado actual
