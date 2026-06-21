CustomHotkeys = {}
CustomHotkeys.__index = CustomHotkeys

-- Common vars
local assignCache = nil
local UseColors = {
    ["UseOnYourself"] = {color = "#b0ffb0", text = "(use object on yourself)"},
    ["UseOnTarget"] = {color = "#ffb0b0", text = "(use object on target)"},
    ["SelectUseTarget"] = {color = "#c87d7d", text = "use object with crosshair"},
    ["Equip"] = {color = "#bfbf00", text = "(equip/unequip object)"},
    ["Use"] = {color = "#b0b0ff", text = "(use object)"},
    ["SmartCast"] = {color = "#e788fb", text = "(use object on cursor position)"},
}

function CustomHotkeys.createList(save)
    if save == nil then
        save = false
    end

    local currentWindow = loadedWindows["customHotkeys"]
    local hotkeyList = currentWindow:recursiveGetChildById("hotkeyList")

    -- unbind old list
    for _, child in pairs(hotkeyList:getChildren()) do
      if child.hotkey and #child.hotkey > 0 then
        g_keyboard.unbindKeyPress(child.hotkey, nil)
        g_keyboard.unbindKeyDown(child.hotkey, nil)
      end
      child:destroy()
    end

    local chatType = currentWindow:recursiveGetChildById('chatOnCheckBox'):isChecked() and "chatOn" or "chatOff"
    if save then
        chatType = Options.isChatOnEnabled and "chatOn" or "chatOff"
    end

    local profile = currentWindow:recursiveGetChildById("profile")
    local customList = Options.getCustomHotkeys(chatType, profile:getCurrentOption().text)
    if not currentWindow:isVisible() then
      customList = Options.getCustomHotkeys(chatType, Options.currentHotkeySetName)
    end

    hotkeyList:destroyChildren()
    for i, k in pairs(customList) do
      local widget = g_ui.createWidget("CustomHotkeyFlat", hotkeyList)

      -- cache things
      widget.isSpell = false
      widget.isItem = k["actionsetting"]["useObject"] ~= nil
      widget.isText = false
      widget.hotkey = k["keysequence"]
      widget.secondaryHotkey = k["secondarySequence"] or ""

      local chatText = k["actionsetting"]["chatText"]
      if chatText then
        local spellData, param = Spells.getSpellDataByParamWords(chatText:lower())
        if spellData then
          widget.isSpell = true
        else
          widget.isText = true
        end
      end

      -- configure action button
      widget.actionEdit.onClick = function()
        local menu = g_ui.createWidget('PopupMenu')
        g_client.setInputLockWidget(nil)
        menu:setGameMenu(true)
        menu:addOption(widget.isSpell and tr('Edit Spell') or tr('Assign Spell'), function() CustomHotkeys.assignSpell(widget) end)
        if widget.item:getItemId() > 100 then
            menu:addOption(tr('Edit Object'), function() CustomHotkeys.assignItem(widget, widget.item:getItemId()) end)
        else
            menu:addOption(tr('Assign Object'), function() CustomHotkeys.assignItemEvent(widget) end)
        end
        menu:addOption(widget.isText and tr('Edit Text') or tr('Assign Text'), function() CustomHotkeys.assignText(widget) end)
        menu:addSeparator()
        menu:addOption(tr('Clear Action'), function() clearCustomHotkey(widget) end)
        menu:display(mousePos)
      end

      -- configure primary button
      widget.primaryEdit.onClick = function() CustomHotkeys.onAssignHotkey(widget) end

      -- configure secondary button
      widget.secondaryEdit.onClick = function() CustomHotkeys.onAssignHotkey(widget, true) end

      if widget.isItem then
        local actionData = UseColors[k["actionsetting"]["useType"]]
        widget.item:setItemId(k["actionsetting"]["useObject"])
        widget.item:setVisible(true)
        widget.action:setText(actionData.text)
        widget.action:setColor(actionData.color)
        if #widget.hotkey > 0 then
          widget.primary:setText(widget.hotkey)
          widget.primary:setColor(actionData.color)
        end

        widget.upgradeTier = k["actionsetting"]["upgradeTier"]
        widget.smartMode = k["actionsetting"]["useEquipSmartMode"]
        widget.actionType = k["actionsetting"]["useType"]
      else
        widget.action:setText(chatText)
        widget.action:setMarginLeft(-15)
        widget.words = chatText
        widget.sendAutomatic = k["actionsetting"]["sendAutomatically"]
        if #widget.hotkey > 0 then
          widget.primary:setText(widget.hotkey)
        end

        if widget.secondaryHotkey and #widget.secondaryHotkey > 0 then
          widget.secondary:setText(widget.secondaryHotkey)
        end
      end

      local background = i % 2 == 0 and "#484848" or "#414141"
      widget:setBackgroundColor(background)
      widget.background = background

      if #widget.hotkey > 0 then
        g_keyboard.bindKeyPress(widget.hotkey, function() onExecuteAction(widget) end, gameRootPanel)
        g_keyboard.bindKeyDown(widget.hotkey, function() onExecuteAction(widget) end, gameRootPanel)
      end

      if widget.secondaryHotkey and #widget.secondaryHotkey > 0 then
        g_keyboard.bindKeyPress(widget.secondaryHotkey, function() onExecuteAction(widget) end, gameRootPanel)
        g_keyboard.bindKeyDown(widget.secondaryHotkey, function() onExecuteAction(widget) end, gameRootPanel)
      end
    end

    local first = hotkeyList:getFirstChild()
    if first then
      first:focus()
    end

    hotkeyList.onChildFocusChange = CustomHotkeys.onCustomHotkeyFocus
    hotkeyList:orderChildrenByText("primary")
