local overlay
local keypad
local touchStart = 0
local updateCursorEvent
local initScaleEvent
local zoomInButton
local zoomOutButton
local keypadButton
local keypadEvent
local keypadMousePos = {x=0.5, y=0.5}
local keypadTicks = 0

-- public functions
function init()
  if not g_app.isMobile() then return end
  overlay = g_ui.displayUI('mobile')
  if not overlay then return end
  keypad = overlay.keypad
  overlay:raise()

  zoomInButton = modules.client_topmenu.addLeftButton('zoomInButton', 'Zoom In', '/images/topbuttons/zoomin', function() g_app.scaleUp() end)
  zoomOutButton = modules.client_topmenu.addLeftButton('zoomOutButton', 'Zoom Out', '/images/topbuttons/zoomout', function() g_app.scaleDown() end)
  keypadButton = modules.client_topmenu.addLeftGameToggleButton('keypadButton', 'Keypad', '/images/topbuttons/keypad', function()
    keypadButton:setChecked(not keypadButton:isChecked())
    if not g_game.isOnline() then
      if keypad then keypad:setVisible(false) end
      return
    end
    if keypad then keypad:setVisible(keypadButton:isChecked()) end
  end)
  keypadButton:setChecked(true)

  initScaleEvent = scheduleEvent(function()
    g_app.scale(5.0)
  end, 10)

  connect(overlay, {
    onMousePress = onMousePress,
    onMouseRelease = onMouseRelease,
    onTouchPress = onMousePress,
    onTouchRelease = onMouseRelease
  })
  if keypad then
    connect(keypad, {
      onTouchPress = onKeypadTouchPress,
      onTouchRelease = onKeypadTouchRelease,
      onMouseMove = onKeypadTouchMove
    })
  end
  connect(g_game, {
    onGameStart = online,
    onGameEnd = offline
  })
  if g_game.isOnline() then
    online()
  end
end

function terminate()
  if not g_app.isMobile() or not overlay then return end
  removeEvent(updateCursorEvent)
  updateCursorEvent = nil
  removeEvent(keypadEvent)
  keypadEvent = nil
  removeEvent(initScaleEvent)
  initScaleEvent = nil
  disconnect(overlay, {
    onMousePress = onMousePress,
    onMouseRelease = onMouseRelease,
    onTouchPress = onMousePress,
    onTouchRelease = onMouseRelease
  })
  if keypad then
    disconnect(keypad, {
      onTouchPress = onKeypadTouchPress,
      onTouchRelease = onKeypadTouchRelease,
      onMouseMove = onKeypadTouchMove
    })
  end
  disconnect(g_game, {
    onGameStart = online,
    onGameEnd = offline
  })
  zoomInButton:destroy()
  zoomOutButton:destroy()
  keypadButton:destroy()
  overlay:destroy()
  overlay = nil
  keypad = nil
end

function hide()
  if not overlay then return end
  overlay:hide()
end

function show()
  if not overlay then return end
  overlay:show()
end

function online()
  if not keypad then return end
  if keypadButton:isChecked() then
    keypad:raise()
    keypad:show()
  end
end

function offline()
  if not keypad then return end
  keypad:hide()
end

function onMousePress(widget, pos, button)
  if not overlay then return end
  overlay:raise()
  if button == MouseTouch then -- touch
    local cursor = overlay.cursor
    if cursor then
      cursor:show()
      cursor:setX(pos.x - 32)
      cursor:setY(pos.y - 32)
    end
    touchStart = g_clock.millis()
    updateCursor()
  else
    if overlay.cursor then overlay.cursor:hide() end
    removeEvent(updateCursorEvent)
  end
end

function onMouseRelease(widget, pos, button)
  if not overlay then return end
  if button == MouseTouch then
    if overlay.cursor then overlay.cursor:hide() end
    removeEvent(updateCursorEvent)
  end
end

function updateCursor()
  removeEvent(updateCursorEvent)
  if not g_mouse.isPressed(MouseTouch) then return end
  if not overlay or not overlay.cursor then return end
  local percent = 100 - math.max(0, math.min(100, (g_clock.millis() - touchStart) / 5)) -- 500 ms
  overlay.cursor:setPercent(percent)
  if percent > 0 then
    overlay.cursor:setOpacity(0.5)
    updateCursorEvent = scheduleEvent(updateCursor, 10)
  else
    overlay.cursor:setOpacity(0.8)
  end
end

local function updateKeypadMousePos(widget, pos)
  keypadMousePos.x = (pos.x - widget:getPosition().x) / widget:getWidth()
  keypadMousePos.y = (pos.y - widget:getPosition().y) / widget:getHeight()
end

function onKeypadTouchMove(widget, pos, offset)
  updateKeypadMousePos(widget, pos)
  return true
end

function onKeypadTouchPress(widget, pos, button)
  if button ~= MouseTouch then return false end
  keypadTicks = 0
  updateKeypadMousePos(widget, pos)
  executeWalk()
  return true
end

function onKeypadTouchRelease(widget, pos, button)
  if button ~= MouseTouch then return false end
  updateKeypadMousePos(widget, pos)
  executeWalk()
  removeEvent(keypadEvent)
  if keypad and keypad.pointer then
    keypad.pointer:setMarginTop(0)
    keypad.pointer:setMarginLeft(0)
  end
  return true
end

function executeWalk()
  if not keypad or not keypad.pointer then return end
  removeEvent(keypadEvent)
  keypadEvent = nil
  if not modules.game_walking or not g_mouse.isPressed(MouseTouch) then
    keypad.pointer:setMarginTop(0)
    keypad.pointer:setMarginLeft(0)
    return
  end
  keypadEvent = scheduleEvent(executeWalk, 20)
  keypadMousePos.x = math.min(1, math.max(0, keypadMousePos.x))
  keypadMousePos.y = math.min(1, math.max(0, keypadMousePos.y))
  local angle = math.atan2(keypadMousePos.x - 0.5, keypadMousePos.y - 0.5)
  local maxTop = math.abs(math.cos(angle)) * 75
  local marginTop = math.max(-maxTop, math.min(maxTop, (keypadMousePos.y - 0.5) * 150))
  local maxLeft = math.abs(math.sin(angle)) * 75
  local marginLeft = math.max(-maxLeft, math.min(maxLeft, (keypadMousePos.x - 0.5) * 150))
  keypad.pointer:setMarginTop(marginTop)
  keypad.pointer:setMarginLeft(marginLeft)
  local dir
  if keypadMousePos.y < 0.3 and keypadMousePos.x < 0.3 then
    dir = Directions.NorthWest
  elseif keypadMousePos.y < 0.3 and keypadMousePos.x > 0.7 then
    dir = Directions.NorthEast
  elseif keypadMousePos.y > 0.7 and keypadMousePos.x < 0.3 then
    dir = Directions.SouthWest
  elseif keypadMousePos.y > 0.7 and keypadMousePos.x > 0.7 then
    dir = Directions.SouthEast
  end
  if not dir and (math.abs(keypadMousePos.y - 0.5) > 0.1 or math.abs(keypadMousePos.x - 0.5) > 0.1) then
    if math.abs(keypadMousePos.y - 0.5) > math.abs(keypadMousePos.x - 0.5) then
      if keypadMousePos.y < 0.5 then
        dir = Directions.North
      else
        dir = Directions.South
      end
    else
      if keypadMousePos.x < 0.5 then
        dir = Directions.West
      else
        dir = Directions.East
      end
    end
  end
  if dir then
    modules.game_walking.walk(dir, keypadTicks)
    if keypadTicks == 0 then
      keypadTicks = 100
    end
  end
end
