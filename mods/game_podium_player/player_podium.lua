local PodiumWindow = nil
local sexRadio = nil
local optionsRadio = nil
local colorBoxGroup = nil
local colorModeGroup = nil
local currentColorBox = nil

-- Buttons
local showOutfitCheck = nil
local showMountCheck = nil
local showAuraCheck = nil
local showPodiumCheck = nil
local addon1Check = nil
local addon2Check = nil
local femaleButton = nil
local maleButton = nil
local showFloorCheck = nil

-- Panel
local outfitCheck = nil
local mountCheck = nil
local presetCheck = nil
local auraCheck = nil

local podiumItem = nil
local podiumData = nil

local availableOutfits = {}
local availableMounts = {}
local availableAuras = {}

function init()
    PodiumWindow = g_ui.displayUI('podiumwindow')
    PodiumWindow:hide()

    sexRadio = UIRadioGroup.create()
    femaleButton = PodiumWindow:recursiveGetChildById("femaleButton")
    maleButton = PodiumWindow:recursiveGetChildById("maleButton")
    sexRadio:addWidget(femaleButton)
    sexRadio:addWidget(maleButton)
    sexRadio:selectWidget(maleButton, true)
    sexRadio.onSelectionChange = function(widget, selected) changeOutfitSex(selected) end

    optionsRadio = UIRadioGroup.create()
    outfitCheck = PodiumWindow:recursiveGetChildById("outfitCheck")
    mountCheck = PodiumWindow:recursiveGetChildById("mountCheck")
    auraCheck = PodiumWindow:recursiveGetChildById("auraCheck")
    presetCheck = PodiumWindow:recursiveGetChildById("presetCheck")
    optionsRadio:addWidget(outfitCheck)
    optionsRadio:addWidget(mountCheck)
    optionsRadio:addWidget(auraCheck)
    optionsRadio:addWidget(presetCheck)
    optionsRadio:selectWidget(outfitCheck, true)
    optionsRadio.onSelectionChange = function(widget, selected) onChangeOptions(selected) end

    colorBoxGroup = UIRadioGroup.create()
    for j = 0, 6 do
        for i = 0, 18 do
            local colorBox = g_ui.createWidget("ColorBox", PodiumWindow:recursiveGetChildById("panelcolor"))
            local outfitColor = getOutfitColor(j * 19 + i)
            colorBox:setBackgroundColor(outfitColor)
            colorBox:setId("colorBox" .. j * 19 + i)
            colorBox.colorId = j * 19 + i
            colorBoxGroup:addWidget(colorBox)
        end
    end

    colorBoxGroup.onSelectionChange = onColorCheckChange

    colorModeGroup = UIRadioGroup.create()
    local headButton = PodiumWindow:recursiveGetChildById("HeadButton")
    local primaryButton = PodiumWindow:recursiveGetChildById("PrimaryButton")
    local secondaryButton = PodiumWindow:recursiveGetChildById("SecondaryButton")
    local detailButton = PodiumWindow:recursiveGetChildById("DetailButton")
    colorModeGroup:addWidget(headButton)
    colorModeGroup:addWidget(primaryButton)
    colorModeGroup:addWidget(secondaryButton)
    colorModeGroup:addWidget(detailButton)
    colorModeGroup.onSelectionChange = onColorModeChange
    colorModeGroup:selectWidget(headButton, true)

    showFloorCheck = PodiumWindow:recursiveGetChildById("showfloorCheck")
    showOutfitCheck = PodiumWindow:recursiveGetChildById("showOutfitCheck")
    showMountCheck = PodiumWindow:recursiveGetChildById("mountedCheck")
    showAuraCheck = PodiumWindow:recursiveGetChildById("showAuraCheck")
    showPodiumCheck = PodiumWindow:recursiveGetChildById("podiumCheck")
    addon1Check = PodiumWindow:recursiveGetChildById("addon1Check")
    addon2Check = PodiumWindow:recursiveGetChildById("addon2Check")

    connect(g_game, { onOpenPodiumWindow = onOpenPodiumWindow, onGameEnd = close })
end

function terminate()
    PodiumWindow:hide()
    disconnect(g_game, { onOpenPodiumWindow = onOpenPodiumWindow, onGameEnd = close })
end

function show()
    PodiumWindow:show()
end

function close()
    PodiumWindow:hide()
end

