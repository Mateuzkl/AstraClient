local window = nil
local colorBoxGroup = nil
local colorModeGroup = nil
local hirelingSexGroup = nil

local currentOutfit = {}
local previewCreature = nil
local ServerData = {}

function init()
    window = g_ui.displayUI("hireling_outfit")
    window:hide()

    colorBoxGroup = UIRadioGroup.create()
    for j = 0, 6 do
        for i = 0, 18 do
            local colorBox = g_ui.createWidget("ColorBox", window.appearance.panelcolor)
            local outfitColor = getOutfitColor(j * 19 + i)
            colorBox:setBackgroundColor(outfitColor)
            colorBox:setId("colorBox" .. j * 19 + i)
            colorBox.colorId = j * 19 + i

            if colorBox.colorId == currentOutfit.head then
                currentColorBox = colorBox
                colorBox:setChecked(true)
                currentColorBox:setBorderWidth(1)
                currentColorBox:setBorderColor("white")
            end
            colorBoxGroup:addWidget(colorBox)
        end
    end

    colorBoxGroup.onSelectionChange = onColorCheckChange

    colorModeGroup = UIRadioGroup.create()
    colorModeGroup:addWidget(window.appearance.panelbar.HeadButton)
    colorModeGroup:addWidget(window.appearance.panelbar.PrimaryButton)
    colorModeGroup:addWidget(window.appearance.panelbar.SecondaryButton)
    colorModeGroup:addWidget(window.appearance.panelbar.DetailButton)
    colorModeGroup.onSelectionChange = onColorModeChange
    colorModeGroup:selectWidget(window.appearance.panelbar.HeadButton)

    hirelingSexGroup = UIRadioGroup.create()
    hirelingSexGroup:addWidget(window:recursiveGetChildById('femaleButton'))
    hirelingSexGroup:addWidget(window:recursiveGetChildById('maleButton'))
    hirelingSexGroup.onSelectionChange = onSexChange
    hirelingSexGroup:selectWidget(window:recursiveGetChildById('maleButton'), true)

    previewCreature = window.preview.previewoutfit.creature
    previewCreature:setOutfit({})
    window.appearance.outfitCheck:setChecked(true)
    window:recursiveGetChildById('showfloor').showfloorCheck:setChecked(true, false)

    connect(g_game, { onOpenHirelingWindow = onOpenHirelingWindow })
end

function terminate()
    disconnect(g_game, { onOpenHirelingWindow = onOpenHirelingWindow })
end

function onOpenHirelingWindow(currentOutfit, outfitList, sex, creatureId, tryOnList)
    local tryOutfits = {}
    for k, v in pairs(tryOnList or {}) do
        if type(v) == 'table' then
            table.insert(tryOutfits, {v[1], v[2]})
        else
            table.insert(tryOutfits, {k, v})
        end
    end

    ServerData = { outfit = currentOutfit, outfits = outfitList, sex = sex, creatureId = creatureId, tryOnList = tryOutfits }
    window:focus()
    window:show()
    g_client.setInputLockWidget(window)
    showOutfits()
end

function showOutfits(searchText, trySex)
    window.ScrollBar.selectionList.onChildFocusChange = nil
    if previewCreature:getOutfit().type == 0 then
        previewCreature:setOutfit(ServerData.outfit)
        colorModeGroup:selectWidget(nil)
        colorModeGroup:selectWidget(window.appearance.panelbar.HeadButton)
    end

    window.ScrollBar.selectionList:destroyChildren()
    window.filter_outfits.onlyCheck:setEnabled(true)

    local isTryOn = #ServerData.tryOnList > 0
    local trySex = not trySex and ServerData.sex or trySex
    window:recursiveGetChildById('okButton'):setVisible(not isTryOn)
    window:setText(isTryOn and "Try Hireling Dress" or "Customize Hireling")
    window:recursiveGetChildById('femaleButton'):setVisible(isTryOn)
    window:recursiveGetChildById('maleButton'):setVisible(isTryOn)

    local availableOutfits = {}
    local lockedOutfits = {}
    local onlyMine = window.filter_outfits.onlyCheck:isChecked()

    for _, data in pairs(ServerData.outfits) do
        data[4] = tonumber(data[4]) or 0
        if data[4] == 0 then
            table.insert(availableOutfits, data)
        else
            table.insert(lockedOutfits, data)
        end
    end

    if not onlyMine then
        for _, data in ipairs(lockedOutfits) do
            table.insert(availableOutfits, data)
        end
    end

    for _, outfitData in ipairs(availableOutfits) do
        if searchText and not matchText(searchText, outfitData[2]) then
            goto continue
        end

        local button = g_ui.createWidget("SelectionButton", window.ScrollBar.selectionList)
        button:setId(outfitData[1])

        local outfit = table.copy(previewCreature:getOutfit())
        local outfitId = outfitData[1]
        if isTryOn then
            for _, v in pairs(ServerData.tryOnList) do
                if outfitId == v[1] or outfitId == v[2] then
                    outfitId = trySex == 0 and v[2] or v[1]
                end
            end
        end

        outfit.type = outfitId
        button.outfit:setOutfit(outfit)
        button.name:setText(outfitData[2])

        local storeOffer = outfitData[4]
        if storeOffer > 0 then
            button:setImageSource("/images/ui/large_blue_button")
            button:setActionId(storeOffer)
        end
        :: continue ::
    end

    window.appearance.grayHover:setVisible(false)
    window.ScrollBar.selectionList.onChildFocusChange = onOutfitSelect
    window.ScrollBar.selectionList:show()

    local focusedWidget = window.ScrollBar.selectionList:recursiveGetChildById(previewCreature:getOutfit().type)
    if searchText then
        window.ScrollBar.selectionList:focusChild(nil)
    elseif not searchText and focusedWidget then
        window.ScrollBar.selectionList:focusChild(nil)
        window.ScrollBar.selectionList:focusChild(focusedWidget)
        window.ScrollBar.selectionList:ensureChildVisible(w, {x = 0, y = 196})
    else
        window.ScrollBar.selectionList:focusChild(nil)
        window.ScrollBar.selectionList:focusChild(window.ScrollBar.selectionList:getFirstChild())
        window.ScrollBar.selectionList:ensureChildVisible(w, {x = 0, y = 196})
    end
