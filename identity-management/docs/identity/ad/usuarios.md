# Usuarios — Active Directory

> **Fuente**: `identity-management/docs/estructura-user-organizacion.md`
> **Última actualización**: 2026-06-11

## Convención de Nombres

| Atributo | Formato | Ejemplo |
|----------|---------|---------|
| sAMAccountName | Primero + Inicial segundo + Apellido (lowercase) | `lnahuel`, `aalvarezf` |
| UPN | `sAMAccountName@GDC01.local` | `lnahuel@GDC01.local` |

---

## Direccion

| Usuario | sAMAccountName | Grupos | OU |
|---------|---------------|--------|----|
| Leopoldo Nahuel | lnahuel | G-Direccion, SRV-PVEAdmin | `OU=Direccion,DC=GDC01,DC=local` |
| Leandro Rocca | lrocca | G-Direccion, SRV-PVEAdmin | `OU=Direccion,DC=GDC01,DC=local` |

---

## Coordinadores (Direccion/Coordinadores)

| Usuario | sAMAccountName | Grupos | Proyecto |
|---------|---------------|--------|----------|
| Agustín Álvarez Ferrando | aalvarezf | G-Coordinadores | (a definir) |
| Maria de los Ángeles Bacigalupe | mbacigalupe | G-Coordinadores | (a definir) |
| Javier Ignacio Marchesini | jmarchesini | G-Coordinadores | (a definir) |
| Mirta Peñalva | mpenalva | G-Coordinadores | (a definir) |
| Zoe Quiroz | zquiroz | G-Coordinadores | (a definir) |
| Emanuel Rodriguez Rodriguez | errodriguez | G-Coordinadores, PROY-INFRAiT, G-IdentityAdmins | INFRAiT |

> Los coordinadores pertenecen a `OU=Coordinadores,OU=Direccion,DC=GDC01,DC=local`.
> El proyecto asignado se refleja agregando el grupo `PROY-*` correspondiente.

---

## Becarios

| Usuario | sAMAccountName | Grupos | OU |
|---------|---------------|--------|----|
| Rafael Cáceres Petckowicz | rcaceresp | G-Becarios | `OU=Becarios,DC=GDC01,DC=local` |
| Juan Ignacio Etcheverry | jetcheverry | G-Becarios | `OU=Becarios,DC=GDC01,DC=local` |
| Romeo Monfroglio | rmonfroglio | G-Becarios, PROY-INFRAiT | `OU=Becarios,DC=GDC01,DC=local` |
| Federico Blanco Cavallero | fblancocavallero | G-Becarios, PROY-INFRAiT | `OU=Becarios,DC=GDC01,DC=local` |
| Santiago Montanari | smontanari | G-Becarios, PROY-INFRAiT | `OU=Becarios,DC=GDC01,DC=local` |
| Tiago Ibañez | tiago.ibanez | G-Becarios, PROY-INFRAiT | `OU=Becarios,DC=GDC01,DC=local` |
| Cintia Valero | cvalero | G-Becarios | `OU=Becarios,DC=GDC01,DC=local` |

> Los becarios pueden pertenecer a múltiples proyectos (grupos `PROY-*`). Pendiente de asignación.

---

## ServiceAccounts

| Usuario | sAMAccountName | Grupos | OU |
|---------|---------------|--------|----|
| infrait | infrait | G-IdentityAdmins | `OU=ServiceAccounts,DC=GDC01,DC=local` |

> Cuenta de servicio para administración de identidad AD + FreeIPA (proyecto INFRAiT).

---

## Resumen

| OU | Cantidad |
|----|----------|
| Direccion | 2 |
| Direccion/Coordinadores | 6 |
| Becarios | 7 |
| ServiceAccounts | 1 |
| **Total** | **16** |
