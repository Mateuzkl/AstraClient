-- Adicionar battle por instancia igual ao Hunting
-- Defaults 20 battle + 1 principal
-- so pode deixar 20 aberto

mainBattleWindow = nil
editNameBattleWindow = nil

mouseWidget = nil

local maxBattleWindow = 21
local battleUpdateEvent = nil
local battleUpdateInterval = 100
local battleAgeNumber = 1
local battleAges = {}
local hoveredCreature = nil
local newHoveredCreature = nil
local prevCreature = nil

local CreatureButtonColors = {
  onIdle = {notHovered = '#afafaf', hovered = '#f7f7f7'},
  onTargeted = {notHovered = '#df3f3f', hovered = '#f7a3a3'},
  onFollowed = {notHovered = '#3fdf3f', hovered = '#b3f7b3'}
}

-- Objects
if not battleClasses then
  battleClasses = {}
end

local keybindOpenBattle = KeyBind:getKeyBind("Windows", "Show/hide battle list")
local keybindOpenSecondaryBattle = KeyBind:getKeyBind("Windows", "Open secondary battle list")

function init()
  g_ui.importStyle('battlebutton')
  g_ui.importStyle('battle')

  keybindOpenBattle:active()
  keybindOpenSecondaryBattle:active()

  mouseWidget = g_ui.createWidget('UIButton')
  mouseWidget:setId('MouseWidget_Battle')
  mouseWidget:setVisible(false)
  mouseWidget:setFocusable(false)
  mouseWidget.cancelNextRelease = false

  battleClasses = {}
  for i = 1, maxBattleWindow, 1 do
    local battleClass = BattleClass.create()
    battleClass:configure(i)
    battleClass:setSecondary(i ~= 1)
    table.insert(battleClasses, battleClass)
  end

  updateBattleList()
end

function terminate()
  keybindOpenBattle:deactive()
  keybindOpenSecondaryBattle:deactive()

  if battleUpdateEvent then
    removeEvent(battleUpdateEvent)
    battleUpdateEvent = nil
  end
  clearBattlePanels()

  mouseWidget:destroy()
end

function toggle()
  local mainBattle = getMainBattle().window
  if mainBattle:isVisible() then
    mainBattle:close()
    modules.game_sidebuttons.setButtonVisible("battleListWidget", false)
  else
    if not mainBattle:getParent() then
      m_interface.getRightPanel():addChild(mainBattle)
    end
    mainBattle:open()
    modules.game_sidebuttons.setButtonVisible("battleListWidget", true)
  end
end

function close()
  local mainBattle = getMainBattle().window
  mainBattle:close()
end

function open()
  local mainBattle = getMainBattle().window
  if not mainBattle:getParent() then
    m_interface.getRightPanel():addChild(mainBattle)
  end
  mainBattle:open()
  modules.game_sidebuttons.setButtonVisible("battleListWidget", true)
end

function onMiniWindowClose(window)
  for _, data in pairs(battleClasses)  do
    if data:getWindow():getId() == window:getId() and window:getId() ~= "battleWindow" then
      data:close()
      break
    end
  end

  local visibleCount = 0
  for _, data in pairs(battleClasses) do
    if data:getWindow() and data:getWindow():isVisible() then
      visibleCount = visibleCount + 1
    end
  end

  if visibleCount == 0 then
    modules.game_sidebuttons.setButtonVisible("battleListWidget", false)
  end
end

function isHidingFilters()
  local settings = g_settings.getNode('BattleList')
  if not settings then
    return false
  end
  return settings['hidingFilters']
end

function setHidingFilters(state)
  settings = {}
  settings['hidingFilters'] = state
  g_settings.mergeNode('BattleList', settings)
end

function hideFilterPanel(id)
  local object = battleClasses[id]
  if not object then
    return
  end

  local filterPanel = object:getFilterPanel()
  local toggleFilterButton = object:getToggleFilterButton()
  if not filterPanel then
	 return
  end

  local battleWindow = object:getWindow()
  object.showFilters = false
  filterPanel.originalHeight = filterPanel:getHeight()
  filterPanel:setHeight(0)
  toggleFilterButton:getParent():setMarginTop(0)
  toggleFilterButton:setImageClip(torect("0 0 21 12"))
  setHidingFilters(true)
  filterPanel:setVisible(false)
  battleWindow:setContentMinimumHeight(56)
  toggleFilterButton:setOn(false)
