-- @docclass
UIMiniWindow = extends(UIWindow, "UIMiniWindow")

local miniWidgets = {
  ["BattleWindow"] = "battleListWidget",
  ["vipWindow"] = "vipWidget",
  ["skillWindow"] = "skillsWidget",
  ["preyTracker"] = "preyWidget",
  ["killTracker"] = "preyWidget",
  ["unjustifiedPointsWindow"] = "unjustifiedPoinsWidget",
  ["bossTrackerWindow"] = "bosstiaryTrackerWidget",
  ["imbuementTrackerWindow"] = "imbuementTrackerWidget",
  ["bestiaryTrackerWindow"] = "bestiaryTrackerWidget",
  ["questTracker"] = "questTrackerWidget",
  ["analyserMiniWindow"] = "analyticsSelectorWidget",
  ["spellList"] = "spellListWidget"
}

local function getMiniWidget(id)
  for buttonId, widgetId in pairs(miniWidgets) do
    if string.find(id, buttonId) then
      return widgetId
    end
  end
  return nil
end


function UIMiniWindow.create()
  local miniwindow = UIMiniWindow.internalCreate()
  miniwindow.UIMiniWindowContainer = true
  miniwindow.dragStarted = false
  miniwindow:addSound(ESoundUI.SoundTypeClick, 2785)
  miniwindow:insertLuaCall("onFocusChange")
  return miniwindow
end

function UIMiniWindow:open()
  self:setVisible(true)
  self.isOpen = true
  signalcall(self.onOpen, self)
end

function UIMiniWindow:isOpened()
  return self.isOpen
end

function UIMiniWindow:close()
  if not self:isExplicitlyVisible() then return end
  if self.forceOpen then return end
  self:setVisible(false)

  local miniWidgetParent = getMiniWidget(self:getId())
  if miniWidgetParent and modules.game_sidebuttons then
      local allBattlesClosed = true
      if miniWidgetParent == "battleListWidget" then
          for _, battleClass in ipairs(modules.game_battle.battleClasses) do
              if battleClass.window:getId() == self:getId() then
                  battleClass.window:close()
              end
              if battleClass.window:isVisible() then
                  allBattlesClosed = false
                  break
              end
          end
      end
      if allBattlesClosed or miniWidgetParent ~= "battleListWidget" then
          modules.game_sidebuttons.setButtonVisible(miniWidgetParent, false)
      end
  end

  if self:getId():find("container") then
    g_game.doThing(false)
    g_game.close(self.container)
    g_game.doThing(true)
  elseif self:getId():find("PartyWindow") then
    modules.game_sidebuttons.setButtonVisible("partyWidget", false)
  elseif self:getId() == "lockerSearchWindow" then
    modules.game_search_locker.toggleSearchFocus()
  end


  self.isOpen = false
  signalcall(self.onClose, self)
end

function UIMiniWindow:minimize()
  self:setOn(true)
  if self:getChildById('contentsPanel') then
    self:getChildById('contentsPanel'):hide()
  end
  if self:getChildById('contentPanel') then
    self:getChildById('contentPanel'):hide()
  end

  if self:getChildById('headPanel') then
    self:getChildById('headPanel'):hide()
  end
  if self:getChildById('setupPanel') then
    self:getChildById('setupPanel'):hide()
  end
  if self:getChildById('filterPanel') then
    self:getChildById('filterPanel'):hide()
  end
  if self:recursiveGetChildById('pagePanel') then
    self:recursiveGetChildById('pagePanel'):setHeight(0)
  end
  if self:getChildById('miniwindowScrollBar') then
    self:getChildById('miniwindowScrollBar'):hide()
  end

  if self:getChildById('bottomResizeBorder') then
    self:getChildById('bottomResizeBorder'):hide()
  end

  local miniborder = self:recursiveGetChildById("miniborder")
  if miniborder then
    miniborder:hide()
  end

  if self.minimizeButton then
    self.minimizeButton:setOn(true)
  end
  self.minimized = true
  self.maximizedHeight = self:getHeight()
  self:setHeight(self.minimizedHeight)
