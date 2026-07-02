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
  connect(g_game, { onGameEnd = show })
  connect(g_app, { onRun = onRun })
  updateCountdown()
end

function onRun()
  -- Single source of truth for the client version (init.lua CLIENT_VERSION).
  G.clientVersion = tonumber(CLIENT_VERSION)
  g_game.setClientVersion(G.clientVersion)
  g_game.setStringVersion(GameInfo.strVersion)
  g_game.setProtocolVersion(g_game.getClientProtocolVersion(G.clientVersion))
  -- NB: setClientVersion(...) above fires onClientVersionChange ->
  -- game_features.updateFeatures -> game_things.load(), so the assets are
  -- already loaded here. A second explicit load() would just reparse the same
  -- catalog/appearances (the "Loaded ... appearances" line printed 2-3x in the
  -- boot log), so it was removed.
  -- requestHintsJson()
  updateStatus()
  requestScheduleJson()

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
  disconnect(g_game, { onGameEnd = show })
  disconnect(g_app, { onRun = onRun })

  removeEvent(statusUpdateEvent)
  removeEvent(hintsUpdateEvent)
  removeEvent(hintsImgUpdateEvent)
  removeEvent(scheduleUpdateEvent)
  background:destroy()

  Background = nil
end

function onGameStart()
  local benchmark = g_clock.millis()
  hide()
  consoleln("Background loaded in " .. (g_clock.millis() - benchmark) / 1000 .. " seconds.")
end

function hide()
  background:hide()
end

function show()
  background:show()
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
  removeEvent(statusUpdateEvent)

  if not serverInfo then
    local serverName = g_settings.get('server')
    serverInfo = getServerInfoByName(serverName)
    if not serverInfo and Servers then
      serverInfo = Servers[1]
    end
  end

  miniWindowBoosted = background.loadAfter.boostedScroll
  if not miniWindowBoosted then return end
  if g_game.isOnline() then return end

  if not serverInfo or type(serverInfo.clientServicesLink) ~= 'string' or serverInfo.clientServicesLink:len() < 4 then
    return
  end

  local url = serverInfo.clientServicesLink

  statusUpdateEvent = scheduleEvent(function()
    updateStatus(serverInfo)
  end, 60000)
  HTTP.postJSON(url, {type="boostedcreature"}, function(data, err)
    if err then
      g_logger.warning("HTTP error for " .. url .. ": " .. err)
      statusUpdateEvent = scheduleEvent(updateStatus, 60000, serverInfo)
      return
    end

    if not data then
      return
    end

    -- possivelmente o cabra logou
    if not miniWindowBoosted then return end
    local creature = g_things.getMonsterList()[data.creatureraceid]
    if creature then
      miniWindowBoosted.creature:setImageSource("")
      miniWindowBoosted.creature:setOutfit({type = creature[2], auxType = creature[3], head = creature[4], body = creature[5], legs = creature[6], feet = creature[7], addons = creature[8]})
      miniWindowBoosted.creature:setTooltip("Today's boosted creature: ".. creature[1] .."\n\n\tBoosted creatures yield more experience\n points, carry more loot than usual\n and respawn at a faster rate.")
    end

    local creature = g_things.getMonsterList()[data.bossraceid]
    if creature then
      miniWindowBoosted.boss:setImageSource("")
      miniWindowBoosted.boss:setOutfit({type = creature[2], auxType = creature[3], head = creature[4], body = creature[5], legs = creature[6], feet = creature[7], addons = creature[8]})
      miniWindowBoosted.boss:setTooltip("Today's boosted boss: ".. creature[1] .."\n\n\tBoosted boss contain more loot and\n count more kills for your bosstiary.")
    end
  end)
end

function toggleLogo(visible)
  background.logo:setVisible(false)
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

function requestScheduleJson(serverInfo)
  removeEvent(scheduleUpdateEvent)

  if not serverInfo then
    local serverName = g_settings.get('server')
    serverInfo = getServerInfoByName(serverName)
    if not serverInfo and Servers then
      serverInfo = Servers[1]
    end
  end

  local widget = background.loadAfter.informationScroll
  if not widget then return end

  if not serverInfo or type(serverInfo.clientServicesLink) ~= 'string' or serverInfo.clientServicesLink:len() < 4 then
    return
  end

  local url = serverInfo.clientServicesLink

  if g_game.isOnline() then return end
  HTTP.postJSON(url, {type = "eventschedule"}, function(data, err)
    if err then
      g_logger.warning("HTTP error for " .. url .. ": " .. err)
      scheduleUpdateEvent = scheduleEvent(requestScheduleJson, 60000)
      return
    end
    if not data then return end
    EventSchedule.events = data.eventlist
    EventSchedule:configureEvent(widget)
  end)
end


function updateCountdown()
  local countdownWindow = background.loadAfter.openingScroll
  if not enableCountdown then
    countdownWindow:setVisible(false)
    local informationScroll = background.loadAfter.informationScroll
    if informationScroll then
      informationScroll:setMarginRight(124)
    end
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
