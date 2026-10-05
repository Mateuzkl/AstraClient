-- Exercise the production module's ownership/scheduling without graphics or a server.
local function count(values) local n = 0; for _ in pairs(values) do n = n + 1 end; return n end
local events, windows, buttons, bindings = {}, {}, {}, {}
local measured = 0
local window
local function newWidget(collection)
  local widget = {visible = false}
  collection[widget] = true
  function widget:destroy() assert(collection[self], 'double destroy'); collection[self] = nil end
  function widget:setOn(_) end
  return widget
end
local env = {
  g_keyboard = {
    bindKeyDown = function(key, fn) assert(not bindings[key]); bindings[key] = fn end,
    unbindKeyDown = function(key, fn) assert(bindings[key] == fn); bindings[key] = nil end,
  },
  g_ui = {displayUI = function() return newWidget(windows) end},
  modules = {client_topmenu = {addLeftButton = function() return newWidget(buttons) end}},
  scheduleEvent = function(fn) local event = {}; events[event] = fn; return event end,
  removeEvent = function(event) events[event] = nil end,
  g_logger = {warning = function() end},
  g_memLeak = {
    uiInit = function(value) assert(not window); window = value end,
    uiTerminate = function() if window then window:destroy(); window = nil end end,
    toggle = function() window.visible = not window.visible end,
    hide = function() if window then window.visible = false end end,
    isWindowVisible = function() return window and window.visible end,
  },
}
for _, name in ipairs({'updateMemoryDisplay', 'updateObjectCounts', 'updateEventDisplay', 'updateMemoryBreakdown'}) do
  env.g_memLeak[name] = function() assert(window and window.visible, 'collection while closed'); measured = measured + 1 end
end
setmetatable(env, {__index = _G})
local chunk = assert(loadfile('modules/game_memleak/memleak.lua')); setfenv(chunk, env); chunk()
for _ = 1, 20 do
  env.init(); env.init()
  assert(count(bindings) == 1 and count(buttons) == 1 and count(windows) == 0 and count(events) == 0,
    'init must be idempotent and allocate no monitoring window/events')
  env.toggle()
  assert(count(windows) == 1 and count(events) == 2 and measured > 0)
  local ticks = {}; for event, fn in pairs(events) do ticks[event] = fn end
  local beforeTick = measured
  for event, fn in pairs(ticks) do
    events[event] = nil -- The dispatcher consumes a scheduled event before its callback.
    fn()
    assert(count(events) == 2 and not events[event], 'each tick must replace only its own event')
  end
  assert(measured == beforeTick + 4, 'both production sampling callbacks must execute')
  local stale = {}; for _, fn in pairs(events) do stale[#stale + 1] = fn end
  env.onClose(); env.onClose()
  assert(count(events) == 0 and not window.visible)
  local before = measured
  for _, fn in ipairs(stale) do fn() end
  assert(measured == before and count(events) == 0, 'stale callbacks must not collect or requeue')
  env.toggle()
  for _, fn in ipairs(stale) do fn() end
  assert(count(events) == 2, 'old callbacks must not overwrite the new timer handles')
  env.onClose()
  assert(count(events) == 0, 'both current timers remain cancellable')
  env.toggle()
  local afterReload = {}; for _, fn in pairs(events) do afterReload[#afterReload + 1] = fn end
  env.terminate(); env.terminate()
  assert(count(events) == 0 and count(windows) == 0 and count(buttons) == 0 and count(bindings) == 0)
  for _, fn in ipairs(afterReload) do fn() end
  assert(count(events) == 0, 'late callbacks after unload must stay stopped')
end
env.g_memLeak = nil
env.init()
assert(count(bindings) == 0 and count(windows) == 0, 'old binaries must fail gracefully')
env.terminate()
print('Memory monitor module: lazy UI, visibility, stale callbacks and repeated reloads passed')
