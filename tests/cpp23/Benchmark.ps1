param(
  [Parameter(Mandatory)][string]$Baseline,
  [Parameter(Mandatory)][string]$Cpp23,
  [string]$OutputDirectory = 'build/cpp23/benchmark'
)
$ErrorActionPreference = 'Stop'
$runner = Join-Path $PSScriptRoot '../minimap_hd/Run-Smoke.ps1'
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
# Sequential, same production UI fixture / isolated profile / hardware backend.
# Run only after builds finish; this is NOT a connected gameplay FPS benchmark.
foreach ($entry in @(@{name='cpp17';binary=$Baseline}, @{name='cpp23';binary=$Cpp23})) {
  & $runner -BinaryPath $entry.binary -Cyclopedia -MetricsPath (Join-Path $OutputDirectory ($entry.name + '.json')) 2>&1 |
    Tee-Object -FilePath (Join-Path $OutputDirectory ($entry.name + '.log'))
}
