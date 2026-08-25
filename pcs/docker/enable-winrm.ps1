<#
.SYNOPSIS
    One-time bootstrap: enable WinRM on this PC for internal LAN management.

.USAGE
    Run interactively in an ELEVATED PowerShell window on the target PC:
        .\enable-winrm.ps1

.NOTES
    Keeps management traffic restricted: HTTP (5985) listener, firewall scoped
    to LocalSubnet, and Basic authentication over the network stays disabled
    (NTLM/Kerberos only, matching the deploy orchestrator).
#>

#Requires -RunAsAdministrator

$ErrorActionPreference = 'Stop'

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
