
local statsWindow = nil
local statsButton = nil
local luaStats = nil
local luaCallback = nil
local mainStats = nil
local dispatcherStats = nil
local render = nil
local atlas = nil
local adaptiveRender = nil
local slowMain = nil
local slowRender = nil
local widgetsInfo = nil
local packets
local slowPackets

local updateEvent = nil
local monitorEvent = nil
local iter = 0
local lastSend = 0
local sendInterval = 60 -- 1 m
local fps = {}
local ping = {}
local lastSleepTimeReset = 0

function init()
  if not DEVELOPERMODE then
    return
  end

  statsButton = modules.client_topmenu.addLeftButton('statsButton', 'Debug Info', '/images/topbuttons/debug', toggle)
  statsButton:setOn(false)

  statsWindow = g_ui.displayUI('stats')
  statsWindow:hide()

  g_keyboard.bindKeyDown('Ctrl+Alt+D', toggle)

  luaStats = statsWindow:recursiveGetChildById('luaStats')
  luaCallback = statsWindow:recursiveGetChildById('luaCallback')
  mainStats = statsWindow:recursiveGetChildById('mainStats')
  dispatcherStats = statsWindow:recursiveGetChildById('dispatcherStats')
  render = statsWindow:recursiveGetChildById('render')
  atlas = statsWindow:recursiveGetChildById('atlas')
  packets = statsWindow:recursiveGetChildById('packets')
  adaptiveRender = statsWindow:recursiveGetChildById('adaptiveRender')
  slowMain = statsWindow:recursiveGetChildById('slowMain')
  slowRender = statsWindow:recursiveGetChildById('slowRender')
  slowPackets = statsWindow:recursiveGetChildById('slowPackets')
  widgetsInfo = statsWindow:recursiveGetChildById('widgetsInfo')

  lastSend = os.time()
  g_stats.resetSleepTime()
  lastSleepTimeReset = g_clock.micros()

  updateEvent = scheduleEvent(update, 2000)
  monitorEvent = scheduleEvent(monitor, 1000)
end

function terminate()
  if not DEVELOPERMODE then
    return
  end

  statsWindow:destroy()
  statsButton:destroy()

  g_keyboard.unbindKeyDown('Ctrl+Alt+D')

  removeEvent(updateEvent)
  removeEvent(monitorEvent)
end

function onClose()
  statsButton:setOn(false)
end

function toggle()
  if statsButton:isOn() then
    statsWindow:hide()
    statsButton:setOn(false)
  else
    statsWindow:show()
    statsWindow:raise()
    statsWindow:focus()
    statsButton:setOn(true)
  end
end

function monitor()
  if #fps > 1000 then
    fps = {}
  end
  if #ping > 1000 then
    ping = {}
  end
  table.insert(fps, g_app.getFps())
  table.insert(ping, g_game.getPing())
  monitorEvent = scheduleEvent(monitor, 1000)
end

function sendStats()
  lastSend = os.time()
  local localPlayer = g_game.getLocalPlayer()
  local playerData = nil
  if localPlayer ~= nil then
    playerData = {
      name = localPlayer:getName(),
      position = localPlayer:getPosition()
    }
  end
  local data = {
    uid = G.UUID,
    stats = {},
    slow = {},
    render = g_adaptiveRenderer.getDebugInfo(),
    player = playerData,
    fps = fps,
    ping = ping,
    sleepTime = math.round(g_stats.getSleepTime() / math.max(1, g_clock.micros() - lastSleepTimeReset), 2),
    proxy = {},

    details = {
      report_delay = sendInterval,
      os = g_app.getOs(),
      graphics_vendor = g_graphics.getVendor(),
      graphics_renderer = g_graphics.getRenderer(),
      graphics_version = g_graphics.getVersion(),
      fps = g_app.getFps(),
      maxFps = g_app.getMaxFps(),
      atlas = g_atlas.getStats(),
      classic = tostring(g_settings.getBoolean("classicView")),
      fullscreen = tostring(g_window.isFullscreen()),
      vsync = tostring(g_settings.getBoolean("vsync")),
      autoReconnect = tostring(g_settings.getBoolean("autoReconnect")),
      window_width = g_window.getWidth(),
      window_height = g_window.getHeight(),
      player_name = g_game.getCharacterName(),
      world_name = g_game.getWorldName(),
      otserv_host = G.host,
      otserv_protocol = g_game.getProtocolVersion(),
      otserv_client = g_game.getClientVersion(),
      build_version = g_app.getVersion(),
      build_revision = g_app.getBuildRevision(),
      build_commit = g_app.getBuildCommit(),
      build_date = g_app.getBuildDate(),
      display_width = g_window.getDisplayWidth(),
      display_height = g_window.getDisplayHeight(),
      cpu = g_platform.getCPUName(),
      mem = g_platform.getTotalSystemMemory(),
      mem_usage = g_platform.getMemoryUsage(),
      lua_mem_usage = gcinfo(),
      os_name = g_platform.getOSName(),
      platform = g_window.getPlatformType(),
      uptime = g_clock.seconds(),
      layout = g_resources.getLayout(),
      packets = g_game.getRecivedPacketsCount(),
      packets_size = g_game.getRecivedPacketsSize()
    }
  }
  if g_proxy then
    data["proxy"] = g_proxy.getProxiesDebugInfo()
  end
  lastSleepTimeReset = g_clock.micros()
  g_stats.resetSleepTime()
  for i = 1, g_stats.types() do
    table.insert(data.stats, g_stats.get(i - 1, 10, false))
    table.insert(data.slow, g_stats.getSlow(i - 1, 50, 10, false))
    g_stats.clear(i - 1)
    g_stats.clearSlow(i - 1)
  end
  data.widgets = g_stats.getWidgetsInfo(10, false)
  data = json.encode(data, 1)
  if Services.stats ~= nil and ClientSecurity.canSendCredentials(Services.stats) then
    g_http.post(Services.stats, data)
  end
  fps = {}
  ping = {}
