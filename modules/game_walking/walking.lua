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
walkTeleportDelay = 100
walkStairsDelay = 50
walkFirstStepDelay = 50
walkTurnDelay = 10
walkCtrlTurnDelay = 10

local data = {
  ["ctrlCheckBox"] = {"Ctrl"},
  ["shiftCheckBox"] = {"Shift"},
  ["altCheckBox"] = {"Alt", "Ctrl+Alt"}
}

function init()
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
  g_keyboard.bindKeyDown(key, 
    function(c, k, ticks)
      if modules.game_walking.isBlockWalk() then
        return
      end

      if g_keyboard.getModifiers() == KeyboardNoModifier then
        if m_settings.getOption('smartWalk') then
          changeWalkDir(dir)
        else
          walk(dir) 
          checkPressedWalkKeys(key)
        end
      end
    end, gameRootPanel, true)

  g_keyboard.bindKeyUp(key, function() changeWalkDir(dir, true) end, gameRootPanel, true)
  g_keyboard.bindKeyPress(key, 
    function(c, k, ticks) 
      if modules.game_walking.isBlockWalk() then
        return
      end

      checkPressedWalkKeys(key)
      if m_settings.getOption('smartWalk') then
        smartWalk(dir, ticks) 
      else
        walk(dir, ticks) 
      end
    end, gameRootPanel)
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
    local dash = g_settings.getBoolean("dash", false) and g_game.getPing() > 50
    local player = g_game.getLocalPlayer()
    local teleportWalkDelay = player and player.getTeleportWalkDelay and player:getTeleportWalkDelay() or 0
    if dash and dir == lastWalkDir and teleportWalkDelay < g_clock.millis() then
      g_game.cancelNextWalk()
    end

    if #smartWalkDirs == 0 then
      stopSmartWalk()
      return
    end
  else
    table.insert(smartWalkDirs, 1, dir)
  end

  smartWalkDir = smartWalkDirs[1]
  if m_settings.getOption('smartWalk') and #smartWalkDirs > 1 then
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

function internalSmartWalk(dir, ticks)
  if g_keyboard.getModifiers() == KeyboardNoModifier then
    local direction = smartWalkDir or dir
    walk(direction, ticks)
    return true
  end
end

function smartWalk(dir, ticks)
  walkEvent = scheduleEvent(function()
    internalSmartWalk(dir, ticks)
  end, 20)
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
  -- floor change is also teleport
  if math.abs(newPos.x - oldPos.x) >= 3 or math.abs(newPos.y - oldPos.y) >= 3 or math.abs(newPos.z - oldPos.z) >= 2 then
    -- far teleport, lock walk for 100ms
    walkLock = g_clock.millis() + walkTeleportDelay
  else
    walkLock = g_clock.millis() + walkStairsDelay
  end
  if player.setTeleportWalkDelay then
    player:setTeleportWalkDelay(walkLock)
  end
  nextWalkDir = nil -- cancel autowalk
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

function checkPressedWalkKeys(newKey)
  if m_settings.getOption('smartWalk') then
    return
  end

  local keysToCheck = {
    'Up', 'Right', 'Down', 'Left',
    'NUp', 'NRight', 'NDown', 'NLeft',
    'NPgUp', 'NPgDown', 'NEnd', 'NHome'
  }

  for _, key in ipairs(keysToCheck) do
    if newKey ~= key and g_keyboard.isKeyPressed(key) then
      g_window.releaseKey(getKeyCode(key))
    end
  end

  local movements = {
    "Go East", "Go North", "Go South", "Go West",
    "Go North-East", "Go North-West", "Go South-East", "Go South-West"
  }

  for _, movement in ipairs(movements) do
    local keyBind = KeyBind:getKeyBind("Movement", movement)
    if newKey ~= keyBind.firstKey and g_keyboard.isKeyPressed(keyBind.firstKey) then
      g_window.releaseKey(getKeyCode(keyBind.firstKey))
    elseif newKey ~= keyBind.secondKey and g_keyboard.isKeyPressed(keyBind.secondKey) then
      g_window.releaseKey(getKeyCode(keyBind.secondKey))
    end
  end
end

function isWalkKeyPressed()
  local keysToCheck = {
    'Up', 'Right', 'Down', 'Left',
    'NUp', 'NRight', 'NDown', 'NLeft',
    'NPgUp', 'NPgDown', 'NEnd', 'NHome'
  }

  for _, key in ipairs(keysToCheck) do
    if g_keyboard.isKeyPressed(key) then
      return true
    end
  end

  local movements = {
    "Go East", "Go North", "Go South", "Go West",
    "Go North-East", "Go North-West", "Go South-East", "Go South-West"
  }

  for _, movement in ipairs(movements) do
    local keyBind = KeyBind:getKeyBind("Movement", movement)
    if g_keyboard.isKeyPressed(keyBind.firstKey) or g_keyboard.isKeyPressed(keyBind.secondKey) then
      return true
    end
  end

  return false
end

