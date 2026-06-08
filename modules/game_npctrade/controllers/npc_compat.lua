local legacyCanTradeItem = canTradeItem
local legacyCloseNpcTrade = closeNpcTrade
local legacySellAll = sellAll

sellAllWhitelist = sellAllWhitelist or {}
npcWindow = npcWindow or nil
searchText = searchText or nil
amountText = amountText or nil

local function isLoadedPlayerReady()
    return LoadedPlayer and LoadedPlayer.isLoaded and LoadedPlayer:isLoaded()
end

function saveData()
    if not isLoadedPlayerReady() then return end

    local file = "/characterdata/" .. LoadedPlayer:getId() .. "/sellAllWhitelist.json"
    local status, result = pcall(function() return json.encode(sellAllWhitelist, 2) end)
    if not status then
        return g_logger.error("Error while saving profile sellAllWhitelist. Data won't be saved. Details: " .. result)
    end

    if result:len() > 100 * 1024 * 1024 then
        return g_logger.error("Something went wrong, file is above 100MB, won't be saved")
    end

    g_resources.writeFileContents(file, result)
end

function loadData()
    if not isLoadedPlayerReady() then return end

    local file = "/characterdata/" .. LoadedPlayer:getId() .. "/sellAllWhitelist.json"
    if g_resources.fileExists(file) then
        local status, result = pcall(function()
            return json.decode(g_resources.readFileContents(file))
        end)
        if not status then
            return g_logger.error(
                "Error while reading profiles file. To fix this problem you can delete sellAllWhitelist.json. Details: " ..
                    result)
        end
        sellAllWhitelist = result or {}
    else
        sellAllWhitelist = {}
    end
end

function removeItemInList(clientId)
    if type(clientId) ~= "number" or not sellAllWhitelist then
        return
    end
    for k, v in pairs(sellAllWhitelist) do
        if v == clientId then
            table.remove(sellAllWhitelist, k)
            break
        end
    end
end

function inWhiteList(clientId)
    if not sellAllWhitelist then
        return false
    end
    return table.contains(sellAllWhitelist, clientId or 0)
end

function addToWhitelist(clientId)
    if type(clientId) ~= "number" then
        return
    end
    if table.contains(sellAllWhitelist, clientId) then
        return
    end
    table.insert(sellAllWhitelist, clientId)
end

local function getItemIdAndSubtype(item)
    if type(item) == 'number' then
        return item, 0
    end
    if not item then
        return nil, nil
    end
    if item.itemId then
        return item.itemId, item.displayCot or item.subType or 0
    end
    if item.ptr then
        item = item.ptr
    end
    local ok, id, subtype = pcall(function()
        return item:getId(), item:getSubType()
    end)
    if ok then
        return id, subtype
    end
    return nil, nil
end

local function findTradeEntry(item, list)
    if item and item.ptr then
        return item
    end

    local id, subtype = getItemIdAndSubtype(item)
    if not id then
        return nil
    end

    for _, entry in ipairs(list or {}) do
        if entry.ptr and entry.ptr:getId() == id then
            local entrySubtype = entry.ptr:getSubType()
            if not subtype or subtype == 0 or entrySubtype == subtype then
                return entry
            end
        elseif entry.itemId == id then
            return entry
        end
    end
    return nil
end

local function isNewNpcDialogActive()
    return controllerNpcTrader and controllerNpcTrader.useNewNpcDialog and controllerNpcTrader:useNewNpcDialog()
end

function isTrading()
    return controllerNpcTrader and controllerNpcTrader.isTradeOpen == true
end

function getSellItems()
    if isNewNpcDialogActive() then
        return controllerNpcTrader.sellItems or {}
    end
    local legacy = controllerNpcTrader and controllerNpcTrader.legacyTradeItems
    return (legacy and legacy[controllerNpcTrader.SELL]) or controllerNpcTrader.sellItems or {}
end

function getBuyItems()
    if isNewNpcDialogActive() then
        return controllerNpcTrader.buyItems or {}
    end
    local legacy = controllerNpcTrader and controllerNpcTrader.legacyTradeItems
    return (legacy and legacy[controllerNpcTrader.BUY]) or controllerNpcTrader.buyItems or {}
end

function getSellQuantity(item)
    if not controllerNpcTrader then
        return 0
    end
    if isNewNpcDialogActive() then
        if type(item) == 'number' then
            item = Item.create(item)
        end
        return controllerNpcTrader:getSellQuantity(item)
    end

    local id = getItemIdAndSubtype(item)
    if id and getSellQuantityFromItemId then
        return getSellQuantityFromItemId(id)
    end
    return 0
end

