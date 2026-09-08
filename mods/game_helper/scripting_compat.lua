-- ZeroBot compatibility layer for EloriaBot player scripting.
--
-- Purpose: let a script written against the ZeroBot API run unmodified. This
-- module only adds names, enum tables and event plumbing on top of the
-- restricted API built by scripting_actions.lua -- it never widens what a
-- script may actually do. Every action still runs through the same token
-- buckets and the same "am I online" check, and still uses the ordinary game
-- protocol.
--
-- Where ZeroBot's numeric enum values disagree with this client's protocol the
-- *name* is kept and the *value* is corrected, so symbolic script code keeps
-- working (see Enums.Directions).
local compat = {}

_Helper = _Helper or {}
_Helper.ScriptingCompat = compat

local MAX_MODAL_WINDOWS = 5
local MAX_MODAL_BUTTONS = 20
local MAX_CAPTION_LENGTH = 64
local MAX_DESCRIPTION_LENGTH = 54
local MAX_BUTTON_TEXT_LENGTH = 40

local actions = nil
local stylesImported = false

-- Numeric event ids, identical to ZeroBot's Game.Events.
local EVENTS = {
  TALK = 0,
  MAGIC_EFFECT = 1,
  HUD_CLICK = 2,
  HOTKEY_SHORTCUT_PRESS = 3,
  TEXT_MESSAGE = 4,
  MODAL_WINDOW = 5,
  CUSTOM_MODAL_WINDOW_BUTTON_CLICK = 6,
  IMBUEMENT_DATA = 7,
  IMBUEMENT_OPEN_WINDOW = 8,
  QUEST_LOG = 9,
  QUEST_LINES = 10,
  DISTANCE_SHOOT_EFFECT = 11,
  PARTY_HUNT = 12,
  LABEL = 13,
  OPEN_STASH = 14,
  HUD_DRAG = 15,
  STORE_CATEGORIES = 16,
  STORE_OFFERS = 17,
  OPEN_DAILY_REWARD = 18,
  DAILY_REWARD_DAYS_DATA = 19,
  ALARM = 20,
  TASK_HUNTING_DATA = 21
}
compat.EVENTS = EVENTS

--------------------------------------------------------------------------------
-- Enums
--------------------------------------------------------------------------------

