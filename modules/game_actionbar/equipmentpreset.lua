-- common variables
local presetWindow = nil
local selectIconWindow = nil
local radioIconGroup = nil
local currentButton = nil

PresetSlotStyles = {
  [InventorySlotHead] = "Slot1",
  [InventorySlotNeck] = "Slot2",
  [InventorySlotBack] = "Slot3",
  [InventorySlotBody] = "Slot4",
  [InventorySlotRight] = "Slot5",
  [InventorySlotLeft] = "Slot6",
  [InventorySlotLeg] = "Slot7",
  [InventorySlotFeet] = "Slot8",
  [InventorySlotFinger] = "Slot9",
  [InventorySlotAmmo] = "Slot10"
}

local presetDefaultStruct = {
	["equipSlot1"] = {itemId = 0, tier = 0, identifier = "", smartMode = false},
	["equipSlot2"] = {itemId = 0, tier = 0, identifier = "", smartMode = false},
	["equipSlot4"] = {itemId = 0, tier = 0, identifier = "", smartMode = false},
	["equipSlot5"] = {itemId = 0, tier = 0, identifier = "", smartMode = false},
	["equipSlot6"] = {itemId = 0, tier = 0, identifier = "", smartMode = false},
	["equipSlot7"] = {itemId = 0, tier = 0, identifier = "", smartMode = false},
	["equipSlot8"] = {itemId = 0, tier = 0, identifier = "", smartMode = false},
	["equipSlot9"] = {itemId = 0, tier = 0, identifier = "", smartMode = false},
	["equipSlot10"] = {itemId = 0, tier = 0, identifier = "", smartMode = false},
}

local PresetDisplayIcons = {
	"death",    "earth",
	"energy",   "fire", 
	"holy",     "ice", 
	"physical", "speed"
}

local DynamicItems = {
	[3086] = 3049, [3087] = 3050, [3088] = 3051, [3089] = 3052,
	[3090] = 3053, [3094] = 3091, [3095] = 3092, [3096] = 3093,
	[3099] = 3097, [3100] = 3098, [3549] = 6529, [6300] = 6299, 
	[9018] = 9019, [9392] = 9393, [16264] = 16114, [22134] = 22061,
	[23476] = 23477, [23530] = 23529, [23532] = 23531, [23534] = 23533,
	[23526] = 23542, [23527] = 23543, [23528] = 23544, [30343] = 30342,
	[30345] = 30344, [30402] = 30403, [31616] = 31557, [32635] = 32621,
	[39178] = 39177, [39181] = 39180, [39184] = 39183, [39187] = 39186, 
	[39234] = 39233, [50148] = 50147, [50151] = 50150, [50153] = 50152,
	[50155] = 50154, [23475] = 23474
}

local function getCurrentItemId(ItemPtr)
	if not ItemPtr then
		return 0
	end

	local inventoryItemId = ItemPtr:getId()
	if DynamicItems[inventoryItemId] then
		inventoryItemId = DynamicItems[inventoryItemId]
	end
	return inventoryItemId
end

function isPresetWindowVisible()
	if not presetWindow or not presetWindow:isVisible() then
		return false
	end
	return true
end

function closePresetWindow()
	if presetWindow then
		presetWindow:hide()
		presetWindow:destroy()
		presetWindow = nil
	end
end

