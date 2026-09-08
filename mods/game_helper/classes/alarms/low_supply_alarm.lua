-- ===== HELPER LOW SUPPLY ALARM =====
-- Modulo para gerenciar alarme de supply baixo do Helper
-- Usa _Helper.AlarmSettings para load/save do flag enabled (secao "supply" em alarms.json)
-- Usa helperConfig.supplyProfiles para profiles e regras (em helper.json)

if not _Helper then
  _Helper = {}
end

_Helper.LowSupplyAlarm = {}

-- Expor via modules para acesso em callbacks OTUI
modules.game_helper = modules.game_helper or {}
modules.game_helper.lowSupplyAlarm = _Helper.LowSupplyAlarm

-- ===== CONFIGURACOES LOCAIS =====

local SOUND_FILE = '/sounds/low_supply.ogg'
local CHECK_INTERVAL = 10000 -- 10 segundos

local lastPlayTime = 0
local isLoadingUI = false
local soundPreloaded = false

local settingsWindow = nil
local selectedItemId = 0
local selectedItemName = ""
local mouseGrabberWidget = nil
local editingIndex = nil -- nil = ADD mode, number = UPDATE mode

-- ===== FUNCOES AUXILIARES =====

local function ensurePreloaded()
  if not soundPreloaded and g_sounds then
    g_sounds.preload(SOUND_FILE)
    soundPreloaded = true
  end
end

local function getMouseGrabber()
  if mouseGrabberWidget then return mouseGrabberWidget end
  mouseGrabberWidget = g_ui.createWidget('UIWidget')
  mouseGrabberWidget:setVisible(false)
  mouseGrabberWidget:setFocusable(false)
  return mouseGrabberWidget
end

local function getItemName(itemId, item)
  if item and item.getName then
    local name = item:getName()
    if name and name ~= "" then return name end
  end
  local thingType = g_things.getThingType(itemId, ThingCategoryItem)
  if thingType then
    local marketData = thingType:getMarketData()
    if marketData and marketData.name and marketData.name ~= "" then
      return marketData.name
    end
  end
  return "Item #" .. itemId
end

local function getActiveProfile()
  local helperConfig = _Helper.getHelperConfig()
  if not helperConfig then return nil end
  local profileName = helperConfig.selectedSupplyProfile or "Default"
  local profiles = helperConfig.supplyProfiles
  if not profiles then return nil end
  return profiles[profileName]
end

local function getRulesList()
  if not settingsWindow then return nil end
  return settingsWindow:recursiveGetChildById('rulesList')
end

local function updateArrowButtonStates()
  local rulesList = getRulesList()
  if rulesList and _RuleList then
    _RuleList.updateArrowButtonStates(rulesList)
  end
end

-- ===== FUNCOES DO LOW SUPPLY ALARM =====

_Helper.LowSupplyAlarm.toggle = function(checked)
  if isLoadingUI then return end

  local config = _Helper.AlarmSettings.getConfig()
  config.supply.enabled = checked

  if not checked then
    if g_sounds then
      g_sounds.stopAlarm()
    end
  end

  if not checked then
    lastPlayTime = 0
  end

  _Helper.AlarmSettings.saveConfig()
end

