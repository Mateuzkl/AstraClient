-- Production Wheel functions with deterministic UI/network doubles; no server or files are modified.
local function loadProduction(path, env)
  local chunk = assert(loadfile(path))
  setfenv(chunk, env)
  chunk()
end
local function count(values)
  local n = 0
  for _ in pairs(values) do n = n + 1 end
  return n
end
local function setUpvalue(fn, wanted, value)
  for i = 1, 100 do
    local name = debug.getupvalue(fn, i)
    if not name then break end
    if name == wanted then debug.setupvalue(fn, i, value); return end
  end
  error('missing production state: ' .. wanted)
end
local function fixture()
  local state = {roots = {}, handlers = {}, events = {}, sent = {}, writes = {}, loaded = false,
    online = true, vocation = 8, errors = {}}
  local function window()
    local widget = {visible = true, destroyed = false}
    state.roots[widget] = true
    function widget:destroy()
      assert(not self.destroyed, 'double destroy')
      self.destroyed = true
      state.roots[self] = nil
    end
    function widget:isDestroyed() return self.destroyed end
    function widget:hide() assert(not self.destroyed); self.visible = false end
    function widget:show() assert(not self.destroyed); self.visible = true end
    function widget:isVisible() return self.visible end
    return widget
  end
  local env = setmetatable({
    g_game = {isOnline = function() return state.online end,
      sendGemAtelierAction = function(...) state.sent[#state.sent + 1] = {...} end},
    LoadedPlayer = {isLoaded = function() return state.loaded end,
      getVocation = function() return state.vocation end, getId = function() return 119 end},
    g_ui = {displayUI = function() error('Wheel must not eagerly allocate UI') end,
      loadUI = function() error('Wheel must not eagerly allocate UI') end},
    g_client = {setInputLockWidget = function(widget) state.inputLock = widget end},
    g_resources = {
      fileExists = function(path) return path:find('/characterdata/', 1, true) and state.savedJson ~= nil end,
      readFileContents = function() return assert(state.savedJson) end,
      writeFileContents = function(path, value) state.writes[path] = value end
    },
    g_logger = {error = function(message) state.errors[#state.errors + 1] = message end},
    tr = function(text) return text end,
    connect = function(_, handlers)
      for signal, fn in pairs(handlers) do
        assert(not state.handlers[signal], 'duplicate signal'); state.handlers[signal] = fn
      end
    end,
    disconnect = function(_, handlers)
      for signal, fn in pairs(handlers) do assert(state.handlers[signal] == fn); state.handlers[signal] = nil end
    end,
    scheduleEvent = function(fn) local event = {}; state.events[event] = fn; return event end,
    removeEvent = function(event) if event then state.events[event] = nil end end,
    string = setmetatable({}, {__index = string}),
    table = setmetatable({empty = function(values) return next(values) == nil end,
      isIn = function(values, needle)
        for _, value in ipairs(values) do if value == needle then return true end end
        return false
      end}, {__index = table}),
    GemDomains = {GREEN = 0, RED = 1, ACQUA = 2, PURPLE = 3}
  }, {__index = _G})
  env.displayGeneralBox = function(_, _, buttons)
    local widget = window(); widget.buttons = buttons; return widget
  end
  for _, path in ipairs({'modules/corelib/string.lua', 'modules/corelib/base64.lua',
    'modules/corelib/json.lua', 'modules/gamelib/util.lua', 'mods/game_wheel/wheel.lua',
    'mods/game_wheel/classes/wheelclass.lua', 'mods/game_wheel/classes/gematelier.lua'}) do
    loadProduction(path, env)
  end
  function state.createWindows()
    env.wheelWindow, env.newPresetWindow, env.renamePresetWindow = window(), window(), window()
  end
  function state.openAccessDialog()
    local before = {}
    for widget in pairs(state.roots) do before[widget] = true end
    env.WheelOfDestiny.onDestinyWheel(0, false, 0, 0)
    for widget in pairs(state.roots) do if not before[widget] then return widget end end
    error('missing access dialog')
  end
  function state.selectGem(id)
    setUpvalue(env.GemAtelier.onDestroyGem, 'lastSelectedGem', {getActionId = function() return 1 end})
    setUpvalue(env.GemAtelier.onDestroyGem, 'currentGemList', {{gemID = id}})
  end
  function state.openGemDialog(id)
    state.selectGem(id)
    local before = {}
    for widget in pairs(state.roots) do before[widget] = true end
    env.GemAtelier.onDestroyGem({isOn = function() return true end})
    for widget in pairs(state.roots) do if not before[widget] then return widget end end
    error('missing gem dialog')
  end
  return env, state
end

do
  local env, state = fixture()
  for _ = 1, 20 do
    env.init()
    assert(count(state.roots) == 0 and count(state.handlers) == 5, 'lazy initialization owns five signals')
    state.createWindows()
    local access, gem = state.openAccessDialog(), state.openGemDialog(111)
    env.onWheelOfDestinyApply(true, true)
    local firstEvent = next(state.events)
    env.onWheelOfDestinyApply(true, true)
    assert(count(state.events) == 1 and next(state.events) ~= firstEvent, 'apply-close replaces its timer')
    state.online = false
    state.handlers.onGameEnd()
    assert(access.destroyed and gem.destroyed and count(state.roots) == 3 and count(state.events) == 0)
    access.buttons[1].callback(); gem.buttons[1].callback(); gem.buttons[2].callback()
    assert(#state.sent == 0 and state.inputLock == nil, 'closed dialogs must not send actions or restore UI')
    env.terminate()
    assert(count(state.roots) == 0 and count(state.handlers) == 0 and count(state.events) == 0)

    -- Old callbacks must not destroy a newly opened dialog after a reload.
    state.online = true
    env.init(); state.createWindows()
    local nextAccess, nextGem = state.openAccessDialog(), state.openGemDialog(222)
    access.buttons[1].callback(); gem.buttons[1].callback(); gem.buttons[2].callback()
    assert(not nextAccess.destroyed and not nextGem.destroyed and #state.sent == 0)
    env.terminate()
    assert(nextAccess.destroyed and nextGem.destroyed and count(state.roots) == 0 and count(state.handlers) == 0)
  end
end

do
  local env, state = fixture()
  env.init(); state.createWindows()
  local dialog = state.openGemDialog(111)
  state.selectGem(222)
  dialog.buttons[1].callback(); dialog.buttons[1].callback()
  assert(#state.sent == 1 and state.sent[1][1] == 0 and state.sent[1][3] == 111,
    'confirmation sends only the original selected gem, once')
  assert(dialog.destroyed and env.wheelWindow.visible and state.inputLock == env.wheelWindow)
  dialog = state.openGemDialog(222)
  dialog.buttons[2].callback()
  assert(dialog.destroyed and #state.sent == 1 and env.wheelWindow.visible)

  dialog = state.openGemDialog(333)
  env.gemAtelierWindow = {recursiveGetChildById = function()
    return {searchText = {clearText = function() end}, setCurrentIndex = function() end, setChecked = function() end}
  end}
  env.Workshop = {getFragmentList = function() return {} end}
  env.GemAtelier.resetFields()
  assert(dialog.destroyed and count(state.roots) == 3, 'reset must destroy the confirmation, not lose its reference')
  dialog.buttons[1].callback(); dialog.buttons[2].callback()
  assert(#state.sent == 1)
  env.terminate()
  assert(count(state.roots) == 0)
end

do
  local env, state = fixture()
  env.init()
  local payload = env.base64.encode(env.string.pack_custom('I2', 100) .. string.rep('\0', 36 + 4))
  assert(#env.base64.decode(payload) == 42)
  local cases = {{4, 'K0'}, {8, 'K0'}, {3, 'P0'}, {7, 'P0'}, {1, 'S0'}, {5, 'S0'},
    {2, 'D0'}, {6, 'D0'}, {9, 'M0'}, {10, 'M0'}}
  for _, case in ipairs(cases) do
    state.vocation = case[1]
    for _, prefix in ipairs({'K0', 'P0', 'S0', 'D0', 'M0', 'N0', '01'}) do
      local accepted = env.WheelOfDestiny.validadeImportCode(prefix .. payload) == ''
      assert(accepted == (prefix == case[2]), 'preset vocation mismatch: ' .. prefix .. '/' .. case[1])
    end
  end
  state.vocation = 0
  assert(env.WheelOfDestiny.validadeImportCode('K0' .. payload) ~= '')
  state.vocation = 8
  for _, value in ipairs({'', 'K0', 'K0' .. env.base64.encode('x'), 'K0' .. env.base64.encode(string.rep('\0', 43))}) do
    assert(env.WheelOfDestiny.validadeImportCode(value) ~= '', 'malformed payload must be rejected without throwing')
  end
  assert(env.WheelOfDestiny.validadeImportCode({}) ~= '')

  state.loaded = true
  env.WheelOfDestiny.loadWheelPresets()
  assert(#env.WheelOfDestiny.internalPreset == 1, 'default preset remains valid')
  for _, malformed in ipairs({'null', 'false', '{"presets":false}'}) do
    state.savedJson = malformed
    env.WheelOfDestiny.loadWheelPresets()
    assert(#env.WheelOfDestiny.internalPreset == 1, 'malformed saved structure falls back to the default')
  end
  local ownCode = 'K0' .. payload
  state.savedJson = env.json.encode({presets = {
    {name = 'Other vocation', exportString = 'S0' .. payload}, {name = 'Broken', exportString = 'K0WA=='},
    {name = 'Missing code'}, {name = 'First valid', exportString = ownCode},
    {name = 'Second valid', exportString = ownCode}
  }})
  env.WheelOfDestiny.loadWheelPresets()
  assert(#env.WheelOfDestiny.internalPreset == 2 and #env.WheelOfDestiny.externalPreset.presets == 2)
  assert(env.WheelOfDestiny.internalPreset[1].presetName == 'First valid')
  assert(env.WheelOfDestiny.internalPreset[2].presetName == 'Second valid')
  env.WheelOfDestiny.generateInternalPreset()
  assert(#env.WheelOfDestiny.internalPreset == 2, 'rebuilding presets must not accumulate duplicates')
  env.WheelOfDestiny.saveWheelPresets()
  local saved = env.json.decode(assert(state.writes['/characterdata/119/wheelOfDestiny.json']))
  assert(#saved.presets == 2 and saved.presets[1].name == 'First valid')
  assert(env.WheelOfDestiny.validadeImportCode(saved.presets[1].exportString) == '', 'saved preset round-trips')

  -- Confirmation itself must reject a foreign vocation, even without the text-change validation.
  state.createWindows()
  local code = 'S0' .. payload
  local importOption = {}
  env.newPresetWindow.contentPanel = {import = importOption,
    presetName = {getText = function() return 'Imported' end}, presetCode = {getText = function() return code end}}
  env.selectedNewPresetRadio = {getSelectedWidget = function() return importOption end, destroy = function() end}
  local created = 0
  env.WheelOfDestiny.createPreset = function(_, data) created = created + 1; assert(data.availablePoints == 100) end
  env.WheelOfDestiny.configurePresets = function() end
  env.WheelOfDestiny.onConfirmCreatePreset()
  assert(created == 0)
  code = ownCode
  env.WheelOfDestiny.onConfirmCreatePreset()
  assert(created == 1)
  env.terminate()
  assert(count(state.roots) == 0 and count(state.handlers) == 0)
end

print('Wheel lifecycle, dialog ownership and preset vocation: OK')
