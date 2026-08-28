# Varredura estatica: acha widgets .otui cujo texto estoura a largura fixa na fonte nova.
#
# Contexto: silkscreen-16 e ~1,7x mais largo que o verdana-11px-antialised que ele substitui,
# entao todo layout com largura fixa calibrada pro Verdana corta texto. Este script mede cada
# rotulo com a metrica real da fonte (mesma logica do BitmapFont::calculateGlyphsWidthsAutomatically)
# e lista o que nao cabe, para nao precisar abrir janela por janela no cliente rodando.
#
#   .\tools\otui-textfit.ps1                  # varre modules/ e mods/
#   .\tools\otui-textfit.ps1 -Path modules/game_viplist
#
param(
    [string]$Path = "",
    [string]$Font = "data/fonts/silkscreen-16.png",
    [int]$GlyphSize = 16,
    [int]$FirstGlyph = 32,
    [int]$SpaceWidth = 8,
    # Desligado por padrao: o cliente nao corta texto na altura do widget (os checkboxes de
    # 12px da tela de login exibem rotulos de 16px inteiros), entao isso so gera ruido.
    # Ligue se estiver caçando um caso com `clipping: true` no pai.
    [switch]$CheckHeight
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$repo = Split-Path -Parent $PSScriptRoot
$fontPath = Join-Path $repo $Font
if (-not (Test-Path $fontPath)) { throw "atlas nao encontrado: $fontPath" }

# --- larguras dos glifos, lidas do atlas do mesmo jeito que a engine faz ---
$bmp = New-Object System.Drawing.Bitmap($fontPath)
$rect = New-Object System.Drawing.Rectangle(0, 0, $bmp.Width, $bmp.Height)
$data = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly,
                      [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$bytes = New-Object byte[] ($data.Stride * $bmp.Height)
[System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $bytes, 0, $bytes.Length)
$bmp.UnlockBits($data)
$stride = $data.Stride

$cols = [Math]::Floor($bmp.Width / $GlyphSize)
$rows = [Math]::Floor($bmp.Height / $GlyphSize)
$gw = @{}   # largura de avanco, como a engine calcula
$gh = @{}   # ultima linha com tinta - a maioria dos glifos para na 13, so Q q & _ , $ | descem ate 15
for ($off = 0; $off -lt ($cols * $rows); $off++) {
    $glyph = $FirstGlyph + $off
    $cx = ($off % $cols) * $GlyphSize
    $cy = [Math]::Floor($off / $cols) * $GlyphSize
    $width = $GlyphSize; $inkBottom = -1
    for ($x = 0; $x -lt $GlyphSize; $x++) {
        $filled = $false
        for ($y = 0; $y -lt $GlyphSize; $y++) {
            if ($bytes[(($cy + $y) * $stride) + (($cx + $x) * 4) + 3] -ne 0) {
                $filled = $true
                if ($y -gt $inkBottom) { $inkBottom = $y }
            }
        }
        if ($filled) { $width = $x + 1 }
    }
    $gw[$glyph] = $width
    $gh[$glyph] = $inkBottom
}
$gw[32] = $SpaceWidth
$gh[32] = -1
$bmp.Dispose()

function Measure-Text([string]$s) {
    $total = 0
    foreach ($ch in $s.ToCharArray()) {
        $code = [int]$ch
        if ($gw.ContainsKey($code)) { $total += $gw[$code] } else { $total += $GlyphSize }
    }
    return $total
}

# altura que ESTE texto realmente ocupa, nao a altura nominal da fonte
function Measure-TextHeight([string]$s) {
    $deepest = -1
    foreach ($ch in $s.ToCharArray()) {
        $code = [int]$ch
        if ($gh.ContainsKey($code) -and $gh[$code] -gt $deepest) { $deepest = $gh[$code] }
    }
    return $deepest + 1
}

# --- varre os .otui ---
$roots = if ($Path) { @(Join-Path $repo $Path) } else { @((Join-Path $repo "modules"), (Join-Path $repo "mods")) }
$files = $roots | Where-Object { Test-Path $_ } | ForEach-Object { Get-ChildItem $_ -Recurse -Filter *.otui }

$findings = @()
foreach ($file in $files) {
    $lines = Get-Content $file.FullName
    # um "bloco" e o widget corrente; propriedades vivem num nivel de indentacao maior
    $blockIndent = -1; $text = $null; $box = 0; $boxH = 0; $autoResize = $false; $textLine = 0
    $usesFont = $false; $wrap = $false; $anyFont = $false; $typeInherits = $false
    $flush = {
        # so interessa quem realmente cai na fonte nova: Button usa cipsoftFont (8px) e nao muda
        # Label e MenuLabel herdam silkscreen-16 de 10-labels.otui quando nao declaram fonte.
        # FlatLabel e GameLabel derivam direto de UILabel e seguem em Verdana - nao entram.
        if ($typeInherits -and -not $anyFont) { $usesFont = $true }
        if ($text -and $usesFont) {
            $need = Measure-Text $text
            # altura: compara com a tinta real do texto. Uma caixa de 15px so corta se o
            # rotulo tiver Q q & _ , $ ou | - o resto dos glifos para na linha 13.
            $needH = Measure-TextHeight $text
            if ($CheckHeight -and $boxH -gt 0 -and $boxH -lt $needH) {
                $script:findings += [pscustomobject]@{
                    File = $file.FullName.Substring($repo.Length + 1).Replace('\', '/')
                    Line = $textLine; Text = $text; Kind = 'altura'
                    Box  = $boxH; Need = $needH; Overflow = $needH - $boxH
                }
            }
            # largura so importa quando o texto nao quebra nem se auto-redimensiona
            if ($box -gt 0 -and -not $autoResize -and -not $wrap -and $need -gt $box) {
                $script:findings += [pscustomobject]@{
                    File = $file.FullName.Substring($repo.Length + 1).Replace('\', '/')
                    Line = $textLine; Text = $text; Kind = 'largura'
                    Box  = $box; Need = $need; Overflow = $need - $box
                }
            }
        }
        $script:text = $null; $script:box = 0; $script:boxH = 0
        $script:autoResize = $false; $script:usesFont = $false; $script:wrap = $false
        $script:anyFont = $false; $script:typeInherits = $false
    }
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line -match '^\s*$' -or $line -match '^\s*//') { continue }
        $indent = ($line -replace '^(\s*).*$', '$1').Length

        # linha de propriedade? (contem ':' e nao abre bloco novo no mesmo nivel)
        if ($line -match '^\s*!?text:\s*(?:tr\()?[''"]([^''"]+)[''"]') {
            $text = $Matches[1]; $textLine = $i + 1
        }
        elseif ($line -match '^\s*size:\s*(\d+)\s+(\d+)') { $box = [int]$Matches[1]; $boxH = [int]$Matches[2] }
        elseif ($line -match '^\s*width:\s*(\d+)') { $box = [int]$Matches[1] }
        elseif ($line -match '^\s*height:\s*(\d+)') { $boxH = [int]$Matches[1] }
        elseif ($line -match '^\s*text-wrap:\s*true') { $wrap = $true }
        elseif ($line -match '^\s*text-auto-resize:\s*true') { $autoResize = $true }
        elseif ($line -match '^\s*font:') {
            $anyFont = $true
            if ($line -match '^\s*font:\s*(\$var-cip-font|silkscreen-16)\s*$') { $usesFont = $true }
        }
        elseif ($line -notmatch ':') {
            # nome de widget = novo bloco; fecha o anterior
            & $flush
            $blockIndent = $indent
            if ($line -match '^\s*(Label|MenuLabel)\s*$') { $typeInherits = $true }
        }
    }
    & $flush
}

if (-not $findings) { Write-Output "nenhum estouro encontrado."; return }

Write-Output ""
Write-Output ("{0,-50} {1,5} {2,8} {3,5} {4,5}  {5}" -f "ARQUIVO", "LINHA", "TIPO", "CAIXA", "PREC.", "TEXTO")
Write-Output ("-" * 115)
foreach ($f in ($findings | Sort-Object -Property Kind, Overflow -Descending)) {
    Write-Output ("{0,-50} {1,5} {2,8} {3,5} {4,5}  {5}" -f $f.File, $f.Line, $f.Kind, $f.Box, $f.Need, $f.Text)
}
Write-Output ""
$w = ($findings | Where-Object Kind -eq 'largura').Count
$h = ($findings | Where-Object Kind -eq 'altura').Count
Write-Output "$w estouram largura, $h estouram altura, em $(($findings | Select-Object -Unique File).Count) arquivos."