end

function UIMiniWindow:maximize()
  self:setOn(false)
  if self:getChildById('contentsPanel') then
    self:getChildById('contentsPanel'):show()
  end
  if self:getChildById('contentPanel') then
    self:getChildById('contentPanel'):show()
  end
  if self:getChildById('miniwindowScrollBar') then
    self:getChildById('miniwindowScrollBar'):show()
  end
  if self:getChildById('bottomResizeBorder') then
    self:getChildById('bottomResizeBorder'):show()
  end
  if self:getChildById('headPanel') then
    self:getChildById('headPanel'):show()
  end
  if self:getChildById('setupPanel') then
    self:getChildById('setupPanel'):show()
  end
  if self:recursiveGetChildById('pagePanel') then
    self:recursiveGetChildById('pagePanel'):setHeight(24)
  end
  if self:getChildById('filterPanel') then
    self:getChildById('filterPanel'):show()
  end

  local miniborder = self:recursiveGetChildById("miniborder")
  if miniborder then
    miniborder:show()
  end

  if self.minimizeButton then
    self.minimizeButton:setOn(false)
  end
  self.minimized = false
  self:setHeight(self.maximizedHeight)

  local parent = self:getParent()
  if parent and parent:getClassName() == 'UIMiniWindowContainer' then
    parent:fitAll(self)
  end
end

function UIMiniWindow:lock()
  local lockButton = self:getChildById('lockButton')
  if lockButton then
    lockButton:setOn(true)
  end
  self:setDraggable(false)
  self:setBorderWidth(1)
  self:setBorderColor('$var-text-cip-store-red')

  signalcall(self.onLockChange, self)
end

function UIMiniWindow:unlock()
  local lockButton = self:getChildById('lockButton')
  if lockButton then
    lockButton:setOn(false)
  end
  self:setDraggable(true)
  self:setBorderWidth(0)
  signalcall(self.onLockChange, self)
end

