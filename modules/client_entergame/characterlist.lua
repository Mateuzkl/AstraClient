CharacterList = { }
CharacterList.message = ''
CharacterList.waiting = false
CharacterList.scheduleTime = 5

local function worldIsComingSoon(worldId)
  local world = Worlds:getWorldById(worldId)
  if world and os.time() < world:getGrandOpening() then
    return true
  end

  return false
end

-- private variables
local charactersWindow
local characterList
local panelSort
local lastSortButton
local errorBox
local waitingWindow
local updateWaitEvent
local resendWaitEvent
local autoReconnectEvent
local lastWidget
local lastLogout = 0

CharacterList.camRecordCheck = nil

local function widgetAlive(widget)
  if widget == nil then
    return false
  end

  if g_ui ~= nil and type(g_ui.isWidgetAlive) == 'function' then
    local ok, alive = pcall(g_ui.isWidgetAlive, widget)
    return ok and alive == true
  end

  local ok, destroyed = pcall(function()
    return widget:isDestroyed()
  end)
  return ok and not destroyed
end

local function updateWait(timeStart, timeEnd)
  if errorBox and errorBox:isVisible() then
    errorBox:setVisible(false)
  end

  if updateWaitEvent then
    removeEvent(updateWaitEvent)
    updateWaitEvent = nil
  end

  if g_game.isOnline() then
    if waitingWindow then
      waitingWindow:destroy()
      waitingWindow = nil
    end
    if updateWaitEvent then
      removeEvent(updateWaitEvent)
      updateWaitEvent = nil
    end
    return false
  end

  LoginEvent:reset()

  if not waitingWindow then
    waitingWindow = g_ui.displayUI('waitinglist')

    local label = waitingWindow.contentPanel:getChildById('infoLabel')
    label:setText(CharacterList.message)
  end

  if waitingWindow then
    local time = g_clock.seconds()
    if time <= timeEnd then
      local percent = ((time - timeStart) / (timeEnd - timeStart)) * 100
      local timeStr = string.format("%.0f", timeEnd - time)

      local progressBar = waitingWindow.contentPanel:getChildById('progressBar')
      progressBar:setPercent(percent)

      local label = waitingWindow.contentPanel:getChildById('timeLabel')
      label:setText(tr('Trying to reconnect in %s seconds.', timeStr))

      updateWaitEvent = scheduleEvent(function() updateWait(timeStart, timeEnd) end, 1000 * progressBar:getPercentPixels() / 100 * (timeEnd - timeStart))
      return true
    end
  end

end

local function resendWait()
  if updateWaitEvent then
    removeEvent(updateWaitEvent)
    updateWaitEvent = nil
  end

  LoginEvent:reset()

  if waitingWindow then
    waitingWindow:destroy()
    waitingWindow = nil

    if widgetAlive(charactersWindow) and widgetAlive(characterList) then
      local selected = characterList:getFocusedChild()
      if selected then
        local charInfo = {
                          worldHost = selected.worldHost,
                          worldPort = selected.worldPort,
                          worldName = selected.gameworldName,
                          vocation = selected.vocationName,
                          characterName = selected.characterName, }

        LoginEvent:setCharInfo(charInfo)
      end
    end
  end
end

local function updateTryLogin(timeStart, timeEnd)
  if updateWaitEvent then
    removeEvent(updateWaitEvent)
    updateWaitEvent = nil
  end

  if errorBox then
    local time = g_clock.seconds()
    if time <= timeEnd then
      local percent = ((time - timeStart) / (timeEnd - timeStart)) * 100
      local timeStr = string.format("%.0f", timeEnd - time)

      local progressBar = errorBox.contentPanel:getChildById('progressBar')
      progressBar:setPercent(percent)

      local label = errorBox.contentPanel:getChildById('timeLabel')
      label:setText(tr('Trying to reconnect in %s seconds.', timeStr))

      updateWaitEvent = scheduleEvent(function() updateTryLogin(timeStart, timeEnd) end, 1000 * progressBar:getPercentPixels() / 100 * (timeEnd - timeStart))
      return true
    end
  end
