-- chunkname: @/mods/game_proficiency/proficiency.lua

if not WeaponProficiency then
	WeaponProficiency = {}
	WeaponProficiency.__index = WeaponProficiency
	WeaponProficiency.window = nil
	WeaponProficiency.warningWindow = nil
	WeaponProficiency.displayItemPanel = nil
	WeaponProficiency.perkPanel = nil
	WeaponProficiency.bonusDetailPanel = nil
	WeaponProficiency.starProgressPanel = nil
	WeaponProficiency.optionFilter = nil
	WeaponProficiency.itemListScroll = nil
	WeaponProficiency.vocationWarning = nil
	WeaponProficiency.button = nil
	WeaponProficiency.resetButton = nil
	WeaponProficiency.applyButton = nil
	WeaponProficiency.okButton = nil
	WeaponProficiency.closeButton = nil
	WeaponProficiency.modifyButton = nil
	WeaponProficiency.modifyCost = nil
	WeaponProficiency.modifyCostText = nil
	WeaponProficiency.dustBalanceText = nil
	WeaponProficiency.progressDescription = nil
	WeaponProficiency.nextLevelDescription = nil
	WeaponProficiency.proficiencyProgress = nil
	WeaponProficiency.iconMasteryLevel = nil
	WeaponProficiency.itemMasteryLevel = nil
	WeaponProficiency.searchField = nil
	WeaponProficiency.infoWidget = nil
	WeaponProficiency.vocButton = nil
	WeaponProficiency.itemListWidget = nil
	WeaponProficiency.displayItemWidget = nil
	WeaponProficiency.itemNameTitle = nil
	WeaponProficiency.firstItemRequested = nil
	WeaponProficiency.selectedModifySlot = nil
	WeaponProficiency.selectedClientId = nil
	WeaponProficiency.selectedListEntry = nil
	WeaponProficiency.allProficiencyRequested = false
	WeaponProficiency.saveWeaponMissing = false
	WeaponProficiency.itemList = {}
	WeaponProficiency.cacheList = {}
	WeaponProficiency.maxDust = 0
	WeaponProficiency.dustIconChar = "\xA4"
	WeaponProficiency.orbIconChar = "\xA5"
	WeaponProficiency.ItemCategory = {
		FistWeapons = 27,
		WandsRods = 21,
		Swords = 20,
		DistanceWeapons = 19,
		Clubs = 18,
		Axes = 17
	}
	WeaponProficiency.perkPanelsName = {
		"oneBonusIconPanel",
		"twoBonusIconPanel",
		"threeBonusIconPanel"
	}
	WeaponProficiency.filters = {
		vocButton = false,
		twoButton = false,
		oneButton = false,
		levelButton = false
	}
	WeaponProficiency.listWidgetHeight = 36
	WeaponProficiency.listCapacity = 0
	WeaponProficiency.listMinWidgets = 0
	WeaponProficiency.listMaxWidgets = 0
	WeaponProficiency.offset = 0
	WeaponProficiency.listData = {}
	WeaponProficiency.scrollUpdateEvent = nil
	WeaponProficiency.pendingScrollUpdate = nil
end

local destroyProficiencyDynamicDialogs

local function onItemListScrollValueChange(list, value, delta)
	WeaponProficiency.pendingScrollUpdate = {
		list = list,
		value = value,
		delta = delta
	}

	if WeaponProficiency.scrollUpdateEvent then
		return
	end

	WeaponProficiency.scrollUpdateEvent = scheduleEvent(function()
		WeaponProficiency.scrollUpdateEvent = nil
		local pending = WeaponProficiency.pendingScrollUpdate
		WeaponProficiency.pendingScrollUpdate = nil

		if pending and pending.list and not pending.list:isDestroyed() then
			WeaponProficiency:onItemListValueChange(pending.list, pending.value, pending.delta)
		end
	end, 16)
end

local function onItemListChildFocusChange(_, child)
	if child then
		WeaponProficiency:onItemListFocusChange(child.cache)
	end
end

local function closeWindowDeferred()
	WeaponProficiency.closeWindowEvent = nil

	local window = WeaponProficiency.window
	if window and not window:isDestroyed() and window:isVisible() then
		WeaponProficiency:onCloseWindow(WeaponProficiency.closeButton)
	end
end

local function onPlayerStatesChange()
	local window = WeaponProficiency.window
	local itemId = WeaponProficiency.selectedClientId

	if window and itemId and not window:isHidden() then
		WeaponProficiency:onUpdateSelectedProficiency(itemId)
	end
end

local function applyProficiencyItemRarity(widget, displayItem)
	if not widget then
		return
	end

	local rarityWidget = widget.rarity or widget:getChildById("rarity")

	if not rarityWidget then
		return
	end

	if displayItem then
		if ItemsDatabase and ItemsDatabase.setRarityItem then
			ItemsDatabase.setRarityItem(rarityWidget, displayItem)
		end
		if ItemsDatabase and ItemsDatabase.syncRarityWidgetVisibility then
			ItemsDatabase.syncRarityWidgetVisibility(rarityWidget)
		else
			rarityWidget:setVisible(true)
		end
		if ItemsDatabase and ItemsDatabase.applyContainerRarityStackOrder then
			ItemsDatabase.applyContainerRarityStackOrder(widget)
		end
	else
		if ItemsDatabase and ItemsDatabase.setRarityItem then
			ItemsDatabase.setRarityItem(rarityWidget, nil)
		end
		rarityWidget:setVisible(false)
	end
end

function init()
	WeaponProficiency.window = g_ui.displayUI("weapon_proficiency")
	if not WeaponProficiency.window then
		logger.error("[Weapon Proficiency] Unable to load weapon_proficiency.otui")
		return
	end

	g_ui.importStyle("weapon_proficiency_modify")

	WeaponProficiency.displayItemPanel = WeaponProficiency.window:recursiveGetChildById("itemPanel")
	WeaponProficiency.perkPanel = WeaponProficiency.window:recursiveGetChildById("bonusProgressBackground")
	WeaponProficiency.bonusDetailPanel = WeaponProficiency.window:recursiveGetChildById("bonusDetailBackground")
	WeaponProficiency.optionFilter = WeaponProficiency.window:recursiveGetChildById("classFilter")
	WeaponProficiency.starProgressPanel = WeaponProficiency.window:recursiveGetChildById("starsPanelBackground")
	WeaponProficiency.itemListScroll = WeaponProficiency.window:recursiveGetChildById("itemListScroll")
	WeaponProficiency.vocationWarning = WeaponProficiency.window:recursiveGetChildById("vocationWarning")

	local win = WeaponProficiency.window

	WeaponProficiency.resetButton = win:getChildById("reset")
	WeaponProficiency.applyButton = win:getChildById("apply")
	WeaponProficiency.okButton = win:getChildById("ok")
	WeaponProficiency.closeButton = win:getChildById("close")
	WeaponProficiency.modifyButton = win:recursiveGetChildById("modifyButton")
	WeaponProficiency.modifyCost = win:recursiveGetChildById("modifyCost")
	WeaponProficiency.modifyCostText = win:recursiveGetChildById("modifyCostText")
	WeaponProficiency.dustBalanceText = win:recursiveGetChildById("dustBalanceText")
	WeaponProficiency.progressDescription = win:recursiveGetChildById("progressDescription")
	WeaponProficiency.nextLevelDescription = win:recursiveGetChildById("nextLevelDescription")
	WeaponProficiency.proficiencyProgress = win:recursiveGetChildById("proficiencyProgress")
	WeaponProficiency.iconMasteryLevel = win:recursiveGetChildById("iconMasteryLevel")
	WeaponProficiency.itemMasteryLevel = win:recursiveGetChildById("itemMasteryLevel")
	WeaponProficiency.searchField = win:recursiveGetChildById("searchText")
	WeaponProficiency.infoWidget = win:recursiveGetChildById("infoWidget")
	WeaponProficiency.vocButton = win:recursiveGetChildById("vocButton")
	WeaponProficiency.itemListWidget = win:recursiveGetChildById("itemList")
	WeaponProficiency.displayItemWidget = WeaponProficiency.displayItemPanel:getChildById("item")
	WeaponProficiency.itemNameTitle = WeaponProficiency.displayItemPanel:getChildById("itemNameTitle")
	WeaponProficiency.itemListScroll.onValueChange = onItemListScrollValueChange
	WeaponProficiency.itemListWidget.onChildFocusChange = onItemListChildFocusChange

	WeaponProficiency.window:hide()

	if ProficiencyData and ProficiencyData.loadProficiencyJsonContentOnly then
		ProficiencyData:loadProficiencyJsonContentOnly()
	end

	connect(g_game, {
		onInspection = onInspection,
		onLogin = loadProficiencyJson,
		onGameStart = onGameStart,
		onGameEnd = onGameEnd,
		onWeaponProficiencyCatalogItem = onWeaponProficiencyCatalogItem,
		onWeaponProficiencyCatalogReady = onWeaponProficiencyCatalogReady,
		onWeaponProficiency = onWeaponProficiency,
		onWeaponProficiencyReshape = onWeaponProficiencyReshape,
		onWeaponProficiencyExperience = onWeaponProficiencyExperience,
		onResourceBalance = onResourceBalance,
		-- event names of our engine (the Paulistinha module listened to onItemClasses/onOpenExaltationForge,
		-- which protocolgameparse never emits - hence the dust limit stuck at 0)
		forgeData = onItemClasses,
		onOpenForge = onOpenExaltationForge
	})
	connect(g_things, {
		onLoadDat = loadProficiencyJson
	})
	connect(LocalPlayer, {
		onStatesChange = onPlayerStatesChange
	})
end

function terminate()
	if WeaponProficiency.closeWindowEvent then
		removeEvent(WeaponProficiency.closeWindowEvent)
		WeaponProficiency.closeWindowEvent = nil
	end

	if WeaponProficiency.scrollUpdateEvent then
		removeEvent(WeaponProficiency.scrollUpdateEvent)
		WeaponProficiency.scrollUpdateEvent = nil
	end
	WeaponProficiency.pendingScrollUpdate = nil

	disconnect(g_game, {
		onInspection = onInspection,
		onLogin = loadProficiencyJson,
		onGameStart = onGameStart,
		onGameEnd = onGameEnd,
		onWeaponProficiencyCatalogItem = onWeaponProficiencyCatalogItem,
		onWeaponProficiencyCatalogReady = onWeaponProficiencyCatalogReady,
		onWeaponProficiency = onWeaponProficiency,
		onWeaponProficiencyReshape = onWeaponProficiencyReshape,
		onWeaponProficiencyExperience = onWeaponProficiencyExperience,
		onResourceBalance = onResourceBalance,
		-- event names of our engine (the Paulistinha module listened to onItemClasses/onOpenExaltationForge,
		-- which protocolgameparse never emits - hence the dust limit stuck at 0)
		forgeData = onItemClasses,
		onOpenForge = onOpenExaltationForge
	})
	disconnect(g_things, {
		onLoadDat = loadProficiencyJson
	})
	disconnect(LocalPlayer, {
		onStatesChange = onPlayerStatesChange
	})

	if destroyProficiencyDynamicDialogs then
		destroyProficiencyDynamicDialogs()
	end

	if WeaponProficiency.button and not WeaponProficiency.button:isDestroyed() then
		WeaponProficiency.button:destroy()
	end

	local window = WeaponProficiency.window
	if window and not window:isDestroyed() then
		if g_modalManager then
			g_modalManager.hide(window)
		end
		window:destroy()
	end

	for _, field in ipairs({
		"window", "warningWindow", "displayItemPanel", "perkPanel", "bonusDetailPanel",
		"starProgressPanel", "optionFilter", "itemListScroll", "vocationWarning", "button",
		"resetButton", "applyButton", "okButton", "closeButton", "modifyButton", "modifyCost",
		"modifyCostText", "dustBalanceText", "progressDescription", "nextLevelDescription",
		"proficiencyProgress", "iconMasteryLevel", "itemMasteryLevel", "searchField", "infoWidget",
		"vocButton", "itemListWidget", "displayItemWidget", "itemNameTitle"
	}) do
		WeaponProficiency[field] = nil
	end
end

local function ensureProficiencyShortcutHighlightWidget()
	local btn = WeaponProficiency.button

	if not btn or btn:isDestroyed() then
		return
	end

	if btn:recursiveGetChildById("proficiencyShortcutHighlight") then
		return
	end

	local h = g_ui.createWidget("UIWidget", btn)

	if not h then
		return
	end

	h:setId("proficiencyShortcutHighlight")
	h:setSize({
		width = 22,
		height = 22
	})
	h:setPhantom(true)
	h:setClipping(false)
	h:setImageSource("/images/animations/button-highlight-22x22")
	h:breakAnchors()
	h:addAnchor(AnchorHorizontalCenter, "parent", AnchorHorizontalCenter)
	h:addAnchor(AnchorVerticalCenter, "parent", AnchorVerticalCenter)

	if StatsBar and StatsBar.resyncProficiencyPerkHighlightWidgets then
		StatsBar.resyncProficiencyPerkHighlightWidgets()
	end
end

function onGameStart()
	WeaponProficiency.allProficiencyRequested = false
	WeaponProficiency.saveWeaponMissing = false
	WeaponProficiency.firstItemRequested = nil

	loadProficiencyJson()

	WeaponProficiency.button = modules.game_mainpanel.addToggleButton("ProciencyButton", tr("Open Weapon Proficiency"), "/images/options/button_weapon_proficiency", function()
		requestOpenWindow()
	end, false, 10, "WeaponProficiencyMainToggleButton")

	ensureProficiencyShortcutHighlightWidget()

	if StatsBar and StatsBar.applyDefaultTopProficiencyLayout then
		StatsBar.applyDefaultTopProficiencyLayout()
	end
end

local PROFICIENCY_DYNAMIC_DIALOG_IDS = {
	"shapeDialog",
	"reshapeDialog",
	"perkShapingOptionsDialog",
	"saveConfirmDialog",
	"refineConfirmDialog",
	"maximiseConfirmDialog",
	"clearConfirmDialog",
	"reshapeConfirmDialog",
	"reshapeReplaceConfirmDialog",
	"modifyConfirmDialog"
}

destroyProficiencyDynamicDialogs = function()
	local root = g_ui.getRootWidget()

	if not root then
		return
	end

	for _, dialogId in ipairs(PROFICIENCY_DYNAMIC_DIALOG_IDS) do
		local dlg = root:recursiveGetChildById(dialogId)

		if dlg then
			if g_modalManager then
				g_modalManager.hide(dlg)
			end

			dlg:destroy()
		end
	end
end

function onGameEnd()
	hide()
	destroyProficiencyDynamicDialogs()

	WeaponProficiency.warningWindow = nil
	WeaponProficiency.reshapeData = nil

	WeaponProficiency:invalidateShapingOptionsCache()
	WeaponProficiency:reset()
