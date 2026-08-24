EnterGame = {}

-- private variables
local loadBox
local enterGame
local logpass
local twofactor
local protocolLogin
local loginEvent
local characterListEvent
local settingsSaveEvent
local showEvent
local autoLoginEvent

-- login module widgets (see entergame.otui / data/styles/40-entergame.otui)
local accountNameTextEdit
local accountPasswordTextEdit
local rememberEmailBox
local rememberPasswordBox
local autoLoginBox

-- Guards the @onCheckChange handlers while init() restores the saved state:
-- without it, seeding "remember email" fires the handler before the password
-- box has been seeded and wipes the stored password on every startup.
local uiReady = false

-- Generation tokens. An HTTP response can arrive after the attempt that asked
-- for it was cancelled, the server was changed, or the module was terminated.
-- Cancelling a scheduleEvent is not enough once the request is already on the
-- wire, so every in-flight callback carries the generation it belongs to and
-- returns early when it no longer matches.
local loginGeneration = 0
local httpOperationId = nil

-- Name of the server this client talks to. The login module deliberately has
-- no server picker (see ui-login), so it is resolved once from Servers
-- (init.lua) plus the saved 'server' setting.
local serverName

-- Protocol the whole Backlands stack is pinned to; used when nothing is saved.
local DEFAULT_CLIENT_VERSION = "860"

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
  return DEFAULT_CLIENT_VERSION
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
      if not server.name then server.name = tostring(name) end
      if not server.host then server.host = "" end
      if not server.port then server.port = 7171 end
      if not server.version then server.version = GameInfo.version end
      if not server.loginLink and server.host ~= "" then
        server.loginLink = string.format('%s:%d:%d', server.host, server.port, server.version)
      end
      if not server.clientServicesLink then server.clientServicesLink = Services and Services.status or "" end
      if not server.hintsJson then server.hintsJson = "" end
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
        hintsJson = ''
      })
    end
  end
  Servers = normalized
end

local function finishCharacterList(characters, account, otui)
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

  if settingsSaveEvent then
    removeEvent(settingsSaveEvent)
  end
  settingsSaveEvent = scheduleEvent(function()
    settingsSaveEvent = nil
    g_settings.save()
  end, 1)
end

local function onCharacterList(protocol, characters, account, otui)
  if characterListEvent then
    removeEvent(characterListEvent)
  end
  characterListEvent = scheduleEvent(function()
    characterListEvent = nil
    finishCharacterList(characters, account, otui)
  end, 1)
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

  -- rebuilt per login: keeping entries from a previously selected server would
  -- let a stale world id resolve against the wrong host
  worlds = {}

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
  httpOperationId = nil

  if err then
    return EnterGame.onError(err)
  end

  if data['errorCode'] == 6 then
    if loadBox then
      loadBox:destroy()
      loadBox = nil
    end

    -- both handlers are wired to two triggers each (onEscape/cancelButton and
    -- onEnter/okButton), so they must tolerate being fired twice
    local doCancelLogin = function()
      if not twofactor then return end
      g_client.setInputLockWidget(nil)
      twofactor:destroy()
      twofactor = nil
      EnterGame.show()
    end

    local doEnterGame = function()
      if not twofactor then return end
      local token = twofactor.tokenEnter:getText()
      g_client.setInputLockWidget(nil)
      twofactor:destroy()
      twofactor = nil
      EnterGame.doLogin(G.account, G.password, token, G.host, G.gtoken)
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

-- The login module shows no server picker, so the target is resolved here:
-- the remembered server while it still exists in Servers, otherwise the first
-- entry declared in init.lua.
local function getCurrentServer()
  if not Servers or #Servers == 0 then
    return nil
  end
  return getServerInfoByName(serverName) or Servers[1]
end

