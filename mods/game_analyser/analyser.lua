analyserMiniWindow = nil
if not configPopupWindow then
  configPopupWindow = {}
end

openedWindows = {}

local OPCODE_KILL_TRACKER = 0xD1
local MAX_KILL_TRACKER_DEPTH = 4

local analyserWindows = {
  huntingButton = 'styles/hunting',
  lootButton = 'styles/loot',
  supplyButton = 'styles/supply',
  impactButton = 'styles/impact',
  damageButton = 'styles/input',
  xpButton = 'styles/xp',
  dropButton = 'styles/droptracker',
  partyButton = 'styles/partyhunt',
  bossButton = 'styles/boss',
  miscButton = 'styles/misc'
}

-- objects
function init()
  ProtocolGame.unregisterOpcode(OPCODE_KILL_TRACKER)
  ProtocolGame.registerOpcode(OPCODE_KILL_TRACKER, parseCompactKillTracker)

  analyserMiniWindow = g_ui.loadUI('analyser', m_interface.getRightPanel())
  analyserMiniWindow:disableResize()
  analyserMiniWindow:close()
  analyserMiniWindow:setup()

  configPopupWindow["lootButton"] = g_ui.displayUI('styles/lootTarget')
  configPopupWindow["lootButton"]:hide()

  configPopupWindow["impactButton"] = g_ui.displayUI('styles/dpshpsTarget')
  configPopupWindow["impactButton"]:hide()

  configPopupWindow["xpButton"] = g_ui.displayUI('styles/xpTarget')
  configPopupWindow["xpButton"]:hide()

  configPopupWindow["dropButton"] = g_ui.displayUI('styles/dropTarget')
  configPopupWindow["dropButton"]:hide()

  huntingButton = analyserMiniWindow:recursiveGetChildById("huntingButton")
  lootButton = analyserMiniWindow:recursiveGetChildById("lootButton")
  supplyButton = analyserMiniWindow:recursiveGetChildById("supplyButton")
  impactButton = analyserMiniWindow:recursiveGetChildById("impactButton")
  damageButton = analyserMiniWindow:recursiveGetChildById("damageButton")
  xpButton = analyserMiniWindow:recursiveGetChildById("xpButton")
  dropButton = analyserMiniWindow:recursiveGetChildById("dropButton")
  partyButton = analyserMiniWindow:recursiveGetChildById("partyButton")
  bossButton = analyserMiniWindow:recursiveGetChildById("bossButton")
  miscButton = analyserMiniWindow:recursiveGetChildById("miscButton")

  for id, style in pairs(analyserWindows) do
    openedWindows[id] = g_ui.loadUI(style, m_interface.getRightPanel())
    if openedWindows[id] then
      openedWindows[id]:setup()
      openedWindows[id].closeButton.onClick = function() toggleAnalysers(id) end
      openedWindows[id]:close()
      local scrollbar = openedWindows[id]:getChildById('miniwindowScrollBar')
      scrollbar:mergeStyle({ ['$!on'] = { }})
    end
  end

  HuntingAnalyser:create()
  HuntingAnalyser:updateWindow()

  LootAnalyser:create()
  LootAnalyser:updateWindow()

  SupplyAnalyser:create()
  SupplyAnalyser:updateWindow()

  ImpactAnalyser:create()
  ImpactAnalyser:updateWindow()

  InputAnalyser:create()
  InputAnalyser:updateWindow()

  XPAnalyser:create()
  XPAnalyser:updateWindow()

  DropTrackerAnalyser:create()
  DropTrackerAnalyser:updateWindow()

  PartyHuntAnalyser:create()
  PartyHuntAnalyser:updateWindow()

  BossCooldown:create()
  BossCooldown:updateWindow()

  MiscAnalyzer:create()
  MiscAnalyzer:updateWindow()

  connect(g_game, {
    onGameStart = onlineAnalyser,
    onGameEnd = offlineAnalyser,
    onSupplyTracker = onSupplyTracker,
    onLootStats = onLootStats,
    onImpactTracker = onImpactTracker,
    onKillTracker = onKillTracker,
    onPartyAnalyzer = onPartyAnalyzer,
    onBossCooldown = onBossCooldown,
    onUpdateExperience = onUpdateExperience,
    onCharmActivated = onCharmActivated,
    onImbuementActivated = onImbuementActivated,
    onSpecialSkillActivated = onSpecialSkillActivated,
  })

  connect(LocalPlayer, {
    onExperienceChange = onExperienceChange,
    onLevelChange = onLevelChange,
    onPartyMembersChange = onPartyMembersChange
  })

  connect(Creature, {
      onShieldChange = onShieldChange,
  })