function UIMiniWindow:setup()
  if self.closeButton then
      self.closeButton.onClick = function() self:close() end
      if self.forceOpen then
          if self.closeButton then
            self.closeButton:hide()
          end
      end
  end

  if(self.minimizeButton) then
    self.minimizeButton.onClick =
      function()
        if self:isOn() then
          self:maximize()
        else
          self:minimize()
        end
      end
  end

  local lockButton = self:getChildById('lockButton')
  if lockButton then
    lockButton.onClick =
      function ()
        if self:isDraggable() then
          self:lock()
        else
          self:unlock()
        end
      end
  end

  local filterBattleButton = self:getChildById('filterBattleButton')
  if filterBattleButton then
      filterBattleButton:setOn(true)
      if(self.onFilter ~= nil) then
        filterBattleButton.onClick = function ()
              signalcall(self.onFilter, self)
          end
      else
        filterBattleButton:hide()
      end
  end

  local extraBattleButton = self:getChildById('extraBattleButton')
  if extraBattleButton then
      if(self.onBattleExtra ~= nil) then
        extraBattleButton.onClick = function ()
              signalcall(self.onBattleExtra, self)
          end
      else
        extraBattleButton:hide()
      end
  end

  local redirectBattleButton = self:getChildById('redirectBattleButton')
  if redirectBattleButton then
      if(self.onBattleRedirect ~= nil) then
        redirectBattleButton.onClick = function ()
              signalcall(self.onBattleRedirect, self)
          end
      else
        redirectBattleButton:hide()
      end
  end

  local extraButton = self:getChildById('extraButton')
  if extraButton then
      if(self.onExtra ~= nil) then
          extraButton.onClick = function ()
              signalcall(self.onExtra, self)
          end
      else
          extraButton:hide()
      end
  end

  local filterButton = self:getChildById('filterContainer')
  if filterButton and not self.containerWindow then
    filterButton:hide()
  end

  local redirectButton = self:getChildById('redirectButton')
  if redirectButton then
      if(self.onRedirect ~= nil) then
          redirectButton.onClick = function ()
              signalcall(self.onRedirect, self)
          end
      else
          redirectButton:hide()
      end
  end

  if self.miniwindowTopBar then
  self.miniwindowTopBar.onDoubleClick =
    function()
      if self:isOn() then
        self:maximize()
      else
        self:minimize()
      end
    end
  end

  if self.bottomResizeBorder then
    self.bottomResizeBorder.onDoubleClick = function()
      self:setHeight(self.bottomResizeBorder:getMinimum())
    end
  end

  local oldParent = self:getParent()

  local settings = {}
  if g_settings.getNodeSize('MiniWindows') < 50 then
    settings = g_settings.getNode('MiniWindows')
  end

  if settings then
    local selfSettings = settings[self:getId()]
    if selfSettings then

      -- Hacky way of keeping buttons enabled when logging in and/or reloading widgets.
      if self:getId() == 'skillWindow' and not selfSettings.closed then
          modules.game_sidebuttons.setButtonVisible("skillsWidget", true)
      end

      if self:getId() == 'battleWindow' and not selfSettings.closed then
          modules.game_sidebuttons.setButtonVisible("battleListWidget", true)
      end

      if self:getId() == 'vipWindow' and not selfSettings.closed then
          modules.game_sidebuttons.setButtonVisible("vipWidget", true)
      end

      if self:getId() == 'spellListWidget' and not selfSettings.closed then
        modules.game_sidebuttons.setButtonVisible("spellListWidget", true)
      end

      if selfSettings.parentId then
        local parent = rootWidget:recursiveGetChildById(selfSettings.parentId)
        if parent then
          if parent:getClassName() == 'UIMiniWindowContainer' and selfSettings.index and parent:isOn() then
            self:setParent(parent, true)
            self.miniIndex = selfSettings.index
            parent:scheduleInsert(self, selfSettings.index)
          elseif selfSettings.position then
            self:setParent(parent, true)
            self:setPosition(topoint(selfSettings.position))
          end
        end
      end

      if selfSettings.minimized then
        self:minimize(true)
      else
        if selfSettings.height and self:isResizeable() then
          self:setHeight(selfSettings.height)
        end
      end
      if selfSettings.closed and not self.multiOpen and not self.forceOpen and not self.containerWindow then
        self:close(true)
      end

      if selfSettings.locked then
        self:lock(true)
      end
    else
      if not self.forceOpen and self.autoOpen ~= nil and (self.autoOpen == 0 or self.autoOpen == false) and not self.containerWindow then
        self:close(true)
      end
    end
  end

  local newParent = self:getParent()

  self.miniLoaded = true

  if self.save then
    if oldParent and oldParent:getClassName() == 'UIMiniWindowContainer' and not self.containerWindow then
      addEvent(function() oldParent:order() end)
    end
    if newParent and newParent:getClassName() == 'UIMiniWindowContainer' and newParent ~= oldParent then
      addEvent(function() newParent:order() end)
    end
  end

  self:fitOnParent()
end

function UIMiniWindow:onVisibilityChange(visible)
  self:fitOnParent()
end

function UIMiniWindow:onDragEnter(mousePos)
  local parent = self:getParent()
  if not parent then return false end

  local lockButton = self:getChildById('lockButton')
  if lockButton and lockButton:isOn() then
    return false
  end

  if parent:getClassName() == 'UIMiniWindowContainer' then
    local containerParent = parent:getParent():getParent()
    parent:removeChild(self)
    containerParent:addChild(self)
  end

  local oldPos = self:getPosition()
  self.movingReference = { x = mousePos.x - oldPos.x, y = mousePos.y - oldPos.y }
  self:setPosition(oldPos)
  self.free = true

  self.dragStarted = true
  return true
end

local function isInArray(table, value)
	for v = 1, #table do
		if table[v] == value then
			return true
		end
	end
return false
end

