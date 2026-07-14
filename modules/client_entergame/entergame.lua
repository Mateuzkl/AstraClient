EnterGame = {}

-- private variables
local loadBox
local enterGame
local logpass
local twofactor

local customServerSelectorPanel
local serverSelectorPanel
local serverSelector
local clientVersionSelector
local serverHostTextEdit
local rememberPasswordBox
local rememberEmailBox
-- Only the current era is supported; the version selector shows a single fixed entry.
local protos = { tostring(CLIENT_VERSION) }

-- Development config may force every world returned by the HTTP login service
-- to a local game server while preserving the world port supplied by the AAC.
local function resolveWorldAddress(address)
  local override = rawget(_G, 'GAME_HOST_OVERRIDE')
  if type(override) == 'string' and override:len() > 0 then
    return override
  end
  return address
end

-- The client targets a single era (CLIENT_VERSION, init.lua): every login path
-- resolves to it. `requested` (a server-entry suffix or selector value) is
-- accepted for call-site compatibility but ignored — there is no other version.
local function resolveClientVersion(requested)
  return tonumber(CLIENT_VERSION)
end

-- Google Configuration
local googleSession = ""
local awaitingGoogleAuth = false

local waitingForHttpResults = 0

local keybindChangeChar = KeyBind:getKeyBind("Misc.", "Change Character")

-- private functions
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
  CharacterList.create(characters, account, otui)
  CharacterList.show()

  g_settings.save()
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

-- Detects Koliseu's flat HTTP response shape.
-- Koliseu sends `clientVersion` (number) + top-level `worlds` / `characters` arrays,
-- in contrast to the Tibia 12.x shape which nests everything under `session`/`playdata`.
local function isKoliseuShape(data)
  if type(data) ~= "table" then
    return false
  end
  if type(data["clientVersion"]) ~= "number" then
    return false
  end
  return type(data["worlds"]) == "table" or type(data["characters"]) == "table"
end

-- Queues HTTP.download calls for appearances.dat + sprite sheets into data/things/<version>/.
-- Reuses the same HTTP.download primitive as modules/updater/updater.lua.
-- doneCallback() fires once every file finishes (or immediately if there is nothing to fetch).
local function downloadKoliseuCatalog(catalogUrl, clientVersion, files, index, doneCallback)
  local entry = files[index]
  if not entry then
    return doneCallback()
  end
  local relPath = "data/things/" .. tostring(clientVersion) .. "/" .. entry
  HTTP.download(catalogUrl .. "/" .. entry, relPath, function(_file, _checksum, err)
    if err then
      g_logger.warning("Koliseu catalog: failed to fetch " .. entry .. " (" .. tostring(err) .. ")")
    end
    downloadKoliseuCatalog(catalogUrl, clientVersion, files, index + 1, doneCallback)
  end)
end

