marketWindow = nil

local marketItems = {}
local categoryList = {}
local depotLockerItems = {}
local buyOffers = {}
local sellOffers = {}

local lastSelectedCategory = nil
local lastSelectedItem = {}

local lastSelectedMySell = nil
local lastSelectedMyBuy = nil

local lastSelectedHistorySell = nil
local lastSelectedHistoryBuy = nil

local showLockerOnly = false
local mainMarket = nil

local lastItemID = 0
local lastItemTier = 0
local currentActionType = 1
local marketCatalogReady = false
local marketCatalogBuilding = false
local marketCatalogEvent = nil
local marketCatalogGeneration = 0

local MARKET_CATALOG_BATCH_SIZE = 20
local MARKET_CATEGORY_BATCH_SIZE = 6

local cache = {
	SCROLL_MARKET_ITEMS = {
		listMin = 0,
		listMax = 0,
		listFit = 0,
		listPool = 14,
		listData = {},
		offset = 0,
		scrollDelay = 0
	},

	SCROLL_SELL_OFFERS = {
		listMin = 0,
		listMax = 0,
		listFit = 0,
		listPool = 14,
		listData = {},
		lastSelected = 0
	},

	SCROLL_BUY_OFFERS = {
		listMin = 0,
		listMax = 0,
		listFit = 0,
		listPool = 14,
		listData = {},
		lastSelected = 0
	}
}

local sortButtons = {
	["levelButton"] = false,
	["vocButton"] = false,
	["oneButton"] = false,
	["twoButton"] = false,
	["classFilter"] = -1,
	["tierFilter"] = 0
}

local enableCategories = { 17, 18, 19, 20, 21, 27, 32 }
local enableClassification = {1, 3, 7, 8, 15, 17, 18, 19, 20, 21, 24, 27, 32 }

local function cancelMarketCatalogBuild()
	if marketCatalogEvent then
		removeEvent(marketCatalogEvent)
		marketCatalogEvent = nil
	end

	marketCatalogBuilding = false
	marketCatalogGeneration = marketCatalogGeneration + 1
end

local function scheduleMarketCatalogStep(generation, callback)
	marketCatalogEvent = scheduleEvent(function()
		marketCatalogEvent = nil
		if generation ~= marketCatalogGeneration or not marketWindow or marketWindow:isDestroyed() then
			return
		end

		callback()
	end, 1)
end

local function resetMarketCatalog()
	cancelMarketCatalogBuild()
	marketCatalogReady = false
	marketItems = {}
	categoryList = {}

	if marketWindow and not marketWindow:isDestroyed() then
		marketWindow.contentPanel.category:destroyChildren()
	end
end

local function onMarketSessionChange()
	resetMarketCatalog()
	hide()
end

local function getDepotItemKey(itemId, tier)
	return string.format("%d:%d", itemId or 0, tier or 0)
end

local function getMarketCategoryName(category)
	local categories = g_things.getMarketCategories and g_things.getMarketCategories() or {}
	local clientName = categories and categories[category]
	if type(clientName) == 'string' and clientName ~= '' and tonumber(clientName) == nil then
		return clientName:gsub("\n", " ")
	end

	if getObjectCategoryName then
		local name = getObjectCategoryName(category)
		if name and name ~= '' then
			return name:gsub("\n", " ")
		end
	end

	return 'Unassigned'
end

local function copyMarketData(itemType, itemId, category, name)
	local source = itemType and itemType:getMarketData() or {}
	local marketData = {}
	for key, value in pairs(source or {}) do
		marketData[key] = value
	end

	marketData.category = category or marketData.category or MarketCategory.Others
	marketData.name = name or marketData.name or ('Item ' .. itemId)
	marketData.showAs = marketData.showAs or itemId
	marketData.requiredLevel = marketData.requiredLevel or 0
	marketData.restrictVocation = marketData.restrictVocation or {}
	return marketData
end

local function setItemRarityFrame(widget, itemOrId)
	if ItemsDatabase and ItemsDatabase.setRarityItem then
		local target = widget
		if widget and widget.getParent then
			local parent = widget:getParent()
			if parent and parent.itemBackground then
				target = parent.itemBackground
			end
		end

		if widget and widget.getId and widget:getId() == 'selectedItem' and marketWindow and marketWindow.contentPanel.selectedItemBackground then
			target = marketWindow.contentPanel.selectedItemBackground
		end

		ItemsDatabase.setRarityItem(target, itemOrId)
	end
end

local function clearMarketItemWidget(widget)
	if not widget then
		return
	end

	if widget.setItem then
		widget:setItem(nil)
	elseif widget.setItemId then
		widget:setItemId(0)
	end

	if ItemsDatabase and ItemsDatabase.setTier then
		ItemsDatabase.setTier(widget, nil)
	end
	setItemRarityFrame(widget, nil)
end

local function getMarketItemTier(itemInfo, fallbackTier)
	if itemInfo and itemInfo.tier ~= nil then
		return itemInfo.tier
	end
	return fallbackTier or 0
end

local function getMarketItemCount(itemInfo, fallbackTier)
	return getDepotItemCount(itemInfo.thingType:getId(), getMarketItemTier(itemInfo, fallbackTier))
end

local function addMarketListItem(itemInfo, tier)
	if tier and tier > 0 then
		local copy = table.copy(itemInfo)
		copy.tier = tier
		table.insert(cache.SCROLL_MARKET_ITEMS.listData, copy)
	else
		table.insert(cache.SCROLL_MARKET_ITEMS.listData, itemInfo)
	end
end

function init()
  marketWindow = g_ui.displayUI('t_market')
  mainMarket = marketWindow.contentPanel.mainMarket
  marketWindow.contentPanel.lockerOnly.onCheckChange = function(self, checked) toggleShowLockerOnly(self, checked) end

  if initMarketProtocol then
    initMarketProtocol()
  end

  hide()
  mainMarket.createOfferSell:setChecked(true)
  connect(g_game, {
	onUpdateResourceValue = onUpdateResourceValue,
	onGameEnd = onMarketSessionChange,
	onGameStart = onMarketSessionChange,
	onMarketEnter = onMarketEnter,
	onMarketBrowse = onMarketBrowse,
	onMarketDetail = onMarketDetail,
	onParseMyOffers = MarketOwnOffers.onParseMyOffers,
	onParseMarketHistory = MarketHistory.onParseMarketHistory,
	onMarketLeave = hide,
	onCoinBalance = onCoinBalance,
  })

end

function terminate()
	cancelMarketCatalogBuild()

  if terminateMarketProtocol then
    terminateMarketProtocol()
  end

	disconnect(g_game, {
	  onUpdateResourceValue = onUpdateResourceValue,
	  onGameStart = onMarketSessionChange,
	  onGameEnd = onMarketSessionChange,
	  onMarketEnter = onMarketEnter,
	  onMarketBrowse = onMarketBrowse,
	  onMarketDetail = onMarketDetail,
	  onParseMyOffers = MarketOwnOffers.onParseMyOffers,
	  onParseMarketHistory = MarketHistory.onParseMarketHistory,
	  onMarketLeave = hide,
	  onCoinBalance = onCoinBalance,
	})

	if marketWindow then
	  marketWindow:destroy()
	  marketWindow = nil
	end
end

function toggle()
  if marketWindow:isVisible() then
    marketWindow:hide()
	g_client.setInputLockWidget(nil)
	modules.game_console.getConsole():focus()
  else
    if g_game.openMarket then
      g_game.openMarket()
    end
	g_client.setInputLockWidget(marketWindow)
    marketWindow:show(true)
    marketWindow.contentPanel.searchText:focus()
  end
end

function hide()
	cancelMarketCatalogBuild()

	local wasVisible = marketWindow:isVisible()
	local mainMarket = marketWindow.contentPanel:getChildById('mainMarket')
	local detailsMarket = marketWindow.contentPanel:getChildById('detailsMarket')
	local closeButton = marketWindow.contentPanel:getChildById('closeButton')
	local marketButton = marketWindow.contentPanel:getChildById('marketButton')
	mainMarket:setVisible(true)
	closeButton:setVisible(true)
  	detailsMarket:setVisible(false)
  	marketButton:setVisible(false)

	onClearMainMarket(true)
	marketWindow:hide()
	g_client.setInputLockWidget(nil)
	onClearSearch()

	if wasVisible then
		g_game.doThing(false)
		g_game.sendMarketLeave()
		g_game.doThing(true)
	end
  	lastSelectedItem = {}
	modules.game_console.getConsole():focus()
end

function show()
  marketWindow:show(true)
  g_client.setInputLockWidget(marketWindow)
  marketWindow.contentPanel.searchText:focus()
  sortButtons["classFilter"] = -1
  sortButtons["tierFilter"] = 0
end

function detailsButton()
  local mainMarket = marketWindow.contentPanel:getChildById('mainMarket')
  local detailsMarket = marketWindow.contentPanel:getChildById('detailsMarket')
  local closeButton = marketWindow.contentPanel:getChildById('closeButton')
  local marketButton = marketWindow.contentPanel:getChildById('marketButton')

  if detailsMarket:isVisible() then
    return
  end

  if mainMarket:isVisible() then
    mainMarket:setVisible(false)
    detailsMarket:setVisible(true)
    closeButton:setVisible(false)
    marketButton:setVisible(true)
  else
    detailsMarket:setVisible(false)
    mainMarket:setVisible(true)
    marketButton:setVisible(false)
    closeButton:setVisible(true)
  end
end

function offersButton()
  local mainMarket = marketWindow.contentPanel:getChildById('mainMarket')
  local detailsMarket = marketWindow.contentPanel:getChildById('detailsMarket')
  local closeButton = marketWindow.contentPanel:getChildById('closeButton')
  local marketButton = marketWindow.contentPanel:getChildById('marketButton')
  if not mainMarket:isVisible() then
    detailsMarket:setVisible(false)
    mainMarket:setVisible(true)
    marketButton:setVisible(false)
    closeButton:setVisible(true)
  end
end

