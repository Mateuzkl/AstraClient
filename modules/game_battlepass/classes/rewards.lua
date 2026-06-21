local function getRewardItemServerId(itemData)
    if not itemData then
        return 0
    end
    return tonumber(itemData.itemId) or tonumber(itemData.thingId) or 0
end

local function getRewardItemMetadata(itemData)
    if not itemData or type(itemData.randomValues) ~= "table" then
        return nil
    end

    return itemData.randomValues[1]
end

local function getRewardItemClientId(itemData)
    if not itemData then
        return 0
    end

    local clientId = tonumber(itemData.clientId) or 0
    if clientId > 0 then
        return clientId
    end

    local metadata = getRewardItemMetadata(itemData)
    local metadataClientId = tonumber(metadata and metadata.thingId) or 0
    if metadataClientId > 0 then
        return metadataClientId
    end

    return getRewardItemServerId(itemData)
end

local function getRewardItemName(itemData)
    local name = itemData and (itemData.itemName or itemData.thingName) or nil
    if name and name ~= "" then
        return name
    end

    local metadata = getRewardItemMetadata(itemData)
    name = metadata and metadata.thingName or nil
    if name and name ~= "" then
        return name
    end

    local clientId = getRewardItemClientId(itemData)
    if clientId > 0 and Item and Item.create then
        local item = Item.create(clientId, 1)
        if item and item.getName and type(item.getName) == "function" then
            local itemName = item:getName()
            if itemName and itemName ~= "" then
                return itemName
            end
        end
    end

    return "Unknown Item"
end

local function setRewardWidgetItem(widget, itemData)
    local clientId = getRewardItemClientId(itemData)
    if clientId > 0 and Item and Item.create then
        widget:setItem(Item.create(clientId, 1))
    else
        widget:clearItem()
    end
end

local function getRewardChildItemData(reward, itemData, index)
    local metadata = reward and type(reward.randomValues) == "table" and reward.randomValues[index] or nil
    if not itemData or not metadata then
        return itemData
    end

    local data = {}
    for key, value in pairs(itemData) do
        data[key] = value
    end
    data.clientId = metadata.thingId
    data.itemName = metadata.thingName
    return data
end

if not BattlePassRewards then
    BattlePassRewards = {}
    BattlePassRewards.__index = BattlePassRewards

    BattlePassRewards.claimRewardWindow = nil
    BattlePassRewards.confirmRewardWindow = nil

    BattlePassRewards.rewardWidthIncrement = 80
    BattlePassRewards.rewardEmptyHeight = 140

    BattlePassRewards.selectedItemId = -1

    BattlePassRewards.textReward = ''
end

local skillName = {
    [0] = "Fist Fighting",
    [1] = "Club Fighting",
    [2] = "Sword Fighting",
    [3] = "Axe Fighting",
    [4] = "Distance Fighting",
    [5] = "Shielding",
    [13] = "Magic Level"
}

local selectableRewardTypes = {
    ["Boosted Exercise"] = true,
    ["Exercise Item"] = true,
    ["Extra Skill"] = true,
    ["Elemental Outfit"] = true,
    ["Choosable Item"] = true,
}

local function validateSelectedItem(self, reward)
    if self.selectedItemId == -1 and selectableRewardTypes[BattleRewardTypes[reward.rewardType]] then
        modules.game_textmessage.displayFailureMessage("You must select an item before collecting the reward.")
        return false
    end

    return true
end

local function getRewardInfoSlot(parent, index)
    local widget = parent:recursiveGetChildById("rewardSlot" .. index)
    if not widget then
        widget = g_ui.createWidget("RewardInfoSlot", parent)
        widget:setId("rewardSlot" .. index)
        widget:setVisible(false)
    end

    return widget
end

