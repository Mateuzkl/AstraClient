-- @docclass
UIResizeBorder = extends(UIWidget, "UIResizeBorder")

-- The horizontal top rails (horizontalLeftPanel / horizontalRightPanel) are locked to a fixed
-- height and must not be resizable in any way. A mini-window docked into one of them still owns
-- its own bottom ResizeBorder, so we detect that case to suppress both the resize cursor
-- (onHoverChange) and the drag itself (onMouseMove).
local LOCKED_HORIZONTAL_PANELS = {"horizontalLeftPanel", "horizontalRightPanel"}

function UIResizeBorder.create()
  local resizeborder = UIResizeBorder.internalCreate()
  resizeborder:setFocusable(false)
  resizeborder.minimum = 0
  resizeborder.maximum = 4000
  resizeborder:insertLuaCall("onSetup")
  resizeborder:insertLuaCall("onDestroy")
  return resizeborder
end

function UIResizeBorder:onSetup()
  if self:getWidth() > self:getHeight() then
    self.vertical = true
  else
    self.vertical = false
  end
end

function UIResizeBorder:onDestroy()
  if self.hovering then
    g_mouse.popCursor(self.cursortype)
  end
end

-- True when this border belongs to a mini-window docked inside one of the locked horizontal
-- rails (see LOCKED_HORIZONTAL_PANELS). Mirrors how onMouseMove resolves the resized widget.
function UIResizeBorder:isInsideLockedHorizontalPanel()
  local parent = self:getParent()
  if self.lastParent then
    parent = g_ui.getRootWidget():recursiveGetChildById(self.lastParent)
  end
  if not parent then return false end
  local topParent = parent:getParent()
  return topParent ~= nil and table.contains(LOCKED_HORIZONTAL_PANELS, topParent:getId())
end

function UIResizeBorder:onHoverChange(hovered)
  if hovered then
    if g_mouse.isCursorChanged() or g_mouse.isPressed() then return end
    -- Locked horizontal rails: never show the resize cursor on a mini-window docked into them.
    if self:isInsideLockedHorizontalPanel() then return end
    if self:getWidth() > self:getHeight() then
      self.vertical = true
      self.cursortype = 'vertical'
    else
      self.vertical = false
      self.cursortype = 'horizontal'
    end
    g_mouse.pushCursor(self.cursortype)
    self.hovering = true
  else
    if not self:isPressed() and self.hovering then
      g_mouse.popCursor(self.cursortype)
      self.hovering = false
    end
  end
end

function UIResizeBorder:onMouseMove(mousePos, mouseMoved)
  if self:isPressed() then
    local parent = self:getParent()
    if self.lastParent then
      parent = g_ui.getRootWidget():recursiveGetChildById(self.lastParent)
    end

    if parent:getClassName() == "UIMiniWindow" and parent.minimizeButton and parent.minimizeButton:isOn() then
      return false
    end

    local topParent = parent:getParent()
    -- Locked horizontal rails: a mini-window docked into one of them must not be resizable, so
    -- swallow the drag entirely instead of clamping it to the (now fixed) rail height.
    if topParent and table.contains(LOCKED_HORIZONTAL_PANELS, topParent:getId()) then
      return false
    end

    local maximum = self.maximum
    local newSize = 0
    if self.vertical then
      local delta = mousePos.y - self:getY() - self:getHeight()/2
      newSize = math.min(math.max(parent:getHeight() + delta, self.minimum), maximum)
      parent:setHeight(newSize)
    else
      local delta = mousePos.x - self:getX() - self:getWidth()/2
      newSize = math.min(math.max(parent:getWidth() + delta, self.minimum), maximum)
      parent:setWidth(newSize)
    end

    self:checkBoundary(newSize)
    return true
  end
end

function UIResizeBorder:onMouseRelease(mousePos, mouseButton)
  -- Only pop if we actually pushed a cursor (self.hovering). On the locked horizontal rails the
  -- hover cursor is suppressed, so a press+release there must not pop an unrelated cursor off the
  -- shared stack (popCursor with an empty name pops the stack top -- someone else's cursor).
  if not self:isHovered() and self.hovering then
    g_mouse.popCursor(self.cursortype)
    g_effects.fadeOut(self)
    self.hovering = false
  end
end

function UIResizeBorder:onStyleApply(styleName, styleNode)
  for name,value in pairs(styleNode) do
    if name == 'maximum' then
      self:setMaximum(tonumber(value))
    elseif name == 'minimum' then
      self:setMinimum(tonumber(value))
    elseif name == 'lastParent' then
      self.lastParent = value
    end
  end
end

function UIResizeBorder:onVisibilityChange(visible)
  if visible and self.maximum == self.minimum then
    self:hide()
  end
end

function UIResizeBorder:setMaximum(maximum)
  self.maximum = maximum
  self:checkBoundary()
end

function UIResizeBorder:setMinimum(minimum)
  self.minimum = minimum
  self:checkBoundary()
end

function UIResizeBorder:getMaximum() return self.maximum end
function UIResizeBorder:getMinimum() return self.minimum end

function UIResizeBorder:setParentSize(size)
  local parent = self:getParent()
  if self.vertical then
    parent:setHeight(size)
  else
    parent:setWidth(size)
  end
  self:checkBoundary(size)
end

function UIResizeBorder:getParentSize()
  local parent = self:getParent()
  if self.vertical then
    return parent:getHeight()
  else
    return parent:getWidth()
  end
end

function UIResizeBorder:checkBoundary(size)
  size = size or self:getParentSize()
  if self.maximum == self.minimum and size == self.maximum then
    self:hide()
  else
    self:show()
  end
end
