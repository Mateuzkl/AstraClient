# AstraClient Web — Arquitetura Dual-Profile (Web Desktop Full + Web Mobile Lite)

Este documento descreve a arquitetura, as decisões técnicas, a auditoria de proveniência e os benchmarks reais medidos para o suporte simultâneo a **Web Desktop Full** e **Web Mobile Lite** a partir de uma única engine C++, um único repositório e uma única URL de entrada (`astraclient.html`).

---

## 1. Auditoria de Proveniência e Decisão Clean-Room

Antes da implementação, a pasta de referência local (`Tibia 2 - OTC completo 2026-11-23\mobile`) foi auditada integralmente:

- O arquivo `AVISO-LEGAL.txt` no diretório pai identifica o pacote como software proprietário da **HG GAMES LTDA** (*Pangeia / Tibia 2*) obtido por decriptação e proíbe expressamente reutilização, cópia, adaptação ou redistribuição de código ou assets.
- **Decisão:** **zero** código, OTUI, Lua, imagens, fontes ou binários da pasta de referência foram copiados ou adaptados para este repositório.
- Toda a experiência Mobile Lite (`modules/client_mobile/`, `layouts/mobile/styles/50-mobile-controls.otui`, `layouts/mobile/images/title.png`, `browser/platform.js`, `browser/spr-pager.js` e otimizações da engine C++) foi construída de forma **100% clean-room** sobre a arquitetura moderna do AstraClient.

---

## 2. Visão Geral da Arquitetura Dual-Profile

O mesmo endereço web (`astraclient.html`) serve um launcher leve que detecta o perfil **antes** de baixar qualquer `.data`, `.wasm` ou `.js` da engine:

```text
astraclient.html + launcher.js + platform.js + profiles.json
    |
    +--> Desktop (Windows / Linux / macOS / híbridos com mouse/hover)
    |      |-- desktop/astraclient.wasm   (5,66 MiB; 768 MiB init / 2048 MiB max; 4 pthreads)
    |      |-- desktop/astraclient.js     (720 KiB)
    |      |-- desktop/astraclient.data   (601,70 MiB; 5.040 arquivos; 10 chunks IDB)
    |      |-- desktop/asset-manifest.json
    |      +-- Comportamento 100% preservado (Atlas 4096x4096, todos os 110 módulos)
    |
    +--> Mobile Lite (Android / iPhone / iPad / iPadOS / tablets touch)
           |-- mobile/astraclient.wasm    (5,66 MiB; 256 MiB init / 768 MiB max; 2 pthreads)
           |-- mobile/astraclient.js      (420 KiB)
           |-- mobile/astraclient.data    (22,94 MiB; 2.295 arquivos; 1 chunk IDB; Tibia.spr.idx)
           |-- mobile/asset-manifest.json
           |-- mobile/spr-manifest.json   (122 KiB; hashes SHA-256 de 1.728 páginas de 256 KiB)
           |-- mobile/Tibia.spr           (431,78 MiB servidos sob demanda via HTTP Range 206)
           +-- Flag -mobile-lite (48 módulos essenciais sem chrome Desktop, gameinterface_mobile.otui 100% mapa tela cheia, Atlas 2048x2048, DPR<=1.75x, multitouch + Gboard/iOS IME síncrono)
```

### Compatibilidade retroativa (modo flat)

O modo padrão de CI (`./browser/build-wasm.sh Release`) continua gerando o layout flat compatível com os workflows e testes existentes (`nginx.test.cjs`, `launcher.test.cjs`), enquanto `--profile all` gera a distribuição unificada com `profiles.json`, `desktop/` e `mobile/`.

---

## 3. Detecção de Plataforma, Override Manual e Orientação Horizontal

### 3.1 Detecção Multi-Sinal (`browser/platform.js`)

A detecção combina múltiplos sinais em vez de depender apenas de `User-Agent` ou largura da janela:

- `navigator.userAgentData.mobile` e `platform` (User-Agent Client Hints, quando disponíveis).
- Heurística explícita para **iPadOS Safari** (`MacIntel` + `maxTouchPoints > 1` + ausência de ponteiro fino/hover).
- Media queries de capacidade real de entrada: `(pointer: coarse)`, `(any-pointer: fine)`, `(hover: hover)` e `navigator.maxTouchPoints`.
- Classificação correta de **dispositivos híbridos** (notebooks Windows/Linux com tela sensível ao toque + mouse/trackpad permanecem em **Desktop**).
- Redimensionar uma janela desktop estreita **nunca** ativa Mobile Lite sem sinais touch/mobile.
- **Imutabilidade na sessão ativa:** o perfil escolhido antes do boot nunca muda durante uma sessão em execução apenas por rotação ou redimensionamento de janela.
- **Override manual:** seletor `Auto / Desktop Full / Mobile Lite` disponível no card do launcher, no painel *Web Options* (Desktop) e no drawer *Settings -> Web* (Mobile Lite — o botão flutuante `Web options` fica completamente oculto no Mobile para não obstruir a interface), persistido por `location.pathname` em `localStorage` com fallback seguro caso o bundle alvo não esteja publicado.