function BattlePassRewards:onConfirmClaimReward(index, rewardType)
    local reward = self:getReward(index, rewardType)
    if not reward then
        return
    end

    if self.confirmRewardWindow then
        self.confirmRewardWindow:destroy()
        self.confirmRewardWindow = nil
    end

    self.claimRewardWindow = g_ui.createWidget("SelectRewardWindow", rootWidget)
    local widgetsPanel = self.claimRewardWindow:recursiveGetChildById("rewardsInfoPanel")

    local rewardLabel = self.claimRewardWindow:recursiveGetChildById("rewardLabel")
    local text = rewardLabel:getText()
    rewardLabel:setText(string.format(text, index))

    self.claimRewardWindow.onEscape = function()
        self.claimRewardWindow:destroy()
        self.claimRewardWindow = nil
        BattlePass:showBattlePass()
    end

    self.claimRewardWindow:recursiveGetChildById("close").onClick = function()
        self.claimRewardWindow:destroy()
        self.claimRewardWindow = nil
        BattlePass:showBattlePass()
    end

    local function okfunction()
        if not validateSelectedItem(self, reward) then
            return
        end

        self.confirmRewardWindow:destroy()
        self.confirmRewardWindow = nil
        BattlePass:showBattlePass()

        self:onRedeemReward(index, reward.rewardId, reward.rewardType, self.selectedItemId)
    end

    local cancelFunc = function()
        self.confirmRewardWindow:destroy()
        self.confirmRewardWindow = nil
        self.claimRewardWindow:show()
    end

    self.claimRewardWindow:recursiveGetChildById("collectRewardButton").onClick = function()
        if not validateSelectedItem(self, reward) then
            return
        end

        if BattleRewardTypes[reward.rewardType] == "Extra Skill" then
            self.textReward = string.format("You will receive +%d skill points in %s\nfor %d hours (Scroll 30 days).", reward.count, skillName[self.selectedItemId], reward.durationTime)
        elseif BattleRewardTypes[reward.rewardType] == "Elemental Outfit" then
            local elements = {
                [1] = "Death",
                [2] = "Energy",
                [3] = "Holy",
                [4] = "Ice",
                [5] = "Earth",
                [6] = "Fire"
            }
            self.textReward = string.format("You will receive the %s Elemental Outfits\nwith addons %s.", elements[self.selectedItemId], reward.addons and "enabled" or "disabled")
        elseif BattleRewardTypes[reward.rewardType] == "Choosable Item" then
            local selectedItemName = ""
            for _, v in pairs(reward.choosableValues) do
                if v.thingId == self.selectedItemId then
                    selectedItemName = getRewardItemName(v)
                    break
                end
            end
            self.textReward = string.format("You will receive %dx %s.", reward.count, string.capitalize(selectedItemName))
        end

        self.claimRewardWindow:hide()
        self.confirmRewardWindow = g_ui.createWidget("ConfirmReward", rootWidget)

        self.confirmRewardWindow.onEscape = cancelFunc
        self.confirmRewardWindow:recursiveGetChildById('cancel').onClick = cancelFunc
        self.confirmRewardWindow:recursiveGetChildById('confirm').onClick = okfunction
        self.confirmRewardWindow:recursiveGetChildById('textContent'):setText(self.textReward)
    end

    BattlePass.hide()

    self.textReward = ''
    local infoLabel = self.claimRewardWindow:recursiveGetChildById("infoLabel")
    local rewardsInfoPanel = self.claimRewardWindow:recursiveGetChildById("rewardsInfoPanel")
    local outfitsInfoPanel = self.claimRewardWindow:recursiveGetChildById("outfitsInfoPanel")
    rewardsInfoPanel:setVisible(true)
    outfitsInfoPanel:setVisible(false)
    rewardsInfoPanel:setWidth(self.rewardWidthIncrement)
    local rewardsInfoScrollBar = self.claimRewardWindow:recursiveGetChildById("rewardsInfoScrollBar")
    rewardsInfoScrollBar:setVisible(true)

    local width = 0
    local normalHeight = 250

    self.selectedItemId = -1
    if BattleRewardTypes[reward.rewardType] == "Outfit" then
        local function rotateOutfit(value)
            self.currentOutfitDirection = self.currentOutfitDirection or Directions.North
            local direction = self.currentOutfitDirection + value
            if direction < Directions.North then
                direction = Directions.West
            elseif direction > Directions.West then
                direction = Directions.North
            end
            self.currentOutfitDirection = direction

            local index = 1
            while true do
                local outfitWidget = rewardsInfoPanel:recursiveGetChildById("rewardSlot" .. index - 1)
                if not outfitWidget then break end
                if outfitWidget:isVisible() then
                    outfitWidget.rewardOutfit:setDirection(direction)
                end
                index = index + 1
            end
        end

        local function setupOutfitWidget(outfitWidget, outfitData, currentOutfit)
            outfitWidget.rewardOutfit:setVisible(true)
            outfitWidget.rewardOutfit:setOutfit({
                type = outfitData.thingId,
                head = currentOutfit.head,
                body = currentOutfit.body,
                legs = currentOutfit.legs,
                feet = currentOutfit.feet,
                addons = reward.addons
            })

            outfitWidget:setImageSource('/images/game/battlepass/ground-bg')
            if self.currentOutfitDirection then
                outfitWidget.rewardOutfit:setDirection(self.currentOutfitDirection)
            end
        end

        local previousButton = self.claimRewardWindow:recursiveGetChildById("rotatePrevButton")
        local nextButton = self.claimRewardWindow:recursiveGetChildById("rotateNextButton")

        rewardsInfoPanel:setVisible(true)
        nextButton:setVisible(true)
        previousButton:setVisible(true)

        nextButton.onClick = function()
            rotateOutfit(-1)
        end
        previousButton.onClick = function()
            rotateOutfit(1)
        end

        local outfitName = ''
        local addonText = ''
        for k, v in pairs(reward.randomValues) do
            local widget = getRewardInfoSlot(widgetsPanel, k - 1)
            widget:setVisible(true)
            widget.rewardOutfit:setVisible(true)

            local currentOutfit = g_game.getLocalPlayer():getOutfit()
            local displayOutfit = {type = v.thingId, head = currentOutfit.head, body = currentOutfit.body, legs = currentOutfit.legs, feet = currentOutfit.feet, addons = reward.addons}
            --widget.rewardOutfit:setOutfit(displayOutfit)
            setupOutfitWidget(widget, v, currentOutfit)
            addonText = reward.addons == 1 and "first addon" or (reward.addons == 2 and "second addon" or "full addons")
            local tooltipText = string.format("%s with %s", v.thingName, addonText)
            widget.rewardOutfit:setTooltip(tooltipText)
            --widget.rewardOutfit:setImageSource('/images/game/battlepass/ground-bg')
            width = width + self.rewardWidthIncrement
            outfitName = tooltipText
        end

        infoLabel:setText(string.format("You will receive the following outfit with %s:", addonText))
        self.textReward = string.format("You will receive the following outfit:\n%s.", outfitName)
    elseif BattleRewardTypes[reward.rewardType] == "Random Item" then
        for k, v in pairs(reward.randomValues) do
            local widget = getRewardInfoSlot(widgetsPanel, k - 1)
            widget:setVisible(true)
            widget.rewardItem:setVisible(true)
            setRewardWidgetItem(widget.rewardItem, v)
            widget.rewardItem.rewardItemCount:setText(reward.count > 1 and tostring(reward.count) or "")
            widget.rewardItem:setTooltip(string.capitalize(getRewardItemName(v)))
            width = width + self.rewardWidthIncrement
        end

        local message = "You will receive a random item from the list below:"
        if reward.stuck then
            message = message .. "\n[color=white]The reward will be bound to your character.[/color]"
        end

       self.textReward = string.format("You will receive a random item from the list.")
       infoLabel:parseColoredText(message)
    elseif BattleRewardTypes[reward.rewardType] == "Random Mount" then
        for k, v in pairs(reward.randomValues) do
            local widget = getRewardInfoSlot(widgetsPanel, k - 1)
            widget:setVisible(true)
            widget:setPhantom(false)
            widget.rewardOutfit:setVisible(true)
            widget.rewardOutfit:setTooltip(v.thingName)
            widget:setImageSource('/images/game/battlepass/ground-bg')
            widget.rewardOutfit:setOutfit({type = v.thingId})
            width = width + self.rewardWidthIncrement
        end

        infoLabel:setText("You will receive a random mount from the list below:")
        self.textReward = string.format("You will receive a random mount from the list.")
    elseif BattleRewardTypes[reward.rewardType] == "Item" then
        local widget = getRewardInfoSlot(widgetsPanel, 0)
        widget:setVisible(true)
        widget.rewardItem:setVisible(true)
        setRewardWidgetItem(widget.rewardItem, reward)
        widget.rewardItem.rewardItemCount:setText(reward.count > 1 and tostring(reward.count) or "")
        local itemName = getRewardItemName(reward)
        local item = widget.rewardItem:getItem()

        if reward.charges > 0 then
            widget.rewardItem:setTooltip(string.format("%s\nCharges: %s", string.capitalize(itemName), reward.charges))
        else
            widget.rewardItem:setTooltip(string.format("%sx %s", reward.count, string.capitalize(itemName)))
        end

        if item then
            widget.rewardItem:setFixedSize(not item:isWrapable())

            if reward.itemId == 63246 then
                widget.rewardItem:setFixedSize(true)
            end

        end

        width = width + self.rewardWidthIncrement

        local message = "You will receive the following item."
        if reward.stuck then
            message = message .. "\n[color=white]The reward will be bound to your character.[/color]"
        end

       infoLabel:parseColoredText(message)
       self.textReward = string.format("You will receive the following item: %d %s.", reward.count, string.capitalize(itemName))

    elseif BattleRewardTypes[reward.rewardType] == "Boosted Exercise" or BattleRewardTypes[reward.rewardType] == "Exercise Item" then
        for k, v in pairs(reward.randomValues) do
            local widget = getRewardInfoSlot(widgetsPanel, k - 1)
            widget:setVisible(true)
            widget.rewardItem:setVisible(true)
            setRewardWidgetItem(widget.rewardItem, v)

            local itemName = getRewardItemName(v)

            widget.rewardItem:setTooltip(string.capitalize(itemName))
            widget:setFocusable(true)
            normalHeight = 260

            widget.rewardItem.onClick = function(w)
                if w:isFocused() then
                    self.selectedItemId = v.thingId

                    self.textReward = string.format("You must choose one %s,\nhave %d charges.", string.capitalize(itemName), reward.charges)
                end
            end

            width = width + self.rewardWidthIncrement
        end

        local message = "You must choose [color=white]one[/color] of the following items, have [color=white]" .. reward.charges .. " charges.[/color]"
        if reward.stuck then
            message = message .. "\n[color=white]The reward will be bound to your character.[/color]"
        end

       infoLabel:parseColoredText(message)
    elseif BattleRewardTypes[reward.rewardType] == "Charms" then
        infoLabel:parseColoredText("You will receive [color=white]+" .. reward.count .. " charm points[/color] on your character.")
        rewardsInfoPanel:setVisible(false)
        rewardsInfoScrollBar:setVisible(false)
        normalHeight = self.rewardEmptyHeight
        self.textReward = string.format("You will receive +%d charm points on your character.", reward.count)
    elseif BattleRewardTypes[reward.rewardType] == "Prey" then
        infoLabel:parseColoredText("You will receive [color=white]+" .. reward.count .. " prey wildcards[/color] on your character.")
        rewardsInfoPanel:setVisible(false)
        rewardsInfoScrollBar:setVisible(false)
        normalHeight = self.rewardEmptyHeight
        self.textReward = string.format("You will receive +%d prey wildcards on your character.", reward.count)
    elseif BattleRewardTypes[reward.rewardType] == "Regen" then
        infoLabel:parseColoredText("You will receive [color=white]" .. reward.durationTime .. " hours (Scroll 30 days) of Double Regeneration[/color].")
        rewardsInfoPanel:setVisible(false)
        rewardsInfoScrollBar:setVisible(false)
        normalHeight = self.rewardEmptyHeight
        self.textReward = string.format("You will receive %d hours (Scroll 30 days)\nof Double Regeneration.", reward.durationTime)
    elseif BattleRewardTypes[reward.rewardType] == "Instant Reward" then
        infoLabel:parseColoredText("You will receive [color=white]+" .. reward.count .. " instant rewards[/color] on your character.")
        rewardsInfoPanel:setVisible(false)
        rewardsInfoScrollBar:setVisible(false)
        normalHeight = self.rewardEmptyHeight
        self.textReward = string.format("You will receive +%d instant rewards on your character.", reward.count)
    elseif BattleRewardTypes[reward.rewardType] == "Double Skill" then
        infoLabel:parseColoredText("You will receive [color=white]" .. reward.durationTime .. " hours (Scroll 30 days) of Double Skill[/color].")
        rewardsInfoPanel:setVisible(false)
        rewardsInfoScrollBar:setVisible(false)
        normalHeight = self.rewardEmptyHeight
        self.textReward = string.format("You will receive %d hours (Scroll 30 days)\nof Double Skill.", reward.durationTime)
    elseif BattleRewardTypes[reward.rewardType] == "Level" then
        infoLabel:parseColoredText("You will receive [color=white]+" .. reward.count .. " Level[/color] on your character.")
        rewardsInfoPanel:setVisible(false)
        rewardsInfoScrollBar:setVisible(false)
        normalHeight = self.rewardEmptyHeight
        self.textReward = string.format("You will receive +%d Level on your character.", reward.count)
    elseif BattleRewardTypes[reward.rewardType] == "Overload Forge" then
        infoLabel:parseColoredText("You will receive [color=white]" .. reward.durationTime .. " hours (Scroll 30 days) of Exaltation Overload[/color].")
        rewardsInfoPanel:setVisible(false)
        rewardsInfoScrollBar:setVisible(false)
        normalHeight = self.rewardEmptyHeight
        self.textReward = string.format("You will receive %d hours (Scroll 30 days)\nof Exaltation Overload.", reward.durationTime)
    elseif BattleRewardTypes[reward.rewardType] == "Exp Boost" then
        infoLabel:parseColoredText("You will receive [color=white]" .. reward.durationTime .. " hours of store XP Boost[/color].")
        rewardsInfoPanel:setVisible(false)
        rewardsInfoScrollBar:setVisible(false)
        normalHeight = self.rewardEmptyHeight
        self.textReward = string.format("You will receive %d hours of store XP Boost,\nlinked to your skill tab.", reward.durationTime)
    elseif BattleRewardTypes[reward.rewardType] == "Extra Skill" then
        infoLabel:parseColoredText("You will receive [color=white]+" .. reward.count .. " skill points[/color] in the skill of your choice for [color=white]" .. reward.durationTime .. " hours[/color].")
        rewardsInfoPanel:setVisible(true)
        rewardsInfoScrollBar:setVisible(true)

        local skills = {0, 1, 2, 3, 4, 5, 13}
        for k, v in pairs(skills) do
            local widget = getRewardInfoSlot(widgetsPanel, k - 1)
            widget:setVisible(true)
            widget.rewardSpecial:setVisible(true)
            widget.rewardSpecial:setTooltip(skillName[v] .. " (" .. reward.count .. " points for " .. reward.durationTime .. " hours)")
            widget.rewardSpecial:setImageSource('/images/game/battlepass/skills/' .. v)

            widget:setFocusable(true)

            widget.rewardSpecial.onClick = function(w)
                if w:isFocused() then
                    self.selectedItemId = v
                end
            end

            width = width + self.rewardWidthIncrement
        end

    elseif BattleRewardTypes[reward.rewardType] == "Elemental Outfit" then
        local function rotateOutfit(value)
            self.currentOutfitDirection = self.currentOutfitDirection or Directions.North
            local direction = self.currentOutfitDirection + value
            if direction < Directions.North then
                direction = Directions.West
            elseif direction > Directions.West then
                direction = Directions.North
            end
            self.currentOutfitDirection = direction

            local index = 1
            while true do
                local outfitWidget = outfitsInfoPanel:recursiveGetChildById("outfitPreview" .. index - 1)
                if not outfitWidget then break end
                if outfitWidget:isVisible() then
                    outfitWidget.rewardOutfit:setDirection(direction)
                end
                index = index + 1
            end
        end

        local function setupOutfitWidget(outfitWidget, outfitData, currentOutfit)
            outfitWidget.rewardOutfit:setVisible(true)
            outfitWidget.rewardOutfit:setOutfit({
                type = outfitData.looktype,
                head = currentOutfit.head,
                body = currentOutfit.body,
                legs = currentOutfit.legs,
                feet = currentOutfit.feet,
                addons = reward.addons
            })
            outfitWidget.rewardOutfit:setTooltip(outfitData.name)
            outfitWidget:setTooltip(outfitData.name)
            outfitWidget:setImageSource('/images/game/battlepass/ground-bg')
            if self.currentOutfitDirection then
                outfitWidget.rewardOutfit:setDirection(self.currentOutfitDirection)
            end
        end

        local previousButton = self.claimRewardWindow:recursiveGetChildById("previousButton")
        local nextButton = self.claimRewardWindow:recursiveGetChildById("nextButton")

        infoLabel:parseColoredText("You will receive the [color=white]Elemental Outfit[/color] of your choice.")
        rewardsInfoPanel:setVisible(true)
        outfitsInfoPanel:setVisible(true)
        nextButton:setVisible(true)
        previousButton:setVisible(true)

        nextButton.onClick = function()
            rotateOutfit(-1)
        end
        previousButton.onClick = function()
            rotateOutfit(1)
        end

        normalHeight = 340

        local elements = {
            [1] = "Death",
            [2] = "Energy",
            [3] = "Holy",
            [4] = "Ice",
            [5] = "Earth",
            [6] = "Fire"
        }

        for i = 1, 6 do
            local widget = getRewardInfoSlot(widgetsPanel, i - 1)
            widget:setVisible(true)
            widget.rewardSpecial:setVisible(true)
            widget.rewardSpecial:setImageSource('/images/game/battlepass/tiles/' .. i)
            widget.rewardSpecial:setTooltip("Elemental Outfit " .. elements[i])
            widget:setFocusable(true)

            if i == 1 then
                widget:recursiveFocus(2)
                self.selectedItemId = i

                local currentOutfit = g_game.getLocalPlayer():getOutfit()
                local index = 1
                for _, v in pairs(reward.maleOutfit[i]) do
                    local outfitWidget = outfitsInfoPanel:recursiveGetChildById("outfitPreview" .. index - 1)
                    setupOutfitWidget(outfitWidget, v, currentOutfit)
                    index = index + 1
                end
                for _, v in pairs(reward.femaleOutfit[i]) do
                    local outfitWidget = outfitsInfoPanel:recursiveGetChildById("outfitPreview" .. index - 1)
                    setupOutfitWidget(outfitWidget, v, currentOutfit)
                    index = index + 1
                end
            end

            widget.rewardSpecial.onClick = function(w)
                if w:isFocused() then
                    self.selectedItemId = i
                    local currentOutfit = g_game.getLocalPlayer():getOutfit()
                    local index = 1
                    for _, v in pairs(reward.maleOutfit[i]) do
                        local outfitWidget = outfitsInfoPanel:recursiveGetChildById("outfitPreview" .. index - 1)
                        setupOutfitWidget(outfitWidget, v, currentOutfit)
                        index = index + 1
                    end
                    for _, v in pairs(reward.femaleOutfit[i]) do
                        local outfitWidget = outfitsInfoPanel:recursiveGetChildById("outfitPreview" .. index - 1)
                        setupOutfitWidget(outfitWidget, v, currentOutfit)
                        index = index + 1
                    end
                end
            end

            width = width + self.rewardWidthIncrement
        end
    elseif BattleRewardTypes[reward.rewardType] == "Choosable Item" then
        for k, v in pairs(reward.choosableValues) do
            local widget = getRewardInfoSlot(widgetsPanel, k - 1)
            widget:setVisible(true)
            widget.rewardItem:setVisible(true)
            setRewardWidgetItem(widget.rewardItem, v)
            widget.rewardItem.rewardItemCount:setText(reward.count > 1 and tostring(reward.count) or "")

            local itemName = getRewardItemName(v)

            widget.rewardItem:setTooltip(string.format("%dx %s", reward.count, string.capitalize(itemName)))
            widget:setFocusable(true)
            normalHeight = 260

            widget.rewardItem.onClick = function(w)
                if w:isFocused() then
                    self.selectedItemId = v.thingId
                    self.textReward = string.format("You have selected %dx %s.", reward.count, string.capitalize(itemName))
                end
            end

            width = width + self.rewardWidthIncrement
        end

        local message = "You must choose [color=white]one[/color] of the following items:"
        if reward.stuck then
            message = message .. "\n[color=white]The reward will be bound to your character.[/color]"
        end

        infoLabel:parseColoredText(message)

    elseif BattleRewardTypes[reward.rewardType] == "Multi Items" then
        local stuck = reward.stuck or false
        local itemName = ''
        for k, v in pairs(reward.items) do
            local itemData = getRewardChildItemData(reward, v, k)
            local widget = getRewardInfoSlot(widgetsPanel, k - 1)
            widget:setVisible(true)
            widget.rewardItem:setVisible(true)
            setRewardWidgetItem(widget.rewardItem, itemData)
            widget.rewardItem.rewardItemCount:setText(v.count > 1 and tostring(v.count) or "")
            local childName = getRewardItemName(itemData)
            widget.rewardItem:setTooltip(string.capitalize(childName))

            width = width + self.rewardWidthIncrement
            if v.stuck then
                stuck = true
            end
            if itemName ~= '' then
                itemName = itemName .. ", " .. v.count .. " " .. string.capitalize(childName)
            else
                itemName = v.count .. " " .. string.capitalize(childName)
            end
        end

        local message = "You will receive these items from the list below:"
        if stuck then
            message = message .. "\n[color=white]The reward will be bound to your character.[/color]"
        end

       infoLabel:parseColoredText(message)
         self.textReward = string.format("You will receive these items from the list:\n%s", itemName)
    end

    local rewardCount = 0
    local i = 0
    while true do
        local widget = widgetsPanel:recursiveGetChildById("rewardSlot" .. i)
        if not widget then
            break
        end
        if widget:isVisible() then
            rewardCount = rewardCount + 1
        end
        i = i + 1
    end

    if rewardCount >= 6 then
        rewardsInfoPanel:setWidth(465)
    else
        rewardsInfoPanel:setWidth(math.min(430, width) + 10)
    end

    self.claimRewardWindow:setSize(tosize(500 .. " " .. normalHeight))

    if width <= 175 then
        rewardsInfoScrollBar:setVisible(false)
        rewardsInfoPanel:setImageSource("")
    end

end

function BattlePassRewards:onRedeemReward(index, internalRewardId, internalRewardType, objectId)
    if not g_game.isOnline() then
        return
    end

    if BattlePass and BattlePass.sendToServer then
        BattlePass.sendToServer("redeem", {
            index = index,
            rewardId = internalRewardId,
            objectId = objectId or 0,
        })
    end
end


function BattlePassRewards:getRewardDescription(reward)
    if reward.rewardType == 1 then
        local itemName = getRewardItemName(reward)
        return string.format("%dx %s", reward.count, string.capitalize(itemName))
    end

    return "Reward Type: " .. BattleRewardTypes[reward.rewardType]
end

function BattlePassRewards:getReward(index, rewardType)
    if not BattlePass or type(BattlePass.rewardSteps) ~= "table" then
        return nil
    end

    local isFreeReward = (rewardType == "free")
    for _, step in ipairs(BattlePass.rewardSteps) do
        if step.stepId == index then
            for _, reward in ipairs(step.rewards) do
                if isFreeReward and reward.freeReward then
                    return reward
                elseif not isFreeReward and not reward.freeReward then
                    return reward
                end
            end
        end
    end
    return nil
end
