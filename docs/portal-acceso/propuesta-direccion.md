# Propuesta: Portal de Acceso Unificado GIDAS

> Documento para presentación a dirección.
> Estado actual, logros, limitaciones y plan de evolución.

---

## 1. Resumen Ejecutivo

Se implementó un **Portal de Acceso Unificado** que permite a los miembros de GIDAS acceder a todas las herramientas del grupo (GitLab, Redmine, Grafana, etc.) desde cualquier lugar, sin necesidad de VPN ni configuración especial, usando solo el navegador.

Actualmente el sistema funciona y está operativo. Esta propuesta presenta los pasos siguientes para llevarlo a una solución estable y profesional.

### ¿Qué logramos?

| Logro | Detalle |
|-------|---------|
| **Login unificado** | Un solo usuario y contraseña (AD) para todas las herramientas |
| **Acceso remoto** | Desde cualquier lugar, sin VPN, sin configuraciones |
| **Sin depender de UTN** | El portal es independiente del sitio Drupal institucional |
| **Auto-gestionable** | El equipo GIDAS administra usuarios, accesos y herramientas |
| **Costo actual** | $0 (infraestructura existente + Cloudflare free) |

---

## 2. Situación Actual

### Cómo funciona hoy

```
Usuario → gidas.frlp.utn.edu.ar (Drupal)
              ↓ click en "Portal GIDAS"
       Tunnel Cloudflare → Portal GIDAS (login AD)
              ↓
       Dashboard con herramientas:
       ├── GitLab     ✅
       ├── Redmine    ✅  
       ├── Grafana    ✅
       └── [más herramientas se pueden agregar]
```

### Infraestructura utilizada

| Recurso | Propósito | Dependencia |
|---------|-----------|-------------|
| CT 208 (portal) | Servidor del portal y proxy | Propio (pve-desa04) |
| Cloudflare Tunnel | Conexión pública sin abrir puertos | Cloudflare (gratis) |
| Portal FastAPI | Login AD + dashboard | Propio (código en repo) |
| Drupal UTN | Punto de entrada público | UTN-FRLP |
| Active Directory | Usuarios y grupos | Propio (GDC01) |

### Tools funcionando

| Tool | Estado | Acceso |
|------|--------|--------|
| Portal GIDAS | ✅ | Via tunnel |
| GitLab | ✅ | Via tunnel |
| Redmine | ✅ | Via tunnel |
| Grafana | ✅ | Via tunnel |
| LibreNMS | ⚠️ | Via red interna |
| Vaultwarden | 🔒 | Solo red interna |

---

## 3. Limitaciones Actuales

### Técnicas

| Limitación | Impacto | Solución propuesta |
|-----------|---------|-------------------|
| **URL temporal** | La dirección del portal cambia si el servicio se reinicia | Migrar a Named Tunnel (Cloudflare gratis) |
| **Sin dominio propio** | La URL no es profesional (trycloudflare.com) | Comprar dominio gidas.com.ar (~$5/año) |
| **Sin respaldo** | Si CT 208 falla, no hay acceso | Evaluar redundancia |

### De Gestión

| Limitación | Impacto | Solución propuesta |
|-----------|---------|-------------------|
| **Twlingate personal** | Cuenta free limitada a 2-5 usuarios | Ya no se usa para el portal |
| **Drupal externo** | Dependemos de UTN para el punto de entrada | El portal es independiente, Drupal es solo un link |
| **Sin presupuesto** | No se pueden contratar servicios paga | Todas las soluciones propuestas son $0 o ~$5/año |

---

## 4. Plan de Evolución

### Fase 1 — Estabilización ($0)

| Tarea | Detalle | Beneficio |
|-------|---------|-----------|
| Crear cuenta Cloudflare | 2 minutos, gratis | URL estable del portal |
| Migrar a Named Tunnel | Configurar tunnel con cuenta | La URL ya no cambia nunca |

**Resultado**: Portal con URL fija. Sin cambios en la infraestructura actual.

### Fase 2 — Dominio Propio (~$5/año)

| Tarea | Detalle | Beneficio |
|-------|---------|-----------|
| Comprar gidas.com.ar | nic.ar, renovación anual | URL profesional |
| Conectar a Cloudflare | DNS gestionado por Cloudflare | portal.gidas.com.ar |

**Resultado**: El portal accesible desde `https://portal.gidas.com.ar`.

### Fase 3 — Seguridad ($0)

| Tarea | Detalle | Beneficio |
|-------|---------|-----------|
| Cloudflare Zero Trust | Autenticación en el tunnel | Solo miembros GIDAS acceden |
| Hasta 50 usuarios gratis | Login con Google/GitHub/email | Sin VPN, sin configuraciones |

**Resultado**: Acceso seguro sin exponer las herramientas a internet.

---

## 5. Costos

| Concepto | Hoy | Con el plan |
|----------|-----|-------------|
| **Infraestructura** | $0 | $0 |
| **Cloudflare** | $0 | $0 |
| **Dominio** | — | ~$5/año |
| **Mantenimiento** | 0 hs/semana | 0 hs/semana |
| **Total** | **$0** | **~$5/año** |

> No hay costos recurrentes significativos. Todo el software es open source
> y la infraestructura corre en servidores existentes del grupo.

---

## 6. Próximos Pasos

| Paso | Responsable | Tiempo |
|------|-------------|--------|
| 1. Aprobación de la propuesta | Dirección | — |
| 2. Crear cuenta Cloudflare | Administrador del portal | 2 minutos |
| 3. Migrar a Named Tunnel | Administrador del portal | 30 minutos |
| 4. Evaluar compra de dominio | Dirección | — |
| 5. Configurar autenticación | Administrador del portal | 30 minutos |

---

## 7. Preguntas Frecuentes

### ¿Es seguro?
Sí. Todo el tráfico viaja cifrado (HTTPS). No se abren puertos en el firewall. Las herramientas internas no se exponen directamente.

### ¿Dependemos de alguna empresa?
Cloudflare Tunnel es gratuito y no requiere tarjeta de crédito. Si en el futuro decidiéramos no usarlo más, el portal sigue funcionando en la red local sin cambios.

### ¿Qué pasa si Cloudflare deja de funcionar?
El portal sigue accesible en la red local (192.168.1.43) como siempre. Solo se pierde el acceso remoto.

### ¿Podemos agregar más herramientas?
Sí. Cada nueva herramienta se agrega en minutos configurando el proxy y el dashboard del portal.

---

## 8. Resumen para la Decisión

```
Inversión requerida:      ~$5/año (solo si se compra dominio)
Mantenimiento:            Cero
Dependencias externas:    Cloudflare (gratis, sin compromiso)
Beneficio inmediato:      Acceso remoto sin VPN para todo el grupo
Escalabilidad:            Ilimitada (solo depende de recursos propios)
```

---

*Documento: 2026-07-03 — Próxima actualización post-aprobación*
