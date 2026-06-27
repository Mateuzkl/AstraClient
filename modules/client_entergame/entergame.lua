EnterGame = {}

-- private variables
local loadBox
local enterGame
local logpass
local twofactor
local protocolLogin

local customServerSelectorPanel
local serverSelectorPanel
local serverSelector
local clientVersionSelector
local serverHostTextEdit
local rememberPasswordBox
local rememberEmailBox
local protos = { "860", "1524" }

-- Google Configuration
local googleSession = ""
local awaitingGoogleAuth = false

local waitingForHttpResults = 0

local keybindChangeChar = KeyBind:getKeyBind("Misc.", "Change Character")

-- private functions
local function onProtocolError(protocol, message, errorCode)
  if errorCode then
    return EnterGame.onError(message)
  end
  return EnterGame.onLoginError(message)
end

local function onSessionKey(protocol, sessionKey)
  G.sessionKey = sessionKey
end

local function getServerInfoByName(name)
  if Servers then
    for _, server in pairs(Servers) do
      if name == server.name then
        return server
      end
    end
  end
  return nil
end

local function getDefaultClientVersion()
  local clientVersion = g_settings.get('client-version')
  if clientVersion and clientVersion ~= "" then
    return tostring(clientVersion)
  end
  return protos[1]
end

local function ensureThingsLoaded()
  local gameThings = modules.game_things
  if not gameThings or gameThings.isLoaded() then
    return nil
  end

  if G.clientVersion then
    g_game.setClientVersion(G.clientVersion)
    g_game.setStringVersion(GameInfo.strVersion)
    g_game.setProtocolVersion(g_game.getClientProtocolVersion(G.clientVersion))
  end

  if not gameThings.isLoading() and gameThings.load then
    gameThings.load()
  end

  if gameThings.isLoaded() then
    return nil
  end

  if gameThings.getLoadError then
    return gameThings.getLoadError()
  end

  if gameThings.getMissing860Message then
    return gameThings.getMissing860Message()
  end

  return tr('Please place the Tibia 8.60 asset files in data/things/860 (Tibia.dat and Tibia.spr).')
end

local function normalizeServers()
  if not Servers then return end

  local normalized = {}
  for name, server in pairs(Servers) do
    if type(server) == 'table' then
      if not server.googleLogin then
        server.googleLogin = server.clientServicesLink or server.loginLink
      end
      table.insert(normalized, server)
    elseif type(server) == 'string' then
      local params = server:split(':')
      table.insert(normalized, {
        name = tostring(name),
        loginLink = server,
        host = params[1],
        port = tonumber(params[2]) or 7171,
        version = tonumber(params[3]) or GameInfo.version,
        clientServicesLink = Services and Services.status or '',
        googleLogin = server,
        hintsJson = ''
      })
    end
  end
  Servers = normalized
end

local function getGoogleLoginUrl(server)
  if not server then
    return nil
  end

  local url = server.googleLogin or server.clientServicesLink or server.loginLink
  if type(url) ~= 'string' or url == '' then
    return nil
  end

  return url:gsub('/+$', '')
end

local function onCharacterList(protocol, characters, account, otui)
  if rememberEmailBox:isChecked() then
    local account = g_crypt.encrypt(G.account)
    g_settings.set('account', account)
  else
    g_settings.remove('account')
  end

  if rememberPasswordBox:isChecked() and (G.gtoken == '' or G.gtoken == nil) then
    local password = g_crypt.encrypt(G.password)
    g_settings.set('password', password)
  elseif not rememberPasswordBox:isChecked() then
    g_settings.remove('password')
  end

  for _, characterInfo in pairs(characters) do
    if characterInfo.previewState and characterInfo.previewState ~= PreviewState.Default then
      characterInfo.worldName = characterInfo.worldName .. ', Preview'
    end
  end

  if loadBox then
    loadBox:destroy()
    loadBox = nil
  end

  if twofactor then
    twofactor:destroy()
    twofactor = nil
  end

  modules.client_background.toggleLogo(false)
  if account.boostedCreature or account.boostedBoss then
    modules.client_background.updateBoostedInfo(account.boostedCreature, account.boostedBoss)
  end
  CharacterList.create(characters, account, otui)
  CharacterList.show()

  g_settings.save()
