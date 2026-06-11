smartWalkDirs = {}
smartWalkDir = nil
wsadWalking = false
nextWalkDir = nil
lastWalkDir = nil
lastFinishedStep = 0
autoWalkEvent = nil
firstStep = true
walkLock = 0
walkEvent = nil
lastWalk = 0
lastTurn = 0
lastTurnDirection = 0
lastStop = 0
lastManualWalk = 0
autoFinishNextServerWalk = 0
turnKeys = {}
walkTeleportDelay = 0
walkStairsDelay = 0
walkFirstStepDelay = 50
walkTurnDelay = 0
walkCtrlTurnDelay = 0

local data = {
  ["ctrlCheckBox"] = {"Ctrl"},
  ["shiftCheckBox"] = {"Shift"},
  ["altCheckBox"] = {"Alt", "Ctrl+Alt"}
}

local function migrateClassicWalkDefaults()
  if g_settings.getBoolean("astraClassicWalkDefaultsV1") then
    return
  end

  if g_settings.getNumber("walkTeleportDelay") == 200 then
    g_settings.set("walkTeleportDelay", 0)
  end

  if g_settings.getNumber("walkFirstStepDelay") == 200 then
    g_settings.set("walkFirstStepDelay", 50)
  end

  g_settings.set("astraClassicWalkDefaultsV1", true)
end

local function migrateDirectTurnWalk()
  if g_settings.getBoolean("astraDirectTurnWalkV1") then
    return
  end

  if g_settings.getNumber("walkTurnDelay") == 100 then
    g_settings.set("walkTurnDelay", 0)
  end

  g_settings.set("astraDirectTurnWalkV1", true)
end

local function migrateDirectWalkDefaults()
  if g_settings.getBoolean("astraDirectWalkDefaultsV2") then
    return
  end

  if g_settings.getBoolean("hotkeyDelayNative") then
    g_settings.set("hotkeyDelayNative", false)
  end

  if table.contains({80, 120, 200, 250}, g_settings.getNumber("hotkeyDelay")) then
    g_settings.set("hotkeyDelay", 5)
  end

  if table.contains({50, 100, 200}, g_settings.getNumber("walkTeleportDelay")) then
    g_settings.set("walkTeleportDelay", 0)
  end

  if table.contains({50, 100, 200}, g_settings.getNumber("walkStairsDelay")) then
    g_settings.set("walkStairsDelay", 0)
  end

  if table.contains({100, 200}, g_settings.getNumber("walkFirstStepDelay")) then
    g_settings.set("walkFirstStepDelay", 50)
  end

  if table.contains({10, 100}, g_settings.getNumber("walkTurnDelay")) then
    g_settings.set("walkTurnDelay", 0)
  end

  if table.contains({10, 150, 200}, g_settings.getNumber("walkCtrlTurnDelay")) then
    g_settings.set("walkCtrlTurnDelay", 0)
  end

  if not g_settings.getBoolean("dash") then
    g_settings.set("dash", true)
  end

  if not g_settings.getBoolean("smartWalk") then
    g_settings.set("smartWalk", true)
  end

  g_settings.set("astraDirectWalkDefaultsV2", true)
end

local function applyDirectWalkRuntimeOptions()
  local gameRootPanel = rootWidget and rootWidget:getChildById("gameRootPanel")
  if gameRootPanel then
    local delay = g_settings.getBoolean("hotkeyDelayNative") and 250 or math.max(0, g_settings.getNumber("hotkeyDelay"))
    gameRootPanel:setAutoRepeatDelay(delay)
  end

  g_game.setMaxPreWalkingSteps(g_settings.getBoolean("dash") and 2 or 1)
end

function setWalkDelayOption(key, value)
  value = math.max(0, tonumber(value) or 0)

  if key == 'walkTeleportDelay' then
    walkTeleportDelay = value
  elseif key == 'walkStairsDelay' then
    walkStairsDelay = value
  elseif key == 'walkTurnDelay' then
    walkTurnDelay = value
  elseif key == 'walkFirstStepDelay' then
    walkFirstStepDelay = value
  elseif key == 'walkCtrlTurnDelay' then
    walkCtrlTurnDelay = value
  end
end

