local clock = 1000
local online = false
local pendingEvents = {}
local connectCount = 0
local disconnectCount = 0

local actions = {}
local sentOpcodes = {}
local spectators = {}
local containers = {}
local tiles = {}
local inventoryCounts = {}
local inventorySlots = {}
local attackingCreature = nil
local mapWalkable = false
local sightClear = true
local autoWalkAccepted = true
local botCheckAlarmActive = false

PlayerStates = {
  Pz = 1,
  Haste = 2,
  ManaShield = 4,
  NewMagicShield = 8,
  NewManaShield = 8,
  Feared = 16,
  Paralyze = 32
}
EmblemGreen = 1
EmblemMember = 4
InventorySlotFirst = 1
InventorySlotLast = 10
InventorySlotNeck = 2
InventorySlotBack = 3
InventorySlotFinger = 9
InventorySlotAmmo = 10

g_clock = {
  millis = function()
    return clock
  end
}

local function record(kind, data)
  data = data or {}
  data.kind = kind
  table.insert(actions, data)
  return data
end

local function pendingCount()
  local count = 0
  for _ in pairs(pendingEvents) do
    count = count + 1
  end
  return count
end

function scheduleEvent(callback, delay)
  local event = { callback = callback, delay = delay }
  pendingEvents[event] = true
  return event
end

function removeEvent(event)
  pendingEvents[event] = nil
end

function connect(object, callbacks)
  connectCount = connectCount + 1
  for signal, callback in pairs(callbacks) do
    object[signal] = callback
  end
end

function disconnect(object, callbacks)
  disconnectCount = disconnectCount + 1
  for signal, callback in pairs(callbacks) do
    if object[signal] == callback then
      object[signal] = nil
    end
  end
end

function signalcall(signal, ...)
  if type(signal) == 'function' then
    return signal(...)
  elseif type(signal) == 'table' then
    for _, callback in pairs(signal) do
      callback(...)
    end
  end
end

local function makeItem(id, count)
  local item = { id = id, count = count or 1 }
  function item:getId() return self.id end
  function item:getCount() return self.count end
  return item
end

local function makeContainer(items, capacity, baseY)
  local container = {
    items = items or {},
    capacity = capacity or 20,
    baseY = baseY or 64
  }
  function container:getItems() return self.items end
  function container:getSize() return #self.items end
  function container:getCapacity() return self.capacity end
  function container:getSlotPosition(slot)
    return { x = 65535, y = self.baseY, z = slot }
  end
  return container
end

local function makeTile(items, walkable)
  local tile = { items = items or {}, walkable = walkable == true }
  function tile:getItems() return self.items end
  function tile:isWalkable(_) return self.walkable end
  function tile:isPathable() return self.walkable end
  return tile
end

local function makeCreature(options)
  options = options or {}
  local creature = {
    id = options.id or 100,
    name = options.name or 'Creature',
    position = options.position or { x = 101, y = 100, z = 7 },
    health = options.health or 100,
    monster = options.monster == true,
    player = options.player == true,
    dead = options.dead == true,
    masterId = options.masterId or 0,
    vocation = options.vocation,
    party = options.party == true,
    emblem = options.emblem or 0
  }
  function creature:isMonster() return self.monster end
  function creature:isPlayer() return self.player end
  function creature:isDead() return self.dead end
  function creature:getMasterId() return self.masterId end
  function creature:getPosition() return self.position end
  function creature:getHealthPercent() return self.health end
  function creature:getId() return self.id end
  function creature:getName() return self.name end
  function creature:isPartyMember() return self.party end
  function creature:getEmblem() return self.emblem end
  function creature:isKnight() return self.vocation == 'Knight' end
  function creature:isPaladin() return self.vocation == 'Paladin' end
  function creature:isMonk() return self.vocation == 'Monk' end
  function creature:isSorcerer() return self.vocation == 'Sorcerer' end
  function creature:isDruid() return self.vocation == 'Druid' end
  return creature
end

local player = {
  id = 1,
  position = { x = 100, y = 100, z = 7 },
  healthPercent = 100,
  mana = 1000,
  maxMana = 1000,
  harmony = 0,
  pz = false,
  haste = false,
  shield = false,
  magicShield = 1000,
  maxMagicShield = 1000,
  mounted = false,
  feared = false,
  paralyzed = false,
  direction = 0,
  autoWalking = false
}

function player:getId() return self.id end
function player:getPosition() return self.position end
function player:getHealthPercent() return self.healthPercent end
function player:getHealth() return self.healthPercent end
function player:getMaxHealth() return 100 end
function player:getMana() return self.mana end
function player:getMaxMana() return self.maxMana end
function player:getHarmony() return self.harmony end
function player:isInProtectionZone() return self.pz end
function player:hasHaste() return self.haste end
function player:hasManaShield() return self.shield end
function player:isParalyzed() return self.paralyzed end
function player:getMagicShield() return self.magicShield end
function player:getMaxMagicShield() return self.maxMagicShield end
function player:isMounted() return self.mounted end
function player:getDirection() return self.direction end
function player:getInventoryCount(itemId, _)
  return inventoryCounts[itemId] or 0
end
function player:getInventoryItem(slot)
  return inventorySlots[slot]
end
function player:hasCondition(condition)
  if condition == PlayerStates.Pz then return self.pz end
  if condition == PlayerStates.Haste then return self.haste end
  if condition == PlayerStates.ManaShield or condition == PlayerStates.NewMagicShield then return self.shield end
  if condition == PlayerStates.Feared then return self.feared end
  if condition == PlayerStates.Paralyze then return self.paralyzed end
  return false
