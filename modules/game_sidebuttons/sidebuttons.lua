buttonsWindow = nil
battleButton = nil
skillsbutton = nil
vipButton = nil
rewardWall = nil
highscore = nil
isHiddenMenuActive = false
currentOpenWidget = nil

local MAIN_BUTTONS_BASE_HEIGHT = 101 -- 77px base + 20px Battle Pass button + 4px margin

-- Hotfix when a new button is introduced
local forceButtons = { "weaponProficiency" }

local buttons = {
  "skillsButton", "battleButton", "partyList", "vipButton", "spellList", "wheel", "questLog",
  "questTracker", "unjustPoints", "preyDialog", "preyWindow", "rewardWall",
  "analytics", "compendium", "cyclopedia", "bosstiaryDialog", "bossSlots",
  "bosstiaryTracker", "bestiary", "imbueTracker", "exaltationForge",
  "socialDialog", "lenshelpFunction", "highscore", "helperDialog", "weaponProficiency",
  "manageShortcuts", "taskHuntDialog"
}

local toggleButtons = {
  "skillsWidget", "battleListWidget", "vipWidget", "questTrackerWidget", "unjustifiedPoinsWidget", "imbuementTrackerWidget",
  "partyWidget", "bosstiaryTrackerWidget", "bestiaryTrackerWidget", "preyWidget", "analyticsSelectorWidget", "spellListWidget", "lenshelpFunction"
}

function getControlButtonTooltip(button)
  local buttonTooltip = ControlButtonTooltips[button]
  if not buttonTooltip then
    return ("%s Unkown")
  end
  return buttonTooltip
end

function openBattlePassWindow()
  if modules.game_battlepass and modules.game_battlepass.BattlePass then
    modules.game_battlepass.BattlePass.onBattlePassBarClick()
  end
end

function init()
  buttonsWindow = g_ui.loadUI('sidebuttons', m_interface.getRightPanel())
  local activeWidgets = Options.getActiveWidgets()
  local inactiveWidgets = Options.getInactiveWidgets()
  local buttonPanel = buttonsWindow:recursiveGetChildById("buttons")
  local storeBorder = buttonsWindow:recursiveGetChildById("storeBorder")

  storeBorder:setImageShader("text_staff")

  for k, v in pairs(forceButtons) do
    if not table.find(activeWidgets, v) and not table.find(inactiveWidgets, v) then
      table.insert(activeWidgets, v)
    end
  end

  for _, v in pairs(activeWidgets) do
    local widget = g_ui.createWidget("UISideButton", buttonPanel)
    widget.button:setImageSource(tr("/images/topbuttons/%s.png", v))
    widget:setId(v)
    widget.button.onClick = function() handleButtonClick(widget.button) end
    widget.button:setTooltip(tr(getControlButtonTooltip(v), "Open"))
  end

  local totalLines = math.max(2, math.ceil(buttonPanel:getChildCount() / 5))
  buttonsWindow:setHeight(MAIN_BUTTONS_BASE_HEIGHT + ((totalLines - 1) * 22))

  if modules.game_minimap and modules.game_minimap.isOpen and modules.game_minimap.isOpen() then
    setButtonVisible("lenshelpFunction", true)
  end

  connect(g_game, {
    onGameStart = online,
    onGameEnd = offline,
    onBestiaryHighlight = onBestiaryHighlight,
    onBosstiaryHighlight = onBosstiaryHighlight,
    onResourceBalance = onResourceBalance,
    onOpenRewardWall = onOpenRewardWall,
    onProficiencyHighlight = onProficiencyHighlight
  })
end

function setButtonVisible(buttonId, state)
  local buttonPanel = buttonsWindow:recursiveGetChildById("buttons")
  local button = buttonPanel:recursiveGetChildById(buttonId)
  if button then
    button.button:setChecked(state)
  end
end

function isButtonVisible(buttonId)
  local buttonPanel = buttonsWindow:recursiveGetChildById("buttons")
  local button = buttonPanel:recursiveGetChildById(buttonId)
  if not button then
    return false
  end

  return button.button:isChecked()
end

function getButtonById(buttonId)
  local buttonPanel = buttonsWindow:recursiveGetChildById("buttons")
  local button = buttonPanel:recursiveGetChildById(buttonId)
  if not button then
    return nil
  end
  return button
end

