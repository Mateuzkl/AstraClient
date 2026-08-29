# Aplica em lote as larguras que o otui-textfit.ps1 pediu.
#
# A licao que este script existe para nao repetir: numa passagem anterior um sed
# por numero de linha pegou o `size:` do bloco SEGUINTE e redimensionou o widget
# errado no cyclopedia.otui. Aqui a escrita so acontece se o valor encontrado bater
# exatamente com a CAIXA que a varredura reportou, e a busca fica presa ao bloco do
# widget: mesma indentacao do `text:`, nunca a de um filho ou de um irmao.
#
#   .\tools\otui-fitfix.ps1 -WhatIf              # so mostra o que faria
#   .\tools\otui-fitfix.ps1 -Types Button        # aplica so nos botoes
#   .\tools\otui-fitfix.ps1 -Path mods/game_report
param(
    [string]$Path = "",
    # Regex do tipo de widget. Vazio = todos os que a varredura achar.
    [string]$Types = "",
    # Respiro entre o texto e a borda da caixa, somado ao que a varredura pediu.
    [int]$Pad = 10,
    # Tambem escreve `width:` em quem nao declara tamanho nenhum.
    [switch]$FixUnsized,
    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot

$scanArgs = @{}
if ($Path) { $scanArgs['Path'] = $Path }
$raw = & (Join-Path $PSScriptRoot 'otui-textfit.ps1') @scanArgs

$findings = @()
foreach ($line in $raw) {
    if ($line -match '^(\S+)\s+(\d+)\s+(largura|sem-tam)\s+(\S+)\s+(\d+)\s+(\d+)\s+(.*)$') {
        $findings += [pscustomobject]@{
            File = $Matches[1]; Line = [int]$Matches[2]; Kind = $Matches[3]
            Type = $Matches[4]; Box = [int]$Matches[5]; Need = [int]$Matches[6]
            Text = $Matches[7].Trim()
        }
    }
}
if ($Types) { $findings = $findings | Where-Object { $_.Type -match $Types } }
if (-not $FixUnsized) { $findings = $findings | Where-Object { $_.Kind -eq 'largura' } }

# par para o grid de 2px em que o resto da skin e desenhada
function Round2([int]$n) { if ($n % 2) { return $n + 1 } return $n }

$applied = 0; $skipped = 0
foreach ($group in ($findings | Group-Object File)) {
    $full = Join-Path $repo $group.Name
    if (-not (Test-Path $full)) { Write-Output "AUSENTE $($group.Name)"; continue }
    $lines = [System.IO.File]::ReadAllLines($full)
    $touched = $false

    # de baixo para cima: escrever nao desloca as linhas ainda por processar
    foreach ($f in ($group.Group | Sort-Object Line -Descending)) {
        $idx = $f.Line - 1
        if ($idx -lt 0 -or $idx -ge $lines.Count) { Write-Output "FORA   $($f.File):$($f.Line)"; $skipped++; continue }
        $indent = ($lines[$idx] -replace '^(\s*).*$', '$1').Length

        # limites do bloco: sobe ate o cabecalho (indentacao menor), desce enquanto
        # a indentacao continuar sendo do bloco ou de um filho dele
        $start = $idx
        while ($start -gt 0) {
            $l = $lines[$start - 1]
            if ($l -match '^\s*$' -or $l -match '^\s*//') { $start--; continue }
            if ((($l -replace '^(\s*).*$', '$1').Length) -lt $indent) { break }
            $start--
        }
        $end = $idx
        while ($end -lt $lines.Count - 1) {
            $l = $lines[$end + 1]
            if ($l -match '^\s*$' -or $l -match '^\s*//') { $end++; continue }
            if ((($l -replace '^(\s*).*$', '$1').Length) -lt $indent) { break }
            $end++
        }

        $newWidth = Round2 ($f.Need + $Pad)
        $done = $false
        for ($j = $start; $j -le $end -and -not $done; $j++) {
            $l = $lines[$j]
            if ((($l -replace '^(\s*).*$', '$1').Length) -ne $indent) { continue }   # filho, nao o bloco
            if ($l -match '^(\s*)size:\s*(\d+)\s+(\d+)\s*$') {
                if ([int]$Matches[2] -ne $f.Box) { continue }                        # nao e o widget da varredura
                $lines[$j] = "$($Matches[1])size: $newWidth $($Matches[3])"
                $done = $true
            }
            elseif ($l -match '^(\s*)width:\s*(\d+)\s*$') {
                if ([int]$Matches[2] -ne $f.Box) { continue }
                $lines[$j] = "$($Matches[1])width: $newWidth"
                $done = $true
            }
        }

        if (-not $done -and $f.Kind -eq 'sem-tam' -and $FixUnsized) {
            $pre = ' ' * $indent
            $lines = $lines[0..$idx] + @("${pre}width: $newWidth") + $lines[($idx + 1)..($lines.Count - 1)]
            $done = $true
        }

        if ($done) {
            $applied++
            Write-Output ("OK     {0}:{1,-5} {2,-20} {3,3} -> {4,3}  {5}" -f $f.File, $f.Line, $f.Type, $f.Box, $newWidth, $f.Text)
            $touched = $true
        } else {
            $skipped++
            Write-Output ("PULOU  {0}:{1,-5} {2,-20} caixa {3} nao encontrada no bloco  {4}" -f $f.File, $f.Line, $f.Type, $f.Box, $f.Text)
        }
    }

    if ($touched -and -not $WhatIf) {
        # WriteAllText com \n explicito, nao WriteAllLines: o Set-Content -Encoding utf8 do
        # PS 5.1 grava BOM, e o WriteAllLines junta com Environment.NewLine, que no Windows
        # e CRLF - os .otui do repo sao LF, entao ele reescreveria o arquivo inteiro e
        # afogaria a mudanca real num diff de milhares de linhas.
        $text = ($lines -join "`n") + "`n"
        [System.IO.File]::WriteAllText($full, $text, (New-Object System.Text.UTF8Encoding($false)))
    }
}

Write-Output ""
Write-Output "$applied aplicados, $skipped pulados$(if ($WhatIf) { ' (WhatIf: nada foi escrito)' })"
