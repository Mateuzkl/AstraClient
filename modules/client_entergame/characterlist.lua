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
local errorBox
local waitingWindow
local updateWaitEvent
local resendWaitEvent
local autoReconnectEvent
local lastWidget
local lastLogout = 0
local suppressCheckCallbacks = false

local SORT_COLUMN = {
  Character = 1,
  Status = 2,
  Level = 3,
  Vocation = 4,
  World = 5
}
local SORT_BUTTON_IDS = {
  [SORT_COLUMN.Character] = 'characterSort',
  [SORT_COLUMN.Status] = 'statusSort',
  [SORT_COLUMN.Level] = 'levelSort',
  [SORT_COLUMN.Vocation] = 'vocationSort',
  [SORT_COLUMN.World] = 'worldSort'
}
local SORT_COLUMN_SETTING = 'characterlist-sort-column'
local SORT_ASCENDING_SETTING = 'characterlist-sort-ascending'
local PINNED_CHARACTERS_SETTING = 'characterlist-pinned-characters'

local function setCheckedWithoutCallback(widget, checked)
  if not widget then return end
  suppressCheckCallbacks = true
  widget:setChecked(checked)
  suppressCheckCallbacks = false
end

local function getSortColumn()
  local sortColumn = g_settings.getNumber(SORT_COLUMN_SETTING, SORT_COLUMN.Character)
  if sortColumn < SORT_COLUMN.Character or sortColumn > SORT_COLUMN.World then
    sortColumn = SORT_COLUMN.Character
  end
  return sortColumn
end

local function getSortAscending()
  return g_settings.getBoolean(SORT_ASCENDING_SETTING, true)
end

local function getCharacterPinKey(characterName, worldName)
  local name = tostring(characterName or '')
  if name == '' then return nil end
  return name .. '|' .. tostring(worldName or '')
end

local function getPinnedCharacters()
  local raw = g_settings.getNode(PINNED_CHARACTERS_SETTING)
  local pinned = {}
  if type(raw) == 'table' then
    for key, value in pairs(raw) do
      if type(key) == 'number' and type(value) == 'string' and value ~= '' then
        pinned[value] = true
      elseif type(key) == 'string' and
        (value == true or (type(value) == 'number' and value ~= 0) or
         (type(value) == 'string' and (value:lower() == 'true' or value == '1'))) then
        pinned[key] = true
      end
    end
  end

  return pinned
end

local function setPinnedCharacters(pinned)
  g_settings.setNode(PINNED_CHARACTERS_SETTING, pinned)
end

local function isCharacterPinned(characterName, worldName, pinnedLookup)
  local pinKey = getCharacterPinKey(characterName, worldName)
  if not pinKey then return false end
  local pinned = pinnedLookup or getPinnedCharacters()
  return pinned[pinKey] == true or pinned[tostring(characterName)] == true
end

local function setCharacterPinned(characterName, worldName, isPinned)
  local pinKey = getCharacterPinKey(characterName, worldName)
  if not pinKey then return end
  local pinned = getPinnedCharacters()
  pinned[pinKey] = isPinned and true or nil
  pinned[tostring(characterName)] = nil
  setPinnedCharacters(pinned)
end

local function getCharacterStatusValue(character)
  local main = character.mainCharacter and 0 or 1
  local hidden = character.hidden and 0 or 1
  local dailyReward = character.dailyRewardState and 0 or 1
  return main * 100 + hidden * 10 + dailyReward
end

local function toLowerText(value)
  return string.lower(tostring(value or ''))
end

local function toNumberValue(value)
  if type(value) == 'number' then
    return value
  end

  local numericValue = tonumber(value)
  if numericValue then
    return numericValue
  end

  if type(value) == 'string' then
    numericValue = tonumber((value:gsub('[^%d%-%.]', '')))
    if numericValue then
      return numericValue
    end
  end

  return 0
end

local function compareCharacters(a, b, sortColumn, sortAscending, pinnedLookup)
  local prioritizePinned = sortColumn ~= SORT_COLUMN.Level
  if prioritizePinned then
    local aPinned = isCharacterPinned(a.name, a.worldName, pinnedLookup)
    local bPinned = isCharacterPinned(b.name, b.worldName, pinnedLookup)
    if aPinned ~= bPinned then return aPinned end
  end

  local aValue, bValue
  if sortColumn == SORT_COLUMN.Character then
    aValue, bValue = toLowerText(a.name), toLowerText(b.name)
  elseif sortColumn == SORT_COLUMN.Status then
    aValue, bValue = getCharacterStatusValue(a), getCharacterStatusValue(b)
  elseif sortColumn == SORT_COLUMN.Level then
    aValue, bValue = toNumberValue(a.level), toNumberValue(b.level)
  elseif sortColumn == SORT_COLUMN.Vocation then
    aValue, bValue = toLowerText(a.vocation), toLowerText(b.vocation)
  else
    aValue, bValue = toLowerText(a.worldName), toLowerText(b.worldName)
  end

  if aValue == bValue then
    aValue, bValue = toLowerText(a.name), toLowerText(b.name)
    if aValue == bValue then
      aValue, bValue = toLowerText(a.worldName), toLowerText(b.worldName)
    end
  end
  if sortAscending then return aValue < bValue end
  return aValue > bValue
