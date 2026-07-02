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

	WeaponProficiency.itemList = {}
	WeaponProficiency.cacheList = {} -- [itemId] = {experience, perks}

	WeaponProficiency.allProficiencyRequested = false
	WeaponProficiency.firstItemRequested = nil

	WeaponProficiency.saveWeaponMissing = false

	WeaponProficiency.ItemCategory = {
		Axes = 17, Clubs = 18, DistanceWeapons = 19,
		Swords = 20, WandsRods = 21, FistWeapons = 27,
	}
	WeaponProficiency.perkPanelsName = {
		"oneBonusIconPanel", "twoBonusIconPanel",
		"threeBonusIconPanel"
	}
	WeaponProficiency.filters = {
		["levelButton"] = false,
		["vocButton"] = false,
		["oneButton"] = false,
		["twoButton"] = false,
	}

	-- Scrollable settings
	WeaponProficiency.listWidgetHeight = 34 -- 34x34
	WeaponProficiency.listCapacity = 0
	WeaponProficiency.listMinWidgets = 0
	WeaponProficiency.listMaxWidgets = 0
	WeaponProficiency.offset = 0
	WeaponProficiency.listPool = {}
	WeaponProficiency.listData = {}
end

function isAvailable()
	return type(g_things.getProficiencyThings) == "function"
end

function init()
	if not isAvailable() then
		g_logger.warning("Weapon proficiency disabled: missing g_things.getProficiencyThings in this client build.")
		return
	end

	WeaponProficiency.window = g_ui.displayUI('weapon_proficiency')
	WeaponProficiency.displayItemPanel = WeaponProficiency.window:recursiveGetChildById("itemPanel")
	WeaponProficiency.perkPanel = WeaponProficiency.window:recursiveGetChildById("bonusProgressBackground")
	WeaponProficiency.bonusDetailPanel = WeaponProficiency.window:recursiveGetChildById("bonusDetailBackground")
	WeaponProficiency.optionFilter = WeaponProficiency.window:recursiveGetChildById("classFilter")
	WeaponProficiency.starProgressPanel = WeaponProficiency.window:recursiveGetChildById("starsPanelBackground")
	WeaponProficiency.itemListScroll = WeaponProficiency.window:recursiveGetChildById("itemListScroll")
	WeaponProficiency.vocationWarning = WeaponProficiency.window:recursiveGetChildById("vocationWarning")
	WeaponProficiency.window:hide()

	connect(g_game, {
		onInspection = onInspection,
		onGameStart = onGameStart,
		onGameEnd = onGameEnd,
		onWeaponProficiency = onWeaponProficiency,
		onWeaponProficiencyExperience = onWeaponProficiencyExperience,
		onProficiencyNotification = onProficiencyNotification
	})
	connect(g_things, { onLoadDat = loadProficiencyJson })

	-- onLoadDat is emitted while the appearances load at boot, BEFORE this
	-- sandboxed mod's @onLoad init() runs, so the event has already passed and
	-- loadProficiencyJson -> createItemCache would never fire, leaving the item
	-- grid permanently empty. If the dat is already loaded, prime the cache once
	-- now (mirrors modules/game_offsets/offsets.lua). The window exists by this
	-- point, so createItemCache's recursiveGetChildById('itemList') is valid.
	if modules.game_things and modules.game_things.isLoaded and modules.game_things.isLoaded() then
		loadProficiencyJson()
	end
end

function terminate()
	if not isAvailable() then
		return
	end

	disconnect(g_game, {
		onInspection = onInspection,
		onGameStart = onGameStart,
		onGameEnd = onGameEnd,
		onWeaponProficiency = onWeaponProficiency,
		onWeaponProficiencyExperience = onWeaponProficiencyExperience,
		onProficiencyNotification = onProficiencyNotification
	})
	disconnect(g_things, { onLoadDat = loadProficiencyJson })
end

function onGameStart()
	WeaponProficiency.allProficiencyRequested = false
	WeaponProficiency.saveWeaponMissing = false
	WeaponProficiency.firstItemRequested = nil

	-- Rebuild the client-side item grid on login if the boot-time prime was
	-- skipped (dat not yet loaded when init() ran). Matches the reference
	-- koliseu-otc proficiency.lua which calls createItemCache() on game start.
	-- NOTE: check the actual weapon list, not the outer itemList table —
	-- createItemCache always seeds itemList[WeaponsAll]={} + the category keys,
	-- so the outer table is never empty after a (possibly premature) first run;
	-- guarding on it would pin an empty grid forever.
	if isAvailable() and table.empty(WeaponProficiency.itemList[MarketCategory.WeaponsAll]) then
		loadProficiencyJson()
	end
end

function onGameEnd()
	if not WeaponProficiency.window then
		g_client.setInputLockWidget(nil)
		return
	end

	WeaponProficiency.window:hide()
	WeaponProficiency:reset()

	if WeaponProficiency.warningWindow then
		WeaponProficiency:destroy()
		WeaponProficiency.warningWindow = nil
	end
	g_client.setInputLockWidget(nil)
end

function loadProficiencyJson()
	if not isAvailable() then
		return
	end

	ProficiencyData:loadProficiencyJson()
end

function show()
	if not isAvailable() or not WeaponProficiency.window then
		return
	end

	WeaponProficiency.window:show(true)
	WeaponProficiency.window:raise()
	WeaponProficiency.window:focus()
end

function hide()
	if not isAvailable() or not WeaponProficiency.window then
		return
	end

	WeaponProficiency.window:hide()
end

function getUnknownMarketCategory(itemType)
	return UnknownCategories[itemType:getWeaponType()]
end

