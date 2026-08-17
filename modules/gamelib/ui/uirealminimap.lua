if not UIRealMinimap then
  if not UIMinimap then
    return
  end

  UIRealMinimap = {
    create = function()
      local widget = UIMinimap.create()
      for name, value in pairs(UIRealMinimap) do
        if name ~= 'create' then
          widget[name] = value
        end
      end
      return widget
    end
  }
end

function UIRealMinimap:onCreate()
  self.autowalk = true
  self.customMouseEvents = {}
  self.alternatives = {}
end

function UIRealMinimap:onSetup()
  self.flagWindow = nil
  self.alternatives = {}

  self.autoWidgets= {}

  -- widget.imagePath, widget.imageSize, widget.position, widget.tooltip
  self.onAddAutomapFlag = function(pos, icon, description)
    local id = self:addWidget("data/images/game/minimap/flag"..icon..".png", {width = 11, height = 11}, pos, description)
    local uid = string.format("%d,%d,%d-%s-%s", pos.x, pos.y, pos.z, icon, description)
    self.autoWidgets[uid] = id
  end

  self.onRemoveAutomapFlag = function(pos, icon, description)
    local uid = string.format("%d,%d,%d-%s-%s", pos.x, pos.y, pos.z, icon, description)
    local id = self.autoWidgets[uid]
    self:removeWidget(id)
  end
  connect(g_game, {
    onAddAutomapFlag = self.onAddAutomapFlag,
    onRemoveAutomapFlag = self.onRemoveAutomapFlag,
  })
end

function UIRealMinimap:onDestroy()
  -- Child alternatives have already been destroyed by UIWidget::internalDestroy
  -- before this callback runs. Only alternatives detached through
  -- setAlternativeWidgetsVisible(false) still need explicit destruction.
  local alternatives = self.alternatives or {}
  self.alternatives = {}
  for _, widget in pairs(alternatives) do
    local ok, destroyed = pcall(function()
      return widget == nil or widget:isDestroyed()
    end)
    if ok and not destroyed then
      pcall(function()
        widget:destroy()
      end)
    end
  end
  disconnect(g_game, {
    onAddAutomapFlag = self.onAddAutomapFlag,
    onRemoveAutomapFlag = self.onRemoveAutomapFlag,
  })
  self:destroyFlagWindow()
end

function UIRealMinimap:onVisibilityChange()
  if not self:isVisible() then
    self:destroyFlagWindow()
  end
end

function UIRealMinimap:onCameraPositionChange(cameraPos)
  if self.cross then
    self:setCrossPosition(self.cross.pos)
  end
end

function UIRealMinimap:hideFloor()
  self.floorUpWidget:hide()
  self.floorDownWidget:hide()
end

function UIRealMinimap:hideZoom()
  self.zoomInWidget:hide()
  self.zoomOutWidget:hide()
end

function UIRealMinimap:disableAutoWalk()
  self.autowalk = false
end

function UIRealMinimap:load()
  local settings = g_settings.getNode('RealMinimap')
  if settings then
    if settings.flags then
      for _,widget in pairs(settings.flags) do
        self:addWidget(widget.imagePath, widget.imageSize, widget.position, widget.tooltip)
      end
    end
    self:setZoom(settings.zoom)
  end
end

function UIRealMinimap:save()
  local settings = { flags={} }
  local currentWidgets = {}
  for _,widget in pairs(currentWidgets) do
    table.insert(settings.flags, {
      position = widget.pos,
      imagePath = widget.imagePath,
      imageSize = widget.imageSize,
      description = widget.tooltip,
    })
  end
  settings.zoom = self:getZoom()
  g_settings.setNode('RealMinimap', settings)
end

function UIRealMinimap:setCrossPosition(pos)
  local cross = self.cross
  if not self.cross then
    cross = g_ui.createWidget('MinimapCross', self)
    cross:setIcon('/images/game/minimap/cross')
    self.cross = cross
  end

  cross:setVisible(true)
  pos.z = self:getCameraPosition().z
  cross.pos = pos
  if pos then
    self:centerInPosition(cross, pos)
  else
    cross:breakAnchors()
  end
end

function UIRealMinimap:hideCross()
  local cross = self.cross
  if cross then
    cross:setVisible(false)
  end
end

function UIRealMinimap:addAlternativeWidget(widget, pos, maxZoom)
  widget.pos = pos
  widget.maxZoom = maxZoom or 0
  widget.minZoom = minZoom
  table.insert(self.alternatives, widget)
end

