UIGameMap = extends(UIMap, "UIGameMap")

function UIGameMap.create()
  local gameMap = UIGameMap.internalCreate()
  gameMap:setKeepAspectRatio(true)
  gameMap:setVisibleDimension({width = 15, height = 11})
  gameMap:setDrawLights(true)
  gameMap.markedThing = nil
  gameMap.blockNextRelease = 0
  gameMap:insertLuaCall("onDestroy")
  return gameMap
end

function UIGameMap:onDestroy()
  if self.updateMarkedCreatureEvent then
    removeEvent(self.updateMarkedCreatureEvent)
  end
end

function UIGameMap:setDrawMarks(draw)
  if self.updateMarkedCreatureEvent then
    removeEvent(self.updateMarkedCreatureEvent)
    self.updateMarkedCreatureEvent = nil
  end

  if draw and not g_app.isMobile() then
    self.updateMarkedCreatureEvent = cycleEvent(function() self:updateMarkedCreature() end, 100)
  else
    if self.markedThing then
      self.markedThing:setMarked('')
    end
  end
end

function UIGameMap:markThing(thing, color)

  if self.markedThing == thing then
    return
  end

  local markedColor = thing and thing:isMarked() and thing:getMarkedColor()
  if markedColor and (markedColor.r ~= 255 or markedColor.g ~= 255 or markedColor.b ~= 0) then
    return
  end

  if self.markedThing then
    self.markedThing:setMarked('')
  end

  self.markedThing = thing

  if self.markedThing and g_settings.getBoolean('highlightThingsUnderCursor') then
    if g_keyboard.isShiftPressed() or m_settings.getOption('classicControl') == 3 then
      self.markedThing:setMarked(color)
    end
  end
end

function UIGameMap:onDragEnter(mousePos)
  local tile = self:getTile(mousePos)
  if not tile then return false end
  if self.dragTile ~= tile then return false end

  local thing = tile:getTopMoveThing()
  if not thing then return false end

  if thing:isNotMoveable() then
    self.allowNextRelease = false
    return false
  end
  self.currentDragThing = thing

  if thing:getClassName() == "Item" and not thing:isNotMoveable() then
    local dragClone = g_ui.createWidget("DragItem")
    dragClone:setParent(m_interface.getRootPanel())
    dragClone:setItemId(thing:getId())
    dragClone:setItemSubType(thing:getSubType())
    dragClone:setX(mousePos.x + 12)
    dragClone:setY(mousePos.y + 9)
    self.dragClone = dragClone
  end

  g_mouse.pushCursor('target')
  self.allowNextRelease = false
  return true
end

function UIGameMap:onDragMove(mousePos, mouseMoved)
  self.mousePos = mousePos
  if self.dragClone then
    self.dragClone:setX(mousePos.x + 12)
    self.dragClone:setY(mousePos.y + 9)
  end
  return false
end

function UIGameMap:onDragLeave(droppedWidget, mousePos)
  self.currentDragThing = nil
  self.hoveredWho = nil
  g_mouse.popCursor('target')

  if self.dragClone then
    self.dragClone:destroy()
    self.dragClone = nil
  end
  return true
end

function UIGameMap:onDrop(widget, mousePos)
  if self.blockNextRelease > g_clock.millis() then
    return true
  end

  if not self:canAcceptDrop(widget, mousePos) then return false end

  local tile = self:getTile(mousePos)
  if not tile then return false end

  local thing = widget.currentDragThing
  local toPos = tile:getPosition()

  local thingPos = thing:getPosition()
  if not thingPos then return false end
  if thingPos.x == toPos.x and thingPos.y == toPos.y and thingPos.z == toPos.z then return false end

  if thing:isItem() then
    m_interface.moveStackableItem(thing, toPos)
  else
    g_game.move(thing, toPos, (thing:isItem() and thing:getCount() or 1), modules.game_containers.useManualSort())
  end
  return true
end

function UIGameMap:onMouseMove(mousePos, mouseMoved)
  self.mousePos = mousePos
  return false
end

