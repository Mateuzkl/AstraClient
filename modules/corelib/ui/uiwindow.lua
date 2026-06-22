-- @docclass
UIWindow = extends(UIWidget, "UIWindow")

local function isTitleDragArea(window, mousePos)
  if not window.htmlTitleDragOnly then
    return true
  end

  if not mousePos then
    return false
  end

  local titleHeight = window.htmlTitleDragHeight or 32
  local localY = mousePos.y - window:getY()
  return localY >= 0 and localY <= titleHeight
end

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

  -- The window just lost focus. Distinguish *why*:
  --   * focus moved to another widget while this window stays open  -> nothing to do
  --     (whatever the user clicked/opened already owns the focus).
  --   * this window is being hidden or destroyed                    -> reclaim focus for
  --     the game window.
  -- When a focused child is hidden/removed the framework hands focus to an arbitrary
  -- sibling (focusPreviousChild, rotate=true). In-game that sibling is rarely the game
  -- window, so the keybinds bound to it (Escape -> "Stop All Actions", movement keys)
  -- silently stop firing -- e.g. closing the Helper with Escape left a dangling focus and
  -- a second Escape no longer cancelled the current target. Restoring focus to the game
  -- window here keeps Escape/movement working the moment any feature window closes.
  --
  -- Note: at this point in setVisible() the HiddenState isn't applied yet, so isVisible()
  -- still reports true; m_visible (isExplicitlyVisible) is already false, which is what we
  -- check. On destroy m_visible may stay true, hence the isDestroyed() guard.
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
  if not isTitleDragArea(self, mousePos) then
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
