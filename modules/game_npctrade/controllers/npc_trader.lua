local function getCurrencyName(currencyName)
    if type(currencyName) == "string" and currencyName ~= "" then
        return currencyName
    end
    return controllerNpcTrader.DEFAULT_CURRENCY_NAME
end

local function getItemSubType(item)
    if item and item.getSubType then
        return item:getSubType()
    end
    if item and item.getCountOrSubType then
        return item:getCountOrSubType()
    end
    return 0
end

local function setScrollRange(scroll, minimum, maximum)
    if not scroll then
        return
    end

    if scroll.setRange then
        scroll:setRange(minimum, maximum)
        return
    end

    if scroll.setMaximum then
        scroll:setMaximum(maximum)
    end
    if scroll.setMinimum then
        scroll:setMinimum(minimum)
    end
end

local function setScrollValue(scroll, value)
    if scroll and scroll.setValue then
        scroll:setValue(value)
    end
end

local function setItemWidget(widget, item)
    if not widget then
        return
    end
    if item and widget.setItem then
        widget:setItem(item)
    elseif item and item.getId and widget.setItemId then
        widget:setItemId(item:getId())
    elseif widget.clearItem then
        widget:clearItem()
    elseif widget.setItemId then
        widget:setItemId(0)
    end
end

local function shortenText(text, maxLength)
    text = tostring(text or "")
    if short_text then
        return short_text(text, maxLength)
    end
    if #text <= maxLength then
        return text
    end
    return text:sub(1, math.max(0, maxLength - 3)) .. "..."
end

function controllerNpcTrader:onOpenNpcTrade(items, currencyId, currencyName)
    local isNewSession = not controllerNpcTrader.isTradeOpen
    if isNewSession then
        controllerNpcTrader.isTradeOpen = true
        controllerNpcTrader.widthConsole = controllerNpcTrader.TRADE_CONSOLE_WIDTH
        controllerNpcTrader.buyItems = {}
        controllerNpcTrader.sellItems = {}
        controllerNpcTrader.currencyId = tonumber(currencyId) or controllerNpcTrader.DEFAULT_CURRENCY_ID
        controllerNpcTrader.currencyName = getCurrencyName(currencyName)
    else
        if currencyId then
            controllerNpcTrader.currencyId = tonumber(currencyId) or controllerNpcTrader.DEFAULT_CURRENCY_ID
        end
        if currencyName then
            controllerNpcTrader.currencyName = getCurrencyName(currencyName)
        end
    end

    local ui = controllerNpcTrader.ui
    if not ui or not ui:isVisible() then
        controllerNpcTrader:initNpcWindow()
    else
        controllerNpcTrader:updateTradeWindowLayout()
    end

    if items and type(items) == "table" then
        controllerNpcTrader.buyItems = {}
        controllerNpcTrader.sellItems = {}
        controllerNpcTrader.selectedItem = nil
        for _, itemData in ipairs(items) do
            local ptr = itemData[1]
            local name = itemData[2]
            local weight = (tonumber(itemData[3]) or 0) / 100
            local buyPrice = tonumber(itemData[4]) or 0
            local sellPrice = tonumber(itemData[5]) or 0
            if buyPrice > 0 then
                table.insert(controllerNpcTrader.buyItems, {
                    ptr = ptr,
                    name = name,
                    weight = weight,
                    price = buyPrice,
                    count = 1
                })
            end
            if sellPrice > 0 then
                table.insert(controllerNpcTrader.sellItems, {
                    ptr = ptr,
                    name = name,
                    weight = weight,
                    price = sellPrice,
                    count = 1
                })
            end
        end
    end

    local currencyLabel = controllerNpcTrader:findWidget(".tradeCurrencyName")
    if currencyLabel then
        currencyLabel:setText(controllerNpcTrader.currencyName)
    end
    local currencyIcon = controllerNpcTrader:findWidget(".tradeCurrencyIcon")
    if currencyIcon then
        if currencyIcon.setItemId then
            currencyIcon:setItemId(controllerNpcTrader.currencyId)
        elseif currencyIcon.setItem then
            currencyIcon:setItem(Item.create(controllerNpcTrader.currencyId))
        end
    end

    if isNewSession then
        -- Initial State
        local initialMode = controllerNpcTrader.BUY
        if #controllerNpcTrader.buyItems > 0 then
            initialMode = controllerNpcTrader.BUY
        elseif #controllerNpcTrader.sellItems > 0 then
            initialMode = controllerNpcTrader.SELL
        end

        controllerNpcTrader.tradeMode = initialMode
        controllerNpcTrader.searchText = ""
        controllerNpcTrader.itemBatchSize = controllerNpcTrader.ITEM_BATCH_SIZE
        controllerNpcTrader.loadedItems = 0
        controllerNpcTrader.currentList = {}

        -- Settings & Sorting
        controllerNpcTrader.sortBy = controllerNpcTrader.DEFAULT_SORT_BY
        controllerNpcTrader.ignoreCapacity = controllerNpcTrader.DEFAULT_IGNORE_CAPACITY
        controllerNpcTrader.buyWithBackpack = controllerNpcTrader.DEFAULT_BUY_WITH_BACKPACK
        controllerNpcTrader.ignoreEquipped = controllerNpcTrader.DEFAULT_IGNORE_EQUIPPED

        controllerNpcTrader:setTradeMode(initialMode)
    else
        controllerNpcTrader.allTradeItems = (controllerNpcTrader.tradeMode == controllerNpcTrader.BUY) and
                                                controllerNpcTrader.buyItems or controllerNpcTrader.sellItems
        controllerNpcTrader:filterTradeList(controllerNpcTrader.searchText or "")
        controllerNpcTrader:refreshPlayerGoods(true)
    end
