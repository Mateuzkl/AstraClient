-- LuaJIT regression tests; no client window, compilation, or CTest required.
local managerPath = arg[1] or 'modules/gamelib/modulefeatures.lua'
local bossPath = arg[2] or 'mods/game_boss_health/boss_health.lua'
local hintsPath = arg[3] or 'mods/game_hints/hint.lua'

local function read(path)
  local file = assert(io.open(path, 'rb'))
  local contents = file:read('*a')
  file:close()
  return contents
end

local function reset(saved)
  local state = {settings = saved or {}, modules = {}, connections = {}, logs = {},
                 saves = 0, online = false, feature = false, buttonRefreshes = 0}
  g_settings = {
    setDefault = function(key, value) if state.settings[key] == nil then state.settings[key] = value end end,
    getBoolean = function(key) return state.settings[key] == true end,
    set = function(key, value) state.settings[key] = value end,
    save = function() state.saves = state.saves + 1 end,
  }
  g_game = {isOnline = function() return state.online end, getFeature = function() return state.feature end}
  g_logger = {}
  for _, level in ipairs({'info', 'error', 'warning'}) do
    g_logger[level] = function(text) state.logs[#state.logs + 1] = text end
  end
  connect = function(_, handlers)
    for event, callback in pairs(handlers) do
      assert(not state.connections[event], 'duplicate manager signal')
      state.connections[event] = callback
    end
  end
  disconnect = function(_, handlers)
    for event, callback in pairs(handlers) do
      assert(state.connections[event] == callback)
      state.connections[event] = nil
    end
  end
  modules = {game_sidebuttons = {updateSideButtons = function() state.buttonRefreshes = state.buttonRefreshes + 1 end}}
  g_modules = {getModule = function(name) return state.modules[name] end}
  dofile(managerPath)
  for _, entry in ipairs(ModuleFeatureManager.getRegistry()) do
    local module = {loads = 0, inits = 0, widgets = 0, events = 0, unloads = 0, loaded = false}
    function module:isLoaded() return self.loaded end
    function module:canUnload() return self.loaded and not self.blocked end
    function module:load() error('optional feature used the fatal loader') end
    function module:tryLoad()
      self.loads = self.loads + 1
      if self.fail then return false end
      self.loaded = true
      self.inits, self.widgets, self.events = self.inits + 1, self.widgets + 1, self.events + 1
      return true
    end
    function module:unload()
      assert(self:canUnload(), 'forced unload')
      self.loaded = false
      self.widgets, self.events = 0, 0
      self.unloads = self.unloads + 1
    end
    state.modules[entry.module] = module
  end
  return state, ModuleFeatureManager
end

-- Migration retains availability; applying the policy twice and relogging is
-- idempotent, and does not rebuild unchanged side-button UI.
local state, manager = reset()
manager.applyStartupPolicy()
manager.applyStartupPolicy()
state.online = true
state.connections.onGameStart()
state.online = false
state.connections.onGameEnd()
state.online = true
state.connections.onGameStart()
local before = 0
for _, entry in ipairs(manager.getRegistry()) do
  local module = state.modules[entry.module]
  assert(manager.isEnabled(entry.id) and manager.isLoaded(entry.id))
  assert(module.loads == 1 and module.inits == 1 and module.widgets == 1 and module.events == 1)
  assert(manager.getStatus(entry.id) == 'loaded')
  before = before + 1
end
assert(state.buttonRefreshes == 0, 'unchanged policy rebuilt side buttons')
manager.terminate()
assert(next(state.connections) == nil, 'manager leaked signals')

-- An already loaded complex module is not force-unloaded. Re-enabling cancels
-- the restart requirement without another init.
state, manager = reset()
manager.applyStartupPolicy()
assert(manager.setEnabled('wheel', false))
assert(manager.getStatus('wheel') == 'disable-pending-restart')
assert(manager.isLoaded('wheel') and not manager.isButtonAvailable('skillWheelDialog'))
assert(state.modules.game_wheel.unloads == 0)
assert(manager.setEnabled('wheel', true))
assert(manager.getStatus('wheel') == 'loaded' and state.modules.game_wheel.loads == 1)

-- Safe unload respects native canUnload, including a loaded reverse dependent.
state.modules.game_boss_health.blocked = true
manager.setEnabled('bossHealth', false)
assert(manager.getStatus('bossHealth') == 'blocked-by-dependent')
assert(state.modules.game_boss_health.unloads == 0)
state.modules.game_boss_health.blocked = false
manager.applyOnlineCapabilities()
assert(manager.getStatus('bossHealth') == 'disabled-not-loaded')
assert(state.modules.game_boss_health.unloads == 1)
assert(state.modules.game_boss_health.widgets == 0 and state.modules.game_boss_health.events == 0)
manager.setEnabled('bossHealth', false)
assert(state.modules.game_boss_health.unloads == 1)
manager.setEnabled('bossHealth', true)
assert(state.modules.game_boss_health.inits == 2)

-- Discovered != loaded. OFF startup runs neither scripts nor init and preserves
-- all saved false values, including across a simulated settings restart.
local saved = {}
for _, entry in ipairs(manager.getRegistry()) do saved[entry.option] = false end
state, manager = reset(saved)
manager.applyStartupPolicy()
manager.applyStartupPolicy()
local after = 0
for _, entry in ipairs(manager.getRegistry()) do
  local module = assert(g_modules.getModule(entry.module))
  assert(not module:isLoaded() and module.loads == 0 and module.inits == 0)
  assert(module.widgets == 0 and module.events == 0)
  assert(manager.getStatus(entry.id) == 'disabled-not-loaded')
  after = after + (module:isLoaded() and 1 or 0)
end
assert(not manager.isButtonAvailable('skillWheelDialog'))
local persisted = state.settings
state, manager = reset(persisted)
manager.applyStartupPolicy()
assert(not manager.isLoaded('healthCircle') and not manager.isLoaded('wheel'))

-- Online-capability policy infrastructure uses an existing feature ID, not a
-- fabricated protocol bit. This is a fixture, not a gate added to Boss Health.
for _, option in ipairs({false, true}) do
  for _, capability in ipairs({false, true}) do
    state, manager = reset({enableBossHealthModule = option})
    for _, entry in ipairs(manager.getRegistry()) do
      if entry.id == 'bossHealth' then entry.capability = 132 end -- GameProficiency
    end
    state.online, state.feature = true, capability
    manager.applyStartupPolicy()
    assert(manager.isLoaded('bossHealth') == (option and capability))
    if option and not capability then assert(manager.getStatus('bossHealth') == 'enabled-pending-capability') end
  end
end
state, manager = reset()
manager.getRegistry()[1].requiresOnline = true
manager.applyStartupPolicy()
assert(manager.getStatus('healthCircle') == 'enabled-pending-capability')
state.online = true
state.connections.onGameStart()
assert(state.modules.game_healthcircle.loads == 1)

-- Failed optional init is nonfatal, does not block other features, and is not
-- retried automatically (partial external hooks require a clean restart).
state, manager = reset()
state.modules.game_healthcircle.fail = true
manager.applyStartupPolicy()
manager.applyOnlineCapabilities()
manager.setEnabled('healthCircle', false)
manager.setEnabled('healthCircle', true)
assert(manager.getStatus('healthCircle') == 'failed-to-load')
assert(state.modules.game_healthcircle.loads == 1 and manager.isLoaded('notifications'))
state, manager = reset()
state.modules.game_healthcircle.tryLoad = nil
manager.applyStartupPolicy()
assert(manager.getStatus('healthCircle') == 'failed-to-load', 'old binary must fail safely')

-- Exercise the real GameOptions path, including defaults, persisted settings,
-- callbacks, and save scheduling, rather than only testing the registry API.
state, manager = reset({enableWheelModule = false})
local optionEnv = setmetatable({GameOptions = {options = {}, loadedWindows = {}},
  scheduleEvent = function(callback) return {callback = callback} end,
  removeEvent = function() end}, {__index = _G})
setfenv(assert(loadfile('mods/client_settings/classes/GameOptions.lua')), optionEnv)()
optionEnv.GameOptions:setupStart()
optionEnv.GameOptions:loadSettings()
manager.applyStartupPolicy()
assert(not manager.isLoaded('wheel'))
optionEnv.GameOptions:setOption('enableWheelModule', true)
optionEnv.GameOptions:flushSettingsSave()
assert(manager.isLoaded('wheel') and state.settings.enableWheelModule and state.saves > 0)

-- Real module cleanup and retained callback safety, including unload/reload.
local function lifecycleEnv(path)
  local env = {handlers = {}, events = {}, widgets = {}, g_game = {}, g_ui = {}}
  setmetatable(env, {__index = _G})
  env.connect = function(_, handlers) for name, fn in pairs(handlers) do
    assert(not env.handlers[name]); env.handlers[name] = fn
  end end
  env.disconnect = function(_, handlers) for name, fn in pairs(handlers) do
    assert(env.handlers[name] == fn); env.handlers[name] = nil
  end end
  env.removeEvent = function(event) event.cancelled = true end
  env.scheduleEvent = function(fn) local event = {fn = fn}; env.events[#env.events + 1] = event; return event end
  env.cycleEvent = env.scheduleEvent
  local function widget()
    local value = {destroyed = false}
    function value:hide() assert(not self.destroyed) end
    function value:show() assert(not self.destroyed) end
    function value:destroy() assert(not self.destroyed); self.destroyed = true end
    function value:recursiveGetChildById() return self end
    function value:setText() assert(not self.destroyed) end
    function value:setOutfit() assert(not self.destroyed) end
    function value:setPercent() assert(not self.destroyed) end
    env.widgets[#env.widgets + 1] = value
    return value
  end
  env.g_ui.displayUI = widget
  env.g_ui.loadUI = widget
  env.g_ui.getRootWidget = function() return {} end
  env.g_things = {getMonsterList = function() return {[1] = {'Boss', 2, 0, 0, 0, 0, 0, 0}} end}
  env.string = setmetatable({capitalize = function(text) return text end}, {__index = string})
  setfenv(assert(loadfile(path)), env)()
  return env
end

local boss = lifecycleEnv(bossPath)
boss.init()
boss.onMonsterHealth(1, 100, 100, 10)
local oldCycle = boss.events[#boss.events]
boss.onMonsterHealthHide()
local oldHide = boss.events[#boss.events]
assert(oldCycle.cancelled)
boss.terminate()
assert(oldHide.cancelled and boss.widgets[1].destroyed and next(boss.handlers) == nil)
oldCycle.fn(); oldHide.fn(); boss.onMonsterHealth(1, 1, 100, 10)
boss.init()
-- Callbacks retained before unload must also remain inert after reload.
oldCycle.fn(); oldHide.fn()
assert(#boss.events == 2)
boss.onMonsterHealth(1, 1, 100, 10)
boss.handlers.onGameEnd()
assert(boss.events[#boss.events].cancelled)
boss.handlers.onGameStart()
boss.terminate()

local hints = lifecycleEnv(hintsPath)
hints.init()
hints.showHint('arrival')
hints.showHint('arrival')
assert(#hints.widgets == 1)
hints.handlers.onGameEnd()
assert(hints.widgets[1].destroyed)
hints.showHint('arrival')
hints.terminate()
assert(hints.widgets[2].destroyed and next(hints.handlers) == nil)
hints.showHint('arrival'); hints.tutorialHint('next')
assert(#hints.widgets == 2, 'stale hint callback recreated UI')
hints.init(); hints.showHint('arrival'); hints.terminate()
assert(hints.widgets[3].destroyed)

-- Verify unconditional startup sources cannot bypass the manager. Keep core
-- and custom-opcode consumers loaded. These assertions supplement live tests.
local interface = read('modules/game_interface/interface.otmod')
for _, entry in ipairs(manager.getRegistry()) do
  assert(not interface:find('%- ' .. entry.module .. '%s'), entry.module .. ' remains in load-later')
end
for _, name in ipairs({'game_inventory', 'game_walking', 'game_npctrade', 'game_actionbar',
                       'game_forge', 'game_battlepass', 'game_attachedeffects', 'game_proficiency'}) do
  assert(interface:find('%- ' .. name .. '%s'), name .. ' lost mandatory loading')
end
assert(not read('modules/game_healthcircle/game_healthcircle.otmod'):find('autoload: true', 1, true))
local bootstrap = read('init.lua')
assert(bootstrap:find('ensureModuleLoaded("game_interface")', 1, true) < bootstrap:find('ModuleFeatureManager.applyStartupPolicy()', 1, true))
print(string.format('Optional module lifecycle: passed; policy fixtures full=%d, minimal=%d (not native performance measurements)', before, after))
