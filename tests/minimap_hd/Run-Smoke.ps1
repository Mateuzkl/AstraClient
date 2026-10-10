param(
  [Parameter(Mandatory = $true)][string]$BinaryPath,
  [switch]$Satellite,
  [switch]$Export,
  [switch]$Audit,
  [switch]$Glitches,
  [switch]$Visual
)
$ErrorActionPreference = 'Stop'
if ((@($Satellite, $Export, $Audit, $Glitches) | Where-Object { $_ }).Count -gt 1) { throw 'Choose one test mode' }
$repoPath = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$binary = (Resolve-Path -LiteralPath $BinaryPath).Path
$testDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ('astra-hd-minimap-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testDirectory | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'bootstrap.lua') -Destination (Join-Path $testDirectory 'init.lua')
$testFile = if ($Glitches) { 'glitch_test.lua' } elseif ($Audit) { 'audit_test.lua' } elseif ($Export) { 'export_test.lua' } elseif ($Satellite) { 'satellite_test.lua' } else { 'native_test.lua' }
Copy-Item -LiteralPath (Join-Path $PSScriptRoot $testFile) -Destination (Join-Path $testDirectory 'test.lua')
Copy-Item -LiteralPath (Join-Path $repoPath 'init.lua') -Destination (Join-Path $testDirectory 'production-init.lua')
foreach ($resourceName in @('data', 'modules', 'mods', 'layouts')) {
  New-Item -ItemType Junction -Path (Join-Path $testDirectory $resourceName) -Target (Join-Path $repoPath $resourceName) | Out-Null
}
if ($Satellite) {
  & python (Join-Path $PSScriptRoot 'otmm_fixture.py') (Join-Path $repoPath 'data/minimap_hd/minimap.otmm') $testDirectory
  if ($LASTEXITCODE -ne 0) { throw 'Failed to prepare classic merge fixture' }
}
if ($Audit) {
  & python (Join-Path $PSScriptRoot 'negative_fixture.py') (Join-Path $repoPath 'data/minimap_hd/source.json') $testDirectory
  if ($LASTEXITCODE -ne 0) { throw 'Failed to prepare negative fixtures' }
}
if ($Glitches) {
  & python -B (Join-Path $PSScriptRoot 'glitch_fixture.py') (Join-Path $repoPath 'data/minimap_hd/source.json') $testDirectory
  if ($LASTEXITCODE -ne 0) { throw 'Failed to prepare glitch fixtures' }
}
$stdout = Join-Path $testDirectory 'stdout.log'
$stderr = Join-Path $testDirectory 'stderr.log'
$testArguments = @('--test')
if ($Audit) { $testArguments += '--test-expected-errors' }
if ($Visual) { $testArguments += '--hd-minimap-visual' }
$windowStyle = if ($Visual) { 'Normal' } else { 'Hidden' }
$process = Start-Process -FilePath $binary -ArgumentList $testArguments -WorkingDirectory $testDirectory -WindowStyle $windowStyle -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
if (-not $process.WaitForExit(60000)) {
  Stop-Process -Id $process.Id
  throw "Smoke test timed out. Logs kept at $testDirectory"
}
$process.Refresh()
$result = Get-Content -LiteralPath $stdout -Raw
Write-Output $result
Write-Output "Smoke-test artifacts: $testDirectory"
if ($Audit) {
  foreach ($taskErrorLine in ($result -split "`r?`n" | Where-Object { $_ -match '^ERROR:' })) {
    if ($taskErrorLine -notmatch "^ERROR: failed to load OTMM minimap: corrupt compressed minimap block$|^ERROR: \[HD Minimap\] Could not load '/negative/bad-(signature|index)/index.txt':|^ERROR: \[HD Minimap\] Cannot decode '/negative/(oversized|animated|truncated|enc3-bomb|missing|bad-seed)/satellite-1-96-96-7.png':") {
      throw "Unexpected audit error: $taskErrorLine (logs: $testDirectory)"
    }
  }
}
if ($process.ExitCode -ne 0 -or $result -notmatch '\[HD MINIMAP TEST\] PASS:') {
  throw "Smoke test failed (exit $($process.ExitCode)). Logs kept at $testDirectory"
}
if ($Export) {
  if ($result -notmatch '\[HD MINIMAP TEST\] EXPORT FIXTURE: ([^\r\n]+)') { throw 'Export fixture path missing' }
  & python (Join-Path $PSScriptRoot 'export_pixels_test.py') $Matches[1].Trim()
  if ($LASTEXITCODE -ne 0) { throw "Export pixel comparison failed; logs kept at $testDirectory" }
}
if ($Glitches) {
  if ($result -notmatch '\[HD MINIMAP TEST\] GLITCH FIXTURE: ([^\r\n]+)') { throw 'Glitch fixture path missing' }
  & python -B (Join-Path $PSScriptRoot 'glitch_pixels_test.py') $Matches[1].Trim()
  if ($LASTEXITCODE -ne 0) { throw "GPU transition pixel comparison failed; logs kept at $testDirectory" }
}
