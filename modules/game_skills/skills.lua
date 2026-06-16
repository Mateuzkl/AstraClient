skillsWindow = nil
storeXPButton = nil

local storeBoostTimerEvent = nil
local storeBoostTime = 0

local healthUpdateEvent = nil
local manaUpdateEvent = nil
local lastHealthValue = nil
local lastManaValue = nil

skillWidgetsOptions = {}

local combatElementMap = {
  [0] = "physical",
  [1] = "fire",
  [2] = "earth",
  [3] = "energy",
  [4] = "ice",
  [5] = "holy",
  [6] = "death",
  [7] = "healing",
  [8] = "drowning",
  [9] = "lifeDrain",
  [10] = "manaDrain",
  [11] = "agony",
}

local function onWheelSkillStats(protocol, opcode, data)
  if type(data) ~= "table" then
    return
  end

  local offensePanel = skillsWindow:recursiveGetChildById("attackPanel")

  local dmgHealWidget = skillsWindow:recursiveGetChildById("damageHealingLabel")
  local dmgHealVal = tonumber(data.damageAndHealing) or 0
  if dmgHealWidget then
    dmgHealWidget:setText(tostring(math.floor(dmgHealVal + 0.5)))
  end

  local atkWidget = skillsWindow:recursiveGetChildById("attackValue")
  local atkVal = tonumber(data.attackValue) or 0
  local atkElem = tonumber(data.attackElement) or 0
  if atkWidget then
    atkWidget:recursiveGetChildById("value"):setText(tostring(math.floor(atkVal + 0.5)))
    if atkVal > 0 then
      atkWidget:recursiveGetChildById("value"):setColor("#44ad25")
    end
    atkWidget:recursiveGetChildById("combatIcon"):setImageSource("/game_cyclopedia/images/icons/stats/element_" .. atkElem)
  end

  local lifeWidget = skillsWindow:recursiveGetChildById("lifeLeech")
  local lifeVal = tonumber(data.lifeLeech) or 0
  if lifeWidget and math.abs(lifeVal) > 0.0001 then
    lifeWidget:recursiveGetChildById("value"):setText(string.format("+%.2f%%", lifeVal * 100))
    lifeWidget:recursiveGetChildById("value"):setColor("#44ad25")
    lifeWidget:setVisible(true)
  elseif lifeWidget then
    lifeWidget:setVisible(false)
  end

  local manaWidget = skillsWindow:recursiveGetChildById("manaLeech")
  local manaVal = tonumber(data.manaLeech) or 0
  if manaWidget and math.abs(manaVal) > 0.0001 then
    manaWidget:recursiveGetChildById("value"):setText(string.format("+%.2f%%", manaVal * 100))
    manaWidget:recursiveGetChildById("value"):setColor("#44ad25")
    manaWidget:setVisible(true)
  elseif manaWidget then
    manaWidget:setVisible(false)
  end

  local critChance = tonumber(data.criticalChance) or 0
  local critDamage = tonumber(data.criticalDamage) or 0
  local critSeparator = skillsWindow:recursiveGetChildById("skillIdHitSeparator")
  local critChanceWidget = skillsWindow:recursiveGetChildById("criticalChance")
  local critDamageWidget = skillsWindow:recursiveGetChildById("criticalDamage")
  if critSeparator and (math.abs(critChance) > 0.0001 or math.abs(critDamage) > 0.0001) then
    critSeparator:setVisible(true)
  elseif critSeparator then
    critSeparator:setVisible(false)
  end
  if critChanceWidget and math.abs(critChance) > 0.0001 then
    critChanceWidget:recursiveGetChildById("value"):setText(string.format("+%.2f%%", critChance * 100))
    critChanceWidget:recursiveGetChildById("value"):setColor("#44ad25")
    critChanceWidget:setVisible(true)
  elseif critChanceWidget then
    critChanceWidget:setVisible(false)
  end
  if critDamageWidget and math.abs(critDamage) > 0.0001 then
    critDamageWidget:recursiveGetChildById("value"):setText(string.format("+%.2f%%", critDamage * 100))
    critDamageWidget:recursiveGetChildById("value"):setColor("#44ad25")
    critDamageWidget:setVisible(true)
  elseif critDamageWidget then
    critDamageWidget:setVisible(false)
  end

  local defenseVal = tonumber(data.defense) or 0
  local armorVal = tonumber(data.armor) or 0
  local mitiVal = tonumber(data.mitigation) or 0

  local defWidget = skillsWindow:recursiveGetChildById("defenseValue")
  if defWidget then
    defWidget:recursiveGetChildById("value"):setText(tostring(math.floor(defenseVal + 0.5)))
    if math.abs(defenseVal) > 0.0001 then
      defWidget:recursiveGetChildById("value"):setColor("#44ad25")
    end
  end

  local armorWidget = skillsWindow:recursiveGetChildById("armorValue")
  if armorWidget then
    armorWidget:recursiveGetChildById("value"):setText(tostring(math.floor(armorVal + 0.5)))
    if math.abs(armorVal) > 0.0001 then
      armorWidget:recursiveGetChildById("value"):setColor("#44ad25")
    end
  end

  local mitiWidget = skillsWindow:recursiveGetChildById("mitigationValue")
  if mitiWidget then
    mitiWidget:recursiveGetChildById("value"):setText(string.format("+%.2f%%", mitiVal * 100))
    if math.abs(mitiVal) > 0.0001 then
      mitiWidget:recursiveGetChildById("value"):setColor("#44ad25")
    end
  end

  local convertedWidget = skillsWindow:recursiveGetChildById("convertedDamage")
  local convertedVal = tonumber(data.convertedValue) or 0
  local convertedElem = tonumber(data.convertedElement) or 0
  if convertedWidget then
    if convertedVal > 0 then
      convertedWidget:recursiveGetChildById("value"):setText(string.format("+%d%%", math.floor(convertedVal * 100 + 0.5)))
      convertedWidget:recursiveGetChildById("combatIcon"):setImageSource("/game_cyclopedia/images/icons/stats/element_" .. convertedElem)
      convertedWidget:setVisible(true)
    else
      convertedWidget:setVisible(false)
    end
  end

  if data.absorbs then
    for idx, name in pairs(combatElementMap) do
      local w = skillsWindow:recursiveGetChildById("elementalDefense_" .. idx)
      if w then
        local absorbVal = tonumber(data.absorbs[name]) or 0
        if math.abs(absorbVal) > 0.0001 then
          w:recursiveGetChildById("value"):setText(string.format("%+.2f%%", absorbVal * 100))
          w:recursiveGetChildById("value"):setColor(absorbVal > 0 and "#44ad25" or "#ff9854")
          w:setVisible(true)
        else
          w:setVisible(false)
        end
      end
    end
  end

  scheduleEvent(function()
    skillsWindow:setContentMaximumHeight(math.max(125, getContentPanelHeight() + 6))
  end, 100)
end

local function onMonkData(protocol, opcode, data)
  if type(data) ~= "table" then return end

  local player = g_game.getLocalPlayer()
  if not player then return end

  local harmony = tonumber(data.harmony) or 0
  local serene = data.serene == true

  if modules.game_topbar and modules.game_topbar.onHarmonyChange then
    modules.game_topbar.onHarmonyChange(player, harmony)
  end
  if modules.game_topbar and modules.game_topbar.onSerenityChange then
    modules.game_topbar.onSerenityChange(player, serene)
  end
end

local skillNames = {
  [0] = "Fist",
  [1] = "Club",
  [2] = "Sword",
  [3] = "Axe",
  [4] = "Distance",
  [5] = "Shielding",
  [6] = "Fishing",
  [13] = "Magic Level"
}