local function buildEnums()
  local enums = {}

  enums.HorizontalAlign = { None = 0, Left = 1, Center = 2, Right = 3 }
  enums.VerticalAlign = { None = 0, Top = 1, Center = 2, Bottom = 3 }

  -- ZeroBot exposes the TFS direction order (SOUTHWEST = 4). This client speaks
  -- the Tibia protocol order (NORTHEAST = 4), so the names are kept and the
  -- values corrected: Game.walk(Enums.Directions.SOUTHWEST) really walks
  -- south-west here instead of north-east.
  enums.Directions = {
    NORTH = 0, EAST = 1, SOUTH = 2, WEST = 3,
    NORTHEAST = 4, SOUTHEAST = 5, SOUTHWEST = 6, NORTHWEST = 7,
    NORTH_EAST = 4, SOUTH_EAST = 5, SOUTH_WEST = 6, NORTH_WEST = 7,
    DIAGONAL_MASK = 4, INVALIDDIRECTION = 8
  }

  enums.TalkTypes = {
    TALKTYPE_SAY = 1, TALKTYPE_WHISPER = 2, TALKTYPE_YELL = 3,
    TALKTYPE_PRIVATE_PN = 11, TALKTYPE_PRIVATE = 5, TALKTYPE_CHANNEL = 7,
    SAY = 1, WHISPER = 2, YELL = 3, PRIVATE = 5, CHANNEL = 7, NPC = 11
  }

  enums.InventorySlot = {
    CONST_SLOT_HEAD = 1, CONST_SLOT_NECKLACE = 2, CONST_SLOT_BACKPACK = 3,
    CONST_SLOT_ARMOR = 4, CONST_SLOT_RIGHT = 5, CONST_SLOT_LEFT = 6,
    CONST_SLOT_LEGS = 7, CONST_SLOT_FEET = 8, CONST_SLOT_RING = 9,
    CONST_SLOT_AMMO = 10, CONST_SLOT_STORE_INBOX = 11,
    HEAD = 1, NECKLACE = 2, BACKPACK = 3, ARMOR = 4, RIGHT_HAND = 5,
    LEFT_HAND = 6, LEGS = 7, FEET = 8, RING = 9, AMMO = 10, PURSE = 11
  }

  enums.FightMode = {
    FIGHTMODE_ATTACK = 1, FIGHTMODE_BALANCED = 2, FIGHTMODE_DEFENSE = 3,
    OFFENSIVE = 1, BALANCED = 2, DEFENSIVE = 3
  }
  enums.ChaseMode = { STAND = 0, CHASE = 1 }

  enums.States = {
    STATE_POISON = 0, STATE_BURN = 1, STATE_ENERGY = 2, STATE_DRUNK = 3,
    STATE_MANASHIELD = 4, STATE_PARALYZE = 5, STATE_HASTE = 6, STATE_SWORDS = 7,
    STATE_DROWNING = 8, STATE_FREEZING = 9, STATE_DAZZLED = 10,
    STATE_CURSED = 11, STATE_PARTY_BUFF = 12, STATE_REDSWORDS = 13,
    STATE_PIGEON = 14, STATE_BLEEDING = 15, STATE_SUFFERING_LESSER_HEX = 16,
    STATE_SUFFERING_INTENSER_HEX = 17, STATE_SUFFERING_GREATER_HEX = 18,
    STATE_ROOTED = 19, STATE_FEARED = 20, STATE_CURSE_I = 21,
    STATE_CURSE_II = 22, STATE_CURSE_III = 23, STATE_CURSE_IV = 24,
    STATE_CURSE_V = 25, STATE_MAGIC_SHIELD = 26, STATE_AGONY = 27
  }

  enums.CreatureTypes = {
    CREATURETYPE_PLAYER = 0, CREATURETYPE_MONSTER = 1, CREATURETYPE_NPC = 2,
    CREATURETYPE_SUMMONPLAYER = 3, CREATURETYPE_SUMMON_OWN = 3,
    CREATURETYPE_SUMMON_OTHERS = 4, CREATURETYPE_HIDDEN = 5
  }

  enums.Skulls = {
    SKULL_NONE = 0, SKULL_YELLOW = 1, SKULL_GREEN = 2, SKULL_WHITE = 3,
    SKULL_RED = 4, SKULL_BLACK = 5, SKULL_ORANGE = 6
  }

  enums.PartyIcons = {
    SHIELD_NONE = 0, SHIELD_WHITEYELLOW = 1, SHIELD_WHITEBLUE = 2,
    SHIELD_BLUE = 3, SHIELD_YELLOW = 4, SHIELD_BLUE_SHAREDEXP = 5,
    SHIELD_YELLOW_SHAREDEXP = 6, SHIELD_BLUE_NOSHAREDEXP_BLINK = 7,
    SHIELD_YELLOW_NOSHAREDEXP_BLINK = 8, SHIELD_BLUE_NOSHAREDEXP = 9,
    SHIELD_YELLOW_NOSHAREDEXP = 10, SHIELD_GRAY = 11
  }

  enums.GuildEmblem = {
    GUILDEMBLEM_NONE = 0, GUILDEMBLEM_ALLY = 1, GUILDEMBLEM_ENEMY = 2,
    GUILDEMBLEM_NEUTRAL = 3, GUILDEMBLEM_MEMBER = 4, GUILDEMBLEM_OTHER = 5
  }

  enums.Vocations = {
    NONE = 0, KNIGHT = 1, PALADIN = 2, SORCERER = 3, DRUID = 4, MONK = 5,
    MASTER_SORCERER = 6, ELDER_DRUID = 7, ROYAL_PALADIN = 8, ELITE_KNIGHT = 9,
    EXALTED_MONK = 15
  }

  enums.SpellGroups = {
    SPELLGROUP_NONE = 0, SPELLGROUP_ATTACK = 1, SPELLGROUP_HEALING = 2,
    SPELLGROUP_SUPPORT = 3, SPELLGROUP_POWERSTRIKES = 4, SPELLGROUP_CONJURE = 5,
    SPELLGROUP_CRIPPLING = 6, SPELLGROUP_FOCUS = 7,
    SPELLGROUP_ULTIMATESTRIKES = 8, SPELLGROUP_GREATBEAMS = 9,
    SPELLGROUP_BURSTS_OF_NATURE = 10, SPELLGROUP_STANCE = 11
  }
  enums.SpellGroups.SPELLGROUP_SPECIAL = enums.SpellGroups.SPELLGROUP_POWERSTRIKES
  enums.SpellGroups.SPELLGROUP_BURSTS = enums.SpellGroups.SPELLGROUP_BURSTS_OF_NATURE
  enums.SpellGroups.SPELLGROUP_VIRTUE = enums.SpellGroups.SPELLGROUP_STANCE

  enums.MessageTypes = {
    MESSAGE_STATUS_CONSOLE_RED = 13, MESSAGE_STATUS_DEFAULT = 17,
    MESSAGE_STATUS_WARNING = 18, MESSAGE_EVENT_ADVANCE = 19,
    MESSAGE_STATUS_SMALL = 21, MESSAGE_INFO_DESCR = 22,
    MESSAGE_DAMAGE_DEALT = 23, MESSAGE_DAMAGE_RECEIVED = 24, MESSAGE_HEALED = 25,
    MESSAGE_EXPERIENCE = 26, MESSAGE_DAMAGE_OTHERS = 27,
    MESSAGE_HEALED_OTHERS = 28, MESSAGE_EXPERIENCE_OTHERS = 29,
    MESSAGE_EVENT_DEFAULT = 30, MESSAGE_LOOT = 31, MESSAGE_GUILD = 33,
    MESSAGE_PARTY_MANAGEMENT = 34, MESSAGE_PARTY = 35, MESSAGE_EVENT_ORANGE = 36,
    MESSAGE_STATUS_CONSOLE_ORANGE = 37, MESSAGE_REPORT = 38, MESSAGE_HOTKEY = 39,
    MESSAGE_TUTORIAL_HINT = 40, MESSAGE_THANK_YOU = 41, MESSAGE_MARKET = 42,
    MESSAGE_MANA = 43, MESSAGE_BEYOND_LAST = 44, MESSAGE_ATTENTION = 48,
    MESSAGE_BOOSTED_CREATURE = 49, MESSAGE_OFFLINE_TRAINING = 50,
    MESSAGE_TRANSACTION = 51, MESSAGE_POTION = 52
  }

  enums.BlessingState = { UNDEFINED = -1, NONE = 0, NORMAL = 1, FULL = 2 }
  enums.QuestState = { PENDING = 0, COMPLETED = 1 }
  enums.FlagModifiers = { CONTROL = 0x1, ALT = 0x2, SHIFT = 0x4, NUMLOCK = 0x8 }
  enums.WalkMode = { MAP_CLICK = 0, ARROW_KEYS = 1 }
  enums.SpecialAreaType = { SPECIAL_AREA_ALL = 0, SPECIAL_AREA_CAVEBOT = 1, SPECIAL_AREA_TARGETING = 2 }
  enums.CreatureIconType = { QUEST = 0, MODIFIER = 1 }
  enums.MonkPassiveType = {
    MONK_PASSIVE_VIRTUE_NONE = 0, MONK_PASSIVE_VIRTUE_HARMONY = 1,
    MONK_PASSIVE_VIRTUE_JUSTICE = 2, MONK_PASSIVE_VIRTUE_SUSTAIN = 3
  }
  enums.DailyRewardType = {
    DAILY_REWARD_TYPE_ITEMS = 1, DAILY_REWARD_TYPE_PREY_REROLL = 2,
    DAILY_REWARD_TYPE_XP_BOOST = 3
  }
  enums.GameStoreOfferType = {
    GAMESTORE_OFFER_TYPE_NONE = 0, GAMESTORE_OFFER_TYPE_MOUNT = 1,
    GAMESTORE_OFFER_TYPE_OUTFIT = 2, GAMESTORE_OFFER_TYPE_ITEM = 3,
    GAMESTORE_OFFER_TYPE_HIRELING = 4
  }
  enums.GameStoreCoinType = { GAMESTORE_COIN_TYPE = 0, GAMESTORE_TRANSFERABLE_COIN_TYPE = 1 }
  enums.GameStoreState = {
    GAMESTORE_CATEGORY_NONE = 0, GAMESTORE_CATEGORY_NEW = 1,
    GAMESTORE_CATEGORY_SALE = 2, GAMESTORE_CATEGORY_TIMED = 3
  }
  enums.PreyTaskDataState = {
    PREY_TASK_DATA_STATE_LOCKED = 0, PREY_TASK_DATA_STATE_INACTIVE = 1,
    PREY_TASK_DATA_STATE_SELECTION = 2, PREY_TASK_DATA_STATE_LIST_SELECTION = 3,
    PREY_TASK_DATA_STATE_ACTIVE = 4, PREY_TASK_DATA_STATE_COMPLETED = 5
  }
  enums.AlarmType = {
    DISCONNECTED = 0, DAMAGE_TAKEN = 1, LOW_HEALTH = 2, PRIVATE_MESSAGE = 3,
    MONSTER_DETECTED = 4, MONSTER_ON_SCREEN = 5, PLAYER_ATTACK = 6,
    PLAYER_DETECTED = 7, PLAYER_ON_SCREEN = 8, PLAYER_STUCK = 9,
    SKULL_DETECTED = 10, SKULL_ON_SCREEN = 11, ENEMY_DETECTED = 12,
    ENEMY_ON_SCREEN = 13, GM_DETECTED = 14, LOW_CAP = 15, PLAYER_IDLE = 16
  }
  enums.CreatureIcons = {
    CREATURE_ICON_NONE = 0, CREATURE_ICON_HIGHER_DAMAGE_RECEIVED = 1,
    CREATURE_ICON_LOWER_DAMAGE_DEALT = 2, CREATURE_ICON_TURNED_MELEE = 3,
    CREATURE_ICON_INFLUENCED = 4, CREATURE_ICON_FIENDISH = 5,
    CREATURE_ICON_REDUCED_HEALTH = 6
  }
  enums.CreatureQuestIcons = {
    CREATURE_QUEST_ICON_NONE = 0, CREATURE_QUEST_ICON_WHITECROSS = 1,
    CREATURE_QUEST_ICON_REDCROSS = 2, CREATURE_QUEST_ICON_REDBALL = 3,
    CREATURE_QUEST_ICON_GREENBALL = 4, CREATURE_QUEST_ICON_REDGREENBALL = 5,
    CREATURE_QUEST_ICON_GREENSHIELD = 6, CREATURE_QUEST_ICON_YELLOWSHIELD = 7,
    CREATURE_QUEST_ICON_BLUESHIELD = 8, CREATURE_QUEST_ICON_PURPLESHIELD = 9,
    CREATURE_QUEST_ICON_REDSHIELD = 10, CREATURE_QUEST_ICON_DOVE = 11,
    CREATURE_QUEST_ICON_ENERGY = 12, CREATURE_QUEST_ICON_EARTH = 13,
    CREATURE_QUEST_ICON_WATER = 14, CREATURE_QUEST_ICON_FIRE = 15,
    CREATURE_QUEST_ICON_ICE = 16, CREATURE_QUEST_ICON_ARROWUP = 17,
    CREATURE_QUEST_ICON_ARROWDOWN = 18, CREATURE_QUEST_ICON_EXCLAMATIONMARK = 19,
    CREATURE_QUEST_ICON_QUESTIONMARK = 20, CREATURE_QUEST_ICON_CANCELMARK = 21,
    CREATURE_QUEST_ICON_HAZARD = 22, CREATURE_QUEST_ICON_BROWNSKULL = 23,
    CREATURE_QUEST_ICON_BLOODDROP = 24
  }
  enums.WaypointType = {
    WAYPOINT_TYPE_STAND = 0, WAYPOINT_TYPE_NODE = 1, WAYPOINT_TYPE_START_LURE = 2,
    WAYPOINT_TYPE_END_LURE = 3, WAYPOINT_TYPE_ROPE = 4, WAYPOINT_TYPE_LADDER = 5,
    WAYPOINT_TYPE_HOLE = 6, WAYPOINT_TYPE_USE = 7, WAYPOINT_TYPE_TELEPORT = 8,
    WAYPOINT_TYPE_LABEL = 9, WAYPOINT_TYPE_GOTO = 10, WAYPOINT_TYPE_SCRIPT = 11,
    WAYPOINT_TYPE_DYNAMIC_START_LURE = 12, WAYPOINT_TYPE_DYNAMIC_END_LURE = 13,
    WAYPOINT_TYPE_DOOR = 14, WAYPOINT_TYPE_HUR_UP = 15,
    WAYPOINT_TYPE_HUR_DOWN = 16, WAYPOINT_TYPE_MACHETE = 17
  }

  enums.ThingFlagAttr = { None = 0 }
  local flagNames = {
    'Ground', 'GroundBorder', 'OnBottom', 'OnTop', 'Container', 'Stackable',
    'ForceUse', 'MultiUse', 'Writable', 'Chargeable', 'WritableOnce',
    'FluidContainer', 'Splash', 'NotWalkable', 'NotMoveable', 'BlockProjectile',
    'NotPathable', 'NoMovementAnimation', 'Pickupable', 'Hangable', 'HookSouth',
    'HookEast', 'Rotateable', 'Light', 'DontHide', 'Translucent', 'Displacement',
    'Elevation', 'LyingCorpse', 'AnimateAlways', 'MinimapColor', 'LensHelp'
  }
  for index, name in ipairs(flagNames) do
    enums.ThingFlagAttr[name] = bit.lshift(1, index - 1)
  end

  return enums