function myOffersButton(widget)
  local marketPanel = marketWindow.contentPanel:getChildById('mainMarket')
  local detailsMarket = marketWindow.contentPanel:getChildById('detailsMarket')
  local marketMain = marketWindow:getChildById('contentPanel')
  local marketHistory = marketWindow:getChildById('MarketHistory')
  local sellButton = marketWindow.MarketHistory.currentOffers.buyCancelOffer
  local closeButton = marketWindow.contentPanel:getChildById('closeButton')

  MarketOwnOffers.myBuyOffers = {}
  MarketOwnOffers.mySellOffers = {}

  if widget:getId() == 'myOffers' then
	g_game.sendMarketAction(2)
  elseif widget:getId() == "currentOffers" then
	g_game.sendMarketAction(2)
	return
  elseif widget:getId() == 'historyButton' then
	g_game.sendMarketAction(1)
	return
  end

  if widget:getId() ~= 'myOffers' then
	if lastItemID then
		g_game.sendMarketAction(3, lastItemID, lastItemTier)
		lastItemID, lastItemTier = 0
	end
  end

  if marketMain:isVisible() then
	marketWindow.MarketHistory.currentOffers.sellSeparator:setVisible(false)
	marketWindow.MarketHistory.currentOffers.sellStatusButton:setVisible(false)
	marketWindow.MarketHistory.currentOffers.buySeparator:setVisible(false)
	marketWindow.MarketHistory.currentOffers.buyStatusButton:setVisible(false)
	marketWindow.MarketHistory.currentOffers.sellEndButton:setWidth(220)
	marketWindow.MarketHistory.currentOffers.buyEndButton:setWidth(220)
    marketMain:setVisible(false)
	closeButton:setVisible(false)
    marketHistory:setVisible(true)
  else
	lastSelectedMySell = nil
	lastSelectedMyBuy = nil
	lastSelectedHistorySell = nil
	lastSelectedHistoryBuy = nil
    marketHistory:setVisible(false)
    marketMain:setVisible(true)
    detailsMarket:setVisible(false)
    marketPanel:setVisible(true)
	closeButton:setVisible(true)
  end
end

function getDepotItemCount(itemId, tier)
	tier = tier or 0

	if depotLockerItems and depotLockerItems.depotItems then
		local count = depotLockerItems.depotItems[getDepotItemKey(itemId, tier)]
		if count then
			return count
		end
	end

	for _, data in pairs(depotLockerItems) do
		if type(data) == "table" and data[1] == itemId and (data[2] or 0) == tier then
			return data[3] or 0
		end
	end

	if itemId == 22118 then
		return g_game.getTransferableTibiaCoins and g_game.getTransferableTibiaCoins() or 0
	end

	return 0
end

function onUpdateResourceValue()
	if not g_game.isOnline() or not marketWindow or not marketWindow:isVisible() then
		return
	end

	local playerBank = g_game.getLocalPlayer():getResourceValue(ResourceBank)
	local playerInventory = g_game.getLocalPlayer():getResourceValue(ResourceInventary)
	local playerCoins = g_game.getTransferableTibiaCoins()
	local moneyTooltip = {}

	setStringColor(moneyTooltip, "Cash: " .. comma_value(playerInventory), "#3f3f3f")
	setStringColor(moneyTooltip, " $", "#f7e6fe")
	setStringColor(moneyTooltip, "\nBank: " .. comma_value(playerBank), "#3f3f3f")
	setStringColor(moneyTooltip, " $", "#f7e6fe")

	marketWindow.contentPanel.moneyPanel.gold:setText(comma_value(playerBank + playerInventory))
	marketWindow.contentPanel.moneyPanel.gold:setTooltip(moneyTooltip)
	marketWindow.contentPanel.coinPanel.gold:setText(comma_value(playerCoins))

	marketWindow.MarketHistory.currentOffers.moneyPanel.gold:setText(comma_value(playerBank + playerInventory))
	marketWindow.MarketHistory.currentOffers.moneyPanel.gold:setTooltip(moneyTooltip)
	marketWindow.MarketHistory.currentOffers.coinPanel.gold:setText(comma_value(playerCoins))
end

function onCoinBalance(coins, transferableCoins)
	if not marketWindow:isVisible() then
		return
	end
	
	local coinTooltip = {}

	setStringColor(coinTooltip, "Total Astra Coins: " .. comma_value(coins + transferableCoins), "#3f3f3f")
	setStringColor(coinTooltip, " £", "#f7e6fe")
	setStringColor(coinTooltip, "\nIncluded transferable Astra Coins: " .. comma_value(transferableCoins), "#3f3f3f")
	setStringColor(coinTooltip, " ¢", "#f7e6fe")

	marketWindow.contentPanel.coinPanel.gold:setText(comma_value(transferableCoins))
	marketWindow.contentPanel.coinPanel.gold:setTooltip(coinTooltip)
	marketWindow.MarketHistory.currentOffers.coinPanel.gold:setText(comma_value(transferableCoins))
	marketWindow.MarketHistory.currentOffers.coinPanel.gold:setTooltip(coinTooltip)

	local selectedItem = marketWindow.contentPanel.selectedItem:getItem()
	if selectedItem and selectedItem:getId() == 22118 then
		selectedItem:setCount(transferableCoins)
	end

	local itemList = marketWindow:recursiveGetChildById("itemList")
	if not itemList then
		return true
	end

	for _, widget in pairs(itemList:getChildren()) do
		local widgetItem = widget.item:getItem()
		if widgetItem and widgetItem:getId() == 22118 then
			widgetItem:setCount(transferableCoins)
			break
		end
	end
end

local function finishMarketEnter()
	if not marketWindow or marketWindow:isDestroyed() then
		return
	end

	marketWindow.contentPanel.classFilter:clearOptions()
	marketWindow.contentPanel.tierFilter:clearOptions()

	local itemListScroll = marketWindow:recursiveGetChildById("itemListScroll")
	itemListScroll:setValue(0)
	itemListScroll:setMinimum(0)
	itemListScroll:setMaximum(0)
	itemListScroll.onValueChange = nil

	show()
	marketWindow:focus()
	onUpdateResourceValue()
	marketWindow.contentPanel.category.onChildFocusChange = function(self, selected) onSelectChildCategory(self, selected) end
end

