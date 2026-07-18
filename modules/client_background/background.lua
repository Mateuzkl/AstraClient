-- private variables
local background

local hintsUpdateEvent
local hintsImgUpdateEvent
local enableCountdown = false
local countdownEndTime = os.time({year = 2025, month = 9, day = 04, hour = 19, min = 0, sec = 0})
local boostedCreatureInfo = nil
local boostedBossInfo = nil

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

local function resolveBoostedInfo(info)
  if type(info) == 'number' or type(info) == 'string' then
    local raceId = tonumber(info)
    local creature = raceId and g_things.getMonsterList()[raceId] or nil
    if not creature then
      return nil
    end

    return {
      raceId = raceId,
      name = creature[1],
      outfit = {
        type = creature[2],
        auxType = creature[3],
        head = creature[4],
        body = creature[5],
        legs = creature[6],
        feet = creature[7],
        addons = creature[8]
      }
    }
  end

  if type(info) ~= 'table' then
    return nil
  end

  if info.outfit then
    return info
  end

  return resolveBoostedInfo(info.raceId or info.raceid or info.creatureraceid or info.bossraceid)
end

local function setBoostedWidget(widget, info, tooltip)
  if not widget then
    return
  end

  info = resolveBoostedInfo(info)
  if not info or not info.outfit then
    widget:setImageSource("/images/ui/unknownoutfit")
    widget:setTooltip("")
    return
  end

  local outfit = info.outfit
  widget:setImageSource("")
  widget:setOutfit({
    type = outfit.type or outfit.lookType or 0,
    auxType = outfit.auxType or outfit.typeEx or outfit.lookTypeEx or 0,
    head = outfit.head or outfit.lookHead or 0,
    body = outfit.body or outfit.lookBody or 0,
    legs = outfit.legs or outfit.lookLegs or 0,
    feet = outfit.feet or outfit.lookFeet or 0,
    addons = outfit.addons or outfit.lookAddons or 0
  })
  widget:setTooltip(tooltip(info.name or "?"))
end

local function applyBoostedInfo()
  if not background or not background.loadAfter then
    return
  end

  local miniWindowBoosted = background.loadAfter.boostedScroll
  if not miniWindowBoosted then
    return
  end

  setBoostedWidget(miniWindowBoosted.creature, boostedCreatureInfo, function(name)
    return "Today's boosted creature: " .. name .. "\n\n\tBoosted creatures yield more experience\n points, carry more loot than usual\n and respawn at a faster rate."
  end)

  setBoostedWidget(miniWindowBoosted.boss, boostedBossInfo, function(name)
    return "Today's boosted boss: " .. name .. "\n\n\tBoosted boss contain more loot and\n count more kills for your bosstiary."
  end)
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
  G.clientVersion = GameInfo.version
  g_game.setClientVersion(G.clientVersion)
  g_game.setStringVersion(GameInfo.strVersion)
  g_game.setProtocolVersion(g_game.getClientProtocolVersion(G.clientVersion))
  -- Carrega os arquivos things (dat e spr)
  addEvent(function() modules.game_things.load() end)
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
  applyBoostedInfo()
end

function terminate()
  disconnect(g_game, { onGameStart = onGameStart })
  disconnect(g_game, { onGameEnd = show })
  disconnect(g_app, { onRun = onRun })

  removeEvent(statusUpdateEvent)
  removeEvent(hintsUpdateEvent)
  removeEvent(hintsImgUpdateEvent)
  removeEvent(scheduleUpdateEvent)
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

function hide()
  background:hide()
end

function show()
  background:show()
  applyBoostedInfo()
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
  removeEvent(statusUpdateEvent)

  if not serverInfo then
    local serverName = g_settings.get('server')
    serverInfo = getServerInfoByName(serverName)
    if not serverInfo and Servers then
      serverInfo = Servers[1]
    end
  end

  if Cast then Cast.updateStatus(serverInfo) end

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

    updateBoostedInfo(data.creature or data.creatureraceid, data.boss or data.bossraceid)
  end)
end

function updateBoostedInfo(creatureInfo, bossInfo)
  boostedCreatureInfo = creatureInfo
  boostedBossInfo = bossInfo
  applyBoostedInfo()
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
      informationScroll:setMarginRight(224)
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
