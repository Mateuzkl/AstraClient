# Plano de Implementação — API de Scripting (KoliseuClient)

Este documento consolida a auditoria de 11 agentes de design sobre a **API de scripting Lua** do KoliseuClient (o sandbox de bots exposto pela aba *Scripting* do `game_helper`, dialeto compatível com Zerobot). O objetivo é fechar todos os pontos que hoje são *stub*, *no-op* ou *parcial* — dizer, para cada um: por que está quebrado, como consertar, e quanto custa.

A **fonte da verdade é o código** (cliente Windows em `mods/game_helper/scripting/`, engine C++ em `src/`, e servidor crystalserver 1524 no WSL). A **wiki** em `koliseu-aac/docs/docs/scripting/` documenta o status *atual* de cada namespace e será atualizada junto de cada correção (as páginas hoje descrevem várias APIs como inertes/impossíveis — em vários casos essa descrição está desatualizada).

---

## Sumário executivo

Números agregados da auditoria:

- **58 itens** analisados nos 11 grupos.
- **42 client-only** (Lua puro; a maioria sem recompilar nada).
- **1 requires-server** (`Game.autoLoot`, resolvido com um *talkaction* — sem C++).
- **16 do-now-high**, **16 do-soon-medium**, **11 do-later-low**, **15 wont-fix**.
- Apenas **6 itens** exigem *rebuild* do cliente C++ (e vários deles têm *stopgap* em Lua).

**Achado central:** a esmagadora maioria dos "buracos" não é falta de feature — é **fiação**. O wrapper da API existe, mas está apontando para um `_G.xxx` que é `nil`, para uma flag que nenhum worker lê, ou para um gate morto (OTB/serverId). O **sender/global/worker real já existe no cliente** e já é usado pela UI do próprio jogo. Fechar esses itens é, na prática, "ligar o fio no lugar certo". Só 1 item toca o servidor, e mesmo assim de forma trivial. Hunting Tasks e as features PvP (anti-push, rune-max, login, licença) são **decisão de produto** — não-fazer conscientes, não bugs.

**Itens de maior impacto/prioridade (fazer primeiro):**

- **Stow trio** (`Container:stowItem` / `stowAllItems` / `Inventory.stowContainer`) — guardar loot no stash; os senders (`g_game.stowItem*`, opcode 0x28) já são instalados por `game_stash` e provados pela UI. ~1h de Lua, alto valor para bots.
- **`Npc.buy` / `Npc.sell`** — hoje sempre retornam `nil` por um gate OTB morto; a correção valida contra os *appearances* e reusa o `ItemPtr` da janela de trade. Fecha os dois de uma vez e mata o *log spam* "invalid thing type".
- **Waypoint-script exec context** (PR único) — Timer/HUD/eventos/modal dentro de um waypoint Script hoje lançam erro; pior, `CaveBot.pause(ms)` **congela** o cavebot sem resume. Um "script-record sintético" des-quebra 5 APIs e remove esse *hazard*.
- **`CaveBot.saveFile`** — hoje **sempre** retorna false (bug de `_G` local); publicar o saver e religar é 1 linha + rewire, e desbloqueia a persistência do CRUD.
- **Evento `LABEL` (13)** — hoje o handler de waypoint label é no-op; emitir via um novo bridge `Scripting.emitGameEvent`.
- **`Engine.enableCaveBot`** — hoje só grava a flag e o cavebot pode não andar; rotear pelo `toggleCavebotHelper`/`EnableCavebotReal` real.
- **`Player.getDustsMaximum`** — hoje retorna `0` fixo; ler `modules.game_forge.ForgeSystem.maxPlayerDust` (já populado no login pelo 0x86). Lua puro.
- **3 WIRE de Engine/Client** (`showMessage`, `reconnectEnable`, `holdTargetEnable`) — cada um liga a uma feature que já existe (`game_textmessage`, auto-reconnect, Hold Attack).

---

## Matriz de priorização

Uma linha por item (os 6 stubs `huntingTask*` idênticos foram condensados em uma linha). Ordenado por prioridade.

| Item | Grupo | Lado | Esforço | Prioridade | Recompila? |
|---|---|---|---|---|---|
| `Client.showMessage` → `displayGameMessage` | engine-client-features-sem-equivalente | client-only | S | do-now-high | Não |
| `reconnectEnable` / `isReconnectEnabled` | engine-client-features-sem-equivalente | client-only | S | do-now-high | Não |
| `holdTargetEnable` / `isHoldTargetEnabled` | engine-client-features-sem-equivalente | client-only | S | do-now-high | Não |
| `Container:stowItem` | stow-imbuement-fase2 | client-only | S | do-now-high | Não |
| `Container:stowAllItems` | stow-imbuement-fase2 | client-only | S | do-now-high | Não |
| `Inventory.stowContainer` | stow-imbuement-fase2 | client-only | S | do-now-high | Não |
| `Npc.buy` / `Npc.sell` (tradeItem) | npc-trade-itemid | client-only | S | do-now-high | Não |
| `CaveBot.saveFile` | cavebot-fase2 | client-only | S | do-now-high | Não |
| Evento `LABEL` (13) | cavebot-fase2 | client-only | M | do-now-high | Não |
| runSnippet: script-record sintético | waypoint-script-exec-context | client-only | M | do-now-high | Não |
| Ciclo de vida + `Scripting.stopSnippets()` | waypoint-script-exec-context | client-only | M | do-now-high | Não |
| Identidade por-waypoint (idempotência) | waypoint-script-exec-context | client-only | S | do-now-high | Não |
| `storage` no ambiente do snippet | waypoint-script-exec-context | client-only | S | do-now-high | Não |
| `CaveBot.pause(ms>0)` — remover hazard | waypoint-script-exec-context | client-only | S | do-now-high | Não |
| `Player.getDustsMaximum` | data-partials-icons-outfit-boss-dust-xp | client-only | S | do-now-high | Não |
| `Engine.enableCaveBot` → `EnableCavebotReal` | engine-client-inert-toggles | client-only | S | do-now-high | Não |
| `Container:pickItemImbuement` | stow-imbuement-fase2 | client-only | S | do-soon-medium | Não |
| `Inventory.pickItemImbuement` | stow-imbuement-fase2 | client-only | S | do-soon-medium | Não |
| CRUD waypoints → persistência via saveFile | cavebot-fase2 | client-only | L | do-soon-medium | Não |
| Corrigir docs Hunting Tasks (enganosos) | hunting-tasks | client-only | S | do-soon-medium | Não |
| Atualizar docs waypoint-script (novo contrato) | waypoint-script-exec-context | client-only | M | do-soon-medium | Não |
| `Creature:getIcons` (stopgap / binding completo) | data-partials-icons-outfit-boss-dust-xp | client-only | S | do-soon-medium | Stopgap Não / completo Sim |
| `isBoss` (getAllMonsters/getMonsterByRaceId) | data-partials-icons-outfit-boss-dust-xp | client-only | M | do-soon-medium | Sim |
| `Game.openDailyReward` | game-protocol-stubs | client-only | S | do-soon-medium | Não |
| `Game.collectDailyReward` | game-protocol-stubs | client-only | M | do-soon-medium | Não |
| `Game.getChannelsHistory` | game-protocol-stubs | client-only | S | do-soon-medium | Não |
| `Game.stashRetrieve` (gate `isInStash`) | game-protocol-stubs | client-only | S | do-soon-medium | Não |
| `setAlarm` / `isAlarmEnabled` / `allAlarmsEnable` | engine-client-inert-toggles | client-only | M | do-soon-medium | Não |
| `autoSSAEnable` / `isAutoSSAEnabled` | engine-client-inert-toggles | client-only | M | do-soon-medium | Não |
| `autoMightRingEnable` / `isAutoMightRingEnabled` | engine-client-inert-toggles | client-only | S | do-soon-medium | Não |
| `translate.spellGroup*` + religar cooldown de grupo | spellgroups-cooldown-mapping | client-only | S | do-soon-medium | Não |
| Corrigir chaves `.group` no SpellInfo | spellgroups-cooldown-mapping | client-only | S | do-soon-medium | Não |
| `Client.sendHotkey` (injeção de tecla) | engine-client-features-sem-equivalente | client-only | M | do-later-low | Sim |
| Npc read-helpers (`isTradeOpen`/`getBuyPrice`/…) | npc-trade-itemid | client-only | S | do-later-low | Não |
| Id estável de waypoint | cavebot-fase2 | client-only | M | do-later-low | Não |
| `Creature:getOutfit` — cores de montaria | data-partials-icons-outfit-boss-dust-xp | client-only | M | do-later-low | Sim |
| `Player.getXpBoostTime` (já exato; só comentário) | data-partials-icons-outfit-boss-dust-xp | client-only | S | do-later-low | Não |
| `Game.autoLoot()` | game-protocol-stubs | requires-server | S | do-later-low | Não (talkaction) |
| `Game.writeTextWindow(text[, id])` | game-protocol-stubs | client-only | S | do-later-low | Não |
| `Game.getItemCount` por tier | game-protocol-stubs | client-only | M | do-later-low | Sim |
| Aliases `Enums.SpellGroups` (AOE_MS/ED_BURSTS) | spellgroups-cooldown-mapping | client-only | S | do-later-low | Não |
| `HUD:setFontSize` | hud-setfontsize-setscale | client-only | S | do-later-low | Não |
| `HUD:setScale` sprite/item | hud-setfontsize-setscale | client-only | M | do-later-low | Sim |
| `Client.login` (login por credenciais no sandbox) | engine-client-features-sem-equivalente | wont-fix | S | wont-fix | — |
| Anti-Push (`antiPushEnable`/`setFirst/SecondAntiPushId`…) | engine-client-features-sem-equivalente | wont-fix | L | wont-fix | — |
| Rune Max (`runeMaxEnable`/`get/setRuneMaxId`…) | engine-client-features-sem-equivalente | wont-fix | M | wont-fix | — |
| `getUserId` / `getLicenseTime` / `loadConfig` | engine-client-features-sem-equivalente | wont-fix | S | wont-fix | — |
| Popular OTB/itemType no boot (alternativa rejeitada) | npc-trade-itemid | wont-fix | L | wont-fix | — |
| Binding `g_things.isValidDatId` (alternativa rejeitada) | npc-trade-itemid | wont-fix | S | wont-fix | — |
| CaveBot sell list (`get/setSellList`) | cavebot-fase2 | wont-fix | M | wont-fix | — |
| CaveBot end-lure (`set/getEndLureSettings`) | cavebot-fase2 | wont-fix | XL | wont-fix | — |
| `Game.huntingTask*` (6 ações: RerollList/RerollRewards/ListAllMonsters/SelectMonster/Cancel/Claim) | hunting-tasks | wont-fix | S | wont-fix | — |
| `Game.Events.TASK_HUNTING_DATA` (evento id 21) | hunting-tasks | wont-fix | S | wont-fix | — |

