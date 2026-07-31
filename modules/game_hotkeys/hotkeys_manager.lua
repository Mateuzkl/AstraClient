HOTKEY_MANAGER_USE = nil
HOTKEY_MANAGER_USEONSELF = 1
HOTKEY_MANAGER_USEONTARGET = 2
HOTKEY_MANAGER_USEWITH = 3
HOTKEY_MANAGER_USEATCURSOR = 4

HOTKEY_ACTION_TOGGLE_WASD = 1
HOTKEY_ACTION_ATTACK_NEXT = 2
HOTKEY_ACTION_ATTACK_PREV = 3
HOTKEY_ACTION_TOGGLE_CHASE = 4

HotkeyActions = {
  { id = HOTKEY_ACTION_TOGGLE_WASD, text = tr('Toggle WASD chat mode') },
  { id = HOTKEY_ACTION_ATTACK_NEXT, text = tr('Attack next creature in battle list') },
  { id = HOTKEY_ACTION_ATTACK_PREV, text = tr('Attack previous creature in battle list') },
  { id = HOTKEY_ACTION_TOGGLE_CHASE, text = tr('Toggle chase mode') }
}

HotkeyColors = {
  text = '#888888',
  textAutoSend = '#FFFFFF',
  itemUse = '#8888FF',
  itemUseSelf = '#00FF00',
  itemUseTarget = '#FF0000',
  itemUseWith = '#F5B325',
  action = '#F97ACD'
}

local hotkeysManagerLoaded = false
local hotkeysWindow
local hotkeysWindowButton
local currentHotkeyLabel
local currentItemPreview
local addHotkeyButton
local removeHotkeyButton
local hotkeyActionCombo
local hotkeyText
local hotKeyTextLabel
local sendAutomatically
local selectObjectButton
local clearObjectButton
local useOnSelf
local useOnTarget
local useWith
local useAtCursor
local defaultComboKeys
local perServer = true
local perCharacter = true
local mouseGrabberWidget
local useRadioGroup
local currentHotkeys
local boundCombosCallback = {}
local hotkeyList = {}
local hotkeyBlockingSources = {}
local nextSourceId = 1
local lastHotkeyTime = g_clock.millis()
local saveEvent
local refreshModernHotkeysEvent
local chatTextEvent
local hotkeyAssignWindow
local choosingItem = false
local loadedServerKey
local loadedCharacterKey
local loadedProfileKey
local loadedPerServer
local loadedPerCharacter

local SETTINGS_SAVE_DELAY = 250

local function getGameRootPanel()
  if m_interface and m_interface.getRootPanel then
    return m_interface.getRootPanel()
  end
  if modules.game_interface and modules.game_interface.getRootPanel then
    return modules.game_interface.getRootPanel()
  end
  return rootWidget
end

local function encodeSettingsKey(value)
  return tostring(value):gsub('[^%w%.%- ]', function(character)
    return string.format('_%02X', string.byte(character))
  end)
end

local function getServerKey()
  local host = G and G.host or g_settings.getString('host') or 'default'
  host = tostring(host):gsub('^https?://', '')
  return encodeSettingsKey(host ~= '' and host or 'default')
end

local function getCharacterKey()
  local name = g_game.getCharacterName()
  return encodeSettingsKey(name and name ~= '' and name or 'default')
end

local function getProfileKey()
  local profile = Options and Options.currentHotkeySetName
  return encodeSettingsKey(profile and profile ~= '' and profile or 'default')
end

local function cancelSaveEvent()
  if saveEvent then
    removeEvent(saveEvent)
    saveEvent = nil
  end
end

local function cancelRefreshModernHotkeysEvent()
  if refreshModernHotkeysEvent then
    removeEvent(refreshModernHotkeysEvent)
    refreshModernHotkeysEvent = nil
  end
end

local function cancelChatTextEvent()
  if chatTextEvent then
    removeEvent(chatTextEvent)
    chatTextEvent = nil
  end
end

local function scheduleSettingsSave()
  cancelSaveEvent()
  saveEvent = scheduleEvent(function()
    saveEvent = nil
    g_settings.save()
  end, SETTINGS_SAVE_DELAY)
end

local function flushSettingsSave()
  if not saveEvent then
    return
  end
  cancelSaveEvent()
  g_settings.save()
end

local function getSettingsScope(settings, create, serverKey, characterKey, savePerServer, savePerCharacter)
  local scope = settings
  if savePerServer then
    if create then
      scope[serverKey] = type(scope[serverKey]) == 'table' and scope[serverKey] or {}
    end
    scope = type(scope) == 'table' and scope[serverKey] or nil
  end
  if savePerCharacter then
    if create and type(scope) == 'table' then
      scope[characterKey] = type(scope[characterKey]) == 'table' and scope[characterKey] or {}
    end
    scope = type(scope) == 'table' and scope[characterKey] or nil
  end
  return scope
end

local function isLegacyHotkeyTable(scope)
  if type(scope) ~= 'table' then
    return false
  end
  for key, value in pairs(scope) do
    if key ~= 'profiles' and type(value) == 'table' and
        (value.autoSend ~= nil or value.itemId ~= nil or value.useType ~= nil or
          value.value ~= nil or value.action ~= nil) then
      return true
    end
  end
  return false
end

local function cloneTable(value)
  if type(value) ~= 'table' then
    return value
  end
  local copy = {}
  for key, child in pairs(value) do
    copy[key] = cloneTable(child)
  end
  return copy
