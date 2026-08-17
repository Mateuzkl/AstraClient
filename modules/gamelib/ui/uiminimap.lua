local MIN_ZOOM_LIMIT = -1

function UIMinimap:onCreate()
  self.autowalk = true
end

function UIMinimap:onSetup()
  self.flagWindow = nil
  self.floorUpWidget = self:getChildById('floorUpButton')
  self.floorDownWidget = self:getChildById('floorDownButton')
  self.zoomInWidget = self:getChildById('zoomInButton')
  self.zoomOutWidget = self:getChildById('zoomOutButton')
  self.flags = {}
  self.partyColorMode = 1 -- [0 == hidden, 1 == normal color, 2 == vocation colors
  self:setPartyColorMode(self.partyColorMode)
  self.alternatives = {}
  self.autoWidgets = {}
  self.onAddAutomapFlag = function(pos, icon, description)
    local id = self:addWidget("/data/images/game/minimap/flag"..icon..".png", {width = 11, height = 11}, pos, description)
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

  if self.setMinZoom then
    self:setMinZoom(MIN_ZOOM_LIMIT)
  elseif self.setMixZoom then
    self:setMixZoom(MIN_ZOOM_LIMIT)
  end
end

function UIMinimap:onDestroy()
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
  self.flags = {}
end

function UIMinimap:onVisibilityChange()
  if not self:isVisible() then
    self:destroyFlagWindow()
  end
end

function UIMinimap:onCameraPositionChange(cameraPos)
  if self.cross then
    self:setCrossPosition(self.cross.pos)
  end
end

function UIMinimap:hideFloor()
  if self.floorUpWidget then self.floorUpWidget:hide() end
  if self.floorDownWidget then self.floorDownWidget:hide() end
end

function UIMinimap:hideZoom()
  if self.zoomInWidget then self.zoomInWidget:hide() end
  if self.zoomOutWidget then self.zoomOutWidget:hide() end
end

function UIMinimap:disableAutoWalk()
  self.autowalk = false
end

function UIMinimap:load()
  local settings = g_settings.getNode('Minimap')
  if settings then
    if settings.flags then
      self.flags = settings.flags
      for _,widget in pairs(settings.flags) do
        self:addWidget(widget.imagePath, widget.imageSize, widget.position, widget.description)
      end
    end
    self:setZoom(settings.zoom)
  end
end

function UIMinimap:save()
  local settings = { flags={} }
  for _,widget in pairs(self.flags) do
    table.insert(settings.flags, {
      position = widget.position,
      imagePath = widget.imagePath,
      imageSize = widget.imageSize,
      description = widget.description,
    })
  end
  settings.zoom = self:getZoom()
  g_settings.setNode('Minimap', settings)
end

function UIMinimap:setCrossPosition(pos)
  local cross = self.cross
  if not self.cross then
    cross = g_ui.createWidget('MinimapCross', self)
    cross:setIcon('/images/game/minimap/cross')
    self.cross = cross
  end

  pos.z = self:getCameraPosition().z
  cross.pos = pos
  if pos then
    self:centerInPosition(cross, pos)
  else
    cross:breakAnchors()
  end
end

function UIMinimap:addAlternativeWidget(widget, pos, maxZoom)
  widget.pos = pos
  widget.maxZoom = maxZoom or 0
  widget.minZoom = minZoom
  table.insert(self.alternatives, widget)
end

function UIMinimap:setAlternativeWidgetsVisible(show)
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

function UIMinimap:onZoomChange(zoom)
  for _,widget in pairs(self.alternatives) do
    if (not widget.minZoom or widget.minZoom >= zoom) and widget.maxZoom <= zoom then
      widget:show()
    else
      widget:hide()
    end
  end

  g_tooltip.hide()
end

function UIMinimap:showParty()
  if not self.partyMode:isVisible() then
    self.partyMode:show()
  end
end

function UIMinimap:resetParty()
  self.partyMode:hide()
end

function UIMinimap:switchPartyView(button)
  if self.partyColorMode == 0 then
    self.partyColorMode = 1
    self:setPartyColorMode(self.partyColorMode)
    button:setImageSource("/images/game/minimap/party-vocation-color")
    button:setTooltip("Enable vocation colors")
  elseif self.partyColorMode == 1 then
    self.partyColorMode = 2
    self:setPartyColorMode(self.partyColorMode)
    button:setImageSource("/images/game/minimap/party-hidden")
    button:setTooltip("Hide party members")
  elseif self.partyColorMode == 2 then
    self.partyColorMode = 0
    self:setPartyColorMode(self.partyColorMode)
    button:setImageSource("/images/game/minimap/party-normal-color")
    button:setTooltip("Enable default party colors")
  end
end

function UIMinimap:ViewUpdate(Type)
	return nil
end

function UIMinimap:FloorUpdate(floor)
	for _, widget in pairs(Party.ActivePlayers) do
		if widget.widgetId ~= 0 then
			local pos = widget.pos
			pos.z = floor

      if self.moveWidget then
			  self:moveWidget(widget.widgetId, pos)
      end
		end
	end

	return nil
end

function UIMinimap:reset()
  self:setZoom(0)
  if self.cross then
    self:setCameraPosition(self.cross.pos)
  end
end

function UIMinimap:move(x, y)
  local cameraPos = self:getCameraPosition()
  local scale = self:getScale()
  if scale > 1 then scale = 1 end
  local dx = x/scale
  local dy = y/scale
  local pos = {x = cameraPos.x - dx, y = cameraPos.y - dy, z = cameraPos.z}
  self:setCameraPosition(pos)
end

function UIMinimap:onMouseWheel(mousePos, direction)
  local keyboardModifiers = g_keyboard.getModifiers()
  if direction == MouseWheelUp and keyboardModifiers == KeyboardNoModifier then
    self:zoomIn()
  elseif direction == MouseWheelDown and keyboardModifiers == KeyboardNoModifier then
    self:zoomOut()
  elseif direction == MouseWheelDown and keyboardModifiers == KeyboardCtrlModifier then
    self:floorUp(1)
  elseif direction == MouseWheelUp and keyboardModifiers == KeyboardCtrlModifier then
    self:floorDown(1)
  end
end

function UIMinimap:onMousePress(pos, button)
  if not self:isDragging() then
    self.allowNextRelease = true
  end
end

function UIMinimap:onMouseMove(mousePos, mouseMoved)
    local mapPos = self:getTilePosition(mousePos)
    local mouseBefore = {x = mousePos.x - mouseMoved.x, y = mousePos.y - mouseMoved.y}
    if not mapPos then return end

    if self.onHoverPosition then
        self:onHoverPosition(mapPos)
        local widgetInfo = self:getWidgetInfoFromPoint(mousePos)
        local widgetInfoBefore = self:getWidgetInfoFromPoint(mouseBefore)
        if widgetInfo and not widgetInfoBefore then
          g_tooltip.displayText(widgetInfo.tooltip)
        elseif not widgetInfo and widgetInfoBefore then
          g_tooltip.hide()
        end
    end
end

function UIMinimap:onMouseRelease(pos, button)
  if not self.allowNextRelease then return true end
  self.allowNextRelease = false

  local mapPos = self:getTilePosition(pos)
  if not mapPos then return end

  if button == MouseLeftButton and g_keyboard.isCtrlPressed() and g_keyboard.isShiftPressed() then
    g_game.sendTeleport(mapPos)
  elseif button == MouseLeftButton then
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
      menu:setGameMenu(true)
      menu:addOption(tr('Delete mark'), function()
        if widgetInfo.fromUIRealMinimap then
          self:removeWidget(widgetInfo.widgetId)
        else
          g_minimap.removeWidget(widgetInfo.widgetId)
          RealMap.setIgnoreFlag(widgetInfo.pos)
        end

        local pos = widgetInfo.pos
        for i,widget in pairs(self.flags) do
          if widget.position.x == pos.x and widget.position.y == pos.y and widget.position.z == pos.z then
            self.flags[i] = nil
          end
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

function UIMinimap:getFlagByPos(pos)
  for _,widget in pairs(self.flags) do
    if widget.position.x == pos.x and widget.position.y == pos.y and widget.position.z == pos.z then
      return widget
    end
  end
  return nil
end

function UIMinimap:onDragEnter(pos)
  self.dragReference = pos
  self.dragCameraReference = self:getCameraPosition()
  return true
end

function UIMinimap:onDragMove(pos, moved)
  local scale = self:getScale()
  local dx = (self.dragReference.x - pos.x)/scale
  local dy = (self.dragReference.y - pos.y)/scale
  local pos = {x = self.dragCameraReference.x + dx, y = self.dragCameraReference.y + dy, z = self.dragCameraReference.z}
  self:setCameraPosition(pos)
  return true
end

function UIMinimap:onDragLeave(widget, pos)
  return true
end

function UIMinimap:onStyleApply(styleName, styleNode)
  for name,value in pairs(styleNode) do
    if name == 'autowalk' then
      self.autowalk = value
    end
  end
end

function UIMinimap:createFlagWindow(pos)
  if self.flagWindow then return end
  if not pos then return end

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
    local imagePath = "/data/images/game/minimap/flag"..flagRadioGroup:getSelectedWidget().icon..".png"
    local widgetId = self:addWidget(imagePath, {width = 11, height = 11}, pos, description:getText())
    self.flags[widgetId] = {imagePath = imagePath, imageSize = {width = 11, height = 11}, position = pos, description = description:getText()}
    self:destroyFlagWindow()
  end

  local cancelFunc = function()
    self:destroyFlagWindow()
  end

  okButton.onClick = successFunc
  cancelButton.onClick = cancelFunc

  self.flagWindow.onEnter = successFunc
  self.flagWindow.onEscape = cancelFunc

  self.flagWindow.onDestroy = function() flagRadioGroup:destroy() end
end

function UIMinimap:destroyFlagWindow()
  if self.flagWindow then
    self.flagWindow:destroy()
    self.flagWindow = nil
  end

  g_client.setInputLockWidget(nil)
end
