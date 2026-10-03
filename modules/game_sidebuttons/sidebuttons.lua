buttonsWindow = nil
isHiddenMenuActive = false

local buttonDefinitions = {
  { id = 'skillsWidget', tooltip = 'Skills', action = function() modules.game_skills.toggle() end },
  { id = 'battleListWidget', tooltip = 'Battle List', action = function() modules.game_battle.toggle() end },
  { id = 'partyWidget', tooltip = 'Party List', action = function() modules.game_party_list.toggle() end },
  { id = 'vipWidget', tooltip = 'VIP List', action = function() modules.game_viplist.toggle() end },
  { id = 'spellListWidget', tooltip = 'Spell List', action = function() modules.game_spells.toggle() end },
  { id = 'questDialog', tooltip = 'Quest Log', action = function()
      g_game.requestQuestLog()
      modules.game_questlog.toggle()
    end },
  { id = 'unjustifiedPoinsWidget', tooltip = 'Unjustified Points', action = function()
      modules.game_unjustifiedpoints.toggle()
    end },
  { id = 'preyDialog', tooltip = 'Prey', action = function() modules.game_prey.toggle() end },
  { id = 'lenshelpFunction', tooltip = 'Minimap', action = function() modules.game_minimap.toggle() end },
  { id = 'bot', tooltip = 'Bot', action = function() modules.game_bot.toggle() end }
}

local function getButtonsPanel()
  return buttonsWindow and buttonsWindow:recursiveGetChildById('buttons') or nil
end

local function updateWindowHeight()
  if not buttonsWindow or isHiddenMenuActive then
    return
  end

  local rows = math.max(1, math.ceil(#buttonDefinitions / 5))
  buttonsWindow:setHeight(9 + rows * 22)
end

local function triggerButton(definition, button)
  button:setChecked(true)
  scheduleEvent(function()
    if button and not button:isDestroyed() then
      button:setChecked(false)
    end
  end, 100)
  definition.action()
end

local function populateButtons()
  local panel = getButtonsPanel()
  if not panel then
    return
  end

  panel:destroyChildren()
  for _, definition in ipairs(buttonDefinitions) do
    local widget = g_ui.createWidget('UISideButton', panel)
    widget:setId(definition.id)
    widget.button:setImageSource('/images/topbuttons/' .. definition.id .. '.png')
    widget.button:setTooltip(tr('Open %s', definition.tooltip))
    widget.button.onClick = function()
      triggerButton(definition, widget.button)
    end
  end

  updateWindowHeight()
end

function init()
  buttonsWindow = g_ui.loadUI('sidebuttons', m_interface.getRightPanel())
  populateButtons()

  connect(g_game, {
    onGameStart = online,
    onGameEnd = offline
  })

  if g_game.isOnline() then
    online()
  end
end

function terminate()
  disconnect(g_game, {
    onGameStart = online,
    onGameEnd = offline
  })

  if buttonsWindow then
    buttonsWindow:destroy()
    buttonsWindow = nil
  end
end

function online()
  if not buttonsWindow then
    return
  end

  m_interface.addToPanels(buttonsWindow)
  updateWindowHeight()
end

function offline()
end

function setButtonVisible(buttonId, state)
  local panel = getButtonsPanel()
  local widget = panel and panel:recursiveGetChildById(buttonId) or nil
  if widget and widget.button then
    widget.button:setChecked(state)
  end
end

function getButtonById(buttonId)
  local panel = getButtonsPanel()
  return panel and panel:recursiveGetChildById(buttonId) or nil
end

function updateSideButtons()
  populateButtons()
end

function toggleMainButtons()
  if not buttonsWindow then
    return
  end

  isHiddenMenuActive = not isHiddenMenuActive
  buttonsWindow.minimized = isHiddenMenuActive

  local buttonsPanel = buttonsWindow:recursiveGetChildById('buttons')
  local optionsButton = buttonsWindow:recursiveGetChildById('options')
  local logoutButton = buttonsWindow:recursiveGetChildById('logout')
  local separator = buttonsWindow:recursiveGetChildById('sep')
  local hiddenMenuButton = buttonsWindow:recursiveGetChildById('hiddenMenu')

  buttonsPanel:setVisible(not isHiddenMenuActive)
  optionsButton:setVisible(not isHiddenMenuActive)
  logoutButton:setVisible(not isHiddenMenuActive)
  separator:setVisible(not isHiddenMenuActive)

  if isHiddenMenuActive then
    buttonsWindow:setHeight(27)
    hiddenMenuButton:setImageSource('/images/ui/hidden-menu-up')
  else
    hiddenMenuButton:setImageSource('/images/ui/hidden-menu-down')
    updateWindowHeight()
  end
end

function move(panel, index, minimized)
  buttonsWindow:setParent(panel)
  buttonsWindow:open()
  if minimized and not isHiddenMenuActive then
    toggleMainButtons()
  elseif not minimized and isHiddenMenuActive then
    toggleMainButtons()
  end
  return buttonsWindow
end