end

function controllerNpcTrader:setTradeMode(mode)
    self.tradeMode = mode
    self.selectedItem = nil

    local buyTab = self:findWidget("#tabBuy")
    local sellTab = self:findWidget("#tabSell")

    if buyTab then
        buyTab:setEnabled(mode ~= controllerNpcTrader.BUY)
    end
    if sellTab then
        sellTab:setEnabled(mode ~= controllerNpcTrader.SELL)
    end
    local toggleButton = self:findWidget("#toggleButton")
    if toggleButton then
        toggleButton:setText(mode == controllerNpcTrader.BUY and "Buy" or "Sell")
    end

    self.shouldFocusFirst = true
    self:updateListSource()
    self:refreshPlayerGoods(true)
end

function controllerNpcTrader:updateListSource()
    if self.tradeMode == controllerNpcTrader.BUY then
        self.allTradeItems = self.buyItems
    else
        self.allTradeItems = self.sellItems
    end
    self:filterTradeList(self.searchText or "")
end

function controllerNpcTrader:refreshTradeListWidgets()
    self:renderTradeList()
    self:onTradeListRendered()
    self:updateAmountWidgets()
end

function controllerNpcTrader:renderTradeList()
    local list = self:findWidget("#tradeListScroll")
    if not list then
        return
    end

    list:destroyChildren()
    for _, item in ipairs(self.tradeItems or {}) do
        self.__renderTradeItem = item
        local row = self:createWidgetFromHTML([[
            <div class="tradeListItem flex fullWidth">
                <UIItem class="iconBox item" *item="self.__renderTradeItem.ptr" />
                <div class="itemInfoBlock">
                    <label id="nameLabel" class="tradeItemName fontText"></label>
                    <label id="infoLabel" class="tradeItemInfo fontText"></label>
                </div>
            </div>
        ]], list)

        if row then
            row.tradeItem = item
            local nameLabel = row:recursiveGetChildById("nameLabel")
            if nameLabel then
                nameLabel:setText(shortenText(item.name, controllerNpcTrader.MAX_ITEM_NAME_LENGTH))
            end
            local infoLabel = row:recursiveGetChildById("infoLabel")
            if infoLabel then
                local info = "Price " .. item.price .. ", " .. item.weight .. " oz"
                infoLabel:setText(shortenText(info, controllerNpcTrader.MAX_ITEM_INFO_LENGTH))
            end
        end
    end
    self.__renderTradeItem = nil
end

function controllerNpcTrader:loadNextBatch(refresh)
    if not self.currentList then
        return
    end

    local total = #self.currentList
    local current = self.loadedItems
    if current >= total then
        return
    end

    local limit = math.min(total, current + self.itemBatchSize)
    for i = current + 1, limit do
        table.insert(self.tradeItems, self.currentList[i])
    end
    self.loadedItems = limit
    if refresh ~= false then
        self:refreshTradeListWidgets()
    end
end

