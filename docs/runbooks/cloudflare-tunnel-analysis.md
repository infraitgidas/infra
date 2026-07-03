# Cloudflare Tunnel — Análisis y Roadmap

> Documentación del tunnel utilizado para exponer el portal GIDAS,
> limitaciones de la versión actual y opciones de escalado.

---

## 1. ¿Qué estamos usando?

### Quick Tunnel (trycloudflare.com)

Actualmente usamos el **Quick Tunnel** de Cloudflare, que se genera automáticamente al ejecutar `cloudflared tunnel` sin autenticación. Es una funcionalidad gratuita que permite probar la tecnología sin crear una cuenta.

| Aspecto | Detalle |
|---------|---------|
| **Tipo** | Quick Tunnel (sin autenticación) |
| **Comando** | `cloudflared tunnel --url http://...` |
| **URL** | `https://palabras-aleatorias.trycloudflare.com` |
| **Cuenta** | ❌ No requiere cuenta |
| **Usuario** | Ninguno (anónimo) |
| **Password** | Ninguna |
| **Email** | Ninguno |
| **Costo** | $0 |

### ¿Cómo lo iniciamos?

```bash
# En CT 208, via systemd:
/usr/local/bin/cloudflared tunnel \
  --url http://127.0.0.1:80 \
  --no-autoupdate \
  --logfile /var/log/cloudflared.log
```

---

## 2. Limitaciones del Quick Tunnel

### 2.1 Sin garantía de uptime

El mensaje oficial de Cloudflare al iniciar el tunnel:

> *"be aware that these account-less Tunnels have no uptime guarantee, are subject to the Cloudflare Online Services Terms of Use, and Cloudflare reserves the right to investigate your use of Tunnels for violations of such terms."*

Traducción: **Sin garantía de disponibilidad**. Cloudflare puede investigar o limitar el uso.

### 2.2 URL volátil

| Evento | ¿Cambia la URL? |
|--------|----------------|
| Reinicio del servicio | ✅ **Sí** — nueva URL aleatoria |
| Reinicio del CT 208 | ✅ **Sí** |
| Actualización de cloudflared | ✅ **Sí** |
| Tunnel corriendo estable | ❌ No (misma URL) |

Cada vez que cambia, el script `auto-tunnel.py` actualiza la página de Drupal automáticamente.

### 2.3 Sin control de DNS

- No podemos usar un dominio personalizado (ej: `portal.gidas.com.ar`)
- No podemos configurar reglas de firewall de Cloudflare (WAF, IP filtering)
- No podemos usar autenticación Cloudflare Zero Trust
- No tenemos acceso a analytics del tráfico

### 2.4 Límites implícitos

Cloudflare no documenta límites exactos para Quick Tunnels, pero por experiencia comunitaria:

| Aspecto | Límite estimado |
|---------|----------------|
| **Conexiones simultáneas** | ~100-500 (no documentado) |
| **Ancho de banda** | Ilimitado (sujeto a uso aceptable) |
| **Tiempo máximo por conexión** | Ilimitado |
| **Número de túneles** | 1 por instancia de cloudflared |
| **Ubicaciones de PoP** | Todos los PoPs de Cloudflare |
| **HTTPS/SSL** | ✅ Automático (certificado de Cloudflare) |

---

## 3. Opciones de Escalado

### Opción A: Named Tunnel con cuenta Cloudflare gratis ($0)

| Aspecto | Quick Tunnel (actual) | Named Tunnel |
|---------|----------------------|--------------|
| **Cuenta** | No requiere | Cloudflare gratis |
| **URL** | `xxx.trycloudflare.com` | `xxx.cfargotunnel.com` o dominio propio |
| **Estabilidad** | ❌ Cambia al reiniciar | ✅ **Fija** |
| **Dominio propio** | ❌ No | ✅ Sí (con DNS en Cloudflare) |
| **WAF / Reglas** | ❌ No | ✅ Sí |
| **Analytics** | ❌ No | ✅ Sí |
| **Autenticación** | ❌ No | ✅ Cloudflare Zero Trust |
| **Límite usuarios** | Ilimitado (implícito) | Ilimitado |
| **Costo** | $0 | $0 |

