if not _Helper then
  _Helper = {}
end

_Helper.HotkeyManager = {}

local hotkeyManager = _Helper.HotkeyManager

local helperWidget = nil
local executingHotkeyKeyCode = nil

local function getAssignBlockedKeys()
  if type(AssignBlockedKeys) == 'table' then
    return AssignBlockedKeys
  end
  if type(blockedKeys) == 'table' then
    return blockedKeys
  end
  return {}
end

local function containsHotkey(list, value)
  if type(list) ~= 'table' or value == nil then
    return false
  end
  for _, item in pairs(list) do
    if item == value then
      return true
    end
  end
  return false
end

local function helperDebug(message)
  if _Helper and _Helper.debugLog then
    _Helper.debugLog(message)
  end
end

local function getGameRootPanel()
  if rootWidget and rootWidget.getChildById then
    return rootWidget:getChildById('gameRootPanel')
  end
  return nil
end

local function bindHelperKeyDown(code, callback)
  if not g_keyboard or not code or code == '' or not callback then
    return
  end

  g_keyboard.bindKeyDown(code, callback)

  local gameRootPanel = getGameRootPanel()
  if gameRootPanel then
    g_keyboard.bindKeyDown(code, callback, gameRootPanel)
  end
end

local function unbindHelperKeyDown(code, callback)
  if not g_keyboard or not code or code == '' then
    return
  end

  g_keyboard.unbindKeyDown(code, callback)

  local gameRootPanel = getGameRootPanel()
  if gameRootPanel then
    g_keyboard.unbindKeyDown(code, callback, gameRootPanel)
  end
end

local function isFunctionKey(keyCode)
  return keyCode and keyCode >= KeyF1 and keyCode <= KeyF12
end

local function makeBoundToggle(def)
  local toggleFunc = def.makeToggle()
  return function(widget, keyCode, ...)
    helperDebug("hotkey fired type=" .. tostring(def.type) ..
      " keyCode=" .. tostring(keyCode) ..
      " combo=" .. tostring(helperConfig and helperConfig[def.codeKey]))
    local previousKeyCode = executingHotkeyKeyCode
    executingHotkeyKeyCode = keyCode
    local ok, err = pcall(toggleFunc, widget, keyCode, ...)
    executingHotkeyKeyCode = previousKeyCode
    if not ok then
      error(err)
    end
    return true
  end
end

function hotkeyManager.setHelperWidget(widget)
  helperWidget = widget
end

-- Verifica se as hotkeys do helper podem ser ativadas
-- Retorna false em janelas bloqueantes e em campos de texto quando nao for F1-F12.
local function canExecuteHelperHotkey()
  local allowTextFocus = isFunctionKey(executingHotkeyKeyCode)

  local consoleTextEdit = modules.game_console and modules.game_console.getConsole and modules.game_console.getConsole()
  if not allowTextFocus and consoleTextEdit and consoleTextEdit.isFocused and consoleTextEdit:isFocused() then
    helperDebug("hotkey blocked: console text focused")
    return false
  end

  if modules.game_interface and modules.game_interface.isInternalLocked and modules.game_interface.isInternalLocked() then
    helperDebug("hotkey blocked: internal interface locked")
    return false
  end

  if modules.game_npctrade and modules.game_npctrade.npcWindow then
    local npcWindow = modules.game_npctrade.npcWindow
    if npcWindow:isVisible() then
      if not allowTextFocus and modules.game_npctrade.searchText and modules.game_npctrade.searchText:isFocused() then
        helperDebug("hotkey blocked: npc search focused")
        return false
      end
      if not allowTextFocus and modules.game_npctrade.amountText and modules.game_npctrade.amountText:isFocused() then
        helperDebug("hotkey blocked: npc amount focused")
        return false
      end
    end
  end

  if modules.game_modaldialog and modules.game_modaldialog.modalDialog then
    local modalDialog = modules.game_modaldialog.modalDialog
    if modalDialog:isVisible() then
      local searchInput = modalDialog:recursiveGetChildById('searchInput')
      if not allowTextFocus and searchInput and searchInput:isFocused() then
        helperDebug("hotkey blocked: modal search focused")
        return false
      end
    end
  end

  local storeUI = modules.game_store and modules.game_store.getUI and modules.game_store.getUI()
  if storeUI and storeUI:isVisible() and storeUI.SearchEdit then
    if not allowTextFocus and storeUI.SearchEdit:isFocused() then
      helperDebug("hotkey blocked: store search focused")
      return false
    end
  end


  return true
end

