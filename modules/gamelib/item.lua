function Item:setInCorpse(value)
	self.isInCorpse = value
end

function Item:inCorpse()
	return self.isInCorpse
end

if not Item._serverDetailsWrapped then
    Item._nativeGetDescription = Item.getDescription
    Item._nativeGetNPCSaleData = Item.getNPCSaleData
    Item._nativeGetAverageMarketValue = Item.getAverageMarketValue
    Item._nativeGetDefaultValue = Item.getDefaultValue
    Item._nativeGetDefaultBuyPrice = Item.getDefaultBuyPrice
    Item._serverDetailsWrapped = true
end

local function getServerItemDetails(item)
    if not item or not item.getId or not ItemsDatabase or not ItemsDatabase.getServerItemDetails then
        return nil
    end

    local ok, itemId = pcall(function()
        return item:getId()
    end)
    if not ok then
        return nil
    end

    return ItemsDatabase.getServerItemDetails(itemId)
end

local function getNpcPrices(item)
    if not item or not item.getNPCSaleData then
        return 0, 0
    end

    local ok, npcData = pcall(function()
        return item:getNPCSaleData()
    end)

    if not ok or type(npcData) ~= 'table' then
        return 0, 0
    end

    local bestBuyPrice = 0
    local bestSellPrice = 0
    for _, offer in pairs(npcData) do
        if type(offer) == 'table' then
            local buyPrice = tonumber(offer.buyPrice or offer.buy or offer.itemBuyPrice) or 0
            local sellPrice = tonumber(offer.salePrice or offer.sellPrice or offer.sell or offer.itemSellPrice) or 0
            bestBuyPrice = math.max(bestBuyPrice, buyPrice)
            bestSellPrice = math.max(bestSellPrice, sellPrice)
        end
    end

    return bestSellPrice, bestBuyPrice
end

function Item:getDescription(...)
    local details = getServerItemDetails(self)
    if details then
        if details.description and details.description ~= "" then
            return details.description
        end
        if type(details.descriptions) == 'table' and details.descriptions[1] then
            return details.descriptions[1].description or ""
        end
    end

    if Item._nativeGetDescription then
        local ok, value = pcall(Item._nativeGetDescription, self, ...)
        if ok then
            return value or ""
        end
    end
    return ""
end

function Item:getNPCSaleData()
    local details = getServerItemDetails(self)
    if details and type(details.npcSaleData) == 'table' and #details.npcSaleData > 0 then
        return details.npcSaleData
    end

    if Item._nativeGetNPCSaleData then
        local ok, data = pcall(Item._nativeGetNPCSaleData, self)
        if ok and type(data) == 'table' then
            return data
        end
    end
    return {}
end

function Item:getAverageMarketValue()
    local details = getServerItemDetails(self)
    local value = details and tonumber(details.averageMarketValue) or 0
    if value and value > 0 then
        return value
    end

    if Item._nativeGetAverageMarketValue then
        local ok, nativeValue = pcall(Item._nativeGetAverageMarketValue, self)
        if ok then
            return tonumber(nativeValue) or 0
        end
    end
    return 0
end

function Item:getDefaultValue()
    local details = getServerItemDetails(self)
    local value = details and tonumber(details.defaultValue) or 0
    if value and value > 0 then
        return value
    end

    if Item._nativeGetDefaultValue then
        local ok, nativeValue = pcall(Item._nativeGetDefaultValue, self)
        if ok and tonumber(nativeValue) and tonumber(nativeValue) > 0 then
            return tonumber(nativeValue)
        end
    end

    local sellPrice, buyPrice = getNpcPrices(self)
    return sellPrice > 0 and sellPrice or buyPrice
end

function Item:getDefaultBuyPrice()
    local details = getServerItemDetails(self)
    local value = details and tonumber(details.defaultBuyPrice) or 0
    if value and value > 0 then
        return value
    end

    if Item._nativeGetDefaultBuyPrice then
        local ok, nativeValue = pcall(Item._nativeGetDefaultBuyPrice, self)
        if ok and tonumber(nativeValue) and tonumber(nativeValue) > 0 then
            return tonumber(nativeValue)
        end
    end

    local _, buyPrice = getNpcPrices(self)
    return buyPrice
end

