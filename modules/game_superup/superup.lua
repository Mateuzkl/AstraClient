local OPCODE = 221

local window = nil
local selectedKey = nil
local huntGroup = nil

local function send(message)
  local protocol = g_game.getProtocolGame()
  if protocol and g_game.isOnline() then protocol:sendExtendedOpcode(OPCODE, message) end
end

local function formatRemaining(seconds)
  seconds = math.max(0, tonumber(seconds) or 0)
  local minutes = math.floor(seconds / 60)
  local remainingSeconds = seconds % 60
  if minutes < 10 then minutes = '0' .. minutes end
  if remainingSeconds < 10 then remainingSeconds = '0' .. remainingSeconds end
  return tr('Tempo restante: ') .. minutes .. ':' .. remainingSeconds
end

local function addHunt(key, name, description, lookType)
  local list = window:recursiveGetChildById('huntList')
  local widget = g_ui.createWidget('SuperUpHunt', list)
  widget.huntKey = key
  widget:recursiveGetChildById('name'):setText(name)
  widget:recursiveGetChildById('description'):setText(description)
  widget:recursiveGetChildById('creature'):setOutfit({type = tonumber(lookType) or 0})
  huntGroup:addWidget(widget)
  if not selectedKey then huntGroup:selectWidget(widget) end
end

local function open(payload)
  if not window then return end
  local fields = string.split(payload, '|')
  window:recursiveGetChildById('remaining'):setText(formatRemaining(fields[2]))
  local list = window:recursiveGetChildById('huntList')
  list:destroyChildren()
  selectedKey = nil
  if huntGroup then huntGroup:destroy() end
  huntGroup = UIRadioGroup.create()
  huntGroup.onSelectionChange = function(_, widget, previousWidget)
    if previousWidget then
      local marker = previousWidget:recursiveGetChildById('selected')
      if marker then marker:setVisible(false) end
    end
    selectedKey = widget and widget.huntKey or nil
    if widget then
      local marker = widget:recursiveGetChildById('selected')
      if marker then marker:setVisible(true) end
    end
  end
  for index = 3, #fields do
    local row = string.split(fields[index], '~')
    if #row >= 4 then addHunt(row[1], row[2], row[3], row[4]) end
  end
  window:show()
  window:raise()
  window:focus()
end

-- Opcode 221 is registered by game_skills so its XP tooltip and this window
-- share one receiver without replacing each other's callback.
function onExtendedOpcode(protocol, opcode, buffer)
  if opcode ~= OPCODE then return end
  if buffer == 'close' then close() return end
  if buffer:sub(1, 5) == 'open|' then
    open(buffer)
  elseif buffer:sub(1, 7) == 'active|' then
    close()
  end
end

function init()
  g_ui.importStyle('superup_style')
  window = g_ui.displayUI('superup')
  window:hide()
  connect(g_game, {onGameEnd = close})
end

function terminate()
  disconnect(g_game, {onGameEnd = close})
  if window then window:destroy() window = nil end
  if huntGroup then huntGroup:destroy() huntGroup = nil end
end

function confirm()
  if selectedKey then send('select:' .. selectedKey) end
end

function close()
  if window then window:hide() end
end