### 3.2 Fullscreen, Landscape e Teclado Virtual Nativo (Android & iOS)

No perfil Mobile Lite (`createMobileViewportController` em `browser/platform.js`, `installTextBridge` em `browser/runtime.js`, `BrowserWindow` + `UITextEdit` e `browser/launcher.css`):

- Ao clicar em **Play** (gesto explícito do usuário), tenta `requestFullscreen()` e `screen.orientation.lock('landscape')`.
- Suporta `landscape-primary` (`landscape-left`) e `landscape-secondary` (`landscape-right`), recalculando viewport e enviando `_astra_browser_viewport_changed()` para o WASM.
- Quando o navegador bloqueia `screen.orientation.lock()` (caso comum no Safari iOS/iPadOS) e o aparelho está em **portrait**, exibe o overlay `#astra-rotate-overlay` orientando o usuário a girar o aparelho, com botão de tentativa de tela cheia + opção *Continue anyway* (e oculta automaticamente o overlay enquanto o teclado virtual está aberto).
- Respeita `env(safe-area-inset-*)` (via variáveis CSS `--astra-safe-top/right/bottom/left` em `:root`) para notch/ilha dinâmica/barras gestuais (`viewport-fit=cover` em `browser/shell.html`).
- Bloqueia scroll/pinch-zoom acidental sobre o canvas (`touch-action: none`, `overscroll-behavior: none`, `user-select: none`).
- **Teclado virtual síncrono global para todos os `UITextEdit`:**
  - Sob `-sPROXY_TO_PTHREAD=1`, chamadas assíncronas do pthread C++ chegam à main thread depois que o evento `touchend` expira, fazendo Android Chrome e iOS Safari rejeitarem `.focus()` silenciosamente. Além disso, `UITextEdit::getTextPos()` retornava `-1` em campos vazios e impedia a abertura do editor.
  - Solução implementada globalmente: `BrowserWindow::syncTextInputRects()` sincroniza periodicamente (e a cada mudança de foco) os retângulos CSS e metadados (`id`, `text`, `email`, `password`, `numeric`, `multiline`, `maxLen`, cursor/seleção) de **todos** os `UITextEdit` visíveis e editáveis para a main thread.
  - Um listener em fase de captura (`touchend`) no `#canvas` faz hit-test síncrono (+12px de tolerância tátil), chama `event.preventDefault()` para impedir que o `<canvas tabindex="0">` roube o foco via `mousedown` sintético e foca imediatamente `<input id="astra-mobile-input">` (campos simples/senha) ou `<textarea id="astra-mobile-textarea">` (campos multilinha como livros e listas de casa, preservando `\n`) em `font-size: 16px`, exibindo a barra `#astra-mobile-keyboard-bar` (com **Next** / `Tab` protegido por `expectedWidgetId` e **OK**) ancorada sobre `window.visualViewport`.
  - A sincronização bidirecional usa `astra_browser_set_text(expectedId, text, selStart, selEnd)`, `astra_browser_focus_text_edit(widgetId)` e `astra_browser_next_text_edit(fromId)` com conversão exata **UTF-16 <-> UTF-8** nos dois sentidos, truncamento seguro sem cortar caracteres multi-byte, remapeamento de seleção após `validChars` (com eco `normalized: true`), sincronização contínua durante composição IME do Android Gboard (`input` sempre sincroniza para o C++ mesmo com `composing === true`, evitando perda do texto de conta ao tocar em `Next`), conclusão determinística de foco em `Next` (`onVirtualTabProcessed` + timeout de segurança, sem travar em campos multilinha) e tolerância tátil de `24px` no mobile.
- Pausa a renderização quando a aba entra em segundo plano (`visibilitychange` -> `_astra_browser_set_visibility`) e trata perda/restauração de contexto WebGL2 (`webglcontextlost` / `webglcontextrestored` -> `_astra_browser_context_lost` + reconstrução completa de Painter, FBOs, Atlas, Texturas, TextRender, Shaders, Minimap, Fontes e ThingTypes com guarda de geração atômica).

