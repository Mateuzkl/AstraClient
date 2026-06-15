local order = {"Items", "Bestiary", "Charm", "Map", "Houses", "Character", "Bosstiary", "Boss Slots", "Magical Archive"}
local options = {
  ["Items"] = {icon = "iteminfo", text = "Items", enabled = true, selected = true, assignSpellButton = false, aimTargetBox = false, coinsStatus = false, charmStatus = false, minorCharmStatus = false},
  ["Bestiary"] = {icon = "monsterinfo", text = "Bestiary", enabled = true, assignSpellButton = false, aimTargetBox = false, coinsStatus = true, charmStatus = true, minorCharmStatus = true},
  ["Charm"] =  {icon = "monsterbonusinfo", text = "Charm", enabled = true, assignSpellButton = false, aimTargetBox = false, coinsStatus = true, charmStatus = true, minorCharmStatus = true},
  ["Map"] = {icon = "map", text = "Map", enabled = true, assignSpellButton = false, aimTargetBox = false, coinsStatus = true, charmStatus = false, minorCharmStatus = false},
  ["Houses"] = {icon = "houses", text = "Houses", enabled = true, assignSpellButton = false, aimTargetBox = false, coinsStatus = true, charmStatus = false, minorCharmStatus = false},
  ["Character"] = {icon = "characterinfo", text = "Character", enabled = true, assignSpellButton = false, aimTargetBox = false, coinsStatus = true,  charmStatus = true, minorCharmStatus = true},
  ["Bosstiary"] = {icon = "bosstiary", text = "Bosstiary", enabled = true, assignSpellButton = false, aimTargetBox = false, coinsStatus = false, charmStatus = false, minorCharmStatus = false},
  ["Boss Slots"] =  {icon = "bossslots", text = "Boss Slots", enabled = true, assignSpellButton = false, aimTargetBox = false, coinsStatus = true, charmStatus = false, minorCharmStatus = false},
  ["Magical Archive"] =  {icon = "magicalarchive", text = "Magical Archive", enabled = true, assignSpellButton = true, aimTargetBox = false, coinsStatus = false, charmStatus = false, minorCharmStatus = false},
}

--Verify Buttons
children_visible = true
display_children_visible = true
markShowallMark = true
areaorsub_children_visible = true
--Verify Buttons
buttonspack = {}

Cyclopedia = {}
cyclopediaWindow = nil
cyclopediaOptionsPanel = nil

BestiaryGroups = nil
VisibleCyclopediaPanel = nil

backWidget = nil
backMonster = nil

MinimapViewCheckBox = nil

local selectedOption = nil
local bestiaryTracker = nil
local lastTabSwitchTime = 0

local keybindCycBestiary = KeyBind:getKeyBind("Dialogs", "Open Cyclopedia - Bestiary")
local keybindBestiaryTracker = KeyBind:getKeyBind("Windows", "Show/hide bestiary tracker")

local function getTimeDisplayClip(hour)
  local startX = 62
  local increment = startX / 12
  local x = math.floor(startX + (hour * increment))
  if x > 124 then
    x = x - 124
  end

  return x .. " 0 31 31"
end