end

local ENUMS = buildEnums()
compat.Enums = ENUMS

--------------------------------------------------------------------------------
-- Native game hooks
--
-- Each hook is connected the first time a script registers for it and stays
-- connected until the scripting runtime is torn down. All of them forward into
-- scripting.lua's dispatcher, which pcalls every callback, so a broken script
-- can never take down the client's own game callbacks.
--------------------------------------------------------------------------------

local hooks = {}
local connectedHooks = {}
local npcTradeItems = {}

local function dispatch(eventId, ...)
  local scripting = _Helper.Scripting
  if scripting and scripting.dispatch then scripting.dispatch(eventId, ...) end
end

local function tupleList(list)
  local result = {}
  for index, entry in ipairs(list or {}) do
    if type(entry) == 'table' then
      result[index] = { id = tonumber(entry[1]) or 0, text = tostring(entry[2] or '') }
    end
  end
  return result
end

hooks[EVENTS.MODAL_WINDOW] = {
  onModalDialog = function(id, title, message, buttons, enterButton, escapeButton, choices, priority)
    dispatch(EVENTS.MODAL_WINDOW, {
      id = tonumber(id) or 0,
      title = tostring(title or ''),
      message = tostring(message or ''),
      buttons = tupleList(buttons),
      choices = tupleList(choices),
      defaultEnterButton = tonumber(enterButton) or 255,
      defaultEscapeButton = tonumber(escapeButton) or 255,
      priority = priority == true and 1 or 0
    })
  end
}

