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
-- Canonical runtime model. The widget rows in currentHotkeys are only an editor
-- for this table: they carry a keyCombo for identity and nothing else. Runtime
-- execution, ownership and serialisation all read from here, so editing a
-- hotkey takes effect immediately instead of waiting for a save to rebuild it.
local hotkeysByCombo = {}
-- combo -> { callback = <exact function>, widget = <exact widget> }. Only ever
-- holds bindings this module created, so it can never unbind another system's.
local classicBindings = {}
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

local STORAGE_VERSION = 2

-- Accepts both the versioned layout this module writes and the flat
-- combo -> settings map written by the original classic port, so an existing
-- config.otml keeps its hotkeys instead of being silently reset.
local function readStoredEntries(stored)
  if type(stored) ~= 'table' then
    return nil
  end
  if type(stored.entries) == 'table' then
    return stored.entries
  end
  return stored
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

local function normalizeCombo(keyCombo)
  if keyCombo == nil then
    return nil
  end
  keyCombo = tostring(keyCombo)
  if keyCombo == '' then
    return nil
  end
  return keyCombo
end

-- A row only owns its key once it can actually do something. The classic
-- manager creates F1-F12 and Shift+F1-F4 up front, and those blanks must stay
-- invisible to every other hotkey system: no binding, no claim.
local function isExecutableHotkey(entry)
  if not entry then
    return false
  end
  if entry.action and entry.action > 0 then
    return true
  end
  if entry.itemId and entry.itemId > 0 then
    return true
  end
  if entry.value and entry.value ~= '' then
    return true
  end
  return false
end

local function newEntry(keySettings)
  local value = keySettings and keySettings.value
  local itemId = keySettings and tonumber(keySettings.itemId) or nil
  local action = keySettings and tonumber(keySettings.action) or nil
  -- Normalise the "no action" spellings to nil. Stored data can carry a zero,
  -- and zero is truthy in Lua, so leaving it would make the row render as an
  -- action while isExecutableHotkey correctly treats it as blank.
  if itemId and itemId <= 0 then
    itemId = nil
  end
  if action and action <= 0 then
    action = nil
  end
  return {
    autoSend = keySettings and toboolean(keySettings.autoSend) or false,
    itemId = itemId,
    subType = keySettings and tonumber(keySettings.subType) or nil,
    useType = keySettings and tonumber(keySettings.useType) or nil,
    action = action,
    value = value ~= nil and tostring(value) or ''
  }
end

local function getEntry(keyCombo)
  keyCombo = normalizeCombo(keyCombo)
  return keyCombo and hotkeysByCombo[keyCombo] or nil
end

local function getLabelEntry(hotkeyLabel)
  return hotkeyLabel and getEntry(hotkeyLabel.keyCombo) or nil
end

local function unbindClassicCombo(keyCombo)
  local binding = classicBindings[keyCombo]
  if not binding then
    return false
  end
  classicBindings[keyCombo] = nil
  -- Unbind by identity: the exact callback on the exact widget it was bound to.
  g_keyboard.unbindKeyPress(keyCombo, binding.callback, binding.widget)
  return true
end

local function bindClassicCombo(keyCombo)
  if not isExecutableHotkey(hotkeysByCombo[keyCombo]) then
    return false
  end
  local widget = getGameRootPanel()
  local binding = classicBindings[keyCombo]
  if binding and binding.widget == widget then
    return false
  end
  unbindClassicCombo(keyCombo)

  local callback = function()
    doKeyCombo(keyCombo)
  end
  classicBindings[keyCombo] = { callback = callback, widget = widget }
  g_keyboard.bindKeyPress(keyCombo, callback, widget)
  return true
end

-- Brings the binding in line with the model. Returns true when ownership
-- flipped, which is the only case worth asking the modern systems to refresh.
local function reconcileClassicCombo(keyCombo)
  keyCombo = normalizeCombo(keyCombo)
  if not keyCombo then
    return false
  end
  local wasBound = classicBindings[keyCombo] ~= nil
  if not isExecutableHotkey(hotkeysByCombo[keyCombo]) then
    unbindClassicCombo(keyCombo)
    return wasBound
  end
  bindClassicCombo(keyCombo)
  return not wasBound
end

-- Asks the action bar to repaint any slot mirroring this combo. Used when the
-- content changed but ownership did not, since that case triggers no rebuild.
local function refreshClassicPreview(keyCombo)
  local actionbar = modules and modules.game_actionbar
  if actionbar and actionbar.refreshClassicHotkeyPreview then
    actionbar.refreshClassicHotkeyPreview(keyCombo)
  end
end

