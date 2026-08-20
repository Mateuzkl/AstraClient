local source = debug.getinfo(1, 'S').source
local scriptPath = (source:sub(1, 1) == '@' and source:sub(2) or source):gsub('\\', '/')
local testDirectory = scriptPath:match('^(.*)/[^/]+$') or '.'
local clientRoot = testDirectory:match('^(.*)/tests$') or (testDirectory == 'tests' and '.' or testDirectory)

local clock = 1000
local function advanceClock(milliseconds)
  clock = clock + (milliseconds or 50)
end

local online = false
local scheduled = 0
local removed = 0
local connected = 0
local disconnected = 0
local disconnectedTargets = {}
local playerStops = 0
local gameStops = 0
local sent = {}
local lastEvent = nil
local usedItems = {}
local gameCallbacks = nil
local playerCallbacks = nil

g_clock = { millis = function() return clock end }
LocalPlayer = {}

function connect(target, callbacks)
  connected = connected + 1
  if target == g_game then
    gameCallbacks = callbacks
  elseif target == LocalPlayer then
    playerCallbacks = callbacks
  end
end

function disconnect(target, callbacks)
  disconnected = disconnected + 1
  table.insert(disconnectedTargets, { target = target, callbacks = callbacks })
end

function scheduleEvent(callback, delay)
  scheduled = scheduled + 1
  lastEvent = { callback = callback, delay = delay }
  return lastEvent
end

function removeEvent(_)
  removed = removed + 1
end

function signalcall(signal, value)
  if type(signal) == 'function' then
    return signal(value)
  end
end

local player = {
  stopAutoWalk = function()
    playerStops = playerStops + 1
  end,
  getPosition = function() return { x = 100, y = 100, z = 7 } end,
  getHealthPercent = function() return 40 end,
  getMana = function() return 100 end,
  getMaxMana = function() return 100 end,
  getHarmony = function() return 0 end,
  getInventoryCount = function(_, itemId) return itemId == 266 and 1 or 0 end,
  isInProtectionZone = function() return false end,
  getInventoryItem = function() return nil end,
  getDirection = function() return 0 end
}

local protocol = {}
function protocol:sendExtendedOpcode(opcode, payload)
  table.insert(sent, tostring(opcode) .. ':' .. payload)
end

g_game = {
  isOnline = function() return online end,
  getLocalPlayer = function() return player end,
  getProtocolGame = function() return protocol end,
  stop = function() gameStops = gameStops + 1 end,
  getAttackingCreature = function() return nil end,
  canPerformGameAction = function() return true end,
  useInventoryItemWith = function(itemId, target, subtype)
    table.insert(usedItems, { itemId = itemId, target = target, subtype = subtype })
  end,
  getContainers = function() return {} end
}
g_map = { getSpectators = function() return {} end }

g_minibot = nil
MiniBotRuntime = nil
dofile(clientRoot .. '/modules/game_minibot/runtime.lua')

local requiredApi = {
  'reset', 'resetModule', 'addModule', 'cycle', 'getAreaCoordinates',
  'getAutoAttack', 'getCurrentWalkIndex', 'isModuleToggle',
  'registerWalkWaypoint', 'resetRecorderSession', 'setAutoAttack',
  'setCurrentWalkIndex', 'setExplorerWalker', 'setModuleTimeTick',
  'setModuleToggle', 'applyServerCavebotState'
}

for _, name in ipairs(requiredApi) do
  assert(type(g_minibot[name]) == 'function', 'missing ABI: ' .. name)
end

for _, name in ipairs({ 'init', 'start', 'stop', 'terminate', 'applyServerCavebotState' }) do
  assert(type(MiniBotRuntime[name]) == 'function', 'missing lifecycle API: ' .. name)
end

assert(scheduled == 0, 'offline init scheduled a polling loop')
assert(connected == 2, 'runtime lifecycle signals were not connected exactly once')
MiniBotRuntime.init()
assert(connected == 2, 'runtime init is not idempotent')

