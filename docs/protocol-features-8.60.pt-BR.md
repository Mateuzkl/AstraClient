# AstraClient 8.60 protocol features

Este guia separa as features usadas pelo AstraClient das features usadas pelo OTCv8 Classic.

O objetivo e evitar bug de protocolo causado por ligar `g_game.enableFeature(...)` sem o servidor mandar os bytes esperados.

## Arquivos importantes

- `modules/game_features/features.lua`: features padrao por versao do client.
- `modules/gamelib/const.lua`: ids das features no Lua.
- `src/client/const.h`: ids das features no C++.
- `src/client/protocolgameparse.cpp`: parser de pacotes e `parseFeatures`.
- `modules/client_entergame/entergame.lua`: features recebidas via login HTTP e `server_params`.

No server, a referencia principal e `ProtocolGame::sendFeatures()` em `src/protocolgame.cpp`.

## Regra principal

Nem toda feature e apenas visual.

Algumas features mudam o tamanho ou a ordem dos pacotes. Se o client habilita uma dessas features e o server nao envia os bytes extras, o parser sai de alinhamento.

Sintomas comuns:

- item aparece com ID errado;
- container abre quebrado;
- map fica preto ou com tiles errados;
- erro de opcode desconhecido;
- look/use para de funcionar;
- crash ou disconnect ao abrir backpack, loot, corpo ou store inbox.

## Como o Astra habilita features

O Astra usa um perfil direto para `version == 860` em `modules/game_features/features.lua`.

Ele reseta todas as features com `g_game.resetFeatures()` e depois habilita apenas o conjunto esperado para o Astra 8.60.

Tambem existem features que podem vir do server:

- login HTTP: campo `features`;
- game packet `GameServerFeatures` (`0x43`), lido por `parseFeatures`;
- `server_params` no `init.lua`, que o Astra tambem pode usar para habilitar features extras.

Use `server_params` apenas para features seguras. Nao use esse caminho para feature que muda pacote de item/mapa/container.

## Astra 8.60: features base

Estas features sao habilitadas para o Astra 8.60 porque fazem parte do protocolo/base esperada:

```lua
GameLooktypeU16
GameMessageStatements
GameLoginPacketEncryption
GamePlayerAddons
GamePlayerStamina
GameNewFluids
GameMessageLevel
GamePlayerStateU16
GameNewOutfitProtocol
GameWritableDate
GameProtocolChecksum
GameAccountNames
GameDoubleFreeCapacity
GameChallengeOnLogin
GameMessageSizeCheck
GameTileAddThingWithStackpos
GameCreatureEmblems
```

## Astra 8.60: extensoes habilitadas no client

Estas estao hardcoded no Astra 8.60:

```lua
GameAttackSeq
GameBot
GameExtendedOpcode
GameSkillsBase
GamePlayerMounts
GameMagicEffectU16
GameDistanceEffectU16
GameDoubleHealth
GameOfflineTrainingTime
GameBaseSkillU16
GameAdditionalSkills
GameIdleAnimations
GameEnhancedAnimations
GameExtendedClientPing
GameSpritesU32
GameDoublePlayerGoodsMoney
GameCreatureIcons
GameColorizedLootValue
GameBrowseField
GamePlayerFamiliars
GameProficiency
GameUnjustifiedPoints
GamePrey
```

Observacoes:

- `GameSpritesU32` precisa bater com os assets estendidos (`.spr`) usados pelo client.
- `GamePlayerFamiliars` altera dados de outfit no Astra; nao copie isso para o OTC Classic sem suporte no parser.
- `GameColorizedLootValue` e uma feature do Astra, nao existe no OTC Classic desta branch.
- `GameProficiency` existe como feature no client, mas so deve ser mantida se o server tambem estiver alinhado com os pacotes usados por ela.

## Features negociadas pelo server

O server pode enviar features pelo packet `0x43` (`GameServerFeatures`). O Astra tambem aceita features pelo login HTTP.