local function canTradeNewEntry(entry)
    if not entry or not controllerNpcTrader then
        return false
    end
    if controllerNpcTrader.tradeMode == controllerNpcTrader.SELL then
        return controllerNpcTrader:getSellQuantity(entry.ptr) > 0
    end

    local player = g_game.getLocalPlayer()
    local freeCapacity = player and player.getFreeCapacity and player:getFreeCapacity() or 0
    local hasCapacity = controllerNpcTrader.ignoreCapacity or freeCapacity >= (entry.weight or 0)
    local hasMoney = controllerNpcTrader:getPlayerMoney() >= (entry.price or 0)
    return hasCapacity and hasMoney
end

function canTradeItem(item)
    if isNewNpcDialogActive() then
        local list = controllerNpcTrader.tradeMode == controllerNpcTrader.SELL and controllerNpcTrader.sellItems or
            controllerNpcTrader.buyItems
        return canTradeNewEntry(findTradeEntry(item, list))
    end
    if legacyCanTradeItem then
        return legacyCanTradeItem(item)
    end
    return false
end

local function getSellPacketMaxAmount()
    if g_game.getFeature(GameDoubleShopSellAmount) then
        return controllerNpcTrader.MAX_AMOUNT_STACKABLE or 10000
    end
    return controllerNpcTrader.MAX_AMOUNT_NORMAL or 100
end

function sellAll(delayed, exceptions)
    if type(delayed) == "table" then
        exceptions = delayed
        delayed = false
    end
    exceptions = exceptions or {}

    if not isNewNpcDialogActive() then
        if legacySellAll then
            return legacySellAll(delayed, exceptions)
        end
        if controllerNpcTrader and controllerNpcTrader.sellAllLegacy then
            return controllerNpcTrader:sellAllLegacy(delayed, exceptions)
        end
        return
    end

    if controllerNpcTrader.sellAllWithDelayEvent then
        removeEvent(controllerNpcTrader.sellAllWithDelayEvent)
        controllerNpcTrader.sellAllWithDelayEvent = nil
    end

    local queue = {}
    for _, entry in ipairs(controllerNpcTrader.sellItems or {}) do
        local id = entry.ptr and entry.ptr:getId()
        if id and not table.find(exceptions, id) then
            local amount = controllerNpcTrader:getSellQuantity(entry.ptr)
            while amount > 0 do
                local packetAmount = math.min(amount, getSellPacketMaxAmount())
                if delayed then
                    g_game.sellItem(entry.ptr, packetAmount, controllerNpcTrader.ignoreEquipped)
                    controllerNpcTrader.sellAllWithDelayEvent = scheduleEvent(function()
                        sellAll(true, exceptions)
                    end, 1100)
                    return
                end
                table.insert(queue, { entry.ptr, packetAmount, controllerNpcTrader.ignoreEquipped })
                amount = amount - packetAmount
            end
        end
    end

    for _, entry in ipairs(queue) do
        g_game.sellItem(entry[1], entry[2], entry[3])
    end
end

function closeNpcTrade()
    if isNewNpcDialogActive() then
        return controllerNpcTrader:onCloseNpcTrade()
    end
    if legacyCloseNpcTrade then
        return legacyCloseNpcTrade()
    end
    if g_game then
        return g_game.closeNpcTrade()
    end
end

function controllerNpcTrader:syncPublicWidgets()
    local window = self.ui
    if (not window or window:isDestroyed()) and self.legacyWindow and not self.legacyWindow:isDestroyed() then
        window = self.legacyWindow
    end

    if not window or window:isDestroyed() then
        npcWindow = nil
        searchText = nil
        amountText = nil
        return
    end

    npcWindow = window
    if window.recursiveGetChildById then
        searchText = window:recursiveGetChildById("searchText") or window:recursiveGetChildById("tradeSearchInput")
        amountText = window:recursiveGetChildById("tradeAmountInput") or window:recursiveGetChildById("amountInput") or
            window:recursiveGetChildById("quantityEdit")
    end
    if (not searchText or searchText:isDestroyed()) and self.findWidget then
        searchText = self:findWidget(".tradeSearchInput")
    end
end

function toggleNPCFocus(visible)
    if not visible and controllerNpcTrader and controllerNpcTrader.releaseNpcTextInput then
        controllerNpcTrader:releaseNpcTextInput()
    end

    local window = controllerNpcTrader and (controllerNpcTrader.ui or controllerNpcTrader.legacyWindow)
    if not window or window:isDestroyed() then
        return
    end
    if visible then
        if window.setBorderWidth then window:setBorderWidth(2) end
        if window.setBorderColor then window:setBorderColor('white') end
        local lockedInput = controllerNpcTrader and controllerNpcTrader._npcInputLockWidget
        if not lockedInput and window.focus then window:focus() end
    else
        if window.setBorderWidth then window:setBorderWidth(0) end
    end
end

function onTypeFieldsHover(widget, hovered)
    toggleNPCFocus(hovered)
    return true
end
