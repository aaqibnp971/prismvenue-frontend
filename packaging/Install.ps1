# Prism Venues — per-user installer.
#
# Deliberately per-user (%LOCALAPPDATA%) rather than Program Files: no admin
# rights, no UAC prompt, and nothing to undo at the machine level. A venue
# manager can install this on their own laptop without calling IT.
#
# Run it via Install.cmd (which sets the execution policy for this one call),
# or directly:
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1

[CmdletBinding()]
param(
    # Skip the desktop shortcut (Start Menu entry is always created).
    [switch]$NoDesktopShortcut,
    # Install somewhere other than the default per-user location.
    [string]$InstallDir = "$env:LOCALAPPDATA\Programs\PrismVenues"
)

$ErrorActionPreference = 'Stop'

$AppName   = 'Prism Venues'
$ExeName   = 'prism_venues.exe'
$RegKey    = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\PrismVenues'
$SourceDir = Join-Path $PSScriptRoot 'app'

Write-Host ""
Write-Host "  Installing $AppName" -ForegroundColor Cyan
Write-Host "  -> $InstallDir"
Write-Host ""

if (-not (Test-Path (Join-Path $SourceDir $ExeName))) {
    Write-Host "  ERROR: $ExeName not found in '$SourceDir'." -ForegroundColor Red
    Write-Host "  Run this from the extracted folder, keeping the 'app' folder beside it."
    exit 1
}

# A running copy holds a lock on its own exe and DLLs, so an upgrade over the
# top of a live install fails halfway. Close it first.
$running = Get-Process -Name ([IO.Path]::GetFileNameWithoutExtension($ExeName)) -ErrorAction SilentlyContinue
if ($running) {
    Write-Host "  $AppName is running - closing it..."
    $running | Stop-Process -Force
    Start-Sleep -Milliseconds 700
}

# Replace rather than merge: a stale asset left behind from a previous version
# is worse than a slightly slower install. The engine re-extracts its stems
# from the bundle on next launch anyway (assets/audio/index.txt is the marker).
if (Test-Path $InstallDir) {
    Write-Host "  Removing the previous version..."
    Remove-Item -Path $InstallDir -Recurse -Force
}

New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
Write-Host "  Copying files..."
Copy-Item -Path (Join-Path $SourceDir '*') -Destination $InstallDir -Recurse -Force

# The uninstaller has to live inside the install directory, because the
# Add/Remove Programs entry points at it long after this folder is gone.
Copy-Item -Path (Join-Path $PSScriptRoot 'Uninstall.ps1') -Destination $InstallDir -Force

$exePath = Join-Path $InstallDir $ExeName
$shell   = New-Object -ComObject WScript.Shell

function New-AppShortcut {
    param([string]$LinkPath)
    $lnk = $shell.CreateShortcut($LinkPath)
    $lnk.TargetPath       = $exePath
    $lnk.WorkingDirectory = $InstallDir
    $lnk.IconLocation     = "$exePath,0"
    $lnk.Description      = 'Prism Venues - venue audio control'
    $lnk.Save()
}

$startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
New-AppShortcut -LinkPath (Join-Path $startMenu "$AppName.lnk")
Write-Host "  Start Menu shortcut created."

if (-not $NoDesktopShortcut) {
    New-AppShortcut -LinkPath (Join-Path ([Environment]::GetFolderPath('Desktop')) "$AppName.lnk")
    Write-Host "  Desktop shortcut created."
}

# Registering here is what makes this a real install rather than a folder of
# files: the app shows up in Settings > Apps with a working Uninstall button.
$version = (Get-Item $exePath).VersionInfo.ProductVersion
if ([string]::IsNullOrWhiteSpace($version)) { $version = '1.0.0' }
$size = [math]::Round(((Get-ChildItem $InstallDir -Recurse -File | Measure-Object -Property Length -Sum).Sum / 1KB))

New-Item -Path $RegKey -Force | Out-Null
New-ItemProperty -Path $RegKey -Name 'DisplayName'     -Value $AppName -PropertyType String -Force | Out-Null
New-ItemProperty -Path $RegKey -Name 'DisplayVersion'  -Value $version -PropertyType String -Force | Out-Null
New-ItemProperty -Path $RegKey -Name 'Publisher'       -Value 'Prism' -PropertyType String -Force | Out-Null
New-ItemProperty -Path $RegKey -Name 'InstallLocation' -Value $InstallDir -PropertyType String -Force | Out-Null
New-ItemProperty -Path $RegKey -Name 'DisplayIcon'     -Value $exePath -PropertyType String -Force | Out-Null
New-ItemProperty -Path $RegKey -Name 'EstimatedSize'   -Value $size -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $RegKey -Name 'NoModify'        -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $RegKey -Name 'NoRepair'        -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $RegKey -Name 'UninstallString' `
    -Value "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$InstallDir\Uninstall.ps1`"" `
    -PropertyType String -Force | Out-Null

# Audio is optional by design: the dashboard must keep working when the engine
# does not (lib/engine/prism_engine_native.dart swallows failures into status).
# Say so plainly rather than letting a silent room look like a broken install.
if (-not (Test-Path (Join-Path $InstallDir 'prism_core.dll'))) {
    Write-Host ""
    Write-Host "  NOTE: prism_core.dll is not in this bundle." -ForegroundColor Yellow
    Write-Host "  The app will run normally but the speakers will stay silent."
}

Write-Host ""
Write-Host "  Done. Launch it from the Start Menu or the desktop." -ForegroundColor Green
Write-Host "  Uninstall from Settings > Apps > Installed apps > $AppName."
Write-Host ""
