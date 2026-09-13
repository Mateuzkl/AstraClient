---------------------------
-- Lua code author: R1ck --
-- Company: VICTOR HUGO PERENHA - JOGOS ONLINE --
---------------------------

CyclopediaItems = {}
CyclopediaItems.__index = CyclopediaItems

local marketItems = {}
local lastSelectedItem = nil
local lastSelectedCategory = nil
local oldBuyChild = nil
local oldSaleChild = nil
local itemsData = {
	primaryLootValueSources = {},
	customSalePrices = {}
}
local pendingItemDetails = {}
local pendingItemDetailEvents = {}
local itemsLoaded = false
local itemsIndexRetryEvent = nil
local redirectRetryEvent = nil
local pendingRedirectItemId = nil
local OPCODE_ITEM_DETAILS = 0xC7

local RESERVED_CATEGORY_IDS = {
	[30] = true,
	[MarketCategory.Unassigned] = true,
	[MarketCategory.WeaponsAll] = true,
}

local function getCachedServerMarketItems()
	if modules.game_tibia_market and modules.game_tibia_market.getCachedCustomMarketItems then
		return modules.game_tibia_market.getCachedCustomMarketItems()
	end
	return nil
end

local function requestServerMarketItems()
	if modules.game_tibia_market and modules.game_tibia_market.requestMarketItemsForCyclopedia then
		modules.game_tibia_market.requestMarketItemsForCyclopedia()
	end
end

function CyclopediaItems.cancelPendingEvents()
	for _, event in pairs(pendingItemDetailEvents) do
		removeEvent(event)
	end
	pendingItemDetailEvents = {}
	pendingItemDetails = {}
	lastSelectedItem = nil
	lastSelectedCategory = nil
	oldBuyChild = nil
	oldSaleChild = nil
	CyclopediaItems.cancelItemsIndexRetry()
	CyclopediaItems.cancelRedirectRetry()
	pendingRedirectItemId = nil
end

function CyclopediaItems.cancelRedirectRetry()
	if redirectRetryEvent then
		removeEvent(redirectRetryEvent)
		redirectRetryEvent = nil
	end
end

function CyclopediaItems.cancelItemsIndexRetry()
	if itemsIndexRetryEvent then
		removeEvent(itemsIndexRetryEvent)
		itemsIndexRetryEvent = nil
	end
end

local function scheduleItemsIndexRetry()
	if getCachedServerMarketItems() or not g_game.isOnline() then
		CyclopediaItems.cancelItemsIndexRetry()
		return
	end

	if itemsIndexRetryEvent then
		return
	end

	itemsIndexRetryEvent = scheduleEvent(function()
		itemsIndexRetryEvent = nil
		if not VisibleCyclopediaPanel or VisibleCyclopediaPanel:isDestroyed() or VisibleCyclopediaPanel:getId() ~= 'itemDataPanel' then
			return
		end

		requestServerMarketItems()
		if getCachedServerMarketItems() then
			CyclopediaItems.onMarketItemsUpdated()
		else
			scheduleItemsIndexRetry()
		end
	end, 500)
end

local function getMarketItemId(itemInfo)
	if not itemInfo or not itemInfo.thingType then
		return nil
	end
	return itemInfo.thingType:getId()
end

local function findMarketItemCategory(itemId)
	itemId = tonumber(itemId)
	if not itemId then
		return nil
	end

	for category = MarketCategory.First, MarketCategory.Last do
		for _, itemInfo in ipairs(marketItems[category] or {}) do
			if getMarketItemId(itemInfo) == itemId then
				return category
			end
		end
	end

	for _, category in ipairs({ 30, MarketCategory.Unassigned, MarketCategory.WeaponsAll }) do
		for _, itemInfo in ipairs(marketItems[category] or {}) do
			if getMarketItemId(itemInfo) == itemId then
				return category
			end
		end
	end

	return nil
end

local function findCategoryWidget(categoryId)
	if not VisibleCyclopediaPanel or not VisibleCyclopediaPanel.leftInfo then
		return nil
	end

	local categoriesList = VisibleCyclopediaPanel.leftInfo.categoriesList
	if not categoriesList then
		return nil
	end

	for _, child in ipairs(categoriesList:getChildren()) do
		if child:getActionId() == categoryId then
			return child
		end
	end

	return nil
end

local function findItemWidget(itemId)
	if not VisibleCyclopediaPanel or not VisibleCyclopediaPanel.leftInfo then
		return nil
	end

	local itemList = VisibleCyclopediaPanel.leftInfo.itemList
	if not itemList then
		return nil
	end

	for _, child in ipairs(itemList:getChildren()) do
		if child.item and child.item:getItemId() == itemId then
			return child
		end
	end

	return nil
end

function CyclopediaItems.applyRedirect()
	local itemId = pendingRedirectItemId
	if not itemId or not VisibleCyclopediaPanel or VisibleCyclopediaPanel:isDestroyed()
		or VisibleCyclopediaPanel:getId() ~= 'itemDataPanel' then
		return false
	end

	if modules.game_tibia_market and modules.game_tibia_market.ensureMarketHiddenForCyclopedia then
		modules.game_tibia_market.ensureMarketHiddenForCyclopedia()
	end

	CyclopediaItems.loadItems(getCachedServerMarketItems() ~= nil)
	local categoryId = findMarketItemCategory(itemId)
	if not categoryId then
		return false
	end

	CyclopediaItems.showCategories()

	local categoryWidget = findCategoryWidget(categoryId)
	if not categoryWidget then
		return false
	end

	CyclopediaItems.categoryListChildFocus(VisibleCyclopediaPanel.leftInfo.categoriesList, categoryWidget)

	local itemWidget = findItemWidget(itemId)
	if not itemWidget then
		return false
	end

	CyclopediaItems.itemListChildFocus(VisibleCyclopediaPanel.leftInfo.itemList, itemWidget)
	VisibleCyclopediaPanel.leftInfo.itemList:ensureChildVisible(itemWidget)

	if modules.game_cyclopedia and modules.game_cyclopedia.cyclopediaWindow then
		local cyclopediaWindow = modules.game_cyclopedia.cyclopediaWindow
		cyclopediaWindow:show(true)
		cyclopediaWindow:raise()
		cyclopediaWindow:focus()
		g_client.setInputLockWidget(cyclopediaWindow)
	end

	pendingRedirectItemId = nil
	CyclopediaItems.cancelRedirectRetry()
	return true
end

local function scheduleRedirectRetry()
	if not pendingRedirectItemId or not g_game.isOnline() then
		CyclopediaItems.cancelRedirectRetry()
		return
	end

	if redirectRetryEvent then
		return
	end

	redirectRetryEvent = scheduleEvent(function()
		redirectRetryEvent = nil
		if not pendingRedirectItemId then
			return
		end

		if not getCachedServerMarketItems() then
			requestServerMarketItems()
		end

		if CyclopediaItems.applyRedirect() then
			return
		end

		scheduleRedirectRetry()
	end, 500)
