local actionBars = {}
local activeActionBars = {}

local activeWindow = nil

local mouseGrabberWidget = nil
local gameRootPanel = nil
local player = nil
local lastHighlightWidget = nil
local isLoaded = false
local loadActionBarEvent = nil

-- new
local hotkeyItemList = {}
local passiveData = { cooldown = 0, max = 0}
local spellModification = {}
local spellListData = {}

local spellCooldownCache = {}
local spellGroupCooldownCache = {}
local spellGroupPressed = {}

local MULTI_ACTION_DELAY_MS = 500

local cachedItemWidget = {}
local dragButton = nil
local dragItem = nil

local ItemTypeCategory = {
	Weapon = 3,
	Ammunition = 4,
	Armor = 5,
	Charges = 6
}

local function hasAstraItemState()
	return g_game.isAstraItemStateEnabled and g_game.isAstraItemStateEnabled()
end

local function hasPackedInventorySnapshot()
	return hasAstraItemState() and g_game.getFeature and g_game.getFeature(GamePackedPlayerInventory)
end

local function getActionItemCount(itemId, upgradeTier)
	if not player then
		return 0
	end

	return player:getInventoryCount(itemId, upgradeTier or 0)
end

local function hasActionItemAvailable(itemId, upgradeTier)
	if not player then
		return false
	end

	if not hasPackedInventorySnapshot() then
		return true
	end

	return player:getInventoryCount(itemId, upgradeTier or 0) > 0
end

local function hasActionItemEquipped(itemId, upgradeTier)
	return player and player:hasEquippedItemId(itemId, upgradeTier or 0)
end

local function getEquippedActionItem(itemId, upgradeTier)
	if not player or not itemId or itemId == 0 then
		return nil
	end

	upgradeTier = upgradeTier or 0
	for slot = InventorySlotFirst, InventorySlotLast do
		local item = player:getInventoryItem(slot)
		if item and item:getId() == itemId and (item:getTier() or 0) == upgradeTier then
			return item
		end
	end

	return nil
end

local function updateActionButtonItem(button, itemId, upgradeTier)
	if not button or not button.item then
		return
	end

	local equippedItem = getEquippedActionItem(itemId, upgradeTier)
	if equippedItem then
		button.item:setItem(equippedItem:clone())
		return
	end

	button.item:setItemId(itemId or 0, true)
	if button.item:getItem() then
		button.item:getItem():setTier(upgradeTier or 0)
	end
end

function updateGameMapPanelMargin()
	local gameMapPanel = nil
	if m_interface then
		gameMapPanel = m_interface.getMapPanel and m_interface.getMapPanel() or m_interface.gameMapPanel
	end

	if gameMapPanel and gameMapPanel:getMarginBottom() ~= 0 then
		gameMapPanel:setMarginBottom(0)
	end

	if modules.game_textmessage and modules.game_textmessage.updateActionBarMessageMargin then
		modules.game_textmessage.updateActionBarMessageMargin(7)
	end
end

local function refreshActionButtonRarity(button)
	if not button or not button.item or not ItemsDatabase or not ItemsDatabase.setRarityItem then
		return
	end

	local item = button.item:getItem()
	local hasRarityFrame = item and ItemsDatabase.getRarityFrame and ItemsDatabase.getRarityFrame(item)
	ItemsDatabase.setRarityItem(button.item, hasRarityFrame and item or nil)
end

function getGrabberWidget()
	return mouseGrabberWidget
end

function getRootPanel()
	return gameRootPanel
end

function getButtonCache(button)
	if not button then
		return {
			cooldownEvent = nil,
			cooldownTime = 0,
			isSpell = false,
			isRuneSpell = false,
			isPassive = false,
			spellID = 0,
			spellData = nil,
			param = "",
			sendAutomatic = false,
			actionType = 0,
			upgradeTier = 0,
			smartMode = nil,
			hotkey = nil,
			lastClick = 0,
			nextDownKey = 0,
			isDragging = false,
			buttonIndex = 0,
			buttonParent = nil,
			itemId = 0,
			equipmentPreset = {},
			equipmentPresetIcon = "",
			multiActions = {{}, {}, {}},
			multiSlotIndex = 0
		}
	end

	if not button.cache then
		button.cache = {
			cooldownEvent = nil,
			cooldownTime = 0,
			isSpell = false,
			isRuneSpell = false,
			isPassive = false,
			spellID = 0,
			spellData = nil,
			param = "",
			sendAutomatic = false,
			actionType = 0,
			upgradeTier = 0,
			smartMode = nil,
			hotkey = nil,
			lastClick = 0,
			nextDownKey = 0,
			isDragging = false,
			buttonIndex = 0,
			buttonParent = nil,
			itemId = 0,
			equipmentPreset = {},
			equipmentPresetIcon = "",
			multiActions = {{}, {}, {}},
			multiSlotIndex = 0
		}
	end

	return button.cache
end

function getSmartCast(itemId)
	if smartList[itemId] then return smartList[itemId] end

	for inactiveId, activeId in pairs(smartList) do
		if itemId == activeId then
			return inactiveId
		end
	end
end

function getInactiveSmartCast(activeItemId)
	for inactiveId, activeId in pairs(smartList) do
		if activeItemId == activeId then
			return inactiveId
		end
	end
end

function getActiveSmartCast(inactiveItemId)
	return smartList[inactiveItemId]
end

local function getActionbarItemMarketData(item)
	if not item or not item:getId() or item:getId() == 0 then
		return nil
	end

	if item.getMarketData then
		local ok, marketData = pcall(function() return item:getMarketData() end)
		if ok and marketData then
			return marketData
		end
	end

	if g_things and g_things.getThingType then
		local thingType = g_things.getThingType(item:getId(), ThingCategoryItem)
		if thingType and thingType.getMarketData then
			local ok, marketData = pcall(function() return thingType:getMarketData() end)
			if ok then
				return marketData
			end
		end
	end

	return nil
end

local function getActionbarItemCategory(item)
	local marketData = getActionbarItemMarketData(item)
	return marketData and marketData.category or 0
end

local function getActionbarItemName(item)
	if item and item.getName then
		local ok, name = pcall(function() return item:getName() end)
		if ok and name and name ~= "" then
			return name:lower()
		end
	end

	local marketData = getActionbarItemMarketData(item)
	if marketData and marketData.name and marketData.name ~= "" then
		return marketData.name:lower()
	end

	if getItemServerName and item and item:getId() and item:getId() > 0 then
		local ok, name = pcall(function() return getItemServerName(item:getId()) end)
		if ok and name then
			return name:lower()
		end
	end

	return ""
end

local function isActionbarEquipCategory(category)
	if not MarketCategory then
		return false
	end

	return category == MarketCategory.Armors or
		category == MarketCategory.Amulets or
		category == MarketCategory.Boots or
		category == MarketCategory.HelmetsHats or
		category == MarketCategory.Legs or
		category == MarketCategory.Rings or
		category == MarketCategory.Shields or
		category == MarketCategory.Ammunition or
		category == MarketCategory.Axes or
		category == MarketCategory.Clubs or
		category == MarketCategory.DistanceWeapons or
		category == MarketCategory.Swords or
		category == MarketCategory.WandsRods or
		category == MarketCategory.Quivers or
		category == MarketCategory.FistWeapons or
		category == MarketCategory.WeaponsAll or
		category == MarketCategory.MetaWeapons
end

local function isActionbarEquipName(item)
	local name = getActionbarItemName(item)
	return name:find("ring", 1, true) ~= nil or
		name:find("amulet", 1, true) ~= nil or
		name:find("necklace", 1, true) ~= nil
end

local function isActionbarFoodName(item)
	local name = getActionbarItemName(item)
	return name:find("mushroom", 1, true) ~= nil or
		name:find("food", 1, true) ~= nil or
		name:find("meat", 1, true) ~= nil or
		name:find("ham", 1, true) ~= nil or
		name:find("fish", 1, true) ~= nil or
		name:find("bread", 1, true) ~= nil or
		name:find("cheese", 1, true) ~= nil or
		name:find("egg", 1, true) ~= nil or
		name:find("fruit", 1, true) ~= nil or
		name:find("apple", 1, true) ~= nil or
		name:find("banana", 1, true) ~= nil or
		name:find("orange", 1, true) ~= nil or
		name:find("lemon", 1, true) ~= nil or
		name:find("berry", 1, true) ~= nil or
		name:find("blueberry", 1, true) ~= nil or
		name:find("grape", 1, true) ~= nil or
		name:find("coconut", 1, true) ~= nil or
		name:find("mango", 1, true) ~= nil or
		name:find("pear", 1, true) ~= nil or
		name:find("plum", 1, true) ~= nil or
		name:find("melon", 1, true) ~= nil or
		name:find("pumpkin", 1, true) ~= nil or
		name:find("potato", 1, true) ~= nil or
		name:find("tomato", 1, true) ~= nil or
		name:find("carrot", 1, true) ~= nil or
		name:find("corn", 1, true) ~= nil or
		name:find("rice", 1, true) ~= nil or
		name:find("seed", 1, true) ~= nil or
		name:find("walnut", 1, true) ~= nil or
		name:find("shrimp", 1, true) ~= nil or
		name:find("lobster", 1, true) ~= nil or
		name:find("salmon", 1, true) ~= nil or
		name:find("tuna", 1, true) ~= nil or
		name:find("rotworm", 1, true) ~= nil or
		name:find("rabbit", 1, true) ~= nil or
		name:find("deer", 1, true) ~= nil or
		name:find("wolf paw", 1, true) ~= nil or
		name:find("bear paw", 1, true) ~= nil or
		name:find("dragon ham", 1, true) ~= nil or
		name:find("jungle moss", 1, true) ~= nil or
		name:find("cake", 1, true) ~= nil or
		name:find("cookie", 1, true) ~= nil
end

local function canUseActionbarItem(item)
	if not item then
		return false
	end

	local category = getActionbarItemCategory(item)
	local isFood = MarketCategory and category == MarketCategory.Food
	return (item:isUsable() and not item:isMultiUse()) or item:isContainer() or isFood or isActionbarFoodName(item) or not canEquipItem(item)
end

local UseTypes = {
	["UseOnYourself"] = 1,
	["UseOnTarget"] = 2,
	["SmartCast"] = 3,
	["SelectUseTarget"] = 4,
	["Equip"] = 5,
	["Use"] = 6,

	-- Custom
	["chatText"] = 7,
	["passiveAbility"] = 8,
	["equipmentPreset"] = 9
}

local UseTypesTip = {
	[1] = "Use %s on Yourself",
	[2] = "Use %s on Attack Target",
	[3] = "Smart press %s",
	[4] = "Use %s with Crosshair",
	[5] = "%s %s",
	[6] = "Use %s",
}

function init()
	g_ui.importStyle('multiaction.otui')
	connect(LocalPlayer, {
		onManaChange 		= onUpdateActionBarStatus,
		onSoulChange 		= onUpdateActionBarStatus,
		onLevelChange 		= onUpdateLevel,
		onSpellsChange 		= onSpellsChange,
		onMonkPassiveChange = onUpdateActionBarStatus,
	})

	connect(g_game, {
		onGameEnd 				  = offline,
		onItemInfo                = onHotkeyItems,
		onGameStart 		      = online,
		onPassiveData             = onPassiveData,
		onSpellCooldown 		  = onSpellCooldown,
		onMultiUseCooldown        = onMultiUseCooldown,
		onSpellModification       = onSpellModification,
		onReleaseActionKeys       = onReleaseActionKeys,
		onSpellGroupCooldown 	  = onSpellGroupCooldown,
		updateInventoryItems      = updateInventoryItems,
		onEquipmentPresetCooldown = onEquipmentPresetCooldown
	})

	if g_game.isOnline() then
		online()
	end

	onCreateActionBars()

	gameRootPanel = m_interface.getRootPanel()
	mouseGrabberWidget = g_ui.createWidget('UIWidget')
	mouseGrabberWidget:setVisible(false)
	mouseGrabberWidget:setFocusable(false)
	mouseGrabberWidget.onMouseRelease = onDropActionButton
end

local function removeButtonEvents(button)
	if not button or not button.cache then
		return
	end

	if button.cache.hotkey then
		g_keyboard.unbindKeyPress(button.cache.hotkey, nil, gameRootPanel)
		g_keyboard.unbindKeyDown(button.cache.hotkey, nil, gameRootPanel)
		g_keyboard.unbindKeyUp(button.cache.hotkey, nil, gameRootPanel)
	end

	if button.cache.cooldownEvent then
		removeEvent(button.cache.cooldownEvent)
		button.cache.cooldownEvent = nil
	end

	if button.cache.removeCooldownEvent then
		removeEvent(button.cache.removeCooldownEvent)
		button.cache.removeCooldownEvent = nil
	end
end

local function clearMultiActionCooldownEvents()
	if not multiActionCooldownEvents then
		return
	end

	for _, events in pairs(multiActionCooldownEvents) do
		for _, event in pairs(events) do
			removeEvent(event)
		end
	end

	multiActionCooldownEvents = {}
end

function terminate()
	disconnect(LocalPlayer, {
		onManaChange 		= onUpdateActionBarStatus,
		onSoulChange 		= onUpdateActionBarStatus,
		onLevelChange 		= onUpdateLevel,
		onSpellsChange 		= onSpellsChange,
		onMonkPassiveChange = onUpdateActionBarStatus,
	})

	disconnect(g_game, {
		onGameEnd 				  = offline,
		onItemInfo                = onHotkeyItems,
		onGameStart 		      = online,
		onPassiveData             = onPassiveData,
		onSpellCooldown 		  = onSpellCooldown,
		onMultiUseCooldown        = onMultiUseCooldown,
		onSpellModification       = onSpellModification,
		onReleaseActionKeys       = onReleaseActionKeys,
		onSpellGroupCooldown 	  = onSpellGroupCooldown,
		updateInventoryItems      = updateInventoryItems,
		onEquipmentPresetCooldown = onEquipmentPresetCooldown
	})

	removeEvent(loadActionBarEvent)
	loadActionBarEvent = nil

	if closeCurrentMultiActionPanel then
		closeCurrentMultiActionPanel()
	end
	clearMultiActionCooldownEvents()

	for _, actionbar in pairs(actionBars) do
		if actionbar then
			unbindActionBarEvent(actionbar)
			if not actionbar:isDestroyed() then
				actionbar:destroy()
			end
		end
	end

	actionBars = {}
	activeActionBars = {}
	cachedItemWidget = {}
	hotkeyItemList = {}
	spellCooldownCache = {}
	spellGroupCooldownCache = {}
	spellGroupPressed = {}
	cacheMultiActionButtons = {}
	dragButton = nil
	dragItem = nil
	player = nil
	isLoaded = false

	if window then
		window:destroy()
		window = nil
	end

	if activeWindow then
		activeWindow:destroy()
		activeWindow = nil
	end

	if mouseGrabberWidget then
		if g_ui.isMouseGrabbed and g_ui.isMouseGrabbed() then
			mouseGrabberWidget:ungrabMouse()
		end
		mouseGrabberWidget:destroy()
		mouseGrabberWidget = nil
	end

	gameRootPanel = nil
