-- @docclass
UIComboBox = extends(UIWidget, "UIComboBox")

function UIComboBox.create()
  local combobox = UIComboBox.internalCreate()
  combobox:setFocusable(false)
  combobox.options = {}
  combobox.currentIndex = -1
  combobox.mouseScroll = true
  combobox.menuScroll = false
  combobox.menuHeight = 100
  combobox.menuScrollStep = 0
  combobox.maxTextLength = -1
  combobox.additionalWidth = 0
  combobox.currentMenuWindow = nil
  return combobox
end

function UIComboBox:clearOptions()
  self.options = {}
  self.currentIndex = -1
  self:clearText()
end

function UIComboBox:clear()
  return self:clearOptions()
end

function UIComboBox:getOptionsCount()
  return #self.options
end

function UIComboBox:isOption(text)
  if not self.options then return false end
  for i,v in ipairs(self.options) do
    if v.text == text then
      return true
    end
  end
  return false
end

function UIComboBox:setOption(text, dontSignal)
  self:setCurrentOption(text, dontSignal)
end

function UIComboBox:setCurrentOptionLower(text, dontSignal)
  if not self.options then return end
  for i,v in ipairs(self.options) do
    if v.text:lower() == text:lower() and self.currentIndex ~= i then
      self.currentIndex = i
      if self.maxTextLength ~= -1 then
        self:setText(short_text(text, self.maxTextLength))
      else
        self:setText(text)
      end
      if not dontSignal then
        signalcall(self.onOptionChange, self, text, v.data)
      end
      return
    end
  end
end

function UIComboBox:setCurrentOption(text, dontSignal)
  if not self.options then return end
  for i,v in ipairs(self.options) do
    if v.text == text and self.currentIndex ~= i then
      self.currentIndex = i
      if self.maxTextLength ~= -1 then
        self:setText(short_text(text, self.maxTextLength))
      else
        self:setText(text)
      end
      if not dontSignal then
        signalcall(self.onOptionChange, self, text, v.data)
      end
      return
    end
  end
end

function UIComboBox:updateCurrentOption(newText)
  self.options[self.currentIndex].text = newText
  self:setText(newText)
end

function UIComboBox:setCurrentOptionByData(data, dontSignal)
  if not self.options then return end
  for i,v in ipairs(self.options) do
    if v.data == data and self.currentIndex ~= i then
      self.currentIndex = i
      self:setText(v.text)
      if not dontSignal then
        signalcall(self.onOptionChange, self, v.text, v.data)
      end
      return
    end
  end
end

function UIComboBox:setCurrentIndex(index, dontSignal)
  if index >= 1 and index <= #self.options then
    local v = self.options[index]
    self.currentIndex = index
    self:setText(v.text)
    if not dontSignal then
      signalcall(self.onOptionChange, self, v.text, v.data)
    end
  end
end

function UIComboBox:getCurrentOption()
  if table.haskey(self.options, self.currentIndex) then
    return self.options[self.currentIndex]
  end
end

function UIComboBox:addOption(text, data, dontSignal)
  table.insert(self.options, { text = text, data = data })
  local index = #self.options
  if index == 1 then self:setCurrentOption(text, dontSignal) end
  return index
end

function UIComboBox:addOptionFromHtml(text, value)
  return self:addOption(text, value)
end

function UIComboBox:removeOption(text)
  for i,v in ipairs(self.options) do
    if v.text == text then
      table.remove(self.options, i)
      if self.currentIndex == i then
        self:setCurrentIndex(1)
      elseif self.currentIndex > i then
        self.currentIndex = self.currentIndex - 1
      end
      return
    end
  end
end

function UIComboBox:changeOption(text, newText)
  for i,v in ipairs(self.options) do
    if v.text == text then
	  self.options[i].text = newText
	  self:setText(newText)
      return
    end
  end
end

function UIComboBox:onMousePress(mousePos, mouseButton)
  if g_ui.getCustomInputWidget() then
    self.lastLockedWidget = g_ui.getCustomInputWidget()
  end

  if self.menuScroll then
    self.currentMenuWindow = g_ui.createWidget(self:getStyleName() .. 'PopupScrollMenu', self)
    self.currentMenuWindow:setHeight(self.menuHeight)
    if self.menuScrollStep > 0 then
      self.currentMenuWindow:setScrollbarStep(self.menuScrollStep)
    end
  else
    self.currentMenuWindow = g_ui.createWidget(self:getStyleName() .. 'PopupMenu', self)
  end

  g_client.setInputLockWidget(nil)
  g_client.setInputLockWidget(self.currentMenuWindow)
  self.currentMenuWindow:setId(self:getId() .. 'PopupMenu')
  for i,v in ipairs(self.options) do
    self.currentMenuWindow:addOption(v.text, function() self:setCurrentOption(v.text) end)
  end
  self.currentMenuWindow:setWidth(self:getWidth() + self.additionalWidth)
  self.currentMenuWindow:display({ x = self:getX(), y = self:getY() + self:getHeight() })
  self.currentMenuWindow:insertLuaCall("onDestroy")
  connect(self.currentMenuWindow, { onDestroy = function() self:setOn(false) self:setChecked(false) self.currentMenuWindow = nil if self.lastLockedWidget then g_client.setInputLockWidget(self.lastLockedWidget) end end })
  self:setOn(true)
  if self.currentIndex ~= -1 then
    self:setChecked(true)
  end
  return true
end

function UIComboBox:destroyCurrentMenu()
  if self.currentMenuWindow then
    self.currentMenuWindow:destroy()
    self.currentMenuWindow = nil
  end
end

function UIComboBox:onMouseWheel(mousePos, direction)
  if not self.mouseScroll or self.disableScroll then
    return false
  end
  if direction == MouseWheelUp and self.currentIndex > 1 then
    self:setCurrentIndex(self.currentIndex - 1)
  elseif direction == MouseWheelDown and self.currentIndex < #self.options then
    self:setCurrentIndex(self.currentIndex + 1)
  end
  return true
end

function UIComboBox:onStyleApply(styleName, styleNode)
  if styleNode.options then
    for k,option in pairs(styleNode.options) do
      self:addOption(option)
    end
  end

  if styleNode.data then
    for k,data in pairs(styleNode.data) do
      local option = self.options[k]
      if option then
        option.data = data
      end
    end
  end

  for name,value in pairs(styleNode) do
    if name == 'mouse-scroll' then
      self.mouseScroll = value
    elseif name == 'menu-scroll' then
      self.menuScroll = value
    elseif name == 'menu-height' then
      self.menuHeight = value
    elseif name == 'menu-scroll-step' then
      self.menuScrollStep = value
    elseif name == 'max-text-length' then
      self.maxTextLength = value
    elseif name == 'additional-width' then
      self.additionalWidth = value
    end
  end
end

function UIComboBox:setMouseScroll(scroll)
  self.mouseScroll = scroll
end

function UIComboBox:canMouseScroll()
  return self.mouseScroll
end

function UIComboBox:getCurrentOptionIndex()
  return self.currentIndex
end

function UIComboBox:getCurrentIndex()
  return self.currentIndex
end
