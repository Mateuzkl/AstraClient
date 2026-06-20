# Relatório: `develop` (KoliseuClient/15.24) × `upstream/main` (AstraClient/8.60)

**Data:** 2026-06-19 · **Merge-base:** `9eb3dfd` (2026-06-01) · **Commits no upstream/main ainda não no fork:** 121 · **Commits próprios do fork desde a divergência:** 86

## Resumo executivo

O fork e o upstream **divergiram de direção**, não só de código:

- **Fork (KoliseuClient):** upgrade para **protocolo 15.24**, servidor **crystalserver/koliseuot**. Já fez 86 commits próprios (upgrade 15.24 + muitos fixes genéricos reimplementados de forma independente).
- **Upstream/main (AstraClient):** permaneceu em **8.60** / servidor **Astra**, somando features específicas do Astra (Battlepass, Task Hunt, Soul Seal, ATC, bounty talisman, item-value 0xC6/0xC7, highscores 8.60, etc.).

Por isso, dos **121 commits**, a maioria é **(C) específica do Astra/8.60** (não aplica e em alguns casos *quebraria* o stream 15.24), **(B) já feita** independentemente no fork, ou **(E) superada** (o fork foi por outro caminho deliberado). Sobraram **~22 commits genuinamente portáveis (Classe A)**, abaixo, em tiers por valor/risco.

> ⚠️ **2 bugs reais já presentes no fork** que o código do upstream conserta — ver Tier 1: `a923e0b` (equipment preset chama métodos C++ inexistentes → erro em runtime) e `b75a746` (UI do quickloot toda fiada, mas todas as chamadas ao servidor são *no-op stubs* → quickloot não faz nada).

---

## TIER 1 — Alto valor / risco baixo-médio (fazer primeiro)

### 1. `a923e0b` — Bindings C++ `Item::setHash`/`getItemHash` + `UIItem::setHash`  ⭐ corrige bug ativo
- **Por quê:** `mods/.../equipmentpreset.lua` JÁ chama `item:getItemHash()` (linhas 138, 295) e `newItem:setHash(...)` (252, 270), mas o C++ do fork **não tem** esses métodos (`m_hash`/`setHash`/`getItemHash`/`isInMarket` inexistentes). Essas chamadas **erram em runtime** hoje ao usar equipment presets.
- **Portar:** só a parte C++ (`item.h`, `uiitem.h`, `luafunctions_client.cpp`; opcional `isInMarket/setInMarket` em `localplayer.h`). **NÃO** portar a parte Lua (depende do `ItemsDatabase` removido).
- Esforço **baixo** / risco **baixo**.

### 2. `b75a746` — API C++ de envio do Quickloot  ⭐ destrava feature morta
- **Por quê:** a UI do quickloot do fork está toda fiada (`quickloot.lua`, `gameinterface.lua`, `keybinds.lua` chamam `quickLoot`, `quickLootArea`, `removeLootContainer`, `updateLootContainer`, `updateLootWhiteList`, `doThing`…), mas **todas são no-op stubs** em `globals.lua` (linhas 593-630). Ou seja, o quickloot **não envia nada** ao servidor — silenciosamente inativo.
- **Portar:** a API de envio (`game.cpp/.h`, `protocolgame.h`, `protocolgamesend.cpp`, `protocolcodes.h`, `luafunctions_client.cpp`). **PULAR** `parseLootContainers`/guard `getItemType` (já feitos no fork).
- ⚠️ **Verificar antes:** os opcodes 143/144/145 e o layout de bytes são valores CIP — confirmar que o crystalserver/15.24 usa o mesmo (gate `>= 1332`). Errar o wire format **desincroniza o stream**.
- Esforço **médio** / risco **médio-alto** (gated em verificação de protocolo).

### 3. `188652a` — Fixes do `UITextEdit` (seleção/cursor/scroll)  *(= `d6ab0e6`, que é o merge do mesmo fix)*
- **Por quê:** clipa os retângulos de highlight de seleção à área visível, evita retângulos fantasma em newlines/control-chars (buffer de bg separado), só desenha o caret quando `m_editable`, e não dá scroll-pro-topo ao focar com o mouse. O fork ainda tem o código antigo sem clamp (`uitextedit.cpp:117-122`, `update(true)` no focus).
- **Portar:** `src/framework/ui/uitextedit.cpp` + `.h`. Aplica em qualquer protocolo.
- Esforço **baixo** / risco **baixo**.

