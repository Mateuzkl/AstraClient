if not Charm then
    Charm = {}
    Charm.__index = Charm
    Charm.resetPrice = 0
    Charm.data = {}
    Charm.emptySlots = 0
    Charm.selectedCharm = -1
    Charm.monsters = {}
    Charm.selectedType = "majorMenu"
    Charm.raceId = 0
    Charm.listConfig = {
        min = 0,
        max = 0,
        maxFitItems = 0,
        labelSize = 36,
        visibleLabel = 3,
        labels = {}
    }
    
end

local self = Charm

function Charm:reset()
    self.resetPrice = 0
    self.data = {}
    self.emptySlots = 0
    self.selectedCharm = -1
    self.monsters = {}
    self.raceId = 0

    self.selectedType = "majorMenu"
end

local constTexts = {
    [1] = "You can assign %d more Charms",
    [2] = 'You can assing %d more Charms to creatures.\nBuy a "Charm Expansion" to assing your unlocked Charms to\ncreatures nearly unlimitedly and to get 25%% discount whenever\nyou are removing a Charm.',
}

local askWindowText = {
    [0] = "Do you want to unlock the Charm %s? This will cost you %d %s?",
    [1] = "Do you want to upgrade the Charm %s? This will cost you %d %s?",
}

local MajorMenu = {
    [0] = {id = 0, name = "Wound", description = "Your attacks have a %d%% chance to deal physical damage equal to 5%% of the target's initial hit  points.", prices = {[0] = 240, [1] = 360, [2] = 1200, }, bonuses = {[0] = 5, [1] = 10, [2] = 11, }},
    [1] = {id = 1, name = "Enflame", description = "Your attacks have a %d%% chance to deal fire damage equal to 5%% of the target's initial hit  points.", prices = {[0] = 400, [1] = 600, [2] = 2000, }, bonuses = {[0] = 5, [1] = 10, [2] = 11, }},
    [2] = {id = 2, name = "Poison", description = "Your attacks have a %d%% chance to deal earth damage equal to 5%% of the target's initial hit  points.", prices = {[0] = 240, [1] = 360, [2] = 1200, }, bonuses = {[0] = 5, [1] = 10, [2] = 11, }},
    [3] = {id = 3, name = "Freeze", description = "Your attacks have a %d%% chance to deal ice damage equal to 5%% of the target's initial hit  points.", prices = {[0] = 320, [1] = 480, [2] = 1600, }, bonuses = {[0] = 5, [1] = 10, [2] = 11, }},
    [4] = {id = 4, name = "Zap", description = "Your attacks have a %d%% chance to deal energy damage equal to 5%% of the target's initial hit  points.", prices = {[0] = 320, [1] = 480, [2] = 1600, }, bonuses = {[0] = 5, [1] = 10, [2] = 11, }},
    [5] = {id = 5, name = "Curse", description = "Your attacks have a %d%% chance to deal death damage equal to 5%% of the target's initial hit  points.", prices = {[0] = 360, [1] = 540, [2] = 1800, }, bonuses = {[0] = 5, [1] = 10, [2] = 11, }},
    [7] = {id = 7, name = "Parry", description = "Each time you take damage, you have a %d%% chance to reflect it back to the aggressor.", prices = {[0] = 400, [1] = 600, [2] = 2000, }, bonuses = {[0] = 5, [1] = 10, [2] = 11, }},
    [8] = {id = 8, name = "Dodge", description = "Grants a %d%% chance to dodge an attack.", prices = {[0] = 240, [1] = 360, [2] = 1200, }, bonuses = {[0] = 5, [1] = 10, [2] = 11, }},
    [15] = {id = 15, name = "Low Blow", description = "Adds %d%% critical hit chance to attacks with critical hit weapons.", prices = {[0] = 800, [1] = 1200, [2] = 4000, }, bonuses = {[0] = 4, [1] = 8, [2] = 9, }},
    [16] = {id = 16, name = "Divine Wrath", description = "Your attacks have a %d%% chance to deal holy damage equal to 5%% of the target's initial hit  points.", prices = {[0] = 600, [1] = 900, [2] = 3000, }, bonuses = {[0] = 5, [1] = 10, [2] = 11, }},
    [19] = {id = 19, name = "Savage Blow", description = "Adds %d%% critical extra damage to attacks with critical hit weapons.", prices = {[0] = 800, [1] = 1200, [2] = 4000, }, bonuses = {[0] = 20, [1] = 40, [2] = 44, }},
    [22] = {id = 22, name = "Carnage", description = "Killing a monster has %d%% chance to deal physical damage equal to 15%% of its maximum health to all monsters in small radius.", prices = {[0] = 600, [1] = 900, [2] = 3000, }, bonuses = {[0] = 10, [1] = 20, [2] = 22, }},
    [23] = {id = 23, name = "Overpower", description = "Your attacks have a %d%% chance to deal damage equal to 5%% of your maximum health.", prices = {[0] = 600, [1] = 900, [2] = 3000, }, bonuses = {[0] = 5, [1] = 10, [2] = 11, }},
    [24] = {id = 24, name = "Overflux", description = "Your attacks have a %d%% chance to deal damage equal to 2.5%% of your maximum mana.", prices = {[0] = 600, [1] = 900, [2] = 3000, }, bonuses = {[0] = 5, [1] = 10, [2] = 11, }},
}

