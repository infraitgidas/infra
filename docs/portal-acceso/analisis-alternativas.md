# Portal de Acceso Unificado GIDAS — Análisis de Alternativas

> **Contexto**: Proveer a los miembros de GIDAS un punto único de acceso (portal) a todas las herramientas del grupo, con autenticación unificada, desde internet y LAN. Herramientas actuales: Redmine, GitLab, Proxmox VE, Grafana, futuras herramientas.
>
> **Branch**: `feat/portal-access-remoto`
> **Fecha**: 2026-06-13

---

## Resumen Ejecutivo

| Criterio | Valor |
|----------|-------|
| Usuarios | ~17 miembros GIDAS (Dirección, Coordinadores, Becarios) |
| Fuente de identidad | Active Directory `GDC01.local` (ya creado y poblado) |
| Herramientas actuales | Redmine, GitLab, Proxmox, Grafana, AD dashboard |
| Acceso | Internet + LAN (sin VPN obligatoria) |
| Presupuesto | $0 — open source / self-hosted |
| Restricción | Mínima complejidad operativa |

---

## Escenario Ideal (a donde vamos)

```
                    ┌─────────────────┐
                    │   Portal Único  │
                    │  (login con AD) │
                    └────────┬────────┘
                             │
              ┌──────────────┼──────────────┐
              │              │              │
              ▼              ▼              ▼
        ┌──────────┐  ┌──────────┐  ┌──────────┐
        │ Redmine  │  │  GitLab  │  │ Grafana  │  ...
        │  (SSO)   │  │  (SSO)   │  │  (SSO)   │
        └──────────┘  └──────────┘  └──────────┘
```

El usuario:
1. Entra a `portal.gidas.local` (o `gidas.frlp.utn.edu.ar/portal`)
2. Se autentica con su usuario y contraseña de AD
3. Ve un dashboard con **cards** de cada herramienta disponible
4. Hace clic en una card y es redirigido a la herramienta **ya autenticado** (SSO)

---

## Alternativas Analizadas

### Alternativa A: Authentik — Identity Provider + Portal

