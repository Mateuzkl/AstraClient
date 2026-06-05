InventorySlotStyles = {
  [InventorySlotHead] = "HeadSlot",
  [InventorySlotNeck] = "NeckSlot",
  [InventorySlotBack] = "BackSlot",
  [InventorySlotBody] = "BodySlot",
  [InventorySlotRight] = "RightSlot",
  [InventorySlotLeft] = "LeftSlot",
  [InventorySlotLeg] = "LegSlot",
  [InventorySlotFeet] = "FeetSlot",
  [InventorySlotFinger] = "FingerSlot",
  [InventorySlotAmmo] = "AmmoSlot"
}

inventoryWindow = nil
inventoryPanel = nil
inventoryButton = nil
purseButton = nil

combatControlsWindow = nil
fightOffensiveBox = nil
fightBalancedBox = nil
fightDefensiveBox = nil
chaseModeButton = nil
safeFightButton = nil
fightModeRadioGroup = nil
chaseModeRadioGroup = nil
chaseModeStandBox = nil
chaseModeChaseBox = nil
buttonPvp = nil
pvpModesPanel = nil
soulLabel = nil
capLabel = nil
conditionPanel = nil
slotValue = {}

pvpModeCheckBox = nil

doveModeWidget = nil
whiteModeWidget = nil
yellowModeWidget = nil
redModeWidget = nil

local function isPlayerMonk()
  local player = g_game.getLocalPlayer()
  return player and player.isMonk and player:isMonk() or false
end

function init()
  connect(LocalPlayer, {
    onInventoryChange = onInventoryChange,
    onBlessingsChange = onBlessingsChange,
    onVocationChange = onVocationChange
  })

  inventoryWindow = g_ui.loadUI('inventory', m_interface.getRightPanel())
  inventoryWindow:disableResize()
  inventoryPanel = inventoryWindow:getChildById('contentsPanel')
  inventoryWindow:setHeight(167)

  purseButton = inventoryWindow:recursiveGetChildById('purseButton')
  purseButton.onClick = function()
    local player = g_game.getLocalPlayer()
    if not player then return end
    local purse = player:getInventoryItem(InventorySlotPurse)
    if purse then
      g_game.use(purse)
    end
  end

  -- controls
  fightOffensiveBox = inventoryWindow:recursiveGetChildById('fightOffensiveBox')
  fightBalancedBox = inventoryWindow:recursiveGetChildById('fightBalancedBox')
  fightDefensiveBox = inventoryWindow:recursiveGetChildById('fightDefensiveBox')

  chaseModeStandBox = inventoryWindow:recursiveGetChildById('chaseModeBoxStand')
  chaseModeChaseBox = inventoryWindow:recursiveGetChildById('chaseModeBoxChase')

  chaseModeButton = inventoryWindow:recursiveGetChildById('chaseModeBox')
  safeFightButton = inventoryWindow:recursiveGetChildById('safeFightBox')
  buttonPvp = inventoryWindow:recursiveGetChildById('openPvpButton')
  pvpModesPanel = inventoryWindow:recursiveGetChildById('pvpModesPanel')

  doveModeWidget = inventoryWindow:recursiveGetChildById('doveMode')
  doveModeWidget.pvpMode = PVPWhiteDove
  whiteModeWidget = inventoryWindow:recursiveGetChildById('whiteMode')
  whiteModeWidget.pvpMode = PVPWhiteHand
  yellowModeWidget = inventoryWindow:recursiveGetChildById('yellowMode')
  yellowModeWidget.pvpMode = PVPYellowHand
  redModeWidget = inventoryWindow:recursiveGetChildById('redMode')
  redModeWidget.pvpMode = PVPRedFist

  pvpModeCheckBox = UIRadioGroup.create()
  pvpModeCheckBox:addWidget(doveModeWidget)
  pvpModeCheckBox:addWidget(whiteModeWidget)
  pvpModeCheckBox:addWidget(yellowModeWidget)
  pvpModeCheckBox:addWidget(redModeWidget)

  pvpModeCheckBox.onSelectionChange = onSelectionChangePvp
  pvpModeCheckBox:selectWidget(doveModeWidget)

  whiteDoveBox = inventoryWindow:recursiveGetChildById('doveMode')
  whiteHandBox = inventoryWindow:recursiveGetChildById('whiteMode')
  yellowHandBox = inventoryWindow:recursiveGetChildById('yellowMode')
  redFistBox = inventoryWindow:recursiveGetChildById('redMode')

  fightModeRadioGroup = UIRadioGroup.create()
  fightModeRadioGroup:addWidget(fightOffensiveBox)
  fightModeRadioGroup:addWidget(fightBalancedBox)
  fightModeRadioGroup:addWidget(fightDefensiveBox)

  chaseModeRadioGroup = UIRadioGroup.create()
  chaseModeRadioGroup:addWidget(chaseModeStandBox)
  chaseModeRadioGroup:addWidget(chaseModeChaseBox)

  connect(fightModeRadioGroup, { onSelectionChange = onSetFightMode })
  connect(chaseModeRadioGroup, { onSelectionChange = onSetChaseMode })
  connect(safeFightButton, { onCheckChange = onSetSafeFight })
  if buttonPvp then
    connect(buttonPvp, { onClick = onOpenPvpButtonClick })
  end
  connect(g_game, {
    onGameStart = online,
    onGameEnd = offline,
    onFightModeChange = update,
    onChaseModeChange = update,
    onSafeFightChange = update,
    onPVPModeChange   = update,
    onWalk = check,
    onAutoWalk = check,
  })

  if g_game.isOnline() then
    online()
  end
  -- controls end

  -- status
  soulLabel = inventoryWindow:recursiveGetChildById('soulLabel')
  capLabel = inventoryWindow:recursiveGetChildById('capLabel')
  conditionPanel = inventoryWindow:recursiveGetChildById('conditionPanel')
  m_settings.ConditionsHUD:startInventoryPanel(conditionPanel)


  connect(LocalPlayer, {
                         onSoulChange = onSoulChange,
                        onTotalCapacityChange = onTotalCapacityChange,
                        onBaseCapacityChange = onBaseCapacityChange,
                         onFreeCapacityChange = onFreeCapacityChange
                        })
  -- status end

  refresh()
  inventoryWindow:setup()
  inventoryWindow:open()