function controllerNpcTrader:onTradeScroll(widget, offset)
    if self.loadedItems >= #self.currentList then
        return
    end
    local rowHeight = controllerNpcTrader.ITEM_ROW_HEIGHT
    local contentHeight = self.loadedItems * rowHeight
    local viewportHeight = widget:getHeight()
    local maxScroll = math.max(0, contentHeight - viewportHeight)
    local value = offset.y
    if value >= maxScroll - controllerNpcTrader.SCROLL_THRESHOLD then
        self:loadNextBatch()
    end
end

function controllerNpcTrader:onTradeListRendered()
    local list = self:findWidget("#tradeListScroll")
    if list then
        if not list.onScrollEventConnected then
            list.onScrollChange = function(widget, offset)
                self:onTradeScroll(widget, offset)
            end
            list.onScrollEventConnected = true
        end
        for i = 1, list:getChildCount() do
            local child = list:getChildByIndex(i)
            local item = child.tradeItem
            if item then
                local canTrade = self:canTradeItem(item)
                local color = canTrade and '#c0c0c0' or '#707070'
                local nameLabel = child:recursiveGetChildById("nameLabel")
                local infoLabel = child:recursiveGetChildById("infoLabel")
                if nameLabel then
                    nameLabel:setColor(color)
                end
                if infoLabel then
                    infoLabel:setColor(color)
                end

                child.onMouseRelease = function(widget, mousePos, mouseButton)
                    self:onTradeItemMouseRelease(item, widget, mousePos, mouseButton)
                end
            end
        end
        if self.shouldFocusFirst then
            local firstChild = list:getChildByIndex(1)
            if firstChild then
                self:selectTradeItem(self.tradeItems[1], firstChild)
            end
            self.shouldFocusFirst = false
        elseif self.selectedItem then
            for i = 1, list:getChildCount() do
                local child = list:getChildByIndex(i)
                if child.tradeItem == self.selectedItem then
                    child:focus()
                    break
                end
            end
        end
    end
end

function controllerNpcTrader:onTradeItemMouseRelease(item, widget, mousePos, mouseButton)
    if mouseButton == MouseRightButton then
        local menu = g_ui.createWidget('PopupMenu')
        menu:setGameMenu(true)
        menu:addOption("Look", function()
            g_game.inspectNpcTrade(item.ptr)
        end)
        menu:addOption("Inspect", function()
            if g_game.sendInspectionObject then
                g_game.sendInspectionObject(3, item.ptr:getId(), 1)
            end
        end)
        menu:display(mousePos)
        return true
    elseif mouseButton == MouseLeftButton then
        self:selectTradeItem(item, widget)
        return true
    end
    return false
end

function controllerNpcTrader:selectTradeItem(item, widget)
    self.selectedItem = item
    if widget then
        widget:focus()
    end
    self:updateAmount(1)

    local scroll = self:findWidget("#amountScrollBar")
    if scroll then
        scroll:enable()
        setScrollValue(scroll, 1)
    end
end

function controllerNpcTrader:updateAmount(amount)
    amount = tonumber(amount) or 1
    if self.selectedItem then
        local maxAmount = controllerNpcTrader.MAX_AMOUNT_NORMAL
        local minAmount = controllerNpcTrader.MIN_AMOUNT
        if self.tradeMode == controllerNpcTrader.BUY then
            local playerMoney = self:getPlayerMoney()
            local maxByMoney = math.floor(playerMoney / self.selectedItem.price)
            local maxByCapacity = controllerNpcTrader.MAX_AMOUNT_NORMAL
            if not self.ignoreCapacity then
                local player = g_game.getLocalPlayer()
                local freeCapacity = player and player:getFreeCapacity() or 0
                local itemWeight = tonumber(self.selectedItem.weight) or 0
                maxByCapacity = itemWeight > 0 and math.floor(freeCapacity / itemWeight) or maxByCapacity
            end
            maxAmount = math.max(minAmount, math.min(controllerNpcTrader.MAX_AMOUNT_NORMAL, maxByMoney, maxByCapacity))
            if self.selectedItem.ptr and self.selectedItem.ptr:isStackable() then
                maxAmount = math.max(minAmount,
                    math.min(controllerNpcTrader.MAX_AMOUNT_STACKABLE, maxByMoney, maxByCapacity))
            end
        else
            local sellable = self:getSellQuantity(self.selectedItem.ptr)
            minAmount = sellable > 0 and controllerNpcTrader.MIN_AMOUNT or 0
            maxAmount = math.max(minAmount, sellable)
        end
        if amount > maxAmount then
            amount = maxAmount
        end
        if amount < minAmount then
            amount = minAmount
        end
        local scroll = self:findWidget("#amountScrollBar")
        if scroll then
            setScrollRange(scroll, minAmount, maxAmount)
            if not scroll.getValue or scroll:getValue() ~= amount then
                setScrollValue(scroll, amount)
            end
        end
    end
    self.amount = amount
    if self.selectedItem then
        self.totalPrice = self.selectedItem.price * amount
        self.totalWeight = string.format("%.2f", self.selectedItem.weight * amount)
    else
        self.totalPrice = 0
        self.totalWeight = "0.00"
    end
    self:updateAmountWidgets()
