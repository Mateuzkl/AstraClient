unjustifiedPointsWindow = nil
unjustifiedPointsButton = nil
contentsPanel = nil

openPvpSituationsLabel = nil
currentSkullWidget = nil
skullTimeLabel = nil

dayProgressBar = nil
weekProgressBar = nil
monthProgressBar = nil

daySkullWidget = nil
weekSkullWidget = nil
monthSkullWidget = nil

local OPCODE_UNJUSTIFIED_REQUEST = 0x2E
local OPCODE_UNJUSTIFIED_SEND = 0x2F
local ACTION_REFRESH = 1

local function registerProtocol()
  ProtocolGame.unregisterOpcode(OPCODE_UNJUSTIFIED_SEND)
  ProtocolGame.registerOpcode(OPCODE_UNJUSTIFIED_SEND, function(protocol, msg)
    local unjustifiedPoints = {
      killsDay = msg:getU8(),
      killsDayRemaining = msg:getU8(),
      killsWeek = msg:getU8(),
      killsWeekRemaining = msg:getU8(),
      killsMonth = msg:getU8(),
      killsMonthRemaining = msg:getU8(),
      skullTimeSeconds = msg:getU32()
    }
    local openPvpSituations = msg:getU8()
    local skull = msg:getU8()

    onUnjustifiedPointsChange(unjustifiedPoints)
    onOpenPvpSituationsChange(openPvpSituations)

    local localPlayer = g_game.getLocalPlayer()
    if localPlayer then
      onSkullChange(localPlayer, skull)
    end
  end)
end

function init()
  connect(g_game, { onGameStart = online,
                    onUnjustifiedPointsChange = onUnjustifiedPointsChange,
                    onOpenPvpSituationsChange = onOpenPvpSituationsChange })
  connect(LocalPlayer, { onSkullChange = onSkullChange } )

  unjustifiedPointsButton = modules.client_topmenu.addRightGameToggleButton('unjustifiedPointsButton',
    tr('Unjustified Points'), '/images/icons/icon-unjustified-points-widget', toggle)
  unjustifiedPointsWindow = g_ui.loadUI('unjustifiedpoints', m_interface.getRightPanel())
  unjustifiedPointsWindow:disableResize()
  unjustifiedPointsWindow:setup()
  unjustifiedPointsWindow:hide()
  unjustifiedPointsWindow:setOn(false)

  contentsPanel = unjustifiedPointsWindow:getChildById('contentsPanel')

  openPvpSituationsLabel = contentsPanel:getChildById('openPvpSituationsLabel')
  currentSkullWidget = contentsPanel:getChildById('currentSkullWidget')
  skullTimeLabel = contentsPanel:getChildById('skullTimeLabel')

  dayProgressBar = contentsPanel:getChildById('dayProgressBar')
  weekProgressBar = contentsPanel:getChildById('weekProgressBar')
  monthProgressBar = contentsPanel:getChildById('monthProgressBar')
  daySkullWidget = contentsPanel:getChildById('daySkullWidget')
  weekSkullWidget = contentsPanel:getChildById('weekSkullWidget')
  monthSkullWidget = contentsPanel:getChildById('monthSkullWidget')

  if g_game.isOnline() then
    online()
  end
end

function terminate()
  disconnect(g_game, { onGameStart = online,
                       onUnjustifiedPointsChange = onUnjustifiedPointsChange,
                       onOpenPvpSituationsChange = onOpenPvpSituationsChange })
  disconnect(LocalPlayer, { onSkullChange = onSkullChange } )

  unjustifiedPointsWindow:destroy()
  unjustifiedPointsButton:destroy()
  ProtocolGame.unregisterOpcode(OPCODE_UNJUSTIFIED_SEND)
end

function onMiniWindowClose()
  unjustifiedPointsButton:setOn(false)
  modules.game_sidebuttons.setButtonVisible("unjustifiedPoinsWidget", false)
end