end

function terminate()
  disconnect(LocalPlayer, {
    onInventoryChange = onInventoryChange,
    onBlessingsChange = onBlessingsChange,
    onVocationChange = onVocationChange
  })

  -- controls
  if g_game.isOnline() then
    offline()
  end

  fightModeRadioGroup:destroy()

  disconnect(g_game, {
    onGameStart = online,
    onGameEnd = offline,
    onFightModeChange = update,
    onChaseModeChange = update,
    onSafeFightChange = update,
    onPVPModeChange   = update,
    onWalk = check,
    onAutoWalk = check,
  })

  -- controls end
  -- status
  disconnect(LocalPlayer, {
                         onSoulChange = onSoulChange,
                        onTotalCapacityChange = onTotalCapacityChange,
                        onBaseCapacityChange = onBaseCapacityChange,
                         onFreeCapacityChange = onFreeCapacityChange })
  -- status end

  inventoryWindow:destroy()
  if inventoryButton then
    inventoryButton:destroy()
  end
end

function getInventoryPanel()
  return inventoryPanel
end

function toggleAdventurerStyle(hasBlessing)
  for slot = InventorySlotFirst, InventorySlotLast do
    local itemWidget = inventoryPanel:getChildById('slot' .. slot)
    if itemWidget then
      itemWidget:setOn(hasBlessing)
    end
  end
end

function refresh()
  local player = g_game.getLocalPlayer()
  for i = InventorySlotFirst, InventorySlotPurse do
    if g_game.isOnline() then
      onInventoryChange(player, i, player:getInventoryItem(i))
    else
      onInventoryChange(player, i, nil)
    end
    toggleAdventurerStyle(player and Bit.hasBit(player:getBlessings(), Blessings.Adventurer) or false)
  end
  if player then
    onSoulChange(player, player:getSoul())
    onFreeCapacityChange(player, player:getFreeCapacity())
    onBaseCapacityChange(player, player:getFreeCapacity())
    onTotalCapacityChange(player, player:getFreeCapacity())
  end

  purseButton:setVisible(true)
end

function toggle()
  if not inventoryButton then
    return
  end
  if inventoryButton:isOn() then
    inventoryWindow:close()
    inventoryButton:setOn(false)
  else
    inventoryWindow:open()
    inventoryButton:setOn(true)
  end
end

function onMiniWindowClose()
  if not inventoryButton then
    return
  end
  inventoryButton:setOn(false)
end