end

function loadProficiencyJson()
	local loaded, loadError = ProficiencyData:loadProficiencyJson()

	if not loaded then
		g_logger.error("[Weapon Proficiency] Unable to build item cache: " .. tostring(loadError))
	elseif StatsBar and StatsBar.applyDefaultTopProficiencyLayout then
		StatsBar.applyDefaultTopProficiencyLayout()
	end
end

function show()
	if not WeaponProficiency.window then
		return
	end

	WeaponProficiency.window:show(true)
	WeaponProficiency.window:raise()
	WeaponProficiency.window:focus()

	if g_modalManager then
		g_modalManager.show(WeaponProficiency.window)
	end

	WeaponProficiency:updateModifyButtonState()
	WeaponProficiency:updateDustBalance()
	WeaponProficiency:updateModifyCost()
end

function hide()
	if g_modalManager then
		g_modalManager.hide(WeaponProficiency.window)
	end

	WeaponProficiency.window:hide()
end

function isAvailable()
	return WeaponProficiency.window ~= nil
end

function getUnknownMarketCategory(itemOrType)
	local thingType = itemOrType

	if itemOrType.getThingType then
		thingType = itemOrType:getThingType()
	end

	if thingType then
		local marketData = thingType:getMarketData()

		if marketData and WeaponCategoryToString[marketData.category] then
			return marketData.category
		end
	end

	local weaponType = itemOrType.getWeaponType and itemOrType:getWeaponType()
		or (thingType and thingType.getWeaponType and thingType:getWeaponType())
	local categoryByWeaponType = {
		[WEAPON_SWORD] = MarketCategory.Swords,
		[WEAPON_AXE] = MarketCategory.Axes,
		[WEAPON_CLUB] = MarketCategory.Clubs,
		[WEAPON_FIST] = MarketCategory.FistWeapons,
		[WEAPON_BOW] = MarketCategory.DistanceWeapons,
		[WEAPON_CROSSBOW] = MarketCategory.DistanceWeapons,
		[WEAPON_THROW] = MarketCategory.DistanceWeapons,
		[WEAPON_WANDROD] = MarketCategory.WandsRods
	}

	if categoryByWeaponType[weaponType] then
		return categoryByWeaponType[weaponType]
	end

	return MarketCategory.WeaponsAll
end

function sortWeaponProficiency(marketCategory)
	local itemList = WeaponProficiency.itemList[marketCategory]

	if not itemList then
		return false
	end

	local cacheList = WeaponProficiency.cacheList

	for _, entry in ipairs(itemList) do
		local c = cacheList[ProficiencyData:getServerClientId(entry)]

		entry._sortExp = c and c.exp or 0
	end

	table.sort(itemList, function(a, b)
		if a._sortExp ~= b._sortExp then
			return a._sortExp > b._sortExp
		end

		return (a.marketData._nameLower or a.marketData.name:lower()) < (b.marketData._nameLower or b.marketData.name:lower())
	end)

	return true
end

function WeaponProficiency:getSelectedClientId()
	return self.selectedClientId or 0
end

function requestOpenWindow(redirectItem)
	local category = "Weapons: All"
	local targetItemId
	local leftSlotItem = modules.game_inventory.getWeaponProficiencyHandItem()

	if leftSlotItem then
		category = WeaponCategoryToString[getUnknownMarketCategory(leftSlotItem)]
		targetItemId = leftSlotItem:getId()
	end

	if redirectItem then
		category = WeaponCategoryToString[getUnknownMarketCategory(redirectItem)]
		targetItemId = redirectItem:getId()
	end

	if WeaponProficiency.firstItemRequested then
		category = WeaponCategoryToString[getUnknownMarketCategory(WeaponProficiency.firstItemRequested)]
		targetItemId = WeaponProficiency.firstItemRequested:getId()
		WeaponProficiency.firstItemRequested = nil
	end

	if not WeaponProficiency.allProficiencyRequested then
		g_game.sendWeaponProficiencyAction(1)

		WeaponProficiency.allProficiencyRequested = true
	end

	local focusFirstChild = false
	local focusVocation = category ~= "Weapons: All"

	if not focusVocation then
		focusFirstChild = true

		sortWeaponProficiency(MarketCategory.WeaponsAll)
	end

	WeaponProficiency.filters.vocButton = focusVocation
	WeaponProficiency.pendingCategory = category
	WeaponProficiency.pendingTargetItemId = targetItemId

	WeaponProficiency.vocButton:setChecked(focusVocation, true)
	WeaponProficiency:onClearSearch(true)
	show()

	if WeaponProficiency.catalogReady then
		WeaponProficiency:onWeaponCategoryChange(category, nil, targetItemId, focusFirstChild)
	end
end

function onWeaponProficiencyCatalogItem(itemId, marketCategory, proficiencyId, name)
	WeaponProficiency:addCatalogItem(itemId, marketCategory, proficiencyId, name)
end

function onWeaponProficiencyCatalogReady()
	WeaponProficiency.catalogReady = true
	if not WeaponProficiency.window or WeaponProficiency.window:isHidden() then
		return
	end
	local category = WeaponProficiency.pendingCategory or "Weapons: All"
	local targetItemId = WeaponProficiency.pendingTargetItemId
	WeaponProficiency:onWeaponCategoryChange(category, nil, targetItemId, true)
end

function onInspection(inspectType, itemName, item, descriptions)
	if inspectType ~= InspectionResponseTypes.Proficiency then
		return
	end

	if not WeaponProficiency.window or WeaponProficiency.window:isHidden() then
		return
	end

	local infoWidget = WeaponProficiency.infoWidget

	if not infoWidget then
		return
	end

	local text = itemName or ""

	for _, data in pairs(descriptions or {}) do
		if type(data) == "table" then
			local detail = data.detail or data[1] or ""
			local description = data.description or data[2] or ""

			text = text .. string.format("\n%s: %s", tostring(detail), wrapTextByWords(tostring(description), 52))
		end
	end

	infoWidget:setTooltip(text)

	local displayWidget = WeaponProficiency.displayItemWidget

	if displayWidget and item and item:getId() > 0 then
		displayWidget:setItem(item)
	end
end

local STAR_IMAGE_GOLD = "/images/game/proficiency/icon-star-tiny-gold"
local STAR_IMAGE_SILVER = "/images/game/proficiency/icon-star-tiny-silver"

local function updateStarsForWidget(starPanel, weaponLevel, starImage)
	if starPanel._lastStarCount == weaponLevel and starPanel._lastStarImage == starImage then
		return
	end

	starPanel._lastStarCount = weaponLevel
	starPanel._lastStarImage = starImage

	if weaponLevel <= 0 then
		starPanel:destroyChildren()

		return
	end

	local children = starPanel:getChildren()
	local currentCount = #children

	if currentCount < weaponLevel then
		for i = currentCount + 1, weaponLevel do
			g_ui.createWidget("MiniStar", starPanel)
		end
	elseif weaponLevel < currentCount then
		local ch = starPanel:getChildren()

		for i = #ch, weaponLevel + 1, -1 do
			ch[i]:destroy()
		end
	end

	for _, star in pairs(starPanel:getChildren()) do
		if star:getImageSource() ~= starImage then
			star:setImageSource(starImage)
		end
	end
end

function onWeaponProficiency(itemId, experience, perks, marketCategory, modifiers)
	WeaponProficiency.cacheList[itemId] = {
		exp = experience,
		perks = perks,
		modifiers = modifiers or {}
	}

	sortWeaponProficiency(marketCategory)
	WeaponProficiency:onUpdateSelectedProficiency(itemId)

	local root = g_ui.getRootWidget()
	local shape = root and root:recursiveGetChildById("shapeDialog")

	if shape then
		WeaponProficiency:updateShapePerkPreview(shape)
		WeaponProficiency:updateShapeResourceBalances()
	end

	if not WeaponProficiency.window or WeaponProficiency.window:isHidden() then
		return
	end

	local itemListWidget = WeaponProficiency.itemListWidget

	if not itemListWidget then
		return
	end

	local cacheEntry = WeaponProficiency.cacheList[itemId]
	local exp = cacheEntry and cacheEntry.exp or 0

	for _, widget in pairs(itemListWidget:getChildren()) do
		if not widget:isVisible() or not widget.cache or ProficiencyData:getServerClientId(widget.cache) ~= itemId then
			-- block empty
		else
			local displayItem = widget.cache.displayItem
			local profId = ProficiencyData:getEntryProficiencyId(widget.cache)
			local weaponLevel = ProficiencyData:getCurrentLevelByExp(displayItem, exp)
			local starPanel = widget:getChildById("starsBackground")
			local maxExperience = ProficiencyData:getMaxExperience(ProficiencyData:getPerkLaneCount(profId), displayItem)
			local starImage = maxExperience <= exp and STAR_IMAGE_GOLD or STAR_IMAGE_SILVER

			updateStarsForWidget(starPanel, weaponLevel, starImage)
		end
	end
end

function onWeaponProficiencyReshape(itemId, grade, slot, options)
	WeaponProficiency.reshapeData = {
		itemId = itemId,
		grade = grade,
		slot = slot,
		options = options or {}
	}

	WeaponProficiency:openReshapeDialog()
end

function onProficiencyNotification(itemId, experience, hasHighlight, thingType)
	local itemCache = WeaponProficiency.cacheList[itemId]

	if not itemCache then
		WeaponProficiency.cacheList[itemId] = {
			exp = experience,
			perks = {},
			modifiers = {}
		}
	elseif experience > 0 then
		itemCache.exp = experience
	end

	if thingType then
		sortWeaponProficiency(thingType:getMarketData().category)
	end

	local hand = modules.game_inventory.getWeaponProficiencyHandItem()

	if not hand or hand:getId() ~= itemId then
		return
	end

	if modules.game_topbar and modules.game_topbar.onUpdateProficiencyData then
		modules.game_topbar.onUpdateProficiencyData(WeaponProficiency.cacheList[itemId], hasHighlight, thingType)
	end
end

function onWeaponProficiencyExperience(itemId, experience, hasHighlight)
	local thingType = g_things.getThingType(itemId, ThingCategoryItem)
	onProficiencyNotification(itemId, experience, hasHighlight, thingType)
end

function onResourceBalance(type, value)
	if type == ResourceTypes.FORGE_DUST then
		WeaponProficiency:updateDustBalance()
		WeaponProficiency:updateModifyCost()
		WeaponProficiency:updateModifyButtonState()
		WeaponProficiency:updateShapeResourceBalances()
	elseif type == ResourceTypes.PROFICIENCY_DUST_LIMIT then
		WeaponProficiency.maxDust = math.max(0, tonumber(value) or 0)
		WeaponProficiency:updateDustBalance()
		WeaponProficiency:updateShapeResourceBalances()
	elseif type == ResourceTypes.LUNAR_ASCENSION_ORBS then
		WeaponProficiency:updateShapeResourceBalances()
	end
end

-- dust limit = 100 + (level above 100) * 20, the same way the forge and the maxDustCap parser compute it
local function setMaxDustFromLevel(fullDustLevel)
	if not fullDustLevel then
		return
	end

	WeaponProficiency.maxDust = 100 + math.max(0, fullDustLevel - 100) * 20

	WeaponProficiency:updateDustBalance()
end

-- our engine emits "forgeData" with a flat ForgeConfigData (maxDustLevel = already the full level,
-- parseItemClasses does 100 + byte), not "onItemClasses" with a nested data.config.maxDust
function onItemClasses(cfg)
	if cfg then
		setMaxDustFromLevel(cfg.maxDustLevel or (cfg.config and cfg.config.maxDust and cfg.config.maxDust + 100))
	end
end

-- the engine emits "onOpenForge"; 0x87 carries the FULL dust level (0x86 carries level-100)
function onOpenExaltationForge(data)
	if data then
		setMaxDustFromLevel(data.dustLevel)
	end
end

local function canChangeWeaponPerks()
	local player = g_game.getLocalPlayer()

	if not player or not g_game.isOnline() then
		return false
	end

	return player:isInProtectionZone()
end

local function isMasteryAchieved(entry)
	if not entry then
		return false
	end

	local clientId = ProficiencyData:getServerClientId(entry)
	local profId = ProficiencyData:getEntryProficiencyId(entry)
	local displayItem = entry.displayItem
	local maxExperience = ProficiencyData:getMaxExperience(ProficiencyData:getPerkLaneCount(profId), displayItem)
	local weaponEntry = WeaponProficiency.cacheList[clientId]
	local currentExperience = weaponEntry and weaponEntry.exp or 0

	return maxExperience <= currentExperience
end

local function getModifierEntry(modifiers, grade, slot)
	if not modifiers or type(modifiers) ~= "table" then
		return nil
	end

	for _, modifier in ipairs(modifiers) do
		if modifier.grade == grade and modifier.slot == slot then
			return modifier
		end
	end

	return nil
end

local function getModifiedPerkData(modifiers, grade, slot)
	local modifier = getModifierEntry(modifiers, grade, slot)

	if not modifier then
		return nil
	end

	return ProficiencyData:getModifierPerkData(modifier.modifierEnum, modifier.refineLevel)
end

local function updateManipulateRankWidget(bonusIcon, modifierEntry, isActive)
	local rankWidget = bonusIcon:getChildById("manipulateRank")

	if not rankWidget then
		return
	end

	if not modifierEntry then
		rankWidget:setVisible(false)

		return
	end

	rankWidget:setVisible(true)

	local imageSource = isActive and "/images/game/proficiency/backdrop_manipulation_rank" or "/images/game/proficiency/backdrop_manipulation_rank_disabled"

	if rankWidget:getImageSource() ~= imageSource then
		rankWidget:setImageSource(imageSource)
	end

	local rankValue = rankWidget:getChildById("rankValue")

	if rankValue then
		rankValue:setText(tostring(modifierEntry.refineLevel or 0))
	end
end

local function applyBonusIconVisualState(bonusIcon)
	local showColor = bonusIcon.active == true
	local icon = bonusIcon:getChildById("icon")
	local iconGrey = bonusIcon:getChildById("icon-grey")

	if icon then
		icon:setVisible(showColor)
	end

	if iconGrey then
		iconGrey:setVisible(not showColor)
	end

	local iconPerks = bonusIcon:getChildById("iconPerks")
	local iconPerksGrey = bonusIcon:getChildById("iconPerks-grey")
	local showPerkOverlay = bonusIcon.hasPerkOverlay == true

	if iconPerks then
		iconPerks:setVisible(showPerkOverlay and showColor)
	end

	if iconPerksGrey then
		iconPerksGrey:setVisible(showPerkOverlay and not showColor)
	end
end

local function getBonusIconModifierEntry(bonusIcon)
	local itemId = WeaponProficiency:getSelectedClientId()
	local cacheEntry = itemId > 0 and WeaponProficiency.cacheList[itemId] or nil
	local modifiers = cacheEntry and cacheEntry.modifiers or {}

	return getModifierEntry(modifiers, bonusIcon.grade, bonusIcon.slot)
