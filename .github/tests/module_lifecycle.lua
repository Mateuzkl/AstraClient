-- Exercise production functions; no client, graphics, credentials or server needed.
local function loadProduction(path, env)
  local chunk = assert(loadfile(path))
  setfenv(chunk, setmetatable(env, {__index = _G}))
  chunk()
end
local function count(values)
  local n = 0
  for _ in pairs(values) do n = n + 1 end
  return n
end
local function read(path)
  local file = assert(io.open(path, 'rb'))
  local text = file:read('*a')
  file:close()
  return text
end

-- Gameplay lifecycle names must not overwrite another module's init/terminate.
for _, path in ipairs({
  'mods/game_memorial/memorial.otmod', 'mods/game_blessing/blessing.otmod',
  'mods/game_dailyreward/dailyreward.otmod', 'mods/game_quickloot/quickloot.otmod',
  'mods/game_killperf/killperf.otmod', 'modules/game_bossdifficulty/game_bossdifficulty.otmod',
  'modules/game_offsets/offsets.otmod', 'modules/game_walking/walking.otmod'
}) do
  assert(read(path):match('sandboxed:%s*true'), path .. ' must own its lifecycle')
end

do
  local windows, connected = {}, {}
  local function newWindow()
    local window = {hide = function() end, show = function() end}
    windows[window] = true
    function window:destroy() assert(windows[self], 'double destroy'); windows[self] = nil end
    return window
  end
  local env = {
    g_app = {}, g_ui = {displayUI = newWindow, loadUI = newWindow, getRootWidget = function() return {} end},
    connect = function(_, handlers) for _, fn in pairs(handlers) do connected[fn] = true end end,
    disconnect = function(_, handlers) for _, fn in pairs(handlers) do connected[fn] = nil end end
  }
  for _, path in ipairs({'mods/client_init/client_init.lua', 'mods/game_lootsplitter/lootsplitter.lua'}) do
    env.init, env.terminate = nil, nil
    loadProduction(path, env)
    local init, terminate = rawget(env, 'init'), rawget(env, 'terminate')
    assert(type(init) == 'function', path .. ' must define init')
    assert(type(terminate) == 'function', path .. ' must define terminate')
    for _ = 1, 20 do
      init(); terminate()
      assert(count(windows) == 0, path .. ' retained a window')
      assert(count(connected) == 0, path .. ' retained a callback')
    end
  end
  local hintsEnv = {g_ui = env.g_ui}
  loadProduction('mods/game_hints/hint.lua', hintsEnv)
  assert(rawget(hintsEnv, 'init') and rawget(hintsEnv, 'terminate'), 'hints must own their lifecycle')
  hintsEnv.init()
  hintsEnv.showHint('audit'); hintsEnv.showHint('audit')
  assert(count(windows) == 1, 'hint window must not be duplicated')
  hintsEnv.terminate()
  assert(count(windows) == 0, 'hints must destroy their own windows')
end

do
  local handlers, events, closed, destroyed, setups = {}, {}, 0, false, 0
  local parent = {moveChildToIndex = function() end, getChildren = function() return {} end}
  local window = {
    setup = function() end, close = function() closed = closed + 1 end, setId = function() end,
    destroy = function() destroyed = true end, isDestroyed = function() return destroyed end,
    minimize = function() end, isVisible = function() return false end,
    getParent = function() return parent end, getMinimumHeight = function() return 50 end, setHeight = function() end
  }
  local env = {
    g_game = {}, g_ui = {importStyle = function() end, createWidget = function() return window end},
    m_interface = {getContainerPanel = function() end, addToPanels = function() return true end},
    PartyClass = {configure = function() end, setup = function() end, setName = function() end,
      panel = {setSortType = function() end}, sortType = {}},
    table = setmetatable({empty = function() return false end}, {__index = table}),
    connect = function(_, values) for key, fn in pairs(values) do handlers[key] = fn end end,
    disconnect = function(_, values) for key, fn in pairs(values) do assert(handlers[key] == fn); handlers[key] = nil end end,
    scheduleEvent = function(fn) local event = {}; events[event] = fn; return event end,
    removeEvent = function(event) if event then events[event] = nil end end
  }
  loadProduction('mods/game_party_list/partyList.lua', env)
  env.setupPartyPanel = function() setups = setups + 1 end
  env.init()
  assert(handlers.onGameStart == nil and handlers.onGameEnd == rawget(env, 'offline'))
  local config = {name = 'Audit', battleListFilters = {}, battleListSortOrder = {'byAgeAscending'}, contentHeight = 50}
  env.onPlayerLoad(config)
  local stale = next(events) and events[next(events)]
  env.onPlayerLoad(config)
  assert(count(events) == 1, 'party setup must replace its previous timer')
  handlers.onGameEnd()
  assert(closed == 2 and count(events) == 0, 'game end closes party list and cancels setup')
  env.onPlayerLoad(config)
  env.terminate()
  assert(destroyed and count(events) == 0 and count(handlers) == 0)
  stale()
  assert(setups == 0, 'stale party setup must not access a destroyed window')
