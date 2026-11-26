param(
    [ValidateSet("Debug", "Release", "RelWithDebInfo")]
    [string]$BuildType = "Release",
    [ValidateSet("Flat", "Desktop", "Mobile", "All")]
    [string]$Profile = "Flat",
    [string]$BuildDirectory = "",
    [string]$ThingsDirectory = "",
    [int]$Jobs = 0,
    [string[]]$ExtraCMakeArgs = @()
)

$ErrorActionPreference = "Stop"
$expectedEmscripten = "6.0.8"
$rootDirectory = Split-Path -Parent $PSScriptRoot
$profileLower = $Profile.ToLowerInvariant()

if (-not $env:EMSDK) {
    throw "EMSDK is not set. Activate the pinned Emscripten SDK first."
}
if (-not $BuildDirectory) {
    if ($profileLower -eq "flat") {
        $BuildDirectory = Join-Path $rootDirectory ("build-wasm-" + $BuildType.ToLowerInvariant())
    } else {
        $BuildDirectory = Join-Path $rootDirectory ("build-wasm-" + $profileLower + "-" + $BuildType.ToLowerInvariant())
    }
}

foreach ($commandName in @("emcc", "emcmake", "cmake", "ninja", "python", "node")) {
    if (-not (Get-Command $commandName -ErrorAction SilentlyContinue)) {
        throw "Required command not found: $commandName"
    }
}

$emccVersion = (& emcc --version | Select-Object -First 1)
if ($emccVersion -notmatch [regex]::Escape($expectedEmscripten)) {
    throw "Expected Emscripten $expectedEmscripten, got: $emccVersion"
}

if (-not $env:EM_COMPILER_WRAPPER -and (Get-Command ccache -ErrorAction SilentlyContinue)) {
    $env:EM_COMPILER_WRAPPER = "ccache"
}

if ($Jobs -le 0) {
    $cpuCount = [Environment]::ProcessorCount
    $Jobs = [Math]::Max(2, [Math]::Min(4, [int][Math]::Floor($cpuCount / 2)))
}

function Invoke-ProfileBuild {
    param(
        [string]$TargetProfile,
        [string]$ObjDir,
        [string]$DistRoot,
        [string]$Subdir
    )

    $configureOptions = @(
        "-DCMAKE_BUILD_TYPE=$BuildType",
        "-DASTRA_WASM_PROFILE=$TargetProfile",
        "-DASTRA_WASM_DIST_DIR=$DistRoot",
        "-DASTRA_WASM_OUTPUT_SUBDIR=$Subdir"
    )
    if ($ThingsDirectory) {
        $configureOptions += "-DASTRA_WASM_THINGS_DIR=$ThingsDirectory"
    }
    if ($ExtraCMakeArgs.Count -gt 0) {
        $configureOptions += $ExtraCMakeArgs
    }

    Write-Host "==> Configuring AstraClient Web ($TargetProfile, subdir='$Subdir', jobs=$Jobs) in $ObjDir"
    $cacheFile = Join-Path $ObjDir "CMakeCache.txt"
    if (Test-Path $cacheFile) {
        & emcmake cmake -S $rootDirectory -B $ObjDir -G Ninja @configureOptions
    } else {
        & emcmake cmake --fresh -S $rootDirectory -B $ObjDir -G Ninja @configureOptions
    }
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    & cmake --build $ObjDir --parallel $Jobs
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

$distRoot = Join-Path $BuildDirectory "dist"
switch ($profileLower) {
    "flat" {
        Invoke-ProfileBuild -TargetProfile "desktop" -ObjDir $BuildDirectory -DistRoot $distRoot -Subdir ""
    }
    "desktop" {
        Invoke-ProfileBuild -TargetProfile "desktop" -ObjDir (Join-Path $BuildDirectory "desktop-obj") -DistRoot $distRoot -Subdir "desktop"
    }
    "mobile" {
        Invoke-ProfileBuild -TargetProfile "mobile" -ObjDir (Join-Path $BuildDirectory "mobile-obj") -DistRoot $distRoot -Subdir "mobile"
    }
    "all" {
        Invoke-ProfileBuild -TargetProfile "desktop" -ObjDir (Join-Path $BuildDirectory "desktop-obj") -DistRoot $distRoot -Subdir "desktop"
        Invoke-ProfileBuild -TargetProfile "mobile" -ObjDir (Join-Path $BuildDirectory "mobile-obj") -DistRoot $distRoot -Subdir "mobile"
    }
}

& python (Join-Path $rootDirectory "tools/check_browser_assets.py")
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "AstraClient browser artifacts ($profileLower): $distRoot"
