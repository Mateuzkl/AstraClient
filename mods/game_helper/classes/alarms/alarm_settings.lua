-- ===== HELPER ALARM SETTINGS =====
-- Modulo centralizado para gerenciar o modal e a configuracao de alarmes.
-- Gerencia o arquivo alarms.json e coordena todos os tipos de alarme.

if not _Helper then
  _Helper = {}
end

_Helper.AlarmSettings = {}

-- Expor via modules para acesso em callbacks OTUI
modules.game_helper = modules.game_helper or {}
modules.game_helper.alarmSettings = _Helper.AlarmSettings

-- ===== CONFIGURACAO COMPARTILHADA DO ARQUIVO ALARMS =====

local ALARMS_FILENAME = 'alarms.json'
local cachedConfig = nil
local alarmSettingsWindow = nil

local DEFAULT_CONFIG = {
  cap = {
    enabled = false,
    min_cap = 50
  },
  dust = {
    enabled = false
  },
  supply = {
    enabled = false,
    alertInProtectZone = false
  },
  private_message = {
    enabled = false
  },
  health = {
    enabled = false,
    percent = 30
  },
  mana = {
    enabled = false,
    percent = 30
  }
}

local function getAlarmsFilePath()
  local currentPlayer = g_game.getLocalPlayer()
  if not currentPlayer then
    return nil
  end
  local dir = _Helper.getCharacterStorageDir and _Helper.getCharacterStorageDir(currentPlayer) or
      ("/characterdata/" .. currentPlayer:getId())
  local legacyDir = "/characterdata/" .. currentPlayer:getId()
  return dir, dir .. "/" .. ALARMS_FILENAME, legacyDir .. "/" .. ALARMS_FILENAME
end

local function loadFromFile()
  local dir, filePath, legacyFilePath = getAlarmsFilePath()
  if not filePath then
    return nil
  end

  local migratedFromLegacy = false
  if not g_resources.fileExists(filePath) then
    if legacyFilePath and legacyFilePath ~= filePath and g_resources.fileExists(legacyFilePath) then
      filePath = legacyFilePath
      migratedFromLegacy = true
    else
      return nil
    end
  end

  local rawConfig = nil
  local status, result = pcall(function()
    rawConfig = g_resources.readFileContents(filePath)
    return json.decode(rawConfig)
  end)

  if not status or not result then
    return nil
  end

  if migratedFromLegacy and rawConfig then
    g_resources.makeDir(dir)
    pcall(function()
      g_resources.writeFileContents(dir .. "/" .. ALARMS_FILENAME, rawConfig)
    end)
  end

  return result
end

local function saveToFile(config)
  local dir, filePath = getAlarmsFilePath()
  if not filePath then
    return false
  end

  g_resources.makeDir(dir)

  local status, encoded = pcall(function()
    return json.encode(config, 2)
  end)

  if not status then
    return false
  end

  local writeStatus = pcall(function()
    return g_resources.writeFileContents(filePath, encoded)
  end)

  return writeStatus
end

-- ===== API PUBLICA DE CONFIGURACAO =====

-- Retorna config cacheada ou carrega do arquivo.
-- Garante que todas as secoes existem.
_Helper.AlarmSettings.getConfig = function()
  if not cachedConfig then
    cachedConfig = loadFromFile() or {}
  end
  -- Garantir que todas as secoes existem
  for key, defaults in pairs(DEFAULT_CONFIG) do
    if not cachedConfig[key] then
      cachedConfig[key] = {}
    end
    for field, value in pairs(defaults) do
      if cachedConfig[key][field] == nil then
        cachedConfig[key][field] = value
      end
    end
  end
  return cachedConfig
end

-- Salva a config cacheada no arquivo
_Helper.AlarmSettings.saveConfig = function()
  if not cachedConfig then return false end
  return saveToFile(cachedConfig)
end

-- Limpa cache (chamado ao deslogar/trocar de char)
_Helper.AlarmSettings.clearCache = function()
  cachedConfig = nil
end

-- ===== MODAL =====

_Helper.AlarmSettings.open = function()
  if alarmSettingsWindow then
    alarmSettingsWindow:destroy()
    alarmSettingsWindow = nil
  end

  alarmSettingsWindow = g_ui.createWidget('AlarmSettingsWindow', g_ui.getRootWidget())

  -- Carregar estado de cada tipo de alarme no modal
  _Helper.LowCapacityAlarm.loadToModal(alarmSettingsWindow)
  _Helper.LowCapacityAlarm.setupModalThresholdInput(alarmSettingsWindow)
  _Helper.FullDustAlarm.loadToModal(alarmSettingsWindow)
  _Helper.PrivateMessageAlarm.loadToModal(alarmSettingsWindow)
  _Helper.LowHealthAlarm.loadToModal(alarmSettingsWindow)
  _Helper.LowHealthAlarm.setupModalThresholdInput(alarmSettingsWindow)
  _Helper.LowManaAlarm.loadToModal(alarmSettingsWindow)
  _Helper.LowManaAlarm.setupModalThresholdInput(alarmSettingsWindow)

  -- Sempre o ultimo alarme a ser carregado no modal
  _Helper.LowSupplyAlarm.loadToModal(alarmSettingsWindow)

end

_Helper.AlarmSettings.close = function()
  -- Close supply settings first (if open)
  if _Helper.LowSupplyAlarm and _Helper.LowSupplyAlarm.closeSettings then
    -- Temporarily clear alarmSettingsWindow so closeSettings doesn't try to show it
    local win = alarmSettingsWindow
    alarmSettingsWindow = nil
    _Helper.LowSupplyAlarm.closeSettings()
    alarmSettingsWindow = win
  end

  if alarmSettingsWindow then
    alarmSettingsWindow:destroy()
    alarmSettingsWindow = nil
  end
end

_Helper.AlarmSettings.getWindow = function()
  return alarmSettingsWindow
end

-- ===== FIM HELPER ALARM SETTINGS =====