---

## Fase 1 — Quick wins client-only (prioridade alta, sem build)

Todos os 16 itens abaixo são `client-only`, `do-now-high` e **não exigem recompilar** — puro Lua, valem no próximo reload/restart do cliente.

### Client.showMessage → modules.game_textmessage.displayGameMessage

- **Causa-raiz:** `client.lua:97-103` tenta `_G.displayGameMessage`, que é `nil`. `displayGameMessage` é definido como **global dentro** do módulo `game_textmessage` (`textmessage.lua:68`), que é *sandboxed* (`textmessage.otmod:6 sandboxed:true`), então a global vive no env do módulo, não em `_G` (padrão *sandboxed-module-cross-access*). A chamada sempre cai em `unsupported()`. O `helper.lua` já usa o padrão correto ~40x (ex.: `helper.lua:2511`).
- **Correção:** editar `mods/game_helper/scripting/api/client.lua` em `Client.showMessage`: usar `modules.game_textmessage.displayGameMessage` sob `pcall` (`local m = modules and modules.game_textmessage; if m and type(m.displayGameMessage)=='function' then pcall(m.displayGameMessage, tostring(message or '')); return end`); senão `unsupported('showMessage')`. Usa `MessageModes.Game` (mensagem central). Atualizar `client.md`.
- **Risco:** baixíssimo — só muda o alvo de uma chamada já embrulhada em `pcall`; sem protocolo, sem crash.
- **Teste:** script `Client.showMessage('teste 123')` online → mensagem central na tela; offline não desenha (isConnected false), mas sem erro.

### reconnectEnable / isReconnectEnabled → auto-reconnect existente

- **Causa-raiz:** stubs em `engine.lua:138`/`:228` e `client.lua:588-589`. Mas o motor de auto-reconnect existe e está ligado à UI: `characterlist.lua:400-427` (`scheduleAutoReconnect`/`executeAutoReconnect`), alimentado por duas fontes — flag global `g_settings 'autoReconnect'` e o node per-char `getAutoReconnect`/`saveAutoReconnect` (`characterlist.lua:1007-1016`). O helper já expõe o setter único: `modules.game_helper.toggleAutoReconnect(checked)` (`helper.lua:16456-16463`), o mesmo do checkbox "Auto Reconnect".
- **Correção:** em `engine.lua`/`client.lua`: `reconnectEnable(b)` → `modules.game_helper.toggleAutoReconnect(b==true)`; `isReconnectEnabled()` → se online e existir `getAutoReconnect`, `getAutoReconnect(g_game.getCharacterName())`, senão `g_settings.getBoolean('autoReconnect', false)`. Preferir **apenas o toggle** (não adicionar `Client.reconnect()` imperativo — só dispara offline na character list e o script do sandbox morre no logout).
- **Risco:** baixo — escreve preferência persistida client-side, sem protocolo. Se a aba Tools estiver aberta, o checkbox só re-sincroniza no próximo load do helper (aceitável, igual aos outros setters de flag).
- **Teste:** `Client.reconnectEnable(true)`; conferir `g_settings.getBoolean('autoReconnect')` e `getAutoReconnect(char)` true; E2E: com reconnect ON, matar a conexão online → `scheduleAutoReconnect` re-loga; com OFF não religa.

### holdTargetEnable / isHoldTargetEnabled → Hold Attack existente

- **Causa-raiz:** stubs em `engine.lua:132`/`:221` e `client.lua:579-580` (com comentário "holdAttack is a different thing" — incorreto). O **Hold Attack do helper é exatamente** o hold-target do ZB: `helperConfig.holdAttack` + worker `checkHoldAttack()` (`helper.lua:16605-16666`) que re-ataca o alvo travado e só cancela no ESC. Já existe setter com semântica SET: `modules.game_helper.toggleHoldAttack(checked)` (`helper.lua:16469-16482`).
- **Correção:** `isHoldTargetEnabled()` → `flag('holdAttack')`; `holdTargetEnable(b)` → `modules.game_helper.toggleHoldAttack(b==true)`. **Documentar 2 nuances vs ZB:** (a) é mutuamente exclusivo com `autoTarget` — `checkHoldAttack` retorna cedo se `helperConfig.autoTargetEnabled` (`helper.lua:16610`); (b) só o ESC limpa o lock.
- **Risco:** baixo — grava flag client-side; o worker já roda no `helperCycle`. Sem protocolo novo (usa `g_game.attack`). Se `autoTarget` estiver on, `holdAttack` fica inerte por design (documentar).
- **Teste:** atacar um monstro manualmente, `Client.holdTargetEnable(true)` → deve re-atacar o mesmo alvo ao andar/parar; ESC limpa o lock; com `autoTarget` on, fica inerte.

### Container:stowItem(containerSlot, itemCount)

- **Causa-raiz:** stub em `container.lua:289-293` (só `ctx.log('...Fase 2')` + `return false`). O comentário `container.lua:287` ("`g_game.stowItem` é no-op / gameNoops") está **desatualizado**: `mods/game_stash/stash.lua:216-218` instala `g_game.stowItem` no `init()`, sobrescrevendo o noop de `globals.lua:652`. Sender real → `sendStashStow` (`stash.lua:68-86`): opcode 0x28, action `SUPPLY_STASH_ACTION_STOW_ITEM=0`. UI que já usa: `gameinterface.lua:1204`. **Não existe** binding C++ `Game::stowItem` — é override Lua.
- **Correção:** em `container.lua`, adicionar helper local `stashModLoaded()` (`g_modules.getModule('game_stash'):isLoaded()`). Reescrever: resolver o container e o item; gate por `stashModLoaded()` e `g_game.getLocalPlayer():isInStash()`; então `g_game.stowItem(item:getPosition(), item:getId(), item:getStackPos(), itemCount or item:getCount())`; `return true`. Atualizar comentário `container.lua:33-34` e wiki `container.md:301-311`.
- **Risco:** BAIXA — Lua puro; guardas nil + gate de módulo; reusa sender/bytes já validados pela UI; longe do depot o gate retorna false (e o servidor dropa via `isStashMenuAvailable`).
- **Teste:** perto de um depot, `Container(0):stowItem(0)` → item some da bag e aparece no Stash; longe do depot → false; `game_stash` descarregado → false + log; stack: `Container(0):stowItem(slot, 50)` guarda 50.

### Container:stowAllItems(containerSlot)

- **Causa-raiz:** stub em `container.lua:296-300`. Sender real: `stash.lua:220-222` `g_game.stowItemContainerStack(action,pos,itemId,stackpos)`. Mapeia para "Stow all items of this type" = `SUPPLY_STASH_ACTION_STOW_STACK=2` (`gameinterface.lua:1205`; constante em `player.lua:31`). Layout igual ao `stowItem` mas **sem** o byte de count.
- **Correção:** reescrever reusando `resolve()`+`itemAt()`+`stashModLoaded()`+`isInStash` (do item anterior): `g_game.stowItemContainerStack(SUPPLY_STASH_ACTION_STOW_STACK, item:getPosition(), item:getId(), item:getStackPos()); return true`. Atualizar comentário e wiki.
- **Risco:** BAIXA. Única incerteza é semântica (ver Questões em aberto): STOW_STACK ("todos do tipo") vs esvaziar o container inteiro. Recomendado STOW_STACK, para particionar limpo com `Inventory.stowContainer` (STOW_CONTAINER).
- **Teste:** perto do depot, bag com várias pilhas do mesmo id, `Container(0):stowAllItems(slotDoItem)` → todas as pilhas daquele id vão pro stash.

### Inventory.stowContainer(inventorySlot)

- **Causa-raiz:** stub em `inventory.lua:104-108`; comentário `inventory.lua:102` desatualizado. Mapeia para "Stow container's content" = `SUPPLY_STASH_ACTION_STOW_CONTAINER=1` (`gameinterface.lua:1198`; `player.lua:30`). Item vem de `slotItem(inventorySlot)`.
- **Correção:** adicionar `stashModLoaded()` local em `inventory.lua`; gate `isInStash`; enviar **direto** `g_game.stowItemContainerStack(SUPPLY_STASH_ACTION_STOW_CONTAINER, ...)`. **IMPORTANTE:** não chamar `modules.game_stash.stowContainerContent` (abre modal de confirmação — script não quer modal). Atualizar comentário `inventory.lua:26-27` e wiki.
- **Risco:** BAIXA (STOW_CONTAINER já usado pela UI).
- **Teste:** perto do depot, backpack cheia equipada, `Inventory.stowContainer(Enums.InventorySlot.CONST_SLOT_BACKPACK)` → conteúdo stowável vai pro stash; slot vazio → nil; `game_stash` off → false.

### Npc.buy / Npc.sell — trocar o gate OTB morto por validação de appearances

- **Causa-raiz:** `npc.lua:46-51` — `tradeItem()` faz `g_things.getItemType(id):getServerId()==0 → nil`. No boot 1524 só roda `loadAppearances` (`thingtypemanager.cpp:273-299`), nunca `loadOtb` (`:432`), então `m_itemTypes.size()==1` (só o null type) e **qualquer id retorna serverId 0** — o gate sempre falha e ainda loga `"invalid thing type, server id"`. Prova de que OTB não é preciso: buy/sell (`protocolgamesend.cpp:470-493`) mandam `addItemId(item->getId())`; a janela 0x7A (`protocolgameparse.cpp:1482-1486`) lê `getItemId()`→`Item::create(id)`; no servidor `networkmessage.hpp:74-79` `addItemId`/`getItemId` são `add/get<uint32_t>` puros. **O id na wire já é o client/appearance id**; subType só importa em fluid container.
- **Correção:** arquivo único `mods/game_helper/scripting/api/npc.lua`. (1) constantes `local NPC_BUY, NPC_SELL = 1, 2`. (2) Reescrever `tradeItem(id, kind)` em 2 camadas: **primeiro** o `ItemPtr` exato da janela aberta — `modules.game_npctrade.getTradeItemData(id, kind)` (`npctrade.lua:937`, carrega o subType correto inclusive de fluid); **fallback** validando appearances sem OTB — `local item = Item.create(id, 0); if not item or item:getId()==0 then return nil end; return item` (`Item::setId` zera o client id de id inexistente, `item.cpp:188-193`). (3) Trocar os call sites `npc.lua:58`/`:71` para passar `NPC_BUY`/`NPC_SELL`. (4) Atualizar comentário `npc.lua:42-51`. Semântica preservada: `nil`=não é item real; `false`=offline/amount<1; `true`=pacote enviado.
- **Risco:** baixo — puro Lua, roda fora do sandbox; `pcall` no acesso cross-module. Some o *log spam* "invalid thing type". U32-safe (ids >65535 passam sem truncar; feature 140).
- **Teste:** shop aberto, `Npc.buy(<id_de_runa>, 1)` → compra + true; `Npc.buy(999999, 1)` → nil; offline → false; NPC comprador `Npc.sell(<id>, 1)` → vende + true; fluid container (vial) → subType casa via `data.ptr`; conferir que o log não gera mais "invalid thing type".

