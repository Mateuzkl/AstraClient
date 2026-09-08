-- Keep helper startup quiet, but do not hide real UI/load errors.
local function safeLog(level, message)
  if level ~= "error" or not g_logger or not g_logger.error then
    return
  end

  g_logger.error(tostring(message))
end

local function helperDebug(message)
end

-- Tabela global para organizar submódulos do Helper
-- Não sobrescreve se já existir (shortcut_panel.lua pode ser carregado antes)
if not _Helper then
  _Helper = {}
end

-- Flag para suprimir mensagens de status durante carregamento de UI (login, loadSettings, etc.)
_Helper._suppressMessages = false
_Helper.debugLog = helperDebug

local function installHelperSoundCompatibility()
  if not g_sounds then
    return
  end

  local function getAlarmChannel()
    if g_sounds.getChannel then
      return g_sounds.getChannel(SoundChannels and SoundChannels.Bot or 4)
    end
    return nil
  end

  local alarmDeviceRestarted = false

  if not g_sounds.playAlarm then
    g_sounds.playAlarm = function(file)
      if not alarmDeviceRestarted and g_sounds.restartAudioDevice then
        alarmDeviceRestarted = g_sounds.restartAudioDevice()
      end

      -- Alarm playback must work even when the audio device was not initialized
      -- from the options screen during this client session.
      if g_sounds.isAudioEnabled and not g_sounds.isAudioEnabled() and g_sounds.setAudioEnabled then
        g_sounds.setAudioEnabled(true)
      end

      -- Use the core sound API first. The dedicated Bot channel is not
      -- configured by every client build and can remain inaudible.
      if g_sounds.play then
        local source = g_sounds.play(file, 0, 1.0)
        if source then
          if g_logger and g_logger.info then
            g_logger.info("[HELPER ALARM] sound started: " .. tostring(file))
          end
          return source
        end
      end

      local channel = getAlarmChannel()
      if channel then
        if channel.setEnabled then
          channel:setEnabled(true)
        end
        if channel.stop then
          channel:stop(0)
        end
        if channel.play then
          local source = channel:play(file, 0, 1.0)
          if g_logger and g_logger.info then
            g_logger.info("[HELPER ALARM] channel sound result=" .. tostring(source ~= nil) .. ": " .. tostring(file))
          end
          return source
        end
      end

      if g_logger and g_logger.error then
        g_logger.error("[HELPER ALARM] sound failed: " .. tostring(file))
      end
    end
  end

  if not g_sounds.stopAlarm then
    g_sounds.stopAlarm = function()
      local channel = getAlarmChannel()
      if channel and channel.stop then
        return channel:stop(0)
      end
    end
  end
end

installHelperSoundCompatibility()

-- Resolve custom rune: if area is a table (custom definition) but empty, replace with SpellAreas.AREA_CIRCLE3X3
function _Helper.resolveCustomRuneArea(runeSpell)
  if runeSpell and runeSpell.area then
    if type(runeSpell.area) == "table" and #runeSpell.area == 0 then
      runeSpell.area = SpellAreas.AREA_CIRCLE3X3
    elseif runeSpell.area == true then
      runeSpell.area = SpellAreas.AREA_CIRCLE3X3
    end
  end
  return runeSpell
end

-- Configura um TextEdit para aceitar apenas números, com limites opcionais.
-- widget: o UIWidget (TextEdit)
-- minValue: valor numérico mínimo (ex: 1). nil = sem limite. Aplicado ao perder foco.
-- maxValue: valor numérico máximo (ex: 100). nil = sem limite.
function _Helper.setupNumericInput(widget, minValue, maxValue)
  if not widget then return end
  local isUpdating = false
  widget.onTextChange = function(w, text)
    if isUpdating then return end
    isUpdating = true
    local numericText = text:gsub("[^%d]", "")
    if maxValue then
      local value = tonumber(numericText) or 0
      if value > maxValue then
        numericText = tostring(maxValue)
      end
    end
    if numericText ~= text then
      w:setText(numericText)
    end
    isUpdating = false
  end
  if minValue then
    widget.onFocusChange = function(w, focused)
      if not focused then
        if isUpdating then return end
        isUpdating = true
        local value = tonumber(w:getText()) or 0
        if value < minValue then
          w:setText(tostring(minValue))
        end
        isUpdating = false
      end
    end
  end
end

local player = nil
local healingPanel = nil
local toolsPanel = nil
local toolsPanelContainer = nil
local namedSioPanel = nil
local equipPanelContainer = nil
local cavebotPanel = nil
local timerPanelContainer = nil
local scriptingPanel = nil
local settingsPanel = nil
local mouseGrabberWidget = nil
local helper = nil
local helperProfile = nil
local helperVocationEvent = nil
local helperInitRetryEvent = nil
local helperGameStateMonitorEvent = nil
local activeOnlinePlayerName = nil
local hotkeyHelperStatus = false
local afkTime = 180
local helperAutomaticFunctionsEnabled = true
local lastActiveMenu = 'healingMenu'
local isTransitioningPlayer = false

-- fallback for LoadedPlayer when not provided by server-side module
if not LoadedPlayer then
  LoadedPlayer = g_game.getLocalPlayer()
end

-- Retorna a chave de vocação de uma criatura para o sistema de friend healing
local function getVocationKey(creature)
  if creature:isKnight() then
    return "knight"
  elseif creature:isPaladin() then
    return "paladin"
  elseif creature:isSorcerer() then
    return "sorcerer"
  elseif creature:isDruid() then
    return "druid"
  elseif creature:isMonk() then
    return "monk"
  end
  return nil
end


-- Utility function to check if any group in targetGroups is present in groups
local function containsAnyGroup(groups, targetGroups)
  for _, group in ipairs(targetGroups) do
    if table.contains(groups, group) then
      return true
    end
  end
  return false
end

-- fallback for SpellIcons
if not SpellIcons then
  SpellIcons = {}
end

-- Resolve icons exactly like game_actionbar: SpellInfo.icon -> SpellIcons client id.
-- Accepts either a SpellInfo entry or its server spell id so all Helper panels
-- can share the same icon code.
local function getClientSpellIconId(spell)
  local spellData = spell
  if type(spellData) ~= 'table' and Spells and Spells.getSpellDataById then
    spellData = Spells.getSpellDataById(tonumber(spell))
  end

  if spellData and SpellIcons then
    local iconData = SpellIcons[spellData.icon]
    if iconData then
      return iconData[1]
    end
  end

  -- Preserve support for custom entries whose server and client ids match.
  return type(spell) == 'table' and tonumber(spell.id) or tonumber(spell)
end

-- Helper function to get the 32x32 spell icon clip.
-- @param spell: SpellInfo entry or spell server id
-- @param profile: Optional profile name (default: 'Default')
-- @return: Icon clip string in format "x y width height"
_Helper.getSpellIconClip = function(spell, profile)
  local spellIconId = getClientSpellIconId(spell)
  if not spellIconId then
    return "0 0 32 32"
  end

  if Spells and Spells.getImageClipNormal then
    local success, clip = pcall(function()
      return Spells.getImageClipNormal(spellIconId, profile or 'Default')
    end)
    if success and clip then
      return clip
    end
  end
  -- Fallback: return default clip
  return "0 0 32 32"
end

-- Helper function to get spell icon source
-- @param profile: Optional profile name (default: 'Default')
-- @return: Icon source path
_Helper.getSpellIconSource = function(profile)
  profile = profile or 'Default'
  if SpelllistSettings and SpelllistSettings[profile] then
    local source = SpelllistSettings[profile].iconsFolder or SpelllistSettings[profile].iconFile
    if source then
      return source
    end
  end
  return '/images/game/spells/spell-icons-32x32'
end

-- Convenience function to set spell icon on a widget
-- @param widget: The widget to set the icon on (must have setImageSource and setImageClip methods)
-- @param spellId: The spell ID
-- @param profile: Optional profile name (default: 'Default')
_Helper.setSpellIcon = function(widget, spellId, profile)
  if not widget then return end
  local source = _Helper.getSpellIconSource(profile)
  local clip = _Helper.getSpellIconClip(spellId, profile)
  widget:setImageSource(source)
  widget:setImageClip(clip)
end

-- Helper function to safely call g_game.doThing
local function safeDoThing(flag)
  if g_game and type(g_game.doThing) == "function" then
    g_game.doThing(flag)
  end
end

-- Helper function to safely get harmony count
local function getHarmonyCountSafe(p)
  if p and type(p.getHarmony) == 'function' then
    local ok, value = pcall(function() return p:getHarmony() end)
    if ok and type(value) == 'number' then
      return value
    end
  end
  return 0
end

-- Raw player vocation -> spell vocation IDs.
-- Standard Tibia IDs are 1-10; some supported servers use 11-15 for promoted
-- vocations. Spell definitions use {base, promoted}, e.g. Sorcerer {1, 5}.
local ServerToClientVocationMap = {
  [1] = { 1, 5 }, [5] = { 1, 5 }, [13] = { 1, 5 },   -- Sorcerer / Master Sorcerer
  [2] = { 2, 6 }, [6] = { 2, 6 }, [14] = { 2, 6 },   -- Druid / Elder Druid
  [3] = { 3, 7 }, [7] = { 3, 7 }, [12] = { 3, 7 },   -- Paladin / Royal Paladin
  [4] = { 4, 8 }, [8] = { 4, 8 }, [11] = { 4, 8 },   -- Knight / Elite Knight
  [9] = { 9, 10 }, [10] = { 9, 10 }, [15] = { 9, 10 } -- Monk / Exalted Monk
}

-- Check if server vocation can use spell based on client vocations
local function canUseByServerVoc(spellVocations, serverVocId)
  if not serverVocId then return false end

  local mapped = ServerToClientVocationMap[serverVocId]
  if not mapped or table.empty(mapped) then
    return false
  end
  for _, clientVoc in ipairs(mapped) do
    if table.contains(spellVocations, clientVoc) then
      return true
    end
  end
  return false
end

-- Helper function to get spell by client ID
local function getSpellByClientId(clientId)
  if Spells and Spells.getSpellByClientId then
    local success, spell = pcall(function() return Spells.getSpellByClientId(clientId) end)
    if success and spell then
      return spell
    end
  end
  -- Fallback: try to find spell in SpellInfo by clientId
  if SpellInfo and SpellInfo.Default then
    for spellName, spellData in pairs(SpellInfo.Default) do
      if spellData.clientId == clientId then
        return spellData
      end
    end
  end
  return nil
end

-- Helper function to get spell data by ID
local function getSpellDataById(spellId)
  if not spellId or spellId == 0 then
    return nil
  end
  -- First try SpellInfo.Default (most reliable)
  if SpellInfo and SpellInfo.Default then
    for spellName, spellData in pairs(SpellInfo.Default) do
      if spellData.id == spellId then
        return spellData
      end
    end
  end
  -- Then try Spells.getSpellDataById if available
  if Spells and Spells.getSpellDataById then
    local success, spell = pcall(function() return Spells.getSpellDataById(spellId) end)
    if success and spell then
      return spell
    end
  end
  return nil
end

local autoTargetOnHold = false
local multiUseExDelay = 0
local lastObjectUseWasRune = false
local afkTime = 180
local autoTargetModes = {
  ["A"] = 1,
  ["B"] = 2,
  ["C"] = 3,
  ["D"] = 4,
  ["E"] = 5,
  ["F"] = 6,
  ["G"] = 7,
  ["H"] = 8
}

local function deepCopy(original)
  local copy = {}
  for k, v in pairs(original) do
    if type(v) == "table" then
      copy[k] = deepCopy(v)
    else
      copy[k] = v
    end
  end
  return copy
end

local defaultShooterProfile = {
  spells = {
    { id = 0, percent = 0, creatures = 1, priority = 1, forceCast = false, selfCast = false },
    { id = 0, percent = 0, creatures = 1, priority = 2, forceCast = false, selfCast = false },
    { id = 0, percent = 0, creatures = 1, priority = 3, forceCast = false, selfCast = false },
    { id = 0, percent = 0, creatures = 1, priority = 4, forceCast = false, selfCast = false },
    { id = 0, percent = 0, creatures = 1, priority = 5, forceCast = false, selfCast = false },
  },
  runes = {
    { id = 0, creatures = 1, priority = 6, forceCast = false },
    { id = 0, creatures = 1, priority = 7, forceCast = false },
  },
  autoTargetMode = autoTargetModes['F']
}

local potionConfig = { id = "potion", exhaustion = 1000 }
local specialFoodConfig = { id = "specialfood", exhaustion = 1000 }
local specialFoodLocalCooldowns = {} -- { [itemId] = expiresAtMillis } - set immediately on use
local SPECIAL_FOOD_SLOTS = 4         -- free-assign item slots per category (hp / mana)
local SPECIAL_FOOD_CATEGORIES = {
  hp = { rowsId = "hpFoodRows", defaultPercent = 80 },
  mana = { rowsId = "manaFoodRows", defaultPercent = 60 },
}
local potionTurnCooldown = 0         -- turn system: blocks next potion to give rune a turn

local auxiliadorPreCooldown = 200
local specialFoodsWindow = nil
local specialFoodAssignActive = false -- true while the mouse grabber waits for a Special Foods pick

local function safeDoThing(flag)
  if g_game and type(g_game.doThing) == "function" then
    g_game.doThing(flag)
  end
end


local helperEvents = {
  helperCycleEvent = nil,
  helperCycleTimer = 50
}

local timers = {
  checkHealthHealing = 0,
  checkMana = 0,
  routineChecks = 0,
  checkFriendHealing = 0,
  -- checkAutoHaste removido: agora usa onStatesChange + cycle event temporario
  checkMagicShooter = 0,
  checkAutoTarget = 0,
  checkExerciseEvent = 0,
  updatePartyHealth = 0,
  checkEquipItems = 0,
  checkQuiverRefill = 0,
  checkMagicShield = 0,
  refreshBotHud = 0
}

-- PZ (Protection Zone) state tracking for auto_target and magic_shooter
local pzState = {
  wasInPZ = false,                -- Track previous PZ status for edge detection
  wasAutoTargetEnabled = false,   -- Auto target state before PZ entry
  wasMagicShooterEnabled = false, -- Magic shooter state before PZ entry
}

local eventTable = {
  -- Intervalos maiores pois onHealthChange/onManaChange fornecem reação instantânea
  checkHealthHealing = { interval = 50, action = nil }, -- Backup polling (era 250)
  checkMana = { interval = 50, action = nil },          -- Backup polling (era 100)
  routineChecks = { interval = 2500, action = nil },    -- Aumentado: autoChangeGold agora é reativo via onResourcesBalanceChange
  checkFriendHealing = { interval = 50, action = nil },
  -- checkAutoHaste removido: agora usa onStatesChange + cycle event temporario
  checkMagicShooter = { interval = 50, action = nil },
  checkAutoTarget = { interval = 750, action = nil },
  checkFollowFriend = { interval = 300, action = nil },
  checkExerciseEvent = { interval = 10000, action = nil },
  updatePartyHealth = { interval = 50, action = nil },
  checkEquipItems = { interval = 50, action = nil },    -- Check and equip rings/amulets based on health
  checkQuiverRefill = { interval = 500, action = nil }, -- Check and refill quiver for paladins
  checkMagicShield = { interval = 50, action = nil },   -- Check and manage magic shield for mages
  -- The bot HUD used to be redrawn only from cavebot.walkerTick, which exists
  -- solely while the cavebot walker is running. With the cavebot off the HUD
  -- froze: targeting, equipment, timers, haste and player rows never changed,
  -- and toggling a module looked like it did nothing. Refresh it here instead,
  -- so it is live whenever the player is online.
  refreshBotHud = { interval = 250, action = nil }
}

local spellsCooldown = {}
local function getSpellCooldown(spellId)
  return spellsCooldown[spellId] or 0
end

local groupsCooldown = {}
local function getGroupSpellCooldown(groupId)
  return groupsCooldown[groupId] or 0
end

-- Optimization Caches
local cachedPrioritizedSpells = {}
local cachedPrioritizedHealthPotions = {}
local cachedPrioritizedManaPotions = {}
local healingActiveBuffs = {}

-- Forward declaration
local rebuildHealingCache


local function getDistanceBetween(p1, p2)
  return math.max(math.abs(p1.x - p2.x), math.abs(p1.y - p2.y))
end

local function positionCompare(position1, position2)
  if not position1 or not position2 then return false end
  return position1.x == position2.x and position1.y == position2.y and position1.z == position2.z
end

-- Reusable objects for tight loops to reduce garbage collection
local tempPos = { x = 0, y = 0, z = 0 }
local reusableCountedCreatures = {}

local function getDirectionTo(fromPos, toPos)
  local dx = toPos.x - fromPos.x
  local dy = toPos.y - fromPos.y

  if dx == 0 and dy == 0 then
    return nil
  end

  if math.abs(dx) > math.abs(dy) then
    if dx > 0 then
      return Directions.East
    else
      return Directions.West
    end
  else
    if dy > 0 then
      return Directions.South
    else
      return Directions.North
    end
  end
end

local function getPlayer()
  if player then
    -- Valida se o player cacheado ainda é válido
    local success = pcall(function() return player:getId() end)
    if not success then
      player = nil
    end
  end
  if not player then
    player = g_game.getLocalPlayer()
  end
  return player
end

local function playerHasSpell(player, spellId)
  -- getSpells() may not be available, so we'll assume the player has the spell
  -- if they meet the level and mana requirements (which are checked separately)
  -- This is a fallback - if getSpells is available, use it
  if player and player.getSpells then
    local success, spells = pcall(function() return player:getSpells() end)
    -- TFS 8.60 sends spell count 0 in the basic-data packet. An empty list
    -- means the learned-spell feature is unavailable, not that the player
    -- knows no spells. Only enforce the list when the server populated it.
    if success and type(spells) == 'table' and next(spells) ~= nil then
      return table.contains(spells, spellId)
    end
  end
  -- If we can't check, assume the player has the spell
  -- The level/mana checks will filter out spells they can't use anyway
  return true
end

local function numberToOrdinal(n)
  local lastDigit = n % 10
  local lastTwoDigits = n % 100
  if lastTwoDigits >= 11 and lastTwoDigits <= 13 then
    return tostring(n) .. "th"
  end
  if lastDigit == 1 then
    return tostring(n) .. "st"
  elseif lastDigit == 2 then
    return tostring(n) .. "nd"
  elseif lastDigit == 3 then
    return tostring(n) .. "rd"
  else
    return tostring(n) .. "th"
  end
end

local function isWithinReach(playerPos, targetPos)
  if type(targetPos) ~= "table" then
    return false
  end

  local deltaX = math.abs(playerPos.x - targetPos.x)
  local deltaY = math.abs(playerPos.y - targetPos.y)
  local withinX = deltaX <= 7
  local withinY = deltaY <= 5
  return withinX and withinY and playerPos.z == targetPos.z
end

local lastEngineSpectators = {}

-- Flag to prevent saving config during login/initialization
local skipSaveUntilLoaded = true

-- Creature ids are temporary and change on every login. Keep Helper settings
-- under a stable, filesystem-safe key derived from the character name.
local lastCharacterStorageDir = nil

local function getCharacterStorageName(currentPlayer)
  -- The connected player is authoritative. During a fast character switch,
  -- g_game.getCharacterName() may still expose the previous login selection for
  -- a short time; using it first could save the new character over the old one.
  if currentPlayer then
    local playerName = currentPlayer.getName and currentPlayer:getName() or nil
    return type(playerName) == 'string' and playerName ~= '' and playerName or nil
  end

  local name = g_game and g_game.getCharacterName and g_game.getCharacterName() or nil
  return type(name) == 'string' and name or nil
end

local function getCharacterStorageDir(currentPlayer)
  local name = getCharacterStorageName(currentPlayer)
  if name and name ~= '' then
    local key = name:lower():gsub('[^%w%-_]', function(char)
      return string.format('_%02x', string.byte(char))
    end)
    lastCharacterStorageDir = '/characterdata/characters/' .. key
  elseif currentPlayer then
    -- A player object without a usable name is still being initialized. Never
    -- fall back to the previously connected character in that state.
    return nil
  end

  if lastCharacterStorageDir then
    return lastCharacterStorageDir
  end
  return nil
end

local function getLegacyCharacterStorageDir(currentPlayer)
  if not currentPlayer then return nil end
  return '/characterdata/' .. currentPlayer:getId()
end

_Helper.getCharacterStorageDir = getCharacterStorageDir
_Helper.getLegacyCharacterStorageDir = getLegacyCharacterStorageDir

local function getWriteDir()
  local dir = g_resources.getWriteDir() or ""
  return dir:gsub("[\\/]+$", "")
end

local function isWindowsPath(dir)
  return dir:match("^%a:") ~= nil or dir:find("\\") ~= nil
end

local function getHelperSettingsFilePath(dir)
  local writeDir = getWriteDir()
  if writeDir == "" or not dir then
    return nil
  end

  local relativePath = dir:gsub("^[/\\]+", "")
  if isWindowsPath(writeDir) then
    return writeDir .. "\\" .. relativePath:gsub("/", "\\") .. "\\helper.json"
  end
  return writeDir .. "/" .. relativePath:gsub("\\", "/") .. "/helper.json"
end

function openHelperSettingsFolder()
  local currentPlayer = g_game and g_game.getLocalPlayer and g_game.getLocalPlayer() or nil
  local dir = getCharacterStorageDir(currentPlayer)
  if not dir then
    displayErrorBox(tr("Bot Eloria settings"), tr("Log in with a character first."))
    return
  end

  g_resources.makeDir(dir)
  if saveSettings then
    saveSettings()
  end

  local writeDir = getWriteDir()
  local settingsFile = getHelperSettingsFilePath(dir)
  if writeDir == "" or not settingsFile then
    displayErrorBox(tr("Bot Eloria settings"), tr("Could not find the client write directory."))
    return
  end

  if isWindowsPath(writeDir) and g_resources.fileExists(dir .. "/helper.json") then
    g_platform.openDir(string.format('/select,"%s"', settingsFile), true)
    return
  end

  local folder = settingsFile:gsub("[/\\]helper%.json$", "")
  g_platform.openDir(folder, true)
end

_Helper.openSettingsFolder = openHelperSettingsFolder


helperConfig = {
  spells = {
    { id = 0, percent = 80 },
    { id = 0, percent = 80 },
    { id = 0, percent = 80 }
  },
  potions = {
    { id = 0, percent = 50, priority = 0 },
    { id = 0, percent = 50, priority = 0 },
    { id = 0, percent = 50, priority = 0 }
  },
  training = {
    { id = 0, percent = 0, enabled = false }
  },
  haste = {
    { id = 0, enabled = false, safecast = false, onlyWalking = false }
  },
  friendhealing = {
    knight   = { enabled = false, percent = 90, priority = 5 },
    paladin  = { enabled = false, percent = 90, priority = 4 },
    sorcerer = { enabled = false, percent = 90, priority = 3 },
    druid    = { enabled = false, percent = 90, priority = 2 },
    monk     = { enabled = false, percent = 90, priority = 1 },
  },
  namedSio = {
    enabled = false,
    name = "",
    percent = 90,
    spell = "sio" -- "sio" (spell 84) or "gransio" (spell 242)
  },
  gransiohealing = {
    knight   = { enabled = false, percent = 90, priority = 5 },
    paladin  = { enabled = false, percent = 90, priority = 4 },
    sorcerer = { enabled = false, percent = 90, priority = 3 },
    druid    = { enabled = false, percent = 90, priority = 2 },
    monk     = { enabled = false, percent = 90, priority = 1 },
  },
  masreshealing = {
    extended = false,
    knight   = { enabled = false, percent = 90, priority = 5 },
    paladin  = { enabled = false, percent = 90, priority = 4 },
    sorcerer = { enabled = false, percent = 90, priority = 3 },
    druid    = { enabled = false, percent = 90, priority = 2 },
    monk     = { enabled = false, percent = 90, priority = 1 },
  },

  healingTargetMode = "party",
  helperAutomaticFunctionsEnabled = true,

  shooterProfiles = {
    ["Default"] = defaultShooterProfile
  },
  selectedShooterProfile = "Default",

  equipProfiles = {
    ["Default"] = { rules = {}, enabled = true }
  },
  selectedEquipProfile = "Default",

  autoEatFood = false,
  showLookItemId = false,
  autoQuillSell = false,
  autoQuillSellBelowCap = false,
  autoQuillSellCapacity = 100,
  antiIdle = false,
  autoParty = {
    enabled = false,
    acceptEnabled = false,
    sendList = { "", "", "", "" },
    acceptLeader = ""
  },
  autoChangeGold = false,
  magicShooterEnabled = false,
  magicShooterOnHold = false,
  disableInProtectZone = true,
  alwaysChaseOpponent = false,
  followFriendEnabled = false,
  followFriendName = "",
  autoTargetEnabled = false,
  autoTargetMode = autoTargetModes['F'],
  currentLockedTargetId = 0,
  hotkeyCode = nil,          -- Armazena o código da hotkey
  hotkeyFunc = nil,          -- Armazena a função da hotkey
  presetHotkeyEnabled = true,
  recordingHotkeyCode = nil, -- Armazena o código da hotkey de recording
  recordingHotkeyFunc = nil, -- Armazena a função da hotkey de recording

  -- Free-assign slots: the player picks any item per slot (see assignSpecialFoodEvent).
  specialFoods = {
    hp = {
      { id = 0, enabled = false, percent = 80, priority = 1 },
      { id = 0, enabled = false, percent = 80, priority = 2 },
      { id = 0, enabled = false, percent = 80, priority = 3 },
      { id = 0, enabled = false, percent = 80, priority = 4 },
    },
    mana = {
      { id = 0, enabled = false, percent = 60, priority = 1 },
      { id = 0, enabled = false, percent = 60, priority = 2 },
      { id = 0, enabled = false, percent = 60, priority = 3 },
      { id = 0, enabled = false, percent = 60, priority = 4 },
    }
  }
}



-- spells that can be cast on both targets and self
local bothCastTypeSpells = {
  258
}


-- ignoredSpellsIds now loaded from spelldata.json via HelperSpellData module
-- Access via: HelperSpellData.getIgnoredSpellsIds()

-- Spell data now loaded from spelldata.json via HelperSpellData module
-- Access via: HelperSpellData.getIgnoredTrainingSpells()
--             HelperSpellData.getPotionWhitelist()
--             HelperSpellData.getHasteWhiteList()

-- Converte diferentes representações de vocação em um ID padronizado
-- Retornos: 0=rook, 1=Knight, 2=Paladin, 3=Sorcerer, 4=Druid, 5=Monk
function translateVocation(v)
  local map = {
    [0] = 0,
    [4] = 1,
    [8] = 1,
    [11] = 1, -- Knight + EK
    [3] = 2,
    [7] = 2,
    [12] = 2, -- Paladin + RP
    [1] = 3,
    [5] = 3,
    [13] = 3, -- Sorcerer + MS
    [2] = 4,
    [6] = 4,
    [14] = 4, -- Druid + ED
    [9] = 5,
    [10] = 5,
    [15] = 5, -- Monk + promo
  }

  if type(v) == 'number' then
    return map[v] or v
  end

  if type(v) == 'string' then
    local s = v:lower()
    if s:find('knight') or s == 'ek' then return 1 end
    if s:find('paladin') or s == 'rp' then return 2 end
    if s:find('sorcerer') or s == 'ms' then return 3 end
    if s:find('druid') or s == 'ed' then return 4 end
    if s:find('monk') then return 5 end
    if s == 'rook' or s == 'none' then return 0 end
    return 0
  end

  local ok, num = pcall(function() return tonumber(v) end)
  if ok and num then
    return map[num] or num
  end
  return 0
end

-- Mapeamento de vocações do servidor para IDs de classe do cliente (spells)
-- Standard IDs are 1-10; alternate promoted IDs are 11-15.
-- Spell definitions use the standard {base, promoted} pairs.
local ServerToClientVocationMap = {
  [1] = { 1, 5 }, [5] = { 1, 5 }, [13] = { 1, 5 },   -- Sorcerer / Master Sorcerer
  [2] = { 2, 6 }, [6] = { 2, 6 }, [14] = { 2, 6 },   -- Druid / Elder Druid
  [3] = { 3, 7 }, [7] = { 3, 7 }, [12] = { 3, 7 },   -- Paladin / Royal Paladin
  [4] = { 4, 8 }, [8] = { 4, 8 }, [11] = { 4, 8 },   -- Knight / Elite Knight
  [9] = { 9, 10 }, [10] = { 9, 10 }, [15] = { 9, 10 } -- Monk / Exalted Monk
}

-- Retorna a lista de IDs de vocação do cliente correspondente à vocação enviada pelo servidor
function getClientVocationsForServerVoc(serverVocId)
  return deepCopy(ServerToClientVocationMap[serverVocId] or {})
end

-- Verifica se a vocação do servidor pode usar a spell/runa com base nas vocações de cliente da spell
local function canUseByServerVoc(spellVocations, serverVocId)
  local mapped = ServerToClientVocationMap[serverVocId]
  if not mapped or table.empty(mapped) then
    return false
  end
  for _, clientVoc in ipairs(mapped) do
    if table.contains(spellVocations, clientVoc) then
      return true
    end
  end
  return false
end




function clearHelperProfile()
  if not helperProfile then return end
  helperProfile:recursiveGetChildById('profileCreature'):hide()
  helperProfile:recursiveGetChildById('profileName'):setText(tr('Not connected'))
  helperProfile:recursiveGetChildById('profileVocation'):setText('')
  helperProfile:recursiveGetChildById('profileLevel'):setText('')
end

function refreshHelperProfile(changedPlayer)
  if not helperProfile or not helper then return end
  local currentPlayer = g_game.getLocalPlayer()
  if changedPlayer and changedPlayer ~= currentPlayer then return end
  if not currentPlayer then
    clearHelperProfile()
    return
  end
  if not helper:isVisible() then return end

  -- getOutfit returns a value table; removing the preview mount never changes
  -- the actual creature. Resolve the player anew for every lifecycle update.
  local outfit = currentPlayer:getOutfit()
  outfit.category = ThingCategoryCreature
  outfit.mount = 0
  local preview = helperProfile:recursiveGetChildById('profileCreature')
  preview:setOutfit(outfit)
  preview:show()
  helperProfile:recursiveGetChildById('profileName'):setText(currentPlayer:getName())
  local vocation = g_game.getVocationName(currentPlayer:getVocation())
  helperProfile:recursiveGetChildById('profileVocation'):setText(vocation ~= 'None' and tr(vocation) or '')
  helperProfile:recursiveGetChildById('profileLevel'):setText(tr('Level: %s', tostring(currentPlayer:getLevel())))
end

