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

    RealMap.loadSettings()
    RealMap.setMarkers()
    RealMap.loaded = true
end

function RealMap.loadSettings()
  RealMap.settings = g_settings.getNode('game_minimap') or {}
  RealMap.settings.ignoreFlag = RealMap.settings.ignoreFlag or {}
end

function RealMap.unload()
    g_realMinimap:clean()
end

function RealMap.setIgnoreFlag(position)
    RealMap.loadSettings()
    RealMap.settings.ignoreFlag[position.x .. ',' .. position.y .. ',' .. position.z] = true

    g_settings.setNode('game_minimap', RealMap.settings)
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

  modules.game_cyclopedia.MapCyclopedia.setImprovevedValue(mainAreaId)

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

      local areaName, subAreaName = self:getAreaNameById(region.areaId)
      modules.game_cyclopedia.MapCyclopedia.onChangeArea(areaName, subAreaName)
      modules.game_cyclopedia.MapCyclopedia.setImprovevedValue(region.areaId)

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
  if not widget or widget:isDestroyed() then return end
  RealMap.loadSettings()
  if not RealMap.markerIndex or (RealMap.markerIndexSource and RealMap.markerIndexSource ~= RealMap.markers) then
    RealMap.markerIndex = MapMarkerIndex.create()
    RealMap.markerIndexSource = RealMap.markers
    for id, marker in ipairs(RealMap.markers or {}) do
      local path = flagToFilePath[marker.icon]
      if path then
        RealMap.markerIndex:insert({id = 'catalog-' .. id, imagePath = path,
          imageSize = {width = 11, height = 11}, position = marker.pos,
          tooltip = marker.description, priority = 0,
          positionKey = marker.pos.x .. ',' .. marker.pos.y .. ',' .. marker.pos.z})
      end
    end
  end
  -- Reuse one data-only catalog between opens. UIRealMinimap owns only a small
  -- visible pool, and its scheduled refresh is cancelled on destruction.
  widget.markerCatalog = RealMap.markerIndex
  widget:refreshMarks()
end

function RealMap.setLevelSeparator(widget, levelSeparator)
  widget:setLevelSeparator(levelSeparator)
end
