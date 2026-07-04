# make_release.ps1 — assembles a distributable KoliseuOT client release.
# Replaces the obsolete tools/make_snapshot.sh (edubart mingw/win32).
#
# Output: a release/ folder with:
#   KoliseuClient.exe + libGLESv2.dll + libEGL.dll + d3dcompiler_47.dll + vulkan-1.dll
#   data.zip   (init.lua + modules/ + mods/ + data/ + config.lua  -> the client VFS)
#
# Also archives this build's debug symbols into the symbol vault (symbols\ by default):
#   symbols\KoliseuClient_<stamp>[_r<Rev>][_<gitsha>]\ -> KoliseuClient.pdb + exe + build-info.txt
# The shipped exe is stripped, so this PDB is what tools\symbolicate_crash.ps1 needs to
# turn a player's minidump into a source backtrace. Dev recompiles overwrite the root
# PDB, so we snapshot it here at release time. Skip with -NoArchivePdb; relocate with -SymbolVault.
#
# config.lua is bundled INSIDE data.zip (not next to the exe): in data.zip mode the
# client only keeps the write dir + the in-memory archive mounted, so a loose config
# next to the exe is never read. Bundling it also puts it inside the encryption.
#
# What this script does to the SHIPPED copy (never the dev tree):
#   - flips DEVELOPERMODE = false in init.lua  -> hides the PumpkinBot terminal,
#     the Draw/Debug overlay, the "Debug Info" profiler, the offset tool and Ctrl+R reload.
#   - with -Encrypt: per-file encryption (see docs/RELEASE_CLIENT_TESTE.md):
#       "KoliseuClient.exe --encrypt --quiet" -> each file (init.lua/config.lua/modules/
#       mods/data) becomes Lua bytecode + AES-GCM, in place. The data.zip stays a normal
#       zip (folder names visible) but every file's CONTENT is encrypted.
#   - with -Encrypt -Container: ALSO wrap the whole data.zip in an opaque AES-GCM blob
#       ("--pack", no PK signature -> unbrowsable). Heavier (the whole zip is decrypted to
#       RAM at boot); off by default. Note: the in-client updater needs a browsable archive,
#       so don't use -Container with the updater.
#   The build's baked-in key (keymaterial.gen.h) must match at runtime, so generate the key
#   + rebuild BEFORE running this.
#
# Usage:
#   .\tools\make_release.ps1                                  # prod, no encryption
#   .\tools\make_release.ps1 -Env test -Encrypt              # TEST client, per-file encrypted
#   .\tools\make_release.ps1 -Env test -Encrypt -Container   # + opaque container
#   .\tools\make_release.ps1 -SkipBuild -Env test -Encrypt
#   .\tools\make_release.ps1 -Url https://cdn/files/ -Rev 123 # + generate update.json

