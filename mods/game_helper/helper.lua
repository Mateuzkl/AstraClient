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

  if not g_sounds.playAlarm then
    g_sounds.playAlarm = function(file)
      local channel = getAlarmChannel()
      if channel then
        if channel.setEnabled then
          channel:setEnabled(true)
        end
        if channel.stop then
          channel:stop(0)
        end
        if channel.play then
          return channel:play(file, 0, 1.0)
        end
      end

      if g_sounds.play then
        return g_sounds.play(file, 0, 1.0)
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
local equipPanelContainer = nil
local cavebotPanel = nil
local timerPanelContainer = nil
local mouseGrabberWidget = nil
local helper = nil
local helperRules = nil
local hotkeyHelperStatus = false
local atcHelperWidget = nil
local afkTime = 180
local helperAutomaticFunctionsEnabled = true
local lastActiveMenu = 'healingMenu'
local isTransitioningPlayer = false

-- fallback for LoadedPlayer when not provided by server-side module
if not LoadedPlayer then
  LoadedPlayer = g_game.getLocalPlayer()
end

-- fallback for translateVocation
if not translateVocation then
  function translateVocation(id)
    -- Vocation translation mapping client IDs to server IDs
    -- Based on game_actionbar/logics/const.lua and gamelib/creature.lua
    -- Client: Knight=1, Paladin=2, Sorcerer=3, Druid=4, Monk=5, EliteKnight=11, RoyalPaladin=12, MasterSorcerer=13, ElderDruid=14, ExaltedMonk=15
    -- Server: Sorcerer=1, Druid=2, Paladin=3, Knight=4, MasterSorcerer=5, ElderDruid=6, RoyalPaladin=7, EliteKnight=8, Monk=9, ExaltedMonk=10
    if id == 1 or id == 11 then     -- Knight or Elite Knight
      return 8                      -- Elite Knight
    elseif id == 2 or id == 12 then -- Paladin or Royal Paladin
      return 7                      -- Royal Paladin
    elseif id == 3 or id == 13 then -- Sorcerer or Master Sorcerer
      return 5                      -- Master Sorcerer
    elseif id == 4 or id == 14 then -- Druid or Elder Druid
      return 6                      -- Elder Druid
    elseif id == 5 or id == 15 then -- Monk or Exalted Monk
      return 10                     -- Exalted Monk
    end
    return 0
  end
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

-- Helper function to get spell icon clip using spell.id and iconIndex from SpellInfo.Default
-- This is the centralized function that all modules should use for spell icons
-- @param spellId: The spell ID (spell.id from SpellInfo.Default)
-- @param profile: Optional profile name (default: 'Default')
-- @return: Icon clip string in format "x y width height"
_Helper.getSpellIconClip = function(spellId, profile)
  if not spellId then
    return "0 0 32 32"
  end
  if Spells and Spells.getImageClip then
    local success, clip = pcall(function() return Spells.getImageClip(spellId, profile or 'Default') end)
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
  if SpelllistSettings and SpelllistSettings[profile] and SpelllistSettings[profile].iconFile then
    return SpelllistSettings[profile].iconFile
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

