# Reskin pixel-art — estado da migração

Branch `telaLOGIN`. Documento de continuidade: leia isto primeiro ao retomar em outra máquina.

## Contexto

A skin pixel-art (sprites cobre/marrom + fonte `silkscreen-16`) começou pela tela de login e
está sendo estendida ao resto do cliente.

O ponto de alavanca é `&var-cip-font` em `data/styles/0-vars.otui`. Essa variável era
**referenciada 1510 vezes em 155 arquivos mas nunca definida** — o OTML resolvia para string
vazia e `UIWidget::setFont` caía em `getDefaultFont()` (= `verdana-11px-antialised`).
Definir a variável vira todas essas telas de uma vez.

## O problema central da migração

`silkscreen-16` é **~1,7x mais largo** que `verdana-11px-antialised` (16px de altura contra 11px).
Todo layout com largura fixa calibrada para o Verdana corta texto quando recebe a fonte nova.

Não há atalho: testei se o atlas era um 8px escalado 2x (daria para gerar uma variante estreita
sem perda) — **não é**, 21,7% dos blocos 2x2 divergem. A fonte é desenhada em 16px de verdade.

Então a migração é tela a tela: trocar a fonte, remedir as larguras, validar rodando.

## Blast radius — menor do que parece

O HUD do jogo (abas de chat, `ATC Helper`, `Soul`/`Cap`, `Map View`, barra de hotkeys, contadores
de fps) **não usa** `$var-cip-font`; define fontes explicitamente. Ficou intacto com o var global
ligado. O que a variável atinge são as janelas modais e de feature.

## Feito e validado rodando

| Tela | Arquivo | Status |
|---|---|---|
| Login (entergame) | `modules/client_entergame/entergame.otui` | ✅ fonte + layout refeitos |
| Título da janela de login | `data/styles/40-entergame.otui` | ✅ |
| Select Character | `modules/client_entergame/characterlist.otui` | ✅ colunas e checkboxes remedidos |
| Chrome compartilhado | `data/styles/10-windows.otui` | ✅ divisor do popupwindow não repete mais |
| `&var-cip-font` definido | `data/styles/0-vars.otui` | ✅ vira as ~155 telas que usavam a var |
| 27 rótulos que cortavam | wheel, cyclopedia, announcement, gem menu, healthcircle, hotkey, graphics, prey, offsets | ⚠️ medidos e corrigidos, **sem validação visual** |
| "Join Discord" no topo | `data/styles/20-topmenu.otui` | ✅ aparecia como "IN DISCO" |
| 73 rótulos sem largura | console, mainpanel, bazaar, soulseal, prey, forge, wheel, cyclopedia, settings, trackers | ⚠️ `text-auto-resize`, cliente sobe limpo, **sem validação visual** |

### Correções de bug que vieram junto (todas pré-existentes, não regressões)

1. `silkscreen-16.otfont` trazia `fixed-glyph-width: 0` — `BitmapFont::load` testa se a chave
   **existe**, não se é não-zero, então todo glifo ficava com largura 0 e a fonte não desenhava
   nada. Estava latente desde que a fonte foi adicionada.
2. `UITextEdit::setTextHidden` ignorava o argumento (`m_textHidden = true` fixo) — os dois olhos
   de mostrar/ocultar eram de mão única. **Exige recompilar** (`vc23`, config `OpenGL|x64`).
3. `popupwindow.png` tem um divisor preto de 2px nas linhas 28-29, e `image-border-top: 27`
   deixava ele dentro da faixa que se repete; qualquer janela acima de ~207px repetia a linha.
4. `client_background.updateBoostedInfo` não existe — a chamada nil abortava
   `finishCharacterList` antes do `CharacterList.show()` e travava o login depois de autenticar.
5. Estados `$pressed`/`$hover` dos botões de olho sobrescreviam o `setImageSource` do Lua.

## Armadilha recorrente: `image-offset` das setas de ordenação

Ao **estreitar** um `UIButton` que tem `image-offset`, a seta pode cair fora do widget — e isso
desloca o cálculo do texto, jogando o label para fora da janela. Aconteceu com `characterSort`.
Sempre reduza o `image-offset` junto com a largura (regra: `largura - 7 - 4`).

## A ferramenta: `tools/otui-textfit.ps1`

Varredura estática que mede cada rótulo `.otui` com a métrica real do atlas (mesma regra do
`BitmapFont::calculateGlyphsWidthsAutomatically`) e lista o que não cabe na largura fixa.
Muito mais rápido que abrir 155 janelas no cliente rodando.

```powershell
.\tools\otui-textfit.ps1                          # varre modules/ e mods/
.\tools\otui-textfit.ps1 -Path mods/game_wheel    # escopo menor
```

Duas lições que ela incorpora, para não reintroduzir ruído:

