messagesPanel = nil

function init()
  for messageMode, _ in pairs(MessageTypes) do
    registerMessageMode(messageMode, displayMessage)
  end

  connect(g_game, 'onGameEnd', clearMessages)
  messagesPanel = g_ui.loadUI('textmessage', m_interface.getRootPanel())
end

function terminate()
  for messageMode, _ in pairs(MessageTypes) do
    unregisterMessageMode(messageMode, displayMessage)
  end

  disconnect(g_game, 'onGameEnd', clearMessages)
  clearMessages()
  if messagesPanel and not messagesPanel:isDestroyed() then
    messagesPanel:destroy()
  end
  messagesPanel = nil
end

function displayMessage(mode, text)
  if not g_game.isOnline() then return end

  local msgtype = MessageTypes[mode]
  if not msgtype then
    return
  end

  if msgtype == SpeakTypesSettings.none then return end

  if mode == MessageModes.Loot and not m_settings.getOption('showLootMessagesInConsole') then
    return
  end

  if mode == MessageModes.HotkeyUse and not m_settings.getOption('showHotkeyMessagesInConsole') then
    return
  end

  if msgtype.screenTarget and m_settings.getOption("showMessages") then
    local label = messagesPanel:recursiveGetChildById(msgtype.screenTarget)
    local hasColorLoot = type(text) == 'string' and ItemsDatabase and ItemsDatabase.hasColorLootMarkup and ItemsDatabase.hasColorLootMarkup(text)
    if hasColorLoot and ItemsDatabase.setColorLootMessage then
      local text2 = ItemsDatabase.setColorLootMessage(text, msgtype.color)
      label:setColoredText(text2)
    elseif not msgtype.colored then
      local tt = string.format("[color=%s]%s[/color]", msgtype.color, text)
      label:setColorText(tt)
    else
      local text2 = text:tocolored(msgtype.color)
      label:setColoredText(text2)
    end
    label:setVisible(true)
    removeEvent(label.hideEvent)

    label.hideEvent = scheduleEvent(function() label:setVisible(false) end, msgtype.visibleTime or 5000)
  end
end

function updateActionBarMessageMargin(margin)
  if not messagesPanel or messagesPanel:isDestroyed() then
    return
  end

  local statusLabel = messagesPanel:recursiveGetChildById('statusLabel')
  if statusLabel then
    statusLabel:setMarginBottom(margin or 7)
  end
end

function displayPrivateMessage(text)
  displayMessage(254, text)
end

function displayStatusMessage(text)
  displayMessage(MessageModes.Status, text)
end

function displayFailureMessage(text)
  displayMessage(MessageModes.Failure, text)
end

function displayGameMessage(text)
  displayMessage(MessageModes.Game, text)
end

function displayBroadcastMessage(text)
  displayMessage(MessageModes.Warning, text)
end

function clearMessages()
  if not messagesPanel or messagesPanel:isDestroyed() then
    return
  end

  for _i,child in pairs(messagesPanel:recursiveGetChildren()) do
    if child:getId():match('Label') then
      child:hide()
      removeEvent(child.hideEvent)
    end
  end
end

function LocalPlayer:onAutoWalkFail(player)
  modules.game_textmessage.displayFailureMessage(tr('There is no way.'))
end
