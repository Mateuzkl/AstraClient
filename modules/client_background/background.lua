-- private variables
local background

local thingsLoadEvent
local statusUpdateEvent
local hintsUpdateEvent
local scheduleUpdateEvent
local countdownUpdateEvent

local statusRequestId = 0
local hintsRequestId = 0
local scheduleRequestId = 0
local moduleActive = false

local enableCountdown = false
local countdownEndTime = os.time({ year = 2025, month = 9, day = 4, hour = 19, min = 0, sec = 0 })
local boostedCreatureInfo
local boostedBossInfo

local function removeScheduledEvent(event)
  if event then
    removeEvent(event)
  end
end

local function getServerInfoByName(name)
  if not Servers then
    return nil
  end

  for _, server in pairs(Servers) do
    if name == server.name then
      return server
    end
  end

  return nil
end

local function resolveServerInfo(serverInfo)
  if serverInfo then
    return serverInfo
  end

  local serverName = g_settings.get('server')
  serverInfo = getServerInfoByName(serverName)
  if not serverInfo and Servers then
    serverInfo = Servers[1]
  end

  return serverInfo
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

local function setBoostedWidget(widget, info, tooltipBuilder)
  if not widget then
    return
  end

  info = resolveBoostedInfo(info)
  if not info or not info.outfit then
    widget:setImageSource('/images/ui/unknownoutfit')
    widget:setTooltip('')
    return
  end

  local outfit = info.outfit
  widget:setImageSource('')
  widget:setOutfit({
    type = outfit.type or outfit.lookType or 0,
    auxType = outfit.auxType or outfit.typeEx or outfit.lookTypeEx or 0,
    head = outfit.head or outfit.lookHead or 0,
    body = outfit.body or outfit.lookBody or 0,
    legs = outfit.legs or outfit.lookLegs or 0,
    feet = outfit.feet or outfit.lookFeet or 0,
    addons = outfit.addons or outfit.lookAddons or 0
  })
  widget:setTooltip(tooltipBuilder(info.name or '?'))
end

local function boostedCreatureTooltip(name)
  return "Today's boosted creature: " .. name ..
    "\n\n\tBoosted creatures yield more experience\n points, carry more loot than usual\n and respawn at a faster rate."
end

local function boostedBossTooltip(name)
  return "Today's boosted boss: " .. name ..
    "\n\n\tBoosted boss contain more loot and\n count more kills for your bosstiary."
end

local function applyBoostedInfo()
  if not background or not background.loadAfter then
    return
  end

  local miniWindowBoosted = background.loadAfter.boostedScroll
  if not miniWindowBoosted then
    return
  end

  setBoostedWidget(miniWindowBoosted.creature, boostedCreatureInfo, boostedCreatureTooltip)
  setBoostedWidget(miniWindowBoosted.boss, boostedBossInfo, boostedBossTooltip)
end

local function loadThings()
  thingsLoadEvent = nil
  if not moduleActive then
    return
  end

  if modules.game_things and modules.game_things.load then
    modules.game_things.load()
  end
end

local function scheduledStatusUpdate(serverInfo)
  statusUpdateEvent = nil
  if moduleActive then
    updateStatus(serverInfo)
  end
end

local function scheduledHintsUpdate(serverInfo)
  hintsUpdateEvent = nil
  if moduleActive then
    requestHintsJson(serverInfo)
  end
end

local function scheduledScheduleUpdate(serverInfo)
  scheduleUpdateEvent = nil
  if moduleActive then
    requestScheduleJson(serverInfo)
  end
end

local function countdownTick()
  countdownUpdateEvent = nil
  if moduleActive then
    updateCountdown()
  end
end

-- public functions
function init()
  if background then
    return
  end

  moduleActive = true
  background = g_ui.displayUI('background')
  background:lower()

  connect(g_game, {
    onGameStart = onGameStart,
    onGameEnd = show
  })
  connect(g_app, { onRun = onRun })

  updateCountdown()
end

function onRun()
  if not moduleActive then
    return
  end

  G.clientVersion = GameInfo.version
  g_game.setClientVersion(G.clientVersion)
  g_game.setStringVersion(GameInfo.strVersion)
  g_game.setProtocolVersion(g_game.getClientProtocolVersion(G.clientVersion))

  removeScheduledEvent(thingsLoadEvent)
  thingsLoadEvent = addEvent(loadThings)

  updateStatus()
  requestScheduleJson()

  if not g_settings.getBoolean('resetconfig') then
    g_settings.set('resetconfig', true)
    g_settings.save()
  end
