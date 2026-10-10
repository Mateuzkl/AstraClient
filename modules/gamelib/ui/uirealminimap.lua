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
  self.markerIndex = MapMarkerIndex.create()
  self.markerIds = {}
  self.markerPool = {}
  self.nextMarkerId = 0
  self.hiddenCatalogMarks = {}
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
    self.autoWidgets[uid] = nil
  end
  connect(g_game, {
    onAddAutomapFlag = self.onAddAutomapFlag,
    onRemoveAutomapFlag = self.onRemoveAutomapFlag,
  })
end

function UIRealMinimap:onDestroy()
  self._closing = true
  if self.markerEvent then removeEvent(self.markerEvent); self.markerEvent = nil end
  for _,widget in pairs(self.alternatives) do
    widget:destroy()
  end
  self.alternatives = {}
  disconnect(g_game, {
    onAddAutomapFlag = self.onAddAutomapFlag,
    onRemoveAutomapFlag = self.onRemoveAutomapFlag,
  })
  self:destroyFlagWindow()
  self.markerPool, self.markerIds, self.markerCatalog = {}, {}, nil
  self.markerIndex = nil
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
        self:addWidget(widget.imagePath, widget.imageSize, widget.position, widget.description or widget.tooltip)
      end
    end
    self:setZoom(tonumber(settings.zoom) or -1)
  end
  -- Flags already received by the HUD remain available when Cyclopedia opens.
  local hud = modules.game_minimap and modules.game_minimap.minimapWidget
  for _, flag in pairs(hud and hud.flags or {}) do
    self:addWidget(flag.imagePath, flag.imageSize, flag.position, flag.description)
  end
  for _, flag in pairs(hud and hud._minimapWidgets or {}) do
    if not flag:isDestroyed() then self:addWidget(flag.imagePath, flag.imageSize, flag.pos, flag.tooltip) end
  end
end

function UIRealMinimap:save()
  local settings = { flags={} }
  for _,widget in pairs(self.markerIndex and self.markerIndex.records or {}) do
    table.insert(settings.flags, {
      position = widget.position,
      imagePath = widget.imagePath,
      imageSize = widget.imageSize,
      description = widget.tooltip,
    })
  end
  settings.zoom = self:getZoom()
  g_settings.setNode('RealMinimap', settings)
end

function UIRealMinimap:addWidget(imagePath, imageSize, pos, tooltip)
  if self:isDestroyed() or not pos or type(imagePath) ~= 'string' then return nil end
  imagePath = imagePath:gsub('^/', '')
  local uid = string.format('%d,%d,%d\0%s\0%s', pos.x, pos.y, pos.z, imagePath, tooltip or '')
  if self.markerIds[uid] then return self.markerIds[uid] end
  self.nextMarkerId = self.nextMarkerId + 1
  local id = self.nextMarkerId
  if not self.markerIndex:insert({id = id, uid = uid, imagePath = imagePath,
      imageSize = imageSize or {width = 11, height = 11},
      position = {x = pos.x, y = pos.y, z = pos.z}, tooltip = tooltip or '', priority = 1}) then return nil end
  self.markerIds[uid] = id
  self:refreshMarks()
  return id
end

function UIRealMinimap:removeWidget(id)
  if not id then return end
  if type(id) == 'string' then self.hiddenCatalogMarks[id] = true
  else
    local record = self.markerIndex.records[id]
    if record then self.markerIds[record.uid] = nil; self.markerIndex:remove(id) end
  end
  self:refreshMarks()
end

function UIRealMinimap:moveWidget(id, pos)
  local record = self.markerIndex.records[id]
  if not record then return end
  local path, size, text = record.imagePath, record.imageSize, record.tooltip
  self:removeWidget(id)
  return self:addWidget(path, size, pos, text)
end

function UIRealMinimap:isWidgetIgnored(path)
  return (self.ignoredMarks or {})[(path or ''):gsub('^/', '')] == true
end

function UIRealMinimap:getWidgetInfoFromPoint(point)
  for _, widget in ipairs(self.markerPool) do
    if widget:isVisible() and widget:containsPoint(point) and widget.marker then
      local r = widget.marker
      return {widgetId = r.id, pos = r.position, imagePath = r.imagePath,
        tooltip = r.tooltip, fromUIRealMinimap = true}
    end
  end
end

