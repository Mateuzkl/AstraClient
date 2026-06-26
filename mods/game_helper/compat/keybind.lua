
CHAT_MODE = {
  ON = 1,
  OFF = 2
}

Keybind = {
  presets = {},
  presetToIndex = {},
  currentPreset = nil,
  configs = {
    keybinds = {},
    hotkeys = {}
  },
  defaultKeys = {
    [CHAT_MODE.ON] = {},
    [CHAT_MODE.OFF] = {}
  },
  defaultKeybinds = {},
  hotkeys = {
    [CHAT_MODE.ON] = {},
    [CHAT_MODE.OFF] = {}
  },
  chatMode = CHAT_MODE.ON,

  reservedKeys = {
    ["Up"] = true,
    ["Down"] = true,
    ["Left"] = true,
    ["Right"] = true
  }
}

KEY_UP = 1
KEY_DOWN = 2
KEY_PRESS = 3

HOTKEY_ACTION = {
  USE_YOURSELF = 1,
  USE_CROSSHAIR = 2,
  USE_TARGET = 3,
  EQUIP = 4,
  USE = 5,
  TEXT = 6,
  TEXT_AUTO = 7,
  SPELL = 8
}

-- Maps client vocation ID to base preset name
local function vocationToPresetName(vocationId)
  if not vocationId or type(vocationId) ~= 'number' then return nil end
  local map = {
    [1] = "Knight",   [11] = "Knight",   -- Knight / Elite Knight
    [2] = "Paladin",  [12] = "Paladin",  -- Paladin / Royal Paladin
    [3] = "Sorcerer", [13] = "Sorcerer", -- Sorcerer / Master Sorcerer
    [4] = "Druid",    [14] = "Druid",    -- Druid / Elder Druid
  }
  return map[vocationId]
end