end

do
  local handlers, unbound, shown = {}, 0, 0
  local env = {
    KeyBind = {getKeyBind = function() return {} end}, G = {}, modules = {}, gameRootPanel = {},
    g_game = {isLogging = function() return false end}, g_settings = {remove = function() end},
    g_clock = {millis = function() return 0 end},
    g_keyboard = {unbindKeyDown = function(key) assert(key == 'Alt+F4'); unbound = unbound + 1 end},
    LoginEvent = {destroyLoadBox = function() end, reset = function() end},
    connect = function(_, values) for key, fn in pairs(values) do handlers[key] = fn end end,
    disconnect = function(_, values) for key, fn in pairs(values) do assert(handlers[key] == fn); handlers[key] = nil end end,
    removeEvent = function() end
  }
  loadProduction('modules/client_entergame/entergame.lua', env)
  local enterGameEnd = assert(env.EnterGame.onGameEnd)
  for _ = 1, 20 do
    loadProduction('modules/client_entergame/characterlist.lua', env)
    assert(env.EnterGame.onGameEnd == enterGameEnd, 'character list must not replace login callbacks')
    env.CharacterList.destroyLoadBox = function() end
    env.CharacterList.showAgain = function() shown = shown + 1 end
    env.CharacterList.init()
    assert(handlers.onGameEnd and handlers.onGameEnd ~= enterGameEnd)
    enterGameEnd(); handlers.onGameEnd()
    env.CharacterList.terminate()
    assert(count(handlers) == 0)
  end
  assert(unbound == 20 and shown == 20, 'both production game-end paths must run independently')
end

do
  local env = {UIWidget = {}, extends = function() return {} end, g_ui = {}}
  local function newTab()
    return {setId = function() end, setText = function() end, setWidth = function() end,
      getTextSize = function() return {width = 50} end, getPaddingLeft = function() return 0 end,
      getPaddingRight = function() return 0 end, insertLuaCall = function() end, mergeStyle = function() end,
      setDraggable = function() end, setMarginLeft = function() end}
  end
  env.g_ui.createWidget = newTab
  for _, spec in ipairs({{'uitabbar', 'UITabBar'}, {'uimovabletabbar', 'UIMoveableTabBar'}}) do
    loadProduction('modules/corelib/ui/' .. spec[1] .. '.lua', env)
    for _, alreadyDestroyed in ipairs({false, true}) do
      local destroyed, calls = alreadyDestroyed, 0
      local panel = {isDestroyed = function() return destroyed end, destroy = function()
        assert(not destroyed, 'tab panel must not be destroyed twice'); destroyed = true; calls = calls + 1
      end}
      local bar = {tabs = {}, getStyleName = function() return 'AuditTabBar' end, selectTab = function() end}
      local tab = env[spec[2]].addTab(bar, 'Audit', panel)
      tab.onDestroy(); tab.onDestroy()
      assert(destroyed and tab.tabPanel == nil and calls == (alreadyDestroyed and 0 or 1))
    end
  end
end