end

local function onLoginWait(message, time)
  consoleln("[+] CharacterList.onLoginWait()" .. message .. " " .. time)
  CharacterList.destroyLoadBox()

  if waitingWindow then
    waitingWindow:destroy()
    waitingWindow = nil
  end

  if updateWaitEvent then
    removeEvent(updateWaitEvent)
    updateWaitEvent = nil
  end

  if resendWaitEvent then
    removeEvent(resendWaitEvent)
    resendWaitEvent = nil
  end

  CharacterList.waiting = true
  CharacterList.scheduleTime = time
  waitingWindow = g_ui.displayUI('waitinglist')

  local label = waitingWindow.contentPanel:getChildById('infoLabel')
  label:setText(message)
  CharacterList.message = message

  updateWaitEvent = scheduleEvent(function() updateWait(g_clock.seconds(), g_clock.seconds() + time) end, 0)
  resendWaitEvent = scheduleEvent(resendWait, time * 1000)
end

function onGameLoginError(message)
  if modules.client_background and modules.client_background.handleCastLoginError
     and modules.client_background.handleCastLoginError(message) then
    return
  end

  consoleln("[+] CharacterList.onGameLoginError()", message)
  CharacterList.destroyLoadBox()

  if message:find("Your client version is too old.\n") then
      local okFunc = function()
        local path = os.getenv("EMAC_ASTRACLIENT_LAUNCHER_LAST_PATH")
        if not path then
          return
        end

        local ok, err = os.execute('start "" "' .. path .. '"')
        if not ok then
          g_logger.error(err)
        end
        g_app.exit()
      end

      local cancelFunc = function()
        -- I assume it wasn't destroyed before
        if errorBox then
          errorBox:destroy()
        end
        errorBox = nil
        CharacterList.showAgain()
      end

      local ExitFunc = function()
        g_app.exit()
      end

      errorBox = displayGeneralBox(tr('Info'), "Your client version is too old.\nRestart Astra to update your client.", {
        { text=tr('Update'), callback=okFunc },
        { text=tr('Exit'), callback=ExitFunc },
        { text=tr('Cancel'), callback=cancelFunc }
      }, okFunc, cancelFunc)
      return
  end

  if errorBox then
    errorBox:destroy()
    errorBox = nil
  end

  if autoReconnectEvent then
    removeEvent(autoReconnectEvent)
    autoReconnectEvent = nil
  end

  errorBox = displayErrorBox(tr("Login Error"), message)
  errorBox.onOk = function()
    -- I assume it wasn't destroyed before
    if errorBox then
      errorBox:destroy()
    end
    errorBox = nil
    CharacterList.showAgain()
  end
end

function onGameSessionEnd(messageId)
  CharacterList.destroyLoadBox()
  if messageId == 0 then
    CharacterList.showAgain()
    return
  end

  errorBox = displayErrorBox(tr("Login Error"), "You have been disconnected")
  errorBox.onOk = function()
    -- I assume it wasn't destroyed before
    if errorBox then
      errorBox:destroy()
    end
    errorBox = nil
    CharacterList.showAgain()
  end
end

function onGameLoginToken(unknown)
  CharacterList.destroyLoadBox()
  -- TODO: make it possible to enter a new token here / prompt token
  errorBox = displayErrorBox(tr("Two-Factor Authentification"), 'A new authentification token is required.\nPlease login again.')
  errorBox.onOk = function()
    errorBox = nil
    EnterGame.show()
  end
end

