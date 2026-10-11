-- Opt-in integration test against a server/account explicitly supplied by its owner.
-- No movement, combat, commands, purchases or server mutation. Separate profile.
scheduleEvent(function()
  local config = json.decode(g_resources.readFileContents('/session-config.json'))
  local login, sessionKey, character, round = nil, '', nil, 0
  local stopping, finished = false, false
  local function fail(message)
    if finished then return end
    finished = true
    if login then login:cancelLogin(); login = nil end
    g_logger.error('[CXX23 LIVE] FAIL: ' .. message)
    if g_game.isOnline() then g_game.safeLogout() end
    scheduleEvent(g_app.exit, 500)
  end
  local function enter()
    g_game.loginWorld(config.account, config.password, character.worldName,
      character.worldIp, character.worldPort, character.name, '', sessionKey)
  end
  local function closeSession()
    stopping = true
    g_game.safeLogout()
  end
  connect(g_game, {
    onLoginError = function(message) fail('world login: ' .. message) end,
    onConnectionError = function(message)
      -- TFS closes the socket after accepting safeLogout. onGameEnd below
      -- is still mandatory; an unrelated disconnect must fail the test.
      if not stopping then fail('connection: ' .. message) end
    end,
    onGameStart = function()
      g_logger.info('[CXX23 LIVE] world start received')
      round = round + 1
      stopping = false
      scheduleEvent(function()
        local player = g_game.getLocalPlayer()
        if not player or player:getName():lower() ~= config.character:lower() then
          fail('unexpected/missing character'); return
        end
        if player:getHealth() <= 0 or not player:getPosition() then
          fail('missing player state'); return
        end
        g_logger.info('[CXX23 LIVE] received character, health, outfit and position; session ' .. round)
        if round == 1 then
          modules.client_settings.setOption('minimapHD', true)
          modules.game_minimap.toggleFullMap()
          scheduleEvent(function()
            modules.game_minimap.toggleFullMap()
            modules.game_cyclopedia.toggleRedirect('Map')
            scheduleEvent(function()
              g_app.doScreenshot('cpp23-live-map.png')
              modules.game_cyclopedia.Cyclopedia.endGame()
              modules.client_settings.setOption('minimapHD', false)
              scheduleEvent(closeSession, 1000)
            end, 2000)
          end, 1000)
        else
          scheduleEvent(closeSession, 1500)
        end
      end, 1500)
    end,
    onGameEnd = function()
      if finished then return end
      if not stopping then fail('unexpected disconnect'); return end
      if round == 1 then
        scheduleEvent(enter, 1000)
      else
        finished = true
        g_logger.info('[CXX23 LIVE] PASS: real login, encrypted world traffic, HD/full map/Cyclopedia, logout, reconnect, classic mode, clean logout')
        config.account, config.password = nil, nil
        login = nil
        scheduleEvent(g_app.exit, 500)
      end
    end
  }, true)
  -- Production loads this lazily. Do not send an unencrypted legacy packet
  -- simply because an automated test runs before the login window is ready.
  g_modules.ensureModuleLoaded('game_things')
  g_modules.ensureModuleLoaded('game_features')
  g_game.setClientVersion(config.version)
  g_game.setProtocolVersion(g_game.getClientProtocolVersion(config.version))
  g_game.setCustomProtocolVersion(0)
  g_game.setCustomOs(-1)
  g_game.chooseRsa(config.host)
  if not g_game.getFeature(GameExtendedOpcode) then g_game.setCustomOs(2) end
  g_modules.ensureModuleLoaded('game_things')
  modules.game_things.load()
  if g_proxy then g_proxy.clear() end
  g_logger.info(string.format('[CXX23 LIVE] profile version=%d protocol=%d RSA=%s checksum=%s account-names=%s',
    g_game.getClientVersion(), g_game.getProtocolVersion(), tostring(g_game.getFeature(GameLoginPacketEncryption)),
    tostring(g_game.getFeature(GameProtocolChecksum)), tostring(g_game.getFeature(GameAccountNames))))
  login = ProtocolLogin.create()
  login.onLoginError = function(_, message) fail('account login: ' .. message) end
  login.onSessionKey = function(_, key) sessionKey = key end
  login.onCharacterList = function(_, characters)
    for _, entry in ipairs(characters) do
      if entry.name:lower() == config.character:lower() then character = entry; break end
    end
    if not character then fail('requested character not in list'); return end
    scheduleEvent(enter, 200)
  end
  login:login(config.host, config.port, config.account, config.password, '', false)
  scheduleEvent(function() if not finished then fail('integration timeout') end end, 40000)
end, 500)