end
function player:isAutoWalking() return self.autoWalking end
function player:autoWalk(destination, retry)
  record('autoWalk', { destination = destination, retry = retry })
  self.autoWalking = autoWalkAccepted
  return autoWalkAccepted
end
function player:stopAutoWalk()
  self.autoWalking = false
  record('stopAutoWalk')
end

local protocol = {}
function protocol:sendExtendedOpcode(opcode, payload)
  table.insert(sentOpcodes, { opcode = opcode, payload = payload })
end

g_game = {
  isOnline = function() return online end,
  getLocalPlayer = function() return player end,
  canPerformGameAction = function() return true end,
  getProtocolGame = function() return protocol end,
  getAttackingCreature = function() return attackingCreature end,
  getContainers = function() return containers end,
  findItemInContainers = function(itemId, _)
    for _, container in pairs(containers) do
      for _, item in pairs(container:getItems()) do
        if item:getId() == itemId then
          return item
        end
      end
    end
    return nil
  end,
  useInventoryItem = function(itemId, subtype)
    record('useInventoryItem', { itemId = itemId, subtype = subtype })
  end,
  useInventoryItemWith = function(itemId, target, subtype)
    record('useInventoryItemWith', { itemId = itemId, target = target, subtype = subtype })
  end,
  talk = function(words)
    record('talk', { words = words })
  end,
  use = function(item)
    record('use', { item = item })
  end,
  move = function(item, destination, count)
    record('move', { item = item, destination = destination, count = count })
  end,
  equipItem = function(item)
    record('equipItem', { item = item })
  end,
  equipItemId = function(itemId, tier)
    record('equipItemId', { itemId = itemId, tier = tier })
  end,
  mount = function(enabled)
    player.mounted = enabled
    record('mount', { enabled = enabled })
  end,
  attack = function(creature)
    attackingCreature = creature
    record('attack', { creature = creature })
  end,
  cancelAttack = function()
    attackingCreature = nil
    record('cancelAttack')
  end,
  stop = function()
    record('stop')
  end,
  turn = function(direction)
    player.direction = direction
    record('turn', { direction = direction })
  end
}

local function positionKey(position)
  return position.x .. ':' .. position.y .. ':' .. position.z
end

local defaultWalkTile = makeTile({}, true)
g_map = {
  getSpectators = function(_, _)
    return spectators
  end,
  isSightClear = function(_, _)
    return sightClear
  end,
  getTile = function(position)
    local tile = tiles[positionKey(position)]
    if tile ~= nil then
      return tile
    end
    if mapWalkable then
      return defaultWalkTile
    end
    return nil
  end
}

LocalPlayer = {}
g_minibot = nil
MiniBotRuntime = nil
dofile('modules/game_minibot/runtime.lua')
MiniBotCompat = {
  getBotCheckAlarmState = function()
    return { active = botCheckAlarmActive }
  end
}

local function onlyPendingEvent()
  assert(pendingCount() == 1, 'expected exactly one controlled runtime event, got ' .. pendingCount())
  for event in pairs(pendingEvents) do
    return event
  end
end

local function tick(milliseconds)
  clock = clock + (milliseconds or 1000)
  local event = onlyPendingEvent()
  pendingEvents[event] = nil
  event.callback()
  assert(pendingCount() == 1, 'runtime cycle did not leave exactly one successor event')
end

local function clearActions()
  actions = {}
end

local function action(kind)
  for _, entry in ipairs(actions) do
    if entry.kind == kind then
      return entry
    end
  end
  return nil
end

local function assertNoAction(kind, message)
  assert(action(kind) == nil, message or ('unexpected action: ' .. kind))
end

local function resetScenario()
  g_minibot.reset()
  clock = clock + 5000
  actions = {}
  sentOpcodes = {}
  spectators = {}
  containers = {}
  tiles = {}
  inventoryCounts = {}
  inventorySlots = {}
  attackingCreature = nil
  mapWalkable = false
  sightClear = true
  autoWalkAccepted = true
  botCheckAlarmActive = false
  player.position = { x = 100, y = 100, z = 7 }
  player.healthPercent = 100
  player.mana = 1000
  player.maxMana = 1000
  player.harmony = 0
  player.pz = false
  player.haste = false
  player.shield = false
  player.magicShield = 1000
  player.maxMagicShield = 1000
  player.mounted = false
  player.feared = false
  player.paralyzed = false
  player.direction = 0
  player.autoWalking = false
end

local function addRule(moduleType, values)
  assert(g_minibot.addModule(moduleType, values), 'failed to add module ' .. moduleType)
  assert(g_minibot.setModuleToggle(moduleType, true), 'failed to enable module ' .. moduleType)
end

assert(connectCount == 2, 'runtime did not connect both lifecycle signal sets')
assert(pendingCount() == 0, 'offline runtime init created a polling event')
online = true
g_game.onGameStart()
assert(pendingCount() == 0, 'game start ran before player-info readiness')
MiniBotRuntime.start()
assert(pendingCount() == 1, 'explicit post-player-info start did not create runtime event')
MiniBotRuntime.start()
assert(pendingCount() == 1, 'idempotent start duplicated runtime event')

