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

## Próximos passos

1. Ensinar a varredura a detectar **container de tamanho fixo cortando filho com
   `text-auto-resize`** — foi exatamente o caso dos checkboxes da lista de personagens, e ela
   ainda não pega.
2. Validar visualmente as janelas de `mods/` já corrigidas (wheel, cyclopedia, announcement,
   gem menu). As correções passam na medição, mas ninguém abriu essas telas no cliente ainda.
3. `NewWindow` / `WindowCyclopedia` / `WindowPodium` em `10-windows.otui` ainda usam
   `image-border-top: 17` com a arte nova (que quer 30). 68 otui usam essa família — precisa
   validar tela a tela antes de mexer no `padding-top` junto.

## Como validar

Servidor: `docker start backlands-db backlands-srv` (config já aponta para `backlands-db:3306`).
O binário Windows `theforgottenserver-x64.exe` **não roda nesta máquina** — crasha com
`0xC000001D`, compilado para CPU com AVX2. Docker é o único caminho.

Conta de teste: usuário `1`, senha `1`. O servidor autentica por `accounts.name`, não por email,
apesar do label dizer "Email:". Personagem jogável: **Tester** (nível 20, Thais).
O "Account Manager" não carrega — tem caminho especial em `iologindata.cpp` que força Town ID 1,
que não existe no mapa.