function init()
  cyclopediaWindow = g_ui.displayUI('cyclopedia.otui')

  g_ui.importStyle('styles/items')
  g_ui.importStyle('styles/bestiary')
  g_ui.importStyle('styles/charm')
  g_ui.importStyle('styles/map')
  g_ui.importStyle('styles/house')
  g_ui.importStyle('styles/character')
  g_ui.importStyle('styles/bosstiary')
  g_ui.importStyle('styles/bossslot')
  g_ui.importStyle('styles/magicalarchive')

  keybindCycBestiary:active(consolePanel)
  keybindBestiaryTracker:active(consolePanel)

  cyclopediaOptionsPanel = cyclopediaWindow.optionsTabBar

  backWidget = nil
  backMonster = nil

  bestiaryTracker = g_ui.createWidget('BestiaryTracker', m_interface.getRightPanel())
  bestiaryTracker:setup()
  bestiaryTracker:setContentMaximumHeight(100)
  bestiaryTracker:setContentMinimumHeight(47)
  bestiaryTracker:hide()

	cyclopediaWindow:hide()
  connect(g_game, {
    onResourceBalance = Charm.onResourceBalance,
    onInspection = CyclopediaItems.onInspection,
    onItemDetails = CyclopediaItems.onItemDetails,
    onMonsterTrackerData = Bestiary.bestiaryTracker,
    onCharmData = Charm.onCharmData,
    updateBestiaryMonsterData = Bestiary.updateBestiaryMonsterData,
    updateBestiaryGroup = Bestiary.updateBestiaryGroup,
    updateBestiaryOverview = Bestiary.updateBestiaryOverview,
    onBosstiaryBaseData = Bosstiary.onBosstiaryBaseData,
    onBosstiaryWindowData = Bosstiary.onBosstiaryWindowData,
    onBosstiarySlotsData = BosstiarySlot.onBosstiarySlotsData,
    onCyclopediaInspect = Character.onCyclopediaInspect,
    onCyclopediaBaseInformation = Character.onCyclopediaBaseInformation,
    onCyclopediaRecentDeath = Character.showRecentDeaths,
    onCyclopediaPvpDeath = Character.showPvPDeaths,
    onRecvHousesData = House.onRecvHousesData,
    onRecvHouseMessage = House.onRecvHouseMessage,
    onCyclopediaItemSummary = Character.onCyclopediaItemSummary,
    onCyclopediaAppearances = Character.onCyclopediaAppearances,
    onCyclopediaOffence = Character.onCyclopediaOffence,
    onCyclopediaDefence = Character.onCyclopediaDefence,
    onCyclopediaMisc = Character.onCyclopediaMisc,
    onCyclopediaAchievements = Character.onCyclopediaAchievements,
    onCyclopediaTitles = Titles.parseData,
    onServerTime = Cyclopedia.onServerTime,

    onGameStart = Cyclopedia.startGame,
    onGameEnd = Cyclopedia.endGame
  })

  connect(LocalPlayer, {
    onPositionChange = MapCyclopedia.updatePlayerPosition
  })

  if initCyclopediaProtocol then
    initCyclopediaProtocol()
  end
  if initBosstiaryProtocol then
    initBosstiaryProtocol()
  end

  for id, v in ipairs(order) do
    local info = options[v]
    local widget = g_ui.createWidget('CyclopediaOptions', cyclopediaOptionsPanel)
    widget:setId(id)
    local size = {width = widget.icon:getImageWidth(), height = widget.icon:getImageHeight()}
    local size2 = {width = widget.image:getImageWidth(), height = widget.image:getImageHeight()}
    widget:setEnabled(info.enabled)
    widget.icon:setSize(size)
    widget.image:setSize(size2)
    widget.icon:setImageSource('images/icons/icon-cyclopedia-'..info.icon)
    widget.image:setImageSource('images/icons/icon-cyclopedia-'..info.icon)
    widget.category:setText(info.text)
    if info.selected then
      onOptionChange(widget)
    end
  end

  if g_game.isOnline() then
    Cyclopedia.startGame()
  end
end