local function renderMarketCategories(generation, onComplete)
	local categoryPanel = marketWindow.contentPanel.category
	categoryPanel:destroyChildren()

	local nextIndex = 1
	local function renderBatch()
		local batchEnd = math.min(nextIndex + MARKET_CATEGORY_BATCH_SIZE - 1, #categoryList)
		for index = nextIndex, batchEnd do
			local pair = categoryList[index]
			local widget = g_ui.createWidget('CategoryItemListLabel', categoryPanel)
			local color = (index - 1) % 2 == 0 and '#414141' or '#484848'
			widget:setActionId(pair[1])
			widget.color = color
			widget:setId(pair[2])
			widget:setText(pair[2])
			widget:setBackgroundColor(color)
		end

		nextIndex = batchEnd + 1
		if nextIndex <= #categoryList then
			scheduleMarketCatalogStep(generation, renderBatch)
			return
		end

		local firstWidget = categoryPanel:getFirstChild()
		if firstWidget then
			categoryPanel:moveChildToIndex(firstWidget, 2)
		end

		local lastWidget = categoryPanel:getChildById('Weapons: All')
		if lastWidget then
			categoryPanel:moveChildToIndex(lastWidget, categoryPanel:getChildCount())
		end

		marketCatalogBuilding = false
		marketCatalogReady = true
		onComplete()
	end

	scheduleMarketCatalogStep(generation, renderBatch)
end

function configureList(serverItems, onComplete)
	cancelMarketCatalogBuild()
	marketCatalogBuilding = true
	local generation = marketCatalogGeneration

	marketItems = {}
	for category = MarketCategory.First, MarketCategory.WeaponsAll do
		marketItems[category] = {}
	end

	local tasks = {}
	local addedItems = {}
	local serverCatalog = serverItems or {}
	local serverIndex = 1
	local clientCatalog = nil
	local clientIndex = 1
	local taskIndex = 1
	local usingClientCatalog = false
	local collectClientBatch

	local function beginClientCatalog()
		usingClientCatalog = true
		clientCatalog = g_things.findThingTypeByAttr(ThingAttrMarket, 0) or {}
		clientIndex = 1
		tasks = {}
		taskIndex = 1
		scheduleMarketCatalogStep(generation, collectClientBatch)
	end

	local function finishCatalog()
		categoryList = {}
		for category = MarketCategory.First, MarketCategory.Last do
			if marketItems[category] and #marketItems[category] > 0 then
				categoryList[#categoryList + 1] = {category, getMarketCategoryName(category)}
			end
		end

		if #marketItems[MarketCategory.WeaponsAll] > 0 then
			categoryList[#categoryList + 1] = {MarketCategory.WeaponsAll, 'Weapons: All'}
		end
		table.sort(categoryList, function(a, b) return a[2] < b[2] end)
		renderMarketCategories(generation, onComplete)
	end

	local function sortCategory(category)
		if not usingClientCatalog or category > MarketCategory.WeaponsAll then
			scheduleMarketCatalogStep(generation, finishCatalog)
			return
		end

		local entries = marketItems[category] or {}
		if #entries > 1 then
			table.sort(entries, function(a, b)
				if a.sortName == b.sortName then
					return a.thingType:getId() < b.thingType:getId()
				end
				return a.sortName < b.sortName
			end)
		end
		scheduleMarketCatalogStep(generation, function() sortCategory(category + 1) end)
	end

	local function processBatch()
		local batchEnd = math.min(taskIndex + MARKET_CATALOG_BATCH_SIZE - 1, #tasks)
		for index = taskIndex, batchEnd do
			local task = tasks[index]
			local itemId = tonumber(task.itemId)
			if itemId and not addedItems[itemId] and itemId ~= 49870 and itemId ~= 14258 then
				local thingType = task.thingType or g_things.getThingType(itemId, ThingCategoryItem) or g_things.getThingType(itemId)
				if thingType then
					local category = tonumber(task.category) or MarketCategory.Others
					marketItems[category] = marketItems[category] or {}
					local data = {
						thingType = thingType,
						marketData = copyMarketData(thingType, itemId, category, task.name)
					}
					data.sortName = string.lower(tostring(data.marketData.name or ''))
					marketItems[category][#marketItems[category] + 1] = data
					if (category >= MarketCategory.Ammunition and category <= MarketCategory.WandsRods) or
						category == MarketCategory.FistWeapons then
						marketItems[MarketCategory.WeaponsAll][#marketItems[MarketCategory.WeaponsAll] + 1] = data
					end
					addedItems[itemId] = true
				end
			end
		end

		taskIndex = batchEnd + 1
		if taskIndex <= #tasks then
			scheduleMarketCatalogStep(generation, processBatch)
		elseif not usingClientCatalog and next(addedItems) == nil then
			beginClientCatalog()
		elseif usingClientCatalog then
			scheduleMarketCatalogStep(generation, function() sortCategory(MarketCategory.First) end)
		else
			scheduleMarketCatalogStep(generation, finishCatalog)
		end
	end

	collectClientBatch = function()
		local batchEnd = math.min(clientIndex + MARKET_CATALOG_BATCH_SIZE - 1, #clientCatalog)
		for index = clientIndex, batchEnd do
			local itemType = clientCatalog[index]
			local marketData = itemType:getMarketData()
			if not table.empty(marketData) then
				tasks[#tasks + 1] = {
					itemId = itemType:getId(),
					category = marketData.category,
					name = marketData.name,
					thingType = itemType
				}
			end
		end

		clientIndex = batchEnd + 1
		if clientIndex <= #clientCatalog then
			scheduleMarketCatalogStep(generation, collectClientBatch)
		else
			scheduleMarketCatalogStep(generation, processBatch)
		end
	end

	local function collectServerBatch()
		local batchEnd = math.min(serverIndex + MARKET_CATALOG_BATCH_SIZE - 1, #serverCatalog)
		for index = serverIndex, batchEnd do
			local entry = serverCatalog[index]
			if type(entry) == 'table' and (tonumber(entry[2]) or 0) == 0 then
				tasks[#tasks + 1] = {
					itemId = entry.itemId or entry[1],
					category = entry.category,
					name = entry.name
				}
			end
		end

		serverIndex = batchEnd + 1
		if serverIndex <= #serverCatalog then
			scheduleMarketCatalogStep(generation, collectServerBatch)
		elseif #tasks > 0 then
			scheduleMarketCatalogStep(generation, processBatch)
		else
			beginClientCatalog()
		end
	end

	scheduleMarketCatalogStep(generation, collectServerBatch)
end

-- Main Window
function onMarketEnter(offerCount, items)
	depotLockerItems = items

	if marketCatalogReady then
		finishMarketEnter()
	elseif not marketCatalogBuilding then
		configureList(items, finishMarketEnter)
	end
end

function onMarketBrowse(itemID, tier, buyList, sellList)
	if table.empty(lastSelectedItem) then return end

	buyOffers = buyList
	sellOffers = sellList

	cache.SCROLL_BUY_OFFERS.listFit = math.floor(mainMarket.buyOffersList:getHeight() / 16) - 1
	cache.SCROLL_BUY_OFFERS.listMin = 0
	cache.SCROLL_BUY_OFFERS.listPool = {}
	cache.SCROLL_BUY_OFFERS.listData = buyOffers
	cache.SCROLL_BUY_OFFERS.lastSelected = 0

	local colorCount = 0
	mainMarket.buyOffersList:destroyChildren()

	for i, data in pairs(buyOffers) do
		if i > cache.SCROLL_BUY_OFFERS.listFit then
			break
		end

		local widget = g_ui.createWidget('MarketOfferWidget', mainMarket.buyOffersList)
		local color = colorCount % 2 == 0 and '#414141' or '#484848'
		local holder = data.holder
		widget:setId(color)
		widget:setActionId(i)
		widget:setBackgroundColor(color)
		widget.name:setText(short_text(data.holder, 15))
		widget.amount:setText(data.amount)
		widget.endAt:setText(os.date("%Y-%m-%d, %H:%M:%S", data.timestamp))
		if widget.setIgnoreEqualFocus then widget:setIgnoreEqualFocus(true) end

		if #holder >= 15 then
			widget.name:setTooltip(data.holder)
		end

		local totalPrice = data.price * data.amount
		local unitPrice = data.price
		widget.piecePrice:setText(convertGold(unitPrice))
		widget.totalPrice:setText(convertGold(totalPrice))
		colorCount = colorCount + 1

		local count = getDepotItemCount(itemID, tier)
		widget.piecePrice:setColor(count > 0 and "#c0c0c0" or "#808080")
		widget.totalPrice:setColor(count > 0 and "#c0c0c0" or "#808080")
		widget.name:setColor(count > 0 and "#c0c0c0" or "#808080")
		widget.amount:setColor(count > 0 and "#c0c0c0" or "#808080")
		widget.endAt:setColor(count > 0 and "#c0c0c0" or "#808080")
		table.insert(cache.SCROLL_BUY_OFFERS.listPool, widget)
	end

	cache.SCROLL_BUY_OFFERS.listMin = #buyOffers > 0 and 1 or 0
	cache.SCROLL_BUY_OFFERS.listMax = #buyOffers + 1

	local buyListScroll = marketWindow:recursiveGetChildById("buyOffersListScroll")
	buyListScroll:setValue(cache.SCROLL_BUY_OFFERS.listMin)
	buyListScroll:setMinimum(cache.SCROLL_BUY_OFFERS.listMin)
	buyListScroll:setMaximum(#cache.SCROLL_BUY_OFFERS.listPool < 11 and 0 or math.max(0, cache.SCROLL_BUY_OFFERS.listMax - #cache.SCROLL_BUY_OFFERS.listPool))
	buyListScroll.onValueChange = function(self, value, delta) onBuyListValueChange(self, value, delta) end
	
	cache.SCROLL_SELL_OFFERS.listFit = math.floor(mainMarket.sellOffersList:getHeight() / 16) - 1
	cache.SCROLL_SELL_OFFERS.listMin = 0
	cache.SCROLL_SELL_OFFERS.listPool = {}
	cache.SCROLL_SELL_OFFERS.listData = sellOffers
	cache.SCROLL_SELL_OFFERS.lastSelected = 0

	colorCount = 0
	mainMarket.sellOffersList:destroyChildren()

	for i, data in pairs(sellOffers) do
		if i > cache.SCROLL_SELL_OFFERS.listFit then
			break
		end

		local widget = g_ui.createWidget('MarketOfferWidget', mainMarket.sellOffersList)
		local color = colorCount % 2 == 0 and '#414141' or '#484848'
		local holder = data.holder
		widget:setId(color)
		widget:setActionId(i)
		widget:setBackgroundColor(color)
		widget.name:setText(short_text(data.holder, 15))
		widget.amount:setText(data.amount)
		widget.endAt:setText(os.date("%Y-%m-%d, %H:%M:%S", data.timestamp))
		if widget.setIgnoreEqualFocus then widget:setIgnoreEqualFocus(true) end

		local totalPrice = data.price * data.amount
		local unitPrice = data.price
		widget.piecePrice:setText(convertGold(unitPrice))
		widget.totalPrice:setText(convertGold(totalPrice))

		if #holder >= 15 then
			widget.name:setTooltip(data.holder)
		end

		if totalPrice > 99999999 then
		widget.totalPrice:setTooltip(comma_value(totalPrice))
		end

		if unitPrice > 99999999 then
		widget.piecePrice:setTooltip(comma_value(unitPrice))
		end

		local hasMoney = getTotalMoney() >= unitPrice
		widget.piecePrice:setColor(hasMoney and "#c0c0c0" or "#808080")
		widget.totalPrice:setColor(hasMoney and "#c0c0c0" or "#808080")
		widget.name:setColor(hasMoney and "#c0c0c0" or "#808080")
		widget.amount:setColor(hasMoney and "#c0c0c0" or "#808080")
		widget.endAt:setColor(hasMoney and "#c0c0c0" or "#808080")
		colorCount = colorCount + 1
		table.insert(cache.SCROLL_SELL_OFFERS.listPool, widget)
	end

	cache.SCROLL_SELL_OFFERS.listMin = #sellOffers > 0 and 1 or 0
	cache.SCROLL_SELL_OFFERS.listMax = #sellOffers + 1

	local sellListScroll = marketWindow:recursiveGetChildById("sellOffersListScroll")
	sellListScroll:setValue(cache.SCROLL_SELL_OFFERS.listMin)
	sellListScroll:setMinimum(cache.SCROLL_SELL_OFFERS.listMin)
	sellListScroll:setMaximum(#cache.SCROLL_SELL_OFFERS.listPool < 11 and 0 or math.max(0, cache.SCROLL_SELL_OFFERS.listMax - #cache.SCROLL_SELL_OFFERS.listPool))
	sellListScroll.onValueChange = function(self, value, delta) onSellListValueChange(self, value, delta) end

	lastItemID = itemID
	lastItemTier = tier
	mainMarket.sellOffersList.onChildFocusChange = function(self, selected, oldFocus) onSelectSellOffer(self, selected, oldFocus) end
	mainMarket.buyOffersList.onChildFocusChange = function(self, selected, oldFocus) onSelectBuyOffer(self, selected, oldFocus) end

	onUpdateChildItem(itemID, tier)
	local firstChild = mainMarket.sellOffersList:getChildren()[1]
	if firstChild then
		mainMarket.sellOffersList:focusChild(firstChild)
	end

	firstChild = mainMarket.buyOffersList:getChildren()[1]
	if firstChild then
		mainMarket.buyOffersList:focusChild(firstChild)
	end
end

function onBuyListValueChange(scroll, value, delta)
	local startLabel = math.max(cache.SCROLL_BUY_OFFERS.listMin, value)
	local endLabel = startLabel + #cache.SCROLL_BUY_OFFERS.listPool - 1
  
	if endLabel > cache.SCROLL_BUY_OFFERS.listMax then
	  endLabel = cache.SCROLL_BUY_OFFERS.listMax
	  startLabel = endLabel - #cache.SCROLL_BUY_OFFERS.listPool + 1
	end

	for i, widget in ipairs(cache.SCROLL_BUY_OFFERS.listPool) do
	  local index = startLabel + i - 1
	  local data = cache.SCROLL_BUY_OFFERS.listData[index]

	  if data then
		local color = index % 2 == 0 and '#414141' or '#484848'
		local holder = data.holder
		widget:setId(color)
		widget:setActionId(index)
		widget:setBackgroundColor(color)
		widget.name:setText(short_text(data.holder, 15))
		widget.amount:setText(data.amount)
		widget.endAt:setText(os.date("%Y-%m-%d, %H:%M:%S", data.timestamp))

		if #holder >= 15 then
			widget.name:setTooltip(data.holder)
		end

		local totalPrice = data.price * data.amount
		local unitPrice = data.price
		widget.piecePrice:setText(convertGold(unitPrice))
		widget.totalPrice:setText(convertGold(totalPrice))

		local count = getDepotItemCount(lastItemID, lastItemTier)
		widget.piecePrice:setColor(count > 0 and "#c0c0c0" or "#808080")
		widget.totalPrice:setColor(count > 0 and "#c0c0c0" or "#808080")
		widget.name:setColor(count > 0 and "#c0c0c0" or "#808080")
		widget.amount:setColor(count > 0 and "#c0c0c0" or "#808080")
		widget.endAt:setColor(count > 0 and "#c0c0c0" or "#808080")

		if index == cache.SCROLL_BUY_OFFERS.lastSelected then
			widget:setBackgroundColor('#35241d')
			widget.piecePrice:setColor("#f4f4f4")
			widget.totalPrice:setColor("#f4f4f4")
			widget.name:setColor("#f4f4f4")
			widget.amount:setColor("#f4f4f4")
			widget.endAt:setColor("#f4f4f4")
		end
	  end
	end
end

function onSellListValueChange(scroll, value, delta)
	local startLabel = math.max(cache.SCROLL_SELL_OFFERS.listMin, value)
	local endLabel = startLabel + #cache.SCROLL_SELL_OFFERS.listPool - 1
  
	if endLabel > cache.SCROLL_SELL_OFFERS.listMax then
	  endLabel = cache.SCROLL_SELL_OFFERS.listMax
	  startLabel = endLabel - #cache.SCROLL_SELL_OFFERS.listPool + 1
	end

	for i, widget in ipairs(cache.SCROLL_SELL_OFFERS.listPool) do
	  local index = startLabel + i - 1
	  local data = cache.SCROLL_SELL_OFFERS.listData[index]

	  if data then
		local color = index % 2 == 0 and '#414141' or '#484848'
		local holder = data.holder
		widget:setId(color)
		widget:setActionId(index)
		widget:setBackgroundColor(color)
		widget.name:setText(short_text(data.holder, 15))
		widget.amount:setText(data.amount)
		widget.endAt:setText(os.date("%Y-%m-%d, %H:%M:%S", data.timestamp))
		if widget.setIgnoreEqualFocus then widget:setIgnoreEqualFocus(true) end

		local totalPrice = data.price * data.amount
		local unitPrice = data.price
		widget.piecePrice:setText(convertGold(unitPrice))
		widget.totalPrice:setText(convertGold(totalPrice))

		if #holder >= 15 then
			widget.name:setTooltip(data.holder)
		end

		if totalPrice > 99999999 then
			widget.totalPrice:setTooltip(comma_value(totalPrice))
		end

		if unitPrice > 99999999 then
			widget.piecePrice:setTooltip(comma_value(unitPrice))
		end

		local hasMoney = getTotalMoney() >= unitPrice
		widget.piecePrice:setColor(hasMoney and "#c0c0c0" or "#808080")
		widget.totalPrice:setColor(hasMoney and "#c0c0c0" or "#808080")
		widget.name:setColor(hasMoney and "#c0c0c0" or "#808080")
		widget.amount:setColor(hasMoney and "#c0c0c0" or "#808080")
		widget.endAt:setColor(hasMoney and "#c0c0c0" or "#808080")

		if index == cache.SCROLL_SELL_OFFERS.lastSelected then
			widget:setBackgroundColor('#35241d')
			widget.piecePrice:setColor("#f4f4f4")
			widget.totalPrice:setColor("#f4f4f4")
			widget.name:setColor("#f4f4f4")
			widget.amount:setColor("#f4f4f4")
			widget.endAt:setColor("#f4f4f4")
		end
	  end
	end
end

function onItemListValueChange(scroll, value, delta)
	local startLabel = math.max(cache.SCROLL_MARKET_ITEMS.listMin, value)
	local endLabel = startLabel + #cache.SCROLL_MARKET_ITEMS.listPool - 1
  
	if endLabel > cache.SCROLL_MARKET_ITEMS.listMax then
	  endLabel = cache.SCROLL_MARKET_ITEMS.listMax
	  startLabel = endLabel - #cache.SCROLL_MARKET_ITEMS.listPool + 1
	end

	cache.SCROLL_MARKET_ITEMS.offset = cache.SCROLL_MARKET_ITEMS.offset + ((value % 5) * 2)
	if cache.SCROLL_MARKET_ITEMS.offset > 20 or value == 0 or value == 133 then
		cache.SCROLL_MARKET_ITEMS.offset = 0
	end
  
	if value >= #cache.SCROLL_MARKET_ITEMS.listData - 6 then
		cache.SCROLL_MARKET_ITEMS.offset = 28
	end

	local list = marketWindow:recursiveGetChildById("itemList")
	list:setVirtualOffset({x = 0, y = cache.SCROLL_MARKET_ITEMS.offset})

	for i, widget in ipairs(cache.SCROLL_MARKET_ITEMS.listPool) do
	  local index = value > 0 and (startLabel + i - 1) or (startLabel + i)
	  local data = cache.SCROLL_MARKET_ITEMS.listData[index]
	  if data and widget.item then

		local isSelected = lastSelectedItem.itemId == data.thingType:getId()
		if data.tier then
			isSelected = lastSelectedItem.itemId == data.thingType:getId() and data.tier == lastSelectedItem.tier
		end

		local backgroundColor = isSelected and '#585858' or '#404040'
		widget:setBackgroundColor(backgroundColor)
		if isSelected then
			lastSelectedItem.lastWidget = widget
		end

		local tier = getMarketItemTier(data, sortButtons["tierFilter"] or 0)
		local count = getMarketItemCount(data, tier)
		widget.item:setItemId(data.thingType:getId())
		setItemRarityFrame(widget.item, data.thingType:getId())

		widget.name:setTooltip('')
		widget.name:setText(data.marketData.name)
		if widget.name.isOfflimit and widget.name:isOfflimit() then
			widget.name:setText(short_text(data.marketData.name, 15))
			widget.name:setTooltip(data.marketData.name)
		end

		widget.item:getItem():setCount(count)
		widget.item:setActionId(index)
		widget.item:setTooltip(tr("%s%s%s%s", comma_value(count), "x", (count > 65000 and "+ " or " "), data.marketData.name))
		widget.item:setTier(tier)

		if not widget.name:isTextWraped() then
			widget.name:setMarginTop(1)
		end

		widget.grayHover:setOpacity(count > 0 and '0.0' or '0.5')
	  end
	end
end

function onSelectChildCategory(widget, selected, keepFilter)
	if lastSelectedCategory then
		lastSelectedCategory:setBackgroundColor(lastSelectedCategory.color)
		lastSelectedCategory:setColor('#c0c0c0')
	end

	local itemList = marketWindow:recursiveGetChildById("itemList")
	if not itemList then
		return true
	end

	lastSelectedCategory = selected
	selected:setBackgroundColor('#35241d')
	selected:setColor('#f4f4f4')

	cache.SCROLL_MARKET_ITEMS.listFit = math.floor(itemList:getHeight() / 36) + 1
	cache.SCROLL_MARKET_ITEMS.listMin = 0
	cache.SCROLL_MARKET_ITEMS.listPool = {}
	cache.SCROLL_MARKET_ITEMS.listData = {}

	cache.SCROLL_SELL_OFFERS.lastSelected = 0
	cache.SCROLL_BUY_OFFERS.lastSelected = 0

	marketWindow.contentPanel.itemList:destroyChildren()

	local clearHands = not lastSelectedCategory or not table.contains(enableCategories, lastSelectedCategory:getActionId())

	lastSelectedItem = {}
	onClearSearch(clearHands)
	onClearMainMarket(true)

	marketWindow.contentPanel.mainMarket.getPotionsButton:setVisible(false)

	-- Habilitar botoes
	if table.contains(enableCategories, selected:getActionId()) then
		marketWindow.contentPanel.oneButton:setEnabled(true)
		marketWindow.contentPanel.twoButton:setEnabled(true)
	else
		onClearHandFilter()
	end

	if not keepFilter then
		sortButtons["classFilter"] = -1
		sortButtons["tierFilter"] = 0

		if table.contains(enableClassification, selected:getActionId()) then
			marketWindow.contentPanel.classFilter:clearOptions()
			marketWindow.contentPanel.classFilter:addOption("All", nil, true)
			marketWindow.contentPanel.classFilter:addOption("None", nil, true)
			for i = 1, 4 do
				marketWindow.contentPanel.classFilter:addOption("Class " .. i, nil, true)
			end

			marketWindow.contentPanel.tierFilter:clearOptions()
			for i = 0, 10 do
				marketWindow.contentPanel.tierFilter:addOption("Tier " .. i, nil, true)
			end
		else
			marketWindow.contentPanel.classFilter:clearOptions()
			marketWindow.contentPanel.tierFilter:clearOptions()
		end
	end

	clearMarketItemWidget(marketWindow.contentPanel.selectedItem)
	itemList.onChildFocusChange = function(self, selected, oldFocus) onSelectChildItem(self, selected, oldFocus) end

	local tier = sortButtons["tierFilter"] or 0
	-- Sorted items
	for i, itemInfo in pairs(marketItems[selected:getActionId()] or {}) do
		if not checkSortMarketOptions(itemInfo) or (showLockerOnly and getDepotItemCount(itemInfo.thingType:getId(), tier) == 0) then
			goto continue
		end

		addMarketListItem(itemInfo, tier)
		:: continue ::
	end

	for i, itemInfo in pairs(cache.SCROLL_MARKET_ITEMS.listData) do
		if #cache.SCROLL_MARKET_ITEMS.listPool >= cache.SCROLL_MARKET_ITEMS.listFit then
			break
		end

		local itemTier = getMarketItemTier(itemInfo, tier or 0)
		local count = getMarketItemCount(itemInfo, itemTier)
		if not checkSortMarketOptions(itemInfo) or (count == 0 and showLockerOnly) then
			goto continue
		end

		local widget = g_ui.createWidget('MarketItemList', itemList)
		if widget.setIgnoreEqualFocus then widget:setIgnoreEqualFocus(true) end
		widget.item:setItemId(itemInfo.thingType:getId())
		setItemRarityFrame(widget.item, itemInfo.thingType:getId())

		widget.name:setText(itemInfo.marketData.name)
		if widget.name.isOfflimit and widget.name:isOfflimit() then
			widget.name:setText(short_text(itemInfo.marketData.name, 15))
			widget.name:setTooltip(itemInfo.marketData.name)
		end

		widget:setBackgroundColor('#271b17')
		widget.item:getItem():setCount(count)
		widget.item:setActionId(i)
		widget.item:setTooltip(tr("%s%s%s%s", comma_value(count), "x", (count > 65000 and "+ " or " "), itemInfo.marketData.name))

		widget.item:setTier(itemTier)

		if not widget.name:isTextWraped() then
			widget.name:setMarginTop(1)
		end

		if count > 0 then
			widget.grayHover:setOpacity('0.0')
		end

		table.insert(cache.SCROLL_MARKET_ITEMS.listPool, widget)

		:: continue ::
	end

	cache.SCROLL_MARKET_ITEMS.listMax = #cache.SCROLL_MARKET_ITEMS.listData

	local itemListScroll = marketWindow:recursiveGetChildById("itemListScroll")
	itemListScroll:setValue(0)
	itemListScroll:setMinimum(cache.SCROLL_MARKET_ITEMS.listMin)
	itemListScroll:setMaximum(#cache.SCROLL_MARKET_ITEMS.listPool < 8 and 0 or math.max(0, cache.SCROLL_MARKET_ITEMS.listMax - #cache.SCROLL_MARKET_ITEMS.listPool) + 2)
	itemListScroll.onValueChange = function(self, value, delta) onItemListValueChange(self, value, delta) end

	itemList:setVirtualOffset({x = 0, y = 0})

	if selected:getActionId() == 10 then
		marketWindow.contentPanel.mainMarket.getPotionsButton:setVisible(true)
	end
end

function onUpdateChildItem(itemID, tier)
	for _, widget in pairs(marketWindow.contentPanel.itemList:getChildren()) do
		if widget.item:getItem():getId() == itemID and widget.item:getItem():getTier() == tier then
			local count = itemID == 22118 and g_game.getTransferableTibiaCoins() or getDepotItemCount(itemID, tier)

			if lastSelectedCategory then
				local itemInfo = cache.SCROLL_MARKET_ITEMS.listData[widget.item:getActionId()]
				if itemInfo and itemInfo.marketData then
					widget.item:setTooltip(tr("%s%s%s%s", comma_value(count), "x", (count > 65000 and "+ " or " "), itemInfo.marketData.name))
				end
			end

			widget.item:getItem():setCount(count == 0 and 0 or count)
			widget.grayHover:setOpacity(count == 0 and '0.5' or '0.0')
			break
		end
	end

	local firstChild = mainMarket.sellOffersList:getChildren()[1]
	if firstChild then
		mainMarket.sellOffersList:onChildFocusChange(firstChild, nil, KeyboardFocusReason)
	end

	firstChild = mainMarket.buyOffersList:getChildren()[1]
	if firstChild then
		mainMarket.buyOffersList:onChildFocusChange(firstChild, nil, KeyboardFocusReason)
	end
end

function onSelectChildItem(widget, selected, oldFocus)
	if not selected or not selected.item then return end

	if oldFocus then
		oldFocus:setBackgroundColor('#271b17')
	end

	if lastSelectedItem.lastWidget then
		lastSelectedItem.lastWidget:setBackgroundColor('#271b17')
	end

	local item = selected.item:getItem()
	if not item then return end

	selected:setBackgroundColor('#35241d')
	local itemID = selected.item:getItemId()
	local itemTier = item:getTier()
	if lastSelectedItem.itemId == itemID and lastSelectedItem.tier == itemTier then
		return true
	end

	marketWindow.contentPanel.selectedItem:setItemId(itemID)
	marketWindow.contentPanel.selectedItem:setTier(itemTier)
	setItemRarityFrame(marketWindow.contentPanel.selectedItem, itemID)

	lastSelectedItem = {itemId = itemID, tier = itemTier, lastWidget = selected}

	if itemID == 22118 then
		marketWindow.contentPanel.selectedItem:getItem():setCount(g_game.getTransferableTibiaCoins())
	else
		marketWindow.contentPanel.selectedItem:getItem():setCount(getDepotItemCount(itemID, itemTier))
	end
	onClearMainMarket(false)
	g_game.sendMarketAction(3, itemID, itemTier)
end

function onClearMainMarket(cleanList)
	buyOffers = {}
	sellOffers = {}
	MarketOwnOffers.mySellOffers = {}
	MarketOwnOffers.myBuyOffers = {}
	lastItemID = 0
	lastItemTier = 0
	mainMarket.sellAcceptButton:setEnabled(false)
	mainMarket.buyAcceptButton:setEnabled(false)
	mainMarket.sellOffersList:destroyChildren()
	mainMarket.buyOffersList:destroyChildren()
	mainMarket.amountSellScrollBar:setRange(0, 0)
	mainMarket.amountBuyScrollBar:setRange(0, 0)
	mainMarket.piecePriceCreate:clearText()

	marketWindow.contentPanel.detailsMarket.detailsList:destroyChildren()
	marketWindow.contentPanel.detailsMarket.statisticsList:destroyChildren()

	if cleanList then
		updateSellCount(nil, 0)
		updateBuyCount(nil, 0)
		clearMarketItemWidget(marketWindow.contentPanel.selectedItem)
		marketWindow.contentPanel.itemList:destroyChildren()
	end

	cache.SCROLL_BUY_OFFERS.listMin = 0
	cache.SCROLL_BUY_OFFERS.listMax = 0
	cache.SCROLL_BUY_OFFERS.listFit = 0
	cache.SCROLL_BUY_OFFERS.listMin = 0
	cache.SCROLL_BUY_OFFERS.listPool = {}
	cache.SCROLL_BUY_OFFERS.listData = {}
	cache.SCROLL_BUY_OFFERS.lastSelected = 0

	cache.SCROLL_SELL_OFFERS.listMin = 0
	cache.SCROLL_SELL_OFFERS.listMax = 0
	cache.SCROLL_SELL_OFFERS.listFit = 0
	cache.SCROLL_SELL_OFFERS.listMin = 0
	cache.SCROLL_SELL_OFFERS.listPool = {}
	cache.SCROLL_SELL_OFFERS.listData = {}
	cache.SCROLL_SELL_OFFERS.lastSelected = 0

	local buyListScroll = marketWindow:recursiveGetChildById("buyOffersListScroll")
	buyListScroll.onValueChange = nil
	buyListScroll:setValue(0)
	buyListScroll:setMinimum(0)
	buyListScroll:setMaximum(0)

	local sellListScroll = marketWindow:recursiveGetChildById("sellOffersListScroll")
	sellListScroll.onValueChange = nil
	sellListScroll:setValue(0)
	sellListScroll:setMinimum(0)
	sellListScroll:setMaximum(0)

	mainMarket.totalValue:setText(0)
	mainMarket.totalSellValue:setText(0)

  mainMarket.grossAmount:setText(0)
  mainMarket.grossAmount.value = 0
end

function toggleShowLockerOnly(widget, checked)
	showLockerOnly = checked
	if not lastSelectedCategory then
		lastSelectedItem = {}
		onClearMainMarket(true)
		if #marketWindow.contentPanel.searchText:getText() > 0 then
			onSearchItem(marketWindow.contentPanel.searchText)
		end
		return true
	end

	onSelectChildCategory(nil, lastSelectedCategory, true)
end

function onSelectSellOffer(widget, selected, oldFocus)
	if not selected then return end

	local money = getTotalMoney()
	if oldFocus then
		local offer = sellOffers[cache.SCROLL_SELL_OFFERS.lastSelected]
		local offerPrice = offer and offer.price or 0
		local color = money >= offerPrice and "#c0c0c0" or "#808080"
		oldFocus:setBackgroundColor(oldFocus:getId())
		oldFocus.piecePrice:setColor(color)
		oldFocus.totalPrice:setColor(color)
		oldFocus.name:setColor(color)
		oldFocus.amount:setColor(color)
		oldFocus.endAt:setColor(color)
	end

	selected:setBackgroundColor('#35241d')
	selected.piecePrice:setColor("#f4f4f4")
	selected.totalPrice:setColor("#f4f4f4")
	selected.name:setColor("#f4f4f4")
	selected.amount:setColor("#f4f4f4")
	selected.endAt:setColor("#f4f4f4")
	cache.SCROLL_SELL_OFFERS.lastSelected = selected:getActionId()

	local currentOffer = sellOffers[cache.SCROLL_SELL_OFFERS.lastSelected]
	if money < currentOffer.price then
		mainMarket.sellAcceptButton:setEnabled(false)
		updateSellCount(nil, 0)
		mainMarket.amountSellScrollBar:setRange(0, 0)
		return
	end

	local maxValue = math.min(currentOffer.amount, math.floor(money / currentOffer.price))
	mainMarket.amountSellScrollBar:setValue(1)
	mainMarket.amountSellScrollBar:setRange(1, maxValue)
	mainMarket.amountSellScrollBar:setIncrementStep(1)
	mainMarket.totalValue:setText(comma_value(currentOffer.price))
	mainMarket.sellAcceptButton:setEnabled(true)

	local startValue = 1
	if not table.empty(lastSelectedItem) and lastSelectedItem.itemId == 22118 then
		local sellCount = math.floor(money / (currentOffer.price * 25))
		if sellCount > 0 then
			mainMarket.amountSellScrollBar:setRange(25, math.min(currentOffer.amount, sellCount * 25))
			mainMarket.amountSellScrollBar:setValue(25)
			mainMarket.sellAcceptButton:setEnabled(true)
			mainMarket.amountSellScrollBar:setStep(25)
			mainMarket.amountSellScrollBar:setIncrementStep(25)
			startValue = 25
		else
			mainMarket.amountSellScrollBar:setRange(0, 0)
			mainMarket.amountSellScrollBar:setValue(0)
			mainMarket.sellAcceptButton:setEnabled(false)
			startValue = 0
		end
	end

  	updateSellCount(nil, startValue)
	local sellListScroll = marketWindow:recursiveGetChildById("sellOffersListScroll")
	if cache.SCROLL_SELL_OFFERS.listFit > 11 then
		onSellListValueChange(sellListScroll, sellListScroll:getValue(), 0)
	end
end

function onSelectBuyOffer(widget, selected, oldFocus)
	if not selected or table.empty(lastSelectedItem) then return end

	local count = getDepotItemCount(lastItemID, lastItemTier)
	if oldFocus then
		local color = count > 0 and "#c0c0c0" or "#808080"
		oldFocus:setBackgroundColor(oldFocus:getId())
		oldFocus.piecePrice:setColor(color)
		oldFocus.totalPrice:setColor(color)
		oldFocus.name:setColor(color)
		oldFocus.amount:setColor(color)
		oldFocus.endAt:setColor(color)
	end

	selected:setBackgroundColor('#35241d')
	selected.piecePrice:setColor("#f4f4f4")
	selected.totalPrice:setColor("#f4f4f4")
	selected.name:setColor("#f4f4f4")
	selected.amount:setColor("#f4f4f4")
	selected.endAt:setColor("#f4f4f4")
	cache.SCROLL_BUY_OFFERS.lastSelected = selected:getActionId()

	if count == 0 then
		mainMarket.buyAcceptButton:setEnabled(false)
		mainMarket.amountBuyScrollBar:setRange(0, 0)
		updateBuyCount(nil, 0)
		return
	end

	local currentOffer = buyOffers[cache.SCROLL_BUY_OFFERS.lastSelected]
	mainMarket.amountBuyScrollBar:setValue(lastSelectedItem.itemId == 22118 and 25 or 1)
	mainMarket.amountBuyScrollBar:setRange(1, math.min(count, currentOffer.amount))
	mainMarket.amountBuyScrollBar:setIncrementStep(1)
	mainMarket.totalSellValue:setText(comma_value(currentOffer.price))
	mainMarket.buyAcceptButton:setEnabled(true)

	local steps = getCoinStepValue(lastSelectedItem.itemId)
	mainMarket.amountBuyScrollBar:setStep(steps)

	if lastSelectedItem.itemId == 22118 then
		local startValue = 0
		local coinBalance = g_game.getTransferableTibiaCoins()
		local buyCount = math.floor(coinBalance / 25)
		if buyCount > 0 then
			mainMarket.amountBuyScrollBar:setRange(25, math.min(currentOffer.amount, buyCount * 25))
			mainMarket.amountBuyScrollBar:setValue(25)
			mainMarket.buyAcceptButton:setEnabled(true)
			mainMarket.amountBuyScrollBar:setStep(25)
			mainMarket.amountBuyScrollBar:setIncrementStep(25)
			startValue = 25
		else
			mainMarket.amountBuyScrollBar:setRange(0, 0)
			mainMarket.amountBuyScrollBar:setValue(0)
			mainMarket.buyAcceptButton:setEnabled(false)
		end

		updateBuyCount(nil, startValue)
	end

	local buyListScroll = marketWindow:recursiveGetChildById("buyOffersListScroll")
	if cache.SCROLL_BUY_OFFERS.listFit > 11 then
		onBuyListValueChange(buyListScroll, buyListScroll:getValue(), 0)
	end
end

function updateSellCount(widget, value)
	if table.empty(lastSelectedItem) then
		return
	end

	if widget and widget:getIncrementValue() > 1 then
		value = math.cround(value, widget:getIncrementValue())
	end

	if cache.SCROLL_SELL_OFFERS.lastSelected == 0 then
		mainMarket.amountSell:setText(value)
		mainMarket.totalValue:setText(value)
		return
	end

	local steps = getCoinStepValue(lastSelectedItem.itemId)
	mainMarket.amountSellScrollBar:setStep(steps)

	local currentOffer = sellOffers[cache.SCROLL_SELL_OFFERS.lastSelected]
	if currentOffer then
		mainMarket.amountSell:setText(value)
		mainMarket.totalValue:setText(comma_value(currentOffer.price * value))
	end
end

function updateBuyCount(widget, value)
	if widget and widget:getIncrementValue() > 1 then
		value = math.cround(value, widget:getIncrementValue())
	end

	if cache.SCROLL_BUY_OFFERS.lastSelected == 0 then
		mainMarket.amountBuy:setText(value)
		mainMarket.totalSellValue:setText(convertGold(value))
		return
	end

	local currentOffer = buyOffers[cache.SCROLL_BUY_OFFERS.lastSelected]
	if currentOffer then
		mainMarket.amountBuy:setText(value)
		mainMarket.totalSellValue:setText(convertGold(currentOffer.price * value))
	end
end

function onAcceptSellOffer()
	if cache.SCROLL_SELL_OFFERS.lastSelected == 0 then
		return
	end

	local currentOffer = sellOffers[cache.SCROLL_SELL_OFFERS.lastSelected]
	if not currentOffer then
		return
	end

  local amount = tonumber(mainMarket.amountSell:getText())

	g_game.sendMarketAcceptOffer(currentOffer.timestamp, currentOffer.counter, amount)
end

function onAcceptBuyOffer()
	if cache.SCROLL_BUY_OFFERS.lastSelected == 0 then
		return
	end

	local currentOffer = buyOffers[cache.SCROLL_BUY_OFFERS.lastSelected]
	if not currentOffer then
		return
	end

  local amount = tonumber(mainMarket.amountBuy:getText())

	g_game.sendMarketAcceptOffer(currentOffer.timestamp, currentOffer.counter, amount)
end

function updateCreateCount(widget, value)
	if widget and widget:getIncrementValue() > 1 then
		value = math.cround(value, widget:getIncrementValue())
	end

	mainMarket.createOfferAmount:setText("Amount: " .. value)
	onPiecePriceEdit(mainMarket.piecePriceCreate)
end

function onPiecePriceEdit(widget)
	if table.empty(lastSelectedItem) then
		return
	end

	if #widget:getText() == 0 then
		mainMarket.grossAmount.value = 0
		mainMarket.profitAmount:setText(0)
		mainMarket.feeAmount:setText(0)
		mainMarket.createButton:setEnabled(false)
		mainMarket.amountCreateScrollBar:setIncrementStep(25)
		mainMarket.amountCreateScrollBar:setRange(0, 0)
		return
	end

	local currentText = widget:getText():gsub("[^%d]", "")
	widget:setText(currentText)

	if #currentText > 12 then
		currentText = currentText:sub(1, -2)
		widget:setText(currentText)
	end

	local isTibiaCoin = lastSelectedItem.itemId == 22118
	local numericValue = tonumber(currentText)
	if not numericValue then
		return true
	end

	if numericValue >= 999999999999 then
		currentText = "999999999999"
		widget:setText(currentText)
	end

	local amount = mainMarket.amountCreateScrollBar:getValue()
	if mainMarket.amountCreateScrollBar:getIncrementValue() > 1 then
		amount = math.cround(amount, mainMarket.amountCreateScrollBar:getIncrementValue())
	end

	local fee = math.ceil((numericValue / 50) * amount)
	if fee < 20 then
		fee = 20
	elseif fee > 1000000 then
		fee = 1000000
	end

	local thing = g_things.getThingType(lastSelectedItem.itemId)
	local stackable = thing:isStackable()
	local maxCount = stackable and 64000 or 2000

	local maxValue = 999999999999
	if not isTibiaCoin and numericValue * amount >= maxValue then
		local newAmount = math.floor(maxValue / numericValue)
		amount = newAmount
		maxCount = newAmount
		mainMarket.amountCreateScrollBar:setValue(amount)
	end

	local steps = getCoinStepValue(lastSelectedItem.itemId)
	mainMarket.amountCreateScrollBar:setIncrementStep(1)
	if isTibiaCoin then
		steps = 25
		mainMarket.amountCreateScrollBar:setIncrementStep(25)
	end

	mainMarket.amountCreateScrollBar:setStep(steps)

	if currentActionType == 0 then
		local grossProfit = numericValue * amount
		mainMarket.grossAmount:setText(convertGold(grossProfit, true))
		mainMarket.grossAmount.value = numericValue
		mainMarket.profitAmount:setText(convertGold(grossProfit + fee, true))
		mainMarket.createButton:setEnabled(true)
		mainMarket.feeAmount:setText(convertGold(fee))

		local balance = getTotalMoney()
		local barCount = 0
		if isTibiaCoin then
			barCount = math.floor(balance / (numericValue * 25))
			if mainMarket.amountCreateScrollBar:getValue() <= 1 then
				mainMarket.amountCreateScrollBar:setValue(25)
				mainMarket.amountCreateScrollBar:setStep(25)
				mainMarket.amountCreateScrollBar:setIncrementStep(25)
			end

			if barCount > 0 then
				mainMarket.amountCreateScrollBar:setRange(25, barCount * 25)
			else
				mainMarket.amountCreateScrollBar:setRange(0, 0)
			end
		else
			if getTotalMoney() >= numericValue then
				barCount = math.min(maxCount, getTotalMoney() / numericValue)
			end
			if barCount > 0 then
				mainMarket.amountCreateScrollBar:setRange(1, barCount)
			else
				mainMarket.amountCreateScrollBar:setRange(0, 0)
			end
		end
	else
		local itemCount = isTibiaCoin and g_game.getTransferableTibiaCoins() or getDepotItemCount(lastSelectedItem.itemId, lastSelectedItem.tier)
		if itemCount > 0 then
			if isTibiaCoin and itemCount < 25 then
				mainMarket.amountCreateScrollBar:setValue(0)
				mainMarket.amountCreateScrollBar:setStep(25)
				mainMarket.amountCreateScrollBar:setIncrementStep(25)
			else
				mainMarket.amountCreateScrollBar:setRange((isTibiaCoin and 25 or 1), math.min(maxCount, itemCount))
				mainMarket.createButton:setEnabled(true)
			end
		else
			mainMarket.amountCreateScrollBar:setRange(0, 0)
		end

		local grossProfit = numericValue * amount
		mainMarket.grossAmount:setText(convertGold(grossProfit, true))
		mainMarket.grossAmount.value = numericValue
		mainMarket.profitAmount:setText(convertGold(grossProfit - fee, true))
		mainMarket.feeAmount:setText(convertGold(fee))
	end
end

function changeOfferType(widget, primary)
	if widget:isChecked() then
		return
	end

	if primary then
		widget:setChecked(true)
		mainMarket.createOfferBuy:setChecked(false)
		currentActionType = 1
		mainMarket.grossProfit:setText("Gross Profit:")
		mainMarket.profitLabel:setText("Total Profit:")
	else
		widget:setChecked(true)
		mainMarket.createOfferSell:setChecked(false)
		currentActionType = 0
		mainMarket.grossProfit:setText("Price:")
		mainMarket.profitLabel:setText("Total Price:")
	end

	mainMarket.piecePriceCreate:clearText()
end

function createMarketOffer()
	if table.empty(lastSelectedItem) then
		return
	end

	local n = mainMarket.createOfferAmount:getText()
	local amount = n:gsub("%D", "")
	local price = tonumber(mainMarket.grossAmount.value)
	if currentActionType == 0 and getTotalMoney() < price then
		return
	end
	mainMarket.amountCreateScrollBar:setRange(0, 0)
	mainMarket.createButton:setEnabled(false)
	mainMarket.amountCreateScrollBar:setValue(0)
	mainMarket.amountCreateScrollBar:setIncrementStep(1)
	mainMarket.grossAmount:setText("0")
	mainMarket.grossAmount.value = 0
	mainMarket.profitAmount:setText("0")
	mainMarket.feeAmount:setText("0")
	mainMarket.piecePriceCreate:clearText()

	lastItemID = 0
	lastItemTier = 0

	g_game.sendMarketCreateOffer(currentActionType, lastSelectedItem.itemId, lastSelectedItem.tier, amount, price, mainMarket.anonymous:isChecked())
end

function onSearchItem(textField)
	lastSelectedItem = {}
	if #textField:getText() == 0 then
		onClearSearch()
		return
	end

	if lastSelectedCategory then
		local colourCount = 0
		for i, pair in ipairs(categoryList) do
			local colour = colourCount % 2 == 0 and '#414141' or '#484848'
			if pair[2] == lastSelectedCategory:getText() then
				lastSelectedCategory:setBackgroundColor(colour)
				lastSelectedCategory:setColor('#c0c0c0')
			end
			colourCount = colourCount + 1
		end
		lastSelectedCategory = nil
	end

	local itemList = marketWindow:recursiveGetChildById("itemList")
	if not itemList then
		return true
	end

	itemList:setVirtualOffset({x = 0, y = 0})

	cache.SCROLL_MARKET_ITEMS.listFit = math.floor(itemList:getHeight() / 36) + 1
	cache.SCROLL_MARKET_ITEMS.listMin = 0
	cache.SCROLL_MARKET_ITEMS.listPool = {}
	cache.SCROLL_MARKET_ITEMS.listData = {}

	marketWindow.contentPanel.itemList:destroyChildren()

	onClearMainMarket(true)

	marketWindow.contentPanel.mainMarket.getPotionsButton:setVisible(false)
	clearMarketItemWidget(marketWindow.contentPanel.selectedItem)

	itemList.onChildFocusChange = function(self, selected, oldFocus) onSelectChildItem(self, selected, oldFocus) end

	if sortButtons["classFilter"] == -1 then
		marketWindow.contentPanel.classFilter:clearOptions()
		marketWindow.contentPanel.classFilter:addOption("All", nil, true)
		marketWindow.contentPanel.classFilter:addOption("None", nil, true)
		for i = 1, 4 do
			marketWindow.contentPanel.classFilter:addOption("Class " .. i, nil, true)
		end
	end

	if sortButtons["tierFilter"] == 0 then
		marketWindow.contentPanel.tierFilter:clearOptions()
		for i = 0, 10 do
			marketWindow.contentPanel.tierFilter:addOption("Tier " .. i, nil, true)
		end
	end

	local tier = sortButtons["tierFilter"] or 0
	for c = MarketCategory.First, MarketCategory.Last do
		local marketItem = marketItems[c]
		if marketItem then
			for _, data in pairs(marketItem) do
				if not checkSortMarketOptions(data) or (showLockerOnly and getDepotItemCount(data.thingType:getId(), tier) == 0)then
					goto continue
				end

				if matchText(textField:getText(), data.marketData.name) then
					addMarketListItem(data, tier)
				end

				::continue::
			end
		else
			perror("MarketData ".. c .. " is nil")
		end
	end

	for i, itemInfo in pairs(cache.SCROLL_MARKET_ITEMS.listData) do
		if #cache.SCROLL_MARKET_ITEMS.listPool >= cache.SCROLL_MARKET_ITEMS.listFit then
			break
		end

		local itemTier = getMarketItemTier(itemInfo, tier or 0)
		local count = getMarketItemCount(itemInfo, itemTier)
		if not checkSortMarketOptions(itemInfo) or (count == 0 and showLockerOnly) then
			goto continue
		end

		local widget = g_ui.createWidget('MarketItemList', itemList)
		if widget.setIgnoreEqualFocus then widget:setIgnoreEqualFocus(true) end
		widget.item:setItemId(itemInfo.thingType:getId())
		setItemRarityFrame(widget.item, itemInfo.thingType:getId())

		widget.name:setText(itemInfo.marketData.name)
		if widget.name.isOfflimit and widget.name:isOfflimit() then
			widget.name:setText(short_text(itemInfo.marketData.name, 15))
			widget.name:setTooltip(itemInfo.marketData.name)
		end

		widget:setBackgroundColor('#271b17')
		widget.item:getItem():setCount(count)
		widget.item:setActionId(i)
		widget.item:setTooltip(tr("%s%s%s%s", comma_value(count), "x", (count > 65000 and "+ " or " "), itemInfo.marketData.name))

		widget.item:setTier(itemTier)

		if not widget.name:isTextWraped() then
			widget.name:setMarginTop(1)
		end

		if count > 0 then
			widget.grayHover:setOpacity('0.0')
		end

		table.insert(cache.SCROLL_MARKET_ITEMS.listPool, widget)

		:: continue ::
	end

	cache.SCROLL_MARKET_ITEMS.listMax = #cache.SCROLL_MARKET_ITEMS.listData

	local sellScrollbar = marketWindow:recursiveGetChildById("itemListScroll")
	sellScrollbar:setValue(0)
	sellScrollbar:setMinimum(cache.SCROLL_MARKET_ITEMS.listMin)
	sellScrollbar:setMaximum(#cache.SCROLL_MARKET_ITEMS.listPool < 8 and 0 or math.max(0, cache.SCROLL_MARKET_ITEMS.listMax - #cache.SCROLL_MARKET_ITEMS.listPool) + 2)

	sellScrollbar.onValueChange = function(self, value, delta) onItemListValueChange(self, value, delta) end
	itemList:setVirtualOffset({x = 0, y = 0})
end

function onShowRedirect(item)
	lastSelectedItem = {}

	if lastSelectedCategory then
		local colourCount = 0
		for i, pair in ipairs(categoryList) do
			local colour = colourCount % 2 == 0 and '#414141' or '#484848'
			if pair[2] == lastSelectedCategory:getText() then
				lastSelectedCategory:setBackgroundColor(colour)
				lastSelectedCategory:setColor('#c0c0c0')
			end
			colourCount = colourCount + 1
		end
		lastSelectedCategory = nil
	end

	local itemList = marketWindow:recursiveGetChildById("itemList")
	if not itemList then
		return true
	end

	itemList:setVirtualOffset({x = 0, y = 0})

	cache.SCROLL_MARKET_ITEMS.listFit = math.floor(itemList:getHeight() / 36) + 1
	cache.SCROLL_MARKET_ITEMS.listMin = 0
	cache.SCROLL_MARKET_ITEMS.listPool = {}
	cache.SCROLL_MARKET_ITEMS.listData = {}

	marketWindow.contentPanel.itemList:destroyChildren()

	onClearMainMarket(true)

	marketWindow.contentPanel.mainMarket.getPotionsButton:setVisible(false)
	clearMarketItemWidget(marketWindow.contentPanel.selectedItem)

	itemList.onChildFocusChange = function(self, selected, oldFocus) onSelectChildItem(self, selected, oldFocus) end

	if sortButtons["classFilter"] == -1 then
		marketWindow.contentPanel.classFilter:clearOptions()
		marketWindow.contentPanel.classFilter:addOption("All", nil, true)
		marketWindow.contentPanel.classFilter:addOption("None", nil, true)
		for i = 1, 4 do
			marketWindow.contentPanel.classFilter:addOption("Class " .. i, nil, true)
		end
	end

	if sortButtons["tierFilter"] == 0 then
		marketWindow.contentPanel.tierFilter:clearOptions()
	end

	local tier = 0
	for c = MarketCategory.First, MarketCategory.Last do
		local marketItem = marketItems[c]
		if marketItem then
			for _, data in pairs(marketItem) do
				if item:getId() == data.thingType:getId() then
					local tierCount = item:getClassification()
					if tierCount == 4 then
						tierCount = 10
					end

					-- Duplicate items for tiers
					for i = 0, tierCount do
						local tableCopy = table.copy(data)
						tableCopy.tier = i
						table.insert(cache.SCROLL_MARKET_ITEMS.listData, tableCopy)
					end

					break
				end
			end
		end
	end

	for i, itemInfo in pairs(cache.SCROLL_MARKET_ITEMS.listData) do
		if #cache.SCROLL_MARKET_ITEMS.listPool >= cache.SCROLL_MARKET_ITEMS.listFit then
			break
		end

		local itemTier = getMarketItemTier(itemInfo, tier or 0)
		local count = getMarketItemCount(itemInfo, itemTier)
		if not checkSortMarketOptions(itemInfo) or (count == 0 and showLockerOnly) then
			goto continue
		end

		local widget = g_ui.createWidget('MarketItemList', itemList)
		if widget.setIgnoreEqualFocus then widget:setIgnoreEqualFocus(true) end
		widget.item:setItemId(itemInfo.thingType:getId())
		setItemRarityFrame(widget.item, itemInfo.thingType:getId())

		widget.name:setText(itemInfo.marketData.name)
		if widget.name.isOfflimit and widget.name:isOfflimit() then
			widget.name:setText(short_text(itemInfo.marketData.name, 15))
			widget.name:setTooltip(itemInfo.marketData.name)
		end

		widget:setBackgroundColor('#271b17')
		widget.item:getItem():setCount(count)
		widget.item:setActionId(i)
		widget.item:setTooltip(tr("%s%s%s%s", comma_value(count), "x", (count > 65000 and "+ " or " "), itemInfo.marketData.name))

		-- Tier as index
		widget.item:setTier(itemTier)

		if not widget.name:isTextWraped() then
			widget.name:setMarginTop(1)
		end

		if count > 0 then
			widget.grayHover:setOpacity('0.0')
		end

		table.insert(cache.SCROLL_MARKET_ITEMS.listPool, widget)

		:: continue ::
	end

	cache.SCROLL_MARKET_ITEMS.listMax = #cache.SCROLL_MARKET_ITEMS.listData

	local sellScrollbar = marketWindow:recursiveGetChildById("itemListScroll")
	sellScrollbar:setValue(0)
	sellScrollbar:setMinimum(cache.SCROLL_MARKET_ITEMS.listMin)
	sellScrollbar:setMaximum(#cache.SCROLL_MARKET_ITEMS.listPool < 8 and 0 or math.max(0, cache.SCROLL_MARKET_ITEMS.listMax - #cache.SCROLL_MARKET_ITEMS.listPool) + 2)

	sellScrollbar.onValueChange = function(self, value, delta) onItemListValueChange(self, value, delta) end
	itemList:setVirtualOffset({x = 0, y = 0})

	g_game.doThing(false)
	itemList:focusChild(itemList:getFirstChild())
	g_game.doThing(true)
end

-- Clear one/two handed filter
function onClearHandFilter()
	marketWindow.contentPanel.oneButton:setEnabled(false)
	marketWindow.contentPanel.oneButton:setChecked(false)
	marketWindow.contentPanel.twoButton:setEnabled(false)
	marketWindow.contentPanel.twoButton:setChecked(false)
	sortButtons["oneButton"] = false
	sortButtons["twoButton"] = false
end

function onClearSearch(clearHands)
	marketWindow.contentPanel.searchText:clearText(true)
	onClearMainMarket(true)
	if clearHands then
		onClearHandFilter()
	end
	marketWindow.contentPanel.itemList:updateScrollBars()
end

function checkSortMarketOptions(itemData)
	local player = g_game.getLocalPlayer()
	if not player then
		return false
	end

	local playerLevel = player:getLevel()
	local playerVocation = translateWheelVocation(player:getVocation())

	if sortButtons["levelButton"] then
		if itemData.marketData.requiredLevel > playerLevel then
			return false
		end
	end

	if sortButtons["vocButton"] then
		local itemVocation = itemData.marketData.restrictVocation
		if #itemVocation > 0 and not table.contains(itemVocation, playerVocation) then
			return false
		end
	end

	if sortButtons["oneButton"] then
		if itemData.thingType:getClothSlot() ~= 6 then
			return false
		end
	end

	if sortButtons["twoButton"] then
		if itemData.thingType:getClothSlot() ~= 0 then
			return false
		end
	end

	if sortButtons["classFilter"] ~= -1 then
		if itemData.thingType:getClassification() ~= sortButtons["classFilter"] then
			return false
		end
	end

	if sortButtons["tierFilter"] > 0 and itemData.thingType:getClassification() == 0 then
		return false
	end

	return true
end

function onSortMarketFields(widget, checked)
	if table.contains({'oneButton', 'twoButton'}, widget:getId()) then
		widget:setChecked(not checked)
		sortButtons[widget:getId()] = not checked
		if widget:getId() == 'oneButton' then
			sortButtons["twoButton"] = false
			marketWindow.contentPanel.twoButton:setChecked(false)
		elseif widget:getId() == 'twoButton' then
			marketWindow.contentPanel.oneButton:setChecked(false)
			sortButtons["oneButton"] = false
		end
	elseif table.contains({'classFilter', 'tierFilter'}, widget:getId()) then
		if widget:getId() == "classFilter" then
			sortButtons["classFilter"] = checked > 1 and (checked - 2) or -1
		elseif widget:getId() == "tierFilter" then
			sortButtons["tierFilter"] = math.max(0, checked - 1)
		end
	elseif table.contains({'levelButton', 'vocButton'}, widget:getId()) then
		widget:setChecked(not checked)
		sortButtons[widget:getId()] = not checked
	end

	if not lastSelectedCategory then
		lastSelectedItem = {}
		onClearMainMarket(true)
		if #marketWindow.contentPanel.searchText:getText() > 0 then
			onSearchItem(marketWindow.contentPanel.searchText)
		end
		return true
	end

	lastSelectedItem = {}
	onClearMainMarket(true)
	onSelectChildCategory(nil, lastSelectedCategory, true)
end

function onMarketDetail(itemID, tier, details, purchase, sale)
	marketWindow.contentPanel.detailsMarket.detailsList:destroyChildren()
	for i, str in pairs(details) do
		if #str == 0 then
			goto continue
		end

		local widget = g_ui.createWidget('DatailsLabel', marketWindow.contentPanel.detailsMarket.detailsList)
		widget:setText(MarketDetailNames[i + 1] .. str)
		:: continue ::
	end

	marketWindow.contentPanel.detailsMarket.statisticsList:destroyChildren()
	local purchaseWidget = g_ui.createWidget('StatisticWidget', marketWindow.contentPanel.detailsMarket.statisticsList)
	purchaseWidget.header:setText("Buy Offers:")
	if #purchase > 0 then
		local transactionsText = purchaseWidget.transactions:getText():gsub("0", purchase[1].numTransactions)
		purchaseWidget.transactions:setText(transactionsText)

		local highestText = purchaseWidget.highestPrice:getText():gsub("0", comma_value(purchase[1].highestPrice))
		purchaseWidget.highestPrice:setText(highestText)

		local avgText = purchaseWidget.avgPrice:getText():gsub("0", comma_value(math.floor(purchase[1].totalPrice / purchase[1].numTransactions)))
		purchaseWidget.avgPrice:setText(avgText)

		local lowText = purchaseWidget.lowPrice:getText():gsub("0", comma_value(purchase[1].lowestPrice))
		purchaseWidget.lowPrice:setText(lowText)
	end

	local saleWidget = g_ui.createWidget('StatisticWidget', marketWindow.contentPanel.detailsMarket.statisticsList)
	saleWidget.header:setText("Sell Offers:")
	if #sale > 0 then
		local transactionsText = saleWidget.transactions:getText():gsub("0", sale[1].numTransactions)
		saleWidget.transactions:setText(transactionsText)

		local highestText = saleWidget.highestPrice:getText():gsub("0", comma_value(sale[1].highestPrice))
		saleWidget.highestPrice:setText(highestText)

		local avgText = saleWidget.avgPrice:getText():gsub("0", comma_value(math.floor(sale[1].totalPrice / sale[1].numTransactions)))
		saleWidget.avgPrice:setText(avgText)

		local lowText = saleWidget.lowPrice:getText():gsub("0", comma_value(sale[1].lowestPrice))
		saleWidget.lowPrice:setText(lowText)
	end
end

function getItemNameById(itemId)
  for c = MarketCategory.First, MarketCategory.WeaponsAll do
		local marketItem = marketItems[c]
		if marketItem then
			for _, data in pairs(marketItem) do
				if data.thingType:getId() == itemId then
					return data.marketData.name
				end
			end
		end
	end
  return ''
end

function onRedirect(item)
  g_game.sendMarketAction(3, item:getId(), 0)

  scheduleEvent(function()
	onShowRedirect(item)
  end, 100)
end

function focusPrevItemWidget(list)
	if cache.SCROLL_MARKET_ITEMS.scrollDelay >= g_clock.millis() then
		return
	end

	local c = list:getFocusedChild()
	if not c then return end
	local cIndex = list:getChildIndex(c)
	local scrollbar = marketWindow:recursiveGetChildById('itemListScroll')
	if scrollbar:getMaximum() > 0 and cIndex == 1 and scrollbar:getValue() == scrollbar:getMinimum() then
		return
	end

	if cIndex > 1 then
		if cIndex < 3 then
			list:setVirtualOffset({x = 0, y = 0})
		end
	  	list:focusPreviousChild(KeyboardFocusReason)
	else
	  scrollbar:setValue(scrollbar:getValue() - 1)
	  if cIndex == 1 then
		local a = list:getFocusedChild()
		local nextChild = list:getChildByIndex(cIndex + 1)
		if nextChild then
			list:focusChild(nextChild)
		end
		list:focusChild(a)
		list:setVirtualOffset({x = 0, y = 0})
	  end
	end

	cache.SCROLL_MARKET_ITEMS.scrollDelay = g_clock.millis() + 30
end
  
function focusNextItemWidget(list)
	if cache.SCROLL_MARKET_ITEMS.scrollDelay >= g_clock.millis() then
		return
	end

	local c = list:getFocusedChild()
	local cIndex = list:getChildIndex(c)
	local cCount = list:getChildCount()
	local scrollbar = marketWindow:recursiveGetChildById('itemListScroll')
	if scrollbar:getMaximum() > 0 and cIndex == cCount and scrollbar:getValue() == scrollbar:getMaximum() then
		return
	end

	if cIndex < (cCount - 1) then
	  list:focusNextChild(KeyboardFocusReason)
	else
	  scrollbar:setValue(scrollbar:getValue() + 1)
	  if cIndex == (cCount - 1) then
		list:focusNextChild(KeyboardFocusReason)
		if scrollbar:getMaximum() > 0 then
			list:setVirtualOffset({x = 0, y = 28})
		end
	  elseif cIndex == cCount then
		if scrollbar:getMaximum() > 0 then
			list:setVirtualOffset({x = 0, y = 28})
		end

		local prevChild = list:getChildByIndex(cIndex - 1)
		if prevChild then
			list:focusChild(prevChild)
		end
		list:focusChild(c)
	  end
	end

	cache.SCROLL_MARKET_ITEMS.scrollDelay = g_clock.millis() + 30
end

function focusPrevSellLabel(list)
	local c = list:getFocusedChild()
	if not c then return end
	local cIndex = list:getChildIndex(c)

	local scrollbar = list:getParent():recursiveGetChildById('sellOffersListScroll')
	if cache.SCROLL_SELL_OFFERS.lastSelected - 1 > 0 then
		cache.SCROLL_SELL_OFFERS.lastSelected = cache.SCROLL_SELL_OFFERS.lastSelected - 1
	end

	if cIndex > 1 then
	  list:focusPreviousChild(KeyboardFocusReason)
	else
	  scrollbar:setValue(scrollbar:getValue() - 1)
	  list:focusChild(c)
	  if cIndex == 1 then
		list:focusPreviousChild(KeyboardFocusReason)
	  end
	end

	scrollbar:setValue(scrollbar:getValue())
end
  
function focusNextSellLabel(list)
	local scrollbar = list:getParent():recursiveGetChildById('sellOffersListScroll')

	local c = list:getFocusedChild()
	local cIndex = list:getChildIndex(c)
	local cCount = list:getChildCount()

	if cIndex < cCount then
	  list:focusNextChild(KeyboardFocusReason)
	else
	  scrollbar:setValue(scrollbar:getValue() + 1)
	  list:focusChild(c)
	  if cIndex == cCount then
		list:focusNextChild(KeyboardFocusReason)
	  end
	end

	if cache.SCROLL_SELL_OFFERS.lastSelected + 1 < #cache.SCROLL_SELL_OFFERS.listData then
		cache.SCROLL_SELL_OFFERS.lastSelected = cache.SCROLL_SELL_OFFERS.lastSelected + 1
	end
end

function focusPrevBuyLabel(list)
	local c = list:getFocusedChild()
	if not c then return end
	local cIndex = list:getChildIndex(c)
	local scrollbar = list:getParent():recursiveGetChildById('buyOffersListScroll')

	if cache.SCROLL_BUY_OFFERS.lastSelected - 1 > 0 then
		cache.SCROLL_BUY_OFFERS.lastSelected = cache.SCROLL_BUY_OFFERS.lastSelected - 1
	end

	if cIndex > 1 then
	  list:focusPreviousChild(KeyboardFocusReason)
	else
	  scrollbar:setValue(scrollbar:getValue() - 1)
	  list:focusChild(c)
	  if cIndex == 1 then
		list:focusPreviousChild(KeyboardFocusReason)
	  end
	end
end
  
function focusNextBuyLabel(list)
	local c = list:getFocusedChild()
	local cIndex = list:getChildIndex(c)
	local cCount = list:getChildCount()
	local scrollbar = list:getParent():recursiveGetChildById('buyOffersListScroll')

	if cIndex < cCount then
	  list:focusNextChild(KeyboardFocusReason)
	else
	  scrollbar:setValue(scrollbar:getValue() + 1)
	  list:focusChild(c)
	  if cIndex == cCount then
		list:focusNextChild(KeyboardFocusReason)
	  end
	end

	if cache.SCROLL_BUY_OFFERS.lastSelected + 1 < #cache.SCROLL_BUY_OFFERS.listData then
		cache.SCROLL_BUY_OFFERS.lastSelected = cache.SCROLL_BUY_OFFERS.lastSelected + 1
	end
end