function updateSideButtons()
  local activeWidgets = Options.getActiveWidgets()
  local inactiveWidgets = Options.getInactiveWidgets()
  local buttonPanel = buttonsWindow:recursiveGetChildById("buttons")

  for k, v in pairs(forceButtons) do
    if not table.find(activeWidgets, v) and not table.find(inactiveWidgets, v) then
      table.insert(activeWidgets, v)
    end
  end

  buttonPanel:destroyChildren()
  for _, v in pairs(activeWidgets) do
    local widget = g_ui.createWidget("UISideButton", buttonPanel)
    widget.button:setImageSource(tr("/images/topbuttons/%s.png", v))
    widget:setId(v)
    widget.button.onClick = function() handleButtonClick(widget.button) end
    widget.button:setTooltip(tr(getControlButtonTooltip(v), "Open"))
  end

  local totalLines = math.max(2, math.ceil(buttonPanel:getChildCount() / 5))
  buttonsWindow:setHeight(MAIN_BUTTONS_BASE_HEIGHT + ((totalLines - 1) * 22))
end

function terminate()
  buttonsWindow:destroy()
  disconnect(g_game, {
    onGameStart = online,
    onGameEnd = offline,
    onBestiaryHighlight = onBestiaryHighlight,
    onBosstiaryHighlight = onBosstiaryHighlight,
    onResourceBalance = onResourceBalance,
    onOpenRewardWall = onOpenRewardWall,
    onProficiencyHighlight = onProficiencyHighlight
  })
end

function offline()
  currentOpenWidget = nil
end

function online()
  local benchmark = g_clock.millis()
  m_interface.addToPanels(buttonsWindow)
  clearHighlight()
  consoleln("Side Buttons loaded in " .. (g_clock.millis() - benchmark) / 1000 .. " seconds.")
end

function clearHighlight()
  local buttons = {"cyclopediaDialog", "bosstiaryDialog", "skillWheelDialog", "exaltationForgeDialog"}
  for _, str in pairs(buttons) do
    local buttonWidget = getButtonById(str)
    if buttonWidget then
      buttonWidget.button:setActionId(0)
      buttonWidget.highlight:setVisible(false)
      buttonWidget.brightButton:setVisible(false)
    end
  end
end

function onBestiaryHighlight(raceId)
  local cyclopediaButton = getButtonById("cyclopediaDialog")
  if cyclopediaButton then
    cyclopediaButton.button:setActionId(raceId)
    cyclopediaButton.highlight:setVisible(true)
    cyclopediaButton.brightButton:setVisible(true)
  end
end

function onBosstiaryHighlight(raceId)
  local bosstiaryButton = getButtonById("bosstiaryDialog")
  if bosstiaryButton then
    bosstiaryButton.button:setActionId(raceId)
    bosstiaryButton.highlight:setVisible(true)
    bosstiaryButton.brightButton:setVisible(true)
  end
end

function onProficiencyHighlight(hasUnusedPerk)
  local proficiencyButton = getButtonById("weaponProficiency")
  if proficiencyButton then
    proficiencyButton.highlight:setVisible(hasUnusedPerk)
    proficiencyButton.brightButton:setVisible(hasUnusedPerk)
  end
end

function onOpenRewardWall(fromShrine, nextRewardTime, currentIndex, message, dailyState, jokerToken, serverSave, dayStreakLevell)
  local rewardButton = getButtonById("rewardWallDialog")
  if rewardButton then
    rewardButton.highlight:setVisible(dailyState ~= 0)
    rewardButton.brightButton:setVisible(dailyState ~= 0)
  end
end

function onResourceBalance(resourceType, amount)
  -- wheel
  if resourceType == ResourceWheelPoints then
    local wheelButton = getButtonById("skillWheelDialog")
    if wheelButton then
      wheelButton.highlight:setVisible(amount > 0)
      wheelButton.brightButton:setVisible(amount > 0)
    end
  end

  -- forge
  if resourceType == ResourceForgeDust then
    local forgeButton = getButtonById("exaltationForgeDialog")
    if forgeButton then
      forgeButton.highlight:setVisible(amount == modules.game_forge.ForgeSystem.maxPlayerDust)
      forgeButton.brightButton:setVisible(amount == modules.game_forge.ForgeSystem.maxPlayerDust)
    end
  end

end