---

## 4. Separação de Módulos e Preservação de Protocolo

- O perfil **Desktop Full** continua carregando todos os **110 módulos** existentes sem alterações.
- O perfil **Mobile Lite** inicia com `-mobile-lite` (`g_app.isMobileLite()`), ativando:
  - Whitelist de assets dedicada (`browser/mobile-assets.json`) e diretiva `mobile-excluded-load-later` (`modules/game_interface/interface.otmod`, `src/framework/core/module.cpp`) carregando apenas os **48 módulos essenciais de jogabilidade** e excluindo, exclusivamente sob `g_app.isMobileLite()`, todo o chrome Desktop (`game_buttons`, `game_sidebars`, `game_topbar`, `game_stats`, `game_sidebuttons`) e os **57 módulos pesados de protocolo 15.x** (Cyclopedia, Bestiary, Bosstiary, Battlepass, Forge, Imbuing, Destiny Wheel, Prey, Compendium, Wiki, Task Hunt, Daily Reward, Store, Market, Analyzers, Stash, Reward Wall, Bot, Dev tools, etc.).
  - **Preservação total do Desktop Full, Android Nativo e protocolo C++:** todas as adaptações da interface Web Mobile são isoladas atrás de `g_app.isMobileLite()`; `gameinterface.otui`, `entergame.otui` e `characterlist.otui` originais do Desktop permanecem 100% inalterados e nenhum opcode ou `GameFeature` da engine C++ foi removido.
  - **Correção de camadas de estilo (`modules/client_styles/styles.lua`) e atualização de `layouts/mobile/styles/{30-miniwindow,40-console}.otui`:** o carregador agora importa `/data/<dir>` primeiro e aplica os overrides de `/layouts/<layout>/<dir>` por cima, garantindo que estilos adicionados em versões recentes do AstraClient (como `MapMiniWindow` e os widgets de `game_console`) nunca desapareçam no layout mobile.

---

## 5. Otimização de Assets e Paginação Sob Demanda de `Tibia.spr`

### 5.1 Eliminação da Duplicação de 601 MiB na Memória JS

No perfil Desktop Full, `astraclient.data` (601,70 MiB, incluindo `Tibia.spr` de 431,78 MiB) precisa ser remontado em memória JS (`Module.getPreloadedPackage`) para alimentar o MEMFS do Emscripten, elevando o heap JS para **~610 MiB** no cold boot (e pico de ~1,2 GiB antes do GC no warm boot).

No perfil **Mobile Lite**:

1. **`tools/browser_bundle.cjs` (`sprMode: "paged"`):** extrai exclusivamente o cabeçalho e a tabela de offsets de `Tibia.spr` em **`Tibia.spr.idx`** (**1,85 MiB**, 485.548 sprites) para dentro do `astraclient.data`, deixando o corpo completo de `Tibia.spr` (431,78 MiB) fora do pacote inicial e gerando `mobile/spr-manifest.json` com hash SHA-256 de cada página de **256 KiB** (1.728 páginas).
2. **`browser/launcher.css`:** o wallpaper desktop `launcher-background.png` (3,28 MiB) foi escopado exclusivamente para `#astra-launcher[data-profile="desktop"]::before`, eliminando seu download no mobile.
3. **Cache e Paginação Sob Demanda (`browser/spr-pager.js` + `src/client/spritemanager.cpp`):**
   - `SpriteManager::loadSpr` carrega apenas `Tibia.spr.idx` em **~6–13 ms**.
   - Quando um sprite ainda não está na cache LRU C++ (limite fixo de **64 páginas = 16 MiB**), `SpriteManager` dispara `Module.astraRequestSprPage(pageIndex)` de forma assíncrona com cooldown de 3s para retries, e `ThingType::getTexture()` evita cachear texturas incompletas até a página chegar.
   - `browser/spr-pager.js` verifica primeiro o IndexedDB (`astra-spr-pages:<path>:mobile`); em cache miss, faz `fetch` com header `Range: bytes=start-end` exigindo estritamente **HTTP `206 Partial Content`**, valida o **SHA-256** da página contra `spr-manifest.json`, grava no IndexedDB e entrega os bytes ao heap WASM via `_astra_spr_page_loaded(...)` seguido de `g_app.repaint()`.

---

## 6. Otimização de Memória WASM e Análise Single-Thread

### 6.1 Medições Reais: Desktop 768 MiB vs Mobile 256 MiB vs Mobile 128 MiB

