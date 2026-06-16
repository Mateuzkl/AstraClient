BattleClass = {}
BattleClass.__index = BattleClass

local function setupBattlePanelCompatibility(panel)
  panel.filters = panel.filters or {}
  panel.sortType = panel.sortType or 'byAgeAscending'

  panel.setFilter = panel.setFilter or function(self, filter, value)
    self.filters[filter] = value == nil and true or value
  end

  panel.setSortType = panel.setSortType or function(self, sortType)
    self.sortType = sortType
  end

  panel.getVisibleCreatures = panel.getVisibleCreatures or function(self)
    local creatures = {}
    for _, child in ipairs(self:getChildren()) do
      if (not child.isVisible or child:isVisible()) and child.getCreature then
        local creature = child:getCreature()
        if creature then
          table.insert(creatures, creature)
        end
      end
    end
    return creatures
  end

  panel.getAttackableCreatures = panel.getAttackableCreatures or function(self)
    local creatures = {}
    for _, creature in ipairs(self:getVisibleCreatures()) do
      if not creature.isNpc or not creature:isNpc() then
        table.insert(creatures, creature)
      end
    end
    return creatures
  end
end

function BattleClass:create()
	return setmetatable({
	secondary = false,
	showFilters = true,
	panel = nil,
	filterPanel = nil,
	toggleFilterButton = nil,
	name = "",
	sortType = {
		[1] = "byAgeAscending",
		[2] = "byAgeAscending", -- ??
	},
  buttons = {},
  lastSignature = nil,
	window = nil,
}, BattleClass)
end

function BattleClass:createButton()
  local battleButton = g_ui.createWidget('BattleButton', self.panel)
  if battleButton.setup then
    battleButton:setup()
  end
  battleButton:hide()
  battleButton.onHoverChange = onBattleButtonHoverChange
  battleButton.onMouseRelease = onBattleButtonMouseRelease
  table.insert(self.buttons, battleButton)
  return battleButton
end