function handleButtonClick(button)
  if isToggleButton(button:getParent():getId()) then
    if button:isChecked() then
      button:setImageClip(torect("0 0 20 20"))
      button:setChecked(false)
      button:setTooltip(tr(getControlButtonTooltip(button:getParent():getId()), "Open"))
    else
      button:setImageClip(torect("0 20 20 20"))
      button:setChecked(true)
      button:setTooltip(tr(getControlButtonTooltip(button:getParent():getId()), "Close"))
    end
  else
    button:setChecked(true)
    scheduleEvent(function()
      button:setChecked(false)
    end, 100)

    if currentOpenWidget then
      forceCloseButton(currentOpenWidget)
    end
    currentOpenWidget = button
  end

  executeButtonFunctionality(button)
end

function isToggleButton(buttonId)
  for _, toggleButtonId in pairs(toggleButtons) do
      if buttonId == toggleButtonId then
          return true
  elseif parentId == "taskHuntDialog" then
    if modules.game_task_hunt and modules.game_task_hunt.hide then
      modules.game_task_hunt.hide()
    end
  end
  end
  return false
end

function executeButtonFunctionality(button)
  if button:getParent():getId() == "skillsWidget" then
    if button:isChecked(true) then
      modules.game_skills:open()
    else
      modules.game_skills:close()
      button:setChecked(false)
    end
  elseif button:getParent():getId() == "battleListWidget" then
    if button:isChecked(true) then
        modules.game_battle:open()
        button:setChecked(true)
      else
        modules.game_battle:close()
        button:setChecked(false)
    end
  elseif button:getParent():getId() == "partyWidget" then
      modules.game_party_list.toggle()
  elseif button:getParent():getId() == "vipWidget" then
    if button:isChecked(true) then
        modules.game_viplist.toggle()
      else
        modules.game_viplist:close()
        button:setChecked(false)
    end
  elseif button:getParent():getId() == "spellListWidget" then
    modules.game_spells.toggle()
  elseif button:getParent():getId() == "skillWheelDialog" then
    modules.game_wheel:toggle()
  elseif button:getParent():getId() == "questDialog" then
    g_game.requestQuestLog()
    modules.game_questlog:toggle()
  elseif button:getParent():getId() == "questTrackerWidget" then
    modules.game_questlog:toggleTracker()
  elseif button:getParent():getId() == "unjustifiedPoinsWidget" then
    modules.game_unjustifiedpoints:toggle()
  elseif button:getParent():getId() == "preyDialog" then
    modules.game_prey.toggle()
  elseif button:getParent():getId() == "preyWidget" then
    if modules.game_trackers and modules.game_trackers.toggleKillTracker then
      modules.game_trackers.toggleKillTracker()
    end
  elseif button:getParent():getId() == "rewardWallDialog" then
      g_game.openDailyReward()
  elseif button:getParent():getId() == "analyticsSelectorWidget" then
    modules.game_analyser:toggle()
  elseif button:getParent():getId() == "compendiumDialog" then
    modules.game_compendium:show(true)
  elseif button:getParent():getId() == "cyclopediaDialog" then
    if button:getActionId() ~= 0 then
      modules.game_cyclopedia.toggleRedirect("Bestiary", button:getActionId())
      button:setActionId(0)
      button:getParent().highlight:setVisible(false)
      button:getParent().brightButton:setVisible(false)
    else
      modules.game_cyclopedia:toggle()
    end
  elseif button:getParent():getId() == "bosstiaryDialog" then
    if button:getActionId() ~= 0 then
      modules.game_cyclopedia.toggleRedirect("Bosstiary", button:getActionId())
      button:setActionId(0)
      button:getParent().highlight:setVisible(false)
      button:getParent().brightButton:setVisible(false)
    else
      modules.game_cyclopedia.Bosstiary.onSideButtonRedirect()
    end
  elseif button:getParent():getId() == "bossslotsDialog" then
    modules.game_cyclopedia.BosstiarySlot.onSideButtonRedirect()
  elseif button:getParent():getId() == "bosstiaryTrackerWidget" then
    modules.game_trackers.toggleBossTracker()
  elseif button:getParent():getId() == "bestiaryTrackerWidget" then
    modules.game_trackers.toggleBestiaryTracker()
  elseif button:getParent():getId() == "imbuementTrackerWidget" then
    modules.game_trackers.toggleImbuementTracker()
  elseif button:getParent():getId() == "exaltationForgeDialog" then
    modules.game_forge:toggle()
  elseif button:getParent():getId() == "friendsDialog" then
    displayErrorBox(tr("For Your Information"), tr("Content Under Development..."))
  elseif button:getParent():getId() == "lenshelpFunction" then
    if button:isChecked(true) then
      modules.game_minimap:toggle()
      button:setChecked(true)
      button:getParent().highlight:setVisible(false)
      button:getParent().brightButton:setVisible(true)
    else
      modules.game_minimap:toggle()
      button:setChecked(false)
      button:getParent().highlight:setVisible(true)
    end
  elseif button:getParent():getId() == "highscoresDialog" then
    modules.game_highscores:show(true)
  elseif button:getParent():getId() == "helperDialog" then
    modules.game_helper:showTerms()
  elseif button:getParent():getId() == "weaponProficiency" then
    modules.game_proficiency.requestOpenWindow()
  elseif button:getParent():getId() == "manageShortcuts" then
    m_settings.toggleShortcuts()
  elseif button:getParent():getId() == "taskHuntDialog" then
    if modules.game_task_hunt then modules.game_task_hunt.toggle() end
  end
