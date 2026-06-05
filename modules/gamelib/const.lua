-- @docconsts @{

GOLD_COINS = 3031
REWARD_CHEST = 19250
ITEM_WILD_GROWTH = 2130

HELP_CHANNEL = 7

LOCAL_CHAT_NAME = "Local Chat"
SERVER_LOG_NAME = "Server Log"
NPC_NAME_CHAT = "NPCs"
SPELL_CHANNEL_NAME = "Spells"
SPELL_CHANNEL_ID = 0xFFEF

RENOWN_PODIUM = 35973
VIGOUR_PODIUM = 38707
TENACITY_PODIUM = 42367

FloorHigher = 0
FloorLower = 15

SkullNone = 0
SkullYellow = 1
SkullGreen = 2
SkullWhite = 3
SkullRed = 4
SkullBlack = 5
SkullOrange = 6

ShieldNone = 0
ShieldWhiteYellow = 1
ShieldWhiteBlue = 2
ShieldBlue = 3
ShieldYellow = 4
ShieldBlueSharedExp = 5
ShieldYellowSharedExp = 6
ShieldBlueNoSharedExpBlink = 7
ShieldYellowNoSharedExpBlink = 8
ShieldBlueNoSharedExp = 9
ShieldYellowNoSharedExp = 10
ShieldGray = 11

uint8Max = 255
uint16Max = 65535
uint32Max = 4294967295
uint64Max = 18446744073709551615

EmblemNone = 0
EmblemGreen = 1
EmblemRed = 2
EmblemBlue = 3
EmblemMember = 4
EmblemOther = 5

VipIconFirst = 0
VipIconLast = 10

ResourceBank = 0
ResourceInventary = 1
ResourceInventory = ResourceInventary
ResourceNpcTrade = 2
ResourcePreyBonus = 10
ResourceReward = 20
ResourceJokerReward = 21
ResourceBoss = 30

ResourceCharmBalance = 30
ResourceEchoeBalance = 31
ResourceMaxCharmBalance = 32
ResourceMaxEchoeBalance = 33

ResourceHuntingTask = 50
ResourceNpcStorageTrade = 60
ResourceForgeDust = 20
ResourceForgeSlivers = 21
ResourceForgeExaltedCore = 22
ResourceWheelPoints = 80
ResourceLesserGem = 81
ResourceRegularGem = 82
ResourceGreaterGem = 83
ResourceLesserFragment = 84
ResourceGreaterFragment = 85

Directions = {
  North = 0,
  East = 1,
  South = 2,
  West = 3,
  NorthEast = 4,
  SouthEast = 5,
  SouthWest = 6,
  NorthWest = 7
}

Flip = {
  None = 0,
  Horizontal = 1,
  Vertical = 2,
}
FlipDirection = Flip

Skill = {
  Fist = 0,
  Club = 1,
  Sword = 2,
  Axe = 3,
  Distance = 4,
  Shielding = 5,
  Fishing = 6,
  CriticalChance = 7,
  CriticalDamage = 8,
  LifeLeechChance = 9,
  LifeLeechAmount = 10,
  ManaLeechChance = 11,
  ManaLeechAmount = 12,
  OnslaughtChance = 13,
  RuseChance = 14,
  MomentumChance = 15,
  TranscendenceChance = 16,
  AmplificationChance = 17
}

specialTooltips = {
  ["convertedDamage"] = "+%s%% of your attack value will be converted into %s damage.",
  ["lifeLeech"] = "You get +%s%% of the damage dealt as hit points.",
  ["manaLeech"] = "You get +%s%% of the damage dealt as mana.",
  ["criticalChance"] = "You have a +%s%% chance to cause +%s%% extra damage",
  ["criticalDamage"] = "You have a +%s%% chance to cause +%s%% extra damage",
  ["onslaught"] = " You have a +%s%% chance to trigger Onslaught, granting you 60%%\nincreased damage for all attacks.",
  ["protection"] = "Any %s damage you receive from attacks is %s by +%s%%.\n%s",
  ["protection_note"] = "Note that the damage reduction is calculated from the individual\ndamage reductions of your equipment as well as from bonuses\nunlocked in the Wheel of Destiny. However, these values are not\nsimply added up. It depends on various factors to which extent the\ndamage reduction is added to your overall damage reduction. For\nexample, the benefit of damage reduction diminishes when wearing\nequipment with the same damage resistance.",
  ["reflectionValue"] = "You reflect %s of the taken damage to the attacker",
  ["ruseValue"] = "When attacked, you have a %s chance to trigger Ruse, which\nwill fully mitigate the damage.",
  ["momentumValue"] = "During combat, you have a +%s%% chance to trigger Momentum,\nwich reduced all spell cooldowns by 2 seconds.",
  ["transcendenceValue"] = "During combat, you have a +%s%% chance to trigger\nTranscendence, wich transforms your character into a vocation\nspecific avatar for 7 seconds. While in this form, you will benefit\nfrom a 15%% damage reduction and guaranteed critical hits that\ndeal an additional 15%% damage.",
  ["amplificationValue"] = "Effects of tiered items are amplified by +%s%%.",
}

CONST_SLOT_WHEREEVER = 0
CONST_SLOT_HEAD      = 1
CONST_SLOT_NECKLACE  = 2
CONST_SLOT_BACKPACK  = 3
CONST_SLOT_ARMOR     = 4
CONST_SLOT_RIGHT     = 5
CONST_SLOT_LEFT      = 6
CONST_SLOT_LEGS      = 7
CONST_SLOT_FEET      = 8
CONST_SLOT_RING      = 9
CONST_SLOT_AMMO      = 10

ELEMENTAL_PHYSICAL  = 0
ELEMENTAL_FIRE      = 1
ELEMENTAL_EARTH     = 2
ELEMENTAL_ENERGY    = 3
ELEMENTAL_ICE       = 4
ELEMENTAL_HOLY      = 5
ELEMENTAL_DEATH     = 6
ELEMENTAL_HEALING   = 7
ELEMENTAL_DROWN     = 8
ELEMENTAL_LIFEDRAIN = 9
ELEMENTAL_MANADRAIN = 10
ELEMENTAL_AGONY     = 11
ELEMENTAL_UNDEFINED = 12
ELEMENTAL_HEALING2  = 18

WEAPON_NONE = 0
WEAPON_SWORD = 1
WEAPON_AXE = 2
WEAPON_CLUB = 3
WEAPON_FIST = 4
WEAPON_BOW = 5
WEAPON_CROSSBOW = 6
WEAPON_WANDROD = 7
WEAPON_THROW = 8

North = Directions.North
East = Directions.East
South = Directions.South
West = Directions.West
NorthEast = Directions.NorthEast
SouthEast = Directions.SouthEast
SouthWest = Directions.SouthWest
NorthWest = Directions.NorthWest

FightOffensive = 1
FightBalanced = 2
FightDefensive = 3

DontChase = 0
ChaseOpponent = 1

PVPWhiteDove = 0
PVPWhiteHand = 1
PVPYellowHand = 2
PVPRedFist = 3

GameProtocolChecksum = 1
GameAccountNames = 2
GameChallengeOnLogin = 3
GamePenalityOnDeath = 4
GameNameOnNpcTrade = 5
GameDoubleFreeCapacity = 6
GameDoubleExperience = 7
GameTotalCapacity = 8
GameSkillsBase = 9
GamePlayerRegenerationTime = 10
GameChannelPlayerList = 11
GamePlayerMounts = 12
GameEnvironmentEffect = 13
GameCreatureEmblems = 14
GameItemAnimationPhase = 15
GameMagicEffectU16 = 16
GamePlayerMarket = 17
GameSpritesU32 = 18
GameTileAddThingWithStackpos = 19
GameOfflineTrainingTime = 20
GamePurseSlot = 21
GameFormatCreatureName = 22
GameSpellList = 23
GameClientPing = 24
GameExtendedClientPing = 25
GameDoubleHealth = 28
GameDoubleSkills = 29
GameChangeMapAwareRange = 30
GameMapMovePosition = 31
GameAttackSeq = 32
GameBlueNpcNameColor = 33
GameDiagonalAnimatedText = 34
GameLoginPending = 35
GameNewSpeedLaw = 36
GameForceFirstAutoWalkStep = 37
GameMinimapRemove = 38
GameDoubleShopSellAmount = 39
GameContainerPagination = 40
GameThingMarks = 41
GameLooktypeU16 = 42
GamePlayerStamina = 43
GamePlayerAddons = 44
GameMessageStatements = 45
GameMessageLevel = 46
GameNewFluids = 47
GamePlayerStateU16 = 48
GameNewOutfitProtocol = 49
GamePVPMode = 50
GameWritableDate = 51
GameAdditionalVipInfo = 52
GameBaseSkillU16 = 53
GameCreatureIcons = 54
GameHideNpcNames = 55
GameSpritesAlphaChannel = 56
GamePremiumExpiration = 57
GameBrowseField = 58
GameEnhancedAnimations = 59
GameOGLInformation = 60
GameMessageSizeCheck = 61
GamePreviewState = 62
GameLoginPacketEncryption = 63
GameClientVersion = 64
GameContentRevision = 65
GameExperienceBonus = 66
GameAuthenticator = 67
GameUnjustifiedPoints = 68
GameSessionKey = 69
GameDeathType = 70
GameIdleAnimations = 71
GameKeepUnawareTiles = 72
GameIngameStore = 73
GameIngameStoreHighlights = 74
GameIngameStoreServiceType = 75
GameAdditionalSkills = 76
GameDistanceEffectU16 = 77
GamePrey = 78
GameDoubleMagicLevel = 79

GameExtendedOpcode = 80
GameMinimapLimitedToSingleFloor = 81
GameSendWorldName = 82

GameDoubleLevel = 83
GameDoubleSoul = 84
GameDoublePlayerGoodsMoney = 85
GameCreatureWalkthrough = 86 -- add Walkthrough for versions less than 854, unpass = msg->getU8(); in protocolgameparse.cpp
GameDoubleTradeMoney = 87
GameSequencedPackets = 88
GameTibia12Protocol = 89

GameNewWalking = 90
GameSlowerManualWalking = 91
GameItemTooltip = 93

GameBot = 95
GameBiggerMapCache = 96
GameForceLight = 97
GameNoDebug = 98
GameBotProtection = 99

GameCreatureDirectionPassable = 100
GameFasterAnimations = 101
GameCenteredOutfits = 102
GameSendIdentifiers = 103
GameWingsAndAura = 104
GamePlayerStateU32 = 105
GameOutfitShaders = 106
GameForceAllowItemHotkeys = 107
GameCountU16 = 108
GameDrawAuraOnTop = 109

GamePacketSizeU32 = 110
GamePacketCompression = 111

GameOldInformationBar = 112
GameHealthInfoBackground = 113
GameWingOffset = 114
GameAuraFrontAndBack = 115 -- To use that: First layer is bottom/back, second (blend layer) is top/front

GameMapDrawGroundFirst = 116 -- useful for big auras & wings
GameMapIgnoreCorpseCorrection = 117
GameDontCacheFiles = 118 -- doesn't work with encryption and compression
GameBigAurasCenter = 119 -- Automatic negative offset for aura bigger than 32x32
GameNewUpdateWalk = 120 -- Walk update rate dependant on FPS
GameColorizedLootValue = 121 -- Mehah/Canary-compatible loot value colouring
GameCreaturesMana = 122 -- get mana from server for creatures other than Player
GameQuickLootFlags = 123 -- enables quick loot feature for all protocols
GameDontMergeAnimatedText = 124
GameMissionId = 125
GameItemCustomAttributes = 126
GameAnimatedTextCustomFont = 127
GameDrawFloorShadow = 128
GameDisplayItemDuration = 129
GameThingUpgradeClassification = 130
GameItemTierByte = 131
GameProficiency = 132

GameLoadTibiaAssets = 133
GameGroupInMessage = 134
GameExevoVisHur = 135
GameNewCreatureStacking = 136 -- Ignore MAX_THINGS limit while adding to tile

LastGameFeature = 137

TextColors = {
  red        = '#F55E5E',
  orange     = '#F36500',
  orangeMob  = '#FE6500',
  orangeChat = '#F6A731',
  yellow     = '#FFFF00',
  yellowSay  = '#F0F000',
  green      = '#00EB00',
  lightblue  = '#5FF7F7',
  darkblue   = '#1f9ffe',
  blue       = '#9F9DFD',
  white      = '#FFFFFF',
}

EquipmentPresetSlots = {
  CONST_SLOT_HEAD,
  CONST_SLOT_NECKLACE,
  CONST_SLOT_ARMOR,
  CONST_SLOT_RIGHT,
  CONST_SLOT_LEFT,
  CONST_SLOT_LEGS, 
  CONST_SLOT_FEET,
  CONST_SLOT_RING,
  CONST_SLOT_AMMO
}

MessageModes = {
  None                    = 0,
  Say                     = 1,
  Whisper                 = 2,
  Yell                    = 3,
  PrivateFrom             = 4,
  PrivateTo               = 5,
  ChannelManagement       = 6,
  Channel                 = 7,
  ChannelHighlight        = 8,
  Spell                   = 9,
  NpcFrom                 = 10,
  NpcTo                   = 11,
  GamemasterBroadcast     = 12,
  GamemasterChannel       = 13,
  GamemasterPrivateFrom   = 14,
  GamemasterPrivateTo     = 15,
  Login                   = 16,
  Warning                 = 17,
  Game                    = 18,
  Failure                 = 19,
  Look                    = 20,
  DamageDealed            = 21,
  DamageReceived          = 22,
  Heal                    = 23,
  Exp                     = 24,
  DamageOthers            = 25,
  HealOthers              = 26,
  ExpOthers               = 27,
  Status                  = 28,
  Loot                    = 29,
  TradeNpc                = 30,
  Guild                   = 31,
  PartyManagement         = 32,
  Party                   = 33,
  BarkLow                 = 34,
  BarkLoud                = 35,
  Report                  = 36,
  HotkeyUse               = 37,
  TutorialHint            = 38,
  Thankyou                = 39,
  Market                  = 40,
  Mana                    = 41,
  BeyondLast              = 42,
  MonsterYell             = 43,
  MonsterSay              = 44,
  Red                     = 45,
  Blue                    = 46,
  RVRChannel              = 47,
  Notification            = 48,
  RVRContinue             = 49,
  GameHighlight           = 50,
  NpcFromStartBlock       = 51,
  BoostedMessage          = 52,
  Potion                  = 53,
  Last                    = 54,
  Invalid                 = 255,
}

OTSERV_RSA  = "1091201329673994292788609605089955415282375029027981291234687579" ..
              "3726629149257644633073969600111060390723088861007265581882535850" ..
              "3429057592827629436413108566029093628212635953836686562675849720" ..
              "6207862794310902180176810615217550567108238764764442605581471797" ..
              "07119674283982419152118103759076030616683978566631413"

CIPSOFT_RSA = "1321277432058722840622950990822933849527763264961655079678763618" ..
              "4334395343554449668205332383339435179772895415509701210392836078" ..
              "6959821132214473291575712138800495033169914814069637740318278150" ..
              "2907336840325241747827401343576296990629870233111328210165697754" ..
              "88792221429527047321331896351555606801473202394175817"

-- set to the latest Astra.pic signature to make otclient compatible with official Astra
PIC_SIGNATURE = 0x56C5DDE7

OsTypes = {
  Linux = 1,
  Windows = 2,
  Flash = 3,
  OtclientLinux = 10,
  OtclientWindows = 11,
  OtclientMac = 12,
}

PathFindResults = {
  Ok = 0,
  Position = 1,
  Impossible = 2,
  TooFar = 3,
  NoWay = 4,
}

PathFindFlags = {
  AllowNullTiles = 1,
  AllowCreatures = 2,
  AllowNonPathable = 4,
  AllowNonWalkable = 8,
}

VipState = {
  Offline = 0,
  Online = 1,
  Pending = 2,
  Training = 3,
  Prestige = 4
}

ExtendedIds = {
  Activate = 0,
  Locale = 1,
  Ping = 2,
  Sound = 3,
  Game = 4,
  Particles = 5,
  MapShader = 6,
  NeedsUpdate = 7,
  Cavebot = 210,
  SmartFollow = 212,
  BotCheckAlert = 230,
  Teleportation = 246
}

PreviewState = {
  Default = 0,
  Inactive = 1,
  Active = 2
}

Blessings = {
  None = 0,
  Adventurer = 1,
  SpiritualShielding = 2,
  EmbraceOfTibia = 4,
  FireOfSuns = 8,
  WisdomOfSolitude = 16,
  SparkOfPhoenix = 32
}

DeathType = {
  Regular = 0,
  Blessed = 1
}

ProductType = {
  Other = 0,
  NameChange = 1
}

StoreErrorType = {
  NoError = -1,
  PurchaseError = 0,
  NetworkError = 1,
  HistoryError = 2,
  TransferError = 3,
  Information = 4
}

StoreState = {
  None = 0,
  New = 1,
  Sale = 2,
  Timed = 3
}

AccountStatus = {
  Ok = 0,
  Frozen = 1,
  Suspended = 2,
}

SubscriptionStatus = {
  Free = 0,
  Premium = 1,
}

ChannelEvent = {
  Join = 0,
  Leave = 1,
  Invite = 2,
  Exclude = 3,
}

-- @}