end

function showFilterPanel(id)
  local object = battleClasses[id]
  if not object then
    return
  end

  local filterPanel = object:getFilterPanel()
  local toggleFilterButton = object:getToggleFilterButton()
  if not filterPanel then
   return
  end

  if filterPanel.originalHeight == 0 then
    filterPanel.originalHeight = 50
  end

  local battleWindow = object:getWindow()
  object.showFilters = true
  toggleFilterButton:getParent():setMarginTop(5)
  filterPanel:setHeight(filterPanel.originalHeight)
  toggleFilterButton:setImageClip(torect("21 0 21 12"))
  setHidingFilters(false)
  filterPanel:setVisible(true)

  toggleFilterButton:setOn(true)
  if battleWindow:getHeight() < 115 then
    battleWindow:setHeight(115)
  end

  battleWindow:setContentMinimumHeight(115)
end

function toggleFilterPanel(self)
  local id = self.bid
  local object = battleClasses[id]
  if not object then
    return
  end

  local filterBattleButton = self:getChildById('filterBattleButton')
  local filterPanel = object:getFilterPanel()
  if not filterPanel then
   return
  end

  if filterPanel:isVisible() then
    filterBattleButton:setOn(false)
    hideFilterPanel(id)
  else
    filterBattleButton:setOn(true)
    showFilterPanel(id)
  end
end

function setSortType(state)
  settings = {}
  settings['sortType'] = state
  g_settings.mergeNode('BattleList', settings)
end

function updateBattleList()
  if battleUpdateEvent then
    removeEvent(battleUpdateEvent)
  end

  battleUpdateEvent = scheduleEvent(updateBattleList, battleUpdateInterval)
  checkCreatures()
end

local function getMapPanel()
  if m_interface and m_interface.getMapPanel then
    return m_interface.getMapPanel()
  end

  if modules.game_interface and modules.game_interface.getMapPanel then
    return modules.game_interface.getMapPanel()
  end

  return nil
end

local function getDistanceBetween(p1, p2)
  return math.max(math.abs(p1.x - p2.x), math.abs(p1.y - p2.y))
end

local function isFilterChecked(battle, id)
  if not battle or not battle.filterPanel or not battle.filterPanel.buttons then
    return true
  end

  local button = battle.filterPanel.buttons:getChildById(id)
  return not button or button:isChecked()
end

local function isSummon(creature)
  if not creature.getType then
    return false
  end

  local creatureType = creature:getType()
  return creatureType == CreatureTypeSummonOwn or creatureType == CreatureTypeSummonOther
end

local function doCreatureFitFilters(battle, creature, player)
  if not creature or creature:isLocalPlayer() or creature:getHealthPercent() <= 0 then
    return false
  end

  local pos = creature:getPosition()
  local playerPos = player:getPosition()
  if not pos or not playerPos or pos.z ~= playerPos.z or not creature:canBeSeen() then
    return false
  end

  if creature:isPlayer() then
    if not isFilterChecked(battle, 'showPlayers') then
      return false
    end
    if not isFilterChecked(battle, 'showNonSkulled') and creature:getSkull() == SkullNone then
      return false
    end
    if not isFilterChecked(battle, 'showParty') and creature:getShield() > ShieldWhiteBlue then
      return false
    end
    if creature.getVocation then
      if not isFilterChecked(battle, 'showKnights') and creature:isKnight() then
        return false
      end
      if not isFilterChecked(battle, 'showPaladins') and creature:isPaladin() then
        return false
      end
      if not isFilterChecked(battle, 'showDruids') and creature:isDruid() then
        return false
      end
      if not isFilterChecked(battle, 'showSorcerers') and creature:isSorcerer() then
        return false
      end
      if not isFilterChecked(battle, 'showMonks') and creature:isMonk() then
        return false
      end
    end
  elseif creature:isNpc() then
    if not isFilterChecked(battle, 'showNPCs') then
      return false
    end
  elseif creature:isMonster() then
    if isSummon(creature) and not isFilterChecked(battle, 'showSummons') then
      return false
    end
    if not isFilterChecked(battle, 'showMonsters') then
      return false
    end
  end

  return true
end

