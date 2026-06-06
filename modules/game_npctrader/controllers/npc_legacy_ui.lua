local BUY = 1
local SELL = 2
local CURRENCY = 'gold'
local CURRENCY_DECIMAL = false
local WEIGHT_UNIT = 'oz'
local LAST_INVENTORY = 10

local npcWindow = nil
local itemsPanel = nil
local searchText = nil
local setupPanel = nil
local quantityScroll = nil
local quantityEdit = nil
local priceLabel = nil
local moneyLabel = nil
local legacySelectionItem = nil
local tradeButton = nil
local buyTab = nil
local sellTab = nil
local headPanel = nil
local initialized = false

local showWeight = true
local buyWithBackpack = false
local ignoreCapacity = false
local ignoreEquipped = true

local playerFreeCapacity = 0
local playerMoney = 0
local tradeItems = {[BUY] = {}, [SELL] = {}}
local playerItems = {}
local selectedItem = nil
local selectedItemBox = nil

local cancelNextRelease = nil
local _legacyQtySync = false
local _legacyQtyFocusClearing = false
local _legacyClosing = false

local _legacyPlayerGoodsRefreshScheduled = false
local _legacyInternalUpdate = false

local function legacySetItemWidgetFromEntry(itemWidget, entry)
    if not itemWidget or itemWidget:isDestroyed() or not entry or not entry.itemId then
        return
    end
    itemWidget:setItemId(entry.itemId)
    if entry.isStackable then
        itemWidget:setItemCount(math.max(1, entry.displayCot or 1))
    else
        itemWidget:setItemSubType(entry.displayCot or 0)
    end
end

local function legacyItemForProtocolFromEntry(entry)
    if not entry or not entry.itemId then
        return nil
    end
    local i = Item.create(entry.itemId)
    if i then
        i:setCount(entry.displayCot or 1)
    end
    return i
end

--- Trunca texto para largura da coluna.
local function short_text(text, maxLen)
    if not text then return '' end
    if #text > maxLen then
        return text:sub(1, maxLen - 2) .. '..'
    end
    return text
end

--- Gold do jogador na linha inferior: separador de milhares + sufixo " k" (estilo global).
local function formatLegacyPlayerGold(amount)
    local n = math.floor(tonumber(amount) or 0)
    if n < 0 then
        n = 0
    end
    local s = tostring(n)
    local formatted = s:reverse():gsub('(%d%d%d)', '%1,'):reverse()
    if formatted:sub(1, 1) == ',' then
        formatted = formatted:sub(2)
    end
    return formatted .. ' k'
end

local function applyItemBoxTradeableVisual(box, canTrade)
    if not box or box:isDestroyed() then
        return
    end
    local lbl = box:getChildById('nameLabel')
    if lbl and not lbl:isDestroyed() then
        lbl:setEnabled(canTrade)
        lbl:setColor(canTrade and '#c0c0c0' or '#707070')
    end
end

local function deselectCurrentItemBox()
    if selectedItemBox and not selectedItemBox:isDestroyed() then
        selectedItemBox:setOn(false)
    end
    selectedItemBox = nil
end

local function applyLegacyRowSelection(box)
    if not box or box:isDestroyed() then
        return
    end
    local item = box.item
    if not item or not item.itemId then
        return
    end
    deselectCurrentItemBox()
    box:setOn(true)
    selectedItemBox = box
    selectedItem = item
    refreshItem(item, true)
    if tradeButton and not tradeButton:isDestroyed() and quantityScroll and not quantityScroll:isDestroyed() then
        if quantityScroll:getMaximum() >= 1 and quantityScroll:getValue() >= 1 then
            tradeButton:enable()
        else
            tradeButton:disable()
        end
    end
end

local function scheduleLegacyRefreshPlayerGoods()
    if not initialized or not controllerNpcTrader or not controllerNpcTrader.isTradeOpen then
        return
    end
    if _legacyPlayerGoodsRefreshScheduled then
        return
    end
    _legacyPlayerGoodsRefreshScheduled = true
    scheduleEvent(function()
        _legacyPlayerGoodsRefreshScheduled = false
        if not initialized or not controllerNpcTrader or not controllerNpcTrader.isTradeOpen then
            return
        end
        refreshPlayerGoods()
    end, 0)
end