end

-- Spells
function CustomHotkeys.assignSpell(button)
	local radio = UIRadioGroup.create()
  window = g_ui.createWidget('SpellMainWindow', rootWidget)
	window:show(true)
	window:raise()
	window:focus()
  optionsWindow:hide()
  g_client.setInputLockWidget(nil)
  g_client.setInputLockWidget(window)

	window:setText("Assign Spell")

	local spells = modules.gamelib.SpellInfo['Default']
  local player = g_game.getLocalPlayer()
	for spellName, spellData in pairs(spells) do
    if not player then
      break
    end

		if not table.contains(spellData.vocations, translateVocation(player:getVocation())) then
			goto continue
		end

		local widget = g_ui.createWidget('SpellPreview', window.contentPanel.spellList)
    local spellId = SpellIcons[spellData.icon][1]
		-- radio
		radio:addWidget(widget)
		widget:setId(spellData.id)
		widget:setText(spellName.."\n"..spellData.words)
		widget.voc = spellData.vocations
    widget.param = spellData.parameter
		widget.source = SpelllistSettings['Default'].iconsFolder
		widget.clip = Spells.getImageClipNormal(spellId, 'Default')
		widget.image:setImageSource(widget.source)
		widget.image:setImageClip(widget.clip)
    
    if spellData.level then
      widget.levelLabel:setVisible(true)
      widget.levelLabel:setText(string.format("Level: %d", spellData.level))
      if player:getLevel() < spellData.level then
        widget.image.gray:setVisible(true)
      end
    end

    local primaryGroup = Spells.getPrimaryGroup(spellData)
    if primaryGroup ~= -1 then
      local offSet = 1
      if primaryGroup == 2 then
        offSet = (23 * (primaryGroup - 1))
      elseif primaryGroup == 3 then
        offSet = (23 * (primaryGroup - 1)) - 1
      end
      widget.imageGroup:setImageClip(offSet .. " 25 20 20")
      widget.imageGroup:setVisible(true)
    end
		:: continue ::
	end

	-- sort alphabetically
	local widgets = window.contentPanel.spellList:getChildren()
	table.sort(widgets, function(a, b) return a:getText() < b:getText() end)
	for i, widget in ipairs(widgets) do
		window.contentPanel.spellList:moveChildToIndex(widget, i)
	end

	-- callback
	radio.onSelectionChange = function(widget, selected)
		if selected then
			window.contentPanel.preview:setText(selected:getText())
			window.contentPanel.preview.image:setImageSource(selected.source)
			window.contentPanel.preview.image:setImageClip(selected.clip)
			window.contentPanel.paramLabel:setOn(selected.param)
			window.contentPanel.paramText:setEnabled(selected.param)
			window.contentPanel.paramText:clearText()
			if selected:getText():lower():find("levitate") then
				window.contentPanel.paramText:setText("up|down")
			end
			window.contentPanel.spellList:ensureChildVisible(widget)
		end
	end

	if window.contentPanel.spellList:getChildren() then
		radio:selectWidget(window.contentPanel.spellList:getChildren()[1])
	end

	local okFunc = function(destroy)
		local selected = radio:getSelectedWidget()
		if not selected then return end

		local chatOn = selectedWindow:recursiveGetChildById("chatOnCheckBox"):isChecked()
		local param = string.match(selected:getText(), "\n(.*)")
    local paramText = window.contentPanel.paramText:getText()

		local check = (param .. " " .. paramText)
		if string.find(check, "utevo res ina") then
			param = "utevo res ina"
			paramText = string.gsub(paramText, "ina ", "")
		end

    if paramText:lower():find("up|down") then
			window.contentPanel.paramText:setText("")
		end
    if not string.empty(paramText) then
      param = param .. ' "' .. paramText:gsub('"', '') .. '"'
    end

    local oldText = (button and button.action:getText() or "")
    local hotkey = (button and button.hotkey or "")
    if assignCache ~= nil then
        if button then
          Options.removeCustomHotkey(button, chatOn)
        end

        Options.createOrUpdateCustomText(param, assignCache.action:getText(), true, hotkey, chatOn)
        CustomHotkeys.assignSpellButton(assignCache, param)
    elseif button ~= nil then
        Options.removeCustomHotkey(button, chatOn)
        Options.createOrUpdateCustomText(param, button.action:getText(), true, hotkey, chatOn)
        CustomHotkeys.assignSpellButton(button, param)
    else
        Options.createOrUpdateCustomText(param, oldText, true, hotkey, chatOn)
        assignCache = CustomHotkeys.assignSpellButton(nil, param)
    end

    if destroy then
        assignCache = nil
        window:destroy()
        optionsWindow:show(true)
        g_client.setInputLockWidget(optionsWindow)
        end
    end

	local cancelFunc = function()
    assignCache = nil
		window:destroy()
    optionsWindow:show(true)
    g_client.setInputLockWidget(optionsWindow)
	end

	window.contentPanel.buttonOk.onClick = function() okFunc(true) end
	window.contentPanel.buttonApply.onClick = function() okFunc(false) end
	window.contentPanel.buttonClose.onClick = cancelFunc
	window.contentPanel.onEnter = function() okFunc(true) end
	window.onEscape = cancelFunc