-- Table-driven hotkey definitions. Each entry defines one configurable hotkey.
-- Adding a new hotkey = adding one entry here. All generic functions iterate this table.
local HOTKEY_DEFS = {
  {
    type = "Enable/Disable Helper",
    codeKey = "hotkeyCode",
    funcKey = "hotkeyFunc",
    makeToggle = function()
      return function()
        if not canExecuteHelperHotkey() then return end
        if toggleHelperFunctions then
          toggleHelperFunctions()
          return
        end

        if _Helper.setHelperAutomaticFunctionsEnabled and _Helper.isHelperAutomaticFunctionsEnabled then
          local enabled = not _Helper.isHelperAutomaticFunctionsEnabled()
          _Helper.setHelperAutomaticFunctionsEnabled(enabled)
          if botStatus then
            botStatus()
          end
          if _Helper.Shortcut and _Helper.Shortcut.syncButton then
            _Helper.Shortcut.syncButton('shortcutHelper', enabled)
          end
          if saveSettings then
            saveSettings()
          end
        end
      end
    end,
  },
  {
    type = "Enable/Disable Auto Target",
    codeKey = "autoTargetHotkeyCode",
    funcKey = "autoTargetHotkeyFunc",
    makeToggle = function()
      return function()
        if not canExecuteHelperHotkey() then return end
        local widget = enableButtons and enableButtons:recursiveGetChildById("enableAutoTarget")
        if widget then
          widget:setChecked(not widget:isChecked())
          toggleAutoTarget(widget)
        end
      end
    end,
  },
  {
    type = "Enable/Disable Magic Shooter",
    codeKey = "magicShooterHotkeyCode",
    funcKey = "magicShooterHotkeyFunc",
    makeToggle = function()
      return function()
        if not canExecuteHelperHotkey() then return end
        local widget = enableButtons and enableButtons:recursiveGetChildById("enableMagicShooter")
        if widget then
          widget:setChecked(not widget:isChecked())
          toggleMagicShooter(widget)
        end
      end
    end,
  },
  {
    type = "Enable/Disable Target and Magic Shooter",
    codeKey = "targetMagicShooterHotkeyCode",
    funcKey = "targetMagicShooterHotkeyFunc",
    makeToggle = function()
      return function()
        if not canExecuteHelperHotkey() then return end
        local autoTargetWidget = enableButtons and enableButtons:recursiveGetChildById("enableAutoTarget")
        local magicShooterWidget = enableButtons and enableButtons:recursiveGetChildById("enableMagicShooter")

        if autoTargetWidget then
          autoTargetWidget:setChecked(not autoTargetWidget:isChecked())
          toggleAutoTarget(autoTargetWidget)
        end

        if magicShooterWidget then
          magicShooterWidget:setChecked(not magicShooterWidget:isChecked())
          toggleMagicShooter(magicShooterWidget)
        end
      end
    end,
  },
  {
    type = "Change Shooter Preset",
    codeKey = "presetHotkeyCode",
    funcKey = "presetHotkeyFunc",
    makeToggle = function()
      return function()
        if not canExecuteHelperHotkey() then return end
        local pm = modules.game_helper and modules.game_helper.presetManager
        if pm then
          local ctx = pm.getShooterContext()
          if ctx then pm.togglePreset(ctx, nil, false) end
        end
        if modules.game_helper and modules.game_helper.magicShooter then
          modules.game_helper.magicShooter.updateRulesList()
        end
      end
    end,
  },
  {
    type = "Change Equipment Preset",
    codeKey = "equipPresetHotkeyCode",
    funcKey = "equipPresetHotkeyFunc",
    makeToggle = function()
      return function()
        if not canExecuteHelperHotkey() then return end
        if modules.game_helper and modules.game_helper.equip then
          modules.game_helper.equip.togglePreset(nil, false)
          modules.game_helper.equip.updateRulesList()
        end
      end
    end,
  },
  {
    type = "Enable/Disable Equipment",
    codeKey = "equipmentHotkeyCode",
    funcKey = "equipmentHotkeyFunc",
    makeToggle = function()
      return function()
        if not canExecuteHelperHotkey() then return end
        if modules.game_helper and modules.game_helper.equip then
          local enabled = modules.game_helper.equip.isEnabled()
          modules.game_helper.equip.toggleEquipment(not enabled)
          local equipPanel = modules.game_helper.equip.getPanel()
          if equipPanel then
            local enableEquipmentPanel = equipPanel:getChildById('enableEquipmentPanel')
            if enableEquipmentPanel then
              local enableCheckbox = enableEquipmentPanel:getChildById('enableEquipment')
              if enableCheckbox then
                enableCheckbox:setChecked(not enabled)
              end
            end
          end
        end
      end
    end,
  },
  {
    type = "Enable/Disable Cavebot",
    codeKey = "cavebotHotkeyCode",
    funcKey = "cavebotHotkeyFunc",
    makeToggle = function()
      return function()
        if not canExecuteHelperHotkey() then return end
        if modules.game_helper and modules.game_helper.cavebot then
          local enabled = modules.game_helper.cavebot.isEnabled()
          modules.game_helper.cavebot.toggle(not enabled)
        end
      end
    end,
  },
  {
    type = "Toggle Recording",
    codeKey = "recordingHotkeyCode",
    funcKey = "recordingHotkeyFunc",
    makeToggle = function()
      return function()
        if not canExecuteHelperHotkey() then return end
        if modules.game_helper and modules.game_helper.cavebot then
          modules.game_helper.cavebot.toggleRecording()
        end
      end
    end,
  },
  {
    type = "Enable/Disable Timer",
    codeKey = "timerHotkeyCode",
    funcKey = "timerHotkeyFunc",
    makeToggle = function()
      return function()
        if not canExecuteHelperHotkey() then return end
        if helperConfig then
          helperConfig.timerEnabled = not helperConfig.timerEnabled
          if _Helper.Shortcut and _Helper.Shortcut.syncButton then
            _Helper.Shortcut.syncButton('shortcutTimer', helperConfig.timerEnabled)
          end
          if modules.game_helper and modules.game_helper.timerPanel and modules.game_helper.timerPanel.syncEnableTimer then
            modules.game_helper.timerPanel.syncEnableTimer()
          end
          saveSettings()
        end
      end
    end,
  },
  {
    type = "Enable/Disable Supply Alarm",
    codeKey = "supplyAlarmHotkeyCode",
    funcKey = "supplyAlarmHotkeyFunc",
    makeToggle = function()
      return function()
        if not canExecuteHelperHotkey() then return end
        if _Helper.LowSupplyAlarm then
          local config = _Helper.AlarmSettings.getConfig()
          config.supply.enabled = not config.supply.enabled
          _Helper.AlarmSettings.saveConfig()
          -- Sync checkbox no alarm settings modal se estiver aberto
          local window = _Helper.AlarmSettings.getWindow()
          if window then
            local cb = window:recursiveGetChildById("lowSupplyAlarm")
            if cb then cb:setChecked(config.supply.enabled) end
          end
        end
      end
    end,
  },
  {
    type = "Change Supply Preset",
    codeKey = "supplyPresetHotkeyCode",
    funcKey = "supplyPresetHotkeyFunc",
    makeToggle = function()
      return function()
        if not canExecuteHelperHotkey() then return end
        local pm = modules.game_helper and modules.game_helper.presetManager
        if pm then
          local ctx = pm.getSupplyContext() or pm.buildSupplyContext()
          if ctx then pm.togglePreset(ctx, nil, false) end
        end
      end
    end,
  },
}

