<#
.SYNOPSIS
    Idempotent Docker Desktop installer for GIDAS domain PCs (Windows 10/11).

.DESCRIPTION
    Runs ON the target PC (interactive session or via WinRM). Performs preflight
    checks, enables the WSL2/VirtualMachinePlatform Windows features, installs
    Docker Desktop when missing, and grants the domain group access through the
    local 'docker-users' group.

    Emits a machine-parseable final line on stdout:
        [RESULT] STATE=<OK|REBOOT_REQUIRED|FAILED> detail=<short reason>

.NOTES
    Windows PowerShell 5.1 compatible. Must run elevated. Never echoes or
    embeds any credential.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$script:RebootPending = $false

function Write-Info { param([string]$Message) Write-Output "[INFO] $Message" }
function Write-WarnMsg { param([string]$Message) Write-Output "[WARN] $Message" }

function ConvertTo-CleanDetail {
    param([string]$Text)
    $cleaned = (($Text -replace '\r?\n', ' ') -replace '\s+', ' ').Trim()
    if ($cleaned.Length -gt 100) { $cleaned = $cleaned.Substring(0, 100) }
    return $cleaned
}

function Complete-Run {
    param([string]$State, [string]$Detail)
    Write-Output ("[RESULT] STATE={0} detail={1}" -f $State, (ConvertTo-CleanDetail $Detail))
    if ($State -eq 'FAILED') { exit 1 }
    exit 0
}

# --- 1. Elevation check (abort early, clear message) -------------------------

$identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Complete-Run 'FAILED' 'not elevated: run from an administrator session (WinRM tokens must be elevated too)'
}

try {
    # --- 2. Preflight checks -------------------------------------------------

    $os = Get-CimInstance Win32_OperatingSystem
    $build = [int]$os.BuildNumber
    Write-Info ("Detected OS '{0}' build {1}" -f $os.Caption.Trim(), $build)
    if ($build -lt 19044) {
        Complete-Run 'FAILED' ("OS build {0} unsupported, need >= 19044 (Windows 10 21H2 or newer)" -f $build)
    }

    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    if ($cpu.VirtualizationFirmwareEnabled) {
        Write-Info 'Firmware virtualization reported as enabled.'
    } else {
        # Non-fatal: Hyper-V/WSL2 can mask this value; Docker will fail later if truly off.
        Write-WarnMsg 'Firmware virtualization not reported enabled; if Docker fails to start its VM, enable VT-x/AMD-V (and SLAT) in BIOS/UEFI.'
    }

    $computerSystem = Get-CimInstance Win32_ComputerSystem
    if ($computerSystem.Domain -ieq 'GDC01.local') {
        Write-Info 'Domain membership confirmed (GDC01.local).'
    } else {
        Write-WarnMsg ("Computer is joined to '{0}', expected 'GDC01.local'; continuing anyway." -f $computerSystem.Domain)
    }

    $freeGb = [math]::Round((Get-PSDrive C).Free / 1GB, 1)
    Write-Info ("Free space on C: {0} GB." -f $freeGb)
    if ($freeGb -lt 10) {
        Complete-Run 'FAILED' ("only {0} GB free on C:, need at least 10 GB" -f $freeGb)
    }

    # --- 3. Windows features (WSL2 backend prerequisites) --------------------

    foreach ($feature in @('Microsoft-Windows-Subsystem-Linux', 'VirtualMachinePlatform')) {
        Write-Info ("Enabling Windows feature '{0}' via DISM..." -f $feature)
        $null = & dism.exe /Online /Enable-Feature "/FeatureName:$feature" /All /NoRestart
        switch ($LASTEXITCODE) {
            0     { Write-Info ("Feature '{0}' enabled or already present." -f $feature) }
            3010  { Write-Info ("Feature '{0}' enabled, restart pending." -f $feature); $script:RebootPending = $true }
            default { Write-WarnMsg ("DISM exited {0} enabling '{1}' (tolerated; install continues)." -f $LASTEXITCODE, $feature) }
        }
    }

    Write-Info 'Updating WSL kernel (best effort)...'
    try {
        $null = & wsl.exe --update 2>&1
        if ($LASTEXITCODE -ne 0) { Write-WarnMsg ("wsl --update exited {0} (tolerated)." -f $LASTEXITCODE) }
    } catch {
        Write-WarnMsg 'wsl --update unavailable on this build (tolerated).'
    }

    # --- 4. Docker Desktop installation --------------------------------------

    $dockerExe = Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'
    if (Test-Path $dockerExe) {
        Write-Info 'Docker Desktop already installed, skipping download/install.'
    } else {
        $url = 'https://desktop.docker.com/win/main/amd64/Docker%20Desktop%20Installer.exe'
        $installer = Join-Path $env:TEMP 'DockerDesktopInstaller.exe'
        Write-Info ("Downloading Docker Desktop installer to '{0}'..." -f $installer)
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $url -OutFile $installer -UseBasicParsing

        Write-Info 'Installing Docker Desktop (quiet, WSL2 backend). This can take several minutes...'
        $process = Start-Process -FilePath $installer `
            -ArgumentList 'install', '--quiet', '--accept-license', '--backend=wsl-2' `
            -Wait -PassThru
        $installerExit = $process.ExitCode
        switch ($installerExit) {
            0     { Write-Info 'Docker Desktop installed successfully.' }
            3010  { Write-Info 'Docker Desktop installed, restart required.'; $script:RebootPending = $true }
            default { Complete-Run 'FAILED' ("Docker Desktop installer exited with code {0}" -f $installerExit) }
        }

        if (-not (Test-Path $dockerExe)) {
            Complete-Run 'FAILED' 'Docker Desktop executable not found after installation'
        }
    }

    # --- 5. Local group configuration ----------------------------------------

    $groupName = 'docker-users'
    if (-not (Get-LocalGroup -Name $groupName -ErrorAction SilentlyContinue)) {
        New-LocalGroup -Name $groupName -Description 'Docker Desktop application users' | Out-Null
        Write-Info ("Created local group '{0}'." -f $groupName)
    } else {
        Write-Info ("Local group '{0}' already exists." -f $groupName)
    }

    $domainGroup = 'GDC01\Domain Users'
    $existingMember = Get-LocalGroupMember -Group $groupName -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like '*Domain Users*' } |
        Select-Object -First 1
    if ($existingMember) {
        Write-Info ("'{0}' is already a member of '{1}'." -f $domainGroup, $groupName)
    } else {
        try {
            Add-LocalGroupMember -Group $groupName -Member $domainGroup -ErrorAction Stop
            Write-Info ("Added '{0}' to '{1}'." -f $domainGroup, $groupName)
        } catch {
            # Tolerate the idempotent case: member already present (0x89a / AlreadyPresent).
            $alreadyMember = ($_.CategoryInfo.Category -eq 'AlreadyPresent') -or
                             ($_.Exception.Message -match 'already a member')
            if ($alreadyMember) {
                Write-Info ("'{0}' already a member of '{1}' (tolerated)." -f $domainGroup, $groupName)
            } else {
                Complete-Run 'FAILED' ("cannot add '{0}' to '{1}': {2}" -f $domainGroup, $groupName, $_.Exception.Message)
            }
        }
    }

    # --- 6. Final state -------------------------------------------------------

    if ($script:RebootPending) {
        Complete-Run 'REBOOT_REQUIRED' 'windows features or installer require a restart'
    }
    Complete-Run 'OK' 'docker desktop present, docker-users configured'
} catch {
    Complete-Run 'FAILED' ('unexpected error: ' + $_.Exception.Message)
}
