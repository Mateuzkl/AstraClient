-- ===== HELPER SHORTCUT PANEL =====
-- Módulo separado para gerenciar o painel de atalhos do Helper

-- Garante que _Helper existe (será definido em helper.lua, mas pode ser carregado antes)
if not _Helper then
  _Helper = {}
end

_Helper.Shortcut = {}

local helperShortcutPanel = nil
local shortcutsVisible = true -- Valor default para mostrar o painel de atalhos

-- Função auxiliar para obter o painel mais à esquerda dos painéis da direita
local function getRootPanel()
  if modules.game_interface and modules.game_interface.getRootPanel then
    return modules.game_interface.getRootPanel()
  end
  return nil
end

local function isVisiblePanel(widget)
  if not widget then
    return false
  end
  if widget.isVisible and not widget:isVisible() then
    return false
  end
  if widget.getWidth and widget:getWidth() <= 0 then
    return false
  end
  return true
end

local function getVerticalAnchorId(rootWidget)
  if rootWidget:getChildById('gameMainRightPanel') then
    return 'gameMainRightPanel'
  end
  if rootWidget:getChildById('gameMapPanel') then
    return 'gameMapPanel'
  end
  return 'parent'
end

-- Place the shortcuts vertically below the FPS/latency overlay.
local function anchorBelowGameStats(panel)
  local statsPanel = g_ui.getRootWidget():recursiveGetChildById('game_stats')
  if not statsPanel or not statsPanel:getParent() then
    return false
  end

  panel:breakAnchors()
  if panel:getParent() ~= statsPanel:getParent() then
    panel:setParent(statsPanel:getParent())
  end

  panel:addAnchor(AnchorTop, 'game_stats', AnchorBottom)
  panel:addAnchor(AnchorLeft, 'game_stats', AnchorLeft)
  panel:setMarginLeft(0)
  panel:setMarginTop(4)

  return true
end

local function getLeftmostRightPanel()
  local rootWidget = getRootPanel()
  if not rootWidget then
    return nil, nil
  end

  local gameRightPanel = rootWidget:getChildById('gameRightPanel')
  local gameRightPanels = rootWidget:getChildById('gameRightPanels')
  local gameRightExtraPanel = rootWidget:getChildById('gameRightExtraPanel')
  local gameRightExtraPanel2 = rootWidget:getChildById('gameRightExtraPanel2')
  local gameRightExtraPanel3 = rootWidget:getChildById('gameRightExtraPanel3')
  local gameRightActionPanel = rootWidget:getChildById('gameRightActionPanel')

  -- Verificar se há action bars da direita visíveis (usando getActiveRightBars do game_actionbar)
  local hasActiveRightActionBars = false
  if modules.game_actionbar and modules.game_actionbar.getActiveRightBars then
    local activeRightBars = modules.game_actionbar.getActiveRightBars()
    hasActiveRightActionBars = activeRightBars and activeRightBars > 0
  end

  -- Prioridade: gameRightActionPanel (se tiver action bars ativas) > gameRightExtraPanel3 > gameRightExtraPanel2 > gameRightExtraPanel > gameRightPanel
  if gameRightActionPanel and hasActiveRightActionBars and isVisiblePanel(gameRightActionPanel) then
    return gameRightActionPanel, 'gameRightActionPanel'
  elseif gameRightExtraPanel3 and gameRightExtraPanel3:isOn() then
    return gameRightExtraPanel3, 'gameRightExtraPanel3'
  elseif gameRightExtraPanel2 and gameRightExtraPanel2:isOn() then
    return gameRightExtraPanel2, 'gameRightExtraPanel2'
  elseif gameRightExtraPanel and gameRightExtraPanel:isOn() then
    return gameRightExtraPanel, 'gameRightExtraPanel'
  elseif isVisiblePanel(gameRightPanels) then
    return gameRightPanels, 'gameRightPanels'
  elseif gameRightPanels then
    return gameRightPanels, 'gameRightPanels'
  else
    return gameRightPanel, 'gameRightPanel'
  end