Avaliamos empiricamente no Chrome headless (WASM Release) três configurações reais de memória:

| Configuração | `INITIAL_MEMORY` | `MAXIMUM_MEMORY` | `PTHREAD_POOL_SIZE` | `wasmHeapCapacityMiB` (pós-boot) | `wasmMallocAllocatedMiB` (pós-boot) | Folga livre no boot |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| **Desktop Full** | 768 MiB | 2048 MiB | 4 | **768 MiB** | **172,49 MiB** | 595,5 MiB |
| **Mobile Lite (Padrão)** | **256 MiB** | **768 MiB** | **2** | **256 MiB** | **93,99 MiB** | **162,0 MiB** |
| **Mobile Lite (128 MiB Exp.)** | 128 MiB | 512 MiB | 2 | **128 MiB** | **93,98 MiB** | **34,0 MiB** |

**Conclusão empírica para o valor padrão (`256 MiB / 768 MiB / 2 pthreads`):**

- No Mobile Lite, a alocação viva C++/Lua após o boot completo (`Tibia.dat` + `Tibia.spr.idx` + 53 módulos Lua + UI + fontes + Atlas 2048×2048) caiu de **172,49 MiB** para **93,99 MiB** (**-45,5%**).
- O experimento de **128 MiB** funcionou com **zero `memory.grow()`** e zero erros na tela de login (`wasmHeapCapacityMiB = 128 MiB`, `wasmReadyMs = 126 ms`), provando viabilidade para dispositivos extremamente restritos (2–3 GB RAM).
- Contudo, **34 MiB** de folga inicial serão excedidos assim que o jogador entrar no mapa e preencher o cache LRU de 16 MiB de páginas SPR + tiles + criaturas + tabelas Lua de combate, forçando `WebAssembly.Memory.grow` durante a partida (o que sob `-pthread` sincroniza views do `SharedArrayBuffer`).
- Por isso, **`256 MiB` inicial / `768 MiB` máximo / `2` pthreads** foi escolhido como padrão de produção do perfil Mobile Lite (reduzindo a reserva inicial em **66,7%** frente ao Desktop com **162 MiB** de margem para jogo fluido), mantendo overrides configuráveis via CMake (`-DASTRA_WASM_INITIAL_MEMORY=134217728 -DASTRA_WASM_MAXIMUM_MEMORY=536870912`) para builds ultraleves.

### 6.2 Viabilidade de Build Single-Thread (Sem `SharedArrayBuffer`)

Analisamos a viabilidade arquitetural de um build single-thread para navegadores sem isolamento cross-origin (`COOP/COEP` / `SharedArrayBuffer`):

- Atualmente a engine Web usa **`-pthread` + `-sPROXY_TO_PTHREAD=1` + `-sOFFSCREENCANVAS_SUPPORT=1`** para executar `main()`, `initLua` (~1,9–4,9s), parsing de `Tibia.dat`, WebGL2 via `OffscreenCanvas` e `AsyncDispatcher` fora da main thread do navegador.
- Um build single-thread sem `SharedArrayBuffer` **não é apenas remover `-pthread`**: exigiria remover `PROXY_TO_PTHREAD` e `OFFSCREENCANVAS_SUPPORT`, converter o loop principal C++ (`GraphicalApplication::run`) para `emscripten_set_main_loop` cooperativo, serializar o `AsyncDispatcher` no loop principal e lidar com bloqueios síncronos de 2+ segundos na UI thread durante `initLua` / `Tibia.dat` (causando congelamento da aba e avisos *"Page Unresponsive"* no mobile).
- **Decisão:** manter a arquitetura multi-thread enxuta (**2 pthreads** no Mobile Lite) servida sob HTTPS + COOP/COEP/CORP, que já é suportada por Chrome/Edge/Firefox modernos, Android WebView/Chrome e iOS Safari 15.2+. Não introduzir um modo single-thread parcial que degradaria a responsividade e estabilidade.

---

## 7. Controles Touch, Interface Mobile e Otimizações Gráficas

