-- Exercise production Lua with bounded mock widgets/events, no client/server needed.
local function loadProduction(path, env)
  local chunk = assert(loadfile(path))
  setfenv(chunk, setmetatable(env, {__index = _G}))
  chunk()
end
local function noop() end
local function count(values) local n = 0; for _ in pairs(values) do n = n + 1 end; return n end
local function upvalue(fn, key, replacement)
  for i = 1, math.huge do
    local name, value = debug.getupvalue(fn, i)
    assert(name, 'missing upvalue ' .. key)
    if name == key then
      if replacement ~= nil then debug.setupvalue(fn, i, replacement) end
      return value
    end
  end
end
local function scheduler()
  local pending = {}
  local function schedule(fn, delay)
    local event = {callback = fn, delay = delay}
    pending[event] = true
    return event
  end
  local function cancel(event)
    if event then pending[event] = nil; event.callback = nil end
  end
  local function fire(event, repeating)
    local fn = assert(event.callback)
    if not repeating then pending[event] = nil; event.callback = nil end
    fn()
  end
  return pending, schedule, cancel, fire
end
local function widget()
  local w = {width = 0, visible = false, sets = 0, children = 0, text = ''}
  function w:isDestroyed() return self.destroyed == true end
  function w:destroy() assert(not self.destroyed); self.destroyed = true end
  function w:show() self.visible = true end
  function w:hide() self.visible = false end
  function w:setVisible(value) self.visible = value; self.sets = self.sets + 1 end
  function w:setPercent(value) self.percent = value; self.sets = self.sets + 1 end
  function w:setWidth(value) self.width = value; self.sets = self.sets + 1 end
  function w:getWidth() return self.width end
  function w:setImageSource(value) self.image = value; self.width = 11; self.sets = self.sets + 1 end
  function w:setCreature(value) self.creature = value end
  function w:setText(value) self.text = value; self.sets = self.sets + 1 end
  function w:getText() return self.text end
  function w:setColoredText(value) self.text = value end
  function w:getChildCount() return self.children end
  function w:destroyChildren() self.children = 0 end
  w.setColor, w.setBackgroundColor, w.setMarginLeft, w.setHeight = noop, noop, noop, noop
  w.setTooltip, w.removeTooltip, w.setBorderWidth, w.setBorderColor = noop, noop, noop, noop
  w.removeEventListener, w.setImageShader, w.setImageClip, w.setImageBorder = noop, noop, noop, noop
  w.setSize, w.setOn, w.setImageColor = noop, noop, noop
  w.setMarginBottom = noop
  return w
end