### CaveBot.saveFile — publicar o saver e religar (bug: SEMPRE false)

- **Causa-raiz:** `cavebot.lua:773-781` lê `_G.saveCavebotToFile` (`:777`); esse saver é **local** em `hunting_recorder.lua` (fwd-decl `:4110`, definido `:5563`), **nunca publicado** em `_G` nem no module table. O guard `:778` (`type(saver)~='function'`) sempre falha → `saveFile` retorna false para qualquer nome. Wiki `cavebot.md:616-629` audita como QUEBRADO.
- **Correção:** (a) em `hunting_recorder.lua`, logo após `:5592`, adicionar `hunting_recorderModule.saveCavebotToFile = saveCavebotToFile`. (b) em `cavebot.lua:773-781`, trocar `local saver = _G.saveCavebotToFile` por `local m = hr(); local saver = m and m.saveCavebotToFile`; manter o `pcall(saver, tostring(fileName), data, true)` (o `force=true` é obrigatório, senão retorna false em `:5564`). Opcional cosmético: `m.refreshMainCavebotsList()` para o Manager mostrar o arquivo novo.
- **Risco:** baixo — sem build, `pcall`. Ressalva: persiste `cavebotData.waypoints`, que pode estar *stale* vs a `actionList` do motor se o script usou o CRUD de runtime (endereçado no item de persistência do CRUD, Fase 2).
- **Teste:** com um perfil ativo, `CaveBot.saveFile('test_api')` → true; conferir `/helper/cavebots/test_api.json` no disco; `CaveBot.loadFile('test_api')` → true.

### Evento LABEL (13) — emitir na chegada ao waypoint label

- **Causa-raiz:** `actions.lua:588-590` — o handler da ação `label` é no-op `return true`; o loop avança por índice (`core.lua:63`) e nunca notifica o registry de eventos. O `Game.executeEvents` (`game.lua:558`) só é alcançável via `ZB_API`, que é **local** de `scripting.lua` (`:460-470`); não há acessor público. `Game.Events.LABEL=13` (`game.lua:530`). Wiki `events.md:571-573` e `cavebot.md:108-122` auditam como morto.
- **Correção:** (a) em `scripting.lua`, adicionar bridge público `Scripting.emitGameEvent(eventType, ...)` que chama `ZB_API.Game.executeEvents` (que já isola cada handler com `ctx.wrap`+`pcall` e é no-op sem listener). (b) em `actions.lua:588`, dentro do handler label: `if _G.Scripting and _G.Scripting.emitGameEvent then pcall(_G.Scripting.emitGameEvent, 13, value) end` antes de `return true` (o `value` é o nome do label, `core.lua:776`). **PAUSE:** não auto-pausar (congelaria cavebots Amon que usam label como alvo de salto); scripts que querem o padrão ZB chamam `CaveBot.pause()`/`pause(0)` manualmente.
- **Risco:** baixo-moderado — sem build; `pcall` duplo + isolamento do `executeEvents`; emissão é no-op barato sem listener. A auto-pause opcional (gated por listener) tem *footgun* de travar a hunt — por isso fica opcional.
- **Teste:** `Game.registerEvent(Game.Events.LABEL, function(name) print('LABEL '..tostring(name)) end)`; rota com um WP Label 'inicio' → esperar 'LABEL inicio' no console a cada passagem; cavebot com labels e sem listener roda inalterado.

### Waypoint-script exec context — os 5 itens abaixo formam UM PR coeso

Os cinco itens seguintes (`runSnippet`, ciclo de vida, identidade, `storage`, `pause`) são um único PR em `scripting.lua` mais dois one-liners em `core.lua` e `actions.lua`. Juntos, des-quebram Timer/HUD/`Game.registerEvent`/`CustomModalWindow` dentro de waypoints Script **e** removem o *hazard* do cavebot congelado.

#### runSnippet: estabelecer um script-record sintético

- **Causa-raiz:** `Scripting.runSnippet` (`scripting.lua:504-513`) compila e roda o chunk com `pcall` mas **nunca seta** o upvalue `runningScript` (ao contrário de `runScriptOnce`, `:518-525`). `ctx.wrap` (`:376-389`) lança "wrap() must be called while a script is running" quando `runningScript` é nil; `ctx.onCleanup` idem (`:331-334`). Por isso, dentro do waypoint Script (`actions.lua:648-673`): `Timer()` quebra (`timer.lua:93`), `HUD()` aborta (`hud.lua:117-119`), `Game.registerEvent()` quebra (`game.lua:578`), `CustomModalWindow()` aborta (`custommodalwindow.lua:97-99`). O erro é engolido pelo `pcall` → o waypoint avança.
- **Correção:** em `scripting.lua`: (a) novo `local snippetRecords = {}` (tabela **forte**, não weak — senão o record com storage some entre voltas por GC). (b) helper `getSnippetRecord(key)` que cria/reusa `{ name='cavebot:wp'..key, enabled=true, cleanups={}, storage={}, errors=0, isSnippet=true }`. (c) reescrever `runSnippet(code, extra, chunk, key)`: após `loadstring`/`setfenv`, `s=getSnippetRecord(key or chunk)`; `prev=runningScript; runningScript=s; ok,ret=pcall(fn); runningScript=prev`. Nenhuma mudança em `timer.lua`/`hud.lua`/`game.lua`/`custommodalwindow.lua` — todas passam a funcionar.
- **Risco:** baixo — Lua puro, só `pcall`. Efeito colateral: Timer/HUD/eventos criados no corpo passam a **persistir** após o waypoint avançar (endereçado pelos itens de ciclo de vida/identidade/storage).
- **Teste:** waypoint Script com `Timer('t', function() print('tick') end, 1000)`; ligar o cavebot; **não** deve aparecer "wrap() must be called…"; deve aparecer 'tick' a cada 1s. Repetir com `HUD`, `Game.registerEvent`, `CustomModalWindow`.

#### Ciclo de vida: registry por-sessão-do-cavebot + Scripting.stopSnippets() + hooks de teardown

- **Causa-raiz:** sem um dono e um momento de limpeza, os callbacks diferidos vazam. Timer cria um `cycleEvent` próprio (`timer.lua:63-71`) que só morre via `ctx.onCleanup`; HUD é widget parenteado ao map panel (`hud.lua:140`); `Game.registerEvent` conecta um sinal de engine. Hoje **não há dono nem hook** de limpeza para snippets. O modelo coerente é **por-sessão-do-cavebot**: side-effects vivem enquanto o cavebot está ligado e caem quando ele desliga/reloga.
- **Correção:** em `scripting.lua`: (a) `Scripting.stopSnippets()` itera `snippetRecords`, chama `stopScript(s)` (reuso de `:241-251`, roda cleanups newest-first), e `snippetRecords[k]=nil`. (b) chamar `Scripting.stopSnippets()` dentro de `Scripting.offline()` (`:890-894`) e `Scripting.terminate()` (`:896-902`). (c) guardar `onScriptError` (`:255-265`) com `if not s.isSnippet then ... end` (Option A: snippet loga o erro do callback mas **não** auto-desabilita). Em `core.lua`, no `CaveBot.setOff` (`:502-528`), **após** o guard `if val==false then return CaveBot.setOn() end` e junto do teardown: `if Scripting and Scripting.stopSnippets then pcall(Scripting.stopSnippets) end`. `setOff` é o funil de parada (stopWalk, loadCavebotByName, init teardown, ação `stop_cavebot`).
- **Risco:** médio-controlado — se `stopSnippets` falhar em algum caminho, vaza timer/HUD (mitigado pela cobertura tripla setOff+offline+terminate). **Cuidado 1:** o hook vai APÓS o guard `val==false` (senão `setOff(false)`=`setOn` limparia ao ligar). **Cuidado 2:** o watchdog externo faz `stopWalk(true)+startWalk` (`helper.lua:5878-5880`) → HUDs/timers piscam no restart (aceitável).
- **Teste:** waypoint Script com `if not storage.h then storage.h=HUD(50,50,'x') end` + `Timer('t',...,500)`; ligar → HUD aparece, timer roda; **desligar** → HUD some, timer para; relogar com cavebot ligado → recriados limpos (sem duplicar); trocar de profile → registry limpo.

#### Identidade por-waypoint reutilizável (idempotência em retry/volta)

- **Causa-raiz:** `runSnippet` é chamado muitas vezes por waypoint (uma vez por retry, `core.lua:118`, e uma vez por volta). Se cada chamada criasse um record novo, cada retry/volta criaria Timers/HUDs novos → vazamento massivo. Reutilizar o **mesmo record por identidade de waypoint** torna a recriação idempotente para Timer (`timer.lua:97-103` substitui timer de mesmo nome/dono), mas **não** para HUD/Event/Modal (que incrementam seq).
- **Correção:** chave = índice do waypoint. Em `actions.lua` (ação `script`, `:665`), mudar `Scripting.runSnippet(value, extra, '@cavebot_script')` para passar `(CaveBot.getCurrentIndex and CaveBot.getCurrentIndex()) or 0` como `key`. `getCurrentIndex` é global do engine (`core.lua:577`). `getSnippetRecord` reusa `snippetRecords[index]` entre retries e voltas. O índice é estável durante um run porque editar waypoint exige cavebot desligado e `setOff` limpa o registry. **Contrato de idempotência:** Timer é seguro a cada tick; HUD/Event/Modal devem ser guardados com `storage` (`if not storage.x then storage.x = HUD(...) end`).
- **Risco:** baixo. Risco residual = double-creation em retry para HUD/Event/Modal se o usuário não guardar com `storage` (footgun de usuário, mitigado pelo item de `storage` + docs).
- **Teste:** waypoint com `Timer('t',...,1000)` **sem** guarda, várias voltas → deve existir só 1 timer 't'. HUD sem guarda → 1 widget por volta (vazamento esperado, demonstra a necessidade); com guarda `storage` → 1 único widget.

