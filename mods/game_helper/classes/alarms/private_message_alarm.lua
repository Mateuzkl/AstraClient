-- ===== HELPER PRIVATE MESSAGE ALARM =====
-- Modulo separado para gerenciar o alarme de mensagem privada do Helper
-- Usa _Helper.AlarmSettings para load/save do arquivo alarms.json (secao "private_message")

if not _Helper then
  _Helper = {}
end

_Helper.PrivateMessageAlarm = {}

-- ===== CONFIGURACOES LOCAIS =====

local SOUND_FILE = '/sounds/private_message.ogg'
local DEBOUNCE_INTERVAL = 2000 -- 2 segundos

local lastPlayTime = 0
local isLoadingUI = false
local soundPreloaded = false

local function ensurePreloaded()
  if not soundPreloaded and g_sounds then
    g_sounds.preload(SOUND_FILE)
    soundPreloaded = true
  end
end

-- ===== FUNCOES DO PRIVATE MESSAGE ALARM =====

_Helper.PrivateMessageAlarm.toggle = function(checked)
  if isLoadingUI then return end

  local config = _Helper.AlarmSettings.getConfig()
  config.private_message.enabled = checked

  if not checked and g_sounds and g_sounds.stopAlarm then
    g_sounds.stopAlarm()
  end

  if not checked then
    lastPlayTime = 0
  end

  _Helper.AlarmSettings.saveConfig()
end

-- Chamado pelo onTalk handler quando recebe uma mensagem privada
_Helper.PrivateMessageAlarm.check = function(name, level, mode)
  if not g_game.isOnline() then
    return
  end

  if mode ~= MessageModes.PrivateFrom then
    return
  end

  local config = _Helper.AlarmSettings.getConfig()
  if not config.private_message.enabled then
    return
  end

  local now = g_clock.millis()
  if lastPlayTime > 0 and now - lastPlayTime < DEBOUNCE_INTERVAL then
    return
  end

  lastPlayTime = now

  if g_sounds then
    ensurePreloaded()
    g_sounds.playAlarm(SOUND_FILE)
  end

  local cfg = _Helper.AlarmSettings.getConfig()
  if cfg.flash_window and cfg.flash_window.enabled then
    g_window.flashWindow(0)
  end
end

-- Reset state (chamado apenas no offline/logout)
_Helper.PrivateMessageAlarm.resetCheckbox = function()
  if g_sounds and g_sounds.stopAlarm then
    g_sounds.stopAlarm()
  end
  lastPlayTime = 0
end

-- Load state into the alarm settings modal window
_Helper.PrivateMessageAlarm.loadToModal = function(window)
  if not window then return end

  local config = _Helper.AlarmSettings.getConfig()

  isLoadingUI = true

  local checkbox = window:recursiveGetChildById("privateMessageAlarm")
  if checkbox then
    checkbox:setChecked(config.private_message.enabled or false)
  end

  isLoadingUI = false

  if checkbox then
    checkbox.onCheckChange = function(widget, checked)
      _Helper.PrivateMessageAlarm.toggle(checked)
    end
  end
end

-- ===== FIM HELPER PRIVATE MESSAGE ALARM =====