hooks[EVENTS.TEXT_MESSAGE] = {
  onTextMessage = function(mode, text)
    dispatch(EVENTS.TEXT_MESSAGE, {
      messageType = tonumber(mode) or 0,
      text = tostring(text or ''),
      channelId = 0,
      x = 0, y = 0, z = 0,
      messagePrimaryValue = 0, messagePrimaryColor = 0,
      messageSecondaryValue = 0, messageSecondaryColor = 0
    })
  end
}

hooks[EVENTS.TALK] = {
  onTalk = function(name, level, mode, text, channelId, pos)
    pos = type(pos) == 'table' and pos or {}
    dispatch(EVENTS.TALK,
      tostring(name or ''), tonumber(level) or 0, tonumber(mode) or 0,
      tonumber(pos.x) or 0, tonumber(pos.y) or 0, tonumber(pos.z) or 0,
      tostring(text or ''), tonumber(channelId) or 0)
  end
}

hooks[EVENTS.QUEST_LOG] = {
  onQuestLog = function(quests) dispatch(EVENTS.QUEST_LOG, quests) end
}

hooks[EVENTS.QUEST_LINES] = {
  onQuestLine = function(questId, missions) dispatch(EVENTS.QUEST_LINES, questId, missions) end
}

-- Not a script-visible event: keeps the id -> item map that Npc.buy/sell need,
-- because the client's buyItem/sellItem take an item object, not an id.
local tradeHook = {
  onOpenNpcTrade = function(items)
    npcTradeItems = {}
    for _, entry in ipairs(items or {}) do
      local item = type(entry) == 'table' and entry[1] or entry
      local ok, itemId = pcall(function() return item:getId() end)
      if ok and itemId and not npcTradeItems[itemId] then npcTradeItems[itemId] = item end
    end
  end,
  onCloseNpcTrade = function() npcTradeItems = {} end
}

