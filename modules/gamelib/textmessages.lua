local messageModeCallbacks = {}

function g_game.onTextMessage(messageMode, message)
  -- Market message
  if messageMode == 40 then
    local player = g_game.getLocalPlayer()
    if player and player:isInMarket() and modules.game_tibia_market and modules.game_tibia_market.marketWindow and g_ui.getCustomInputWidget() == modules.game_tibia_market.marketWindow then
      scheduleEvent(function() if modules.game_tibia_market and modules.game_tibia_market.marketWindow then modules.game_tibia_market.marketWindow:hide() end end, 50)
      displayInfoBox(tr("Market Message"), message, function() if modules.game_tibia_market and modules.game_tibia_market.marketWindow then modules.game_tibia_market.marketWindow:show() end end)
    end
    return
  end

  local extraInfo = ''
  if messageMode == 0 then
    extraInfo = ' (MessageModes.None)'
  end

  local callbacks = messageModeCallbacks[messageMode]
  if not callbacks or #callbacks == 0 then
    perror(string.format('Unhandled onTextMessage message mode %i: %s |%s', messageMode, message, extraInfo))
    return
  end

  for _, callback in pairs(callbacks) do
    callback(messageMode, message)
  end
end

function registerMessageMode(messageMode, callback)
  if not messageModeCallbacks[messageMode] then
    messageModeCallbacks[messageMode] = {}
  end

  table.insert(messageModeCallbacks[messageMode], callback)
  return true
end

function unregisterMessageMode(messageMode, callback)
  if not messageModeCallbacks[messageMode] then
    return false
  end

  return table.removevalue(messageModeCallbacks[messageMode], callback)
end
