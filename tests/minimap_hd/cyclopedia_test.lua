-- Actual production controllers/widgets, isolated profile, real GL/ANGLE draw.
scheduleEvent(function()
  g_game.setProtocolVersion(860); g_game.setClientVersion(860)
  g_modules.ensureModuleLoaded('game_things'); modules.game_things.load()
  g_minimap.clean()
  assert(g_minimap.loadOtmm('/surface-pack/minimap.otmm'))
  assert(g_minimap.loadSatellitePack('/surface-pack'))
  local folder = '/surface-' .. os.time() .. '-' .. g_clock.millis()
  assert(g_resources.makeDir(folder))
  local captures, center = {}, {x = 4160, y = 4160, z = 6}
  local requests, originalRequest = 0, g_game.requestResource
  g_game.requestResource = function(...) requests = requests + 1; return originalRequest(...) end
  local cyc = modules.game_cyclopedia
  local function frame(z, opacity, name)
    center.z = z
    local level = g_minimap.auditSurfaceFrame({width = 256, height = 256}, center, 8, opacity, name and (folder .. '/' .. name .. '.png') or '')
    assert(g_minimap.getSatelliteTextureCount() <= 32 and g_minimap.getSatelliteDecodeCount() <= 4)
    if name then captures[#captures + 1] = {name = name .. '.png', level = level, z = z, opacity = opacity, x = center.x, y = center.y, scale = 8} end
    return level
  end
  local cases = {{6,0}, {6,.5}, {6,1}, {0,0}, {0,.5}, {0,1}, {7,1}, {8,1}}
  local case, polls = 0, 0
  local originalCatalog = RealMap.markerIndex
  local openTimes, closeTimes, markerTimes = {}, {}, {}
  local function connections(signal)
    local handlers = g_game[signal]
    return type(handlers) == 'table' and #handlers or (type(handlers) == 'function' and 1 or 0)
  end
  local addHandlers, removeHandlers = connections('onAddAutomapFlag'), connections('onRemoveAutomapFlag')
  local function finish()
    for _, capture in ipairs(captures) do
      if not g_resources.fileExists(folder .. '/' .. capture.name) then scheduleEvent(finish, 20); return end
    end
    assert(g_resources.writeFileContents(folder .. '/frames.json', json.encode(captures)))
    assert(g_resources.writeFileContents(folder .. '/timings.json', json.encode({open = openTimes, close = closeTimes, markers = markerTimes})))
    RealMap.markerIndex = originalCatalog
    g_game.requestResource = originalRequest
    assert(requests == 0, 'Map open/toggle sent unnecessary balance requests')
    g_logger.info('[HD MINIMAP TEST] SURFACE FIXTURE: ' .. g_resources.getWriteDir() .. folder .. '/frames.json')
    g_logger.info('[HD MINIMAP TEST] PASS: surface alpha 0/50/100 floors 0/6/7/8, HUD independence, virtualized markers, filters, persistent flags, direct Map redirect, 100 real panel lifecycles, no map balance requests')
    scheduleEvent(g_app.exit, 500)
  end
  local cycle = 0
  local function edgeCases()
    local preview = g_ui.createWidget('RealMinimap',rootWidget)
    preview:setCameraPosition({x=4160,y=4160,z=6})
    preview:setCurrentView('satellite')
    assert(preview:isSurfaceMode() and preview:getSurfaceOpacity()==0, 'House preview composed unrelated floors')
    preview:setCurrentView('fullMinimap')
    assert(preview.currentView=='fullMinimap' and not preview:isSurfaceMode())
    preview:destroy()
    assert(g_minimap.getSurfaceViewCount()==0)
    -- Actual Items panel/focus path, with no loaded quickloot player profile.
    cyc.Cyclopedia:open('Items')
    local panel = cyc.VisibleCyclopediaPanel
    local row = g_ui.createWidget('ItemListLabel', panel.leftInfo.itemList)
    row.item:setItemId(100)
    cyc.CyclopediaItems.itemListChildFocus(panel.leftInfo.itemList,row)
    local box = panel.panelitemshide.checkLootbox
    assert(not box:isEnabled(), 'Unavailable quickloot profile was fabricated/enabled')
    local owner = modules.game_quickloot
    local oldSelection = owner.getLootSelection
    owner.getLootSelection = function() return 'whitelist',true end
    cyc.CyclopediaItems.itemListChildFocus(panel.leftInfo.itemList,row)
    assert(box:isEnabled() and box:isChecked())
    owner.getLootSelection = function() return 'blacklist',false end
    cyc.CyclopediaItems.itemListChildFocus(panel.leftInfo.itemList,row)
    assert(box:isEnabled() and not box:isChecked())
    owner.getLootSelection = oldSelection
    cyc.Cyclopedia.endGame()
    -- A missing pack disables only Surface; the classic Map remains usable.
    g_minimap.clearSatellitePack()
    local exists = g_resources.fileExists
    g_resources.fileExists = function(path)
      if path == '/data/minimap_hd/index.txt' then return false end
      return exists(path)
    end
    cyc.toggleRedirect('Map')
    local map = cyc.MapCyclopedia.getWidget()
    assert(not map:isSurfaceMode() and not cyc.MapCyclopedia.surfaceView:isEnabled())
    assert(cyc.MapCyclopedia.mapView:isEnabled() and g_minimap.getSurfaceViewCount()==0)
    cyc.Cyclopedia.endGame()
    g_resources.fileExists = exists
    assert(g_minimap.loadSatellitePack('/surface-pack'))
    finish()
  end
  local function lifecycle()
    cycle = cycle + 1
    local start = g_clock.millis()
    cyc.toggleRedirect('Map')
    openTimes[#openTimes + 1] = g_clock.millis() - start
    local map = cyc.MapCyclopedia.getWidget()
    assert(map and map:isSurfaceMode() and g_minimap.getSurfaceViewCount() == 1)
    assert(connections('onAddAutomapFlag') == addHandlers + 1 and connections('onRemoveAutomapFlag') == removeHandlers + 1)
    assert(not modules.game_minimap.minimapWidget:isSpriteMode() and not modules.client_settings.getOption('minimapHD'))
    assert(g_minimap.getSpriteCacheTileCount() == 0, 'Surface enabled live terrain cache')
    scheduleEvent(function()
      assert(#map.markerPool <= 128 and map:getChildCount() <= 162, 'Unbounded marker widget growth')
      start = g_clock.millis(); map:updateVisibleMarkers(); markerTimes[#markerTimes + 1] = g_clock.millis() - start
      if cycle == 1 then
        for _ = 1, 12 do map:updateVisibleMarkers() end
        assert(#map.markerPool > 0, 'Dense in-view markers did not render')
        for _,widget in ipairs(map.markerPool) do assert(not widget.marker or widget.marker.id~='excluded', 'Legacy position exclusion was ignored') end
        local id = map:addWidget('/data/images/game/minimap/flag3.png', {width=11,height=11}, {x=4160,y=4160,z=6}, 'test flag')
        assert(id == map:addWidget('data/images/game/minimap/flag3.png', {width=11,height=11}, {x=4160,y=4160,z=6}, 'test flag'), 'Repeated flags were not deduplicated')
        map:save()
        map.onAddAutomapFlag({x=4161,y=4161,z=6},3,'server mark')
        local received = map.nextMarkerId
        map.onAddAutomapFlag({x=4161,y=4161,z=6},3,'server mark')
        assert(map.nextMarkerId == received)
        map.onRemoveAutomapFlag({x=4161,y=4161,z=6},3,'server mark')
        assert(not map.markerIndex.records[received])
        map:ignoreWidget('data/images/game/minimap/flag3.png'); map:updateVisibleMarkers()
        for _, widget in ipairs(map.markerPool) do assert(not widget:isVisible(), 'Filter left visible marker') end
        map:unignoreWidget('data/images/game/minimap/flag3.png'); map:updateVisibleMarkers()
        cyc.MapCyclopedia.floorDown(); cyc.MapCyclopedia.floorDown()
        assert(not map:isSurfaceMode() and cyc.MapCyclopedia.preference == 'satellite')
        map:setZoom(2)
        cyc.MapCyclopedia.floorUp(); cyc.MapCyclopedia.floorUp()
        assert(map:isSurfaceMode() and map:getCameraPosition().z == 6 and map:getZoom()==4, 'Automatic floor switch lost per-view zoom')
        cyc.toggleDisplayShowAll()
        assert(map:isWidgetIgnored('data/images/game/minimap/flag3.png'))
        cyc.toggleDisplayShowAll()
        assert(not map:isWidgetIgnored('data/images/game/minimap/flag3.png'))
        cyc.MapCyclopedia.labelsEnabled = true
        cyc.MapCyclopedia.cityLabels = {
          {name='Visible city',position={x=4160,y=4160,z=7},minZoom=-8},
          {name='Overlapping city',position={x=4160,y=4160,z=7},minZoom=-8},
          {name='Offscreen city',position={x=30000,y=30000,z=7},minZoom=-8}}
        cyc.MapCyclopedia.updateLabels()
        local labelsShown=0
        for _,label in ipairs(cyc.MapCyclopedia.cityWidgets) do if label:isVisible() then labelsShown=labelsShown+1 end end
        assert(labelsShown==1 and #cyc.MapCyclopedia.cityWidgets<=32, 'Labels did not cull/declutter')
        -- Flag editing must keep this same map/pool alive, not rebuild it.
        map:createFlagWindow({x=4160,y=4160,z=6})
        assert(map.flagWindow and not map:isDestroyed())
        map.flagWindow.onEscape()
        assert(not map.flagWindow and cyc.MapCyclopedia.getWidget() == map)
        modules.client_settings.setOption('minimapHD', true)
        assert(map:isSurfaceMode() and modules.game_minimap.minimapWidget:isSpriteMode())
        modules.client_settings.setOption('minimapHD', false)
        assert(map:isSurfaceMode() and g_minimap.getSurfaceViewCount() == 1)
        cyc.MinimapViewCheckBox:selectWidget(cyc.MapCyclopedia.mapView)
        assert(not map:isSurfaceMode() and map.currentView == 'minimap')
        cyc.MinimapViewCheckBox:selectWidget(cyc.MapCyclopedia.surfaceView)
        assert(map:isSurfaceMode() and map:getZoom() == 4)
        -- Redirecting Map while already open must save before destroying the
        -- old panel, not destroy its children and then read missing controls.
        local previous = map
        cyc.toggleRedirect('Map')
        map = cyc.MapCyclopedia.getWidget()
        assert(previous:isDestroyed() and map ~= previous and map:isSurfaceMode())
        assert(connections('onAddAutomapFlag') == addHandlers + 1)
        map:ignoreWidget('data/images/game/minimap/flag5.png')
        cyc.MapCyclopedia.syncMarkFilters()
      elseif cycle == 2 then
        local persisted = false
        for _, marker in pairs(map.markerIndex.records) do if marker.tooltip == 'test flag' then persisted = true end end
        assert(persisted, 'Flag lost across close/reopen')
        assert(map:isWidgetIgnored('data/images/game/minimap/flag5.png') and
          not cyc.VisibleCyclopediaPanel:recursiveGetChildById('marksButton7'):isChecked(), 'Saved filter/UI state disagreed')
      end
      start = g_clock.millis(); cyc.Cyclopedia.endGame(); closeTimes[#closeTimes + 1] = g_clock.millis() - start
      assert(map:isDestroyed() and not map.markerEvent and g_minimap.getSurfaceViewCount() == 0)
      assert(connections('onAddAutomapFlag') == addHandlers and connections('onRemoveAutomapFlag') == removeHandlers)
      assert(cyc.cyclopediaWindow.optionsPanel:getChildCount() == 0, 'Orphan panel remained')
      if cycle < 100 then scheduleEvent(lifecycle, 16) else edgeCases() end
    end, 32)
  end
  local function controllers()
    g_settings.setNode('CyclopediaMap', {view='satellite', camera={x=4160,y=4160,z=6}, zooms={minimap=-1,satellite=4}, separator=100, labels=false})
    g_settings.setNode('RealMinimap', {flags={},zoom=-1})
    -- 20k data entries off-screen plus a dense visible cluster. This exercises
    -- the actual virtualized UI, not 20k mocked widgets or a hidden renderer.
    RealMap.markerIndex = MapMarkerIndex.create()
    RealMap.setIgnoreFlag({x=4160,y=4160,z=6})
    RealMap.markerIndex:insert({id='excluded', imagePath='data/images/game/minimap/flag3.png', imageSize={width=11,height=11},
      position={x=4160,y=4160,z=6}, positionKey='4160,4160,6', priority=99})
    for id = 1, 20200 do
      local visible = id > 20000
      RealMap.markerIndex:insert({id='stress-'..id, imagePath='data/images/game/minimap/flag3.png', imageSize={width=11,height=11},
        position={x=visible and (4156 + id % 8) or (30000 + id % 256), y=visible and (4156 + math.floor(id/8)%8) or (30000 + math.floor(id/256)), z=6}, tooltip='stress', priority=0})
    end
    lifecycle()
  end
  local function nextCase()
    case, polls = case + 1, 0
    if case > #cases then
      -- Separate callback timing from concurrent GPU readback/PNG encoding.
      local function awaitCaptures()
        for _, capture in ipairs(captures) do
          if not g_resources.fileExists(folder .. '/' .. capture.name) then scheduleEvent(awaitCaptures,20); return end
        end
        controllers()
      end
      awaitCaptures()
      return
    end
    local z, opacity = unpack(cases[case])
    local function ready()
      polls = polls + 1; assert(polls < 300, 'Surface composition did not become ready')
      if z < 8 and frame(z,opacity) == 0 then scheduleEvent(ready,20); return end
      frame(z,opacity,z==8 and 'underground' or ('floor'..z..'-alpha'..opacity))
      nextCase()
    end
    ready()
  end
  nextCase()
end, 1000)
