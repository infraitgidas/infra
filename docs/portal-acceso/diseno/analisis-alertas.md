# Análisis de Alertas Multicanal — LibreNMS

> **Feature**: Sistema de notificaciones para LibreNMS
> **Rama**: `feat/monitoreo-red`
> **Fecha**: 2026-07-02

---

## 1. Canales Disponibles

LibreNMS soporta múltiples **transports** (canales de alerta) de forma nativa:

| Canal | Transport LibreNMS | Implementación |
|-------|-------------------|----------------|
| 📧 Email | Nativo via SMTP | Office 365 (configurado) |
| 📱 Telegram | `telegram` (bot API) | LibreNMS → Bot de Telegram |
| 💬 WhatsApp | No nativo | Via gateway externo |

---

## 2. Telegram

### Cómo funciona

LibreNMS incluye transporte nativo para Telegram via Bot API.

### Setup

```bash
# 1. Crear bot en Telegram
#    - Buscar @BotFather en Telegram
#    - Enviar: /newbot
#    - Elegir nombre: "GIDAS Alerts"
#    - Copiar el token API

# 2. Obtener Chat ID
#    - Iniciar chat con el bot
#    - Visitar: https://api.telegram.org/bot<TOKEN>/getUpdates
#    - Copiar chat id del mensaje

# 3. Configurar en LibreNMS
#    Global Settings → Alerting → Transports → Telegram
#    - Bot Token: <token>
#    - Chat ID: <chat_id> (pueden ser varios separados por coma)
```

### Configuración en LibreNMS

Desde la UI de LibreNMS:
1. Ir a **Global Settings → Alerting → Transports**
2. Agregar **Telegram Transport**
3. Configurar:
   - `bot_token`: token de BotFather
   - `chat_id`: ID del chat/grupo
   - `format`: Markdown o HTML

### Múltiples destinatarios

Se pueden crear **múltiples transports** con diferentes bot tokens o diferentes chat IDs. Por ejemplo:
- Un grupo para alertas críticas (Dirección + Coordinadores)
- Otro grupo para alertas informativas (todo el equipo)

---

## 3. WhatsApp

LibreNMS **NO** tiene transporte nativo para WhatsApp. Opciones:

### Opción A: CallMeBot (WhatsApp API)

**Servicio**: [callmebot.com](https://www.callmebot.com/blog/free-api-whatsapp-messages/)

| Aspecto | Detalle |
|---------|---------|
| **Costo** | Gratuito (500 msgs/día) |
| **Setup** | Enviar "I allow callmebot" al +34 603 53 28 53 via WhatsApp |
| **API Key** | Generada automáticamente |
| **Integración** | LibreNMS → Webhook → CallMeBot API |
| **Limitación** | Solo 1 número de destino por API key |

**Setup**:
```bash
# Probar envio:
curl -s "https://api.callmebot.com/whatsapp.php?phone=541122334455&text=test&apikey=123456"
```

**En LibreNMS**: Usar transporte **Webhook** apuntando a la URL de CallMeBot.

### Opción B: WhatsApp Business API (Meta)

| Aspecto | Detalle |
|---------|---------|
| **Costo** | Pago por conversación |
| **Setup** | Requiere cuenta Business verificada en Meta |
| **Complejidad** | Alta (requiere servidor webhook, certificados) |
| **Para GIDAS** | ❌ Overkill para 17 usuarios |

### Opción C: Gateway SMS/WhatsApp (Twilio, MessageBird)

| Aspecto | Detalle |
|---------|---------|
| **Costo** | Por mensaje (~$0.05 USD/msg) |
| **Setup** | API key + número virtual |
| **Integración** | LibreNMS → Webhook → Twilio API |
| **Para GIDAS** | 🟡 Factible pero tiene costo |

---

## 4. Arquitectura de Alertas Propuesta

```
                ┌─────────────────────────────┐
                │       LibreNMS              │
                │    (motor de alertas)        │
                └──────┬──────────┬───────────┘
                       │          │
          ┌────────────┼──────────┼──────────────┐
          │            │          │              │
          ▼            ▼          ▼              ▼
    ┌─────────┐ ┌──────────┐ ┌────────┐ ┌──────────────┐
    │  Email  │ │ Telegram │ │Webhook │ │  Webhook     │
    │ Office  │ │ Bot API  │ │→OSMS   │ │→CallMeBot    │
    │  365    │ │          │ │(futuro)│ │  (WhatsApp)   │
    └─────────┘ └──────────┘ └────────┘ └──────────────┘
```

---

## 5. Destinatarios por Severidad

| Severidad | Email | Telegram | WhatsApp |
|-----------|-------|----------|----------|
| 🔴 **Crítica** (down, hardware fail) | ✅ infrait@frlp | ✅ Grupo Dirección | ✅ Números guardia |
| 🟡 **Alta** (link flap, high latency) | ✅ infrait@frlp | ✅ Grupo Técnico | ❌ |
| 🔵 **Media** (disk usage, temp) | ❌ | ✅ Canal info | ❌ |

---

## 6. Configuración de Múltiples Destinatarios

LibreNMS permite **default contacts** (usuarios) y **custom contacts** (emails externos, grupos).

### Default Contacts
Cada usuario de LibreNMS puede configurar su email en su perfil. Las alertas se envían automáticamente según el rol.

### Custom Contacts
Se pueden agregar contactos adicionales desde:
- **Global Settings → Alerting → Contacts**
- Email, Telegram Chat ID, o Webhook URL
- Asociados a reglas de alerta específicas

### Para el futuro
Crear un sistema de **escalado de alertas**:
- Si alerta crítica no es acknowledge en 15 min → Telegram + WhatsApp
- Si no se resuelve en 60 min → Email a Dirección