end

function CustomHotkeys.assignSpellButton(button, param)
  local customList = loadedWindows["customHotkeys"]:recursiveGetChildById("hotkeyList")
  local widget = (button ~= nil and button or g_ui.createWidget("CustomHotkeyFlat", customList))

  widget.isSpell = true
  widget.isItem = false
  widget.isText = false

  widget.action:setText(param)
  widget.words = param
  widget.action:setMarginLeft(-15)
  widget.item:setItem(nil)
  widget.item:setVisible(false)
  widget.action:setColor("#dfdfdf")

  widget.actionEdit.onClick = function()
    local menu = g_ui.createWidget('PopupMenu')
    g_client.setInputLockWidget(nil)
    menu:setGameMenu(true)
    menu:addOption(widget.isSpell and tr('Edit Spell') or tr('Assign Spell'), function() CustomHotkeys.assignSpell(widget) end)
    if widget.item:getItemId() > 100 then
      menu:addOption(tr('Edit Object'), function() CustomHotkeys.assignItem(widget, widget.item:getItemId()) end)
    else
      menu:addOption(tr('Assign Object'), function() CustomHotkeys.assignItemEvent(widget) end)
    end
    menu:addOption(widget.isText and tr('Edit Text') or tr('Assign Text'), function() CustomHotkeys.assignText(widget) end)
    menu:addSeparator()
    menu:addOption(tr('Clear Action'), function() clearCustomHotkey(widget) end)
    menu:display(g_window.getMousePosition())
  end

  -- configure primary button
  widget.primaryEdit.onClick = function() CustomHotkeys.onAssignHotkey(widget) end

  -- configure secondary button
  widget.secondaryEdit.onClick = function() CustomHotkeys.onAssignHotkey(widget, true) end

  local background = customList:getChildCount() % 2 == 0 and "#484848" or "#414141"
  widget:setBackgroundColor(background)
  widget.background = background
  return widget
end

-- Items
function CustomHotkeys.assignItemEvent(button)
	optionsWindow:hide()
  g_client.setInputLockWidget(nil)
  g_mouse.updateGrabber(mouseGrabberSetting, 'target')
	mouseGrabberSetting:grabMouse()
	g_mouse.pushCursor('target')
	mouseGrabberSetting.onMouseRelease = function(self, mousePosition, mouseButton) CustomHotkeys.onAssignItem(self, mousePosition, mouseButton, button) end