function UIRealMinimap:setAlternativeWidgetsVisible(show)
  local layout = self:getLayout()
  layout:disableUpdates()
  for _,widget in pairs(self.alternatives) do
    if show then
      self:insertChild(1, widget)
      self:centerInPosition(widget, widget.pos)
    else
      self:removeChild(widget)
    end
  end
  layout:enableUpdates()
  layout:update()
end

function UIRealMinimap:onZoomChange(zoom)
  for _,widget in pairs(self.alternatives) do
    if (not widget.minZoom or widget.minZoom >= zoom) and widget.maxZoom <= zoom then
      widget:show()
    else
      widget:hide()
    end
  end

  g_tooltip.hide()
end

function UIRealMinimap:reset()
  self:setZoom(0)
  if self.cross then
    self:setCameraPosition(self.cross.pos)
  end
end

function UIRealMinimap:move(x, y)
  local cameraPos = self:getCameraPosition()
  local scale = self:getScale()
  if scale > 1 then scale = 1 end
  local dx = x/scale
  local dy = y/scale
  local pos = {x = cameraPos.x - dx, y = cameraPos.y - dy, z = cameraPos.z}
  self:setCameraPosition(pos)
end

function UIRealMinimap:onMouseWheel(mousePos, direction)
  local keyboardModifiers = g_keyboard.getModifiers()
  if direction == MouseWheelUp and keyboardModifiers == KeyboardNoModifier then
    self:zoomIn()
  elseif direction == MouseWheelDown and keyboardModifiers == KeyboardNoModifier then
    self:zoomOut()
  elseif direction == MouseWheelDown and keyboardModifiers ~= KeyboardNoModifier then
    self:floorUp(1)
  elseif direction == MouseWheelUp and keyboardModifiers ~= KeyboardNoModifier then
    self:floorDown(1)
  end
end

function UIRealMinimap:onMousePress(pos, button)
  if not self:isDragging() then
    self.allowNextRelease = true
  end
end

function UIRealMinimap:onMouseMove(mousePos, mouseMoved)
    local mapPos = self:getTilePosition(mousePos)
    local mouseBefore = {x = mousePos.x - mouseMoved.x, y = mousePos.y - mouseMoved.y}
    if not mapPos then return end

    if self.onHoverPosition then
        self:onHoverPosition(mapPos)
        local widgetInfo = self:getWidgetInfoFromPoint(mousePos)
        local widgetInfoBefore = self:getWidgetInfoFromPoint(mouseBefore)
        if widgetInfo and not widgetInfoBefore then
          if self:isWidgetIgnored(widgetInfo.imagePath) then return end

          g_tooltip.displayText(widgetInfo.tooltip)
        elseif not widgetInfo and widgetInfoBefore then
          g_tooltip.hide()
        end
    end
end

function UIRealMinimap:onHide()
  -- table.dump(self.customMouseEvents)
  for buttonType, customMouseEvents in pairs(self.customMouseEvents) do
    for _, customMouseEvent in ipairs(customMouseEvents) do
      customMouseEvent.callback(self, customMouseEvent.fromMapPos, customMouseEvent.fromMapPos)
    end
  end
end

function UIRealMinimap:resetCustomMouseEvent()
  self.customMouseEvents = {}
end

function UIRealMinimap:onMouseRelease(pos, button)
  if self.unclickable then return end
  if not self.allowNextRelease then return true end
  self.allowNextRelease = false

  local mapPos = self:getTilePosition(pos)
  if not mapPos then return end

  -- check if has selectedCity
  local widgetInfo = self:getWidgetInfoFromPoint(pos)
  if widgetInfo and widgetInfo.type == "city" then
    self:setSelectedCity(widgetInfo.widgetId)
    local regions = g_things.getSubAreaById(widgetInfo.widgetId)
    RealMap.setRegions(self, widgetInfo.widgetId, regions)
    return true
  end

  local customMouseEvents = self.customMouseEvents[button]
  if customMouseEvents then
    for _, customMouseEvent in ipairs(customMouseEvents) do
      if mapPos.x >= customMouseEvent.fromMapPos.x and
        mapPos.x <= customMouseEvent.toMapPos.x and
        mapPos.y >= customMouseEvent.fromMapPos.y and
        mapPos.y <= customMouseEvent.toMapPos.y and
        (customMouseEvent.ignoreZ or (mapPos.z >= customMouseEvent.fromMapPos.z and
        mapPos.z <= customMouseEvent.toMapPos.z)) then

        customMouseEvent.callback(self, mapPos, pos)
      end
    end
  end

  if button == MouseLeftButton and g_keyboard.isCtrlPressed() and g_keyboard.isShiftPressed() then
    g_game.sendTeleport(mapPos)
  elseif button == MouseLeftButton and g_keyboard.isShiftPressed() then
    local player = g_game.getLocalPlayer()
    if self.autowalk then
      local widgetInfo = self:getWidgetInfoFromPoint(pos)
      if widgetInfo then
        if widgetInfo.type == "party" then
          Party.ChangeView()
        else
          if player then player:autoWalk(widgetInfo.pos) end
        end
      else
        if player then player:autoWalk(mapPos) end
      end
    end
    return true
  elseif button == MouseRightButton then
    local widgetInfo = self:getWidgetInfoFromPoint(pos)
    if widgetInfo then
      local menu = g_ui.createWidget('PopupMenu')
      g_client.setInputLockWidget(nil)
      menu:setGameMenu(true)
      menu:addOption(tr('Delete mark'), function()
        if widgetInfo.fromUIRealMinimap then
          self:removeWidget(widgetInfo.widgetId)
        else
          g_realMinimap.removeWidget(widgetInfo.widgetId)
        end
      end)
      menu:display(pos)
      return true
    end

    local menu = g_ui.createWidget('PopupMenu')
    menu:setGameMenu(true)
    menu:addOption(tr('Create mark'), function() self:createFlagWindow(mapPos) end)
    menu:display(pos)
    return true
  end
  return false