end

_Helper.Shortcut.toggle = function(checked)
  shortcutsVisible = checked
  if checked then
    if not helperShortcutPanel then
      _Helper.Shortcut.createPanel()
    else
      helperShortcutPanel:setVisible(true)
    end
  else
    if helperShortcutPanel then
      helperShortcutPanel:setVisible(false)
    end
  end
  -- Salvar configuração
  if _Helper.saveSettings then
    _Helper.saveSettings()
  end
end

_Helper.Shortcut.isVisible = function()
  return shortcutsVisible
end

_Helper.Shortcut.setVisible = function(value)
  shortcutsVisible = value
end

_Helper.Shortcut.createPanel = function()
  if helperShortcutPanel then
    return -- Já existe
  end

  local rootWidget = getRootPanel()
  if not rootWidget then
    return
  end

  local gameRightPanel = rootWidget:getChildById('gameRightPanel') or rootWidget:getChildById('gameRightPanels')

  if not gameRightPanel then
    return
  end

  helperShortcutPanel = g_ui.createWidget('HelperShortcutPanel', rootWidget)
  if not helperShortcutPanel then
    return
  end

  -- Default position: below the FPS/latency overlay.
  if not anchorBelowGameStats(helperShortcutPanel) then
    -- Fallback: à esquerda do painel da direita, centralizado verticalmente
    helperShortcutPanel:addAnchor(AnchorVerticalCenter, getVerticalAnchorId(rootWidget), AnchorVerticalCenter)

    local _, panelId = getLeftmostRightPanel()
    if panelId then
      helperShortcutPanel:addAnchor(AnchorRight, panelId, AnchorLeft)
    else
      helperShortcutPanel:addAnchor(AnchorRight, 'gameRightPanels', AnchorLeft)
    end

    helperShortcutPanel:setMarginRight(20)

  end

  -- game_stats may load after Helper, so retry the final placement.
  for _, delay in ipairs({300, 800, 1500, 3000}) do
    scheduleEvent(function()
      if helperShortcutPanel then
        anchorBelowGameStats(helperShortcutPanel)
        helperShortcutPanel:raise()
      end
    end, delay)
  end

  helperShortcutPanel:raise()

  -- Sincronizar estado dos botões com as configurações atuais
  _Helper.Shortcut.syncPanelState()
end

_Helper.Shortcut.destroyPanel = function()
  if helperShortcutPanel then
    helperShortcutPanel:destroy()
    helperShortcutPanel = nil
  end
end

_Helper.Shortcut.updatePosition = function()
  if not helperShortcutPanel then
    return
  end

  local rootWidget = getRootPanel()
  if not rootWidget then
    return
  end

  local gameRightPanel = rootWidget:getChildById('gameRightPanel') or rootWidget:getChildById('gameRightPanels')

  if not gameRightPanel then
    return
  end

  -- Remover todos os anchors atuais
  helperShortcutPanel:breakAnchors()

  -- Reposition below the FPS/latency overlay.
  if not anchorBelowGameStats(helperShortcutPanel) then
    -- Fallback: centralizado verticalmente e à esquerda do painel correto
    -- (reparenta para a root, pois pode ter sido movido para a top bar)
    if helperShortcutPanel:getParent() ~= rootWidget then
      helperShortcutPanel:setParent(rootWidget)
    end
    helperShortcutPanel:addAnchor(AnchorVerticalCenter, getVerticalAnchorId(rootWidget), AnchorVerticalCenter)

    local _, panelId = getLeftmostRightPanel()
    if panelId then
      helperShortcutPanel:addAnchor(AnchorRight, panelId, AnchorLeft)
    else
      helperShortcutPanel:addAnchor(AnchorRight, 'gameRightPanels', AnchorLeft)
    end

    helperShortcutPanel:setMarginRight(20)
  end

  helperShortcutPanel:raise()
end