-- public functions
function EnterGame.init()
  if USE_NEW_ENERGAME then return end
  enterGame = g_ui.displayUI('entergame')
  if LOGPASS ~= nil then
    logpass = g_ui.loadUI('logpass', enterGame:getParent())
  end

  keybindChangeChar:active(rootWidget)

  local panel = enterGame:getChildById('panel')
  local nameField = panel:getChildById('accountNameField')
  local passwordField = panel:getChildById('accountPasswordField')
  accountNameTextEdit = nameField:getChildById('accountNameTextEdit')
  accountPasswordTextEdit = passwordField:getChildById('accountPasswordTextEdit')
  rememberEmailBox = panel:getChildById('rememberEmailBox')
  rememberPasswordBox = panel:getChildById('rememberPasswordBox')
  autoLoginBox = panel:getChildById('autoLoginBox')

  normalizeServers()

  serverName = g_settings.get('server')
  local server = getCurrentServer()
  if server then
    serverName = server.name
    -- guarded: this runs at module load, so client_background may not be up yet
    if modules.client_background and modules.client_background.updateStatus then
      modules.client_background.updateStatus(server)
    end
  end

  local account = g_crypt.decrypt(g_settings.get('account'))
  local password = g_crypt.decrypt(g_settings.get('password'))

  accountNameTextEdit:setText(account)
  accountNameTextEdit:setCursorPos(#account)
  accountPasswordTextEdit:setText(password)

  -- Defaults come from ui-login/layout.json: remember email ON, remember
  -- password OFF, auto login OFF. Both fields start masked - that is the
  -- LoginInput style (text-hidden) plus the eye toggles starting unchecked.
  rememberEmailBox:setChecked(g_settings.getBoolean('rememberEmail', true))
  rememberPasswordBox:setChecked(g_settings.getBoolean('rememberPassword', #password > 0))
  autoLoginBox:setChecked(g_settings.getBoolean('autoLogin', false))
  uiReady = true

  if g_game.isOnline() then
    return EnterGame.hide()
  end

  showEvent = scheduleEvent(function()
    showEvent = nil
    if not EnterGame then return end
    EnterGame.show()
  end, 100)

  -- Auto login: one shot, and only with credentials already on disk. A failed
  -- attempt drops the player back on the form instead of retrying in a loop.
  if autoLoginBox:isChecked() and #account > 0 and #password > 0 then
    autoLoginEvent = scheduleEvent(function()
      autoLoginEvent = nil
      if not EnterGame or g_game.isOnline() or g_game.isLogging() then return end
      EnterGame.doLogin()
    end, 600)
  end

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
  -- module-global resources are released unconditionally: they can exist even
  -- when `enterGame` is nil (init() returns early when already online), and a
  -- skipped cleanup here leaves events and signals running against dead state
  if loginEvent then
    removeEvent(loginEvent)
    loginEvent = nil
  end
  if characterListEvent then
    removeEvent(characterListEvent)
    characterListEvent = nil
  end
  if settingsSaveEvent then
    removeEvent(settingsSaveEvent)
    settingsSaveEvent = nil
  end
  if showEvent then
    removeEvent(showEvent)
    showEvent = nil
  end
  if autoLoginEvent then
    removeEvent(autoLoginEvent)
    autoLoginEvent = nil
  end

  -- invalidate any login response still on the wire
  loginGeneration = loginGeneration + 1
  if httpOperationId then
    HTTP.cancel(httpOperationId)
    httpOperationId = nil
  end

  disconnect(g_game, {
    onGameStart = onGameStart,
    onGameEnd = onGameEnd
  })

  keybindChangeChar:deactive()

  uiReady = false

  if not enterGame then
    EnterGame = nil
    return
  end

  if logpass then
    logpass:destroy()
    logpass = nil
  end

  enterGame:destroy()
  enterGame = nil
  if loadBox then
    loadBox:destroy()
    loadBox = nil
  end
  if twofactor then
    -- the 2FA window installs itself as the input lock; releasing it here keeps
    -- a destroyed widget from staying pinned in g_ui's lock slot
    g_client.setInputLockWidget(nil)
    twofactor:destroy()
    twofactor = nil
  end
  if protocolLogin then
    protocolLogin:cancelLogin()
    protocolLogin.onLoginError = nil
    protocolLogin.onSessionKey = nil
    protocolLogin.onCharacterList = nil
    protocolLogin.onUpdateNeeded = nil
    protocolLogin.onProxyList = nil
    protocolLogin = nil
  end

  accountNameTextEdit = nil
  accountPasswordTextEdit = nil
  rememberPasswordBox = nil
  rememberEmailBox = nil
  autoLoginBox = nil

  EnterGame = nil
end

function EnterGame.show()
  G.characters = nil
  if not enterGame then return end
  enterGame:show()
  enterGame:raise()
  enterGame:focus()
  -- recursiveFocus, not focus: the edit sits two containers deep and key events
  -- only reach it when every widget on the way up is the focused child
  accountNameTextEdit:recursiveFocus(ActiveFocusReason)
  if logpass then
    logpass:show()
    logpass:raise()
    logpass:focus()
  end
end

function EnterGame.hide()
  if not enterGame then return end
  if not rememberPasswordBox:isChecked() then
    accountPasswordTextEdit:clearText()
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
  if g_game.isLogging() or g_game.isOnline() then
    return
  end

  if G.characters then
    CharacterList.show()
  elseif not CharacterList.isVisible() then
    EnterGame.show()
  end
end

function EnterGame.clearAccountFields()
  if not enterGame then return end
  if not rememberEmailBox:isChecked() then
    accountNameTextEdit:clearText()
    g_settings.remove('account')
  end
  if not rememberPasswordBox:isChecked() then
    accountPasswordTextEdit:clearText()
    g_settings.remove('password')
  end
  accountNameTextEdit:recursiveFocus(ActiveFocusReason)
end

local function performLogin(account, password, token, host, gtoken)
  if g_game.isOnline() then
    local errorBox = displayErrorBox(tr('Login Error'), tr('Cannot login while already in game.'))
    connect(errorBox, { onOk = EnterGame.show })
    return
  end

  G.account = account or accountNameTextEdit:getText()
  G.password = password or accountPasswordTextEdit:getText()
  -- there is no token field in the login module: a server that demands a
  -- second factor asks for it through the twofactor popup (errorCode 6)
  G.authenticatorToken = token or ""
  G.gtoken = gtoken or ""
  G.stayLogged = true
  local chosenServer = getCurrentServer()
  G.server = chosenServer and chosenServer.name or ""
  G.host = chosenServer and chosenServer.loginLink or ""
  G.clientVersion = chosenServer and chosenServer.version or tonumber(getDefaultClientVersion())

  if G.password == "" then
    return
  end

  local thingsError = ensureThingsLoaded()
  if thingsError then
    return EnterGame.onError(thingsError)
  end

  -- "Remember email" is honoured literally: checked stores the login the same
  -- encrypted way the character list does, unchecked stores nothing at all
  if rememberEmailBox:isChecked() then
    g_settings.set('account', g_crypt.encrypt(G.account))
  else
    g_settings.remove('account')
  end

  if rememberPasswordBox:isChecked() and G.gtoken == '' then
    g_settings.set('password', g_crypt.encrypt(G.password))
  end

  g_settings.set('host', G.host)
  g_settings.set('server', G.server)
  g_settings.set('client-version', G.clientVersion)

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
  -- capture THIS attempt's protocol. Reading the `protocolLogin` upvalue at
  -- click time would cancel whatever login happens to be current, which after a
  -- retry is a different connection than the one this box belongs to.
  local loginProtocol = protocolLogin

  loadBox = displayCancelBox(tr('Please wait'), tr('Connecting to login server...'))
  connect(loadBox, {
    onCancel = function(msgbox)
      loadBox = nil
      if loginProtocol then
        loginProtocol:cancelLogin()
      end
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

function EnterGame.doLogin(account, password, token, host, gtoken)
  if loginEvent then
    return
  end

  loginEvent = scheduleEvent(function()
    loginEvent = nil
    performLogin(account, password, token, host, gtoken)
  end, 1)
end

function EnterGame.doLoginHttp()
  if G.host == nil or G.host:len() < 10 then
    return EnterGame.onError("Invalid server url: " .. G.host)
  end

  -- supersede any previous attempt: a response already on the wire must not be
  -- allowed to apply its features/rsa/version onto this new session
  loginGeneration = loginGeneration + 1
  local generation = loginGeneration
  if httpOperationId then
    HTTP.cancel(httpOperationId)
    httpOperationId = nil
  end

  loadBox = displayCancelBox(tr('Please wait'), tr('Connecting to login server...'))
  connect(loadBox, {
    onCancel = function(msgbox)
      loadBox = nil
      loginGeneration = loginGeneration + 1
      if httpOperationId then
        HTTP.cancel(httpOperationId)
        httpOperationId = nil
      end
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

  local chosenServer = getCurrentServer()
  if chosenServer then
    local loginLink = chosenServer.loginLink
    httpOperationId = HTTP.postJSON(loginLink, data, function(result, err)
      if generation ~= loginGeneration then
        return -- cancelled, superseded, or the module was terminated
      end
      onHTTPResult(result, err)
    end)
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

-- --------------------------------------------------------------------------
-- login module callbacks (entergame.otui)
-- --------------------------------------------------------------------------

-- The eye toggle only flips the mask of its own field: checked = revealed.
function EnterGame.onRevealChange(toggle)
  if not uiReady then return end
  local input = (toggle:getId() == 'accountNameEye') and accountNameTextEdit or accountPasswordTextEdit
  if not input then return end
  input:setTextHidden(not toggle:isChecked())
end

-- The three options are persisted the moment they are toggled, so unchecking
-- "remember" really does drop the stored credential instead of waiting for the
-- next successful login.
function EnterGame.onOptionChange()
  if not uiReady then return end

  g_settings.set('rememberEmail', rememberEmailBox:isChecked())
  g_settings.set('rememberPassword', rememberPasswordBox:isChecked())
  g_settings.set('autoLogin', autoLoginBox:isChecked())

  if not rememberEmailBox:isChecked() then
    g_settings.remove('account')
  end
  if not rememberPasswordBox:isChecked() then
    g_settings.remove('password')
  end
end

-- The links point at whatever the server operator configured in Services
-- (init.lua). Unset means "this deployment has no web front-end yet", which is
-- worth saying out loud rather than opening a nil url.
local function openService(url, what)
  if type(url) ~= 'string' or url == '' then
    return displayInfoBox(tr('Backlands'), tr('%s is not configured for this client yet.', what))
  end
  g_platform.openUrl(url)
end

function EnterGame.openCreateAccount()
  openService(Services and Services.createAccount, tr('Account creation'))
end

function EnterGame.openRecoverPassword()
  openService(Services and Services.recoverPassword, tr('Password recovery'))
end

function EnterGame.openRecoverEmail()
  openService(Services and Services.recoverEmail, tr('Login recovery'))
end
