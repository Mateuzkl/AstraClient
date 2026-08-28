---
name: backlands-verify-login-ui
description: Checklist de verificacao para o reskin pixel-art da tela de login (entergame) do AstraClient, feito em 6 commits no repo client/. Use quando o usuario pedir para verificar, testar, validar ou conferir a tela de login nova, os sprites reskinados (popupwindow, textedit, checkbox, buttons, scrollbar, combobox, item slots) ou os dois toggles de olho / auto login / os dois links de "esqueci". Precisa compilar e rodar o AstraClient (Windows) - nao roda numa VM Linux sem GUI. Ao final do checklist, APAGUE esta skill (instrucoes na ultima secao).
---

# Verificar o reskin da tela de login

Este checklist cobre o trabalho feito em `d:\backlands\client` a partir do pacote
`D:\Login Pixel Art Retro\ui-login` (o pacote com `AUDITORIA-CLIENTE.md` - **nao** o
`ui-login` antigo que ainda existe solto em `d:\backlands\ui-login`, esse ficou obsoleto).

Commits, do mais antigo pro mais novo (`git -C d:\backlands\client log --oneline -7`):

1. `Add pixel-art login UI assets` - fonte `silkscreen-16.otfont` + `.png` em
   `data/fonts/`, `Verdana-11px-italic.otfont` desativada (`.disabled`).
2. `Replace login screen...` (**revertido pelo commit 3** - ignore).
3. `Revert entergame OTUI/Lua swap` - desfaz o commit 2.
4. `Reskin shared UI chrome (Track A)` - 25 sprites genericos trocados em
   `data/images/ui/` e `data/images/game/entergame/` (nao so a tela de login - qualquer
   janela, campo de texto, checkbox, botao, scrollbar, combobox e slot de item do
   cliente inteiro usa esses arquivos). 4 ajustes de estilo em `data/styles/`
   (`10-buttons.otui`, `10-textedits.otui`, `40-entergame.otui`, `10-labels.otui`).
5. `Replace entergame.otui with lean tree` - arvore de
   `modules/client_entergame/entergame.otui` trocada: token 2FA e servidor ficam
   ocultos (nao apagados), Google/cam saem da tela, ganha segundo olho + auto login +
   dois links.
6. `Patch entergame.lua + util.lua` - 3 mexidas em
   `modules/client_entergame/entergame.lua` e `modules/corelib/util.lua` que fazem os
   callbacks da arvore nova funcionar.

Nada disso foi testado rodando o cliente de verdade - a sessao que fez esses commits
so tinha acesso de arquivo a esta pasta (VM Linux sem GUI, sem compilador). **Este
checklist e o que falta.**

## 0. Pre-requisitos

- `client/data/things/860.rar` precisa estar extraido em `client/data/things/860/`
  (sem isso o cliente nem abre - ver skill `backlands`, secao 2).
- Compilar: abrir `vc23/otclient.sln` no Visual Studio, projeto `AstraClient`,
  `Release`/`x64` (o `readme.md` do repo fala em `vc17`, esta desatualizado - use
  `vc23`).

## 1. A tela de login em si

Va ate a tela de login (primeira tela do cliente) e confira, contra
`d:\Login Pixel Art Retro\ui-login\reference\login-module.png` como referencia visual
(a paleta e o layout de bloco sao 2x maiores la - o cliente usa o dobro de densidade de
pixel - mas cores e proporcoes relativas tem que bater):

- [ ] Janela, campo de email, campo de senha, botao "Log in" todos com a arte nova
      (moldura dourada/marrom, nao mais o cinza generico do Tibia).
- [ ] Titulo da janela ("Journey Onwards") na cor `#ebbf90` (dourado claro), nao mais
      cinza `#909090`.
- [ ] Texto dos labels (Email, Password, Remember Email, etc.) na fonte pixelada
      `silkscreen-16`, nao mais Verdana antialiased.
- [ ] Texto do botao "Log in" legivel (cor `#201e1d`, escuro) sobre o fundo dourado do
      botao - **esse era o motivo do ajuste de estilo #1**, se aparecer claro-sobre-claro
      o ajuste nao pegou.
- [ ] Campo de texto com espaco visivel pra moldura/sombra (a borda ficou mais grossa
      de proposito - `image-border: 3`), sem faixa repetida/serrilhada dentro do campo.
- [ ] **Dois** icones de olho, um no campo de email (`hiddenEmail`) e outro no campo de
      senha (`hidden`) - clique em cada um, cada um mascara/revela **so o seu campo**,
      independente do outro. Se um afetar o campo errado, foi exatamente o bug que o
      patch do Lua deveria corrigir (`chooseTextMode` / `chooseTextModeEmail` trocados
      de campo) - reveja `modules/client_entergame/entergame.lua`.