end

function UIRealMinimap:onDragEnter(pos)
  self.dragReference = pos
  self.dragCameraReference = self:getCameraPosition()
  return true
end

function UIRealMinimap:onDragMove(pos, moved)
  local scale = self:getScale()
  local dx = (self.dragReference.x - pos.x)/scale
  local dy = (self.dragReference.y - pos.y)/scale
  local pos = {x = self.dragCameraReference.x + dx, y = self.dragCameraReference.y + dy, z = self.dragCameraReference.z}
  self:setCameraPosition(pos)
  return true
end

function UIRealMinimap:addCustomMouseEvent(buttonType, fromMapPos, toMapPos, callback, ignoreZ)
  self.customMouseEvents = self.customMouseEvents or {}
  self.customMouseEvents[buttonType] = self.customMouseEvents[buttonType] or {}
  table.insert(self.customMouseEvents[buttonType], {fromMapPos = fromMapPos, toMapPos = toMapPos, callback = callback, ignoreZ = ignoreZ})
  return true
end

function UIRealMinimap:onDragLeave(widget, pos)
  return true
end

function UIRealMinimap:onStyleApply(styleName, styleNode)
  for name,value in pairs(styleNode) do
    if name == 'autowalk' then
      self.autowalk = value
    end
  end
end

function UIRealMinimap:createFlagWindow(pos)
  if self.flagWindow then return end
  if not pos then return end


  modules.game_cyclopedia.Cyclopedia.endGame()
  self.flagWindow = g_ui.createWidget('MinimapFlagWindow', rootWidget)
  g_client.setInputLockWidget(self.flagWindow)

  local positionLabel = self.flagWindow:getChildById('position')
  local description = self.flagWindow:getChildById('description')
  local okButton = self.flagWindow:getChildById('okButton')
  local cancelButton = self.flagWindow:getChildById('cancelButton')

  positionLabel:setText(string.format('%i, %i, %i', pos.x, pos.y, pos.z))

  local flagRadioGroup = UIRadioGroup.create()
  for i=0,19 do
    local checkbox = self.flagWindow:getChildById('flag' .. i)
    checkbox.icon = i
    flagRadioGroup:addWidget(checkbox)
  end

  flagRadioGroup:selectWidget(flagRadioGroup:getFirstWidget())

  local successFunc = function()
    modules.game_cyclopedia.toggleRedirect("Map")
    local map = modules.game_cyclopedia.MapCyclopedia.getWidget()
    map:addWidget("data/images/game/minimap/flag"..flagRadioGroup:getSelectedWidget().icon..".png", {width = 11, height = 11}, pos, description:getText())
    self:destroyFlagWindow(pos)
  end

  local cancelFunc = function()
    modules.game_cyclopedia.toggleRedirect("Map")
    self:destroyFlagWindow(pos)
  end

  okButton.onClick = successFunc
  cancelButton.onClick = cancelFunc

  self.flagWindow.onEnter = successFunc
  self.flagWindow.onEscape = cancelFunc

  self.flagWindow.onDestroy = function() flagRadioGroup:destroy() end
end

function UIRealMinimap:destroyFlagWindow(oldPos)
  if self.flagWindow then
    self.flagWindow:destroy()
    self.flagWindow = nil

    if oldPos then
      local map = modules.game_cyclopedia.MapCyclopedia.getWidget()
      map:setCameraPosition(oldPos)
    end
  end
end