#### Injetar storage no ambiente do snippet (guarda create-once)

- **Causa-raiz:** hoje o `extra` do waypoint Script (`actions.lua:654-664`) injeta só `retries`/`prev`/`delay`/`gotoLabel`/`print` — **não** injeta `storage` (wiki `waypoint-script.md:116` confirma). Sem estado persistente entre execuções, não há como fazer *create-once* para HUD/Event/Modal (o único jeito seguro num contexto que roda a cada tick/volta).
- **Correção:** no `runSnippet` (item do record), mesclar `merged.storage = s.storage` quando o caller não fornece storage. O storage vem do record, então **persiste entre retries E voltas** do mesmo waypoint, e some quando o cavebot desliga. Igual à semântica do storage da aba Scripting (memória-de-sessão, nunca em disco). Habilita `if not storage.hud then storage.hud = HUD(10,10,'boss') end`.
- **Risco:** baixo. Contradiz a doc atual (`waypoint-script.md:116`) — exige atualização (item de docs).
- **Teste:** waypoint `storage.n = (storage.n or 0) + 1; print('n='..storage.n)`; várias voltas → n incrementa; desligar/religar o cavebot → n reinicia em 1.

#### CaveBot.pause(ms>0): remover o hazard de cavebot congelado

- **Causa-raiz:** é o caso mais grave. `CaveBot.pause` (`cavebot.lua:303-319`): para `ms>0` chama `e.pause()` (`core.lua:530`: `isPaused=true`) e **só depois** monta `resume=ctx.wrap(...)` (`:313`), que **lança** porque `runningScript` é nil. O erro sobe pelo `pcall`, é logado, o waypoint avança — mas `isPaused` ficou true e nenhum `scheduleEvent(resume)` foi agendado. Resultado: `mainLoop` (`core.lua:372`) retorna cedo para sempre; o cavebot fica **travado** até religar manualmente (wiki `waypoint-script.md:173`).
- **Correção:** resolvido diretamente pelo item do script-record: com `runningScript` setado, `ctx.wrap` para de lançar, o `scheduleEvent(resume, ms)` é agendado e o cavebot volta após `ms`. **Documentar interação síncrono×assíncrono:** se o script chama `pause(ms)` e retorna `true`, o waypoint **avança** (currentActionIndex++) e o cavebot resume no **próximo** waypoint; para pausar "neste" waypoint, retorne `'retry'`. Defesa em profundidade opcional: reordenar em `cavebot.lua` para montar o `resume` **antes** de `e.pause()`.
- **Risco:** o fix **remove** um hazard alto (cavebot congela hoje) → risco negativo (melhora). Com o record aplicado, risco residual baixo.
- **Teste:** waypoint `CaveBot.pause(800); return true`; ligar → sem erro de wrap; pausa ~800ms e retoma, **não** congela; `CaveBot.pause(0)` = resume imediato. Contrastar com o baseline (sem fix) que trava.

### Player.getDustsMaximum

- **Causa-raiz:** `player.lua:296-298` retorna `0` fixo. O limite de dust **não** é um resource do LocalPlayer — chega no pacote de config da forja **0x86** (`forge.lua:103-104`: `dustLevel`/`maxDust`), guardado em `ForgeSystem.maxPlayerDust`/`maxDust` (`Forge.lua:101-103`). O servidor empurra 0x86 **no login** (`protocolgame.cpp:8521`) e `forge.lua` registra o opcode no `init` (`:282-291`), então `maxPlayerDust` já está populado logo após o login, sem abrir a forja.
- **Correção:** reescrever `Player.getDustsMaximum()` para ler `modules.game_forge.ForgeSystem` com type-check: `if type(fs)=='table' and type(fs.maxPlayerDust)=='number' then return fs.maxPlayerDust end; return 0`. Caminho `modules.game_forge.X` é o padrão comprovado para módulo sandboxed. Sem binding C++.
- **Risco:** nenhum (Lua guardado). Único caso de 0: janela curtíssima antes do 0x86 do login, ou `game_forge` desabilitado — ambos cobertos pelo fallback.
- **Teste:** `Player.getDusts()..'/'..Player.getDustsMaximum()` (a) logo após login e (b) após abrir a forja → limite real (ex.: 100/225) nos dois. Corrige o exemplo da wiki `exemplos.md:82` (hoje mostra denominador 0).

### Engine.enableCaveBot → gatilho real EnableCavebotReal

- **Causa-raiz:** `engine.lua:199-201` só faz `setFlagPersisted('cavebotHelperEnabled', enable)`. O toggle real `toggleCavebotHelper` (`helper.lua:32980-33029`) chama `EnableCavebotReal(1/2)` (`hunting_recorder.lua:1246-1368`) que valida waypoints ≥2, bloqueia em área restrita/gravação, marca o checkbox, dispara `map.enabled`, inicia minimap waypoint update + gold balance, e exibe a mensagem. Escrever só a flag pula tudo isso → o cavebot pode **não** começar a andar. Wiki `engine.md:132-136`.
- **Correção:** reescrever `Engine.enableCaveBot` reusando `setViaToggle` (`engine.lua:77-84`): `setViaToggle(Engine.isCaveBotEnabled, _G.toggleCavebotHelper, enable)`; depois `return Engine.isCaveBotEnabled()` para refletir o **desfecho real** (`EnableCavebotReal` pode RECUSAR e deixar a flag false). Manter fallback ao `setFlagPersisted` se `toggleCavebotHelper` ausente. Não precisa editar `helper.lua`.
- **Risco:** sem build/crash. Gameplay MÉDIO: ligar inicia caminhada real — mas só com cavebot de 2+ waypoints; `EnableCavebotReal` já protege (mensagem de falha + reset do checkbox). Muda o contrato de retorno de "gravou" para "estado real" (desejável).
- **Teste:** com cavebot de 2+ WP, `Engine.enableCaveBot(true)` → mensagem "Cavebot Helper is enabled", anda a rota, checkbox marcado; `(false)` → para e desmarca; sem waypoints → retorna false + mensagem de falha.

---

## Fase 2 — Client-only, esforço médio (prioridade média)

Itens `do-soon-medium` e `client-only`. Salvo nota, nenhum exige recompilar (a versão *completa* de `getIcons` e o item `isBoss` exigem build e estão detalhados na Fase 3, com prioridade `do-soon-medium`).

### Container:pickItemImbuement / Inventory.pickItemImbuement

- **Causa-raiz:** stubs em `container.lua:304-308` e `inventory.lua:112-116` ("protocolo não portado" — **falso**). `g_game.selectImbuementItem(itemId, position, stackPos)` é **binding C++ real** (`luafunctions_client.cpp:418` → `game.cpp:1564` → `protocolgamesend.cpp:984`, `ClientImbuementAction=178`/`IMBUEMENT_WINDOW_SELECT_ITEM=1`). A UI usa exatamente isso (`imbuementselection.lua:55`). Apesar de estar em `globals.lua:630`, o `or noop` preserva o binding C++ registrado no boot.
- **Correção:** reescrever ambas para resolver o item e chamar `g_game.selectImbuementItem(item:getId(), item:getPosition(), item:getStackPos())`. **Não** precisa gate de módulo nem `isInStash`. **Documentar precondição:** a janela de imbuing precisa estar **aberta** (semântica do servidor; não há primitiva client→server para abrir a janela de um item arbitrário — o caso de uso é auto-imbue com a janela já aberta). Atualizar comentários e wiki `container.md`/`inventory.md`.
- **Risco:** BAIXA — mesmos bytes de `imbuementselection.lua`; binding C++ tem gate `canPerformGameAction`; se a janela não estiver aberta, o servidor ignora o pacote.
- **Teste:** abrir a janela de imbuing (shrine), `Container(0):pickItemImbuement(slot)` com item imbuível → a janela repopula; slot vazio → false.

### CRUD de waypoints → amarrar a persistência via saveFile

- **Causa-raiz:** `addWaypoint`/`insertWaypoint`/`replaceWaypoint`/`deleteWaypoint` (`cavebot.lua:333-377`) editam a `actionList` do **motor** (`core.lua:589-641`), uma projeção só-runtime. `saveFile` persiste `cavebotData.waypoints` — **modelo diferente** (montado pelo Manager/recorder, `hunting_recorder.lua:6539-6581`). Os dois nunca sincronizam, e a `actionList` é reconstruída de `cavebotData.waypoints` no start (`core.lua:835`), então o CRUD de runtime é duplamente efêmero. Wiki `cavebot.md:199-210,702-710`.
- **Correção:** preferir **Opção B** (lossless, construir dos args ZB): os wrappers CRUD mantêm **também** `cavebotData.waypoints`, montado dos args originais (que têm a posição, ao contrário da string `value` do motor). Criar helper `zbToCavebotWaypoint(index, waypointType, x,y,z, extraData)` devolvendo a forma persistida (`{index, position, type=<string>, label, gotoCondition, levitateMode, ...}`), reusando **exatamente** o set de type-strings de `hunting_recorder.lua:308-330`. `addWaypoint`: após `e.addAction`, `table.insert(data.waypoints, ...)` + `hr().setCurrentCavebotData(data)`. `insert`/`replace`/`delete`: mutar e **reindexar** (`for i,w in ipairs(list) do w.index=i end`, espelhando `hunting_recorder.lua:7223-7225`). **Opção A** (mais leve, lossy p/ posição de goto/label): `actionsToWaypoints(actionList)` dentro do `saveFile` antes de escrever.
- **Risco:** moderado — sem build; mapa de tipos ou reindex errado pode corromper um perfil salvo (mitigar reusando o set exato de `hunting_recorder`). **Depende do `saveFile` (Fase 1) entrar antes.**
- **Teste:** `clearWaypoints`; `addWaypoint(NODE/GOTO/LABEL...)`; `saveFile('crud_test')`; `loadFile('crud_test')`; `getWaypoints()` → mesma rota; ligar o cavebot e confirmar que anda a rota salva; comparar o JSON com um perfil salvo pelo Manager.

