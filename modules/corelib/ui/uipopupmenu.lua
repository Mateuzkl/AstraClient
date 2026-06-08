-- @docclass
UIPopupMenu = extends(UIWidget, "UIPopupMenu")

local currentMenu

local function isNpcTradeInputWidget(widget)
  if not widget or (widget.isDestroyed and widget:isDestroyed()) then
    return false
  end

  local id = widget.getId and widget:getId() or nil
  if id == 'chatInput' or id == 'tradeSearchInput' or id == 'tradeAmountInput' then
    return true
  end

  return controllerNpcTrader and controllerNpcTrader._npcInputLockWidget == widget
end

local function restoreNpcTradeInput(widget)
  if not isNpcTradeInputWidget(widget) then
    return false
  end

  if controllerNpcTrader and controllerNpcTrader.focusNpcTextInput then
    controllerNpcTrader:focusNpcTextInput(widget)
    return true
  end

  if g_ui and g_ui.setInputLockWidget then
    g_ui.setInputLockWidget(widget)
  end
  if widget.grabKeyboard then
    widget:grabKeyboard()
  end
  if widget.focus then
    widget:focus()
  end
  return true
end

function UIPopupMenu.create()
  local menu = UIPopupMenu.internalCreate()
  local layout = UIVerticalLayout.create(menu)
  layout:setFitChildren(true)
  menu:setLayout(layout)
  menu.isGameMenu = false
  menu:insertLuaCall("onGeometryChange")
  menu:insertLuaCall("onDestroy")

  if g_ui.getCustomInputWidget() then
    menu.lastLockedWidget = g_ui.getCustomInputWidget()
  end

  g_client.setInputLockWidget(nil)
  g_client.setInputLockWidget(menu)
  return menu
end

function UIPopupMenu:display(pos)
  -- don't display if not options was added
  if self:getChildCount() == 0 then
    self:destroy()
    return
  end

  if g_ui.isMouseGrabbed() then
    self:destroy()
    return
  end

  if currentMenu then
    currentMenu:destroy()
  end

  if pos == nil then
    pos = g_window.getMousePosition()
  end

  rootWidget:addChild(self)
  self:setPosition(pos)
  g_mouse.updateGrabber(self, '')
  self:grabMouse()
  self:focus()
  self:setHeight(self:getHeight() + 10)
  --self:grabKeyboard()
  currentMenu = self
end

function UIPopupMenu:onGeometryChange(oldRect, newRect)
  local parent = self:getParent()
  if not parent then return end
  local ymax = parent:getY() + parent:getHeight()
  local xmax = parent:getX() + parent:getWidth()
  if newRect.y + newRect.height > ymax then
    local newy = ymax - newRect.height
    if newy > 0 and newy + newRect.height < ymax then self:setY(newy) end
  end
  if newRect.x + newRect.width > xmax then
    local newx = xmax - newRect.width
    if newx > 0 and newx + newRect.width < xmax then self:setX(newx) end
  end
  self:bindRectToParent()
end

function UIPopupMenu:addOption(optionName, optionCallback, shortcut)
  local optionWidget = g_ui.createWidget(self:getStyleName() .. 'Button', self)
  optionWidget.onClick = function(widget)
    self:destroy()
    optionCallback()
  end
  if type(optionName) == 'table' then
    optionWidget:setColoredText(optionName)
  else
    optionWidget:setText(optionName)
  end
  local width = optionWidget:getTextSize().width + optionWidget:getMarginLeft() + optionWidget:getMarginRight() + 50

  if shortcut then
    local shortcutLabel = g_ui.createWidget(self:getStyleName() .. 'ShortcutLabel', optionWidget)
    if type(shortcut) == 'table' then
      shortcutLabel:setColoredText(shortcut)
    else
      shortcutLabel:setText(tr(shortcut))
    end
    width = width + shortcutLabel:getTextSize().width + shortcutLabel:getMarginLeft() + shortcutLabel:getMarginRight()
  end

  self:setWidth(math.max(self:getWidth(), width))
  self:setHeight(self:getHeight() + optionWidget:getHeight())
end

function UIPopupMenu:addCheckBoxOption(optionName, optionCallback, shortcut, checked)
  local optionWidget = g_ui.createWidget(self:getStyleName() .. 'CheckBox', self)
  optionWidget.onClick = function(widget)
    optionCallback()
    self:destroy()
  end
  optionWidget:setText(optionName)
  optionWidget:setChecked(checked)
  local width = optionWidget:getTextSize().width + optionWidget:getMarginLeft() + optionWidget:getMarginRight() + 50

  if shortcut then
    local shortcutLabel = g_ui.createWidget(self:getStyleName() .. 'ShortcutLabel', optionWidget)
    shortcutLabel:setText(shortcut)
    width = width + shortcutLabel:getTextSize().width + shortcutLabel:getMarginLeft() + shortcutLabel:getMarginRight()
  end

  self:setWidth(math.max(self:getWidth(), width))
  return optionWidget
end

function UIPopupMenu:addSeparator()
  local separator = g_ui.createWidget('HorizontalSeparator', self)
  separator:setMarginLeft(1)
  separator:setMarginRight(1)
  self:setHeight(self:getHeight() + (separator:getHeight() + 4))
end

function UIPopupMenu:setGameMenu(state)
  self.isGameMenu = state
  self:setHeight(22)
end

function UIPopupMenu:onDestroy()
  if currentMenu == self then
    currentMenu = nil
  end
  g_mouse.updateGrabber(self, '')
  self:ungrabMouse()
  local restoredNpcInput = false
  if self.lastLockedWidget then
    restoredNpcInput = restoreNpcTradeInput(self.lastLockedWidget)
    if not restoredNpcInput then
      g_client.setInputLockWidget(self.lastLockedWidget)
    end
  end

  -- Bring back focus to main panel
  if not restoredNpcInput then
    scheduleEvent(function() rootWidget:getChildById("gameRootPanel"):focus() end, 50)
  end
end

function UIPopupMenu:onMousePress(mousePos, mouseButton)
  -- clicks outside menu area destroys the menu
  if not self:containsPoint(mousePos) then
    self:destroy()
  end
  return true
end

function UIPopupMenu:onKeyPress(keyCode, keyboardModifiers)
  if keyCode == KeyEscape then
    self:destroy()
    return true
  end
  return false
end

-- close all menus when the window is resized
local function onRootGeometryUpdate()
  if currentMenu then
    currentMenu:destroy()
  end
end

local function onGameEnd()
  if currentMenu and currentMenu.isGameMenu then
    currentMenu:destroy()
  end
end

connect(rootWidget, { onGeometryChange = onRootGeometryUpdate })
connect(g_game, { onGameEnd = onGameEnd } )
