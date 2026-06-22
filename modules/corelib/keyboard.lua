-- @docclass
g_keyboard = {}

-- private functions
function translateKeyCombo(keyCombo)
  if not keyCombo or #keyCombo == 0 then
    return nil
  end

  local keyComboDesc = ''
  local modifierDesc = {[21] = "Ctrl", [22] = "Shift", [23] = "Alt"}

  for k,v in pairs(keyCombo) do
    if not v then 
      return nil
    end

    if modifierDesc[v] then
      keyComboDesc = keyComboDesc .. '+' .. modifierDesc[v]
    else
      if #v == 1 and v:match("%a") then
        keyComboDesc = keyComboDesc .. '+' .. v:upper()
      else
        keyComboDesc = keyComboDesc .. '+' .. v
      end
    end
  end

  keyComboDesc = keyComboDesc:sub(2)
  return keyComboDesc
end

function getKeyCode(key)
  for keyCode, keyDesc in pairs(KeyCodeDescs) do
    if keyDesc:lower() == key:trim():lower() then
      return keyCode
    end
  end
end

function getKeyDesc(code)
  for keyCode, keyDesc in pairs(KeyCodeDescs) do
    if code == keyCode then
      return keyDesc
    end
  end
end

function retranslateKeyComboDesc(keyComboDesc)
  if keyComboDesc == nil then
    error('Unable to translate key combo \'' .. keyComboDesc .. '\'')
  end

  if type(keyComboDesc) == 'number' then
    keyComboDesc = tostring(keyComboDesc)
  end

  local keyCombo = {}
  for i,currentKeyDesc in ipairs(keyComboDesc:split('+')) do
    table.insert(keyCombo, currentKeyDesc)
  end
  return translateKeyCombo(keyCombo)
end

function g_keyboard.determineKeyComboDescription(keyCode, keyboardModifiers, keyText)
  local keyCombo = {}

  if not keyText or string.empty(keyText) or (keyCode >= KeyNumpad0 and keyCode <= KeyNumpad9) then
    keyText = KeyCodeDescs[keyCode]
  end

  if keyCode == KeyCtrl or keyCode == KeyShift or keyCode == KeyAlt then
    table.insert(keyCombo, keyCode)
  elseif keyText then
    if keyboardModifiers == KeyboardCtrlModifier then
      table.insert(keyCombo, KeyCtrl)
    elseif keyboardModifiers == KeyboardAltModifier then
      table.insert(keyCombo, KeyAlt)
    elseif keyboardModifiers == KeyboardCtrlAltModifier then
      table.insert(keyCombo, KeyCtrl)
      table.insert(keyCombo, KeyAlt)
    elseif keyboardModifiers == KeyboardShiftModifier then
      table.insert(keyCombo, KeyShift)
    elseif keyboardModifiers == KeyboardCtrlShiftModifier then
      table.insert(keyCombo, KeyCtrl)
      table.insert(keyCombo, KeyShift)
    elseif keyboardModifiers == KeyboardAltShiftModifier then
      table.insert(keyCombo, KeyAlt)
      table.insert(keyCombo, KeyShift)
    elseif keyboardModifiers == KeyboardCtrlAltShiftModifier then
      table.insert(keyCombo, KeyCtrl)
      table.insert(keyCombo, KeyAlt)
      table.insert(keyCombo, KeyShift)
    end
    table.insert(keyCombo, keyText)
  end
  return translateKeyCombo(keyCombo)
end

determineKeyComboDesc = g_keyboard.determineKeyComboDescription

local function onWidgetKeyDown(widget, keyCode, keyboardModifiers, keyText)
  if not keyText or string.empty(keyText) then
    keyText = KeyCodeDescs[keyCode]
  end

  if keyCode == KeyUnknown then return false end
  local callback = widget.boundAloneKeyDownCombos[g_keyboard.determineKeyComboDescription(keyCode, KeyboardNoModifier, keyText)]
  signalcall(callback, widget, keyCode)
  callback = widget.boundKeyDownCombos[g_keyboard.determineKeyComboDescription(keyCode, keyboardModifiers, keyText)]
  return signalcall(callback, widget, keyCode, keyText)
end

local function onWidgetKeyUp(widget, keyCode, keyboardModifiers)
  if keyCode == KeyUnknown then return false end
  local callback = widget.boundAloneKeyUpCombos[g_keyboard.determineKeyComboDescription(keyCode, KeyboardNoModifier)]
  signalcall(callback, widget, keyCode)
  callback = widget.boundKeyUpCombos[g_keyboard.determineKeyComboDescription(keyCode, keyboardModifiers)]
  return signalcall(callback, widget, keyCode)
end