end

function showPanel()
  if not background or not background.loadAfter then
    return
  end

  background.loadAfter:setVisible(true)
  applyBoostedInfo()
end

function terminate()
  moduleActive = false
  statusRequestId = statusRequestId + 1
  hintsRequestId = hintsRequestId + 1
  scheduleRequestId = scheduleRequestId + 1

  disconnect(g_game, {
    onGameStart = onGameStart,
    onGameEnd = show
  })
  disconnect(g_app, { onRun = onRun })

  removeScheduledEvent(thingsLoadEvent)
  removeScheduledEvent(statusUpdateEvent)
  removeScheduledEvent(hintsUpdateEvent)
  removeScheduledEvent(scheduleUpdateEvent)
  removeScheduledEvent(countdownUpdateEvent)

  thingsLoadEvent = nil
  statusUpdateEvent = nil
  hintsUpdateEvent = nil
  scheduleUpdateEvent = nil
  countdownUpdateEvent = nil

  if Cast then
    Cast.terminate()
  end

  if EventSchedule and EventSchedule.clear then
    EventSchedule:clear()
  end

  if background then
    background:destroy()
    background = nil
  end

  boostedCreatureInfo = nil
  boostedBossInfo = nil
end

function onGameStart()
  local benchmark = g_clock.millis()
  hide()

  if Cast then
    Cast.onGameStart()
  end

  consoleln('Background loaded in ' .. (g_clock.millis() - benchmark) / 1000 .. ' seconds.')
end

function hide()
  if background then
    background:hide()
  end
end

function show()
  if not background then
    return
  end

  background:show()
  applyBoostedInfo()

  if Cast then
    Cast.updateStatus()
  end
end

function getBackground()
  return background
end

function showIcon()
  if background then
    background:getChildById('logo'):hide()
  end
end

function hideIcon()
  if background then
    background:getChildById('logo'):hide()
  end
end

