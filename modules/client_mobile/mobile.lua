-- Clean-room Mobile Lite overlay, multitouch controls, HUD toggles and performance settings.
local overlay
local keypad
local rightControls
local mobileHudBar
local mobileLoginSettingsBtn
local settingsDrawer
local touchStart = 0
local touchOrigin = { x = 0, y = 0 }
local updateCursorEvent
local initScaleEvent
local zoomInButton
local zoomOutButton
local keypadButton
local keypadEvent
local keypadActive = false
local keypadTouchButton = nil
local keypadMousePos = { x = 0.5, y = 0.5 }
local keypadTicks = 0
local controlsVisible = true
local controlScale = 1.0
local joystickSide = 'left'
local manualUiScale = false
local drawLightsEnabled = true
local floorFadingEnabled = true
local actionMode = nil -- nil | 'use' | 'look'

local DEADZONE = 0.16
local LONG_PRESS_MS = 450

local function clamp(value, minVal, maxVal)
  if value < minVal then return minVal end
  if value > maxVal then return maxVal end
  return value
end

local function computeAutoScale()
  local size = g_window.getSize()
  if not size or size.width <= 0 or size.height <= 0 then
    return 1.0
  end
  -- Target crisp readability and generous touch targets in landscape (~700x360 logical UI units).
  local ratioW = size.width / 700.0
  local ratioH = size.height / 360.0
  local autoScale = math.min(ratioW, ratioH)
  -- Snap to 0.25 increments in [1.0, 2.5] for crisp bitmap font rendering.
  autoScale = clamp(math.floor(autoScale * 4 + 0.5) / 4, 1.0, 2.5)
  return autoScale
end

local function applyResponsiveScale()
  if manualUiScale then return end
  g_app.scale(computeAutoScale())
end

local function getMapPanel()
  if modules.game_interface and modules.game_interface.getMapPanel then
    return modules.game_interface.getMapPanel()
  end
  return nil
end

local function applyControlScale()
  if not keypad or not rightControls then return end
  local s = clamp(controlScale, 0.75, 1.5)
  local padSize = math.floor(156 * s)
  local knobSize = math.floor(46 * s)
  keypad:setSize({ width = padSize, height = padSize })
  keypad:setImageRect({ x = 3, y = 3, width = padSize - 6, height = padSize - 6 })
  if keypad.pointer then
    keypad.pointer:setSize({ width = knobSize, height = knobSize })
  end

  local actionW = math.floor(168 * s)
  local actionH = math.floor(112 * s)
  local rightW = math.floor(214 * s)
  local rightH = math.floor(166 * s)
  rightControls:setSize({ width = rightW, height = rightH })

  local actionCluster = rightControls:recursiveGetChildById('actionCluster')
  if actionCluster then
    actionCluster:setSize({ width = actionW, height = actionH })
    local btnAttack = actionCluster:getChildById('btnAttack')
    local btnUse = actionCluster:getChildById('btnUse')
    local btnFollow = actionCluster:getChildById('btnFollow')
    local btnLook = actionCluster:getChildById('btnLook')
    local btnStop = actionCluster:getChildById('btnStop')
    if btnAttack then btnAttack:setSize({ width = math.floor(56 * s), height = math.floor(56 * s) }) end
    if btnUse then btnUse:setSize({ width = math.floor(50 * s), height = math.floor(50 * s) }) end
    if btnFollow then btnFollow:setSize({ width = math.floor(50 * s), height = math.floor(50 * s) }) end
    if btnLook then btnLook:setSize({ width = math.floor(50 * s), height = math.floor(50 * s) }) end
    if btnStop then btnStop:setSize({ width = math.floor(44 * s), height = math.floor(44 * s) }) end
  end

  local hotkeyPad = rightControls:recursiveGetChildById('hotkeyPad')
  if hotkeyPad then
    hotkeyPad:setSize({ width = math.floor(210 * s), height = math.floor(44 * s) })
    for i = 1, 6 do
      local slot = hotkeyPad:getChildById('hkF' .. i)
      if slot then
        slot:setSize({ width = math.floor(32 * s), height = math.floor(40 * s) })
      end
    end
  end
end