function terminate()
  if terminateCyclopediaProtocol then
    terminateCyclopediaProtocol()
  end
  if terminateBosstiaryProtocol then
    terminateBosstiaryProtocol()
  end

	cyclopediaWindow:hide()
  selectedOption = nil
  searchFilterCharmText = ''
  for _, child in pairs(cyclopediaOptionsPanel:getChildren()) do
    child:destroy()
    child = nil
  end

  g_keyboard.unbindKeyPress('Tab', toggleNextWindow, cyclopediaWindow)
  g_keyboard.unbindKeyPress('Shift+Tab', togglePreviousWindow, cyclopediaWindow)

  keybindCycBestiary:deactive(consolePanel)
  keybindBestiaryTracker:deactive(consolePanel)

  npcValueCheckBox = nil
  marketValueCheckBox = nil
  backWidget = nil
  backMonster = nil
  MonsterList = {}
  listMonsters = {}
  listMonsterShow = {}
  marketItems = {}

  MinimapViewCheckBox = nil

  cyclopediaOptionsPanel = nil
  if VisibleCyclopediaPanel then
    for _, widget in pairs(VisibleCyclopediaPanel:getChildren()) do
      widget:destroy()
      widget = nil
    end
  end

  VisibleCyclopediaPanel = nil
  BestiaryGroups = nil

  local bestiaryTrackerList = bestiaryTracker:getChildById('contentsPanel')
  if bestiaryTrackerList then
    bestiaryTrackerList:destroyChildren()
  end

  if bestiaryTracker then
    bestiaryTracker:destroy()
  end

  bestiaryTracker = nil

  disconnect(g_game, {
    onResourceBalance = Charm.onResourceBalance,
    onInspection = CyclopediaItems.onInspection,
    onItemDetails = CyclopediaItems.onItemDetails,
    onCharmData = Charm.onCharmData,
    onMonsterTrackerData = Bestiary.bestiaryTracker,
    updateBestiaryGroup = Bestiary.updateBestiaryGroup,
    updateBestiaryOverview = Bestiary.updateBestiaryOverview,
    onBosstiaryBaseData = Bosstiary.onBosstiaryBaseData,
    onBosstiaryWindowData = Bosstiary.onBosstiaryWindowData,
    onBosstiarySlotsData = BosstiarySlot.onBosstiarySlotsData,
    onCyclopediaInspect = Character.onCyclopediaInspect,
    onCyclopediaBaseInformation = Character.onCyclopediaBaseInformation,
    onCyclopediaRecentDeath = Character.showRecentDeaths,
    onCyclopediaPvpDeath = Character.showPvPDeaths,
    onRecvHousesData = House.onRecvHousesData,
    onRecvHouseMessage = House.onRecvHouseMessage,
    onCyclopediaItemSummary = Character.onCyclopediaItemSummary,
    onCyclopediaAppearances = Character.onCyclopediaAppearances,
    onCyclopediaOffence = Character.onCyclopediaOffence,
    onCyclopediaDefence = Character.onCyclopediaDefence,
    onCyclopediaMisc = Character.onCyclopediaMisc,
    onCyclopediaAchievements = Character.onCyclopediaAchievements,
    onCyclopediaTitles = Titles.parseData,
    onServerTime = Cyclopedia.onServerTime,

    onGameStart = Cyclopedia.startGame,
    onGameEnd = Cyclopedia.endGame
  })

  disconnect(LocalPlayer, {
    onPositionChange = MapCyclopedia.updatePlayerPosition
  })
end

function Cyclopedia.run()
	cyclopediaWindow:setOn(true)
	cyclopediaWindow:open()
end

function Cyclopedia.onServerTime(hour, minute)
  if not VisibleCyclopediaPanel then
    return
  end

  local centerMap = VisibleCyclopediaPanel:recursiveGetChildById('centerMap')
  if centerMap then
    centerMap:setImageClip(getTimeDisplayClip(hour))
  end
end

function Cyclopedia:open()
  if cyclopediaWindow:isHidden() then
    cyclopediaWindow:show(true)
    cyclopediaWindow:raise()
    cyclopediaWindow:focus()
  end

  g_client.setInputLockWidget(cyclopediaWindow)
  searchFilterCharmText = ''
  if VisibleCyclopediaPanel then
    for _, widget in pairs(VisibleCyclopediaPanel:getChildren()) do
      widget:destroy()
      widget = nil
    end
  end

  for id, child in pairs(cyclopediaOptionsPanel:getChildren()) do
    if child.category:getText() == 'Items' then
      onOptionChange(child)
      break
    end
  end

  g_keyboard.bindKeyPress('Tab', toggleNextWindow, cyclopediaWindow)
  g_keyboard.bindKeyPress('Shift+Tab', togglePreviousWindow, cyclopediaWindow)
end

function toggle()
  if cyclopediaWindow:isVisible() then
    local minimap = VisibleCyclopediaPanel:recursiveGetChildById('minimap')
    if minimap then
        minimap:onHide()
    end
    Cyclopedia.endGame()
    g_keyboard.unbindKeyPress('Tab', toggleNextWindow, cyclopediaWindow)
    g_keyboard.unbindKeyPress('Shift+Tab', togglePreviousWindow, cyclopediaWindow)
  else
    Cyclopedia:open()
  end
end

function hide()
  Cyclopedia.endGame()
end

function toggleRedirect(action, raceId)
  if action == "Bestiary" then
    Cyclopedia:open()
    for _, child in pairs(cyclopediaOptionsPanel:getChildren()) do
      if child.category:getText() == action then
        onOptionChange(child)
        break
      end
    end
    g_game.bestiaryMonsterData(raceId)
  elseif action == "Bosstiary" then
    local monsterName = getCyclopediaMonster(raceId)
    if monsterName then
      Bosstiary.onSideButtonRedirect(monsterName[1])
    end
  elseif action == "Character" then
    Cyclopedia:open()
    for _, child in pairs(cyclopediaOptionsPanel:getChildren()) do
      if child.category:getText() == action then
        onOptionChange(child)
        break
      end
    end
  elseif action == "Charm" then
    Cyclopedia:open()
    for _, child in pairs(cyclopediaOptionsPanel:getChildren()) do
      if child.category:getText() == action then
        onOptionChange(child)
        break
      end
    end
  elseif action == "Items" then
    Cyclopedia:open()
    for _, child in pairs(cyclopediaOptionsPanel:getChildren()) do
      if child.category:getText() == action then
        onOptionChange(child)
        break
      end
    end
  elseif action == "Map" then
    Cyclopedia:open()
    onOptionChange(cyclopediaOptionsPanel:recursiveGetChildById('4'))
  end
