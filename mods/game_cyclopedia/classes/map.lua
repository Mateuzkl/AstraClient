MapCyclopedia = {}
MapCyclopedia.__index = MapCyclopedia
MapCyclopedia.currentArea = 0
MapCyclopedia.currentAreaName = ''
MapCyclopedia.askWindow = nil

MapCyclopedia.setup = function()
    MapCyclopedia.currentArea = 0
    MapCyclopedia.currentAreaName = ''
    g_game.requestResource(ResourceBank)
    g_game.requestResource(ResourceInventary)

    local player = g_game.getLocalPlayer()
    local bankMoney = player:getResourceValue(ResourceBank)
    local characterMoney = player:getResourceValue(ResourceInventary)

    cyclopediaWindow:recursiveGetChildById('coinsAmount'):setText(comma_value(bankMoney + characterMoney))

    VisibleCyclopediaPanel = g_ui.createWidget('MapDataPanel', cyclopediaWindow.optionsPanel)
    VisibleCyclopediaPanel:setId('MapDataPanel')

    if MinimapViewCheckBox then
        MinimapViewCheckBox:destroy()
        MinimapViewCheckBox = nil
    end

    local minimap = VisibleCyclopediaPanel:recursiveGetChildById('minimap')
    if minimap then
        -- Save live minimap to disk and load into cyclopedia widget (avoids per-flag packet flood)
        g_minimap.saveOtmm('/minimap.otmm')
        g_minimap.loadOtmm('/minimap.otmm')
        minimap:load()
        minimap:setCameraPosition(g_game.getLocalPlayer():getPosition())
        minimap:setCrossPosition(g_game.getLocalPlayer():getPosition(), true)
        minimap:setZoom(2)

        minimap.view = "satellite"

        minimap.onFloorChange = function(self, newPos, oldPos)
            MapCyclopedia.updateFloorImage(minimap:getCameraPosition().z)
            if newPos.z > 7 then
                minimap:setCurrentView("minimap")
                minimap:setBackgroundColor("#000000ff")
                MinimapViewCheckBox:selectWidget(MapCyclopedia.mapView)
                MapCyclopedia.surfaceView:setEnabled(false)
            else
                minimap:setCurrentView(minimap.view)
                minimap:setBackgroundColor("#274DA6")
                if not MapCyclopedia.surfaceView:isEnabled() then
                    MapCyclopedia.surfaceView:setEnabled(true)
                end
            end
        end

        MinimapViewCheckBox = UIRadioGroup.create()
        MinimapViewCheckBox.onSelectionChange = function(widget, selectedWidget)
            if selectedWidget:getId() == 'surfaceView' then
                minimap:setCurrentView("satellite")
                minimap.view = "satellite"
            else
                minimap:setCurrentView("minimap")
                minimap.view = "minimap"
            end

            local localPlayer = g_game.getLocalPlayer()
            local localPlayerPos = localPlayer:getPosition()
            MapCyclopedia.updatePlayerPosition(localPlayer, localPlayerPos, localPlayerPos)
        end

        MapCyclopedia.surfaceView = VisibleCyclopediaPanel:recursiveGetChildById('surfaceView')
        MapCyclopedia.mapView = VisibleCyclopediaPanel:recursiveGetChildById('mapView')

        MinimapViewCheckBox:addWidget(MapCyclopedia.surfaceView)
        MinimapViewCheckBox:addWidget(MapCyclopedia.mapView)

        local playerPosition = g_game.getLocalPlayer():getPosition() or {x = 0, y = 0, z = 0}

        MinimapViewCheckBox:selectWidget(playerPosition.z <= 7 and MapCyclopedia.surfaceView or MapCyclopedia.mapView)
        MinimapViewCheckBox.onSelectionChange(MinimapViewCheckBox, MinimapViewCheckBox:getSelectedWidget())

        local zoomInButton = VisibleCyclopediaPanel:recursiveGetChildById('zoomInWidget')
        local zoomOutButton = VisibleCyclopediaPanel:recursiveGetChildById('zoomOutWidget')

        if zoomInButton then
            zoomInButton.onClick = MapCyclopedia.zoomIn
        end

        if zoomOutButton then
            zoomOutButton.onClick = MapCyclopedia.zoomOut
        end

        local floorUpButton = VisibleCyclopediaPanel:recursiveGetChildById('floorUp')
        local floorDownButton = VisibleCyclopediaPanel:recursiveGetChildById('floorDown')

        if floorUpButton then
            floorUpButton.onClick = function() MapCyclopedia.floor(true) end
        end

        if floorDownButton then
            floorDownButton.onClick = function() MapCyclopedia.floor(false) end
        end

        local floorPosition = VisibleCyclopediaPanel:recursiveGetChildById('floorPosition')
        if floorPosition then
            floorPosition.onMouseWheel = function(self, mousePos, direction)
                if direction == MouseWheelUp then
                    MapCyclopedia.floor(true)
                else
                    MapCyclopedia.floor(false)
                end
                
                return true
            end
        end
    end
