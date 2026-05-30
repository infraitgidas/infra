# Baja de Usuario — Offboarding

> Procedimiento para deshabilitar/eliminar un usuario del sistema de identidad del Grupo Gidas.

## Disparadores

- El investigador/becario/estudiante finaliza su vínculo con el grupo
- Cuenta comprometida o inactiva por más de 90 días
- Solicitud del responsable del subgrupo

## Paso a Paso

### 1. Deshabilitar usuario en AD

```powershell
# Conectar a VM-DC1
ssh Administrator@192.168.1.117

# Deshabilitar cuenta (RECOMENDADO — preserva grupos y SID)
Disable-ADAccount -Identity "jperez"

# Verificar estado
Get-ADUser jperez -Properties Enabled | fl Name, Enabled
```

> **Nota**: Deshabilitar es preferible a eliminar. Si en el futuro el usuario regresa, solo hay que re-habilitar la cuenta y la pertenencia a grupos se mantiene.

### 2. (Alternativa) Eliminar usuario del AD

Solo si la política del grupo requiere eliminación definitiva:

```powershell
Remove-ADUser -Identity "jperez" -Confirm:$false
```

### 3. Limpiar HBAC rules (si aplica)

Las HBAC rules en FreeIPA referencian grupos, no usuarios individuales. Al deshabilitar/eliminar el usuario del AD, FreeIPA lo detecta via trust y automáticamente le niega acceso. No requiere acción manual en FreeIPA.

### 4. Revocar sesiones activas

Si el usuario tiene sesiones SSH activas, forzar cierre:

```bash
# En cada host donde el usuario podría tener sesión
ssh root@<host>
pkill -KILL -u jperez  # matar procesos del usuario
# Verificar sesiones activas
who | grep jperez
```

### 5. Documentar la baja

```bash
# Registrar en el changelog
echo "2026-05-29: Baja de jperez (Juan Pérez) - gidas-rojo" >> tasks/completed/offboarding.log
```

## Post-Baja

- [ ] Cuenta deshabilitada en AD (o eliminada)
- [ ] Sesiones activas revocadas
- [ ] Acceso a recursos verificado (intentar SSH → debe fallar)
- [ ] Grupos de AD preservados (si es deshabilitación)
- [ ] Registro en el changelog

## Restauración (si fue deshabilitación)

```powershell
Enable-ADAccount -Identity "jperez"
```

El usuario recupera acceso inmediato a los hosts de su grupo (vía HBAC + trust).

## Tiempo Estimado

5-10 minutos.
