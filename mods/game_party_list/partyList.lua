partyList = nil

local partyUpdateInterval = 200
local partyUpdateEvent = nil

function init()
  g_ui.importStyle('partyList')
  partyList = g_ui.createWidget('PartyListWindow', m_interface.getContainerPanel())
  partyList:setup()
  partyList:close()
  partyList:setId('PartyWindow')

  PartyClass:configure()
  PartyClass:setup(1, partyList)

  connect(g_game, {
    onGameStart = online,
    onGameEnd = offline,
    onUpdateMana = onUpdateMana,
  })

  if g_game.isOnline() then
    online()
  end
end

function terminate()
  if partyUpdateEvent then
    removeEvent(partyUpdateEvent)
    partyUpdateEvent = nil
  end

  if partyList then
    partyList:destroy()
    partyList = nil
  end

  disconnect(g_game, {
      onGameStart = online,
      onGameEnd = offline,
      onUpdateMana = onUpdateMana,
    })
end

function toggle()
  if partyList:isVisible() then
    partyList:close()
  else
    partyList:open()
    partyList:setup()
    if m_interface.addToPanels(partyList) then
      if partyList:getParent() then
        partyList:getParent():moveChildToIndex(partyList, #partyList:getParent():getChildren())
      end
      local filterBattleButton = partyList:getChildById('filterBattleButton')
      local filterPanel = partyList:recursiveGetChildById('filterPanel')
      if filterPanel and not filterPanel:isVisible() then
        filterBattleButton:setOn(false)
      end
    end
  end
end

function hide()
  partyList:close()
end

function show()
  partyList:open()
  partyList:setup()
end

function filterPopUp()
  PartyClass:onFilterPopup()
end

function onMiniWindowClose()
  modules.game_sidebuttons.setButtonVisible("partyWidget", false)
end

function setHidingFilters(state)
  settings = {}
  settings['hidingFilters'] = state
  g_settings.mergeNode('BattleList', settings)
end

function hideFilterPanel(id)
  local filterPanel = partyList:recursiveGetChildById('filterPanel')
  local toggleFilterButton = PartyClass:getToggleFilterButton()
  if not filterPanel then
	 return
  end

  local battleWindow = partyList
  PartyClass.showFilters = false
  filterPanel.originalHeight = 50
  filterPanel:setHeight(0)
  toggleFilterButton:getParent():setMarginTop(0)
  toggleFilterButton:setImageClip(torect("0 0 21 12"))
  setHidingFilters(true)
  filterPanel:setVisible(false)
  battleWindow:setContentMinimumHeight(56)
  toggleFilterButton:setOn(false)
end

function showFilterPanel(id)
  local filterPanel = partyList:recursiveGetChildById('filterPanel')
  local toggleFilterButton = PartyClass:getToggleFilterButton()
  if not filterPanel then
   return
  end

  local battleWindow = partyList
  PartyClass.showFilters = true
  toggleFilterButton:getParent():setMarginTop(5)
  filterPanel:setHeight(50)
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
  local filterBattleButton = self:getChildById('filterBattleButton')
  local filterPanel = PartyClass:getFilterPanel()
  if not filterPanel then
   return
  end

  if filterPanel:isVisible() then
    filterBattleButton:setOn(false)
    hideFilterPanel(id)
    self:getChildById('separator'):setVisible(false)
  else
    filterBattleButton:setOn(true)
    showFilterPanel(id)
    self:getChildById('separator'):setVisible(true)
  end
end

function onPlayerLoad(config)
  if not config then
    partyList:setup()
    return
  end

  if table.empty(config) then
    config = {
      ["name"] = "Party List",
      ["contentHeight"] = 0,
      ["showFilters"] = false,
      ["contentMaximized"] = true,
      ["battleListFilters"] = {},
      ["battleListSortOrder"] = {
        [1] = "byAgeAscending",
        [2] = "byAgeAscending",     -- ??
      }
    }
  end

  PartyClass:setName(config.name)
  for _, value in pairs(config.battleListFilters) do
    if value == "hidePlayerSummons" then
      value = "hideSummons"
    elseif value == "showPlayerSummons" then
      value = "showSummons"
    end

    PartyClass.panel:setFilter(value)
  end

  for _, value in pairs(config.battleListFilters) do
    local invertedValue = value:gsub("hide", "show")
    local button = partyList:recursiveGetChildById('filterPanel').buttons:getChildById(invertedValue)
    if button then
    PartyClass.panel:setFilter(invertedValue)
      button:setChecked(false)
    end
  end

  PartyClass.panel:setSortType(config.battleListSortOrder[1])
  PartyClass.sortType[1] = config.battleListSortOrder[1]

  if config.contentMaximized then
    partyList:maximize()
  else
    partyList:minimize()
  end
  if not m_interface.addToPanels(partyList) then
    modules.game_sidebuttons.setButtonVisible("partyWidget", false)
    return
  end

  if partyList:isVisible() then
    modules.game_sidebuttons.setButtonVisible("partyWidget", true)
  end

  partyList:getParent():moveChildToIndex(partyList, #partyList:getParent():getChildren())
  scheduleEvent(function() setupPartyPanel(config.showFilters) end, 2000, "setupParty")
  if config.contentHeight < partyList:getMinimumHeight() then
    config.contentHeight = partyList:getMinimumHeight()
  end
  partyList:setHeight(config.contentHeight)
  partyList:setup()
end

function setupPartyPanel(showFilters)
  local filterBattleButton = partyList:getChildById('filterBattleButton')
  local filterPanel = partyList:recursiveGetChildById('filterPanel')
  if not filterPanel then
   return
  end
  if not showFilters then
    if not filterPanel:isVisible() then
      return
    end
    filterBattleButton:setOn(false)
    hideFilterPanel()
  else
    if filterPanel:isVisible() then
      return
    end
    filterBattleButton:setOn(true)
    showFilterPanel()
  end
end

function move(panel, height, minimized)
  partyList:setParent(panel)
  partyList:open()
  partyList:maximize()
  partyList:setHeight(height)

  return partyList
end

-- The donor client's party panel was a C++ creature panel that populated its
-- own rows; this panel is plain Lua, so we poll like battle.lua's
-- checkCreatures loop. Runs while online even with the window closed:
-- helper.lua's friend healing reads panel:getPartyCreatures() regardless of
-- visibility. Documented limitation: party members the client knows only via
-- 0x8B full-creature updates but that are not on a known map tile (off-screen)
-- are not listed.
local function isFilterChecked(id)
  local filterPanel = PartyClass.filterPanel
  if not filterPanel or not filterPanel.buttons then
    return true
  end

  local button = filterPanel.buttons:getChildById(id)
  return not button or button:isChecked()
end

local function doCreatureFitPartyFilters(creature)
  -- Players only: a party member's summon arrives as CreatureTypeSummonOwn with
  -- the master id discarded at parse, so summons can't be attributed to the
  -- party client-side and the showSummons checkbox stays inert.
  if not creature:isPlayer() or creature:getHealthPercent() <= 0 then
    return false
  end

  -- Includes the local player, matching the real Tibia party list.
  if not creature.isPartyMember or not creature:isPartyMember() then
    return false
  end

  if not isFilterChecked('showPlayers') then
    return false
  end

  if creature.getVocation then
    if not isFilterChecked('showKnights') and creature:isKnight() then
      return false
    end
    if not isFilterChecked('showPaladins') and creature:isPaladin() then
      return false
    end
    if not isFilterChecked('showDruids') and creature:isDruid() then
      return false
    end
    if not isFilterChecked('showSorcerers') and creature:isSorcerer() then
      return false
    end
    if not isFilterChecked('showMonks') and creature:isMonk() then
      return false
    end
  end

  return true
end

local function sortPartyCreatures(creatures, player)
  local sortType = PartyClass.sortType[1] or 'byAgeAscending'
  local descending = sortType:find('Descending') ~= nil

  local kind = 0 -- 0 = age (default)
  local playerPos
  if sortType:find('Distance') then
    kind = 1
    playerPos = player:getPosition()
  elseif sortType:find('Hitpoints') then
    kind = 2
  elseif sortType:find('Name') then
    kind = 3
  end

  local function valueOf(c)
    if kind == 1 then
      local pos = c:getPosition()
      if not pos or not playerPos then
        return 9999
      end
      return math.max(math.abs(playerPos.x - pos.x), math.abs(playerPos.y - pos.y))
    elseif kind == 2 then
      return c:getHealthPercent()
    elseif kind == 3 then
      return c:getName():lower()
    end
    return PartyClass.ages[c:getId()] or 0
  end

  table.sort(creatures, function(a, b)
    local valueA, valueB = valueOf(a), valueOf(b)
    if valueA == valueB then
      valueA = PartyClass.ages[a:getId()] or 0
      valueB = PartyClass.ages[b:getId()] or 0
    end

    if descending then
      return valueA > valueB
    end
    return valueA < valueB
  end)
end

local function clearPartyButtons(fromIndex)
  for i = fromIndex or 1, #(PartyClass.buttons or {}) do
    local button = PartyClass.buttons[i]
    if button.setCreature then
      button:setCreature(nil)
    else
      button.creature = nil
    end
    button:hide()
    button:setOn(false)
  end
end

function checkPartyMembers()
  if not PartyClass.panel or not PartyClass.buttons then
    return
  end

  local localPlayer = g_game.getLocalPlayer()
  if not g_game.isOnline() or not localPlayer or not localPlayer:isPartyMember() then
    clearPartyButtons()
    return
  end

  local creatures = {}
  for _, creature in ipairs(g_map.getSpectators(localPlayer:getPosition(), true)) do
    if doCreatureFitPartyFilters(creature) then
      if not PartyClass.ages[creature:getId()] then
        if PartyClass.ageNumber > 1000 then
          PartyClass.ageNumber = 1
          PartyClass.ages = {}
        end
        PartyClass.ages[creature:getId()] = PartyClass.ageNumber
        PartyClass.ageNumber = PartyClass.ageNumber + 1
      end
      table.insert(creatures, creature)
    end
  end

  -- The loop runs every 200ms even when the window is closed, because helper
  -- friend-healing reads PartyClass.panel:getPartyCreatures() (which is sourced
  -- from button.creature) regardless of visibility. So the creature->button
  -- assignment below must happen always, but the *visual* work (sort, the HP/mana/
  -- skull/emblem widget refresh in creatureSetup, show/setOn, layout relayout) is
  -- wasted while hidden and is skipped there.
  local visible = partyList and partyList:isVisible()

  while #PartyClass.buttons < #creatures do
    PartyClass.panel.createButton()
  end

  if visible then
    sortPartyCreatures(creatures, localPlayer)

    -- Batch the per-button widget mutations behind a single relayout, like
    -- modules/game_battle/battle.lua does for its creature buttons.
    local layout = PartyClass.panel:getLayout()
    if layout and layout.disableUpdates then
      layout:disableUpdates()
    end

    for i = 1, #creatures do
      local button = PartyClass.buttons[i]
      -- If this button was last touched by the lightweight hidden path, its
      -- button.creature is already set but the outfit/name widgets were NOT
      -- refreshed; creatureSetup gates those behind `self.creature ~= creature`,
      -- so force the gate open once to repaint them on the first visible tick.
      if button.partyVisualStale then
        button.creature = nil
        button.partyVisualStale = nil
      end
      -- creatureSetup refreshes HP/mana/skull/emblem every tick, which also
      -- covers 0x8C health updates and 0x91 leader shield changes.
      button:creatureSetup(creatures[i])
      if button:isHidden() then
        button:show()
      end
      if not button:isOn() then
        button:setOn(true)
      end
    end

    if layout and layout.enableUpdates then
      layout:enableUpdates()
      layout:update()
    end
  else
    -- Hidden: keep button.creature in sync (this is what getPartyCreatures reads)
    -- but skip every widget mutation. setCreature only assigns the field. Mark the
    -- button so the next visible tick knows to repaint the outfit/name widgets.
    for i = 1, #creatures do
      local button = PartyClass.buttons[i]
      if button.setCreature then
        button:setCreature(creatures[i])
      else
        button.creature = creatures[i]
      end
      button.partyVisualStale = true
    end
  end

  clearPartyButtons(#creatures + 1)
end

function updatePartyList()
  if partyUpdateEvent then
    removeEvent(partyUpdateEvent)
  end

  partyUpdateEvent = scheduleEvent(updatePartyList, partyUpdateInterval)
  checkPartyMembers()
end

function online()
  updatePartyList()
end

function offline()
  if partyUpdateEvent then
    removeEvent(partyUpdateEvent)
    partyUpdateEvent = nil
  end
  clearPartyButtons()
end

function getUpcomingPartyMembers()
  local localPlayer = g_game.getLocalPlayer()
  local players = {}
  for _, creature in pairs(PartyClass.panel:getPartyCreatures()) do
    local creaturePosition = creature:getPosition() or {x = 0xFFFF, y = 0xFFFF, z = 0}
    if Position.distance(creaturePosition, localPlayer:getPosition()) <= 9 then
      table.insert(players, creature)
    end
  end
  return players
end

function onUpdateMana(creatureId, manaPercent)
  for _, creature in pairs(PartyClass.panel:getPartyCreatures()) do
    if creatureId == creature:getId() then
      creature:setManaPercent(manaPercent)
      break
    end
  end
end