end

MapCyclopedia.updatePlayerPosition = function(localPlayer, newPos, oldPos)
    if not VisibleCyclopediaPanel then
        return
    end
    local minimap = VisibleCyclopediaPanel:recursiveGetChildById('minimap')
    if not minimap then
        return
    end
    RealMap.setCrossPosition(minimap, g_game.getLocalPlayer():getPosition())

    if newPos.z > 7 then
        minimap:setCurrentView("minimap")
        minimap:setBackgroundColor("#000000ff")
        MinimapViewCheckBox:selectWidget(MapCyclopedia.mapView)
        MapCyclopedia.surfaceView:setEnabled(false)
    else
        minimap:setCurrentView(minimap.view)
        minimap:setBackgroundColor("#274DA6")
        if not MapCyclopedia.surfaceView:isEnabled() then
            MapCyclopedia.surfaceView:setEnabled(true)
        end
    end
end

MapCyclopedia.zoomIn = function()
    local minimap = VisibleCyclopediaPanel:recursiveGetChildById('minimap')
    if minimap then
        local currentZoom = minimap:getZoom()
        minimap:setZoom(currentZoom + 1)
    end
end

MapCyclopedia.zoomOut = function()
    local minimap = VisibleCyclopediaPanel:recursiveGetChildById('minimap')
    if minimap then
        local currentZoom = minimap:getZoom()
        minimap:setZoom(currentZoom - 1)
    end
end

MapCyclopedia.floorUp = function()
    local minimap = VisibleCyclopediaPanel:recursiveGetChildById('minimap')
    if minimap then
        local currentFloor = minimap:getFloor()
        minimap:setFloor(currentFloor - 1)
    end
end

MapCyclopedia.floorDown = function()
    local minimap = VisibleCyclopediaPanel:recursiveGetChildById('minimap')
    if minimap then
        local currentFloor = minimap:getFloor()
        minimap:setFloor(currentFloor + 1)
    end
end

function MapCyclopedia.updateFloorImage(posZ)
    local floorPos = VisibleCyclopediaPanel:recursiveGetChildById('floorPosition')
    if floorPos then
        floorPos:setImageClip((posZ * 14) .. " 0 14 67")
    end
end

function MapCyclopedia.getMinimapWidget()
    return VisibleCyclopediaPanel:recursiveGetChildById('minimap')
end

function MapCyclopedia.floor(bool)
    local minimap = VisibleCyclopediaPanel:recursiveGetChildById('minimap')
    if minimap then
        if bool then
            minimap:floorUp(1)
        else
            minimap:floorDown(1)
        end
        MapCyclopedia.updateFloorImage(minimap:getCameraPosition().z)
    end
end

local icon = {
    [1] = "data/images/game/minimap/flag0.png",
    [2] = "data/images/game/minimap/flag1.png",
    [3] = "data/images/game/minimap/flag2.png",
    [4] = "data/images/game/minimap/flag3.png",
    [5] = "data/images/game/minimap/flag4.png",
    [6] = "",
    [7] = "data/images/game/minimap/flag5.png",
    [8] = "data/images/game/minimap/flag6.png",
    [9] = "data/images/game/minimap/flag7.png",
    [10] = "data/images/game/minimap/flag8.png",
    [11] = "data/images/game/minimap/flag9.png",
    [12] = "",
    [13] = "data/images/game/minimap/flag10.png",
    [14] = "data/images/game/minimap/flag11.png",
    [15] = "data/images/game/minimap/flag12.png",
    [16] = "data/images/game/minimap/flag13.png",
    [17] = "data/images/game/minimap/flag14.png",
    [18] = "",
    [19] = "data/images/game/minimap/flag15.png",
    [20] = "data/images/game/minimap/flag16.png",
    [21] = "data/images/game/minimap/flag17.png",
    [22] = "data/images/game/minimap/flag18.png",
    [23] = "data/images/game/minimap/flag19.png",
}

function MapCyclopedia.getWidget()
    return VisibleCyclopediaPanel:recursiveGetChildById('minimap')
end