end

function controllerNpcTrader:updateAmountWidgets()
    local amountText = tostring(self.amount or 0)
    local amountInput = self:findWidget("#amountInput")
    if amountInput and amountInput.setText then
        if not amountInput.getText or amountInput:getText() ~= amountText then
            amountInput:setText(amountText)
        end
    end

    local priceDisplay = self:findWidget("#totalPriceDisplay")
    if priceDisplay and priceDisplay.setText then
        priceDisplay:setText(tostring(self.totalPrice or 0))
    end

    local preview = self:findWidget("#tradePreviewItem")
    local item = self.selectedItem and self.selectedItem.ptr or nil
    setItemWidget(preview, item)
end

function controllerNpcTrader:onAmountScrollBarChange(value)
    self:updateAmount(value)
end

function controllerNpcTrader:onAmountInputChange(event)
    local input = event.target
    local text = input:getText()
    local cleanText = text:gsub("[^%d]", "")
    if cleanText ~= text then
        input:setText(cleanText)
        text = cleanText
    end
    if text == "" then
        text = "1"
    end
    local amount = tonumber(text) or 1
    self:updateAmount(amount)
    local scroll = self:findWidget("#amountScrollBar")
    if scroll then
        if amount ~= self.amount then
            input:setText(tostring(self.amount))
        end
        setScrollValue(scroll, self.amount)
    end
end

function controllerNpcTrader:getPlayerMoney()
    if self.playerMoney ~= nil then
        return self.playerMoney
    end
    if getTotalMoney then
        return getTotalMoney()
    end

    local player = g_game.getLocalPlayer()
    if not player or not player.getResourceValue then
        return 0
    end
    return (player:getResourceValue(ResourceBank) or 0) + (player:getResourceValue(ResourceInventary) or 0)
end

function controllerNpcTrader:getSellQuantity(itemPtr)
    if not itemPtr then
        return 0
    end
    local id = itemPtr:getId()
    local subType = getItemSubType(itemPtr)
    local key = id .. "_" .. subType
    local inventoryTotal = self.playerItems and (self.playerItems[key] or self.playerItems[id] or 0) or 0

    if self.ignoreEquipped then
        local player = g_game.getLocalPlayer()
        local equippedCount = 0
        if player then
            for i = 1, 10 do
                local item = player:getInventoryItem(i)
                if item and item:getId() == id and getItemSubType(item) == subType then
                    equippedCount = equippedCount + item:getCount()
                end
            end
        end
        return math.max(0, inventoryTotal - equippedCount)
    end

    return inventoryTotal
end

function controllerNpcTrader:canTradeItem(item)
    if self.tradeMode == controllerNpcTrader.BUY then
        local playerMoney = self:getPlayerMoney()
        -- Add capacity check if needed, but for now we'll just check price
        return playerMoney >= item.price
    else
        return self:getSellQuantity(item.ptr) > 0
    end
end

function controllerNpcTrader:onPlayerGoods(money, items)
    if type(money) == "table" and items == nil then
        items = money
        money = nil
    end

    if not items or type(items) ~= "table" then
        return
    end
    self.playerMoney = tonumber(money) or self.playerMoney or 0
    local newPlayerItems = {}
    for id, itemData in pairs(items) do
        local itemId
        local subType = 0
        local count

        if type(itemData) == "table" then
            local ptr = itemData[1]
            if ptr and ptr.getId then
                itemId = ptr:getId()
                subType = getItemSubType(ptr)
            else
                itemId = itemData.id or itemData[1]
            end
            count = itemData[2] or itemData.amount or itemData.count
        elseif type(id) == "number" and type(itemData) == "number" then
            itemId = id
            count = itemData
        end

        itemId = tonumber(itemId)
        count = tonumber(count)
        if itemId and count then
            local key = itemId .. "_" .. subType
            newPlayerItems[key] = (newPlayerItems[key] or 0) + count
            newPlayerItems[itemId] = (newPlayerItems[itemId] or 0) + count
        end
    end
    self.playerItems = newPlayerItems
    self:refreshPlayerGoods()
