param([string]$BinaryPath = (Join-Path $PSScriptRoot '../../otclient_dx_x64.exe'))
$ErrorActionPreference = 'Stop'
$binary = (Resolve-Path -LiteralPath $BinaryPath).Path
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('astra-battle-hover-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null
Set-Content -LiteralPath (Join-Path $fixture 'init.lua') -Value 'APP_NAME = "astra_battle_hover_test"' -Encoding ASCII
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'hover.lua') -Destination (Join-Path $fixture 'test.lua')
foreach ($name in @('modules', 'data')) {
  New-Item -ItemType Junction -Path (Join-Path $fixture $name) -Target (Join-Path $repo $name) | Out-Null
}
$process = Start-Process -FilePath $binary -ArgumentList '--test' -WorkingDirectory $fixture -WindowStyle Hidden -PassThru
$null = $process.Handle
if (-not $process.WaitForExit(30000)) {
  $process.Kill()
  throw "Battle List test timed out. Logs in $fixture"
}
$process.Refresh()
$log = Join-Path $fixture 'astra_battle_hover_test.log'
if ($process.ExitCode -ne 0 -or !(Select-String -LiteralPath $log -SimpleMatch '[Battle List] PASS' -Quiet)) {
  throw "Battle List test failed. See $log"
}
Select-String -LiteralPath $log -SimpleMatch '[Battle List]' | ForEach-Object { $_.Line }