local function sortCreaturesForBattle(battle, creatures, player)
  local sortType = (battle.sortType and battle.sortType[1]) or (battle.panel and battle.panel.sortType) or 'byAgeAscending'
  local descending = sortType:find('Descending') ~= nil

  local function compareValue(a, b)
    if sortType:find('Distance') then
      local playerPos = player:getPosition()
      return getDistanceBetween(playerPos, a:getPosition()), getDistanceBetween(playerPos, b:getPosition())
    elseif sortType:find('Hitpoints') then
      return a:getHealthPercent(), b:getHealthPercent()
    elseif sortType:find('Name') then
      return a:getName():lower(), b:getName():lower()
    end

    return battleAges[a:getId()] or 0, battleAges[b:getId()] or 0
  end

  table.sort(creatures, function(a, b)
    local valueA, valueB = compareValue(a, b)
    if valueA == valueB then
      valueA = battleAges[a:getId()] or 0
      valueB = battleAges[b:getId()] or 0
    end

    if descending then
      return valueA > valueB
    end
    return valueA < valueB
  end)
end

local function updateBattleCreatures(battle, spectators, player)
  if not battle or not battle.panel then
    return
  end

  local buttons = battle.buttons or {}
  local maxCreatures = #buttons
  if maxCreatures == 0 then
    for i = 1, 30 do
      battle:createButton()
    end
    buttons = battle.buttons
    maxCreatures = #buttons
  end

  local creatures = {}
  local now = g_clock.millis()
  local resetAgePoint = now - 250
  for _, creature in ipairs(spectators) do
    if doCreatureFitFilters(battle, creature, player) and #creatures < maxCreatures then
      if not creature.lastSeen or creature.lastSeen < resetAgePoint then
        creature.screenAge = now
      end
      creature.lastSeen = now

      if not battleAges[creature:getId()] then
        if battleAgeNumber > 1000 then
          battleAgeNumber = 1
          battleAges = {}
        end
        battleAges[creature:getId()] = battleAgeNumber
        battleAgeNumber = battleAgeNumber + 1
      end

      table.insert(creatures, creature)
    end
  end

  sortCreaturesForBattle(battle, creatures, player)

  local layout = battle.panel:getLayout()
  if layout and layout.disableUpdates then
    layout:disableUpdates()
  end

  for i = 1, #creatures do
    local button = buttons[i]
    if button then
      button:creatureSetup(creatures[i])
      button:show()
      button:setOn(true)
    end
  end

  for i = #creatures + 1, maxCreatures do
    local button = buttons[i]
    if button then
      button:setCreature(nil)
      button:hide()
    end
  end

  if layout and layout.enableUpdates then
    layout:enableUpdates()
    layout:update()
  end
end

function checkCreatures()
  if not g_game.isOnline() then
    clearBattlePanels()
    return
  end

  local player = g_game.getLocalPlayer()
  local mapPanel = getMapPanel()
  if not player or not mapPanel then
    return
  end

  local dimension = mapPanel:getVisibleDimension()
  local playerPos = player:getPosition()
  if not playerPos then
    return
  end
  local spectators = g_map.getSpectatorsInRangeEx(playerPos, false, math.floor(dimension.width / 2), math.floor(dimension.width / 2), math.floor(dimension.height / 2), math.floor(dimension.height / 2))

  for _, battle in pairs(battleClasses) do
    if not battle.secondary or (battle.window and battle.window:isVisible()) then
      updateBattleCreatures(battle, spectators, player)
    end
  end

  updateBattleButtons()
end

function clearBattlePanels()
  if hoveredCreature then
    hoveredCreature:hideStaticSquare()
  end
  if prevCreature then
    prevCreature:hideStaticSquare()
  end
  hoveredCreature = nil
  newHoveredCreature = nil
  prevCreature = nil

  for _, battle in pairs(battleClasses) do
    for _, button in ipairs(battle.buttons or {}) do
      if button.setCreature then
        button:setCreature(nil)
      else
        button.creature = nil
      end
      button:hide()
      button:setOn(false)
    end
  end
end

function updateBattleButtons()
  for _, battle in pairs(battleClasses) do
    for _, button in ipairs(battle.buttons or {}) do
      if not button:isHidden() and button.update then
        button:update()
      end
    end
  end

  updateSquare()
end

