-- Lua compatibility runtime for the original MiniBot module.
--
-- The distributed module normally receives g_minibot from a native client
-- extension.  AstraClient does not ship that extension, so this file keeps the
-- same public ABI and executes the configured rules with AstraClient APIs.

local rootEnvironment = _G
local previousMiniBot = rawget(rootEnvironment, 'g_minibot')
if previousMiniBot ~= nil and previousMiniBot.__astraLuaRuntime then
  if MiniBotRuntime ~= nil and type(MiniBotRuntime.terminate) == 'function' then
    MiniBotRuntime.terminate()
  end
  previousMiniBot = nil
end

-- Prefer a real native implementation when a future build provides one.
if previousMiniBot ~= nil and type(previousMiniBot.addModule) == 'function' then
  g_minibot = previousMiniBot
  MiniBotRuntime = {
    native = true
  }

  function MiniBotRuntime.init()
    return true
  end

  function MiniBotRuntime.start()
    return true
  end

  function MiniBotRuntime.stop()
    return true
  end

  function MiniBotRuntime.terminate()
    return true
  end

  function MiniBotRuntime.applyServerCavebotState(enabled)
    if type(g_minibot.applyServerCavebotState) == 'function' then
      return g_minibot.applyServerCavebotState(enabled == true)
    end
    return false
  end

  return
end

g_minibot = {
  __astraLuaRuntime = true
}

local api = g_minibot
local runtime = {}
MiniBotRuntime = runtime

local function publishApi()
  rawset(rootEnvironment, 'g_minibot', api)
end

publishApi()

local LOOP_INTERVAL = 50
local CAVEBOT_OPCODE = 210
local MAGIC_SHIELD_POTION = 35563
local GOLD_COIN = 3031
local PLATINUM_COIN = 3035
local MULTI_USE_GROUP = 255
local DEFAULT_MULTI_USE_COOLDOWN = 1000
local AUTO_TRAINING_RETRY_INTERVAL = 30000

local state = {
  initialized = false,
  connected = false,
  running = false,
  loopEvent = nil,
  modules = {},
  toggles = {},
  moduleTicks = {},
  autoAttack = 0,
  spellCooldowns = {},
  groupCooldowns = {},
  multiUseCooldownUntil = 0,
  nextGlobalActionAt = 0,
  lastAttackCheck = 0,
  waypoints = {},
  currentWalkIndex = 0,
  announcedWalkIndex = 0,
  walkNextAt = 0,
  walkPaused = false,
  walkCommandKind = nil,
  walkFailureCount = 0,
  teleportStartPosition = nil,
  explorer = {
    findCreatures = 0,
    resumeCreatures = 0,
    lureCreatures = false
  },
  explorerDirection = 1,
  explorerTarget = nil,
  explorerPaused = false,
  explorerFailures = 0,
  lastSentCavebotState = nil,
  virtueUntil = 0,
  gameCallbacks = nil,
  playerCallbacks = nil
}

for moduleType = 0, 22 do
  state.modules[moduleType] = {}
  state.toggles[moduleType] = false
  state.moduleTicks[moduleType] = 0
end

local function nowMillis()
  if g_clock ~= nil and type(g_clock.millis) == 'function' then
    return g_clock.millis()
  end
  return math.floor(os.clock() * 1000)
end

local function finiteNumber(value, fallback)
  local number = tonumber(value)
  if number == nil or number ~= number or number == math.huge or number == -math.huge then
    return fallback or 0
  end
  return number
end

local function integer(value, fallback)
  return math.floor(finiteNumber(value, fallback or 0))
end

local function nonNegative(value)
  return math.max(0, finiteNumber(value, 0))
end

local function copyNumberList(source)
  local result = {}
  if type(source) ~= 'table' then
    return result
  end

  for _, value in pairs(source) do
    local number = integer(value, 0)
    if number > 0 then
      table.insert(result, number)
    end
  end
  return result
end

local function copyItemGroups(source)
  local groups = {}
  local multiUse = false
  if type(source) ~= 'table' then
    return groups, multiUse
  end

  for _, value in pairs(source) do
    local number = integer(value, 0)
    if number == MULTI_USE_GROUP then
      -- 255 is the donor runtime's shared multi-use cooldown marker. Keep it
      -- separate from real alternative equipment ids.
      multiUse = true
    elseif number > 0 then
      table.insert(groups, number)
    end
  end
  return groups, multiUse
end

local function contains(list, value)
  if type(list) ~= 'table' then
    return false
  end
  for _, entry in ipairs(list) do
    if entry == value then
      return true
    end
  end
  return false
end

local function copyPosition(position)
  if type(position) ~= 'table' then
    return nil
  end
  local x = integer(position.x, -1)
  local y = integer(position.y, -1)
  local z = integer(position.z, -1)
  if x < 0 or y < 0 or z < 0 then
    return nil
  end
  return { x = x, y = y, z = z }
end

local function samePosition(first, second)
  return first ~= nil and second ~= nil and
      first.x == second.x and first.y == second.y and first.z == second.z
end

local function tileDistance(first, second)
  if first == nil or second == nil or first.z ~= second.z then
    return 9999
  end
  return math.max(math.abs(first.x - second.x), math.abs(first.y - second.y))
end

local function normalizeRule(input)
  input = type(input) == 'table' and input or {}
  local itemGroups, multiUse = copyItemGroups(input.itemGroup)
  return {
    item = math.max(0, integer(input.item, 0)),
    -- Donor pages feed table.find's numeric index here. Lua treats every
    -- non-nil/non-false value (including numeric indexes) as enabled.
    use = input.use ~= nil and input.use ~= false,
    min = nonNegative(input.min),
    max = nonNegative(input.max),
    enabled = input.enabled ~= false,
    ignorePz = input.ignorePz == true,
    smart = input.smart == true,
    spell = type(input.spell) == 'string' and input.spell or '',
    reqmana = nonNegative(input.reqmana),
    harmony = nonNegative(input.harmony),
    manaMin = nonNegative(input.manaMin),
    manaMax = nonNegative(input.manaMax),
    health = nonNegative(input.health),
    mana = nonNegative(input.mana),
    hits = nonNegative(input.hits),
    area = type(input.area) == 'string' and input.area or '',
    target = type(input.target) == 'string' and input.target or '',
    itemGroup = itemGroups,
    multiUse = multiUse,
    spellGroup = copyNumberList(input.spellGroup),
    spellId = copyNumberList(input.spellId),
    lastCall = nonNegative(input.lastCall),
    _nextAt = nonNegative(input.lastCall),
    _primedUntil = 0
  }
end

local function cloneMatrix(matrix)
  local result = {}
  for y, row in ipairs(matrix) do
    result[y] = {}
    for x, value in ipairs(row) do
      result[y][x] = value
    end
  end
  return result
end

local function makeCircle(radius, marker)
  local size = radius * 2 + 1
  local matrix = {}
  for y = 1, size do
    matrix[y] = {}
    for x = 1, size do
      local dx = x - radius - 1
      local dy = y - radius - 1
      local affected = (dx * dx + dy * dy) <= (radius * radius + radius)
      matrix[y][x] = affected and 1 or 0
    end
  end
  matrix[radius + 1][radius + 1] = marker
  return matrix
end

local function makeCross(radius, marker)
  local size = radius * 2 + 1
  local matrix = {}
  for y = 1, size do
    matrix[y] = {}
    for x = 1, size do
      local dx = math.abs(x - radius - 1)
      local dy = math.abs(y - radius - 1)
      matrix[y][x] = (dx == 0 or dy == 0) and 1 or 0
    end
  end
  matrix[radius + 1][radius + 1] = marker
  return matrix
end

