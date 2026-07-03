# ADR-004: Cloudflare Tunnel como solución de acceso remoto al portal

**Fecha:** 2026-07-03
**Contexto:** El portal GIDAS (`portal.gidas.local`) corre en un CT interno (192.168.1.43) sin IP pública. Se necesita que los miembros del grupo puedan acceder desde internet. Inicialmente se usaba Twingate (cuenta personal free, limitada a 2-5 usuarios), pero no escalaba para todo el grupo. El dominio `gidas.frlp.utn.edu.ar` existe pero está en servidores de UTN-FRLP sin acceso SSH.

## Decisión

**Usar Cloudflare Tunnel (Quick Tunnel)** desde el CT 208 (portal) para exponer el portal vía HTTPS público, con actualización automática de la URL en la página de Drupal. Como solución de respaldo, se mantiene el enlace desde el menú del sitio Drupal.

## Alternativas Consideradas

| Alternativa | Descartada por |
|-------------|----------------|
| **Twingate (cuenta free personal)** | Límite de 2-5 usuarios. No escalable para todo el grupo. Cuenta personal atada a Google del administrador. |
| **Port forwarding en MikroTik** | Sin credenciales de administración del MikroTik. Puertos 80/443/22 cerrados desde fuera de la red UTN. |
| **SSH reverse tunnel desde VPS** | Requiere VPS pago (~$5/mes). Sin presupuesto asignado. |
| **Subdominio gestionado por UTN** | Sin acceso al DNS de UTN. El administrador anterior ya no está. Sin respuesta del Departamento de Sistemas. |
| **Apache reverse proxy en servidor Drupal** | Sin acceso SSH al servidor 200.10.126.117. Puerto 22 bloqueado incluso desde la red UTN. |
| **Compra de dominio propio** (gidas.com.ar) | Sin presupuesto. Opción evaluada para futuro (~$5/año). |
| **Drupal + iframe** | El portal tiene headers que bloquean iframes (X-Frame-Options). Además no resuelve el acceso real. |

## Argumentos a Favor

1. **Costo cero:** Cloudflare Tunnel es gratuito. Sin límite de usuarios ni ancho de banda para el plan试用.
2. **Sin puertos abiertos:** El tunnel establece una conexión saliente desde el CT hacia Cloudflare. No se abre ningún puerto en el firewall.
3. **HTTPS automático:** Cloudflare provee SSL/TLS sin configuración adicional.
4. **Fácil de automatizar:** Script Python que crea el tunnel, extrae la URL y actualiza Drupal automáticamente.
5. **Tolerante a fallos:** Systemd reinicia el servicio automáticamente. Al reiniciar, se genera nueva URL y se actualiza Drupal.
6. **Independencia:** No depende de UTN, de Twingate ni de ningún proveedor externo más que Cloudflare.

## Riesgos y Mitigaciones

| Riesgo | Mitigación |
|--------|------------|
| Quick Tunnel no tiene uptime garantizado | Cloudflare advierte que es para experimentación. Para producción, migrar a named tunnel con cuenta Cloudflare gratis. |
| URL cambia si el proceso muere | Systemd restart automático + script actualiza Drupal. La página de Drupal siempre tiene la URL vigente. |
| Sin dominio propio | La URL `xxx.trycloudflare.com` no es ideal pero es funcional. Evaluar compra de `gidas.com.ar` (~$5/año). |
| CT 208 no tiene Docker | cloudflared instalado como binario directo. Service systemd nativo. |

## Arquitectura

```
Usuario → gidas.frlp.utn.edu.ar → Menú "Portal GIDAS" → Página /node/40
                                                              ↓
                                     Botón "ACCEDER AL PORTAL GIDAS"
                                                              ↓
                                    https://xxx.trycloudflare.com
                                                              ↓
                                          Cloudflare Edge
                                                              ↓ (tunnel)
                                        CT 208 (cloudflared)
                                                              ↓
                                    portal.gidas.local (192.168.1.43)
                                                              ↓
                                               Login AD
```

## Componentes

| Componente | Tecnología | Propósito |
|------------|-----------|-----------|
| Drupal | CMS (gidas.frlp.utn.edu.ar) | Página pública con enlace al portal |
| Cloudflare Tunnel | cloudflared + edge network | Túnel HTTPS desde CT a Cloudflare |
| Proxy reverso | nginx (en container Docker de PC auxiliar) | Alternativa de respaldo |
| Sistema automático | Python + systemd | Crea tunnel, actualiza Drupal, monitorea |
| Portal | FastAPI + LDAP (CT 208) | Login AD + dashboard de herramientas |

## Automatización

El script `auto-tunnel.py` (en CT 208, `/opt/portal-gidas/`) ejecuta el ciclo:

```
1. Iniciar cloudflared tunnel → URL
2. Extraer URL del log → https://xxx.trycloudflare.com
3. Login a Drupal + extraer formulario de edición
4. Actualizar body de /node/40 con nueva URL y botón
5. Monitorear tunnel. Si muere, reiniciar desde paso 1.
```

Service systemd: `gidas-tunnel.service` con `Restart=always`.

## Próximos Pasos

1. **Crear cuenta Cloudflare** (gratis) y migrar a named tunnel para URL estable
2. **Evaluar compra de dominio** `gidas.com.ar` (~$5/año) para URL definitiva
3. **Si UTN lo permite**, delegar `portal.gidas.frlp.utn.edu.ar` al tunnel
4. **Mejorar seguridad**: agregar autenticación en Cloudflare (Zero Trust)

## Estado

**Aceptada e Implementada** (fase inicial con Quick Tunnel)