hotkeyManager.HOTKEY_DEFS = HOTKEY_DEFS

local function findDef(hotkeyType)
  for _, def in ipairs(HOTKEY_DEFS) do
    if def.type == hotkeyType then return def end
  end
end

function hotkeyManager.unregister(def)
  local code = helperConfig[def.codeKey]
  local func = helperConfig[def.funcKey]
  if code and code ~= "" and func then
    unbindHelperKeyDown(code, func)
  end
  helperConfig[def.funcKey] = nil
end

function hotkeyManager.unregisterAll()
  if not g_keyboard then return end
  for _, def in ipairs(HOTKEY_DEFS) do
    hotkeyManager.unregister(def)
  end
end

function hotkeyManager.register(def)
  local code = helperConfig[def.codeKey]
  if code and code ~= "" then
    local toggleFunc = makeBoundToggle(def)
    helperConfig[def.funcKey] = toggleFunc
    bindHelperKeyDown(code, toggleFunc)
    helperDebug("hotkey registered type=" .. tostring(def.type) .. " combo=" .. tostring(code))
  end
end

function hotkeyManager.registerAll()
  if not g_keyboard then return end
  for _, def in ipairs(HOTKEY_DEFS) do
    hotkeyManager.register(def)
  end
end

function hotkeyManager.isInUse(keyCombo, excludeType)
  for _, def in ipairs(HOTKEY_DEFS) do
    if def.type ~= excludeType and helperConfig[def.codeKey] == keyCombo then
      return def.type
    end
  end
  return nil
end