function onGameConnectionError(message, code)
  if modules.client_background and modules.client_background.handleCastLoginError
     and modules.client_background.handleCastLoginError(message, code) then
    return
  end

  CharacterList.destroyLoadBox()
  if errorBox and code ~= 2 then
    errorBox:destroy()
    errorBox = nil
  end

  if (not g_game.isOnline() or code ~= 2) and not errorBox then -- code 2 is normal disconnect, end of file
    if code == 10054 then
        errorBox = displayErrorBox(tr("Connection Lost"), "The connection to the game server was lost.\n\nError: The remote host closed the connection.\n\nPlease try again later.")
        errorBox.onOk = function()
          -- I assume it wasn't destroyed before
          if errorBox then
            errorBox:destroy()
          end
          errorBox = nil
          CharacterList.showAgain()
        end

        scheduleAutoReconnect()
        return
    end

    if code == 16654 then
        errorBox = displayErrorBox(tr("Connection Failed"), "Cannot connect to the game server.\n\nError: Connection refused.\n\nThe game server is offline. Check astraclient.local\nfor more information.\n\nFor more information take a look at the FAQs in the\nSupport section at astraclient.local.")
        errorBox.onOk = function()
          -- I assume it wasn't destroyed before
          if errorBox then
            errorBox:destroy()
          end
          errorBox = nil
          CharacterList.showAgain()
        end

        scheduleAutoReconnect()
        return
    end

    if code == 16655 then
      errorBox = displayErrorBox(tr("Connection Failed"), "Couldn't authenticate your account.\n\nPlease try again later.")
      errorBox.onOk = function()
        -- I assume it wasn't destroyed before
        if errorBox then
          errorBox:destroy()
        end
        errorBox = nil
        CharacterList.hide(true)
      end
      return
  end

    if code == 2 or code == 10061 then
      errorBox = g_ui.displayUI('waitinglist')
      local function removeEventAndDestroy()
        if errorBox then
          errorBox:destroy()
        end
        errorBox = nil
        CharacterList.showAgain()
        if autoReconnectEvent then
          removeEvent(autoReconnectEvent)
        end
      end

      errorBox.onEscape = removeEventAndDestroy
      errorBox.onEnter = function()
        removeEventAndDestroy()
        LoginEvent.loginTries = 0
      end
      errorBox:recursiveGetChildById('buttonCancel').onClick = function()
        removeEventAndDestroy()
        LoginEvent.loginTries = 0
      end

      local label = errorBox.contentPanel:getChildById('infoLabel')
      label:setText("Failed to establish connection to\nthe game server.\nFailed attempts so far: " .. LoginEvent.loginTries)
      updateWaitEvent = scheduleEvent(function() updateTryLogin(g_clock.seconds(), g_clock.seconds() + 5) end, 0)
      scheduleReconnect()
      return
    end

    local text = translateNetworkError(code, g_game.getProtocolGame() and g_game.getProtocolGame():isConnecting(), message)
    errorBox = displayErrorBox(tr("Connection Error"), text)
    errorBox.onOk = function()
      -- I assume it wasn't destroyed before
      if errorBox then
        errorBox:destroy()
      end
      errorBox = nil
      CharacterList.showAgain()
    end
  end

  if g_game.isOnline() then
    scheduleAutoReconnect()
  end
end

function executeReconnect()
  if not widgetAlive(characterList) then
    return
  end

  local selected = characterList:getFocusedChild()
  if not selected then return end

  if g_game.isOnline() then
    return
  end

  if errorBox then
    errorBox:destroy()
    errorBox = nil
  end

  CharacterList.doLogin()
end

function scheduleReconnect()
  if lastLogout + 2000 > g_clock.millis() and LoginEvent.loginTries >= 9 then
    return
  end
  if autoReconnectEvent then
    removeEvent(autoReconnectEvent)
  end
  autoReconnectEvent = scheduleEvent(executeReconnect, CharacterList.scheduleTime * 1000)
end

function onGameUpdateNeeded(signature)
  CharacterList.destroyLoadBox()
  errorBox = displayErrorBox(tr("Update needed"), tr('Enter with your account again to update your client.'))
  errorBox.onOk = function()
    -- I assume it wasn't destroyed before
    if errorBox then
      errorBox:destroy()
    end
    errorBox = nil
    CharacterList.showAgain()
  end
end

local function onCharacterListGameEnd()
  if CharacterList and CharacterList.showAgain then
    CharacterList.showAgain()
  end
end

function onLogout()
  lastLogout = g_clock.millis()
  local characterName = g_game.getCharacterName()
  if characterName then
    saveAutoReconnect(characterName, g_settings.getBoolean('autoReconnect', false))
  end
end

