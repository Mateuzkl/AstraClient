-- @docclass

-- Per-widget autopress state, keyed by widget then by mouse button.
-- Stored on the widget itself as widget._autoPressState[button].
-- Each entry: { generation = number, repeatEvent = eventHandle,
--               onPress = func, onRelease = func, onDestroy = func }

function g_mouse.bindAutoPress(widget, callback, delay, button, loopingDelay)
  if not widget then return end

  button = button or MouseLeftButton
  if loopingDelay == nil then
    loopingDelay = 30
  end
  if delay == nil then
    delay = loopingDelay
  end

  -- Ensure per-widget state table exists
  if not widget._autoPressState then
    widget._autoPressState = {}
  end

  -- If there is a previous binding for this button, disconnect it first (idempotent)
  local prev = widget._autoPressState[button]
  if prev then
    -- Cancel any pending repeat
    removeEvent(prev.repeatEvent)
    prev.repeatEvent = nil
    prev.generation = prev.generation + 1 -- invalidate stale callbacks
    -- Disconnect old handlers
    disconnect(widget, { onMousePress = prev.onPress })
    disconnect(widget, { onMouseRelease = prev.onRelease })
    disconnect(widget, { onDestroy = prev.onDestroy })
    widget._autoPressState[button] = nil
  end

  local state = {
    generation = 0,
    repeatEvent = nil
  }

  -- Press handler: immediate callback + schedule first repeat after delay
  local function onPress(w, mousePos, mouseButton)
    if mouseButton ~= button then
      return false
    end

    -- Invalidate any lingering callback from a previous press
    state.generation = state.generation + 1
    removeEvent(state.repeatEvent)
    state.repeatEvent = nil

    local gen = state.generation
    local startTime = g_clock.millis()

    -- Immediate callback
    callback(w, mousePos, mouseButton, 0)

    -- Schedule repeats using explicit scheduleEvent handles
    local function doRepeat()
      -- Guard: stale generation
      if gen ~= state.generation then
        return
      end
      -- Guard: widget destroyed
      if not w or w:isDestroyed() then
        state.repeatEvent = nil
        return
      end
      -- Guard: mouse button no longer pressed
      if not g_mouse.isPressed(mouseButton) then
        state.repeatEvent = nil
        return
      end

      callback(w, g_window.getMousePosition(), mouseButton, g_clock.millis() - startTime)

      -- Schedule next repeat at loopingDelay
      if gen == state.generation then
        state.repeatEvent = scheduleEvent(doRepeat, loopingDelay)
      end
    end

    -- First repeat after the initial delay
    state.repeatEvent = scheduleEvent(doRepeat, delay)
    return true
  end

  -- Release handler: cancel pending repeat, invalidate generation
  local function onRelease(w, mousePos, mouseButton)
    if mouseButton ~= button then
      return false
    end

    state.generation = state.generation + 1
    removeEvent(state.repeatEvent)
    state.repeatEvent = nil
    return false
  end

  -- Destroy handler: full cleanup
  local function onDestroy(w)
    state.generation = state.generation + 1
    removeEvent(state.repeatEvent)
    state.repeatEvent = nil
  end

  -- Save references for idempotent disconnect
  state.onPress = onPress
  state.onRelease = onRelease
  state.onDestroy = onDestroy
  widget._autoPressState[button] = state

  connect(widget, { onMousePress = onPress })
  connect(widget, { onMouseRelease = onRelease })
  connect(widget, { onDestroy = onDestroy })
end

function g_mouse.bindPressMove(widget, callback)
  connect(widget, { onMouseMove = function(widget, mousePos, mouseMoved)
    if widget:isPressed() then
      callback(mousePos, mouseMoved)
      return true
    end
  end })
end

function g_mouse.bindPress(widget, callback, button)
  connect(widget, { onMousePress = function(widget, mousePos, mouseButton)
    if not button or button == mouseButton then
      callback(mousePos, mouseButton)
      return true
    end
    return false
  end })
end

if not g_mouse.grabbedMouse then
  g_mouse.grabbedMouse = {}
end

local systemCursorByName = {
  horizontal = 'horizontal',
  vertical = 'vertical',
  pointer = 'hand',
  target = 'cross',
  text = 'text'
}

function g_mouse.applyNativeCursor(mouse)
  if not g_mouse.isUsingNativeCursor or not g_mouse.isUsingNativeCursor() then
    return false
  end

  if not g_window or not g_window.setSystemCursor then
    return false
  end

  g_window.setSystemCursor(systemCursorByName[mouse] or mouse)
  return true
end

function g_mouse.restoreNativeCursor()
  if not g_mouse.isUsingNativeCursor or not g_mouse.isUsingNativeCursor() then
    return false
  end

  if not g_window or not g_window.restoreMouseCursor then
    return false
  end

  g_window.restoreMouseCursor()
  return true
end

function g_mouse.getActiveGrabberCursor()
  for _, mouse in pairs(g_mouse.grabbedMouse) do
    if mouse ~= '' then
      return mouse
    end
  end

  return nil
end

function g_mouse.setGrabber(widget, mouse)
  if not widget then
    return false
  end

  g_mouse.grabbedMouse[widget] = mouse
  if mouse ~= '' then
    g_mouse.applyNativeCursor(mouse)
  end
  return true
end

function g_mouse.releaseGrabber(widget)
  if not widget or g_mouse.grabbedMouse[widget] == nil then
    return nil
  end

  local releasedMouse = g_mouse.grabbedMouse[widget]
  g_mouse.grabbedMouse[widget] = nil

  local nextMouse = g_mouse.getActiveGrabberCursor()
  if nextMouse then
    g_mouse.applyNativeCursor(nextMouse)
  else
    g_mouse.restoreNativeCursor()
  end

  return releasedMouse
end

function g_mouse.updateGrabber(widget, mouse)
  if not g_mouse.grabbedMouse[widget] then
    g_mouse.grabbedMouse[widget] = mouse
    g_mouse.applyNativeCursor(mouse)
  else
    g_mouse.grabbedMouse[widget] = nil
    local nextMouse = g_mouse.getActiveGrabberCursor()
    if nextMouse then
      g_mouse.applyNativeCursor(nextMouse)
    else
      g_mouse.restoreNativeCursor()
    end
  end
end

function g_mouse.clearGrabber()
  for widget, mouse in pairs(g_mouse.grabbedMouse) do
    if mouse ~= '' then
      g_mouse.popCursor(mouse)
    end
    widget:ungrabMouse()
  end
  g_mouse.grabbedMouse = {}
  g_mouse.restoreNativeCursor()
end
