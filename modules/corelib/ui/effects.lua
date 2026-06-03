-- @docclass
g_effects = {}

local function ensureFadeCleanup(widget)
  if widget.fadeDestroyCleanup then
    return
  end
  widget.fadeDestroyCleanup = true
  connect(widget, { onDestroy = g_effects.cancelFade })
end

local function releaseFadeCleanup(widget)
  if not widget.fadeDestroyCleanup then
    return
  end
  disconnect(widget, { onDestroy = g_effects.cancelFade })
  widget.fadeDestroyCleanup = nil
end

function g_effects.fadeIn(widget, time, elapsed)
  if not elapsed then elapsed = 0 end
  if not time then time = 300 end
  ensureFadeCleanup(widget)
  widget:setOpacity(math.min(elapsed/time, 1))
  removeEvent(widget.fadeEvent)
  if elapsed < time then
    removeEvent(widget.fadeEvent)
    widget.fadeEvent = scheduleEvent(function()
      g_effects.fadeIn(widget, time, elapsed + 30)
    end, 30)
  else
    widget.fadeEvent = nil
    releaseFadeCleanup(widget)
  end
end

function g_effects.fadeOut(widget, time, elapsed, hideOnFinish)
  if not elapsed then elapsed = 0 end
  if not time then time = 300 end

  hideOnFinish = hideOnFinish or false
  elapsed = math.max((1 - widget:getOpacity()) * time, elapsed)
  ensureFadeCleanup(widget)
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
    releaseFadeCleanup(widget)
  end
end

function g_effects.cancelFade(widget)
  removeEvent(widget.fadeEvent)
  widget.fadeEvent = nil
  releaseFadeCleanup(widget)
end

function g_effects.cleanupBlink(widget)
  disconnect(widget, { onClick = g_effects.stopBlink,
                       onDestroy = g_effects.cleanupBlink })
  removeEvent(widget.blinkEvent)
  removeEvent(widget.blinkStopEvent)
  widget.blinkEvent = nil
  widget.blinkStopEvent = nil
end

function g_effects.startBlink(widget, duration, interval, clickCancel)
  duration = duration or 0 -- until stop is called
  interval = interval or 500
  clickCancel = clickCancel or true

  removeEvent(widget.blinkEvent)
  removeEvent(widget.blinkStopEvent)

  disconnect(widget, { onDestroy = g_effects.cleanupBlink })
  connect(widget, { onDestroy = g_effects.cleanupBlink })

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
  g_effects.cleanupBlink(widget)
  widget:setOn(false)
end

function g_effects.cleanupBorderBlink(widget)
  disconnect(widget, { onDestroy = g_effects.cleanupBorderBlink })
  removeEvent(widget.borderBlinkEvent)
  removeEvent(widget.borderBlinkStopEvent)
  widget.borderBlinkEvent = nil
  widget.borderBlinkStopEvent = nil
end

function g_effects.startBorderBlink(widget, duration, interval, size)
  duration = duration or 250
  interval = interval or 500

  removeEvent(widget.borderBlinkEvent)
  removeEvent(widget.borderBlinkStopEvent)

  disconnect(widget, { onDestroy = g_effects.cleanupBorderBlink })
  connect(widget, { onDestroy = g_effects.cleanupBorderBlink })

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
  g_effects.cleanupBorderBlink(widget)
  widget:setBorderWidth(defaultSize)  
end
