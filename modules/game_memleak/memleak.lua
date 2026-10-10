-- Optional diagnostic UI; allocate the window and schedule work only when opened.
local window, button, monitorEvent, updateEvent
local initialized = false
local generation = 0
local hotkey = 'Ctrl+Alt+M'
local performanceLabels = {}
local performanceSamples = {}
local performanceSnapshot
local sampleInterval = 2000
local maxSamples = 120

local function setPerformanceText(id, value)
  local label = performanceLabels[id]
  if label and not label:isDestroyed() and label:getText() ~= value then label:setText(value) end
end

local function validMetric(value, minimum)
  return type(value) == 'number' and value == value and value < math.huge and value >= minimum and value or nil
end

local function readPerformance()
  local online = g_game and g_game.isOnline and g_game.isOnline()
  local ping = online and g_game.getPing and validMetric(g_game.getPing(), 0) or nil
  local proxyPing = online and g_proxy and g_proxy.getPing and validMetric(g_proxy.getPing(), 1) or nil
  return {
    timestamp = g_clock.realMillis(),
    fps = g_app and g_app.getFps and validMetric(g_app.getFps(), 0) or nil,
    ping = ping,
    proxyPing = proxyPing
  }
end

local function metricText(value, unit)
  return value and string.format('%.0f%s', value, unit) or 'unavailable'
end

local function metricSummary(key)
  local total, count, low, high = 0, 0, math.huge, 0
  for _, sample in ipairs(performanceSamples) do
    local value = sample[key]
    if value then
      total, count = total + value, count + 1
      low, high = math.min(low, value), math.max(high, value)
    end
  end
  if count == 0 then return 'unavailable' end
  return string.format('avg %.0f / min %.0f / max %.0f', total / count, low, high)
end

local function updatePerformance(delay)
  local sample = readPerformance()
  sample.delay = delay -- The initial sample has no preceding scheduled deadline.
  performanceSamples[#performanceSamples + 1] = sample
  if #performanceSamples > maxSamples then table.remove(performanceSamples, 1) end
  setPerformanceText('perfCurrent', 'FPS: ' .. metricText(sample.fps, '') .. ' | Game ping: ' .. metricText(sample.ping, ' ms') ..
    ' | Proxy ping: ' .. metricText(sample.proxyPing, ' ms'))
  return sample
end

local function updatePerformanceHistory()
  local span = (performanceSamples[#performanceSamples].timestamp - performanceSamples[1].timestamp) / 1000
  setPerformanceText('perfHistory', string.format('Sampled over %.1fs (%d/%d; every 2s):\nFPS: %s\nGame ping (ms): %s\nMonitor timer delay (ms): %s\nMonitor collection work (ms): %s',
    span, #performanceSamples, maxSamples, metricSummary('fps'), metricSummary('ping'), metricSummary('delay'), metricSummary('work')))
end

local function stopMonitoring()
  generation = generation + 1
  if monitorEvent then removeEvent(monitorEvent); monitorEvent = nil end
  if updateEvent then removeEvent(updateEvent); updateEvent = nil end
end

local function startMonitoring()
  stopMonitoring()
  performanceSamples = {}
  performanceSnapshot = nil
  setPerformanceText('perfDiff', 'Snapshot/Diff also compares FPS and ping. Unavailable readings are not zero.')
  local expected = generation
  local sampleDeadline
  local function memoryTick()
    if expected ~= generation or not initialized then return end
    monitorEvent = nil
    if not g_memLeak.isWindowVisible() then return end
    local started = g_clock.realMillis()
    local delay = sampleDeadline and math.max(0, started - sampleDeadline) or nil
    local sample = updatePerformance(delay)
    g_memLeak.updateMemoryDisplay()
    if expected ~= generation or not initialized or not g_memLeak.isWindowVisible() then return end
    sample.work = math.max(0, g_clock.realMillis() - started)
    updatePerformanceHistory()
    -- Use the native event's deadline: its clock may be cached within a frame.
    -- Real time above measures callback work without mistaking it for lateness.
    monitorEvent = scheduleEvent(memoryTick, sampleInterval)
    sampleDeadline = monitorEvent:ticks()
  end
  local function detailTick()
    if expected ~= generation or not initialized then return end
    updateEvent = nil
    if not g_memLeak.isWindowVisible() then return end
    g_memLeak.updateObjectCounts()
    g_memLeak.updateEventDisplay()
    g_memLeak.updateMemoryBreakdown()
    updateEvent = scheduleEvent(detailTick, 5000)
  end
  memoryTick()
  detailTick()
end

function init()
  if initialized then return end
  if not g_memLeak then
    g_logger.warning('Memory monitor requires an updated AstraClient executable. Rebuild the client first.')
    return
  end
  initialized = true
  g_keyboard.bindKeyDown(hotkey, toggle)
  button = modules.client_topmenu.addLeftButton('memLeakButton', 'Memory Monitor', '/images/topbuttons/debug', toggle)
  button:setOn(false)
end

function terminate()
  stopMonitoring()
  if initialized then g_keyboard.unbindKeyDown(hotkey, toggle) end
  initialized = false
  if g_memLeak then g_memLeak.uiTerminate() end
  window = nil -- C++ destroys the owned window and drops all child references.
  performanceLabels = {}
  performanceSamples = {}
  performanceSnapshot = nil
  if button then button:destroy(); button = nil end
end

function toggle()
  if not initialized then return end
  if not window then
    window = g_ui.displayUI('memleak')
    if not window then return end
    for _, id in ipairs({'perfCurrent', 'perfHistory', 'perfDiff'}) do
      performanceLabels[id] = window:recursiveGetChildById(id)
    end
    g_memLeak.uiInit(window)
  end
  g_memLeak.toggle()
  local visible = g_memLeak.isWindowVisible()
  if button then button:setOn(visible) end
  if visible then startMonitoring() else stopMonitoring() end
end

function onClose()
  stopMonitoring()
  if g_memLeak then g_memLeak.hide() end
  if button then button:setOn(false) end
end

function takeSnapshot()
  if not initialized or not g_memLeak.isWindowVisible() then return end
  performanceSnapshot = readPerformance()
  g_memLeak.takeSnapshot()
  setPerformanceText('perfDiff', 'Snapshot: FPS ' .. metricText(performanceSnapshot.fps, '') ..
    ' | Game ping ' .. metricText(performanceSnapshot.ping, ' ms'))
end

function showDiff()
  if not initialized or not g_memLeak.isWindowVisible() then return end
  g_memLeak.computeDiff()
  if not performanceSnapshot then
    setPerformanceText('perfDiff', 'Take a Snapshot first to compare FPS and ping.')
    return
  end
  local sample = readPerformance()
  local function change(key, unit)
    local before, after = performanceSnapshot[key], sample[key]
    if not before or not after then return 'unavailable' end
    return metricText(before, unit) .. ' -> ' .. metricText(after, unit) .. string.format(' (%+.0f%s)', after - before, unit)
  end
  setPerformanceText('perfDiff', string.format('Performance diff over %.1fs:\nFPS: %s | Game ping: %s\nProxy ping: %s',
    (sample.timestamp - performanceSnapshot.timestamp) / 1000, change('fps', ''), change('ping', ' ms'), change('proxyPing', ' ms')))
end
function clearAlerts() g_memLeak.clearAlerts() end
function forceGC() g_memLeak.forceGC() end