- **Multitouch real (`src/framework/platform/browserwindow.cpp`, `src/framework/ui/uimanager.cpp`):** suporte simultâneo a até 3 toques independentes (`MouseTouch`, `MouseTouch2`, `MouseTouch3`) com roteamento de movimento por dedo (`g_ui.onTouchMove`) permitindo controlar o joystick com um segundo dedo enquanto outro segura ações, tolerância de `16px` lógicos, consumo de gesto (`g_window.consumeTouchGesture()`) suprimindo clique e drag sintéticos, hit-test direto no mapa antes de disparar *Use/Look*, cancelamento seguro de drag em `touchcancel` e conversão exata CSS -> backing buffer (`cssToWindowPos`).
- **Interface Mobile Dedicada e Independente (Tema Clássico Dark-Charcoal / Slate Translúcido — exclusiva de `g_app.isMobileLite()`, Desktop Full e Android Nativo 100% preservados):**
  - **Interface In-Game Independente (`modules/game_interface/gameinterface_mobile.otui` + `updateMobileLiteMapGeometry()`):** substitui o `gameinterface.otui` Desktop no Mobile Lite por um layout 100% focado no jogo com `gameMapPanel` preenchendo **100% da tela (`anchors.fill: parent`)**, sem margens cinzas, sem `topmenu`, sem sidebars Desktop, sem action bars Desktop (`game_actionbar` desativado no Mobile Lite) e sem espaço preto reservado para chat quando fechado. A dimensão visível é calculada estritamente dentro do `awareRange` do servidor (`18×14` -> tiles quadrados nítidos sem esticar sprites via `MapView::calcFramebufferSource`).
  - **Kit visual e fontes próprias (`layouts/mobile/images/mobile_ui/`, `layouts/mobile/fonts/`, `layouts/mobile/styles/25-mobile-theme.otui`):** 32 sprites clean-room em grafite/dark-charcoal translúcido (incluindo joystick circular metálico com setas cardinais e thumbstick esférico), fundo dark-slate leve (`layouts/mobile/images/title.png`, 16 KB) e 4 fontes bitmap CP1252 antialiased (`mobile-title-18`, `mobile-btn-15`, `mobile-input-14`, `mobile-hud-12`).
  - **Login e Seleção de Personagens dedicados (`modules/client_entergame/{entergame_mobile,characterlist_mobile}.otui`):** card limpo dark-charcoal com campos táteis, alternância de visibilidade de email/senha, preview animado de outfit + status VIP compacto e botões táteis `LOG IN` / `ENTER GAME`.
  - **HUD In-Game e Controles Touch (`modules/client_mobile/{mobile.otui,mobile.lua}`, `modules/game_minimap/minimap.lua`, `modules/game_inventory/inventory.lua`, `modules/game_console/console.lua`):**
    - **Topo Esquerdo:** Minimap compacto translúcido (`114×114`) com botões `+`/`-` de zoom, sem controles Desktop residuais.
    - **Topo Centro-Esquerdo:** HUD transparente único de **HP / MP / XP / Lv / Ping / FPS** (coração + barra vermelha + número, gota azul + barra azul + número, barra fina de XP) — **zero barras duplicadas** (`game_topbar` excluído e `HealthOverlay`/`healthInfoWindow` ocultos no Mobile Lite). Target Bar dinâmico exibido apenas durante combate.
    - **Topo Direito:** Containers/Backpacks translúcidos flutuando diretamente sobre o mapa + barra de 4 ícones (`[≡ Menu]` `[🔒 Safe]` `[⚙ Settings]` `[🛡 Equipment]`) e painel **Equipment** translúcido (`126×186`, slots + Soul + Cap) deslocando-se dinamicamente para a esquerda dos containers abertos.
    - **Inferior Esquerdo:** Joystick analógico circular clássico (aro metálico grafite + 4 setas cardinais + thumbstick esférico) + grade 2×2 de utilidades (`OFF/BAL/DEF`, `Equipment`, `Backpack`, `Chat` flutuante centralizado sob demanda com teclado nativo).
    - **Inferior Direito:** Grade de **Hotkeys Reais** (4 páginas `1/4..4/4`, 28 slots) exibindo **sprites reais de itens (`UIItem`) com contadores vivos** (priorizando poções/runas da backpack ou bindings do jogador em `game_hotkeys`) e **ícones reais de magias (`Spells.getSpellIcon`)**, acima da fileira de combate (`[? Look]` `[↻ Turn]` `[🏃 Follow]` `[🪜 Use]` `[⚔ Attack]`).
    - **Drawer de Configurações rolável (`ScrollablePanel`):** escala de controles, lado do joystick, zoom do mapa (`Closer / Auto / Wider`), limite de FPS, qualidade DPR (`1.0x..2.0x`), luzes, floor-fade e ações Web integradas (`Fullscr / Diag / Desktop` — sem botão flutuante `Web options` no Mobile).
