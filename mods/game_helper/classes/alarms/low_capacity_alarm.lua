-- ===== HELPER LOW CAPACITY ALARM =====
-- Modulo separado para gerenciar o alarme de capacidade baixa do Helper
-- Usa _Helper.AlarmSettings para load/save do arquivo alarms.json (secao "cap")

if not _Helper then
  _Helper = {}
end

_Helper.LowCapacityAlarm = {}

-- ===== CONFIGURACOES LOCAIS =====

local SOUND_FILE = '/sounds/low_capacity.ogg'
local CHECK_INTERVAL = 10000 -- 10 segundos
local DEFAULT_THRESHOLD = 50

local lastPlayTime = 0
local isLoadingUI = false
local soundPreloaded = false

local function ensurePreloaded()
  if not soundPreloaded and g_sounds then
    g_sounds.preload(SOUND_FILE)
    soundPreloaded = true
  end
end

-- ===== FUNCOES DO LOW CAPACITY ALARM =====

_Helper.LowCapacityAlarm.toggle = function(checked)
  if isLoadingUI then return end

  local config = _Helper.AlarmSettings.getConfig()
  config.cap.enabled = checked

  if not checked and g_sounds then
    g_sounds.stopAlarm()
  end

  if not checked then
    lastPlayTime = 0
  end

  _Helper.AlarmSettings.saveConfig()
end

_Helper.LowCapacityAlarm.setThreshold = function(value)
  if isLoadingUI then return end

  local config = _Helper.AlarmSettings.getConfig()
  config.cap.min_cap = value
  _Helper.AlarmSettings.saveConfig()
end

_Helper.LowCapacityAlarm.getThreshold = function()
  local config = _Helper.AlarmSettings.getConfig()
  return config.cap.min_cap or DEFAULT_THRESHOLD
end

_Helper.LowCapacityAlarm.check = function()
  if not g_game.isOnline() then
    return
  end

  local config = _Helper.AlarmSettings.getConfig()
  if not config.cap.enabled then
    return
  end

  local currentPlayer = g_game.getLocalPlayer()
  if not currentPlayer then
    return
  end

  local threshold = config.cap.min_cap or DEFAULT_THRESHOLD
  local freeCapacity = currentPlayer:getFreeCapacity()
  if freeCapacity >= threshold then
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

-- Reset state (close modal if open, stop sound)
_Helper.LowCapacityAlarm.resetCheckbox = function()
  if _Helper.AlarmSettings and _Helper.AlarmSettings.close then
    _Helper.AlarmSettings.close()
  end

  if g_sounds then
    g_sounds.stopAlarm()
  end
  lastPlayTime = 0

  _Helper.AlarmSettings.clearCache()
end

_Helper.LowCapacityAlarm.loadToUI = function()
  _Helper.AlarmSettings.clearCache()
end

-- No-op: input validation is setup when the alarm modal opens
_Helper.LowCapacityAlarm.setupThresholdInput = function()
end

-- Load state into the alarm settings modal window
_Helper.LowCapacityAlarm.loadToModal = function(window)
  if not window then return end

  local config = _Helper.AlarmSettings.getConfig()

  isLoadingUI = true

  local checkbox = window:recursiveGetChildById("lowCapacityAlarm")
  if checkbox then
    checkbox:setChecked(config.cap.enabled or false)
  end

  local thresholdInput = window:recursiveGetChildById("lowCapacityThreshold")
  if thresholdInput then
    local text = tostring(config.cap.min_cap or DEFAULT_THRESHOLD)
    thresholdInput:setText(text)
    thresholdInput:setCursorPos(#text)
  end

  isLoadingUI = false

  if checkbox then
    checkbox.onCheckChange = function(widget, checked)
      _Helper.LowCapacityAlarm.toggle(checked)
    end
  end
end

-- Setup input validation inside the alarm settings modal
_Helper.LowCapacityAlarm.setupModalThresholdInput = function(window)
  if not window then return end

  local input = window:recursiveGetChildById('lowCapacityThreshold')
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
        if value and value >= 1 then
          _Helper.LowCapacityAlarm.setThreshold(value)
        end
      end

      isUpdating = false
    end
  end
end

-- ===== FIM HELPER LOW CAPACITY ALARM =====