function init()
  migrateClassicWalkDefaults()
  migrateDirectTurnWalk()
  migrateDirectWalkDefaults()
  applyDirectWalkRuntimeOptions()

  connect(g_game, {
    onTeleport = onTeleport
  })
  connect(LocalPlayer, {
    onPositionChange = onPositionChange,
    onWalk = onWalk,
    onWalkFinish = onWalkFinish,
    onCancelWalk = onCancelWalk
  })

  m_interface.getRootPanel().onFocusChange = stopSmartWalk
  bindKeys()
end

function terminate()
  disconnect(g_game, {
    onTeleport = onTeleport
  })

  disconnect(LocalPlayer, {
    onPositionChange = onPositionChange,
    onWalk = onWalk,
    onWalkFinish = onWalkFinish,
    onCancelWalk = onCancelWalk
  })
  removeEvent(autoWalkEvent)
  stopSmartWalk()
  unbindKeys()
  disableWSAD()

  local keybindNorthEast = KeyBind:getKeyBind("Movement", "Go North-East")
  local keybindNorthWest = KeyBind:getKeyBind("Movement", "Go North-West")
  local keybindSouthEast = KeyBind:getKeyBind("Movement", "Go South-East")
  local keybindSouthWest = KeyBind:getKeyBind("Movement", "Go South-West")
  keybindNorthEast:deactive()
  keybindNorthWest:deactive()
  keybindSouthEast:deactive()
  keybindSouthWest:deactive()
end

function updateTurnKey(direction, key, remove)
  local dirs = {
    ["Go North"] = North,
    ["Go South"] = South,
    ["Go East"] = East,
    ["Go West"] = West
  }

  for box, modifiers in pairs(data) do
    local mode = m_settings.getOption(box)
    for _, modifier in pairs(modifiers) do
      if not mode or remove then
        unbindTurnKey(modifier .."+" .. key, dirs[direction])
      else
        bindTurnKey(modifier .."+" .. key, dirs[direction])
      end
    end
  end
end

function configureRotateKeys(mode, enabled)
  local dataMode = data[mode]
  for _, modifier in pairs(dataMode) do
    if enabled then
      bindTurnKey(modifier .. '+Up', North)
      bindTurnKey(modifier .. '+Right', East)
      bindTurnKey(modifier .. '+Down', South)
      bindTurnKey(modifier .. '+Left', West)
      bindTurnKey(modifier .. '+NUp', North)
      bindTurnKey(modifier .. '+NRight', East)
      bindTurnKey(modifier .. '+NDown', South)
      bindTurnKey(modifier .. '+NLeft', West)
    else
      unbindTurnKey(modifier .. '+Up', North)
      unbindTurnKey(modifier .. '+Right', East)
      unbindTurnKey(modifier .. '+Down', South)
      unbindTurnKey(modifier .. '+Left', West)
      unbindTurnKey(modifier .. '+NUp', North)
      unbindTurnKey(modifier .. '+NRight', East)
      unbindTurnKey(modifier .. '+NDown', South)
      unbindTurnKey(modifier .. '+NLeft', West)
    end
  end
end

function bindKeys()
  bindWalkKey('Up', North)
  bindWalkKey('Right', East)
  bindWalkKey('Down', South)
  bindWalkKey('Left', West)

  bindWalkKey('NUp', North)
  bindWalkKey('NPgUp', NorthEast)
  bindWalkKey('NRight', East)
  bindWalkKey('NPgDown', SouthEast)
  bindWalkKey('NDown', South)
  bindWalkKey('NEnd', SouthWest)
  bindWalkKey('NLeft', West)
  bindWalkKey('NHome', NorthWest)
end

function unbindKeys()
  unbindWalkKey('Up', North)
  unbindWalkKey('Right', East)
  unbindWalkKey('Down', South)
  unbindWalkKey('Left', West)

  unbindWalkKey('NUp', North)
  unbindWalkKey('NPgUp', NorthEast)
  unbindWalkKey('NRight', East)
  unbindWalkKey('NPgDown', SouthEast)
  unbindWalkKey('NDown', South)
  unbindWalkKey('NEnd', SouthWest)
  unbindWalkKey('NLeft', West)
  unbindWalkKey('NHome', NorthWest)