- **Otimizações de GPU e Memória Gráfica:**
  - **Atlas de Sprites:** `2048×2048` (**16 MiB VRAM**) no Mobile Lite vs `4096×4096` (**64 MiB VRAM**) no Desktop (**-75% VRAM**).
  - **DPR Cap (Nitidez vs Performance):** teto padrão ajustado para **`1.75×`** no mobile (`g_window.setMaxPixelRatio(1.75)`), renderizando um celular DPR 3 (`844×390` CSS) em `1477×683` em vez de `2532×1170` (**~2,9× menos pixels** que DPR nativo, com fontes bitmap significativamente mais nítidas que `1.5×`, ainda configurável entre `1.0×` e `2.0×`).
  - **FPS Cap & Idle:** teto padrão de 45 FPS configurável no mobile; pausa automática em aba oculta; skip do `cycleEvent` de hover do mouse no `uigamemap.lua`; skip de shaders pesados de arena em `game_shaders/shaders.lua`.
  - **Cache LRU e Eviction:** `ImageCache` limitado a `512` itens / `8 MiB` no mobile (vs `2000` / `32 MiB`); eviction de `ThingType` acelerada para `25s` @ `200/s` (vs `60s` @ `100/s`) + `TextureManager::trimCache(30)` seguro a cada 15s (verificando `tex.use_count() <= mapRefs`).

---

## 8. Benchmarks Reais — Antes vs Depois

Medições reais coletadas em builds **Release** (Emscripten 6.0.8, C++23, `wasm-opt`), executadas ao vivo no **Chrome headless com CDP e WebGL2 (SwiftShader)** contra `browser/serve.py` em loopback (`crossOriginIsolated: true`).

### 8.1 Tamanho dos Artefatos e Pacotes

| Métrica | Baseline (`origin/main`) | Desktop Full (Novo) | Mobile Lite (256 MiB) | Mobile Lite (128 MiB Exp.) | Redução (Mobile vs Desktop) |
| --- | ---: | ---: | ---: | ---: | ---: |
| `astraclient.data` (boot) | 601,65 MiB | 601,70 MiB | **22,65 MiB** | **22,64 MiB** | **-96,24% (26,6× menor)** |
| Arquivos no `.data` | 5.038 | 5.040 | **2.248** | **2.235** | **-55,4%** |
| Chunks no IndexedDB | 10 | 10 | **1** | **1** | **-90,0%** |
| `astraclient.js` | 718,6 KiB | 720,0 KiB | **419,8 KiB** | **419,8 KiB** | **-41,7%** |
| `astraclient.wasm` | 5,63 MiB | 5,66 MiB | **5,66 MiB** | **5,66 MiB** | 0% (mesma engine C++) |
| `launcher-background.png` baixado | Sim (3,28 MiB) | Sim (3,28 MiB) | **Não (0 B)** | **Não (0 B)** | **-100%** |
| `Tibia.spr` no boot | 431,78 MiB (embutido) | 431,78 MiB (embutido) | **0 B no boot** (paginado 256 KiB) | **0 B no boot** (paginado 256 KiB) | **Sob demanda (`HTTP 206`)** |
| Módulos Lua carregados | 110 | 110 | **53** | **53** | **-51,8%** |

### 8.2 Execução Ao Vivo no Chrome Headless (Cold & Warm)

