-- Exercise the production module's ownership/scheduling without graphics or a server.
local function count(values) local n = 0; for _ in pairs(values) do n = n + 1 end; return n end
local events, windows, buttons, bindings = {}, {}, {}, {}
local function activeEvents()
  local n = 0
  for _, event in pairs(events) do if not event.canceled then n = n + 1 end end
  return n
end
local function activeCallbacks()
  local callbacks = {}
  for event, entry in pairs(events) do
    if not entry.canceled then callbacks[event] = entry.callback end
  end
  return callbacks
end
local function drainCanceled()
  for event, entry in pairs(events) do
    if entry.canceled then
      assert(not entry.callback, 'canceled entries must release their callback before the deadline')
      events[event] = nil
    end
  end
end
local measured = 0
local now, fps, ping, proxyPing, online = 0, 61, 51, 0, true
local window
local function newWidget(collection)
  local widget = {visible = false}
  collection[widget] = true
  function widget:destroy() assert(collection[self], 'double destroy'); collection[self] = nil end
  function widget:setOn(_) end
  widget.labels = {}
  function widget:recursiveGetChildById(id)
    if not self.labels[id] then
      self.labels[id] = {text = '', isDestroyed = function() return false end,
        getText = function(label) return label.text end, setText = function(label, value) label.text = value end}
    end
    return self.labels[id]
  end
  return widget
