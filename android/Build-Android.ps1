#Requires -Version 7.0
# Gradle 8.11.1 + JDK 17 + SDK 35/CMake 3.31.6 + NDK 28.2.13676358.
# Example: pwsh android/Build-Android.ps1
param([string]$Gradle = (Join-Path $PSScriptRoot 'gradlew.bat'), [switch]$Release)
$ErrorActionPreference = 'Stop'
if (-not $env:VCPKG_ROOT -or -not (Test-Path -LiteralPath (Join-Path $env:VCPKG_ROOT 'scripts/buildsystems/vcpkg.cmake'))) {
    throw 'Set VCPKG_ROOT to a checkout at cmake/ci/vcpkg-tool.sha; do not reuse C:/android C++17 static libraries.'
}
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$pinned = (Get-Content -LiteralPath (Join-Path $repo 'cmake/ci/vcpkg-tool.sha') -Raw).Trim()
$actual = & git -C $env:VCPKG_ROOT rev-parse HEAD
if ($LASTEXITCODE -ne 0 -or $actual -ne $pinned) { throw 'VCPKG_ROOT must match cmake/ci/vcpkg-tool.sha.' }
$version = & $Gradle --version
if ($LASTEXITCODE -ne 0 -or ($version -join "`n") -notmatch 'Gradle 8\.11\.1\b') { throw 'Install Gradle 8.11.1 and JDK 17.' }
$task = if ($Release) { ':otclientv8:assembleRelease' } else { ':otclientv8:assembleDebug' }
& $Gradle -p $PSScriptRoot --no-daemon --max-workers=2 $task
if ($LASTEXITCODE -ne 0) { throw "Android build failed (exit $LASTEXITCODE)." }
