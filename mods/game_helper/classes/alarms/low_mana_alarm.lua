-- ===== HELPER LOW MANA ALARM =====
-- Modulo para gerenciar o alarme de mana baixa do Helper
-- Usa _Helper.AlarmSettings para load/save do arquivo alarms.json (secao "mana")

if not _Helper then
  _Helper = {}
end

_Helper.LowManaAlarm = {}

-- ===== CONFIGURACOES LOCAIS =====

local SOUND_FILE = '/sounds/low_mana.ogg'
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

-- ===== FUNCOES DO LOW MANA ALARM =====

_Helper.LowManaAlarm.toggle = function(checked)
  if isLoadingUI then return end

  local config = _Helper.AlarmSettings.getConfig()
  config.mana.enabled = checked

  if not checked and g_sounds then
    g_sounds.stopAlarm()
  end

  if not checked then
    lastPlayTime = 0
  end

  _Helper.AlarmSettings.saveConfig()
end

_Helper.LowManaAlarm.setThreshold = function(value)
  if isLoadingUI then return end

  local config = _Helper.AlarmSettings.getConfig()
  config.mana.percent = value
  _Helper.AlarmSettings.saveConfig()
end

_Helper.LowManaAlarm.getThreshold = function()
  local config = _Helper.AlarmSettings.getConfig()
  return config.mana.percent or DEFAULT_THRESHOLD
end

_Helper.LowManaAlarm.check = function()
  if not g_game.isOnline() then
    return
  end

  local config = _Helper.AlarmSettings.getConfig()
  if not config.mana.enabled then
    return
  end

  local currentPlayer = g_game.getLocalPlayer()
  if not currentPlayer then
    return
  end

  local threshold = config.mana.percent or DEFAULT_THRESHOLD
  local maxMana = currentPlayer:getMaxMana()
  if maxMana <= 0 then
    return
  end

  local manaPercent = math.floor((currentPlayer:getMana() / maxMana) * 100)
  if manaPercent >= threshold then
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
_Helper.LowManaAlarm.resetCheckbox = function()
  if g_sounds then
    g_sounds.stopAlarm()
  end
  lastPlayTime = 0
end

_Helper.LowManaAlarm.loadToUI = function()
  -- Nada a fazer: config carregada via AlarmSettings
end

-- Load state into the alarm settings modal window
_Helper.LowManaAlarm.loadToModal = function(window)
  if not window then return end

  local config = _Helper.AlarmSettings.getConfig()

  isLoadingUI = true

  local checkbox = window:recursiveGetChildById("lowManaAlarm")
  if checkbox then
    checkbox:setChecked(config.mana.enabled or false)
  end

  local thresholdInput = window:recursiveGetChildById("lowManaThreshold")
  if thresholdInput then
    local text = tostring(config.mana.percent or DEFAULT_THRESHOLD)
    thresholdInput:setText(text)
    thresholdInput:setCursorPos(#text)
  end

  isLoadingUI = false

  if checkbox then
    checkbox.onCheckChange = function(widget, checked)
      _Helper.LowManaAlarm.toggle(checked)
    end
  end
end

-- Setup input validation inside the alarm settings modal
_Helper.LowManaAlarm.setupModalThresholdInput = function(window)
  if not window then return end

  local input = window:recursiveGetChildById('lowManaThreshold')
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
          _Helper.LowManaAlarm.setThreshold(value)
        end
      end

      isUpdating = false
    end
  end
end

-- ===== FIM HELPER LOW MANA ALARM =====