local function onWidgetKeyPress(widget, keyCode, keyboardModifiers, autoRepeatTicks, keyText)
  if not keyText or string.empty(keyText) then
    keyText = KeyCodeDescs[keyCode]
  end

  if keyCode == KeyUnknown then return false end
  local callback = widget.boundKeyPressCombos[g_keyboard.determineKeyComboDescription(keyCode, keyboardModifiers, keyText)]
  return signalcall(callback, widget, keyCode, autoRepeatTicks, keyText)
end

local function connectKeyDownEvent(widget)
  if widget.boundKeyDownCombos then return end
  connect(widget, { onKeyDown = onWidgetKeyDown })
  widget.boundKeyDownCombos = {}
  widget.boundAloneKeyDownCombos = {}
end

local function connectKeyUpEvent(widget)
  if widget.boundKeyUpCombos then return end
  connect(widget, { onKeyUp = onWidgetKeyUp })
  widget.boundKeyUpCombos = {}
  widget.boundAloneKeyUpCombos = {}
end

local function connectKeyPressEvent(widget)
  if widget.boundKeyPressCombos then return end
  connect(widget, { onKeyPress = onWidgetKeyPress })
  widget.boundKeyPressCombos = {}
end

-- public functions
function g_keyboard.bindKeyDown(keyComboDesc, callback, widget, alone)
  if not keyComboDesc then
    return true
  end

  widget = widget or rootWidget
  connectKeyDownEvent(widget)
  local keyCombo = retranslateKeyComboDesc(keyComboDesc)

  -- hotfix for NumLock
  if keyComboDesc == "Num+NumLock" then
    keyCombo = keyComboDesc
  elseif keyComboDesc == "NumDel" then
    keyCombo = keyComboDesc
  end

  if alone then
    connect(widget.boundAloneKeyDownCombos, keyCombo, callback)
  else
    connect(widget.boundKeyDownCombos, keyCombo, callback)
  end
end

function g_keyboard.bindKeyUp(keyComboDesc, callback, widget, alone)
  if not keyComboDesc then
    return true
  end
  widget = widget or rootWidget
  connectKeyUpEvent(widget)
  local keyComboDesc = retranslateKeyComboDesc(keyComboDesc)
  if alone then
    connect(widget.boundAloneKeyUpCombos, keyComboDesc, callback)
  else
    connect(widget.boundKeyUpCombos, keyComboDesc, callback)
  end
end

function g_keyboard.bindKeyPress(keyComboDesc, callback, widget)
  if not keyComboDesc then
    return true
  end

  widget = widget or rootWidget
  connectKeyPressEvent(widget)
  local keyComboDesc = retranslateKeyComboDesc(keyComboDesc)
  connect(widget.boundKeyPressCombos, keyComboDesc, callback)
end

local function getUnbindArgs(arg1, arg2)
  local callback
  local widget
  if type(arg1) == 'function' then callback = arg1
  elseif type(arg2) == 'function' then callback = arg2 end
  if type(arg1) == 'userdata' then widget = arg1
  elseif type(arg2) == 'userdata' then widget = arg2 end
  widget = widget or rootWidget
  return callback, widget
end

function g_keyboard.unbindKeyDown(keyComboDesc, arg1, arg2, alone)
  if not keyComboDesc then
    return true
  end
  local callback, widget = getUnbindArgs(arg1, arg2)

  local keyComboDesc = retranslateKeyComboDesc(keyComboDesc)
  if alone then
    if widget.boundAloneKeyDownCombos == nil then
      return
    end
    disconnect(widget.boundAloneKeyDownCombos, keyComboDesc, callback)
  else
    if widget.boundKeyDownCombos == nil then
      return
    end

    disconnect(widget.boundKeyDownCombos, keyComboDesc, callback)
  end
end

function g_keyboard.unbindKeyUp(keyComboDesc, arg1, arg2, alone)
  if not keyComboDesc then
    return true
  end

  local callback, widget = getUnbindArgs(arg1, arg2)
  local keyComboDesc = retranslateKeyComboDesc(keyComboDesc)

  if alone then
    if widget.boundAloneKeyUpCombos == nil then
      return
    end
    disconnect(widget.boundAloneKeyUpCombos, keyComboDesc, callback)
  else
    if widget.boundKeyUpCombos == nil then
      return
    end
    disconnect(widget.boundKeyUpCombos, keyComboDesc, callback)
  end
end

function g_keyboard.unbindKeyPress(keyComboDesc, arg1, arg2, alone)
  if not keyComboDesc then
    return true
  end

  local callback, widget = getUnbindArgs(arg1, arg2)
  local keyComboDesc = retranslateKeyComboDesc(keyComboDesc)
  if alone then
    if widget.boundKeyPressCombos == nil then
      return
    end
    disconnect(widget.boundKeyPressCombos, keyComboDesc, callback)
  else
    if widget.boundKeyPressCombos == nil then
      return
    end
    disconnect(widget.boundKeyPressCombos, keyComboDesc, callback)
  end