function Keybind.init()
  Keybind._onGameStart = function() Keybind.online() end
  Keybind._onGameEnd = function() Keybind.offline() end
  connect(g_game, { onGameStart = Keybind._onGameStart, onGameEnd = Keybind._onGameEnd })

  Keybind.presets = g_settings.getList("controls-presets")

  if #Keybind.presets == 0 then
    Keybind.presets = { "Druid", "Knight", "Paladin", "Sorcerer" }
    Keybind.currentPreset = "Druid"
  else
    Keybind.currentPreset = g_settings.getValue("controls-preset-current")
    -- Validate that currentPreset exists in the presets list
    local presetExists = false
    for _, preset in ipairs(Keybind.presets) do
      if preset == Keybind.currentPreset then
        presetExists = true
        break
      end
    end
    if not presetExists then
      Keybind.currentPreset = Keybind.presets[1]
    end
  end

  for index, preset in ipairs(Keybind.presets) do
    Keybind.presetToIndex[preset] = index
  end

  if not g_resources.directoryExists("/controls") then
    g_resources.makeDir("/controls")
  end

  if not g_resources.directoryExists("/controls/keybinds") then
    g_resources.makeDir("/controls/keybinds")
  end

  if not g_resources.directoryExists("/controls/hotkeys") then
    g_resources.makeDir("/controls/hotkeys")
  end

  for _, preset in ipairs(Keybind.presets) do
    Keybind.configs.keybinds[preset] = g_configs.create("/controls/keybinds/" .. preset .. ".otml")
    Keybind.configs.hotkeys[preset] = g_configs.create("/controls/hotkeys/" .. preset .. ".otml")
  end

  -- NOTE: Standard hotkey loading from preset .otml files is disabled.
  -- The "New Action" button in General Hotkeys is disabled and the system is unused.
  -- Any stale data in /controls/hotkeys/*.otml files is intentionally ignored.
  -- User-configured hotkeys are handled by the Custom Hotkeys system (per-character).
  for chatMode = CHAT_MODE.ON, CHAT_MODE.OFF do
    for _, preset in ipairs(Keybind.presets) do
      Keybind.hotkeys[chatMode][preset] = {}
    end
  end
end

function Keybind.terminate()
  disconnect(g_game, { onGameStart = Keybind._onGameStart, onGameEnd = Keybind._onGameEnd })

  for _, preset in ipairs(Keybind.presets) do
    Keybind.configs.keybinds[preset]:save()
    Keybind.configs.hotkeys[preset]:save()
  end

  g_settings.setList("controls-presets", Keybind.presets)
  g_settings.setValue("controls-preset-current", Keybind.currentPreset)
  g_settings.save()
end

function Keybind.online()
  -- Load per-character preset
  local charName = g_game.getCharacterName()
  local charPresets = g_settings.getNode('controls-preset-per-char') or {}
  local savedPreset = charPresets[charName]

  local localPlayer = g_game.getLocalPlayer()

  if savedPreset and Keybind.presetToIndex[savedPreset] then
    Keybind.selectPreset(savedPreset)
  else
    if localPlayer then
      local vocId = localPlayer:getVocation()
      local presetName = vocationToPresetName(vocId)
      if presetName and Keybind.presetToIndex[presetName] then
        Keybind.selectPreset(presetName)
        charPresets[charName] = presetName
        g_settings.setNode('controls-preset-per-char', charPresets)
        g_settings.save()
      end
    end
  end
end

function Keybind.offline()
  -- Standard hotkeys are disabled; nothing to unbind here.
  -- Custom hotkeys are unbound by customHk_onGameEnd().
end

function Keybind.new(category, action, primary, secondary, alone)
  local index = category .. '_' .. action
  if Keybind.defaultKeybinds[index] then
    pwarning(string.format("Keybind for [%s: %s] is already in use", category, action))
    return
  end

  local keys = {}
  if type(primary) == "string" then
    keys[CHAT_MODE.ON] = { primary = primary }
    keys[CHAT_MODE.OFF] = { primary = primary }
  else
    keys[CHAT_MODE.ON] = { primary = primary[CHAT_MODE.ON] }
    keys[CHAT_MODE.OFF] = { primary = primary[CHAT_MODE.OFF] }
  end

  if type(secondary) == "string" then
    keys[CHAT_MODE.ON].secondary = secondary
    keys[CHAT_MODE.OFF].secondary = secondary
  else
    keys[CHAT_MODE.ON].secondary = secondary[CHAT_MODE.ON]
    keys[CHAT_MODE.OFF].secondary = secondary[CHAT_MODE.OFF]
  end

  keys[CHAT_MODE.ON].primary = retranslateKeyComboDesc(keys[CHAT_MODE.ON].primary)

  if keys[CHAT_MODE.ON].secondary then
    keys[CHAT_MODE.ON].secondary = retranslateKeyComboDesc(keys[CHAT_MODE.ON].secondary)
  end

  keys[CHAT_MODE.OFF].primary = retranslateKeyComboDesc(keys[CHAT_MODE.OFF].primary)

  if keys[CHAT_MODE.OFF].secondary then
    keys[CHAT_MODE.OFF].secondary = retranslateKeyComboDesc(keys[CHAT_MODE.OFF].secondary)
  end

  if Keybind.defaultKeys[CHAT_MODE.ON][keys[CHAT_MODE.ON].primary] then
    local primaryIndex = Keybind.defaultKeys[CHAT_MODE.ON][keys[CHAT_MODE.ON].primary]
    local primaryKeybind = Keybind.defaultKeybinds[primaryIndex]
    perror(string.format("Default primary key (Chat Mode On) assigned to [%s: %s] is already in use by [%s: %s]",
      category, action, primaryKeybind.category, primaryKeybind.action))
    return
  end

  if Keybind.defaultKeys[CHAT_MODE.OFF][keys[CHAT_MODE.OFF].primary] then
    local primaryIndex = Keybind.defaultKeys[CHAT_MODE.OFF][keys[CHAT_MODE.OFF].primary]
    local primaryKeybind = Keybind.defaultKeybinds[primaryIndex]
    perror(string.format("Default primary key (Chat Mode Off) assigned to [%s: %s] is already in use by [%s: %s]",
      category, action, primaryKeybind.category, primaryKeybind.action))
    return
  end

  if keys[CHAT_MODE.ON].secondary and Keybind.defaultKeys[CHAT_MODE.ON][keys[CHAT_MODE.ON].secondary] then
    local secondaryIndex = Keybind.defaultKeys[CHAT_MODE.ON][keys[CHAT_MODE.ON].secondary]
    local secondaryKeybind = Keybind.defaultKeybinds[secondaryIndex]
    perror(string.format("Default secondary key (Chat Mode On) assigned to [%s: %s] is already in use by [%s: %s]",
      category, action, secondaryKeybind.category, secondaryKeybind.action))
    return
  end

  if keys[CHAT_MODE.OFF].secondary and Keybind.defaultKeys[CHAT_MODE.OFF][keys[CHAT_MODE.OFF].secondary] then
    local secondaryIndex = Keybind.defaultKeys[CHAT_MODE.OFF][keys[CHAT_MODE.OFF].secondary]
    local secondaryKeybind = Keybind.defaultKeybinds[secondaryIndex]
    perror(string.format("Default secondary key (Chat Mode Off) assigned to [%s: %s] is already in use by [%s: %s]",
      category, action, secondaryKeybind.category, secondaryKeybind.action))
    return
  end

  if keys[CHAT_MODE.ON].primary then
    Keybind.defaultKeys[CHAT_MODE.ON][keys[CHAT_MODE.ON].primary] = index
  end

  if keys[CHAT_MODE.OFF].primary then
    Keybind.defaultKeys[CHAT_MODE.OFF][keys[CHAT_MODE.OFF].primary] = index
  end

  Keybind.defaultKeybinds[index] = {
    category = category,
    action = action,
    keys = keys,
    alone = alone
  }

  if keys[CHAT_MODE.ON].secondary then
    Keybind.defaultKeys[CHAT_MODE.ON][keys[CHAT_MODE.ON].secondary] = index
  end
  if keys[CHAT_MODE.OFF].secondary then
    Keybind.defaultKeys[CHAT_MODE.OFF][keys[CHAT_MODE.OFF].secondary] = index
  end
end

function Keybind.delete(category, action)
  local index = category .. '_' .. action
  local keybind = Keybind.defaultKeybinds[index]

  if not keybind then
    return
  end

  Keybind.unbind(category, action)

  local keysOn = keybind.keys[CHAT_MODE.ON]
  local keysOff = keybind.keys[CHAT_MODE.OFF]

  local primaryOn = keysOn.primary and tostring(keysOn.primary) or nil
  local primaryOff = keysOff.primary and tostring(keysOff.primary) or nil
  local secondaryOn = keysOn.secondary and tostring(keysOn.secondary) or nil
  local secondaryOff = keysOff.secondary and tostring(keysOff.secondary) or nil

  if primaryOn and primaryOn:len() > 0 then
    Keybind.defaultKeys[CHAT_MODE.ON][primaryOn] = nil
  end
  if secondaryOn and secondaryOn:len() > 0 then
    Keybind.defaultKeys[CHAT_MODE.ON][secondaryOn] = nil
  end

  if primaryOff and primaryOff:len() > 0 then
    Keybind.defaultKeys[CHAT_MODE.OFF][primaryOff] = nil
  end
  if secondaryOff and secondaryOff:len() > 0 then
    Keybind.defaultKeys[CHAT_MODE.OFF][secondaryOff] = nil
  end

  Keybind.defaultKeybinds[index] = nil
end

function Keybind.sanitize()
  local cleaned = 0
  for index, keybind in pairs(Keybind.defaultKeybinds) do
    if keybind.widget and type(keybind.widget) == 'userdata' and keybind.widget.isDestroyed and keybind.widget:isDestroyed() then
      keybind.widget = nil
      keybind.callbacks = nil
      cleaned = cleaned + 1
    end
  end
  return cleaned
end

function Keybind.bind(category, action, callbacks, widget)
  if widget and type(widget) == 'userdata' and widget.isDestroyed and widget:isDestroyed() then
    return
  end

  local index = category .. '_' .. action
  local keybind = Keybind.defaultKeybinds[index]

  if not keybind then
    return
  end

  keybind.callbacks = callbacks
  keybind.widget = widget

  local keys = Keybind.getKeybindKeys(category, action)

  for _, callback in ipairs(keybind.callbacks) do
    if callback.type == KEY_UP then
      if keys.primary then
        keys.primary = tostring(keys.primary)
        if keys.primary:len() > 0 then
          g_keyboard.bindKeyUp(keys.primary, callback.callback, keybind.widget, callback.alone)
        end
      end
      if keys.secondary then
        keys.secondary = tostring(keys.secondary)
        if keys.secondary:len() > 0 then
          g_keyboard.bindKeyUp(keys.secondary, callback.callback, keybind.widget, callback.alone)
        end
      end
    elseif callback.type == KEY_DOWN then
      if keys.primary then
        keys.primary = tostring(keys.primary)
        if keys.primary:len() > 0 then
          g_keyboard.bindKeyDown(keys.primary, callback.callback, keybind.widget, callback.alone)
        end
      end
      if keys.secondary then
        keys.secondary = tostring(keys.secondary)
        if keys.secondary:len() > 0 then
          g_keyboard.bindKeyDown(keys.secondary, callback.callback, keybind.widget, callback.alone)
        end
      end
    elseif callback.type == KEY_PRESS then
      if keys.primary then
        keys.primary = tostring(keys.primary)
        if keys.primary:len() > 0 then
          g_keyboard.bindKeyPress(keys.primary, callback.callback, keybind.widget)
        end
      end
      if keys.secondary then
        keys.secondary = tostring(keys.secondary)
        if keys.secondary:len() > 0 then
          g_keyboard.bindKeyPress(keys.secondary, callback.callback, keybind.widget)
        end
      end
    end
  end
end

function Keybind.unbind(category, action)
  local index = category .. '_' .. action
  local keybind = Keybind.defaultKeybinds[index]

  if not keybind or not keybind.callbacks then
    return
  end

  local keys = Keybind.getKeybindKeys(category, action)

  for _, callback in ipairs(keybind.callbacks) do
    if callback.type == KEY_UP then
      if keys.primary then
        keys.primary = tostring(keys.primary)
        if keys.primary:len() > 0 then
          g_keyboard.unbindKeyUp(keys.primary, callback.callback, keybind.widget)
        end
      end
      if keys.secondary then
        keys.secondary = tostring(keys.secondary)
        if keys.secondary:len() > 0 then
          g_keyboard.unbindKeyUp(keys.secondary, callback.callback, keybind.widget)
        end
      end
    elseif callback.type == KEY_DOWN then
      if keys.primary then
        keys.primary = tostring(keys.primary)
        if keys.primary:len() > 0 then
          g_keyboard.unbindKeyDown(keys.primary, callback.callback, keybind.widget)
        end
      end
      if keys.secondary then
        keys.secondary = tostring(keys.secondary)
        if keys.secondary:len() > 0 then
          g_keyboard.unbindKeyDown(keys.secondary, callback.callback, keybind.widget)
        end
      end
    elseif callback.type == KEY_PRESS then
      if keys.primary then
        keys.primary = tostring(keys.primary)
        if keys.primary:len() > 0 then
          g_keyboard.unbindKeyPress(keys.primary, callback.callback, keybind.widget)
        end
      end
      if keys.secondary then
        keys.secondary = tostring(keys.secondary)
        if keys.secondary:len() > 0 then
          g_keyboard.unbindKeyPress(keys.secondary, callback.callback, keybind.widget)
        end
      end
    end
  end
end

function Keybind.newPreset(presetName)
  if Keybind.presetToIndex[presetName] then
    return
  end

  table.insert(Keybind.presets, presetName)
  Keybind.presetToIndex[presetName] = #Keybind.presets

  Keybind.configs.keybinds[presetName] = g_configs.create("/controls/keybinds/" .. presetName .. ".otml")
  Keybind.configs.hotkeys[presetName] = g_configs.create("/controls/hotkeys/" .. presetName .. ".otml")

  Keybind.hotkeys[CHAT_MODE.ON][presetName] = {}
  Keybind.hotkeys[CHAT_MODE.OFF][presetName] = {}

  g_settings.setList("controls-presets", Keybind.presets)
  g_settings.save()
end

function Keybind.copyPreset(fromPreset, toPreset)
  if Keybind.presetToIndex[toPreset] then
    return false
  end

  table.insert(Keybind.presets, toPreset)
  Keybind.presetToIndex[toPreset] = #Keybind.presets

  Keybind.configs.keybinds[fromPreset]:save()
  Keybind.configs.hotkeys[fromPreset]:save()

  local keybindsConfigPath = Keybind.configs.keybinds[fromPreset]:getFileName()
  local keybindsConfigContent = g_resources.readFileContents(keybindsConfigPath)
  g_resources.writeFileContents("/controls/keybinds/" .. toPreset .. ".otml", keybindsConfigContent)
  Keybind.configs.keybinds[toPreset] = g_configs.create("/controls/keybinds/" .. toPreset .. ".otml")

  local hotkeysConfigPath = Keybind.configs.hotkeys[fromPreset]:getFileName()
  local hotkeysConfigContent = g_resources.readFileContents(hotkeysConfigPath)
  g_resources.writeFileContents("/controls/hotkeys/" .. toPreset .. ".otml", hotkeysConfigContent)
  Keybind.configs.hotkeys[toPreset] = g_configs.create("/controls/hotkeys/" .. toPreset .. ".otml")

  for chatMode = CHAT_MODE.ON, CHAT_MODE.OFF do
    Keybind.hotkeys[chatMode][toPreset] = {}

    local hotkeyId = 1
    local hotkeys = Keybind.configs.hotkeys[toPreset]:getNode(chatMode)

    if hotkeys then
      local hotkey = hotkeys[tostring(hotkeyId)] or hotkeys[hotkeyId]
      while hotkey do
        if hotkey.data and hotkey.data.parameter then
          hotkey.data.parameter = "\"" .. hotkey.data.parameter .. "\"" -- forcing quotes cause OTML is not saving them, just wow
        end

        table.insert(Keybind.hotkeys[chatMode][toPreset], hotkey)
        hotkeyId = hotkeyId + 1

        hotkey = hotkeys[tostring(hotkeyId)] or hotkeys[hotkeyId]
      end
    end
  end

  g_settings.setList("controls-presets", Keybind.presets)
  g_settings.save()

  return true
end

function Keybind.renamePreset(oldPresetName, newPresetName)
  if Keybind.currentPreset == oldPresetName then
    Keybind.currentPreset = newPresetName
  end

  local index = Keybind.presetToIndex[oldPresetName]
  Keybind.presetToIndex[oldPresetName] = nil
  Keybind.presetToIndex[newPresetName] = index
  Keybind.presets[index] = newPresetName

  local keybindsConfigPath = Keybind.configs.keybinds[oldPresetName]:getFileName()
  Keybind.configs.keybinds[oldPresetName]:save()
  Keybind.configs.keybinds[oldPresetName] = nil

  local keybindsConfigContent = g_resources.readFileContents(keybindsConfigPath)
  g_resources.deleteFile(keybindsConfigPath)
  g_resources.writeFileContents("/controls/keybinds/" .. newPresetName .. ".otml", keybindsConfigContent)
  Keybind.configs.keybinds[newPresetName] = g_configs.create("/controls/keybinds/" .. newPresetName .. ".otml")

  local hotkeysConfigPath = Keybind.configs.hotkeys[oldPresetName]:getFileName()
  Keybind.configs.hotkeys[oldPresetName]:save()
  Keybind.configs.hotkeys[oldPresetName] = nil

  local hotkeysConfigContent = g_resources.readFileContents(hotkeysConfigPath)
  g_resources.deleteFile(hotkeysConfigPath)
  g_resources.writeFileContents("/controls/hotkeys/" .. newPresetName .. ".otml", hotkeysConfigContent)
  Keybind.configs.hotkeys[newPresetName] = g_configs.create("/controls/hotkeys/" .. newPresetName .. ".otml")

  Keybind.hotkeys[CHAT_MODE.ON][newPresetName] = Keybind.hotkeys[CHAT_MODE.ON][oldPresetName]
  Keybind.hotkeys[CHAT_MODE.OFF][newPresetName] = Keybind.hotkeys[CHAT_MODE.OFF][oldPresetName]

  g_settings.setList("controls-presets", Keybind.presets)
  g_settings.save()
end

function Keybind.removePreset(presetName)
  if #Keybind.presets == 1 then
    return false
  end

  table.remove(Keybind.presets, Keybind.presetToIndex[presetName])
  Keybind.presetToIndex[presetName] = nil

  Keybind.configs.keybinds[presetName] = nil
  g_configs.unload("/controls/keybinds/" .. presetName .. ".otml")
  g_resources.deleteFile("/controls/keybinds/" .. presetName .. ".otml")

  Keybind.configs.hotkeys[presetName] = nil
  g_configs.unload("/controls/hotkeys/" .. presetName .. ".otml")
  g_resources.deleteFile("/controls/hotkeys/" .. presetName .. ".otml")

  if Keybind.currentPreset == presetName then
    Keybind.currentPreset = Keybind.presets[1]
  end

  g_settings.setList("controls-presets", Keybind.presets)
  g_settings.save()

  return true
end

function Keybind.selectPreset(presetName)
  if Keybind.currentPreset == presetName then
    return false
  end

  if not Keybind.presetToIndex[presetName] then
    return false
  end

  for _, keybind in pairs(Keybind.defaultKeybinds) do
    if keybind.callbacks then
      Keybind.unbind(keybind.category, keybind.action)
    end
  end

  Keybind.currentPreset = presetName

  local function rebindKeybinds()
    for _, keybind in pairs(Keybind.defaultKeybinds) do
      if keybind.callbacks then
        if keybind.widget and type(keybind.widget) == 'userdata' and keybind.widget.isDestroyed and keybind.widget:isDestroyed() then
          keybind.widget = nil
          keybind.callbacks = nil
        else
          Keybind.bind(keybind.category, keybind.action, keybind.callbacks, keybind.widget)
        end
      end
    end
  end

  local ok, err = pcall(rebindKeybinds)
  if not ok then
    g_logger.warning('[Keybind] selectPreset rebind failed: ' .. tostring(err) .. ' — sanitizing and retrying')
    Keybind.sanitize()
    local ok2, err2 = pcall(rebindKeybinds)
    if not ok2 then
      g_logger.error('[Keybind] selectPreset recovery failed: ' .. tostring(err2))
    end
  end

  -- Save preset choice per character
  if g_game.isOnline() then
    local charName = g_game.getCharacterName()
    if charName and charName ~= '' then
      local charPresets = g_settings.getNode('controls-preset-per-char') or {}
      charPresets[charName] = presetName
      g_settings.setNode('controls-preset-per-char', charPresets)
      g_settings.save()
    end
  end

  return true
end

function Keybind.getAction(category, action)
  local index = category .. '_' .. action
  return Keybind.defaultKeybinds[index]
end

function Keybind.setPrimaryActionKey(category, action, preset, keyCombo, chatMode)
  local index = category .. '_' .. action
  local keybind = Keybind.defaultKeybinds[index]
  local config = preset and Keybind.configs.keybinds[preset]
  
  if not config then
    return false
  end

  local keys = config:getNode(index)
  if not keys then
    keys = table.recursivecopy(keybind.keys)
  else
    chatMode = tostring(chatMode)
  end

  if keybind.callbacks then
    Keybind.unbind(category, action)
  end
  
  if not keys[chatMode] then
    keys[chatMode] = { primary = keyCombo, secondary = keybind.keys[tonumber(chatMode)].secondary }
  end

  keys[chatMode].primary = keyCombo

  local ret = false
  if keys[chatMode].secondary == keyCombo then
    keys[chatMode].secondary = nil
    ret = true
  end

  Keybind.configs.keybinds[preset]:setNode(index, keys)

  if keybind.callbacks then
    Keybind.bind(category, action, keybind.callbacks, keybind.widget)
  end

  return ret
end

function Keybind.setSecondaryActionKey(category, action, preset, keyCombo, chatMode)
  local index = category .. '_' .. action
  local keybind = Keybind.defaultKeybinds[index]
  local config = preset and Keybind.configs.keybinds[preset]
  
  if not config then
    return false
  end

  local keys = config:getNode(index)
  if not keys then
    keys = table.recursivecopy(keybind.keys)
  else
    chatMode = tostring(chatMode)
  end

  if keybind.callbacks then
    Keybind.unbind(category, action)
  end
  
  if not keys[chatMode] then
    keys[chatMode] = { primary = keybind.keys[tonumber(chatMode)].primary, secondary = keyCombo }
  end

  keys[chatMode].secondary = keyCombo

  local ret = false
  if keys[chatMode].primary == keyCombo then
    keys[chatMode].primary = nil
    ret = true
  end

  config:setNode(index, keys)

  if keybind.callbacks then
    Keybind.bind(category, action, keybind.callbacks, keybind.widget)
  end

  return ret
end

function Keybind.resetKeybindsToDefault(presetName, chatMode)
  if not chatMode then
    chatMode = Keybind.chatMode
  end

  local config = presetName and Keybind.configs.keybinds[presetName]
  if not config then
    return
  end

  for _, keybind in pairs(Keybind.defaultKeybinds) do
    if keybind.callbacks then
      Keybind.unbind(keybind.category, keybind.action)
    end
  end

  for _, keybind in pairs(Keybind.defaultKeybinds) do
    local index = keybind.category .. '_' .. keybind.action
    config:setNode(index, keybind.keys)
  end

  local function rebindKeybinds()
    for _, keybind in pairs(Keybind.defaultKeybinds) do
      if keybind.callbacks then
        if keybind.widget and type(keybind.widget) == 'userdata' and keybind.widget.isDestroyed and keybind.widget:isDestroyed() then
          keybind.widget = nil
          keybind.callbacks = nil
        else
          Keybind.bind(keybind.category, keybind.action, keybind.callbacks, keybind.widget)
        end
      end
    end
  end

  local ok, err = pcall(rebindKeybinds)
  if not ok then
    g_logger.warning('[Keybind] resetKeybindsToDefault failed: ' .. tostring(err) .. ' — sanitizing and retrying')
    Keybind.sanitize()
    local ok2, err2 = pcall(rebindKeybinds)
    if not ok2 then
      g_logger.error('[Keybind] resetKeybindsToDefault recovery failed: ' .. tostring(err2))
    end
  end
end

function Keybind.getKeybindKeys(category, action, chatMode, preset, forceDefault)
  if not chatMode then
    chatMode = Keybind.chatMode
  end

  local index = category .. '_' .. action
  local keybind = Keybind.defaultKeybinds[index]
  local presetName = preset or Keybind.currentPreset
  local config = presetName and Keybind.configs.keybinds[presetName]
  local keys = nil
  
  if config then
    keys = config:getNode(index)
  end

  if not keys or forceDefault then
    if keybind and keybind.keys and keybind.keys[chatMode] then
      keys = {
        primary = keybind.keys[chatMode].primary,
        secondary = keybind.keys[chatMode].secondary
      }
    end
  else
    keys = keys[chatMode] or keys[tostring(chatMode)]
  end

  if not keys then
    keys = {
      primary = "",
      secondary = ""
    }
  end

  return keys
end

function Keybind.isKeyComboUsed(keyCombo, category, action, chatMode)
  if not chatMode then
    chatMode = Keybind.chatMode
  end

  if Keybind.reservedKeys[keyCombo] then
    return true
  end

  -- Quando category e action sao passados (edicao de General Hotkey), permitir mesma tecla em varias acoes
  if category and action then
    -- Nao considerar outros general keybinds como conflito; apenas reservedKeys acima
    -- (custom hotkeys e action bar sao checados em keybins.lua)
  else
    for _, keybind in pairs(Keybind.defaultKeybinds) do
      local keys = Keybind.getKeybindKeys(keybind.category, keybind.action, chatMode, Keybind.currentPreset)
      if keys.primary == keyCombo or keys.secondary == keyCombo then
        return true
      end
    end

    local hotkeys = Keybind.hotkeys[chatMode] and Keybind.hotkeys[chatMode][Keybind.currentPreset]
    if hotkeys then
      for _, hotkey in ipairs(hotkeys) do
        if hotkey.primary == keyCombo or hotkey.secondary == keyCombo then
          return true
        end
      end
    end
  end

  return false
end

function Keybind.newHotkey(action, data, primary, secondary, chatMode)
  if not chatMode then
    chatMode = Keybind.chatMode
  end

  local hotkey = {
    action = action,
    data = data,
    primary = primary or "",
    secondary = secondary or ""
  }

  if not Keybind.hotkeys[chatMode][Keybind.currentPreset] then
    Keybind.hotkeys[chatMode][Keybind.currentPreset] = {}
  end

  table.insert(Keybind.hotkeys[chatMode][Keybind.currentPreset], hotkey)

  local hotkeyId = #Keybind.hotkeys[chatMode][Keybind.currentPreset]
  hotkey.hotkeyId = hotkeyId
  Keybind.configs.hotkeys[Keybind.currentPreset]:setNode(chatMode, Keybind.hotkeys[chatMode][Keybind.currentPreset])
  Keybind.configs.hotkeys[Keybind.currentPreset]:save()

  Keybind.bindHotkey(hotkeyId, chatMode)
end

function Keybind.removeHotkey(hotkeyId, chatMode)
  if not chatMode then
    chatMode = Keybind.chatMode
  end

  local hotkeys = Keybind.hotkeys[chatMode] and Keybind.hotkeys[chatMode][Keybind.currentPreset]
  if not hotkeys then
    return
  end

  Keybind.unbindHotkey(hotkeyId, chatMode)

  table.remove(hotkeys, hotkeyId)

  -- Re-index remaining hotkeys
  for id, hotkey in ipairs(hotkeys) do
    hotkey.hotkeyId = id
  end

  -- Save correctly under the chatMode key (not top-level)
  Keybind.configs.hotkeys[Keybind.currentPreset]:setNode(chatMode, hotkeys)
  Keybind.configs.hotkeys[Keybind.currentPreset]:save()
end

function Keybind.editHotkey(hotkeyId, action, data, chatMode)
  if not chatMode then
    chatMode = Keybind.chatMode
  end

  Keybind.unbindHotkey(hotkeyId, chatMode)

  local hotkey = Keybind.hotkeys[chatMode][Keybind.currentPreset][hotkeyId]
  hotkey.action = action
  hotkey.data = data
  Keybind.configs.hotkeys[Keybind.currentPreset]:setNode(chatMode, Keybind.hotkeys[chatMode][Keybind.currentPreset])
  Keybind.configs.hotkeys[Keybind.currentPreset]:save()

  Keybind.bindHotkey(hotkeyId, chatMode)
end

function Keybind.editHotkeyKeys(hotkeyId, primary, secondary, chatMode)
  if not chatMode then
    chatMode = Keybind.chatMode
  end

  Keybind.unbindHotkey(hotkeyId, chatMode)

  local hotkey = Keybind.hotkeys[chatMode][Keybind.currentPreset][hotkeyId]
  hotkey.primary = primary or ""
  hotkey.secondary = secondary or ""
  Keybind.configs.hotkeys[Keybind.currentPreset]:setNode(chatMode, Keybind.hotkeys[chatMode][Keybind.currentPreset])
  Keybind.configs.hotkeys[Keybind.currentPreset]:save()

  Keybind.bindHotkey(hotkeyId, chatMode)
end

function Keybind.removeAllHotkeys(chatMode)
  if not chatMode then
    chatMode = Keybind.chatMode
  end

  local hotkeys = Keybind.hotkeys[chatMode] and Keybind.hotkeys[chatMode][Keybind.currentPreset]
  if hotkeys then
    for _, hotkey in ipairs(hotkeys) do
      Keybind.unbindHotkey(hotkey.hotkeyId, chatMode)
    end
  end

  if Keybind.hotkeys[chatMode] then
    Keybind.hotkeys[chatMode][Keybind.currentPreset] = {}
  end

  Keybind.configs.hotkeys[Keybind.currentPreset]:remove(chatMode)
  Keybind.configs.hotkeys[Keybind.currentPreset]:save()
end

function Keybind.getHotkeyKeys(hotkeyId, preset, chatMode)
  if not chatMode then
    chatMode = Keybind.chatMode
  end
  if not preset then
    preset = Keybind.currentPreset
  end

  local keys = { primary = "", secondary = "" }
  if not Keybind.hotkeys[chatMode] or not Keybind.hotkeys[chatMode][preset] then
    return keys
  end

  local hotkey = Keybind.hotkeys[chatMode][preset][hotkeyId]
  if not hotkey then
    return keys
  end

  -- Read from runtime data directly (always correct types)
  return {
    primary = hotkey.primary or "",
    secondary = hotkey.secondary or ""
  }
end

function Keybind.hotkeyCallback(hotkeyId, chatMode)
  if not chatMode then
    chatMode = Keybind.chatMode
  end

  local hotkey = Keybind.hotkeys[chatMode][Keybind.currentPreset][hotkeyId]

  if not hotkey then
    return
  end

  local action = hotkey.action
  local data = hotkey.data

  if action == HOTKEY_ACTION.USE_YOURSELF then
    if g_game.getClientVersion() < 780 then
      local item = g_game.findPlayerItem(data.itemId, data.subType or -1)

      if item then
        g_game.useWith(item, g_game.getLocalPlayer())
      end
    else
      g_game.useInventoryItemWith(data.itemId, g_game.getLocalPlayer(), data.subType or -1)
    end
  elseif action == HOTKEY_ACTION.USE_CROSSHAIR then
    local item = Item.create(data.itemId)

    if g_game.getClientVersion() < 780 then
      item = g_game.findPlayerItem(data.itemId, data.subType or -1)
    end

    if item then
      modules.game_interface.startUseWith(item, data.subType or -1)
    end
  elseif action == HOTKEY_ACTION.USE_TARGET then
    local attackingCreature = g_game.getAttackingCreature()
    if not attackingCreature then
      local item = Item.create(data.itemId)

      if g_game.getClientVersion() < 780 then
        item = g_game.findPlayerItem(data.itemId, data.subType or -1)
      end

      if item then
        modules.game_interface.startUseWith(item, data.subType or -1)
      end

      return
    end

    if attackingCreature:getTile() then
      if g_game.getClientVersion() < 780 then
        local item = g_game.findPlayerItem(data.itemId, data.subType or -1)
        if item then
          g_game.useWith(item, attackingCreature, data.subType or -1)
        end
      else
        g_game.useInventoryItemWith(data.itemId, attackingCreature, data.subType or -1)
      end
    end
  elseif action == HOTKEY_ACTION.EQUIP then
    if g_game.getClientVersion() >= 910 then
      local item = Item.create(data.itemId)

      g_game.equipItem(item)
    end
  elseif action == HOTKEY_ACTION.USE then
    if g_game.getClientVersion() < 780 then
      local item = g_game.findPlayerItem(data.itemId, data.subType or -1)

      if item then
        g_game.use(item)
      end
    else
      g_game.useInventoryItem(data.itemId)
    end
  elseif action == HOTKEY_ACTION.TEXT then
    if modules.game_interface.isChatVisible() then
      modules.game_console.setTextEditText(hotkey.data.text)
    end
  elseif action == HOTKEY_ACTION.TEXT_AUTO then
    if modules.game_interface.isChatVisible() then
      modules.game_console.sendMessage(hotkey.data.text)
    else
      g_game.talk(hotkey.data.text)
    end
  elseif action == HOTKEY_ACTION.SPELL then
    local text = data.words
    if data.parameter then
      text = text .. " " .. data.parameter
    end

    if modules.game_interface.isChatVisible() then
      modules.game_console.sendMessage(text)
    else
      g_game.talk(text)
    end
  end
end

function Keybind.bindHotkey(hotkeyId, chatMode)
  if not chatMode or chatMode ~= Keybind.chatMode then
    return
  end

  if not modules.game_interface then
    return
  end

  local hotkey = Keybind.hotkeys[chatMode][Keybind.currentPreset][hotkeyId]

  if not hotkey then
    return
  end

  local gameRootPanel = modules.game_interface.getRootPanel()
  local action = hotkey.action
  local primary = tostring(hotkey.primary or "")
  local secondary = tostring(hotkey.secondary or "")

  hotkey.callback = function() Keybind.hotkeyCallback(hotkeyId, chatMode) end

  if primary:len() > 0 then
    if action == HOTKEY_ACTION.EQUIP or action == HOTKEY_ACTION.USE or action == HOTKEY_ACTION.TEXT or action == HOTKEY_ACTION.TEXT_AUTO then
      g_keyboard.bindKeyDown(primary, hotkey.callback, gameRootPanel)
    else
      g_keyboard.bindKeyPress(primary, hotkey.callback, gameRootPanel)
    end
  end

  if secondary:len() > 0 then
    if action == HOTKEY_ACTION.EQUIP or action == HOTKEY_ACTION.USE or action == HOTKEY_ACTION.TEXT or action == HOTKEY_ACTION.TEXT_AUTO then
      g_keyboard.bindKeyDown(secondary, hotkey.callback, gameRootPanel)
    else
      g_keyboard.bindKeyPress(secondary, hotkey.callback, gameRootPanel)
    end
  end
end

function Keybind.unbindHotkey(hotkeyId, chatMode)
  if not chatMode or chatMode ~= Keybind.chatMode then
    return
  end

  if not modules.game_interface then
    return
  end

  local hotkey = Keybind.hotkeys[chatMode][Keybind.currentPreset][hotkeyId]

  if not hotkey then
    return
  end

  local gameRootPanel = modules.game_interface.getRootPanel()
  local action = hotkey.action
  local primary = tostring(hotkey.primary or "")
  local secondary = tostring(hotkey.secondary or "")

  if primary:len() > 0 then
    if action == HOTKEY_ACTION.EQUIP or action == HOTKEY_ACTION.USE or action == HOTKEY_ACTION.TEXT or action == HOTKEY_ACTION.TEXT_AUTO then
      g_keyboard.unbindKeyDown(primary, hotkey.callback, gameRootPanel)
    else
      g_keyboard.unbindKeyPress(primary, hotkey.callback, gameRootPanel)
    end
  end

  if secondary:len() > 0 then
    if action == HOTKEY_ACTION.EQUIP or action == HOTKEY_ACTION.USE or action == HOTKEY_ACTION.TEXT or action == HOTKEY_ACTION.TEXT_AUTO then
      g_keyboard.unbindKeyDown(secondary, hotkey.callback, gameRootPanel)
    else
      g_keyboard.unbindKeyPress(secondary, hotkey.callback, gameRootPanel)
    end
  end
end

function Keybind.setChatMode(chatMode)
  if Keybind.chatMode == chatMode then
    return
  end

  for _, keybind in pairs(Keybind.defaultKeybinds) do
    if keybind.callbacks then
      Keybind.unbind(keybind.category, keybind.action)
    end
  end

  local hotkeysToUnbind = Keybind.hotkeys[Keybind.chatMode] and Keybind.hotkeys[Keybind.chatMode][Keybind.currentPreset]
  if hotkeysToUnbind then
    for _, hotkey in ipairs(hotkeysToUnbind) do
      Keybind.unbindHotkey(hotkey.hotkeyId, Keybind.chatMode)
    end
  end

  if modules.game_walking then
    modules.game_walking.unbindTurnKeys()
  end

  Keybind.chatMode = chatMode

  local function rebindAll()
    for _, keybind in pairs(Keybind.defaultKeybinds) do
      if keybind.callbacks then
        if keybind.widget and type(keybind.widget) == 'userdata' and keybind.widget.isDestroyed and keybind.widget:isDestroyed() then
          keybind.widget = nil
          keybind.callbacks = nil
        else
          Keybind.bind(keybind.category, keybind.action, keybind.callbacks, keybind.widget)
        end
      end
    end

    local hotkeysToBind = Keybind.hotkeys[chatMode] and Keybind.hotkeys[chatMode][Keybind.currentPreset]
    if hotkeysToBind then
      for _, hotkey in ipairs(hotkeysToBind) do
        Keybind.bindHotkey(hotkey.hotkeyId, chatMode)
      end
    end

    if modules.game_walking then
      modules.game_walking.bindTurnKeys()
    end
  end

  local ok, err = pcall(rebindAll)
  if not ok then
    g_logger.warning('[Keybind] setChatMode failed: ' .. tostring(err) .. ' — sanitizing and retrying')
    Keybind.sanitize()
    local ok2, err2 = pcall(rebindAll)
    if not ok2 then
      g_logger.error('[Keybind] setChatMode recovery failed: ' .. tostring(err2))
    end
  end
end
