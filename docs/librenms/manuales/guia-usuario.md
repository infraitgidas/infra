# Guía de Usuario — LibreNMS GIDAS

> **URL**: https://nms.gidas.local
> **Login**: Usuario y contraseña de AD GIDAS

---

## 1. ¿Qué es LibreNMS?

LibreNMS es el sistema de monitoreo de red de GIDAS. Permite ver el estado de todos los dispositivos de la infraestructura (servidores, switches, routers) en tiempo real, recibir alertas cuando algo falla, y consultar históricos de rendimiento.

---

## 2. Acceso

1. Abrí https://nms.gidas.local
2. Iniciá sesión con tu **usuario y contraseña de AD** (la misma que usás para GitLab, Redmine, etc.)
3. Según tu grupo AD vas a tener distintos permisos:

| Tu grupo | Podés hacer |
|----------|-------------|
| Cualquier usuario | ✅ Ver dispositivos, estado, gráficos |
| `gidas-admins`, `SRV-Monitoring`, `G-IdentityAdmins` | ✅ Administrar dispositivos, configurar alertas |

---

## 3. Dashboard Principal

Al iniciar sesión ves el dashboard con:

- **Dispositivos**: cantidad total, cuántos están UP/DOWN
- **Alertas**: notificaciones activas
- **World map**: ubicación geográfica de los dispositivos (si tiene coordenadas)
- **Gráficos**: uptime, tráfico de red

Podés personalizar el dashboard desde el botón **Edit Dashboard** (arriba a la derecha).

---

## 4. Ver Dispositivos

Andá a **Devices → All Devices**. Aparece la lista completa:

| Columna | Significado |
|---------|-------------|
| **Hostname** | Nombre del dispositivo |
| **Platform** | Sistema operativo / firmware |
| **Type** | Tipo: server, network, etc. |
| **Status** | 🟢 = UP, 🔴 = DOWN |
| **Uptime** | Tiempo desde último reinicio |
| **Last Polled** | Última vez que se actualizaron los datos |

Hacé click en cualquier dispositivo para ver sus detalles completos:
- Gráficos de CPU, memoria, disco
- Puertos de red con tráfico
- Sensores (temperatura, voltaje)
- Alertas activas para ese dispositivo

---

## 5. Alertas

### ¿Cómo me llegan las alertas?

| Canal | Configuración |
|-------|---------------|
| **📧 Email** | A infrait@frlp.utn.edu.ar (por ahora) |
| **🤖 Telegram** | Al bot @GiDAS_alertbot |

### Tipos de alerta

| Icono | Severidad | Significado |
|-------|-----------|-------------|
| 🔴 | Critical | Dispositivo caído, recurso crítico al límite |
| 🟡 | Warning | Recurso接近 límite, latencia alta, rendimiento degradado |

Cuando un dispositivo genera una alerta, se crea un evento en **Alerts → Active Alerts**.

---

## 6. Consultar Historial

### Gráficos históricos
Cada dispositivo tiene gráficos de:
- **CPU**: uso en el tiempo (última hora, día, semana, mes, año)
- **Memoria RAM**: igual que CPU
- **Disco**: uso por partición
- **Tráfico de red**: puertos con entrada/salida en bps
- **Temperatura**: sensores disponibles

Podés cambiar el rango de tiempo con el selector en la parte superior del gráfico.

### Log de eventos
**Events → Event Log** muestra todos los eventos registrados: cambios de estado, alertas, polling, etc.

---

## 7. Grafana

Además de LibreNMS, las métricas también están disponibles en **Grafana**:

- **URL**: `http://192.168.1.205:3000`
- **Usuario/Password**: Consultar con el administrador

Dashboards disponibles:
- **Overview**: visión general de infraestructura
- **Performance**: CPU/RAM/disco por dispositivo
- **Network**: tráfico de red, errores, ancho de banda

---

## 8. Preguntas Frecuentes

### No puedo iniciar sesión
- Asegurate de usar tu **usuario de AD** (no el local de la máquina)
- Probá en https://portal.gidas.local primero para verificar que tu usuario funciona
- Si el problema persiste, contactá al administrador

### Veo "No roles!" o "No access!"
Tu usuario AD no está en ninguno de los grupos que dan permisos en LibreNMS. Todos los usuarios tienen al menos acceso de lectura, pero si ves este mensaje, contactá al administrador.

### No veo datos en un dispositivo
Puede ser que:
- El dispositivo esté apagado o sin red
- El SNMP no esté configurado correctamente
- El poller todavía no haya pasado (esperá 5 minutos)

### No me llegan alertas
- Revisá la sección **Alerts → Active Alerts** para ver si hay alertas activas
- Si no hay alertas activas, es porque no hay condiciones que las disparen
- Si hay alertas activas pero no te llegan, contactá al administrador

---

## 9. Contacto

| Problema | Contacto |
|----------|----------|
| No puedo iniciar sesión | Administrador de AD |
| Dispositivo incorrecto o faltante | Equipo de infraestructura |
| Alerta falsa | Reportar en Telegram @GiDAS_alertbot |
| Consultas generales | infrait@frlp.utn.edu.ar |

---

*Última actualización: 2026-07-03*
