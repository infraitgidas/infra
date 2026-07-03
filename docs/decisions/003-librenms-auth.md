# ADR-003: Active Directory como mecanismo de autenticación y roles en LibreNMS

**Fecha:** 2026-07-03
**Contexto:** LibreNMS requiere autenticación de usuarios y control de acceso basado en roles. GIDAS ya cuenta con Active Directory (GDC01.local) como fuente de verdad de identidades. Se necesitaba definir cómo integrar AD sin duplicar usuarios ni gestionar roles manualmente.

## Decisión

**Usar el mecanismo nativo `active_directory` de LibreNMS** con mapeo de roles por grupos AD. NO usar el mecanismo genérico `ldap` ni crear usuarios locales.

## Alternativas Consideradas

| Alternativa | Descartada por |
|-------------|----------------|
| **Mecanismo `ldap` genérico** | No soporta `getRoles()` correctamente para el mapeo grupo→rol. El mecanismo `active_directory` es específico para AD e implementa `getRoles()` con soporte para grupos anidados. |
| **Usuarios locales MySQL** | No integrable con AD. Cada usuario requiere cuenta separada. Sin herencia de roles por grupo. El comando `user:add` advierte que no se podrá loguear con auth AD activo. |
| **Sincronización periódica (cron)** | Más complejo de mantener. El sync nativo via `getRoles()` se ejecuta en cada login, garantizando roles actualizados siempre. |

## Argumentos a Favor

1. **Integración nativa:** `ActiveDirectoryAuthorizer` autentica contra AD, crea usuarios automáticamente en el primer login, y asigna roles según grupo AD.
2. **Roles dinámicos:** `getRoles()` se ejecuta en cada login. Si un usuario cambia de grupo en AD, su rol en LibreNMS se actualiza automáticamente.
3. **Sin duplicación:** No hay que crear usuarios en dos lugares. AD es la fuente de verdad.
4. **Soporte de grupos anidados:** La función `userInGroup()` usa `LDAP_MATCHING_RULE_IN_CHAIN` para membresía anidada.
5. **Mínimo mantenimiento:** No hay scripts de sync que mantener. La configuración está en `config.php`.

## Riesgos y Mitigaciones

| Riesgo | Mitigación |
|--------|------------|
| `getRoles()` devuelve `[]` sin `auth_ad_groups` → `syncRoles([])` borra roles | `auth_ad_global_read=true` da rol mínimo a todos. `auth_ad_groups` mapea grupos existentes. |
| Servicio account `infrait` usada como personal | Documentado. Crear usuarios humanos separados en AD. |
| Grupo `G-IdentityAdmins` usado como admin por defecto | No es semánticamente correcto. Migrar a `gidas-admins` o `SRV-Monitoring` cuando se definan los grupos. |

## Configuración Final

```php
$config["auth_mechanism"] = "active_directory";
$config["auth_ad_domain"] = "GDC01.local";
$config["auth_ad_url"] = "ldap://192.168.1.117";
$config["auth_ad_base_dn"] = "DC=GDC01,DC=local";
$config["auth_ad_binduser"] = "infrait";
$config["auth_ad_bindpassword"] = "Gidas2026!";
$config["auth_ad_require_groupmembership"] = false;
$config["auth_ad_global_read"] = true;
$config["auth_ad_groups"] = array(
    "gidas-admins"       => array("roles" => array("admin")),
    "SRV-Monitoring"     => array("roles" => array("admin")),
    "G-IdentityAdmins"   => array("roles" => array("admin")),
    "gidas-pve-admin"    => array("roles" => array("global-read")),
    "gidas-pve-viewer"   => array("roles" => array("global-read")),
);
```

### Mapeo Resultante

| Grupo AD | Rol LNMS | Alcance |
|----------|----------|---------|
| `gidas-admins` | admin | Full acceso |
| `SRV-Monitoring` | admin | Full acceso |
| `G-IdentityAdmins` | admin | Full acceso |
| `gidas-pve-admin` | global-read | Solo lectura |
| `gidas-pve-viewer` | global-read | Solo lectura |
| Cualquier otro | global-read | Por defecto (`auth_ad_global_read`) |

## Próximos Pasos

1. Definir grupos AD definitivos para NMS (migrar de `G-IdentityAdmins` a `gidas-admins`)
2. Agregar miembros a `SRV-Monitoring`
3. Evaluar si se necesitan roles más granulares (ej: `user` para solo alertas)

## Estado

**Aceptada e Implementada**
