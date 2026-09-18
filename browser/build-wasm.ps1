param(
    [ValidateSet("Debug", "Release", "RelWithDebInfo")]
    [string]$BuildType = "Release",
    [string]$BuildDirectory = ""
)

$ErrorActionPreference = "Stop"
$expectedEmscripten = "6.0.8"
$rootDirectory = Split-Path -Parent $PSScriptRoot

if (-not $env:EMSDK) {
    throw "EMSDK is not set. Activate the pinned Emscripten SDK first."
}
if (-not $BuildDirectory) {
    $BuildDirectory = Join-Path $rootDirectory ("build-wasm-" + $BuildType.ToLowerInvariant())
}

foreach ($commandName in @("emcc", "emcmake", "cmake", "ninja", "python")) {
    if (-not (Get-Command $commandName -ErrorAction SilentlyContinue)) {
        throw "Required command not found: $commandName"
    }
}

$emccVersion = (& emcc --version | Select-Object -First 1)
if ($emccVersion -notmatch [regex]::Escape($expectedEmscripten)) {
    throw "Expected Emscripten $expectedEmscripten, got: $emccVersion"
}

& emcmake cmake --fresh -S $rootDirectory -B $BuildDirectory -G Ninja "-DCMAKE_BUILD_TYPE=$BuildType"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& cmake --build $BuildDirectory --parallel
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& python (Join-Path $rootDirectory "tools/check_browser_assets.py")
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "AstraClient browser artifacts: $(Join-Path $BuildDirectory 'dist')"