function walk(dir, ticks)
  -- Cannot walk while input locked
  if g_ui.getCustomInputWidget() then
    return
  end

  -- Do not walk when turn modifiers keys are pressed
  local turnModifiers = {KeyboardCtrlModifier, KeyboardAltModifier, KeyboardShiftModifier}
  if table.contains(turnModifiers, g_keyboard.getModifiers()) then
    return
  end

  lastManualWalk = g_clock.millis()
  local player = g_game.getLocalPlayer()

  if dir == lastWalkDir and not isWalkKeyPressed() then
    if player then
      player:stopAutoWalk()
    end
    g_game.stop()
    nextWalkDir = nil
    return
  end

  if not player or g_game.isDead() or player:isDead() then
    return
  end

  if player:isWalkLocked() or player:isRooted() then
    nextWalkDir = nil
    return
  end

  if g_game.isFollowing() then
    g_game.cancelFollow()
  end

  if player and player:isAutoWalking() then
    if lastStop + 100 < g_clock.millis() then
      lastStop = g_clock.millis()
      player:stopAutoWalk()
      g_game.stop()
    end
  end

  if player:isWalking() and (player:isParalyzed() or player:getPreWalkLockedDelay() >= g_clock.millis()) then
    return
  end

  local dash = false
  local ignoredCanWalk = false
  local teleportWalkDelay = player.getTeleportWalkDelay and player:getTeleportWalkDelay() or 0
  if not g_game.getFeature(GameNewWalking) and teleportWalkDelay < g_clock.millis() then
    dash = g_settings.getBoolean("dash", false) and g_game.getPing() > 50
  end

  local ticksToNextWalk = player:getStepTicksLeft()
  if player and not player:canWalk(dir) then -- canWalk return false when previous walk is not finished or not confirmed by server
    if dash then
      ignoredCanWalk = true
    else
      if ticksToNextWalk < 500 and (lastWalkDir ~= dir or ticks == 0) then
        nextWalkDir = dir
      end
      if ticksToNextWalk < 30 and lastFinishedStep + 400 > g_clock.millis() and nextWalkDir == nil then -- clicked walk 20 ms too early, try to execute again as soon possible to keep smooth walking
        nextWalkDir = dir
      end
      return
    end
  end

  if nextWalkDir ~= nil and nextWalkDir ~= lastWalkDir then
    dir = nextWalkDir
  end

  local toPos = player:getPrewalkingPosition(true)
  if not toPos then
    toPos = player:getPosition()
    if not toPos then
      return
    end
  end
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
  if walkLock >= g_clock.millis() and lastWalkDir == dir or (toTile and toTile:getCollisionCreatureId() > 0 and player:getGroupType() < 4) then
    nextWalkDir = nil
    return
  end

  if firstStep and lastWalkDir == dir and lastWalk + walkFirstStepDelay > g_clock.millis() then
    firstStep = false
    walkLock = lastWalk + walkFirstStepDelay
    return
  end

  if dash and lastWalkDir == dir and lastWalk + 50 > g_clock.millis() then
    return
  end

  firstStep = (not player:isWalking() and lastFinishedStep + 100 < g_clock.millis() and walkLock + 100 < g_clock.millis())
  if player:isServerWalking() and not dash then
    walkLock = walkLock + math.max(walkFirstStepDelay, 100)
  end

  nextWalkDir = nil
  removeEvent(autoWalkEvent)
  autoWalkEvent = nil
  local preWalked = false
  if toTile and toTile:isWalkable() and not toTile:hasItem(ITEM_WILD_GROWTH) then
    if not player:isServerWalking() and not ignoredCanWalk then
      -- Diagonal pre-walk makes double step
      local diagonalDirs = {4, 5, 6, 7}
      if not table.contains(diagonalDirs, dir) and (player:getPreWalkLockedDelay() < g_clock.millis() and not player:isParalyzed() and not not table.contains(diagonalDirs, lastWalkDir)) then
        player:preWalk(dir)
        preWalked = true
      end
    end
  else
    local playerTile = player:getTile()
    if (playerTile and playerTile:hasElevation(3) and canChangeFloorUp(toPos)) or canChangeFloorDown(toPos) or (toTile and toTile:isEmpty() and not toTile:isBlocking()) then
      player:lockWalk(100)
    elseif player:isServerWalking() then
      g_game.stop()
      return
    elseif not toTile then
      player:lockWalk(100) -- bug fix for missing stairs down on map
    elseif toTile:getTopCreature() and not toTile:getTopCreature():isPassable() then
      modules.game_textmessage.displayFailureMessage(tr('Sorry, not possible.'))
      if m_settings.getOption("alwaysTurnTowardsMoveDirection") and dir ~= player:getDirection() then
        g_game.turn(dir)
      end

      if toTile:getTopCreature():isPlayer() then
        g_game.cancelPushAction()
      end
      return
    else
      if g_app.isMobile() and dir <= Directions.West then
        turn(dir, ticks > 0)
      end
      modules.game_textmessage.displayFailureMessage(tr('Sorry, not possible.'))
      if m_settings.getOption("alwaysTurnTowardsMoveDirection") and dir ~= player:getDirection() then
        g_game.turn(dir)
      end
      return -- not walkable tile
    end
  end

  if player:isServerWalking() and not dash then
    g_game.stop()
    player:finishServerWalking()
    autoFinishNextServerWalk = g_clock.millis() + 200
  end

  g_game.walk(dir, preWalked)

  if not firstStep and lastWalkDir ~= dir then
    walkLock = g_clock.millis() + walkTurnDelay
  end

  lastWalkDir = dir
  lastWalk = g_clock.millis()
  return true
end

function turn(dir, repeated)
  local player = g_game.getLocalPlayer()
  if player:isAutoWalking() then
    if lastStop + 100 < g_clock.millis() then
      lastStop = g_clock.millis()
	  return
    end
  end

  if not repeated or (lastTurn + 100 < g_clock.millis()) then
    g_game.turn(dir)
    changeWalkDir(dir)
    lastTurn = g_clock.millis()
    if not repeated then
      lastTurn = g_clock.millis() + 50
    end
    lastTurnDirection = dir
    nextWalkDir = nil
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