local MinorMenu = {
    [6] = {id = 6, name = "Cripple", description = "Your attacks have a %d%% chance to paralyse the target for 10 seconds.", prices = {[0] = 100, [1] = 150, [2] = 225, }, bonuses = {[0] = 6, [1] = 9, [2] = 12, }},
    [9] = {id = 9, name = "Adrenaline Burst", description = "Each time you're hit you have a %d%% chance to trigger a burst of adrenaline, boosting your speed by 150%% for 10 seconds.", prices = {[0] = 100, [1] = 150, [2] = 225, }, bonuses = {[0] = 6, [1] = 9, [2] = 12, }},
    [10] = {id = 10, name = "Numb", description = "After being attacked, you have a %d%% chance to paralyse the aggressor for 10 seconds.", prices = {[0] = 100, [1] = 150, [2] = 225, }, bonuses = {[0] = 6, [1] = 9, [2] = 12, }},
    [11] = {id = 11, name = "Cleanse", description = "Each time you're hit, you have a %d%% chance to cleanse one random negative status effect and gain temporary immunity to it for 11 seconds", prices = {[0] = 100, [1] = 150, [2] = 225, }, bonuses = {[0] = 6, [1] = 9, [2] = 12, }},
    [12] = {id = 12, name = "Bless", description = "Blesses you, reducing skill and experience loss by %d%% when killed by the chosen creature.", prices = {[0] = 100, [1] = 150, [2] = 225, }, bonuses = {[0] = 6, [1] = 9, [2] = 12, }},
    [13] = {id = 13, name = "Scavenge", description = "Increases your chance of successfully skinning/ dusting a skinnable/ dustable creature by %d%%.", prices = {[0] = 100, [1] = 150, [2] = 225, }, bonuses = {[0] = 60, [1] = 90, [2] = 120, }},
    [14] = {id = 14, name = "Gut", description = "Gutting the creature yiels %d%% more creature products.", prices = {[0] = 100, [1] = 150, [2] = 225, }, bonuses = {[0] = 6, [1] = 9, [2] = 12, }},
    [17] = {id = 17, name = "Vampiric Embrace", description = "Increases your current life leech by %.1f%%.", prices = {[0] = 100, [1] = 150, [2] = 225, }, bonuses = {[0] = 1.6, [1] = 2.4, [2] = 3.2, }},
    [18] = {id = 18, name = "Void's Call", description = "Increases your current mana leech by %.1f%%.", prices = {[0] = 100, [1] = 150, [2] = 225, }, bonuses = {[0] = 0.8, [1] = 1.2, [2] = 1.6, }},
    [20] = {id = 20, name = "Fatal Hold", description = "Your attacks have a %d%% chance to prevent creatures from fleeing due to low health for 30 seconds.", prices = {[0] = 100, [1] = 150, [2] = 225, }, bonuses = {[0] = 30, [1] = 45, [2] = 60, }},
    [21] = {id = 21, name = "Void Inversion", description = " %d%% chance to gain mana instead of losing it when taking mana drain damage.", prices = {[0] = 100, [1] = 150, [2] = 225, }, bonuses = {[0] = 20, [1] = 30, [2] = 40, }},
}

