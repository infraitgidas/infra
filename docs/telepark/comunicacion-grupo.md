# Comunicación al grupo Telepark — Herramientas de desarrollo

> **Canal de salida**: email / chat del grupo
> **Fecha**: 2026-08-27
> **Autores**: Administración de Infraestructura (GDC01)

Mensaje listo para enviar. Se mantiene en el repo como registro y para
reutilizarlo cuando haya novedades.

---

## Asunto: Nuevas herramientas de desarrollo para el grupo Telepark ✨

Hola, equipo Telepark 👋

Les compartimos las **herramientas de desarrollo** que ya están disponibles para
el grupo en la VM `telepark-dev` (192.168.1.48). Todo se accede con su
**usuario de dominio** (el mismo con el que entran a su PC).

---

### ✅ Lo que ya pueden usar

| Herramienta | ¿Para qué? | Cómo acceder |
|-------------|-----------|--------------|
| **SSH** | Terminal de la VM | `ssh <usuario>@gdc01.local@192.168.1.48` |
| **SSH desde casa** | Conectarse fuera de la oficina | Card "SSH Telepark" en el Portal GIDAS |
| **Docker / Compose** | Correr y orquestar contenedores | Por terminal (SSH) |
| **Portainer** | Gestión visual de Docker | `https://192.168.1.48:9443` |
| **Ver tu app en el navegador** | Revisar cualquier deploy por puerto | `https://<portal>/port/<puerto>/` |

### ✨ Lo nuevo: ver tus despliegues en el navegador (cualquier puerto)

Ahora **no necesitás estar en la red de la empresa** para ver tu aplicación
corriendo. Si levantás un servicio en cualquier puerto (por ejemplo `8080`),
lo abrís desde tu navegador con:

```
https://<portal>/port/8080/
```

Solo tenés que estar logueado en el **Portal GIDAS** y pertenecer al grupo
`PROY-Telepark`. Funciona para HTTP y WebSockets, es decir, también para apps
con conexiones en tiempo real.

> 💡 **Puertos internos**: no utilicen puertos del 1 al 1024 ni puertos
> reservados del sistema (SSH `22`, Cockpit `9090`, Portainer `9443`, etc.).
> Para sus apps usen puertos tipo `8080`, `3000`, `9000`, etc.

---

### 🔜 En el roadmap (mejora a futuro)

- **IDE (VS Code) en el navegador**: un editor completo (extensiones, terminal
  y Git) que corre en la VM y se abre desde el navegador, sin instalar nada.
  **Queda pendiente de validación final** y lo vamos a habilitar en una próxima
  etapa. No es parte de la entrega actual.

---

### 📖 Documentación completa

Tenemos un **manual del desarrollador** con todos los detalles de uso, atajos y
solución de problemas. Sin dudas avisen si les pasa algo raro o si quieren que
agreguemos herramientas.

¡Que disfruten las herramientas! Cualquier duda, por acá.

Saludos,
**Infra GDC01**