end

function terminate()
  ProtocolGame.unregisterOpcode(OPCODE_KILL_TRACKER)

  if analyserMiniWindow then
    analyserMiniWindow:destroy()
    analyserMiniWindow = nil
  end

  for _, w in pairs(openedWindows) do
    w:destroy()
  end
  openedWindows = {}

  for _, w in pairs(configPopupWindow) do
    w:destroy()
  end
  configPopupWindow = {}

  disconnect(g_game, {
    onGameStart = onlineAnalyser,
    onGameEnd = offlineAnalyser,
    onSupplyTracker = onSupplyTracker,
    onLootStats = onLootStats,
    onImpactTracker = onImpactTracker,
    onKillTracker = onKillTracker,
    onPartyAnalyzer = onPartyAnalyzer,
    onBossCooldown = onBossCooldown,
    onUpdateExperience = onUpdateExperience,
    onCharmActivated = onCharmActivated,
    onImbuementActivated = onImbuementActivated,
    onSpecialSkillActivated = onSpecialSkillActivated,
  })
  disconnect(LocalPlayer, {
    onExperienceChange = onExperienceChange,
    onLevelChange = onLevelChange,
    onPartyMembersChange = onPartyMembersChange
  })

  disconnect(Creature, {
      onShieldChange = onShieldChange,
  })

end

local function parseCompactKillTrackerItems(msg, dropItems, depth)
  local itemCount = msg:getU8()
  if depth > MAX_KILL_TRACKER_DEPTH then
    return
  end

  for _ = 1, itemCount do
    local item = Item.create(msg:getU16())
    if item and item:isContainer() then
      parseCompactKillTrackerItems(msg, dropItems, depth + 1)
      table.insert(dropItems, item)
    else
      local count = msg:getU8()
      msg:getU16() -- worth
      msg:getString() -- item name
      if item and item:getId() ~= 0 then
        item:setCount(math.max(1, count))
        table.insert(dropItems, item)
      end
    end
  end
end

function parseCompactKillTracker(protocol, msg)
  local monsterName = msg:getString()
  local monsterOutfit = {
    type = msg:getU16(),
    head = msg:getU8(),
    body = msg:getU8(),
    legs = msg:getU8(),
    feet = msg:getU8(),
    addons = msg:getU8()
  }
  local dropItems = {}
  parseCompactKillTrackerItems(msg, dropItems, 1)
  signalcall(g_game.onKillTracker, monsterName, monsterOutfit, dropItems)
end

function startNewSession(login)
  -- Hunting
  HuntingAnalyser:reset()
  if login then
    HuntingAnalyser:loadConfigJson()
  end
  HuntingAnalyser:updateWindow(true)

  -- Loot
  LootAnalyser:reset()
  LootAnalyser:updateWindow(true, true)

  -- Supply
  SupplyAnalyser:reset()
  SupplyAnalyser:updateWindow(true, true)

  ImpactAnalyser:reset()
  if login then
    ImpactAnalyser:loadConfigJson()
  end
  ImpactAnalyser:updateWindow(true)

  InputAnalyser:reset()
  if login then
    InputAnalyser:loadConfigJson()
  end
  InputAnalyser:updateWindow(true)

  XPAnalyser:reset()
  if login then
    XPAnalyser:loadConfigJson()
  end
  XPAnalyser:updateWindow(true)

  DropTrackerAnalyser:reset(login)
  if login then
    DropTrackerAnalyser:loadConfigJson()
  end
  DropTrackerAnalyser:updateWindow(true)

  MiscAnalyzer:reset()
  MiscAnalyzer:resetSessionData()
  MiscAnalyzer:updateWindow(true)

  PartyHuntAnalyser:reset()
  PartyHuntAnalyser:updateWindow(true, true)
  PartyHuntAnalyser:startEvent()

  ControllerAnalyser:startEvent()
end

function onlineAnalyser()
  local benchmark = g_clock.millis()
  startNewSession(true)

  loadGainAndWastConfigJson()
  consoleln("Analyser loaded in " .. (g_clock.millis() - benchmark) / 1000 .. " seconds")
end

function offlineAnalyser()
  HuntingAnalyser:saveConfigJson()
  ImpactAnalyser:saveConfigJson()
  InputAnalyser:saveConfigJson()
  XPAnalyser:saveConfigJson()
  DropTrackerAnalyser:saveConfigJson()
  saveGainAndWastConfigJson()
  BossCooldown.cooldown = {}
end