**Open Source** — [goauthentik.io](https://goauthentik.io) — MIT License — 22k ⭐

**Qué es**: Identity Provider (IdP) moderno con soporte LDAP/AD, OIDC, SAML, y un dashboard de aplicaciones integrado.

**Cómo funciona para nuestro caso**:
- Se despliega en Docker Compose en una VM del cluster
- Se conecta al AD como fuente de identidad (LDAP)
- Ofrece un dashboard "My Applications" con cards para cada herramienta
- Actúa como SSO: cuando el usuario clickea una card, Authentik lo autentica vía OIDC/SAML contra la herramienta destino

**Lo que nos sirve**:
- ✅ Dashboard nativo con cards de aplicaciones
- ✅ Integración LDAP/AD directa (sin custom code)
- ✅ SSO vía OIDC/SAML para herramientas compatibles
- ✅ MFA/TOTP incorporado
- ✅ Self-service: cambio de password, perfil
- ✅ Fácil de agregar nuevas herramientas (configuración vía UI)

**Lo que no nos sirve**:
- ⚠️ No reemplaza el Drupal existente (son complementarios)
- ⚠️ Algunas herramientas requieren adaptación para SSO pleno

**Recursos**: ~1 vCPU / 1-2GB RAM (Docker Compose)
**Costo**: $0
**Dificultad**: Media

**SSO con herramientas actuales**:

| Herramienta | SSO vía Authentik |
|-------------|------------------|
| **GitLab** | ✅ OIDC nativo — soporte directo |
| **Redmine** | ⚠️ Vía plugin (openid_connect) o reverse proxy |
| **Grafana** | ✅ OAuth nativo — soporte directo (ya lo tiene) |
| **Proxmox VE** | ⚠️ Autenticación por ticket + PAM, requiere adaptador LDAP |
| **Herramientas futuras** | ✅ Cualquier app con OIDC/SAML/LDAP |

---

### Alternativa B: Keycloak — Identity Provider (CNCF)

**Open Source** — [keycloak.org](https://keycloak.org) — Apache 2.0 — CNCF Incubation

**Qué es**: El IdP open source más maduro del mercado. Similar a Authentik pero con más años de desarrollo.

**Cómo funciona**: Mismo concepto que Authentik — se conecta al AD, ofrece SSO, tiene account management console.

**Lo que nos sirve**:
- ✅ Integración LDAP/AD (User Federation)
- ✅ SSO vía OIDC/SAML maduro y probado
- ✅ MFA/TOTP, password policies
- ✅ Account console para usuarios
- ✅ Catálogo de aplicaciones (applications list)

**Lo que no nos sirve**:
- ❌ **No tiene dashboard visual con cards** por defecto (solo lista de apps)
- ⚠️ Más pesado que Authentik (Java/Quarkus)
- ⚠️ Requiere configuración más compleja

**Recursos**: ~1-2 vCPU / 1-2GB RAM (Java)
**Costo**: $0
**Dificultad**: Media-Alta

**Veredicto**: Más potente pero con peor experiencia de portal que Authentik. Recomendado solo si necesitamos features muy específicas (SAML, brokers complejos) que Authentik no tenga.

---

### Alternativa C: Drupal como Portal (con LDAP)

**Estado actual**: Drupal 7/10? en `gidas.frlp.utn.edu.ar` con usuarios propios (NO AD).

**Qué implica**:
- Instalar módulo LDAP en Drupal (`ldap_authentication`)
- Configurar Drupal para autenticar contra AD GDC01
- Crear una landing page con cards de herramientas (custom module o page builder)
- Los usuarios existentes de Drupal deberían migrarse o vincularse con AD

**Lo que nos sirve**:
- ✅ Ya existe, ya está publicado en internet
- ✅ Los usuarios conocen la URL
- ✅ Puede tener contenido informativo + portal en el mismo sitio
- ✅ Drupal soporta LDAP via módulos

**Lo que no nos sirve**:
- ❌ **NO hace SSO** — cada herramienta requiere login independiente
- ❌ Drupal no es un IdP, no puede emitir tokens OIDC/SAML
- ⚠️ Los usuarios de Drupal son diferentes a los de AD (habría que migrar)
- ⚠️ El sitio está en infraestructura de UTN (no controlamos el hosting)
- ⚠️ Drupal tiene overhead de mantenimiento (core + módulos + security updates)

**Veredicto**: Sirve como landing page informativa + redirect, pero **no resuelve el SSO**. El usuario tendría que loguearse en Drupal Y luego en cada herramienta.

---

### Alternativa D: Homer / Dashy + Authelia (Auth Proxy)

| Componente | Rol | Costo |
|-----------|-----|-------|
| **Authelia** | Auth proxy — intercepta requests, pide login LDAP | $0 |
| **Homer / Dashy** | Dashboard estático con cards — sirve HTML+CSS+JS | $0 |
| **nginx/caddy** | Reverse proxy que combina ambos | $0 |

**Cómo funciona**:
```
Usuario → nginx → Authelia (pide login LDAP) → Homer (dashboard con cards)
                → nginx → Authelia (verifica sesión) → GitLab/Redmine/Grafana
```

**Lo que nos sirve**:
- ✅ Cards visuales con Homer/Dashy
- ✅ Autenticación LDAP/AD con Authelia
- ✅ Liviano (Homer es estático, Authelia es Go)
- ✅ Fácil de agregar nuevas herramientas
- ✅ MFA/TOTP con Authelia

**Lo que no nos sirve**:
- ❌ **No hay SSO** (cada herramienta requiere su propio login, Authelia solo protege el acceso)
- ❌ Doble autenticación: Authelia + login de la herramienta
- ⚠️ Más componentes que mantener

**Veredicto**: Solución viable solo como portal de acceso + protección por firewall, pero **no resuelve el SSO** entre herramientas.

---

### Alternativa E: Estrategia Híbrida (RECOMENDADA)

Combinar Drupal (cara pública + información) + Authentik (portal transaccional + SSO).

```
                      ┌──────────────────────────────┐
  Mundo público       │  Drupal gidas.frlp.utn.edu.ar │
  (sin login)         │  - Quiénes somos              │
                      │  - Proyectos, Noticias         │
                      │  - Áreas de aplicación         │
                      └──────────┬───────────────────┘
                                 │ link
                                 ▼
                      ┌──────────────────────────────┐
  Portal GIDAS        │  Authentik portal.gidas.local │
  (requiere login)    │  - Login con AD               │
                      │  - Dashboard con cards         │
                      │  - SSO a herramientas          │
                      └──────────┬───────────────────┘
                                 │
              ┌──────────────────┼──────────────────┐
              ▼                  ▼                  ▼
        ┌──────────┐      ┌──────────┐      ┌──────────┐
        │ GitLab   │      │ Redmine  │      │ Grafana  │  ...
        │ (SSO vía │      │ (SSO vía │      │ (SSO vía │
        │  OIDC)   │      │  OIDC)   │      │  OAuth)  │
        └──────────┘      └──────────┘      └──────────┘
```

**Qué implica**:
1. Desplegar Authentik en Docker Compose en el cluster Proxmox
2. Conectar Authentik al AD (LDAP bind con infrait)
3. Configurar cada herramienta como "Application" en Authentik
4. Cada herramienta se configura con OIDC/SAML para aceptar tokens de Authentik
5. El portal queda en `portal.gidas.local` con DNS en MikroTik
6. Drupal puede tener un link "Acceso a Herramientas → portal.gidas.local"
7. Publicar portal.gidas.local a internet (DNAT/firewall)

---

## Tabla Comparativa

| Característica | Authentik | Keycloak | Drupal+LDAP | Homer+Authelia | Híbrida |
|---------------|-----------|----------|-------------|----------------|---------|
| Login con AD | ✅ | ✅ | ✅ | ✅ | ✅ |
| Dashboard con cards | ✅ nativo | ⚠️ básico | ✅ custom | ✅ nativo | ✅ |
| SSO entre herramientas | ✅ OIDC/SAML | ✅ OIDC/SAML | ❌ | ❌ | ✅ |
| MFA/TOTP | ✅ | ✅ | ⚠️ módulo | ✅ Authelia | ✅ |
| Self-service perfil | ✅ | ✅ | ✅ | ❌ | ✅ |
| Agregar herramienta nueva | ⚠️ config | ⚠️ config | ❌ custom code | ✅ Homer | ✅ |
| Conexión a AD existente | ✅ directa | ✅ directa | ⚠️ módulo | ✅ Authelia | ✅ |
| Recursos necesarios | 1GB RAM | 2GB RAM | existe | 256MB | 1GB |
| Dificultad | Media | Media-Alta | Media | Baja | Media |
| Mantenimiento | Bajo | Bajo | Medio | Medio | Bajo |
| Madurez | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐ |

---

## Recomendación

### Fase 1 (Corto Plazo — 1 semana)
**Desplegar Authentik como portal de acceso + SSO**

Pasos:
1. Crear VM/CT liviana (1 vCPU, 1.5GB RAM) en pve-desa04
2. Desplegar Authentik con Docker Compose
3. Conectar al AD (LDAP bind con `infrait`)
4. Configurar las primeras aplicaciones:
   - GitLab (OIDC) — soporte nativo
   - Grafana (OAuth) — soporte nativo
   - Redmine (vía plugin openid_connect o reverse proxy)
5. Agregar DNS en MikroTik: `portal.gidas.local`
6. Publicar a internet con HTTPS (DNAT + Let's Encrypt via Caddy)

### Fase 2 (Mediano Plazo — 1 mes)
**Integración total con SSO**

- Configurar SSO completo en Redmine, Proxmox, demás herramientas
- Migrar Drupal a usar Authentik como IdP (si la UTN lo permite)
- Agregar MFA para roles sensibles (Dirección, Coordinadores)

### Fase 3 (Largo Plazo)
**Evaluar Keycloak si Authentik no escala**

- Si necesitamos features que Authentik no tiene (ej: SAML complex broker, políticas avanzadas)
- Migrar a Keycloak como IdP (similar esfuerzo que Authentik, mismo modelo)

---

## Por qué Authentik y no Keycloak

1. **Dashboard nativo con cards** — Authentik tiene "My Applications" con íconos, tarjetas, search. Keycloak solo lista en texto.
2. **Menor consumo de recursos** — Authentik (Python + Go) vs Keycloak (Java/Quarkus).
3. **Configuración más intuitiva** — UI más moderna, menos opciones abrumadoras.
4. **Outposts** — Authentik puede deployar "outposts" (proxies ligeros) que se ponen delante de las apps para manejar autenticación sin modificar las apps. Esto es CLAVE para apps legacy.

Si en el futuro necesitamos SAML complejo o features enterprise que Authentik no tenga, Keycloak sigue siendo la alternativa.

---

## Próximos Pasos Propuestos

1. ✅ Aprobar esta recomendación
2. Crear spec SDD para el cambio "Portal de Acceso + SSO"
3. Desplegar Authentik en el cluster
4. Configurar integración con AD
5. Configurar cada herramienta como aplicación
6. Publicar y probar