function getLeftSlotItem()
  local itemWidget = inventoryPanel:getChildById('slot6')
  if not itemWidget then
    return nil
  end
  return itemWidget:getItem()
end

function configureMirror()
  local itemWidget = inventoryPanel:getChildById('slot6')
  if not itemWidget then
    return
  end
  local item = itemWidget:getItem()

  local itemWidgetMirror = inventoryPanel:getChildById('slot5')
  if not itemWidgetMirror then
    return
  end

  local function clearMirror()
    itemWidgetMirror:setStyle(InventorySlotStyles[5])
    itemWidgetMirror:setItem(nil)
    itemWidgetMirror:setOpacity(1.0)
    itemWidgetMirror:setDraggable(true)
    itemWidgetMirror:setEnabled(true)
    itemWidgetMirror:setFlipDirection(FlipDirection.None)
    itemWidgetMirror.slot5Dual:setVisible(false)
    itemWidgetMirror:setPhantom(false)
    itemWidgetMirror.clone = false
  end

  if not isPlayerMonk() then
    if itemWidgetMirror.clone then
      clearMirror()
    end
    return
  end

  if not item then
    if itemWidgetMirror.clone then
      clearMirror()
    end
    return
  end

  local player = g_game.getLocalPlayer()
  local realRightItem = player and player:getInventoryItem(InventorySlotRight)
  if realRightItem then
    if itemWidgetMirror.clone then
      clearMirror()
    end
    return
  end

  itemWidgetMirror:setItem(item)
  itemWidgetMirror:setStyle('NoneInventoryItem')
  itemWidgetMirror:setOpacity(0.5)
  itemWidgetMirror:setDraggable(false)
  itemWidgetMirror:setEnabled(false)
  itemWidgetMirror:setFlipDirection(FlipDirection.Horizontal)
  itemWidgetMirror.slot5Dual:setVisible(true)
  itemWidgetMirror:setPhantom(true)
  itemWidgetMirror.clone = true
end

function scheduleMonkMirrorUpdate()
  local itemWidget = inventoryPanel:getChildById('slot6')
  local item = itemWidget:getItem()
  if not item then
    return
  end
  local itemWidgetMirror = inventoryPanel:getChildById('slot5')
  if itemWidgetMirror.clone then
    return
  end

  addEvent(function() configureMirror() end, 100)
end

-- hooked events
function onInventoryChange(player, slot, item, oldItem)
  if slot > InventorySlotPurse then return end

  if slot == InventorySlotPurse then
    return
  end

  local itemWidget = inventoryPanel:getChildById('slot' .. slot)
  itemWidget:setItemShader('')
  if item then
    itemWidget:setStyle('InventoryItem')
    itemWidget:setItem(item)
    if slot == 6 then
      addEvent(function()  configureMirror() end, 100)
    elseif slot == 5 then
      itemWidget:setOpacity(1.0)
      itemWidget:setDraggable(true)
      itemWidget:setEnabled(true)
      itemWidget:setFlipDirection(FlipDirection.None)
      itemWidget.clone = false
    end
    updateFlags(item, itemWidget)
  else
    if slot == 6 then
      addEvent(function() configureMirror() end, 100)
    elseif slot == 5 then
      scheduleMonkMirrorUpdate()
    end
    itemWidget:setStyle(InventorySlotStyles[slot])
    itemWidget.quicklootflags:setVisible(false)
    itemWidget:setItem(nil)
  end
  ItemsDatabase.setTier(itemWidget, item)
  slotValue[slot] = item
end

function onVocationChange()
  addEvent(function() configureMirror() end, 100)
end

function SlotValue()
  return slotValue
end

