if not UIWindow then dofile 'uiwindow' end

-- @docclass
UIMessageBox = extends(UIWindow, "UIMessageBox")

-- messagebox cannot be created from otui files
UIMessageBox.create = nil

function UIMessageBox.display(title, message, buttons, onEnterCallback, onEscapeCallback)
  local messageBox = UIMessageBox.internalCreate()
  rootWidget:addChild(messageBox)

  messageBox:setStyle('MainWindow')
  messageBox:setText(title)
  messageBox:setFont("$var-cip-font")

  messageBox:insertLuaCall("onDestroy")
  messageBox.onDestroy = function()
    if messageBox.lastLockedWidget then
      g_client.setInputLockWidget(messageBox.lastLockedWidget)
    end

    if g_game.isOnline() then
      modules.game_console.getConsole():recursiveFocus(2)
    end
  end

  local messageLabel = g_ui.createWidget('MessageBoxLabel', messageBox)
  if type(message) == "table" then
    messageLabel:setColoredText(message)
  else
    messageLabel:setText(message)
  end

  local buttonsWidth = 0
  local buttonsHeight = 0

  local separator
  if #buttons > 0 then
    separator = g_ui.createWidget('HorizontalSeparator', messageBox)
    separator:addAnchor(AnchorTop, 'prev', AnchorBottom)
    separator:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    separator:addAnchor(AnchorRight, 'parent', AnchorRight)
    separator:setMarginTop(10)
  end

  if g_ui.getCustomInputWidget() then
    messageBox.lastLockedWidget = g_ui.getCustomInputWidget()
  end

  g_client.setInputLockWidget(nil)
  g_client.setInputLockWidget(messageBox)

  local anchor = AnchorRight
  if buttons.anchor then anchor = buttons.anchor end

  local buttonHolder = g_ui.createWidget('MessageBoxButtonHolder', messageBox)
  buttonHolder:addAnchor(anchor, 'parent', anchor)

  for i=1,#buttons do
    local button = messageBox:addButton(buttons[i].text, buttons[i].callback)
    if i == 1 then
      button:setMarginLeft(0)
      button:addAnchor(AnchorLeft, 'parent', AnchorLeft)
      buttonsHeight = button:getHeight()
    else
      button:addAnchor(AnchorBottom, 'prev', AnchorBottom)
      button:addAnchor(AnchorLeft, 'prev', AnchorRight)
    end

    if buttons[i].disabled then
      button:setEnabled(false)
    end

    buttonsWidth = buttonsWidth + button:getWidth() + button:getMarginLeft()
  end

  buttonHolder:setWidth(buttonsWidth)
  buttonHolder:setHeight(buttonsHeight)

  if onEnterCallback then connect(messageBox, { onEnter = onEnterCallback }) end
  if onEscapeCallback then connect(messageBox, { onEscape = onEscapeCallback }) end

  local height = messageLabel:getHeight() + messageBox:getPaddingTop() + messageBox:getPaddingBottom() + buttonHolder:getHeight() + buttonHolder:getMarginTop()
  if separator then
    height = height + separator:getHeight() + separator:getMarginTop()
  end

  messageBox:setWidth(math.max(messageLabel:getWidth(), messageBox:getTextSize().width, buttonHolder:getWidth()) + messageBox:getPaddingLeft() + messageBox:getPaddingRight())
  messageBox:setHeight(height)
  return messageBox
end

function displayInfoBox(title, message)
  local messageBox
  local defaultCallback = function() messageBox:ok() end
  messageBox = UIMessageBox.display(title, message, {{text='Ok', callback=defaultCallback}}, defaultCallback, defaultCallback)
  return messageBox
end

function displayInfoBox(title, message, okFunc)
  local messageBox
  local defaultCallback = function() messageBox:ok() end
  if okFunc then
    defaultCallback = function() okFunc() messageBox:ok() end
  end
  messageBox = UIMessageBox.display(title, message, {{text='Ok', callback=defaultCallback}}, defaultCallback, defaultCallback)
  return messageBox
end

function displayNonCloseInfoBox(title, message)
  local messageBox
  local defaultCallback = nil
  messageBox = UIMessageBox.display(title, message, {}, defaultCallback, defaultCallback)
  return messageBox
end

function alert(message)
	return displayInfoBox("Alert", tostring(message or ""))
end

function displayErrorBox(title, message)
  local messageBox
  local defaultCallback = function() messageBox:ok() end
  messageBox = UIMessageBox.display(title, message, {{text='Ok', callback=defaultCallback}}, defaultCallback, defaultCallback)
  return messageBox
end

function displayCancelBox(title, message)
  local messageBox
  local defaultCallback = function() messageBox:cancel() end
  messageBox = UIMessageBox.display(title, message, {{text='Cancel', callback=defaultCallback}}, defaultCallback, defaultCallback)
  return messageBox
end

function displayGeneralBox(title, message, buttons, onEnterCallback, onEscapeCallback)
  return UIMessageBox.display(title, message, buttons, onEnterCallback, onEscapeCallback)
end

function UIMessageBox:addButton(text, callback)
  local buttonHolder = self:getChildById('buttonHolder')
  local button = g_ui.createWidget('MessageBoxButton', buttonHolder)
  button:setText(text)
  connect(button, { onClick = callback })
  return button
end

function UIMessageBox:ok()
  signalcall(self.onOk, self)
  self.onOk = nil
  self:destroy()

  if g_game.isOnline() then
    modules.game_console.getConsole():recursiveFocus(2)
  end
end

function UIMessageBox:cancel()
  signalcall(self.onCancel, self)
  self.onCancel = nil
  self:destroy()
end