function UIMiniWindow:onDragLeave(droppedWidget, mousePos)
  local lockButton = self:getChildById('lockButton')
  if lockButton and lockButton:isOn() then
    return false
  end

  if not self.dragStarted then
    return false
  end

  self.dragStarted = false

  local children = rootWidget:recursiveGetChildrenByMarginPos(mousePos)
  local blockToHorizontal = {"inventoryWindow", "analyserMiniWindow", "mainButtonsWindow", "healthInfoWindow", "tradeWindow"}
  local availablePanels = {"gameLeftPanel", "gameRightPanel", "rightPanel2", "rightPanel3", "rightPanel4", "leftPanel1", "leftPanel2", "leftPanel3", "leftPanel4", "horizontalLeftPanel", "horizontalRightPanel"}
  local dropInPanel = 0
  local destWidget
  for i=1,#children do
    local child = children[i]
    if isInArray(availablePanels, child:getId())
      and not (isInArray({"horizontalLeftPanel", "horizontalRightPanel"}, child:getId()) and isInArray(blockToHorizontal, self:getId()))
      then

        if isInArray({"horizontalLeftPanel", "horizontalRightPanel"}, child:getId()) then
          if child:getChildInPanel() == 1 then
            dropInPanel = 1
            destWidget = child
          end
        else
          dropInPanel = 1
          destWidget = child
        end
    end
  end

  if dropInPanel == 0 then
    if not m_interface.addToPanels(self) then
      self:close()
      return false
    end
  end

  if destWidget and destWidget:getEmptySlot(self) < self:getHeight() and destWidget:getEmptySlot(self) < self:getMinimumHeight() and destWidget:getEmptySlot(self) > 10 then
    self:setHeight(destWidget:getEmptySlot(self))
  end

  if self.movedWidget then
    self.setMovedChildMargin(self.movedOldMargin or 0)
    self.movedWidget = nil
    self.setMovedChildMargin = nil
    self.movedOldMargin = nil
    self.movedIndex = nil
  end
  if isInArray({"horizontalLeftPanel", "horizontalRightPanel"}, self:getParent():getId()) then
    self:getParent():setHeight(self:getParent():getHeight() - 5)
  end

  UIWindow:onDragLeave(self, droppedWidget, mousePos)
  if isInArray({"horizontalLeftPanel", "horizontalRightPanel"}, self:getParent():getId()) then
    self:getParent():setHeight(self:getParent():getHeight() + 5)
  end

  if self:getHeight() > self:getParent():getHeight() then
    self:setHeight(self:getParent():getHeight() - 5)
  end
end

function UIMiniWindow:onDragMove(mousePos, mouseMoved)
  local oldMousePosY = mousePos.y - mouseMoved.y
  local children = rootWidget:recursiveGetChildrenByMarginPos(mousePos)
  local overAnyWidget = false
  for i=1,#children do
    local child = children[i]
    if child:getParent():getClassName() == 'UIMiniWindowContainer' then
      overAnyWidget = true

      local childCenterY = child:getY() + child:getHeight() / 2
      if child == self.movedWidget and mousePos.y < childCenterY and oldMousePosY < childCenterY then
        break
      end

      if self.movedWidget then
        self.setMovedChildMargin(self.movedOldMargin or 0)
        self.setMovedChildMargin = nil
      end

      if mousePos.y < childCenterY then
        self.movedOldMargin = child:getMarginTop()
        self.setMovedChildMargin = function(v) child:setMarginTop(v) end
        self.movedIndex = 0
      else
        self.movedOldMargin = child:getMarginBottom()
        self.setMovedChildMargin = function(v) child:setMarginBottom(v) end
        self.movedIndex = 1
      end

      self.movedWidget = child
      self.setMovedChildMargin(self:getHeight())
      break
    end
  end

  if not overAnyWidget and self.movedWidget then
    self.setMovedChildMargin(self.movedOldMargin or 0)
    self.movedWidget = nil
  end

  return UIWindow.onDragMove(self, mousePos, mouseMoved)
end

function UIMiniWindow:onMousePress()
  local parent = self:getParent()
  if not parent then return false end
  if parent:getClassName() ~= 'UIMiniWindowContainer' then
    self:raise()
    return true
  end
