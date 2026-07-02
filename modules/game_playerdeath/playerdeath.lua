deathWindow = nil

RequestOpenStore = false

local deathTexts = {
  regular = {text = 'Alas! Brave adventurer, you have met a sad fate.\nBut do not despair, for the gods will bring you back\ninto this world in exchange for a small sacrifice\n\nSimply click on Ok to resume your journeys!', height = 140, width = 0},
  unfair = {text = 'Alas! Brave adventurer, you have met a sad fate.\nBut do not despair, for the gods will bring you back\ninto this world in exchange for a small sacrifice\n\nThis death penalty has been reduced by %i%%\nbecause it was an unfair fight.\n\nSimply click on Ok to resume your journeys!', height = 185, width = 0},
  blessed = {text = 'Alas! Brave adventurer, you have met a sad fate.\nBut do not despair, for the gods will bring you back into this world\n\nThis death penalty has been reduced by 100%\nbecause you are blessed with the Adventurer\'s Blessing\n\nSimply click on Ok to resume your journeys!', height = 170, width = 90}
}

function init()
  g_ui.importStyle('deathwindow')

  connect(g_game, { onDeath = display,
                    onGameEnd = reset,
                    onEnterGame = onEnterGame })
end

function terminate()
  disconnect(g_game, { onDeath = display,
                       onGameEnd = reset,
                       onEnterGame = onEnterGame })

  reset()
end

function onEnterGame()
  if not RequestOpenStore then
    return
  end

  RequestOpenStore = false
  g_game.doThing(false)
  g_game.openStore()
  g_game.doThing(true)
  g_game.doThing(false)
  modules.game_store.Store:openHome()
  g_game.doThing(true)
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

  -- NOTE: do NOT disable Magic Shooter / Auto Target here. The player owns those
  -- toggles. Dying resumes in-game via processPendingGame() (no logout), respawning
  -- at the temple -- a PZ where the combat routines already hold fire on
  -- PlayerStates.Pz -- so leaving the toggles ON is safe and they resume on exit.
  -- Killing them here left them off after respawn with nothing to turn them back on
  -- (no relog means reapplyAutomationAfterRelog never runs).

  local messageT = {}
  local textLabel = deathWindow:getChildById('labelText')
  if deathType == DeathType.Regular then
    if penalty == 100 then
	  setStringColor(messageT, 'Alas! Brave adventurer, you have met a sad fate.\nBut do not despair, for the gods will bring you back\ninto the world in exchange for a small sacrifice\n\nSimply click on ', "#c0c0c0")
	  setStringColor(messageT, "Ok ", "#ffffff")
	  setStringColor(messageT, 'to resume your journeys in game\nor on ', "#c0c0c0")
	  setStringColor(messageT, "Cancel ", "#ffffff")
	  setStringColor(messageT, 'to get to your character list!\n\nClick on ', "#c0c0c0")
	  setStringColor(messageT, "Store ", "#ffffff")
	  setStringColor(messageT, 'to resume your journeys and to shop\nblessings to ease the pain if you are unfortunate\nenough to lose another fight!', "#c0c0c0")
	  textLabel:setColoredText(messageT)
      deathWindow:setHeight(deathWindow.baseHeight + 15)
      deathWindow:setWidth(deathWindow.baseWidth)
    else
	  setStringColor(messageT, 'Alas! Brave adventurer, you have met a sad fate.\nBut do not despair, for the gods will bring you back\ninto the world in exchange for a small sacrifice\n\n', "#c0c0c0")
	  setStringColor(messageT, 'This death penalty has been reduced by ' .. tostring(penalty) .. '%\nbecause it was a unfair fight.\n\nSimply click on ', "#c0c0c0")
	  setStringColor(messageT, "Ok ", "#ffffff")
	  setStringColor(messageT, 'to resume your journeys in game\nor on ', "#c0c0c0")
	  setStringColor(messageT, "Cancel ", "#ffffff")
	  setStringColor(messageT, 'to get to your character list!\n\nClick on ', "#c0c0c0")
	  setStringColor(messageT, "Store ", "#ffffff")
	  setStringColor(messageT, 'to resume your journeys and to shop\nblessings to ease the pain if you are unfortunate\nenough to lose another fight!', "#c0c0c0")
	  textLabel:setColoredText(messageT)
      deathWindow:setHeight(deathWindow.baseHeight + 46)
      deathWindow:setWidth(deathWindow.baseWidth)
    end
  end

  local okButton = deathWindow:getChildById('buttonOk')
  local cancelButton = deathWindow:getChildById('buttonCancel')
  local buttonStore = deathWindow:getChildById('buttonStore')

  local buttonStoreFunc = function()
    g_client.setInputLockWidget(nil)
    if g_game.isOnline() then
      g_game.processPendingGame()
      g_game.setDead(false)
      RequestOpenStore = true
    end

    deathWindow:destroy()
    deathWindow = nil
  end

  local okFunc = function()
    g_client.setInputLockWidget(nil)
    if g_game.isOnline() then
      g_game.processPendingGame()
      g_game.setDead(false)
    end

    okButton:getParent():destroy()
    deathWindow = nil
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
  buttonStore.onClick = buttonStoreFunc
end
