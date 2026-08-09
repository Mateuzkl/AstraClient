MiniBotEngine = {}

local SETTINGS_NODE = "AstraMiniBot"
local TICK_INTERVAL = 100

local defaults = {
  masterEnabled = false,

  healthSpellEnabled = false,
  healthSpell = "exura gran",
  healthSpellPercent = 70,
  healthItemEnabled = false,
  healthItemId = 0,
  healthItemPercent = 45,
  manaItemEnabled = false,
  manaItemId = 0,
  manaItemPercent = 45,
  groupHealEnabled = false,
  groupHealName = "",
  groupHealSpell = "exura sio",
  groupHealPercent = 60,

  autoTargetEnabled = false,
  attackSpellEnabled = false,
  attackSpell = "exori",
  attackMinMonsters = 1,
  attackRange = 5,
  attackRuneEnabled = false,
  attackRuneId = 0,
  combatPauseCavebot = true,

  hasteEnabled = false,
  hasteSpell = "utani hur",
  manaShieldEnabled = false,
  manaShieldSpell = "utamo vita",
  antiParalyzeEnabled = false,
  antiParalyzeSpell = "exura",
  manaTrainerEnabled = false,
  manaTrainerSpell = "utevo lux",
  manaTrainerPercent = 90,
  timerSpellEnabled = false,
  timerSpell = "",
  timerSpellInterval = 2000,

  equipmentEnabled = false,
  emergencyPercent = 50,
  emergencyAmuletId = 0,
  normalAmuletId = 0,
  emergencyRingId = 0,
  normalRingId = 0,

  cavebotEnabled = false,
  cavebotLoop = true,
  cavebotWaypoints = "",
  cavebotStepDelay = 600
}

local settings = nil
local config = nil
local tickEvent = nil
local saveEvent = nil
local online = false
local serverAuthorized = false
local statusCallback = nil
local lastStatus = nil
local lastActions = {}
local lastErrorAt = 0
local waypoints = {}
local waypointIndex = 1
local waypointWaitUntil = 0
local waypointsDirty = true

local function copyTable(source)
  local result = {}
  for key, value in pairs(source) do
    result[key] = type(value) == "table" and copyTable(value) or value
  end
  return result
end

local function mergeDefaults(target, sourceDefaults)
  if type(target) ~= "table" then
    target = {}
  end
  for key, value in pairs(sourceDefaults) do
    if type(target[key]) ~= type(value) then
      target[key] = type(value) == "table" and copyTable(value) or value
    elseif type(value) == "table" then
      target[key] = mergeDefaults(target[key], value)
    end
  end
  return target
end

local function setStatus(text)
  if text == lastStatus then
    return
  end
  lastStatus = text
  if statusCallback then
    statusCallback(text)
  end
end

local function flushSettings()
  if saveEvent then
    removeEvent(saveEvent)
    saveEvent = nil
  end
  if settings then
    g_settings.setNode(SETTINGS_NODE, settings)
    g_settings.save()
  end
end

local function scheduleSave()
  if saveEvent then
    removeEvent(saveEvent)
  end
  saveEvent = scheduleEvent(function()
    saveEvent = nil
    flushSettings()
  end, 250)
end

local function actionReady(name, delay)
  local now = g_clock.millis()
  if (lastActions[name] or 0) + delay > now then
    return false
  end
  lastActions[name] = now
  return true
end

local function castSpell(words, delay)
  if type(words) ~= "string" or words:trim() == "" or not actionReady("spell", delay or 1000) then
    return false
  end
  g_game.talk(words:trim())
  return true
end

local function useItemOn(itemId, target, delay)
  itemId = tonumber(itemId) or 0
  if itemId <= 0 or not target or not actionReady("item", delay or 600) then
    return false
  end
  g_game.useInventoryItemWith(itemId, target)
  return true
end

local function manaPercent(player)
  local maximum = player:getMaxMana()
  if maximum <= 0 then
    return 100
  end
  return math.floor(player:getMana() * 100 / maximum)
end

local function distanceBetween(first, second)
  if not first or not second or first.z ~= second.z then
    return math.huge
  end
  return math.max(math.abs(first.x - second.x), math.abs(first.y - second.y))
end

