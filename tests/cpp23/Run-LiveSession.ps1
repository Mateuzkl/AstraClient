param(
  [Parameter(Mandatory = $true)][string]$BinaryPath,
  [Parameter(Mandatory = $true)][string]$Account,
  [Parameter(Mandatory = $true)][string]$Password,
  [Parameter(Mandatory = $true)][string]$Character,
  [string]$ServerHost = '127.0.0.1',
  [int]$Port = 7171,
  [int]$Version = 860
)
$ErrorActionPreference = 'Stop'
$repoPath = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$binary = (Resolve-Path -LiteralPath $BinaryPath).Path
$testDirectory = Join-Path ([IO.Path]::GetTempPath()) ('astra-cpp23-live-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testDirectory | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'live_bootstrap.lua') -Destination (Join-Path $testDirectory 'init.lua')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'live_session.lua') -Destination (Join-Path $testDirectory 'test.lua')
Copy-Item -LiteralPath (Join-Path $repoPath 'init.lua') -Destination (Join-Path $testDirectory 'production-init.lua')
foreach ($resourceName in @('data', 'modules', 'mods', 'layouts')) {
  New-Item -ItemType Junction -Path (Join-Path $testDirectory $resourceName) -Target (Join-Path $repoPath $resourceName) | Out-Null
}
$credentialFile = Join-Path $testDirectory 'session-config.json'
$process = $null
try {
  $sessionJson = @{ account=$Account; password=$Password; character=$Character; host=$ServerHost; port=$Port; version=$Version } |
    ConvertTo-Json
  [IO.File]::WriteAllText($credentialFile, $sessionJson, (New-Object Text.UTF8Encoding $false))
  $stdout = Join-Path $testDirectory 'stdout.log'
  $stderr = Join-Path $testDirectory 'stderr.log'
  $process = Start-Process -FilePath $binary -ArgumentList '--test' -WorkingDirectory $testDirectory -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
  if (-not $process.WaitForExit(50000)) { throw "Live session timed out: $testDirectory" }
  $process.Refresh()
  $result = Get-Content -LiteralPath $stdout -Raw
  Write-Output $result
  Write-Output "Live-session artifacts: $testDirectory"
  if ($process.ExitCode -ne 0 -or $result -notmatch '\[CXX23 LIVE\] PASS:') { throw 'Live session failed' }
} finally {
  if ($process -and -not $process.HasExited) { Stop-Process -Id $process.Id }
  # Exact file produced by this runner; never remove user configs or junctions.
  if (Test-Path -LiteralPath $credentialFile) { Remove-Item -LiteralPath $credentialFile }
}