function requestPodiumOutfitData(item)
    -- Renown podium: the server answers ClientConfigureShowOffSocket (0x86) with a 0xC8
    -- window. ProtocolGame::parsePodiumOutfitWindow fires g_game.onOpenPodiumOutfitWindow,
    -- which game_outfit handles (reusing the outfit window in podium mode + applying via
    -- g_game.changePodiumOutfit). This legacy module's own onOpenPodiumWindow stays unused.
    g_game.requestPodiumData(item)
end

function onOpenPodiumWindow(outfit, outfitList, mountList, data, maleOutfits, femaleOutfits, auraList)
    if not PodiumWindow:isVisible() then
        show()
    end

    availableOutfits = {}
    podiumData = data

    local femaleOutfitMap = {}
    for index, outfitId in pairs(femaleOutfits) do
        femaleOutfitMap[outfitId] = index
    end

    local maleOutfitMap = {}
    for index, outfitId in pairs(maleOutfits) do
        maleOutfitMap[outfitId] = index
    end

    for _, outfitData in pairs(outfitList) do
        if outfitData[4] > 0 then
            goto continue
        end

        local outfitName = outfitData[2]
        local outfitId = outfitData[1]
        local addons = outfitData[3]

        if maleOutfitMap[outfitId] then
            local femaleId = femaleOutfits[maleOutfitMap[outfitId]]
            table.insert(availableOutfits, {name = outfitName, male = outfitId, female = femaleId, addons = addons})
            goto continue
        end

        if femaleOutfitMap[outfitId] then
            local maleId = maleOutfits[femaleOutfitMap[outfitId]]
            table.insert(availableOutfits, {name = outfitName, male = maleId, female = outfitId, addons = addons})
            goto continue
        end

        ::continue::
    end

    availableMounts = mountList
    availableAuras = auraList
    local itemWidget = PodiumWindow:recursiveGetChildById("podiumItem")
    itemWidget:setItemId(podiumData.itemId)
    podiumItem = itemWidget:getItem()
    podiumItem:setPodiumDirection(podiumData.direction)
    podiumItem:setOutfit(outfit)

    local search = PodiumWindow:recursiveGetChildById("searchfilter")
    search:clearText(true)
    onShowPodiumOutfits(true)
end

function onShowPodiumOutfits(startup, searchText)
    local typeList = PodiumWindow.ScrollBar.selectionList
    local currentItemOutfit = podiumItem:getOutfit()

    typeList:destroyChildren()
    typeList.onChildFocusChange = nil
    sexRadio:selectWidget(maleButton)

    local currentOutfitChild = nil
    local selectFemale = false

    for _, outfitInfo in pairs(availableOutfits) do
        if searchText and not string.empty(searchText) and not matchText(searchText, outfitInfo.name) then
            goto continue
        end

        local button = g_ui.createWidget("SelectionButton", typeList)
        button.outfit:setOutfit({type = outfitInfo.male, head = currentItemOutfit.head, body = currentItemOutfit.body, legs = currentItemOutfit.legs, feet = currentItemOutfit.feet, addons = outfitInfo.addons})
        button.name:setText(outfitInfo.name)
        button.outfitInfo = outfitInfo

        if currentItemOutfit.type == outfitInfo.male or currentItemOutfit.type == outfitInfo.female then
            currentOutfitChild = button
        end

        if currentItemOutfit.type == outfitInfo.female then
            selectFemale = true
        end

        :: continue ::
    end

    local mountLabel = PodiumWindow:recursiveGetChildById("mountName")
    if #availableMounts > 0 then
        if podiumData.mounted then
            for _, data in pairs(availableMounts) do
                if currentItemOutfit.mount == data[1] then
                    mountLabel:setText(data[2])
                    podiumItem.cachedMountId = currentItemOutfit.mount
                    podiumItem.cachedOutfitId = currentItemOutfit.type
                    break
                end
            end
        else
            mountLabel:setText(availableMounts[1][2])
        end
    end

    if startup then
        optionsRadio:selectWidget(PodiumWindow:recursiveGetChildById("outfitCheck"))
        showOutfitCheck:setChecked(podiumData.showOutfit, false)
        showMountCheck:setChecked(podiumData.mounted, false)
        showAuraCheck:setChecked(podiumData.aura, false)
        showPodiumCheck:setChecked(podiumData.showPodium, false)
        showFloorCheck:setChecked(true)

        local addons = currentItemOutfit.addons
        if addons == 3 then
            addon1Check:setChecked(true)
            addon2Check:setChecked(true)
        elseif addons == 2 then
            addon1Check:setChecked(false)
            addon2Check:setChecked(true)
        elseif addons == 1 then
            addon1Check:setChecked(true)
            addon2Check:setChecked(false)
        else
            addon1Check:setChecked(false)
            addon2Check:setChecked(false)
        end

        if selectFemale then
            sexRadio:selectWidget(femaleButton)
        end
    end

    local targetFocus = currentOutfitChild == nil and typeList:getFirstChild() or currentOutfitChild
    typeList.onChildFocusChange = onOutfitFocusChange
    typeList:focusChild(nil)
    typeList:focusChild(targetFocus)
    typeList:ensureChildVisible(targetFocus)
    colorModeGroup:selectWidget(nil)
    colorModeGroup:selectWidget(PodiumWindow:recursiveGetChildById("HeadButton"))
