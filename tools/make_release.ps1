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
# Every run bumps CLIENT_RELEASE_VERSION in init.lua (patch) and prints the version. With
# -Publish it also zips release/, creates+uploads a GitHub release, and POSTs the new
# version + download URL to the server (/api/client/publish) so the Launcher and the login
# gate go live automatically. -Publish needs: gh authenticated + $env:KOLISEU_PUBLISH_TOKEN.
#
# Usage:
#   .\tools\make_release.ps1                                  # prod, no encryption (bumps version)
#   .\tools\make_release.ps1 -Env test -Encrypt              # TEST client, per-file encrypted
#   .\tools\make_release.ps1 -Env test -Encrypt -Container   # + opaque container
#   .\tools\make_release.ps1 -SkipBuild -Env test -Encrypt
#   .\tools\make_release.ps1 -Env prod -Encrypt -Publish     # + GitHub release + publish to server (prod)
#   .\tools\make_release.ps1 -Env test -Encrypt -Publish -NoBump  # publish 2nd env of the same build
#   .\tools\make_release.ps1 -Env prod -Encrypt -Publish -Version 1.2.0  # set an explicit version
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
  [switch]$NoArchivePdb,                   # skip archiving the PDB into the symbol vault
  [switch]$Publish,                        # zip release/, create+upload a GitHub release, and publish version+url to the server
  [switch]$NoBump,                         # do NOT bump CLIENT_RELEASE_VERSION (remount the same version, e.g. 2nd env of one build)
  [string]$Version = "",                   # set CLIENT_RELEASE_VERSION explicitly (x.y.z) instead of auto-bumping the patch
  [string]$ReleaseRepo = "JoaoCRDias/kot-files",  # GitHub repo (owner/name) that hosts the release zips ($repo below is the local path -- distinct var; PS names are case-insensitive so do NOT call this $Repo)
  [switch]$Yes                             # skip the interactive production-publish confirmation
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

# --- resolve publish target + confirm production up front (before any heavy work) ---
# Do this FIRST so aborting a production publish costs nothing (no build, no version bump).
# $publishEnv/$publishHost are reused by the actual publish step at the end.
if ($Publish) {
  if ($Env -eq "test") {
    $publishEnv = "testServer"; $publishHost = "https://gameteste.koliseuot.com.br"
  } else {
    $publishEnv = "production"; $publishHost = "https://game.koliseuot.com.br"
  }
  if ([string]::IsNullOrEmpty($env:KOLISEU_PUBLISH_TOKEN)) { throw "KOLISEU_PUBLISH_TOKEN is not set (required for -Publish)" }
  if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw "GitHub CLI 'gh' not found (required for -Publish)" }
  if ($publishEnv -eq "production" -and -not $Yes) {
    $answer = Read-Host "About to build AND PUBLISH to PRODUCTION ($publishHost). Type 'yes' to continue"
    if ($answer -ne "yes") { Write-Host "Aborted before any work." -ForegroundColor Yellow; exit 1 }
  }
}

# -Env test|prod is a shortcut: it selects config.<env>.lua (unless -ConfigFile was
# given explicitly) and, if present, an init.<env>.lua override. The env-specific
# part is the CONFIG (URLs); init.lua is normally shared (DEVELOPERMODE is flipped
# off below regardless), so init.<env>.lua is optional.
if ($Env -ne "" -and -not $PSBoundParameters.ContainsKey('ConfigFile')) {
  $ConfigFile = "config.$Env.lua"
}

# --- resolve + bump the release version (init.lua CLIENT_RELEASE_VERSION) -----------
# The distribution version lives in init.lua (baked into data.zip, encrypted) and is the
# single source of truth the login gate checks. Bump it here so every release gets a fresh
# version that we ALSO publish to the server (client embeds X, server requires X). We bump
# the same file that gets packaged (init.<env>.lua if present, else the shared init.lua).
#   default  -> auto-bump the patch (1.0.6 -> 1.0.7)
#   -NoBump  -> keep the current version (e.g. packaging the 2nd environment of one build)
#   -Version -> set it explicitly (x.y.z)
$initForVersion = Join-Path $repo 'init.lua'
if ($Env -ne "" -and (Test-Path (Join-Path $repo "init.$Env.lua"))) {
  $initForVersion = Join-Path $repo "init.$Env.lua"
}
$initVerTxt = [System.IO.File]::ReadAllText($initForVersion)
$verMatch = [regex]::Match($initVerTxt, 'CLIENT_RELEASE_VERSION\s*=\s*"([^"]+)"')
if (-not $verMatch.Success) { throw "CLIENT_RELEASE_VERSION not found in $initForVersion" }
$currentVersion = $verMatch.Groups[1].Value

if ($Version -ne "") {
  if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw "-Version must be x.y.z, got '$Version'" }
  $releaseVersion = $Version
} elseif ($NoBump) {
  $releaseVersion = $currentVersion
} else {
  if ($currentVersion -notmatch '^\d+\.\d+\.\d+$') { throw "current CLIENT_RELEASE_VERSION '$currentVersion' is not x.y.z; pass -Version" }
  $vp = $currentVersion -split '\.'
  $vp[2] = [string]([int]$vp[2] + 1)
  $releaseVersion = $vp -join '.'
}

