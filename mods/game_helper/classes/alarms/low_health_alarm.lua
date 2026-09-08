-- ===== HELPER LOW HEALTH ALARM =====
-- Modulo para gerenciar o alarme de vida baixa do Helper
-- Usa _Helper.AlarmSettings para load/save do arquivo alarms.json (secao "health")

if not _Helper then
  _Helper = {}
end

_Helper.LowHealthAlarm = {}

-- ===== CONFIGURACOES LOCAIS =====

local SOUND_FILE = '/sounds/low_health.ogg'
local CHECK_INTERVAL = 3000 -- 3 segundos
local DEFAULT_THRESHOLD = 30

local lastPlayTime = 0
local isLoadingUI = false
local soundPreloaded = false

local function ensurePreloaded()
  if not soundPreloaded and g_sounds then
    g_sounds.preload(SOUND_FILE)
    soundPreloaded = true
  end
end

-- ===== FUNCOES DO LOW HEALTH ALARM =====

_Helper.LowHealthAlarm.toggle = function(checked)
  if isLoadingUI then return end

  local config = _Helper.AlarmSettings.getConfig()
  config.health.enabled = checked

  if not checked then
    if g_sounds then
      g_sounds.stopAlarm()
    end
  end

  if not checked then
    lastPlayTime = 0
  end

  _Helper.AlarmSettings.saveConfig()
end

_Helper.LowHealthAlarm.setThreshold = function(value)
  if isLoadingUI then return end

  local config = _Helper.AlarmSettings.getConfig()
  config.health.percent = value
  _Helper.AlarmSettings.saveConfig()
end

_Helper.LowHealthAlarm.getThreshold = function()
  local config = _Helper.AlarmSettings.getConfig()
  return config.health.percent or DEFAULT_THRESHOLD
end

_Helper.LowHealthAlarm.check = function()
  if not g_game.isOnline() then
    return
  end

  local config = _Helper.AlarmSettings.getConfig()
  if not config.health.enabled then
    return
  end

  local currentPlayer = g_game.getLocalPlayer()
  if not currentPlayer then
    return
  end

  local threshold = config.health.percent or DEFAULT_THRESHOLD
  local healthPercent = currentPlayer:getHealthPercent()
  if healthPercent >= threshold then
    return
  end

  local now = g_clock.millis()
  if lastPlayTime > 0 and now - lastPlayTime < CHECK_INTERVAL then
    return
  end

  lastPlayTime = now

  if g_sounds then
    ensurePreloaded()
    g_sounds.playAlarm(SOUND_FILE)
  end

end

-- Reset state (stop sound)
_Helper.LowHealthAlarm.resetCheckbox = function()
  if g_sounds then
    g_sounds.stopAlarm()
  end
  lastPlayTime = 0
end

_Helper.LowHealthAlarm.loadToUI = function()
  -- Nada a fazer: config carregada via AlarmSettings
end

-- Load state into the alarm settings modal window
_Helper.LowHealthAlarm.loadToModal = function(window)
  if not window then return end

  local config = _Helper.AlarmSettings.getConfig()

  isLoadingUI = true

  local checkbox = window:recursiveGetChildById("lowHealthAlarm")
  if checkbox then
    checkbox:setChecked(config.health.enabled or false)
  end

  local thresholdInput = window:recursiveGetChildById("lowHealthThreshold")
  if thresholdInput then
    local text = tostring(config.health.percent or DEFAULT_THRESHOLD)
    thresholdInput:setText(text)
    thresholdInput:setCursorPos(#text)
  end

  isLoadingUI = false

  if checkbox then
    checkbox.onCheckChange = function(widget, checked)
      _Helper.LowHealthAlarm.toggle(checked)
    end
  end
end

-- Setup input validation inside the alarm settings modal
_Helper.LowHealthAlarm.setupModalThresholdInput = function(window)
  if not window then return end

  local input = window:recursiveGetChildById('lowHealthThreshold')
  if input then
    local isUpdating = false
    input.onTextChange = function(widget, text)
      if isUpdating then return end
      isUpdating = true

      local numericText = text:gsub("[^%d]", "")
      if numericText ~= text then
        widget:setText(numericText)
      end

      if not isLoadingUI then
        local value = tonumber(numericText)
        if value and value >= 1 and value <= 100 then
          _Helper.LowHealthAlarm.setThreshold(value)
        end
      end

      isUpdating = false
    end
  end
end

-- ===== FIM HELPER LOW HEALTH ALARM =====
