local dialogScript = assert(arg[1], 'missing npcdialog.lua')
local events, cancelled = {}, {}
local function schedule(callback)
  local event = { callback = callback }
  events[#events + 1] = event
  return event
end
addEvent, scheduleEvent = schedule, schedule
removeEvent = function(event) cancelled[event] = true end

local function widget()
  local self = { children = {}, visible = false, pointerCursorActive = false }
  function self:isDestroyed() return false end
  function self:isVisible() return self.visible end
  function self:show() self.visible = true end
  function self:hide() self.visible = false end
  function self:getChildren() return self.children end
  function self:getChildCount() return #self.children end
  function self:destroyChildren() self.children = {} end
  function self:getWidth() return 800 end
  function self:getHeight() return 500 end
  function self:getParent() return nil end
  function self:recursiveGetChildById(id)
    self[id] = rawget(self, id) or widget()
    return self[id]
  end
  function self:getChildById(id) return self:recursiveGetChildById(id) end
  function self:isEnabled() return true end
  return setmetatable(self, { __index = function() return function() end end })
end

local root, dialog = widget(), widget()
g_ui = {
  getRootWidget = function() return root end,
  loadUI = function() return dialog end,
  createWidget = function(_, parent)
    local child = widget()
    if parent then parent.children[#parent.children + 1] = child end
    return child
  end
}
local sent, tradeHidden = 0, 0
g_game = {
  isOnline = function() return true end,
  getLocalPlayer = function() return { getPosition = function() return { x = 100, y = 100, z = 7 } end } end,
  getCharacterName = function() return 'Player' end,
  closeNpcChannel = function() sent = sent + 1 end
}
g_map = { getSpectators = function() return {} end }
g_clock = { millis = function() return 0 end }
m_settings = { getOption = function() return false end }
modules = { game_console = {
  isChatEnabled = function() return true end,
  sendNpcMessage = function() sent = sent + 1; return true end
} }
MessageModes = { NpcFrom = 1, NpcFromStartBlock = 2, Failure = 3 }
registerMessageMode = function() end
tr = function(text, ...) return string.format(text, ...) end
setStringColor = function() end
string.trim = function(text) return text:match('^%s*(.-)%s*$') end
isTrading = function() return false end
hide = function() tradeHidden = tradeHidden + 1 end

assert(loadfile(dialogScript))()
initNpcDialog()
onNpcPlayerTalk('hi')
assert(tryHandleNpcDialogMessage('Captain', 0, MessageModes.NpcFrom, 'Choose your destination.'))
assert(dialog.visible)

local origin = { x = 100, y = 100, z = 7 }
onNpcDialogPositionChange(nil, { x = 101, y = 101, z = 7 }, origin)
assert(dialog.visible and tradeHidden == 0, 'normal steps closed the NPC dialog')
onNpcDialogPositionChange(nil, origin, { x = 65535, y = 65535, z = 255 })
assert(dialog.visible, 'initial map position closed the dialog')

onNpcDialogPositionChange(nil, { x = 733, y = 973, z = 6 }, origin)
assert(not dialog.visible and tradeHidden == 1, 'travel did not close both windows')
assert(sent == 0, 'travel sent farewell/channel packets to the arrival location')
for _, event in ipairs(events) do
  assert(cancelled[event], 'travel left a pending dialog event')
  event.callback() -- even a stale callback must not resurrect the old dialog
end
assert(not dialog.visible)
assert(not tryHandleNpcDialogMessage('Captain', 0, MessageModes.NpcFrom, 'Late travel reply.'))
assert(not dialog.visible, 'a late reply reopened the old NPC dialog')

onNpcPlayerTalk('hi')
assert(tryHandleNpcDialogMessage('New Captain', 0, MessageModes.NpcFrom, 'Welcome!'))
assert(dialog.visible, 'the next NPC could not open a fresh conversation')
onNpcDialogPositionChange(nil, { x = 100, y = 100, z = 6 }, origin)
assert(not dialog.visible and tradeHidden == 2, 'a floor change did not close the dialog')
print('NPC travel dialog lifecycle: passed')
