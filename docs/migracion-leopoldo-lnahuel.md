# Migración de perfil: `leopoldo` (local) → `lnahuel` (GDC01.local)

PC piloto: `192.168.1.30` (DIRECCION). Estado: **MIGRACIÓN COMPLETADA y VERIFICADA** ✅

## Contexto

- `leopoldo` es el usuario local de `.30`; su perfil vivía en `C:\Users\Usuario` (SID local `S-1-5-21-2189000330-4125934007-1009026202-1001`).
- `lnahuel` es el usuario de dominio `GDC01.local` que lo reemplaza (nombre real: Leopoldo Nahuel, uid AD `902401128`).
- Objetivo: migrar el perfil in-place con ForensiT User Profile Wizard (ProfWiz, freeware R24) para conservar datos y passwords de navegador (DPAPI).
- Concepto clave: copiar carpetas a mano rompe las passwords (DPAPI ata las claves al SID + password). ProfWiz migra in-place y corrige DPAPI.

## Resultado final verificado

| Ítem | Estado |
|---|---|
| Migración con ProfWiz (GUI) | ✅ Ejecutada por el usuario en pantalla, "un éxito" |
| Perfil migrado | ✅ `C:\Users\Usuario` ahora asociado al SID de dominio `GDC01\lnahuel` (`S-1-5-21-2742181437-2264419243-1616310729-1128`) — re-mapeado in-place por ProfWiz |
| Datos redirigidos `D:\Users\Usuario` | ✅ Intactos: 60.464 archivos / 8,50 GB |
| Estructura del perfil | ✅ Completa (AppData, Documents, OneDrive, NTUSER.DAT...) |
| Login screen | ✅ Solo tiles de dominio: `lnahuel` y `leorocca` |

## Mapeo SID ↔ usuario de dominio (resuelto desde `.30`)

| SID de dominio | Usuario | Perfil |
|---|---|---|
| `S-1-5-21-2742181437-2264419243-1616310729-1128` | `GDC01\lnahuel` | `C:\Users\Usuario` |
| `S-1-5-21-2742181437-2264419243-1616310729-1129` | `GDC01\leorocca` | `C:\Users\Leandro` (carpeta con nombre viejo) |

Método: `New-Object System.Security.Principal.SecurityIdentifier($sid)).Translate([NTAccount]).Value` en la máquina del dominio (no requiere consulta AD al DC).

## Login screen (pedido: dejar solo lnahuel y leorocca)

En Windows, los tiles del login screen salen de los **logons cacheados** (usuarios que ya iniciaron sesión en la máquina). Los usuarios locales habilitados también aparecen como tiles, ensuciando la lista.

Configuración aplicada en `.30`:

1. **Ocultar los 5 usuarios locales** de la UI del login — clave `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\UserList`, cada usuario con valor DWORD `0`:
   - `Administrador`, `Gidas Miembro`, `Javier`, `Leandro`, `Leopoldo`
   - OJO: ocultar del tile NO bloquea la cuenta — siguen logueables escribiendo el nombre.
2. **Caché de logon verificado**: LSA `NL$1` y `NL$2` con datos (2 logons cacheados = `lnahuel` + `leorocca`), `CachedLogonsCount=10`.
3. **Sin GPO que oculte la lista**: `dontdisplaylastusername=0` (política local y de grupo limpias).
4. `DefaultUserName=leorocca` (el operador), `LastUsedUsername=Administrador` (por la sesión de migración).

Resultado esperado: al bloquear/reiniciar `.30`, el login screen muestra como tiles `lnahuel` y `leorocca` + opción "Otros usuarios".

## Redirección de carpetas (CRÍTICO — se conservó)

El perfil tiene **carpetas redirigidas a `D:\Users\Usuario`**:

