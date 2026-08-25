-- private variables
local background

local hintsUpdateEvent
local hintsImgUpdateEvent
local enableCountdown = false
local countdownEndTime = os.time({year = 2025, month = 9, day = 04, hour = 19, min = 0, sec = 0})

local function getServerInfoByName(name)
  if Servers then
    for _, server in pairs(Servers) do
      if name == server.name then
        return server
      end
    end
  end
  return nil
end


-- public functions
function init()
  background = g_ui.displayUI('background')
  background:lower()

  connect(g_game, { onGameStart = onGameStart })
  connect(g_game, { onGameEnd = onGameEnd })
  connect(g_app, { onRun = onRun })

  -- Load and apply settings persistence
  local showAnimation = g_settings.getBoolean('background-animation', true)
  background.toggleVideo:setChecked(showAnimation)
  toggleVideo(showAnimation)

  local playSound = g_settings.getBoolean('enableMusicSound', true)
  background.toggleSound:setChecked(playSound)
  toggleSound(playSound)

  updateCountdown()
end

function onRun()
  G.clientVersion = GameInfo.version
  g_game.setClientVersion(G.clientVersion)
  g_game.setStringVersion(GameInfo.strVersion)
  g_game.setProtocolVersion(g_game.getClientProtocolVersion(G.clientVersion))
  -- Carrega os arquivos things (dat e spr)
  addEvent(function() modules.game_things.load() end)
  -- requestHintsJson()
  updateStatus()

  if g_settings.getBoolean('resetconfig') ~= true then
    g_settings.set('resetconfig', true)
    g_settings.save()
  end
end

function showPanel()
  background.loadAfter:setVisible(true)
end

function terminate()
  disconnect(g_game, { onGameStart = onGameStart })
  disconnect(g_game, { onGameEnd = onGameEnd })
  disconnect(g_app, { onRun = onRun })

  removeEvent(hintsUpdateEvent)
  removeEvent(hintsImgUpdateEvent)
  if Cast then Cast.terminate() end
  background:destroy()

  Background = nil
end

function onGameStart()
  local benchmark = g_clock.millis()
  hide()
  if Cast then Cast.onGameStart() end
  consoleln("Background loaded in " .. (g_clock.millis() - benchmark) / 1000 .. " seconds.")
end

function onGameEnd()
  if Cast then Cast.onGameEnd() end
  show()

  local playSound = g_settings.getBoolean('enableMusicSound', true)
  if playSound then
    local musicChannel = g_sounds.getChannel(1)
    if musicChannel then
      musicChannel:stop()
      musicChannel:enqueue("/sounds/intro.ogg", 3)
    end
  end
end

function hide()
  background:hide()
end

function show()
  if background:isVisible() then return end
  background:show()
  if Cast then Cast.updateStatus() end
end

function getBackground()
  return background
end

function showIcon()
  background:getChildById('logo'):hide()
end

function hideIcon()
  background:getChildById('logo'):hide()
end

function updateStatus(serverInfo)
  if not serverInfo then
    local serverName = g_settings.get('server')
    serverInfo = getServerInfoByName(serverName)
    if not serverInfo and Servers then
      serverInfo = Servers[1]
    end
  end

  if Cast then Cast.updateStatus(serverInfo) end
end

function toggleLogo(visible)
  background.logo:setVisible(false)
end

function toggleVideo(checked)
  if background and background.videoBackground then
    background.videoBackground:setVisible(checked)
  end
  g_settings.set('background-animation', checked)
  g_settings.save()
end

function toggleSound(checked)
  if g_sounds then
    g_sounds.setAudioEnabled(checked)
  end
  local musicChannel = g_sounds.getChannel(1)
  if musicChannel then
    musicChannel:setEnabled(checked)
    if checked then
      local volume = g_settings.getInteger('musicSoundVolume', 50)
      if volume == 0 then
        volume = 50
        g_settings.set('musicSoundVolume', volume)
      end
      musicChannel:setGain(volume / 100)
      musicChannel:stop()
      musicChannel:enqueue("/sounds/intro.ogg", 3)
    else
      musicChannel:stop(3)
    end
  end
  g_settings.set('enableMusicSound', checked)
  g_settings.save()