local function ensureCharmDefaults(menu)
    for _, charm in pairs(menu) do
        charm.level = charm.level or 0
        charm.creatureId = charm.creatureId or 0
        charm.removePrice = charm.removePrice or 0
    end
end

ensureCharmDefaults(MajorMenu)
ensureCharmDefaults(MinorMenu)

function Charm:setResetPanelVisibility(value)
    local resetContent = VisibleCyclopediaPanel:recursiveGetChildById('resetContent')
    resetContent:getChildById('resetText'):setVisible(value)
    resetContent:getChildById('openStore'):setVisible(value)
    resetContent:getChildById('infoHover'):setVisible(value)
end

function Charm:configureWidget(charm, charmList)
    local charmItem = g_ui.createWidget('CharmWidget', charmList)
    charmItem:setText(charm.name)
    charmItem:setId(charm.id)
    charmItem:recursiveGetChildById('charmImage'):setImageSource('/images/game/cyclopedia/monster-bonus-effects/monster-bonus-effects-' .. charm.id)
    charmItem:recursiveGetChildById('charmImage'):setTooltip(string.todivide(charm.name .. ": " .. string.format(charm.description, charm.bonuses[math.max(0, charm.level - 1)]), 10))

    local raceId = charm.creatureId
    if raceId ~= 0 then
        local monster = getCyclopediaMonster(raceId)
        if monster then
            charmItem:recursiveGetChildById('creature'):setOutfit({type = monster[2], auxType = monster[3], head = monster[4], body = monster[5], legs = monster[6], feet = monster[7], addons = monster[8]})
        end
    end
    return charmItem
end

function Charm:configureCharmPanel()
    local charmList = VisibleCyclopediaPanel:recursiveGetChildById('charmListPanel')
    charmList:destroyChildren()

    local visibleList = {}
    if self.selectedType == "majorMenu" then
        visibleList = MajorMenu
    else
        visibleList = MinorMenu
    end

    local unlockedList = {}
    local lockedList = {}
    for _, charmData in pairs(self.data) do
        local charm = visibleList[charmData.id]
        if charm then
            charm.level = charmData.level
            charm.creatureId = charmData.creatureId
            charm.removePrice = charmData.removePrice
            if charmData.level > 0 then
                table.insert(unlockedList, charm)
            else
                table.insert(lockedList, charm)
            end
        end
    end

    table.sort(unlockedList, function(a, b) return a.name < b.name end)
    table.sort(lockedList, function(a, b) return a.name < b.name end)

    local selectedWidget = nil
    for _, charm in ipairs(unlockedList) do
        local charmItem = self:configureWidget(charm, charmList)

        local opacityItem = charmItem:recursiveGetChildById('opacityItem')
        opacityItem:setVisible(false)

        local level = charmItem:recursiveGetChildById('level')
        if charm.level > 0 then
            level:setImageSource('/images/game/cyclopedia/ui/backdrop_charmgrade'..charm.level)
        end

        if not selectedWidget or self.selectedCharm == charm.id then
            selectedWidget = charmItem
        end
    end

    for _, charm in ipairs(lockedList) do
        local charmItem = self:configureWidget(charm, charmList)
        if not selectedWidget or self.selectedCharm == charm.id then
            selectedWidget = charmItem
        end
    end

    if selectedWidget then
        self:setupContentPanel(selectedWidget)
        selectedWidget:focus()
    end
end

