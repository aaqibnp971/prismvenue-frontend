<#
    Raises the build number in pubspec.yaml.

    The `+N` in `version: 1.0.6+7` is Android's versionCode, and Play treats it
    as the sole ordering key for a release: it must increase on EVERY upload,
    including a rebuild of byte-identical code, because Play has already
    recorded the number even if it rejected the bundle for another reason.

    Forgetting it costs a full rebuild and a confusing error that names a
    version rather than the thing you changed:

        Version code 6 has already been used. Try another version code.

    Run this before `flutter build appbundle`, or pass -Release to move the
    human-facing 1.0.x part as well — that half may repeat freely, so it only
    moves when a build carries work worth naming.
#>
param(
    # Also bump the patch component of the version name (1.0.6 -> 1.0.7).
    [switch]$Release,
    # Print what would change and write nothing.
    [switch]$WhatIfOnly
)

$ErrorActionPreference = 'Stop'

$pubspec = Join-Path (Split-Path -Parent $PSScriptRoot) 'pubspec.yaml'
$lines = Get-Content -LiteralPath $pubspec

$index = ($lines | Select-String -Pattern '^version:\s' | Select-Object -First 1).LineNumber - 1
if ($index -lt 0) { throw "No 'version:' line in $pubspec" }

if ($lines[$index] -notmatch '^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$') {
    throw "Cannot parse version line: $($lines[$index])"
}
$major = [int]$Matches[1]; $minor = [int]$Matches[2]
$patch = [int]$Matches[3]; $build = [int]$Matches[4]

$was = "$major.$minor.$patch+$build"
$build++
if ($Release) { $patch++ }
$now = "$major.$minor.$patch+$build"

Write-Host "  $was  ->  $now" -ForegroundColor Cyan
Write-Host "  versionCode $build, versionName $major.$minor.$patch"

if ($WhatIfOnly) { Write-Host "  (not written)" -ForegroundColor Yellow; return }

$lines[$index] = "version: $now"
Set-Content -LiteralPath $pubspec -Value $lines -Encoding utf8
