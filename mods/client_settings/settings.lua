local importFiles = {
  'styles/hotkey',
  'styles/assingobjectwindow',
  'styles/assingtextwindow',
  'styles/spell',
  'styles/text',
  'styles/object'
}

ActionTypes = {
  USE = 0,
  USE_SELF = 1,
  USE_TARGET = 2,
  USE_WITH = 3,
  EQUIP = 4
}

ActionColors = {
  empty = '#00000033',
  text = '#00000033',
  itemUse = '#8888FF88',
  itemUseSelf = '#00FF0088',
  itemUseTarget = '#FF000088',
  itemUseWith = '#F5B32588',
  itemEquip = '#FFFFFF88'
}

function canAssignEquipItem(item)
  if not item then
    return false
  end

  if modules.game_actionbar and modules.game_actionbar.canEquipItem then
    return modules.game_actionbar.canEquipItem(item)
  end

  local clothSlot = item:getClothSlot()
  local classification = item:getClassification()
  local isAmmo = item:isAmmo()
  local hasWearOut = item.hasWearOut and item:hasWearOut() or false
  local isMarketEquipable = false
  if MarketCategory and g_things and g_things.getThingType then
    local thingType = g_things.getThingType(item:getId(), ThingCategoryItem)
    if thingType and thingType.getMarketData then
      local ok, marketData = pcall(function() return thingType:getMarketData() end)
      local category = ok and marketData and marketData.category or 0
      isMarketEquipable = category == MarketCategory.Armors or
        category == MarketCategory.Amulets or
        category == MarketCategory.Boots or
        category == MarketCategory.HelmetsHats or
        category == MarketCategory.Legs or
        category == MarketCategory.Rings or
        category == MarketCategory.Shields or
        category == MarketCategory.Ammunition or
        category == MarketCategory.Axes or
        category == MarketCategory.Clubs or
        category == MarketCategory.DistanceWeapons or
        category == MarketCategory.Swords or
        category == MarketCategory.WandsRods or
        category == MarketCategory.Quivers or
        category == MarketCategory.FistWeapons or
        category == MarketCategory.WeaponsAll or
        category == MarketCategory.MetaWeapons
    end
  end
  local isServerEquipable = false
  if item.isEquipableByServerType then
    local ok, value = pcall(function() return item:isEquipableByServerType() end)
    isServerEquipable = ok and value or false
  elseif item.isEquipable then
    local ok, value = pcall(function() return item:isEquipable() end)
    isServerEquipable = ok and value or false
  end

  if item:isContainer() and not (isServerEquipable or isMarketEquipable or clothSlot > 0 or classification > 0 or isAmmo or hasWearOut) then
    return false
  end

  if clothSlot > 0 or isServerEquipable or isMarketEquipable or classification > 0 or isAmmo or hasWearOut then
    return true
  end

  if item.isChargeableByCategory then
    local ok, isChargeableByCategory = pcall(function() return item:isChargeableByCategory() end)
    if ok and isChargeableByCategory and not item:isMultiUse() then
      return true
    end
  end

  if ItemTypeCategory and g_things and g_things.findItemTypeByClientId then
    local itemType = g_things.findItemTypeByClientId(item:getId())
    if itemType and itemType.getCategory then
      local ok, resolvedCategory = pcall(function() return itemType:getCategory() end)
      if ok then
        if resolvedCategory == ItemTypeCategory.Weapon or resolvedCategory == ItemTypeCategory.Ammunition or resolvedCategory == ItemTypeCategory.Armor then
          return true
        end
        if resolvedCategory == ItemTypeCategory.Charges and not item:isMultiUse() and not item:isUsable() then
          return true
        end
      end
    end
  end

  local isChargeable = item.isChargeable and item:isChargeable() or (item.hasCharges and item:hasCharges())
  if clothSlot == 0 and isChargeable and not item:isMultiUse() and not item:isUsable() then
    return true
  end

  return false
end

local options = {
  {id = "controls", style = "ControlsWindow", children = {"generalHotkeys", "actionsHotkeys", "customHotkeys"}},
  {id = "generalHotkeys", style = "HotkeysWindow", parent = "controls"},
  {id = "actionsHotkeys", style = "HotkeysWindow", parent = "controls"},
  {id = "customHotkeys", style = "HotkeysWindow", parent = "controls"},
  -- Interface
  {id = "interface", style = "InterfaceWindow", children = {"hud", "console", "gameWindow", "actionsBars", "controlButtons"}},
  {id = "hud", style = "HudWindow", parent = "interface"},
  {id = "console", style = "ConsoleWindow", parent = "interface"},
  {id = "gameWindow", style = "GameWindow", parent = "interface"},
  {id = "actionsBars", style = "ActionsWindow", parent = "interface"},
  {id = "controlButtons", style = "ControlsButtonsWindow", parent = "interface"},
  -- Graphics
  {id = "graphics", style = "GraphicsWindow", children = {"effects"}},
  {id = "effects", style = "EffectsWindow", parent = "graphics"},
  -- Sound
  -- {id = "sound", style = "SoundWindow", children = {"battleSounds", "uiSounds"}},
  -- {id = "battleSounds", style = "BattleSoundsWindow", parent = "sound"},
  -- {id = "uiSounds", style = "UiSoundsWindow", parent = "sound"},
  -- Misc
  {id = "misc", style = "MiscWindow", children = {"gameplay", "screenshot"}},
  {id = "gameplay", style = "GameplayWindow", parent = "misc"},
  {id = "screenshot", style = "ScreenshotWindow", parent = "misc"}
}

loadedWindows = {}
local loadedButton = {}
local extraOptions = {}

-- antes do apply
local tmpResetActions = {}
local autoApplyEvent = nil
local applyingOptions = false
local pendingInterfaceRefreshEvents = {}

local globalGeneralHotkey = {}
local actionBarHotkey = {}

optionsWindow = nil
selectedButton = nil
selectedWindow = nil
radioItemSelected = nil
lastFocusHK = nil
resetWindow = nil
presetWindow = nil
mouseGrabberSetting = nil

-- hotkeys
local hotkeyWindow = nil
local EditActionWidget = nil
local hotkeyAssignWindow = nil
local deployedWindow = nil
local assingobjectwindow = nil
local assingtextwindow = nil
local buttonsOption = nil
local assingobjectOption = nil
local selectedWidgetItem = nil
local chatModeCheckBox = nil
local chatMode = "chatOn"
HotKeys = {}

local boundCombosCallback = {}
local boundCombosHelper = {}

local function migrateCacheUIDefaultOn()
  if g_settings.getBoolean("astraCacheUIDefaultOnV1") then
    return
  end

  -- Old defaults were persisted on startup, so a saved false is not a reliable
  -- manual opt-out. setupStart only writes defaults; loadSettings applies this
  -- migrated value later in setup().
  g_settings.set("cacheUI", true)
  g_settings.set("astraCacheUIDefaultOnV1", true)
end

function shouldShowLootHighlightEffect()
  return getOption('lootHighlight') ~= false
end

local keybindOptions = KeyBind:getKeyBind("Dialogs", "Open Options")
local keybindCreatureNameBars = KeyBind:getKeyBind("UI", "Show/hide Creature Names and Bars")
local keybindFullScreen = KeyBind:getKeyBind("UI", "Toggle Fullscreen")
local keybindHotkeys = KeyBind:getKeyBind("Dialogs", "Open Options - Custom Hotkeys")

function init()
  for _, v in ipairs(g_extras.getAll()) do
    extraOptions[v] = g_extras.get(v)
    g_settings.setDefault("extras_" .. v, extraOptions[v])
  end

  optionsWindow = g_ui.displayUI('settings')
  isButtonPressed = not isButtonPressed
  optionsWindow:hide()
  g_client.setInputLockWidget(nil)
  for i, option in pairs(options) do
    g_ui.importStyle("options/"..option.id)
    loadedWindows[option.id] = g_ui.createWidget(option.style, optionsWindow.option)
    loadedWindows[option.id].children = option.children
    loadedWindows[option.id].parent = option.parent
    loadedWindows[option.id]:hide()
  end

  GameOptions:setLoadedWindow(loadedWindows)
  GameOptions:setupStart()
  migrateCacheUIDefaultOn()
  g_game.shouldShowLootHighlightEffect = shouldShowLootHighlightEffect

  for i, file in pairs(importFiles) do
    g_ui.importStyle(file)
  end

  -- set options
  for i, option in pairs(options) do
    if not option.parent then
      local widget = g_ui.createWidget('OptionButton', optionsWindow.options)
      widget:setId(option.id)
      widget.button:setImageSource("/images/optionstab/" .. option.id)
      loadedButton[widget:getId()] = widget
    end
  end

  ConditionsHUD:configure()

  mouseGrabberSetting = g_ui.createWidget('UIWidget')
  mouseGrabberSetting:setVisible(false)
  mouseGrabberSetting:setFocusable(false)
  mouseGrabberSetting.onMouseRelease = onChooseItemMouseRelease

  keybindOptions:active(gameRootPanel)
  keybindCreatureNameBars:active(gameRootPanel)
  keybindFullScreen:active(gameRootPanel)
  keybindHotkeys:active(gameRootPanel)

  onClickOptionButton(loadedButton["controls"])

  optionsButton = modules.client_topmenu.addLeftButton('optionsButton', tr('Options'), '/images/topbuttons/options', toggle)

  addEvent(function() setup() end)

  ProtocolGame.registerExtendedOpcode(0x8C, function(protocol, opcode, buffer)
    if #buffer >= 8 then
      local lo = string.byte(buffer, 1) + string.byte(buffer, 2) * 256 +
                string.byte(buffer, 3) * 65536 + string.byte(buffer, 4) * 16777216
      local hi = string.byte(buffer, 5) + string.byte(buffer, 6) * 256 +
                string.byte(buffer, 7) * 65536 + string.byte(buffer, 8) * 16777216
      local highStates = lo + hi * 4294967296
      local player = g_game.getLocalPlayer()
      if player and highStates ~= 0 then
        local combined = player:getStates() + highStates
        ConditionsHUD:notifierStatesChange(player, combined, 0, nil, {})
      end
    end
  end)

  connect(g_game,
          { onGameStart = online,
            onGameEnd = offline,
            onRestingAreaState = onRestingAreaState
          }
  )
  connect(LocalPlayer, { onTakeScreenshot = onScreenShot})

  connect(LocalPlayer, { onStatesChange = onStatesChange,
                        onTaintsChange = onTaintsChange,
                         onSkullChange = onSkullChange,
                        })

  connect(Creature, {onEmblemChange = onEmblemChange})

  radioItemSelected = UIRadioGroup.create()

  HotKeys = {}
  connect(radioItemSelected, { onSelectionChange = onSelectionChange })
end