end

local sortButtons = {
	["levelButton"] = false,
	["vocButton"] = false,
	["oneHandButton"] = false,
	["twoHandButton"] = false,
	["classOptions"] = -1
}

local enableCategories = { 17, 18, 19, 20, 21, 27 }
local enableClassification = {1, 3, 7, 8, 15, 17, 18, 19, 20, 24, 27 }

local function hasUsableDescriptions(descriptions)
	if type(descriptions) ~= 'table' then
		return false
	end

	for _, data in pairs(descriptions) do
		if type(data) == 'table' then
			local detail = data.detail or ""
			local description = data.description or ""
			if detail ~= "" or description ~= "" then
				return true
			end
		end
	end

	return false
end

local function hasDetailedServerItemDetails(itemId)
	if not ItemsDatabase or not ItemsDatabase.getServerItemDetails then
		return false
	end

	local details = ItemsDatabase.getServerItemDetails(itemId)
	if type(details) ~= 'table' then
		return false
	end

	return hasUsableDescriptions(details.descriptions) or
		(type(details.npcSaleData) == 'table' and #details.npcSaleData > 0)
end

local function getCategoryName(category)
	local categories = g_things.getMarketCategories and g_things.getMarketCategories() or {}
	local clientName = categories and categories[category]
	if type(clientName) == "string" and clientName ~= "" and tonumber(clientName) == nil then
		return clientName:gsub("\n", " ")
	end
	if getObjectCategoryName then
		local name = getObjectCategoryName(category)
		if name and name ~= "" then
			return name:gsub("\n", " ")
		end
	end
	return tostring(category)
end

local function setItemRarityFrame(widget, itemOrId)
	if ItemsDatabase and ItemsDatabase.setRarityItem then
		ItemsDatabase.setRarityItem(widget, itemOrId)
	end
end

local function normalizeItemDescriptions(descriptions)
	if type(descriptions) ~= 'table' then
		return descriptions
	end

	local itemName = ""
	for _, data in ipairs(descriptions) do
		if type(data) == 'table' and data.detail == "Name" then
			itemName = tostring(data.description or "")
			break
		end
	end

	local normalized = {}
	for _, data in ipairs(descriptions) do
		if type(data) ~= 'table' then
			goto continue
		end

		local detail = data.detail or ""
		local description = tostring(data.description or "")
		if detail == "Description" then
			local normalizedName = itemName:lower():gsub("^%s+", ""):gsub("%s+$", "")
			local normalizedDescription = description:lower():gsub("^%s+", ""):gsub("%s+$", "")
			if normalizedDescription == "" or normalizedDescription == normalizedName then
				goto continue
			end
		end

		normalized[#normalized + 1] = data
		::continue::
	end

	return normalized
end

local function getItemDescriptionDetails(item)
	if item and item.getId and ItemsDatabase and ItemsDatabase.getServerItemDetails then
		local details = ItemsDatabase.getServerItemDetails(item:getId())
		if details and type(details.descriptions) == 'table' and #details.descriptions > 0 then
			return normalizeItemDescriptions(details.descriptions)
		end
	end

	local description = item and item:getDescription() or ""
	if description == "" then
		return {}
	end

	return {
		{ detail = "Description", description = description }
	}
end

function CyclopediaItems.requestServerItemData(itemId)
	itemId = tonumber(itemId)
	if not itemId or itemId <= 0 then
		return
	end
	if hasDetailedServerItemDetails(itemId) then
		return
	end
	if pendingItemDetails[itemId] then
		return
	end

	local protocolGame = g_game.getProtocolGame()
	if not protocolGame then
		return
	end

	local msg = OutputMessage.create()
	msg:addU8(OPCODE_ITEM_DETAILS)
	msg:addU16(itemId)
	protocolGame:send(msg)

	pendingItemDetails[itemId] = true
	pendingItemDetailEvents[itemId] = scheduleEvent(function()
		pendingItemDetailEvents[itemId] = nil
		pendingItemDetails[itemId] = nil
	end, 2000)
end

function CyclopediaItems.showSelectedItemDetails(item)
	if not item then
		return
	end

	CyclopediaItems.showItemDescription(getItemDescriptionDetails(item))
	CyclopediaItems.showNpcData(item)
	CyclopediaItems.showItemPrice(item)
end

function CyclopediaItems.onItemDetails(itemId)
	itemId = tonumber(itemId)
	if not itemId then
		return
	end

	if pendingItemDetailEvents[itemId] then
		removeEvent(pendingItemDetailEvents[itemId])
		pendingItemDetailEvents[itemId] = nil
	end

	pendingItemDetails[itemId] = nil

	if not VisibleCyclopediaPanel
		or not lastSelectedItem
		or not lastSelectedItem.item
		or lastSelectedItem.item:getItemId() ~= itemId then
		return
	end

	local targetItem = lastSelectedItem.item:getItem()
	if not targetItem then
		return
	end

	CyclopediaItems.showSelectedItemDetails(targetItem)
end

function CyclopediaItems.terminate()
	CyclopediaItems.cancelPendingEvents()
	CyclopediaItems.saveJson()
	itemsLoaded = false
end

-- Json data
function CyclopediaItems.loadJson()
	if not LoadedPlayer:isLoaded() then
		return true
	end

	local file = "/characterdata/" .. LoadedPlayer:getId() .. "/itemprices.json"
	if g_resources.fileExists(file) then
		local status, result = pcall(function()
			return json.decode(g_resources.readFileContents(file))
		end)

		if not status then
			return g_logger.error("Error while reading characterdata file. Details: " .. result)
		end

		itemsData = result
	else
		itemsData["customSalePrices"] = {}
		itemsData["primaryLootValueSources"] = {}
		CyclopediaItems.saveJson()
	end

	if type(itemsData) ~= "table" then
		itemsData = {}
	end

	if table.empty(itemsData) then
		itemsData = {
			["primaryLootValueSources"] = {},
			["customSalePrices"] = {}
		}
	end

	itemsData["primaryLootValueSources"] = itemsData["primaryLootValueSources"] or {}
	itemsData["customSalePrices"] = itemsData["customSalePrices"] or {}
	if ItemsDatabase and ItemsDatabase.adoptServerValueCacheData then
		ItemsDatabase.adoptServerValueCacheData(itemsData)
	end

	local useMarketPrice = {}
	for k, v in pairs(itemsData["primaryLootValueSources"]) do
		table.insert(useMarketPrice, k)
	end

	local customPrice = g_things.getItemsPrice()
	for k, v in pairs(itemsData["customSalePrices"]) do
		local key = tonumber(k) or k
		customPrice[key] = v
	end

	local player = g_game.getLocalPlayer()
	if not player then
		return true
	end

	player:setCyclopediaMarketList(useMarketPrice)
	player:setCyclopediaCustomPrice(customPrice)
end

function CyclopediaItems.saveJson()
	if not LoadedPlayer:isLoaded() then
		return true
	end

	if ItemsDatabase then
		if ItemsDatabase.adoptServerValueCacheData then
			ItemsDatabase.adoptServerValueCacheData(itemsData)
		end
		if ItemsDatabase.prepareServerValueCacheData then
			itemsData = ItemsDatabase.prepareServerValueCacheData(itemsData)
		end
	end

	local file = "/characterdata/" .. LoadedPlayer:getId() .. "/itemprices.json"
	local status, result = pcall(function() return json.encode(itemsData, 2) end)
	if not status then
		return g_logger.error("Error while saving profile itemsData. Data won't be saved. Details: " .. result)
	end

	if result:len() > 100 * 1024 * 1024 then
		return g_logger.error("Something went wrong, file is above 100MB, won't be saved")
	end
	g_resources.writeFileContents(file, result)
end

function CyclopediaItems.onInspection(inspectType, itemName, item, descriptions)
	if inspectType ~= 1 then return end
	local selectedItem = lastSelectedItem and lastSelectedItem.item or nil
	local selectedItemId = selectedItem and selectedItem:getItemId() or nil
	local inspectedItemId = item and item.getId and item:getId() or nil

	if selectedItemId and inspectedItemId and selectedItemId ~= inspectedItemId then
		return
	end

	if selectedItem and (hasDetailedServerItemDetails(selectedItemId) or not hasUsableDescriptions(descriptions)) then
		CyclopediaItems.showSelectedItemDetails(selectedItem:getItem())
		return
	end

	if not hasUsableDescriptions(descriptions) then
		return
	end

	CyclopediaItems.showItemDescription(normalizeItemDescriptions(descriptions))
end

local function buildMarketItemFromServerEntry(serverItem)
	local itemId = tonumber(serverItem.id)
	if not itemId or itemId <= 100 then
		return nil
	end

	local thingType = g_things.getThingType(itemId, ThingCategoryItem)
	if not thingType then
		return nil
	end

	local item = Item.create(itemId)
	if not item then
		return nil
	end

	local source = thingType:getMarketData() or {}
	local marketData = {}
	for key, value in pairs(source) do
		marketData[key] = value
	end

	marketData.category = tonumber(serverItem.category) or marketData.category or MarketCategory.Others
	marketData.name = serverItem.name or marketData.name or ('Item ' .. itemId)
	marketData.showAs = marketData.showAs or itemId
	marketData.requiredLevel = tonumber(serverItem.requiredLevel) or 0
	marketData.restrictVocation = tonumber(serverItem.restrictVocation) or 0
	marketData.classification = tonumber(serverItem.classification) or marketData.classification or 0
	marketData.vocationEncoding = 'server'

	if marketData.showAs ~= itemId then
		item:setId(marketData.showAs)
	end

	return {
		displayItem = item,
		thingType = thingType,
		marketData = marketData
	}
end

local function addMarketItemEntry(marketItem)
	local category = tonumber(marketItem.marketData.category) or MarketCategory.Others
	if marketItems[category] == nil then
		marketItems[category] = {}
	end
	marketItem.marketData.category = category
	table.insert(marketItems[category], marketItem)
end

function CyclopediaItems.loadItems(force)
	if itemsLoaded and not force then
		return
	end

	marketItems = {}
	for c = MarketCategory.First, MarketCategory.WeaponsAll do
		marketItems[c] = {}
	end

	local seen = {}
	local serverItems = getCachedServerMarketItems()
	if serverItems then
		for index = 1, #serverItems do
			local marketItem = buildMarketItemFromServerEntry(serverItems[index])
			if marketItem then
				local itemId = marketItem.thingType:getId()
				if not seen[itemId] then
					seen[itemId] = true
					addMarketItemEntry(marketItem)
				end
			end
		end
	end

  	local unsorted = g_game.getUnsortedCyclopediaItems()
	local types = g_things.findThingTypeByAttr(ThingAttrMarket, 0)
	for i = 1, #types do
		local itemType = types[i]
		if seen[itemType:getId()] then
			goto continue
		end

		local item = Item.create(itemType:getId())
		if item then
			local marketData = itemType:getMarketData()
			if not table.empty(marketData) then
				marketData.vocationEncoding = 'dat'
				-- Some items use a different sprite in Market
				item:setId(marketData.showAs)

				-- create new marketItem block
				local marketItem = { displayItem = item, thingType = itemType, marketData = marketData }

				-- add new market item
				seen[itemType:getId()] = true
				addMarketItemEntry(marketItem)
        		end
		end
		:: continue ::
	end

	-- Inset money
	local values = {{id = 3031, name = "gold coin"}, {id = 3035, name = "platinum coin"}, {id = 3043, name = "crystal coin"}}
	for _, data in pairs(values) do
		local itemType = g_things.getThingType(data.id)
		local item = Item.create(itemType:getId())
		if item then
			local marketData = itemType:getMarketData()
			marketData.category = 30
			marketData.name = data.name
			local marketItem = { displayItem = item, thingType = itemType, marketData = marketData }

			-- add new market item
			table.insert(marketItems[marketData.category], marketItem)
		end
	end

  -- Insert unsorted
  for id, name in pairs(unsorted) do
	id = tonumber(id)
	if not id or seen[id] then
		goto continue
	end

    local itemType = g_things.getThingType(id)
	if not itemType then
		goto continue
	end

	local item = Item.create(itemType:getId())
	local marketData = itemType:getMarketData() or {}
	marketData.category = MarketCategory.Unassigned
	marketData.name = name
	marketData.vocationEncoding = 'dat'
    local marketItem = { displayItem = item, thingType = itemType, marketData = marketData }
	seen[id] = true
    addMarketItemEntry(marketItem)
	:: continue ::
  end

  -- Weapons all category
  marketItems[MarketCategory.WeaponsAll] = {}
  for c = MarketCategory.Ammunition, MarketCategory.WandsRods do
    for _, data in pairs(marketItems[c] or {}) do
      table.insert(marketItems[MarketCategory.WeaponsAll], data)
    end
  end
  for _, data in pairs(marketItems[MarketCategory.FistWeapons] or {}) do
    table.insert(marketItems[MarketCategory.WeaponsAll], data)
  end

	local function compareMarketItemsByNameCaseInsensitive(a, b)
		local nameA = string.lower(a.marketData.name)
		local nameB = string.lower(b.marketData.name)
		return nameA < nameB
	end

	for c = MarketCategory.First, MarketCategory.WeaponsAll do
		if marketItems[c] then
			table.sort(marketItems[c], compareMarketItemsByNameCaseInsensitive)
		end
	end
	itemsLoaded = true
end

function CyclopediaItems.onMarketItemsUpdated()
	itemsLoaded = false
	CyclopediaItems.cancelItemsIndexRetry()
	if VisibleCyclopediaPanel and not VisibleCyclopediaPanel:isDestroyed() and VisibleCyclopediaPanel:getId() == 'itemDataPanel' then
		if pendingRedirectItemId then
			CyclopediaItems.applyRedirect()
		else
			CyclopediaItems.showCategories()
		end
	end
end

function CyclopediaItems.showCategories()
	if not VisibleCyclopediaPanel or VisibleCyclopediaPanel:isDestroyed() then
		return
	end

	if not getCachedServerMarketItems() and g_game.isOnline() then
		requestServerMarketItems()
		scheduleItemsIndexRetry()
	end

	CyclopediaItems.loadItems(getCachedServerMarketItems() ~= nil)

	local categoriesList = VisibleCyclopediaPanel.leftInfo.categoriesList
	categoriesList:destroyChildren()
	categoriesList.onChildFocusChange = function(self, selected) CyclopediaItems.categoryListChildFocus(self, selected) end

	local categoryList = {}
	for category = MarketCategory.First, MarketCategory.Last do
		if not RESERVED_CATEGORY_IDS[category] and marketItems[category] and #marketItems[category] > 0 then
			table.insert(categoryList, {category, getCategoryName(category)})
		end
	end

	if marketItems[30] and #marketItems[30] > 0 then
		table.insert(categoryList, {30, "Gold"})
	end
	if marketItems[MarketCategory.Unassigned] and #marketItems[MarketCategory.Unassigned] > 0 then
		table.insert(categoryList, {MarketCategory.Unassigned, "Unsorted"})
	end
	if marketItems[MarketCategory.WeaponsAll] and #marketItems[MarketCategory.WeaponsAll] > 0 then
		table.insert(categoryList, {MarketCategory.WeaponsAll, "Weapons: All"})
	end
	table.sort(categoryList, function(a, b) return tostring(a[2] or ""):lower() < tostring(b[2] or ""):lower() end)

	local colorCount = 0
	for _, pair in ipairs(categoryList) do
		local widget = g_ui.createWidget("CategoryItemListLabel", categoriesList)
		local color = colorCount % 2 == 0 and '#414141' or '#484848'
		widget:setActionId(pair[1])
		widget:setId(tostring(pair[2] or ""))
		widget.color = color
		widget:setText(tostring(pair[2] or ""))
		widget:setBackgroundColor(color)
		colorCount = colorCount + 1
	end

	if VisibleCyclopediaPanel.leftInfo.itemList then
		VisibleCyclopediaPanel.leftInfo.itemList:destroyChildren()
	end

	local childCount = categoriesList:getChildCount()
	if childCount >= 3 then
		local firstWidget = categoriesList:getFirstChild()
		if firstWidget then
			categoriesList:moveChildToIndex(firstWidget, 2)
		end
	end

	if childCount >= 2 then
		local lastWidget = categoriesList:getChildById('Weapons: All')
		if lastWidget then
			categoriesList:moveChildToIndex(lastWidget, categoriesList:getChildCount())
		end
	end

	VisibleCyclopediaPanel.leftInfo.itemList.onChildFocusChange = function(self, selected) CyclopediaItems.itemListChildFocus(self, selected) end

	local firstChild = categoriesList:getFirstChild()
	if firstChild then
		CyclopediaItems.categoryListChildFocus(categoriesList, firstChild)
	end

	if getCachedServerMarketItems() then
		CyclopediaItems.cancelItemsIndexRetry()
	end

	VisibleCyclopediaPanel:focus()
	VisibleCyclopediaPanel:recursiveGetChildById("searchText"):focus()
end

function CyclopediaItems.categoryListChildFocus(self, selected)
	if not VisibleCyclopediaPanel or VisibleCyclopediaPanel:getId() ~= 'itemDataPanel' or not selected then return end

	if VisibleCyclopediaPanel.leftInfo.itemList then
		VisibleCyclopediaPanel.leftInfo.itemList:destroyChildren()
	end

	VisibleCyclopediaPanel.leftInfo.imageWidget.itemImage:setItem(nil)

	if #VisibleCyclopediaPanel.leftInfo.searchText:getText() > 0 then
		VisibleCyclopediaPanel.leftInfo.searchText:clearText()
	end

	if lastSelectedCategory then
		lastSelectedCategory:setBackgroundColor(lastSelectedCategory.color) -- background
		lastSelectedCategory:setColor('#c0c0c0') -- text
	end

	lastSelectedCategory = selected
	selected:setBackgroundColor('#585858')
	selected:setColor('#f4f4f4')

	-- Habilitar botoes
	if table.contains(enableCategories, selected:getActionId()) then
		VisibleCyclopediaPanel.leftInfo.oneHandButton:setEnabled(true)
		VisibleCyclopediaPanel.leftInfo.twoHandButton:setEnabled(true)
	else
		VisibleCyclopediaPanel.leftInfo.oneHandButton:setEnabled(false)
		VisibleCyclopediaPanel.leftInfo.twoHandButton:setEnabled(false)
		VisibleCyclopediaPanel.leftInfo.oneHandButton:setChecked(false)
		VisibleCyclopediaPanel.leftInfo.twoHandButton:setChecked(false)
		sortButtons["oneHandButton"] = false
		sortButtons["twoHandButton"] = false
	end

	if table.contains(enableClassification, selected:getActionId()) then
		VisibleCyclopediaPanel.leftInfo.classOptions:clearOptions()
		VisibleCyclopediaPanel.leftInfo.classOptions:addOption("All", nil, true)
		VisibleCyclopediaPanel.leftInfo.classOptions:addOption("None", nil, true)
		VisibleCyclopediaPanel.leftInfo.classOptions:addOption("Class 1", nil, true)
		VisibleCyclopediaPanel.leftInfo.classOptions:addOption("Class 2", nil, true)
		VisibleCyclopediaPanel.leftInfo.classOptions:addOption("Class 3", nil, true)
		VisibleCyclopediaPanel.leftInfo.classOptions:addOption("Class 4", nil, true)
	else
		VisibleCyclopediaPanel.leftInfo.classOptions:clearOptions()
	end

	VisibleCyclopediaPanel.leftInfo.itemList.onChildFocusChange = function(self, selected) CyclopediaItems.itemListChildFocus(self, selected) end
	for i, itemInfo in ipairs(marketItems[selected:getActionId()] or {}) do
		if not CyclopediaItems.checkSortOptions(itemInfo) then
			goto Continue
		end

		local widget = g_ui.createWidget('ItemListLabel', VisibleCyclopediaPanel.leftInfo.itemList)
		widget.item:setItemId(itemInfo.thingType:getId())
		setItemRarityFrame(widget.item, itemInfo.thingType:getId())
    	if #itemInfo.marketData.name >= 20 then
      		widget.name:setTextWrap(true)
    	end

		widget.name:setText(itemInfo.marketData.name)
		if widget.name:isTextWraped() then
			widget.name:setMarginTop(0)
		end

		if modules.game_analyser.isInDropTracker(itemInfo.thingType:getId()) then
			widget.name:setColor("#FF9854")
		else
			widget.name:setColor("#c0c0c0")
		end
		widget:setBackgroundColor('#404040')

		:: Continue ::
	end

	local firstChild = VisibleCyclopediaPanel.leftInfo.itemList:getChildren()[1]
	if firstChild then
		VisibleCyclopediaPanel.leftInfo.itemList:onChildFocusChange(firstChild, nil, KeyboardFocusReason)
	end

	oldBuyChild = nil
	oldSaleChild = nil
end

function CyclopediaItems.itemListChildFocus(self, selected)
  if not selected or not selected.item then return end

  local item = selected.item:getItem()
  local itemId = selected.item:getItemId()
  VisibleCyclopediaPanel.leftInfo.imageWidget.itemImage:setItemId(itemId)
  setItemRarityFrame(VisibleCyclopediaPanel.leftInfo.imageWidget.itemImage, itemId)
  if not hasDetailedServerItemDetails(itemId) then
    g_game.sendInspectionObject(3, itemId, 0)
  end

  VisibleCyclopediaPanel.panelitemshide:setVisible(true)
  VisibleCyclopediaPanel.leftInfo.header:setVisible(true)
  VisibleCyclopediaPanel.leftInfo.circlemarket:setVisible(true)
  VisibleCyclopediaPanel.leftInfo.circlenpc:setVisible(true)
  VisibleCyclopediaPanel.leftInfo.circlenpc:setChecked(true)
  VisibleCyclopediaPanel.emptyLabel:setVisible(false)

  if lastSelectedItem then
    lastSelectedItem:setBackgroundColor('#404040')
  end

  selected:setBackgroundColor('#585858')
  lastSelectedItem = selected

  oldBuyChild = nil
  oldSaleChild = nil

  CyclopediaItems.showSelectedItemDetails(selected.item:getItem())
  CyclopediaItems.requestServerItemData(itemId)

  local isMarketPrice = false
  local primaryLootValueSources = itemsData["primaryLootValueSources"] or {}
  if primaryLootValueSources[tostring(itemId)] then
    VisibleCyclopediaPanel.leftInfo.circlenpc:setChecked(false)
    VisibleCyclopediaPanel.leftInfo.circlemarket:setChecked(true)
  else
    VisibleCyclopediaPanel.leftInfo.circlenpc:setChecked(true)
    VisibleCyclopediaPanel.leftInfo.circlemarket:setChecked(false)
  end

  local lootConfig = lootData["listType"]
  local lootTable = (lootConfig == "whitelist" and lootData["whitelistTypes"] or lootData["blacklistTypes"])

  if lootTable and table.contains(lootTable, selected.item:getItem():getId()) then
    VisibleCyclopediaPanel.panelitemshide.checkLootbox:setChecked(true)
  else
    VisibleCyclopediaPanel.panelitemshide.checkLootbox:setChecked(false)
  end

  if lootConfig == "blacklist" then
    VisibleCyclopediaPanel.panelitemshide.lootBox:setImageSource("/mods/game_cyclopedia/images/ui/names/skipwhen")
  else
    VisibleCyclopediaPanel.panelitemshide.lootBox:setImageSource("/mods/game_cyclopedia/images/ui/names/lootwhen")
  end

  if modules.game_npctrade.inWhiteList(selected.item:getItem():getId()) then
	VisibleCyclopediaPanel.panelitemshide.quickListbox:setChecked(true)
  else
	VisibleCyclopediaPanel.panelitemshide.quickListbox:setChecked(false)
  end

  -- tracker
  local check = VisibleCyclopediaPanel:recursiveGetChildById("checkbox-track-drops")
  if check then
  	local inTracker = modules.game_analyser.isInDropTracker(selected.item:getItem():getId())
	check:setChecked(inTracker)
	if inTracker then

	end
  end
end

function CyclopediaItems.updateDropTracker(widget, checked)
	if not lastSelectedItem or not lastSelectedItem.item then return end
	widget:setChecked(not checked)

	lastSelectedItem.name:setColor(checked and "#c0c0c0" or "#FF9854")
	modules.game_analyser.managerDropTracker(lastSelectedItem.item:getItem():getId(), widget:isChecked())
end

function CyclopediaItems.showNpcData(item)
	local data = {}
	if item and item.getNPCSaleData then
		data = item:getNPCSaleData() or {}
	end

	VisibleCyclopediaPanel.panelitemshide.sellToList:destroyChildren()
	VisibleCyclopediaPanel.panelitemshide.buyFromList:destroyChildren()

	local sellToCount = 0
	local buyFromCount = 0
	local rashidFound = false
	local yasirFound = false

	for _, v in pairs(data) do
		local buyPrice = v.buyPrice
		local salePrice = v.salePrice
		local npc = v.name
		local location = v.location

		if buyPrice ~= 0 then
			if (npc == 'Rashid' and rashidFound) or (npc == 'Yasir' and yasirFound) then
				goto Continue
			end

			if npc == 'Rashid' then
				rashidFound = true
				location = "Various Locations"
			elseif npc == 'Yasir' then
				yasirFound = true
				location = "Various Locations"
			end

			local widget = g_ui.createWidget("SaleList", VisibleCyclopediaPanel.panelitemshide.sellToList)
			local color = sellToCount % 2 == 0 and '#414141' or '#484848'

			widget.valueLabel:setText(comma_value(buyPrice) .. " gp, " .. npc)
			widget.locationLabel:setText("Residence: " .. location)

			if sellToCount == 0 then
				widget:setBackgroundColor("#585858")
				widget.valueLabel:setColor("#f4f4f4")
				widget.locationLabel:setColor("#f4f4f4")
				oldBuyChild = widget
			else
				widget:setBackgroundColor(color)
			end

			widget:setId(color)
			sellToCount = sellToCount + 1
		end

		if salePrice ~= 0 then
			local widget = g_ui.createWidget("SaleList", VisibleCyclopediaPanel.panelitemshide.buyFromList)
			local color = buyFromCount % 2 == 0 and '#414141' or '#484848'

			if v.currencyQuestFlagDisplayName == '' then
				widget.valueLabel:setText(comma_value(salePrice) .. " gp, " .. npc)
			else
				widget.valueLabel:setText(comma_value(salePrice) .. " x " .. v.currencyQuestFlagDisplayName .. ", " .. npc)
			end
			widget.locationLabel:setText("Residence: " .. location)

			if buyFromCount == 0 then
				widget:setBackgroundColor("#585858")
				widget.valueLabel:setColor("#f4f4f4")
				widget.locationLabel:setColor("#f4f4f4")
				oldSaleChild = widget
			else
				widget:setBackgroundColor(color)
			end

			widget:setId(color)
			buyFromCount = buyFromCount + 1
		end
		:: Continue ::
	end

	VisibleCyclopediaPanel.panelitemshide.sellToList.onChildFocusChange = function(self, selected) CyclopediaItems.onSelectBuyChild(self, selected) end
	VisibleCyclopediaPanel.panelitemshide.buyFromList.onChildFocusChange = function(self, selected) CyclopediaItems.onSelectSaleChild(self, selected) end
end

function CyclopediaItems.onSelectBuyChild(self, selected)
	if oldBuyChild == selected or not selected.valueLabel then
		return
	end

	if oldBuyChild then
		oldBuyChild:setBackgroundColor(oldBuyChild:getId())
		oldBuyChild.valueLabel:setColor('#c0c0c0')
		oldBuyChild.locationLabel:setColor('#c0c0c0')
	end

	selected:setBackgroundColor('#585858')
	selected.valueLabel:setColor('#f7f7f7')
	selected.locationLabel:setColor('#f7f7f7')
	oldBuyChild = selected
end

function CyclopediaItems.onSelectSaleChild(self, selected)
	if oldSaleChild == selected or not selected.valueLabel then
		return
	end

	if oldSaleChild then
		oldSaleChild:setBackgroundColor(oldSaleChild:getId())
		oldSaleChild.valueLabel:setColor('#c0c0c0')
		oldSaleChild.locationLabel:setColor('#c0c0c0')
	end

	selected:setBackgroundColor('#585858')
	selected.valueLabel:setColor('#f7f7f7')
	selected.locationLabel:setColor('#f7f7f7')
	oldSaleChild = selected
end

local function updateCustomPricePlaceholder()
	local panel = VisibleCyclopediaPanel and VisibleCyclopediaPanel.panelitemshide
	if not panel or not panel.customPrice or not panel.customPricePlaceholder then
		return
	end

	panel.customPricePlaceholder:setVisible(panel.customPrice:getText():len() == 0)
end

function CyclopediaItems.showItemPrice(item)
	local avgMarket = item:getAverageMarketValue()
	VisibleCyclopediaPanel.panelitemshide.averageMarketPrice:setText(comma_value(avgMarket))

	local isMarketPrice = false
	local primaryLootValueSources = itemsData["primaryLootValueSources"] or {}
	if primaryLootValueSources[tostring(item:getId())] then
		isMarketPrice = true
	end

	local resulting = isMarketPrice and avgMarket or item:getDefaultValue()
	if resulting == 0 then
		resulting = avgMarket
	end

	local customSalePrices = itemsData["customSalePrices"] or {}
	if customSalePrices[tostring(item:getId())] then
		resulting = customSalePrices[tostring(item:getId())]
		VisibleCyclopediaPanel.panelitemshide.customPrice:setText(resulting)
	else
		VisibleCyclopediaPanel.panelitemshide.customPrice:clearText(true)
	end
	updateCustomPricePlaceholder()

	VisibleCyclopediaPanel.panelitemshide.resultingValue:setText(comma_value(resulting))
	if resulting == 0 then
		VisibleCyclopediaPanel.panelitemshide.itemColor:setImageSource("")
	else
		VisibleCyclopediaPanel.panelitemshide.itemColor:setImageSource("/mods/game_cyclopedia/images/ui/itemcolor/" .. getItemPriceColor(resulting))
	end

	return resulting
end

function CyclopediaItems.showItemDescription(desc)
	if not VisibleCyclopediaPanel then
		return true
	end

	local basicPanel = VisibleCyclopediaPanel:recursiveGetChildById("basicDetails")
	if not basicPanel then
		return true
	end
	desc = normalizeItemDescriptions(desc)
	if not hasUsableDescriptions(desc) then
		return true
	end

	local scrollBar = VisibleCyclopediaPanel:recursiveGetChildById("basic-item-details-scroll")
	local scrollBarWidth = scrollBar and scrollBar:isVisible() and 16 or 0
	local infoWidth = basicPanel:getWidth() - scrollBarWidth

	basicPanel:destroyChildren()
	for _, data in ipairs(desc) do
		if type(data) == 'table' then
			local detail = data.detail or ""
			local description = data.description or ""
			if detail ~= "" or description ~= "" then
				local widget = g_ui.createWidget("CyclopediaInspectRow", basicPanel)
				widget:setWidth(infoWidth)
				widget:setTextAlign(AlignCenter)
				if detail ~= "" and description ~= "" then
					widget:setText(detail .. ": " .. description)
				elseif detail ~= "" then
					widget:setText(detail)
				else
					widget:setText(description)
				end

				if widget:isTextWraped() then
					local wrappedLines = math.max(1, widget:getWrappedLinesCount())
					widget:setHeight(math.max(21, 21 * wrappedLines + 6))
				end
			end
		end
	end
end

function CyclopediaItems.onClickLootContainers()
	-- fazer um terminate
	modules.game_cyclopedia.toggle()
	modules.game_quickloot.showQuickLoot()
end

local function findItem(t, itemId)
	for _, item in pairs(t) do
		if item.displayItem:getId() == itemId then
			return true
		end
	end
	return false
end

-- Search
function CyclopediaItems.onSearch(widget)
	local searchList = {}
	local currrentText = widget:getText()

	lastSelectedItem = nil
	if #currrentText == 0 then
		CyclopediaItems.showSearchResult(searchList)
		return
	end

	local count = 0
	for c = MarketCategory.First, MarketCategory.Last do
		if count >= 200 then
			break
		end

		for i, itemInfo in ipairs(marketItems[c]) do
			if count >= 200 then
				break
			end

			if matchText(currrentText, itemInfo.marketData.name) and not findItem(searchList, itemInfo.displayItem:getId()) then
				table.insert(searchList, itemInfo)
				count = count + 1
			end
		end
	end
	CyclopediaItems.showSearchResult(searchList)
end

function CyclopediaItems.showSearchResult(list)
	VisibleCyclopediaPanel.leftInfo.classOptions:setCurrentIndex(1)
	VisibleCyclopediaPanel.leftInfo.itemList:destroyChildren()
	VisibleCyclopediaPanel.leftInfo.imageWidget.itemImage:setItem(nil)
	VisibleCyclopediaPanel.leftInfo.oneHandButton:setEnabled(true)
	VisibleCyclopediaPanel.leftInfo.twoHandButton:setEnabled(true)
	sortButtons["classOptions"] = -1

	for _, data in pairs(list) do
		if not CyclopediaItems.checkSortOptions(data) then
			goto Continue
		end

		local widget = g_ui.createWidget('ItemListLabel', VisibleCyclopediaPanel.leftInfo.itemList)
		widget.item:setItemId(data.thingType:getId())
		setItemRarityFrame(widget.item, data.thingType:getId())
		widget.name:setText(data.marketData.name)
		if modules.game_analyser.isInDropTracker(data.thingType:getId()) then
			widget.name:setColor("#FF9854")
		else
			widget.name:setColor("#c0c0c0")
		end
		widget:setBackgroundColor('#404040')
		:: Continue ::
	end

	local firstChild = VisibleCyclopediaPanel.leftInfo.itemList:getChildren()[1]
	if firstChild then
		VisibleCyclopediaPanel.leftInfo.itemList:onChildFocusChange(firstChild, nil, KeyboardFocusReason)
	end
end

function CyclopediaItems.clearSearch(widget)
	if #widget:getText() > 0 then
		VisibleCyclopediaPanel.leftInfo.oneHandButton:setEnabled(false)
		VisibleCyclopediaPanel.leftInfo.twoHandButton:setEnabled(false)
		VisibleCyclopediaPanel.leftInfo.oneHandButton:setChecked(false)
		VisibleCyclopediaPanel.leftInfo.twoHandButton:setChecked(false)
		sortButtons["oneHandButton"] = false
		sortButtons["twoHandButton"] = false
		sortButtons["classOptions"] = -1
		widget:clearText()
		CyclopediaItems.showSearchResult({})
		VisibleCyclopediaPanel.leftInfo.itemList:updateScrollBars()
	end

	lastSelectedItem = nil
end

-- Sort
function CyclopediaItems.checkSortOptions(itemData)
	local player = g_game.getLocalPlayer()
	if not player then
		return false
	end

	local playerLevel = player:getLevel()

	if sortButtons["levelButton"] then
	if itemData.marketData.requiredLevel > playerLevel then
			return false
		end
	end

	if sortButtons["vocButton"] then
		local itemVocation = itemData.marketData.restrictVocation
		if type(itemVocation) == 'table' then
			local playerVocation = translateWheelVocation(player:getVocation())
			if #itemVocation > 0 and not table.contains(itemVocation, playerVocation) then
				return false
			end
		else
			itemVocation = tonumber(itemVocation) or 0
			if itemVocation > 0 then
				local vocBitMask = itemData.marketData.vocationEncoding == 'server'
					and getMarketVocationBitMask(player:getVocation())
					or getDatVocationBitMask(player:getVocation())
				if vocBitMask > 0 and not Bit.hasBit(itemVocation, vocBitMask) then
					return false
				end
			end
		end
	end

	if sortButtons["oneHandButton"] then
		if itemData.thingType:getClothSlot() ~= 6 then
			return false
		end
	end

	if sortButtons["twoHandButton"] then
		if itemData.thingType:getClothSlot() ~= 0 then
			return false
		end
	end
	return true
end

function CyclopediaItems.onSortFields(widget, checked)
	if not lastSelectedCategory then
		return true
	end

	local player = g_game.getLocalPlayer()
	if not player or not VisibleCyclopediaPanel then
		return
	end

	lastSelectedItem = nil
	if widget:getId() ~= "classOptions" then
		widget:setChecked(not checked)
		sortButtons[widget:getId()] = not checked

		if widget:getId() == 'oneHandButton' then
			sortButtons["twoHandButton"] = false
			VisibleCyclopediaPanel.leftInfo.twoHandButton:setChecked(false)
		elseif widget:getId() == 'twoHandButton' then
			VisibleCyclopediaPanel.leftInfo.oneHandButton:setChecked(false)
			sortButtons["oneHandButton"] = false
		end
	else
		if checked > 1 then
			sortButtons["classOptions"] = (checked - 2)
		end
	end

	VisibleCyclopediaPanel.leftInfo.itemList:destroyChildren()
	for i, itemInfo in ipairs(marketItems[lastSelectedCategory:getActionId()]) do
		if not CyclopediaItems.checkSortOptions(itemInfo) then
			goto Continue
		end

		if sortButtons["classOptions"] ~= -1 then
			if itemInfo.thingType:getClassification() ~= sortButtons["classOptions"] then
				goto Continue
			end
		end

		local widget = g_ui.createWidget('ItemListLabel', VisibleCyclopediaPanel.leftInfo.itemList)
		widget.item:setItemId(itemInfo.thingType:getId())
		setItemRarityFrame(widget.item, itemInfo.thingType:getId())
		widget.name:setText(itemInfo.marketData.name)
		if modules.game_analyser.isInDropTracker(itemInfo.thingType:getId()) then
			widget.name:setColor("#FF9854")
		else
			widget.name:setColor("#c0c0c0")
		end
		widget:setBackgroundColor('#404040')

		:: Continue ::
	end
end

function CyclopediaItems.manageQuickloot(widget, checked)
	if not lastSelectedItem or not lastSelectedItem.item then
		return true
	end

	if not checked then
		modules.game_quickloot.addToQuickLoot(lastSelectedItem.item:getItem():getId())
	else
		modules.game_quickloot.removeItemInList(lastSelectedItem.item:getItem():getId())
	end
	widget:setChecked(not checked)
end

function CyclopediaItems.manageQuickSellWhitelist(widget, checked)
	if not lastSelectedItem or not lastSelectedItem.item then
		return true
	end

	if not checked then
		modules.game_npctrade.addToWhitelist(lastSelectedItem.item:getItem():getId())
	else
		modules.game_npctrade.removeItemInList(lastSelectedItem.item:getItem():getId())
	end
	widget:setChecked(not checked)
end

function CyclopediaItems.onSourceValueChange(checked, npcSource)
	if checked or not lastSelectedItem then
		return
	end

	if not itemsData then
		itemsData = {
			primaryLootValueSources = {},
			customSalePrices = {}
		}
	end
	itemsData["primaryLootValueSources"] = itemsData["primaryLootValueSources"] or {}
	itemsData["customSalePrices"] = itemsData["customSalePrices"] or {}

	local player = g_game.getLocalPlayer()
	local item = lastSelectedItem.item:getItem()
	local itemId = item:getId()
	local currentItemID = tostring(itemId)
	local currentPrice = 0

	if npcSource then
		local newItemList = {}
		newItemList["primaryLootValueSources"] = {}
		for k, v in pairs(itemsData["primaryLootValueSources"]) do
			if k ~= currentItemID then
				newItemList["primaryLootValueSources"][k] = v
			end
		end

		itemsData["primaryLootValueSources"] = newItemList["primaryLootValueSources"]
		currentPrice = CyclopediaItems.showItemPrice(item)
		VisibleCyclopediaPanel.leftInfo.circlenpc:setChecked(true)
		VisibleCyclopediaPanel.leftInfo.circlemarket:setChecked(false)
		if player and player.updateCyclopediaMarketList then
			player:updateCyclopediaMarketList(itemId, true)
		end
	else
		itemsData["primaryLootValueSources"][currentItemID] = "market"
		currentPrice = CyclopediaItems.showItemPrice(item)
		VisibleCyclopediaPanel.leftInfo.circlenpc:setChecked(false)
		VisibleCyclopediaPanel.leftInfo.circlemarket:setChecked(true)
		if player and player.updateCyclopediaMarketList then
			player:updateCyclopediaMarketList(itemId, false)
		end
	end

	if player and player.updateCyclopediaCustomPrice then
		player:updateCyclopediaCustomPrice(itemId, currentPrice)
	end
	modules.game_analyser.HuntingAnalyser:updateLootedItemValue(itemId, currentPrice)
	modules.game_analyser.LootAnalyser:updateBasePriceFromLootedItems(itemId, currentPrice)
	if modules.game_analyser.getLeaderLootType() == PriceTypeEnum.Leader and modules.game_analyser.isLeaderParty() then
		local price = {
			[tonumber(itemId)] = itemsData["primaryLootValueSources"][itemId]
		}
		g_game.sendPartyLootPrice(price)
	end
end

function CyclopediaItems.onUpdateResultingValue(value)
	local resulting = tonumber(value) or 0
	VisibleCyclopediaPanel.panelitemshide.resultingValue:setText(comma_value(resulting))
	if resulting == 0 then
		VisibleCyclopediaPanel.panelitemshide.itemColor:setImageSource("")
	else
		VisibleCyclopediaPanel.panelitemshide.itemColor:setImageSource("/mods/game_cyclopedia/images/ui/itemcolor/" .. getItemPriceColor(resulting))
	end
end

function CyclopediaItems.onChangeCustomPrice(widget)
	updateCustomPricePlaceholder()

	if not lastSelectedItem then
		return
	end

	if not itemsData then
		itemsData = {
			primaryLootValueSources = {},
			customSalePrices = {}
		}
	end
	itemsData["primaryLootValueSources"] = itemsData["primaryLootValueSources"] or {}
	itemsData["customSalePrices"] = itemsData["customSalePrices"] or {}

	local player = g_game.getLocalPlayer()
	local currentText = widget:getText()
	local item = lastSelectedItem.item:getItem()
	local itemId = item:getId()
	local itemIdStr = tostring(itemId)
	if #currentText == 0 then
		local newItemList = {}
		newItemList["customSalePrices"] = {}

		for k, v in pairs(itemsData["customSalePrices"]) do
			if k ~= itemIdStr then
				newItemList["customSalePrices"][k] = v
			end
		end

		itemsData["customSalePrices"] = newItemList["customSalePrices"]
		CyclopediaItems.showItemPrice(item)
		local itemDefaultValue = item:getDefaultValue()
		if player and player.updateCyclopediaCustomPrice then
			player:updateCyclopediaCustomPrice(itemId, itemDefaultValue)
		end
		modules.game_analyser.HuntingAnalyser:updateLootedItemValue(itemId, itemDefaultValue)
		modules.game_analyser.LootAnalyser:updateBasePriceFromLootedItems(itemId, itemDefaultValue)
		if modules.game_analyser.getLeaderLootType() == PriceTypeEnum.Leader and modules.game_analyser.isLeaderParty() then
			local price = {
				[itemId] = itemDefaultValue
			}
			g_game.sendPartyLootPrice(price)
		end
		return
	end

    currentText = currentText:gsub("[^%d]", "")
    widget:setText(currentText)

    local numericValue = tonumber(currentText)
    if numericValue then
        if numericValue >= 999999999 then
            currentText = "999999999"
            widget:setText(currentText)
        end
    end

    local numericValue = tonumber(currentText)
	if not numericValue then
		widget:setText("0")
		numericValue = 0
	end

	itemsData["customSalePrices"][itemIdStr] = numericValue
 	CyclopediaItems.onUpdateResultingValue(currentText)
	if player and player.updateCyclopediaCustomPrice then
		player:updateCyclopediaCustomPrice(itemId, numericValue)
	end
	modules.game_analyser.LootAnalyser:updateBasePriceFromLootedItems(itemId, numericValue)
	modules.game_analyser.HuntingAnalyser:updateLootedItemValue(itemId, numericValue)
	if modules.game_analyser.getLeaderLootType() == PriceTypeEnum.Leader and modules.game_analyser.isLeaderParty() then
		local price = {
			[itemId] = numericValue
		}
		g_game.sendPartyLootPrice(price)
	end
end

function CyclopediaItems.onRedirect(itemId)
	itemId = tonumber(itemId)
	if not itemId or not modules.game_cyclopedia or not modules.game_cyclopedia.Cyclopedia then
		return
	end

	pendingRedirectItemId = itemId
	CyclopediaItems.cancelRedirectRetry()

	if modules.game_tibia_market and modules.game_tibia_market.ensureMarketHiddenForCyclopedia then
		modules.game_tibia_market.ensureMarketHiddenForCyclopedia()
	end

	modules.game_cyclopedia.Cyclopedia:open()

	scheduleEvent(function()
		if pendingRedirectItemId ~= itemId then
			return
		end

		if not CyclopediaItems.applyRedirect() and g_game.isOnline() then
			scheduleRedirectRetry()
		end
	end, 0)
end

function CyclopediaItems.getCurrentItemValue(item)
	local avgMarket = item:getAverageMarketValue()
	local isMarketPrice = false

	local primaryLootValueSources = itemsData["primaryLootValueSources"] or {}
	if primaryLootValueSources[tostring(item:getId())] then
		isMarketPrice = true
	end

	local resulting = isMarketPrice and avgMarket or item:getDefaultValue()
	if resulting == 0 then
		resulting = avgMarket
	end

	local customSalePrices = itemsData["customSalePrices"] or {}
	if customSalePrices[tostring(item:getId())] then
		resulting = customSalePrices[tostring(item:getId())]
	end
	return resulting
end

function CyclopediaItems.sendPartyLootItems()
    local totalList = {}
    for i, category in pairs(marketItems) do
		if i == MarketCategory.WeaponsAll or i == MarketCategory.Gold then
			goto continue
		end

        for i, itemInfo in ipairs(category) do
			totalList[tonumber(itemInfo.marketData.showAs)] = CyclopediaItems.getCurrentItemValue(itemInfo.displayItem)
        end
		:: continue ::
    end

    g_game.sendPartyLootPrice(totalList)
end