local combatNames = {
  [0] = "Physical",
  [1] = "Fire",
  [2] = "Earth",
  [3] = "Energy",
  [4] = "Ice",
  [5] = "Holy",
  [6] = "Death",
  [7] = "Healing",
  [8] = "Drowning",
  [9] = "Life Drain",
  [10] = "Mana Drain",
  [11] = "Agony"
}

local temporaryBonusDescription = {
  [1] = "Your potions and healing spells will heal 20% more\nwhen used on yourself.",
  [2] = "All your damage and defenses against monsters will\nincrease by 15%.",
  [3] = "You will receive a general bonus of 20% on acquired\nexperience.",
  [4] = "Gain a additional 8% of mana leech.",
  [5] = "The Exaltation Overload effect will be applied\nto you."
}

function init()
  connect(LocalPlayer, {
    onExperienceChange = onExperienceChange,
    onLevelChange = onLevelChange,
    onHealthChange = onHealthChange,
    onManaChange = onManaChange,
    onSoulChange = onSoulChange,
    onFreeCapacityChange = onFreeCapacityChange,
    onTotalCapacityChange = onTotalCapacityChange,
    onBaseCapacityChange = onBaseCapacityChange,
    onStaminaChange = onStaminaChange,
    onOfflineTrainingChange = onOfflineTrainingChange,
    onRegenerationChange = onRegenerationChange,
    onSpeedChange = onSpeedChange,
    onBaseSpeedChange = onBaseSpeedChange,
    onMagicLevelChange = onMagicLevelChange,
    onBaseMagicLevelChange = onBaseMagicLevelChange,
    onSkillChange = onSkillChange,
    onBaseSkillChange = onBaseSkillChange,
	  onUpdateGainRate = onUpdateGainRate,
	  onExpBoostChange = onExpBoostChange,
	  onUpdateOffenceStats = onUpdateOffenceStats,
    onUpdateDefenceStats = onUpdateDefenceStats,
    onUpdateMiscStats = onUpdateMiscStats,
    onTemporaryBonusChange = onTemporaryBonusChange,
    onBattlePassBonusChange = onBattlePassBonusChange,
    onMagicBoostChange = onMagicBoostChange,
  })
  connect(g_game, {
    onGameStart = onGameStart,
    onGameEnd = offline
  })

  skillsWindow = g_ui.loadUI('skills')
  ProtocolGame.registerExtendedJSONOpcode(ExtendedIds.WheelSkills, onWheelSkillStats)
  ProtocolGame.registerExtendedJSONOpcode(ExtendedIds.MonkData, onMonkData)
  storeXPButton = skillsWindow:recursiveGetChildById('boostButton')
  skillsWindow:hide()

  -- this disables scrollbar auto hiding
  local scrollbar = skillsWindow:getChildById('miniwindowScrollBar')
  scrollbar:mergeStyle({ ['$!on'] = { }})

  skillsWindow.onMouseRelease = function(widget, mousePos, mouseButton)
    if mouseButton == MouseRightButton then
      showSkillsPopUp(mousePos)
    end
  end

  refresh()
  skillsWindow:setup()
end

function terminate()
  if healthUpdateEvent then
    removeEvent(healthUpdateEvent)
    healthUpdateEvent = nil
  end

  if manaUpdateEvent then
    removeEvent(manaUpdateEvent)
    manaUpdateEvent = nil
  end

  disconnect(LocalPlayer, {
    onExperienceChange = onExperienceChange,
    onLevelChange = onLevelChange,
    onHealthChange = onHealthChange,
    onManaChange = onManaChange,
    onSoulChange = onSoulChange,
    onFreeCapacityChange = onFreeCapacityChange,
    onTotalCapacityChange = onTotalCapacityChange,
    onBaseCapacityChange = onBaseCapacityChange,
    onStaminaChange = onStaminaChange,
    onOfflineTrainingChange = onOfflineTrainingChange,
    onRegenerationChange = onRegenerationChange,
    onSpeedChange = onSpeedChange,
    onBaseSpeedChange = onBaseSpeedChange,
    onMagicLevelChange = onMagicLevelChange,
    onBaseMagicLevelChange = onBaseMagicLevelChange,
    onSkillChange = onSkillChange,
    onBaseSkillChange = onBaseSkillChange,
	  onUpdateGainRate = onUpdateGainRate,
	  onExpBoostChange = onExpBoostChange,
	  onUpdateOffenceStats = onUpdateOffenceStats,
    onUpdateDefenceStats = onUpdateDefenceStats,
    onUpdateMiscStats = onUpdateMiscStats,
    onTemporaryBonusChange = onTemporaryBonusChange,
    onBattlePassBonusChange = onBattlePassBonusChange,
    onMagicBoostChange = onMagicBoostChange,
  })
  disconnect(g_game, {
    onGameStart = onGameStart,
    onGameEnd = offline
  })

  ProtocolGame.unregisterExtendedJSONOpcode(ExtendedIds.WheelSkills)
  ProtocolGame.unregisterExtendedJSONOpcode(ExtendedIds.MonkData)

  skillsWindow:destroy()
end

function expForLevel(level)
  return math.floor((50*level*level*level)/3 - 100*level*level + (850*level)/3 - 200)
end

function expToAdvance(currentLevel, currentExp)
  return expForLevel(currentLevel+1) - currentExp
end

function resetSkillColor(id)
  local skill = skillsWindow:recursiveGetChildById(id)
  if not skill then
	return
  end
  local widget = skill:getChildById('value')
  widget:setColor('#bbbbbb')
end

function toggleSkill(id, state)
  local skill = skillsWindow:recursiveGetChildById(id)
  if not skill then
	return
  end
  skill:setVisible(state)
  scheduleEvent(function()
    skillsWindow:setContentMaximumHeight(math.max(125, getContentPanelHeight() + 6))
  end, 100)
end

function showOrHidePercentBar(skillId)
  if skillId then
    local skill = skillsWindow:recursiveGetChildById(skillId)
    local percentBar = skill:getChildById('percent')
    local skillIcon = skill:getChildById('skillIcon')
    local toggleVisible = not percentBar:isVisible()
    percentBar:setVisible(toggleVisible)
    if toggleVisible then
      skill:setHeight(21)
      for k, v in pairs(skillWidgetsOptions["invisibleProgressBars"]) do
        if v == skillId then
          table.remove(skillWidgetsOptions["invisibleProgressBars"], k)
          break
        end
      end
    else
      skill:setHeight(21 - 7)
      table.insert(skillWidgetsOptions["invisibleProgressBars"], skillId)
    end

    if skillIcon then
      skillIcon:setVisible(toggleVisible)
    end

    scheduleEvent(function()
      skillsWindow:setContentMaximumHeight(math.max(125, getContentPanelHeight() + 6))
    end, 100)
    return
  end

  -- Hide/Show all
  local options = {"level", "stamina", "offlineTraining", "magiclevel"}
  for i = Skill.Fist, Skill.Fishing do
    table.insert(options, "skillId"..i)
  end

  local isVisible = #skillWidgetsOptions["invisibleProgressBars"] == 0
  for _, skillId in pairs(options) do
    local skill = skillsWindow:recursiveGetChildById(skillId)
    local percentBar = skill:getChildById('percent')
    local skillIcon = skill:getChildById('skillIcon')
    if skillIcon then
      skillIcon:setVisible(not isVisible)
    end

    if isVisible then
      percentBar:setVisible(false)
      skill:setHeight(21 - 7)
      table.insert(skillWidgetsOptions["invisibleProgressBars"], skillId)
    else
      percentBar:setVisible(true)
      skill:setHeight(21)
      for k, v in pairs(skillWidgetsOptions["invisibleProgressBars"]) do
        if v == skillId then
          table.remove(skillWidgetsOptions["invisibleProgressBars"], k)
          break
        end
      end
    end
  end

  scheduleEvent(function()
    skillsWindow:setContentMaximumHeight(math.max(125, getContentPanelHeight() + 6))
  end, 100)