end

local function onUpdateNeeded(protocol, signature)
  return EnterGame.onError(tr('Your client needs updating, try redownloading it.'))
end

local function onProxyList(protocol, proxies)
  for _, proxy in ipairs(proxies) do
    g_proxy.addProxy(proxy["host"], proxy["port"], proxy["priority"])
  end
end

local function parseFeatures(features)
  for feature_id, value in pairs(features) do
    if value == "1" or value == "true" or value == true then
      g_game.enableFeature(feature_id)
    else
      g_game.disableFeature(feature_id)
    end
  end
end

local worlds = {}
function getWorldInfo(id)
  return worlds[id]
end

local function onTibia12HTTPResult(session, playdata)
  local characters = {}
  local account = {
    status = 0,
    subStatus = 0,
    premDays = 0,
  }

  if table.empty(playdata["characters"]) then
    return EnterGame.onError("No characters found on this account.")
  end

  if session["status"] ~= "active" then
    account.status = 1
  end
  if session["ispremium"] then
    account.subStatus = 1 -- premium
  end
  if session["premiumuntil"] > g_clock.seconds() then
    account.subStatus = math.floor((session["premiumuntil"] - g_clock.seconds()) / 86400)
  end

  if session["viptime"] and session["viptime"] > os.time() then
    account.premDays = math.max(0, math.ceil((session["viptime"] - os.time()) / 86400))
    account.subStatus = SubscriptionStatus.Premium -- premium
  else
    account.subStatus = SubscriptionStatus.Free
  end
  G.clientVersion = session["version"]

  onSessionKey(nil, session["sessionkey"])

  Worlds:loadWorlds(playdata)
  for _, world in pairs(playdata["worlds"]) do
    worlds[world.id] = {
      name = world.name,
      port = world.externalportunprotected or world.externalportprotected or world.externaladdress,
      address = world.externaladdressunprotected or world.externaladdressprotected or world.externalport,
      pvptype = world.pvptype
    }
  end

  for _, character in pairs(playdata["characters"]) do
    local world = worlds[character.worldid]
    if world then
      table.insert(characters, {
        name = character.name,
        worldName = world.name,
        worldIp = world.address,
        worldPort = world.port,
        pvpType = world.pvptype,
        mainCharacter = character.ismaincharacter,
        dailyRewardState = character.dailyrewardstate,
        level = character.level,
        vocation = character.vocation,
        worldId = character.worldid,
        outfit = {
          type = character.outfitid,
          head = character.headcolor,
          body = character.torsocolor,
          legs = character.legscolor,
          feet = character.detailcolor,
          addons = character.addonsflags,
        },
      })
    end
  end

  -- proxies
  if g_proxy then
    Proxies:loadProxyConfig(playdata)
  end

  g_game.setCustomProtocolVersion(0)
  g_game.chooseRsa(G.host)
  g_game.setCustomOs(-1)  -- disable
  if not g_game.getFeature(GameExtendedOpcode) then
    g_game.setCustomOs(5) -- set os to windows if opcodes are disabled
  end

  onCharacterList(nil, characters, account, nil)
end