function assignEquipment(button)
	if presetWindow then
		presetWindow:destroy()
	end

	presetWindow = g_ui.loadUI('equippreset', g_ui.getRootWidget())
	presetWindow:show()
	presetWindow:raise()

	scheduleEvent(function()
		presetWindow:focus()
	end, 50)

	currentButton = button

	local inventoryPanel = modules.game_inventory.getInventoryPanel()
	local backpackSlot = inventoryPanel:recursiveGetChildById("slot3")

	local presetBackpack = presetWindow.contentPanel:recursiveGetChildById("equipSlot3")
	local backpackId = backpackSlot:getItem() and backpackSlot:getItemId() or 0
	presetBackpack:setItemId(backpackId)
	presetBackpack:setStyle(backpackId > 0 and 'PresetEmptyItem' or PresetSlotStyles[3])

	for k, v in pairs(button.cache.equipmentPreset) do
		local widget = presetWindow:recursiveGetChildById(string.format(k))
		local slot = tonumber(string.match(k, "%d+"))
		widget:setItemId(v.itemId)
		widget:setTier(v.tier)
		if v.itemId > 0 then
			widget:getItem():setHash(v.identifier)
		end

		widget:setStyle(v.itemId > 0 and 'PresetEmptyItem' or PresetSlotStyles[slot])
	end

	local iconSource = presetWindow:recursiveGetChildById("imageContainer")
	local currentIcon = button.cache.equipmentPresetIcon
	if not string.empty(currentIcon) then
		iconSource:setImageSource("/images/game/actionbar/equip-preset/" .. currentIcon)
	end

	presetWindow.contentPanel.apply:setEnabled(not string.empty(currentIcon))
	presetWindow.contentPanel.missingIcon:setVisible(string.empty(currentIcon))

	presetWindow.contentPanel.apply.onClick = function()
		local iconSource = presetWindow:recursiveGetChildById("imageContainer")
		local filename = string.match(iconSource:getImageSource(), "([^/]+)$")
		
		local equippedCount = 0
		for _, slotId in pairs(EquipmentPresetSlots) do
			local widget = presetWindow:recursiveGetChildById(string.format("equipSlot%d", slotId))
			local item = widget and widget:getItem() or nil
			if widget then
				if not button.cache.equipmentPreset[widget:getId()] then
					button.cache.equipmentPreset[widget:getId()] = table.recursivecopy(presetDefaultStruct)
				end

				local itemId = item and item:getId() or 0
				local itemTier = item and item:getTier() or 0
				local itemHash = item and item:getItemHash() or ""

				button.cache.equipmentPreset[widget:getId()].itemId = itemId
				button.cache.equipmentPreset[widget:getId()].tier = itemTier
				button.cache.equipmentPreset[widget:getId()].identifier = itemHash

				if itemId > 0 then
					equippedCount = equippedCount + 1
				end
			end
		end

		if equippedCount == 0 then
			button.cache.equipmentPreset = {}
			presetWindow:hide()
			presetWindow:destroy()
			presetWindow = nil
			return true
		end

		local barID, buttonID = string.match(button:getId(), "(.*)%.(.*)")

		Options.createOrUpdatePreset(tonumber(barID), tonumber(buttonID), button.cache.equipmentPreset, filename)
		updateButton(button)

		-- Equipa automaticamente ao clicar Apply
		local preset = {}
		for i, data in pairs(button.cache.equipmentPreset) do
			local slotId = tonumber(string.match(i, "%d+"))
			if slotId and data.itemId and data.itemId > 0 then
				table.insert(preset, {slot = slotId, itemId = data.itemId, tier = data.tier, identifier = data.identifier, smartMode = data.smartMode})
			end
		end
		if #preset > 0 then
			g_game.sendEquipmentPreset(preset)
		end

		presetWindow:hide()
		presetWindow:destroy()
		presetWindow = nil
	end

	presetWindow.contentPanel.close.onClick = function()
		presetWindow:hide()
		presetWindow:destroy()
		presetWindow = nil
	end
end

function assignItemPreset(widget, mousePos, mouseButton)
	if mouseButton ~= MouseRightButton then
		return
	end

	local menu = g_ui.createWidget('PopupMenu')
	menu:setGameMenu(true)

	if widget:getItemId() == 0 then
		menu:addOption(tr('Select Item'), function() selectPresetItem(widget) end)
	else
		menu:addOption(tr('Edit Item'), function() selectPresetItem(widget) end)
		if table.contains(DynamicItems, widget:getItemId()) then
			menu:addCheckBoxOption(tr('Smart Mode'), function() onEditSmartMode(widget) end, nil, smartModeEnabled(widget))
		end

		menu:addOption(tr('Remove Item'), function() onRemovePresetItem(widget) end)
	end

	menu:display(mousePos)
end

function selectPresetItem(widget)
	local grabber = modules.game_actionbar.getGrabberWidget()
	g_mouse.updateGrabber(grabber, 'target')
	grabber:grabMouse()
	g_mouse.pushCursor('target')
	grabber.onMouseRelease = function(self, mousePosition, mouseButton) onSelectPresetItem(self, mousePosition, mouseButton, widget) end
end