local function findCreatureByName(name, player)
  name = type(name) == "string" and name:trim():lower() or ""
  if name == "" then
    return nil
  end
  for _, creature in ipairs(g_map.getSpectators(player:getPosition(), false)) do
    if creature:getName():lower() == name then
      return creature
    end
  end
  return nil
end

local function findClosestMonster(player, maximumRange)
  local closest = nil
  local closestDistance = math.huge
  for _, creature in ipairs(g_map.getSpectators(player:getPosition(), false)) do
    if creature:isMonster() and creature:getHealthPercent() > 0 then
      local distance = distanceBetween(player:getPosition(), creature:getPosition())
      if distance <= maximumRange and distance < closestDistance then
        closest = creature
        closestDistance = distance
      end
    end
  end
  return closest
end

local function countMonsters(player, range)
  local count = 0
  for _, creature in ipairs(g_map.getSpectators(player:getPosition(), false)) do
    if creature:isMonster() and creature:getHealthPercent() > 0 and distanceBetween(player:getPosition(), creature:getPosition()) <= range then
      count = count + 1
    end
  end
  return count
end

local function processHealing(player)
  local health = player:getHealthPercent()
  if config.healthItemEnabled and health <= config.healthItemPercent and useItemOn(config.healthItemId, player, 600) then
    return true
  end
  if config.healthSpellEnabled and health <= config.healthSpellPercent and castSpell(config.healthSpell, 1000) then
    return true
  end

  local mana = manaPercent(player)
  if config.manaItemEnabled and mana <= config.manaItemPercent and useItemOn(config.manaItemId, player, 600) then
    return true
  end

  if config.groupHealEnabled then
    local friend = findCreatureByName(config.groupHealName, player)
    if friend and friend:getHealthPercent() <= config.groupHealPercent then
      local words = string.format('%s "%s', config.groupHealSpell:trim(), friend:getName())
      if castSpell(words, 1000) then
        return true
      end
    end
  end
  return false
end

local function processSupport(player)
  if config.antiParalyzeEnabled and player:isParalyzed() and castSpell(config.antiParalyzeSpell, 1000) then
    return true
  end
  if config.manaShieldEnabled and not player:hasManaShield() and castSpell(config.manaShieldSpell, 1000) then
    return true
  end
  if config.hasteEnabled and not player:hasHaste() and castSpell(config.hasteSpell, 1000) then
    return true
  end
  if config.manaTrainerEnabled and manaPercent(player) >= config.manaTrainerPercent and castSpell(config.manaTrainerSpell, 1000) then
    return true
  end
  if config.timerSpellEnabled and actionReady("timerSpell", math.max(250, config.timerSpellInterval)) then
    return castSpell(config.timerSpell, 250)
  end
  return false
end

local function processCombat(player)
  if player:isInPz() then
    return false
  end

  local range = math.max(1, config.attackRange)
  local target = g_game.getAttackingCreature()
  if target and (not target:isMonster() or target:getHealthPercent() <= 0) then
    target = nil
  end
  if not target and config.autoTargetEnabled and actionReady("target", 500) then
    target = findClosestMonster(player, range)
    if target then
      g_game.attack(target)
    end
  end
  if not target then
    return false
  end

  if config.attackSpellEnabled and countMonsters(player, range) >= math.max(1, config.attackMinMonsters) and castSpell(config.attackSpell, 1000) then
    return true
  end
  if config.attackRuneEnabled and useItemOn(config.attackRuneId, target, 1000) then
    return true
  end
  return false
end

local function equipItem(itemId)
  itemId = tonumber(itemId) or 0
  if itemId <= 0 or not actionReady("equipment", 1200) then
    return false
  end
  g_game.equipItemId(itemId, 0)
  return true
end

local function processEquipment(player)
  if not config.equipmentEnabled then
    return false
  end
  local emergency = player:getHealthPercent() <= config.emergencyPercent
  local amuletId = emergency and config.emergencyAmuletId or config.normalAmuletId
  local ringId = emergency and config.emergencyRingId or config.normalRingId

  local necklace = player:getInventoryItem(InventorySlotNeck)
  if amuletId > 0 and (not necklace or necklace:getId() ~= amuletId) and equipItem(amuletId) then
    return true
  end
  local ring = player:getInventoryItem(InventorySlotFinger)
  if ringId > 0 and (not ring or ring:getId() ~= ringId) and equipItem(ringId) then
    return true
  end
  return false