function hotkeyManager.clearConflicting(keyCombo)
  for _, def in ipairs(HOTKEY_DEFS) do
    if helperConfig[def.codeKey] == keyCombo then
      if helperConfig[def.funcKey] then
        unbindHelperKeyDown(keyCombo, helperConfig[def.funcKey])
      else
        unbindHelperKeyDown(keyCombo)
      end
      helperConfig[def.codeKey] = ""
      helperConfig[def.funcKey] = nil
    end
  end
end

function hotkeyManager.assign(def, keyComboDesc)
  if helperConfig[def.codeKey] and helperConfig[def.codeKey] ~= "" then
    if helperConfig[def.funcKey] then
      unbindHelperKeyDown(helperConfig[def.codeKey], helperConfig[def.funcKey])
    else
      unbindHelperKeyDown(helperConfig[def.codeKey])
    end
  end
  hotkeyManager.clearConflicting(keyComboDesc)
  local toggleFunc = makeBoundToggle(def)
  helperConfig[def.codeKey] = keyComboDesc
  helperConfig[def.funcKey] = toggleFunc
  bindHelperKeyDown(keyComboDesc, toggleFunc)
  helperDebug("hotkey assigned type=" .. tostring(def.type) .. " combo=" .. tostring(keyComboDesc))
  saveSettings()
end

function hotkeyManager.clear(def)
  if helperConfig[def.codeKey] and helperConfig[def.codeKey] ~= "" then
    if helperConfig[def.funcKey] then
      unbindHelperKeyDown(helperConfig[def.codeKey], helperConfig[def.funcKey])
    else
      unbindHelperKeyDown(helperConfig[def.codeKey])
    end
    helperConfig[def.codeKey] = ""
    helperConfig[def.funcKey] = nil
  end
end

function hotkeyManager.preserveFuncs()
  local saved = {}
  for _, def in ipairs(HOTKEY_DEFS) do
    saved[def.funcKey] = helperConfig[def.funcKey]
  end
  return saved
end

function hotkeyManager.restoreFuncs(saved)
  for _, def in ipairs(HOTKEY_DEFS) do
    helperConfig[def.funcKey] = saved[def.funcKey]
  end
end

function hotkeyManager.preserveAll()
  local saved = {}
  for _, def in ipairs(HOTKEY_DEFS) do
    saved[def.codeKey] = helperConfig[def.codeKey]
    saved[def.funcKey] = helperConfig[def.funcKey]
  end
  return saved
end

function hotkeyManager.restoreAll(saved)
  for _, def in ipairs(HOTKEY_DEFS) do
    helperConfig[def.codeKey] = saved[def.codeKey]
    helperConfig[def.funcKey] = saved[def.funcKey]
  end
end