end

function CustomHotkeys.onAssignItem(self, mousePosition, mouseButton, button)
  g_mouse.updateGrabber(mouseGrabberSetting, 'target')
	mouseGrabberSetting:ungrabMouse()
	g_mouse.popCursor('target')
	mouseGrabberSetting.onMouseRelease = onChooseItemMouseRelease

  local gameRootPanel = m_interface.getRootPanel()
	local clickedWidget = gameRootPanel:recursiveGetChildByPos(mousePosition, false)
    if not clickedWidget then
      optionsWindow:show(true)
      g_client.setInputLockWidget(optionsWindow)
		return true
	end

	local itemId = 0
	local itemTier = 0
	if clickedWidget:getClassName() == 'UIItem' and not clickedWidget:isVirtual() and clickedWidget:getItem() then
		itemId = clickedWidget:getItem():getId()
		itemTier = clickedWidget:getItem():getTier()
	elseif clickedWidget:getClassName() == 'UIGameMap' then
		local tile = clickedWidget:getTile(mousePosition)
		if tile then
			itemId = tile:getTopUseThing():getId()
		end
	end

	local itemType = g_things.getThingType(itemId)
	if not itemType or not itemType:isPickupable() then
		modules.game_textmessage.displayFailureMessage(tr('Invalid object!'))
    optionsWindow:show(true)
    g_client.setInputLockWidget(optionsWindow)
		return true
	end

	CustomHotkeys.assignItem(button, itemId, itemTier)
end

function CustomHotkeys.assignItem(button, itemId, itemTier)
	local radio = UIRadioGroup.create()
	local item = nil
  if window then
      window:destroy()
  end

  window = g_ui.createWidget('CustomObjectWindow', rootWidget)
	window:show(true)
	window:raise()
	window:focus()

	window:setText("Assign Object")
	window.contentPanel.select.onClick = function()
    window:destroy()
    CustomHotkeys.assignItemEvent(button)
	end

  optionsWindow:hide()
  g_client.setInputLockWidget(window)

	local fromSelect = false
	if button and button.item:getItemId() > 0 and button.item:getItemId() ~= itemId then
		fromSelect = true
	end

	window.contentPanel.item:setItemId(itemId)
	if not item then
		item = window.contentPanel.item:getItem()
	end

	if window.contentPanel.item:getItem() then
		window.contentPanel.item:getItem():setTier(itemTier)
	end

	-- ativar smart object (se tem cloth e se tem wearout)
	window.contentPanel.checks.smart:setVisible(false)
	if (item:getClothSlot() > 0 and (item:hasExpireStop() or modules.game_actionbar.getSmartCast(item:getId()))) then
		window.contentPanel.checks.smart:setVisible(true)
		if button and button.smartMode and button.smartMode == true then
			window.contentPanel.checks.smart:setChecked(true)
		end
	end

	for i, child in ipairs(window.contentPanel.checks:getChildren()) do
		if i == 6 then
			goto continue
		end

		radio:addWidget(child)
		child:setEnabled(false)

		if i <= 4 and item:isMultiUse() then
			child:setEnabled(true)
      if not radio:getSelectedWidget() then
			  radio:selectWidget(child)
      end
		end

		if i == 5 and canAssignEquipItem(item) then
			child:setEnabled(true)
      if not radio:getSelectedWidget() then
			  radio:selectWidget(child)
      end
		end

		if i == 7 and item:isUsable() and not item:isMultiUse() then
      child:setEnabled(true)
      if not radio:getSelectedWidget() then
          radio:selectWidget(child)
      end
		end

		child.onCheckChange = function(self)
			if self:getId() == "Equip" and not window.contentPanel.checks.smart:isEnabled() then
				window.contentPanel.checks.smart:setEnabled(true)
			elseif self:getId() ~= "Equip" and window.contentPanel.checks.smart:isEnabled() then
				window.contentPanel.checks.smart:setChecked(false)
				window.contentPanel.checks.smart:setEnabled(false)
			end
		end
		:: continue ::
	end

  if button then
    local child = radio:getWidgetById(button.actionType)
    if child and child:isEnabled() then
      radio:selectWidget(child)
    end
  end

	window.contentPanel.buttonOk:setEnabled(item and item:getId() > 100)
	window.contentPanel.buttonApply:setEnabled(item and item:getId() > 100)

	itemTier = not itemTier and button.upgradeTier or itemTier
	window.contentPanel.tier:setVisible(itemTier and itemTier > 0 or false)
	if itemTier and itemTier > 1 then
		window.contentPanel.tier:setImageClip(18 * (itemTier - 1) .. " 0 18 16")
	end

	local okFunc = function(destroy)
		local selected = radio:getSelectedWidget()
    if not selected then
      return
    end
    
    selected = selected:getId()
    local chatOn = selectedWindow:recursiveGetChildById("chatOnCheckBox"):isChecked()

		if item:getClassification() == 0 then
			itemTier = nil
		end

		local smartMode = nil
		if window.contentPanel.checks.smart:isVisible() then
			smartMode = window.contentPanel.checks.smart:isChecked()
		end

    if button then
      Options.removeCustomHotkey(button, chatOn)
    end

    if assignCache ~= nil then
      Options.createOrUpdateCustomAction(itemId, assignCache.item:getItemId(), selected, itemTier, smartMode, "", chatOn)
      CustomHotkeys.assignItemButton(assignCache, itemId, itemTier, smartMode, selected)
    elseif button and button.item then
      Options.createOrUpdateCustomAction(itemId, button.item:getItemId(), selected, itemTier, smartMode, "", chatOn)
      CustomHotkeys.assignItemButton(button, itemId, itemTier, smartMode, selected)
    else
      local oldItemId = (button and button.item and button.item:getItemId() or 0)
      Options.createOrUpdateCustomAction(itemId, oldItemId, selected, itemTier, smartMode, "", chatOn)
      assignCache = CustomHotkeys.assignItemButton(nil, itemId, itemTier, smartMode, selected)
    end

		if destroy then
      assignCache = nil
			window:destroy()
			radio:destroy()
      optionsWindow:show(true)
      g_client.setInputLockWidget(optionsWindow)
		end
	end

	local cancelFunc = function()
    assignCache = nil
		window:destroy()
		radio:destroy()
    optionsWindow:show(true)
    g_client.setInputLockWidget(optionsWindow)
	end

	window.contentPanel.buttonOk.onClick = function() okFunc(true) end
	window.contentPanel.onEnter = function() okFunc(true) end
	window.contentPanel.buttonApply.onClick = function() okFunc(false) end
	window.contentPanel.buttonClose.onClick = function() cancelFunc() end
	window.onEscape = function() cancelFunc() end
