#Requires -Version 5.1
param([string]$TempRoot = [IO.Path]::GetTempPath())
$ErrorActionPreference = 'Stop'
$runner = Join-Path $PSScriptRoot 'Run-LiveSession.ps1'
$tokens = $null
$parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($runner, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw 'Live-session runner has syntax errors.' }
$tryBlock = $ast.Find({ param($node) $node -is [Management.Automation.Language.TryStatementAst] }, $false)
# Run only the production JSON serialization statements, never the client/login.
$serialize = [ScriptBlock]::Create(($tryBlock.Body.Statements[0..1] | ForEach-Object { $_.Extent.Text }) -join "`n")
$Account = 'synthetic-account'
$Password = 'not-a-real-password'
$Character = 'Unicode-' + [char]0x00E7
$ServerHost = '127.0.0.1'
$Port = 7171
$Version = 860
$credentialFile = Join-Path (Resolve-Path -LiteralPath $TempRoot).Path ('astra-encoding-' + [guid]::NewGuid().ToString('N') + '.json')
try {
    & $serialize
    $bytes = [IO.File]::ReadAllBytes($credentialFile)
    if ($bytes.Length -lt 3 -or ($bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191)) {
        throw 'Session JSON is empty or has a UTF-8 BOM.'
    }
    $decoded = (New-Object Text.UTF8Encoding $false, $true).GetString($bytes) | ConvertFrom-Json
    foreach ($key in @('Account', 'Password', 'Character', 'ServerHost', 'Port', 'Version')) {
        $jsonKey = if ($key -eq 'ServerHost') { 'host' } else { $key.ToLowerInvariant() }
        if ($decoded.$jsonKey -cne (Get-Variable -Name $key -ValueOnly)) { throw "JSON field changed: $key" }
    }
    "Live-session JSON: PASS (UTF-8 without BOM, PowerShell $($PSVersionTable.PSVersion))"
} finally {
    # Only this synthetic, uniquely named file; no credentials or live-client files.
    if (Test-Path -LiteralPath $credentialFile) { Remove-Item -LiteralPath $credentialFile }
}