local function applyJoystickSide()
  if not keypad or not rightControls then return end
  keypad:breakAnchors()
  rightControls:breakAnchors()
  if joystickSide == 'right' then
    keypad:addAnchor(AnchorBottom, 'parent', AnchorBottom)
    keypad:addAnchor(AnchorRight, 'parent', AnchorRight)
    keypad:setMarginRight(16)
    keypad:setMarginBottom(16)
    keypad:setMarginLeft(0)

    rightControls:addAnchor(AnchorBottom, 'parent', AnchorBottom)
    rightControls:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    rightControls:setMarginLeft(14)
    rightControls:setMarginBottom(14)
    rightControls:setMarginRight(0)
  else
    keypad:addAnchor(AnchorBottom, 'parent', AnchorBottom)
    keypad:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    keypad:setMarginLeft(16)
    keypad:setMarginBottom(16)
    keypad:setMarginRight(0)

    rightControls:addAnchor(AnchorBottom, 'parent', AnchorBottom)
    rightControls:addAnchor(AnchorRight, 'parent', AnchorRight)
    rightControls:setMarginRight(14)
    rightControls:setMarginBottom(14)
    rightControls:setMarginLeft(0)
  end
end

local function syncSettingsHighlights()
  if not settingsDrawer then return end
  local function setChecked(id, state)
    local w = settingsDrawer:recursiveGetChildById(id)
    if w then w:setChecked(state) end
  end
  setChecked('cfgScaleSm', math.abs(controlScale - 0.8) < 0.05)
  setChecked('cfgScaleMd', math.abs(controlScale - 1.0) < 0.05)
  setChecked('cfgScaleLg', math.abs(controlScale - 1.25) < 0.05)
  setChecked('cfgScaleXl', math.abs(controlScale - 1.5) < 0.05)
  setChecked('cfgStickLeft', joystickSide == 'left')
  setChecked('cfgStickRight', joystickSide == 'right')

  local fps = g_app.getMaxFps and g_app.getMaxFps() or 45
  setChecked('cfgFps30', fps <= 30)
  setChecked('cfgFps45', fps > 30 and fps <= 45)
  setChecked('cfgFps60', fps > 45)

  local dpr = g_window.getMaxPixelRatio and g_window.getMaxPixelRatio() or 1.75
  setChecked('cfgDpr10', dpr > 0 and dpr <= 1.1)
  setChecked('cfgDpr15', dpr > 1.1 and dpr <= 1.6)
  setChecked('cfgDpr175', dpr > 1.6 and dpr <= 1.85)
  setChecked('cfgDpr20', dpr > 1.85 or dpr == 0)

  local lightsBtn = settingsDrawer:recursiveGetChildById('cfgLights')
  if lightsBtn then
    lightsBtn:setText('Lights: ' .. (drawLightsEnabled and 'On' or 'Off'))
    lightsBtn:setChecked(drawLightsEnabled)
  end
  local fadeBtn = settingsDrawer:recursiveGetChildById('cfgFloorFade')
  if fadeBtn then
    fadeBtn:setText('Fade: ' .. (floorFadingEnabled and 'On' or 'Off'))
    fadeBtn:setChecked(floorFadingEnabled)
  end
end

local function updateActionButtons()
  if not rightControls then return end
  local btnUse = rightControls:recursiveGetChildById('btnUse')
  local btnLook = rightControls:recursiveGetChildById('btnLook')
  if btnUse then btnUse:setChecked(actionMode == 'use') end
  if btnLook then btnLook:setChecked(actionMode == 'look') end
end

local function applyMobileGraphicsOptions()
  local mapPanel = getMapPanel()
  if not mapPanel then return end
  if mapPanel.setDrawLights then
    mapPanel:setDrawLights(drawLightsEnabled)
  end
  if mapPanel.setFloorFading then
    mapPanel:setFloorFading(floorFadingEnabled and 500 or 0)
  end
end

local function updateOnlineVisibility()
  if not overlay then return end
  local isOnline = g_game.isOnline()
  if mobileLoginSettingsBtn then mobileLoginSettingsBtn:setVisible(not isOnline) end
  if mobileHudBar then mobileHudBar:setVisible(isOnline) end
  if keypad then keypad:setVisible(isOnline and controlsVisible) end
  if rightControls then rightControls:setVisible(isOnline and controlsVisible) end
  if mobileHudBar then
    local padBtn = mobileHudBar:getChildById('hudTogglePad')
    if padBtn then padBtn:setChecked(controlsVisible) end
  end
end