local areaNames = {
  'target', 'fill_circle_1_center', 'fill_circle_3', 'fill_circle_3_center',
  'fill_circle_10_center', 'cross_1', 'ring_circle_3_center',
  'hammer_1_dir', 'hammer_3_dir', 'hammer_5_dir', 'wave_4_dir',
  'wave_5_dir', 'beam_5_dir', 'beam_6_dir', 'beam_7_dir',
  'spear_3_dir', 'spear_line_4_dir'
}
for _, areaName in ipairs(areaNames) do
  local matrix = g_minibot.getAreaCoordinates(areaName)
  assert(#matrix > 0 and #matrix[1] > 0, 'empty area ' .. areaName)
  local width = #matrix[1]
  for _, row in ipairs(matrix) do
    assert(#row == width, 'non-rectangular area ' .. areaName)
  end
end

-- 1: health healing, validated item used on self.
resetScenario()
player.healthPercent = 35
inventoryCounts[266] = 1
addRule(1, { item = 266, min = 0, max = 50, enabled = true })
tick()
assert(action('useInventoryItemWith') and action('useInventoryItemWith').target == player,
  'module 1 did not heal the local player')
assertNoAction('useInventoryItem', 'targeted item was incorrectly normalized as direct-use')

-- Harmony requirements use the live LocalPlayer value at levels 0, 1 and 5.
for _, scenario in ipairs({
  { required = 0, before = 0, shouldCastBefore = true },
  { required = 1, before = 0, shouldCastBefore = false },
  { required = 5, before = 4, shouldCastBefore = false }
}) do
  resetScenario()
  player.healthPercent = 35
  player.harmony = scenario.before
  addRule(1, { spell = 'exura', min = 0, max = 50, harmony = scenario.required, enabled = true })
  tick()
  if scenario.shouldCastBefore then
    assert(action('talk') and action('talk').words == 'exura',
      'Harmony level 0 unexpectedly blocked a zero-requirement spell')
  else
    assertNoAction('talk', 'Harmony gate accepted a level below its requirement')
    player.harmony = scenario.required
    tick(600)
    assert(action('talk') and action('talk').words == 'exura',
      'Harmony gate did not release at level ' .. scenario.required)
  end
end

-- 2: table.find-style numeric truthiness must select direct item use.
resetScenario()
player.mana = 100
player.maxMana = 1000
inventoryCounts[26074] = 1
addRule(2, { item = 26074, use = 7, min = 0, max = 20, enabled = true })
tick()
assert(action('useInventoryItem') and action('useInventoryItem').itemId == 26074,
  'module 2 did not honor numeric table.find truthiness for direct use')
assertNoAction('useInventoryItemWith', 'direct-use item was incorrectly sent to a target')

-- Multi-use item exhaustion is shared across modules, begins conservatively at
-- 1000ms locally, and is extended by the authoritative server event.
resetScenario()
player.healthPercent = 30
player.mana = 100
player.maxMana = 1000
inventoryCounts[266] = 1
inventoryCounts[26074] = 1
addRule(1, { item = 266, itemGroup = { 255 }, min = 0, max = 50, enabled = true })
addRule(2, { item = 26074, itemGroup = { 255 }, use = true, min = 0, max = 20, enabled = true })
tick()
assert(action('useInventoryItemWith') and action('useInventoryItemWith').itemId == 266,
  'first multi-use item did not execute')
g_minibot.setModuleToggle(1, false)
clearActions()
tick(600)
assertNoAction('useInventoryItem', 'shared multi-use cooldown ended at the old 500ms rule delay')
tick(400)
assert(action('useInventoryItem') and action('useInventoryItem').itemId == 26074,
  'second module did not execute when the shared 1000ms cooldown ended')

resetScenario()
player.mana = 100
player.maxMana = 1000
inventoryCounts[26074] = 1
addRule(2, { item = 26074, itemGroup = { 255 }, use = true, min = 0, max = 20, enabled = true })
g_game.onMultiUseCooldown(1500)
tick(1499)
assertNoAction('useInventoryItem', 'server multi-use cooldown was ignored')
tick(1)
assert(action('useInventoryItem') and action('useInventoryItem').itemId == 26074,
  'server multi-use cooldown did not release at its declared deadline')

-- 0: cooldown-aware shooter on a current target.
resetScenario()
local shooterTarget = makeCreature({ monster = true, id = 200, position = { x = 101, y = 100, z = 7 } })
attackingCreature = shooterTarget
spectators = { shooterTarget }
addRule(0, {
  spell = 'exori', spellId = { 101 }, spellGroup = { 1 },
  hits = 1, health = 100, mana = 0, enabled = true
})
g_game.onSpellCooldown(101, 1000)
g_game.onSpellGroupCooldown(1, 2000)
tick(100)
assertNoAction('talk', 'module 0 ignored spell cooldown')
tick(1000)
assertNoAction('talk', 'module 0 ignored group cooldown')
tick(1000)
assert(action('talk') and action('talk').words == 'exori', 'module 0 did not cast after cooldown expiry')

-- 0 area targeting: target-centered AoE and directional beam hit gates.
resetScenario()
local areaTarget = makeCreature({ monster = true, id = 201, position = { x = 102, y = 100, z = 7 } })
local areaOther1 = makeCreature({ monster = true, id = 202, position = { x = 102, y = 101, z = 7 } })
local areaOther2 = makeCreature({ monster = true, id = 203, position = { x = 101, y = 100, z = 7 } })
attackingCreature = areaTarget
spectators = { areaTarget, areaOther1, areaOther2 }
inventoryCounts[3161] = 1
addRule(0, { item = 3161, area = 'fill_circle_3', hits = 3, health = 100, enabled = true })
tick()
assert(action('useInventoryItemWith') and action('useInventoryItemWith').target == areaTarget,
  'module 0 target-centered area count failed')

resetScenario()
local beamTarget = makeCreature({ monster = true, id = 204, position = { x = 100, y = 99, z = 7 } })
local beamOther = makeCreature({ monster = true, id = 205, position = { x = 100, y = 97, z = 7 } })
attackingCreature = beamTarget
spectators = { beamTarget, beamOther }
player.direction = 0
addRule(0, { spell = 'exevo vis lux', area = 'beam_5_dir', hits = 2, health = 100, enabled = true })
tick()
assert(action('talk') and action('talk').words == 'exevo vis lux', 'module 0 directional area count failed')

-- Smart directional spells rotate to the highest-hit orientation immediately
-- before casting; the Smart flag is independent from the PZ guard.
resetScenario()
local eastTarget = makeCreature({ monster = true, id = 206, position = { x = 101, y = 100, z = 7 } })
local eastOther = makeCreature({ monster = true, id = 207, position = { x = 103, y = 100, z = 7 } })
attackingCreature = eastTarget
spectators = { eastTarget, eastOther }
player.direction = 0
addRule(0, {
  spell = 'exevo vis lux', area = 'beam_5_dir', hits = 2,
  health = 100, smart = true, ignorePz = false, enabled = true
})
tick()
assert(actions[1] and actions[1].kind == 'turn' and actions[1].direction == 1 and
  actions[2] and actions[2].kind == 'talk' and actions[2].words == 'exevo vis lux',
  'smart directional shooter did not turn immediately before casting')

resetScenario()
attackingCreature = eastTarget
spectators = { eastTarget, eastOther }
player.direction = 0
addRule(0, {
  spell = 'exevo vis lux', area = 'beam_5_dir', hits = 2,
  health = 100, smart = false, ignorePz = false, enabled = true
})
tick()
assertNoAction('turn', 'disabled Smart still rotated the player')
assertNoAction('talk', 'disabled Smart cast a directional spell without enough forward hits')

-- Auto-attack target selection (closest, lowest HP, smart cluster, melee constraint).
resetScenario()
local near = makeCreature({ monster = true, id = 210, health = 90, position = { x = 101, y = 100, z = 7 } })
local farLow = makeCreature({ monster = true, id = 211, health = 10, position = { x = 104, y = 100, z = 7 } })
spectators = { farLow, near }
g_minibot.setAutoAttack(1)
tick()
assert(action('attack') and action('attack').creature == near, 'closest auto-target mode failed')

resetScenario()
spectators = { near, farLow }
g_minibot.setAutoAttack(2)
tick()
assert(action('attack') and action('attack').creature == farLow, 'lowest-health auto-target mode failed')

resetScenario()
local clusterCenter = makeCreature({ monster = true, id = 212, health = 80, position = { x = 104, y = 104, z = 7 } })
local clusterA = makeCreature({ monster = true, id = 213, position = { x = 103, y = 104, z = 7 } })
local clusterB = makeCreature({ monster = true, id = 214, position = { x = 104, y = 103, z = 7 } })
spectators = { near, clusterCenter, clusterA, clusterB }
g_minibot.setAutoAttack(200)
tick()
assert(action('attack') and action('attack').creature == clusterCenter, 'smart-cluster auto-target mode failed')

resetScenario()
spectators = { farLow, near }
g_minibot.setAutoAttack(102)
tick()
assert(action('attack') and action('attack').creature == near, 'melee-only auto-target constraint failed')

-- 3: combat timer monster bounds and configured repeat delay.
resetScenario()
local timerMonster = makeCreature({ monster = true, id = 220 })
spectators = { timerMonster }
inventoryCounts[7439] = 1
addRule(3, { item = 7439, max = 2, manaMin = 1, manaMax = 2, enabled = true })
tick()
assert(action('useInventoryItemWith'), 'module 3 did not execute inside monster bounds')
clearActions()
tick(1000)
assertNoAction('useInventoryItemWith', 'module 3 ignored its repeat delay')
tick(1100)
assert(action('useInventoryItemWith'), 'module 3 did not repeat after configured delay')

-- 4: haste toggle/state guards.
resetScenario()
addRule(4, { spell = 'utani hur', enabled = true })
tick()
assert(action('talk') and action('talk').words == 'utani hur', 'module 4 did not cast haste')
resetScenario()
g_minibot.addModule(4, { spell = 'utani hur', enabled = true })
player.haste = true
g_minibot.setModuleToggle(4, true)
tick()
assertNoAction('talk', 'module 4 cast while haste was already active')

-- 6 + 18: custom-name group healing with item.
resetScenario()
local alice = makeCreature({ player = true, id = 300, name = 'Alice', health = 30 })
spectators = { alice }
inventoryCounts[3152] = 1
g_minibot.setModuleToggle(18, true)
addRule(6, { item = 3152, target = 'alice', max = 50, enabled = true })
tick()
assert(action('useInventoryItemWith') and action('useInventoryItemWith').target == alice,
  'module 18 custom group mode did not select its named player')

-- 6 + 19: party vocation, Virtue pre-cast, then targeted heal.
resetScenario()
local bob = makeCreature({ player = true, id = 301, name = 'Bob', health = 25, party = true, vocation = 'Knight' })
spectators = { bob }
g_minibot.setModuleToggle(19, true)
addRule(6, { spell = 'exura sio', target = 'Knight', hits = 0, max = 50, area = 'utura tio', enabled = true })
tick()
assert(action('talk') and action('talk').words == 'utura tio', 'module 19 did not prime Virtue of Sustain')
clearActions()
tick(600)
assert(action('talk') and action('talk').words == 'exura sio "Bob"',
  'module 19 did not heal the selected party vocation after priming')

-- 6 + 20: guild emblem and vocation targeting.
resetScenario()
local clara = makeCreature({ player = true, id = 302, name = 'Clara', health = 20, emblem = 1, vocation = 'Druid' })
spectators = { clara }
g_minibot.setModuleToggle(20, true)
addRule(6, { spell = 'exura sio', target = 'Druid', hits = 4, max = 50, enabled = true })
tick()
assert(action('talk') and action('talk').words == 'exura sio "Clara"',
  'module 20 did not select a same-guild vocation')

-- Group healing must honor the spell-derived reqmana supplied by its loader.
resetScenario()
local lowManaTarget = makeCreature({ player = true, id = 303, name = 'LowMana', health = 20 })
spectators = { lowManaTarget }
player.mana = 60
g_minibot.setModuleToggle(18, true)
addRule(6, { spell = 'exura sio', target = 'LowMana', reqmana = 70, max = 50, enabled = true })
tick()
assertNoAction('talk', 'group healing ignored its required mana gate')
player.mana = 70
tick(600)
assert(action('talk') and action('talk').words == 'exura sio "LowMana"',
  'group healing did not cast once required mana became available')

-- 7: platinum/gold stack conversion prefers platinum.
resetScenario()
local gold = makeItem(3031, 100)
local platinum = makeItem(3035, 100)
containers = { makeContainer({ gold, platinum }, 20) }
g_minibot.setModuleToggle(7, true)
tick()
assert(action('use') and action('use').item == platinum, 'module 7 did not prefer a platinum stack')

-- 8: periodic direct food use.
resetScenario()
inventoryCounts[3582] = 1
addRule(8, { item = 3582, use = true, enabled = true })
tick()
assert(action('useInventoryItem') and action('useInventoryItem').itemId == 3582,
  'module 8 did not directly use food')
clearActions()
tick(1000)
assertNoAction('useInventoryItem', 'module 8 ignored its food interval')

-- 9: ammunition refill from an open container.
resetScenario()
local equippedAmmo = makeItem(3447, 50)
local reserveAmmo = makeItem(3447, 50)
inventorySlots[InventorySlotAmmo] = equippedAmmo
inventoryCounts[3447] = 100
containers = { makeContainer({ reserveAmmo }, 20) }
addRule(9, { item = 3447, enabled = true })
tick()
assert(action('equipItem') and action('equipItem').item == reserveAmmo,
  'module 9 did not refill partial ammunition')

-- 10: equip and unequip amulet through real container positions.
resetScenario()
local amulet = makeItem(3081, 1)
inventoryCounts[3081] = 1
containers = { makeContainer({ amulet }, 10, 70) }
addRule(10, { item = 3081, min = 0, max = 100, enabled = true })
tick()
assert(action('equipItem') and action('equipItem').item == amulet, 'module 10 did not equip an amulet')

resetScenario()
local equippedAmulet = makeItem(3081, 1)
local filler = makeItem(1000, 1)
inventorySlots[InventorySlotNeck] = equippedAmulet
containers = { makeContainer({ filler }, 5, 71) }
addRule(10, { item = 3081, use = true, min = 0, max = 100, enabled = true })
tick()
assert(action('move') and action('move').destination.y == 71 and action('move').destination.z == 1,
  'module 10 did not unequip into a valid open-container slot')

resetScenario()
inventorySlots[InventorySlotNeck] = equippedAmulet
containers = { makeContainer({ makeItem(1), makeItem(2) }, 2, 72) }
addRule(10, { item = 3081, use = true, min = 0, max = 100, enabled = true })
tick()
assertNoAction('move', 'module 10 moved an item without container capacity')

-- 11: ignored equipment blocks rule, then equip-by-id fallback works.
resetScenario()
inventoryCounts[3051] = 1
inventorySlots[1] = makeItem(9999, 1)
addRule(11, { item = 3051, min = 0, max = 100, spellGroup = { 9999 }, enabled = true })
tick()
assertNoAction('equipItemId', 'module 11 ignored its equipped-item exclusion')
resetScenario()
inventoryCounts[3051] = 1
addRule(11, { item = 3051, min = 0, max = 100, enabled = true })
tick()
assert(action('equipItemId') and action('equipItemId').itemId == 3051,
  'module 11 did not use equip-by-id fallback')

-- 255 remains a cooldown sentinel, never an alternative equipment item id.
resetScenario()
inventoryCounts[3081] = 1
inventorySlots[InventorySlotNeck] = makeItem(255, 1)
addRule(10, { item = 3081, itemGroup = { 255 }, min = 0, max = 100, enabled = true })
tick()
assert(action('equipItemId') and action('equipItemId').itemId == 3081,
  'multi-use group marker 255 was interpreted as equipped item id 255')

-- 16: Tank Mode equips SSA first, then Might Ring, and becomes a no-op once
-- both requested slots are already satisfied.
resetScenario()
local tankSsa = makeItem(3081, 1)
local tankRing = makeItem(3048, 1)
inventoryCounts[3081] = 1
inventoryCounts[3048] = 1
containers = { makeContainer({ tankSsa, tankRing }, 20) }
assert(g_minibot.addModule(16, { item = 3081, enabled = true }))
assert(g_minibot.addModule(16, { item = 3048, enabled = true }))
assert(g_minibot.setModuleToggle(16, true))
tick()
assert(action('equipItem') and action('equipItem').item == tankSsa,
  'module 16 did not prioritize Stone Skin Amulet')
inventorySlots[InventorySlotNeck] = tankSsa
clearActions()
tick(600)
assert(action('equipItem') and action('equipItem').item == tankRing,
  'module 16 did not equip Might Ring after SSA')
inventorySlots[InventorySlotFinger] = tankRing
clearActions()
tick(600)
assertNoAction('equipItem', 'module 16 kept equipping already satisfied tank slots')
assertNoAction('equipItemId', 'module 16 kept equipping already satisfied tank slots by id')

resetScenario()
player.pz = true
inventoryCounts[3081] = 1
addRule(16, { item = 3081, ignorePz = true, enabled = true })
tick()
assertNoAction('equipItemId', 'module 16 ignored its PZ guard')

-- 12: exercise weapon finds a configured dummy and obeys its tick gate.
resetScenario()
local exerciseWeapon = 28552
local dummy = makeItem(28561, 1)
inventoryCounts[exerciseWeapon] = 1
tiles['101:100:7'] = makeTile({ dummy }, true)
addRule(12, { item = exerciseWeapon, spellGroup = { 28561, 28562 }, enabled = true })
tick()
assert(action('useInventoryItemWith') and action('useInventoryItemWith').target == dummy,
  'module 12 did not use an exercise weapon on its dummy')
clearActions()
tick(1000)
assertNoAction('useInventoryItemWith', 'module 12 ignored its training tick gate')
tick(29000)
assert(action('useInventoryItemWith'), 'module 12 did not retry after its training tick gate')

-- 13: spell activation and potion fallback while the spell is cooling down.
resetScenario()
player.healthPercent = 30
addRule(13, { spell = 'utamo vita', spellId = { 44 }, max = 50, enabled = true })
tick()
assert(action('talk') and action('talk').words == 'utamo vita', 'module 13 did not cast Magic Shield')

resetScenario()
player.healthPercent = 30
inventoryCounts[35563] = 1
addRule(13, { spell = 'utamo vita', spellId = { 44 }, item = 35563, max = 50, enabled = true })
g_game.onSpellCooldown(44, 2000)
tick(100)
assert(action('useInventoryItemWith') and action('useInventoryItemWith').itemId == 35563,
  'module 13 did not fall back to Magic Shield Potion')

resetScenario()
player.healthPercent = 30
inventoryCounts[35563] = 1
addRule(13, { spell = '', item = 35563, max = 50, enabled = true })
tick()
assert(action('useInventoryItemWith') and action('useInventoryItemWith').itemId == 35563,
  'module 13 did not execute an item-only Magic Shield fallback')
assertNoAction('talk', 'item-only Magic Shield fallback attempted an unavailable spell')

-- 14: Fear is an independent item-shield trigger.
resetScenario()
player.healthPercent = 100
player.feared = true
inventoryCounts[35563] = 1
addRule(14, { item = 35563, use = true, max = 0, hits = 0, enabled = true })
tick()
assert(action('useInventoryItemWith') and action('useInventoryItemWith').itemId == 35563,
  'module 14 did not trigger on Fear')

-- 15: remove shield only when HP/monster/Fear guards allow it.
resetScenario()
player.shield = true
player.healthPercent = 90
player.feared = true
spectators = { makeCreature({ monster = true, id = 400 }) }
addRule(15, { spell = 'exana vita', max = 70, hits = 2, use = true, enabled = true })
tick()
assertNoAction('talk', 'module 15 removed shield while Ignore Fear was active')
player.feared = false
clearActions()
tick(600)
assert(action('talk') and action('talk').words == 'exana vita',
  'module 15 did not remove shield after all guards passed')

-- 17: Anti-Paralyze only runs while paralyzed and preserves left-to-right
-- priority while skipping rules blocked by mana, cooldown or PZ.
resetScenario()
addRule(17, { spell = 'utani hur', spellId = { 600 }, reqmana = 10, enabled = true })
tick()
assertNoAction('talk', 'module 17 cast while the player was not paralyzed')
player.paralyzed = true
tick(600)
assert(action('talk') and action('talk').words == 'utani hur',
  'module 17 did not cast after Paralyze became active')

resetScenario()
player.paralyzed = true
player.mana = 100
assert(g_minibot.addModule(17, {
  spell = 'first cure', spellId = { 601 }, spellGroup = { 7 }, reqmana = 200, enabled = true
}))
assert(g_minibot.addModule(17, {
  spell = 'second cure', spellId = { 602 }, spellGroup = { 8 }, reqmana = 50, enabled = true
}))
assert(g_minibot.setModuleToggle(17, true))
tick()
assert(action('talk') and action('talk').words == 'second cure',
  'module 17 did not skip the higher-priority spell with insufficient mana')

resetScenario()
player.paralyzed = true
player.pz = true
assert(g_minibot.addModule(17, {
  spell = 'pz blocked', spellId = { 603 }, ignorePz = true, enabled = true
}))
assert(g_minibot.addModule(17, {
  spell = 'pz allowed', spellId = { 604 }, ignorePz = false, enabled = true
}))
assert(g_minibot.setModuleToggle(17, true))
g_game.onSpellCooldown(603, 2000)
tick(100)
assert(action('talk') and action('talk').words == 'pz allowed',
  'module 17 did not preserve priority while honoring cooldown/PZ guards')

-- 22: configured mount outside PZ only.
resetScenario()
addRule(22, { enabled = true })
tick()
assert(action('mount') and action('mount').enabled, 'module 22 did not mount outside PZ')
resetScenario()
player.pz = true
addRule(22, { enabled = true })
tick()
assertNoAction('mount', 'module 22 mounted inside PZ')

-- 5: recorder advances nodes, walks, pauses for monsters, and fails wrong floors.
resetScenario()
local walkedNodes = {}
local walkFailures = {}
g_minibot.onWalkToNextNode = function(index) table.insert(walkedNodes, index) end
g_minibot.onWalkFailed = function(code, moduleType)
  table.insert(walkFailures, { code = code, moduleType = moduleType })
end
g_minibot.registerWalkWaypoint({ position = { x = 100, y = 100, z = 7 }, index = 1, speed = 5 })
g_minibot.registerWalkWaypoint({ position = { x = 104, y = 100, z = 7 }, index = 2, speed = 5 })
g_minibot.setModuleToggle(5, true)
tick()
assert(g_minibot.getCurrentWalkIndex() == 1 and walkedNodes[#walkedNodes] == 2,
  'module 5 did not advance from a reached waypoint')
clearActions()
tick(600)
assert(action('autoWalk') and action('autoWalk').destination.x == 104,
  'module 5 did not walk toward the next waypoint')

-- The donor Recorder exposes all lure speeds from 1 through 20. Check the
-- bottom, midpoint, and top values so the upper half cannot collapse to 10.
for _, speedCase in ipairs({
  { speed = 1, interval = 1175 },
  { speed = 10, interval = 500 },
  { speed = 20, interval = 250 }
}) do
  resetScenario()
  g_minibot.registerWalkWaypoint({
    position = { x = 104, y = 100, z = 7 }, index = 1, lure = true, speed = speedCase.speed
  })
  g_minibot.setModuleToggle(5, true)
  tick()
  assert(action('autoWalk'), 'module 5 did not walk at lure speed ' .. speedCase.speed)
  clearActions()
  tick(speedCase.interval - 1)
  assertNoAction('autoWalk', 'module 5 repeated too early at lure speed ' .. speedCase.speed)
  tick(1)
  assert(action('autoWalk'), 'module 5 lost lure cadence at speed ' .. speedCase.speed)
end

resetScenario()
walkedNodes = {}
walkFailures = {}
local blockingMonster = makeCreature({ monster = true, id = 410 })
g_minibot.registerWalkWaypoint({
  position = { x = 100, y = 100, z = 7 }, index = 1, speed = 5
})
g_minibot.registerWalkWaypoint({
  position = { x = 104, y = 100, z = 7 }, index = 2, creatures = 1, resume = 0, speed = 5
})
g_minibot.setModuleToggle(5, true)
tick()
spectators = { blockingMonster }
clearActions()
tick(600)
assert(action('autoWalk') and action('autoWalk').destination.x == 104 and not action('stop'),
  'module 5 applied waypoint thresholds before reaching the waypoint area')
player.position = { x = 103, y = 100, z = 7 }
clearActions()
tick(600)
assertNoAction('autoWalk', 'module 5 walked through a threshold at the waypoint area')
assert(action('stop'), 'module 5 did not pause after reaching the waypoint area')
spectators = {}
clearActions()
tick(50)
assert(action('autoWalk') and action('autoWalk').destination.x == 104,
  'module 5 did not resume the paused waypoint after monsters cleared')

resetScenario()
walkFailures = {}
g_minibot.registerWalkWaypoint({ position = { x = 100, y = 100, z = 8 }, index = 1, speed = 5 })
g_minibot.setModuleToggle(5, true)
tick()
assert(walkFailures[1] ~= nil and walkFailures[1].code == 0 and
  walkFailures[1].moduleType == 5 and not g_minibot.isModuleToggle(5),
  'module 5 did not signal/stop on a wrong-floor waypoint')

-- Legacy routes serialized both ends of a floor transition as teleport=true.
-- They must consume origin then arrival and continue walking on the new floor.
resetScenario()
walkFailures = {}
walkedNodes = {}
g_minibot.onWalkToNextNode = function(index) table.insert(walkedNodes, index) end
g_minibot.onWalkFailed = function(code, moduleType)
  table.insert(walkFailures, { code = code, moduleType = moduleType })
end
g_minibot.registerWalkWaypoint({
  position = { x = 100, y = 100, z = 7 }, index = 1, teleport = true, speed = 5
})
g_minibot.registerWalkWaypoint({
  position = { x = 100, y = 100, z = 8 }, index = 2, teleport = true, speed = 5
})
g_minibot.registerWalkWaypoint({
  position = { x = 104, y = 100, z = 8 }, index = 3, teleport = false, speed = 5
})
g_minibot.setModuleToggle(5, true)
tick()
assert(g_minibot.getCurrentWalkIndex() == 0 and g_minibot.isModuleToggle(5),
  'legacy teleport origin was completed before the floor transition')
player.position = { x = 100, y = 100, z = 8 }
tick(100)
assert(g_minibot.getCurrentWalkIndex() == 1 and g_minibot.isModuleToggle(5),
  'legacy teleport origin was not consumed after changing floor')
tick(100)
assert(g_minibot.getCurrentWalkIndex() == 2 and #walkFailures == 0,
  'legacy teleport arrival was treated as a second origin')
clearActions()
tick(1500)
assert(action('autoWalk') and action('autoWalk').destination.x == 104 and
  action('autoWalk').destination.z == 8 and g_minibot.isModuleToggle(5),
  'Recorder did not continue its multi-floor route after the teleport pair')

-- 21: explorer walks, honors stop/resume thresholds, and owns no extra timer.
resetScenario()
mapWalkable = true
g_minibot.setExplorerWalker({ findCreatures = 0, resumeCreatures = 0, lureCreatures = false })
g_minibot.setModuleToggle(21, true)
tick()
assert(action('autoWalk') and
  math.max(math.abs(action('autoWalk').destination.x - player.position.x),
    math.abs(action('autoWalk').destination.y - player.position.y)) >= 4,
  'module 21 did not select a normal exploration destination')
assert(pendingCount() == 1, 'module 21 created an extra scheduler')

resetScenario()
mapWalkable = true
g_minibot.setExplorerWalker({ findCreatures = 0, resumeCreatures = 0, lureCreatures = true })
g_minibot.setModuleToggle(21, true)
tick()
local fastLureWalk = action('autoWalk')
assert(fastLureWalk and
  math.max(math.abs(fastLureWalk.destination.x - player.position.x),
    math.abs(fastLureWalk.destination.y - player.position.y)) <= 2,
  'module 21 lure mode did not choose a short destination')
clearActions()
tick(249)
assertNoAction('autoWalk', 'module 21 zero-monster lure repeated before its fast interval')
tick(1)
assert(action('autoWalk'), 'module 21 zero-monster lure did not use its fast interval')

resetScenario()
mapWalkable = true
spectators = { makeCreature({ monster = true, id = 419 }) }
g_minibot.setExplorerWalker({ findCreatures = 0, resumeCreatures = 0, lureCreatures = true })
g_minibot.setModuleToggle(21, true)
tick()
local cautiousLureWalk = action('autoWalk')
assert(cautiousLureWalk and
  math.max(math.abs(cautiousLureWalk.destination.x - player.position.x),
    math.abs(cautiousLureWalk.destination.y - player.position.y)) <= 2,
  'module 21 monster lure did not choose a short destination')
clearActions()
tick(649)
assertNoAction('autoWalk', 'module 21 monster lure repeated before its cautious interval')
tick(1)
assert(action('autoWalk'), 'module 21 monster lure did not resume at its cautious interval')

resetScenario()
mapWalkable = true
spectators = { makeCreature({ monster = true, id = 420 }) }
g_minibot.setExplorerWalker({ findCreatures = 1, resumeCreatures = 0, lureCreatures = true })
g_minibot.setModuleToggle(21, true)
tick()
assertNoAction('autoWalk', 'module 21 ignored its monster stop threshold')
assert(action('stop'), 'module 21 pause did not send the authoritative game stop command')
spectators = {}
clearActions()
tick(300)
assert(action('autoWalk'), 'module 21 did not resume exploration')

resetScenario()
walkFailures = {}
g_minibot.onWalkFailed = function(code, moduleType)
  table.insert(walkFailures, { code = code, moduleType = moduleType })
end
mapWalkable = false
g_minibot.setExplorerWalker({ findCreatures = 0, resumeCreatures = 0, lureCreatures = false })
g_minibot.setModuleToggle(21, true)
tick()
tick(1000)
tick(1000)
assert(walkFailures[1] ~= nil and walkFailures[1].code == 1 and
  walkFailures[1].moduleType == 21 and not g_minibot.isModuleToggle(21),
  'module 21 did not signal/stop after repeated destination failures')

-- Runtime safety rejects re-enabling either movement engine during BotCheck.
resetScenario()
botCheckAlarmActive = true
assert(g_minibot.setModuleToggle(5, true) == false and not g_minibot.isModuleToggle(5),
  'BotCheck allowed Recorder to be re-enabled')
assert(g_minibot.setModuleToggle(21, true) == false and not g_minibot.isModuleToggle(21),
  'BotCheck allowed Explorer to be re-enabled')

-- Missing resources and targets must remain safe/no-op.
resetScenario()
addRule(1, { item = 266, min = 0, max = 100, enabled = true })
tick()
assertNoAction('useInventoryItemWith', 'missing item was used')
resetScenario()
addRule(0, { item = 3161, hits = 1, health = 100, enabled = true })
tick()
assertNoAction('useInventoryItemWith', 'shooter acted without a target')

-- Lifecycle: logout clears the previous character and reconnect waits for the
-- explicit player-info-owned start before recreating the sole loop.
g_minibot.setAutoAttack(2)
g_minibot.setModuleToggle(16, true)
g_minibot.setModuleToggle(17, true)
online = false
g_game.onGameEnd()
assert(pendingCount() == 0, 'game end left the runtime loop alive')
assert(g_minibot.getAutoAttack() == 0 and not g_minibot.isModuleToggle(0) and
  not g_minibot.isModuleToggle(16) and not g_minibot.isModuleToggle(17),
  'game end retained automation from the previous character')
online = true
g_game.onGameStart()
assert(pendingCount() == 0, 'reconnect restarted before player info')
MiniBotRuntime.start()
assert(pendingCount() == 1, 'post-player-info reconnect did not recreate the runtime loop')
MiniBotRuntime.terminate()
MiniBotRuntime.terminate()
assert(pendingCount() == 0, 'terminate left a runtime event alive')
assert(disconnectCount == 2, 'terminate was not idempotent for signal disconnects')

print('minibot executor matrix: OK (0-22, targeting, areas, recorder, explorer, lifecycle)')