function MapCyclopedia.onChangeButtonMarks(button, i)
    local icon = icon[i]
    local isChecked = button:isChecked()
    local minimap = VisibleCyclopediaPanel:recursiveGetChildById('minimap')
    if minimap.ignoreWidget then minimap:ignoreWidget(icon) end
    if isChecked then
        button:setImageClip("0 0 43 20")
        button:setChecked(false)
    else
        button:setImageClip("0 20 43 20")
        button:setChecked(true)
        if minimap.unignoreWidget then minimap:unignoreWidget(icon) end
    end
end

function MapCyclopedia.onChangeArea(areaName, subAreaName)
    if not VisibleCyclopediaPanel then
        return true
    end

    local areaWidget = VisibleCyclopediaPanel:recursiveGetChildById('areaorsub')
    if areaWidget then
        areaWidget:getParent():ensureChildVisible(areaWidget)
    end

    local areaNameWidget = VisibleCyclopediaPanel:recursiveGetChildById('nameSubarea')
    if areaNameWidget then
        areaNameWidget:setText(areaName)
    end

    MapCyclopedia.currentAreaName = areaName

    local subAreaNameWidget = VisibleCyclopediaPanel:recursiveGetChildById('respawnText')
    if subAreaNameWidget then
        subAreaNameWidget:setText(subAreaName)
    end
end

function MapCyclopedia.setImprovevedValue(areaId)
    if not VisibleCyclopediaPanel then
        return true
    end

    local areaId = g_things.getAreaById(areaId)
    if areaId == 0 then
        return
    end

    local donateAmountTextEdit = VisibleCyclopediaPanel:recursiveGetChildById('donateAmountTextEdit')
    if donateAmountTextEdit then
        donateAmountTextEdit:setText('')
    end

    local maps = g_game.getBoostedAreas()
    local improved = maps[areaId]

    local totalGoldDonate = VisibleCyclopediaPanel:recursiveGetChildById('totalGoldDonate')
    if totalGoldDonate then
        totalGoldDonate:setText(comma_value(improved.second))
    end

    local progressBox = VisibleCyclopediaPanel:recursiveGetChildById('progressBox')
    if progressBox then
        progressBox:setValue(improved.second, 0, g_game.getMapBoostPrice())
        progressBox:setTooltip(string.format("%s of %s gold donated -\nYour game world needs to donate at least %s gold\nto be able to win the Improved Respawn Rate for this area.", comma_value(improved.second), comma_value(g_game.getMapBoostPrice()), comma_value(g_game.getMapBoostPrice())))
    end

    MapCyclopedia.currentArea = areaId
end

function MapCyclopedia.onDonateTextChange(value)
    local player = g_game.getLocalPlayer()
    local bankMoney = player:getResourceValue(ResourceBank)
    local characterMoney = player:getResourceValue(ResourceInventary)

    local donateButton = VisibleCyclopediaPanel:recursiveGetChildById('donateButton')
    if value > 0 and value <= (bankMoney + characterMoney) and MapCyclopedia.currentArea ~= 0 then
        donateButton:setEnabled(true)
    else
        donateButton:setEnabled(false)
    end
end

function MapCyclopedia.onDonateClick()
    local donateValue = VisibleCyclopediaPanel:recursiveGetChildById('donateAmountTextEdit'):getText()
    if donateValue == '' then
        return
    end

    local donateValue = tonumber(donateValue)
    if donateValue == nil then
        return
    end

    local player = g_game.getLocalPlayer()
    local bankMoney = player:getResourceValue(ResourceBank)
    local characterMoney = player:getResourceValue(ResourceInventary)

    if donateValue > (bankMoney + characterMoney) then
        return
    end

    if MapCyclopedia.askWindow then
        MapCyclopedia.askWindow:destroy()
        MapCyclopedia.askWindow = nil
    end

    local noCallback = function() VisibleCyclopediaPanel:recursiveGetChildById('donateAmountTextEdit'):setText('') g_client.setInputLockWidget(nil) MapCyclopedia.askWindow:destroy() MapCyclopedia.askWindow = nil cyclopediaWindow:setVisible(true) end
    local yesCallback = function() g_game.doDonateMap(MapCyclopedia.currentArea, donateValue) noCallback() end

    local text = string.format("Do you really want to donate %s gold coins for %s?", comma_value(donateValue), MapCyclopedia.currentAreaName)
    local title = "Information"

    MapCyclopedia.askWindow = displayGeneralBox(title, text,
        { { text=tr('Yes'), callback=yesCallback },
        { text=tr('No'), callback=noCallback },
    }, yesCallback, noCallback)

    cyclopediaWindow:setVisible(false)
    g_client.setInputLockWidget(MapCyclopedia.askWindow)
end