end

function g_keyboard.getModifiers()
  return g_window.getKeyboardModifiers()
end

function g_keyboard.isKeyPressed(key)
  if type(key) == 'string' then
    key = getKeyCode(key)
  end
  return g_window.isKeyPressed(key)
end

function g_keyboard.areKeysPressed(keyComboDesc)
  for i,currentKeyDesc in ipairs(keyComboDesc:split('+')) do
    for keyCode, keyDesc in pairs(KeyCodeDescs) do
      if keyDesc:lower() == currentKeyDesc:trim():lower() then
        if keyDesc:lower() == "ctrl" then
          if not g_keyboard.isCtrlPressed() then
            return false
          end
        elseif keyDesc:lower() == "shift" then
          if not g_keyboard.isShiftPressed() then
            return false
          end
        elseif keyDesc:lower() == "alt" then
          if not g_keyboard.isAltPressed() then
            return false
          end
        elseif not g_window.isKeyPressed(keyCode) then
          return false
        end
      end
    end
  end
  return true
end

function g_keyboard.isKeySetPressed(keys, all)
  all = all or false
  local result = {}
  for k,v in pairs(keys) do
    if type(v) == 'string' then
      v = getKeyCode(v)
    end
    if g_window.isKeyPressed(v) then
      if not all then
        return true
      end
      table.insert(result, true)
    end
  end
  return #result == #keys
end

function g_keyboard.isInUse()
  for i = FirstKey, LastKey do
    if g_window.isKeyPressed(key) then
      return true
    end
  end
  return false
end

function g_keyboard.isCtrlPressed()
  return bit32.band(g_window.getKeyboardModifiers(), KeyboardCtrlModifier) ~= 0
end

function g_keyboard.isAltPressed()
  return bit32.band(g_window.getKeyboardModifiers(), KeyboardAltModifier) ~= 0
end

function g_keyboard.isShiftPressed()
  return bit32.band(g_window.getKeyboardModifiers(), KeyboardShiftModifier) ~= 0
end

----------------------------

-- Effective held-key walking delay (ms) from the keyboard-delay option: native => the
-- fixed 250ms default, otherwise the user slider. game_walking throttles its held-key
-- auto-repeat to one step per this, so a higher delay slows continuous walking (helps
-- very fast characters not send walk commands faster than the server can process).
function g_keyboard.getWalkRepeatDelay()
  local settings = modules.client_settings
  if not settings or not settings.getOption then return 0 end
  if settings.getOption('hotkeyDelayNative') then return 250 end
  return tonumber(settings.getOption('hotkeyDelay')) or 0
end

function g_keyboard.bindWalkKey(key, dir)
  -- "Dir" may come as a function which dynamically determines the direction and returns it. In that case, call the function to get the return.
  if type(dir) == "function" then
    dir = dir()
  end

  --Added player manual steering block.
  local function keyDownWalk()
    local localPlayer = g_game.getLocalPlayer()
    if (localPlayer ~= nil and localPlayer:isSteeringLocked()) or (KeybindManager.keybindsMuted == true) then
      return
    end
	  modules.game_playercontrols.changeWalkDir(dir)
  end

  local function keyUpWalk()
    local localPlayer = g_game.getLocalPlayer()
    if localPlayer ~= nil and localPlayer:isSteeringLocked() or (KeybindManager.keybindsMuted == true) then
      return
    end
	  modules.game_playercontrols.changeWalkDir(dir, true)
  end

  local function keyPressWalk()
    local localPlayer = g_game.getLocalPlayer()
    if localPlayer ~= nil and localPlayer:isSteeringLocked() or (KeybindManager.keybindsMuted == true) then
      return
    end
    modules.game_playercontrols.smartWalk(dir)
  end

  if dir == NorthEast or dir == SouthEast or dir == NorthWest or dir == SouthWest then
    g_ui.addDiagonalKey(getKeyCode(key))
  end

  g_keyboard.bindKeyDown(key, keyDownWalk, rootWidget:getChildById("gameRootPanel"), true)
  g_keyboard.bindKeyUp(key, keyUpWalk, rootWidget:getChildById("gameRootPanel"), true)
  g_keyboard.bindKeyPress(key, keyPressWalk, rootWidget:getChildById("gameRootPanel"))
end

function g_keyboard.unbindWalkKey(key)
  if g_ui.isDiagonalKey(getKeyCode(key)) then
    g_ui.removeDiagonalKey(getKeyCode(key))
  end
  g_keyboard.unbindKeyDown(key, rootWidget:getChildById("gameRootPanel"))
  g_keyboard.unbindKeyUp(key, rootWidget:getChildById("gameRootPanel"))
  g_keyboard.unbindKeyPress(key, rootWidget:getChildById("gameRootPanel"))
end