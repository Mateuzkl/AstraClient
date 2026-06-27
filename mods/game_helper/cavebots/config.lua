-- CaveBot Config Module
-- Sistema de configuração extensível baseado na referência game_bot
-- Adaptado para OFICIAL-OTC-AMON com configurações especiais

CaveBot = CaveBot or {}
CaveBot.Config = {}
CaveBot.Config.values = {}
CaveBot.Config.default_values = {}
CaveBot.Config.value_setters = {}

-- ============================================================================
-- SETUP - Inicializa configurações padrão
-- ============================================================================

CaveBot.Config.setup = function()
  local add = CaveBot.Config.add

  -- Configurações da referência (walking)
  add("ping", "Server ping", 100)
  add("walkDelay", "Walk delay", 20)
  add("mapClick", "Use map click", false)
  add("mapClickDelay", "Map click delay", 50)
  add("walkMode", "Walk mode", "walk")  -- "walk" ou "click"
  add("ignoreFields", "Ignore fields", false)
  add("skipBlocked", "Skip blocked path", false)
  add("useDelay", "Delay after use", 400)

  -- Configurações especiais do usuário (hunting)
  add("nodeDistance", "Node distance", 2)
  add("stopToKillDistance", "Stop to kill distance", 2)
  add("creaturesToStop", "Creatures to stop", 99)
  add("creaturesToWalk", "Creatures to walk", 99)
  add("finishKillMobCount", "Finish kill mob count", 0)
  add("finishKillHpPct", "Finish kill HP %", 30)
  add("lureMode", "Lure mode", false)
  add("lureDebug", "Lure debug", false)
  add("lureCheckRangeX", "Lure check X", 6)
  add("lureCheckRangeY", "Lure check Y", 4)
  add("lureWaypointLookAhead", "Lure waypoint look-ahead", 10)
  add("lureWaypointRadius", "Lure waypoint radius", 4)
  add("lureApproachInterval", "Lure approach window (ms)", 1500)
  add("avoidTrap", "Avoid trap", false)
  add("trapDistance", "Trap distance", 1)
  add("creaturesToAvoid", "Creatures to avoid", 7)
  add("staminaToLeave", "Stamina to leave", 39)
  add("staminaToReturn", "Stamina to return", 42)
  add("capToLeave", "Cap to leave", 500)
  add("deathsToDisable", "Deaths to disable", 0)
  add("ignoredCreatures", "Ignored creatures", {})
  add("specialAreas", "Special areas (blocked)", {})
  add("zRecovery", "Z-Recovery (auto floor return)", true)

  -- Stop-to-kill smart filter (lure-aware): only counts mobs that are
  -- reachable AND approaching, with a hard wait cap so the bot can't get
  -- pinned by an off-screen / unreachable mob still in CreatureCache range.
  add("stopToKillSmart", "Stop to kill: smart filter", true)
  add("stopToKillMaxWait", "Stop to kill: max wait (ms)", 60000)
  add("stopToKillStuckTimeout", "Stop to kill: stuck timeout (ms)", 3000)
  add("stopToKillRequirePath", "Stop to kill: require reachable path", true)
  add("stopToKillEmptyGrace", "Stop to kill: empty grace (ms)", 5000)
end

-- ============================================================================
-- CONFIG CHANGE - Chamado quando configuração muda
-- ============================================================================

CaveBot.Config.onConfigChange = function(configName, isEnabled, configData)
  -- Restaurar valores padrão
  for k, v in pairs(CaveBot.Config.default_values) do
    if CaveBot.Config.value_setters[k] then
      CaveBot.Config.value_setters[k](v)
    else
      CaveBot.Config.values[k] = v
    end
  end

  -- Aplicar novos valores se fornecidos
  if not configData then return end
  for k, v in pairs(configData) do
    if CaveBot.Config.value_setters[k] then
      CaveBot.Config.value_setters[k](v)
    elseif CaveBot.Config.values[k] ~= nil then
      CaveBot.Config.values[k] = v
    end
  end
end

-- ============================================================================
-- SAVE - Retorna valores para salvar
-- ============================================================================

CaveBot.Config.save = function()
  return CaveBot.Config.values
end

-- ============================================================================
-- ADD - Adiciona uma configuração
-- ============================================================================

CaveBot.Config.add = function(id, title, defaultValue)
  if CaveBot.Config.values[id] ~= nil then
    return -- Já existe, não duplicar
  end

  local setter
  if type(defaultValue) == "number" then
    setter = function(value)
      CaveBot.Config.values[id] = tonumber(value) or defaultValue
    end
  elseif type(defaultValue) == "boolean" then
    setter = function(value)
      if type(value) == "boolean" then
        CaveBot.Config.values[id] = value
      elseif type(value) == "string" then
        CaveBot.Config.values[id] = value:lower() == "true"
      else
        CaveBot.Config.values[id] = defaultValue
      end
    end
  elseif type(defaultValue) == "table" then
    setter = function(value)
      if type(value) == "table" then
        CaveBot.Config.values[id] = value
      else
        CaveBot.Config.values[id] = defaultValue
      end
    end
  else
    setter = function(value)
      CaveBot.Config.values[id] = value or defaultValue
    end
  end

  CaveBot.Config.value_setters[id] = setter
  CaveBot.Config.values[id] = defaultValue
  CaveBot.Config.default_values[id] = defaultValue
end

-- ============================================================================
-- GET - Obtém valor de uma configuração
-- ============================================================================

CaveBot.Config.get = function(id)
  if CaveBot.Config.values[id] == nil then
    error("Invalid CaveBot.Config.get, id: " .. tostring(id))
  end
  return CaveBot.Config.values[id]
end

-- ============================================================================
-- SET - Define valor de uma configuração
-- ============================================================================

CaveBot.Config.set = function(id, value)
  if CaveBot.Config.value_setters[id] then
    CaveBot.Config.value_setters[id](value)
  elseif CaveBot.Config.values[id] ~= nil then
    CaveBot.Config.values[id] = value
  else
    error("Invalid CaveBot.Config.set, id: " .. tostring(id))
  end
end

-- ============================================================================
-- SYNC FROM UI - Sincroniza valores da UI existente
-- ============================================================================

CaveBot.Config.syncFromUI = function(settingsData)
  if not settingsData then return end

  -- Mapear campos da UI para config
  local mapping = {
    nodeDistance = "nodeDistance",
    stopToKillDistance = "stopToKillDistance",
    stopAt = "creaturesToStop",
    resumeAt = "creaturesToWalk",
    delayWalk = "walkDelay",
    walkModeWalk = function(v) return not v end, -- inverte para mapClick
    walkModeClick = "mapClick",
    lure = "lureMode",
    lureDebug = "lureDebug",
    checkX = "lureCheckRangeX",
    checkY = "lureCheckRangeY",
    approachInterval = "lureApproachInterval",
    avoidTrap = "avoidTrap",
    trapDistance = "trapDistance",
    creaturesToAvoid = "creaturesToAvoid",
    staminaToLeave = "staminaToLeave",
    staminaToReturn = "staminaToReturn",
    capToLeave = "capToLeave",
    deathsToDisable = "deathsToDisable",
    ignoredMobsText = "ignoredCreatures",
    zRecovery = "zRecovery"
  }

  for uiField, configField in pairs(mapping) do
    if settingsData[uiField] ~= nil then
      if type(configField) == "function" then
        -- Transformação especial
      elseif type(configField) == "string" then
        CaveBot.Config.set(configField, settingsData[uiField])
      end
    end
  end
end

-- Inicializar configurações automaticamente
CaveBot.Config.setup()

return CaveBot.Config