function onBlessingsChange(player, blessings, oldBlessings)
  local hasAdventurerBlessing = Bit.hasBit(blessings, Blessings.Adventurer)
  if hasAdventurerBlessing ~= Bit.hasBit(oldBlessings, Blessings.Adventurer) then
    toggleAdventurerStyle(hasAdventurerBlessing)
  end

  local tooltip = 'You are protected by the following blessings:'
  if Bit.hasBit(blessings, bit.lshift(1, 1)) then
    tooltip = tooltip .. '\nTwist of Fate'
  end
  if Bit.hasBit(blessings, bit.lshift(1, 2)) then
    tooltip = tooltip .. '\nWisdom of Solitude'
  end
  if Bit.hasBit(blessings, bit.lshift(1, 3)) then
    tooltip = tooltip .. '\nSpark of the Phoenix'
  end
  if Bit.hasBit(blessings, bit.lshift(1, 4)) then
    tooltip = tooltip .. '\nFire of the Suns'
  end
  if Bit.hasBit(blessings, bit.lshift(1, 5)) then
    tooltip = tooltip .. '\nSpiritual Shielding'
  end
  if Bit.hasBit(blessings, bit.lshift(1, 6)) then
    tooltip = tooltip .. '\nEmbrace of Tibia'
  end
  if Bit.hasBit(blessings, bit.lshift(1, 7)) then
    tooltip = tooltip .. '\nHeart of the Mountain'
  end
  if Bit.hasBit(blessings, bit.lshift(1, 8)) then
    tooltip = tooltip .. '\nBlood of the Mountain'
  end
  blessedButton = inventoryWindow:recursiveGetChildById('blessedButton')
  blessedButton:setTooltip(tooltip)
  local status = player:getBlessingStatus()
  if status == 1 then
    blessedButton:setImageSource('/images/game/blessings/button-blessings-grey-idle')
  elseif status == 2 then
    blessedButton:setImageSource('/images/game/blessings/button-blessings-gold-idle')
  elseif status == 3 then
    blessedButton:setImageSource('/images/game/blessings/button-blessings-green-idle')
  end
end

-- controls
function update()
  local fightMode = g_game.getFightMode()
  if fightMode == FightOffensive then
    fightModeRadioGroup:selectWidget(fightOffensiveBox)
  elseif fightMode == FightBalanced then
    fightModeRadioGroup:selectWidget(fightBalancedBox)
  else
    fightModeRadioGroup:selectWidget(fightDefensiveBox)
  end

  local chaseMode = g_game.getChaseMode()
  if chaseMode == ChaseOpponent then
    chaseModeRadioGroup:selectWidget(chaseModeChaseBox)
  else
    chaseModeRadioGroup:selectWidget(chaseModeStandBox)
  end

  local safeFight = g_game.isSafeFight()
  safeFightButton:setChecked(not safeFight)
  if safeFightButton:isChecked() then
    safeFightButton:setTooltip(tr("Secure Mode Off: You are able to attack someone by targeting,\nregardless of your expert mode. You risk white, red and black\nskulls as well as a protection zone block."))
  else
    safeFightButton:setTooltip(tr("Secure Mode On: You are able to attack only those players\nyour expert mode allows. You risk skulls and protection zone\nblocks depending on your active expert mode."))
  end

  if buttonPvp then
    local isOpenPvPWorld = g_game.getCanChangePvpFrameOption()
    if not isOpenPvPWorld then
      pvpModesPanel:setVisible(false)
      buttonPvp:setChecked(false)
    end

    buttonPvp:setEnabled(isOpenPvPWorld)
  end

  if g_game.getFeature(GamePVPMode) then
    local pvpMode = g_game.getPVPMode()
    local pvpWidget = getPVPBoxByMode(pvpMode)
  end
end

function check()
  if m_settings.getOption('autoChaseOverride') then
    if g_game.isAttacking() and g_game.getChaseMode() == ChaseOpponent then
      g_game.doThing(false)
      g_game.setChaseMode(DontChase)
      g_game.doThing(true)
    end
  end
end

function online()
  local benchmark = g_clock.millis()
  local player = g_game.getLocalPlayer()
  if player then
    local char = g_game.getCharacterName()

    local lastCombatControls = g_settings.getNode('LastCombatControls')

    -- Check if the world is OpenPVP and Enable buttonPvp
    if g_game.getCanChangePvpFrameOption() then
        buttonPvp:setOn(true)
      else
        buttonPvp:setOn(false)
    end

    if not table.empty(lastCombatControls) then
      if lastCombatControls[char] then
        local lasfightMode = lastCombatControls[char].fightMode
        local laschaseMode = lastCombatControls[char].chaseMode
        g_game.doThing(false)
        g_game.setFightMode(lasfightMode)
        g_game.doThing(true)
        g_game.doThing(false)
        g_game.setChaseMode(laschaseMode)
        g_game.doThing(true)
        g_game.doThing(false)
        g_game.setSafeFight(true)
        g_game.doThing(true)
        g_game.doThing(false)
        g_game.setPVPMode(0)
        g_game.doThing(true)
      end
    end
  end
  update()
  refresh()
  consoleln("Inventory controls refreshed in " .. (g_clock.millis() - benchmark) / 1000 .. " seconds.")
end