local function getLegacyTradeParentPanel()
    local gi = modules.game_interface
    if not gi then
        return nil
    end
    if gi.findContentPanelAvailable and npcWindow then
        local panel = gi.findContentPanelAvailable(npcWindow, 80)
        if panel then
            return panel
        end
    end
    if gi.getRightPanel then
        return gi.getRightPanel()
    end
    return nil
end

local function dockLegacyNpcTradeWindow()
    if not npcWindow or npcWindow:isDestroyed() then
        return
    end
    local panel = getLegacyTradeParentPanel()
    if not panel then
        return
    end
    if npcWindow:getParent() == panel then
        return
    end
    local old = npcWindow:getParent()
    if old and not old:isDestroyed() then
        old:removeChild(npcWindow)
    end
    local gi = modules.game_interface
    if gi and gi.addWindowToPanelInSequence then
        gi.addWindowToPanelInSequence(panel, npcWindow)
    else
        panel:addChild(npcWindow)
    end
end

local legacyTradeMode = BUY

local function syncLegacyTabVisuals()
    if buyTab and not buyTab:isDestroyed() then
        buyTab:setOn(legacyTradeMode == BUY)
    end
    if sellTab and not sellTab:isDestroyed() then
        sellTab:setOn(legacyTradeMode == SELL)
    end
end

local function setLegacyTradeModeFromUser(mode)
    if legacyTradeMode == mode then
        return
    end
    legacyTradeMode = mode
    syncLegacyTabVisuals()
    refreshTradeItems()
    refreshPlayerGoods()
end

local function hideLegacyMiniWindowExtras(root)
    if not root then
        return
    end
    for _, bid in ipairs({ 'lockButton', 'toggleFilterButton', 'contextMenuButton', 'newWindowButton' }) do
        local b = root:recursiveGetChildById(bid)
        if b then
            b:setVisible(false)
        end
    end
end

--- Campo vazio + barra no mínimo (igual à UI HTML ao focar/clicar em Amount).
local function legacyApplyQuantityEditFocusClear(widget)
    if not initialized or _legacyInternalUpdate or not widget or widget:isDestroyed() then
        return
    end
    if not selectedItem or not quantityScroll or quantityScroll:isDestroyed() then
        return
    end
    local minV = quantityScroll:getMinimum() or 0
    local maxV = quantityScroll:getMaximum() or 0
    if maxV < 1 then
        return
    end
    local v = math.max(minV, math.min(maxV, 1))
    _legacyQtyFocusClearing = true
    _legacyQtySync = true
    widget:clearText()
    quantityScroll:setValue(v)
    _legacyQtySync = false
    _legacyQtyFocusClearing = false
    if priceLabel and not priceLabel:isDestroyed() then
        priceLabel:setText(formatCurrency(getItemPrice(selectedItem)))
    end
end

local function bindLegacyOtuiSignals()
    if quantityScroll and not quantityScroll:isDestroyed() then
        quantityScroll.onValueChange = function(_, value)
            controllerNpcTrader:onQuantityValueChangeLegacy(value)
        end
    end
    if quantityEdit and not quantityEdit:isDestroyed() then
        quantityEdit.onTextChange = function(widget)
            controllerNpcTrader:onLegacyQuantityEditChange(widget)
        end
        quantityEdit.onFocusChange = function(widget, focused)
            controllerNpcTrader:onLegacyQuantityEditFocusChange(widget, focused)
        end
        quantityEdit.onClick = function(widget)
            legacyApplyQuantityEditFocusClear(widget)
        end
    end
end

local function refreshLegacyCurrencyRow()
    if not npcWindow or npcWindow:isDestroyed() then
        return
    end
    local lbl = npcWindow:recursiveGetChildById('currencyLabel')
    if lbl then
        lbl:setText(short_text(CURRENCY or '', 11))
    end
end

local function refreshLegacyCurrencyItem()
    if not npcWindow or npcWindow:isDestroyed() then
        return
    end
    local currencyWidget = npcWindow:recursiveGetChildById('currencyItem')
    if not currencyWidget then
        return
    end
    local cid = controllerNpcTrader._legacyCurrencyItemId
    if not cid or cid == 0 then
        cid = controllerNpcTrader.DEFAULT_CURRENCY_ID
    end
    if not cid then
        return
    end
    currencyWidget:setItemId(cid)
    currencyWidget:setItemCount(100)
end

