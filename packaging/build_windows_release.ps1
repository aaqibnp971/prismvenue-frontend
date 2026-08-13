# Build, stage and zip a distributable Windows x64 build of Prism Venues.
#
# Run from anywhere:
#   powershell -NoProfile -ExecutionPolicy Bypass -File packaging\build_windows_release.ps1
#
# Two things this does that `flutter build windows` alone does not, and both are
# why hand-built bundles have shipped broken before:
#
#  1. It bakes the backend URL in. PRISM_API_BASE_URL is a --dart-define, read
#     by a `const String.fromEnvironment` (lib/app/env.dart) - so it is fixed at
#     COMPILE time. There is no runtime setting, no config file to edit beside
#     the exe. A bundle built without it silently points at localhost:8000.
#  2. It copies prism_core.dll in. Nothing in the Flutter Windows CMake does;
#     PrismCore.defaultLibrary() just calls DynamicLibrary.open('prism_core.dll'),
#     which resolves next to the executable. Without this step the app runs
#     perfectly and the room stays silent.

[CmdletBinding()]
param(
    # Backend the built app will talk to. Default matches dart_config.json.
    [string]$ApiBaseUrl = 'https://dgzniqfquuwoelxgozrt.supabase.co/functions/v1/api',
    # The engine DLL. Built with: cmake -S . -B build/shared-win -DPRISM_BUILD_SHARED=ON
    [string]$EngineDll  = '..\prism-core\build\shared-win\core\Release\prism_core.dll',
    # Ship without audio (dashboard only).
    [switch]$NoEngine,
    # Reuse the existing build/windows output instead of rebuilding.
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'

$RepoRoot  = Split-Path -Parent $PSScriptRoot
$Runner    = Join-Path $RepoRoot 'build\windows\x64\runner\Release'
$DistRoot  = Join-Path $RepoRoot 'dist'
$StageName = 'PrismVenues-windows-x64'
$Stage     = Join-Path $DistRoot $StageName
$Zip       = Join-Path $DistRoot "$StageName.zip"

Push-Location $RepoRoot
try {
    if (-not $SkipBuild) {
        Write-Host "==> flutter build windows --release" -ForegroundColor Cyan
        Write-Host "    PRISM_API_BASE_URL = $ApiBaseUrl"
        flutter build windows --release --dart-define=PRISM_API_BASE_URL=$ApiBaseUrl
        if ($LASTEXITCODE -ne 0) { throw "flutter build failed with exit code $LASTEXITCODE" }
    }

    if (-not (Test-Path (Join-Path $Runner 'prism_venues.exe'))) {
        throw "No build output at $Runner"
    }

    Write-Host "==> Staging $Stage" -ForegroundColor Cyan
    if (Test-Path $Stage) { Remove-Item $Stage -Recurse -Force }
    $AppDir = Join-Path $Stage 'app'
    New-Item -ItemType Directory -Path $AppDir -Force | Out-Null
    Copy-Item -Path (Join-Path $Runner '*') -Destination $AppDir -Recurse -Force

    if (-not $NoEngine) {
        $dllPath = if ([IO.Path]::IsPathRooted($EngineDll)) { $EngineDll } else { Join-Path $RepoRoot $EngineDll }
        if (Test-Path $dllPath) {
            Copy-Item -Path $dllPath -Destination $AppDir -Force
            Write-Host "    + prism_core.dll (audio enabled)"
        } else {
            Write-Host "    ! prism_core.dll not found at $dllPath - shipping WITHOUT audio" -ForegroundColor Yellow
        }
    }

    foreach ($f in @('Install.cmd', 'Install.ps1', 'Uninstall.cmd', 'Uninstall.ps1',
                     'Run without installing.cmd', 'README.txt')) {
        $src = Join-Path $PSScriptRoot $f
        if (Test-Path $src) { Copy-Item $src -Destination $Stage -Force }
    }

    Write-Host "==> Zipping" -ForegroundColor Cyan
    if (Test-Path $Zip) { Remove-Item $Zip -Force }
    Compress-Archive -Path $Stage -DestinationPath $Zip -CompressionLevel Optimal

    $mb = [math]::Round((Get-Item $Zip).Length / 1MB, 1)
    Write-Host ""
    Write-Host "Done: $Zip ($mb MB)" -ForegroundColor Green
    Write-Host "Folder: $Stage"
}
finally {
    Pop-Location
}