- **Não checa altura por padrão.** O cliente não corta texto na altura do widget — a tela de
  login desenha rótulos de 16px ao lado de checkboxes de 12px inteiros. Além disso quase todo
  glifo termina na linha 13; só `Q q & _ , $ |` chegam à 15. Checar altura nominal gerava 204
  falso-positivos. Use `-CheckHeight` só ao caçar um caso com `clipping: true` no pai.
- **Filtra por fonte real.** `Button` usa `cipsoftFont` (8px) e nunca estoura; incluí-lo
  enterrava os achados reais sob ~100 falso-positivos. `Label` e `MenuLabel` herdam
  silkscreen-16 quando não declaram fonte; `FlatLabel` e `GameLabel` seguem em Verdana.

Ao aplicar correções em lote, **confira que a largura encontrada bate com a que a varredura
reportou** antes de escrever — numa passagem anterior o sed redimensionou o widget errado no
`cyclopedia.otui` porque pegou o `size:` do bloco seguinte.

## Próximos passos, em ordem

### 1. Os 2 templates de estilo que sobraram

`.\tools\otui-textfit.ps1` hoje reporta **0 largura, 0 altura, 2 sem-tamanho**. Eram 75 em 33
arquivos. Os 73 resolvidos levaram `text-auto-resize: true`, que é independente de fonte.

Os 2 restantes são **templates**, não instâncias, e por isso ficaram de fora:

- `VipGroupBox < CheckBox` em `modules/game_viplist/editvip.otui:2`
- `EventsScheduleLabel < UIWidget` em `modules/client_background/background.otui:3`

Mexer neles muda **todas** as instâncias de uma vez. Veja os pontos de uso antes de decidir.

> Ao aplicar `text-auto-resize` em lote, o filtro que importa é: **o próximo irmão ancora em
> `prev.right`?** Cuidado que o rótulo costuma ele mesmo ter `anchors.left: prev.right` (ele
> fica à direita de um checkbox) — isso não conta. Olhe o bloco seguinte, não o próprio. Errei
> nos dois sentidos antes de acertar: primeiro pulei 13 casos seguros, depois uma janela de
> busca larga demais pegou a âncora do rótulo seguinte.

### 2. Validar visualmente o que já foi corrigido por medição

Os 27 rótulos alargados (wheel, cyclopedia, announcement, gem menu, healthcircle, hotkey,
graphics, prey, offsets) passam na medição e o cliente sobe limpo, mas **ninguém abriu essas
janelas no cliente**. Navegar até elas dentro do jogo é o que falta.

### 3. Nomes de outfit quebrando com hífen

Na janela "Customise Character" os tiles do grid de outfits têm largura fixa e os nomes longos
agora quebram: "ENTREPREN-EUR", "ELEMENTALI-ST". Não é corte, é `text-wrap` fazendo o trabalho
dele num tile estreito demais para a fonte nova. A varredura não pega porque texto que quebra
é explicitamente ignorado. Ou alarga o tile, ou aceita a quebra.

### 4. `NewWindow` / `WindowCyclopedia` / `WindowPodium`

Em `10-windows.otui` ainda usam `image-border-top: 17` com a arte nova, que quer 30 — fatiam no
meio da faixa de título. 68 otui usam essa família, e o conserto mexe também no `padding-top`
delas, o que desloca o conteúdo. Precisa validar tela a tela.

## Armadilhas já pagas — não repita

- **`image-offset` ao estreitar um `UIButton`**: se a seta cair fora do widget, o cálculo do
  texto se desloca e o rótulo vai parar fora da janela. Aconteceu com `characterSort`. Reduza o
  `image-offset` junto com a largura (regra prática: `largura - 7 - 4`).
- **Aplicar largura em lote por número de linha**: numa passagem o sed pegou o `size:` do bloco
  seguinte e redimensionou o widget errado no `cyclopedia.otui`. Sempre confira que o valor
  encontrado bate com o que a varredura reportou antes de escrever.
- **`Set-Content -Encoding utf8` no PowerShell 5.1 grava BOM** e suja o diff inteiro. Use `sed`
  ou `[System.IO.File]::WriteAllLines`.
- **Automação de captura**: minimizar/restaurar a janela para forçar foco às vezes abre o menu
  Iniciar por cima e provoca `Render error: 1286` (GL_INVALID_FRAMEBUFFER_OPERATION) nessa GPU
  antiga. É artefato da automação, não do cliente.

## Como validar

Servidor: `docker start backlands-db backlands-srv` (config já aponta para `backlands-db:3306`).
O binário Windows `theforgottenserver-x64.exe` **não roda nesta máquina** — crasha com
`0xC000001D`, compilado para CPU com AVX2. Docker é o único caminho.

Conta de teste: usuário `1`, senha `1`. O servidor autentica por `accounts.name`, não por email,
apesar do label dizer "Email:". Personagem jogável: **Tester** (nível 20, Thais).
O "Account Manager" não carrega — tem caminho especial em `iologindata.cpp` que força Town ID 1,
que não existe no mapa.