function compat.onEventRegistered(eventId)
  local hook = hooks[eventId]
  if not hook or connectedHooks[eventId] then return end
  connectedHooks[eventId] = true
  connect(g_game, hook)
end

--------------------------------------------------------------------------------
-- CustomModalWindow
--------------------------------------------------------------------------------

local modalRecords = {}
local modalWindows = {}
local modalCount = 0
local nextModalId = 0

local function importModalStyle()
  if stylesImported then return true end
  stylesImported = pcall(function() g_ui.importStyle('styles/scripting_modal') end)
  return stylesImported
end

local function clampText(value, maximum)
  return (tostring(value or ''):gsub('[\r\n]', ' ')):sub(1, maximum)
end

local ModalMethods = {}
local ModalMeta = { __index = ModalMethods }

local function requireModal(object)
  local record = modalRecords[object]
  if not record or record.destroyed then return nil end
  if not record.window or record.window:isDestroyed() then return nil end
  return record
end

function ModalMethods:getId()
  local record = modalRecords[self]
  return record and record.id or -1
end

function ModalMethods:setCaption(caption)
  local record = requireModal(self)
  if record then record.window:setText(clampText(caption, MAX_CAPTION_LENGTH)) end
end

function ModalMethods:setDescription(description)
  local record = requireModal(self)
  if not record then return end
  local label = record.window:recursiveGetChildById('descriptionLabel')
  if label then label:setText(clampText(description, MAX_DESCRIPTION_LENGTH)) end
end

function ModalMethods:setCallback(callback)
  local record = modalRecords[self]
  if record then record.callback = type(callback) == 'function' and callback or nil end
end