end

function isEnableWSAD()
  return wsadWalking
end

function enableWSAD()
  if wsadWalking then
    return
  end
  wsadWalking = true
  local player = g_game.getLocalPlayer()
  if player then
    player:lockWalk(100) -- 100 ms walk lock for all directions
  end

  g_keyboard.unbindKeyDown('Ctrl+S')

  local keybindEast = KeyBind:getKeyBind("Movement", "Go East")
  local keybindNorth = KeyBind:getKeyBind("Movement", "Go North")
  local keybindSouth = KeyBind:getKeyBind("Movement", "Go South")
  local keybindWest = KeyBind:getKeyBind("Movement", "Go West")
  keybindEast:active(m_interface.getRootPanel(), true)
  keybindNorth:active(m_interface.getRootPanel(), true)
  keybindSouth:active(m_interface.getRootPanel(), true)
  keybindWest:active(m_interface.getRootPanel(), true)

  local keybindNorthEast = KeyBind:getKeyBind("Movement", "Go North-East")
  local keybindNorthWest = KeyBind:getKeyBind("Movement", "Go North-West")
  local keybindSouthEast = KeyBind:getKeyBind("Movement", "Go South-East")
  local keybindSouthWest = KeyBind:getKeyBind("Movement", "Go South-West")
  keybindNorthEast:active(m_interface.getRootPanel())
  keybindNorthWest:active(m_interface.getRootPanel())
  keybindSouthEast:active(m_interface.getRootPanel())
  keybindSouthWest:active(m_interface.getRootPanel())
end

function disableWSAD()
  if not wsadWalking then
    return
  end

  wsadWalking = false
  g_keyboard.bindKeyDown('Ctrl+S', modules.game_skills.toggle)

  local keybindEast = KeyBind:getKeyBind("Movement", "Go East")
  local keybindNorth = KeyBind:getKeyBind("Movement", "Go North")
  local keybindSouth = KeyBind:getKeyBind("Movement", "Go South")
  local keybindWest = KeyBind:getKeyBind("Movement", "Go West")

  keybindEast:deactive()
  keybindNorth:deactive()
  keybindSouth:deactive()
  keybindWest:deactive()

  local keybindNorthEast = KeyBind:getKeyBind("Movement", "Go North-East")
  local keybindNorthWest = KeyBind:getKeyBind("Movement", "Go North-West")
  local keybindSouthEast = KeyBind:getKeyBind("Movement", "Go South-East")
  local keybindSouthWest = KeyBind:getKeyBind("Movement", "Go South-West")
  keybindNorthEast:deactive()
  keybindNorthWest:deactive()
  keybindSouthEast:deactive()
  keybindSouthWest:deactive()
end

function bindWalkKey(key, dir)
  if dir == NorthEast or dir == SouthEast or dir == NorthWest or dir == SouthWest then
    g_ui.addDiagonalKey(getKeyCode(key))
  end

  local gameRootPanel = m_interface.getRootPanel()
  g_keyboard.bindKeyDown(key, function() changeWalkDir(dir) end, gameRootPanel, true)
  g_keyboard.bindKeyUp(key, function() changeWalkDir(dir, true) end, gameRootPanel, true)
  g_keyboard.bindKeyPress(key, function(c, k, ticks) smartWalk(dir, ticks) end, gameRootPanel)
end

function unbindWalkKey(key)
  if g_ui.isDiagonalKey(getKeyCode(key)) then
    g_ui.removeDiagonalKey(getKeyCode(key))
  end
  local gameRootPanel = m_interface.getRootPanel()
  g_keyboard.unbindKeyDown(key, gameRootPanel)
  g_keyboard.unbindKeyUp(key, gameRootPanel)
  g_keyboard.unbindKeyPress(key, gameRootPanel)
end

function bindTurnKey(key, dir)
  turnKeys[key] = dir
  local gameRootPanel = m_interface.getRootPanel()
  g_keyboard.bindKeyDown(key, function() local player = g_game.getLocalPlayer() turn(dir, false) end, gameRootPanel)
  g_keyboard.bindKeyPress(key, function() turn(dir, true) end, gameRootPanel)
end