function controllerNpcTrader:legacy_init()
    npcWindow = g_ui.displayUI('/game_npctrader/templates/npctrade_legacy')
    if not npcWindow then
        return
    end
    npcWindow:setVisible(false)
    hideLegacyMiniWindowExtras(npcWindow)

    npcWindow:setContentMinimumHeight(175)
    npcWindow:setContentHeight(175)
    npcWindow:setup()

    itemsPanel = npcWindow:recursiveGetChildById('contentsPanel')
    searchText = npcWindow:recursiveGetChildById('searchText')

    setupPanel = npcWindow:recursiveGetChildById('setupPanel')
    if not setupPanel or setupPanel:isDestroyed() then
        npcWindow:destroy()
        npcWindow = nil
        return
    end
    quantityScroll = setupPanel:getChildById('quantityScroll')
    if not quantityScroll or quantityScroll:isDestroyed() then
        npcWindow:destroy()
        npcWindow = nil
        return
    end
    quantityEdit = setupPanel:recursiveGetChildById('quantityEdit')
    priceLabel = npcWindow:recursiveGetChildById('price')
    moneyLabel = npcWindow:recursiveGetChildById('money')
    legacySelectionItem = setupPanel:recursiveGetChildById('legacySelectionItem')
    tradeButton = npcWindow:recursiveGetChildById('tradeButton')
    headPanel = npcWindow:recursiveGetChildById('headPanel')
    buyTab = npcWindow:recursiveGetChildById('buyTab')
    sellTab = npcWindow:recursiveGetChildById('sellTab')

    if buyTab and not buyTab:isDestroyed() then
        buyTab.onClick = function()
            setLegacyTradeModeFromUser(BUY)
        end
    end
    if sellTab and not sellTab:isDestroyed() then
        sellTab.onClick = function()
            setLegacyTradeModeFromUser(SELL)
        end
    end
    syncLegacyTabVisuals()

    cancelNextRelease = false

    if g_game.isOnline() then
        local lp = g_game.getLocalPlayer()
        if lp then
            playerFreeCapacity = lp:getFreeCapacity()
        end
    end

    connect(LocalPlayer, {
        onFreeCapacityChange = onFreeCapacityChange,
        onInventoryChange = onInventoryChange
    })

    controllerNpcTrader.legacyWindow = npcWindow
    controllerNpcTrader.legacyTradeItems = tradeItems

    setShowWeight(false)
    refreshLegacyCurrencyRow()
    refreshLegacyCurrencyItem()

    bindLegacyOtuiSignals()

    initialized = true
end

function controllerNpcTrader:legacyClearSearch()
    if searchText and not searchText:isDestroyed() then
        searchText:clearText()
    end
    if initialized then
        refreshPlayerGoods()
    end
end

function controllerNpcTrader:ensureLegacyInit()
    if initialized and npcWindow and not npcWindow:isDestroyed() then
        return
    end
    if initialized then
        self:legacy_terminate()
    end
    self:legacy_init()
end

function controllerNpcTrader:legacy_terminate()
    initialized = false
    selectedItem = nil
    selectedItemBox = nil
    _legacyPlayerGoodsRefreshScheduled = false
    _legacyInternalUpdate = false
    _legacyClosing = false

    disconnect(LocalPlayer, {
        onFreeCapacityChange = onFreeCapacityChange,
        onInventoryChange = onInventoryChange
    })

    if npcWindow then
        npcWindow:destroy()
    end
    npcWindow = nil
    controllerNpcTrader.legacyWindow = nil
end

function controllerNpcTrader:legacy_show()
    if not g_game.isOnline() or not npcWindow or npcWindow:isDestroyed() then
        return
    end
    dockLegacyNpcTradeWindow()
    syncLegacyTabVisuals()
    npcWindow:show()
    npcWindow:raise()
end

function controllerNpcTrader:onLegacyWindowClose()
    if _legacyClosing then
        return
    end
    _legacyClosing = true
    self:onCloseNpcTrade()
    _legacyClosing = false
end

function controllerNpcTrader:legacy_hide()
    if npcWindow and not npcWindow:isDestroyed() then
        npcWindow:hide()
    end
end

function controllerNpcTrader:legacy_onNpcTradeUiClosed()
    selectedItem = nil
    deselectCurrentItemBox()
    if initialized and npcWindow and not npcWindow:isDestroyed() then
        clearSelectedItem()
    end
end

