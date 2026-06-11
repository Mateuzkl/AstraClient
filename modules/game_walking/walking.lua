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

function setWalkDelayOption(key, value)
  value = math.max(0, tonumber(value) or 0)

  if key == 'walkTeleportDelay' then
    walkTeleportDelay = value
  elseif key == 'walkStairsDelay' then
    walkStairsDelay = value
  elseif key == 'walkTurnDelay' then
    walkTurnDelay = value
  end
end

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
  removeEvent(walkEvent)
  walkEvent = scheduleEvent(function()
    internalSmartWalk(dir, ticks)
  end, 10)
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
  if g_ui.getCustomInputWidget() then
    return
  end

  local player = g_game.getLocalPlayer()
  if not player or g_game.isDead() or player:isDead() then
    return
  end

  if player:isWalkLocked() or player:isRooted() then
    nextWalkDir = nil
    return
  end

  if not player:canWalk(dir) then
    nextWalkDir = dir
    return
  end

  if g_game.isFollowing() then
    g_game.cancelFollow()
  end

  if player:isAutoWalking() then
    player:stopAutoWalk()
    g_game.stop()
  end

  nextWalkDir = nil
  removeEvent(autoWalkEvent)
  autoWalkEvent = nil

  local toPos = player:getPrewalkingPosition(true)
  if not toPos then
    toPos = player:getPosition()
    if not toPos then
      return
    end
  end
  local dx, dy = 0, 0
  if dir == North then dy = -1
  elseif dir == South then dy = 1
  elseif dir == East then dx = 1
  elseif dir == West then dx = -1
  elseif dir == NorthEast then dx, dy = 1, -1
  elseif dir == SouthEast then dx, dy = 1, 1
  elseif dir == SouthWest then dx, dy = -1, 1
  elseif dir == NorthWest then dx, dy = -1, -1
  end
  toPos = {x = toPos.x + dx, y = toPos.y + dy, z = toPos.z}

  local toTile = g_map.getTile(toPos)
  local preWalked = false

  if toTile and toTile:isWalkable() then
    if not player:isPreWalking() and not player:isServerWalking() then
      player:preWalk(dir)
      preWalked = true
    end
  else
    local playerTile = player:getTile()
    if (playerTile and playerTile:hasElevation(3) and canChangeFloorUp(toPos)) or canChangeFloorDown(toPos) then
      player:lockWalk(100)
    elseif not toTile then
      player:lockWalk(100)
    elseif toTile:getTopCreature() and not toTile:getTopCreature():isPassable() then
      modules.game_textmessage.displayFailureMessage(tr('Sorry, not possible.'))
      if m_settings.getOption("alwaysTurnTowardsMoveDirection") and dir ~= player:getDirection() then
        g_game.turn(dir)
      end
      return
    else
      modules.game_textmessage.displayFailureMessage(tr('Sorry, not possible.'))
      if m_settings.getOption("alwaysTurnTowardsMoveDirection") and dir ~= player:getDirection() then
        g_game.turn(dir)
      end
      return
    end
  end

  if player:isServerWalking() then
    player:finishServerWalking()
  end

  g_game.walk(dir, preWalked)

  lastWalkDir = dir
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