**Para migrar**:

```bash
# 1. Crear cuenta en https://cloudflare.com
# 2. Autenticar cloudflared:
cloudflared tunnel login

# 3. Crear tunnel nombrado:
cloudflared tunnel create gidas-portal

# 4. Configurar DNS (si tenés dominio en Cloudflare):
cloudflared tunnel route dns gidas-portal portal.gidas.com.ar

# 5. Instalar como servicio:
cloudflared service install
```

### Opción B: Domain propio + Cloudflare DNS (~$5/año)

| Concepto | Detalle |
|----------|---------|
| **Dominio** | Ej: `gidas.com.ar` |
| **Registro** | nic.ar (Argentina) |
| **Costo** | ~$5/año (renovación anual) |
| **DNS** | Cloudflare (gratis) |
| **SSL** | Automático (Cloudflare edge) |
| **Ventaja** | URL profesional, independencia de UTN |

### Opción C: VPS + Reverse Proxy directo (~$5/mes)

| Concepto | Detalle |
|----------|---------|
| **Servicio** | VPS en DigitalOcean, Hetzner, etc. |
| **Costo** | ~$5-10/mes |
| **Uso** | Reverse proxy nginx + WireGuard a red GIDAS |
| **Ventaja** | Control total, sin límites de Cloudflare |
| **Desventaja** | Costo mensual, mantener servidor |

### Opción D: Cloudflare Zero Trust (gratis hasta 50 usuarios)

Cloudflare Zero Trust permite agregar **autenticación** al tunnel:
- Login con Google, GitHub, email, etc.
- Hasta 50 usuarios gratis
- Reglas de acceso por grupo
- Protege las tools detrás de autenticación

---

## 4. Roadmap Recomendado

| Fase | Acción | Costo | Dependencia |
|------|--------|-------|-------------|
| **Ahora** | ✅ Quick Tunnel (actual) + auto-update Drupal | $0 | — |
| **Corto plazo** | Crear cuenta Cloudflare + Named Tunnel | $0 | Cuenta Cloudflare |
| **Mediano plazo** | Comprar dominio `gidas.com.ar` | ~$5/año | Aprobación |
| **Largo plazo** | Cloudflare Zero Trust (auth para tools) | $0 (hasta 50 users) | Cuenta Cloudflare |
| **Opcional** | VPS dedicado como proxy | ~$5/mes | Presupuesto |

---

## 5. Resumen de Costos

| Escenario | Costo inicial | Costo mensual | Usuarios |
|-----------|-------------|---------------|----------|
| Solo Quick Tunnel (actual) | $0 | $0 | Ilimitado (sin garantía) |
| + Cuenta Cloudflare + Named Tunnel | $0 | $0 | Ilimitado |
| + Dominio propio | ~$5 | ~$0.42/mes | Ilimitado |
| + Cloudflare Zero Trust | $0 | $0 | Hasta 50 |
| + VPS proxy | $0 | $5-10/mes | Ilimitado |

---

## 6. Recomendación Final

**Para producción estable con $0 presupuesto**:
1. Crear cuenta Cloudflare (gratis)
2. Migrar a Named Tunnel (URL fija)
3. Agregar Cloudflare Zero Trust para autenticar el acceso

**Si hay presupuesto (~$5/año)**:
4. Comprar `gidas.com.ar` y conectarlo al tunnel

Con esto se obtiene:
- ✅ URL estable y profesional
- ✅ Sin límites de usuarios
- ✅ Sin depender de UTN ni Twingate
- ✅ Autenticación opcional via Cloudflare
- ✅ Control total de DNS y seguridad