end

function forceCloseButton(button)
  if not button:getParent() then
    return true
  end

  local parentId = button:getParent():getId()
  
  if parentId == "spellListWidget" then
    if modules.game_spells and modules.game_spells.hide then
      modules.game_spells.hide()
    end
  elseif parentId == "skillWheelDialog" then
    if modules.game_wheel and modules.game_wheel.hide then
      modules.game_wheel:hide()
    end
  elseif parentId == "questDialog" then
    if modules.game_questlog and modules.game_questlog.hide then
      modules.game_questlog:hide()
    end
  elseif parentId == "preyDialog" then
    if modules.game_prey and modules.game_prey.hide then
      modules.game_prey:hide()
    end
  elseif parentId == "rewardWallDialog" then
    if modules.game_dailyreward and modules.game_dailyreward.closeDaily then
      modules.game_dailyreward:closeDaily()
    end
  elseif parentId == "compendiumDialog" then
    if modules.game_compendium and modules.game_compendium.hide then
      modules.game_compendium:hide()
    end
  elseif parentId == "cyclopediaDialog" or parentId == "bosstiaryDialog" or parentId == "bossslotsDialog" then
    if modules.game_cyclopedia and modules.game_cyclopedia.hide then
      modules.game_cyclopedia:hide()
    end
  elseif parentId == "exaltationForgeDialog" then
    if modules.game_forge and modules.game_forge.hideForge then
      modules.game_forge.hideForge()
    end
  elseif parentId == "friendsDialog" then
    -- TODO
  elseif parentId == "lenshelpFunction" then
    if modules.game_minimap and modules.game_minimap.toggle then
      modules.game_minimap:toggle()
    end
  elseif parentId == "highscoresDialog" then
    if modules.game_highscores and modules.game_highscores.hide then
      modules.game_highscores:hide()
    end
  elseif parentId == "helperDialog" then
    if modules.game_helper and modules.game_helper.hide then
      modules.game_helper:hide()
    end
  elseif parentId == "manageShortcuts" then
    if m_settings and m_settings.closeOptions then
      m_settings.closeOptions()
    end
  end
end

function toggleMainButtons()
  isHiddenMenuActive = not isHiddenMenuActive

  if not buttonsWindow then return end

  buttonsWindow.minimized = isHiddenMenuActive
  local buttonsPanel = buttonsWindow:recursiveGetChildById('buttons')
  local optionsButton = buttonsWindow:recursiveGetChildById('options')
  local logoutButton = buttonsWindow:recursiveGetChildById('logout')
  local separator = buttonsWindow:recursiveGetChildById('sep')
  local hiddenMenuButton = buttonsWindow:recursiveGetChildById('hiddenMenu')
  local battlePassButton = buttonsWindow:recursiveGetChildById('battlePassButton')

  buttonsPanel:setVisible(not isHiddenMenuActive)
  optionsButton:setVisible(not isHiddenMenuActive)
  logoutButton:setVisible(not isHiddenMenuActive)
  separator:setVisible(not isHiddenMenuActive)
  if battlePassButton then
    battlePassButton:setVisible(not isHiddenMenuActive)
  end

  if isHiddenMenuActive then
    buttonsWindow:setHeight(27)
    hiddenMenuButton:setImageSource('/images/ui/hidden-menu-up')
  else
    updateSideButtons()
    hiddenMenuButton:setImageSource('/images/ui/hidden-menu-down')
  end
end

function move(panel, index, minimized)
  buttonsWindow:setParent(panel)
  buttonsWindow:open()
  if minimized then
    toggleMainButtons()
  end

  return buttonsWindow
end