### 4. `7628dfa` (parcial) — Ativar a opção `lootHighlight` (que está morta) + nil-guards
- **Por quê:** o fork **tem** a opção "Show Loot Highlighting" (`dataset.lua:1258`, `default-config.otml:79`) mas é um **toggle órfão** — sem consumidor. O commit adiciona o filtro C++ do efeito 252 (`shouldShowLootHighlightEffect` em `parseMagicEffect`) que dá vida à opção. Também traz nil-guards limpos em `game_attachedeffects`.
- **Portar:** `settings.lua`, `protocolgameparse.cpp` (filtro do efeito 252), `mods/game_attachedeffects/lib.lua`+`attachedeffects.lua` (nil-guards). **PULAR** a reescrita de rarity-spritesheet (o fork usa frames per-color próprios).
- ⚠️ Confirmar que o koliseuot usa o efeito id **252** para loot highlight.
- Esforço **baixo** / risco **baixo**.

### 5. `74dd2a3` (parcial) — Bug `newPos`→`newPosition` no minimap + bind `setMinZoom`
- **Por quê:** `minimap.lua:186-191` referencia o global indefinido `newPos` (latente, mascarado porque o `oldPos` irmão é sempre nil e curto-circuita). O fork só bindou `setMixZoom`, não `setMinZoom`.
- **Portar:** só o fix do `minimap.lua` + o bind `setMinZoom` (`luafunctions_client.cpp`). O `ensureLayout`/waypoints já existem no fork (`cff30a3`).
- Esforço **baixo** / risco **baixo**.

---

## TIER 2 — Robustez / QoL, risco baixo

| # | Commit | O que traz | Arquivos | Esf/Risco |
|---|--------|-----------|----------|-----------|
| 6 | `e6ab8cb` | Guards de runtime: `closeRestoredWidget` (close→destroy→hide c/ pcall) + guards `LoadedPlayer` no topbar; evita crash no onPlayerLoad/topbar. Supersede `e0501e0`. | `gameinterface.lua`, `topbar.lua` | baixo-médio / baixo |
| 7 | `9534e67` | Flag "silent" na init dos combos de gráficos → valores salvos (DirectX11/AA) não são sobrescritos por defaults no boot. **Afeta os defaults Vulkan/Smooth-Retro do fork.** | `GameOptions.lua`, `graphics.otui` | baixo / baixo |
| 8 | `343e9c0` (só tooltip) | Guard de event-leak no tooltip agendado (`delayedTooltipEvent`/`mouseMoveConnected`). `tooltip.lua:58` do fork ainda vaza. | `corelib/ui/tooltip.lua` | baixo / baixo |
| 9 | `db113d7` (cherry) | Fix de **event-leak do shield-blink** da creature (`scheduleEvent` fire-and-forget vira `ScheduledEventPtr` cancelável) + cache de textura de creature-icon. Bug presente no fork. | `creature.cpp/.h` | médio / médio |
| 10 | `55abceb` | Nil-guard no `setSkillPercent` (manter o `/100` do fork — só adicionar o guard). | `game_skills/skills.lua` | baixo / baixo |
| 11 | `6459af3` (só bitmapfont) | `calculateGlyphsWidthsAutomatically` ganha bounds + bpp-awareness; o fork ainda faz leitura OOB de pixel em fonte malformada. | `framework/graphics/bitmapfont.cpp/.h` | médio / baixo-médio |
| 12 | `a8f4559` | Sliders de walk delay (turn/teleport/stairs) na UI — o fork tem as vars mas **hardcoded** sem UI. | `controls.otui`, `dataset.lua`, `settings.lua`, `walking.lua` | baixo-médio / baixo |
| 13 | `921b288` | Renderizar **CreatureIcons** (quest/modification c/ contador) — o fork **já parseia** o wire 15.24 (`protocolgameparse.cpp:1851`) mas **descarta**; ícones nunca aparecem. | `creature.h/.cpp`, alimentar no site de parse existente, `gamelib/creature.lua` | médio / baixo-médio |
| 14 | `e857bce` (parcial) | `pcall` em volta do `importFont` — uma `.otfont` ruim hoje **aborta todo o resto** do carregamento de estilos no fork. Extrair só o pcall (preservar o `table.sort` anti-overflow do fork). | `client_styles/styles.lua` | baixo / baixo-médio |