- [ ] **Tres** checkboxes: Remember Email, Remember Password, **Auto login** (esse e
      novo). Marcar Auto login tambem marca os outros dois automaticamente.
- [ ] **Dois** links separados: "Forgot password" e "Forgot email" (antes era um so,
      "Forgot password and/or email"). Os dois abrem URL (mesmo que seja a mesma URL
      hoje - `Services.recoveryEmail` nao existe em `init.lua` ainda, o codigo cai pra
      `Services.recoveryPassword` de proposito, ver commit 6). O importante aqui e que
      **os dois sejam clicaveis e visualmente distintos**, nao que a URL final seja
      diferente.
- [ ] Feche e abra o cliente de novo com "Remember Password" + email/senha preenchidos:
      sem Auto login marcado, a tela normal aparece. Marque Auto login, fecha e abre de
      novo: login dispara sozinho **uma unica vez** (nao entra em loop).
- [ ] Nada no log (`otclientv8.log` ou console do cliente) sobre
      `accountTokenTextEdit`, `serverSelector`, `serverHostTextEdit` ou
      `clientVersionSelector` nulos - esses widgets ficaram ocultos (`visible: false` /
      `on: false`), nao removidos, e o Lua ainda tenta ler eles.
- [ ] Nada no log tipo `font 'silkscreen-16' not found` - se aparecer, a fonte nao
      registrou (confira `data/fonts/silkscreen-16.otfont` e `.png` existem e o atlas de
      texto 2048x2048 nao estourou).

## 2. Fora da tela de login (o commit 4 mexeu em sprites COMPARTILHADOS)

O commit 4 trocou `popupwindow.png`, `textedit.png`, `checkbox.png`, `buttons.png`,
`buttons-blue.png`, `button.png`, `panel_flat.png`, `scrollbar.png`,
`combobox_square.png`, `combobox_rounded.png`, `item.png`, `item66.png`,
`miniborder.png`, `separator_horizontal/vertical(66).png` e `pin-button.png` - todos
usados em telas fora do login. Abra pelo menos:

- [ ] Uma janela qualquer do jogo (inventario, skills, o que estiver mais a mao) -
      confere que a moldura/titulo nao ficou cortada ou repetida (o `popupwindow.png`
      novo tem `image-border: 6` + `image-border-top: 27`, se a proporcao estourar a
      barra de titulo aparece quebrada).
- [ ] Um combobox e uma scrollbar (ex: menu de opcoes) - abrem, arrastam, sem esticar
      a arte.
- [ ] Um slot de item (inventario) - a moldura nova nao pode cobrir o sprite do item.
- [ ] **Barras de vida e mana continuam do jeito antigo** (nao foram mexidas de
      proposito - `progressbar.png`, `progressbar_thick.png` e `progressbarhpmana.png`
      ficaram de fora do commit 4, ver a mensagem do commit pra entender por que). Se
      elas mudaram ou quebraram, algo NAO relacionado a este trabalho mexeu nelas.
- [ ] Texto em qualquer outra tela (nao so login) - o commit 4 mudou `Label.font` pra
      `silkscreen-16` **globalmente** (em `10-labels.otui`), entao qualquer `Label`
      (nao `FlatLabel`, nao `GameLabel`) do cliente inteiro trocou de fonte. Confira que
      nao ha texto cortado/sobrepondo por causa da largura de caractere diferente da
      fonte nova.

## 3. Se algo estiver errado

Corrija o **sprite**, nao o OTUI, a menos que o problema seja claramente de layout
(margem, ancora, ordem). Regra de `d:\Login Pixel Art Retro\ui-login\IMPLEMENTACAO.md`:
"o mock vence a skill; o cliente rodando vence o mock". Compare pixel a pixel com
`ui-login/reference/login-module.png` antes de mudar qualquer `.otui`.

As ferramentas citadas nas skills deste pacote (`tools/otui-lint.js`,
`tools/lua-syntax.lua`, `tools/ui-shot.ps1`, `tools/pixelui/probe.js`) **nao existem
ainda** neste checkout - a verificacao acima e manual, olhando a tela. Se quiser
automatizar, essas ferramentas precisam ser escritas primeiro (fora do escopo deste
checklist).

## 4. Ao terminar - remova esta skill

Este arquivo e um checklist de uma tarefa especifica (o reskin da tela de login), nao
uma skill de uso continuo. Depois que todos os itens acima passarem (ou depois de
corrigir o que estava quebrado e re-testar), apague a pasta inteira:

```powershell
Remove-Item -Recurse -Force "d:\backlands\client\.claude\skills\backlands-verify-login-ui"
```

E se o resultado for commitado, faca isso como o commit final desse trabalho (mensagem
sugerida: "Remove backlands-verify-login-ui skill - verificacao concluida"). Nao apague
antes de rodar o checklist - so depois.