if ($releaseVersion -ne $currentVersion) {
  # Regex-replace only the version literal so the file's CRLF endings and everything else
  # stay intact; write with no BOM (matches the DEVELOPERMODE flip below).
  $newVerTxt = [regex]::Replace($initVerTxt, 'CLIENT_RELEASE_VERSION\s*=\s*"[^"]+"', "CLIENT_RELEASE_VERSION = `"$releaseVersion`"")
  [System.IO.File]::WriteAllText($initForVersion, $newVerTxt, (New-Object System.Text.UTF8Encoding($false)))
  Write-Host ("  release version: {0} -> {1}  (bumped in {2})" -f $currentVersion, $releaseVersion, (Split-Path -Leaf $initForVersion)) -ForegroundColor Green
} else {
  Write-Host ("  release version: {0} (unchanged)" -f $releaseVersion) -ForegroundColor Green
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

Write-Host "`nRelease ready: $rel  (version $releaseVersion)" -ForegroundColor Green
Get-ChildItem $rel -File | ForEach-Object { "  {0,-34} {1,8:N0} KB" -f $_.Name, ($_.Length / 1KB) }

# --- optional: publish to GitHub Releases + client_version (make the release live) --
# Zips release/ (exe + DLLs + data.zip), creates/updates a GitHub release + uploads the
# zip, then POSTs version + download_url to the server's /api/client/publish so the
# Launcher (and the login gate) pick up the new version. Idempotent: safe to re-run.
# $publishEnv/$publishHost + the token/gh/prod-confirmation were resolved at the top.
if ($Publish) {
  Write-Host "`nPublishing $publishEnv/otc v$releaseVersion ..." -ForegroundColor Cyan

  # 1. zip exe + DLLs + data.zip (the launcher downloads this zip and extracts it)
  $zipName = "KoliseuClient-$publishEnv-$releaseVersion.zip"
  $zipPath = Join-Path $rel $zipName
  if (Test-Path $zipPath) { Remove-Item -Force $zipPath }
  $zipSource = @($exe) + $dlls + @('data.zip') | ForEach-Object { Join-Path $rel $_ }
  Compress-Archive -Path $zipSource -DestinationPath $zipPath -CompressionLevel Optimal -Force
  Write-Host ("  zipped {0} ({1:N1} MB)" -f $zipName, ((Get-Item $zipPath).Length / 1MB)) -ForegroundColor Green

  # 2. create the GitHub release if the tag is new, else just (re)upload the asset.
  #    gh prints "release not found" (and progress) to stderr; under $ErrorActionPreference
  #    = 'Stop' that stderr becomes a terminating NativeCommandError in Windows PowerShell
  #    5.1, which would abort the harmless not-found probe below. Drop to 'Continue' across
  #    the gh calls so we branch on $LASTEXITCODE ourselves (restored in finally).
  $tag = "client-v$releaseVersion"
  $prevEAP = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    gh release view $tag --repo $ReleaseRepo *> $null
    if ($LASTEXITCODE -ne 0) {
      gh release create $tag $zipPath --repo $ReleaseRepo --title "KoliseuClient $releaseVersion" --notes "Automated release $releaseVersion." | Out-Null
      if ($LASTEXITCODE -ne 0) { throw "gh release create failed" }
      Write-Host "  created GitHub release $tag" -ForegroundColor Green
    } else {
      gh release upload $tag $zipPath --repo $ReleaseRepo --clobber | Out-Null
      if ($LASTEXITCODE -ne 0) { throw "gh release upload failed" }
      Write-Host "  uploaded asset to existing release $tag" -ForegroundColor Green
    }
  } finally {
    $ErrorActionPreference = $prevEAP
  }

  # 3. asset's browser download URL (deterministic; the publish endpoint allowlists it)
  $downloadUrl = "https://github.com/$ReleaseRepo/releases/download/$tag/$zipName"

  # 4. publish version + url to the server (upserts the active client_version row)
  $body = @{ environment = $publishEnv; client_type = "otc"; version = $releaseVersion; download_url = $downloadUrl } | ConvertTo-Json -Compress
  try {
    Invoke-RestMethod -Method Post -Uri "$publishHost/api/client/publish" `
      -Headers @{ Authorization = "Bearer $($env:KOLISEU_PUBLISH_TOKEN)" } -Body $body -ContentType "application/json" | Out-Null
  } catch {
    throw "publish endpoint failed: $($_.Exception.Message) (the GitHub release $tag is up; fix token/host and re-run -Publish)"
  }

  Write-Host "`n============================================================" -ForegroundColor Green
  Write-Host (" PUBLISHED  {0}/otc  v{1}" -f $publishEnv, $releaseVersion) -ForegroundColor Green
  Write-Host ("   github : {0}" -f $downloadUrl)
  Write-Host ("   server : {0}/api/client/version" -f $publishHost)
  Write-Host "============================================================" -ForegroundColor Green
} else {
  Write-Host ("`n  version {0} built but NOT published -- re-run with -Publish, or set" -f $releaseVersion) -ForegroundColor Yellow
  Write-Host    "  client_version manually in /admin/client. (the bump is already in init.lua)" -ForegroundColor Yellow
}