_Helper.Shortcut.syncPanelState = function()
  if not helperShortcutPanel then
    return
  end

  -- Helper status
  local shortcutHelper = helperShortcutPanel:getChildById('shortcutHelper')
  if shortcutHelper then
    local helperEnabled = _Helper.isHelperAutomaticFunctionsEnabled and _Helper.isHelperAutomaticFunctionsEnabled() or
    false
    shortcutHelper:setChecked(helperEnabled)
    _Helper.Shortcut.updateMark(shortcutHelper, helperEnabled)
  end

  -- Auto Target
  local shortcutAutoTarget = helperShortcutPanel:getChildById('shortcutAutoTarget')
  if shortcutAutoTarget and helperConfig then
    local enabled = helperConfig.autoTargetEnabled or false
    shortcutAutoTarget:setChecked(enabled)
    _Helper.Shortcut.updateMark(shortcutAutoTarget, enabled)
  end

  -- Shooter
  local shortcutShooter = helperShortcutPanel:getChildById('shortcutShooter')
  if shortcutShooter and helperConfig then
    local enabled = helperConfig.magicShooterEnabled or false
    shortcutShooter:setChecked(enabled)
    _Helper.Shortcut.updateMark(shortcutShooter, enabled)
  end

  -- Auto Haste
  local shortcutHaste = helperShortcutPanel:getChildById('shortcutHaste')
  if shortcutHaste and helperConfig and helperConfig.haste and helperConfig.haste[1] then
    local enabled = helperConfig.haste[1].enabled or false
    shortcutHaste:setChecked(enabled)
    _Helper.Shortcut.updateMark(shortcutHaste, enabled)
  end

  -- Mana Training
  local shortcutTraining = helperShortcutPanel:getChildById('shortcutTraining')
  if shortcutTraining and helperConfig and helperConfig.training and helperConfig.training[1] then
    local enabled = helperConfig.training[1].enabled or false
    shortcutTraining:setChecked(enabled)
    _Helper.Shortcut.updateMark(shortcutTraining, enabled)
  end

  -- Equipment
  local shortcutEquipment = helperShortcutPanel:getChildById('shortcutEquipment')
  if shortcutEquipment then
    local enabled = false
    if modules.game_helper and modules.game_helper.equip and modules.game_helper.equip.isEnabled then
      enabled = modules.game_helper.equip.isEnabled()
    end
    shortcutEquipment:setChecked(enabled)
    _Helper.Shortcut.updateMark(shortcutEquipment, enabled)
  end

  -- Always Chase Opponent
  local shortcutAlwaysChase = helperShortcutPanel:getChildById('shortcutAlwaysChase')
  if shortcutAlwaysChase and helperConfig then
    local chaseEnabled = helperConfig.alwaysChaseOpponent or false
    shortcutAlwaysChase:setChecked(chaseEnabled)
    _Helper.Shortcut.updateMark(shortcutAlwaysChase, chaseEnabled)
  end

  -- Timer
  local shortcutTimer = helperShortcutPanel:getChildById('shortcutTimer')
  if shortcutTimer and helperConfig then
    -- Default to true if not explicitly set to false
    local enabled = helperConfig.timerEnabled ~= false
    shortcutTimer:setChecked(enabled)
    _Helper.Shortcut.updateMark(shortcutTimer, enabled)
  end
end

_Helper.Shortcut.syncButton = function(buttonId, enabled)
  if not helperShortcutPanel then
    return
  end

  local button = helperShortcutPanel:getChildById(buttonId)
  if button then
    button:setChecked(enabled)
    _Helper.Shortcut.updateMark(button, enabled)
  end
end

_Helper.Shortcut.updateMark = function(button, isEnabled)
  if not button then return end
  local mark = button:getChildById('mark')
  if mark then
    mark:setVisible(isEnabled)
  end
end

