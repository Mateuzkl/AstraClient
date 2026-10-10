-- Render the real minimap queue into an offscreen GL/ANGLE framebuffer.
-- Deterministic slow decodes make intermediate frames testable, without a login.
scheduleEvent(function()
  g_game.setProtocolVersion(860)
  g_game.setClientVersion(860)
  g_modules.ensureModuleLoaded('game_things')
  modules.game_things.load()
  g_minimap.clean()
  assert(g_minimap.loadOtmm('/glitch-pack/minimap.otmm'))
  assert(g_minimap.loadSatellitePack('/glitch-pack'))
  modules.client_settings.setOption('minimapHD', true)
  g_minimap.setSatelliteTestDecodeDelay(150)
  local folder = '/glitch-' .. os.time() .. '-' .. g_clock.millis()
  assert(g_resources.makeDir(folder))
  local captures = {}
  local center = {x = 4160, y = 4160, z = 7}
  local small, large = {width = 256, height = 256}, {width = 512, height = 512}
  local function frame(size, scale, name)
    local path = name and (folder .. '/' .. name .. '.png') or ''
    local level = g_minimap.auditSatelliteFrame(size, center, scale, path)
    assert(g_minimap.getSatelliteTextureCount() <= 32, 'Prefetch exceeded texture budget')
    assert(g_minimap.getSatelliteDecodeCount() <= 4, 'Prefetch exceeded job budget')
    if name then
      captures[#captures + 1] = {name = name .. '.png', level = level, x = center.x, y = center.y, z = center.z, scale = scale}
    end
    return level
  end
  local polls, partial = 0, false
  local function finish()
    for _, capture in ipairs(captures) do
      if not g_resources.fileExists(folder .. '/' .. capture.name) then
        scheduleEvent(finish, 20)
        return
      end
    end
    assert(g_resources.writeFileContents(folder .. '/frames.json', json.encode(captures)))
    g_logger.info('[HD MINIMAP TEST] GLITCH FIXTURE: ' .. g_resources.getWriteDir() .. folder .. '/frames.json')
    modules.client_settings.setOption('minimapHD', false)
    g_logger.info('[HD MINIMAP TEST] PASS: coherent LOD promotion, partial-decode retention, full-map/zoom/floor transitions, bounded nearby prefetch, real offscreen GPU frames')
    scheduleEvent(g_app.exit, 500)
  end
  local function floorWarm()
    polls = polls + 1
    assert(polls < 300)
    if frame(small, 8) == 0 then scheduleEvent(floorWarm, 20); return end
    assert(frame(small, 8, 'floor8') > 0)
    -- Churn real views, not unprotected direct preload calls. Overview stays pinned.
    local cycle = 0
    local function pan()
      cycle = cycle + 1
      center.x = 4112 + cycle % 12 * 8
      center.y = 4112 + math.floor(cycle / 12) % 12 * 8
      assert(frame(small, 32) > 0, 'Pan lost the ready HD overview under LRU pressure')
      if cycle < 100 then scheduleEvent(pan, 20); return end
      center.x, center.y = 4160, 4160
      g_minimap.clearSatellitePack()
      assert(frame(small, 8, 'classic') == 0)
      finish()
    end
    pan()
  end
  local function fullMap()
    -- Fractional zoom and odd dimensions catch independent-edge rounding gaps.
    assert(frame({width = 257, height = 259}, 5.5, 'fractional') > 0)
    local mini = modules.game_minimap.minimapWidget
    mini:setCameraPosition(center)
    mini:setZoom(4)
    modules.game_minimap.toggleFullMap()
    assert(modules.game_minimap.fullmapView)
    assert(frame(mini:getSize(), 16, 'full-map-pending') > 0, 'Full map exposed OTMM while HD loaded')
    modules.game_minimap.toggleFullMap()
    assert(not modules.game_minimap.fullmapView)
    assert(frame(small, 8, 'returned') > 0)
    g_minimap.setSatelliteTestDecodeDelay(0)
    center.z, polls = 8, 0
    floorWarm()
  end
  local function refine()
    polls = polls + 1
    assert(polls < 300)
    local level = frame(large, 16)
    assert(level > 0, 'Zoom transition exposed classic rectangles')
    if level == 2 then
      assert(partial, 'Did not exercise a partially completed target LOD')
      assert(frame(large, 16, 'refined') == 2)
      fullMap()
      return
    end
    local firstReady = g_minimap.preloadSatelliteTile({x = 4140, y = 4140, z = 7}, 16)
    if firstReady and not partial then
      partial = true
      assert(frame(large, 16, 'partial') == 4, 'Published an incomplete new LOD')
    end
    scheduleEvent(refine, 20)
  end
  local function warm()
    polls = polls + 1
    assert(polls < 300)
    if frame(small, 8) ~= 4 then scheduleEvent(warm, 20); return end
    assert(frame(small, 8, 'warm') == 4)
    assert(frame(large, 16, 'zoom-start') == 4)
    polls = 0
    refine()
  end
  warm()
end, 1000)
