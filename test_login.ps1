# test_login.ps1 — compile, run the client for ~22s, then report parse errors and
# the opcode trail before the last failure. Used to iterate on 15.25 packet parsing.
$root = "c:\Users\joaoc\KoliseuOT\AstraClient"
& "$root\compile.ps1" 2>&1 | Select-String -Pattern "error C|FAILED|Build OK" | Select-Object -First 5
if ($LASTEXITCODE -ne 0) { Write-Host "BUILD FAILED"; exit 1 }
Stop-Process -Name 'AstraClient*' -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 400
Start-Process -FilePath "$root\AstraClient_debug_x64.exe" -WorkingDirectory $root
Start-Sleep -Seconds 22
Stop-Process -Name 'AstraClient*' -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
$alog = "$root\astraclient.log"
$lines = Get-Content $alog
$peCount = ($lines | Select-String "parse message exception").Count
Write-Host "parse exceptions: $peCount"
$errIdx = ($lines | Select-String "parse message exception" | Select-Object -Last 1).LineNumber
if ($errIdx) {
  ($lines[0..($errIdx-1)] | Select-String "\[OPC\]") | Select-Object -Last 8 | ForEach-Object { $_.Line }
  Write-Host "--- ERRO ---"; $lines[$errIdx-1]
} else {
  Write-Host "=== SEM ERRO DE PARSE! ==="
  $lines | Select-String "now online|GameStart|enter game|processGameStart" | ForEach-Object { $_.Line } | Select-Object -Last 3
}