function onSelectPresetItem(self, mousePosition, mouseButton, widget)
	local grabber = modules.game_actionbar.getGrabberWidget()
	local rootPanel = modules.game_actionbar.getRootPanel()

	g_mouse.updateGrabber(grabber, 'target')
	grabber:ungrabMouse()
	g_mouse.popCursor('target')
	grabber.onMouseRelease = modules.game_actionbar.onDropActionButton

	local clickedWidget = rootPanel:recursiveGetChildByPos(mousePosition, false)
    if not clickedWidget then
		return true
	end

	local item = nil
	if clickedWidget:getClassName() == 'UIItem' and not clickedWidget:isVirtual() and clickedWidget:getItem() then
		item = clickedWidget:getItem()
	elseif clickedWidget:getClassName() == 'UIGameMap' then
		local tile = clickedWidget:getTile(mousePosition)
		if tile then
			item = tile:getTopUseThing()
		end
	end

	if not item then
		return
	end

	if not item:isPickupable() then
		modules.game_textmessage.displayFailureMessage('This item can\'t be assigned to this slot.')
		return true
	end

	local slot = tonumber(string.match(widget:getId(), "%d+"))
	local canEquip, message = isValidEquipSlot(item, slot)
	if not canEquip then
		modules.game_textmessage.displayFailureMessage(message)
        return
    end

	local newItemId = getCurrentItemId(item)
	if newItemId == 0 then
		return
	end

    local newItem = Item.create(newItemId)
    newItem:setTier(item:getTier())
	newItem:setHash(item:getItemHash())
	widget:setStyle('PresetEmptyItem')
    widget:setItem(newItem)
end

function onDropPresetItem(widget, item)
    local slotId = tonumber(widget:getId():match("%d+"))
	 if not isValidEquipSlot(item, slotId) then
        return
    end

	local newItemId = getCurrentItemId(item)
	if newItemId == 0 then
		return
	end

    local newItem = Item.create(newItemId)
    newItem:setTier(item:getTier())
	newItem:setHash(item:getItemHash())
    widget:setStyle("PresetEmptyItem")
    widget:setItem(newItem)
end

function assignPlayerEquipments()
	if not presetWindow or not presetWindow:isVisible() then
		return
	end

	local inventoryPanel = modules.game_inventory.getInventoryPanel()
	if not inventoryPanel then
		return
	end

	for _, slotId in pairs(EquipmentPresetSlots) do
		local widget = presetWindow:recursiveGetChildById(string.format("equipSlot%d", slotId))
		local inventoryItem = inventoryPanel:recursiveGetChildById(string.format("slot%d", slotId))

		if not widget or not inventoryItem then
			goto continue
		end

		-- Items already in inventory slots are valid by definition, copy directly
		local item = inventoryItem:getItem()
		local inventoryItemId = getCurrentItemId(item)
		local inventoryTier = item and item:getTier() or 0
		local inventoryHash = item and item:getItemHash() or "0"

		widget:setItemId(inventoryItemId)
		widget:setTier(inventoryTier)
		widget:setHash(inventoryHash)
		widget:setStyle(inventoryItemId > 0 and 'PresetEmptyItem' or PresetSlotStyles[slotId])

		:: continue ::
	end
end

function onRemovePresetItem(widget)
	local slot = tonumber(string.match(widget:getId(), "%d+"))
	widget:setItem(nil)
	-- Force hide the tier icon since the item is now nil
	if ItemsDatabase and ItemsDatabase.setTier then
		ItemsDatabase.setTier(widget, nil)
	end
	widget:setStyle(PresetSlotStyles[slot])
end

function editPresetIcon(widget, mousePos, mouseButton)
	presetWindow:hide()

	selectIconWindow = g_ui.createWidget("SelectEquipPresetIcon", g_ui.getRootWidget())
	if not selectIconWindow then
		presetWindow:show()
		return
	end

	g_ui.setInputLockWidget(selectIconWindow)

	local iconList = selectIconWindow:recursiveGetChildById("selectEquipPresetPanel")
	radioIconGroup = UIRadioGroup.create()

	for _, widget in pairs(iconList:getChildren()) do
  		radioIconGroup:addWidget(widget)
	end

  	radioIconGroup.onSelectionChange = function(widget, currentWidget, prevWidget) 
		if prevWidget then
			prevWidget:recursiveGetChildById("selectedFrame"):setVisible(false)
		end

		currentWidget:recursiveGetChildById("selectedFrame"):setVisible(true)
		selectIconWindow:recursiveGetChildById("selectButton"):setEnabled(true)
	end
end

