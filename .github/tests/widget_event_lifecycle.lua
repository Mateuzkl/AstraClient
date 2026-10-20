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
env.move(1, widget(), 40, 1, false, false)
lock.f()
assert(lock.cancelled and not container.locked, 'an old move re-locked an unlocked placement')
env.move(1, widget(), 40, 1, false, true)
local supersededLock = events[#events]
env.move(1, widget(), 40, 1, false, true)
local latestLock = events[#events]
supersededLock.f(); assert(supersededLock.cancelled and not container.locked)
latestLock.f(); assert(container.locked, 'the latest requested lock was lost')
container.locked = nil
env.move(1, widget(), 40, 1, false, true)
local destroyedLock = events[#events]
container:destroy(); destroyedLock.f()
assert(destroyedLock.cancelled and not container.locked)

-- Load the entire production TextWindow module and close its real edit dialogs.
-- This reaches the private queueGameFocus through the installed UI callbacks.
load('modules/game_textwindow/textwindow.lua')
local gameRoot = widget()
local focusCalls = 0
gameRoot.focus = function(self) assert(not self.destroyed); focusCalls = focusCalls + 1 end
env.rootWidget = {getChildById = function() return gameRoot end}
env.g_game = {isOnline = function() return true end}
env.g_client.setInputLockWidget = function() end
env.g_things = {getThingType = function() return {hasAttribute = function() return false end} end}
env.ThingAttrWritableOnce, env.ThingAttrWritable = 1, 2
env.tr = function(s) return s end
env.table = setmetatable({removevalue = function(values, target)
  for i, value in ipairs(values) do if value == target then table.remove(values, i); return end end
end}, {__index = table})
local dialog
ui.createWidget = function()
  local window = widget()
  window.children = {}
  function window:getChildById(id)
    if not self.children[id] then
      local child = widget()
      for _, name in ipairs({'setItemId', 'setMaxLength', 'setText', 'setEditable',
        'setCursorVisible', 'setCursorPos', 'setMarginTop', 'setMarginRight',
        'setWidth', 'setHeight', 'setValue'}) do child[name] = function() end end
      child.isHidden = function() return false end
      child.getHeight = function() return 64 end
      child.hide = function() end
      self.children[id] = child
    end
    return self.children[id]
  end
  window.setText, window.focusChild = function() end, function() end
  dialog = window
  return window
end
local function closeTextDialog(kind)
  if kind == 'text' then
    env.onGameEditText(1, 100, 100, 'editable text', '', '')
    dialog.children.cancelButton.onClick()
  else
    env.onGameEditList(1, 2, 'guest')
    dialog.onEscape()
  end
  assert(dialog.destroyed and #env.windows == 0)
  return events[#events]
end
local firstFocus = closeTextDialog('text')
assert(firstFocus.delay == 50 and focusCalls == 0)
local listFocus = closeTextDialog('list')
assert(firstFocus.cancelled, 'real TextWindow close did not replace the pending focus')
firstFocus.f(); assert(focusCalls == 0)
listFocus.f(); assert(focusCalls == 1, 'real TextWindow close did not return focus')
local logoutFocus = closeTextDialog('text')
env.destroyWindows(); logoutFocus.f()
assert(logoutFocus.cancelled and focusCalls == 1, 'TextWindow focus survived logout cleanup')
local destroyedFocus = closeTextDialog('list')
gameRoot:destroy(); destroyedFocus.f()
assert(destroyedFocus.cancelled and focusCalls == 1, 'TextWindow focused a destroyed game panel')
gameRoot = nil
local beforeNoPanel = #events
closeTextDialog('text')
assert(#events == beforeNoPanel, 'TextWindow scheduled focus without a game panel')

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
