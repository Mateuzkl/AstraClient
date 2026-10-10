-- Runs in the actual client (--test), with a separate profile and no login.
scheduleEvent(function()
  local mini = modules.game_minimap.minimapWidget
  assert(mini and mini.setSpriteMode, 'New native API was not loaded')
  local panel = modules.client_settings.loadedWindows.graphics
  local checkbox = panel:recursiveGetChildById('minimapHD')
  assert(checkbox and checkbox:isEnabled(), 'Graphics checkbox is missing/disabled')
  local window = modules.game_minimap.minimapWindow
  local hdButton = window:getChildById('minimapHDButton')
  local cyclopediaButton = window:getChildById('fullSize')
  local function assertControlsOnTop()
    assert(mini:getParent() == window and window:getChildIndex(mini) == 1,
           'Minimap must be the background after leaving Ctrl+Shift+M')
    for _, id in ipairs({'glass', 'centerMap', 'floorPosition', 'zoomInWidget',
                         'zoomOutWidget', 'fullSize', 'minimapHDButton'}) do
      local control = window:getChildById(id)
      assert(control and window:getChildIndex(control) > window:getChildIndex(mini),
             'Minimap covered control: ' .. id)
    end
  end
  assertControlsOnTop()
  assert(hdButton and hdButton:isEnabled() and not hdButton:isOn(), 'Quick HD button is missing/incorrect')
  local hdPos, mapPos = hdButton:getPosition(), cyclopediaButton:getPosition()
  -- OTUI anchors use inclusive rectangle edges: margin 2 leaves a one-pixel gap.
  assert(hdPos.x + hdButton:getWidth() + 1 == mapPos.x and hdPos.y == mapPos.y,
         string.format('Quick HD button must be beside Cyclopedia: HD=(%d,%d,%d,%d), map=(%d,%d)',
                       hdPos.x, hdPos.y, hdButton:getWidth(), hdButton:getHeight(), mapPos.x, mapPos.y))
  assert(hdButton:getWidth() == 20 and hdButton:getHeight() == 20)
  local textSize = hdButton:getTextSize()
  assert(textSize.width < 20 and textSize.height < 20, 'HD label must fit inside its button')
  local downloadButton = window:getChildById('downloadMapButton')
  local downloadWasVisible = downloadButton:isVisible()
  downloadButton:setVisible(true)
  local downloadPos = downloadButton:getPosition()
  assert(downloadPos.x >= window:getPosition().x and
         downloadPos.x + downloadButton:getWidth() < hdPos.x,
         'Download Map must fit without overlapping the quick HD button')
  downloadButton:setVisible(downloadWasVisible)
  hdButton.onClick(hdButton)
  assert(mini:isSpriteMode() and checkbox:isChecked() and hdButton:isOn())
  assert(modules.client_settings.getOption('minimapHD') and g_settings.getBoolean('minimapHD'),
         'Quick HD button must persist the preference')
  hdButton.onClick(hdButton)
  assert(not mini:isSpriteMode() and not checkbox:isChecked() and not hdButton:isOn())
  assert(not modules.client_settings.getOption('minimapHD') and not g_settings.getBoolean('minimapHD'))
  assert(not modules.client_settings.getOption('minimapHD'), 'HD should start off')
  assert(not mini:isSpriteMode() and g_minimap.getSpriteCacheTileCount() == 0)
  g_settings.setNode('Minimap', { zoom = -1, spriteZoom = 3 })

  -- Changing the version loads the actual local 8.60 DAT/SPR through game_things.
  g_game.setProtocolVersion(860)
  g_game.setClientVersion(860)
  g_modules.ensureModuleLoaded('game_things')
  modules.game_things.load()
  assert(g_things.isDatLoaded() and g_sprites.isLoaded(), 'Local DAT/SPR failed to load')
  local groundId, commonId
  for _, thing in pairs(g_things.getThingTypes(ThingCategoryItem)) do
    if not groundId and thing:isGround() then groundId = thing:getId() end
    if not commonId and not thing:isGround() and not thing:isOnTop() and
       not thing:isOnBottom() and not thing:isGroundBorder() then commonId = thing:getId() end
    if groundId and commonId then break end
  end
  assert(groundId and commonId)
  local function put(id, x, y, z)
    g_map.addThing(Item.create(id, 1), { x = x, y = y, z = z or 7 }, -1)
  end
  mini:setZoom(-1)
  put(groundId, 100, 100)
  assert(g_minimap.getSpriteCacheTileCount() == 0, 'Classic mode allocated HD terrain')
  modules.client_settings.setOption('minimapHD', true)
  assert(mini:isSpriteMode() and mini:getZoom() == 3 and checkbox:isChecked() and hdButton:isOn())
  assert(mini:setZoom(0) == g_minimap.hasSatellitePack(), 'Only a pre-rendered LOD pack should allow wide close views')
  mini:setCameraPosition({ x = 100, y = 100, z = 7 })
  for y = 88, 111 do
    for x = 88, 111 do
      if x ~= 100 or y ~= 100 then put(groundId, x, y) end
    end
  end
  mini:setZoom(4)
  modules.game_minimap.toggleFullMap()
  assert(mini:setZoom(-1))
  assert(g_minimap.getSpriteCacheTileCount() > 0, 'Full map destroyed terrain cache')
  modules.game_minimap.toggleFullMap()
  assert(mini:getZoom() == 4)
  assertControlsOnTop()
  for _, enabled in ipairs({false, true}) do
    modules.client_settings.setOption('minimapHD', enabled)
    local smallZoom = mini:getZoom()
    for cycle = 1, 5 do
      modules.game_minimap.toggleFullMap()
      assert(mini:setZoom(0))
      modules.game_minimap.toggleFullMap()
      assert(mini:getZoom() == smallZoom and mini:isSpriteMode() == enabled)
      assertControlsOnTop()
    end
  end
  -- Verify real native transitions that the standalone Lua mock cannot cover.
  modules.game_minimap.toggleFullMap()
  mini:setZoom(0)
  modules.client_settings.setOption('minimapHD', false)
  assert(mini:getZoom() == 0)
  modules.game_minimap.toggleFullMap()
  assert(mini:getZoom() == -1 and not mini:isSpriteMode())
  assertControlsOnTop()
  modules.game_minimap.toggleFullMap()
  mini:setZoom(0)
  modules.client_settings.setOption('minimapHD', true)
  assert(mini:getZoom() == 0)
  modules.game_minimap.toggleFullMap()
  assert(mini:isSpriteMode() and mini:getZoom() == 3)
  assertControlsOnTop()
  mini:setZoom(4)
  local pos = { x = 101, y = 101, z = 7 }
  -- Mode changes deliberately clear snapshots. Seed this tile again before
  -- measuring one new item's delta, without depending on a visible renderer.
  assert(g_map.removeThing(g_map.getTile(pos):getItems()[1]))
  put(groundId, pos.x, pos.y)
  local before = g_minimap.getSpriteCacheItemCount()
  put(commonId, pos.x, pos.y)
  assert(g_minimap.getSpriteCacheItemCount() == before + 1, 'Terrain changes were not captured')
  assert(g_map.removeThing(g_map.getTile(pos):getItems()[2]))
  assert(g_minimap.getSpriteCacheItemCount() == before, 'Removed items left stale snapshots')
  mini:save()
  local settings = g_settings.getNode('Minimap')
  assert(tonumber(settings.zoom) == -1 and tonumber(settings.spriteZoom) == 4)
  modules.client_settings.setOption('minimapHD', false)
  assert(mini:getZoom() == -1 and g_minimap.getSpriteCacheTileCount() == 0 and not hdButton:isOn())
  modules.client_settings.setOption('minimapHD', true)
  assert(mini:getZoom() == 4, 'HD zoom was not restored')
  g_minimap.clearSpriteCache()

  for index = 1, 9000 do put(groundId, 1000 + index % 100, 1000 + math.floor(index / 100)) end
  assert(g_minimap.getSpriteCacheTileCount() == 8192, 'Tile cache is not bounded')
  assert(g_minimap.getSpriteCacheItemCount() == 8192)
  g_minimap.clearSpriteCache()
  for index = 1, 600 do
    for count = 1, 64 do put(commonId, 2000 + index % 100, 2000 + math.floor(index / 100)) end
  end
  assert(g_minimap.getSpriteCacheItemCount() <= 32768, 'Item cache is not bounded')
  g_map.clean()
  assert(g_minimap.getSpriteCacheTileCount() == 0, 'World reset retained HD terrain')
  modules.client_settings.setOption('minimapHD', false)
  for y = 85, 115 do
    for x = 85, 115 do put(groundId, x, y) end
  end
  assert(g_minimap.getSpriteCacheTileCount() == 0)
  local previousParent = mini:getParent()
  mini:setParent(g_ui.getRootWidget())
  mini:breakAnchors()
  mini:setSize({ width = 320, height = 240 })
  mini:setPosition({ x = 100, y = 100 })
  mini:show()
  mini:setCameraPosition({ x = 100, y = 100, z = 7 })
  modules.client_settings.setOption('minimapHD', true)
  mini:setZoom(3)
  local visual = g_app.getStartupOptions():find('--hd-minimap-visual', 1, true) ~= nil
  if visual then g_window.show() end
  scheduleEvent(function()
    if visual then
      assert(g_minimap.getSpriteCacheTileCount() > 0, 'HD renderer did not rehydrate terrain while stationary')
      g_app.doScreenshot('hd-minimap.png')
    else
      g_logger.info('[HD MINIMAP TEST] Hidden-window run: visual rendering test skipped (use -Visual)')
    end
    local point = mini:getTilePoint({ x = 102, y = 103, z = 7 })
    local position = mini:getTilePosition(point)
    assert(position.x == 102 and position.y == 103 and position.z == 7, 'HD click/marker alignment changed')
    modules.client_settings.setOption('minimapHD', false)
    mini:setParent(previousParent)
    mini:fill('parent')
    modules.client_settings.GameOptions:flushSettingsSave()
    g_logger.info('[HD MINIMAP TEST] PASS: native bindings, quick toggle layout/checkbox sync, settings UI, zooms, updates, cache budgets, world reset, marker alignment')
    scheduleEvent(g_app.exit, 500)
  end, 500)
end, 1000)