function unbindTurnKey(key)
  turnKeys[key] = nil
  local gameRootPanel = m_interface.getRootPanel()
  g_keyboard.unbindKeyDown(key, gameRootPanel)
  g_keyboard.unbindKeyPress(key, gameRootPanel)
end

function stopSmartWalk()
  smartWalkDirs = {}
  smartWalkDir = nil
end

function changeWalkDir(dir, pop)
  while table.removevalue(smartWalkDirs, dir) do end
  if pop then
    if #smartWalkDirs == 0 then
      stopSmartWalk()
      return
    end
  else
    table.insert(smartWalkDirs, 1, dir)
  end

  smartWalkDir = smartWalkDirs[1]
  if m_settings.getOption("smartWalk") and #smartWalkDirs > 1 then
    for _,d in pairs(smartWalkDirs) do
      if (smartWalkDir == North and d == West) or (smartWalkDir == West and d == North) then
        smartWalkDir = NorthWest
        break
      elseif (smartWalkDir == North and d == East) or (smartWalkDir == East and d == North) then
        smartWalkDir = NorthEast
        break
      elseif (smartWalkDir == South and d == West) or (smartWalkDir == West and d == South) then
        smartWalkDir = SouthWest
        break
      elseif (smartWalkDir == South and d == East) or (smartWalkDir == East and d == South) then
        smartWalkDir = SouthEast
        break
      end
    end
  end
end

function smartWalk(dir, ticks)
  removeEvent(walkEvent)

  if g_keyboard.getModifiers() == KeyboardNoModifier then
    local direction = smartWalkDir or dir
    return walk(direction, ticks)
  end

  return false
end

function canChangeFloorDown(pos)
  pos.z = pos.z + 1
  toTile = g_map.getTile(pos)
  return toTile and toTile:hasElevation(3)
end

function canChangeFloorUp(pos)
  pos.z = math.max(0, pos.z - 1)
  toTile = g_map.getTile(pos)
  return toTile and toTile:isWalkable()
end

function onPositionChange(player, newPos, oldPos)
end

function onWalk(player, newPos, oldPos)
  if autoFinishNextServerWalk + 200 > g_clock.millis() then
    player:finishServerWalking()
  end
end

function onTeleport(player, newPos, oldPos)
  if not newPos or not oldPos then
    return
  end
  local delay = 0
  if math.abs(newPos.x - oldPos.x) >= 3 or math.abs(newPos.y - oldPos.y) >= 3 or math.abs(newPos.z - oldPos.z) >= 2 then
    delay = g_settings.getNumber("walkTeleportDelay")
  else
    delay = g_settings.getNumber("walkStairsDelay")
  end

  walkLock = delay > 0 and g_clock.millis() + delay or 0

  nextWalkDir = nil
end

function onWalkFinish(player)
  lastFinishedStep = g_clock.millis()
  if nextWalkDir ~= nil then
    removeEvent(autoWalkEvent)
    autoWalkEvent = addEvent(function() if nextWalkDir ~= nil then walk(nextWalkDir, 0) end end, false)
  end
end

function onCancelWalk(player)
  player:lockWalk(50)
end

