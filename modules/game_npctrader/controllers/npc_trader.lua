-- Logs desabilitados em produção (habilite manualmente para debugar: controllerNpcTrader.DEBUG_LOG = true)
controllerNpcTrader.DEBUG_LOG = false
local function logDebug(...)
    if not controllerNpcTrader or not controllerNpcTrader.DEBUG_LOG then
        return
    end
    local args = { ... }
    local ok, msg = pcall(function()
        local parts = { "[npc_trader][amount]" }
        for i = 1, #args do
            parts[#parts + 1] = tostring(args[i])
        end
        return table.concat(parts, " ")
    end)
    if not ok then
        return
    end
    if g_logger and g_logger.info then
        g_logger.info(msg)
    else
        print(msg)
    end
end

--- Legado: preview por item id fictício (montaria nativa usa mountClientId vindo do servidor).
local TRADE_MOUNT_PREVIEW_BY_ITEM_ID = {}

function controllerNpcTrader:ensureTradePreviewMountWidget(footer, itemPreview)
    if not footer or not itemPreview or itemPreview:isDestroyed() then
        return nil
    end
    local w = footer:getChildById("tradePreviewMount")
    if w and w:isDestroyed() then
        w = nil
    end
    if not w then
        w = g_ui.createWidget("UICreature", footer)
        w:setId("tradePreviewMount")
        if w.setCreatureSize then
            w:setCreatureSize(36)
        end
        if w.setCenter then
            w:setCenter(true)
        end
    end
    return w
end

function controllerNpcTrader:syncTradeMountPreviewLayout(itemPreview, mountWidget)
    if not itemPreview or itemPreview:isDestroyed() or not mountWidget or mountWidget:isDestroyed() then
        return
    end
    mountWidget:setPosition(itemPreview:getPosition())
    mountWidget:setSize(itemPreview:getSize())
end

--- Preview só da montaria: mesmo truque da lista de mounts em outfit.lua (type = id da montaria, mount = 0).
function controllerNpcTrader:applyTradeMountPreview(mountWidget, mountClientId)
    if not mountWidget or mountWidget:isDestroyed() or not g_game.getFeature(GamePlayerMounts) then
        return
    end
    mountWidget:setDirection(2)
    mountWidget:setOutfit({
        type = mountClientId,
        mount = 0,
        head = 0,
        body = 0,
        legs = 0,
        feet = 0,
        addons = 0,
    })
end

--- Lista do trade: linhas de montaria não têm sprite de item — sobrepõe UICreature no slot do ícone.
function controllerNpcTrader:syncTradeListRowMountIcon(rowWidget, tradeItem)
    if not rowWidget or rowWidget:isDestroyed() or not tradeItem then
        return
    end
    local iconItem = rowWidget:getChildByIndex(1)
    if not iconItem or iconItem:isDestroyed() then
        return
    end

    local prev = rowWidget._tradeListMountCreature
    if prev and not prev:isDestroyed() then
        prev:destroy()
        rowWidget._tradeListMountCreature = nil
    end

    local mountClientId = tonumber(tradeItem.mountClientId) or 0
    if mountClientId > 0 and g_game.getFeature(GamePlayerMounts) then
        iconItem:setVisible(false)
        local mw = g_ui.createWidget("UICreature", rowWidget)
        rowWidget._tradeListMountCreature = mw
        mw:setPhantom(true)
        local sz = math.max(10, math.min(iconItem:getWidth(), iconItem:getHeight()) - 4)
        if mw.setCreatureSize then
            mw:setCreatureSize(sz)
        end
        if mw.setCenter then
            mw:setCenter(true)
        end
        mw:setPosition(iconItem:getPosition())
        mw:setSize(iconItem:getSize())
        self:applyTradeMountPreview(mw, mountClientId)
        mw:setVisible(true)
        if mw.raise then
            mw:raise()
        end
        addEvent(function()
            if rowWidget:isDestroyed() or not mw or mw:isDestroyed() or not iconItem or iconItem:isDestroyed() then
                return
            end
            mw:setPosition(iconItem:getPosition())
            mw:setSize(iconItem:getSize())
        end)
    else
        iconItem:setVisible(true)
    end
end

local function ensureSellQty(item)
    if controllerNpcTrader.tradeMode == controllerNpcTrader.SELL and item and item.sellQty == nil then
        item.sellQty = controllerNpcTrader:getSellQuantity(item.ptr)
    end
end

function onOpenNpcTrade(items, currencyId, currencyName)
    if not controllerNpcTrader:useNewNpcDialog() then
        local isNewSession = not controllerNpcTrader.isTradeOpen
        controllerNpcTrader:initNpcWindow(nil, nil)
        controllerNpcTrader:ensureLegacyInit()
        controllerNpcTrader._legacyCurrencyItemId = currencyId
        setCurrency((currencyName and currencyName ~= '') and currencyName or controllerNpcTrader.DEFAULT_CURRENCY_NAME, false)
        controllerNpcTrader.isTradeOpen = true
        controllerNpcTrader:onOpenNpcTradeLegacy(items or {}, isNewSession)
        return
    end

    local ui = controllerNpcTrader.ui
    if not ui or not ui:isVisible() then
        controllerNpcTrader:initNpcWindow()
    end
    logDebug("onOpenNpcTrade start items", items and #items or 0)
    controllerNpcTrader:addTradeButton()
    local isNewSession = not controllerNpcTrader.isTradeOpen
    if isNewSession then
        controllerNpcTrader.isTradeOpen = true
        controllerNpcTrader.widthConsole = controllerNpcTrader.TRADE_CONSOLE_WIDTH
        controllerNpcTrader.buyItems = {}
        controllerNpcTrader.sellItems = {}
        controllerNpcTrader.currencyId = currencyId or controllerNpcTrader.DEFAULT_CURRENCY_ID
        controllerNpcTrader.currencyName = (currencyName and currencyName ~= "") and currencyName or controllerNpcTrader.DEFAULT_CURRENCY_NAME
    else
        if currencyId then
            controllerNpcTrader.currencyId = currencyId
        end
        if currencyName and currencyName ~= "" then
            controllerNpcTrader.currencyName = currencyName
        end
    end

    if items and type(items) == "table" then
        if isNewSession then
            controllerNpcTrader.buyItems = {}
            controllerNpcTrader.sellItems = {}
            controllerNpcTrader.selectedItem = nil
        end
        for _, itemData in ipairs(items) do
            local ptr = itemData[1]
            local name = itemData[2]
            local weight = itemData[3] / 100
            local buyPrice = itemData[4]
            local sellPrice = itemData[5]
            local buyPriceStr = itemData.buyPriceStr
            local sellPriceStr = itemData.sellPriceStr
            local mountServerId = itemData.mountServerId or itemData[6] or 0
            local mountClientId = itemData.mountClientId or itemData[7] or 0
            if buyPrice > 0 then
                table.insert(controllerNpcTrader.buyItems, {
                    ptr = ptr,
                    name = name,
                    weight = weight,
                    price = buyPrice,
                    priceText = buyPriceStr,
                    count = 1,
                    mountServerId = mountServerId,
                    mountClientId = mountClientId
                })
            end
            if sellPrice > 0 then
                table.insert(controllerNpcTrader.sellItems, {
                    ptr = ptr,
                    name = name,
                    weight = weight,
                    price = sellPrice,
                    priceText = sellPriceStr,
                    count = 1,
                    mountServerId = mountServerId,
                    mountClientId = mountClientId
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
        if currencyIcon.setShowCount then
            currencyIcon:setShowCount(false)
        end
        local item = Item.create(controllerNpcTrader.currencyId)
        if item then
            item:setCount(1)
            currencyIcon:setItem(item)
        else
            currencyIcon:setItemId(controllerNpcTrader.currencyId)
        end
    end

    if isNewSession then
        local initialMode = controllerNpcTrader.BUY
        if #controllerNpcTrader.buyItems > 0 then
            initialMode = controllerNpcTrader.BUY
        elseif #controllerNpcTrader.sellItems > 0 then
            initialMode = controllerNpcTrader.SELL
        end
        logDebug("onOpenNpcTrade isNewSession mode", initialMode == controllerNpcTrader.BUY and "BUY" or "SELL", "buyItems", #controllerNpcTrader.buyItems, "sellItems", #controllerNpcTrader.sellItems)

        controllerNpcTrader.tradeMode = initialMode
        controllerNpcTrader.searchText = ""
        controllerNpcTrader.itemBatchSize = controllerNpcTrader.ITEM_BATCH_SIZE
        controllerNpcTrader.loadedItems = 0
        controllerNpcTrader.currentList = {}
        controllerNpcTrader.totalPrice = 0
        controllerNpcTrader.playerMoney = controllerNpcTrader:getPlayerMoney()

        controllerNpcTrader.sortBy = controllerNpcTrader.DEFAULT_SORT_BY
        controllerNpcTrader.ignoreCapacity = controllerNpcTrader.DEFAULT_IGNORE_CAPACITY
        controllerNpcTrader.buyWithBackpack = controllerNpcTrader.DEFAULT_BUY_WITH_BACKPACK
        controllerNpcTrader.ignoreEquipped = controllerNpcTrader.DEFAULT_IGNORE_EQUIPPED
        controllerNpcTrader.showSearchField = controllerNpcTrader.DEFAULT_SHOW_SEARCH_FIELD
        controllerNpcTrader.noLargeAmountWarning = controllerNpcTrader.DEFAULT_NO_LARGE_AMOUNT_WARNING

        controllerNpcTrader:setTradeMode(initialMode)
        -- Garantir que a lista fique selecionável mesmo se *for-finished disparar antes da UI estar pronta
        for _, delayMs in ipairs({ 80, 150, 250 }) do
            scheduleEvent(function()
                if not controllerNpcTrader.isTradeOpen or not controllerNpcTrader.ui or controllerNpcTrader.ui:isDestroyed() then return end
                controllerNpcTrader:onTradeListRendered()
            end, delayMs)
        end
    else
        controllerNpcTrader.allTradeItems = (controllerNpcTrader.tradeMode == controllerNpcTrader.BUY) and
            controllerNpcTrader.buyItems or controllerNpcTrader.sellItems
        controllerNpcTrader:filterTradeList(controllerNpcTrader.searchText or "")
        controllerNpcTrader:refreshPlayerGoods()
    end
end

function controllerNpcTrader:setTradeMode(mode)
    local sameMode = (self.tradeMode == mode)
    self.tradeMode = mode

    local buyTab = self:findWidget("#tabBuy")
    local sellTab = self:findWidget("#tabSell")
    if buyTab then
        buyTab:setEnabled(mode ~= controllerNpcTrader.BUY)
    end
    if sellTab then
        sellTab:setEnabled(mode ~= controllerNpcTrader.SELL)
    end

    if sameMode then
        self.shouldFocusFirst = true
        self:updateListSource()
        self:refreshPlayerGoods()
        return
    end
    self.selectedItem = nil
    self.amount = 0
    self._forceAmountInputRefresh = true
    self:refreshFooter()

    local toggleButton = self:findWidget("#toggleButton")
    if toggleButton then
        toggleButton:setText(mode == controllerNpcTrader.BUY and "Buy" or "Sell")
    end

    self.shouldFocusFirst = true
    self:updateListSource()
    self:refreshPlayerGoods()
end

function controllerNpcTrader:updateSellQuantities()
    if self.tradeMode ~= controllerNpcTrader.SELL then return end
    for _, item in ipairs(self.sellItems) do
        item.sellQty = self:getSellQuantity(item.ptr)
    end
    if self.currentList then
        for _, item in ipairs(self.currentList) do
            ensureSellQty(item)
        end
    end
    if self.tradeItems then
        for _, item in ipairs(self.tradeItems) do
            ensureSellQty(item)
        end
    end
end

function controllerNpcTrader:updateListSource()
    if self.tradeMode == controllerNpcTrader.BUY then
        self.allTradeItems = self.buyItems
    else
        self:updateSellQuantities()
        self.allTradeItems = self.sellItems
    end
    self:filterTradeList(self.searchText or "")
end

function controllerNpcTrader:loadNextBatch()
    if not self.currentList then
        return
    end

    local total = #self.currentList
    local current = self.loadedItems
    if current >= total then
        return
    end

    local newItems = {unpack(self.tradeItems)}
    local limit = math.min(total, current + self.itemBatchSize)

    for i = current + 1, limit do
        local item = self.currentList[i]
        ensureSellQty(item)
        table.insert(newItems, item)
    end

    self.tradeItems = newItems
    self.loadedItems = limit
    logDebug("loadNextBatch loaded", self.loadedItems, "of", total)

    -- Garante binding de eventos mesmo se *for-finished não disparar, com guardas para evitar callbacks expirados
    local function safeRender()
        if not controllerNpcTrader or controllerNpcTrader.isTradeOpen ~= true then return end
        if not controllerNpcTrader.ui or controllerNpcTrader.ui:isDestroyed() then return end
        if controllerNpcTrader.onTradeListRendered then
            controllerNpcTrader:onTradeListRendered()
        end
    end
    scheduleEvent(safeRender, 0)
    scheduleEvent(safeRender, 50)
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
        logDebug("onTradeListRendered childCount", list:getChildCount())
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
                logDebug("bind onMouseRelease item", item.name or "nil", item.ptr and item.ptr:getId() or "nil")
                child.onMouseRelease = function(widget, mousePos, mouseButton)
                    self:onTradeItemMouseRelease(item, widget, mousePos, mouseButton)
                end
                if not child._npcTradeTooltipHoverBound then
                    child._npcTradeTooltipHoverBound = true
                    child.onHoverChange = function(_, hovered)
                        self:onNpcTradeRowHover(item, hovered)
                    end
                end
                self:syncTradeListRowMountIcon(child, item)
            else
                logDebug("bind onMouseRelease child without tradeItem", i)
            end
        end
        if self.shouldFocusFirst then
            self.shouldFocusFirst = false
            if self.tradeItems[1] then
                local firstChild = list:getChildByIndex(1)
                if firstChild then
                    self:selectTradeItem(self.tradeItems[1], firstChild)
                end
            end
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

        menu:addOption(tr("Look"), function()
            g_game.inspectNpcTrade(item.ptr)
        end)
        menu:addOption(tr("Inspect"), function()
            g_game.inspectNpcTrade(item.ptr)
        end)

        menu:addSeparator()

        local sortOptions = {
            { label = "Sort by name",   key = 'name' },
            { label = "Sort by price",  key = 'price' },
            { label = "Sort by weight", key = 'weight' },
        }
        for _, opt in ipairs(sortOptions) do
            menu:addCheckBox(tr(opt.label), self.sortBy == opt.key, function()
                self:setSortBy(opt.key)
            end)
        end

        menu:addSeparator()

        if self.tradeMode == controllerNpcTrader.BUY then
            if self.currencyId == controllerNpcTrader.DEFAULT_CURRENCY_ID then
                menu:addCheckBox(tr("Buy in shopping bags"), self.buyWithBackpack, function()
                    self:toggleBuyWithBackpack()
                end)
            end
            menu:addCheckBox(tr("Ignore capacity"), self.ignoreCapacity, function()
                self:toggleIgnoreCapacity()
            end)
        else
            menu:addCheckBox(tr("Sell equipped"), not self.ignoreEquipped, function()
                self:toggleIgnoreEquipped()
            end)
        end

        menu:addSeparator()

        menu:addCheckBox(tr("Show search field"), self.showSearchField, function()
            self:toggleSearchField()
        end)
        menu:addCheckBox(tr("Do not show a warning when trading large amounts"), self.noLargeAmountWarning, function()
            self.noLargeAmountWarning = not self.noLargeAmountWarning
        end)

        menu:display(mousePos)
        return true
    elseif mouseButton == MouseLeftButton then
        logDebug("onTradeItemMouseRelease left", item.name or "nil", "id", item.ptr and item.ptr:getId() or "nil")
        self:selectTradeItem(item, widget)
        return true
    end
    return false
end

function controllerNpcTrader:findTradeWidget(selector)
    if not self.ui then return nil end

    -- Primeiro tenta por id via árvore completa (mais robusto que querySelector em HTML dinâmico)
    local id = selector:match("^#(.+)$")
    if id and self.ui.recursiveGetChildById then
        local byId = self.ui:recursiveGetChildById(id)
        if byId then
            logDebug("findTradeWidget hit recursive id:", id)
            return byId
        end
    end

    -- Fallback para seletor CSS
    local w = self.ui:querySelector(selector)
    if not w then
        local rightPanel = self.ui:querySelector(".rightPanel")
        if rightPanel and rightPanel.querySelector then
            w = rightPanel:querySelector(selector)
        end
    end
    if not w then
        logDebug("findTradeWidget missing:", selector)
    end
    return w
end

function controllerNpcTrader:refreshFooter()
    if not self.ui or not self.ui:isVisible() then
        return
    end

    local footer = self.ui:recursiveGetChildById("tradeFooter")
    if not footer then return end

    local hasItem = self.selectedItem ~= nil

    if not hasItem then
        local scrollEmpty = self:findTradeWidget('#amountScrollBar')
        if scrollEmpty then
            scrollEmpty:setEnabled(false)
            scrollEmpty:setMinimum(0)
            scrollEmpty:setMaximum(1)
            scrollEmpty:setValue(0)
        end
    end

    local preview = footer:getChildById("tradePreview")
    if preview then
        local itemId = (hasItem and self.selectedItem.ptr) and self.selectedItem.ptr:getId() or 0
        local mountClientId = nil
        if self.tradeMode == controllerNpcTrader.BUY and hasItem and self.selectedItem then
            local mc = self.selectedItem.mountClientId
            if mc and mc > 0 then
                mountClientId = mc
            else
                mountClientId = TRADE_MOUNT_PREVIEW_BY_ITEM_ID[itemId]
            end
        end

        if mountClientId and g_game.getFeature(GamePlayerMounts) then
            preview:clearItem()
            preview:setVisible(false)
            local mw = self:ensureTradePreviewMountWidget(footer, preview)
            if mw then
                self:applyTradeMountPreview(mw, mountClientId)
                mw:setVisible(true)
                self:syncTradeMountPreviewLayout(preview, mw)
                addEvent(function()
                    if not controllerNpcTrader.isTradeOpen or not footer or footer:isDestroyed() then
                        return
                    end
                    local ip = footer:getChildById("tradePreview")
                    local cw = footer:getChildById("tradePreviewMount")
                    if ip and cw and not ip:isDestroyed() and not cw:isDestroyed() then
                        controllerNpcTrader:syncTradeMountPreviewLayout(ip, cw)
                    end
                end)
            else
                preview:setVisible(true)
                if hasItem and self.selectedItem.ptr then
                    preview:setItem(self.selectedItem.ptr)
                else
                    preview:clearItem()
                end
            end
        else
            local mw = footer:getChildById("tradePreviewMount")
            if mw and not mw:isDestroyed() then
                mw:setVisible(false)
            end
            preview:setVisible(true)
            if hasItem and self.selectedItem.ptr then
                preview:setItem(self.selectedItem.ptr)
            else
                preview:clearItem()
            end
        end
    end

    local amountInput = footer:recursiveGetChildById("tradeAmountInput")
    if amountInput and amountInput.setText then
        -- Ao trocar de item o input pode continuar "focado" na UI HTML; força texto = self.amount.
        local forceSync = self._forceAmountInputRefresh == true
        if forceSync then
            self._forceAmountInputRefresh = false
            self._typingAmount = false
            self._amountInputEmpty = false
        end
        local focused = amountInput.isFocused and amountInput:isFocused()
        if forceSync or (not focused and not self._typingAmount) then
            logDebug("refreshFooter setText", "forceSync=", forceSync, "focused=", focused, "typing=", self._typingAmount, "amount=", self.amount)
            amountInput:setText(tostring(self.amount or 0))
        else
            logDebug("refreshFooter skip", "focused=", focused, "typing=", self._typingAmount, "amount=", self.amount,
                "empty=", self._amountInputEmpty, "handling=", self._handlingAmountInput)
        end
    elseif self._forceAmountInputRefresh then
        self._forceAmountInputRefresh = false
    end

    self.playerMoney = self:getPlayerMoney()

    local tradeBtn = footer:getChildById("toggleButton")
    if tradeBtn then
        local canTrade = hasItem and (self.amount or 0) > 0
        tradeBtn:setEnabled(canTrade)
    end
end

function controllerNpcTrader:selectTradeItem(item, widget)
    if not item then return end
    local wasSameItem = (self.selectedItem and self.selectedItem.ptr and item.ptr and self.selectedItem.ptr == item.ptr) or false
    self.selectedItem = item
    logDebug("selectTradeItem", item.name or "nil", "ptrId", item.ptr and item.ptr:getId() or "nil", "mode", self.tradeMode == controllerNpcTrader.BUY and "BUY" or "SELL")
    if widget then
        widget:focus()
    end

    local initialAmount = 1
    if self.tradeMode == controllerNpcTrader.SELL then
        local qty = item.sellQty or self:getSellQuantity(item.ptr)
        item.sellQty = qty
        initialAmount = qty > 0 and qty or 0
        logDebug("selectTradeItem sellQty", qty, "initialAmount", initialAmount)
    elseif wasSameItem and (self.amount or 0) >= controllerNpcTrader.MIN_AMOUNT then
        -- Mantém o amount ao comprar repetidamente o mesmo item (experiência equivalente ao legacy).
        initialAmount = self.amount
    end

    self._forceAmountInputRefresh = true
    self:updateAmount(initialAmount)
end

function controllerNpcTrader:updateAmount(amount)
    if self._updatingAmount then return end
    self._updatingAmount = true
    logDebug("updateAmount in", "raw=", amount, "mode=", self.tradeMode, "selected=", self.selectedItem and (self.selectedItem.name or "item") or "nil")
    amount = tonumber(amount) or 0
    if self.selectedItem then
        local maxAmount = controllerNpcTrader.MAX_AMOUNT_NORMAL
        local minAmount = controllerNpcTrader.MIN_AMOUNT
        if self.tradeMode == controllerNpcTrader.BUY then
            local playerMoney = self:getPlayerMoney()
            local price = self.selectedItem.price
            if price > 0 then
                local maxByMoney = math.floor(playerMoney / price)
                maxAmount = math.max(minAmount,
                    math.min(controllerNpcTrader.MAX_AMOUNT_NORMAL, maxByMoney))
                local mountOnly = (self.selectedItem.mountServerId or 0) > 0
                if not mountOnly and self.selectedItem.ptr and self.selectedItem.ptr:isStackable() then
                    maxAmount = math.max(minAmount,
                        math.min(controllerNpcTrader.MAX_AMOUNT_STACKABLE, maxByMoney))
                end
            end
        else
            local sellable = self:getSellQuantity(self.selectedItem.ptr)
            maxAmount = sellable
            if sellable > 0 then
                minAmount = controllerNpcTrader.MIN_AMOUNT
            else
                minAmount = 0
                amount = 0
            end
        end
        -- Teto global do controle (independente de dinheiro/estoque).
        local uiCap = tonumber(controllerNpcTrader.MAX_AMOUNT_UI) or 50
        if uiCap > 0 then
            maxAmount = math.min(maxAmount, uiCap)
        end
        logDebug("updateAmount clamp", "min=", minAmount, "max=", maxAmount, "before=", amount)
        if amount > maxAmount then
            amount = maxAmount
        end
        if amount < minAmount then
            amount = minAmount
        end
        local scroll = self:findTradeWidget("#amountScrollBar")
        if scroll then
            scroll:setMaximum(math.max(1, maxAmount))
            scroll:setMinimum(minAmount)
            scroll:setEnabled(maxAmount > 0)
            if scroll:getValue() ~= amount then
                logDebug("updateAmount scroll:setValue", "from=", scroll:getValue(), "to=", amount,
                    "settingFromInput=", self._settingAmountScrollFromInput)
                -- Evita que o onAmountScrollBarChange trate isso como ação do usuário.
                local prev = self._settingAmountScrollFromInput
                self._settingAmountScrollFromInput = true
                scroll:setValue(amount)
                self._settingAmountScrollFromInput = prev
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
    self._updatingAmount = false
    logDebug("updateAmount out", "amount=", self.amount, "totalPrice=", self.totalPrice, "totalWeight=", self.totalWeight)
    self:refreshFooter()
end

function controllerNpcTrader:onAmountScrollBarChange(value)
    logDebug("onAmountScrollBarChange", "value=", value, "settingFromInput=", self._settingAmountScrollFromInput,
        "handling=", self._handlingAmountInput, "typing=", self._typingAmount)
    -- Se a barra disparou durante um update interno, não reprocessa nem escreve no input.
    if self._updatingAmount then
        logDebug("onAmountScrollBarChange skip (updatingAmount)")
        return
    end
    -- Mudança programática (originada do input/updateAmount) não deve mexer no texto enquanto o usuário digita.
    if self._settingAmountScrollFromInput then
        logDebug("onAmountScrollBarChange skip (programmatic)")
        return
    end
    self:updateAmount(value)
    -- Se o usuário estiver com o input focado (ex.: apagou tudo), mover a barra deve refletir no campo.
    local footer = self.ui and self.ui:recursiveGetChildById("tradeFooter")
    local amountInput = footer and footer:recursiveGetChildById("tradeAmountInput")
    if amountInput and amountInput.setText and amountInput.isFocused and amountInput:isFocused() then
        self._amountInputEmpty = false
        self._typingAmount = true
        logDebug("onAmountScrollBarChange setText", "amount=", self.amount)
        amountInput:setText(tostring(self.amount or 0))
        self._typingAmount = false
    end
end

function controllerNpcTrader:onAmountInputChange(event)
    if self._handlingAmountInput then
        logDebug("onAmountInputChange skip (reentrant)")
        return
    end
    if self._tradeAmountInputFocusClearing then
        return
    end
    self._handlingAmountInput = true
    local input = event and event.target
    -- Em UI HTML, o onTextChange pode disparar antes do texto final estar aplicado no widget.
    -- Para garantir consistência (ex.: selecionar "1" e digitar "30" => "30"), processa no próximo tick.
    if event and not event._deferred and input and input.getText then
        logDebug("onAmountInputChange defer", "event.value=", event.value, "inputTextNow=", input:getText())
        addEvent(function()
            if controllerNpcTrader and controllerNpcTrader.isTradeOpen and input and not input:isDestroyed() then
                controllerNpcTrader:onAmountInputChange({ target = input, _deferred = true })
            end
        end)
        self._handlingAmountInput = false
        return
    end

    local text = (input and input.getText and input:getText()) or ""
    logDebug("onAmountInputChange run", "deferred=", event and event._deferred, "text=", text, "focused=", input and input.isFocused and input:isFocused())
    local cleanText = text:gsub("[^%d]", "")
    if cleanText ~= text then
        logDebug("onAmountInputChange sanitize", "from=", text, "to=", cleanText)
        self._typingAmount = true
        input:setText(cleanText)
        self._typingAmount = false
        text = cleanText
    end
    local scroll = self:findTradeWidget("#amountScrollBar")
    -- Permite apagar o valor (texto vazio) sem "grudar" no default.
    -- Quando vazio, a barra volta para o mínimo (1) e passa a controlar a quantidade normalmente.
    if text == "" then
        logDebug("onAmountInputChange empty", "willSetMin", scroll and scroll.getMinimum and scroll:getMinimum() or 1)
        self._amountInputEmpty = true
        local minV = (scroll and scroll.getMinimum and scroll:getMinimum()) or 1
        -- Atualiza quantidade/barra para o mínimo, mas sem reescrever o texto do input.
        self._settingAmountScrollFromInput = true
        self:updateAmount(minV)
        if scroll and scroll.getValue and scroll:getValue() ~= (self.amount or minV) then
            logDebug("onAmountInputChange empty scroll:setValue", "to=", self.amount or minV)
            scroll:setValue(self.amount or minV)
        end
        self._settingAmountScrollFromInput = false
        self._handlingAmountInput = false
        return
    end

    self._amountInputEmpty = false
    local amount = tonumber(text) or 1
    logDebug("onAmountInputChange parsed", "amount=", amount)
    self._typingAmount = true
    self:updateAmount(amount)
    self._typingAmount = false

    if scroll then
        if self.amount ~= amount then
            logDebug("onAmountInputChange mismatch", "typed=", amount, "clamped=", self.amount)
            self._typingAmount = true
            input:setText(tostring(self.amount))
            self._typingAmount = false
        end
        self._settingAmountScrollFromInput = true
        logDebug("onAmountInputChange scroll:setValue", "to=", self.amount)
        scroll:setValue(self.amount)
        self._settingAmountScrollFromInput = false
    end
    self._handlingAmountInput = false
end

--- UI HTML: ao focar/clicar no Amount, limpa o campo e posiciona a barra no mínimo (quantidade interna = min até digitar).
function controllerNpcTrader:onTradeAmountInputFocus(target)
    if not self.isTradeOpen or not target or target:isDestroyed() or not target.setText then
        return
    end
    self._tradeAmountInputFocusClearing = true
    self._typingAmount = true
    target:setText('')
    self._tradeAmountInputFocusClearing = false
    self._amountInputEmpty = true

    local scroll = self:findTradeWidget('#amountScrollBar')
    local minV = (scroll and scroll.getMinimum and scroll:getMinimum()) or 1
    self:updateAmount(minV)
    self._typingAmount = false
end

--- Se sair do campo vazio, aplica quantidade mínima e sincroniza texto/barra.
function controllerNpcTrader:onTradeAmountInputBlur(target)
    if not self.isTradeOpen or not target or target:isDestroyed() or not target.getText then
        return
    end
    local text = target:getText() or ''
    if text ~= '' and not text:match('^%s*$') then
        return
    end
    local scroll = self:findTradeWidget('#amountScrollBar')
    local minV = (scroll and scroll.getMinimum and scroll:getMinimum()) or 1
    self._typingAmount = true
    self:updateAmount(minV)
    target:setText(tostring(self.amount or minV))
    self._typingAmount = false
    self._amountInputEmpty = false
end

--- O motor de templates HTML não expõe onblur; liga-se aqui após carregar a UI.
function controllerNpcTrader:setupTradeAmountInputHooks()
    if not self.ui or self.ui:isDestroyed() then
        return
    end
    local input = self.ui:recursiveGetChildById("tradeAmountInput")
    if not input or input:isDestroyed() then
        return
    end
    input.onFocusChange = function(widget, focused)
        if focused then
            return
        end
        if controllerNpcTrader and controllerNpcTrader.onTradeAmountInputBlur then
            controllerNpcTrader:onTradeAmountInputBlur(widget)
        end
    end
end

function controllerNpcTrader:getPlayerMoney()
    local cid = self.currencyId or controllerNpcTrader.currencyId or controllerNpcTrader.DEFAULT_CURRENCY_ID
    local player = g_game.getLocalPlayer()
    if not player then
        return 0
    end
    if cid == controllerNpcTrader.DEFAULT_CURRENCY_ID then
        return player:getTotalMoney()
    end
    return player:getResourceBalance(ResourceTypes.CURRENCY_CUSTOM_EQUIPPED)
end

function controllerNpcTrader:getSellQuantity(itemPtr)
    if not itemPtr then
        return 0
    end
    local id = itemPtr:getId()
    local inventoryTotal = self.playerItems and self.playerItems[id] or 0

    if self.ignoreEquipped then
        local player = g_game.getLocalPlayer()
        local equippedCount = 0
        for i = 1, 10 do
            local item = player:getInventoryItem(i)
            if item and item:getId() == id then
                equippedCount = equippedCount + item:getCount()
            end
        end
        return math.max(0, inventoryTotal - equippedCount)
    end

    return inventoryTotal
end

function controllerNpcTrader:onPlayerGoods(items)
    if not items or type(items) ~= "table" then
        return
    end
    self.playerItems = items
    self:refreshPlayerGoods()
end

function controllerNpcTrader:refreshPlayerGoods()
    self.playerMoney = self:getPlayerMoney()
    if self.tradeMode == controllerNpcTrader.SELL then
        self:updateSellQuantities()
    end
    if self.selectedItem then
        self:updateAmount(self.amount)
    end
end

controllerNpcTrader.LARGE_AMOUNT_THRESHOLD = 100

function controllerNpcTrader:executeTrade()
    if not self.selectedItem or (self.amount or 0) <= 0 then
        return
    end

    local function doTrade()
        if self.tradeMode == controllerNpcTrader.BUY then
            g_game.buyItem(self.selectedItem.ptr, self.amount, self.ignoreCapacity, self.buyWithBackpack)
        else
            g_game.sellItem(self.selectedItem.ptr, self.amount, self.ignoreEquipped)
        end
    end

    if not self.noLargeAmountWarning and self.amount >= controllerNpcTrader.LARGE_AMOUNT_THRESHOLD then
        local action = self.tradeMode == controllerNpcTrader.BUY and tr("buy") or tr("sell")
        local msg = tr("Do you really want to %s %d x %s?", action, self.amount, self.selectedItem.name or "")
        local confirmBox
        confirmBox = displayGeneralBox(tr("Warning"), msg, {
            { text = tr("Yes"), callback = function() if confirmBox then confirmBox:destroy() confirmBox = nil end doTrade() end },
            { text = tr("No"),  callback = function() if confirmBox then confirmBox:destroy() confirmBox = nil end end },
        }, nil, function() if confirmBox then confirmBox:destroy() confirmBox = nil end end)
        return
    end

    doTrade()
end

function controllerNpcTrader:toggleSearchField()
    self.showSearchField = not self.showSearchField
    -- HTML UI
    local searchRow = self:findWidget(".tradeSearchRow")
    if searchRow then
        searchRow:setVisible(self.showSearchField)
    end
    -- Legacy UI
    local searchLabel = self.ui and self.ui:recursiveGetChildById("searchLabel")
    local searchText = self.ui and self.ui:recursiveGetChildById("searchText")
    if searchLabel then searchLabel:setVisible(self.showSearchField) end
    if searchText then searchText:setVisible(self.showSearchField) end
    if not self.showSearchField then
        self:clearSearch()
    end
end

function controllerNpcTrader:clearSearch()
    local input = self:findWidget(".tradeSearchInput")
    if input then
        input:setText("")
    end
    local legacyInput = self.ui and self.ui:recursiveGetChildById("searchText")
    if legacyInput then
        legacyInput:setText("")
    end
    self:filterTradeList("")
end

function controllerNpcTrader:filterTradeList(searchText)
    if not self.allTradeItems then
        return
    end

    self.searchText = searchText
    local lowerSearch = searchText:lower()
    local filteredItems = {}

    if searchText == "" then
        filteredItems = self.allTradeItems
    else
        for _, item in ipairs(self.allTradeItems) do
            if item.name:lower():find(lowerSearch, 1, true) then
                table.insert(filteredItems, item)
            end
        end
    end

    self:sortTradeItems(filteredItems)

    self.currentList = filteredItems
    self.tradeItems = {}
    self.loadedItems = 0
    self:loadNextBatch()

    if #self.tradeItems > 0 and not self.selectedItem then
        self.shouldFocusFirst = true
    end
    logDebug("filterTradeList search", searchText, "results", #filteredItems)
end

--- Tooltip ajuda (poções/runas/boost) na lista HTML do trade.
function controllerNpcTrader:onNpcTradeRowHover(item, hovered)
    local nt = modules.game_npctrader and modules.game_npctrader.NpcTradeTooltip
    if not nt or not item or not item.ptr then
        return
    end
    nt.onHoverItem({
        item = item.ptr,
        name = item.name
    }, hovered)
end