end

function online()
	local benchmark = g_clock.millis()
	dragItem = nil
	dragButton = nil
	cachedItemWidget = {}
	player = g_game.getLocalPlayer()
	hotkeyItemList = {}
	spellGroupPressed = {}

	modules.game_console.setChatState(Options.isChatOnEnabled)

	for i = 1, #actionBars do
		setupActionBar(i)
	end

	-- schedule update items
	removeEvent(loadActionBarEvent)
	loadActionBarEvent = scheduleEvent(function()
		loadActionBarEvent = nil
		updateActionBar()
		onUpdateActionBarStatus()
		updateActionPassive()
		updateVisibleWidgets()
		isLoaded = true
	end, 300)
	consoleln("ActionBars loaded in " .. (g_clock.millis() - benchmark) / 1000 .. " seconds.")
end

function offline()
	for _, actionbar in pairs(activeActionBars) do
		unbindActionBarEvent(actionbar)
	end

	removeEvent(loadActionBarEvent)
	loadActionBarEvent = nil
	clearMultiActionCooldownEvents()
	if closeCurrentMultiActionPanel then
		closeCurrentMultiActionPanel()
	end

	hotkeyItemList = {}

	if window then
		window:destroy()
		window = nil
	end

	if activeWindow then
		activeWindow:destroy()
		activeWindow = nil
	end

	offLineEvents()
end

function onCreateActionBars()
	local gameMapPanel = m_interface.gameMapPanel
	if not gameMapPanel then
		return true
	end

	if #actionBars == 0 then
		createActionBars()
	end
	for i = 1, #actionBars do
		local actionbar = actionBars[i]
		local enabled = Options.actionBar[i].isVisible

		actionbar:setOn(enabled)
		setupActionBar(i)
		if not enabled then
			goto continue
		end

		table.insert(activeActionBars, actionbar)

		:: continue ::
	end

	resizeLockButtons()
	updateGameMapPanelMargin()
end

function createActionBars()
	local bottomPanel = m_interface.getBottomActionPanel()
	local leftPanel = m_interface.getLeftActionPanel()
	local rightPanel = m_interface.getRightActionPanel()

	-- 1-3: bottom
	-- 4-6: left
	-- 7-9: right
	for i = 1, 9 do
		local parent, index, layout, isVertical
		if i <= 3 then
			parent = bottomPanel
			index = i
			layout = 'actionbar'
			isVertical = false
		elseif i <= 6 then
			parent = leftPanel
			index = i - 3
			layout = 'sideactionbar'
			isVertical = true
		else
			parent = rightPanel
			index = i - 6
			layout = 'sideactionbar'
			isVertical = true
		end

		actionBars[i] = g_ui.loadUI(layout, parent)
		actionBars[i]:setId("actionbar."..i)
		actionBars[i].n = i
		actionBars[i].isVertical = isVertical
		parent:moveChildToIndex(actionBars[i], index)
	end
end

function resizeLockButtons()
	local rightLockPanel = m_interface.getRightLockPanel()
	local rightCount = getActiveRightBars()
	rightLockPanel:setVisible(true)
	rightLockPanel:setIcon(Options.clientOptions["actionBarRightLocked"] and "/images/game/actionbar/locked" or "/images/game/actionbar/unlocked")
	if rightCount >= 1 and rightCount <= 3 then
		rightLockPanel:setWidth(35 + (rightCount - 1) * 36 - 1)
		rightLockPanel:getParent():setWidth(((36 + (rightCount - 1) * 36)) + 1)
	else
		rightLockPanel:setWidth(0)
		rightLockPanel:getParent():setWidth(0)
		rightLockPanel:setVisible(false)
	end

	local bottomLockPanel = m_interface.getBottomLockPanel()
	local bottomCount = getActiveBottomBars()
	bottomLockPanel:setVisible(true)
	bottomLockPanel:setIcon(Options.clientOptions["actionBarBottomLocked"] and "/images/game/actionbar/locked" or "/images/game/actionbar/unlocked")
	if bottomCount >= 1 and bottomCount <= 3 then
		bottomLockPanel:setHeight(34 + (bottomCount - 1) * 36)
	else
		bottomLockPanel:setHeight(0)
		bottomLockPanel:setVisible(false)
	end

	local leftLockPanel = m_interface.getLeftLockPanel()
	local leftCount = getActiveLeftBars()
	leftLockPanel:setVisible(true)
	leftLockPanel:setIcon(Options.clientOptions["actionBarLeftLocked"] and "/images/game/actionbar/locked" or "/images/game/actionbar/unlocked")
	if leftCount >= 1 and leftCount <= 3 then
		leftLockPanel:setWidth(35 + (leftCount - 1) * 36 - 1)
		leftLockPanel:getParent():setWidth(((36 + (leftCount - 1) * 36)) + 1)
	else
		leftLockPanel:setWidth(0)
		leftLockPanel:getParent():setWidth(0)
		leftLockPanel:setVisible(false)
	end
end

function setupActionBar(n)
	local actionbar = actionBars[n]
	local visible = actionbar:isVisible()
	local locked = Options.actionBar[n].isLocked
	actionbar.tabBar.onMouseWheel = nil

	actionbar.locked = locked

	local items = {}
	for i = 1, 50 do
		local layout = n < 4 and 'ActionButton' or 'SideActionButton'
		local widget = actionbar.tabBar:getChildById(n.."."..i)

		if not widget then
			widget = g_ui.createWidget(layout, actionbar.tabBar)
			widget:setId(n.."."..i)
		end

		resetButtonCache(widget)
		if g_game.isOnline() then
			updateButton(widget)
		end

		if widget.cooldown then
			widget.cooldown:stop()
		end

		if widget.item and widget.item:getItemId() > 100 then
			table.insert(items, widget.item:getItem())
		end
	end

	scheduleEvent(function() g_game.doThing(false) g_game.requestHotkeyItems(items) g_game.doThing(true) end, 100)
end

function resetButtonCache(button)
	if button.cache and button.cache.itemId > 0 then
		local cachedItem = cachedItemWidget[button.cache.itemId]
		if cachedItem then
			for index, widget in pairs(cachedItem) do
				if button == widget then
					table.remove(cachedItem, index)
				end
			end
		end
	end

	if button.item then
		button.item:setItem(nil)
		button.item:setOn(false)
		button.item:setChecked(false)
		button.item:setDraggable(false)
		if button.item.gray then
			button.item.gray:setVisible(false)
		end
		if button.item.text then
			button.item.text.gray:setVisible(false)
			button.item.text:setImageSource('')
			button.item.text:setText('')
		end
	end

	if button.hotkeyLabel then
		button.hotkeyLabel:setText('')
	end
	if button.parameterText then
		button.parameterText:setText('')
	end
	if button.cooldown then
		button.cooldown:setPercent(100)
		button.cooldown:setText("")
	end

	if button.cache then
		if button.cache.cooldownEvent then
			removeEvent(button.cache.cooldownEvent)
		end
		if button.cache.removeCooldownEvent then
			removeEvent(button.cache.removeCooldownEvent)
		end
	end

	button.cache = {
		cooldownEvent = nil,
		cooldownTime = 0,
		isSpell = false,
		isRuneSpell = false,
    	isPassive = false,
		spellID = 0,
		spellData = nil,
		primaryGroup = nil,
		param = "",
		sendAutomatic = false,
		actionType = 0,
		upgradeTier = 0,
		smartMode = nil,
		hotkey = nil,
		lastClick = 0,
		nextDownKey = 0,
		isDragging = false,
		buttonIndex = 0,
		buttonParent = nil,
		itemId = 0,
		equipmentPreset = {},
		equipmentPresetIcon = ""
	}
end

function onDropActionButton(self, mousePosition, mouseButton)
	if not g_ui.isMouseGrabbed() then return end
	g_mouse.updateGrabber(self, 'target')
	g_mouse.popCursor('target')
	self:ungrabMouse()
end

function onMultiUseCooldown(time)
	updateActionBar(time)
end

function onSpellCooldown(spellId, delay)
	if not m_settings.getOption("graphicalCooldown") and not m_settings.getOption("cooldownSecond") then
		return true
	end

	local isRune = Spells.isRuneSpell(spellId)
  spellCooldownCache[spellId] = {exhaustion = delay, startTime = g_clock.millis()}

	for _, actionbar in pairs(activeActionBars) do
		for _, button in pairs(actionbar.tabBar:getChildren()) do
			local cache = getButtonCache(button)
			if not (cache.isSpell or cache.isRuneSpell) then
				goto continue
			end

			if cache.isRuneSpell and not isRune then
				goto continue
			end

			if not cache.isRuneSpell and cache.spellID ~= spellId then
				goto continue
			end

			if cache.cooldownEvent ~= nil and button.cooldown:getTimeElapsed() > delay then
				goto continue
			end

			updateCooldown(button, delay)
			if cache.removeCooldownEvent then
				removeEvent(button.cache.removeCooldownEvent)
			end
			button.cache.removeCooldownEvent = scheduleEvent(function() modules.game_actionbar.removeCooldown(button) end, delay)
			:: continue ::
		end
	end
end

function onSpellGroupCooldown(groupId, delay)
	if not m_settings.getOption("graphicalCooldown") and not m_settings.getOption("cooldownSecond") then
		return true
	end

	spellGroupCooldownCache[groupId] = {exhaustion = delay, startTime = g_clock.millis()}

	for _, actionbar in pairs(activeActionBars) do
		for _, button in pairs(actionbar.tabBar:getChildren()) do
			local cache = getButtonCache(button)
			if cache.isRuneSpell or not cache.spellData then
				goto continue
			end

			if Spells.getCooldownByGroup(cache.spellData, groupId) then
				local resttime = button.cooldown:getDuration() - button.cooldown:getTimeElapsed()
				if resttime < delay then
					updateCooldown(button, delay)
					removeEvent(button.cache.removeCooldownEvent)
					button.cache.removeCooldownEvent = scheduleEvent(function() modules.game_actionbar.removeCooldown(button) end, delay)
					spellCooldownCache[button.cache.spellData.id] = {exhaustion = delay, startTime = g_clock.millis()}
				end
			end

			if Spells.getCooldownBySecondaryGroup(cache.spellData, groupId) then
				local spellCache = spellCooldownCache[button.cache.spellData.id]
				if not spellCache then
					spellCache = {}
					spellCache.startTime = 0
				end

				local resttime = button.cooldown:getDuration() - button.cooldown:getTimeElapsed()
				if resttime < delay then
					updateCooldown(button, delay)
					removeEvent(button.cache.removeCooldownEvent)
					button.cache.removeCooldownEvent = scheduleEvent(function() modules.game_actionbar.removeCooldown(button) end, delay)
					spellCooldownCache[button.cache.spellData.id] = {exhaustion = delay, startTime = g_clock.millis()}
				end
			end
			:: continue ::
		end
	end
end

function onEquipmentPresetCooldown(delay)
	for _, actionbar in pairs(activeActionBars) do
		for _, button in pairs(actionbar.tabBar:getChildren()) do
			local cache = getButtonCache(button)
			if string.empty(cache.equipmentPresetIcon) then
				goto continue
			end

			updateCooldown(button, delay)
			removeEvent(button.cache.removeCooldownEvent)
			button.cache.removeCooldownEvent = scheduleEvent(function() modules.game_actionbar.removeCooldown(button) end, delay)

			:: continue ::
		end
	end
end

function onPassiveData(currentCooldown, maxCooldown, canDecay)
	passiveData = {cooldown = currentCooldown, max = maxCooldown}
	updateActionPassive()
end

function onSpellsChange(player, list)
	spellListData = {}
	for _, spellId in pairs(list) do
		local spell = Spells.getSpellByClientId(spellId)
		if spell then
			spellListData[tostring(spellId)] = spell
		end
	end
end

function onSpellModification(spells)
	spellModification = {}
	for _, data in pairs(spells) do
		spellModification[tostring(data[1])] = {type = data[2], value = data[3]}
	end

	onUpdateActionBarStatus()
end

function getActiveBottomBars()
	if #actionBars == 0 then
		return 0
	end

	local count = 0
	for i = 1, 3 do
		local enabled = Options.actionBar[i].isVisible
		if enabled then
			count = count + 1
		end
	end
	return count
end

function getActiveRightBars()
	if #actionBars == 0 then
		return 0
	end

	local count = 0
	for i = 7, 9 do
		local enabled = Options.actionBar[i].isVisible
		if enabled then
			count = count + 1
		end
	end
	return count
end

function getActiveLeftBars()
	if #actionBars == 0 then
		return 0
	end

	local count = 0
	for i = 4, 6 do
		local enabled = Options.actionBar[i].isVisible
		if enabled then
			count = count + 1
		end
	end
	return count
end

function onHotkeyItems(itemList)
	for _, data in pairs(itemList) do
		table.insert(hotkeyItemList, data)
	end

	for _, actionbar in pairs(activeActionBars) do
		for _, button in pairs(actionbar.tabBar:getChildren()) do
			if button.item:getItemId() < 100 then
				goto continue
			end
			setupButtonTooltip(button, false)
			:: continue ::
		end
	end
end

function updateInventoryItems(_)
    for _, widgetList in pairs(cachedItemWidget) do
        for _, widget in pairs(widgetList) do
            updateButtonState(widget)
        end
    end
end