end

function CustomHotkeys.assignItemButton(button, itemId, itemTier, smartMode, useType)
    local customList = loadedWindows["customHotkeys"]:recursiveGetChildById("hotkeyList")
    local widget = (button ~= nil and button or g_ui.createWidget("CustomHotkeyFlat", customList))

    widget.isSpell = false
    widget.isItem = true
    widget.isText = false

    local actionData = UseColors[useType]
    widget.item:setItemId(itemId)
    widget.item:setVisible(true)
    widget.action:setText(actionData.text)
    widget.action:setColor(actionData.color)
    widget.upgradeTier = itemTier
    widget.smartMode = smartMode
    widget.actionType = useType
    widget.action:setMarginLeft(3)

    widget.actionEdit.onClick = function()
      local menu = g_ui.createWidget('PopupMenu')
      g_client.setInputLockWidget(nil)
      menu:setGameMenu(true)
      menu:addOption(widget.isSpell and tr('Edit Spell') or tr('Assign Spell'), function() CustomHotkeys.assignSpell(widget) end)
      if widget.item:getItemId() > 100 then
        menu:addOption(tr('Edit Object'), function() CustomHotkeys.assignItem(widget, widget.item:getItemId()) end)
      else
        menu:addOption(tr('Assign Object'), function() CustomHotkeys.assignItemEvent(widget) end)
      end
      menu:addOption(widget.isText and tr('Edit Text') or tr('Assign Text'), function() CustomHotkeys.assignText(widget) end)
      menu:addSeparator()
      menu:addOption(tr('Clear Action'), function() clearCustomHotkey(widget) end)
      menu:display(g_window.getMousePosition())
    end

    -- configure primary button
    widget.primaryEdit.onClick = function() CustomHotkeys.onAssignHotkey(widget) end

    -- configure secondary button
    widget.secondaryEdit.onClick = function() CustomHotkeys.onAssignHotkey(widget, true) end

    local background = customList:getChildCount() % 2 == 0 and "#484848" or "#414141"
    widget:setBackgroundColor(background)
    widget.background = background
    return widget
