interfaceSaved = false
gameRootPanel = nil
gameMapPanel = nil
gameRightPanels = nil
gameLeftPanels = nil
gameBottomPanel = nil
horizontalRightPanel = nil
horizontalLeftPanel = nil

local function isClassicViewActive()
  return g_settings.getBoolean("classicView") and not g_gameConfig.isExtendedViewUI()
end

local function getExtendedMaxZoomOut()
  if not gameRootPanel or gameRootPanel:getWidth() <= 0 or gameRootPanel:getHeight() <= 0 then
    return 11
  end

  local awareRange = g_map.getAwareRange()
  local aspectRatio = gameRootPanel:getWidth() / gameRootPanel:getHeight()
  local maxZoom = math.floor(awareRange.height)
  if maxZoom % 2 == 0 then
    maxZoom = maxZoom - 1
  end

  -- UIMap rounds both dimensions to odd values. Find the furthest zoom that
  -- still fits completely inside the map area sent by the server.
  while maxZoom > 3 do
    local visibleWidth = math.floor(maxZoom * aspectRatio)
    if visibleWidth % 2 == 0 then
      visibleWidth = visibleWidth + 1
    end
    if visibleWidth <= awareRange.width then
      return maxZoom
    end
    maxZoom = maxZoom - 2
  end
  return 3
end

local panelArrowIds = {
  'addRightPanelButton',
  'removeRightPanelButton',
  'addLeftPanelButton',
  'removeLeftPanelButton'
}

local function isMinimapExpansionReservation(panel)
  return panel and panel.minimapExpansionReservation == true
end

-- The reservation stands in for the space the expanded minimap covers, so it has to stay
-- on the edge the minimap grows towards. Inserting a real panel displaces it from there.
local function keepMinimapExpansionReservationAtEdge(container, side)
  if not container then
    return
  end

  for _, panel in ipairs(container:getChildren()) do
    if isMinimapExpansionReservation(panel) then
      local target = side == 'left' and container:getChildCount() or 1
      if container:getChildIndex(panel) ~= target then
        container:moveChildToIndex(panel, target)
      end
      return
    end
  end
end