### Corrigir documentação/comentários enganosos (Hunting Tasks)

- **Causa-raiz:** três fontes afirmam **falsamente** que a feature está desligada no servidor: `game.lua:495-498`/`:940`; wiki `game.md:434-447`; memory `hunting-tasks-removed-from-client.md`. Realidade auditada: `config.lua:185 taskHuntingSystemEnabled=true` (default true, `configmanager.cpp:163`); o servidor **envia** 0xBB; e existe um task system **vivo diferente** — mod `game_tasks` (`tasks.lua:4-5`, ext opcode 211 + 0xBC `TaskKillTick`; bridge servidor em `task_otc_bridge.lua`). A causa do stub não é "feature off", e sim que a API ZB `huntingTask*` mira o protocolo legado prey-adjacent (0xBB + `PreyAction_t`), órfão/sem UI.
- **Correção:** reescrever os comentários em `game.lua` (495-498, 940) e a seção da wiki `game.md:434-447` para: (1) `huntingTask*` = Task Hunting **legado** (0xBB + `PreyAction_t`), sem send binding, sem UI, handler órfão (`IOPrey::parseTaskHuntingAction` em `ioprey.cpp:413` nunca é chamado); (2) o task system vivo é o `game_tasks` (ext 211 + 0xBC) — outra API; (3) stubs mantidos por compat ZB (retornam false); evento id 21 inativo. Aposentar/atualizar a memory.
- **Risco:** nenhum (texto/comentário).
- **Teste:** revisão de texto; conferir que os file:line batem (`game.lua:495-508/538/940`, `config.lua:185`, `tasks.lua:4-5`).

### Atualizar a documentação (wiki) do waypoint-script

- **Causa-raiz:** a wiki hoje documenta explicitamente Timer/HUD/`registerEvent`/`CustomModalWindow` como **não-funcionais** dentro de waypoints e o `storage` como ausente (`waypoint-script.md:116,166-176,212,356-363`) — o que deixa de valer após o PR da Fase 1.
- **Correção:** reescrever o bloco *caution* (`:166-176`): as 5 APIs agora funcionam; side-effects vivem enquanto o cavebot está ligado e caem ao desligar/relogar (modelo por-sessão). Documentar o **contrato de idempotência** (Timer seguro a cada passagem; HUD/Event/Modal com guarda `storage`) e a semântica síncrona do `pause(ms)`. Corrigir a linha 116 (`storage` agora é injetado). Ajustar `timer.md`/`hud.md`/`events.md`. Manter o aviso pedagógico: para monitoramento sempre-ligado, prefira a aba Scripting.
- **Risco:** sem risco de código. Escrever **depois** dos itens 1-5 da Fase 1. Docs vivem em `koliseu-aac` (WSL), não no servidor de jogo.
- **Teste:** cada afirmação da página deve casar com um teste dos itens da Fase 1; build do Docusaurus sem erro de link.

### Creature:getIcons (stopgap sem build)

- **Causa-raiz:** `creature.lua:191-196` retorna `{}` porque nenhum getter da **lista** de ícones está bindado. Mas o dado existe: `Creature::m_creatureIcons` = `vector<tuple<uint8 iconId, uint8 category, uint16 count>>` (`creature.h:241`), preenchido em `protocolgameparse.cpp:1776-1782` (0x8B) e `:4653-4662`. O getter `getCreatureIcons()` existe (`creature.h:119`) mas não está bindado; só `getIcon`/`hasCreatureIcon` (`luafunctions_client.cpp:628,646`) estão.
- **Correção (Fase 2, sem build):** *stopgap* de presença — implementar `getIcons` no shim enumerando `c:hasCreatureIcon(id, cat)` (já bindado) para `cat in {0,1}` e `id` nas faixas dos enums (`Enums.CreatureIcons`/`CreatureQuestIcons`), montando a lista. Perde o `count` (nível Fiendish) mas detecta Influenced/Fiendish/Hazard **hoje**, sem buildar. A versão completa (com `count`) é 1 binding C++ — ver Fase 3.
- **Risco:** stopgap é crash-safe (só leitura via binding existente).
- **Teste:** validar em um monstro Influenced/Fiendish (paridade com o gate de crippling do helper, `helper.lua:32548-32550`, que usa `hasCreatureIcon(1..3,1)`).

### Game.openDailyReward()

- **Causa-raiz:** stub em `game.lua:490-493`. O sender real existe: `dailyrewardprotocol.lua:224` instala `g_game.openDailyReward` (envia 0xD8 sem payload). A corelib instala um noop homônimo (`globals.lua:620`), então `type()=='function'` não distingue real vs noop — foi por isso que virou stub. Servidor: `daily_reward.lua` trata 0xD8 (`sendOpenRewardWall`).
- **Correção:** adicionar `dailyRewardModLoaded()` (espelhando `forgeModLoaded()`, `game.lua:328`); reescrever: `if not canAct() then return false end; if not dailyRewardModLoaded() then unsupported(...); return false end; g_game.openDailyReward(); return true`. Opcional: `modules.game_dailyreward.show()` para também abrir a janela.
- **Risco:** baixo (0xD8 sem payload, exercitado em produção pela UI).
- **Teste:** `Game.openDailyReward()` → a reward wall abre; com `game_dailyreward` descarregado → false + log.

### Game.collectDailyReward(isFromShrine, itemsToPick)

- **Causa-raiz:** stub em `game.lua:486-489`. Sender real: `dailyrewardprotocol.lua:202` `dailyRewardConfirm(panel, items)` envia 0xDA. Layout **confirmado** no servidor (`daily_reward.lua:426-471`): `[U8 target]` (0=shrine, 1=painel) e, só em dia de item, `[U8 columnsPicked]` + `columnsPicked×([U32 itemId][U8 count])`. É 1 opcode por mensagem (sem risco de desync). O comentário antigo superestimou o risco.
- **Correção:** gate `dailyRewardModLoaded()`; normalizar `itemsToPick` → mapa `{[itemId]=count}` (aceitar mapa, array de `{itemId=,count=}` ou pares); `nil`/vazio → 0 colunas (dias prey/xpboost); mapear target (`isFromShrine=true` → shrine); enviar `g_game.dailyRewardConfirm(not isFromShrine, items)`.
- **Risco:** médio-baixo — sem desync (1 opcode/mensagem); itens inválidos num dia de item → servidor recusa com `sendError` (sem crash). Atenção à robustez do normalizador.
- **Teste:** dia de item: `Game.collectDailyReward(true, {[itemId]=n})`; dia de prey/xpboost: `Game.collectDailyReward(false, nil)` coleta sem colunas.

### Game.getChannelsHistory()

- **Causa-raiz:** stub em `game.lua:152-155` (retorna `{}`). O engine não cacheia canais, mas há fonte fiel: os sinais `g_game.onOpenChannel(channelId, name[, participants])` e `onOpenPrivateChannel(name)`, emitidos pelo C++ (`game.cpp:396,401`) e já consumidos por `console.lua:472-481`.
- **Correção:** buffer module-level em `game.lua` (mesmo padrão do tracker `onEditText`, `game.lua:1045-1048`): `connect(g_game, { onOpenChannel = fn1, onOpenPrivateChannel = fn2 })`; `fn1` insere `{id,name}` (dedup por id), `fn2` insere `{id=nil,name}` (dedup por name); limpar em `onGameEnd`. `getChannelsHistory()` retorna cópia rasa.
- **Risco:** baixo (listener leve; sem alocação por frame). Único cuidado: limpar no `onGameEnd`.
- **Teste:** abrir alguns canais (World Chat, party, private), `Game.getChannelsHistory()` → lista `{id,name}`; relogar → lista zerada.

### Game.stashRetrieve(itemId, itemCount)

- **Causa-raiz:** já funciona, mas o gate é frágil: `game.lua:425-431` exige `stashOpened`, que só vira true com um handler de `OPEN_STASH` registrado E a stash aberta. O gate **real** do servidor é `parseStashWithdraw` → `isStashMenuAvailable()` (proximidade de depot), **não** que a janela esteja aberta. O cliente já tem essa fonte: `Player:isInStash()` (`player.lua:193`), populado pelo 0x2A (`stash.lua:153`).
- **Correção:** trocar o gate por (a) `stashModLoaded()` (garante que `stashWithdraw` é o sender real, não o noop) + (b) liberar se `isInStash()` OU `stashOpened` (mantém compat com quem já usa, mas deixa de **exigir** o handler). Manter `g_game.stashWithdraw(itemId, 0, itemCount or 1)`.
- **Risco:** baixo — `isInStash` reflete o gate exato do servidor; longe do depot ele recusa de qualquer jeito.
- **Teste:** perto do depot, **sem** registrar handler de OPEN_STASH: `Game.stashRetrieve(3031, 100)` deve enviar (hoje retorna false); longe do depot → false.

### setAlarm / isAlarmEnabled / allAlarmsEnable → sincronizar o checkbox

- **Causa-raiz:** o disparo do alarme lê o **checkbox ao vivo** via `isAlarmEnabled` file-local (`helper.lua:2865-2868` → `getAlarmCheckbox(id):isChecked()`, usos em `:3175,3200-3221,4660-4665`). O wrapper `Engine.setAlarm` (`engine.lua:468-476`) grava só `helperConfig.alarms[id]`; como o checkbox não é tocado, a mudança só vale quando a aba re-sincroniza os checkboxes a partir do config (`helper.lua:24961-24964`) — que pode nunca ocorrer na sessão → **desync e falha silenciosa** (alarme não toca apesar de `isAlarmEnabled=true`). Wiki `engine.md:316-325`.
- **Correção (A, recomendada, edita `helper.lua`):** adicionar `modules.game_helper.setAlarmChecked(id, enabled)` (chama `getAlarmCheckbox(id):setChecked(...)`, o que dispara `onAlarmCheckboxChange` → grava config + `updateAlarmSettings`), garantindo `helperConfig.alarms[id]=enabled` também (idempotência, pois `setChecked` só dispara se o estado mudar), e `saveSettings()`. E `setAllAlarmsChecked(enabled)` iterando os 9 ids. São **campos de tabela, não novos locais** (não afeta o limite de 200 locais). Delegar `engine.lua:468/479/496`. **Alternativa B (sem editar `helper.lua`):** o wrapper alcança o checkbox via `helper.contentPanel:recursiveGetChildById('alarmsPanel')` → `recursiveGetChildById(id):setChecked(...)`.
- **Risco:** baixo — só liga/desliga alarme (som/flash). Nota: por ser **falha silenciosa de uma feature de segurança**, pode ser promovido a `do-now-high` (ver Questões em aberto).
- **Teste:** `Engine.setAlarm('alarmLowHealth', true)` → checkbox marcado E alarme dispara ao cair a vida, **sem** reabrir a aba; `Engine.allAlarmsEnable(false)` desmarca todos.

