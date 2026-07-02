# Design: LibreNMS

## Arquitectura

```
┌─ CT 210 (Rocky Linux 9) ─────────────────────────┐
│                                                    │
│  nginx (reverse proxy, SSL)                       │
│  │  puerto 443 → LibreNMS:80                      │
│  │                                                │
│  ┌─ Docker Compose ───────────────────────────┐   │
│  │  librenms (PHP-FPM + nginx, puerto 80)     │   │
│  │  mariadb (MySQL, puerto 3306)              │   │
│  │  redis                                     │   │
│  │  msmtpd (SMTP relay local)                 │   │
│  └────────────────────────────────────────────┘   │
│       │                                           │
│       ├── SNMP polls → dispositivos red           │
│       ├── LDAP bind → AD GDC01                    │
│       └── SMTP → Office 365 (alertas email)       │
└────────────────────────────────────────────────────┘
```

## Config

| Aspecto | Valor |
|---------|-------|
| **CT** | 210, Rocky Linux 9, 1GB RAM, 1 vCPU, 16GB disco |
| **IP** | 192.168.1.45/24 |
| **DNS** | nms.gidas.local |
| **Auth** | LDAP contra AD GDC01 |
| **DB** | MariaDB local (container) |
| **Redis** | Cache + session |

## Alertas

Estrategia multicanal:

| Canal | Transporte | Implementación |
|-------|-----------|----------------|
| Email | SMTP Office 365 | Transport nativo de LibreNMS |
| Telegram | Bot API | Transport nativo de LibreNMS |
| WhatsApp | Gateway / API | Via transporte custom o CallMeBot API |

Los destinatarios se configuran en la UI de LibreNMS → Alert Rules → Contacts.