function Charm:configureCreatureList(monsters)
    local monsterList = VisibleCyclopediaPanel:recursiveGetChildById('monsterList')
    monsterList:destroyChildren()
    monsters = monsters or {}
    local sortedMonsters = {}
    for monsterId in pairs(monsters) do
        sortedMonsters[#sortedMonsters + 1] = tonumber(monsterId) or monsterId
    end

    table.sort(sortedMonsters, function(a, b)
        local monsterA = getCyclopediaMonster(a)
        local monsterB = getCyclopediaMonster(b)
        local nameA = monsterA and monsterA[1] or tostring(a)
        local nameB = monsterB and monsterB[1] or tostring(b)
        return nameA:lower() < nameB:lower()
    end)

    for _, monsterId in ipairs(sortedMonsters) do
        local monster = getCyclopediaMonster(monsterId)
        local monsterName = monster and monster[1]
        if monsterName and monsterName ~= "" and monsterName ~= "?" then
            local monsterItem = g_ui.createWidget('CharmListLabel', monsterList)
            monsterItem:setText(string.capitalize(monsterName))
            monsterItem:setId(monsterId)
        end
    end

end

function Charm:focusFirstVisibleCreature(keepKeyboardFocus)
    if keepKeyboardFocus == nil then
        keepKeyboardFocus = true
    end

    local monsterList = VisibleCyclopediaPanel:recursiveGetChildById('monsterList')
    local selectCreatureButton = VisibleCyclopediaPanel:recursiveGetChildById('selectCreatureButton')
    local creatureWidget = VisibleCyclopediaPanel:recursiveGetChildById('creature')
    for _, child in ipairs(monsterList:getChildren()) do
        if child:isVisible() then
            if keepKeyboardFocus then
                child:focus()
            end
            self:onMonsterFocusChange(child, true)
            return true
        end
    end

    self.raceId = 0
    selectCreatureButton:setEnabled(false)
    creatureWidget:setOutfit({type = 0})
    return false
end

function Charm.onCharmData(resetAllCharmPrice, charmData, emptySlots, monsters)
    Charm.resetPrice = resetAllCharmPrice
    Charm.data = charmData
    Charm.emptySlots = emptySlots
    Charm.monsters = monsters

    for _, charmData in pairs(self.data) do
        local charm = MajorMenu[charmData.id]
        if charm then
            charm.level = charmData.level
            charm.creatureId = charmData.creatureId
            charm.removePrice = charmData.removePrice
        end
    end

    for _, charmData in pairs(self.data) do
        local charm = MinorMenu[charmData.id]
        if charm then
            charm.level = charmData.level
            charm.creatureId = charmData.creatureId
            charm.removePrice = charmData.removePrice
        end
    end

    g_game.doThing(false)
    g_game.requestResource(ResourceBank)
    g_game.doThing(true)
    g_game.doThing(false)
    g_game.requestResource(ResourceInventary)
    g_game.doThing(true)

    if not VisibleCyclopediaPanel or VisibleCyclopediaPanel:getId() ~= "charmDataPanel" then
        return
    end

    local resetContent = VisibleCyclopediaPanel:recursiveGetChildById('resetContent')
    self:setResetPanelVisibility(emptySlots < 0xFF)
    if emptySlots < 0xFF then
        resetContent:getChildById('resetText'):setText(string.format(constTexts[1], emptySlots))
        resetContent:getChildById('infoHover'):setTooltip(string.format(constTexts[2], emptySlots))
    end

    VisibleCyclopediaPanel:recursiveGetChildById('goldResetAmount'):setText(comma_value(resetAllCharmPrice))

    -- make list
    self:configureCharmPanel()
    self:configureCreatureList(self.monsters)
    self:loadMenu(self.selectedType)
end

function Charm:requestData()
    g_game.requestCharmData()
end

function Charm:loadMenu(menu)
    local lastui = VisibleCyclopediaPanel:recursiveGetChildById(self.selectedType)
    if lastui then
        lastui:setOn(false)
    end
    self.selectedType = menu
    local ui = VisibleCyclopediaPanel:recursiveGetChildById(menu)
    ui:setOn(true)
    self:configureCharmPanel()

    local charmBgSlot = VisibleCyclopediaPanel:recursiveGetChildById('charmBgSlot')
    local imagetType = charmBgSlot:recursiveGetChildById('imagetType')

    if menu == "majorMenu" then
        imagetType:setImageSource('/images/game/cyclopedia/ui/charm-points')
    else
        imagetType:setImageSource('/images/game/cyclopedia/ui/minor-charm-echoes')
    end
end

function Charm:getCharm(charmId)
    local list = {}
    if self.selectedType == "majorMenu" then
        list = MajorMenu
    else
        list = MinorMenu
    end

    local charm = list[charmId]
    if not charm then
        return
    end

    return charm
end

function Charm:setupContentPanel(widget)
    local charm = self:getCharm(tonumber(widget:getId()))
    if not charm then
        return
    end

    if not VisibleCyclopediaPanel or VisibleCyclopediaPanel:getId() ~= "charmDataPanel" then
        return
    end

    local player = g_game.getLocalPlayer()
    local bankMoney = player:getResourceValue(ResourceBank)
    local characterMoney = player:getResourceValue(ResourceInventary)

    cyclopediaWindow:recursiveGetChildById('coinsAmount'):setText(comma_value(bankMoney + characterMoney))

    local charmContent = VisibleCyclopediaPanel:recursiveGetChildById('charmContent')

    self.selectedCharm = charm.id

    local level = charm.level
    charmContent:recursiveGetChildById('informationText'):setText(string.format(charm.description, charm.bonuses[math.max(0, level - 1)]))

    VisibleCyclopediaPanel:recursiveGetChildById('title'):setText(charm.name)

    -- set image
    local image = charmContent:recursiveGetChildById('charmImage')
    image:setImageSource('/images/game/cyclopedia/monster-bonus-effects/monster-bonus-effects-' .. charm.id)
    image:setTooltip(string.todivide(charm.name .. ": " .. string.format(charm.description, charm.bonuses[math.max(0, charm.level - 1)]), 10))

    local unlockButton = charmContent:recursiveGetChildById('unlockButton')
    unlockButton:setEnabled(true)
    if level == 0 then
        unlockButton:setText('Unlock')
    elseif level < 3 then
        unlockButton:setText('Upgrade to ' .. charm.bonuses[math.max(0, level)] .. '%')
    else
        unlockButton:setEnabled(false)
        unlockButton:setText('Fully Unlocked')
    end

    local clearButton = charmContent:recursiveGetChildById('clearButton')
    clearButton:setEnabled(charm.creatureId ~= 0)

    if level < 3 then
        local price = charm.prices[math.max(0, level)]
        charmContent:recursiveGetChildById('charmInfoAmount'):setText(comma_value(price))
    else
        charmContent:recursiveGetChildById('charmInfoAmount'):setText(0)
    end

    local charmPrice = charm.prices[math.max(0, charm.level)]
    local charmPriceLabel = charmContent:recursiveGetChildById('charmInfoAmount')
    local player = g_game.getLocalPlayer()
    if player and charmPrice then
        if self.selectedType == "majorMenu" then
            if charmPrice > player:getResourceValue(ResourceCharmBalance) then
                charmPriceLabel:setColor("$var-text-cip-store-red")
                unlockButton:setEnabled(false)
            else
                charmPriceLabel:setColor("$var-text-cip-color")
            end
        else
            if charmPrice > player:getResourceValue(ResourceEchoeBalance) then
                charmPriceLabel:setColor("$var-text-cip-store-red")
                unlockButton:setEnabled(false)
            else
                charmPriceLabel:setColor("$var-text-cip-color")
            end
        end
    end

    if player and self.resetPrice > (player:getResourceValue(ResourceBank) + player:getResourceValue(ResourceInventary)) then
        VisibleCyclopediaPanel:recursiveGetChildById('goldResetAmount'):setColor("$var-text-cip-store-red")
        VisibleCyclopediaPanel:recursiveGetChildById('resetCharmsButton'):setEnabled(false)
    else
        VisibleCyclopediaPanel:recursiveGetChildById('goldResetAmount'):setColor("$var-text-cip-color")
        VisibleCyclopediaPanel:recursiveGetChildById('resetCharmsButton'):setEnabled(true)
    end

    local level = charmContent:recursiveGetChildById('level')
    if charm.level > 0 then
        level:setVisible(true)
        level:setImageSource('/images/game/cyclopedia/ui/backdrop_charmgrade'..charm.level)
    else
        level:setVisible(false)
    end

    if charm.creatureId ~= 0 then
        self:configureCreatureList({[charm.creatureId] = charm.id})
    elseif charm.level > 0 then
        self:configureCreatureList(self.monsters)
    else
        self:configureCreatureList({})
    end

    local selectCreatureButton = VisibleCyclopediaPanel:recursiveGetChildById('selectCreatureButton')
    selectCreatureButton:setEnabled(false)

    local creatureWidget = VisibleCyclopediaPanel:recursiveGetChildById('creature')
    creatureWidget:setOutfit({type = 0})

    local player = g_game.getLocalPlayer()
    local bankMoney = player:getResourceValue(ResourceBank)
    local characterMoney = player:getResourceValue(ResourceInventary)

    -- configure clear button
    local charmRemovePrice = charmContent:recursiveGetChildById('goldClearAmount')
    if charm.creatureId ~= 0 then
        charmRemovePrice:setText(comma_value(charm.removePrice))

        if charm.removePrice > (bankMoney + characterMoney) then
            charmRemovePrice:setColor("$var-text-cip-store-red")
            clearButton:setEnabled(false)
        else
            charmRemovePrice:setColor("$var-text-cip-color")
            clearButton:setEnabled(true)
        end
    else
        charmRemovePrice:setText('0')
        charmRemovePrice:setColor("$var-text-cip-color")
        clearButton:setEnabled(false)
    end

    if charm.creatureId ~= 0 then
        self.raceId = charm.creatureId
        local monster = getCyclopediaMonster(charm.creatureId)
        if monster then
            creatureWidget:setOutfit({type = monster[2], auxType = monster[3], head = monster[4], body = monster[5], legs = monster[6], feet = monster[7], addons = monster[8]})
        end
    elseif charm.level > 0 then
        self:focusFirstVisibleCreature()
    else
        self.raceId = 0
    end
end

function Charm:onFocusChange(widget, focused)
    if not focused then
        return
    end

    scheduleEvent(function()
        self:setupContentPanel(widget)
    end, 100)
end

function Charm.onResourceBalance()
    if not cyclopediaWindow or not cyclopediaWindow:isVisible() then
        return
    end
    local player = g_game.getLocalPlayer()
    local bankMoney = player:getResourceValue(ResourceBank)
    local characterMoney = player:getResourceValue(ResourceInventary)

    local charmBalance = player:getResourceValue(ResourceCharmBalance)
    local echoeBalance = player:getResourceValue(ResourceEchoeBalance)
    local maxCharmBalance = player:getResourceValue(ResourceMaxCharmBalance)
    local maxEchoeBalance = player:getResourceValue(ResourceMaxEchoeBalance)

    cyclopediaWindow:recursiveGetChildById('minorCharmAmount'):setText(echoeBalance.." / "..maxEchoeBalance)
    cyclopediaWindow:recursiveGetChildById('charmAmount'):setText(charmBalance.." / "..maxCharmBalance)
    cyclopediaWindow:recursiveGetChildById('coinsAmount'):setText(comma_value(bankMoney + characterMoney))
end

function Charm:upgradeCharm()
    local charm = self:getCharm(self.selectedCharm)
    if not charm then
        return
    end
    g_game.charmUnlock(self.selectedCharm)
end

function Charm:onUpgradeCharm()
    if self.askWindow then
        return true
    end

    local charm = self:getCharm(self.selectedCharm)
    if not charm then
        return
    end

    local level = charm.level
    if level == 3 then
        return
    end

    local yesCallback = function() g_client.setInputLockWidget(nil) self.askWindow:destroy() self.askWindow = nil Charm:upgradeCharm() cyclopediaWindow:setVisible(true) end
    local noCallback = function() g_client.setInputLockWidget(nil) self.askWindow:destroy() self.askWindow = nil cyclopediaWindow:setVisible(true) end


    local text = ""
    local title = "Confirm Unlocking of Charm"
    local resourceName = self.selectedType == "minorMenu" and "Minor Charm Echoes" or "Charm Points"
    if level == 0 then
        text = string.format(askWindowText[0], charm.name, charm.prices[0], resourceName)
    elseif level == 1 then
        text = string.format(askWindowText[1], charm.name, charm.prices[1], resourceName)
        title = "Confirm Upgrading of Charm"
    elseif level == 2 then
        text = string.format(askWindowText[1], charm.name, charm.prices[2], resourceName)
        title = "Confirm Upgrading of Charm"
    end

    self.askWindow = displayGeneralBox(title, text,
        { { text=tr('Yes'), callback=yesCallback },
        { text=tr('No'), callback=noCallback },
    }, yesCallback, noCallback)

    cyclopediaWindow:setVisible(false)
    g_client.setInputLockWidget(self.askWindow)
    return true
end

function Charm:resetAllCharm()
    g_game.resetAllCharm()
    return true
end

function Charm:onResetAllCharm()
    if self.askWindow then
        return true
    end

    local yesCallback = function() g_client.setInputLockWidget(nil) self.askWindow:destroy() self.askWindow = nil self:resetAllCharm() cyclopediaWindow:setVisible(true) end
    local noCallback = function() g_client.setInputLockWidget(nil) self.askWindow:destroy() self.askWindow = nil cyclopediaWindow:setVisible(true) end

    local text = string.format("Do you want to reset all Charms? This will cost you %s gold?", comma_value(self.resetPrice))

    local title = "Confirm Reset of Charms"

    self.askWindow = displayGeneralBox(title, text,
        { { text=tr('Yes'), callback=yesCallback },
        { text=tr('No'), callback=noCallback },
    }, yesCallback, noCallback)

    cyclopediaWindow:setVisible(false)
    g_client.setInputLockWidget(self.askWindow)
    return true
end

function Charm:onMonsterFocusChange(widget, focused)
    if not focused then
        return
    end

    local creatureWidget = VisibleCyclopediaPanel:recursiveGetChildById('creature')
    local raceId = tonumber(widget:getId())
    self.raceId = raceId
    local monster = getCyclopediaMonster(raceId)
    if monster then
        creatureWidget:setOutfit({type = monster[2], auxType = monster[3], head = monster[4], body = monster[5], legs = monster[6], feet = monster[7], addons = monster[8]})
    end

    local selectCreatureButton = VisibleCyclopediaPanel:recursiveGetChildById('selectCreatureButton')

    local charm = self:getCharm(self.selectedCharm)
    if charm then
        if charm.level == 0 or charm.creatureId ~= 0 then
            selectCreatureButton:setEnabled(false)
            return
        end
    end

    selectCreatureButton:setEnabled(true)
end

function Charm:selectCreature()
    local charm = self:getCharm(self.selectedCharm)
    if not charm then
        return
    end

    if not self.raceId or self.raceId <= 0 or not getCyclopediaMonster(self.raceId) then
        return
    end

    g_game.charmSelect(self.selectedCharm, self.raceId)
end

function Charm:onSelectCreature()
    if self.askWindow then
        return true
    end

    local charm = self:getCharm(self.selectedCharm)
    if not charm then
        return
    end

    local yesCallback = function() g_client.setInputLockWidget(nil) self.askWindow:destroy() self.askWindow = nil self:selectCreature() cyclopediaWindow:setVisible(true) end
    local noCallback = function() g_client.setInputLockWidget(nil) self.askWindow:destroy() self.askWindow = nil cyclopediaWindow:setVisible(true) end

    local text = string.format("Do you want to use the Charm %s for this creature?", charm.name)

    local title = "Confirm Selected Charms"

    self.askWindow = displayGeneralBox(title, text,
        { { text=tr('Yes'), callback=yesCallback },
        { text=tr('No'), callback=noCallback },
    }, yesCallback, noCallback)

    cyclopediaWindow:setVisible(false)
    g_client.setInputLockWidget(self.askWindow)
    return true
end

function Charm:clearCharm()
    local charm = self:getCharm(self.selectedCharm)
    if not charm then
        return
    end

    g_game.charmRemove(self.selectedCharm)
end

function Charm:onClearCharm()
    if self.askWindow then
        return true
    end

    local charm = self:getCharm(self.selectedCharm)
    if not charm then
        return
    end

    local yesCallback = function() g_client.setInputLockWidget(nil) self.askWindow:destroy() self.askWindow = nil self:clearCharm() cyclopediaWindow:setVisible(true) end
    local noCallback = function() g_client.setInputLockWidget(nil) self.askWindow:destroy() self.askWindow = nil cyclopediaWindow:setVisible(true) end

    local text = string.format("Do you want to remove the Charm %s from this creature? This will cost you %s gold pieces.", charm.name, comma_value(charm.removePrice))

    local title = "Confirm Charm Removal"

    self.askWindow = displayGeneralBox(title, text,
        { { text=tr('Yes'), callback=yesCallback },
        { text=tr('No'), callback=noCallback },
    }, yesCallback, noCallback)

    cyclopediaWindow:setVisible(false)
    g_client.setInputLockWidget(self.askWindow)
    return true
end

function Charm:onSearchTextChange(text)
    local monsterList = VisibleCyclopediaPanel:recursiveGetChildById('monsterList')
    text = text or ''
    local normalizedText = text:lower()
    for _, child in pairs(monsterList:getChildren()) do
        local name = child:getText():lower()
        if name:find(normalizedText, 1, true) or text == '' or #text < 3 then
            child:setVisible(true)
        else
            child:setVisible(false)
        end
    end

    if #text >= 3 then
        self:focusFirstVisibleCreature(false)
    end
end

function Charm:onClearSearchText()
    local search = VisibleCyclopediaPanel:recursiveGetChildById('searchTextCharm')
    search:setText('')
    self:focusFirstVisibleCreature()
end

function Charm:getEmptyMajorSlots()
    local charms = {}
    for _, charm in pairs(MajorMenu) do
        if (charm.level or 0) > 0 and (charm.creatureId or 0) == 0 then
            table.insert(charms, charm)
        end
    end

    return charms
end

function Charm:getEmptyMinorSlots()
    local charms = {}
    for _, charm in pairs(MinorMenu) do
        if (charm.level or 0) > 0 and (charm.creatureId or 0) == 0 then
            table.insert(charms, charm)
        end
    end

    return charms
end

function Charm:getMajorCharm(monsterId)
    for _, charm in pairs(MajorMenu) do
        if charm.creatureId == monsterId then
            return charm
        end
    end

    return {id = -1}
end

function Charm:getMinorCharm(monsterId)
    for _, charm in pairs(MinorMenu) do
        if charm.creatureId == monsterId then
            return charm
        end
    end

    return {id = -1}
end

function Charm:getCharmCost(charmId)
    local charm = MajorMenu[charmId]
    if not charm then
        charm = MinorMenu[charmId]
    end

    if not charm then
        return 0
    end

    return charm.removePrice
end

function Charm:getCharmByName(name)
    for _, charm in pairs(MajorMenu) do
        if charm.name:lower() == name:lower() then
            return charm
        end
    end

    for _, charm in pairs(MinorMenu) do
        if charm.name:lower() == name:lower() then
            return charm
        end
    end

    return nil
end

function Charm:getCharmById(id)
    if MajorMenu[id] then
        return MajorMenu[id]
    end

    if MinorMenu[id] then
        return MinorMenu[id]
    end

    return nil
end

function Charm:redirectToStore()
    cyclopediaWindow:setVisible(false)
    modules.game_prey.storeRedirect(3)
end