function onBattleButtonHoverChange(battleButton, hovered)
  if not hovered then
    newHoveredCreature = nil
  else
    newHoveredCreature = battleButton.getCreature and battleButton:getCreature() or battleButton.creature
  end

  if battleButton.isHovered ~= hovered then
    battleButton.isHovered = hovered
    if battleButton.update then
      battleButton:update()
    end
  end

  updateSquare()
end

function updateSquare()
  local following = g_game.getFollowingCreature()
  local attacking = g_game.getAttackingCreature()

  if not newHoveredCreature then
    if hoveredCreature then
      hoveredCreature:hideStaticSquare()
      hoveredCreature = nil
    end
  else
    if hoveredCreature then
      hoveredCreature:hideStaticSquare()
    end
    hoveredCreature = newHoveredCreature
    hoveredCreature:showStaticSquare(CreatureButtonColors.onIdle.hovered)
  end

  local color = CreatureButtonColors.onIdle
  local creature = nil
  if attacking then
    color = CreatureButtonColors.onTargeted
    creature = attacking
  elseif following then
    color = CreatureButtonColors.onFollowed
    creature = following
  end

  if prevCreature ~= creature then
    if prevCreature then
      prevCreature:hideStaticSquare()
    end
    prevCreature = creature
  end

  if not creature then
    return
  end

  color = creature == hoveredCreature and color.hovered or color.notHovered
  creature:showStaticSquare(color)
end

-- other functions
function onBattleButtonMouseRelease(self, mousePosition, mouseButton)
  if mouseWidget.cancelNextRelease then
    mouseWidget.cancelNextRelease = false
    return false
  end

  local creature = self:getCreature()
  if creature then
    if ((g_mouse.isPressed(MouseLeftButton) and mouseButton == MouseRightButton) or (g_mouse.isPressed(MouseRightButton) and mouseButton == MouseLeftButton)) then
      mouseWidget.cancelNextRelease = true
      g_game.look(creature, true)
      return true
    elseif mouseButton == MouseLeftButton and g_keyboard.isShiftPressed() then
      g_game.look(creature, true)
      return true
    elseif mouseButton == MouseLeftButton and not g_mouse.isPressed(MouseRightButton) then
      if g_game.getAttackingCreature() == creature then
        modules.game_helper.helperConfig.currentLockedTargetId = 0
        g_game.cancelAttack()
        g_game.attack(nil)
      else
        modules.game_helper.helperConfig.currentLockedTargetId = creature:getId()
        g_game.attack(creature)
      end
      return true
    elseif mouseButton == MouseRightButton and not g_mouse.isPressed(MouseLeftButton) then
      local player = g_game.getLocalPlayer()
      local creatureName = creature:getName()
      local isPlayer = creature:isPlayer()
      local isNpc = creature:isNpc()

      local menu = g_ui.createWidget('PopupMenu')
      menu:setGameMenu(true)

      if not isNpc then
        if g_game.getAttackingCreature() == creature then
          menu:addOption(tr('Stop Attack'), function()  modules.game_helper.helperConfig.currentLockedTargetId = 0; g_game.attack(nil) end)
        else
          menu:addOption(tr('Attack'), function() modules.game_helper.helperConfig.currentLockedTargetId = creature:getId(); g_game.attack(creature) end)
        end
      elseif isNpc then
        menu:addOption(tr('Talk'), function()
          if not m_interface.talkToNpc(creature) then
            return modules.game_textmessage.displayFailureMessage(tr('You are too far away.'))
          end
        end)
      end
      menu:addOption(tr('Follow'), function() g_game.follow(creature) end)
      menu:addOption(tr('Look'), function() g_game.look(creature, true) end)
      if isPlayer then
        menu:addSeparator()
        menu:addOption(tr('Message to ' .. creatureName), function () g_game.openPrivateChannel(creatureName) end)
        if not player:hasVip(creatureName) then
          menu:addOption(tr('Add ' .. creatureName .. ' to VIP list'), function () g_game.addVip(creatureName) end)
        end
        if modules.game_console.Communication:isIgnored(creatureName) then
          menu:addOption(tr('Unignore') .. ' ' .. creatureName, function() modules.game_console.Communication:removeIgnoredPlayer(creatureName) end)
        else
          menu:addOption(tr('Ignore') .. ' ' .. creatureName, function() modules.game_console.Communication:addIgnoredPlayer(creatureName) end)
        end
        local localPlayerShield = player:getShield()
        local creatureShield = creature:getShield()
        if localPlayerShield == ShieldNone or localPlayerShield == ShieldWhiteBlue then
          if creatureShield == ShieldWhiteYellow then
            menu:addOption(tr('Join %s\'s Party', creature:getName()), function() g_game.partyJoin(creature:getId()) end)
          else
            menu:addOption(tr('Invite %s to Party', creature:getName()), function() g_game.partyInvite(creature:getId()) end)
          end
        elseif localPlayerShield == ShieldWhiteYellow then
          if creatureShield == ShieldWhiteBlue then
            menu:addOption(tr('Revoke %s\'s Invitation', creature:getName()), function() g_game.partyRevokeInvitation(creature:getId()) end)
          end
        elseif localPlayerShield == ShieldYellow or localPlayerShield == ShieldYellowSharedExp or localPlayerShield == ShieldYellowNoSharedExpBlink or localPlayerShield == ShieldYellowNoSharedExp then
          if creatureShield == ShieldWhiteBlue then
            menu:addOption(tr('Revoke %s\'s Invitation', creature:getName()), function() g_game.partyRevokeInvitation(creature:getId()) end)
          elseif creatureShield == ShieldBlue or creatureShield == ShieldBlueSharedExp or creatureShield == ShieldBlueNoSharedExpBlink or creatureShield == ShieldBlueNoSharedExp then
            menu:addOption(tr('Pass Leadership to %s', creature:getName()), function() g_game.partyPassLeadership(creature:getId()) end)
          else
            menu:addOption(tr('Invite to Party'), function() g_game.partyInvite(creature:getId()) end)
          end
        end
        menu:addOption(tr('Inspect %s', creature:getName()), function() print("toDo") end)
        menu:addOption(tr('Revoke %s allowance to inspect me', creature:getName()), function() print("toDo") end)
        menu:addSeparator()
        menu:addOption(tr('Report Name'), function() modules.game_report.doReportName(creature:getName()) end)
        menu:addOption(tr('Report Bot/Macro'), function() modules.game_report.doReportMacro(creature:getId(), creature:getName()) end)
        menu:addSeparator()
        menu:addOption(tr('Copy Name'), function () g_window.setClipboardText(creatureName) end)
      else
        menu:addSeparator()
        menu:addOption(tr('Copy Name'), function () g_window.setClipboardText(creatureName) end)
      end

      menu:display(mousePosition)
      return true
    end
  end
  return false