### autoSSAEnable / isAutoSSAEnabled → Tank Mode amuleto (SSA 3081)

- **Causa-raiz:** os wrappers gravam campo **morto**: `engine.lua:211-213`/`client.lua:563-565` escrevem `helperConfig.autoSSA`; `autoSSA` **não aparece** em `helper.lua` (grep: 0 ocorrências). `ssaTankEnabled` só é escrito por um handler morto `onEnableSSATank` (`helper.lua:35679-35682`) que nenhum OTUI chama e é restaurado num checkbox **inexistente** (`enableSSATank`). O worker real é `checkTankMode` (`helper.lua:35788`), que reequipa `tankModeAmuletId` (`:35833`, default 3081=SSA) quando `tankModeAmuletEnabled~=false`, com `tankModeEnabled==true`. Wiki `engine.md:80-85,141-149`.
- **Correção (A, recomendada):** adicionar `modules.game_helper.setAutoSSAEnabled(enable)` (em `helper.lua`, perto de `:35687`): se `enable` → `tankModeAmuletId=3081; tankModeAmuletEnabled=true; if tankModeRingEnabled==nil then tankModeRingEnabled=false end` (evita ligar troca de anel não pedida); `onEnableTankMode(true)`; refresh de UI; `saveSettings()`. Se `disable` → `tankModeAmuletEnabled=false; if tankModeRingEnabled~=true then onEnableTankMode(false) end`. Delegar `Engine`/`Client.autoSSAEnable`. Redefinir `isAutoSSAEnabled` para o estado **real**: `tankModeEnabled and tankModeAmuletEnabled~=false and (id==3081 or id==3082)`.
- **Risco:** sem build/crash. Gameplay MÉDIO: ligar em combate reequipa o SSA no próximo tick (~100ms) — é o que "Auto SSA" promete. `onEnableTankMode` **não** salva sozinho, por isso `saveSettings()` no setter.
- **Teste:** `Client.autoSSAEnable(true)`; desequipar o amuleto → `checkTankMode` reequipa SSA em ≤100ms; conferir config e UI; `(false)` para de reequipar.

### autoMightRingEnable / isAutoMightRingEnabled → Tank Mode anel (Might Ring 3048)

- **Causa-raiz:** simétrico ao autoSSA. `engine.lua:216-218`/`client.lua:573-575` escrevem `helperConfig.mightRingEnabled`, só escrito pelo handler morto `onEnableMightRing` (`helper.lua:35684-35687`), restaurado num checkbox inexistente. Worker real `checkTankMode` reequipa `tankModeRingId` (`:35857`, default 3048) quando `tankModeRingEnabled~=false`. Há interação com `respectEnergyRing` (`:35867`), já tratada pelo worker.
- **Correção:** adicionar `setAutoMightRingEnabled(enable)` simétrico (`tankModeRingId=3048; tankModeRingEnabled=true; if tankModeAmuletEnabled==nil then tankModeAmuletEnabled=false end; onEnableTankMode(true)`); refresh + `saveSettings()`. Redefinir `isAutoMightRingEnabled` → `tankModeEnabled and tankModeRingEnabled~=false and tonumber(tankModeRingId)==3048`. **Fazer no mesmo commit do autoSSA** (mesma região de edição).
- **Risco:** sem build/crash. Gameplay MÉDIO: pode conflitar com `respectEnergyRing`/Energy Ring — mas `checkTankMode` já resolve a prioridade (`:35867-35882`).
- **Teste:** `Client.autoMightRingEnable(true)`; desequipar o anel → reequip em ≤100ms; com `respectEnergyRing` on + Energy Ring equipado, confirmar que **não** troca (prioridade do energy ring).

### translate.spellGroupToEngine/FromEngine + religar consultas de cooldown de grupo

- **Causa-raiz:** `Enums.SpellGroups` (`enums.lua:293-306`) copia os valores do ZB verbatim (GREATBEAMS=9, BURSTS=10, VIRTUE=11), mas o ledger `groupExpiry` é keyed pelo id do **servidor** (`spells.lua:94-98`, U8 cru de `onSpellGroupCooldown`, `protocolgameparse.cpp:2312`). O enum do servidor (`creatures_definitions.hpp:730-746`) tem `BURSTS_OF_NATURE=9`/`GREAT_BEAMS=10` (inverso do ZB) e `AOE_MS=11`/`ED_BURSTS=12`. `getLeftGroupCooldownTime`/`groupIsInCooldown` (`spells.lua:200-208`) usam o argumento **cru**, sem tradução. **Evidência:** grupos 9/10 do servidor **não** são usados por nenhuma magia (só support/attack/healing + secundários aoe_ms=11/ed_bursts=12), então o descasamento 9/10 é latente; o único wrong-read observável é `VIRTUE(11)` devolvendo o cooldown de AoE MS.
- **Correção:** (1) em `enums.lua` (junto dos outros translators, ~`:851`): `local SPELLGROUP_SWAP = { [9]=10, [10]=9 }; translate.spellGroupToEngine(zbGroup)` retorna `SWAP[zbGroup] or zbGroup`; `translate.spellGroupFromEngine = translate.spellGroupToEngine` (a troca 9↔10 é involução). (2) em `spells.lua`: file-local `toEngineGroup(groupId)` lê lazy `api.Enums.translate.spellGroupToEngine` com guarda; trocar `getLeftGroupCooldownTime` para `remaining(groupExpiry, toEngineGroup(groupId))`. Mapa ZB→ledger: 0..8 identidade; 9→10; 10→9; 11→11; 12→12. Follow-up docs: remover a caution "evite 9-11" em `enums.md:530-545`/`spells.md`.
- **Risco:** nenhum (Lua guardado). Impacto observável no server atual ~ zero (correção semântica + DX + blindagem futura). **Subir junto do item de dados abaixo.**
- **Teste:** imprimir `translate.spellGroupToEngine` para 8..12 (espera 8,10,9,11,12); ao vivo, como MS castar o trio AoE e checar `getLeftGroupCooldownTime(SPELLGROUP_VIRTUE=11) > 0`; como ED checar `getLeftGroupCooldownTime(12) > 0`.

### Corrigir chaves .group desatualizadas no SpellInfo

- **Causa-raiz:** o `SpellInfo` em `gamelib/spells.lua` carrega mapas `.group` por magia cujas chaves secundárias estão **erradas** vs o servidor ao vivo: `:253` Great Death Beam tem `[9]` mas o servidor faz `aoe_ms→11`; `:249/:250` Terra/Ice Burst têm `[10]` mas o servidor faz `ed_bursts→12`; `:406-408` Virtues têm `{[2],[11]}` mas o servidor faz `support→3`; `:295` Great Energy Beam tem `[9]` mas o servidor faz só `attack`. O ledger vivo é keyed por 11/12/3, então o padrão recomendado ("itere `spell.group`") lê chaves 9/10/11 que **nunca** aparecem no ledger → não detecta o cooldown do trio AoE/ED e classifica as virtudes na coluna errada. **Este é o wrong-read observável de verdade.**
- **Correção:** editar as 7 entradas para espelhar o servidor: Great Death Beam `[9]→[11]`; Terra/Ice Burst `[10]→[12]` (e cd 22000→6000, cosmético); Virtues `{[2],[11]}→{[3]=2000}` (support); Great Energy Beam remover `[9]` → `{[1]=2000}`. Opcional: adicionar `[11]` em Great Fire Wave e Energy Wave para o trio AoE MS inteiro expor o grupo. Os **valores** de cd em `.group` são cosméticos (o ledger usa a duração viva); o que importa são as **chaves**.
- **Risco:** baixo — `.group` é lido por `cast_timing.lua`, `t_spelllist.lua`, `actionbar.lua`, `magical_archive`; todos ficam mais corretos. A única mudança visível é as virtudes de Monk migrarem de Healing para Support (correto). `game_cooldown` **não** lê `SpellInfo.group` (é dirigido pelo evento do servidor), então os ícones de cooldown não são afetados.
- **Teste:** `getSpellByWords('exevo max mort').group` → `{1,11}`; `('exevo ulus tera').group` → `{1,12}`; `('utori virtu').group` → `{3}`; verificar a lista de magias (virtudes sob Support).

---

## Fase 3 — Requer recompilar o cliente (C++)

Todos exigem *rebuild* (DirectX x64), que **fica com o usuário** (regra *dont-recompile-client-leave-to-user*). Sempre que houver um build por outro motivo, agrupar estes bindings para pegar carona.

### Creature:getIcons — versão completa (com count/nível Fiendish)

- **Correção:** 1 binding em `luafunctions_client.cpp` após `:646`: `g_lua.bindClassMemberFunction<Creature>("getCreatureIcons", &Creature::getCreatureIcons);` (o push de `vector<tuple<uint8,uint8,uint16>>` já funciona por `luavaluecasts.h`). No shim `creature.lua`, remapear cada tupla para `{ id=t[1], category=t[2], count=t[3] }`. Fallback de fidelidade se o push de `tuple<uint8>` der ruim: método `getIconsForLua()` retornando `vector<tuple<int,int,int>>`.
- **Prioridade:** `do-soon-medium`. O *stopgap* sem build (Fase 2) já cobre presença; esta versão acrescenta o `count`.
- **Teste (pós-build):** `Creature(id):getIcons()` num Fiendish → `{id=5,category=1,count>0}`.

### Client.getAllMonsters / getMonsterByRaceId — isBoss

