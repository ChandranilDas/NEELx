<#
.SYNOPSIS
    NEELx for Windows 11 — Clean Uninstaller & WinLogon Rollback.

.DESCRIPTION
    Removes NEELx app binaries (%LOCALAPPDATA%\NEELx-App), Start Menu shortcut, and any
    optional WinLogon Credential Provider registry entry. Preserves your DPAPI biometric
    vault (%LOCALAPPDATA%\NEELx) by default unless -WipeVault is specified.

.EXAMPLE
    .\uninstall.ps1

.EXAMPLE
    .\uninstall.ps1 -WipeVault
#>
[CmdletBinding()]
param(
    [switch]$WipeVault
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$InstallDir = Join-Path $env:LOCALAPPDATA "NEELx-App"
$VaultDir = Join-Path $env:LOCALAPPDATA "NEELx"
$ShortcutPath = Join-Path ([Environment]::GetFolderPath("Programs")) "NEELx.lnk"
$CredProviderRegPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\Credential Providers\{9F4D7B21-6C1E-4A3E-8D25-E8477B14A902}"

Write-Host "Stopping NEELx if running..."
Get-Process -Name "NEELx.Windows" -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 250

if (Test-Path $InstallDir) {
    Remove-Item -Path $InstallDir -Recurse -Force
    Write-Host "Removed app binaries: $InstallDir" -ForegroundColor Green
}

if (Test-Path $ShortcutPath) {
    Remove-Item -Path $ShortcutPath -Force
    Write-Host "Removed Start Menu shortcut: $ShortcutPath" -ForegroundColor Green
}

if (Test-Path $CredProviderRegPath) {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($isAdmin) {
        Remove-Item -Path $CredProviderRegPath -Recurse -Force
        Write-Host "Unregistered optional WinLogon Credential Provider." -ForegroundColor Green
    } else {
        Write-Warning "Optional WinLogon Credential Provider registry key exists. Re-run uninstall.ps1 as Administrator to unregister it."
    }
}

if ($WipeVault) {
    if (Test-Path $VaultDir) {
        Remove-Item -Path $VaultDir -Recurse -Force
        Write-Host "Wiped DPAPI biometric vault & models: $VaultDir" -ForegroundColor Yellow
    }
} else {
    Write-Host "Preserved your DPAPI biometric vault at $VaultDir (pass -WipeVault to delete)." -ForegroundColor Cyan
}

Write-Host "NEELx uninstall complete." -ForegroundColor Green