local function getPersistentSidePanels(container)
  local panels = {}
  if not container then
    return panels
  end

  for _, panel in ipairs(container:getChildren()) do
    if not isMinimapExpansionReservation(panel) then
      panels[#panels + 1] = panel
    end
  end
  return panels
end

local function getPersistentSidePanel(container, index)
  local panels = getPersistentSidePanels(container)
  if index < 0 then
    index = #panels + index + 1
  end
  return panels[index]
end

local function getPersistentSidePanelCount(container)
  return #getPersistentSidePanels(container)
end

local function getSidePanelsWidth(container)
  local width = 0
  if not container then
    return width
  end

  for _, panel in ipairs(container:getChildren()) do
    if panel:isVisible() then
      width = width + panel:getWidth()
    end
  end
  return width
end

local function updatePanelArrowVisibility()
  if not gameRootPanel then return end

  local visible = not g_gameConfig.isExtendedViewUI()
  for _, id in ipairs(panelArrowIds) do
    local button = gameRootPanel:getChildById(id)
    if button then
      button:setVisible(visible)
    end
  end
end

gameBottomActionPanel = nil
gameBottomCooldownPanel = nil
gameLeftActionPanel = nil
gameRightActionPanel = nil
gameLeftActions = nil
gameTopBar = nil
logoutButton = nil
mouseGrabberWidget = nil
countWindow = nil
logoutWindow = nil
exitWindow = nil
bottomSplitter = nil
gameBottomLockPanel = nil
gameRightLockPanel = nil
gameLeftLockPanel = nil
backgroundPanel = nil
limitedZoom = false
arcDistance = 1
arcLifeDistance = 0
focusReason = {}
hookedMenuOptions = {}
lastDirTime = g_clock.millis()
local healthCircleResizeEvent = nil
local lockedTargetId = 0
local miniBotPanel = nil
local miniBotPresetPanel = nil
local miniBotTimerPanel = nil
local miniBotTimerEvent = nil
local miniBotTimerEnabled = false

local keybindStopAll = KeyBind:getKeyBind("Movement", "Stop All Actions")
local keybindLogout = KeyBind:getKeyBind("Misc.", "Logout")
local keybindClearOldMessage = KeyBind:getKeyBind("Misc.", "Clear oldest message from Game Window")

local widgetItem
local lastAction = 0
local npcTalkMaxDistance = 3
local ITEM_DECORATION_KIT = 23398
-- 8.6 dat does not flag Store decoration-kit outputs as wrapable.
local ITEM_DECORATION_KIT_WRAPABLE_RANGES = {
  {12699, 12699},
  {22736, 22737},
  {23399, 23411},
  {23414, 23414},
  {23417, 23445},
  {23448, 23455},
  {23536, 23537},
  {23691, 23691},
  {23693, 23720},
  {23722, 23725},
  {24416, 24435},
  {25103, 25104},
  {25174, 25175},
  {25182, 25183},
  {25200, 25200},
  {25210, 25233},
  {25720, 25723},
  {25879, 25883},
  {25889, 25893},
  {25899, 25900},
  {25903, 25914},
  {26075, 26078},
  {26081, 26084},
  {26088, 26099},
  {26101, 26123},
  {26150, 26167},
  {26170, 26174},
  {27661, 27671},
  {27673, 27675},
  {27679, 27689},
  {27691, 27700},
  {27702, 27703},
  {28525, 28525},
  {28559, 28564},
  {28671, 28671},
  {28674, 28690},
  {28694, 28694},
  {28696, 28699},
  {28912, 28914},
  {28919, 28948},
  {30227, 30230},
  {30232, 30249},
  {31183, 31197},
  {31207, 31214},
  {31217, 31226},
  {31382, 31382},
  {31462, 31462},
  {31464, 31464},
  {31466, 31469},
  {31679, 31684},
  {31687, 31698},
  {31703, 31706},
  {31931, 31951},
  {31955, 31956},
  {32123, 32123},
  {32128, 32166},
  {32473, 32536},
  {32541, 32566},
  {32751, 32756},
  {32775, 32793},
  {32795, 32801},
  {32907, 32912},
  {32918, 32918},
  {32943, 32974},
  {32979, 32979},
  {33026, 33049},
  {34027, 34071},
  {34269, 34276},
  {34278, 34278},
  {34280, 34280},
  {34282, 34282},
  {34284, 34305},
  {34309, 34309},
  {34312, 34325},
  {34332, 34332},
  {35153, 35193},
  {35203, 35209},
  {35582, 35582},
  {35584, 35586},
  {35851, 35900},
  {35911, 35939},
  {35941, 35944},
  {35949, 35949},
  {35954, 35964},
  {35969, 35969},
  {35973, 35974},
  {36617, 36654},
  {36748, 36754},
  {36756, 36756},
  {36833, 36833},
  {36865, 36869},
  {36995, 36995},
  {37004, 37034},
  {37165, 37165},
  {37174, 37212},
  {37519, 37520},
  {37700, 37700},
  {37746, 37746},
  {37763, 37816},
  {38640, 38640},
  {38707, 38707},
  {39419, 39447},
  {39496, 39502},
  {39504, 39510},
  {39517, 39526},
  {39668, 39668},
  {39767, 39810},
  {42267, 42308},
  {42320, 42368},
  {50435, 50436},
  {51186, 51186},
  {51188, 51190},
  {51196, 51199},
  {51204, 51223},
  {51237, 51237},
}

local function isDecorationKitWrapable(thing)
  if not thing or not thing:isItem() then
    return false
  end

  local thingId = thing:getId()
  for _, range in ipairs(ITEM_DECORATION_KIT_WRAPABLE_RANGES) do
    if thingId >= range[1] and thingId <= range[2] then
      return true
    end
  end

  return false
end

local function getTopDecorationKitWrapableThing(tile)
  if not tile or type(tile.getThings) ~= 'function' then
    return nil
  end

  local things = tile:getThings()
  for i = #things, 1, -1 do
    if isDecorationKitWrapable(things[i]) then
      return things[i]
    end
  end

  return nil
end

local function isDecorationKitThing(thing)
  return thing and thing:isItem() and thing:getId() == ITEM_DECORATION_KIT
end

local function showDecorationKitMenu(tile, menuPosition, lookThing, useThing, creatureThing)
  if not isDecorationKitThing(useThing) then
    return false
  end

  createThingMenu(tile, menuPosition, lookThing, useThing, creatureThing)
  return true
end

function canTalkToNpc(creature)
  if not creature or not creature:isNpc() then
    return false
  end

  local player = g_game.getLocalPlayer()
  if not player then
    return false
  end

  local playerPos = player:getPosition()
  local npcPos = creature:getPosition()
  if not playerPos or not npcPos or playerPos.z ~= npcPos.z then
    return false
  end

  return math.max(math.abs(playerPos.x - npcPos.x), math.abs(playerPos.y - npcPos.y)) <= npcTalkMaxDistance
end

function talkToNpc(creature)
  if not canTalkToNpc(creature) then
    return false
  end

  g_game.talk("hi")
  return true
end

function clearLockedTarget()
  lockedTargetId = 0
end

function getLockedTargetId()
  return lockedTargetId
end

function setLockedTarget(target)
  if not g_game.isOnline() then
    clearLockedTarget()
    return false
  end

  local targetId = nil
  if type(target) == 'number' then
    targetId = target
  elseif target then
    local ok, result = pcall(function() return target:getId() end)
    if ok then
      targetId = result
    end
  end

  targetId = tonumber(targetId)
  if not targetId or targetId <= 0 then
    clearLockedTarget()
    return false
  end

  lockedTargetId = math.floor(targetId)
  return true
end

function attackCreature(creature)
  if not setLockedTarget(creature) then
    return false
  end

  g_game.attack(creature)
  return true
end

local function stopMiniBotTimerEvent()
  if miniBotTimerEvent then
    removeEvent(miniBotTimerEvent)
    miniBotTimerEvent = nil
  end
end

local function updateMiniBotTimer()
  miniBotTimerEvent = nil
  if not miniBotTimerEnabled or not miniBotTimerPanel or miniBotTimerPanel:isDestroyed() then
    return
  end

  local text = tr('Cavebot timer unavailable')
  local player = g_game.isOnline() and g_game.getLocalPlayer() or nil
  if player and type(player.getCaveBotTimeLeft) == 'function' then
    local ok, timeLeft = pcall(function() return player:getCaveBotTimeLeft() end)
    timeLeft = ok and tonumber(timeLeft) or nil
    if timeLeft then
      timeLeft = math.max(0, math.floor(timeLeft))
      local hours = math.floor(timeLeft / 3600)
      local minutes = math.floor((timeLeft % 3600) / 60)
      local seconds = timeLeft % 60
      text = string.format('%s: %d:%02d:%02d', tr('Cavebot'), hours, minutes, seconds)
    end
  elseif not g_game.isOnline() then
    text = tr('Cavebot: offline')
  end

  miniBotTimerPanel:setText(text)
  miniBotTimerPanel:show()
  miniBotTimerEvent = scheduleEvent(updateMiniBotTimer, 1000)
end

local function ensureMiniBotPanels()
  if not gameRootPanel or gameRootPanel:isDestroyed() or
     not gameMapPanel or gameMapPanel:isDestroyed() then
    return false
  end

  if miniBotPanel and not miniBotPanel:isDestroyed() and miniBotPanel:getParent() ~= gameMapPanel then
    miniBotPanel:setParent(gameMapPanel)
  end

  if not miniBotPanel or miniBotPanel:isDestroyed() then
    miniBotPanel = g_ui.createWidget('Panel', gameMapPanel)
    miniBotPanel:setId('miniBotPanel')
    miniBotPanel:setFocusable(false)
    local layout = UIVerticalLayout.create(miniBotPanel)
    layout:setFitChildren(true)
    layout:setSpacing(1)
    miniBotPanel:setLayout(layout)
    miniBotPanel:hide()
  end

  -- Reparenting removes the widget's old anchor-layout entries. Reapply these
  -- anchors even for an existing panel so a live session self-corrects instead
  -- of keeping the absolute rectangle it had under gameRootPanel.
  miniBotPanel:breakAnchors()
  miniBotPanel:setWidth(22)
  miniBotPanel:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  miniBotPanel:addAnchor(AnchorRight, 'parent', AnchorRight)
  miniBotPanel:setMarginRight(8)

  if not miniBotPresetPanel or miniBotPresetPanel:isDestroyed() then
    miniBotPresetPanel = g_ui.createWidget('Label', gameMapPanel)
    miniBotPresetPanel:setId('miniBotPresetPanel')
    miniBotPresetPanel:setFocusable(false)
    miniBotPresetPanel:setPhantom(true)
    miniBotPresetPanel:setTextAutoResize(true)
    miniBotPresetPanel:setTextAlign(AlignCenter)
    miniBotPresetPanel:setColor('#f0f0f0')
    miniBotPresetPanel:addAnchor(AnchorTop, 'parent', AnchorTop)
    miniBotPresetPanel:addAnchor(AnchorHorizontalCenter, 'parent', AnchorHorizontalCenter)
    miniBotPresetPanel:setMarginTop(8)
    miniBotPresetPanel:hide()
  end

  if not miniBotTimerPanel or miniBotTimerPanel:isDestroyed() then
    miniBotTimerPanel = g_ui.createWidget('Label', gameMapPanel)
    miniBotTimerPanel:setId('miniBotTimerPanel')
    miniBotTimerPanel:setFocusable(false)
    miniBotTimerPanel:setPhantom(true)
    miniBotTimerPanel:setTextAutoResize(true)
    miniBotTimerPanel:setTextAlign(AlignRight)
    miniBotTimerPanel:setColor('#f0f0f0')
    miniBotTimerPanel:addAnchor(AnchorTop, 'parent', AnchorTop)
    miniBotTimerPanel:addAnchor(AnchorRight, 'parent', AnchorRight)
    miniBotTimerPanel:setMarginTop(8)
    miniBotTimerPanel:setMarginRight(8)
    miniBotTimerPanel:hide()
  end

  return true
end

function getMiniBotPanel()
  return ensureMiniBotPanels() and miniBotPanel or nil
end

function getMiniBotPresetPanel()
  return ensureMiniBotPanels() and miniBotPresetPanel or nil
end

function getMiniBotTimerPanel()
  return ensureMiniBotPanels() and miniBotTimerPanel or nil
end

function setMiniBotTimerPanelStatus(enabled)
  miniBotTimerEnabled = enabled == true
  stopMiniBotTimerEvent()
  if not miniBotTimerEnabled then
    if miniBotTimerPanel and not miniBotTimerPanel:isDestroyed() then
      miniBotTimerPanel:hide()
      miniBotTimerPanel:clearText()
    end
    return
  end

  if ensureMiniBotPanels() then
    updateMiniBotTimer()
  end
end

function resetMiniBotPanels()
  miniBotTimerEnabled = false
  stopMiniBotTimerEvent()

  if miniBotPanel and not miniBotPanel:isDestroyed() then
    miniBotPanel:destroyChildren()
    miniBotPanel:hide()
  end
  if miniBotPresetPanel and not miniBotPresetPanel:isDestroyed() then
    miniBotPresetPanel:clearText()
    miniBotPresetPanel:hide()
  end
  if miniBotTimerPanel and not miniBotTimerPanel:isDestroyed() then
    miniBotTimerPanel:clearText()
    miniBotTimerPanel:hide()
  end
end

function init()
  g_ui.importStyle('styles/countwindow')

  connect(g_game, {
    onGameStart = onGameStart,
    onGameEnd = onGameEnd,
    onLoginAdvice = onLoginAdvice,
  }, true)

  -- Call load AFTER game window has been created and
  -- resized to a stable state, otherwise the saved
  -- settings can get overridden by false onGeometryChange
  -- events
  connect(g_app, {
    onRun = load,
    onExit = save
  })

  connect(Creature, {
    onHealthPercentChange = creatureHealthPercentChange,
  })

  gameRootPanel = g_ui.displayUI('gameinterface')
  gameRootPanel:hide()
  gameRootPanel:lower()
  gameRootPanel:insertLuaCall("onGeometryChange")
  gameRootPanel.onGeometryChange = updateStretchShrink

  mouseGrabberWidget = gameRootPanel:getChildById('mouseGrabber')
  mouseGrabberWidget.onMouseRelease = onMouseGrabberRelease
  mouseGrabberWidget.onTouchRelease = mouseGrabberWidget.onMouseRelease

  bottomSplitter = gameRootPanel:getChildById('bottomSplitter')
  gameMapPanel = gameRootPanel:getChildById('gameMapPanel')
  ensureMiniBotPanels()
  gameRightPanels = gameRootPanel:getChildById('gameRightPanels')
  gameLeftPanels = gameRootPanel:getChildById('gameLeftPanels')
  gameBottomPanel = gameRootPanel:getChildById('gameBottomPanel')
  gameBottomActionPanel = gameRootPanel:getChildById('gameBottomActionPanel')
  gameBottomCooldownPanel = gameRootPanel:getChildById('gameBottomCooldownPanel')
  gameRightActionPanel = gameRootPanel:getChildById('gameRightActionPanel')
  gameLeftActionPanel = gameRootPanel:getChildById('gameLeftActionPanel')

  gameBottomLockPanel = gameRootPanel:recursiveGetChildById('bottomLock')
  gameRightLockPanel = gameRootPanel:recursiveGetChildById('rightLock')
  gameLeftLockPanel = gameRootPanel:recursiveGetChildById('leftLock')

  gameTopBar = gameRootPanel:getChildById('gameTopBar')
  gameLeftBar = gameRootPanel:getChildById('gameLeftTopBar')
  gameRightBar = gameRootPanel:getChildById('gameRightTopBar')

  gameLeftActions = gameRootPanel:getChildById('gameLeftActions')

  horizontalRightPanel = gameRootPanel:getChildById('horizontalRightPanel')
  horizontalLeftPanel = gameRootPanel:getChildById('horizontalLeftPanel')
  updatePanelArrowVisibility()
  connect(gameLeftPanel, { onVisibilityChange = onLeftPanelVisibilityChange })

  logoutButton = modules.client_topmenu.addLeftButton('logoutButton', tr('Exit'), '/images/topbuttons/logout', tryLogout, true)

  local firstWidget = g_ui.createWidget('GameSidePanel')
  firstWidget:setId("panel1")
  gameRightPanels:addChild(firstWidget)

  gameMapPanel.onClick = toggleInternalFocus
  gameRightPanels.onClick = toggleInternalFocus
  gameLeftPanels.onClick = toggleInternalFocus
  gameBottomPanel.onClick = toggleInternalFocus

  gameMapPanel:insertLuaCall("onGeometryChange")
  setupLeftActions()
  refreshViewMode()
  applyMouseCursorOptions()

  lastAction = 0
  bindKeys()

  connect(gameMapPanel, { onGeometryChange = updateSize, onVisibleDimensionChange = updateSize })
  connect(g_game, { onMapChangeAwareRange = updateSize })

  if g_game.isOnline() then
    show()
  end
end

function cancelAll()
  if not gameMapPanel:isEnabled() then
    return
  end
    if lastAction + 50 > g_clock.millis() then return end
    lastAction = g_clock.millis()
    clearLockedTarget()
    g_game.cancelAttackAndFollow()
end

function bindKeys()
  keybindStopAll:active(gameRootPanel)
  keybindLogout:active(gameRootPanel)
  keybindClearOldMessage:active(gameRootPanel)
  g_keyboard.bindKeyPress('Ctrl+=', function() gameMapPanel:zoomIn() end, gameRootPanel)
  g_keyboard.bindKeyPress('Ctrl+-', function() gameMapPanel:zoomOut() end, gameRootPanel)
  g_keyboard.bindKeyDown('Ctrl+W', function() g_map.cleanTexts() modules.game_textmessage.clearMessages() end, gameRootPanel)
end

function terminate()
  hookedMenuOptions = {}
  markThing = nil
  cancelMouseTargetSelection(false)
  resetMiniBotPanels()
  clearLockedTarget()

  if healthCircleResizeEvent then
    removeEvent(healthCircleResizeEvent)
    healthCircleResizeEvent = nil
  end

  disconnect(g_game, {
    onGameStart = onGameStart,
    onGameEnd = onGameEnd,
    onLoginAdvice = onLoginAdvice
  }, true)

  disconnect(g_app, {
    onRun = load,
    onExit = save
  })

  disconnect(Creature, {
    onHealthPercentChange = creatureHealthPercentChange,
  })

  if gameLeftPanel then
    disconnect(gameLeftPanel, { onVisibilityChange = onLeftPanelVisibilityChange })
  end

  if gameMapPanel then
    disconnect(gameMapPanel, { onGeometryChange = updateSize, onVisibleDimensionChange = updateSize })
  end

  disconnect(g_game, { onMapChangeAwareRange = updateSize })

  if gameRootPanel then
    g_keyboard.unbindKeyDown('Ctrl+W', nil, gameRootPanel)
  end

  keybindStopAll:deactive()
  keybindLogout:deactive()
  keybindClearOldMessage:deactive()

  if logoutButton then
    logoutButton:destroy()
    logoutButton = nil
  end

  if gameRootPanel then
    gameRootPanel:destroy()
    gameRootPanel = nil
  end

  gameMapPanel = nil
  miniBotPanel = nil
  miniBotPresetPanel = nil
  miniBotTimerPanel = nil
  gameRightPanels = nil
  gameLeftPanels = nil
  gameBottomPanel = nil
  horizontalRightPanel = nil
  horizontalLeftPanel = nil
  gameBottomActionPanel = nil
  gameBottomCooldownPanel = nil
  gameLeftActionPanel = nil
  gameRightActionPanel = nil
  gameLeftActions = nil
  gameTopBar = nil
  mouseGrabberWidget = nil
  bottomSplitter = nil
end

function onMouseRelease(widget, pos, button)
  if not widgetItem then
    widgetItem = g_ui.createWidget('Item', rootWidget)
    widgetItem:setItemId(3031)
    widgetItem:setImageSource('')
    widgetItem:setVirtual(true)
    widgetItem:setPhantom(true)
    widgetItem:setFocusable(false)
  end

  widgetItem:setPosition(g_window.getMousePosition())
end

function applyMouseCursorOptions()
  if not gameMapPanel then
    return
  end

  local nativeCursor = m_settings.getOption('nativeMouseCursor') == true
  local animatedCursor = m_settings.getOption('mouseAnimatedCursor')
  if animatedCursor == nil then
    animatedCursor = true
  end

  g_mouse.setUseNativeCursor(nativeCursor)
  gameMapPanel:setCursorAnimations(animatedCursor and not nativeCursor)

  if nativeCursor then
    g_window.restoreMouseCursor()
  end
end

local function scheduleTopBarSettingsRefresh()
  for _, delay in ipairs({50, 250, 750, 1500, 3000}) do
    scheduleEvent(function()
      if modules.game_topbar and modules.game_topbar.reloadFromSettings then
        modules.game_topbar.reloadFromSettings()
      end
    end, delay)
  end
end

function onGameStart()
  local benchmark = g_clock.millis()
  refreshViewMode()
  applyMouseCursorOptions()
  show()

  local player = g_game.getLocalPlayer()
  if player then
    LoadedPlayer:setId(player:getId())
    LoadedPlayer:setName(player:getName())
    LoadedPlayer:setVocation(player:getVocation())

    scheduleTopBarSettingsRefresh()
  end

  -- open Astra has delay in auto walking
  local ok, err = pcall(function()
    if not g_game.isOfficialTibia() then
      g_game.enableFeature(GameForceFirstAutoWalkStep)
    else
      g_game.disableFeature(GameForceFirstAutoWalkStep)
    end
  end)
  if not ok then
    g_logger.warning("Unable to update first auto walk feature: " .. tostring(err))
  end

  interfaceSaved = false
  consoleln("Game Interface loaded in " .. (g_clock.millis() - benchmark) / 1000 .. " seconds.")
end

function onGameEnd()
  cancelMouseTargetSelection(false)
  clearLockedTarget()
  resetMiniBotPanels()
  hide()
  modules.client_topmenu.getTopMenu():setImageColor('white')
  onPlayerUnload()
  interfaceSaved = true
end

function show()
  connect(g_app, { onClose = tryExit })
  modules.client_background.hide()
  gameRootPanel:show()
  gameRootPanel:focus()
  gameMapPanel:followCreature(g_game.getLocalPlayer())

  updateStretchShrink()
  logoutButton:setTooltip(tr('Logout'))

  addEvent(function()
    if not isClassicViewActive() then
      gameMapPanel:setMaxZoomOut(getExtendedMaxZoomOut())
      gameMapPanel:setLimitVisibleRange(false)
    elseif not limitedZoom or g_game.isGM() then
      gameMapPanel:setMaxZoomOut(513)
      gameMapPanel:setLimitVisibleRange(false)
    else
      gameMapPanel:setMaxZoomOut(15)
      gameMapPanel:setLimitVisibleRange(true)

    end
  end)
end

function hide()
  disconnect(g_app, { onClose = tryExit })
  logoutButton:setTooltip(tr('Exit'))

  if logoutWindow then
    logoutWindow:destroy()
    logoutWindow = nil
  end
  if exitWindow then
    exitWindow:destroy()
    exitWindow = nil
  end
  if countWindow then
    countWindow.contentPanel:destroy()
    countWindow = nil
  end
  gameRootPanel:hide()
  gameMapPanel:setShader("")
  modules.client_background.show()
end

function save()
  local settings = {}
  settings.splitterMarginBottom = bottomSplitter:getMarginBottom()
  g_settings.setNode('game_interface', settings)

  -- call others functions
  onPlayerUnload()
end

function load()
  local settings = g_settings.getNode('game_interface')
  if settings then
    if settings.splitterMarginBottom then
      bottomSplitter:setMarginBottom(settings.splitterMarginBottom)
    end
  end
end

function onLoginAdvice(message)
  displayInfoBox(tr("For Your Information"), message)
end

function forceExit()
  g_game.cancelLogin()
  scheduleEvent(exit, 10)
  return true
end

function tryExit()
--[[  if not gameRootPanel:isFocused() then
    return true
  end--]]
  if exitWindow then
    return true
  end

  local exitFunc = function() g_client.setInputLockWidget(nil) scheduleEvent(onProcessExit, 10) end
  local logoutFunc = function() g_client.setInputLockWidget(nil) g_game.safeLogout() exitWindow:destroy() exitWindow = nil end
  local cancelFunc = function() g_client.setInputLockWidget(nil) exitWindow:destroy() exitWindow = nil end

  exitWindow = displayGeneralBox(tr('Exit'), tr("If you shut down the program, your character might stay in the game.\nClick on 'Logout' to ensure that you character leaves the game properly.\nClick on 'Exit' if you want to exit the program without logging out your character."),
  { { text=tr('Exit'), callback=exitFunc },
    { text=tr('Logout'), callback=logoutFunc },
    { text=tr('Cancel'), callback=cancelFunc },
  }, logoutFunc, cancelFunc)

  g_client.setInputLockWidget(exitWindow)

  g_keyboard.bindKeyPress("E", exitFunc, exitWindow)
  g_keyboard.bindKeyPress("C", cancelFunc, exitWindow)
  g_keyboard.bindKeyPress("L", logoutFunc, exitWindow)
  return true
end

function onProcessExit()
  if g_game.isOnline() then
    g_game.invokeOnLogout()
  end

  g_game.doThing(false)
  g_game.invokeOnGameEnd()
  g_game.doThing(true)
  exit()
end

function tryLogout(prompt)
  if type(prompt) ~= "boolean" then
    prompt = true
  end
  if not g_game.isOnline() then
    exit()
    return
  end

  if logoutWindow then
    return
  end

  local msg, yesCallback
  if not g_game.isConnectionOk() then
    msg = 'Your connection is failing, if you logout now your character will be still online, do you want to force logout?'

    yesCallback = function()
      g_game.forceLogout()
      if logoutWindow then
        logoutWindow:destroy()
        logoutWindow=nil
      end
    end
  else
    msg = 'Are you sure you want to leave Astra?'

    yesCallback = function()
      g_game.safeLogout()
      if logoutWindow then
        logoutWindow:destroy()
        logoutWindow=nil
      end
    end
  end

  local noCallback = function()
    logoutWindow:destroy()
    logoutWindow=nil
  end

  if prompt then
    logoutWindow = displayGeneralBox(tr('Warning'), tr(msg), {
      { text=tr('Yes'), callback=yesCallback },
      { text=tr('No'), callback=noCallback },
    }, yesCallback, noCallback)
  g_keyboard.bindKeyPress("Y", yesCallback, logoutWindow)
  g_keyboard.bindKeyPress("N", noCallback, logoutWindow)
  else
     yesCallback()
  end
end

function updateStretchShrink()
  if m_settings.getOption('dontStretchShrink') and not alternativeView then
    gameMapPanel:setVisibleDimension({ width = 15, height = 11 })
    -- Set gameMapPanel size to height = 11 * 32 + 2
    bottomSplitter:setMarginBottom(bottomSplitter:getMarginBottom() + (gameMapPanel:getHeight() - 32 * 11) - 10)
  end
end

function configureWidgetOnPanel(widget, panel)
  if isMinimapExpansionReservation(panel) then
    return false
  end

  local childsSize = 0
  for _, child in pairs(panel:getChildren()) do
    if child:isVisible() and widget:getId() ~= child:getId() then
      childsSize = child:getHeight() + childsSize
    end
  end

  local emptySize = panel:getHeight() - childsSize
  if emptySize - widget:getHeight() >= 0 then
    widget:setParent(panel)
    local oldOnClose = widget.onClose
    widget.onClose = function()
      if oldOnClose then oldOnClose() end
      local panel = widget:getParent()
      if panel then panel:removeChild(widget) end
    end
    return true
  end

  local minimus = widget:getMinimumHeight()
   if widget:getId():find("BattleWindow") then
    minimus = 104
  elseif widget:getId():find("minimapWindow") then
    minimus = 200
  end

  if emptySize - minimus >= 0 then
    widget:setParent(panel)
    local oldOnClose = widget.onClose
    widget.onClose = function()
      if oldOnClose then oldOnClose() end
      local panel = widget:getParent()
      if panel then panel:removeChild(widget) end
    end
    return true
  end

  return false
end

function recalculateWidgetOnPanel(widget, panel)
  if isMinimapExpansionReservation(panel) then
    return false
  end

  local childsSize = 0
  local backpacks = {}

  local childrenIds = {"skillWindow", "analyserMiniWindow"}
  for _, child in pairs(panel:getChildren()) do
    if child:isVisible() and widget:getId() ~= child:getId() then
      childsSize = child:getHeight() + childsSize
      if child:getId():find("container") or table.find(childrenIds, child:getId()) then
        backpacks[#backpacks+1] = child
      end
    end
  end

  local backpackSize = #backpacks
  if backpackSize == 0 then
    return false
  end
  local emptySize = panel:getHeight() - childsSize

  local backpackToRemove = {}
  local totalHeight = 0
  for _, backpack in pairs(backpacks) do
    local height = backpack:getHeight()
    if height + emptySize >= widget:getHeight() then
      backpack:close()
      widget:setParent(panel)
      widget.onClose = function()
        local panel = widget:getParent()
        if panel then
          panel:removeChild(widget)
        end
      end

      return true
    end

    if backpackSize > 1 then
      backpackToRemove[#backpackToRemove+1] = backpack
      totalHeight = totalHeight + height
    end

    if totalHeight + emptySize >= widget:getHeight() then
      break
    end
  end

  if totalHeight > 0 then
    for _, backpack in pairs(backpackToRemove) do
      backpack:close()
    end

    widget:setParent(panel)
    widget.onClose = function()
      local panel = widget:getParent()
      if panel then
        panel:removeChild(widget)
      end
    end

    return true
  end

  return false
end

function addToPanels(uiWidget)
  local right = getRightPanel()
  local left = getLeftPanel()
  uiWidget.onRemoveFromContainer = function(widget)
    if left:isOn() then
      if widget:getParent():getId() == 'gameRightPanel' then
        if left:getEmptySpaceHeight() - widget:getHeight() >= 0 then
          widget:setParent(left)
        end
      elseif widget:getParent():getId() == 'gameLeftPanel' then
        if right:getEmptySpaceHeight() - widget:getHeight() >= 0 then
          widget:setParent(right)
        end
      end
    end
  end

  local widgetName = uiWidget:getId()
  if string.find(widgetName, "widget") then
    uiWidget:setHeight(uiWidget:getMinimumHeight())
  end

  local count = gameRightPanels:getChildCount()
  local panels = {}

  for i = count, 1, -1 do
    local panel = gameRightPanels:getChildByIndex(i)
    if not isMinimapExpansionReservation(panel) then
      panels[#panels+1] = panel
    end
  end

  local count = gameLeftPanels:getChildCount()
  for i = 1, count do
    local panel = gameLeftPanels:getChildByIndex(i)
    if not isMinimapExpansionReservation(panel) then
      panels[#panels+1] = panel
    end
  end

  for _, panel in ipairs(panels) do
    if configureWidgetOnPanel(uiWidget, panel) then
      return true
    end
  end

  local childrenIds = {"tradeWindow",}
  if table.find(childrenIds, uiWidget:getId()) then
    uiWidget:setHeight(uiWidget:getMinimumHeight())
    for _, panel in ipairs(panels) do
      if recalculateWidgetOnPanel(uiWidget, panel) then
        return true
      end
    end
  end

  uiWidget:close()
  local analyserTypes = {'bossCooldowns', 'damageInputAnalyser', 'lootTracker','huntingSessionAnalyser', 'impactAnalyser', 'lootAnalyser', 'partyHuntAnalyser', 'wasteAnalyser', 'xpAnalyser', 'miscAnalyzer'}
  if not table.find(analyserTypes, uiWidget:getType()) then
    modules.game_textmessage.displayFailureMessage(tr('There is no available space.'))
  end
  return false
end

-- Enhanced version of addToPanels that can force space for priority widgets
function addToPanelsWithPriority(uiWidget, forcePriority)
  forcePriority = forcePriority or false
  
  -- Define priority widgets
  local priorityWidgets = {"inventoryWindow", "mainButtons"}
  
  -- Check if widget is priority
  local function isPriorityWidget(widget)
    local widgetType = widget:getId() or ""
    for _, priority in pairs(priorityWidgets) do
      if string.find(widgetType, priority) then
        return true
      end
    end
    return false
  end
  
  local isCurrentWidgetPriority = isPriorityWidget(uiWidget) or forcePriority

  local right = getRightPanel()
  local left = getLeftPanel()
  
  uiWidget.onRemoveFromContainer = function(widget)
    if left:isOn() then
      if widget:getParent():getId() == 'gameRightPanel' then
        if left:getEmptySpaceHeight() - widget:getHeight() >= 0 then
          widget:setParent(left)
        end
      elseif widget:getParent():getId() == 'gameLeftPanel' then
        if right:getEmptySpaceHeight() - widget:getHeight() >= 0 then
          widget:setParent(right)
        end
      end
    end
  end
  
  local widgetName = uiWidget:getId()
  if string.find(widgetName, "widget") then
    uiWidget:setHeight(uiWidget:getMinimumHeight())
  end

  local function forceWidgetOnPanel(widget, panel)
    if not widget or not panel then
      return false
    end

    widget:setParent(panel)
    local oldOnClose = widget.onClose
    widget.onClose = function()
      if oldOnClose then oldOnClose() end
      local parent = widget:getParent()
      if parent then parent:removeChild(widget) end
    end
    if panel.fitAll then
      panel:fitAll(widget)
    end
    return true
  end
  
  -- Build panels list in same order as original addToPanels
  local rightCount = gameRightPanels:getChildCount()
  local panels = {}
  for i = rightCount, 1, -1 do
    local panel = gameRightPanels:getChildByIndex(i)
    if not isMinimapExpansionReservation(panel) then
      panels[#panels+1] = {panel = panel, name = "right panel " .. (rightCount - i + 1), side = "right", index = i}
    end
  end
  
  local leftCount = gameLeftPanels:getChildCount()
  for i = 1, leftCount do
    local panel = gameLeftPanels:getChildByIndex(i)
    if not isMinimapExpansionReservation(panel) then
      panels[#panels+1] = {panel = panel, name = "left panel " .. i, side = "left", index = i}
    end
  end
  
  -- Function to force space in a specific panel for priority widgets
  local function forceSpaceInPanel(panel, requiredHeight)
    local emptySpace = panel:getEmptySpaceHeight() or 0  -- Fixed: added parentheses
 
    if emptySpace >= requiredHeight then
      return true
    end
    
    local spaceNeeded = requiredHeight - emptySpace
    local panelChildren = panel:getChildren()
    local removedWidgets = {}
    
    -- Remove non-priority widgets from the end until there's enough space
    local childrenToRemove = {}
    for i = #panelChildren, 1, -1 do
      local childWidget = panelChildren[i]
      if not isPriorityWidget(childWidget) then
        local childHeight = childWidget:getHeight()
  
        table.insert(childrenToRemove, childWidget)
        table.insert(removedWidgets, childWidget:getId() or "unknown")
        spaceNeeded = spaceNeeded - childHeight
        
        -- Check if we will have enough space after removing this widget
        if spaceNeeded <= 0 then
          break
        end
      end
    end
    
    -- Actually remove the widgets
    for _, widgetToRemove in ipairs(childrenToRemove) do
      widgetToRemove:close()
    end
    
    -- Check final space after removal
    local finalEmptySpace = panel:getEmptySpaceHeight() or 0  -- Fixed: added parentheses

    if finalEmptySpace >= requiredHeight then
      return true
    else
      return false
    end
  end
  
  -- Try each panel
  for _, panelInfo in ipairs(panels) do
    local panel = panelInfo.panel

    -- For priority widgets, check if we need to force space BEFORE trying normal add
    if isCurrentWidgetPriority then
      local emptySpace = panel:getEmptySpaceHeight() or 0  -- Fixed: added parentheses
      local requiredHeight = uiWidget:getHeight()

      if emptySpace < requiredHeight then
        if forceSpaceInPanel(panel, requiredHeight) then
          -- Try to configure after forcing space
          if configureWidgetOnPanel(uiWidget, panel) then
            return true
          else
            return forceWidgetOnPanel(uiWidget, panel)
          end
        end
      else
        -- Has enough space, try normal add
        if configureWidgetOnPanel(uiWidget, panel) then
          return true
        end
      end
    else
      -- Non-priority widget, try normal add only
      if configureWidgetOnPanel(uiWidget, panel) then
        return true
      end
    end
  end
  
  -- Handle special cases (same as original)
  local childrenIds = {"tradeWindow"}
  if table.find(childrenIds, uiWidget:getId()) then
    uiWidget:setHeight(uiWidget:getMinimumHeight())
    for _, panelInfo in ipairs(panels) do
      if recalculateWidgetOnPanel(uiWidget, panelInfo.panel) then
        return true
      end
    end
  end
  
  -- If we reach here, couldn't place the widget
  if isCurrentWidgetPriority then
    -- For priority widgets, force placement on first available panel as absolute last resort
    if #panels > 0 then
      local firstPanel = panels[1].panel
      return forceWidgetOnPanel(uiWidget, firstPanel)
    end
  else
    uiWidget:close()
    modules.game_textmessage.displayFailureMessage(tr('There is no available space.'))
  end
  
  return false
end

-- Generic function to remove panel (works for both left and right)
function removePanel(side)
  if side ~= "left" and side ~= "right" then
    return
  end
  
  -- Set width function based on side
  if side == "left" then
    setLeftHorizontalWidth()
  else
    setRightHorizontalWidth()
  end
  
  -- Get the appropriate panels container
  local panels = (side == "left") and gameLeftPanels or gameRightPanels
  local oppositePanels = (side == "left") and gameRightPanels or gameLeftPanels
  
  -- Different logic for left vs right panels
  local panel, targetPanel
  
  if side == "left" then
    -- Left panel logic: remove last panel, check if any panels exist
    if panels:getChildCount() == 0 then
      return
    end
    
    panel = panels:getChildByIndex(-1)

    if isMinimapExpansionReservation(panel) then
      local minimap = modules.game_minimap
      if minimap and minimap.isExpanded and minimap.isExpanded() and minimap.toggleExpanded then
        minimap.toggleExpanded()
      else
        -- Reservation with nothing expanding into it. Returning here would swallow the
        -- click and leave it wedged in the sidebar for good.
        releaseMinimapExpansionSpace(panel)
      end
      return
    end
    
    -- Determine target for left panel
    if getPersistentSidePanelCount(panels) >= 2 then
      targetPanel = getPersistentSidePanel(panels, -2)
    else
      if getPersistentSidePanelCount(oppositePanels) > 0 then
        targetPanel = getPersistentSidePanel(oppositePanels, 1)
      end
    end
  else
    -- Right panel logic: remove first panel, check if more than 1 panel exists
    if panels:getChildCount() == 0 then
      return
    end
    
    panel = panels:getChildByIndex(1)

    if isMinimapExpansionReservation(panel) then
      local minimap = modules.game_minimap
      if minimap and minimap.isExpanded and minimap.isExpanded() and minimap.toggleExpanded then
        minimap.toggleExpanded()
      else
        -- Reservation with nothing expanding into it. Returning here would swallow the
        -- click and leave it wedged in the sidebar for good.
        releaseMinimapExpansionSpace(panel)
      end
      return
    end

    if getPersistentSidePanelCount(panels) <= 1 then
      return
    end
    targetPanel = getPersistentSidePanel(panels, 2)
  end
  
  local moveWidgets = {}
  
  -- Define priority widgets
  local priorityWidgets = {"inventoryWindow", "mainButtons"}
  
  -- Check if widget is priority
  local function isPriorityWidget(widget)
    local widgetType = widget:getId() or ""
    for _, priority in pairs(priorityWidgets) do
      if string.find(widgetType, priority) then
        return true
      end
    end
    return false
  end
  
  -- Collect widgets from the panel to be removed
  for _, widget in pairs(panel:getChildren()) do
    table.insert(moveWidgets, widget)
  end
  
  -- Separate widgets by priority
  local highPriorityWidgets = {}
  local normalWidgets = {}
  
  for _, widget in pairs(moveWidgets) do
    if isPriorityWidget(widget) then
      table.insert(highPriorityWidgets, widget)
    else
      table.insert(normalWidgets, widget)
    end
  end
  
  -- Move the empty panel
  if targetPanel then
    panel:moveTo(targetPanel)
  end
  panels:removeChild(panel)
  
  -- Process high priority widgets first
  for _, widget in pairs(highPriorityWidgets) do
    addToPanelsWithPriority(widget, true)
  end
  
  -- Then process normal widgets
  for _, widget in pairs(normalWidgets) do
    addToPanelsWithPriority(widget, false)
  end
  
  -- Set width and save settings based on side
  if side == "left" then
    setLeftHorizontalWidth()
    g_settings.set("leftPanels", getPersistentSidePanelCount(gameLeftPanels))
  else
    setRightHorizontalWidth()
    g_settings.set("rightPanels", getPersistentSidePanelCount(gameRightPanels))
  end
  
  scheduleEvent(function() modules.game_actionbar.updateVisibleWidgets() end, 10)
end

function onMouseGrabberRelease(self, mousePosition, mouseButton)
  if mouseButton == MouseTouch then return end
  local thing = selectedThing
  local action = selectedType

  if thing and mouseButton == MouseLeftButton then
    local clickedWidget = gameRootPanel:recursiveGetChildByPos(mousePosition, false)
    if clickedWidget then
      if action == 'use' then
        onUseWith(clickedWidget, mousePosition)
      elseif action == 'trade' then
        onTradeWith(clickedWidget, mousePosition)
      end
    end
  end

  cancelMouseTargetSelection(true)
  return true
end

function cancelMouseTargetSelection(blockNextRelease)
  local hadSelection = selectedThing ~= nil
  selectedThing = nil
  selectedType = nil
  selectedSubtype = 0

  if mouseGrabberWidget then
    local releasedMouse = g_mouse.releaseGrabber(mouseGrabberWidget)
    if releasedMouse == 'target' then
      g_mouse.popCursor('target')
    end
    mouseGrabberWidget:ungrabMouse()
  end

  if blockNextRelease and gameMapPanel then
    gameMapPanel:blockNextMouseRelease(true)
  end

  return hadSelection
end

function isMouseTargetSelectionActive()
  return selectedThing ~= nil
end

function onUseWith(clickedWidget, mousePosition)
  if clickedWidget:getClassName() == 'UIGameMap' then
    local tile = clickedWidget:getTile(mousePosition)
    if tile then
      if selectedThing:isFluidContainer() or selectedThing:isMultiUse() then
        if selectedThing:getId() == 3180 or selectedThing:getId() == 3156 then
          -- special version for mwall
          g_game.useWith(selectedThing, tile:getTopUseThing(), selectedSubtype)
        else
          g_game.useWith(selectedThing, tile:getTopMultiUseThingEx(clickedWidget:getPositionOffset(mousePosition)), selectedSubtype)
        end
      else
        g_game.useWith(selectedThing, tile:getTopUseThing(), selectedSubtype)
      end
    end
  elseif clickedWidget:getClassName() == 'UIItem' and not clickedWidget:isVirtual() then
    g_game.useWith(selectedThing, clickedWidget:getItem(), selectedSubtype)
  elseif clickedWidget:getClassName() == 'UICreatureButton' or clickedWidget:getClassName() == 'UIRealCreatureButton' then
    local creature = clickedWidget:getCreature()
    if creature then
      g_game.useWith(selectedThing, creature, selectedSubtype)
    end
  end
end

function onTradeWith(clickedWidget, mousePosition)
  if clickedWidget:getClassName() == 'UIGameMap' then
    local tile = clickedWidget:getTile(mousePosition)
    if tile then
      g_game.requestTrade(selectedThing, tile:getTopCreatureEx(clickedWidget:getPositionOffset(mousePosition)))
    end
  elseif clickedWidget:getClassName() == 'UICreatureButton' then
    local creature = clickedWidget:getCreature()
    if creature then
      g_game.requestTrade(selectedThing, creature)
    end
  end
end

function startUseWith(thing, subType)
  gameMapPanel:blockNextMouseRelease()
  if not thing then return end
  if g_ui.isMouseGrabbed() then
    if selectedThing then
      selectedThing = thing
      selectedType = 'use'
      selectedSubtype = subType or 0
    end
    return
  end
  selectedType = 'use'
  selectedThing = thing
  selectedSubtype = subType or 0
  g_mouse.setGrabber(mouseGrabberWidget, 'target')
  mouseGrabberWidget:grabMouse()
  g_mouse.pushCursor('target')
end

function startTradeWith(thing)
  if not thing then return end
  if g_ui.isMouseGrabbed() then
    if selectedThing then
      selectedThing = thing
      selectedType = 'trade'
    end
    return
  end
  selectedType = 'trade'
  selectedThing = thing
  selectedSubtype = 0
  g_mouse.setGrabber(mouseGrabberWidget, 'target')
  mouseGrabberWidget:grabMouse()
  g_mouse.pushCursor('target')
end

function isMenuHookCategoryEmpty(category)
  if category then
    for _,opt in pairs(category) do
      if opt then return false end
    end
  end
  return true
end

function addMenuHook(category, name, callback, condition, shortcut)
  if not hookedMenuOptions[category] then
    hookedMenuOptions[category] = {}
  end
  hookedMenuOptions[category][name] = {
    callback = callback,
    condition = condition,
    shortcut = shortcut
  }
end

function removeMenuHook(category, name)
  if not name then
    hookedMenuOptions[category] = {}
  else
    hookedMenuOptions[category][name] = nil
  end
end

function createThingMenu(tile, menuPosition, lookThing, useThing, creatureThing)
  if not g_game.isOnline() then return end
  local menu = g_ui.createWidget('PopupMenu')
  menu:setGameMenu(true)

  local shortcut = nil

  if not g_app.isMobile() then shortcut = '(Shift)' else shortcut = nil end
  if lookThing then
    menu:addOption(tr('Look'), function() g_game.look(lookThing) end, shortcut)
  end

  if lookThing and not lookThing:isCreature() and not lookThing:isNotMoveable() and lookThing:isPickupable() then
    menu:addOption(tr('Inspect'), function() g_game.sendInspectionNormalObject(lookThing:getPosition()) end)
    menu:addOption(tr('Cyclopedia'), function() modules.game_cyclopedia.CyclopediaItems.onRedirect(lookThing:getId()) end)

    local hasProficiencyId = lookThing.getProficiencyId ~= nil
    local proficiencyId = 0
    if hasProficiencyId then
      local ok, id = pcall(function() return lookThing:getProficiencyId() end)
      if ok then
        proficiencyId = id
      end
    end

    if proficiencyId > 0 and modules.game_proficiency and type(modules.game_proficiency.isAvailable) == 'function' and modules.game_proficiency.isAvailable() then
      menu:addOption(tr('Weapon Proficiency'), function() modules.game_proficiency.requestOpenWindow(lookThing) end)
    end
  end

  if not g_app.isMobile() then shortcut = '(Alt)' else shortcut = nil end
  if useThing and not useThing:isStatic() then
    if not isDecorationKitThing(useThing) then
      if useThing:isContainer() then
        if useThing:getParentContainer() then
          menu:addOption(tr('Open'), function() g_game.open(useThing, useThing:getParentContainer()) end)
          menu:addOption(tr('Open in new window'), function() g_game.openContainer(useThing) end)
        else
          menu:addOption(tr('Open in new window'), function() g_game.openContainer(useThing) end)
        end
      else
        if useThing:isMultiUse() then
          menu:addOption(tr('Use with ...'), function() startUseWith(useThing) end)
        else
          if creatureThing and creatureThing:isNpc() then
            menu:addOption(tr('Use'), function() g_game.use(creatureThing) end)
          else
            menu:addOption(tr('Use'), function() g_game.use(useThing) end)
          end
        end
      end
    end

    if g_game.getFeature(GameQuickLootFlags) or g_game.getFeature(GameTibia12Protocol) then
      if useThing:isCorpse() and not useThing:isPlayerCorpse() then
        menu:addOption(tr('Loot Corpse'), function() g_game.quickLoot(useThing:getPosition(), useThing:getId(), useThing:getStackPos(), true) end)
      elseif useThing:inCorpse() then
        menu:addOption(tr('Loot'), function() g_game.quickLoot(useThing:getPosition(), useThing:getId(), useThing:getStackPos(), false) end)
      end
    end

    local wrapThing
    if useThing:isWrapable() or isDecorationKitWrapable(useThing) then
      wrapThing = useThing
    elseif tile then
      wrapThing = tile:getTopWrapableThing() or getTopDecorationKitWrapableThing(tile)
    end

    if wrapThing then
      menu:addOption(tr('Wrap'), function() g_game.wrap(wrapThing) end)
    end

    if useThing:isUnwrapable() or useThing:getId() == ITEM_DECORATION_KIT then
      menu:addOption(tr('Unwrap'), function() g_game.wrap(useThing) end)
    end
    local podiumIds = {RENOWN_PODIUM, LEGACY_RENOWN_PODIUM, VIGOUR_PODIUM, TENACITY_PODIUM, ASTRA_MONSTER_PODIUM}
    local isPodium = table.contains(podiumIds, useThing:getId())
    if useThing:isRotateable() or isPodium then
      menu:addOption(tr('Rotate'), function() g_game.rotate(useThing) end)
    end
    if isPodium then
      menu:addOption(tr('Customise Podium'),
        function()
          if useThing:getId() == VIGOUR_PODIUM or useThing:getId() == TENACITY_PODIUM or useThing:getId() == ASTRA_MONSTER_PODIUM then
            modules.game_monster_podium.requestMonsterData(useThing)
          elseif useThing:getId() == RENOWN_PODIUM or useThing:getId() == LEGACY_RENOWN_PODIUM then
            modules.game_player_podium.requestPodiumOutfitData(useThing)
          end
        end)
    end

    local rewards = {REWARD_CHEST, 63567, 62034, 62035, 62036, 62037, 62038, 62039, 62040, 62041, 63560}
    if table.contains(rewards, useThing:getId()) then
      menu:addOption(tr('Collect all'), function() g_game.requestCollectAll(useThing:getPosition(), useThing:getId(), useThing:getStackPos()) end)
    end

    if g_game.getFeature(GameBrowseField) and useThing and useThing:getPosition() and useThing:getPosition().x ~= 0xffff then
      menu:addOption(tr('Browse Field'), function() g_game.browseField(useThing:getPosition()) end)
      menu:addSeparator()
      menu:addOption(tr('Report Coordinate'), function() modules.game_bugreport.show(useThing:getPosition(), 0) end)
    end
  end

  local localPlayer = g_game.getLocalPlayer()
  if lookThing and not lookThing:isCreature() and not lookThing:isNotMoveable() and lookThing:isPickupable() and not useThing:isStatic() then
    menu:addSeparator()
    local parentContainer = lookThing:getParentContainer()
    if parentContainer and parentContainer:hasParent() then
      menu:addOption(tr('Move up'), function() g_game.moveToParentContainer(lookThing, lookThing:getCount()) end)
    end
    menu:addOption(tr('Trade with ...'), function() startTradeWith(lookThing) end)
    if lookThing:isMarketable() and localPlayer:isInMarket() then
      menu:addOption(tr('Show in Market'), function() modules.game_tibia_market.onRedirect(lookThing) end)
    end
  elseif useThing and not useThing:isCreature() and not useThing:isNotMoveable() and useThing:isPickupable() and not useThing:isStatic() then
    menu:addSeparator()
    menu:addOption(tr('Trade with ...'), function() startTradeWith(useThing) end)
    if useThing:isMarketable() and localPlayer:isInMarket() then
      menu:addOption(tr('Show in Market'), function() modules.game_tibia_market.onRedirect(useThing) end)
    end
  end

  if useThing and useThing:isContainer() and (useThing:getParentContainer() or useThing:getPosition().x == 65535) then
    menu:addSeparator()
    menu:addOption(tr('Manage Loot containers'), function() modules.game_quickloot.showQuickLoot() end)
  end

  if lookThing and not lookThing:isCreature() and not lookThing:isNotMoveable() and lookThing:isPickupable() and not useThing:isStatic() then
    if not useThing:isContainer() then
      menu:addSeparator()
    end
    if not modules.game_quickloot.inWhiteList(lookThing:getId()) then
      menu:addOption(tr('Add to Loot List'), function() modules.game_quickloot.addToQuickLoot(lookThing:getId()) end)
    else
      menu:addOption(tr('Remove from Loot List'), function() modules.game_quickloot.removeItemInList(lookThing:getId()) end)
    end
    if not modules.game_npctrade.inWhiteList(lookThing:getId()) then
      menu:addOption(tr('Add to Quick Sell BlackList'), function() modules.game_npctrade.addToWhitelist(lookThing:getId()) end)
    else
      menu:addOption(tr('Remove from Quick Sell BlackList'), function() modules.game_npctrade.removeItemInList(lookThing:getId()) end)
    end
  end

  if useThing and useThing:isContainer() and (useThing:getParentContainer() or useThing:getPosition().x == 65535) and useThing:getId() ~= 28750 and localPlayer:isInStash() then
    menu:addSeparator()
    menu:addOption(tr('Stow container\'s content'), function() if m_settings.getOption('stowContainer') then modules.game_stash.stowContainerContent(useThing, nil, false) else g_game.stowItemContainerStack(SUPPLY_STASH_ACTION_STOW_CONTAINER, useThing:getPosition(), useThing:getId(), useThing:getStackPos()) end end)
  end

  if useThing and useThing:isStowable() and (useThing:getParentContainer() or useThing:getPosition().x == 65535) and localPlayer:isInStash() then
    if not isGoldCoin(useThing:getId()) and useThing:isMarketable() then
      menu:addSeparator()
      menu:addOption(tr('Stow'), function() g_game.stowItem(useThing:getPosition(), useThing:getId(), useThing:getStackPos(), useThing:getCount()) end)
      menu:addOption(tr('Stow all items of this type'), function() g_game.stowItemContainerStack(SUPPLY_STASH_ACTION_STOW_STACK, useThing:getPosition(), useThing:getId(), useThing:getStackPos()) end)
    end
  end

  if creatureThing then
    local localPlayer = g_game.getLocalPlayer()
    menu:addSeparator()

    if creatureThing:isLocalPlayer() then
      menu:addOption(tr('Customise Character'), function() g_game.requestOutfit(0) end)

      if g_game.getFeature(GamePlayerMounts) then
        if not localPlayer:isMounted() then
          menu:addOption(tr('Mount'), function() localPlayer:mount() end)
        else
          menu:addOption(tr('Dismount'), function() localPlayer:dismount() end)
        end
      end

      if g_game.getFeature(GamePrey) and modules.game_prey then
        menu:addOption(tr('Open Prey Dialog'), function() modules.game_prey.show() end)
      end

      if creatureThing:isPartyMember() then
        if creatureThing:isPartyLeader() then
          if creatureThing:isPartySharedExperienceActive() then
            menu:addOption(tr('Disable Shared Experience'), function() g_game.partyShareExperience(false) end)
          else
            menu:addOption(tr('Enable Shared Experience'), function() g_game.partyShareExperience(true) end)
          end
        end
        menu:addOption(tr('Leave Party'), function() g_game.partyLeave() end)
      end

      menu:addOption(tr('Inspect %s Prestige', creatureThing:getName()), function() g_game.sendRequestPrestigeInspect(creatureThing:getName()) end)
      menu:addSeparator()
      menu:addOption(tr('Copy Name'), function() g_window.setClipboardText(creatureThing:getName()) end)

    else
      local localPosition = localPlayer:getPosition()
      if not g_app.isMobile() then shortcut = '(Alt)' else shortcut = nil end
      if creatureThing:getPosition().z == localPosition.z then
        if not creatureThing:isNpc() then
          if g_game.getAttackingCreature() ~= creatureThing then
            menu:addOption(tr('Attack'), function() attackCreature(creatureThing) end, shortcut)
          else
            menu:addOption(tr('Stop Attack'), function() clearLockedTarget(); g_game.cancelAttack() end, shortcut)
          end
        end

      if creatureThing:isNpc() and creatureThing:getPosition().z == localPosition.z then
        menu:addOption(tr('Talk'), function()
          talkToNpc(creatureThing)
        end, shortcut)
      end

        if g_game.getFollowingCreature() ~= creatureThing then
          menu:addOption(tr('Follow'), function() g_game.follow(creatureThing) end)
        else
          menu:addOption(tr('Stop Follow'), function() g_game.cancelFollow() end)
        end
      end

      if creatureThing:isNpc() and creatureThing:getIcon() == NpcIconHireling then
          menu:addSeparator()
          local coloredText = {}
          setStringColor(coloredText, '(Store)', '$var-text-cip-store-timed')

          menu:addOption(tr('Customise Character'), function() g_game.requestHirelingOutfit(creatureThing:getId()) end)
          menu:addOption(tr('Change Name/Sex'), function() g_game.openStore() end, coloredText)
          menu:addSeparator()
          menu:addOption(tr('Report Name'), function() modules.game_report.doReportMacro(creatureThing:getId(), creatureThing:getName()) end)
      end

      if creatureThing:isPlayer() then
        menu:addSeparator()
        local creatureName = creatureThing:getName()
        menu:addOption(tr('Message to %s', creatureName), function() g_game.openPrivateChannel(creatureName) end)
        if modules.game_console.hasOwnPrivateTab() then
          menu:addOption(tr('Invite to private chat'), function() g_game.inviteToOwnChannel(creatureName) end)
          menu:addOption(tr('Exclude from private chat'), function() g_game.excludeFromOwnChannel(creatureName) end) -- [TODO] must be removed after message's popup labels been implemented
        end
        if not localPlayer:hasVip(creatureName) then
          menu:addOption(tr('Add %s to VIP list', creatureName), function() g_game.addVip(creatureName) end)
        end

        if modules.game_console.Communication:isIgnored(creatureName) then
          menu:addOption(tr('Unignore') .. ' ' .. creatureName, function() modules.game_console.Communication:removeIgnoredPlayer(creatureName) end)
        else
          menu:addOption(tr('Ignore') .. ' ' .. creatureName, function() modules.game_console.Communication:addIgnoredPlayer(creatureName) end)
        end

        local localPlayerShield = localPlayer:getShield()
        local creatureShield = creatureThing:getShield()

        if localPlayerShield == ShieldNone or localPlayerShield == ShieldWhiteBlue then
          if creatureShield == ShieldWhiteYellow then
            menu:addOption(tr('Join %s\'s Party', creatureThing:getName()), function() g_game.partyJoin(creatureThing:getId()) end)
          else
            menu:addOption(tr('Invite %s to Party', creatureThing:getName()), function() g_game.partyInvite(creatureThing:getId()) end)
          end
        elseif localPlayerShield == ShieldWhiteYellow then
          if creatureShield == ShieldWhiteBlue then
            menu:addOption(tr('Revoke %s\'s Invitation', creatureThing:getName()), function() g_game.partyRevokeInvitation(creatureThing:getId()) end)
          end
        elseif localPlayerShield == ShieldYellow or localPlayerShield == ShieldYellowSharedExp or localPlayerShield == ShieldYellowNoSharedExpBlink or localPlayerShield == ShieldYellowNoSharedExp then
          if creatureShield == ShieldWhiteBlue then
            menu:addOption(tr('Revoke %s\'s Invitation', creatureThing:getName()), function() g_game.partyRevokeInvitation(creatureThing:getId()) end)
          elseif creatureShield == ShieldBlue or creatureShield == ShieldBlueSharedExp or creatureShield == ShieldBlueNoSharedExpBlink or creatureShield == ShieldBlueNoSharedExp then
            menu:addOption(tr('Pass Leadership to %s', creatureThing:getName()), function() g_game.partyPassLeadership(creatureThing:getId()) end)
          else
            menu:addOption(tr('Invite to Party'), function() g_game.partyInvite(creatureThing:getId()) end)
          end
        end
        menu:addOption(tr('Inspect %s Prestige', creatureThing:getName()), function() g_game.sendRequestPrestigeInspect(creatureThing:getName()) end)
        menu:addSeparator()
        menu:addOption(tr('Report Name'), function() modules.game_report.doReportName(creatureThing:getName()) end)
        menu:addOption(tr('Report Bot/Macro'), function() modules.game_report.doReportMacro(creatureThing:getId(), creatureThing:getName()) end)
      end
      menu:addSeparator()
      menu:addOption(tr('Copy Name'), function() g_window.setClipboardText(creatureThing:getName()) end)
    end
  end

  -- hooked menu options
  for _,category in pairs(hookedMenuOptions) do
    if not isMenuHookCategoryEmpty(category) then
      menu:addSeparator()
      for name,opt in pairs(category) do
        if opt and opt.condition(menuPosition, lookThing, useThing, creatureThing) then
          menu:addOption(name, function() opt.callback(menuPosition,
            lookThing, useThing, creatureThing) end, opt.shortcut)
        end
      end
    end
  end
  menu:display(menuPosition)
end

local function isItemThing(thing)
  return thing and type(thing.isItem) == 'function' and thing:isItem()
end

local function hasThingMethod(thing, methodName)
  return thing and type(thing[methodName]) == 'function'
end

local function callThingBool(thing, methodName)
  return hasThingMethod(thing, methodName) and thing[methodName](thing) or false
end

local function isQuickLootFeatureEnabled()
  return g_game.getFeature(GameQuickLootFlags) or g_game.getFeature(GameTibia12Protocol)
end

local function isQuickLootCorpseThing(thing)
  return isItemThing(thing) and
    not callThingBool(thing, 'isPlayerCorpse') and
    (callThingBool(thing, 'isCorpse') or callThingBool(thing, 'isLyingCorpse'))
end

local function isRootLootContainer(thing)
  return isItemThing(thing) and
    hasThingMethod(thing, 'isContainer') and
    hasThingMethod(thing, 'getParentContainer') and
    (callThingBool(thing, 'isContainer') or callThingBool(thing, 'isLyingCorpse')) and
    not thing:getParentContainer()
end

local function isQuickLootTargetThing(thing)
  return isQuickLootCorpseThing(thing)
end

local function findQuickLootThing(tile, useThing, lookThing)
  if isQuickLootTargetThing(useThing) then
    return useThing
  end
  if isQuickLootTargetThing(lookThing) then
    return lookThing
  end

  if tile and type(tile.getThings) == 'function' then
    local things = tile:getThings()
    if type(things) == 'table' then
      for _, thing in ipairs(things) do
        if isQuickLootTargetThing(thing) then
          return thing
        end
      end
    end
  end

  return nil
end

local function shouldBlockQuickLootForCreature(creatureThing)
  return creatureThing and not callThingBool(creatureThing, 'isLocalPlayer')
end

function processClassicControl(tile, menuPosition, mouseButton, autoWalkPos, lookThing, useThing, creatureThing, attackCreature, marking)
  local keyboardModifiers = g_keyboard.getModifiers()
  local config = m_settings.getOption("lootControl")
  local isLootLeftClick = config == 3 and mouseButton == MouseLeftButton and keyboardModifiers == KeyboardNoModifier
  local useLoot = (config == 1 and mouseButton == MouseRightButton and not g_keyboard.isShiftPressed() and not g_keyboard.isCtrlPressed()) or (config == 2 and mouseButton == MouseRightButton and g_keyboard.isShiftPressed()) or isLootLeftClick

  local lootThing
  if isLootLeftClick then
    lootThing = isRootLootContainer(useThing) and useThing or nil
    if not lootThing then
      lootThing = isRootLootContainer(lookThing) and lookThing or nil
    end
  end

  local quickLootThing = findQuickLootThing(tile, useThing, lookThing) or lootThing or useThing

  if quickLootThing and useLoot and isQuickLootFeatureEnabled() then
    if shouldBlockQuickLootForCreature(creatureThing) then
      goto next
    end

    if isQuickLootTargetThing(quickLootThing) or (isItemThing(quickLootThing) and mouseButton == MouseLeftButton and callThingBool(quickLootThing, 'inCorpse')) then
      g_game.quickLoot(quickLootThing:getPosition(), quickLootThing:getId(), quickLootThing:getStackPos(true), true)
      return true
    end
  end

  if isLootLeftClick and lootThing then
    g_game.openContainer(lootThing)
    return true
  end

  :: next ::

  if useThing and mouseButton == MouseRightButton and g_keyboard.isShiftPressed() then
    if showDecorationKitMenu(tile, menuPosition, lookThing, useThing, creatureThing) then
      return true
    end

    if useThing and useThing:isContainer() then
      g_game.open(useThing)
      return true
    end

    local thing = g_things.getThingType(useThing:getId())
    if creatureThing and not thing:hasAttribute(ThingAttrForceUse) and not creatureThing:getTile():hasDoor() then
      g_game.follow(creatureThing)
    elseif showDecorationKitMenu(tile, menuPosition, lookThing, useThing, creatureThing) then
      return true
    elseif useThing then
      g_game.use(useThing)
    end
  end

  if useThing and keyboardModifiers == KeyboardNoModifier and mouseButton == MouseRightButton and not g_mouse.isPressed(MouseLeftButton) then
    if showDecorationKitMenu(tile, menuPosition, lookThing, useThing, creatureThing) then
      return true
    end

    local thing = g_things.getThingType(useThing:getId())
    if not creatureThing and thing:hasAttribute(ThingAttrForceUse) then
      if showDecorationKitMenu(tile, menuPosition, lookThing, useThing, creatureThing) then
        return true
      end

      g_game.use(useThing)
      return true
    end

    local player = g_game.getLocalPlayer()
    if attackCreature and attackCreature ~= player then
      if attackCreature:isNpc() then
        g_game.use(attackCreature)
      else
        g_game.attack(attackCreature)
      end
      return true
    elseif creatureThing and creatureThing ~= player and creatureThing:getPosition().z == autoWalkPos.z then
      if creatureThing:isNpc() then
        g_game.use(creatureThing)
      else
        g_game.attack(creatureThing)
      end
      return true
    elseif useThing:isContainer() then
      if useThing:getParentContainer() then
        g_game.open(useThing, useThing:getParentContainer())
        return true
      else
        g_game.openContainer(useThing)
        return true
      end
    elseif useThing:isMultiUse() then
      startUseWith(useThing)
      return true
    elseif showDecorationKitMenu(tile, menuPosition, lookThing, useThing, creatureThing) then
      return true
    else
      g_game.use(useThing)
      return true
    end
    return true
  elseif lookThing and keyboardModifiers == KeyboardShiftModifier and (mouseButton == MouseLeftButton) then
    g_game.look(lookThing)
    return true
  elseif lookThing and ((g_mouse.isPressed(MouseLeftButton) and mouseButton == MouseRightButton) or (g_mouse.isPressed(MouseRightButton) and mouseButton == MouseLeftButton)) then
    g_game.look(lookThing)
    return true
  elseif useThing and keyboardModifiers == KeyboardCtrlModifier and (mouseButton == MouseLeftButton or mouseButton == MouseRightButton) then
    createThingMenu(tile, menuPosition, lookThing, useThing, creatureThing)
    return true
  elseif attackCreature and g_keyboard.isAltPressed() and (mouseButton == MouseLeftButton or mouseButton == MouseRightButton) then
    if attackCreature:isNpc() then
      g_game.use(attackCreature)
    else
      g_game.attack(attackCreature)
    end
    return true
  elseif creatureThing and autoWalkPos and creatureThing:getPosition().z == autoWalkPos.z and g_keyboard.isAltPressed() and (mouseButton == MouseLeftButton or mouseButton == MouseRightButton) then
    if creatureThing:isNpc() then
      g_game.use(creatureThing)
    else
      g_game.attack(creatureThing)
    end
    return true
  end

  if autoWalkPos and keyboardModifiers == KeyboardNoModifier and (mouseButton == MouseLeftButton or mouseButton == MouseTouch2 or mouseButton == MouseTouch3) then
    local autoWalkTile = g_map.getTile(autoWalkPos)
    if autoWalkTile and not autoWalkTile:isWalkable(false) then
      modules.game_textmessage.displayFailureMessage(tr('Sorry, not possible.'))
      return false
    end
    local player = g_game.getLocalPlayer()
    if player and not player:isWalkLocked() then
      player:autoWalk(autoWalkPos)
    end
    return true
  end

  return false
end

function processRegularControl(tile, menuPosition, mouseButton, autoWalkPos, lookThing, useThing, creatureThing, attackCreature, marking)
  local keyboardModifiers = g_keyboard.getModifiers()

  local quickLootThing = findQuickLootThing(tile, useThing, lookThing)
  if quickLootThing and g_keyboard.isShiftPressed() and mouseButton == MouseRightButton and isQuickLootFeatureEnabled() then
    if shouldBlockQuickLootForCreature(creatureThing) then
      goto next
    end

    g_game.quickLoot(quickLootThing:getPosition(), quickLootThing:getId(), quickLootThing:getStackPos(true), true)
    return true
  end

  :: next ::

  if keyboardModifiers == KeyboardNoModifier and mouseButton == MouseRightButton then
    createThingMenu(tile, menuPosition, lookThing, useThing, creatureThing)
    return true
  elseif lookThing and keyboardModifiers == KeyboardShiftModifier and mouseButton == MouseLeftButton then
    g_game.look(lookThing)
    return true
  elseif useThing and keyboardModifiers == KeyboardCtrlModifier and (mouseButton == MouseLeftButton or mouseButton == MouseRightButton) then
    if showDecorationKitMenu(tile, menuPosition, lookThing, useThing, creatureThing) then
      return true
    end

    if useThing:isContainer() then
      if useThing:getParentContainer() then
        g_game.open(useThing, useThing:getParentContainer())
      else
        g_game.openContainer(useThing)
      end
      return true
    elseif useThing:isMultiUse() then
      startUseWith(useThing)
      return true
    elseif showDecorationKitMenu(tile, menuPosition, lookThing, useThing, creatureThing) then
      return true
    else
      g_game.use(useThing)
      return true
    end
    return true
  elseif attackCreature and g_keyboard.isAltPressed() and mouseButton == MouseLeftButton then
    if attackCreature:isNpc() then
      g_game.use(attackCreature)
    else
      g_game.attack(attackCreature)
    end
    return true
  elseif creatureThing and creatureThing:getPosition().z == autoWalkPos.z and g_keyboard.isAltPressed() and mouseButton == MouseLeftButton then
    if creatureThing:isNpc() then
      g_game.use(creatureThing)
    else
      g_game.attack(creatureThing)
    end
    return true
  end

  if autoWalkPos and keyboardModifiers == KeyboardNoModifier and mouseButton == MouseLeftButton then
    local autoWalkTile = g_map.getTile(autoWalkPos)
    
    if autoWalkTile and not autoWalkTile:isWalkable(false) then
      modules.game_textmessage.displayFailureMessage(tr('Sorry, not possible.'))
      return false
    end
    local player = g_game.getLocalPlayer()
    if player and not player:isWalkLocked() then
      player:autoWalk(autoWalkPos)
    end
    return true
  end

  return false
end

function processSmartControl(tile, menuPosition, mouseButton, autoWalkPos, lookThing, useThing, creatureThing, attackCreature, marking)
  local keyboardModifiers = g_keyboard.getModifiers()
  local player = g_game.getLocalPlayer()
  if not player then
    return false
  end

  local quickLootThing = findQuickLootThing(tile, useThing, lookThing)
  if quickLootThing and g_keyboard.isAltPressed() and mouseButton == MouseLeftButton and isQuickLootFeatureEnabled() then
    if shouldBlockQuickLootForCreature(creatureThing) then
      goto next
    end

    g_game.quickLoot(quickLootThing:getPosition(), quickLootThing:getId(), quickLootThing:getStackPos(true), true)
    return true
  end

  :: next ::
  
  if keyboardModifiers == KeyboardNoModifier then
    if creatureThing and mouseButton == MouseLeftButton then
      if creatureThing:isNpc() then
        talkToNpc(creatureThing)
      else
        g_game.attack(creatureThing)
      end
      return true
    elseif useThing and mouseButton == MouseLeftButton then
      if showDecorationKitMenu(tile, menuPosition, lookThing, useThing, creatureThing) then
        return true
      end

      if useThing:isContainer() then
        if useThing:getParentContainer() then
          g_game.open(useThing, useThing:getParentContainer())
        else
          g_game.openContainer(useThing)
        end
      elseif useThing:isMultiUse() then
        startUseWith(useThing)
      elseif showDecorationKitMenu(tile, menuPosition, lookThing, useThing, creatureThing) then
        return true
      elseif useThing:isUsable() or useThing:isForceUse() or useThing:isPickupable() then
        g_game.use(useThing)
      elseif (useThing:isGround() or useThing:isGroundBorder() or useThing:isFullGround() or useThing:isIgnoreLook() or useThing:isNotPathable()) and autoWalkPos then
        local player = g_game.getLocalPlayer()
        if player and not player:isWalkLocked() then
          player:autoWalk(autoWalkPos)
        end
      else
        if lookThing then
          g_game.look(lookThing)
        end
      end
      return true
    elseif mouseButton == MouseRightButton then
      createThingMenu(tile, menuPosition, lookThing, useThing, creatureThing)
      return true
    end
  elseif keyboardModifiers == KeyboardCtrlModifier then
    if useThing:isContainer() then
      if useThing:getParentContainer() then
        g_game.open(useThing, useThing:getParentContainer())
      else
        g_game.openContainer(useThing)
      end
    end
  end

  if lookThing and g_keyboard.isShiftPressed() and mouseButton == MouseLeftButton then
    g_game.look(lookThing)
    return true
  end
  return false
end

function processMouseAction(tile, menuPosition, mouseButton, autoWalkPos, lookThing, useThing, creatureThing, attackCreature, marking)
  if not g_app.isMobile()
      and mouseButton == MouseRightButton
      and g_keyboard.getModifiers() == KeyboardNoModifier
      and m_settings.getOption('talkOnRightClick')
      and talkToNpc(creatureThing) then
    return true
  end

  local gameControl = tonumber(m_settings.getOption('classicControl')) or 1
  if gameControl < 1 or gameControl > 3 then
    gameControl = 1
  end

  if gameControl == 1 then
    return processClassicControl(tile, menuPosition, mouseButton, autoWalkPos, lookThing, useThing, creatureThing, attackCreature, marking)
  elseif gameControl == 2 then
    return processRegularControl(tile, menuPosition, mouseButton, autoWalkPos, lookThing, useThing, creatureThing, attackCreature, marking)
  elseif gameControl == 3 then
    return processSmartControl(tile, menuPosition, mouseButton, autoWalkPos, lookThing, useThing, creatureThing, attackCreature, marking)
  else
    g_logger.error("[ProcessMouseAction]: gameControl " .. gameControl .. " does not exist.")
  end

  return false
end

function moveStackableItem(item, toPos)
  if countWindow then
    return
  end

  local count = item:getCount()
  local manualSort = modules.game_containers.useManualSort()
  if count == 1 then
    g_game.move(item, toPos, count, manualSort)
    return
  elseif g_keyboard.isShiftPressed() then
    g_game.move(item, toPos, 1, manualSort)
    return
  elseif g_keyboard.isCtrlPressed() or g_keyboard.isKeyPressed("Enter") then
    g_game.move(item, toPos, count, manualSort)
    return
  end

  countWindow = g_ui.createWidget('CountWindow', rootWidget)
  local itembox = countWindow.contentPanel:getChildById('item')
  local itemCountLabel = countWindow.contentPanel:getChildById('itemCount')
  local scrollbar = countWindow.contentPanel:getChildById('countScrollBar')
  local setItemboxCount = function(value)
    itembox:setItemCount(value)
    itemCountLabel:setText(tostring(value))
  end

  g_client.setInputLockWidget(countWindow)
  itembox:setItemId(item:getId())
  setItemboxCount(count)
  scrollbar:setMaximum(count)
  scrollbar:setMinimum(1)
  scrollbar:setValue(count)

  local spinbox = countWindow.contentPanel:getChildById('spinBox')
  spinbox:setMaximum(count)
  spinbox:setMinimum(0)
  spinbox:setValue(0)
  spinbox:hideButtons()
  spinbox:focus()
  spinbox.firstEdit = true

  local spinBoxValueChange = function(self, value)
    spinbox.firstEdit = false
    scrollbar:setValue(value)
  end
  spinbox.onValueChange = spinBoxValueChange

  local check = function()
    if spinbox.firstEdit then
      spinbox:setValue(spinbox:getMaximum())
      spinbox.firstEdit = false
    end
  end
  local okButton = countWindow.contentPanel:getChildById('buttonOk')
  local moveFunc = function()
    g_keyboard.unbindKeyDown('Enter', nil, countWindow)
    g_keyboard.unbindKeyDown('Escape', nil, countWindow)
    g_keyboard.unbindKeyDown('Num+Enter', nil, countWindow)
    g_game.move(item, toPos, itembox:getItemCount(), manualSort)
    g_client.setInputLockWidget(nil)
    countWindow:destroy()
    countWindow = nil
  end
  local cancelButton = countWindow.contentPanel:getChildById('buttonCancel')
  local cancelFunc = function()
    g_keyboard.unbindKeyDown('Enter', nil, countWindow)
    g_keyboard.unbindKeyDown('Escape', nil, countWindow)
    g_keyboard.unbindKeyDown('Num+Enter', nil, countWindow)
    g_client.setInputLockWidget(nil)
    countWindow:destroy()
    countWindow = nil
  end

  g_keyboard.bindKeyDown('Enter', moveFunc, countWindow)
  g_keyboard.bindKeyDown('Num+Enter', moveFunc, countWindow)
  g_keyboard.bindKeyDown('Escape', cancelFunc, countWindow)

  g_keyboard.bindKeyPress("Up", function() check() spinbox:up() end, spinbox)
  g_keyboard.bindKeyPress("Down", function() check() spinbox:down() end, spinbox)
  g_keyboard.bindKeyPress("Right", function() check() spinbox:up() end, spinbox)
  g_keyboard.bindKeyPress("Left", function() check() spinbox:down() end, spinbox)
  g_keyboard.bindKeyPress("PageUp", function() check() spinbox:setValue(spinbox:getValue()+10) end, spinbox)
  g_keyboard.bindKeyPress("PageDown", function() check() spinbox:setValue(spinbox:getValue()-10) end, spinbox)
  g_keyboard.bindKeyPress("Enter", function() moveFunc() end, spinbox)
  g_keyboard.bindKeyPress("Num+Enter", function() moveFunc() end, spinbox)

  scrollbar.onValueChange = function(self, value)
    setItemboxCount(value)
    spinbox.onValueChange = nil
    spinbox:setValue(value)
    spinbox.onValueChange = spinBoxValueChange
  end

  scrollbar.onClick =
    function()
      local mousePos = g_window.getMousePosition()
      check()
      local sliderButton = scrollbar:getChildById('sliderButton')
      scrollbar:setSliderClick(sliderButton, sliderButton:getPosition())
      scrollbar:setSliderPos(sliderButton, sliderButton:getPosition(), {x = mousePos.x - sliderButton:getPosition().x, y = 0})
    end

  onEnter = moveFunc
  onEscape = cancelFunc

  okButton.onClick = moveFunc
  cancelButton.onClick = cancelFunc
end

function getRootPanel()
  return gameRootPanel
end

function getMapPanel()
  return gameMapPanel
end

function getRightPanel()
  if getPersistentSidePanelCount(gameRightPanels) == 0 then
    addRightPanel()
  end
  return getPersistentSidePanel(gameRightPanels, -1)
end

function getLeftPanel()
  if getPersistentSidePanelCount(gameLeftPanels) >= 1 then
    return getPersistentSidePanel(gameLeftPanels, -1)
  end
  return getRightPanel()
end

function getContainerPanel()
  local containerPanel = g_settings.getNumber("containerPanel")
  if containerPanel >= 5 then
    containerPanel = containerPanel - 4
    return getPersistentSidePanel(gameRightPanels,
      math.min(containerPanel, getPersistentSidePanelCount(gameRightPanels)))
  end
  if getPersistentSidePanelCount(gameLeftPanels) == 0 then
    return getRightPanel()
  end
  return getPersistentSidePanel(gameLeftPanels,
    math.min(containerPanel, getPersistentSidePanelCount(gameLeftPanels)))
end

function addRightPanel()
  setRightHorizontalWidth()
  local panelCount = getPersistentSidePanelCount(gameRightPanels)
  if panelCount >= 4 then
    return
  end
  local panel = g_ui.createWidget('GameSidePanel')
  panel:setId("rightPanel" .. (panelCount + 1))
  panel.onClick = toggleInternalFocus
  gameRightPanels:insertChild(1, panel)
  keepMinimapExpansionReservationAtEdge(gameRightPanels, 'right')

  setRightHorizontalWidth()
  g_settings.set("rightPanels", getPersistentSidePanelCount(gameRightPanels))
  scheduleEvent(function() modules.game_actionbar.updateVisibleWidgets() end, 10)
  return panel
end

function addLeftPanel()
  setLeftHorizontalWidth()
  local panelCount = getPersistentSidePanelCount(gameLeftPanels)
  if panelCount >= 4 then
    return
  end
  local panel = g_ui.createWidget('GameSidePanel')
  panel:setId("leftPanel" .. (panelCount + 1))
  panel.onClick = toggleInternalFocus
  gameLeftPanels:addChild(panel)
  keepMinimapExpansionReservationAtEdge(gameLeftPanels, 'left')

  setLeftHorizontalWidth()
  g_settings.set("leftPanels", getPersistentSidePanelCount(gameLeftPanels))
  scheduleEvent(function() modules.game_actionbar.updateVisibleWidgets() end, 10)
  return panel
end

function reserveMinimapExpansionSpace(side, width, reservation)
  if side ~= 'left' and side ~= 'right' then
    return nil
  end

  local panels = side == 'left' and gameLeftPanels or gameRightPanels
  if not panels then
    return nil
  end

  if not reservation or reservation:isDestroyed() or reservation:getParent() ~= panels then
    reservation = g_ui.createWidget('GameSidePanel')
    reservation:setId('minimapExpansionReservation' .. (side == 'left' and 'Left' or 'Right'))
    reservation.minimapExpansionReservation = true
    reservation.save = false
    reservation:setFocusable(false)
    -- It is a spacer, not a sidebar: refuse mini windows dropped onto it, which
    -- setFocusable alone does not prevent.
    reservation.onDrop = function() return false end
    if side == 'left' then
      panels:addChild(reservation)
    else
      panels:insertChild(1, reservation)
    end
  end

  reservation:setWidth(math.max(1, math.floor(width)))
  if side == 'left' then
    setLeftHorizontalWidth()
  else
    setRightHorizontalWidth()
  end
  return reservation
end

function releaseMinimapExpansionSpace(reservation)
  if not reservation or reservation:isDestroyed() or
      not isMinimapExpansionReservation(reservation) then
    return
  end

  local parent = reservation:getParent()
  local side = parent == gameLeftPanels and 'left' or
    (parent == gameRightPanels and 'right' or nil)

  -- Anything that still ended up inside the reservation would be destroyed along with
  -- it, so hand it over to a real panel first.
  local survivor = getPersistentSidePanel(parent, 1) or
    getPersistentSidePanel(gameRightPanels, 1) or
    getPersistentSidePanel(gameLeftPanels, 1)
  if survivor then
    for _, child in ipairs(reservation:getChildren()) do
      reservation:removeChild(child)
      survivor:addChild(child)
    end
  end

  reservation:destroy()

  if side == 'left' then
    setLeftHorizontalWidth()
  elseif side == 'right' then
    setRightHorizontalWidth()
  end
end

function removeRightPanel()
  removePanel("right")
end

function removeLeftPanel()
  removePanel("left")
end

function toggleInternalFocus()
  for reason, _ in pairs(focusReason) do
    if reason == 'bosscooldown' then
      modules.game_analyser.toggleBossCDFocus(false)
    elseif reason == 'npctrade' then
      modules.game_npctrade.toggleNPCFocus(false)
    elseif reason == 'searchlocker' then
      modules.game_search_locker.toggleSearchFocus(false)
    end
  end
end

function isInternalLocked()
  if not focusReason or table.empty(focusReason) then
    return false
  end
  return true
end

function toggleFocus(value, reason)
  if not reason then
    reason = ''
  end
  if not value then
    getBottomPanel():focus()
    if not reason then
      reason = ''
    end

    focusReason[reason] = nil
  else
    focusReason[reason] = true
  end

  if not value and #focusReason ~= 0 then
    return
  end

  gameRightPanels:setFocusable(value)
  gameLeftPanels:setFocusable(value)
end

function isPanelFocused()
  return gameRightPanels:isFocused() or gameLeftPanels:isFocused()
end

function getBottomPanel()
  return gameBottomPanel
end

function getBottomActionPanel()
  return gameBottomActionPanel
end

function getBottomCooldownPanel()
  return gameBottomCooldownPanel
end

function getLeftActionPanel()
  return gameLeftActionPanel
end

function getRightActionPanel()
  return gameRightActionPanel
end

function getBottomLockPanel()
  return gameBottomLockPanel
end

function getRightLockPanel()
  return gameRightLockPanel
end

function getLeftLockPanel()
  return gameLeftLockPanel
end

function getTopBar()
  return gameTopBar
end

function getLeftBar()
  return gameLeftBar
end

function getRightBar()
  return gameRightBar
end

local function replaceAnchor(widget, anchor, target, targetAnchor)
  if not widget then
    return
  end

  widget:removeAnchor(anchor)
  widget:addAnchor(anchor, target, targetAnchor)
end

local function anchorGameAreaToParentTop()
  replaceAnchor(gameMapPanel, AnchorTop, 'parent', AnchorTop)
  replaceAnchor(gameLeftActionPanel, AnchorTop, 'parent', AnchorTop)
  replaceAnchor(gameRightActionPanel, AnchorTop, 'parent', AnchorTop)
  gameLeftActionPanel:setPaddingTop(54)
  gameRightActionPanel:setPaddingTop(54)
end

local function anchorGameAreaToTopBar()
  replaceAnchor(gameMapPanel, AnchorTop, 'gameTopBar', AnchorBottom)
  replaceAnchor(gameLeftActionPanel, AnchorTop, 'gameTopBar', AnchorBottom)
  replaceAnchor(gameRightActionPanel, AnchorTop, 'gameTopBar', AnchorBottom)
  gameLeftActionPanel:setPaddingTop(1)
  gameRightActionPanel:setPaddingTop(1)
end

local function scheduleHealthCircleResizeUpdates()
  if healthCircleResizeEvent then
    removeEvent(healthCircleResizeEvent)
  end

  healthCircleResizeEvent = scheduleEvent(function()
    healthCircleResizeEvent = nil
    if modules.game_healthcircle and modules.game_healthcircle.scheduleMapResizeUpdates then
      modules.game_healthcircle.scheduleMapResizeUpdates()
    end
  end, 50)
end

function updateTopBar(side)
  -- In extended view the map is the full-screen background. Top-bar settings
  -- are reloaded after login and must not restore the classic side/bottom
  -- anchors, otherwise uncovered sidebar and console areas turn black.
  if not isClassicViewActive() then
    gameTopBar:setVisible(false)
    gameMapPanel:breakAnchors()
    gameMapPanel:fill('parent')
    gameMapPanel:setMarginLeft(0)
    gameMapPanel:setMarginRight(0)
    gameMapPanel:setMarginTop(0)
    gameMapPanel:setMarginBottom(0)
    scheduleHealthCircleResizeUpdates()
    return
  end

  if side == "bottom" then
    gameTopBar:setVisible(true)
    gameTopBar:setParent(gameBottomActionPanel)
    gameMapPanel:addAnchor(AnchorLeft, 'gameLeftActionPanel', AnchorRight)
    gameMapPanel:addAnchor(AnchorRight, 'gameRightActionPanel', AnchorLeft)
    gameMapPanel:addAnchor(AnchorBottom, 'bottomSplitter', AnchorTop)
    anchorGameAreaToParentTop()
  elseif side == "top" then
    gameTopBar:setVisible(true)
    gameTopBar:setParent(gameRootPanel)
    replaceAnchor(gameTopBar, AnchorTop, 'parent', AnchorTop)
    replaceAnchor(gameTopBar, AnchorLeft, 'gameBottomActionPanel', AnchorLeft)
    replaceAnchor(gameTopBar, AnchorRight, 'gameBottomActionPanel', AnchorRight)

    gameRootPanel:moveChildToIndex(gameTopBar, 1)
    gameMapPanel:addAnchor(AnchorLeft, 'gameLeftActionPanel', AnchorRight)
    gameMapPanel:addAnchor(AnchorRight, 'gameRightActionPanel', AnchorLeft)
    gameMapPanel:addAnchor(AnchorBottom, 'bottomSplitter', AnchorTop)
    anchorGameAreaToTopBar()

  elseif side == "left" or side == "right" then
    gameTopBar:setVisible(false)
    anchorGameAreaToParentTop()
    gameMapPanel:addAnchor(AnchorBottom, 'bottomSplitter', AnchorTop)
  else
    gameTopBar:setVisible(false)
    anchorGameAreaToParentTop()
    gameMapPanel:addAnchor(AnchorBottom, 'bottomSplitter', AnchorTop)
  end

  if isClassicViewActive() and modules.game_actionbar and modules.game_actionbar.updateGameMapPanelMargin then
    modules.game_actionbar.updateGameMapPanelMargin()
  else
    gameMapPanel:setMarginBottom(0)
  end

  scheduleHealthCircleResizeUpdates()
end

function refreshViewMode()
  local classic = isClassicViewActive() -- and not g_app.isMobile()
  updatePanelArrowVisibility()
  local rightPanels = g_settings.getNumber("rightPanels") - getPersistentSidePanelCount(gameRightPanels)
  local leftPanels = g_settings.getNumber("leftPanels") - getPersistentSidePanelCount(gameLeftPanels)

  while rightPanels ~= 0 do
    if rightPanels > 0 then
      addRightPanel()
      rightPanels = rightPanels - 1
    else
      removeRightPanel()
      rightPanels = rightPanels + 1
    end
  end
  while leftPanels ~= 0 do
    if leftPanels > 0 then
      addLeftPanel()
      leftPanels = leftPanels - 1
    else
      removeLeftPanel()
      leftPanels = leftPanels + 1
    end
  end

  if not g_game.isOnline() then
    return
  end

  local minimumWidth = (g_settings.getNumber("rightPanels") + g_settings.getNumber("leftPanels") - 1) * 200 + 200
  minimumWidth = math.max(minimumWidth, 800)
  g_window.setMinimumSize({ width = minimumWidth, height = 600})
  if g_window.getWidth() < minimumWidth then
    local oldPos = g_window.getPosition()
    local size = { width = minimumWidth, height = g_window.getHeight() }
    g_window.resize(size)
    g_window.move(oldPos)
  end

  for i=1,gameRightPanels:getChildCount()+gameLeftPanels:getChildCount() do
    local panel
    if i > gameRightPanels:getChildCount() then
      panel = gameLeftPanels:getChildByIndex(i - gameRightPanels:getChildCount())
    else
      panel = gameRightPanels:getChildByIndex(i)
    end
    if classic then
      panel:setImageColor('white')
    else
      panel:setImageColor('alpha')
    end
  end

  local sidePanelColor = classic and 'white' or 'alpha'
  horizontalRightPanel:setImageColor(sidePanelColor)
  horizontalLeftPanel:setImageColor(sidePanelColor)

  panel = gameRightPanels:getChildByIndex(gameRightPanels:getChildCount())
  if panel then
    panel:setMarginRight(0)
  end

  if classic then
    gameRightPanels:setMarginTop(0)
    gameLeftPanels:setMarginTop(0)
    gameMapPanel:setMarginLeft(0)
    gameMapPanel:setMarginRight(0)
    gameMapPanel:setMarginTop(0)
  end

  gameMapPanel:setVisibleDimension({ width = 15, height = 11 })

  if classic then
    gameMapPanel:addAnchor(AnchorLeft, 'gameLeftActionPanel', AnchorRight)
    gameMapPanel:addAnchor(AnchorRight, 'gameRightActionPanel', AnchorLeft)
    gameMapPanel:addAnchor(AnchorBottom, 'gameBottomActionPanel', AnchorTop)
    gameMapPanel:addAnchor(AnchorBottom, 'gameBottomCooldownPanel', AnchorTop)
    local customisableTopBarEnabled = false
    if modules.game_topbar then
      if modules.game_topbar.shouldShowCustomisableBar then
        customisableTopBarEnabled = modules.game_topbar.shouldShowCustomisableBar()
      elseif modules.game_topbar.isCustomisableBarVisible then
        customisableTopBarEnabled = modules.game_topbar.isCustomisableBarVisible()
      end
    end

    if customisableTopBarEnabled then
      updateTopBar(modules.game_topbar.getCurrentDirection())
    else
      updateTopBar("hidden")
    end
    gameMapPanel:setKeepAspectRatio(true)
    gameMapPanel:setLimitVisibleRange(false)
    gameMapPanel:setZoom(11)
    gameMapPanel:setOn(false) -- frame
    gameLeftActionPanel:setImageSource('/images/ui/actionbar_background-light')
    gameRightActionPanel:setImageSource('/images/ui/actionbar_background-light')
    gameLeftActionPanel:setBorderWidthRight(1)
    gameRightActionPanel:setBorderWidthLeft(1)

    modules.client_topmenu.getTopMenu():setImageColor('white')

    if modules.game_console then
      modules.game_console.switchMode(false)
    end
  else
    gameMapPanel:breakAnchors()
    gameMapPanel:fill('parent')
    gameMapPanel:setKeepAspectRatio(false)
    gameMapPanel:setLimitVisibleRange(false)
    gameMapPanel:setOn(true)
    gameLeftActionPanel:setImageSource("")
    gameRightActionPanel:setImageSource("")
    gameLeftActionPanel:setBorderWidthRight(0)
    gameRightActionPanel:setBorderWidthLeft(0)
    -- Same behavior as Mehah's extended view: keep the normal tile zoom and
    -- use the larger server aware range to fill the widescreen map panel.
    gameMapPanel:setZoom(11)

    modules.client_topmenu.getTopMenu():setImageColor('#ffffff66')
    if g_app.isMobile() then
      gameMapPanel:setMarginTop(-32)
    end
    if modules.game_console then
      modules.game_console.switchMode(true)
    end
  end

  if g_settings.getBoolean("cacheMap") then
    g_game.enableFeature(GameBiggerMapCache)
  end

  updateSize()
end

function limitZoom()
  limitedZoom = true
end

function updateSize()
  if g_app.isMobile() then return end

  local classic = isClassicViewActive()
  local height = gameMapPanel:getHeight()
  local width = gameMapPanel:getWidth()

  if not classic then
    local rheight = gameRootPanel:getHeight()
    local rwidth = gameRootPanel:getWidth()

    local dimenstion = gameMapPanel:getVisibleDimension()
    local zoom = gameMapPanel:getZoom()
    local awareRange = g_map.getAwareRange()
    local maxZoomOut = getExtendedMaxZoomOut()
    gameMapPanel:setMaxZoomOut(maxZoomOut)
    if zoom > maxZoomOut then
      gameMapPanel:setZoom(maxZoomOut)
      return
    end
    local dheight = dimenstion.height
    local dwidth = dimenstion.width
    local tileSize = rheight / dheight
    local maxWidth = tileSize * (awareRange.width + 1)
    if g_game.getFeature(GameChangeMapAwareRange) and g_game.getFeature(GameNewWalking) then
      maxWidth = tileSize * (awareRange.width - 1)
    end
    gameMapPanel:setMarginTop(-tileSize)
    if modules.game_stats then
      modules.game_stats.ui:setMarginTop(tileSize)
    end
    if g_settings.getBoolean("cacheMap") then
      gameMapPanel:setMarginLeft(0)
      gameMapPanel:setMarginRight(0)
    else
      local margin = math.max(0, math.floor((rwidth - maxWidth) / 2))
      gameMapPanel:setMarginLeft(margin)
      gameMapPanel:setMarginRight(margin)
    end
  else
    if modules.game_stats then
      modules.game_stats.ui:setMarginTop(0)
    end
  end

  gameMapPanel:setWidth(width)
  gameMapPanel:setHeight(height)
  if classic and modules.game_actionbar and modules.game_actionbar.updateGameMapPanelMargin then
    modules.game_actionbar.updateGameMapPanelMargin()
  else
    gameMapPanel:setMarginBottom(0)
  end

  scheduleHealthCircleResizeUpdates()
end

function setupLeftActions()
  if not g_app.isMobile() then return end
  for _, widget in ipairs(gameLeftActions:getChildren()) do
    widget.image:setChecked(false)
    widget.lastClicked = 0
    widget.onClick = function()
      if widget.image:isChecked() then
        widget.image:setChecked(false)
        if widget.doubleClickAction and widget.lastClicked + 200 > g_clock.millis() then
          widget.doubleClickAction()
        end
        return
      end
      resetLeftActions()
      widget.image:setChecked(true)
      widget.lastClicked = g_clock.millis()
    end
  end
  if gameLeftActions.use then
    gameLeftActions.use.doubleClickAction = function()
      local player = g_game.getLocalPlayer()
      local dir = player:getDirection()
      local usePos = player:getPrewalkingPosition(true)
      if dir == North then
        usePos.y = usePos.y - 1
      elseif dir == East then
        usePos.x = usePos.x + 1
      elseif dir == South then
        usePos.y = usePos.y + 1
      elseif dir == West then
        usePos.x = usePos.x - 1
      end
      local tile = g_map.getTile(usePos)
      if not tile then return end
      local thing = tile:getTopUseThing()
      if thing and not isDecorationKitThing(thing) then
        g_game.use(thing)
      end
    end
  end
  if gameLeftActions.attack then
    gameLeftActions.attack.doubleClickAction = function()
      local battlePanel = modules.game_battle.battlePanel
      local attackedCreature = g_game.getAttackingCreature()
      local child = battlePanel:getFirstChild()
      if child and (not child.creature or not child:isOn()) then
        child = nil
      end
      if child then
        attackCreature(child.creature)
      else
        clearLockedTarget()
        g_game.attack(nil)
      end
    end
  end
  if gameLeftActions.follow then
    gameLeftActions.follow.doubleClickAction = function()
      local battlePanel = modules.game_battle.battlePanel
      local attackedCreature = g_game.getAttackingCreature()
      local child = battlePanel:getFirstChild()
      if child and (not child.creature or not child:isOn()) then
        child = nil
      end
      if child then
        g_game.follow(child.creature)
      else
        g_game.follow(nil)
      end
    end
  end
  if gameLeftActions.look then
    gameLeftActions.look.doubleClickAction = function()
      local battlePanel = modules.game_battle.battlePanel
      local attackedCreature = g_game.getAttackingCreature()
      local child = battlePanel:getFirstChild()
      if child and (not child.creature or child:isHidden()) then
        child = nil
      end
      if child then
        g_game.look(child.creature)
      end
    end
  end
  if not gameLeftActions.chat then return end
  gameLeftActions.chat.onClick = function()
    if gameBottomPanel:getHeight() <= 5 then
      gameBottomPanel:setHeight(90)
    else
      gameBottomPanel:setHeight(0)
    end
  end
end

function resetLeftActions()
  for _, widget in ipairs(gameLeftActions:getChildren()) do
    widget.image:setChecked(false)
    widget.lastClicked = 0
  end
end

function getLeftAction()
  for _, widget in ipairs(gameLeftActions:getChildren()) do
    if widget.image:isChecked() then
      return widget:getId()
    end
  end
  return ""
end

function isChatVisible()
  return gameBottomPanel:getHeight() >= 5
end

function creatureHealthPercentChange(creature, healthPercent)
  if healthPercent > 94 then
    creature:setInformationColor("#00C000FF")
  elseif healthPercent > 59 then
    creature:setInformationColor("#60c060FF")
  elseif healthPercent > 29 then
    creature:setInformationColor("#c0c000FF")
  elseif healthPercent > 9 then
    creature:setInformationColor("#c03030FF")
  elseif healthPercent > 3 then
    creature:setInformationColor("#c00000FF")
  else
    creature:setInformationColor("#600000FF")
  end
end

function canUpdateWindowMargin(self, newMargin)
	return math.max(math.min(newMargin, self:getParent():getHeight() - 150), 155)
end

function showRightHorizontalPanel(visible)
  horizontalRightPanel:setHeight(visible and 200 or 0)
  setRightHorizontalWidth()
  if not visible then
    local children = horizontalRightPanel:getChildren()
    for _, widget in pairs(children) do
      moveToOtherPanel(widget)
    end
  end
end

function showLeftHorizontalPanel(visible)
  if getPersistentSidePanelCount(gameLeftPanels) < 1 and visible then
    g_settings.set("leftPanels", 1)
    refreshViewMode()
  end

  horizontalLeftPanel:setHeight(visible and 200 or 0)
  if not visible then
    local children = horizontalLeftPanel:getChildren()
    for _, widget in pairs(children) do
      moveToOtherPanel(widget)
    end
  end
end

function moveToOtherPanel(widget)
  local mousePos = g_window.getMousePosition()
    if(m_interface.getLeftPanel():isVisible()) then
      if m_interface.getRootPanel():getWidth() / 2 < mousePos.x then
        addEvent(function() widget:setParent(m_interface.getRightPanel()) end)
      else
        addEvent(function() widget:setParent(m_interface.getLeftPanel()) end)
    end
  else
    addEvent(function() widget:setParent(m_interface.getRightPanel()) end)
  end
end

function setLeftHorizontalWidth()
  horizontalLeftPanel:setWidth(getSidePanelsWidth(gameLeftPanels))
  if horizontalLeftPanel:getWidth() == 0 then
    local children = horizontalLeftPanel:getChildren()
    for _, widget in pairs(children) do
      moveToOtherPanel(widget)
    end
  end
end

function setRightHorizontalWidth()
  horizontalRightPanel:setWidth(getSidePanelsWidth(gameRightPanels))
  if horizontalRightPanel:getWidth() == 0 then
    local children = horizontalRightPanel:getChildren()
    for _, widget in pairs(children) do
      moveToOtherPanel(widget)
    end
  end
end

function checkHorizontalPanel(widget)
  local relativeHeight = 0
  local totalHeight = widget:getHeight() + 10 -- margin de erro

  local moveWidgets = {}
  local children = widget:getChildren()
  for _, child in pairs(children) do
    relativeHeight = relativeHeight + child:getHeight()
    if relativeHeight > totalHeight then
      table.insert(moveWidgets, child)
    end
  end

  for _, w in pairs(moveWidgets) do
    moveToOtherPanel(w)
  end
end

function onLoadHorizontalPanels(horizontalLeftOptions, horizontalRightOptions)
  if horizontalLeftOptions and horizontalLeftOptions.contentHeight then
    horizontalLeftPanel:setHeight(horizontalLeftOptions.contentHeight)
  end
  if horizontalRightOptions and horizontalRightOptions.contentHeight then
    horizontalRightPanel:setHeight(horizontalRightOptions.contentHeight)
  end
end

local function callRestoredWidgetMethod(widget, methodName)
  local method = widget[methodName]
  if not method then return false end

  local ok, err = pcall(method, widget)
  if not ok and g_logger and g_logger.warning then
    g_logger.warning(string.format("Failed to %s restored widget %s: %s", methodName, widget:getId() or '', tostring(err)))
  end
  return ok
end

local function closeRestoredWidget(widget, primordial)
  if not widget or not widget:isVisible() then
    return
  end

  local id = widget:getId() or ''
  if string.containsTable(id, primordial) then
    return
  end

  if callRestoredWidgetMethod(widget, 'close') then return end
  if callRestoredWidgetMethod(widget, 'destroy') then return end
  callRestoredWidgetMethod(widget, 'hide')
end

function onPlayerLoad(config)
  if not config.leftSidebarCount then
    for i = 1, getPersistentSidePanelCount(gameLeftPanels) do
      removeLeftPanel()
    end
    config.leftSidebarCount = 0
  end

  if not config.openWidgetsOrderPerSidebar then
    return
  end
  local leftPanels = config.leftSidebarCount
  local rightPanels = #config.openWidgetsOrderPerSidebar - leftPanels
  local primordial = {"container", "inventoryWindow", "mainButtons", "healthInfo"}

  if getPersistentSidePanelCount(gameLeftPanels) >= leftPanels then
    for i = 1, getPersistentSidePanelCount(gameLeftPanels) do
      removeLeftPanel()
    end
  end

  g_settings.set("rightPanels", rightPanels)
  g_settings.set("leftPanels", leftPanels)

  refreshViewMode()

  addEvent(function()
    -- get RightPanels
    for i = 1, rightPanels do
      local panel = getPersistentSidePanel(gameRightPanels, i)
      if panel then
        for _, widget in pairs(panel:getChildren()) do
          closeRestoredWidget(widget, primordial)
        end

        for k, x in ipairs(config.openWidgetsOrderPerSidebar[i]) do
          restorePanelWidget(panel, x, k)
        end
      end
    end

    -- get LeftPanels
    for i = 1, leftPanels do
      local panel = getPersistentSidePanel(gameLeftPanels, i)
      if panel then
        for _, widget in pairs(panel:getChildren()) do
          closeRestoredWidget(widget, primordial)
        end

        for k, x in ipairs(config.openWidgetsOrderPerSidebar[i + rightPanels]) do
          restorePanelWidget(panel, x, k)
        end
      end
    end

    -- get Right Horizontal
    if config.openWidgetsHorizontalRight then
      for _, widget in pairs(horizontalRightPanel:getChildren()) do
        closeRestoredWidget(widget, primordial)
      end

      for k, x in ipairs(config.openWidgetsHorizontalRight) do
        restorePanelWidget(horizontalRightPanel, x, k)
      end
    end
    -- get Left Horizontal
    if config.openWidgetsHorizontalLeft then
      for _, widget in pairs(horizontalLeftPanel:getChildren()) do
        closeRestoredWidget(widget, primordial)
      end

      for k, x in ipairs(config.openWidgetsHorizontalLeft) do
        restorePanelWidget(horizontalLeftPanel, x, k)
      end
    end
  end)
end

function onPlayerUnload()
  -- avoid double save
  if interfaceSaved then
    return
  end

  g_logger.info("Saving opened widgets...")

  local config = {
    leftSidebarCount = getPersistentSidePanelCount(gameLeftPanels),
    openWidgetsOrderPerSidebar = {},
    openWidgetsHorizontalRight = {},
    openWidgetsHorizontalLeft = {},
  }

  local rightPanels = getPersistentSidePanels(gameRightPanels)
  for _, panel in ipairs(rightPanels) do
    config.openWidgetsOrderPerSidebar[#config.openWidgetsOrderPerSidebar + 1] = {}
    for z, a in pairs(panel:getChildren()) do
      local widgetType = a.getType and a:getType()
      if widgetType and (a:isOpened() or widgetType == 'miniMap') then
        local tt = {type = widgetType}
        if a.instance then
          tt.instance = a.instance
        end

        tt.minimized = a.minimized
        if widgetType == "inventoryWindow" or widgetType == "mainButtonsWindow" then
          tt.minimized = a.minimized or false
        end

        if a.minimized then
          tt.height = a.maximizedHeight
        else
          tt.height = a:getHeight()
        end

        if a:isLocked() then
          tt.locked = a:isLocked()
        end
        table.insert(config.openWidgetsOrderPerSidebar[#config.openWidgetsOrderPerSidebar], tt)
      end
    end
  end

  local leftPanels = getPersistentSidePanels(gameLeftPanels)
  for _, panel in ipairs(leftPanels) do
    config.openWidgetsOrderPerSidebar[#config.openWidgetsOrderPerSidebar + 1] = {}
    for z, a in pairs(panel:getChildren()) do
      local widgetType = a.getType and a:getType()
      if widgetType and (a:isOpened() or widgetType == 'miniMap') then
        local tt = {type = widgetType}
        if a.instance then
          tt.instance = a.instance
        end

        tt.minimized = a.minimized
        if widgetType == "inventoryWindow" or widgetType == "mainButtonsWindow" then
          tt.minimized = a.minimized or false
        end

        if a.minimized then
          tt.height = a.maximizedHeight
        else
          tt.height = a:getHeight()
        end

        if a:isLocked() then
          tt.locked = a:isLocked()
        end
        table.insert(config.openWidgetsOrderPerSidebar[#config.openWidgetsOrderPerSidebar], tt)
      end
    end
  end

  for z, a in pairs(horizontalRightPanel:getChildren()) do
    local widgetType = a.getType and a:getType()
    if widgetType and a.isOpen then
      local tt = {type = widgetType}
      if a.instance then
        tt.instance = a.instance
      end

      tt.minimized = a.minimized
      if widgetType == "inventoryWindow" or widgetType == "mainButtonsWindow" then
        tt.minimized = a.minimized or false
      end

      if a.minimized then
        tt.height = a.maximizedHeight
      else
        tt.height = a:getHeight()
      end
      if a:isLocked() then
        tt.locked = a:isLocked()
      end
      table.insert(config.openWidgetsHorizontalRight, tt)
    end
  end
  for z, a in pairs(horizontalLeftPanel:getChildren()) do
    local widgetType = a.getType and a:getType()
    if widgetType and a.isOpen then
      local tt = {type = widgetType}
      if a.instance then
        tt.instance = a.instance
      end

      tt.minimized = a.minimized
      if widgetType == "inventoryWindow" or widgetType == "mainButtonsWindow" then
        tt.minimized = a.minimized or false
      end

      if a.minimized then
        tt.height = a.maximizedHeight
      else
        tt.height = a:getHeight()
      end
      if a:isLocked() then
        tt.locked = a:isLocked()
      end
      table.insert(config.openWidgetsHorizontalLeft, tt)
    end
  end

  modules.game_sidebars.resetConfigs()
  modules.game_sidebars.registerHorizontalPanels(horizontalLeftPanel:getHeight(), horizontalRightPanel:getHeight())
  modules.game_sidebars.registerSideBarWidgetsManager(config)
  modules.game_sidebars.saveConfigJson()
end

local fixedWidgets = {"miniMap", "healthInfo", 'mainButtons'}
function restorePanelWidget(panel, x, k)
  if not x.height then
    x.height = 120
  end

  if not x.minimized and not table.contains(fixedWidgets, x.type) then
    x.minimized = false
  end

  local widget = nil
  if x.type == 'container' then
    widget = modules.game_containers.move(x.instance, panel, x.height, k, x.minimized, x.locked)
  elseif x.type == 'analyticsSelector' then
    widget = modules.game_analyser.moveAnalyser(panel, x.height, x.minimized)
    modules.game_sidebuttons.setButtonVisible("analyticsSelectorWidget", true)
  elseif table.contains({'bossCooldowns', 'damageInputAnalyser', 'lootTracker','huntingSessionAnalyser', 'impactAnalyser', 'lootAnalyser', 'partyHuntAnalyser', 'wasteAnalyser', 'xpAnalyser', 'miscAnalyzer'}, x.type) then
    widget = modules.game_analyser.moveChildAnalyser(x.type, panel, x.height, x.minimized)
  elseif table.contains({'bestiaryTracker', 'bosstiaryTracker', 'imbuementTracker'}, x.type) then
    widget = modules.game_trackers.moveTracker(x.type, panel, x.height, x.minimized)
    modules.game_sidebuttons.setButtonVisible(x.type .. "Widget", true)
  elseif x.type == 'battleList' then
    widget = modules.game_battle.moveBattle(x.instance, panel, x.height, x.minimized)
    modules.game_sidebuttons.setButtonVisible("battleListWidget", true)
  elseif x.type == 'prey' then
    widget = modules.game_prey.move(panel, x.height, x.minimized)
    modules.game_sidebuttons.setButtonVisible("preyWidget", true)
  elseif x.type == 'questTracker' then
    widget = modules.game_questlog.move(panel, x.height, k, x.minimized)
    modules.game_sidebuttons.setButtonVisible("questTrackerWidget", true)
  elseif x.type == 'skills' then
    widget = modules.game_skills.move(panel, x.height, k, x.minimized)
    modules.game_sidebuttons.setButtonVisible("skillsWidget", true)
  elseif x.type == 'unjustifiedPoints' then
    widget = modules.game_unjustifiedpoints.move(panel, x.height, k, x.minimized)
    modules.game_sidebuttons.setButtonVisible("unjustifiedPoinsWidget", true)
  elseif x.type == 'vip' then
    widget = modules.game_viplist.move(panel, x.height, x.minimized)
    modules.game_sidebuttons.setButtonVisible("vipWidget", true)
  elseif x.type == 'miniMap' then
    widget = modules.game_minimap.move(panel, x.height, k)
  elseif x.type == 'healthInfo' then
    widget = modules.game_healthinfo.move(panel, k)
  elseif x.type == 'inventoryWindow' then
    widget = modules.game_inventory.move(panel, k, x.minimized)
  elseif x.type == 'mainButtons' then
    widget = modules.game_sidebuttons.move(panel, k, x.minimized)
  elseif x.type == 'partyList' then
    widget = modules.game_party_list.move(panel, x.height, x.minimized)
    modules.game_sidebuttons.setButtonVisible("partyWidget", true)
  elseif x.type == 'spellList' then
    widget = modules.game_spells.move(panel, x.height, x.minimized)
  end

  if not widget then
    return
  end

  if not panel:hasChild(widget) then
    return
  end

  panel:moveChildToIndex(widget, math.min(k, panel:getChildCount()))
end

function getSidePanelsCount()
  return getPersistentSidePanelCount(gameRightPanels) + getPersistentSidePanelCount(gameLeftPanels)
end

function createDarkBackgroundPanel()
  if not backgroundPanel then
    backgroundPanel = g_ui.createWidget('Panel', rootWidget)
    backgroundPanel:setId('blackBackground')
    backgroundPanel:setBackgroundColor('#000000')
    backgroundPanel:setOpacity(0.9)
    backgroundPanel:fill('parent')
  end
end

function removeDarkBackgroundPanel()
  if backgroundPanel then
    backgroundPanel:destroy()
  end
end
