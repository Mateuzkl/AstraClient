windows = {}

function init()
  g_ui.importStyle('textwindow')

  connect(g_game, { onEditText = onGameEditText,
                    onEditList = onGameEditList,
                    onGameEnd = destroyWindows })
end

function terminate()
  disconnect(g_game, { onEditText = onGameEditText,
                       onEditList = onGameEditList,
                       onGameEnd = destroyWindows })

  destroyWindows()
end

function destroyWindows()
  for _,window in pairs(windows) do
    window:destroy()
    g_client.setInputLockWidget(nil)
  end
  windows = {}
end

function onGameEditText(id, itemId, maxLength, text, writer, time)
  local textWindow = g_ui.createWidget('TextWindow', rootWidget)

  g_client.setInputLockWidget(textWindow)

  local writeable = maxLength > 0 and (#text == 0 or #text < maxLength)
  local textItem = textWindow:getChildById('textItem')
  local description = textWindow:getChildById('description')
  local textEdit = textWindow:getChildById('text')
  local okButton = textWindow:getChildById('okButton')
  local cancelButton = textWindow:getChildById('cancelButton')
  local reportButton = textWindow:getChildById('reportButton')

  local textScroll = textWindow:getChildById('textScroll')

  if textItem:isHidden() then
    textItem:show()
  end

  local thing = g_things.getThingType(itemId)
  if writeable and (thing:hasAttribute(ThingAttrWritableOnce or thing:hasAttribute(ThingAttrWritable))) and #writer > 0 then
    writeable = false
  end

  textItem:setItemId(itemId)
  textEdit:setMaxLength(maxLength)
  textEdit:setText(text)
  textEdit:setEditable(writeable)
  textEdit:setCursorVisible(writeable)

  local desc = 'You read the following.'
  if #writer > 0 then
    desc = tr('You read the following, written by \n%s ', writer)
    description:setMarginTop(10)
    if #time > 0 then
      desc = desc .. tr('on %s.\n', time)
    else
      desc = desc .. tr('.\n')
    end
  elseif #time > 0 then
    desc = tr('You read the following, written on \n%s.\n', time)
  end

  if #text == 0 and not writeable then
    desc = tr("It is empty.")
  elseif writeable and #text == 0 then
    desc = tr('It is currently empty.\nYou can enter new text.')
  elseif writeable then
    desc = desc .. tr('You can enter new text.')
  end

  local lines = #{string.find(desc, '\n')}
  if lines < 2 then desc = desc .. '\n' end

  description:setText(desc)

  if not writeable then
    textWindow:setText(tr('Show Text'))
    cancelButton:hide()
    cancelButton:setWidth(0)
    reportButton:hide()
    reportButton:setWidth(0)
    okButton:setMarginRight(0)
  else
    textWindow:focusChild(textEdit, MouseFocusReason)
    textWindow:setText(tr('Edit Text'))
  end

  if description:getHeight() < 64 then
    description:setHeight(64)
  end

  local function destroy()
    textEdit:destroy()
    textWindow:destroy()
    g_client.setInputLockWidget(nil)
    table.removevalue(windows, textWindow)
  
    -- Bring back focus to main panel
    scheduleEvent(function() rootWidget:getChildById("gameRootPanel"):focus() end, 50)
  end

  local doneFunc = function()
    if writeable then
      g_game.editText(id, textEdit:getText())
    end
    g_client.setInputLockWidget(nil)
    destroy()
  end

  okButton.onClick = doneFunc
  cancelButton.onClick = destroy
  reportButton.onClick = destroy

  if not writeable then
    textWindow.onEnter = doneFunc
  end

  textWindow.onEscape = destroy

  table.insert(windows, textWindow)
  if writeable then
    textEdit:setCursorPos(-1)
  else
    textEdit:setCursorPos(0)
    textScroll:setValue(0)
  end
end

function onGameEditList(id, doorId, text)
  local textWindow = g_ui.createWidget('TextWindow', rootWidget)

  g_client.setInputLockWidget(textWindow)
  local textEdit = textWindow:getChildById('text')
  local description = textWindow:getChildById('description')
  local okButton = textWindow:getChildById('okButton')
  local cancelButton = textWindow:getChildById('cancelButton')
  local reportButton = textWindow:getChildById('reportButton')

  local textItem = textWindow:getChildById('textItem')
  if textItem and not textItem:isHidden() then
    textItem:hide()
  end

  textEdit:setMaxLength(8192)
  textEdit:setText(text)
  textEdit:setEditable(true)
  description:setText(tr('Enter one name per line.'))
  textWindow:setText(tr('Edit List'))

  if description:getHeight() < 64 then
    description:setHeight(64)
  end

  local function destroy()
    textWindow:destroy()
    g_client.setInputLockWidget(nil)
    table.removevalue(windows, textWindow)
    -- Bring back focus to main panel
    scheduleEvent(function() rootWidget:getChildById("gameRootPanel"):focus() end, 50)
  end

  local doneFunc = function()
    g_game.editList(id, doorId, textEdit:getText())
    g_client.setInputLockWidget(nil)
    destroy()
  end

  okButton.onClick = doneFunc
  cancelButton.onClick = destroy
  textWindow.onEscape = destroy
  reportButton.onClick = destroy

  table.insert(windows, textWindow)
end

function callbackCancel(self)
  local cancel = self:recursiveGetChildById('cancelButton')
  if cancel then
    cancel.onClick()
  end
end
