MapCyclopedia = {}
MapCyclopedia.__index = MapCyclopedia
MapCyclopedia.currentArea = 0
MapCyclopedia.currentAreaName = ''
MapCyclopedia.askWindow = nil
MapCyclopedia.preference = 'minimap'
MapCyclopedia.cityLabels = {}

function MapCyclopedia.getMinimapWidget()
    if not VisibleCyclopediaPanel or VisibleCyclopediaPanel:isDestroyed() or
        VisibleCyclopediaPanel:getId() ~= 'MapDataPanel' then return nil end
    return VisibleCyclopediaPanel:recursiveGetChildById('minimap')
end

function MapCyclopedia.updateViewMode()
    local map = MapCyclopedia.getMinimapWidget()
    if not map or not MinimapViewCheckBox then return end
    local floor = map:getCameraPosition().z
    local available = map.setSurfaceMode ~= nil and g_minimap.hasSatellitePack and g_minimap.hasSatellitePack() and floor <= 7
    local surface = available and MapCyclopedia.preference == 'satellite'
    local view = surface and 'satellite' or 'minimap'
    local oldView = map.currentView
    if oldView and oldView ~= view then MapCyclopedia.zooms[oldView] = map:getZoom() end
    -- Deselect before disabling (the radio group must be able to uncheck).
    MinimapViewCheckBox:selectWidget(surface and MapCyclopedia.surfaceView or MapCyclopedia.mapView, true)
    MapCyclopedia.surfaceView:setEnabled(available)
    MapCyclopedia.surfaceView:setTooltip(available and 'PNG satellite view (independent of HUD HD)' or 'Surface needs the updated executable and a matching HD pack; floors 0-7 only')
    map:setCurrentView(view)
    if oldView ~= view then map:setZoom(tonumber(MapCyclopedia.zooms[view]) or -1) end
    map:setColor(floor <= 7 and '#274DA6' or '#000000')
    MapCyclopedia.separator:setEnabled(surface and floor < 7)
    VisibleCyclopediaPanel:recursiveGetChildById('levelSeparatorLabel'):setEnabled(surface and floor < 7)
    MapCyclopedia.updateFloorImage(floor)
    MapCyclopedia.queueLabels()
end

function MapCyclopedia.terminatePanel()
    local map = MapCyclopedia.getMinimapWidget()
    if MapCyclopedia.labelEvent then removeEvent(MapCyclopedia.labelEvent); MapCyclopedia.labelEvent = nil end
    if map then
        map:save()
        MapCyclopedia.camera = map:getCameraPosition()
        MapCyclopedia.zooms[map.currentView or 'minimap'] = map:getZoom()
        g_settings.setNode('CyclopediaMap', {view = MapCyclopedia.preference,
            zooms = MapCyclopedia.zooms, camera = MapCyclopedia.camera,
            separator = MapCyclopedia.separator:getValue(), labels = MapCyclopedia.labelsEnabled,
            ignoredMarks = map.ignoredMarks or {}, hiddenMarks = map.hiddenCatalogMarks or {}})
        if map.setSurfaceMode then map:setSurfaceMode(false) end
    end
    MapCyclopedia.cityWidgets = {}
end