end

local function getHotkeyDelay()
  if m_settings and m_settings.getOption then
    return math.max(0, tonumber(m_settings.getOption('hotkeyDelay')) or 50)
  end
  return math.max(0, g_settings.getNumber('hotkeyDelay') or 50)
end

local function usesNativeCursor()
  return m_settings and m_settings.getOption and m_settings.getOption('nativeMouseCursor') == true
end

local function unbindComboEverywhere(keyCombo)
  local gameRootPanel = getGameRootPanel()
  local targets = { rootWidget }
  if gameRootPanel and gameRootPanel ~= rootWidget then
    targets[#targets + 1] = gameRootPanel
  end

  for _, target in ipairs(targets) do
    g_keyboard.unbindKeyPress(keyCombo, nil, target)
    g_keyboard.unbindKeyDown(keyCombo, nil, target)
    g_keyboard.unbindKeyUp(keyCombo, nil, target)
  end
end

local function refreshModernHotkeys()
  if not g_game.isOnline() then
    return
  end

  cancelRefreshModernHotkeysEvent()
  refreshModernHotkeysEvent = scheduleEvent(function()
    refreshModernHotkeysEvent = nil
    if not g_game.isOnline() then
      return
    end
    local refreshedCustomHotkeys = false
    if modules.game_actionbar and modules.game_actionbar.switchChatMode and Options then
      modules.game_actionbar.switchChatMode(Options.isChatOnEnabled == true)
      refreshedCustomHotkeys = true
    elseif KeyBinds and KeyBinds.setupAndReset and Options then
      KeyBinds:setupAndReset(Options.currentHotkeySetName,
        Options.isChatOnEnabled and 'chatOn' or 'chatOff')
    end

    if not refreshedCustomHotkeys then
      local customHotkeys = m_settings and m_settings.CustomHotkeys or
        (modules.client_settings and modules.client_settings.CustomHotkeys)
      if customHotkeys and customHotkeys.createList then
        customHotkeys.createList(true)
      end
    end
  end, 1)
end

local function bindCombo(keyCombo)
  unbindComboEverywhere(keyCombo)
  boundCombosCallback[keyCombo] = function()
    doKeyCombo(keyCombo)
  end
  g_keyboard.bindKeyPress(keyCombo, boundCombosCallback[keyCombo], getGameRootPanel())
end

function init()
  hotkeysWindow = g_ui.displayUI('hotkeys_manager')
  hotkeysWindow:hide()

  hotkeysWindowButton = modules.client_topmenu.addRightGameToggleButton(
    'hotkeysWindowButton', tr('Hotkeys') .. ' (Ctrl+K)', '/images/options/hotkeys', toggle)

  currentHotkeys = hotkeysWindow:getChildById('currentHotkeys')
  currentItemPreview = hotkeysWindow:getChildById('itemPreview')
  addHotkeyButton = hotkeysWindow:getChildById('addHotkeyButton')
  removeHotkeyButton = hotkeysWindow:getChildById('removeHotkeyButton')
  hotkeyText = hotkeysWindow:getChildById('hotkeyText')
  hotKeyTextLabel = hotkeysWindow:getChildById('hotKeyTextLabel')
  sendAutomatically = hotkeysWindow:getChildById('sendAutomatically')
  selectObjectButton = hotkeysWindow:getChildById('selectObjectButton')
  clearObjectButton = hotkeysWindow:getChildById('clearObjectButton')
  useOnSelf = hotkeysWindow:getChildById('useOnSelf')
  useOnTarget = hotkeysWindow:getChildById('useOnTarget')
  useWith = hotkeysWindow:getChildById('useWith')
  useAtCursor = hotkeysWindow:getChildById('useAtCursor')

  useRadioGroup = UIRadioGroup.create()
  useRadioGroup:addWidget(useOnSelf)
  useRadioGroup:addWidget(useOnTarget)
  useRadioGroup:addWidget(useWith)
  useRadioGroup:addWidget(useAtCursor)
  useRadioGroup.onSelectionChange = function(_, selected)
    onChangeUseType(selected)
  end

  hotkeyActionCombo = hotkeysWindow:getChildById('hotkeyActionCombo')
  hotkeyActionCombo:addOption(tr('None'), 0)
  for _, action in ipairs(HotkeyActions) do
    hotkeyActionCombo:addOption(action.text, action.id)
  end
  hotkeyActionCombo.onOptionChange = onActionChange

  mouseGrabberWidget = g_ui.createWidget('UIWidget')
  mouseGrabberWidget:setVisible(false)
  mouseGrabberWidget:setFocusable(false)
  mouseGrabberWidget.onMouseRelease = onChooseItemMouseRelease

  currentHotkeys.onChildFocusChange = function(_, hotkeyLabel)
    onSelectHotkeyLabel(hotkeyLabel)
  end
  g_keyboard.bindKeyPress('Down', function()
    currentHotkeys:focusNextChild(KeyboardFocusReason)
  end, hotkeysWindow)
  g_keyboard.bindKeyPress('Up', function()
    currentHotkeys:focusPreviousChild(KeyboardFocusReason)
  end, hotkeysWindow)

  connect(g_game, {
    onGameStart = online,
    onGameEnd = offline
  })

  load()
  if g_game.isOnline() then
    online()
  end
end

function terminate()
  disconnect(g_game, {
    onGameStart = online,
    onGameEnd = offline
  })

  if hotkeysManagerLoaded then
    save()
  else
    flushSettingsSave()
  end
  cancelRefreshModernHotkeysEvent()
  cancelChatTextEvent()

  if hotkeyAssignWindow then
    hotkeyAssignWindow:destroy()
    hotkeyAssignWindow = nil
  end
  if choosingItem and mouseGrabberWidget then
    mouseGrabberWidget:ungrabMouse()
    if usesNativeCursor() then
      g_window.restoreMouseCursor()
    else
      g_mouse.popCursor('target')
    end
    choosingItem = false
  end

  unload()

  if hotkeysWindowButton then
    hotkeysWindowButton:destroy()
    hotkeysWindowButton = nil
  end
  if hotkeysWindow then
    hotkeysWindow:destroy()
    hotkeysWindow = nil
  end
  if mouseGrabberWidget then
    mouseGrabberWidget:destroy()
    mouseGrabberWidget = nil
  end
  if useRadioGroup then
    useRadioGroup:destroy()
    useRadioGroup = nil
  end

  hotkeyActionCombo = nil
  hotKeyTextLabel = nil
  hotkeyText = nil
  sendAutomatically = nil
  selectObjectButton = nil
  clearObjectButton = nil
  addHotkeyButton = nil
  removeHotkeyButton = nil
  currentItemPreview = nil
  useOnSelf = nil
  useOnTarget = nil
  useWith = nil
  useAtCursor = nil
  currentHotkeys = nil
  clearAllHotkeyBlocks()
end

function configure(savePerServer, savePerCharacter)
  if hotkeysManagerLoaded then
    save()
  end
  perServer = savePerServer
  perCharacter = savePerCharacter
  reload()
end

function online()
  reload()
  hide()
  refreshModernHotkeys()
end

function offline()
  if hotkeysManagerLoaded then
    save()
  else
    flushSettingsSave()
  end
  cancelRefreshModernHotkeysEvent()
  cancelChatTextEvent()
  unload()
  hide()
end

function show()
  if not g_game.isOnline() or not hotkeysWindow then
    return
  end
  hotkeysWindow:show()
  hotkeysWindow:raise()
  hotkeysWindow:focus()
  if hotkeysWindowButton then
    hotkeysWindowButton:setOn(true)
  end
end

function hide()
  if hotkeysWindow then
    hotkeysWindow:hide()
  end
  if hotkeysWindowButton then
    hotkeysWindowButton:setOn(false)
  end
end

function toggle()
  if not hotkeysWindow or hotkeysWindow:isVisible() then
    hide()
  else
    show()
  end
end

function ok()
  queueSave()
  hide()
end

function cancel()
  queueSave()
  hide()
end

function load(forceDefaults)
  hotkeysManagerLoaded = false
  local settings = g_settings.getNode('game_hotkeys') or {}
  loadedServerKey = getServerKey()
  loadedCharacterKey = getCharacterKey()
  loadedProfileKey = getProfileKey()
  loadedPerServer = perServer
  loadedPerCharacter = perCharacter

  local scope = getSettingsScope(settings, false, loadedServerKey, loadedCharacterKey,
    loadedPerServer, loadedPerCharacter)
  local stored
  local hasStoredProfile = false
  if type(scope) == 'table' and type(scope.profiles) == 'table' then
    stored = scope.profiles[loadedProfileKey]
    hasStoredProfile = stored ~= nil
  elseif isLegacyHotkeyTable(scope) then
    stored = scope
    hasStoredProfile = true
  end

  hotkeyList = {}
  if not forceDefaults and type(stored) == 'table' then
    for keyCombo, keySettings in pairs(stored) do
      local combo = tostring(keyCombo)
      addKeyCombo(combo, keySettings)
      hotkeyList[combo] = keySettings
    end
  end

  if forceDefaults or not hasStoredProfile then
    loadDefautComboKeys()
  end
  hotkeysManagerLoaded = true
end

function unload()
  hotkeysManagerLoaded = false
  for keyCombo, callback in pairs(boundCombosCallback) do
    g_keyboard.unbindKeyPress(keyCombo, callback, getGameRootPanel())
  end
  boundCombosCallback = {}
  hotkeyList = {}
  currentHotkeyLabel = nil

  if currentHotkeys then
    currentHotkeys:destroyChildren()
  end
  if hotkeysWindow then
    updateHotkeyForm(true)
  end
end

function reset()
  unload()
  load(true)
  queueSave()
  refreshModernHotkeys()
end

function reload()
  unload()
  load()
end

function save(flushToDisk)
  if not currentHotkeys or not hotkeysManagerLoaded then
    return
  end

  local settings = g_settings.getNode('game_hotkeys') or {}
  local scope = getSettingsScope(settings, true, loadedServerKey, loadedCharacterKey,
    loadedPerServer, loadedPerCharacter)
  scope.profiles = type(scope.profiles) == 'table' and scope.profiles or {}
  scope.profiles[loadedProfileKey] = type(scope.profiles[loadedProfileKey]) == 'table' and
    scope.profiles[loadedProfileKey] or {}
  local stored = scope.profiles[loadedProfileKey]

  table.clear(stored)
  for _, child in ipairs(currentHotkeys:getChildren()) do
    stored[child.keyCombo] = {
      autoSend = child.autoSend,
      itemId = child.itemId,
      subType = child.subType,
      useType = child.useType,
      value = child.value,
      action = child.action
    }
  end

  hotkeyList = stored
  g_settings.setNode('game_hotkeys', settings)
  if flushToDisk ~= false then
    cancelSaveEvent()
    g_settings.save()
  end
end

function queueSave()
  if not currentHotkeys or not hotkeysManagerLoaded then
    return
  end
  save(false)
  scheduleSettingsSave()
end

function prepareProfileChange()
  if not hotkeysManagerLoaded then
    return
  end
  queueSave()
  unload()
end

function finishProfileChange()
  if not currentHotkeys or hotkeysManagerLoaded then
    return
  end
  load()
end

function copyProfile(sourceProfile, targetProfile)
  if not sourceProfile or sourceProfile == '' or not targetProfile or targetProfile == '' then
    return
  end
  if hotkeysManagerLoaded then
    save(false)
  end
  local sourceKey = encodeSettingsKey(sourceProfile)
  local targetKey = encodeSettingsKey(targetProfile)
  local settings = g_settings.getNode('game_hotkeys') or {}
  local scope = getSettingsScope(settings, true, loadedServerKey or getServerKey(),
    loadedCharacterKey or getCharacterKey(), loadedPerServer ~= false, loadedPerCharacter ~= false)
  scope.profiles = type(scope.profiles) == 'table' and scope.profiles or {}
  if type(scope.profiles[sourceKey]) == 'table' then
    scope.profiles[targetKey] = cloneTable(scope.profiles[sourceKey])
    g_settings.setNode('game_hotkeys', settings)
    scheduleSettingsSave()
  end
end

function renameProfile(sourceProfile, targetProfile)
  if not sourceProfile or sourceProfile == '' or not targetProfile or targetProfile == '' then
    return
  end
  if hotkeysManagerLoaded then
    save(false)
  end
  local sourceKey = encodeSettingsKey(sourceProfile)
  local targetKey = encodeSettingsKey(targetProfile)
  local settings = g_settings.getNode('game_hotkeys') or {}
  local scope = getSettingsScope(settings, true, loadedServerKey or getServerKey(),
    loadedCharacterKey or getCharacterKey(), loadedPerServer ~= false, loadedPerCharacter ~= false)
  scope.profiles = type(scope.profiles) == 'table' and scope.profiles or {}
  if type(scope.profiles[sourceKey]) == 'table' then
    scope.profiles[targetKey] = scope.profiles[sourceKey]
    scope.profiles[sourceKey] = nil
    if loadedProfileKey == sourceKey then
      loadedProfileKey = targetKey
    end
    g_settings.setNode('game_hotkeys', settings)
    scheduleSettingsSave()
  end
end

function removeProfile(profileName)
  if not profileName or profileName == '' then
    return
  end
  local profileKey = encodeSettingsKey(profileName)
  if hotkeysManagerLoaded and loadedProfileKey == profileKey then
    unload()
  end
  local settings = g_settings.getNode('game_hotkeys') or {}
  local scope = getSettingsScope(settings, false, loadedServerKey or getServerKey(),
    loadedCharacterKey or getCharacterKey(), loadedPerServer ~= false, loadedPerCharacter ~= false)
  if type(scope) == 'table' and type(scope.profiles) == 'table' then
    scope.profiles[profileKey] = nil
    g_settings.setNode('game_hotkeys', settings)
    scheduleSettingsSave()
  end
end

function loadDefautComboKeys()
  if defaultComboKeys then
    for keyCombo, keySettings in pairs(defaultComboKeys) do
      addKeyCombo(keyCombo, keySettings)
    end
    return
  end

  for index = 1, 12 do
    addKeyCombo('F' .. index)
  end
  for index = 1, 4 do
    addKeyCombo('Shift+F' .. index)
  end
end

function setDefaultComboKeys(combos)
  defaultComboKeys = combos
end

function onActionChange(comboBox)
  local option = comboBox:getCurrentOption()
  local action = option and option.data or 0
  if not hotkeysManagerLoaded or not currentHotkeyLabel then
    return
  end
  if (currentHotkeyLabel.action or 0) == action then
    return
  end

  if action > 0 then
    currentHotkeyLabel.action = action
    currentHotkeyLabel.itemId = nil
    currentHotkeyLabel.subType = nil
    currentHotkeyLabel.useType = nil
    currentHotkeyLabel.value = nil
    currentHotkeyLabel.autoSend = false
  else
    currentHotkeyLabel.action = nil
  end
  updateHotkeyLabel(currentHotkeyLabel)
  updateHotkeyForm(true, true)
  queueSave()
end

function onChooseItemMouseRelease(self, mousePosition, mouseButton)
  local item
  if mouseButton == MouseLeftButton then
    local clickedWidget = getGameRootPanel():recursiveGetChildByPos(mousePosition, false)
    if clickedWidget then
      if clickedWidget:getClassName() == 'UIGameMap' then
        local tile = clickedWidget:getTile(mousePosition)
        local thing = tile and tile:getTopMoveThing()
        if thing and thing:isItem() then
          item = thing
        end
      elseif clickedWidget:getClassName() == 'UIItem' and not clickedWidget:isVirtual() then
        item = clickedWidget:getItem()
      end
    end
  end

  if item and currentHotkeyLabel then
    currentHotkeyLabel.itemId = item:getId()
    currentHotkeyLabel.subType = item:isFluidContainer() and item:getSubType() or nil
    currentHotkeyLabel.useType = item:isMultiUse() and HOTKEY_MANAGER_USEWITH or HOTKEY_MANAGER_USE
    currentHotkeyLabel.value = nil
    currentHotkeyLabel.action = nil
    currentHotkeyLabel.autoSend = false
    updateHotkeyLabel(currentHotkeyLabel)
    updateHotkeyForm(true)
    queueSave()
  end

  show()
  if usesNativeCursor() then
    g_window.restoreMouseCursor()
  else
    g_mouse.popCursor('target')
  end
  self:ungrabMouse()
  choosingItem = false
  return true
end

function startChooseItem()
  if g_ui.isMouseGrabbed() then
    return
  end
  mouseGrabberWidget:grabMouse()
  if usesNativeCursor() then
    g_window.setSystemCursor('cross')
  else
    g_mouse.pushCursor('target')
  end
  choosingItem = true
  hide()
end

function clearObject()
  if not currentHotkeyLabel then
    return
  end
  currentHotkeyLabel.itemId = nil
  currentHotkeyLabel.subType = nil
  currentHotkeyLabel.useType = nil
  currentHotkeyLabel.autoSend = false
  currentHotkeyLabel.value = ''
  currentHotkeyLabel.action = nil
  updateHotkeyLabel(currentHotkeyLabel)
  updateHotkeyForm(true)
  queueSave()
end

function addHotkey()
  if hotkeyAssignWindow then
    hotkeyAssignWindow:destroy()
  end
  local assignWindow = g_ui.createWidget('HotkeyAssignWindow', rootWidget)
  hotkeyAssignWindow = assignWindow
  assignWindow:grabKeyboard()
  g_client.setInputLockWidget(assignWindow)

  assignWindow.onDestroy = function()
    g_client.setInputLockWidget(nil)
    if hotkeyAssignWindow == assignWindow then
      hotkeyAssignWindow = nil
    end
  end
  local comboLabel = assignWindow:getChildById('comboPreview')
  comboLabel.keyCombo = ''
  assignWindow.onKeyDown = hotkeyCapture
end

function addKeyCombo(keyCombo, keySettings, focus)
  if not keyCombo or keyCombo == '' then
    return
  end

  local existing = currentHotkeys:getChildById(keyCombo)
  if existing then
    if focus then
      currentHotkeys:focusChild(existing)
      currentHotkeys:ensureChildVisible(existing)
      updateHotkeyForm(true)
    end
    return existing
  end

  local hotkeyLabel = g_ui.createWidget('HotkeyListLabel')
  hotkeyLabel:setId(keyCombo)
  local children = currentHotkeys:getChildren()
  children[#children + 1] = hotkeyLabel
  table.sort(children, function(a, b)
    if a:getId():len() == b:getId():len() then
      return a:getId() < b:getId()
    end
    return a:getId():len() < b:getId():len()
  end)
  for index, child in ipairs(children) do
    if child == hotkeyLabel then
      currentHotkeys:insertChild(index, hotkeyLabel)
      break
    end
  end

  hotkeyLabel.keyCombo = keyCombo
  hotkeyLabel.autoSend = keySettings and toboolean(keySettings.autoSend) or false
  hotkeyLabel.itemId = keySettings and tonumber(keySettings.itemId) or nil
  hotkeyLabel.subType = keySettings and tonumber(keySettings.subType) or nil
  hotkeyLabel.useType = keySettings and tonumber(keySettings.useType) or nil
  hotkeyLabel.action = keySettings and tonumber(keySettings.action) or nil
  hotkeyLabel.value = keySettings and tostring(keySettings.value or '') or ''

  updateHotkeyLabel(hotkeyLabel)
  bindCombo(keyCombo)

  if focus then
    currentHotkeyLabel = hotkeyLabel
    currentHotkeys:focusChild(hotkeyLabel)
    currentHotkeys:ensureChildVisible(hotkeyLabel)
    updateHotkeyForm(true)
  end
  return hotkeyLabel
end

function doKeyCombo(keyCombo)
  if not g_game.isOnline() or not canPerformKeyCombo(keyCombo) then
    return
  end

  local hotkey = hotkeyList[keyCombo]
  if not hotkey then
    return
  end

  local now = g_clock.millis()
  if now - lastHotkeyTime < getHotkeyDelay() then
    return
  end
  lastHotkeyTime = now

  if hotkey.action then
    if hotkey.action == HOTKEY_ACTION_TOGGLE_WASD then
      modules.game_console.toggleChat()
    elseif hotkey.action == HOTKEY_ACTION_ATTACK_NEXT and modules.game_battle then
      modules.game_battle.chooseNextCreature()
    elseif hotkey.action == HOTKEY_ACTION_ATTACK_PREV and modules.game_battle then
      modules.game_battle.choosePrevCreature()
    elseif hotkey.action == HOTKEY_ACTION_TOGGLE_CHASE then
      toggleChaseMode()
    end
    return
  end

  if hotkey.itemId then
    executeHotkeyItem(hotkey.useType, hotkey.itemId, hotkey.subType)
    return
  end

  if not hotkey.value or hotkey.value == '' then
    return
  end
  if hotkey.autoSend then
    modules.game_console.sendMessage(hotkey.value)
  else
    if not modules.game_console.isChatEnabled() then
      modules.game_console.toggleChat()
    end
    local text = hotkey.value
    cancelChatTextEvent()
    chatTextEvent = scheduleEvent(function()
      chatTextEvent = nil
      if g_chat then
        g_chat:setTextEditText(text)
      end
    end, 1)
  end
end

function toggleChaseMode()
  local nextMode = g_game.getChaseMode() == ChaseOpponent and DontChase or ChaseOpponent
  g_game.setChaseMode(nextMode)
end

function executeHotkeyItem(action, itemId, subType)
  local function getUseThingUnderCursor()
    local mapPanel = m_interface and m_interface.getMapPanel and m_interface.getMapPanel()
    if not mapPanel then
      return nil
    end

    local mousePosition = g_window.getMousePosition()
    if not mapPanel:containsPoint(mousePosition) then
      return nil
    end

    local mapPosition = mapPanel:getPosition(mousePosition)
    if not mapPosition then
      return nil
    end

    local player = g_game.getLocalPlayer()
    if player and mapPosition.z ~= player:getPosition().z then
      local dz = mapPosition.z - player:getPosition().z
      mapPosition.x = mapPosition.x + dz
      mapPosition.y = mapPosition.y + dz
      mapPosition.z = player:getPosition().z
    end

    local tile = g_map.getTile(mapPosition)
    if not tile then
      return nil
    end

    local virtualItem = Item.create(itemId)
    if virtualItem:isFluidContainer() or virtualItem:isMultiUse() then
      return tile:getTopMultiUseThing()
    end
    return tile:getTopUseThing()
  end

  local function getInventoryItem()
    return g_game.findPlayerItem(itemId, subType or -1)
  end

  local function getUseItem()
    if g_game.getClientVersion() < 780 or subType then
      return getInventoryItem()
    end
    return Item.create(itemId)
  end

  if action == HOTKEY_MANAGER_USE then
    if g_game.getClientVersion() < 780 or subType then
      local item = getInventoryItem()
      if item then
        g_game.use(item)
      end
    else
      g_game.useInventoryItem(itemId)
    end
  elseif action == HOTKEY_MANAGER_USEONSELF then
    local player = g_game.getLocalPlayer()
    if g_game.getClientVersion() < 780 or subType then
      local item = getInventoryItem()
      if item and player then
        g_game.useWith(item, player)
      end
    elseif player then
      g_game.useInventoryItemWith(itemId, player)
    end
  elseif action == HOTKEY_MANAGER_USEONTARGET then
    local target = g_game.getAttackingCreature()
    if not target then
      local item = getUseItem()
      if item then
        modules.game_interface.startUseWith(item, subType)
      end
      return
    end
    if not target:getTile() then
      return
    end
    if g_game.getClientVersion() < 780 or subType then
      local item = getInventoryItem()
      if item then
        g_game.useWith(item, target)
      end
    else
      g_game.useInventoryItemWith(itemId, target)
    end
  elseif action == HOTKEY_MANAGER_USEWITH then
    local item = getUseItem()
    if item then
      modules.game_interface.startUseWith(item, subType)
    end
  elseif action == HOTKEY_MANAGER_USEATCURSOR then
    local useThing = getUseThingUnderCursor()
    if not useThing then
      local item = getUseItem()
      if item then
        modules.game_interface.startUseWith(item, subType)
      end
      return
    end
    if g_game.getClientVersion() < 780 or subType then
      local item = getInventoryItem()
      if item then
        g_game.useWith(item, useThing)
      end
    else
      g_game.useInventoryItemWith(itemId, useThing)
    end
  end
end

function updateHotkeyLabel(hotkeyLabel)
  if not hotkeyLabel then
    return
  end

  if hotkeyLabel.useType == HOTKEY_MANAGER_USEONSELF then
    hotkeyLabel:setText(tr('%s: (use object on yourself)', hotkeyLabel.keyCombo))
    hotkeyLabel:setColor(HotkeyColors.itemUseSelf)
  elseif hotkeyLabel.useType == HOTKEY_MANAGER_USEONTARGET then
    hotkeyLabel:setText(tr('%s: (use object on target)', hotkeyLabel.keyCombo))
    hotkeyLabel:setColor(HotkeyColors.itemUseTarget)
  elseif hotkeyLabel.useType == HOTKEY_MANAGER_USEWITH then
    hotkeyLabel:setText(tr('%s: (use object with crosshair)', hotkeyLabel.keyCombo))
    hotkeyLabel:setColor(HotkeyColors.itemUseWith)
  elseif hotkeyLabel.useType == HOTKEY_MANAGER_USEATCURSOR then
    hotkeyLabel:setText(tr('%s: (use object at cursor position)', hotkeyLabel.keyCombo))
    hotkeyLabel:setColor(HotkeyColors.itemUseWith)
  elseif hotkeyLabel.itemId then
    hotkeyLabel:setText(tr('%s: (use object)', hotkeyLabel.keyCombo))
    hotkeyLabel:setColor(HotkeyColors.itemUse)
  elseif hotkeyLabel.action then
    local description = ''
    for _, action in ipairs(HotkeyActions) do
      if action.id == hotkeyLabel.action then
        description = action.text
        break
      end
    end
    hotkeyLabel:setText(string.format('%s: %s', hotkeyLabel.keyCombo, description))
    hotkeyLabel:setColor(HotkeyColors.action)
  else
    hotkeyLabel:setText(hotkeyLabel.keyCombo .. ': ' .. (hotkeyLabel.value or ''))
    hotkeyLabel:setColor(hotkeyLabel.autoSend and HotkeyColors.textAutoSend or HotkeyColors.text)
  end
end

function updateHotkeyForm(reset, dontUpdateCombo)
  if not hotkeysWindow then
    return
  end

  if not currentHotkeyLabel then
    if not dontUpdateCombo then
      hotkeyActionCombo:setCurrentIndex(1)
    end
    hotkeyActionCombo:disable()
    removeHotkeyButton:disable()
    hotkeyText:disable()
    hotKeyTextLabel:disable()
    sendAutomatically:disable()
    selectObjectButton:disable()
    clearObjectButton:disable()
    useOnSelf:disable()
    useOnTarget:disable()
    useWith:disable()
    useAtCursor:disable()
    hotkeyText:clearText()
    useRadioGroup:clearSelected()
    sendAutomatically:setChecked(false)
    currentItemPreview:clearItem()
    return
  end

  removeHotkeyButton:enable()
  if currentHotkeyLabel.itemId then
    if not dontUpdateCombo then
      hotkeyActionCombo:setCurrentIndex(1)
    end
    hotkeyActionCombo:disable()
    hotkeyText:clearText()
    hotkeyText:disable()
    hotKeyTextLabel:disable()
    sendAutomatically:setChecked(false)
    sendAutomatically:disable()
    selectObjectButton:disable()
    clearObjectButton:enable()
    currentItemPreview:setItemId(currentHotkeyLabel.itemId)
    if currentHotkeyLabel.subType then
      currentItemPreview:setItemSubType(currentHotkeyLabel.subType)
    end

    local item = currentItemPreview:getItem()
    if item and item:isMultiUse() then
      useOnSelf:enable()
      useOnTarget:enable()
      useWith:enable()
      useAtCursor:enable()
      if currentHotkeyLabel.useType == HOTKEY_MANAGER_USEONSELF then
        useRadioGroup:selectWidget(useOnSelf)
      elseif currentHotkeyLabel.useType == HOTKEY_MANAGER_USEONTARGET then
        useRadioGroup:selectWidget(useOnTarget)
      elseif currentHotkeyLabel.useType == HOTKEY_MANAGER_USEWITH then
        useRadioGroup:selectWidget(useWith)
      elseif currentHotkeyLabel.useType == HOTKEY_MANAGER_USEATCURSOR then
        useRadioGroup:selectWidget(useAtCursor)
      end
    else
      useOnSelf:disable()
      useOnTarget:disable()
      useWith:disable()
      useAtCursor:disable()
      useRadioGroup:clearSelected()
    end
  elseif currentHotkeyLabel.action then
    if not dontUpdateCombo then
      hotkeyActionCombo:setCurrentOptionByData(currentHotkeyLabel.action)
    end
    hotkeyActionCombo:enable()
    hotkeyText:clearText()
    hotkeyText:disable()
    hotKeyTextLabel:disable()
    sendAutomatically:setChecked(false)
    sendAutomatically:disable()
    selectObjectButton:disable()
    clearObjectButton:disable()
    useOnSelf:disable()
    useOnTarget:disable()
    useWith:disable()
    useAtCursor:disable()
    useRadioGroup:clearSelected()
    currentItemPreview:clearItem()
  else
    if not dontUpdateCombo then
      hotkeyActionCombo:setCurrentIndex(1)
    end
    hotkeyActionCombo:enable()
    useOnSelf:disable()
    useOnTarget:disable()
    useWith:disable()
    useAtCursor:disable()
    useRadioGroup:clearSelected()
    hotkeyText:enable()
    hotKeyTextLabel:enable()
    hotkeyText:setText(currentHotkeyLabel.value or '')
    if reset then
      hotkeyText:setCursorPos(-1)
    end
    sendAutomatically:setChecked(currentHotkeyLabel.autoSend == true)
    sendAutomatically:setEnabled(currentHotkeyLabel.value and currentHotkeyLabel.value ~= '')
    selectObjectButton:enable()
    clearObjectButton:disable()
    currentItemPreview:clearItem()
  end
end

local function removeHotkeyLabel(hotkeyLabel)
  if not hotkeyLabel then
    return false
  end

  local keyCombo = hotkeyLabel.keyCombo
  local callback = boundCombosCallback[keyCombo]
  if callback then
    g_keyboard.unbindKeyPress(keyCombo, callback, getGameRootPanel())
  end
  boundCombosCallback[keyCombo] = nil
  hotkeyList[keyCombo] = nil
  if currentHotkeyLabel == hotkeyLabel then
    currentHotkeyLabel = nil
  end
  hotkeyLabel:destroy()
  updateHotkeyForm(true)
  return true
end

function removeHotkey()
  if removeHotkeyLabel(currentHotkeyLabel) then
    queueSave()
    refreshModernHotkeys()
  end
end

function onHotkeyTextChange(value)
  if not hotkeysManagerLoaded or not currentHotkeyLabel then
    return
  end
  if currentHotkeyLabel.value == value then
    return
  end
  currentHotkeyLabel.value = value
  if value == '' then
    currentHotkeyLabel.autoSend = false
  end
  updateHotkeyLabel(currentHotkeyLabel)
  updateHotkeyForm(false, true)
  queueSave()
end

function onSendAutomaticallyChange(autoSend)
  if not hotkeysManagerLoaded or not currentHotkeyLabel or
      not currentHotkeyLabel.value or currentHotkeyLabel.value == '' then
    return
  end
  if currentHotkeyLabel.autoSend == autoSend then
    return
  end
  currentHotkeyLabel.autoSend = autoSend
  updateHotkeyLabel(currentHotkeyLabel)
  updateHotkeyForm(false, true)
  queueSave()
end

function onChangeUseType(useTypeWidget)
  if not hotkeysManagerLoaded or not currentHotkeyLabel then
    return
  end
  local useType = HOTKEY_MANAGER_USE
  if useTypeWidget == useOnSelf then
    useType = HOTKEY_MANAGER_USEONSELF
  elseif useTypeWidget == useOnTarget then
    useType = HOTKEY_MANAGER_USEONTARGET
  elseif useTypeWidget == useWith then
    useType = HOTKEY_MANAGER_USEWITH
  elseif useTypeWidget == useAtCursor then
    useType = HOTKEY_MANAGER_USEATCURSOR
  end
  if currentHotkeyLabel.useType == useType then
    return
  end
  currentHotkeyLabel.useType = useType
  updateHotkeyLabel(currentHotkeyLabel)
  updateHotkeyForm()
  queueSave()
end

function onSelectHotkeyLabel(hotkeyLabel)
  currentHotkeyLabel = hotkeyLabel
  updateHotkeyForm(true)
end

function hotkeyCapture(assignWindow, keyCode, keyboardModifiers)
  local keyCombo = determineKeyComboDesc(keyCode, keyboardModifiers)
  local comboPreview = assignWindow:getChildById('comboPreview')
  comboPreview:setText(tr('Current hotkey to add: %s', keyCombo))
  comboPreview.keyCombo = keyCombo
  comboPreview:resizeToText()
  assignWindow:getChildById('addButton'):setEnabled(keyCombo ~= '')
  return true
end

function hotkeyCaptureOk(assignWindow, keyCombo)
  if not keyCombo or keyCombo == '' then
    return
  end
  addKeyCombo(keyCombo, nil, true)
  queueSave()
  refreshModernHotkeys()
  g_client.setInputLockWidget(nil)
  assignWindow:destroy()
end

function enableHotkeys(sourceId)
  if sourceId then
    hotkeyBlockingSources[sourceId] = nil
  end
end

function disableHotkeys(sourceIdentifier)
  local sourceId = sourceIdentifier or ('auto_' .. nextSourceId)
  nextSourceId = nextSourceId + 1
  hotkeyBlockingSources[sourceId] = true
  return sourceId
end

local function getCallerModule()
  local info = debug.getinfo(3, 'S')
  if not info or not info.source then
    return 'unknown'
  end
  local source = info.source:gsub('@', '')
  local moduleName = source:match('/modules/([^/]+)/') or
    source:match('\\modules\\([^\\]+)\\') or source:match('([^/\\]+)%.lua$') or 'unknown'
  return moduleName:gsub('_', '')
end

function createHotkeyBlock(sourceIdentifier)
  local callerModule = getCallerModule()
  local fullId = sourceIdentifier and (sourceIdentifier .. '_' .. callerModule) or
    ('auto_' .. callerModule .. '_' .. nextSourceId)
  local blockId = disableHotkeys(fullId)
  return {
    release = function()
      enableHotkeys(blockId)
    end,
    getId = function()
      return fullId
    end
  }
end

function areHotkeysDisabled()
  return next(hotkeyBlockingSources) ~= nil
end

function clearAllHotkeyBlocks()
  hotkeyBlockingSources = {}
end

function getHotkeyBlockingInfo()
  local sources = {}
  for sourceId in pairs(hotkeyBlockingSources) do
    sources[#sources + 1] = sourceId
  end
  table.sort(sources)
  return #sources, sources
end

function printHotkeyBlockingInfo()
  local count, sources = getHotkeyBlockingInfo()
  print('=== Hotkey Blocking Info ===')
  print('Total blocks: ' .. count)
  for index, source in ipairs(sources) do
    print('  ' .. index .. '. ' .. source)
  end
  print('============================')
end

function canPerformKeyCombo(keyCombo)
  if areHotkeysDisabled() then
    return false
  end
  if not modules.game_console.isChatEnabled() then
    return true
  end

  local platformType = g_window.getPlatformType() or ''
  if platformType:find('MACOS') then
    return keyCombo:match('Cmd%+') or keyCombo:match('Ctrl%+') or
      keyCombo:match('Alt%+') or keyCombo:match('Option%+') or keyCombo:match('F%d+')
  end
  return keyCombo:match('Ctrl%+') or keyCombo:match('Alt%+') or keyCombo:match('F%d+')
end

function removeHotkeyByCombo(keyCombo, persist)
  if not keyCombo or keyCombo == '' or not currentHotkeys then
    return false
  end
  local hotkeyLabel = currentHotkeys:getChildById(keyCombo)
  if not removeHotkeyLabel(hotkeyLabel) then
    return false
  end
  if persist ~= false then
    queueSave()
  end
  return true
end

function isHotkeyUsedByManager(keyCombo)
  if not keyCombo or keyCombo == '' then
    return false
  end
  return boundCombosCallback[keyCombo] ~= nil or
    (currentHotkeys and currentHotkeys:getChildById(keyCombo) ~= nil)
end
