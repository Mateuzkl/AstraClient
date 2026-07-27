-- Live cast (livestream) discovery for the login screen.
--
-- The game server's "livestream" system lets anyone watch a broadcasting player by
-- connecting with an empty account, password = the cast's password (empty for open
-- casts) and characterName = the caster's name. The client reuses the normal
-- g_game.loginWorld path for that. The empty account is exactly how this TFS routes
-- the connection to ProtocolGame::spectate().

-- Shared inside the client_background sandbox and referenced by background.lua.
-- The global is intentional because the module has multiple script files.
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
local expectedCastCancelError = false

local CastRequestPassword = '__astra_casts_v1__'
local CastRefreshInterval = 30000

local onLoadBoxCancel
local onPasswordConnect
local onPasswordCancel

local function cancelProtocolLogin(protocol)
  protocol:cancelLogin()
end

local function cancelGameLogin()
  g_game.cancelLogin()
end

local function clearProtocolCallbacks(protocol)
  if not protocol then
    return
  end

  protocol.onCastList = nil
  protocol.onLoginError = nil
end

local function destroyLoadBox()
  local loadBox = Cast.loadBox
  if not loadBox then
    return
  end

  disconnect(loadBox, { onCancel = onLoadBoxCancel })
  Cast.loadBox = nil
  loadBox:destroy()
end

local function destroyPasswordWindow()
  local window = passwordWindow
  if not window then
    return
  end

  window.onEnter = nil
  window.onEscape = nil
  window.castInfo = nil

  if window.okButton then
    window.okButton.onClick = nil
  end
  if window.cancelButton then
    window.cancelButton.onClick = nil
  end

  passwordWindow = nil
  window:destroy()
end

local function destroyCastWindow()
  local window = castWindow
  if not window then
    return
  end

  castWindow = nil
  window:destroy()
end

local function castBox()
  local bg = getBackground and getBackground() or nil
  if not bg or not bg.loadAfter then
    return nil
  end

  return bg.loadAfter.castScroll
end

local function setCounts(casters, viewers)
  local box = castBox()
  if not box or not box.castCount or not box.viewerCount then
    return
  end

  box.castCount:setText(string.format(
    '%d %s',
    casters,
    casters == 1 and 'Player Casting' or 'Players Casting'
  ))
  box.viewerCount:setText(string.format(
    '%d %s',
    viewers,
    viewers == 1 and 'Viewer' or 'Viewers'
  ))
end

local function cancelCastRequest()
  castRequestId = castRequestId + 1

  local protocol = castProtocol
  castProtocol = nil
  if not protocol then
    return
  end

  clearProtocolCallbacks(protocol)
  pcall(cancelProtocolLogin, protocol)
end

local function getLoginEndpoint(serverInfo)
  if type(serverInfo) ~= 'table' then
    return nil
  end

  local host = type(serverInfo.host) == 'string' and serverInfo.host or nil
  local port = tonumber(serverInfo.port)
  if not host or host:len() == 0 or not port or port <= 0 then
    return nil
  end

  return host, port
end

local function sortCastsByName(first, second)
  return tostring(first.name or ''):lower() < tostring(second.name or ''):lower()
end

local function refreshCastStatus()
  castStatusEvent = nil
  Cast.updateStatus()
end

local function onCastRowDoubleClick()
  Cast.watchSelected()
  return true
end

local function loginBox()
  return modules.client_entergame and modules.client_entergame.EnterGame or nil
end