Item.getPriceValue = Item.getPriceValue or function(self)
    local prices = Analyzer and Analyzer.analyzers and Analyzer.analyzers.customPrices or {}
    return prices[tostring(self:getId())] or prices[self:getId()] or self:getDefaultValue()
end

Item.isAmmo = Item.isAmmo or function(self)
    local id = self:getId()
    if not id or id == 0 then
        return false
    end
    local itemType = g_things.findItemTypeByClientId(id)
    if not itemType or not itemType.getCategory then
        return false
    end
    local ok, category = pcall(function() return itemType:getCategory() end)
    return ok and category == 4 or false
end

Item.hasWearout = Item.hasWearout or Item.hasWearOut or function(self)
    return false
end

Item.hasWearOut = Item.hasWearOut or Item.hasWearout

Item.hasClockExpire = Item.hasClockExpire or function(self)
    return false
end

Item.hasExpire = Item.hasExpire or function(self)
    return false
end

Item.hasExpireStop = Item.hasExpireStop or function(self)
    return false
end

Item.hasCharges = Item.hasCharges or function(self)
    return self:getSubType() > 0
end

function getItemServerName(itemId)
    itemId = tonumber(itemId) or 0
    if itemId <= 0 then
        return ""
    end

    if ItemsDatabase and ItemsDatabase.getServerItemDetails then
        local details = ItemsDatabase.getServerItemDetails(itemId)
        if type(details) == "table" and type(details.name) == "string" and details.name ~= "" then
            return string.capitalize(details.name)
        end
    end

    local thing = g_things.getThingType(itemId, ThingCategoryItem)
    if not thing then
        return ""
    end

    local moneyNames = {
      [3031] = "gold coin",
      [3035] = "platinum coin",
      [3043] = "crystal coin"
    }

    if moneyNames[itemId] then
      return string.capitalize(moneyNames[itemId])
    end

    local marketData = thing:getMarketData()
    local name = marketData and marketData.name or ""
    if (not name or name == "") and thing.getName then
      name = thing:getName()
    end

    return string.capitalize(name or "") or ""
end

function getItemCategory(itemId)
    local thing = g_things.getThingType(itemId, ThingCategoryItem)
    if not thing then
        return 0
    end

    return thing:getMarketData().category or 0
end

function getItemCategoryBySlot(itemId)
    local thing = g_things.getThingType(itemId, ThingCategoryItem)
    if not thing then
        return -1
    end

    local category = thing:getMarketData().category
    if not category then
        return -1
    end

    local leftHand = {MarketCategory.Axes, Clubs, DistanceWeapons, Swords, WandsRods}
    if category == MarketCategory.HelmetsHats then
        return CONST_SLOT_HEAD
    elseif category == MarketCategory.Armors then
        return CONST_SLOT_ARMOR
    elseif category == MarketCategory.Legs then
        return CONST_SLOT_LEGS
    elseif category == MarketCategory.Boots then
        return CONST_SLOT_FEET
    elseif category >= MarketCategory.Axes and category <= MarketCategory.WandsRods or category == MarketCategory.FistWeapons then
        return CONST_SLOT_LEFT
    end

    return -1
end

function isCorpse(itemId)
    local thing = g_things.getThingType(itemId, ThingCategoryItem)
    if not thing then
        return false
    end

    local corpse = false
    if thing.isCorpse then
        corpse = thing:isCorpse()
    elseif thing.isLyingCorpse then
        corpse = thing:isLyingCorpse()
    end

    local playerCorpse = false
    if thing.isPlayerCorpse then
        playerCorpse = thing:isPlayerCorpse()
    end

    return corpse and not playerCorpse
end

function getItemColor(itemId)
    if ItemsDatabase and ItemsDatabase.getItemColor then
        return ItemsDatabase.getItemColor(itemId)
    end

    local item = Item.create(itemId, 1)
    if not item then
        return "#F0F0F0"
    end

    local value = item:getPriceValue()
    if value >= 1000000 then
        return "#F0F000"
    elseif value >= 100000 then
        return "#FF68FF"
    elseif value >= 10000 then
        return "#20A0FF"
    elseif value >= 1000 then
        return "#00F000"
    elseif value >= 1 then
        return "#AAAAAA"
    end

    return "#F0F0F0"
end