end

function onColorModeChange(widget, selectedWidget)
    if not previewCreature or not selectedWidget then
        return
    end

    local colorMode = selectedWidget:getId()
    if colorMode == "HeadButton" then
        selectedWidget:getParent():setImageClip("0 0 253 18")
        colorBoxGroup:selectWidget(window.appearance.panelcolor["colorBox" .. previewCreature:getOutfit().head])
    elseif colorMode == "PrimaryButton" then
        selectedWidget:getParent():setImageClip("0 18 253 18")
        colorBoxGroup:selectWidget(window.appearance.panelcolor["colorBox" .. previewCreature:getOutfit().body])
    elseif colorMode == "SecondaryButton" then
        selectedWidget:getParent():setImageClip("0 36 253 18")
        colorBoxGroup:selectWidget(window.appearance.panelcolor["colorBox" .. previewCreature:getOutfit().legs])
    elseif colorMode == "DetailButton" then
        selectedWidget:getParent():setImageClip("0 54 253 18")
        colorBoxGroup:selectWidget(window.appearance.panelcolor["colorBox" .. previewCreature:getOutfit().feet])
    end
end
  
function onColorCheckChange(widget, selectedWidget)
    local colorId = selectedWidget.colorId
  
    if currentColorBox then
      currentColorBox:setBorderWidth(0)
      currentColorBox:setBorderColor("alpha")
      currentColorBox:setChecked(false)
    end
  
    currentColorBox = selectedWidget
    selectedWidget:setBorderWidth(1)
    selectedWidget:setBorderColor("white")

    local tempOutfit = previewCreature:getOutfit()
    local colorMode = colorModeGroup:getSelectedWidget():getId()
    if colorMode == "HeadButton" then
        tempOutfit.head = colorId
    elseif colorMode == "PrimaryButton" then
        tempOutfit.body = colorId
    elseif colorMode == "SecondaryButton" then
        tempOutfit.legs = colorId
    elseif colorMode == "DetailButton" then
        tempOutfit.feet = colorId
    end
  
    previewCreature:setOutfit(tempOutfit)
    showOutfits()
end 

function onSexChange(widget, selectedWidget)
    if not selectedWidget or not previewCreature then
        return
    end

    local sexId = selectedWidget:getId() == "femaleButton" and 0 or 1
    for _, widget in pairs(window.ScrollBar.selectionList:getChildren()) do
        local outfit = widget.outfit:getOutfit()
        for _, v in pairs(ServerData.tryOnList) do
            if outfit.type == v[1] or outfit.type == v[2] then
                outfit.type = sexId == 0 and v[2] or v[1]
            end
        end

        widget.outfit:setOutfit(outfit)
    end
end

function onOutfitSelect(list, focusedChild, unfocusedChild, reason)
    if not focusedChild or not focusedChild.name then
        return
    end

    window.ScrollBar.selectionList:ensureChildVisible(focusedChild, {x = 0, y = 2})
    window.appearance.outfit.name:setText(focusedChild.name:getText())
    if focusedChild:getActionId() > 0 then
        window.appearance.outfit:setImageSource("/images/ui/hlarge-blue-button")
        window.appearance.outfit.purse:setVisible(true)
        window.appearance.outfit.onClick = function() close() g_game.openStore() g_game.requestStoreOffers(4, "", focusedChild:getActionId()) end
        window.okButton:setEnabled(false)
    else
        window.appearance.outfit:setImageSource("/images/ui/pressed-large-button")
        window.appearance.outfit.purse:setVisible(false)
        window.appearance.outfit.onClick = nil
        window.okButton:setEnabled(true)
    end

    local currentOutfit = previewCreature:getOutfit()
    currentOutfit.type = focusedChild.outfit:getOutfit().type
    previewCreature:setOutfit(currentOutfit)
    window.appearance.grayHover:setVisible(not previewCreature:isColoredOutfit())
end
  
function rotate(value)
    local direction = previewCreature:getDirection()
    direction = direction + value
    if direction < Directions.North then
        direction = Directions.West
    elseif direction > Directions.West then
        direction = Directions.North
    end
    previewCreature:setDirection(direction)
end
  
function onFilterSearch(widget)
    local hasText = not string.empty(widget:getText())
    showOutfits(hasText and widget:getText() or nil)
end
  
function onClearFilterSearch(widget)
    widget:clearText(false)
    showOutfits()
end

function manageFloor(checked)
    local widget = window:recursiveGetChildById('previewoutfit')
    widget:setImageSource(checked and "/images/game/outfit_ground" or "")
end

function setHirelingOutfit()
    if not previewCreature then
        return
    end

    g_game.changeHirelingOutfit(previewCreature:getOutfit(), ServerData.creatureId)
    close()
end

function close()
    window:hide()
    previewCreature:setOutfit({})
    window:recursiveGetChildById('searchfilter'):clearText(true)
    window:recursiveGetChildById('onlyCheck'):setChecked(false, true)
    window:recursiveGetChildById('showfloor').showfloorCheck:setChecked(true)
    g_client.setInputLockWidget(nil)
end
