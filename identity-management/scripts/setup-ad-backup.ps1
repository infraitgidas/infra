# setup-ad-backup.ps1 — F5.2: Configurar backup de Active Directory
#
# Configura Windows Server Backup en DC1-GIDAS para backup diario
# y documenta el procedimiento de snapshot PVE.
#
# Uso:
#   Ejecutar como Administrador en DC1-GIDAS (192.168.1.117)
#
#   # Opción 1: Backup a disco local (E:)
#   .\setup-ad-backup.ps1 -BackupTarget "E:" -Schedule "02:00"
#
#   # Opción 2: Backup a ruta de red
#   .\setup-ad-backup.ps1 -BackupTarget "\\192.168.1.31\backups\ad" -Schedule "02:00"
#
# Diseño: identity-management/sdd/design.md §8
# Especificación: identity-management/sdd/specs.md §R10

param(
    [Parameter(Mandatory=$true)]
    [string]$BackupTarget,

    [Parameter(Mandatory=$false)]
    [string]$Schedule = "02:00",

    [Parameter(Mandatory=$false)]
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$LogFile = "C:\Windows\Logs\ad-backup-setup.log"

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp $Message" | Out-File -FilePath $LogFile -Append
    Write-Host "$timestamp $Message"
}

function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-WBAdmin {
    try {
        $null = Get-Command wbadmin -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

function Install-WBFeature {
    Write-Log "Instalando Windows Server Backup feature..."
    
    if ($DryRun) {
        Write-Log "[DRY-RUN] Install-WindowsFeature -Name Windows-Server-Backup"
        return
    }

    try {
        Install-WindowsFeature -Name Windows-Server-Backup -IncludeManagementTools
        Write-Log "✅ Windows Server Backup instalado"
    } catch {
        Write-Log "❌ Error instalando Windows Server Backup: $_"
        throw
    }
}

function Enable-BackupSchedule {
    param(
        [string]$Target,
        [string]$Time
    )

    Write-Log "Configurando backup diario a las $Time..."
    Write-Log "Target: $Target"

    if ($DryRun) {
        Write-Log "[DRY-RUN] wbadmin enable backup -addtarget:$Target -schedule:$Time -include:C: -allCritical -quiet"
        return
    }

    try {
        # Configurar backup programado diario
        $backupPolicy = New-WBPolicy
        $backupFileSpec = New-WBFileSpec -FileSpec "C:"
        Add-WBFileSpec -Policy $backupPolicy -FileSpec $backupFileSpec
        
        $backupTarget = New-WBBackupTarget -VolumePath $Target
        Add-WBBackupTarget -Policy $backupPolicy -Target $backupTarget
        
        # Incluir System State (critical para AD)
        Add-WBSystemState -Policy $backupPolicy
        
        # Configurar schedule
        $scheduleTime = [TimeSpan]::Parse($Time)
        Set-WBSchedule -Policy $backupPolicy -Schedule $scheduleTime
        
        # Aplicar política
        Set-WBPolicy -Policy $backupPolicy
        
        Write-Log "✅ Backup schedule configurado correctamente"
    } catch {
        Write-Log "❌ Error configurando backup: $_"
        throw
    }
}

function Test-BackupTarget {
    param([string]$Target)

    # Si es ruta UNC, verificar que sea accesible
    if ($Target -match "^\\\\") {
        if (Test-Path $Target) {
            Write-Log "✅ Target de red accesible: $Target"
        } else {
            Write-Log "⚠️  Target de red no accesible: $Target"
            Write-Log "   Verificar que el share exista y tenga permisos de escritura"
        }
    }
}

function Show-PVESnapshotProcedure {
    Write-Log ""
    Write-Log "=== Procedimiento Snapshot PVE ==="
    Write-Log ""
    Write-Log "Además del backup de Windows, tomar snapshot en PVE:"
    Write-Log ""
    Write-Log "  # Snapshot de DC1-GIDAS (VM ID 101 en pve-ad)"
    Write-Log "  qm snapshot 101 pre-backup-$(Get-Date -Format 'yyyyMMdd')"
    Write-Log ""
    Write-Log "  # Snapshot de FreeIPA (VM ID 102 en pve-ad)"
    Write-Log "  qm snapshot 102 pre-backup-$(Get-Date -Format 'yyyyMMdd')"
    Write-Log ""
    Write-Log "  # Programar snapshot semanal en PVE (opcional):"
    Write-Log "  # vzdump 101 --mode snapshot --compress zstd"
    Write-Log "  # vzdump 102 --mode snapshot --compress zstd"
}

function Show-VerificationProcedure {
    Write-Log ""
    Write-Log "=== Verificación Post-Configuración ==="
    Write-Log ""
    Write-Log "1. Verificar backup programado:"
    Write-Log "   wbadmin get versions"
    Write-Log ""
    Write-Log "2. Verificar última ejecución de backup:"
    Write-Log "   wbadmin get status"
    Write-Log ""
    Write-Log "3. Ejecutar backup manual de prueba:"
    Write-Log "   wbadmin start backup -backupTarget:$BackupTarget -include:C: -allCritical -quiet"
    Write-Log ""
    Write-Log "4. Verificar snapshots PVE:"
    Write-Log "   qm listsnapshot 101"
}

# === MAIN ===
Write-Log "=== Setup AD Backup — DC1-GIDAS ==="
Write-Log ""

# Verificar permisos
if (-not (Test-Admin)) {
    Write-Log "❌ Este script debe ejecutarse como Administrador"
    exit 1
}

# Verificar wbadmin
if (-not (Test-WBAdmin)) {
    Write-Log "⚠️  Windows Server Backup no está instalado"
    Install-WBFeature
} else {
    Write-Log "✅ Windows Server Backup ya está instalado"
}

echo ""
# Verificar target
Test-BackupTarget -Target $BackupTarget

echo ""
# Configurar backup
Enable-BackupSchedule -Target $BackupTarget -Time $Schedule

echo ""
# Mostrar procedimiento PVE
Show-PVESnapshotProcedure

echo ""
# Mostrar verificación
Show-VerificationProcedure

echo ""
Write-Log "=== Configuración de backup AD completada ==="
