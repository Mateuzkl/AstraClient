# Passos manuais após a implementação da API de Scripting

As Ondas A/B implementaram a maior parte do plano. **A Onda A (Lua) já está ativa** ao recarregar o Helper. Faltam três passos manuais seus (build do cliente, reload do servidor, e a religação Lua pós-build), abaixo.

## 1. Servidor — recarregar talkactions (para `Game.autoLoot`)

Foi criado o talkaction `!autoloot` em `data/scripts/talkactions/player/autoloot.lua` (no servidor WSL `/home/joao/koliseuot`), amarrado ao auto-loot **nativo** do servidor (`Features.AutoLoot`, lido por `Player::checkAutoLoot`). O cliente `Game.autoLoot()` envia `!autoloot`.

No servidor, rode:

```
/reload talkactions
```

(ou reinicie o servidor). Até isso, `!autoloot` só apareceria como chat normal — inofensivo.

## 2. Cliente — recompilar (para os bindings C++)

A Onda B escreveu (mas **não compilou** — build é seu) bindings C++ em `src/client/`. Recompile o cliente para ativá-los:

- `Client.getAllMonsters()/getMonsterByRaceId()` — campo `isBoss` real (9º campo, append-only). Depende de `staticdata.dat` ter a lista de `bosses` populada (cheque o log de boot: `Loaded X monsters, Y bosses`).
- `Creature:getCreatureIcons()` — lista real de ícones (id/category/count), incl. nível Fiendish.
- `Creature:getOutfit()` — cores de montaria reais (`mountHead/Body/Legs/Feet`).
- `Game.getItemCount(id, tier)` — contagem segmentada por tier (mapa paralelo do 0xF5).
- `HUD:setScale()` em sprite/item — passa a escalar (já era chamado pelo `hud.lua`).

Nenhuma assinatura existente foi alterada (tudo append-only); o revisor verificou alta plausibilidade de compilar. `Client.sendHotkey` ficou **deferido** (o método de injeção de tecla é `protected` num header do core; redundante com `Game.talk`/`useItem`/`Spells`).

Observação: os arquivos `src/client/*` já tinham mudanças suas não-commitadas (packet-governor, HWID); as da Onda B são aditivas por cima.

## 3. Cliente — religar os consumidores Lua APÓS o build

Estes ajustes de **uma linha** trocam os stopgaps pelos bindings C++ reais. Aplique-os **só depois** de compilar (antes do build, chamariam funções ainda inexistentes):

1. `mods/game_helper/scripting/api/client.lua` — `monsterRecord()` (~L518): trocar `isBoss = false` por `isBoss = (tuple[9] == 1)`.
2. `mods/game_helper/scripting/api/creature.lua` — `getIcons` (~L190): trocar o stopgap por
   `local out={}; for _,t in ipairs(c:getCreatureIcons() or {}) do out[#out+1]={id=t[1],category=t[2],count=t[3]} end; return out`.
3. `mods/game_helper/scripting/api/creature.lua` `getOutfit` (~L167) e `client.lua` (~L504): ler `outfit.mountHead/mountBody/mountLegs/mountFeet` em vez de fixar `0` (o record de `getMonsterList` em `monsterRecord` continua `0` — staticdata não carrega cor de montaria).
4. `mods/game_helper/scripting/api/game.lua` — `Game.getItemCount` (~L188): passar o tier, `getInventoryCount(itemId, itemTier)`.
5. `setScale` (sprite/item): **nenhum** ajuste Lua — `hud.lua` já chama `:setScale()`; passa a valer sozinho após o build.

Posso aplicar esses 5 ajustes num passo único quando você confirmar que buildou.