end

function toggleTracker()
  if bestiaryTracker:isVisible() then
    bestiaryTracker:hide()
  else
    bestiaryTracker:show()
  end
end

function onOptionChange(widget)
  RegisterBackButton(onOptionChange, widget)
  local bntstatus = options[widget.category:getText()]
  cyclopediaWindow.refreshButton:setVisible(false)

  if not selectedOption or selectedOption ~= widget:getId() then
    widget:setWidth(200)
    widget.category:setVisible(true)
    widget:setImageSource('/images/ui/2pixel-up-frame-borderimage-upside-down')
    widget:setImageClip("1 1 98 98")
    widget.icon:setVisible(false)
    widget.image:setVisible(true)
    cyclopediaWindow.coinsStatus:setVisible(bntstatus.coinsStatus)
    cyclopediaWindow.charmStatus:setVisible(bntstatus.charmStatus)
    cyclopediaWindow.minorCharmStatus:setVisible(bntstatus.minorCharmStatus)
    cyclopediaWindow.assignSpellButton:setVisible(bntstatus.assignSpellButton)
    cyclopediaWindow.aimTargetBox:setVisible(bntstatus.aimTargetBox)

    if widget.category:getText() == "Houses" then
      cyclopediaWindow.coinsStatus.imageGold:setImageSource('/game_cyclopedia/images/ui/bank')
      cyclopediaWindow.coinsStatus.imageGold:setMarginTop(3)
    else
      cyclopediaWindow.coinsStatus.imageGold:setImageSource('/game_cyclopedia/images/ui/gold')
      cyclopediaWindow.coinsStatus.imageGold:setMarginTop(5)
    end
  end

  if VisibleCyclopediaPanel then
    cyclopediaWindow.bestiarytrackerButton:setVisible(false)
    VisibleCyclopediaPanel:destroyChildren()
  end

  selectedOption = widget:getId()
  for _, child in pairs(cyclopediaOptionsPanel:getChildren()) do
    if selectedOption ~= child:getId() then
      child:setWidth(34)
      child.category:setVisible(false)
      child:setImageSource('images/ui/buttons')
      child:setImageClip("0 0 43 20")
      child.icon:setVisible(true)
      child.image:setVisible(false)
    end
  end

  -- functions
  if widget.category:getText() == 'Boss Slots' then
    VisibleCyclopediaPanel = g_ui.createWidget('BossslotGroupPanel', cyclopediaWindow.optionsBossslotPanel)
    VisibleCyclopediaPanel:setId('BossslotGroupPanel')
    BosstiarySlot.requestData()
  elseif widget.category:getText() == 'Bosstiary' then
    VisibleCyclopediaPanel = g_ui.createWidget('BosstiaryGroupPanel', cyclopediaWindow.optionsPanel)
    VisibleCyclopediaPanel:setId('BosstiaryGroupPanel')
    Bosstiary.reset()
    Bosstiary.requestData()
  elseif widget.category:getText() == 'Character' then
    VisibleCyclopediaPanel = g_ui.createWidget('CharacterDataPanel', cyclopediaWindow.optionsCharacterPanel)
    VisibleCyclopediaPanel:setId('CharacterDataPanel')
    Character.loadLocalPlayerData()

    -- Request resources
    g_game.requestResource(ResourceBank)
    g_game.requestResource(ResourceInventary)
    g_game.requestResource(ResourceCharmBalance)
    g_game.requestResource(ResourceEchoeBalance)
    g_game.requestResource(ResourceMaxCharmBalance)
    g_game.requestResource(ResourceMaxEchoeBalance)

    -- Request windows
    g_game.requestCyclopediaData(0)
    g_game.requestCyclopediaData(2)
    g_game.requestCyclopediaData(9)

    scheduleEvent(function() Character.initMainWindow() end, 200)
  elseif widget.category:getText() == 'Houses' then
    VisibleCyclopediaPanel = g_ui.createWidget('HouseGroupPanel', cyclopediaWindow.optionsBosstiaryPanel)
    VisibleCyclopediaPanel:setId('HouseGroupPanel')
    House.resetWindow()
    g_game.requestResource(ResourceBank)
    modules.game_cyclopedia.House.refresh()
    cyclopediaWindow.refreshButton:setVisible(true)
    g_game.sendHouseAction(0, "")
  elseif widget.category:getText() == 'Map' then
    MapCyclopedia.setup()
    addButtonsToElementsMarks()
  elseif widget.category:getText() == 'Bestiary' then
    VisibleCyclopediaPanel = g_ui.createWidget('BestiaryGroupPanel', cyclopediaWindow.optionsPanel)
    VisibleCyclopediaPanel:setId('bestiaryGroupPanel')
    Bestiary.reset()
    g_game.openCyclopedia()
    Charm:requestData()
    backWidget = widget
    cyclopediaWindow.bestiarytrackerButton:setVisible(true)
    cyclopediaWindow.optionsPanel:focus()
    VisibleCyclopediaPanel:focus()
  elseif widget.category:getText() == 'Charm' then
    VisibleCyclopediaPanel = g_ui.createWidget('CharmDataPanel', cyclopediaWindow.optionsPanel)
    VisibleCyclopediaPanel:setId('charmDataPanel')
    Charm:requestData()
  elseif widget.category:getText() == 'Items' then
    VisibleCyclopediaPanel = g_ui.createWidget('ItemDataPanel', cyclopediaWindow.optionsPanel)
    cyclopediaWindow.bestiarytrackerButton:setVisible(false)
    VisibleCyclopediaPanel:setId('itemDataPanel')
    CyclopediaItems.showCategories()
    cyclopediaWindow.optionsPanel:focus()
  elseif widget.category:getText() == 'Magical Archive' then
    VisibleCyclopediaPanel = g_ui.createWidget('MagicalArchiveDataPanel', cyclopediaWindow.optionsPanel)
    cyclopediaWindow.bestiarytrackerButton:setVisible(false)
    VisibleCyclopediaPanel:setId('MagicalArchiveDataPanel')
    MagicalArchive.showSpellList()
    cyclopediaWindow.optionsPanel:focus()
  else
    VisibleCyclopediaPanel = nil
  end