function scheduleAutoReconnect()
  if autoReconnectEvent then
    removeEvent(autoReconnectEvent)
  end
  autoReconnectEvent = scheduleEvent(executeAutoReconnect, 2500)
end

function executeAutoReconnect()
  -- disconnect por recorder
  if not widgetAlive(characterList) then
    return
  end
  local selected = characterList:getFocusedChild()
  if not selected then return end

  local autoReconnect = getAutoReconnect(selected.characterName)

  if autoReconnect == false or g_game.isOnline() then
    return
  end

  if errorBox then
    errorBox:destroy()
    errorBox = nil
  end

  CharacterList.doLogin()
end

-- public functions
function CharacterList.init()
  if USE_NEW_ENERGAME then return end
  connect(g_game, { onLoginError = onGameLoginError })
  connect(g_game, { onLoginToken = onGameLoginToken })
  connect(g_game, { onUpdateNeeded = onGameUpdateNeeded })
  connect(g_game, { onConnectionError = onGameConnectionError })
  connect(g_game, { onGameStart = CharacterList.destroyLoadBox })
  connect(g_game, { onLoginWait = onLoginWait })
  connect(g_game, { onGameEnd = onCharacterListGameEnd })
  connect(g_game, { onLogout = onLogout })
  connect(g_game, { onSessionEnd = onGameSessionEnd })

  if G.characters then
    CharacterList.create(G.characters, G.characterAccount)
  end
end

function CharacterList.terminate()
 if USE_NEW_ENERGAME then return end
  disconnect(g_game, { onLoginError = onGameLoginError })
  disconnect(g_game, { onLoginToken = onGameLoginToken })
  disconnect(g_game, { onUpdateNeeded = onGameUpdateNeeded })
  disconnect(g_game, { onConnectionError = onGameConnectionError })
  disconnect(g_game, { onGameStart = CharacterList.destroyLoadBox })
  disconnect(g_game, { onLoginWait = onLoginWait })
  disconnect(g_game, { onGameEnd = onCharacterListGameEnd })
  disconnect(g_game, { onLogout = onLogout })
  disconnect(g_game, { onSessionEnd = onGameSessionEnd })

  g_client.setInputLockWidget(nil)
  local window = charactersWindow
  charactersWindow = nil
  characterList = nil
  panelSort = nil
  lastSortButton = nil
  CharacterList.camRecordCheck = nil
  if widgetAlive(window) then
    window:destroy()
  end

  if g_game.isLogging() then
    LoginEvent:cancelLogin()
  else
    LoginEvent:destroyLoadBox()
  end

  local waitWindow = waitingWindow
  waitingWindow = nil
  if widgetAlive(waitWindow) then
    waitWindow:destroy()
  end

  local currentErrorBox = errorBox
  errorBox = nil
  if widgetAlive(currentErrorBox) then
    currentErrorBox:destroy()
  end

  if updateWaitEvent then
    removeEvent(updateWaitEvent)
    updateWaitEvent = nil
  end

  if resendWaitEvent then
    removeEvent(resendWaitEvent)
    resendWaitEvent = nil
  end

  if autoReconnectEvent then
    removeEvent(autoReconnectEvent)
    autoReconnectEvent = nil
  end

  LoginEvent:reset()

  if lastWidget then
    lastWidget = nil
  end

  CharacterList = nil
end