function setupButtonTooltip(button, isEmpty)
	if not g_game.isOnline() then
		return true
	end

	local cache = getButtonCache(button)
	if isEmpty then
	  local tooltip = "Action Button " .. button:getId()
		local hotkeyDesc = cache.hotkey and cache.hotkey or "None"
		tooltip = tooltip.."\n\nAction:  " .. "None"
		tooltip = tooltip.."\nHotkeys:  " .. hotkeyDesc
		if button.item then
			button.item:setTooltip(tooltip)
		end
		return true
	end

	local actionDesc = ""
	local spellData = cache.spellData

	local function getModifiedSpellCooldown(data)
		local modified = spellModification[tostring(data.id)]
		if not modified or modified.type ~= 1 then
			return data.exhaustion
		end

		return data.exhaustion + modified.value
	end

	local function getModifiedSpellMana(data)
		local modified = spellModification[tostring(data.id)]
		if not modified or modified.type ~= 0 then
			return data.mana
		end

		return data.mana + modified.value
	end

	if cache.actionType == 7 then
		if not cache.isSpell then
			actionDesc = 'Say: "' .. string.lineBreaks(cache.param, 44, 36) .. '"\n'
			actionDesc = actionDesc .. "Auto sent:  " .. (cache.sendAutomatic and "Yes" or "No")
		else
			actionDesc = "Cast " .. Spells.getSpellNameByWords(spellData.words) .."\n"
			actionDesc = actionDesc.. "   Formula:  ".. cache.param .. "\n"
			actionDesc = actionDesc.. " Cooldown:  " .. getModifiedSpellCooldown(spellData) / 1000 .. "s\n"
			actionDesc = actionDesc.. "         Mana:  ".. getModifiedSpellMana(spellData)
		end
	elseif cache.actionType == 8 then
		actionDesc = "Gift of Life"
	elseif cache.actionType == 9 then
		actionDesc = "Equip Preset"
	else
		actionDesc = UseTypesTip[cache.actionType]
		if actionDesc == nil then
			actionDesc = "Use %s"
		end

		if cache.actionType == UseTypes["Equip"] then
			local itemName = getItemNameById(button.item:getItem():getId()) .. ((cache.upgradeTier and cache.upgradeTier > 0) and " (Tier " .. cache.upgradeTier .. ")" or "")
			actionDesc = tr(actionDesc, (button.item:isChecked() and "Unequip" or "Equip"), itemName)
		elseif button.item:getItem() then
			actionDesc = tr(actionDesc, getItemNameById(button.item:getItem():getId()))
		end

		local smartId = getSmartCast(button.cache.itemId)
		local upgradeTier = button.cache.upgradeTier or 0
		local itemCount = getActionItemCount(button.cache.itemId, upgradeTier)
		if smartId then
			itemCount = itemCount + getActionItemCount(smartId, upgradeTier)
		end
		actionDesc = actionDesc .. "\n    Amount:  " .. itemCount
	end

	local hotkeyDesc = cache.hotkey and cache.hotkey or "None"
	local tooltip = "Action Button ".. button:getId()

	if cache.actionType == 8 then
		tooltip = tooltip .. "\n\n Passive Ability:  " .. actionDesc
		tooltip = tooltip .. "\n            Hotkeys:  " .. hotkeyDesc
	else
		tooltip = tooltip .. "\n\n       Action:  " .. actionDesc
		tooltip = tooltip .. "\n   Hotkeys:  " .. hotkeyDesc
	end

	button.item:setTooltip(tooltip)
end

function updateButton(button)
	if not player then
		player = g_game.getLocalPlayer()
	end

	local buttonData = nil
	local barID, buttonID = string.match(button:getId(), "(%d+)%.(%d+)")

	if not button.item then
		local actionId, buttonId = button:getId():match("([^.]+)%.([^.]+)")
		button:destroy()
		local actionbar = actionBars[tonumber(actionId)]
		local layout = tonumber(actionId) < 4 and 'ActionButton' or 'SideActionButton'
		local widget = g_ui.createWidget(layout, actionbar.tabBar)
		actionbar.tabBar:moveChildToIndex(widget, tonumber(buttonId))
		widget:setId(actionId.."."..buttonId)
		updateButton(widget)
		return
	end

	for _, data in pairs(Options.actionBarMappings) do
		if data["actionBar"] == tonumber(barID) and data["actionButton"] == tonumber(buttonID) then
			buttonData = data
			break
		end
	end

	resetButtonCache(button)
	button.item.text:setTextOffset("0 0")

	button.cache = getButtonCache(button)
	if button.item.getItemId and not button.cache.actionType then
		button.item:setItemId(0, true)
		button.item:setOn(false)
		-- Clear tier icon so it doesn't remain after item is removed
		if ItemsDatabase and ItemsDatabase.setTier then
			ItemsDatabase.setTier(button.item, nil)
		end
	end

	setupHotkeyButton(button)
	if button.cache.hotkey then
		button.hotkeyLabel:setText(translateDisplayHotkey(button.cache.hotkey))
	end

	if not buttonData or not buttonData["actionsetting"] then
		setupButtonTooltip(button, true)
		button.item:setDraggable(false)
		configureButtonMouseRelease(button)
		return true
	end

	local useAction = buttonData["actionsetting"]["useObject"]
	local sendText = buttonData["actionsetting"]["chatText"]
	local passiveAbility = buttonData["actionsetting"]["passiveAbility"]
	local equipPreset = buttonData["actionsetting"]["equipmentPreset"]
	local equipPresetIcon = buttonData["actionsetting"]["equipmentPresetIcon"] or ""

	if useAction then
		button.item:setItemId(useAction, true)
		button.item:setOn(true)

		local cached = cachedItemWidget[useAction]
		if cached then
			table.insert(cached, button)
		else
			cachedItemWidget[useAction] = {}
			table.insert(cachedItemWidget[useAction], button)
		end

		-- check runes
		local spellData = Spells.getRuneSpellByItem(useAction)
		if spellData then
			button.cache.isRuneSpell = true
			button.cache.spellData = spellData
			if spellData.vocations and not table.contains(spellData.vocations, translateVocation(player:getVocation())) then
				button.item.gray:setVisible(true)
			end
		end

		button.cache.itemId = button.item:getItemId()
		button.cache.smartMode = buttonData["actionsetting"]["useEquipSmartMode"]
		button.cache.upgradeTier = buttonData["actionsetting"]["upgradeTier"]
		button.item:setTier(button.cache.upgradeTier or 0)
		button.cache.actionType = UseTypes[buttonData["actionsetting"]["useType"]]
		updateButtonState(button)
	end

	if sendText then
		local displayText = sendText
		local normalizedText = sendText:lower()
		if normalizedText == "exori san infir" then
			normalizedText = "exori infir con"
		end

		local spellData, param = Spells.getSpellDataByParamWords(normalizedText)
		local spellIcon = spellData and SpellIcons[spellData.icon]
		if spellData and spellIcon then
			local spellId = spellIcon[1]
			local source = SpelllistSettings['Default'].iconsFolder
			local clip = Spells.getImageClipNormal(spellId, 'Default')

			button.item.text:setImageSource(source)
			button.item.text:setImageClip(clip)
			button.cache.isSpell = true
			button.cache.spellID = spellData.id
			button.cache.spellData = spellData
			button.cache.primaryGroup = spellData.group and Spells.getGroupIds(spellData)[1] or nil

			if param then
				local formatedParam = param:gsub('"', '')
        		button.parameterText:setText(short_text('"' .. formatedParam, 4))
        		button.cache.castParam = formatedParam
			end

			if not playerCanUseSpell(spellData) then
				button.item.text.gray:setVisible(true)
			end

      		checkRemainSpellCooldown(button, spellData.id)
		else
			if button.cache.hotkey then
				displayText = displayText:match("^(%S+)") or displayText
				button.item.text:setTextOffset("0 10")
				button.item.text:setText(short_text(displayText, 6))
			else
				button.item.text:setText(short_text(displayText, 15))
			end
		end

		button.item:setOn(true)
		button.cache.param = sendText
		button.cache.sendAutomatic = buttonData["actionsetting"]["sendAutomatically"]
		button.cache.actionType = UseTypes["chatText"]
	end

	if passiveAbility then
		local passive = PassiveAbilities[passiveAbility]
		button.item.text:setImageSource(passive.icon)
		button.item.text:setImageClip("0 0 32 32")
		button.cache.actionType = UseTypes["passiveAbility"]
		button.cache.isPassive = true
		updateActionPassive(button)
	end

	if equipPreset and not table.empty(equipPreset) then
		button.item:setOn(true)
		button.cache.equipmentPreset = equipPreset
		button.cache.equipmentPresetIcon = equipPresetIcon
		button.cache.actionType = UseTypes["equipmentPreset"]

		if not string.empty(equipPresetIcon) then
			button.item.text:setImageSource("/images/game/actionbar/equip-preset/" .. equipPresetIcon)
			button.item.text:setImageClip("0 0 30 30")
		end
	end

  button.item:setDraggable(true)
  setupButtonTooltip(button, false)

  local parentButton = button:getParent()
  if parentButton then
	button.cache.buttonIndex = parentButton:getChildIndex(button)
	button.cache.buttonParent = parentButton
  end

  button.item.onDragEnter = function(self, mousePos)
    if Options.actionBar[tonumber(barID)].isLocked then
      return false
    end

	closeCurrentMultiActionPanel()
	button.cooldown:setBorderWidth(1)
    button.cache.isDragging = true
	dragButton = button
	dragItem = self
    onDragItem(self, mousePos)
    return true
  end

  button.item.onDragMove = function(self, mousePos, mouseMoved)
    self:setX(mousePos.x)
    self:setY(mousePos.y)

    if lastHighlightWidget then
      lastHighlightWidget:setBorderWidth(0)
      lastHighlightWidget:setBorderColor('alpha')
    end

    local clickedWidget = gameRootPanel:recursiveGetChildByPos(mousePos, false)
    if clickedWidget and clickedWidget:backwardsGetWidgetById("tabBar") then
      lastHighlightWidget = clickedWidget
      lastHighlightWidget:setBorderWidth(1)
      lastHighlightWidget:setBorderColor('white')
    else
      lastHighlightWidget = nil
    end

    return true
  end

  button.item.onDragLeave = function(self, widget, mousePos)
    if not button.cache.isDragging then
      return false
    end
    isLoaded = false
    button.cache.isDragging = false
    onDragItemLeave(self, mousePos, button)
    isLoaded = true
	dragButton = nil
	dragItem = nil
    return true
  end

  button.item.onClick = function() onExecuteAction(button) end
  button.item.text.onClick = function() onExecuteAction(button) end
  configureButtonMouseRelease(button)
  scheduleEvent(function() updateActionBar() end, 100)
end

function checkRemainSpellCooldown(button, spellId)
  if not m_settings.getOption("graphicalCooldown") and not m_settings.getOption("cooldownSecond") then
    return true
  end

  local cooldownData = spellCooldownCache[spellId]
  if not cooldownData then
    return
  end

  if (cooldownData.startTime + cooldownData.exhaustion) < g_clock.millis() then
    return
  end

  button.cache = getButtonCache(button)
  local remainTime = (cooldownData.startTime + cooldownData.exhaustion) - g_clock.millis()

  updateCooldown(button, remainTime)
  removeEvent(button.cache.removeCooldownEvent)
  button.cache.removeCooldownEvent = scheduleEvent(function() modules.game_actionbar.removeCooldown(button) end, remainTime)
end

function configureButtonMouseRelease(button)
  button.onMouseRelease = function(button, mousePos, mouseButton)
	button.cache = getButtonCache(button)
	if mouseButton == MouseRightButton then
		local menu = g_ui.createWidget('PopupMenu')
		menu:setGameMenu(true)
		menu:addOption(button.cache.isSpell and tr('Edit Spell') or tr('Assign Spell'), function() assignSpell(button) end)
		if button.item and button.item:getItemId() > 100 then
			menu:addOption(tr('Edit Object'), function() assignItem(button, button.item:getItemId()) end)
		else
			menu:addOption(tr('Assign Object'), function() assignItemEvent(button) end)
		end

		local buttonText = ""
		if button.item then
			buttonText = button.item.text:getText()
		end

		local hasEquipmentPreset = button.cache.equipmentPreset and not table.empty(button.cache.equipmentPreset)
		menu:addOption(buttonText:len() > 0 and tr('Edit Text') or tr('Assign Text'), function() assignText(button) end)
		menu:addOption(button.cache.isPassive and tr('Edit Passive Ability') or tr('Assign Passive Ability'), function() assignPassive(button) end)
		menu:addOption(button.cache.hotkey and tr('Edit Hotkey') or tr('Assign Hotkey'), function() assignHotkey(button) end)
		menu:addOption(hasEquipmentPreset and tr('Edit Equipments') or tr('Assign Equipments'), function() assignEquipment(button) end)
		menu:addSeparator()
		menu:addOption(tr('Multi-Action'), function() toggleMultiActionPanel(button) end)
		if button.cache.actionType > 0 then
			menu:addSeparator()
			menu:addOption(tr('Clear Action'), function() clearButton(button, true) end)
		end
		menu:display(mousePos)
		end
	end
end

function onDragItem(self, mousePos)
  self:setPhantom(true)
  self:setParent(gameRootPanel)
  self:setX(mousePos.x)
  self:setY(mousePos.y)

  self:setBorderColor('white')

  if lastHighlightWidget then
    lastHighlightWidget:setBorderWidth(0)
    lastHighlightWidget:setBorderColor('alpha')
  end

  local clickedWidget = gameRootPanel:recursiveGetChildByPos(mousePos, false)
  if not clickedWidget or not clickedWidget:backwardsGetWidgetById("tabBar") then
	return true
  end

  lastHighlightWidget = clickedWidget
  lastHighlightWidget:setBorderWidth(1)
  lastHighlightWidget:setBorderColor('white')
end

function onDragItemLeave(self, mousePos, button)
  if lastHighlightWidget then
    lastHighlightWidget:setBorderWidth(0)
    lastHighlightWidget:setBorderColor('alpha')
  end

  local clickedWidget = gameRootPanel:recursiveGetChildByPos(mousePos, false)
  if not clickedWidget or not clickedWidget:backwardsGetWidgetById("tabBar") then
    	resetDragWidget(self, button)
		return true
	end

  local destButton = getButtonById(clickedWidget:getParent():getId())
  if not destButton then
    resetDragWidget(self, button)
    return true
  end

  local destButtonCache = destButton.cache

  button.cache = getButtonCache(button)
  local itemId = button.cache.itemId
  local destBarID, destButtonID = string.match(destButton:getId(), "(.*)%.(.*)")
  local draggedBarID, draggedButtonID = string.match(button:getId(), "(.*)%.(.*)")

  local cachedItem = cachedItemWidget[itemId]
  if cachedItem then
    for index, widget in pairs(cachedItem) do
      if button == widget then
        table.remove(cachedItem, index)
      end
	end
  end

  local cachedItem = cachedItemWidget[destButtonCache.itemId ]
  if cachedItem then
    for index, widget in pairs(cachedItem) do
      if button == widget then
        table.remove(cachedItem, index)
      end
	end
  end

  local isButtonEmpty = buttonIsEmpty(destButton)

  if button.cache.actionType == UseTypes["chatText"] then
    Options.createOrUpdateText(tonumber(destBarID), tonumber(destButtonID), button.cache.param, button.cache.sendAutomatic)
  elseif itemId ~= 0 then
    Options.createOrUpdateAction(tonumber(destBarID), tonumber(destButtonID), getActionName(button.cache.actionType), itemId, button.cache.upgradeTier, button.cache.smartMode)
  elseif button.cache.isPassive then
    Options.createOrUpdatePassive(tonumber(destBarID), tonumber(destButtonID), 1)
  elseif not table.empty(button.cache.equipmentPreset) then
    Options.createOrUpdatePreset(tonumber(destBarID), tonumber(destButtonID), button.cache.equipmentPreset, button.cache.equipmentPresetIcon)
  end

  updateButton(destButton)

  if isButtonEmpty then
    Options.removeAction(tonumber(draggedBarID), tonumber(draggedButtonID))
	removeCooldown(destButton)
    resetDragWidget(self, button)
  else
    if destButtonCache.actionType == UseTypes["chatText"] then
      Options.createOrUpdateText(tonumber(draggedBarID), tonumber(draggedButtonID), destButtonCache.param, destButtonCache.sendAutomatic)
    elseif destButtonCache.itemId ~= 0 then
      Options.createOrUpdateAction(tonumber(draggedBarID), tonumber(draggedButtonID), getActionName(destButtonCache.actionType), destButtonCache.itemId, destButtonCache.upgradeTier, destButtonCache.smartMode)
    elseif destButtonCache.isPassive then
      Options.createOrUpdatePassive(tonumber(draggedBarID), tonumber(draggedButtonID), 1)
	elseif not table.empty(destButtonCache.equipmentPreset) then
		Options.createOrUpdatePreset(tonumber(draggedBarID), tonumber(draggedButtonID), destButtonCache.equipmentPreset, destButtonCache.equipmentPresetIcon)
    end

	removeCooldown(destButton)
    resetDragWidget(self, button)
  end

  self:setBorderColor('alpha')