end

function updateVisblePercentBar()
  for i = Skill.Fist, Skill.Fishing do
    local skillId = "skillId"..i
    local skill = skillsWindow:recursiveGetChildById(skillId)
    local percentBar = skill:getChildById('percent')
    local skillIcon = skill:getChildById('skillIcon')
    if table.find(skillWidgetsOptions["invisibleProgressBars"], skillId) == nil then
      percentBar:setVisible(true)
      skill:setHeight(21)
      if skillIcon then
        skillIcon:setVisible(true)
      end
    else
      percentBar:setVisible(false)
      skill:setHeight(21 - 7)
      if skillIcon then
        skillIcon:setVisible(false)
      end
    end
  end
end

function resetPercentVisibility()
  local options = {"level", "stamina", "offlineTraining", "magiclevel"}
  for i = Skill.Fist, Skill.Fishing do
    table.insert(options, "skillId"..i)
  end

  for _, skillId in pairs(options) do
    local skill = skillsWindow:recursiveGetChildById(skillId)
    local percentBar = skill:getChildById('percent')
    percentBar:setVisible(true)
    skill:setHeight(21)
  end
end

function getContentPanelHeight()
  local calculatedHeight = 0
  local contentPanel = skillsWindow:recursiveGetChildById("contentsPanel")
  if not contentPanel then
    return 0
  end

  for _, widget in pairs(contentPanel:getChildren()) do
    if widget:isVisible() then
      calculatedHeight = calculatedHeight + widget:getHeight()

      if widget:getMarginTop() > 0 then
        calculatedHeight = calculatedHeight + widget:getMarginTop()
      end

      if widget:getId() == 'miscPanel' and widget:getMarginBottom() > 0 then
        calculatedHeight = calculatedHeight + widget:getMarginBottom() + 8
      end
    end
  end
  return calculatedHeight
end

