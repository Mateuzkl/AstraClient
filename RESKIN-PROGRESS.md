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

## Próximos passos

1. **Varredura estática**: script que cruza, em cada `.otui`, widgets com `size:`/`width:` fixo e
   `!text:` usando `$var-cip-font`, medindo o texto em silkscreen para listar os que estourarão.
   É muito mais rápido que abrir janela por janela no cliente.
2. Converter as janelas por ordem de tráfego: Options, VIP list, quest log, quickloot, report,
   wheel, bazaar.
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