function UIGameMap:updateMarkedCreature()
  if self.mousePos and g_game.isOnline() then
    local mousePosition = self.mousePos
    local autoWalkPos = self:getPosition(mousePosition)
    local positionOffset = self:getPositionOffset(mousePosition)

    -- happens when clicking outside of map boundaries
    if not autoWalkPos then
      self:markThing(nil)
      return
    end

    local localPlayerPos = g_game.getLocalPlayer():getPosition()
    if autoWalkPos.z ~= localPlayerPos.z then
      local dz = autoWalkPos.z - localPlayerPos.z
      autoWalkPos.x = autoWalkPos.x + dz
      autoWalkPos.y = autoWalkPos.y + dz
      autoWalkPos.z = localPlayerPos.z
    end

    local lookThing
    local useThing
    local creatureThing
    local attackCreature

    local tile = self:getTile(mousePosition)
    if tile then
      lookThing = tile:getTopLookThingEx(positionOffset)
      useThing = tile:getTopUseThing()
      creatureThing = tile:getTopCreatureEx(positionOffset)
    end

    local autoWalkTile = g_map.getTile(autoWalkPos)
    if autoWalkTile then
      attackCreature = autoWalkTile:getTopCreatureEx(positionOffset)
    end

    if attackCreature then
      self:markThing(attackCreature, 'yellow')
    elseif creatureThing then
      self:markThing(creatureThing, 'yellow')
    elseif useThing and not useThing:isGround() then
      self:markThing(useThing, 'yellow')
    elseif lookThing and not lookThing:isGround() then
      self:markThing(lookThing, 'yellow')
    else
      self:markThing(nil, '')
    end
  end
end

function UIGameMap:onMousePress(mousePos)
  if not self:isDragging() and self.blockNextRelease < g_clock.millis() then
    self.dragTile = self:getTile(mousePos)
    self.allowNextRelease = true
    self.markingMouseRelease = false
  end
end

function UIGameMap:blockNextMouseRelease(postAction)
  self.allowNextRelease = false
  if postAction then
    self.blockNextRelease = g_clock.millis() + 10
  else
    self.blockNextRelease = g_clock.millis() + 10
  end
end

function UIGameMap:scheduleBlockMouseRelease(time)
  if not time then
    time = 10
  end

  self.blockNextRelease = g_clock.millis() + time
end

function UIGameMap:onMouseRelease(mousePosition, mouseButton)
  if not self.allowNextRelease and not self.markingMouseRelease then
    return true
  end
  local autoWalkPos = self:getPosition(mousePosition)
  local positionOffset = self:getPositionOffset(mousePosition)

  -- happens when clicking outside of map boundaries
  if not autoWalkPos then
    if self.markingMouseRelease then
      self:markThing(nil)
    end
    return false
  end

  local localPlayerPos = {x = 0, y = 0, z = 0}
  local localPlayer = g_game.getLocalPlayer()
  if localPlayer then
    localPlayerPos = localPlayer:getPosition()
  end
  if autoWalkPos.z ~= localPlayerPos.z then
    local dz = autoWalkPos.z - localPlayerPos.z
    autoWalkPos.x = autoWalkPos.x + dz
    autoWalkPos.y = autoWalkPos.y + dz
    autoWalkPos.z = localPlayerPos.z
  end

  local lookThing
  local useThing
  local creatureThing
  local multiUseThing
  local attackCreature

  local tile = self:getTile(mousePosition)
  if tile then
    lookThing = tile:getTopLookThingEx(positionOffset)
    useThing = tile:getTopUseThing()
    creatureThing = tile:getTopCreatureEx(positionOffset)
    if not creatureThing then
      creatureThing = g_map.getCreatureById(tile:getCollisionCreatureId())
    end
  end

  local autoWalkTile = g_map.getTile(autoWalkPos)
  if autoWalkTile then
    attackCreature = autoWalkTile:getTopCreatureEx(positionOffset)
  end

  local ret = m_interface.processMouseAction(tile, mousePosition, mouseButton, autoWalkPos, lookThing, useThing, creatureThing, attackCreature, self.markingMouseRelease)

  if ret then
    self.allowNextRelease = false
  end

  return ret
end

function UIGameMap:onTouchRelease(mousePosition, mouseButton)
  if mouseButton ~= MouseTouch then
    return self:onMouseRelease(mousePosition, mouseButton)
  end
end

function UIGameMap:canAcceptDrop(widget, mousePos)
  if not widget or not widget.currentDragThing then return false end

  if widget:getClassName() == "UIItem" and widget:getItem() and modules.game_actionbar.isPresetWindowVisible() then
    return false
  end

  local children = rootWidget:recursiveGetChildrenByPos(mousePos)
  for i=1,#children do
    local child = children[i]
    if child == self then
      return true
    elseif not child:isPhantom() then
      return false
    end
  end

  error('Widget ' .. self:getId() .. ' not in drop list.')
  return false
end
