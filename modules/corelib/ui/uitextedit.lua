function UITextEdit:onStyleApply(styleName, styleNode)
  for name,value in pairs(styleNode) do
    if name == 'vertical-scrollbar' or name == 'horizontal-scrollbar' then
      addEvent(function()
        if self:isDestroyed() then return end
        local parent = self:getParent()
        if not parent or parent:isDestroyed() then return end
        local scrollbar = parent:getChildById(value)
        if not scrollbar or scrollbar:isDestroyed() then return end
        if name == 'vertical-scrollbar' then
          self:setVerticalScrollBar(scrollbar)
        else
          self:setHorizontalScrollBar(scrollbar)
        end
      end)
    end
  end
end

function UITextEdit:onMouseWheel(mousePos, mouseWheel)
  if self.verticalScrollBar and self:isMultiline() then
    if mouseWheel == MouseWheelUp then
      self.verticalScrollBar:smoothScrollBy(-self.verticalScrollBar:getStep())
    else
      self.verticalScrollBar:smoothScrollBy(self.verticalScrollBar:getStep())
    end
    return true
  elseif self.horizontalScrollBar then
    if mouseWheel == MouseWheelUp then
      self.horizontalScrollBar:smoothScrollBy(self.horizontalScrollBar:getStep())
    else
      self.horizontalScrollBar:smoothScrollBy(-self.horizontalScrollBar:getStep())
    end
    return true
  end
end

function UITextEdit:onTextAreaUpdate(virtualOffset, virtualSize, totalSize)
  self:updateScrollBars()
end

function UITextEdit:setVerticalScrollBar(scrollbar)
  self.verticalScrollBar = scrollbar
  self.verticalScrollBar.onValueChange = function(scrollbar, value)
    local virtualOffset = self:getTextVirtualOffset()
    virtualOffset.y = value
    self:setTextVirtualOffset(virtualOffset)
  end
  self:updateScrollBars()
end

function UITextEdit:setHorizontalScrollBar(scrollbar)
  self.horizontalScrollBar = scrollbar
  self.horizontalScrollBar.onValueChange = function(scrollbar, value)
    local virtualOffset = self:getTextVirtualOffset()
    virtualOffset.x = value
    self:setTextVirtualOffset(virtualOffset)
  end
  self:updateScrollBars()
end

function UITextEdit:updateScrollBars()
  local scrollSize = self:getTextTotalSize()
  local scrollWidth = math.max(scrollSize.width - self:getTextVirtualSize().width, 0)
  local scrollHeight = math.max(scrollSize.height - self:getTextVirtualSize().height, 0)

  local scrollbar = self.verticalScrollBar
  if scrollbar then
    scrollbar:setMinimum(0)
    scrollbar:setMaximum(scrollHeight)
    scrollbar:setValue(self:getTextVirtualOffset().y)
  end

  local scrollbar = self.horizontalScrollBar
  if scrollbar then
    scrollbar:setMinimum(0)
    scrollbar:setMaximum(scrollWidth)
    scrollbar:setValue(self:getTextVirtualOffset().x)
  end

end

function UITextEdit:onCheckHotkeyText(text, pressedKey)
  if self:getId() ~= "consoleTextEdit" then
    return true
  end

  if not modules.game_console.isChatEnabled() then
    return false
  end

  local keyCombo = determineKeyComboDesc(pressedKey, nil, text)
  if g_keyboard.isShiftPressed() and not string.find(keyCombo, "Shift+") then
    keyCombo = "Shift+" .. keyCombo
  end

  if KeyBinds:isUsedHotkey(keyCombo) then
    return false
  end

  return true
end
