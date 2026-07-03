# Dominio gidas.frlp.utn.edu.ar — Gestión y Contacto

> Documentación de contacto y procedimientos para gestionar el dominio institucional
> del Grupo GIDAS en la Universidad Tecnológica Nacional - Facultad Regional La Plata.

---

## Sitio Web

| Aspecto | Detalle |
|---------|---------|
| **URL** | `https://gidas.frlp.utn.edu.ar` |
| **CMS** | Drupal (versión por confirmar) |
| **Hosting** | UTN-FRLP (servidores institucionales) |
| **IP pública** | `200.10.126.117` |
| **Admin** | Por determinar — contactar al Departamento de Sistemas FRLP |

---

## Contacto para Cambios

> ⏳ **PENDIENTE**: Identificar al administrador del sitio y documentar el contacto aquí.

**Posibles vías de contacto**:
- Departamento de Sistemas FRLP
- Secretaría de Ciencia y Técnica de FRLP
- Webmaster institucional

---

## Servicios GIDAS

### Acceso Público vs Privado

| Tipo | Plataforma | URL | Acceso |
|------|-----------|-----|--------|
| 🔓 **Público** | Drupal institucional | `https://gidas.frlp.utn.edu.ar` | Cualquier persona |
| 🔒 **Privado** | Portal GIDAS | `https://portal.gidas.local` | Miembros GIDAS via Twingate/LAN |
| 🔒 **Privado** | Servicios internos | `*.gidas.local` | Miembros GIDAS via Twingate/LAN |

### Enlaces solicitados para Drupal

| Enlace | URL | Descripción |
|--------|-----|-------------|
| Portal GIDAS | `https://portal.gidas.local` | Acceso a todas las herramientas internas |
| GitLab | `https://gitlab.gidas.local` | Repositorios y CI/CD |
| Redmine | `https://redmine.gidas.local` | Gestión de proyectos |
| LibreNMS | `https://nms.gidas.local` | Monitoreo de red |
| Grafana | `http://192.168.1.205:3000` | Métricas y dashboards |

---

## Correo Electrónico

| Dirección | Uso | Gestión |
|-----------|-----|---------|
| `gidas@frlp.utn.edu.ar` | Contacto institucional del grupo | UTN-FRLP |
| `infrait@frlp.utn.edu.ar` | Notificaciones del sistema (SMTP Office 365) | Equipo GIDAS |

---

## Acceso Remoto (Twingate)

Para acceder a los servicios GIDAS desde fuera de la UTN:
1. Instalar [Twingate](https://portal.twingate.com) en el dispositivo
2. Solicitar acceso al administrador de GIDAS
3. Una vez conectado, acceder a `https://portal.gidas.local`

---

*Última actualización: 2026-07-03*