local function onHTTPResult(data, err)
  if waitingForHttpResults == 0 then
    return
  end

  waitingForHttpResults = waitingForHttpResults - 1
  if err and waitingForHttpResults > 0 then
    return -- ignore, wait for other requests
  end

  if err then
    return EnterGame.onError(err)
  end
  waitingForHttpResults = 0

  if data['errorCode'] == 6 then
    if loadBox then
      loadBox:destroy()
      loadBox = nil
    end

    local doCancelLogin = function()
      g_client.setInputLockWidget(nil);
      twofactor:destroy();
      twofactor = nil;
      EnterGame.show()
    end

    local doEnterGame = function()
      g_client.setInputLockWidget(nil)
      EnterGame.doLogin(G.account, G.password, twofactor.tokenEnter:getText(), G.host, G.gtoken)
      twofactor:destroy()
      twofactor = nil
    end

    twofactor = g_ui.displayUI('twofactor')
    twofactor.onEscape = doCancelLogin
    twofactor.onEnter = doEnterGame
    twofactor.cancelButton.onClick = doCancelLogin
    twofactor.okButton.onClick = doEnterGame
    g_client.setInputLockWidget(twofactor)
    return
  end

  if data['error'] and data['error']:len() > 0 then
    return EnterGame.onLoginError(data['error'])
  elseif data['errorMessage'] and data['errorMessage']:len() > 0 then
    return EnterGame.onLoginError(data['errorMessage'])
  end

  if type(data["session"]) == "table" and type(data["playdata"]) == "table" then
    return onTibia12HTTPResult(data["session"], data["playdata"])
  end

  local characters = data["characters"]
  local account = data["account"]
  local session = data["session"]

  local version = data["version"]
  local things = data["things"]
  local customProtocol = data["customProtocol"]

  local features = data["features"]
  local settings = data["settings"]
  local rsa = data["rsa"]
  local proxies = data["proxies"]

  -- custom protocol
  g_game.setCustomProtocolVersion(0)
  if customProtocol ~= nil then
    customProtocol = tonumber(customProtocol)
    if customProtocol ~= nil and customProtocol > 0 then
      g_game.setCustomProtocolVersion(customProtocol)
    end
  end

  -- force player settings
  if settings ~= nil then
    for option, value in pairs(settings) do
      m_settings.setOption(option, value, true)
    end
  end

  -- version
  G.clientVersion = version
  g_game.setClientVersion(version)
  g_game.setStringVersion(GameInfo.strVersion)
  g_game.setProtocolVersion(g_game.getClientProtocolVersion(version))
  g_game.setCustomOs(-1) -- disable

  if rsa ~= nil then
    g_game.setRsa(rsa)
  end

  if features ~= nil then
    parseFeatures(features)
  end

  if session ~= nil and session:len() > 0 then
    onSessionKey(nil, session)
  end

  -- proxies
  if g_proxy then
    g_proxy.clear()
    if proxies then
      for i, proxy in ipairs(proxies) do
        g_proxy.addProxy(proxy["host"], tonumber(proxy["port"]), tonumber(proxy["priority"]))
      end
    end
  end

  onCharacterList(nil, characters, account, nil)
end


function EnterGame.addTestServer()
  local testServer = {
    name = "TesteArena",
    loginLink = "http://logints.astra.com.br:8083/login",
    clientServicesLink = "https://astra.net/clientservices/clientservices.php",
    hintsLink = "https://astra.net/hints.json",
    googleLogin = "https://astra.com.br/"
  }

  if not Servers then
    Servers = {}
  end

  if not getServerInfoByName(testServer.name) then
    table.insert(Servers, testServer)
    serverSelector:addOption(testServer.name)
    serverSelector:setCurrentOption(testServer.name, true)
    g_logger.info("Added Test server to server list via Lua.")
  end

  local testServer = {
    name = "TesteMulti",
    loginLink = "http://logints.astra.com.br:8071/login",
    clientServicesLink = "https://astra.net/clientservices/clientservices.php",
    hintsLink = "https://astra.net/hints.json",
    googleLogin = "https://astra.com.br/"
  }

  if not getServerInfoByName(testServer.name) then
    table.insert(Servers, testServer)
    serverSelector:addOption(testServer.name)
    serverSelector:setCurrentOption(testServer.name, true)
    g_logger.info("Added Test server to server list via Lua.")
  end
end

