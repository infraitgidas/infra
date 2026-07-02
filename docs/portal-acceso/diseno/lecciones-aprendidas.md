# Lecciones Aprendidas — Portal de Acceso GIDAS

> **Feature**: Portal de Acceso (Feature #6)
> **Rama**: `feat/portal-access-remoto`
> **Fecha**: 2026-07-02

---

## 1. Resumen

Antes de llegar a la solución actual, se evaluaron e implementaron dos aproximaciones que no cubrieron las necesidades del grupo GIDAS. Este documento registra qué se probó, por qué no funcionó, y qué aprendimos.

---

## 2. Intento 1: Authentik (IdP + SSO)

### Período
2026-06-13 → 2026-07-01

### Stack
- Authentik 2026.5.3 (Docker Compose: server + worker + postgres + redis)
- SSO vía OIDC/OAuth para GitLab, Grafana, Redmine
- LDAP → AD GDC01 como fuente de identidad

### Lo que se logró
- Authentik desplegado y operativo en GitLab VM (192.168.1.41:9000)
- 17 usuarios AD importados (con workaround vía `ak shell`)
- Providers OIDC/OAuth creados para GitLab, Grafana, Redmine
- SSO GitLab configurado y funcional

### Por qué no funcionó
| Problema | Detalle |
|----------|---------|
| **LDAP sync inestable** | El worker Dramatiq de Authentik no sincronizaba correctamente. Hubo que hacer sync manual vía `ak shell`. |
| **SSO incompleto** | Cada herramienta implementaba OIDC/OAuth de forma distinta. Redmine necesitaba un plugin externo. Proxmox no soporta OIDC. |
| **Complejidad operativa** | Authentik requería 4 containers, actualizaciones de seguridad, migraciones de DB, monitoreo de workers. |
| **Single point of failure** | Si Authentik caía, todas las herramientas quedaban inaccesibles vía SSO. |
| **Mantenimiento** | Updates semanales, riesgo de breaking changes, configuración vía UI que no es versionable. |

### Aprendizaje
> **Un IdP (OIDC/SAML) agrega complejidad desproporcionada para 17 usuarios y 6 herramientas.** El SSO promete comodidad pero el costo de configuración y mantenimiento supera al beneficio cuando las herramientas ya autentican contra AD directamente.

---

## 3. Intento 2: Homer (Dashboard estático)

### Período
2026-07-01 → 2026-07-02

### Stack
- Homer v26.4.2 (Vue.js SPA estático servido por nginx)
- CT Rocky Linux 9 (208) en pve-desa04
- Sin backend, sin base de datos

### Lo que se logró
- CT 208 creado y operativo (192.168.1.43)
- Homer instalado y sirviendo dashboard con 11 cards
- DNS MikroTik `portal.gidas.local → 192.168.1.43`

### Por qué no funcionó
| Problema | Detalle |
|----------|---------|
| **Sin autenticación** | Homer NO tiene login. Es solo un panel de links. |
| **Sin RBAC** | No puede filtrar herramientas según el grupo AD del usuario. Todos ven todo. |
| **No resuelve el problema** | El usuario necesita un portal que controle QUIÉN ve QUÉ. Homer es solo HTML estático. |

### Aprendizaje
> **Un dashboard sin autenticación no es un portal.** El core del problema no es mostrar links, es controlar el acceso según el perfil del usuario.

---

## 4. Análisis de la Necesidad Real

### Requisitos funcionales (RF)
| ID | Requisito | Prioridad |
|----|-----------|-----------|
| RF-1 | El usuario debe autenticarse con credenciales de AD (GDC01) | Alta |
| RF-2 | El dashboard debe mostrar solo las herramientas que el usuario puede usar según sus grupos AD | Alta |
| RF-3 | Los links deben ser configurables vía archivo YAML (sin código) | Alta |
| RF-4 | El mapeo grupos → herramientas debe ser configurable vía YAML | Alta |
| RF-5 | Debe poder agregarse una nueva herramienta editando solo el YAML | Media |

### Requisitos no funcionales (RNF)
| ID | Requisito | Prioridad |
|----|-----------|-----------|
| RNF-1 | Sin base de datos — toda la configuración en archivos YAML | Alta |
| RNF-2 | Consumo de recursos < 256MB RAM, 0.5 vCPU | Alta |
| RNF-3 | Sin dependencia de servicios externos (ni IdP, ni Redis, ni K8s) | Alta |
| RNF-4 | Tiempo de deploy < 10 minutos desde CT limpio | Alta |
| RNF-5 | Mantenimiento mínimo — un binario o container Python | Media |

---

## 5. Cambio de Estrategia

| Aspecto | Antes (Authentik + Homer) | Ahora (Portal custom) |
|---------|--------------------------|----------------------|
| **Autenticación** | IdP externo (OIDC/SAML) | Directa contra AD (LDAP bind) |
| **Autorización** | Inexistente o delegada al IdP | Por grupo AD (memberOf) |
| **Dashboard** | Estático (Homer) | Server-side rendering con Jinja2 |
| **Estado** | JWT en IdP | JWT propio (cookie firmada) |
| **Configuración** | UI web + secrets | YAML versionable en git |
| **Complejidad** | 4 containers + CT | 1 container Python + CT |
| **Deploy** | Docker Compose + secrets | Docker o directo con systemd |

---

## 6. Conclusión

La solución correcta para GIDAS no es un IdP estándar (Authentik, Keycloak) ni un dashboard estático (Homer). Es una **aplicación web hecha a medida** que:

1. Valida contra AD (como ya hacen Redmine y GitLab)
2. Filtra herramientas según grupos AD del usuario
3. Se configura con YAML versionable
4. Corre en un container liviano sin dependencias externas

Esto no es "Not Invented Here" syndrome. Es reconocer que el problema de GIDAS no es lo suficientemente complejo como para justificar la sobrecarga de las herramientas estándar. Para 17 usuarios y 6 herramientas, una app de 200 líneas es más mantenible que Authentik + OIDC + plugins + base de datos + workers.
