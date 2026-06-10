TaskShop = {}

local shopGrid = nil
local shopData = {}
local confirmBox = nil

local bonusTypeImages = {
    ["wheel_of_destiny_points"] = '/images/game/task_hunt/icon_tasksystem_promotionpoint'
}

function TaskShop.requestRefresh()
    g_game.taskHuntingShopRequest()
end

function TaskShop.init(shopPanel)
    if not shopPanel then return end
    shopGrid = shopPanel:recursiveGetChildById('shopGrid')
end

function TaskShop.onShopData(items)
    local oldData = shopData
    shopData = items or {}

    if not shopGrid or #oldData ~= #shopData or shopGrid:getChildCount() ~= #shopData then
        TaskShop.rebuild()
        return
    end

    for i, raw in ipairs(shopData) do
        local card = shopGrid:getChildByIndex(i)
        if not card or card.shopId ~= (tonumber(raw.id) or 0) then
            TaskShop.rebuild()
            return
        end
    end

    TaskShop.updateCards()
end

function TaskShop.onShopResult(itemId, result)
    -- Native protocol: server sends full shop data refresh after purchase.
    -- This function is kept as a no-op stub for compatibility.
    -- Error display is handled by the server sending updated shop data
    -- where the item's "bought" status reflects the result.
end

function TaskShop.rebuild()
    if not shopGrid then return end
    shopGrid:destroyChildren()

    for _, raw in ipairs(shopData) do
        local data = TaskShop.parseItem(raw)
        TaskShop.createCard(shopGrid, data)
    end
end

function TaskShop.updateCards()
    if not shopGrid then return end

    for i, raw in ipairs(shopData) do
        local card = shopGrid:getChildByIndex(i)
        if not card then break end

        local data = TaskShop.parseItem(raw)

        local descLabel = card:recursiveGetChildById('cardDescription')
        if descLabel then descLabel:setText(data.description) end

        local priceLabel = card:recursiveGetChildById('panelLabel')
        if priceLabel then priceLabel:setText(comma_value(data.price)) end

        local buyBtn = card:recursiveGetChildById('buyButton')
        local boughtBtn = card:recursiveGetChildById('boughtButton')

        if data.bought and not card.shopBought then
            if buyBtn then
                buyBtn:setVisible(false)
                buyBtn:setEnabled(false)
                buyBtn.onClick = nil
            end
            if boughtBtn then boughtBtn:setVisible(true) end
        end

        card.shopId = data.id
        card.shopPrice = data.price
        card.shopBought = data.bought
    end
end

function TaskShop.parseItem(raw)
    local data = {
        id = tonumber(raw.id) or 0,
        title = raw.title or "",
        description = raw.description or "",
        price = tonumber(raw.price) or 0,
        bought = (raw.bought == "1"),
        type = raw.type or "Decoration"
    }

    if data.type == "Outfit" then
        data.outfit = {
            lookType = tonumber(raw.lookType) or 0,
            lookHead = tonumber(raw.lookHead) or 0,
            lookBody = tonumber(raw.lookBody) or 0,
            lookLegs = tonumber(raw.lookLegs) or 0,
            lookFeet = tonumber(raw.lookFeet) or 0,
            lookAddons = tonumber(raw.lookAddons) or 0
        }
    elseif data.type == "Mount" then
        data.outfit = {
            lookType = tonumber(raw.lookType) or 0,
            lookHead = 0,
            lookBody = 0,
            lookLegs = 0,
            lookFeet = 0
        }
    elseif data.type == "Decoration" then
        data.clientId = tonumber(raw.clientId) or tonumber(raw.itemId) or 0
        data.itemId = data.clientId
    elseif data.type == "Bonus" then
        data.bonusType = raw.bonusType or ""
        data.imageSource = bonusTypeImages[data.bonusType] or ""
        data.maxPurchases = tonumber(raw.maxPurchases) or 0
        data.currentPurchases = tonumber(raw.currentPurchases) or 0
        data.nextCost = tonumber(raw.nextCost) or 0
        data.price = data.nextCost
        data.description = data.description ..
            "\nAlready purchased " .. data.currentPurchases .. " / " .. data.maxPurchases
    end

    return data
end