function walk(dir, ticks)
  ticks = ticks or 0
  lastManualWalk = g_clock.millis()
  local player = g_game.getLocalPlayer()

  if not player or g_game.isDead() or player:isDead() then
    return
  end

  if player:isWalkLocked() then
    nextWalkDir = nil
    return
  end

  if g_game.isFollowing() then
    g_game.cancelFollow()
  end

  if player:isAutoWalking() and lastStop + 100 < g_clock.millis() then
    lastStop = g_clock.millis()
    player:stopAutoWalk()
    g_game.stop()
  end

  local dash = false
  local ignoredCanWalk = false

  if not g_game.getFeature(GameNewWalking) then
    dash = g_settings.getBoolean("dash", false)
  end

  local ticksToNextWalk = player:getStepTicksLeft()

  if not player:canWalk(dir) then
    if dash then
      ignoredCanWalk = true
    else
      if ticksToNextWalk < 500 and (lastWalkDir ~= dir or ticks == 0) then
        nextWalkDir = dir
      end

      if ticksToNextWalk < 30 and g_clock.millis() < lastFinishedStep + 400 and nextWalkDir == nil then
        nextWalkDir = dir
      end

      return
    end
  end

  if nextWalkDir ~= nil and nextWalkDir ~= lastWalkDir then
    dir = nextWalkDir
  end

  local toPos = player:getPrewalkingPosition(true)

  if dir == North then
    toPos.y = toPos.y - 1
  elseif dir == East then
    toPos.x = toPos.x + 1
  elseif dir == South then
    toPos.y = toPos.y + 1
  elseif dir == West then
    toPos.x = toPos.x - 1
  elseif dir == NorthEast then
    toPos.x = toPos.x + 1
    toPos.y = toPos.y - 1
  elseif dir == SouthEast then
    toPos.x = toPos.x + 1
    toPos.y = toPos.y + 1
  elseif dir == SouthWest then
    toPos.x = toPos.x - 1
    toPos.y = toPos.y + 1
  elseif dir == NorthWest then
    toPos.x = toPos.x - 1
    toPos.y = toPos.y - 1
  end

  local toTile = g_map.getTile(toPos)
  local now = g_clock.millis()

  if now <= walkLock then
    nextWalkDir = nil
    return
  end

  if firstStep and lastWalkDir == dir and now < lastWalk + g_settings.getNumber("walkFirstStepDelay") then
    firstStep = false
    walkLock = lastWalk + g_settings.getNumber("walkFirstStepDelay")
    return
  end

  if dash and lastWalkDir == dir and now < lastWalk + 50 then
    return
  end

  local firstStepDelay = g_settings.getNumber("walkFirstStepDelay")
  firstStep = not player:isWalking() and lastFinishedStep + firstStepDelay < now and walkLock + firstStepDelay < now

  if player:isServerWalking() and not dash then
    walkLock = firstStepDelay > 0 and now + firstStepDelay or 0
  end

  nextWalkDir = nil

  removeEvent(autoWalkEvent)

  autoWalkEvent = nil
  local preWalked = false

  if toTile and toTile:isWalkable() then
    if not player:isServerWalking() and not ignoredCanWalk then
      player:preWalk(dir)
      preWalked = true
    end
  else
    local playerTile = player:getTile()

    if playerTile and playerTile:hasElevation(3) and canChangeFloorUp(toPos) or canChangeFloorDown(toPos) or toTile and toTile:isEmpty() and not toTile:isBlocking() then
      player:lockWalk(100)
    elseif player:isServerWalking() then
      g_game.stop()
      return
    elseif not toTile then
      player:lockWalk(100)
    else
      if g_app.isMobile() and dir <= Directions.West then
        turn(dir, ticks > 0)
      end

      return
    end
  end

  if player:isServerWalking() and not dash then
    g_game.stop()
    player:finishServerWalking()

    autoFinishNextServerWalk = g_clock.millis() + 200
  end

  g_game.walk(dir, preWalked)

  local turnDelay = g_settings.getNumber("walkTurnDelay")
  if turnDelay > 0 and not firstStep and lastWalkDir ~= dir then
    walkLock = g_clock.millis() + turnDelay
  end

  lastWalkDir = dir
  lastWalk = g_clock.millis()

  return true
end

function turn(dir, repeated)
  local player = g_game.getLocalPlayer()

  if player:isWalking() and player:getWalkDirection() == dir and not player:isServerWalking() then
    return
  end

  removeEvent(walkEvent)

  if not repeated or lastTurn + 100 < g_clock.millis() then
    g_game.turn(dir)
    changeWalkDir(dir)

    lastTurn = g_clock.millis()

    if not repeated then
      lastTurn = g_clock.millis() + 50
    end

    lastTurnDirection = dir
    nextWalkDir = nil

    local ctrlTurnDelay = g_settings.getNumber("walkCtrlTurnDelay")
    if ctrlTurnDelay > 0 then
      player:lockWalk(ctrlTurnDelay)
    end
  end
end

function checkTurn()
  for keys, direction in pairs(turnKeys) do
    if g_keyboard.areKeysPressed(keys) then
      turn(direction, false)
    end
  end
end

function isBlockWalk()
return (not rootWidget:getChildById("gameRootPanel"):isFocused() or m_interface.isPanelFocused())
end