SpeakTypesSettings = {
  none = {},
  consoleYellow =         { color = TextColors.yellow,                                      consoleTab='Local Chat' },
  private =               { color = TextColors.lightblue,                                   private = true,                  screenTarget='privateLabel', visibleTime=3000},
  privateRed =            { color = TextColors.red, private = true },
  privatePlayerToPlayer = { color = TextColors.blue, private = true },
  privatePlayerToNpc =    { color = TextColors.blue, private = true, npcChat = true },
  privateNpcToPlayer =    { color = TextColors.lightblue,                                   private = true,           npcChat = true },
  channelYellow =         { color = TextColors.yellow },
  channelWhite =          { color = TextColors.white },
  channelRed =            { color = TextColors.red },
  channelOrange =         { color = TextColors.orangeChat },
  monsterSay =            { color = TextColors.orangeMob,                                  hideInConsole = true},
  monsterYell =           { color = TextColors.orangeMob,                                  hideInConsole = true},
  rvrAnswerFrom =         { color = TextColors.orangeMob },
  rvrAnswerTo =           { color = TextColors.orangeMob },
  potion =                { color = TextColors.orangeMob,                                  hideInConsole = true},


  consoleRed             = { color = TextColors.red,      consoleTab='Local Chat' },
  consoleOrange          = { color = TextColors.orange,   hideInConsole = true },
  consoleBlue            = { color = TextColors.blue,     consoleTab='Local Chat' },
  centerRed              = { color = TextColors.red,      consoleTab='Server Log', screenTarget='lowCenterLabel' , visibleTime=30000},
  centerGreen            = { color = TextColors.green,    consoleTab='Server Log', screenTarget='highCenterLabel',   consoleOption='showInfoMessagesInConsole' },
  centerHKGreen          = { color = TextColors.green,    consoleTab='Server Log', screenTarget='highCenterLabel',   consoleOption='showHotkeyMessagesInConsole' },
  centerWhite            = { color = TextColors.white,    consoleTab='Server Log', screenTarget='middleCenterLabel', consoleOption='showEventMessagesInConsole' },
  bottomWhite            = { color = TextColors.white,    consoleTab='Server Log', screenTarget='statusLabel',       consoleOption='showEventMessagesInConsole' },
  status                 = { color = TextColors.white,    consoleTab='Server Log', screenTarget='statusLabel',       consoleOption='showStatusMessagesInConsole' },
  statusOwn              = { color = TextColors.white,    consoleTab='Server Log',                                   consoleOption='showStatusMessagesInConsole' },
  statusBoosted          = { color = TextColors.white,    consoleTab='Server Log', screenTarget='statusLabel',       consoleOption='showBoostedMessagesInConsole' },
  statusOthers           = { color = TextColors.white,    consoleTab='Server Log',                                   consoleOption='showStatusOthersMessagesInConsole' },
  statusSmall            = { color = TextColors.white,                             screenTarget='statusLabel' },
--  private                = { color = TextColors.lightblue,                         screenTarget='privateLabel' },
  centerWhiteColored     = { color = TextColors.white,    consoleTab='Loot',       screenTarget='middleCenterLabel2', colored = true, visibleTime=8000 },
}

