-- Actual native engine, hidden window, no login or live server map packets.
scheduleEvent(function()
  g_game.setProtocolVersion(860)
  g_game.setClientVersion(860)
  g_modules.ensureModuleLoaded('game_things')
  modules.game_things.load()
  assert(g_minimap.loadSatellitePack('/data/minimap_hd'), 'Generated persistent pack failed to load')
  local count = g_minimap.getSatelliteChunkCount()
  assert(count > 0 and g_minimap.hasSatellitePack())
  assert(g_minimap.getSatelliteTextureCount() == 0, 'Indexing eagerly decoded the entire world')
  local info = json.decode(g_resources.readFileContents('/data/minimap_hd/source.json'))
  assert(count == info.total_chunks)
  local first
  for line in g_resources.readFileContents('/data/minimap_hd/index.txt'):gmatch('[^\r\n]+') do
    local level, x, y, z = line:match('^(%d+) (%d+) (%d+) (%d+) ')
    if level == '1' then
      first = { x = tonumber(x) + 8, y = tonumber(y) + 8, z = tonumber(z) }
      break
    end
  end
  assert(first and g_minimap.hasSatelliteTile(first))
  assert(#g_map.getTiles(-1) == 0, 'Test must not rely on any live map tiles')
  local overlay = json.decode(g_resources.readFileContents('/classic-overlay.json'))
  assert(g_minimap.loadOtmm('/data/minimap_hd/minimap.otmm'))
  assert(g_map.getMinimapColor(overlay.preserved) == overlay.preserved_color)
  assert(g_minimap.mergeOtmm('/classic-overlay.otmm'))
  assert(g_map.getMinimapColor(overlay.changed) == overlay.color, "User's known colors were not merged")
  assert(g_map.getMinimapColor(overlay.preserved) == overlay.preserved_color, 'Unknown user cells erased the revealed map')
  modules.client_settings.setOption('minimapHD', true)
  local mini = modules.game_minimap.minimapWidget
  mini:setCameraPosition(first)
  assert(mini:isSpriteMode() and mini:setZoom(-1), 'LOD pack should permit zooming out in HD')
  local attempts = 0
  local function waitForImages()
    attempts = attempts + 1
    local ready = g_minimap.preloadSatelliteTile(first, 8)
    local farReady = g_minimap.preloadSatelliteTile(first, 1 / 32)
    if not ready or not farReady then
      assert(attempts < 100, 'Asynchronous visible chunk decode timed out')
      scheduleEvent(waitForImages, 50)
      return
    end
    assert(g_minimap.getSatelliteTextureCount() <= 32)
    modules.client_settings.setOption('minimapHD', false)
    assert(g_minimap.getSatelliteTextureCount() == 0, 'HD off retained decoded PNG textures')
    assert(g_minimap.getSatelliteChunkCount() == count, 'HD off erased the disk index')
    modules.client_settings.setOption('minimapHD', true)
    mini:setZoom(-1)
    local marker = mini:getTilePosition(mini:getTilePoint(first))
    -- At sub-tile scales multiple world tiles share one screen pixel.
    assert(math.abs(marker.x - first.x) <= 2 and math.abs(marker.y - first.y) <= 2)
    g_map.clean()
    g_minimap.clean()
    assert(g_minimap.getSatelliteChunkCount() == count, 'Logout erased persistent HD coverage')
    assert(g_minimap.getSatelliteTextureCount() == 0 and g_minimap.hasSatelliteTile(first))
    g_minimap.clearSatellitePack() -- Simulate a new client process, not just a map reset.
    assert(g_minimap.loadSatellitePack('/data/minimap_hd'))
    assert(g_minimap.getSatelliteChunkCount() == count and g_minimap.hasSatelliteTile(first))
    modules.client_settings.setOption('minimapHD', false)
    assert(not mini:isSpriteMode(), 'Classic checkbox failed')
    g_logger.info('[HD MINIMAP TEST] PASS: persistent pack, no exploration, classic merge, lazy decode, far LOD, logout/restart, optional classic mode')
    scheduleEvent(g_app.exit, 500)
  end
  waitForImages()
end, 1000)
