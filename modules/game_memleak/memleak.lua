-- Optional diagnostic UI; allocate the window and schedule work only when opened.
local window, button, monitorEvent, updateEvent
local initialized = false
local generation = 0
local hotkey = 'Ctrl+Alt+M'

local function stopMonitoring()
  generation = generation + 1
  if monitorEvent then removeEvent(monitorEvent); monitorEvent = nil end
  if updateEvent then removeEvent(updateEvent); updateEvent = nil end
end

local function startMonitoring()
  stopMonitoring()
  local expected = generation
  local function memoryTick()
    if expected ~= generation or not initialized then return end
    monitorEvent = nil
    if not g_memLeak.isWindowVisible() then return end
    g_memLeak.updateMemoryDisplay()
    monitorEvent = scheduleEvent(memoryTick, 2000)
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
  if button then button:destroy(); button = nil end
end

function toggle()
  if not initialized then return end
  if not window then
    window = g_ui.displayUI('memleak')
    if not window then return end
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

function takeSnapshot() g_memLeak.takeSnapshot() end
function showDiff() g_memLeak.computeDiff() end
function clearAlerts() g_memLeak.clearAlerts() end
function forceGC() g_memLeak.forceGC() end