function CharacterList.create(characters, account, otui)
  if not otui then otui = 'characterlist' end
  local oldWindow = charactersWindow
  charactersWindow = nil
  characterList = nil
  panelSort = nil
  CharacterList.camRecordCheck = nil
  if widgetAlive(oldWindow) then
    oldWindow:destroy()
  end

  charactersWindow = g_ui.displayUI(otui)
  characterList = charactersWindow:getChildById('characters')
  panelSort = charactersWindow:getChildById('characterTable')
  CharacterList.camRecordCheck = charactersWindow.recordPanel:getChildById("recordSession")

  charactersWindow.static = not g_game.isOnline()

  -- characters
  G.characters = characters
  G.characterAccount = account

  lastWidget = nil

  local showOutfit = Options.getOption("characterSelectionShowOutfits")
  if not showOutfit then
    charactersWindow.characterTable.characterSort:setTextOffset("-206 0")
  else
    charactersWindow.characterTable.characterSort:setTextOffset("-73 0")
  end

  local outfitCheckBox = charactersWindow:recursiveGetChildById('checkBoxOutfit')
  outfitCheckBox:setChecked(showOutfit, true)
  onReorderCharacterList()

  characterList.onChildFocusChange = function(self, focusChild, oldFocusChild)
    characterList:ensureChildVisible(focusChild)
    removeEvent(autoReconnectEvent)
    autoReconnectEvent = nil
  end

  if focusLabel then
    characterList:focusChild(focusLabel, KeyboardFocusReason, true)
    local list = characterList
    local label = focusLabel
    addEvent(function()
      if widgetAlive(list) and widgetAlive(label) then
        list:ensureChildVisible(label)
      end
    end)
  end

  -- account
  local status = ''
  if account.status == AccountStatus.Frozen then
    status = tr(' (Frozen)')
  elseif account.status == AccountStatus.Suspended then
    status = tr(' (Suspended)')
  end

  local accountStatusLabel = charactersWindow:getChildById('accountStatusLabel')
  accountStatusLabel:setImageShader("")
  if account.subStatus == SubscriptionStatus.Free and account.premDays < 1 then
    accountStatusLabel:setText(('%s%s'):format(tr('Free Account'), status))
    charactersWindow.accountStatusIcon:setImageSource("/images/game/entergame/nopremium")
  else
    if account.premDays == 0 or account.premDays == 65535 then
      accountStatusLabel:setText(('%s%s'):format(tr('VIP Account (Free days left)', account.premDays), status))
      charactersWindow.accountStatusIcon:setImageSource("/images/game/entergame/premium")
    else
      accountStatusLabel:setText(('%s%s'):format(tr('VIP Account (%s days left)', account.premDays), status))
      accountStatusLabel:setImageShader("text_green")
      charactersWindow.accountStatusIcon:setImageSource("/images/game/entergame/premium")
    end
  end

  if account.premDays > 0 and account.premDays <= 7 then
    accountStatusLabel:setOn(true)
  else
    accountStatusLabel:setOn(false)
  end
end

function CharacterList.camRecordCheck()
  local camRecord = widget:isChecked()
  g_settings.set("recordSession", camRecord)
end

function CharacterList.destroy()
  CharacterList.hide(true)
  local window = charactersWindow
  charactersWindow = nil
  characterList = nil
  panelSort = nil
  lastSortButton = nil
  CharacterList.camRecordCheck = nil
  if widgetAlive(window) then
    window:destroy()
  end
end

function CharacterList.show()
  if not G.characters then
    consoleln("[!] CharacterList.show() - No characters found")
    return
  end

  if LoginEvent:getLoadBox() or errorBox or not widgetAlive(charactersWindow) then return end

  g_client.setInputLockWidget(nil)
  charactersWindow:show()
  charactersWindow:raise()
  charactersWindow:focus()
  g_client.setInputLockWidget(charactersWindow)

  charactersWindow.static = not g_game.isOnline()
  if not charactersWindow.startPos then
    charactersWindow.startPos = charactersWindow:getPosition()
  end

  charactersWindow:setPosition(charactersWindow.startPos)

  local camRecord = g_settings.getBoolean("recordSession", false)
  if widgetAlive(CharacterList.camRecordCheck) then
    CharacterList.camRecordCheck:setOn(camRecord)
  end
end

function CharacterList.hide(showLogin)
  showLogin = showLogin or false
  if widgetAlive(charactersWindow) then
    charactersWindow:hide()
  end
  g_client.setInputLockWidget(nil)

  if showLogin and EnterGame and not g_game.isOnline() then
    if modules.client_background and modules.client_background.toggleLogo then
      modules.client_background.toggleLogo(true)
    end
    EnterGame.show()
    g_game.invokeOnLogout()
  end
end