end

function UIMiniWindow:onFocusChange(focused)
  if not focused then return end
  local parent = self:getParent()
  if parent and parent:getClassName() ~= 'UIMiniWindowContainer' then
    self:raise()
  end
end

function UIMiniWindow:onHeightChange(height)
  self:fitOnParent()
end

function UIMiniWindow:disableResize()
  if self.bottomResizeBorder then
    self.bottomResizeBorder:disable()
  end
end

function UIMiniWindow:enableResize()
  if self.bottomResizeBorder then
    self.bottomResizeBorder:enable()
  end
end

function UIMiniWindow:fitOnParent()
  local parent = self:getParent()
  if self:isVisible() and parent and parent:getClassName() == 'UIMiniWindowContainer' then
    parent:fitAll(self)
  end
end

function UIMiniWindow:setParent(parent)
  UIWidget.setParent(self, parent)
  self:fitOnParent()
end

function UIMiniWindow:setHeight(height)
  UIWidget.setHeight(self, height)
  signalcall(self.onHeightChange, self, height)
end

function UIMiniWindow:setContentHeight(height)
  local contentsPanel = self:getChildById('contentsPanel')
  local minHeight = contentsPanel:getMarginTop() + contentsPanel:getMarginBottom() + contentsPanel:getPaddingTop() + contentsPanel:getPaddingBottom()

  local resizeBorder = self:getChildById('bottomResizeBorder')
  if resizeBorder then
    resizeBorder:setParentSize(minHeight + height)
  end
end

function UIMiniWindow:getContentHeight()
  local resizeBorder = self:getChildById('bottomResizeBorder')
  if resizeBorder then
    return resizeBorder:getParentSize()
  end

  return 0
end

function UIMiniWindow:setContentMinimumHeight(height)
  local contentsPanel = self:getChildById('contentsPanel')
  local minHeight = contentsPanel:getMarginTop() + contentsPanel:getMarginBottom() + contentsPanel:getPaddingTop() + contentsPanel:getPaddingBottom()

  local resizeBorder = self:getChildById('bottomResizeBorder')
  if resizeBorder then
    resizeBorder:setMinimum(minHeight + height)
  end
end

function UIMiniWindow:setContentMaximumHeight(height)
  local contentsPanel = self:getChildById('contentsPanel')
  local minHeight = contentsPanel:getMarginTop() + contentsPanel:getMarginBottom() + contentsPanel:getPaddingTop() + contentsPanel:getPaddingBottom()

  local resizeBorder = self:getChildById('bottomResizeBorder')
  if resizeBorder then
    resizeBorder:setMaximum(minHeight + height)
  end
end

function UIMiniWindow:getMinimumHeight()
  local resizeBorder = self:getChildById('bottomResizeBorder')
  if not resizeBorder then
    return 0
  end
  return resizeBorder:getMinimum()
end

function UIMiniWindow:getMaximumHeight()
  local resizeBorder = self:getChildById('bottomResizeBorder')
  if not resizeBorder then
    return 0
  end
  return resizeBorder:getMaximum()
end

function UIMiniWindow:isResizeable()
  local resizeBorder = self:getChildById('bottomResizeBorder')
  if not resizeBorder then
    return 0
  end
  return resizeBorder:isExplicitlyVisible() and resizeBorder:isEnabled()
end

function UIMiniWindow:getFilterButton()
	return self:getChildById('filterBattleButton')
end

function UIMiniWindow:getExtraBattleButton()
	return self:getChildById('extraBattleButton')
end

function UIMiniWindow:getRedirectBattleButton()
	return self:getChildById('redirectBattleButton')
end

function UIMiniWindow:getExtraButton()
	return self:getChildById('extraButton')
end

function UIMiniWindow:getRedirectButton()
	return self:getChildById('redirectButton')
end

function UIMiniWindow:getType()
  return self.type
end

function UIMiniWindow:isLocked()
  local lockButton = self:getChildById('lockButton')
  return lockButton and lockButton:isOn()
end