end

function filterPopUp(widget)
  local id = widget.bid
  local object = battleClasses[id]
  if not object then
    return
  end

  object:onFilterPopup()
end

function addBattleWindow()
  for i = 2, maxBattleWindow do
    local data = battleClasses[i]
    if data and data:getWindow() and not data:getWindow():isVisible() and m_interface.addToPanels(data:getWindow()) then
      data:showBattle()
      data:getWindow():getParent():moveChildToIndex(data:getWindow(), data:getWindow():getParent():getChildCount())
      return
    end
  end

  modules.game_textmessage.displayFailureMessage(tr("You cannot open more battle lists."))
end

function updateBattleIconCreatures(widget, checked)
  local displaName = {
    ['showPlayers'] = 'Players',
    ['showNPCs'] = 'NPCs',
    ['showKnights'] = 'Knights',
    ['showPaladins'] = 'Paladins',
    ['showDruids'] = 'Druids',
    ['showSorcerers'] = 'Sorceres',
    ['showMonks'] = 'Monks',
    ['showSummons'] = 'Summons',
    ['showMonsters'] = 'Monsters',
    ['showNonSkulled'] = 'Non-Skulled Players',
    ['showParty'] = 'Party Members',
    ['showOwnGuilds'] = 'Members of Own Guild',
  }

  local name = displaName[widget:getId()]
  if not name then
    return
  end

  local window = widget:getParent():getParent():getParent()
  if not window then return end
  local battle = window.battle
  if not battle then return end
  local panel = window.battle.panel
  if not panel then return end

  panel:setFilter(widget:getId(), checked)

  widget:setTooltip((checked and 'Hide' or 'Show') .. ' ' .. name)
  checkCreatures()
end