function controllerNpcTrader:onQuantityValueChangeLegacy(quantity)
    if not initialized or _legacyInternalUpdate then
        return
    end
    if _legacyQtySync or _legacyQtyFocusClearing then
        return
    end
    _legacyQtySync = true
    if quantityEdit and not quantityEdit:isDestroyed() then
        quantityEdit:setText(tostring(quantity))
    end
    _legacyQtySync = false
    if selectedItem and priceLabel and not priceLabel:isDestroyed() then
        priceLabel:setText(formatCurrency(getItemPrice(selectedItem)))
    end
end

function controllerNpcTrader:onLegacyQuantityEditChange(widget)
    if not initialized or _legacyQtySync or not selectedItem or not quantityScroll or quantityScroll:isDestroyed() or not widget or widget:isDestroyed() then
        return
    end
    local raw = widget:getText()
    if raw == nil or raw == '' or raw:match('^%s*$') then
        return
    end
    local n = tonumber(raw:match('^%s*(%d+)'))
    if not n then
        return
    end
    local minV = quantityScroll:getMinimum()
    local maxV = quantityScroll:getMaximum()
    if maxV < minV or maxV < 1 then
        return
    end
    n = math.max(minV, math.min(maxV, math.floor(n)))
    _legacyQtySync = true
    quantityScroll:setValue(n)
    widget:setText(tostring(n))
    _legacyQtySync = false
    if priceLabel and not priceLabel:isDestroyed() then
        priceLabel:setText(formatCurrency(getItemPrice(selectedItem)))
    end
end

--- Ao focar: limpa o texto e põe a barra no mínimo; ao sair: confirma min/max.
function controllerNpcTrader:onLegacyQuantityEditFocusChange(widget, focused)
    if not initialized or _legacyQtySync or not quantityScroll or quantityScroll:isDestroyed() or not widget or widget:isDestroyed() then
        return
    end
    if focused then
        legacyApplyQuantityEditFocusClear(widget)
        return
    end
    self:onLegacyQuantityEditCommit(widget)
end

function controllerNpcTrader:onLegacyQuantityEditCommit(widget)
    if not initialized or _legacyQtySync or not selectedItem or not quantityScroll or quantityScroll:isDestroyed() or not widget or widget:isDestroyed() then
        return
    end
    local raw = widget:getText()
    local minV = quantityScroll:getMinimum()
    local maxV = quantityScroll:getMaximum()
    local n
    if raw == nil or raw == '' or raw:match('^%s*$') then
        if maxV >= 1 and minV <= maxV then
            n = math.max(minV, math.min(maxV, 1))
        else
            n = minV
        end
    else
        local parsed = tonumber(raw:match('^%s*(%d+)'))
        if not parsed then
            n = (maxV >= 1 and minV <= maxV) and math.max(minV, math.min(maxV, 1)) or minV
        else
            n = math.max(minV, math.min(maxV, math.floor(parsed)))
        end
    end
    _legacyQtySync = true
    quantityScroll:setValue(n)
    widget:setText(tostring(n))
    _legacyQtySync = false
    if priceLabel and not priceLabel:isDestroyed() then
        priceLabel:setText(formatCurrency(getItemPrice(selectedItem)))
    end
end

function controllerNpcTrader:onTradeClickLegacy()
    if not selectedItem or not selectedItem.itemId or not quantityScroll or quantityScroll:isDestroyed() then
        return
    end
    local qty = quantityScroll:getValue()
    if qty < 1 then
        return
    end
    local sendItem = legacyItemForProtocolFromEntry(selectedItem)
    if not sendItem then
        return
    end
    if getCurrentTradeType() == BUY then
        g_game.buyItem(sendItem, qty, ignoreCapacity, buyWithBackpack)
    else
        g_game.sellItem(sendItem, qty, ignoreEquipped)
    end
    addEvent(function()
        scheduleLegacyRefreshPlayerGoods()
    end)
end

function controllerNpcTrader:onSearchTextChangeLegacy()
    if not initialized or _legacyInternalUpdate then
        return
    end
    refreshPlayerGoods()
end