end

local function refreshBonusDescription(hightLightWidget, bonusDescWidget, bonusTooltip, isModified)
	if hightLightWidget then
		hightLightWidget:setImageSource(string.format("/images/game/proficiency/%s", isModified and "backdrop_weaponmastery_manipulate_highlight" or "backdrop_weaponmastery_highlight"))
	end

	if not bonusDescWidget then
		return
	end

	bonusDescWidget:setImageSource("")
	bonusDescWidget:setText(bonusTooltip)

	if bonusDescWidget:getWrappedLinesCount() > 4 then
		bonusDescWidget:setText(short_text(bonusTooltip, 57))
		bonusDescWidget:setTooltip(bonusTooltip)
	else
		bonusDescWidget:removeTooltip()
	end
end

local function enableBonusIcon(bonusIcon, hightLightWidget, borderWidget, bonusDescWidget, bonusTooltip, perkData, isModified)
	if bonusIcon.blocked or bonusIcon.locked then
		return true
	end

	if bonusIcon.active then
		refreshBonusDescription(hightLightWidget, bonusDescWidget, bonusTooltip, isModified)

		return true
	end

	hightLightWidget:setVisible(true)
	borderWidget:setImageSource("/images/game/proficiency/border-weaponmasterytreeicons-active")
	refreshBonusDescription(hightLightWidget, bonusDescWidget, bonusTooltip, isModified)

	bonusIcon.active = true

	applyBonusIconVisualState(bonusIcon)
end

local function disableBonusIcon(bonusIcon, hightLightWidget, borderWidget, bonusDescWidget, perkData)
	hightLightWidget:setVisible(false)
	borderWidget:setImageSource("/images/game/proficiency/border-weaponmasterytreeicons-inactive")
	bonusDescWidget:setImageSource("/images/game/proficiency/icon-lock-grey")
	bonusDescWidget:setText("")
	bonusDescWidget:removeTooltip()
	applyBonusIconVisualState(bonusIcon)
end

local function disableOtherBonusIcons(currentPerkPanel, currentBonusIcon)
	for i = 0, 2 do
		local bonusIcon = currentPerkPanel:getChildById("bonusIcon" .. i)

		if bonusIcon and bonusIcon ~= currentBonusIcon and bonusIcon.active then
			bonusIcon.blocked = false
			bonusIcon.active = false

			local hightLightWidget = bonusIcon:getChildById("highlight")
			local borderWidget = bonusIcon:getChildById("border")

			hightLightWidget:setVisible(false)
			borderWidget:setImageSource("/images/game/proficiency/border-weaponmasterytreeicons-inactive")
			applyBonusIconVisualState(bonusIcon)
			updateManipulateRankWidget(bonusIcon, getBonusIconModifierEntry(bonusIcon), false)
		end
	end
end

local function updatePercentWidgets(child, currentExperience, _index, itemType)
	if not child then
		return
	end

	local percentWidget = child:getChildById("bonusSelectProgress")
	local starWidget = WeaponProficiency.starProgressPanel:getChildById("starWidget" .. _index)
	local starProgress = starWidget:getChildById("starProgress")
	local percent = ProficiencyData:getLevelPercent(currentExperience, _index, itemType)
	local maxLevelExperience = ProficiencyData:getMaxExperienceByLevel(_index, itemType)

	percentWidget:setPercent(percent)
	starProgress:setPercent(percent)
	starProgress:setTooltip(string.format("%s / %s", comma_value(currentExperience), comma_value(maxLevelExperience)))

	if percent >= 100 then
		local iconTypo = isMasteryAchieved(WeaponProficiency.selectedListEntry) and "gold" or "silver"

		starWidget:getChildById("star"):setImageSource(string.format("/images/icons/icon-star-%s", iconTypo))

		for _, widget in pairs(child.currentPerkPanel:getChildren()) do
			widget.blocked = false
		end
	end
end

local function buildSortContext()
	local player = g_game.getLocalPlayer()

	if not player then
		return nil
	end

	local playerVocation = translateWheelVocation(player:getVocation())
	local demotedVoc = playerVocation > 10 and playerVocation - 10 or playerVocation

	return {
		playerLevel = player:getLevel(),
		vocBitMask = Bit.bit(demotedVoc)
	}
end

local function checkSortOptions(itemData, ctx)
	if not ctx then
		return false
	end

	if WeaponProficiency.filters.levelButton and itemData.marketData.requiredLevel > ctx.playerLevel then
		return false
	end

	if WeaponProficiency.filters.vocButton then
		local itemVocation = itemData.marketData.restrictVocation

		if itemVocation > 0 and not Bit.hasBit(itemVocation, ctx.vocBitMask) then
			return false
		end
	end

	if WeaponProficiency.filters.oneButton and itemData.thingType:getClothSlot() ~= 6 then
		return false
	end

	if WeaponProficiency.filters.twoButton and itemData.thingType:getClothSlot() ~= 0 then
		return false
	end

	return true
end

local function setupPerkIconOverlay(perkData, bonusIcon)
	local augmentIconNormal = bonusIcon and bonusIcon:getChildById("iconPerks")
	local augmentIconGrey = bonusIcon and bonusIcon:getChildById("iconPerks-grey")
	local hasPerkOverlay = perkData.Type == PERK_SPELL_AUGMENT

	bonusIcon.hasPerkOverlay = hasPerkOverlay

	if hasPerkOverlay then
		local clip = ProficiencyData:getAugmentIconClip(perkData)

		for _, augmentIcon in ipairs({
			augmentIconNormal,
			augmentIconGrey
		}) do
			if augmentIcon then
				augmentIcon:setImageSource(SKILLWHEEL_SMALLPERKS_PATH)
				augmentIcon:setImageClip(clip)
			end
		end
	end

	local showColor = bonusIcon.active ~= false

	if augmentIconNormal then
		augmentIconNormal:setVisible(hasPerkOverlay and showColor)
	end

	if augmentIconGrey then
		augmentIconGrey:setVisible(hasPerkOverlay and not showColor)
	end
end

local function populateShapePerkPreview(previewWidget, perkData, modifierEntry)
	if not previewWidget or not perkData then
		return
	end

	local icon = previewWidget:getChildById("icon")
	local borderWidget = previewWidget:getChildById("border")

	if icon then
		local iconSource, iconClip = ProficiencyData:getImageSourceAndClip(perkData)

		icon:setImageSource(iconSource)
		icon:setImageClip(string.format("%s 32 32", iconClip))
	end

	if borderWidget then
		borderWidget:setImageSource("/images/game/proficiency/border-weaponmasterytreeicons-active")
	end

	setupPerkIconOverlay(perkData, previewWidget)
	updateManipulateRankWidget(previewWidget, modifierEntry, true)
end

local RESHAPE_PERK_TITLE_MAX_LEN = 29
local RESHAPE_PERK_TITLE_TRUNCATED_LEN = 26
local SHAPE_PERK_TITLE_MAX_LEN = 39
local SHAPE_PERK_TITLE_TRUNCATED_LEN = 36

local function formatPerkBonusTitle(name, maxLen, truncatedLen)
	name = name or ""
	maxLen = maxLen or RESHAPE_PERK_TITLE_MAX_LEN
	truncatedLen = truncatedLen or RESHAPE_PERK_TITLE_TRUNCATED_LEN

	if maxLen >= #name then
		return name, ""
	end

	return name:sub(1, truncatedLen) .. "...", name
end

local function populateReshapePerkPanel(panel, modifierEnum, refineLevel)
	if not panel or not modifierEnum then
		return
	end

	local perkData = ProficiencyData:getModifierPerkData(modifierEnum, refineLevel)

	if not perkData then
		return
	end

	local modifierEntry = {
		modifierEnum = modifierEnum,
		refineLevel = refineLevel or 0
	}
	local bonusName, bonusTooltip = ProficiencyData:getBonusNameAndTooltip(perkData)
	local displayName, titleTooltip = formatPerkBonusTitle(bonusName)
	local panelTitle = panel:getChildById("panelTitle")

	if panelTitle then
		panelTitle:setText(displayName)
		panelTitle:setTooltip(titleTooltip)
	end

	local perkPreview = panel:getChildById("perkPreview")

	if perkPreview then
		populateShapePerkPreview(perkPreview, perkData, modifierEntry)
	end

	local perkBonusText = panel:recursiveGetChildById("perkBonusText")

	if perkBonusText then
		perkBonusText:setText(bonusTooltip or "")
	end
end

local function onBonusIconHoverChange(widget, hovered)
	g_tooltip.onWidgetHoverChange(widget, hovered)
end

local function onBonusIconClick(bonusIcon)
	local grade = bonusIcon.grade
	local slot = bonusIcon.slot
	local currentPerkPanel = bonusIcon:getParent()

	if not bonusIcon.blocked and not bonusIcon.locked and not bonusIcon.active then
		disableOtherBonusIcons(currentPerkPanel, bonusIcon)

		local currentPerkData = bonusIcon.perkData
		local _, currentTooltip = ProficiencyData:getBonusNameAndTooltip(currentPerkData)
		local currentItem = WeaponProficiency.displayItemWidget:getItem()
		local itemId = currentItem and currentItem:getId()
		local cacheEntry = itemId and WeaponProficiency.cacheList[itemId]
		local modifiers = cacheEntry and cacheEntry.modifiers or {}
		local isModified = getModifiedPerkData(modifiers, grade, slot) ~= nil
		local bonusDetail = WeaponProficiency.bonusDetailPanel:getChildById("bonusDetail_" .. grade + 1)

		enableBonusIcon(bonusIcon, bonusIcon:getChildById("highlight"), bonusIcon:getChildById("border"), bonusDetail and bonusDetail:recursiveGetChildById("bonusName"), currentTooltip, currentPerkData, isModified)
		WeaponProficiency:checkPerksMatch(itemId)
	end

	WeaponProficiency.selectedModifySlot = {
		grade = grade,
		slot = slot
	}

	WeaponProficiency:updateModifyButtonState()
	WeaponProficiency:updateSelectedPerkVisuals()
	WeaponProficiency:updateModifyCost()
end

function WeaponProficiency:reset()
	if self.closeWindowEvent then
		removeEvent(self.closeWindowEvent)
		self.closeWindowEvent = nil
	end

	if self.scrollUpdateEvent then
		removeEvent(self.scrollUpdateEvent)
		self.scrollUpdateEvent = nil
	end
	self.pendingScrollUpdate = nil
	self.cacheList = {}
	self.allProficiencyRequested = false
	self.selectedModifySlot = nil
	self.selectedClientId = nil
	self.selectedListEntry = nil
	self.saveWeaponMissing = false

	if self.perkPanel then
		self.perkPanel:destroyChildren()
	end

	if self.bonusDetailPanel then
		self.bonusDetailPanel:destroyChildren()
	end

	if self.starProgressPanel then
		self.starProgressPanel:destroyChildren()
	end

	if self.displayItemWidget then
		self.displayItemWidget:setItem(nil)
	end
end

function WeaponProficiency:updateMainButtons(currentData)
	local enableReset = canChangeWeaponPerks() and table.size(currentData.perks) > 0

	self.resetButton:setOn(enableReset)
	self.applyButton:setOn(false)
	self.okButton:setOn(false)

	local resetTooltip = "Reset your perks"

	if not canChangeWeaponPerks() then
		resetTooltip = "You can only reset your perks in a protection zone."
	elseif table.empty(currentData.perks) then
		resetTooltip = "You don't have any perks to reset."
	end

	self.resetButton:setTooltip(resetTooltip)
	self.applyButton:setTooltip("No changes have been made to your perks.")
	self.closeButton:setText("Close")
end

function WeaponProficiency:createItemCache()
	self.itemList = {}
	self.catalogItems = {}
	self.catalogReady = false
	ProficiencyData.catalogProficiencyByItem = {}
	self.itemList[MarketCategory.WeaponsAll] = {}

	for _, v in pairs(self.ItemCategory) do
		self.itemList[v] = {}
	end
end

function WeaponProficiency:addCatalogItem(itemId, marketCategory, proficiencyId, name)
	itemId = tonumber(itemId) or 0
	marketCategory = tonumber(marketCategory) or MarketCategory.WeaponsAll
	self.catalogItems = self.catalogItems or {}

	if itemId <= 0 or self.catalogItems[itemId] then
		return
	end

	if not self.itemList[marketCategory] then
		marketCategory = MarketCategory.WeaponsAll
	end

	proficiencyId = ProficiencyData:registerCatalogItem(itemId, marketCategory, name, proficiencyId)

	if proficiencyId == 0 then
		return
	end

	local itemType = g_things.getThingType(itemId, ThingCategoryItem)
	local rawMarket = itemType and itemType:getMarketData() or nil
	local marketData = {}

	if rawMarket then
		for key, value in pairs(rawMarket) do
			marketData[key] = value
		end
	end

	marketData.category = marketCategory
	marketData.clientId = itemId
	marketData.showAs = itemId
	marketData.name = tostring(name or "")
	marketData.requiredLevel = marketData.requiredLevel or 0
	marketData.restrictVocation = marketData.restrictVocation or 0
	marketData._nameLower = marketData.name:lower()

	local marketItem = {
		displayItem = Item.create(itemId),
		thingType = itemType,
		marketData = marketData,
		proficiencyId = proficiencyId
	}

	if marketCategory ~= MarketCategory.WeaponsAll then
		table.insert(self.itemList[marketCategory], marketItem)
	end
	table.insert(self.itemList[MarketCategory.WeaponsAll], marketItem)
	self.catalogItems[itemId] = true
end

function WeaponProficiency:onItemListValueChange(scroll, value, delta)
	if value == self.oldScrollValue and self.oldScrollValue ~= nil then
		return
	end

	self.oldScrollValue = value

	local itemListWidget = self.itemListWidget
	local itemsPerRow = 5
	local totalItems = #self.listData
	local ROW_HEIGHT = 37
	local CONTENT_MARGIN = 2
	local displayOffset = value - CONTENT_MARGIN
	local startRow = 0
	local subOffset = displayOffset

	if displayOffset >= 0 then
		startRow = math.floor(displayOffset / ROW_HEIGHT)
		subOffset = displayOffset % ROW_HEIGHT
	end

	local startLabel = startRow * itemsPerRow + 1

	itemListWidget:setVirtualOffset({
		x = 0,
		y = subOffset
	})

	if startLabel == self.oldScrollStartLabel then
		return
	end

	self.oldScrollStartLabel = startLabel

	local currentWidgetIndex = startLabel

	for _, widget in ipairs(itemListWidget:getChildren()) do
		if totalItems < currentWidgetIndex then
			widget:setVisible(false)
		else
			local entry = self.listData[currentWidgetIndex]

			if not entry then
				widget:setVisible(false)
			else
				widget:getChildById("item"):setItemId(ProficiencyData:getServerClientId(entry))
				applyProficiencyItemRarity(widget, entry.displayItem)
				widget:setTooltip(entry.marketData.name)

				widget.cache = entry

				widget:setVisible(true)

				if widget:isFocused() then
					itemListWidget:focusChild(nil, MouseFocusReason, false, true)
				end

				if self.selectedClientId and self.selectedClientId == ProficiencyData:getServerClientId(entry) then
					itemListWidget:focusChild(widget, MouseFocusReason, false, true)
				end

				local cacheEntry = self.cacheList[ProficiencyData:getServerClientId(entry)] or nil
				local weaponLevel = ProficiencyData:getCurrentLevelByExp(entry.displayItem, cacheEntry and cacheEntry.exp or 0)
				local starPanel = widget:getChildById("starsBackground")
				local starImage = isMasteryAchieved(entry) and STAR_IMAGE_GOLD or STAR_IMAGE_SILVER

				updateStarsForWidget(starPanel, weaponLevel, starImage)

				currentWidgetIndex = currentWidgetIndex + 1
			end
		end
	end