_Helper.Shortcut.onButtonChange = function(button)
  if not button then return end

  local id = button:getId()
  local isChecked = button:isChecked()


  _Helper.Shortcut.updateMark(button, isChecked)

  if id == 'shortcutHelper' then
    if _Helper.setHelperAutomaticFunctionsEnabled then
      _Helper.setHelperAutomaticFunctionsEnabled(isChecked)
    end
    if botStatus then
      botStatus()
    end
    if saveSettings then
      saveSettings()
    end
  elseif id == 'shortcutAutoTarget' then
    -- Sincronizar com checkbox do painel (que vai chamar toggleAutoTarget)
    local sPanel = _Helper.getShooterPanel and _Helper.getShooterPanel()
    if sPanel then
      local enableAutoTarget = sPanel:recursiveGetChildById('enableAutoTarget')
      if enableAutoTarget and enableAutoTarget:isChecked() ~= isChecked then
        enableAutoTarget:setChecked(isChecked)
      end
    end
  elseif id == 'shortcutShooter' then
    -- Sincronizar com checkbox do painel (que vai chamar toggleMagicShooter)
    local sPanel = _Helper.getShooterPanel and _Helper.getShooterPanel()
    if sPanel then
      local enableMagicShooter = sPanel:recursiveGetChildById('enableMagicShooter')
      if enableMagicShooter and enableMagicShooter:isChecked() ~= isChecked then
        enableMagicShooter:setChecked(isChecked)
      end
    end
  elseif id == 'shortcutHaste' then
    -- Sincronizar com checkbox do painel (que vai chamar toggleAutoHaste)
    local tPanel = _Helper.getToolsPanel and _Helper.getToolsPanel()
    if tPanel then
      local enableHaste = tPanel:recursiveGetChildById('enableHaste0')
      if enableHaste and enableHaste:isChecked() ~= isChecked then
        enableHaste:setChecked(isChecked)
      end
    end
  elseif id == 'shortcutTraining' then
    -- Sincronizar com checkbox do painel (que vai chamar onEnableTraining)
    local tPanel = _Helper.getToolsPanel and _Helper.getToolsPanel()
    if tPanel then
      local enableTraining = tPanel:recursiveGetChildById('enableTraining0')
      if enableTraining and enableTraining:isChecked() ~= isChecked then
        enableTraining:setChecked(isChecked)
      end
    end
  elseif id == 'shortcutEquipment' then
    -- Sincronizar com checkbox do equipment panel
    if modules.game_helper and modules.game_helper.equip then
      modules.game_helper.equip.toggleEquipment(isChecked)
      -- Update checkbox
      local equipPanel = modules.game_helper.equip.getPanel()
      if equipPanel then
        local enableEquipmentPanel = equipPanel:getChildById('enableEquipmentPanel')
        if enableEquipmentPanel then
          local enableCheckbox = enableEquipmentPanel:getChildById('enableEquipment')
          if enableCheckbox and enableCheckbox:isChecked() ~= isChecked then
            enableCheckbox:setChecked(isChecked)
          end
        end
      end
    end
  elseif id == 'shortcutTimer' then
    -- Toggle Timer enabled/disabled
    if helperConfig then
      helperConfig.timerEnabled = isChecked
      -- Sincronizar com checkbox do timer panel
      if modules.game_helper and modules.game_helper.timerPanel and modules.game_helper.timerPanel.syncEnableTimer then
        modules.game_helper.timerPanel.syncEnableTimer()
      end
      if _Helper.saveSettings then
        _Helper.saveSettings()
      end
    end
  elseif id == 'shortcutAlwaysChase' then
    local sPanel = _Helper.getShooterPanel and _Helper.getShooterPanel()
    if sPanel then
      local chaseCheckbox = sPanel:recursiveGetChildById('alwaysChaseOpponent')
      if chaseCheckbox and chaseCheckbox:isChecked() ~= isChecked then
        chaseCheckbox:setChecked(isChecked)
      end
    end
  elseif id == 'shortcutCavebot' then
    -- Sincronizar com cavebot toggle
    if modules.game_helper and modules.game_helper.cavebot then
      modules.game_helper.cavebot.toggle(isChecked)
    end
  end
end

_Helper.Shortcut.getPanel = function()
  return helperShortcutPanel
end

-- ===== FIM HELPER SHORTCUT PANEL =====
