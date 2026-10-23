#Requires -Version 7.0
param(
    [Parameter(Mandatory)][string]$Output,
    [string]$ThingsDirectory = (Join-Path $PSScriptRoot '../data/things/860'),
    [ValidatePattern('^[a-zA-Z0-9.:\[\]-]+$')][string]$TestServer
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$things = (Resolve-Path -LiteralPath $ThingsDirectory).Path
$destination = [IO.Path]::GetFullPath($Output)
if (Test-Path -LiteralPath $destination) { throw "Refusing to overwrite $destination" }
$files = @(& git -C $repo ls-files -- data layouts modules mods init.lua)
if ($LASTEXITCODE -ne 0) { throw 'Cannot enumerate tracked client assets.' }
$files = @($files | Where-Object { $_ -notlike 'data/things/*' })
foreach ($name in @('Tibia.dat','Tibia.spr')) {
    if (-not (Test-Path -LiteralPath (Join-Path $things $name) -PathType Leaf)) { throw "Missing $name in $things" }
}
New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($destination)) -Force | Out-Null
$stream = [IO.File]::Open($destination, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
$archive = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create)
function Add-Asset([string]$Path,[string]$Entry,$Text) {
    if ((Get-Item -LiteralPath $Path).Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw "Refusing symbolic link in asset pack: $Entry"
    }
    $entryStream = $archive.CreateEntry($Entry,[IO.Compression.CompressionLevel]::Optimal).Open()
    try {
        if ($null -ne $Text) {
            $bytes = [Text.UTF8Encoding]::new($false).GetBytes($Text)
            $entryStream.Write($bytes,0,$bytes.Length)
        } else {
            $source = [IO.File]::OpenRead($Path)
            try { $source.CopyTo($entryStream) } finally { $source.Dispose() }
        }
    } finally { $entryStream.Dispose() }
}
try {
    $count = 0
    foreach ($file in $files) {
        $path = Join-Path $repo $file
        $text = $null
        if ($file -eq 'init.lua' -and $TestServer) {
            $text = [IO.File]::ReadAllText($path)
            if ($text -notmatch 'host = "127\.0\.0\.1"' -or $text -notmatch 'ALLOW_CUSTOM_SERVERS = false') {
                throw 'Test-server template changed; refusing to silently package a wrong connection.'
            }
            $text = $text.Replace('host = "127.0.0.1"', ('host = "' + $TestServer + '"'))
            $text = $text.Replace('ALLOW_CUSTOM_SERVERS = false', 'ALLOW_CUSTOM_SERVERS = true')
        }
        Add-Asset $path $file $text
        if (++$count % 100 -eq 0) { Write-Progress -Activity 'Packaging tracked Android assets' -PercentComplete (100*$count/$files.Count) }
    }
    foreach ($name in @('Tibia.dat','Tibia.spr','Tibia.otfi')) {
        $path = Join-Path $things $name
        if (Test-Path -LiteralPath $path -PathType Leaf) { Add-Asset $path "data/things/860/$name" $null }
    }
} finally {
    $archive.Dispose()
    $stream.Dispose()
    Write-Progress -Activity 'Packaging tracked Android assets' -Completed
}
Write-Output "Android assets: $destination"