_Helper.LowSupplyAlarm.check = function()
  if not g_game.isOnline() then return end

  -- Check client option (Options > Interface > Game Window > Alert Supply)

  local config = _Helper.AlarmSettings.getConfig()
  if not config.supply.enabled then return end

  local player = g_game.getLocalPlayer()
  if not player then return end

  -- Skip if in protect zone and option is disabled
  if player:isInProtectionZone() and not config.supply.alertInProtectZone then return end

  local profile = getActiveProfile()
  if not profile or not profile.rules then return end

  local triggerRule = nil
  for _, rule in ipairs(profile.rules) do
    if rule.enabled and rule.itemId and rule.itemId > 0 then
      local count = player:getInventoryCount(rule.itemId, 0)
      -- Also count the decayed/equipped variant of the item
      if ItemsDatabase and ItemsDatabase.decayMapping then
        local equippedId = ItemsDatabase.decayMapping[rule.itemId]
        if equippedId then
          count = count + player:getInventoryCount(equippedId, 0)
        end
        local unequippedId = ItemsDatabase.reverseDecayMapping and ItemsDatabase.reverseDecayMapping[rule.itemId]
        if unequippedId then
          count = count + player:getInventoryCount(unequippedId, 0)
        end
      end
      if count < (rule.threshold or 0) then
        triggerRule = rule
        break
      end
    end
  end

  if not triggerRule then return end

  local now = g_clock.millis()
  if lastPlayTime > 0 and now - lastPlayTime < CHECK_INTERVAL then
    return
  end

  lastPlayTime = now

  if g_sounds then
    ensurePreloaded()
    g_sounds.playAlarm(SOUND_FILE)
  end

  if modules.client_options.getOption('alertSupply') == false then return end
  -- Show notifier with item icon
  local notifierMod = modules.notifier
  if notifierMod and notifierMod.Notifier and notifierMod.Notifier.show then
    local itemName = triggerRule.name or ("Item #" .. triggerRule.itemId)
    notifierMod.Notifier.show({
      type = "item",
      itemId = triggerRule.itemId,
      title = "Low Supply",
      description = itemName,
      duration = 3000,
      source = "alert"
    })
  end
end

_Helper.LowSupplyAlarm.resetCheckbox = function()
  if g_sounds then
    g_sounds.stopAlarm()
  end
  lastPlayTime = 0

  -- Fechar settings window se aberta
  if settingsWindow then
    settingsWindow:destroy()
    settingsWindow = nil
  end
end

_Helper.LowSupplyAlarm.loadToUI = function()
  -- Nada a fazer no loadToUI: config de profiles vem do helperConfig
end

_Helper.LowSupplyAlarm.loadToModal = function(window)
  if not window then return end

  local config = _Helper.AlarmSettings.getConfig()

  isLoadingUI = true

  local checkbox = window:recursiveGetChildById("lowSupplyAlarm")
  if checkbox then
    checkbox:setChecked(config.supply.enabled or false)
  end

  isLoadingUI = false

  if checkbox then
    checkbox.onCheckChange = function(widget, checked)
      _Helper.LowSupplyAlarm.toggle(checked)
    end
  end
end

-- ===== RULE MANAGEMENT =====

_Helper.LowSupplyAlarm.getActiveProfile = function()
  return getActiveProfile()
end

_Helper.LowSupplyAlarm.addOrUpdateRule = function()
  if not settingsWindow then return end
  if selectedItemId == 0 then
    modules.game_textmessage.displayFailureMessage(tr('Select an item first!'))
    return
  end

  local thInput = settingsWindow:recursiveGetChildById('thresholdInput')
  local threshold = thInput and tonumber(thInput:getText()) or 0
  if threshold <= 0 then
    modules.game_textmessage.displayFailureMessage(tr('Enter a valid threshold!'))
    return
  end

  local profile = getActiveProfile()
  if not profile then return end
  if not profile.rules then profile.rules = {} end

  local rule = {
    itemId = selectedItemId,
    name = selectedItemName,
    threshold = threshold,
    enabled = true
  }

  if editingIndex then
    -- Update existing rule, preserving enabled state
    if profile.rules[editingIndex] then
      rule.enabled = profile.rules[editingIndex].enabled
      profile.rules[editingIndex] = rule
    end
  else
    -- Check for duplicate itemId
    for _, r in ipairs(profile.rules) do
      if r.itemId == selectedItemId then
        modules.game_textmessage.displayFailureMessage(tr('This item is already in the list!'))
        return
      end
    end
    -- Add new rule
    table.insert(profile.rules, rule)
  end

  _Helper.LowSupplyAlarm.updateRulesList()
  _Helper.LowSupplyAlarm.clearForm()
  saveSettings()
end

_Helper.LowSupplyAlarm.removeRule = function(index)
  local profile = getActiveProfile()
  if not profile or not profile.rules then return end

  local ruleName = "this rule"
  if profile.rules[index] then
    ruleName = profile.rules[index].name or "this rule"
  end

  _RuleList.confirmRemove(ruleName, function()
    table.remove(profile.rules, index)
    _Helper.LowSupplyAlarm.updateRulesList()

    if editingIndex == index then
      _Helper.LowSupplyAlarm.clearForm()
    elseif editingIndex and editingIndex > index then
      editingIndex = editingIndex - 1
    end

    saveSettings()
  end)
