<#
.SYNOPSIS
    One-time bootstrap: enable WinRM on this PC for internal LAN management.

.USAGE
    Run interactively in an ELEVATED PowerShell window on the target PC:
        .\enable-winrm.ps1 [-AllowRemoteLocalAdmin]

.NOTES
    Keeps management traffic restricted: HTTP (5985) listener, firewall scoped
    to LocalSubnet, and Basic authentication over the network stays disabled
    (NTLM/Kerberos only, matching the deploy orchestrator).

    -AllowRemoteLocalAdmin sets LocalAccountTokenFilterPolicy=1 so REMOTE
    sessions with a LOCAL admin account receive a full (non-filtered) token.
    Without it, remote local-admin logons are UAC-filtered and every elevated
    operation (DISM, installer, group changes) fails with access denied.
    Only needed while managing these PCs with LOCAL admin accounts; domain
    admin credentials do not require this. Rollback: set the value to 0.
#>

#Requires -RunAsAdministrator

param(
    # Grant remote LOCAL admins a full token (see NOTES). Default: off.
    [switch]$AllowRemoteLocalAdmin
)

$ErrorActionPreference = 'Stop'

if ($AllowRemoteLocalAdmin) {
    Write-Host '[0/4] Enabling full-token remote sessions for LOCAL admin accounts (LocalAccountTokenFilterPolicy=1)...'
    $regPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
    Set-ItemProperty -Path $regPath -Name LocalAccountTokenFilterPolicy -Value 1 -Type DWord
    Write-Host '      done. Rollback later with:  Set-ItemProperty -Path'
    Write-Host "      '$regPath' -Name LocalAccountTokenFilterPolicy -Value 0"
}

Write-Host '[1/4] Enabling PowerShell remoting (WinRM service, listener, default firewall rules)...'
Enable-PSRemoting -Force -SkipNetworkProfileCheck | Out-Null

Write-Host '[2/4] Disabling Basic auth on the WinRM service (NTLM/Kerberos only)...'
Set-Item -Path WSMan:\localhost\Service\Auth\Basic -Value $false

Write-Host '[3/4] Restricting WinRM HTTP-In firewall rules to LocalSubnet...'
Get-NetFirewallRule -Name 'WINRM-HTTP-In-TCP*' -ErrorAction SilentlyContinue |
    ForEach-Object {
        $rule = $_
        try {
            Set-NetFirewallRule -Name $rule.Name -RemoteAddress LocalSubnet -ErrorAction Stop
            Write-Host ("      scoped rule '{0}' to LocalSubnet" -f $rule.Name)
        } catch {
            Write-Warning ("could not scope rule '{0}': {1}" -f $rule.Name, $_.Exception.Message)
        }
    }

Write-Host '[4/4] Setting WinRM service startup to Automatic and starting it...'
Set-Service -Name WinRM -StartupType Automatic
Start-Service -Name WinRM   # idempotent if already running

Write-Host ''
Write-Host 'WinRM is enabled. Current service state:'
Get-Service -Name WinRM | Format-Table -AutoSize Status, Name, DisplayName
Write-Host 'Verify from the Linux management host with:  Test-WSMan -ComputerName <this-pc>'
