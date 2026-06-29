searchlocker = nil

local titemList = {}
local enableCategories = {17, 18, 19, 20, 21, 32}
local enableClassification = {1, 7, 8, 15, 17, 18, 19, 20, 21, 24, 32}
local marketItems = {}
local categoryList = {}
local depotItemList = {}
local lastSelectedCategory = nil
local showLockerOnly = false

local searchPage = nil
local itemSearchPage = nil

local sortButtons = {
    ["levelButton"] = false,
    ["vocButton"] = false,
    ["oneButton"] = false,
    ["twoButton"] = false,
    ["classFilter"] = -1,
    ["tierFilter"] = 0
}

local listConfig = {
    min = 0,
    max = 0,
    maxFitItems = 0,
    labelSize = 36,
    visibleLabel = 3,
    labels = {}
}

local function setupWindow(window)
    window.bottomResizeBorder:enable()
    window.bottomResizeBorder.onDoubleClick = function()
        window:setHeight(window.bottomResizeBorder:getMinimum())
    end
end

function init()
    searchlocker = g_ui.displayUI("searchlocker")
    hideSearch()

    searchlocker:getChildById('upButton'):setVisible(false)

    setupWindow(searchlocker)

    searchlocker:recursiveGetChildById("lockerOnly").onCheckChange = function(self, checked)
        toggleShowLockerOnly(self, checked)
    end

    searchlocker:setup()

    searchPage = searchlocker:recursiveGetChildById("searchPage")
    itemSearchPage = searchlocker:recursiveGetChildById("itemSearchPage")

    connect(
        g_game,
        {
            onGameStart = online,
            onGameEnd = offline,
            onRecvDepotLockerItems = onRecvDepotLockerItems,
            onCloseSearchLocker = onCloseSearchLocker,
            onRecvSearchItem = onRecvSearchItem,
            onSpecialContainerAvailable = onSpecialContainerAvailable
        }
    )
end

function terminate()
    if searchlocker then
        searchlocker:destroy()
        searchlocker = nil
    end

    disconnect(
        g_game,
        {
            onGameStart = online,
            onGameEnd = offline,
            onRecvDepotLockerItems = onRecvDepotLockerItems,
            onCloseSearchLocker = onCloseSearchLocker,
            onRecvSearchItem = onRecvSearchItem,
            onSpecialContainerAvailable = onSpecialContainerAvailable
        }
    )
end

function online()
    local benchmark = g_clock.millis()
    onCloseSearchLocker()
    consoleln("Search Locker loaded in " .. (g_clock.millis() - benchmark) / 1000 .. " seconds.")
end

function offline()
    onCloseSearchLocker()
end

function toggle()
end

function hideSearch()
    toggleSearchFocus(false)
    searchlocker:hide()
end

function show()
    searchlocker:show()
end

function onCloseSearchLocker()
    depotItemList = {}
    lastSelectedCategory = nil
    titemList = {}
    searchlocker:recursiveGetChildById("headerContentPanel"):destroyChildren()
    searchlocker:recursiveGetChildById("itemListAll"):destroyChildren()
    searchlocker:recursiveGetChildById("selectedItem"):setItemId(0)
    onClearHandFilter()
    hideSearch()
end

function onSpecialContainerAvailable(isInStash, isInMarket)
    if not isInMarket and searchlocker:isVisible() then
        g_game.doThing(false)
        g_game.closeSearchLocker()
        g_game.doThing(true)
    end
end