end

local function updateSortButtons()
  if not panelSort then return end
  local sortColumn = getSortColumn()
  local sortAscending = getSortAscending()
  for column = SORT_COLUMN.Character, SORT_COLUMN.World do
    local button = panelSort:getChildById(SORT_BUTTON_IDS[column])
    if button then
      local selected = column == sortColumn
      button:setOn(selected)
      button:setChecked(selected and sortAscending or false, true)
    end
  end
end

local function buildCharacters(pinnedLookup)
  local characters = {}
  for _, character in ipairs(G.characters or {}) do
    characters[#characters + 1] = character
  end
  local sortColumn = getSortColumn()
  local sortAscending = getSortAscending()
  table.sort(characters, function(a, b)
    return compareCharacters(a, b, sortColumn, sortAscending, pinnedLookup)
  end)
  return characters
end


local function isRecentManualLogout()
  return lastLogout > 0 and lastLogout + 2000 > g_clock.millis()
end

CharacterList.camRecordCheck = nil

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

    if charactersWindow then
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
  if isRecentManualLogout() then
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

function onGameEnd()
  local background = modules.client_background
  if background and background.isReturningToCastList and background.isReturningToCastList() then
    return
  end
  CharacterList.showAgain()
end

function onLogout()
  lastLogout = g_clock.millis()
  if autoReconnectEvent then
    removeEvent(autoReconnectEvent)
    autoReconnectEvent = nil
  end

  local characterName = g_game.getCharacterName()
  if characterName then
    saveAutoReconnect(characterName, g_settings.getBoolean('autoReconnect', false))
  end
end

function scheduleAutoReconnect()
  if isRecentManualLogout() then
    return
  end

  if autoReconnectEvent then
    removeEvent(autoReconnectEvent)
  end
  autoReconnectEvent = scheduleEvent(executeAutoReconnect, 2500)
end

function executeAutoReconnect()
  -- disconnect por recorder
  if not characterList then
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
  connect(g_game, { onGameEnd = onGameEnd })
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
  disconnect(g_game, { onGameEnd = onGameEnd })
  disconnect(g_game, { onLogout = onLogout })
  disconnect(g_game, { onSessionEnd = onGameSessionEnd })

  if charactersWindow then
    characterList = nil
    panelSort = nil
    g_client.setInputLockWidget(nil)
    charactersWindow:destroy()
    charactersWindow = nil
  end

  if g_game.isLogging() then
    LoginEvent:cancelLogin()
  else
    LoginEvent:destroyLoadBox()
  end

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

  LoginEvent:reset()

  if lastWidget then
    lastWidget = nil
  end

  CharacterList = nil
end

function CharacterList.create(characters, account, otui)
  if not otui then otui = 'characterlist' end
  if charactersWindow then
    charactersWindow:destroy()
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
  if showOutfit == nil then
    showOutfit = true
  end
  if not showOutfit then
    charactersWindow.characterTable.characterSort:setTextOffset("-206 0")
  else
    charactersWindow.characterTable.characterSort:setTextOffset("-73 0")
  end

  local outfitCheckBox = charactersWindow:recursiveGetChildById('checkBoxOutfit')
  setCheckedWithoutCallback(outfitCheckBox, showOutfit)

  characterList.onChildFocusChange = function(self, focusChild, oldFocusChild)
    if focusChild then self:ensureChildVisible(focusChild) end
    if autoReconnectEvent then
      removeEvent(autoReconnectEvent)
      autoReconnectEvent = nil
    end
  end
  CharacterList.rebuildCharactersList()

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
  if charactersWindow then
    characterList = nil
    charactersWindow:destroy()
    charactersWindow = nil
    panelSort = nil
  end
end

function CharacterList.show()
  if not G.characters then
    consoleln("[!] CharacterList.show() - No characters found")
    return
  end

  if LoginEvent:getLoadBox() or errorBox or not charactersWindow then return end

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
  CharacterList.camRecordCheck:setOn(camRecord)
end

function CharacterList.hide(showLogin)

  showLogin = showLogin or false
  charactersWindow:hide()
  g_client.setInputLockWidget(nil)

  if showLogin and EnterGame and not g_game.isOnline() then
    modules.client_background.toggleLogo(true)
    EnterGame.show()
    g_game.invokeOnLogout()
  end
end

function CharacterList.showAgain()
  if not G.characters then
    CharacterList.hide(true)
    EnterGame.show()
    return
  end

  LoginEvent.loginTries = 0
  if characterList and characterList:hasChildren() then
    CharacterList.show()
    charactersWindow.static = not g_game.isOnline()
    if not charactersWindow.startPos then
      charactersWindow.startPos = charactersWindow:getPosition()
    end
  
    charactersWindow:setPosition(charactersWindow.startPos)
  end
end

function CharacterList.isVisible()
  if charactersWindow and charactersWindow:isVisible() then
    return true
  end
  return false
end

function CharacterList.doLogin()

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
  charactersWindow:recursiveFocus(2)
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
    local worldLabel = lastWidget:getChildById('worldName')
    if worldLabel then
      worldLabel:setColor("#c0c0c0")
    end
  end

  lastWidget = self
end

function onPinCharacter(widget, isChecked)
  if suppressCheckCallbacks then return end
  local row = widget and widget:getParent()
  if not row or not row.characterName then return end
  setCharacterPinned(row.characterName, row.worldName, isChecked)
  CharacterList.rebuildCharactersList(row.characterName, row.worldName)
end

function onSortButtonClick(button, columnIndex)
  if not SORT_BUTTON_IDS[columnIndex] then return end
  local sortColumn = getSortColumn()
  local sortAscending = getSortAscending()
  if sortColumn == columnIndex then
    sortAscending = not sortAscending
  else
    sortColumn = columnIndex
    sortAscending = true
  end
  g_settings.set(SORT_COLUMN_SETTING, sortColumn)
  g_settings.set(SORT_ASCENDING_SETTING, sortAscending)
  CharacterList.rebuildCharactersList()
end

function CharacterList.rebuildCharactersList(focusNameOverride, focusWorldOverride)
  if not characterList then return end

  local focused = characterList:getFocusedChild()
  local focusName = focusNameOverride or (focused and focused.characterName) or g_settings.get('last-used-character')
  local focusWorld = focusWorldOverride or (focused and focused.worldName) or g_settings.get('last-used-world')
  local pinnedLookup = getPinnedCharacters()
  local characters = buildCharacters(pinnedLookup)
  local showOutfit = Options.getOption('characterSelectionShowOutfits') ~= false
  if charactersWindow.characterTable then
    charactersWindow.characterTable.characterSort:setTextOffset(showOutfit and '-73 0' or '-206 0')
  end

  lastWidget = nil
  characterList:destroyChildren()
  local focusLabel
  local firstWidget
  for i, characterInfo in ipairs(characters) do
    local widget = g_ui.createWidget(showOutfit and 'CharacterWidgetOn' or 'CharacterWidgetOff', characterList)
    widget.realColor = i % 2 == 0 and '#414141' or '#484848'
    widget:setBackgroundColor(widget.realColor)

    local pvpType = PvPTypes[characterInfo.pvpType] or PvPTypes[0] or ''
    local comingSoon = worldIsComingSoon(characterInfo.worldId)
    for key, value in pairs(characterInfo) do
      local subWidget = widget:getChildById(key)
      if key == 'name' then
        widget:setId('ui_' .. value)
      elseif key == 'mainCharacter' then
        widget.main:setVisible(value)
      elseif key == 'dailyRewardState' then
        local source = value and 'dailyreward_collected' or 'dailyreward_notcollected'
        widget.statusDailyReward:setImageSource('/images/game/entergame/' .. source)
      end

      if subWidget then
        if key == 'outfit' and showOutfit then
          subWidget:setOutfit(value)
        else
          local text = value
          local worldPvpType = pvpType
          if key == 'worldName' and comingSoon then
            subWidget:setImageShader('text_coming')
            worldPvpType = 'Coming Soon'
          end
          if subWidget.baseText and subWidget.baseTranslate then
            text = tr(subWidget.baseText, text)
          elseif subWidget.baseText then
            text = string.format(subWidget.baseText, text, worldPvpType)
          end
          subWidget:setText(text)
        end
      end
    end

    -- Keep both the new row identity and Astra's login fields.
    widget.characterName = characterInfo.name
    widget.worldName = characterInfo.worldName
    widget.gameworldName = characterInfo.worldName
    widget.worldHost = characterInfo.worldHost or characterInfo.worldIp
    widget.worldPort = characterInfo.worldPort
    widget.vocationName = characterInfo.vocation
    local pin = widget:getChildById('pin')
    setCheckedWithoutCallback(pin, isCharacterPinned(widget.characterName, widget.worldName, pinnedLookup))

    connect(widget, { onDoubleClick = function() CharacterList.doLogin() return true end })
    if not firstWidget then firstWidget = widget end
    if focusName == widget.characterName and focusWorld == widget.worldName then
      focusLabel = widget
    end
  end

  focusLabel = focusLabel or firstWidget
  if focusLabel then
    characterList:focusChild(focusLabel, KeyboardFocusReason, true)
    characterList:ensureChildVisible(focusLabel)
    local currentList = characterList
    local visibleName, visibleWorld = focusLabel.characterName, focusLabel.worldName
    addEvent(function()
      if characterList ~= currentList then return end
      local selected = currentList:getFocusedChild()
      if selected and selected.characterName == visibleName and selected.worldName == visibleWorld then
        currentList:ensureChildVisible(selected)
      end
    end)
  end
  updateSortButtons()
end

function onShowOutfits(button, isChecked)
  if suppressCheckCallbacks then return end
  Options.setOption("characterSelectionShowOutfits", isChecked)
  CharacterList.rebuildCharactersList()
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
