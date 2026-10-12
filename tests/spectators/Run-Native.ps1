[CmdletBinding()]
param(
    [ValidateSet('OpenGL', 'DirectX')][string[]]$Configuration = @('OpenGL', 'DirectX'),
    [string]$DependencyRoot,
    [string]$BuildRoot = (Join-Path $env:TEMP 'astra-spectator-tests'),
    [switch]$Benchmark
)
$ErrorActionPreference = 'Stop'
$spectatorRepo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$spectatorVsWhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$spectatorVs = & $spectatorVsWhere -latest -products '*' -requires Microsoft.Component.MSBuild -property installationPath
if (-not $spectatorVs) { throw 'Visual Studio/MSBuild not found' }
$spectatorMsbuild = Join-Path $spectatorVs 'MSBuild/Current/Bin/MSBuild.exe'
$spectatorBin = Join-Path ([IO.Path]::GetFullPath($BuildRoot)) 'bin'
New-Item -ItemType Directory -Path $spectatorBin -Force | Out-Null
foreach ($spectatorConfig in $Configuration) {
    $spectatorSuffix = if ($spectatorConfig -eq 'OpenGL') { 'gl' } else { 'dx' }
    $spectatorIntermediate = Join-Path ([IO.Path]::GetFullPath($BuildRoot)) "native-$spectatorSuffix"
    $spectatorOptions = @(
        (Join-Path $spectatorRepo 'vc23/otclient.vcxproj'), '/t:Build',
        "/p:Configuration=$spectatorConfig", '/p:Platform=x64',
        "/p:ForceImportBeforeCppTargets=$(Join-Path $PSScriptRoot 'native-harness.props')",
        "/p:IntDir=$spectatorIntermediate\", "/p:OutDir=$spectatorBin\",
        "/p:TargetName=spectator_tests_$spectatorSuffix", '/p:CL_MPCount=2',
        '/m:1', '/nr:false', '/nologo', '/v:minimal'
    )
    if ($DependencyRoot) {
        $spectatorDependencies = (Resolve-Path -LiteralPath $DependencyRoot).Path
        $spectatorOptions += @('/p:VcpkgEnableManifest=false', "/p:VcpkgInstalledDir=$spectatorDependencies\")
    }
    & $spectatorMsbuild @spectatorOptions
    if ($LASTEXITCODE -ne 0) { throw "$spectatorConfig native build failed" }
    [string[]]$spectatorTestArgs = @()
    if ($Benchmark) { $spectatorTestArgs = @('--benchmark') }
    & (Join-Path $spectatorBin "spectator_tests_$spectatorSuffix.exe") @spectatorTestArgs
    if ($LASTEXITCODE -ne 0) { throw "$spectatorConfig regression failed" }
}