local AREA_TEMPLATES = {
  target = { { 3 } },
  fill_circle_1_center = makeCircle(1, 2),
  fill_circle_3 = makeCircle(3, 3),
  fill_circle_3_center = makeCircle(3, 2),
  fill_circle_10_center = makeCircle(5, 2),
  cross_1 = makeCross(1, 3),
  ring_circle_3_center = {
    { 0, 0, 0, 1, 1, 1, 0, 0, 0 },
    { 0, 0, 1, 1, 1, 1, 1, 0, 0 },
    { 0, 1, 1, 1, 1, 1, 1, 1, 0 },
    { 1, 1, 1, 0, 0, 0, 1, 1, 1 },
    { 1, 1, 1, 0, 2, 0, 1, 1, 1 },
    { 1, 1, 1, 0, 0, 0, 1, 1, 1 },
    { 0, 1, 1, 1, 1, 1, 1, 1, 0 },
    { 0, 0, 1, 1, 1, 1, 1, 0, 0 },
    { 0, 0, 0, 1, 1, 1, 0, 0, 0 }
  },
  hammer_1_dir = {
    { 1, 1, 1 },
    { 0, 2, 0 }
  },
  hammer_3_dir = {
    { 1, 1, 1 },
    { 1, 1, 1 },
    { 0, 1, 0 },
    { 0, 2, 0 }
  },
  hammer_5_dir = {
    { 1, 1, 1, 1, 1 },
    { 0, 1, 1, 1, 0 },
    { 0, 1, 1, 1, 0 },
    { 0, 0, 1, 0, 0 },
    { 0, 0, 2, 0, 0 }
  },
  wave_4_dir = {
    { 1, 1, 1 },
    { 1, 1, 1 },
    { 1, 1, 1 },
    { 0, 1, 0 },
    { 0, 1, 0 },
    { 0, 2, 0 }
  },
  wave_5_dir = {
    { 0, 0, 1, 0, 0 },
    { 0, 1, 1, 1, 0 },
    { 0, 1, 1, 1, 0 },
    { 1, 1, 1, 1, 1 },
    { 0, 1, 2, 1, 0 }
  },
  beam_5_dir = { { 1 }, { 1 }, { 1 }, { 1 }, { 1 }, { 2 } },
  beam_6_dir = { { 1 }, { 1 }, { 1 }, { 1 }, { 1 }, { 1 }, { 2 } },
  beam_7_dir = { { 1 }, { 1 }, { 1 }, { 1 }, { 1 }, { 1 }, { 1 }, { 2 } },
  spear_3_dir = {
    { 0, 1, 0 },
    { 0, 1, 0 },
    { 1, 1, 1 },
    { 0, 2, 0 }
  },
  spear_line_4_dir = { { 1 }, { 1 }, { 1 }, { 1 }, { 2 } }
}

function api.getAreaCoordinates(areaName)
  local template = AREA_TEMPLATES[areaName]
  if template == nil then
    template = AREA_TEMPLATES.target
  end
  return cloneMatrix(template)
end

local function isOnline()
  return g_game ~= nil and type(g_game.isOnline) == 'function' and g_game.isOnline()
end

local function getPlayer()
  if g_game == nil or type(g_game.getLocalPlayer) ~= 'function' then
    return nil
  end
  return g_game.getLocalPlayer()
end

local function canPerformAction()
  if not isOnline() then
    return false
  end
  if type(g_game.canPerformGameAction) == 'function' and not g_game.canPerformGameAction() then
    return false
  end
  return true
end

local function getHealthPercent(player)
  if type(player.getHealthPercent) == 'function' then
    return finiteNumber(player:getHealthPercent(), 0)
  end
  if type(player.getHealth) ~= 'function' or type(player.getMaxHealth) ~= 'function' then
    return 0
  end
  local maximum = finiteNumber(player:getMaxHealth(), 0)
  if maximum <= 0 then
    return 0
  end
  return finiteNumber(player:getHealth(), 0) * 100 / maximum
end

local function getManaPercent(player)
  if type(player.getMana) ~= 'function' or type(player.getMaxMana) ~= 'function' then
    return 0
  end
  local maximum = finiteNumber(player:getMaxMana(), 0)
  if maximum <= 0 then
    return 0
  end
  return finiteNumber(player:getMana(), 0) * 100 / maximum
end

local function hasCondition(player, condition)
  if condition == nil then
    return false
  end
  if type(player.hasCondition) == 'function' then
    return player:hasCondition(condition)
  end
  if type(player.hasState) == 'function' then
    return player:hasState(condition)
  end
  return false
end

local function isInProtectionZone(player)
  if type(player.isInProtectionZone) == 'function' then
    return player:isInProtectionZone()
  end
  return PlayerStates ~= nil and hasCondition(player, PlayerStates.Pz)
end

local function isFeared(player)
  return PlayerStates ~= nil and hasCondition(player, PlayerStates.Feared)
end

local function hasHaste(player)
  if type(player.hasHaste) == 'function' then
    return player:hasHaste()
  end
  return PlayerStates ~= nil and hasCondition(player, PlayerStates.Haste)
end

local function isParalyzed(player)
  if type(player.isParalyzed) == 'function' then
    return player:isParalyzed()
  end
  return PlayerStates ~= nil and hasCondition(player, PlayerStates.Paralyze)
end

local function hasManaShield(player)
  if type(player.hasManaShield) == 'function' then
    return player:hasManaShield()
  end
  if PlayerStates == nil then
    return false
  end
  return hasCondition(player, PlayerStates.ManaShield) or
      hasCondition(player, PlayerStates.NewMagicShield) or
      hasCondition(player, PlayerStates.NewManaShield)
end

local function getMagicShieldPercent(player)
  local current = type(player.getMagicShield) == 'function' and finiteNumber(player:getMagicShield(), 0) or
      (type(player.getMana) == 'function' and finiteNumber(player:getMana(), 0) or 0)
  local maximum = type(player.getMaxMagicShield) == 'function' and finiteNumber(player:getMaxMagicShield(), 0) or
      (type(player.getMaxMana) == 'function' and finiteNumber(player:getMaxMana(), 0) or 0)
  if maximum <= 0 then
    return 0
  end
  return current * 100 / maximum
end

local function getHarmony(player)
  if type(player.getHarmony) == 'function' then
    return finiteNumber(player:getHarmony(), 0)
  end
  return 0
end

local function itemCount(player, itemId)
  if itemId <= 0 or type(player.getInventoryCount) ~= 'function' then
    return 0
  end
  return integer(player:getInventoryCount(itemId, 0), 0)
end

local function getSpectators(position)
  if position == nil or g_map == nil or type(g_map.getSpectators) ~= 'function' then
    return {}
  end
  return g_map.getSpectators(position, false) or {}
end

local function isValidMonster(creature, playerPosition)
  if creature == nil or type(creature.isMonster) ~= 'function' or not creature:isMonster() then
    return false
  end
  if type(creature.isDead) == 'function' and creature:isDead() then
    return false
  end
  if type(creature.getHealthPercent) == 'function' and creature:getHealthPercent() <= 0 then
    return false
  end
  if type(creature.getMasterId) == 'function' and creature:getMasterId() > 0 then
    return false
  end
  if type(creature.getPosition) ~= 'function' then
    return false
  end
  local position = creature:getPosition()
  return position ~= nil and playerPosition ~= nil and position.z == playerPosition.z
end

local function visibleMonsters(player)
  local playerPosition = player:getPosition()
  local result = {}
  for _, creature in pairs(getSpectators(playerPosition)) do
    if isValidMonster(creature, playerPosition) then
      table.insert(result, creature)
    end
  end
  return result
end

local function ruleReady(rule, player, at)
  if not rule.enabled or at < rule._nextAt then
    return false
  end
  if rule.multiUse and at < state.multiUseCooldownUntil then
    return false
  end
  if rule.ignorePz and isInProtectionZone(player) then
    return false
  end
  if rule.reqmana > 0 and type(player.getMana) == 'function' and player:getMana() < rule.reqmana then
    return false
  end
  if rule.harmony > 0 and getHarmony(player) < rule.harmony then
    return false
  end
  for _, spellId in ipairs(rule.spellId) do
    if (state.spellCooldowns[spellId] or 0) > at then
      return false
    end
  end
  for _, groupId in ipairs(rule.spellGroup) do
    if (state.groupCooldowns[groupId] or 0) > at then
      return false
    end
  end
  return true
end

local function markRuleAction(rule, at, delay, itemAction)
  rule._nextAt = at + (delay or 500)
  rule.lastCall = at
  for _, spellId in ipairs(rule.spellId) do
    state.spellCooldowns[spellId] = math.max(state.spellCooldowns[spellId] or 0, at + 500)
  end
  for _, groupId in ipairs(rule.spellGroup) do
    state.groupCooldowns[groupId] = math.max(state.groupCooldowns[groupId] or 0, at + 500)
  end
  if itemAction and rule.multiUse then
    state.multiUseCooldownUntil = math.max(
      state.multiUseCooldownUntil, at + DEFAULT_MULTI_USE_COOLDOWN)
  end
  state.nextGlobalActionAt = at + 175