function CharacterList.showAgain()
  if not G.characters then
    CharacterList.hide(true)
    return
  end

  LoginEvent.loginTries = 0
  if widgetAlive(charactersWindow) and widgetAlive(characterList) and characterList:hasChildren() then
    CharacterList.show()
    charactersWindow.static = not g_game.isOnline()
    if not charactersWindow.startPos then
      charactersWindow.startPos = charactersWindow:getPosition()
    end
  
    charactersWindow:setPosition(charactersWindow.startPos)
  end
end

function CharacterList.isVisible()
  if widgetAlive(charactersWindow) and charactersWindow:isVisible() then
    return true
  end
  return false
end

function CharacterList.doLogin()
  if not widgetAlive(characterList) then
    return
  end

  local selected = characterList:getFocusedChild()
  if selected then
    local charInfo = { worldHost = selected.worldHost,
                       worldPort = selected.worldPort,
                       worldName = selected.gameworldName,
                       vocation = selected.vocationName,
                       characterName = selected.characterName, }
    CharacterList.hide()
    g_client.setInputLockWidget(nil)
    LoginEvent:setNewEvent(charInfo)
  else
    displayErrorBox(tr('Error'), tr('You must select a character to login!'))
  end
end

function CharacterList.doLoginExtended(options)
  if options then
    local charInfo = { worldHost = options.worldHost,
                       worldPort = options.worldPort,
                       worldName = options.worldName,
                       vocation = options.vocation,
                       characterName = options.characterName, }


    CharacterList.hide()
    g_client.setInputLockWidget(nil)
    LoginEvent:setNewEvent(charInfo)
  else
    displayErrorBox(tr('Error'), tr('You must select a character to login!'))
  end
end

function CharacterList.destroyLoadBox()
  consoleln("[+] CharacterList.destroyLoadBox()")
  LoginEvent:destroyLoadBox()

  if g_game.isOnline() then
    if waitingWindow then
      waitingWindow:destroy()
      waitingWindow = nil
    end
    if errorBox then
      errorBox:destroy()
      errorBox = nil
    end

    LoginEvent.loginTries = 0

    CharacterList.waiting = false
    CharacterList.scheduleTime = 5
  end
end

function CharacterList.cancelWait()
  consoleln("[+] CharacterList.cancelWait()")
  if waitingWindow then
    waitingWindow:destroy()
    waitingWindow = nil
  end

  if updateWaitEvent then
    removeEvent(updateWaitEvent)
    updateWaitEvent = nil
  end

  LoginEvent:reset()

  if autoReconnectEvent then
    removeEvent(autoReconnectEvent)
    autoReconnectEvent = nil
  end

  if resendWaitEvent then
    removeEvent(resendWaitEvent)
    resendWaitEvent = nil
  end

  if errorBox then
    errorBox:destroy()
    errorBox = nil
  end

  CharacterList.scheduleTime = 5
  CharacterList.waiting = false
  CharacterList.destroyLoadBox()
  CharacterList.showAgain()
  if widgetAlive(charactersWindow) then
    charactersWindow:recursiveFocus(2)
  end
end

function onUpdateOnStates(self)
  if not self:isFocused() then
    return
  end

  self:setBackgroundColor("#585858")
  local children = self:getChildren()
  for i=1,#children do
    children[i]:setColor("#f4f4f4")
    if children[i]:getId() == "pin" then
      children[i]:setVisible(true)
      if Options.getOption("characterSelectionShowOutfits") then
        children[i]:setChecked(isCharacterPinned(children[3]:getText()))
      else
        children[i]:setChecked(isCharacterPinned(children[2]:getText()))
      end
    end
  end

  if lastWidget and lastWidget ~= self then
    lastWidget:setBackgroundColor(lastWidget.realColor)
    if lastWidget.pin then
      lastWidget.pin:setVisible(false)
    end
    if lastWidget.name then
      lastWidget.name:setColor("#c0c0c0")
    end
    if lastWidget.level then
      lastWidget.level:setColor("#c0c0c0")
    end
    if lastWidget.vocation then
      lastWidget.vocation:setColor("#c0c0c0")
    end
    if lastWidget.worldName then
      lastWidget.worldName:setColor("#c0c0c0")
    end
  end

  lastWidget = self