function offline()
  local lastCombatControls = g_settings.getNode('LastCombatControls')
  if not lastCombatControls then
    lastCombatControls = {}
  end

  local player = g_game.getLocalPlayer()
  if player then
    local char = g_game.getCharacterName()
    lastCombatControls[char] = {
      fightMode = g_game.getFightMode(),
      chaseMode = g_game.getChaseMode(),
    }

    -- save last combat control settings
    g_settings.setNode('LastCombatControls', lastCombatControls)
  end
end

function onSetFightMode(self, selectedFightButton)
  if selectedFightButton == nil then return end
  local buttonId = selectedFightButton:getId()
  local fightMode
  if buttonId == 'fightOffensiveBox' then
    fightMode = FightOffensive
  elseif buttonId == 'fightBalancedBox' then
    fightMode = FightBalanced
  else
    fightMode = FightDefensive
  end
  g_game.doThing(false)
  g_game.setFightMode(fightMode)
  g_game.doThing(true)
end

function onSetChaseMode(self, selectedButton)
  if selectedButton == nil then return end
  local buttonId = selectedButton:getId()
  local chaseMode
  if buttonId == 'chaseModeBoxChase' then
    chaseMode = ChaseOpponent
  else
    chaseMode = DontChase
  end
  g_game.doThing(false)
  g_game.setChaseMode(chaseMode)
  g_game.doThing(true)
end

function onSetSafeFight(self, checked)
  g_game.doThing(false)
  g_game.setSafeFight(not checked)
  g_game.doThing(true)
end

function onSetPVPMode(self, selectedPVPButton)
  if selectedPVPButton == nil then
    return
  end

  local buttonId = selectedPVPButton:getId()
  local pvpMode = PVPWhiteDove
  if buttonId == 'whiteDoveBox' then
    pvpMode = PVPWhiteDove
  elseif buttonId == 'whiteHandBox' then
    pvpMode = PVPWhiteHand
  elseif buttonId == 'yellowHandBox' then
    pvpMode = PVPYellowHand
  elseif buttonId == 'redFistBox' then
    pvpMode = PVPRedFist
  end

  g_game.setPVPMode(pvpMode)
end

function getPVPBoxByMode(mode)
  local widget = nil
  if mode == PVPWhiteDove then
    widget = whiteDoveBox
  elseif mode == PVPWhiteHand then
    widget = whiteHandBox
  elseif mode == PVPYellowHand then
    widget = yellowHandBox
  elseif mode == PVPRedFist then
    widget = redFistBox
  end
  return widget
end

function onSoulChange(localPlayer, soul)
  if not soul then return end
  soulLabel:setText(tr'' .. soul)
end

function onFreeCapacityChange(player, freeCapacity)
  if not freeCapacity then return end
  freeCapacity = math.floor(freeCapacity)
  local formattedCapacity = freeCapacity
  if freeCapacity > 100000 and type(tokformat) == 'function' then
    formattedCapacity = tokformat(freeCapacity)
  end
  capLabel.label:setText(tr'' .. formattedCapacity)
  if freeCapacity == 0 then
    capLabel.label:setColor('$var-text-cip-store-red')
  elseif player and player:getTotalCapacity() ~= player:getBaseCapacity() then
    capLabel.label:setColor('#44ad25') -- green
  else
    capLabel.label:setColor('$var-text-cip-color')
  end
end

function onTotalCapacityChange(player, freeCapacity)
  onFreeCapacityChange(player, player:getFreeCapacity())
end

function onBaseCapacityChange(player, freeCapacity)
  onFreeCapacityChange(player, player:getFreeCapacity())
end

