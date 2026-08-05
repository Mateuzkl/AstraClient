-- @docclass
UIWindow = extends(UIWidget, "UIWindow")

function UIWindow.create()
  local window = UIWindow.internalCreate()
  window:setTextAlign(AlignTopCenter)
  window:setDraggable(true)
  window:setAutoFocusPolicy(AutoFocusFirst)
  window:insertLuaCall("onFocusChange")
  return window
end

function UIWindow:onKeyDown(keyCode, keyboardModifiers)
  if keyboardModifiers == KeyboardNoModifier then
    if keyCode == KeyEnter or keyCode == KeyNumEnter then
      g_ui.setCallEnterKey(true)
      signalcall(self.onEnter, self)
    elseif keyCode == KeyEscape then
      g_ui.setCallEscapeKey(true)
      signalcall(self.onEscape, self)
    end
  end
end

function UIWindow:onFocusChange(focused)
  if focused then
    self:raise()
    return
  end

  -- Hiding a focused window makes the framework choose a previous sibling.
  -- Restore the in-game focus chain so global movement and action hotkeys keep
  -- reaching gameRootPanel after any feature window closes.
  if not self:isDestroyed() and self:isExplicitlyVisible() then
    return
  end

  if not g_game.isOnline() then
    return
  end

  local root = rootWidget or g_ui.getRootWidget()
  local gameWindow = root and root:getChildById('gameRootPanel')
  if gameWindow and gameWindow:isVisible() then
    gameWindow:focus()
  end
end

function UIWindow:onDragEnter(mousePos)
  if self.static then
    return false
  end
  self:breakAnchors()
  self.movingReference = { x = mousePos.x - self:getX(), y = mousePos.y - self:getY() }
  return true
end

function UIWindow:onDragLeave(droppedWidget, mousePos)
  -- TODO: auto detect and reconnect anchors
end

function UIWindow:onDragMove(mousePos, mouseMoved)
  if self.static then
    return
  end
  local pos = { x = mousePos.x - self.movingReference.x, y = mousePos.y - self.movingReference.y }
  self:setPosition(pos)
  self:bindRectToParent()
end