end

function resetDragWidget(self, button)
  button.cache = getButtonCache(button)
  local cachedItem = cachedItemWidget[button.cache.itemId]
  if cachedItem then
    for index, widget in pairs(cachedItem) do
      if button == widget then
        table.remove(cachedItem, index)
      end
    end
  end

  self:destroy()
  local barID, buttonID = string.match(button:getId(), "(.*)%.(.*)")
  local style = tonumber(barID) > 3 and "SideActionButton" or "ActionButton"

  button:destroy()

  local destBar = actionBars[tonumber(barID)].tabBar
  local widget = g_ui.createWidget(style, destBar)

  if destBar then
	destBar:moveChildToIndex(widget, buttonID)
  end
  widget:setId(barID.."."..buttonID)
  updateButton(widget)
end

function buttonIsEmpty(button)
  return button.item:getItemId() == 0 and string.empty(button.item.text:getText()) and string.empty(button.item.text:getImageSource())
end

function getActionName(actionType)
  for k, v in pairs(UseTypes) do
    if v == actionType then
      return k
    end
  end
end

function removeCooldown(button)
	if not button or not button.cache then
		return true
	end

	button.cache.removeCooldownEvent = nil
	if button.cooldown then
		button.cooldown:stop()
		button.cooldown:setPercent(100)
		button.cooldown:setText("")
	end
end

function updateCooldown(button, timeMs)
	button.cooldown:showTime(m_settings.getOption("cooldownSecond"))
	button.cooldown:showProgress(m_settings.getOption("graphicalCooldown"))
	button.cooldown:setDuration(timeMs)
	button.cooldown:start()
end

function updateActionPassive(button)
	if not m_settings.getOption("graphicalCooldown") and not m_settings.getOption("cooldownSecond") then
		return true
	end

	if not button then
		for _, actionbar in pairs(activeActionBars) do
			for _, button in pairs(actionbar.tabBar:getChildren()) do
				if button.cache.isPassive then
					button.item.text.gray:setVisible(passiveData.max == 0)
				end

				if not button.cache.isPassive or button.cache.cooldownEvent ~= nil then
					goto continue
				end

				updateCooldown(button, passiveData.cooldown * 1000)
				button.cache.removeCooldownEvent = scheduleEvent(function() modules.game_actionbar.removeCooldown(button) end, passiveData.cooldown * 1000)
				:: continue ::
			end
		end
		return true
	else
		if button.cache.isPassive then
			button.item.text.gray:setVisible(passiveData.max == 0)
		end
	end

	if passiveData.max > 0 then
		removeEvent(button.cache.removeCooldownEvent)
		updateCooldown(button, passiveData.cooldown * 1000)
		button.cache.removeCooldownEvent = scheduleEvent(function() modules.game_actionbar.removeCooldown(button) end, passiveData.cooldown * 1000)
	end
end

function onUpdateLevel(localPlayer, level, levelPercent, oldLevel, oldLevelPercent)
	if level ~= oldLevel then
		onUpdateActionBarStatus()
	end
end

function onUpdateActionBarStatus()
	if #activeActionBars == 0 then
		return true
	end

	for _, actionbar in pairs(activeActionBars) do
		for _, button in pairs(actionbar.tabBar:getChildren()) do
            updateButtonState(button)
			pcall(function() updateMultiButtonState(button) end)
		end
	end
end

function updateActionBar(multiUseCooldown)
	for _, actionbar in pairs(activeActionBars) do
		for _, button in pairs(actionbar.tabBar:getChildren()) do
			updateButtonState(button)
			if multiUseCooldown and button.item and button.cache.itemId then
				local item = button.item:getItem()
				if item and item:isMultiUse() then
					local marketArray = {10, 12, 14}
					if table.contains(marketArray, item:getMarketData().category) then
						updateCooldown(button, multiUseCooldown)
					end
				end
			end
		end
	end
end

