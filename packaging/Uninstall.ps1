# Prism Venues — per-user uninstaller.
#
# Reached from Settings > Apps, or run directly. Removes the install directory,
# both shortcuts and the Add/Remove Programs entry.

[CmdletBinding()]
param([string]$InstallDir = "$env:LOCALAPPDATA\Programs\PrismVenues")

$ErrorActionPreference = 'Stop'

$AppName = 'Prism Venues'
$RegKey  = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\PrismVenues'

# A script cannot reliably delete the directory it is running from, and the
# installed copy of this file lives inside exactly that directory. Re-launch
# from TEMP so the delete below always has a free hand.
if ($PSScriptRoot -and $PSScriptRoot.TrimEnd('\') -ieq $InstallDir.TrimEnd('\')) {
    $relay = Join-Path $env:TEMP 'PrismVenues-Uninstall.ps1'
    Copy-Item -Path $PSCommandPath -Destination $relay -Force
    Start-Process -FilePath 'powershell.exe' `
        -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$relay`"",
                        '-InstallDir', "`"$InstallDir`"")
    return
}

Write-Host ""
Write-Host "  Uninstalling $AppName" -ForegroundColor Cyan
Write-Host ""

$running = Get-Process -Name 'prism_venues' -ErrorAction SilentlyContinue
if ($running) {
    Write-Host "  Closing $AppName..."
    $running | Stop-Process -Force
    Start-Sleep -Milliseconds 700
}

foreach ($dir in @((Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'),
                   [Environment]::GetFolderPath('Desktop'))) {
    $lnk = Join-Path $dir "$AppName.lnk"
    if (Test-Path $lnk) {
        Remove-Item $lnk -Force
        Write-Host "  Removed shortcut: $lnk"
    }
}

if (Test-Path $InstallDir) {
    Remove-Item -Path $InstallDir -Recurse -Force
    Write-Host "  Removed $InstallDir"
}

if (Test-Path $RegKey) {
    Remove-Item -Path $RegKey -Recurse -Force
    Write-Host "  Removed the Add/Remove Programs entry."
}

# Left deliberately: the saved sign-in token (Windows Credential Manager, via
# flutter_secure_storage), the remembered theme, and the extracted audio stems
# under %APPDATA%\com.example\prism_venues. Wiping them would sign the user out
# of a reinstall for no reason. Delete that folder by hand for a clean slate.

Write-Host ""
Write-Host "  Done." -ForegroundColor Green
Write-Host ""
Start-Sleep -Seconds 2