local function rebindAllClassicCombos()
  local combos = {}
  for keyCombo in pairs(hotkeysByCombo) do
    combos[#combos + 1] = keyCombo
  end
  for _, keyCombo in ipairs(combos) do
    reconcileClassicCombo(keyCombo)
  end
end

local function unbindAllClassicCombos()
  local combos = {}
  for keyCombo in pairs(classicBindings) do
    combos[#combos + 1] = keyCombo
  end
  for _, keyCombo in ipairs(combos) do
    unbindClassicCombo(keyCombo)
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

    -- Every subsystem above now removes only its own callbacks, so ordering is
    -- no longer load-bearing. Reconciling last is belt and braces: if a rebuild
    -- ever drops a classic binding, this puts it back instead of leaving the
    -- key dead. It only binds combos that are actually executable.
    rebindAllClassicCombos()
  end, 1)
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

  hotkeysByCombo = {}
  if not forceDefaults then
    local entries = readStoredEntries(stored)
    if entries then
      for keyCombo, keySettings in pairs(entries) do
        local combo = normalizeCombo(keyCombo)
        if combo and combo ~= 'version' and combo ~= 'entries' and type(keySettings) == 'table' then
          -- Seed the model before the row so addKeyCombo adopts it as-is.
          hotkeysByCombo[combo] = newEntry(keySettings)
          addKeyCombo(combo)
        end
      end
    end
  end

  if forceDefaults or not hasStoredProfile then
    loadDefautComboKeys()
  end
  hotkeysManagerLoaded = true
  rebindAllClassicCombos()
end

function unload()
  hotkeysManagerLoaded = false
  unbindAllClassicCombos()
  hotkeysByCombo = {}
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

  -- Serialised straight from the model, not from the widget rows. Blank rows are
  -- kept so the classic list still shows F1-F12 after a restart; they simply
  -- carry no executable action and therefore claim nothing.
  local entries = {}
  for keyCombo, entry in pairs(hotkeysByCombo) do
    entries[keyCombo] = {
      autoSend = entry.autoSend,
      itemId = entry.itemId,
      subType = entry.subType,
      useType = entry.useType,
      value = entry.value,
      action = entry.action
    }
  end
  scope.profiles[loadedProfileKey] = { version = STORAGE_VERSION, entries = entries }

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
  local entry = getLabelEntry(currentHotkeyLabel)
  if not hotkeysManagerLoaded or not entry then
    return
  end
  if (entry.action or 0) == action then
    return
  end

  if action > 0 then
    entry.action = action
    entry.itemId = nil
    entry.subType = nil
    entry.useType = nil
    entry.value = ''
    entry.autoSend = false
  else
    entry.action = nil
  end
  local ownershipChanged = reconcileClassicCombo(currentHotkeyLabel.keyCombo)
  updateHotkeyLabel(currentHotkeyLabel)
  updateHotkeyForm(true, true)
  queueSave()
  if ownershipChanged then
    refreshModernHotkeys()
  end
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

  local entry = getLabelEntry(currentHotkeyLabel)
  if item and entry then
    entry.itemId = item:getId()
    entry.subType = item:isFluidContainer() and item:getSubType() or nil
    entry.useType = item:isMultiUse() and HOTKEY_MANAGER_USEWITH or HOTKEY_MANAGER_USE
    entry.value = ''
    entry.action = nil
    entry.autoSend = false
    local ownershipChanged = reconcileClassicCombo(currentHotkeyLabel.keyCombo)
    updateHotkeyLabel(currentHotkeyLabel)
    updateHotkeyForm(true)
    queueSave()
    if ownershipChanged then
      refreshModernHotkeys()
    else
      refreshClassicPreview(currentHotkeyLabel.keyCombo)
    end
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
  local entry = getLabelEntry(currentHotkeyLabel)
  if not entry then
    return
  end
  entry.itemId = nil
  entry.subType = nil
  entry.useType = nil
  entry.autoSend = false
  entry.value = ''
  entry.action = nil
  -- The row is blank again, so the classic manager drops ownership and whatever
  -- system had the combo before can take it back on the next refresh.
  local ownershipChanged = reconcileClassicCombo(currentHotkeyLabel.keyCombo)
  updateHotkeyLabel(currentHotkeyLabel)
  updateHotkeyForm(true)
  queueSave()
  if ownershipChanged then
    refreshModernHotkeys()
  end
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
  keyCombo = normalizeCombo(keyCombo)
  if not keyCombo then
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
  -- The row holds no hotkey data of its own; the model is the only copy.
  hotkeysByCombo[keyCombo] = hotkeysByCombo[keyCombo] or newEntry(keySettings)

  updateHotkeyLabel(hotkeyLabel)
  -- A brand new row is blank, so this binds nothing. It only matters when
  -- loading stored hotkeys that already carry an action.
  reconcileClassicCombo(keyCombo)

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

  local hotkey = hotkeysByCombo[keyCombo]
  -- Defence in depth: a stale binding for a combo that has since been cleared
  -- must do nothing rather than fall through to the text branch.
  if not isExecutableHotkey(hotkey) then
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

-- Shows the spell icon next to a row whose text is a known spell, matching what
-- the custom hotkey list already does. Falls back to plain text for anything
-- else, including object hotkeys, which already describe themselves in words.
local function updateHotkeyLabelIcon(hotkeyLabel, entry)
  local icon = hotkeyLabel:getChildById('spellIcon')
  if not icon then
    return
  end

  local source, clip
  if entry and not entry.itemId and not entry.action and
      entry.value and entry.value ~= '' and Spells and Spells.getSpellIcon then
    source, clip = Spells.getSpellIcon(entry.value)
  end

  if source then
    icon:setImageSource(source)
    icon:setImageClip(clip)
    icon:setVisible(true)
    hotkeyLabel:setTextOffset('15 0')
  else
    icon:setImageSource('')
    icon:setVisible(false)
    hotkeyLabel:setTextOffset('2 0')
  end
end

function updateHotkeyLabel(hotkeyLabel)
  if not hotkeyLabel then
    return
  end
  local entry = getLabelEntry(hotkeyLabel)
  if not entry then
    return
  end

  updateHotkeyLabelIcon(hotkeyLabel, entry)

  if entry.useType == HOTKEY_MANAGER_USEONSELF then
    hotkeyLabel:setText(tr('%s: (use object on yourself)', hotkeyLabel.keyCombo))
    hotkeyLabel:setColor(HotkeyColors.itemUseSelf)
  elseif entry.useType == HOTKEY_MANAGER_USEONTARGET then
    hotkeyLabel:setText(tr('%s: (use object on target)', hotkeyLabel.keyCombo))
    hotkeyLabel:setColor(HotkeyColors.itemUseTarget)
  elseif entry.useType == HOTKEY_MANAGER_USEWITH then
    hotkeyLabel:setText(tr('%s: (use object with crosshair)', hotkeyLabel.keyCombo))
    hotkeyLabel:setColor(HotkeyColors.itemUseWith)
  elseif entry.useType == HOTKEY_MANAGER_USEATCURSOR then
    hotkeyLabel:setText(tr('%s: (use object at cursor position)', hotkeyLabel.keyCombo))
    hotkeyLabel:setColor(HotkeyColors.itemUseWith)
  elseif entry.itemId then
    hotkeyLabel:setText(tr('%s: (use object)', hotkeyLabel.keyCombo))
    hotkeyLabel:setColor(HotkeyColors.itemUse)
  elseif entry.action then
    local description = ''
    for _, action in ipairs(HotkeyActions) do
      if action.id == entry.action then
        description = action.text
        break
      end
    end
    hotkeyLabel:setText(string.format('%s: %s', hotkeyLabel.keyCombo, description))
    hotkeyLabel:setColor(HotkeyColors.action)
  else
    hotkeyLabel:setText(hotkeyLabel.keyCombo .. ': ' .. (entry.value or ''))
    hotkeyLabel:setColor(entry.autoSend and HotkeyColors.textAutoSend or HotkeyColors.text)
  end
end

function updateHotkeyForm(reset, dontUpdateCombo)
  if not hotkeysWindow then
    return
  end

  local entry = getLabelEntry(currentHotkeyLabel)
  if not entry then
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
  if entry.itemId then
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
    currentItemPreview:setItemId(entry.itemId)
    if entry.subType then
      currentItemPreview:setItemSubType(entry.subType)
    end

    local item = currentItemPreview:getItem()
    if item and item:isMultiUse() then
      useOnSelf:enable()
      useOnTarget:enable()
      useWith:enable()
      useAtCursor:enable()
      if entry.useType == HOTKEY_MANAGER_USEONSELF then
        useRadioGroup:selectWidget(useOnSelf)
      elseif entry.useType == HOTKEY_MANAGER_USEONTARGET then
        useRadioGroup:selectWidget(useOnTarget)
      elseif entry.useType == HOTKEY_MANAGER_USEWITH then
        useRadioGroup:selectWidget(useWith)
      elseif entry.useType == HOTKEY_MANAGER_USEATCURSOR then
        useRadioGroup:selectWidget(useAtCursor)
      end
    else
      useOnSelf:disable()
      useOnTarget:disable()
      useWith:disable()
      useAtCursor:disable()
      useRadioGroup:clearSelected()
    end
  elseif entry.action then
    if not dontUpdateCombo then
      hotkeyActionCombo:setCurrentOptionByData(entry.action)
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
    hotkeyText:setText(entry.value or '')
    if reset then
      hotkeyText:setCursorPos(-1)
    end
    sendAutomatically:setChecked(entry.autoSend == true)
    sendAutomatically:setEnabled(entry.value ~= nil and entry.value ~= '')
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
  unbindClassicCombo(keyCombo)
  hotkeysByCombo[keyCombo] = nil
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
  local entry = getLabelEntry(currentHotkeyLabel)
  if not hotkeysManagerLoaded or not entry then
    return
  end
  if entry.value == value then
    return
  end
  entry.value = value
  if value == '' then
    entry.autoSend = false
  end
  -- Runtime first, disk later: the key must start or stop working the moment
  -- the text changes, never on the debounced save.
  local ownershipChanged = reconcileClassicCombo(currentHotkeyLabel.keyCombo)
  updateHotkeyLabel(currentHotkeyLabel)
  updateHotkeyForm(false, true)
  queueSave()
  if ownershipChanged then
    refreshModernHotkeys()
  else
    -- Ownership is unchanged, so nothing rebuilds; repaint the mirrored slot
    -- directly or the bar would keep showing the previous spell.
    refreshClassicPreview(currentHotkeyLabel.keyCombo)
  end
end

function onSendAutomaticallyChange(autoSend)
  local entry = getLabelEntry(currentHotkeyLabel)
  if not hotkeysManagerLoaded or not entry or not entry.value or entry.value == '' then
    return
  end
  if entry.autoSend == autoSend then
    return
  end
  entry.autoSend = autoSend
  updateHotkeyLabel(currentHotkeyLabel)
  updateHotkeyForm(false, true)
  queueSave()
  -- Ownership is untouched, but a mirrored slot has to follow the change.
  refreshClassicPreview(currentHotkeyLabel.keyCombo)
end

function onChangeUseType(useTypeWidget)
  local entry = getLabelEntry(currentHotkeyLabel)
  if not hotkeysManagerLoaded or not entry then
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
  if entry.useType == useType then
    return
  end
  entry.useType = useType
  updateHotkeyLabel(currentHotkeyLabel)
  updateHotkeyForm()
  queueSave()
  -- Same combo, different use type: the mirrored slot must switch too, or a
  -- click would still cast on self after the user picked "on target".
  refreshClassicPreview(currentHotkeyLabel.keyCombo)
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

-- Public conflict contract. Other hotkey systems must consult these instead of
-- unbinding a shared combo blind.

-- True only when this manager has an action it can actually run for the combo.
-- Deliberately ignores widget rows and raw binding tables: a blank F3 row is
-- not ownership, and treating it as such is what left F3 dead.
function isComboClaimed(keyCombo)
  keyCombo = normalizeCombo(keyCombo)
  if not hotkeysManagerLoaded or not keyCombo then
    return false
  end
  return isExecutableHotkey(hotkeysByCombo[keyCombo])
end

-- Kept so older call sites keep working; same meaning as isComboClaimed now.
function isHotkeyUsedByManager(keyCombo)
  return isComboClaimed(keyCombo)
end

-- Hands a combo back to an external editor after the user explicitly chose to
-- overwrite it. Clears the classic action through the model so the UI, the
-- binding and the saved profile all agree, which a bare unbind would not do.
function releaseComboForExternalAssignment(keyCombo)
  keyCombo = normalizeCombo(keyCombo)
  local entry = keyCombo and hotkeysByCombo[keyCombo] or nil
  if not entry then
    return false
  end
  if not isExecutableHotkey(entry) then
    unbindClassicCombo(keyCombo)
    return false
  end

  entry.value = ''
  entry.autoSend = false
  entry.itemId = nil
  entry.subType = nil
  entry.useType = nil
  entry.action = nil
  unbindClassicCombo(keyCombo)

  local hotkeyLabel = currentHotkeys and currentHotkeys:getChildById(keyCombo)
  if hotkeyLabel then
    updateHotkeyLabel(hotkeyLabel)
    if currentHotkeyLabel == hotkeyLabel then
      updateHotkeyForm(true)
    end
  end
  queueSave()
  return true
end

function rebindAll()
  rebindAllClassicCombos()
end

function reloadProfile(profileName)
  if profileName and profileName ~= '' and
      Options and Options.currentHotkeySetName ~= profileName then
    return false
  end
  reload()
  refreshModernHotkeys()
  return true
end

function getComboState(keyCombo)
  keyCombo = normalizeCombo(keyCombo)
  local entry = keyCombo and hotkeysByCombo[keyCombo] or nil
  return {
    exists = entry ~= nil,
    executable = isExecutableHotkey(entry),
    bound = keyCombo ~= nil and classicBindings[keyCombo] ~= nil,
    value = entry and entry.value or nil,
    autoSend = entry and entry.autoSend or false,
    itemId = entry and entry.itemId or nil,
    subType = entry and entry.subType or nil,
    useType = entry and entry.useType or nil,
    action = entry and entry.action or nil
  }
end