- **Causa-raiz:** a tupla estática de `getMonsterList()` tem 8 campos (name/lookType/…/addons, `creatures.cpp:191,200`) e o enum `CreatureRace` só tem Npc/Monster — sem Boss. Mas a *boss-ness* é conhecida no load: `loadStaticData` lê uma lista **separada** `bosses` (`staticdata.proto:15`) e chama `addEntry` (`creatures.cpp:262-263`), mas a origem é descartada. Log de boot já conta bosses (`:279-280`).
- **Correção:** (1) `creatures.h`: `CreatureAttrIsBoss=7` + `setBoss`/`isBoss` no `CreatureType`; alargar o retorno de `getMonsterList` para 9 ints (**append-only**). (2) `creatures.cpp`: `addEntry` recebe `bool isBoss` (`:260-261` false, `:262-263` true) e o `make_tuple` acrescenta o 9º elemento. (3) `client.lua:494-515`: `isBoss = (tuple[9]==1)`. Aridade append-only → consumidores existentes (`background.lua`, `mpodium.lua`, cyclopedia/bestiary/bosstiary, `prey.lua`, `tasks.lua`) não quebram. **Alternativa rejeitada:** cruzar com o bosstiary vivo (0x73) — pacotes consumidos-e-descartados e só cobrem o set rastreado; `staticdata` é completo/autoritativo.
- **Prioridade:** `do-soon-medium`. **Dependência de dado:** o `staticdata.dat` empacotado precisa ter a lista `bosses` populada.
- **Teste:** conferir o log de boot `Loaded X monsters, Y bosses…` (`creatures.cpp:279`) — se Y>0 o dado está presente. Pós-build: `getMonsterByRaceId(<boss>).isBoss` true; monstro comum false.

### Creature:getOutfit — cores de montaria (mountHead/Legs/Feet)

- **Causa-raiz:** o engine **lê e joga fora** os 4 bytes de cor da montaria (`protocolgameparse.cpp:4484-4499`, e no bloco de podium `:4806-4810`). A classe `Outfit` não tem membros de cor por montaria. Por isso `creature.lua:167-169`/`client.lua:504-507` fixam 0. **O dado está na wire.**
- **Correção:** `outfit.h`: `m_mountHead/Body/Legs/Feet` + getters/setters; em `getOutfit` (`:4489-4492`) e no podium, armazenar os bytes; `luavaluecasts_client.cpp` push dentro do `if getFeature(GamePlayerMounts)`; `creature.lua:167-169` mapear.
- **Prioridade:** `do-later-low` — cosmético, sem consumidor conhecido. Provável *wont-fix* (os campos já existem como 0 para compat de shape ZB). É um patch limpo se um build acontecer.
- **Teste:** montar um jogador com montaria tingida e ler `getOutfit().mountHead/Legs/Feet`.

### Game.getItemCount(itemId, itemTier) — tier ignorado

- **Causa-raiz:** `game.lua:188-192` chama `getInventoryCount(itemId)` sem tier; `localplayer.cpp:719` **ignora** o 2º arg. O tier existe no wire do 0xF5 (`protocolgameparse.cpp:3145` lê `getU8() // tier` e **descarta**); a agregação é só por itemId (`m_inventoryItemsCount`). É limite de **dados no cliente**, não do servidor.
- **Correção:** (1) `protocolgameparse.cpp`: agregar `map<int, map<int,int>>` (itemId→tier→count); (2) `localplayer`: `getInventoryCount(itemId, tier)` com `tier<0/nil` = soma todos (compat com callers atuais, ex.: action bar); (3) `game.lua`: repassar `itemTier`. Wire inalterado.
- **Prioridade:** `do-later-low` — demanda baixa (potions/runes/gold não têm tier). Só vale um recompile se algum script realmente precisar contar por tier; senão manter documentado como limite (`game.md:157-159`).
- **Teste:** com itens forjados de tiers distintos, `Game.getItemCount(id, 1)` deve diferir de `Game.getItemCount(id)` (total).

### HUD:setScale em sprite e item

- **Causa-raiz:** `hud.lua:364-369` chama `setScale` em `_sprite`/`_outfit`. Só `UICreature` tem escala real (`uicreature.cpp:53`, binding `luafunctions_client.cpp:1087`) — a HUD de **outfit já funciona**. `UISprite`/`UIItem` não têm `m_scale`/`setScale`; a chamada é engolida pelo `pcall` → no-op. Ambos já escalam com o **tamanho** do widget (`getPaddingRect`).
- **Correção (C++ mínimo, espelha UICreature):** `float m_scale=1.0` + `setScale`/`getScale` em `uisprite.h`/`uiitem.h`; no `drawSelf` escalar o dest a partir do topLeft (`Rect(r.topLeft(), r.size()*m_scale)`); bindar `setScale` em `luafunctions_client.cpp` (após `:1072` UISprite e `:1064` UIItem). A chamada `hud.lua:366` passa a funcionar sem editar o Lua. **Alternativa sem build (mais frágil):** reescrever `ensureSprite`/`iconItem` para ancorar center + size próprio e `setScale` mudar o size do filho (risco de sobreposição com a legenda + dupla escala do outfit).
- **Prioridade:** `do-later-low` — o caso visual principal (outfit) já escala; sprite/item raramente precisam (dá pra usar `setSize`).
- **Teste (pós-build):** `HUD.newSpellIcon(60,60,1):setScale(2)` e `HUD.new(60,120,3031):setScale(1.5)` devem crescer; comparar com `HUD.newOutfit(80,80,128):setScale(2)`.

### Client.sendHotkey (injeção de tecla sintética)

- **Causa-raiz:** `client.lua:299` stub. Não há binding de injeção: `g_window` só expõe `isKeyPressed`/`releaseKey`/`getKeyboardModifiers` (`luafunctions.cpp:383-385`). Os métodos que sintetizam tecla existem em C++ (`platformwindow.h:114-117`) mas são **protected**. O caminho "wire ao sistema de hotkeys" é frágil (General Hotkeys desabilitadas, `keybind.lua:93-96`; Custom Hotkeys sem API estável).
- **Correção:** binding C++ novo (rejeitar o wire ao hotkey system). (1) método público em `platformwindow.h/.cpp` (`fakeKeyPress(Fw::Key k){ processKeyDown(k); processKeyUp(k); }`, ou InputEvent completo para honrar modificadores); (2) bindar em `luafunctions.cpp:385`; (3) em `client.lua`, traduzir via `Client._toFwKey` (`:248-262`) e chamar. Header core → rebuild longo.
- **Prioridade:** `do-later-low` — semanticamente redundante (a doc já orienta usar `Game.talk`/`Game.useItem`/`Spells`; movimento via `Game.walk`/`turn`). Valor baixo — só ganha um script ZB que dependa literalmente de `sendHotkey`.
- **Teste (pós-build):** bindar F1 = uma magia; `Client.sendHotkey('F1')` → a magia dispara; testar modificador `Ctrl+F1`.

---

## Requer mudança no servidor

Um único item. **Não** é C++ — é um *talkaction* RevScriptSys auto-load.

### Game.autoLoot()

- **Causa-raiz:** stub em `game.lua:386-389`. **Não** existe sender/opcode de toggle no cliente (autoLoot nem está em `gameNoops`). O servidor tem auto-loot **nativo**: `player.cpp:7174 checkAutoLoot()` lê o KV `features.autoloot` (0=off, 1=on exceto boss, 2=on tudo); aplicado no death (`creature.cpp:889`). O **único** toggle é o modal `!settings` (`settings.lua:16` `player:setFeature(Features.AutoLoot, ...)`) — assíncrono, índices variáveis, frágil para mapear. A semântica ZB (automação client-side de walk-to-corpse) também não bate com o auto-loot server-side nativo.
- **Cliente:** `Game.autoLoot()` → `if not canAct() then return false end; g_game.talk('!autoloot'); return true` (1 linha). Documentar na wiki que no KoliseuOT isto **alterna o auto-loot server-side** (diferente do ZB).
- **Servidor:** adicionar `data/scripts/talkactions/player/autoloot.lua` (~20 linhas, sem C++, só `/reload talkactions`): ler `player:getFeature(Features.AutoLoot)`, alternar 0↔1 (ou aceitar `on`/`off`/`boss` → 0/1/2), `player:setFeature(...)`, respeitar `checkEnabled(AUTOLOOT)` e `checkVip(VIP_AUTOLOOT_VIP_ONLY)`, `sendTextMessage` de feedback. Respeitar GUARDRAILS: English-only, não nomear `config.lua`.
- **Protocolo/esforço:** sem opcode novo (usa `g_game.talk`). Servidor: talkaction isolado, fora de hot path, sem build. Esforço **S** total.
- **Alternativa:** aceitar *wont-fix* — o auto-loot nativo + `!settings` já cobrem. É decisão do dono (ver Questões em aberto).
- **Teste:** criar `autoloot.lua`, `/reload talkactions`; `Game.autoLoot()`; matar um mob e ver se lootou; conferir o status em `!settings`.

---

## Decisões de produto / Não-fazer

Escolhas **conscientes**, não bugs. Os stubs permanecem honestos (retornam false/`{}`/nil), preservando compat com scripts ZB portados e a numeração exata dos event ids.

### Hunting Tasks — `Game.huntingTask*` (6 ações) + evento `TASK_HUNTING_DATA` (id 21)

Os 6 `huntingTask*` e o evento são stubs honestos e **nada no cliente os chama** (grep de call-sites vazio). A API ZB mira o **Task Hunting legado** prey-adjacent (dados 0xBB + `PreyAction_t`): o handler de ações no servidor (`IOPrey::parseTaskHuntingAction`, `ioprey.cpp:413`) está **órfão** (nenhum opcode recv o alcança); o cliente não tem send binding, faz *parse-and-discard* do 0xBB (`protocolgameparse.cpp:4157`), e não tem UI (`game_prey_hunting` removido). O task system **real** do KoliseuOT é outro — `game_tasks` via ext opcode 211 + 0xBC. Re-mapear os stubs ressuscitaria um protocolo vestigial que **duplica** o sistema vivo, com semântica incompatível, custo XL e alto risco de protocolo. **Manter stubs + só corrigir a documentação enganosa** (item na Fase 2).

### Client.login (login por credenciais no sandbox)

O ciclo de vida do sandbox torna a chamada **infabricável**: scripts só rodam ON login e param no offline; in-game a chamada é bloqueada (`entergame.lua:818-822`), e após logout o script já morreu. Some-se a incompatibilidade de assinatura (ZB `email,password,characterIndex` não carrega host/token/char) e a dependência da UI de login. Necessidade real já coberta por AUTO_LOGIN + auto-reconnect. Meio-implementar é **pior** (loginWorld com args faltando dessincroniza a sessão).

### Anti-Push (`antiPushEnable`/`setFirst/SecondAntiPushId`…)

Feature 100% nova — `antiPush` só aparece nos próprios stubs (grep). Um worker que emita `walk` pode **brigar com cavebot/auto-follow** (dois donos do walker). Custo L, benefício nicho: Koliseu é PvE de hunt (cavebot/shooter já andam por você); anti-push é feature PvP/multidão pouco usada aqui.