[CmdletBinding()]
param(
  [string]$Env = "",                       # environment shortcut: -Env test -> bundles config.test.lua (+ init.test.lua if present)
  [switch]$SkipBuild,
  [switch]$Encrypt,                        # per-file encrypt the shipped data (Lua bytecode + AES-GCM)
  [switch]$Container,                       # with -Encrypt: ALSO wrap data.zip in an opaque AES-GCM container
  [string]$ConfigFile = "config.prod.lua", # which config to bundle as config.lua (overrides -Env)
  [string]$Url = "",                       # if set, also generate update.json (needs Python)
  [string]$Rev = "",                       # revision tag appended to the published binary name
  [string]$ReleaseDir = "release",
  [string]$SymbolVault = "symbols",        # where to archive this build's PDB (relative to repo, or absolute)
  [switch]$NoArchivePdb                    # skip archiving the PDB into the symbol vault
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

# -Env test|prod is a shortcut: it selects config.<env>.lua (unless -ConfigFile was
# given explicitly) and, if present, an init.<env>.lua override. The env-specific
# part is the CONFIG (URLs); init.lua is normally shared (DEVELOPERMODE is flipped
# off below regardless), so init.<env>.lua is optional.
if ($Env -ne "" -and -not $PSBoundParameters.ContainsKey('ConfigFile')) {
  $ConfigFile = "config.$Env.lua"
}

$exe = "KoliseuClient.exe"
$dlls = @('libGLESv2.dll', 'libEGL.dll', 'd3dcompiler_47.dll', 'vulkan-1.dll')

if (-not $SkipBuild) {
  Write-Host "Building DirectX..." -ForegroundColor Cyan
  & "$repo\compile.ps1" -Config DirectX
  if ($LASTEXITCODE -ne 0) { throw "build failed" }
}

# --- clean release dir ---
$rel = Join-Path $repo $ReleaseDir
if (Test-Path $rel) { Remove-Item -Recurse -Force $rel }
New-Item -ItemType Directory -Force -Path $rel | Out-Null

# --- exe + DLLs ---
foreach ($f in @($exe) + $dlls) {
  if (-not (Test-Path (Join-Path $repo $f))) { throw "missing artifact: $f (build first?)" }
  Copy-Item (Join-Path $repo $f) -Destination $rel -Force
}

# --- archive this build's PDB into the symbol vault -------------------------------
# The shipped exe is STRIPPED, and every dev recompile overwrites KoliseuClient.pdb in
# the repo root. So snapshot THIS build's PDB aside now, keyed by a build stamp, so a
# player's minidump can still be turned into a source backtrace later
# (tools\symbolicate_crash.ps1 -Symbols <vault>). Copy (not move): the root PDB stays
# put for local debugging; the vault just keeps an immutable per-release copy.
if (-not $NoArchivePdb) {
  $pdbSrc = Join-Path $repo 'KoliseuClient.pdb'   # the DirectX build's PDB; matches KoliseuClient.exe
  if (Test-Path $pdbSrc) {
    $vaultRoot = if ([System.IO.Path]::IsPathRooted($SymbolVault)) { $SymbolVault } else { Join-Path $repo $SymbolVault }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $gitSha = ""
    if (Get-Command git -ErrorAction SilentlyContinue) {
      $sha = git -C $repo rev-parse --short HEAD 2>$null
      if ($LASTEXITCODE -eq 0 -and $sha) { $gitSha = $sha.Trim() }
    }
    $name = "KoliseuClient_$stamp"
    if ($Rev -ne "") { $name += "_r$Rev" }
    if ($gitSha)     { $name += "_$gitSha" }
    $dest = Join-Path $vaultRoot $name
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    Copy-Item $pdbSrc -Destination (Join-Path $dest 'KoliseuClient.pdb') -Force
    Copy-Item (Join-Path $repo $exe) -Destination (Join-Path $dest $exe) -Force   # keep the exact exe too
    $info = @(
      "archived : $stamp",
      "git      : $(if ($gitSha) { $gitSha } else { '(no git)' })",
      "rev      : $(if ($Rev -ne '') { $Rev } else { '(none)' })",
      "env      : $(if ($Env -ne '') { $Env } else { 'prod' })"
    ) -join "`r`n"
    [System.IO.File]::WriteAllText((Join-Path $dest 'build-info.txt'), "$info`r`n", (New-Object System.Text.UTF8Encoding($false)))
    Write-Host ("  archived PDB -> {0}\ ({1:N0} MB)" -f $dest, ((Get-Item $pdbSrc).Length / 1MB)) -ForegroundColor Green
  } else {
    Write-Host "  WARNING: KoliseuClient.pdb not found in repo root -> this build's crash dumps" -ForegroundColor Yellow
    Write-Host "           won't be symbolizable. Build via compile.ps1 -Config DirectX first, and" -ForegroundColor Yellow
    Write-Host "           avoid -SkipBuild right after a dev rebuild that overwrote the PDB." -ForegroundColor Yellow
  }
}

# --- stage the client VFS into a temp tree (NEVER the dev tree) -------------------
# We stage a COPY because (1) we flip DEVELOPERMODE off in the shipped init.lua and
# (2) --encrypt rewrites files in place. The dev tree must stay pristine.
$stage = Join-Path $rel "_stage"
New-Item -ItemType Directory -Force -Path $stage | Out-Null
foreach ($i in @('modules', 'mods', 'data')) {
  $src = Join-Path $repo $i
  if (-not (Test-Path $src)) { throw "missing data item: $i" }
  Copy-Item $src -Destination $stage -Recurse -Force
}
# init.lua: use init.<env>.lua if it exists, otherwise the shared init.lua.
$initSrc = Join-Path $repo 'init.lua'
if ($Env -ne "" -and (Test-Path (Join-Path $repo "init.$Env.lua"))) {
  $initSrc = Join-Path $repo "init.$Env.lua"
  Write-Host "  using init.$Env.lua as init.lua" -ForegroundColor Green
}
Copy-Item $initSrc -Destination (Join-Path $stage 'init.lua') -Force

# --- flip DEVELOPERMODE off in the SHIPPED init.lua (BOM-safe write) --------------
$stageInit = Join-Path $stage 'init.lua'
$initTxt = [System.IO.File]::ReadAllText($stageInit)
$initTxt = $initTxt -replace 'DEVELOPERMODE\s*=\s*true', 'DEVELOPERMODE = false'
[System.IO.File]::WriteAllText($stageInit, $initTxt, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "  init.lua: DEVELOPERMODE = false (terminal/Draw/Debug/profiler hidden)" -ForegroundColor Green

# --- bundle the prod/test config as /config.lua INSIDE data.zip -------------------
# Stays plaintext (public URLs); at runtime m_customEncryption is 0 so a non-encrypted
# file loads fine, and the container layer makes it unbrowsable anyway. NEVER the dev config.lua.
$zipNames = @('init.lua', 'modules', 'mods', 'data')
$cfg = Join-Path $repo $ConfigFile
if (Test-Path $cfg) {
  Copy-Item $cfg -Destination (Join-Path $stage 'config.lua') -Force
  $zipNames += 'config.lua'
  Write-Host "  bundled $ConfigFile as /config.lua inside data.zip" -ForegroundColor Green
} else {
  Write-Host "  WARNING: $ConfigFile not found -> data.zip ships NO config.lua" -ForegroundColor Yellow
  Write-Host "           (client falls back to init.lua's built-in defaults)." -ForegroundColor Yellow
}

# --- optional: per-file encryption (Lua bytecode + AES-GCM), in place, on the stage --
if ($Encrypt) {
  Write-Host "Encrypting staged data (per-file: KoliseuClient.exe --encrypt)..." -ForegroundColor Cyan
  # The exe implicitly imports the ANGLE DLLs, so it needs them next to it to even
  # start -- even for the encrypt/pack paths. For --encrypt cwd MUST be the stage:
  # encrypt() walks ./data ./modules ./mods ./layouts + init.lua relative to cwd.
  foreach ($f in @($exe) + $dlls) { Copy-Item (Join-Path $repo $f) -Destination $stage -Force }
  $p = Start-Process -FilePath (Join-Path $stage $exe) -ArgumentList '--encrypt', '--quiet' `
        -WorkingDirectory $stage -NoNewWindow -Wait -PassThru
  if ($p.ExitCode -ne 0) { throw "per-file encryption failed (exit $($p.ExitCode))" }
  Write-Host "  per-file: Lua bytecode + AES-GCM (config.lua left plaintext, public URLs)" -ForegroundColor Green
}

# --- assemble data.zip ------------------------------------------------------------
# Zip an explicit name list from the stage (the exe/DLLs/log copied above are excluded).
$dataZip = Join-Path $rel "data.zip"
$zipItems = $zipNames | ForEach-Object { Join-Path $stage $_ }

if ($Encrypt -and $Container) {
  # Build a plain zip first, then wrap it in the opaque encrypted container.
  $tmpZip = Join-Path $rel "_data_plain.zip"
  Write-Host "Zipping intermediate archive..." -ForegroundColor Cyan
  Compress-Archive -Path $zipItems -DestinationPath $tmpZip -CompressionLevel Optimal -Force
  Write-Host "Packing opaque container (KoliseuClient.exe --pack -> data.zip)..." -ForegroundColor Cyan
  $packArgs = @('--pack', "`"$tmpZip`"", "`"$dataZip`"")
  $p = Start-Process -FilePath (Join-Path $stage $exe) -ArgumentList $packArgs `
        -WorkingDirectory $stage -NoNewWindow -Wait -PassThru
  if ($p.ExitCode -ne 0) { throw "container pack failed (exit $($p.ExitCode))" }
  Remove-Item -Force $tmpZip
  Write-Host "  data.zip = opaque AES-GCM container (no PK signature, unbrowsable)" -ForegroundColor Green
} else {
  Write-Host "Zipping data.zip..." -ForegroundColor Cyan
  Compress-Archive -Path $zipItems -DestinationPath $dataZip -CompressionLevel Optimal -Force
}
Write-Host ("  data.zip: {0:N1} MB" -f ((Get-Item $dataZip).Length / 1MB))

# --- drop the stage ---
Remove-Item -Recurse -Force $stage

# --- optional: update manifest ----------------------------------------------------
# NOTE: the per-file CRCs in update.json assume a BROWSABLE archive. The opaque
# container hides the entries, so don't combine -Container with the in-client updater.
if ($Url -ne "") {
  $py = (Get-Command python -ErrorAction SilentlyContinue).Source
  if (-not $py) { $py = (Get-Command py -ErrorAction SilentlyContinue).Source }
  if ($py) {
    $binName = if ($Rev -ne "") { "KoliseuClient-$Rev.exe" } else { $exe }
    & $py "$repo\tools\gen_update_manifest.py" $dataZip --url $Url `
        --binary (Join-Path $rel $exe) --binary-name $binName -o (Join-Path $rel "update.json")
    Write-Host "  generated update.json (url=$Url, binary=$binName)" -ForegroundColor Green
  } else {
    Write-Host "  python not found -> skipped update.json" -ForegroundColor Yellow
  }
}

Write-Host "`nRelease ready: $rel" -ForegroundColor Green
Get-ChildItem $rel | ForEach-Object { "  {0,-26} {1,8:N0} KB" -f $_.Name, ($_.Length / 1KB) }
