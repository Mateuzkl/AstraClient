-- Exercise production lifecycle functions without a game server or graphics.
local function check(value, message) assert(value, message) end
local function count(values) local n = 0; for _ in pairs(values) do n = n + 1 end; return n end
local events, windows = {}, {}
local online = false
local connections = {}
local parent = {getChildCount = function() return 1 end, moveChildToIndex = function() end}
local function widget()
  return {
    setId = function() end, setVisible = function() end, setFocusable = function() end,
    destroy = function(self) windows[self] = nil end,
    isVisible = function(self) return self.visible == true end,
    open = function(self) self.visible = true end,
    close = function(self) self.visible = false end,
    getParent = function() return parent end,
    setParent = function() end, maximize = function() end, minimize = function() end,
    setHeight = function() end, getMinimumHeight = function() return 86 end,
    isOpened = function(self) return self.visible == true end,
  }
end
local env = setmetatable({
  KeyBind = {getKeyBind = function() return {active = function() end, deactive = function() end} end},
  g_ui = {importStyle = function() end, createWidget = widget},
  g_game = {isOnline = function() return online end},
  connect = function(_, handlers) for name, handler in pairs(handlers) do connections[name] = handler end end,
  disconnect = function(_, handlers) for name in pairs(handlers) do connections[name] = nil end end,
  scheduleEvent = function(fn) local event = {}; events[event] = fn; return event end,
  removeEvent = function(event) events[event] = nil end,
  m_interface = {addToPanels = function() return true end},
  modules = {game_sidebuttons = {setButtonVisible = function() end}},
  tr = function(text) return text end,
}, {__index = _G})
env.addEvent = env.scheduleEvent
env.BattleClass = {create = function()
  return {
    buttons = {}, sortType = {},
    configure = function(self)
      self.window = widget(); windows[self.window] = true
      self.panel = {setSortType = function() end}
    end,
    setSecondary = function(self, value) self.secondary = value end,
    getWindow = function(self) return self.window end,
    showBattle = function(self) self.window:open() end,
    setName = function() end,
  }
end}
local battleChunk = assert(loadfile('modules/game_battle/battle.lua'))
setfenv(battleChunk, env); battleChunk()
env.init()
check(count(windows) == 1, 'startup creates only the primary BattleWindow')
check(count(events) == 0, 'offline startup has no recurring Battle List timer')
env.addBattleWindow()
check(count(windows) == 2, 'secondary list is created on demand')
check(env.battleClasses[2].window:isVisible(), 'secondary list opens')
local config = {name = 'Saved', battleListFilters = {}, battleListSortOrder = {'byAgeAscending'},
  contentMaximized = true, contentHeight = 120, showFilters = true}
env.onPlayerLoad({['3'] = config, ['99'] = config})
check(count(windows) == 3 and env.battleClasses[4].window, 'saved noncontiguous instance restores lazily')
check(count(events) == 1, 'invalid saved instance is ignored')
env.onGameEnd()
check(count(events) == 0, 'logout cancels pending panel callbacks')
local originalCheck = env.checkCreatures
env.checkCreatures = function() end
online = true
connections.onGameStart()
check(count(events) == 1, 'login starts one Battle List timer')
env.updateBattleList()
check(count(events) == 1, 'repeated updates do not multiply timers')
online = false
connections.onGameEnd()
check(count(events) == 0, 'logout stops Battle List polling')
env.checkCreatures = originalCheck
env.terminate()
check(count(windows) == 0 and count(events) == 0 and count(connections) == 0, 'terminate releases windows and events')
for _ = 1, 50 do env.init(); env.terminate() end
check(count(windows) == 0 and count(events) == 0, '50 reloads do not accumulate windows or callbacks')

-- Find the scheduler captured by the actual Quest Tracker functions.
local function findUpvalue(fn, name, seen)
  seen = seen or {}
  if seen[fn] then return end
  seen[fn] = true
  for i = 1, math.huge do
    local key, value = debug.getupvalue(fn, i)
    if not key then return end
    if key == name then return value end
    if type(value) == 'function' then
      local found = findUpvalue(value, name, seen)
      if found then return found end
    end
  end
end
local questEnv = setmetatable({
  g_game = {isOnline = function() return true end, getClientVersion = function() return 860 end},
  scheduleEvent = env.scheduleEvent, removeEvent = env.removeEvent,
  connect = function() end, disconnect = function() end,
}, {__index = _G})
local questChunk = assert(loadfile('modules/game_trackers/classes/quest_tracker.lua'))
setfenv(questChunk, questEnv); questChunk()
local quest = questEnv.Tracker.Quest
quest.init()
quest.getSettings().autoUntrackCompleted = true
local schedule = findUpvalue(quest.rebuildFromSettings, 'scheduleAutoUntrack')
check(schedule, 'test reaches the production auto-untrack scheduler')
schedule(1000); schedule(5000)
check(count(events) == 1, 'auto-untrack has exactly one scheduled chain')
local event, callback = next(events); events[event] = nil; callback()
check(count(events) == 1, 'periodic callback schedules exactly one successor')
quest.getSettings().autoUntrackCompleted = false
schedule(1000)
check(count(events) == 0, 'disabling auto-untrack cancels its timer')
quest.getSettings().autoUntrackCompleted = true
schedule(1000); quest.onGameEnd()
check(count(events) == 0, 'logout cancels tracker events even after a client-version change')
quest.init(); schedule(1000); quest.terminate()
check(count(events) == 0, 'tracker termination cancels its timer')
print('Startup/module lifecycle: OK')