end

function controllerNpcTrader:refreshPlayerGoods(skipFilter)
    local money = self:getPlayerMoney()
    local display = self:findWidget("#playerMoneyDisplay")
    if display then
        display:setText(tostring(money))
    end
    if not skipFilter and self.tradeMode == controllerNpcTrader.SELL then
        self:filterTradeList(self.searchText or "")
    end
    if self.selectedItem then
        self:updateAmount(self.amount)
    end
end

function controllerNpcTrader:executeTrade()
    if not self.selectedItem then
        return
    end
    if self.tradeMode == controllerNpcTrader.BUY then
        g_game.buyItem(self.selectedItem.ptr, self.amount, self.ignoreCapacity, self.buyWithBackpack)
    else
        g_game.sellItem(self.selectedItem.ptr, self.amount, self.ignoreEquipped)
    end
end

function controllerNpcTrader:clearSearch()
    local input = self:findWidget(".tradeSearchInput")
    if input then
        input:setText("")
        self:filterTradeList("")
    end
end

function controllerNpcTrader:filterTradeList(searchText)
    if not self.allTradeItems then
        return
    end

    self.searchText = searchText
    local lowerSearch = searchText:lower()
    local filteredItems = {}

    for _, item in ipairs(self.allTradeItems) do
        local includeItem = true
        if searchText ~= "" and not item.name:lower():find(lowerSearch, 1, true) then
            includeItem = false
        end

        if includeItem then
            table.insert(filteredItems, item)
        end
    end

    if self.tradeMode == controllerNpcTrader.SELL then
        table.sort(filteredItems, function(a, b)
            local qtyA = self:getSellQuantity(a.ptr)
            local qtyB = self:getSellQuantity(b.ptr)
            if qtyA ~= qtyB then
                return qtyA > qtyB
            end
            if self.sortBy == 'price' then
                return a.price > b.price
            elseif self.sortBy == 'weight' then
                return a.weight > b.weight
            else
                return a.name:lower() < b.name:lower()
            end
        end)
    else
        self:sortTradeItems(filteredItems)
    end

    self.currentList = filteredItems
    self.tradeItems = {}
    self.loadedItems = 0
    self:loadNextBatch(false)

    if #self.currentList > 0 then
        local found = false
        if self.selectedItem then
            for _, item in ipairs(self.currentList) do
                if item == self.selectedItem then
                    found = true;
                    break
                end
            end
        end
        if not found then
            self:selectTradeItem(self.tradeItems[1])
        end
    else
        self.selectedItem = nil
        self:updateAmount(0)
    end
    self:refreshTradeListWidgets()
end

function controllerNpcTrader:sellAll(delayed, exceptions)
    if type(delayed) == "table" then
        exceptions = delayed
        delayed = false
    end
    exceptions = exceptions or {}

    if self.sellAllWithDelayEvent then
        removeEvent(self.sellAllWithDelayEvent)
        self.sellAllWithDelayEvent = nil
    end

    local queue = {}
    if not self.sellItems or #self.sellItems == 0 then
        return
    end

    for _, entry in ipairs(self.sellItems or {}) do
        local id = entry.ptr:getId()
        if not table.find(exceptions, id) then
            local sellQuantity = self:getSellQuantity(entry.ptr)
            while sellQuantity > 0 do
                local maxPossible = g_game.getFeature(GameDoubleShopSellAmount) and 10000 or 100
                local maxAmount = math.min(sellQuantity, maxPossible)

                if delayed then
                    g_game.sellItem(entry.ptr, maxAmount, self.ignoreEquipped)
                    self.sellAllWithDelayEvent = scheduleEvent(function()
                        self:sellAll(true, exceptions)
                    end, 1100)
                    return
                end

                table.insert(queue, {entry.ptr, maxAmount, self.ignoreEquipped})
                sellQuantity = sellQuantity - maxAmount
            end
        end
    end

    for _, entry in ipairs(queue) do
        g_game.sellItem(entry[1], entry[2], entry[3])
    end
end
