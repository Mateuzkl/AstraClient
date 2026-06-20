-- @docclass
g_effects = {}

function g_effects.fadeIn(widget, time, elapsed)
  if not elapsed then elapsed = 0 end
  if not time then time = 300 end
  widget:setOpacity(math.min(elapsed/time, 1))
  removeEvent(widget.fadeEvent)
  if elapsed < time then
    removeEvent(widget.fadeEvent)
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
  clickCancel = clickCancel or true

  removeEvent(widget.blinkEvent)
  removeEvent(widget.blinkStopEvent)

  widget.blinkEvent = cycleEvent(function()
    widget:setOn(not widget:isOn())
  end, interval)

  if duration > 0 then
    widget.blinkStopEvent = scheduleEvent(function()
      g_effects.stopBlink(widget)
    end, duration)
  end

  connect(widget, { onClick = g_effects.stopBlink })
end

function g_effects.stopBlink(widget)
  disconnect(widget, { onClick = g_effects.stopBlink })
  removeEvent(widget.blinkEvent)
  removeEvent(widget.blinkStopEvent)
  widget.blinkEvent = nil
  widget.blinkStopEvent = nil
  widget:setOn(false)
end

function g_effects.startBorderBlink(widget, duration, interval, size)
  duration = duration or 250
  interval = interval or 500

  removeEvent(widget.borderBlinkEvent)
  removeEvent(widget.borderBlinkStopEvent)

  widget.borderBlinkEvent = cycleEvent(function()
    widget:setBorderWidth(widget:getBorderLeftWidth() == 0 and size or 0)
  end, interval)

  if duration > 0 then
    widget.borderBlinkStopEvent = scheduleEvent(function()
      g_effects.stopBorderBlink(widget, size)
    end, duration)
  end
end

function g_effects.stopBorderBlink(widget, defaultSize)
  removeEvent(widget.borderBlinkEvent)
  removeEvent(widget.borderBlinkStopEvent)
  widget.borderBlinkEvent = nil
  widget.borderBlinkStopEvent = nil
  widget:setBorderWidth(defaultSize)  
end