end
local env = {
  g_clock = {millis = function() return now end},
  g_app = {getFps = function() return fps end},
  g_game = {isOnline = function() return online end, getPing = function() return ping end},
  g_proxy = {getPing = function() return proxyPing end},
  g_keyboard = {
    bindKeyDown = function(key, fn) assert(not bindings[key]); bindings[key] = fn end,
    unbindKeyDown = function(key, fn) assert(bindings[key] == fn); bindings[key] = nil end,
  },
  g_ui = {displayUI = function() return newWidget(windows) end},
  modules = {client_topmenu = {addLeftButton = function() return newWidget(buttons) end}},
  scheduleEvent = function(fn, delay) local event = {}; events[event] = {callback = fn, canceled = false, delay = delay}; return event end,
  removeEvent = function(event)
    -- Like the real dispatcher: release the callback, retain the queue entry until poll().
    local entry = assert(events[event]); entry.canceled = true; entry.callback = nil
  end,
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
  assert(count(windows) == 1 and activeEvents() == 2 and measured > 0)
  assert(window.labels.perfCurrent.text:find('FPS: 61', 1, true) and window.labels.perfCurrent.text:find('Game ping: 51 ms', 1, true))
  local ticks = activeCallbacks()
  local beforeTick = measured
  for event, fn in pairs(ticks) do
    events[event] = nil -- The dispatcher consumes a scheduled event before its callback.
    fn()
    assert(activeEvents() == 2 and not events[event], 'each tick must replace only its own event')
  end
  assert(measured == beforeTick + 4, 'both production sampling callbacks must execute')
  local stale = {}; for _, fn in pairs(activeCallbacks()) do stale[#stale + 1] = fn end
  env.onClose(); env.onClose()
  assert(activeEvents() == 0 and count(events) == 2 and not window.visible,
    'close cancels callbacks but does not immediately erase dispatcher queue entries')
  local before = measured
  for _, fn in ipairs(stale) do fn() end
  assert(measured == before and activeEvents() == 0, 'stale callbacks must not collect or requeue')
  env.toggle()
  for _, fn in ipairs(stale) do fn() end
  assert(activeEvents() == 2, 'old callbacks must not overwrite the new timer handles')
  env.onClose()
  assert(activeEvents() == 0, 'both current timers remain cancellable')
  env.toggle()
  local afterReload = {}; for _, fn in pairs(activeCallbacks()) do afterReload[#afterReload + 1] = fn end
  env.terminate(); env.terminate()
  assert(activeEvents() == 0 and count(windows) == 0 and count(buttons) == 0 and count(bindings) == 0)
  for _, fn in ipairs(afterReload) do fn() end
  assert(activeEvents() == 0, 'late callbacks after unload must stay stopped')
  drainCanceled()
  assert(count(events) == 0, 'dispatcher eventually removes canceled entries')
end
-- Performance uses the same visible-only memory timer, with bounded history.
local snapshots, diffs = 0, 0
env.g_memLeak.takeSnapshot = function() snapshots = snapshots + 1 end
env.g_memLeak.computeDiff = function() diffs = diffs + 1 end
env.init(); env.toggle()
fps, ping, proxyPing = 60, 50, 55
env.takeSnapshot()
assert(snapshots == 1 and window.labels.perfDiff.text:find('FPS 60', 1, true))
local function sample(elapsed)
  now = now + elapsed
  for event, entry in pairs(events) do
    if not entry.canceled and entry.delay == 2000 then
      local fn = entry.callback; events[event] = nil; fn(); return
    end
  end
  error('missing memory/performance timer')
end
for i = 1, 150 do fps = i % 2 == 0 and 30 or 60; sample(2000) end
assert(window.labels.perfHistory.text:find('(120/120;', 1, true), 'performance history must remain bounded')
assert(window.labels.perfHistory.text:find('FPS: avg 45 / min 30 / max 60', 1, true))
ping, proxyPing = 250, 60; sample(2300)
assert(window.labels.perfHistory.text:find('max 300', 1, true), 'late timers must be reported separately from network ping')
env.showDiff()
assert(diffs == 1 and window.labels.perfDiff.text:find('60 -> 30 (-30)', 1, true))
assert(window.labels.perfDiff.text:find('50 ms -> 250 ms (+200 ms)', 1, true))
online = false; sample(2000)
assert(window.labels.perfCurrent.text:find('Game ping: unavailable', 1, true), 'offline is not zero ping')
online, ping, proxyPing, fps = true, -1, 0, 0; sample(2000)
assert(window.labels.perfCurrent.text:find('FPS: 0', 1, true) and window.labels.perfCurrent.text:find('Game ping: unavailable', 1, true))
fps, ping, proxyPing = 0 / 0, math.huge, -1; sample(2000)
assert(window.labels.perfCurrent.text:find('FPS: unavailable', 1, true) and window.labels.perfCurrent.text:find('Game ping: unavailable', 1, true),
  'non-finite metrics must be treated as unavailable')
env.g_app, env.g_proxy = nil, nil; sample(2000)
assert(window.labels.perfCurrent.text:find('FPS: unavailable', 1, true), 'missing metrics must not fabricate readings')
env.onClose(); env.takeSnapshot(); env.showDiff()
assert(snapshots == 1 and diffs == 1 and activeEvents() == 0, 'closed diagnostics must not sample or snapshot')
env.toggle()
assert(window.labels.perfHistory.text:find('(1/120;', 1, true), 'reopening must reset performance history')
env.showDiff()
assert(window.labels.perfDiff.text:find('Take a Snapshot first', 1, true), 'old performance baselines must not survive reopening')
env.terminate(); drainCanceled()

env.g_memLeak = nil
env.init()
assert(count(bindings) == 0 and count(windows) == 0, 'old binaries must fail gracefully')
env.terminate()
local source = assert(io.open('src/client/memleakmanager.cpp', 'rb'))
local cpp = source:read('*a'); source:close()
local periodic = assert(cpp:match('void MemLeakManager::updateObjectCounts%(%)%s*(.-)void MemLeakManager::updateMemoryBreakdown'))
assert(periodic:find('g_stats.getObjectCounts()', 1, true), 'periodic metrics must use cheap production counters')
assert(not periodic:find('getWidgetsInfo', 1, true), 'periodic sampling must not build the widget tree/source report')
local _, scans = cpp:gsub('g_stats%.getWidgetsInfo%(', '')
assert(scans == 2, 'full widget reports are reserved for explicit Snapshot/Diff')
local memoryDisplay = assert(cpp:match('void MemLeakManager::updateMemoryDisplay%(%)%s*(.-)void MemLeakManager::updateObjectCounts'))
assert(memoryDisplay:find('m_history.add(*privateCommit, lua,', 1, true),
  'growth history must sample private commit, not working set/capacity')
assert(memoryDisplay:find('if (!privateCommit)', 1, true), 'unavailable private commit must not create fake samples')
local snapshot = assert(cpp:match('void MemLeakManager::takeSnapshot%(%)%s*(.-)std::string MemLeakManager::computeDiff'))
assert(snapshot:find('privateMemoryUsage()', 1, true) and not snapshot:find('g_platform.getMemoryUsage', 1, true),
  'snapshot memory baseline must use the same private-commit metric as alerts')
assert(cpp:find('Private commit delta: unavailable', 1, true), 'failed snapshot queries must not produce false deltas')
assert(cpp:find('Scheduled queue entries (includes canceled, awaiting removal)', 1, true),
  'queue entries must not be advertised as active callbacks')
print('Memory monitor: lazy lifecycle, bounded FPS/ping history, timer delay and Snapshot/Diff passed')