end

-- Text
function CustomHotkeys.assignText(button)
    window = g_ui.createWidget('CustomTextWindow', rootWidget)
    window:show(true)
    window:raise()
    window:focus()
    optionsWindow:hide()
    g_client.setInputLockWidget(nil)
    g_client.setInputLockWidget(window)

    window:setText("Assign Text")
    window.contentPanel.buttonOk:setEnabled(false)
    window.contentPanel.buttonApply:setEnabled(false)
    window.contentPanel.text.onTextChange = function(self, text)
        window.contentPanel.buttonOk:setEnabled(text:len() > 0)
        window.contentPanel.buttonApply:setEnabled(text:len() > 0)
    end

    local currentText = (button and button.action:getText() or "")
    if button and button.isItem then
      currentText = ""
    end

    window.contentPanel.checkPanel.tick:setChecked(true)
    window.contentPanel.text:setText(currentText)
    window.contentPanel.text:setCursorPos(#currentText)
  
    if #window.contentPanel.text:getText() > 0 then
        window.contentPanel.checkPanel.tick:setChecked(true)
    end

    local okFunc = function(destroy)
        local autoSay = window.contentPanel.checkPanel.tick:isChecked()
        local text = window.contentPanel.text:getText()
        local fomartedText = Spells.getSpellFormatedName(text)
        local chatOn = selectedWindow:recursiveGetChildById("chatOnCheckBox"):isChecked()
        local oldText = (button and button.action:getText() or "")
        local hotkey = (button and button.hotkey or "")

        if assignCache ~= nil then
            if button then
              Options.removeCustomHotkey(button, chatOn)
            end

            CustomHotkeys.assignTextButton(assignCache, fomartedText, autoSay)
            Options.createOrUpdateCustomText(fomartedText, oldText, autoSay, hotkey, chatOn)
        elseif button and #button.action:getText() > 0 then
            Options.removeCustomHotkey(button, chatOn)
            CustomHotkeys.assignTextButton(button, fomartedText, autoSay)
            Options.createOrUpdateCustomText(fomartedText, oldText, autoSay, hotkey, chatOn)
        else
            Options.createOrUpdateCustomText(fomartedText, oldText, autoSay, hotkey, chatOn)
            assignCache = CustomHotkeys.assignTextButton(button, fomartedText, autoSay)
        end

        if destroy then
            assignCache = nil
            window:destroy()
            optionsWindow:show(true)
            g_client.setInputLockWidget(optionsWindow)
        end
    end

    local cancelFunc = function()
        assignCache = nil
        window:destroy()
        optionsWindow:show(true)
        g_client.setInputLockWidget(optionsWindow)
    end

    window.contentPanel.buttonOk.onClick = function() okFunc(true) end
    window.contentPanel.buttonApply.onClick = function() okFunc(false) end
    window.contentPanel.buttonClose.onClick = cancelFunc
    window.onEscape = cancelFunc
    window.onEnter = function() okFunc(true) end
end

function CustomHotkeys.assignTextButton(button, text, autoSay)
    local customList = loadedWindows["customHotkeys"]:recursiveGetChildById("hotkeyList")
    local widget = (button ~= nil and button or g_ui.createWidget("CustomHotkeyFlat", customList))

    widget.isSpell = false
    widget.isItem = false
    widget.isText = false
    widget.words = text
    widget.action:setText(text)
    widget.action:setMarginLeft(-15)
    widget.item:setItem(nil)
    widget.item:setVisible(false)
    widget.action:setColor("#dfdfdf")

    if text then
      local spellData, param = Spells.getSpellDataByParamWords(text:lower())
      widget.isSpell = spellData
      widget.isText = not spellData
    end

    widget.actionEdit.onClick = function()
      local menu = g_ui.createWidget('PopupMenu')
      g_client.setInputLockWidget(nil)
      menu:setGameMenu(true)
      menu:addOption(widget.isSpell and tr('Edit Spell') or tr('Assign Spell'), function() CustomHotkeys.assignSpell(widget) end)
      if widget.item:getItemId() > 100 then
        menu:addOption(tr('Edit Object'), function() CustomHotkeys.assignItem(widget, widget.item:getItemId()) end)
      else
        menu:addOption(tr('Assign Object'), function() CustomHotkeys.assignItemEvent(widget) end)
      end
      menu:addOption(widget.isText and tr('Edit Text') or tr('Assign Text'), function() CustomHotkeys.assignText(widget) end)
      menu:addSeparator()
      menu:addOption(tr('Clear Action'), function() clearCustomHotkey(widget) end)
      menu:display(g_window.getMousePosition())
    end

    widget.primaryEdit.onClick = function() CustomHotkeys.onAssignHotkey(widget) end
    widget.secondaryEdit.onClick = function() CustomHotkeys.onAssignHotkey(widget, true) end

    local background = customList:getChildCount() % 2 == 0 and "#484848" or "#414141"
    widget:setBackgroundColor(background)
    widget.background = background
    return widget
end

-- Things
function CustomHotkeys.onCustomHotkeyFocus(list, focused, unfocus, trem)
    if unfocus then
        unfocus:setBackgroundColor(unfocus.background)
        local actionEdit = unfocus:recursiveGetChildById("actionEdit")
        if actionEdit then
            actionEdit:setVisible(false)
        end

        local primaryEdit = unfocus:recursiveGetChildById("primaryEdit")
        if primaryEdit then
            primaryEdit:setVisible(false)
        end
    end

    if focused then
        focused:recursiveGetChildById("actionEdit"):setVisible(true)
        focused:recursiveGetChildById("primaryEdit"):setVisible(true)
    end
end

function CustomHotkeys.onAssignHotkey(widget, secondaryHotkey)
    if hotkeyAssignWindow then
        hotkeyAssignWindow:destroy()
    end

    optionsWindow:hide()
    g_client.setInputLockWidget(nil)
    local assignWindow = g_ui.createWidget('ActionAssignWindow', rootWidget)
    assignWindow:setText("Edit Hotkey for: \"" .. widget.action:getText() .. "\"")
    assignWindow:grabKeyboard()
    assignWindow.display:setText(secondaryHotkey and widget.secondaryHotkey or widget.hotkey)
    g_client.setInputLockWidget(assignWindow)

    assignWindow.onKeyDown = function(assignWindow, keyCode, keyboardModifiers, keyText)
      local keyCombo = determineKeyComboDesc(keyCode, keyboardModifiers, keyText)
      local resetCombo = {"Shift", "Ctrl", "Alt"}
      if table.contains(resetCombo, keyCombo) then
        assignWindow.display:setText('')
        assignWindow.warning:setVisible(false)
        assignWindow.buttonOk:setEnabled(true)
        return true
      end

      assignWindow.display:setText(keyCombo)
      assignWindow.warning:setVisible(false)
      assignWindow.buttonOk:setEnabled(true)
      if KeyBinds:hotkeyIsUsed(keyCombo) or modules.game_actionbar.isHotkeyUsed(keyCombo, false) or modules.game_actionbar.isHotkeyUsed(keyCombo, true) then
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

    local chatOn = selectedWindow:recursiveGetChildById("chatOnCheckBox"):isChecked()
    assignWindow.chatMode:setText(chatOn and "Mode: \"Chat On\"" or "Mode: \"Chat Off\"")

    assignWindow.onDestroy = function(widget)
      if widget == hotkeyAssignWindow then
        hotkeyAssignWindow = nil
      end
    end

    assignWindow.buttonOk.onClick = function()
      local text = tostring(assignWindow.display:getText())
      if #text == 0 then
        CustomHotkeys.checkAndRemoveUsedHotkey(secondaryHotkey and widget.secondaryHotkey or widget.hotkey, chatOn)
        widget.primary:setText('')
        assignWindow:destroy()
        g_client.setInputLockWidget(nil)
        optionsWindow:show(true)
        g_client.setInputLockWidget(optionsWindow)
      end

      if KeyBinds:hotkeyIsUsed(text) and text ~= '' then
        local key = KeyBind:getKeyBindByHotkey(text)
        if key then
          g_keyboard.unbindKeyPress(key.firstKey, nil)
          Options.removeActionHotkey(chatOn and "chatOn" or "chatOff", key.jsonName)
        end
      end

      if text ~= '' then
        local key = KeyBind:getKeyBindBySecondHotkey(text)
        if key then
          g_keyboard.unbindKeyPress(key.secondKey, nil)
          Options.removeActionHotkey(chatOn and "chatOn" or "chatOff", key.jsonName)
        end
      end

      if modules.game_actionbar.isHotkeyUsed(text, false) then
        local usedButton = modules.game_actionbar.getUsedHotkeyButton(text)
        if usedButton then
          Options.removeHotkey(usedButton:getId())
          g_keyboard.unbindKeyPress(text, nil, m_interface.getRootPanel())
          g_keyboard.unbindKeyDown(text, nil, m_interface.getRootPanel())
          modules.game_actionbar.updateButton(usedButton)
        end
      end

      if modules.game_actionbar.isHotkeyUsed(text, true) then
        ActionHotkey.checkAndRemoveSecondary(text)
      end

      CustomHotkeys.checkAndRemoveUsedHotkey(text, chatOn)
      Options.updateCustomHotkey(widget, text, chatOn, secondaryHotkey)
      CustomHotkeys.updateWidget(widget, text, secondaryHotkey)
      g_client.setInputLockWidget(nil)
      assignWindow:destroy()
      optionsWindow:show(true)
      g_client.setInputLockWidget(optionsWindow)
    end

    assignWindow.buttonClear.onClick = function()
      g_keyboard.unbindKeyPress(text, nil, m_interface.getRootPanel())
      g_keyboard.unbindKeyDown(text, nil, m_interface.getRootPanel())
      Options.updateCustomHotkey(widget, '', chatOn, secondaryHotkey)
      CustomHotkeys.updateWidget(widget, '', secondaryHotkey)
      g_client.setInputLockWidget(nil)
      assignWindow:destroy()
      optionsWindow:show(true)
      g_client.setInputLockWidget(optionsWindow)
    end

    hotkeyAssignWindow = assignWindow
end

function CustomHotkeys.updateWidget(widget, text, isSecondary)
  local currentHotkey = isSecondary and widget.secondaryHotkey or widget.hotkey
  if currentHotkey and #currentHotkey > 0 then
    g_keyboard.unbindKeyPress(currentHotkey, nil, m_interface.getRootPanel())
    g_keyboard.unbindKeyDown(currentHotkey, nil, m_interface.getRootPanel())
  end

  if isSecondary then
    widget.secondaryHotkey = text
    widget.secondary:setText(text)
  else
    widget.hotkey = text
    widget.primary:setText(text)
  end

  if text ~= '' then
    g_keyboard.bindKeyPress(text, function() onExecuteAction(widget) end, m_interface.getRootPanel())
    g_keyboard.bindKeyDown(text, function() onExecuteAction(widget) end, m_interface.getRootPanel())
  end

  widget:getParent():orderChildrenByText("primary")
end

function CustomHotkeys.newActionFunc(widget, mousePosition, mouseButton)
    EditActionWidget = widget
    local topParent = EditActionWidget:getParent():getParent():getId()
    local menu = g_ui.createWidget('PopupMenu')
    g_client.setInputLockWidget(nil)
    menu:setGameMenu(true)
    menu:addOption(tr('Assign Spell'), function() CustomHotkeys.assignSpell() end)
    menu:addOption(tr('Assign Object'), function() CustomHotkeys.assignItemEvent() end)
    menu:addOption(tr('Assign Text'), function() CustomHotkeys.assignText() end)
    menu:display(mousePosition)
    return true
end

function CustomHotkeys.checkAndRemoveUsedHotkey(text, chatOn, secondary)
    local currentWindow = loadedWindows["customHotkeys"]
    if not currentWindow then
      return
    end

    for _, child in pairs(currentWindow:recursiveGetChildById("hotkeyList"):getChildren()) do
        if child.hotkey ~= '' and child.hotkey == text then
          Options.updateCustomHotkey(child, '', chatOn)
          CustomHotkeys.updateWidget(child, '')
          g_keyboard.unbindKeyPress(text, nil)
          g_keyboard.unbindKeyDown(text, nil)
          return
        end

        if child.secondaryHotkey ~= '' and child.secondaryHotkey == text then
          Options.updateCustomHotkey(child, '', chatOn, secondary)
          CustomHotkeys.updateWidget(child, '', secondary)
          g_keyboard.unbindKeyPress(text, nil)
          g_keyboard.unbindKeyDown(text, nil)
          return
        end
    end
    return
end

function CustomHotkeys.onSearchTextChange(text)
  local spellList = window:recursiveGetChildById('spellList')
  for _, child in pairs(spellList:getChildren()) do
      local name = child:getText():lower()
      if name:find(text:lower()) or text == '' or #text < 3 then
          child:setVisible(true)
      else
          child:setVisible(false)
      end
  end
end

function CustomHotkeys.onClearSearchText()
  local search = window:recursiveGetChildById('searchText')
  search:setText('')
end