local function attackNearestOrCycle()
  if not g_game.isOnline() then return end
  if modules.game_battle and modules.game_battle.getAttackableCreatures then
    local list = modules.game_battle.getAttackableCreatures()
    if list and #list > 0 then
      local current = g_game.getAttackingCreature()
      local nextTarget = list[1]
      for i = 1, #list do
        if list[i] == current then
          nextTarget = list[(i % #list) + 1]
          break
        end
      end
      if nextTarget then
        g_game.attack(nextTarget)
        return
      end
    end
  end
  if modules.game_battle and modules.game_battle.chooseNextCreature then
    modules.game_battle.chooseNextCreature()
  end
end

local function toggleFollowOrChase()
  if not g_game.isOnline() then return end
  local target = g_game.getAttackingCreature()
  if target then
    if g_game.getFollowingCreature() == target then
      g_game.cancelFollow()
    else
      g_game.follow(target)
    end
    return
  end
  if modules.game_hotkeys and modules.game_hotkeys.toggleChaseMode then
    modules.game_hotkeys.toggleChaseMode()
  elseif g_game.getChaseMode and g_game.setChaseMode then
    local mode = g_game.getChaseMode()
    g_game.setChaseMode(mode == ChaseOpponent and DontChase or ChaseOpponent)
  end
end

local function triggerTouchActionOnTile(pos)
  local mapPanel = getMapPanel()
  if not mapPanel then return false end
  local tile = mapPanel:getTile(pos)
  if not tile then return false end
  if actionMode == 'look' then
    local thing = tile:getTopLookThing()
    if thing then g_game.look(thing) end
    actionMode = nil
    updateActionButtons()
    return true
  elseif actionMode == 'use' then
    local thing = tile:getTopUseThing()
    if thing then g_game.use(thing) end
    actionMode = nil
    updateActionButtons()
    return true
  end
  return false
end

local function focusMobileChat()
  local consoleMod = modules.game_console
  if consoleMod then
    if consoleMod.isChatEnabled and not consoleMod.isChatEnabled() and consoleMod.enableChat then
      consoleMod.enableChat(true)
    end
    local edit = nil
    if consoleMod.getConsole then
      local consoleObj = consoleMod.getConsole()
      if consoleObj then
        if consoleObj.consoleTextEdit then
          edit = consoleObj.consoleTextEdit
        elseif consoleObj.panel and consoleObj.panel.recursiveGetChildById then
          edit = consoleObj.panel:recursiveGetChildById('consoleTextEdit')
        elseif consoleObj.recursiveGetChildById then
          edit = consoleObj:recursiveGetChildById('consoleTextEdit')
        end
      end
    end
    if not edit and consoleMod.getConsoleTextEdit then
      edit = consoleMod.getConsoleTextEdit()
    end
    if not edit then
      local root = g_ui.getRootWidget()
      if root then edit = root:recursiveGetChildById('consoleTextEdit') end
    end
    if edit then
      edit:recursiveFocus(MouseFocusReason)
      if g_window.showTextEditor then
        g_window.showTextEditor('Chat', '', edit:getText() or '', 0)
      end
      return
    end
  end
  if g_window.showTextEditor then
    g_window.showTextEditor('Chat', '', '', 0)
  end
end

local function toggleSettingsDrawer()
  if not settingsDrawer then return end
  local show = not settingsDrawer:isVisible()
  settingsDrawer:setVisible(show)
  if show then
    settingsDrawer:raise()
    syncSettingsHighlights()
  end
end

local function wireOverlayButtons()
  if mobileHudBar then
    local function bindHud(id, fn)
      local btn = mobileHudBar:getChildById(id)
      if btn then btn.onClick = fn end
    end
    bindHud('hudInventory', function()
      if modules.game_inventory and modules.game_inventory.toggle then modules.game_inventory.toggle() end
    end)
    bindHud('hudBattle', function()
      if modules.game_battle and modules.game_battle.toggle then modules.game_battle.toggle() end
    end)
    bindHud('hudVip', function()
      if modules.game_viplist and modules.game_viplist.toggle then modules.game_viplist.toggle() end
    end)
    bindHud('hudSkills', function()
      if modules.game_skills and modules.game_skills.toggle then modules.game_skills.toggle() end
    end)
    bindHud('hudMinimap', function()
      if modules.game_minimap and modules.game_minimap.toggle then modules.game_minimap.toggle() end
    end)
    bindHud('hudChat', focusMobileChat)
    bindHud('hudHotkeys', function()
      if modules.game_hotkeys and modules.game_hotkeys.toggle then modules.game_hotkeys.toggle() end
    end)
    bindHud('hudTogglePad', function()
      controlsVisible = not controlsVisible
      g_settings.set('mobileControlsVisible', controlsVisible)
      if keypadButton then keypadButton:setChecked(controlsVisible) end
      updateOnlineVisibility()
    end)
    bindHud('hudSettings', toggleSettingsDrawer)
  end
  if mobileLoginSettingsBtn then
    mobileLoginSettingsBtn.onClick = toggleSettingsDrawer
  end

  if rightControls then
    local function bindAction(id, fn)
      local btn = rightControls:recursiveGetChildById(id)
      if btn then btn.onClick = fn end
    end
    bindAction('btnAttack', attackNearestOrCycle)
    bindAction('btnFollow', toggleFollowOrChase)
    bindAction('btnUse', function()
      if actionMode == 'use' then
        actionMode = nil
      else
        actionMode = 'use'
      end
      updateActionButtons()
    end)
    bindAction('btnLook', function()
      local target = g_game.getAttackingCreature()
      if target and actionMode ~= 'look' then
        g_game.look(target)
        return
      end
      if actionMode == 'look' then
        actionMode = nil
      else
        actionMode = 'look'
      end
      updateActionButtons()
    end)
    bindAction('btnStop', function()
      actionMode = nil
      updateActionButtons()
      g_game.cancelAttackAndFollow()
    end)

    for i = 1, 6 do
      local combo = 'F' .. i
      bindAction('hk' .. combo, function()
        if modules.game_hotkeys and modules.game_hotkeys.doKeyCombo then
          modules.game_hotkeys.doKeyCombo(combo)
        end
      end)
    end
  end

  if settingsDrawer then
    local function bindCfg(id, fn)
      local btn = settingsDrawer:recursiveGetChildById(id)
      if btn then btn.onClick = fn end
    end
    local function setScale(val)
      controlScale = val
      g_settings.set('mobileControlScale', val)
      applyControlScale()
      syncSettingsHighlights()
    end
    bindCfg('cfgScaleSm', function() setScale(0.8) end)
    bindCfg('cfgScaleMd', function() setScale(1.0) end)
    bindCfg('cfgScaleLg', function() setScale(1.25) end)
    bindCfg('cfgScaleXl', function() setScale(1.5) end)

    bindCfg('cfgUiDown', function() manualUiScale = true; g_app.scaleDown() end)
    bindCfg('cfgUiAuto', function() manualUiScale = false; applyResponsiveScale() end)
    bindCfg('cfgUiUp', function() manualUiScale = true; g_app.scaleUp() end)

    bindCfg('cfgStickLeft', function()
      joystickSide = 'left'
      g_settings.set('mobileJoystickSide', joystickSide)
      applyJoystickSide()
      syncSettingsHighlights()
    end)
    bindCfg('cfgStickRight', function()
      joystickSide = 'right'
      g_settings.set('mobileJoystickSide', joystickSide)
      applyJoystickSide()
      syncSettingsHighlights()
    end)

    local function setFps(val)
      if g_app.setMaxFps then g_app.setMaxFps(val) end
      g_settings.set('mobileMaxFps', val)
      syncSettingsHighlights()
    end
    bindCfg('cfgFps30', function() setFps(30) end)
    bindCfg('cfgFps45', function() setFps(45) end)
    bindCfg('cfgFps60', function() setFps(60) end)

    local function setDpr(val)
      if g_window.setMaxPixelRatio then g_window.setMaxPixelRatio(val) end
      g_settings.set('mobileMaxDpr', val)
      syncSettingsHighlights()
    end
    bindCfg('cfgDpr10', function() setDpr(1.0) end)
    bindCfg('cfgDpr15', function() setDpr(1.5) end)
    bindCfg('cfgDpr175', function() setDpr(1.75) end)
    bindCfg('cfgDpr20', function() setDpr(2.0) end)

    bindCfg('cfgLights', function()
      drawLightsEnabled = not drawLightsEnabled
      g_settings.set('mobileDrawLights', drawLightsEnabled)
      applyMobileGraphicsOptions()
      syncSettingsHighlights()
    end)
    bindCfg('cfgFloorFade', function()
      floorFadingEnabled = not floorFadingEnabled
      g_settings.set('mobileFloorFading', floorFadingEnabled)
      applyMobileGraphicsOptions()
      syncSettingsHighlights()
    end)
    bindCfg('cfgWebFull', function()
      if g_window.requestWebFullscreen then g_window.requestWebFullscreen() end
    end)
    bindCfg('cfgWebDiag', function()
      if g_window.toggleWebDiagnostics then g_window.toggleWebDiagnostics() end
    end)
    bindCfg('cfgWebDesktop', function()
      if g_window.openWebProfile then g_window.openWebProfile('desktop') end
    end)
    bindCfg('cfgTrimCache', function()
      if g_textures and g_textures.trimCache then
        g_textures.trimCache(0)
      end
    end)
    bindCfg('cfgCloseDrawer', function()
      settingsDrawer:setVisible(false)
    end)
  end
end

local function onWindowResize()
  applyResponsiveScale()
end

-- public functions
function init()
  if not g_app.isMobile() then return end

  controlScale = clamp(tonumber(g_settings.getNumber('mobileControlScale', 1.0)) or 1.0, 0.75, 1.5)
  local savedSide = g_settings.getString('mobileJoystickSide', 'left')
  joystickSide = (savedSide == 'right') and 'right' or 'left'
  controlsVisible = g_settings.getBoolean('mobileControlsVisible', true)
  drawLightsEnabled = g_settings.getBoolean('mobileDrawLights', true)
  floorFadingEnabled = g_settings.getBoolean('mobileFloorFading', true)

  local savedFps = tonumber(g_settings.getNumber('mobileMaxFps', 45)) or 45
  if g_app.setMaxFps then g_app.setMaxFps(clamp(savedFps, 20, 60)) end
  local savedDpr = tonumber(g_settings.getNumber('mobileMaxDpr', 1.75)) or 1.75
  if g_window.setMaxPixelRatio then g_window.setMaxPixelRatio(clamp(savedDpr, 1.0, 2.0)) end

  overlay = g_ui.displayUI('mobile')
  if not overlay then return end
  keypad = overlay:getChildById('keypad')
  rightControls = overlay:getChildById('rightControls')
  mobileHudBar = overlay:getChildById('mobileHudBar')
  mobileLoginSettingsBtn = overlay:getChildById('mobileLoginSettingsBtn')
  settingsDrawer = overlay:getChildById('mobileSettingsDrawer')
  overlay:raise()

  applyControlScale()
  applyJoystickSide()
  wireOverlayButtons()
  syncSettingsHighlights()
  updateActionButtons()

  if modules.client_topmenu then
    zoomInButton = modules.client_topmenu.addLeftButton('zoomInButton', 'Zoom In', '/images/topbuttons/zoomin', function()
      manualUiScale = true
      g_app.scaleUp()
    end)
    zoomOutButton = modules.client_topmenu.addLeftButton('zoomOutButton', 'Zoom Out', '/images/topbuttons/zoomout', function()
      manualUiScale = true
      g_app.scaleDown()
    end)
    keypadButton = modules.client_topmenu.addLeftGameToggleButton('keypadButton', 'Touch Controls', '/images/topbuttons/keypad', function()
      controlsVisible = not controlsVisible
      keypadButton:setChecked(controlsVisible)
      g_settings.set('mobileControlsVisible', controlsVisible)
      updateOnlineVisibility()
    end)
    if keypadButton then keypadButton:setChecked(controlsVisible) end
  end

  initScaleEvent = scheduleEvent(function()
    applyResponsiveScale()
  end, 10)

  connect(g_ui, {
    onMousePress = onGlobalMousePress,
    onMouseMove = onGlobalMouseMove,
    onMouseRelease = onGlobalMouseRelease
  })
  if keypad then
    connect(keypad, {
      onTouchPress = onKeypadTouchPress,
      onTouchRelease = onKeypadTouchRelease,
      onMousePress = onKeypadTouchPress,
      onMouseRelease = onKeypadTouchRelease,
      onMouseMove = onKeypadTouchMove
    })
  end
  connect(g_game, {
    onGameStart = online,
    onGameEnd = offline
  })
  local root = g_ui.getRootWidget()
  if root then
    connect(root, {
      onGeometryChange = onWindowResize
    })
  end
  if g_game.isOnline() then
    online()
  end
end

function terminate()
  if not g_app.isMobile() or not overlay then return end
  removeEvent(updateCursorEvent)
  updateCursorEvent = nil
  removeEvent(keypadEvent)
  keypadEvent = nil
  removeEvent(initScaleEvent)
  initScaleEvent = nil
  keypadActive = false

  disconnect(g_ui, {
    onMousePress = onGlobalMousePress,
    onMouseMove = onGlobalMouseMove,
    onMouseRelease = onGlobalMouseRelease
  })
  if keypad then
    disconnect(keypad, {
      onTouchPress = onKeypadTouchPress,
      onTouchRelease = onKeypadTouchRelease,
      onMousePress = onKeypadTouchPress,
      onMouseRelease = onKeypadTouchRelease,
      onMouseMove = onKeypadTouchMove
    })
  end
  disconnect(g_game, {
    onGameStart = online,
    onGameEnd = offline
  })
  local root = g_ui.getRootWidget()
  if root then
    disconnect(root, {
      onGeometryChange = onWindowResize
    })
  end
  if zoomInButton then zoomInButton:destroy(); zoomInButton = nil end
  if zoomOutButton then zoomOutButton:destroy(); zoomOutButton = nil end
  if keypadButton then keypadButton:destroy(); keypadButton = nil end
  overlay:destroy()
  overlay = nil
  keypad = nil
  rightControls = nil
  mobileHudBar = nil
  mobileLoginSettingsBtn = nil
  settingsDrawer = nil
end

function hide()
  if not overlay then return end
  overlay:hide()
end

function show()
  if not overlay then return end
  overlay:show()
end

function online()
  applyMobileGraphicsOptions()
  updateOnlineVisibility()
  if overlay then overlay:raise() end
end

function offline()
  keypadActive = false
  actionMode = nil
  removeEvent(keypadEvent)
  keypadEvent = nil
  if keypad and keypad.pointer then
    keypad.pointer:setMarginTop(0)
    keypad.pointer:setMarginLeft(0)
  end
  updateActionButtons()
  updateOnlineVisibility()
end

function onGlobalMousePress(pos, button)
  if not overlay then return end
  if button == MouseTouch then
    if actionMode and not (keypad and keypad:isVisible() and keypad:containsPoint(pos))
       and not (rightControls and rightControls:isVisible() and rightControls:containsPoint(pos))
       and not (mobileHudBar and mobileHudBar:isVisible() and mobileHudBar:containsPoint(pos)) then
      if triggerTouchActionOnTile(pos) and g_window.consumeTouchGesture then
        g_window.consumeTouchGesture()
      end
      return
    end
    if keypad and keypad:isVisible() and keypad:containsPoint(pos) then
      if overlay.cursor then overlay.cursor:hide() end
      removeEvent(updateCursorEvent)
      return
    end
    touchOrigin.x = pos.x
    touchOrigin.y = pos.y
    touchStart = g_clock.millis()
    local cursor = overlay.cursor
    if cursor then
      cursor:show()
      cursor:setX(pos.x - 28)
      cursor:setY(pos.y - 28)
      cursor:setPercent(100)
    end
    updateCursor()
  else
    if overlay.cursor then overlay.cursor:hide() end
    removeEvent(updateCursorEvent)
  end
end

function onGlobalMouseMove(pos, moved)
  if not overlay then return end
  if keypadActive and keypad then
    updateKeypadMousePos(keypad, pos)
  end
  if overlay.cursor and overlay.cursor:isVisible() then
    if math.abs(pos.x - touchOrigin.x) > 8 or math.abs(pos.y - touchOrigin.y) > 8 then
      overlay.cursor:hide()
      removeEvent(updateCursorEvent)
    end
  end
end

function onGlobalMouseRelease(pos, button)
  if not overlay then return end
  if button == MouseTouch or button == MouseLeftButton or button == keypadTouchButton then
    if overlay.cursor then overlay.cursor:hide() end
    removeEvent(updateCursorEvent)
    if keypadActive and (button == keypadTouchButton or (not keypadTouchButton and not g_mouse.isPressed(MouseTouch))) then
      stopKeypadWalk()
    end
  end
end

function updateCursor()
  removeEvent(updateCursorEvent)
  if not g_mouse.isPressed(MouseTouch) then return end
  if not overlay or not overlay.cursor or not overlay.cursor:isVisible() then return end
  local elapsed = g_clock.millis() - touchStart
  local percent = 100 - clamp(elapsed * 100 / LONG_PRESS_MS, 0, 100)
  overlay.cursor:setPercent(percent)
  if percent > 0 then
    overlay.cursor:setOpacity(0.45)
    updateCursorEvent = scheduleEvent(updateCursor, 25)
  else
    overlay.cursor:setOpacity(0.85)
  end
end

function updateKeypadMousePos(widget, pos)
  local w = math.max(1, widget:getWidth())
  local h = math.max(1, widget:getHeight())
  keypadMousePos.x = (pos.x - widget:getPosition().x) / w
  keypadMousePos.y = (pos.y - widget:getPosition().y) / h
end

function stopKeypadWalk()
  keypadActive = false
  keypadTouchButton = nil
  removeEvent(keypadEvent)
  keypadEvent = nil
  if keypad and keypad.pointer then
    keypad.pointer:setMarginTop(0)
    keypad.pointer:setMarginLeft(0)
  end
end

function onKeypadTouchMove(widget, pos, offset)
  if not keypadActive then return false end
  updateKeypadMousePos(widget, pos)
  return true
end

function onKeypadTouchPress(widget, pos, button)
  if button ~= MouseTouch and button ~= MouseTouch2 and button ~= MouseTouch3 and button ~= MouseLeftButton then
    return false
  end
  if keypadActive and keypadTouchButton and keypadTouchButton ~= button then
    return false
  end
  keypadActive = true
  keypadTouchButton = button
  keypadTicks = 0
  updateKeypadMousePos(widget, pos)
  if button == MouseTouch and g_window.consumeTouchGesture then
    g_window.consumeTouchGesture()
  end
  executeWalk()
  return true
end

function onKeypadTouchRelease(widget, pos, button)
  if keypadTouchButton and button ~= keypadTouchButton then
    return false
  end
  if button ~= MouseTouch and button ~= MouseTouch2 and button ~= MouseTouch3 and button ~= MouseLeftButton then
    return false
  end
  stopKeypadWalk()
  return true
end

local function directionFromVector(dx, dy)
  local mag = math.sqrt(dx * dx + dy * dy)
  if mag < DEADZONE then
    return nil
  end
  -- 8-way compass sector calculation (22.5 deg half-sectors around each cardinal/diagonal)
  local deg = math.deg(math.atan2(dy, dx)) -- 0 = East, 90 = South, -90 = North, +-180 = West
  if deg >= -22.5 and deg < 22.5 then
    return Directions.East
  elseif deg >= 22.5 and deg < 67.5 then
    return Directions.SouthEast
  elseif deg >= 67.5 and deg < 112.5 then
    return Directions.South
  elseif deg >= 112.5 and deg < 157.5 then
    return Directions.SouthWest
  elseif deg >= 157.5 or deg < -157.5 then
    return Directions.West
  elseif deg >= -157.5 and deg < -112.5 then
    return Directions.NorthWest
  elseif deg >= -112.5 and deg < -67.5 then
    return Directions.North
  else
    return Directions.NorthEast
  end
end

function executeWalk()
  if not keypad or not keypad.pointer then return end
  removeEvent(keypadEvent)
  keypadEvent = nil
  if not keypadActive or not modules.game_walking then
    stopKeypadWalk()
    return
  end
  local activeBtn = keypadTouchButton or MouseTouch
  if not g_mouse.isPressed(activeBtn) and not g_mouse.isPressed(MouseLeftButton) then
    stopKeypadWalk()
    return
  end

  keypadEvent = scheduleEvent(executeWalk, 35)
  local dx = clamp((keypadMousePos.x - 0.5) * 2.0, -1.0, 1.0)
  local dy = clamp((keypadMousePos.y - 0.5) * 2.0, -1.0, 1.0)
  local mag = math.sqrt(dx * dx + dy * dy)
  local maxRadius = math.floor(keypad:getWidth() * 0.34)
  if mag > 1.0 then
    dx = dx / mag
    dy = dy / mag
  end
  keypad.pointer:setMarginLeft(math.floor(dx * maxRadius))
  keypad.pointer:setMarginTop(math.floor(dy * maxRadius))

  local dir = directionFromVector(dx, dy)
  if dir then
    modules.game_walking.walk(dir, keypadTicks)
    if keypadTicks == 0 then
      keypadTicks = 100
    end
  end
end