do
  local queued, setters = {}, 0
  local env = {UITextEdit = {}, addEvent = function(fn) queued[#queued + 1] = fn end}
  loadProduction('modules/corelib/ui/uitextedit.lua', env)
  for _, axis in ipairs({'vertical-scrollbar', 'horizontal-scrollbar'}) do
    for _, state in ipairs({'alive', 'destroyed', 'detached', 'parent-destroyed', 'missing', 'scrollbar-destroyed'}) do
      local scrollbar = {isDestroyed = function() return state == 'scrollbar-destroyed' end}
      local parent = {isDestroyed = function() return state == 'parent-destroyed' end,
        getChildById = function() if state ~= 'missing' then return scrollbar end end}
      local widget = {
        isDestroyed = function() return state == 'destroyed' end,
        getParent = function() if state ~= 'detached' then return parent end end,
        setVerticalScrollBar = function(_, bar) assert(bar == scrollbar); setters = setters + 1 end,
        setHorizontalScrollBar = function(_, bar) assert(bar == scrollbar); setters = setters + 1 end
      }
      env.UITextEdit.onStyleApply(widget, 'TextEdit', {[axis] = 'scrollbar'})
      local callback = table.remove(queued)
      assert(callback); callback()
    end
  end
  assert(setters == 2, 'only the two live scrollbar setups should execute')
end

do
  local root, parent, registrations = {}, {}, {}
  local env = {rootWidget = root, modules = {}, m_settings = {getGeneralHotkeyWidget = function() end}, g_keyboard = {}}
  env.table = setmetatable({find = function(values, needle)
    for index, value in ipairs(values) do if value == needle then return index end end
  end}, {__index = table})
  for _, name in ipairs({'KeyDown', 'KeyUp', 'KeyPress'}) do
    env.g_keyboard['bind' .. name] = function(key, fn, widget, alone)
      registrations[#registrations + 1] = {kind = name, key = key, fn = fn, widget = widget or root,
        alone = name ~= 'KeyPress' and alone == true}
    end
    env.g_keyboard['unbind' .. name] = function(key, fn, widget, alone)
      assert(fn, 'must not remove other owners by passing a nil callback')
      for i, binding in ipairs(registrations) do
        if binding.kind == name and binding.key == key and binding.fn == fn
            and binding.widget == (widget or root) and binding.alone == (name ~= 'KeyPress' and alone == true) then
          table.remove(registrations, i)
          break
        end
      end
    end
  end
  loadProduction('modules/corelib/keybinds.lua', env)
  local down, up, press, unrelated = function() end, function() end, function() end, function() end
  local data = {jsonName = 'AuditAction', firstKey = 'Escape', secondKey = 'Ctrl+S',
    bindKeyDown = down, bindKeyUp = up, bindKeyPress = press}
  env.KeyBinds.Hotkeys = {Audit = {Action = data}}
  env.Options = {hotkeySets = {Default = {chatOn = {
    {actionsetting = {action = 'AuditAction'}, keysequence = 'Esc'},
    {actionsetting = {action = 'AuditAction'}, keysequence = 'Ctrl+F'}, -- additional primary alias
    {actionsetting = {action = 'AuditAction'}, keysequence = 'Ctrl+F'}, -- duplicate row
    {actionsetting = {action = 'AuditAction'}, keysequence = 'Ctrl+S', secondary = true}
  }, chatOff = {{actionsetting = {action = 'AuditAction'}, keysequence = 'Alt+F'}}}}}
  local binding = env.KeyBind:getKeyBind('Audit', 'Action')
  binding:active(parent, true)
  env.g_keyboard.bindKeyDown('Escape', unrelated)
  for _ = 1, 20 do env.KeyBinds:setupAndReset('Default', 'chatOn') end
  assert(#registrations == 10, 'three aliases * three event kinds plus unrelated handler')
  for _, registration in ipairs(registrations) do assert(registration.widget == root and not registration.alone) end
  binding.repeatable = false
  for _ = 1, 20 do binding:active(root) end
  assert(#registrations == 10, 'activation must not duplicate callbacks already installed by the profile')
  binding:deactive()
  assert(#registrations == 1 and registrations[1].fn == unrelated, 'deactivation preserves other owners')
  env.KeyBinds:setupAndReset('Default', 'chatOff')
  assert(#registrations == 4, 'switching profile does not retain old aliases')
  env.KeyBinds:reset()
  assert(#registrations == 1 and registrations[1].fn == unrelated)
end

do
  local events, players, hiddenCursors, fullscreen = {}, {}, 0, false
  local function schedule(fn)
    local event = {}; events[event] = fn; return event
  end
  local function newPlayer()
    local player = {visible = true, destroyed = false}
    local function button()
      return {on = false, setOn = function(self, on) self.on = on end,
        isOn = function(self) return self.on end, getWidth = function() return 80 end}
    end
    player.timeline = {title = {setText = function() end}, bar = {},
      playPause = button(), fullscreen = button(), volume = button(),
      volumeFill = {setWidth = function() end}, setOpacity = function() end,
      isDestroyed = function() return player.destroyed end}
    player.video = {setVideoSource = function() end, getVolume = function() return 1 end,
      play = function() end, pause = function() end, isPaused = function() return false end,
      isDestroyed = function() return player.destroyed end}
    player.resizeRight, player.resizeBottom = {show = function() end, hide = function() end}, {show = function() end, hide = function() end}
    function player:setSize(size) self.size = size end
    function player:getSize() return self.size end
    function player:isVisible() return self.visible end
    function player:isDestroyed() return self.destroyed end
    function player:destroy()
      assert(not self.destroyed, 'double destroy')
      self.destroyed = true
      self.timeline.fullscreen = nil -- native destruction clears children's fields first
      if self.onDestroy then self.onDestroy(self) end
    end
    players[#players + 1] = player
    return player
  end
  local env = {
    g_ui = {displayUI = newPlayer},
    connect = function(object, handlers) for key, fn in pairs(handlers) do object[key] = fn end end,
    disconnect = function(object, handlers) for key, fn in pairs(handlers) do if object[key] == fn then object[key] = nil end end end,
    scheduleEvent = schedule, removeEvent = function(event) if event then events[event] = nil end end,
    g_mouse = {pushCursor = function() hiddenCursors = hiddenCursors + 1 end,
      popCursor = function() hiddenCursors = hiddenCursors - 1 end},
    g_window = {getMousePosition = function() return {x = 10, y = 10} end,
      isFullscreen = function() return fullscreen end, setFullscreen = function(value) fullscreen = value end,
      getSize = function() return {width = 1920, height = 1080} end},
    g_effects = {fadeOut = function() end, cancelFade = function() end}
  }
  loadProduction('modules/client_videoplayer/video_player.lua', env)
  for _, directDestroy in ipairs({false, true}) do
    local player = env.g_videoPlayer.create('Audit', '/audit.webm', 100, 100)
    player.onMouseMove(player, {x = 10, y = 10}, {x = 1, y = 0})
    local stale = {}
    for _, fn in pairs(events) do stale[#stale + 1] = fn end
    local idle = events[player.mouseCheckEvent]; events[player.mouseCheckEvent] = nil; idle()
    assert(hiddenCursors == 1)
    player.timeline.fullscreen.onClick()
    assert(fullscreen and player.fullscreenResizeEvent)
    player.visible = false
    if directDestroy then player:destroy() else env.g_videoPlayer.destroy(player) end
    assert(count(events) == 0 and hiddenCursors == 0 and not fullscreen)
    assert(count(env.g_videoPlayer.players) == 0)
    for _, fn in ipairs(stale) do fn() end
    assert(count(events) == 0, 'stale callbacks must not reschedule a destroyed player')
  end
  local first = env.g_videoPlayer.create('Audit', '/same.webm', 100, 100)
  first.visible = false
  env.g_videoPlayer.create('Audit', '/same.webm', 100, 100)
  assert(first.destroyed, 'replacing a hidden player destroys it')
  env.g_videoPlayer.create('Audit', '/other.webm', 100, 100).visible = false
  env.g_videoPlayer.terminate()
  assert(count(events) == 0 and count(env.g_videoPlayer.players) == 0)
  for _, player in ipairs(players) do assert(player.destroyed) end
end

do
  local online, setups = false, {}
  local env = {Options = {actionBar = {}}, g_game = {isOnline = function() return online end},
    m_interface = {gameMapPanel = {}},
    table = setmetatable({insert = function(list, value) table.insert(list, value) end}, {__index = table})}
  loadProduction('modules/game_actionbar/actionbar.lua', env)
  local bars = {}
  for i = 1, 9 do
    env.Options.actionBar[i] = {isVisible = false}
    bars[i] = {setOn = function() end}
  end
  for i = 1, math.huge do
    local name = debug.getupvalue(env.onCreateActionBars, i)
    if not name then break end
    if name == 'actionBars' then debug.setupvalue(env.onCreateActionBars, i, bars) end
  end
  env.setupActionBar = function(n) setups[#setups + 1] = n end
  env.resizeLockButtons, env.updateGameMapPanelMargin = function() end, function() end
  env.onCreateActionBars()
  assert(#setups == 0, 'hidden action bars must stay unallocated before login')
  env.Options.actionBar[2].isVisible = true
  env.onCreateActionBars(); env.onCreateActionBars()
  assert(#setups == 2 and setups[1] == 2 and setups[2] == 2)
  for i = 1, math.huge do
    local name, value = debug.getupvalue(env.onCreateActionBars, i)
    if not name then break end
    if name == 'activeActionBars' then assert(#value == 1, 'visible bars must not accumulate on rebuild') end
  end
  setups = {}; online = true
  env.onCreateActionBars()
  assert(#setups == 9, 'online rebuild must still configure hotkeys on all hidden bars')
end

print('Audited module lifecycle and lazy startup: OK')