function onPlayerLoad(bCondig)
  for id, config in pairs(bCondig) do
    if config.isPartyView then
      goto continue
    end

    local data = battleClasses[id + 1]
    if (data and data:getWindow()) or data.window:isVisible() then
      data:setName(config.name)
      for _, value in pairs(config.battleListFilters) do
        local invertedValue = value:gsub("hide", "show")
        local button = data.filterPanel.buttons:getChildById(invertedValue)
        if button then
        data.panel:setFilter(invertedValue)
          button:setChecked(false)
        end
      end
      data.panel:setSortType(config.battleListSortOrder[1])
      data.sortType[1] = config.battleListSortOrder[1]
      if config.contentMaximized then
        data.window:maximize()
      else
        data.window:minimize()
      end

      scheduleEvent(function() setupBattlePanel(data, id + 1, config.showFilters) end, (id + 1) * 1000, "setupBattlePanel")

      if config.contentHeight < data:getWindow():getMinimumHeight() then
        config.contentHeight = data:getWindow():getMinimumHeight()
      end

      data:getWindow():setHeight(config.contentHeight)
      data.window:setVisible(true)
    end
    ::continue::
  end
end

function setupBattlePanel(data, id, showFilters)
  local filterBattleButton = data.window:getChildById('filterBattleButton')
  local filterPanel = data:getFilterPanel()
  if not filterPanel then
   return
  end
  if not showFilters then
    if not filterPanel:isVisible() then
      return
    end
    hideFilterPanel(id)
    filterBattleButton:setOn(false)
  else
    if filterPanel:isVisible() then
      return
    end
    showFilterPanel(id)
    filterBattleButton:setOn(true)
  end
end

function onPlayerUnload()
  for k, data in pairs(battleClasses) do
    if data and data:getWindow():isOpened() then
      data:registerInSideBars()
    end
  end

  modules.game_party_list.PartyClass:registerInSideBars()
end

function moveBattle(instance, panel, height, minimized)
  local data = battleClasses[instance + 1]

  if (data and data:getWindow()) or data.window:isVisible() then
    local window = data.window

    window:setParent(panel)
    window:open()
    data:showBattle()
    window:maximize()
    window:setHeight(height)

    return window
  end

  return nil
end

function chooseNextCreature()
  if not rootWidget:getChildById("gameRootPanel"):isFocused() then
    return
  end

  local creatures = getMainBattle().panel:getVisibleCreatures()
  local attackedCreature = g_game.getAttackingCreature()
  local nextChild = nil
  local breakNext = false

  local firstAttacked = nil
  for i = 1, #creatures do
    local creature = creatures[i]
    if creature ~= attackedCreature then
      firstAttacked = creature
    end
    if firstAttacked then
      break
    end
  end

  for i = 1, #creatures do
    local creature = creatures[i]

    nextChild = creature
    if breakNext then
      break
    end

    if creature == attackedCreature then
      breakNext = true
      nextChild = firstAttacked
    end
  end

  if not breakNext then
    nextChild = firstAttacked
  end

  if nextChild then
    g_game.attack(nextChild)
    modules.game_helper.helperConfig.currentLockedTargetId = nextChild:getId()
  end
end

function getCreatures()
  return getMainBattle().panel:getVisibleCreatures()
end

function getAttackableCreatures()
  return getMainBattle().panel:getAttackableCreatures()
end

function choosePrevCreature()
  if not rootWidget:getChildById("gameRootPanel"):isFocused() then
    return
  end
  local creatures = getMainBattle().panel:getVisibleCreatures()
  local attackedCreature = g_game.getAttackingCreature()
  local prevChild = nil

  local firstAttacked = nil
  for i = #creatures, 1, -1 do
    local creature = creatures[i]
    if creature ~= attackedCreature then
      firstAttacked = creature
      break
    end
  end

  for i = 1, #creatures do
    local creature = creatures[i]
    if creature == attackedCreature then
      if not prevChild then
        prevChild = firstAttacked
      end
      break
    end
    prevChild = creature
  end

  if prevChild then
    g_game.attack(prevChild)
    modules.game_helper.helperConfig.currentLockedTargetId = prevChild:getId()
  end
end

function getMainBattle()
  for k, data in pairs(battleClasses) do
    if not data.secondary then
      return data
    end
  end

  return battleClasses[1]
end