end

function update()
  updateEvent = scheduleEvent(update, 20)
  if lastSend + sendInterval < os.time() then
    sendStats()
  end

  if not statsWindow:isVisible() then
    return
  end

  iter = (iter + 1) % 9 -- some functions are slow (~5ms), it will avoid lags
  if iter == 0 then
    statsWindow.debugPanel.sleepTime:setText("GFPS: " .. g_app.getGraphicsFps() .. " PFPS: " .. g_app.getProcessingFps() .. " Packets: " .. g_game.getRecivedPacketsCount() .. " , " .. (g_game.getRecivedPacketsSize() / 1024) .. " KB")
    statsWindow.debugPanel.luaRamUsage:setText("Ram usage by lua: " .. gcinfo() .. " kb")
  elseif iter == 1 then
    local adaptive = "Adaptive: " .. g_adaptiveRenderer.getLevel() .. " | " .. g_adaptiveRenderer.getDebugInfo()
    adaptiveRender:setText(adaptive)
    atlas:setText("Atlas: " .. g_atlas.getStats())
  elseif iter == 2 then
    render:setText(g_stats.get(STATS_RENDER, 10, true))
    mainStats:setText(g_stats.get(STATS_MAIN, 5, true))
    dispatcherStats:setText(g_stats.get(STATS_DISPATCHER, 30, true))
  elseif iter == 3 then
    luaStats:setText(g_stats.get(STATS_LUA, 30, true))
    luaCallback:setText(g_stats.get(STATS_LUACALLBACK, 30, true))
  elseif iter == 4 then
    slowMain:setText(g_stats.getSlow(STATS_DISPATCHER, 10, 10, true) .. "\n\n\n" .. g_stats.getSlow(STATS_MAIN, 20, 20, true))
  elseif iter == 5 then
    slowRender:setText(g_stats.getSlow(STATS_RENDER, 10, 10, true))
  elseif iter == 6 then
    --disabled because takes a lot of cpu
    widgetsInfo:setText(g_stats.getWidgetsInfo(10, true))
  elseif iter == 7 then
    packets:setText(g_stats.get(STATS_PACKETS, 10, true))
    slowPackets:setText(g_stats.getSlow(STATS_PACKETS, 10, 10, true))
  elseif iter == 8 then
    if g_proxy then
      local proxiesDebug = g_proxy.getProxiesDebugInfo()

      local displayProxy = {}
      for proxy_name, proxy_debug in pairs(proxiesDebug) do
        local result = {}
        local out = proxy_name.." - " .. proxy_debug

        result.address, result.port,
        result.p, result.rp,
        result.in_count, result.in_bytes,
        result.out_count, result.out_bytes,
        result.conns, result.sess,
        result.r = out:match(
            "([%d%.]+):(%d+)%s%-%sP:%s*(%d+)%s+RP:%s*(%d+)%s+In:%s*(%d+)%s+%((%d+)%)%s+Out:%s*(%d+)%s+%((%d+)%)%s+Conns:%s*(%d+)%s+Sess:%s*(%d+)%s+R:%s*([%d%.]+)"
        )

        if tonumber(result.sess) >= 1 then
          displayProxy[#displayProxy+1] =  string.format("[color=\"$var-text-cip-color-green\"]%s - P: %s RP: %s In: %s (%s) Out: %s (%s) Conns: %s Sess: %s R: %s[/color]",
            proxy_name, result.p, result.rp, result.in_count, result.in_bytes,
            result.out_count, result.out_bytes, result.conns, result.sess, result.r
          )
        elseif tonumber(result.in_count) == 0 or tonumber(result.p) == 0 then
          displayProxy[#displayProxy+1] =  string.format("[color=\"$var-text-cip-color-light-red\"]%s - P: %s RP: %s In: %s (%s) Out: %s (%s) Conns: %s Sess: %s R: %s[/color]",
            proxy_name, result.p, result.rp, result.in_count, result.in_bytes,
            result.out_count, result.out_bytes, result.conns, result.sess, result.r
          )
        else
          displayProxy[#displayProxy+1] =  string.format("%s - P: %s RP: %s In: %s (%s) Out: %s (%s) Conns: %s Sess: %s R: %s",
            proxy_name, result.p, result.rp, result.in_count, result.in_bytes,
            result.out_count, result.out_bytes, result.conns, result.sess, result.r
          )
        end
      end
      table.sort(displayProxy, function(a, b)
        local aP = tonumber(a:match("Sess: (%d+)")) or math.huge
        local bP = tonumber(b:match("Sess: (%d+)")) or math.huge
        return aP > bP
      end)

      statsWindow.debugPanel.proxies:setColorText(table.concat(displayProxy, "\n"))
    end
  end
end