function toggle()
  if unjustifiedPointsButton:isOn() then
    unjustifiedPointsWindow:close()
    unjustifiedPointsButton:setOn(false)
  else
    unjustifiedPointsWindow:open()
    if m_interface.addToPanels(unjustifiedPointsWindow) then
      unjustifiedPointsButton:setOn(true)
      unjustifiedPointsWindow:getParent():moveChildToIndex(unjustifiedPointsWindow, #unjustifiedPointsWindow:getParent():getChildren())
    end
  end
end

function online()
  registerProtocol()
  local benchmark = g_clock.millis()
  refresh()
  requestRefresh()
  consoleln("Unjustified Points loaded in " .. (g_clock.millis() - benchmark) / 1000 .. " seconds.")
end

function requestRefresh()
  local protocolGame = g_game.getProtocolGame()
  if not protocolGame then
    return
  end

  local msg = OutputMessage.create()
  msg:addU8(OPCODE_UNJUSTIFIED_REQUEST)
  msg:addU8(ACTION_REFRESH)
  protocolGame:send(msg)
end

function refresh()
  local localPlayer = g_game.getLocalPlayer()

  local unjustifiedPoints = g_game.getUnjustifiedPoints()
  onUnjustifiedPointsChange(unjustifiedPoints)

  onSkullChange(localPlayer, localPlayer:getSkull())
  onOpenPvpSituationsChange(g_game.getOpenPvpSituations())
end

function onSkullChange(localPlayer, skull)
  if not localPlayer:isLocalPlayer() then return end

  if skull == SkullRed or skull == SkullBlack then
    currentSkullWidget:setIcon(getSkullImagePath(skull))
    currentSkullWidget:setTooltip('Remaining skull time')
  else
    currentSkullWidget:setIcon('')
    currentSkullWidget:setTooltip('You currently have no red or black skull.')
  end

  daySkullWidget:setIcon(getSkullImagePath(getNextSkullId(skull)))
  weekSkullWidget:setIcon(getSkullImagePath(getNextSkullId(skull)))
  monthSkullWidget:setIcon(getSkullImagePath(getNextSkullId(skull)))
end

function onOpenPvpSituationsChange(amount)
  openPvpSituationsLabel:setText(amount)
end

local function getColorByKills(kills)
  local imageSource = ''
  if kills < 2 then
    imageSource = '/game_cyclopedia/images/ui/mosnter-bar'
  elseif kills < 3 then
    imageSource = '/game_cyclopedia/images/ui/mosnter-bar'
  end
  return 'alpha'
end

function onUnjustifiedPointsChange(unjustifiedPoints)
	if unjustifiedPoints.skullTimeSeconds == 0 then
    skullTimeLabel:setTooltip('You currently have no red or black skull.')
  else
    skullTimeLabel:setTooltip('Remaining skull time')
  end

  dayProgressBar:setValue(unjustifiedPoints.killsDay, 0, 100)
  dayProgressBar:setBackgroundColor(getColorByKills(unjustifiedPoints.killsDayRemaining))
  dayProgressBar:setTooltip(string.format('UPs gained in 24 h.\n%i kill%s left.', unjustifiedPoints.killsDayRemaining, (unjustifiedPoints.killsDayRemaining == 1 and '' or 's')))

  weekProgressBar:setValue(unjustifiedPoints.killsWeek, 0, 100)
  weekProgressBar:setBackgroundColor(getColorByKills(unjustifiedPoints.killsWeekRemaining))
  weekProgressBar:setTooltip(string.format('UPs gained in 7 days.\n%i kill%s left.', unjustifiedPoints.killsWeekRemaining, (unjustifiedPoints.killsWeekRemaining == 1 and '' or 's')))

  monthProgressBar:setValue(unjustifiedPoints.killsMonth, 0, 100)
  monthProgressBar:setBackgroundColor(getColorByKills(unjustifiedPoints.killsMonthRemaining))
  monthProgressBar:setTooltip(string.format('UPs gained in 30 days.\n%i kill%s left.', unjustifiedPoints.killsMonthRemaining, (unjustifiedPoints.killsMonthRemaining == 1 and '' or 's')))
end

function move(panel, height, index, minimized)
  unjustifiedPointsWindow:setParent(panel)
  unjustifiedPointsWindow:open()

  if minimized then
    unjustifiedPointsWindow:setHeight(74)
    unjustifiedPointsWindow:minimize()
  else
    unjustifiedPointsWindow:maximize()
    unjustifiedPointsWindow:setHeight(74)
  end

  return unjustifiedPointsWindow
end