-- Ask the TFS login port for the current cast list, then refresh every 30 seconds.
function Cast.updateStatus(serverInfo)
  if castStatusEvent then
    removeEvent(castStatusEvent)
    castStatusEvent = nil
  end

  cancelCastRequest()

  if serverInfo and serverInfo ~= Cast.serverInfo then
    Cast.list = {}
    setCounts(0, 0)
    if castWindow then
      Cast.populateList()
    end
  end

  if serverInfo then
    Cast.serverInfo = serverInfo
  end
  serverInfo = Cast.serverInfo

  if not castBox() or g_game.isOnline() then
    return
  end

  local host, port = getLoginEndpoint(serverInfo)
  if not host then
    return
  end

  local requestId = castRequestId
  castStatusEvent = scheduleEvent(refreshCastStatus, CastRefreshInterval)

  local version = tonumber(serverInfo.version)
  if version then
    g_game.setClientVersion(version)
    g_game.setProtocolVersion(g_game.getClientProtocolVersion(version))
  end
  g_game.chooseRsa(host)

  local protocol = ProtocolLogin.create()
  castProtocol = protocol

  local function releaseProtocol()
    if castProtocol == protocol then
      castProtocol = nil
    end
    clearProtocolCallbacks(protocol)
  end

  protocol.onCastList = function(_, casts, totalViewers)
    if requestId ~= castRequestId or castProtocol ~= protocol then
      clearProtocolCallbacks(protocol)
      return
    end

    releaseProtocol()
    Cast.list = type(casts) == 'table' and casts or {}
    table.sort(Cast.list, sortCastsByName)
    setCounts(#Cast.list, tonumber(totalViewers) or 0)

    if castWindow then
      Cast.populateList()
    end
  end

  protocol.onLoginError = function()
    if requestId == castRequestId and castProtocol == protocol then
      releaseProtocol()
    else
      clearProtocolCallbacks(protocol)
    end
  end

  local ok, err = pcall(function()
    protocol:login(host, port, '', CastRequestPassword, '', false)
  end)
  if not ok then
    releaseProtocol()
    pcall(cancelProtocolLogin, protocol)
    g_logger.warning('Could not request the Astra cast list: ' .. tostring(err))
  end
end

function Cast.terminate()
  if castStatusEvent then
    removeEvent(castStatusEvent)
    castStatusEvent = nil
  end

  cancelCastRequest()

  if Cast.watching then
    expectedCastCancelError = true
    pcall(cancelGameLogin)
  end

  Cast.watching = nil
  destroyLoadBox()
  Cast.closeList()
  Cast.list = {}
  Cast.serverInfo = nil
end

function clearExpectedCastCancelError()
  expectedCastCancelError = false
end

function openCastList()
  if g_game.isOnline() then
    return
  end

  local enterGame = loginBox()
  if enterGame then
    enterGame.hide(true)
  end

  destroyCastWindow()
  castWindow = g_ui.displayUI('castlist')
  if not castWindow then
    return
  end

  if #Cast.list == 0 then
    Cast.updateStatus()
  end
  Cast.populateList()

  castWindow:raise()
  castWindow:focus()
end

function watchSelectedCast()
  Cast.watchSelected()
end

function closeCastList()
  Cast.closeList()

  if not g_game.isOnline() and not Cast.loadBox and not Cast.watching then
    local enterGame = loginBox()
    if enterGame then
      enterGame.show()
    end
  end
end

function Cast.closeList()
  destroyPasswordWindow()
  destroyCastWindow()
end

function Cast.populateList()
  if not castWindow then
    return
  end

  local list = castWindow:getChildById('castList')
  if not list then
    return
  end

  list:destroyChildren()
  for _, cast in ipairs(Cast.list) do
    local row = g_ui.createWidget('CastListRow', list)
    row.castInfo = cast
    row.onDoubleClick = onCastRowDoubleClick

    local viewers = tonumber(cast.viewers) or 0
    local nameLabel = row:getChildById('name')
    local viewersLabel = row:getChildById('viewers')
    local lockIcon = row:getChildById('lock')

    if nameLabel then
      nameLabel:setText(cast.name or '?')
    end
    if viewersLabel then
      viewersLabel:setText(viewers == 1 and tr('1 viewer') or tr('%d viewers', viewers))
    end
    if lockIcon then
      lockIcon:setVisible(cast.haspassword and true or false)
    end
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
  if not castWindow then
    return
  end

  local list = castWindow:getChildById('castList')
  local selected = list and list:getFocusedChild() or nil
  if not selected or not selected.castInfo then
    displayErrorBox(tr('Watch Cast'), tr('Select a cast to watch.'))
    return
  end

  Cast.watch(selected.castInfo)
end

function Cast.watch(castInfo)
  if type(castInfo) ~= 'table' then
    return
  end

  if castInfo.haspassword then
    Cast.promptPassword(castInfo)
  else
    Cast.connect(castInfo, '')
  end
end

onPasswordConnect = function()
  local window = passwordWindow
  if not window then
    return
  end

  local castInfo = window.castInfo
  local password = window.passwordEnter and window.passwordEnter:getText() or ''
  destroyPasswordWindow()

  if castInfo then
    Cast.connect(castInfo, password)
  end
end

onPasswordCancel = function()
  destroyPasswordWindow()
end

function Cast.promptPassword(castInfo)
  if type(castInfo) ~= 'table' then
    return
  end

  destroyPasswordWindow()
  passwordWindow = g_ui.displayUI('castpassword')
  if not passwordWindow then
    return
  end

  passwordWindow.castInfo = castInfo
  passwordWindow.caster:setText(tr('Cast: %s', castInfo.name or '?'))

  local edit = passwordWindow.passwordEnter
  if edit then
    edit:focus()
  end

  passwordWindow.onEnter = onPasswordConnect
  passwordWindow.onEscape = onPasswordCancel
  passwordWindow.okButton.onClick = onPasswordConnect
  passwordWindow.cancelButton.onClick = onPasswordCancel
end

onLoadBoxCancel = function()
  local loadBox = Cast.loadBox
  if loadBox then
    disconnect(loadBox, { onCancel = onLoadBoxCancel })
  end
  Cast.loadBox = nil

  expectedCastCancelError = true
  pcall(cancelGameLogin)
  Cast.watching = nil
  openCastList()
end

function Cast.connect(castInfo, password)
  if g_game.isOnline() or type(castInfo) ~= 'table' then
    return
  end

  local port = tonumber(castInfo.port)
  if not castInfo.host or not port then
    displayErrorBox(tr('Watch Cast'), tr('This cast has no reachable server.'))
    return
  end

  expectedCastCancelError = false
  Cast.watching = castInfo
  Cast.closeList()
  destroyLoadBox()

  Cast.loadBox = displayCancelBox(tr('Please wait'), tr('Connecting to livestream...'))
  if Cast.loadBox then
    connect(Cast.loadBox, { onCancel = onLoadBoxCancel })
  end

  local ok, err = pcall(function()
    g_game.loginWorld(
      '',
      password or '',
      castInfo.world or 'Cast',
      castInfo.host,
      port,
      castInfo.name,
      '',
      '',
      nil
    )
  end)

  if not ok then
    g_logger.error('Cast connect failed: ' .. tostring(err))
    Cast.watching = nil
    destroyLoadBox()
    displayErrorBox(tr('Watch Cast'), tr('Could not connect to the livestream.'))
    openCastList()
  end
end

function handleCastLoginError(message, code)
  if expectedCastCancelError then
    local errorText = tostring(message or ''):lower()
    local isExpectedCancel = code == 2 or code == 125 or code == 995 or errorText == ''
      or errorText:find('operation canceled', 1, true)
      or errorText:find('operation cancelled', 1, true)

    expectedCastCancelError = false
    if isExpectedCancel then
      return true
    end
  end

  if not Cast.watching then
    return false
  end

  Cast.watching = nil
  expectedCastCancelError = true
  destroyLoadBox()

  message = tostring(message or '')
  if message:find('Incorrect password') or message:find('Wrong password') then
    displayInfoBox(
      tr('Wrong Password'),
      tr('The password you entered is incorrect.'),
      openCastList
    )
  else
    local text = message ~= '' and message or tr('The livestream is no longer available.')
    displayInfoBox(tr('Cast Unavailable'), text, openCastList)
  end

  return true
end

function Cast.onGameStart()
  if castStatusEvent then
    removeEvent(castStatusEvent)
    castStatusEvent = nil
  end

  cancelCastRequest()
  Cast.watching = nil
  destroyLoadBox()
  Cast.closeList()
end
