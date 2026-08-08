Bestiary = {}
Bestiary.__index = Bestiary

local BestiaryGroups = {}
local MonsterList = {}
local overviewPage = 1
local monsterListPage = 1
local BESTIARY_MONSTER_ID = 0
local monsterTracked = {}
local MasteryCount = 0
local selectedCharm = 0
local BestiaryMonster
local MonsterId = 0
local CurrentLevel = 0
local renderEvent = nil
local renderGeneration = 0

local function setItemRarityFrame(widget, itemOrId)
  if ItemsDatabase and ItemsDatabase.setRarityItem then
    ItemsDatabase.setRarityItem(widget, itemOrId)
  end
end

local function cancelRender()
  if renderEvent then
    removeEvent(renderEvent)
    renderEvent = nil
  end
  renderGeneration = renderGeneration + 1
end

function Bestiary.cancelPendingEvents()
  cancelRender()
end

local function beginRender()
  cancelRender()
  return renderGeneration
end

local function isCurrentRender(generation, panel, panelId)
  return generation == renderGeneration and panel and not panel:isDestroyed() and
    panel == VisibleCyclopediaPanel and panel:getId() == panelId
end

local function scheduleRender(callback)
  renderEvent = scheduleEvent(function()
    renderEvent = nil
    callback()
  end, 1)
end

local function configureLootSlot(parent, info)
  local slot = g_ui.createWidget('BestiaryLootItem', parent)
  if not info then
    return
  end

  if info.item <= 0 then
    slot.image:setImageSource("/images/ui/unkown-button")
    return
  end

  slot.image:setImageClip("0 34 34 34")
  slot.item:setItemId(info.item)
  setItemRarityFrame(slot.item, info.item)
  slot.item:setVirtualCount(info.stackable and "1+" or "1")
  slot.item:setTooltip(info.name)
  slot.item.onClick = function()
    modules.game_cyclopedia.cyclopediaWindow:hide()
    modules.game_cyclopedia.CyclopediaItems.onRedirect(info.item)
  end
  slot.item.onMouseRelease = function(widget, mousePos, mouseButton)
    if not widget:containsPoint(mousePos) or mouseButton ~= MouseRightButton then
      return
    end

    local menu = g_ui.createWidget('PopupMenu')
    menu:setGameMenu(true)
    local buttonText = modules.game_quickloot.inWhiteList(info.item) and
      'Remove from Loot List' or 'Add to Loot List'
    menu:addOption(tr(buttonText), function() Bestiary.itemToList(info.item) end)
    menu:display(mousePos)
  end
end

