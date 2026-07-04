# ADR-005: Seguridad en el Portal de Acceso — Rate Limiting y Headers OWASP

**Fecha:** 2026-07-03
**Contexto:** El portal GIDAS está expuesto a internet via Cloudflare Tunnel, accesible sin autenticación previa (solo el login). Esto lo convierte en blanco de ataques de fuerza bruta, inyección y scraping automatizado. Se necesitan medidas de seguridad básicas pero efectivas para proteger las credenciales AD de los miembros del grupo.

## Decisión

**Implementar rate limiting en memoria** (sin base de datos externa) con bloqueo temporal tras 4 intentos fallidos, más headers de seguridad OWASP en todas las respuestas. Las alertas de fuerza bruta se envían por Telegram.

## Alternativas Consideradas

| Alternativa | Descartada por |
|-------------|----------------|
| **Redis-based rate limiting** | Requiere Redis externo. El portal no tiene Redis. Sobredimensionado para el volumen actual (~15 usuarios). |
| **Fail2ban a nivel SO** | No aplica porque el login es vía HTTP (no SSH). Habría que parsear logs de uvicorn. Más complejo de mantener. |
| **Cloudflare WAF + Rate Limiting** | Requiere cuenta Cloudflare con dominio en Cloudflare (Fase 2 del roadmap). No implementado aún. |
| **JWT blacklist en DB** | El portal no tiene base de datos. Usar una lista negra en memoria es más simple y consistente. |
| **Captcha (reCAPTCHA)** | Dependencia externa (Google). No queremos depender de terceros para la autenticación. |

## Argumentos a Favor

1. **Sin dependencias externas:** El rate limiter usa un dict en memoria + threading.Lock. No requiere Redis, DB ni servicios externos.
2. **Ligero:** Cada intento fallido ocupa ~200 bytes. Para 15 usuarios es irrelevante.
3. **Auto-limpieza:** Entradas antiguas (>1 hora) se limpian automáticamente cuando se superan 1000 entradas.
4. **Notificación inmediata:** Al detectar fuerza bruta, envía Telegram al admin.
5. **Headers OWASP:** Sin impacto en performance. Se aplican via middleware de Starlette.
6. **Sin falsos bloqueos:** El rate limit es por IP+usuario. Un usuario legítimo que se equivoca de contraseña no bloquea a otros.

## Riesgos y Mitigaciones

| Riesgo | Mitigación |
|--------|------------|
| **Bloqueo de IP compartida** (NAT) | El rate limit combina IP + usuario. Múltiples usuarios desde la misma IP no se afectan entre sí. |
| **Pérdida de contadores al reiniciar** | Aceptable. Los contadores se pierden, pero un atacante perdería su progreso también. |
| **Memory leak por muchas entradas** | Cleanup automático cuando se superan 1000 entradas (entradas > 1 hora se eliminan). |
| **Telegram como único canal de alerta** | Depende de la API de Telegram. Si Telegram está caído, la alerta no llega. Aceptable para el nivel actual. |

## Configuración

```python
MAX_ATTEMPTS = 4          # Intentos antes de bloquear
BLOCK_MINUTES = 15         # Duración del bloqueo
MAX_ENTRIES = 1000         # Limpieza automática
CLEANUP_AGE = 3600         # 1 hora
```

### Headers de seguridad implementados

| Header | Valor |
|--------|-------|
| `X-Content-Type-Options` | `nosniff` |
| `X-Frame-Options` | `DENY` |
| `X-XSS-Protection` | `1; mode=block` |
| `Referrer-Policy` | `strict-origin-when-cross-origin` |
| `Permissions-Policy` | `geolocation=(), microphone=(), camera=()` |
| `Cache-Control` | `no-store` |

### Endpoint de monitoreo

```
GET /security/stats → {"total_tracked": 1, "blocked_ips": 0}
```

## Próximos Pasos

1. Migrar a Cloudflare Zero Trust cuando se implemente el dominio propio (autenticación a nivel de edge, antes de llegar al portal)
2. Evaluar si se necesita rate limiting más agresivo (ej: bloqueo por IP pura después de N intentos desde la misma IP)
3. Agregar logging centralizado de intentos fallidos

## Estado

**Aceptada e Implementada**
