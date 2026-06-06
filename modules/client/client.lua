local musicFilename = "/sounds/startup"
local musicChannel = nil

function setMusic(filename)
  musicFilename = filename

  if not g_game.isOnline() and musicChannel ~= nil then
    musicChannel:stop()
    musicChannel:enqueue(musicFilename, 3)
  end
end

function reloadScripts()
  if g_game.getFeature(GameNoDebug) then
    return
  end

  if not DEVELOPERMODE then
    return
  end

  if not g_app.isDevMode() then
      return
  end
  g_textures.clearCache()
  g_modules.reloadModules()

  local script = '/' .. g_app.getCompactName() .. 'rc.lua'
  if g_resources.fileExists(script) then
    dofile(script)
  end

  local message = tr('All modules and scripts were reloaded.')

  modules.game_textmessage.displayGameMessage(message)
  print(message)
end

function startup()
  if g_sounds ~= nil then
    musicChannel = g_sounds.getChannel(1)
  end
  
  G.UUID = g_settings.getString('report-uuid')
  if not G.UUID or #G.UUID ~= 36 then
    G.UUID = g_crypt.genUUID()
    g_settings.set('report-uuid', G.UUID)
  end
  
  -- Play startup music (The Silver Tree, by Mattias Westlund)
  --musicChannel:enqueue(musicFilename, 3)
  connect(g_game, { onGameStart = function() if musicChannel ~= nil then musicChannel:stop(3) end end })
  connect(g_game, { onGameEnd = function()
      if g_sounds ~= nil then
        g_sounds.stopAll()
        --musicChannel:enqueue(musicFilename, 3)
      end
  end })
end

function init()
  connect(g_app, { onRun = startup,
                   onExit = exit })
  connect(g_game, { onGameStart = onGameStart,
                    onGameEnd = onGameEnd })

  if g_sounds ~= nil then
    --g_sounds.preload(musicFilename)
  end

  if not Updater then
    local platformType = g_window.getPlatformType()
    local isX11 = type(platformType) == 'string' and platformType:find('X11', 1, true) == 1
    local density = (isX11 and g_window.getDisplayDensity()) or 1
    local displaySize = g_window.getDisplaySize()
    local metricsSpace = g_settings.getString('window-metrics-space', '')
    local shouldScaleLegacySavedMetrics = isX11 and density ~= 1 and metricsSpace ~= 'physical-v1'

    --if g_resources.getLayout() == "mobile" then
      --g_window.setMinimumSize({ width = 640, height = 360 })
    --else
      local minSize = { width = 1490, height = 714 }
      if isX11 then
        minSize.width = math.max(1, math.min(minSize.width, displaySize.width))
        minSize.height = math.max(1, math.min(minSize.height, displaySize.height))
      end
      g_window.setMinimumSize(minSize)
    --end

    -- window size
    local hasSavedWindowSize = g_settings.exists('window-size')
    local size = { width = 1024, height = 600 }
    size = g_settings.getSize('window-size', size)
    if shouldScaleLegacySavedMetrics and hasSavedWindowSize then
      size = {
        width = math.floor((size.width * density) + 0.5),
        height = math.floor((size.height * density) + 0.5)
      }
    end
    if isX11 then
      size.width = math.max(1, math.min(size.width, displaySize.width))
      size.height = math.max(1, math.min(size.height, displaySize.height))
    end
    g_window.resize(size)

    -- window position, default is the screen center
    local defaultPos = { x = (displaySize.width - size.width)/2,
                         y = (displaySize.height - size.height)/2 }
    local pos = defaultPos
    if not isX11 then
      pos = g_settings.getPoint('window-pos', defaultPos)
    end
    if isX11 then
      local maxX = math.max(displaySize.width - size.width, 0)
      local maxY = math.max(displaySize.height - size.height, 0)
      pos.x = math.max(0, math.min(pos.x, maxX))
      pos.y = math.max(0, math.min(pos.y, maxY))
    else
      pos.x = math.max(pos.x, 0)
      pos.y = math.max(pos.y, 0)
    end
    g_window.move(pos)

    -- window maximized?
    local maximized = g_settings.getBoolean('window-maximized', false)
    if maximized then g_window.maximize() end
  end

  g_window.setTitle(g_app.getName())
  g_window.setIcon('/images/clienticon')

  -- g_keyboard.bindKeyDown('Ctrl+Shift+R', reloadScripts)

  -- generate machine uuid, this is a security measure for storing passwords
  if not g_crypt.setMachineUUID(g_settings.get('uuid')) then
    g_settings.set('uuid', g_crypt.getMachineUUID())
    g_settings.save()
  end
end

function terminate()
  disconnect(g_app, { onRun = startup,
                      onExit = exit })
  disconnect(g_game, { onGameStart = onGameStart,
                       onGameEnd = onGameEnd })
  -- save window configs
  local platformType = g_window.getPlatformType()
  local isX11 = type(platformType) == 'string' and platformType:find('X11', 1, true) == 1
  g_settings.set('window-size', g_window.getUnmaximizedSize())
  if isX11 then
    g_settings.remove('window-pos')
    g_settings.set('window-metrics-space', 'physical-v1')
  else
    g_settings.set('window-pos', g_window.getUnmaximizedPos())
    g_settings.remove('window-metrics-space')
  end
  g_settings.set('window-maximized', g_window.isMaximized())
end

function exit()
  KeyBinds:offline()
  g_logger.info("Exiting application..")
end

function onGameStart()
  local benchmark = g_clock.millis()

  if LoadedPlayer:isLoaded() then
    local function extractNumbers(str)
      local numbers = str:match("%d+")
      return numbers or false
    end

    local numberedName = extractNumbers(LoadedPlayer:getName())
    if numberedName then
      g_window.setTitle(g_app.getName() .. " - CAM" .. numberedName)
    else
      g_window.setTitle(g_app.getName() .. " - " .. LoadedPlayer:getName())
    end
  end

  consoleln("Game loaded in " .. (g_clock.millis() - benchmark) / 1000 .. " seconds.")
end

function onGameEnd()
  g_window.setTitle(g_app.getName())
end