MessageTypes = {
  [MessageModes.Say] = SpeakTypesSettings.consoleYellow,
  [MessageModes.Whisper] = SpeakTypesSettings.consoleYellow,
  [MessageModes.Yell] = SpeakTypesSettings.consoleYellow,
  [MessageModes.PrivateFrom] = SpeakTypesSettings.private,
  [MessageModes.PrivateTo] = SpeakTypesSettings.privatePlayerToPlayer,
  [MessageModes.GamemasterPrivateFrom] = SpeakTypesSettings.privateRed,
  [MessageModes.NpcTo] = SpeakTypesSettings.privatePlayerToNpc,
  [MessageModes.NpcFrom] = SpeakTypesSettings.privateNpcToPlayer,
  [MessageModes.Channel] = SpeakTypesSettings.channelYellow,
  [MessageModes.ChannelManagement] = SpeakTypesSettings.channelWhite,
  [MessageModes.GamemasterChannel] = SpeakTypesSettings.channelRed,
  [MessageModes.ChannelHighlight] = SpeakTypesSettings.channelOrange,
  [MessageModes.MonsterSay] = SpeakTypesSettings.monsterSay,
  [MessageModes.MonsterYell] = SpeakTypesSettings.monsterYell,
  [MessageModes.RVRChannel] = SpeakTypesSettings.channelWhite,
  [MessageModes.RVRContinue] = SpeakTypesSettings.consoleYellow,
  [MessageModes.NpcFromStartBlock] = SpeakTypesSettings.privateNpcToPlayer,
  [MessageModes.Spell] = SpeakTypesSettings.consoleYellow,

  -- ignored types
  --[MessageModes.Spell] = SpeakTypesSettings.none,
  [MessageModes.Potion] = SpeakTypesSettings.potion,

  [MessageModes.BarkLow] = SpeakTypesSettings.consoleOrange,
  [MessageModes.BarkLoud] = SpeakTypesSettings.consoleOrange,
  [MessageModes.Failure] = SpeakTypesSettings.statusSmall,
  [MessageModes.Login] = SpeakTypesSettings.bottomWhite,
  [MessageModes.Game] = SpeakTypesSettings.centerWhite,
  [MessageModes.Status] = SpeakTypesSettings.status,
  [MessageModes.Warning] = SpeakTypesSettings.centerRed,
  [MessageModes.Look] = SpeakTypesSettings.centerGreen,
  [MessageModes.Loot] = SpeakTypesSettings.centerWhiteColored,
  [MessageModes.Red] = SpeakTypesSettings.consoleRed,
  [MessageModes.Blue] = SpeakTypesSettings.consoleBlue,

  [MessageModes.GamemasterBroadcast] = SpeakTypesSettings.consoleRed,

  [MessageModes.DamageDealed] = SpeakTypesSettings.statusOwn,
  [MessageModes.DamageReceived] = SpeakTypesSettings.statusOwn,
  [MessageModes.Heal] = SpeakTypesSettings.statusOwn,
  [MessageModes.Exp] = SpeakTypesSettings.statusOwn,

  [MessageModes.DamageOthers] = SpeakTypesSettings.statusOthers,
  [MessageModes.HealOthers] = SpeakTypesSettings.statusOthers,
  [MessageModes.ExpOthers] = SpeakTypesSettings.statusOthers,

  [MessageModes.TradeNpc] = SpeakTypesSettings.centerGreen,
  [MessageModes.Guild] = SpeakTypesSettings.centerWhite,
  [MessageModes.Party] = SpeakTypesSettings.centerGreen,
  [MessageModes.PartyManagement] = SpeakTypesSettings.centerWhite,
  [MessageModes.TutorialHint] = SpeakTypesSettings.centerWhite,
  [MessageModes.BeyondLast] = SpeakTypesSettings.centerWhite,
  [MessageModes.Report] = SpeakTypesSettings.consoleRed,
  [MessageModes.GameHighlight] = SpeakTypesSettings.centerRed,
  [MessageModes.HotkeyUse] = SpeakTypesSettings.centerHKGreen,

  [MessageModes.BoostedMessage] = SpeakTypesSettings.statusBoosted,
  [MessageModes.Market] = SpeakTypesSettings.consoleRed, -- necessita fazer a UI
  [MessageModes.Notification] = SpeakTypesSettings.statusOwn,

  [254] = SpeakTypesSettings.private

}