No server atual, `sendFeatures()` envia, entre outras:

```cpp
ExtendedOpcode = true
SkillsBase = true
PlayerMounts = true
MagicEffectU16 = true
OfflineTrainingTime = true
DoubleSkills = true
BaseSkillU16 = true
AdditionalSkills = true
ExtendedClientPing = true
CreatureIcons = true
ContainerPagination = true
BrowseField = true
QuickLootFlags = shouldSendQuickLootFlags()
ThingUpgradeClassification = false
ItemTierByte = shouldSendItemTierByte()
```

Quando o client e Astra, o server tambem pode enviar:

```cpp
ExperienceBonus = true
PlayerFamiliars = true
AstraCreatureIcons = true
AstraQuiverCountU16 = true
AstraOutfitStoreMode = true
DisplayItemDuration = true
DisplayItemCharges = true
PackedPlayerInventory = true
AstraItemMetadata = true
```

Essas features precisam combinar com o parser do Astra. Nao copie as flags `Astra*` para o OTC Classic.

## Features perigosas

Estas tres sao as mais comuns de causar bug de protocolo:

```lua
GameQuickLootFlags              -- id 123
GameThingUpgradeClassification  -- id 130
GameItemTierByte                -- id 131
```

Nao troque `disableFeature` por `enableFeature` nelas sem alterar o server junto.

### GameQuickLootFlags

Muda leitura/escrita de flags de quick loot em itens/containers. Se o client espera a flag e o server nao envia, o proximo byte do pacote vira lixo para o parser.

### GameThingUpgradeClassification

Muda leitura de classificacao/tier em item. No server atual, essa feature e enviada como `false` para OTCv8/Astra.

### GameItemTierByte

Muda leitura de tier com um byte extra. So deve ficar ativa quando `shouldSendItemTierByte()` no server tambem estiver ativo.

## Diferencas para OTCv8 Classic

O OTCv8 Classic desta branch usa regras por faixas de versao (`if version >= 770`, `>= 780`, `>= 860`, etc.).

No bloco `version >= 860`, o OTC Classic habilita principalmente:

```lua
GameAttackSeq
GameBot
GameExtendedOpcode
GameSkillsBase
GamePlayerMounts
GameMagicEffectU16
GameDistanceEffectU16
GameDoubleHealth
GameOfflineTrainingTime
GameBaseSkillU16
GameAdditionalSkills
GameIdleAnimations
GameEnhancedAnimations
GameExtendedClientPing
GameSpritesU32
GameDoublePlayerGoodsMoney
GameCreatureIcons
GamePurseSlot
GamePrey
```

E deixa explicito que estas ficam desligadas por padrao:

```lua
g_game.disableFeature(GameQuickLootFlags)
g_game.disableFeature(GameThingUpgradeClassification)
g_game.disableFeature(GameItemTierByte)
```

O Astra nao e uma copia direta desse bloco. O Astra 8.60 tem features proprias e parser proprio para algumas extensoes.

## Checklist antes de mexer em feature

- [ ] A feature e so visual/UI ou muda pacote de rede?
- [ ] O id existe em `modules/gamelib/const.lua` e `src/client/const.h`?
- [ ] O server envia a mesma feature em `sendFeatures()` ou login HTTP?
- [ ] Se muda item, conferi `getItem`, `addItem`, container, map e inventory?
- [ ] Se muda creature/outfit, conferi outfit window, creature icons e login?
- [ ] Testei login, walk, look, use, open backpack, corpse, store inbox e logout?
- [ ] Testei com a feature `false` e `true` quando ela e negociada?

## Regra pratica

Para o Astra 8.60:

- feature comum e estavel do perfil Astra pode ficar em `modules/game_features/features.lua`;
- feature que muda pacote deve vir do server por handshake;
- feature Astra-only nao deve ser copiada para OTC Classic;
- `GameQuickLootFlags`, `GameThingUpgradeClassification` e `GameItemTierByte` devem seguir o server, nao a vontade do client.