-- Server to Client Vocation Mapping
local ServerToClientVocationMap = {
  [1] = { 4, 8 },
  [11] = { 4, 8 },  -- Knight
  [2] = { 3, 7 },
  [12] = { 3, 7 },  -- Paladin
  [3] = { 1, 5 },
  [13] = { 1, 5 },  -- Sorcerer
  [4] = { 2, 6 },
  [14] = { 2, 6 },  -- Druid
  [5] = { 9, 10 },
  [15] = { 9, 10 }, -- Monk
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
local potionTurnCooldown = 0         -- turn system: blocks next potion to give rune a turn

local auxiliadorPreCooldown = 200
local specialFoodsWindow = nil

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
  checkMagicShield = 0
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
  checkExerciseEvent = { interval = 10000, action = nil },
  updatePartyHealth = { interval = 50, action = nil },
  checkEquipItems = { interval = 50, action = nil },    -- Check and equip rings/amulets based on health
  checkQuiverRefill = { interval = 500, action = nil }, -- Check and refill quiver for paladins
  checkMagicShield = { interval = 50, action = nil }    -- Check and manage magic shield for mages
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
    if success and spells then
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

  shooterProfiles = {
    ["Default"] = defaultShooterProfile
  },
  selectedShooterProfile = "Default",

  equipProfiles = {
    ["Default"] = { rules = {}, enabled = true }
  },
  selectedEquipProfile = "Default",

  terms = false,
  autoEatFood = false,
  autoReconnect = false,
  autoChangeGold = false,
  magicShooterEnabled = false,
  magicShooterOnHold = false,
  disableInProtectZone = true,
  autoTargetEnabled = false,
  autoTargetMode = autoTargetModes['F'],
  currentLockedTargetId = 0,
  hotkeyCode = nil,          -- Armazena o código da hotkey
  hotkeyFunc = nil,          -- Armazena a função da hotkey
  presetHotkeyEnabled = true,
  recordingHotkeyCode = nil, -- Armazena o código da hotkey de recording
  recordingHotkeyFunc = nil, -- Armazena a função da hotkey de recording

  specialFoods = {
    hp = {
      { id = 11586, enabled = false, percent = 80, priority = 1 },
      { id = 9079,  enabled = false, percent = 80, priority = 2 },
      { id = 29414, enabled = false, percent = 80, priority = 3 },
      { id = 28485, enabled = false, percent = 80, priority = 4 },
    },
    mana = {
      { id = 29415, enabled = false, percent = 60, priority = 1 },
      { id = 28484, enabled = false, percent = 60, priority = 2 },
      { id = 9086,  enabled = false, percent = 60, priority = 3 },
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
-- Servidor envia: Knight(1,11), Paladin(2,12), Sorcerer(3,13), Druid(4,14), Monk(5,15)
-- Cliente usa: Sorcerer {1,5}, Druid {2,6}, Paladin {3,7}, Knight {4,8}, Monk {9,10}
local ServerToClientVocationMap = {
  [1] = { 4, 8 },
  [11] = { 4, 8 },  -- Knight
  [2] = { 3, 7 },
  [12] = { 3, 7 },  -- Paladin
  [3] = { 1, 5 },
  [13] = { 1, 5 },  -- Sorcerer
  [4] = { 2, 6 },
  [14] = { 2, 6 },  -- Druid
  [5] = { 9, 10 },
  [15] = { 9, 10 }, -- Monk
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




function init()
  -- Carregar dados de spells do JSON (uma única vez)
  if not HelperSpellData.load() then
    g_logger.warning("[game_helper] Failed to load spell data from JSON, using fallback")
  end

  local success, err = pcall(function()
    if LocalPlayer then
      connect(LocalPlayer, {
        onPartyMembersChange = onPartyMembersChange,
        onHealthChange = onPlayerHealthChange,
        onManaChange = onPlayerManaChange,
        onStatesChange = onPlayerStatesChange,
        onPositionChange = _Helper.SmartFollow.onLocalPlayerPositionChange,
        onVocationChange = function()
          scheduleEvent(function()
            if g_game.isOnline() then
              online()
            end
          end, 100)
        end,
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

    -- SmartFollow: escuta onPositionChange de TODAS as criaturas para detectar mudanca de andar do target
    if Creature then
      connect(Creature, {
        onPositionChange = _Helper.SmartFollow.onCreaturePositionChange,
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

  -- Registrar opcode do BotCheck alarm FORA do pcall dos connects
  -- para garantir que o alarme funcione mesmo se algum connect falhar
  local botCheckOk, botCheckErr = pcall(function()
    _Helper.BotCheckAlarm.register()
  end)
  if not botCheckOk then
    safeLog("error", string.format("Helper: init() - Error registering BotCheck alarm: %s", tostring(botCheckErr)))
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
    g_ui.importStyle('styles/atchelper')
    helper = g_ui.loadUI('helper_window', g_ui.getRootWidget())
    if helper then
      _Helper.HotkeyManager.setHelperWidget(helper)
      safeLog("debug", "Helper: init() - Helper window created")
    else
      safeLog("error", "Helper: init() - Failed to create helper window")
    end
  end)

  if not success then
    safeLog("error", string.format("Helper: init() - Error creating UI: %s", tostring(err)))
  end

  success, err = pcall(function()
    local rootWidget = g_ui.getRootWidget()
    helperRules = g_ui.createWidget('HelperRules', rootWidget)
    if helperRules then
      helperRules:hide()
    end
  end)

  if not success then
    safeLog("error", string.format("Helper: init() - Error creating rules: %s", tostring(err)))
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
      toolsPanel = toolsPanelContainer:getChildById('toolsPanel') or toolsPanelContainer:recursiveGetChildById('toolsPanel')
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
      friendHealingPanel = healingPanel:recursiveGetChildById("friendHealingPanel")
      granSioPanel = healingPanel:recursiveGetChildById("granSioPanel")
      masResPanel = healingPanel:recursiveGetChildById("masResPanel")
      healingTargetModePanel = healingPanel:recursiveGetChildById("healingTargetModePanel")

      -- Setup UIRadioGroup para Screen/Party toggle
      if healingTargetModePanel then
        healingTargetModeRadio = UIRadioGroup.create()
        local screenBtn = healingTargetModePanel:recursiveGetChildById("targetModeScreen")
        local partyBtn = healingTargetModePanel:recursiveGetChildById("targetModeParty")
        if screenBtn and partyBtn then
          healingTargetModeRadio:addWidget(screenBtn)
          healingTargetModeRadio:addWidget(partyBtn)
          healingTargetModeRadio.onSelectionChange = function(self, selected)
            if selected then
              local mode = (selected:getId() == "targetModeScreen") and "screen" or "party"
              helperConfig.healingTargetMode = mode
            end
          end
          -- Selecionar baseado na config salva
          local mode = helperConfig.healingTargetMode or "party"
          if mode == "screen" then
            healingTargetModeRadio:selectWidget(screenBtn)
          else
            healingTargetModeRadio:selectWidget(partyBtn)
          end
        end
      end
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
            _G.scheduleEvent(retryAttempt, delay)
          end
        end
        _G.scheduleEvent(retryAttempt, 300)
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
      _G.scheduleEvent(monitorGameState, 1000)
    end
    _G.scheduleEvent(monitorGameState, 2000)
  end)

  if not success then
    safeLog("error", string.format("Helper: init() - Error checking online status: %s", tostring(err)))
  end

  --  safeLog("info", "Helper: init() - Initialization complete")

  -- Funções de teste removidas - não estão definidas

  -- Configurações são carregadas por personagem em loadSettings() quando o jogador faz login
end

function terminate()
  if LocalPlayer then
    disconnect(LocalPlayer, {
      onPartyMembersChange = onPartyMembersChange,
      onHealthChange = onPlayerHealthChange,
      onManaChange = onPlayerManaChange,
      onStatesChange = onPlayerStatesChange,
      onPositionChange = _Helper.SmartFollow.onLocalPlayerPositionChange,
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

  -- SmartFollow: desconectar onPositionChange de Creature
  if Creature then
    disconnect(Creature, {
      onPositionChange = _Helper.SmartFollow.onCreaturePositionChange,
    })
  end

  -- Desregistrar opcode do BotCheck alarm
  _Helper.BotCheckAlarm.unregister()

  if helper then
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

  if helperRules then
    helperRules:destroy()
    helperRules = nil
  end

  destroyATCHelperWidget()

  if modules.game_helper and modules.game_helper.equip and modules.game_helper.equip.terminate then
    modules.game_helper.equip.terminate()
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
    toolsPanel = toolsPanelContainer:getChildById('toolsPanel') or toolsPanelContainer:recursiveGetChildById('toolsPanel')
  end
  if healingPanel then
    healPanel = healPanel or healingPanel.healingPanel or healingPanel:recursiveGetChildById('healingPanel')
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

  return contentPanel
end

local helperMenuIds = {
  'healingMenu',
  'toolsMenu',
  'shooterMenu',
  'equipMenu',
  'cavebotMenu',
  'timerMenu'
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
  if helper then
    helper:setSize(tosize("329 309"))
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
    timerPanelContainer
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

local function ensureHelperRules()
  if helperRules then
    return helperRules
  end

  local rootWidget = g_ui.getRootWidget()
  if not rootWidget then
    return nil
  end

  helperRules = g_ui.createWidget('HelperRules', rootWidget)
  if helperRules then
    helperRules:hide()
  end

  return helperRules
end

function showTerms()
  if helperConfig and helperConfig.terms then
    show()
    return
  end

  local rulesWindow = ensureHelperRules()
  if not rulesWindow then
    show()
    return
  end

  createHelperRules()
  rulesWindow:show()
  rulesWindow:raise()
  rulesWindow:focus()
end

function closeTerms()
  if helperRules then
    helperRules:hide()
  end
end

function createHelperRules()
  local rulesWindow = ensureHelperRules()
  if not rulesWindow then
    return
  end

  local nextButton = rulesWindow:recursiveGetChildById('next')
  if nextButton then
    nextButton:setEnabled(true)
  end

  local termsCheckbox = rulesWindow:recursiveGetChildById('termCondition')
  if termsCheckbox then
    termsCheckbox:setChecked(false)
  end

  local longText = "\n           Extended Terms and Conditions for Helper Services\n\n" ..
                   " These Terms of Service establish the conditions under which D FATO GAMES LTDA provides 'Helper' and related services for the online RPG game 'Astra'. This document complements the Astra Service Agreement accepted by every user when creating an account.\n\n" ..
                   "2 - Cheating\n\n" ..
                   "2.H - Automations in ATC.\n If the player is using the ATC client and helper automation features to attack monsters and/or cast spells, they may undergo a standard check by our team. If player absence is confirmed, the player and account may be banned."

  local rulesText = rulesWindow:recursiveGetChildById('rulesText')
  if rulesText then
    rulesText:setText(longText)
  end
end

function onHelperTermCondition(widgetId, value)
  if not helperRules then
    return
  end

  local nextButton = helperRules:recursiveGetChildById('next')
  if nextButton then
    nextButton:setEnabled(true)
  end
end

function onHelperTermConditionNext()
  if helperRules then
    helperRules:hide()
  end

  if helperConfig then
    helperConfig.terms = true
  end
  if saveSettings then
    pcall(saveSettings)
  end

  show()
end

function hasAcceptedTerms()
  return helperConfig and helperConfig.terms or false
end

function onATCHelperClick()
  toggle()
end

local function getATCHelperPanel()
  local gameInterface = modules.game_interface or m_interface
  if not gameInterface then
    return nil
  end

  if gameInterface.getMainRightPanel then
    return gameInterface.getMainRightPanel()
  end

  if gameInterface.getRightPanel then
    return gameInterface.getRightPanel()
  end

  return nil
end

function createATCHelperWidget()
  -- Evitar criar duplicado
  if atcHelperWidget then
    return
  end

  local mainRightPanel = getATCHelperPanel()
  if not mainRightPanel then
    return
  end

  atcHelperWidget = g_ui.createWidget('ATCHelperWidget')
  if not atcHelperWidget then
    return
  end

  local insertIndex = 1
  local children = mainRightPanel:getChildren()
  for i, child in ipairs(children) do
    if child:getId() == 'minimapWindow' then
      insertIndex = i + 1
      break
    end
  end

  mainRightPanel:insertChild(insertIndex, atcHelperWidget)

  if mainRightPanel.fitAllChildren then
    mainRightPanel:fitAllChildren()
  end
end

function destroyATCHelperWidget()
  if atcHelperWidget then
    atcHelperWidget:destroy()
    atcHelperWidget = nil
  end
end

function repositionATCHelperBelowMinimap()
  if not atcHelperWidget then
    return
  end

  local mainRightPanel = getATCHelperPanel()
  if not mainRightPanel then
    return
  end

  mainRightPanel:removeChild(atcHelperWidget)

  local insertIndex = 1
  local children = mainRightPanel:getChildren()
  for i, child in ipairs(children) do
    if child:getId() == 'minimapWindow' then
      insertIndex = i + 1
      break
    end
  end

  mainRightPanel:insertChild(insertIndex, atcHelperWidget)

  if mainRightPanel.fitAllChildren then
    mainRightPanel:fitAllChildren()
  end
end

function getATCHelperWidget()
  return atcHelperWidget
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
    timers[eventName] = timers[eventName] + helperEvents.helperCycleTimer
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

  -- Criar ATCHelper widget no painel direito
  scheduleEvent(function()
    if g_game.isOnline() then
      createATCHelperWidget()
    end
  end, 100)

  -- Iniciar Timer se necessario
  scheduleEvent(function()
    if g_game.isOnline() and _Helper.Timer and _Helper.Timer.onLogin then
      _Helper.Timer.onLogin()
    end
  end, 1700)
end

function offline()
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

  -- Parar Smart Follow
  if _Helper.SmartFollow and _Helper.SmartFollow.onLogout then
    _Helper.SmartFollow.onLogout()
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

  -- Reset botcheck alarm on logout
  _Helper.BotCheckAlarm.resetCheckbox()

  -- Fechar special foods window
  destroySpecialFoodsWindow()

  -- Remover hotkeys antes de deslogar (serão re-registradas no próximo online())
  unregisterAllHelperHotkeys()

  -- Salvar antes de deslogar
  saveSettings()

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

  -- Destruir ATCHelper widget ao deslogar
  destroyATCHelperWidget()

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

_Helper.getShooterPanel = function()
  return shooterPanel
end

_Helper.isHelperAutomaticFunctionsEnabled = function()
  return helperAutomaticFunctionsEnabled
end

_Helper.setHelperAutomaticFunctionsEnabled = function(value)
  helperAutomaticFunctionsEnabled = value and true or false
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

    if helperConfig and helperConfig.disableInProtectZone then
      -- Case A1: Permanently disable both systems (updates UI and config)
      pzDisableSystem("autoTarget", true)
      pzDisableSystem("magicShooter", true)
      if saveSettings then
        saveSettings()
      end
    else
      -- Case A2: Just record which systems were enabled for restore notification
      -- DO NOT modify enabled flags - the PZ guard will block actions
      pzState.wasAutoTargetEnabled = helperConfig and helperConfig.autoTargetEnabled or false
      pzState.wasMagicShooterEnabled = helperConfig and helperConfig.magicShooterEnabled or false
      if pzState.wasAutoTargetEnabled then
        pzSuspendSystem("autoTarget")
      end
      if pzState.wasMagicShooterEnabled then
        pzSuspendSystem("magicShooter")
      end
    end
  end

  -- Detect PZ exit (edge: in PZ -> not in PZ)
  if not inPZ and wasInPZ then
    pzState.wasInPZ = false

    -- Only show restore message if disableInProtectZone is false (Case A2)
    -- and the system is still enabled (user didn't manually disable while in PZ)
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
    timerMenu = "timerMenu"
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

  local currentPlayer = g_game.getLocalPlayer()
  if not currentPlayer then
    -- If no player, just show default layout
    if healingPanel and toolsPanelContainer and shooterPanel then
      healingPanel:show(true)
      toolsPanelContainer:hide()
      shooterPanel:hide()
      if equipPanelContainer then equipPanelContainer:hide() end
      if cavebotPanel then cavebotPanel:hide() end
      if timerPanelContainer then timerPanelContainer:hide() end
      helper:setSize(tosize("329 240"))
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
    if currentPlayer:isKnight() then
      helper:setSize(tosize("329 309"))
      healPanel:setHeight(160)
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
      helper:setSize(tosize("329 309"))
      if healingTargetModePanel then healingTargetModePanel:setVisible(false) end
      friendHealingPanel:setVisible(false)
      granSioPanel:setVisible(false)
      if masResPanel then masResPanel:setVisible(false) end
      healPanel:setHeight(160)
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
      helper:setSize(tosize("329 465"))
      healPanel:setHeight(120)
      if healingTargetModePanel then healingTargetModePanel:setVisible(true) end
      friendHealingPanel:setVisible(true)
      local friendTitleLabel = friendHealingPanel:recursiveGetChildById("friendTitle")
      if friendTitleLabel then friendTitleLabel:setText("Ultimate Healing Rune Helper") end
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
      helper:setSize(tosize("329 762"))
      healPanel:setHeight(120)
      if healingTargetModePanel then healingTargetModePanel:setVisible(true) end
      friendHealingPanel:setVisible(true)
      local friendTitleLabel = friendHealingPanel:recursiveGetChildById("friendTitle")
      if friendTitleLabel then friendTitleLabel:setText("Heal Friend Helper") end
      granSioPanel:setVisible(true)
      if masResPanel then masResPanel:setVisible(true) end
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
      helper:setSize(tosize("329 507"))
      healPanel:setHeight(160)
      if healingTargetModePanel then healingTargetModePanel:setVisible(true) end
      friendHealingPanel:setVisible(true)
      local friendTitleLabel = friendHealingPanel:recursiveGetChildById("friendTitle")
      if friendTitleLabel then friendTitleLabel:setText("Restore Balance Helper") end
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
      helper:setSize(tosize("329 271"))
      healPanel:setHeight(120)
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
  elseif menuId == 'toolsMenu' then
    healingPanel:hide()
    shooterPanel:hide()
    if equipPanelContainer then equipPanelContainer:hide() end
    if cavebotPanel then cavebotPanel:hide() end
    if timerPanelContainer then timerPanelContainer:hide() end
    if toolsPanelContainer then toolsPanelContainer:show(true) end

    -- Update vocation-specific panels visibility
    if modules.game_helper and modules.game_helper.tools and modules.game_helper.tools.updateVocationPanels then
      modules.game_helper.tools.updateVocationPanels()
    end

    -- Adjust window size based on vocation panels
    local baseHeight = 275
    local extraHeight = 0
    if currentPlayer then
      local voc = translateVocation(currentPlayer:getVocation())
      if voc == 2 then                 -- Paladin: show quiver refill panel (height 95 + margin 5)
        extraHeight = 100
      elseif voc == 3 or voc == 4 then -- Sorcerer/Druid: show magic shield panel (height 130 + margin 5)
        extraHeight = 135
      end
    end
    helper:setSize(tosize("329 " .. (baseHeight + extraHeight)))
  elseif menuId == 'shooterMenu' then
    healingPanel:hide()
    if toolsPanelContainer then toolsPanelContainer:hide() end
    if equipPanelContainer then equipPanelContainer:hide() end
    if cavebotPanel then cavebotPanel:hide() end
    if timerPanelContainer then timerPanelContainer:hide() end
    shooterPanel:show(true)
    -- New unified magic shooter panel - wider width for better layout
    helper:setSize(tosize("400 600"))
    -- Update rules list when switching to shooter menu
    if modules.game_helper and modules.game_helper.magicShooter then
      modules.game_helper.magicShooter.updateUI()
    end
  elseif menuId == 'equipMenu' then
    helper:setSize(tosize("390 550"))
    healingPanel:hide()
    shooterPanel:hide()
    if toolsPanelContainer then toolsPanelContainer:hide() end
    if equipPanelContainer then
      equipPanelContainer:show(true)
    end
    if cavebotPanel then cavebotPanel:hide() end
    if timerPanelContainer then timerPanelContainer:hide() end
  elseif menuId == 'cavebotMenu' then
    healingPanel:hide()
    shooterPanel:hide()
    if toolsPanelContainer then toolsPanelContainer:hide() end
    if equipPanelContainer then equipPanelContainer:hide() end
    if timerPanelContainer then timerPanelContainer:hide() end
    if cavebotPanel then cavebotPanel:show(true) end
    if cbLabel then cbLabel:show() end
    if cbBtn then cbBtn:show() end
    helper:setSize(tosize("430 550"))
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
    helper:setSize(tosize("400 600"))
  end
end

--[[ Events ]] --
function assignTrainingSpell(button, isHaste)
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

  local windowHeader = isHaste and "Assign Haste Spell" or "Assign Training Spell"
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

    if isHaste then
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
    widget.clip = _Helper.getSpellIconClip(spellData.id)
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
    if isHaste then
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
    widget.clip = _Helper.getSpellIconClip(spellData.id)
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
    widget.clip = _Helper.getSpellIconClip(spellData.id)
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
end

function useAutoSio(target)
  local spellId = 84
  local spell = getSpellByClientId(tonumber(spellId))
  if not spell or spell.id == 0 then
    return false
  end

  if not checkHealthPriority() then
    return
  end

  if (isSpellOnCooldown(spell)) then
    return false
  end

  safeDoThing(false)
  g_game.talk(string.format("%s \"%s\"", spell.words, target:getName()), true)
  safeDoThing(true)
end

function useAutoGranSio(target)
  local spellId = 242
  local spell = getSpellByClientId(spellId)
  if not spell or spell.id == 0 then
    return false
  end

  if not checkHealthPriority() then
    return
  end

  if (isSpellOnCooldown(spell)) then
    return false
  end

  safeDoThing(false)
  g_game.talk(string.format("%s \"%s\"", spell.words, target:getName()), true)
  safeDoThing(true)
end

function useAutoTioSio(target)
  local spellId = 297
  local spell = getSpellByClientId(spellId)
  if not spell or spell.id == 0 then
    return false
  end

  if not checkHealthPriority() then
    return
  end

  if (isSpellOnCooldown(spell)) then
    return false
  end

  safeDoThing(false)
  g_game.talk(string.format("%s \"%s\"", spell.words, target:getName()), true)
  safeDoThing(true)
end

function useAutoMasRes()
  local spellId = 82 -- Mass Healing (exura gran mas res)
  local spell = getSpellByClientId(spellId)
  if not spell or spell.id == 0 then
    return false
  end

  if not checkHealthPriority() then
    return
  end

  if (isSpellOnCooldown(spell)) then
    return false
  end

  safeDoThing(false)
  g_game.talk(spell.words, true)
  safeDoThing(true)
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
    return
  end

  -- UH rune shares object use exhaustion with potions and magic shooter runes
  if multiUseExDelay > g_clock.millis() or (spellsCooldown[potionConfig.id] or 0) > g_clock.millis() then
    return false
  end

  helperConfig.magicShooterOnHold = true

  if hasItemInBackpack(runeId) then
    safeDoThing(false)
    g_game.useInventoryItemWith(runeId, target, 0, true)
    safeDoThing(true)
    -- Set shared cooldown so potions/magic shooter know UH was just used
    local expires = g_clock.millis() + potionConfig.exhaustion
    multiUseExDelay = expires
    spellsCooldown[potionConfig.id] = expires
    lastObjectUseWasRune = true
  end

  helperConfig.magicShooterOnHold = false
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

-- Wrapper function para Smart Follow (OTUI compatibilidade)
function toggleSmartFollow(checked)
  _Helper.SmartFollow.toggle(checked)
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
          if creaturePos and positionCompare(creaturePos, tempPos) and (g_map.isSightClear(casterPos, creaturePos)) then
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

function checkFriendHealing(cachedSpectators)
  if not helperAutomaticFunctionsEnabled then return end
  local localPlayer = g_game.getLocalPlayer()
  if not localPlayer then return end
  local healingMode = helperConfig.healingTargetMode or "party"
  if healingMode == "screen" or localPlayer:isPartyMember() then
    onFriendHealing(localPlayer, cachedSpectators)
  end
end

eventTable.checkFriendHealing.action = checkFriendHealing

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
    useAutoUH(member)
  elseif localPlayer:isMonk() then
    useAutoTioSio(member)
  else
    useAutoSio(member)
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
  local healingMode = helperConfig.healingTargetMode or "party"
  local granSioCandidates = {} -- Nature's Embrace targets
  local friendCandidates = {}  -- Heal Friend targets
  local needMasRes = false     -- Mass Healing flag

  for _, creature in pairs(spectators) do
    if creature and creature:isPlayer() and creature:getId() ~= localPlayerId then
      -- Modo "party": somente membros da party (shield > 0)
      -- Modo "screen": qualquer player visivel na tela
      local isValidTarget = false
      if healingMode == "screen" then
        isValidTarget = true
      else
        local shield = creature:getShield()
        isValidTarget = (shield and shield > 0)
      end
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

  -- 1) Tentar Nature's Embrace primeiro (maior prioridade de magia)
  if #granSioCandidates > 0 then
    table.sort(granSioCandidates, sortByPriorityThenHealth)
    useAutoGranSio(granSioCandidates[1].creature)
    return
  end

  -- 2) Tentar Heal Friend (segunda prioridade / fallback do Nature's Embrace)
  if #friendCandidates > 0 then
    table.sort(friendCandidates, sortByPriorityThenHealth)
    castFriendHealOnMember(localPlayer, friendCandidates[1].creature)
    return
  end

  -- 3) Tentar Mass Healing (menor prioridade - so se alguem estiver no raio)
  if needMasRes then
    useAutoMasRes()
    return
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

  -- Check Mas Res healing (area heal, no target needed)
  local masResCfg = helperConfig.masreshealing and helperConfig.masreshealing[vocKey]
  if masResCfg and masResCfg.enabled and healthPercent <= masResCfg.percent then
    useAutoMasRes()
    return
  end

  -- Check Gran Sio healing
  local granSioCfg = helperConfig.gransiohealing[vocKey]
  if granSioCfg and granSioCfg.enabled and healthPercent <= granSioCfg.percent then
    useAutoGranSio(creature)
    return
  end

  -- Check friend healing (sio/uh/tiosio)
  local friendCfg = helperConfig.friendhealing[vocKey]
  if friendCfg and friendCfg.enabled and healthPercent <= friendCfg.percent then
    castFriendHealOnMember(localPlayer, creature)
    return
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
    if button.potionItem then
      button.potionItem:destroy()
    end
    percent:setText("50%")
  elseif type == "training" then
    _Helper.ManaTraining.removeAction(button)
  elseif type == "haste" then
    _Helper.AutoHaste.removeAction(button)
  elseif type == "exercise" then
    local box = toolsPanel:recursiveGetChildById("autoTrainingItem")
    box:setImageSource("/images/game/actionbar/actionbarslot")
    if button.potionItem then
      button.potionItem:destroy()
    end
  end
  -- Persist configuration after removal
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

  -- Reset auto food checkbox
  _Helper.AutoFood.resetCheckbox()

  -- Reset low capacity alarm
  _Helper.LowCapacityAlarm.resetCheckbox()

  -- Reset low health alarm
  _Helper.LowHealthAlarm.resetCheckbox()

  -- Reset low mana alarm
  _Helper.LowManaAlarm.resetCheckbox()

  -- Reset smart follow checkbox
  _Helper.SmartFollow.resetCheckbox()

  -- Reset auto target checkbox
  _Helper.AutoTarget.resetCheckbox()

  -- Reset other checkboxes
  local reconnect = toolsPanel:recursiveGetChildById("reconnect")
  if reconnect then reconnect:setChecked(false) end

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

  -- Limpar UI antes de carregar novos dados
  resetHelperUI()

  -- Restaurar valores que foram sobrescritos pelo callback
  _Helper.AutoHaste.saveAndRestoreStates(savedHasteEnabled, savedHasteSafecast, savedHasteOnlyWalking)
  _Helper.ManaTraining.saveAndRestoreStates(savedTrainingEnabled)
  helperConfig.autoEatFood = savedAutoEatFood
  helperConfig.autoChangeGold = savedAutoChangeGold
  helperConfig.autoTargetEnabled = savedAutoTargetEnabled
  helperConfig.magicShooterEnabled = savedMagicShooterEnabled

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

  -- Carregar smart follow para UI
  _Helper.SmartFollow.loadToUI()

  -- Carregar auto target para UI
  _Helper.AutoTarget.loadToUI()

  -- Populate presets combobox with saved profiles
  local pm = modules.game_helper and modules.game_helper.presetManager
  if pm then
    local sCtx = pm.getShooterContext()
    if sCtx then pm.loadProfileOptions(sCtx) end
  end

  loadShooterProfileByName(helperConfig.selectedShooterProfile)

  local reconnect = toolsPanel:recursiveGetChildById("reconnect")
  if reconnect then reconnect:setChecked(helperConfig.autoReconnect) end

  local changeGold = toolsPanel:recursiveGetChildById("changeGold")
  if changeGold then changeGold:setChecked(helperConfig.autoChangeGold) end

  -- Carregar paineis de vocação (Exercise Training, Quiver Refill e Magic Shield)
  if modules.game_helper and modules.game_helper.tools then
    modules.game_helper.tools.loadExerciseTrainingToUI()
    modules.game_helper.tools.loadQuiverRefillToUI()
    modules.game_helper.tools.loadMagicShieldToUI()
    modules.game_helper.tools.updateVocationPanels()
  end

  local enableMagicShooter = enableButtons:recursiveGetChildById("enableMagicShooter")
  if enableMagicShooter then enableMagicShooter:setChecked(helperConfig.magicShooterEnabled) end

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

  -- Restaurar UI do Healing Target Mode (Screen/Party)
  if healingTargetModePanel and healingTargetModeRadio then
    local mode = helperConfig.healingTargetMode or "party"
    local screenBtn = healingTargetModePanel:recursiveGetChildById("targetModeScreen")
    local partyBtn = healingTargetModePanel:recursiveGetChildById("targetModeParty")
    if mode == "screen" and screenBtn then
      healingTargetModeRadio:selectWidget(screenBtn)
    elseif partyBtn then
      healingTargetModeRadio:selectWidget(partyBtn)
    end
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
    return
  end

  local currentPlayer = g_game.getLocalPlayer()
  if not currentPlayer then
    return
  end

  local dir    = "/characterdata/" .. currentPlayer:getId()
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

  cleanConfig.shortcutsVisible = _Helper.Shortcut.isVisible()

  local status, result = pcall(function()
    return json.encode(cleanConfig, 2)
  end)
  if not status then
    return
  end

  if result:len() > 100 * 1024 * 1024 then
    return
  end

  -- Safely attempt to write the file
  local writeStatus, writeError = pcall(function()
    return g_resources.writeFileContents(folder, result)
  end)

  if not writeStatus then
    g_logger.debug("Could not save helper settings: " .. tostring(writeError))
  end
end

-- Exportar saveSettings para módulos externos (deve ficar APÓS a definição da função)
_Helper.saveSettings = saveSettings

function saveHelperSettings()
  saveSettings()
  modules.game_textmessage.displayGameMessage("Helper configuration saved successfully!")
end

-- ============================================================================
-- TOOL WARNING WINDOW (Cavebot / Follow)
-- ============================================================================
local activeToolWarning = nil

function showToolWarning(onAcceptCallback, onCancelCallback)
  -- Se o player já marcou "não mostrar novamente", executa direto
  if helperConfig.hideToolWarning then
    helperDebug("tool warning skipped: hideToolWarning=true")
    if onAcceptCallback then onAcceptCallback() end
    return
  end

  -- Se já existe uma janela de aviso aberta, não abre outra
  if activeToolWarning and not activeToolWarning:isDestroyed() then
    helperDebug("tool warning already open")
    return
  end

  local warningWindow = g_ui.createWidget('WarningToolWindow', rootWidget)
  if not warningWindow then
    helperDebug("tool warning failed to create WarningToolWindow")
    if onCancelCallback then onCancelCallback() end
    return
  end

  helperDebug("tool warning opened")
  activeToolWarning = warningWindow

  -- Título
  local titleLabel = warningWindow:getChildById('warningTitle')
  titleLabel:setText('Important Warning')
  titleLabel:setColor('#ffffff')

  -- Conteúdo com cores
  local contentLabel = warningWindow:getChildById('warningContent')
  local warningText =
      "[color=#ffffff]Periodic checks during use.[/color]\n\n" ..
      "If a verification is sent and you " ..
      "[color=#FF4444]do not respond in time[/color], your character will be " ..
      "[color=#FF4444]teleported to prison[/color].\n\n" ..
      "To leave, you must " ..
      "[color=#FFD700]pay bail in gold[/color] or " ..
      "[color=#FFD700]wait 24 hours[/color].\n\n" ..
      "[color=#44DD44]Use this tool responsibly. Always stay attentive to the game.[/color]"

  if contentLabel.parseColoredText then
    contentLabel:parseColoredText(warningText, "$var-text-cip-color")
  else
    contentLabel:setText(warningText:gsub("%[/?color[^%]]*%]", ""))
  end

  -- Checkbox "Não mostrar novamente"
  local checkbox = warningWindow:getChildById('warningCheckbox')

  local function closeWarning()
    warningWindow:destroy()
    activeToolWarning = nil
  end

  -- Botão "Entendi"
  local acceptButton = warningWindow:getChildById('warningAcceptButton')
  if not acceptButton then
    helperDebug("tool warning missing warningAcceptButton")
    closeWarning()
    if onCancelCallback then onCancelCallback() end
    return
  end

  connect(acceptButton, {
    onClick = function()
      helperDebug("tool warning accept clicked")
      if checkbox and checkbox:isChecked() then
        helperConfig.hideToolWarning = true
        saveSettings()
      end
      closeWarning()
      if onAcceptCallback then onAcceptCallback() end
    end
  })

  -- ESC fecha sem ativar (reverte estado do checkbox/botão)
  connect(warningWindow, {
    onEscape = function()
      helperDebug("tool warning cancelled by escape")
      closeWarning()
      if onCancelCallback then onCancelCallback() end
    end
  })

  if UIModalOverlay and UIModalOverlay.register and UIModalOverlay.show then
    UIModalOverlay.register(warningWindow)
    UIModalOverlay.show(warningWindow)
  else
    helperDebug("tool warning using non-modal fallback")
    warningWindow:show()
    warningWindow:raise()
    warningWindow:focus()
  end
end

_Helper.showToolWarning = showToolWarning

function loadSettings()
  local currentPlayer = g_game.getLocalPlayer()
  if not currentPlayer then
    return false
  end

  -- mesmo caminho usado no saveSettings
  local folder = "/characterdata/" .. currentPlayer:getId() .. "/helper.json"

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
      autoReconnect          = false,
      autoChangeGold         = false,
      magicShooterEnabled    = false,
      magicShooterOnHold     = false,
      disableInProtectZone   = true,
      autoTargetEnabled      = false,
      autoTargetMode         = autoTargetModes["F"],
      currentLockedTargetId  = 0,
      ignoreMonsterList      = "",
      priorityMonsterList    = "",
      hideToolWarning        = false
    }
    _Helper.HotkeyManager.restoreAll(savedHotkeys)
  end

  if not g_resources.fileExists(folder) then
    resetToDefaults()
    helperAutomaticFunctionsEnabled = true
    return false
  end

  local status, result = pcall(function()
    return json.decode(g_resources.readFileContents(folder))
  end)

  if not status or not result then
    resetToDefaults()
    return false
  end

  -- Preservar funções de hotkey (não são serializáveis, então não vêm do arquivo)
  local savedFuncs = _Helper.HotkeyManager.preserveFuncs()

  helperConfig = result

  -- Restaurar apenas as funções de hotkey (os códigos vêm do arquivo)
  _Helper.HotkeyManager.restoreFuncs(savedFuncs)

  -- Restaurar estado do helper enabled
  if result.helperAutomaticFunctionsEnabled ~= nil then
    helperAutomaticFunctionsEnabled = result.helperAutomaticFunctionsEnabled
  end

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

  -- specialFoods: always rebuild arrays to ensure correct IDs and count
  local expectedHpFoods = {
    { id = 11586, enabled = false, percent = 80, priority = 1 },
    { id = 9079,  enabled = false, percent = 80, priority = 2 },
    { id = 29414, enabled = false, percent = 80, priority = 3 },
    { id = 28485, enabled = false, percent = 80, priority = 4 },
  }
  local expectedManaFoods = {
    { id = 29415, enabled = false, percent = 60, priority = 1 },
    { id = 28484, enabled = false, percent = 60, priority = 2 },
    { id = 9086,  enabled = false, percent = 60, priority = 3 },
  }
  if not helperConfig.specialFoods then
    helperConfig.specialFoods = {}
  end
  -- Rebuild HP foods preserving saved settings by matching ID
  local oldHp = helperConfig.specialFoods.hp or {}
  local oldHpById = {}
  for _, f in pairs(oldHp) do
    if f.id then oldHpById[f.id] = f end
  end
  helperConfig.specialFoods.hp = {}
  for i, def in ipairs(expectedHpFoods) do
    local saved = oldHpById[def.id]
    helperConfig.specialFoods.hp[i] = {
      id = def.id,
      enabled = saved and saved.enabled or false,
      percent = (saved and saved.percent and saved.percent > 0) and saved.percent or def.percent,
      priority = (saved and saved.priority and saved.priority > 0) and saved.priority or def.priority,
    }
  end
  -- Rebuild Mana foods preserving saved settings by matching ID
  local oldMana = helperConfig.specialFoods.mana or {}
  local oldManaById = {}
  for _, f in pairs(oldMana) do
    if f.id then oldManaById[f.id] = f end
  end
  helperConfig.specialFoods.mana = {}
  for i, def in ipairs(expectedManaFoods) do
    local saved = oldManaById[def.id]
    helperConfig.specialFoods.mana[i] = {
      id = def.id,
      enabled = saved and saved.enabled or false,
      percent = (saved and saved.percent and saved.percent > 0) and saved.percent or def.percent,
      priority = (saved and saved.priority and saved.priority > 0) and saved.priority or def.priority,
    }
  end

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
  -- Garantir que todas as vocações existam no config
  for voc, def in pairs(defaultVocHealing) do
    if not helperConfig.friendhealing[voc] then
      helperConfig.friendhealing[voc] = deepCopy(def)
    end
    local v = helperConfig.friendhealing[voc]
    if v.enabled == nil then v.enabled = false end
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
    if v.enabled == nil then v.enabled = false end
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
    if v.enabled == nil then v.enabled = false end
    if not v.percent then v.percent = 90 end
    if not v.priority then v.priority = def.priority end
  end
  if helperConfig.masreshealing.extended == nil then
    helperConfig.masreshealing.extended = false
  end
  if not helperConfig.healingTargetMode then
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
  if helperConfig.autoReconnect == nil then
    helperConfig.autoReconnect = false
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
      potionEnabled = false,
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
    if helperConfig.magicShield.potionEnabled == nil then
      helperConfig.magicShield.potionEnabled = false
    end
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

local function initSpecialFoodsWindow()
  if not specialFoodsWindow or not helperConfig then return end

  local hpFoods = helperConfig.specialFoods and helperConfig.specialFoods.hp or {}
  for i, food in ipairs(hpFoods) do
    local slotIdx = i - 1
    local slot = specialFoodsWindow:recursiveGetChildById("hpFoodSlot" .. slotIdx)
    if slot and food.id and food.id ~= 0 then
      local existing = slot:getChildById('foodItem')
      if existing then existing:destroy() end
      local itemWidget = g_ui.createWidget('FoodItem', slot)
      itemWidget:setItemId(food.id)
      itemWidget:setId('foodItem')
    end
    local checkbox = specialFoodsWindow:recursiveGetChildById("hpFoodEnable" .. slotIdx)
    if checkbox then
      checkbox:setChecked(food.enabled or false)
    end
    local percentLabel = specialFoodsWindow:recursiveGetChildById("hpFoodPercentLabel" .. slotIdx)
    if percentLabel then
      percentLabel:setText(food.percent .. "%")
    end
    local priorityLabel = specialFoodsWindow:recursiveGetChildById("hpFoodPriorityLabel" .. slotIdx)
    if priorityLabel then
      priorityLabel:setText(tostring(food.priority or i))
    end
  end

  local manaFoods = helperConfig.specialFoods and helperConfig.specialFoods.mana or {}
  for i, food in ipairs(manaFoods) do
    local slotIdx = i - 1
    local slot = specialFoodsWindow:recursiveGetChildById("manaFoodSlot" .. slotIdx)
    if slot and food.id and food.id ~= 0 then
      local existing = slot:getChildById('foodItem')
      if existing then existing:destroy() end
      local itemWidget = g_ui.createWidget('FoodItem', slot)
      itemWidget:setItemId(food.id)
      itemWidget:setId('foodItem')
    end
    local checkbox = specialFoodsWindow:recursiveGetChildById("manaFoodEnable" .. slotIdx)
    if checkbox then
      checkbox:setChecked(food.enabled or false)
    end
    local percentLabel = specialFoodsWindow:recursiveGetChildById("manaFoodPercentLabel" .. slotIdx)
    if percentLabel then
      percentLabel:setText(food.percent .. "%")
    end
    local priorityLabel = specialFoodsWindow:recursiveGetChildById("manaFoodPriorityLabel" .. slotIdx)
    if priorityLabel then
      priorityLabel:setText(tostring(food.priority or i))
    end
  end
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
    specialFoodsWindow:destroy()
    specialFoodsWindow = nil
  end
end

function toggleSpecialFood(category, index, checked)
  if not helperConfig or not helperConfig.specialFoods then return end
  if not helperConfig.specialFoods[category] then return end
  if not helperConfig.specialFoods[category][index] then return end
  helperConfig.specialFoods[category][index].enabled = checked
  saveSettings()
end

function updateSpecialFoodPercent(category, index, delta)
  if not helperConfig or not helperConfig.specialFoods then return end
  if not helperConfig.specialFoods[category] then return end
  if not helperConfig.specialFoods[category][index] then return end

  local food = helperConfig.specialFoods[category][index]
  local newPercent = (food.percent or 50) + delta
  if newPercent < 5 then newPercent = 5 end
  if newPercent > 99 then newPercent = 99 end
  food.percent = newPercent

  if specialFoodsWindow then
    local prefix = category == "hp" and "hpFoodPercentLabel" or "manaFoodPercentLabel"
    local label = specialFoodsWindow:recursiveGetChildById(prefix .. (index - 1))
    if label then
      label:setText(newPercent .. "%")
    end
  end

  saveSettings()
end

function updateSpecialFoodPriority(category, index, delta)
  if not helperConfig or not helperConfig.specialFoods then return end
  if not helperConfig.specialFoods[category] then return end
  if not helperConfig.specialFoods[category][index] then return end

  local maxPriority = #helperConfig.specialFoods[category]
  local food = helperConfig.specialFoods[category][index]
  local newPriority = (food.priority or 1) + delta
  if newPriority < 1 then newPriority = 1 end
  if newPriority > maxPriority then newPriority = maxPriority end
  food.priority = newPriority

  if specialFoodsWindow then
    local prefix = category == "hp" and "hpFoodPriorityLabel" or "manaFoodPriorityLabel"
    local label = specialFoodsWindow:recursiveGetChildById(prefix .. (index - 1))
    if label then
      label:setText(tostring(newPriority))
    end
  end

  saveSettings()
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
    "timerMenu"
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