### Rune Max (`runeMaxEnable`/`get/setRuneMaxId`…)

Feature nova (`runeMax`/`conjureRune` inexistente no helper). Castar conjuração em loop competiria com o cast arbiter do shooter/healing. Benefício nicho de mage rune-maker; o meta de Koliseu compra supply/usa shooter, não conjura. Custo M.

### getUserId / getLicenseTime / loadConfig

Não existe sistema de licença/identidade no projeto (o HWID anti-multibox não expõe user id ao Lua) → `getUserId`/`getLicenseTime` mantêm stub (`''`/`nil`). `loadConfig`: aplicar um profile completo por nome via script é arriscado (troca o `helperConfig` inteiro, re-render, save) e já existe o auto-load por personagem → manter stub (`false`).

### Alternativas rejeitadas no `npc-trade-itemid`

- **Popular OTB/itemType no boot:** neste fork o id na wire **é** o client/appearance id — não há espaço de server-id separado. Fabricar `m_itemTypes`/serverId não mapeia para nada real, exigiria mexer no boot C++/recompilar, com risco de crash/atlas e **zero ganho** — o fix em Lua resolve.
- **Binding C++ `g_things.isValidDatId`:** seria só cosmético; o resultado é idêntico ao idiom `Item.create(id):getId()==0` (ambos batem em `ThingTypeManager::isValidDatId` internamente). Só valeria de carona num rebuild já em andamento.

### CaveBot sell list / end-lure

- **Sell list (`get/setSellList`):** não há data model no cavebot Amon; venda de loot é feature **separada** ("Loot Seller", ext opcode 207 / KV `lootseller.blacklist`). Implementar de verdade significa inventar storage + UI. Um alias para a blacklist **global** trocaria silenciosamente a semântica por-cavebot do ZB → não recomendado.
- **End-lure (`set/getEndLureSettings`):** o motor de lure do Amon é dirigido por chaves de Config planas, não pela máquina de 9 estados do end-lure ZB. Portar mexeria no **hot loop de lure** (risco de regressão num comportamento central de hunt), e nenhuma rota/UI produz esses params. Custo XL.

> **Nota sobre "hold target":** apesar de superficialmente parecer um stub PvP, a auditoria concluiu que ele mapeia 1:1 para o **Hold Attack** que já existe no helper — por isso foi para a **Fase 1** (do-now-high), e **não** é não-fazer.

---

## Roadmap sugerido

**Onda 1 — Os wires triviais (máxima cobertura por menor custo).**
Fechar tudo que é "ligar o fio no lugar certo", puro Lua, sem build: os 3 WIRE de Engine/Client (`showMessage`, `reconnectEnable`, `holdTargetEnable`), o **stow trio**, `Npc.buy`/`Npc.sell`, `Player.getDustsMaximum` e `Engine.enableCaveBot`. Justificativa: cada um reaproveita código já provado pela UI; risco baixíssimo; ganho imediato e visível para bots.

**Onda 2 — Waypoint-script exec context (PR único) + CaveBot saveFile/LABEL.**
Aterrissar o "script-record sintético" (5 itens da Fase 1) que des-quebra Timer/HUD/eventos/modal e **remove o hazard do cavebot congelado no `pause(ms)`**, mais `CaveBot.saveFile` (1 linha + rewire) e o evento `LABEL`. Justificativa: é o maior salto de capacidade do grupo; `saveFile` desbloqueia a persistência do CRUD (Onda 4).

**Onda 3 — Protocolo/estado que já está no cliente (Fase 2, sem build).**
Daily reward (`open`/`collect`), `getChannelsHistory`, `stashRetrieve` (gate `isInStash`), os toggles inertes que faltam (`setAlarm`, `autoSSA`, `autoMightRing`), o par de imbuement (`pickItemImbuement`), e a correção de spell groups (translate + chaves `.group`). Justificativa: senders/sinais/workers já existem; fecha a maior parte dos stubs restantes; considerar **promover `setAlarm`** (falha silenciosa de feature de segurança).

**Onda 4 — CaveBot Fase 2 pesada + stopgap getIcons + docs.**
CRUD de waypoints → persistência (Opção B lossless, depende do `saveFile` da Onda 2), o *stopgap* de `getIcons` via `hasCreatureIcon`, e a atualização da wiki (waypoint-script + Hunting Tasks). Justificativa: valor real mas esforço L; docs devem vir **depois** do comportamento aterrissar.

**Onda 5 — Build C++ agrupado (Fase 3).**
Quando o usuário for recompilar (por qualquer motivo), pegar carona com **todos** os bindings de uma vez: `getCreatureIcons` (getIcons completo com count), `isBoss` (9º campo append-only), e — se valerem — `getItemCount` por tier, `setScale` sprite/item, cores de montaria e `sendHotkey`. Justificativa: agrupar minimiza o número de rebuilds longos; `isBoss` e `getIcons` completo têm a maior prioridade dentre os C++.

**Onda 6 — Servidor (talkaction) + baixa prioridade.**
Se o dono aprovar, o *talkaction* `!autoloot` (`Game.autoLoot`). Junto, os `do-later-low` sem build que sobraram (Npc read-helpers, id estável de waypoint, `writeTextWindow`, aliases de SpellGroups, `HUD:setFontSize`, comentário de `getXpBoostTime`). Justificativa: polimento/paridade de baixa demanda; ficam por último por escolha.

---

## Questões em aberto

Consolidadas dos 11 grupos (as mais relevantes para decisão):

**Semântica / contrato de API:**

- **`Container:stowAllItems`:** mapear para `STOW_STACK=2` ("todos do tipo", recomendado, particiona limpo com `Inventory.stowContainer`=`STOW_CONTAINER`) ou "esvaziar o container inteiro"?
- **Gate `isInStash` nas funções de stow:** incluir (retorno false honesto quando o servidor recusaria; espelha a UI) ou só enviar e deixar o servidor dropar? Recomendado **incluir** (barato e fiel). O gate obrigatório é `game_stash` carregado.
- **`Npc.buy`/`Npc.sell` sem shop aberto:** o fallback envia mesmo assim (servidor no-opa, retorna true fire-and-forget, fiel ao ZB) ou retornar false checando `isTradeOpen()`? Definir o comportamento oficial.
- **`holdTarget` × `autoTarget`:** manter mutuamente exclusivo (fiel ao helper) ou fazer `holdTargetEnable(true)` também desligar `autoTarget` (mais próximo da intenção ZB)?
- **`storage` no waypoint-script:** persistir entre **voltas** do cavebot (paridade com a aba Scripting) e zerar ao desligar — confirmar que é o desejado (um usuário pode esperar que zere a cada passagem).
- **`getDustsMaximum`:** retornar `maxPlayerDust` (limite pessoal atual, recomendado — denominador de `getDusts`) ou `maxDust` (teto absoluto, ex.: 225)?
- **Shape de `getIcons`:** lista de records `{id,category,count}` (superset, preserva o count/Fiendish-level) ou array plano de ids para paridade estrita ZB?

**Modelo de execução / ciclo de vida:**

- **Erros de snippet:** Option A (nunca auto-desabilita; erros de callback só logados, recomendado no 1º PR) ou Option B (auto-disable async após 5 erros)?
- **Identidade do record:** índice do waypoint (simples, estável enquanto o cavebot roda) vs referência da action-table com weak-keys (robusta a shifts em runtime)? Recomendado índice.
- **LABEL auto-pause:** adotar a auto-pause opcional gated-por-listener (mais fiel ao ZB, com footgun de travar a hunt) ou deixar 100% dirigido por script? Decisão de produto.
- **`CaveBot.loadFile`:** manter a semântica de **swap** (troca o perfil inteiro e desliga o cavebot, mais seguro) ou adicionar a variante ZB-merge de waypoints?
- **Persistência do CRUD:** Opção B (lossless, tocar cada wrapper) vs Opção A (inverse-serialize no `saveFile`, lossy p/ posição de goto/label)? Recomendado B.
- **`enableCaveBot`:** confirmar que o novo contrato de retorno (reflete o desfecho real, pode ser false quando recusado) é aceitável vs o boolean "gravou" de hoje.

**Toggles de Tank Mode:**

- **Acoplamento autoSSA↔autoMightRing:** independência (ao ligar um, fixar o irmão `nil→false`, recomendado) ou ligar um liga o Tank Mode inteiro?
- **Forçar ids:** `autoSSAEnable(true)` deve forçar `tankModeAmuletId=3081` mesmo se o usuário escolheu outro amuleto de tank na UI (semântica ZB diz que sim, mas sobrescreve a escolha manual)? Idem Might Ring=3048.
- **Redefinir `isAutoSSA`/`isAutoMightRing`** para refletir o estado real do Tank Mode muda o valor retornado vs hoje (que lê flag inerte) — confirmar que é aceitável.
- **`setAlarm`:** promover de `do-soon-medium` para `do-now-high` por ser falha silenciosa de uma feature de segurança?
- **Estratégia de implementação (alarmes/tank):** setters públicos em `modules.game_helper` (edita `helper.lua`, uma fonte de verdade, recomendado) vs wrapper-only alcançando a UI por globais (não edita `helper.lua`, mas duplica lógica)?

**Servidor / protocolo:**

- **`Game.autoLoot`:** adicionar o *talkaction* `!autoloot` (dá utilidade real, custo trivial) ou aceitar *wont-fix* (o auto-loot nativo + `!settings` já cobrem)? A semântica diverge do ZB de qualquer forma.
- **`getItemCount` por tier:** vale um recompile? Demanda tende a ser baixa (itens contáveis típicos não têm tier).
- **Task system real:** scripters precisam de acesso programático ao `game_tasks` (ext 211)? Se sim, o design correto é uma API KoliseuOT-native separada (ex.: expor `CommandBridge.getState().tasks`), **não** forçar a semântica ZB `huntingTask*`.
- **Tráfego 0xBB vestigial:** considerar `taskHuntingSystemEnabled=false` para parar o 0xBB inútil (opcional, escopo servidor).

**HUD:**

- **`setFontSize`:** que faixa de tamanhos os scripts ZB pedem (define o clamp e se vale o híbrido `verdana-Npx-rounded`<=11 com contorno vs `verdanab.ttf@N` smooth acima)? É aceitável texto anti-aliased sem contorno preto (menos legível sobre sprites claros)?
- **`setScale` sprite/item:** vale recompilar só por isso, ou o outfit (que já escala) + `setSize` dos filhos cobrem as necessidades reais?
