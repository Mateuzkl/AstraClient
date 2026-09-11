-- @docclass
UISpinBox = extends(UITextEdit, "UISpinBox")

function UISpinBox.create()
  local spinbox = UISpinBox.internalCreate()
  spinbox:setFocusable(false)
  spinbox:setValidCharacters('0123456789')
  spinbox.displayButtons = true
  spinbox.minimum = 0
  spinbox.maximum = 1
  spinbox.value = 0
  spinbox.step = 1
  spinbox.firstchange = true
  spinbox.mouseScroll = true
  spinbox.allowModifiers = false
  spinbox.possibleValues = {}
  spinbox:setText("1")
  spinbox:setValue(1)
  spinbox:insertLuaCall("onSetup")
  spinbox:insertLuaCall("onFocusChange")
  return spinbox
end

function UISpinBox:onSetup()
  g_mouse.bindAutoPress(self:getChildById('up'), function() self:up() end, 300)
  g_mouse.bindAutoPress(self:getChildById('down'), function() self:down() end, 300)
end

function UISpinBox:onMouseWheel(mousePos, direction)
  if not self.mouseScroll or self.disableScroll then
    return false
  end
  if direction == MouseWheelUp then
    self:up()
  elseif direction == MouseWheelDown then
    self:down()
  end
  return true
end

function UISpinBox:onKeyPress()
  if self.firstchange then
    self.firstchange = false
    self:setText('')
  end

  removeEvent(self.firstChangeEvent)
  self.firstChangeEvent = scheduleEvent(function()
    if not self:isDestroyed() then
      self.firstchange = true
      self.firstChangeEvent = nil
    end
  end, 800)
  return false
end

function UISpinBox:onTextChange(text, oldText)
  if text:len() == 0 then
    return
  end

  local number = tonumber(text)
  if not number then
    self:setText(number)
    return
  else
    if number < self.minimum then
      self:setText(self.minimum)
      return
    elseif number > self.maximum then
      self:setText(self.maximum)
      return
    end
  end

  self:setValue(number)
end

function UISpinBox:onValueChange(value)
  -- nothing to do
end

function UISpinBox:onFocusChange(focused)
  if not focused then
    if self:getText():len() == 0 then
      self:setText(self.minimum)
    end
  end
end

function UISpinBox:onStyleApply(styleName, styleNode)
  for name, value in pairs(styleNode) do
    if name == 'maximum' then
      self.maximum = value
      addEvent(function() self:setMaximum(value) end)
    elseif name == 'minimum' then
      self.minimum = value
      addEvent(function() self:setMinimum(value) end)
    elseif name == 'mouse-scroll' then
      addEvent(function() self:setMouseScroll(value) end)
    elseif name == 'allow-modifier' then
      self.allowModifiers = value
    elseif name == 'buttons' then
      addEvent(function()
        if value then
          self:showButtons()
        else
          self:hideButtons()
        end
      end)
    end
  end
end

function UISpinBox:showButtons()
  self:getChildById('up'):show()
  self:getChildById('down'):show()
  self.displayButtons = true
end

function UISpinBox:hideButtons()
  self:getChildById('up'):hide()
  self:getChildById('down'):hide()
  self.displayButtons = false
end

function UISpinBox:getCountByModifier()
  if not self.allowModifiers then
    return 0
  end
  
  local modifier = 1
  if g_keyboard.getModifiers() == KeyboardAltModifier then
    modifier = 1
  elseif g_keyboard.getModifiers() == KeyboardShiftModifier then
    modifier = 50
  elseif g_keyboard.getModifiers() == KeyboardCtrlModifier then
    modifier = 100
  end
  return modifier 
end

function UISpinBox:up()
  -- Custom values by array
  if not table.empty(self.possibleValues) then
    local value = self.value
    for i = #self.possibleValues, 1, -1 do
      if self.possibleValues[i] < value then
        value = self.possibleValues[i]
        break
      end
    end

    self:setValue(value)
    return
  end

  local modifier = self.step
  if self.allowModifiers then
    modifier = self:getCountByModifier()
  end

  self:setValue(self.value + modifier)
end

function UISpinBox:down()
  -- Custom values by array
  if not table.empty(self.possibleValues) then
    local value = self.value
    for _, v in pairs(self.possibleValues) do
      if v > value then
        value = v
        break
      end
    end

    self:setValue(value)
    return
  end

  local modifier = self.step
  if self.allowModifiers then
    modifier = self:getCountByModifier()
  end

  self:setValue(self.value - modifier)
end

function UISpinBox:setValue(value, dontSignal)
  if type(value) == "string" then
    value = tonumber(value)
  end
  value = value or 0
  value = math.max(math.min(self.maximum, value), self.minimum)

  if value == self.value then return end

  self.value = value
  if self:getText():len() > 0 then
    self:setText(value)
  end

  local upButton = self:getChildById('up')
  local downButton = self:getChildById('down')
  if upButton then
    upButton:setEnabled(self.maximum ~= self.minimum and self.value ~= self.maximum)
  end
  if downButton then
    downButton:setEnabled(self.maximum ~= self.minimum and self.value ~= self.minimum)
  end

  if not dontSignal then
    signalcall(self.onValueChange, self, value)
  end
end

function UISpinBox:getValue()
  return self.value
end

function UISpinBox:setMinimum(minimum)
  minimum = minimum or -9223372036854775808
  self.minimum = minimum
  if self.minimum > self.maximum then
    self.maximum = self.minimum
  end
  if self.value < minimum then
    self:setValue(minimum)
  end
end

function UISpinBox:getMinimum()
  return self.minimum
end

function UISpinBox:setMaximum(maximum)
  maximum = maximum or 9223372036854775807
  self.maximum = maximum
  if self.value > maximum then
    self:setValue(maximum)
  end
end

function UISpinBox:getMaximum()
  return self.maximum
end

function UISpinBox:setStep(step)
  self.step = step or 1
end

function UISpinBox:setMouseScroll(mouseScroll)
  self.mouseScroll = mouseScroll
end

function UISpinBox:getMouseScroll()
  return self.mouseScroll
end

function UISpinBox:updatePossibleValues(array)
  self.possibleValues = {}
  self.possibleValues = array
end