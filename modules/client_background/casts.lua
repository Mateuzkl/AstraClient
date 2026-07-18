-- Live cast (livestream) discovery for the login screen.
--
-- The game server's "livestream" system lets anyone watch a broadcasting player by
-- connecting with an empty account, password = the cast's password (empty for open
-- casts) and characterName = the caster's name. The client reuses the normal
-- g_game.loginWorld path for that. The empty account is exactly how this TFS routes
-- the connection to ProtocolGame::spectate().
--
-- The active-cast list and aggregate counts come straight from the TFS login
-- protocol. Passwords are validated server-side on connect; the list packet only
-- tells us whether a cast is protected (haspassword), never the password itself.

Cast = Cast or {}
Cast.list = {}
Cast.serverInfo = nil
Cast.watching = nil
Cast.loadBox = nil

local castStatusEvent
local castWindow
local passwordWindow
local castProtocol
local castRequestId = 0

local CastRequestPassword = '__astra_casts_v1__'
local CastRefreshInterval = 30000

-- Resolve the castScroll widget on the login panel. nil before the UI loads, after
-- teardown, or once in game.
local function castBox()
  local bg = getBackground and getBackground() or nil
  if not bg or not bg.loadAfter then return nil end
  return bg.loadAfter.castScroll
end

local function setCounts(casters, viewers)
  local box = castBox()
  if not box then return end
  box.castCount:setText(string.format('%d %s', casters, casters == 1 and 'Player Casting' or 'Players Casting'))
  box.viewerCount:setText(string.format('%d %s', viewers, viewers == 1 and 'Viewer' or 'Viewers'))
end

local function cancelCastRequest()
  castRequestId = castRequestId + 1
  if castProtocol then
    pcall(function() castProtocol:cancelLogin() end)
    castProtocol = nil
  end
end

local function getLoginEndpoint(serverInfo)
  if type(serverInfo) ~= 'table' then return nil end
  local host = type(serverInfo.host) == 'string' and serverInfo.host or nil
  local port = tonumber(serverInfo.port)
  if not host or host:len() == 0 or not port or port <= 0 then return nil end
  return host, port
end