function itemPopup(self, mousePosition, mouseButton)
    if cancelNextRelease then
        cancelNextRelease = false
        return false
    end

    local itemWidget = self:getChildById('item')
    if not itemWidget then
        itemWidget = self
    end

    if mouseButton == MouseRightButton then
        local menu = g_ui.createWidget('PopupMenu')
        menu:setGameMenu(true)

        menu:addOption(tr('Look'), function()
            return g_game.inspectNpcTrade(itemWidget:getItem())
        end)
        menu:addOption(tr('Inspect'), function()
            return g_game.inspectNpcTrade(itemWidget:getItem())
        end)

        menu:addSeparator()

        local sortOptions = {
            { label = "Sort by name",   key = 'name' },
            { label = "Sort by price",  key = 'price' },
            { label = "Sort by weight", key = 'weight' },
        }
        for _, opt in ipairs(sortOptions) do
            local checked = (controllerNpcTrader.sortBy == opt.key)
            menu:addOption(tr(opt.label), function()
                controllerNpcTrader:setSortBy(opt.key)
            end)
        end

        menu:addSeparator()

        if getCurrentTradeType() == BUY then
            menu:addOption(tr('Buy in shopping bags') .. (buyWithBackpack and ' [x]' or ''), function()
                buyWithBackpack = not buyWithBackpack
                refreshPlayerGoods()
            end)
            menu:addOption(tr('Ignore capacity') .. (ignoreCapacity and ' [x]' or ''), function()
                ignoreCapacity = not ignoreCapacity
                refreshPlayerGoods()
            end)
        else
            menu:addOption(tr('Sell equipped') .. (not ignoreEquipped and ' [x]' or ''), function()
                ignoreEquipped = not ignoreEquipped
                refreshTradeItems()
                refreshPlayerGoods()
            end)
        end

        menu:display(mousePosition)
        return true
    elseif ((g_mouse.isPressed(MouseLeftButton) and mouseButton == MouseRightButton) or
        (g_mouse.isPressed(MouseRightButton) and mouseButton == MouseLeftButton)) then
        cancelNextRelease = true
        g_game.inspectNpcTrade(itemWidget:getItem())
        return true
    end
    return false
end

function controllerNpcTrader:onBuyWithBackpackChangeLegacy()
    if not initialized then
        return
    end
    if selectedItem then
        refreshItem(selectedItem)
    end
end

function controllerNpcTrader:onIgnoreCapacityChangeLegacy()
    if not initialized then
        return
    end
    refreshPlayerGoods()
end

function controllerNpcTrader:onIgnoreEquippedChangeLegacy()
    if not initialized then
        return
    end
    refreshPlayerGoods()
end

function controllerNpcTrader:onShowAllItemsChangeLegacy()
    if not initialized then
        return
    end
    refreshPlayerGoods()
end

function setCurrency(currency, decimal)
    CURRENCY = currency
    CURRENCY_DECIMAL = decimal
    refreshLegacyCurrencyRow()
end

function setShowWeight(state)
    showWeight = state
end

function setShowYourCapacity(state)
end

function clearSelectedItem()
    local wasInternal = _legacyInternalUpdate
    _legacyInternalUpdate = true

    if priceLabel and not priceLabel:isDestroyed() then
        priceLabel:setText('0')
    end
    if quantityEdit and not quantityEdit:isDestroyed() then
        quantityEdit:setText('0')
    end
    if legacySelectionItem and not legacySelectionItem:isDestroyed() then
        legacySelectionItem:clearItem()
    end
    if tradeButton and not tradeButton:isDestroyed() then
        tradeButton:disable()
    end
    if quantityScroll and not quantityScroll:isDestroyed() then
        quantityScroll:setMinimum(0)
        quantityScroll:setMaximum(0)
    end
    deselectCurrentItemBox()
    selectedItem = nil

    _legacyInternalUpdate = wasInternal
end

function getCurrentTradeType()
    return legacyTradeMode
end

function getItemPrice(item, single)
    if not item or not item.itemId or not quantityScroll or quantityScroll:isDestroyed() then
        return 0
    end
    local amount = 1
    local single = single or false
    if not single then
        amount = quantityScroll:getValue()
    end
    if getCurrentTradeType() == BUY then
        if buyWithBackpack then
            if item.isStackable then
                return item.price * amount + 20
            else
                return item.price * amount + math.ceil(amount / 20) * 20
            end
        end
    end
    return (item.price or 0) * amount
end