local function fitHelperWindow()
  if not helper then return end
  local root = helper:getParent()
  if root:getWidth() <= 0 or root:getHeight() <= 0 then return end
  helper:setSize({ width = math.min(960, root:getWidth() - 16), height = math.min(580, root:getHeight() - 48) })
  helper:setPosition({ x = math.floor((root:getWidth() - helper:getWidth()) / 2),
    y = math.max(34, math.floor((root:getHeight() - helper:getHeight()) / 2)) })
  local bar = helper:recursiveGetChildById('optionsTabBar')
  if bar then
    local width = math.floor((bar:getWidth() - 1) / #bar:getChildren()) - 1
    for _, button in ipairs(bar:getChildren()) do button:setWidth(width) end
  end
  helper:bindRectToParent()
end

function onHelperViewportChange()
  if helper and helper:isVisible() then fitHelperWindow() end
end

function onHelperVocationChange(changedPlayer)
  refreshHelperProfile(changedPlayer)
  if helperVocationEvent then removeEvent(helperVocationEvent) end
  helperVocationEvent = scheduleEvent(function()
    helperVocationEvent = nil
    if helper and g_game.isOnline() then online() end
  end, 100)
end

function init()
  -- Carregar dados de spells do JSON (uma única vez)
  if not HelperSpellData.load() then
    g_logger.warning("[game_helper] Failed to load spell data from JSON, using fallback")
  end

  local success, err = pcall(function()
    if LocalPlayer then
      connect(LocalPlayer, {
        onOutfitChange = refreshHelperProfile,
        onLevelChange = refreshHelperProfile,
        onPartyMembersChange = onPartyMembersChange,
        onHealthChange = onPlayerHealthChange,
        onManaChange = onPlayerManaChange,
        onStatesChange = onPlayerStatesChange,
        onVocationChange = onHelperVocationChange,
      })
    end

    if g_game then
      connect(g_game, {
        onGameStart = online,
        onGameEnd = offline,
        onSpellCooldown = onSpellCooldown,
        onSpellGroupCooldown = onSpellGroupCooldown,
        onUpdateSpellArea = onUpdateSpellArea,
        onPartyDataUpdate = onPartyDataUpdate,
        onPartyDataClear = onPartyDataClear,
        onMultiUseCooldown = onMultiUseCooldown,
        onResourcesBalanceChange = onResourcesBalanceChange,
        onPartyMemberHealthChange = onPartyMemberHealthChangeHelper,
        onTalk = _Helper.PrivateMessageAlarm.check,
      })
    end

    --safeLog("debug", "Helper: init() - Game events connected")
  end)

  if not success then
    safeLog("error", string.format("Helper: init() - Error connecting events: %s", tostring(err)))
  end

  if not success then
    safeLog("error", string.format("Helper: init() - Error connecting creature events: %s", tostring(err)))
  end

  success, err = pcall(function()
    g_ui.importStyle('styles/rule_list')
    g_ui.importStyle('styles/helper')
    g_ui.importStyle('styles/tools_panel')
    g_ui.importStyle('styles/alarm_settings')
    g_ui.importStyle('styles/low_supply_alarm_settings')
    g_ui.importStyle('styles/presets')
    g_ui.importStyle('styles/equip_panel')
    g_ui.importStyle('styles/shortcut_panel')
    g_ui.importStyle('styles/magic_shooter_panel')
    g_ui.importStyle('styles/timer_panel')
    g_ui.importStyle('styles/cavebot_panel')
    g_ui.importStyle('styles/cavebot_settings')
    g_ui.importStyle('styles/scripting_panel')
    g_ui.importStyle('styles/scripting_modal')
    helper = g_ui.loadUI('helper_window', g_ui.getRootWidget())
    if helper then
      helperProfile = helper:recursiveGetChildById('helperProfile')
      connect(helper:getParent(), { onGeometryChange = onHelperViewportChange })
      _Helper.HotkeyManager.setHelperWidget(helper)
      safeLog("debug", "Helper: init() - Helper window created")
    else
      safeLog("error", "Helper: init() - Failed to create helper window")
    end
  end)

  if not success then
    safeLog("error", string.format("Helper: init() - Error creating UI: %s", tostring(err)))
  end

  player = g_game.getLocalPlayer()
  -- hide() moved after panel creation to avoid issues
  local helperContentPanel = nil
  if helper then
    helperContentPanel = helper.contentPanel or helper:getChildById('contentPanel') or helper:recursiveGetChildById('contentPanel')
  end

  if helperContentPanel then
    healingPanel = helperContentPanel:getChildById('healingPanel') or helperContentPanel:recursiveGetChildById('healingPanel')
    toolsPanelContainer = helperContentPanel:getChildById('toolsPanelContainer') or helperContentPanel:recursiveGetChildById('toolsPanelContainer')
    if toolsPanelContainer then
      toolsPanel = helper
    end

    -- Log warning if panels don't exist, but continue initialization
    if not healingPanel or not toolsPanel then
      safeLog("error", "Helper: init() - Required panels not found, but continuing initialization")
    end

    if healingPanel then
      potionButton2 = healingPanel:recursiveGetChildById("potionButton2")
      rmvPotionPercentButton2 = healingPanel:recursiveGetChildById("rmvPotionPercentButton2")
      potionPercentBg2 = healingPanel:recursiveGetChildById("potionPercentBg2")
      addPotionPercentButton2 = healingPanel:recursiveGetChildById("addPotionPercentButton2")
      priority2 = healingPanel:recursiveGetChildById("priority2")
      namedSioPanel = healingPanel:recursiveGetChildById("namedSioPanel")
      friendHealingPanel = healingPanel:recursiveGetChildById("friendHealingPanel")
      granSioPanel = healingPanel:recursiveGetChildById("granSioPanel")
      masResPanel = healingPanel:recursiveGetChildById("masResPanel")
      healingTargetModePanel = nil
      spellButton2 = healingPanel:recursiveGetChildById("spellButton2")
      rmvPercentButton2 = healingPanel:recursiveGetChildById("rmvPercentButton2")
      spellPercentBg2 = healingPanel:recursiveGetChildById("spellPercentBg2")
      addPercentButton2 = healingPanel:recursiveGetChildById("addPercentButton2")
      if healingPanel.healingPanel then
        healPanel = healingPanel.healingPanel
      else
        healPanel = healingPanel:recursiveGetChildById('healingPanel')
      end
      priorityButton1 = healingPanel:recursiveGetChildById("priority0")
      priorityButton2 = healingPanel:recursiveGetChildById("priority1")
      priorityButton3 = healingPanel:recursiveGetChildById("priority2")
      if toolsPanel then
        equipPanel = toolsPanel:recursiveGetChildById("equipPanel")
      end
      shooterPanel = helperContentPanel:getChildById('shooterPanel') or helperContentPanel:recursiveGetChildById('shooterPanel')
      equipPanelContainer = helperContentPanel:getChildById('equipPanelContainer') or helperContentPanel:recursiveGetChildById('equipPanelContainer')
      -- Initialize equip panel module
      if equipPanelContainer and modules.game_helper and modules.game_helper.equip then
        modules.game_helper.equip.init(helper)
      end
      if shooterPanel then
        -- New unified magic shooter panel
        local magicShooterContainer = shooterPanel:recursiveGetChildById("magicShooterPanelContainer")
        if magicShooterContainer then
          local magicShooterPanel = magicShooterContainer:recursiveGetChildById("magicShooterPanel")
          if magicShooterPanel then
            enableButtons = magicShooterPanel:recursiveGetChildById("enableButtonsPanel")
          end
        end
        -- Initialize magic shooter panel module
        if modules.game_helper and modules.game_helper.magicShooter then
          modules.game_helper.magicShooter.init(helper)
        end
      end
      cavebotPanel = helperContentPanel:getChildById('cavebotPanel') or helperContentPanel:recursiveGetChildById('cavebotPanel')
      if cavebotPanel then
        if modules.game_helper and modules.game_helper.cavebot then
          modules.game_helper.cavebot.init(helper)
        end
      end
      timerPanelContainer = helperContentPanel:getChildById('timerPanelContainer') or helperContentPanel:recursiveGetChildById('timerPanelContainer')
      if timerPanelContainer then
        if modules.game_helper and modules.game_helper.timerPanel then
          modules.game_helper.timerPanel.init(timerPanelContainer)
        end
      end
    end
    scriptingPanel = helperContentPanel:getChildById('scriptingPanel') or helperContentPanel:recursiveGetChildById('scriptingPanel')
    if scriptingPanel and modules.game_helper and modules.game_helper.scripting then
      modules.game_helper.scripting.init(scriptingPanel)
    end
  end

  -- Deliberately outside the helperContentPanel/healingPanel block above: unlike
  -- the other panels, tools.init() also starts the automation cycle (anti-idle,
  -- auto-party, Auto Sell Loot), and none of those need a panel to exist.
  --
  -- This call was missing entirely. Without it startAutomationCycle() never ran,
  -- so nothing ever polled the Summon Quill state -- Auto Sell Loot only fired
  -- on the state pushes the server happens to send, which is why it looked like
  -- it "only works if you open and close the Quill window".
  if modules.game_helper and modules.game_helper.tools and modules.game_helper.tools.init then
    modules.game_helper.tools.init(helper)
  end

  botStatus()

  -- Hide the window after everything is set up
  if helper then
    helper:hide()
  end

  mouseGrabberWidget = g_ui.createWidget('UIWidget')
  mouseGrabberWidget:setVisible(false)
  mouseGrabberWidget:setFocusable(false)

  -- Bind Ctrl+H to toggle helper window
  if g_keyboard then
    g_keyboard.bindKeyDown('Ctrl+H', toggle)
  end

  success, err = pcall(function()
    local attempts = 0
    local maxAttempts = 10

    local function tryInitialize()
      attempts = attempts + 1
      -- Verificar diretamente se o player existe (mais confiável que isOnline())
      if g_game and g_game.getLocalPlayer then
        local currentPlayer = g_game.getLocalPlayer()
        if currentPlayer then
          online()
          return true
        else
          safeLog("debug",
            string.format("Helper: init() - Player not available yet (attempt %d/%d)", attempts, maxAttempts))
          return false
        end
      else
        safeLog("debug",
          string.format("Helper: init() - g_game.getLocalPlayer not available yet (attempt %d/%d)", attempts, maxAttempts))
        return false
      end
    end

    -- Tentar inicializar imediatamente
    if not tryInitialize() then
      -- Se falhou, tentar novamente com intervalos progressivos
      if _G.scheduleEvent then
        safeLog("debug", "Helper: init() - Scheduling initialization retry attempts")
        local function retryAttempt()
          if helperEvents and helperEvents.helperCycleEvent then
            safeLog("info", "Helper: init() - CycleEvent already registered, stopping retries")
            return
          end
          if attempts >= maxAttempts then
            safeLog("debug",
              string.format("Helper: init() - Max initialization attempts reached (%d), will initialize on game start",
                maxAttempts))
            return
          end
          if tryInitialize() then
            --  safeLog("info", "Helper: init() - Initialization successful after retry")
          else
            -- Agendar próxima tentativa com intervalo maior
            local delay = math.min(500 + (attempts * 200), 2000)
            helperInitRetryEvent = _G.scheduleEvent(retryAttempt, delay)
          end
        end
        helperInitRetryEvent = _G.scheduleEvent(retryAttempt, 300)
      end
    end

    -- Monitor contínuo para detectar login de novo player quando o ciclo não está rodando
    local function monitorGameState()
      if g_game and g_game.isOnline and g_game.isOnline() then
        if not helperEvents or not helperEvents.helperCycleEvent then
          local currentPlayer = g_game.getLocalPlayer()
          if currentPlayer then
            online()
          end
        end
      end
      helperGameStateMonitorEvent = _G.scheduleEvent(monitorGameState, 1000)
    end
    helperGameStateMonitorEvent = _G.scheduleEvent(monitorGameState, 2000)
  end)

  if not success then
    safeLog("error", string.format("Helper: init() - Error checking online status: %s", tostring(err)))
  end

  --  safeLog("info", "Helper: init() - Initialization complete")

  -- Funções de teste removidas - não estão definidas

  -- Configurações são carregadas por personagem em loadSettings() quando o jogador faz login
end

function terminate()
  if helperInitRetryEvent then
    removeEvent(helperInitRetryEvent)
    helperInitRetryEvent = nil
  end
  if helperGameStateMonitorEvent then
    removeEvent(helperGameStateMonitorEvent)
    helperGameStateMonitorEvent = nil
  end
  if helperVocationEvent then
    removeEvent(helperVocationEvent)
    helperVocationEvent = nil
  end
  -- Persist while the cached character path and UI-backed configs still exist.
  saveSettings()

  if modules.game_helper and modules.game_helper.scripting then
    modules.game_helper.scripting.terminate()
  end

  if modules.game_helper and modules.game_helper.cavebot and modules.game_helper.cavebot.terminate then
    modules.game_helper.cavebot.terminate()
  end

  if modules.game_helper and modules.game_helper.magicShooter and modules.game_helper.magicShooter.terminate then
    modules.game_helper.magicShooter.terminate()
  end

  if _Helper.AutoStaminaFood and _Helper.AutoStaminaFood.terminate then
    _Helper.AutoStaminaFood.terminate()
  end

  if _Helper.ParalyzeCure and _Helper.ParalyzeCure.terminate then
    _Helper.ParalyzeCure.terminate()
  end

  if _Helper.FollowFriend and _Helper.FollowFriend.reset then
    _Helper.FollowFriend.reset()
  end

  if LocalPlayer then
    disconnect(LocalPlayer, {
      onVocationChange = onHelperVocationChange,
      onOutfitChange = refreshHelperProfile,
      onLevelChange = refreshHelperProfile,
      onPartyMembersChange = onPartyMembersChange,
      onHealthChange = onPlayerHealthChange,
      onManaChange = onPlayerManaChange,
      onStatesChange = onPlayerStatesChange,
    })
  end

  if g_game then
    disconnect(g_game, {
      onGameStart = online,
      onGameEnd = offline,
      onSpellCooldown = onSpellCooldown,
      onSpellGroupCooldown = onSpellGroupCooldown,
      onUpdateSpellArea = onUpdateSpellArea,
      onPartyDataUpdate = onPartyDataUpdate,
      onPartyDataClear = onPartyDataClear,
      onMultiUseCooldown = onMultiUseCooldown,
      onResourcesBalanceChange = onResourcesBalanceChange,
      onPartyMemberHealthChange = onPartyMemberHealthChangeHelper,
      onTalk = _Helper.PrivateMessageAlarm.check,
    })
  end

  if helper then
    helperProfile = nil
    disconnect(helper:getParent(), { onGeometryChange = onHelperViewportChange })
    g_keyboard.unbindKeyPress('Tab', toggleNextWindow, helper)
    helper:destroy()
    helper = nil
  end

  -- Fecha a janela de settings do cavebot se estiver aberta
  if modules.game_helper and modules.game_helper.cavebot and modules.game_helper.cavebot.closeSettingsWindow then
    modules.game_helper.cavebot.closeSettingsWindow()
  end

  -- Fecha a janela de alarm settings se estiver aberta
  if _Helper.AlarmSettings and _Helper.AlarmSettings.close then
    _Helper.AlarmSettings.close()
  end

  -- Fecha a janela de special foods se estiver aberta
  destroySpecialFoodsWindow()

  -- Unbind Ctrl+H toggle helper window
  if g_keyboard then
    g_keyboard.unbindKeyDown('Ctrl+H', toggle)
  end

  if mouseGrabberWidget then
    mouseGrabberWidget:destroy()
    mouseGrabberWidget = nil
  end


  if modules.game_helper and modules.game_helper.equip and modules.game_helper.equip.terminate then
    modules.game_helper.equip.terminate()
  end

  -- Stops the automation cycle started in init(); without this the cycleEvent
  -- would outlive the module.
  if modules.game_helper and modules.game_helper.tools and modules.game_helper.tools.terminate then
    modules.game_helper.tools.terminate()
  end

  _Helper.Shortcut.destroyPanel()
end

function toggle()
  if not g_game or not g_game.isOnline or not g_game.isOnline() then return end
  if helper and helper:isVisible() then
    hide()
  else
    show()
  end
end

function hide()
  -- Commit any pending quiver refill inputs before hiding so typed values
  -- that haven't lost focus yet still get clamped + saved.
  if modules.game_helper.tools and modules.game_helper.tools.commitQuiverInputs then
    modules.game_helper.tools.commitQuiverInputs()
  end
  saveSettings()
  if helper then
    g_keyboard.unbindKeyPress('Tab', toggleNextWindow, helper)
    helper:hide()
  end
  if modules.game_helper.magicShooter then
    modules.game_helper.magicShooter.closeConditionSettings()
  end
  if _Helper.AlarmSettings and _Helper.AlarmSettings.close then
    _Helper.AlarmSettings.close()
  end
end

local function getHelperContentPanel()
  if not helper then
    return nil
  end

  return helper.contentPanel or helper:getChildById('contentPanel') or helper:recursiveGetChildById('contentPanel')
end

local function refreshHelperPanelRefs()
  local contentPanel = getHelperContentPanel()
  if not contentPanel then
    return nil
  end

  healingPanel = healingPanel or contentPanel:getChildById('healingPanel') or contentPanel:recursiveGetChildById('healingPanel')
  toolsPanelContainer = toolsPanelContainer or contentPanel:getChildById('toolsPanelContainer') or contentPanel:recursiveGetChildById('toolsPanelContainer')
  if toolsPanelContainer and not toolsPanel then
    toolsPanel = helper
  end
  if healingPanel then
    healPanel = healPanel or healingPanel.healingPanel or healingPanel:recursiveGetChildById('healingPanel')
    namedSioPanel = namedSioPanel or healingPanel:recursiveGetChildById("namedSioPanel")
    potionButton2 = potionButton2 or healingPanel:recursiveGetChildById("potionButton2")
    rmvPotionPercentButton2 = rmvPotionPercentButton2 or healingPanel:recursiveGetChildById("rmvPotionPercentButton2")
    potionPercentBg2 = potionPercentBg2 or healingPanel:recursiveGetChildById("potionPercentBg2")
    addPotionPercentButton2 = addPotionPercentButton2 or healingPanel:recursiveGetChildById("addPotionPercentButton2")
    priority2 = priority2 or healingPanel:recursiveGetChildById("priority2")
    friendHealingPanel = friendHealingPanel or healingPanel:recursiveGetChildById("friendHealingPanel")
    granSioPanel = granSioPanel or healingPanel:recursiveGetChildById("granSioPanel")
    masResPanel = masResPanel or healingPanel:recursiveGetChildById("masResPanel")
    healingTargetModePanel = healingTargetModePanel or healingPanel:recursiveGetChildById("healingTargetModePanel")
    spellButton2 = spellButton2 or healingPanel:recursiveGetChildById("spellButton2")
    rmvPercentButton2 = rmvPercentButton2 or healingPanel:recursiveGetChildById("rmvPercentButton2")
    spellPercentBg2 = spellPercentBg2 or healingPanel:recursiveGetChildById("spellPercentBg2")
    addPercentButton2 = addPercentButton2 or healingPanel:recursiveGetChildById("addPercentButton2")
    priorityButton1 = priorityButton1 or healingPanel:recursiveGetChildById("priority0")
    priorityButton2 = priorityButton2 or healingPanel:recursiveGetChildById("priority1")
    priorityButton3 = priorityButton3 or healingPanel:recursiveGetChildById("priority2")
  end
  shooterPanel = shooterPanel or contentPanel:getChildById('shooterPanel') or contentPanel:recursiveGetChildById('shooterPanel')
  equipPanelContainer = equipPanelContainer or contentPanel:getChildById('equipPanelContainer') or contentPanel:recursiveGetChildById('equipPanelContainer')
  cavebotPanel = cavebotPanel or contentPanel:getChildById('cavebotPanel') or contentPanel:recursiveGetChildById('cavebotPanel')
  timerPanelContainer = timerPanelContainer or contentPanel:getChildById('timerPanelContainer') or contentPanel:recursiveGetChildById('timerPanelContainer')
  scriptingPanel = scriptingPanel or contentPanel:getChildById('scriptingPanel') or contentPanel:recursiveGetChildById('scriptingPanel')
  settingsPanel = settingsPanel or contentPanel:getChildById('settingsPanel') or contentPanel:recursiveGetChildById('settingsPanel')

  return contentPanel
end

local helperMenuIds = {
  'healingMenu',
  'toolsMenu',
  'shooterMenu',
  'equipMenu',
  'cavebotMenu',
  'timerMenu',
  'scriptingMenu',
  'settingsFolderMenu',
}

local function getHelperTabBar(contentPanel)
  if not contentPanel then
    return nil
  end

  return contentPanel.optionsTabBar or contentPanel:getChildById('optionsTabBar') or contentPanel:recursiveGetChildById('optionsTabBar')
end

local function setHelperSelectedMenu(menuId)
  local contentPanel = refreshHelperPanelRefs()
  local tabBar = getHelperTabBar(contentPanel)
  if not tabBar then
    return
  end

  for _, buttonId in ipairs(helperMenuIds) do
    local button = tabBar:getChildById(buttonId)
    if button then
      button:setChecked(buttonId == menuId)
    end
  end
end

local function getHelperSaveEntries()
  local entries = {}
  local seen = {}

  local function addEntry(name, dir)
    local helperFile = dir .. "/helper.json"
    local alarmsFile = dir .. "/alarms.json"
    local hasHelper = g_resources.fileExists(helperFile)
    local hasAlarms = g_resources.fileExists(alarmsFile)
    if seen[dir] or (not hasHelper and not hasAlarms) then return end
    seen[dir] = true
    table.insert(entries, {
      name = name,
      dir = dir,
      file = helperFile,
      alarmsFile = alarmsFile,
      jsonCount = (hasHelper and 1 or 0) + (hasAlarms and 1 or 0),
      path = getHelperSettingsFilePath(dir) or helperFile
    })
  end

  local charactersRoot = "/characterdata/characters"
  local ok, characterDirs = pcall(function() return g_resources.listDirectoryFiles(charactersRoot) end)
  if ok and characterDirs then
    for _, name in ipairs(characterDirs) do
      addEntry(name, charactersRoot .. "/" .. name)
    end
  end

  local legacyRoot = "/characterdata"
  ok, characterDirs = pcall(function() return g_resources.listDirectoryFiles(legacyRoot) end)
  if ok and characterDirs then
    for _, name in ipairs(characterDirs) do
      if name ~= "characters" then
        addEntry(name, legacyRoot .. "/" .. name)
      end
    end
  end

  table.sort(entries, function(a, b) return a.name:lower() < b.name:lower() end)
  return entries
end

local function openHelperSettingsEntry(entry)
  if not entry then return end
  local writeDir = getWriteDir()
  if isWindowsPath(writeDir) and g_resources.fileExists(entry.file) then
    g_platform.openDir(string.format('/select,"%s"', entry.path), true)
    return
  end
  g_platform.openDir(entry.path:gsub("[/\\]helper%.json$", ""), true)
end

local function deleteHelperSettingsEntry(entry)
  if not entry then return end

  local confirmWindow = nil
  local confirm = function()
    if confirmWindow then
      confirmWindow:destroy()
      confirmWindow = nil
    end

    local deleted = true
    if g_resources.fileExists(entry.file) then
      deleted = g_resources.deleteFile(entry.file) and deleted
    end
    if g_resources.fileExists(entry.alarmsFile) then
      deleted = g_resources.deleteFile(entry.alarmsFile) and deleted
    end
    if deleted then
      pcall(function() g_resources.deleteFile(entry.dir) end)
    end

    if modules.game_textmessage and modules.game_textmessage.displayGameMessage then
      modules.game_textmessage.displayGameMessage(deleted and "Bot Eloria save data deleted." or "Could not delete Bot Eloria save data.")
    end
    refreshHelperSettingsPanel()
  end

  local cancel = function()
    if confirmWindow then
      confirmWindow:destroy()
      confirmWindow = nil
    end
  end

  confirmWindow = displayGeneralBox(
    tr("Delete Bot Eloria Save"),
    tr('Delete saved settings for "%s"?', entry.name),
    {
      { text = tr("Yes"), callback = confirm },
      { text = tr("No"), callback = cancel }
    },
    confirm, cancel
  )
end

local function addHelperSaveRow(list, entry)
  local row = g_ui.createWidget("Panel", list)
  row:setHeight(34)
  row:setImageSource("/images/ui/panel_flat")
  row:setImageBorder(1)

  local nameLabel = g_ui.createWidget("Label", row)
  nameLabel:setId("characterName")
  nameLabel:addAnchor(AnchorLeft, "parent", AnchorLeft)
  nameLabel:addAnchor(AnchorTop, "parent", AnchorTop)
  nameLabel:addAnchor(AnchorRight, "parent", AnchorRight)
  nameLabel:setMarginLeft(6)
  nameLabel:setMarginRight(146)
  nameLabel:setMarginTop(3)
  nameLabel:setText(entry.name)
  nameLabel:setColor("#c8c8c8")

  local pathLabel = g_ui.createWidget("Label", row)
  pathLabel:setId("characterPath")
  pathLabel:addAnchor(AnchorLeft, "parent", AnchorLeft)
  pathLabel:addAnchor(AnchorTop, "characterName", AnchorBottom)
  pathLabel:addAnchor(AnchorRight, "parent", AnchorRight)
  pathLabel:setMarginLeft(6)
  pathLabel:setMarginRight(146)
  pathLabel:setMarginTop(1)
  pathLabel:setText(string.format("%d settings file(s)  -  Open to view", entry.jsonCount or 1))
  row:setTooltip(entry.path)
  pathLabel:setTooltip(entry.path)
  pathLabel:setColor("#aaaaaa")

  local openButton = g_ui.createWidget("Button", row)
  openButton:setId("openButton")
  openButton:addAnchor(AnchorRight, "parent", AnchorRight)
  openButton:addAnchor(AnchorTop, "parent", AnchorTop)
  openButton:setMarginRight(84)
  openButton:setMarginTop(6)
  openButton:setSize({ width = 52, height = 22 })
  openButton:setText("Open")
  openButton.onClick = function() openHelperSettingsEntry(entry) end

  local deleteButton = g_ui.createWidget("Button", row)
  deleteButton:setId("deleteButton")
  deleteButton:addAnchor(AnchorRight, "parent", AnchorRight)
  deleteButton:addAnchor(AnchorTop, "parent", AnchorTop)
  deleteButton:setMarginRight(18)
  deleteButton:setMarginTop(6)
  deleteButton:setSize({ width = 60, height = 22 })
  deleteButton:setText("Delete")
  deleteButton:setTooltip("Delete this character save")
  deleteButton.onClick = function() deleteHelperSettingsEntry(entry) end
end

local function refreshHelperStorageLocations(panel)
  local list = panel:recursiveGetChildById('settingsLocationsList')
  if not list then return end
  list:destroyChildren()
  local writeDir = getWriteDir()
  local function addLocation(title, virtualPath, description, isFile)
    local path = writeDir .. '/' .. virtualPath:gsub('^/', '')
    if isWindowsPath(writeDir) then path = path:gsub('/', '\\') end
    local row = g_ui.createWidget('BotStorageLocationRow', list)
    row:getChildById('locationTitle'):setText(title)
    row:getChildById('locationPath'):setText(virtualPath)
    row:getChildById('locationPath'):setTooltip(description .. '\n' .. path)
    row:getChildById('locationTitle'):setTooltip(description .. '\n' .. path)
    row:setTooltip(description .. '\n' .. path)
    row:getChildById('copyPath').onClick = function()
      g_window.setClipboardText(path)
    end
    row:getChildById('openLocation').onClick = function()
      if writeDir == '' then
        displayErrorBox(tr('Storage locations'), tr('Could not find the client write directory.'))
        return
      end
      if isFile then
        -- Flush pending names and script edits before opening their save location.
        saveSettings()
        if isWindowsPath(writeDir) and g_resources.fileExists(virtualPath) then
          g_platform.openDir(string.format('/select,"%s"', path), true)
        else
          g_platform.openDir(path:match('^(.*)[/\\][^/\\]+$'), true)
        end
      else
        g_resources.makeDir(virtualPath)
        g_platform.openDir(path, true)
      end
    end
  end
  addLocation(tr('Cavebot scripts & categories'), '/cavebots',
    tr('Cavebot routes are JSON files. Each subfolder is a category.'))
  local categories = {}
  local folders = g_resources.directoryExists('/cavebots') and g_resources.listDirectoryFiles('/cavebots') or {}
  for _, name in ipairs(folders or {}) do
    if name ~= '.' and name ~= '..' and g_resources.directoryExists('/cavebots/' .. name) then
      table.insert(categories, name)
    end
  end
  table.sort(categories)
  for _, name in ipairs(categories) do
    addLocation(tr('Category: ') .. name, '/cavebots/' .. name, tr('Saved cavebot routes in this category.'))
  end
  local characterDir = getCharacterStorageDir(g_game.getLocalPlayer())
  if characterDir then
    addLocation(tr('Custom scripts & HUDs'), characterDir .. '/helper.json',
      tr('Your five script slots, names and code are saved in helper.json under scriptingScripts.'), true)
  end
  addLocation(tr('All character saves'), '/characterdata/characters',
    tr('Per-character bot settings, custom scripts and alarms.'))
end

function refreshHelperSettingsPanel()
  local contentPanel = refreshHelperPanelRefs()
  local panel = settingsPanel or (contentPanel and contentPanel:recursiveGetChildById("settingsPanel")) or nil
  if not panel then return end
  refreshHelperStorageLocations(panel)

  local list = panel:recursiveGetChildById("settingsCharactersList")
  local stats = panel:recursiveGetChildById("settingsStatsLabel")
  if not list or not stats then return end

  list:destroyChildren()
  local entries = getHelperSaveEntries()
  local jsonCount = 0
  for _, entry in ipairs(entries) do
    jsonCount = jsonCount + (entry.jsonCount or 1)
  end
  stats:setText(string.format("%d characters   /   %d settings files", #entries, jsonCount))

  if #entries == 0 then
    local empty = g_ui.createWidget("Label", list)
    empty:setHeight(24)
    empty:setText("No saved character settings found.")
    empty:setColor("#aaaaaa")
    return
  end

  for _, entry in ipairs(entries) do
    addHelperSaveRow(list, entry)
  end
end

_Helper.refreshSettingsPanel = refreshHelperSettingsPanel

local function showFallbackHelperMenu()
  refreshHelperPanelRefs()
  setHelperSelectedMenu('healingMenu')

  if healingPanel then
    healingPanel:show(true)
  end
  if toolsPanelContainer then
    toolsPanelContainer:hide()
  end
  if shooterPanel then
    shooterPanel:hide()
  end
  if equipPanelContainer then
    equipPanelContainer:hide()
  end
  if cavebotPanel then
    cavebotPanel:hide()
  end
  if timerPanelContainer then
    timerPanelContainer:hide()
  end
  if scriptingPanel then
    scriptingPanel:hide()
  end
  if settingsPanel then
    settingsPanel:hide()
  end
end

local function hasVisibleHelperMenu()
  refreshHelperPanelRefs()

  local panels = {
    healingPanel,
    toolsPanelContainer,
    shooterPanel,
    equipPanelContainer,
    cavebotPanel,
    timerPanelContainer,
    scriptingPanel,
    settingsPanel,
  }

  for _, panel in ipairs(panels) do
    local ok, visible = pcall(function()
      return panel and panel:isVisible()
    end)
    if ok and visible then
      return true
    end
  end

  return false
end

function show()
  if helper then
    refreshHelperPanelRefs()
    helper:show(true)
    helper:raise()
    helper:focus()
    fitHelperWindow()
    refreshHelperProfile()
    g_keyboard.bindKeyPress('Tab', toggleNextWindow, helper)
    local success, err = pcall(function()
      loadMenu(lastActiveMenu or 'healingMenu')
    end)
    if not success then
      safeLog("error", string.format("Helper: show() - Error loading menu: %s", tostring(err)))
    end
    if not success or not hasVisibleHelperMenu() then
      showFallbackHelperMenu()
    end
  end
end

-- Compatibility for side-panel layouts saved by older client versions. The
-- redesigned Helper is a standalone window, so there is no widget to reparent.
function move()
  show()
  return nil
end

function onEloriaBotClick()
  toggle()
end

local lastPlayerName = nil

-- Detector de "freeze" do servidor (ex.: server save).
-- Usa g_game.getElapsedTicksSinceLastRead() como heartbeat (ms desde o último
-- byte recebido do server). Se passar do threshold, pausamos o helper para
-- não acumular pacotes que derrubem o player ao retomar.
local serverHeartbeat = {
  wasFrozen = false,       -- estado anterior, para detectar transição
  resumeAt = 0,            -- g_clock.millis() até quando ainda esperar após retomar
  freezeThreshold = 2000,  -- ms sem dados do server para considerar freeze
  resumeCooldown = 500     -- ms de carência após server voltar (para escoar backlog)
}

local function isServerFrozen()
  if not g_game.isOnline() then
    return false
  end
  local now = g_clock.millis()
  local idle = g_game.getElapsedTicksSinceLastRead and g_game.getElapsedTicksSinceLastRead() or -1
  if idle >= 0 and idle > serverHeartbeat.freezeThreshold then
    serverHeartbeat.wasFrozen = true
    return true
  end
  if serverHeartbeat.wasFrozen then
    serverHeartbeat.wasFrozen = false
    serverHeartbeat.resumeAt = now + serverHeartbeat.resumeCooldown
  end
  if serverHeartbeat.resumeAt > 0 and now < serverHeartbeat.resumeAt then
    return true
  end
  serverHeartbeat.resumeAt = 0
  return false
end

function helperCycleEvent()
  -- Pausa o helper enquanto o servidor não responder (ex.: server save).
  -- Sem isso, comandos enfileirados derrubam o player por excesso de pacotes ao retomar.
  if isServerFrozen() then
    return
  end

  -- Não executar durante transição de player
  if isTransitioningPlayer then
    return
  end

  -- Always Chase Opponent vs. the cavebot walker.
  --
  -- Dynamic lure and Skip fight near players both mean "keep walking and do
  -- not engage". Chasing means the opposite: the server walks the character
  -- toward the target while the walker is issuing steps toward the next
  -- waypoint, and the two fight for control. Suspend chase for as long as the
  -- cavebot is suppressing combat, then hand the player's setting straight
  -- back. Nothing is lost by doing so -- suppression cancels the attack, so
  -- there is no target to chase in the first place.
  if helperConfig and helperConfig.alwaysChaseOpponent and g_game.isOnline() then
    local cavebot = modules.game_helper and modules.game_helper.cavebot
    local suppressed = cavebot and cavebot.isCombatSuppressed and cavebot.isCombatSuppressed()
    -- Spelled out rather than `suppressed and DontChase or ChaseOpponent`:
    -- DontChase is 0, and that idiom only happens to work because Lua counts 0
    -- as truthy. Not worth leaving as a trap.
    local wantedChaseMode = ChaseOpponent
    if suppressed then
      wantedChaseMode = DontChase
    end
    if g_game.getChaseMode() ~= wantedChaseMode then
      g_game.setChaseMode(wantedChaseMode)
    end
  end

  -- Detectar mudança de player (login com outro personagem)
  local currentPlayer = g_game.getLocalPlayer()
  if currentPlayer then
    local currentName = currentPlayer:getName()
    if lastPlayerName and lastPlayerName ~= currentName then
      lastPlayerName = currentName
      player = currentPlayer
      -- Recarregar configurações do novo player
      scheduleEvent(function()
        if g_game.isOnline() then
          loadSettings()
          -- Registrar hotkeys salvas APÓS loadSettings() carregar os dados
          unregisterAllHelperHotkeys()
          registerSavedHotkeys()
          scheduleEvent(function()
            if healingPanel and toolsPanel and shooterPanel then
              _Helper._suppressMessages = true
              onLoadHelperData()
              _Helper._suppressMessages = false
            end
          end, 200)
        end
      end, 100)
      return
    elseif not lastPlayerName then
      lastPlayerName = currentName
    end
  end

  -- Centralizar captura de espectadores para otimização
  -- Limite de visão do player: 7 tiles horizontal (cada lado), 5 tiles vertical (cada lado)
  local spectatorsSnapshot = nil
  if currentPlayer then
    local pos = currentPlayer:getPosition()
    if pos then
      spectatorsSnapshot = g_map.getSpectatorsInRange(pos, false, 7, 5)
    end
  end
  lastEngineSpectators = spectatorsSnapshot or {}

  for eventName, eventData in pairs(eventTable) do
    -- `timers` is a parallel table to `eventTable`; a key added to one but not
    -- the other used to make this nil + number, which threw and aborted the rest
    -- of the loop for that tick (and pairs() order decides which events die).
    timers[eventName] = (timers[eventName] or 0) + helperEvents.helperCycleTimer
    if timers[eventName] >= eventData.interval then
      timers[eventName] = 0
      local func = eventData.action
      if func and type(func) == "function" then
        -- Passar spectators para funções que podem se beneficiar
        if eventName == "updatePartyHealth" or eventName == "checkFriendHealing" then
          func(lastEngineSpectators)
        else
          func()
        end
      end
    end
  end
end

function isValidAutoTargetCreature(creature)
  return _Helper.AutoTarget.isValidCreature(creature)
end

function online()
  local benchmark = g_clock.millis()
  player = g_game.getLocalPlayer()
  if not player then return end
  local onlinePlayerName = player:getName()
  if helperEvents.helperCycleEvent and activeOnlinePlayerName == onlinePlayerName then
    refreshHelperProfile(player)
    return
  end
  activeOnlinePlayerName = onlinePlayerName
  refreshHelperProfile()

  -- Reset do detector de freeze para a sessão atual
  serverHeartbeat.wasFrozen = false
  serverHeartbeat.resumeAt = 0

  -- bloqueia save até tudo carregar
  skipSaveUntilLoaded = true
  isTransitioningPlayer = true
  helperConfig.currentLockedTargetId = 0

  -- Carrega UI e configurações

  -- Carregar settings se houver arquivo salvo
  scheduleEvent(function()
    if g_game.isOnline() then
      loadSettings()

      -- Registrar hotkeys salvas APÓS loadSettings() carregar os dados
      unregisterAllHelperHotkeys()
      registerSavedHotkeys()

      -- Aplica dados salvos na UI (depois que painéis existem)
      scheduleEvent(function()
        if healingPanel and toolsPanel and shooterPanel then
          _Helper._suppressMessages = true
          onLoadHelperData()
          _Helper._suppressMessages = false
        end

        -- Libera salvamento e ações após carregar
        skipSaveUntilLoaded = false
        isTransitioningPlayer = false
      end, 200)
    end
  end, 500)

  -- Atualiza o status visual do helper após carregar config
  scheduleEvent(function()
    if helper then
      botStatus()
    end
  end, 100)

  helperConfig.currentLockedTargetId = 0
  if helperEvents.helperCycleEvent then
    removeEvent(helperEvents.helperCycleEvent)
    helperEvents.helperCycleEvent = nil
  end
  helperEvents.helperCycleEvent = cycleEvent(helperCycleEvent, helperEvents.helperCycleTimer)

  resetPartyPanel()
  loadMenu('toolsMenu')

  -- ===== ADICIONE AQUI =====
  -- scheduleEvent(function()
  -- local function syncPartyList()
  -- if modules.game_party_list and modules.game_party_list.getPartyMembers then
  -- local members = modules.game_party_list.getPartyMembers()
  -- if members and #members > 0 then
  -- onPartyDataUpdate(members)
  -- end
  -- end
  -- scheduleEvent(syncPartyList, 2000, "helperSyncParty")
  -- end
  -- syncPartyList()
  -- end, 3000)
  -- ===== FIM =====

  if helper then
    botStatus()
  end

  -- Criar o painel de atalhos do helper (shortcut panel) se estiver habilitado
  scheduleEvent(function()
    if g_game.isOnline() and _Helper.Shortcut.isVisible() then
      _Helper.Shortcut.createPanel()
    end
    -- Sincronizar checkbox do helper com o valor carregado
    local contentPanel = getHelperContentPanel()
    if contentPanel then
      local shortcutsCheckbox = contentPanel:recursiveGetChildById('shortcuts')
      if shortcutsCheckbox then
        shortcutsCheckbox:setChecked(_Helper.Shortcut.isVisible())
      end
    end
  end, 1000)

  -- Iniciar Auto Haste se necessario (verifica se player nao tem haste no login)
  scheduleEvent(function()
    if g_game.isOnline() and _Helper.AutoHaste and _Helper.AutoHaste.onLogin then
      _Helper.AutoHaste.onLogin()
    end
  end, 1500)

  -- Iniciar Exercise Training se necessario
  scheduleEvent(function()
    if g_game.isOnline() and _Helper.ExerciseTraining and _Helper.ExerciseTraining.onLogin then
      _Helper.ExerciseTraining.onLogin()
    end
  end, 1600)

  -- Iniciar Timer se necessario
  scheduleEvent(function()
    if g_game.isOnline() and _Helper.Timer and _Helper.Timer.onLogin then
      _Helper.Timer.onLogin()
    end
  end, 1700)
end

function offline()
  activeOnlinePlayerName = nil
  clearHelperProfile()
  if helperVocationEvent then
    removeEvent(helperVocationEvent)
    helperVocationEvent = nil
  end
  -- Save before logout cleanup resets transient UI/alarm state.
  saveSettings()

  if modules.game_helper and modules.game_helper.scripting then
    modules.game_helper.scripting.onGameEnd()
  end

  -- Everything below is runtime/UI cleanup only. Reset helpers update widgets
  -- whose callbacks can save their temporary "off" state. Keep saves blocked
  -- until online() loads this character's settings again.
  skipSaveUntilLoaded = true

  -- Bloquear ações durante transição
  isTransitioningPlayer = true

  -- Parar ciclo de eventos PRIMEIRO para evitar usar dados antigos
  if helperEvents and helperEvents.helperCycleEvent then
    removeEvent(helperEvents.helperCycleEvent)
    helperEvents.helperCycleEvent = nil
  end

  -- Parar cycle event do Auto Haste
  if _Helper.AutoHaste and _Helper.AutoHaste.onLogout then
    _Helper.AutoHaste.onLogout()
  end

  -- Parar cycle event do Exercise Training
  if _Helper.ExerciseTraining and _Helper.ExerciseTraining.onLogout then
    _Helper.ExerciseTraining.onLogout()
  end

  -- Parar Timer
  if _Helper.Timer and _Helper.Timer.onLogout then
    _Helper.Timer.onLogout()
  end

  if _Helper.FollowFriend and _Helper.FollowFriend.reset then
    _Helper.FollowFriend.reset()
  end

  -- Reset PZ state on logout
  if _Helper.resetPZState then
    _Helper.resetPZState()
  end

  -- Reset full dust alarm on logout
  _Helper.FullDustAlarm.resetCheckbox()

  -- Reset low supply alarm on logout
  _Helper.LowSupplyAlarm.resetCheckbox()

  -- Reset private message alarm on logout
  _Helper.PrivateMessageAlarm.resetCheckbox()

  -- Reset low health alarm on logout
  _Helper.LowHealthAlarm.resetCheckbox()

  -- Reset low mana alarm on logout
  _Helper.LowManaAlarm.resetCheckbox()

  -- Fechar special foods window
  destroySpecialFoodsWindow()

  -- Remover hotkeys antes de deslogar (serão re-registradas no próximo online())
  unregisterAllHelperHotkeys()

  -- Clear preset lists on disconnect (keep contexts alive — they're recreated only in init())
  local pm = modules.game_helper and modules.game_helper.presetManager
  if pm then
    local sCtx = pm.getShooterContext()
    if sCtx and sCtx.presetsPanel then
      local presets = sCtx.presetsPanel:recursiveGetChildById('presets')
      if presets then presets:clear() end
    end
    local eCtx = pm.getEquipContext()
    if eCtx and eCtx.presetsPanel then
      local presets = eCtx.presetsPanel:recursiveGetChildById('presets')
      if presets then presets:clear() end
    end
  end

  -- Limpar cooldowns ao deslogar para evitar problemas ao relogar
  for k in pairs(spellsCooldown) do spellsCooldown[k] = nil end
  for k in pairs(groupsCooldown) do groupsCooldown[k] = nil end

  -- Limpar spectators cache
  for k in pairs(lastEngineSpectators) do lastEngineSpectators[k] = nil end

  -- Resetar timers para zero
  for k in pairs(timers) do timers[k] = 0 end

  -- Resetar player para nil
  player = nil
  lastPlayerName = nil

  if helper then
    hide()
  end

  -- Destruir o shortcut panel ao deslogar
  _Helper.Shortcut.destroyPanel()

  -- Forçar coleta de lixo ao deslogar
  scheduleEvent(function()
    collectgarbage("collect")
  end, 500)
end

-- HELPER SHORTCUT PANEL: Funções movidas para classes/shortcut_panel.lua
-- Funções getter para acesso externo às variáveis locais (usadas por _Helper.Shortcut)

_Helper.getHelperWindow = function()
  return helper
end

_Helper.getToolsPanel = function()
  return toolsPanel
end

_Helper.getToolsPanelContainer = function()
  return toolsPanelContainer
end

_Helper.getShooterPanel = function()
  return shooterPanel
end

_Helper.isHelperAutomaticFunctionsEnabled = function()
  return helperAutomaticFunctionsEnabled
end

_Helper.setHelperAutomaticFunctionsEnabled = function(value)
  helperAutomaticFunctionsEnabled = value and true or false
  if helperConfig then
    helperConfig.helperAutomaticFunctionsEnabled = helperAutomaticFunctionsEnabled
  end
  helperDebug("helper state set enabled=" .. tostring(helperAutomaticFunctionsEnabled))
end

-- NOTA: _Helper.saveSettings é definido APÓS a função saveSettings() (linha ~4755)

-- HELPER AUTO HASTE: Funções getter/setter para acesso externo às variáveis locais (usadas por _Helper.AutoHaste)

_Helper.getHelperConfig = function()
  return helperConfig
end

_Helper.getSpellDataById = function(spellId)
  return getSpellDataById(spellId)
end

_Helper.getSpellCooldown = function(spellId)
  return getSpellCooldown(spellId)
end

_Helper.getGroupSpellCooldown = function(groupId)
  return getGroupSpellCooldown(groupId)
end

_Helper.checkHealthPriority = function()
  return checkHealthPriority()
end

_Helper.safeDoThing = function(flag)
  return safeDoThing(flag)
end

_Helper.translateVocation = translateVocation

-- HELPER MANA TRAINING: Funcao getter para acesso externo (usada por _Helper.ManaTraining)
_Helper.castHealingSpell = function(spellData)
  return castHealingSpell(spellData)
end

-- HELPER AUTO FOOD: Funcao setter para acesso externo ao cooldown (usada por _Helper.AutoFood)
_Helper.setSpellCooldown = function(spellId, value)
  spellsCooldown[spellId] = value
end

-- HELPER AUTO TARGET: Funcoes getter/setter para acesso externo (usadas por _Helper.AutoTarget)
_Helper.getSpectators = function()
  return lastEngineSpectators
end

_Helper.getAutoTargetModes = function()
  return autoTargetModes
end

_Helper.getEnableButtons = function()
  return enableButtons
end

_Helper.getDistanceBetween = function(p1, p2)
  return getDistanceBetween(p1, p2)
end

_Helper.isWithinReach = function(pos1, pos2)
  return isWithinReach(pos1, pos2)
end

_Helper.positionCompare = function(position1, position2)
  return positionCompare(position1, position2)
end

_Helper.getAfkTime = function()
  return afkTime
end

_Helper.setAutoTargetOnHold = function(value)
  autoTargetOnHold = value
end

_Helper.getAutoTargetOnHold = function()
  return autoTargetOnHold
end

-- ===== PZ (Protection Zone) Handler =====
-- Handles state transitions for auto_target and magic_shooter when entering/leaving PZ
-- Returns: true if system should continue, false if action should be blocked

-- Internal helper: disable a system permanently (used when disableInProtectZone == true)
local function pzDisableSystem(systemName, showMessage)
  local enableButtons = _Helper.getEnableButtons and _Helper.getEnableButtons()
  if not enableButtons then return end

  if systemName == "autoTarget" then
    local widget = enableButtons:recursiveGetChildById("enableAutoTarget")
    if widget and widget:isChecked() then
      widget:setChecked(false)
      if helperConfig then
        helperConfig.autoTargetEnabled = false
        helperConfig.currentLockedTargetId = 0
        g_game.cancelAttack()
      end
      if showMessage then
        modules.game_textmessage.displayGameMessage("Auto Target disabled (Protection Zone).")
      end
      if _Helper.Shortcut and _Helper.Shortcut.syncButton then
        _Helper.Shortcut.syncButton('shortcutAutoTarget', false)
      end
    end
  elseif systemName == "magicShooter" then
    local widget = enableButtons:recursiveGetChildById("enableMagicShooter")
    if widget and widget:isChecked() then
      widget:setChecked(false)
      if helperConfig then
        helperConfig.magicShooterEnabled = false
      end
      if showMessage then
        modules.game_textmessage.displayGameMessage("Magic Shooter disabled (Protection Zone).")
      end
      if _Helper.Shortcut and _Helper.Shortcut.syncButton then
        _Helper.Shortcut.syncButton('shortcutMagicShooter', false)
      end
    end
  end
end

-- Internal helper: suspend a system temporarily (used when disableInProtectZone == false)
-- For Case A2: We do NOT modify enabled flag, just cancel current attack silently
local function pzSuspendSystem(systemName)
  if systemName == "autoTarget" then
    if helperConfig then
      helperConfig.currentLockedTargetId = 0
    end
    g_game.cancelAttack()
  end
end

-- Internal helper: restore after leaving PZ (for Case A2) - silent
local function pzRestoreSystem(_systemName)
end

-- Main PZ handler - call from check functions
-- Returns: true if action should continue, false if blocked (in PZ)
_Helper.handlePZState = function()
  local player = g_game.getLocalPlayer()
  if not player then return false end

  local inPZ = player:isInProtectionZone()
  local wasInPZ = pzState.wasInPZ

  -- Detect PZ entry (edge: not in PZ -> in PZ)
  if inPZ and not wasInPZ then
    pzState.wasInPZ = true

    -- A protection zone is a temporary runtime pause, not a configuration
    -- change. After death the character reconnects inside a PZ, so permanently
    -- unchecking Shooter/Auto Target here would erase the player's setup.
    pzState.wasAutoTargetEnabled = helperConfig and helperConfig.autoTargetEnabled or false
    pzState.wasMagicShooterEnabled = helperConfig and helperConfig.magicShooterEnabled or false
    if pzState.wasAutoTargetEnabled then
      pzSuspendSystem("autoTarget")
    end
    if pzState.wasMagicShooterEnabled then
      pzSuspendSystem("magicShooter")
    end
  end

  -- Detect PZ exit (edge: in PZ -> not in PZ)
  if not inPZ and wasInPZ then
    pzState.wasInPZ = false

    -- Enabled choices remain intact; combat checks resume naturally outside PZ.
    if helperConfig and not helperConfig.disableInProtectZone then
      if pzState.wasAutoTargetEnabled and helperConfig.autoTargetEnabled then
        pzRestoreSystem("autoTarget")
      end
      if pzState.wasMagicShooterEnabled and helperConfig.magicShooterEnabled then
        pzRestoreSystem("magicShooter")
      end
    end
    -- Reset saved states
    pzState.wasAutoTargetEnabled = false
    pzState.wasMagicShooterEnabled = false
  end

  -- GUARD: Always block actions while in PZ
  if inPZ then
    return false
  end

  return true
end

-- Getter for pzState (for debugging/testing)
_Helper.getPZState = function()
  return pzState
end

-- Reset PZ state (called on logout/character change)
_Helper.resetPZState = function()
  pzState.wasInPZ = false
  pzState.wasAutoTargetEnabled = false
  pzState.wasMagicShooterEnabled = false
end

-- NOTA: _Helper.getShooterProfile é definido mais abaixo, após a função getShooterProfile ser declarada

-- HELPER MAGIC SHOOTER: Funcoes getter/setter para acesso externo (usadas por _Helper.MagicShooter)
_Helper.getHelper = function()
  return helper
end

_Helper.deepCopy = deepCopy
_Helper.defaultShooterProfile = defaultShooterProfile

-- Legacy getter - returns nil since runePanel no longer exists
_Helper.getRunePanel = function()
  return nil
end

_Helper.numberToOrdinal = function(n)
  return numberToOrdinal(n)
end

_Helper.removeAction = removeAction

_Helper.getHarmonyCountSafe = function(p)
  return getHarmonyCountSafe(p)
end

_Helper.canUseByServerVoc = function(spellVocations, serverVocId)
  return canUseByServerVoc(spellVocations, serverVocId)
end

_Helper.playerHasSpell = function(player, spellId)
  return playerHasSpell(player, spellId)
end

-- Retorna a tabela de monstros a ignorar (usado por auto_target e magic_shooter)
_Helper.getIgnoreMonsterTable = function()
  if modules.game_helper and modules.game_helper.magicShooter and modules.game_helper.magicShooter.getIgnoreMonsterTable then
    return modules.game_helper.magicShooter.getIgnoreMonsterTable()
  end
  return {}
end

-- Retorna a whitelist de alvos (nil = atacar todos os monstros)
_Helper.getTargetMonsterTable = function()
  if modules.game_helper and modules.game_helper.magicShooter and modules.game_helper.magicShooter.getTargetMonsterTable then
    return modules.game_helper.magicShooter.getTargetMonsterTable()
  end
  return nil
end

-- NOTA: _Helper.getRelativePosition, _Helper.isSpellOnCooldown, _Helper.onSpellCooldown,
-- _Helper.onSpellGroupCooldown, _Helper.findBestTarget e _Helper.countAttackableCreatures
-- sao definidos mais abaixo no arquivo, apos as funcoes locais correspondentes serem declaradas.

-- Wrapper functions para compatibilidade com chamadas externas (OTUI e outros módulos)
function toggleShortcuts(checked)
  _Helper.Shortcut.toggle(checked)
end

function updateShortcutPanelPosition()
  _Helper.Shortcut.updatePosition()
end

function onShortcutButtonChange(button)
  _Helper.Shortcut.onButtonChange(button)
end

function onSpellCooldown(spellId, delay)
  spellsCooldown[spellId] = g_clock.millis() + delay
end

function onSpellGroupCooldown(groupId, delay)
  groupsCooldown[groupId] = g_clock.millis() + delay
end

function onMultiUseCooldown(time)
  local now = g_clock.millis()
  local newExpiry = now + time
  -- Use gap based on last object type: 125ms for runes, 50ms for potions
  -- Filters latency-induced extensions while respecting genuine server exhaustion
  local gap = lastObjectUseWasRune and 125 or 50
  if multiUseExDelay <= now or newExpiry > multiUseExDelay + gap then
    multiUseExDelay = newExpiry
  end
end

function onUpdateSpellArea(energyWaveEnlarged)
  if energyWaveEnlarged then
    SpellInfo.Default["Energy Wave"].area = SpellAreas.AREA_SQUAREWAVE6
  else
    SpellInfo.Default["Energy Wave"].area = SpellAreas.AREA_SQUAREWAVE4
  end
end

function getShooterProfile()
  local profile = helperConfig.shooterProfiles[helperConfig.selectedShooterProfile]
  if not profile then
    return defaultShooterProfile
  end
  return profile
end

-- HELPER MAGIC SHOOTER: Getter definido apos a funcao getShooterProfile
_Helper.getShooterProfile = getShooterProfile

function loadMenu(menuId)
  local contentPanel = refreshHelperPanelRefs()
  if not helper or not contentPanel then
    return
  end
  fitHelperWindow()
  refreshHelperProfile()

  local optionsTabBar = getHelperTabBar(contentPanel)
  if not optionsTabBar then
    showFallbackHelperMenu()
    return
  end

  local buttons = {
    healingMenu = 'healingMenu',
    toolsMenu = 'toolsMenu',
    shooterMenu = 'shooterMenu',
    equipMenu = "equipMenu",
    cavebotMenu = 'cavebotMenu',
    timerMenu = "timerMenu",
    scriptingMenu = "scriptingMenu",
    settingsFolderMenu = "settingsFolderMenu",
  }

  if not menuId or not buttons[menuId] then
    menuId = 'healingMenu'
  end

  for buttonName, buttonId in pairs(buttons) do
    local button = optionsTabBar:getChildById(buttonId)
    if button then
      button:setChecked(false)
    end
  end

  -- Close alarm settings modals when switching tabs
  if _Helper.AlarmSettings and _Helper.AlarmSettings.close then
    _Helper.AlarmSettings.close()
  end

  -- Default hide Cavebot footer elements
  local cbLabel = helper:recursiveGetChildById('cavebotStatusLabel')
  local cbBtn = helper:recursiveGetChildById('cavebotToggleButton')
  if cbLabel then cbLabel:hide() end
  if cbBtn then cbBtn:hide() end

  lastActiveMenu = menuId

  local selectedButton = optionsTabBar:getChildById(menuId)
  if selectedButton then
    selectedButton:setChecked(true)
  end

  -- Start every tab switch from a known state. Individual branches below only
  -- need to show their own panel, including the standalone Scripting workspace.
  if healingPanel then healingPanel:hide() end
  if toolsPanelContainer then toolsPanelContainer:hide() end
  if shooterPanel then shooterPanel:hide() end
  if equipPanelContainer then equipPanelContainer:hide() end
  if cavebotPanel then cavebotPanel:hide() end
  if timerPanelContainer then timerPanelContainer:hide() end
  if scriptingPanel then scriptingPanel:hide() end
  if settingsPanel then settingsPanel:hide() end

  local currentPlayer = g_game.getLocalPlayer()
  if not currentPlayer then
    if menuId == 'settingsFolderMenu' and settingsPanel then
      if healingPanel then healingPanel:hide() end
      if toolsPanelContainer then toolsPanelContainer:hide() end
      if shooterPanel then shooterPanel:hide() end
      if equipPanelContainer then equipPanelContainer:hide() end
      if cavebotPanel then cavebotPanel:hide() end
      if timerPanelContainer then timerPanelContainer:hide() end
      settingsPanel:show(true)
      refreshHelperSettingsPanel()
      return
    end

    -- If no player, just show default layout
    if healingPanel and toolsPanelContainer and shooterPanel then
      healingPanel:show(true)
      toolsPanelContainer:hide()
      shooterPanel:hide()
      if equipPanelContainer then equipPanelContainer:hide() end
      if cavebotPanel then cavebotPanel:hide() end
      if timerPanelContainer then timerPanelContainer:hide() end
      if settingsPanel then settingsPanel:hide() end
    end
    return
  end

  player = currentPlayer

  if not healingPanel or not shooterPanel then
    showFallbackHelperMenu()
    return
  end

  if menuId == 'healingMenu' then
    healingPanel:show(true)
    if toolsPanelContainer then toolsPanelContainer:hide() end
    shooterPanel:hide()
    if equipPanelContainer then equipPanelContainer:hide() end
    if cavebotPanel then cavebotPanel:hide() end
    if timerPanelContainer then timerPanelContainer:hide() end
    if settingsPanel then settingsPanel:hide() end
    if namedSioPanel then namedSioPanel:setVisible(false) end
    if currentPlayer:isKnight() then
      if healingTargetModePanel then healingTargetModePanel:setVisible(false) end
      friendHealingPanel:setVisible(false)
      granSioPanel:setVisible(false)
      if masResPanel then masResPanel:setVisible(false) end
      if spellButton2 then spellButton2:setVisible(true) end
      if rmvPercentButton2 then rmvPercentButton2:setVisible(true) end
      if spellPercentBg2 then spellPercentBg2:setVisible(true) end
      if addPercentButton2 then addPercentButton2:setVisible(true) end
      potionButton2:setVisible(true)
      rmvPotionPercentButton2:setVisible(true)
      potionPercentBg2:setVisible(true)
      addPotionPercentButton2:setVisible(true)
      priority2:setVisible(true)
      priorityButton1:setTooltip(
        "Uses a healing or mana potion when your health or\nmana reaches the defined percentage.")
      priorityButton2:setTooltip(
        "Uses a healing or mana potion when your health or\nmana reaches the defined percentage.")
      priorityButton3:setTooltip(
        "Uses a healing or mana potion when your health or\nmana reaches the defined percentage.")
    elseif currentPlayer:isPaladin() then
      if healingTargetModePanel then healingTargetModePanel:setVisible(false) end
      friendHealingPanel:setVisible(false)
      granSioPanel:setVisible(false)
      if masResPanel then masResPanel:setVisible(false) end
      if spellButton2 then spellButton2:setVisible(true) end
      if rmvPercentButton2 then rmvPercentButton2:setVisible(true) end
      if spellPercentBg2 then spellPercentBg2:setVisible(true) end
      if addPercentButton2 then addPercentButton2:setVisible(true) end
      potionButton2:setVisible(true)
      rmvPotionPercentButton2:setVisible(true)
      potionPercentBg2:setVisible(true)
      addPotionPercentButton2:setVisible(true)
      priority2:setVisible(true)
      priorityButton1:setTooltip(
        "Uses a healing or mana potion when your health or\nmana reaches the defined percentage.\nClick on this button to change the potion priority:\n  - Icon: Blue (Mana Priority)\n  - Icon: Red  (Health Priority)")
      priorityButton2:setTooltip(
        "Uses a healing or mana potion when your health or\nmana reaches the defined percentage.\nClick on this button to change the potion priority:\n  - Icon: Blue (Mana Priority)\n  - Icon: Red  (Health Priority)")
      priorityButton3:setTooltip(
        "Uses a healing or mana potion when your health or\nmana reaches the defined percentage.\nClick on this button to change the potion priority:\n  - Icon: Blue (Mana Priority)\n  - Icon: Red  (Health Priority)")
    elseif currentPlayer:isSorcerer() then
      if healingTargetModePanel then healingTargetModePanel:setVisible(false) end
      friendHealingPanel:setVisible(false)
      granSioPanel:setVisible(false)
      if masResPanel then masResPanel:setVisible(false) end
      if spellButton2 then spellButton2:setVisible(false) end
      if rmvPercentButton2 then rmvPercentButton2:setVisible(false) end
      if spellPercentBg2 then spellPercentBg2:setVisible(false) end
      if addPercentButton2 then addPercentButton2:setVisible(false) end
      potionButton2:setVisible(false)
      rmvPotionPercentButton2:setVisible(false)
      potionPercentBg2:setVisible(false)
      addPotionPercentButton2:setVisible(false)
      priority2:setVisible(false)
      priorityButton1:setTooltip(
        "Uses a healing or mana potion when your health or\nmana reaches the defined percentage.")
      priorityButton2:setTooltip(
        "Uses a healing or mana potion when your health or\nmana reaches the defined percentage.")
    elseif currentPlayer:isDruid() then
      if healingTargetModePanel then healingTargetModePanel:setVisible(false) end
      if namedSioPanel then namedSioPanel:setVisible(true) end
      friendHealingPanel:setVisible(false)
      granSioPanel:setVisible(false)
      if masResPanel then masResPanel:setVisible(false) end
      if spellButton2 then spellButton2:setVisible(false) end
      if rmvPercentButton2 then rmvPercentButton2:setVisible(false) end
      if spellPercentBg2 then spellPercentBg2:setVisible(false) end
      if addPercentButton2 then addPercentButton2:setVisible(false) end
      potionButton2:setVisible(false)
      rmvPotionPercentButton2:setVisible(false)
      potionPercentBg2:setVisible(false)
      addPotionPercentButton2:setVisible(false)
      priority2:setVisible(false)
      priorityButton1:setTooltip(
        "Uses a healing or mana potion when your health or\nmana reaches the defined percentage.")
      priorityButton2:setTooltip(
        "Uses a healing or mana potion when your health or\nmana reaches the defined percentage.")
    elseif currentPlayer:isMonk() then
      if healingTargetModePanel then healingTargetModePanel:setVisible(false) end
      friendHealingPanel:setVisible(false)
      granSioPanel:setVisible(false)
      if masResPanel then masResPanel:setVisible(false) end
      if spellButton2 then spellButton2:setVisible(true) end
      if rmvPercentButton2 then rmvPercentButton2:setVisible(true) end
      if spellPercentBg2 then spellPercentBg2:setVisible(true) end
      if addPercentButton2 then addPercentButton2:setVisible(true) end
      potionButton2:setVisible(true)
      rmvPotionPercentButton2:setVisible(true)
      potionPercentBg2:setVisible(true)
      addPotionPercentButton2:setVisible(true)
      priority2:setVisible(true)
      priorityButton1:setTooltip(
        "Uses a healing or mana potion when your health or\nmana reaches the defined percentage.\nClick on this button to change the potion priority:\n  - Icon: Blue (Mana Priority)\n  - Icon: Red  (Health Priority)")
      priorityButton2:setTooltip(
        "Uses a healing or mana potion when your health or\nmana reaches the defined percentage.\nClick on this button to change the potion priority:\n  - Icon: Blue (Mana Priority)\n  - Icon: Red  (Health Priority)")
      priorityButton3:setTooltip(
        "Uses a healing or mana potion when your health or\nmana reaches the defined percentage.\nClick on this button to change the potion priority:\n  - Icon: Blue (Mana Priority)\n  - Icon: Red  (Health Priority)")
    else
      if healingTargetModePanel then healingTargetModePanel:setVisible(false) end
      friendHealingPanel:setVisible(false)
      granSioPanel:setVisible(false)
      if masResPanel then masResPanel:setVisible(false) end
      if spellButton2 then spellButton2:setVisible(false) end
      if rmvPercentButton2 then rmvPercentButton2:setVisible(false) end
      if spellPercentBg2 then spellPercentBg2:setVisible(false) end
      if addPercentButton2 then addPercentButton2:setVisible(false) end
      potionButton2:setVisible(false)
      rmvPotionPercentButton2:setVisible(false)
      potionPercentBg2:setVisible(false)
      addPotionPercentButton2:setVisible(false)
      priority2:setVisible(false)
      priorityButton1:setTooltip(
        "Uses a healing or mana potion when your health or\nmana reaches the defined percentage.")
      priorityButton2:setTooltip(
        "Uses a healing or mana potion when your health or\nmana reaches the defined percentage.")
    end
    local thirdSpellHelp = healingPanel:recursiveGetChildById('thirdSpellHelp')
    if thirdSpellHelp then thirdSpellHelp:setVisible(spellButton2 and spellButton2:isVisible() or false) end
  elseif menuId == 'toolsMenu' then
    healingPanel:hide()
    shooterPanel:hide()
    if equipPanelContainer then equipPanelContainer:hide() end
    if cavebotPanel then cavebotPanel:hide() end
    if timerPanelContainer then timerPanelContainer:hide() end
    if settingsPanel then settingsPanel:hide() end
    if toolsPanelContainer then toolsPanelContainer:show(true) end

    -- Update vocation-specific panels visibility
    if modules.game_helper and modules.game_helper.tools and modules.game_helper.tools.updateVocationPanels then
      modules.game_helper.tools.updateVocationPanels()
    end

    -- Wide desktop layout; the vocation panel shares the third column and no
    -- longer increases the window height.
  elseif menuId == 'shooterMenu' then
    healingPanel:hide()
    if toolsPanelContainer then toolsPanelContainer:hide() end
    if equipPanelContainer then equipPanelContainer:hide() end
    if cavebotPanel then cavebotPanel:hide() end
    if timerPanelContainer then timerPanelContainer:hide() end
    if settingsPanel then settingsPanel:hide() end
    shooterPanel:show(true)
    -- Targeting uses a wider workspace so conditions remain readable and
    -- preset/actions controls do not collide.
    -- Update rules list when switching to shooter menu
    if modules.game_helper and modules.game_helper.magicShooter then
      modules.game_helper.magicShooter.updateUI()
    end
  elseif menuId == 'equipMenu' then
    healingPanel:hide()
    shooterPanel:hide()
    if toolsPanelContainer then toolsPanelContainer:hide() end
    if equipPanelContainer then
      equipPanelContainer:show(true)
    end
    if cavebotPanel then cavebotPanel:hide() end
    if timerPanelContainer then timerPanelContainer:hide() end
    if settingsPanel then settingsPanel:hide() end
  elseif menuId == 'cavebotMenu' then
    healingPanel:hide()
    shooterPanel:hide()
    if toolsPanelContainer then toolsPanelContainer:hide() end
    if equipPanelContainer then equipPanelContainer:hide() end
    if timerPanelContainer then timerPanelContainer:hide() end
    if settingsPanel then settingsPanel:hide() end
    if cavebotPanel then cavebotPanel:show(true) end
    if cbLabel then cbLabel:show() end
    if cbBtn then cbBtn:show() end
    -- Migra scripts antigos e carrega lista de sessões do cavebot ao abrir a aba
    if cavebot then
      if cavebot.migrateOldScripts then
        cavebot.migrateOldScripts()
      end
      if cavebot.loadSessionList then
        cavebot.loadSessionList()
      end
    end
  elseif menuId == 'timerMenu' then
    healingPanel:hide()
    shooterPanel:hide()
    if toolsPanelContainer then toolsPanelContainer:hide() end
    if equipPanelContainer then equipPanelContainer:hide() end
    if cavebotPanel then cavebotPanel:hide() end
    if timerPanelContainer then timerPanelContainer:show(true) end
    if settingsPanel then settingsPanel:hide() end
  elseif menuId == 'scriptingMenu' then
    if scriptingPanel then scriptingPanel:show(true) end
  elseif menuId == 'settingsFolderMenu' then
    healingPanel:hide()
    shooterPanel:hide()
    if toolsPanelContainer then toolsPanelContainer:hide() end
    if equipPanelContainer then equipPanelContainer:hide() end
    if cavebotPanel then cavebotPanel:hide() end
    if timerPanelContainer then timerPanelContainer:hide() end
    if settingsPanel then settingsPanel:show(true) end
    refreshHelperSettingsPanel()
  end
end

--[[ Events ]] --
function assignTrainingSpell(button, isHaste, isParalyzeCure)
  local window = g_ui.loadUI('styles/spell', g_ui.getRootWidget())
  if not window then
    return true
  end

  window:show(true)
  window:raise()
  window:focus()
  if g_client and g_client.setInputLockWidget then
    g_client.setInputLockWidget(window)
  end
  helper:hide()

  local windowHeader = isParalyzeCure and "Assign Cure Paralyze Spell" or
      (isHaste and "Assign Haste Spell" or "Assign Training Spell")
  window:setText(windowHeader)

  local localPlayer = g_game.getLocalPlayer()
  if not localPlayer then
    window:destroy()
    helper:show()
    return
  end

  local playerVocation = translateVocation(localPlayer:getVocation())
  local spells = modules.gamelib.SpellInfo and modules.gamelib.SpellInfo['Default'] or {}

  -- Get spell data from centralized module
  local allowedHasteForVoc = HelperSpellData.getHasteSpellsForVocation(playerVocation)
  local trainingHealSpellsSet = HelperSpellData.getTrainingHealSpellsSet()
  local allowedTrainingSpells = trainingHealSpellsSet[playerVocation] or {}

  -- Manual selection (avoid RadioGroup getY errors)
  local selectedWidget = nil

  local addedSpells = 0
  for spellName, spellData in pairs(spells) do
    if not spellData then goto continue end

    local spellId = spellData.id
    local groups = (Spells.getGroupIds and Spells.getGroupIds(spellData)) or {}
    local vocs = (spellData and spellData.vocations) or {}

    if isParalyzeCure then
      if not spellData.words or spellData.words == '' or not table.contains(vocs, localPlayer:getVocation()) then
        goto continue
      end
    elseif isHaste then
      -- Haste: show ID 6 or whitelist for vocation
      if not (spellId == 6 or table.contains(allowedHasteForVoc, spellId)) then
        goto continue
      end
    else
      -- Training: only show spells in the whitelist for this vocation
      if not allowedTrainingSpells[spellId] then
        goto continue
      end
    end

    addedSpells = addedSpells + 1
    local widget = g_ui.createWidget('SpellPreview', window.contentPanel.spellList)

    widget:setId(spellId)
    widget:setText(spellName .. "\n" .. spellData.words)
    widget.voc = vocs

    widget.source = _Helper.getSpellIconSource()
    widget.clip = _Helper.getSpellIconClip(spellData)
    widget.image:setImageSource(widget.source)
    widget.image:setImageClip(widget.clip)

    -- Manual select behavior
    widget.onClick = function(clickedWidget)
      if selectedWidget and not selectedWidget:isDestroyed() then
        selectedWidget:setChecked(false)
      end
      clickedWidget:setChecked(true)
      selectedWidget = clickedWidget
      window.contentPanel.preview:setText(clickedWidget:getText())
      window.contentPanel.preview.image:setImageSource(clickedWidget.source)
      window.contentPanel.preview.image:setImageClip(clickedWidget.clip)
    end

    if spellData.level then
      widget.levelLabel:setVisible(true)
      widget.levelLabel:setText(string.format("Level: %d", spellData.level))
      if localPlayer:getLevel() < spellData.level then
        widget.image.gray:setVisible(true)
      end
    end

    local primaryGroup = Spells.getPrimaryGroup(spellData)
    if primaryGroup ~= -1 then
      local offSet = 1
      if primaryGroup == 2 then
        offSet = (23 * (primaryGroup - 1))
      elseif primaryGroup == 3 then
        offSet = (23 * (primaryGroup - 1)) - 1
      end
      widget.imageGroup:setImageClip(offSet .. " 25 20 20")
      widget.imageGroup:setVisible(true)
    end

    ::continue::
  end

  -- Order the spell list
  local widgets = window.contentPanel.spellList:getChildren()
  table.sort(widgets, function(a, b) return a:getText() < b:getText() end)
  for i, widget in ipairs(widgets) do
    window.contentPanel.spellList:moveChildToIndex(widget, i)
  end

  -- Manual OK handler
  local okFunc = function(destroy)
    if not selectedWidget then
      return
    end

    local spellIcon = selectedWidget.source
    local spellClip = selectedWidget.clip
    local spellId = selectedWidget:getId()
    local spellName = selectedWidget:getText():match("^(.-)\n")
    local spellWords = selectedWidget:getText():match("\n(.+)")

    local slotID = tonumber(button:getId():match("%d+"))
    if isParalyzeCure then
      helperConfig.paralyzeCure[1].id = tonumber(spellId)
    elseif isHaste then
      -- Usa o modulo AutoHaste para configurar
      local helperConfigLocal = _Helper.getHelperConfig and _Helper.getHelperConfig() or helperConfig
      helperConfigLocal.haste[slotID + 1].id = tonumber(spellId)
    else
      helperConfig.training[1].id = tonumber(spellId)
      if helperConfig.training[1].percent == 0 then
        helperConfig.training[1].percent = 100
        updateTrainingPercent('spellTrainingButton0', helperConfig.training[1].percent)
      end
    end

    if g_client and g_client.setInputLockWidget then
      g_client.setInputLockWidget(nil)
    end
    button:setImageSource(spellIcon)
    button:setImageClip(spellClip)
    button:setBorderColorTop("#1b1b1b")
    button:setBorderColorLeft("#1b1b1b")
    button:setBorderColorRight("#757575")
    button:setBorderColorBottom("#757575")
    button:setBorderWidth(1)
    button:setTooltip("Spell: " .. spellName .. "\nWords: " .. spellWords)
    saveSettings()

    if destroy then
      helper:show(true)
      -- Limpar referências antes de destruir
      local spellListWidgets = window.contentPanel.spellList:getChildren()
      for _, w in ipairs(spellListWidgets) do
        w.onClick = nil
        w.source = nil
        w.clip = nil
        w.voc = nil
      end
      selectedWidget = nil
      window:destroy()
    end
  end

  local cancelFunc = function()
    helper:show(true)
    if g_client and g_client.setInputLockWidget then
      g_client.setInputLockWidget(nil)
    end
    -- Limpar referências antes de destruir
    local spellListWidgets = window.contentPanel.spellList:getChildren()
    for _, w in ipairs(spellListWidgets) do
      w.onClick = nil
      w.source = nil
      w.clip = nil
      w.voc = nil
    end
    selectedWidget = nil
    window:destroy()
  end

  window.contentPanel.buttonOk.onClick = function() okFunc(true) end
  window.contentPanel.buttonApply.onClick = function() okFunc(false) end
  window.contentPanel.buttonClose.onClick = cancelFunc
  window.contentPanel.onEnter = function() okFunc(true) end
  window.onEscape = cancelFunc
end

function assignSpell(button, groupName, groups, tableToAssign)
  local radio = UIRadioGroup.create()
  local window = g_ui.loadUI('styles/spell', g_ui.getRootWidget())
  if not window then
    return true
  end

  window:show(true)
  window:raise()
  window:focus()
  if g_client and g_client.setInputLockWidget then
    g_client.setInputLockWidget(window)
  end
  helper:hide()

  window:setText("Assign " .. groupName .. " Spell")

  local profile = getShooterProfile()
  local playerVocation = translateVocation(player:getVocation())

  -- Get spell data from centralized module
  local spellFilterByVocation = HelperSpellData.getSpellFilterByVocation()
  local healingSpellFilter = HelperSpellData.getHealingSpellFilter()

  -- Detecta se é janela de healing (grupo 2)
  local isHealingWindow = false
  for _, group in ipairs(groups) do
    if group == 2 then
      isHealingWindow = true
      break
    end
  end

  -- Get allowed spell IDs for this vocation
  local allowedSpellIds = spellFilterByVocation[playerVocation] or {}
  local allowedSpellIdSet = {}

  if isHealingWindow then
    -- Para healing spells, usar o filtro específico de cura
    allowedSpellIdSet = HelperSpellData.getHealingSpellsForVocation(playerVocation)
  else
    -- Para attack spells, usar o filtro geral por vocação
    for _, id in ipairs(allowedSpellIds) do
      allowedSpellIdSet[id] = true
    end
  end

  -- Table to hold widgets before adding to radio group
  local spellWidgets = {}

  -- Get spells from SpellInfo
  local spells = modules.gamelib.SpellInfo['Default']
  for spellName, spellData in pairs(spells) do
    local groupIds = Spells.getGroupIds(spellData)

    -- Check if spell ID is allowed for this vocation
    if not allowedSpellIdSet[spellData.id] then
      goto continue_spell
    end

    -- Check if spell is in correct group (skip for healing window, healingSpellFilter is authoritative)
    if not isHealingWindow and not containsAnyGroup(groupIds, groups) then
      goto continue_spell
    end

    if HelperSpellData.getIgnoredSpellsIds()[spellData.id] then
      goto continue_spell
    end

    -- Do not filter by level; show all and mark unmet level

    local widget = g_ui.createWidget('SpellPreview', window.contentPanel.spellList)

    -- Store widget for later, don't add to radio yet
    table.insert(spellWidgets, widget)
    widget:setId(spellData.id)
    widget:setText(spellName .. "\n" .. spellData.words)
    widget.voc = spellData.vocations

    widget.source = _Helper.getSpellIconSource()
    widget.clip = _Helper.getSpellIconClip(spellData)
    widget.image:setImageSource(widget.source)
    widget.image:setImageClip(widget.clip)

    if spellData.level then
      widget.levelLabel:setVisible(true)
      widget.levelLabel:setText(string.format("Level: %d", spellData.level))
      if player:getLevel() < spellData.level then
        widget.image.gray:setVisible(true)
      end
    end

    local primaryGroup = Spells.getPrimaryGroup(spellData)
    if primaryGroup ~= -1 then
      local offSet = 1
      if primaryGroup == 2 then
        offSet = (23 * (primaryGroup - 1))
      elseif primaryGroup == 3 then
        offSet = (23 * (primaryGroup - 1)) - 1
      end
      widget.imageGroup:setImageClip(offSet .. " 25 20 20")
      widget.imageGroup:setVisible(true)
    end

    ::continue_spell::
  end

  -- sort alphabetically
  local widgets = window.contentPanel.spellList:getChildren()
  table.sort(widgets, function(a, b) return a:getText() < b:getText() end)
  for i, widget in ipairs(widgets) do
    window.contentPanel.spellList:moveChildToIndex(widget, i)
  end

  -- Manual selection system instead of radio group to avoid getY() errors
  local selectedWidget = nil

  for _, widget in ipairs(spellWidgets) do
    if widget and not widget:isDestroyed() then
      widget.onClick = function(clickedWidget)
        -- Deselect previous
        if selectedWidget then
          selectedWidget:setChecked(false)
        end
        -- Select new
        clickedWidget:setChecked(true)
        selectedWidget = clickedWidget
        -- Update preview
        window.contentPanel.preview:setText(clickedWidget:getText())
        window.contentPanel.preview.image:setImageSource(clickedWidget.source)
        window.contentPanel.preview.image:setImageClip(clickedWidget.clip)
      end
    end
  end

  -- Don't use radio group at all to avoid errors

  window:recursiveGetChildById('tick'):setChecked(true)
  window:recursiveGetChildById('tick'):setEnabled(false)

  local okFunc = function(destroy, profile)
    if not selectedWidget then
      modules.game_textmessage.displayGameMessage("Please select a spell first!")
      return
    end

    local profile = getShooterProfile()
    local spellIcon = selectedWidget.source
    local spellClip = selectedWidget.clip
    local spellId = selectedWidget:getId()
    local spellName = selectedWidget:getText():match("^(.-)\n")
    local spellWords = selectedWidget:getText():match("\n(.+)")

    local slotID = tonumber(button:getId():match("%d+"))
    if button:getId():find("attackSpellButton") then
      profile.spells[slotID + 1].id = tonumber(spellId)
      profile.spells[slotID + 1].name = spellName
    else
      tableToAssign[slotID + 1].id = tonumber(spellId)
      tableToAssign[slotID + 1].name = spellName
    end

    if g_client and g_client.setInputLockWidget then
      g_client.setInputLockWidget(nil)
    end
    button:setImageSource(spellIcon)
    button:setImageClip(spellClip)
    button:setBorderColorTop("#1b1b1b")
    button:setBorderColorLeft("#1b1b1b")
    button:setBorderColorRight("#757575")
    button:setBorderColorBottom("#757575")
    button:setBorderWidth(1)
    button:setTooltip("Spell: " .. spellName .. "\nWords: " .. spellWords)

    if button:getId():find("attackSpellButton") then
      local creaturesMin = shooterPanel:recursiveGetChildById("countMinCreature" .. slotID)
      local forceCast = shooterPanel:recursiveGetChildById("conditionSetting" .. slotID)
      local selfCast = shooterPanel:recursiveGetChildById("selfCast" .. slotID)
      local spell = Spells.getSpellByClientId(tonumber(spellId))
      if spell then
        if table.contains(bothCastTypeSpells, spell.id) then -- divine grenade self cast
          if not selfCast then
            selfCast = g_ui.createWidget('CheckBox', creaturesMin:getParent())
            local style = {
              ["width"] = 12,
              ["anchors.top"] = "countMinCreature" .. slotID .. ".top",
              ["anchors.left"] = "countMinCreature" .. slotID .. ".right",
              ["margin-top"] = 6,
              ["margin-left"] = 5
            }
            selfCast:mergeStyle(style)
            selfCast:setId('selfCast' .. slotID)
            selfCast:setTooltip('Cast On Foot')
            selfCast:setVisible(true)
            selfCast.onCheckChange = function() toggleSelfCast(selfCast:getId():match("%d+"), selfCast:isChecked()) end
          end
        end
        if selfCast and not table.contains(bothCastTypeSpells, spell.id) then
          profile.spells[slotID + 1].selfCast = false
          selfCast:destroy()
        end
        if (spell.range > 0 or not spell.area) and not table.contains(bothCastTypeSpells, spell.id) then
          profile.spells[slotID + 1].creatures = 1
          creaturesMin:setCurrentOption("1+")
          creaturesMin:disable()
          if forceCast then
            forceCast:setChecked(profile.spells[slotID + 1].forceCast)
            forceCast:setVisible(true)
          end
        else
          creaturesMin:enable()
          if forceCast then
            forceCast:setChecked(false)
            forceCast:setVisible(false)
            profile.spells[slotID + 1].forceCast = false
          end
        end
      end
    end
    -- Persist configuration after assignment
    saveSettings()

    if destroy then
      helper:show()
      -- Limpar referências antes de destruir
      for _, w in ipairs(spellWidgets) do
        w.onClick = nil
        w.source = nil
        w.clip = nil
        w.voc = nil
      end
      spellWidgets = {}
      selectedWidget = nil
      window:destroy()
    end
  end

  local cancelFunc = function()
    helper:show()
    if g_client and g_client.setInputLockWidget then
      g_client.setInputLockWidget(nil)
    end
    -- Limpar referências antes de destruir
    for _, w in ipairs(spellWidgets) do
      w.onClick = nil
      w.source = nil
      w.clip = nil
      w.voc = nil
    end
    spellWidgets = {}
    selectedWidget = nil
    window:destroy()
  end

  window.contentPanel.buttonOk.onClick = function() okFunc(true) end
  window.contentPanel.buttonApply.onClick = function() okFunc(false) end
  window.contentPanel.buttonClose.onClick = cancelFunc
  window.contentPanel.onEnter = function() okFunc(true) end
  window.onEscape = cancelFunc
end

function assignRune(button, groupName, groups, tableToAssign)
  mouseGrabberWidget:grabMouse()
  helper:hide()
  g_mouse.pushCursor('target')
  mouseGrabberWidget.onMouseRelease = function(self, mousePosition, mouseButton)
    onAssignRune(self, mousePosition, mouseButton, button)
  end
end

function onAssignRune(self, mousePosition, mouseButton, button)
  mouseGrabberWidget:ungrabMouse()
  helper:show()
  g_mouse.popCursor('target')
  mouseGrabberWidget.onMouseRelease = nil

  local rootWidget = g_ui.getRootWidget()
  if not rootWidget then
    return true
  end

  local clickedWidget = rootWidget:recursiveGetChildByPos(mousePosition, false)
  if not clickedWidget then
    return true
  end

  local runeId = 0
  if clickedWidget:getClassName() == 'UIItem' and not clickedWidget:isVirtual() then
    local item = clickedWidget:getItem()
    if item then
      runeId = item:getId()
    end
  elseif clickedWidget:getClassName() == 'UIGameMap' then
    local tile = clickedWidget:getTile(mousePosition)
    if tile then
      local topUseThing = tile:getTopUseThing()
      if topUseThing then
        runeId = topUseThing:getId()
      end
    end
  end

  local rune = Spells.getRuneSpellByItem(runeId)
  if not rune and CustomRuneIds then rune = CustomRuneIds[runeId] end
  _Helper.resolveCustomRuneArea(rune)
  if rune and rune.group == 1 then
    if rune.vocations and not canUseByServerVoc(rune.vocations, player:getVocation()) then
      modules.game_textmessage.displayFailureMessage(tr('Your vocation can not use this rune.'))
      return true
    end
    updateRuneButton(button, runeId, rune)
  else
    modules.game_textmessage.displayFailureMessage(tr('Invalid rune!'))
  end
end

-- Legacy function - kept for backward compatibility
-- New system uses magic_shooter_panel.lua
function updateRuneButton(button, runeId, rune)
  -- New unified panel doesn't use this function
  -- Just log and return
  safeLog("debug", "updateRuneButton called - legacy function, use magic_shooter_panel instead")
end

-- Function for Magic Shooter Panel to select spells
function assignSpellForMagicShooter(button, callback)
  local radio = UIRadioGroup.create()
  local window = g_ui.loadUI('styles/spell', g_ui.getRootWidget())
  if not window then
    return true
  end

  window:show(true)
  window:raise()
  window:focus()
  if g_client and g_client.setInputLockWidget then
    g_client.setInputLockWidget(window)
  end
  helper:hide()

  window:setText("Select Attack Spell")

  local profile = getShooterProfile()
  local playerVocation = translateVocation(player:getVocation())
  local groups = { 1, 4, 8 } -- Attack groups

  local spellFilterByVocation = HelperSpellData.getSpellFilterByVocation()
  local allowedSpellIds = spellFilterByVocation[playerVocation] or {}
  local allowedSpellIdSet = {}
  for _, id in ipairs(allowedSpellIds) do
    allowedSpellIdSet[id] = true
  end

  local spellWidgets = {}
  local spells = modules.gamelib.SpellInfo['Default']
  for spellName, spellData in pairs(spells) do
    local groupIds = Spells.getGroupIds(spellData)
    local isAttackGroup = containsAnyGroup(groupIds, groups)
    local isSupportAllowed = HelperSpellData.isSupportSpellAllowed(spellData.id, playerVocation)

    -- Deve estar em grupo de ataque OU na whitelist de suporte
    if not isAttackGroup and not isSupportAllowed then
      goto continue_spell
    end
    if not allowedSpellIdSet[spellData.id] then
      goto continue_spell
    end
    if HelperSpellData.getIgnoredSpellsIds()[spellData.id] then
      goto continue_spell
    end

    local widget = g_ui.createWidget('SpellPreview', window.contentPanel.spellList)
    table.insert(spellWidgets, widget)
    widget:setId(spellData.id)
    widget:setText(spellName .. "\n" .. spellData.words)
    widget.voc = spellData.vocations

    widget.source = _Helper.getSpellIconSource()
    widget.clip = _Helper.getSpellIconClip(spellData)
    widget.image:setImageSource(widget.source)
    widget.image:setImageClip(widget.clip)

    if spellData.level then
      widget.levelLabel:setVisible(true)
      widget.levelLabel:setText(string.format("Level: %d", spellData.level))
      if player:getLevel() < spellData.level then
        widget.image.gray:setVisible(true)
      end
    end

    local primaryGroup = Spells.getPrimaryGroup(spellData)
    if primaryGroup ~= -1 then
      local offSet = 1
      if primaryGroup == 2 then
        offSet = (23 * (primaryGroup - 1))
      elseif primaryGroup == 3 then
        offSet = (23 * (primaryGroup - 1)) - 1
      end
      widget.imageGroup:setImageClip(offSet .. " 25 20 20")
      widget.imageGroup:setVisible(true)
    end

    ::continue_spell::
  end

  local widgets = window.contentPanel.spellList:getChildren()
  table.sort(widgets, function(a, b) return a:getText() < b:getText() end)
  for i, widget in ipairs(widgets) do
    window.contentPanel.spellList:moveChildToIndex(widget, i)
  end

  local selectedWidget = nil
  for _, widget in ipairs(spellWidgets) do
    if widget and not widget:isDestroyed() then
      widget.onClick = function(clickedWidget)
        if selectedWidget then
          selectedWidget:setChecked(false)
        end
        clickedWidget:setChecked(true)
        selectedWidget = clickedWidget
        window.contentPanel.preview:setText(clickedWidget:getText())
        window.contentPanel.preview.image:setImageSource(clickedWidget.source)
        window.contentPanel.preview.image:setImageClip(clickedWidget.clip)
      end
    end
  end

  window:recursiveGetChildById('tick'):setChecked(true)
  window:recursiveGetChildById('tick'):setEnabled(false)

  local okFunc = function(destroy)
    if not selectedWidget then
      modules.game_textmessage.displayGameMessage("Please select a spell first!")
      return
    end

    local spellId = selectedWidget:getId()
    local spellName = selectedWidget:getText():match("^(.-)\n")
    local spellWords = selectedWidget:getText():match("\n(.+)")

    if g_client and g_client.setInputLockWidget then
      g_client.setInputLockWidget(nil)
    end

    -- Call the callback with spell data
    if callback then
      callback({
        id = tonumber(spellId),
        name = spellName,
        words = spellWords,
        source = selectedWidget.source,
        clip = selectedWidget.clip
      })
    end

    if destroy then
      helper:show()
      for _, w in ipairs(spellWidgets) do
        w.onClick = nil
        w.source = nil
        w.clip = nil
        w.voc = nil
      end
      spellWidgets = {}
      selectedWidget = nil
      window:destroy()
    end
  end

  local cancelFunc = function()
    helper:show()
    if g_client and g_client.setInputLockWidget then
      g_client.setInputLockWidget(nil)
    end
    for _, w in ipairs(spellWidgets) do
      w.onClick = nil
      w.source = nil
      w.clip = nil
      w.voc = nil
    end
    spellWidgets = {}
    selectedWidget = nil
    window:destroy()
  end

  window.contentPanel.buttonOk.onClick = function() okFunc(true) end
  window.contentPanel.buttonApply.onClick = function() okFunc(false) end
  window.contentPanel.buttonClose.onClick = cancelFunc
  window.contentPanel.onEnter = function() okFunc(true) end
  window.onEscape = cancelFunc
end

function getPotionInfoById(itemId)
  local potionWhitelist = HelperSpellData.getPotionWhitelist()
  for _, potion in pairs(potionWhitelist) do
    if itemId == potion.id then
      return true, potion.name
    end
  end
  return false, "Unknown Potion"
end

function isHealthPotion(potionId)
  local potionWhitelist = HelperSpellData.getPotionWhitelist()
  for _, potion in ipairs(potionWhitelist) do
    if potion.id == potionId and potion.type == "health" then
      return true
    end
  end
  return false
end

function isManaPotion(potionId)
  local potionWhitelist = HelperSpellData.getPotionWhitelist()
  for _, potion in ipairs(potionWhitelist) do
    if potion.id == potionId and potion.type == "mana" then
      return true
    end
  end
  return false
end

function usePotion(potionId)
  local player = g_game.getLocalPlayer()
  if not player or not potionId or potionId == 0 then
    return false
  end

  local now = g_clock.millis()

  local cooldown = spellsCooldown[potionConfig.id] or 0
  if cooldown > now then
    return false
  end

  if multiUseExDelay > now then
    return false
  end

  -- Turn system: after rune, give rune priority before next potion
  if potionTurnCooldown > now then
    return false
  end

  -- Usar getInventoryCount que funciona com containers fechados
  local potionCount = player:getInventoryCount(potionId, 0)
  if potionCount and potionCount > 0 then
    safeDoThing(false)
    g_game.useInventoryItemWith(potionId, player, 0, true)
    safeDoThing(true)
    local expires = now + potionConfig.exhaustion
    spellsCooldown[potionConfig.id] = expires
    multiUseExDelay = expires
    lastObjectUseWasRune = false
    -- If magic shooter is enabled, block next potion for 1100ms
    -- so rune has a 100ms priority window after the 1000ms shared exhaust expires
    -- If magic shooter is enabled, block next potion for 1100ms
    -- so rune has a 100ms priority window after the 1000ms shared exhaust expires
    if helperConfig.magicShooterEnabled then
      potionTurnCooldown = now + 1100
    end
    return true
  end

  return false
end

function assignPotionEvent(button)
  mouseGrabberWidget:grabMouse()
  helper:hide()
  g_mouse.pushCursor('target')
  mouseGrabberWidget.onMouseRelease = function(self, mousePosition, mouseButton)
    onAssignPotion(self, mousePosition, mouseButton, button)
  end
end

function onAssignPotion(self, mousePosition, mouseButton, button)
  mouseGrabberWidget:ungrabMouse()
  helper:show()
  g_mouse.popCursor('target')
  mouseGrabberWidget.onMouseRelease = nil

  local rootWidget = g_ui.getRootWidget()
  if not rootWidget then
    return true
  end

  local clickedWidget = rootWidget:recursiveGetChildByPos(mousePosition, false)
  if not clickedWidget then
    return true
  end

  local potionId = 0
  if clickedWidget:getClassName() == 'UIItem' and not clickedWidget:isVirtual() then
    local item = clickedWidget:getItem()
    if item then
      potionId = item:getId()
    end
  elseif clickedWidget:getClassName() == 'UIGameMap' then
    local tile = clickedWidget:getTile(mousePosition)
    if tile then
      local topUseThing = tile:getTopUseThing()
      if topUseThing then
        potionId = topUseThing:getId()
      end
    end
  end

  local isPotion, potionName = getPotionInfoById(potionId)
  if isPotion then
    updatePotionButton(button, potionId, potionName)
  else
    modules.game_textmessage.displayFailureMessage(tr('Invalid potion!'))
  end
end

function updatePotionButton(button, potionId, potionName)
  button:setImageSource('/images/ui/item')

  if not button:getChildById('potionItem') then
    local itemWidget = g_ui.createWidget('PotionItem', button)
    itemWidget:setId('potionItem')
  end

  local itemWidget = button:getChildById('potionItem')
  itemWidget:setItemId(potionId)
  itemWidget:setTooltip(potionName)

  local buttonId = button:getId()
  local slotID = tonumber(buttonId:match("%d+"))
  helperConfig.potions[slotID + 1].id = potionId
  helperConfig.potions[slotID + 1].percent = helperConfig.potions[slotID + 1].percent

  local priorityButton = healingPanel:recursiveGetChildById("priority" .. slotID)

  if isManaPotion(potionId) then
    helperConfig.potions[slotID + 1].priority = 2
    priorityButton:setImageSource("/images/ui/checkboxcircle")
    priorityButton:setImageColor("#0066ff")
    priorityButton:setTooltip("This potion is healing mana...")
  elseif isHealthPotion(potionId) then
    helperConfig.potions[slotID + 1].priority = 1
    priorityButton:setImageSource("/images/ui/checkboxcircle")
    priorityButton:setImageColor("#d94a3a")
    priorityButton:setTooltip("This potion is healing health...")
  else
    helperConfig.potions[slotID + 1].priority = 0
    priorityButton:setImageSource("/images/ui/checkbox")
    priorityButton:setImageColor("$var-text-cip-color-white")
    priorityButton:setTooltip("No potion selected")
  end
  rebuildHealingCache()
  -- Persist immediately: the Enable/Disable button reloads helper.json, so an
  -- unsaved assignment would be wiped the next time it is pressed.
  saveSettings()
end

function updateButton(button)
  local profile = getShooterProfile()
  local index = tonumber(button:getId():match("%d+"))
  local buttonId = button:getId()

  button.onMousePress = function(self, mousePos, mouseButton)
    if mouseButton == MouseRightButton then
      local menu = g_ui.createWidget('PopupMenu')
      menu:setGameMenu(true)
      if buttonId:find("runeShooterButton") then
        if profile.runes[index + 1].id > 0 then
          menu:addOption(tr('Edit Rune'), function() assignRune(button) end)
          menu:addOption(tr('Remove'), function() removeAction("rune", button) end)
        else
          menu:addOption(tr('Assign Rune'), function() assignRune(button) end)
        end
      elseif buttonId:find("attackSpellButton") then
        if profile.spells[index + 1].id > 0 then
          menu:addOption(tr('Edit Spell'), function() assignSpell(button, "Aggressive", { 1, 4, 8 }, profile.spells) end)
          menu:addOption(tr('Remove'), function() removeAction("shooter", button) end)
        else
          menu:addOption(tr('Assign Spell'),
            function() assignSpell(button, "Aggressive", { 1, 4, 8 }, profile.spells) end)
        end
      elseif buttonId:find("spellButton") then
        if helperConfig.spells[index + 1].id > 0 then
          menu:addOption(tr('Edit Spell'), function() assignSpell(button, "Healing", { 2 }, helperConfig.spells) end)
          menu:addOption(tr('Remove'), function() removeAction("spell", button) end)
        else
          menu:addOption(tr('Assign Spell'), function() assignSpell(button, "Healing", { 2 }, helperConfig.spells) end)
        end
      elseif buttonId:find("potionButton") then
        if helperConfig.potions[index + 1].id > 0 then
          menu:addOption(tr('Edit Potion'), function() assignPotionEvent(button) end)
          menu:addOption(tr('Remove'), function() removeAction("potion", button) end)
        else
          menu:addOption(tr('Assign Potion'), function() assignPotionEvent(button) end)
        end
      elseif buttonId:find("spellTrainingButton") then
        if helperConfig.training[index + 1].id > 0 then
          menu:addOption(tr('Edit Training Spell'), function() assignTrainingSpell(button) end)
          menu:addOption(tr('Remove'), function() removeAction("training", button) end)
        else
          menu:addOption(tr('Assign Training Spell'), function() assignTrainingSpell(button) end)
        end
      elseif buttonId:find("hasteButton") then
        if helperConfig.haste[index + 1].id > 0 then
          menu:addOption(tr('Edit Haste Spell'), function() assignTrainingSpell(button, true) end)
          menu:addOption(tr('Remove'), function() removeAction("haste", button) end)
        else
          menu:addOption(tr('Assign Haste Spell'), function() assignTrainingSpell(button, true) end)
        end
      elseif buttonId:find("autoTrainingItem") then
        if not button.potionItem or button.potionItem:getItemId() == 0 then
          menu:addOption(tr('Select exercise weapon'), function() assignExerciseEvent(button) end)
        else
          menu:addOption(tr('Remove'), function() removeAction("exercise", button) end)
        end
      end

      menu:display(mousePos)
      return true
    end
    return false
  end
end

function onPartyMembersChange()
  -- This function is called when party members change
  -- We can update party healing settings here if needed
end

-- Atualiza a lista de membros da party
function updatePartyMembersHealth(cachedSpectators)
  -- No vocation-based system, no widget lists to update.
  -- Healing logic is handled by onFriendHealing() and onPartyMemberHealthChangeHelper().
end

eventTable.updatePartyHealth.action = updatePartyMembersHealth

function onPartyDataClear()
  -- No vocation-based system, nothing to clear (no widget lists)
end

function onPartyDataUpdate(members)
  -- Compatibility stub
end

function resetPartyPanel()
  -- No vocation-based system, nothing to reset (checkboxes persist their state via config)
end

-- Vocation-based friend healing UI callbacks
function onEnableVocFriend(vocation, checked)
  if helperConfig.friendhealing[vocation] then
    helperConfig.friendhealing[vocation].enabled = checked
  end
end

function onNamedSioEnabled(checked)
  helperConfig.namedSio = helperConfig.namedSio or { enabled = false, name = "", percent = 90 }
  helperConfig.namedSio.enabled = checked == true
  saveSettings()
end

function onNamedSioName(text)
  helperConfig.namedSio = helperConfig.namedSio or { enabled = false, name = "", percent = 90 }
  helperConfig.namedSio.name = text or ""
  saveSettings()
end

function onNamedSioPercent(text)
  helperConfig.namedSio = helperConfig.namedSio or { enabled = false, name = "", percent = 90 }
  local value = tonumber((text or ""):match("%d+")) or helperConfig.namedSio.percent or 90
  value = math.max(1, math.min(99, value))
  helperConfig.namedSio.percent = value
  saveSettings()
end

-- Which heal Auto Heal Friend casts on the listed names: "sio" (spell 84) or
-- "gransio" (spell 242). Stored as a key rather than the label so the setting
-- survives translation of the combo box text.
function onNamedSioSpell(text)
  helperConfig.namedSio = helperConfig.namedSio or { enabled = false, name = "", percent = 90 }
  helperConfig.namedSio.spell = (tostring(text or ""):lower():find("gran")) and "gransio" or "sio"
  saveSettings()
end

function onEnableVocGranSio(vocation, checked)
  if helperConfig.gransiohealing[vocation] then
    helperConfig.gransiohealing[vocation].enabled = checked
  end
end

function onEnableVocMasRes(vocation, checked)
  if helperConfig.masreshealing[vocation] then
    helperConfig.masreshealing[vocation].enabled = checked
  end
end

function onMasResExtendedChange(checked)
  helperConfig.masreshealing.extended = checked
end

-- Wrapper function para OTUI (modulo sandboxed)
function onEnableTraining(buttonId, checked)
  _Helper.ManaTraining.toggle(buttonId, checked)
end

-- Bot functions
function updateHealingPercent(buttonId, newPercent)
  local buttonIndex = string.match(buttonId, "%d+")
  if not buttonIndex then
    return
  end

  buttonIndex = tonumber(buttonIndex)
  local config = helperConfig.spells[buttonIndex + 1]
  if string.find(buttonId, "add") then
    if config.percent + 1 > 99 then
      healingPanel:recursiveGetChildById("addPercentButton" .. buttonIndex):setEnabled(false)
      return
    end

    healingPanel:recursiveGetChildById("rmvPercentButton" .. buttonIndex):setEnabled(true)
    config.percent = config.percent + 1
    local label = healingPanel:recursiveGetChildById("spellPercentLabel" .. buttonIndex)
    label:setText(config.percent .. "%")
  elseif string.find(buttonId, "rmv") then
    if config.percent - 1 < 1 then
      healingPanel:recursiveGetChildById("rmvPercentButton" .. buttonIndex):setEnabled(false)
      return
    end

    healingPanel:recursiveGetChildById("addPercentButton" .. buttonIndex):setEnabled(true)
    config.percent = config.percent - 1
    local label = healingPanel:recursiveGetChildById("spellPercentLabel" .. buttonIndex)
    label:setText(config.percent .. "%")
  end

  cachedSpells = table.copy(helperConfig.spells)
  table.sort(cachedSpells, function(a, b) return a.percent < b.percent end)

  if rebuildHealingCache then rebuildHealingCache() end
end

-- HELPER MAGIC SHOOTER: Wrapper functions para OTUI compatibilidade
function updateMagicShooterPercent(buttonId, newPercent)
  _Helper.MagicShooter.updatePercent(buttonId, newPercent)
end

function updateRuneShooterCreatures(name, index, creatures)
  _Helper.MagicShooter.updateRuneCreatures(name, index, creatures)
end

function updateRuneShooterPriority(index, priority)
  _Helper.MagicShooter.updateRunePriority(index, priority)
end

function updatePotionPercent(buttonId, newPercent)
  local buttonIndex = string.match(buttonId, "%d+")
  if not buttonIndex then
    return
  end

  buttonIndex = tonumber(buttonIndex)
  local config = helperConfig.potions[buttonIndex + 1]
  if string.find(buttonId, "add") then
    if config.percent + 1 > 99 then
      healingPanel:recursiveGetChildById("addPotionPercentButton" .. buttonIndex):setEnabled(false)
      return
    end

    healingPanel:recursiveGetChildById("rmvPotionPercentButton" .. buttonIndex):setEnabled(true)
    config.percent = config.percent + 1
    local label = healingPanel:recursiveGetChildById("potionPercentLabel" .. buttonIndex)
    label:setText(config.percent .. "%")
  elseif string.find(buttonId, "rmv") then
    if config.percent - 1 < 1 then
      healingPanel:recursiveGetChildById("rmvPotionPercentButton" .. buttonIndex):setEnabled(false)
      return
    end

    healingPanel:recursiveGetChildById("addPotionPercentButton" .. buttonIndex):setEnabled(true)
    config.percent = config.percent - 1
    local label = healingPanel:recursiveGetChildById("potionPercentLabel" .. buttonIndex)
    label:setText(config.percent .. "%")
  end

  if rebuildHealingCache then rebuildHealingCache() end
end

function updateVocFriendPercent(vocation, newPercent)
  if helperConfig.friendhealing[vocation] then
    helperConfig.friendhealing[vocation].percent = tonumber(newPercent)
  end
end

function updateVocGranSioPercent(vocation, newPercent)
  if helperConfig.gransiohealing[vocation] then
    helperConfig.gransiohealing[vocation].percent = tonumber(newPercent)
  end
end

function updateVocFriendPriority(vocation, newPriority)
  if helperConfig.friendhealing[vocation] then
    helperConfig.friendhealing[vocation].priority = tonumber(newPriority)
  end
end

function updateVocGranSioPriority(vocation, newPriority)
  if helperConfig.gransiohealing[vocation] then
    helperConfig.gransiohealing[vocation].priority = tonumber(newPriority)
  end
end

function updateVocMasResPercent(vocation, newPercent)
  if helperConfig.masreshealing[vocation] then
    helperConfig.masreshealing[vocation].percent = tonumber(newPercent)
  end
end

function updateVocMasResPriority(vocation, newPriority)
  if helperConfig.masreshealing[vocation] then
    helperConfig.masreshealing[vocation].priority = tonumber(newPriority)
  end
end

function castHealingSpell(spellData)
  local spellId = spellData and spellData.id or 0
  if spellId == 0 then
    return false
  end

  -- Try to get spell by ID first (spell.id), then by clientId
  local spell = getSpellDataById(spellId)

  -- If not found by ID, try by clientId
  if not spell then
    spell = getSpellByClientId(tonumber(spellId))
  end

  if not spell then
    return false
  end

  -- Check if spell has words (required for casting)
  if not spell.words or spell.words == "" then
    return false
  end

  if (isSpellOnCooldown(spell)) then
    return false
  end

  -- Check if buff is still active (e.g. Protector lasts 10s but cooldown is 2s)
  local buffDuration = HelperSpellData.getBuffDuration(spell.id)
  if buffDuration > 0 and healingActiveBuffs[spell.id] and healingActiveBuffs[spell.id] > g_clock.millis() then
    return false
  end

  local currentPlayer = getPlayer()
  if not currentPlayer then
    return false
  end

  -- Check if player has enough mana for the spell
  if spell.mana and spell.mana > 0 then
    local playerMana = currentPlayer:getMana()
    if playerMana < spell.mana then
      return false
    end
  end

  -- Check soul requirement
  if spell.soul and spell.soul > 0 then
    local playerSoul = currentPlayer:getSoul()
    if playerSoul < spell.soul then
      return false
    end

    if spell.source and not hasItemInBackpack(spell.source) then
      return false
    end
  end

  -- Execute the spell
  safeDoThing(false)
  g_game.talk(spell.words, true)
  safeDoThing(true)

  -- Track buff expiration for spells with buff duration
  if buffDuration > 0 then
    healingActiveBuffs[spell.id] = g_clock.millis() + buffDuration
  end

  return true
end

function checkHealthHealing()
  local localPlayer = g_game.getLocalPlayer()
  if not helperAutomaticFunctionsEnabled or not localPlayer then
    return false
  end

  local health, maxHealth = localPlayer:getHealth(), localPlayer:getMaxHealth()
  local healthPercent = (health / maxHealth) * 100

  local usedSomething = false

  -- 1. Tentar usar special HP foods primeiro (maior prioridade, cooldown independente)
  if helperConfig.specialFoods and helperConfig.specialFoods.hp then
    local sortedHpFoods = sortSpecialFoodsByPriority(helperConfig.specialFoods.hp)
    for _, food in ipairs(sortedHpFoods) do
      if food.enabled and food.id ~= 0 and healthPercent <= food.percent then
        if not isSpecialFoodOnCooldown(food.id) and hasItemInBackpack(food.id) then
          if useSpecialFood(food.id) then
            usedSomething = true
            break
          end
        end
      end
    end
  end

  -- 2. Tentar usar spell (cooldown independente de food)
  health = localPlayer:getHealth()
  healthPercent = (health / maxHealth) * 100
  for _, spell in ipairs(cachedPrioritizedSpells) do
    if HelperSpellData.getIgnoredSpellsIds()[spell.id] then
      goto skipSpell
    end

    if spell.id ~= 0 and healthPercent <= spell.percent then
      local success = castHealingSpell(spell)
      if success then
        usedSomething = true
        break
      end
    end

    ::skipSpell::
  end

  -- 3. Tentar usar potion (cooldown independente da spell)
  health = localPlayer:getHealth()
  healthPercent = (health / maxHealth) * 100
  for _, potion in ipairs(cachedPrioritizedHealthPotions) do
    local hasItem = hasItemInBackpack(potion.id)
    local shouldUse = healthPercent <= potion.percent
    if hasItem and shouldUse then
      local potionUsed = usePotion(potion.id)
      if potionUsed then
        usedSomething = true
        break
      end
    end
  end

  return usedSomething
end

eventTable.checkHealthHealing.action = checkHealthHealing

--safeLog("info", "Helper: checkHealthHealing action assigned to eventTable")

function hasItemInBackpack(potionId)
  local currentPlayer = g_game.getLocalPlayer()
  if not currentPlayer then
    return false
  end
  local success, count = pcall(function()
    return currentPlayer:getInventoryCount(potionId, 0)
  end)
  return success and count and count > 0
end

function checkManaHealing(mana, maxMana)
  if not helperAutomaticFunctionsEnabled then
    return
  end

  local manaPercent = (mana / maxMana) * 100

  local startHealthPotionPriority = false
  local localPlayer = g_game.getLocalPlayer()
  if localPlayer then
    -- Quick check: if any health potion condition is met, we might need to prioritize health (skip mana for now?)
    -- The original logic seemed to check if a health potion *should* be used based on health,
    -- and if so, it skips mana check? That seems to be the intent of "healthPotionPriority".
    -- Let's use the cached health potions to check this efficiently.
    local success, health, maxHealth = pcall(function()
      return localPlayer:getHealth(), localPlayer:getMaxHealth()
    end)
    if not success or not health or not maxHealth or maxHealth == 0 then return end
    local currentHealthPercent = (health / maxHealth) * 100
    for _, potion in ipairs(cachedPrioritizedHealthPotions) do
      -- Only check if we actually have it (optimization: maybe skip hasItem check here if we want pure speed?)
      -- Original code checked hasItemInBackpack.
      if hasItemInBackpack(potion.id) and currentHealthPercent <= potion.percent then
        startHealthPotionPriority = true
        break
      end
    end
  end

  if startHealthPotionPriority then
    return
  end

  -- 1. Tentar usar special Mana foods primeiro (maior prioridade, cooldown independente)
  if helperConfig.specialFoods and helperConfig.specialFoods.mana then
    local sortedManaFoods = sortSpecialFoodsByPriority(helperConfig.specialFoods.mana)
    for _, food in ipairs(sortedManaFoods) do
      if food.enabled and food.id ~= 0 and manaPercent <= food.percent then
        if not isSpecialFoodOnCooldown(food.id) and hasItemInBackpack(food.id) then
          if useSpecialFood(food.id) then
            return
          end
        end
      end
    end
  end

  -- 2. Tentar usar mana potion (cooldown independente de food)
  for _, potion in ipairs(cachedPrioritizedManaPotions) do
    local hasItem = hasItemInBackpack(potion.id)
    local shouldUse = manaPercent <= potion.percent
    if hasItem and shouldUse then
      usePotion(potion.id)
      return
    end
  end
end

-- Event handlers para reação instantânea a mudanças de vida/mana
function onPlayerHealthChange(player, health, maxHealth, oldHealth)
  if not helperAutomaticFunctionsEnabled then return end
  if isTransitioningPlayer then return end

  -- Só reagir quando a vida diminuir (tomou dano)
  if oldHealth and health < oldHealth then
    checkHealthHealing()
  end
end

function rebuildHealingCache()
  -- Rebuild Spells Cache
  cachedPrioritizedSpells = {}
  for _, spell in pairs(helperConfig.spells) do
    table.insert(cachedPrioritizedSpells, spell)
  end
  table.sort(cachedPrioritizedSpells, function(a, b)
    if a.percent == b.percent then
      return a.id < b.id
    else
      return a.percent < b.percent
    end
  end)

  -- Rebuild Potions Cache
  cachedPrioritizedHealthPotions = {}
  cachedPrioritizedManaPotions = {}

  -- Pre-sort potions list first to ensure consistent ordering when splitting
  local sortedPotions = {}
  for _, potion in pairs(helperConfig.potions) do
    if potion.id ~= 0 then
      table.insert(sortedPotions, potion)
    end
  end
  table.sort(sortedPotions, function(a, b)
    if a.percent == b.percent then
      return a.priority < b.priority
    else
      return a.percent < b.percent
    end
  end)

  for _, potion in ipairs(sortedPotions) do
    if potion.priority ~= 0 then
      -- User explicitly set category: respect it
      if potion.priority == 1 then
        table.insert(cachedPrioritizedHealthPotions, potion)
      elseif potion.priority == 2 then
        table.insert(cachedPrioritizedManaPotions, potion)
      end
    else
      -- No user selection: fallback to whitelist type
      if isHealthPotion(potion.id) then
        table.insert(cachedPrioritizedHealthPotions, potion)
      elseif isManaPotion(potion.id) then
        table.insert(cachedPrioritizedManaPotions, potion)
      end
    end
  end

  -- Mana potions are also sorted by percent in original code
  table.sort(cachedPrioritizedManaPotions, function(a, b)
    return a.percent < b.percent
  end)
end

function onPlayerManaChange(player, mana, maxMana, oldMana)
  if not helperAutomaticFunctionsEnabled then return end
  if isTransitioningPlayer then return end

  -- Só reagir quando a mana diminuir (usou spell/foi drenado)
  if oldMana and mana < oldMana then
    checkManaHealing(mana, maxMana)
  end
end

-- Callback para mudanca de estados do player (usado pelo Auto Haste)
function onPlayerStatesChange(player, states, oldStates)
  if not helperAutomaticFunctionsEnabled then return end
  if isTransitioningPlayer then return end
  if not player then return end

  -- Verificar se perdeu o estado de Haste
  local hadHaste = oldStates and bit.band(oldStates, PlayerStates.Haste) ~= 0
  local hasHaste = states and bit.band(states, PlayerStates.Haste) ~= 0

  if hadHaste and not hasHaste then
    -- Perdeu haste, notificar o modulo AutoHaste
    if _Helper.AutoHaste and _Helper.AutoHaste.onHasteLost then
      _Helper.AutoHaste.onHasteLost()
    end
  end

  local hadParalyze = oldStates and bit.band(oldStates, PlayerStates.Paralyze) ~= 0
  local hasParalyze = states and bit.band(states, PlayerStates.Paralyze) ~= 0
  if hasParalyze and not hadParalyze and _Helper.ParalyzeCure and _Helper.ParalyzeCure.check then
    _Helper.ParalyzeCure.check()
  end
end

-- The helper happily shouts a spell the character cannot actually cast, the
-- server rejects it, and the caller still counts it as a successful heal. That
-- is what let Nature's Embrace (level 300, 400 mana) permanently swallow every
-- Heal Friend attempt for a druid below that level or short on mana.
function canCastSpell(spell)
  if not spell then
    return false
  end

  local localPlayer = g_game.getLocalPlayer()
  if not localPlayer then
    return false
  end

  local required = tonumber(spell.level) or 0
  if required > 0 and type(localPlayer.getLevel) == "function" then
    local level = tonumber(localPlayer:getLevel()) or 0
    if level > 0 and level < required then
      return false
    end
  end

  local cost = tonumber(spell.mana) or 0
  if cost > 0 and type(localPlayer.getMana) == "function" then
    local mana = tonumber(localPlayer:getMana()) or 0
    if mana < cost then
      return false
    end
  end

  return true
end

function useAutoSio(target)
  local spellId = 84
  local spell = getSpellByClientId(tonumber(spellId))
  if not spell or spell.id == 0 then
    return false
  end

  if not canCastSpell(spell) then
    return false
  end

  if not checkHealthPriority() then
    return false
  end

  if (isSpellOnCooldown(spell)) then
    return false
  end

  safeDoThing(false)
  g_game.talk(string.format("%s \"%s\"", spell.words, target:getName()), true)
  safeDoThing(true)

  return true
end

local function trimNamedSioText(text)
  return tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function parseNamedSioNames(text)
  local names = {}
  for name in tostring(text or ""):gmatch("[^,]+") do
    name = trimNamedSioText(name)
    if name ~= "" then
      names[name:lower()] = true
    end
  end
  return names
end

local function checkNamedSio(localPlayer, cachedSpectators)
  if not localPlayer or not localPlayer.isDruid or not localPlayer:isDruid() then
    return false
  end

  local cfg = helperConfig.namedSio
  if not cfg or not cfg.enabled then
    return false
  end

  local targetNames = parseNamedSioNames(cfg.name)
  if not next(targetNames) then
    return false
  end

  local position = localPlayer:getPosition()
  if not position then
    return false
  end

  local spectators = cachedSpectators or g_map.getSpectators(position, false)
  if not spectators then
    return false
  end

  local threshold = math.max(1, math.min(99, tonumber(cfg.percent) or 90))
  for _, creature in pairs(spectators) do
    if creature and creature:isPlayer() and creature:getName() and targetNames[creature:getName():lower()] then
      local healthPercent = creature:getHealthPercent()
      local targetPos = creature:getPosition()
      if healthPercent and healthPercent <= threshold and targetPos and
          g_map.isSightClear(position, targetPos) and isWithinReach(position, targetPos) then
        if cfg.spell == "gransio" then
          return useAutoGranSio(creature)
        end
        return useAutoSio(creature)
      end
    end
  end

  return false
end

function useAutoGranSio(target)
  local spellId = 242
  local spell = getSpellByClientId(spellId)
  if not spell or spell.id == 0 then
    return false
  end

  if not canCastSpell(spell) then
    return false
  end

  if not checkHealthPriority() then
    return false
  end

  if (isSpellOnCooldown(spell)) then
    return false
  end

  safeDoThing(false)
  g_game.talk(string.format("%s \"%s\"", spell.words, target:getName()), true)
  safeDoThing(true)

  return true
end

function useAutoTioSio(target)
  local spellId = 297
  local spell = getSpellByClientId(spellId)
  if not spell or spell.id == 0 then
    return false
  end

  if not canCastSpell(spell) then
    return false
  end

  if not checkHealthPriority() then
    return false
  end

  if (isSpellOnCooldown(spell)) then
    return false
  end

  safeDoThing(false)
  g_game.talk(string.format("%s \"%s\"", spell.words, target:getName()), true)
  safeDoThing(true)

  return true
end

function useAutoMasRes()
  local spellId = 82 -- Mass Healing (exura gran mas res)
  local spell = getSpellByClientId(spellId)
  if not spell or spell.id == 0 then
    return false
  end

  if not canCastSpell(spell) then
    return false
  end

  if not checkHealthPriority() then
    return false
  end

  if (isSpellOnCooldown(spell)) then
    return false
  end

  safeDoThing(false)
  g_game.talk(spell.words, true)
  safeDoThing(true)

  return true
end

function useAutoUH(target)
  local runeId = 3160
  local rune = Spells.getRuneSpellByItem(runeId)
  if not rune and CustomRuneIds then rune = CustomRuneIds[runeId] end
  _Helper.resolveCustomRuneArea(rune)
  if not rune then
    return false
  end

  if not checkHealthPriority() then
    return false
  end

  -- UH rune shares object use exhaustion with potions and magic shooter runes
  if multiUseExDelay > g_clock.millis() or (spellsCooldown[potionConfig.id] or 0) > g_clock.millis() then
    return false
  end

  helperConfig.magicShooterOnHold = true

  local casted = false
  if hasItemInBackpack(runeId) then
    safeDoThing(false)
    g_game.useInventoryItemWith(runeId, target, 0, true)
    safeDoThing(true)
    -- Set shared cooldown so potions/magic shooter know UH was just used
    local expires = g_clock.millis() + potionConfig.exhaustion
    multiUseExDelay = expires
    spellsCooldown[potionConfig.id] = expires
    lastObjectUseWasRune = true
    casted = true
  end

  helperConfig.magicShooterOnHold = false

  return casted
end

-- toolMenu
-- Wrapper function para OTUI (modulo sandboxed)
function updateTrainingPercent(buttonId, newPercent)
  _Helper.ManaTraining.updatePercent(buttonId, newPercent)
end

-- Wrapper function que chama o modulo ManaTraining
function checkTrainingSpell(mana, maxMana)
  _Helper.ManaTraining.check(mana, maxMana)
end

-- Wrapper function para Auto Food (OTUI compatibilidade)
function toggleAutoEat(checked)
  _Helper.AutoFood.toggle(checked)
end

-- Wrapper function para Low Capacity Alarm (OTUI compatibilidade)
function toggleLowCapacityAlarm(checked)
  _Helper.LowCapacityAlarm.toggle(checked)
end

-- Wrapper functions para Auto Haste (OTUI compatibilidade)
function toggleAutoHaste(checked)
  _Helper.AutoHaste.toggle(checked)
end

function toggleAutoHastePz(checked)
  _Helper.AutoHaste.togglePz(checked)
end

function toggleAutoHasteOnlyWalking(checked)
  _Helper.AutoHaste.toggleOnlyWalking(checked)
end

function selectAutoStaminaItem()
  if _Helper.AutoStaminaFood then _Helper.AutoStaminaFood.selectItem() end
end

function toggleAutoStamina(checked)
  if _Helper.AutoStaminaFood then _Helper.AutoStaminaFood.toggle(checked) end
end

function toggleParalyzeCure(checked)
  if _Helper.ParalyzeCure then _Helper.ParalyzeCure.toggle(checked) end
end

-- Wrapper function for Gold Change (OTUI compatibility)
function toogleChangeGold(checked)
  if modules.game_helper and modules.game_helper.tools then
    modules.game_helper.tools.toggleChangeGold(checked)
  else
    helperConfig.autoChangeGold = checked
  end
end

-- Wrapper function for auto change gold
function autoChangeGold()
  if modules.game_helper and modules.game_helper.tools then
    modules.game_helper.tools.autoChangeGold()
  end
end

-- Wrapper function for Exercise Training (OTUI compatibility)
function toggleExerciseTraining(checked)
  if _Helper.ExerciseTraining and _Helper.ExerciseTraining.toggle then
    _Helper.ExerciseTraining.toggle(checked)
  elseif modules.game_helper and modules.game_helper.tools then
    modules.game_helper.tools.toggleExerciseTraining(checked)
  end
end

-- Wrapper function for resources balance change
function onResourcesBalanceChange(value, oldValue, resourceType)
  if modules.game_helper and modules.game_helper.tools then
    modules.game_helper.tools.onResourcesBalanceChange(value, oldValue, resourceType)
  end
end

function checkMana()
  if not g_game.isOnline() or not helperAutomaticFunctionsEnabled then return end
  local currentPlayer = getPlayer()
  if not currentPlayer then
    return
  end

  local mana = currentPlayer:getMana()
  local maxMana = currentPlayer:getMaxMana()
  checkManaHealing(mana, maxMana)
  checkTrainingSpell(mana, maxMana)
end

eventTable.checkMana.action = checkMana

function routineChecks()
  if not helperAutomaticFunctionsEnabled then return end
  local currentPlayer = getPlayer()
  if currentPlayer then
    if currentPlayer:getRegenerationTime() <= 500 then
      _Helper.AutoFood.check()
    end

    autoChangeGold()
    _Helper.LowCapacityAlarm.check()
    _Helper.LowSupplyAlarm.check()
    _Helper.LowHealthAlarm.check()
    _Helper.LowManaAlarm.check()
  end
end

eventTable.routineChecks.action = routineChecks

function updateMagicShooterPriority(index, priority)
  _Helper.MagicShooter.updatePriority(index, priority)
end

function updateMagicShooterCreatures(name, index, creatures)
  _Helper.MagicShooter.updateCreatures(name, index, creatures)
end

function toggleSelfCast(index, checked)
  _Helper.MagicShooter.toggleSelfCast(index, checked)
end

function toggleForceCast(index, checked)
  _Helper.MagicShooter.toggleForceCast(index, checked)
end

function toggleForceRuneCast(index, checked)
  _Helper.MagicShooter.toggleForceRuneCast(index, checked)
end

function isMagicShooterActive()
  return _Helper.MagicShooter.isActive()
end

function toggleMagicShooter(widget, message)
  _Helper.MagicShooter.toggle(widget, message)
end

function holdMagicShooter()
  _Helper.MagicShooter.hold()
end

function releaseMagicShooter()
  _Helper.MagicShooter.release()
end

function toggleDisableInProtectZone(checked)
  if helperConfig then
    helperConfig.disableInProtectZone = checked
    saveSettings()
  end
end

function toggleAlwaysChaseOpponent(checked)
  if not helperConfig then return end

  helperConfig.alwaysChaseOpponent = checked
  if _Helper.Shortcut and _Helper.Shortcut.syncButton then
    _Helper.Shortcut.syncButton('shortcutAlwaysChase', checked)
  end
  if checked and g_game.isOnline() and g_game.getChaseMode() ~= ChaseOpponent then
    g_game.setChaseMode(ChaseOpponent)
  end
  saveSettings()
end

-- HELPER AUTO TARGET: Funções movidas para classes/auto_target.lua
-- Wrapper functions para compatibilidade com OTUI e código existente

function isAutoTargetActive()
  return _Helper.AutoTarget.isActive()
end

function toggleAutoTarget(widget)
  _Helper.AutoTarget.toggle(widget)
end

function updateAutoTargetMode(mode)
  _Helper.AutoTarget.updateMode(mode)
end

function applyPriorityMonsterList()
  _Helper.AutoTarget.applyPriorityList()
end

local function printArea(area)
  -- Debug function disabled
end

local function rotateArea(area, direction)
  if not area or type(area) ~= "table" or #area == 0 or not area[1] or type(area[1]) ~= "table" then
    return area
  end

  local rotatedArea = {}
  local rows = #area
  local cols = #area[1]

  if direction == Directions.North then
    rotatedArea = area
  elseif direction == Directions.South then
    for y = 1, rows do
      rotatedArea[y] = {}
      for x = 1, cols do
        rotatedArea[y][x] = area[rows - y + 1][cols - x + 1]
      end
    end
  elseif direction == Directions.East then
    for x = 1, cols do
      rotatedArea[x] = {}
      for y = 1, rows do
        rotatedArea[x][y] = area[rows - y + 1][x]
      end
    end
  elseif direction == Directions.West then
    for x = 1, cols do
      rotatedArea[x] = {}
      for y = 1, rows do
        rotatedArea[x][y] = area[y][cols - x + 1]
      end
    end
  end

  return rotatedArea
end

local function findPlayerPosition(area)
  for y, row in ipairs(area) do
    for x, value in ipairs(row) do
      if value == 3 or value == 2 then
        return x, y
      end
    end
  end
  return nil, nil
end

function getRelativePosition(targetPos)
  local player = g_game.getLocalPlayer()
  if not player then return targetPos end
  local playerPos = player:getPosition()

  local relativePos = { x = targetPos.x, y = targetPos.y, z = targetPos.z }
  if playerPos.x < targetPos.x and playerPos.y < targetPos.y then
    relativePos.x = relativePos.x - 1;
    relativePos.y = relativePos.y - 1;
  elseif (playerPos.x < targetPos.x and playerPos.y > targetPos.y) or playerPos.x < targetPos.x then
    relativePos.x = relativePos.x - 1;
  elseif (playerPos.x > targetPos.x and playerPos.y < targetPos.y) or playerPos.y < targetPos.y then
    relativePos.y = relativePos.y - 1;
  end
  return relativePos
end

-- HELPER MAGIC SHOOTER: Getter para getRelativePosition (definido aqui apos a funcao)
_Helper.getRelativePosition = function(targetPos)
  return getRelativePosition(targetPos)
end

-- Map::isSightClear walks the line and tests every tile it steps onto INCLUDING
-- the destination, so a creature standing on (or right beside) anything that
-- blocks projectiles -- a fence, a platform edge, a rock -- reports "no sight"
-- even though the server lands the spell on it perfectly well. Nothing on an
-- adjacent tile can be occluded, and for a self-centred area like Divine
-- Caldera's 3x3 circle every affected tile IS adjacent, so the check was
-- vetoing the whole spell. Treat neighbours as always reachable and fall back
-- to the line walk for anything further out.
local function hasCombatSight(casterPos, targetPos)
  if casterPos.z == targetPos.z
      and math.abs(casterPos.x - targetPos.x) <= 1
      and math.abs(casterPos.y - targetPos.y) <= 1 then
    return true
  end
  return g_map.isSightClear(casterPos, targetPos)
end

local function countAttackableCreatures(casterPos, direction, area, creatureList, ranged)
  if direction == Directions.SouthEast or direction == Directions.NorthEast then
    direction = Directions.East
  elseif direction == Directions.SouthWest or direction == Directions.NorthWest then
    direction = Directions.West
  end

  local area = rotateArea(area, direction)
  local creatures = 0
  local playerX, playerY = findPlayerPosition(area)
  if not playerX or not playerY then
    return 0
  end

  -- Clear reusable table
  for k in pairs(reusableCountedCreatures) do reusableCountedCreatures[k] = nil end

  for yOffset, row in ipairs(area) do
    for xOffset, value in ipairs(row) do
      if value == 1 or (ranged and (value == 3 or value == 2)) then
        tempPos.x = casterPos.x + (xOffset - playerX)
        tempPos.y = casterPos.y + (yOffset - playerY)
        tempPos.z = casterPos.z

        for _, creatureData in ipairs(creatureList) do
          local creaturePos = creatureData.position
          if creaturePos and positionCompare(creaturePos, tempPos) and hasCombatSight(casterPos, creaturePos) then
            local creature = creatureData.creature
            local creatureId = creature and creature.getId and creature:getId() or
                tostring(creaturePos.x) .. "," .. tostring(creaturePos.y) .. "," .. tostring(creaturePos.z)
            if not reusableCountedCreatures[creatureId] then
              reusableCountedCreatures[creatureId] = true
              creatures = creatures + 1
              break
            end
          end
        end
      end
    end
  end
  -- Limpeza do pool de tabelas
  for k in pairs(reusableCountedCreatures) do reusableCountedCreatures[k] = nil end

  return creatures
end

-- HELPER AUTO TARGET: Getter para countAttackableCreatures (definido aqui apos a funcao local)
_Helper.countAttackableCreatures = function(casterPos, direction, area, creatureList, ranged)
  return countAttackableCreatures(casterPos, direction, area, creatureList, ranged)
end

-- Encontra a melhor direcao para castar um spell de area, maximizando o numero de criaturas atingidas
-- Retorna a melhor direcao e o numero de criaturas que serao atingidas
local function findBestDirectionForSpell(casterPos, area, creatureList, ranged)
  local cardinalDirections = {
    Directions.North,
    Directions.South,
    Directions.East,
    Directions.West
  }

  local bestDirection = Directions.North
  local maxCreatures = 0

  for _, dir in ipairs(cardinalDirections) do
    local creatures = countAttackableCreatures(casterPos, dir, area, creatureList, ranged)
    if creatures > maxCreatures then
      maxCreatures = creatures
      bestDirection = dir
    end
  end

  return bestDirection, maxCreatures
end

-- HELPER MAGIC SHOOTER: Getter para findBestDirectionForSpell
_Helper.findBestDirectionForSpell = function(casterPos, area, creatureList, ranged)
  return findBestDirectionForSpell(casterPos, area, creatureList, ranged)
end

-- HELPER MAGIC SHOOTER: Funcoes movidas para classes/magic_shooter.lua
-- sortMagicShooterByPriority e findBestTarget agora estao em _Helper.MagicShooter

local function sortMagicShooterByPriority(list)
  return _Helper.MagicShooter.sortByPriority(list)
end

local function findBestTarget(position, direction, area, creatureList, minCreatures)
  local bestTarget = nil
  local maxCreaturesHit = 0

  for _, creatureInfo in pairs(creatureList) do
    if isWithinReach(position, creatureInfo.position) and g_map.isSightClear(position, creatureInfo.position) then
      local creaturesHit = countAttackableCreatures(creatureInfo.position, direction, area, creatureList, true)
      if creaturesHit >= minCreatures then
        if creaturesHit > maxCreaturesHit then
          maxCreaturesHit = creaturesHit
          bestTarget = creatureInfo.creature
        end
      end
    end
  end

  return bestTarget, maxCreaturesHit
end

-- Converte a area da runa em offsets relativos ao centro (valor 3 ou 2)
-- Retorna uma lista achatada {ox1, oy1, bonus1, ox2, oy2, bonus2, ...}
-- onde bonus = 1/(sqrt(ox²+oy²)+1), pre-calculado para evitar sqrt no loop principal
local function getOffsetsFromArea(area)
  local centerX, centerY = findPlayerPosition(area)
  if not centerX or not centerY then return {} end

  local offsets = {}
  local n = 0
  for y = 1, #area do
    local row = area[y]
    for x = 1, #row do
      local v = row[x]
      -- Valor 1 = area de dano, 2/3 = centro
      if v == 1 or v == 2 or v == 3 then
        local ox = x - centerX
        local oy = y - centerY
        offsets[n + 1] = ox
        offsets[n + 2] = oy
        offsets[n + 3] = 1 / (math.sqrt(ox * ox + oy * oy) + 1)
        n = n + 3
      end
    end
  end
  return offsets, n
end

-- Encontra o melhor tile para jogar a runa de area, maximizando o numero de criaturas atingidas
-- Usa logica de score: para cada criatura, calcula todos os tiles possiveis onde a runa
-- poderia ser jogada para atingi-la, acumulando score por posicao
-- Isso e mais eficiente que iterar sobre todos os tiles do mapa
local KEY_STRIDE = 100000 -- positions em OT cabem folgadamente em [0, 65535]
local function findBestTileForRune(playerPos, direction, area, creatureList, minCreatures)
  local offsets, offsetsLen = getOffsetsFromArea(area)
  if offsetsLen == 0 then return nil, 0 end

  -- Upvalues locais (evita lookup global por iteracao)
  local isSightClear = g_map.isSightClear
  local abs = math.abs

  local playerX, playerY, playerZ = playerPos.x, playerPos.y, playerPos.z

  -- Acumuladores por tile (chave = goalY * STRIDE + goalX, inteiro)
  local scoreByPosition = {}
  local creatureCountByPosition = {}
  -- Cache: player sight clear para cada tile (chave inteira)
  local playerSightCache = {}
  -- Cache: tile -> criatura (chave composta tambem inteira)
  local creatureSightCache = {}

  -- Melhor candidato rastreado durante o acumulo (elimina 2o pass)
  local bestScore = 0
  local bestKey = nil
  local bestCount = 0
  local bestGoalX, bestGoalY = 0, 0

  -- Reutilizar tabelas de posicao em vez de alocar a cada iteracao
  local goalPos = { x = 0, y = 0, z = 0 }
  local creaturePosTmp = { x = 0, y = 0, z = 0 }

  for ci = 1, #creatureList do
    local creatureData = creatureList[ci]
    local creaturePos = creatureData.position
    if creaturePos and creaturePos.z == playerZ then
      local cx, cy = creaturePos.x, creaturePos.y
      creaturePosTmp.x, creaturePosTmp.y, creaturePosTmp.z = cx, cy, playerZ
      local creatureKey = cy * KEY_STRIDE + cx

      for oi = 1, offsetsLen, 3 do
        local ox = offsets[oi]
        local oy = offsets[oi + 1]
        local goalX = cx - ox
        local goalY = cy - oy

        -- Pre-filtro barato: alcance do player (7x5 client-side) antes de qualquer cache/sight
        if abs(goalX - playerX) <= 7 and abs(goalY - playerY) <= 5 then
          local key = goalY * KEY_STRIDE + goalX
          local cached = playerSightCache[key]
          if cached == nil then
            goalPos.x, goalPos.y, goalPos.z = goalX, goalY, playerZ
            cached = isSightClear(playerPos, goalPos)
            playerSightCache[key] = cached
          end

          if cached then
            local csKey = key * KEY_STRIDE + creatureKey
            local cs = creatureSightCache[csKey]
            if cs == nil then
              goalPos.x, goalPos.y, goalPos.z = goalX, goalY, playerZ
              cs = isSightClear(goalPos, creaturePosTmp)
              creatureSightCache[csKey] = cs
            end

            if cs then
              local score = (scoreByPosition[key] or 0) + 1 + offsets[oi + 2]
              local count = (creatureCountByPosition[key] or 0) + 1
              scoreByPosition[key] = score
              creatureCountByPosition[key] = count
              if score > bestScore and count >= minCreatures then
                bestScore = score
                bestKey = key
                bestCount = count
                bestGoalX = goalX
                bestGoalY = goalY
              end
            end
          end
        end
      end
    end
  end

  if not bestKey then
    return nil, 0, nil
  end

  local tilePos = { x = bestGoalX, y = bestGoalY, z = playerZ }
  local tile = g_map.getTile(tilePos)
  if tile then
    local topThing = tile:getTopUseThing()
    if topThing then
      return topThing, bestCount, tilePos
    end
  end

  return nil, 0, nil
end

function isSpellOnCooldown(spell)
  if getSpellCooldown(spell.id) >= g_clock.millis() then
    return true
  end

  if type(spell.group) == "table" then
    for group, _ in pairs(spell.group) do
      if getGroupSpellCooldown(group) >= g_clock.millis() then
        return true
      end
    end
  else
    if getGroupSpellCooldown(spell.group) >= g_clock.millis() then
      return true
    end
  end

  return false
end

-- HELPER MAGIC SHOOTER: Getters definidos apos as funcoes locais
_Helper.isSpellOnCooldown = function(spell)
  return isSpellOnCooldown(spell)
end

_Helper.onSpellCooldown = function(spellId, delay)
  onSpellCooldown(spellId, delay)
end

_Helper.onSpellGroupCooldown = function(groupId, delay)
  onSpellGroupCooldown(groupId, delay)
end

-- HELPER MAGIC SHOOTER: Object use exhaustion (shared between potions and runes)
_Helper.isObjectUseOnCooldown = function()
  return multiUseExDelay > g_clock.millis() or (spellsCooldown[potionConfig.id] or 0) > g_clock.millis()
end

_Helper.setObjectUseCooldown = function(duration)
  duration = duration or potionConfig.exhaustion
  local now = g_clock.millis()
  local expires = now + duration
  multiUseExDelay = expires
  spellsCooldown[potionConfig.id] = expires
  lastObjectUseWasRune = true
  -- Rune was used, block potion for 1.1s (1s object exhaust + 100ms buffer)
  -- so rune always has priority over potion
  potionTurnCooldown = now + 1100
end

-- HELPER MAGIC SHOOTER: Try to use potion immediately after a spell cast (spells don't share object exhaustion)
_Helper.tryPotionAfterSpell = function()
  checkHealthHealing()
  local localPlayer = g_game.getLocalPlayer()
  if localPlayer then
    local mana, maxMana = localPlayer:getMana(), localPlayer:getMaxMana()
    if mana and maxMana and maxMana > 0 then
      checkManaHealing(mana, maxMana)
    end
  end
end

_Helper.findBestTarget = function(position, direction, area, creatureList, minCreatures)
  return findBestTarget(position, direction, area, creatureList, minCreatures)
end

_Helper.findBestTileForRune = function(playerPos, direction, area, creatureList, minCreatures)
  return findBestTileForRune(playerPos, direction, area, creatureList, minCreatures)
end

function checkMagicShooter()
  _Helper.MagicShooter.check()
end

eventTable.checkMagicShooter.action = checkMagicShooter

function checkAutoTarget()
  _Helper.AutoTarget.check()
end

eventTable.checkAutoTarget.action = checkAutoTarget

function checkFollowFriend()
  _Helper.FollowFriend.check()
end

eventTable.checkFollowFriend.action = checkFollowFriend

-- Called from the Follow Friend checkbox and name field in the targeting panel.
function toggleFollowFriend(widget)
  _Helper.FollowFriend.toggle(widget)
end

function setFollowFriendName(text)
  _Helper.FollowFriend.setName(text)
end

function checkFriendHealing(cachedSpectators)
  if not helperAutomaticFunctionsEnabled then return end
  local localPlayer = g_game.getLocalPlayer()
  if not localPlayer then return end
  if checkNamedSio(localPlayer, cachedSpectators) then
    return
  end
end

eventTable.checkFriendHealing.action = checkFriendHealing

-- Keeps the bot HUD live independently of the cavebot. refreshBotHud() returns
-- immediately (and tears the HUD down) when the HUD is disabled, so this costs
-- nothing for players who never turn it on.
function refreshBotHud()
  local cavebot = modules.game_helper and modules.game_helper.cavebot
  if cavebot and cavebot.refreshBotHud then
    cavebot.refreshBotHud()
  end
end

eventTable.refreshBotHud.action = refreshBotHud

-- HELPER AUTO HASTE: Funções movidas para classes/auto_haste.lua
-- Agora usa onStatesChange + cycle event temporario em vez de eventTable polling

function checkHealthPriority()
  if not helperAutomaticFunctionsEnabled then return true end
  local localPlayer = g_game.getLocalPlayer()
  if not localPlayer then return true end
  local success, health, maxHealth = pcall(function()
    return localPlayer:getHealth(), localPlayer:getMaxHealth()
  end)
  if not success or not health or not maxHealth or maxHealth == 0 then return true end
  for _, spell in ipairs(helperConfig.spells) do
    local healthPercent = (health / maxHealth) * 100
    if spell.id ~= 0 and healthPercent <= tonumber(spell.percent) then
      return false
    end
  end
  return true
end

-- Helper para executar a cura correta baseada na vocação do local player
local function castFriendHealOnMember(localPlayer, member)
  if localPlayer:isSorcerer() then
    return useAutoUH(member)
  elseif localPlayer:isMonk() then
    return useAutoTioSio(member)
  else
    return useAutoSio(member)
  end
end

function onFriendHealing(localPlayer, cachedSpectators)
  if not helperAutomaticFunctionsEnabled then return end

  -- Garantir que temos um localPlayer válido
  if not localPlayer then
    localPlayer = g_game.getLocalPlayer()
  end
  if not localPlayer then return end

  local success, position, localPlayerId = pcall(function()
    return localPlayer:getPosition(), localPlayer:getId()
  end)
  if not success or not position then return end

  -- Buscar membros da party pelos spectators
  local spectators = cachedSpectators
  if not spectators then
    spectators = g_map.getSpectators(position, false)
  end
  if not spectators then return end

  -- Pre-calcular cooldowns das magias de cura
  local granSioSpell = getSpellByClientId(242) -- Nature's Embrace
  local granSioOnCooldown = not granSioSpell or granSioSpell.id == 0 or isSpellOnCooldown(granSioSpell)

  local masResSpell = getSpellByClientId(82) -- Mass Healing
  local masResOnCooldown = not masResSpell or masResSpell.id == 0 or isSpellOnCooldown(masResSpell)

  -- Area real da Mass Healing - mapa de tiles validos
  -- Chave: dy (distancia vertical), Valor: dx maximo permitido naquela linha
  -- Normal (AREA_CIRCLE3X3): cantos cortados nas diagonais
  -- Extended (4x4): area expandida com cantos cortados
  local masResExtended = helperConfig.masreshealing and helperConfig.masreshealing.extended
  local masResArea
  if masResExtended then
    -- 4x4: grid 9x9, centro [4,4]
    masResArea = { [0] = 4, [1] = 4, [2] = 3, [3] = 2, [4] = 1 }
  else
    -- AREA_CIRCLE3X3: grid 7x7, centro [3,3]
    masResArea = { [0] = 3, [1] = 3, [2] = 2, [3] = 1 }
  end

  -- Coletar candidatos a cura, separados por tipo de magia
  -- Prioridade fixa de magias: 1) Nature's Embrace  2) Heal Friend  3) Mass Healing
  -- Dentro de cada magia: prioridade da vocacao (5=mais importante) > vida mais baixa
  local granSioCandidates = {} -- Nature's Embrace targets
  local friendCandidates = {}  -- Heal Friend targets
  local needMasRes = false     -- Mass Healing flag

  for _, creature in pairs(spectators) do
    if creature and creature:isPlayer() and creature:getId() ~= localPlayerId then
      local shield = creature:getShield()
      local isValidTarget = shield and shield > 0
      if isValidTarget then
        local vocKey = getVocationKey(creature)
        if vocKey then
          local memberPos = creature:getPosition()
          if memberPos and g_map.isSightClear(position, memberPos) and isWithinReach(position, memberPos) then
            local memberHealth = creature:getHealthPercent()

            -- 1) Nature's Embrace (maior prioridade - verificar apenas se nao esta em cooldown)
            if not granSioOnCooldown then
              local granSioCfg = helperConfig.gransiohealing[vocKey]
              if granSioCfg and granSioCfg.enabled and memberHealth <= granSioCfg.percent then
                table.insert(granSioCandidates, {
                  creature = creature,
                  priority = granSioCfg.priority or 1,
                  health = memberHealth
                })
              end
            end

            -- 2) Heal Friend (segunda prioridade - fallback do Nature's Embrace)
            local friendCfg = helperConfig.friendhealing[vocKey]
            if friendCfg and friendCfg.enabled and memberHealth <= friendCfg.percent then
              table.insert(friendCandidates, {
                creature = creature,
                priority = friendCfg.priority or 1,
                health = memberHealth
              })
            end

            -- 3) Mass Healing (menor prioridade - precisa estar dentro do raio da magia)
            if not masResOnCooldown then
              local masResCfg = helperConfig.masreshealing and helperConfig.masreshealing[vocKey]
              if masResCfg and masResCfg.enabled and memberHealth <= masResCfg.percent then
                local dx = math.abs(position.x - memberPos.x)
                local dy = math.abs(position.y - memberPos.y)
                local maxDx = masResArea[dy]
                if maxDx and dx <= maxDx and position.z == memberPos.z then
                  needMasRes = true
                end
              end
            end
          end
        end
      end
    end
  end

  -- Ordenar: prioridade da vocacao maior primeiro (5 > 4 > 3...), depois vida mais baixa
  local function sortByPriorityThenHealth(a, b)
    if a.priority ~= b.priority then
      return a.priority > b.priority
    end
    return a.health < b.health
  end

  -- Each spell falls through to the next when it did not actually cast (on
  -- cooldown, self-heal took priority, no rune in the backpack). These used to
  -- return unconditionally, so a blocked higher-priority spell swallowed the
  -- heal and Heal Friend never fired while Nature's Embrace was enabled.
  if #granSioCandidates > 0 then
    table.sort(granSioCandidates, sortByPriorityThenHealth)
    if useAutoGranSio(granSioCandidates[1].creature) then
      return
    end
  end

  if #friendCandidates > 0 then
    table.sort(friendCandidates, sortByPriorityThenHealth)
    if castFriendHealOnMember(localPlayer, friendCandidates[1].creature) then
      return
    end
  end

  if needMasRes then
    useAutoMasRes()
  end
end

-- Event-driven friend healing: called directly when party member health changes
-- More efficient than polling - only processes when health actually changes
function onPartyMemberHealthChangeHelper(creature, healthPercent)
  if not helperAutomaticFunctionsEnabled then return end
  if not creature then return end

  local localPlayer = g_game.getLocalPlayer()
  if not localPlayer then return end

  local success, isParty, position = pcall(function()
    return localPlayer:isPartyMember(), localPlayer:getPosition()
  end)
  if not success or not isParty then return end
  if not position then return end

  local memberPos = creature:getPosition()
  if not memberPos then return end

  -- Check if in sight and within reach
  if not g_map.isSightClear(position, memberPos) then return end
  if not isWithinReach(position, memberPos) then return end

  local vocKey = getVocationKey(creature)
  if not vocKey then return end

  -- Same order as onFriendHealing(): Nature's Embrace, then Heal Friend, then
  -- Mass Healing -- and only stop once a spell really went out. This path used
  -- to check Mass Healing first and return no matter what, so an enabled but
  -- unavailable Mass Healing consumed every health-change event.
  local granSioCfg = helperConfig.gransiohealing[vocKey]
  if granSioCfg and granSioCfg.enabled and healthPercent <= granSioCfg.percent then
    if useAutoGranSio(creature) then
      return
    end
  end

  local friendCfg = helperConfig.friendhealing[vocKey]
  if friendCfg and friendCfg.enabled and healthPercent <= friendCfg.percent then
    if castFriendHealOnMember(localPlayer, creature) then
      return
    end
  end

  local masResCfg = helperConfig.masreshealing and helperConfig.masreshealing[vocKey]
  if masResCfg and masResCfg.enabled and healthPercent <= masResCfg.percent then
    useAutoMasRes()
  end
end

function reset()
  -- Safeguard: skip if panels not ready (avoids nil errors on early init)
  if not healingPanel or not shooterPanel or not toolsPanel then
    return
  end

  for i = 0, 2 do
    removeAction("spell", healingPanel:recursiveGetChildById("spellButton" .. i))
    removeAction("potion", healingPanel:recursiveGetChildById("potionButton" .. i))
  end

  removeAction("training", toolsPanel:recursiveGetChildById("spellTrainingButton0"))
  removeAction("haste", toolsPanel:recursiveGetChildById("hasteButton0"))

  -- Clear magic shooter rules using the new panel
  if modules.game_helper and modules.game_helper.magicShooter then
    modules.game_helper.magicShooter.clearForm()
  end
end

function removeAction(type, button, keepInfo)
  local slotIndex = tonumber(button:getId():match("%d+"))
  if type == "spell" then
    helperConfig.spells[slotIndex + 1].id = 0
    helperConfig.spells[slotIndex + 1].percent = 80
    local button = healingPanel:recursiveGetChildById("spellButton" .. slotIndex)
    local percent = healingPanel:recursiveGetChildById("spellPercentLabel" .. slotIndex)
    button:setImageSource("/images/game/actionbar/actionbarslot")
    button:setImageClip("0 0 34 34")
    button:setBorderWidth(0)
    button:setTooltip("")
    percent:setText("80%")
  elseif type == "potion" then
    if not helperConfig.potions[slotIndex + 1] then
      helperConfig.potions[slotIndex + 1] = {}
    end

    if helperConfig.potions[slotIndex + 1].id == 7642 or helperConfig.potions[slotIndex + 1].id == 23374 then
      helperConfig.potions[slotIndex + 1].priority = 0
      local priorityButton = healingPanel:recursiveGetChildById("priority" .. slotIndex)
      priorityButton:setImageSource("/images/skin/show-gui-help-grey")
      priorityButton:setTooltip(
        "Uses a healing or mana potion when your health or\nmana reaches the defined percentage.\nPaladins can click on this button to change the potion priority:\n  - Icon: Blue (Mana Priority)\n  - Icon: Red  (Health Priority)")
    end

    helperConfig.potions[slotIndex + 1].id = 0
    helperConfig.potions[slotIndex + 1].percent = 50
    local button = healingPanel:recursiveGetChildById("potionButton" .. slotIndex)
    button:setImageSource("/images/game/actionbar/actionbarslot")
    local percent = healingPanel:recursiveGetChildById("potionPercentLabel" .. slotIndex)
    local itemWidget = button:getChildById('potionItem')
    if itemWidget then
      itemWidget:destroy()
    end
    percent:setText("50%")
  elseif type == "training" then
    _Helper.ManaTraining.removeAction(button)
  elseif type == "haste" then
    _Helper.AutoHaste.removeAction(button)
  elseif type == "paralyzeCure" then
    _Helper.ParalyzeCure.removeAction(button)
  elseif type == "exercise" then
    local box = toolsPanel:recursiveGetChildById("autoTrainingItem")
    box:setImageSource("/images/game/actionbar/actionbarslot")
    if button.potionItem then
      button.potionItem:destroy()
    end
  end
  -- Persist configuration after removal
  saveSettings()
end

function loadShooterProfileByName(profileName)
  _Helper.MagicShooter.loadProfileByName(profileName)
end

function resetHelperUI()
  if not healingPanel or not toolsPanel then
    return
  end

  -- Reset spell buttons
  for i = 0, 2 do
    local button = healingPanel:recursiveGetChildById("spellButton" .. i)
    if button then
      button:setImageSource("/images/game/actionbar/actionbarslot")
      button:setImageClip("0 0 34 34")
      button:setBorderWidth(0)
      button:setTooltip("")
    end
    local percent = healingPanel:recursiveGetChildById("spellPercentLabel" .. i)
    if percent then
      percent:setText("80%")
    end
  end

  -- Reset potion buttons
  for i = 0, 2 do
    local button = healingPanel:recursiveGetChildById("potionButton" .. i)
    if button then
      button:setImageSource("/images/game/actionbar/actionbarslot")
      local oldWidget = button:getChildById('potionItem')
      if oldWidget then
        oldWidget:destroy()
      end
    end
    local percent = healingPanel:recursiveGetChildById("potionPercentLabel" .. i)
    if percent then
      percent:setText("50%")
    end
    local priority = healingPanel:recursiveGetChildById("priority" .. i)
    if priority then
      priority:setImageColor("#808080")
      priority:setTooltip("")
    end
  end

  -- Reset training button
  _Helper.ManaTraining.resetButton()

  -- Reset haste button
  _Helper.AutoHaste.resetButton()

  -- Reset stamina food button
  if _Helper.AutoStaminaFood then _Helper.AutoStaminaFood.resetButton() end

  -- Reset paralyze cure button
  if _Helper.ParalyzeCure then _Helper.ParalyzeCure.resetButton() end

  -- Reset auto food checkbox
  _Helper.AutoFood.resetCheckbox()

  -- Reset low capacity alarm
  _Helper.LowCapacityAlarm.resetCheckbox()

  -- Reset low health alarm
  _Helper.LowHealthAlarm.resetCheckbox()

  -- Reset low mana alarm
  _Helper.LowManaAlarm.resetCheckbox()

  -- Reset auto target checkbox
  _Helper.AutoTarget.resetCheckbox()

  -- Reset other checkboxes
  local changeGold = toolsPanel:recursiveGetChildById("changeGold")
  if changeGold then changeGold:setChecked(false) end

  -- Reset shooter panel if available
  if shooterPanel and enableButtons then
    local enableMagicShooter = enableButtons:recursiveGetChildById("enableMagicShooter")
    if enableMagicShooter then enableMagicShooter:setChecked(false) end
  end
end

function onLoadHelperData()
  if not healingPanel or not toolsPanel then
    return
  end

  -- Salvar valores ANTES de resetHelperUI (callbacks podem sobrescrever)
  local savedHasteEnabled, savedHasteSafecast, savedHasteOnlyWalking = _Helper.AutoHaste.collectStates()
  local savedTrainingEnabled = _Helper.ManaTraining.collectStates()
  local savedAutoEatFood = helperConfig.autoEatFood
  local savedAutoChangeGold = helperConfig.autoChangeGold
  local savedAutoTargetEnabled = helperConfig.autoTargetEnabled
  local savedMagicShooterEnabled = helperConfig.magicShooterEnabled
  local savedStaminaFoodEnabled = helperConfig.staminaFood and helperConfig.staminaFood.enabled
  local savedParalyzeCureEnabled = helperConfig.paralyzeCure and helperConfig.paralyzeCure[1] and
      helperConfig.paralyzeCure[1].enabled

  -- Limpar UI antes de carregar novos dados
  resetHelperUI()

  -- Restaurar valores que foram sobrescritos pelo callback
  _Helper.AutoHaste.saveAndRestoreStates(savedHasteEnabled, savedHasteSafecast, savedHasteOnlyWalking)
  _Helper.ManaTraining.saveAndRestoreStates(savedTrainingEnabled)
  helperConfig.autoEatFood = savedAutoEatFood
  helperConfig.autoChangeGold = savedAutoChangeGold
  helperConfig.autoTargetEnabled = savedAutoTargetEnabled
  helperConfig.magicShooterEnabled = savedMagicShooterEnabled
  if helperConfig.staminaFood then
    helperConfig.staminaFood.enabled = savedStaminaFoodEnabled
  end
  if helperConfig.paralyzeCure and helperConfig.paralyzeCure[1] then
    helperConfig.paralyzeCure[1].enabled = savedParalyzeCureEnabled
  end

  for k, v in pairs(helperConfig.spells) do
    if v.id ~= 0 then
      local button = healingPanel:recursiveGetChildById("spellButton" .. k - 1)
      local spell = Spells.getSpellDataById(v.id)
      if spell then
        local spellName = Spells.getSpellNameByWords(spell.words)
        _Helper.setSpellIcon(button, spell.id)
        button:setBorderColorTop("#1b1b1b")
        button:setBorderColorLeft("#1b1b1b")
        button:setBorderColorRight("#757575")
        button:setBorderColorBottom("#757575")
        button:setBorderWidth(1)
        button:setTooltip("Spell: " .. spellName .. "\nWords: " .. spell.words)
      end
    end
    local percentOption = healingPanel:recursiveGetChildById("spellPercentLabel" .. k - 1)
    percentOption:setText(tostring(v.percent) .. "%")
  end

  -- Configurar evento de clique para botoes de spell healing
  for i = 0, 2 do
    local spellButton = healingPanel:recursiveGetChildById("spellButton" .. i)
    if spellButton then
      local index = i
      -- Clique esquerdo: abre seleção de spell
      spellButton.onClick = function()
        assignSpell(spellButton, "Healing", { 2 }, helperConfig.spells)
      end
      -- Clique direito: menu de contexto
      spellButton.onMousePress = function(self, mousePos, mouseButton)
        if mouseButton == MouseRightButton then
          local menu = g_ui.createWidget('PopupMenu')
          menu:setGameMenu(true)
          if helperConfig.spells[index + 1].id > 0 then
            menu:addOption(tr('Edit Spell'),
              function() assignSpell(spellButton, "Healing", { 2 }, helperConfig.spells) end)
            menu:addOption(tr('Remove'), function() removeAction("spell", spellButton) end)
          else
            menu:addOption(tr('Assign Spell'),
              function() assignSpell(spellButton, "Healing", { 2 }, helperConfig.spells) end)
          end
          menu:display(mousePos)
          return true
        end
        return false
      end
    end
  end

  for k, v in pairs(helperConfig.potions) do
    local button = healingPanel:recursiveGetChildById("potionButton" .. k - 1)

    if v.id ~= 0 then
      -- Remove widget antigo se existir
      local oldWidget = button:getChildById('potionItem')
      if oldWidget then
        oldWidget:destroy()
      end

      local itemWidget = g_ui.createWidget('PotionItem', button)
      itemWidget:setItemId(v.id)
      itemWidget:setId('potionItem')
    end

    -- Apply priority color for all potions (even if no potion assigned)
    local priorityButton = healingPanel:recursiveGetChildById("priority" .. k - 1)
    if priorityButton then
      local priority = v.priority or 0
      priorityButton:setImageSource("/images/ui/checkboxcircle")
      if priority == 1 then
        priorityButton:setImageColor("#d94a3a")
        priorityButton:setTooltip("This potion is healing health...")
      elseif priority == 2 then
        priorityButton:setImageColor("#3a8ad9")
        priorityButton:setTooltip("This potion is healing mana...")
      else
        priorityButton:setImageColor("#808080")
        priorityButton:setTooltip("")
      end
    end

    local percentOption = healingPanel:recursiveGetChildById("potionPercentLabel" .. k - 1)
    percentOption:setText(tostring(v.percent) .. "%")
  end

  -- Carregar training para UI
  _Helper.ManaTraining.loadToUI()

  -- Configurar evento de clique para botao de training
  local trainingButton = toolsPanel:recursiveGetChildById("spellTrainingButton0")
  if trainingButton then
    -- Clique esquerdo: abre seleção de spell
    trainingButton.onClick = function()
      assignTrainingSpell(trainingButton)
    end
    -- Clique direito: menu de contexto
    trainingButton.onMousePress = function(self, mousePos, mouseButton)
      if mouseButton == MouseRightButton then
        local menu = g_ui.createWidget('PopupMenu')
        menu:setGameMenu(true)
        if helperConfig.training[1].id > 0 then
          menu:addOption(tr('Edit Training Spell'), function() assignTrainingSpell(trainingButton) end)
          menu:addOption(tr('Remove'), function() removeAction("training", trainingButton) end)
        else
          menu:addOption(tr('Assign Training Spell'), function() assignTrainingSpell(trainingButton) end)
        end
        menu:display(mousePos)
        return true
      end
      return false
    end
  end

  -- Carregar haste para UI
  _Helper.AutoHaste.loadToUI()

  -- Configurar evento de clique para botao de haste
  local hasteButton = toolsPanel:recursiveGetChildById("hasteButton0")
  if hasteButton then
    -- Clique esquerdo: abre seleção de spell
    hasteButton.onClick = function()
      assignTrainingSpell(hasteButton, true)
    end
    -- Clique direito: menu de contexto
    hasteButton.onMousePress = function(self, mousePos, mouseButton)
      if mouseButton == MouseRightButton then
        local menu = g_ui.createWidget('PopupMenu')
        menu:setGameMenu(true)
        if helperConfig.haste[1].id > 0 then
          menu:addOption(tr('Edit Haste Spell'), function() assignTrainingSpell(hasteButton, true) end)
          menu:addOption(tr('Remove'), function() removeAction("haste", hasteButton) end)
        else
          menu:addOption(tr('Assign Haste Spell'), function() assignTrainingSpell(hasteButton, true) end)
        end
        menu:display(mousePos)
        return true
      end
      return false
    end
  end

  -- Carregar auto stamina food para UI
  if _Helper.AutoStaminaFood then _Helper.AutoStaminaFood.loadToUI() end

  -- Carregar paralyze cure para UI
  if _Helper.ParalyzeCure then _Helper.ParalyzeCure.loadToUI() end

  -- Carregar auto food para UI
  _Helper.AutoFood.loadToUI()

  -- Carregar low capacity alarm para UI
  _Helper.LowCapacityAlarm.loadToUI()
  _Helper.LowCapacityAlarm.setupThresholdInput()

  -- Carregar full dust alarm para UI
  _Helper.FullDustAlarm.loadToUI()

  -- Carregar low health alarm para UI
  _Helper.LowHealthAlarm.loadToUI()

  -- Carregar low mana alarm para UI
  _Helper.LowManaAlarm.loadToUI()

  -- Carregar low supply alarm para UI
  _Helper.LowSupplyAlarm.loadToUI()

  -- Carregar auto target para UI
  _Helper.AutoTarget.loadToUI()
  _Helper.FollowFriend.loadToUI()

  -- Populate presets combobox with saved profiles
  local pm = modules.game_helper and modules.game_helper.presetManager
  if pm then
    local sCtx = pm.getShooterContext()
    if sCtx then pm.loadProfileOptions(sCtx) end
  end

  loadShooterProfileByName(helperConfig.selectedShooterProfile)

  local changeGold = toolsPanel:recursiveGetChildById("changeGold")
  if changeGold then changeGold:setChecked(helperConfig.autoChangeGold) end

  -- Carregar paineis de vocação (Exercise Training, Quiver Refill e Magic Shield)
  if modules.game_helper and modules.game_helper.tools then
    modules.game_helper.tools.loadAutomationToUI()
    modules.game_helper.tools.loadExerciseTrainingToUI()
    modules.game_helper.tools.loadQuiverRefillToUI()
    modules.game_helper.tools.loadMagicShieldToUI()
    modules.game_helper.tools.updateVocationPanels()
  end

  local enableMagicShooter = enableButtons:recursiveGetChildById("enableMagicShooter")
  if enableMagicShooter then enableMagicShooter:setChecked(helperConfig.magicShooterEnabled) end

  local alwaysChaseOpponent = enableButtons:recursiveGetChildById("alwaysChaseOpponent")
  if alwaysChaseOpponent then alwaysChaseOpponent:setChecked(helperConfig.alwaysChaseOpponent or false) end

  local disableInProtectZone = enableButtons:recursiveGetChildById("disableInProtectZone")
  if disableInProtectZone then disableInProtectZone:setChecked(helperConfig.disableInProtectZone) end

  botStatus()

  -- Migrate old equipConfig to equipProfiles
  if helperConfig.equipConfig then
    helperConfig.equipProfiles = {
      ["Default"] = helperConfig.equipConfig
    }
    helperConfig.selectedEquipProfile = "Default"
    helperConfig.equipConfig = nil
  end

  -- Validate equipProfiles
  if not helperConfig.equipProfiles then
    helperConfig.equipProfiles = { ["Default"] = { rules = {}, enabled = true } }
    helperConfig.selectedEquipProfile = "Default"
  end
  if not helperConfig.selectedEquipProfile or not helperConfig.equipProfiles[helperConfig.selectedEquipProfile] then
    helperConfig.selectedEquipProfile = "Default"
    if not helperConfig.equipProfiles["Default"] then
      helperConfig.equipProfiles["Default"] = { rules = {}, enabled = true }
    end
  end

  -- Load selected equip profile into equipment module
  if modules.game_helper and modules.game_helper.equip and modules.game_helper.equip.loadConfig then
    local selectedEquipConfig = helperConfig.equipProfiles[helperConfig.selectedEquipProfile]
    if selectedEquipConfig then
      modules.game_helper.equip.loadConfig(selectedEquipConfig)
    end
    if modules.game_helper.equip.loadProfileOptions then
      modules.game_helper.equip.loadProfileOptions()
    end
  end

  -- Carregar configuração do timer
  if _Helper.Timer and _Helper.Timer.loadConfig then
    if helperConfig.timerConfig then
      _Helper.Timer.loadConfig(helperConfig.timerConfig)
      -- Atualizar UI do timer panel
      if modules.game_helper and modules.game_helper.timerPanel and modules.game_helper.timerPanel.rebuildRulesList then
        modules.game_helper.timerPanel.rebuildRulesList()
      end
    end
  end

  -- Sincronizar shortcut panel após carregar todas as configs
  if _Helper.Shortcut and _Helper.Shortcut.syncPanelState then
    _Helper.Shortcut.syncPanelState()
  end

  -- Restaurar UI do Friend Healing (vocation-based)
  if helperConfig.namedSio and healingPanel then
    local namedPanel = healingPanel:recursiveGetChildById('namedSioPanel')
    if namedPanel then
      local enabled = namedPanel:recursiveGetChildById('enableNamedSio')
      local name = namedPanel:recursiveGetChildById('namedSioPlayerName')
      local percent = namedPanel:recursiveGetChildById('namedSioHpPercent')
      local spell = namedPanel:recursiveGetChildById('namedSioSpell')
      if enabled then enabled:setChecked(helperConfig.namedSio.enabled == true) end
      if name then name:setText(helperConfig.namedSio.name or "") end
      if percent then percent:setText(tostring(helperConfig.namedSio.percent or 90)) end
      if spell then
        spell:setCurrentOption(helperConfig.namedSio.spell == "gransio" and "Exura Gran Sio" or "Exura Sio")
      end
    end
  end

  if helperConfig.friendhealing then
    local sioPanel = healingPanel:recursiveGetChildById('friendHealingPanel')
    if sioPanel then
      local vocations = { "Knight", "Paladin", "Sorcerer", "Druid", "Monk" }
      for _, vocName in ipairs(vocations) do
        local vocKey = vocName:lower()
        local config = helperConfig.friendhealing[vocKey]
        if config then
          local enableCb = sioPanel:recursiveGetChildById("enableFriend" .. vocName)
          if enableCb then enableCb:setChecked(config.enabled or false) end
          local percentCb = sioPanel:recursiveGetChildById("friendPercent" .. vocName)
          if percentCb and config.percent then percentCb:setCurrentOption(tostring(config.percent) .. "%") end
          local prioCb = sioPanel:recursiveGetChildById("friendPriority" .. vocName)
          if prioCb and config.priority then prioCb:setCurrentOption(tostring(config.priority)) end
        end
      end
    end
  end

  -- Restaurar UI do Gran Sio Healing (vocation-based)
  if helperConfig.gransiohealing then
    local granPanel = healingPanel:recursiveGetChildById('granSioPanel')
    if granPanel then
      local vocations = { "Knight", "Paladin", "Sorcerer", "Druid", "Monk" }
      for _, vocName in ipairs(vocations) do
        local vocKey = vocName:lower()
        local config = helperConfig.gransiohealing[vocKey]
        if config then
          local enableCb = granPanel:recursiveGetChildById("enableGranSio" .. vocName)
          if enableCb then enableCb:setChecked(config.enabled or false) end
          local percentCb = granPanel:recursiveGetChildById("granSioPercent" .. vocName)
          if percentCb and config.percent then percentCb:setCurrentOption(tostring(config.percent) .. "%") end
          local prioCb = granPanel:recursiveGetChildById("granSioPriority" .. vocName)
          if prioCb and config.priority then prioCb:setCurrentOption(tostring(config.priority)) end
        end
      end
    end
  end

  -- Restaurar UI do Mas Res Healing (vocation-based)
  if helperConfig.masreshealing then
    local masPanel = healingPanel:recursiveGetChildById('masResPanel')
    if masPanel then
      local vocations = { "Knight", "Paladin", "Sorcerer", "Druid", "Monk" }
      for _, vocName in ipairs(vocations) do
        local vocKey = vocName:lower()
        local config = helperConfig.masreshealing[vocKey]
        if config then
          local enableCb = masPanel:recursiveGetChildById("enableMasRes" .. vocName)
          if enableCb then enableCb:setChecked(config.enabled or false) end
          local percentCb = masPanel:recursiveGetChildById("masResPercent" .. vocName)
          if percentCb and config.percent then percentCb:setCurrentOption(tostring(config.percent) .. "%") end
          local prioCb = masPanel:recursiveGetChildById("masResPriority" .. vocName)
          if prioCb and config.priority then prioCb:setCurrentOption(tostring(config.priority)) end
        end
      end
      local extendedCb = masPanel:recursiveGetChildById("masResExtended")
      if extendedCb then extendedCb:setChecked(helperConfig.masreshealing.extended or false) end
    end
  end

  -- Scripting settings are character-specific, like the rest of EloriaBot.
  if modules.game_helper and modules.game_helper.scripting then
    modules.game_helper.scripting.loadConfig(helperConfig.scriptingScripts)
    helperConfig.scriptingScripts = modules.game_helper.scripting.getConfig()
  end

  -- Sincronizar shortcut panel com os dados carregados
  _Helper.Shortcut.syncPanelState()

  -- Allow saving now that config is loaded
  skipSaveUntilLoaded = false

  -- Rebuild cache after loading all data
  rebuildHealingCache()
end

-- SAVE
function saveSettings()
  if skipSaveUntilLoaded then
    return false
  end

  local currentPlayer = g_game.getLocalPlayer()
  local dir = getCharacterStorageDir(currentPlayer)
  if not dir then
    return false
  end

  local folder = dir .. "/helper.json"

  g_resources.makeDir(dir)

  local cleanConfig = {}
  for k, v in pairs(helperConfig) do
    if type(v) ~= "function" then
      cleanConfig[k] = v
    end
  end

  -- Salvar estado do helper enabled
  cleanConfig.helperAutomaticFunctionsEnabled = helperAutomaticFunctionsEnabled
  cleanConfig.characterName = getCharacterStorageName(currentPlayer)

  -- Save current equip config back to active profile
  if modules.game_helper and modules.game_helper.equip and modules.game_helper.equip.saveConfig then
    local activeProfile = helperConfig.selectedEquipProfile or "Default"
    if not helperConfig.equipProfiles then
      helperConfig.equipProfiles = {}
    end
    helperConfig.equipProfiles[activeProfile] = modules.game_helper.equip.saveConfig()
  end
  cleanConfig.equipConfig = nil

  -- Salvar configuração do timer
  if _Helper.Timer and _Helper.Timer.saveConfig then
    cleanConfig.timerConfig = _Helper.Timer.saveConfig()
  end

  if modules.game_helper and modules.game_helper.scripting then
    cleanConfig.scriptingScripts = modules.game_helper.scripting.getConfig()
  end

  cleanConfig.shortcutsVisible = _Helper.Shortcut.isVisible()

  local status, result = pcall(function()
    return json.encode(cleanConfig, 2)
  end)
  if not status then
    g_logger.error("Could not encode helper settings: " .. tostring(result))
    return false
  end

  if result:len() > 100 * 1024 * 1024 then
    g_logger.error("Could not save helper settings: encoded configuration is too large")
    return false
  end

  -- Safely attempt to write the file
  local writeStatus, writeResult = pcall(function()
    return g_resources.writeFileContents(folder, result)
  end)

  if not writeStatus then
    g_logger.error("Could not save helper settings: " .. tostring(writeResult))
    return false
  end
  if writeResult == false then
    g_logger.error("Could not save helper settings: writeFileContents returned false")
    return false
  end
  return true
end

-- Exportar saveSettings para módulos externos (deve ficar APÓS a definição da função)
_Helper.saveSettings = saveSettings

function saveHelperSettings()
  if saveSettings() then
    modules.game_textmessage.displayGameMessage("Helper configuration saved successfully!")
  else
    modules.game_textmessage.displayFailureMessage("Could not save Helper configuration.")
  end
end

function loadSettings()
  local currentPlayer = g_game.getLocalPlayer()
  if not currentPlayer then
    return false
  end

  -- Prefer the stable per-character path. Read the old runtime-id path once
  -- and copy it forward so existing users keep their configuration.
  local dir = getCharacterStorageDir(currentPlayer)
  if not dir then return false end
  local folder = dir .. "/helper.json"
  local legacyDir = getLegacyCharacterStorageDir(currentPlayer)
  local legacyFolder = legacyDir and (legacyDir .. "/helper.json") or nil
  local migratedFromLegacy = false

  if not g_resources.fileExists(folder) and legacyFolder and legacyFolder ~= folder and
      g_resources.fileExists(legacyFolder) then
    folder = legacyFolder
    migratedFromLegacy = true
  end

  local function resetToDefaults()
    local savedHotkeys = _Helper.HotkeyManager.preserveAll()
    helperConfig = {
      spells                 = {
        { id = 0, percent = 80 },
        { id = 0, percent = 80 },
        { id = 0, percent = 80 }
      },
      potions                = {
        { id = 0, percent = 50, priority = 0 },
        { id = 0, percent = 50, priority = 0 },
        { id = 0, percent = 50, priority = 0 }
      },
      training               = { { id = 0, percent = 0, enabled = false } },
      haste                  = { { id = 0, enabled = false, safecast = false, onlyWalking = false } },
      staminaFood            = { id = 0, enabled = false, thresholdMinutes = 30 },
      paralyzeCure           = { { id = 0, enabled = false } },
      friendhealing          = {
        knight   = { enabled = false, percent = 90, priority = 5 },
        paladin  = { enabled = false, percent = 90, priority = 4 },
        sorcerer = { enabled = false, percent = 90, priority = 3 },
        druid    = { enabled = false, percent = 90, priority = 2 },
        monk     = { enabled = false, percent = 90, priority = 1 },
      },
      gransiohealing         = {
        knight   = { enabled = false, percent = 90, priority = 5 },
        paladin  = { enabled = false, percent = 90, priority = 4 },
        sorcerer = { enabled = false, percent = 90, priority = 3 },
        druid    = { enabled = false, percent = 90, priority = 2 },
        monk     = { enabled = false, percent = 90, priority = 1 },
      },
      masreshealing          = {
        extended = false,
        knight   = { enabled = false, percent = 90, priority = 5 },
        paladin  = { enabled = false, percent = 90, priority = 4 },
        sorcerer = { enabled = false, percent = 90, priority = 3 },
        druid    = { enabled = false, percent = 90, priority = 2 },
        monk     = { enabled = false, percent = 90, priority = 1 },
      },
      healingTargetMode      = "party",
      shooterProfiles        = { ["Default"] = deepCopy(defaultShooterProfile) },
      selectedShooterProfile = "Default",
      equipProfiles          = { ["Default"] = { rules = {}, enabled = true } },
      selectedEquipProfile   = "Default",
      supplyProfiles         = { ["Default"] = { rules = {} } },
      selectedSupplyProfile  = "Default",
      autoEatFood            = false,
      showLookItemId         = false,
      autoQuillSell          = false,
      autoQuillSellBelowCap  = false,
      autoQuillSellCapacity  = 100,
      antiIdle               = false,
      autoParty              = {
        enabled = false,
        acceptEnabled = false,
        sendList = { "", "", "", "" },
        acceptLeader = ""
      },
      autoChangeGold         = false,
      magicShooterEnabled    = false,
      magicShooterOnHold     = false,
      disableInProtectZone   = true,
      alwaysChaseOpponent   = false,
      autoTargetEnabled      = false,
      autoTargetMode         = autoTargetModes["F"],
      currentLockedTargetId  = 0,
      ignoreMonsterList      = "",
      priorityMonsterList    = "",
      targetMonsterList      = "*",
      scriptingScripts      = {},
    }
    _Helper.HotkeyManager.restoreAll(savedHotkeys)
    if modules.game_helper and modules.game_helper.scripting then
      modules.game_helper.scripting.loadConfig(helperConfig.scriptingScripts)
    end
  end

  if not g_resources.fileExists(folder) then
    resetToDefaults()
    helperAutomaticFunctionsEnabled = true
    if helperConfig then
      helperConfig.helperAutomaticFunctionsEnabled = true
    end
    return false
  end

  local rawConfig = nil
  local status, result = pcall(function()
    rawConfig = g_resources.readFileContents(folder)
    return json.decode(rawConfig)
  end)

  if not status or not result then
    resetToDefaults()
    return false
  end

  if migratedFromLegacy and rawConfig then
    g_resources.makeDir(dir)
    pcall(function()
      g_resources.writeFileContents(dir .. "/helper.json", rawConfig)
    end)
  end

  -- Preservar funções de hotkey (não são serializáveis, então não vêm do arquivo)
  local savedFuncs = _Helper.HotkeyManager.preserveFuncs()

  helperConfig = result

  -- Restaurar apenas as funções de hotkey (os códigos vêm do arquivo)
  _Helper.HotkeyManager.restoreFuncs(savedFuncs)

  -- Restaurar estado do helper enabled
  if result.helperAutomaticFunctionsEnabled ~= nil then
    helperAutomaticFunctionsEnabled = result.helperAutomaticFunctionsEnabled == true
  else
    helperAutomaticFunctionsEnabled = true
  end
  helperConfig.helperAutomaticFunctionsEnabled = helperAutomaticFunctionsEnabled

  -- Restaurar estado do shortcuts visible
  if result.shortcutsVisible ~= nil then
    _Helper.Shortcut.setVisible(result.shortcutsVisible)
  end

  -- spells
  if not helperConfig.spells then
    helperConfig.spells = {
      { id = 0, percent = 80 },
      { id = 0, percent = 80 },
      { id = 0, percent = 80 }
    }
  end
  if #helperConfig.spells < 3 then
    table.insert(helperConfig.spells, { id = 0, percent = 0 })
  end
  for _, k in pairs(helperConfig.spells) do
    if k.percent == 0 then
      k.percent = 80
    end
  end

  -- potions
  if not helperConfig.potions then
    helperConfig.potions = {
      { id = 0, percent = 50, priority = 0 },
      { id = 0, percent = 50, priority = 0 },
      { id = 0, percent = 50, priority = 0 }
    }
  end
  for _, k in pairs(helperConfig.potions) do
    if k.percent == 0 then k.percent = 50 end
    if not k.priority then k.priority = 0 end
    if not k.id then k.id = 0 end
  end

  -- specialFoods: SPECIAL_FOOD_SLOTS free-assign slots per category. The item in
  -- each slot is chosen by the player, so keep whatever was saved (by slot index)
  -- and only pad/trim the list to the expected slot count.
  local function normalizeSpecialFoods(saved, defaultPercent)
    local slots = {}
    for i = 1, SPECIAL_FOOD_SLOTS do
      local f = type(saved) == "table" and saved[i] or nil
      local percent = f and tonumber(f.percent) or nil
      local priority = f and tonumber(f.priority) or nil
      slots[i] = {
        id = (f and tonumber(f.id)) or 0,
        enabled = (f and f.enabled) and true or false,
        percent = (percent and percent > 0) and percent or defaultPercent,
        priority = (priority and priority > 0) and priority or i,
      }
    end
    return slots
  end

  if not helperConfig.specialFoods then
    helperConfig.specialFoods = {}
  end
  helperConfig.specialFoods.hp = normalizeSpecialFoods(helperConfig.specialFoods.hp, 80)
  helperConfig.specialFoods.mana = normalizeSpecialFoods(helperConfig.specialFoods.mana, 60)

  if not helperConfig.training then
    helperConfig.training = { { id = 0, percent = 0, enabled = false } }
  end
  if not helperConfig.haste then
    helperConfig.haste = { { id = 0, enabled = false, safecast = false, onlyWalking = false } }
  end
  -- Garantir que cada item de haste tenha o campo onlyWalking (migração de dados antigos)
  for _, k in pairs(helperConfig.haste) do
    if k.onlyWalking == nil then k.onlyWalking = false end
  end

  -- staminaFood: single free-assign slot, same shape as haste
  if type(helperConfig.staminaFood) ~= "table" then
    helperConfig.staminaFood = { id = 0, enabled = false, thresholdMinutes = 30 }
  end
  helperConfig.staminaFood.id = tonumber(helperConfig.staminaFood.id) or 0
  helperConfig.staminaFood.enabled = helperConfig.staminaFood.enabled == true
  local staminaThreshold = tonumber(helperConfig.staminaFood.thresholdMinutes)
  helperConfig.staminaFood.thresholdMinutes = (staminaThreshold and staminaThreshold >= 0) and staminaThreshold or 30

  -- paralyzeCure: single free-assign spell slot, same shape as haste
  if type(helperConfig.paralyzeCure) ~= "table" or not helperConfig.paralyzeCure[1] then
    helperConfig.paralyzeCure = { { id = 0, enabled = false } }
  end
  helperConfig.paralyzeCure[1].id = tonumber(helperConfig.paralyzeCure[1].id) or 0
  helperConfig.paralyzeCure[1].enabled = helperConfig.paralyzeCure[1].enabled == true
  -- Migração de formato antigo (array com name) para novo formato (vocation-based)
  local defaultVocHealing = {
    knight   = { enabled = false, percent = 90, priority = 5 },
    paladin  = { enabled = false, percent = 90, priority = 4 },
    sorcerer = { enabled = false, percent = 90, priority = 3 },
    druid    = { enabled = false, percent = 90, priority = 2 },
    monk     = { enabled = false, percent = 90, priority = 1 },
  }
  if not helperConfig.friendhealing or helperConfig.friendhealing[1] ~= nil then
    helperConfig.friendhealing = deepCopy(defaultVocHealing)
  end
  if type(helperConfig.namedSio) ~= "table" then
    helperConfig.namedSio = { enabled = false, name = "", percent = 90, spell = "sio" }
  end
  helperConfig.namedSio.enabled = helperConfig.namedSio.enabled == true
  helperConfig.namedSio.name = trimNamedSioText(helperConfig.namedSio.name)
  helperConfig.namedSio.percent = math.max(1, math.min(99, tonumber(helperConfig.namedSio.percent) or 90))
  -- Existing configs predate the selector, so anything but "gransio" means plain sio.
  helperConfig.namedSio.spell = helperConfig.namedSio.spell == "gransio" and "gransio" or "sio"
  -- Garantir que todas as vocações existam no config
  for voc, def in pairs(defaultVocHealing) do
    if not helperConfig.friendhealing[voc] then
      helperConfig.friendhealing[voc] = deepCopy(def)
    end
    local v = helperConfig.friendhealing[voc]
    v.enabled = v.enabled == true
    if not v.percent then v.percent = 90 end
    if not v.priority then v.priority = def.priority end
  end
  if not helperConfig.gransiohealing or helperConfig.gransiohealing[1] ~= nil then
    helperConfig.gransiohealing = deepCopy(defaultVocHealing)
  end
  for voc, def in pairs(defaultVocHealing) do
    if not helperConfig.gransiohealing[voc] then
      helperConfig.gransiohealing[voc] = deepCopy(def)
    end
    local v = helperConfig.gransiohealing[voc]
    v.enabled = v.enabled == true
    if not v.percent then v.percent = 90 end
    if not v.priority then v.priority = def.priority end
  end
  if not helperConfig.masreshealing or helperConfig.masreshealing[1] ~= nil then
    helperConfig.masreshealing = deepCopy(defaultVocHealing)
  end
  for voc, def in pairs(defaultVocHealing) do
    if not helperConfig.masreshealing[voc] then
      helperConfig.masreshealing[voc] = deepCopy(def)
    end
    local v = helperConfig.masreshealing[voc]
    v.enabled = v.enabled == true
    if not v.percent then v.percent = 90 end
    if not v.priority then v.priority = def.priority end
  end
  helperConfig.masreshealing.extended = helperConfig.masreshealing.extended == true
  if helperConfig.healingTargetMode ~= "screen" and helperConfig.healingTargetMode ~= "party" then
    helperConfig.healingTargetMode = "party"
  end
  if not helperConfig.shooterProfiles then
    helperConfig.selectedShooterProfile = "Default"
    helperConfig.shooterProfiles = { ["Default"] = defaultShooterProfile }
  end
  -- Validate selectedShooterProfile exists, fallback to Default if not
  if not helperConfig.selectedShooterProfile or not helperConfig.shooterProfiles[helperConfig.selectedShooterProfile] then
    helperConfig.selectedShooterProfile = "Default"
    -- Ensure Default profile exists
    if not helperConfig.shooterProfiles["Default"] then
      helperConfig.shooterProfiles["Default"] = deepCopy(defaultShooterProfile)
    end
  end
  for _, profile in pairs(helperConfig.shooterProfiles) do
    if not profile.autoTargetMode then
      profile.autoTargetMode = autoTargetModes["F"]
    end
  end

  -- Validate equipProfiles
  if not helperConfig.equipProfiles then
    helperConfig.equipProfiles = { ["Default"] = { rules = {}, enabled = true } }
    helperConfig.selectedEquipProfile = "Default"
  end
  if not helperConfig.selectedEquipProfile or not helperConfig.equipProfiles[helperConfig.selectedEquipProfile] then
    helperConfig.selectedEquipProfile = "Default"
    if not helperConfig.equipProfiles["Default"] then
      helperConfig.equipProfiles["Default"] = { rules = {}, enabled = true }
    end
  end

  -- Validate supplyProfiles
  if not helperConfig.supplyProfiles then
    helperConfig.supplyProfiles = { ["Default"] = { rules = {} } }
    helperConfig.selectedSupplyProfile = "Default"
  end
  if not helperConfig.selectedSupplyProfile or not helperConfig.supplyProfiles[helperConfig.selectedSupplyProfile] then
    helperConfig.selectedSupplyProfile = "Default"
    if not helperConfig.supplyProfiles["Default"] then
      helperConfig.supplyProfiles["Default"] = { rules = {} }
    end
  end

  if helperConfig.autoEatFood == nil then
    helperConfig.autoEatFood = false
  end
  if helperConfig.showLookItemId == nil then
    helperConfig.showLookItemId = false
  end
  if helperConfig.antiIdle == nil then
    helperConfig.antiIdle = false
  end
  if not helperConfig.autoParty then
    helperConfig.autoParty = {
      enabled = false,
      acceptEnabled = false,
      sendList = { "", "", "", "" },
      acceptLeader = ""
    }
  else
    if helperConfig.autoParty.enabled == nil then helperConfig.autoParty.enabled = false end
    if helperConfig.autoParty.acceptEnabled == nil then helperConfig.autoParty.acceptEnabled = false end
    if type(helperConfig.autoParty.sendList) ~= "table" then
      helperConfig.autoParty.sendList = { "", "", "", "" }
    end
    for i = 1, 4 do
      if helperConfig.autoParty.sendList[i] == nil then helperConfig.autoParty.sendList[i] = "" end
    end
    if helperConfig.autoParty.acceptLeader == nil then helperConfig.autoParty.acceptLeader = "" end
  end
  if helperConfig.autoChangeGold == nil then
    helperConfig.autoChangeGold = false
  end
  if helperConfig.magicShooterEnabled == nil then
    helperConfig.magicShooterEnabled = false
  end
  if helperConfig.magicShooterOnHold == nil then
    helperConfig.magicShooterOnHold = false
  end
  if helperConfig.disableInProtectZone == nil then
    helperConfig.disableInProtectZone = true
  end
  if helperConfig.alwaysChaseOpponent == nil then
    helperConfig.alwaysChaseOpponent = false
  end
  if helperConfig.autoTargetEnabled == nil then
    helperConfig.autoTargetEnabled = false
  end
  if not helperConfig.autoTargetMode then
    helperConfig.autoTargetMode = autoTargetModes["F"]
  end
  if not helperConfig.currentLockedTargetId then
    helperConfig.currentLockedTargetId = 0
  end
  if helperConfig.ignoreMonsterList == nil then
    helperConfig.ignoreMonsterList = ""
  end
  -- "*" == attack every monster. Existing profiles predate this field, so they
  -- must default to "all" and not to an empty (= attack nothing) whitelist.
  if helperConfig.targetMonsterList == nil or helperConfig.targetMonsterList == "" then
    helperConfig.targetMonsterList = "*"
  end
  if helperConfig.priorityMonsterList == nil then
    helperConfig.priorityMonsterList = ""
  end

  -- Initialize quiverRefill defaults if not present
  if not helperConfig.quiverRefill then
    helperConfig.quiverRefill = {
      enabled = false,
      itemId = 0,
      minValue = 50,
      refillValue = 100
    }
  else
    -- Ensure all fields have defaults
    if helperConfig.quiverRefill.enabled == nil then
      helperConfig.quiverRefill.enabled = false
    end
    if not helperConfig.quiverRefill.itemId then
      helperConfig.quiverRefill.itemId = 0
    end
    if not helperConfig.quiverRefill.minValue then
      helperConfig.quiverRefill.minValue = 50
    end
    if not helperConfig.quiverRefill.refillValue then
      helperConfig.quiverRefill.refillValue = 100
    end
  end

  -- Initialize magicShield defaults if not present
  if not helperConfig.magicShield then
    helperConfig.magicShield = {
      utamoEnabled = false,
      exanaEnabled = false,
      utamoHpPercent = 80,
      exanaHpPercent = 90
    }
  else
    -- Ensure all fields have defaults
    if helperConfig.magicShield.utamoEnabled == nil then
      helperConfig.magicShield.utamoEnabled = false
    end
    if helperConfig.magicShield.exanaEnabled == nil then
      helperConfig.magicShield.exanaEnabled = false
    end
    helperConfig.magicShield.potionEnabled = nil
    if not helperConfig.magicShield.utamoHpPercent then
      helperConfig.magicShield.utamoHpPercent = 80
    end
    if not helperConfig.magicShield.exanaHpPercent then
      helperConfig.magicShield.exanaHpPercent = 90
    end
  end

  return true
end

-- Wrapper function for Exercise Event (OTUI compatibility)
-- NOTE: Exercise training now uses its own cycle event in _Helper.ExerciseTraining
-- The eventTable polling is disabled to prevent redundant checks
function checkExerciseEvent()
  -- Delegated to the ExerciseTraining class which has its own cycle event
  -- This function is kept for backwards compatibility but the eventTable action is disabled
end

-- Wrapper function for getting exercise dummy
function getExerciseDummy()
  if modules.game_helper and modules.game_helper.tools then
    return modules.game_helper.tools.getExerciseDummy()
  end
  return nil
end

-- Disabled: Exercise training now uses its own cycle event via _Helper.ExerciseTraining
-- eventTable.checkExerciseEvent.action = checkExerciseEvent

-- Check and equip items (rings/amulets) based on health conditions
function checkEquipItems()
  if not g_game.isOnline() or not helperAutomaticFunctionsEnabled then return end

  -- Call the equip module's check function
  if modules.game_helper and modules.game_helper.equip and modules.game_helper.equip.checkEquipItems then
    modules.game_helper.equip.checkEquipItems()
  end
end

eventTable.checkEquipItems.action = checkEquipItems

-- Check and refill quiver for paladins
function checkQuiverRefill()
  if not g_game.isOnline() or not helperAutomaticFunctionsEnabled then return end

  -- Call the tools module's check function
  if modules.game_helper and modules.game_helper.tools and modules.game_helper.tools.checkQuiverRefill then
    modules.game_helper.tools.checkQuiverRefill()
  end
end

eventTable.checkQuiverRefill.action = checkQuiverRefill

-- Check and manage magic shield for mages
function checkMagicShield()
  if not g_game.isOnline() or not helperAutomaticFunctionsEnabled then return end

  -- Call the tools module's check function
  if modules.game_helper and modules.game_helper.tools and modules.game_helper.tools.checkMagicShield then
    modules.game_helper.tools.checkMagicShield()
  end
end

eventTable.checkMagicShield.action = checkMagicShield

-- Wrapper function for assigning exercise event (OTUI compatibility)
function assignExerciseEvent(button)
  if modules.game_helper and modules.game_helper.tools then
    modules.game_helper.tools.assignExerciseEvent(button)
  end
end

-- Wrapper function for assign exercise callback (OTUI compatibility)
function onAssignExercise(self, mousePosition, mouseButton, button)
  if modules.game_helper and modules.game_helper.tools then
    modules.game_helper.tools.onAssignExercise(self, mousePosition, mouseButton, button)
  end
end

function onCheckPotionPriority(button)
  local index = tonumber(button:getId():match("%d+"))
  local current = helperConfig.potions[index + 1].priority or 0
  local newPriority
  if current == 0 then
    newPriority = 1
  elseif current == 1 then
    newPriority = 2
  else
    newPriority = 1
  end
  helperConfig.potions[index + 1].priority = newPriority
  button:setImageSource("/images/ui/checkboxcircle")
  if newPriority == 1 then
    button:setImageColor("#d94a3a")
    button:setTooltip("This potion is healing health...")
  else
    button:setImageColor("#3a8ad9")
    button:setTooltip("This potion is healing mana...")
  end
  rebuildHealingCache()
end

function onPotionPriorityMouse(self, mousePosition, mouseButton)
  local index = tonumber(self:getId():match("%d+"))
  local current = helperConfig.potions[index + 1].priority or 0
  local newPriority = (current == 1) and 2 or 1
  helperConfig.potions[index + 1].priority = newPriority
  self:setImageSource("/images/ui/checkboxcircle")
  if newPriority == 1 then
    self:setImageColor("#d94a3a")
    self:setTooltip("This potion is healing health...")
  else
    self:setImageColor("#3a8ad9")
    self:setTooltip("This potion is healing mana...")
  end
  rebuildHealingCache()
end

-- ===== SPECIAL FOODS =====

-- Ordena foods por prioridade (menor primeiro), embaralhando foods com mesma prioridade
function sortSpecialFoodsByPriority(foods)
  -- Agrupar por prioridade
  local groups = {}
  for _, food in ipairs(foods) do
    local p = food.priority or 99
    if not groups[p] then groups[p] = {} end
    table.insert(groups[p], food)
  end
  -- Coletar prioridades e ordenar
  local priorities = {}
  for p, _ in pairs(groups) do
    table.insert(priorities, p)
  end
  table.sort(priorities)
  -- Montar lista final, embaralhando cada grupo
  local result = {}
  for _, p in ipairs(priorities) do
    local group = groups[p]
    -- Fisher-Yates shuffle
    for i = #group, 2, -1 do
      local j = math.random(1, i)
      group[i], group[j] = group[j], group[i]
    end
    for _, food in ipairs(group) do
      table.insert(result, food)
    end
  end
  return result
end

modules.game_helper = modules.game_helper or {}

function useSpecialFood(foodId)
  local player = g_game.getLocalPlayer()
  if not player or not foodId or foodId == 0 then
    return false
  end

  local cooldown = spellsCooldown[specialFoodConfig.id] or 0
  if cooldown > g_clock.millis() then
    return false
  end

  if multiUseExDelay > g_clock.millis() then
    return false
  end

  local foodCount = player:getInventoryCount(foodId, 0)
  if foodCount and foodCount > 0 then
    safeDoThing(false)
    g_game.useInventoryItem(foodId)
    safeDoThing(true)
    local now = g_clock.millis()
    spellsCooldown[specialFoodConfig.id] = now + specialFoodConfig.exhaustion
    multiUseExDelay = now + specialFoodConfig.exhaustion
    specialFoodLocalCooldowns[foodId] = now + (15 * 60 * 1000) -- 15 min local cooldown
    return true
  end

  return false
end

-- Guards the checkbox callback while refreshSpecialFoodRow pushes config into the UI,
-- so setChecked() does not bounce back into toggleSpecialFood and re-save.
local specialFoodsSyncingUI = false

local function getSpecialFoodSlotConfig(category, index)
  if not helperConfig or not helperConfig.specialFoods then return nil end
  local list = helperConfig.specialFoods[category]
  if not list then return nil end
  return list[index]
end

local function getSpecialFoodRow(category, index)
  if not specialFoodsWindow then return nil end
  local meta = SPECIAL_FOOD_CATEGORIES[category]
  if not meta then return nil end
  local rows = specialFoodsWindow:recursiveGetChildById(meta.rowsId)
  if not rows then return nil end
  return rows:getChildById(category .. "FoodRow" .. index)
end

local function getSpecialFoodItemName(itemId, item)
  if item and item.getName then
    local name = item:getName()
    if name and name ~= "" then return name end
  end
  local thingType = g_things.getThingType(itemId, ThingCategoryItem)
  if thingType then
    local marketData = thingType:getMarketData()
    if marketData and marketData.name and marketData.name ~= "" then
      return marketData.name
    end
  end
  return "Item #" .. itemId
end

local function refreshSpecialFoodRow(category, index)
  local row = getSpecialFoodRow(category, index)
  local food = getSpecialFoodSlotConfig(category, index)
  if not row or not food then return end

  local meta = SPECIAL_FOOD_CATEGORIES[category]
  local slot = row:getChildById('slot')
  if slot then
    local existing = slot:getChildById('foodItem')
    if food.id and food.id ~= 0 then
      if not existing then
        existing = g_ui.createWidget('FoodItem', slot)
        existing:setId('foodItem')
      end
      existing:setItemId(food.id)
      slot:setImageSource('/images/ui/item')
      slot:setTooltip(getSpecialFoodItemName(food.id) .. "\nRight click to change or remove")
    else
      if existing then existing:destroy() end
      slot:setImageSource('/images/game/actionbar/actionbarslot')
      slot:setTooltip(tr('Right click to assign an item'))
    end
  end

  specialFoodsSyncingUI = true
  local checkbox = row:getChildById('enable')
  if checkbox then
    checkbox:setChecked(food.enabled and true or false)
  end
  specialFoodsSyncingUI = false

  local percentLabel = row:recursiveGetChildById('percentLabel')
  if percentLabel then
    percentLabel:setText((food.percent or meta.defaultPercent) .. "%")
  end

  local priorityLabel = row:recursiveGetChildById('priorityLabel')
  if priorityLabel then
    priorityLabel:setText(tostring(food.priority or index))
  end
end

function toggleSpecialFood(category, index, checked)
  if specialFoodsSyncingUI then return end
  local food = getSpecialFoodSlotConfig(category, index)
  if not food then return end
  food.enabled = checked and true or false
  saveSettings()
end

function updateSpecialFoodPercent(category, index, delta)
  local food = getSpecialFoodSlotConfig(category, index)
  if not food then return end

  local newPercent = (food.percent or 50) + delta
  if newPercent < 5 then newPercent = 5 end
  if newPercent > 99 then newPercent = 99 end
  food.percent = newPercent

  local row = getSpecialFoodRow(category, index)
  local label = row and row:recursiveGetChildById('percentLabel')
  if label then
    label:setText(newPercent .. "%")
  end

  saveSettings()
end

function updateSpecialFoodPriority(category, index, delta)
  local food = getSpecialFoodSlotConfig(category, index)
  if not food then return end

  local maxPriority = #(helperConfig.specialFoods[category] or {})
  local newPriority = (food.priority or 1) + delta
  if newPriority < 1 then newPriority = 1 end
  if newPriority > maxPriority then newPriority = maxPriority end
  food.priority = newPriority

  local row = getSpecialFoodRow(category, index)
  local label = row and row:recursiveGetChildById('priorityLabel')
  if label then
    label:setText(tostring(newPriority))
  end

  saveSettings()
end

function removeSpecialFood(category, index)
  local food = getSpecialFoodSlotConfig(category, index)
  if not food then return end

  food.id = 0
  food.enabled = false
  refreshSpecialFoodRow(category, index)
  saveSettings()
end

function onAssignSpecialFood(self, mousePosition, mouseButton, category, index)
  specialFoodAssignActive = false
  mouseGrabberWidget:ungrabMouse()
  g_mouse.popCursor('target')
  mouseGrabberWidget.onMouseRelease = nil

  if specialFoodsWindow then
    specialFoodsWindow:show()
    specialFoodsWindow:raise()
    specialFoodsWindow:focus()
  end

  local rootWidget = g_ui.getRootWidget()
  if not rootWidget then return true end

  local clickedWidget = rootWidget:recursiveGetChildByPos(mousePosition, false)
  if not clickedWidget then return true end

  local itemId = 0
  local item = nil
  if clickedWidget:getClassName() == 'UIItem' and not clickedWidget:isVirtual() then
    item = clickedWidget:getItem()
    if item then
      itemId = item:getId()
    end
  elseif clickedWidget:getClassName() == 'UIGameMap' then
    local tile = clickedWidget:getTile(mousePosition)
    if tile then
      local topUseThing = tile:getTopUseThing()
      if topUseThing then
        itemId = topUseThing:getId()
        item = topUseThing
      end
    end
  end

  if itemId == 0 then
    modules.game_textmessage.displayFailureMessage(tr('No item selected!'))
    return true
  end

  local food = getSpecialFoodSlotConfig(category, index)
  if not food then return true end

  food.id = itemId
  refreshSpecialFoodRow(category, index)
  saveSettings()
end

function assignSpecialFoodEvent(category, index)
  if not mouseGrabberWidget then return end
  specialFoodAssignActive = true
  mouseGrabberWidget:grabMouse()
  if specialFoodsWindow then specialFoodsWindow:hide() end
  g_mouse.pushCursor('target')
  mouseGrabberWidget.onMouseRelease = function(self, mousePosition, mouseButton)
    onAssignSpecialFood(self, mousePosition, mouseButton, category, index)
  end
end

local function buildSpecialFoodRows(category)
  local meta = SPECIAL_FOOD_CATEGORIES[category]
  if not meta or not specialFoodsWindow then return end

  local rows = specialFoodsWindow:recursiveGetChildById(meta.rowsId)
  if not rows then return end
  rows:destroyChildren()

  for index = 1, SPECIAL_FOOD_SLOTS do
    local row = g_ui.createWidget('SpecialFoodRow', rows)
    row:setId(category .. "FoodRow" .. index)

    local slot = row:getChildById('slot')
    if slot then
      slot.onMousePress = function(self, mousePos, mouseButton)
        if mouseButton ~= MouseRightButton then return false end
        local menu = g_ui.createWidget('PopupMenu')
        menu:setGameMenu(true)
        local food = getSpecialFoodSlotConfig(category, index)
        if food and food.id and food.id ~= 0 then
          menu:addOption(tr('Change Item'), function() assignSpecialFoodEvent(category, index) end)
          menu:addOption(tr('Remove'), function() removeSpecialFood(category, index) end)
        else
          menu:addOption(tr('Assign Item'), function() assignSpecialFoodEvent(category, index) end)
        end
        menu:display(mousePos)
        return true
      end
    end

    local checkbox = row:getChildById('enable')
    if checkbox then
      checkbox.onCheckChange = function(self)
        toggleSpecialFood(category, index, self:isChecked())
      end
    end

    local rmvPercent = row:getChildById('rmvPercent')
    if rmvPercent then
      g_mouse.bindAutoPress(rmvPercent, function() updateSpecialFoodPercent(category, index, -1) end, 150)
    end
    local addPercent = row:getChildById('addPercent')
    if addPercent then
      g_mouse.bindAutoPress(addPercent, function() updateSpecialFoodPercent(category, index, 1) end, 150)
    end
    local rmvPriority = row:getChildById('rmvPriority')
    if rmvPriority then
      g_mouse.bindAutoPress(rmvPriority, function() updateSpecialFoodPriority(category, index, -1) end, 150)
    end
    local addPriority = row:getChildById('addPriority')
    if addPriority then
      g_mouse.bindAutoPress(addPriority, function() updateSpecialFoodPriority(category, index, 1) end, 150)
    end

    refreshSpecialFoodRow(category, index)
  end
end

local function initSpecialFoodsWindow()
  if not specialFoodsWindow or not helperConfig then return end
  buildSpecialFoodRows("hp")
  buildSpecialFoodRows("mana")
end

modules.game_helper.specialFoodsOpen = function()
  if specialFoodsWindow then
    specialFoodsWindow:destroy()
    specialFoodsWindow = nil
  end

  specialFoodsWindow = g_ui.createWidget('SpecialFoodsWindow', g_ui.getRootWidget())
  initSpecialFoodsWindow()
end

modules.game_helper.specialFoodsClose = function()
  if specialFoodsWindow then
    -- The grabber would stay active if the window is closed mid-assignment.
    if specialFoodAssignActive and mouseGrabberWidget then
      specialFoodAssignActive = false
      mouseGrabberWidget:ungrabMouse()
      mouseGrabberWidget.onMouseRelease = nil
      g_mouse.popCursor('target')
    end
    specialFoodsWindow:destroy()
    specialFoodsWindow = nil
  end
end

modules.game_helper.updateSpecialFoodPriority = updateSpecialFoodPriority

function destroySpecialFoodsWindow()
  modules.game_helper.specialFoodsClose()
end

-- Verifica se uma food específica está em cooldown (local + servidor)
function isSpecialFoodOnCooldown(foodId)
  -- 1. Cooldown local (definido imediatamente ao usar a food)
  local localExpires = specialFoodLocalCooldowns[foodId]
  if localExpires and g_clock.millis() < localExpires then
    return true
  end
  -- 2. Cooldown do servidor (via TimersAnalyser/sendActiveTimers)
  if TimersAnalyser and TimersAnalyser.timers then
    for _, timer in ipairs(TimersAnalyser.timers) do
      if timer.keyType == 1 and timer.key == foodId and timer.category == 3 then
        local elapsed = os.time() - (timer.receivedAt or 0)
        local remaining = (timer.remaining or 0) - elapsed
        if remaining > 0 then return true end
      end
    end
  end
  return false
end

-- ===== END SPECIAL FOODS =====

local function setHelperEnabled(enabled, source, loadConfig)
  local requestedEnabled = enabled and true or false
  helperDebug("setHelperEnabled source=" .. tostring(source) ..
    " enabled=" .. tostring(requestedEnabled) ..
    " loadConfig=" .. tostring(loadConfig))


  if loadConfig then
    loadSettings()
    if healingPanel and toolsPanel then
      _Helper._suppressMessages = true
      onLoadHelperData()
      _Helper._suppressMessages = false
      helperDebug("setHelperEnabled loaded saved helper data")
    else
      helperDebug("setHelperEnabled skipped onLoadHelperData panelsReady=" ..
        tostring(healingPanel ~= nil and toolsPanel ~= nil))
    end
  end

  helperAutomaticFunctionsEnabled = requestedEnabled
  if helperConfig then
    helperConfig.helperAutomaticFunctionsEnabled = helperAutomaticFunctionsEnabled
  end

  if helper then
    botStatus()
  end

  if _Helper.Shortcut and _Helper.Shortcut.syncButton then
    _Helper.Shortcut.syncButton('shortcutHelper', helperAutomaticFunctionsEnabled)
  end

  if saveSettings then
    saveSettings()
  end

end

function toggleHelperStatusButton()
  helperDebug("helper status button clicked current=" .. tostring(helperAutomaticFunctionsEnabled))
  setHelperEnabled(not helperAutomaticFunctionsEnabled, "button", true)
  if modules.game_textmessage and modules.game_textmessage.displayGameMessage then
    modules.game_textmessage.displayGameMessage("Helper toggled + Config LOADED!")
  end
end

function toggleCavebotFromButton()
  local cavebotModule = modules.game_helper and modules.game_helper.cavebot
  if not cavebotModule or not cavebotModule.toggle then
    helperDebug("cavebot button clicked but cavebot module is missing")
    return
  end

  local enabled = cavebotModule.isEnabled and cavebotModule.isEnabled() or false
  helperDebug("cavebot button clicked current=" .. tostring(enabled) .. " next=" .. tostring(not enabled))
  cavebotModule.toggle(not enabled)
end

function botStatus()
  local contentPanel = getHelperContentPanel()
  if not contentPanel then
    helperDebug("botStatus skipped: content panel missing")
    return
  end

  local helperStatus = contentPanel:recursiveGetChildById("helperStatus")
  local helperStatusLabel = contentPanel:recursiveGetChildById("helperStatusLabel")
  local setKeyButton = contentPanel:recursiveGetChildById("setKeyHelperButton")

  if not helperStatusLabel then
    helperDebug("botStatus skipped: helperStatusLabel missing")
    return
  end

  -- VISUAL STATUS
  if helperProfile then
    local status = helperProfile:recursiveGetChildById('profileStatus')
    status:setText(tr('Helper: %s', helperAutomaticFunctionsEnabled and tr('Enabled') or tr('Disabled')))
    status:setColor(helperAutomaticFunctionsEnabled and '#3acb3a' or '#d94a3a')
  end
  if helperAutomaticFunctionsEnabled then
    if helperStatus then
      helperStatus:setImageSource("/images/ui/icon-yes")
      helperStatus:setTooltip("Enabled - Click to DISABLE auto functions OR LOAD config")
    end
    helperStatusLabel:setText("Enabled")
    helperStatusLabel:setColor("#3acb3a")
    if setKeyButton then
      setKeyButton:setText("On")
      setKeyButton:setColor("#3acb3a")
    end
  else
    if helperStatus then
      helperStatus:setImageSource("/images/ui/icon-no")
      helperStatus:setTooltip("Disabled - Click to ENABLE auto functions OR LOAD config")
    end
    helperStatusLabel:setText("Disabled")
    helperStatusLabel:setColor("#d94a3a")
    if setKeyButton then
      setKeyButton:setText("Off")
      setKeyButton:setColor("#d94a3a")
    end
  end

  -- helperStatus = Toggle + Load Config
  if helperStatus and not helperStatus.clickHandlerSetup then
    helperStatus.onClick = function()
      toggleHelperStatusButton()
    end
    helperStatus.clickHandlerSetup = true
  end
end

function toggleNextWindow()
  local widgetList = {
    "healingMenu",
    "toolsMenu",
    "shooterMenu",
    "equipMenu",
    "cavebotMenu",
    "timerMenu",
  }

  local selectedIndex = nil
  for i, widget in ipairs(widgetList) do
    if widget == menuId then
      selectedIndex = i
      break
    end
  end

  if not selectedIndex then
    selectedIndex = 1
  end

  local nextWidgetId = (selectedIndex == #widgetList and 1 or selectedIndex + 1)
  menuId = widgetList[nextWidgetId]
  loadMenu(menuId)
end

function toggleHelperFunctions()
  helperDebug("toggleHelperFunctions called current=" .. tostring(helperAutomaticFunctionsEnabled))
  setHelperEnabled(not helperAutomaticFunctionsEnabled, "hotkey", false)
end

function manageHotkeys(typo)
  _Helper.HotkeyManager.manageHotkeys(typo)
end

function onDropSpell(widget, spellWords)
  local spellData = Spells.getSpellDataByWords(spellWords)
  if not spellData then
    return
  end

  local isHealingPanel = string.match(widget:getId(), "^spellButton%d*")
  local isTrainingPanel = string.match(widget:getId(), "^spellTrainingButton")
  local isHastePanel = string.match(widget:getId(), "^hasteButton")
  local isAttackPanel = string.match(widget:getId(), "^attackSpellButton%d*")
  local profile = getShooterProfile()

  if isHealingPanel then
    onSetupDropSpell(widget, spellData, { 2 }, helperConfig.spells)
  elseif isTrainingPanel or isHastePanel then
    onSetupDropSupport(widget, spellData, isHastePanel)
  elseif isAttackPanel then
    onSetupDropSpell(widget, spellData, { 1, 4, 8 }, profile.spells)
  end
end

function onSetupDropSpell(button, spellData, groups, tableToAssign)
  local groupIds = Spells.getGroupIds(spellData)
  local playerVocation = player:getVocation()
  local profile = getShooterProfile()

  if containsAnyGroup(groupIds, groups) and table.contains(spellData.vocations, playerVocation) and not HelperSpellData.getIgnoredSpellsIds()[spellData.id] then
    local spell = Spells.getSpellDataById(spellData.id)
    _Helper.setSpellIcon(button, spellData.id)
    button:setBorderColorTop("#1b1b1b")
    button:setBorderColorLeft("#1b1b1b")
    button:setBorderColorRight("#757575")
    button:setBorderColorBottom("#757575")
    button:setBorderWidth(1)
    button:setTooltip("Spell: " .. spellData.name .. "\nWords: " .. spellData.words)

    local slotID = tonumber(button:getId():match("%d+"))
    if button:getId():find("attackSpellButton") then
      profile.spells[slotID + 1].id = tonumber(spellData.id)
    else
      tableToAssign[slotID + 1].id = tonumber(spellData.id)
    end

    if button:getId():find("attackSpellButton") then
      local creaturesMin = shooterPanel:recursiveGetChildById("countMinCreature" .. slotID)
      local forceCast = shooterPanel:recursiveGetChildById("conditionSetting" .. slotID)
      local selfCast = shooterPanel:recursiveGetChildById("selfCast" .. slotID)
      if table.contains(bothCastTypeSpells, spell.id) then -- divine grenade self cast
        if not selfCast then
          selfCast = g_ui.createWidget('CheckBox', creaturesMin:getParent())
          local style = {
            ["width"] = 12,
            ["anchors.top"] = "countMinCreature" .. slotID .. ".top",
            ["anchors.left"] = "countMinCreature" .. slotID .. ".right",
            ["margin-top"] = 6,
            ["margin-left"] = 5
          }
          selfCast:mergeStyle(style)
          selfCast:setId('selfCast' .. slotID)
          selfCast:setTooltip('Cast On Foot')
          selfCast:setVisible(true)
          selfCast.onCheckChange = function() toggleSelfCast(selfCast:getId():match("%d+"), selfCast:isChecked()) end
        end
      end

      if selfCast and not table.contains(bothCastTypeSpells, spell.id) then
        profile.spells[slotID + 1].selfCast = false
        selfCast:destroy()
      end

      if (spell.range > 0 or not spell.area) and not table.contains(bothCastTypeSpells, spell.id) then
        profile.spells[slotID + 1].creatures = 1
        creaturesMin:setCurrentOption("1+")
        creaturesMin:disable()
        if forceCast then
          forceCast:setChecked(profile.spells[slotID + 1].forceCast)
          forceCast:setVisible(true)
        end
      else
        creaturesMin:enable()
        if forceCast then
          forceCast:setChecked(false)
          forceCast:setVisible(false)
          profile.spells[slotID + 1].forceCast = false
        end
      end
    end

    -- Persist configuration after assignment
    saveSettings()
  end
end

function onSetupDropSupport(widget, spellData, hasteSpell)
  local playerVocation = translateVocation(player:getVocation())
  local hasteWhiteList = HelperSpellData.getHasteWhiteList()
  local trainingHealSpellsSet = HelperSpellData.getTrainingHealSpellsSet()
  local allowedTrainingSpells = trainingHealSpellsSet[playerVocation] or {}

  if hasteSpell and not table.contains(hasteWhiteList[playerVocation] or {}, spellData.id) then
    return
  end

  if not hasteSpell and not allowedTrainingSpells[spellData.id] then
    return
  end

  if allowedTrainingSpells[spellData.id] or table.contains(hasteWhiteList[playerVocation] or {}, spellData.id) then
    _Helper.setSpellIcon(widget, spellData.id)
    widget:setBorderColorTop("#1b1b1b")
    widget:setBorderColorLeft("#1b1b1b")
    widget:setBorderColorRight("#757575")
    widget:setBorderColorBottom("#757575")
    widget:setBorderWidth(1)
    widget:setTooltip("Spell: " .. spellData.name .. "\nWords: " .. spellData.words)

    local slotID = tonumber(widget:getId():match("%d+"))
    if hasteSpell then
      -- Usa o modulo AutoHaste para configurar
      local helperConfigLocal = _Helper.getHelperConfig and _Helper.getHelperConfig() or helperConfig
      helperConfigLocal.haste[1].id = tonumber(spellData.id)
    else
      helperConfig.training[1].id = tonumber(spellData.id)
      if helperConfig.training[1].percent == 0 then
        helperConfig.training[1].percent = 100
        updateTrainingPercent('spellTrainingButton0', helperConfig.training[1].percent)
      end
    end
  end
end

function onSearchTextChange(text, window)
  local spellList = window:recursiveGetChildById('spellList')
  for _, child in pairs(spellList:getChildren()) do
    local name = child:getText():lower()
    if name:find(text:lower()) or text == '' or #text < 3 then
      child:setVisible(true)
    else
      child:setVisible(false)
    end
  end
end

function onClearSearchText(window)
  local search = window:recursiveGetChildById('searchText')
  search:setText('')
end

function unregisterAllHelperHotkeys()
  _Helper.HotkeyManager.unregisterAll()
end

function registerSavedHotkeys()
  _Helper.HotkeyManager.registerAll()
end