function toggle()
  if analyserMiniWindow:isVisible() then
    analyserMiniWindow:close()
    modules.game_sidebuttons.setButtonVisible("analyticsSelectorWidget", false)
    analyserMiniWindow.isOpen = false
  else
    analyserMiniWindow:open()
    if m_interface.addToPanels(analyserMiniWindow) then
      analyserMiniWindow:getParent():moveChildToIndex(analyserMiniWindow, #analyserMiniWindow:getParent():getChildren())
      modules.game_sidebuttons.setButtonVisible("analyticsSelectorWidget", true)
      analyserMiniWindow.isOpen = true
    end
  end
end

function hide()
  analyserMiniWindow:close()
  analyserMiniWindow.isOpen = false
  modules.game_sidebuttons.setButtonVisible("analyticsSelectorWidget", false)
end

function onOpen()
  analyserMiniWindow:setHeight(247)
  analyserMiniWindow.isOpen = true
end

function show()
  analyserMiniWindow:open()
  analyserMiniWindow.isOpen = true
  modules.game_sidebuttons.setButtonVisible("analyticsSelectorWidget", true)
end

function toggleAnalysers(buttonId)
  local buttonWidget = analyserMiniWindow:recursiveGetChildById(buttonId)
  local widget = openedWindows[buttonId]
  if not widget then
    return
  end

  if widget:isVisible() then
    widget:close()
    widget.isOpen = false
    buttonWidget:setOn(false)
    if buttonId == 'bossButton' then
      toggleBossCDFocus(false)
    end
  else
    if m_interface.addToPanels(widget) then
      widget:getParent():moveChildToIndex(widget, #widget:getParent():getChildren())
    end
    widget.isOpen = true
    widget:open()
    buttonWidget:setOn(true)

    if buttonId == 'impactButton' then
      ImpactAnalyser:checkAnchos()
    elseif buttonId == 'damageButton' then
      InputAnalyser:checkAnchos()
    elseif buttonId == 'xpButton' then
      XPAnalyser:checkAnchos()
    elseif buttonId == 'bossButton' then
      toggleBossCDFocus(false)
      widget:focus()
    elseif buttonId == 'xpAnalyser' then
      XPAnalyser:checkAnchos()
    end
  end
end

function onExperienceChange(localPlayer, value)
  HuntingAnalyser:setupStartExp(value)
  XPAnalyser:setupStartExp(value)
end

function onUpdateExperience(rawExp, exp)
  HuntingAnalyser:addRawXPGain(rawExp)
  HuntingAnalyser:addXpGain(exp)
  XPAnalyser:addRawXPGain(rawExp)
  XPAnalyser:addXpGain(exp)
end

function onLootStats(item, name)
  HuntingAnalyser:addLootedItems(item, name)
  LootAnalyser:addLootedItems(item, name)
end

function onSupplyTracker(itemId)
  HuntingAnalyser:addSuppliesItems(itemId)
  SupplyAnalyser:addSuppliesItems(itemId)
end

function onImpactTracker(analyzerType, amount, effect, target)
  if analyzerType == ANALYZER_HEAL then
    HuntingAnalyser:addHealing(amount)
    ImpactAnalyser:addHealing(amount)
  elseif analyzerType == ANALYZER_DAMAGE_DEALT then
    HuntingAnalyser:addDealDamage(amount)
    ImpactAnalyser:addDealDamage(amount, effect)
  elseif analyzerType == ANALYZER_DAMAGE_RECEIVED then
    InputAnalyser:addInputDamage(amount, effect, target)
  end
end

function onKillTracker(monsterName, monsterOutfit, dropItems)
  HuntingAnalyser:addMonsterKilled(monsterName)
  DropTrackerAnalyser:checkMonsterKilled(monsterName, monsterOutfit, dropItems)
end


-- Loot and Wast file
function loadGainAndWastConfigJson()
  local config = {
    gainGaugeTarget = 0,
    gainGaugeVisible = true,
    gainGraphVisible = true,
    wasteGaugeTarget = 0,
    wasteGaugeVisible = true,
    wasteGraphVisible = true,
  }

  if not LoadedPlayer:isLoaded() then return end

  local file = "/characterdata/" .. LoadedPlayer:getId() .. "/gainandwaste.json"
  if g_resources.fileExists(file) then
    local status, result = pcall(function()
      return json.decode(g_resources.readFileContents(file))
    end)

    if not status then
      return g_logger.error("Error while reading characterdata file. Details: " .. result)
    end

    config = result
  end

  LootAnalyser:setLootPerHourGauge(config.gainGaugeVisible)
  LootAnalyser:setLootPerHourGraph(config.gainGraphVisible)
  LootAnalyser:setTarget(config.gainGaugeTarget)

  SupplyAnalyser:setSupplyPerHourGauge(config.wasteGaugeVisible)
  SupplyAnalyser:setSupplyPerHourGraph(config.wasteGraphVisible)
  SupplyAnalyser:setTarget(config.wasteGaugeTarget)
end

function saveGainAndWastConfigJson()
  if not LoadedPlayer:isLoaded() then return end
  local config = {
    gainGaugeTarget = LootAnalyser:getTarget(),
    gainGaugeVisible = LootAnalyser:gaugeIsVisible(),
    gainGraphVisible = LootAnalyser:graphIsVisible(),
    wasteGaugeTarget = SupplyAnalyser:getTarget(),
    wasteGaugeVisible = SupplyAnalyser:gaugeIsVisible(),
    wasteGraphVisible = SupplyAnalyser:graphIsVisible(),
  }

  local file = "/characterdata/" .. LoadedPlayer:getId() .. "/gainandwaste.json"
  local status, result = pcall(function() return json.encode(config, 2) end)
  if not status then
    return g_logger.error("Error while saving profile Analyzer data. Data won't be saved. Details: " .. result)
  end

  if result:len() > 100 * 1024 * 1024 then
    return g_logger.error("Something went wrong, file is above 100MB, won't be saved")
  end
  g_resources.writeFileContents(file, result)
end

function checkNumber(self, text)
  local number = tonumber(text)
  if (not number or number < 0) and #text > 1 then
    self:setText('0', false)
  end
end

function onLevelChange(localPlayer, value, percent)
  XPAnalyser:setupLevel(value, percent)
end

function managerDropTracker(itemId, checked)
  DropTrackerAnalyser:managerDropItem(itemId, checked)
end

function isInDropTracker(itemId)
  return DropTrackerAnalyser:isInDropTracker(itemId)
end

function onPartyAnalyzer(startTime, leaderID, lootType, membersData, membersName)
  PartyHuntAnalyser:onPartyAnalyzer(startTime, leaderID, lootType, membersData, membersName)
end

function onBossCooldown(bossIds, cooldownTimestamps, bossNames, bossOutfits)
  local cooldown = {}
  for i = 1, #bossIds do
    cooldown[i] = {bossIds[i], cooldownTimestamps[i], bossNames[i], bossOutfits[i]}
  end
  BossCooldown:setupCooldown(cooldown)
end

function onCloseMiniWindow(self)
  self.isOpen = false
end

function onPlayerLoad()

end

function onPlayerUnload()

end

function moveAnalyser(panel, height, minimzed)
  analyserMiniWindow:setParent(panel)
  analyserMiniWindow:open()

  if minimzed then
    analyserMiniWindow:setHeight(height)
    analyserMiniWindow:minimize()
  else
    -- Hardcoded height
    if height < 247 then
      height = 247
    end

    analyserMiniWindow:maximize()
    analyserMiniWindow:setHeight(height)
  end

  return analyserMiniWindow
end

function moveChildAnalyser(type, panel, height, minimzed)
  local window = {
    ['bossCooldowns'] = 'bossButton',
    ['damageInputAnalyser'] = 'damageButton',
    ['lootTracker'] = 'dropButton',
    ['huntingSessionAnalyser'] = 'huntingButton',
    ['impactAnalyser'] = 'impactButton',
    ['lootAnalyser'] = 'lootButton',
    ['partyHuntAnalyser'] = 'partyButton',
    ['wasteAnalyser'] = 'supplyButton',
    ['xpAnalyser'] = 'xpButton',
    ['miscAnalyzer'] = 'miscButton'
  }

  local widget = openedWindows[window[type]]
  if widget then
    widget:setParent(panel)
    widget:open()

    if minimzed then
      widget:setHeight(height)
      widget:minimize()
    else
      widget:maximize()
      widget:setHeight(height)
    end

    if type == 'xpAnalyser' then
      XPAnalyser:checkAnchos()
    end

    -- check
    local buttonWidget = analyserMiniWindow:recursiveGetChildById(window[type])
    if buttonWidget then
      buttonWidget:setOn(true)
    end
  end

  return widget
end

function onCharmActivated(charmId)
  MiscAnalyzer:onCharmActivated(charmId)
end

function onImbuementActivated(imbuementId, amount)
  MiscAnalyzer:onImbuementActivated(imbuementId, amount)
end

function onSpecialSkillActivated(skillId)
  MiscAnalyzer:onSpecialSkillActivated(skillId)
end
