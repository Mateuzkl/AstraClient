param(
    [Parameter(Mandatory)][string]$Binary,
    [string]$TempRoot = [IO.Path]::GetTempPath(),
    [ValidateSet('core', 'skilltree')][string]$Scenario = 'core',
    [ValidateSet('', '-warp', '-dx11', '-opengl')][string]$GraphicsBackend = ''
)
$ErrorActionPreference = 'Stop'
$binaryPath = (Resolve-Path -LiteralPath $Binary).Path
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$fixture = Join-Path $TempRoot ('astra-rmlui-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $fixture 'modules'), (Join-Path $fixture 'data\fonts'), (Join-Path $fixture 'data\styles') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $fixture 'data\images\ui') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $repo 'data\images\ui\background.png') -Destination (Join-Path $fixture 'data\images\ui')
Copy-Item -LiteralPath (Join-Path $repo 'tests\rendering\scene.lua') -Destination (Join-Path $fixture 'render-scene.lua')
Copy-Item -LiteralPath (Join-Path $repo 'modules\corelib') -Destination (Join-Path $fixture 'modules') -Recurse
Copy-Item -LiteralPath (Join-Path $repo 'data\fonts\rml') -Destination (Join-Path $fixture 'data\fonts') -Recurse
Copy-Item -LiteralPath (Join-Path $repo 'data\styles\rml') -Destination (Join-Path $fixture 'data\styles') -Recurse
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'bootstrap.lua') -Destination (Join-Path $fixture 'init.lua')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'test.lua'), (Join-Path $PSScriptRoot 'smoke.rml') -Destination $fixture
if ($Scenario -eq 'skilltree') {
    Copy-Item -LiteralPath (Join-Path $repo 'modules\game_rmlskilltree') -Destination (Join-Path $fixture 'modules') -Recurse
    foreach ($folder in @('spells', 'tutorial')) { New-Item -ItemType Directory -Path (Join-Path $fixture "data\images\game\$folder") -Force | Out-Null }
    Copy-Item -LiteralPath (Join-Path $repo 'data\images\game\spells\spell-icons-32x32.png') -Destination (Join-Path $fixture 'data\images\game\spells')
    Copy-Item -LiteralPath (Join-Path $repo 'data\images\game\tutorial\backdrop_knight.png') -Destination (Join-Path $fixture 'data\images\game\tutorial')
    Copy-Item -LiteralPath (Join-Path $repo 'modules\gamelib\spells.lua') -Destination (Join-Path $fixture 'spell-catalog.lua')
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'skilltree.lua') -Destination (Join-Path $fixture 'test.lua')
}
$stdout = Join-Path $fixture 'stdout.log'
$stderr = Join-Path $fixture 'stderr.log'
$clientArguments = @('--test')
if ($GraphicsBackend) { $clientArguments += $GraphicsBackend }
$process = Start-Process -FilePath $binaryPath -ArgumentList $clientArguments -WorkingDirectory $fixture -WindowStyle Hidden `
    -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
if (-not $process.WaitForExit(45000)) {
    $process.Kill()
    throw "Isolated RmlUi smoke timed out. Artifacts: $fixture"
}
$process.Refresh()
$log = if (Test-Path -LiteralPath (Join-Path $fixture 'astra_rmlui_smoke.log')) {
    Get-Content -LiteralPath (Join-Path $fixture 'astra_rmlui_smoke.log') -Raw
} else { Get-Content -LiteralPath $stdout -Raw }
$log
if ($process.ExitCode -ne 0 -or $log -notmatch '\[RMLUI TEST\] PASS:') {
    Get-Content -LiteralPath $stderr
    throw "RmlUi smoke failed (exit $($process.ExitCode)). Artifacts: $fixture"
}
if ($log -match 'ERROR:|FreeType error') { throw "RmlUi logged an error. Artifacts: $fixture" }
if ($GraphicsBackend -in @('-warp', '-dx11') -and $log -notmatch 'backend ANGLE ES') {
    throw "DirectX smoke did not initialize the ANGLE backend. Artifacts: $fixture"
}
"RmlUi smoke artifacts: $fixture"
