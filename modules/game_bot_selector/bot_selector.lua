local BOT_KINDS = {
  vbot = {
    setting = "astraVBotEnabled",
    moduleName = "game_bot"
  },
  minibot = {
    setting = "astraMiniBotEnabled",
    moduleName = "game_minibot"
  }
}

local optionWidgets = {}
local synchronizing = false

local function getOtherKind(kind)
  return kind == "vbot" and "minibot" or "vbot"
end

local function getModule(kind)
  local definition = BOT_KINDS[kind]
  return definition and g_modules.getModule(definition.moduleName) or nil
end

local function unloadBot(kind)
  local botModule = getModule(kind)
  if botModule and botModule:isLoaded() then
    botModule:unload()
  end
end

local function loadBot(kind)
  local definition = BOT_KINDS[kind]
  local botModule = getModule(kind)
  if not definition or not botModule then
    g_logger.error(string.format("[BotSelector] Module for '%s' was not found.", tostring(kind)))
    return false
  end

  if botModule:isLoaded() then
    return true
  end

  if not botModule:load() then
    g_logger.error(string.format("[BotSelector] Unable to load module '%s'.", definition.moduleName))
    return false
  end

  return true
end

local function syncOptionWidgets()
  synchronizing = true
  for kind, widget in pairs(optionWidgets) do
    if widget then
      widget:setChecked(g_settings.getBoolean(BOT_KINDS[kind].setting))
    end
  end
  synchronizing = false
end

local function disableAll()
  for kind, definition in pairs(BOT_KINDS) do
    g_settings.set(definition.setting, false)
    unloadBot(kind)
  end
end

function init()
  for _, definition in pairs(BOT_KINDS) do
    g_settings.setDefault(definition.setting, false)
  end

  local vbotEnabled = g_settings.getBoolean(BOT_KINDS.vbot.setting)
  local minibotEnabled = g_settings.getBoolean(BOT_KINDS.minibot.setting)

  -- A manually edited or old configuration must never start two automation
  -- engines at once. Resolve the invalid state to the safe default: both off.
  if vbotEnabled and minibotEnabled then
    disableAll()
  elseif vbotEnabled and not loadBot("vbot") then
    g_settings.set(BOT_KINDS.vbot.setting, false)
  elseif minibotEnabled and not loadBot("minibot") then
    g_settings.set(BOT_KINDS.minibot.setting, false)
  end
end

function terminate()
  unloadBot("vbot")
  unloadBot("minibot")
  optionWidgets = {}
end

function setupOptionWidget(kind, widget)
  if not BOT_KINDS[kind] or not widget then
    return
  end

  optionWidgets[kind] = widget
  syncOptionWidgets()
end

function onOptionChanged(kind, enabled)
  if synchronizing or not BOT_KINDS[kind] then
    return
  end

  if enabled then
    local otherKind = getOtherKind(kind)
    g_settings.set(BOT_KINDS[otherKind].setting, false)
    unloadBot(otherKind)

    if loadBot(kind) then
      g_settings.set(BOT_KINDS[kind].setting, true)
    else
      g_settings.set(BOT_KINDS[kind].setting, false)
    end
  else
    g_settings.set(BOT_KINDS[kind].setting, false)
    unloadBot(kind)
  end

  g_settings.save()
  syncOptionWidgets()
end

function isEnabled(kind)
  return BOT_KINDS[kind] and g_settings.getBoolean(BOT_KINDS[kind].setting) or false
end