end

function onShowPodiumMounts(searchText)
    if not podiumItem then
        return
    end

    local typeList = PodiumWindow.ScrollBar.selectionList
    local currentOutfit = podiumItem:getOutfit()
    typeList:destroyChildren()
    typeList:updateScrollBars()

    typeList.onChildFocusChange = nil

    local currentMountChild = nil
    for _, mountInfo in pairs(availableMounts) do
        if searchText and not string.empty(searchText) and not matchText(searchText, mountInfo[2]) then
            goto continue
        end

        local button = g_ui.createWidget("SelectionButton", typeList)
        button.outfit:setOutfit({type = mountInfo[1]})
        button.name:setText(mountInfo[2])
        button.mountInfo = mountInfo

        if currentOutfit.mount == mountInfo[1] then
            currentMountChild = button
        end

        ::continue::
    end

    typeList.onChildFocusChange = onMountFocusChange

    typeList:focusChild(nil)
    typeList:focusChild(currentMountChild and currentMountChild or typeList:getFirstChild())
end

function onShowPodiumAuras(searchText)
    if not podiumItem then
        return
    end

    local typeList = PodiumWindow.ScrollBar.selectionList
    local currentOutfit = podiumItem:getOutfit()
    typeList:destroyChildren()
    typeList:updateScrollBars()

    typeList.onChildFocusChange = nil

    local currentAuraChild = nil
    for _, auraInfo in pairs(availableAuras) do
        if searchText and not string.empty(searchText) and not matchText(searchText, auraInfo[4]) then
            goto continue
        end

        local button = g_ui.createWidget("SelectionButton", typeList)
        local outfit = table.copy(currentOutfit)
        outfit.aura = auraInfo[3]
        outfit.auraCategory = auraInfo[2]
        button.outfit:setOutfit(outfit)

        button.name:setText(auraInfo[4])
        button.auraInfo = auraInfo

        if currentOutfit.aura == auraInfo[3] then
            currentAuraChild = button
        end

        ::continue::
    end

    typeList.onChildFocusChange = onAuraFocusChange

    typeList:focusChild(nil)
    typeList:focusChild(currentAuraChild and currentAuraChild or typeList:getFirstChild())
end

function changeOutfitSex(selected)
    local typeList = PodiumWindow.ScrollBar.selectionList
    for i, widget in pairs(typeList:getChildren()) do
        local outfit = availableOutfits[i]
        if not outfit then
            goto continue
        end

        if selected:getId() == "maleButton" then
            widget.outfit:setOutfit({type = outfit.male, addons = outfit.addons})
        else
            widget.outfit:setOutfit({type = outfit.female, addons = outfit.addons})
        end

        widget.name:setText(outfit.name)
        ::continue::
    end

    typeList:focusChild(nil)
    typeList:focusChild(typeList:getFirstChild())
    typeList:ensureChildVisible(typeList:getFirstChild())
end

function onUpdatePreview(newOutfit)
    if not podiumItem then
        return
    end

    if newOutfit then
        podiumItem:setOutfit(newOutfit)
    end

    podiumItem:setOutfitVisible(showOutfitCheck:isChecked())
    podiumItem:setMountVisible(showMountCheck:isChecked())
    podiumItem:setAuraVisible(showAuraCheck:isChecked())
    podiumItem:setPodiumVisible(showPodiumCheck:isChecked())
    if newOutfit and newOutfit.type > 0 then
        podiumItem.cachedOutfitId = newOutfit.type
    end
end