local typeBackdrops = {
    ["Outfit"] = '/images/game/task_hunt/backdrop_huntingtaskpoint_shop_outfit',
    ["Mount"] = '/images/game/task_hunt/backdrop_huntingtaskpoint_shop_Mount',
    ["Decoration"] = '/images/game/task_hunt/backdrop_huntingtaskpoint_shop_decoration',
    ["Bonus"] = '/images/game/task_hunt/backdrop_huntingtaskpoint_shop_boost'
}

function TaskShop.createCard(parent, data)
    local card = g_ui.createWidget('ShopItemCard', parent)
    if not card then return end

    card:setText(data.title)

    local descLabel = card:recursiveGetChildById('cardDescription')
    if descLabel then
        descLabel:setText(data.description)
    end

    local priceLabel = card:recursiveGetChildById('panelLabel')
    if priceLabel then
        priceLabel:setText(comma_value(data.price))
    end

    if data.bought then
        local buyBtn = card:recursiveGetChildById('buyButton')
        if buyBtn then
            buyBtn:setVisible(false)
            buyBtn:setEnabled(false)
        end
        local boughtBtn = card:recursiveGetChildById('boughtButton')
        if boughtBtn then boughtBtn:setVisible(true) end
    else
        local buyBtn = card:recursiveGetChildById('buyButton')
        if buyBtn then
            buyBtn.onClick = function()
                local message = tr("Do you really want to buy '%s' for %s Hunting Task Points?", data.title,
                    comma_value(data.price))
                local function yesCallback()
                    g_game.taskHuntingShopPurchase(data.id)
                    if confirmBox then
                        confirmBox:destroy()
                        confirmBox = nil
                    end
                end
                local function cancelCallback()
                    if confirmBox then
                        confirmBox:destroy()
                        confirmBox = nil
                    end
                end
                confirmBox = displayGeneralBox(tr('Confirm Purchase'), message,
                    { { text = tr('Yes'),  callback = yesCallback },
                        { text = tr('Cancel'), callback = cancelCallback } },
                    yesCallback, cancelCallback, taskHuntWindow)
            end
        end
    end

    -- Preview: Outfit or Item
    if data.outfit and (tonumber(data.outfit.lookType) or 0) > 0 then
        local creatureWidget = card:recursiveGetChildById('outfitCreature')
        if creatureWidget then
            pcall(function()
                local creature = Creature.create()
                creature:setOutfit({
                    type = data.outfit.lookType,
                    head = data.outfit.lookHead or 0,
                    body = data.outfit.lookBody or 0,
                    legs = data.outfit.lookLegs or 0,
                    feet = data.outfit.lookFeet or 0,
                    addons = data.outfit.lookAddons or 0
                })
                creature:setDirection(2)
                creatureWidget:setCreature(creature)
                creatureWidget:setVisible(true)
            end)
        end
    elseif data.imageSource and data.imageSource ~= "" then
        local iconWidget = card:recursiveGetChildById('iconDisplay')
        if iconWidget then
            iconWidget:setImageSource(data.imageSource)
            iconWidget:setVisible(true)
        end
    elseif data.itemId and data.itemId > 0 then
        local item = card:recursiveGetChildById('itemDisplay')
        if item then
            item:setItemId(data.itemId)
            item:setVisible(true)
        end
    end

    card.shopId = data.id
    card.shopPrice = data.price
    card.shopBought = data.bought

    local backdrop = card:recursiveGetChildById('typeBackdrop')
    if backdrop and typeBackdrops[data.type] then
        backdrop:setImageSource(typeBackdrops[data.type])
    end
end

function TaskShop.updateBalance(balance)
    if not shopGrid then return end
    for i = 1, shopGrid:getChildCount() do
        local card = shopGrid:getChildByIndex(i)
        if card and not card.shopBought then
            local buyBtn = card:recursiveGetChildById('buyButton')
            if buyBtn then
                buyBtn:setEnabled(balance >= (card.shopPrice or 0))
            end
        end
    end
end

function TaskShop.resetData()
    shopData = {}
end

function TaskShop.terminate()
    if confirmBox then
        confirmBox:destroy()
        confirmBox = nil
    end
    shopGrid = nil
    shopData = {}
end
