-- @docclass
UIMoveableTabBar = extends(UIWidget, "UIMoveableTabBar")

-- private functions
local function onTabClick(tab)
  tab.tabBar:selectTab(tab)
end

local function updateMargins(tabBar)
  if #tabBar.tabs == 0 then return end

  local currentMargin = 0
  for i = 1, #tabBar.tabs do
    tabBar.tabs[i]:setMarginLeft(currentMargin)
    currentMargin = currentMargin + tabBar.tabSpacing + tabBar.tabs[i]:getWidth()
  end
end

local function updateNavigation(tabBar)
  if tabBar.prevNavigation then
    local preHidden = 0
    for _, tab in pairs(tabBar.preTabs) do
      if not tab:isVisible() then
        preHidden = preHidden + 1
      end
    end

    tabBar.prevNavigation:setVisible(preHidden > 0)
  end

  if tabBar.nextNavigation then
    local postHidden = 0
    for _, tab in pairs(tabBar.postTabs) do
      if not tab:isVisible() then
        postHidden = postHidden + 1
      end
    end

    tabBar.nextNavigation:setVisible(postHidden > 0)
  end
end

local function updateIndexes(tabBar, tab, xoff, movementX)
  local tabs = tabBar.tabs
  local prevIndex = table.find(tabs, tab)
  local newIndex = prevIndex
  local xmid = xoff + tab:getWidth() / 2
  local currentMargin = 0

  for i = 1, #tabs do
    local otherTab = tabs[i]
    if otherTab ~= tab then
      local otherMid = 0
      if movementX < 0 then
        otherMid = currentMargin + otherTab:getWidth() / 1
      else
        otherMid = currentMargin + otherTab:getWidth() / 2
      end

      if movementX > 0 and i > prevIndex and xmid >= otherMid then
        newIndex = i
      elseif movementX < 0 and i < prevIndex and xmid <= otherMid then
        newIndex = i
        break
      end
    end
    currentMargin = currentMargin + tabBar.tabSpacing * (i - 1) + otherTab:getWidth()
  end

  if newIndex ~= prevIndex then
    table.remove(tabs, prevIndex)
    table.insert(tabs, newIndex, tab)

    if tabBar.onIndexChange then
      tabBar.onIndexChange(prevIndex, newIndex)
    end
  end

  updateNavigation(tabBar)
end

