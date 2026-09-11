-- @docclass
g_effects = {}

function g_effects.fadeIn(widget, time, elapsed)
  if not elapsed then elapsed = 0 end
  if not time then time = 300 end
  widget:setOpacity(math.min(elapsed/time, 1))
  removeEvent(widget.fadeEvent)
  if elapsed < time then
    widget.fadeEvent = scheduleEvent(function()
      g_effects.fadeIn(widget, time, elapsed + 30)
    end, 30)
  else
    widget.fadeEvent = nil
  end
end

function g_effects.fadeOut(widget, time, elapsed, hideOnFinish)
  if not elapsed then elapsed = 0 end
  if not time then time = 300 end

  hideOnFinish = hideOnFinish or false
  elapsed = math.max((1 - widget:getOpacity()) * time, elapsed)
  removeEvent(widget.fadeEvent)
  widget:setOpacity(math.max((time - elapsed)/time, 0))
  if elapsed < time then
    widget.fadeEvent = scheduleEvent(function()
      g_effects.fadeOut(widget, time, elapsed + 30, hideOnFinish)
    end, 30)
  else
    widget.fadeEvent = nil
    if hideOnFinish then
      widget:hide()
      widget:setOpacity(100)
    end
  end
end

function g_effects.cancelFade(widget)
  removeEvent(widget.fadeEvent)
  widget.fadeEvent = nil
end

local function easeOutCubic(t)
  return 1 - math.pow(1 - t, 3)
end

function g_effects.moveTo(widget, targetPos, time, onFinish)
  if not widget or widget:isDestroyed() then
    return
  end

  time = time or 140
  local startPos = widget:getPosition()
  local startTime = g_clock.millis()

  removeEvent(widget.moveEvent)

  local function animate()
    if not widget or widget:isDestroyed() then
      return
    end

    local elapsed = g_clock.millis() - startTime
    local progress = math.min(elapsed / time, 1)
    local eased = easeOutCubic(progress)
    local x = math.floor(startPos.x + (targetPos.x - startPos.x) * eased + 0.5)
    local y = math.floor(startPos.y + (targetPos.y - startPos.y) * eased + 0.5)

    widget:setPosition({ x = x, y = y })

    if progress < 1 then
      widget.moveEvent = scheduleEvent(animate, 16)
    else
      widget:setPosition(targetPos)
      widget.moveEvent = nil
      if onFinish then
        onFinish(widget)
      end
    end
  end

  animate()
end

function g_effects.cancelMove(widget)
  if not widget or widget:isDestroyed() then
    return
  end

  removeEvent(widget.moveEvent)
  widget.moveEvent = nil
end

function g_effects.startBlink(widget, duration, interval, clickCancel)
  duration = duration or 0 -- until stop is called
  interval = interval or 500
  if clickCancel == nil then
    clickCancel = true
  end

  -- Stop any previous blink cleanly before starting a new one
  g_effects.stopBlink(widget)

  widget.blinkEvent = cycleEvent(function()
    if not widget or widget:isDestroyed() then
      -- Cancel the recurring event so it stops polling
      removeEvent(widget.blinkEvent)
      widget.blinkEvent = nil
      removeEvent(widget.blinkStopEvent)
      widget.blinkStopEvent = nil
      return
    end
    widget:setOn(not widget:isOn())
  end, interval)

  if duration > 0 then
    widget.blinkStopEvent = scheduleEvent(function()
      if not widget or widget:isDestroyed() then return end
      g_effects.stopBlink(widget)
    end, duration)
  end

  widget._blinkClickCancel = clickCancel
  if clickCancel then
    connect(widget, { onClick = g_effects.stopBlink })
  end

  -- Install onDestroy to cancel events when widget is destroyed
  widget._blinkOnDestroy = function()
    removeEvent(widget.blinkEvent)
    removeEvent(widget.blinkStopEvent)
    widget.blinkEvent = nil
    widget.blinkStopEvent = nil
    widget._blinkClickCancel = nil
    widget._blinkOnDestroy = nil
  end
  connect(widget, { onDestroy = widget._blinkOnDestroy })
end

function g_effects.stopBlink(widget)
  if not widget then return end
  -- Cancel events before any widget-state operations
  removeEvent(widget.blinkEvent)
  removeEvent(widget.blinkStopEvent)
  widget.blinkEvent = nil
  widget.blinkStopEvent = nil
  -- Disconnect handlers (only if widget is still alive)
  if not widget:isDestroyed() then
    if widget._blinkClickCancel then
      disconnect(widget, { onClick = g_effects.stopBlink })
    end
    if widget._blinkOnDestroy then
      disconnect(widget, { onDestroy = widget._blinkOnDestroy })
    end
    widget:setOn(false)
  end
  widget._blinkClickCancel = nil
  widget._blinkOnDestroy = nil
end

function g_effects.startBorderBlink(widget, duration, interval, size)
  if not widget or widget:isDestroyed() then return end
  duration = duration or 250
  interval = interval or 500

  -- Stop previous border blink cleanly
  g_effects.stopBorderBlink(widget, size)

  widget.borderBlinkEvent = cycleEvent(function()
    if not widget or widget:isDestroyed() then
      -- Cancel the recurring event so it stops polling
      removeEvent(widget.borderBlinkEvent)
      widget.borderBlinkEvent = nil
      removeEvent(widget.borderBlinkStopEvent)
      widget.borderBlinkStopEvent = nil
      return
    end
    widget:setBorderWidth(widget:getBorderLeftWidth() == 0 and size or 0)
  end, interval)

  if duration > 0 then
    widget.borderBlinkStopEvent = scheduleEvent(function()
      if not widget or widget:isDestroyed() then return end
      g_effects.stopBorderBlink(widget, size)
    end, duration)
  end

  -- Install onDestroy to cancel events when widget is destroyed
  widget._borderBlinkOnDestroy = function()
    removeEvent(widget.borderBlinkEvent)
    removeEvent(widget.borderBlinkStopEvent)
    widget.borderBlinkEvent = nil
    widget.borderBlinkStopEvent = nil
    widget._borderBlinkOnDestroy = nil
  end
  connect(widget, { onDestroy = widget._borderBlinkOnDestroy })
end

function g_effects.stopBorderBlink(widget, defaultSize)
  if not widget then return end
  -- Cancel events before any widget-state operations
  removeEvent(widget.borderBlinkEvent)
  removeEvent(widget.borderBlinkStopEvent)
  widget.borderBlinkEvent = nil
  widget.borderBlinkStopEvent = nil
  -- Widget-state operations only if still alive
  if not widget:isDestroyed() then
    if widget._borderBlinkOnDestroy then
      disconnect(widget, { onDestroy = widget._borderBlinkOnDestroy })
    end
    widget:setBorderWidth(defaultSize)
  end
  widget._borderBlinkOnDestroy = nil
end