function terminate()
  g_game.shouldShowLootHighlightEffect = nil

  ConditionsHUD:save()
  disconnect(radioItemSelected, { onSelectionChange = onSelectionChange })
  disconnect(g_game,
              { onGameStart = online,
                onGameEnd = offline,
                onRestingAreaState = onRestingAreaState
              }
            )

  disconnect(LocalPlayer, { onTakeScreenshot = onScreenShot})
  ProtocolGame.unregisterExtendedOpcode(0x8C)
  disconnect(LocalPlayer, { onStatesChange = onStatesChange,
                        onTaintsChange = onTaintsChange,
                         onSoulChange = onSoulChange,
                         onSkullChange = onSkullChange,
                        })
  disconnect(Creature, {onEmblemChange = onEmblemChange})
  for key, combo in pairs(boundCombosCallback) do
    g_keyboard.unbindKeyDown(key, combo, gameRootPanel)
  end

  boundCombosCallback = {}

  if mouseGrabberSetting then
    mouseGrabberSetting:destroy()
    mouseGrabberSetting = nil
  end
  if resetWindow then
    resetWindow:destroy()
    resetWindow = nil
  end
  if EditActionWidget then
    EditActionWidget:destroy()
    EditActionWidget = nil
  end

  keybindCreatureNameBars:deactive(gameRootPanel)
  keybindFullScreen:deactive(gameRootPanel)
  keybindHotkeys:deactive(gameRootPanel)

  if radioItemSelected then
    radioItemSelected:destroy()
    radioItemSelected = nil
  end

  if optionsWindow then
    optionsWindow:destroy()
    optionsWindow = nil
  end

  -- destroy hotkeys
  local actionbarHotkey = loadedWindows["actionsHotkeys"]
  if actionbarHotkey then
    local panel = actionbarHotkey:recursiveGetChildById("hotkeyList")
    if panel then
      panel:destroyChildren()
    end
  end

  actionBarHotkey = {}

  for i, widget in pairs(loadedWindows) do
    if widget and not widget:isDestroyed() then
      widget:destroy()
    end
  end

  loadedWindows = {}
end

function setHealthCircleModules(value)
  local gameMapPanel = m_interface and m_interface.getMapPanel and m_interface.getMapPanel()
  if gameMapPanel and gameMapPanel.setShowArcs then
    gameMapPanel:setShowArcs(false)
  end

  if modules.game_healthcircle then
    if modules.game_healthcircle.handleShowArc then
      modules.game_healthcircle.handleShowArc(value)
    else
      if modules.game_healthcircle.setHealthCircle then
        modules.game_healthcircle.setHealthCircle(value)
      end
      if modules.game_healthcircle.setManaCircle then
        modules.game_healthcircle.setManaCircle(value)
      end
    end
  end
end

local function refreshOnlineInterfaceOptions()
  if not g_game.isOnline() then
    return
  end

  setHealthCircleModules(getOption("showHealthManaCircle"))

  if modules.game_topbar then
    if modules.game_topbar.reloadFromSettings then
      modules.game_topbar.reloadFromSettings(getOption("customisableBars"))
    elseif modules.game_topbar.toggle then
      modules.game_topbar.toggle(getOption("customisableBars"))
    end
  end
end

local function scheduleOnlineInterfaceOptionsRefresh()
  for _, event in ipairs(pendingInterfaceRefreshEvents) do
    removeEvent(event)
  end
  pendingInterfaceRefreshEvents = {}

  -- Retry through the login/layout settle window because interface modules finish at different ticks.
  local delays = {50, 250, 750, 1500, 3000}
  for index, delay in ipairs(delays) do
    pendingInterfaceRefreshEvents[#pendingInterfaceRefreshEvents + 1] = scheduleEvent(function()
      refreshOnlineInterfaceOptions()
      if index == #delays then
        pendingInterfaceRefreshEvents = {}
      end
    end, delay)
  end
end

function online()
  local benchmark = g_clock.millis()
  tmpResetActions = {}
  local gameMapPanel = m_interface and m_interface.getMapPanel()
  if gameMapPanel then
    gameMapPanel:setAntiAliasingMode(GameOptions:getOption("antialiasing"))
  else
    local retryEvent
    local retries = 0
    retryEvent = cycleEvent(function()
      local panel = m_interface and m_interface.getMapPanel()
      if panel then
        panel:setAntiAliasingMode(GameOptions:getOption("antialiasing"))
        retryEvent:cancel()
      else
        retries = retries + 1
        if retries >= 10 then
          retryEvent:cancel()
        end
      end
    end, 500)
  end

  if Options.getAutoSwtichPreset() then
    autoSwitchHotkey()
  end

  KeyBinds:setupAndReset(Options.currentHotkeySetName, (Options.isChatOnEnabled and "chatOn" or "chatOff"))
  configureGeneralHotkeys()
  CustomHotkeys.createList(true)

  ActionHotkey.configureActionBarHotkeys()
  ConditionsHUD:onGameStart()
  scheduleOnlineInterfaceOptionsRefresh()
  consoleln("Settings loaded in " .. (g_clock.millis() - benchmark) / 1000 .. " seconds.")
end

function offline()
  if presetWindow then
  presetWindow:destroy()
  end
  lastFocusHK = nil
  ConditionsHUD:onGameEnd()
  m_settings:closeOptions()
end

-- toggle
function toggle()
  m_settings:openOptions()
end

local displayState = 0

function toggleDisplays()
  local gameMapPanel = m_interface.getMapPanel()
  displayState = (displayState + 1) % 4

  if displayState == 0 then
    -- Mostrar tudo
    gameMapPanel:setDrawNames(true)
    gameMapPanel:setDrawHealthBars(true)
    gameMapPanel:setDrawManaBar(true)
    gameMapPanel:setDrawOwnName(true)
    if getOption("showOwnHealth") then
      gameMapPanel:setDrawOwnHealth(true)
    end
    if getOption("showOwnMana") then
      gameMapPanel:setDrawOwnManaBar(true)
      gameMapPanel:setDrawOwnManaShieldBar(true)
    end
    if getOption("showHarmony") then
      gameMapPanel:setDrawHarmonyBar(true)
    end
    if getOption("showHealthManaCircle") then
      setHealthCircleModules(true)
    end
  elseif displayState == 1 then
    -- Ocultar own
    gameMapPanel:setDrawOwnName(false)
    gameMapPanel:setDrawOwnHealth(false)
    gameMapPanel:setDrawOwnManaBar(false)
    gameMapPanel:setDrawOwnManaShieldBar(false)
    gameMapPanel:setDrawPlayerBars(false)
    setHealthCircleModules(false)
  elseif displayState == 2 then
    -- Ocultar others e mostrar own
    gameMapPanel:setDrawNames(false)
    gameMapPanel:setDrawHealthBars(false)
    gameMapPanel:setDrawManaBar(false)
    gameMapPanel:setDrawOwnName(true)
    if getOption("showOwnHealth") then
      gameMapPanel:setDrawOwnHealth(true)
    end
    if getOption("showOwnMana") then
      gameMapPanel:setDrawOwnManaBar(true)
      gameMapPanel:setDrawOwnManaShieldBar(true)
    end
    if getOption("showHealthManaCircle") then
      setHealthCircleModules(true)
    end
  elseif displayState == 3 then
    -- Ocultar tudo
    gameMapPanel:setDrawNames(false)
    gameMapPanel:setDrawHealthBars(false)
    gameMapPanel:setDrawManaBar(false)
    gameMapPanel:setDrawOwnName(false)
    if getOption("showOwnHealth") then
      gameMapPanel:setDrawOwnHealth(false)
    end
    if getOption("showOwnMana") then
      gameMapPanel:setDrawOwnManaBar(false)
      gameMapPanel:setDrawOwnManaShieldBar(false)
    end
    if getOption("showHealthManaCircle") then
      setHealthCircleModules(false)
    end
  end
end

function toggleHotkeys()
  m_settings:openOptions("customHotkeys")
end

function toggleShortcuts()
  m_settings:openOptions()
  onClickOptionButton(loadedButton["interface"], "controlButtons")
end

function toggleOption(key)
  setOption(key, not getOption(key))
end
-- toggle

-- setup buttons
function onSelectionChange(widget, selectedWidget)
  if selectedWidget then

  end
end

function closeOptions()
  if TempOptions:hasOptions() then
    onApplyOptions(nil, true)
  end

  optionsWindow:hide()
  g_client.setInputLockWidget(nil)
  TempOptions:resetAllOptions()
  tmpResetActions = {}

  -- Force update options upon close
  KeyBinds:setupAndReset(Options.currentHotkeySetName, (Options.isChatOnEnabled and "chatOn" or "chatOff"))
end

function openOptions(self, redirectId)
  optionsWindow:show(true)
  optionsWindow:focus()
  g_client.setInputLockWidget(optionsWindow)
  onClickOptionButton(loadedButton["controls"], redirectId)
end

function setup()
  -- load options
  GameOptions:loadSettings()
  TempOptions:resetAllOptions()

  if g_game.isOnline() then
    online()
  end

  configureGeneralHotkeys()
  ActionHotkey.configureActionBarHotkeys()
end

function recursiveButton(widget)
  if widget.button then
    widget.button:setOn(false)
  end
  if widget.extraButton then
    widget.extraButton:destroyChildren()
    widget.extraButton:setHeight(0)
    widget.extraButton:setVisible(false)
  end
  widget:setHeight(20)
end