| Métrica (Chrome Headless WebGL2 SwiftShader) | Desktop Full (Cold) | Desktop Full (Warm) | Mobile Lite 256M (Cold) | Mobile Lite 256M (Warm) | Mobile Lite 128M (Cold) | Mobile Lite 128M (Warm) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Detecção automática correta | Sim (`desktop`) | Sim (`desktop`) | **Sim (`mobile`)** | **Sim (`mobile`)** | **Sim (`mobile`)** | **Sim (`mobile`)** |
| Requisições do perfil errado | 0 | 0 | **0** | **0** | **0** | **0** |
| Download `.data` (bytes) | 601,70 MiB | 0 B (IDB) | **22,65 MiB** | **0 B (IDB)** | **22,64 MiB** | **0 B (IDB)** |
| Leitura do cache IDB (`cacheReadMs`) | 11 ms | 1.013 ms | **6 ms** | **33 ms** | **1 ms** | **31 ms** |
| Instanciação WASM (`wasmReadyMs`) | 195 ms | 185 ms | **119 ms** | **106 ms** | **126 ms** | **93 ms** |
| `initLua` | 4.987 ms | 4.142 ms | **1.919 ms** | **2.240 ms** | **1.938 ms** | **1.768 ms** |
| `datLoad` | 201 ms | 189 ms | **262 ms** | **110 ms** | **194 ms** | **108 ms** |
| `sprLoad` (índice) | 5,1 ms | 5,4 ms | **13,0 ms** | **6,1 ms** | **10,9 ms** | **5,9 ms** |
| **Play -> 1º Frame (`playToFirstFrameMs`)** | **11.282 ms** | **6.031 ms** | **3.072 ms** | **2.866 ms** | **3.021 ms** | **2.316 ms** |
| Heap JS usado (`usedJSHeapMiB`) | 609,54 MiB | 1.215,70 MiB | **28,14 MiB** | **76,96 MiB** | **28,38 MiB** | **76,98 MiB** |
| Capacidade Heap WASM (`wasmHeapCapacityMiB`) | 768 MiB | 768 MiB | **256 MiB** | **256 MiB** | **128 MiB** | **128 MiB** |
| Alocação C++/Lua viva (`wasmMallocAllocatedMiB`) | 172,49 MiB | 172,46 MiB | **93,99 MiB** | **93,98 MiB** | **93,98 MiB** | **93,97 MiB** |
| Atlas WebGL2 (VRAM estimada) | 4096×4096 (64 MiB) | 4096×4096 (64 MiB) | **2048×2048 (16 MiB)** | **2048×2048 (16 MiB)** | **2048×2048 (16 MiB)** | **2048×2048 (16 MiB)** |
| Backing canvas (CSS -> px) | 1280×720 -> 1280×720 | 1280×720 -> 1280×720 | **844×390 -> 1266×585** | **844×390 -> 1266×585** | **844×390 -> 1266×585** | **844×390 -> 1266×585** |
| FPS (SwiftShader software GL) | 39,9 FPS | 42,6 FPS | **48,3 FPS** | **40,3 FPS** | **57,9 FPS** | **46,4 FPS** |
| Erros de runtime JS / Lua (`runtimeErrors` / `errorLogs`) | **0 / 0** | **0 / 0** | **0 / 0** | **0 / 0** | 0 / 14* | 0 / 14* |
| SPR sob demanda (`HTTP 206` -> IDB hit) | N/A | N/A | **`206` (256 KiB, 0 erros)** | **`idbHits: 1`, 0 B rede** | N/A | N/A |
| Overlay portrait + imutabilidade de perfil | N/A | N/A | **OK (mostra/dispensa)** | **OK (mostra/dispensa)** | **OK** | **OK** |

*\*Os 14 avisos no experimento anterior de 128 MiB correspondiam aos 13 ícones `element_0..12.png` (~4 KiB) adicionados em seguida ao `mobile-assets.json`, resultando em **0 / 0 erros** no build final unificado.*

---

## 9. Matriz de Validação (Emulado vs Hardware Físico)

| Cenário / Plataforma | Status | Ambiente / Observação |
| --- | --- | --- |
| Testes unitários JS/Node (`browser/tests/*.test.cjs`) | **Validado (87/87 PASS)** | Node 24 (inclui `platform`, `spr-pager` idle-timeout + dispose, `serve-range`, `dual-profile`, `runtime` touch/keyboard/multiline/IME/caret sync, `security`, `asset-cache`, `launcher`) |
| Testes Python & integridade de assets | **Validado (6/6 + 948 text assets PASS)** | `check_browser_assets.py`, `text_assets.py`, `manifest.py`, `style_font_routing.lua`, `browser_bundle.cjs scan` (0 findings) |
| Testes C++ nativos + ASan/UBSan | **Validado (100% PASS)** | Suites C++23, UTF-8, WebSocket, RSA, UUID, Fetch, Keyboard, Cursor, ASan+UBSan Queue & Lua |
| Nginx TLS + COOP/COEP/CORP + WSS binário | **Validado (1/1 PASS)** | `nginx.test.cjs` com Nginx real em Ubuntu 24.04 (WSL2) |
| Web Desktop Full (Cold & Warm, WebGL2) | **Validado ao vivo (0 erros)** | Chrome Headless CDP (Windows, 1280×720, SwiftShader WebGL2, `Web options` visível) |
| Web Mobile Lite **Online In-Game** (Emulado CDP: `640×360`, `800×360`, `844×390`, `1024×768`) | **Validado ao vivo online (0 erros JS / 0 erros Lua)** | Chrome Headless CDP conectado a servidor TFS 1.8 (8.60) real: login com composição Android Gboard + `Next` preservando conta, seleção tátil de personagem, mapa 100% tela cheia nos 4 viewports (`1477×683` @ `1.75x` em `844×390`), `60,9 FPS`, `37,5 MiB` heap JS in-game, `45` páginas SPR HTTP `206` (`11,25 MiB` sob demanda vs `432 MiB`), mochila aberta + `Equipment` deslocado + hotkeys com sprites/contadores (`50`) + magias reais, chat centralizado, configurações, joystick + multitouch, rotação portrait->landscape e logout limpo |
| **Checklist físico Android (Chrome / Samsung Internet)** | **Requer validação em aparelho real** | 1) Tocar em Email/Senha/Token abre Gboard imediatamente; 2) Digitação, autocorreção, Backspace, copiar/colar e botão `Next` funcionam sem fechar o teclado; 3) Barra acessória acompanha `visualViewport` acima do teclado em landscape; 4) Fullscreen + `orientation.lock('landscape')` e safe-area; 5) Botão `Settings` no login abre drawer com `Fullscr/Diag/Desktop` e sem `Web options` flutuante; 6) Multitouch joystick + ações em jogo |
| **Checklist físico iOS / iPadOS (Safari 16+/17+/18+)** | **Requer validação em aparelho real** | 1) Toque síncrono em `touchend` abre teclado iOS sem auto-zoom (`font-size: 16px`); 2) Botão `Next` navega entre campos sem perder foco; 3) Overlay portrait + safe-area de notch/ilha dinâmica; 4) Estabilidade de `WebAssembly.Memory` (256 MiB) sob WebKit jetsam |

