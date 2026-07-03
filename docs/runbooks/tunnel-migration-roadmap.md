# Roadmap: Migración del Tunnel a alternativas estables

> Plan de migración desde el Quick Tunnel (trycloudflare.com) actual
> hacia soluciones más estables y escalables para el portal GIDAS.
>
> **Estado actual**: Quick Tunnel (trycloudflare) — URL volátil, sin cuenta, $0
> **Objetivo**: Solución estable, con dominio propio o URL fija, escalable a más servicios y usuarios.

---

## 📊 Estado Actual vs. Alternativas

| Aspecto | Quick Tunnel (hoy) | Named Tunnel | + Dominio propio | + VPS |
|---------|-------------------|--------------|------------------|-------|
| **URL estable** | ❌ | ✅ | ✅ | ✅ |
| **Dominio propio** | ❌ | ❌ | ✅ | ✅ |
| **Sin cuenta externa** | ✅ | ❌ (Cloudflare) | ❌ | ✅ |
| **Control total** | ❌ | ❌ | ✅ | ✅ |
| **Costo** | $0 | $0 | ~$5/año | ~$5/mes |
| **Esfuerzo migración** | — | 30 min | 1 hora | 1 día |
| **Disponibilidad** | Sin garantía | Buena | Buena | Total |

---

## 🗺️ Fases de Migración

### Fase 0: Quick Tunnel (Actual) ✅

**Qué tenemos hoy**:
- `cloudflared` sin autenticación → URL `xxx.trycloudflare.com`
- Auto-update de Drupal con la URL actual
- nginx como reverse proxy en CT 208
- Portal + Grafana + GitLab + Redmine funcionando

**Limitaciones**:
- URL cambia al reiniciar el servicio
- Sin garantía de uptime
- No podemos usar dominio propio
- Sin analytics ni control de acceso

---

### Fase 1: Named Tunnel con Cloudflare 🎯 **(Recomendado - $0)**

**Objetivo**: URL estable sin depender de trycloudflare.

#### Pasos

```bash
# 1. Crear cuenta gratuita en https://dash.cloudflare.com/sign-up
#    (solo email + contraseña, 2 minutos)

# 2. En CT 208, autenticar cloudflared:
cloudflared tunnel login
# → Se abre un link para autorizar con la cuenta de Cloudflare

# 3. Crear el tunnel nombrado:
cloudflared tunnel create gidas-portal
# → Genera un ID único y credenciales

# 4. Verificar el tunnel:
cloudflared tunnel list
# → Debe mostrar: gidas-portal (ID: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)

# 5. Crear archivo de configuración:
mkdir -p ~/.cloudflared
cat > ~/.cloudflared/config.yml << EOF
tunnel: gidas-portal
credentials-file: /root/.cloudflared/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx.json
ingress:
  - hostname: tunnel-id.cfargotunnel.com
    service: http://127.0.0.1:80
  - service: http_status:404
EOF

# 6. Instalar como servicio systemd:
cloudflared service install

# 7. Iniciar:
systemctl start cloudflared
systemctl enable cloudflared
```

**Resultado**: 
- URL estable: `https://xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx.cfargotunnel.com`
- Ya no cambia al reiniciar
- Misma infraestructura, mismo nginx, mismo portal
- **Costo: $0**

#### Impacto en el sistema actual

| Componente | Cambio necesario |
|-----------|-----------------|
| auto-tunnel.py | ✅ Ya no se necesita (URL fija) |
| gidas-tunnel.service | ✅ Reemplazar por cloudflared service |
| Drupal (node/40) | ⚠️ Actualizar URL una sola vez (manual) |
| nginx CT 208 | ✅ Sin cambios |
| Portal config.yaml | ✅ Sin cambios |

---

### Fase 2: Dominio Propio 🎯 **(Recomendado - ~$5/año)**

**Objetivo**: URL profesional tipo `portal.gidas.com.ar` en vez de `xxx.cfargotunnel.com`.

#### Pasos

```bash
# 1. Comprar dominio
#    Opciones:
#    - nic.ar: gidas.com.ar (~$5/año, renovación anual)
#    - Namecheap: gidas.com (~$10/año)
#    - DuckDNS: gidas-portal.duckdns.org (GRATIS, subdominio)

# 2. Agregar dominio a Cloudflare:
#    Dashboard → Add Site → ingresar dominio
#    Cloudflare escanea los registros DNS existentes
#    Cambiar nameservers a los de Cloudflare

# 3. Crear registro DNS:
cloudflared tunnel route dns gidas-portal portal.gidas.com.ar

# 4. Actualizar config.yml del tunnel:
#    hostname: portal.gidas.com.ar

# 5. Actualizar página de Drupal con la nueva URL
```

**Resultado**:
- URL: `https://portal.gidas.com.ar`
- Con SSL automático de Cloudflare
- Con WAF, caching, analytics
- **Costo: ~$5/año** (el dominio)

#### Alternativa gratis: DuckDNS

