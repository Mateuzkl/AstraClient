local botScript = assert(arg[1], "missing bot.lua path")
local waypointsScript = assert(arg[2], "missing waypoints.lua path")

local function assertEqual(actual, expected, message)
  assert(actual == expected,
    string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)))
end

local function connect(object, signals)
  for signal, slot in pairs(signals) do
    if not object[signal] then
      object[signal] = slot
    elseif type(object[signal]) == "function" then
      object[signal] = { object[signal], slot }
    else
      table.insert(object[signal], slot)
    end
  end
end

local function disconnect(object, signals)
  for signal, slot in pairs(signals) do
    local connected = object[signal]
    if type(connected) == "function" then
      if connected == slot then object[signal] = nil end
    elseif type(connected) == "table" then
      for index, candidate in ipairs(connected) do
        if candidate == slot then
          table.remove(connected, index)
          if #connected == 1 then object[signal] = connected[1] end
          break
        end
      end
    end
  end
end

local function emit(signal, ...)
  if type(signal) == "function" then
    signal(...)
  else
    for _, slot in ipairs(signal or {}) do slot(...) end
  end
end

local function replaceUpvalue(func, name, replacement)
  for index = 1, math.huge do
    local upvalueName = debug.getupvalue(func, index)
    if not upvalueName then return false end
    if upvalueName == name then
      debug.setupvalue(func, index, replacement)
      return true
    end
  end
end

local function testCallbackLifecycle()
  rootWidget, g_game, Tile, Container, g_map = {}, {}, {}, {}, {}
  Creature = {}
  Player = setmetatable({}, { __index = Creature })
  LocalPlayer = setmetatable({}, { __index = Player })
  _G.connect, _G.disconnect = connect, disconnect

  assert(loadfile(botScript))()

  local localPositionCalls = 0
  local creaturePositionCalls = 0
  local localWalkCalls = 0
  local creatureWalkCalls = 0
  local localPlayer = { isLocalPlayer = function() return true end }
  local creature = { isLocalPlayer = function() return false end }
  local realCreaturePositionChange = botCreaturePositionChange
  local realLocalPlayerPositionChange = botLocalPlayerPositionChange
  local realCreatureWalk = botCreatureWalk
  local realLocalPlayerWalk = botLocalPlayerWalk

  local function dispatchSpy(callbackName, subject)
    if callbackName == "onCreaturePositionChange" then
      if subject == localPlayer then
        localPositionCalls = localPositionCalls + 1
      elseif subject == creature then
        creaturePositionCalls = creaturePositionCalls + 1
      end
    elseif callbackName == "onWalk" then
      if subject == localPlayer then
        localWalkCalls = localWalkCalls + 1
      elseif subject == creature then
        creatureWalkCalls = creatureWalkCalls + 1
      end
    end
  end

  assert(replaceUpvalue(realCreaturePositionChange, "dispatchBotCallback", dispatchSpy),
    "dispatchBotCallback upvalue not found")

  initCallbacks()
  initCallbacks()
  emit(LocalPlayer.onPositionChange, localPlayer, {}, {})
  emit(LocalPlayer.onWalk, localPlayer, {}, {})
  emit(Creature.onPositionChange, localPlayer, {}, {})
  emit(Creature.onWalk, localPlayer, {}, {})
  emit(Creature.onPositionChange, creature, {}, {})
  emit(Creature.onWalk, creature, {}, {})
  assertEqual(localPositionCalls, 1, "one local position callback")
  assertEqual(localWalkCalls, 1, "one local walk callback")
  assertEqual(creaturePositionCalls, 1, "one creature position callback")
  assertEqual(creatureWalkCalls, 1, "one creature walk callback")
  assertEqual(botCreaturePositionChange, realCreaturePositionChange, "real creature position handler preserved")
  assertEqual(botLocalPlayerPositionChange, realLocalPlayerPositionChange, "real local position handler preserved")
  assertEqual(botCreatureWalk, realCreatureWalk, "real creature walk handler preserved")
  assertEqual(botLocalPlayerWalk, realLocalPlayerWalk, "real local walk handler preserved")

  terminateCallbacks()
  assertEqual(rawget(LocalPlayer, "onPositionChange"), nil, "local position signal removed")
  assertEqual(rawget(LocalPlayer, "onWalk"), nil, "local walk signal removed")
  emit(LocalPlayer.onPositionChange, localPlayer, {}, {})
  emit(LocalPlayer.onWalk, localPlayer, {}, {})
  emit(Creature.onPositionChange, creature, {}, {})
  emit(Creature.onWalk, creature, {}, {})
  assertEqual(localPositionCalls, 1, "position callback disconnected")
  assertEqual(localWalkCalls, 1, "walk callback disconnected")
  assertEqual(creaturePositionCalls, 1, "creature position callback disconnected")
  assertEqual(creatureWalkCalls, 1, "creature walk callback disconnected")

  for _ = 1, 10 do
    initCallbacks()
    terminateCallbacks()
  end
  initCallbacks()
  emit(LocalPlayer.onPositionChange, localPlayer, {}, {})
  emit(LocalPlayer.onWalk, localPlayer, {}, {})
  emit(Creature.onPositionChange, localPlayer, {}, {})
  emit(Creature.onWalk, localPlayer, {}, {})
  emit(Creature.onPositionChange, creature, {}, {})
  emit(Creature.onWalk, creature, {}, {})
  assertEqual(localPositionCalls, 2, "reload cycles do not duplicate callbacks")
  assertEqual(localWalkCalls, 2, "reload cycles do not duplicate walk callbacks")
  assertEqual(creaturePositionCalls, 2, "reload cycles preserve creature position routing")
  assertEqual(creatureWalkCalls, 2, "reload cycles preserve creature walk routing")
  terminateCallbacks()
