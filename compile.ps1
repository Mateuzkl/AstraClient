# compile.ps1 — Build helper for AstraClient (15.25 upgrade fork).
#
# Usage:
#   .\compile.ps1                       # Debug|x64, incremental
#   .\compile.ps1 -Config DirectX       # release-style ANGLE/D3D build
#   .\compile.ps1 -Clean                # full Rebuild target
#   .\compile.ps1 -NoKill               # don't kill running AstraClient*.exe
#   .\compile.ps1 -Toolset v143         # build on Visual Studio 2022 (v145 = VS 2026)
#   .\compile.ps1 -NoVcpkg              # skip the vcpkg bootstrap (you manage it yourself)
#
# Why this script exists:
#   - MSBuild lives at an annoyingly-versioned path; we resolve it via vswhere.
#   - The Debug build pins PlatformToolset=v145 because the machine has
#     Visual Studio 2026 (VS 18) installed, not VS 2022 (v143).
#   - When the client is still running, LINK fails with LNK1104 'cannot open
#     AstraClient_debug_x64.exe' — Stop-Process handles that up front.
#   - The C++ deps (Boost/OpenSSL/protobuf/...) come from vcpkg manifest mode +
#     autolink, which needs vcpkg installed AND integrated into MSBuild. A fresh
#     clone has neither, so this script bootstraps vcpkg automatically (clone +
#     bootstrap + integrate) before building. See BUILD.md.

[CmdletBinding()]
param(
    # Debug = unoptimized dev build. OpenGL/DirectX = the optimized "release" builds
    # (MaxSpeed, NDEBUG, LTCG) — use these for performance testing. The bare "Release"
    # config exists in the vcxproj but is NOT mapped in the .sln, so it won't build.
    [ValidateSet('Debug', 'OpenGL', 'DirectX')]
    [string]$Config = 'Debug',

    [ValidateSet('x64', 'Win32')]
    [string]$Platform = 'x64',

    [string]$Toolset = 'v145',

    # Where to keep the vcpkg clone this script bootstraps. Defaults to
    # $env:VCPKG_ROOT if set, otherwise %USERPROFILE%\vcpkg.
    [string]$VcpkgRoot = '',

    [switch]$Clean,
    [switch]$NoKill,

    # Skip the vcpkg presence/integration check (for devs who manage vcpkg themselves).
    [switch]$NoVcpkg
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSCommandPath
$solutionPath = Join-Path $repoRoot 'vc17\AstraClient.sln'

if (-not (Test-Path $solutionPath)) {
    throw "Could not find solution at $solutionPath. Run this script from the AstraClient repo root."
}

# --- Locate MSBuild via vswhere -----------------------------------------------
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vswhere)) {
    throw "vswhere.exe not found at $vswhere. Install Visual Studio 2022+."
}

$msbuild = & $vswhere -prerelease -latest -find 'MSBuild\**\Bin\MSBuild.exe' | Select-Object -First 1
if (-not $msbuild -or -not (Test-Path $msbuild)) {
    throw "Could not locate MSBuild.exe via vswhere."
}
Write-Host "MSBuild: $msbuild" -ForegroundColor DarkGray

# --- Ensure vcpkg is present + integrated ------------------------------------
# The vcxproj uses vcpkg manifest mode + autolink, which only activates when
# vcpkg's MSBuild integration is installed machine-wide. Without it a fresh clone
# fails early (no manifest restore -> no protoc.exe -> MSB8066, or missing Boost
# headers). This makes the build work on a box that has never seen vcpkg.
if (-not $NoVcpkg) {
    if (-not $VcpkgRoot) {
        $VcpkgRoot = if ($env:VCPKG_ROOT) { $env:VCPKG_ROOT } else { Join-Path $env:USERPROFILE 'vcpkg' }
    }
    $vcpkgExe = Join-Path $VcpkgRoot 'vcpkg.exe'

    if (-not (Test-Path $vcpkgExe)) {
        if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
            throw "git is required to bootstrap vcpkg but was not found on PATH. Install Git, or pass -NoVcpkg if you manage vcpkg yourself."
        }
        if (-not (Test-Path $VcpkgRoot)) {
            Write-Host "vcpkg not found - cloning to $VcpkgRoot ..." -ForegroundColor Yellow
            git clone https://github.com/microsoft/vcpkg $VcpkgRoot
            if ($LASTEXITCODE -ne 0) { throw "git clone of vcpkg failed." }
        }
        Write-Host "Bootstrapping vcpkg (compiles vcpkg.exe, one-time)..." -ForegroundColor Yellow
        & (Join-Path $VcpkgRoot 'bootstrap-vcpkg.bat') -disableMetrics
        if (-not (Test-Path $vcpkgExe)) { throw "vcpkg bootstrap failed - $vcpkgExe was not produced." }
    }

    $env:VCPKG_ROOT = $VcpkgRoot
    Write-Host "Ensuring vcpkg MSBuild integration (vcpkg at $VcpkgRoot)..." -ForegroundColor DarkGray
    & $vcpkgExe integrate install | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "'vcpkg integrate install' failed." }
    Write-Host "Note: the first build also runs the vcpkg manifest restore (Boost/OpenSSL/etc. compiled from source) - this can take 30-60+ min once, then it's cached." -ForegroundColor DarkGray
}

# --- Kill running client so LINK can overwrite the .exe ----------------------
if (-not $NoKill) {
    $running = Get-Process -Name 'AstraClient*' -ErrorAction SilentlyContinue
    if ($running) {
        Write-Host "Stopping $($running.Count) running AstraClient process(es)..." -ForegroundColor Yellow
        $running | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 300
    }
}

# --- Build --------------------------------------------------------------------
$targetArg = if ($Clean) { '/t:Rebuild' } else { '/t:Build' }

$args = @(
    $solutionPath,
    "/p:Configuration=$Config",
    "/p:Platform=$Platform",
    "/p:PlatformToolset=$Toolset",
    '/m',
    '/v:minimal',
    '/nologo',
    $targetArg
)

Write-Host "Building $Config|$Platform (toolset $Toolset)..." -ForegroundColor Cyan
$startTime = Get-Date

& $msbuild @args
$exitCode = $LASTEXITCODE

$elapsed = (Get-Date) - $startTime

if ($exitCode -eq 0) {
    $exeName = switch ($Config) {
        'Debug'   { 'AstraClient_debug_x64.exe' }
        'OpenGL'  { 'AstraClient_gl_x64.exe' }
        'DirectX' { 'AstraClient.exe' }
        default   { 'AstraClient_debug_x64.exe' }
    }
    $exePath = Join-Path $repoRoot $exeName
    Write-Host ""
    Write-Host "Build OK in $([int]$elapsed.TotalSeconds)s" -ForegroundColor Green
    if (Test-Path $exePath) {
        $size = [math]::Round((Get-Item $exePath).Length / 1MB, 1)
        Write-Host "Output: $exePath ($size MB)" -ForegroundColor Green
    }
} else {
    Write-Host ""
    Write-Host "Build FAILED (exit $exitCode) after $([int]$elapsed.TotalSeconds)s" -ForegroundColor Red
    exit $exitCode
}