end

function onPinCharacter(self)
  self:setChecked(not self:isChecked())
  local focusedOption = characterList:getFocusedChild()
  if not focusedOption then
    return
  end

  Options.managePinnedCharacters(focusedOption.name:getText(), self:isChecked())
  onReorderCharacterList()
end

function isCharacterPinned(name)
  return table.contains(Options.pinnedCharacters, name)
end

function setupSortButton(button, sortType, sortIndex)
  if lastSortButton and lastSortButton ~= button then
    lastSortButton:setChecked(false)
    lastSortButton:setOn(false)
  end

  button:setOn(true)
  if lastSortButton == button then
    button:setChecked(not button:isChecked(), true)
  end

  lastSortButton = button
  Options.setOption("characterSelectionSortColumn", sortIndex)
  Options.setOption("characterSelectionSortAscendingOrder", button:isChecked())

  if sortType ~= "status" then
    onReorderCharacterList()
  end
end

function onReorderCharacterList()
  if not G.characters or not widgetAlive(charactersWindow) or
      not widgetAlive(characterList) or not widgetAlive(panelSort) then
    return
  end

  local sortIndex = Options.getOption("characterSelectionSortColumn") or 1
  local sortAscend = Options.getOption("characterSelectionSortAscendingOrder")
  local showOutfit = Options.getOption("characterSelectionShowOutfits")
  if charactersWindow.characterTable then
    if not showOutfit then
      charactersWindow.characterTable.characterSort:setTextOffset("-206 0")
    else
      charactersWindow.characterTable.characterSort:setTextOffset("-73 0")
    end
  end

  if lastWidget and lastWidget.pin then
    lastWidget:setBackgroundColor(lastWidget.realColor)
    lastWidget.pin:setVisible(false)
    lastWidget.name:setColor("#c0c0c0")
    lastWidget.level:setColor("#c0c0c0")
    lastWidget.vocation:setColor("#c0c0c0")
    lastWidget.worldName:setColor("#c0c0c0")
  end

  lastWidget = nil
  local characters = table.copy(G.characters)
  local focusLabel = nil
  characterList:destroyChildren()

  if sortIndex == 1 then
    panelSort.characterSort:setOn(true)
    lastSortButton = panelSort.characterSort
    table.sort(characters, function(a, b)
      local aPinned = isCharacterPinned(a.name)
      local bPinned = isCharacterPinned(b.name)
      if aPinned and not bPinned then
          return true
      elseif bPinned and not aPinned then
          return false
      else
          if sortAscend then
              return a.name > b.name
          else
              return a.name < b.name
          end
      end
    end)
  end

  if sortIndex == 2 then
    panelSort.statusSort:setOn(true)
    lastSortButton = panelSort.statusSort
    table.sort(characters, function(a, b)
      local aPinned = isCharacterPinned(a.name)
      local bPinned = isCharacterPinned(b.name)
      if aPinned and not bPinned then
          return true
      elseif bPinned and not aPinned then
          return false
      end
    end)
  end

  if sortIndex == 3 then
    panelSort.levelSort:setOn(true)
    lastSortButton = panelSort.levelSort
    table.sort(characters, function(a, b)
      local aPinned = isCharacterPinned(a.name)
      local bPinned = isCharacterPinned(b.name)
      if aPinned and not bPinned then
          return true
      elseif bPinned and not aPinned then
          return false
      else
          return sortAscend and a.level > b.level or not sortAscend and a.level < b.level
      end
    end)
  end

  if sortIndex == 4 then
    panelSort.vocationSort:setOn(true)
    lastSortButton = panelSort.vocationSort
    table.sort(characters, function(a, b)
      local aPinned = isCharacterPinned(a.name)
      local bPinned = isCharacterPinned(b.name)
      if aPinned and not bPinned then
          return true
      elseif bPinned and not aPinned then
          return false
      else
          return sortAscend and a.vocation > b.vocation or not sortAscend and a.vocation < b.vocation
      end
    end)
  end

  if sortIndex == 5 then
    panelSort.worldSort:setOn(true)
    lastSortButton = panelSort.worldSort
    table.sort(characters, function(a, b)
      local aPinned = isCharacterPinned(a.name)
      local bPinned = isCharacterPinned(b.name)
      local checked = lastSortButton:isChecked()
      if aPinned and not bPinned then
          return true
      elseif bPinned and not aPinned then
          return false
      else
          return sortAscend and a.worldName > b.worldName or not sortAscend and a.worldName < b.worldName
      end
    end)
  end

  for i, characterInfo in ipairs(characters) do
    local widget = g_ui.createWidget(showOutfit and 'CharacterWidgetOn' or 'CharacterWidgetOff', characterList)
    widget.realColor = (i % 2 == 0 and "#414141" or "#484848")
    widget:setBackgroundColor(widget.realColor)

    for key,value in pairs(characterInfo) do
      local subWidget = widget:getChildById(key)
      if key == 'name' then
        widget:setId("ui_"..value)
      end

      if key == 'mainCharacter' then
        widget.main:setVisible(value)
      end

      if key == 'dailyRewardState' then
        local source = value and "dailyreward_collected" or "dailyreward_notcollected"
        widget.statusDailyReward:setImageSource("/images/game/entergame/" .. source)
      end

      if subWidget then
        if key == 'outfit' and showOutfit then -- it's an exception
          subWidget:setOutfit(value)
        else
          local text = value

          local pvpType = PvPTypes[characterInfo.pvpType] or PvPTypes[0] or ""
          if key == 'worldName' and worldIsComingSoon(characterInfo.worldId) then
            subWidget:setImageShader("text_coming")
            pvpType = "Coming Soon"
          end

          if subWidget.baseText and subWidget.baseTranslate then
            text = tr(subWidget.baseText, text)
          elseif subWidget.baseText then
            text = string.format(subWidget.baseText, text, pvpType)
          end
          subWidget:setText(text)
        end
      end
    end

    -- these are used by login
    widget.characterName = characterInfo.name
    widget.gameworldName = characterInfo.worldName
    widget.worldHost = characterInfo.worldHost or characterInfo.worldIp
    widget.worldPort = characterInfo.worldPort
    widget.vocationName = characterInfo.vocation

    connect(widget, { onDoubleClick = function () CharacterList.doLogin() return true end } )

    if i == 1 or (g_settings.get('last-used-character') == widget.characterName and g_settings.get('last-used-world') == widget.worldName) then
      focusLabel = widget
    end
  end

  if focusLabel then
    characterList:focusChild(focusLabel, KeyboardFocusReason, true)
    local list = characterList
    local label = focusLabel
    addEvent(function()
      if widgetAlive(list) and widgetAlive(label) then
        list:ensureChildVisible(label)
      end
    end)
  end
end

function onShowOutfits(button, isChecked)
  Options.setOption("characterSelectionShowOutfits", isChecked)
  onReorderCharacterList()
end

function onRecordSession(widget, isChecked)
  g_settings.set("recordSession", isChecked)
end

function saveAutoReconnect(characterName, setting)
  local settings = g_settings.getNode('autoReconnectSettings') or {}
  settings[characterName] = setting
  g_settings.setNode('autoReconnectSettings', settings)
end

function getAutoReconnect(characterName)
  local settings = g_settings.getNode('autoReconnectSettings') or {}
  return settings[characterName] or false
end

function GetCharacterInfoByWorldID(worldID)
  if not G.characters then
    return nil
  end

  for i, characterInfo in ipairs(G.characters) do
    if characterInfo.worldId == worldID then
      local info = getWorldInfo(characterInfo.worldId)
      return { worldHost = info.address,
            worldPort = characterInfo.worldPort,
            worldName = info.name,
            vocation = characterInfo.vocation,
            characterName = characterInfo.name, }
    end
  end

  return nil
end

function SetLoginOption(worldID)
  local characterInfo = GetCharacterInfoByWorldID(worldID)
  if not characterInfo then
    return
  end

  CharacterList.doLoginExtended(characterInfo)
end