---

## 10. Como Compilar e Publicar

### Build Linux / WSL2 (`browser/build-wasm.sh`)

```bash
# Build unificado com Desktop Full + Mobile Lite e profiles.json:
./browser/build-wasm.sh Release --profile all --jobs 4

# Apenas Mobile Lite (com override opcional de memória 128 MiB):
./browser/build-wasm.sh Release --profile mobile --jobs 4 -- \
  -DASTRA_WASM_INITIAL_MEMORY=134217728 -DASTRA_WASM_MAXIMUM_MEMORY=536870912

# Modo flat legado (CI padrão):
./browser/build-wasm.sh Release
```

### Build Windows (`browser/build-wasm.ps1`)

```powershell
.\browser\build-wasm.ps1 -BuildType Release -Profile all -Jobs 4
```

### Servidor Local de Desenvolvimento (com suporte a HTTP `Range 206`)

```bash
python3 browser/serve.py --bind 127.0.0.1 --port 8088 build-wasm-all-release/dist
```

### Requisitos de Produção (Nginx)

Ver [`browser/nginx.conf.example`](../browser/nginx.conf.example):
- **HTTPS obrigatório** (exigido por `SharedArrayBuffer` / `crossOriginIsolated` e `browser/runtime.js`).
- Headers `Cross-Origin-Opener-Policy: same-origin`, `Cross-Origin-Embedder-Policy: require-corp` e `Cross-Origin-Resource-Policy: same-origin`.
- Suporte nativo a **HTTP `Range` (`206 Partial Content`)** para `mobile/Tibia.spr` (habilitado por padrão em arquivos estáticos no Nginx; **não** aplicar gzip/brotli sobre `Tibia.spr`, pois compressão em trânsito quebra byte ranges!).
- Bridges WebSocket binárias (ex.: `websockify`) mapeadas em `config.js` (`websocketOverrides`) para login (`7171`) e game (`7172`).

---

## 11. Limitações Conhecidas e Próximos Passos

1. **Testes em aparelhos físicos Android e iOS/iPadOS:** todos os benchmarks ao vivo foram coletados em Chrome headless com emulação móvel/touch e SwiftShader; a ergonomia real de 3 dedos, comportamento do teclado virtual nativo (Gboard/iOS Keyboard) e limites de memória do iOS WebKit devem ser verificados em hardware físico.
2. **Pop-in breve de sprites na primeira visita mobile:** como `Tibia.spr` é paginado em blocos de 256 KiB sob demanda, sprites inéditos aparecem assim que o `HTTP 206` conclui (em rede local/VPS rápida, dezenas de milissegundos; em 4G instável, pode haver leve pop-in na primeira visualização antes de ficar salvo no IndexedDB).
3. **Sem modo single-thread sem `SharedArrayBuffer`:** navegadores ou proxies que removam COOP/COEP não iniciarão o WASM multi-thread; HTTPS com headers de isolamento cross-origin é requisito obrigatório em produção.
4. **Próximos passos recomendados:** pré-aquecimento opcional em background das páginas de sprites mais comuns (UI/outfit inicial/terrenos base) após o login, e medição de telemetria em sessões longas de caça em celulares reais de 3–4 GB de RAM.
