# pageheap.ps1 - turn on Windows Page Heap for the client so heap corruption
# (buffer overflow / use-after-free / double-free) crashes AT THE OFFENDING ACCESS
# instead of minutes later inside ntdll's allocator. The crash then lands in the
# client's own crash handler, so exception.dmp points at the guilty code and
# symbolizes against KoliseuClient.pdb.
#
# This is the same mechanism as `gflags /p /enable <exe> /full`. It writes the
# per-image "Image File Execution Options" key, so it MUST run ELEVATED (admin).
#
# Usage (from an elevated PowerShell, repo root):
#   powershell -ExecutionPolicy Bypass -File tools\pageheap.ps1 -Enable        # full page heap
#   powershell -ExecutionPolicy Bypass -File tools\pageheap.ps1 -Enable -Light # standard (low memory)
#   powershell -ExecutionPolicy Bypass -File tools\pageheap.ps1 -Status
#   powershell -ExecutionPolicy Bypass -File tools\pageheap.ps1 -Disable
#
# FULL page heap puts every allocation on its own page with a guard page right
# after it, so a 1-byte overflow faults immediately, but virtual-memory use
# balloons. If the client fails to launch or is unusably slow, use -Light
# (standard page heap: fill patterns checked on free; lighter, less precise).
#
# Remember to -Disable when you are done; the client runs much slower under it.

[CmdletBinding()]
param(
  [string]$Exe = "KoliseuClient.exe",
  [switch]$Enable,
  [switch]$Disable,
  [switch]$Status,
  [switch]$Light
)
$ErrorActionPreference = "Stop"
$ifeo = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\$Exe"

function Test-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  return ([Security.Principal.WindowsPrincipal]$id).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
}

if ($Status) {
  if (Test-Path $ifeo) {
    $p = Get-ItemProperty $ifeo
    $gf  = if ($null -ne $p.GlobalFlag)    { "0x{0:x8}" -f [int]$p.GlobalFlag }    else { "(unset)" }
    $phf = if ($null -ne $p.PageHeapFlags) { "0x{0:x}"  -f [int]$p.PageHeapFlags } else { "(unset)" }
    "page heap for ${Exe}: GlobalFlag=$gf  PageHeapFlags=$phf"
  } else {
    "page heap NOT enabled for $Exe"
  }
  return
}

if (-not (Test-Admin)) {
  throw "Must run elevated (Administrator): this writes HKLM Image File Execution Options."
}

if ($Enable) {
  if (-not (Test-Path $ifeo)) { New-Item -Path $ifeo -Force | Out-Null }
  # GlobalFlag bit 0x02000000 = FLG_HEAP_PAGE_ALLOCS ("hpa"), arms page heap for this image.
  New-ItemProperty -Path $ifeo -Name GlobalFlag -Value 0x02000000 -PropertyType DWord -Force | Out-Null
  # PageHeapFlags: 0x1 = enable, 0x2 = full (guard page per allocation). 0x3 = full, 0x1 = light.
  $phf = 0x3
  if ($Light) { $phf = 0x1 }
  New-ItemProperty -Path $ifeo -Name PageHeapFlags -Value $phf -PropertyType DWord -Force | Out-Null
  $mode = "FULL (guard page per allocation)"
  if ($Light) { $mode = "STANDARD/light (checked on free)" }
  "Enabled $mode page heap for $Exe."
  "Launch the client and reproduce the crash; it will fault at the offending access."
  "Analyze exception.dmp as usual, then run: tools\pageheap.ps1 -Disable"
  return
}

if ($Disable) {
  if (Test-Path $ifeo) {
    Remove-ItemProperty -Path $ifeo -Name GlobalFlag    -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $ifeo -Name PageHeapFlags -ErrorAction SilentlyContinue
    if (-not (Get-Item $ifeo).Property) { Remove-Item $ifeo -Force }
    "Disabled page heap for $Exe."
  } else {
    "Nothing to disable for $Exe."
  }
  return
}

"Specify -Enable (optionally -Light), -Disable, or -Status."
