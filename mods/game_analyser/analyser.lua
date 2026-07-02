analyserMiniWindow = nil
if not configPopupWindow then
  configPopupWindow = {}
end

openedWindows = {}

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

-- Misc Analyser proc feed: server (crystalserver) sends charm/imbuement/special-skill
-- activations via this OTC-only extended opcode (see MiscAnalyzer.onMiscProcTracker).
local MISC_PROC_OPCODE = 204

-- objects
function init()
  analyserMiniWindow = g_ui.loadUI('analyser', m_interface.getRightPanel())
  analyserMiniWindow:disableResize()
  analyserMiniWindow:close()
  analyserMiniWindow:setup()

  -- Popup de configuracao de target: usado apenas pelo Drop Tracker. Loot, Supply,
  -- Impact e XP tiveram grafico/target removidos (seus popups de target foram deletados).
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
      -- Keep the selector button in sync whenever the tracker closes through a path
      -- that bypasses toggleAnalysers. Dragging a window out of every panel makes
      -- UIMiniWindow:onDragLeave call self:close() directly, which only fires onClose
      -- and never clears the button's $on state, leaving it lit as if still open.
      connect(openedWindows[id], { onClose = function() onTrackerClosed(id) end })
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

  pcall(function() ProtocolGame.unregisterExtendedOpcode(MISC_PROC_OPCODE) end)
  ProtocolGame.registerExtendedOpcode(MISC_PROC_OPCODE, onMiscProcTracker)

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
  pcall(function() ProtocolGame.unregisterExtendedOpcode(MISC_PROC_OPCODE) end)

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

  consoleln("Analyser loaded in " .. (g_clock.millis() - benchmark) / 1000 .. " seconds")
end

function offlineAnalyser()
  HuntingAnalyser:saveConfigJson()
  ImpactAnalyser:saveConfigJson()
  InputAnalyser:saveConfigJson()
  XPAnalyser:saveConfigJson()
  DropTrackerAnalyser:saveConfigJson()
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
  -- Don't force the expanded height while minimized. minimize() hides contentsPanel and
  -- shrinks the window, and close() doesn't undo that, so forcing 247 here reopened the
  -- panel expanded-but-blank (full height, hidden contents). Only restore the full height
  -- when maximized; a minimized panel reopens minimized, like every other MiniWindow.
  if not analyserMiniWindow.minimized then
    analyserMiniWindow:setHeight(247)
  end
  analyserMiniWindow.isOpen = true
end

function show()
  analyserMiniWindow:open()
  analyserMiniWindow.isOpen = true
  modules.game_sidebuttons.setButtonVisible("analyticsSelectorWidget", true)
end

-- Sync a selector button back to the "off" look when its tracker window closes.
-- Fired from the tracker's onClose, so it covers every close path uniformly: the
-- selector button, the window's own X, and being dragged out of all panels (which
-- goes straight through UIMiniWindow:close() and never touched the button before).
function onTrackerClosed(buttonId)
  if not analyserMiniWindow then return end
  local buttonWidget = analyserMiniWindow:recursiveGetChildById(buttonId)
  if buttonWidget then
    buttonWidget:setOn(false)
  end
  if buttonId == 'bossButton' then
    toggleBossCDFocus(false)
  end
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
    widget.isOpen = true
    widget:open()

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
    elseif buttonId == 'partyButton' then
      -- Party data keeps arriving from the server while the window is closed
      -- (onPartyAnalyzer updates membersData in memory), but updateWindow skips
      -- rendering when hidden. Force a redraw with the current data on open so it
      -- isn't frozen on stale/empty values until the next server tick.
      PartyHuntAnalyser:updateWindow(true, true)
    elseif buttonId == 'lootButton' then
      -- Loot keeps being tracked while the window is closed (onLootStats updates
      -- lootedItems in memory), but the item sprites are only created inside
      -- updateWindow's scroll pass, which is gated by the visibility guard. So a
      -- closed window shows stale sprites until the next drop. Force a redraw with
      -- the accumulated items on open (ignoreVisible=true).
      LootAnalyser:updateWindow(true, true)
    end

    if m_interface.addToPanels(widget) then
      widget:getParent():moveChildToIndex(widget, #widget:getParent():getChildren())
      buttonWidget:setOn(true)
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

function onBossCooldown(cooldown)
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
    elseif type == 'partyHuntAnalyser' then
      PartyHuntAnalyser:updateWindow(true, true)
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