local areas = {
  'target', 'fill_circle_1_center', 'fill_circle_3', 'fill_circle_3_center',
  'fill_circle_10_center', 'cross_1', 'ring_circle_3_center',
  'hammer_1_dir', 'hammer_3_dir', 'hammer_5_dir', 'wave_4_dir',
  'wave_5_dir', 'beam_5_dir', 'beam_6_dir', 'beam_7_dir',
  'spear_3_dir', 'spear_line_4_dir'
}
for _, areaName in ipairs(areas) do
  local area = g_minibot.getAreaCoordinates(areaName)
  assert(type(area) == 'table' and #area > 0 and #area[1] > 0, 'invalid area: ' .. areaName)
  local width = #area[1]
  for _, row in ipairs(area) do
    assert(#row == width, 'non-rectangular area: ' .. areaName)
  end
end

assert(g_minibot.addModule(1, { item = 266, min = 0, max = 50 }) == 1)
assert(g_minibot.resetModule(1))
assert(g_minibot.setModuleTimeTick(12, 1234))
assert(g_minibot.registerWalkWaypoint({
  position = { x = 100, y = 100, z = 7 }, index = 1, speed = 5
}))
assert(g_minibot.setCurrentWalkIndex(0) == 0)
assert(g_minibot.getCurrentWalkIndex() == 0)

online = true
MiniBotRuntime.start()
MiniBotRuntime.start()
assert(scheduled == 1, 'runtime start created duplicate loops')

assert(g_minibot.addModule(1, { item = 266, min = 0, max = 50 }) == 1)
assert(g_minibot.setModuleToggle(1, true))
advanceClock(math.max(lastEvent.delay or 0, 50))
lastEvent.callback()
assert(#usedItems == 1 and usedItems[1].itemId == 266 and usedItems[1].target == player,
  'health executor did not use the validated item on the local player')
assert(scheduled == 2, 'cycle did not preserve the single recursive scheduler')

g_minibot.applyServerCavebotState(false)
assert(playerStops == 0 and gameStops == 0, 'repeated server false stopped unrelated walking')
assert(g_minibot.setModuleToggle(5, true))
assert(#sent == 1 and sent[1] == '210:1', 'cavebot enable opcode is incorrect')
assert(not g_minibot.setModuleToggle(5, true) and #sent == 1, 'duplicate enable was sent')

g_minibot.applyServerCavebotState(false)
assert(#sent == 1, 'server authority was echoed to the server')
assert(playerStops == 1 and gameStops == 1, 'server disable did not stop active cavebot walking')
g_minibot.applyServerCavebotState(false)
assert(playerStops == 1 and gameStops == 1, 'repeated server false stopped walking again')

assert(g_minibot.setModuleToggle(5, true))
assert(g_minibot.setModuleToggle(5, false))
assert(sent[#sent - 1] == '210:1' and sent[#sent] == '210:0', 'cavebot transitions were not synchronized')

g_minibot.setAutoAttack(2)
g_minibot.setModuleToggle(1, true)
local actionsBeforeLogout = #usedItems
gameCallbacks.onGameEnd()
assert(g_minibot.getAutoAttack() == 0 and not g_minibot.isModuleToggle(1),
  'logout retained automation from the previous character')
local schedulesAtLogout = scheduled
gameCallbacks.onGameStart()
assert(scheduled == schedulesAtLogout, 'onGameStart restarted the loop before player info')
advanceClock(math.max(lastEvent.delay or 0, 50))
lastEvent.callback()
assert(#usedItems == actionsBeforeLogout, 'a stale queued loop acted during reconnect readiness')
MiniBotRuntime.start()
assert(scheduled == schedulesAtLogout + 1, 'explicit post-player-info start did not resume the loop')

local removedBeforeTerminate = removed
MiniBotRuntime.terminate()
local removedAfterFirstTerminate = removed
MiniBotRuntime.terminate()
assert(removedAfterFirstTerminate == removedBeforeTerminate + 1,
  'terminate did not remove the active runtime loop')
assert(removed == removedAfterFirstTerminate, 'runtime loop teardown was not idempotent')
assert(disconnected == 2 and #disconnectedTargets == 2,
  'runtime lifecycle signals were not disconnected exactly once')
assert(disconnectedTargets[1].target == g_game and disconnectedTargets[1].callbacks == gameCallbacks,
  'terminate disconnected an unexpected game target or callback table')
assert(disconnectedTargets[2].target == LocalPlayer and disconnectedTargets[2].callbacks == playerCallbacks,
  'terminate disconnected an unexpected player target or callback table')

print('minibot runtime smoke: OK')
