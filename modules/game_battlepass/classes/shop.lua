BattlePassShop = BattlePassShop or {}

local shopGrid
local shopPoints = 0
local shopUnlocked = false
local confirmBox

local typeBackdrops = {
    item = '/images/game/task_hunt/backdrop_huntingtaskpoint_shop_decoration',
    [1] = '/images/game/task_hunt/backdrop_huntingtaskpoint_shop_decoration',
    mount = '/images/game/task_hunt/backdrop_huntingtaskpoint_shop_Mount',
    [3] = '/images/game/task_hunt/backdrop_huntingtaskpoint_shop_Mount',
    outfit = '/images/game/task_hunt/backdrop_huntingtaskpoint_shop_outfit',
    [2] = '/images/game/task_hunt/backdrop_huntingtaskpoint_shop_outfit',
    prey = '/images/game/task_hunt/backdrop_huntingtaskpoint_shop_boost',
    charms = '/images/game/task_hunt/backdrop_huntingtaskpoint_shop_boost',
}

local function closeConfirmBox()
    if confirmBox then
        confirmBox:destroy()
        confirmBox = nil
    end
end

local function updateHeader()
    if not BattlePass.window then
        return
    end

    local pointsPanel = BattlePass.window:recursiveGetChildById('battlePassShopPointsPanel')
    local pointsLabel = pointsPanel and pointsPanel:recursiveGetChildById('panelLabel')
    if pointsLabel then
        pointsLabel:setText(comma_value(shopPoints))
    end

    local statusLabel = BattlePass.window:recursiveGetChildById('battlePassShopStatus')
    if statusLabel then
        if shopUnlocked then
            statusLabel:setText(tr('Complete daily missions to earn shop points until the season ends.'))
        else
            statusLabel:setText(tr('Complete Battle Pass level 80 to unlock shop points.'))
        end
    end
end

local function setCreaturePreview(widget, lookType, addons)
    if not widget or lookType <= 0 then
        return false
    end

    local ok = pcall(function()
        local creature = Creature.create()
        creature:setOutfit({
            type = lookType,
            head = 0,
            body = 0,
            legs = 0,
            feet = 0,
            addons = addons or 0,
        })
        creature:setDirection(East)
        widget:setCreature(creature)
        widget:setVisible(true)
    end)
    return ok
end

local function updateCardButtons()
    if not shopGrid then
        return
    end

    for i = 1, shopGrid:getChildCount() do
        local card = shopGrid:getChildByIndex(i)
        local buyButton = card and card:recursiveGetChildById('buyButton')
        if buyButton and (not card.shopPurchased or card.shopRepeatable) then
            buyButton:setEnabled(shopUnlocked and shopPoints >= (card.shopPrice or 0))
        end
    end
end

local function createCard(raw)
    if not shopGrid then
        return
    end

    local priceValue = tonumber(raw.price) or 0
    local card = g_ui.createWidget('BattlePassShopCard', shopGrid)
    if not card then
        return
    end

    card:setText(raw.title or '')

    local description = card:recursiveGetChildById('cardDescription')
    if description then description:setText(raw.description or '') end

    local price = card:recursiveGetChildById('panelLabel')
    if price then price:setText(comma_value(priceValue)) end

    local creature = card:recursiveGetChildById('creaturePreview')
    local item = card:recursiveGetChildById('itemPreview')
    local previewType = tonumber(raw.previewType) or 0
    local itemId = tonumber(raw.itemId) or 0
    local lookType = tonumber(raw.lookType) or 0
    local addons = tonumber(raw.addons) or 0
    if previewType == 1 and itemId > 0 and item then
        item:setItemId(itemId)
        item:setVisible(true)
    elseif (previewType == 2 or previewType == 3) and creature then
        setCreaturePreview(creature, lookType, addons)
    end

    local buyButton = card:recursiveGetChildById('buyButton')
    local boughtButton = card:recursiveGetChildById('boughtButton')
    if raw.purchased and not raw.repeatable then
        if buyButton then
            buyButton:setVisible(false)
            buyButton:setEnabled(false)
        end
        if boughtButton then
            boughtButton:setVisible(true)
        end
    else
        if buyButton then
            buyButton:setVisible(true)
            buyButton:setEnabled(shopUnlocked and shopPoints >= priceValue)
            buyButton.onClick = function()
                closeConfirmBox()
                local function confirmPurchase()
                    BattlePass.sendToServer('buyShop', { shopId = raw.id })
                    closeConfirmBox()
                end
                confirmBox = displayGeneralBox(
                    tr('Confirm Purchase'),
                    tr("Do you want to buy '%s' for %s Battle Pass points?", raw.title, comma_value(priceValue)),
                    { { text = tr('Yes'), callback = confirmPurchase }, { text = tr('Cancel'), callback = closeConfirmBox } },
                    confirmPurchase,
                    closeConfirmBox,
                    BattlePass.window
                )
            end
        end
        if boughtButton then boughtButton:setVisible(false) end
    end

    local backdrop = card:recursiveGetChildById('typeBackdrop')
    local rawType = raw.type
    if rawType == nil or rawType == '' then
        rawType = raw.previewType
    end
    if type(rawType) == 'string' then
        rawType = rawType:lower()
    end
    if backdrop and typeBackdrops[rawType] then
        backdrop:setImageSource(typeBackdrops[rawType])
    end

    card.shopPrice = priceValue
    card.shopPurchased = raw.purchased == true
    card.shopRepeatable = raw.repeatable == true
end

function BattlePassShop.init(panel)
    shopGrid = panel and panel:recursiveGetChildById('battlePassShopGrid') or nil
end

function BattlePassShop.onShopData(data)
    shopPoints = tonumber(data and data.shopPoints) or 0
    shopUnlocked = data and data.unlocked == true or false
    updateHeader()

    if not shopGrid then
        return
    end
    shopGrid:destroyChildren()
    for _, raw in ipairs(data and data.entries or {}) do
        createCard(raw)
    end
end

function BattlePassShop.updateBalance(points, unlocked)
    if points ~= nil then
        shopPoints = tonumber(points) or 0
    end
    if unlocked ~= nil then
        shopUnlocked = unlocked == true
    end
    updateHeader()
    updateCardButtons()
end

function BattlePassShop.requestRefresh()
    BattlePass.sendToServer('getShop')
end

function BattlePassShop.reset()
    closeConfirmBox()
    shopPoints = 0
    shopUnlocked = false
    if shopGrid then
        shopGrid:destroyChildren()
    end
    updateHeader()
end

function BattlePassShop.terminate()
    BattlePassShop.reset()
    shopGrid = nil
end