-- public functions
function EnterGame.init()
  if USE_NEW_ENERGAME then return end
  enterGame = g_ui.displayUI('entergame')
  if LOGPASS ~= nil then
    logpass = g_ui.loadUI('logpass', enterGame:getParent())
  end

  keybindChangeChar:active(gameRootPanel)

  serverSelectorPanel = enterGame:getChildById('serverSelectorPanel')
  customServerSelectorPanel = enterGame:getChildById('customServerSelectorPanel')

  serverSelector = serverSelectorPanel:getChildById('serverSelector')
  rememberEmailBox = enterGame:getChildById('rememberEmailBox')
  rememberPasswordBox = enterGame:getChildById('rememberPasswordBox')
  serverHostTextEdit = customServerSelectorPanel:getChildById('serverHostTextEdit')
  clientVersionSelector = customServerSelectorPanel:getChildById('clientVersionSelector')

  normalizeServers()

  if Servers ~= nil then
    for i, server in pairs(Servers) do
      serverSelector:addOption(server.name)
    end
  end
  if serverSelector:getOptionsCount() == 0 or ALLOW_CUSTOM_SERVERS then
    serverSelector:addOption(tr("Another"))
  end
  for i, proto in pairs(protos) do
    clientVersionSelector:addOption(proto)
  end

  local account = g_crypt.decrypt(g_settings.get('account'))
  local password = g_crypt.decrypt(g_settings.get('password'))
  local hiddenEmail = g_settings.get('hiddenEmail')
  local server = g_settings.get('server')
  local host = g_settings.get('host')

  if serverSelector:isOption(server) then
    local serverInfo = getServerInfoByName(server)
    serverSelector:setCurrentOption(server, false)
    if Servers == nil then
      serverHostTextEdit:setText(host)
    end
    clientVersionSelector:setOption(serverInfo and serverInfo.version and tostring(serverInfo.version) or getDefaultClientVersion())
  else
    server = ""
    host = ""
  end

  g_keyboard.bindKeyDown("Ctrl+Alt+T", EnterGame.addTestServer, enterGame)

  enterGame:getChildById('accountPasswordTextEdit'):setText(password)

  local accountWidget = enterGame:getChildById('accountNameTextEdit')
  accountWidget:setText(account)
  accountWidget:setCursorPos(#account)
  rememberEmailBox:setChecked(#account > 0)

  rememberPasswordBox:setChecked(#password > 0)
  if hiddenEmail == "1" then
    enterGame.accountNameTextEdit:setTextHidden(true)
  end

  if g_game.isOnline() then
    return EnterGame.hide()
  end

  scheduleEvent(function()
    EnterGame.show()
  end, 100)

  connect(g_game, {
    onGameStart = onGameStart,
    onGameEnd = onGameEnd
  })
end

function onGameStart(...)
  local benchmark = g_clock.millis()
  if g_game.isOnline() then
    g_keyboard.bindKeyDown("Alt+F4", function() m_interface.tryExit() end, gameRootPanel)
    return EnterGame.hide()
  end
  consoleln("EnterGame loaded in " .. (g_clock.millis() - benchmark) / 1000 .. " seconds.")
end

function onGameEnd(...)
  g_keyboard.unbindKeyDown("Alt+F4", nil, gameRootPanel)
end

function EnterGame.terminate()
  if not enterGame then return end

  keybindChangeChar:deactive(gameRootPanel)
  g_keyboard.unbindKeyDown("Ctrl+Alt+T", enterGame)

  if logpass then
    logpass:destroy()
    logpass = nil
  end

  enterGame:destroy()
  if loadBox then
    loadBox:destroy()
    loadBox = nil
  end
  if twofactor then
    twofactor:destroy()
    twofactor = nil
  end
  if protocolLogin then
    protocolLogin:cancelLogin()
    protocolLogin = nil
  end
  EnterGame = nil

  disconnect(g_game, {
    onGameStart = onGameStart,
    onGameEnd = onGameEnd
  })
end

function EnterGame.show()
  G.characters = nil
  if not enterGame then return end
  enterGame:show()
  enterGame:raise()
  enterGame:focus()
  enterGame:getChildById('accountNameTextEdit'):focus()
  if logpass then
    logpass:show()
    logpass:raise()
    logpass:focus()
  end
end

function EnterGame.hide()
  if not enterGame then return end
  if not rememberPasswordBox:isChecked() then
    enterGame:getChildById('accountPasswordTextEdit'):clearText()
    g_settings.remove('password')
  end
  enterGame:hide()
  if logpass then
    logpass:hide()
    if modules.logpass then
      modules.logpass:hide()
    end
  end
end

function EnterGame.openWindow()
  if g_game.isOnline() then
    CharacterList.show()
  elseif not g_game.isLogging() and not CharacterList.isVisible() then
    EnterGame.show()
  end
end

function EnterGame.clearAccountFields()
  if not rememberEmailBox:isChecked() then
    enterGame:getChildById('accountNameTextEdit'):clearText()
    enterGame:getChildById('accountNameTextEdit'):focus()
    g_settings.remove('account')
  end
  if not rememberPasswordBox:isChecked() then
    enterGame:getChildById('accountPasswordTextEdit'):clearText()
    g_settings.remove('password')
  end
  enterGame:getChildById('accountTokenTextEdit'):clearText()
  enterGame:getChildById('accountNameTextEdit'):focus()
end

function EnterGame.onServerChange()
  serverName = serverSelector:getText()
  local serverInfo = Servers and getServerInfoByName(serverName) or nil
  if serverInfo and serverInfo.name == tr("Another") then
    if not customServerSelectorPanel:isOn() then
      serverHostTextEdit:setText("")
      customServerSelectorPanel:setOn(true)
    end
  elseif serverInfo then
    customServerSelectorPanel:setOn(false)
  end
  if serverInfo then
    serverHostTextEdit:setText(serverInfo.name)
    clientVersionSelector:setOption(serverInfo.version and tostring(serverInfo.version) or getDefaultClientVersion())
    modules.client_background.updateStatus(serverInfo)
  end
end

function EnterGame.doLogin(account, password, token, host, gtoken)
  if g_game.isOnline() then
    local errorBox = displayErrorBox(tr('Login Error'), tr('Cannot login while already in game.'))
    connect(errorBox, { onOk = EnterGame.show })
    return
  end


  G.account = account or enterGame:getChildById('accountNameTextEdit'):getText()
  G.password = password or enterGame:getChildById('accountPasswordTextEdit'):getText()
  G.authenticatorToken = token or enterGame:getChildById('accountTokenTextEdit'):getText()
  G.gtoken = gtoken or ""
  G.stayLogged = true
  G.server = serverSelector:getText():trim()
  local chosenServer = getServerInfoByName(G.server)
  G.host = chosenServer and chosenServer.loginLink or serverHostTextEdit:getText()
  G.clientVersion = chosenServer and chosenServer.version or tonumber(clientVersionSelector:getText())

  if G.password == "" then
    return
  end

  local thingsError = ensureThingsLoaded()
  if thingsError then
    return EnterGame.onError(thingsError)
  end

  if not rememberEmailBox:isChecked() then
    g_settings.set('account', G.account)
  end

  if rememberPasswordBox:isChecked() and G.gtoken == '' then
    g_settings.set('password', g_crypt.encrypt(G.password))
  end

  g_settings.set('host', G.host)
  g_settings.set('server', G.server)
  g_settings.set('client-version', G.clientVersion)
  g_settings.set('hiddenEmail', enterGame.accountNameTextEdit:isTextHidden() and 1 or 0)

  g_settings.save()

  local server_params = G.host:split(":")
  if G.host:lower():find("http") ~= nil then
    if #server_params >= 4 then
      G.host = server_params[1] .. ":" .. server_params[2] .. ":" .. server_params[3]
      G.clientVersion = tonumber(server_params[4])
    elseif #server_params >= 3 then
      if tostring(tonumber(server_params[3])) == server_params[3] then
        G.host = server_params[1] .. ":" .. server_params[2]
        G.clientVersion = tonumber(server_params[3])
      end
    end
    return EnterGame.doLoginHttp()
  end

  local server_ip = server_params[1]
  local server_port = 7171
  if #server_params >= 2 then
    server_port = tonumber(server_params[2])
  end

  if #server_params >= 3 then
    G.clientVersion = tonumber(server_params[3])
  end
  if type(server_ip) ~= 'string' or server_ip:len() <= 3 or not server_port or not G.clientVersion then
    return EnterGame.onError("Invalid server, it should be in format IP:PORT or it should be http url to login script")
  end

  protocolLogin = ProtocolLogin.create()
  protocolLogin.onLoginError = onProtocolError
  protocolLogin.onSessionKey = onSessionKey
  protocolLogin.onCharacterList = onCharacterList
  protocolLogin.onUpdateNeeded = onUpdateNeeded
  protocolLogin.onProxyList = onProxyList

  EnterGame.hide()
  loadBox = displayCancelBox(tr('Please wait'), tr('Connecting to login server...'))
  connect(loadBox, {
    onCancel = function(msgbox)
      loadBox = nil
      protocolLogin:cancelLogin()
      EnterGame.show()
    end
  })

  if G.clientVersion == 1000 then -- some people don't understand that Astra 10 uses 1100 protocol
    G.clientVersion = 1100
  end
  -- if you have custom rsa or protocol edit it here
  g_game.setClientVersion(G.clientVersion)
  g_game.setStringVersion(GameInfo.strVersion)
  g_game.setProtocolVersion(g_game.getClientProtocolVersion(G.clientVersion))
  g_game.setCustomProtocolVersion(0)
  g_game.setCustomOs(-1) -- disable
  g_game.chooseRsa(G.host)
  if #server_params <= 3 and not g_game.getFeature(GameExtendedOpcode) then
    g_game.setCustomOs(2) -- set os to windows if opcodes are disabled
  end

  -- extra features from init.lua
  for i = 4, #server_params do
    g_game.enableFeature(tonumber(server_params[i]))
  end

  -- proxies
  if g_proxy then
    g_proxy.clear()
  end

  if modules.game_things.isLoaded() then
    g_logger.info("Connecting to: " .. server_ip .. ":" .. server_port)
    protocolLogin:login(server_ip, server_port, G.account, G.password, G.authenticatorToken, G.stayLogged)
  else
    local thingsError = ensureThingsLoaded() or tr('Please place the Tibia 8.60 asset files in data/things/860 (Tibia.dat and Tibia.spr).')
    return EnterGame.onError(thingsError)
  end
end

function EnterGame.doLoginHttp()
  if G.host == nil or G.host:len() < 10 then
    return EnterGame.onError("Invalid server url: " .. G.host)
  end

  loadBox = displayCancelBox(tr('Please wait'), tr('Connecting to login server...'))
  connect(loadBox, {
    onCancel = function(msgbox)
      loadBox = nil
      EnterGame.show()
    end
  })

  local data = {
    type = "login",
    account = G.account,
    accountname = G.account,
    email = G.account,
    password = G.password,
    gtoken = G.gtoken,
    token = G.authenticatorToken,
    version = APP_VERSION,
    uid = G.UUID,
    stayloggedin = true
  }

  local server = serverSelector:getText()
  local chosenServer = Servers and getServerInfoByName(server) or nil
  if chosenServer then
    local loginLink = chosenServer.loginLink
    waitingForHttpResults = 1
    HTTP.postJSON(loginLink, data, onHTTPResult)
  end
  EnterGame.hide()
end

function EnterGame.onError(err)
  if loadBox then
    loadBox:destroy()
    loadBox = nil
  end
  local errorBox = displayErrorBox(tr('Login Error'), err)
  errorBox.onOk = EnterGame.show
end

function EnterGame.onLoginError(err)
  if loadBox then
    loadBox:destroy()
    loadBox = nil
  end
  local errorBox = displayErrorBox(tr('Login Error'), err)
  errorBox.onOk = EnterGame.show
  if err:lower():find("invalid") or err:lower():find("not correct") or err:lower():find("or password") then
    EnterGame.clearAccountFields()
  end
end

function chooseTextMode()
  local hiddenButton = enterGame:getChildById('hidden')
  local hidden = enterGame.accountNameTextEdit:isTextHidden()

  isButtonPressed = not isButtonPressed

  if isButtonPressed then
    hiddenButton:setImageSource("/images/ui/hidden-button-down")
    enterGame.accountNameTextEdit:setTextHidden(false)
  else
    hiddenButton:setImageSource("/images/ui/hidden-button")
    enterGame.accountNameTextEdit:setTextHidden(true)
  end
end

function chooseButtonVisibility()
  local checkboxEmail = enterGame:getChildById('rememberEmailBox')
  local checkbox = enterGame:getChildById('rememberPasswordBox')
  local buttonMail = enterGame:getChildById('buttonInformation')
  local buttonPass = enterGame:getChildById('passwordInformation')

  if checkboxEmail:isChecked() then
    buttonMail:setVisible(true)
  else
    buttonMail:setVisible(false)
  end

  if checkbox:isChecked() then
    buttonPass:setVisible(true)
  else
    buttonPass:setVisible(false)
  end
end

local function isValidEmail(value)
  return value == "" or (string.len(value) > 3 and string.find(value, "@"))
end

function onTextChange()
  if not isValidEmail(enterGame.accountNameTextEdit:getText()) then
    enterGame.emailStatus:setVisible(true)
  else
    enterGame.emailStatus:setVisible(false)
  end
end

local charset = {}

for c = 48, 57 do
  table.insert(charset, string.char(c))
end

for c = 65, 90 do
  table.insert(charset, string.char(c))
end

for c = 97, 122 do
  table.insert(charset, string.char(c))
end


local function randomString(length)
  if not length or length <= 0 then
    return ""
  end

  math.randomseed(os.clock() ^ 5)

  if length == 1 then
    return charset[math.random(1, #charset)]
  end

  return randomString(length - 1) .. charset[math.random(1, #charset)]
end

local function onGoogleLoginResult(data, err)
  if awaitingGoogleAuth then
    removeEvent(awaitingGoogleAuth)
    awaitingGoogleAuth = nil
  end

  if err then
    return EnterGame.onError("Google login failed: " .. err)
  end

  if data.pending then
    -- Still waiting for authorization, check again
    awaitingGoogleAuth = scheduleEvent(function()
      local server = serverSelector:getText()
      local chosenServer = Servers and getServerInfoByName(server) or nil
      local googleLogin = getGoogleLoginUrl(chosenServer)
      if googleLogin then
        HTTP.getJSON(googleLogin .. "/webservices/gauth/check.php?session=" .. googleSession, onGoogleLoginResult)
      end
    end, 2000)
    return
  end

  if loadBox then
    loadBox:destroy()
    loadBox = nil
  end

  if data.success and data.account then
    -- Login successful, proceed with game login using returned credentials
    G.account = data.account.email
    G.password = data.account.ptoken or ""  -- Password may not be returned, handle accordingly
    G.gtoken = data.account.gtoken or ""
    G.authenticatorToken = ""

    -- Save to settings if remember is checked
    if rememberEmailBox:isChecked() then
      g_settings.set('account', g_crypt.encrypt(G.account))
    end

    g_settings.set('gtoken', g_crypt.encrypt(G.gtoken))

    -- Now proceed with regular HTTP login
    EnterGame.doLoginHttp()
  else
    EnterGame.onError(data.error or "Google authentication failed")
  end
end

function EnterGame.onGoogleClick()
  if g_game.isOnline() then
    local errorBox = displayErrorBox(tr("Login Error"), tr("Cannot login while already in game."))
    connect(errorBox, { onOk = EnterGame.show })
    return
  end

  G.stayLogged = true
  G.server = serverSelector:getText():trim()
  local chosenServer = getServerInfoByName(G.server)
  local googleLogin = getGoogleLoginUrl(chosenServer)
  if not googleLogin then
    return EnterGame.onError("Google login is not configured for this server.")
  end
  G.host = chosenServer and chosenServer.loginLink or serverHostTextEdit:getText()
  G.clientVersion = tonumber(clientVersionSelector:getText())

  -- Generate session ID for Google OAuth
  googleSession = "google_" .. randomString(32)
  EnterGame.hide()

  loadBox = displayCancelBox(tr('Google Authorization'), tr('Awaiting authorization in browser...'))
  connect(loadBox, {
    onCancel = function(msgbox)
      if loadBox then
        loadBox:destroy()
        loadBox = nil
      end
      if awaitingGoogleAuth then
        removeEvent(awaitingGoogleAuth)
        awaitingGoogleAuth = nil
      end
      googleSession = ""
      EnterGame.show()
    end
  })

  -- Open Google OAuth URL with client-specific callback
  local googleAuthUrl = googleLogin .. "/webservices/gauth/login_client.php?state=" .. googleSession
  g_platform.openUrl(googleAuthUrl)

  -- Start polling for login result
  awaitingGoogleAuth = scheduleEvent(function()
    HTTP.getJSON(googleLogin .. "/webservices/gauth/check.php?session=" .. googleSession, onGoogleLoginResult)
  end, 3000)
end

function EnterGame.doGoogleLogin()
  local server = serverSelector:getText()
  local chosenServer = Servers and getServerInfoByName(server) or nil
  local googleLogin = getGoogleLoginUrl(chosenServer)
  if googleLogin then
    HTTP.getJSON(googleLogin .. "/webservices/gauth/check.php?session=" .. googleSession, onGoogleLoginResult)
  end
end
