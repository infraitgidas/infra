# Informe de Cambios — LibreNMS (Monitoreo de Red)

**Feature branch**: `feat/monitoreo-red`
**Fecha**: 2026-07-02
**Estado**: IMPLEMENTADO (Telegram bot operativo)

---

## 1. Resumen Ejecutivo

Se desplegó LibreNMS como sistema de monitoreo de red dedicado para dispositivos GIDAS. Complementa el stack Prometheus+Grafana existente con features NMS: auto-descubrimiento SNMP, mapas de topología, alertas inteligentes.

| Concepto | Valor |
|----------|-------|
| **Versión** | LibreNMS latest (Docker) |
| **CT** | 210 — Rocky Linux 9 — 1GB RAM — 1 vCPU |
| **IP** | 192.168.1.45/24 |
| **DNS** | nms.gidas.local |
| **Auth** | LDAP contra AD GDC01 |
| **DB** | MariaDB 10 (container) |
| **Cache** | Redis 7 (container) |
| **SSL** | Self-signed via nginx reverse proxy |
| **SMTP** | Office 365 (infrait@frlp.utn.edu.ar) |

---

## 2. Infraestructura

| Recurso | Detalle |
|---------|---------|
| **CT 210** | Rocky Linux 9, 1GB RAM, 1 vCPU, 16GB disco |
| **Docker** | docker-ce + docker-compose-plugin |
| **Containers** | librenms, mariadb:10, redis:7-alpine |
| **nginx** | Reverse proxy SSL, puerto 443 → librenms:8080 |
| **Almacenamiento** | Volúmenes Docker: librenms_data, mysql_data, redis_data |
| **Config persistente** | `librenms_data/_data/config/config.php` |

## 3. Configuración

| Componente | Detalle |
|------------|---------|
| **LDAP** | Servidor 192.168.1.117, bind CN=infrait, filter (sAMAccountName=%u) |
| **SMTP** | smtp.office365.com:587, TLS, infrait@frlp.utn.edu.ar |
| **Base URL** | https://nms.gidas.local |
| **Trusted proxies** | 127.0.0.1, 10.0.0.0/8, 172.16.0.0/12 |

## 4. Incidencias Post-Implementación

### Problema: Container librenms en restart loop

**Síntoma**: nginx devolvía 502 Bad Gateway. Container mostraba `04-svc-main.sh: exited 1`.

**Causa raíz**: Dos errores en la configuración PHP:
1. `config.php` línea 48: `\$config[\x27base_url\x27]` — escapes literales no interpretados (PHP syntax error)
2. `base_url.php` en volumen persistente: `[base_url] = https://...` — faltaba `$config` y comillas

**Solución**:
```bash
# 1. Fix config.php en la imagen (commit nuevo)
sed -i "48d" config.php           # Eliminar linea rota
# 2. Fix config persistente en volumen
cat > /data/config/base_url.php
docker restart librenms
```

**Lección**: Al editar archivos PHP via heredoc en bash, el `$config` es interpretado por bash. Usar Python o `pct push` para escribir archivos PHP.

## 5. Verificación

| Criterio | Resultado |
|----------|-----------|
| Web UI responde HTTPS | ✅ 200 OK |
| Login page visible | ✅ Title: LibreNMS |
| Telegram Bot configurado | ✅ Mensaje de prueba enviado |
| LDAP configurado | ✅ En .env |
| SMTP configurado | ✅ En .env |
| Auto-discovery SNMP | ⏳ Pendiente configurar comunidades |

## 6. Trabajo Futuro

| Tarea | Prioridad |
|-------|-----------|
| ✅ Telegram Bot configurado y probado | Alta | ✅ |
| Configurar comunidades SNMP en dispositivos | Alta | ⏳ |
| Configurar auto-discovery en LibreNMS | Alta | ⏳ |
| Agregar card en portal GIDAS | Baja | ⏳ |
| Configurar WhatsApp (CallMeBot) | Baja | ⏳ |