function onOutfitFocusChange(list, focused)
    if not focused or not podiumItem then
        return
    end

    local outfitInfo = focused.outfitInfo
    local outfitLabel = PodiumWindow:recursiveGetChildById("outfitName")
    outfitLabel:setText(outfitInfo.name)

    local addons = outfitInfo.addons
    addon1Check:setEnabled(addons >= 1)
    addon2Check:setEnabled(addons >= 2)

    local focusedOutfit = table.copy(focused.outfit:getOutfit())
    if focusedOutfit then
        if addon1Check:isChecked() and addon2Check:isChecked() and addons == 3 then
            focusedOutfit.addons = 3
        elseif addon2Check:isChecked() and addons > 1 then
            focusedOutfit.addons = 2
        elseif addon1Check:isChecked() and addons > 0 then
            focusedOutfit.addons = 1
        else
            focusedOutfit.addons = 0
        end

        if podiumItem:getOutfit().mount > 0 then
            focusedOutfit.mount = podiumItem:getOutfit().mount
        end

        onUpdatePreview(focusedOutfit)
    end
end

function onMountFocusChange(list, focused)
    if not focused or not podiumItem then
        return true
    end

    local tmpOutfit = podiumItem:getOutfit()
    local mountLabel = PodiumWindow:recursiveGetChildById("mountName")
    mountLabel:setText(focused.mountInfo[2])

    if showMountCheck:isChecked() and not showOutfitCheck:isChecked() then
        tmpOutfit.type = focused.mountInfo[1]
    elseif showMountCheck:isChecked() and showOutfitCheck:isChecked() then
        tmpOutfit.mount = focused.mountInfo[1]
    end

    podiumItem:setOutfit(tmpOutfit)
    podiumItem:setOutfitVisible(true)
    podiumItem.cachedMountId = focused.mountInfo[1]
end

function onAuraFocusChange(list, focused)
    if not focused or not podiumItem then
        return true
    end

    local tmpOutfit = podiumItem:getOutfit()
    local auraLabel = PodiumWindow:recursiveGetChildById("auraName")
    auraLabel:setText(focused.auraInfo[4])

    if showAuraCheck:isChecked() then
        tmpOutfit.aura = focused.auraInfo[3]
        tmpOutfit.auraCategory = focused.auraInfo[2]

        if showMountCheck:isChecked() then
          showMountCheck:setChecked(false)
        end
    end

    podiumItem:setOutfit(tmpOutfit)
    podiumItem:setOutfitVisible(showAuraCheck:isChecked() and showOutfitCheck:isChecked())
    podiumItem.cachedAuraId = focused.auraInfo[1]
    podiumItem.cachedAuraCid = focused.auraInfo[3]
    podiumItem.cachedAuraCat = focused.auraInfo[2]
end

function onChangeOptions(focused)
    local grayHover = PodiumWindow:recursiveGetChildById("grayHover")

    if focused:getId() == "outfitCheck" then
        onShowPodiumOutfits(false)
        grayHover:setVisible(false)
        femaleButton:setVisible(true)
        maleButton:setVisible(true)
    elseif focused:getId() == "mountCheck" then
        onShowPodiumMounts()
        grayHover:setVisible(true)
        femaleButton:setVisible(false)
        maleButton:setVisible(false)
    elseif focused:getId() == "presetCheck" then
        -- TODO presets
    elseif focused:getId() == "auraCheck" then
        onShowPodiumAuras()
        grayHover:setVisible(true)
        femaleButton:setVisible(false)
        maleButton:setVisible(false)
    end
end

function onVisibleOutfit(state)
    if not podiumItem then
        return
    end

    if not showMountCheck:isChecked() then
        podiumItem:setOutfitVisible(state)
        return
    end

    podiumItem:setOutfitVisible(true)
    local tmpOutfit = podiumItem:getOutfit()
    tmpOutfit.type = state and podiumItem.cachedOutfitId or tmpOutfit.mount
    tmpOutfit.mount = state and podiumItem.cachedMountId or 0
    podiumItem:setOutfit(tmpOutfit)
end