function getSellQuantityFromItemId(itemId)
    if not itemId or not playerItems[itemId] then
        return 0
    end
    local removeAmount = 0
    if ignoreEquipped then
        local localPlayer = g_game.getLocalPlayer()
        if localPlayer then
            for i = 1, LAST_INVENTORY do
                local inventoryItem = localPlayer:getInventoryItem(i)
                if inventoryItem and inventoryItem:getId() == itemId then
                    removeAmount = removeAmount + inventoryItem:getCount()
                end
            end
        end
    end
    return playerItems[itemId] - removeAmount
end

function canTradeItem(item)
    if not item or not item.itemId then
        return false
    end
    if getCurrentTradeType() == BUY then
        return (ignoreCapacity or playerFreeCapacity >= (item.weight or 0)) and playerMoney >= getItemPrice(item, true)
    end
    return getSellQuantityFromItemId(item.itemId) > 0
end

function refreshItem(item, newRowSelection)
    if not item or not item.itemId or not quantityScroll or quantityScroll:isDestroyed() then
        return
    end

    local function applyQuantityRange(minV, maxV, preferValue)
        if minV > maxV then
            minV, maxV = 0, 0
        end
        quantityScroll:setMinimum(minV)
        quantityScroll:setMaximum(maxV)
        local v = math.max(minV, math.min(maxV, preferValue))
        quantityScroll:setValue(v)
        _legacyQtySync = true
        if quantityEdit and not quantityEdit:isDestroyed() then
            quantityEdit:setText(tostring(v))
        end
        _legacyQtySync = false
    end

    local currentValue = quantityScroll:getValue() or 0

    if getCurrentTradeType() == BUY then
        local uw = item.weight
        if not uw or uw <= 0 then
            uw = 0.0001
        end
        local capacityMaxCount = math.floor(playerFreeCapacity / uw)
        if ignoreCapacity then
            capacityMaxCount = 65535
        end
        local unitPrice = getItemPrice(item, true)
        local priceMaxCount = (unitPrice > 0) and math.floor(playerMoney / unitPrice) or 0
        local finalCount = math.max(0, math.min(getMaxAmount(), math.min(priceMaxCount, capacityMaxCount)))
        if finalCount >= 1 then
            local prefer
            if newRowSelection then
                prefer = 1
            else
                prefer = (currentValue and currentValue >= 1) and math.min(currentValue, finalCount) or 1
            end
            applyQuantityRange(1, finalCount, prefer)
        else
            applyQuantityRange(0, 0, 0)
        end
    else
        local sq = math.max(0, math.min(getMaxAmount(), getSellQuantityFromItemId(item.itemId)))
        if sq >= 1 then
            local prefer
            if newRowSelection then
                prefer = sq
            else
                -- Mesmo item (ex.: atualização de lista/inventário): mantém quantidade até o teto atual.
                prefer = (currentValue and currentValue >= 1) and math.min(currentValue, sq) or sq
            end
            applyQuantityRange(1, sq, prefer)
        else
            applyQuantityRange(0, 0, 0)
        end
    end

    controllerNpcTrader:onQuantityValueChangeLegacy(quantityScroll:getValue())

    if legacySelectionItem and not legacySelectionItem:isDestroyed() then
        legacySetItemWidgetFromEntry(legacySelectionItem, item)
    end

    if setupPanel and not setupPanel:isDestroyed() then
        setupPanel:enable()
    end
end

