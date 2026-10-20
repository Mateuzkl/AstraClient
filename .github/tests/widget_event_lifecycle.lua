local env = setmetatable({}, {__index = _G})
local events, hooks, connections = {}, {}, 0
env.g_ui, env.UIWidget, env.g_client = {}, {}, {}
env.connect = function(widget, callbacks)
  assert(not hooks[widget], 'duplicate destroy hook')
  hooks[widget] = callbacks.onDestroy; connections = connections + 1
end
env.scheduleEvent = function(f, delay)
  local e = {f = f, delay = delay}; events[#events + 1] = e; return e
end
env.addEvent = function(f) return env.scheduleEvent(f, 0) end
env.removeEvent = function(e) e.cancelled = true end
local function load(path)
  local f = assert(loadfile(path)); setfenv(f, env); f()
end
load('modules/corelib/ui/uiwidget.lua')
local ui = env.g_ui
local function widget()
  local w = {touches = 0}
  function w:isDestroyed() return self.destroyed or false end
  function w:destroy() self.destroyed = true; if hooks[self] then hooks[self](self) end end
  function w:setParent(parent) assert(not self.destroyed); self.parent = parent; self.touches = self.touches + 1 end
  function w:open() assert(not self.destroyed) end
  return w
end
local w = widget()
local n = 0
local first = ui.scheduleWidgetEvent(w, function() n = n + 1 end, 10, 'move')
local second = ui.scheduleWidgetEvent(w, function() n = n + 10 end, 10, 'move')
first.f(); second.f(); assert(n == 10 and first.cancelled)
assert(connections == 1)
local pending = ui.scheduleWidgetEvent(w, function() error('destroyed widget callback') end, 50)
w:destroy(); assert(pending.cancelled); pending.f()
assert(ui.scheduleWidgetEvent(w, function() end) == nil)
local stale = setmetatable({}, {__index = function() error('stale native lookup') end})
assert(not ui.isWidgetAlive(stale))
local live = widget()
local cancelled = ui.scheduleWidgetEvent(live, function() error('old generation') end)
ui.cancelWidgetEvents(live); cancelled.f()
local new = ui.scheduleWidgetEvent(live, function() n = n + 1 end)
new.f(); assert(n == 11 and connections == 2, 'cancel/reschedule duplicated the hook')

-- Exercise the actual deferred inventory move with a destroyed destination.
local source = assert(io.open('modules/game_inventory/inventory.lua', 'rb'))
local text = source:read('*a'); source:close()
local move = assert(text:match('(function move%(panel, index, minimized%).-\nend)'))
local f = assert(loadstring(move)); setfenv(f, env); f()
env.inventoryWindow = widget()
env.onInventoryMinimize = function() end
local panel = widget()
env.move(panel, 1, false); local delayed = events[#events]
panel:destroy(); delayed.f()
assert(env.inventoryWindow.touches == 0)
env.move(widget(), 1, false); local cancelledMove = events[#events]
env.inventoryWindow:destroy(); cancelledMove.f()
assert(cancelledMove.cancelled)

local function loadFunction(path, signature)
  local file = assert(io.open(path, 'rb')); local source = file:read('*a'); file:close()
  local code = assert(source:match('(' .. signature .. '.-\nend)'), signature)
  local chunk = assert(loadstring(code)); setfenv(chunk, env); chunk()
end

loadFunction('modules/game_healthinfo/healthinfo.lua', 'function move%(panel, index%)')
env.m_settings = {getOption = function() return true end}
env.healthInfoWindow = widget()
env.healthInfoWindow.isVisible = function() return true end
local healthPanel = widget()
env.move(healthPanel, 1); local healthMove = events[#events]
healthPanel:destroy(); healthMove.f()
assert(not env.healthInfoWindow.parent)

loadFunction('modules/game_containers/containers.lua', 'function move%(instance, panel, height, index, minimized, locked%)')
local container = widget()
container.setHeight, container.maximize = function() end, function() end
container.lock = function(self) assert(not self.destroyed); self.locked = true end
env.rootWidget = {recursiveGetChildById = function() return container end}
env.move(1, widget(), 40, 1, false, true)
local lock = events[#events]
container:destroy(); lock.f()
assert(lock.cancelled and not container.locked)

loadFunction('modules/game_textwindow/textwindow.lua', 'function destroyWindows%(%)')
local gameRoot = widget()
env.rootWidget = {getChildById = function() return gameRoot end}
env.windows = {}
local focus = ui.scheduleWidgetEvent(gameRoot, function() error('focus after logout') end, 50, 'textWindowFocus')
env.destroyWindows(); focus.f(); assert(focus.cancelled)

loadFunction('mods/game_tibia_market/t_market.lua', 'function onRedirect%(item%)')
local redirect
env.onShowRedirect = function(snapshot) redirect = snapshot end
env.g_game = {isOnline = function() return true end, sendMarketAction = function() end}
env.marketWindow = widget()
local item = {getId = function() return 2160 end, getClassification = function() return 3 end}
env.onRedirect(item); local redirectEvent = events[#events]
item.getId, item.getClassification = function() error('retained item') end, function() error('retained item') end
redirectEvent.f()
assert(redirect.id == 2160 and redirect.classification == 3)
env.onRedirect({getId = function() return 100 end, getClassification = function() return 0 end})
local destroyedRedirect = events[#events]
env.marketWindow:destroy(); destroyedRedirect.f()
assert(destroyedRedirect.cancelled and redirect.id == 2160)
print('Widget event ownership, replacement, cancellation and stale destinations: OK')