ControlButtonNames = {
  ["skillsWidget"] = "Skills",
  ["battleListWidget"] = "Battle List",
  ["partyWidget"] = "Party List",
  ["vipWidget"] = "VIP List",
  ["spellListWidget"] = "Spell List",
  ["skillWheelDialog"] = "Wheel of Destiny",
  ["questDialog"] = "Quest Log",
  ["questTrackerWidget"] = "Quest Tracker",
  ["unjustifiedPoinsWidget"] = "Unjustified Points",
  ["preyDialog"] = "Prey Dialog",
  ["preyWidget"] = "Prey",
  ["rewardWallDialog"] = "Reward Wall",
  ["analyticsSelectorWidget"] = "Analytics Selector",
  ["compendiumDialog"] = "Compendium",
  ["cyclopediaDialog"] = "Cyclopedia",
  ["bosstiaryDialog"] = "Bosstiary",
  ["bossslotsDialog"] = "Boss Slots",
  ["bosstiaryTrackerWidget"] = "Bosstiary Tracker",
  ["bestiaryTrackerWidget"] = "Bestiary Tracker",
  ["imbuementTrackerWidget"] = "Imbuement Tracker",
  ["exaltationForgeDialog"] = "Exaltation Forge",
  ["friendsDialog"] = "Social",
  ["lenshelpFunction"] = "Minimap",
  ["highscoresDialog"] = "Highscores",
  ["helperDialog"] = "Helper",
  ["playerGuide"] = "Player Guide",
  ["manageShortcuts"] = "Manage Buttons",
  ["weaponProficiency"] = "Weapon Proficiency"
}

