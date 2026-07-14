# Runs the client under cdb (console debugger) so any crash is captured live
# with the full stack and locals — no need to wait for WER dumps.
#
# Usage:
#   .\debug-attach.ps1                  # Debug build (best: no inlining, full locals)
#   .\debug-attach.ps1 -Config DirectX  # release builds also work (PDBs exist)
#
# The game window opens normally; play until it crashes. When it does, the
# triage (exception, stack, locals) is appended to crashdumps\cdb_*.log and the
# process exits. For interactive breakpoints/watches, prefer opening
# vc17\AstraClient.sln in Visual Studio and F5 with the Debug config.
param(
    [ValidateSet('Debug','OpenGL','DirectX')]
    [string]$Config = 'Debug'
)

$exeName = switch ($Config) {
    'Debug'   { 'AstraClient_debug_x64.exe' }
    'OpenGL'  { 'AstraClient_gl_x64.exe' }
    'DirectX' { 'AstraClient.exe' }
}

$root = $PSScriptRoot
$exe  = Join-Path $root $exeName
if (-not (Test-Path $exe)) {
    throw "$exeName not found - build it first: .\compile.ps1 -Config $Config"
}

# cdb ships inside the Microsoft Store WinDbg package.
$cdb = Get-ChildItem 'C:\Program Files\WindowsApps\Microsoft.WinDbg_*\amd64\cdb.exe' -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending | Select-Object -First 1
if (-not $cdb) {
    throw 'cdb.exe not found - install WinDbg from the Microsoft Store'
}

$logDir = Join-Path $root 'crashdumps'
New-Item -ItemType Directory -Force $logDir | Out-Null
$log = Join-Path $logDir ("cdb_{0}_{1}.log" -f $Config.ToLower(), (Get-Date -Format 'yyyyMMdd_HHmmss'))

# Project PDBs live in the repo root; OS symbols come from the MS server.
$symPath = "$root;srv*$logDir\sym*https://msdl.microsoft.com/download/symbols"

# sxd eh: C++ exceptions are part of normal flow here (parser/http throw and
# catch) - breaking on first-chance EH would stop constantly. ld/ud/cpr noise
# is also muted. Everything after `g` runs at the FIRST real break, which with
# -g -G is the crash itself: triage + exception-context stack + locals, quit.
$startup = 'sxd eh; sxd ld; sxd ud; sxd cpr; g; .echo ==== CRASH CAPTURED ====; .lastevent; !analyze -v; .ecxr; kv 40; .frame 1; dv /t /v; q'

Push-Location $root
try {
    Write-Host "Running $exeName under cdb. Crash log: $log"
    & $cdb.FullName -g -G -logo $log -y $symPath -c $startup $exe
} finally {
    Pop-Location
}
Write-Host "Session ended. If it crashed, the stack is in: $log"