function MapCyclopedia.loadCityLabels()
    MapCyclopedia.cityLabels = {}
    if not g_resources.fileExists('/data/minimap_hd/cities.json') then return end
    local ok, labels, source = pcall(function()
        return json.decode(g_resources.readFileContents('/data/minimap_hd/cities.json')),
            json.decode(g_resources.readFileContents('/data/minimap_hd/source.json'))
    end)
    if not ok or type(labels) ~= 'table' or type(source) ~= 'table' or labels.format ~= 1 or
        labels.world_sha256 ~= source.world_sha256 or type(labels.world_sha256) ~= 'string' or
        #labels.world_sha256 ~= 64 or not labels.world_sha256:match('^[a-fA-F0-9]+$') or
        type(labels.labels) ~= 'table' or #labels.labels > 1024 then
        g_logger.warning('[Cyclopedia] City labels do not match the installed pack; labels disabled')
        return
    end
    local ids = {}
    for _, label in ipairs(labels.labels) do
        local p = type(label) == 'table' and label.position
        if type(label) == 'table' and type(label.id) == 'string' and #label.id <= 80 and not ids[label.id] and type(label.name) == 'string' and
            #label.name > 0 and #label.name <= 80 and type(p) == 'table' and
            type(p.x) == 'number' and type(p.y) == 'number' and type(p.z) == 'number' and
            p.x > 0 and p.x <= 65535 and p.y > 0 and p.y <= 65535 and p.z >= 0 and p.z <= 7 and
            p.x == math.floor(p.x) and p.y == math.floor(p.y) and p.z == math.floor(p.z) then
            ids[label.id] = true
            local priority, minZoom = tonumber(label.priority), tonumber(label.minZoom)
            label.priority = priority and priority >= -100000 and priority <= 100000 and priority or 0
            label.minZoom = minZoom and minZoom >= -8 and minZoom <= 8 and minZoom or -8
            MapCyclopedia.cityLabels[#MapCyclopedia.cityLabels + 1] = label
        end
    end
    table.sort(MapCyclopedia.cityLabels, function(a, b)
        if a.priority ~= b.priority then return a.priority > b.priority end
        return a.id < b.id
    end)
end

function MapCyclopedia.queueLabels()
    if MapCyclopedia.labelEvent then return end
    MapCyclopedia.labelEvent = scheduleEvent(function()
        MapCyclopedia.labelEvent = nil
        MapCyclopedia.updateLabels()
    end, 1)
end

function MapCyclopedia.updateLabels()
    local map = MapCyclopedia.getMinimapWidget()
    if not map then return end
    for _, widget in ipairs(MapCyclopedia.cityWidgets) do widget:hide() end
    if not MapCyclopedia.labelsEnabled or map:getCameraPosition().z > 7 then return end
    local used, boxes, bounds = 0, {}, map:getRect()
    for _, label in ipairs(MapCyclopedia.cityLabels) do
        if map:getZoom() >= label.minZoom then
            local pos = {x = label.position.x, y = label.position.y, z = map:getCameraPosition().z}
            local point = map:getTilePoint(pos)
            if point.x >= bounds.x and point.x <= bounds.x + bounds.width and point.y >= bounds.y and point.y <= bounds.y + bounds.height then
                local widget = MapCyclopedia.cityWidgets[used + 1]
                if not widget then
                    widget = g_ui.createWidget('CyclopediaCityLabel', map)
                    MapCyclopedia.cityWidgets[used + 1] = widget
                end
                widget:hide()
                widget:setText(label.name)
                widget:resizeToText()
                local box = {x = point.x - widget:getWidth()/2 - 3, y = point.y - widget:getHeight()/2 - 2,
                    width = widget:getWidth() + 6, height = widget:getHeight() + 4}
                local overlap = false
                for _, other in ipairs(boxes) do
                    if box.x < other.x + other.width and box.x + box.width > other.x and
                        box.y < other.y + other.height and box.y + box.height > other.y then overlap = true; break end
                end
                if not overlap then
                    used = used + 1
                    boxes[#boxes + 1] = box
                    map:centerInPosition(widget, pos)
                    widget:show()
                    if used == 32 then break end
                end
            end
        end
    end
end

MapCyclopedia.setup = function()
    MapCyclopedia.currentArea = 0
    MapCyclopedia.currentAreaName = ''
    -- Use already-received resource values. Rendering a local map requires no
    -- balance request or network round-trip on every open.

    local player = g_game.getLocalPlayer()
    local bankMoney = player and player:getResourceValue(ResourceBank) or 0
    local characterMoney = player and player:getResourceValue(ResourceInventary) or 0

    cyclopediaWindow:recursiveGetChildById('coinsAmount'):setText(comma_value(bankMoney + characterMoney))

    VisibleCyclopediaPanel = g_ui.createWidget('MapDataPanel', cyclopediaWindow.optionsPanel)
    VisibleCyclopediaPanel:setId('MapDataPanel')

    if MinimapViewCheckBox then
        MinimapViewCheckBox:destroy()
        MinimapViewCheckBox = nil
    end

    local minimap = VisibleCyclopediaPanel:recursiveGetChildById('minimap')
    if minimap then
        minimap.surfaceComposite = true
        -- Share in-memory OTMM and the indexed PNG cache. No save/clean/reload.
        if minimap.setSurfaceMode and g_minimap.loadSatellitePack and not g_minimap.hasSatellitePack() and
            g_resources.fileExists('/data/minimap_hd/index.txt') then g_minimap.loadSatellitePack('/data/minimap_hd') end
        local settings = g_settings.getNode('CyclopediaMap') or {}
        MapCyclopedia.preference = settings.view == 'satellite' and 'satellite' or 'minimap'
        MapCyclopedia.zooms = settings.zooms or {minimap = -1, satellite = -1}
        MapCyclopedia.labelsEnabled = settings.labels ~= false
        MapCyclopedia.cityWidgets = {}
        minimap:load()
        minimap.ignoredMarks = settings.ignoredMarks or {}
        minimap.hiddenCatalogMarks = settings.hiddenMarks or {}
        local position = player and player:getPosition() or {x = 32768, y = 32768, z = 7}
        minimap:setCameraPosition(settings.camera or position)
        minimap:setCrossPosition(position)
        minimap:setZoom(tonumber(MapCyclopedia.zooms[MapCyclopedia.preference]) or -1)
        minimap.onCameraPositionChange = function(self, newPos, oldPos)
            UIRealMinimap.onCameraPositionChange(self, newPos)
            self:refreshMarks()
            MapCyclopedia.updateViewMode()
        end
        minimap.onZoomChange = function(self, zoom)
            UIRealMinimap.onZoomChange(self, zoom)
            self:refreshMarks()
            MapCyclopedia.queueLabels()
        end
        minimap.onGeometryChange = function(self) self:refreshMarks(); MapCyclopedia.queueLabels() end

        MinimapViewCheckBox = UIRadioGroup.create()
        MinimapViewCheckBox.onSelectionChange = function(widget, selectedWidget)
            if not selectedWidget or minimap:isDestroyed() then return end
            MapCyclopedia.zooms[minimap.currentView or 'minimap'] = minimap:getZoom()
            MapCyclopedia.preference = selectedWidget:getId() == 'surfaceView' and 'satellite' or 'minimap'
            MapCyclopedia.updateViewMode()
            minimap:setZoom(tonumber(MapCyclopedia.zooms[minimap.currentView]) or -1)
        end

        MapCyclopedia.surfaceView = VisibleCyclopediaPanel:recursiveGetChildById('surfaceView')
        MapCyclopedia.mapView = VisibleCyclopediaPanel:recursiveGetChildById('mapView')

        MinimapViewCheckBox:addWidget(MapCyclopedia.surfaceView)
        MinimapViewCheckBox:addWidget(MapCyclopedia.mapView)

        MapCyclopedia.separator = VisibleCyclopediaPanel:recursiveGetChildById('levelSeparatorScroll')
        MapCyclopedia.separator:setValue(math.max(0, math.min(100, tonumber(settings.separator) or 100)))
        minimap:setLevelSeparator(MapCyclopedia.separator:getValue())
        MapCyclopedia.separator.onValueChange = function(self, value) minimap:setLevelSeparator(value) end
        local labels = VisibleCyclopediaPanel:recursiveGetChildById('cityLabels')
        labels:setChecked(MapCyclopedia.labelsEnabled)
        labels.onCheckChange = function(self, checked) MapCyclopedia.labelsEnabled = checked; MapCyclopedia.queueLabels() end
        MapCyclopedia.loadCityLabels()
        MapCyclopedia.updateViewMode()
        RealMap.setUIMarkers(minimap)

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
    if newPos then minimap:setCrossPosition(newPos) end -- Do not change the browsed virtual floor.
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
    MapCyclopedia.floor(true)
end

MapCyclopedia.floorDown = function()
    MapCyclopedia.floor(false)
end

function MapCyclopedia.updateFloorImage(posZ)
    local floorPos = VisibleCyclopediaPanel:recursiveGetChildById('floorPosition')
    if floorPos then
        floorPos:setImageClip((posZ * 14) .. " 0 14 67")
    end
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
    return MapCyclopedia.getMinimapWidget()
end

function MapCyclopedia.onChangeButtonMarks(button, i, desired)
    local map = MapCyclopedia.getMinimapWidget()
    if not map then return end
    local path = icon[i]
    if not path or path == '' then button:setEnabled(false); return end
    local checked = desired
    if checked == nil then checked = not button:isChecked() end
    button:setChecked(checked)
    button:setImageClip(checked and '0 20 43 20' or '0 0 43 20')
    if checked then map:unignoreWidget(path) else map:ignoreWidget(path) end
end

function MapCyclopedia.syncMarkFilters()
    local map = MapCyclopedia.getMinimapWidget()
    if not map then return end
    local all = true
    for i, path in ipairs(icon) do
        local button = VisibleCyclopediaPanel:recursiveGetChildById('marksButton' .. i)
        if button then
            if path ~= '' then
                local checked = not map:isWidgetIgnored(path)
                MapCyclopedia.onChangeButtonMarks(button, i, checked)
                if not checked then all = false end
            else button:setEnabled(false) end
        end
    end
    VisibleCyclopediaPanel:recursiveGetChildById('markShowall'):setChecked(all)
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
