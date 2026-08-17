deathWindow = nil

local deathTexts = {
  regular = {text = 'Alas! Brave adventurer, you have met a sad fate.\nBut do not despair, for the gods will bring you back\ninto this world in exchange for a small sacrifice\n\nSimply click on Ok to resume your journeys!', height = 140, width = 0},
  unfair = {text = 'Alas! Brave adventurer, you have met a sad fate.\nBut do not despair, for the gods will bring you back\ninto this world in exchange for a small sacrifice\n\nThis death penalty has been reduced by %i%%\nbecause it was an unfair fight.\n\nSimply click on Ok to resume your journeys!', height = 185, width = 0},
  blessed = {text = 'Alas! Brave adventurer, you have met a sad fate.\nBut do not despair, for the gods will bring you back into this world\n\nThis death penalty has been reduced by 100%\nbecause you are blessed with the Adventurer\'s Blessing\n\nSimply click on Ok to resume your journeys!', height = 170, width = 90}
}

function init()
  g_ui.importStyle('deathwindow')

  connect(g_game, { onDeath = display,
                    onGameEnd = reset })
end

function terminate()
  disconnect(g_game, { onDeath = display,
                       onGameEnd = reset })

  reset()
end

function reset()
  if deathWindow then
    g_client.setInputLockWidget(nil)
    deathWindow:destroy()
    deathWindow = nil
  end
end

function display(deathType, penalty)
  displayDeadMessage()
  openWindow(deathType, penalty)
end

function displayDeadMessage()
  local advanceLabel = m_interface.getRootPanel():recursiveGetChildById('middleCenterLabel')
  if advanceLabel:isVisible() then return end
  modules.game_textmessage.displayGameMessage(tr('You are dead.'))
end

function openWindow(deathType, penalty)
  if deathWindow then
    deathWindow:destroy()
    return
  end

  deathWindow = g_ui.createWidget('DeathWindow', rootWidget)
  deathWindow:focus()
  g_client.setInputLockWidget(deathWindow)

  local miniBot = modules.game_minibot
  if miniBot and type(miniBot.onMiniBotGameWindowChangeFromPanel) == 'function' then
    miniBot.onMiniBotGameWindowChangeFromPanel('shooter_gamewindow', false)
    miniBot.onMiniBotGameWindowChangeFromPanel('combat_gamewindow', false)
  end

  local messageT = {}
  local textLabel = deathWindow:getChildById('labelText')
  if deathType == DeathType.Regular then
    if penalty == 100 then
	  setStringColor(messageT, 'Alas! Brave adventurer, you have met a sad fate.\nBut do not despair, for the gods will bring you back\ninto the world in exchange for a small sacrifice\n\nSimply click on ', "#c0c0c0")
	  setStringColor(messageT, "Ok ", "#ffffff")
	  setStringColor(messageT, 'to resume your journeys in game\nor on ', "#c0c0c0")
	  setStringColor(messageT, "Cancel ", "#ffffff")
	  setStringColor(messageT, 'to get to your character list!', "#c0c0c0")
	  textLabel:setColoredText(messageT)
      deathWindow:setHeight(deathWindow.baseHeight - 30)
      deathWindow:setWidth(deathWindow.baseWidth)
    else
	  setStringColor(messageT, 'Alas! Brave adventurer, you have met a sad fate.\nBut do not despair, for the gods will bring you back\ninto the world in exchange for a small sacrifice\n\n', "#c0c0c0")
	  setStringColor(messageT, 'This death penalty has been reduced by ' .. tostring(penalty) .. '%\nbecause it was a unfair fight.\n\nSimply click on ', "#c0c0c0")
	  setStringColor(messageT, "Ok ", "#ffffff")
	  setStringColor(messageT, 'to resume your journeys in game\nor on ', "#c0c0c0")
	  setStringColor(messageT, "Cancel ", "#ffffff")
	  setStringColor(messageT, 'to get to your character list!', "#c0c0c0")
	  textLabel:setColoredText(messageT)
      deathWindow:setHeight(deathWindow.baseHeight)
      deathWindow:setWidth(deathWindow.baseWidth)
    end
  end

  local okButton = deathWindow:getChildById('buttonOk')
  local cancelButton = deathWindow:getChildById('buttonCancel')

  local okFunc = function()
    g_client.setInputLockWidget(nil)
    okButton:getParent():destroy()
    deathWindow = nil

    if g_game.isOnline() then
      CharacterList.doLogin()
    end
  end
  local cancelFunc = function()
    g_client.setInputLockWidget(nil)
    if g_game.isOnline() then
      g_game.safeLogout()
    end

    cancelButton:getParent():destroy()
    deathWindow = nil
  end

  deathWindow.onEnter = okFunc
  deathWindow.onEscape = cancelFunc

  okButton.onClick = okFunc
  cancelButton.onClick = cancelFunc
end