local function onKoliseuHTTPResult(data)
  local clientVersion = resolveClientVersion(data["clientVersion"])
  local catalogUrl = data["catalogUrl"]
  local sessionKey = nil
  if type(data["session"]) == "table" then
    sessionKey = data["session"]["sessionkey"]
  elseif type(data["session"]) == "string" then
    sessionKey = data["session"]
  end

  local account = {
    status = 0,
    subStatus = SubscriptionStatus.Free,
    premDays = 0,
  }

  if type(data["session"]) == "table" then
    local session = data["session"]
    if session["status"] and session["status"] ~= "active" then
      account.status = 1
    end
    -- Compare against os.time() (epoch), not g_clock.seconds() (client uptime).
    local premiumExpiry = math.max(tonumber(session["premiumuntil"]) or 0, tonumber(session["viptime"]) or 0)
    if premiumExpiry > os.time() then
      account.subStatus = SubscriptionStatus.Premium
      account.premDays = math.max(0, math.ceil((premiumExpiry - os.time()) / 86400))
    elseif session["ispremium"] then
      account.subStatus = SubscriptionStatus.Premium
    end
  end

  for _, world in pairs(data["worlds"] or {}) do
    worlds[world.id] = {
      name = world.name,
      address = resolveWorldAddress(world.host),
      port = world.port,
      pvptype = world.pvptype or 0,
      version = world.version or clientVersion,
    }
  end

  local characters = {}
  for _, character in pairs(data["characters"] or {}) do
    local world = worlds[character.worldid or character.worldId]
    if world then
      table.insert(characters, {
        name = character.name,
        worldName = world.name,
        worldIp = world.address,
        worldPort = world.port,
        pvpType = world.pvptype,
        mainCharacter = character.ismaincharacter or character.mainCharacter,
        dailyRewardState = character.dailyrewardstate or character.dailyRewardState or 0,
        level = character.level or 1,
        vocation = character.vocation or 0,
        worldId = character.worldid or character.worldId,
        outfit = character.outfit or {
          type = character.outfitid or 128,
          head = character.headcolor or 0,
          body = character.torsocolor or 0,
          legs = character.legscolor or 0,
          feet = character.detailcolor or 0,
          addons = character.addonsflags or 0,
        },
      })
    end
  end

  if #characters == 0 then
    return EnterGame.onError("No characters found on this account.")
  end

  G.clientVersion = clientVersion
  g_game.setClientVersion(clientVersion)
  g_game.setStringVersion(GameInfo.strVersion)
  g_game.setProtocolVersion(g_game.getClientProtocolVersion(clientVersion))
  g_game.setCustomProtocolVersion(0)
  g_game.chooseRsa(G.host)
  g_game.setCustomOs(-1)
  if not g_game.getFeature(GameExtendedOpcode) then
    g_game.setCustomOs(5)
  end

  if sessionKey then
    onSessionKey(nil, sessionKey)
  end

  local function proceed()
    onCharacterList(nil, characters, account, nil)
  end

  if type(catalogUrl) == "string" and catalogUrl:len() > 0 then
    -- Strip trailing slash so we can do catalogUrl .. "/" .. file uniformly.
    catalogUrl = catalogUrl:gsub("/+$", "")
    local catalogFiles = data["catalogFiles"]
    if type(catalogFiles) ~= "table" or #catalogFiles == 0 then
      catalogFiles = { "appearances.dat", "catalog-content.json" }
    end
    if loadBox then
      loadBox.label:setText(tr("Downloading game data..."))
    end
    downloadKoliseuCatalog(catalogUrl, clientVersion, catalogFiles, 1, proceed)
  else
    proceed()
  end
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

  -- Premium/VIP status. Koliseu's AAC sends `ispremium` (bool) + `premiumuntil`
  -- (unix expiry timestamp); other backends send `viptime` (unix expiry). Support
  -- both, and always compare against os.time() -- g_clock.seconds() is the client
  -- uptime, not the epoch, so it would yield a garbage day count. account.premDays
  -- carries the remaining days the character list renders.
  account.subStatus = SubscriptionStatus.Free
  account.premDays = 0

  local premiumExpiry = math.max(tonumber(session["premiumuntil"]) or 0, tonumber(session["viptime"]) or 0)
  if premiumExpiry > os.time() then
    account.premDays = math.max(0, math.ceil((premiumExpiry - os.time()) / 86400))
    account.subStatus = SubscriptionStatus.Premium
  elseif session["ispremium"] then
    account.subStatus = SubscriptionStatus.Premium
  end
  G.clientVersion = resolveClientVersion(session["version"])

  onSessionKey(nil, session["sessionkey"])

  Worlds:loadWorlds(playdata)
  for _, world in pairs(playdata["worlds"]) do
    worlds[world.id] = {
      name = world.name,
      port = world.externalportunprotected or world.externalportprotected or world.externalport,
      address = resolveWorldAddress(world.externaladdressunprotected or world.externaladdressprotected or world.externaladdress),
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

    -- Tell "token required" (first prompt) apart from "token rejected" (retry):
    -- if we already sent a non-empty token and the server still answers errorCode 6,
    -- the previous token was wrong/expired. Surface the server's message instead of
    -- silently reopening a blank dialog, so the user knows the code didn't work.
    local tokenRejected = G.authenticatorToken ~= nil and G.authenticatorToken ~= ""
    local serverMessage = data['errorMessage']

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

    if tokenRejected then
      local msg = (serverMessage and serverMessage:len() > 0) and serverMessage
        or 'Two-factor authentication failed, token is wrong.'
      twofactor.messageLabel:setText(tr(msg))
      twofactor.messageLabel:setColor('#ff5555')
    end
    twofactor.tokenEnter:focus()

    g_client.setInputLockWidget(twofactor)
    return
  end

  -- Client outdated: the login service refused this build's release_version
  -- (server-authoritative version gate). errorCode 20 is our dedicated "update
  -- required" signal; show the update dialog + Launcher hand-off instead of the
  -- generic login-error box. `available` is the version published for this environment.
  if data['errorCode'] == 20 then
    if loadBox then
      loadBox:destroy()
      loadBox = nil
    end
    return EnterGame.showUpdateRequired(CLIENT_RELEASE_VERSION, data['available'])
  end

  if data['error'] and data['error']:len() > 0 then
    return EnterGame.onLoginError(data['error'])
  elseif data['errorMessage'] and data['errorMessage']:len() > 0 then
    return EnterGame.onLoginError(data['errorMessage'])
  end

  -- Koliseu's flat shape: clientVersion + top-level worlds/characters arrays.
  -- Check before the Tibia 12.x branch since Koliseu may also include a `session` table.
  if isKoliseuShape(data) then
    return onKoliseuHTTPResult(data)
  end

  if type(data["session"]) == "table" and type(data["playdata"]) == "table" then
    return onTibia12HTTPResult(data["session"], data["playdata"])
  end

  local characters = data["characters"]
  local account = data["account"]
  local session = data["session"]

  local version = resolveClientVersion(data["version"])
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

  if type(characters) == 'table' then
    for _, character in pairs(characters) do
      character.worldIp = resolveWorldAddress(character.worldIp)
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
  -- The client targets a single era: pin the selector to CLIENT_VERSION so the UI
  -- matches the version the login flow actually uses (see resolveClientVersion).
  local clientVersion = tostring(CLIENT_VERSION)

  if serverSelector:isOption(server) then
    serverSelector:setCurrentOption(server, false)
    if Servers == nil then
      serverHostTextEdit:setText(host)
    end
    clientVersionSelector:setOption(clientVersion)
  else
    server = ""
    host = ""
  end

  -- The server selector is hidden in this client (the external Launcher chooses prod/test,
  -- and each client targets a single server). Pin the selector to the first real server so
  -- doLogin always has a valid login target, even on a fresh install. See EnterGame.openLauncher.
  if not getServerInfoByName(serverSelector:getText()) and Servers then
    for _, srv in pairs(Servers) do
      if not srv.launchBinary then
        serverSelector:setCurrentOption(srv.name, false)
        break
      end
    end
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

  -- Optional dev auto-login (set AUTO_LOGIN_DEBUG + AUTO_LOGIN_EMAIL/PASS in
  -- config.lua). Fires the HTTP login and, unless AUTO_SELECT_CHAR == false,
  -- auto-selects the first character. Off by default; handy for iterating on
  -- the 15.25 connection without typing credentials each run.
  if AUTO_LOGIN_DEBUG then
    scheduleEvent(function()
      EnterGame.doLogin(AUTO_LOGIN_EMAIL, AUTO_LOGIN_PASS, nil, AUTO_LOGIN_HOST or "http://127.0.0.1/login.php", "")
    end, 3000)
    if AUTO_SELECT_CHAR ~= false then
      -- Retry until the character list widget exists and has a focused row, so
      -- we don't call doLogin() before CharacterList.create() ran.
      local function autoSelect()
        if CharacterList and CharacterList.isVisible and CharacterList.isVisible() then
          CharacterList.doLogin()
        else
          scheduleEvent(autoSelect, 500)
        end
      end
      scheduleEvent(autoSelect, 5000)
    end
  end
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

  -- The login window is hidden during a login attempt and shown again when the user
  -- returns (e.g. Esc from the character/cast list). Across that hide the account field
  -- stays THIS window's focused child (hiding the window only moved the root's focus, not
  -- the window's internal focus), so the :focus() above is a no-op: it never fires
  -- onFocusChange and the text-edit's update() is never re-run. A text edit caches the
  -- absolute screen coords of its glyphs; if the box's rect briefly oscillates within one
  -- dispatcher tick (the Esc handler hides the char list, shows this window and fires
  -- onLogout back to back) the corrective onGeometryChange can be deduped away, leaving the
  -- cached glyphs stale relative to the box -- the email text ends up drawn outside the
  -- input. Force each field to recompute its text layout, both now and once the tick has
  -- settled, so it always renders inside its box.
  local function refreshLoginFields()
    if not enterGame or enterGame:isDestroyed() then return end
    for _, id in ipairs({ 'accountNameTextEdit', 'accountPasswordTextEdit', 'accountTokenTextEdit' }) do
      local field = enterGame:getChildById(id)
      if field then field:setTextVirtualOffset(field:getTextVirtualOffset()) end
    end
  end
  refreshLoginFields()
  addEvent(refreshLoginFields)

  if logpass then
    logpass:show()
    logpass:raise()
    logpass:focus()
  end
end

-- keepFields: hide the window WITHOUT clearing the (unsaved) password. The clear only
-- makes sense after an actual "Log in"; the cast overlay hides the form just to get it out
-- of the way while browsing/watching, and must leave it untouched for when it comes back.
function EnterGame.hide(keepFields)
  if not enterGame then return end
  if not keepFields and not rememberPasswordBox:isChecked() then
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
    modules.client_background.updateStatus(serverInfo)
  end
end

function EnterGame.openLauncher()
  -- "Change Client": hand off to the external Launcher (Tauri app). When the launcher
  -- started this client it set KOLISEU_LAUNCHER to its own absolute path; fall back to a
  -- sibling KoliseuLauncher.exe otherwise. Pass --show so the Launcher always presents its
  -- UI (even when "Default Client" is set) so the player can install/switch clients.
  local launcher = os.getenv("KOLISEU_LAUNCHER")
  if not launcher or launcher == "" then
    launcher = "KoliseuOT-Launcher.exe"
  end
  if not g_app.launchBinary(launcher, "--show") then
    displayErrorBox(tr('Launcher'),
      tr('The Koliseu Launcher was not found.\n' ..
         'Reinstall through the launcher to switch clients.'))
  end
end

-- Shown when the login service refuses an outdated client (onHTTPResult, errorCode 20).
-- `installed` is this build's CLIENT_RELEASE_VERSION; `available` is the version published
-- for this environment in client_version. Offers the Launcher to update.
function EnterGame.showUpdateRequired(installed, available)
  local updateFunc = function() EnterGame.openLauncher() end
  local cancelFunc = function() end
  displayGeneralBox(tr('Update Required'),
    tr("Your client is outdated and can't connect to the server.\n\nInstalled: %s\nAvailable: %s\n\nUpdate through the Launcher to continue.",
       installed or '?', available or '?'),
    {
      { text = tr('Update'), callback = updateFunc },
      { text = tr('Cancel'), callback = cancelFunc },
    }, updateFunc, cancelFunc)
end

function EnterGame.doLogin(account, password, token, host, gtoken)
  if g_game.isOnline() then
    local errorBox = displayErrorBox(tr('Login Error'), tr('Cannot login while already in game.'))
    connect(errorBox, { onOk = EnterGame.show })
    return
  end

  -- Version gate: no longer a separate pre-flight request. The client sends its
  -- CLIENT_RELEASE_VERSION as `release_version` in the login payload (see doLoginHttp)
  -- and the login service (koliseu-aac /api/login) rejects an outdated client with a
  -- dedicated errorCode, handled in onHTTPResult -> showUpdateRequired. This is
  -- server-authoritative and fail-closed, and covers every login path uniformly.

  G.account = account or enterGame:getChildById('accountNameTextEdit'):getText()
  G.password = password or enterGame:getChildById('accountPasswordTextEdit'):getText()
  G.authenticatorToken = token or enterGame:getChildById('accountTokenTextEdit'):getText()
  G.gtoken = gtoken or ""
  G.stayLogged = true
  G.server = serverSelector:getText():trim()
  local chosenServer = getServerInfoByName(G.server)

  -- Test/prod split: a server entry with `launchBinary` is not a connection target -- it
  -- hands off to a separate client exe (the test build). See docs/DISTRIBUICAO_E_UPDATER.md.
  if chosenServer and chosenServer.launchBinary then
    if not g_app.launchBinary(chosenServer.launchBinary, "") then
      displayErrorBox(tr('Test Client'),
        tr('The test client (%s) is not installed yet.', chosenServer.launchBinary))
    end
    return
  end

  G.host = chosenServer and chosenServer.loginLink or serverHostTextEdit:getText()
  G.clientVersion = resolveClientVersion(clientVersionSelector:getText())

  if G.password == "" then
    return
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
      G.clientVersion = resolveClientVersion(server_params[4])
    elseif #server_params >= 3 then
      if tostring(tonumber(server_params[3])) == server_params[3] then
        G.host = server_params[1] .. ":" .. server_params[2]
        G.clientVersion = resolveClientVersion(server_params[3])
      end
    end
    return EnterGame.doLoginHttp()
  end

  -- Legacy TCP ProtocolLogin (ip:port:version on 7171) was removed: KoliseuClient
  -- targets a single modern era (1525) and authenticates over HTTP only. A host
  -- that is not an http(s) URL is a misconfiguration, not an old-protocol server.
  return EnterGame.onError(tr("Invalid server: it must be an http(s) URL to the login script."))
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
    release_version = CLIENT_RELEASE_VERSION,
    -- Sinaliza build em developer mode (init.lua DEVELOPERMODE). O gate de versao e
    -- server-authoritative; o servidor SO honra este flag fora de producao
    -- (NODE_ENV != production), entao em producao o gate continua nao-forjavel.
    developer_mode = DEVELOPERMODE == true,
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

  if hidden then
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
  G.clientVersion = resolveClientVersion(clientVersionSelector:getText())

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