function UIRealMinimap:updateVisibleMarkers()
  if self:isDestroyed() then return end
  for _, widget in ipairs(self.markerPool) do widget:hide() end
  local rect, center = self:getPaddingRect(), self:getCameraPosition()
  local first = self:getTilePosition({x = rect.x, y = rect.y})
  local last = self:getTilePosition({x = rect.x + rect.width - 1, y = rect.y + rect.height - 1})
  if not first or not last then return end
  local bounds = {left = first.x, top = first.y, right = last.x, bottom = last.y}
  local limit = 128
  local candidates = self.markerIndex:query(bounds, center.z, center, limit, self.ignoredMarks)
  if self.markerCatalog then
    for _, candidate in ipairs(self.markerCatalog:query(bounds, center.z, center, limit, self.ignoredMarks, self.hiddenCatalogMarks, RealMap.settings.ignoreFlag)) do
      candidates[#candidates + 1] = candidate
    end
    MapMarkerIndex.sortAndTrim(candidates, limit)
  end
  local started, created, more = g_clock.millis(), 0, false
  for i, candidate in ipairs(candidates) do
    local widget = self.markerPool[i]
    if not widget then
      -- Budget creation per dispatcher slice; even a dense world zoom cannot
      -- turn into a 125-widget, hundreds-of-ms callback.
      if created == 16 or g_clock.millis() - started >= 4 then more = true; break end
      widget = g_ui.createWidget('MinimapFlag', self)
      self.markerPool[i] = widget
      created = created + 1
    end
    local record = candidate.record
    if widget.marker ~= record then
      widget:breakAnchors()
      widget:setImageSource('/' .. record.imagePath)
      widget:setSize(record.imageSize)
      widget:setTooltip(record.tooltip)
      widget.marker = record
      self:centerInPosition(widget, record.position)
    end
    widget:show()
  end
  for i = #candidates + 1, #self.markerPool do self.markerPool[i]:hide() end
  if more then self:refreshMarks() end
end

function UIRealMinimap:setCrossPosition(pos)
  if not pos then return end
  pos = {x = pos.x, y = pos.y, z = self:getCameraPosition().z}
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
  self:destroyFlagWindow() -- Hiding a map must never synthesize region clicks.
end

function UIRealMinimap:setCurrentView(view)
  self.currentView = view -- Preserve legacy names such as fullMinimap.
  -- Map opts into floor composition. House previews keep only their selected
  -- surface floor, without changing zoom or enabling live terrain snapshots.
  if not self.surfaceComposite and self.setSurfaceOpacity then self:setSurfaceOpacity(0) end
  if self.setSurfaceMode then self:setSurfaceMode(self.currentView == 'satellite') end
end

function UIRealMinimap:setLevelSeparator(value)
  if self.setSurfaceOpacity then self:setSurfaceOpacity(self.surfaceComposite and math.max(0, math.min(100, value)) / 100 or 0) end
end

function UIRealMinimap:ignoreWidget(imagePath)
  self.ignoredMarks = self.ignoredMarks or {}
  self.ignoredMarks[imagePath:gsub('^/', '')] = true
  self:refreshMarks()
end

function UIRealMinimap:unignoreWidget(imagePath)
  self.ignoredMarks = self.ignoredMarks or {}
  self.ignoredMarks[imagePath:gsub('^/', '')] = nil
  self:refreshMarks()
end

function UIRealMinimap:refreshMarks()
  if self.markerEvent or self:isDestroyed() then return end
  self.markerEvent = scheduleEvent(function()
    self.markerEvent = nil
    if not self:isDestroyed() then self:updateVisibleMarkers() end
  end, 16)
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


  -- Keep the map alive while editing a flag. Rebuilding it on confirmation
  -- loses marker state and schedules a second world-catalog load.
  modules.game_cyclopedia.cyclopediaWindow:hide()
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
    self:addWidget("data/images/game/minimap/flag"..flagRadioGroup:getSelectedWidget().icon..".png", {width = 11, height = 11}, pos, description:getText())
    self:save()
    self:destroyFlagWindow(pos)
  end

  local cancelFunc = function()
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

    if not self._closing and not self:isDestroyed() then
      local window = modules.game_cyclopedia.cyclopediaWindow
      window:show(true); window:raise(); window:focus()
      g_client.setInputLockWidget(window)
      if oldPos then self:setCameraPosition(oldPos) end
    end
  end
end