end

_Helper.LowSupplyAlarm.toggleRule = function(index, enabled)
  local profile = getActiveProfile()
  if not profile or not profile.rules or not profile.rules[index] then return end
  profile.rules[index].enabled = enabled

  -- Update the widget directly without rebuilding the list
  local rulesList = getRulesList()
  if rulesList then
    local children = rulesList:getChildren()
    if children[index] then
      if enabled then
        if index == editingIndex then
          children[index]:setBackgroundColor('#3a6a3a88') -- Green for selected
        else
          children[index]:setBackgroundColor('#00000022') -- Default
        end
      else
        children[index]:setBackgroundColor('#6a3a3a88') -- Red for disabled
      end
    end
  end

  saveSettings()
end

_Helper.LowSupplyAlarm.moveRuleUp = function(index)
  local profile = getActiveProfile()
  if not profile or not profile.rules then return end

  local rulesList = getRulesList()
  if _RuleList and _RuleList.swapRule(rulesList, profile.rules, index, -1) then
    -- Update editingIndex if the edited rule moved
    if editingIndex == index then
      editingIndex = index - 1
    elseif editingIndex == index - 1 then
      editingIndex = index
    end
    saveSettings()
    updateArrowButtonStates()
  end
end

_Helper.LowSupplyAlarm.moveRuleDown = function(index)
  local profile = getActiveProfile()
  if not profile or not profile.rules then return end

  local rulesList = getRulesList()
  if _RuleList and _RuleList.swapRule(rulesList, profile.rules, index, 1) then
    -- Update editingIndex if the edited rule moved
    if editingIndex == index then
      editingIndex = index + 1
    elseif editingIndex == index + 1 then
      editingIndex = index
    end
    saveSettings()
    updateArrowButtonStates()
  end
end

_Helper.LowSupplyAlarm.loadProfileByName = function(name)
  local helperConfig = _Helper.getHelperConfig()
  if not helperConfig then return end
  helperConfig.selectedSupplyProfile = name
  saveSettings()
  _Helper.LowSupplyAlarm.clearForm()
  _Helper.LowSupplyAlarm.updateRulesList()
end

-- ===== RULE CLICK / SELECTION =====

_Helper.LowSupplyAlarm.onRuleClick = function(index)
  local profile = getActiveProfile()
  if not profile or not profile.rules or not profile.rules[index] then return end

  local rule = profile.rules[index]
  editingIndex = index

  -- Load rule data into form
  selectedItemId = rule.itemId
  selectedItemName = rule.name or ("Item #" .. rule.itemId)

  if settingsWindow then
    -- Update item button
    local itemButton = settingsWindow:recursiveGetChildById('itemButton')
    if itemButton then
      itemButton:setImageSource('/images/ui/item')
      local existingItem = itemButton:getChildById('formItem')
      if not existingItem then
        existingItem = g_ui.createWidget('UIItem', itemButton)
        existingItem:setId('formItem')
        existingItem:setSize({ width = 32, height = 32 })
        existingItem:setPhantom(true)
        existingItem:fill('parent')
      end
      existingItem:setItemId(rule.itemId)
      itemButton:setTooltip(selectedItemName)
    end

    -- Update item name label
    local itemNameLabel = settingsWindow:recursiveGetChildById('itemNameLabel')
    if itemNameLabel then
      itemNameLabel:setText(selectedItemName)
      itemNameLabel:setColor('$var-text-color')
    end

    -- Update threshold
    local thresholdInput = settingsWindow:recursiveGetChildById('thresholdInput')
    if thresholdInput then
      thresholdInput:setText(tostring(rule.threshold or 0))
    end

    -- Change button to "Update" and show clear
    local addButton = settingsWindow:recursiveGetChildById('addButton')
    if addButton then
      addButton:setText("Update")
    end
    local clearButton = settingsWindow:recursiveGetChildById('clearButton')
    if clearButton then
      clearButton:setVisible(true)
    end
  end

  -- Update visual selection in the list
  _Helper.LowSupplyAlarm.updateRuleSelection()
end