-- Returns the 0-based button index, matching ZeroBot.
function ModalMethods:addButton(buttonText)
  local record = requireModal(self)
  if not record then return -1 end
  if #record.buttons >= MAX_MODAL_BUTTONS then return -1 end

  local panel = record.window:recursiveGetChildById('buttonPanel')
  if not panel then return -1 end

  local buttonIndex = #record.buttons
  local button = g_ui.createWidget('ScriptingModalButton', panel)
  button:setText(clampText(buttonText, MAX_BUTTON_TEXT_LENGTH))
  button.onClick = function()
    if record.destroyed then return end
    dispatch(EVENTS.CUSTOM_MODAL_WINDOW_BUTTON_CLICK, record.id, buttonIndex)
  end
  table.insert(record.buttons, button)

  record.window:setHeight(math.min(420, 80 + #record.buttons * 23))
  return buttonIndex
end

function ModalMethods:destroy()
  local record = modalRecords[self]
  if not record or record.destroyed then return end
  record.destroyed = true
  if record.window and not record.window:isDestroyed() then record.window:destroy() end
  modalRecords[self] = nil
  modalWindows[record.id] = nil
  modalCount = math.max(0, modalCount - 1)
end

local function newModalWindow(caption, description)
  if modalCount >= MAX_MODAL_WINDOWS then
    error('custom modal window limit reached (' .. MAX_MODAL_WINDOWS .. ')')
  end
  if not importModalStyle() then error('scripting modal style is not available') end

  local parent = rootWidget
  if not parent then error('game window is not available') end

  local window = g_ui.createWidget('ScriptingModalWindow', parent)
  window:setText(clampText(caption, MAX_CAPTION_LENGTH))
  local label = window:recursiveGetChildById('descriptionLabel')
  if label then label:setText(clampText(description, MAX_DESCRIPTION_LENGTH)) end

  local object = setmetatable({}, ModalMeta)
  local record = { id = nextModalId, window = window, buttons = {}, destroyed = false }
  nextModalId = nextModalId + 1
  modalCount = modalCount + 1
  modalRecords[object] = record
  modalWindows[record.id] = object

  local closeButton = window:recursiveGetChildById('closeButton')
  if closeButton then closeButton.onClick = function() object:destroy() end end
  window.onEscape = function() object:destroy() end

  return object
end

function compat.destroyAllModals()
  local objects = {}
  for object in pairs(modalRecords) do table.insert(objects, object) end
  for _, object in ipairs(objects) do object:destroy() end
  modalCount = 0
end

-- Bridges the CUSTOM_MODAL_WINDOW_BUTTON_CLICK event onto the per-window
-- callback, exactly like ZeroBot's onCustomModalButtonOnClick does.
function compat.onCustomModalButtonClick(modalId, buttonIndex)
  local object = modalWindows[modalId]
  local record = object and modalRecords[object] or nil
  if not record or record.destroyed or not record.callback then return end
  record.callback(buttonIndex)
end

function compat.reset()
  for eventId in pairs(connectedHooks) do
    disconnect(g_game, hooks[eventId])
  end
  connectedHooks = {}
  compat.destroyAllModals()
end

--------------------------------------------------------------------------------
-- Engine (maps onto the EloriaBot panels that already exist)
--------------------------------------------------------------------------------

local function enableButton(id)
  local buttons = _Helper.getEnableButtons and _Helper.getEnableButtons()
  return buttons and buttons:recursiveGetChildById(id) or nil
end

local function readCheckbox(id)
  local widget = enableButton(id)
  return widget and widget:isChecked() == true or false
end

local function writeCheckbox(id, enabled)
  local widget = enableButton(id)
  if not widget then return false end
  enabled = enabled == true
  if widget:isChecked() == enabled then return true end
  widget:setChecked(enabled)
  -- setChecked does not fire onClick, so mirror what a real click would do.
  if widget.onCheckChange then pcall(widget.onCheckChange, widget, enabled) end
  return true
end

local function getCavebot()
  return modules.game_helper and modules.game_helper.cavebot or nil
end

local function buildEngine()
  local engine = {}
  local perform = actions.perform

  engine.getBotVersion = function() return 'EloriaBot' end
  engine.isBotEnabled = function()
    return _Helper.isHelperAutomaticFunctionsEnabled and
      _Helper.isHelperAutomaticFunctionsEnabled() == true or false
  end
  engine.enableBot = function(enable)
    if not _Helper.setHelperAutomaticFunctionsEnabled then return false end
    return perform('mode', function()
      _Helper.setHelperAutomaticFunctionsEnabled(enable == true)
      return true
    end)
  end

  engine.isHealingEnabled = engine.isBotEnabled
  engine.enableHealing = engine.enableBot

  engine.isTargetingEnabled = function() return readCheckbox('enableAutoTarget') end
  engine.enableTargeting = function(enable)
    return perform('mode', function() return writeCheckbox('enableAutoTarget', enable) end)
  end

  engine.isMagicShooterEnabled = function() return readCheckbox('enableMagicShooter') end
  engine.enableMagicShooter = function(enable)
    return perform('mode', function() return writeCheckbox('enableMagicShooter', enable) end)
  end

  engine.isEquipmentEnabled = function() return readCheckbox('enableEquipment') end
  engine.enableEquipment = function(enable)
    return perform('mode', function() return writeCheckbox('enableEquipment', enable) end)
  end

  engine.isTimerEnabled = function() return readCheckbox('enableTimer') end
  engine.enableTimer = function(enable)
    return perform('mode', function() return writeCheckbox('enableTimer', enable) end)
  end

  engine.isHealFriendEnabled = function()
    local config = _Helper.getHelperConfig and _Helper.getHelperConfig() or nil
    return type(config) == 'table' and type(config.namedSio) == 'table' and
      config.namedSio.enabled == true or false
  end
  engine.enableHealFriend = function(enable)
    return perform('mode', function() return writeCheckbox('enableNamedSio', enable) end)
  end

  engine.isCaveBotEnabled = function()
    local cavebot = getCavebot()
    return cavebot and cavebot.isRunning and cavebot.isRunning() == true or false
  end
  engine.enableCaveBot = function(enable)
    local cavebot = getCavebot()
    if not cavebot or not cavebot.toggle then return false end
    return perform('mode', function() return cavebot.toggle(enable == true) ~= false end)
  end

  -- Features EloriaBot has no equivalent for. They answer honestly instead of
  -- erroring, so a ZeroBot script that probes them keeps running.
  for _, name in ipairs({
    'isAutoSSAEnabled', 'isHoldTargetEnabled', 'isAutoMightRingEnabled',
    'isAntiPushEnabled', 'isRuneMaxEnabled', 'isReconnectEnabled',
    'isAllAlarmsDisabled', 'isAlarmEnabled', 'isScriptLoaded'
  }) do
    engine[name] = function() return false end
  end

  for _, name in ipairs({
    'autoSSAEnable', 'holdTargetEnable', 'autoMightRingEnable', 'antiPushEnable',
    'runeMaxEnable', 'reconnectEnable', 'setFirstAntiPushId', 'setSecondAntiPushId',
    'setRuneMaxId', 'setAlarm', 'allAlarmsEnable', 'loadScript', 'unloadScript',
    'reloadScript', 'loadConfig', 'targetingSetProfileSettings',
    'magicShooterSwitchProfile', 'targetingSwitchProfile',
    'equipmentSwitchProfile', 'healingSwitchProfile'
  }) do
    engine[name] = function() return false end
  end

  for _, name in ipairs({
    'magicShooterGetProfile', 'targetingGetProfile', 'equipmentGetProfile',
    'healingGetProfile', 'getRuneMaxId', 'getLicenseTime'
  }) do
    engine[name] = function() return 0 end
  end

  for _, name in ipairs({
    'magicShooterGetProfileName', 'targetingGetProfileName',
    'equipmentGetProfileName', 'healingGetProfileName', 'getUserId',
    'getScriptsDirectory', 'getScriptsDirectoryUtf8'
  }) do
    engine[name] = function() return '' end
  end

  engine.targetingGetProfileSettings = function() return {} end

  return engine
end

--------------------------------------------------------------------------------
-- Install
--------------------------------------------------------------------------------

local function installEvents(environment)
  local game = environment.Game
  game.Events = {}
  for name, value in pairs(EVENTS) do game.Events[name] = value end

  game.modalWindowAnswer = function(id, button, choice, closeAfterAnswer)
    id = actions.integer(id, 0, 0xffffffff)
    button = actions.integer(button or 0, 0, 255)
    choice = actions.integer(choice or 0, 0, 255)
    if not id or not button or not choice then return false end
    -- ZeroBot defaults closeAfterAnswer to true. Answering the server does not
    -- take the client's own dialog widget down, so without this a scripted
    -- answer loop leaves a stack of dead windows on screen.
    if closeAfterAnswer == nil then closeAfterAnswer = true end
    return actions.perform('mode', function()
      g_game.answerModalDialog(id, button, choice)
      if closeAfterAnswer and modules.game_modaldialog and modules.game_modaldialog.destroyDialog then
        modules.game_modaldialog.destroyDialog()
      end
      return true
    end)
  end
end

local function installClient(environment)
  local client = environment.Client
  local game = environment.Game
  local perform = actions.perform

  -- ZeroBot puts the combat modes on Client; EloriaBot had them on Game only.
  client.getFightMode = game.getFightMode
  client.setFightMode = game.setFightMode
  client.getChaseMode = game.getChaseMode
  client.setChaseMode = game.setChaseMode

  client.getWorldName = function() return tostring(g_game.getWorldName() or '') end
  client.hasFocus = function() return g_window.hasFocus() == true end
  client.focus = function() return perform('mode', function() g_window.show(); return true end) end
  client.flashWindow = function() return perform('mode', function() g_window.flash(); return true end) end
  client.setWindowTitle = function(title)
    title = (tostring(title or ''):gsub('[\r\n]', ' ')):sub(1, 120)
    return perform('mode', function() g_window.setTitle(title); return true end)
  end
  client.isChatEnabled = function()
    return modules.game_console and modules.game_console.isChatEnabled and
      modules.game_console.isChatEnabled() == true or false
  end
  client.toggleChatEnabled = function()
    if not modules.game_console then return false end
    return perform('mode', function()
      if modules.game_console.isChatEnabled() then
        modules.game_console.disableChat()
      else
        modules.game_console.enableChat()
      end
      return true
    end)
  end
  client.isKeyPressed = function(key)
    if type(key) == 'string' then
      for code, description in pairs(KeyCodeDescs or {}) do
        if description == key then key = code break end
      end
    end
    key = actions.integer(key, 0, 0xffff)
    if not key then return false end
    return g_window.isKeyPressed(key) == true
  end
  client.getCursorMapPosition = function()
    local mapPanel = modules.game_interface and modules.game_interface.gameMapPanel
    if not mapPanel then return nil end
    local ok, position = pcall(function() return mapPanel:getPosition(g_window.getMousePosition()) end)
    return ok and actions.copyPosition(position) or nil
  end
  client.isTradeShopOpen = function() return next(npcTradeItems) ~= nil end

  -- Deliberately inert: session control is not something a script may drive.
  client.login = function() return false end
  client.logout = function() return false end
  client.XLog = function() return false end
  client.sendHotkey = function() return false end
  client.getMapIndexes = function() return {} end
  client.getAllItems = function() return {} end
  client.getAllMonsters = function() return {} end
  client.getMonsterByRaceId = function() return nil end
  client.getLootBlackWhitelist = function() return {} end
  client.setLootBlackWhitelist = function() return false end
end

local function installPlayerExtras(environment)
  local player = environment.Player
  local getLocalPlayer = actions.getLocalPlayer

  -- ZeroBot passes a state *index* (Enums.States), not a bitmask.
  player.getState = function(index)
    index = actions.integer(index, 0, 31)
    local localPlayer = getLocalPlayer()
    if not localPlayer or not index then return false end
    return bit.band(localPlayer:getStates(), bit.lshift(1, index)) ~= 0
  end

  player.isHungry = function()
    local localPlayer = getLocalPlayer()
    if not localPlayer then return false end
    return bit.band(localPlayer:getStates(), bit.lshift(1, 23)) ~= 0
  end

  -- No client-side source for these on this server. They report neutral values
  -- rather than raising, so scripts that read them keep running.
  for _, name in ipairs({
    'getXpBoostTime', 'getDusts', 'getDustsMaximum', 'getTotalGoldBalance',
    'getHuntingPoints', 'getPreyWildcards', 'getHarmony', 'getMonkPassiveType'
  }) do
    player[name] = function() return 0 end
  end
  for _, name in ipairs({ 'getHuntingTaskPrices', 'getUnjustifiedData', 'getStances' }) do
    player[name] = function() return {} end
  end
  player.isSerene = function() return false end
end

local function installNpc(environment)
  local npc = {}
  local perform = actions.perform

  local function tradeItem(itemId)
    itemId = actions.integer(itemId, 1, 65535)
    return itemId and npcTradeItems[itemId] or nil
  end

  npc.buy = function(itemId, amount, ignoreCap, inBackpacks)
    local item = tradeItem(itemId)
    amount = actions.integer(amount or 1, 1, 10000)
    if not item or not amount then return false end
    return perform('item', function()
      g_game.buyItem(item, amount, ignoreCap == true, inBackpacks == true)
      return true
    end)
  end

  npc.sell = function(itemId, amount, ignoreEquipped)
    local item = tradeItem(itemId)
    amount = actions.integer(amount or 1, 1, 10000)
    if not item or not amount then return false end
    return perform('item', function()
      g_game.sellItem(item, amount, ignoreEquipped == true)
      return true
    end)
  end

  environment.Npc = npc
end

local function installSound(environment)
  -- Restricted to the client's own sounds directory: a script may pick which
  -- bundled sound plays, never probe or read an arbitrary path.
  environment.Sound = {
    play = function(filePath)
      filePath = tostring(filePath or '')
      if filePath == '' or filePath:len() > 128 then return false end
      if filePath:find('%.%.', 1, true) or filePath:find('[:\\]') or filePath:sub(1, 1) == '/' then
        return false
      end
      return actions.perform('mode', function()
        g_sounds.play('/sounds/' .. filePath)
        return true
      end)
    end
  }
end

local function installUnsupportedGameActions(environment)
  -- ZeroBot exposes these; this client has no protocol support for them (and
  -- several are deliberately out of scope). They exist so a copied script does
  -- not die on a nil call, and they report failure honestly.
  local game = environment.Game
  for _, name in ipairs({
    'forgeConvertDust', 'forgeConvertSlivers', 'forgeIncreaseLimit',
    'applyImbuement', 'applyImbuementOnScroll', 'clearImbuement',
    'closeImbuementWindow', 'autoLoot', 'stashRetrieve', 'storeBuyOffer',
    'storeOpen', 'storeRequestOffers', 'collectDailyReward', 'openDailyReward',
    'huntingTaskRerollList', 'huntingTaskRerollRewards',
    'huntingTaskListAllMonsters', 'huntingTaskSelectMonster',
    'huntingTaskCancel', 'huntingTaskClaim', 'writeTextWindow',
    'requestQuestLog', 'requestQuestLines'
  }) do
    if not game[name] then game[name] = function() return false end end
  end
  game.storeGetTibiaCoinsBalance = function() return 0 end
  game.storeGetTransferableCoinsBalance = function() return 0 end
  game.getChannelsHistory = function() return {} end
end

-- Each script slot gets its own copy so one script cannot rewrite an enum out
-- from under another.
local function copyEnums()
  local copy = {}
  for tableName, values in pairs(ENUMS) do
    local entries = {}
    for key, value in pairs(values) do entries[key] = value end
    copy[tableName] = entries
  end
  return copy
end

function compat.install(environment)
  actions = _Helper.ScriptingActions
  if not actions or not actions.perform then return end

  environment.Enums = copyEnums()
  installEvents(environment)
  installClient(environment)
  installPlayerExtras(environment)
  installNpc(environment)
  installSound(environment)
  installUnsupportedGameActions(environment)

  environment.Engine = buildEngine()

  environment.CustomModalWindow = setmetatable({ new = newModalWindow }, {
    __call = function(_, ...) return newModalWindow(...) end
  })

  -- Low-level container externals. These are not part of ZeroBot's documented
  -- API but scripts in the wild call them directly (the fishing drop routine
  -- in the Eloria pack, for one), so they are mapped onto the same restricted
  -- container handles the Container class uses.
  environment.containerGetItems = function(containerIndex)
    local container = actions.getContainer(containerIndex)
    if not container then return {} end
    local result = {}
    for index, item in ipairs(container:getItems() or {}) do
      result[index] = actions.itemData(item, index - 1)
    end
    return result
  end

  environment.containerMoveItemToGround = function(containerIndex, containerSlot, count, x, y, z)
    local handle = environment.Container(containerIndex)
    if not handle then return false end
    return handle:moveItemToGround(containerSlot, count, x, y, z)
  end

  environment.HotkeyManager = {
    parseKeyCombination = function(combination)
      local keys = {}
      for part in tostring(combination or ''):gmatch('[^%+]+') do
        part = (part:gsub('^%s+', ''):gsub('%s+$', ''))
        if part ~= '' then table.insert(keys, part) end
      end
      return keys
    end
  }
end

-- The NPC trade cache has to follow the client, not a script, so it is
-- connected for the lifetime of the module. Guarded so that a failure here can
-- never stop the module from loading -- Npc.buy/sell would simply find no
-- items, and the rest of the compatibility layer stays available.
local tradeHookConnected = pcall(function() connect(g_game, tradeHook) end)

function compat.terminate()
  compat.reset()
  if tradeHookConnected then
    pcall(disconnect, g_game, tradeHook)
    tradeHookConnected = false
  end
  npcTradeItems = {}
end