function onCloseSelectPresetIcon()
	if selectIconWindow then
		selectIconWindow:hide()
		selectIconWindow:destroy()
		radioIconGroup:destroy()
		selectIconWindow = nil
		radioIconGroup = nil

		g_ui.setInputLockWidget(nil)
	end
	presetWindow:show()
end

function onSelectPresetIcon()
	local selectedWidget = radioIconGroup:getSelectedWidget()
	if selectedWidget then
		presetWindow:recursiveGetChildById("imageContainer"):setImageSource(selectedWidget.imageContainer:getImageSource())
	end

	onCloseSelectPresetIcon()
	presetWindow.contentPanel.apply:setEnabled(true)
	presetWindow.contentPanel.missingIcon:setVisible(false)
end

function isValidEquipSlot(item, slotId)
	if not presetWindow or not presetWindow:isVisible() then
		return false
	end

    local cloth = item:getClothSlot()
    local isTwoHanded = cloth == 0 and item:getClassification() > 0

    if (slotId ~= cloth and not (isTwoHanded and slotId == 6)) or (cloth == 0 and not isTwoHanded) then
        return false, "You cannot dress this object there"
    end

    local itemType = g_things.getThingType(item:getId(), ThingCategoryItem)
    local marketData = itemType:getMarketData()

	if item:getId() == 28494 then
		marketData.category = MarketCategory.Shields
	end

    -- Slot 5 (right hand)
    if slotId == 5 then
        local leftWidget = presetWindow:recursiveGetChildById("equipSlot6")
        local leftItemId = leftWidget:getItemId()
        if leftItemId > 0 then
            local leftType = g_things.getThingType(leftItemId, ThingCategoryItem)
            local leftMarket = leftType:getMarketData()
            local leftIsTwoHanded = leftType:getClothSlot() == 0 and (
                leftMarket.category == MarketCategory.Shields or
                leftType:getClassification() > 0
            )
            if marketData.category == MarketCategory.Shields and leftIsTwoHanded then
                return false, "Both hands need to be free"
            end
        end
    end

    -- Slot 6 (left hand)
    if slotId == 6 then
        local rightWidget = presetWindow:recursiveGetChildById("equipSlot5")
        local rightItemId = rightWidget:getItemId()
        if rightItemId > 0 then
            local rightType = g_things.getThingType(rightItemId, ThingCategoryItem)
            local rightMarket = rightType:getMarketData()
            if rightMarket.category == MarketCategory.Shields and itemType:getClothSlot() == 0 then
                return false, "Both hands need to be free"
            end
        end
    end

	-- Amulet/Ring slot wearout check
	if (slotId == 2 or slotId == 9) and item:hasWearOut() and item:hasCharges() then
		return false, "Items with charges are not allowed"
	end

	local player = g_game.getLocalPlayer()
	local playerLevel = player:getLevel()
	local playerVocation = translateWheelVocation(player:getVocation())

	local itemVocation = marketData.restrictVocation
	if type(itemVocation) == "table" then
		if #itemVocation > 0 and not table.contains(itemVocation, playerVocation) then
			return false, "You don't have the required profession"
		end
	elseif type(itemVocation) == "number" then
		if itemVocation > 0 and itemVocation ~= playerVocation then
			return false, "You don't have the required profession"
		end
	end

	if marketData.requiredLevel > player:getLevel() then
		return false, "You do not have enough level"
	end
    return true
end

function offLineEvents()
	if selectIconWindow then
		selectIconWindow:hide()
		selectIconWindow:destroy()
		radioIconGroup:destroy()
		selectIconWindow = nil
		radioIconGroup = nil

		g_ui.setInputLockWidget(nil)
	end

	if presetWindow then
		presetWindow:hide()
		presetWindow:destroy()
		presetWindow = nil
	end

	currentButton = nil
end

function onEditSmartMode(widget)
	if not currentButton.cache.equipmentPreset[widget:getId()] then
		currentButton.cache.equipmentPreset[widget:getId()] = { itemId = 0, tier = 0, identifier = "", smartMode = true }
		return
	end

	local currentState = currentButton.cache.equipmentPreset[widget:getId()].smartMode
	currentButton.cache.equipmentPreset[widget:getId()].smartMode = not currentState
end

function smartModeEnabled(widget)
	if not currentButton.cache.equipmentPreset[widget:getId()] then
		return false
	end

	return currentButton.cache.equipmentPreset[widget:getId()].smartMode
end