local function getMaxMargin(tabBar, tab)
  if #tabBar.tabs == 0 then return 0 end

  local maxMargin = 0
  for i = 1, #tabBar.tabs do
    if tabBar.tabs[i] ~= tab then
      maxMargin = maxMargin + (tabBar.tabs[i]:getWidth())
    end
  end

  local currentMargin = 0
  if tabBar.tabToDrag then
    currentMargin = 185
  end

  return (maxMargin + tabBar.tabSpacing * (#tabBar.tabs - 1)) + currentMargin
end

local function getMaxDragMargin(tabBar, tab)
  return tabBar:getSize().width
end

local function updateTabs(tabBar)
  if #tabBar.postTabs > 0 then
    local i = 1
    while i <= #tabBar.postTabs do
      local tab = tabBar.postTabs[i]
      if getMaxMargin(tabBar) + tab:getWidth() > tabBar:getWidth() then
        break
      end

      table.remove(tabBar.postTabs, i)
      table.insert(tabBar.tabs, tab)
      tab:setVisible(true)
    end
  end
  if #tabBar.preTabs > 0 then
    for i = #tabBar.preTabs, 1, -1 do
      local tab = tabBar.preTabs[i]
      if getMaxMargin(tabBar) + tab:getWidth() > tabBar:getWidth() then
        break
      end

      table.remove(tabBar.preTabs, i)
      table.insert(tabBar.tabs, 1, tab)
      tab:setVisible(true)
    end
  end
  updateNavigation(tabBar)
  updateMargins(tabBar)
  if not tabBar.currentTab and #tabBar.tabs > 0 then
    tabBar:selectTab(tabBar.tabs[1])
  end
end

local function hideTabs(tabBar, fromBack, toArray, width)
  while #tabBar.tabs > 0 and getMaxMargin(tabBar) + width > tabBar:getWidth() do
    local index = fromBack and #tabBar.tabs or 1
    local tab = tabBar.tabs[index]
    table.remove(tabBar.tabs, index)
    if fromBack then
      table.insert(toArray, 1, tab)
    else
      table.insert(toArray, tab)
    end
    if tabBar.currentTab == tab then
      if #tabBar.tabs > 0 then
        tabBar:selectTab(tabBar.tabs[#tabBar.tabs])
      else
        tabBar.currentTab:setChecked(false)
        tabBar.currentTab = nil
      end
    end
    tab:setVisible(false)
  end
end

local function showPreTab(tabBar)
  if #tabBar.preTabs == 0 then
    return nil
  end

  local tmpTab = tabBar.preTabs[#tabBar.preTabs]
  hideTabs(tabBar, true, tabBar.postTabs, tmpTab:getWidth())

  table.remove(tabBar.preTabs, #tabBar.preTabs)
  table.insert(tabBar.tabs, 1, tmpTab)
  tmpTab:setVisible(true)
  return tmpTab
end

local function showPostTab(tabBar)
  if #tabBar.postTabs == 0 then
    return nil
  end

  local tmpTab = tabBar.postTabs[1]
  hideTabs(tabBar, false, tabBar.preTabs, tmpTab:getWidth())

  table.remove(tabBar.postTabs, 1)
  table.insert(tabBar.tabs, tmpTab)
  tmpTab:setVisible(true)
  return tmpTab
end

local function onTabMouseRelease(tab, mousePos, mouseButton)
  if mouseButton == MouseRightButton then
    if tab.menuCallback then tab.menuCallback(tab, mousePos, mouseButton) end
    return true
  end
end

local function onTabDragEnter(tab, mousePos)
  if not focus then tab.tabBar:selectTab(tab) end
  tab:raise()
  tab.hotSpot = mousePos.x - tab:getMarginLeft()
  tab.tabBar.selected = tab
  return true
end

local function onTabDrop(widget, draggedWidget, mousePos)
  signalcall(widget.onTabDrop, widget, draggedWidget, mousePos)
end

local function onTabDragLeave(tab)
  updateMargins(tab.tabBar)
  tab.tabBar.selected = nil

  -- checar se tiver algum parent que aceite o drag
  if tab.tabBar.tabDraggable then
    local widgets = g_ui.getRootWidget():recursiveGetChildrenByPos(g_window.getMousePosition())
    for key, value in pairs(widgets) do
      if value:getId() == tab.tabBar.tabToDrag then
        onTabDrop(tab.tabBar, tab, value, g_window.getMousePosition())
        return true
      end
    end
  end

  return true
end

local function onTabDragMove(tab, mousePos, mouseMoved)
  if tab == tab.tabBar.selected then
    local xoff = mousePos.x - tab.hotSpot

    updateIndexes(tab.tabBar, tab, xoff, mouseMoved.x)
    updateMargins(tab.tabBar)

    xoff = math.max(xoff, 0)
    if tab.tabBar.tabDraggable then
      xoff = math.min(xoff, getMaxDragMargin(tab.tabBar, tab))
    else
      xoff = math.min(xoff, getMaxMargin(tab.tabBar, tab))
    end
    tab:setMarginLeft(xoff)
  end
end

local function tabBlink(tab, step, noBlink)
  if noBlink then
    tab:setOn(false)
    tab.blinking = false
	return false
  end
  local step = step or 0
  if not tab:setOn() then
    tab:setColor('#f7f7f7')
  end
  removeEvent(tab.blinkEvent)
  if step < 1 then
    tab.blinkEvent = scheduleEvent(function() tabBlink(tab, step+1) end, 1000)
  else
    tab:setOn(true)
    tab.blinkEvent = nil
  end
end

-- public functions
function UIMoveableTabBar.create()
  local tabbar = UIMoveableTabBar.internalCreate()
  tabbar:setFocusable(false)
  tabbar.tabs = {}
  tabbar.selected = nil  -- dragged tab
  tabbar.tabSpacing = 0
  tabbar.tabsMoveable = false
  tabbar.tabDraggable = false
  tabbar.tabToDrag = ''
  tabbar.preTabs = {}
  tabbar.postTabs = {}
  tabbar.prevNavigation = nil
  tabbar.nextNavigation = nil
  tabbar:insertLuaCall("onGeometryChange")
  tabbar:insertLuaCall("onDestroy")
  tabbar.onGeometryChange = function()
                              hideTabs(tabbar, true, tabbar.postTabs, 0)
                              updateTabs(tabbar)
                            end
  return tabbar
end

function UIMoveableTabBar:onDestroy()
  if self.prevNavigation then
    self.prevNavigation:disable()
  end

  if self.nextNavigation then
    self.nextNavigation:disable()
  end

  self.nextNavigation = nil
  self.prevNavigation = nil
end

function UIMoveableTabBar:setContentWidget(widget)
  self.contentWidget = widget
  if #self.tabs > 0 then
    self.contentWidget:addChild(self.tabs[1].tabPanel)
  end
end

function UIMoveableTabBar:setTabSpacing(tabSpacing)
  self.tabSpacing = tabSpacing
  updateMargins(self)
end

function UIMoveableTabBar:updateNavigation()
  updateNavigation(self)
end

function UIMoveableTabBar:addTab(text, panel, menuCallback)
  if panel == nil then
    panel = g_ui.createWidget(self:getStyleName() .. 'Panel')
    panel:setId('tabPanel')
  end

  local tab = g_ui.createWidget(self:getStyleName() .. 'Button', self)
  panel.isTab = true
  tab.tabPanel = panel
  tab.tabBar = self
  tab:setId('tab')
  tab:setDraggable(self.tabsMoveable)
  tab:setText(text)
  if text:len() > 13 then
	  tab:setWidth(tab:getTextSize().width + 10)
  else
	  tab:setWidth(tab.tabWidth)
  end
  tab.menuCallback = menuCallback or nil
  tab.onClick = onTabClick
  tab.onMouseRelease = onTabMouseRelease
  tab.onDragEnter = onTabDragEnter
  tab.onDragLeave = onTabDragLeave
  tab.onDragMove = onTabDragMove
  tab:insertLuaCall("onDestroy")
  tab.onDestroy = function()
    local panel = tab.tabPanel
    tab.tabPanel = nil
    if panel and not panel:isDestroyed() then panel:destroy() end
  end

  if #self.tabs == 0 then
    self:selectTab(tab)
    tab:setMarginLeft(0)
    table.insert(self.tabs, tab)
  else
    local newMargin = self.tabSpacing * #self.tabs
    for i = 1, #self.tabs do
      newMargin = newMargin + self.tabs[i]:getWidth()
    end
    tab:setMarginLeft(newMargin)

    hideTabs(self, true, self.postTabs, tab:getWidth())
    table.insert(self.tabs, tab)
    if #self.tabs == 1 then
      self:selectTab(tab)
    end
    updateMargins(self)
  end

  updateNavigation(self)
  return tab
end

-- Additional function to move the tab by lua
function UIMoveableTabBar:moveTab(tab, units)
  local index = table.find(self.tabs, tab)
  if index == nil then return end

  local focus = false
  if self.currentTab == tab then
    self:selectPrevTab()
    focus = true
  end

  table.remove(self.tabs, index)

  local newIndex = math.min(#self.tabs+1, math.max(index + units, 1))
  table.insert(self.tabs, newIndex, tab)
  if focus then self:selectTab(tab) end
  updateMargins(self)
  return newIndex
end

function UIMoveableTabBar:onStyleApply(styleName, styleNode)
  if styleNode['movable'] then
    self.tabsMoveable = styleNode['movable']
  end
  if styleNode['tab-spacing'] then
    self:setTabSpacing(styleNode['tab-spacing'])
  end

  if styleNode['tab-draggable'] then
    self.tabDraggable = styleNode['tab-draggable']
  end

  if styleNode['tab-todrag'] then
    self.tabToDrag = styleNode['tab-todrag']
  end
end

function UIMoveableTabBar:clearTabs()
  while #self.tabs > 0 do
    self:removeTab(self.tabs[#self.tabs])
  end
end

function UIMoveableTabBar:removeTab(tab)
  local tabTables = {self.tabs, self.preTabs, self.postTabs}
  local index = nil
  local tabTable = nil
  for i = 1, #tabTables do
    index = table.find(tabTables[i], tab)
    if index ~= nil then
      tabTable = tabTables[i]
      break
    end
  end

  if tabTable == nil then
    return
  end
  table.remove(tabTable, index)
  if self.currentTab == tab then
    self:selectPrevTab()
    if #self.tabs == 1 then
      self.currentTab = nil
    end
  end
  if tab.blinkEvent then
    removeEvent(tab.blinkEvent)
  end
  updateTabs(self)
  tab:destroy()
end

function UIMoveableTabBar:getTab(text)
  for k,tab in pairs(self.tabs) do
    local tabText = tab:getText()
    if tab:getTooltip() then
      tabText = tab:getTooltip()
    end


    if tabText:lower() == text:lower() then
      return tab
    end
  end
  for k,tab in pairs(self.preTabs) do
    local tabText = tab:getText()
    if tab:getTooltip() then
      tabText = tab:getTooltip()
    end

    if tabText:lower() == text:lower() then
      return tab
    end
  end
  for k,tab in pairs(self.postTabs) do
    local tabText = tab:getText()
    if tab:getTooltip() then
      tabText = tab:getTooltip()
    end

    if tabText:lower() == text:lower() then
      return tab
    end
  end
end

function UIMoveableTabBar:getTabs()
  return self.tabs
end

function UIMoveableTabBar:selectTab(tab)
  if self.currentTab == tab then return end

  -- reject tab nil
  if not tab then return end
  if self.contentWidget then
    local selectedWidget = self.contentWidget:getLastChild()
    if selectedWidget and selectedWidget.isTab then
      self.contentWidget:removeChild(selectedWidget)
    end
    if tab.tabPanel then
      self.contentWidget:addChild(tab.tabPanel)
      tab.tabPanel:fill('parent')
      tab.tabPanel:show()
    end
  end

  if self.currentTab and self.currentTab.tabPanel then
    self.currentTab.tabPanel:hide()
    self.currentTab:setChecked(false)
  end
  signalcall(self.onTabChange, self, tab)
  self.currentTab = tab
  tab:setChecked(true)
  tab:setOn(false)
  tab.blinking = false

  if tab.blinkEvent then
    removeEvent(tab.blinkEvent)
    tab.blinkEvent = nil
  end

  local parent = tab:getParent()
  if parent then
    parent:focusChild(tab, MouseFocusReason)
  end
  updateNavigation(self)
end

function UIMoveableTabBar:selectNextTab()
  if self.currentTab == nil then
    return
  end

  local index = table.find(self.tabs, self.currentTab)
  if index == nil then
    return
  end

  local newIndex = index + 1
  if newIndex > #self.tabs then
    if #self.postTabs > 0 then
      local widget = showPostTab(self)
      self:selectTab(widget)
    else
      if #self.preTabs > 0 then
        for i = 1, #self.preTabs do
          showPreTab(self)
        end
      end

      self:selectTab(self.tabs[1])
    end
    updateTabs(self)
    return
  end

  local nextTab = self.tabs[newIndex]
  if not nextTab then
    return
  end

  self:selectTab(nextTab)
end

function UIMoveableTabBar:selectPrevTab()
  if self.currentTab == nil then
    return
  end

  local index = table.find(self.tabs, self.currentTab)
  if index == nil then
    return
  end

  local newIndex = index - 1
  if newIndex <= 0 then
    if #self.preTabs > 0 then
      local widget = showPreTab(self)
      self:selectTab(widget)
    else
      if #self.postTabs > 0 then
        for i = 1, #self.postTabs do
          showPostTab(self)
        end
      end

      self:selectTab(self.tabs[#self.tabs])
    end
    updateTabs(self)
    return
  end

  local prevTab = self.tabs[newIndex]
  if not prevTab then
    return
  end

  self:selectTab(prevTab)
end

function UIMoveableTabBar:blinkTab(tab, noBlink)
  if tab:isChecked() then return end
  if tab.blinking then
    return
  end
  tab.blinking = true
  tabBlink(tab, 0, noBlink)
end

function UIMoveableTabBar:getTabPanel(tab)
  return tab.tabPanel
end

function UIMoveableTabBar:getCurrentTabPanel()
  if self.currentTab then
    return self.currentTab.tabPanel
  end
end

function UIMoveableTabBar:getCurrentTab()
  return self.currentTab
end

function UIMoveableTabBar:setNavigation(prevButton, nextButton)
  self.prevNavigation = prevButton
  self.nextNavigation = nextButton

  if self.prevNavigation then
    self.prevNavigation.onClick = function() self:selectPrevTab() end
  end
  if self.nextNavigation then
    self.nextNavigation.onClick = function() self:selectNextTab() end
  end
  updateNavigation(self)
end