function showSkillsPopUp(mousePosition)
  local menu = g_ui.createWidget('PopupMenu')
  menu:setGameMenu(true)
  menu:addOption(tr('Reset Experience Counter'), function() g_game.getLocalPlayer().expSpeed = 0; end) -- aqui tem que trocar a tooltip tbm
  menu:addSeparator()
  menu:addCheckBoxOption(tr('Level'), function() showOrHidePercentBar("level") end, "", table.find(skillWidgetsOptions["invisibleProgressBars"], "level") == nil)
  menu:addCheckBoxOption(tr('Stamina'), function() showOrHidePercentBar("stamina") end, "", table.find(skillWidgetsOptions["invisibleProgressBars"], "stamina") == nil)
  menu:addCheckBoxOption(tr('Offline Training'), function() showOrHidePercentBar("offlineTraining") end, "", table.find(skillWidgetsOptions["invisibleProgressBars"], "offlineTraining") == nil)
  menu:addCheckBoxOption(tr('Magic'), function() showOrHidePercentBar("magiclevel") end, "", table.find(skillWidgetsOptions["invisibleProgressBars"], "magiclevel") == nil)
  for i = Skill.Fist, Skill.Fishing do
    local skillName = skillNames[i]
    menu:addCheckBoxOption(tr(skillName), function() showOrHidePercentBar("skillId"..i) end, "", table.find(skillWidgetsOptions["invisibleProgressBars"], "skillId"..i) == nil)
  end

  menu:addSeparator()
  menu:addCheckBoxOption(tr('Offence Stats'), function()
    local currentState = skillWidgetsOptions["offenceStatsVisible"]
    manageOffenceStats(not currentState)
    skillWidgetsOptions["offenceStatsVisible"] = not currentState
  end, "", skillWidgetsOptions["offenceStatsVisible"])

  menu:addCheckBoxOption(tr('Defence Stats'), function()
    local currentState = skillWidgetsOptions["defenceStatsVisible"]
    manageDefenceStats(not currentState)
    skillWidgetsOptions["defenceStatsVisible"] = not currentState
  end, "", skillWidgetsOptions["defenceStatsVisible"])

  menu:addCheckBoxOption(tr('Misc. Stats'), function()
    local currentState = skillWidgetsOptions["miscStatsVisible"]
    manageMiscStats(not currentState)
    skillWidgetsOptions["miscStatsVisible"] = not currentState
  end, "", skillWidgetsOptions["miscStatsVisible"])

  menu:addSeparator()
  menu:addCheckBoxOption(tr('Show all Skill Bars'), function() showOrHidePercentBar(nil) end, "", #skillWidgetsOptions["invisibleProgressBars"] == 0)

  menu:display(mousePosition)
end

function setSkillBase(id, value, baseValue, loyalty)
  if loyalty == nil then
    loyalty = 0
  end

  local skill = skillsWindow:recursiveGetChildById(id)
  if not skill then
    return
  end

  local converId = id:gsub("%D", "")
  local skillNumber = tonumber(converId)
  if skillNumber and skillNumber >= 7 then
    return
  end

  local widget = skill:getChildById('value')
  local percentWidget = skill:getChildById('percent')

  skill:removeTooltip()
  widget:setColor('#bbbbbb')

  local additionalTooltip = ''
  if id == 'magiclevel' then
    local player = g_game.getLocalPlayer()
    if player and player.getMagicBoosts then
      local magicBoost = player:getMagicBoosts()
      if magicBoost and table.size(magicBoost) > 0 then
        additionalTooltip = tr('\n\nAdditional magic level modifiers:')
        for i, count in pairs(magicBoost) do
          additionalTooltip = additionalTooltip .. string.format("\n%s magic level +%d", combatNames[i], count)
        end
      end
    end
  end

  if baseValue <= 0 or value < 0 or (baseValue == value) then
    if percentWidget then
      local tooltip = ''
      if loyalty > 0 then
        tooltip = tr("%s = %s (+%s Loyalty)\n", (baseValue + loyalty), baseValue, loyalty)
      end
      local percent = tr('%sYou have %s percent to go%s', tooltip, convertSkillPercent(10000 - (percentWidget:getPercent() * 100), false), additionalTooltip)
      percentWidget:setTooltip(percent)
      skill:setTooltip(percent)
    end
    return
  end

  local realBase = baseValue + loyalty
  local realValue = value + loyalty

  if value > baseValue or (realBase > baseValue) then
	  local tooltip = tr("%s = %s", realValue, baseValue)
	  if value > baseValue then
		  tooltip = tr("%s +%s", tooltip, (value - baseValue))
		  widget:setColor('#44ad25') -- green
	  end

	  if loyalty > 0 then
		  tooltip = tr("%s (+%s Loyalty)", tooltip, loyalty)
	  end

    local percentWidget = skill:getChildById('percent')
    if percentWidget then
      local percent = tr('You have %s percent to go', convertSkillPercent(10000 - (percentWidget:getPercent() * 100), false))
      tooltip = tooltip .. '\n' .. percent
      percentWidget:setTooltip(tooltip .. additionalTooltip)
    end

    tooltip = tooltip .. additionalTooltip
    skill:setTooltip(tooltip)
  elseif value < baseValue then
    widget:setColor('#c00000') -- red
    skill:setTooltip(baseValue .. ' ' .. (value - baseValue))
  else
    widget:setColor('#bbbbbb') -- default
    skill:removeTooltip()
  end
end

function setSkillValue(id, value)
  local skill = skillsWindow:recursiveGetChildById(id)
  if not skill then
	  return
  end

  local widget = skill:getChildById('value')
  if value == 0 then
	  widget:setColor('#bbbbbb') -- reset
  end

  if id == 'capacity' then
    local player = g_game.getLocalPlayer()
    if value == 0 then
      widget:setColor('$var-text-cip-store-red')
    elseif player and player:getTotalCapacity() ~= player:getBaseCapacity() then
      widget:setColor('#44ad25') -- green
    else
      widget:setColor('#bbbbbb') -- reset
    end
    value = math.floor(value)
  end

  if id == 'regenerationTime' then
    local tooltip = "You are hungry.\nEat something to regenerate your and mana over time"
    local hours, minutes, seconds = string.match(value, "(%d%d):(%d%d):(%d%d)")
    if value ~= "00:00:00" then
      if tonumber(hours) > 0 then
        tooltip = tr("You are regenerating hit points and mana for %s hours and %s minutes", hours, minutes)
      else
        tooltip = tr("You are regenerating hit points and mana for %s minutes and %s seconds", minutes, seconds)
      end
    end

    value = hours .. ":" .. minutes
    skill:setTooltip(tooltip)
  end

  widget:setText(value)

  local expLabel = skillsWindow:recursiveGetChildById('expLabel')
  if id == "experience" then
    if widget:getWidth() > 75 then
        expLabel:setText("XP")
    else
        expLabel:setText("Experience")
    end
  end

end

function setSkillColor(id, value)
  local skill = skillsWindow:recursiveGetChildById(id)
  local widget = skill:getChildById('value')
  widget:setColor(value)
end

function setSkillTooltip(id, value)
  local skill = skillsWindow:recursiveGetChildById(id)
  local widget = skill:getChildById('value')
  widget:setTooltip(value)
end

function setSkillPercent(id, percent, tooltip, color)
  local skill = skillsWindow:recursiveGetChildById(id)
  if not skill then
	  return
  end

  local widget = skill:getChildById('percent')
  if widget then
    widget:setPercent(percent)
    if table.contains({'offlineTraining', 'stamina'}, id) then
      widget:setPercent(math.floor(percent))
    end

	if id == 'offlineTraining' then
		widget:setBackgroundColor('#c00000') -- red
	end

    if color then
    	widget:setBackgroundColor(color)
    end

    if not table.empty(skillWidgetsOptions) and table.contains(skillWidgetsOptions["invisibleProgressBars"], id) then
      widget:setVisible(false)
    end
  end
end

function update()
  local offlineTraining = skillsWindow:recursiveGetChildById('offlineTraining')
  if not g_game.getFeature(GameOfflineTrainingTime) then
    offlineTraining:hide()
  else
    offlineTraining:show()
  end

  local regenerationTime = skillsWindow:recursiveGetChildById('regenerationTime')
  if not g_game.getFeature(GamePlayerRegenerationTime) then
    regenerationTime:hide()
  else
    regenerationTime:show()
  end
end

function onGameStart()
  local benchmark = g_clock.millis()
  refresh()
  consoleln("Skills loaded in " .. (g_clock.millis() - benchmark) / 1000 .. " seconds.")
end

function refresh()
  local player = g_game.getLocalPlayer()
  if not player then return end

  skillWidgetsOptions = modules.game_sidebars.getSkillsWidgetConfig()
  if table.empty(skillWidgetsOptions) then
    skillWidgetsOptions = {
      ["contentHeight"] = 0,
      ["contentMaximized"] = true,
      ["invisibleProgressBars"] = {},
      ["defenceStatsVisible"] = true,
      ["miscStatsVisible"] = true,
      ["offenceStatsVisible"] = true
    }
  end

  local missingOptions = {"defenceStatsVisible", "miscStatsVisible", "offenceStatsVisible"}
  for _, option in pairs(missingOptions) do
    if skillWidgetsOptions[option] == nil then
      skillWidgetsOptions[option] = true
    end
  end

  for i = Skill.Fist, Skill.Fishing do
    updateVisblePercentBar()
  end

  manageOffenceStats(skillWidgetsOptions["offenceStatsVisible"])
  manageDefenceStats(skillWidgetsOptions["defenceStatsVisible"])
  manageMiscStats(skillWidgetsOptions["miscStatsVisible"])

  if expSpeedEvent then removeEvent(expSpeedEvent) end
  expSpeedEvent = cycleEvent(checkExpSpeed, 30*1000)

  onExperienceChange(player, player:getExperience())
  onLevelChange(player, player:getLevel(), player:getLevelPercent())
  onHealthChange(player, player:getHealth(), player:getMaxHealth())
  onManaChange(player, player:getMana(), player:getMaxMana())
  onSoulChange(player, player:getSoul())
  onFreeCapacityChange(player, player:getFreeCapacity())
  onTotalCapacityChange(player, player:getFreeCapacity())
  onBaseCapacityChange(player, player:getFreeCapacity())
  onStaminaChange(player, player:getStamina())
  onMagicLevelChange(player, player:getMagicLevel(), player:getMagicLevelPercent())
  onOfflineTrainingChange(player, player:getOfflineTrainingTime())
  onRegenerationChange(player, player:getRegenerationTime())
  onSpeedChange(player, player:getSpeed())
  onMagicBoostChange(player, player:getMagicBoosts())

  local hasAdditionalSkills = g_game.getFeature(GameAdditionalSkills)
  for i = Skill.Fist, Skill.Fishing do
    onSkillChange(player, i, player:getSkillLevel(i), player:getSkillLevelPercent(i))
    onBaseSkillChange(player, i, player:getSkillBaseLevel(i))
  end

  update()

  skillsWindow:setContentMinimumHeight(44)
  if hasAdditionalSkills then
    skillsWindow:setContentMaximumHeight(680)
  else
    skillsWindow:setContentMaximumHeight(390)
  end
end

function offline()
  if healthUpdateEvent then
    removeEvent(healthUpdateEvent)
    healthUpdateEvent = nil
  end

  if manaUpdateEvent then
    removeEvent(manaUpdateEvent)
    manaUpdateEvent = nil
  end

  if expSpeedEvent then expSpeedEvent:cancel() expSpeedEvent = nil end

  rateHighlightEvent = nil
  resetPercentVisibility()
  skillsWindow:close()
  skillsWindow:setParent(nil)
end

function toggle()
  if modules.game_sidebuttons.isButtonVisible("skillsWidget") then
    skillsWindow:close()
    modules.game_sidebuttons.setButtonVisible("skillsWidget", false)
  else
    skillsWindow:open()
    if m_interface.addToPanels(skillsWindow) then
      skillsWindow:getParent():moveChildToIndex(skillsWindow, #skillsWindow:getParent():getChildren())
      modules.game_sidebuttons.setButtonVisible("skillsWidget", true)

      scheduleEvent(function()
        skillsWindow:setContentMaximumHeight(math.max(125, getContentPanelHeight() + 6))
      end, 100)

    end
  end
end

function close()
  skillsWindow:close()
end

function open()
  skillsWindow:open()
  if m_interface.addToPanels(skillsWindow) then
    skillsWindow:getParent():moveChildToIndex(skillsWindow, #skillsWindow:getParent():getChildren())
    modules.game_sidebuttons.setButtonVisible("skillsWidget", true)
    scheduleEvent(function()
      skillsWindow:setContentMaximumHeight(math.max(125, getContentPanelHeight() + 6))
    end, 100)
  else
    modules.game_sidebuttons.setButtonVisible("skillsWidget", false)
  end
end

function checkExpSpeed()
  local player = g_game.getLocalPlayer()
  if not player then return end

  local currentExp = player:getExperience()
  local currentTime = g_clock.seconds()
  if player.lastExps ~= nil then
    player.expSpeed = (currentExp - player.lastExps[1][1])/(currentTime - player.lastExps[1][2])
    onLevelChange(player, player:getLevel(), player:getLevelPercent())
  else
    player.lastExps = {}
  end
  table.insert(player.lastExps, {currentExp, currentTime})
  if #player.lastExps > 30 then
    table.remove(player.lastExps, 1)
  end
end

function onMiniWindowClose()
  modules.game_sidebuttons.setButtonVisible("skillsWidget", false)
end

function onExperienceChange(localPlayer, value, oldValue)
  if value >= 1*(1000000000000000) then
    setSkillValue('experience', "1kkkk+")
  else
    setSkillValue('experience', comma_value(value))
  end
end

function onLevelChange(localPlayer, value, percent)
  setSkillValue('level', comma_value(value))
  local levelLabel = skillsWindow:recursiveGetChildById('level')
  levelLabel:recursiveGetChildById('percent'):setTooltip(tr('You have %s percent to go', 100 - percent))

  local text = tr("%s XP for next level", comma_value(expToAdvance(localPlayer:getLevel(), localPlayer:getExperience())))
  if localPlayer.expSpeed ~= nil then
     local expPerHour = math.floor(localPlayer.expSpeed * 3600)
     if expPerHour > 0 then
        local nextLevelExp = expForLevel(localPlayer:getLevel()+1)
        local hoursLeft = (nextLevelExp - localPlayer:getExperience()) / expPerHour
        local minutesLeft = math.floor((hoursLeft - math.floor(hoursLeft))*60)
        hoursLeft = math.floor(hoursLeft)
        text = text .. '\n' .. tr('currently %s XP per hour, next level in %d hours and %d minutes', comma_value(expPerHour), hoursLeft, minutesLeft)
     end
  end

  local experienceLabel = skillsWindow:recursiveGetChildById('experience')
  experienceLabel:setTooltip(text)
  setSkillPercent('level', percent)
  modules.game_topbar.updateLevelTooltip(text)
end

function onHealthChange(localPlayer, health, maxHealth)
  lastHealthValue = health

  if healthUpdateEvent then
    removeEvent(healthUpdateEvent)
  end

  healthUpdateEvent = scheduleEvent(function()
    setSkillValue('health', lastHealthValue)
    healthUpdateEvent = nil
  end, 50) -- 50ms debounce delay
end

function onManaChange(localPlayer, mana, maxMana)
  lastManaValue = mana

  if manaUpdateEvent then
    removeEvent(manaUpdateEvent)
  end

  manaUpdateEvent = scheduleEvent(function()
    setSkillValue('mana', lastManaValue)
    manaUpdateEvent = nil
  end, 50) -- 50ms debounce delay
end

function onSoulChange(localPlayer, soul)
  setSkillValue('soul', soul)
end

function onFreeCapacityChange(localPlayer, freeCapacity)
  setSkillValue('capacity', freeCapacity)
end

function onTotalCapacityChange(localPlayer, totalCapacity)
  local player = g_game.getLocalPlayer()
  setSkillValue('capacity', player and player:getFreeCapacity() or 0)
end

function onBaseCapacityChange(localPlayer, totalCapacity)
  local player = g_game.getLocalPlayer()
  setSkillValue('capacity', player and player:getFreeCapacity() or 0)
end

function onStaminaChange(localPlayer, stamina)
	local hours = math.floor(stamina / 60)
	local minutes = stamina % 60
	if minutes < 10 then
		minutes = '0' .. minutes
	end
	local percent = math.floor(100 * stamina / (42 * 60)) -- max is 42 hours --TODO not in all client versions

	setSkillValue('stamina', hours .. ":" .. minutes)

    --TODO not all client versions have premium time
	local text = ""
	if stamina > (39*60) and g_game.getClientVersion() >= 1038 then
		text = tr("You have %s hours and %s minutes left and receive ", hours, minutes) .. "50% more\nexperience (Premium Only)"
		setSkillPercent('stamina', percent, text, 'green')
	elseif stamina > (39*60) and g_game.getClientVersion() < 1038 then
		text = tr("You have %s hours and %s minutes left", hours, minutes) .. '\n' ..
		tr("If you are premium player, you will gain 50%% more experience")
		setSkillPercent('stamina', percent, text, 'green')
	elseif stamina <= (39*60) and stamina > 840 then
		setSkillPercent('stamina', percent, tr("You have %s hours and %s minutes left", hours, minutes), 'orange')
	elseif stamina <= 840 and stamina > 0 then
		text = tr("You have %s hours and %s minutes left", hours, minutes) .. "\n" ..
		tr("You gain only 50%% experience and you don't may gain loot from monsters")
		setSkillPercent('stamina', percent, text, 'red')
	elseif stamina == 0 then
		text = tr("You have %s hours and %s minutes left", hours, minutes) .. "\n" ..
		tr("You don't may receive experience and loot from monsters")
		setSkillPercent('stamina', percent, text, 'black')
	end
end

function onOfflineTrainingChange(localPlayer, offlineTrainingTime)
  if not g_game.getFeature(GameOfflineTrainingTime) then
    return
  end
  local hours = math.floor(offlineTrainingTime / 60)
  local minutes = offlineTrainingTime % 60
  if minutes < 10 then
    minutes = '0' .. minutes
  end
  local percent = 100 * offlineTrainingTime / (12 * 60) -- max is 12 hours

  setSkillValue('offlineTraining', hours .. ":" .. minutes)
  setSkillPercent('offlineTraining', percent, tr('You have %s hours and %s minutes of offline training time left', hours, tostring(tonumber(minutes))))
end

function onRegenerationChange(localPlayer, regenerationTime)
  if not g_game.getFeature(GamePlayerRegenerationTime) or regenerationTime < 0 then
    return
  end

  local hours = math.floor(regenerationTime / 3600)
  local minutes = math.floor((regenerationTime % 3600) / 60)
  local seconds = regenerationTime % 60

  if hours < 10 then
    hours = '0' .. hours
  end
  if minutes < 10 then
    minutes = '0' .. minutes
  end
  if seconds < 10 then
    seconds = '0' .. seconds
  end

  modules.client_settings.onHungryChange(localPlayer, regenerationTime > 0)
  setSkillValue('regenerationTime', hours .. ":" .. minutes .. ":" .. seconds)
end


function onSpeedChange(localPlayer, speed)
  setSkillValue('speed', speed)
  onBaseSpeedChange(localPlayer, localPlayer:getBaseSpeed())
end

function onBaseSpeedChange(localPlayer, baseSpeed)
  setSkillBase('speed', localPlayer:getSpeed(), baseSpeed)
end

function onMagicLevelChange(localPlayer, magiclevel, percent)
  setSkillValue('magiclevel', magiclevel + localPlayer:getMagicLoyalty())
  setSkillPercent('magiclevel', (percent / 100))
  onBaseMagicLevelChange(localPlayer, localPlayer:getBaseMagicLevel())
end

function onBaseMagicLevelChange(localPlayer, baseMagicLevel)
  setSkillBase('magiclevel', localPlayer:getMagicLevel(), baseMagicLevel, localPlayer:getMagicLoyalty())
end

function onSkillChange(localPlayer, id, level, percent)
  setSkillValue('skillId' .. id, (level + localPlayer:getSkillLoyalty(id)))
  setSkillPercent('skillId' .. id, (percent / 100))
  onBaseSkillChange(localPlayer, id, localPlayer:getSkillBaseLevel(id))
end

function onBaseSkillChange(localPlayer, id, baseLevel)
  setSkillBase('skillId'..id, localPlayer:getSkillLevel(id), baseLevel, localPlayer:getSkillLoyalty(id))
end

function onExpBoostChange(localPlayer, time, canBuy)
  storeXPButton:setVisible(canBuy)
  onUpdateGainRate(localPlayer, localPlayer:getBaseExpRate(), localPlayer:getLowLevelRate(), localPlayer:getExpBoostRate(), localPlayer:getStaminaRate())

  storeBoostTime = time
  if storeBoostTimerEvent then
    removeEvent(storeBoostTimerEvent)
    storeBoostTimerEvent = nil
  end
  if time > 0 then
    storeBoostTimerEvent = scheduleEvent(function()
      storeBoostTime = storeBoostTime - 1
      onUpdateGainRate(localPlayer, localPlayer:getBaseExpRate(), localPlayer:getLowLevelRate(), localPlayer:getExpBoostRate(), localPlayer:getStaminaRate())
    end, 1000)
  else
    local storeBoostValue = skillsWindow:recursiveGetChildById('storeBoostValue')
    storeBoostValue:setText('00:00')
    storeBoostValue:setColor("$var-text-cip-store-red")
  end
end

function onTemporaryBonusChange(localPlayer, bonus, endTime)
  local temporaryBoostPanel = skillsWindow:recursiveGetChildById('temporaryBonus')
  if bonus == 0 then
    temporaryBoostPanel:setVisible(false)
    temporaryBoostPanel:removeTooltip()
    return
  end

  local timeLabel = temporaryBoostPanel:getChildById('temporaryBonusValue')
  temporaryBoostPanel:setVisible(true)
  timeLabel:setText('00:00')

  if endTime > 0 then
    local timeLeft = endTime - os.time()
    if timeLeft < 0 then
      temporaryBoostPanel:setVisible(false)
      timeLabel:setText('00:00')
      return
    end

    local hours = math.floor(timeLeft / 3600)
    local minutes = math.floor((timeLeft % 3600) / 60)
    timeLabel:setText(string.format("%d:%d", hours, minutes))
    temporaryBoostPanel:setTooltip(string.format("Current Temporary Bonus:\n- %s", temporaryBonusDescription[bonus] or ""))
  end
end

function onBoostClick()
  instantlyBuyBoost()
end

local function getXpBoostStoreOffer()
  if not g_game.getStoreOfferBySubtype then
    return nil
  end
  return g_game.getStoreOfferBySubtype("expboost") or g_game.getStoreOfferBySubtype("xpboost")
end

local function getXpBoostPurchaseData()
  local offer = getXpBoostStoreOffer()
  local selectedOffer = offer and offer.offers and offer.offers[1]
  if not offer or not offer.id or not selectedOffer or not selectedOffer.price then
    return nil
  end
  return offer.id, selectedOffer.price
end

function onUpdateGainRate(localPlayer, baseRate, lowLevelBonus, expBoost, staminaMulti)
  if not g_game.isOnline() then
    return
  end

  local rate = skillsWindow:recursiveGetChildById('xpGainRate')
  if not rate then
	return
  end

  local totalGainRate = (baseRate + lowLevelBonus + expBoost) * staminaMulti / 100
  local tooltip = tr("Your current XP gain rate amounts to %s%s.", totalGainRate, "%") .. "\nYour XP gain rate is calculated as follows:\n" .. tr("- Base XP gain rate: %s%s", baseRate, "%")
  if lowLevelBonus ~= 0 then
    tooltip = tr("%s\n- Low level bonus: +%s%s ", tooltip, lowLevelBonus, "%") .. "(until level 50)"
  end

  local formattedTime = formatTimeBySeconds(storeBoostTime)

  if expBoost ~= 0 then
    tooltip = tr("%s\n- XP boost: +%s%s ", tooltip, expBoost, "%") .. tr("(%s remaining)", formattedTime)
    local storeBoostValue = skillsWindow:recursiveGetChildById('storeBoostValue')
    storeBoostValue:setText(formattedTime)

    if storeBoostTime <= 300 then
      storeBoostValue:setColor("$var-text-cip-store-red")
    else
      storeBoostValue:setColor("$var-text-cip-color-green")
    end
  end

  local storeBoostWidget = skillsWindow:recursiveGetChildById('storeBoost')
  storeBoostWidget:setTooltip(tr("XP boost remaining time: %s", formattedTime .. "\n- Click here to increase your experience gain"))
  storeBoostWidget.onClick = onBoostClick

  if staminaMulti > 100 then
    local staminaStr = tostring(staminaMulti)
    formattedStr = staminaStr:sub(1, 1) .. "." .. staminaStr:sub(2)
    finalStr = tostring(tonumber(formattedStr))
    tooltip = tr("%s\n- Stamina bonus: x%s ", tooltip, finalStr) .. tr("(%s h remaining)", formatTimeByMinutes(localPlayer:getStamina() - 2340))
  end

  local widget = rate:getChildById('value')
  widget:setText(totalGainRate .. "%")
  widget:setColor("$var-text-cip-color-green")
  rate:setTooltip(tooltip)

  if not rateHighlightEvent then
    local endTime = g_clock.millis() + 6000
	  rateHighlightEvent = cycleEvent(function()
      if not g_game.isOnline() or not doHighlight then
        rateHighlightEvent = nil
        return
      end
      doHighlight(endTime)
    end, 200)
  end
end

function instantlyBuyBoost()
  local offerId, price = getXpBoostPurchaseData()
  if not offerId then
    if g_game.openStore then
      g_game.openStore()
    end
    displayErrorBox(tr('Warning'), tr('XP boost offer is not loaded. Open the Store and try again.'))
    return
  end

  local yesCallback = function()
    if confirmBoostWindow then
      g_game.buyStoreOffer(offerId, OFFER_BUY_TYPE_OTHERS or 0, "")
      confirmBoostWindow:destroy()
    end
  end

  local noCallback = function()
    if confirmBoostWindow then
      confirmBoostWindow:destroy()
    end
  end

  local message = tr("Do you want to buy an XP boost for %s Astra Coins?", price)
  confirmBoostWindow = displayGeneralBox(tr('Warning'), message, {
    { text=tr('Yes'), callback=yesCallback },
    { text=tr('No'), callback=noCallback },
  }, yesCallback, noCallback)

  onEnter = yesCallback
  onEscape = noCallback
end

function doHighlight(endTime)
  if not g_game.isOnline() or not skillsWindow then
    removeEvent(rateHighlightEvent)
    rateHighlightEvent = nil
    return
  end

  local widget = skillsWindow:recursiveGetChildById('gainLabel')
  if not widget then
    removeEvent(rateHighlightEvent)
    rateHighlightEvent = nil
    return
  end

  if widget:getActionId() == 0 then
    widget:setColor('#ebebeb')
    widget:setActionId(1)
  elseif widget:getActionId() == 1 then
    widget:setColor('#dfdfdf')
    widget:setActionId(2)
  elseif widget:getActionId() == 2 then
    widget:setColor('#d6d6d6')
    widget:setActionId(3)
  elseif widget:getActionId() == 3 then
    widget:setColor('#cecece')
    widget:setActionId(4)
  else
    widget:setColor('#c0c0c0')
    widget:setActionId(0)
  end

  if g_clock.millis() >= endTime then
    removeEvent(rateHighlightEvent)
    rateHighlightEvent = nil
    widget:setColor('#c0c0c0')
  end
end

function move(panel, height, index, minimized)
  skillsWindow:setParent(panel)
  skillsWindow:open()

  if minimized then
    skillsWindow:setHeight(height)
    skillsWindow:minimize()
  else
    skillsWindow:maximize()
    skillsWindow:setHeight(height)
  end

  return skillsWindow
end

function getCombatName(combatId)
  return combatNames[combatId] or "Unkown"
end

function manageOffenceStats(state)
  local panel = skillsWindow:recursiveGetChildById("attackPanel")
  local separator = skillsWindow:recursiveGetChildById("attackSeparator")
  panel:setVisible(state)
  separator:setVisible(state)

  scheduleEvent(function()
    skillsWindow:setContentMaximumHeight(math.max(125, getContentPanelHeight() + 6))
  end, 100)
end

function manageDefenceStats(state)
  local panel = skillsWindow:recursiveGetChildById("defencePanel")
  local separator = skillsWindow:recursiveGetChildById("defenceSeparator")
  panel:setVisible(state)
  separator:setVisible(state)

  scheduleEvent(function()
    skillsWindow:setContentMaximumHeight(math.max(125, getContentPanelHeight() + 6))
  end, 100)
end

function manageMiscStats(state)
  local panel = skillsWindow:recursiveGetChildById("miscPanel")
  local separator = skillsWindow:recursiveGetChildById("miscSeparator")
  panel:setVisible(state)
  separator:setVisible(state)

  scheduleEvent(function()
    skillsWindow:setContentMaximumHeight(math.max(125, getContentPanelHeight() + 6))
  end, 100)
end

function onUpdateOffenceStats(player, damageAndHealing, damageValue, damageElement, convertedValue, convertedElement)
  -- Damage and Healing
  local damageHealingWidget = skillsWindow:recursiveGetChildById('damageHealingLabel')
  damageHealingWidget:setText(damageAndHealing)

  -- Attack Value
  local attackWidget = skillsWindow:recursiveGetChildById('attackValue')
  attackWidget:recursiveGetChildById("value"):setText(damageValue)
  attackWidget:recursiveGetChildById("combatIcon"):setImageSource("/game_cyclopedia/images/icons/stats/element_" .. damageElement)

  -- Converted Damage
  local convertedWidget = skillsWindow:recursiveGetChildById('convertedDamage')
  convertedWidget:recursiveGetChildById("value"):setText("+" .. convertedValue .. "%")
  convertedWidget:recursiveGetChildById("combatIcon"):setImageSource("/game_cyclopedia/images/icons/stats/element_" .. convertedElement)
  convertedWidget:setTooltip(tr(specialTooltips["convertedDamage"], convertedValue, getCombatName(convertedElement)))
  convertedWidget:setVisible(convertedValue > 0)

  if convertedValue > 10.0 then
    convertedWidget:recursiveGetChildById("nameLabel"):setText("Convert...")
  end

  -- Life Leech
  local lifeWidget = skillsWindow:recursiveGetChildById('lifeLeech')
  local lifeLevel = player:getSpecialSkill(Skill.LifeLeechAmount)
  lifeWidget:recursiveGetChildById("value"):setText("+" .. lifeLevel .. "%")
  lifeWidget:setTooltip(tr(specialTooltips["lifeLeech"], lifeLevel))
  lifeWidget:setVisible(lifeLevel > 0)

  -- Mana Leech
  local manaWidget = skillsWindow:recursiveGetChildById('manaLeech')
  local manaLevel = player:getSpecialSkill(Skill.ManaLeechAmount)
  manaWidget:recursiveGetChildById("value"):setText("+" .. manaLevel .. "%")
  manaWidget:setTooltip(tr(specialTooltips["manaLeech"], manaLevel))
  manaWidget:setVisible(manaLevel > 0)

  -- Critical
  local criticalWidget = skillsWindow:recursiveGetChildById('skillIdHitSeparator')
  local chanceWidget = skillsWindow:recursiveGetChildById('criticalChance')
  local extraDamageWidget = skillsWindow:recursiveGetChildById('criticalDamage')

  local chanceLevel = player:getSpecialSkill(Skill.CriticalChance)
  local damageLevel = player:getSpecialSkill(Skill.CriticalDamage)

  chanceWidget:recursiveGetChildById("value"):setText("+" .. chanceLevel .. "%")
  chanceWidget:setTooltip(tr(specialTooltips["criticalChance"], chanceLevel, damageLevel))
  extraDamageWidget:recursiveGetChildById("value"):setText("+" .. damageLevel .. "%")
  extraDamageWidget:setTooltip(tr(specialTooltips["criticalDamage"], chanceLevel, damageLevel))

  criticalWidget:setVisible(chanceLevel > 0 or damageLevel > 0)
  chanceWidget:setVisible(chanceLevel > 0)
  extraDamageWidget:setVisible(damageLevel > 0)

  -- Onslaught
  local onslaughtWidget = skillsWindow:recursiveGetChildById('onslaught')
  local onslaughtLevel = player:getSpecialSkill(Skill.OnslaughtChance)
  onslaughtWidget:recursiveGetChildById('value'):setText("+" .. onslaughtLevel .. "%")
  onslaughtWidget:setTooltip(tr(specialTooltips["onslaught"], onslaughtLevel))
  onslaughtWidget:setVisible(onslaughtLevel > 0)

  scheduleEvent(function()
    skillsWindow:setContentMaximumHeight(math.max(125, getContentPanelHeight() + 6))
  end, 100)
end

function onUpdateDefenceStats(player, elementalProtections, defense, armor, mantra, mitigation, damageReflection)
  -- Combat Defenses
  for i = 0, 11 do
    local value = elementalProtections[i + 1] or 0
    local elementWidget = skillsWindow:recursiveGetChildById('elementalDefense_' .. i)
    if elementWidget then
      elementWidget:setVisible(value ~= 0)
      elementWidget:recursiveGetChildById("value"):setText(value < 0 and (value .. "%") or ("+" .. value .. "%"))
      elementWidget:recursiveGetChildById("value"):setColor(value < 0 and "#ff9854" or "#44ad25")

      local effectStr = value < 0 and "increased" or "reduced"
      local noteStr = specialTooltips["protection_note"]
      elementWidget:setTooltip(tr(specialTooltips["protection"], getCombatName(i), effectStr, value, noteStr))
    end
  end

  -- Defense
  local defenseWidget = skillsWindow:recursiveGetChildById('defenseValue')
  defenseWidget:recursiveGetChildById('value'):setText(defense)

  -- Armor
  local armorWidget = skillsWindow:recursiveGetChildById('armorValue')
  armorWidget:recursiveGetChildById('value'):setText(armor)

  -- Mantra
  local mantraWidget = skillsWindow:recursiveGetChildById('mantraValue')
  mantraWidget:recursiveGetChildById('value'):setText(mantra)

  -- Mitigation
  local mitigationWidget = skillsWindow:recursiveGetChildById('mitigationValue')
  mitigationWidget:recursiveGetChildById('value'):setText("+" .. mitigation .. "%")

  -- Dodge
  local ruseWidget = skillsWindow:recursiveGetChildById('ruseValue')
  local ruseLevel = player:getSpecialSkill(Skill.RuseChance)
  ruseWidget:recursiveGetChildById('value'):setText("+" .. ruseLevel .. "%")
  ruseWidget:setTooltip(tr(specialTooltips["ruseValue"], ruseLevel))
  ruseWidget:setVisible(ruseLevel > 0)

  -- Damage Reflection
  local reflectionWidget = skillsWindow:recursiveGetChildById('reflectionValue')
  reflectionWidget:recursiveGetChildById('value'):setText(damageReflection)
  reflectionWidget:setTooltip(tr(specialTooltips["reflectionValue"], damageReflection))
  reflectionWidget:setVisible(damageReflection > 0)

  scheduleEvent(function()
    skillsWindow:setContentMaximumHeight(math.max(125, getContentPanelHeight() + 6))
  end, 100)
end

function onUpdateMiscStats(player)
  -- Momentum
  local momentumWidget = skillsWindow:recursiveGetChildById('momentumValue')
  local momentumLevel = player:getSpecialSkill(Skill.MomentumChance)
  momentumWidget:recursiveGetChildById('value'):setText("+" .. momentumLevel .. "%")
  momentumWidget:setTooltip(tr(specialTooltips["momentumValue"], momentumLevel))
  momentumWidget:setVisible(momentumLevel > 0)

  -- Transcendence
  local transcendenceWidget = skillsWindow:recursiveGetChildById('transcendenceValue')
  local transcendenceLevel = player:getSpecialSkill(Skill.TranscendenceChance)
  transcendenceWidget:recursiveGetChildById('value'):setText("+" .. transcendenceLevel .. "%")
  transcendenceWidget:setTooltip(tr(specialTooltips["transcendenceValue"], transcendenceLevel))
  transcendenceWidget:setVisible(transcendenceLevel > 0)

  -- Amplification
  local amplificationWidget = skillsWindow:recursiveGetChildById('amplificationValue')
  local amplificationLevel = player:getSpecialSkill(Skill.AmplificationChance)
  amplificationWidget:recursiveGetChildById('value'):setText("+" .. amplificationLevel .. "%")
  amplificationWidget:setTooltip(tr(specialTooltips["amplificationValue"], amplificationLevel))
  amplificationWidget:setVisible(amplificationLevel > 0)

  scheduleEvent(function()
    skillsWindow:setContentMaximumHeight(math.max(125, getContentPanelHeight() + 6))
  end, 100)
end

local boostedBattlePassBonuses = {
  [1] = "Double Experience",
  [2] = "Double Skill",
  [3] = "Double Regeneration",
  [4] = "Exaltation Overload",
  [5] = "Extra Skill"
}

function onBattlePassBonusChange(localPlayer, bonuses)
  local battlePassBoostPanel = skillsWindow:recursiveGetChildById('battlePass')
  if #bonuses == 0 then
    battlePassBoostPanel:setVisible(false)
    battlePassBoostPanel:removeTooltip()
    return
  end

  battlePassBoostPanel:setVisible(true)
  local tooltip = "Current Battle Pass Bonuses:"
  for _, bonus in pairs(bonuses) do
    local stringFormat = "\n%s is active for another %s."
    local stringSkillFormat = "\n+%d extra skill %s fighting is active for another %s."
    local bonusName = boostedBattlePassBonuses[bonus[1]] or "Unknown Bonus"
    local timeLeft = bonus[2]
    local hours = math.floor(timeLeft / 3600)
    local minutes = math.floor((timeLeft % 3600) / 60)
    local timeString = string.format("%d hours and %02d minutes", hours, minutes)
    if hours == 0 then
      timeString = string.format("%02d minutes", minutes)
    end
    if bonus[1] == 5 then
      tooltip = tooltip .. stringSkillFormat:format(bonus[3], skillNames[bonus[4]]:lower(), timeString)
    else
      tooltip = tooltip .. stringFormat:format(bonusName, timeString)
    end

    if bonus[1] == 1 then
      local xpBoostValue = skillsWindow:recursiveGetChildById('battlePassBoostValue')

      xpBoostValue:setText(string.format("%02d:%02d", hours, minutes))
      xpBoostValue:setColor("$var-text-cip-color-green")
      xpBoostValue:setTooltip(tr("Double Experience Boost active for another %s", timeString))
    end

    battlePassBoostPanel:setTooltip(tooltip)
  end

end

function onPlayerUnload()
  if skillWidgetsOptions then
    modules.game_sidebars.registerSkillWidgetsConfig(skillWidgetsOptions)
  end
end

function onMagicBoostChange(localPlayer, magicBoosts)
  setSkillBase('magiclevel', localPlayer:getMagicLevel(), localPlayer:getBaseMagicLevel(), localPlayer:getMagicLoyalty())
end

-- Offline Training Dialog (ported from mehah PR #1604, opcode 0x1B/27)
local offlineTrainingModal = nil

local offlineTrainingDefs = {
    { valueId = "magicValue", barId = "magicBar", name = "Magic", icon = "/images/icons/icon_magic", skillType = 5 },
    { valueId = "fistValue", barId = "fistBar", name = "Fist", icon = "/images/icons/icon_fist", skillType = Skill.Fist },
    { valueId = "clubValue", barId = "clubBar", name = "Club", icon = "/images/icons/icon_club", skillType = Skill.Club },
    { valueId = "swordValue", barId = "swordBar", name = "Sword", icon = "/images/icons/icon_sword", skillType = Skill.Sword },
    { valueId = "axeValue", barId = "axeBar", name = "Axe", icon = "/images/icons/icon_axe", skillType = Skill.Axe },
    { valueId = "distanceValue", barId = "distanceBar", name = "Distance", icon = "/images/icons/icon_distance", skillType = Skill.Distance },
}

function onMultiOfflineTrainingDialog()
    if offlineTrainingModal and not offlineTrainingModal:isDestroyed() then
        offlineTrainingModal:raise()
        offlineTrainingModal:show()
        refreshOfflineTrainingDialog()
        return
    end

    offlineTrainingModal = g_ui.loadUI("offlinetraining")
    if not offlineTrainingModal then return end

    -- Set button handlers
    local btns = {
        magicBtn = 5,
        fistBtn = Skill.Fist,
        clubBtn = Skill.Club,
        swordBtn = Skill.Sword,
        axeBtn = Skill.Axe,
        distanceBtn = Skill.Distance,
    }
    for btnId, skillType in pairs(btns) do
        local btn = offlineTrainingModal:recursiveGetChildById(btnId)
        if btn then
            btn.onClick = function() sendStartOfflineTraining(skillType) end
        end
    end
    local cancelBtn = offlineTrainingModal:recursiveGetChildById("cancelBtn")
    if cancelBtn then cancelBtn.onClick = hideOfflineTrainingDialog end

    local x = (g_window.getDisplaySize().width - offlineTrainingModal:getWidth()) / 2
    local y = (g_window.getDisplaySize().height - offlineTrainingModal:getHeight()) / 2
    offlineTrainingModal:setX(math.floor(x))
    offlineTrainingModal:setY(math.floor(y))
    offlineTrainingModal:show()

    refreshOfflineTrainingDialog()
end

function hideOfflineTrainingDialog()
    if offlineTrainingModal then
        offlineTrainingModal:hide()
    end
end

function refreshOfflineTrainingDialog()
    if not offlineTrainingModal or offlineTrainingModal:isDestroyed() then return end
    local player = g_game.getLocalPlayer()
    if not player then return end
    for _, def in ipairs(offlineTrainingDefs) do
        local val = offlineTrainingModal:recursiveGetChildById(def.valueId)
        local bar = offlineTrainingModal:recursiveGetChildById(def.barId)
        if val then val:setText(tostring(getSkillLevel(def.name, player))) end
        if bar then
            local pct = getSkillPercent(def.name, player) or 0
            bar:setPercent(math.floor(pct))
        end
    end
end

function sendStartOfflineTraining(skillType)
    g_game.sendStartOfflineTraining(skillType)
    hideOfflineTrainingDialog()
end

function getSkillLevel(name, player)
    if name == "Magic" then return player:getMagicLevel() end
    if name == "Fist" then return player:getSkillLevel(Skill.Fist) end
    if name == "Club" then return player:getSkillLevel(Skill.Club) end
    if name == "Sword" then return player:getSkillLevel(Skill.Sword) end
    if name == "Axe" then return player:getSkillLevel(Skill.Axe) end
    if name == "Distance" then return player:getSkillLevel(Skill.Distance) end
    return 0
end

function getSkillPercent(name, player)
    if name == "Magic" then return player:getMagicLevelPercent() end
    if name == "Fist" then return player:getSkillLevelPercent(Skill.Fist) end
    if name == "Club" then return player:getSkillLevelPercent(Skill.Club) end
    if name == "Sword" then return player:getSkillLevelPercent(Skill.Sword) end
    if name == "Axe" then return player:getSkillLevelPercent(Skill.Axe) end
    if name == "Distance" then return player:getSkillLevelPercent(Skill.Distance) end
    return 0
end