---

## TIER 3 — Polimento de UX, risco baixo

| # | Commit | O que traz | Arquivos | Esf/Risco |
|---|--------|-----------|----------|-----------|
| 15 | `69b521c` | Smooth scrolling em todas as scrollbars de UI. | `corelib/ui/uiscrollbar.lua`, `uiscrollarea.lua` | baixo-médio / baixo |
| 16 | `c6cadd8` | Animação suave de docking de miniwindows (`g_effects.moveTo`/easeOutCubic). `onDrop` do fork == base pré-patch → aplica quase limpo. | `corelib/ui/effects.lua`, `uiminiwindow.lua`, `uiminiwindowcontainer.lua` | baixo / baixo |
| 17 | `93a4ed9` | Highlight de alvo/follow imediato ao trocar de alvo (remove o "delay" do quadrado vermelho). | `game_battle/battle.lua` | baixo / baixo |
| 18 | `8e235f5` | Dedup do histórico de chat (msg reenviada sobe pro topo). | `game_console/classes/Chat.lua` | baixo / baixo |
| 19 | `bda363c` | Coloração de canais (World Chat/Help/NPCs) na lista e nas abas. Cosmético, isolado. | `game_console/classes/Channel.lua`, `TabMessages.lua` | baixo / baixo |
| 20 | `825e765` | Ctrl+K abre direto os Custom Hotkeys (sem flash do painel pai + sem delay de 100ms). | `client_settings/settings.lua` | baixo / baixo |
| 21 | `a6236fa` | Opção `talkOnRightClick` + dedup das checagens de distância de NPC. **Manter `g_game.sendNPCTalk`** (não o `talk("hi")` do 8.60). | `gameinterface.lua`, `battle.lua`, `dataset.lua`, `gameplay.otui` | baixo-médio / baixo |
| 22 | `c2b6a8b` (só creature.cpp) | Tira o render da mana-bar de dentro do bloco `DrawBars` p/ toggle independente. | `creature.cpp` | baixo / baixo |
| 23 | `ef90662` (parcial) | Troca o gate `isMobile()` por opção real `alwaysTurnTowardsMoveDirection` (wall-facing). **Pular** o flip de default do smartWalk. | `walking.lua`, `controls.otui` | baixo / baixo |

---

## TIER 4 — Condicional / precisa verificação / merge manual

| Commit | Observação | Risco |
|--------|-----------|-------|
| `0fbd0f7` | `else if`→`if` p/ quivers lerem o byte de quickloot-flags no `getItem`. **Verificar no crystalserver** se quiver/container carrega esse byte — errar **desincroniza o stream**. Faz par com b75a746. | médio-alto |
| `b9c502e` (só Unity) | Flags `EnableUnitySupport` no MSBuild (build mais rápido). **Testar compile** (Unity pode expor colisões ODR/nome). **Nunca** portar o rename AstraClient→otclient. | médio |
| `2c09074` | Auto-apply na janela de opções (debounce + guard de reentrância, remove botão Apply). `settings.lua` do fork muito divergente → adaptação manual. | médio |
| `a57ba62` | Wire dos toggles "show own" p/ as world-bars + guard do `harmonyArcSide` (o handler do fork em `hud.otui` está sem guard — bug real). `dataset.lua` divergente → adaptar. | baixo-médio |
| `fa81603` (parcial) | Hardening do `changeHotkeyProfile` (validar+salvar) + texto fallback da actionbar. **Pular** conteúdo de spell `exori`. `settings.lua` divergente. | médio |
| `aeef1fa` (seletivo) | Nuggets C++ num commit de helper: captura de **`masterId`** de summon + `CreatureTypeSummonOther` (o fork joga o master id fora) e **`hasFloorChange()`** em Thing/Tile (útil p/ cavebot/scripting) + guard no `table.find`. Merge do masterId precisa cuidado (getCreature reestruturado p/ 15.24). | médio |
| `b4ef479` / `4a0ebc8` | Robustez do saldo de coins/gift na store (cachear coins, ler no Gift). Mesma base Astra; **verificar se a UI de gift é alcançável no koliseuot**. `4a0ebc8` é subconjunto de `b4ef479`. Baixa prioridade. | baixo |

---

## ⚠️ NÃO portar (alguns *quebram* o fork)