-- Ask the TFS login port for the current cast list, then refresh every 30 seconds.
-- The response also carries the game-world address and port used by Watch.
function Cast.updateStatus(serverInfo)
  removeEvent(castStatusEvent)
  castStatusEvent = nil

  cancelCastRequest()
  if serverInfo and serverInfo ~= Cast.serverInfo then
    Cast.list = {}
    setCounts(0, 0)
    if castWindow then Cast.populateList() end
  end
  if serverInfo then Cast.serverInfo = serverInfo end
  serverInfo = Cast.serverInfo

  if not castBox() then return end
  if g_game.isOnline() then return end
  local host, port = getLoginEndpoint(serverInfo)
  if not host then return end

  local requestId = castRequestId
  castStatusEvent = scheduleEvent(function() Cast.updateStatus() end, CastRefreshInterval)

  local version = tonumber(serverInfo.version)
  if version then
    g_game.setClientVersion(version)
    g_game.setProtocolVersion(g_game.getClientProtocolVersion(version))
  end
  g_game.chooseRsa(host)

  local protocol = ProtocolLogin.create()
  castProtocol = protocol
  protocol.onCastList = function(_, casts, totalViewers)
    if requestId ~= castRequestId or castProtocol ~= protocol then return end
    castProtocol = nil

    Cast.list = type(casts) == 'table' and casts or {}
    table.sort(Cast.list, function(a, b)
      return tostring(a.name or ''):lower() < tostring(b.name or ''):lower()
    end)
    setCounts(#Cast.list, tonumber(totalViewers) or 0)
    -- Keep an open list window in sync with fresh data.
    if castWindow then
      Cast.populateList()
    end
  end
  protocol.onLoginError = function()
    if requestId == castRequestId and castProtocol == protocol then
      -- Silent: the panel keeps its last values and the timer retries.
      castProtocol = nil
    end
  end

  local ok, err = pcall(function()
    protocol:login(host, port, '', CastRequestPassword, '', false)
  end)
  if not ok then
    if castProtocol == protocol then castProtocol = nil end
    g_logger.warning('Could not request the Astra cast list: ' .. tostring(err))
  end
end

-- Remove the refresh timer and any in-flight login connection.
function Cast.terminate()
  removeEvent(castStatusEvent)
  castStatusEvent = nil
  cancelCastRequest()
  Cast.closeList()
end

-- Reach the login form (client_entergame) so the cast overlay can hide/show it. Kept as a
-- thin accessor so both openCastList and closeCastList agree on how to find it.
local function loginBox()
  return modules.client_entergame and modules.client_entergame.EnterGame or nil
end

-- Open the cast list window (Watch button). Refresh first when we have no data yet;
-- the poll callback repopulates the window once it arrives.
function openCastList()
  if g_game.isOnline() then return end

  -- Get the "Journey Onwards" login form out of the way while the cast list is up. It used
  -- to stay visible behind the list and, after picking a cast, behind the "Connecting..."
  -- modal. keepFields=true so the player's typed email/password survive the round trip.
  local eg = loginBox()
  if eg then eg.hide(true) end

  if castWindow then
    castWindow:destroy()
    castWindow = nil
  end
  castWindow = g_ui.displayUI('castlist')

  if #Cast.list == 0 then
    Cast.updateStatus()
  end
  Cast.populateList()

  castWindow:raise()
  castWindow:focus()
end

-- OTUI @onClick/@onEscape handlers run in the real global env, not the module
-- sandbox, so castlist.otui reaches these via modules.client_background.* (the module
-- table) rather than the sandbox-global `Cast`. Thin wrappers over the Cast methods.
function watchSelectedCast()
  Cast.watchSelected()
end

function closeCastList()
  Cast.closeList()
  -- Cancelling out of the cast list returns to the login form that openCastList hid.
  -- Skip while a watch is mid-flight (loadBox/watching set) or already in a game, so we
  -- never flash the login form behind the "Connecting..." modal or over the game.
  if not g_game.isOnline() and not Cast.loadBox and not Cast.watching then
    local eg = loginBox()
    if eg then eg.show() end
  end
end

function Cast.closeList()
  if passwordWindow then
    passwordWindow:destroy()
    passwordWindow = nil
  end
  if castWindow then
    castWindow:destroy()
    castWindow = nil
  end
end

function Cast.populateList()
  if not castWindow then return end
  local list = castWindow:getChildById('castList')
  list:destroyChildren()
  for _, cast in ipairs(Cast.list) do
    local row = g_ui.createWidget('CastListRow', list)
    row.castInfo = cast
    local viewers = tonumber(cast.viewers) or 0
    row:getChildById('name'):setText(cast.name or '?')
    row:getChildById('viewers'):setText(viewers == 1 and tr('1 viewer') or tr('%d viewers', viewers))
    row:getChildById('lock'):setVisible(cast.haspassword and true or false)
    connect(row, { onDoubleClick = function() Cast.watchSelected() return true end })
  end

  local info = castWindow:getChildById('infoLabel')
  if info then
    if #Cast.list == 0 then
      info:setText(tr('No one is casting right now.'))
    else
      info:setText(tr('%d cast(s) live', #Cast.list))
    end
  end
end

function Cast.watchSelected()
  if not castWindow then return end
  local list = castWindow:getChildById('castList')
  local sel = list:getFocusedChild()
  if not sel or not sel.castInfo then
    displayErrorBox(tr('Watch Cast'), tr('Select a cast to watch.'))
    return
  end
  Cast.watch(sel.castInfo)
end

function Cast.watch(castInfo)
  if castInfo.haspassword then
    Cast.promptPassword(castInfo)
  else
    Cast.connect(castInfo, "")
  end
end

-- Password prompt for protected casts. Ok -> connect with the typed password,
-- Cancel -> back to the list.
function Cast.promptPassword(castInfo)
  if passwordWindow then
    passwordWindow:destroy()
    passwordWindow = nil
  end
  passwordWindow = g_ui.displayUI('castpassword')
  passwordWindow.caster:setText(tr('Cast: %s', castInfo.name or '?'))
  local edit = passwordWindow.passwordEnter
  edit:focus()

  local doConnect = function()
    local pw = edit:getText()
    passwordWindow:destroy()
    passwordWindow = nil
    Cast.connect(castInfo, pw)
  end
  local doCancel = function()
    passwordWindow:destroy()
    passwordWindow = nil
  end
  passwordWindow.onEnter = doConnect
  passwordWindow.onEscape = doCancel
  passwordWindow.okButton.onClick = doConnect
  passwordWindow.cancelButton.onClick = doCancel
end

-- Connect to the game server as a livestream viewer. An empty account selects the
-- server's cast route; the caster name is the "character" and password is optional.
-- handleCastLoginError() below turns a rejection into a friendly dialog.
function Cast.connect(castInfo, password)
  if g_game.isOnline() then return end
  if not castInfo.host or not tonumber(castInfo.port) then
    displayErrorBox(tr('Watch Cast'), tr('This cast has no reachable server.'))
    return
  end

  Cast.watching = castInfo
  Cast.closeList()

  if Cast.loadBox then
    Cast.loadBox:destroy()
    Cast.loadBox = nil
  end
  Cast.loadBox = displayCancelBox(tr('Please wait'), tr('Connecting to livestream...'))
  connect(Cast.loadBox, {
    onCancel = function()
      Cast.loadBox = nil
      -- Mark dismissal time before canceling so handleCastLoginError recognizes the
      -- expected cancelLogin error and suppresses the reconnect window.
      Cast.dismissedAt = g_clock.millis()
      pcall(function() g_game.cancelLogin() end)
      -- Clear watching state after cancelLogin triggers its error callback.
      Cast.watching = nil
      openCastList()
    end
  })

  local ok, err = pcall(function()
    g_game.loginWorld("", password, castInfo.world or 'Cast',
      castInfo.host, tonumber(castInfo.port), castInfo.name, "", "", nil)
  end)
  if not ok then
    g_logger.error("Cast connect failed: " .. tostring(err))
    Cast.watching = nil
    if Cast.loadBox then Cast.loadBox:destroy() Cast.loadBox = nil end
    displayErrorBox(tr('Watch Cast'), tr('Could not connect to the livestream.'))
    openCastList()
  end
end

-- Called from characterlist.lua's onGameLoginError / onGameConnectionError BEFORE its
-- own handling. Returns true when we consumed the error (a cast-watch was in flight),
-- so the character-list flow is skipped and we bounce back to the cast list instead.
function handleCastLoginError(message)
  if not Cast.watching then
    -- The server rejects with disconnectClient: the 0x14 error arrives first, then the
    -- socket closes -> a follow-up onConnectionError (EOF). Swallow that trailing event
    -- silently so the character-list flow doesn't pop a "reconnecting" window on top of
    -- the dialog we just showed.
    if Cast.dismissedAt and (g_clock.millis() - Cast.dismissedAt) < 3000 then
      return true
    end
    return false
  end
  Cast.watching = nil
  Cast.dismissedAt = g_clock.millis()
  if Cast.loadBox then
    Cast.loadBox:destroy()
    Cast.loadBox = nil
  end

  message = tostring(message or "")
  local backToList = function() openCastList() end
  if message:find("Incorrect password") or message:find("Wrong password") then
    displayInfoBox(tr('Wrong Password'), tr('The password you entered is incorrect.'), backToList)
  else
    local text = (message ~= "") and message or tr('The livestream is no longer available.')
    displayInfoBox(tr('Cast Unavailable'), text, backToList)
  end
  return true
end

-- On a successful watch the client enters the game as a viewer; drop our transient
-- state and any leftover UI. Called from background.lua onGameStart.
function Cast.onGameStart()
  removeEvent(castStatusEvent)
  castStatusEvent = nil
  cancelCastRequest()
  Cast.watching = nil
  if Cast.loadBox then
    Cast.loadBox:destroy()
    Cast.loadBox = nil
  end
  Cast.closeList()
end