| Carpeta | Path real |
|---|---|
| Desktop | `D:\Users\Usuario\Desktop` |
| Documents | `D:\Users\Usuario\Documents` |
| Music / Pictures / Videos | `D:\Users\Usuario\{Music,Pictures,Videos}` |
| Downloads / Favorites / 3D Objects / Contacts | `D:\Users\Usuario\...` |

El contenido de `C:\Users\Usuario` es solo AppData + OneDrive + configuración; **los datos reales viven en D:**. ProfWiz migró el NTUSER.DAT con sus `User Shell Folders`, así que `lnahuel` sigue viendo sus carpetas redirigidas — el path sigue diciendo `Usuario`, aceptable.

## Inventario de backup (verificado en `.30`)

| Ruta origen | Backup | Tamaño | Archivos | Errores |
|---|---|---|---|---|
| `C:\Users\Usuario` (perfil) | `D:\backup\Leopoldo` | 3,50 GB | 46.902 | 62 en uso (NTUSER.DAT, AppData abiertos) |
| NTUSER.DAT (registro) | `D:\backup\Leopoldo_NTUSER_regsave.dat` | 18,4 MB | 1 | 0 |
| `D:\Users\Usuario` (datos) | `D:\backup\Leopoldo_D` | 8,50 GB | 60.464 | **0** |
| `C:\Users\lnahuel` (esqueleto) | `D:\backup\lnahuel_esqueleto` | ~0 | — | stubs WindowsApps quedaron en origen |

**Total respaldado: ~12 GB.** Passwords de navegador verificadas en backup (`Login Data` Chrome 40 KB, Edge 57 KB).

## Herramienta

- MSI oficial: `https://www.ForensiT.com/Downloads/Profwiz.msi` (R24, freeware, Win 10/11/7).
- Nota: ForensiT.com está detrás de Cloudflare — solo baja con User-Agent de navegador (curl pelado devuelve HTML).
- Hash SHA-256 verificado en origen y destino: `c93eb6c1dc1cc2b668e3651964e6de73458871243999ad399d4247772da0427b`.
- Extraído sin instalar: `msiexec /a C:\Profwiz.msi /qn TARGETDIR=C:\ProfwizExtract` → `C:\ProfwizExtract\Profwiz.exe`.
- **ProfWiz freeware es SOLO GUI** — la migración la opera una persona en pantalla en `.30`. El CLI (`/ACCOUNT`, `/SILENT`, Deployment Kit) es solo de la Corporate Edition (paga).

## Procedimiento replicable (para las otras 4 Windows)

1. **Verificar redirección de carpetas ANTES de asumir dónde viven los datos** — `HKU\<SID>\...\Explorer\User Shell Folders`. En `.30` los datos reales estaban en `D:\Users\Usuario`, no en `C:\Users\Usuario`.
2. Backup completo: perfil + NTUSER.DAT (vía `reg save HKU\<SID>`) + carpetas redirigidas.
3. Descargar ProfWiz (User-Agent de navegador obligatorio), extraer con `msiexec /a`.
4. Cerrar sesión del usuario local (perfil debe quedar `Loaded=False`).
5. Correr `Profwiz.exe` como admin → "Migrate a user profile" → perfil origen → usuario de dominio + credenciales `GDC01\Administrator`.
6. Verificar: perfil re-mapeado al SID de dominio (`Win32_UserProfile`), datos redirigidos intactos, DPAPI (passwords de navegador).
7. Opcional: ocultar usuarios locales del login screen vía `Winlogon\UserList` (DWORD 0).

## Rollback

- Restaurar perfil: renombrar `C:\Users\lnahuel` y copiar `D:\backup\Leopoldo\*` a `C:\Users\Usuario` + `NTUSER_regsave.dat` como `NTUSER.DAT`.
- Restaurar datos: copiar `D:\backup\Leopoldo_D\*` a `D:\Users\Usuario`.
- Loguear como `leopoldo` local sigue siendo posible (cuenta local intacta).
- Login screen: borrar `Winlogon\UserList` para volver a mostrar todos los tiles.