- **`c0d3c62` (item-value 0xC6/0xC7):** no fork, **0xC6 = `GameServerHousesInfo`**. Registrar 0xC6 como ItemValues **corromperia o stream**. ❌
- **`1f378b2` (killtracker `getOutfit(msg,true)`):** layout de outfit 8.60 — quebraria o parse 0xD1 do fork (que lê inline, sem byte de type). ❌
- **`50fc40b` (vocation mapping):** assume IDs padrão; o fork usa **IDs não-padrão** (Sorc=3/13, Druid=4/14). Inverteria a detecção de vocação. ❌
- **`5d7edf8` (proficiency vector):** o fork consome perks como **map com chave** de propósito; mudar p/ vetor sequencial quebra. ❌
- **8.60/Astra-N/A:** Battlepass (`23a7678`), Task Hunt/Soul Seal (`274c4b6`,`07eade4`,`89742dc`,`f88442b`), ATC (`ff85cce`), bounty talisman (`539fd02`), notifications (`e854ce0`), multi-actionbar (`7c66c83`,`c07eedb`,`98722fc`,`2d8a688`,`7729960`,`2329bb9`), highscores 8.60 (`ad5038d`,`7aefcd8`), state-icon 0x8C (`1bb3e0f`,`889e5c7`), reward wall/market 8.60 (`855dddd`,`7b41844`,`f06597f`), store Astra (`e304c4a`,`0ad2a01`,`1dcc23f`,`90ae2af`,`343e9c0`-core).
- **Superado (fork foi por outro caminho):** xBRZ/HD-upscale (`876e982`,`e9a753a`,`53f1497`-parte) — fork **dropou xBRZ**; cursores animados (`2be9d2d`,`8bdca34`,`be2d8b5`,`8c46b8a`,`aa0d756`) — fork tem cursor estático `CreateIconIndirect`; damage stacking horizontal (`795784d`,`f83f0a8`,`64a7984`) — fork tem vertical+toggle `m_stackEffects`; Vulkan (`17128d9`) — fork tem ANGLE/Vulkan vendorado próprio; Balrog helper inteiro (`cd14c78`,`e02ab69`,`2b29475`,`00005fc`,`5eed6ef`,`3d9f92c`,`3793a0d`,`9448aec`,`21a8f40`,`d9a7570`) — for3
- **Já feito no fork:** font atlas 4096 (`0820e69`), world-time sync (`03e7c93`), bosstiary nil-guards (`9bd9c30`), hunt analyzer/special skills (`53f1497`), NPC trade actionbar (`6e9ac3e`), quickloot loadData guards (`da99bf3`), trackers/imbuement/parse 15.24 (`e85bc2d`).
- **Build/CI do upstream (CMake/vcpkg/GitHub Actions):** `55d883a`,`3b65f35`,`d12f770`,`383ebb0`,`e4b848f`,`10f6fed` — o fork usa MSBuild/compile.ps1 e já trata NOMINMAX/bigobj.
- **Trivial/noise:** `87070fe` (merge), `8300c80`/`8f8019c` (gitignore já coberto), `bf18c69`/`c7be41a` (readme), `41a906c`/`bda241f`/`c0d3c62`-scaffolding (8.60).

---

## Notas transversais de verificação

1. **Trio do quickloot** (`b75a746`, `0fbd0f7`, `d5d20d8`) depende de o crystalserver/15.24 usar os opcodes/format CIP de quickloot. **Verificar uma vez** resolve os três.
2. O módulo **`mods/game_protocol/protocol.lua` é `autoload:false` (código morto)** no fork — qualquer commit que só toca nele é SKIP automático.
3. As partes Lua que dependem do **`ItemsDatabase`** (removido do fork — `gamelib/items.lua` deletado) não aplicam; pular sempre essas fatias.

## Sugestão de ordem de execução
1. **`a923e0b`** (corrige erro ativo do equipment preset) — rápido.
2. **`b75a746` + verificação de protocolo** (destrava quickloot) — maior impacto.
3. Tier 2 inteiro (robustez barata): `e6ab8cb`, `9534e67`, `343e9c0`, `db113d7`, `55abceb`, `6459af3`, `e857bce`.
4. `921b288` (CreatureIcons) e `a8f4559` (walk delay UI) — features visíveis.
5. Tier 3 conforme gosto (polimento).
6. Tier 4 caso a caso, com os testes/verificações indicados.
