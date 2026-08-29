ActionHotkey = {}
ActionHotkey.__index = ActionHotkey

local actionPoolSize = 14
local actionLabelSize = 20

local actionKeyMin = 0
local actionKeyMax = 0

local maxFitLabels = 0

local actionKeys = {}
local searchList = {}

local lastFocusedID = ""
local lastFocusedHK = nil

function ActionHotkey.createCache()
    local actionbarHotkey = loadedWindows["actionsHotkeys"]
	if not actionbarHotkey then
		return false
	end

    actionKeys = {}
    local chatOn = actionbarHotkey:recursiveGetChildById("chatOnCheckBox"):isChecked()
    local profile = actionbarHotkey:recursiveGetChildById("profile"):getCurrentOption().text

    for barN = 1, 9 do
        for x = 1, 50 do
            local barDesc
            if barN < 4 then
                barDesc = "Bottom"
            elseif barN < 7 then
                barDesc = "Left"
            else
                barDesc = "Right"
            end

            local id = barN .. '.' .. x
            local totalText = barDesc .. " Action Bar: Action Button " .. id
            local hotkey = Options.getActionHotkey(id, profile, chatOn)
            local secondary = Options.getSecondaryActionHotkey(id, profile, chatOn)

            actionKeys[#actionKeys + 1] = {
                id = id,
                x = x,
                barDesc = barDesc,
                barN = barN,
                actionText = totalText,
                firstHotkey = hotkey and hotkey or "",
                secondHotkey = secondary and secondary or ""
            }
        end
    end

    local actionbarHotkey = loadedWindows["actionsHotkeys"]
	if not actionbarHotkey then
		return false
	end

	local panel = actionbarHotkey:recursiveGetChildById("hotkeyList")
    if panel:getChildCount() == 0 then
        for i = 1, actionPoolSize do
            local widget = g_ui.createWidget("HotkeysLabel", panel)
            widget:setBackgroundColor((i % 2 == 0 and '#281b17' or '#2c1e19'))
        end
    end
end

function ActionHotkey.onScrollValueChange(scroll, value, delta, panel, fromSearch)
    local startItem = math.max(actionKeyMin, value)
    local endItem = startItem + maxFitLabels - 1

    if endItem > actionKeyMax then
      endItem = actionKeyMax
      startItem = endItem - maxFitLabels + 1
    end

    for i, widget in pairs(panel:getChildren()) do
        local actionId = value > 0 and (startItem + i - 1) or (startItem + i)
        local cachedData = fromSearch and searchList[actionId] or actionKeys[actionId]
        if not cachedData then
            goto continue
        end

        widget.firstKey:setText(cachedData.firstHotkey)
        widget.secondKey:setText(cachedData.secondHotkey)
        widget:setId(actionId)
        widget:setBackgroundColor((actionId % 2 == 0 and '#281b17' or '#2c1e19'))
        widget.firstKey.actionEdit:setVisible(false)
        widget.secondKey.actionEdit:setVisible(false)
        widget.id = cachedData.id
        if lastFocusedID == widget:getId() then
            lastFocusedHK = widget
            lastFocusedHK.lastColor = widget:getBackgroundColor()
            widget:setBackgroundColor("#35241d")
            widget.firstKey.actionEdit:setVisible(true)
            widget.secondKey.actionEdit:setVisible(true)
            panel:focusChild(nil)
        end

        local t = {}
        setStringColor(t, cachedData.barDesc .. " Action Bar:", "#f7f7f7")
        setStringColor(t, " Action Button " .. cachedData.barN .. '.' .. (cachedData.x < 10 and '0' .. cachedData.x or cachedData.x), "$var-text-cip-color")
        widget.action:setColoredText(t)

        :: continue ::
    end
end

