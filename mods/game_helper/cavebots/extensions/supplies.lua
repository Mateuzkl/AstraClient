-- CaveBot Supplies Extension
-- Handles supply checking, buying and tracking

CaveBot = CaveBot or {}
CaveBot.Extensions = CaveBot.Extensions or {}
CaveBot.Extensions.supplies = {}

local supplies = CaveBot.Extensions.supplies

-- Get supply data from hunting_recorder
local function getSupplyData()
    if not modules.game_helper or not modules.game_helper.hunting_recorderModule then
        return nil, nil
    end

    local recorderModule = modules.game_helper.hunting_recorderModule
    if not recorderModule.getCurrentCavebotData then
        return nil, nil
    end

    local cavebotData = recorderModule.getCurrentCavebotData()
    if not cavebotData then
        return nil, nil
    end

    local supplyItems = cavebotData.supplies or {}
    local supplySettings = cavebotData.supplySettings or {}

    return supplyItems, supplySettings
end

-- Get item count in inventory/backpacks
local function getItemCount(itemId)
    if modules.game_helper and modules.game_helper.getItemCountAnywhere then
        return modules.game_helper.getItemCountAnywhere(itemId)
    end

    -- Fallback
    local item = g_game.findPlayerItem(itemId, -1)
    return item and item:getCount() or 0
end

-- Check if a single supply is OK (current >= min; used by check_supply waypoint)
supplies.checkSupply = function(index)
    local supplyItems, supplySettings = getSupplyData()
    if not supplyItems then return true end

    local itemId = supplyItems[index] or 0
    if itemId == 0 then return true end -- No item configured = OK

    local settings = supplySettings[index] or {minSupply = 0, buySupply = 1}
    local minRequired = settings.minSupply or 0

    local currentCount = getItemCount(itemId)
    return currentCount >= minRequired
end

-- Check all supplies (returns true if all OK: current >= min for each supply; used by check_supply waypoint)
supplies.checkAllSupplies = function()
    local supplyItems, supplySettings = getSupplyData()
    if not supplyItems then return true end

    for i = 1, 10 do
        local itemId = supplyItems[i] or 0
        if itemId > 0 then
            local settings = supplySettings[i] or {minSupply = 0, buySupply = 1}
            local minRequired = settings.minSupply or 0

            local currentCount = getItemCount(itemId)
            if currentCount < minRequired then
                return false
            end
        end
    end

    return true
end

-- Get list of supplies that need restocking
supplies.getSuppliesNeeded = function()
    local supplyItems, supplySettings = getSupplyData()
    if not supplyItems then
        return {}
    end

    local needed = {}

    for i = 1, 10 do
        local itemId = supplyItems[i] or 0
        if itemId > 0 then
            local settings = supplySettings[i] or {minSupply = 0, buySupply = 1}
            local buyAmount = settings.buySupply or 1
            local currentCount = getItemCount(itemId)

            if buyAmount > 1 then
                if currentCount < buyAmount then
                    table.insert(needed, {
                        index = i,
                        itemId = itemId,
                        current = currentCount,
                        minimum = buyAmount,
                        buyAmount = buyAmount - currentCount
                    })
                end
            end
        end
    end

    return needed
end

-- Buy a single supply from NPC trade window
supplies.buySupply = function(itemId, amount)
    -- Access buy items via modules.game_npctrade.getBuyItems()
    local buyItems = nil
    if modules and modules.game_npctrade and modules.game_npctrade.getBuyItems then
        buyItems = modules.game_npctrade.getBuyItems()
    end

    if not buyItems then
        return false
    end

    if #buyItems == 0 then
        return false
    end

    for _, item in ipairs(buyItems) do
        if item.ptr and item.ptr:getId() == itemId then
            local price = item.price or 0
            local player = g_game.getLocalPlayer()
            if not player then return false end

            local money = 0
            if player.getMoney then
                money = player:getMoney()
            elseif player.getCapacity then
                -- Alternative: count gold coins manually
                local goldCoin = g_game.findPlayerItem(3031, -1)
                local platinumCoin = g_game.findPlayerItem(3035, -1)
                local crystalCoin = g_game.findPlayerItem(3043, -1)
                money = (goldCoin and goldCoin:getCount() or 0) +
                        (platinumCoin and platinumCoin:getCount() or 0) * 100 +
                        (crystalCoin and crystalCoin:getCount() or 0) * 10000
            end

            -- Calculate how many we can buy.
            -- Non-stackable items (SSA, might ring, etc.) are capped at 100 per buy by the server;
            -- stackable items can go up to 2000. The retry loop will refill what's still missing.
            local isStackable = item.ptr.isStackable and item.ptr:isStackable()
            local perBuyCap = isStackable and 2000 or 100
            local canBuy = math.min(amount, perBuyCap)
            if price > 0 and money > 0 then
                local maxAffordable = math.floor(money / price)
                canBuy = math.min(canBuy, maxAffordable)
            end

            if canBuy > 0 then
                g_game.buyItem(item.ptr, canBuy, false, false)
                if CaveBot and CaveBot.log then
                    local itemName = (item.ptr.getMarketName and item.ptr:getMarketName())
                        or (item.ptr.getName and item.ptr:getName())
                        or ("item " .. tostring(itemId))
                    CaveBot.log(string.format("Bought %dx %s (id %d)", canBuy, itemName, itemId), "action")
                end
                return true, canBuy
            end

            return false
        end
    end

    return false
end

-- Buy all supplies that are needed (call repeatedly until returns false)
supplies.buyAllSupplies = function()
    local needed = supplies.getSuppliesNeeded()
    if #needed == 0 then
        return false
    end

    -- Buy the first supply in the list
    local supply = needed[1]
    local bought = supplies.buySupply(supply.itemId, supply.buyAmount)

    if bought then
        return true -- Return true to indicate we're still buying
    end

    -- If we couldn't buy this supply, try the next one
    if #needed > 1 then
        for i = 2, #needed do
            supply = needed[i]
            bought = supplies.buySupply(supply.itemId, supply.buyAmount)
            if bought then
                return true
            end
        end
    end

    return false -- Nothing left to buy
end

-- Get supply status for display
supplies.getStatus = function()
    local supplyItems, supplySettings = getSupplyData()
    if not supplyItems then return {} end

    local status = {}

    for i = 1, 10 do
        local itemId = supplyItems[i] or 0
        if itemId > 0 then
            local settings = supplySettings[i] or {minSupply = 0, buySupply = 1}
            local currentCount = getItemCount(itemId)
            local minRequired = settings.minSupply or 0

            table.insert(status, {
                index = i,
                itemId = itemId,
                current = currentCount,
                minimum = minRequired,
                buyAmount = settings.buySupply or 1,
                ok = minRequired == 0 or currentCount >= minRequired
            })
        end
    end

    return status
end

return supplies