function onVisibleMount(state)
    if not podiumItem then
        return
    end

    local typeList = PodiumWindow.ScrollBar.selectionList
    local focusedWidget = typeList:getFocusedChild()
    if not focusedWidget then
        return
    end

    podiumItem:setMountVisible(state)

    podiumData.mounted = state
    if optionsRadio:getSelectedWidget():getId() ~= "mountCheck" then
        local tmpOutfit = podiumItem:getOutfit()
        tmpOutfit.mount = state and podiumItem.cachedMountId or 0
        if tmpOutfit.mount > 0 then
            podiumItem.cachedMountId = tmpOutfit.mount
        end

        podiumItem:setOutfit(tmpOutfit)
        return
    end

    local tmpOutfit = podiumItem:getOutfit()
    if showOutfitCheck:isChecked() then
        tmpOutfit.mount = state and focusedWidget.mountInfo[1] or 0
        podiumItem.cachedMountId = tmpOutfit.mount
    else
        podiumItem.cachedOutfitId = tmpOutfit.type
        tmpOutfit.type = state and focusedWidget.mountInfo[1] or 0
    end

    podiumItem:setOutfit(tmpOutfit)
end

function onVisibleFloor(state)
    local widget = PodiumWindow:recursiveGetChildById("previewoutfit")
    if not widget then
        return
    end

    widget:setImageSource(state and "/images/game/outfit_ground" or "")
end

function onAuraButton(state)
    -- if not podiumItem then
    --     return
    -- end

    -- local tmpOutfit = podiumItem:getOutfit()
    -- if not state then
    --     tmpOutfit.aura = 0
    --     tmpOutfit.auraCategory = 0
    -- else
    --     local typeList = PodiumWindow.ScrollBar.selectionList
    --     local focusedWidget = typeList:getFocusedChild()
    --     if not focusedWidget then
    --         return
    --     end

    --     tmpOutfit.aura = focusedWidget.auraInfo[3]
    --     tmpOutfit.auraCategory = focusedWidget.auraInfo[2]
    -- end
    -- podiumItem:setOutfit(tmpOutfit)
end

function onAddon1Button(state)
    if not podiumItem then
        return
    end

    local tmpOutfit = podiumItem:getOutfit()
    if state and addon2Check:isChecked() then
        tmpOutfit.addons = 3
    elseif state and not addon2Check:isChecked() then
        tmpOutfit.addons = 2
    elseif not state and addon2Check:isChecked() then
        tmpOutfit.addons = 2
    elseif not state and not addon2Check:isChecked() then
        tmpOutfit.addons = 0
    end
    podiumItem:setOutfit(tmpOutfit)
end

function onAddon2Button(state)
    if not podiumItem then
        return
    end

    local tmpOutfit = podiumItem:getOutfit()
    if state and addon1Check:isChecked() then
        tmpOutfit.addons = 3
    elseif state and not addon1Check:isChecked() then
        tmpOutfit.addons = 2
    elseif not state and addon1Check:isChecked() then
        tmpOutfit.addons = 1
    elseif not state and not addon1Check:isChecked() then
        tmpOutfit.addons = 0
    end
    podiumItem:setOutfit(tmpOutfit)
end

function rotatePreview(isRight)
    if not podiumItem then
        return true
    end

	local currentDirection = podiumItem:getPodiumDir()
	if isRight then
		if currentDirection == 0 then
			podiumItem:setPodiumDirection(3)
		else
			podiumItem:setPodiumDirection(currentDirection - 1)
		end
	else
		if currentDirection >= 3 then
			podiumItem:setPodiumDirection(0)
		else
			podiumItem:setPodiumDirection(currentDirection + 1)
		end
	end
end

function onColorModeChange(widget, selectedWidget)
    if not podiumItem or not selectedWidget then
        return
    end

    local colorMode = selectedWidget:getId()
    local tmpOutfit = podiumItem:getOutfit()

    if colorMode == "HeadButton" then
        selectedWidget:getParent():setImageClip("0 0 253 18")
        if optionsRadio:getSelectedWidget() == PodiumWindow.appearance.mountCheck then
            colorBoxGroup:selectWidget(PodiumWindow.appearance.panelcolor["colorBox" .. tmpOutfit.mountHead])
        else
            colorBoxGroup:selectWidget(PodiumWindow.appearance.panelcolor["colorBox" .. tmpOutfit.head])
        end

    elseif colorMode == "PrimaryButton" then
        selectedWidget:getParent():setImageClip("0 18 253 18")
        if optionsRadio:getSelectedWidget() == PodiumWindow.appearance.mountCheck then
            colorBoxGroup:selectWidget(PodiumWindow.appearance.panelcolor["colorBox" .. tmpOutfit.mountBody])
        else
            colorBoxGroup:selectWidget(PodiumWindow.appearance.panelcolor["colorBox" .. tmpOutfit.body])
        end

    elseif colorMode == "SecondaryButton" then
        selectedWidget:getParent():setImageClip("0 36 253 18")
        if optionsRadio:getSelectedWidget() == PodiumWindow.appearance.mountCheck then
            colorBoxGroup:selectWidget(PodiumWindow.appearance.panelcolor["colorBox" .. tmpOutfit.mountLegs])
        else
            colorBoxGroup:selectWidget(PodiumWindow.appearance.panelcolor["colorBox" .. tmpOutfit.legs])
        end

    elseif colorMode == "DetailButton" then
        selectedWidget:getParent():setImageClip("0 54 253 18")
        if optionsRadio:getSelectedWidget() == PodiumWindow.appearance.mountCheck then
            colorBoxGroup:selectWidget(PodiumWindow.appearance.panelcolor["colorBox" .. tmpOutfit.mountFeet])
        else
            colorBoxGroup:selectWidget(PodiumWindow.appearance.panelcolor["colorBox" .. tmpOutfit.feet])
        end
    end
