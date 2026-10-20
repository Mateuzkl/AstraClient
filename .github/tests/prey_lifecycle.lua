local function loadProduction(path)
  local env = setmetatable({}, {__index = _G})
  env.g_game = {isOnline = function() return true end}
  env.ProtocolGame = {unregisterOpcode = function() end}
  env.disconnect = function() end
  env.g_keyboard = {unbindKeyPress = function() end}
  env.g_ui = {getCustomInputWidget = function() return env.inputLockWidget end}
  env.g_client = {setInputLockWidget = function(widget)
    assert(not env.inputLockWidget or not env.inputLockWidget.destroyed,
      'input lock must be released before destroying its widget')
    env.inputLockWidget = widget
    env.lockChanges = (env.lockChanges or 0) + 1
  end}
  env.removeEvent = function(e) if e then e.cancelled = true end end
  local f = assert(loadfile(path)); setfenv(f, env); f()
  return env
end
local function seed(fn, event)
  for i = 1, 100 do
    local name = debug.getupvalue(fn, i)
    if name == 'updateRerollEvent' then debug.setupvalue(fn, i, event); return end
    if not name then break end
  end
  error('production reroll event not found')
end
local function widget()
  return {destroy = function(self) assert(not self.destroyed); self.destroyed = true end,
    isVisible = function(self) assert(not self.destroyed, 'access after destroy'); return true end,
    hide = function(self) self.hidden = true end}
end
local prey = loadProduction('modules/game_prey/prey.lua')
for _ = 1, 2 do
  local window, tracker, event = widget(), widget(), {}
  prey.preyWindow, prey.preyTracker = window, tracker
  seed(prey.updateRerollTime, event)
  prey.terminate()
  assert(event.cancelled and window.destroyed and tracker.destroyed)
  assert(prey.preyWindow == nil and prey.preyTracker == nil)
  prey.updateRerollTime() -- A callback already queued before cancel is harmless.
end
local hunting = loadProduction('mods/game_prey_hunting/hunting.lua')
for iteration = 1, 2 do
  local window, event = widget(), {}
  hunting.huntingWindow = window
  hunting.huntingSlots = {{window = window}}
  local lockOwner = iteration == 1 and window or widget()
  hunting.g_client.setInputLockWidget(lockOwner)
  local lockChanges = hunting.lockChanges
  seed(hunting.hide, event)
  hunting.terminate()
  assert(event.cancelled and window.destroyed and hunting.huntingWindow == nil)
  assert(next(hunting.huntingSlots) == nil)
  if lockOwner == window then
    assert(hunting.inputLockWidget == nil and hunting.lockChanges == lockChanges + 1)
  else
    assert(hunting.inputLockWidget == lockOwner and hunting.lockChanges == lockChanges,
      'Hunting teardown stole another window input lock')
  end
  hunting.updateVisibleRerollTime()
end
local event = {}
hunting.huntingWindow = widget()
seed(hunting.hide, event)
hunting.offline()
assert(event.cancelled and hunting.huntingWindow.hidden)
print('Prey/Hunting timer ownership, online unload and repeat teardown: OK')