function updateStatus(serverInfo)
  removeScheduledEvent(statusUpdateEvent)
  statusUpdateEvent = nil

  statusRequestId = statusRequestId + 1
  local requestId = statusRequestId

  if not moduleActive or not background or not background.loadAfter then
    return
  end

  serverInfo = resolveServerInfo(serverInfo)

  if Cast then
    Cast.updateStatus(serverInfo)
  end

  local miniWindowBoosted = background.loadAfter.boostedScroll
  if not miniWindowBoosted or g_game.isOnline() then
    return
  end

  if not serverInfo or type(serverInfo.clientServicesLink) ~= 'string' or serverInfo.clientServicesLink:len() < 4 then
    return
  end

  local url = serverInfo.clientServicesLink
  statusUpdateEvent = scheduleEvent(scheduledStatusUpdate, 60000, serverInfo)

  HTTP.postJSON(url, { type = 'boostedcreature' }, function(data, err)
    if not moduleActive or requestId ~= statusRequestId or not background then
      return
    end

    if err then
      g_logger.warning('HTTP error for ' .. url .. ': ' .. tostring(err))
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
  if background and background.logo then
    background.logo:setVisible(false)
  end
end

function requestHintsJson(serverInfo)
  removeScheduledEvent(hintsUpdateEvent)
  hintsUpdateEvent = nil

  hintsRequestId = hintsRequestId + 1
  local requestId = hintsRequestId

  if not moduleActive or not background or not background.loadAfter then
    return
  end

  serverInfo = resolveServerInfo(serverInfo)

  local randomHints = background.loadAfter.randomHints
  local widget = randomHints and randomHints.hintsPanel or nil
  if not widget or g_game.isOnline() then
    return
  end

  if not serverInfo or type(serverInfo.hintsJson) ~= 'string' or serverInfo.hintsJson:len() < 4 then
    return
  end

  local url = serverInfo.hintsJson
  HTTP.postJSON(url, {}, function(data, err)
    if not moduleActive or requestId ~= hintsRequestId or not background then
      return
    end

    if err then
      g_logger.warning('HTTP error for ' .. url .. ': ' .. tostring(err))
      hintsUpdateEvent = scheduleEvent(scheduledHintsUpdate, 60000, serverInfo)
      return
    end

    if type(data) ~= 'table' or #data == 0 then
      return
    end

    requestImgHintsJson(data[math.random(1, #data)])
  end)
end

function requestImgHintsJson(hintsJson)
  if not moduleActive or type(hintsJson) ~= 'table' or not background or not background.loadAfter then
    return
  end

  local randomHints = background.loadAfter.randomHints
  local widget = randomHints and randomHints.hintsPanel or nil
  if not widget or g_game.isOnline() then
    return
  end

  widget:setHTML(tostring(hintsJson.richText or ''))

  local title = randomHints.title
  if title then
    title:setText(tostring(hintsJson.title or ''))
  end
end

function requestScheduleJson(serverInfo)
  removeScheduledEvent(scheduleUpdateEvent)
  scheduleUpdateEvent = nil

  scheduleRequestId = scheduleRequestId + 1
  local requestId = scheduleRequestId

  if not moduleActive or not background or not background.loadAfter then
    return
  end

  serverInfo = resolveServerInfo(serverInfo)

  local widget = background.loadAfter.informationScroll
  if not widget or g_game.isOnline() then
    return
  end

  if not serverInfo or type(serverInfo.clientServicesLink) ~= 'string' or serverInfo.clientServicesLink:len() < 4 then
    return
  end

  local url = serverInfo.clientServicesLink
  HTTP.postJSON(url, { type = 'eventschedule' }, function(data, err)
    if not moduleActive or requestId ~= scheduleRequestId or not background then
      return
    end

    if err then
      g_logger.warning('HTTP error for ' .. url .. ': ' .. tostring(err))
      scheduleUpdateEvent = scheduleEvent(scheduledScheduleUpdate, 60000, serverInfo)
      return
    end

    if type(data) ~= 'table' then
      return
    end

    EventSchedule.events = type(data.eventlist) == 'table' and data.eventlist or {}
    EventSchedule:configureEvent(widget)
  end)
end

function updateCountdown()
  removeScheduledEvent(countdownUpdateEvent)
  countdownUpdateEvent = nil

  if not moduleActive or not background or not background.loadAfter then
    return
  end

  local countdownWindow = background.loadAfter.openingScroll
  if not countdownWindow then
    return
  end

  if not enableCountdown then
    countdownWindow:setVisible(false)
    local informationScroll = background.loadAfter.informationScroll
    if informationScroll then
      informationScroll:setMarginRight(224)
    end
    return
  end

  local separator1 = countdownWindow:recursiveGetChildById('separator1')
  local separator2 = countdownWindow:recursiveGetChildById('separator2')
  local separator3 = countdownWindow:recursiveGetChildById('separator3')
  local worldName = countdownWindow:recursiveGetChildById('worldName')
  local infoCountLabel = countdownWindow:recursiveGetChildById('infoCountLabel')
  local pvpType = countdownWindow:recursiveGetChildById('pvpType')

  if not separator1 or not separator2 or not separator3 or not worldName or not infoCountLabel or not pvpType then
    return
  end

  separator1:setImageShader('text_green')
  separator2:setImageShader('text_green')
  separator3:setImageShader('text_green')
  infoCountLabel:setImageShader('text_green')
  worldName:setImageShader('text_staff')

  local remaining = countdownEndTime - os.time()
  if remaining <= 0 then
    for i = 1, 8 do
      local digitWidget = countdownWindow:recursiveGetChildById('digit' .. i)
      if digitWidget then
        digitWidget:setVisible(false)
      end
    end

    separator1:setVisible(false)
    separator2:setVisible(false)
    separator3:setVisible(false)
    pvpType:setVisible(true)
    infoCountLabel:setMarginTop(10)
    infoCountLabel:setText('Server is now open!')
    return
  end

  local days = math.floor(remaining / 86400)
  local hours = math.floor((remaining % 86400) / 3600)
  local minutes = math.floor((remaining % 3600) / 60)
  local seconds = remaining % 60
  local timeStr = string.format('%02d%02d%02d%02d', days, hours, minutes, seconds)

  for i = 1, 8 do
    local digitWidget = countdownWindow:recursiveGetChildById('digit' .. i)
    if digitWidget then
      local digit = string.sub(timeStr, i, i)
      digitWidget:setImageSource('/images/ui/numbers/number-' .. digit)
      digitWidget:setImageShader('text_green')
      digitWidget:setVisible(true)
    end
  end

  pvpType:setVisible(false)
  infoCountLabel:setMarginTop(2)
  countdownUpdateEvent = scheduleEvent(countdownTick, 1000)
end