ControlButtonTooltips = {
  ["skillsWidget"] = "%s skills window (Alt+S)",
  ["battleListWidget"] = "%s battle list (Ctrl+B)",
  ["partyWidget"] = "%s party list",
  ["vipWidget"] = "%s VIP list (Ctrl+P)",
  ["spellListWidget"] = "%s spell list",
  ["skillWheelDialog"] = "%s Wheel of Destiny",
  ["questDialog"] = "%s quest log",
  ["questTrackerWidget"] = "%s quest tracker window",
  ["unjustifiedPoinsWidget"] = "%s unjustified points window",
  ["preyDialog"] = "%s prey dialog",
  ["preyWidget"] = "%s prey window",
  ["rewardWallDialog"] = "%s reward wall",
  ["analyticsSelectorWidget"] = "%s analytics selector window",
  ["compendiumDialog"] = "%s compendium",
  ["cyclopediaDialog"] = "%s Astra Cyclopedia",
  ["bosstiaryDialog"] = "%s Bosstiary Dialog",
  ["bossslotsDialog"] = "%s Boss Slots Dialog",
  ["bosstiaryTrackerWidget"] = "%s Bosstiary tracker window",
  ["bestiaryTrackerWidget"] = "%s Bestiary tracker window",
  ["imbuementTrackerWidget"] = "%s imbuement tracker window",
  ["exaltationForgeDialog"] = "%s Exaltation Forge",
  ["friendsDialog"] = "%s Social dialog",
  ["lenshelpFunction"] = "%s Minimap",
  ["highscoresDialog"] = "%s highscores dialog",
  ["helperDialog"] = "%s Helper window",
  ["playerGuide"] = "%s Player Guide widget",
  ["manageShortcuts"] = "%s Manage Control Buttons",
  ["weaponProficiency"] = "%s Weapon Proficiency"
}