do -- Public/private bursts must stop batching after silence; buffers stay bounded.
  local now, online, inputLock = 0, true, nil
  local events, schedule, cancel, fire = scheduler()
  local env = {
    MAX_LINES = 200, MAX_MESSAGE_PER_SECOND = 20,
    LOCAL_CHAT_NAME = 'Local', SERVER_LOG_NAME = 'Log', SPELL_CHANNEL_NAME = 'Spells', NPC_NAME_CHAT = 'NPCs',
    MessageTypes = {[0] = {color = 'white'}, [1] = {color = 'white'}},
    MessageModes = {Whisper = 1, Say = 2, Yell = 3},
    EVENT_TEXT_CLICK = 1, EVENT_TEXT_HOVER = 2,
    m_settings = {getOption = function() return false end},
    setStringColor = function(values, text, color) values[#values + 1] = text; values[#values + 1] = color end,
    g_clock = {millis = function() return now end}, g_game = {isOnline = function() return online end},
    cycleEvent = schedule, removeEvent = cancel, ChannelConfig = {}, Options = {removeChannel = noop},
    g_ui = {getCustomInputWidget = function() return inputLock end},
    g_client = {setInputLockWidget = function(value) inputLock = value end},
    modules = {game_console = {save = noop}}
  }
  loadProduction('modules/game_console/classes/Message.lua', env)
  loadProduction('modules/game_console/classes/TabMessages.lua', env)
  loadProduction('modules/game_console/classes/Chat.lua', env)
  local labels, pinnedLabels = {}, {}
  for i = 1, 200 do labels[i], pinnedLabels[i] = widget(), widget() end
  local bar = {addTab = function() return widget() end, updateNavigation = noop,
    removeTab = function(_, tab) tab:destroy() end}
  local chat = setmetatable({tabs = {}, tabsByName = {}, tabsById = {}, tabsServerLog = {}, tabBar = bar,
    labels = labels, readOnlyLabels = pinnedLabels, readOnly = widget(), readOnlyPanel = widget(), contentPanel = widget(),
    buffer = {moveChildToIndex = noop, reorderChildren = noop}, readOnlyBuffer = {moveChildToIndex = noop}}, {__index = env.Chat})
  env.g_chat = chat
  local function newTab(name, id)
    local tab = env.TabMessages.new(name, bar)
    tab:setId(id); chat.tabs[#chat.tabs + 1] = tab; chat.tabsByName[name] = tab
    return tab
  end
  local tab = newTab('Local', 0)
  chat.currentTab = 'Local'; tab:setCurrent(true)
  for i = 1, 10000 do tab:addMessage('', 0, 1, 'message ' .. i) end
  assert(#tab.messages == 200 and tab.activeLabels == 200 and count(events) == 1)
  assert(tab.messages[200]:getText() == 'message 10000')
  now = 1100; fire(tab.event, true)
  assert(count(events) == 0 and not tab:isInSlowMode() and tab:getMessagesPerSecond() == 0,
    'silent channels must release their batching cycle')
  for i = 1, 80 do now = now + 100; tab:addMessage('', 0, 1, 'slow ' .. i) end
  assert(count(events) == 0, 'a sustained 10 messages/s must not accumulate a lifetime message count')
  for i = 1, 20 do tab:addPrivateMessage('private ' .. i, 1, '') end
  assert(count(events) == 1, 'private messages need the same rate accounting')
  now = now + 1100
  tab:addPrivateMessage('after burst', 1, '')
  assert(count(events) == 0)
  local seen = {}
  for _, label in ipairs(labels) do
    assert(not seen[label.message], 'batch-to-inline transition must not append the last message twice')
    seen[label.message] = true
  end
  assert(labels[200].message:getText() == 'after burst')

  -- Shared labels must not be cleared by records from an inactive tab.
  local other = env.Message.new()
  local label = labels[1]; label.children = 1; label.keywords = {'owned'}
  other.label = label; other:clear()
  assert(label.children == 1 and #label.keywords == 1 and label.message ~= nil)
  label.message:clear()
  assert(label.children == 0 and label.message == nil and #label.keywords == 0)

  local npc = newTab('NPCs', 5)
  tab:setCurrent(false); npc:setCurrent(true); chat.currentTab = 'NPCs'
  for i = 1, 30 do npc:addMessage('', 0, 1, 'npc ' .. i) end
  assert(count(events) == 0 and labels[200].message:getText() == 'npc 30')
  npc:setCurrent(false); chat.currentTab = 'Local'; tab:setCurrent(true)

  -- Removing adjacent channels must not skip any, or retain root-owned dialogs.
  local weak = setmetatable({}, {__mode = 'v'})
  for i = 1, 8 do
    local channel = newTab('Channel' .. i, 10 + i)
    channel.inviteNameWindow, channel.excludeNameWindow = widget(), widget()
    inputLock = channel.inviteNameWindow
    weak[i] = channel
    if i == 8 then
      chat.readOnlyTabMessage = channel; chat.readOnly.tab = channel; channel:setReadOnlyFixed(true)
    end
  end
  online = false; chat:offline()
  assert(#chat.tabs == 1 and chat.tabs[1] == tab and count(events) == 0)
  assert(inputLock == nil and chat.readOnlyTabMessage == nil and chat.readOnly.tab == nil)
  collectgarbage('collect'); collectgarbage('collect')
  assert(count(weak) == 0, 'closed channels must be collectible, including pinned channel/dialog callbacks')

  -- Console unload must destroy its panel as well as all tab-owned windows.
  env.MessageModes = {Whisper = 1, Say = 2, Yell = 3}
  env.ChannelEvent = {Join = 1, Leave = 2, Invite = 3, Exclude = 4}
  loadProduction('modules/game_console/console.lua', env)
  local panel = widget()
  upvalue(env.terminate, 'consolePanel', panel)
  env.g_chat, env.g_channel = chat, {}
  env.g_settings, env.disconnect = {setNode = noop}, noop
  env.Communication = {saveSettings = noop}
  chat.messageHistory = {}
  env.terminate()
  assert(panel.destroyed and tab.destroyed and #chat.tabs == 0 and env.g_chat == nil and env.g_channel == nil)
end

do -- Native portrait references and unchanged UI updates.
  local targetReads = 0
  local env = {UIWidget = {}, extends = function() return {} end, SkullNone = 0, EmblemNone = 0,
    g_game = {getAttackingCreature = function() targetReads = targetReads + 1 end,
      getFollowingCreature = function() targetReads = targetReads + 1 end}}
  loadProduction('modules/corelib/table.lua', env)
  loadProduction('modules/gamelib/ui/uicreaturebutton.lua', env)
  local children = {}
  for _, id in ipairs({'creature', 'label', 'lifeBar', 'manaBar', 'skull', 'emblem', 'monster1', 'monster2', 'monster3', 'monster4'}) do
    children[id] = widget()
  end
  local button = setmetatable({getChildById = function(_, id) return children[id] end}, {__index = env.UICreatureButton})
  button:setup()
  local icons = {{id = 1, modification = false}}
  local hp, mp, monster = 80, 80, true
  local creature = {getName = function() return 'Audit' end, getHealthPercent = function() return hp end,
    getManaBarPercent = function() return mp end, getSkull = function() return 0 end,
    getEmblem = function() return 0 end, getEchoRaidVisualState = function() return -1 end,
    getIcons = function() return icons end, isMonster = function() return monster end}
  children.creature.setBorderWidth = function(self, value) self.borderWidth = value end
  children.creature.setBorderColor = function(self, value) self.borderColor = value end
  button:creatureSetup(creature, {attacking = creature})
  assert(targetReads == 0 and children.creature.borderColor == '#df3f3f', 'shared target context must avoid native getter calls')
  button:update({following = creature})
  assert(targetReads == 0 and children.creature.borderColor == '#3fdf3f', 'shared follow context must retain immediate styling')
  button.isHovered = true; button:update()
  assert(targetReads == 2 and children.creature.borderColor == '#f7f7f7', 'standalone hover updates must still read current targets')
  button.isHovered = false
  button:creatureSetup(creature)
  assert(children.lifeBar.percent == 80 and children.manaBar.percent == 80 and children.manaBar.visible,
    'equal health and mana still need separate caches')
  local changes = children.lifeBar.sets + children.manaBar.sets + children.monster1.sets
  for _ = 1, 1000 do button:creatureSetup(creature) end
  assert(changes == children.lifeBar.sets + children.manaBar.sets + children.monster1.sets,
    'unchanged values must not reset bars/icons or enqueue geometry updates')
  assert(children.monster1.width == 11, 'unchanged icons must not disappear')
  mp = -1; button:creatureSetup(creature); assert(not children.manaBar.visible)
  mp = 80; button:creatureSetup(creature); assert(children.manaBar.visible and children.manaBar.percent == 80)
  icons = {}; button:creatureSetup(creature); assert(children.monster1.width == 0)
  local weak = setmetatable({creature}, {__mode = 'v'})
  button:setCreature(nil); creature = nil
  collectgarbage('collect'); collectgarbage('collect')
  assert(children.creature.creature == nil and weak[1] == nil, 'hidden pool rows must release the native portrait owner too')
end

do -- A crowded map must not filter all spectators after filling the 30-row pool.
  local online, spectators, positionCalls, filterCalls, targetCalls, rowUpdates = true, {}, 0, 0, 0, 0
  local player = {getPosition = function() positionCalls = positionCalls + 1; return {x = 0, y = 0, z = 7} end}
  local env = {g_clock = {millis = function() return 1000 end},
    KeyBind = {getKeyBind = function() return {} end},
    g_game = {isOnline = function() return online end, getLocalPlayer = function() return player end,
      getAttackingCreature = function() targetCalls = targetCalls + 1 end,
      getFollowingCreature = function() targetCalls = targetCalls + 1 end},
    g_map = {getSpectatorsInRangeEx = function() return spectators end},
    m_interface = {getMapPanel = function() return {getVisibleDimension = function() return {width = 15, height = 11} end} end}}
  loadProduction('modules/game_battle/battle.lua', env)
  local buttons = {}
  for i = 1, 30 do
    buttons[i] = {creatureSetup = function(self, value, targetState)
      assert(targetState); self.creature = value; rowUpdates = rowUpdates + 1
    end, show = noop, hide = noop, isHidden = function() return false end,
      update = function(_, targetState) assert(targetState); rowUpdates = rowUpdates + 1 end,
      setOn = noop, setCreature = function(self, value) self.creature = value end}
  end
  local battle = {panel = {getLayout = noop}, buttons = buttons, sortType = {'byDistanceAscending'},
    window = {isVisible = function() return false end}, secondary = false}
  env.battleClasses = {battle}
  for i = 1, 500 do
    local id = i
    spectators[i] = {isLocalPlayer = function() filterCalls = filterCalls + 1; return false end,
      getHealthPercent = function() return 80 end, getPosition = function() return {x = 31 - id, y = 0, z = 7} end,
      canBeSeen = function() return true end, isPlayer = function() return false end,
      isNpc = function() return false end, isMonster = function() return false end,
      getId = function() return id end, getName = function() return string.format('Name%03d', 31 - id) end}
  end
  env.checkCreatures()
  assert(filterCalls == 30 and positionCalls == 1, 'cap filters and share the player position across filtering/sorting')
  assert(targetCalls == 2 and rowUpdates == 30, 'one target snapshot and one row update per battle tick')
  for i = 1, 30 do assert(buttons[i].creature == spectators[31 - i]) end
  battle.sortType[1] = 'byNameDescending'; env.checkCreatures()
  for i = 1, 30 do assert(buttons[i].creature == spectators[i]) end
  battle.sortType[1] = 'byHitpointsAscending'; env.checkCreatures()
  for i = 1, 30 do assert(buttons[i].creature == spectators[i], 'ties preserve age ordering') end
  local checks, filters = 0, {showPlayers = false}
  battle.filterPanel = {buttons = {getChildById = function(_, name)
    checks = checks + 1; return {isChecked = function() return filters[name] ~= false end}
  end}}
  for i = 1, 10 do spectators[i].isPlayer = function() return true end end
  env.checkCreatures()
  assert(checks == 11, 'read each filter once per battle, not once per spectator')
  for _, button in ipairs(buttons) do assert(button.creature:getId() > 10, 'disabled player filter still excludes players') end
  filters.showPlayers = true; env.checkCreatures()
  for i = 1, 30 do assert(buttons[i].creature == spectators[i], 'filter changes apply on the next tick') end
  local before = targetCalls
  env.onTargetStateChange()
  assert(targetCalls == before + 2, 'immediate target events share their native getters across all rows')
  online = false; env.checkCreatures()
  for _, button in ipairs(buttons) do assert(button.creature == nil) end
end

do -- Helper's delayed logins are session-owned, including same-character relogs.
  local events, schedule, cancel, fire = scheduler()
  local online, currentPlayer, loads, registrations, unregistrations, starts = true, nil, 0, 0, 0, 0
  local function newPlayer(name) return {getName = function() return name end, getPosition = function() return {} end} end
  currentPlayer = newPlayer('Audit')
  local env = {g_clock = {millis = function() return 0 end},
    g_game = {isOnline = function() return online end, getLocalPlayer = function() return currentPlayer end},
    modules = {game_helper = {}}, g_keyboard = {unbindKeyDown = noop}, disconnect = noop,
    cycleEvent = schedule, scheduleEvent = schedule, removeEvent = cancel}
  loadProduction('mods/game_helper/helper.lua', env)
  env.loadMenu, env.saveSettings = noop, noop
  env.loadSettings = function() loads = loads + 1 end
  env._Helper.HotkeyManager = {registerAll = function() registrations = registrations + 1 end,
    unregisterAll = function() unregistrations = unregistrations + 1 end}
  env._Helper.Shortcut = {isVisible = function() return false end, destroyPanel = noop}
  for _, name in ipairs({'FullDustAlarm', 'LowSupplyAlarm', 'PrivateMessageAlarm', 'LowHealthAlarm', 'LowManaAlarm'}) do
    env._Helper[name] = {resetCheckbox = noop, check = noop}
  end
  for _, name in ipairs({'AutoHaste', 'ExerciseTraining', 'Timer'}) do
    local event
    env._Helper[name] = {onLogin = function() starts = starts + 1; event = schedule(noop, 100) end,
      onLogout = function() cancel(event); event = nil end}
  end
  local function callbacks()
    local stale = {}; for event in pairs(events) do stale[#stale + 1] = event.callback end; return stale
  end
  local function runDelay(delay)
    local selected = {}; for event in pairs(events) do if event.delay == delay then selected[#selected + 1] = event end end
    for _, event in ipairs(selected) do fire(event) end
  end
  for _ = 1, 20 do
    env.online(); env.online()
    assert(count(events) == 7, 'duplicate game-start must not create another cycle/login timers')
    local stale = callbacks()
    online = false; env.offline()
    assert(count(events) == 1, 'only the owned offline GC may remain after logout')
    currentPlayer = newPlayer('Audit'); online = true; env.online()
    local before = count(events)
    for _, fn in ipairs(stale) do fn() end
    assert(loads == 0 and starts == 0 and count(events) == before,
      'old login timers must not run on a later login of the same character')
    online = false; env.offline(); runDelay(500)
    assert(count(events) == 0)
    currentPlayer = newPlayer('Audit'); online = true
  end
  env.online(); runDelay(500)
  assert(loads == 1 and registrations == 1)
  local staleApply = callbacks()
  env.offline(); env.online()
  for _, fn in ipairs(staleApply) do fn() end
  assert(loads == 1, 'nested UI apply callbacks are owned by their login session too')
  runDelay(500); runDelay(200); runDelay(100); runDelay(1000)
  runDelay(1500); runDelay(1600); runDelay(1700)
  assert(loads == 2 and starts == 3 and count(events) == 4)
  local stale = callbacks()
  upvalue(env.helperCycleEvent, 'lastPlayerName', 'Audit')
  env.terminate()
  assert(count(events) == 0 and unregistrations > 0, 'unload must stop main and component cycles plus hotkeys')
  assert(upvalue(env.helperCycleEvent, 'lastPlayerName') == nil, 'unload must clear the actual private character identity')
  for _, fn in ipairs(stale) do fn() end
  env.online(); env.helperCycleEvent()
  assert(count(events) == 0, 'late game-start/tick after unload must not restart Helper')
end

do -- Terminal spam must not grow the copy buffer or allocate rows indefinitely.
  local events, schedule, cancel, fire = scheduler()
  local created, rows, depth, reorders, layouts = 0, {}, 0, 0, 0
  local buffer, selection = widget(), widget()
  local layout = {disableUpdates = function() depth = depth + 1 end,
    enableUpdates = function() depth = depth - 1 end, update = function() layouts = layouts + 1 end}
  function buffer:getLayout() return layout end
  function buffer:getChildCount() return #rows end
  function buffer:getChildByIndex(index) return rows[index] end
  function buffer:reorderChildren(ordered)
    assert(#ordered == #rows); rows = ordered; reorders = reorders + 1
  end
  function buffer:destroyChildren() for _, row in ipairs(rows) do row:destroy() end; rows = {} end
  local env = {LogDebug = 1, LogInfo = 2, LogWarning = 3, LogError = 4,
    runinsandbox = function() return {} end, scheduleEvent = schedule, removeEvent = cancel,
    g_ui = {createWidget = function(_, parent)
      assert(parent == buffer); created = created + 1
      local row = widget(); row.setId = noop; row.setColor = function(self, value) self.color = value end
      rows[#rows + 1] = row; return row
    end}, g_settings = {setList = noop, setNode = noop},
    g_keyboard = {unbindKeyDown = noop}, g_logger = {setOnLog = noop}}
  env._G = env
  loadProduction('modules/client_terminal/terminal.lua', env)
  upvalue(env.flushLines, 'terminalBuffer', buffer)
  env.terminalSelectText = selection
  local function flush()
    assert(count(events) == 1); fire(next(events))
    assert(count(events) == 0 and depth == 0)
    local lines = upvalue(env.flushLines, 'allLines')
    local texts = {}
    for i, line in ipairs(lines) do texts[i] = line.text end
    assert(selection.text == (#texts > 0 and '\n' .. table.concat(texts, '\n') or ''),
      'copy text must exactly match the bounded visible log, with no stale suffixes')
  end
  for i = 1, 10000 do env.addLine('burst ' .. i, 'pink') end
  assert(#upvalue(env.addLine, 'cachedLines') == 128, 'pending logs must be bounded even before a flush')
  assert(next(events).delay == 50, 'terminal display should batch spam without altering game/bot timers')
  flush()
  assert(#rows == 128 and created == 128 and rows[1].text == 'burst 9873' and rows[128].text == 'burst 10000')
  for i = 1, 3000 do env.addLine(string.rep('x', i % 80 + 1), 'yellow'); flush() end
  assert(#rows == 128 and created == 128 and #selection.text <= 128 * 81,
    'continuous log replacement must reuse rows and bound the copy buffer')
  local before = reorders
  for i = 1, 64 do env.addLine('batch ' .. i, 'red') end
  flush()
  assert(reorders == before + 1 and rows[65].text == 'batch 1' and rows[128].text == 'batch 64',
    'a batch must rotate all reused rows once and preserve their final order')
  assert(rows[128].color == '#ff4444', 'reused rows must refresh log severity colors')

  local window = widget()
  function window:isVisible() return self.visible end
  window.raise, window.focus = noop, noop
  upvalue(env.show, 'terminalWindow', window)
  local oldText, oldLayouts, oldReorders = selection.text, layouts, reorders
  for i = 1, 10000 do env.addLine('hidden ' .. i, 'white') end
  assert(count(events) == 1); fire(next(events))
  assert(#upvalue(env.flushLines, 'allLines') == 128 and layouts == oldLayouts and reorders == oldReorders and selection.text == oldText,
    'hidden terminal must retain bounded logs without wrapping text or rebuilding layouts')
  env.show()
  assert(rows[1].text == 'hidden 9873' and rows[128].text == 'hidden 10000' and created == 128 and layouts == oldLayouts + 1,
    'show must render the latest hidden history once and reuse the bounded row pool')
  env.show(); assert(layouts == oldLayouts + 1, 'showing unchanged terminal must not rebuild its layout')
  env.clear(); assert(#rows == 0 and selection.text == '' and #upvalue(env.flushLines, 'allLines') == 0)
  env.addLine('discard on clear', 'white'); env.clear()
  assert(count(events) == 0 and #upvalue(env.addLine, 'cachedLines') == 0, 'clear must cancel pending display work too')
  env.addLine('last log', 'white'); local stale = next(events).callback
  env.terminate()
  assert(count(events) == 0 and env.terminalSelectText == nil and upvalue(env.flushLines, 'terminalBuffer') == nil)
  stale(); env.addLine('after unload', 'white')
  assert(count(events) == 0 and #upvalue(env.addLine, 'cachedLines') == 0)
end

print('Memory hotpaths: chat, terminal spam, creature owners, battle cap/sort and Helper sessions passed')