function hotkeyManager.manageHotkeys(typo)
  local def = findDef(typo)
  if not def then
    helperDebug("manageHotkeys ignored unknown type=" .. tostring(typo))
    return
  end

  helperDebug("manageHotkeys open type=" .. tostring(typo))

  if not helperWidget then
    helperDebug("manageHotkeys aborted: helperWidget missing")
    return
  end

  helperWidget:hide()

  if typo == "Toggle Recording" and modules.game_helper and modules.game_helper.cavebot then
    modules.game_helper.cavebot.hideSettingsWindow()
  end

  local assignWindow = g_ui.createWidget('ActionAssignWindow', rootWidget)
  if not assignWindow then
    helperWidget:show(true)
    if typo == "Toggle Recording" and modules.game_helper and modules.game_helper.cavebot then
      modules.game_helper.cavebot.showSettingsWindow()
    end
    return
  end

  assignWindow:setText(tostring(typo))

  local displayLabel = assignWindow:recursiveGetChildById('display')
  local descLabel = assignWindow:recursiveGetChildById('desc')
  local buttonOk = assignWindow:recursiveGetChildById('buttonOk')
  local buttonClose = assignWindow:recursiveGetChildById('buttonClose')
  local buttonClear = assignWindow:recursiveGetChildById('buttonClear')

  if not displayLabel or not descLabel or not buttonOk or not buttonClose then
    assignWindow:destroy()
    helperWidget:show(true)
    return
  end

  local keyCodeMap = {
    [49] = "1", [50] = "2", [51] = "3", [52] = "4", [53] = "5",
    [54] = "6", [55] = "7", [56] = "8", [57] = "9", [48] = "0",
    [65] = "A", [66] = "B", [67] = "C", [68] = "D", [69] = "E",
    [70] = "F", [71] = "G", [72] = "H", [73] = "I", [74] = "J",
    [75] = "K", [76] = "L", [77] = "M", [78] = "N", [79] = "O",
    [80] = "P", [81] = "Q", [82] = "R", [83] = "S", [84] = "T",
    [85] = "U", [86] = "V", [87] = "W", [88] = "X", [89] = "Y",
    [90] = "Z",
    [43] = "Plus",
    [45] = "-",
    [141] = "Num0", [142] = "Num1", [143] = "Num2", [144] = "Num3",
    [145] = "Num4", [146] = "Num5", [147] = "Num6", [148] = "Num7",
    [149] = "Num8", [150] = "Num9",
    [151] = "NumEnter", [152] = "NumPlus", [153] = "NumMinus",
    [154] = "NumMultiply", [155] = "NumDivide", [156] = "NumDecimal",
  }

  local capturedKeyCode = nil
  local capturedKeyChar = ""

  local currentHotkey = helperConfig[def.codeKey]

  if currentHotkey and currentHotkey ~= "" then
    displayLabel:setText(currentHotkey)
    capturedKeyChar = currentHotkey
    if buttonClear then
      buttonClear:setEnabled(true)
    end
  else
    displayLabel:setText("(press a key)")
    if buttonClear then
      buttonClear:setEnabled(false)
    end
  end

  descLabel:setText("Assign hotkey to: " .. tostring(typo))

  assignWindow.onKeyDown = function(widget, keyCode, keyboardModifiers, keyText)
    if keyCode == KeyUp or keyCode == KeyDown or keyCode == KeyLeft or keyCode == KeyRight then
      return false
    end
    local keyCombo = determineKeyComboDesc(keyCode, keyboardModifiers, keyText)
    local resetCombo = { "Shift", "Ctrl", "Alt" }
    if containsHotkey(resetCombo, keyCombo) then
      assignWindow.display:setText('')
      assignWindow.warning:setVisible(false)
      assignWindow.buttonOk:setEnabled(true)
      return true
    end
    local displayText = keyCombo or keyCodeMap[keyCode] or tostring(keyCode)

    if containsHotkey(getAssignBlockedKeys(), keyCombo) then
      assignWindow.warning:setVisible(true)
      assignWindow.warning:setText("This hotkey is already in use and cannot be overwritten.")
      assignWindow.buttonOk:setEnabled(false)
    else
      local conflictWith = hotkeyManager.isInUse(displayText, typo)
      if conflictWith then
        assignWindow.warning:setVisible(true)
        local formattedTypo = conflictWith:gsub("Enable/Disable ", "")
        assignWindow.warning:setText(string.format(
          "This hotkey is already in use by: %s.\nIf you want to proceed, the previous assignment\nwill be cleared.",
          formattedTypo))
        assignWindow.buttonOk:setEnabled(true)
      else
        assignWindow.warning:setVisible(false)
        assignWindow.buttonOk:setEnabled(true)
      end
    end

    capturedKeyCode = keyCode
    capturedKeyChar = displayText
    displayLabel:setText(displayText)
    return true
  end

  buttonOk.onClick = function()
    local keyComboDesc = tostring(displayLabel:getText())

    if not keyComboDesc or keyComboDesc == "" or keyComboDesc == "(pressione uma tecla)" or keyComboDesc == "(press a key)" then
      hotkeyManager.clear(def)
      saveSettings()
      assignWindow:destroy()
      helperWidget:show(true)
      return
    end

    if not g_keyboard then
      assignWindow:destroy()
      helperWidget:show(true)
      return
    end

    hotkeyManager.assign(def, keyComboDesc)

    assignWindow:destroy()
    helperWidget:show(true)
    if typo == "Toggle Recording" and modules.game_helper and modules.game_helper.cavebot then
      modules.game_helper.cavebot.showSettingsWindow()
    end
  end

  buttonClose.onClick = function()
    assignWindow:destroy()
    helperWidget:show(true)
    if typo == "Toggle Recording" and modules.game_helper and modules.game_helper.cavebot then
      modules.game_helper.cavebot.showSettingsWindow()
    end
  end

  if buttonClear then
    buttonClear.onClick = function()
      local hotkeyToRemove = helperConfig[def.codeKey]

      displayLabel:setText("(press a key)")
      capturedKeyCode = nil
      capturedKeyChar = ""

      if hotkeyToRemove and hotkeyToRemove ~= "" then
        assignWindow.warning:setVisible(true)
        assignWindow.warning:setText("Hotkey '" .. hotkeyToRemove .. "' will be removed if you confirm.")
      else
        assignWindow.warning:setVisible(false)
      end

      assignWindow.buttonOk:setEnabled(true)
    end
  end

  assignWindow.onDestroy = function(widget)
    helperWidget:show(true)
  end
end
