--[[============================================================================
  scripting/api/enums.lua — Zerobot-compatible Enums namespace + ZB<->engine
  translation tables.
  ============================================================================

  Builder module (see scripting/CONTRACT.md). Returns
      function(api, ctx) ... return Enums end
  and is injected into every sandboxed script as the global `Enums`.

  TWO PARTS:

  PART 1 — `Enums.<Group>` : VERBATIM copies of every enum group from the
  Zerobot core (`Scripts/core/enums.lua`). SAME names, SAME numeric values.
  Scripts ported from Zerobot expect exactly these. Do not "fix" values to
  match our engine here — that is what PART 2 is for.

  PART 2 — `Enums.translate.*` : pure data + pure functions that convert a
  Zerobot enum value to the value our engine (KoliseuClient / OTClient-Astra)
  expects, and back where useful. Other API modules (Game/Player/Creature/Map
  /HUD/...) call these so the conversion lives in ONE place. Every group gets a
  translator even when ZB and the engine already agree (identity) so callers
  always use the same pattern.

  Engine reference values were read from:
    - modules/corelib/const.lua        (Fw::Key codes, Keyboard*Modifier, Align)
    - modules/gamelib/const.lua        (Directions, MessageModes, Skull*, Shield*,
                                        Emblem*, CONST_SLOT_*, Fight*/Chase*)
    - modules/gamelib/player.lua       (PlayerStates bitmask, InventorySlot*)
    - modules/gamelib/creature.lua     (Skull*, Shield*, Emblem*, CreatureType*,
                                        NpcIcon*)
    - modules/gamelib/util.lua         (translateVocation: clientid mapping)
    - mods/game_helper/compat/vocations.lua (VocationsClient clientids)
    - mods/game_helper/astra_compat.lua (Otc.Direction)

  RULES followed: no globals, no top-level `api.X` reads (refs are lazy if ever
  needed; enums are static data so they don't need the engine at runtime). All
  translation tables are plain Lua literals built at load time.
============================================================================]]

return function(api, ctx)
  local Enums = {}

  -- `bit` is provided by astra_compat.lua (aliases bit32). Guard so this module
  -- never explodes if loaded in isolation; fall back to bit32.
  local bit = bit or bit32

  -- Zerobot runs on LuaJIT, whose bit.lshift masks the shift count to 5 bits
  -- (i.e. wraps mod-32): lshift(1, 47) == lshift(1, 15) == 32768. Our engine
  -- loads Lua 5.2's bit32, whose lshift instead returns 0 for shift >= 32. The
  -- ThingFlagAttr group below mirrors Zerobot VERBATIM and includes bits up to
  -- 47, so to keep the EXACT values a ported ZB script compares against
  -- (Client.getAllItems flags), we wrap the shift ourselves to LuaJIT
  -- semantics, independent of which bit library the sandbox provides.
  local function lsh(n) return bit.lshift(1, n % 32) end

  --==========================================================================
  -- PART 1 — Zerobot enum groups (verbatim values)
  --==========================================================================

  Enums.DailyRewardType = {
    DAILY_REWARD_TYPE_ITEMS = 1,
    DAILY_REWARD_TYPE_PREY_REROLL = 2,
    DAILY_REWARD_TYPE_XP_BOOST = 3,
  }

  Enums.GameStoreOfferType = {
    GAMESTORE_OFFER_TYPE_NONE = 0,
    GAMESTORE_OFFER_TYPE_MOUNT = 1,
    GAMESTORE_OFFER_TYPE_OUTFIT = 2,
    GAMESTORE_OFFER_TYPE_ITEM = 3,
    GAMESTORE_OFFER_TYPE_HIRELING = 4,
  }

  Enums.GameStoreCoinType = {
    GAMESTORE_COIN_TYPE = 0,
    GAMESTORE_TRANSFERABLE_COIN_TYPE = 1,
  }

  Enums.GameStoreState = {
    GAMESTORE_CATEGORY_NONE = 0,
    GAMESTORE_CATEGORY_NEW = 1,
    GAMESTORE_CATEGORY_SALE = 2,
    GAMESTORE_CATEGORY_TIMED = 3,
  }

  -- The UI icon can be found above your character inventory/set.
  Enums.BlessingState = {
    UNDEFINED = -1, -- bot doesn't have this info yet
    NONE = 0,       -- no active blessings, gray icon on client UI
    NORMAL = 1,     -- normal blessings, green icon on client UI
    FULL = 2,       -- full blessings, gold icon on client UI
  }

  Enums.MonkPassiveType = {
    MONK_PASSIVE_VIRTUE_NONE = 0,
    MONK_PASSIVE_VIRTUE_HARMONY = 1,
    MONK_PASSIVE_VIRTUE_JUSTICE = 2,
    MONK_PASSIVE_VIRTUE_SUSTAIN = 3,
  }

  -- NOTE: bits 0..31 are exact powers of two on every VM. Bits 32..47 differ
  -- between LuaJIT (ZB, wraps mod-32) and Lua 5.2 bit32 (returns 0); `lsh`
  -- normalizes to LuaJIT/ZB semantics so the values match ported scripts.
  Enums.ThingFlagAttr = {
    None = 0,
    Ground = lsh(0),
    GroundBorder = lsh(1),
    OnBottom = lsh(2),
    OnTop = lsh(3),
    Container = lsh(4),
    Stackable = lsh(5),
    ForceUse = lsh(6),
    MultiUse = lsh(7),
    Writable = lsh(8),
    Chargeable = lsh(9),
    WritableOnce = lsh(10),
    FluidContainer = lsh(11),
    Splash = lsh(12),
    NotWalkable = lsh(13),
    NotMoveable = lsh(14),
    BlockProjectile = lsh(15),
    NotPathable = lsh(16),
    NoMovementAnimation = lsh(17),
    Pickupable = lsh(18),
    Hangable = lsh(19),
    HookSouth = lsh(20),
    HookEast = lsh(21),
    Rotateable = lsh(22),
    Light = lsh(23),
    DontHide = lsh(24),
    Translucent = lsh(25),
    Displacement = lsh(26),
    Elevation = lsh(27),
    LyingCorpse = lsh(28),
    AnimateAlways = lsh(29),
    MinimapColor = lsh(30),
    LensHelp = lsh(31),
    FullGround = lsh(32),
    Look = lsh(33),
    Cloth = lsh(34),
    Market = lsh(35),
    Usable = lsh(36),
    Wrapable = lsh(37),
    Unwrapable = lsh(38),
    UpgradeClassification = lsh(39),
    WearOut = lsh(40),
    ClockExpire = lsh(41),
    Expire = lsh(42),
    ExpireStop = lsh(43),
    ChangedToExpire = lsh(44),
    Podium = lsh(45),
    TopEffect = lsh(46),
    DefaultAction = lsh(47),
  }

  Enums.PreyTaskDataState = {
    PREY_TASK_DATA_STATE_LOCKED = 0,
    PREY_TASK_DATA_STATE_INACTIVE = 1,
    PREY_TASK_DATA_STATE_SELECTION = 2,
    PREY_TASK_DATA_STATE_LIST_SELECTION = 3,
    PREY_TASK_DATA_STATE_ACTIVE = 4,
    PREY_TASK_DATA_STATE_COMPLETED = 5,
  }

  Enums.AlarmType = {
    DISCONNECTED = 0,
    DAMAGE_TAKEN = 1,
    LOW_HEALTH = 2,
    PRIVATE_MESSAGE = 3,
    MONSTER_DETECTED = 4,
    MONSTER_ON_SCREEN = 5,
    PLAYER_ATTACK = 6,
    PLAYER_DETECTED = 7,
    PLAYER_ON_SCREEN = 8,
    PLAYER_STUCK = 9,
    SKULL_DETECTED = 10,
    SKULL_ON_SCREEN = 11,
    ENEMY_DETECTED = 12,
    ENEMY_ON_SCREEN = 13,
    GM_DETECTED = 14,
    LOW_CAP = 15,
    PLAYER_IDLE = 16,
  }

  -- HUD
  Enums.HorizontalAlign = {
    None = 0,
    Left = 1,
    Center = 2,
    Right = 3,
  }

  Enums.VerticalAlign = {
    None = 0,
    Top = 1,
    Center = 2,
    Bottom = 3,
  }

  Enums.GuildEmblem = {
    GUILDEMBLEM_NONE = 0,
    GUILDEMBLEM_ALLY = 1,
    GUILDEMBLEM_ENEMY = 2,
    GUILDEMBLEM_NEUTRAL = 3,
    GUILDEMBLEM_MEMBER = 4,
    GUILDEMBLEM_OTHER = 5,
  }

  Enums.WaypointType = {
    WAYPOINT_TYPE_STAND = 0,
    WAYPOINT_TYPE_NODE = 1,
    WAYPOINT_TYPE_START_LURE = 2,
    WAYPOINT_TYPE_END_LURE = 3,
    WAYPOINT_TYPE_ROPE = 4,
    WAYPOINT_TYPE_LADDER = 5,
    WAYPOINT_TYPE_HOLE = 6,
    WAYPOINT_TYPE_USE = 7,
    WAYPOINT_TYPE_TELEPORT = 8,
    WAYPOINT_TYPE_LABEL = 9,
    WAYPOINT_TYPE_GOTO = 10,
    WAYPOINT_TYPE_SCRIPT = 11,
    WAYPOINT_TYPE_DYNAMIC_START_LURE = 12,
    WAYPOINT_TYPE_DYNAMIC_END_LURE = 13,
    WAYPOINT_TYPE_DOOR = 14,
    WAYPOINT_TYPE_HUR_UP = 15,
    WAYPOINT_TYPE_HUR_DOWN = 16,
    WAYPOINT_TYPE_MACHETE = 17,
  }

  Enums.SpecialAreaType = {
    SPECIAL_AREA_ALL = 0,
    SPECIAL_AREA_CAVEBOT = 1,
    SPECIAL_AREA_TARGETING = 2,
  }

  Enums.WalkMode = {
    MAP_CLICK = 0,
    ARROW_KEYS = 1,
  }

  Enums.PartyIcons = {
    SHIELD_NONE = 0,
    SHIELD_WHITEYELLOW = 1,
    SHIELD_WHITEBLUE = 2,
    SHIELD_BLUE = 3,
    SHIELD_YELLOW = 4,
    SHIELD_BLUE_SHAREDEXP = 5,
    SHIELD_YELLOW_SHAREDEXP = 6,
    SHIELD_BLUE_NOSHAREDEXP_BLINK = 7,
    SHIELD_YELLOW_NOSHAREDEXP_BLINK = 8,
    SHIELD_BLUE_NOSHAREDEXP = 9,
    SHIELD_YELLOW_NOSHAREDEXP = 10,
    SHIELD_GRAY = 11,
  }

  Enums.Vocations = {
    NONE = 0,
    KNIGHT = 1,
    PALADIN = 2,
    SORCERER = 3,
    DRUID = 4,
    MONK = 5,
  }

  Enums.Directions = {
    NORTH = 0,
    EAST = 1,
    SOUTH = 2,
    WEST = 3,

    DIAGONAL_MASK = 4, -- from TFS
    SOUTHWEST = 0,     -- overwritten below via DIAGONAL_MASK
    SOUTHEAST = 0,
    NORTHWEST = 0,
    NORTHEAST = 0,
    INVALIDDIRECTION = 8,
  }
  Enums.Directions.SOUTHWEST = bit.bor(Enums.Directions.DIAGONAL_MASK, 0) -- 4
  Enums.Directions.SOUTHEAST = bit.bor(Enums.Directions.DIAGONAL_MASK, 1) -- 5
  Enums.Directions.NORTHWEST = bit.bor(Enums.Directions.DIAGONAL_MASK, 2) -- 6
  Enums.Directions.NORTHEAST = bit.bor(Enums.Directions.DIAGONAL_MASK, 3) -- 7

  Enums.Skulls = {
    SKULL_NONE = 0,
    SKULL_YELLOW = 1,
    SKULL_GREEN = 2,
    SKULL_WHITE = 3,
    SKULL_RED = 4,
    SKULL_BLACK = 5,
    SKULL_ORANGE = 6,
  }

  Enums.SpellGroups = {
    SPELLGROUP_NONE = 0,
    SPELLGROUP_ATTACK = 1,
    SPELLGROUP_HEALING = 2,
    SPELLGROUP_SUPPORT = 3,
    SPELLGROUP_SPECIAL = 4,
    SPELLGROUP_CONJURE = 5,
    SPELLGROUP_CRIPPLING = 6,
    SPELLGROUP_FOCUS = 7,
    SPELLGROUP_ULTIMATESTRIKES = 8,
    SPELLGROUP_GREATBEAMS = 9,
    SPELLGROUP_BURSTS = 10,
    SPELLGROUP_VIRTUE = 11,
  }

  -- incomplete list (mirrors Zerobot)
  Enums.TalkTypes = {
    TALKTYPE_SAY = 1,
    TALKTYPE_WHISPER = 2,
    TALKTYPE_YELL = 3,
    TALKTYPE_PRIVATE_PN = 12, -- talk to NPC
  }

  Enums.MessageTypes = {
    MESSAGE_STATUS_CONSOLE_RED = 13,

    MESSAGE_STATUS_DEFAULT = 17,
    MESSAGE_STATUS_WARNING = 18,
    MESSAGE_EVENT_ADVANCE = 19,

    MESSAGE_STATUS_SMALL = 21,
    MESSAGE_INFO_DESCR = 22,
    MESSAGE_DAMAGE_DEALT = 23,
    MESSAGE_DAMAGE_RECEIVED = 24,
    MESSAGE_HEALED = 25,
    MESSAGE_EXPERIENCE = 26,
    MESSAGE_DAMAGE_OTHERS = 27,
    MESSAGE_HEALED_OTHERS = 28,
    MESSAGE_EXPERIENCE_OTHERS = 29,
    MESSAGE_EVENT_DEFAULT = 30,
    MESSAGE_LOOT = 31,

    MESSAGE_GUILD = 33,
    MESSAGE_PARTY_MANAGEMENT = 34,
    MESSAGE_PARTY = 35,
    MESSAGE_EVENT_ORANGE = 36,
    MESSAGE_STATUS_CONSOLE_ORANGE = 37,
    MESSAGE_REPORT = 38,
    MESSAGE_HOTKEY = 39,
    MESSAGE_TUTORIAL_HINT = 40,
    MESSAGE_THANK_YOU = 41,
    MESSAGE_MARKET = 42,
    MESSAGE_MANA = 43,
    MESSAGE_BEYOND_LAST = 44,

    MESSAGE_ATTENTION = 48,
    MESSAGE_BOOSTED_CREATURE = 49,
    MESSAGE_OFFLINE_TRAINING = 50,
    MESSAGE_TRANSACTION = 51,
    MESSAGE_POTION = 52,
  }

  Enums.CreatureTypes = {
    CREATURETYPE_PLAYER = 0,
    CREATURETYPE_MONSTER = 1,
    CREATURETYPE_NPC = 2,
    CREATURETYPE_SUMMONPLAYER = 3,
    CREATURETYPE_SUMMON_OWN = 3,
    CREATURETYPE_SUMMON_OTHERS = 4,
    CREATURETYPE_HIDDEN = 5,
  }

  Enums.CreatureIconType = {
    QUEST = 0,    -- Enums.CreatureQuestIcons
    MODIFIER = 1, -- Enums.CreatureIcons
  }

  Enums.CreatureIcons = {
    CREATURE_ICON_NONE = 0,
    CREATURE_ICON_HIGHER_DAMAGE_RECEIVED = 1,
    CREATURE_ICON_LOWER_DAMAGE_DEALT = 2,
    CREATURE_ICON_TURNED_MELEE = 3,
    CREATURE_ICON_INFLUENCED = 4,
    CREATURE_ICON_FIENDISH = 5,
    CREATURE_ICON_REDUCED_HEALTH = 6,
  }

  Enums.CreatureQuestIcons = {
    CREATURE_QUEST_ICON_NONE = 0,
    CREATURE_QUEST_ICON_WHITECROSS = 1,
    CREATURE_QUEST_ICON_REDCROSS = 2,
    CREATURE_QUEST_ICON_REDBALL = 3,
    CREATURE_QUEST_ICON_GREENBALL = 4,
    CREATURE_QUEST_ICON_REDGREENBALL = 5,
    CREATURE_QUEST_ICON_GREENSHIELD = 6,
    CREATURE_QUEST_ICON_YELLOWSHIELD = 7,
    CREATURE_QUEST_ICON_BLUESHIELD = 8,
    CREATURE_QUEST_ICON_PURPLESHIELD = 9,
    CREATURE_QUEST_ICON_REDSHIELD = 10,
    CREATURE_QUEST_ICON_DOVE = 11,
    CREATURE_QUEST_ICON_ENERGY = 12,
    CREATURE_QUEST_ICON_EARTH = 13,
    CREATURE_QUEST_ICON_WATER = 14,
    CREATURE_QUEST_ICON_FIRE = 15,
    CREATURE_QUEST_ICON_ICE = 16,
    CREATURE_QUEST_ICON_ARROWUP = 17,
    CREATURE_QUEST_ICON_ARROWDOWN = 18,
    CREATURE_QUEST_ICON_EXCLAMATIONMARK = 19,
    CREATURE_QUEST_ICON_QUESTIONMARK = 20,
    CREATURE_QUEST_ICON_CANCELMARK = 21,
    CREATURE_QUEST_ICON_HAZARD = 22,
    CREATURE_QUEST_ICON_BROWNSKULL = 23,
    CREATURE_QUEST_ICON_BLOODDROP = 24,
  }

  Enums.FlagModifiers = {
    CONTROL = 0x1,
    ALT = 0x2,
    SHIFT = 0x4,
    NUMLOCK = 0x8,
  }

  Enums.InventorySlot = {
    CONST_SLOT_HEAD = 1,
    CONST_SLOT_NECKLACE = 2,
    CONST_SLOT_BACKPACK = 3,
    CONST_SLOT_ARMOR = 4,
    CONST_SLOT_RIGHT = 5,
    CONST_SLOT_LEFT = 6,
    CONST_SLOT_LEGS = 7,
    CONST_SLOT_FEET = 8,
    CONST_SLOT_RING = 9,
    CONST_SLOT_AMMO = 10,
    CONST_SLOT_STORE_INBOX = 11,
  }
  -- Zerobot scripts sometimes reference the plural `Enums.InventorySlots`.
  -- Alias to the same table so both spellings resolve.
  Enums.InventorySlots = Enums.InventorySlot

  Enums.States = {
    STATE_POISON = 0,
    STATE_BURN = 1,
    STATE_ENERGY = 2,
    STATE_DRUNK = 3,
    STATE_MANASHIELD = 4,
    STATE_PARALYZE = 5,
    STATE_HASTE = 6,
    STATE_SWORDS = 7,
    STATE_DROWNING = 8,
    STATE_FREEZING = 9,
    STATE_DAZZLED = 10,
    STATE_CURSED = 11,
    STATE_PARTY_BUFF = 12,
    STATE_REDSWORDS = 13,
    STATE_PIGEON = 14,
    STATE_BLEEDING = 15,
    STATE_SUFFERING_LESSER_HEX = 16,
    STATE_SUFFERING_INTENSER_HEX = 17,
    STATE_SUFFERING_GREATER_HEX = 18,
    STATE_ROOTED = 19,
    STATE_FEARED = 20,
    STATE_CURSE_I = 21,
    STATE_CURSE_II = 22,
    STATE_CURSE_III = 23,
    STATE_CURSE_IV = 24,
    STATE_CURSE_V = 25,
    STATE_MAGIC_SHIELD = 26,
    STATE_AGONY = 27,
  }

  Enums.FightMode = {
    FIGHTMODE_ATTACK = 1,
    FIGHTMODE_BALANCED = 2,
    FIGHTMODE_DEFENSE = 3,
  }
  -- client.lua docs reference the plural; alias for compatibility.
  Enums.FightModes = Enums.FightMode

  Enums.ChaseMode = {
    STAND = 0,
    CHASE = 1,
  }
  Enums.ChaseModes = Enums.ChaseMode

  Enums.QuestState = {
    PENDING = 0,
    COMPLETED = 1,
  }

  --==========================================================================
  -- PART 2 — Translation: Zerobot value <-> engine value
  --==========================================================================
  --
  -- Each translator is a pure function. Where ZB and the engine already agree
  -- the function is the identity (kept anyway so callers use one pattern). The
  -- comment on each notes "IDENTITY" or describes the remap. Reverse direction
  -- (`*FromEngine`) is provided where another module needs to surface an
  -- engine value back to a Zerobot script (event payloads, getters).

  local translate = {}
  Enums.translate = translate

  ---------------------------------------------------------------------------
  -- Directions
  --   ZB Directions:    N=0 E=1 S=2 W=3, SW=4 SE=5 NW=6 NE=7 (DIAGONAL_MASK|n),
  --                     INVALIDDIRECTION=8
  --   engine Directions (gamelib/const.lua / Otc.Direction):
  --                     North=0 East=1 South=2 West=3 NorthEast=4 SouthEast=5
  --                     SouthWest=6 NorthWest=7
  --   NOTE: cardinals AGREE (0..3). Diagonals DIFFER — ZB orders SW,SE,NW,NE
  --   (4,5,6,7) while the engine orders NE,SE,SW,NW (4,5,6,7). So a straight
  --   pass-through is WRONG for diagonals; we remap explicitly.
  ---------------------------------------------------------------------------
  local DIR_ZB_TO_ENGINE = {
    [0] = 0, -- NORTH    -> North
    [1] = 1, -- EAST     -> East
    [2] = 2, -- SOUTH    -> South
    [3] = 3, -- WEST     -> West
    [4] = 6, -- SOUTHWEST-> SouthWest(6)
    [5] = 5, -- SOUTHEAST-> SouthEast(5)
    [6] = 7, -- NORTHWEST-> NorthWest(7)
    [7] = 4, -- NORTHEAST-> NorthEast(4)
  }
  local DIR_ENGINE_TO_ZB = {
    [0] = 0, -- North     -> NORTH
    [1] = 1, -- East      -> EAST
    [2] = 2, -- South     -> SOUTH
    [3] = 3, -- West      -> WEST
    [4] = 7, -- NorthEast -> NORTHEAST(7)
    [5] = 5, -- SouthEast -> SOUTHEAST(5)
    [6] = 4, -- SouthWest -> SOUTHWEST(4)
    [7] = 6, -- NorthWest -> NORTHWEST(6)
  }

  -- ZB direction value -> engine Directions value. Returns nil for
  -- INVALIDDIRECTION(8)/out-of-range so callers can skip the action.
  function translate.directionToEngine(zbDir)
    return DIR_ZB_TO_ENGINE[zbDir]
  end

  -- engine Directions value -> ZB direction value.
  function translate.directionFromEngine(engDir)
    return DIR_ENGINE_TO_ZB[engDir]
  end

  ---------------------------------------------------------------------------
  -- TalkTypes  (Game.talk / onInternalTalk payload)
  --   ZB TalkTypes:   SAY=1 WHISPER=2 YELL=3 PRIVATE_PN=12 (talk to NPC)
  --   engine MessageModes (gamelib/const.lua), used by g_game.talk(mode,msg):
  --                   Say=1 Whisper=2 Yell=3 ... NpcTo=11
  --   Cardinal say/whisper/yell AGREE (1/2/3). NPC talk DIFFERS: ZB 12 ->
  --   engine NpcTo=11. (Engine also has NpcFrom=10 for the inbound side.)
  ---------------------------------------------------------------------------
  local TALK_ZB_TO_ENGINE = {
    [1] = 1,  -- SAY        -> Say
    [2] = 2,  -- WHISPER    -> Whisper
    [3] = 3,  -- YELL       -> Yell
    [12] = 11, -- PRIVATE_PN -> NpcTo (talk to NPC)
  }
  local TALK_ENGINE_TO_ZB = {
    [1] = 1,   -- Say     -> SAY
    [2] = 2,   -- Whisper -> WHISPER
    [3] = 3,   -- Yell    -> YELL
    [10] = 12, -- NpcFrom -> PRIVATE_PN (inbound NPC text surfaced as NPC talk)
    [11] = 12, -- NpcTo   -> PRIVATE_PN
  }

  -- ZB TalkType -> engine MessageMode (for g_game.talk). Falls back to the ZB
  -- value itself (Say/Whisper/Yell already match) so unknown types pass through.
  function translate.talkTypeToEngine(zbType)
    return TALK_ZB_TO_ENGINE[zbType] or zbType
  end

  -- engine MessageMode -> ZB TalkType (for onInternalTalk payloads). Returns
  -- the value unchanged if there is no special remap.
  function translate.talkTypeFromEngine(engMode)
    return TALK_ENGINE_TO_ZB[engMode] or engMode
  end

  ---------------------------------------------------------------------------
  -- MessageTypes  (TEXT_MESSAGE event payload .messageType)
  --   ZB MessageTypes are Tibia protocol class ids (STATUS_CONSOLE_RED=13 ...
  --   POTION=52). The engine's onTextMessage delivers an internal MessageMode
  --   (gamelib/const.lua MessageModes: Red=45, Loot=29, DamageDealed=21, ...),
  --   which is NOT the protocol number. To hand a ZB script the value it
  --   expects we map engine MessageMode -> ZB MessageType.
  --
  --   Mapping is best-effort by meaning; unmapped modes return nil (caller may
  --   forward the raw mode or skip). Built from MessageModes (engine) ->
  --   MessageTypes (ZB) where a clear counterpart exists.
  ---------------------------------------------------------------------------
  -- engine MessageMode value (see modules/gamelib/const.lua MessageModes)
  local MSGMODE = {
    Failure = 19, Look = 20, DamageDealed = 21, DamageReceived = 22,
    Heal = 23, Exp = 24, DamageOthers = 25, HealOthers = 26, ExpOthers = 27,
    Status = 28, Loot = 29, Guild = 31, PartyManagement = 32, Party = 33,
    Report = 36, HotkeyUse = 37, TutorialHint = 38, Thankyou = 39,
    Market = 40, Mana = 41, BeyondLast = 42, Red = 45,
    Attention = 53, BoostedCreature = 54, OfflineTraining = 55,
    Transaction = 56, Potion = 57, Game = 18, Warning = 17,
  }
  -- engine MessageMode -> ZB MessageTypes value.
  local MSG_ENGINE_TO_ZB = {
    [MSGMODE.Red]            = Enums.MessageTypes.MESSAGE_STATUS_CONSOLE_RED,   -- 13
    [MSGMODE.Warning]        = Enums.MessageTypes.MESSAGE_STATUS_WARNING,       -- 18
    [MSGMODE.Game]           = Enums.MessageTypes.MESSAGE_EVENT_ADVANCE,        -- 19
    [MSGMODE.Failure]        = Enums.MessageTypes.MESSAGE_STATUS_SMALL,         -- 21
    [MSGMODE.Look]           = Enums.MessageTypes.MESSAGE_INFO_DESCR,           -- 22
    [MSGMODE.DamageDealed]   = Enums.MessageTypes.MESSAGE_DAMAGE_DEALT,         -- 23
    [MSGMODE.DamageReceived] = Enums.MessageTypes.MESSAGE_DAMAGE_RECEIVED,      -- 24
    [MSGMODE.Heal]           = Enums.MessageTypes.MESSAGE_HEALED,               -- 25
    [MSGMODE.Exp]            = Enums.MessageTypes.MESSAGE_EXPERIENCE,           -- 26
    [MSGMODE.DamageOthers]   = Enums.MessageTypes.MESSAGE_DAMAGE_OTHERS,        -- 27
    [MSGMODE.HealOthers]     = Enums.MessageTypes.MESSAGE_HEALED_OTHERS,        -- 28
    [MSGMODE.ExpOthers]      = Enums.MessageTypes.MESSAGE_EXPERIENCE_OTHERS,    -- 29
    [MSGMODE.Loot]           = Enums.MessageTypes.MESSAGE_LOOT,                 -- 31
    [MSGMODE.Guild]          = Enums.MessageTypes.MESSAGE_GUILD,                -- 33
    [MSGMODE.PartyManagement]= Enums.MessageTypes.MESSAGE_PARTY_MANAGEMENT,     -- 34
    [MSGMODE.Party]          = Enums.MessageTypes.MESSAGE_PARTY,                -- 35
    [MSGMODE.Report]         = Enums.MessageTypes.MESSAGE_REPORT,               -- 38
    [MSGMODE.HotkeyUse]      = Enums.MessageTypes.MESSAGE_HOTKEY,               -- 39
    [MSGMODE.TutorialHint]   = Enums.MessageTypes.MESSAGE_TUTORIAL_HINT,        -- 40
    [MSGMODE.Thankyou]       = Enums.MessageTypes.MESSAGE_THANK_YOU,            -- 41
    [MSGMODE.Market]         = Enums.MessageTypes.MESSAGE_MARKET,               -- 42
    [MSGMODE.Mana]           = Enums.MessageTypes.MESSAGE_MANA,                 -- 43
    [MSGMODE.BeyondLast]     = Enums.MessageTypes.MESSAGE_BEYOND_LAST,          -- 44
    [MSGMODE.Attention]      = Enums.MessageTypes.MESSAGE_ATTENTION,            -- 48
    [MSGMODE.BoostedCreature]= Enums.MessageTypes.MESSAGE_BOOSTED_CREATURE,     -- 49
    [MSGMODE.OfflineTraining]= Enums.MessageTypes.MESSAGE_OFFLINE_TRAINING,     -- 50
    [MSGMODE.Transaction]    = Enums.MessageTypes.MESSAGE_TRANSACTION,          -- 51
    [MSGMODE.Potion]         = Enums.MessageTypes.MESSAGE_POTION,               -- 52
  }
  -- Reverse: ZB MessageType -> engine MessageMode (best-effort, derived).
  local MSG_ZB_TO_ENGINE = {}
  for engMode, zbType in pairs(MSG_ENGINE_TO_ZB) do
    MSG_ZB_TO_ENGINE[zbType] = engMode
  end

  -- engine MessageMode -> ZB MessageType (for the TEXT_MESSAGE payload). Returns
  -- nil when no clear counterpart exists (caller decides how to surface it).
  function translate.messageTypeFromEngine(engMode)
    return MSG_ENGINE_TO_ZB[engMode]
  end

  -- ZB MessageType -> engine MessageMode (rarely needed; for symmetry).
  function translate.messageTypeToEngine(zbType)
    return MSG_ZB_TO_ENGINE[zbType]
  end

  ---------------------------------------------------------------------------
  -- InventorySlot
  --   ZB InventorySlot:    HEAD=1 NECKLACE=2 BACKPACK=3 ARMOR=4 RIGHT=5 LEFT=6
  --                        LEGS=7 FEET=8 RING=9 AMMO=10 STORE_INBOX=11
  --   engine (gamelib/const.lua CONST_SLOT_* and gamelib/player.lua
  --   InventorySlot*):     HEAD=1 NECKLACE/Neck=2 BACKPACK/Back=3 ARMOR/Body=4
  --                        RIGHT=5 LEFT=6 LEGS/Leg=7 FEET=8 RING/Finger=9
  --                        AMMO=10 (engine InventorySlotPurse=11).
  --   1..10 AGREE exactly. Slot 11 differs in NAME only (ZB STORE_INBOX vs
  --   engine Purse) but the numeric value matches, so identity is safe for the
  --   equip/use slot calls (CONST_SLOT_* is what g_game uses).
  --   => IDENTITY.
  ---------------------------------------------------------------------------
  function translate.inventorySlotToEngine(zbSlot)
    return zbSlot -- IDENTITY (CONST_SLOT_* values are equal 1..11)
  end
  function translate.inventorySlotFromEngine(engSlot)
    return engSlot -- IDENTITY
  end

  ---------------------------------------------------------------------------
  -- States  (Player.getState / condition checks)
  --   ZB States are BIT INDICES (STATE_POISON=0, STATE_BURN=1, ...).
  --   engine PlayerStates (gamelib/player.lua) are BITMASK FLAGS
  --   (Poison=1=2^0, Burn=2=2^1, Energy=4=2^2, ... Agony=2^27). The engine's
  --   Player:getStates() returns the OR'd bitmask, tested with bit.band.
  --
  --   So to test a ZB state against the engine mask: flag = 2^zbIndex.
  --   Positionally this lines up for the WHOLE range 0..27, EXCEPT two indices
  --   are conceptually different (the bit position still matches, only the
  --   *name/meaning* diverges):
  --     index 13: ZB STATE_REDSWORDS  vs engine 2^13 = PzBlock
  --     index 14: ZB STATE_PIGEON     vs engine 2^14 = Pz
  --   (engine has no RedSwords/Pigeon; it inserts PzBlock/Pz there. ZB has no
  --   PzBlock/Pz. Everything else — including ROOTED=19, FEARED=20, CURSE_I..V,
  --   MAGIC_SHIELD=26, AGONY=27 — matches bit-for-bit.)
  ---------------------------------------------------------------------------
  -- ZB state index -> engine PlayerStates bitmask flag (2^index). Use the
  -- result with bit.band(player:getStates(), flag) ~= 0.
  function translate.stateToEngine(zbStateIndex)
    if type(zbStateIndex) ~= "number" or zbStateIndex < 0 or zbStateIndex > 31 then
      return nil
    end
    return bit.lshift(1, zbStateIndex)
  end

  -- engine PlayerStates bitmask FLAG -> ZB state index. Inverse of the above
  -- for a single-bit flag; returns nil if the value is 0 or not a power of two.
  function translate.stateFromEngine(engFlag)
    if type(engFlag) ~= "number" or engFlag <= 0 then return nil end
    local idx = 0
    local v = engFlag
    while v > 1 do
      if v % 2 ~= 0 then return nil end -- not a single bit
      v = v / 2
      idx = idx + 1
    end
    return idx
  end

  -- Convenience: does the engine state bitmask contain the given ZB state?
  --   translate.hasState(player:getStates(), Enums.States.STATE_ROOTED)
  function translate.hasState(engStatesBitmask, zbStateIndex)
    local flag = translate.stateToEngine(zbStateIndex)
    if not flag or not engStatesBitmask then return false end
    return bit.band(engStatesBitmask, flag) ~= 0
  end

  ---------------------------------------------------------------------------
  -- Vocations
  --   ZB Vocations:   NONE=0 KNIGHT=1 PALADIN=2 SORCERER=3 DRUID=4 MONK=5
  --   engine getVocation() returns the KoliseuOT *clientid*:
  --     base:       Knight=1 Paladin=2 Sorcerer=3 Druid=4 Monk=5
  --     promotion:  EliteKnight=11 RoyalPaladin=12 MasterSorcerer=13
  --                 ElderDruid=14 ExaltedMonk=15
  --   (verified: mods/game_helper/compat/vocations.lua + gamelib/util.lua
  --   translateVocation, which collapses 1/11, 2/12, 3/13, 4/14, 5/15.)
  --
  --   => base IDs (0..5) MATCH ZB exactly. The translation just collapses the
  --   promotion clientids (11..15) down to the ZB base value.
  --
  --   LIMITATION: vocationToEngine cannot recover the promoted clientid — it
  --   returns the BASE clientid (1..5). A script that needs to act on an Elite
  --   Knight specifically must read the raw getVocation() itself. Also note the
  --   "supreme/elite collapse" caveat: at the appearance/clientid level some
  --   higher tiers are indistinguishable (see MEMORY: vocation-ids note); the
  --   real promoted id requires the server-side extended opcode, not this table.
  ---------------------------------------------------------------------------
  local VOC_ENGINE_TO_ZB = {
    [0] = 0,                                    -- None
    [1] = Enums.Vocations.KNIGHT,   [11] = Enums.Vocations.KNIGHT,
    [2] = Enums.Vocations.PALADIN,  [12] = Enums.Vocations.PALADIN,
    [3] = Enums.Vocations.SORCERER, [13] = Enums.Vocations.SORCERER,
    [4] = Enums.Vocations.DRUID,    [14] = Enums.Vocations.DRUID,
    [5] = Enums.Vocations.MONK,     [15] = Enums.Vocations.MONK,
  }
  -- ZB Vocation -> engine BASE clientid (1..5). Promotion info is lost.
  local VOC_ZB_TO_ENGINE = {
    [0] = 0,
    [Enums.Vocations.KNIGHT]   = 1,
    [Enums.Vocations.PALADIN]  = 2,
    [Enums.Vocations.SORCERER] = 3,
    [Enums.Vocations.DRUID]    = 4,
    [Enums.Vocations.MONK]     = 5,
  }

  -- engine vocation clientid (incl. promotions 11..15) -> ZB Vocations value.
  function translate.vocationFromEngine(engVocId)
    return VOC_ENGINE_TO_ZB[engVocId] or 0
  end

  -- ZB Vocations value -> engine BASE clientid (cannot express a promotion).
  function translate.vocationToEngine(zbVoc)
    return VOC_ZB_TO_ENGINE[zbVoc] or 0
  end

  -- Is this engine clientid a promoted vocation (11..15)?
  function translate.isPromotedVocation(engVocId)
    return engVocId ~= nil and engVocId >= 11 and engVocId <= 15
  end

  ---------------------------------------------------------------------------
  -- Skulls
  --   ZB Skulls:   SKULL_NONE=0 YELLOW=1 GREEN=2 WHITE=3 RED=4 BLACK=5 ORANGE=6
  --   engine (gamelib/const.lua & creature.lua):
  --                SkullNone=0 SkullYellow=1 SkullGreen=2 SkullWhite=3
  --                SkullRed=4 SkullBlack=5 SkullOrange=6
  --   => IDENTITY (0..6 match; engine Creature:getSkull() returns these).
  ---------------------------------------------------------------------------
  function translate.skullToEngine(zbSkull)
    return zbSkull -- IDENTITY
  end
  function translate.skullFromEngine(engSkull)
    return engSkull -- IDENTITY
  end

  ---------------------------------------------------------------------------
  -- GuildEmblem
  --   ZB GuildEmblem:  NONE=0 ALLY=1 ENEMY=2 NEUTRAL=3 MEMBER=4 OTHER=5
  --   engine (gamelib/const.lua / creature.lua):
  --                    EmblemNone=0 EmblemGreen=1 EmblemRed=2 EmblemBlue=3
  --                    EmblemMember=4 EmblemOther=5
  --   Numeric values AGREE 0..5 (and match the protocol GUILDEMBLEM order:
  --   Green=ally, Red=enemy, Blue=neutral). => IDENTITY by value.
  ---------------------------------------------------------------------------
  function translate.guildEmblemToEngine(zbEmblem)
    return zbEmblem -- IDENTITY (engine Emblem* == ZB GUILDEMBLEM_* by value)
  end
  function translate.guildEmblemFromEngine(engEmblem)
    return engEmblem -- IDENTITY
  end

  ---------------------------------------------------------------------------
  -- PartyIcons (party shield)
  --   ZB PartyIcons:   SHIELD_NONE=0 WHITEYELLOW=1 WHITEBLUE=2 BLUE=3 YELLOW=4
  --                    BLUE_SHAREDEXP=5 YELLOW_SHAREDEXP=6
  --                    BLUE_NOSHAREDEXP_BLINK=7 YELLOW_NOSHAREDEXP_BLINK=8
  --                    BLUE_NOSHAREDEXP=9 YELLOW_NOSHAREDEXP=10 GRAY=11
  --   engine Shield* (gamelib/const.lua): identical names/order, ShieldNone=0
  --                    .. ShieldGray=11. => IDENTITY (Creature:getShield()).
  ---------------------------------------------------------------------------
  function translate.partyIconToEngine(zbShield)
    return zbShield -- IDENTITY
  end
  function translate.partyIconFromEngine(engShield)
    return engShield -- IDENTITY
  end

  ---------------------------------------------------------------------------
  -- CreatureTypes
  --   ZB CreatureTypes: PLAYER=0 MONSTER=1 NPC=2 SUMMONPLAYER/SUMMON_OWN=3
  --                     SUMMON_OTHERS=4 HIDDEN=5
  --   engine (gamelib/creature.lua): CreatureTypePlayer=0 Monster=1 Npc=2
  --                     SummonOwn=3 SummonOther=4   (no HIDDEN constant)
  --   Values 0..4 AGREE. HIDDEN=5 has no engine constant but the value passes
  --   through unchanged. => IDENTITY by value.
  ---------------------------------------------------------------------------
  function translate.creatureTypeToEngine(zbType)
    return zbType -- IDENTITY (0..4 match; 5/HIDDEN passes through)
  end
  function translate.creatureTypeFromEngine(engType)
    return engType -- IDENTITY
  end

  ---------------------------------------------------------------------------
  -- FightMode
  --   ZB FightMode:  ATTACK=1 BALANCED=2 DEFENSE=3
  --   engine (gamelib/const.lua): FightOffensive=1 FightBalanced=2
  --                               FightDefensive=3
  --   => IDENTITY (1..3 match; used by g_game.setFightMode).
  ---------------------------------------------------------------------------
  function translate.fightModeToEngine(zbMode)
    return zbMode -- IDENTITY
  end
  function translate.fightModeFromEngine(engMode)
    return engMode -- IDENTITY
  end

  ---------------------------------------------------------------------------
  -- ChaseMode
  --   ZB ChaseMode:  STAND=0 CHASE=1
  --   engine (gamelib/const.lua): DontChase=0 ChaseOpponent=1
  --   => IDENTITY (0/1 match; used by g_game.setChaseMode).
  ---------------------------------------------------------------------------
  function translate.chaseModeToEngine(zbMode)
    return zbMode -- IDENTITY
  end
  function translate.chaseModeFromEngine(engMode)
    return engMode -- IDENTITY
  end

  ---------------------------------------------------------------------------
  -- FlagModifiers (keyboard modifier bitmask)
  --   ZB FlagModifiers: CONTROL=0x1 ALT=0x2 SHIFT=0x4 NUMLOCK=0x8 (OR-folded)
  --   engine corelib/const.lua exposes COMBINED constants, not single bits:
  --     KeyboardNoModifier=0 CtrlModifier=1 AltModifier=2 CtrlAltModifier=3
  --     ShiftModifier=4 CtrlShiftModifier=5 AltShiftModifier=6
  --     CtrlAltShiftModifier=7
  --   i.e. the engine uses Ctrl=1, Alt=2, Shift=4 (NO numlock bit). The bit
  --   layout for Ctrl/Alt/Shift is IDENTICAL to ZB, so an OR-folded ZB modifier
  --   maps onto the engine's combined value directly — EXCEPT ZB's NUMLOCK
  --   (0x8) has no engine equivalent and must be stripped.
  --   (g_keyboard / getKeyboardModifiers in this engine returns these combined
  --   Keyboard*Modifier values.)
  ---------------------------------------------------------------------------
  -- ZB modifier bitmask -> engine Keyboard*Modifier combined value.
  -- Strips NUMLOCK (0x8) which the engine does not represent.
  function translate.flagModifiersToEngine(zbMods)
    if type(zbMods) ~= "number" then return 0 end
    -- keep only Ctrl(1)|Alt(2)|Shift(4)
    return bit.band(zbMods, 0x7)
  end
  -- engine Keyboard*Modifier combined value -> ZB modifier bitmask.
  -- Identity over the Ctrl/Alt/Shift bits (engine never sets a numlock bit).
  function translate.flagModifiersFromEngine(engMods)
    if type(engMods) ~= "number" then return 0 end
    return bit.band(engMods, 0x7)
  end

  ---------------------------------------------------------------------------
  -- Keys (HotkeyManager / Client.sendHotkey / Client.isKeyPressed)
  --   Zerobot's HotkeyManager maps key names to QT-style key codes. Our engine
  --   uses the Fw::Key enum (modules/corelib/const.lua: KeyA=65 ... KeyF1=128,
  --   KeyEscape=1, etc.). These enums DIFFER (e.g. ZB letters use ASCII 65-90,
  --   which happens to match KeyA..KeyZ here too, but F-keys, arrows, numpad and
  --   punctuation diverge). The full key-name table belongs in the
  --   hotkeymanager port, not here; we DO NOT attempt a numeric key
  --   cross-walk in this module.
  --   TODO: confirmar — if a numeric ZB-keycode <-> Fw::Key map is ever needed,
  --   build it from corelib/const.lua KeyCodeDescs. For now translate.keyToEngine
  --   is identity (engine consumers should accept Fw::Key codes directly and the
  --   hotkeymanager module should emit Fw::Key codes, not QT codes).
  ---------------------------------------------------------------------------
  function translate.keyToEngine(keyCode)
    return keyCode -- TODO: confirmar (identity; see note above)
  end
  function translate.keyFromEngine(keyCode)
    return keyCode -- TODO: confirmar
  end

  ---------------------------------------------------------------------------
  -- HUD alignment (HorizontalAlign / VerticalAlign)
  --   These are ZB-internal HUD enums consumed by our own HUD module's native
  --   layer; there is no separate engine enum they must convert to (the HUD
  --   port decides how to apply them). Exposed as identity for pattern
  --   consistency only.
  ---------------------------------------------------------------------------
  function translate.horizontalAlignToEngine(v) return v end -- IDENTITY (HUD-internal)
  function translate.verticalAlignToEngine(v) return v end   -- IDENTITY (HUD-internal)

  return Enums
end