function onInventoryMinimize(value)
  minimizeButton = inventoryWindow:recursiveGetChildById('minButton')
  minimizeButton:setOn(value)

  capLabel = inventoryWindow:recursiveGetChildById('capLabel')
  conditionPanel = inventoryWindow:recursiveGetChildById('conditionPanel')
  stopButton = inventoryWindow:recursiveGetChildById('stopButton')
  blessedButton = inventoryWindow:recursiveGetChildById('blessedButton')
  openPvpButton = inventoryWindow:recursiveGetChildById('openPvpButton')
  pvpModesPanel = inventoryWindow:recursiveGetChildById('pvpModesPanel')


  for slots = 1, 10 do
    local slot = inventoryWindow:recursiveGetChildById('slot' .. slots)
    if value then slot:hide() else slot:show() end
  end

  inventoryWindow.minimized = value
  inventoryWindow:setHeight(value and 65 or 170)

  if value then
    capLabel:setMarginTop(-120)
    capLabel:setMarginLeft(-60)
    soulLabel:setMarginTop(-99)
    soulLabel:setMarginLeft(14)

    fightOffensiveBox:setMarginTop(-14)
    fightOffensiveBox:setMarginLeft(-57)
    fightBalancedBox:setMarginTop(-19)
    fightBalancedBox:setMarginLeft(20)
    fightDefensiveBox:setMarginTop(-19)
    fightDefensiveBox:setMarginLeft(20)

    chaseModeStandBox:setMarginTop(22)
    chaseModeStandBox:setMarginLeft(-19)
    chaseModeChaseBox:setMarginTop(-19)
    chaseModeChaseBox:setMarginLeft(20)

    safeFightButton:setSize(tosize("20 20"))
    safeFightButton:setImageSource("/images/game/combatmodes/safefight")
    safeFightButton:setImageClip("0 0 20 20")
    safeFightButton:setMarginTop(3)
    safeFightButton:setMarginLeft(0)

    conditionPanel:setMarginTop(-100)
    conditionPanel:setMarginLeft(14)
    conditionPanel:setMarginRight(-3)
    blessedButton:setMarginTop(44)
    blessedButton:setMarginLeft(-11)

    openPvpButton:setSize(tosize("12 12"))
    openPvpButton:setImageSource("/images/game/combatmodes/min-pvpmode")
    openPvpButton:setImageClip("0 0 12 12")
    openPvpButton:setMarginTop(-11)
    openPvpButton:setMarginLeft(-70)

    pvpModesPanel:setMarginTop(-42)
    pvpModesPanel:setMarginLeft(26)

    stopButton:setMarginTop(25)
    stopButton:setMarginLeft(26)
  else
    capLabel:setMarginTop(4)
    capLabel:setMarginLeft(0)
    soulLabel:setMarginTop(4)
    soulLabel:setMarginLeft(0)

    fightOffensiveBox:setMarginTop(-14)
    fightOffensiveBox:setMarginLeft(8)
    fightBalancedBox:setMarginTop(4)
    fightBalancedBox:setMarginLeft(0)
    fightDefensiveBox:setMarginTop(4)
    fightDefensiveBox:setMarginLeft(0)

    chaseModeStandBox:setMarginTop(0)
    chaseModeStandBox:setMarginLeft(3)
    chaseModeChaseBox:setMarginTop(4)
    chaseModeChaseBox:setMarginLeft(0)
    safeFightButton:setSize(tosize("42 20"))
    safeFightButton:setImageSource("/images/game/combatmodes/pvp")
    safeFightButton:setImageClip("0 0 42 20")
    safeFightButton:setMarginTop(6)
    safeFightButton:setMarginLeft(0)

    conditionPanel:setMarginTop(3)
    conditionPanel:setMarginLeft(0)
    conditionPanel:setMarginRight(0)
    blessedButton:setMarginTop(0)
    blessedButton:setMarginLeft(3)

    openPvpButton:setSize(tosize("20 20"))
    openPvpButton:setImageSource("/images/game/combatmodes/pvpmode")
    openPvpButton:setImageClip("0 0 20 20")
    openPvpButton:setMarginTop(4)
    openPvpButton:setMarginLeft(0)

    pvpModesPanel:setMarginTop(7)
    pvpModesPanel:setMarginLeft(0)

    stopButton:setMarginTop(82)
    stopButton:setMarginLeft(0)
  end
end

function openBlessedWindow()
  g_game.requestBlessings()
end

function move(panel, index, minimized)
  addEvent(function()
    inventoryWindow:setParent(panel)
    inventoryWindow:open()
    if minimized then
      onInventoryMinimize(minimized)
    end
  end)

  return inventoryWindow
end

function onOpenPvpButtonClick(widget)
  pvpModesPanel:setVisible(not pvpModesPanel:isVisible())
  if pvpModesPanel:isVisible() then
    buttonPvp:setChecked(true)
  else
    buttonPvp:setChecked(false)
  end
end

function onSelectionChangePvp(widget, selectedWidget)
  g_game.setPVPMode(selectedWidget.pvpMode)
end

function getConditionPanel()
  return conditionPanel
end

function onLeftSlotChange(itemId)
  if not g_game.isOnline() then
    return
  end
  modules.game_topbar.onUpdateProficiencyWidget(itemId == 0)
end