function configureList()
    marketItems = {}
    for c = MarketCategory.First, MarketCategory.WeaponsAll do
        marketItems[c] = {}
    end

    marketItems[MarketCategory.All] = {}
    local types = g_things.findThingTypeByAttr(ThingAttrMarket, 0)
    for _, itemType in pairs(types) do
        if itemType:getId() == 49870 then
            goto continue
        end

        local item = Item.create(itemType:getId())
        if item then
            local marketData = itemType:getMarketData()
            if not table.empty(marketData) then
                item:setId(marketData.showAs)
                local marketItem = {displayItem = item, thingType = itemType, marketData = marketData}
                if marketItems[marketData.category] ~= nil then
                    table.insert(marketItems[marketData.category], marketItem)

                    -- This might cause high lag
                    table.insert(marketItems[MarketCategory.All], marketItem)
                end
            end
        end

        ::continue::
    end

    -- Weapons all category
    for c = MarketCategory.Ammunition, MarketCategory.WandsRods do
        for _, data in pairs(marketItems[c]) do
            table.insert(marketItems[MarketCategory.WeaponsAll], data)
        end
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

    table.sort(marketItems[MarketCategory.All], compareMarketItemsByNameCaseInsensitive)

    categoryList = {}
    for k, v in pairs(g_things.getMarketCategories()) do
        table.insert(categoryList, {k, v})
    end

    table.insert(categoryList, {MarketCategory.WeaponsAll, "Weapons: All"})
    table.insert(categoryList, {MarketCategory.All, "All"})
    table.sort(
        categoryList,
        function(a, b)
            return a[2] < b[2]
        end
    )
end

function initFields()
    configureList()
    local optionList = searchlocker:recursiveGetChildById("headerContentPanel")
    optionList:destroyChildren()

    local colorCount = 0
    for _, pair in pairs(categoryList) do
        local widget = g_ui.createWidget("CategoryItemListLabel", optionList)
        local color = colorCount % 2 == 0 and "#414141" or "#484848"
        widget:setActionId(pair[1])
        widget.color = color
        widget:setId(pair[2])
        widget:setText(pair[2])
        widget:setBackgroundColor(color)
        colorCount = colorCount + 1
    end

    optionList.onChildFocusChange = function(self, selected)
        onSelectChildCategory(self, selected)
    end
end

function onRequestSearch()
    if not g_game.getLocalPlayer():isInMarket() then
        return true
    end
    g_game.requestSearchLocker()
end