```bash
# 1. Ir a https://duckdns.org
# 2. Crear cuenta con GitHub/Google/Reddit
# 3. Crear subdominio: gidas-portal.duckdns.org
# 4. Configurar CNAME a xxxxxxxx.cfargotunnel.com
```

**Costo: $0** — pero el dominio es `gidas-portal.duckdns.org`

---

### Fase 3: Cloudflare Zero Trust (Auth) 🛡️ **(Opcional - $0 hasta 50 usuarios)**

**Objetivo**: Agregar autenticación al acceso del tunnel.

#### Pasos

```bash
# 1. En Cloudflare Dashboard:
#    Zero Trust → Access → Applications → Add Application

# 2. Seleccionar "Self-hosted"
#    Domain: portal.gidas.com.ar
#    Policy: Allow con reglas:
#      - Emails: @frlp.utn.edu.ar
#      - O Google: gmail addresses específicos

# 3. Opcional: conectar proveedor de identidad:
#    - Google Workspace (gratis)
#    - GitHub (gratis)
#    - Microsoft AD (si integramos)
```

**Resultado**:
- Solo usuarios autenticados pueden acceder
- Sin VPN, sin Twingate
- Hasta 50 usuarios gratis
- **Costo: $0**

---

### Fase 4: VPS Dedicado 💻 **(Opcional - ~$5/mes)**

**Objetivo**: Control total de la infraestructura de proxy.

#### Pasos

```bash
# 1. Contratar VPS en DigitalOcean, Hetzner, o similar
#    Mínimo: 1 vCPU, 1GB RAM, $5-6/mes

# 2. Instalar nginx + Docker

# 3. Configurar WireGuard para conectar con red GIDAS:
#    - VPS → WireGuard → CT en pve-desa04
#    - El CT actúa como gateway a la red interna

# 4. Migrar config de nginx del CT 208 al VPS

# 5. Configurar DNS → VPS
```

**Arquitectura resultante**:
```
Usuario → portal.gidas.com.ar → VPS (nginx)
                                    ↓ WireGuard
                                CT gateway
                                    ↓
                            Servicios internos
```

**Costo: ~$5-6/mes**

---

## 📋 Roadmap Visual

```
Fase 0 ─── Hoy: Quick Tunnel (trycloudflare)
              │
              ▼
Fase 1 ─── Cuenta Cloudflare + Named Tunnel  [$0, 30 min]
              │
              ▼
Fase 2 ─── Dominio propio (gidas.com.ar)     [~$5/año, +1 hora]
              │
              ├── Opcional: DuckDNS           [$0, 15 min]
              │
              ▼
Fase 3 ─── Cloudflare Zero Trust (auth)     [$0, 30 min]
              │
              ▼
Fase 4 ─── VPS Dedicado                     [~$5/mes, 1 día]
```

---

## 📦 Resumen de Costos por Fase

| Fase | Descripción | Costo inicial | Costo recurrente | Tiempo |
|------|-----------|--------------|-----------------|--------|
| **0** | Quick Tunnel (actual) | $0 | $0 | — |
| **1** | Named Tunnel | $0 | $0/mes | 30 min |
| **2a** | Dominio .com.ar | ~$5 | ~$5/año | 1 hora |
| **2b** | DuckDNS (alternativa) | $0 | $0 | 15 min |
| **3** | Zero Trust Auth | $0 | $0/mes | 30 min |
| **4** | VPS dedicado | ~$5 | ~$5/mes | 1 día |

### Escenarios recomendados

| Perfil | Fases | Costo anual | Para qué |
|--------|-------|------------|----------|
| **Mínimo** | 0 + 1 | $0 | Probar, desarrollo |
| **Recomendado** | 0 + 1 + 2a | ~$5/año | Producción chica, equipo GIDAS |
| **Completo** | 0 + 1 + 2a + 3 | ~$5/año | Producción + seguridad |
| **Profesional** | 0 + 1 + 2a + 3 + 4 | ~$65/año | Control total, alta disponibilidad |

---

## ⚡ Acción Inmediata Recomendada

1. **Esta semana**: Crear cuenta Cloudflare (2 min) → Named Tunnel (30 min) → URL estable
2. **Este mes**: Comprar `gidas.com.ar` (~$5) → Dominio profesional
3. **Próximo mes**: Evaluar si necesitamos Zero Trust o VPS

---

## 🔄 Rollback

Cada fase es **reversible**:

- **Fase 1**: Volver a Quick Tunnel = eliminar credenciales de Cloudflare y restaurar `gidas-tunnel.service`
- **Fase 2**: Dejar de usar el dominio = actualizar Drupal con la URL del Named Tunnel
- **Fase 3**: Desactivar Zero Trust = eliminar la política de acceso
- **Fase 4**: Volver a tunnel = apagar VPS y restaurar tunnel desde CT 208

Ninguna fase requiere cambiar la infraestructura interna (nginx, portal, tools).

---

*Documento mantenible — 2026-07-03*
