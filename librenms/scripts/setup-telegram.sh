🚧 La configuración del transporte Telegram se realiza desde la UI de LibreNMS.

Cuando tengas el token, seguí estos pasos:

## 1. Crear el Bot (hacelo vos en Telegram)

1. Abrí Telegram y buscá **@BotFather**
2. Enviá: `/newbot`
3. Nombre: `GIDAS Alerts`
4. Username: `gidas_alerts_bot` (o el que quieras)
5. **Copiá el token** que te da BotFather (algo como `123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11`)

## 2. Obtener el Chat ID

1. Iniciá chat con el bot nuevo que creaste
2. Enviá cualquier mensaje (ej: `/start`)
3. Visitá en el navegador:
   ```
   https://api.telegram.org/bot<TOKEN>/getUpdates
   ```
4. En el JSON, buscá `"chat":{"id":-1001234567890}` → ese número es el chat ID

## 3. Configurar en LibreNMS

1. Andá a `https://nms.gidas.local`
2. **Global Settings → Alerting → Transports**
3. Agregar **Telegram Transport**
4. Ingresá:
   - **Bot Token**: el que te dio BotFather
   - **Chat ID**: el número del paso anterior
   - **Format**: Markdown
5. Guardar

## 4. Probar

Desde la misma página de Transports hay un botón **"Test"** para enviar un mensaje de prueba.

---

> Cuando tengas el token, pasámelo y lo configuro yo directamente si preferís.
