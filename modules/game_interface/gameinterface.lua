interfaceSaved = false
gameRootPanel = nil
gameMapPanel = nil
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

local keybindStopAll = KeyBind:getKeyBind("Movement", "Stop All Actions")
local keybindLogout = KeyBind:getKeyBind("Misc.", "Logout")
local keybindClearOldMessage = KeyBind:getKeyBind("Misc.", "Clear oldest message from Game Window")

local widgetItem
local lastAction = 0
local npcTalkMaxDistance = 3

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
    modules.game_helper.helperConfig.currentLockedTargetId = 0
    g_game.cancelAttackAndFollow()
end

function bindKeys()
  keybindStopAll:active(gameRootPanel)
  keybindLogout:active(gameRootPanel)
  keybindClearOldMessage:active(gameRootPanel)
  g_keyboard.bindKeyDown('Ctrl+W', function() g_map.cleanTexts() modules.game_textmessage.clearMessages() end, gameRootPanel)
end

function terminate()
  hookedMenuOptions = {}
  markThing = nil

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
    if not limitedZoom or g_game.isGM() then
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
    panels[#panels+1] = panel
  end

  local count = gameLeftPanels:getChildCount()
  for i = 1, count do
    local panel = gameLeftPanels:getChildByIndex(i)
    panels[#panels+1] = panel
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
    panels[#panels+1] = {panel = panel, name = "right panel " .. (rightCount - i + 1), side = "right", index = i}
  end
  
  local leftCount = gameLeftPanels:getChildCount()
  for i = 1, leftCount do
    local panel = gameLeftPanels:getChildByIndex(i)
    panels[#panels+1] = {panel = panel, name = "left panel " .. i, side = "left", index = i}
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
    
    -- Determine target for left panel
    if panels:getChildCount() >= 2 then
      targetPanel = panels:getChildByIndex(-2)
    else
      if oppositePanels:getChildCount() > 0 then
        targetPanel = oppositePanels:getChildByIndex(1)
      end
    end
  else
    -- Right panel logic: remove first panel, check if more than 1 panel exists
    if panels:getChildCount() <= 1 then
      return
    end
    
    panel = panels:getChildByIndex(1)
    targetPanel = panels:getChildByIndex(2)
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
    g_settings.set("leftPanels", gameLeftPanels:getChildCount())
  else
    setRightHorizontalWidth()
    g_settings.set("rightPanels", gameRightPanels:getChildCount())
  end
  
  scheduleEvent(function() modules.game_actionbar.updateVisibleWidgets() end, 10)
end

function onMouseGrabberRelease(self, mousePosition, mouseButton)
  if mouseButton == MouseTouch then return end
  if selectedThing == nil then return false end
  if mouseButton == MouseLeftButton then
    local clickedWidget = gameRootPanel:recursiveGetChildByPos(mousePosition, false)
    if clickedWidget then
      if selectedType == 'use' then
        onUseWith(clickedWidget, mousePosition)
      elseif selectedType == 'trade' then
        onTradeWith(clickedWidget, mousePosition)
      end
    end
  end

  selectedThing = nil
  g_mouse.updateGrabber(self, 'target')
  g_mouse.popCursor('target')
  self:ungrabMouse()
  gameMapPanel:blockNextMouseRelease(true)
  return true
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
    end
    return
  end
  selectedType = 'use'
  selectedThing = thing
  selectedSubtype = subType or 0
  g_mouse.updateGrabber(mouseGrabberWidget, 'target')
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
  g_mouse.updateGrabber(mouseGrabberWidget, 'target')
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

    if g_game.getFeature(GameQuickLootFlags) or g_game.getFeature(GameTibia12Protocol) then
      if useThing:isCorpse() and not useThing:isPlayerCorpse() then
        menu:addOption(tr('Loot Corpse'), function() g_game.quickLoot(useThing:getPosition(), useThing:getId(), useThing:getStackPos(), true) end)
      elseif useThing:inCorpse() then
        menu:addOption(tr('Loot'), function() g_game.quickLoot(useThing:getPosition(), useThing:getId(), useThing:getStackPos(), false) end)
      end
    end

    if useThing:isWrapable() then
      menu:addOption(tr('Wrap'), function() g_game.wrap(useThing) end)
    elseif tile and tile:getTopWrapableThing() then
      menu:addOption(tr('Wrap'), function() g_game.wrap(tile:getTopWrapableThing()) end)
    end

    if useThing:isUnwrapable() then
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
            menu:addOption(tr('Attack'), function() modules.game_helper.helperConfig.currentLockedTargetId = creatureThing:getId(); g_game.attack(creatureThing) end, shortcut)
          else
            menu:addOption(tr('Stop Attack'), function() modules.game_helper.helperConfig.currentLockedTargetId = 0; g_game.cancelAttack() end, shortcut)
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

function processClassicControl(tile, menuPosition, mouseButton, autoWalkPos, lookThing, useThing, creatureThing, attackCreature, marking)
  local keyboardModifiers = g_keyboard.getModifiers()
  local config = m_settings.getOption("lootControl")
  local useLoot = (config == 1 and mouseButton == MouseRightButton and not g_keyboard.isShiftPressed() and not g_keyboard.isCtrlPressed()) or (config == 2 and mouseButton == MouseRightButton and g_keyboard.isShiftPressed()) or (config == 3 and mouseButton == MouseLeftButton and not g_keyboard.isShiftPressed() and not g_keyboard.isCtrlPressed())

  if useThing and useLoot and (g_game.getFeature(GameQuickLootFlags) or g_game.getFeature(GameTibia12Protocol)) then
    if creatureThing and not creatureThing:isPlayer() then
      goto next
    end

    if ((useThing:isCorpse() and not useThing:isPlayerCorpse()) or mouseButton == MouseLeftButton and useThing:inCorpse()) then
      g_game.quickLoot(useThing:getPosition(), useThing:getId(), useThing:getStackPos(true), true)
      return
    end
  end

  :: next ::

  if useThing and mouseButton == MouseRightButton and g_keyboard.isShiftPressed() then
    if useThing and useThing:isContainer() then
      g_game.open(useThing)
      return true
    end

    local thing = g_things.getThingType(useThing:getId())
    if creatureThing and not thing:hasAttribute(ThingAttrForceUse) and not creatureThing:getTile():hasDoor() then
      g_game.follow(creatureThing)
    elseif useThing then
      g_game.use(useThing)
    end
  end

  if useThing and keyboardModifiers == KeyboardNoModifier and mouseButton == MouseRightButton and not g_mouse.isPressed(MouseLeftButton) then
    local thing = g_things.getThingType(useThing:getId())
    if not creatureThing and thing:hasAttribute(ThingAttrForceUse) then
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

  if useThing and g_keyboard.isShiftPressed() and mouseButton == MouseRightButton and (g_game.getFeature(GameQuickLootFlags) or g_game.getFeature(GameTibia12Protocol)) then
    if creatureThing and not creatureThing:isPlayer() then
      goto next
    end

    if useThing:isCorpse() and not useThing:isPlayerCorpse() then
      g_game.quickLoot(useThing:getPosition(), useThing:getId(), useThing:getStackPos(true), true)
      return true
    end
  end

  :: next ::

  if keyboardModifiers == KeyboardNoModifier and mouseButton == MouseRightButton then
    createThingMenu(tile, menuPosition, lookThing, useThing, creatureThing)
    return true
  elseif lookThing and keyboardModifiers == KeyboardShiftModifier and mouseButton == MouseLeftButton then
    g_game.look(lookThing)
    return true
  elseif useThing and keyboardModifiers == KeyboardCtrlModifier and (mouseButton == MouseLeftButton or mouseButton == MouseRightButton) then
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

  if useThing and g_keyboard.isAltPressed() and mouseButton == MouseLeftButton and (g_game.getFeature(GameQuickLootFlags) or g_game.getFeature(GameTibia12Protocol)) then
    if creatureThing and not creatureThing:isPlayer() then
      goto next
    end

    if useThing:isCorpse() and not useThing:isPlayerCorpse() then
      g_game.quickLoot(useThing:getPosition(), useThing:getId(), useThing:getStackPos(true), true)
      return true
    end
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
      if useThing:isContainer() then
        if useThing:getParentContainer() then
          g_game.open(useThing, useThing:getParentContainer())
        else
          g_game.openContainer(useThing)
        end
      elseif useThing:isMultiUse() then
        startUseWith(useThing)
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

  local manualSort = modules.game_containers.useManualSort()
  local ctrlDragCheckBox = m_settings.getOption('ctrlDragCheckBox')
  if (ctrlDragCheckBox and g_keyboard.isCtrlPressed()) or item:getCount() == 1 then
    g_game.move(item, toPos, item:getCount(), manualSort)
    return
  elseif g_keyboard.isShiftPressed() then
    g_game.move(item, toPos, 1, manualSort)
    return
  elseif (not g_keyboard.isCtrlPressed() and not ctrlDragCheckBox ) or g_keyboard.isKeyPressed("Enter") then
    g_game.move(item, toPos, item:getCount(), manualSort)
    return
  end
  local count = item:getCount()

  countWindow = g_ui.createWidget('CountWindow', rootWidget)
  local itembox = countWindow.contentPanel:getChildById('item')
  local scrollbar = countWindow.contentPanel:getChildById('countScrollBar')
  g_client.setInputLockWidget(countWindow)
  itembox:setItemId(item:getId())
  itembox:setItemCount(count)
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
    g_game.move(item, toPos, itembox:getItemCount())
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
    itembox:setItemCount(value)
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
  if gameRightPanels:getChildCount() == 0 then
    addRightPanel()
  end
  return gameRightPanels:getChildByIndex(-1)
end

function getLeftPanel()
  if gameLeftPanels:getChildCount() >= 1 then
    return gameLeftPanels:getChildByIndex(-1)
  end
  return getRightPanel()
end

function getContainerPanel()
  local containerPanel = g_settings.getNumber("containerPanel")
  if containerPanel >= 5 then
    containerPanel = containerPanel - 4
    return gameRightPanels:getChildByIndex(math.min(containerPanel, gameRightPanels:getChildCount()))
  end
  if gameLeftPanels:getChildCount() == 0 then
    return getRightPanel()
  end
  return gameLeftPanels:getChildByIndex(math.min(containerPanel, gameLeftPanels:getChildCount()))
end

function addRightPanel()
  setRightHorizontalWidth()
  if gameRightPanels:getChildCount() >= 4 then
    return
  end
  local panel = g_ui.createWidget('GameSidePanel')
  panel:setId("rightPanel" .. (gameRightPanels:getChildCount() + 1))
  panel.onClick = toggleInternalFocus
  gameRightPanels:insertChild(1, panel)

  setRightHorizontalWidth()
  g_settings.set("rightPanels", gameRightPanels:getChildCount())
  scheduleEvent(function() modules.game_actionbar.updateVisibleWidgets() end, 10)
end

function addLeftPanel()
  setLeftHorizontalWidth()
  if gameLeftPanels:getChildCount() >= 4 then
    return
  end
  local panel = g_ui.createWidget('GameSidePanel')
  panel:setId("leftPanel" .. (gameLeftPanels:getChildCount() + 1))
  panel.onClick = toggleInternalFocus
  gameLeftPanels:addChild(panel)

  setLeftHorizontalWidth()
  g_settings.set("leftPanels", gameLeftPanels:getChildCount() + 1)
  scheduleEvent(function() modules.game_actionbar.updateVisibleWidgets() end, 10)
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

function updateTopBar(side)
  if side == "bottom" then
    gameTopBar:setParent(gameBottomActionPanel)
    gameMapPanel:addAnchor(AnchorLeft, 'gameLeftActionPanel', AnchorRight)
    gameMapPanel:addAnchor(AnchorRight, 'gameRightActionPanel', AnchorLeft)
    gameMapPanel:addAnchor(AnchorBottom, 'bottomSplitter', AnchorTop)
    gameMapPanel:addAnchor(AnchorTop, 'parent', AnchorTop)

    gameLeftActionPanel:addAnchor(AnchorTop, 'parent', AnchorTop)
    gameRightActionPanel:addAnchor(AnchorTop, 'parent', AnchorTop)
    gameLeftActionPanel:setPaddingTop(54)
    gameRightActionPanel:setPaddingTop(54)
  elseif side == "top" then
    gameTopBar:setParent(gameRootPanel)
    gameTopBar:addAnchor(AnchorTop, 'parent', AnchorTop)
    gameTopBar:addAnchor(AnchorLeft, 'gameBottomActionPanel', AnchorLeft)
    gameTopBar:addAnchor(AnchorRight, 'gameBottomActionPanel', AnchorRight)

    gameRootPanel:moveChildToIndex(gameTopBar, 1)
    gameMapPanel:addAnchor(AnchorLeft, 'gameLeftActionPanel', AnchorRight)
    gameMapPanel:addAnchor(AnchorRight, 'gameRightActionPanel', AnchorLeft)
    gameMapPanel:addAnchor(AnchorBottom, 'bottomSplitter', AnchorTop)
    gameMapPanel:addAnchor(AnchorTop, 'gameTopBar', AnchorBottom)

    gameLeftActionPanel:setPaddingTop(1)
    gameRightActionPanel:setPaddingTop(1)
    gameLeftActionPanel:addAnchor(AnchorTop, 'gameTopBar', AnchorBottom)
    gameRightActionPanel:addAnchor(AnchorTop, 'gameTopBar', AnchorBottom)

  elseif side == "left" or side == "right" then
    gameLeftActionPanel:addAnchor(AnchorTop, 'parent', AnchorTop)
    gameRightActionPanel:addAnchor(AnchorTop, 'parent', AnchorTop)
    gameLeftActionPanel:setPaddingTop(54)
    gameRightActionPanel:setPaddingTop(54)
    gameMapPanel:addAnchor(AnchorBottom, 'bottomSplitter', AnchorTop)
  end

  gameMapPanel:setMarginBottom(0)
end

function refreshViewMode()
  local classic = g_settings.getBoolean("classicView")-- and not g_app.isMobile()
  local rightPanels = g_settings.getNumber("rightPanels") - gameRightPanels:getChildCount()
  local leftPanels = g_settings.getNumber("leftPanels") - gameLeftPanels:getChildCount()

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
    gameMapPanel:addAnchor(AnchorTop, 'gameTopBar', AnchorBottom)
    gameMapPanel:setKeepAspectRatio(true)
    gameMapPanel:setLimitVisibleRange(false)
    gameMapPanel:setZoom(11)
    gameMapPanel:setOn(false) -- frame

    modules.client_topmenu.getTopMenu():setImageColor('white')

    if modules.game_console then
      modules.game_console.switchMode(false)
    end
  else
    gameMapPanel:fill('parent')
    gameMapPanel:setKeepAspectRatio(false)
    gameMapPanel:setLimitVisibleRange(false)
    gameMapPanel:setOn(true)
    if g_app.isMobile() then
      gameMapPanel:setZoom(15)
    else
      gameMapPanel:setZoom(15)
    end

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

  local classic = g_settings.getBoolean("classicView")
  local height = gameMapPanel:getHeight()
  local width = gameMapPanel:getWidth()

  if not classic then
    local rheight = gameRootPanel:getHeight()
    local rwidth = gameRootPanel:getWidth()

    local dimenstion = gameMapPanel:getVisibleDimension()
    local zoom = gameMapPanel:getZoom()
    local awareRange = g_map.getAwareRange()
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
  gameMapPanel:setMarginBottom(0)
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
      if thing then
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
        g_game.attack(child.creature)
        modules.game_helper.helperConfig.currentLockedTargetId = child.creature:getId()
      else
        modules.game_helper.helperConfig.currentLockedTargetId = 0
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
  if gameLeftPanels:getChildCount() < 1 and visible then
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
  horizontalLeftPanel:setWidth(gameLeftPanels:getChildCount() * 178)
  if horizontalLeftPanel:getWidth() == 0 then
    local children = horizontalLeftPanel:getChildren()
    for _, widget in pairs(children) do
      moveToOtherPanel(widget)
    end
  end
end

function setRightHorizontalWidth()
  horizontalRightPanel:setWidth(gameRightPanels:getChildCount() * 178)
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
    for i = 1, gameLeftPanels:getChildCount() do
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

  if gameLeftPanels:getChildCount() >= leftPanels then
    for i = 1, gameLeftPanels:getChildCount() do
      removeLeftPanel()
    end
  end

  g_settings.set("rightPanels", rightPanels)
  g_settings.set("leftPanels", leftPanels)

  refreshViewMode()

  addEvent(function()
    -- get RightPanels
    for i = 1, rightPanels do
      local panel = gameRightPanels:getChildByIndex(i)
      if panel then
        for _, widget in pairs(panel:getChildren()) do
          closeRestoredWidget(widget, primordial)
        end

        for k, x in ipairs(config.openWidgetsOrderPerSidebar[i]) do
          _moveChildren(panel, x, k)
        end
      end
    end

    -- get LeftPanels
    for i = 1, leftPanels do
      local panel = gameLeftPanels:getChildByIndex(i)
      if panel then
        for _, widget in pairs(panel:getChildren()) do
          closeRestoredWidget(widget, primordial)
        end

        for k, x in ipairs(config.openWidgetsOrderPerSidebar[i + rightPanels]) do
          _moveChildren(panel, x, k)
        end
      end
    end

    -- get Right Horizontal
    if config.openWidgetsHorizontalRight then
      for _, widget in pairs(horizontalRightPanel:getChildren()) do
        closeRestoredWidget(widget, primordial)
      end

      for k, x in ipairs(config.openWidgetsHorizontalRight) do
        if x.type == 'container' then
          modules.game_containers.move(x.instance, horizontalRightPanel, x.height, k)
        elseif x.type == 'analyticsSelector' then
          modules.game_analyser.moveAnalyser(horizontalRightPanel, x.height)
        elseif table.contains({'bossCooldowns', 'damageInputAnalyser', 'lootTracker','huntingSessionAnalyser', 'impactAnalyser', 'lootAnalyser', 'partyHuntAnalyser', 'wasteAnalyser', 'xpAnalyser', 'miscAnalyzer'}, x.type) then
          modules.game_analyser.moveChildAnalyser(x.type, horizontalRightPanel, x.height)
        elseif table.contains({'bestiaryTracker', 'bosstiaryTracker', 'imbuementTracker'}, x.type) then
          modules.game_trackers.moveTracker(x.type, horizontalRightPanel, x.height, k)
        elseif x.type == 'battleList' then
          modules.game_battle.moveBattle(x.instance, horizontalRightPanel, x.height, x.minimized)
        elseif x.type == 'prey' then
          modules.game_prey.move(horizontalRightPanel, x.height, k)
        elseif x.type == 'questTracker' then
          modules.game_questlog.move(horizontalRightPanel, x.height, k)
        elseif x.type == 'skills' then
          modules.game_skills.move(horizontalRightPanel, x.height, k)
        elseif x.type == 'unjustifiedPoints' then
          modules.game_unjustifiedpoints.move(horizontalRightPanel, x.height, k)
        elseif x.type == 'vip' then
          modules.game_viplist.move(horizontalRightPanel, x.height, k)
        elseif x.type == 'miniMap' then
          modules.game_minimap.move(horizontalRightPanel, x.height, k)
        elseif x.type == 'healthInfo' then
          modules.game_healthinfo.move(horizontalRightPanel, k)
        elseif x.type == 'inventoryWindow' then
          modules.game_inventory.move(horizontalRightPanel, k)
        elseif x.type == 'mainButtons' then
          modules.game_sidebuttons.move(horizontalRightPanel, k)
        elseif x.type == 'partyList' then
          modules.game_party_list.move(horizontalRightPanel, x.height, x.minimized)
        elseif x.type == 'spellList' then
          modules.game_spells.move(horizontalRightPanel, x.height)
        elseif x.type == 'helper' then
          modules.game_helper.move(horizontalRightPanel, x.height, k)
        end
      end
    end
    -- get Left Horizontal
    if config.openWidgetsHorizontalLeft then
      for _, widget in pairs(horizontalLeftPanel:getChildren()) do
        closeRestoredWidget(widget, primordial)
      end

      for k, x in ipairs(config.openWidgetsHorizontalLeft) do
        if x.type == 'container' then
           modules.game_containers.move(x.instance, horizontalLeftPanel, x.heigh, k)
        elseif x.type == 'analyticsSelector' then
          modules.game_analyser.moveAnalyser(horizontalLeftPanel, x.height)
        elseif table.contains({'bossCooldowns', 'damageInputAnalyser', 'lootTracker','huntingSessionAnalyser', 'impactAnalyser', 'lootAnalyser', 'partyHuntAnalyser', 'wasteAnalyser', 'xpAnalyser'}, x.type) then
          modules.game_analyser.moveChildAnalyser(x.type, horizontalLeftPanel, x.height)
        elseif table.contains({'bestiaryTracker', 'bosstiaryTracker', 'imbuementTracker'}, x.type) then
          modules.game_trackers.moveTracker(x.type, horizontalLeftPanel, x.height, k)
        elseif x.type == 'battleList' then
          modules.game_battle.moveBattle(x.instance, horizontalLeftPanel, x.height, x.minimized)
        elseif x.type == 'prey' then
          modules.game_prey.move(horizontalLeftPanel, x.height, k)
        elseif x.type == 'questTracker' then
          modules.game_questlog.move(horizontalLeftPanel, x.height, k)
        elseif x.type == 'skills' then
          modules.game_skills.move(horizontalLeftPanel, x.height, k)
        elseif x.type == 'unjustifiedPoints' then
          modules.game_unjustifiedpoints.move(horizontalLeftPanel, x.height, k)
        elseif x.type == 'vip' then
          modules.game_viplist.move(horizontalLeftPanel, x.height, k)
        elseif x.type == 'miniMap' then
          modules.game_minimap.move(horizontalLeftPanel, x.height, k)
        elseif x.type == 'healthInfo' then
          modules.game_healthinfo.move(horizontalLeftPanel, k)
        elseif x.type == 'inventoryWindow' then
          modules.game_inventory.move(horizontalLeftPanel, k)
        elseif x.type == 'mainButtons' then
          modules.game_sidebuttons.move(horizontalLeftPanel, k)
        elseif x.type == 'partyList' then
          modules.game_party_list.move(horizontalLeftPanel, x.height, x.minimized)
        elseif x.type == 'spellList' then
          modules.game_spells.move(horizontalLeftPanel, x.height)
        elseif x.type == 'helper' then
          modules.game_helper.move(horizontalLeftPanel, x.height, k)
        end
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
    leftSidebarCount = gameLeftPanels:getChildCount(),
    openWidgetsOrderPerSidebar = {},
    openWidgetsHorizontalRight = {},
    openWidgetsHorizontalLeft = {},
  }

  local count = gameRightPanels:getChildCount()
  for i = 1, count do
    config.openWidgetsOrderPerSidebar[#config.openWidgetsOrderPerSidebar + 1] = {}
    for z, a in pairs(gameRightPanels:getChildByIndex(i):getChildren()) do
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

  for i = 1, config.leftSidebarCount do
    config.openWidgetsOrderPerSidebar[#config.openWidgetsOrderPerSidebar + 1] = {}
    for z, a in pairs(gameLeftPanels:getChildByIndex(i):getChildren()) do
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
function _moveChildren(panel, x, k)
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
  elseif x.type == 'helper' then
    widget = modules.game_helper.move(panel, x.height, k, x.minimized, x.locked)
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
  return gameRightPanels:getChildCount() + gameLeftPanels:getChildCount()
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
