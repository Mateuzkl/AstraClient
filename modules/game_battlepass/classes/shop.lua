BattlePassShop = BattlePassShop or {}

local shopGrid
local shopPoints = 0
local shopUnlocked = false
local confirmBox

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

    local pointsLabel = BattlePass.window:recursiveGetChildById('battlePassShopPoints')
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

local function createCard(raw)
    if not shopGrid then
        return
    end

    local card = g_ui.createWidget('BattlePassShopCard', shopGrid)
    if not card then
        return
    end

    local title = card:recursiveGetChildById('cardTitle')
    if title then title:setText(raw.title or '') end

    local description = card:recursiveGetChildById('cardDescription')
    if description then description:setText(raw.description or '') end

    local price = card:recursiveGetChildById('cardPrice')
    if price then price:setText(comma_value(raw.price or 0) .. ' BP') end

    local creature = card:recursiveGetChildById('creaturePreview')
    local item = card:recursiveGetChildById('itemPreview')
    if raw.previewType == 1 and raw.itemId > 0 and item then
        item:setItemId(raw.itemId)
        item:setVisible(true)
    elseif (raw.previewType == 2 or raw.previewType == 3) and creature then
        setCreaturePreview(creature, raw.lookType, raw.addons)
    end

    local buyButton = card:recursiveGetChildById('buyButton')
    local boughtLabel = card:recursiveGetChildById('boughtLabel')
    if raw.purchased then
        if buyButton then
            buyButton:setVisible(false)
            buyButton:setEnabled(false)
        end
        if boughtLabel then
            boughtLabel:setVisible(true)
        end
    elseif buyButton then
        buyButton:setEnabled(shopUnlocked and shopPoints >= raw.price)
        buyButton.onClick = function()
            closeConfirmBox()
            local function confirmPurchase()
                BattlePass.sendToServer('buyShop', { shopId = raw.id })
                closeConfirmBox()
            end
            confirmBox = displayGeneralBox(
                tr('Confirm Purchase'),
                tr("Do you want to buy '%s' for %s Battle Pass points?", raw.title, comma_value(raw.price)),
                { { text = tr('Yes'), callback = confirmPurchase }, { text = tr('Cancel'), callback = closeConfirmBox } },
                confirmPurchase,
                closeConfirmBox,
                BattlePass.window
            )
        end
    end

    card.shopPrice = raw.price or 0
    card.shopPurchased = raw.purchased == true
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
