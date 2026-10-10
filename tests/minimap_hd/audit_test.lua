-- Actual native engine, no login/window rendering or user-profile mutation.
scheduleEvent(function()
  g_game.setProtocolVersion(860)
  g_game.setClientVersion(860)
  g_modules.ensureModuleLoaded('game_things')
  modules.game_things.load()
  assert(g_minimap.loadSatellitePack('/data/minimap_hd'))
  local mini = modules.game_minimap.minimapWidget
  assert(g_minimap.getSpriteViewCount() == 0)

  local retained = {}
  for i = 1, 100 do
    local parent = g_ui.createWidget('Panel', g_ui.getRootWidget())
    local view = g_ui.createWidget('Minimap', parent)
    view:setSpriteMode(true)
    view:setSpriteMode(true)
    assert(g_minimap.getSpriteViewCount() == 1, 'Idempotent enable duplicated subscriptions')
    parent:destroy() -- Recursive native destruction, while Lua still owns the child.
    assert(g_minimap.getSpriteViewCount() == 0, 'Destroyed view retained its cache subscription')
    view:setSpriteMode(true)
    assert(not view:isSpriteMode() and g_minimap.getSpriteViewCount() == 0)
    retained[i] = view -- Intentionally keep references alive; no GC-based cleanup shortcut.
  end
  local calls = 0
  local original = modules.game_minimap.setMinimapHD
  modules.game_minimap.setMinimapHD = function(enabled)
    calls = calls + 1
    return original(enabled)
  end
  for i = 1, 100 do
    modules.client_settings.setOption('minimapHD', true)
    assert(g_minimap.getSpriteViewCount() == 1)
    modules.client_settings.setOption('minimapHD', false)
    assert(g_minimap.getSpriteViewCount() == 0)
  end
  modules.game_minimap.setMinimapHD = original
  assert(calls == 200, 'One mode change must invoke one controller callback')

  local samples = {}
  for line in g_resources.readFileContents('/data/minimap_hd/index.txt'):gmatch('[^\r\n]+') do
    local level, x, y, z = line:match('^(%d+) (%d+) (%d+) (%d+) ')
    if level == '1' and #samples < 80 then
      samples[#samples + 1] = {x = tonumber(x) + 8, y = tonumber(y) + 8, z = tonumber(z)}
    end
  end
  assert(#samples == 80)
  for cycle = 1, 100 do
    mini:setSpriteMode(true)
    for index = 1, 4 do g_minimap.preloadSatelliteTile(samples[(cycle + index) % 80 + 1], 32) end
    assert(g_minimap.getSatelliteDecodeCount() <= 4, 'Real jobs exceeded admission capacity')
    if cycle % 2 == 0 then
      g_minimap.clearSatellitePack()
      assert(g_minimap.loadSatellitePack('/data/minimap_hd'))
    end
    mini:setSpriteMode(false)
    assert(g_minimap.getSatelliteTextureCount() == 0)
    assert(g_minimap.getSatelliteDecodeCount() <= 4, 'Cache reset forgot outstanding jobs')
  end
  local attempts = 0
  local function recover()
    attempts = attempts + 1
    if not g_minimap.preloadSatelliteTile(samples[80], 32) then
      assert(attempts < 100, 'Visible chunk starved after reset stress')
      scheduleEvent(recover, 20)
      return
    end
    g_logger.info('[HD AUDIT] PASS: 100 retained destroyed views, 200 single callbacks, 100 pan/reset cycles, job bound <=4 and visible recovery')
    g_minimap.clearSatellitePack()
    mini:setSpriteMode(true)
    g_map.clean()
    local center = {x = 30000, y = 30000, z = 7}
    local size = {width = 256, height = 192}
    local before = g_minimap.getSpriteTileLookupCount()
    g_minimap.auditPrepareSpriteView(size, center, 8)
    local warmed = g_minimap.getSpriteTileLookupCount()
    assert(warmed > before)
    for i = 1, 100 do g_minimap.auditPrepareSpriteView(size, center, 8) end
    assert(g_minimap.getSpriteTileLookupCount() == warmed, 'Static empty viewport repeated map lookups')
    local ground
    for _, thing in pairs(g_things.getThingTypes(ThingCategoryItem)) do
      if thing:isGround() and thing:getMinimapColor() > 0 and thing:getMinimapColor() ~= 255 then ground = thing:getId(); break end
    end
    assert(ground)
    g_map.addThing(Item.create(ground, 1), center, -1)
    assert(g_minimap.getSpriteCacheItemCount() == 1, 'Negative snapshot hid newly received terrain')
    local color = g_map.getMinimapColor(center)
    g_logger.info('[HD AUDIT] EXPECTED ERROR: corrupt OTMM must return false')
    assert(not g_minimap.mergeOtmm('/negative/corrupt.otmm'), 'Corrupt Zlib block was reported successful')
    assert(g_map.getMinimapColor(center) == color)
    mini:setSpriteMode(false)
    g_logger.info('[HD AUDIT] Static empty viewport: first=' .. (warmed - before) .. ' map lookups; next 100 preparations=0; new terrain immediately visible')

    assert(g_minimap.loadSatellitePack('/data/minimap_hd'))
    local count = g_minimap.getSatelliteChunkCount()
    for _, kind in ipairs({'bad-signature', 'bad-index'}) do
      g_logger.info('[HD AUDIT] EXPECTED ERROR: ' .. kind)
      assert(not g_minimap.loadSatellitePack('/negative/' .. kind))
      assert(g_minimap.getSatelliteChunkCount() == count, 'Failed replacement erased valid pack')
    end
    -- Custom-seed fixtures go last: discovery changes only this isolated process.
    local positives = {valid = true, encrypted = true, seeded = true}
    local cases = {'valid', 'encrypted', 'oversized', 'animated', 'truncated', 'enc3-bomb', 'missing', 'seeded', 'bad-seed'}
    local index, polls = 1, 0
    local function checkCase()
      local kind = cases[index]
      polls = polls + 1
      local ready = g_minimap.preloadSatelliteTile({x = 104, y = 104, z = 7}, 32)
      assert(g_minimap.getSatelliteDecodeCount() <= 4)
      if g_minimap.getSatelliteDecodeCount() > 0 then
        assert(polls < 100)
        scheduleEvent(checkCase, 20)
        return
      end
      assert(ready == (positives[kind] == true), 'PNG acceptance mismatch: ' .. kind)
      assert(g_minimap.getSatelliteTextureCount() <= 32)
      index, polls = index + 1, 0
      if index <= #cases then
        if not positives[cases[index]] then g_logger.info('[HD AUDIT] EXPECTED ERROR: ' .. cases[index]) end
        assert(g_minimap.loadSatellitePack('/negative/' .. cases[index]))
        scheduleEvent(checkCase, 20)
      else
        g_minimap.clearSatellitePack()
        assert(g_minimap.loadSatellitePack('/data/minimap_hd'))
        assert(g_minimap.getSpriteViewCount() == 0)
        g_logger.info('[HD MINIMAP TEST] PASS: audit lifecycle, callback count, real decode budget/reset recovery, negative snapshots, invalid pack/PNG/ENC3/OTMM rejection')
        scheduleEvent(g_app.exit, 500)
      end
    end
    assert(g_minimap.loadSatellitePack('/negative/valid'))
    checkCase()
  end
  recover()
end, 1000)