function refreshTradeItems()
    if not itemsPanel or itemsPanel:isDestroyed() then
        return
    end
    local nt = modules.game_npctrader and modules.game_npctrader.NpcTradeTooltip
    if nt then
        nt.onHoverItem(nil, false)
    end
    _legacyInternalUpdate = true

    local layout = itemsPanel.getLayout and itemsPanel:getLayout() or nil
    if layout and layout.disableUpdates then
        layout:disableUpdates()
    end

    clearSelectedItem()

    if searchText and not searchText:isDestroyed() then
        searchText:clearText()
    end
    if setupPanel and not setupPanel:isDestroyed() then
        setupPanel:disable()
    end
    itemsPanel:destroyChildren()

    local currentTradeItems = tradeItems[getCurrentTradeType()]
    for _, item in ipairs(currentTradeItems) do
        if getCurrentTradeType() == SELL and not canTradeItem(item) then
            goto continue
        end

        local itemBox = g_ui.createWidget('NPCItemBox', itemsPanel)
        itemBox.item = item
        itemBox.onClick = function(widget)
            applyLegacyRowSelection(widget)
        end
        itemBox.onHoverChange = function(_, hovered)
            local nt = modules.game_npctrader and modules.game_npctrader.NpcTradeTooltip
            if not nt or not item or not item.itemId then
                return
            end
            if not hovered then
                nt.onHoverItem(nil, false)
                return
            end
            local it = Item.create(item.itemId)
            if it then
                nt.onHoverItem({
                    item = it,
                    name = item.name
                }, true)
            end
        end

        local price = formatCurrency(item.price)
        local infoText = tr('Price') .. ' ' .. price
        if showWeight and (item.weight or 0) > 0 then
            infoText = infoText .. ', ' .. string.format('%.2f', item.weight) .. ' ' .. WEIGHT_UNIT
        end

        local description = string.format('%s\n%s', short_text(item.name, 15), short_text(infoText, 16))
        local nameLabel = itemBox:getChildById('nameLabel')
        if nameLabel then
            nameLabel:setText(description)
        end

        if (#item.name > 15) or (#infoText > 16) then
            itemBox:setTooltip(string.format('%s\n%s', item.name, infoText))
        end

        local itemWidget = itemBox:getChildById('item')
        if itemWidget and item.itemId then
            legacySetItemWidgetFromEntry(itemWidget, item)
            itemBox.onMouseRelease = itemPopup
        end

        if not canTradeItem(item) then
            applyItemBoxTradeableVisual(itemBox, false)
        end

        ::continue::
    end

    if layout and layout.enableUpdates then
        layout:enableUpdates()
        layout:update()
    end

    _legacyInternalUpdate = false
end

function refreshPlayerGoods()
    if not initialized or _legacyInternalUpdate then
        return
    end
    if not itemsPanel or itemsPanel:isDestroyed() or not searchText or searchText:isDestroyed() then
        return
    end

    _legacyInternalUpdate = true

    local listLayout = itemsPanel.getLayout and itemsPanel:getLayout() or nil
    if listLayout and listLayout.disableUpdates then
        listLayout:disableUpdates()
    end

    if moneyLabel and not moneyLabel:isDestroyed() then
        local cid = controllerNpcTrader._legacyCurrencyItemId
        local defId = controllerNpcTrader.DEFAULT_CURRENCY_ID
        if not cid or cid == 0 or cid == defId then
            moneyLabel:setText(formatLegacyPlayerGold(playerMoney))
        else
            moneyLabel:setText(formatCurrency(playerMoney))
        end
    end

    local currentTradeType = getCurrentTradeType()
    local searchFilter = searchText:getText():lower()
    local foundSelectedItem = false

    local items = itemsPanel:getChildCount()
    for i = 1, items do
        local itemWidget = itemsPanel:getChildByIndex(i)
        if itemWidget and not itemWidget:isDestroyed() then
            local item = itemWidget.item
            if type(item) == 'table' and item.itemId then
                local canTrade = canTradeItem(item)
                applyItemBoxTradeableVisual(itemWidget, canTrade)
                itemWidget:setEnabled(canTrade)

                local nameLower = item.name and item.name:lower() or ''
                local searchCondition = (searchFilter == '') or
                    (searchFilter ~= '' and string.find(nameLower, searchFilter) ~= nil)
                local showAllItemsCondition = (currentTradeType == BUY) or (currentTradeType == SELL and canTrade)
                itemWidget:setVisible(searchCondition and showAllItemsCondition)

                if selectedItem == item and itemWidget:isEnabled() and itemWidget:isVisible() then
                    foundSelectedItem = true
                end
            end
        end
    end

    if not foundSelectedItem then
        clearSelectedItem()
    end

    if selectedItem and selectedItem.itemId then
        refreshItem(selectedItem)
    end

    if listLayout and listLayout.enableUpdates then
        listLayout:enableUpdates()
        listLayout:update()
    end

    _legacyInternalUpdate = false
end

function controllerNpcTrader:onOpenNpcTradeLegacy(items, isNewSession)
    if isNewSession then
        tradeItems[BUY] = {}
        tradeItems[SELL] = {}
    end

    for _, item in ipairs(items or {}) do
        if type(item) == 'table' and item[1] then
            local ptr = item[1]
            local snapOk, itemId, displayCot, isStackable = pcall(function()
                return ptr:getId(), ptr:getCountOrSubType(), ptr:isStackable()
            end)
            if snapOk and type(itemId) == 'number' then
                if item[4] and item[4] > 0 then
                    table.insert(tradeItems[BUY], {
                        itemId = itemId,
                        displayCot = displayCot or 1,
                        isStackable = isStackable and true or false,
                        name = item[2],
                        weight = (item[3] or 0) / 100,
                        price = item[4],
                    })
                end
                if item[5] and item[5] > 0 then
                    table.insert(tradeItems[SELL], {
                        itemId = itemId,
                        displayCot = displayCot or 1,
                        isStackable = isStackable and true or false,
                        name = item[2],
                        weight = (item[3] or 0) / 100,
                        price = item[5],
                    })
                end
            end
        end
    end

    controllerNpcTrader.legacyTradeItems = tradeItems

    if #tradeItems[BUY] > 0 then
        legacyTradeMode = BUY
    else
        legacyTradeMode = SELL
    end

    scheduleEvent(function()
        if not controllerNpcTrader or not controllerNpcTrader.isTradeOpen then
            return
        end
        if not initialized or not npcWindow or npcWindow:isDestroyed() then
            return
        end
        syncLegacyTabVisuals()
        refreshTradeItems()
        refreshLegacyCurrencyRow()
        refreshLegacyCurrencyItem()
        refreshPlayerGoods()

        addEvent(function()
            if not controllerNpcTrader or not controllerNpcTrader.isTradeOpen then
                return
            end
            if not initialized or not npcWindow or npcWindow:isDestroyed() then
                return
            end
            controllerNpcTrader:legacy_show()
        end)
    end, 0)
end

function controllerNpcTrader:onCloseNpcTradeLegacy()
    controllerNpcTrader:onCloseNpcTrade()
end

function controllerNpcTrader:onPlayerGoodsLegacy(money, items)
    playerMoney = money

    playerItems = {}
    for key, item in pairs(items or {}) do
        local ok, id = pcall(function() return item[1]:getId() end)
        if ok and id then
            if not playerItems[id] then
                playerItems[id] = item[2]
            else
                playerItems[id] = playerItems[id] + item[2]
            end
        end
    end

    scheduleLegacyRefreshPlayerGoods()
end

function onFreeCapacityChange(localPlayer, freeCapacity, oldFreeCapacity)
    playerFreeCapacity = freeCapacity
    if npcWindow and not npcWindow:isDestroyed() and npcWindow:isVisible() then
        scheduleLegacyRefreshPlayerGoods()
    end
end

function onInventoryChange(inventory, item, oldItem)
    if initialized and npcWindow and not npcWindow:isDestroyed() and npcWindow:isVisible() then
        scheduleLegacyRefreshPlayerGoods()
    end
end

function getTradeItemData(id, type)
    if table.empty(tradeItems[type]) then
        return false
    end

    if type then
        for key, item in pairs(tradeItems[type]) do
            if item.itemId == id then
                return item
            end
        end
    else
        for _, items in pairs(tradeItems) do
            for key, item in pairs(items) do
                if item.itemId == id then
                    return item
                end
            end
        end
    end
    return false
end

function formatCurrency(amount)
    if CURRENCY_DECIMAL then
        return string.format('%.02f', amount / 100.0)
    else
        return tostring(amount)
    end
end

function getMaxAmount()
    if getCurrentTradeType() == SELL and g_game.getFeature(GameDoubleShopSellAmount) then
        return 10000
    end
    return 50
end

function controllerNpcTrader:sellAllLegacy()
    for itemid, _ in pairs(playerItems) do
        local amount = getSellQuantityFromItemId(itemid)
        if amount > 0 then
            local sendItem = Item.create(itemid)
            if sendItem then
                g_game.sellItem(sendItem, amount, ignoreEquipped)
            end
        end
    end
end

function sellAll(wait, exceptions)
    local ctrl = controllerNpcTrader
    local pItems = ctrl.playerItems or playerItems or {}
    for itemid, count in pairs(pItems) do
        if not exceptions or not table.find(exceptions, itemid) then
            local item = Item.create(itemid)
            local amount = ctrl:getSellQuantity(item)
            if amount > 0 then
                g_game.sellItem(item, amount, true)
                if wait then
                    scheduleEvent(function() end, 100)
                end
            end
        end
    end
end

function closeNpcTrade()
    controllerNpcTrader:onCloseNpcTrade()
end
