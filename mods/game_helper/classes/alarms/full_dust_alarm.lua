-- ===== HELPER FULL DUST ALARM =====
-- Modulo separado para gerenciar o alarme de dust cheio do Helper
-- Usa _Helper.AlarmSettings para load/save do arquivo alarms.json (secao "dust")

if not _Helper then
  _Helper = {}
end

_Helper.FullDustAlarm = {}

-- ===== CONFIGURACOES LOCAIS =====

local SOUND_FILE = '/sounds/full_dust.ogg'

local PLAY_DELAY = 3000 -- 3 segundos de atraso antes de tocar

local pendingEvent = nil
local isLoadingUI = false
local soundPreloaded = false
local wasDustFull = true -- começa true para nao tocar no login

-- ===== FUNCOES DO FULL DUST ALARM =====

local function ensurePreloaded()
  if not soundPreloaded and g_sounds then
    g_sounds.preload(SOUND_FILE)
    soundPreloaded = true
  end
end

_Helper.FullDustAlarm.toggle = function(checked)
  if isLoadingUI then return end

  local config = _Helper.AlarmSettings.getConfig()
  config.dust.enabled = checked

  if not checked and g_sounds then
    g_sounds.stopAlarm()
  end

  _Helper.AlarmSettings.saveConfig()
end

-- Chamado por Forge:updateDustHighlight sempre que o dust muda
-- Toca apenas na transicao de nao-cheio para cheio (uma unica vez)
_Helper.FullDustAlarm.check = function(dustFull)
  if not g_game.isOnline() then
    return
  end

  local wasFull = wasDustFull
  wasDustFull = dustFull

  if not dustFull or wasFull then
    return
  end

  local config = _Helper.AlarmSettings.getConfig()
  if not config.dust.enabled then
    return
  end

  if pendingEvent then
    removeEvent(pendingEvent)
    pendingEvent = nil
  end

  pendingEvent = scheduleEvent(function()
    pendingEvent = nil

    if g_sounds then
      ensurePreloaded()
      g_sounds.playAlarm(SOUND_FILE)
    end

  end, PLAY_DELAY)
end

-- Reset state (chamado apenas no offline/logout)
_Helper.FullDustAlarm.resetCheckbox = function()
  if pendingEvent then
    removeEvent(pendingEvent)
    pendingEvent = nil
  end
  if g_sounds then
    g_sounds.stopAlarm()
  end
  wasDustFull = true
end

_Helper.FullDustAlarm.loadToUI = function()
  -- Cache e limpo pelo LowCapacityAlarm.loadToUI ou pelo AlarmSettings.clearCache
end

-- Load state into the alarm settings modal window
_Helper.FullDustAlarm.loadToModal = function(window)
  if not window then return end

  local config = _Helper.AlarmSettings.getConfig()

  isLoadingUI = true

  local checkbox = window:recursiveGetChildById("fullDustAlarm")
  if checkbox then
    checkbox:setChecked(config.dust.enabled or false)
  end

  isLoadingUI = false

  if checkbox then
    checkbox.onCheckChange = function(widget, checked)
      _Helper.FullDustAlarm.toggle(checked)
    end
  end
end

-- ===== FIM HELPER FULL DUST ALARM =====