_Helper.LowSupplyAlarm.updateRuleSelection = function()
  local rulesList = getRulesList()
  if not rulesList then return end

  local profile = getActiveProfile()
  if not profile or not profile.rules then return end

  local children = rulesList:getChildren()
  for i, child in ipairs(children) do
    local rule = profile.rules[i]
    local isSelected = (i == editingIndex)
    local isEnabled = rule and rule.enabled

    if isSelected then
      child:setBackgroundColor('#3a6a3a88') -- Green for selected
    elseif not isEnabled then
      child:setBackgroundColor('#6a3a3a88') -- Red for disabled
    else
      child:setBackgroundColor('#00000022') -- Default
    end
  end
end

_Helper.LowSupplyAlarm.showRuleContextMenu = function(index, ruleName, position)
  local menu = g_ui.createWidget('PopupMenu')

  menu:addOption(tr('Edit'), function()
    _Helper.LowSupplyAlarm.onRuleClick(index)
  end)

  menu:addSeparator()

  menu:addOption(tr('Move Up'), function()
    _Helper.LowSupplyAlarm.moveRuleUp(index)
  end)

  menu:addOption(tr('Move Down'), function()
    _Helper.LowSupplyAlarm.moveRuleDown(index)
  end)

  menu:addSeparator()

  menu:addOption(tr('Remove'), function()
    _Helper.LowSupplyAlarm.removeRule(index)
  end)

  menu:display(position)
end

-- ===== RULE LIST UI =====

_Helper.LowSupplyAlarm.updateRulesList = function()
  if not settingsWindow then return end

  local rulesList = settingsWindow:recursiveGetChildById('rulesList')
  if not rulesList then return end

  rulesList:destroyChildren()

  local profile = getActiveProfile()
  if not profile or not profile.rules then return end

  for _, rule in ipairs(profile.rules) do
    local widget = g_ui.createWidget('RuleListItem', rulesList)

    -- Set type indicator
    local typeIcon = widget:getChildById('typeIcon')
    if typeIcon then
      typeIcon:setText("S")
      typeIcon:setColor("#44aaff")
    end

    -- Set item icon
    local itemIcon = widget:getChildById('itemIcon')
    if itemIcon and rule.itemId > 0 then
      itemIcon:setImageSource('/images/ui/item')
      local itemWidget = g_ui.createWidget('UIItem', itemIcon)
      itemWidget:setId('ruleItemIcon')
      itemWidget:setSize({ width = 22, height = 22 })
      itemWidget:setPhantom(true)
      itemWidget:fill('parent')
      itemWidget:setItemId(rule.itemId)
    end

    -- Set name
    local ruleName = widget:getChildById('ruleName')
    if ruleName then
      ruleName:setText(rule.name or ("Item #" .. rule.itemId))
    end

    -- Set summary
    local ruleSummary = widget:getChildById('ruleSummary')
    if ruleSummary then
      ruleSummary:setText("Count < " .. (rule.threshold or 0))
    end

    -- Helper to get the current index of this widget in the list
    local function currentIndex()
      return rulesList:getChildIndex(widget)
    end

    -- Set enable checkbox
    local enableCheck = widget:getChildById('enableCheck')
    if enableCheck then
      enableCheck:setChecked(rule.enabled ~= false)
      enableCheck.onCheckChange = function(w)
        _Helper.LowSupplyAlarm.toggleRule(currentIndex(), w:isChecked())
      end
    end

    _RuleList.setupDoubleClickToggle(widget)

    -- Apply disabled background color if rule is disabled
    if not rule.enabled then
      widget:setBackgroundColor('#6a3a3a88')
    end

    -- Set move up button
    local moveUpButton = widget:getChildById('moveUpButton')
    if moveUpButton then
      moveUpButton.onClick = function()
        _Helper.LowSupplyAlarm.moveRuleUp(currentIndex())
      end
    end

    -- Set move down button
    local moveDownButton = widget:getChildById('moveDownButton')
    if moveDownButton then
      moveDownButton.onClick = function()
        _Helper.LowSupplyAlarm.moveRuleDown(currentIndex())
      end
    end

    -- Set remove button
    local removeButton = widget:getChildById('removeButton')
    if removeButton then
      removeButton.onClick = function()
        _Helper.LowSupplyAlarm.removeRule(currentIndex())
      end
    end

    -- Click on rule to edit (left click) or show context menu (right click)
    local capturedRuleName = rule.name or ("Item #" .. rule.itemId)
    widget.onMouseRelease = function(w, mousePos, mouseButton)
      if mouseButton == MouseLeftButton then
        local clickedChild = w:getChildByPos(mousePos)
        if clickedChild then
          local childId = clickedChild:getId()
          if childId == 'enableCheck' or childId == 'removeButton' or childId == 'moveUpButton' or childId == 'moveDownButton' then
            return false
          end
        end
        _Helper.LowSupplyAlarm.onRuleClick(currentIndex())
        return true
      elseif mouseButton == MouseRightButton then
        _Helper.LowSupplyAlarm.showRuleContextMenu(currentIndex(), capturedRuleName, mousePos)
        return true
      end
      return false
    end
  end

  updateArrowButtonStates()
  _Helper.LowSupplyAlarm.updateRuleSelection()
