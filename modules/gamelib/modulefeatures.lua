-- Only modules whose startup dependencies and packet consumers have been audited
-- belong here. Rendering/visibility preferences deliberately remain separate.
ModuleFeatureManager = {}
local manager = ModuleFeatureManager
local registry = {
  {id = 'healthCircle', module = 'game_healthcircle', option = 'enableHealthCircleModule',
   label = 'Health Circle', runtimeUnload = false},
  {id = 'wheel', module = 'game_wheel', option = 'enableWheelModule',
   label = 'Wheel of Destiny', runtimeUnload = false, button = 'skillWheelDialog'},
  {id = 'bossHealth', module = 'game_boss_health', option = 'enableBossHealthModule',
   label = 'Boss Health', runtimeUnload = true},
  {id = 'bossDifficulty', module = 'game_bossdifficulty', option = 'enableBossDifficultyModule',
   label = 'Boss Difficulty', runtimeUnload = false},
  {id = 'hints', module = 'game_hints', option = 'enableHintsModule',
   label = 'Hints', runtimeUnload = true},
  {id = 'notifications', module = 'game_notifications', option = 'enableNotificationsModule',
   label = 'Notifications', runtimeUnload = false},
}
local states, failed = {}, {}
local buttonAvailability = {}
local ready, connected = false, false

local function find(feature)
  for _, entry in ipairs(registry) do
    if feature == entry.id or feature == entry.module or feature == entry.option then
      return entry
    end
  end
end

local function status(entry, value, detail)
  local previous = states[entry.id]
  states[entry.id] = {state = value, detail = detail}
  if not previous or previous.state ~= value or previous.detail ~= detail then
    g_logger.info('[ModuleFeature] ' .. entry.module .. ': ' .. value .. (detail and ' (' .. detail .. ')' or ''))
    if manager.onStatusChange then manager.onStatusChange(entry.id, value) end
  end
  return value
end

function manager.getRegistry()
  return registry
end

function manager.isEnabled(feature)
  local entry = find(feature)
  return entry ~= nil and g_settings.getBoolean(entry.option)
end

function manager.isLoaded(feature)
  local entry = find(feature)
  local module = entry and g_modules.getModule(entry.module)
  return module ~= nil and module:isLoaded()
end

function manager.getStatus(feature)
  local entry = find(feature)
  local current = entry and states[entry.id]
  return current and current.state or 'pending-startup', current and current.detail
end

function manager.isButtonAvailable(button)
  for _, entry in ipairs(registry) do
    if entry.button == button then
      -- Before startup policy, create buttons only for enabled settings. A
      -- failed load is filtered out when the policy refreshes side buttons.
      return manager.isEnabled(entry.id) and (not ready or manager.isLoaded(entry.id))
    end
  end
  return true
end

function manager.canUnloadNow(feature)
  local entry = find(feature)
  local module = entry and g_modules.getModule(entry.module)
  return entry ~= nil and entry.runtimeUnload and module ~= nil and module:canUnload()
end

local function capabilityAvailable(entry)
  -- Only an existing, audited, negotiated Game* feature may be specified here.
  -- No version heuristic or invented capability bit.
  return (not entry.requiresOnline or g_game.isOnline()) and
         (not entry.capability or (g_game.isOnline() and g_game.getFeature(entry.capability)))
end

local function apply(entry)
  local module = g_modules.getModule(entry.module)
  if not module then return status(entry, 'failed-to-load', 'module not discovered') end

  if not manager.isEnabled(entry.id) then
    if not module:isLoaded() then return status(entry, 'disabled-not-loaded') end
    if not module:canUnload() then return status(entry, 'blocked-by-dependent', 'restart required; dependency or non-reloadable module') end
    if not entry.runtimeUnload then return status(entry, 'disable-pending-restart', 'restart required') end
    local ok, err = pcall(function() module:unload() end)
    if not ok or module:isLoaded() then
      return status(entry, 'disable-pending-restart', tostring(err or 'unload failed'))
    end
    return status(entry, 'disabled-not-loaded')
  end

  if module:isLoaded() then return status(entry, 'loaded') end
  if not capabilityAvailable(entry) then return status(entry, 'enabled-pending-capability') end
  -- Failed init may have partially installed hooks. Never retry it in the same
  -- process and risk duplicating those hooks; a clean restart is required.
  if failed[entry.id] then return status(entry, 'failed-to-load', failed[entry.id]) end
  if not module.tryLoad then
    failed[entry.id] = 'client binary needs Module.tryLoad; restart with updated binary'
    return status(entry, 'failed-to-load', failed[entry.id])
  end
  local ok, result = pcall(function() return module:tryLoad() end)
  if not ok or not result or not module:isLoaded() then
    failed[entry.id] = 'load failed; check log and restart'
    g_logger.error('[ModuleFeature] ' .. entry.module .. ': ' .. tostring(result))
    return status(entry, 'failed-to-load', failed[entry.id])
  end
  return status(entry, 'loaded')
end

local function refreshButtons()
  local changed = false
  for _, entry in ipairs(registry) do
    if entry.button then
      local available = manager.isButtonAvailable(entry.button)
      if buttonAvailability[entry.button] ~= available then changed = true end
      buttonAvailability[entry.button] = available
    end
  end
  local sidebuttons = modules.game_sidebuttons
  if changed and sidebuttons and sidebuttons.updateSideButtons then sidebuttons.updateSideButtons() end
end

function manager.setEnabled(feature, enabled)
  local entry = find(feature)
  if not entry or type(enabled) ~= 'boolean' then return false end
  local changed = manager.isEnabled(entry.id) ~= enabled
  g_settings.set(entry.option, enabled)
  if ready then
    apply(entry)
    refreshButtons()
  end
  if changed then g_settings.save() end
  return true
end

function manager.applyOnlineCapabilities()
  if not ready then return end
  for _, entry in ipairs(registry) do apply(entry) end
  refreshButtons()
end

function manager.applyStartupPolicy()
  ready = true
  if not connected then
    connect(g_game, {onGameStart = manager.applyOnlineCapabilities, onGameEnd = manager.applyOnlineCapabilities})
    connected = true
  end
  manager.applyOnlineCapabilities()
end

function manager.terminate()
  if connected then
    disconnect(g_game, {onGameStart = manager.applyOnlineCapabilities, onGameEnd = manager.applyOnlineCapabilities})
  end
  ready, connected = false, false
  manager.onStatusChange = nil
end

-- Set defaults synchronously, before client_settings' deferred setup() runs.
for _, entry in ipairs(registry) do
  g_settings.setDefault(entry.option, true)
  if entry.button then buttonAvailability[entry.button] = manager.isEnabled(entry.id) end
end