end

local function newWidget()
  local widget = { children = {}, on = false }
  function widget:setText(value) self.text = value end
  function widget:setColor(value) self.color = value end
  function widget:setOn(value) self.on = value == true end
  function widget:isOn() return self.on end
  function widget:clear() self.options = {} end
  function widget:addOption(value)
    self.options = self.options or {}
    table.insert(self.options, value)
  end
  function widget:setCurrentIndex(value) self.currentIndex = value end
  function widget:destroyChildren() self.children = {} end
  function widget:getLastChild() return self.children[#self.children] end
  function widget:getFirstChild() return self.children[1] end
  function widget:getChildCount() return #self.children end
  function widget:getChildByIndex(index) return self.children[index] end
  function widget:getChildIndex(child)
    for index, candidate in ipairs(self.children) do
      if candidate == child then return index end
    end
  end
  function widget:focusChild(child) self.focusedChild = child end
  function widget:getFocusedChild() return self.focusedChild end
  return widget
end

local function testRecorder()
  local ui = {
    config = newWidget(), list = newWidget(), enableButton = newWidget(),
    recording = newWidget(), pos = newWidget(), add = newWidget(), edit = newWidget(),
    remove = newWidget(), wGoto = newWidget(), wUse = newWidget(),
    wUseWith = newWidget(), wWait = newWidget(), wSay = newWidget(),
    wNpc = newWidget(), wLabel = newWidget(), wFollow = newWidget(),
    wFunction = newWidget()
  }
  local positionCallbacks, useCallbacks, useWithCallbacks = {}, {}, {}
  local warningCount = 0
  local currentPosition = { x = 100, y = 100, z = 7 }
  local context = {
    Panels = {}, now = 0,
    storage = { cavebot = { configs = {}, activeConfig = 0, enabled = false } },
    player = {
      getPosition = function() return currentPosition end,
      isWalking = function() return false end
    },
    setupUI = function() return ui end,
    getConfigName = function(config) return config:match("name:([^\n]+)") end,
    saveConfig = function() end,
    warning = function() warningCount = warningCount + 1 end,
    error = function(message) error(message) end,
    onPlayerPositionChange = function(callback) table.insert(positionCallbacks, callback) end,
    onUse = function(callback) table.insert(useCallbacks, callback) end,
    onUseWith = function(callback) table.insert(useWithCallbacks, callback) end,
    onContainerOpen = function() end,
    macro = function() end,
    displayGeneralBox = function() return newWidget() end
  }

  G = { botContext = context }
  modules = {
    client_textedit = { singlelineEditor = function() end, multilineEditor = function() end },
    game_walking = { lastManualWalk = 0 }
  }
  g_game = { getAttackingCreature = function() end, getFollowingCreature = function() end }
  g_map = {}
  g_ui = {
    createWidget = function(_, parent)
      local widget = newWidget()
      table.insert(parent.children, widget)
      return widget
    end
  }
  tr = function(text) return text end
  AnchorHorizontalCenter = 0
  regexMatch = function(text)
    local matches = {}
    for line in text:gmatch("[^\n]+") do
      local command, value = line:match("^([^:]+):(.*)$")
      if command then table.insert(matches, { line, command, ":", value }) end
    end
    return matches
  end

  assert(loadfile(waypointsScript))()
  local controls = context.Panels.Waypoints(newWidget())

  ui.recording.onClick()
  assertEqual(ui.recording:isOn(), false, "no config keeps switch off")
  assertEqual(warningCount, 1, "no config shows feedback")

  context.storage.cavebot.configs = { "name:Test\nlabel:start" }
  context.storage.cavebot.activeConfig = 1
  controls.refresh()
  ui.recording.onClick()
  assertEqual(ui.recording:isOn(), true, "valid config enables recording")

  positionCallbacks[1]({ x = 101, y = 100, z = 7 }, currentPosition)
  assert(context.storage.cavebot.configs[1]:find("goto:100,100,7", 1, true),
    "first confirmed movement must record a waypoint")

  currentPosition = { x = 101, y = 100, z = 7 }
  positionCallbacks[1]({ x = 101, y = 100, z = 8 }, currentPosition)
  assert(context.storage.cavebot.configs[1]:find("goto:101,100,7\ngoto:101,100,8", 1, true),
    "floor change must record both positions")

  currentPosition = { x = 101, y = 100, z = 8 }
  useCallbacks[1]({ x = 102, y = 100, z = 8 }, 1949, 0, 0)
  assert(context.storage.cavebot.configs[1]:find("use:102,100,8", 1, true),
    "use action must be recorded")

  local target = {
    isItem = function() return true end,
    getPosition = function() return { x = 103, y = 100, z = 8 } end
  }
  useWithCallbacks[1]({}, 3003, target, 0)
  assert(context.storage.cavebot.configs[1]:find("usewith:3003,103,100,8", 1, true),
    "useWith action must be recorded")

  ui.recording.onClick()
  local stoppedConfig = context.storage.cavebot.configs[1]
  positionCallbacks[1]({ x = 104, y = 100, z = 8 }, currentPosition)
  assertEqual(context.storage.cavebot.configs[1], stoppedConfig, "recording off ignores movement")

  ui.recording.onClick()
  context.storage.cavebot.configs = {}
  context.storage.cavebot.activeConfig = 0
  controls.refresh()
  assertEqual(ui.recording:isOn(), false, "removed config disables recording")
end

testCallbackLifecycle()
testRecorder()
print("game_bot auto recording: OK")
