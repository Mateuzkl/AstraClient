param(
  [Parameter(Mandatory = $true)][string]$BinaryPath,
  [Parameter(Mandatory = $true)][string]$WorldPath,
  [Parameter(Mandatory = $true)][string]$ItemsPath,
  [Parameter(Mandatory = $true)][string]$OutputPath,
  [string]$Python = 'python',
  [ValidateRange(1, 86400)][int]$TimeoutSeconds = 1800
)
$ErrorActionPreference = 'Stop'
$repoPath = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$binary = (Resolve-Path -LiteralPath $BinaryPath).Path
$world = (Resolve-Path -LiteralPath $WorldPath).Path
$items = (Resolve-Path -LiteralPath $ItemsPath).Path
$output = [System.IO.Path]::GetFullPath($OutputPath)
if (Test-Path -LiteralPath $output) { throw "Output already exists: $output" }
# Source inputs are only copied/read. No server processes or files are changed.
$taskDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ('astra-hd-export-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $taskDirectory | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'export_bootstrap.lua') -Destination (Join-Path $taskDirectory 'init.lua')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'export.lua') -Destination (Join-Path $taskDirectory 'test.lua')
Copy-Item -LiteralPath (Join-Path $repoPath 'init.lua') -Destination (Join-Path $taskDirectory 'production-init.lua')
Copy-Item -LiteralPath $world -Destination (Join-Path $taskDirectory 'source-world.otbm')
Copy-Item -LiteralPath $items -Destination (Join-Path $taskDirectory 'source-items.otb')
foreach ($resourceName in @('data', 'modules', 'mods', 'layouts')) {
  New-Item -ItemType Junction -Path (Join-Path $taskDirectory $resourceName) -Target (Join-Path $repoPath $resourceName) | Out-Null
}
$stdout = Join-Path $taskDirectory 'stdout.log'
$stderr = Join-Path $taskDirectory 'stderr.log'
$process = Start-Process -FilePath $binary -ArgumentList @('--test') -WorkingDirectory $taskDirectory -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
Write-Output "Export process: $($process.Id); logs: $taskDirectory"
$exportTimer = [System.Diagnostics.Stopwatch]::StartNew()
while (-not $process.WaitForExit(1000)) {
  if ($exportTimer.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
    Stop-Process -Id $process.Id -ErrorAction SilentlyContinue
    throw "Export timed out after $TimeoutSeconds seconds; source untouched, logs kept: $taskDirectory"
  }
  # Native exporter logs progress. No visible client window or server login.
  if ((Get-Item -LiteralPath $stdout).Length -gt 0) {
    $progress = Get-Content -LiteralPath $stdout -Tail 1
    if ($progress -ne $lastProgress) { Write-Output $progress; $lastProgress = $progress }
  }
}
$process.Refresh()
$result = Get-Content -LiteralPath $stdout -Raw
if ($process.ExitCode -ne 0 -or $result -notmatch '\[HD EXPORT\] PASS:' -or $result -match 'ERROR:|Failed to load|invalid item|unable to create item') {
  throw "Export failed (exit $($process.ExitCode)); source untouched, logs kept: $taskDirectory"
}
if ($result -notmatch '\[HD EXPORT\] OUTPUT: ([^\r\n]+)') { throw 'Export path missing' }
$baseDirectory = $Matches[1].Trim()
& $Python (Join-Path $PSScriptRoot 'build_pyramid.py') $baseDirectory $output --world $world --items $items
if ($LASTEXITCODE -ne 0) { throw "Pyramid build failed; incomplete output kept at $output" }
Write-Output "Persistent HD pack ready: $output"