end

-- ===== ITEM SELECTION =====

_Helper.LowSupplyAlarm.clearForm = function()
  selectedItemId = 0
  selectedItemName = ""
  editingIndex = nil

  if not settingsWindow then return end

  local itemButton = settingsWindow:recursiveGetChildById('itemButton')
  if itemButton then
    itemButton:setImageSource('/images/game/actionbar/actionbarslot')
    local existingItem = itemButton:getChildById('formItem')
    if existingItem then existingItem:destroy() end
    itemButton:setTooltip('')
  end

  local itemNameLabel = settingsWindow:recursiveGetChildById('itemNameLabel')
  if itemNameLabel then
    itemNameLabel:setText('Click to select item')
    itemNameLabel:setColor('#888888')
  end

  local thresholdInput = settingsWindow:recursiveGetChildById('thresholdInput')
  if thresholdInput then
    thresholdInput:setText('1')
  end

  -- Reset button to "Add" and hide clear
  local addButton = settingsWindow:recursiveGetChildById('addButton')
  if addButton then
    addButton:setText("Add")
  end
  local clearButton = settingsWindow:recursiveGetChildById('clearButton')
  if clearButton then
    clearButton:setVisible(false)
  end

  -- Clear visual selection
  _Helper.LowSupplyAlarm.updateRuleSelection()
end

_Helper.LowSupplyAlarm.selectItem = function()
  local grabber = getMouseGrabber()

  grabber:grabMouse()
  if settingsWindow then settingsWindow:hide() end
  g_mouse.pushCursor('target')

  grabber.onMouseRelease = function(self, mousePosition, mouseButton)
    _Helper.LowSupplyAlarm.onItemSelected(self, mousePosition, mouseButton)
  end
end