end

local function useInventoryItem(player, itemId, target, directUse)
  if itemCount(player, itemId) <= 0 then
    return false
  end
  if directUse then
    if type(g_game.useInventoryItem) ~= 'function' then
      return false
    end
    g_game.useInventoryItem(itemId, 0)
    return true
  end
  if target == nil or type(g_game.useInventoryItemWith) ~= 'function' then
    return false
  end
  g_game.useInventoryItemWith(itemId, target, 0)
  return true
end

local function castSpell(rule, words, at, delay)
  if words == nil or words == '' or type(g_game.talk) ~= 'function' then
    return false
  end
  g_game.talk(words)
  markRuleAction(rule, at, delay)
  return true
end

local function executeRuleAction(rule, player, target, at, directUse)
  if rule.spell ~= '' and ruleReady(rule, player, at) then
    return castSpell(rule, rule.spell, at, 500)
  end
  if rule.item > 0 and useInventoryItem(player, rule.item, target, directUse or rule.use) then
    markRuleAction(rule, at, 500, true)
    return true
  end
  return false
end

local function inConfiguredRange(value, minimum, maximum)
  if minimum > 0 and value < minimum then
    return false
  end
  if maximum > 0 and value > maximum then
    return false
  end
  return true
end

local function findMatrixMarker(matrix, marker)
  for y, row in ipairs(matrix) do
    for x, value in ipairs(row) do
      if value == marker then
        return x, y
      end
    end
  end
  return math.ceil(#matrix[1] / 2), math.ceil(#matrix / 2)
end

local function rotateOffset(dx, dy, direction)
  if direction == 1 then
    return -dy, dx
  elseif direction == 2 then
    return -dx, -dy
  elseif direction == 3 then
    return dy, -dx
  end
  return dx, dy
end

local function countMonstersInRuleArea(rule, player, target, monsters, directionOverride)
  local areaName = rule.area
  if areaName == nil or areaName == '' or areaName == 'target' then
    return target ~= nil and 1 or 0
  end

  local matrix = AREA_TEMPLATES[areaName]
  if matrix == nil then
    return target ~= nil and 1 or 0
  end

  local directional = areaName:sub(-4) == '_dir'
  local centered = areaName:sub(-7) == '_center'
  local center = nil
  local marker = 3
  if directional or centered then
    center = player:getPosition()
    marker = 2
  elseif target ~= nil and type(target.getPosition) == 'function' then
    center = target:getPosition()
  end
  if center == nil then
    return 0
  end

  local markerX, markerY = findMatrixMarker(matrix, marker)
  local affected = {}
  local direction = directional and
      (directionOverride ~= nil and directionOverride or player:getDirection()) or 0
  for y, row in ipairs(matrix) do
    for x, value in ipairs(row) do
      if value == 1 or value == 3 then
        local dx, dy = x - markerX, y - markerY
        if directional then
          dx, dy = rotateOffset(dx, dy, direction)
        end
        affected[dx .. ':' .. dy] = true
      end
    end
  end

  local count = 0
  for _, creature in ipairs(monsters) do
    local position = creature:getPosition()
    if position ~= nil and position.z == center.z and affected[(position.x - center.x) .. ':' .. (position.y - center.y)] then
      count = count + 1
    end
  end
  return count
end

local function bestDirectionalShooterDirection(rule, player, target, monsters)
  local currentDirection = type(player.getDirection) == 'function' and
    (integer(player:getDirection(), 0) % 4) or 0
  local bestDirection = currentDirection
  local bestHits = countMonstersInRuleArea(rule, player, target, monsters, currentDirection)
  for direction = 0, 3 do
    if direction ~= currentDirection then
      local hits = countMonstersInRuleArea(rule, player, target, monsters, direction)
      if hits > bestHits then
        bestHits = hits
        bestDirection = direction
      end
    end
  end
  return bestHits, bestDirection, currentDirection
end

-- Temporary healing diagnostics. Set to true only while diagnosing locally.
local HEAL_DEBUG = false
local healDebugAt = 0

local function healDiag(message)
  if not HEAL_DEBUG then
    return
  end
  local now = nowMillis()
  if now - healDebugAt < 2000 then
    return
  end
  healDebugAt = now
  if type(g_logger) == 'table' and type(g_logger.info) == 'function' then
    g_logger.info('[minibot-heal] ' .. tostring(message))
  end
end

local function executeHealthHealing(player, at)
  if not state.toggles[1] then
    healDiag('health: toggle OFF (module 1 disabled)')
    return false
  end
  local health = getHealthPercent(player)
  if #state.modules[1] == 0 then
    healDiag(string.format('health: toggle ON but 0 rules loaded (hp=%s)', tostring(health)))
    return false
  end
  for index, rule in ipairs(state.modules[1]) do
    local ready = ruleReady(rule, player, at)
    local inRange = inConfiguredRange(health, rule.min, rule.max)
    if ready and inRange then
      if executeRuleAction(rule, player, player, at, false) then
        return true
      end
      healDiag(string.format('health rule %d: ready+inRange but action FAILED (item=%s spell=%s)',
          index, tostring(rule.item), tostring(rule.spell)))
    else
      healDiag(string.format('health rule %d skipped: ready=%s inRange=%s (hp=%s min=%s max=%s enabled=%s)',
          index, tostring(ready), tostring(inRange), tostring(health),
          tostring(rule.min), tostring(rule.max), tostring(rule.enabled)))
    end
  end
  return false
end

local function executeManaHealing(player, at)
  if not state.toggles[2] then
    return false
  end
  local mana = getManaPercent(player)
  for _, rule in ipairs(state.modules[2]) do
    if ruleReady(rule, player, at) and inConfiguredRange(mana, rule.min, rule.max) and
        executeRuleAction(rule, player, player, at, false) then
      return true
    end
  end
  return false
end

local function matchesVocation(creature, vocationType)
  if vocationType == 0 and type(creature.isKnight) == 'function' then
    return creature:isKnight()
  elseif vocationType == 1 and type(creature.isPaladin) == 'function' then
    return creature:isPaladin()
  elseif vocationType == 2 and type(creature.isMonk) == 'function' then
    return creature:isMonk()
  elseif vocationType == 3 and type(creature.isSorcerer) == 'function' then
    return creature:isSorcerer()
  elseif vocationType == 4 and type(creature.isDruid) == 'function' then
    return creature:isDruid()
  end
  return false
end

local function isPartyTarget(creature)
  return type(creature.isPartyMember) == 'function' and creature:isPartyMember()
end

local function isGuildTarget(creature)
  if type(creature.getEmblem) ~= 'function' then
    return false
  end
  local emblem = creature:getEmblem()
  local green = EmblemGreen or 1
  local member = EmblemMember or 4
  return emblem == green or emblem == member
end

local function findGroupTarget(rule, player, spectators)
  local customMode = state.toggles[18]
  local partyMode = state.toggles[19]
  local guildMode = state.toggles[20]
  if not customMode and not partyMode and not guildMode then
    return nil
  end

  local playerPosition = player:getPosition()
  local playerId = type(player.getId) == 'function' and player:getId() or 0
  local wantedName = rule.target:lower()
  local selected = nil
  local selectedHealth = 101
  for _, creature in pairs(spectators) do
    local isPlayer = creature ~= nil and type(creature.isPlayer) == 'function' and creature:isPlayer()
    local creatureId = isPlayer and type(creature.getId) == 'function' and creature:getId() or 0
    local position = isPlayer and type(creature.getPosition) == 'function' and creature:getPosition() or nil
    if isPlayer and creatureId ~= playerId and position ~= nil and position.z == playerPosition.z then
      local modeMatches = false
      if customMode and type(creature.getName) == 'function' then
        modeMatches = creature:getName():lower() == wantedName
      elseif partyMode then
        modeMatches = isPartyTarget(creature) and matchesVocation(creature, integer(rule.hits, 0))
      elseif guildMode then
        modeMatches = isGuildTarget(creature) and matchesVocation(creature, integer(rule.hits, 0))
      end

      local sightClear = g_map == nil or type(g_map.isSightClear) ~= 'function' or
          g_map.isSightClear(playerPosition, position)
      local health = type(creature.getHealthPercent) == 'function' and creature:getHealthPercent() or 100
      if modeMatches and sightClear and inConfiguredRange(health, rule.min, rule.max) and health < selectedHealth then
        selected = creature
        selectedHealth = health
      end
    end
  end
  return selected
end

local function executeGroupHealing(player, at)
  if not state.toggles[6] then
    return false
  end
  local spectators = getSpectators(player:getPosition())
  for _, rule in ipairs(state.modules[6]) do
    if ruleReady(rule, player, at) then
      local target = findGroupTarget(rule, player, spectators)
      if target ~= nil then
        if rule.area == 'utura tio' and at >= rule._primedUntil then
          if type(g_game.talk) == 'function' then
            g_game.talk('utura tio')
            rule._primedUntil = at + 30000
            rule._nextAt = at + 500
            state.nextGlobalActionAt = at + 175
            return true
          end
        elseif rule.item > 0 and useInventoryItem(player, rule.item, target, false) then
          markRuleAction(rule, at, 500, true)
          return true
        elseif rule.spell ~= '' and type(target.getName) == 'function' then
          return castSpell(rule, rule.spell .. ' "' .. target:getName() .. '"', at, 500)
        end
      end
    end
  end
  return false
end

local function itemFallbackReady(rule, player, at)
  if not rule.enabled or at < rule._nextAt then
    return false
  end
  if rule.ignorePz and isInProtectionZone(player) then
    return false
  end
  return rule.harmony <= 0 or getHarmony(player) >= rule.harmony
end

local function manaShieldTrigger(rule, player, monsterCount, includeFear)
  local healthTrigger = rule.max > 0 and getHealthPercent(player) <= rule.max
  local creatureTrigger = rule.hits > 0 and monsterCount >= rule.hits
  local fearTrigger = includeFear and rule.use and isFeared(player)
  return healthTrigger or creatureTrigger or fearTrigger
end

local function executeManaShield(player, at, monsterCount)
  local shielded = hasManaShield(player)
  for moduleType = 13, 14 do
    if state.toggles[moduleType] then
      for _, rule in ipairs(state.modules[moduleType]) do
        local renew = shielded and rule.manaMin > 0 and getMagicShieldPercent(player) <= rule.manaMin
        local activate = not shielded and manaShieldTrigger(rule, player, monsterCount, moduleType == 14)
        if renew or activate then
          if moduleType == 13 and rule.spell ~= '' and ruleReady(rule, player, at) then
            return castSpell(rule, rule.spell, at, 500)
          end
          if rule.item > 0 and itemFallbackReady(rule, player, at) and
              useInventoryItem(player, rule.item, player, false) then
            markRuleAction(rule, at, 500, true)
            return true
          end
        end
      end
    end
  end

  if state.toggles[15] and shielded then
    for _, rule in ipairs(state.modules[15]) do
      local healthReady = rule.max > 0 and getHealthPercent(player) >= rule.max
      local creaturesReady = rule.hits <= 0 or monsterCount <= rule.hits
      local fearReady = not rule.use or not isFeared(player)
      if healthReady and creaturesReady and fearReady and ruleReady(rule, player, at) and
          executeRuleAction(rule, player, player, at, false) then
        return true
      end
    end
  end
  return false
end

local function getAttackTarget(player)
  if type(g_game.getAttackingCreature) ~= 'function' then
    return nil
  end
  local target = g_game.getAttackingCreature()
  if target ~= nil and isValidMonster(target, player:getPosition()) then
    return target
  end
  return nil
end

local function executeShooter(player, at, monsters)
  if not state.toggles[0] then
    return false
  end
  local target = getAttackTarget(player)
  if target == nil then
    return false
  end
  local health = getHealthPercent(player)
  local mana = getManaPercent(player)
  for _, rule in ipairs(state.modules[0]) do
    local healthReady = rule.health <= 0 or health <= rule.health
    local manaReady = rule.mana <= 0 or mana >= rule.mana
    local hitsRequired = math.max(1, integer(rule.hits, 1))
    if healthReady and manaReady and ruleReady(rule, player, at) then
      local hitCount = countMonstersInRuleArea(rule, player, target, monsters)
      local turnDirection = nil
      local directional = rule.area:sub(-4) == '_dir'
      if rule.smart and directional and rule.spell ~= '' and type(g_game.turn) == 'function' then
        local bestDirection, currentDirection
        hitCount, bestDirection, currentDirection = bestDirectionalShooterDirection(
          rule, player, target, monsters)
        if bestDirection ~= currentDirection then
          turnDirection = bestDirection
        end
      end

      if hitCount >= hitsRequired then
      if rule.item > 0 and useInventoryItem(player, rule.item, target, false) then
        markRuleAction(rule, at, 500, true)
        return true
      elseif rule.spell ~= '' then
        if turnDirection ~= nil then
          g_game.turn(turnDirection)
        end
        return castSpell(rule, rule.spell, at, 500)
      end
      end
    end
  end
  return false
end

local function executeCombatTimers(player, at, monsterCount)
  if not state.toggles[3] then
    return false
  end
  for _, rule in ipairs(state.modules[3]) do
    local minimumReady = rule.manaMin <= 0 or monsterCount >= rule.manaMin
    local maximumReady = rule.manaMax <= 0 or monsterCount <= rule.manaMax
    if minimumReady and maximumReady and ruleReady(rule, player, at) and
        executeRuleAction(rule, player, player, at, false) then
      rule._nextAt = at + math.max(500, rule.max * 1000)
      return true
    end
  end
  return false
end

local function executeHaste(player, at)
  if not state.toggles[4] or hasHaste(player) then
    return false
  end
  for _, rule in ipairs(state.modules[4]) do
    if ruleReady(rule, player, at) and rule.spell ~= '' then
      return castSpell(rule, rule.spell, at, 1000)
    end
  end
  return false
end

local function executeAntiParalyze(player, at)
  if not state.toggles[17] or not isParalyzed(player) then
    return false
  end
  -- Rules are registered in the same left-to-right order shown by the PvP
  -- page. The first spell whose mana/PZ/cooldown gates pass wins this cycle.
  for _, rule in ipairs(state.modules[17]) do
    if rule.spell ~= '' and ruleReady(rule, player, at) and
        castSpell(rule, rule.spell, at, 500) then
      return true
    end
  end
  return false
end

local function itemMatchesRule(itemId, rule)
  return itemId == rule.item or contains(rule.itemGroup, itemId)
end

local function hasIgnoredEquipment(player, ignoredIds)
  if #ignoredIds == 0 or type(player.getInventoryItem) ~= 'function' then
    return false
  end
  local firstSlot = InventorySlotFirst or 1
  local lastSlot = InventorySlotLast or 10
  for slot = firstSlot, lastSlot do
    local item = player:getInventoryItem(slot)
    if item ~= nil and type(item.getId) == 'function' and contains(ignoredIds, item:getId()) then
      return true
    end
  end
  return false
end

local function findContainerItem(itemId)
  if g_game == nil or type(g_game.findItemInContainers) ~= 'function' then
    return nil
  end
  return g_game.findItemInContainers(itemId, -1)
end

local function findOpenContainerPosition()
  if g_game == nil or type(g_game.getContainers) ~= 'function' then
    return nil
  end
  for _, container in pairs(g_game.getContainers() or {}) do
    if container ~= nil and type(container.getSize) == 'function' and
        type(container.getCapacity) == 'function' and type(container.getSlotPosition) == 'function' then
      local size = container:getSize()
      if size < container:getCapacity() then
        return container:getSlotPosition(size)
      end
    end
  end
  return nil
end

local function executeEquipmentModule(moduleType, slot, player, at)
  if not state.toggles[moduleType] or type(player.getInventoryItem) ~= 'function' then
    return false
  end
  local health = getHealthPercent(player)
  local mana = getManaPercent(player)
  for _, rule in ipairs(state.modules[moduleType]) do
    if ruleReady(rule, player, at) and inConfiguredRange(health, rule.min, rule.max) and
        inConfiguredRange(mana, rule.manaMin, rule.manaMax) and not hasIgnoredEquipment(player, rule.spellGroup) then
      local equipped = player:getInventoryItem(slot)
      local equippedId = equipped ~= nil and type(equipped.getId) == 'function' and equipped:getId() or 0
      if rule.use then
        if equipped ~= nil and itemMatchesRule(equippedId, rule) and type(g_game.move) == 'function' then
          local destination = findOpenContainerPosition()
          if destination ~= nil then
            local count = type(equipped.getCount) == 'function' and equipped:getCount() or 1
            g_game.move(equipped, destination, count)
            markRuleAction(rule, at, 500, true)
            return true
          end
        end
      elseif not itemMatchesRule(equippedId, rule) and itemCount(player, rule.item) > 0 then
        local found = findContainerItem(rule.item)
        if found ~= nil and type(g_game.equipItem) == 'function' then
          g_game.equipItem(found)
          markRuleAction(rule, at, 500, true)
          return true
        elseif type(g_game.equipItemId) == 'function' then
          g_game.equipItemId(rule.item, 0)
          markRuleAction(rule, at, 500, true)
          return true
        end
      end
    end
  end
  return false
end

local function executeTankMode(player, at)
  if not state.toggles[16] or type(player.getInventoryItem) ~= 'function' then
    return false
  end
  local tankSlots = {
    [3081] = InventorySlotNeck or 2,   -- Stone Skin Amulet
    [3048] = InventorySlotFinger or 9 -- Might Ring
  }
  for _, rule in ipairs(state.modules[16]) do
    local slot = tankSlots[rule.item]
    if slot ~= nil and ruleReady(rule, player, at) then
      local equipped = player:getInventoryItem(slot)
      local equippedId = equipped ~= nil and type(equipped.getId) == 'function' and
        equipped:getId() or 0
      if equippedId ~= rule.item and itemCount(player, rule.item) > 0 then
        local found = findContainerItem(rule.item)
        if found ~= nil and type(g_game.equipItem) == 'function' then
          g_game.equipItem(found)
          markRuleAction(rule, at, 500, true)
          return true
        elseif type(g_game.equipItemId) == 'function' then
          g_game.equipItemId(rule.item, 0)
          markRuleAction(rule, at, 500, true)
          return true
        end
      end
    end
  end
  return false
end

local function executeAmmoRefill(player, at)
  if not state.toggles[9] or at < state.moduleTicks[9] or type(player.getInventoryItem) ~= 'function' then
    return false
  end
  state.moduleTicks[9] = at + 750
  local slot = InventorySlotAmmo or 10
  for _, rule in ipairs(state.modules[9]) do
    if rule.enabled and rule.item > 0 then
      local equipped = player:getInventoryItem(slot)
      local equippedId = equipped ~= nil and type(equipped.getId) == 'function' and equipped:getId() or 0
      local equippedCount = equipped ~= nil and type(equipped.getCount) == 'function' and equipped:getCount() or 0
      local available = itemCount(player, rule.item)
      local needsAmmo = equippedId ~= rule.item and available > 0 or
          equippedId == rule.item and equippedCount < 100 and available > equippedCount
      if needsAmmo then
        local found = findContainerItem(rule.item)
        if found ~= nil and type(g_game.equipItem) == 'function' then
          g_game.equipItem(found)
          markRuleAction(rule, at, 500, true)
          return true
        elseif type(g_game.equipItemId) == 'function' then
          g_game.equipItemId(rule.item, 0)
          markRuleAction(rule, at, 500, true)
          return true
        end
      end
    end
  end
  return false
end

local function executeAutoEat(player, at)
  if not state.toggles[8] or at < state.moduleTicks[8] then
    return false
  end
  for _, rule in ipairs(state.modules[8]) do
    if rule.enabled and rule.item > 0 and useInventoryItem(player, rule.item, player, true) then
      state.moduleTicks[8] = at + 60000
      markRuleAction(rule, at, 60000, true)
      return true
    end
  end
  state.moduleTicks[8] = at + 1000
  return false
end

local function findCoinStack(itemId)
  if type(g_game.getContainers) ~= 'function' then
    return nil
  end
  for _, container in pairs(g_game.getContainers() or {}) do
    if container ~= nil and type(container.getItems) == 'function' then
      for _, item in pairs(container:getItems() or {}) do
        if item ~= nil and type(item.getId) == 'function' and item:getId() == itemId and
            type(item.getCount) == 'function' and item:getCount() >= 100 then
          return item
        end
      end
    end
  end
  return nil
end

local function executeChangeGold(at)
  if not state.toggles[7] or at < state.moduleTicks[7] or type(g_game.use) ~= 'function' then
    return false
  end
  state.moduleTicks[7] = at + 250
  local stack = findCoinStack(PLATINUM_COIN) or findCoinStack(GOLD_COIN)
  if stack ~= nil then
    g_game.use(stack)
    state.nextGlobalActionAt = at + 175
    return true
  end
  return false
end

local function findTrainingDummy(playerPosition, dummyIds)
  if g_map == nil or type(g_map.getTile) ~= 'function' then
    return nil
  end
  local selected = nil
  local selectedDistance = 9999
  for y = -7, 7 do
    for x = -7, 7 do
      local position = { x = playerPosition.x + x, y = playerPosition.y + y, z = playerPosition.z }
      local tile = g_map.getTile(position)
      if tile ~= nil and type(tile.getItems) == 'function' then
        for _, item in pairs(tile:getItems() or {}) do
          if item ~= nil and type(item.getId) == 'function' and contains(dummyIds, item:getId()) then
            local distance = math.max(math.abs(x), math.abs(y))
            local clear = type(g_map.isSightClear) ~= 'function' or g_map.isSightClear(playerPosition, position)
            if clear and distance < selectedDistance then
              selected = item
              selectedDistance = distance
            end
          end
        end
      end
    end
  end
  return selected
end

local function executeAutoTraining(player, at)
  if not state.toggles[12] or at < state.moduleTicks[12] then
    return false
  end
  for _, rule in ipairs(state.modules[12]) do
    if rule.enabled and rule.item > 0 and #rule.spellGroup > 0 and itemCount(player, rule.item) > 0 then
      local dummy = findTrainingDummy(player:getPosition(), rule.spellGroup)
      if dummy ~= nil and useInventoryItem(player, rule.item, dummy, false) then
        -- A successful use starts a recurring server-side training event. The
        -- server also enforces a 30-second restart cooldown, so retrying every
        -- action cycle only interrupts training or floods rejection messages.
        state.moduleTicks[12] = at + AUTO_TRAINING_RETRY_INTERVAL
        markRuleAction(rule, at, AUTO_TRAINING_RETRY_INTERVAL, true)
        return true
      end
    end
  end
  state.moduleTicks[12] = at + 1000
  return false
end

local function executeAutoMount(player, at)
  if not state.toggles[22] or at < state.moduleTicks[22] or isInProtectionZone(player) then
    return false
  end
  local configured = false
  for _, rule in ipairs(state.modules[22]) do
    if rule.enabled then
      configured = true
      break
    end
  end
  if not configured then
    return false
  end
  state.moduleTicks[22] = at + 2000
  local mounted = type(player.isMounted) == 'function' and player:isMounted()
  if not mounted and type(g_game.mount) == 'function' then
    g_game.mount(true)
    state.nextGlobalActionAt = at + 175
    return true
  end
  return false
end

local function chooseAttackTarget(player, monsters)
  local configuredMode = integer(state.autoAttack, 0)
  if configuredMode <= 0 then
    return nil
  end

  local meleeOnly = false
  local mode = configuredMode
  if mode >= 300 then
    mode = mode - 100
    meleeOnly = true
  elseif mode >= 100 and mode < 200 then
    mode = mode - 100
    meleeOnly = true
  end

  local playerPosition = player:getPosition()
  local selected = nil
  local selectedDistance = 9999
  local selectedHealth = mode == 3 and -1 or 101
  local selectedCluster = -1
  for _, creature in ipairs(monsters) do
    local position = creature:getPosition()
    local distance = tileDistance(playerPosition, position)
    if not meleeOnly or distance <= 1 then
      local health = creature:getHealthPercent()
      local choose = false
      if mode == 2 then
        choose = health < selectedHealth or (health == selectedHealth and distance < selectedDistance)
      elseif mode == 3 then
        choose = health > selectedHealth or (health == selectedHealth and distance < selectedDistance)
      elseif mode == 200 then
        local cluster = 0
        for _, other in ipairs(monsters) do
          if tileDistance(position, other:getPosition()) <= 2 then
            cluster = cluster + 1
          end
        end
        choose = cluster > selectedCluster or
            (cluster == selectedCluster and distance < selectedDistance) or
            (cluster == selectedCluster and distance == selectedDistance and health < selectedHealth)
        if choose then
          selectedCluster = cluster
        end
      else
        choose = distance < selectedDistance or (distance == selectedDistance and health < selectedHealth)
      end

      if choose then
        selected = creature
        selectedDistance = distance
        selectedHealth = health
      end
    end
  end
  return selected
end

local function stepAutoAttack(player, at, monsters)
  if state.autoAttack <= 0 or at < state.lastAttackCheck or isInProtectionZone(player) then
    return false
  end
  state.lastAttackCheck = at + 350
  local selected = chooseAttackTarget(player, monsters)
  local current = type(g_game.getAttackingCreature) == 'function' and g_game.getAttackingCreature() or nil
  if selected ~= nil then
    local selectedId = type(selected.getId) == 'function' and selected:getId() or 0
    local currentId = current ~= nil and type(current.getId) == 'function' and current:getId() or 0
    if selectedId ~= currentId and type(g_game.attack) == 'function' and canPerformAction() then
      g_game.attack(selected)
      state.nextGlobalActionAt = math.max(state.nextGlobalActionAt, at + 100)
      return true
    end
  elseif current ~= nil and type(g_game.cancelAttack) == 'function' then
    g_game.cancelAttack()
    return true
  end
  return false
end

local function stopWalking(force)
  local shouldStopMovement = force == true or state.walkCommandKind ~= nil
  if shouldStopMovement then
    local player = getPlayer()
    if player ~= nil and type(player.stopAutoWalk) == 'function' then
      player:stopAutoWalk()
    end
    if isOnline() and type(g_game.stop) == 'function' then
      g_game.stop()
    end
  end
  state.walkCommandKind = nil
  state.explorerTarget = nil
  state.teleportStartPosition = nil
end

local function emitWalkSignal(signalName, ...)
  local signal = api[signalName]
  if signal ~= nil and type(signalcall) == 'function' then
    signalcall(signal, ...)
  end
end

local function nextWaypoint()
  if #state.waypoints == 0 then
    return nil
  end
  for _, waypoint in ipairs(state.waypoints) do
    if waypoint.index > state.currentWalkIndex then
      return waypoint
    end
  end
  state.currentWalkIndex = 0
  return state.waypoints[1]
end

local function announceWaypoint(waypoint)
  if waypoint ~= nil and state.announcedWalkIndex ~= waypoint.index then
    state.announcedWalkIndex = waypoint.index
    emitWalkSignal('onWalkToNextNode', waypoint.index)
  end
end

local function shouldPauseMovement(monsterCount, stopAt, resumeAt, paused)
  if stopAt <= 0 then
    return false
  end
  if paused then
    local resume = resumeAt > 0 and resumeAt or math.max(0, stopAt - 1)
    return monsterCount > resume
  end
  return monsterCount >= stopAt
end

local function failRecorder(code)
  state.walkFailureCount = state.walkFailureCount + 1
  state.walkNextAt = nowMillis() + 1000
  emitWalkSignal('onWalkFailed', code, 5)
end

local function completeWaypoint(waypoint)
  state.currentWalkIndex = waypoint.index
  state.walkFailureCount = 0
  state.teleportStartPosition = nil
  local upcoming = nextWaypoint()
  state.announcedWalkIndex = 0
  announceWaypoint(upcoming)
end

-- Movement mirrors the keyboard mode of the client's own cavebot
-- (mods/game_helper/cavebot_panel.lua): ask the map for a route and send a
-- single step per tick.  Handing the whole route to LocalPlayer::autoWalk does
-- not work here, because every call wipes the pending destination, cancels the
-- queued continuation event and re-arms a 200ms walk lock, so re-sending it on
-- each tick fights the engine and pins the player in place.
local PATH_FLAGS = 53        -- AllowNotSeenTiles + AllowNonPathable + IgnoreCreatures + BlockFloorChange
local PATH_FLAGS_STRICT = 37 -- same without IgnoreCreatures, so we walk around them

-- Temporary walk diagnostics.  Set to false to silence.
local WALK_DEBUG = false
local walkDebugAt = 0

local function walkDiag(message)
  if not WALK_DEBUG then
    return
  end
  local now = nowMillis()
  if now - walkDebugAt < 1000 then
    return
  end
  walkDebugAt = now
  if type(g_logger) == 'table' and type(g_logger.info) == 'function' then
    g_logger.info('[minibot-walk] ' .. tostring(message))
  end
end

local function describePosition(position)
  if type(position) ~= 'table' then
    return 'nil'
  end
  return string.format('(%s,%s,%s)', tostring(position.x), tostring(position.y), tostring(position.z))
end

local function findWalkStep(from, to)
  local ok, path = pcall(function()
    return g_map.findPath(from, to, 1000, PATH_FLAGS_STRICT)
  end)
  if ok and type(path) == 'table' and #path > 0 then
    return path[1]
  end
  ok, path = pcall(function()
    return g_map.findPath(from, to, 40000, PATH_FLAGS)
  end)
  if ok and type(path) == 'table' and #path > 0 then
    return path[1]
  end
  return nil
end

-- Pace the steps off the character's real step duration so the bot can never
-- outrun the server; `speed` only trims the safety margin on top of it.
local function walkStepDelay(player, direction, speed, lure)
  local stepDuration = 100
  if type(player.getStepDuration) == 'function' then
    -- Pass the direction: a diagonal step costs about three times a straight
    -- one, and pacing them all as straight steps is what makes it stutter.
    stepDuration = integer(player:getStepDuration(false, direction), 100)
  end
  if stepDuration < 50 then
    stepDuration = 100
  end
  -- Stay flush against the step duration so the character walks continuously.
  -- Game::walk queues a step that lands early (isKeyDown), so a tight margin is
  -- safe, while a wide one reads as stop-and-go.
  local margin = math.max(0, 30 - math.max(1, math.min(20, integer(speed, 5))) * 2)
  if lure then
    margin = margin + 150
  end
  return stepDuration + margin
end

local function stepRecorder(player, at, monsterCount)
  if not state.toggles[5] then
    return false
  end
  local waypoint = nextWaypoint()
  if waypoint == nil then
    walkDiag(string.format('no waypoint (count=%d, currentIndex=%d)',
        #state.waypoints, state.currentWalkIndex))
    return false
  end
  announceWaypoint(waypoint)

  local position = player:getPosition()
  local wasPaused = state.walkPaused
  local reachedWaypointArea = tileDistance(position, waypoint.position) <= 1
  if state.walkPaused or reachedWaypointArea then
    state.walkPaused = shouldPauseMovement(
        monsterCount, waypoint.creatures, waypoint.resume, state.walkPaused)
  end
  if state.walkPaused then
    walkDiag(string.format('paused at index %d (monsters=%d, stopAt=%s, resumeAt=%s)',
        waypoint.index, monsterCount, tostring(waypoint.creatures), tostring(waypoint.resume)))
    if not wasPaused or state.walkCommandKind ~= nil then
      stopWalking(true)
    end
    return false
  end

  if waypoint.teleport then
    if state.teleportStartPosition ~= nil and
        (position.z ~= state.teleportStartPosition.z or tileDistance(position, state.teleportStartPosition) > 2) then
      completeWaypoint(waypoint)
      return true
    end
    if samePosition(position, waypoint.position) then
      if state.teleportStartPosition == nil then
        state.teleportStartPosition = copyPosition(position)
        state.walkNextAt = at + 1500
      end
      return false
    end
  elseif samePosition(position, waypoint.position) then
    completeWaypoint(waypoint)
    return true
  end

  if position.z ~= waypoint.position.z then
    walkDiag(string.format('floor mismatch: player %s vs waypoint %d %s - disabling cavebot',
        describePosition(position), waypoint.index, describePosition(waypoint.position)))
    failRecorder(0)
    api.setModuleToggle(5, false)
    return false
  end
  if at < state.walkNextAt then
    return false
  end

  local direction = findWalkStep(position, waypoint.position)
  if direction == nil then
    walkDiag(string.format('no path from %s to waypoint %d %s',
        describePosition(position), waypoint.index, describePosition(waypoint.position)))
    failRecorder(1)
    return false
  end

  state.walkNextAt = at + walkStepDelay(player, direction, waypoint.speed, waypoint.lure)
  state.walkCommandKind = 'recorder'
  state.walkFailureCount = 0
  -- isKeyDown=true so Game::walk queues a step that lands while the previous
  -- one is still running; with false the engine silently drops it.
  local walked = g_game.walk(direction, true)
  walkDiag(string.format('step dir=%s from %s -> waypoint %d %s (g_game.walk returned %s)',
      tostring(direction), describePosition(position), waypoint.index,
      describePosition(waypoint.position), tostring(walked)))
  return true
end

local EXPLORER_OFFSETS = {
  { 5, 0 }, { 0, 5 }, { -5, 0 }, { 0, -5 },
  { 4, 4 }, { -4, 4 }, { -4, -4 }, { 4, -4 }
}

local EXPLORER_LURE_OFFSETS = {
  { 2, 0 }, { 0, 2 }, { -2, 0 }, { 0, -2 },
  { 2, 2 }, { -2, 2 }, { -2, -2 }, { 2, -2 }
}

local function findExplorerDestination(position, lureCreatures)
  if g_map == nil or type(g_map.getTile) ~= 'function' then
    return nil
  end
  local offsets = lureCreatures and EXPLORER_LURE_OFFSETS or EXPLORER_OFFSETS
  local scaleCount = lureCreatures and 1 or 3
  for offsetIndex = 0, #offsets - 1 do
    local index = ((state.explorerDirection + offsetIndex - 1) % #offsets) + 1
    local offset = offsets[index]
    for scale = 1, scaleCount do
      local divisor = scale == 1 and 1 or scale
      local candidate = {
        x = position.x + math.floor(offset[1] / divisor),
        y = position.y + math.floor(offset[2] / divisor),
        z = position.z
      }
      local tile = g_map.getTile(candidate)
      local walkable = tile ~= nil and type(tile.isWalkable) == 'function' and tile:isWalkable(false)
      local pathable = tile == nil or type(tile.isPathable) ~= 'function' or tile:isPathable()
      if walkable and pathable then
        state.explorerDirection = (index % #offsets) + 1
        return candidate
      end
    end
  end
  return nil
end

local function stepExplorer(player, at, monsterCount)
  if not state.toggles[21] or state.toggles[5] or at < state.walkNextAt then
    return false
  end
  local config = state.explorer
  local wasPaused = state.explorerPaused
  state.explorerPaused = shouldPauseMovement(monsterCount, config.findCreatures,
      config.resumeCreatures, state.explorerPaused)
  if state.explorerPaused then
    if not wasPaused or state.walkCommandKind ~= nil then
      stopWalking(true)
    end
    state.walkNextAt = at + 250
    return false
  end

  local position = player:getPosition()
  if state.explorerTarget == nil or tileDistance(position, state.explorerTarget) <= 1 then
    state.explorerTarget = findExplorerDestination(position, config.lureCreatures)
  end
  if state.explorerTarget == nil then
    state.explorerFailures = state.explorerFailures + 1
    state.walkNextAt = at + 1000
    if state.explorerFailures >= 3 then
      state.toggles[21] = false
      emitWalkSignal('onWalkFailed', 1, 21)
    end
    return false
  end

  local direction = findWalkStep(position, state.explorerTarget)
  if direction == nil then
    state.explorerTarget = nil
    state.explorerFailures = state.explorerFailures + 1
    state.walkNextAt = at + 500
    return false
  end

  state.walkNextAt = at + walkStepDelay(player, direction, 5, config.lureCreatures)
  state.walkCommandKind = 'explorer'
  state.explorerFailures = 0
  g_game.walk(direction, true)
  return true
end

local function sendCavebotState(enabled)
  if not isOnline() then
    return false
  end
  local payload = enabled and '1' or '0'
  if state.lastSentCavebotState == payload then
    return false
  end
  if type(g_game.getProtocolGame) ~= 'function' then
    return false
  end
  local protocol = g_game.getProtocolGame()
  if protocol == nil or type(protocol.sendExtendedOpcode) ~= 'function' then
    return false
  end
  protocol:sendExtendedOpcode(CAVEBOT_OPCODE, payload)
  state.lastSentCavebotState = payload
  return true
end

function api.resetModule(moduleType)
  moduleType = integer(moduleType, -1)
  if moduleType < 0 or moduleType > 22 then
    return false
  end
  state.modules[moduleType] = {}
  state.moduleTicks[moduleType] = 0
  return true
end

function api.addModule(moduleType, rule)
  moduleType = integer(moduleType, -1)
  if moduleType < 0 or moduleType > 22 or type(rule) ~= 'table' then
    return false
  end
  local normalized = normalizeRule(rule)
  table.insert(state.modules[moduleType], normalized)
  return #state.modules[moduleType]
end

function api.setModuleToggle(moduleType, enabled)
  moduleType = integer(moduleType, -1)
  if moduleType < 0 or moduleType > 22 then
    return false
  end
  enabled = enabled == true

  -- A bot-check alarm is a hard safety boundary.  Reject every attempt to
  -- re-enable either movement executor until the server explicitly ends it;
  -- UI code also mirrors this state, but the runtime must remain authoritative.
  if enabled and (moduleType == 5 or moduleType == 21) and
      MiniBotCompat ~= nil and type(MiniBotCompat.getBotCheckAlarmState) == 'function' then
    local ok, alarmState = pcall(MiniBotCompat.getBotCheckAlarmState)
    if ok and type(alarmState) == 'table' and alarmState.active == true then
      return false
    end
  end

  local changed = state.toggles[moduleType] ~= enabled
  if not changed then
    return false
  end

  if enabled and moduleType == 5 and state.toggles[21] then
    stopWalking(true)
    state.toggles[21] = false
  elseif enabled and moduleType == 21 and state.toggles[5] then
    stopWalking(true)
    state.toggles[5] = false
    sendCavebotState(false)
  end

  state.toggles[moduleType] = enabled
  state.moduleTicks[moduleType] = 0
  if moduleType == 5 then
    state.walkPaused = false
    state.walkFailureCount = 0
    state.announcedWalkIndex = 0
    state.walkNextAt = 0
    if not enabled then
      stopWalking(true)
    end
    sendCavebotState(enabled)
  elseif moduleType == 21 then
    state.explorerPaused = false
    state.explorerFailures = 0
    state.explorerTarget = nil
    state.walkNextAt = 0
    if not enabled then
      stopWalking(true)
    end
  end
  return true
end

function api.isModuleToggle(moduleType)
  return state.toggles[integer(moduleType, -1)] == true
end

function api.setModuleTimeTick(moduleType, tick)
  moduleType = integer(moduleType, -1)
  if moduleType < 0 or moduleType > 22 then
    return false
  end
  state.moduleTicks[moduleType] = nonNegative(tick)
  return true
end

function api.setAutoAttack(attackType)
  state.autoAttack = math.max(0, integer(attackType, 0))
  state.lastAttackCheck = 0
  if state.autoAttack == 0 and type(g_game.getAttackingCreature) == 'function' and
      g_game.getAttackingCreature() ~= nil and type(g_game.cancelAttack) == 'function' then
    g_game.cancelAttack()
  end
  return state.autoAttack
end

function api.getAutoAttack()
  return state.autoAttack
end

function api.resetRecorderSession()
  stopWalking(false)
  state.waypoints = {}
  state.currentWalkIndex = 0
  state.announcedWalkIndex = 0
  state.walkNextAt = 0
  state.walkPaused = false
  state.walkFailureCount = 0
  return true
end

function api.registerWalkWaypoint(point)
  if type(point) ~= 'table' then
    return false
  end
  local position = copyPosition(point.position)
  local index = integer(point.index, 0)
  if position == nil or index <= 0 then
    return false
  end
  local waypoint = {
    position = position,
    creatures = nonNegative(point.creatures),
    resume = nonNegative(point.resume),
    lure = point.lure == true,
    speed = math.max(1, math.min(20, integer(point.speed, 5))),
    index = index,
    teleport = point.teleport == true
  }
  local replaced = false
  for listIndex, existing in ipairs(state.waypoints) do
    if existing.index == index then
      state.waypoints[listIndex] = waypoint
      replaced = true
      break
    end
  end
  if not replaced then
    table.insert(state.waypoints, waypoint)
  end
  table.sort(state.waypoints, function(first, second)
    return first.index < second.index
  end)

  -- Older Recorder builds marked both the origin and destination of every
  -- floor transition as teleport nodes.  Normalize the second half in memory
  -- so existing routes do not wait for another floor change at the arrival.
  for waypointIndex = 2, #state.waypoints do
    local previous = state.waypoints[waypointIndex - 1]
    local current = state.waypoints[waypointIndex]
    if previous.teleport and current.teleport and
        (previous.position.z ~= current.position.z or
         tileDistance(previous.position, current.position) > 1) then
      current.teleport = false
    end
  end
  return true
end

function api.setCurrentWalkIndex(index)
  state.currentWalkIndex = math.max(0, integer(index, 0))
  state.announcedWalkIndex = 0
  state.teleportStartPosition = nil
  state.walkNextAt = 0
  return state.currentWalkIndex
end

function api.getCurrentWalkIndex()
  return state.currentWalkIndex
end

function api.setExplorerWalker(value)
  value = type(value) == 'table' and value or {}
  state.explorer = {
    findCreatures = nonNegative(value.findCreatures),
    resumeCreatures = nonNegative(value.resumeCreatures),
    lureCreatures = value.lureCreatures == true
  }
  state.explorerPaused = false
  state.explorerTarget = nil
  state.walkNextAt = 0
  return true
end

function api.applyServerCavebotState(enabled)
  enabled = enabled == true
  local wasEnabled = state.toggles[5]
  state.lastSentCavebotState = enabled and '1' or '0'
  if enabled and state.toggles[21] then
    stopWalking(true)
    state.toggles[21] = false
  end
  state.toggles[5] = enabled
  state.walkPaused = false
  state.walkFailureCount = 0
  state.walkNextAt = 0
  if wasEnabled and not enabled then
    stopWalking(true)
  end
  return true
end

function runtime.applyServerCavebotState(enabled)
  return api.applyServerCavebotState(enabled)
end

function api.reset()
  local cavebotWasEnabled = state.toggles[5]
  local explorerWasEnabled = state.toggles[21]
  stopWalking(cavebotWasEnabled or explorerWasEnabled)
  for moduleType = 0, 22 do
    state.modules[moduleType] = {}
    state.toggles[moduleType] = false
    state.moduleTicks[moduleType] = 0
  end
  state.autoAttack = 0
  state.spellCooldowns = {}
  state.groupCooldowns = {}
  state.multiUseCooldownUntil = 0
  state.nextGlobalActionAt = 0
  state.lastAttackCheck = 0
  state.waypoints = {}
  state.currentWalkIndex = 0
  state.announcedWalkIndex = 0
  state.walkPaused = false
  state.explorerPaused = false
  state.explorerTarget = nil
  state.virtueUntil = 0
  if cavebotWasEnabled then
    sendCavebotState(false)
  end
  return true
end

local function runActionPass(player, at, monsters)
  if at < state.nextGlobalActionAt or not canPerformAction() then
    return false
  end
  local monsterCount = #monsters
  return executeAntiParalyze(player, at) or
      executeHealthHealing(player, at) or
      executeManaHealing(player, at) or
      executeGroupHealing(player, at) or
      executeManaShield(player, at, monsterCount) or
      executeTankMode(player, at) or
      executeShooter(player, at, monsters) or
      executeCombatTimers(player, at, monsterCount) or
      executeHaste(player, at) or
      executeEquipmentModule(10, InventorySlotNeck or 2, player, at) or
      executeEquipmentModule(11, InventorySlotFinger or 9, player, at) or
      executeAmmoRefill(player, at) or
      executeAutoEat(player, at) or
      executeChangeGold(at) or
      executeAutoTraining(player, at) or
      executeAutoMount(player, at)
end

local function runCycle()
  if not isOnline() then
    return
  end
  local player = getPlayer()
  if player == nil or type(player.getPosition) ~= 'function' then
    return
  end
  local at = nowMillis()
  local monsters = visibleMonsters(player)
  stepAutoAttack(player, at, monsters)
  if state.toggles[5] then
    stepRecorder(player, at, #monsters)
  elseif state.toggles[21] then
    stepExplorer(player, at, #monsters)
  end
  runActionPass(player, at, monsters)
end

local loop
loop = function()
  state.loopEvent = nil
  if not state.running then
    return
  end
  runCycle()
  if state.running then
    state.loopEvent = scheduleEvent(loop, LOOP_INTERVAL)
  end
end

local function onSpellCooldown(spellId, delay)
  spellId = integer(spellId, 0)
  if spellId > 0 then
    state.spellCooldowns[spellId] = nowMillis() + math.max(0, integer(delay, 0))
  end
end

local function onSpellGroupCooldown(groupId, delay)
  groupId = integer(groupId, 0)
  if groupId > 0 then
    state.groupCooldowns[groupId] = nowMillis() + math.max(0, integer(delay, 0))
  end
end

local function onMultiUseCooldown(delay)
  delay = math.max(0, integer(delay, 0))
  state.multiUseCooldownUntil = math.max(
    state.multiUseCooldownUntil, nowMillis() + delay)
end

local function onGameStart()
  state.lastSentCavebotState = nil
  state.spellCooldowns = {}
  state.groupCooldowns = {}
  state.multiUseCooldownUntil = 0
  state.nextGlobalActionAt = 0
end

local function onGameEnd()
  runtime.stop()
  api.reset()
  state.lastSentCavebotState = nil
end

local function onAutoWalkFail(_, status)
  if state.walkCommandKind == 'recorder' and state.toggles[5] then
    state.walkFailureCount = state.walkFailureCount + 1
    state.walkNextAt = nowMillis() + 750
    if state.walkFailureCount >= 3 then
      emitWalkSignal('onWalkFailed', integer(status, 1), 5)
      state.walkFailureCount = 0
    end
  elseif state.walkCommandKind == 'explorer' and state.toggles[21] then
    state.explorerTarget = nil
    state.explorerFailures = state.explorerFailures + 1
    state.walkNextAt = nowMillis() + 500
    if state.explorerFailures >= 3 then
      state.toggles[21] = false
      emitWalkSignal('onWalkFailed', integer(status, 1), 21)
    end
  end
  state.walkCommandKind = nil
end

function runtime.init()
  publishApi()
  if not state.connected then
    state.gameCallbacks = {
      onGameStart = onGameStart,
      onGameEnd = onGameEnd,
      onSpellCooldown = onSpellCooldown,
      onSpellGroupCooldown = onSpellGroupCooldown,
      onMultiUseCooldown = onMultiUseCooldown
    }
    state.playerCallbacks = {
      onAutoWalkFail = onAutoWalkFail
    }
    connect(g_game, state.gameCallbacks)
    connect(LocalPlayer, state.playerCallbacks)
    state.connected = true
  end
  state.initialized = true
  return true
end

function runtime.start()
  if not state.initialized then
    return runtime.init()
  end
  if state.running then
    return true
  end
  if not isOnline() then
    return true
  end
  state.running = true
  if state.loopEvent == nil then
    state.loopEvent = scheduleEvent(loop, 0)
  end
  return true
end

function runtime.stop()
  if not state.running and state.loopEvent == nil then
    stopWalking(false)
    return true
  end
  state.running = false
  if state.loopEvent ~= nil then
    removeEvent(state.loopEvent)
    state.loopEvent = nil
  end
  stopWalking(false)
  return true
end

function runtime.terminate()
  if state.toggles[5] then
    sendCavebotState(false)
    state.toggles[5] = false
  end
  runtime.stop()
  if state.connected then
    disconnect(g_game, state.gameCallbacks)
    disconnect(LocalPlayer, state.playerCallbacks)
    state.connected = false
  end
  state.initialized = false
  state.gameCallbacks = nil
  state.playerCallbacks = nil
  if rawget(rootEnvironment, 'g_minibot') == api then
    rawset(rootEnvironment, 'g_minibot', nil)
  end
  return true
end

function api.cycle()
  state.nextGlobalActionAt = 0
  state.lastAttackCheck = 0
  return runtime.start()
end

runtime.init()