end

function Cyclopedia.startGame()
  local benchmark = g_clock.millis()
  RealMap.load()
  CyclopediaItems.loadItems()
  CyclopediaItems.loadJson()

  MagicalArchive.loadJson()
  consoleln("Cyclopedia loaded in " .. (g_clock.millis() - benchmark) / 1000 .. " seconds.")
end

function Cyclopedia.endGame()
  -- RealMap.unload()
  g_client.setInputLockWidget(nil)
  m_interface.getRootPanel():focus()
  cyclopediaWindow:hide()
  searchFilterCharmText = ''
  if VisibleCyclopediaPanel then
    VisibleCyclopediaPanel:destroy()
  end

  if MapCyclopedia.askWindow then
    MapCyclopedia.askWindow:destroy()
    MapCyclopedia.askWindow = nil
  end
  VisibleCyclopediaPanel = nil
  Bosstiary.reset()
  Charm:reset()
  CyclopediaItems.terminate()
  MagicalArchive.saveJson()
end

function toggleDisplayChildren()
  local display = g_ui.getRootWidget():recursiveGetChildById('display')

  if not display then
      return
  end

  local miniButtonDisplay = g_ui.getRootWidget():recursiveGetChildById('miniButtonDisplay')

  for _, child in pairs(display:getChildren()) do
      if child:isVisible() then
          display_children_visible = true
      else
          display_children_visible = false
      end
  end

  if display_children_visible then
      for _, child in pairs(display:getChildren()) do
            child:setVisible(false)
      end
      miniButtonDisplay:setImageClip("99 1 12 12")
      display:setHeight(19)
  else
      for _, child in pairs(display:getChildren()) do
          child:setVisible(true)
      end
      miniButtonDisplay:setImageClip("99 29 12 12")
      display:setHeight(253)
  end
end