function onClickOptionButton(widget, redirectId)
  if not redirectId and selectedWindow and selectedWindow:getId() == widget:getId() then
    return
  end

  if selectedWindow then
    selectedWindow:hide()
    if selectedWindow.parent and (not loadedWindows[widget:getId()].parent or not loadedWindows[widget:getId()].children) then
      recursiveButton(loadedButton[selectedWindow.parent])
    end
  end

  if selectedButton then
    recursiveButton(selectedButton)
  end

  selectedButton = widget

  widget.button:setOn(true)
  selectedWindow = loadedWindows[widget:getId()]
  if not redirectId then
    selectedWindow:show(true)
  end

  if selectedWindow.children then
    selectedButton:setHeight(20 * (#selectedWindow.children + 1))
    selectedButton.extraButton:destroyChildren()
    selectedButton.extraButton:setVisible(true)
    selectedButton.extraButton:setHeight(20 * (#selectedWindow.children))
    for i, option in pairs(options) do
      if option.parent and option.parent == selectedWindow:getId() then
        local widget = g_ui.createWidget('NOptionButton', selectedButton.extraButton)
        widget:setId(option.id)
        widget.button:setImageSource("/images/optionstab/" .. option.id)
        widget.button.onClick = function()
          onClickChildOptionButton(widget)
        end

        if redirectId and redirectId == option.id then
          onClickChildOptionButton(widget)
        end
      end
    end
  end

end

function onClickChildOptionButton(widget)
  if selectedWindow then
    selectedWindow:hide()
  end

  if not widget then
    widget = loadedWindows['customHotkeys']
  end

  if selectedButton.button then
    selectedButton.button:setOn(false)
  end
  selectedButton = widget
  if widget.button then
   widget.button:setOn(true)
  end
  selectedWindow = loadedWindows[widget:getId()]
  selectedWindow:show(true)

  --- hack
  if widget:getId() == 'actionsHotkeys' or widget:getId() == 'generalHotkeys' or widget:getId() == 'customHotkeys' then
    radioItemSelected:destroy()
    local isChatLocked = modules.game_console:getChatLocked()
    local chatOn = selectedWindow:recursiveGetChildById('chatOnCheckBox')
    local chatOff = selectedWindow:recursiveGetChildById('chatOffCheckBox')

    radioItemSelected:addWidget(chatOn)
    radioItemSelected:addWidget(chatOff)
    if isChatLocked then
      radioItemSelected:selectWidget(chatOff)
    else
      radioItemSelected:selectWidget(chatOn)
    end

    if lastFocusHK then
      lastFocusHK.firstKey.actionEdit:setVisible(false)
      lastFocusHK:setBackgroundColor(lastFocusHK.lastColor)
    end

    local profile = selectedWindow:recursiveGetChildById('profile')
    onSetupProfile(profile)
    profile:setCurrentOption(Options.currentHotkeySetName, true)
    selectedWindow:recursiveGetChildById('autoSwitchHotkey'):setChecked(Options.getAutoSwtichPreset())

    if widget:getId() == 'actionsHotkeys' then
      ActionHotkey.configureActionBarHotkeys()
    end

    if widget:getId() == 'customHotkeys' then
      local newActionButton = selectedWindow:recursiveGetChildById("newActionButton")
      if newActionButton then
        newActionButton.onMouseRelease = CustomHotkeys.newActionFunc
        newActionButton.onTouchRelease = CustomHotkeys.newActionFunc
      end

      CustomHotkeys.createList()
    end
  elseif widget:getId() == 'controlButtons' then
    displayControlButtons()
  end
end

function onApplyOptions(var, isFromOk)
  if isFromOk == nil then
    isFromOk = false
  end

  if applyingOptions then
    return
  end

  applyingOptions = true
  TempOptions:applyOptions()

  for slot, _ in pairs(tmpResetActions) do
    modules.game_actionbar.resetSlots(slot)
  end

  tmpResetActions = {}
  setupProfile()
  checkRotateOptions(isFromOk)
  onApplyControlButtons()
  applyingOptions = false
end

function setupOkButton()
  if TempOptions:hasOptions() then
    onApplyOptions(nil, true)
  end
  setHotkeyChatMode()
  closeOptions()
end
-- setup buttons

-- options
function setOption(key, value, force)
  if extraOptions[key] ~= nil then
    g_extras.set(key, value)
    g_settings.set("extras_" .. key, value)
    if key == "debugProxy" and modules.game_proxy then
      if value then
        modules.game_proxy.show()
      else
        modules.game_proxy.hide()
      end
    end
    return
  end

  if m_interface == nil then
    return
  end
  GameOptions:setOption(key, value)
end

function getOption(key)
  return GameOptions:getOption(key)
end
function getTmpOption(key)
  return TempOptions:getOption(key)
end

function handleTmpActionBarShow(key, value, parent)
  local allBox
  if getTmpOption(parent) ~= nil then
    allBox = getTmpOption(parent)
  elseif getOption(parent) ~= nil then
    allBox = getOption(parent)
  else
    allBox = false
  end
  local hud = loadedWindows["actionsBars"]:recursiveGetChildById(key)
  if hud then
    hud:setColor(allBox and '$var-text-cip-color' or '$var-cip-inactive-color')
    hud:setChecked(value)
  end
end

function setTempOption(key, value)
  TempOptions:setOption(key, value)

  if applyingOptions then
    return
  end

  if autoApplyEvent then
    removeEvent(autoApplyEvent)
    autoApplyEvent = nil
  end

  autoApplyEvent = scheduleEvent(function()
    autoApplyEvent = nil
    if TempOptions:hasOptions() then
      onApplyOptions()
    end
  end, 1)
end
-- options

-- hotkeys
function resetAction(slot)
  tmpResetActions[slot] = true
end

function removeGeneralUsedHotkey(key, currentButton, chatOn)
  local generalHotkey = loadedWindows["generalHotkeys"]
  if not generalHotkey then
    return false
  end

  local panel = generalHotkey:recursiveGetChildById("hotkeyList")
  for _, widget in pairs(panel:getChildren()) do
    if key == widget.firstKey:getText() and widget ~= currentButton then
    if widget == currentButton then goto continue end

    local isFirstKey = key == widget.firstKey:getText()
    local isSecondKey = key == widget.secondKey:getText()
    if isFirstKey or isSecondKey then
      local hotkey = KeyBind:getKeyBind(widget.a, widget.o)
      widget[isFirstKey and "firstKey" or "secondKey"]:setText("")

      if hotkey then
        hotkey[isFirstKey and "setFirstKey" or "setSecondKey"]('')
        Options.removeActionHotkey(chatOn and "chatOn" or "chatOff", hotkey.jsonName, isSecondKey)
      end
    end

    :: continue ::
  end
end

end

function onHKFocusChange(widget)
  if not widget:isFocused() or not g_game.isOnline() then
    return
  end

  if lastFocusHK then
    lastFocusHK.firstKey.actionEdit:setVisible(false)
    lastFocusHK.secondKey.actionEdit:setVisible(false)
    lastFocusHK:setBackgroundColor(lastFocusHK.lastColor)
  end

  lastFocusHK = widget
  lastFocusHK.lastColor = lastFocusHK:getBackgroundColor()
  lastFocusHK:setBackgroundColor("#585858")
  lastFocusHK.firstKey.actionEdit:setVisible(true)
  lastFocusHK.secondKey.actionEdit:setVisible(true)
end

function onCFocusChange(widget)
  if not widget:isFocused() or not g_game.isOnline() then
    return
  end

  if lastFocusHK and lastFocusHK.action then
    lastFocusHK.action.actionEdit:setVisible(false)
    lastFocusHK.firstKey.actionEdit:setVisible(false)
    lastFocusHK.secondKey.actionEdit:setVisible(false)
    lastFocusHK:setBackgroundColor(lastFocusHK.lastColor)
  end

  lastFocusHK = widget
  lastFocusHK.lastColor = lastFocusHK:getBackgroundColor()
  lastFocusHK:setBackgroundColor("#585858")
  lastFocusHK.action.actionEdit:setVisible(true)
  lastFocusHK.firstKey.actionEdit:setVisible(true)
  lastFocusHK.secondKey.actionEdit:setVisible(true)
end

function updateActionWidget(id)
  local widget = actionBarHotkey[id]
  if not widget then
    return true
  end

  local modAction = modules.game_actionbar
  local action = modAction.getSettingById(id)
  widget.firstKey:setText(action.hotkey and action.hotkey or '')
end

function onChooseItemMouseRelease(self, mousePosition, mouseButton)
  local item = nil
  if mouseButton == MouseLeftButton then
    local clickedWidget = m_interface.getRootPanel():recursiveGetChildByPos(mousePosition, false)
    if clickedWidget then
      if clickedWidget:getClassName() == 'UIGameMap' then
        local tile = clickedWidget:getTile(mousePosition)
        if tile then
          local thing = tile:getTopMoveThing()
          if thing and thing:isItem() then
            item = thing
          end
        end
      elseif clickedWidget:getClassName() == 'UIItem' and not clickedWidget:isVirtual() then
        item = clickedWidget:getItem()
      end
    end
  end

  if item and item:isPickupable() then
    if assingobjectwindow then
      assingobjectwindow:destroy()
      assingobjectwindow = nil
    end

    assingobjectwindow = g_ui.createWidget('AssingObjectWindow', rootWidget)
    assingobjectwindow.cancel.onClick = function()
      if assingobjectwindow then
        assingobjectwindow:destroy()
        assingobjectwindow = nil
      end
    end
    assingobjectwindow.itemPanel.item:setItemId(item:getId())

    if item:isMultiUse() then
      assingobjectwindow.useOnYourSelf:setEnabled(true)
      assingobjectwindow.useOnTarget:setEnabled(true)
      assingobjectwindow.WithCrosshair:setEnabled(true)
    end

    if canAssignEquipItem(item) then
      assingobjectwindow.equipDequip:setEnabled(true)
    end

    if assingobjectOption then
      assingobjectOption:destroy()
      assingobjectOption = nil
    end

    assingobjectOption = UIRadioGroup.create()
    assingobjectOption:addWidget(assingobjectwindow.useOnYourSelf)
    assingobjectOption:addWidget(assingobjectwindow.useOnTarget)
    assingobjectOption:addWidget(assingobjectwindow.WithCrosshair)
    assingobjectOption:addWidget(assingobjectwindow.equipDequip)
    assingobjectOption:addWidget(assingobjectwindow.use)
    assingobjectOption:selectWidget(assingobjectwindow.use)

    assingobjectwindow.okButton.onClick = function()
      local selectId = assingobjectOption:getSelectedWidget():getId()
      local actionType = ActionTypes.USE
      if selectId == 'useOnYourSelf' then
        actionType = ActionTypes.USE_SELF
      elseif selectId == 'useOnTarget' then
        actionType = ActionTypes.USE_TARGET
      elseif selectId == 'WithCrosshair' then
        actionType = ActionTypes.USE_WITH
      elseif selectId == 'equipDequip' then
        actionType = ActionTypes.EQUIP
      else
        actionType = ActionTypes.USE
      end

      if EditActionWidget:getId() == 'actionEdit' then
        local topParent = EditActionWidget:getParent():getParent():getId()
        HotKeys[tonumber(topParent)].item = item:getId()
        HotKeys[tonumber(topParent)].action = actionType
      else
        table.insert(HotKeys, {item = item:getId(), action = actionType, text = nil})
      end

      if assingobjectwindow then
        assingobjectwindow:destroy()
        assingobjectwindow = nil
      end
    end

  else
    modules.game_textmessage.displayFailureMessage(tr('Sorry, not possible.'))
  end

  g_mouse.updateGrabber(self, 'target')
  g_mouse.popCursor('target')
  self:ungrabMouse()
  return true
end

function hotkeyIsUsed(key)
  local hotkeyList = loadedWindows["customHotkeys"]:recursiveGetChildById("hotkeyList")
  for _, child in pairs(hotkeyList:getChildren()) do
    if child.hotkey == key then
      return true
    end
  end
  return false
end

function removeCustomHotkey(key)
  local hotkeyList = loadedWindows["customHotkeys"]:recursiveGetChildById("hotkeyList")
  for _, child in pairs(hotkeyList:getChildren()) do
    if child.hotkey == key then
      g_keyboard.unbindKeyPress(child.hotkey, nil)
      g_keyboard.unbindKeyDown(child.hotkey, nil)
      Options.removeCustomHotkey(child, Options.isChatOnEnabled)
      child.hotkey = ''
      break
    end
  end
end

function resetHotkeys()
  Options.resetToDefault()
  setupProfile()
  lastFocusHK = nil
  KeyBinds:setupAndReset(Options.currentHotkeySetName, "chatOn")

  ActionHotkey.configureActionBarHotkeys()
  configureGeneralHotkeys('')
end

function resetHotkey()
  if resetWindow then
    return
  end

  optionsWindow:hide()
  g_client.setInputLockWidget(nil)

  local msg, yesCallback
  msg = 'You are about to delete all your "Custom Hotkeys" and reset all key bindings of "General Hotkeys" and "Action\n Bar Hotkeys" to their default values.\n\nTo confirm these changes, click on "Ok" below. In order to save these changes, you also need to leave the \nOptions menu by clicking on "Ok" or "Apply".'

  yesCallback = function()
    resetHotkeys()
    resetCustomHotkeys()
    optionsWindow:show()
    g_client.setInputLockWidget(optionsWindow)
    if resetWindow then
      resetWindow:destroy()
      resetWindow=nil
    end
  end

  local noCallback = function()
    resetWindow:destroy()
    resetWindow=nil
    optionsWindow:show()
    g_client.setInputLockWidget(optionsWindow)
  end

  resetWindow = displayGeneralBox(tr('Reset Options'), tr(msg), {
      { text=tr('Ok'), callback=yesCallback },
      { text=tr('Cancel'), callback=noCallback },
    }, yesCallback, noCallback)
  g_keyboard.bindKeyPress("Y", yesCallback, resetWindow)
  g_keyboard.bindKeyPress("N", noCallback, resetWindow)
end

function onTextChange(widget)
  if not assingtextwindow then
    return
  end

  if widget:getText():len() > 0 then
    assingtextwindow.okButton:setEnabled(true)
  else
    assingtextwindow.okButton:setEnabled(false)
  end
end

function onSearchHotkey(widget, parent)
  local text = widget:getText()
  if #text < 3 and #text ~= 0 then
    return
  end

  if parent == 'generalHotkeys' then
    lastFocusHK = nil
    configureGeneralHotkeys(text)
  elseif parent == 'actionHotkeys' then
    lastFocusHK = nil
    ActionHotkey.configureActionBarHotkeys(text)
  end
end

function clearSearch(parent)
  if not parent then
    return
  end
  if parent == 'generalHotkeys' then
    configureGeneralHotkeys('')
    local generalHotkey = loadedWindows["generalHotkeys"]
    if generalHotkey then
      local searchText = generalHotkey:recursiveGetChildById('searchText')
      if searchText then
        searchText:setText('')
      end
    end
  elseif parent == 'actionHotkeys' then
    local actionHotkey = loadedWindows["actionsHotkeys"]
    if actionHotkey then
      actionHotkey:recursiveGetChildById('searchText'):clearText()
    end
  end
  lastFocusHK = nil
end

function configureGeneralHotkeys(searchText)
  local generalHotkey = loadedWindows["generalHotkeys"]
  if not generalHotkey then
    return false
  end

  local panel = generalHotkey:recursiveGetChildById("hotkeyList")
  local count = 1

  panel:destroyChildren()
  local sortedActions = {}
  for action in pairs(KeyBinds.Hotkeys) do
    table.insert(sortedActions, action)
  end
  table.sort(sortedActions)

  panel.onChildFocusChange = function(self, selected) onHKFocusChange(selected) end

  local optionEscaped = searchText and string.searchEscape(searchText) or ''
  for _, action in ipairs(sortedActions) do
    local options = KeyBinds.Hotkeys[action]
    for option, info in pairs(options) do
      if optionEscaped ~= '' and (not string.find(action:lower(), optionEscaped:lower()) and not string.find(option:lower(), optionEscaped:lower())) then
        goto continue
      end

      local widget = g_ui.createWidget("HotkeysLabel", panel)
      widget:setBackgroundColor((count % 2 == 0 and '#414141' or '#484848'))
      widget.a = action
      widget.o = option

      local t = {}
      setStringColor(t, action .. ": ", "#f7f7f7")
      setStringColor(t, short_text(option, 29), "$var-text-cip-color")

      widget.action:setColoredText(t)
      widget.firstKey:setText(info.firstKey)

      if info.secondKey and info.secondKey ~= '' then
        widget.secondKey:setText(info.secondKey)
      end

      -- First key area
      widget.firstKey.actionEdit.onClick = function()
        if hotkeyAssignWindow then
          hotkeyAssignWindow:destroy()
        end

        optionsWindow:hide()
        g_client.setInputLockWidget(nil)
        local assignWindow = g_ui.createWidget('ActionAssignWindow', rootWidget)
        assignWindow:setText("Edit Hotkey for: \"" .. option .. "\"")
        assignWindow:grabKeyboard()
        assignWindow.display:setText(widget.firstKey:getText())

        local chatOn = generalHotkey:recursiveGetChildById("chatOnCheckBox"):isChecked()
        assignWindow.chatMode:setText(chatOn and "Mode: \"Chat On\"" or "Mode: \"Chat Off\"")

        assignWindow.onKeyDown = function(assignWindow, keyCode, keyboardModifiers, keyText)
          local keyCombo = determineKeyComboDesc(keyCode, keyboardModifiers, keyText)
          local resetCombo = {"Shift", "Ctrl", "Alt"}
          if table.contains(resetCombo, keyCombo) then
            assignWindow.display:setText('')
            assignWindow.warning:setVisible(false)
            assignWindow.buttonOk:setEnabled(true)
            return true
          end

          assignWindow.display:setText(keyCombo)
          assignWindow.warning:setVisible(false)
          assignWindow.buttonOk:setEnabled(true)
          if KeyBinds:hotkeyIsUsed(keyCombo) or modules.game_actionbar.isHotkeyUsedByChat(keyCombo, chatOn and "chatOn" or "chatOff") then
            assignWindow.warning:setVisible(true)
            assignWindow.warning:setText("This hotkey is already in use and will be overwritten.")
          end

          if table.contains(blockedKeys, keyCombo) then
            assignWindow.warning:setVisible(true)
            assignWindow.warning:setText("This hotkey is already in use and cannot be overwritten.")
            assignWindow.buttonOk:setEnabled(false)
          end
          return true
        end

        assignWindow:insertLuaCall("onDestroy")
        assignWindow.onDestroy = function(widget)
          if widget == hotkeyAssignWindow then
            hotkeyAssignWindow = nil
          end
        end

        assignWindow.buttonOk.onClick = function()
          local text = tostring(assignWindow.display:getText())
          if #text == 0 then
            local hotkey = KeyBind:getKeyBind(widget.a, widget.o)
            if hotkey then
              widget.firstKey:setText('')
              Options.removeActionHotkey(chatOn and "chatOn" or "chatOff", hotkey.jsonName, false)
              KeyBinds:setupAndReset(Options.currentHotkeySetName, chatOn and "chatOn" or "chatOff")
            end
            assignWindow:destroy()
            g_client.setInputLockWidget(nil)
            optionsWindow:show(true)
            g_client.setInputLockWidget(optionsWindow)
            return true
          end

          if KeyBinds:hotkeyIsUsed(text) and text ~= '' then
            local key = KeyBind:getKeyBindByHotkey(text)
            if key then
              g_keyboard.unbindKeyDown(text, nil)
              Options.removeActionHotkey(chatOn and "chatOn" or "chatOff", key.jsonName)
            end
          end

          if modules.game_actionbar.isHotkeyUsedByChat(text, chatOn and "chatOn" or "chatOff") then
            local usedButton = modules.game_actionbar.getUsedHotkeyButton(text)
            if usedButton then
              Options.removeHotkey(usedButton:getId())
              g_keyboard.unbindKeyPress(text, nil, m_interface.getRootPanel())
              g_keyboard.unbindKeyDown(text, nil, m_interface.getRootPanel())
              usedButton.cache.hotkey = nil
              modules.game_actionbar.updateButton(usedButton)
            end
          end

          CustomHotkeys.checkAndRemoveUsedHotkey(text, chatOn)
          local hotkey = KeyBind:getKeyBind(widget.a, widget.o)
          if hotkey then
            Options.updateGeneralHotkey(chatOn and "chatOn" or "chatOff", hotkey.jsonName, text)
            KeyBinds:setupAndReset(Options.currentHotkeySetName, chatOn and "chatOn" or "chatOff")
            hotkey.firstKey = text
          end

          widget.firstKey:setText(text)

          assignWindow:destroy()
          g_client.setInputLockWidget(nil)
          optionsWindow:show(true)
          g_client.setInputLockWidget(optionsWindow)
        end

        assignWindow.buttonClear.onClick = function()
          local hotkey = KeyBind:getKeyBind(widget.a, widget.o)
          if hotkey then
            widget.firstKey:setText('')
            Options.removeActionHotkey(chatOn and "chatOn" or "chatOff", hotkey.jsonName, false)
            KeyBinds:setupAndReset(Options.currentHotkeySetName, chatOn and "chatOn" or "chatOff")
          end
          assignWindow:destroy()
          g_client.setInputLockWidget(nil)
          optionsWindow:show(true)
          g_client.setInputLockWidget(optionsWindow)
        end
        hotkeyAssignWindow = assignWindow
      end

      -- Second key area
      widget.secondKey.actionEdit.onClick = function()
        if hotkeyAssignWindow then
          hotkeyAssignWindow:destroy()
        end

        optionsWindow:hide()
        g_client.setInputLockWidget(nil)
        local assignWindow = g_ui.createWidget('ActionAssignWindow', rootWidget)
        assignWindow:setText("Edit Hotkey for: \"" .. option .. "\"")
        assignWindow:grabKeyboard()
        assignWindow.display:setText(widget.secondKey:getText())

        assignWindow.onKeyDown = function(assignWindow, keyCode, keyboardModifiers, keyText)
          local keyCombo = determineKeyComboDesc(keyCode, keyboardModifiers, keyText)
          local resetCombo = {"Shift", "Ctrl", "Alt"}
          if table.contains(resetCombo, keyCombo) then
            assignWindow.display:setText('')
            assignWindow.warning:setVisible(false)
            assignWindow.buttonOk:setEnabled(true)
            return true
          end

          assignWindow.display:setText(keyCombo)
          assignWindow.warning:setVisible(false)
          assignWindow.buttonOk:setEnabled(true)
          if KeyBinds:hotkeyIsUsed(keyCombo) or modules.game_actionbar.isHotkeyUsed(keyCombo) then
            assignWindow.warning:setVisible(true)
            assignWindow.warning:setText("This hotkey is already in use and will be overwritten.")
          end

          if table.contains(blockedKeys, keyCombo) then
            assignWindow.warning:setVisible(true)
            assignWindow.warning:setText("This hotkey is already in use and cannot be overwritten.")
            assignWindow.buttonOk:setEnabled(false)
          end
          return true
        end

        local chatOn = generalHotkey:recursiveGetChildById("chatOnCheckBox"):isChecked()
        assignWindow.chatMode:setText(chatOn and "Mode: \"Chat On\"" or "Mode: \"Chat Off\"")

        assignWindow:insertLuaCall("onDestroy")
        assignWindow.onDestroy = function(widget)
          if widget == hotkeyAssignWindow then
            hotkeyAssignWindow = nil
          end
        end

        assignWindow.buttonOk.onClick = function()
          local text = tostring(assignWindow.display:getText())
          if #text == 0 then
            local hotkey = KeyBind:getKeyBind(widget.a, widget.o)
            if hotkey then
              widget.secondKey:setText('')
              Options.removeActionHotkey(chatOn and "chatOn" or "chatOff", hotkey.jsonName, false)
              KeyBinds:setupAndReset(Options.currentHotkeySetName, chatOn and "chatOn" or "chatOff")
            end
            assignWindow:destroy()
            g_client.setInputLockWidget(nil)
            optionsWindow:show(true)
            g_client.setInputLockWidget(optionsWindow)
            return true
          end

          if KeyBinds:hotkeyIsUsed(text) and text ~= '' then
            local key = KeyBind:getKeyBindByHotkey(text)
            if key then
              if key.firstKey ~= '' then
                g_keyboard.unbindKeyDown(key.firstKey, nil)
                key:setFirstKey('')
              elseif key.secondKey ~= '' then
                g_keyboard.unbindKeyDown(key.secondKey, nil)
                key:setSecondKey('')
              end
              Options.removeActionHotkey(chatOn and "chatOn" or "chatOff", key.jsonName)
            end
          end

          if info.secondKey and info.secondKey ~= "" then
            local hotkey = KeyBind:getKeyBind(widget.a, widget.o)
            if hotkey and hotkey.secondKey == info.secondKey then
              g_keyboard.unbindKeyDown(hotkey.secondKey, nil)
              hotkey:setSecondKey('')
              Options.removeActionHotkey(chatOn and "chatOn" or "chatOff", hotkey.jsonName, true)
            end
          end

          if modules.game_actionbar.isHotkeyUsed(text) then
            local usedButton = modules.game_actionbar.getUsedHotkeyButton(text)
            if usedButton then
              Options.removeHotkey(usedButton:getId())
              g_keyboard.unbindKeyPress(text, nil, m_interface.getRootPanel())
              g_keyboard.unbindKeyDown(text, nil, m_interface.getRootPanel())
              usedButton.cache.hotkey = nil
              modules.game_actionbar.updateButton(usedButton)
            end
          end

          local hotkey = KeyBind:getKeyBind(widget.a, widget.o)
          if not hotkey.firstKey or hotkey.firstKey == "" then
            hotkey:setFirstKey(text)
            Options.updateGeneralHotkey(chatOn and "chatOn" or "chatOff", hotkey.jsonName, text, false)
            widget.firstKey:setText(text)
            widget.secondKey:setText('')
          else
            widget.secondKey:setText(text)
            Options.updateGeneralHotkey(chatOn and "chatOn" or "chatOff", hotkey.jsonName, text, true)
          end

          KeyBinds:setupAndReset(Options.currentHotkeySetName, chatOn and "chatOn" or "chatOff")
          assignWindow:destroy()
          g_client.setInputLockWidget(nil)
          optionsWindow:show(true)
          g_client.setInputLockWidget(optionsWindow)
        end

        assignWindow.buttonClear.onClick = function()
          local hotkey = KeyBind:getKeyBind(widget.a, widget.o)
          if hotkey and hotkey.secondKey and hotkey.secondKey ~= '' then
            widget.secondKey:setText('')
            Options.removeActionHotkey(chatOn and "chatOn" or "chatOff", hotkey.jsonName, true)
            KeyBinds:setupAndReset(Options.currentHotkeySetName, chatOn and "chatOn" or "chatOff")
          end
          assignWindow:destroy()
          g_client.setInputLockWidget(nil)
          optionsWindow:show(true)
          g_client.setInputLockWidget(optionsWindow)
        end
        hotkeyAssignWindow = assignWindow
      end

      count = count + 1
      globalGeneralHotkey[widget.a .. "."..widget.o] = widget
      ::continue::
    end
  end
end

function getGeneralHotkeyWidget(id)
  return globalGeneralHotkey[id]
end

function autoSwitchHotkey()
  if not LoadedPlayer:isLoaded() then
    return
  end

  local shouldChange = false
  local hotkeySetName = ""
  for _, name in pairs(Options.profiles) do
    if name:lower() == LoadedPlayer:getName():lower() then
      shouldChange = true
      hotkeySetName = name
      break
    end
  end

  if not shouldChange or string.empty(hotkeySetName) then
    return
  end

  if not changeActiveHotkeyProfile(hotkeySetName) then
    return
  end

  local generalHotkey = loadedWindows["generalHotkeys"]
  local profileBar = generalHotkey:recursiveGetChildById("profile")
  profileBar:setCurrentOptionLower(LoadedPlayer:getName(), true)
end

function onSetupProfile(widget)
  widget:clear()
  for _, k in pairs(Options.profiles) do
    widget:addOption(k, nil, true)
  end
end

function refreshHotkeyProfileCombos(profileName)
  local windows = { "generalHotkeys", "actionsHotkeys", "customHotkeys" }
  for _, windowId in pairs(windows) do
    local window = loadedWindows[windowId]
    local profile = window and window:recursiveGetChildById("profile")
    if profile then
      onSetupProfile(profile)
      profile:setCurrentOption(profileName, true)
    end
  end
end

function getSelectedHotkeyChatType()
  local window = selectedWindow
  if not window or not (window:getId() == "generalHotkeys" or window:getId() == "actionsHotkeys" or window:getId() == "customHotkeys") then
    window = loadedWindows["generalHotkeys"]
  end

  local chatOn = window and window:recursiveGetChildById("chatOnCheckBox")
  local chatOff = window and window:recursiveGetChildById("chatOffCheckBox")
  if chatOn and chatOn:isChecked() then
    return "chatOn"
  end
  if chatOff and chatOff:isChecked() then
    return "chatOff"
  end
  return Options.isChatOnEnabled and "chatOn" or "chatOff"
end

function changeActiveHotkeyProfile(profileName, syncCombos)
  if not Options.changeHotkeyProfile(profileName) then
    return false
  end

  if syncCombos ~= false then
    refreshHotkeyProfileCombos(profileName)
  end

  if lastFocusHK then
    if lastFocusHK.firstKey and lastFocusHK.firstKey.actionEdit then
      lastFocusHK.firstKey.actionEdit:setVisible(false)
    end
    if lastFocusHK.lastColor then
      lastFocusHK:setBackgroundColor(lastFocusHK.lastColor)
    end
    lastFocusHK = nil
  end

  modules.game_actionbar.resetActionBar()
  KeyBinds:setupAndReset(Options.currentHotkeySetName, getSelectedHotkeyChatType())
  configureGeneralHotkeys("")
  ActionHotkey.configureActionBarHotkeys()
  CustomHotkeys.createList(true)
  return true
end

function onChangeProfile(selected)
  changeActiveHotkeyProfile(selected, false)
end

function onChatOnCheck(action)
  KeyBinds:setupAndReset(Options.currentHotkeySetName, "chatOn")
  if lastFocusHK then
    lastFocusHK.firstKey.actionEdit:setVisible(false)
    lastFocusHK:setBackgroundColor(lastFocusHK.lastColor)
    lastFocusHK = nil
  end
  if action == "General" then
    configureGeneralHotkeys("")
  elseif action == "Custom" then
    CustomHotkeys.createList()
  else
    ActionHotkey.configureActionBarHotkeys()
  end
end

function onChatOffCheck(action)
  KeyBinds:setupAndReset(Options.currentHotkeySetName, "chatOff")
  if lastFocusHK then
    lastFocusHK.firstKey.actionEdit:setVisible(false)
    lastFocusHK:setBackgroundColor(lastFocusHK.lastColor)
    lastFocusHK = nil
  end

  if action == "General" then
    configureGeneralHotkeys("")
  elseif action == "Custom" then
    CustomHotkeys.createList()
  else
    ActionHotkey.configureActionBarHotkeys()
  end
end

function setHotkeyChatMode()
  if Options.chatOptions["chatModeOn"] then
    KeyBinds:setupAndReset(Options.currentHotkeySetName, "chatOn")
  else
    KeyBinds:setupAndReset(Options.currentHotkeySetName, "chatOff")
  end
end

function setupProfile()
  local generalHotkey = loadedWindows["generalHotkeys"]
  local actionHotkey = loadedWindows["actionsHotkeys"]
  local customHotkey = loadedWindows["customHotkeys"]
  local selectedProfile = nil

  if generalHotkey:isVisible() then
    selectedProfile = generalHotkey:recursiveGetChildById('profile'):getCurrentOption()
  elseif actionHotkey:isVisible() then
    selectedProfile = actionHotkey:recursiveGetChildById('profile'):getCurrentOption()
  elseif customHotkey:isVisible() then
    selectedProfile = customHotkey:recursiveGetChildById('profile'):getCurrentOption()
  end

  if not selectedProfile then
    return
  end

  changeActiveHotkeyProfile(selectedProfile.text)
end

function toggleNextPreset()
  local currentIndex = 1
  for i, k in pairs(Options.profiles) do
    if k == Options.currentHotkeySetName then
      currentIndex = i
      break
    end
  end

  if currentIndex >= #Options.profiles then
    currentIndex = 0
  end

  local newProfile = Options.profiles[currentIndex + 1]
  if not changeActiveHotkeyProfile(newProfile) then
    return
  end
  modules.game_textmessage.displayFailureMessage(tr("Switched to hotkey preset '%s'", newProfile))
end

function togglePreviousPreset()
  local currentIndex = 1
  for i, k in pairs(Options.profiles) do
    if k == Options.currentHotkeySetName then
      currentIndex = i
      break
    end
  end

  if currentIndex == 1 then
    currentIndex = #Options.profiles
  end

  local newProfile = Options.profiles[currentIndex - 1]
  if not changeActiveHotkeyProfile(newProfile) then
    return
  end
  modules.game_textmessage.displayFailureMessage(tr("Switched to hotkey preset '%s'", newProfile))
end

function onCreateProfile(windowType)
  optionsWindow:hide()
  presetWindow = g_ui.loadUI('options/hotkeyPreset', g_ui.getRootWidget())
  g_client.setInputLockWidget(presetWindow)
  presetWindow.contentPanel.target:focus()
  presetWindow.contentPanel.okButton.onClick = function()
    local text = presetWindow.contentPanel.target:getText()
    if #text == 0 or Options.profileExist(text) then
      g_client.setInputLockWidget(nil)
      presetWindow:destroy()
      optionsWindow:show(true)
      return
    end

    Options.createProfile(text)

    refreshHotkeyProfileCombos(text)
    changeActiveHotkeyProfile(text, false)

    g_client.setInputLockWidget(nil)
    presetWindow:destroy()
    optionsWindow:show(true)
    g_client.setInputLockWidget(optionsWindow)
  end

  presetWindow.contentPanel.cancelButton.onClick = function()
    g_client.setInputLockWidget(nil)
    presetWindow:destroy()
    optionsWindow:show(true)
    g_client.setInputLockWidget(optionsWindow)
  end

  presetWindow.onEscape = function()
    g_client.setInputLockWidget(nil)
    presetWindow:destroy()
    optionsWindow:show(true)
    g_client.setInputLockWidget(optionsWindow)
  end

  presetWindow.onClose = function()
    g_client.setInputLockWidget(nil)
    presetWindow:destroy()
    optionsWindow:show(true)
    g_client.setInputLockWidget(optionsWindow)
  end
end

function onCopyProfile(windowType)
  optionsWindow:hide()
  presetWindow = g_ui.loadUI('options/hotkeyPreset', g_ui.getRootWidget())
  g_client.setInputLockWidget(presetWindow)
  presetWindow.contentPanel.target:focus()
  presetWindow:setText("Copy hotkey preset")

  local generalHotkey = nil
  if windowType == "General" then
    generalHotkey = loadedWindows["generalHotkeys"]
  elseif windowType == "ActionBar" then
    generalHotkey = loadedWindows["actionsHotkeys"]
  elseif windowType == "CustomHotkey" then
    generalHotkey = loadedWindows["customHotkeys"]
  end

  local profileBar = generalHotkey:recursiveGetChildById("profile")
  presetWindow.contentPanel.target:setText(profileBar:getCurrentOption().text)
  presetWindow.contentPanel.okButton.onClick = function()
    local text = presetWindow.contentPanel.target:getText()
    if #text == 0 or Options.profileExist(text) then
      g_client.setInputLockWidget(nil)
      presetWindow:destroy()
      optionsWindow:show(true)
      return
    end

    Options.copyProfile(text, profileBar:getCurrentOption().text)
    refreshHotkeyProfileCombos(text)
    changeActiveHotkeyProfile(text, false)

    g_client.setInputLockWidget(nil)
    presetWindow:destroy()
    optionsWindow:show(true)
    g_client.setInputLockWidget(optionsWindow)
  end

  presetWindow.onEscape = function()
    g_client.setInputLockWidget(nil)
    presetWindow:destroy()
    optionsWindow:show(true)
    g_client.setInputLockWidget(optionsWindow)
  end

  presetWindow.onClose = function()
    g_client.setInputLockWidget(nil)
    presetWindow:destroy()
    optionsWindow:show(true)
    g_client.setInputLockWidget(optionsWindow)
  end

  presetWindow.contentPanel.cancelButton.onClick = function()
    g_client.setInputLockWidget(nil)
    presetWindow:destroy()
    optionsWindow:show(true)
    g_client.setInputLockWidget(optionsWindow)
  end
end

function onRenameProfile(windowType)
  optionsWindow:hide()
  g_client.setInputLockWidget(nil)
  presetWindow = g_ui.loadUI('options/hotkeyPreset', g_ui.getRootWidget())
  presetWindow:setText("Rename hotkey preset")
  presetWindow.contentPanel.text:setImageSource("/images/optionstab/change-label")
  g_client.setInputLockWidget(presetWindow)
  presetWindow.contentPanel.target:focus()

  local generalHotkey = nil
  if windowType == "General" then
    generalHotkey = loadedWindows["generalHotkeys"]
  elseif windowType == "ActionBar" then
    generalHotkey = loadedWindows["actionsHotkeys"]
  elseif windowType == "CustomHotkey" then
    generalHotkey = loadedWindows["customHotkeys"]
  end

  local profileBar = generalHotkey:recursiveGetChildById("profile")
  presetWindow.contentPanel.target:setText(profileBar:getCurrentOption().text)
  presetWindow.contentPanel.target:setCursorPos(#profileBar:getCurrentOption().text)
  presetWindow.contentPanel.okButton.onClick = function()
    local text = presetWindow.contentPanel.target:getText()
    if #text == 0 or Options.profileExist(text) then
      g_client.setInputLockWidget(nil)
      presetWindow:destroy()
      optionsWindow:show(true)
      return
    end

    Options.renamePreset(text, profileBar:getCurrentOption().text)
    refreshHotkeyProfileCombos(text)
    changeActiveHotkeyProfile(text, false)

    g_client.setInputLockWidget(nil)
    presetWindow:destroy()
    optionsWindow:show(true)
    g_client.setInputLockWidget(optionsWindow)
  end

  presetWindow.contentPanel.cancelButton.onClick = function()
    g_client.setInputLockWidget(nil)
    presetWindow:destroy()
    optionsWindow:show(true)
    g_client.setInputLockWidget(optionsWindow)
  end

  presetWindow.onEscape = function()
    g_client.setInputLockWidget(nil)
    presetWindow:destroy()
    optionsWindow:show(true)
    g_client.setInputLockWidget(optionsWindow)
  end

  presetWindow.onClose = function()
    g_client.setInputLockWidget(nil)
    presetWindow:destroy()
    optionsWindow:show(true)
    g_client.setInputLockWidget(optionsWindow)
  end
end

function onRemoveProfile(windowType)
  if presetWindow then
    presetWindow:destroy()
  end

  if #Options.profiles == 1 then
    return true
  end

  optionsWindow:hide()
  g_client.setInputLockWidget(nil)

  local generalHotkey = nil
  if windowType == "General" then
    generalHotkey = loadedWindows["generalHotkeys"]
  elseif windowType == "ActionBar" then
    generalHotkey = loadedWindows["actionsHotkeys"]
  elseif windowType == "CustomHotkey" then
    generalHotkey = loadedWindows["customHotkeys"]
  end

  local profileBar = generalHotkey:recursiveGetChildById("profile")
  local currentProfile = profileBar:getCurrentOption().text

  local yesFunction = function()
    Options.removeProfile(currentProfile)
    local nextProfile = Options.profiles[1]
    refreshHotkeyProfileCombos(nextProfile)
    changeActiveHotkeyProfile(nextProfile, false)

    optionsWindow:show(true)
    g_client.setInputLockWidget(optionsWindow)
    presetWindow:destroy()
    presetWindow = nil
  end

  local noFunction = function()
    optionsWindow:show(true)
    g_client.setInputLockWidget(optionsWindow)
    presetWindow:destroy()
    presetWindow = nil
  end

  presetWindow = displayGeneralBox('Warning', tr("Do you really want to delete the hotkey preset '%s'?", currentProfile),
    { { text=tr('Yes'), callback=yesFunction }, { text=tr('No'), callback=noFunction }
  }, yesFunction, noFunction)
  g_client.setInputLockWidget(presetWindow)
end

function displayControlButtons()
  local activeButtons = Options.getActiveWidgets()
  local inactiveButtons = Options.getInactiveWidgets()

  local activeList = selectedWindow:recursiveGetChildById("buttonsList")
  activeList:destroyChildren()
  activeList.onChildFocusChange = onControlActiveChange

  local count = 1
  for _, id in pairs(activeButtons) do
    local label = g_ui.createWidget("ControlLabel", activeList)
    local background = count % 2 == 0 and "#484848" or "#414141"
    label:setText(ControlButtonNames[id])
    label:setId(id)
    label:setBackgroundColor(background)
    label.originalBackground = background
    label.onDoubleClick = onHideControlButton
    count = count + 1
  end

  local inactiveList = selectedWindow:recursiveGetChildById("availableButtonsList")
  inactiveList:destroyChildren()
  inactiveList.onChildFocusChange = onControlInactiveChange

  count = 1
  for _, id in pairs(inactiveButtons) do
    local label = g_ui.createWidget("ControlLabel", inactiveList)
    local background = count % 2 == 0 and "#484848" or "#414141"
    label:setText(ControlButtonNames[id])
    label:setId(id)
    label:setBackgroundColor(background)
    label.originalBackground = background
    label.onDoubleClick = onDisplayControlButton
    count = count + 1
  end

  local firstActive = activeList:getFirstChild()
  local firstInactive = inactiveList:getFirstChild()
  if firstActive then
    firstActive:focus()
  end

  if firstInactive then
    firstInactive:focus()
  end
end

function onControlActiveChange(list, focused, unfocus)
  if not unfocus then
    return
  end
  unfocus:setBackgroundColor(unfocus.originalBackground)
end

function onControlInactiveChange(list, focused, unfocus)
  if not unfocus then
    return
  end
  unfocus:setBackgroundColor(unfocus.originalBackground)
end

function onMoveControlButton(index)
  local activeList = selectedWindow:recursiveGetChildById("buttonsList")
  local widget = activeList:getFocusedChild()
  local currentIndex = activeList:getChildIndex(widget)
  local newIndex = index > 0 and (math.min(currentIndex + 1, activeList:getChildCount())) or (math.max(1, currentIndex - 1))

  activeList:moveChildToIndex(widget, newIndex)
  activeList:ensureChildVisible(widget)
end

function onHideControlButton()
  local activeList = selectedWindow:recursiveGetChildById("buttonsList")
  local inactiveList = selectedWindow:recursiveGetChildById("availableButtonsList")
  local widget = activeList:getFocusedChild()
  if not widget then
    return true
  end

  if activeList:getChildCount() <= 10 then
    modules.game_textmessage.displayFailureMessage(tr('You must have at least 10 active buttons.'))
    return true
  end

  local currentId = widget:getId()
  widget:destroy()

  local newLabel = g_ui.createWidget("ControlLabel", inactiveList)
  local background = inactiveList:getChildCount() % 2 == 0 and "#484848" or "#414141"
  newLabel:setId(currentId)
  newLabel:setText(ControlButtonNames[currentId])
  newLabel:setBackgroundColor(background)
  newLabel.originalBackground = background
  newLabel.onDoubleClick = onDisplayControlButton

  local button = selectedWindow:recursiveGetChildById("displayButton")
  if inactiveList:getChildCount() > 0 then
    button:setEnabled(true)
    button:setImageClip("60 0 20 20")
  end

  local firstActive = activeList:getFirstChild()
  local firstInactive = inactiveList:getFirstChild()
  if firstActive then
    firstActive:focus()
  end

  if firstInactive then
    firstInactive:focus()
  end
end

function onDisplayControlButton()
  local activeList = selectedWindow:recursiveGetChildById("buttonsList")
  local inactiveList = selectedWindow:recursiveGetChildById("availableButtonsList")
  local widget = inactiveList:getFocusedChild()
  if not widget then
    return true
  end

  local currentId = widget:getId()
  widget:destroy()

  local newLabel = g_ui.createWidget("ControlLabel", activeList)
  local background = activeList:getChildCount() % 2 == 0 and "#484848" or "#414141"
  newLabel:setId(currentId)
  newLabel:setText(ControlButtonNames[currentId])
  newLabel:setBackgroundColor(background)
  newLabel.originalBackground = background
  newLabel.onDoubleClick = onHideControlButton

  local button = selectedWindow:recursiveGetChildById("displayButton")
  if inactiveList:getChildCount() == 0 then
    button:setEnabled(false)
  end

  local first = inactiveList:getFirstChild()
  if first then
    first:focus()
  end
end

function checkRotateOptions(fromOk)
  local window = loadedWindows["controls"]
  if not window then
    return
  end

  local ctrlCheckBox = window:recursiveGetChildById('ctrlCheckBox')
  local shiftCheckBox = window:recursiveGetChildById('shiftCheckBox')
  local altCheckBox = window:recursiveGetChildById('altCheckBox')
  if ctrlCheckBox:isChecked() or shiftCheckBox:isChecked() or altCheckBox:isChecked() then
      return
  end

  if presetWindow then
    presetWindow:destroy()
  end

  optionsWindow:hide()
  g_client.setInputLockWidget(nil)
  local okFunction = function()
    if not fromOk then
      optionsWindow:show(true)
      g_client.setInputLockWidget(optionsWindow)
    end
    presetWindow:destroy()
    presetWindow = nil
  end

  presetWindow = displayGeneralBox('Warning', tr("Select one of the keys to rotate your character! If you do not select a key, you will not be able to manually\nrotate your character."),
    { { text=tr('Ok'), callback=okFunction }
    }, okFunction)

  presetWindow.onEscape = function()
    if not fromOk then
      optionsWindow:show(true)
    end
    presetWindow:destroy()
    presetWindow = nil
  end
end

function onApplyControlButtons()
  if selectedWindow:getId() ~= "controlButtons" then
    return true
  end

  local activeButtons = {}
  for _, widget in pairs(selectedWindow:recursiveGetChildById("buttonsList"):getChildren()) do
    table.insert(activeButtons, widget:getId())
  end

  local hideButtons = {}
  for _, widget in pairs(selectedWindow:recursiveGetChildById("availableButtonsList"):getChildren()) do
    table.insert(hideButtons, widget:getId())
  end

  Options.updateControlButtons("enabledButtons", activeButtons)
  Options.updateControlButtons("disabledButtons", hideButtons)
  Options.saveData()
  modules.game_sidebuttons.updateSideButtons()
end

function resetControl()
  if resetWindow then
    return
  end

  optionsWindow:hide()
  g_client.setInputLockWidget(nil)
  local msg, yesCallback
  msg = 'You are about to reset all options in the current section to their default value.\n\nTo confirm these changes, click on "Ok" below. In order to save these changes, you also need to leave the \nOptions menu by clicking on "Ok" or "Apply".'

  yesCallback = function()
    Options.resetControlButtons()
    displayControlButtons()
    modules.game_sidebuttons.updateSideButtons()
    optionsWindow:show(true)
    g_client.setInputLockWidget(optionsWindow)
    if resetWindow then
      resetWindow:destroy()
      resetWindow=nil
    end
  end

  local noCallback = function()
    optionsWindow:show(true)
    g_client.setInputLockWidget(optionsWindow)
    resetWindow:destroy()
    resetWindow=nil
  end

  resetWindow = displayGeneralBox(tr('Reset Options'), tr(msg), {
      { text=tr('Ok'), callback=yesCallback },
      { text=tr('Cancel'), callback=noCallback },
    }, yesCallback, noCallback)
  g_keyboard.bindKeyPress("Y", yesCallback, resetWindow)
  g_keyboard.bindKeyPress("N", noCallback, resetWindow)
end

function onExecuteAction(widget)
  if widget.lastClick and widget.lastClick > g_clock.millis() then
    return true
  end

  if m_interface.gameRightPanels:isFocusable() or m_interface.gameLeftPanels:isFocusable() then
    return true
  end

  widget.lastClick = g_clock.millis() + 150
  local player = g_game.getLocalPlayer()
  if not player then
    return true
  end

  local action = widget.actionType
  if action == 0 then
    return true
  end

  if action == "Equip" then
    local smartId = modules.game_actionbar.getSmartCast(widget.item:getItemId())
    local item = Item.create(widget.item:getItemId())
		item:setTier(widget.upgradeTier)

    if widget.smartMode then
			g_game.equipItemId(smartId, widget.upgradeTier)
		else
			local thing = g_things.getThingType(widget.item:getItemId(), ThingCategoryItem)
			local clothSlot = thing:getClothSlot()
			local hasEquipped = clothSlot > 0 and player:getEquippedItem(clothSlot) ~= 0

			if (smartId and hasEquipped) then return end

			g_game.equipItem(item)
		end
  end

  if action == "Use" then
    g_game.useInventoryItem(widget.item:getItemId())
  end

  if action == "UseOnYourself" then
    g_game.useInventoryItemWith(widget.item:getItemId(), player, widget.item:getItemSubType() or -1)
  end

  if action == "SelectUseTarget" then
    if not g_ui.getCustomInputWidget() then
      m_interface.startUseWith(widget.item:getItem(), widget.item:getItemSubType() or - 1)
    end
  end

  if action == "SmartCast" then
    local pos = g_window.getMousePosition()
    local clickedWidget = m_interface.getRootPanel():recursiveGetChildByPos(pos, false)
    if not clickedWidget or not clickedWidget:getClassName() == 'UIGameMap' then
      modules.game_textmessage.displayFailureMessage(tr('You can only perfom this action in game window.'))
      return
    end

    local tile = clickedWidget.getTile and clickedWidget:getTile(pos) or nil
    if not tile then
      modules.game_textmessage.displayFailureMessage(tr('You can only perfom this action in game window.'))
      return
    end

    local gameMapPanel = m_interface.gameMapPanel
    gameMapPanel:scheduleBlockMouseRelease(300)
    g_game.useWith(widget.item:getItem(), tile:getTopUseThing(), widget.item:getItemSubType() or -1)
  end

  if action == "UseOnTarget" then
    local attackingCreature = g_game.getAttackingCreature()
    if not attackingCreature then
      m_interface.startUseWith(widget.item:getItem(), widget.item:getItemSubType() or - 1)
    else
      g_game.useWith(widget.item:getItem(), attackingCreature, widget.item:getItemSubType() or -1)
    end
  end

  if widget.isSpell or widget.isText then
    if widget.sendAutomatic then
      if widget.isSpell then
        g_game.talk(widget.words)
      else
        modules.game_console.sendMessage(widget.words)
      end
    else
      modules.game_console.getConsole():setText(widget.words)
      modules.game_console.getConsole():setCursorPos(#widget.words)
    end
  end
end

function clearCustomHotkey(widget)
  Options.removeCustomHotkey(widget, selectedWindow:recursiveGetChildById("chatOnCheckBox"):isChecked())
  if widget.hotkey and #widget.hotkey > 0 then
    g_keyboard.unbindKeyPress(widget.hotkey, nil, m_interface.getRootPanel())
  end
  widget:destroy()
  optionsWindow:show(true)
  g_client.setInputLockWidget(optionsWindow)
end

function resetCustomHotkeys()
  local hotkeyList = loadedWindows["customHotkeys"]:recursiveGetChildById("hotkeyList")
  for _, child in pairs(hotkeyList:getChildren()) do
    if child.hotkey and #child.hotkey > 0 then
      g_keyboard.unbindKeyPress(child.hotkey, nil, m_interface.getRootPanel())
    end
    child:destroy()
  end

  Options.deleteCustomHotkeys()
end

--- Reset area
function resetControls()
  if presetWindow then
    presetWindow:destroy()
  end

  optionsWindow:hide()
  g_client.setInputLockWidget(nil)
  local yesFunction = function()
    setTempOption('hotkeyDelayNative', false)
    setTempOption('hotkeyDelay', 50)
    setTempOption('walkTurnDelay', 0)
    setTempOption('walkTeleportDelay', 0)
    setTempOption('walkStairsDelay', 0)
    setTempOption('walkFirstStepDelay', 50)
    setTempOption('walkCtrlTurnDelay', 0)
    setTempOption('smartWalk', false)
    setTempOption('ctrlCheckBox', true)
    setTempOption('shiftCheckBox', false)
    setTempOption('altCheckBox', false)
    setTempOption('ctrlDragCheckBox', false)
    setTempOption('alwaysTurnTowardsMoveDirection', true)
    onApplyOptions()
    optionsWindow:show(true)
    g_client.setInputLockWidget(optionsWindow)
    presetWindow:destroy()
    presetWindow = nil
  end

  local noFunction = function()
    optionsWindow:show(true)
    g_client.setInputLockWidget(optionsWindow)
    presetWindow:destroy()
    presetWindow = nil
  end

  presetWindow = displayGeneralBox('Reset Options', tr("Are you about to reset all options in the current section to their default value.\n\nTo confirm these changes, click on \"Ok\" below. In order to save these changes, you also need to leave the\nOptions menu by clicking on \"Ok\" or \"Apply\"."),
    { { text=tr('Ok'), callback=yesFunction }, { text=tr('Cancel'), callback=noFunction }
    }, yesFunction, noFunction)
end

function resetInterface()
  if presetWindow then
    presetWindow:destroy()
  end

  optionsWindow:hide()
  g_client.setInputLockWidget(nil)
  local yesFunction = function()
    setTempOption('highlightThingsUnderCursor', false)
    setTempOption('showRightHorizontalPanel', false)
    setTempOption('showLeftHorizontalPanel', false)
    setTempOption('colouriseLootColor', 2)
    setTempOption('timeInventory', false)
    setTempOption('timeContainers', true)
    setTempOption('timeUnnused', true)
    onApplyOptions()
    optionsWindow:show(true)
    g_client.setInputLockWidget(optionsWindow)
    presetWindow:destroy()
    presetWindow = nil
  end

  local noFunction = function()
    optionsWindow:show(true)
    g_client.setInputLockWidget(optionsWindow)
    presetWindow:destroy()
    presetWindow = nil
  end

  presetWindow = displayGeneralBox('Reset Options', tr("Are you about to reset all options in the current section to their default value.\n\nTo confirm these changes, click on \"Ok\" below. In order to save these changes, you also need to leave the\nOptions menu by clicking on \"Ok\" or \"Apply\"."),
    { { text=tr('Ok'), callback=yesFunction }, { text=tr('Cancel'), callback=noFunction }
    }, yesFunction, noFunction)
end

function resetHud()
  if presetWindow then
    presetWindow:destroy()
  end

  optionsWindow:hide()
  g_client.setInputLockWidget(nil)
  local yesFunction = function()
    setTempOption('ownHUDCharacter', true)
    setTempOption('otherHUDCreatures', true)
    setTempOption('opacityArc', 70)
    setTempOption('distanceArc', 0)
    setTempOption('showHealthManaCircle', false)
    setTempOption('customisableBars', true)
    setTempOption('statusBars', false)
    onApplyOptions()
    ConditionsHUD:reset()
    optionsWindow:show(true)
    g_client.setInputLockWidget(optionsWindow)
    presetWindow:destroy()
    presetWindow = nil
  end

  local noFunction = function()
    optionsWindow:show(true)
    g_client.setInputLockWidget(optionsWindow)
    presetWindow:destroy()
    presetWindow = nil
  end

  presetWindow = displayGeneralBox('Reset Options', tr("Are you about to reset all options in the current section to their default value.\n\nTo confirm these changes, click on \"Ok\" below. In order to save these changes, you also need to leave the\nOptions menu by clicking on \"Ok\" or \"Apply\"."),
    { { text=tr('Ok'), callback=yesFunction }, { text=tr('Cancel'), callback=noFunction }
    }, yesFunction, noFunction)
end

function resetConsole()
  if presetWindow then
    presetWindow:destroy()
  end

  optionsWindow:hide()
  g_client.setInputLockWidget(nil)
  local yesFunction = function()
    setTempOption('showInfoMessagesInConsole', true)
    setTempOption('showEventMessagesInConsole', true)
    setTempOption('showStatusMessagesInConsole', true)
    setTempOption('showStatusOthersMessagesInConsole', true)
    setTempOption('openPrivateMessageInNewTab', false)
    setTempOption('showTimestampsInConsole', true)
    setTempOption('showSecondTimestampsInConsole', false)
    setTempOption('showLevelsInConsole', true)
    onApplyOptions()
    optionsWindow:show(true)
    g_client.setInputLockWidget(optionsWindow)
    presetWindow:destroy()
    presetWindow = nil
  end

  local noFunction = function()
    optionsWindow:show(true)
    g_client.setInputLockWidget(optionsWindow)
    presetWindow:destroy()
    presetWindow = nil
  end

  presetWindow = displayGeneralBox('Reset Options', tr("Are you about to reset all options in the current section to their default value.\n\nTo confirm these changes, click on \"Ok\" below. In order to save these changes, you also need to leave the\nOptions menu by clicking on \"Ok\" or \"Apply\"."),
    { { text=tr('Ok'), callback=yesFunction }, { text=tr('Cancel'), callback=noFunction }
    }, yesFunction, noFunction)
end

function resetGameWindow()
  if presetWindow then
    presetWindow:destroy()
  end

  optionsWindow:hide()
  g_client.setInputLockWidget(nil)
  local yesFunction = function()
    setTempOption('textualEffect', true)
    setTempOption('potionSoundEffect', true)
    setTempOption('showSpells', true)
    setTempOption('spellsOthers', true)
    setTempOption('showHotkeyMessagesInConsole', true)
    setTempOption('showBoostedMessagesInConsole', true)
    setTempOption('showLootMessagesInConsole', true)
    setTempOption('showMessages', true)
    setTempOption('lootHighlight', true)
    setTempOption('storeNotification', true)
    setTempOption('showPrivateMessagesOnScreen', true)
    setTempOption('trainingProgress', true)
    setTempOption('combatFrames', true)
    setTempOption('pvpFrames', true)
    setTempOption('markTargetVisually', 1)
    onApplyOptions()
    optionsWindow:show(true)
    g_client.setInputLockWidget(optionsWindow)
    presetWindow:destroy()
    presetWindow = nil
  end

  local noFunction = function()
    optionsWindow:show(true)
    g_client.setInputLockWidget(optionsWindow)
    presetWindow:destroy()
    presetWindow = nil
  end

  presetWindow = displayGeneralBox('Reset Options', tr("Are you about to reset all options in the current section to their default value.\n\nTo confirm these changes, click on \"Ok\" below. In order to save these changes, you also need to leave the\nOptions menu by clicking on \"Ok\" or \"Apply\"."),
    { { text=tr('Ok'), callback=yesFunction }, { text=tr('Cancel'), callback=noFunction }
    }, yesFunction, noFunction)
end

function resetActionBars()
  if presetWindow then
    presetWindow:destroy()
  end

  optionsWindow:hide()
  g_client.setInputLockWidget(nil)
  local yesFunction = function()
    setTempOption('showAssignedHKButton', true)
    setTempOption('showHKObjectsBars', true)
    setTempOption('showSpellParameters', true)
    setTempOption('graphicalCooldown', true)
    setTempOption('cooldownSecond', true)
    setTempOption('actionTooltip', true)
    setTempOption('actionBarShowBottom1', true)
    setTempOption('actionBarShowBottom2', false)
    setTempOption('actionBarShowBottom3', false)
    setTempOption('actionBarShowLeft1', false)
    setTempOption('actionBarShowLeft2', false)
    setTempOption('actionBarShowLeft3', false)
    setTempOption('actionBarShowRight1', false)
    setTempOption('actionBarShowRight2', false)
    setTempOption('actionBarShowRight3', false)
    setTempOption('allActionBar13', true)
    setTempOption('allActionBar46', true)
    setTempOption('allActionBar79', true)
    onApplyOptions()
    optionsWindow:show(true)
    g_client.setInputLockWidget(optionsWindow)
    presetWindow:destroy()
    presetWindow = nil
  end

  local noFunction = function()
    optionsWindow:show(true)
    g_client.setInputLockWidget(optionsWindow)
    presetWindow:destroy()
    presetWindow = nil
  end

  presetWindow = displayGeneralBox('Reset Options', tr("Are you about to reset all options in the current section to their default value.\n\nTo confirm these changes, click on \"Ok\" below. In order to save these changes, you also need to leave the\nOptions menu by clicking on \"Ok\" or \"Apply\"."),
    { { text=tr('Ok'), callback=yesFunction }, { text=tr('Cancel'), callback=noFunction }
    }, yesFunction, noFunction)
end

function resetGraphics()
  if presetWindow then
    presetWindow:destroy()
  end

  optionsWindow:hide()
  g_client.setInputLockWidget(nil)
  local yesFunction = function()
    setTempOption('antialiasing', 2)
    setTempOption('hdmodeBox', true)
    setTempOption('fullscreen', false)
    setTempOption('dontStretchShrink', false)
    setTempOption('cacheUI', true)
    setTempOption('vsync', false)
    setTempOption('noFrameCheckBox', false)
    setTempOption('backgroundFrameRate', 100)
    onApplyOptions()
    optionsWindow:show(true)
    g_client.setInputLockWidget(optionsWindow)
    presetWindow:destroy()
    presetWindow = nil
  end

  local noFunction = function()
    optionsWindow:show(true)
    g_client.setInputLockWidget(optionsWindow)
    presetWindow:destroy()
    presetWindow = nil
  end

  presetWindow = displayGeneralBox('Reset Options', tr("Are you about to reset all options in the current section to their default value.\n\nTo confirm these changes, click on \"Ok\" below. In order to save these changes, you also need to leave the\nOptions menu by clicking on \"Ok\" or \"Apply\"."),
    { { text=tr('Ok'), callback=yesFunction }, { text=tr('Cancel'), callback=noFunction }
    }, yesFunction, noFunction)
end

function resetEffects()
  if presetWindow then
    presetWindow:destroy()
  end

  optionsWindow:hide()
  g_client.setInputLockWidget(nil)
  local yesFunction = function()
    setTempOption('enableLights', true)
    setTempOption('ambientLight', 40)
    setTempOption('stackEffects', false)
    setTempOption('maxEffects', true)
    setTempOption('limitEffects', 400)
    setTempOption('opacityEffects', 100)
    setTempOption('opacityMissile', 100)
    onApplyOptions()
    optionsWindow:show(true)
    g_client.setInputLockWidget(optionsWindow)
    presetWindow:destroy()
    presetWindow = nil
  end

  local noFunction = function()
    optionsWindow:show(true)
    g_client.setInputLockWidget(optionsWindow)
    presetWindow:destroy()
    presetWindow = nil
  end

  presetWindow = displayGeneralBox('Reset Options', tr("Are you about to reset all options in the current section to their default value.\n\nTo confirm these changes, click on \"Ok\" below. In order to save these changes, you also need to leave the\nOptions menu by clicking on \"Ok\" or \"Apply\"."),
    { { text=tr('Ok'), callback=yesFunction }, { text=tr('Cancel'), callback=noFunction }
    }, yesFunction, noFunction)
end

function repairButton(force)
  if g_game.isOnline() then
    return
  end

  if force then
    print("------------------")
    g_resources.deleteFile("/config.otml")
    g_resources.deleteFile("/quickloot.otml")
    g_resources.deleteFile("/topbar.json")
    g_resources.deleteDirectory("/characterdata/")
    g_resources.deleteDirectory("/settings/")
    g_resources.deleteDirectory("/houses/")

    closeOptions()
    scheduleEvent(function() g_app.exit() end, 1000)
    return
  end

  if resetWindow then
    return true
  end
  optionsWindow:hide()
  local logoutFunc = function()
    g_client.setInputLockWidget(nil)
    g_game.safeLogout()
    resetWindow:destroy() resetWindow = nil;
    g_resources.deleteFile("/config.otml")
    g_resources.deleteFile("/minimap.otmm")
    g_resources.deleteFile("/quickloot.otml")
    g_resources.deleteFile("/topbar.json")
    g_resources.deleteDirectory("/characterdata/")
    g_resources.deleteDirectory("/settings/")
    g_resources.deleteDirectory("/houses/")

    closeOptions()
    scheduleEvent(function() g_app.exit() end, 1000)
  end
  local cancelFunc = function() optionsWindow:show(true) g_client.setInputLockWidget(optionsWindow) resetWindow:destroy() resetWindow = nil g_client.setInputLockWidget(nil) end


  if not g_game.isOnline() then
    resetWindow = displayGeneralBox(tr('Repair Options'), tr('If you choose to restore the client, all settings will be reset.\nIf you are sure of this, click on "Repair".'),
    {
      { text=tr('Repair'), callback=logoutFunc },
      { text=tr('Cancel'), callback=cancelFunc },
    }, logoutFunc, cancelFunc)
    return
  end
  resetWindow = displayGeneralBox(tr('Repair Options'), tr("To Repair your client you need shutdown the program.\nIf you shut down the program, your character might stay in the game.\nClick on 'Logout' to ensure that you character leaves the game properly."),
  {
    { text=tr('Logout'), callback=logoutFunc },
    { text=tr('Cancel'), callback=cancelFunc },
  }, logoutFunc, cancelFunc)
end

local harmonyArc = false
function harmonyArcSide(value)
    if harmonyArc then
        return
    end

    local hudWindow = loadedWindows["hud"]
    local gameMapPanel = m_interface.getMapPanel()
    local manaCheck = hudWindow:recursiveGetChildById('harmonyMana')
    local healthCheck = hudWindow:recursiveGetChildById('harmonyHealth')
    local arcsEnabled = getTmpOption("showHealthManaCircle") or getOption("showHealthManaCircle")
    
    if not gameMapPanel then
        return
    end

    if not arcsEnabled then
        return
    end

    harmonyArc = true
    if value == "health" then
        setTempOption("harmonyArcSide", true, true) 
        healthCheck:setChecked(true)
        manaCheck:setChecked(false)
        gameMapPanel:setHarmonyLeftDraw(true)
    elseif value == "mana" then
        setTempOption("harmonyArcSide", false, true)
        healthCheck:setChecked(false)
        manaCheck:setChecked(true)
        gameMapPanel:setHarmonyLeftDraw(false)
    end

    harmonyArc = false
end

function resetScreenshotOptions()
  if presetWindow then presetWindow:destroy() end

  optionsWindow:hide()
  g_client.setInputLockWidget(nil)

  local defaultEvents = {
      screenshotLevelUp = true, screenshotSkillUp = true, screenshotAchievement = true,
      screenshotDeathPve = true, screenshotGiftOfLife = true
  }

  local function applyReset()
      for _, event in ipairs(ScreenShot.AutoScreenshotEvents) do
          local defaultValue = defaultEvents[event.settingKey] or false
          TempOptions:setOption(event.settingKey, defaultValue)
          local checkbox = GameOptions:getLoadedWindow("screenshot"):recursiveGetChildById(event.settingKey)
          if checkbox then checkbox:setChecked(defaultValue) end
      end
  end

  local yesFunction = function()
      applyReset()
      optionsWindow:show(true)
      g_client.setInputLockWidget(optionsWindow)
      presetWindow:destroy()
      presetWindow = nil
  end

  local noFunction = function()
      optionsWindow:show(true)
      g_client.setInputLockWidget(optionsWindow)
      presetWindow:destroy()
      presetWindow = nil
  end

  presetWindow = displayGeneralBox('Reset Options',
      tr("Are you about to reset all screenshot options to their default values.\n\n" ..
         "To confirm these changes, click on \"Ok\" below. In order to save these changes, " ..
         "you also need to leave the\nOptions menu by clicking on \"Ok\" or \"Apply\"."),
      {{text=tr('Ok'), callback=yesFunction}, {text=tr('Cancel'), callback=noFunction}},
      yesFunction, noFunction)
end

function onScreenShot(type)
  ScreenShot:onScreenShot(type)
end

local function refreshStatusIconBar()
  if StatusIconBar and type(StatusIconBar.refreshIcons) == 'function' then
    addEvent(function()
      StatusIconBar.refreshIcons()
    end)
  end
end

function onStatesChange(localPlayer, now, old, m_statesList, removedStates)
  ConditionsHUD:notifierStatesChange(localPlayer, now, old, m_statesList, removedStates)
  refreshStatusIconBar()
end
function onTaintsChange(localPlayer, now, old)
  ConditionsHUD:notifierTaintsChange(localPlayer, now, old)
  refreshStatusIconBar()
end
function onSkullChange(localPlayer, skull)
  ConditionsHUD:notifierSkullChange(localPlayer, skull)
  refreshStatusIconBar()
end

function onRestingAreaState(zone, state, message)
  ConditionsHUD:notifierRestingAreaState(zone, state, message)
  refreshStatusIconBar()
end

function onHungryChange(localPlayer, remove)
  ConditionsHUD:notifierHungryChange(localPlayer, remove)
  refreshStatusIconBar()
end
function onEmblemChange(localPlayer, emblem)
  ConditionsHUD:notifierEmblemChange(localPlayer, emblem)
  refreshStatusIconBar()
end