end

function requestHintsJson()
  removeEvent(hintsUpdateEvent)

  if not serverInfo then
    local serverName = g_settings.get('server')
    serverInfo = getServerInfoByName(serverName)
    if not serverInfo and Servers then
      serverInfo = Servers[1]
    end
  end

  local widget = background.loadAfter.randomHints.hintsPanel
  if not widget then return end
  if g_game.isOnline() then return end

  if not serverInfo or type(serverInfo.hintsJson) ~= 'string' or serverInfo.hintsJson:len() < 4 then
    return
  end

  local url = serverInfo.hintsJson

  HTTP.postJSON(url, {}, function(data, err)
    if err then
      g_logger.warning("HTTP error for " .. url .. ": " .. err)
      hintsUpdateEvent = scheduleEvent(requestHintsJson, 60000)
      return
    end

    math.randomseed(os.time())
    local hintsJson = data[math.random(1, #data)]
    hintsImgUpdateEvent = requestImgHintsJson(hintsJson)
  end)

end


function requestImgHintsJson(hintsJson)
  removeEvent(hintsImgUpdateEvent)

  local widget = background.loadAfter.randomHints.hintsPanel
  if not widget then return end
  if g_game.isOnline() then return end

  widget:setHTML(hintsJson["richText"])

  local title = background.loadAfter.randomHints.title
  if title then
    title:setText(hintsJson["title"])
  end
end



function updateCountdown()
  local countdownWindow = background.loadAfter.openingScroll
  if not enableCountdown then
    countdownWindow:setVisible(false)
    return
  end

  if not countdownWindow then 
    return 
  end

  local separator1 = countdownWindow:recursiveGetChildById("separator1")
  local separator2 = countdownWindow:recursiveGetChildById("separator2")
  local separator3 = countdownWindow:recursiveGetChildById("separator3")
  local worldName = countdownWindow:recursiveGetChildById("worldName")
  local infoCountLabel = countdownWindow:recursiveGetChildById("infoCountLabel")
  local pvpType = countdownWindow:recursiveGetChildById("pvpType")

  separator1:setImageShader("text_green")
  separator2:setImageShader("text_green")
  separator3:setImageShader("text_green")
  infoCountLabel:setImageShader("text_green")
  worldName:setImageShader("text_staff")

  local timeNow = os.time()
  local remaining = countdownEndTime - timeNow

  if remaining <= 0 then
    for i = 1, 8 do
      local digitWidget = countdownWindow:recursiveGetChildById("digit" .. i)
      if digitWidget then
        digitWidget:setVisible(false)
      end
    end
    separator1:setVisible(false)
    separator2:setVisible(false)
    separator3:setVisible(false)
    pvpType:setVisible(true)
    infoCountLabel:setMarginTop(10)
    infoCountLabel:setText("Server is now open!")
    return
  end

  local days = math.floor(remaining / 86400)
  local hours = math.floor((remaining % 86400) / 3600)
  local minutes = math.floor((remaining % 3600) / 60)
  local seconds = remaining % 60

  local timeStr = string.format("%02d%02d%02d%02d", days, hours, minutes, seconds)

  for i = 1, 8 do
    local digitWidget = countdownWindow:recursiveGetChildById("digit" .. i)
    if digitWidget then
      local digit = string.sub(timeStr, i, i)
      digitWidget:setImageSource("/images/ui/numbers/number-" .. digit)
      digitWidget:setImageShader("text_green")
      digitWidget:setVisible(true)
      pvpType:setVisible(false)
      infoCountLabel:setMarginTop(2)
    end
  end

  scheduleEvent(updateCountdown, 1000)
end