function sortWeaponProficiency(marketCategory)
	local itemList = WeaponProficiency.itemList[marketCategory]
	if not itemList then return end

	table.sort(itemList, function(a, b)
		local idA, idB = a.marketData.showAs, b.marketData.showAs

		local expA = WeaponProficiency.cacheList[idA] and WeaponProficiency.cacheList[idA].exp or 0
		local expB = WeaponProficiency.cacheList[idB] and WeaponProficiency.cacheList[idB].exp or 0

		if expA == expB then
			return a.marketData.name:lower() < b.marketData.name:lower()
		end
		return expA > expB
	end)
end

function requestOpenWindow(redirectItem)
	if not isAvailable() or not WeaponProficiency.window then
		return
	end

	-- Self-heal: if the weapon list was never built (boot/login prime skipped
	-- because the dat wasn't loaded yet, OR built prematurely while empty),
	-- build it now so the panel is never blank. Check the actual WeaponsAll
	-- list, not the outer itemList table (which always has the category keys).
	if table.empty(WeaponProficiency.itemList[MarketCategory.WeaponsAll]) then
		loadProficiencyJson()
	end

	local category = "Weapons: All"
	local targetItemId = nil
	local leftSlotItem = modules.game_inventory.getLeftSlotItem()

	-- Default open: stay on "Weapons: All" (full 705-weapon list, no vocation
	-- filter) and merely FOCUS the equipped weapon inside it. Switching the
	-- category to the equipped weapon's class (e.g. "Fist") would both narrow
	-- the grid to a near-empty class AND turn on the vocation filter, leaving
	-- the panel blank. Explicit redirects below still open the clicked class.
	if leftSlotItem then
		targetItemId = leftSlotItem:getId()
	end

	if redirectItem then
		local resolved = WeaponCategoryToString[getUnknownMarketCategory(redirectItem)]
		if resolved then
			category = resolved
			targetItemId = redirectItem:getId()
		end
	end

	if WeaponProficiency.firstItemRequested then
		local resolved = WeaponCategoryToString[getUnknownMarketCategory(WeaponProficiency.firstItemRequested)]
		if resolved then
			category = resolved
			targetItemId = WeaponProficiency.firstItemRequested:getId()
		end
		WeaponProficiency.firstItemRequested = nil
	end

	if not WeaponProficiency.allProficiencyRequested then
		g_game.sendWeaponProficiencyAction(1) -- request all weapons
		WeaponProficiency.allProficiencyRequested = true
		WeaponProficiency.firstItemRequested = redirectItem
	end

	local focusFirstChild = false
	local focusVocation = (category ~= "Weapons: All")
	if not focusVocation then
		focusFirstChild = true
		sortWeaponProficiency(MarketCategory.WeaponsAll)
	end

	WeaponProficiency.filters["vocButton"] = focusVocation 
	WeaponProficiency.window:recursiveGetChildById("vocButton"):setChecked(focusVocation, true)

	WeaponProficiency:onClearSearch(true)
	WeaponProficiency:onWeaponCategoryChange(category, nil, targetItemId, focusFirstChild)

	g_client.setInputLockWidget(WeaponProficiency.window)
	show()
end

function onInspection(inspectType, itemName, item, descriptions)
	if inspectType ~= 2 or not isAvailable() or not WeaponProficiency.window then
		return
	end

	local infoWidget = WeaponProficiency.window:recursiveGetChildById("infoWidget")
	local text = itemName
	for _, data in pairs(descriptions) do
		text = text .. string.format("\n%s: %s", data.detail, wrapTextByWords(data.description, 52))
	end

	if not WeaponProficiency.allProficiencyRequested then
		WeaponProficiency.allProficiencyRequested = true
		requestOpenWindow()
	end

	infoWidget:setTooltip(text)
end

function onWeaponProficiency(itemId, experience, perks)
	WeaponProficiency.cacheList[itemId] = { exp = experience, perks = perks}
	-- The server 0xC4 carries no market category; derive it locally from the thing type.
	local thingType = g_things.getThingType(itemId, ThingCategoryItem)
	if thingType then
		sortWeaponProficiency(thingType:getMarketData().category)
	end
	WeaponProficiency:onUpdateSelectedProficiency(itemId)
end

function onWeaponProficiencyExperience(itemId, experience, hasUnnusedPerk)
	local thingType = g_things.getThingType(itemId, ThingCategoryItem)
	if not thingType then
		return
	end
	onProficiencyNotification(itemId, experience, hasUnnusedPerk, thingType)
end

function onProficiencyNotification(itemId, experience, hasUnnusedPerk, thingType)
	local itemCache = WeaponProficiency.cacheList[itemId]
	if not itemCache then
		WeaponProficiency.cacheList[itemId] = { exp = experience, perks = {} }
	else
		if experience > 0 then
			itemCache.exp = experience
		end
	end

	sortWeaponProficiency(thingType:getMarketData().category)
	modules.game_topbar.onUpdateProficiencyData(WeaponProficiency.cacheList[itemId], hasUnnusedPerk, thingType)
end

---------------------------
----- Local Functions -----
---------------------------
local function canChangeWeaponPerks()
	local player = g_game.getLocalPlayer()
	if not player or not g_game.isOnline() then
		return false
	end
	return true
end

local function isMasteryAchieved(targetItem)
	if not targetItem then
		return false
	end
	
	local maxExperience = ProficiencyData:getMaxExperience(ProficiencyData:getPerkLaneCount(targetItem:getProficiencyId()), targetItem)
	local weaponEntry = WeaponProficiency.cacheList[targetItem:getId()]
	local currentExperience = weaponEntry and weaponEntry.exp or 0

	return currentExperience >= maxExperience
end

local function enableBonusIcon(bonusIcon, iconGrey, hightLightWidget, borderWidget, bonusDescWidget, bonusTooltip, augmentIconDarker, perkData)
	if bonusIcon.blocked or bonusIcon.active or bonusIcon.locked then
		return true
	end

	local visible = not iconGrey:isVisible()

	iconGrey:setVisible(false)
	hightLightWidget:setVisible(true)
	borderWidget:setImageSource("/images/game/proficiency/border-weaponmasterytreeicons-active")

	bonusDescWidget:setImageSource("")
	bonusDescWidget:setText(bonusTooltip)
	if bonusDescWidget:getWrappedLinesCount() > 4 then
		bonusDescWidget:setText(short_text(bonusTooltip, 57))
		bonusDescWidget:setTooltip(bonusTooltip)
	end

	if perkData.Type == PERK_SPELL_AUGMENT then
		augmentIconDarker:setVisible(false)
	end

	bonusIcon.active = true
end

local function disableBonusIcon(iconGrey, hightLightWidget, borderWidget, bonusDescWidget, augmentIconDarker, perkData)
	iconGrey:setVisible(true)
	iconGrey:setOpacity(1)
	hightLightWidget:setVisible(false)
	borderWidget:setImageSource("/images/game/proficiency/border-weaponmasterytreeicons-inactive")

	bonusDescWidget:setImageSource("/images/game/proficiency/icon-lock-grey")
	bonusDescWidget:setText("")
	bonusDescWidget:removeTooltip()

	if perkData.Type == PERK_SPELL_AUGMENT then
		augmentIconDarker:setVisible(true)
		augmentIconDarker:setOpacity(1)
	end
end

local function disableOtherBonusIcons(currentPerkPanel, currentBonusIcon)
	for i = 0, 2 do
		local bonusIcon = currentPerkPanel:getChildById("bonusIcon" .. i)
		if bonusIcon and bonusIcon ~= currentBonusIcon and bonusIcon.active then
			bonusIcon.blocked = false
			bonusIcon.active = false
			local iconGrey = bonusIcon:getChildById("icon-grey")
			local hightLightWidget = bonusIcon:getChildById("highlight")
			local borderWidget = bonusIcon:getChildById("border")
			local augmentIconDarker = bonusIcon:getChildById("iconPerks-grey")
			local augmentIcon = bonusIcon:getChildById("iconPerks")

			iconGrey:setVisible(true)
			iconGrey:setOpacity(1)
			hightLightWidget:setVisible(false)
			borderWidget:setImageSource("/images/game/proficiency/border-weaponmasterytreeicons-inactive")
			if augmentIcon:isVisible() then
				augmentIconDarker:setVisible(true)
				augmentIconDarker:setOpacity(1)
			end
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
		local iconTypo = isMasteryAchieved(itemType) and "gold" or "silver"
		starWidget:getChildById("star"):setImageSource(string.format("/images/store/icon-star-%s", iconTypo))
		for _, widget in pairs(child.currentPerkPanel:getChildren()) do
			widget.blocked = false
		end
	end
end

-- Weapon categories a vocation can use, keyed by translateWheelVocation()
-- (1 knight, 2 paladin, 3 sorcerer, 4 druid, 5 monk). The market field
-- restrict_to_profession is set on only ~45/708 weapons, so the Voc filter must
-- derive usability from the weapon TYPE (category) like the CIP client does.
-- Category ids: Axes=17, Clubs=18, DistanceWeapons=19, Swords=20, WandsRods=21,
-- FistWeapons=27 (see WeaponProficiency.ItemCategory).
local VocationWeaponCategories = {
	[1] = { [20] = true, [17] = true, [18] = true, [27] = true }, -- knight
	[2] = { [19] = true },                                        -- paladin
	[3] = { [21] = true },                                        -- sorcerer (wands)
	[4] = { [21] = true },                                        -- druid (rods)
	[5] = { [27] = true },                                        -- monk
}

local function checkSortOptions(itemData)
	local player = g_game.getLocalPlayer()
	if not player then
		return false
	end

	local playerLevel = player:getLevel()
	local playerVocation = translateWheelVocation(player:getVocation())

	if WeaponProficiency.filters["levelButton"] then
		-- weapon-USE level (AppearanceFlags minimum_level field 63), same source as the
		-- requirements warning; not the market's own minimum_level (field 6).
		if itemData.thingType:getMinimumLevel() > playerLevel then
			return false
		end
	end

	if WeaponProficiency.filters["vocButton"] then
		-- Primary: weapon type must be usable by the player's vocation.
		local allowed = VocationWeaponCategories[playerVocation]
		if allowed and not allowed[itemData.marketData.category] then
			return false
		end
		-- WandsRods (cat 21) share both category AND weapon_type (WAND_ROD) for
		-- sorcerers and druids, so neither distinguishes them. Tibia item names
		-- do: sorcerer wands contain "wand", druid rods contain "rod".
		if itemData.marketData.category == 21 then
			local name = (itemData.marketData.name or ""):lower()
			if playerVocation == 3 and name:find("rod") then  -- sorcerer: hide rods
				return false
			elseif playerVocation == 4 and name:find("wand") then  -- druid: hide wands
				return false
			end
		end
		-- Secondary: honour an explicit vocation restriction when the item has one.
		-- Same weapon-USE source as the requirements warning (AppearanceFlags field 62,
		-- VOCATION enum with monk=5), not the market's restrict_to_profession (no monk).
		local itemVocation = itemData.thingType:getRestrictVocations()
		if #itemVocation > 0 and not table.contains(itemVocation, playerVocation) then
			return false
		end
	end

	if WeaponProficiency.filters["oneButton"] then
		if itemData.thingType:getClothSlot() ~= 6 then
			return false
		end
	end

	if WeaponProficiency.filters["twoButton"] then
		if itemData.thingType:getClothSlot() ~= 0 then
			return false
		end
	end
	return true
end

local function setupPerkIconGrey(perkData, iconSource, iconClip, iconGrey, augmentIconNormal, augmentIconDarker)
	if perkData.Type == PERK_SPELL_AUGMENT then
		iconGrey:setImageSource(string.format("%s-off", iconSource))
		iconGrey:setImageClip(string.format("%s 64 64", iconClip))
		local augmentIconClip = ProficiencyData:getAugmentIconClip(perkData)
		augmentIconNormal:setVisible(true)
		augmentIconDarker:setVisible(true)
		augmentIconNormal:setImageClip(string.format("%s 32 32", augmentIconClip))
		local x = tonumber(augmentIconClip:match("^(%d+)")) or 0
		augmentIconDarker:setImageClip(string.format("%d 32 32 32", x))
	else
		local x = tonumber(iconClip:match("^(%d+)")) or 0
		iconGrey:setImageSource(iconSource)
		iconGrey:setImageClip(string.format("%d 64 64 64", x))
	end
end

local function createHoverHandler(bonusIcon, iconGrey, augmentIconDarker)
	return function(widget, hovered)
		if not bonusIcon.active and not bonusIcon.locked and not bonusIcon.blocked then
			local opacity = hovered and 0.5 or 1
			iconGrey:setOpacity(opacity)
			augmentIconDarker:setOpacity(opacity)
		end
		g_tooltip.onWidgetHoverChange(widget, hovered)
	end
end

local function createClickHandler(bonusIcon, currentPerkPanel, bonusDetail, hightLightWidget, borderWidget, iconGrey, augmentIconDarker, bonusTooltip, perkData, itemId)
	return function()
		if bonusIcon.blocked or bonusIcon.active or bonusIcon.locked then return end
		disableOtherBonusIcons(currentPerkPanel, bonusIcon)
		enableBonusIcon(bonusIcon, iconGrey, hightLightWidget, borderWidget, bonusDetail:recursiveGetChildById("bonusName"), bonusTooltip, augmentIconDarker, perkData)
		WeaponProficiency:checkPerksMatch(itemId)
	end
end

----------------------------
------ Core Functions ------
----------------------------
function WeaponProficiency:reset()
	self.cacheList = {}
	self.allProficiencyRequested = false
end

function WeaponProficiency:updateMainButtons(currentData)
	local enableReset = canChangeWeaponPerks() and table.size(currentData.perks) > 0
	local resetButton = self.window:getChildById("reset")
	local applyButton = self.window:getChildById("apply")
	local okButton = self.window:getChildById("ok")
	local closeButton = self.window:getChildById("close")

	resetButton:setOn(enableReset)
	applyButton:setOn(false)
	okButton:setOn(false)

	local resetTooltip = "Reset your perks"
	if not canChangeWeaponPerks() then
		resetTooltip = "You can only reset your perks in a protection zone."
	elseif table.empty(currentData.perks) then
		resetTooltip = "You don't have any perks to reset."
	end

	resetButton:setTooltip(resetTooltip)
	applyButton:setTooltip("No changes have been made to your perks.")
	closeButton:setText("Close")
end

function WeaponProficiency:createItemCache()
	if not isAvailable() then
		return
	end

	self.itemList[MarketCategory.WeaponsAll] = {}
	for _, v in pairs(self.ItemCategory) do
		self.itemList[v] = {}
	end

	local types = g_things.getProficiencyThings()
	local itemList = self.window:recursiveGetChildById("itemList")
	for index, itemType in pairs(types) do
		local item = Item.create(itemType:getId())
		local marketData = itemType:getMarketData()

		if not table.empty(marketData) then
			if self.itemList[marketData.category] == nil then
				marketData.category = getUnknownMarketCategory(itemType)
				marketData.showAs = itemType:getId()
			end

			item:setId(marketData.showAs)
			if string.empty(marketData.name) then
				marketData.name = g_things.getCyclopediaItemName(itemType:getId())
			end

			local marketItem = { displayItem = item, thingType = itemType, marketData = marketData }
			-- Guard: an item whose resolved category is not one of the proficiency weapon
			-- categories (e.g. unmapped weapon type) must be skipped, not crash the load.
			local categoryList = self.itemList[marketData.category]
			if categoryList then
				table.insert(categoryList, marketItem)
				table.insert(self.itemList[MarketCategory.WeaponsAll], marketItem)
			end
		end
	end

	local function sortByName(a, b)
		local nameA = a.marketData.name:lower()
		local nameB = b.marketData.name:lower()
		return nameA < nameB
	end

	for _, v in pairs(self.itemList) do
		table.sort(v, sortByName)
	end
end

function WeaponProficiency:onItemListValueChange(scroll, value, delta)
	if value == self.oldScrollValue then
		return
	end

	self.oldScrollValue = value
	local itemListWidget = self.window:recursiveGetChildById("itemList")

	-- Special case with half visible lines
	if #self.listData > 30 and #self.listData <= 35 then
    	itemListWidget:setVirtualOffset({x = 0, y = (delta > 0 and 8 or 0)})
		return true
	end

    local itemsPerRow = 5
    local rowsVisible = 8
    local itemsVisible = itemsPerRow * rowsVisible
    local totalItems = #self.listData

    local startLabel = (value * itemsPerRow) + 1
    local endLabel = startLabel + itemsVisible - 1

    local currentWidgetIndex = startLabel

    self.offset = self.offset + ((value % 5) * 2)

    if self.offset > 64 or value == 0 then
        self.offset = 0
    end

    if endLabel >= totalItems then
        self.offset = 7
    end

    itemListWidget:setVirtualOffset({x = 0, y = self.offset})

	local currentItem = self.displayItemPanel:getChildById("item"):getItem()

    for k, widget in pairs(itemListWidget:getChildren()) do
        if currentWidgetIndex > totalItems then
            widget:setVisible(false)
            goto continue
        end

        local entry = self.listData[currentWidgetIndex]
        if not entry then
            widget:setVisible(false)
            goto continue
        end

        widget:getChildById("item"):setItem(entry.displayItem)
        widget:setTooltip(entry.marketData.name)
        widget.cache = entry

        widget:setVisible(true)

		if widget:isFocused() then
			itemListWidget:focusChild(nil, MouseFocusReason, false, true)
		end

		if currentItem and currentItem:getId() == entry.marketData.showAs then
			itemListWidget:focusChild(widget, MouseFocusReason, false, true)
		end

		-- Check experience/stars
		local cacheEntry = self.cacheList[entry.marketData.showAs] or nil
		local weaponLevel = ProficiencyData:getCurrentLevelByExp(entry.displayItem, (cacheEntry and cacheEntry.exp or 0))
		local starPanel = widget:getChildById("starsBackground")

		local mastery = isMasteryAchieved(entry.displayItem)
		starPanel:destroyChildren()
		if weaponLevel > 0 then
			for i = 1, weaponLevel do
				local _star = g_ui.createWidget("MiniStar", starPanel)
				if mastery then
					_star:setImageSource("/images/game/proficiency/icon-star-tiny-gold")
				end
			end
		end

        currentWidgetIndex = currentWidgetIndex + 1
        :: continue ::
    end
end

function WeaponProficiency:onWeaponCategoryChange(selected, searchText, targetItemId, focusFirstChild, fromOptionChange)
	local weaponCategory = WeaponStringToCategory[selected]
	if not weaponCategory then
		-- never leave the grid blank for an unknown/nil category: fall back to All
		selected = "Weapons: All"
		weaponCategory = WeaponStringToCategory[selected]
	end

	sortWeaponProficiency(weaponCategory)

	-- Update current filter without propagation
	self.optionFilter:setCurrentOption(selected, true)
	
	local targetWidget = nil
	local itemListWidget = self.window:recursiveGetChildById("itemList")
	local currentItem = self.displayItemPanel:getChildById("item"):getItem()

	itemListWidget.onChildFocusChange = nil

	self.listCapacity = ((math.floor(itemListWidget:getHeight() / self.listWidgetHeight)) + 2) * 5
    self.listMinWidgets = 0
	self.oldScrollValue = 0
    self.listPool = {}
    self.listData = {}

	-- Generate the filtred list
	for _, data in pairs(self.itemList[weaponCategory]) do
		if not checkSortOptions(data) then
			goto continue
		end
	
		if searchText and not string.empty(searchText) and not matchText(searchText:lower(), data.marketData.name:lower()) then
			goto continue
		end

		table.insert(self.listData, data)
		:: continue ::
	end

	local currentIndex = 0
	for _, data in pairs(self.listData) do
		if #self.listPool >= self.listCapacity then
            break
        end

		local widget = itemListWidget:recursiveGetChildById("widget_" .. currentIndex)
		if not widget or not checkSortOptions(data) then
			goto continue
		end
	
		if searchText and not string.empty(searchText) and not matchText(searchText:lower(), data.marketData.name:lower()) then
			goto continue
		end

		widget:getChildById("item"):setItem(data.displayItem)
		widget:setVisible(true)
		widget:setTooltip(data.marketData.name)
		widget.cache = data

		if not targetWidget then
			if targetItemId and targetItemId == data.marketData.showAs then
				targetWidget = widget
			elseif fromOptionChange and not focusFirstChild and currentItem and currentItem:getId() == data.marketData.showAs then
				targetWidget = widget
			end
		end

		-- Check experience/stars
		local cacheEntry = self.cacheList[data.marketData.showAs] or nil
		local weaponLevel = ProficiencyData:getCurrentLevelByExp(data.displayItem, (cacheEntry and cacheEntry.exp or 0)) -- missing vocation
		local starPanel = widget:getChildById("starsBackground")

		starPanel:destroyChildren()
		local mastery = isMasteryAchieved(data.displayItem)
		if weaponLevel > 0 then
			for i = 1, weaponLevel do
				local _star = g_ui.createWidget("MiniStar", starPanel)
				if mastery then
					_star:setImageSource("/images/game/proficiency/icon-star-tiny-gold")
				end
			end
		end

		currentIndex = currentIndex + 1
		table.insert(self.listPool, widget)
		:: continue ::
	end

	for i = currentIndex, self.listCapacity do
        local widget = itemListWidget:recursiveGetChildById("widget_" .. i)
        if widget then
            widget:setVisible(false)
        end
    end

	self.listMaxWidgets = math.ceil((#self.listData / 5) - 7)
	local specialListSize = false
	if #self.listData > 30 and #self.listData <= 35 then
		self.listMaxWidgets = 1
		specialListSize = true
	end

    self.itemListScroll:setValue(0)
    self.itemListScroll:setMinimum(self.listMinWidgets)
    self.itemListScroll:setMaximum(math.max(0, self.listMaxWidgets))
    self.itemListScroll.onValueChange = function(list, value, delta) self:onItemListValueChange(list, value, delta) end

	self.itemListScroll:setVisibleItems(specialListSize and 9 or math.min(#self.listData, 45))
    self.itemListScroll:setVirtualChilds(specialListSize and 10 or #self.listData)
	
	itemListWidget:setVirtualOffset({x = 0, y = 0})

	itemListWidget.onChildFocusChange = function(_, a)
		-- focusChild(nil, ...) below clears focus and fires this with a == nil;
		-- onItemListFocusChange already nil-guards selectedCache
		WeaponProficiency:onItemListFocusChange(a and a.cache)
	end

	if targetWidget or focusFirstChild then
		itemListWidget:focusChild(targetWidget or itemListWidget:getFirstChild(), MouseFocusReason, true)
	else
		itemListWidget:focusChild(nil, MouseFocusReason, false, true)
	end

	-- Widget not found/visible lets force the selection
	if targetItemId and not targetWidget then
		for _, data in pairs(self.itemList[weaponCategory]) do
			if targetItemId == data.marketData.showAs then
				self:onItemListFocusChange(data)
				break
			end
		end
	end
end

function WeaponProficiency:onItemListFocusChange(selectedCache)
	if not selectedCache or not g_game.isOnline() then return end

	local displayPanel = self.displayItemPanel:getChildById("item")
	local oldItem = displayPanel:getItem()

	-- Display a warning message to save changes
	if self.saveWeaponMissing and oldItem then
		self:onCloseMessage(false, oldItem, function() self:onItemListFocusChange(selectedCache) end)
		return
	end

	local displayItem = selectedCache.displayItem
	local displayItemId = displayItem:getId()
	displayPanel:setItem(displayItem)
	self.displayItemPanel:getChildById("itemNameTitle"):setText(selectedCache.marketData.name)

	self.perkPanel:destroyChildren()
	self.bonusDetailPanel:destroyChildren()
	self.starProgressPanel:destroyChildren()

	-- Vocation / level warning. Requirements come from the appearances weapon-USE flags
	-- (restrict_to_vocation field 62, VOCATION enum WITH monk=5 matching
	-- translateWheelVocation; minimum_level field 63), NOT the market block: the market's
	-- restrict_to_profession enum has no monk and its minimum_level is market metadata, so
	-- both produced false positives ("requirements not met" while the player did meet them).
	local player = g_game.getLocalPlayer()
	local itemVocation = selectedCache.thingType:getRestrictVocations()
	local playerVocation = translateWheelVocation(player:getVocation())
	local requiredLevel = selectedCache.thingType:getMinimumLevel()
	local showVocationWarning = (#itemVocation > 0 and not table.contains(itemVocation, playerVocation)) or player:getLevel() < requiredLevel
	self.vocationWarning:setVisible(showVocationWarning)

	local currentData = self.cacheList[displayItemId] or {exp = 0, perks = {}}
	self.cacheList[displayItemId] = currentData

	g_game.doThing(false)
	g_game.sendInspectionObject(4, displayItemId, 0)
	g_game.doThing(true)

	if self.allProficiencyRequested then
		g_game.doThing(false)
		g_game.sendWeaponProficiencyAction(0, displayItemId)
		g_game.doThing(true)
	end

	local proficiencyId = displayItem:getProficiencyId()
	local profEntry = ProficiencyData:getContentById(proficiencyId)
	if not profEntry then return end

	self:updateExperienceProgress(currentData.exp, #profEntry.Levels, displayItem)

	for i, levelData in ipairs(profEntry.Levels) do
		local widget = g_ui.createWidget("BonusSelectPanel", self.perkPanel)
		-- g_ui.createWidget only takes (style, parent); the id MUST be set
		-- separately (3rd arg is ignored, same as the item grid / starDetail).
		-- Without it, getChildById("bonusDetail_<i>") returns nil and
		-- onResetWeapon crashes dereferencing it (and the bonus-name text in
		-- onUpdateSelectedProficiency silently never renders).
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

		local widgetIsBlocked = not canChangeWeaponPerks() and currentData.perks[i - 1]
		for index, perkData in ipairs(levelData.Perks) do
			local bonusIcon = currentPerkPanel:getChildById(string.format("bonusIcon%s", index - 1))
			local icon = bonusIcon:getChildById("icon")
			local iconGrey = bonusIcon:getChildById("icon-grey")
			local borderWidget = bonusIcon:getChildById("border")
			local hightLightWidget = bonusIcon:getChildById("highlight")
			local augmentIconNormal = bonusIcon:getChildById("iconPerks")
			local augmentIconDarker = bonusIcon:getChildById("iconPerks-grey")

			local iconSource, iconClip = ProficiencyData:getImageSourceAndClip(perkData)
			local bonusName, bonusTooltip = ProficiencyData:getBonusNameAndTooltip(perkData)

			bonusIcon:setTooltip(string.format("%s\n\n%s", bonusName, bonusTooltip))
			bonusIcon.blocked, bonusIcon.locked, bonusIcon.active = true, false, false
			bonusIcon.perkData = perkData

			icon:setImageSource(iconSource)
			icon:setImageClip(string.format("%s 64 64", iconClip))

			-- Setup icon grey and augment
			setupPerkIconGrey(perkData, iconSource, iconClip, iconGrey, augmentIconNormal, augmentIconDarker)

			if currentData.perks[i - 1] == index - 1 then
				bonusIcon.blocked = false
				enableBonusIcon(bonusIcon, iconGrey, hightLightWidget, borderWidget, bonusDetail:recursiveGetChildById("bonusName"), bonusTooltip, augmentIconDarker, perkData)
			end

			if widgetIsBlocked then
				bonusIcon:getChildById("locked-perk"):setVisible(true)
				bonusIcon.locked = true
			end

			bonusIcon.onHoverChange = createHoverHandler(bonusIcon, iconGrey, augmentIconDarker)
			bonusIcon.onClick = createClickHandler(bonusIcon, currentPerkPanel, bonusDetail, hightLightWidget, borderWidget, iconGrey, augmentIconDarker, bonusTooltip, perkData, displayItemId)
		end

		updatePercentWidgets(widget, currentData.exp, i, displayItem)
	end
end

function WeaponProficiency:onUpdateSelectedProficiency(itemId)
	local currentItem = self.displayItemPanel:getChildById("item"):getItem()
	if not currentItem or currentItem:getId() ~= itemId then
		return
	end

	local currentData = self.cacheList[itemId] or {exp = 0, perks = {}}
	local experience = currentData.exp
	self:updateExperienceProgress(experience, #self.perkPanel:getChildren(), currentItem)

	-- Setup window buttons
	self:updateMainButtons(currentData)

	for i, child in ipairs(self.perkPanel:getChildren()) do
		updatePercentWidgets(child, experience, i, currentItem)

		local widgetIsBlocked = not canChangeWeaponPerks() and currentData.perks[i - 1]
		for index, widget in pairs(child.currentPerkPanel:getChildren()) do
			
			if widgetIsBlocked then
				widget:getChildById("locked-perk"):setVisible(true)
				widget.locked = true
			end

			if currentData.perks[i - 1] == index - 1 then
				widget.blocked = false
				widget.locked = false

				local iconGrey = widget:getChildById("icon-grey")
				local borderWidget = widget:getChildById("border")
				local hightLightWidget = widget:getChildById("highlight")
				local augmentIconDarker = widget:getChildById("iconPerks-grey")
				local bonusDetail = self.bonusDetailPanel:getChildById("bonusDetail_" .. i)
				local _, bonusTooltip = ProficiencyData:getBonusNameAndTooltip(widget.perkData)

				-- guard: bonusDetail_<i> may not exist for every perk lane index
				if bonusDetail then
					enableBonusIcon(widget, iconGrey, hightLightWidget, borderWidget, bonusDetail:recursiveGetChildById("bonusName"), bonusTooltip, augmentIconDarker, widget.perkData)
				end
			elseif widget.active then
				-- This perk is lit but is NOT the server-confirmed selection for
				-- this level. It is a stale paint (e.g. the previous perk drawn
				-- from a not-yet-refreshed cache before the 0xC4 arrived). Clear
				-- it so only one perk stays selected per column.
				widget.active = false
				widget.blocked = false
				widget.locked = false
				widget:getChildById("locked-perk"):setVisible(false)

				local iconGrey = widget:getChildById("icon-grey")
				local borderWidget = widget:getChildById("border")
				local hightLightWidget = widget:getChildById("highlight")
				local augmentIconDarker = widget:getChildById("iconPerks-grey")
				local bonusDetail = self.bonusDetailPanel:getChildById("bonusDetail_" .. i)

				if bonusDetail then
					disableBonusIcon(iconGrey, hightLightWidget, borderWidget, bonusDetail:recursiveGetChildById("bonusName"), augmentIconDarker, widget.perkData)
				end
			end
		end
		::continue::
	end
end

function WeaponProficiency:updateExperienceProgress(currentExp, levelsCount, displayItem)
	local experienceWidget = self.window:recursiveGetChildById("progressDescription")
	local experienceLeftWidget = self.window:recursiveGetChildById("nextLevelDescription")
	local totalProgressWidget = self.window:recursiveGetChildById("proficiencyProgress")

	local currentCeilExperience = ProficiencyData:getCurrentCeilExperience(currentExp, displayItem)
	local maxExperience = ProficiencyData:getMaxExperience(levelsCount, displayItem)
	local masteryAchieved = currentExp >= maxExperience

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
	local iconLevelWidget = self.window:recursiveGetChildById("iconMasteryLevel")
	local weaponLevelWidget = self.window:recursiveGetChildById("itemMasteryLevel")

	iconLevelWidget:setImageSource("/images/game/proficiency/icon-masterylevel-" .. weaponLevel)
	weaponLevelWidget:setVisible(weaponLevel > 0)
	if weaponLevel > 0 then
		local color = masteryAchieved and "gold" or "silver"
		weaponLevelWidget:setImageSource(string.format("/images/game/proficiency/icon-masterylevel-%d-%s", weaponLevel, color))
	end
end

function WeaponProficiency:toggleFilterOption(filter)
	local filterId = filter:getId()
	-- self.filters is the source of truth (these are plain Buttons whose own
	-- checked state is unreliable; the old `not filter:isChecked()` evaluated
	-- the state twice and toggled inconsistently, so the filters never applied).
	local newState = not self.filters[filterId]

	-- 1H and 2H are mutually exclusive
	if newState and filterId == "oneButton" then
		self.filters["twoButton"] = false
		self.window:recursiveGetChildById("twoButton"):setChecked(false)
	elseif newState and filterId == "twoButton" then
		self.filters["oneButton"] = false
		self.window:recursiveGetChildById("oneButton"):setChecked(false)
	end

	self.filters[filterId] = newState
	filter:setChecked(newState)

	self:onWeaponCategoryChange(self.optionFilter:getCurrentOption().text)
end

function WeaponProficiency:onSearchTextChange(text)
	local currentCategory = self.optionFilter:getCurrentOption().text
	self:onWeaponCategoryChange(currentCategory, text)
end

function WeaponProficiency:onClearSearch()
	local searchField = self.window:recursiveGetChildById("searchText")
	if not string.empty(searchField:getText()) then
		searchField:clearText()
	end
end

function WeaponProficiency:onApplyChanges(button, targetItem)
	if button and not button:isOn() then return end

	local currentItem = self.displayItemPanel:getChildById("item"):getItem()
	if targetItem then
		currentItem = targetItem
	end

	if not currentItem then
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
		g_game.sendWeaponProficiencyAction(2, currentItem:getId())
		self.cacheList[currentItem:getId()].perks = {}
	else
		local levels = {}
		local perkPositions = {}
		for level, perkPosition in pairs(toSend) do
			table.insert(levels, level)
			table.insert(perkPositions, perkPosition)
		end
		g_game.sendWeaponProficiencyApply(currentItem:getId(), levels, perkPositions)
		-- Keep the client mirror in sync with what we just applied (the reset
		-- branch above already does this). Otherwise the cache stays stale and a
		-- reopen paints the OLD perk, which then collides with the freshly
		-- applied perk arriving via 0xC4 -> two perks lit in the same column.
		if self.cacheList[currentItem:getId()] then
			self.cacheList[currentItem:getId()].perks = toSend
		end
	end

	self.window:getChildById("apply"):setOn(false)
	self.window:getChildById("ok"):setOn(false)
	self.window:getChildById("close"):setText("Close")
	self.saveWeaponMissing = false
end

-- OK = apply the pending changes (same gating as Apply) and then close the
-- window. Apply alone keeps the window open for further edits; OK confirms and
-- dismisses it.
function WeaponProficiency:onConfirmChanges(button)
	if button and not button:isOn() then
		return
	end

	self:onApplyChanges(button)

	hide()
	g_client.setInputLockWidget(nil)
end

function WeaponProficiency:onResetWeapon(button)
	if not canChangeWeaponPerks() or not button:isOn() then
		return
	end

	local currentItem = self.displayItemPanel:getChildById("item"):getItem()
	if not currentItem then
		return
	end

	local applyButton = self.window:getChildById("apply")
	local okButton = self.window:getChildById("ok")
	local closeButton = self.window:getChildById("close")
	local weaponEntry = self.cacheList[currentItem:getId()] or {}
	local perksSize = table.size(weaponEntry.perks)

	button:setOn(false)
	applyButton:setOn(perksSize > 0)
	okButton:setOn(perksSize > 0)

	button:setTooltip("You don't have any perks to reset.")

	if perksSize > 0 then
		local text = "Apply changes to your perks"
		applyButton:setTooltip(text)
		okButton:setTooltip(text)
		closeButton:setText("Cancel")
		self.saveWeaponMissing = true
	else
		local text = "No changes have been made to your perks."
		applyButton:setTooltip(text)
		okButton:setTooltip(text)
		closeButton:setText("Close")
	end

	-- Limpar as informa�oes
	for i, child in ipairs(self.perkPanel:getChildren()) do
		local bonusDetail = self.bonusDetailPanel:getChildById("bonusDetail_" .. i)

		for index, widget in pairs(child.currentPerkPanel:getChildren()) do
			widget:getChildById("locked-perk"):setVisible(false)

			if widget.active then
				widget.blocked = false
				widget.locked = false
				widget.active = false

				local iconGrey = widget:getChildById("icon-grey")
				local borderWidget = widget:getChildById("border")
				local hightLightWidget = widget:getChildById("highlight")
				local augmentIconDarker = widget:getChildById("iconPerks-grey")

				disableBonusIcon(iconGrey, hightLightWidget, borderWidget, bonusDetail:recursiveGetChildById("bonusName"), augmentIconDarker, widget.perkData)
			end
		end
	end
end

function WeaponProficiency:onCloseWindow(button)
	if button:getText() == "Close" then
		hide()
		g_client.setInputLockWidget(nil)
		return true
	end

	self:onCloseMessage(true)
end

function WeaponProficiency:onCloseMessage(userClosingWindow, targetItem, callbackFunction)
	if self.warningWindow then
		self.warningWindow:destroy()
	end

	self.window:hide()
	g_client.setInputLockWidget(nil)

	local noButton = function()
		if self.warningWindow then
			self.warningWindow:destroy()
			self.warningWindow = nil
		end
		self.saveWeaponMissing = false

		if not userClosingWindow then
			self.window:show()
			g_client.setInputLockWidget(self.window)
			if callbackFunction then
				callbackFunction()
			end
		else
			modules.game_console.getConsole():focus()
			m_interface.getRootPanel():focus()
		end
	end

  	local yesButton = function()
    	if self.warningWindow then
      		self.warningWindow:destroy()
			self.warningWindow = nil
    	end

		self:onApplyChanges(nil, targetItem)
		
		if not userClosingWindow then
			if callbackFunction then
				callbackFunction()
			end

			self.window:show()
			g_client.setInputLockWidget(self.window)
		else
			modules.game_console.getConsole():focus()
			m_interface.getRootPanel():focus()
		end
  	end

  	self.warningWindow = displayGeneralBox('Save?', "You did not save the changes you have made to your perks.\n\nWould you like to save your perks?",
		{{ text=tr('Yes'), callback = yesButton }, { text=tr('No'), callback = noButton }
	}, yesFunction, noFunction)
end

function WeaponProficiency:checkPerksMatch(itemId)
    local cachePerks = self.cacheList[itemId].perks
    local allPerksMatch = true

    -- Se o cache estiver vazio, n�o bate
    if table.empty(cachePerks) then
        allPerksMatch = false
    else
        -- Para cada linha de perks
        for levelIndex, perkRow in ipairs(self.perkPanel:getChildren()) do
            local expectedPerk = cachePerks[levelIndex - 1]
            local foundActive = nil

            for perkIndex, widget in pairs(perkRow.currentPerkPanel:getChildren()) do
                if widget.active then
                    foundActive = perkIndex - 1
                    break
                end
            end

            -- Se o cache possui perk esperado mas n�o h� ativo, ou h� ativo a mais que o cache
            if expectedPerk and foundActive ~= expectedPerk then
                allPerksMatch = false
                break
            elseif not expectedPerk and foundActive ~= nil then
                -- Ativo a mais, fora do que o cache esperava
                allPerksMatch = false
                break
            end
        end
    end

    -- Habilita ou desabilita os bot�es
    local applyButton = self.window:getChildById("apply")
    local okButton = self.window:getChildById("ok")
	local closeButton = self.window:getChildById("close")

	if canChangeWeaponPerks() and not allPerksMatch then
		local resetButton = self.window:getChildById("reset")
		resetButton:setOn(true)
		resetButton:setTooltip("Reset your perks")
	end

	local tooltip = not allPerksMatch and "No changes have been made to your perks." or "Apply changes to your perks"

    applyButton:setOn(not allPerksMatch)
    okButton:setOn(not allPerksMatch)
	applyButton:setTooltip(tooltip)
	okButton:setTooltip(tooltip)

	closeButton:setText(not allPerksMatch and "Cancel" or "Close")
	self.saveWeaponMissing = not allPerksMatch
end
