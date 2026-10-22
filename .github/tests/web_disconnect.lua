-- Exercise the real error/game-end handlers without a server, GPU or page reload.
local function loadProduction(path, env)
  setmetatable(env, {__index = _G})
  local chunk = assert(loadfile(path)); setfenv(chunk, env); chunk()
end
for _, browser in ipairs({true, false}) do
  for _, wasOnline in ipairs({true, false}) do
    local online, events, handlers, shownLogin, shownCharacters = wasOnline, {}, {}, 0, 0
    local env = {
      G = {}, modules = {}, ClientSecurity = {isBrowser = function() return browser end},
      g_game = {isOnline = function() return online end, isLogging = function() return false end,
        getProtocolGame = function() return nil end},
      g_clock = {millis = function() return 100000 end},
      g_settings = {remove = function() end},
      g_keyboard = {unbindKeyDown = function() end},
      g_client = {setInputLockWidget = function() end},
      LoginEvent = {destroyLoadBox = function() end, reset = function() end},
      connect = function(_, values) for key, value in pairs(values) do handlers[key] = value end end,
      disconnect = function(_, values) for key in pairs(values) do handlers[key] = nil end end,
      removeEvent = function(event) if event then events[event] = nil end end,
      addEvent = function(callback) events[callback] = true; return callback end,
      tr = function(text) return text end, translateNetworkError = function() return 'Connection lost' end,
      displayErrorBox = function() return {destroy = function() end} end,
      EnterGame = {show = function() shownLogin = shownLogin + 1 end},
      g_app = {exit = function() error('network error must not exit') end,
        restart = function() error('network error must not restart') end}
    }
    loadProduction('modules/client_entergame/characterlist.lua', env)
    env.CharacterList.destroyLoadBox = function() end
    env.CharacterList.hide = function(login) assert(login); shownLogin = shownLogin + 1 end
    env.CharacterList.showAgain = function() shownCharacters = shownCharacters + 1 end
    env.CharacterList.init()
    handlers.onConnectionError('connection reset', 10054)
    online = false
    if wasOnline then handlers.onGameEnd() end
    local late = next(events)
    for event in pairs(events) do events[event] = nil; event() end
    assert(shownLogin == (browser and 1 or 0))
    assert(shownCharacters == (browser and 0 or 1), 'native character-list return stays unchanged')
    env.CharacterList.terminate()
    if late then late() end -- Cancellation alone cannot prevent an already-dequeued callback.
    assert(next(events) == nil and next(handlers) == nil)
  end
end
print('Web disconnect returns to in-client login without restarting; native preserved: PASS')