function toggleNavigationChildren()
  local navigation = g_ui.getRootWidget():recursiveGetChildById('navigation')

  if not navigation then
      return
  end

  local miniButton = g_ui.getRootWidget():recursiveGetChildById('miniButton')

  for _, child in pairs(navigation:getChildren()) do
      if child:isVisible() then
          children_visible = true
      else
          children_visible = false
      end
  end

  if children_visible then
      for _, child in pairs(navigation:getChildren()) do
        if child:getId() ~= 'miniButton' then
            child:setVisible(false)
        end
    end
      miniButton:setImageClip("99 1 12 12")
      navigation:setHeight(19)
  else
      for _, child in pairs(navigation:getChildren()) do
          child:setVisible(true)
      end
      miniButton:setImageClip("99 29 12 12")
      navigation:setHeight(97)
  end
end

function toggleAreaOrSubChildren()
  local areaorsub = g_ui.getRootWidget():recursiveGetChildById('areaorsub')

  if not areaorsub then
      return
  end

  local miniButtonArea = g_ui.getRootWidget():recursiveGetChildById('miniButtonArea')

  for _, child in pairs(areaorsub:getChildren()) do
      if child:isVisible() then
        areaorsub_children_visible = true
      else
        areaorsub_children_visible = false
      end
  end

  if areaorsub_children_visible then
      for _, child in pairs(areaorsub:getChildren()) do
            child:setVisible(false)
      end
      miniButtonArea:setImageClip("99 1 12 12")
      areaorsub:setHeight(19)
  else
      for _, child in pairs(areaorsub:getChildren()) do
          child:setVisible(true)
      end
      miniButtonArea:setImageClip("99 29 12 12")
      areaorsub:setHeight(201)
  end
end

function addButtonsToElementsMarks()
  local elementsMarks = g_ui.getRootWidget():recursiveGetChildById('elementsMarks')
  if not elementsMarks then
      return
  end

  for i = 1, 23 do
      local newButton = g_ui.createWidget('markButton', elementsMarks)
      newButton:setId('marksButton' .. i)
      newButton:setIcon('/images/game/minimap/icon/'..i)

      newButton.onClick = function()
          modules.game_cyclopedia.MapCyclopedia.onChangeButtonMarks(newButton, i)
      end
  end
end

function toggleDisplayShowAll()
  local markShowall = g_ui.getRootWidget():recursiveGetChildById('markShowall')

  if not markShowall then return end
    if markShowallMark then
      for i = 1, 23 do
          local button = g_ui.getRootWidget():recursiveGetChildById('marksButton' .. i)
          if button then
            button:setImageClip("0 20 43 20")
            MapCyclopedia.onChangeButtonMarks(button, i)
          end

      end
      markShowall:setChecked(true)
      markShowallMark = false
    else
      for i = 1, 23 do
        local button = g_ui.getRootWidget():recursiveGetChildById('marksButton' .. i)
        if button then
          button:setImageClip("0 0 43 20")
          MapCyclopedia.onChangeButtonMarks(button, i)
        end
      end

      markShowall:setChecked(false)
      markShowallMark = true
    end
end

function toggleNextWindow()
  local currentTime = g_clock.millis()
  if currentTime - lastTabSwitchTime < 200 then
    return
  end
  lastTabSwitchTime = currentTime

  local widgetList = {
    "Items",
    "Bestiary",
    "Charm",
    "Map",
    "Houses",
    "Character",
    "Bosstiary",
    "Boss Slots",
    "Magical Archive"
  }

  local selected = tonumber(selectedOption)
  local nextWidgetId = (selected == #widgetList and 1 or selectedOption + 1)
  if nextWidgetId == 4 then
    nextWidgetId = 5
  end
  onOptionChange(cyclopediaOptionsPanel:recursiveGetChildById(nextWidgetId))
end

function togglePreviousWindow()
  local currentTime = g_clock.millis()
  if currentTime - lastTabSwitchTime < 200 then
    return
  end
  lastTabSwitchTime = currentTime

  local widgetList = {
    "Items",
    "Bestiary",
    "Charm",
    "Map",
    "Houses",
    "Character",
    "Bosstiary",
    "Boss Slots",
    "Magical Archive"
  }

  local selected = tonumber(selectedOption)
  local previousWidgetId = (selected == 1 and #widgetList or selectedOption - 1)
  if previousWidgetId == 4 then
    previousWidgetId = 3
  end
  onOptionChange(cyclopediaOptionsPanel:recursiveGetChildById(previousWidgetId))
end

function onRedirectToStore()
  g_client.setInputLockWidget(nil)
  cyclopediaWindow:hide()
  g_game.openStore()
end
