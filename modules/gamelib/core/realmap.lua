if not RealMap then
    RealMap = {
        loaded = false,
        settings = {},
    }
end

local flagToFilePath = {
  ["up"] = "data/images/game/minimap/flag18.png",
  ["flag"] = "data/images/game/minimap/flag9.png",
  ["skull"] = "data/images/game/minimap/flag12.png",
  ["crossmark"] = "data/images/game/minimap/flag4.png",
  ["star"] = "data/images/game/minimap/flag3.png",
  ["sword"] = "data/images/game/minimap/flag8.png",
  ["red up"] = "data/images/game/minimap/flag14.png",
  ["?"] = "data/images/game/minimap/flag1.png",
  ["checkmark"] = "data/images/game/minimap/flag0.png",
  ["red left"] = "data/images/game/minimap/flag17.png",
  ["red right"] = "data/images/game/minimap/flag16.png",
  ["!"] = "data/images/game/minimap/flag2.png",
  ["down"] = "data/images/game/minimap/flag19.png",
  ["mouth"] = "data/images/game/minimap/flag6.png",
  ["lock"] = "data/images/game/minimap/flag10.png",
  ["red down"] = "data/images/game/minimap/flag15.png",
  ["bag"] = "data/images/game/minimap/flag11.png",
  ["cross"] = "data/images/game/minimap/flag5.png",
  ["spear"] = "data/images/game/minimap/flag7.png",
  ["$"] = "data/images/game/minimap/flag13.png",
}

function RealMap.load()
    if RealMap.loaded then
        return
    end

    RealMap.settings = g_settings.getNode('game_minimap') or { ignoreFlag = {} }
    RealMap.setMarkers()
    RealMap.loaded = true
end

function RealMap.unload()
    g_realMinimap:clean()
end

function RealMap.setIgnoreFlag(position)
    RealMap.settings.ignoreFlag[position.x .. ',' .. position.y .. ',' .. position.z] = true

    local settings = {}
    settings.ignoreFlag = RealMap.settings.ignoreFlag
    g_settings.setNode('game_minimap', settings)
end

function RealMap.setRegions(minimapWidget, mainAreaId, regions)
  if not minimapWidget.selectedCity then
    minimapWidget.selectedCity = 0
    minimapWidget.selectedRegions = {}
  end

  for _, region in pairs(minimapWidget.selectedRegions) do
    g_realMinimap.disableRegion(region)
  end

  if minimapWidget.selectedCity == mainAreaId then
    minimapWidget:setSelectedCity(0)
    return
  end

  minimapWidget.selectedCity = mainAreaId
  for _, region in pairs(RealMap.regions) do
    if table.contains(regions, region.areaId) then
      local imageId = g_realMinimap.loadRegion(region.image, region.fromPos, 1, 0, 64, region.markedColor, region.areaId)
      g_realMinimap.enableRegion(imageId)
      minimapWidget.selectedRegions[#minimapWidget.selectedRegions + 1] = imageId
    end
  end

  if minimapWidget.selectedRegion then
    g_realMinimap.disableRegion(minimapWidget.selectedRegion.id)
    minimapWidget.selectedRegion = nil
  end
end

function RealMap.setRegion(minimapWidget)
  if minimapWidget._realMapRegionsLoaded then
    return
  end
  minimapWidget._realMapRegionsLoaded = true

  for _, region in pairs(RealMap.regions) do
    local imageId = g_realMinimap.loadRegion(region.image, region.fromPos, 1, 0, 64, region.markedColor, region.areaId)

    minimapWidget:addCustomMouseEvent(MouseLeftButton, region.fromPos, region.toPos, function(self, mapPos, mousePos)
      if not self:hasClickedRegion(imageId, mapPos) then
        return false
      end

      minimapWidget:setSelectedCity(0)
      if minimapWidget.selectedCity and minimapWidget.selectedCity > 0 then
        for _, region in pairs(minimapWidget.selectedRegions) do
          g_realMinimap.disableRegion(region)
        end
        minimapWidget.selectedRegions = {}
        minimapWidget.selectedCity = 0
      end

      if minimapWidget.selectedRegion then
        if minimapWidget.selectedRegion.id == imageId then
          -- if it is the same, just remove it
          g_realMinimap.disableRegion(minimapWidget.selectedRegion.id)
          minimapWidget.selectedRegion = nil
          return true
        end

        -- if it is another one, then we disable it, and continue to enable
        -- a new one (keeping only one selected)
        g_realMinimap.disableRegion(minimapWidget.selectedRegion.id)
        minimapWidget.selectedRegion = nil
      end

      minimapWidget.selectedRegion = {region = region, id = imageId}
      g_realMinimap.enableRegion(imageId)

      return true
    end)
  end
end

function RealMap.setCameraPosition(widget, pos)
  if not widget or not widget.setCameraPosition or not pos or
      type(pos.x) ~= "number" or type(pos.y) ~= "number" or type(pos.z) ~= "number" or
      pos.x <= 0 or pos.y <= 0 or pos.z < 0 or pos.z > 15 then
    return
  end
  widget:setCameraPosition(pos)
end

function RealMap.getCameraPosition(widget)
  if not widget or not widget.getCameraPosition then
    return nil
  end
  return widget:getCameraPosition()
end

function RealMap.setCrossPosition(widget, pos)
  if not widget or not widget.setCrossPosition or not pos then
    return
  end
  widget:setCrossPosition(pos)
end

function RealMap.hideCross(widget)
  widget:hideCross()
end

function RealMap.setZoom(widget, zoom)
  widget:setZoom(zoom)
end

function RealMap.setMarkers()
  local ignoreFlag = RealMap.settings.ignoreFlag and RealMap.settings.ignoreFlag or {}
  for _, markerInfo in pairs(RealMap.markers) do
    local filePath = flagToFilePath[markerInfo.icon]
    if filePath then
      -- g_realMinimap.addWidget(filePath, {width = 11, height = 11}, markerInfo.pos, markerInfo.description)
      if not ignoreFlag[markerInfo.pos.x .. ',' .. markerInfo.pos.y .. ',' .. markerInfo.pos.z] then
        g_minimap.addWidget(filePath, {width = 11, height = 11}, markerInfo.pos, markerInfo.description)
      end
    else
      print(markerInfo.icon, "not loaded!")
    end
  end
end

function RealMap.setUIMarkers(widget)
  if not widget or widget._realMapMarkersLoading or widget._realMapMarkersLoaded then
    return
  end

  widget._realMapMarkersLoading = true
  local index = 1
  local chunkSize = 125

  local function loadChunk()
    if not widget or (widget.isDestroyed and widget:isDestroyed()) then
      return
    end

    local lastIndex = math.min(index + chunkSize - 1, #RealMap.markers)
    for markerIndex = index, lastIndex do
      local markerInfo = RealMap.markers[markerIndex]
      local filePath = markerInfo and flagToFilePath[markerInfo.icon]
      if filePath then
        widget:addWidget(filePath, {width = 11, height = 11}, markerInfo.pos, markerInfo.description)
      elseif markerInfo then
        print(markerInfo.icon, "not loaded!")
      end
    end

    index = lastIndex + 1
    if index <= #RealMap.markers then
      scheduleEvent(loadChunk, 1)
    else
      widget._realMapMarkersLoading = false
      widget._realMapMarkersLoaded = true
    end
  end

  scheduleEvent(loadChunk, 1)
end

function RealMap.setLevelSeparator(widget, levelSeparator)
  widget:setLevelSeparator(levelSeparator)
end