local function renderLootSlots(tasks, generation, panel)
  if #tasks == 0 then
    return
  end

  local panelId = panel:getId()
  local nextIndex = 1
  local function renderBatch()
    if not isCurrentRender(generation, panel, panelId) then
      return
    end

    local batchEnd = math.min(nextIndex + 3, #tasks)
    for index = nextIndex, batchEnd do
      local task = tasks[index]
      configureLootSlot(task.parent, task.info)
    end

    nextIndex = batchEnd + 1
    if nextIndex <= #tasks then
      scheduleRender(renderBatch)
    end
  end

  scheduleRender(renderBatch)
end

local function getCurrentLevelFromProgress(progress)
  progress = tonumber(progress) or 0
  return math.min(math.max(progress + 1, 1), 5)
end

local function normalizeBestiaryName(name)
  return tostring(name or ""):gsub("^%s*(.-)%s*$", "%1"):lower()
end

local function getMonsterName(monster)
  if not monster then
    return ""
  end
  return monster.name or monster[1] or ""
end

local function findBestiaryRaceIdByName(name)
  local normalizedName = normalizeBestiaryName(name)
  if normalizedName == "" then
    return nil
  end

  local monsters = getCyclopediaMonsterList and getCyclopediaMonsterList() or {}
  for i = 1, #MonsterList do
    local raceId = tonumber(MonsterList[i][1])
    local monster = monsters[raceId]
    if normalizeBestiaryName(getMonsterName(monster)) == normalizedName then
      return raceId
    end
  end

  for raceId, monster in pairs(monsters) do
    if normalizeBestiaryName(getMonsterName(monster)) == normalizedName then
      return tonumber(raceId)
    end
  end
  return nil
end

local bestiaryMessageCallbacksRegistered = false
local function getBestiaryMessageModes()
  if not MessageModes then
    return {}
  end

  return {
    MessageModes.Game,
    MessageModes.Status,
    MessageModes.Blue,
    MessageModes.Notification,
    MessageModes.GameHighlight,
    MessageModes.Login,
    MessageModes.ChannelManagement
  }
end

function Bestiary.reset()
  cancelRender()
  overviewPage = 1
  monsterListPage = 1
  BestiaryGroups = {}
  MonsterList = {}
  BESTIARY_MONSTER_ID = 0
  selectedCharm = 0
  BestiaryMonster = {}
  MonsterId = 0
  CurrentLevel = 0
end

function Bestiary.getTrackedList()
  return monsterTracked
end

function Bestiary.monsterInTracker(monsterId)
  if not monsterId or monsterId == 0 then
    return false
  end

  for i, tracked in pairs(monsterTracked) do
    if tracked[1] == monsterId then
      return true
    end
  end

  return false
end

function Bestiary.bestiaryTracker(trackerType, monsterVector)
  if trackerType ~= 0 then
    return
  end
  monsterTracked = monsterVector
end

function Bestiary.monsterSelectCharm(type, charm, monsterId)
  if not charm or not charm.id then return true end
  if type:lower() == 'select' then
    g_game.charmSelect(charm.id, monsterId)
  elseif type:lower() == 'remove' then
    g_game.charmRemove(charm.id)
  end
end

function Bestiary.onOptionChangeBestiaryMonster(list, value, force)
  if not VisibleCyclopediaPanel then
    return true
  end

  local data = list:getCurrentOption()
  local button = VisibleCyclopediaPanel:recursiveGetChildById('selectButton')
  if button then
    button:setEnabled(true)
    button.onClick = function()
      Bestiary.monsterSelectCharm(button:getText(), data.data, BESTIARY_MONSTER_ID)
      g_game.bestiaryMonsterData(BESTIARY_MONSTER_ID)
    end
  end
end

function Bestiary.updateBestiaryGroup(bestiaries)
  BestiaryGroups = bestiaries
  Bestiary.showBestiaryGroups(1)
end

function Bestiary.showBestiaryGroups()
  if not VisibleCyclopediaPanel or not VisibleCyclopediaPanel.listOfMonsters then
    return true
  end

  local generation = beginRender()
  local panel = VisibleCyclopediaPanel
  local panelId = panel:getId()
  local totalPages = math.ceil(#BestiaryGroups / 15)
  if panel.pageCount then
    panel.pageCount:setText(tr('%s / %s', overviewPage, totalPages))
  end
  panel.listOfMonsters.itemsPanel:destroyChildren()
  panel.backListButton.onClick = function() Bestiary.changeOverviewPage(-1) end
  panel.nextListButton.onClick = function() Bestiary.changeOverviewPage(1) end
  panel:recursiveGetChildById("backButton"):setEnabled(false)

  if math.min(overviewPage, totalPages) == 1 then
    panel.backListButton:setEnabled(false)
  else
    panel.backListButton:setEnabled(true)
  end

  if math.min(overviewPage, totalPages) == math.max(1, totalPages) then
    panel.nextListButton:setEnabled(false)
  else
    panel.nextListButton:setEnabled(true)
  end

  local nextIndex = (overviewPage - 1) * 15 + 1
  local lastIndex = math.min(nextIndex + 14, #BestiaryGroups)
  local function renderBatch()
    if not isCurrentRender(generation, panel, panelId) then
      return
    end

    local batchEnd = math.min(nextIndex + 2, lastIndex)
    for index = nextIndex, batchEnd do
      local group = BestiaryGroups[index]
      local widget = g_ui.createWidget('CyclopediaWindow', panel.listOfMonsters.itemsPanel)
      widget:setId(group.name)
      widget:setText(short_text(group.name, 14))
      widget.monster:setIcon('/images/game/cyclopedia/bestiary/' .. group.name)
      widget.monster.onClick = function()
        monsterListPage = 1
        g_game.bestiaryOverview(0, group.name)
      end
      widget.totalKill:setText(string.format("Total: %d", group.amount))
      widget.knownMonster:setText(string.format("Known: %d", group.know))
    end

    nextIndex = batchEnd + 1
    if nextIndex <= lastIndex then
      scheduleRender(renderBatch)
      return
    end

    local search = panel:recursiveGetChildById("searchBestiary")
    if search then
      search:focus()
    end
  end

  scheduleRender(renderBatch)
end

function Bestiary.updateBestiaryOverview(name, monsterList, masteryCount)
  if name == nil then
    onOptionChange(cyclopediaOptionsPanel:recursiveGetChildById('2'))
    return
  end

  MonsterList = monsterList
  MasteryCount = masteryCount
  Bestiary.bestiaryOverview()
end

function Bestiary.updateBestiaryProgress(monsterId, progress, killCounter, first, second, third)
  monsterId = tonumber(monsterId) or 0
  if monsterId <= 0 then
    return
  end

  local currentLevel = getCurrentLevelFromProgress(progress)
  local updatedOverview = false
  for i = 1, #MonsterList do
    if tonumber(MonsterList[i][1]) == monsterId then
      MonsterList[i][2] = currentLevel
      updatedOverview = true
      break
    end
  end

  if updatedOverview and VisibleCyclopediaPanel and VisibleCyclopediaPanel:getId() == 'bestiaryOverviewPanel' then
    Bestiary.bestiaryOverview()
  end

  if BESTIARY_MONSTER_ID == monsterId and VisibleCyclopediaPanel and VisibleCyclopediaPanel:getId() == 'bestiaryMonsterPanel' then
    g_game.bestiaryMonsterData(monsterId)
  end
end

function Bestiary.updateBestiaryProgressByName(monsterName, progress)
  local monsterId = findBestiaryRaceIdByName(monsterName)
  if not monsterId then
    return
  end
  Bestiary.updateBestiaryProgress(monsterId, progress)
end

function Bestiary.onTextMessage(mode, text)
  if type(text) ~= 'string' then
    return
  end

  local patterns = {
    { pattern = "^You unlocked the Bestiary entry for (.+)%.$", progress = 0 },
    { pattern = "^You unlocked the first Bestiary stage for (.+)%.$", progress = 1 },
    { pattern = "^You unlocked the second Bestiary stage for (.+)%.$", progress = 2 },
    { pattern = "^You completed the Bestiary entry for (.+) and earned .+ charm points%.$", progress = 3 }
  }

  for _, data in ipairs(patterns) do
    local monsterName = text:match(data.pattern)
    if monsterName then
      Bestiary.updateBestiaryProgressByName(monsterName, data.progress)
      return
    end
  end
end

function Bestiary.onClientEvent(eventType, monsterId, progress)
  if tonumber(eventType) ~= 6 then
    return
  end
  Bestiary.updateBestiaryProgress(monsterId, progress)
end

function Bestiary.registerMessageCallbacks()
  if bestiaryMessageCallbacksRegistered or not registerMessageMode then
    return
  end

  for _, messageMode in ipairs(getBestiaryMessageModes()) do
    if messageMode then
      registerMessageMode(messageMode, Bestiary.onTextMessage)
    end
  end
  bestiaryMessageCallbacksRegistered = true
end

function Bestiary.unregisterMessageCallbacks()
  cancelRender()
  if not bestiaryMessageCallbacksRegistered or not unregisterMessageMode then
    return
  end

  for _, messageMode in ipairs(getBestiaryMessageModes()) do
    if messageMode then
      unregisterMessageMode(messageMode, Bestiary.onTextMessage)
    end
  end
  bestiaryMessageCallbacksRegistered = false
end

function Bestiary.bestiaryOverview()
  RegisterBackButton(Bestiary.bestiaryOverview, Bestiary)
  if VisibleCyclopediaPanel and VisibleCyclopediaPanel:getId() ~= 'bestiaryOverviewPanel' or not VisibleCyclopediaPanel then
    if VisibleCyclopediaPanel then
      VisibleCyclopediaPanel:destroy()
    end

    VisibleCyclopediaPanel = g_ui.createWidget('BestiaryOverviewPanel', cyclopediaWindow.optionsPanel)
    VisibleCyclopediaPanel:setId('bestiaryOverviewPanel')
  end

  if #MonsterList == 0 then
    Bestiary.showBestiaryGroups()
    return
  end

  local generation = beginRender()
  local panel = VisibleCyclopediaPanel
  local panelId = panel:getId()
  panel.backButton:setEnabled(true)
  panel.backButton.onClick = function() Bestiary.showBestiaryGroups() end
  panel.backListButton.onClick = function() Bestiary.changeMonsterPage(-1) end
  panel.nextListButton.onClick = function() Bestiary.changeMonsterPage(1) end

  local totalPages = math.ceil(#MonsterList / 15)
  panel.pageCount:setText(tr('%s / %s', monsterListPage, totalPages))
  panel.listOfMonsters.itemsPanel:destroyChildren()

  if math.min(monsterListPage, totalPages) == 1 then
    panel.backListButton:setEnabled(false)
  else
    panel.backListButton:setEnabled(true)
  end

  if math.min(monsterListPage, totalPages) == math.max(1, totalPages) then
    panel.nextListButton:setEnabled(false)
  else
    panel.nextListButton:setEnabled(true)
  end

  local nextIndex = (monsterListPage - 1) * 15 + 1
  local lastIndex = math.min(nextIndex + 14, #MonsterList)
  local monsterCount = 0
  local function renderBatch()
    if not isCurrentRender(generation, panel, panelId) then
      return
    end

    local created = 0
    while nextIndex <= lastIndex and monsterCount < 15 and created < 2 do
      local monsterData = MonsterList[nextIndex]
      nextIndex = nextIndex + 1
      local monsterId = monsterData[1]
      local currentLevel = monsterData[2]
      local extraExperience = monsterData[3]
      local monster = getCyclopediaMonster(monsterId)
      if monster then
        local widget = g_ui.createWidget('CyclopediaCreatureWindow', panel.listOfMonsters.itemsPanel)
        local monsterWidget = widget:recursiveGetChildById("monster")
        local checkedWidget = widget:recursiveGetChildById("checked")
        local totalKillWidget = widget:recursiveGetChildById("totalKill")
        local unlocked = currentLevel > 1
        local name = unlocked and string.capitalize(monster[1]) or "?"
        local monsterShader = unlocked and "" or "outfit_black"
        widget:setTooltip(name)
        widget:setText(short_text(name, 14))
        monsterWidget:setOutfit({type = monster[2], auxType = monster[3], head = monster[4], body = monster[5], legs = monster[6], feet = monster[7], addons = monster[8], shader = monsterShader})
        monsterWidget:setTooltip(name)
        if unlocked then
          monsterWidget.onClick = function() backMonster = name; g_game.bestiaryMonsterData(monsterId) end
          widget:recursiveGetChildById("monsterButton").onClick = function() backMonster = name; g_game.bestiaryMonsterData(monsterId) end
        end
        totalKillWidget:setText(currentLevel - 1 .. " / 3")
        if extraExperience > 0 then
          widget.soulCoreIcon:setVisible(true)
          widget.soulCoreIcon:setTooltip(tr('The Animus Mastery for this creature is unlocked.\nIt yields 2%%, plus an additional 0.1%% for every 10 Animus Masteries unlocked, up to a maximum of 4%%.\nYou currently benefit from %.1f%% due to having unlocked %d Animus Masteries.', extraExperience, MasteryCount))
        end
        checkedWidget:setVisible((currentLevel - 1) >= 3)
        totalKillWidget:setVisible((currentLevel - 1) < 3)
        monsterCount = monsterCount + 1
        created = created + 1
      else
        g_logger.error("Bestiary Overview: failed to retrieve data from monster " .. monsterId)
      end
    end

    if nextIndex <= lastIndex and monsterCount < 15 then
      scheduleRender(renderBatch)
    end
  end

  scheduleRender(renderBatch)
end

function Bestiary.updateBestiaryMonsterData(monsterId, bestiaryMonster, currentLevel, killCounter, first, second, third, difficulty, ocorrence, extraExperience, masteryCount)
  RegisterBackButton(Bestiary.updateBestiaryMonsterData, monsterId, bestiaryMonster, currentLevel, killCounter, first, second, third, difficulty, ocorrence, extraExperience, masteryCount)

  if not VisibleCyclopediaPanel or VisibleCyclopediaPanel:getId() == 'charmDataPanel' then return end

  local generation = beginRender()
  local panel = VisibleCyclopediaPanel
  local panelId = panel:getId()
  scheduleRender(function()
    if not isCurrentRender(generation, panel, panelId) then
      return
    end
    BESTIARY_MONSTER_ID = monsterId
    Cyclopedia.bestiaryMonsterData(monsterId, bestiaryMonster, currentLevel, killCounter, first, second, third, difficulty, ocorrence, extraExperience, masteryCount)
  end)
end

function Cyclopedia.bestiaryMonsterData(monsterId, bestiaryMonster, currentLevel, killCounter, first, second, third, difficulty, ocorrence, extraExperience, masteryCount)
  local generation = beginRender()
  if VisibleCyclopediaPanel then
    VisibleCyclopediaPanel:destroy()
    VisibleCyclopediaPanel = g_ui.createWidget('BestiaryMonsterPanel', cyclopediaWindow.optionsPanel)
    VisibleCyclopediaPanel:setId('bestiaryMonsterPanel')
  end
  local panel = VisibleCyclopediaPanel

  VisibleCyclopediaPanel.backButton.onClick = function() Bestiary.bestiaryOverview() end

  local monster = getCyclopediaMonster(monsterId)
  local widget = VisibleCyclopediaPanel.listOfMonsters

  widget:setText(monster[1])
  widget.monster:setOutfit({type = monster[2], auxType = monster[3], head = monster[4], body = monster[5], legs = monster[6], feet = monster[7], addons = monster[8]})

  widget.trackerKills:setChecked(false, true)

  for i, tracked in pairs(monsterTracked) do
    if tracked[1] == monsterId then
      widget.trackerKills:setChecked(true, true)
    end
  end

  if extraExperience > 0 then
    VisibleCyclopediaPanel:recursiveGetChildById("soulCoreIcon"):setVisible(true)
    VisibleCyclopediaPanel:recursiveGetChildById("soulCoreIcon"):setTooltip(tr('The Animus Mastery for this creature is unlocked.\nIt yields 2%%, plus an additional 0.1%% for every 10 Animus Masteries unlocked, up to a maximum of 4%%.\nYou currently benefit from %.1f%% due to having unlocked %d Animus Masteries.', extraExperience, MasteryCount))
  end


  local fullyUnlocked = killCounter >= third
  VisibleCyclopediaPanel:recursiveGetChildById("first"):setPercent(0)
  VisibleCyclopediaPanel:recursiveGetChildById("first"):setValue(killCounter, 0, first)

  VisibleCyclopediaPanel:recursiveGetChildById("second"):setPercent(0)
  VisibleCyclopediaPanel:recursiveGetChildById("third"):setPercent(0)

  if killCounter >= second then
    VisibleCyclopediaPanel:recursiveGetChildById("second"):setValue(killCounter, 0, second)
    VisibleCyclopediaPanel:recursiveGetChildById("third"):setValue(killCounter, 0, third)
  elseif killCounter >= first then
    VisibleCyclopediaPanel:recursiveGetChildById("second"):setValue(killCounter, 0, second)
  end


  if fullyUnlocked then
    VisibleCyclopediaPanel:recursiveGetChildById("first"):setImageSource('/images/game/cyclopedia/bestiary/progress-green')
    VisibleCyclopediaPanel:recursiveGetChildById("second"):setImageSource('/images/game/cyclopedia/bestiary/progress-green')
    VisibleCyclopediaPanel:recursiveGetChildById("third"):setImageSource('/images/game/cyclopedia/bestiary/progress-green')
  end

  VisibleCyclopediaPanel:recursiveGetChildById("first"):setTooltip(tr("%s / %s %s", comma_value(killCounter), comma_value(first), (fullyUnlocked and "(fully unlocked)" or "")))
  VisibleCyclopediaPanel:recursiveGetChildById("second"):setTooltip(tr("%s / %s %s", comma_value(killCounter), comma_value(second), (fullyUnlocked and "(fully unlocked)" or "")))
  VisibleCyclopediaPanel:recursiveGetChildById("third"):setTooltip(tr("%s / %s %s", comma_value(killCounter), comma_value(third), (fullyUnlocked and "(fully unlocked)" or "")))

  VisibleCyclopediaPanel:recursiveGetChildById("second"):setText(comma_value(killCounter))

  -- difficulty
  local difficultyText = {
    [0] = "Harmless",
    [1] = "Trivial",
    [2] = "Easy",
    [3] = "Medium",
    [4] = "Hard",
    [5] = "Challenging"
  }

  local dif = VisibleCyclopediaPanel:recursiveGetChildById('difficulty')
  for i = 1, 5 do
    local widdif = g_ui.createWidget('UIWidget', dif)
    widdif:setId(i)
    widdif:setHeight(10)
    widdif:setWidth(9)
    widdif:setImageSource('/images/game/cyclopedia/icons/icon-star-' .. (i <= difficulty and 'active' or 'inactive'))
    widdif:setTooltip("Difficulty: " .. difficultyText[difficulty])
  end

  -- ocorrence
  ocorrence = ocorrence + 1
  local ocorrenceText = {
    [1] = "Common",
    [2] = "Uncommon",
    [3] = "Rare",
    [4] = "Very Rare",
  }

  local ocor = VisibleCyclopediaPanel:recursiveGetChildById('ocorrency')
  for i = 1, 4 do
    local widdif = g_ui.createWidget('UIWidget', ocor)
    widdif:setId(i)
    widdif:setHeight(10)
    widdif:setWidth(9)
    widdif:setImageSource('/images/game/cyclopedia/icons/monster-icon-diamond-' .. (i <= ocorrence and 'active' or 'inactive'))
    widdif:setTooltip("Ocorrency: " .. ocorrenceText[ocorrence])
  end

  -- looting
  local lootPanel = VisibleCyclopediaPanel:recursiveGetChildById('lootPanel')
  -- dividir o loot
  local common = {}
  local uncommon = {}
  local semirare = {}
  local rare = {}
  local veryrare = {}

  for i, info in pairs(bestiaryMonster.loot) do
    if info.difficulty == 0 then
      table.insert(common, info)
    elseif info.difficulty == 1 then
      table.insert(uncommon, info)
    elseif info.difficulty == 2 then
      table.insert(semirare, info)
    elseif info.difficulty == 3 then
      table.insert(rare, info)
    elseif info.difficulty == 4 then
      table.insert(veryrare, info)
    end
  end

  local lootTasks = {}
  local lootCategories = {
    {label = "Common:", items = common},
    {label = "Uncommon:", items = uncommon},
    {label = "Semi-Rare:", items = semirare},
    {label = "Rare:", items = rare},
    {label = "Very Rare:", items = veryrare}
  }
  for _, category in ipairs(lootCategories) do
    if #category.items > 0 then
      local categoryPanel = g_ui.createWidget('LootPanelWidget', lootPanel)
      local slotCount = #category.items > 15 and 30 or 15
      if slotCount == 30 then
        categoryPanel:setHeight(74)
      end
      categoryPanel.lootType:setText(tr(category.label))
      for index = 1, slotCount do
        lootTasks[#lootTasks + 1] = {parent = categoryPanel.lootItem, info = category.items[index]}
      end
    end
  end

  if currentLevel > 1 then
    local attackImages = {
      [0] = "/images/game/cyclopedia/icons/monster-icon-melee",
      [1] = "/images/game/cyclopedia/icons/monster-icon-ranged",
      [2] = "/images/game/cyclopedia/icons/monster-icon-noattack"
    }

    VisibleCyclopediaPanel:recursiveGetChildById('charmPoints'):setText(bestiaryMonster.difficultyCharm)
    VisibleCyclopediaPanel:recursiveGetChildById('attackRange'):setImageSource(attackImages[bestiaryMonster.attackMode])
    VisibleCyclopediaPanel:recursiveGetChildById('attackRange'):setText('')
    VisibleCyclopediaPanel:recursiveGetChildById('attackRange'):setHeight(9)
    VisibleCyclopediaPanel:recursiveGetChildById('attackRange'):setWidth(9)
    VisibleCyclopediaPanel:recursiveGetChildById('castSpell'):setVisible(true)
    VisibleCyclopediaPanel:recursiveGetChildById('health'):setText(comma_value(bestiaryMonster.health))
    VisibleCyclopediaPanel:recursiveGetChildById('experience'):setText(comma_value(bestiaryMonster.experience))
    VisibleCyclopediaPanel:recursiveGetChildById('speed'):setText(comma_value(bestiaryMonster.speed))
    VisibleCyclopediaPanel:recursiveGetChildById('armor'):setText(bestiaryMonster.armor)

    local mitigation = string.format("%.2f", bestiaryMonster.mitigation)
    VisibleCyclopediaPanel:recursiveGetChildById('mitigation'):setText(mitigation .. "%")
  end

  local elementName = {
    [1] = {name = "physical", id = 0},
    [2] = {name = "earth", id = 2},
    [3] = {name = "fire", id = 1},
    [4] = {name = "death", id = 6},
    [5] = {name = "energy", id = 3},
    [6] = {name = "holy", id = 5},
    [7] = {name = "ice", id = 4},
    [8] = {name = "healing", id = 7}
  }

  local elementsWidgets = {}
  for k, v in ipairs(elementName) do
      local widgetElement = g_ui.createWidget('ElementPanel', VisibleCyclopediaPanel:recursiveGetChildById("elements"))
      widgetElement.progress:setValue(0, 0, 150)
      widgetElement.progress:setBackgroundColor('white')
      widgetElement:setId(v.id)
      widgetElement:setActionId(k)
      widgetElement.icon:setImageSource('/images/game/cyclopedia/icons/monster-icon-'.. v.name ..'-resist')
      widgetElement.icon:setTooltip(string.capitalize(v.name))
  end

  for i, v in ipairs(bestiaryMonster.elements) do
    local list = VisibleCyclopediaPanel:recursiveGetChildById("elements")
    local widgetElement = list:getChildById(bestiaryMonster.elements[i].element)
    widgetElement.index = i
    widgetElement.progress:setValue(0, 0, 150)
    widgetElement.progress:setBackgroundColor('white')
    elementsWidgets[#elementsWidgets + 1] = widgetElement
  end

  if currentLevel > 2 then
    for i = 1, #elementsWidgets do
      local widgetElement = elementsWidgets[i]
      local element = bestiaryMonster.elements
      local index = widgetElement.index

      local id = element[index].element
      local percent = element[index].percent

      widgetElement.progress:setValue(percent, 0, 150)
      widgetElement.progress:setTooltip(tr('Sensitive to %s: %d%% (neutral)', elementName[widgetElement:getActionId()].name, percent))
      if percent < 50 then
        widgetElement.progress:setBackgroundColor('red')
        widgetElement.progress:setTooltip(tr('Sensitive to %s: %d%% (strong)', elementName[widgetElement:getActionId()].name, percent))
      elseif percent < 100 then
        widgetElement.progress:setBackgroundColor('#e4c00a')
        widgetElement.progress:setTooltip(tr('Sensitive to %s: %d%% (strong)', elementName[widgetElement:getActionId()].name, percent))
      elseif percent > 100 then
        widgetElement.progress:setBackgroundColor('#18ce18')
        widgetElement.progress:setTooltip(tr('Sensitive to %s: %d%% (weak)', elementName[widgetElement:getActionId()].name, percent))
      end
    end


    function removeSpacesAfterNewLine(text)
      local result = text:gsub("\n%s+", "\n")
        result = result:gsub("\n%s", "\n")
        return result
    end

    -- location
    if bestiaryMonster.location ~= "" then
      VisibleCyclopediaPanel:recursiveGetChildById("locations"):setText(removeSpacesAfterNewLine(bestiaryMonster.location))
    end
  end

  local panelImage = VisibleCyclopediaPanel:recursiveGetChildById('charmImage')
  panelImage:setImageSource('')

  VisibleCyclopediaPanel:recursiveGetChildById('coinCost'):setText("?")
  BestiaryMonster = bestiaryMonster
  MonsterId = monsterId

  local majorCharmPanel = VisibleCyclopediaPanel:recursiveGetChildById('charm0')
  local major = Charm:getMajorCharm(MonsterId)
  if not major.id or major.id == -1 then
    majorCharmPanel:recursiveGetChildById("charmImage"):setImageSource('')
  else
    majorCharmPanel:recursiveGetChildById("charmImage"):setImageSource('/images/game/cyclopedia/monster-bonus-effects/monster-bonus-effects-'.. major.id)
  end

  local minorCharmPanel = VisibleCyclopediaPanel:recursiveGetChildById('charm1')
  local minor = Charm:getMinorCharm(MonsterId)
  if not minor.id or minor.id == -1 then
    minorCharmPanel:recursiveGetChildById("charmImage"):setImageSource('')
  else
    minorCharmPanel:recursiveGetChildById("charmImage"):setImageSource('/images/game/cyclopedia/monster-bonus-effects/monster-bonus-effects-'.. minor.id)
  end

  local selectAssignButton = VisibleCyclopediaPanel:recursiveGetChildById('selectAssignButton')
  selectAssignButton:setVisible(true)
  selectAssignButton:setEnabled(false)

  local selectClearButton = VisibleCyclopediaPanel:recursiveGetChildById('selectClearButton')
  selectClearButton:setVisible(false)
  selectClearButton:setEnabled(false)

  CurrentLevel = currentLevel
  if currentLevel > 3 then
    Bestiary.onCharm()
  end
  renderLootSlots(lootTasks, generation, panel)
end

------
function Bestiary.changeOverviewPage(index)
  overviewPage = index > 0 and overviewPage + 1 or overviewPage - 1
  Bestiary.showBestiaryGroups()
end

function Bestiary.changeMonsterPage(index)
  monsterListPage = index > 0 and monsterListPage + 1 or monsterListPage - 1
  Bestiary.bestiaryOverview()
end

function Bestiary.itemToList(itemId)
  if not modules.game_quickloot.inWhiteList(itemId) then
		modules.game_quickloot.addToQuickLoot(itemId)
	else
		modules.game_quickloot.removeItemInList(itemId)
	end
end

function Bestiary.onTrackMonster(isChecked, monsterId)
  if not monsterId then
    monsterId = BESTIARY_MONSTER_ID
  end

  g_game.sendMonsterTracker(monsterId, isChecked)
end

function Bestiary.onSearchChange(widget)
  if string.empty(widget:getText()) then
    VisibleCyclopediaPanel:getChildById('searchButton'):setEnabled(false)
  else
    VisibleCyclopediaPanel:getChildById('searchButton'):setEnabled(true)
  end
end

function Bestiary.onSearch()
  if not VisibleCyclopediaPanel then
    return
  end

  local widget = VisibleCyclopediaPanel:getChildById('searchBestiary')
  if not widget then
    return
  end

  local text = widget:getText():lower()

  widget:clearText()
  monsterListPage = 1
  g_game.bestiarySearch(text)
end

function Bestiary.setupBackTrackerButton()
  if VisibleCyclopediaPanel then
    VisibleCyclopediaPanel:recursiveGetChildById("backButton"):setEnabled(true)
    VisibleCyclopediaPanel:recursiveGetChildById("backButton").onClick = function() modules.game_cyclopedia.onOptionChange(modules.game_cyclopedia.cyclopediaOptionsPanel:recursiveGetChildById('2')) end
  end
end

function Bestiary.onApplyCharm(monster, charm, monsterId)
  if messageBoxCharm then
    return
  end

  local okFunc = function()
    g_game.charmSelect(charm.id, monsterId)
    g_game.bestiaryMonsterData(monsterId)
    messageBoxCharm:destroy()
    cyclopediaWindow:show(true)
    g_client.setInputLockWidget(nil)
    messageBoxCharm = nil
  end

  local cancelFunc = function()
    cyclopediaWindow:show(true)
    messageBoxCharm:destroy()
    g_client.setInputLockWidget(nil)
    messageBoxCharm = nil
  end

  cyclopediaWindow:hide()
  g_client.setInputLockWidget(nil)
	messageBoxCharm = displayGeneralBox("Confirm Selected Charm", tr("Do you want to use the Charm %s for this creature?", charm.name),
    { { text=tr('Yes'), callback=okFunc },
    { text=tr('No'), callback=cancelFunc }
  }, okFunc, cancelFunc)

  g_client.setInputLockWidget(messageBoxCharm)
  messageBoxCharm.onEscape = cancelFunc
end

function Bestiary.onRemoveCharm(monster, charm, mosnterId)
  if messageBoxCharm then
    return
  end

  local okFunc = function()
    g_game.charmRemove(charm.id)
    g_game.bestiaryMonsterData(mosnterId)
    messageBoxCharm:destroy()
    cyclopediaWindow:show(true)
    g_client.setInputLockWidget(nil)
    messageBoxCharm = nil
  end

  local cancelFunc = function()
    cyclopediaWindow:show(true)
    messageBoxCharm:destroy()
    g_client.setInputLockWidget(nil)
    messageBoxCharm = nil
  end

  cyclopediaWindow:hide()
  g_client.setInputLockWidget(nil)
  messageBoxCharm = displayGeneralBox("Confirm Charm Removal", tr("Do you want to remove the Charm %s from this creature? This will cost you %s gold pieces.", charm.name, comma_value(charm.removePrice)),
    { { text=tr('Yes'), callback=okFunc },
    { text=tr('No'), callback=cancelFunc }
  }, okFunc, cancelFunc)

  g_client.setInputLockWidget(messageBoxCharm)
  messageBoxCharm.onEscape = cancelFunc
end

function Bestiary.onFocusChangeBestiaryMonster(widget, focus)
  if widget:isFocused() then
    if widget:getId() == "charm0" then
      selectedCharm = 0
    else
      selectedCharm = 1
    end

    Bestiary.onCharm()
  end
end

function Bestiary.onCharm()
  if CurrentLevel <= 3 then
    return
  end

  local charmOptions = VisibleCyclopediaPanel:recursiveGetChildById('charmOptions')

  local currentCharm = {id = -1}
  if selectedCharm == 0 then
    charmList = Charm:getEmptyMajorSlots()
    currentCharm = Charm:getMajorCharm(MonsterId)
  else
    charmList = Charm:getEmptyMinorSlots()
    currentCharm = Charm:getMinorCharm(MonsterId)
  end

  local coinCostPanel = VisibleCyclopediaPanel:recursiveGetChildById('coinCostPanel')
  coinCostPanel:setVisible(false)

  if #charmList == 0 and currentCharm.id == -1 then
    charmOptions:removeOption('?')
    charmOptions:clear()
    charmOptions:addOption('None Unlocked')
    charmOptions:setCurrentIndex(1)
    charmOptions:setEnabled(false)
  elseif currentCharm.id == -1 then
    charmListUnlocked = {}
    charmOptions:removeOption('?')
    charmOptions:clear()
    for i, charm in pairs(charmList) do
      if charm.creatureId == 0 then
        table.insert(charmListUnlocked, charm)
        charmOptions:addOption(charm.name, charm)
      end
    end

    if #charmListUnlocked == 0 then
      charmOptions:clear()
      charmOptions:addOption('None Unlocked')
      charmOptions:setEnabled(false)
    else
      charmOptions:setCurrentIndex(1)
      charmOptions:setEnabled(true)

      local selectAssignButton = VisibleCyclopediaPanel:recursiveGetChildById('selectAssignButton')
      selectAssignButton:setVisible(true)
      selectAssignButton:setEnabled(true)

      local selectClearButton = VisibleCyclopediaPanel:recursiveGetChildById('selectClearButton')
      selectClearButton:setVisible(false)
      selectClearButton:setEnabled(false)

      selectAssignButton.onClick = function()
        local data = charmOptions:getCurrentOption()
        local monster = getCyclopediaMonster(MonsterId)
        if not data or not data.data or not monster then
          return
        end
        Bestiary.onApplyCharm(getMonsterName(monster), data.data, MonsterId)
      end
    end
  elseif currentCharm.id > -1 then
    charmOptions:removeOption('?')
    charmOptions:clear()
    charmOptions:addOption(currentCharm.name, currentCharm)

    charmOptions:setCurrentIndex(1)
    charmOptions:setEnabled(false)
    local data = charmOptions:getCurrentOption()
    if data then
      local panel = VisibleCyclopediaPanel:recursiveGetChildById('charm0')
      if selectedCharm == 1 then
        panel = VisibleCyclopediaPanel:recursiveGetChildById('charm1')
      end
      panel:recursiveGetChildById("charmImage"):setImageSource('/images/game/cyclopedia/monster-bonus-effects/monster-bonus-effects-'.. currentCharm.id)
    end

    local selectAssignButton = VisibleCyclopediaPanel:recursiveGetChildById('selectAssignButton')
    selectAssignButton:setVisible(false)
    selectAssignButton:setEnabled(false)

    local selectClearButton = VisibleCyclopediaPanel:recursiveGetChildById('selectClearButton')
    selectClearButton:setVisible(true)
    selectClearButton:setEnabled(true)

    local coinCostPanel = VisibleCyclopediaPanel:recursiveGetChildById('coinCostPanel')
    coinCostPanel:setVisible(true)

    selectClearButton.onClick = function()
      local monster = getCyclopediaMonster(MonsterId)
      if not monster then
        return
      end
      Bestiary.onRemoveCharm(getMonsterName(monster), currentCharm, MonsterId)
    end
    coinCostPanel:getChildById('coinCost'):setText(comma_value(Charm:getCharmCost(currentCharm.id)))
  end
end