function onExecuteAction(button, isPress)
	local cache = getButtonCache(button)
	if cache.lastClick > g_clock.millis() then
		return true
	end

	if m_interface.gameRightPanels:isFocusable() or m_interface.gameLeftPanels:isFocusable() then
		return true
	end

	if not isPress then
		button.cache.nextDownKey = g_clock.millis() + 500
	end

	if isPress and button.cache.nextDownKey > g_clock.millis() then
		return true
	end

	local cooldown = isPress and 600 or 150
	button.cache.lastClick = g_clock.millis() + cooldown
	local action = button.cache.actionType
	if action == 0 then
		return true
	end

	if action == UseTypes["Equip"] and button.item then
		local smartId = getSmartCast(button.cache.itemId)
		local upgradeTier = button.cache.upgradeTier or 0

		if not smartId or not button.cache.smartMode then
			if smartId then
				if not hasActionItemAvailable(button.cache.itemId, upgradeTier) then
					return
				end
			end

			g_game.equipItemId(button.cache.itemId, upgradeTier)
		else
			local activeId = getActiveSmartCast(button.cache.itemId) or button.cache.itemId

			g_game.equipItemId(activeId, upgradeTier)
		end
	end

	if action == UseTypes["equipmentPreset"] and button.item then
		local preset = {}
		for i, data in pairs(button.cache.equipmentPreset) do
			local slotId = tonumber(string.match(i, "%d+"))
			table.insert(preset, {slot = slotId, itemId = data.itemId, tier = data.tier, identifier = data.identifier, smartMode = data.smartMode})
		end

		g_game.sendEquipmentPreset(preset)
	end

	if action == UseTypes["Use"] and button.item then
		if (button.item:getItem():isContainer()) then
			g_game.closeContainerByItemId(button.item:getItemId())
		else
			g_game.useInventoryItem(button.item:getItemId())
		end
	end

	if action == UseTypes["UseOnYourself"] and button.item then
		g_game.useInventoryItemWith(button.item:getItemId(), player, button.item:getItemSubType() or -1)
	end

	if action == UseTypes["SmartCast"] and button.item then
		local pos = g_window.getMousePosition()
		local clickedWidget = gameRootPanel:recursiveGetChildByPos(pos, false)
		if not clickedWidget or clickedWidget:getClassName() ~= 'UIGameMap' then
			modules.game_textmessage.displayFailureMessage(tr('You can only perfom this action in game window.'))
			return
		end
		local tile = clickedWidget:getTile(pos)
		if not tile then
			modules.game_textmessage.displayFailureMessage(tr('You can only perfom this action in game window.'))
			return
		end

		local gameMapPanel = m_interface.gameMapPanel
		gameMapPanel:scheduleBlockMouseRelease(300)
		g_game.useWith(button.item:getItem(), tile:getTopUseThing(), button.item:getItemSubType() or -1)
	end

	if button.item and not g_ui.getCustomInputWidget() then
		if action == UseTypes["SelectUseTarget"] then
			m_interface.startUseWith(button.item:getItem(), button.item:getItemSubType() or - 1)
		end

		if action == UseTypes["UseOnTarget"] then
			local attackingCreature = g_game.getAttackingCreature()
			if not attackingCreature then
				m_interface.startUseWith(button.item:getItem(), button.item:getItemSubType() or - 1)
			else
				g_game.useWith(button.item:getItem(), attackingCreature, button.item:getItemSubType() or -1)
			end
		end
	end

	if action == UseTypes["chatText"] and button.cache.sendAutomatic then
    if button.cache.isSpell then
      spellGroupPressed[tostring(button.cache.primaryGroup)] = true
      g_game.talk(button.cache.param)
    else
      modules.game_console.sendMessage(button.cache.param)
    end

    modules.game_console.getConsole():setText('')
  elseif action == UseTypes["chatText"] then
  	modules.game_console.getConsole():setText(button.cache.param)
  	modules.game_console.getConsole():setCursorPos(#button.cache.param)
  end

  if cacheMultiActionButtons[button] and button.cache.multiActions then
    local actions = button.cache.multiActions
    for i = 2, 3 do
      if actions[i] and not table.empty(actions[i]) then
        local snappedAction = actions[i]
        scheduleEvent(function()
          if button and not button:isDestroyed() then
            executeMultiAction(button, snappedAction)
          end
        end, MULTI_ACTION_DELAY_MS * (i - 1))
      end
    end
  end
end

function onCheckKeyUp(button)
	local cache = getButtonCache(button)
	if cache.isSpell then
		spellGroupPressed[tostring(button.cache.primaryGroup)] = nil
	end
end

function assignItemEvent(button, multiSlotIndex)
	getButtonCache(button).multiSlotIndex = multiSlotIndex or nil
	g_mouse.updateGrabber(mouseGrabberWidget, 'target')
	mouseGrabberWidget:grabMouse()
	g_mouse.pushCursor('target')
	mouseGrabberWidget.onMouseRelease = function(self, mousePosition, mouseButton) onAssignItem(self, mousePosition, mouseButton, button) end
end

function onAssignItem(self, mousePosition, mouseButton, button)
	g_mouse.updateGrabber(mouseGrabberWidget, 'target')
	mouseGrabberWidget:ungrabMouse()
	g_mouse.popCursor('target')
	mouseGrabberWidget.onMouseRelease = onDropActionButton

	local clickedWidget = gameRootPanel:recursiveGetChildByPos(mousePosition, false)
    if not clickedWidget then
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
		return true
	end
	assignItem(button, itemId, itemTier)
end

function saveMultiState(button)
	return button.cache and button.cache.multiSlotIndex,
	       button.cache and button.cache.multiActions
end

saveMulti = saveMultiState

function restoreMultiState(button, slotIndex, actions)
	if slotIndex ~= nil then button.cache.multiSlotIndex = slotIndex end
	if actions ~= nil then button.cache.multiActions = actions end
end

restoreMulti = restoreMultiState

function hasMultiActions(multiActions)
	if not multiActions then return false end
	local count = 0
	for i = 1, 3 do
		if type(multiActions[i]) == "table" and next(multiActions[i]) ~= nil then count = count + 1 end
	end
	return count >= 2
end

function countFilledMultiSlots(multiActions)
	if not multiActions then return 0 end
	local count = 0
	for i = 1, 3 do
		if type(multiActions[i]) == "table" and next(multiActions[i]) ~= nil then count = count + 1 end
	end
	return count
end

function assignSpell(button, multiSlotIndex)
	getButtonCache(button).multiSlotIndex = multiSlotIndex or nil
	local radio = UIRadioGroup.create()
	if activeWindow and not activeWindow:isDestroyed() then
		activeWindow:destroy()
	end
	activeWindow = g_ui.loadUI('spell', g_ui.getRootWidget())
	local window = activeWindow
	window:show()
	g_client.setInputLockWidget(window)
	window:raise()
	scheduleEvent(function()
		if window and not window:isDestroyed() then
			window:focus()
		end
	end, 50)
	
	window:setText("Assign Spell to Action Button ".. button:getId())

	local spells = modules.gamelib.SpellInfo['Default']
	for spellName, spellData in pairs(spells) do
		if not table.contains(spellData.vocations, translateVocation(player:getVocation())) then
			goto continue
		end

		local widget = g_ui.createWidget('SpellPreview', window.contentPanel.spellList)
		local spellId = SpellIcons[spellData.icon][1]
		local source = SpelllistSettings['Default'].iconsFolder
		local clip = Spells.getImageClipNormal(spellId, 'Default')

		-- radio
		radio:addWidget(widget)
		widget:setId(spellData.id)
		widget:setText(spellName.."\n"..spellData.words)
		widget.voc = spellData.vocations
		widget.param = spellData.parameter
		widget.source = source
		widget.clip = clip
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

  -- edit spell
  if button.cache.spellData and not button.cache.isRuneSpell then
    local name = Spells.getSpellNameByWords(button.cache.spellData.words)
	local spellId = SpellIcons[button.cache.spellData.icon][1]
	local source = SpelllistSettings['Default'].iconsFolder
	local clip = Spells.getImageClipNormal(spellId, 'Default')

    window.contentPanel.preview:setText(name.."\n"..button.cache.spellData.words)
    window.contentPanel.preview.image:setImageSource(source)
    window.contentPanel.preview.image:setImageClip(clip)

    window.contentPanel.paramLabel:setOn(button.cache.spellData.parameter)
    window.contentPanel.paramText:setEnabled(button.cache.spellData.parameter)
    if button.cache.spellData.parameter then
      window.contentPanel.paramText:setText(button.cache.castParam)
	  if button.cache.castParam then
	  	window.contentPanel.paramText:setCursorPos(#button.cache.castParam)
	  end
    end

    for i, k in pairs(window.contentPanel.spellList:getChildren()) do
      if k:getId() == tostring(button.cache.spellData.id) then
        radio:selectWidget(window.contentPanel.spellList:getChildren()[i])
        window.contentPanel.spellList:ensureChildVisible(window.contentPanel.spellList:getChildren()[i])
        break
      end
    end
  end

	-- callback
	radio.onSelectionChange = function(widget, selected)
		if selected and window.contentPanel then
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

	if window.contentPanel.spellList:getChildren() and not button.cache.spellData then
		radio:selectWidget(window.contentPanel.spellList:getChildren()[1])
	end

  local cancelFunc = function()
		g_client.setInputLockWidget(nil)
		updateButton(button)
		if window and not window:isDestroyed() then
			window:destroy()
		end
	end



	local okFunc = function(destroy)
		local selected = radio:getSelectedWidget()
		if not selected then cancelFunc() return end

	  	local barID, buttonID = string.match(button:getId(), "(.*)%.(.*)")
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

		local savedMultiSlotIndex, savedMultiActions = saveMultiState(button)

		Options.createOrUpdateText(tonumber(barID), tonumber(buttonID), param, true)
		updateButton(button)

		restoreMultiState(button, savedMultiSlotIndex, savedMultiActions)
		handleMultiSlotSave(button)

		if destroy then
			g_client.setInputLockWidget(nil)
			if window and not window:isDestroyed() then
				window:destroy()
			end
		end
	end

	window.contentPanel.buttonOk.onClick = function() okFunc(true) end
	window.contentPanel.buttonApply.onClick = function() okFunc(false) end
	window.contentPanel.buttonClose.onClick = cancelFunc
	window.onEnter = function() okFunc(true) end
	window.onEscape = cancelFunc

	local actionbar = button:getParent():getParent()
	if actionbar.locked then
		cancelFunc()
	end
end

function assignText(button)
	if activeWindow and not activeWindow:isDestroyed() then
		activeWindow:destroy()
	end
	activeWindow = g_ui.loadUI('text', g_ui.getRootWidget())
	local window = activeWindow
	window:show()
	g_client.setInputLockWidget(window)
	window:raise()
	scheduleEvent(function()
		if window and not window:isDestroyed() then
			window:focus()
		end
	end, 50)

	window:setText("Assign Text to Action Button ".. button:getId())
	window.contentPanel.text.onTextChange = function(self, text)
		window.contentPanel.buttonOk:setEnabled(text:len() > 0)
		window.contentPanel.buttonApply:setEnabled(text:len() > 0)
	end

	window.contentPanel.checkPanel.tick:setChecked(true)
	window.contentPanel.text:setText(button.cache.param)
	window.contentPanel.text:setCursorPos(#button.cache.param)
	if #window.contentPanel.text:getText() > 0 then
		window.contentPanel.checkPanel.tick:setChecked(button.cache.sendAutomatic)
	end

	local okFunc = function(destroy)
		local 		autoSay = window.contentPanel.checkPanel.tick:isChecked()
		local text = window.contentPanel.text:getText()
		local fomartedText = Spells.getSpellFormatedName(text)
		local barID, buttonID = string.match(button:getId(), "(.*)%.(.*)")
		local savedMultiSlotIndex, savedMultiActions = saveMultiState(button)

		Options.createOrUpdateText(tonumber(barID), tonumber(buttonID), fomartedText, autoSay)
		updateButton(button)

		restoreMultiState(button, savedMultiSlotIndex, savedMultiActions)
		handleMultiSlotSave(button)

		if destroy then
			g_client.setInputLockWidget(nil)
			if window and not window:isDestroyed() then
				window:destroy()
			end
		end
	end

	local cancelFunc = function()
		g_client.setInputLockWidget(nil)
		if window and not window:isDestroyed() then
			window:destroy()
		end
	end

	window.contentPanel.buttonOk.onClick = function() okFunc(true) end
	window.contentPanel.buttonApply.onClick = function() okFunc(false) end
	window.contentPanel.buttonClose.onClick = cancelFunc
	window.onEscape = cancelFunc
	window.onEnter = function() okFunc(true) end
	window:insertLuaCall('onEnter')
	window:insertLuaCall('onEscape')

	local actionbar = button:getParent():getParent()
	if actionbar.locked then
		cancelFunc()
	end
end

function assignItem(button, itemId, itemTier, dragEvent)
	if not isLoaded then
		return true
	end

	if not button.item then
		updateButton(button)
		return
	end

	local actionbar = button:getParent():getParent()
	if dragEvent and actionbar.locked or actionbar.locked then
		updateButton(button)
		return
	end

	local radio = UIRadioGroup.create()
	local item = button.item:getItem()
	local id = button.item:getItemId()

	if activeWindow and not activeWindow:isDestroyed() then
		activeWindow:destroy()
	end

	activeWindow = g_ui.loadUI('object', g_ui.getRootWidget())
	local window = activeWindow
	window:show()
	g_client.setInputLockWidget(window)
	window:raise()
	scheduleEvent(function()
		if window and not window:isDestroyed() then
			window:focus()
		end
	end, 50)

	window:setText("Assign Object to Action Button " .. button:getId())
	window:setId("assignItemWindow")

	window.contentPanel.select.onClick = function()
		window:destroy()
		assignItemEvent(button)
	end

	local fromSelect = false
	if button.item:getItemId() > 0 and button.item:getItemId() ~= itemId then
		fromSelect = true
	end

	window.contentPanel.item:setItemId(itemId)
	if not item or item:getId() == 0 then
		item = window.contentPanel.item:getItem()
	end

	if not item then
		window.contentPanel.buttonOk:setEnabled(false)
		window.contentPanel.buttonApply:setEnabled(false)
		return
	end

	if item:getClassification() == 0 then
		itemTier = 0
	end

	if window.contentPanel.item:getItem() then
		window.contentPanel.item:getItem():setTier(itemTier)
	end

	-- ativar smart object (se tem cloth e se tem wearout)
	window.contentPanel.checks.smart:setVisible(false)
	if (item:getClothSlot() > 0 and (item:hasExpireStop() or getSmartCast(item:getId()))) then
		window.contentPanel.checks.smart:setVisible(true)
		if button.cache.smartMode and button.cache.smartMode == true then
			window.contentPanel.checks.smart:setChecked(true)
		end
	end

	local checkData = {
		{ id = "UseOnYourself", useType = "UseOnYourself" },
		{ id = "UseOnTarget", useType = "UseOnTarget" },
		{ id = "SmartCast", useType = "SmartCast" },
		{ id = "SelectUseTarget", useType = "SelectUseTarget" },
		{ id = "Equip", useType = "Equip" },
		{ id = "Use", useType = "Use" }
	}

	local function canSelectUseType(useType)
		return fromSelect or button.cache.actionType == 0 or button.cache.actionType == UseTypes[useType]
	end

	for _, data in ipairs(checkData) do
		local child = window.contentPanel.checks:getChildById(data.id)
		if child then
			radio:addWidget(child)
			child:setEnabled(false)
			child:setChecked(false)

			local enabled = false
			if data.useType == "Equip" then
				enabled = canEquipItem(item)
			elseif data.useType == "Use" then
				enabled = canUseActionbarItem(item)
			else
				enabled = item:isMultiUse()
			end

			if enabled then
				child:setEnabled(true)
				if not radio:getSelectedWidget() then
					local canAutoSelect = data.useType == "Equip" or not (item:getClothSlot() > 0 or (item:getClothSlot() == 0 and item:getClassification() > 0))
					if canSelectUseType(data.useType) and canAutoSelect then
						radio:selectWidget(child)
					end
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
		end
	end

	itemTier = not itemTier and button.cache.upgradeTier or itemTier
	window.contentPanel.tier:setVisible(itemTier and itemTier > 0 or false)
	if itemTier and itemTier > 1 then
		window.contentPanel.tier:setImageClip(18 * (itemTier - 1) .. " 0 18 16")
	end

	if not radio:getSelectedWidget() then
		for _, child in ipairs(window.contentPanel.checks:getChildren()) do
			if child:getId() ~= "smart" and child:isEnabled() then
				radio:selectWidget(child)
				break
			end
		end
	end

	local hasSelectedAction = radio:getSelectedWidget() ~= nil
	window.contentPanel.buttonOk:setEnabled(item and item:getId() > 100 and hasSelectedAction)
	window.contentPanel.buttonApply:setEnabled(item and item:getId() > 100 and hasSelectedAction)

	local okFunc = function(destroy)
		local selectedWidget = radio:getSelectedWidget()
		if not selectedWidget then return end
		local selected = selectedWidget:getId()
		local barID, buttonID = string.match(button:getId(), "(.*)%.(.*)")

		local cache = getButtonCache(button)
		local cachedItem = cachedItemWidget[cache.itemId]
		if cachedItem then
			for index, widget in pairs(cachedItem) do
				if button == widget then
					table.remove(cachedItem, index)
				end
			end
		end

		if item:getClassification() == 0 and (not itemTier or itemTier == 0) then
			itemTier = nil
		end

		local smartMode = nil
		if window.contentPanel.checks.smart:isVisible() then
			smartMode = window.contentPanel.checks.smart:isChecked()
		end

		Options.createOrUpdateAction(tonumber(barID), tonumber(buttonID), selected, itemId, itemTier, smartMode)

		local savedMultiSlotIndex, savedMultiActions = saveMultiState(button)
		updateButton(button)

		restoreMultiState(button, savedMultiSlotIndex, savedMultiActions)
		handleMultiSlotSave(button)

		if destroy then
			g_client.setInputLockWidget(nil)
			if window and not window:isDestroyed() then
				window:destroy()
			end
			radio:destroy()
		end
	end

	local cancelFunc = function()
		g_client.setInputLockWidget(nil)
		updateButton(button)
		if window and not window:isDestroyed() then
			window:destroy()
		end
		radio:destroy()
	end

	window.contentPanel.buttonOk.onClick = function() okFunc(true) end
	window.onEnter = function() okFunc(true) end
	window.contentPanel.buttonApply.onClick = function() okFunc(false) end
	window.contentPanel.buttonClose.onClick = cancelFunc
	window.onEscape = cancelFunc
	window:insertLuaCall('onEnter')

	local actionbar = button:getParent():getParent()
	if actionbar.locked then
		g_client.setInputLockWidget(nil)
		cancelFunc()
	end
end

function assignHotkey(button)
	if activeWindow and not activeWindow:isDestroyed() then
		activeWindow:destroy()
	end
	activeWindow = g_ui.loadUI('hotkey', g_ui.getRootWidget())
	local window = activeWindow
	window:show()
	g_client.setInputLockWidget(window)
	window:raise()
	window:focus()

	local barN = button:getParent():getParent().n
	local barDesc
	if barN < 4 then
		barDesc = "Bottom"
	elseif barN < 7 then
		barDesc = "Left"
	else
		barDesc = "Right"
	end

	barDesc = barDesc .. " Action Bar: Action Button " .. button:getId()
	window:setText('Edit Hotkey for "' .. barDesc)
	window.desc:setText(window.desc:getText() .. barDesc .. '"')
	window.display:setText(button.cache.hotkey or "")

	local chatOn = Options.isChatOnEnabled
	if chatOn then
		window.chatMode:setText("Mode: \"Chat On\"")
	else
		window.chatMode:setText("Mode: \"Chat Off\"")
	end

	window:grabKeyboard()
	window.onKeyDown = function(window, keyCode, keyboardModifiers, keyText) manageKeyPress(window, keyCode, keyboardModifiers, keyText) end

	local okFunc = function()
		local lastHotkey = button.cache.hotkey or ""
		if lastHotkey ~= "" then
			local usedButton = getUsedHotkeyButton(lastHotkey)
			if usedButton then
				Options.removeHotkey(usedButton:getId())
				g_keyboard.unbindKeyPress(lastHotkey, nil, gameRootPanel)
				g_keyboard.unbindKeyDown(lastHotkey, nil, gameRootPanel)
				updateButton(usedButton)
			end
		end

		local hotkey = window.display.combo
		if hotkey == nil or #hotkey == 0 then
			if button.cache.hotkey ~= "" then
				local hk = button.cache.hotkey
				Options.removeHotkey(button:getId())
				g_keyboard.unbindKeyPress(hk, nil, gameRootPanel)
				g_keyboard.unbindKeyDown(hk, nil, gameRootPanel)
				updateButton(button)
			end
			g_client.setInputLockWidget(nil)
			window:destroy()
			return true
		end

    Options.clearHotkey(hotkey)

		local usedButton = getUsedHotkeyButton(hotkey)
		if usedButton then
			Options.removeHotkey(usedButton:getId())
			g_keyboard.unbindKeyPress(hotkey, nil, gameRootPanel)
			g_keyboard.unbindKeyDown(hotkey, nil, gameRootPanel)
		    updateButton(usedButton)
		end

		if KeyBinds:hotkeyIsUsed(hotkey) and hotkey ~= '' then
			local key = KeyBind:getKeyBindByHotkey(hotkey)
			Options.removeActionHotkey(chatOn and "chatOn" or "chatOff", key.jsonName)
			if key then
				key:setFirstKey('')
				g_keyboard.unbindKeyDown(hotkey, nil, gameRootPanel)
				g_keyboard.unbindKeyPress(hotkey, nil, gameRootPanel)
			end
		end

		if m_settings.hotkeyIsUsed(hotkey) then
			m_settings.removeCustomHotkey(hotkey)
		end

		g_keyboard.bindKeyPress(hotkey, function() onExecuteAction(button, true) end, gameRootPanel)
		g_keyboard.bindKeyDown(hotkey, function() onExecuteAction(button, false) end, gameRootPanel)
		button.cache.hotkey = hotkey
		Options.updateActionBarHotkey("TriggerActionButton_".. button:getId(), hotkey)
		updateButton(button)
		g_client.setInputLockWidget(nil)
		window:destroy()
	end

	local clearFunc = function()
		local hotkey = window.display:getText()
		Options.removeHotkey(button:getId())
		if hotkey ~= '' then
			g_keyboard.unbindKeyPress(hotkey, nil, gameRootPanel)
			g_keyboard.unbindKeyDown(hotkey, nil, gameRootPanel)
		end
		g_client.setInputLockWidget(nil)
		updateButton(button)
		window.display:setText('')
		window:destroy()
	end

	local closeFunc = function()
		g_client.setInputLockWidget(nil)
		window:destroy()
	end

	window.buttonOk.onClick = okFunc
	window.buttonClear.onClick = clearFunc
	window.buttonClose.onClick = closeFunc

	local actionbar = button:getParent():getParent()
	if actionbar.locked then
		g_client.setInputLockWidget(nil)
		closeFunc()
	end
end

function assignPassive(button)
	local radio = UIRadioGroup.create()
	if activeWindow and not activeWindow:isDestroyed() then
		activeWindow:destroy()
	end
	activeWindow = g_ui.loadUI('passive', g_ui.getRootWidget())
	local window = activeWindow
	window:show()
	g_client.setInputLockWidget(window)
	window:raise()
	scheduleEvent(function()
		if window and not window:isDestroyed() then
			window:focus()
		end
	end, 50)

	window:setText("Assign Passive to Action Button ".. button:getId())

	for id, passiveData in pairs(PassiveAbilities) do
		local widget = g_ui.createWidget('PassivePreview', window.contentPanel.passiveList)
		radio:addWidget(widget)
		widget:setId(id)
		widget:setText(passiveData.name)
		widget.image:setImageSource(passiveData.icon)
		widget.source = passiveData.icon
		:: continue ::
	end

	radio.onSelectionChange = function(widget, selected)
		if selected then
			window.contentPanel.preview:setText(selected:getText())
			window.contentPanel.preview.image:setImageSource(selected.source)
			window.contentPanel.passiveList:ensureChildVisible(widget)
		end
	end

	if window.contentPanel.passiveList:getChildren() then
		radio:selectWidget(window.contentPanel.passiveList:getChildren()[1])
		window.contentPanel.preview:setColor("$var-text-cip-color")
	end

	local okFunc = function(destroy)
		local selected = radio:getSelectedWidget()
		if not selected then return end

	  local barID, buttonID = string.match(button:getId(), "(.*)%.(.*)")
		Options.createOrUpdatePassive(tonumber(barID), tonumber(buttonID), tonumber(selected:getId()))
		updateButton(button)

		if destroy then
			g_client.setInputLockWidget(nil)
			window:destroy()
		end
	end

	local cancelFunc = function()
		g_client.setInputLockWidget(nil)
		window:destroy()
	end

	window.contentPanel.buttonOk.onClick = function() okFunc(true) end
	window.contentPanel.buttonApply.onClick = function() okFunc(false) end
	window.contentPanel.buttonClose.onClick = cancelFunc
	window.onEnter = function() okFunc(true) end
	window.onEscape = cancelFunc
	window:insertLuaCall('onEnter')

	local actionbar = button:getParent():getParent()
	if actionbar.locked then
		g_client.setInputLockWidget(nil)
		cancelFunc()
	end
end

function manageKeyPress(window, keyCode, keyboardModifiers, keyText)
	local keyCombo = determineKeyComboDesc(keyCode, keyboardModifiers, keyText)
	local resetCombo = {"Shift", "Ctrl", "Alt"}
    if table.contains(resetCombo, keyCombo) then
		window.display:setText('')
		window.warning:setVisible(false)
		window.buttonOk:setEnabled(true)
      	return true
    end

	local shortCut = (keyCombo == "HalfQuote" and "'" or keyCombo)
	window.display:setText(shortCut)
	window.display.combo = keyCombo
	window.warning:setVisible(false)
	window.buttonOk:setEnabled(true)
	if isHotkeyUsed(keyCombo) then
		window.warning:setVisible(true)
		window.warning:setText("This hotkey is already in use and will be overwritten.")
	end

	if table.contains(blockedKeys, keyCombo) then
		window.warning:setVisible(true)
		window.warning:setText("This hotkey is already in use and cannot be overwritten.")
		window.buttonOk:setEnabled(false)
	end
	return true
end

function clearButton(button, removeAction)
	local hotkey = button.cache.hotkey

	if button.cache.cooldownEvent then
	  removeEvent(button.cache.cooldownEvent)
	end

  	removeCooldown(button)
	resetButtonCache(button)

	-- Clear tier icon when button is cleared
	if button.item and ItemsDatabase and ItemsDatabase.setTier then
		ItemsDatabase.setTier(button.item, nil)
	end
	if button.item and ItemsDatabase and ItemsDatabase.setRarityItem then
		ItemsDatabase.setRarityItem(button.item, nil)
	end

	if hotkey then
		button.cache.hotkey = hotkey
		button.hotkeyLabel:setText(translateDisplayHotkey(button.cache.hotkey))
	end

	setupButtonTooltip(button, true)
	if removeAction then
		local barID, buttonID = string.match(button:getId(), "(.*)%.(.*)")
		Options.removeAction(tonumber(barID), tonumber(buttonID))
	end
end

function playerCanUseSpell(spellData)
	if not g_game.isOnline() then
		return
	end

	if not spellData then
		return false
	end

	if spellData.special and not spellModification[tostring(spellData.id)] then
		return false
	end

	if spellData.needLearn and not spellListData[tostring(spellData.id)] then
		return false
	end

	if spellData.mana and (player:getMana() < spellData.mana) then
		return false
	end

	if spellData.level and (player:getLevel() < spellData.level) then
		return false
	end

	if spellData.soul and (player:getSoul() < spellData.soul) then
		return false
	end

	if spellData.vocations and (not table.contains(spellData.vocations, translateVocation(player:getVocation()))) then
		return false
	end

	return true
end

function getItemNameById(itemId)
	for _, k in pairs(hotkeyItemList) do
		local item = k[1]
		if item:getId() == itemId then
			return k[2]
		end
	end
	return "this object"
end

function setupHotkeyButton(button)
	if not Options.currentHotkeySet then
		return
	end

	local currentSet = Options.isChatOnEnabled and Options.currentHotkeySet["chatOn"] or Options.currentHotkeySet["chatOff"]
	for _, data in pairs(currentSet) do
		if data["actionsetting"] then
			if data["actionsetting"]["action"] == "TriggerActionButton_" .. button:getId() then
				local keySequence = data["keysequence"]
				if keySequence and not string.empty(keySequence) then
					if not data["secondary"] then
						button.cache.hotkey = keySequence
					end

					g_keyboard.unbindKeyPress(keySequence, nil, gameRootPanel)
					g_keyboard.unbindKeyDown(keySequence, nil, gameRootPanel)
					g_keyboard.unbindKeyUp(keySequence, nil, gameRootPanel)

					g_keyboard.bindKeyPress(keySequence, function() onExecuteAction(button, true) end, gameRootPanel)
					g_keyboard.bindKeyDown(keySequence, function() onExecuteAction(button, false) end, gameRootPanel)
					g_keyboard.bindKeyUp(keySequence, function() onCheckKeyUp(button) end, gameRootPanel)
				end
			end
		end
	end
end

function isHotkeyUsed(key, secondary)
	if not secondary then
		secondary = false
	end

	if not key or not Options.currentHotkeySet then
		return false
	end

	local currentSet = Options.isChatOnEnabled and Options.currentHotkeySet["chatOn"] or Options.currentHotkeySet["chatOff"]
	for _, data in pairs(currentSet) do
		if data["actionsetting"] and data["keysequence"] then
			if secondary and data["secondary"] and data["keysequence"]:lower() == key:lower() then
				return true
			end

			if not secondary and not data["secondary"] and data["keysequence"]:lower() == key:lower() then
				return true
			end
		end
	end
	return false
end

function isHotkeyUsedByChat(key, chatType)
	if not key or not Options.currentHotkeySet then
		return false
	end
	local currentSet = Options.currentHotkeySet[chatType]
	for _, data in pairs(currentSet) do
		if data["actionsetting"] and data["keysequence"] then
			if data["keysequence"]:lower() == key:lower() then
				return true
			end
		end
	end
	return false
end

function getUsedHotkeyButton(key)
	for _, actionbar in pairs(activeActionBars) do
		for _, button in pairs(actionbar.tabBar:getChildren()) do
			local hotkey = button.cache.hotkey
			if hotkey and hotkey:lower() == key:lower() then
				return button
			end
		end
	end
	return nil
end

function switchChatMode(enabled)
	Options.setChatMode(enabled)
	KeyBinds:setupAndReset(Options.currentHotkeySetName, enabled and "chatOn" or "chatOff")

	for _, actionbar in pairs(activeActionBars) do
		for _, button in pairs(actionbar.tabBar:getChildren()) do
			if button.cache.hotkey ~= "" then
				g_keyboard.unbindKeyPress(button.cache.hotkey, nil, gameRootPanel)
				g_keyboard.unbindKeyDown(button.cache.hotkey, nil, gameRootPanel)
				button.cache.hotkey = nil
				button.hotkeyLabel:setText("")
			end
		end
	end

	-- insert new ones
	for _, actionbar in pairs(activeActionBars) do
		for _, button in pairs(actionbar.tabBar:getChildren()) do
			setupHotkeyButton(button)
			if button.cache.hotkey then
				button.hotkeyLabel:setText(translateDisplayHotkey(button.cache.hotkey))
			end
		end
	end
	m_settings.CustomHotkeys.createList(true)
end

function updateVisibleWidgets()
	for _, actionBar in pairs(actionBars) do
		if actionBar:isVisible() then
			local tabBar = actionBar.tabBar
			local children = tabBar:getChildren()
			local dimension = actionBar.isVertical and tabBar:getHeight() or tabBar:getWidth()
			local visibleCount = math.max(1, math.floor(dimension / 36))
			local firstIndex = actionBar.firstVisibleIndex or 1

			for i, button in ipairs(children) do
				if i >= firstIndex and i < firstIndex + visibleCount then
					button:setVisible(true)
					actionBar.lastVisibleIndex = i
				else
					button:setVisible(false)
				end
			end
		end
	end
end

local function getFirstVisibleButton(actionBar)
	for _, button in ipairs(actionBar.tabBar:getChildren()) do
		if button:isVisible() then
			return button
		end
	end
	return nil
end

local function getNextInvisibleChild(actionBar, firstIndex)
	for i, button in ipairs(actionBar.tabBar:getChildren()) do
		if i >= firstIndex and not button:isVisible() then
			return button
		end
	end
	return nil
end

local function getPrevInvisibleButton(actionBar)
	local lastButton = nil
	for _, button in ipairs(actionBar.tabBar:getChildren()) do
		if button:isVisible() then
			return lastButton
		end
		lastButton = button
	end
	return nil
end

local function getReverseChildren(widget)
	local children = widget:getChildren()
	local reversed = {}
	for i = #children, 1, -1 do
		table.insert(reversed, children[i])
	end
	return reversed
end

local function getLastVisibleButton(actionBar)
	for _, button in ipairs(getReverseChildren(actionBar.tabBar)) do
		if button:isVisible() then
			return button
		end
	end
	return nil
end

function moveActionButtons(widget)
	local dir = widget:getId()
	local actionBar = widget:getParent():getParent()
	local scroll = actionBar.actionScroll
	local tabBar = actionBar.tabBar
	local buttons = { actionBar.prevPanel.prev, actionBar.prevPanel.first, actionBar.nextPanel.next, actionBar.nextPanel.last }
	local children = tabBar:getChildren()
	local reverseChildren = getReverseChildren(tabBar)

	local dimension = actionBar.isVertical and tabBar:getHeight() or tabBar:getWidth()
	local visibleCount = math.max(1, math.floor(dimension / 36))

	if dir == "next" then
		local firstVisible = getFirstVisibleButton(actionBar)
		if not firstVisible then return end

		local firstIndex = tabBar:getChildIndex(firstVisible)
		local nextInvisible = getNextInvisibleChild(actionBar, firstIndex)

		if not nextInvisible then return end

		firstVisible:setVisible(false)
		nextInvisible:setVisible(true)
		scroll:increment(36)

		actionBar.firstVisibleIndex = tabBar:getChildIndex(firstVisible) + 1
		actionBar.lastVisibleIndex = tabBar:getChildIndex(nextInvisible)

	elseif dir == "prev" then
		local prevInvisible = getPrevInvisibleButton(actionBar)
		local lastVisible = getLastVisibleButton(actionBar)

		if not prevInvisible then return end

		prevInvisible:setVisible(true)
		lastVisible:setVisible(false)
		scroll:decrement(36)

		actionBar.firstVisibleIndex = tabBar:getChildIndex(prevInvisible)
		actionBar.lastVisibleIndex = tabBar:getChildIndex(lastVisible) - 1

	elseif dir == "first" then
		for i, button in ipairs(children) do
			button:setVisible(i <= visibleCount)
		end

		actionBar.firstVisibleIndex = 1
		actionBar.lastVisibleIndex = tabBar:getChildIndex(getLastVisibleButton(actionBar))
		scroll:setValue(scroll:getMinimum())

	elseif dir == "last" then
		for i, button in ipairs(reverseChildren) do
			button:setVisible(i <= visibleCount)
		end

		actionBar.firstVisibleIndex = tabBar:getChildIndex(getFirstVisibleButton(actionBar))
		actionBar.lastVisibleIndex = #children
		scroll:setValue(scroll:getMaximum())
	end

	local prevEnabled = actionBar.firstVisibleIndex ~= 1
	local nextEnabled = actionBar.lastVisibleIndex ~= #children

	buttons[1]:setOn(prevEnabled)
	buttons[2]:setOn(prevEnabled)
	buttons[3]:setOn(nextEnabled)
	buttons[4]:setOn(nextEnabled)
end

function changeLockStatus(button, barType)
	local barData = {
		["Bottom"] = {option = "actionBarBottomLocked", startPos = 1, endPos = 3},
		["Left"] = {option = "actionBarLeftLocked", startPos = 4, endPos = 6},
		["Right"] = {option = "actionBarRightLocked", startPos = 7, endPos = 9}
	}

	local data = barData[barType]
	if not data then
		return true
	end

	Options.clientOptions[data.option] = not Options.clientOptions[data.option]

	for i = data.startPos, data.endPos do
		actionBars[i].locked = not Options.actionBar[i].isLocked
		Options.actionBar[i].isLocked = not Options.actionBar[i].isLocked
	end

	if Options.clientOptions[data.option] then
		button:setIcon("/images/game/actionbar/locked")
	else
		button:setIcon("/images/game/actionbar/unlocked")
	end
end

function unbindActionBarEvent(actionbar)
	for _, button in pairs(actionbar.tabBar:getChildren()) do
		removeButtonEvents(button)
		resetButtonCache(button)
	end
end

function configureActionBar(barStr, visible)
	if not g_game.isOnline() then
		return
	end

	local bottom = string.find(barStr, "Bottom") ~= nil
	local left = string.find(barStr, "Left") ~= nil
	local right = string.find(barStr, "Right") ~= nil
	local actionNumber = tonumber(string.sub(barStr, -1))

	if bottom then
		local actionBar = actionBars[actionNumber]
		if not actionBar then
			return true
		end

		actionBar:setVisible(visible)
		actionBar:setOn(visible)
		Options.actionBar[actionNumber].isVisible = visible
		Options.clientOptions["actionBarShowBottom" .. actionNumber] = visible
		Options.actionBar[actionNumber].created = true
		resizeLockButtons()
		unbindActionBarEvent(actionBar)
		isLoaded = false
		setupActionBar(actionNumber)
		isLoaded = true

		if visible then
			table.insert(activeActionBars, actionBar)
		else
			for index, action in pairs(actionBars) do
				if action:getId() == actionBar:getId() then
					table.remove(activeActionBars, index)
				end
			end
		end
		updateGameMapPanelMargin()
		scheduleEvent(function() modules.game_actionbar.updateVisibleWidgets() end, 10)
		return
	end

	if left then
		local actionBar = actionBars[actionNumber + 3]
		if not actionBar then
			return true
		end

		actionBar:setVisible(visible)
		actionBar:setOn(visible)
		Options.actionBar[actionNumber + 3].isVisible = visible
		Options.clientOptions["actionBarShowLeft" .. actionNumber] = visible
		resizeLockButtons()
		unbindActionBarEvent(actionBar)
		isLoaded = false
		setupActionBar(actionNumber + 3)
		isLoaded = true

		if visible then
			table.insert(activeActionBars, actionBar)
		else
			for index, action in pairs(actionBars) do
				if action:getId() == actionBar:getId() then
					table.remove(activeActionBars, index)
				end
			end
		end
		scheduleEvent(function() modules.game_actionbar.updateVisibleWidgets() end, 10)
		return
	end

	if right then
		local actionBar = actionBars[actionNumber + 6]
		if not actionBar then
			return true
		end

		actionBar:setVisible(visible)
		actionBar:setOn(visible)
		Options.actionBar[actionNumber + 6].isVisible = visible
		Options.clientOptions["actionBarShowRight" .. actionNumber] = visible
		resizeLockButtons()
		unbindActionBarEvent(actionBar)
		isLoaded = false
		setupActionBar(actionNumber + 6)
		isLoaded = true

		if visible then
			table.insert(activeActionBars, actionBar)
		else
			for index, action in pairs(actionBars) do
				if action:getId() == actionBar:getId() then
					table.remove(activeActionBars, index)
				end
			end
		end
		scheduleEvent(function() modules.game_actionbar.updateVisibleWidgets() end, 10)
		return
	end
end

function resetActionBar()
	if not player then
		player = g_game.getLocalPlayer()
	end

	if dragButton and dragItem then
		resetDragWidget(dragItem, dragButton)
		dragItem = nil
		dragButton = nil
	end

	isLoaded = false
	for _, actionbar in pairs(activeActionBars) do
		for _, button in pairs(actionbar.tabBar:getChildren()) do
			if button.cache.hotkey then
				g_keyboard.unbindKeyPress(button.cache.hotkey, nil, gameRootPanel)
				g_keyboard.unbindKeyDown(button.cache.hotkey, nil, gameRootPanel)
				button.cache.hotkey = nil
				button.hotkeyLabel:setText("")
			end

			clearButton(button, false)
			resetButtonCache(button)
			updateButton(button)
		end
	end
	isLoaded = true
end

function resetSlots(slot)
	for _, actionbar in pairs(activeActionBars) do
		if actionbar:getId() == "actionbar." .. slot then
			for _, button in pairs(actionbar.tabBar:getChildren()) do
				if button.cache.hotkey then
					g_keyboard.unbindKeyPress(button.cache.hotkey, nil, gameRootPanel)
					g_keyboard.unbindKeyDown(button.cache.hotkey, nil, gameRootPanel)
					button.cache.hotkey = nil
					button.hotkeyLabel:setText("")
					Options.removeHotkey(button:getId())
				end

				clearButton(button, false)
				resetButtonCache(button)
			end
			break
		end
	end
end

function getButtonById(id)
	for _, actionbar in pairs(actionBars) do
		for _, button in pairs(actionbar.tabBar:getChildren()) do
			if button:getId() == id then
				return button
			end
		end
	end
	return nil
end

function onDragSpellLeave(mousePos, spellWords, actionButton)
	if not actionButton then
		return true
	end

	local destButton = getButtonById(actionButton:getParent():getId())
	if not destButton then
		return true
	end

	local actionbar = destButton:getParent():getParent()
	if actionbar.locked then
		return true
	end

	local destBarID, destButtonID = string.match(destButton:getId(), "(.*)%.(.*)")
	Options.createOrUpdateText(tonumber(destBarID), tonumber(destButtonID), spellWords, true)
	updateButton(destButton)
end

function updateVisibleOptions(option, state)
	for _, actionbar in pairs(activeActionBars) do
		local childs = actionbar.tabBar:getChildren()
		for _, button in pairs(childs) do
			if not button:isVisible() then
				goto continue
			end

			if option == "hotkey" then
				button.hotkeyLabel:setVisible(state)
			elseif option == "amount" then
				button.item:setShowCount(state)
			elseif option == "parameter" then
				button.parameterText:setVisible(state)
			end

			if option == "tooltip" then
				if not state then
					button.item:setTooltip("")
				else
					setupButtonTooltip(button, false)
				end
			end

			:: continue ::
		end
	end
end

function toggleCooldownOption()
	for _, actionbar in pairs(activeActionBars) do
		for _, button in pairs(actionbar.tabBar:getChildren()) do
			local cache = getButtonCache(button)
			if not (cache.isSpell or cache.isRuneSpell) then
				goto continue
			end

			button.cooldown:showTime(m_settings.getOption("cooldownSecond"))
			button.cooldown:showProgress(m_settings.getOption("graphicalCooldown"))
			:: continue ::
		end
	end
end

function onReleaseActionKeys()
	spellGroupPressed = {}
end

function isHotkeyGroupPressed(group)
	return spellGroupPressed[tostring(group)] ~= nil
end

function canEquipItem(item)
	if not item then
		return false
	end

	local clothSlot = item:getClothSlot()
	local classification = item:getClassification()
	local isAmmo = item:isAmmo()
	local smartCast = getSmartCast(item:getId())
	local hasWearout = item.hasWearout and item:hasWearout() or false
	local category = getActionbarItemCategory(item)
	local isMarketEquipable = isActionbarEquipCategory(category)
	local isServerEquipable = false
	if item.isEquipableByServerType then
		local ok, value = pcall(function() return item:isEquipableByServerType() end)
		isServerEquipable = ok and value or false
	elseif item.isEquipable then
		local ok, value = pcall(function() return item:isEquipable() end)
		isServerEquipable = ok and value or false
	end

	if item:isContainer() and not (isServerEquipable or isMarketEquipable or clothSlot > 0 or classification > 0 or isAmmo or hasWearout) then
		return false
	end

	if clothSlot > 0 or isServerEquipable or (clothSlot == 0 and hasWearout) then
		return true
	end

	if clothSlot == 0 and (classification > 0 or isAmmo or smartCast) then
		return true
	end

	if item.isChargeableByCategory then
		local ok, isChargeableByCategory = pcall(function() return item:isChargeableByCategory() end)
		if ok and isChargeableByCategory and not item:isMultiUse() then
			return true
		end
	end

	if isMarketEquipable then
		return true
	end

	local itemType = g_things.findItemTypeByClientId(item:getId())
	if itemType and itemType.getCategory then
		local ok, resolvedCategory = pcall(function() return itemType:getCategory() end)
		if ok then
			if resolvedCategory == ItemTypeCategory.Weapon or resolvedCategory == ItemTypeCategory.Ammunition or resolvedCategory == ItemTypeCategory.Armor then
				return true
			end
			if resolvedCategory == ItemTypeCategory.Charges and not item:isMultiUse() and not item:isUsable() then
				return true
			end
		end
	end

	local isChargeable = item.isChargeable and item:isChargeable() or (item.hasCharges and item:hasCharges())
	if clothSlot == 0 and isChargeable and not item:isMultiUse() and not item:isUsable() then
		return true
	end

	return false
end

function onSearchTextChange(widget, text)
	local window = widget:getParent():getParent()
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

function onClearSearchText(widget)
	local window = widget:getParent():getParent()
	local search = window:recursiveGetChildById('searchText')
  search:setText('')
end

function removeHotkey(name)
  local button = getUsedHotkeyButton(name)

  if not button then return end

  Options.removeHotkey(button:getId())
  g_keyboard.unbindKeyPress(name, nil, m_interface.getRootPanel())
  updateButton(button)
end

function updateButtonState(button)
	if not button then return end

	if not player then
		player = g_game.getLocalPlayer()
	end

	if not player then return end
	if not button.item then return end

	button:recursiveGetChildById('activeSpell'):setVisible(false)
	if button.cache.isSpell then
		setupButtonTooltip(button, false)
		button.item.text.gray:setVisible(not playerCanUseSpell(button.cache.spellData))

		local passiveSpell = player:getMonkPassive()
		local spellId = 0
		if passiveSpell == 1 then
			spellId = 274
		elseif passiveSpell == 2 then
			spellId = 275
		elseif passiveSpell == 3 then
			spellId = 276
		end

		button:recursiveGetChildById('activeSpell'):setVisible(button.cache.spellData.id == spellId)
	elseif button.cache.itemId ~= 0 then
		local smartId = getSmartCast(button.cache.itemId)
		local upgradeTier = button.cache.upgradeTier or 0
		local isItemEquiped = hasActionItemEquipped(button.cache.itemId, upgradeTier)
		local isSmartEquiped = smartId and hasActionItemEquipped(smartId, upgradeTier)
		local itemCount = getActionItemCount(button.cache.itemId, upgradeTier)
		if smartId then
			itemCount = itemCount + getActionItemCount(smartId, upgradeTier)
		end

		-- update checked (pressed)
		if button.cache.actionType == UseTypes["Equip"] and (not smartId or button.cache.smartMode) then
			button.item:setChecked((not hasPackedInventorySnapshot() or itemCount ~= 0) and (isItemEquiped or isSmartEquiped))
		end

		-- update shadow (disabled)
		button.item.gray:setVisible(hasPackedInventorySnapshot() and itemCount == 0)

		-- update item count
		button.item:setItemCount(itemCount);
		if button.item.setVirtualCount then
			button.item:setVirtualCount(itemCount > 1 and tostring(itemCount) or "")
		end

		-- update tooltip
		setupButtonTooltip(button, false)

		-- update item
		if button.cache.smartMode then
			local activeId = getActiveSmartCast(button.cache.itemId) or button.cache.itemId
			local inactiveId = getInactiveSmartCast(button.cache.itemId) or button.cache.itemId

			if hasActionItemEquipped(activeId, upgradeTier) then
				updateActionButtonItem(button, activeId, upgradeTier)
				button.cache.itemId = activeId
			else
				updateActionButtonItem(button, inactiveId, upgradeTier)
				button.cache.itemId = inactiveId

			end
		else
			updateActionButtonItem(button, button.cache.itemId, upgradeTier)
		end
	end

	refreshActionButtonRarity(button)
end
-- ============================================================
-- MULTI-ACTION SYSTEM (ported from mehah PR #1604)
-- ============================================================
multiPanel = nil
cacheMultiActionButtons = {}
multiActionCooldownEvents = {}

local function splitButtonId(button)
	return string.match(button:getId(), "(.*)%.(.*)")
end

local function localGetActionName(actionType)
	if type(actionType) == "string" then return actionType end
	return getActionName(actionType)
end

local function playerCanUseSpellLocal(spellData)
	if not g_game.isOnline() or not spellData then return false end
	if spellData.needLearn and not spellListData[tostring(spellData.id)] then return false end
	if spellData.mana and player and player:getMana() < spellData.mana then return false end
	if spellData.level and player and player:getLevel() < spellData.level then return false end
	if spellData.soul and player and player:getSoul() < spellData.soul then return false end
	if spellData.vocations and player and not table.contains(spellData.vocations, translateVocation(player:getVocation())) then return false end
	return true
end

local function getSpellCooldownRemaining(spellId)
	local cd = spellCooldownCache[spellId]
	if not cd then return 0 end
	local remaining = (cd.startTime + cd.exhaustion) - g_clock.millis()
	return remaining > 0 and remaining or 0
end

local function getSpellGroupCooldownRemaining(spellData)
	if not spellData or not spellData.group or not spellGroupCooldownCache then return 0 end
	local groupIds = Spells.getGroupIds and Spells.getGroupIds(spellData)
	if not groupIds then return 0 end
	local maxRemaining = 0
	local now = g_clock.millis()
	for _, groupId in pairs(groupIds) do
		local gc = spellGroupCooldownCache[groupId]
		if gc then
			local remaining = (gc.startTime + gc.exhaustion) - now
			if remaining > maxRemaining then maxRemaining = remaining end
		end
	end
	return maxRemaining > 0 and maxRemaining or 0
end

local function findNextAvailableAction(multiActions)
	if not multiActions or table.empty(multiActions) then return nil end
	local bestAction = nil
	local closestAction = nil
	local closestTime = math.huge
	local firstValid = nil

	for i, data in ipairs(multiActions) do
		if not data or table.empty(data) then goto continue end

		if data["chatText"] then
			local spellData = Spells.getSpellDataByParamWords(data["chatText"]:lower())
			if spellData then
				if not playerCanUseSpellLocal(spellData) then
					firstValid = firstValid or data
					goto continue
				end
				firstValid = firstValid or data
				local remaining = math.max(getSpellCooldownRemaining(spellData.id), getSpellGroupCooldownRemaining(spellData))
				if remaining <= 0 then bestAction = bestAction or data
				elseif remaining < closestTime then closestTime = remaining; closestAction = data end
			else
				firstValid = firstValid or data
				bestAction = bestAction or data
			end
		elseif data["useObject"] then
			local itemId = data["useObject"]
			local upgradeTier = data["upgradeTier"] or 0
			local itemCount = getActionItemCount(itemId, upgradeTier)
			firstValid = firstValid or data
			local runeData = Spells.getRuneSpellByItem and Spells.getRuneSpellByItem(itemId)
			if runeData and itemCount > 0 then
				local remaining = math.max(getSpellCooldownRemaining(runeData.id), getSpellGroupCooldownRemaining(runeData))
				if remaining <= 0 then bestAction = bestAction or data
				elseif remaining < closestTime then closestTime = remaining; closestAction = data end
			elseif itemCount > 0 then
				bestAction = bestAction or data
			end
		end
		::continue::
	end
	return bestAction or closestAction or firstValid
end

local function renderSlotOnWidget(widget, slotData, isMainButton)
	if not widget or not slotData or table.empty(slotData) then return end

	if slotData["useObject"] then
		if isMainButton then
			widget.cache.isSpell = false
			widget.cache.isRuneSpell = false
			widget.cache.spellID = 0
			widget.cache.spellData = nil
			widget.item.text:setImageSource("")
			widget.item.text:setText("")
		end
		widget.item:setItemId(slotData["useObject"], true)
		widget.item:setOn(true)
		widget.cache.itemId = slotData["useObject"]
		widget.cache.upgradeTier = slotData["upgradeTier"] or 0
		widget.cache.smartMode = slotData["useEquipSmartMode"] or false
		local useTypeName = localGetActionName(slotData["useType"]) or "Use"
		widget.cache.actionType = UseTypes[useTypeName] or UseTypes["Use"]
		local itemCount = getActionItemCount(widget.cache.itemId, widget.cache.upgradeTier)
		widget.item:setItemCount(itemCount)
		if widget.item.setVirtualCount then
			widget.item:setVirtualCount(itemCount > 1 and tostring(itemCount) or "")
		end
		updateActionButtonItem(widget, widget.cache.itemId, widget.cache.upgradeTier)
		if widget.cache.actionType == UseTypes["Equip"] then
			local equipped = hasActionItemEquipped(widget.cache.itemId, widget.cache.upgradeTier)
			widget.item:setChecked((not hasPackedInventorySnapshot() or itemCount ~= 0) and equipped)
		end
		local runeSpellData = Spells.getRuneSpellByItem and Spells.getRuneSpellByItem(widget.cache.itemId)
		if runeSpellData then
			widget.cache.isRuneSpell = true
			widget.cache.spellData = runeSpellData
		end
	elseif slotData["chatText"] then
		local previousItemId = widget.cache.itemId
		if previousItemId and previousItemId > 0 then
			local cachedItems = cachedItemWidget[previousItemId]
			if cachedItems then
				for index = #cachedItems, 1, -1 do
					if cachedItems[index] == widget then
						table.remove(cachedItems, index)
					end
				end
				if #cachedItems == 0 then
					cachedItemWidget[previousItemId] = nil
				end
			end
		end

		widget.cache.itemId = 0
		widget.cache.item = nil
		widget.cache.upgradeTier = 0
		widget.cache.smartMode = nil
		widget.cache.castParam = nil
		widget.item:setItem(nil)
		widget.item:setItemCount(0)
		if widget.item.setVirtualCount then
			widget.item:setVirtualCount("")
		end
		widget.item:setChecked(false)

		local spellData, param = Spells.getSpellDataByParamWords(slotData["chatText"]:lower())
		if spellData then
			local spellId = SpellIcons[spellData.icon] and SpellIcons[spellData.icon][1] or spellData.clientId
			if spellId and SpelllistSettings then
				local source = SpelllistSettings['Default'].iconsFolder
				local clip = Spells.getImageClipNormal(spellId, 'Default')
				widget.item.text:setText("")
				widget.item.text:setImageSource(source)
				widget.item.text:setImageClip(clip)
			end
			widget.cache.isSpell = true
			widget.cache.spellID = spellData.id
			widget.cache.spellData = spellData
			widget.cache.isRuneSpell = false
			if param then widget.cache.castParam = param:gsub('"', '') end
		else
			widget.cache.isSpell = false
			widget.cache.isRuneSpell = false
			widget.item.text:setImageSource("")
			widget.item.text:setText(slotData["chatText"]:sub(1, 15))
		end
		widget.item:setOn(true)
		widget.cache.param = slotData["chatText"]
		widget.cache.sendAutomatic = slotData["sendAutomatically"]
		widget.cache.actionType = UseTypes["chatText"]
	end
	setupButtonTooltip(widget, false)
	refreshActionButtonRarity(widget)
end

function updateMultiButtonState(button)
	if not button or not button.item or not player or not button.cache then return end
	if not button.cache.multiActions or not hasMultiActions(button.cache.multiActions) then
		return
	end
	local action = findNextAvailableAction(button.cache.multiActions)
	if not action then action = button.cache.multiActions[1] end
	if not action or table.empty(action) then return end

	if action["chatText"] and button.cache.param == action["chatText"] and button.cache.sendAutomatic == action["sendAutomatically"] and button.cache.actionType == UseTypes["chatText"] then return end
	if action["useObject"] and button.cache.itemId == action["useObject"] then
		local useTypeName = localGetActionName(action["useType"]) or "Use"
		if button.cache.actionType == (UseTypes[useTypeName] or UseTypes["Use"]) then return end
	end

	removeCooldown(button)
	renderSlotOnWidget(button, action, true)
	cacheMultiActionButtons[button] = true
end

function scheduleMultiActionCooldownEvent(button, eventKey, delay)
	if not button or not eventKey or not delay then return end
	local buttonId = button:getId()
	if not multiActionCooldownEvents[buttonId] then multiActionCooldownEvents[buttonId] = {} end
	if multiActionCooldownEvents[buttonId][eventKey] then removeEvent(multiActionCooldownEvents[buttonId][eventKey]) end
	multiActionCooldownEvents[buttonId][eventKey] = scheduleEvent(function()
		if button and not button:isDestroyed() then updateMultiButtonState(button) end
		if multiActionCooldownEvents[buttonId] then multiActionCooldownEvents[buttonId][eventKey] = nil end
	end, delay + 100)
end

function updateMultiPanelCooldowns()
	if not multiPanel or multiPanel:isDestroyed() then return end
	local refButton = multiPanel.button
	if not refButton or not refButton.cache or not refButton.cache.multiActions then return end

	for k = 1, 3 do
		local slotBtn = multiPanel:recursiveGetChildById("actionButton" .. k)
		if slotBtn and slotBtn.cooldown then
			local data = refButton.cache.multiActions[k]
			if data and not table.empty(data) then
				local remaining = 0
				if data.chatText then
					local spellData, param = Spells.getSpellDataByParamWords(data.chatText:lower())
					if spellData then
						remaining = math.max(getSpellCooldownRemaining(spellData.id), getSpellGroupCooldownRemaining(spellData))
					end
				elseif data.useObject then
					local itemId = data.useObject
					local runeData = Spells.getRuneSpellByItem and Spells.getRuneSpellByItem(itemId)
					if runeData then
						remaining = math.max(getSpellCooldownRemaining(runeData.id), getSpellGroupCooldownRemaining(runeData))
					end
				end

				if remaining > 0 then
					slotBtn.cooldown:showTime(m_settings.getOption("cooldownSecond"))
					slotBtn.cooldown:showProgress(m_settings.getOption("graphicalCooldown"))
					slotBtn.cooldown:setDuration(remaining)
					slotBtn.cooldown:start()
				else
					slotBtn.cooldown:stop()
					slotBtn.cooldown:setPercent(100)
					slotBtn.cooldown:setText("")
				end
			else
				slotBtn.cooldown:stop()
				slotBtn.cooldown:setPercent(100)
				slotBtn.cooldown:setText("")
			end
		end
	end
end

function getMultiActionLayout(barN)
	barN = tonumber(barN) or 1
	if barN >= 1 and barN <= 3 then return "BottomMultiAction"
	elseif barN >= 4 and barN <= 6 then return "LeftMultiAction"
	else return "RightMultiAction" end
end

function getMultiActionPosition(button)
	local actionbar = button:getParent():getParent()
	local barN = actionbar and actionbar.n or 1
	local pos = button:getPosition()
	local x, y = pos.x, pos.y
	if barN >= 1 and barN <= 3 then
		return topoint(string.format("%s %s", x - 20, y - 116))
	elseif barN >= 4 and barN <= 6 then
		return topoint(string.format("%s %s", x + 34, y - 29))
	else
		return topoint(string.format("%s %s", x - 116, y - 29))
	end
end

function closeCurrentMultiActionPanel()
	if multiPanel then
		removeEvent(multiPanel.cooldownCycleEvent)
		local refButton = multiPanel.button
		if refButton then
			refButton.onGeometryChange = nil
			refButton.onVisibilityChange = nil
			refButton.multiPanel = nil
		end
		if gameRootPanel then
			gameRootPanel.onMouseRelease = multiPanel.prevMouseReleaseHandler
		end
		if not multiPanel:isDestroyed() then multiPanel:destroy() end
		multiPanel = nil
	end
end

function assignMultiAction(button, skipPrefill)
	if not button then return end
	if not button.cache then getButtonCache(button) end
	local actionbar = button:getParent():getParent()
	local barN = actionbar and actionbar.n or 1

	if not multiPanel or multiPanel:isDestroyed() or multiPanel.button ~= button then
		if multiPanel and not multiPanel:isDestroyed() then
			removeEvent(multiPanel.cooldownCycleEvent)
			if multiPanel.button then
				multiPanel.button.onGeometryChange = nil
				multiPanel.button.onVisibilityChange = nil
				multiPanel.button.multiPanel = nil
			end
			if gameRootPanel then
				gameRootPanel.onMouseRelease = multiPanel.prevMouseReleaseHandler
			end
			multiPanel:destroy()
		end

		multiPanel = g_ui.createWidget(getMultiActionLayout(barN), gameRootPanel)
		button.multiPanel = multiPanel
		multiPanel.button = button

		local prevHandler = gameRootPanel.onMouseRelease
		multiPanel.prevMouseReleaseHandler = prevHandler
		gameRootPanel.onMouseRelease = function(self, mousePos, mouseButton)
			if mouseButton == MouseRightButton then
				if prevHandler then return prevHandler(self, mousePos, mouseButton) end
				return false
			end
			if multiPanel and not multiPanel:isDestroyed() and not multiPanel:containsPoint(mousePos) then
				closeCurrentMultiActionPanel()
			end
			if prevHandler then return prevHandler(self, mousePos, mouseButton) end
			return false
		end

		button.onGeometryChange = function()
			if not multiPanel or multiPanel:isDestroyed() then
				button.onGeometryChange = nil
				button.onVisibilityChange = nil
				return
			end
			multiPanel:setPosition(getMultiActionPosition(button))
		end
		button.onVisibilityChange = function()
			if not multiPanel or multiPanel:isDestroyed() then return end
			if not button:isVisible() then closeCurrentMultiActionPanel() end
		end
		multiPanel:setPosition(getMultiActionPosition(button))

		-- Start cooldown sync cycle
		removeEvent(multiPanel.cooldownCycleEvent)
		local function cycle()
			if not multiPanel or multiPanel:isDestroyed() then return end
			updateMultiPanelCooldowns()
			multiPanel.cooldownCycleEvent = scheduleEvent(cycle, 100)
		end
		cycle()
	end

	local cache = getButtonCache(button)
	if not cache.multiActions or table.empty(cache.multiActions) then
		cache.multiActions = {{}, {}, {}}
	end

	local barID, buttonID = splitButtonId(button)
	if not skipPrefill then
		local allEmpty = true
		for i = 1, 3 do
			if not table.empty(cache.multiActions[i] or {}) then allEmpty = false; break end
		end
		if allEmpty then
			if cache.param and cache.param ~= "" then
				cache.multiActions[1] = {chatText = cache.param, sendAutomatically = cache.sendAutomatic}
				clearSingleCache(button)
			elseif cache.itemId and cache.itemId > 100 then
				local useType = localGetActionName(cache.actionType) or "Use"
				cache.multiActions[1] = {useObject = cache.itemId, useType = useType, upgradeTier = cache.upgradeTier or 0, useEquipSmartMode = cache.smartMode or false}
				clearSingleCache(button)
			end
		end
	end

	for k = 1, 3 do
		local slotBtn = multiPanel:recursiveGetChildById("actionButton" .. k)
		if slotBtn then
			local data = cache.multiActions[k] or {}
			resetButtonCache(slotBtn)
			slotBtn.cache = getButtonCache(slotBtn)

			slotBtn.onMouseRelease = function(self, mousePos, mouseBtn)
				local current = cache.multiActions[k]
				if mouseBtn == MouseRightButton then
					local menu = g_ui.createWidget('PopupMenu')
					menu:setGameMenu(true)
					menu:addOption(tr('Assign Spell'), function() assignMultiActionSpell(button, k) end)
					if slotBtn.item and slotBtn.item:getItemId() > 100 then
						menu:addOption(tr('Edit Object'), function()
							assignMultiItem(button, k, slotBtn.item:getItemId(), 0, false)
						end)
					else
						menu:addOption(tr('Assign Object'), function() assignItemEvent(button, k) end)
					end
					local hasText = slotBtn.item and slotBtn.item.text and slotBtn.item.text:getText():len() > 0
					menu:addOption(hasText and tr('Edit Text') or tr('Assign Text'), function() assignMultiText(button, k) end)
					if current and not table.empty(current) then
						menu:addSeparator()
						menu:addOption(tr('Clear Action'), function()
							cache.multiActions[k] = {}
							if not hasMultiActions(cache.multiActions) then
								cache.multiActions = {{}, {}, {}}
								cacheMultiActionButtons[button] = nil
								closeCurrentMultiActionPanel()
								clearButton(button, false)
							else
								assignMultiAction(button, true)
								updateMultiButtonState(button)
							end
						end)
					end
					menu:display(mousePos)
				elseif mouseBtn == MouseLeftButton then
					if current and not table.empty(current) then
						executeMultiAction(button, current)
					end
				end
			end

			if not table.empty(data) then renderSlotOnWidget(slotBtn, data, false) end
		end
	end
end

function executeMultiAction(button, data)
	if not player or not data or not next(data) then return end
	if data.useObject then
		local at = UseTypes[data.useType] or UseTypes["Use"]
		if at == UseTypes["UseOnYourself"] then
			g_game.useInventoryItemWith(data.useObject, player)
		elseif at == UseTypes["UseOnTarget"] then
			local tgt = g_game.getAttackingCreature()
			if tgt then g_game.useInventoryItemWith(data.useObject, tgt) end
		elseif at == UseTypes["Equip"] then
			g_game.equipItemId(data.useObject, data.upgradeTier or 0)
		elseif at == UseTypes["SelectUseTarget"] then
			modules.game_interface.startUseWith(Item.create(data.useObject))
		else
			g_game.useInventoryItem(data.useObject)
		end
	elseif data.chatText then
		if data.sendAutomatically then
			g_game.talk(data.chatText)
		else
			modules.game_console.getConsole():setText(data.chatText)
			modules.game_console.getConsole():setCursorPos(#data.chatText)
		end
	end
end

function clearSingleCache(button)
	local cache = getButtonCache(button)
	cache.param = ""
	cache.sendAutomatic = false
	cache.itemId = 0
	cache.actionType = 0
	cache.upgradeTier = 0
	cache.smartMode = false
end

function assignMultiActionSpell(button, multiButtonIndex)
	if not button or not button.cache or not button.cache.multiActions then return end
	local slotData = button.cache.multiActions[multiButtonIndex]
	if slotData and not table.empty(slotData) then
		if slotData.chatText then
			button.cache.param = slotData.chatText
			button.cache.sendAutomatic = slotData.sendAutomatically or false
			local spellData, param = Spells.getSpellDataByParamWords(slotData.chatText:lower())
			if spellData then
				button.cache.spellData = spellData
				button.cache.isSpell = true
				button.cache.castParam = param and param:gsub('"', '') or ""
			end
		elseif slotData.useObject then
			button.cache.itemId = slotData.useObject
			button.cache.upgradeTier = slotData.upgradeTier or 0
			button.cache.actionType = UseTypes[slotData.useType] or UseTypes["Use"]
		end
	else
		button.cache.param = ""
		button.cache.sendAutomatic = false
		button.cache.spellData = nil
		button.cache.isSpell = false
		button.cache.castParam = ""
		button.cache.itemId = 0
	end
	assignSpell(button, multiButtonIndex)
end

function assignMultiText(button, multiButtonIndex)
	getButtonCache(button).multiSlotIndex = multiButtonIndex
	local slotData = button.cache.multiActions[multiButtonIndex]
	if slotData and not table.empty(slotData) and slotData.chatText then
		button.cache.param = slotData.chatText
		button.cache.sendAutomatic = slotData.sendAutomatically or false
	else
		button.cache.param = ""
		button.cache.sendAutomatic = false
	end
	assignText(button)
end

function assignMultiItem(button, multiButtonIndex, itemId, itemTier, dragEvent)
	getButtonCache(button).multiSlotIndex = multiButtonIndex
	assignItem(button, itemId, itemTier or 0, dragEvent)
end

function toggleMultiActionPanel(button)
	if multiPanel and not multiPanel:isDestroyed() and multiPanel.button == button then
		closeCurrentMultiActionPanel()
		return
	end
	assignMultiAction(button, false)
end

function handleMultiSlotSave(button)
	local cache = getButtonCache(button)
	if not cache.multiSlotIndex or cache.multiSlotIndex < 1 then return end
	local slotIdx = cache.multiSlotIndex
	if not cache.multiActions then cache.multiActions = {{}, {}, {}} end

	if cache.itemId and cache.itemId > 100 then
		cache.multiActions[slotIdx] = {
			useObject = cache.itemId,
			useType = localGetActionName(cache.actionType) or "Use",
			upgradeTier = cache.upgradeTier or 0,
			useEquipSmartMode = cache.smartMode or false,
		}
	elseif cache.param and cache.param ~= "" then
		cache.multiActions[slotIdx] = {
			chatText = cache.param,
			sendAutomatically = cache.sendAutomatic or false,
		}
	end

	cache.multiSlotIndex = 0
	if multiPanel and multiPanel.button == button then
		assignMultiAction(button, true)
	end
	updateMultiButtonState(button)
end