function onRecvDepotLockerItems(itemList)
    if not m_interface.addToPanels(searchlocker) then
        return false
    end

    searchlocker:getChildById('upButton'):setVisible(false)
    searchlocker:getParent():moveChildToIndex(searchlocker, #searchlocker:getParent():getChildren())
    depotItemList = itemList
    searchlocker:recursiveGetChildById("searchItemButton"):setEnabled(false)
    initFields()
    searchlocker:show()
    searchPage:setVisible(true)
    itemSearchPage:setVisible(false)

    toggleSearchFocus(true)
end

function toggleShowLockerOnly(widget, checked)
    showLockerOnly = checked
    onSelectChildCategory(nil, lastSelectedCategory, true)
end

function getLockerItemCount(itemId, tier)
    for _, data in pairs(depotItemList) do
        if data[1] == itemId and data[2] == tier then
            return data[3]
        end
    end
    return 0
end

function onClearHandFilter()
    searchlocker:recursiveGetChildById("oneButton"):setEnabled(false)
    searchlocker:recursiveGetChildById("oneButton"):setChecked(false)
    searchlocker:recursiveGetChildById("twoButton"):setEnabled(false)
    searchlocker:recursiveGetChildById("twoButton"):setChecked(false)
    sortButtons["oneButton"] = false
    sortButtons["twoButton"] = false
end

function onSortLockerFields(widget, checked)
    if table.contains({"oneButton", "twoButton"}, widget:getId()) then
        widget:setChecked(not checked)
        sortButtons[widget:getId()] = not checked
        if widget:getId() == "oneButton" then
            sortButtons["twoButton"] = false
            marketWindow.contentPanel.twoButton:setChecked(false)
        elseif widget:getId() == "twoButton" then
            marketWindow.contentPanel.oneButton:setChecked(false)
            sortButtons["oneButton"] = false
        end
    elseif widget:getId() == "classFilter" then
        sortButtons["classFilter"] = checked > 1 and (checked - 2) or -1
    elseif widget:getId() == "tierFilter" then
        sortButtons["tierFilter"] = checked - 1
    end
    onSelectChildCategory(nil, lastSelectedCategory, true)
end

function onSellerChange(widget, option)
    onSelectChildCategory(nil, lastSelectedCategory, true)
end

local function canShowItem(itemInfo)
    if itemInfo == nil then
        return false
    end

    local tier = sortButtons["tierFilter"]
    local count = getLockerItemCount(itemInfo.thingType:getId(), 0) -- checar tier

    if not checkSortLockerOptions(itemInfo) or (count == 0 and showLockerOnly) then
        return false
    end

    if sortButtons["classFilter"] ~= -1 then
        if itemInfo.thingType:getClassification() ~= sortButtons["classFilter"] then
            return false
        end
    end

    if tier > 0 and itemInfo.thingType:getClassification() == 0 then
        return false
    end

    return true
end

local function countItem(itemInfo, itemList)
    if itemInfo == nil then
        return
    end

    if not canShowItem(itemInfo) then
        return
    end

    listConfig.max = listConfig.max + 1
end

local function insertWidget(itemInfo, itemList)
    if itemInfo == nil then
        return
    end

    local tier = sortButtons["tierFilter"]
    local count = getLockerItemCount(itemInfo.thingType:getId(), 0) -- checar tier

    if not checkSortLockerOptions(itemInfo) or (count == 0 and showLockerOnly) then
        return
    end

    if sortButtons["classFilter"] ~= -1 then
        if itemInfo.thingType:getClassification() ~= sortButtons["classFilter"] then
            return
        end
    end

    if tier > 0 and itemInfo.thingType:getClassification() == 0 then
        return
    end

    local widget = g_ui.createWidget("MarketItemList", itemList)
    widget.item:setItemId(itemInfo.thingType:getId())
    widget.name:setText(itemInfo.marketData.name)
    if widget.name:isOfflimit() then
        widget.name:setText(short_text(itemInfo.marketData.name, 15))
        widget.name:setTooltip(itemInfo.marketData.name)
    end
    widget:setBackgroundColor("#404040")
    widget.item:getItem():setCount(count)
    widget.item:setActionId(i)
    widget.item:setTooltip(
        tr("%s%s%s%s", comma_value(count), "x", (count > 65000 and "+ " or " "), itemInfo.marketData.name)
    )

    if tier ~= 0 then
        widget.item:getItem():setTier(tier)
    end

    if not widget.name:isTextWraped() then
        widget.name:setMarginTop(1)
    end

    if count > 0 then
        widget.grayHover:setOpacity("0.0")
    else
        widget.grayHover:setOpacity("0.5")
    end

    widget.onDoubleClick = function()
        local itemID = widget.item:getItemId()
        if itemID ~= 0 then
            g_game.requestLockerItem(itemID)
        end
    end

    table.insert(listConfig.labels, widget)
end

function onSelectChildCategory(widget, selected, resetFilter)
    if not searchlocker or not selected then
        return true
    end
    local itemList = searchlocker:recursiveGetChildById("itemListAll")
    itemList:destroyChildren()
    searchlocker:recursiveGetChildById("searchItemButton"):setEnabled(false)

    local clearHands =
        not lastSelectedCategory or not table.contains(enableCategories, lastSelectedCategory:getActionId())

    if lastSelectedCategory then
        lastSelectedCategory:setBackgroundColor(lastSelectedCategory.color)
        lastSelectedCategory:setColor("#c0c0c0")
    end

    lastSelectedCategory = selected
    selected:setBackgroundColor("#585858")
    selected:setColor("#f4f4f4")

    if table.contains(enableCategories, selected:getActionId()) then
        searchlocker:recursiveGetChildById("oneButton"):setEnabled(true)
        searchlocker:recursiveGetChildById("twoButton"):setEnabled(true)
    else
        onClearHandFilter()
    end

    if not resetFilter then
        sortButtons["classFilter"] = -1
        sortButtons["tierFilter"] = 0

        local classFilter = searchlocker:recursiveGetChildById("classFilter")
        local tierFilter = searchlocker:recursiveGetChildById("tierFilter")
        if table.contains(enableClassification, selected:getActionId()) then
            classFilter:clearOptions()
            classFilter:addOption("All", nil, true)
            classFilter:addOption("None", nil, true)
            for i = 1, 4 do
                classFilter:addOption("Class " .. i, nil, true)
            end

            tierFilter:clearOptions()
            for i = 0, 10 do
                tierFilter:addOption("Tier " .. i, nil, true)
            end
        else
            classFilter:clearOptions()
            tierFilter:clearOptions()
        end
    end

    searchlocker:recursiveGetChildById("selectedItem"):setItemId(0)
    itemList.onChildFocusChange = function(self, selected)
        onSelectChildItem(self, selected)
    end

    titemList = marketItems[selected:getActionId()]
    listConfig.max = #titemList
    listConfig.maxFitItems = math.floor(itemList:getHeight() / listConfig.labelSize)

    local scrollbar = searchlocker:recursiveGetChildById("itemListScroll")
    scrollbar:setMinimum(0)
    local itemListSorted = {}
    if showLockerOnly then
        listConfig.max = 0
        for k = 1, #titemList do
            local itemInfo = titemList[k]
            local count = getLockerItemCount(itemInfo.thingType:getId(), 0)
            if count > 0 then
                listConfig.max = listConfig.max + 1
                itemListSorted[#itemListSorted + 1] = itemInfo
            end
        end
    end
    scrollbar:setMaximum(listConfig.max)
    scrollbar.onValueChange = function(self, value, delta)
        onItemScrollValueChange(scrollbar, value, delta, titemList, itemListSorted)
    end

    for k = 1, #marketItems[selected:getActionId()] do
        local itemInfo = titemList[k]
        insertWidget(itemInfo, itemList)
        if #listConfig.labels >= listConfig.visibleLabel then
            break
        end
    end

    updateItemWindow(titemList)
end

local function updateWidgets(widget, value, startItem, i, titemList, itemListSorted)
    if not widget then
        return false
    end

    local itemId = value > 0 and (startItem + i - 1) or (startItem + i)
    local itemInfo = showLockerOnly and itemListSorted[itemId] or titemList[itemId]
    if not itemInfo then
        return false
    end

    local tier = sortButtons["tierFilter"]
    local count = getLockerItemCount(itemInfo.thingType:getId(), 0) -- checar tier

    if not checkSortLockerOptions(itemInfo) or (count == 0 and showLockerOnly) then
        return false
    end

    local color = ((itemId % 2 == 0) and "#484848" or "#414141")
    widget:setBackgroundColor(color)
    widget.background = color
    if widget.item then
        widget.item:setActionId(i)
        widget.item:setItemId(itemInfo.thingType:getId())
        widget.item:getItem():setCount(count)
        widget.item:setActionId(i)
        widget.item:setTooltip(
            tr("%s%s%s%s", comma_value(count), "x", (count > 65000 and "+ " or " "), itemInfo.marketData.name)
        )
        if tier ~= 0 then
            widget.item:getItem():setTier(tier)
        end
    end

    if widget.name then
        widget.name:setText(itemInfo.marketData.name)
        if widget.name:isOfflimit() then
            widget.name:setText(short_text(itemInfo.marketData.name, 15))
            widget.name:setTooltip(itemInfo.marketData.name)
        end

        if not widget.name:isTextWraped() then
            widget.name:setMarginTop(1)
        end
    end
    widget:setBackgroundColor("#404040")

    if widget.grayHover then
        if count > 0 then
            widget.grayHover:setOpacity("0.0")
        else
            widget.grayHover:setOpacity("0.5")
        end
    end
end

function onItemScrollValueChange(scrollbar, value, delta, titemList, itemListSorted)
    local startItem = math.max(listConfig.min, value)
    local endItem = startItem + listConfig.maxFitItems - 1

    if endItem > listConfig.max then
        endItem = listConfig.max
        startItem = endItem - listConfig.maxFitItems + 1
    end

    for i, widget in ipairs(listConfig.labels) do
        if not widget then
            return
        end

        updateWidgets(widget, value, startItem, i, titemList, itemListSorted)
    end
end

function updateItemWindow(titemList)
    listConfig.labels = {}
    local itemList = searchlocker:recursiveGetChildById("itemListAll")
    itemList:destroyChildren()

    local displayList = {}
    for k = 1, #titemList do
        local itemInfo = titemList[k]
        if canShowItem(itemInfo) then
            table.insert(displayList, itemInfo)
        end
    end

    local it = 0
    local sec = 0
    for k = 1, #displayList do
        local itemInfo = displayList[k]
        insertWidget(itemInfo, itemList)
        if #listConfig.labels >= listConfig.visibleLabel then
            break
        end
    end

    listConfig.max = #displayList

    local scrollbar = searchlocker:recursiveGetChildById("itemListScroll")
    scrollbar:setValue(0)
    listConfig.maxFitItems = math.floor(itemList:getHeight() / listConfig.labelSize)
    scrollbar:setMinimum(listConfig.min)
    local itemListSorted = {}
    if showLockerOnly then
        listConfig.max = 0
        for k = 1, #displayList do
            local itemInfo = displayList[k]
            local count = getLockerItemCount(itemInfo.thingType:getId(), 0)
            if count > 0 then
                listConfig.max = listConfig.max + 1
                itemListSorted[#itemListSorted + 1] = itemInfo
            end
        end
    end

    scrollbar:setMaximum(listConfig.max)
    scrollbar.onValueChange = function(self, value, delta)
        onItemScrollValueChange(self, value, delta, displayList, itemListSorted)
    end
end

function onSelectChildItem(widget, selected)
    if not selected then
        return
    end

    if lastSelectedItem then
        lastSelectedItem:setBackgroundColor("#404040")
    end

    lastSelectedItem = selected
    selected:setBackgroundColor("#585858")
    local itemID = selected.item:getItemId()
    local itemTier = selected.item:getItem():getTier()
    local selectedItem = searchlocker:recursiveGetChildById("selectedItem")
    selectedItem:setItemId(itemID)
    selectedItem:getItem():setTier(itemTier)

    if itemID == 22118 then
        selectedItem:getItem():setCount(g_game.getTransferableTibiaCoins())
    else
        selectedItem:getItem():setCount(getLockerItemCount(itemID, itemTier))
    end

    searchlocker:recursiveGetChildById("searchItemButton"):setEnabled(true)
    searchlocker:recursiveGetChildById("searchItemButton").onClick = function()
        g_game.requestLockerItem(itemID)
    end
end

-------------------------
function checkSortLockerOptions(itemData)
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

    local text = searchlocker:recursiveGetChildById("searchText"):getText():lower()
    if #text > 2 then
        if not itemData.marketData.name:lower():find(text) then
            return false
        end
    end

    local sellerOptions = searchlocker:recursiveGetChildById("sellerOptions")
    local currentOption = sellerOptions:getCurrentOption()
    if currentOption.text ~= 'All Traders' then
        if itemData.thingType and not itemData.thingType:hasNpcSale(currentOption.text) then
            return false
        end
    end
    return true
end

function onRecvSearchItem(itemId, tier, depotItemCount, depotItems, inboxItemCount, inboxItems, stashItems)
    searchPage:setVisible(false)
    itemSearchPage:setVisible(true)
    searchlocker:getChildById('upButton'):setVisible(true)

    local itemName = itemSearchPage:recursiveGetChildById("itemsNameLabel")
    itemName:setText(getItemServerName(itemId):lower())

    local depotAmount = itemSearchPage:recursiveGetChildById("depotAmount")
    depotAmount:setText(comma_value(depotItemCount))

    local depotButton = itemSearchPage:recursiveGetChildById("depotButton")
    depotButton:setEnabled(depotItemCount > 0)
    depotButton.onClick = function()
        setupSearchItemList(depotButton, depotItems, itemId)
    end

    local stashAmount = itemSearchPage:recursiveGetChildById("stashAmount")
    stashAmount:setText(comma_value(#stashItems))

    local stashButton = itemSearchPage:recursiveGetChildById("stashButton")
    stashButton:setEnabled(#stashItems > 0)
    stashButton.onClick = function()
        setupSearchItemList(stashButton, stashItems, itemId)
    end

    local mailBoxAmount = itemSearchPage:recursiveGetChildById("mailBoxAmount")
    mailBoxAmount:setText(comma_value(inboxItemCount))

    local mailBoxButton = itemSearchPage:recursiveGetChildById("mailBoxButton")
    mailBoxButton:setEnabled(inboxItemCount > 0)
    mailBoxButton.onClick = function()
        setupSearchItemList(mailBoxButton, inboxItems, itemId)
    end

    if depotItemCount > 0 then
        setupSearchItemList(depotButton, depotItems, itemId)
    elseif #stashItems > 0 then
        setupSearchItemList(stashButton, stashItems, itemId)
    elseif inboxItemCount > 0 then
        setupSearchItemList(mailBoxButton, inboxItems, itemId)
    else
        setupSearchItemList(nil, {}, itemId)
    end
end

function setupSearchItemList(button, list, itemId)
    local slotCount = 36

    itemSearchPage:recursiveGetChildById("mailBoxButton"):setOn(false)
    itemSearchPage:recursiveGetChildById("stashButton"):setOn(false)
    itemSearchPage:recursiveGetChildById("depotButton"):setOn(false)
    local posy = 0x20
    if button and (button:getId() == "depotButton" or button:getId() == "mailBoxButton") then
        slotCount = 36
        button:setOn(true)
        if button:getId() == "mailBoxButton" then
            posy = 0x21
        end
    elseif button and button:getId() == "stashButton" then
        slotCount = 1
        button:setOn(true)
    end

    local itemList = itemSearchPage:recursiveGetChildById("itemsList")
    itemList:destroyChildren()

    local itemCount = 1
    for i = 1, slotCount do
        local widget = g_ui.createWidget("Item", itemList)
        local item = list[i]
        widget:setBorderColor("red")
        if button and button:getId() ~= "stashButton" then
            if item then
                widget:setItem(item)
                widget.position = {x = 0xFFFF, y = posy, z = i - 1}
                item:setPosition(widget.position)
            end
        elseif button and button:getId() == "stashButton" then
            widget:setVirtual(true)
            widget:setItemId(item[1])
            widget:setItemCount(item[2])
            itemCount = item[2]
        end
    end

    local buttonRetrieve = itemSearchPage:recursiveGetChildById("retrieveButton")
    if button then
        buttonRetrieve:setEnabled(true)
        buttonRetrieve.onClick = function()
            if button:getId() == "depotButton" or button:getId() == "mailBoxButton" then
                g_game.retrieveDisplayed(itemId, posy == 0x20 and 1 or 2)
            else
                modules.game_stash.withdrawItemID(itemId, itemCount)
            end
        end
    else
        buttonRetrieve:setEnabled(false)
    end
end

function toggleSearchFocus(visible)
    local widget = searchlocker:recursiveGetChildById("clickablePanel")
    if not visible and widget then
        local mousePosition = g_window.getMousePosition()
        if widget:containsPoint(mousePosition) then
            visible = true
        end
    end

    if visible then
        KeyBinds:reset()
    else
        KeyBinds:setupAndReset(Options.currentHotkeySetName, (Options.isChatOnEnabled and "chatOn" or "chatOff"))
    end

    if widget and visible then
        widget:setPhantom(true)
    elseif widget then
        widget:setPhantom(false)
        widget.onClick = function()
            m_interface.toggleInternalFocus()
            toggleSearchFocus(not visible)
        end
    end

    m_interface.toggleFocus(visible, "searchlocker")
    if visible then
        searchlocker:setBorderWidth(2)
        searchlocker:setBorderColor("white")
        local text = searchlocker:recursiveGetChildById("searchText")
        text:recursiveFocus(2)
    else
        searchlocker:setBorderWidth(0)
    end
end

function clearSearch()
    local text = searchlocker:recursiveGetChildById("searchText")
    text:setText("")
end

function onTextChange()
    if not lastSelectedCategory then
        local optionList = searchlocker:recursiveGetChildById("headerContentPanel")
        local childrens = optionList:getChildren()
        if #childrens > 0 then
            onSelectChildCategory(nil, childrens[1], true)
        end
    end

    updateItemWindow(titemList)
end