function BattleClass:removeButton()
  local battleButton = self.buttons[#self.buttons]
  if battleButton then
    battleButton:destroy()
    battleButton = nil
    table.remove(self.buttons, #self.buttons)
  end
end

function BattleClass:configure(windowId, window)
	if not window then
		self.window = g_ui.createWidget('BattleWindow', m_interface.getContainerPanel())
		self.window:setId("BattleWindow_" .. windowId)
    self.window.battle = self
		self.window:setup()
		self.window:close()
	else
		self.window = window
	end

	self.window.instance = windowId - 1
	self.window.bid = windowId
  local scrollbar = self.window:getChildById('miniwindowScrollBar')
  scrollbar:mergeStyle({ ['$!on'] = { }})

  local battlePanel = self.window:recursiveGetChildById('battlePanel')
  setupBattlePanelCompatibility(battlePanel)
  battlePanel:setFilter("hideOffScreen", true)
  battlePanel.createButton = function()
    return self:createButton()
  end

  self.panel = battlePanel
  self.buttons = {}
  if not self.secondary then
    for i = 1, 30 do
      self:createButton()
    end
  end

  local _filterPanel = self.window:recursiveGetChildById('filterPanel')
  local _toggleFilterButton = self.window:recursiveGetChildById('toggleFilterButton')
  self.toggleFilterButton = _toggleFilterButton

  local _buttons = _filterPanel.buttons
  if _buttons then
    _buttons.bid = windowId
  end

  if isHidingFilters() then
		hideFilterPanel(windowId)
  end

  local sortTypeBox = _filterPanel.sortPanel.sortTypeBox
  local sortOrderBox = _filterPanel.sortPanel.sortOrderBox
  sortTypeBox:setVisible(false)
  sortOrderBox:setVisible(false)


  self.filterPanel = _filterPanel
  self.window:setContentMinimumHeight(86)

  sortTypeBox:addOption('Name', 'name')
  sortTypeBox:addOption('Distance', 'distance')
  sortTypeBox:addOption('Total age', 'age')
  sortTypeBox:addOption('Screen age', 'screenage')
  sortTypeBox:addOption('Health', 'health')

  self.window.onMouseRelease = function(widget, mousePos, mouseButton)
    if mouseButton == MouseRightButton and not g_mouse.isPressed(MouseLeftButton) then
      local child = widget:recursiveGetChildByPos(mousePos)

      -- Se clicar na creature não abre esse menu
      while child and child ~= widget do
        local className = child:getClassName()
        if child.isBattleButton or className == "UIRealCreatureButton" or className == "UICreatureButton" then
          return
        end
        child = child:getParent()
      end

      modules.game_battle.filterPopUp(self.window)
    end
  end

  -- setup
  self.window:setup()
end

function BattleClass:setSecondary(value)
	self.secondary = value
	self.window:setIcon("/images/icons/icon-battlelist" .. (value and '-secondary-widget' or ''))
end

function BattleClass:getWindow()
	return self.window
end

function BattleClass:getToggleFilterButton()
	return self.toggleFilterButton
end

function BattleClass:getFilterPanel()
	return self.filterPanel
end

function BattleClass:showBattle()
	if self.window:isVisible() then
		return false
	end

	self.window:setContentMinimumHeight(86)
	self.window:open()
	return true
end

function BattleClass:close()
	self.window:close()
  self.lastSignature = nil
	return true
end

-- Extra functions
function BattleClass:onFilterPopup()
  local menu = g_ui.createWidget('PopupMenu')
  menu:setGameMenu(true)
  menu:addOption(tr('Edit Name'), function() self:displayEditName() end)
  menu:addOption(tr('Open secondary battle list'), function() addBattleWindow() end)
  if self.secondary then
    menu:addOption(tr('Set as primary battle list'), function() self:setSecondary(true);self:setSecondary(false) end)
  end
  menu:addSeparator()
  menu:addCheckBoxOption(tr('Sort Ascending by Display Time'), function()
    self.panel:setSortType('byAgeAscending')
    self.sortType[1] = 'byAgeAscending'
  end, "", self.sortType[1] == 'byAgeAscending')
  menu:addCheckBoxOption(tr('Sort Descending by Display Time'), function()
    self.panel:setSortType('byAgeDescending')
    self.sortType[1] = 'byAgeDescending'
  end, "", self.sortType[1] == 'byAgeDescending')
  menu:addCheckBoxOption(tr('Sort Ascending by Distance'), function()
    self.panel:setSortType('byDistanceAscending')
    self.sortType[1] = 'byDistanceAscending'
  end, "", self.sortType[1] == 'byDistanceAscending')
  menu:addCheckBoxOption(tr('Sort Descending by Distance'), function()
    self.panel:setSortType('byDistanceDescending')
    self.sortType[1] = 'byDistanceDescending'
  end, "", self.sortType[1] == 'byDistanceDescending')
  menu:addCheckBoxOption(tr('Sort Ascending by Hit Points'), function()
    self.panel:setSortType('byHitpointsAscending')
    self.sortType[1] = 'byHitpointsAscending'
  end, "", self.sortType[1] == 'byHitpointsAscending')
  menu:addCheckBoxOption(tr('Sort Descending by Hit Points'), function()
    self.panel:setSortType('byHitpointsDescending')
    self.sortType[1] = 'byHitpointsDescending'
  end, "", self.sortType[1] == 'byHitpointsDescending')
  menu:addCheckBoxOption(tr('Sort Ascending by Name'), function()
    self.panel:setSortType('byNameAscending')
    self.sortType[1] = 'byNameAscending'
  end, "", self.sortType[1] == 'byNameAscending')
  menu:addCheckBoxOption(tr('Sort Descending by Name'), function()
    self.panel:setSortType('byNameDescending')
    self.sortType[1] = 'byNameDescending'
  end, "", self.sortType[1] == 'byNameDescending')
  menu:display(g_window.getMousePosition())
end

function BattleClass:displayEditName()
	if editNameBattleWindow then
		editNameBattleWindow:destroy()
    editNameBattleWindow = nil
	end


	editNameBattleWindow = g_ui.displayUI("newName")


	local function cancel()
		editNameBattleWindow:hide()
		editNameBattleWindow:destroy()
		editNameBattleWindow = nil
	end
	local function okCallback()
		local text = editNameBattleWindow.contentPanel.newName:getText()
		self:setName(text)
		editNameBattleWindow:hide()
		editNameBattleWindow:destroy()
		editNameBattleWindow = nil
	end

	editNameBattleWindow.onEscape = cancel
	editNameBattleWindow.onEnter = okCallback
	editNameBattleWindow.contentPanel.newName:focus()
	editNameBattleWindow.contentPanel.newName:setText(self.name)

	editNameBattleWindow.contentPanel.cancel.onClick = cancel
	editNameBattleWindow.contentPanel.ok.onClick = okCallback
end

---
function BattleClass:registerInSideBars()
	local configs = {
		battleListFilters = {},
		battleListSortOrder = self.sortType,
		contentHeight = (self.window.minimizeButton:isOn() and 140 or self.window:getHeight()),
		contentMaximized = not self.window.minimizeButton:isOn(),
		isPartyView = false,
		isPrimary = not self.secondary,
		name = self.name,
		showFilters = self.showFilters,
	}

  local hidePlayers = not self.filterPanel.buttons.showPlayers:isChecked()
  local hideNPCs = not self.filterPanel.buttons.showNPCs:isChecked()
  local hideMonsters = not self.filterPanel.buttons.showMonsters:isChecked()
  local hideSkulls = not self.filterPanel.buttons.showNonSkulled:isChecked()
  local hideParty = not self.filterPanel.buttons.showParty:isChecked()
  local hideKnights = not self.filterPanel.buttons.showKnights:isChecked()
  local hidePaladins = not self.filterPanel.buttons.showPaladins:isChecked()
  local hideDruids = not self.filterPanel.buttons.showDruids:isChecked()
  local hideSorceres = not self.filterPanel.buttons.showSorcerers:isChecked()
  local hideMonks = not self.filterPanel.buttons.showMonks:isChecked()
  local hideSummons = not self.filterPanel.buttons.showSummons:isChecked()
  local hideOwnGuilds = not self.filterPanel.buttons.showOwnGuilds:isChecked()
  if hideKnights then
		table.insert(configs.battleListFilters, "hideKnights")
  end
  if hidePaladins then
		table.insert(configs.battleListFilters, "hidePaladins")
  end
  if hideDruids then
		table.insert(configs.battleListFilters, "hideDruids")
  end
  if hideSorceres then
		table.insert(configs.battleListFilters, "hideSorcerers")
  end
  if hideMonks then
		table.insert(configs.battleListFilters, "hideMonks")
  end
  if hidePlayers then
		table.insert(configs.battleListFilters, "hidePlayers")
  end
  if hideNPCs then
		table.insert(configs.battleListFilters, "hideNPCs")
  end
  if hideMonsters then
		table.insert(configs.battleListFilters, "hideMonsters")
  end
  if hideSkulls then
		table.insert(configs.battleListFilters, "hideNonSkulled")
  end
  if hideParty then
		table.insert(configs.battleListFilters, "hideParty")
  end
  if hideOwnGuilds then
		table.insert(configs.battleListFilters, "hideOwnGuilds")
  end
  if hideSummons then
		table.insert(configs.battleListFilters, "hideSummons")
  end

	modules.game_sidebars.registerBattleWindow(tostring(self.window.bid - 1), configs)
end

function BattleClass:setName(newName)
	self.name = newName
	if newName ~= '' then
		self.window:setText(newName)
	else
		self.window:setText(tr('Battle List'))
	end
end