end

function onColorCheckChange(widget, selectedWidget)
    local colorId = selectedWidget.colorId
    local colorMode = colorModeGroup:getSelectedWidget():getId()

    if currentColorBox then
        currentColorBox:setBorderWidth(0)
        currentColorBox:setBorderColor("alpha")
        currentColorBox:setChecked(false)
    end

    selectedWidget:setBorderWidth(1)
    selectedWidget:setBorderColor("white")
    currentColorBox = selectedWidget

    if not podiumItem then
        return
    end

    local tmpOutfit = podiumItem:getOutfit()
    if colorMode == "HeadButton" then
        if optionsRadio:getSelectedWidget() == PodiumWindow.appearance.mountCheck then
            tmpOutfit.mountHead = colorId
        else
            tmpOutfit.head = colorId
        end
    elseif colorMode == "PrimaryButton" then
        if optionsRadio:getSelectedWidget() == PodiumWindow.appearance.mountCheck then
            tmpOutfit.mountBody = colorId
        else
            tmpOutfit.body = colorId
        end
    elseif colorMode == "SecondaryButton" then
        if optionsRadio:getSelectedWidget() == PodiumWindow.appearance.mountCheck then
            tmpOutfit.mountLegs = colorId
        else
            tmpOutfit.legs = colorId
        end
    elseif colorMode == "DetailButton" then
        if optionsRadio:getSelectedWidget() == PodiumWindow.appearance.mountCheck then
            tmpOutfit.mountFeet = colorId
        else
            tmpOutfit.feet = colorId
        end
    end

    podiumItem:setOutfit(tmpOutfit)
    local typeList = PodiumWindow.ScrollBar.selectionList
    for i, widget in pairs(typeList:getChildren()) do
        local widgetOutfit = widget.outfit:getOutfit()
        widgetOutfit.mountHead = tmpOutfit.mountHead
        widgetOutfit.mountBody = tmpOutfit.mountBody
        widgetOutfit.mountLegs = tmpOutfit.mountLegs
        widgetOutfit.mountFeet = tmpOutfit.mountFeet

        widgetOutfit.head = tmpOutfit.head
        widgetOutfit.body = tmpOutfit.body
        widgetOutfit.legs = tmpOutfit.legs
        widgetOutfit.feet = tmpOutfit.feet
        widget.outfit:setOutfit(widgetOutfit)
    end
end

function onChoosePodiumOutfit()
    if not podiumItem then
        return
    end

    local outfit = podiumItem:getOutfit()
    outfit.type = showOutfitCheck:isChecked() and podiumItem.cachedOutfitId or 0
    outfit.mount = showMountCheck:isChecked() and podiumItem.cachedMountId or 0
    local isAuraChecked = showAuraCheck:isChecked()
    if not isAuraChecked then
        outfit.auraId = 0
    else
        outfit.auraId = podiumItem.cachedAuraId
        outfit.auraCategory = podiumItem.cachedAuraCat
        outfit.aura = podiumItem.cachedAuraCid
    end

    g_game.changePodiumOutfit(outfit, podiumData.pos, podiumData.itemId, podiumItem:getPodiumDir(), showPodiumCheck:isChecked())
    close()
end

function onFilterSearch(widget)
    if outfitCheck:isChecked() then
        onShowPodiumOutfits(false, widget:getText())
    elseif mountCheck:isChecked() then
        onShowPodiumMounts(widget:getText())
    end
end