ANALYZER_HEAL = 0
ANALYZER_DAMAGE_DEALT = 1
ANALYZER_DAMAGE_RECEIVED = 2

PriceTypeEnum = {
	Market = 0,
	Leader = 1,
}

CREATURE_BUTTON_SELECTION_TYPES = {
  TARGETING = 1,
  FOLLOWING = 2,
  HEALING = 4,
  ATTACKING = 8,
}

ContainerSortType = {
	ascendingName = 0,
	descendingName = 1,
	ascendingWeight = 2,
	descendingWeight = 3,
	ascendingExpiry = 4,
	descendingExpiry = 5,
	ascendingStackSize = 6,
	descendingStackSize = 7,
}

smartList = {
  [30403] = 30402, [23542] = 23526, [23543] = 23527, [23544] = 23528,
  [30345] = 30344, [30344] = 30345, [30342] = 30343, [39233] = 39234, [22061] = 22134,
  [3098] = 3100, [39180] = 39181, [39186] = 39187, [39183] = 39184,
  [3092] = 3095, [31557] = 31616, [39177] = 39178, [9392] = 9393,
  [3093] = 3096, [6299] = 6300, [3097] = 3099, [32621] = 32635, 
  [3051] = 3088, [3052] = 3089, [2203] = 2166, [3050] = 3087,
  [23529] = 23530, [23531] = 23532, [23533] = 23534, [908] = 908,
  [12669] = 12670, [3049] = 3086, [3091] = 3094, [3053] = 3090,
  [24790] = 24717, [24717] = 24790, [16114] = 16264,
  [23477] = 23476, [50150] = 50151, [50152] = 50153,
  [6529] = 3549, [9019] = 9018
}


HelperCastTypes = {
  TYPE_SPELL = 1,
  TYPE_RUNE = 2
}
ENumericSoundType = {
  UNKNOWN = 1000,
  SPELL_ATTACK = 1001,
  SPELL_HEALING = 1002,
  SPELL_SUPPORT = 1003,
  WEAPON_ATTACK = 1004,
  CREATURE_NOISE = 1005,
  CREATURE_DEATH = 1006,
  CREATURE_ATTACK = 1007,
  AMBIENCE_STREAM = 1008,
  FOOD_AND_DRINK = 1009,
  ITEM_MOVEMENT = 1010,
  EVENT = 1011,
  UI = 1012,
  WHISPER_WITHOUT_OPEN_CHAT = 1013,
  CHAT_MESSAGE = 1014,
  PARTY = 1015,
  VIP_LIST = 1016,
  RAID_ANNOUNCEMENT = 1017,
  SERVER_MESSAGE = 1018,
  SPELL_GENERIC = 1019,
}