end

function WeaponProficiency:onWeaponCategoryChange(selected, searchText, targetItemId, focusFirstChild, fromOptionChange)
	local weaponCategory = WeaponStringToCategory[selected]

	if not weaponCategory then
		return
	end

	if not sortWeaponProficiency(weaponCategory) then
		return
	end

	self.optionFilter:setCurrentOption(selected, true)

	local targetWidget
	local itemListWidget = self.itemListWidget

	itemListWidget.onChildFocusChange = nil
	self.listCapacity = (math.floor(itemListWidget:getHeight() / self.listWidgetHeight) + 2) * 5
	self.listMinWidgets = 0
	self.oldScrollValue = nil
	self.oldScrollStartLabel = nil
	self.listData = {}

	local sortCtx = buildSortContext()
	local lowerSearch = searchText and not string.empty(searchText) and searchText:lower() or nil

	for _, data in ipairs(self.itemList[weaponCategory]) do
		if not checkSortOptions(data, sortCtx) then
			-- block empty
		elseif lowerSearch and not matchText(lowerSearch, data.marketData._nameLower or data.marketData.name:lower()) then
			-- block empty
		else
			table.insert(self.listData, data)
		end
	end

	local currentIndex = 0

	for _, data in ipairs(self.listData) do
		if currentIndex >= self.listCapacity then
			break
		end

		local widget = itemListWidget:recursiveGetChildById("widget_" .. currentIndex)

		if not widget then
			-- block empty
		else
			local clientId = ProficiencyData:getServerClientId(data)

			widget:setVisible(true)
			widget.cache = data

			if not targetWidget then
				if targetItemId and targetItemId == clientId then
					targetWidget = widget
				elseif fromOptionChange and not focusFirstChild and self.selectedClientId == clientId then
					targetWidget = widget
				end
			end

			currentIndex = currentIndex + 1
		end
	end

	for i = currentIndex, self.listCapacity do
		local widget = itemListWidget:recursiveGetChildById("widget_" .. i)

		if widget then
			widget:setVisible(false)
		end
	end

	self.listMaxWidgets = math.max(0, 2 + math.ceil(#self.listData / 5) * 37 + 2 - 218)

	self.itemListScroll:setMinimum(self.listMinWidgets)
	self.itemListScroll:setMaximum(math.max(0, self.listMaxWidgets))
	self.itemListScroll:setValue(0)

	self.itemListScroll:setVisibleItems(math.min(#self.listData, 45))
	self.itemListScroll:setVirtualChilds(#self.listData)
	itemListWidget:setVirtualOffset({
		x = 0,
		y = 0
	})
	itemListWidget.onChildFocusChange = onItemListChildFocusChange

	if targetWidget or focusFirstChild then
		itemListWidget:focusChild(targetWidget or itemListWidget:getFirstChild(), MouseFocusReason, true)
	else
		itemListWidget:focusChild(nil, MouseFocusReason, false, true)
	end

	if targetItemId and not targetWidget then
		for _, data in ipairs(self.itemList[weaponCategory]) do
			if targetItemId == ProficiencyData:getServerClientId(data) then
				self:onItemListFocusChange(data)

				break
			end
		end
	end

	-- Setting an already-zero scrollbar does not emit onValueChange. Queue one
	-- render after the list geometry is ready so the first visible page is not
	-- left empty until the player scrolls it.
	self.oldScrollValue = nil
	self.oldScrollStartLabel = nil
	onItemListScrollValueChange(self.itemListScroll, 0, 0)
end

function WeaponProficiency:onItemListFocusChange(selectedCache)
	if not selectedCache or not g_game.isOnline() then
		return
	end

	self.selectedListEntry = selectedCache
	self.selectedClientId = ProficiencyData:getServerClientId(selectedCache)
	self.selectedModifySlot = nil

	self:updateModifyCost()

	local displayPanel = self.displayItemWidget
	local oldItem = displayPanel:getItem()

	if self.saveWeaponMissing and oldItem then
		self:onCloseMessage(false, oldItem, function()
			self:onItemListFocusChange(selectedCache)
		end)

		return
	end

	self:updateModifyButtonState()
	self:updateSelectedPerkVisuals()

	local displayItem = selectedCache.displayItem
	local clientId = ProficiencyData:getServerClientId(selectedCache)

	displayPanel:setItemId(clientId)
	self.itemNameTitle:setText(selectedCache.marketData.name)
	self.perkPanel:destroyChildren()
	self.bonusDetailPanel:destroyChildren()
	self.starProgressPanel:destroyChildren()

	local player = g_game.getLocalPlayer()
	local itemVocation = selectedCache.marketData.restrictVocation
	local playerVocation = translateWheelVocation(player:getVocation())
	local showVocationWarning = false

	if itemVocation > 0 then
		local demotedVoc = playerVocation > 10 and playerVocation - 10 or playerVocation
		local vocBitMask = Bit.bit(demotedVoc)

		showVocationWarning = not Bit.hasBit(itemVocation, vocBitMask)
	end

	showVocationWarning = showVocationWarning or player:getLevel() < selectedCache.marketData.requiredLevel

	self.vocationWarning:setVisible(showVocationWarning)

	local currentData = self.cacheList[clientId] or {
		exp = 0,
		perks = {},
		modifiers = {}
	}

	if type(currentData.modifiers) ~= "table" then
		currentData.modifiers = {}
	end

	self.cacheList[clientId] = currentData

	g_game.sendInspectionObject(InspectObjectTypes.Proficiency, clientId, 1)

	if self.allProficiencyRequested then
		g_game.sendWeaponProficiencyAction(0, clientId)
	end

	local proficiencyId = ProficiencyData:getEntryProficiencyId(selectedCache)
	local profEntry = ProficiencyData:getContentById(proficiencyId)

	if not profEntry then
		return
	end

	self:updateExperienceProgress(currentData.exp, #profEntry.Levels, displayItem)

	local canChange = canChangeWeaponPerks()

	for i, levelData in ipairs(profEntry.Levels) do
		local widget = g_ui.createWidget("BonusSelectPanel", self.perkPanel)
		local bonusDetail = g_ui.createWidget("BonusDetailPanel", self.bonusDetailPanel)

		bonusDetail:setId("bonusDetail_" .. i)

		local starDetail = g_ui.createWidget("StarWidget", self.starProgressPanel)

		starDetail:setId("starWidget" .. i)
		widget:getChildById("bonusSelectProgress"):setPercent(0)

		local currentPerkPanel = self.perkPanelsName[#levelData.Perks] and widget:getChildById(self.perkPanelsName[#levelData.Perks])

		if currentPerkPanel then
			currentPerkPanel:setVisible(true)

			widget.currentPerkPanel = currentPerkPanel
		end

		local widgetIsBlocked = not canChange and currentData.perks[i - 1]

		for index, perkData in ipairs(levelData.Perks) do
			local bonusIcon = currentPerkPanel:getChildById(string.format("bonusIcon%s", index - 1))
			local icon = bonusIcon:getChildById("icon")
			local iconGrey = bonusIcon:getChildById("icon-grey")
			local borderWidget = bonusIcon:getChildById("border")
			local hightLightWidget = bonusIcon:getChildById("highlight")
			local displayPerkData = getModifiedPerkData(currentData.modifiers, i - 1, index - 1) or perkData
			local iconSource, iconClip = ProficiencyData:getImageSourceAndClip(displayPerkData)
			local bonusName, bonusTooltip = ProficiencyData:getBonusNameAndTooltip(displayPerkData)

			bonusIcon:setTooltip(string.format("%s\n\n%s", bonusName, bonusTooltip))

			bonusIcon.blocked, bonusIcon.locked, bonusIcon.active = true, false, false
			bonusIcon.originalPerkData = perkData
			bonusIcon.perkData = displayPerkData
			bonusIcon.grade = i - 1
			bonusIcon.slot = index - 1

			bonusIcon:getChildById("selected"):setVisible(false)
			icon:setImageSource(iconSource)
			icon:setImageClip(string.format("%s 32 32", iconClip))

			if iconGrey then
				iconGrey:setImageSource(iconSource)
				iconGrey:setImageClip(string.format("%s 32 32", iconClip))
			end

			setupPerkIconOverlay(displayPerkData, bonusIcon)

			local modifierEntry = getModifierEntry(currentData.modifiers, i - 1, index - 1)

			if currentData.perks[i - 1] == index - 1 then
				bonusIcon.blocked = false

				enableBonusIcon(bonusIcon, hightLightWidget, borderWidget, bonusDetail:recursiveGetChildById("bonusName"), bonusTooltip, displayPerkData, modifierEntry ~= nil)
			end

			applyBonusIconVisualState(bonusIcon)
			updateManipulateRankWidget(bonusIcon, modifierEntry, bonusIcon.active)

			if widgetIsBlocked then
				bonusIcon:getChildById("locked-perk"):setVisible(true)

				bonusIcon.locked = true
			end

			bonusIcon.onHoverChange = onBonusIconHoverChange

			function bonusIcon.onClick()
				onBonusIconClick(bonusIcon)
			end
		end

		updatePercentWidgets(widget, currentData.exp, i, displayItem)
	end
end

function WeaponProficiency:onUpdateSelectedProficiency(itemId)
	if not self.selectedClientId or self.selectedClientId ~= itemId then
		return
	end

	local currentItem = self.displayItemWidget:getItem()

	if not currentItem then
		return
	end

	local currentData = self.cacheList[itemId] or {
		exp = 0,
		perks = {},
		modifiers = {}
	}

	if type(currentData.modifiers) ~= "table" then
		currentData.modifiers = {}
	end

	local experience = currentData.exp

	self:updateExperienceProgress(experience, #self.perkPanel:getChildren(), currentItem)
	self:updateMainButtons(currentData)
	self:updateModifyButtonState()
	self:updateModifyCost()

	local canChange = canChangeWeaponPerks()

	for i, child in ipairs(self.perkPanel:getChildren()) do
		updatePercentWidgets(child, experience, i, currentItem)

		local widgetIsBlocked = not canChange and currentData.perks[i - 1] ~= nil

		for index, widget in pairs(child.currentPerkPanel:getChildren()) do
			widget:getChildById("locked-perk"):setVisible(widgetIsBlocked)
			widget.locked = widgetIsBlocked

			if currentData.perks[i - 1] == index - 1 then
				widget.blocked = false

				local modifiedPerkData = getModifiedPerkData(currentData.modifiers, i - 1, index - 1)
				local displayPerkData = modifiedPerkData or widget.originalPerkData or widget.perkData

				if displayPerkData then
					widget.perkData = displayPerkData

					local iconSource, iconClip = ProficiencyData:getImageSourceAndClip(displayPerkData)
					local icon = widget:getChildById("icon")
					local iconGrey = widget:getChildById("icon-grey")

					icon:setImageSource(iconSource)
					icon:setImageClip(string.format("%s 32 32", iconClip))

					if iconGrey then
						iconGrey:setImageSource(iconSource)
						iconGrey:setImageClip(string.format("%s 32 32", iconClip))
					end

					local borderWidget = widget:getChildById("border")
					local hightLightWidget = widget:getChildById("highlight")
					local bonusDetail = self.bonusDetailPanel:getChildById("bonusDetail_" .. i)
					local bonusName, bonusTooltip = ProficiencyData:getBonusNameAndTooltip(displayPerkData)

					setupPerkIconOverlay(displayPerkData, widget)
					enableBonusIcon(widget, hightLightWidget, borderWidget, bonusDetail:recursiveGetChildById("bonusName"), bonusTooltip, displayPerkData, modifiedPerkData ~= nil)
					widget:setTooltip(string.format("%s\n\n%s", bonusName, bonusTooltip))

					local modifierEntry = getModifierEntry(currentData.modifiers, i - 1, index - 1)

					updateManipulateRankWidget(widget, modifierEntry, widget.active)
				end
			end
		end
	end

	self:updateSelectedPerkVisuals()
	self:checkPerksMatch(itemId)
end

function WeaponProficiency:updateExperienceProgress(currentExp, levelsCount, displayItem)
	local experienceWidget = self.progressDescription
	local experienceLeftWidget = self.nextLevelDescription
	local totalProgressWidget = self.proficiencyProgress
	local currentCeilExperience = ProficiencyData:getCurrentCeilExperience(currentExp, displayItem)
	local maxExperience = ProficiencyData:getMaxExperience(levelsCount, displayItem)
	local masteryAchieved = maxExperience <= currentExp

	experienceWidget:setText(string.format("%s / %s", comma_value(currentExp), comma_value(currentCeilExperience)))
	self:updateItemAddons(currentExp, displayItem, masteryAchieved)

	if masteryAchieved then
		experienceLeftWidget:setText("Mastery achieved")
	else
		experienceLeftWidget:setText(string.format("%s XP for next level", comma_value(currentCeilExperience - currentExp)))
	end

	totalProgressWidget:setPercent(ProficiencyData:getTotalPercent(currentExp, levelsCount, displayItem))
	totalProgressWidget:setTooltip(string.format("%s / %s", comma_value(currentExp), comma_value(maxExperience)))
end

function WeaponProficiency:updateItemAddons(currentExp, displayItem, masteryAchieved)
	local weaponLevel = math.min(7, ProficiencyData:getCurrentLevelByExp(displayItem, currentExp))
	local iconLevelWidget = self.iconMasteryLevel
	local weaponLevelWidget = self.itemMasteryLevel

	iconLevelWidget:setImageSource("/images/game/proficiency/icon-masterylevel-" .. weaponLevel)
	weaponLevelWidget:setVisible(weaponLevel > 0)

	if weaponLevel > 0 then
		local color = masteryAchieved and "gold" or "silver"

		weaponLevelWidget:setImageSource(string.format("/images/game/proficiency/icon-masterylevel-%d-%s", weaponLevel, color))
	end
end

function WeaponProficiency:toggleFilterOption(filter)
	local filterId = filter:getId()

	if filterId == "oneButton" then
		local twoHandButton = self.window:recursiveGetChildById("twoButton")

		if twoHandButton and twoHandButton:isChecked() then
			twoHandButton:setChecked(false, true)

			self.filters.twoButton = false
		end
	elseif filterId == "twoButton" then
		local oneHandButton = self.window:recursiveGetChildById("oneButton")

		if oneHandButton and oneHandButton:isChecked() then
			oneHandButton:setChecked(false, true)

			self.filters.oneButton = false
		end
	end

	self.filters[filterId] = not filter:isChecked()

	filter:setChecked(not filter:isChecked())
	self:onWeaponCategoryChange(self.optionFilter:getCurrentOption().text)
end

function WeaponProficiency:onSearchTextChange(text)
	local currentCategory = self.optionFilter:getCurrentOption().text

	self:onWeaponCategoryChange(currentCategory, text)
end

function WeaponProficiency:onClearSearch(silent)
	if not self.window then
		return
	end

	if not string.empty(self.searchField:getText()) then
		if silent then
			self.searchField:setText("", true)
		else
			self.searchField:clearText()
		end
	end
end

function WeaponProficiency:onApplyChanges(button, targetItem)
	if button and not button:isOn() then
		return
	end

	local currentItem = self.displayItemWidget:getItem()

	if targetItem then
		currentItem = targetItem
	end

	if not currentItem then
		return
	end

	local clientId = self:getSelectedClientId()

	if clientId <= 0 then
		return
	end

	local toSend = {}

	for i, child in ipairs(self.perkPanel:getChildren()) do
		for k, v in pairs(child.currentPerkPanel:getChildren()) do
			if not v.blocked and v.active then
				toSend[i - 1] = k - 1
			end
		end
	end

	if table.empty(toSend) then
		g_game.sendWeaponProficiencyAction(2, clientId)

		self.cacheList[clientId].perks = {}
	else
		-- our binding is sendWeaponProficiencyApply(itemId, levels[], perkPositions[]),
		-- not (itemId, level->perk map) as in Paulistinha - we split it into two arrays
		local levels, positions = {}, {}

		for level in pairs(toSend) do
			levels[#levels + 1] = level
		end

		table.sort(levels)

		for i, level in ipairs(levels) do
			positions[i] = toSend[level]
		end

		g_game.sendWeaponProficiencyApply(clientId, levels, positions)

		self.cacheList[clientId].perks = toSend
	end

	self.applyButton:setOn(false)
	self.okButton:setOn(false)
	self.closeButton:setText("Close")

	self.saveWeaponMissing = false
	self.selectedModifySlot = nil

	self:updateModifyButtonState()
	self:updateSelectedPerkVisuals()
end

function WeaponProficiency:updateSelectedPerkVisuals()
	local clientId = self:getSelectedClientId()
	local cacheEntry = clientId > 0 and self.cacheList[clientId] or nil
	local modifiers = cacheEntry and cacheEntry.modifiers or {}
	local selectedSlot = self.selectedModifySlot

	for i, child in ipairs(self.perkPanel:getChildren()) do
		local currentPerkPanel = child.currentPerkPanel

		if not currentPerkPanel then
			-- block empty
		else
			for k, bonusIcon in pairs(currentPerkPanel:getChildren()) do
				local selectedWidget = bonusIcon:getChildById("selected")
				local highlightWidget = bonusIcon:getChildById("highlight")

				if not selectedWidget then
					-- block empty
				else
					local isSelected = selectedSlot and selectedSlot.grade == bonusIcon.grade and selectedSlot.slot == bonusIcon.slot
					local modifierEntry = getModifierEntry(modifiers, bonusIcon.grade, bonusIcon.slot)
					local isModified = modifierEntry ~= nil

					if highlightWidget then
						local highlightSource = isModified and "/images/game/proficiency/backdrop_weaponmastery_manipulate_highlight" or "/images/game/proficiency/backdrop_weaponmastery_highlight"

						if highlightWidget:getImageSource() ~= highlightSource then
							highlightWidget:setImageSource(highlightSource)
						end
					end

					updateManipulateRankWidget(bonusIcon, modifierEntry, bonusIcon.active)
					selectedWidget:setVisible(isSelected)
					applyBonusIconVisualState(bonusIcon)
				end
			end
		end
	end
end

function WeaponProficiency:isLevelUnlocked(grade)
	local levelPanel = self.perkPanel:getChildren()[grade + 1]

	if not levelPanel then
		return false
	end

	local currentPerkPanel = levelPanel.currentPerkPanel

	if not currentPerkPanel then
		return false
	end

	for _, bonusIcon in pairs(currentPerkPanel:getChildren()) do
		if not bonusIcon.blocked and not bonusIcon.locked then
			return true
		end
	end

	return false
end

function WeaponProficiency:updateDustBalance()
	if not self.dustBalanceText then
		return
	end

	local player = g_game.getLocalPlayer()
	local currentDust = player and player:getResourceBalance(ResourceTypes.FORGE_DUST) or 0

	self.dustBalanceText:setText(string.format("%s/%s", comma_value(currentDust), comma_value(self.maxDust)))
end

local function getShapeDialog()
	local root = g_ui.getRootWidget()

	return root and root:recursiveGetChildById("shapeDialog")
end

function WeaponProficiency:updateShapeResourceBalances(shape)
	shape = shape or getShapeDialog()

	if not shape then
		return
	end

	local player = g_game.getLocalPlayer()
	local currentDust = player and player:getResourceBalance(ResourceTypes.FORGE_DUST) or 0
	local orbCount = player and player:getResourceBalance(ResourceTypes.LUNAR_ASCENSION_ORBS) or 0
	local dustText = shape:recursiveGetChildById("shapeDustBalanceText")

	if dustText then
		dustText:setText(string.format("%s/%s", comma_value(currentDust), comma_value(self.maxDust)))
	end

	local orbText = shape:recursiveGetChildById("shapeOrbBalanceText")

	if orbText then
		orbText:setText(comma_value(orbCount))
	end

	self:updateShapeMaximiseButtonState(shape)
	self:updateShapeRefineButtonState(shape)
	self:updateShapeReshapeButtonState(shape)
	self:updateShapePerkPreview(shape)
	self:setupShapeRankPreviewHover(shape)
end

function WeaponProficiency:updateShapePerkPreview(shape)
	shape = shape or getShapeDialog()

	if not shape or not self.selectedModifySlot then
		return
	end

	local modifierEntry = self:getSelectedModifierEntry()

	if not modifierEntry then
		return
	end

	local refineLevel = modifierEntry.refineLevel or 0
	local modifiedPerkData = ProficiencyData:getModifierPerkData(modifierEntry.modifierEnum, refineLevel)

	if not modifiedPerkData then
		return
	end

	local bonusName, bonusTooltip = ProficiencyData:getBonusNameAndTooltip(modifiedPerkData)
	local displayName, titleTooltip = formatPerkBonusTitle(bonusName, SHAPE_PERK_TITLE_MAX_LEN, SHAPE_PERK_TITLE_TRUNCATED_LEN)
	local leftTitle = shape:recursiveGetChildById("leftTitle")

	if leftTitle then
		leftTitle:setText(displayName)
		leftTitle:setTooltip(titleTooltip)
	end

	self.shapeBaseBonusText = bonusTooltip or ""

	local perkBonusText = shape:recursiveGetChildById("perkBonusText")

	if perkBonusText then
		perkBonusText:setText(self.shapeBaseBonusText)
	end

	local perkPreview = shape:recursiveGetChildById("perkPreview")

	if perkPreview then
		populateShapePerkPreview(perkPreview, modifiedPerkData, modifierEntry)
	end
end

local MAX_MODIFIER_REFINE_LEVEL = 10
local SHAPE_MAX_RANK_TOOLTIP = "Action not possible:\n\x95 Maximum rank has been reached."
local SHAPE_NOT_ENOUGH_DUST_TOOLTIP = "Action not possible:\n\x95 Not enough dust available."
local SHAPE_NOT_ENOUGH_ORBS_TOOLTIP = "Action not possible:\n\x95 Not enough Lunar Ascension Orbs available."
local SHAPE_RESHAPE_DUST_COST = 250

local function getShapeRefineDustCost(refineLevel)
	return 125 + (refineLevel or 0) * 75
end

local function getShapeRankEffectText(modifierEntry, targetRank)
	if not modifierEntry or targetRank == nil then
		return nil
	end

	local perkData = ProficiencyData:getModifierPerkData(modifierEntry.modifierEnum, targetRank)

	if not perkData then
		return nil
	end

	local _, description = ProficiencyData:getBonusNameAndTooltip(perkData)

	if not description or description == "" then
		return nil
	end

	return string.format("Effect at rank %d:\n%s", targetRank, description)
end

local function updateShapePerkBonusTextDisplay(self, shape, targetRank)
	local perkBonusText = shape:recursiveGetChildById("perkBonusText")

	if not perkBonusText then
		return
	end

	local baseText = self.shapeBaseBonusText or ""

	if not targetRank then
		perkBonusText:setText(baseText)

		return
	end

	local modifierEntry = self:getSelectedModifierEntry()
	local preview = getShapeRankEffectText(modifierEntry, targetRank)

	if preview and preview ~= "" then
		perkBonusText:setText(baseText .. "\n\n" .. preview)
	else
		perkBonusText:setText(baseText)
	end
end

function WeaponProficiency:setupShapeRankPreviewHover(shape)
	shape = shape or getShapeDialog()

	if not shape then
		return
	end

	local refineButton = shape:recursiveGetChildById("shapeRefineButton")

	if refineButton and not refineButton.proficiencyRankHoverBound then
		refineButton.proficiencyRankHoverBound = true
		refineButton.onHoverChange = function(widget, hovered)
			if hovered and widget:isEnabled() then
				local entry = self:getSelectedModifierEntry()
				local level = entry and (entry.refineLevel or 0) or 0

				updateShapePerkBonusTextDisplay(self, shape, level + 1)
			else
				updateShapePerkBonusTextDisplay(self, shape, nil)
			end
		end
	end

	local maximiseButton = shape:recursiveGetChildById("shapeMaximiseButton")

	if maximiseButton and not maximiseButton.proficiencyRankHoverBound then
		maximiseButton.proficiencyRankHoverBound = true
		maximiseButton.onHoverChange = function(widget, hovered)
			if hovered and widget:isEnabled() then
				updateShapePerkBonusTextDisplay(self, shape, MAX_MODIFIER_REFINE_LEVEL)
			else
				updateShapePerkBonusTextDisplay(self, shape, nil)
			end
		end
	end
end

local function applyShapeSideButtonMaxRankState(button, costPanel)
	button:setSize({
		width = 149,
		height = 26
	})
	button:setEnabled(false)
	button:setColor("#707070")
	button:setTooltip(SHAPE_MAX_RANK_TOOLTIP)

	if costPanel then
		costPanel:setVisible(false)
	end
end

local function restoreShapeSideButtonLayout(button, costPanel)
	button:setSize({
		width = 92,
		height = 26
	})
	button:setTooltip("")

	if costPanel then
		costPanel:setVisible(true)
	end
end

function WeaponProficiency:updateShapeRefineButtonState(shape)
	shape = shape or getShapeDialog()

	if not shape then
		return
	end

	local refineButton = shape:recursiveGetChildById("shapeRefineButton")
	local refineCost = shape:recursiveGetChildById("shapeRefineCost")
	local refineCostText = refineCost and refineCost:recursiveGetChildById("costText")

	if not refineButton or not refineCostText then
		return
	end

	local modifierEntry

	if self.selectedModifySlot then
		modifierEntry = self:getSelectedModifierEntry()
	end

	local refineLevel = modifierEntry and (modifierEntry.refineLevel or 0) or 0

	if refineLevel >= MAX_MODIFIER_REFINE_LEVEL then
		applyShapeSideButtonMaxRankState(refineButton, refineCost)

		return
	end

	restoreShapeSideButtonLayout(refineButton, refineCost)

	local dustCost = getShapeRefineDustCost(refineLevel)

	refineCostText:setText(tostring(dustCost))

	local player = g_game.getLocalPlayer()
	local currentDust = player and player:getResourceBalance(ResourceTypes.FORGE_DUST) or 0
	local hasEnoughDust = dustCost <= currentDust

	if hasEnoughDust then
		refineButton:setEnabled(true)
		refineButton:setColor("#c0c0c0")
		refineButton:setTooltip("")
		refineCostText:setColor("#c0c0c0")
	else
		refineButton:setEnabled(false)
		refineButton:setColor("#707070")
		refineButton:setTooltip(SHAPE_NOT_ENOUGH_DUST_TOOLTIP)
		refineCostText:setColor("#d33c3c")
	end
end

function WeaponProficiency:updateShapeReshapeButtonState(shape)
	shape = shape or getShapeDialog()

	if not shape then
		return
	end

	local reshapeButton = shape:recursiveGetChildById("shapeReshapeButton")
	local reshapeCost = shape:recursiveGetChildById("shapeReshapeCost")
	local reshapeCostText = reshapeCost and reshapeCost:recursiveGetChildById("costText")

	if not reshapeButton or not reshapeCostText then
		return
	end

	restoreShapeSideButtonLayout(reshapeButton, reshapeCost)
	reshapeCostText:setText(tostring(SHAPE_RESHAPE_DUST_COST))

	local player = g_game.getLocalPlayer()
	local currentDust = player and player:getResourceBalance(ResourceTypes.FORGE_DUST) or 0
	local hasEnoughDust = currentDust >= SHAPE_RESHAPE_DUST_COST

	if hasEnoughDust then
		reshapeButton:setEnabled(true)
		reshapeButton:setColor("#c0c0c0")
		reshapeButton:setTooltip("")
		reshapeCostText:setColor("#c0c0c0")
	else
		reshapeButton:setEnabled(false)
		reshapeButton:setColor("#707070")
		reshapeButton:setTooltip(SHAPE_NOT_ENOUGH_DUST_TOOLTIP)
		reshapeCostText:setColor("#d33c3c")
	end
end

function WeaponProficiency:updateShapeMaximiseButtonState(shape)
	shape = shape or getShapeDialog()

	if not shape then
		return
	end

	local maximiseButton = shape:recursiveGetChildById("shapeMaximiseButton")
	local maximiseCost = shape:recursiveGetChildById("shapeMaximiseCost")
	local maximiseCostText = maximiseCost and maximiseCost:recursiveGetChildById("costText")

	if not maximiseButton or not maximiseCostText then
		return
	end

	local modifierEntry

	if self.selectedModifySlot then
		modifierEntry = self:getSelectedModifierEntry()
	end

	local refineLevel = modifierEntry and (modifierEntry.refineLevel or 0) or 0

	if refineLevel >= MAX_MODIFIER_REFINE_LEVEL then
		applyShapeSideButtonMaxRankState(maximiseButton, maximiseCost)

		return
	end

	restoreShapeSideButtonLayout(maximiseButton, maximiseCost)

	local orbCost = 1

	maximiseCostText:setText(tostring(orbCost))

	local player = g_game.getLocalPlayer()
	local orbCount = player and player:getResourceBalance(ResourceTypes.LUNAR_ASCENSION_ORBS) or 0
	local hasEnoughOrbs = orbCost <= orbCount

	if hasEnoughOrbs then
		maximiseButton:setEnabled(true)
		maximiseButton:setColor("#c0c0c0")
		maximiseButton:setTooltip("")
		maximiseCostText:setColor("#c0c0c0")
	else
		maximiseButton:setEnabled(false)
		maximiseButton:setColor("#707070")
		maximiseButton:setTooltip(SHAPE_NOT_ENOUGH_ORBS_TOOLTIP)
		maximiseCostText:setColor("#d33c3c")
	end
end

local VOCATION_BLOCK_START = {
	1,
	51,
	101,
	151,
	201
}
local GENERAL_SHAPING_ENUMS = {
	251,
	252,
	253,
	254,
	255,
	256,
	257,
	258,
	259,
	260,
	261,
	262,
	263,
	264,
	265,
	266,
	267,
	268,
	269,
	270,
	271,
	281,
	282,
	283,
	284,
	285,
	286,
	287,
	291,
	292,
	293,
	321,
	322,
	323
}
local SHAPING_AUGMENT_GROUPS = 5
local SHAPING_SPELL_SLOTS = 6
local AUGMENT_TYPE_SORT_NAMES = {
	[PERK_AUGMENT_BASE_DAMAGE] = "base damage",
	[PERK_AUGMENT_CHAIN_LENGTH] = "chain length",
	[PERK_AUGMENT_COOLDOWN_REDUCTION] = "cooldown",
	[PERK_AUGMENT_CRITICAL_EXTRA_DAMAGE] = "critical extra damage",
	[PERK_AUGMENT_CRITICAL_HIT_CHANCE] = "critical hit chance",
	[PERK_AUGMENT_HEALING] = "healing",
	[PERK_AUGMENT_LIFE_LEECH] = "life leech",
	[PERK_AUGMENT_MANA_LEECH] = "mana leech"
}

local function buildShapingEnumsForVocation(vocationId)
	local enums = {}
	local blockStart = VOCATION_BLOCK_START[vocationId]

	if blockStart then
		for group = 0, SHAPING_AUGMENT_GROUPS - 1 do
			for slot = 0, SHAPING_SPELL_SLOTS - 1 do
				enums[#enums + 1] = blockStart + group * 10 + slot
			end
		end
	end

	for _, generalEnum in ipairs(GENERAL_SHAPING_ENUMS) do
		enums[#enums + 1] = generalEnum
	end

	return enums
end

local function getPerkShapingOptionsDialog()
	local root = g_ui.getRootWidget()

	return root and root:recursiveGetChildById("perkShapingOptionsDialog")
end

local function abbreviateShapingOptionName(name)
	if #name > 23 then
		return name:sub(1, 20) .. "...", true
	end

	return name, false
end

local function getCurrentShapingVocationId()
	local player = g_game.getLocalPlayer()

	if not player then
		return 0
	end

	return translateWheelVocation(player:getVocation()) or 0
end

function WeaponProficiency:buildPerkShapingOptionsData(vocationId)
	vocationId = vocationId or getCurrentShapingVocationId()

	local cache = self._shapingOptionsCache

	if cache and cache[vocationId] then
		return cache[vocationId]
	end

	local result = {}

	for _, modifierEnum in ipairs(buildShapingEnumsForVocation(vocationId)) do
		local perkDataRank0 = ProficiencyData:getModifierPerkData(modifierEnum, 0)
		local perkDataRank10 = ProficiencyData:getModifierPerkData(modifierEnum, MAX_MODIFIER_REFINE_LEVEL)

		if perkDataRank0 and perkDataRank10 then
			local name, rank0Desc = ProficiencyData:getBonusNameAndTooltip(perkDataRank0)
			local _, rank10Desc = ProficiencyData:getBonusNameAndTooltip(perkDataRank10)
			local iconSource, iconClip = ProficiencyData:getImageSourceAndClip(perkDataRank0)
			local overlaySource, overlayClip
			local hasOverlay = false
			local sortSecondary = rank0Desc:lower()
			local sortTertiary = ""

			if perkDataRank0.Type == PERK_SPELL_AUGMENT then
				overlaySource = SKILLWHEEL_SMALLPERKS_PATH
				overlayClip = ProficiencyData:getAugmentIconClip(perkDataRank0)
				hasOverlay = true

				local spellData = Spells.getSpellDataById(perkDataRank0.SpellId)

				sortSecondary = spellData and spellData.name and spellData.name:lower() or ""
				sortTertiary = AUGMENT_TYPE_SORT_NAMES[perkDataRank0.AugmentType] or ""
			end

			result[#result + 1] = {
				modifierEnum = modifierEnum,
				name = name,
				nameLower = name:lower(),
				rank0Desc = rank0Desc,
				rank0DescLower = rank0Desc:lower(),
				rank10Desc = rank10Desc,
				rank10DescLower = rank10Desc:lower(),
				iconSource = iconSource,
				iconClip = iconClip,
				overlaySource = overlaySource,
				overlayClip = overlayClip,
				hasOverlay = hasOverlay,
				sortSecondary = sortSecondary,
				sortTertiary = sortTertiary
			}
		end
	end

	table.sort(result, function(a, b)
		if a.nameLower ~= b.nameLower then
			return a.nameLower < b.nameLower
		end

		if a.sortSecondary ~= b.sortSecondary then
			return a.sortSecondary < b.sortSecondary
		end

		return a.sortTertiary < b.sortTertiary
	end)

	self._shapingOptionsCache = cache or {}
	self._shapingOptionsCache[vocationId] = result

	return result
end

function WeaponProficiency:invalidateShapingOptionsCache()
	self._shapingOptionsCache = nil
end

function WeaponProficiency:updatePerkShapingOptionsDustBalance(dialog)
	dialog = dialog or getPerkShapingOptionsDialog()

	if not dialog then
		return
	end

	local dustText = dialog:recursiveGetChildById("shapingOptionsDustBalanceText")

	if not dustText then
		return
	end

	local player = g_game.getLocalPlayer()
	local currentDust = player and player:getResourceBalance(ResourceTypes.FORGE_DUST) or 0

	dustText:setText(string.format("%s/%s", comma_value(currentDust), comma_value(self.maxDust)))
end

function WeaponProficiency:populatePerkShapingOptionsList(filterText)
	local dialog = getPerkShapingOptionsDialog()

	if not dialog then
		return
	end

	local list = dialog:recursiveGetChildById("shapingOptionsList")

	if not list then
		return
	end

	list:destroyChildren()

	filterText = filterText and filterText:lower() or ""

	local data = self:buildPerkShapingOptionsData()
	local visibleIndex = 0

	for _, entry in ipairs(data) do
		if filterText == "" or entry.nameLower:find(filterText, 1, true) or entry.rank0DescLower:find(filterText, 1, true) or entry.rank10DescLower:find(filterText, 1, true) then
			visibleIndex = visibleIndex + 1

			local row = g_ui.createWidget("PerkShapingOptionsRow", list)

			row:setBackgroundColor(visibleIndex % 2 == 0 and "#414141" or "#484848")

			local icon = row:recursiveGetChildById("rowPerkIcon")

			if icon then
				icon:setImageSource(entry.iconSource)
				icon:setImageClip(string.format("%s 32 32", entry.iconClip))
			end

			local overlay = row:recursiveGetChildById("rowPerkIconOverlay")

			if overlay then
				if entry.hasOverlay then
					overlay:setImageSource(entry.overlaySource)
					overlay:setImageClip(entry.overlayClip)
					overlay:setVisible(true)
				else
					overlay:setVisible(false)
				end
			end

			local displayName, wasAbbreviated = abbreviateShapingOptionName(entry.name)
			local nameLabel = row:recursiveGetChildById("rowPerkName")

			if nameLabel then
				nameLabel:setText(displayName)

				if wasAbbreviated then
					nameLabel:setTooltip(entry.name)
				else
					nameLabel:removeTooltip()
				end
			end

			local perkColumn = row:recursiveGetChildById("rowPerkColumn")

			if perkColumn then
				if wasAbbreviated then
					perkColumn:setTooltip(entry.name)
				else
					perkColumn:removeTooltip()
				end
			end

			local rank0Label = row:recursiveGetChildById("rowRank0Text")

			if rank0Label then
				rank0Label:setText(entry.rank0Desc)
			end

			local rank10Label = row:recursiveGetChildById("rowRank10Text")

			if rank10Label then
				rank10Label:setText(entry.rank10Desc)
			end
		end
	end

	list:updateLayout()
end

function WeaponProficiency:openPerkShapingOptions()
	local root = g_ui.getRootWidget()

	if not root then
		return
	end

	local shape = root:recursiveGetChildById("shapeDialog")

	if shape then
		shape:hide()

		if g_modalManager then
			g_modalManager.hide(shape)
		end
	end

	local existing = root:recursiveGetChildById("perkShapingOptionsDialog")

	if existing then
		existing:destroy()
	end

	local dialog = g_ui.createWidget("PerkShapingOptionsDialog", root)

	if not dialog then
		g_logger.error("[WeaponProficiency] Unable to create dialog style 'PerkShapingOptionsDialog'.")
		self:returnToShapeDialog()
		return
	end

	dialog:setId("perkShapingOptionsDialog")
	self:updatePerkShapingOptionsDustBalance(dialog)
	self:populatePerkShapingOptionsList("")
	dialog:show()

	if g_modalManager then
		g_modalManager.show(dialog)
	end
end

function WeaponProficiency:closePerkShapingOptions()
	local dialog = getPerkShapingOptionsDialog()

	if dialog then
		dialog:destroy()

		if g_modalManager then
			g_modalManager.hide(dialog)
		end
	end

	self:returnToShapeDialog()
end

function WeaponProficiency:onShapeInfoButtonClick()
	self:openPerkShapingOptions()
end

function WeaponProficiency:onPerkShapingOptionsDialogEscape()
	self:closePerkShapingOptions()
end

function WeaponProficiency:onPerkShapingOptionsClose()
	self:closePerkShapingOptions()
end

function WeaponProficiency:onPerkShapingOptionsSearchChange(text)
	self:populatePerkShapingOptionsList(text)
end

function WeaponProficiency:onPerkShapingOptionsSearchClear()
	local dialog = getPerkShapingOptionsDialog()

	if not dialog then
		return
	end

	local searchEdit = dialog:recursiveGetChildById("shapingOptionsSearchEdit")

	if searchEdit then
		searchEdit:setText("")
		searchEdit:focus()
	end

	self:populatePerkShapingOptionsList("")
end

function WeaponProficiency:updateModifyCost()
	local modifyCostText = self.modifyCostText

	if not modifyCostText then
		return
	end

	local currentItem = self.displayItemWidget:getItem()
	local itemId = currentItem and currentItem:getId()
	local cacheEntry = itemId and self.cacheList[itemId]
	local modifiers = cacheEntry and cacheEntry.modifiers or {}
	local cost = #modifiers >= 1 and 1000 or 250

	modifyCostText:setText(tostring(cost))

	local player = g_game.getLocalPlayer()
	local currentDust = player and player:getResourceBalance(ResourceTypes.FORGE_DUST) or 0

	if currentDust < cost then
		modifyCostText:setColor("#d33c3c")
	else
		modifyCostText:setColor("#c0c0c0")
	end
end

function WeaponProficiency:resetModifyButton(modifyButton, modifyCost)
	modifyButton:setStyle("ModifyButton")

	if modifyCost then
		modifyCost:setVisible(true)
	end
end

function WeaponProficiency:updateModifyButtonState()
	local modifyButton = self.modifyButton
	local modifyCost = self.modifyCost

	if not modifyButton then
		return
	end

	local currentItem = self.displayItemWidget:getItem()
	local itemId = currentItem and currentItem:getId()
	local cacheEntry = itemId and self.cacheList[itemId]
	local modifiers = cacheEntry and cacheEntry.modifiers or {}

	if not self.selectedModifySlot then
		if #modifiers >= 2 then
			modifyButton:setStyle("ModifyButtonLarge")
			modifyButton:setEnabled(false)
			modifyButton:setTooltip("Action not possible:\n\x95 Only 2 perks can be modified.")

			if modifyCost then
				modifyCost:setVisible(false)
			end
		else
			self:resetModifyButton(modifyButton, modifyCost)
			modifyButton:setEnabled(false)
			modifyButton:setTooltip("Action not possible:\n\x95 You need to select a perk.")
		end

		return
	end

	local grade = self.selectedModifySlot.grade
	local slot = self.selectedModifySlot.slot
	local levelPanel = self.perkPanel:getChildren()[grade + 1]
	local currentPerkPanel = levelPanel and levelPanel.currentPerkPanel
	local selectedBonusIcon = currentPerkPanel and currentPerkPanel:getChildById("bonusIcon" .. slot)

	if not selectedBonusIcon or not selectedBonusIcon.grade then
		self:resetModifyButton(modifyButton, modifyCost)
		modifyButton:setEnabled(false)
		modifyButton:setTooltip("Action not possible:\n\x95 You need to select a perk.")

		self.selectedModifySlot = nil

		return
	end

	local totalModified = #modifiers
	local selectedHasModifier = false

	for _, modifier in ipairs(modifiers) do
		if modifier.grade == grade and modifier.slot == slot then
			selectedHasModifier = true

			break
		end
	end

	if totalModified >= 2 and not selectedHasModifier then
		modifyButton:setStyle("ModifyButtonLarge")
		modifyButton:setEnabled(false)
		modifyButton:setTooltip("Action not possible:\n\x95 Only 2 perks can be modified.")

		if modifyCost then
			modifyCost:setVisible(false)
		end

		return
	end

	local level3Unlocked = self:isLevelUnlocked(2)
	local selectedUnlocked = not selectedBonusIcon.blocked and not selectedBonusIcon.locked

	if selectedHasModifier then
		modifyButton:setStyle("ShapeButton")

		if modifyCost then
			modifyCost:setVisible(false)
		end

		if level3Unlocked and selectedUnlocked then
			modifyButton:setEnabled(true)
			modifyButton:setTooltip("Shape selected weapon proficiency slot")
		else
			modifyButton:setEnabled(false)

			local tooltip = "Action not possible:"

			if not selectedUnlocked then
				tooltip = tooltip .. "\n\x95 Perk is not unlocked."
			end

			if not level3Unlocked then
				tooltip = tooltip .. "\n\x95 Level 3 has not been unlocked."
			end

			modifyButton:setTooltip(tooltip)
		end

		return
	end

	self:resetModifyButton(modifyButton, modifyCost)

	local player = g_game.getLocalPlayer()
	local currentDust = player and player:getResourceBalance(ResourceTypes.FORGE_DUST) or 0
	local cost = totalModified >= 1 and 1000 or 250
	local hasEnoughDust = cost <= currentDust

	if level3Unlocked and selectedUnlocked and hasEnoughDust then
		modifyButton:setEnabled(true)
		modifyButton:setTooltip("")

		return
	end

	local tooltip = "Action not possible:"

	if not selectedUnlocked then
		tooltip = tooltip .. "\n\x95 Perk is not unlocked."
	end

	if not level3Unlocked then
		tooltip = tooltip .. "\n\x95 Level 3 has not been unlocked."
	end

	if not hasEnoughDust then
		tooltip = tooltip .. "\n\x95 Not enough dust available."
	end

	modifyButton:setEnabled(false)
	modifyButton:setTooltip(tooltip)
end

function WeaponProficiency:confirmModify()
	local currentItem = self.displayItemWidget:getItem()

	if not currentItem or not self.selectedModifySlot then
		return
	end

	local grade = self.selectedModifySlot.grade
	local slot = self.selectedModifySlot.slot
	local clientId = self:getSelectedClientId()

	if self.saveWeaponMissing then
		self:onApplyChanges(nil, currentItem)

		self.selectedModifySlot = {
			grade = grade,
			slot = slot
		}
	end

	g_game.sendWeaponProficiencyModifierAction(4, clientId, grade, slot)
end

function WeaponProficiency:confirmRefine()
	local currentItem = self.displayItemWidget:getItem()

	if not currentItem or not self.selectedModifySlot then
		return
	end

	local grade = self.selectedModifySlot.grade
	local slot = self.selectedModifySlot.slot
	local clientId = self:getSelectedClientId()
	local cacheEntry = self.cacheList[clientId]

	if cacheEntry then
		local modifierEntry = getModifierEntry(cacheEntry.modifiers, grade, slot)

		if modifierEntry and (modifierEntry.refineLevel or 0) < MAX_MODIFIER_REFINE_LEVEL then
			modifierEntry.refineLevel = (modifierEntry.refineLevel or 0) + 1
		end
	end

	g_game.sendWeaponProficiencyModifierAction(5, clientId, grade, slot)
end

function WeaponProficiency:confirmMaximise()
	local currentItem = self.displayItemWidget:getItem()

	if not currentItem or not self.selectedModifySlot then
		return
	end

	local grade = self.selectedModifySlot.grade
	local slot = self.selectedModifySlot.slot
	local clientId = self:getSelectedClientId()
	local cacheEntry = self.cacheList[clientId]

	if cacheEntry then
		local modifierEntry = getModifierEntry(cacheEntry.modifiers, grade, slot)

		if modifierEntry then
			modifierEntry.refineLevel = MAX_MODIFIER_REFINE_LEVEL
		end
	end

	g_game.sendWeaponProficiencyModifierAction(6, clientId, grade, slot)
end

function WeaponProficiency:requestReshape()
	local currentItem = self.displayItemWidget:getItem()

	if not currentItem or not self.selectedModifySlot then
		return
	end

	local grade = self.selectedModifySlot.grade
	local slot = self.selectedModifySlot.slot

	g_game.sendWeaponProficiencyModifierAction(7, self:getSelectedClientId(), grade, slot)
end

function WeaponProficiency:confirmReshapeReplace(optionIndex)
	local data = self.reshapeData

	if not data then
		return
	end

	local currentItem = self.displayItemWidget:getItem()

	if not currentItem then
		return
	end

	local clientId = self:getSelectedClientId()

	g_game.sendWeaponProficiencyModifierAction(8, clientId, data.grade, data.slot, optionIndex)

	if optionIndex >= 0 and optionIndex <= 2 then
		local option = data.options[optionIndex + 1]

		if option then
			local cacheEntry = self.cacheList[clientId]

			if cacheEntry then
				local modifierEntry = getModifierEntry(cacheEntry.modifiers, data.grade, data.slot)

				if modifierEntry then
					modifierEntry.modifierEnum = option.modifierEnum
					modifierEntry.refineLevel = option.refineLevel
				end
			end
		end
	end

	self.reshapeData = nil
end

function WeaponProficiency:closeReshapeDialog()
	local root = g_ui.getRootWidget()
	local dialog = root and root:recursiveGetChildById("reshapeDialog")

	if dialog then
		dialog:destroy()

		if g_modalManager then
			g_modalManager.hide(dialog)
		end
	end
end

function WeaponProficiency:openReshapeDialog()
	local data = self.reshapeData

	if not data then
		return
	end

	local root = g_ui.getRootWidget()

	if not root then
		return
	end

	local existing = root:recursiveGetChildById("reshapeDialog")

	if existing then
		existing:destroy()
	end

	local shape = root:recursiveGetChildById("shapeDialog")

	if shape and shape:isVisible() then
		shape:hide()

		if g_modalManager then
			g_modalManager.hide(shape)
		end
	end

	local dialog = g_ui.createWidget("ReshapeDialog", root)

	if not dialog then
		g_logger.error("[WeaponProficiency] Unable to create dialog style 'ReshapeDialog'.")
		self:returnToShapeDialog()
		return
	end

	dialog:setId("reshapeDialog")

	local modifierEntry = self:getSelectedModifierEntry()

	if not modifierEntry then
		local currentItem = self.displayItemWidget:getItem()
		local itemId = currentItem and currentItem:getId()
		local cacheEntry = itemId and self.cacheList[itemId]

		if cacheEntry then
			modifierEntry = getModifierEntry(cacheEntry.modifiers, data.grade, data.slot)
		end
	end

	if modifierEntry then
		populateReshapePerkPanel(dialog:recursiveGetChildById("currentPerkPanel"), modifierEntry.modifierEnum, modifierEntry.refineLevel)
	end

	local optionIds = {
		"reshapeOption1",
		"reshapeOption2",
		"reshapeOption3"
	}
	local replaceIds = {
		"reshapeReplace1",
		"reshapeReplace2",
		"reshapeReplace3"
	}

	for i, optionId in ipairs(optionIds) do
		local optionPanel = dialog:recursiveGetChildById(optionId)
		local option = data.options[i]
		local replaceContainer = dialog:recursiveGetChildById(replaceIds[i])

		if optionPanel and option then
			populateReshapePerkPanel(optionPanel, option.modifierEnum, option.refineLevel)
			optionPanel:setVisible(true)

			if replaceContainer then
				replaceContainer:setVisible(true)

				local replaceButton = replaceContainer:recursiveGetChildById("replaceButton")

				if replaceButton then
					function replaceButton.onClick()
						self:onReshapeOptionSelected(i - 1)
					end
				end
			end
		else
			if optionPanel then
				optionPanel:setVisible(false)
			end

			if replaceContainer then
				replaceContainer:setVisible(false)
			end
		end
	end

	dialog:show()

	if g_modalManager then
		g_modalManager.show(dialog)
	end
end

function WeaponProficiency:onReshapeDialogKeyBlock()
	return
end

function WeaponProficiency:onReshapeKeepClicked()
	self:confirmReshapeReplace(3)
	self:closeReshapeDialog()
	self:returnToShapeDialog()
end

function WeaponProficiency:onReshapeOptionSelected(optionIndex)
	local data = self.reshapeData

	if not data then
		return
	end

	local option = data.options[optionIndex + 1]

	if not option then
		return
	end

	local modifierEntry = self:getSelectedModifierEntry()

	if not modifierEntry then
		local currentItem = self.displayItemWidget:getItem()
		local itemId = currentItem and currentItem:getId()
		local cacheEntry = itemId and self.cacheList[itemId]

		if cacheEntry then
			modifierEntry = getModifierEntry(cacheEntry.modifiers, data.grade, data.slot)
		end
	end

	local currentModifier = modifierEntry and modifierEntry.modifierEnum

	if currentModifier and currentModifier == option.modifierEnum then
		self:confirmReshapeReplace(optionIndex)
		self:closeReshapeDialog()
		self:returnToShapeDialog()

		return
	end

	self:showReshapeReplaceConfirmDialog(optionIndex)
end

function WeaponProficiency:confirmClear()
	local currentItem = self.displayItemWidget:getItem()

	if not currentItem or not self.selectedModifySlot then
		return
	end

	local grade = self.selectedModifySlot.grade
	local slot = self.selectedModifySlot.slot
	local itemId = currentItem:getId()
	local cacheEntry = self.cacheList[itemId]

	if cacheEntry and cacheEntry.modifiers then
		for i = #cacheEntry.modifiers, 1, -1 do
			local modifier = cacheEntry.modifiers[i]

			if modifier.grade == grade and modifier.slot == slot then
				table.remove(cacheEntry.modifiers, i)

				break
			end
		end
	end

	g_game.sendWeaponProficiencyModifierAction(9, itemId, grade, slot)
	self:onUpdateSelectedProficiency(itemId)
end

function WeaponProficiency:returnToShapeDialog()
	local root = g_ui.getRootWidget()

	if not root then
		return
	end

	local shape = root:recursiveGetChildById("shapeDialog")

	if not shape then
		return
	end

	shape:show(true)
	shape:raise()
	shape:focus()

	if g_modalManager then
		g_modalManager.show(shape)
	end

	self:updateShapeResourceBalances(shape)
	self:updateShapePerkPreview(shape)
end

function WeaponProficiency:getSelectedModifierEntry()
	if not self.selectedModifySlot then
		return nil
	end

	local currentItem = self.displayItemWidget:getItem()
	local itemId = currentItem and currentItem:getId()
	local cacheEntry = itemId and self.cacheList[itemId]

	if not cacheEntry then
		return nil
	end

	return getModifierEntry(cacheEntry.modifiers, self.selectedModifySlot.grade, self.selectedModifySlot.slot)
end

local SUB_DIALOG_PARENTS = {
	reshapeReplaceConfirmDialog = "reshapeDialog",
	reshapeConfirmDialog = "shapeDialog",
	clearConfirmDialog = "shapeDialog",
	maximiseConfirmDialog = "shapeDialog",
	refineConfirmDialog = "shapeDialog",
	saveConfirmDialog = "weaponProficiencyWindow"
}

local function setProficiencyCostText(widget, cost, icon, action)
	if not widget then
		return
	end

	widget:setColoredText({
		string.format("Do you want to spend %d", cost), "#c0c0c0",
		icon, "#ffffff",
		string.format(" to %s this perk?", action), "#c0c0c0"
	})
end

local function showProficiencyConfirmDialog(self, config)
	local root = g_ui.getRootWidget()

	if not root then
		return
	end

	local parentId = config.parentDialogId or "shapeDialog"
	local parent = root:recursiveGetChildById(parentId)

	if config.checkButton then
		local btn = parent and parent:recursiveGetChildById(config.checkButton)

		if not btn or not btn:isEnabled() then
			return
		end
	elseif not parent then
		return
	end

	if parent then
		parent:hide()

		if g_modalManager then
			g_modalManager.hide(parent)
		end
	end

	local existing = root:recursiveGetChildById(config.dialogId)

	if existing then
		existing:destroy()
	end

	local dialog = g_ui.createWidget(config.widgetName, root)
	if not dialog then
		if parent then
			parent:show(true)

			if g_modalManager then
				g_modalManager.show(parent)
			end
		end

		g_logger.error(string.format("[WeaponProficiency] Unable to create dialog style '%s'.", config.widgetName))
		return
	end

	dialog:setId(config.dialogId)

	local titleLabel = dialog:recursiveGetChildById("title")

	if titleLabel then
		titleLabel:setText(tr(config.titleText))
	end

	if config.buildContent then
		config.buildContent(self, dialog)
	end

	local function doCancel()
		local dlg = root:recursiveGetChildById(config.dialogId)

		if dlg then
			dlg:destroy()

			if g_modalManager then
				g_modalManager.hide(dlg)
			end
		end

		if config.onCancel then
			config.onCancel(self, root)
		elseif parentId == "shapeDialog" then
			self:returnToShapeDialog()
		else
			local p = root:recursiveGetChildById(parentId)

			if p then
				p:show(true)
				p:raise()
				p:focus()

				if g_modalManager then
					g_modalManager.show(p)
				end
			end
		end
	end

	local yesButton = dialog:recursiveGetChildById("yesButton")
	local noButton = dialog:recursiveGetChildById("noButton")

	if yesButton then
		function yesButton.onClick()
			config.onConfirm(self, dialog, root)
		end
	end

	if noButton then
		function noButton.onClick()
			doCancel()
		end
	end

	dialog:show()

	if g_modalManager then
		g_modalManager.show(dialog)
	end
end

local function triggerConfirmDialogButton(dialogId, buttonId)
	local root = g_ui.getRootWidget()
	local dlg = root and root:recursiveGetChildById(dialogId)
	local btn = dlg and dlg:recursiveGetChildById(buttonId)

	if btn and btn.onClick then
		btn.onClick(btn)
	end
end

for dialogId, _ in pairs(SUB_DIALOG_PARENTS) do
	local baseName = dialogId:sub(1, 1):upper() .. dialogId:sub(2, -7)

	WeaponProficiency["on" .. baseName .. "DialogEnter"] = function()
		triggerConfirmDialogButton(dialogId, "yesButton")
	end
	WeaponProficiency["on" .. baseName .. "DialogCancel"] = function()
		triggerConfirmDialogButton(dialogId, "noButton")
	end
end

function WeaponProficiency:showRefineConfirmDialog()
	local modifierEntry = self:getSelectedModifierEntry()
	local refineLevel = modifierEntry and (modifierEntry.refineLevel or 0) or 0
	local dustCost = getShapeRefineDustCost(refineLevel)

	showProficiencyConfirmDialog(self, {
		dialogId = "refineConfirmDialog",
		checkButton = "shapeRefineButton",
		titleText = "Refine?",
		widgetName = "RefineConfirmDialog",
		buildContent = function(s, dialog)
			local ct = dialog:recursiveGetChildById("contentText")
			setProficiencyCostText(ct, dustCost, s.dustIconChar, "refine")
		end,
		onConfirm = function(s, dialog, root)
			s:confirmRefine()
			dialog:destroy()

			if g_modalManager then
				g_modalManager.hide(dialog)
			end

			s:returnToShapeDialog()
		end
	})
end

function WeaponProficiency:showMaximiseConfirmDialog()
	local orbCost = 1

	showProficiencyConfirmDialog(self, {
		dialogId = "maximiseConfirmDialog",
		checkButton = "shapeMaximiseButton",
		titleText = "Maximise?",
		widgetName = "MaximiseConfirmDialog",
		buildContent = function(s, dialog)
			local ct = dialog:recursiveGetChildById("contentText")
			setProficiencyCostText(ct, orbCost, s.orbIconChar, "maximise")
		end,
		onConfirm = function(s, dialog, root)
			s:confirmMaximise()
			dialog:destroy()

			if g_modalManager then
				g_modalManager.hide(dialog)
			end

			s:returnToShapeDialog()
		end
	})
end

function WeaponProficiency:showReshapeConfirmDialog()
	showProficiencyConfirmDialog(self, {
		dialogId = "reshapeConfirmDialog",
		checkButton = "shapeReshapeButton",
		titleText = "Reshape?",
		widgetName = "ReshapeConfirmDialog",
		buildContent = function(s, dialog)
			local ct = dialog:recursiveGetChildById("contentText")
			setProficiencyCostText(ct, SHAPE_RESHAPE_DUST_COST, s.dustIconChar, "reshape")
		end,
		onConfirm = function(s, dialog, root)
			s:requestReshape()
			dialog:destroy()

			if g_modalManager then
				g_modalManager.hide(dialog)
			end
		end
	})
end

function WeaponProficiency:showReshapeReplaceConfirmDialog(optionIndex)
	showProficiencyConfirmDialog(self, {
		dialogId = "reshapeReplaceConfirmDialog",
		parentDialogId = "reshapeDialog",
		titleText = "Reshape?",
		widgetName = "ReshapeReplaceConfirmDialog",
		buildContent = function(_, dialog)
			local ct = dialog:recursiveGetChildById("contentText")

			if ct then
				ct:setText(tr("Please confirm that you want to replace your current perk."))
			end
		end,
		onConfirm = function(s, dialog)
			dialog:destroy()

			if g_modalManager then
				g_modalManager.hide(dialog)
			end

			s:confirmReshapeReplace(optionIndex)
			s:closeReshapeDialog()
			s:returnToShapeDialog()
		end
	})
end

function WeaponProficiency:showClearConfirmDialog()
	showProficiencyConfirmDialog(self, {
		dialogId = "clearConfirmDialog",
		titleText = "Clear?",
		widgetName = "ClearConfirmDialog",
		buildContent = function(s, dialog)
			local ct = dialog:recursiveGetChildById("contentText")

			if ct then
				ct:setText(tr("Are you sure you want to clear this shaped perk? It will be reset to the original perk. You can modify and shape this perk again, but all current changes will be lost."))
			end
		end,
		onConfirm = function(s, dialog, root)
			s:confirmClear()
			dialog:destroy()

			if g_modalManager then
				g_modalManager.hide(dialog)
			end

			local shape = root:recursiveGetChildById("shapeDialog")

			if shape then
				shape:destroy()

				if g_modalManager then
					g_modalManager.hide(shape)
				end
			end

			s:returnToProficiencyWindow()
		end
	})
end

function WeaponProficiency:returnToProficiencyWindow()
	self.window:show(true)
	self.window:raise()
	self.window:focus()

	if g_modalManager then
		g_modalManager.show(self.window)
	end
end

function WeaponProficiency:onModifySubDialogEscape()
	local root = g_ui.getRootWidget()

	if not root then
		return
	end

	local reshape = root:recursiveGetChildById("reshapeDialog")

	if reshape then
		return
	end

	local shape = root:recursiveGetChildById("shapeDialog")

	if shape then
		shape:destroy()
		self:returnToProficiencyWindow()

		return
	end

	local dialog = root:recursiveGetChildById("modifyConfirmDialog")

	if dialog then
		dialog:destroy()
		self:returnToProficiencyWindow()
	end
end

function WeaponProficiency:onModifyConfirmDialogEnter()
	local root = g_ui.getRootWidget()

	if not root then
		return
	end

	local dialog = root:recursiveGetChildById("modifyConfirmDialog")

	if not dialog then
		return
	end

	self:confirmModify()
	dialog:destroy()
	self:returnToProficiencyWindow()
end

function WeaponProficiency:onModifyClick()
	local currentItem = self.displayItemWidget:getItem()

	if not currentItem or not self.selectedModifySlot then
		return
	end

	self:updateModifyButtonState()

	local modifyButton = self.modifyButton

	if not modifyButton or not modifyButton:isEnabled() then
		return
	end

	local cost = 250
	local currentItemId = currentItem:getId()
	local cacheEntry = self.cacheList[currentItemId]
	local modifiers = cacheEntry and cacheEntry.modifiers or {}

	if #modifiers >= 1 then
		cost = 1000
	end

	local function returnToProficiency()
		self:returnToProficiencyWindow()
	end

	local root = g_ui.getRootWidget()

	if not root then
		return
	end

	local selectedHasModifier = false
	local currentData = cacheEntry or {
		modifiers = {}
	}

	for _, m in ipairs(currentData.modifiers or {}) do
		if m.grade == self.selectedModifySlot.grade and m.slot == self.selectedModifySlot.slot then
			selectedHasModifier = true

			break
		end
	end

	if selectedHasModifier then
		local existing = root:recursiveGetChildById("shapeDialog")

		if existing then
			existing:destroy()
		end

		local shape = g_ui.createWidget("ShapeDialog", root)

		if not shape then
			g_logger.error("[WeaponProficiency] Unable to create dialog style 'ShapeDialog'.")
			return
		end

		shape:setId("shapeDialog")

		local modifierEntry = getModifierEntry(currentData.modifiers, self.selectedModifySlot.grade, self.selectedModifySlot.slot)
		local modifiedPerkData = modifierEntry and ProficiencyData:getModifierPerkData(modifierEntry.modifierEnum)
		local bonusName, bonusTooltip = "Modified Bonus", ""

		if modifiedPerkData then
			bonusName, bonusTooltip = ProficiencyData:getBonusNameAndTooltip(modifiedPerkData)
		end

		local displayName, titleTooltip = formatPerkBonusTitle(bonusName, SHAPE_PERK_TITLE_MAX_LEN, SHAPE_PERK_TITLE_TRUNCATED_LEN)
		local leftTitle = shape:recursiveGetChildById("leftTitle")

		if leftTitle then
			leftTitle:setText(displayName)
			leftTitle:setTooltip(titleTooltip)
		end

		local perkBonusText = shape:recursiveGetChildById("perkBonusText")

		if perkBonusText then
			perkBonusText:setText(bonusTooltip)
		end

		local perkPreview = shape:recursiveGetChildById("perkPreview")

		if modifiedPerkData then
			populateShapePerkPreview(perkPreview, modifiedPerkData, modifierEntry)
		end

		self:updateShapeResourceBalances()

		local infoBtn = shape:recursiveGetChildById("shapeInfoButton")

		if infoBtn then
			infoBtn:parseColoreDisplayToolTip(string.format("{Show all perk shaping options, #3f3f3f}\n\n{%s, #ffffff}{ Dust, #3f3f3f}\n{Lunar Ascension Orbs, #3f3f3f}", self.dustIconChar))
		end

		local closeBtn = shape:recursiveGetChildById("closeButton")

		if closeBtn then
			function closeBtn.onClick()
				self:onModifySubDialogEscape()
			end
		end

		local refineBtn = shape:recursiveGetChildById("shapeRefineButton")

		if refineBtn then
			function refineBtn.onClick()
				self:showRefineConfirmDialog()
			end
		end

		local maximiseBtn = shape:recursiveGetChildById("shapeMaximiseButton")

		if maximiseBtn then
			function maximiseBtn.onClick()
				self:showMaximiseConfirmDialog()
			end
		end

		local reshapeBtn = shape:recursiveGetChildById("shapeReshapeButton")

		if reshapeBtn then
			function reshapeBtn.onClick()
				self:showReshapeConfirmDialog()
			end
		end

		local clearBtn = shape:recursiveGetChildById("shapeClearButton")

		if clearBtn then
			function clearBtn.onClick()
				self:showClearConfirmDialog()
			end
		end

		self.window:hide()

		if g_modalManager then
			g_modalManager.hide(self.window)
		end

		shape:show()

		if g_modalManager then
			g_modalManager.show(shape)
		end

		return
	end

	local dialog = root:recursiveGetChildById("modifyConfirmDialog")

	if dialog then
		dialog:destroy()
	end

	dialog = g_ui.createWidget("ModifyConfirmDialog", root)

	if not dialog then
		g_logger.error("[WeaponProficiency] Unable to create dialog style 'ModifyConfirmDialog'.")
		return
	end

	dialog:setId("modifyConfirmDialog")

	local titleLabel = dialog:recursiveGetChildById("title")

	if titleLabel then
		titleLabel:setText(tr("Modify?"))
	end

	local contentText = dialog:recursiveGetChildById("contentText")
	setProficiencyCostText(contentText, cost, self.dustIconChar, "modify")

	local yesButton = dialog:recursiveGetChildById("yesButton")
	local noButton = dialog:recursiveGetChildById("noButton")

	if yesButton then
		function yesButton.onClick()
			self:onModifyConfirmDialogEnter()
		end
	end

	if noButton then
		function noButton.onClick()
			self:onModifySubDialogEscape()
		end
	end

	self.window:hide()

	if g_modalManager then
		g_modalManager.hide(self.window)
	end

	dialog:show()

	if g_modalManager then
		g_modalManager.show(dialog)
	end
end

function WeaponProficiency:onResetWeapon(button)
	if not canChangeWeaponPerks() or not button:isOn() then
		return
	end

	local currentItem = self.displayItemWidget:getItem()

	if not currentItem then
		return
	end

	local weaponEntry = self.cacheList[currentItem:getId()] or {}
	local perksSize = table.size(weaponEntry.perks)

	button:setOn(false)
	self.applyButton:setOn(perksSize > 0)
	self.okButton:setOn(perksSize > 0)
	button:setTooltip("You don't have any perks to reset.")

	if perksSize > 0 then
		local text = "Apply changes to your perks"

		self.applyButton:setTooltip(text)
		self.okButton:setTooltip(text)
		self.closeButton:setText("Cancel")

		self.saveWeaponMissing = true
	else
		local text = "No changes have been made to your perks."

		self.applyButton:setTooltip(text)
		self.okButton:setTooltip(text)
		self.closeButton:setText("Close")
	end

	for i, child in ipairs(self.perkPanel:getChildren()) do
		local bonusDetail = self.bonusDetailPanel:getChildById("bonusDetail_" .. i)

		for index, widget in pairs(child.currentPerkPanel:getChildren()) do
			widget:getChildById("locked-perk"):setVisible(false)

			if widget.active then
				widget.blocked = false
				widget.locked = false
				widget.active = false

				local borderWidget = widget:getChildById("border")
				local hightLightWidget = widget:getChildById("highlight")

				disableBonusIcon(widget, hightLightWidget, borderWidget, bonusDetail:recursiveGetChildById("bonusName"), widget.perkData)
			end
		end
	end
end

function WeaponProficiency:onCloseWindow(button)
	button = button or self.closeButton

	if button and button:getText() == "Close" then
		hide()

		local inspectMod = modules.game_inspect

		if inspectMod and inspectMod.returnToCharacterInspect then
			inspectMod.returnToCharacterInspect()
		end

		return true
	end

	self:onCloseMessage(true)
end

function WeaponProficiency:onEscapeWindow()
	if self.closeWindowEvent then
		return true
	end

	self.closeWindowEvent = addEvent(closeWindowDeferred)
	return true
end

function WeaponProficiency:onCloseMessage(userClosingWindow, targetItem, callbackFunction)
	self.warningWindow = nil

	if g_modalManager then
		g_modalManager.hide(self.window)
	end

	self.window:hide()

	local function doSaveCallback()
		self:onApplyChanges(nil, targetItem)

		if not userClosingWindow then
			if callbackFunction then
				callbackFunction()
			end

			self.window:show()

			if g_modalManager then
				g_modalManager.show(self.window)
			end
		else
			modules.game_console.getConsole():focus()
			modules.game_interface.getRootPanel():focus()

			local inspectMod = modules.game_inspect

			if inspectMod and inspectMod.returnToCharacterInspect then
				inspectMod.returnToCharacterInspect()
			end
		end

		self.saveWeaponMissing = false
	end

	local function doCancelCallback()
		self.saveWeaponMissing = false

		if not userClosingWindow then
			self.window:show()

			if g_modalManager then
				g_modalManager.show(self.window)
			end

			if callbackFunction then
				callbackFunction()
			end
		else
			modules.game_console.getConsole():focus()
			modules.game_interface.getRootPanel():focus()

			local inspectMod = modules.game_inspect

			if inspectMod and inspectMod.returnToCharacterInspect then
				inspectMod.returnToCharacterInspect()
			end
		end
	end

	showProficiencyConfirmDialog(self, {
		dialogId = "saveConfirmDialog",
		parentDialogId = "weaponProficiencyWindow",
		titleText = "Save?",
		widgetName = "SaveConfirmDialog",
		buildContent = function(s, dialog)
			local ct = dialog:recursiveGetChildById("contentText")

			if ct then
				ct:setText(tr("You did not save the changes you have made to your perks. Would you like to save your perks?"))
			end
		end,
		onConfirm = function(s, dialog, root)
			s.warningWindow = nil

			dialog:destroy()

			if g_modalManager then
				g_modalManager.hide(dialog)
			end

			doSaveCallback()
		end,
		onCancel = function(s, root)
			s.warningWindow = nil

			doCancelCallback()
		end
	})

	self.warningWindow = g_ui.getRootWidget() and g_ui.getRootWidget():recursiveGetChildById("saveConfirmDialog")
end

function WeaponProficiency:checkPerksMatch(itemId)
	local cacheEntry = self.cacheList[itemId]
	local cachePerks = cacheEntry and cacheEntry.perks or {}
	local allPerksMatch = true

	for levelIndex, perkRow in ipairs(self.perkPanel:getChildren()) do
		local expectedPerk = cachePerks[levelIndex - 1]
		local foundActive

		for perkIndex, widget in pairs(perkRow.currentPerkPanel:getChildren()) do
			if widget.active then
				foundActive = perkIndex - 1

				break
			end
		end

		if expectedPerk ~= nil and foundActive ~= expectedPerk then
			allPerksMatch = false

			break
		elseif expectedPerk == nil and foundActive ~= nil then
			allPerksMatch = false

			break
		end
	end

	if canChangeWeaponPerks() and not allPerksMatch then
		self.resetButton:setOn(true)
		self.resetButton:setTooltip("Reset your perks")
	end

	local tooltip = allPerksMatch and "No changes have been made to your perks." or "Apply changes to your perks"

	self.applyButton:setOn(not allPerksMatch)
	self.okButton:setOn(not allPerksMatch)
	self.applyButton:setTooltip(tooltip)
	self.okButton:setTooltip(tooltip)
	self.closeButton:setText(not allPerksMatch and "Cancel" or "Close")

	self.saveWeaponMissing = not allPerksMatch
end
