# AstraClient 8.60 Protocol Features

This document explains the 8.60 feature flags used by AstraClient and how they differ from OTCv8 Classic.

PT-BR version: `docs/protocol-features-8.60.pt-BR.md`

Read this before changing any `g_game.enableFeature(...)` or `g_game.disableFeature(...)` call. Some flags are visual, but others change packet layout. Enabling the wrong flag can desync the protocol parser.

## Important Files

- `modules/game_features/features.lua`: default feature profile by client version.
- `modules/gamelib/const.lua`: Lua feature ids.
- `src/client/const.h`: C++ feature ids.
- `src/client/protocolgameparse.cpp`: packet parser and `parseFeatures`.
- `modules/client_entergame/entergame.lua`: features received from HTTP login and `server_params`.

On the server side, the main reference is `ProtocolGame::sendFeatures()` in `src/protocolgame.cpp`.

## Main Rule

Not every feature is just UI.

Some features change packet size or packet field order. If the client enables one of those features and the server does not send the matching extra bytes, the next fields are read from the wrong offset.

Common symptoms:

- wrong item ids;
- broken containers;
- black map or wrong tiles;
- unknown opcode errors;
- look/use stops working;
- crash or disconnect when opening backpacks, corpses, loot, or store inbox.

## How Astra Enables Features

AstraClient uses a direct `version == 860` profile in `modules/game_features/features.lua`.

The client calls `g_game.resetFeatures()` and then enables only the expected Astra 8.60 feature set.

Features can also be negotiated by the server:

- HTTP login `features` field;
- game packet `GameServerFeatures` (`0x43`), parsed by `parseFeatures`;
- `server_params` in `init.lua`, which Astra can use to enable extra features.

Use `server_params` only for safe features. Do not use it for item/map/container packet-layout features.

## Astra 8.60 Base Features

These are enabled because they are part of the expected Astra 8.60 base protocol:

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

## Astra 8.60 Client Extensions

These are hardcoded in the Astra 8.60 profile:

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

Notes:

- `GameSpritesU32` must match the extended `.spr` assets used by the client.
- `GamePlayerFamiliars` affects Astra outfit data. Do not copy it into OTC Classic without parser support.
- `GameColorizedLootValue` exists in Astra and is not present in this OTC Classic branch.
- `GameProficiency` exists as a client feature, but keep it only when the server packet format is aligned with it.

## Server-Negotiated Features

The server can send features through packet `0x43` (`GameServerFeatures`). Astra also accepts features from HTTP login.

The current server `sendFeatures()` sends, among others:

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

When the connected client is Astra, the server may also send:

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

Those `Astra*` flags require Astra parser support. Do not copy them into OTC Classic.

## Dangerous Flags

These three flags are the most common source of protocol bugs:

```lua
GameQuickLootFlags              -- id 123
GameThingUpgradeClassification  -- id 130
GameItemTierByte                -- id 131
```

Do not change them from `disableFeature` to `enableFeature` unless the server is changed at the same time.

### GameQuickLootFlags

Changes item/container quick-loot flag parsing. If the client expects this byte and the server does not send it, the parser consumes the next packet field as a flag.

### GameThingUpgradeClassification

Changes item classification/tier parsing. The current server sends this feature as `false` for OTCv8/Astra.

### GameItemTierByte

Adds a tier byte to item parsing. It must be enabled only when `shouldSendItemTierByte()` is also enabled on the server.

## Differences From OTCv8 Classic

OTCv8 Classic uses version ranges such as `version >= 770`, `version >= 780`, `version >= 860`, and so on.

In the `version >= 860` block, OTC Classic mainly enables:

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

OTC Classic explicitly keeps these disabled by default:

```lua
g_game.disableFeature(GameQuickLootFlags)
g_game.disableFeature(GameThingUpgradeClassification)
g_game.disableFeature(GameItemTierByte)
```

Astra is not a direct copy of that block. Astra 8.60 has its own feature profile and parser-specific extensions.

## Checklist Before Changing a Feature

- [ ] Is the feature UI-only, or does it change network packets?
- [ ] Does the id exist in both `modules/gamelib/const.lua` and `src/client/const.h`?
- [ ] Does the server send the same feature in `sendFeatures()` or HTTP login?
- [ ] If it affects items, did you check `getItem`, `addItem`, containers, map, and inventory?
- [ ] If it affects creatures/outfits, did you check outfit window, creature icons, and login?
- [ ] Did you test login, walking, look, use, backpack, corpse, store inbox, and logout?
- [ ] If the feature is negotiated, did you test both `false` and `true`?

## Practical Rule

For Astra 8.60:

- stable Astra profile features can stay in `modules/game_features/features.lua`;
- packet-layout features should be negotiated by the server;
- Astra-only features must not be copied to OTC Classic;
- `GameQuickLootFlags`, `GameThingUpgradeClassification`, and `GameItemTierByte` must follow the server, not a client-side guess.