end

local function parseWaypoints()
  waypoints = {}
  waypointIndex = 1
  waypointWaitUntil = 0
  waypointsDirty = false

  for line in tostring(config.cavebotWaypoints or ""):gmatch("[^\r\n]+") do
    local command, payload = line:match("^%s*([%a]+)%s*:%s*(.-)%s*$")
    if command and payload then
      command = command:lower()
      if command == "walk" or command == "stand" then
        local x, y, z = payload:match("^(%d+)%s*,%s*(%d+)%s*,%s*(%d+)$")
        if x then
          table.insert(waypoints, { command = command, position = { x = tonumber(x), y = tonumber(y), z = tonumber(z) } })
        end
      elseif command == "wait" then
        table.insert(waypoints, { command = command, duration = math.max(0, tonumber(payload) or 0) })
      elseif command == "say" then
        table.insert(waypoints, { command = command, text = payload })
      elseif command == "use" then
        local itemId, x, y, z = payload:match("^(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)$")
        if itemId then
          table.insert(waypoints, { command = command, itemId = tonumber(itemId), position = { x = tonumber(x), y = tonumber(y), z = tonumber(z) } })
        end
      end
    end
  end
end

local function advanceWaypoint()
  waypointIndex = waypointIndex + 1
  waypointWaitUntil = 0
  if waypointIndex > #waypoints then
    waypointIndex = config.cavebotLoop and 1 or (#waypoints + 1)
  end
end

local function processCavebot(player)
  if not config.cavebotEnabled or player:isInPz() then
    return false
  end
  if config.combatPauseCavebot and g_game.getAttackingCreature() then
    return false
  end
  if waypointsDirty then
    parseWaypoints()
  end
  if #waypoints == 0 or waypointIndex > #waypoints then
    return false
  end

  local waypoint = waypoints[waypointIndex]
  if waypoint.command == "walk" or waypoint.command == "stand" then
    if distanceBetween(player:getPosition(), waypoint.position) == 0 then
      advanceWaypoint()
      return true
    end
    if actionReady("caveWalk", math.max(250, config.cavebotStepDelay)) then
      player:autoWalk(waypoint.position)
      return true
    end
  elseif waypoint.command == "wait" then
    if waypointWaitUntil == 0 then
      waypointWaitUntil = g_clock.millis() + waypoint.duration
    elseif g_clock.millis() >= waypointWaitUntil then
      advanceWaypoint()
    end
    return true
  elseif waypoint.command == "say" then
    if castSpell(waypoint.text, 600) then
      advanceWaypoint()
      return true
    end
  elseif waypoint.command == "use" and actionReady("caveUse", 800) then
    local tile = g_map.getTile(waypoint.position)
    local target = tile and tile:getTopUseThing() or nil
    if target then
      g_game.useInventoryItemWith(waypoint.itemId, target)
    else
      g_game.useInventoryItem(waypoint.itemId)
    end
    advanceWaypoint()
    return true
  end
  return false
end

local function runTick()
  if not online or not g_game.isOnline() then
    setStatus("Offline")
    return
  end
  if not serverAuthorized then
    setStatus("Waiting for Astra server authorization")
    return
  end
  if not config.masterEnabled then
    setStatus("Ready - automation disabled")
    return
  end

  local player = g_game.getLocalPlayer()
  if not player then
    setStatus("Waiting for player data")
    return
  end

  setStatus(string.format("Running - Cavebot node %d/%d", math.min(waypointIndex, #waypoints), #waypoints))
  if not processHealing(player) then
    if not processSupport(player) then
      processCombat(player)
    end
  end
  processEquipment(player)
  processCavebot(player)
end

local function tick()
  tickEvent = nil
  local ok, errorMessage = pcall(runTick)
  if not ok and g_clock.millis() - lastErrorAt > 5000 then
    lastErrorAt = g_clock.millis()
    g_logger.error("[MiniBot] " .. tostring(errorMessage))
    setStatus("Runtime error - see client log")
  end
  if online then
    tickEvent = scheduleEvent(tick, TICK_INTERVAL)
  end
end

function MiniBotEngine.init(callback)
  statusCallback = callback
  settings = g_settings.getNode(SETTINGS_NODE)
  if type(settings) ~= "table" then
    settings = {}
  end
  settings.presets = type(settings.presets) == "table" and settings.presets or {}
  settings.presets.Default = mergeDefaults(settings.presets.Default, defaults)
  settings.activePreset = type(settings.activePreset) == "string" and settings.activePreset or "Default"
  if type(settings.presets[settings.activePreset]) ~= "table" then
    settings.activePreset = "Default"
  end
  config = mergeDefaults(settings.presets[settings.activePreset], defaults)
  flushSettings()
end

function MiniBotEngine.terminate()
  online = false
  if tickEvent then
    removeEvent(tickEvent)
    tickEvent = nil
  end
  flushSettings()
  statusCallback = nil
end

function MiniBotEngine.online()
  online = true
  serverAuthorized = false
  lastActions = {}
  waypointsDirty = true
  if not tickEvent then
    tickEvent = scheduleEvent(tick, TICK_INTERVAL)
  end
end

function MiniBotEngine.offline()
  online = false
  serverAuthorized = false
  if tickEvent then
    removeEvent(tickEvent)
    tickEvent = nil
  end
  setStatus("Offline")
end

function MiniBotEngine.setServerAuthorized(authorized)
  serverAuthorized = authorized == true
  if serverAuthorized then
    setStatus(config.masterEnabled and "Running" or "Ready - automation disabled")
  else
    setStatus("MiniBot disabled by server")
  end
end

function MiniBotEngine.isServerAuthorized()
  return serverAuthorized
end

function MiniBotEngine.get(key)
  return config and config[key]
end

function MiniBotEngine.set(key, value)
  if not config or defaults[key] == nil or type(value) ~= type(defaults[key]) then
    return false
  end
  config[key] = value
  if key == "cavebotWaypoints" then
    waypointsDirty = true
  elseif key == "cavebotEnabled" then
    waypointIndex = 1
    waypointWaitUntil = 0
  end
  scheduleSave()
  return true
end

function MiniBotEngine.getPresetNames()
  local names = {}
  for name in pairs(settings.presets) do
    table.insert(names, name)
  end
  table.sort(names, function(left, right)
    if left == "Default" then return true end
    if right == "Default" then return false end
    return left:lower() < right:lower()
  end)
  return names
end

function MiniBotEngine.getActivePreset()
  return settings.activePreset
end

function MiniBotEngine.selectPreset(name)
  if type(name) ~= "string" or type(settings.presets[name]) ~= "table" then
    return false
  end
  settings.activePreset = name
  config = mergeDefaults(settings.presets[name], defaults)
  waypointsDirty = true
  waypointIndex = 1
  flushSettings()
  return true
end

function MiniBotEngine.createPreset(name)
  name = type(name) == "string" and name:trim() or ""
  if name == "" or #name > 32 or settings.presets[name] then
    return false
  end
  settings.presets[name] = copyTable(config)
  settings.activePreset = name
  config = settings.presets[name]
  flushSettings()
  return true
end

function MiniBotEngine.deleteActivePreset()
  if settings.activePreset == "Default" then
    return false
  end
  settings.presets[settings.activePreset] = nil
  settings.activePreset = "Default"
  config = settings.presets.Default
  waypointsDirty = true
  waypointIndex = 1
  flushSettings()
  return true
end

function MiniBotEngine.resetActivePreset()
  settings.presets[settings.activePreset] = copyTable(defaults)
  config = settings.presets[settings.activePreset]
  waypointsDirty = true
  waypointIndex = 1
  flushSettings()
end

function MiniBotEngine.addCurrentWaypoint()
  local player = g_game.getLocalPlayer()
  if not player then
    return false
  end
  local position = player:getPosition()
  local line = string.format("walk:%d,%d,%d", position.x, position.y, position.z)
  local current = tostring(config.cavebotWaypoints or "")
  config.cavebotWaypoints = current == "" and line or (current .. "\n" .. line)
  waypointsDirty = true
  scheduleSave()
  return true
end

function MiniBotEngine.clearWaypoints()
  config.cavebotWaypoints = ""
  waypointsDirty = true
  waypointIndex = 1
  scheduleSave()
end