_Helper.LowSupplyAlarm.onItemSelected = function(self, mousePosition, mouseButton)
  local grabber = getMouseGrabber()

  grabber:ungrabMouse()
  if settingsWindow then
    settingsWindow:show()
    settingsWindow:raise()
    settingsWindow:focus()
  end
  g_mouse.popCursor('target')
  grabber.onMouseRelease = nil

  local rootWidget = g_ui.getRootWidget()
  if not rootWidget then return true end

  local clickedWidget = rootWidget:recursiveGetChildByPos(mousePosition, false)
  if not clickedWidget then return true end

  local itemId = 0
  local item = nil

  if clickedWidget:getClassName() == 'UIItem' and not clickedWidget:isVirtual() then
    item = clickedWidget:getItem()
    if item then
      itemId = item:getId()
    end
  elseif clickedWidget:getClassName() == 'UIGameMap' then
    local tile = clickedWidget:getTile(mousePosition)
    if tile then
      local topUseThing = tile:getTopUseThing()
      if topUseThing then
        itemId = topUseThing:getId()
        item = topUseThing
      end
    end
  end

  if itemId == 0 then
    modules.game_textmessage.displayFailureMessage(tr('No item selected!'))
    return true
  end

  local itemName = getItemName(itemId, item)

  selectedItemId = itemId
  selectedItemName = itemName

  if not settingsWindow then return true end

  -- Update item button
  local itemButton = settingsWindow:recursiveGetChildById('itemButton')
  if itemButton then
    itemButton:setImageSource('/images/ui/item')
    local existingItem = itemButton:getChildById('formItem')
    if not existingItem then
      existingItem = g_ui.createWidget('UIItem', itemButton)
      existingItem:setId('formItem')
      existingItem:setSize({ width = 32, height = 32 })
      existingItem:setPhantom(true)
      existingItem:fill('parent')
    end
    existingItem:setItemId(itemId)
    itemButton:setTooltip(itemName)
  end

  -- Update item name label
  local itemNameLabel = settingsWindow:recursiveGetChildById('itemNameLabel')
  if itemNameLabel then
    itemNameLabel:setText(itemName)
    itemNameLabel:setColor('$var-text-color')
  end

  -- Show clear button
  local clearButton = settingsWindow:recursiveGetChildById('clearButton')
  if clearButton then
    clearButton:setVisible(true)
  end

  -- Focus threshold input with cursor at end
  local thresholdInput = settingsWindow:recursiveGetChildById('thresholdInput')
  if thresholdInput then
    thresholdInput:focus()
    thresholdInput:setCursorPos(#thresholdInput:getText())
  end

  return true
end

-- ===== SETTINGS WINDOW =====

_Helper.LowSupplyAlarm.openSettings = function()
  if settingsWindow then
    settingsWindow:destroy()
    settingsWindow = nil
  end

  -- Hide alarm settings while supply settings is open
  local alarmWindow = _Helper.AlarmSettings.getWindow()
  if alarmWindow then
    alarmWindow:hide()
  end

  settingsWindow = g_ui.createWidget('LowSupplyAlarmWindow', g_ui.getRootWidget())
  if not settingsWindow then return end

  -- Setup threshold numeric input
  local thresholdInput = settingsWindow:recursiveGetChildById('thresholdInput')
  if thresholdInput and _Helper.setupNumericInput then
    _Helper.setupNumericInput(thresholdInput, 1, nil)
  end

  -- Setup item button click
  local itemButton = settingsWindow:recursiveGetChildById('itemButton')
  if itemButton then
    itemButton.onClick = function()
      _Helper.LowSupplyAlarm.selectItem()
    end
  end

  -- Setup add/update button
  local addButton = settingsWindow:recursiveGetChildById('addButton')
  if addButton then
    addButton.onClick = function()
      _Helper.LowSupplyAlarm.addOrUpdateRule()
    end
  end

  -- Setup clear button
  local clearButton = settingsWindow:recursiveGetChildById('clearButton')
  if clearButton then
    clearButton.onClick = function()
      _Helper.LowSupplyAlarm.clearForm()
    end
  end

  -- Setup presets
  local pm = modules.game_helper and modules.game_helper.presetManager
  if pm then
    local ctx = pm.buildSupplyContext()
    if ctx then
      ctx.presetsPanel = settingsWindow:recursiveGetChildById('presetsSection')
      pm.setSupplyContext(ctx)
      pm.initPresets(ctx)
      pm.loadProfileOptions(ctx)
    end
  end

  -- Setup alertInProtectZone checkbox
  local alertPzCheckbox = settingsWindow:recursiveGetChildById('alertInProtectZone')
  if alertPzCheckbox then
    local config = _Helper.AlarmSettings.getConfig()
    alertPzCheckbox:setChecked(config.supply.alertInProtectZone == true)
    alertPzCheckbox.onCheckChange = function(_, checked)
      local cfg = _Helper.AlarmSettings.getConfig()
      cfg.supply.alertInProtectZone = checked
      _Helper.AlarmSettings.saveConfig()
    end
  end

  -- Clear form and load rules
  _Helper.LowSupplyAlarm.clearForm()
  _Helper.LowSupplyAlarm.updateRulesList()
end

_Helper.LowSupplyAlarm.closeSettings = function()
  if settingsWindow then
    settingsWindow:destroy()
    settingsWindow = nil
  end

  -- Clear supply context since presetsPanel is destroyed with the modal
  local pm = modules.game_helper and modules.game_helper.presetManager
  if pm then
    pm.setSupplyContext(nil)
  end

  -- Show alarm settings again
  local alarmWindow = _Helper.AlarmSettings.getWindow()
  if alarmWindow then
    alarmWindow:show()
    alarmWindow:raise()
    alarmWindow:focus()
  end
end

-- ===== FIM HELPER LOW SUPPLY ALARM =====
