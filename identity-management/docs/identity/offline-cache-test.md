# Procedimiento de Verificación: SSSD Offline Cache ≥ 8h — AC6

> **Referencia**: Especificación AC6 (`identity-management/sdd/specs.md`)
> **Diseño**: `identity-management/sdd/design.md §3.3`
>
> ⚠️ **ADVERTENCIA**: Este procedimiento INTERRUMPE la conectividad con AD.
> Ejecutar SOLO en ventana de mantenimiento y con autorización.

## Objetivo

Verificar que SSSD permite autenticación offline con credenciales cacheadas
por al menos 8 horas después de perder conectividad con el Domain Controller.

## Requisitos

- Host Linux con SSSD configurado para FreeIPA (provider `ipa`)
- Usuario AD que haya hecho login exitosamente en el host (credenciales cacheadas)
- Acceso root al host
- Ventana de mantenimiento (tiempo estimado: 15 min + tiempo de espera de cache)

## Procedimiento

### Paso 1: Verificar estado inicial

```bash
# Verificar que SSSD está corriendo
systemctl status sssd

# Verificar configuración de cache
grep -E "cache_credentials|offline_credentials_expiration|entry_cache_timeout" /etc/sssd/sssd.conf

# Valores esperados (de design.md §3.3):
#   cache_credentials = True
#   offline_credentials_expiration = 8
#   entry_cache_timeout = 3600
```

### Paso 2: Asegurar que hay credenciales cacheadas

```bash
# Hacer login con un usuario AD que exista en el sistema
ssh ad-user@localhost
# Login exitoso → SSSD cachea credenciales

# Verificar que el usuario está en cache SSSD
sssctl cache-stats | grep -i users
# O si sssctl no está disponible:
ls -la /var/lib/sss/db/
# Debe existir un archivo cache_*.ldb
```

### Paso 3: Registrar estado de cache

```bash
# Registrar timestamp actual
date '+%Y-%m-%d %H:%M:%S' > /tmp/offline-test-start.txt

# Verificar que el usuario AD puede autenticarse
su - ad-user -c "id"
# Debe mostrar UID y grupos del AD
```

### Paso 4: Cortar conectividad con AD (y FreeIPA si aplica)

```bash
# Bloquear tráfico a AD (192.168.1.117)
iptables -A OUTPUT -d 192.168.1.117 -j DROP

# Si el host usa FreeIPA como gateway de autenticación,
# también bloquear FreeIPA (192.168.1.118)
iptables -A OUTPUT -d 192.168.1.118 -j DROP

# VERIFICAR que AD no es accesible
ping -c 2 192.168.1.117
# Debe fallar (Destination Host Unreachable o 100% loss)
```

### Paso 5: Probar autenticación offline

```bash
# Intentar login con usuario AD cacheado
ssh ad-user@localhost

# RESULTADO ESPERADO: login exitoso
# SSSD debe usar credenciales cacheadas

# Verificar que SSSD está en modo offline
sssctl domain-status gdc01.local 2>/dev/null | grep -i "Online\|offline"
# Debe mostrar: "Offline" o "Online status: offline"
```

### Paso 6: (Opcional) Verificar timeout de cache

Para probar que el cache es ≥ 8h, se necesita esperar ese tiempo.
Alternativa: reducir `offline_credentials_expiration` temporalmente a 5 min
para verificar el mecanismo:

```bash
# SOLO PARA PRUEBA RÁPIDA — revertir después
sed -i 's/offline_credentials_expiration = 8/offline_credentials_expiration = 5/' /etc/sssd/sssd.conf
systemctl restart sssd

# Esperar 5+ minutos y verificar que el cache expira
# Luego restaurar valor original
sed -i 's/offline_credentials_expiration = 5/offline_credentials_expiration = 8/' /etc/sssd/sssd.conf
systemctl restart sssd
```

### Paso 7: Restaurar conectividad

```bash
# Remover reglas iptables
iptables -D OUTPUT -d 192.168.1.117 -j DROP
iptables -D OUTPUT -d 192.168.1.118 -j DROP

# Verificar conectividad restaurada
ping -c 2 192.168.1.117
# Debe responder

# SSSD detecta conectividad automáticamente y vuelve a online
sssctl domain-status gdc01.local 2>/dev/null | grep -i "Online\|offline"
```

### Paso 8: Verificación post-prueba

```bash
# Verificar que login sigue funcionando (modo online)
ssh ad-user@localhost
# Debe ser exitoso

# Verificar logs de SSSD durante el período offline
journalctl -u sssd --since "5 minutes ago" | grep -i "offline\|cache\|go online"
```

## Criterios de Aceptación

| Criterio | Esperado | Resultado |
|----------|----------|-----------|
| Login offline exitoso | ✅ Sí, con credenciales cacheadas | |
| Tiempo de cache | ≥ 8 horas configurado | `offline_credentials_expiration = 8` |
| SSSD detecta offline | ✅ `sssctl domain-status` → "Offline" | |
| Post-restauración | ✅ Login funciona normalmente | |
| Logs sin errores | ⚠️ Warnings de offline son esperados, no errors | |

## Rollback

Si la prueba falla:

```bash
# Restaurar conectividad inmediatamente
iptables -D OUTPUT -d 192.168.1.117 -j DROP 2>/dev/null || true
iptables -D OUTPUT -d 192.168.1.118 -j DROP 2>/dev/null || true

# Limpiar cache SSSD (los nuevos intentos usarán online)
sss_cache -E

# Reiniciar SSSD
systemctl restart sssd

# Verificar que recuperó conectividad
sssctl domain-status gdc01.local
```

## Referencias

- `identity-management/sdd/specs.md` §AC6, §S5
- `identity-management/sdd/design.md` §3.3 (SSSD config), §4.1 (auth flow)
- `identity-management/scripts/verify-ac6-offline-cache.sh` (verificación no destructiva)