function ActionHotkey.onSearch(widget)
    if string.empty(widget:getText()) then
        ActionHotkey.configureActionBarHotkeys()
        return true
    end

    searchList = {}
    for _, key in pairs(actionKeys) do
        if matchText(widget:getText():lower(), key.actionText:lower()) or matchText(widget:getText():lower(), key.firstHotkey:lower()) then
            searchList[#searchList + 1] = key
        end
    end

    local actionbarHotkey = loadedWindows["actionsHotkeys"]
	if not actionbarHotkey then
		return false
	end

	local panel = actionbarHotkey:recursiveGetChildById("hotkeyList")
    for i, widget in pairs(panel:getChildren()) do
        local cachedData = searchList[i]
        if not cachedData then
            widget:setVisible(false)
            goto continue
        end

        widget:setVisible(true)
        widget.firstKey:setText(cachedData.firstHotkey)
        widget.secondKey:setText(cachedData.secondHotkey)
        widget:setId(i)
        widget:setBackgroundColor((i % 2 == 0 and '#281b17' or '#2c1e19'))
        widget.firstKey.actionEdit:setVisible(false)
        widget.secondKey.actionEdit:setVisible(false)

        if lastFocusedID == widget:getId() then
            lastFocusedHK = widget
            lastFocusedHK.lastColor = widget:getBackgroundColor()
            widget:setBackgroundColor("#35241d")
            widget.firstKey.actionEdit:setVisible(true)
            widget.secondKey.actionEdit:setVisible(true)
            panel:focusChild(nil)
        end

        local t = {}
        setStringColor(t, cachedData.barDesc .. " Action Bar:", "#f7f7f7")
        setStringColor(t, " Action Button " .. cachedData.barN .. '.' .. (cachedData.x < 10 and '0' .. cachedData.x or cachedData.x), "$var-text-cip-color")
        widget.action:setColoredText(t)

        :: continue ::
    end

    maxFitLabels = math.floor(panel:getHeight() / actionLabelSize)
    actionKeyMax = #searchList
    actionKeyMin = actionKeyMax > 0 and 1 or 0

    local scrollbar = actionbarHotkey:recursiveGetChildById("hotkeyListScrollBar")
    scrollbar:setMinimum(actionKeyMin)
    scrollbar:setMaximum(math.max(0, (actionKeyMax - actionPoolSize) + 1))
    scrollbar:setValue(actionKeyMin)
    scrollbar.onValueChange = function(self, value, delta) ActionHotkey.onScrollValueChange(self, value, delta, panel, true) end

    if lastFocusedHK then
        lastFocusedHK.firstKey.actionEdit:setVisible(false)
        lastFocusedHK.secondKey.actionEdit:setVisible(false)
        lastFocusedHK:setBackgroundColor(lastFocusedHK.lastColor)
        lastFocusedID = ""
        lastFocusedHK = nil
    end
end

function ActionHotkey.onHKFocusChange(widget)
    if not widget or not widget:isFocused() or not g_game.isOnline() then
        return
    end

    if lastFocusedHK then
        lastFocusedHK.firstKey.actionEdit:setVisible(false)
        lastFocusedHK.secondKey.actionEdit:setVisible(false)
        lastFocusedHK:setBackgroundColor(lastFocusedHK.lastColor)
    end

    lastFocusedID = widget:getId()
    lastFocusedHK = widget
    lastFocusedHK.lastColor = widget:getBackgroundColor()
    lastFocusedHK:setBackgroundColor("#35241d")
    lastFocusedHK.firstKey.actionEdit:setVisible(true)
    lastFocusedHK.secondKey.actionEdit:setVisible(true)
end

function ActionHotkey.configureActionBarHotkeys()
    ActionHotkey.createCache()
    local actionbarHotkey = loadedWindows["actionsHotkeys"]
	if not actionbarHotkey then
		return false
	end

	local panel = actionbarHotkey:recursiveGetChildById("hotkeyList")
    panel:focusChild(nil)
    panel.onChildFocusChange = function(self, selected, oldFocus) ActionHotkey.onHKFocusChange(selected, oldFocus) end
    for i, widget in pairs(panel:getChildren()) do
        local cachedData = actionKeys[i]
        widget.firstKey:setText(cachedData.firstHotkey)
        widget.secondKey:setText(cachedData.secondHotkey)
        widget:setVisible(true)

        widget:setId(i)
        local actionButtonId = cachedData.barN .. '.' .. (cachedData.x < 10 and '0' .. cachedData.x or cachedData.x)

        local t = {}
        setStringColor(t, cachedData.barDesc .. " Action Bar:", "#f7f7f7")
        setStringColor(t, " Action Button " .. actionButtonId, "$var-text-cip-color")
        widget.action:setColoredText(t)

        -- First Key
        widget.firstKey.actionEdit.onClick = function()
            if not lastFocusedHK or not lastFocusedHK.id then
                return true
            end

            if hotkeyAssignWindow then
                hotkeyAssignWindow:destroy()
            end

            optionsWindow:hide()
            g_client.setInputLockWidget(nil)
            local assignWindow = g_ui.createWidget('ActionAssignWindow', rootWidget)
            assignWindow:setText("Edit Hotkey for: \"" .. widget.action:getText() .. "\"")
            assignWindow:grabKeyboard()
            assignWindow.display:setText(widget.firstKey:getText())

            assignWindow.onKeyDown = function(assignWindow, keyCode, keyboardModifiers, keyText)
                local keyCombo = determineKeyComboDesc(keyCode, keyboardModifiers, keyText)
                local resetCombo = {"Shift", "Ctrl", "Alt"}
                if table.contains(resetCombo, keyCombo) then
                    assignWindow.display:setText('')
                    assignWindow.warning:setVisible(false)
                    assignWindow.buttonOk:setEnabled(true)
                    return true
                end

                local shortCut = (keyCombo == "HalfQuote" and "'" or keyCombo)
                assignWindow.display:setText(shortCut)
                assignWindow.display.combo = keyCombo
                assignWindow.warning:setVisible(false)
                assignWindow.buttonOk:setEnabled(true)
                if KeyBinds:hotkeyIsUsed(keyCombo) or modules.game_actionbar.isHotkeyUsed(keyCombo) then
                    assignWindow.warning:setVisible(true)
                    assignWindow.warning:setText("This hotkey is already in use and will be overwritten.")
                end

                if table.contains(blockedKeys, keyCombo) then
                    assignWindow.warning:setVisible(true)
                    assignWindow.warning:setText("This hotkey is already in use and cannot be overwritten.")
                    assignWindow.buttonOk:setEnabled(false)
                end
                return true
            end

            local chatOn = actionbarHotkey:recursiveGetChildById("chatOnCheckBox"):isChecked()
            assignWindow.chatMode:setText(chatOn and "Mode: \"Chat On\"" or "Mode: \"Chat Off\"")

            assignWindow:insertLuaCall("onDestroy")
            assignWindow.onDestroy = function(widget)
                if widget == hotkeyAssignWindow then
                    hotkeyAssignWindow = nil
                end
            end

            assignWindow.buttonOk.onClick = function()
                if not lastFocusedHK or not lastFocusedHK.id then
                    return true
                end

                local text = assignWindow.display.combo
                if text and #text == 0 then
                    Options.removeHotkey(lastFocusedHK.id)
                    g_keyboard.unbindKeyPress(text, nil, m_interface.getRootPanel())
                    widget.firstKey:setText('')
                    assignWindow:destroy()
                    optionsWindow:show(true)
                    g_client.setInputLockWidget(optionsWindow)
                    return true
                end

                removeGeneralUsedHotkey(text, widget, chatOn)
                ActionHotkey.removeUsedHotkey(text, widget, chatOn)
                KeyBinds:removeHotkey(text)
                modules.game_actionbar.removeHotkey(text)   

                CustomHotkeys.checkAndRemoveUsedHotkey(text, chatOn)
                widget.firstKey:setText(assignWindow.display:getText())
                Options.updateActionMenuHotkey(chatOn, "TriggerActionButton_".. lastFocusedHK.id, text)
                assignWindow:destroy()
                optionsWindow:show(true)
                g_client.setInputLockWidget(optionsWindow)
                ActionHotkey.createCache()
            end

            assignWindow.buttonClear.onClick = function()
                if not lastFocusedHK or not lastFocusedHK.id then
                    return true
                end

                ActionHotkey.removeUsedHotkey(lastFocusedHK.firstKey:getText(), nil, chatOn)
                assignWindow:destroy()
                optionsWindow:show(true)
                g_client.setInputLockWidget(optionsWindow)
            end

            hotkeyAssignWindow = assignWindow
        end

        -- Second Key
        widget.secondKey.actionEdit.onClick = function()
            if not lastFocusedHK or not lastFocusedHK.id then
                return true
            end

            if hotkeyAssignWindow then
                hotkeyAssignWindow:destroy()
            end

            optionsWindow:hide()
            g_client.setInputLockWidget(nil)
            local assignWindow = g_ui.createWidget('ActionAssignWindow', rootWidget)
            assignWindow:setText("Edit Hotkey for: \"" .. widget.action:getText() .. "\"")
            assignWindow:grabKeyboard()
            assignWindow.display:setText(cachedData.secondHotkey)

            assignWindow.onKeyDown = function(assignWindow, keyCode, keyboardModifiers, keyText)
                local keyCombo = determineKeyComboDesc(keyCode, keyboardModifiers, keyText)
                local resetCombo = {"Shift", "Ctrl", "Alt"}
                if table.contains(resetCombo, keyCombo) then
                    assignWindow.display:setText('')
                    assignWindow.warning:setVisible(false)
                    assignWindow.buttonOk:setEnabled(true)
                    return true
                end

                local shortCut = (keyCombo == "HalfQuote" and "'" or keyCombo)
                assignWindow.display:setText(shortCut)
                assignWindow.display.combo = keyCombo
                assignWindow.warning:setVisible(false)
                assignWindow.buttonOk:setEnabled(true)
                if KeyBinds:hotkeyIsUsed(keyCombo) or modules.game_actionbar.isHotkeyUsed(keyCombo) then
                    assignWindow.warning:setVisible(true)
                    assignWindow.warning:setText("This hotkey is already in use and will be overwritten.")
                end

                if table.contains(blockedKeys, keyCombo) then
                    assignWindow.warning:setVisible(true)
                    assignWindow.warning:setText("This hotkey is already in use and cannot be overwritten.")
                    assignWindow.buttonOk:setEnabled(false)
                end

                if keyCombo == cachedData.firstHotkey then
                    assignWindow.warning:setVisible(true)
                    assignWindow.warning:setText("This hotkey is already in use and cannot be overwritten.")
                    assignWindow.buttonOk:setEnabled(false)
                end
                return true
            end

            local chatOn = actionbarHotkey:recursiveGetChildById("chatOnCheckBox"):isChecked()
            assignWindow.chatMode:setText(chatOn and "Mode: \"Chat On\"" or "Mode: \"Chat Off\"")

            assignWindow:insertLuaCall("onDestroy")
            assignWindow.onDestroy = function(widget)
                if widget == hotkeyAssignWindow then
                    hotkeyAssignWindow = nil
                end
            end

            assignWindow.buttonOk.onClick = function()
                if not lastFocusedHK or not lastFocusedHK.id then
                    return true
                end

                local text = assignWindow.display.combo
                if text and #text == 0 then
                    Options.removeSecondHotkey(lastFocusedHK.id)
                    g_keyboard.unbindKeyPress(text, nil, m_interface.getRootPanel())
                    widget.secondKey:setText('')
                    assignWindow:destroy()
                    optionsWindow:show(true)
                    g_client.setInputLockWidget(optionsWindow)
                    return true
                end

                removeGeneralUsedHotkey(text, widget, chatOn)
                ActionHotkey.removeUsedHotkey(text, widget, chatOn)    
                KeyBinds:removeHotkey(text)

                CustomHotkeys.checkAndRemoveUsedHotkey(text, chatOn, true)
                widget.secondKey:setText(assignWindow.display:getText())
                Options.updateActionMenuHotkey(chatOn, "TriggerActionButton_".. lastFocusedHK.id, text, true)
                assignWindow:destroy()
                optionsWindow:show(true)
                g_client.setInputLockWidget(optionsWindow)
                ActionHotkey.createCache()
            end

            assignWindow.buttonClear.onClick = function()
                if not lastFocusedHK or not lastFocusedHK.id then
                    return true
                end

                Options.removeSecondHotkey(lastFocusedHK.id)
                local hk = lastFocusedHK.secondKey:getText()
                widget.secondKey:setText("")
                g_keyboard.unbindKeyPress(hk, nil, m_interface.getRootPanel())
                g_keyboard.unbindKeyDown(hk, nil, m_interface.getRootPanel())
                assignWindow:destroy()
                optionsWindow:show(true)
                g_client.setInputLockWidget(optionsWindow)
            end

            hotkeyAssignWindow = assignWindow
        end
    end

    maxFitLabels = math.floor(panel:getHeight() / actionLabelSize)
    actionKeyMax = #actionKeys
    actionKeyMin = actionKeyMax > 0 and 1 or 0

    local scrollbar = actionbarHotkey:recursiveGetChildById("hotkeyListScrollBar")
    scrollbar:setMinimum(actionKeyMin)
    scrollbar:setMaximum(math.max(0, (actionKeyMax - actionPoolSize) + 1))
    scrollbar:setValue(actionKeyMin)
    scrollbar.onValueChange = function(self, value, delta) ActionHotkey.onScrollValueChange(self, value, delta, panel, false) end

    if lastFocusedHK then
        lastFocusedHK.firstKey.actionEdit:setVisible(false)
        lastFocusedHK.secondKey.actionEdit:setVisible(false)
        lastFocusedHK:setBackgroundColor(lastFocusedHK.lastColor)
        lastFocusedID = ""
        lastFocusedHK = nil
    end
end

function ActionHotkey.checkAndRemoveSecondary(text)
    for _, key in pairs(actionKeys) do
        if key.secondHotkey:lower() == text:lower() then
            g_keyboard.unbindKeyPress(key.secondHotkey, nil, m_interface.getRootPanel())
            g_keyboard.unbindKeyDown(key.secondHotkey, nil, m_interface.getRootPanel())
            Options.updateActionMenuHotkey(chatOn, "TriggerActionButton_".. key.id, "", true)
            break
        end
    end
end

function ActionHotkey.removeUsedHotkey(key, currentButton, chatOn)
    local window = loadedWindows["actionsHotkeys"]
  
    local panel = window:recursiveGetChildById("hotkeyList")
    for _, widget in pairs(panel:getChildren()) do
      if (widget == currentButton) then goto continue end
  
      local isFirstKey = key == widget.firstKey:getText()
      local isSecondKey = key == widget.secondKey:getText()
      if isFirstKey or isSecondKey then
        local hotkey = KeyBind:getKeyBindByHotkey(key)
        widget[isFirstKey and "firstKey" or "secondKey"]:setText("")
  
        if hotkey then
          hotkey[isFirstKey and 'setFirstKey' or 'setSecondKey']('')
          Options.removeActionHotkey(chatOn and "chatOn" or "chatOff", hotkey.jsonName, isSecondKey)
        end
      end
  
      :: continue ::
    end
  
    for _,actionKey in pairs(actionKeys) do
      if actionKey.firstHotkey == key or actionKey.secondHotkey == key then
        Options.removeHotkey(actionKey.id)
      end

      if actionKey.secondHotkey == key then
        Options.removeSecondHotkey(actionKey.id)
      end
    end
  end
