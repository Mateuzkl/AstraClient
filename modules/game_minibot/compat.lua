MiniBotCompat = MiniBotCompat or {}

local rootEnvironment = _G
local OPCODE = 213
local BOTCHECK_OPCODE = 230
local BOTCHECK_SOUND = '/sounds/gm_detected.ogg'
local BOTCHECK_LOOP_INTERVAL = 3000
local MAX_SAFE_INTEGER = 9007199254740991
local MAX_TIMESTAMP = 4294967295
local MAX_DURATION = 315360000
local MAX_OBSCURED_BYTES = 2 * 1024 * 1024

local initialized = false
local opcodeRegistered = false
local botCheckOpcodeRegistered = false
local botCheckActive = false
local botCheckLoopEvent = nil
local botCheckGeneration = 0
local botCheckSoundPreloaded = false
local soundAdapterInstalled = false
local installedPlayAlarm = nil
local installedStopAlarm = nil
local consoleAdapterInstalled = false
local storeButtonAdapterInstalled = false
local thingTypeNameAdapterInstalled = false
local itemNameAdapterInstalled = false
local thingAdaptersInstalled = false
local numericTextEditBindings = setmetatable({}, { __mode = 'k' })
local scrollAreaBindings = setmetatable({}, { __mode = 'k' })
local stateReceivedAt = 0
local previous = {}

local state = {
  enabled = false,
  timeLeft = 0,
  total = 0,
  task = false,
  renewPrice = 0,
  bannedUntil = 0,
  afkPauseUntil = 0,
  afkAvailableAt = 0,
  botCheckActive = false,
  bankBalance = 0,
  inventoryBalance = 0
}

local function warn(message)
  g_logger.warning('[game_minibot/compat] ' .. tostring(message))
end

local function finiteInteger(value, minimum, maximum)
  return type(value) == 'number' and value == value and value ~= math.huge and
      value ~= -math.huge and value == math.floor(value) and value >= minimum and value <= maximum
end

local function widgetAlive(widget)
  if widget == nil then
    return false
  end

  -- Use the UI manager entry point because it receives the userdata without
  -- invoking the destroyed widget's __index metamethod.
  if g_ui ~= nil and type(g_ui.isWidgetAlive) == 'function' then
    local ok, alive = pcall(g_ui.isWidgetAlive, widget)
    return ok and alive == true
  end

  -- Compatibility fallback for a client binary that predates isWidgetAlive.
  local ok, destroyed = pcall(function()
    return widget:isDestroyed()
  end)
  return ok and not destroyed
end

local function callable(callback)
  local callbackType = type(callback)
  return callbackType == 'function' or callbackType == 'table'
end

local function marketName(thingType)
  if thingType == nil then
    return nil
  end
  if type(thingType.isMarketable) == 'function' and type(thingType.getMarketData) == 'function' then
    local marketOk, marketable = pcall(thingType.isMarketable, thingType)
    if marketOk and marketable then
      local dataOk, marketData = pcall(thingType.getMarketData, thingType)
      local marketName = dataOk and type(marketData) == 'table' and marketData.name or nil
      if type(marketName) == 'string' and marketName ~= '' then
        return marketName
      end
    end
  end

  return nil
end

local function objectId(object)
  if object == nil or type(object.getId) ~= 'function' then
    return 0
  end

  local ok, value = pcall(object.getId, object)
  return ok and (tonumber(value) or 0) or 0
end

local function nativeItemName(item)
  if type(previous.itemGetName) ~= 'function' then
    return nil
  end

  local ok, name = pcall(previous.itemGetName, item)
  return ok and type(name) == 'string' and name ~= '' and name or nil
end

-- The donor client exposes ThingType:getName(), while Astra keeps item names
-- in either the DAT market metadata or the OTB-backed Item class. Keep this
-- compatibility local to the MiniBot lifecycle so every imported page can use
-- the donor API without requiring a client binary change.
local function thingTypeName(thingType)
  local name = marketName(thingType)
  if name ~= nil then
    return name
  end

  local itemId = objectId(thingType)

  if itemId > 0 and Item ~= nil and type(Item.create) == 'function' then
    local createOk, item = pcall(Item.create, itemId, 1)
    if createOk then
      name = nativeItemName(item)
      if name ~= nil then
        return name
      end
    end
  end

  return itemId > 0 and ('Item ' .. itemId) or ''
end

-- Item:getName() exists natively, but it only reads the OTB/XML registry and
-- therefore returns an empty string when that optional data is not loaded.
-- Preserve every non-empty native name, then fall back directly to DAT market
-- metadata. This deliberately does not call ThingType:getName(), avoiding a
-- recursion loop between the two compatibility methods.
local function itemName(item)
  local name = nativeItemName(item)
  if name ~= nil then
    return name
  end

  local itemId = objectId(item)
  if itemId > 0 and g_things ~= nil and type(g_things.getThingType) == 'function' then
    local ok, thingType = pcall(g_things.getThingType, itemId, ThingCategoryItem or 0)
    if ok then
      name = marketName(thingType)
      if name ~= nil then
        return name
      end
    end
  end

  return itemId > 0 and ('Item ' .. itemId) or ''
end

local function installItemNameAdapter()
  if itemNameAdapterInstalled or Item == nil then
    return
  end

  previous.itemGetName = Item.getName
  Item.getName = itemName
  itemNameAdapterInstalled = true
end

local function restoreItemNameAdapter()
  if not itemNameAdapterInstalled then
    return
  end

  if Item ~= nil then
    Item.getName = previous.itemGetName
  end
  previous.itemGetName = nil
  itemNameAdapterInstalled = false
end

local function installThingTypeNameAdapter()
  if thingTypeNameAdapterInstalled or ThingType == nil then
    return
  end

  previous.thingTypeGetName = ThingType.getName
  if ThingType.getName == nil then
    ThingType.getName = thingTypeName
  end
  thingTypeNameAdapterInstalled = true
end

local function restoreThingTypeNameAdapter()
  if not thingTypeNameAdapterInstalled then
    return
  end

  if ThingType ~= nil then
    ThingType.getName = previous.thingTypeGetName
  end
  previous.thingTypeGetName = nil
  thingTypeNameAdapterInstalled = false
end

local function matchesKey(keyCode, ...)
  for index = 1, select('#', ...) do
    local candidate = select(index, ...)
    if candidate ~= nil and keyCode == candidate then
      return true
    end
  end
  return false
end

local function widgetStyleName(widget)
  if not widgetAlive(widget) or type(widget.getStyleName) ~= 'function' then
    return nil
  end

  local ok, styleName = pcall(widget.getStyleName, widget)
  return ok and styleName or nil
end

local function widgetClassName(widget)
  if not widgetAlive(widget) or type(widget.getClassName) ~= 'function' then
    return nil
  end

  local ok, className = pcall(widget.getClassName, widget)
  return ok and className or nil
end

local function bindNumericTextEdit(widget)
  if numericTextEditBindings[widget] ~= nil then
    return
  end

  local binding = {
    previousOnTextChange = widget.onTextChange,
    nativeFilterInstalled = false,
    normalizing = false
  }

  binding.onTextChange = function(self, text, oldText)
    if binding.normalizing then
      return
    end

    local rawText = tostring(text or '')
    local normalizedText = rawText:gsub('%D', '')
    if normalizedText ~= rawText then
      binding.normalizing = true
      local ok, err = pcall(function()
        self:setText(normalizedText)
        if type(self.setCursorPos) == 'function' then
          self:setCursorPos(-1)
        end
      end)
      binding.normalizing = false
      if not ok then
        warn('numeric TextEdit normalization failed: ' .. tostring(err))
      end
    end

    if callable(binding.previousOnTextChange) then
      return signalcall(binding.previousOnTextChange, self, normalizedText, oldText)
    end
  end

  widget.onTextChange = binding.onTextChange
  if type(widget.setValidCharacters) == 'function' then
    local ok, err = pcall(widget.setValidCharacters, widget, '0123456789')
    binding.nativeFilterInstalled = ok
    if not ok then
      warn('numeric TextEdit native filter failed: ' .. tostring(err))
    end
  end
  numericTextEditBindings[widget] = binding

  if type(widget.getText) == 'function' then
    local ok, currentText = pcall(widget.getText, widget)
    if ok and tostring(currentText or ''):find('%D') ~= nil then
      binding.onTextChange(widget, currentText, currentText)
    end
  end
end

local function releaseNumericTextEdit(widget)
  local binding = numericTextEditBindings[widget]
  if binding == nil then
    return
  end

  if widgetAlive(widget) then
    if widget.onTextChange == binding.onTextChange then
      widget.onTextChange = binding.previousOnTextChange
    end
    -- MiniBotNumericTextEdit does not declare another valid-character filter,
    -- so the empty value restores the TextEdit default for this local widget.
    if binding.nativeFilterInstalled and type(widget.setValidCharacters) == 'function' then
      local ok, err = pcall(widget.setValidCharacters, widget, '')
      if not ok then
        warn('numeric TextEdit native filter restore failed: ' .. tostring(err))
      end
    end
  end
  numericTextEditBindings[widget] = nil
end

local function dispatchListChildOnce(widget)
  if not widgetAlive(widget) then
    return false
  end

  -- The donor's list navigation dispatched both callbacks, but the local
  -- onClick bridge already forwards to onLeftClick. Prefer the semantic
  -- MiniBot callback directly so keyboard navigation cannot dispatch twice.
  local callback = widget.onLeftClick
  if not callable(callback) then
    callback = widget.onClick
  end
  if not callable(callback) then
    return false
  end

  widget.isClickFromUiScrollAreaArrow = true
  local ok, err = pcall(signalcall, callback, widget)
  widget.isClickFromUiScrollAreaArrow = nil
  if not ok then
    warn('list keyboard callback failed: ' .. tostring(err))
    return false
  end
  return true
end

local function focusedListChild(scrollArea)
  local focused = scrollArea:getFocusedChild()
  if focused ~= nil or scrollArea:getChildCount() == 0 then
    return focused
  end

  local firstChild = scrollArea:getChildByIndex(1)
  if firstChild == nil or firstChild.mask == nil then
    return nil
  end

  for _, child in ipairs(scrollArea:getChildren()) do
    if child.mask ~= nil and child.mask:isVisible() then
      return child
    end
  end
  return nil
end

local function moveListFocus(scrollArea, delta)
  local focused = focusedListChild(scrollArea)
  if focused == nil then
    return false
  end

  local index = scrollArea:getChildIndex(focused)
  if index == nil then
    return false
  end

  local targetIndex = index + delta
  if targetIndex < 1 or targetIndex > scrollArea:getChildCount() then
    return false
  end

  local neighbour = scrollArea:getChildByIndex(targetIndex)
  if neighbour == nil or neighbour.ignoreClickFromUiScrollAreaArrow then
    return false
  end

  neighbour:focus()
  dispatchListChildOnce(neighbour)
  if widgetAlive(scrollArea) and widgetAlive(neighbour) then
    scrollArea:ensureChildVisible(neighbour)
  end
  return true
end

local function bindScrollAreaNavigation(scrollArea)
  if scrollAreaBindings[scrollArea] ~= nil then
    return
  end

  local binding = {
    previousOnArrowDown = scrollArea.onArrowDown,
    previousOnArrowUp = scrollArea.onArrowUp,
    previousOnKeyDown = scrollArea.onKeyDown
  }

  binding.onArrowUp = function(self)
    return moveListFocus(self, -1)
  end

  binding.onArrowDown = function(self)
    return moveListFocus(self, 1)
  end

  binding.onKeyDown = function(self, keyCode, keyboardModifiers)
    if keyboardModifiers == KeyboardNoModifier then
      if matchesKey(keyCode, KeyEnter, rawget(rootEnvironment, 'KeyNumEnter'),
            rawget(rootEnvironment, 'KeyNumpadEnter')) then
        if callable(self.onEnter) then
          signalcall(self.onEnter, self)
          return true
        end
      elseif keyCode == KeyEscape then
        if callable(self.onEscape) then
          signalcall(self.onEscape, self)
          return true
        end
      elseif matchesKey(keyCode, KeyDown, rawget(rootEnvironment, 'KeyNumpadDown'),
            rawget(rootEnvironment, 'KeyNumpad2')) then
        signalcall(self.onArrowDown, self)
        return true
      elseif matchesKey(keyCode, KeyUp, rawget(rootEnvironment, 'KeyNumpadUp'),
            rawget(rootEnvironment, 'KeyNumpad8')) then
        signalcall(self.onArrowUp, self)
        return true
      end
    end

    if callable(binding.previousOnKeyDown) then
      return signalcall(binding.previousOnKeyDown, self, keyCode, keyboardModifiers)
    end
  end

  scrollArea.onArrowUp = binding.onArrowUp
  scrollArea.onArrowDown = binding.onArrowDown
  scrollArea.onKeyDown = binding.onKeyDown
  scrollAreaBindings[scrollArea] = binding
end

local function releaseScrollAreaNavigation(scrollArea)
  local binding = scrollAreaBindings[scrollArea]
  if binding == nil then
    return
  end

  if widgetAlive(scrollArea) then
    if scrollArea.onArrowUp == binding.onArrowUp then
      scrollArea.onArrowUp = binding.previousOnArrowUp
    end
    if scrollArea.onArrowDown == binding.onArrowDown then
      scrollArea.onArrowDown = binding.previousOnArrowDown
    end
    if scrollArea.onKeyDown == binding.onKeyDown then
      scrollArea.onKeyDown = binding.previousOnKeyDown
    end
  end
  scrollAreaBindings[scrollArea] = nil
end

local function prepareWidgetTree(widget)
  if not widgetAlive(widget) then
    return
  end

  local styleName = widgetStyleName(widget)
  if styleName == 'MiniBotNumericTextEdit' then
    bindNumericTextEdit(widget)
  end

  if styleName == 'ScrollablePanel' or widgetClassName(widget) == 'UIScrollArea' then
    bindScrollAreaNavigation(widget)
  end

  for _, child in ipairs(widget:getChildren()) do
    prepareWidgetTree(child)
  end
end

local function releaseWidgetTree(widget)
  if not widgetAlive(widget) then
    return
  end

  for _, child in ipairs(widget:getChildren()) do
    releaseWidgetTree(child)
  end
  releaseNumericTextEdit(widget)
  releaseScrollAreaNavigation(widget)
end

local function restoreLocalWidgetBindings()
  -- The registry keys are C++ userdata. After the UI manager destroys a page,
  -- Lua may still retain a weak key whose native object can no longer be
  -- indexed at all; even probing isDestroyed then raises a fatal C++ error
  -- that is not recoverable by pcall. Live trees are restored explicitly by
  -- releaseWidgetTree before destruction, so final teardown must only discard
  -- any stale bookkeeping without touching its keys.
  numericTextEditBindings = setmetatable({}, { __mode = 'k' })
  scrollAreaBindings = setmetatable({}, { __mode = 'k' })
end

function MiniBotCompat.prepareWidgetTree(widget)
  prepareWidgetTree(widget)
end

function MiniBotCompat.releaseWidgetTree(widget)
  releaseWidgetTree(widget)
end

local function getAlarmChannel()
  if g_sounds == nil or type(g_sounds.getChannel) ~= 'function' then
    return nil
  end
  return g_sounds.getChannel((SoundChannels and SoundChannels.Bot) or 4)
end

local function installSoundAdapter()
  if soundAdapterInstalled or g_sounds == nil then
    return
  end

  previous.playAlarm = g_sounds.playAlarm
  previous.stopAlarm = g_sounds.stopAlarm

  if type(g_sounds.playAlarm) ~= 'function' then
    installedPlayAlarm = function(file)
      local channel = getAlarmChannel()
      if channel ~= nil then
        if type(channel.setEnabled) == 'function' then
          channel:setEnabled(true)
        end
        if type(channel.stop) == 'function' then
          channel:stop(0)
        end
        if type(channel.play) == 'function' then
          return channel:play(file, 0, 1.0)
        end
      end
      if type(g_sounds.play) == 'function' then
        return g_sounds.play(file, 0, 1.0)
      end
      return false
    end
    g_sounds.playAlarm = installedPlayAlarm
  end

  if type(g_sounds.stopAlarm) ~= 'function' then
    installedStopAlarm = function()
      local channel = getAlarmChannel()
      if channel ~= nil and type(channel.stop) == 'function' then
        return channel:stop(0)
      end
      return false
    end
    g_sounds.stopAlarm = installedStopAlarm
  end

  soundAdapterInstalled = true
end

local function restoreSoundAdapter()
  if not soundAdapterInstalled or g_sounds == nil then
    return
  end
  if installedPlayAlarm ~= nil and g_sounds.playAlarm == installedPlayAlarm then
    g_sounds.playAlarm = previous.playAlarm
  end
  if installedStopAlarm ~= nil and g_sounds.stopAlarm == installedStopAlarm then
    g_sounds.stopAlarm = previous.stopAlarm
  end
  installedPlayAlarm = nil
  installedStopAlarm = nil
  soundAdapterInstalled = false
end

local function cancelBotCheckLoop()
  if botCheckLoopEvent ~= nil then
    if type(removeEvent) == 'function' then
      local ok, err = pcall(removeEvent, botCheckLoopEvent)
      if not ok then
        warn('failed to cancel bot-check alarm event: ' .. tostring(err))
      end
    end
    botCheckLoopEvent = nil
  end
end

local function ensureBotCheckSoundPreloaded()
  if botCheckSoundPreloaded or g_sounds == nil or type(g_sounds.preload) ~= 'function' then
    return
  end

  local ok, err = pcall(function()
    g_sounds.preload(BOTCHECK_SOUND)
  end)
  if ok then
    botCheckSoundPreloaded = true
  else
    warn('failed to preload bot-check alarm: ' .. tostring(err))
  end
end

local function playBotCheckSound()
  if not botCheckActive or g_sounds == nil or type(g_sounds.playAlarm) ~= 'function' then
    return
  end

  ensureBotCheckSoundPreloaded()
  local ok, err = pcall(function()
    g_sounds.playAlarm(BOTCHECK_SOUND)
  end)
  if not ok then
    warn('failed to play bot-check alarm: ' .. tostring(err))
  end
end

local function scheduleBotCheckLoop(generation)
  if not botCheckActive or generation ~= botCheckGeneration or type(scheduleEvent) ~= 'function' then
    return
  end

  local ok, eventOrError = pcall(function()
    return scheduleEvent(function()
      if not botCheckActive or generation ~= botCheckGeneration then
        return
      end
      botCheckLoopEvent = nil
      playBotCheckSound()
      scheduleBotCheckLoop(generation)
    end, BOTCHECK_LOOP_INTERVAL)
  end)
  if ok then
    botCheckLoopEvent = eventOrError
  else
    warn('failed to schedule bot-check alarm: ' .. tostring(eventOrError))
  end
end

local function flashBotCheckWindow()
  if g_window == nil then
    return
  end

  local ok, err
  if type(g_window.flash) == 'function' then
    ok, err = pcall(function()
      g_window.flash()
    end)
  elseif type(g_window.flashWindow) == 'function' then
    ok, err = pcall(function()
      g_window.flashWindow(0)
    end)
  else
    return
  end

  if not ok then
    warn('failed to flash window for bot-check alarm: ' .. tostring(err))
  end
end

local function disableBotCheckAutomation()
  local miniBotModule = modules and modules.game_minibot
  if miniBotModule ~= nil and
      type(miniBotModule.getPressetSettings) == 'function' and
      type(miniBotModule.setPressetSettings) == 'function' and
      type(miniBotModule.disableMovementShortcut) == 'function' then
    local ok, err = pcall(function()
      local settings = miniBotModule.getPressetSettings()
      miniBotModule.disableMovementShortcut(settings, 5)
      miniBotModule.disableMovementShortcut(settings, 21)
      miniBotModule.setPressetSettings(settings)
    end)
    if not ok then
      warn('failed to persist disabled movement shortcuts for bot-check alarm: ' .. tostring(err))
    end
  end

  if miniBotModule ~= nil and type(miniBotModule.onMiniBotGameWindowChangeFromPanel) == 'function' then
    local ok, err = pcall(function()
      miniBotModule.onMiniBotGameWindowChangeFromPanel('huntingRecorder_gamewindow', false)
      miniBotModule.onMiniBotGameWindowChangeFromPanel('huntingExplorer_gamewindow', false)
      miniBotModule.onMiniBotGameWindowChangeFromPanel('combat_gamewindow', false)
    end)
    if not ok then
      warn('failed to synchronize bot-check state with MiniBot controls: ' .. tostring(err))
    end
  end

  if miniBotModule ~= nil and type(miniBotModule.syncDisabledMovementAutomationWidgets) == 'function' then
    local ok, err = pcall(miniBotModule.syncDisabledMovementAutomationWidgets)
    if not ok then
      warn('failed to synchronize bot-check movement widgets: ' .. tostring(err))
    end
  end

  if g_minibot ~= nil then
    if type(g_minibot.setModuleToggle) == 'function' then
      local ok, err = pcall(function()
        g_minibot.setModuleToggle(5, false)
        g_minibot.setModuleToggle(21, false)
      end)
      if not ok then
        warn('failed to disable cavebot for bot-check alarm: ' .. tostring(err))
      end
    end
    if type(g_minibot.setAutoAttack) == 'function' then
      local ok, err = pcall(function()
        g_minibot.setAutoAttack(0)
      end)
      if not ok then
        warn('failed to disable auto-attack for bot-check alarm: ' .. tostring(err))
      end
    end
  end

  if g_game ~= nil and type(g_game.cancelAttack) == 'function' then
    local ok, err = pcall(function()
      g_game.cancelAttack()
    end)
    if not ok then
      warn('failed to cancel the current attack for bot-check alarm: ' .. tostring(err))
    end
  end
end

local function synchronizeAuthoritativeCavebotDisabled()
  local miniBotModule = modules and modules.game_minibot
  if miniBotModule ~= nil and
      type(miniBotModule.getPressetSettings) == 'function' and
      type(miniBotModule.setPressetSettings) == 'function' and
      type(miniBotModule.disableMovementShortcut) == 'function' then
    local ok, err = pcall(function()
      local settings = miniBotModule.getPressetSettings()
      miniBotModule.disableMovementShortcut(settings, 5)
      miniBotModule.setPressetSettings(settings)
    end)
    if not ok then
      warn('failed to persist authoritative cavebot shutdown: ' .. tostring(err))
    end
  end

  if miniBotModule ~= nil and type(miniBotModule.syncDisabledMovementAutomationWidgets) == 'function' then
    local ok, err = pcall(miniBotModule.syncDisabledMovementAutomationWidgets, 5)
    if not ok then
      warn('failed to synchronize authoritative cavebot shutdown: ' .. tostring(err))
    end
  end
end

local function startBotCheckAlarm()
  botCheckActive = true
  botCheckGeneration = botCheckGeneration + 1
  cancelBotCheckLoop()

  -- The alarm is intentionally started before touching any automation state.
  playBotCheckSound()
  scheduleBotCheckLoop(botCheckGeneration)
  flashBotCheckWindow()
  disableBotCheckAutomation()
end

local function stopBotCheckAlarm()
  botCheckActive = false
  botCheckGeneration = botCheckGeneration + 1
  cancelBotCheckLoop()

  if g_sounds ~= nil and type(g_sounds.stopAlarm) == 'function' then
    local ok, err = pcall(function()
      g_sounds.stopAlarm()
    end)
    if not ok then
      warn('failed to stop bot-check alarm: ' .. tostring(err))
    end
  end
end

function MiniBotCompat.handleBotCheckCommand(command)
  if not initialized or type(command) ~= 'string' then
    return false
  end

  command = command:match('^%s*(.-)%s*$')
  if command == nil then
    return false
  end
  command = command:lower()
  if command == 'start' then
    startBotCheckAlarm()
    return true
  elseif command == 'stop' then
    stopBotCheckAlarm()
    return true
  end
  return false
end

function MiniBotCompat.getBotCheckAlarmState()
  return {
    active = botCheckActive,
    scheduled = botCheckLoopEvent ~= nil,
    registered = botCheckOpcodeRegistered
  }
end

local function onExtendedBotCheck(_, opcode, buffer)
  if opcode ~= BOTCHECK_OPCODE then
    return
  end
  MiniBotCompat.handleBotCheckCommand(buffer)
end

local function registerBotCheckOpcode()
  ensureBotCheckSoundPreloaded()

  -- Clear a stale registration left by a hot reload or by the retired Helper.
  pcall(function()
    ProtocolGame.unregisterExtendedOpcode(BOTCHECK_OPCODE)
  end)

  local ok, err = pcall(function()
    ProtocolGame.registerExtendedOpcode(BOTCHECK_OPCODE, onExtendedBotCheck)
  end)
  botCheckOpcodeRegistered = ok
  if not ok then
    warn('failed to register bot-check opcode ' .. BOTCHECK_OPCODE .. ': ' .. tostring(err))
  end
end

local function unregisterBotCheckOpcode()
  stopBotCheckAlarm()
  if not botCheckOpcodeRegistered then
    return
  end

  local ok, err = pcall(function()
    ProtocolGame.unregisterExtendedOpcode(BOTCHECK_OPCODE)
  end)
  if not ok then
    warn('failed to unregister bot-check opcode ' .. BOTCHECK_OPCODE .. ': ' .. tostring(err))
  end
  botCheckOpcodeRegistered = false
end

if PlayerStates and PlayerStates.StatePz == nil then
  PlayerStates.StatePz = PlayerStates.Pz
end

SpellGroup = SpellGroup or {}
SpellGroup.Attack = SpellGroup.Attack or 1
SpellGroup.Healing = SpellGroup.Healing or 2
SpellGroup.Support = SpellGroup.Support or 3

if MarketCategory and MarketCategory.Ammunitions == nil then
  MarketCategory.Ammunitions = MarketCategory.Ammunition
end

if ResourceInventary == nil and ResourceInventory ~= nil then
  ResourceInventary = ResourceInventory
end

if rgbToHex == nil then
  function rgbToHex(color, green, blue, alpha)
    local red
    if type(color) == 'table' then
      red = color.r or color[1]
      green = color.g or color[2]
      blue = color.b or color[3]
      alpha = color.a or color[4]
    else
      red = color
    end

    local function channel(value)
      value = tonumber(value) or 0
      return math.max(0, math.min(255, math.floor(value + 0.5)))
    end

    if alpha ~= nil then
      return string.format('#%02X%02X%02X%02X', channel(red), channel(green), channel(blue), channel(alpha))
    end
    return string.format('#%02X%02X%02X', channel(red), channel(green), channel(blue))
  end
end

if UIWidget.constructEnviorementVariables == nil then
  function UIWidget:constructEnviorementVariables()
    for _, child in ipairs(self:getChildren()) do
      local id = child:getId()
      if id ~= nil and id ~= '' then
        self[id] = child
      end
      child:constructEnviorementVariables()
    end
    return self
  end
end

if UIWidget.stopGif == nil then
  function UIWidget:stopGif()
    if self._miniBotGifEvent ~= nil then
      removeEvent(self._miniBotGifEvent)
      self._miniBotGifEvent = nil
    end
  end
end

if UIWidget.loadGif == nil then
  function UIWidget:loadGif(file, frames, duration, size, pingPong)
    self:stopGif()

    frames = math.max(1, math.floor(tonumber(frames) or 1))
    duration = math.max(1, math.floor(tonumber(duration) or 100))
    size = type(size) == 'table' and size or {}
    local width = math.max(1, math.floor(tonumber(size.width) or self:getWidth()))
    local height = math.max(1, math.floor(tonumber(size.height) or self:getHeight()))
    local frame = 1
    local direction = 1

    self:setImageSource(file)

    local function animate()
      if not widgetAlive(self) then
        return
      end

      self:setImageClip(torect(string.format('%d 0 %d %d', (frame - 1) * width, width, height)))

      if pingPong and frames > 1 then
        if frame >= frames then
          direction = -1
        elseif frame <= 1 then
          direction = 1
        end
        frame = frame + direction
      else
        frame = (frame % frames) + 1
      end

      self._miniBotGifEvent = scheduleEvent(animate, duration)
    end

    animate()
  end
end

if UIMinimap.getAlternatives == nil then
  function UIMinimap:getAlternatives()
    self.alternatives = self.alternatives or {}
    return self.alternatives
  end
end

if UIMinimap.destroyAlternatives == nil then
  function UIMinimap:destroyAlternatives()
    local alternatives = self:getAlternatives()
    for index = #alternatives, 1, -1 do
      local widget = alternatives[index]
      if widgetAlive(widget) then
        widget:destroy()
      end
      alternatives[index] = nil
    end
    self.alternatives = {}
  end
end

if UIMinimap.internalRegisterAlternative == nil then
  function UIMinimap:internalRegisterAlternative(widget)
    if not widgetAlive(widget) then
      return false
    end

    local found = false
    for _, alternative in ipairs(self:getAlternatives()) do
      if alternative == widget then
        found = true
        break
      end
    end
    if not found then
      self:addAlternativeWidget(widget, widget.pos or widget.tilePosition)
    end

    if widget.pos ~= nil then
      self:centerInPosition(widget, widget.pos)
    end
    local layout = self:getLayout()
    if layout ~= nil then
      layout:update()
    end
    return true
  end
end

if UIStoreButton == nil then
  UIStoreButton = extends(UIButton, 'UIStoreButton')

  function UIStoreButton.create()
    return UIStoreButton.internalCreate()
  end

  function UIStoreButton:onStyleApply(_, styleNode)
    for name, value in pairs(styleNode) do
      if name == 'buttoncolor' then
        self.hasButtonColors = true
        self:setButtonColor(value)
      end
    end
  end
end

if UIStoreButton.setButtonColor == nil then
  function UIStoreButton:setButtonColor(value)
    self.hasButtonColors = true
    local colors = {
      yellow = '/images/game_minibot/images/store/button_yellow',
      green = '/images/game_minibot/images/store/button_green',
      red = '/images/game_minibot/images/store/button_red',
      blue = '/images/game_minibot/images/store/button_blue'
    }
    self:setImageSource(colors[value] or colors.blue)
  end
end

local function installStoreButtonAdapter()
  if storeButtonAdapterInstalled then
    return
  end
  previous.uiStoreButtonClass = rawget(rootEnvironment, 'UIStoreButton')
  rawset(rootEnvironment, 'UIStoreButton', UIStoreButton)
  storeButtonAdapterInstalled = true
end

local function restoreStoreButtonAdapter()
  if not storeButtonAdapterInstalled then
    return
  end
  if rawget(rootEnvironment, 'UIStoreButton') == UIStoreButton then
    rawset(rootEnvironment, 'UIStoreButton', previous.uiStoreButtonClass)
  end
  storeButtonAdapterInstalled = false
end

local function normalizedSpell(raw)
  if type(raw) ~= 'table' then
    return nil
  end

  local spell = {}
  for key, value in pairs(raw) do
    spell[key] = value
  end

  spell.groups = {}
  if type(raw.group) == 'table' then
    for group in pairs(raw.group) do
      table.insert(spell.groups, group)
    end
    table.sort(spell.groups)
  elseif finiteInteger(raw.group, 1, 255) then
    table.insert(spell.groups, raw.group)
  end

  spell.vocations = {}
  if type(raw.vocations) == 'table' then
    for _, vocation in ipairs(raw.vocations) do
      if type(vocation) == 'number' and VocationNames then
        table.insert(spell.vocations, VocationNames[vocation] or vocation)
      else
        table.insert(spell.vocations, vocation)
      end
    end
  end

  spell.requiresTarget = raw.requiresTarget or raw.needTarget or false
  spell.needDirection = raw.needDirection or raw.directional or false
  return spell
end

local spellAdapter = {}
local spellServerToClient = nil
local spellClientToServer = nil

local function buildSpellIconMaps()
  if spellServerToClient ~= nil then
    return
  end
  spellServerToClient = {}
  spellClientToServer = {}
  if Spells == nil or type(Spells.getSpellList) ~= 'function' or
      type(Spells.getClientId) ~= 'function' then
    return
  end

  for _, spell in ipairs(Spells.getSpellList()) do
    local serverId = tonumber(spell.id)
    local clientId = spell.name and tonumber(Spells.getClientId(spell.name)) or nil
    if serverId ~= nil and clientId ~= nil then
      spellServerToClient[serverId] = clientId
      spellClientToServer[clientId] = serverId
    end
  end
end

function spellAdapter.getSpellInfoById(id)
  id = tonumber(id)
  if id == nil or Spells == nil or Spells.getSpellDataById == nil then
    return nil
  end
  return normalizedSpell(Spells.getSpellDataById(id))
end

function spellAdapter.getSpellRegularImageClipById(id)
  local serverId = math.max(1, math.floor(tonumber(id) or 1))
  buildSpellIconMaps()
  local clientId = spellServerToClient[serverId] or serverId
  return torect(string.format('%d 0 32 32', (clientId - 1) * 32))
end

function spellAdapter.getSpellRegularIdByImageClipX(x)
  x = math.max(0, math.floor(tonumber(x) or 0))
  local clientId = math.floor(x / 32) + 1
  buildSpellIconMaps()
  return spellClientToServer[clientId] or clientId
end

function spellAdapter.getSpellsByGroup(group)
  local result = {}
  if Spells == nil or Spells.getSpellList == nil then
    return result
  end

  for _, raw in ipairs(Spells.getSpellList()) do
    local spell = normalizedSpell(raw)
    if spell and table.find(spell.groups, group) then
      table.insert(result, spell)
    end
  end
  table.sort(result, function(left, right)
    return tostring(left.name):lower() < tostring(right.name):lower()
  end)
  return result
end

function spellAdapter.findSpellsByString(text, group)
  local result = {}
  local needle = tostring(text or ''):lower()
  for _, spell in ipairs(spellAdapter.getSpellsByGroup(group)) do
    if tostring(spell.name or ''):lower():find(needle, 1, true) then
      table.insert(result, { block = spell, type = 'name' })
    end
    if tostring(spell.words or ''):lower():find(needle, 1, true) then
      table.insert(result, { block = spell, type = 'words' })
    end
  end
  return result
end

local function installSpellAdapter()
  previous.g_spells = g_spells
  previous.g_spellsMethods = {}
  g_spells = g_spells or {}
  for name, callback in pairs(spellAdapter) do
    previous.g_spellsMethods[name] = g_spells[name]
    if g_spells[name] == nil then
      g_spells[name] = callback
    end
  end
end

local function restoreSpellAdapter()
  if previous.g_spells == nil then
    g_spells = nil
  else
    for name in pairs(spellAdapter) do
      g_spells[name] = previous.g_spellsMethods[name]
    end
    g_spells = previous.g_spells
  end
  spellServerToClient = nil
  spellClientToServer = nil
end

-- Astra keeps the OTB metadata returned by findItemTypesByString in ItemType
-- objects. Those objects intentionally expose only the OTB-facing API
-- (getClientId/getServerId/category/etc.) and do not have the ThingType market
-- methods expected by MiniBot. Always expose ThingType objects from these
-- compatibility helpers, matching the donor API.
local function asThingType(candidate)
  if candidate == nil or g_things == nil then
    return nil
  end

  if candidate.isMarketable ~= nil and candidate.getMarketData ~= nil and candidate.getId ~= nil then
    return candidate
  end

  if candidate.getClientId == nil or g_things.getThingType == nil then
    return nil
  end

  local okClientId, clientId = pcall(function()
    return candidate:getClientId()
  end)
  clientId = okClientId and tonumber(clientId) or nil
  if clientId == nil or clientId <= 0 then
    return nil
  end

  local okThingType, thingType = pcall(function()
    return g_things.getThingType(clientId, ThingCategoryItem or 0)
  end)
  if not okThingType or thingType == nil or thingType.isMarketable == nil or thingType.getMarketData == nil then
    return nil
  end
  return thingType
end

local function getMarketData(thingType)
  thingType = asThingType(thingType)
  if thingType == nil then
    return nil, nil
  end

  local okMarketable, marketable = pcall(function()
    return thingType:isMarketable()
  end)
  if not okMarketable or not marketable then
    return thingType, nil
  end

  local okMarketData, marketData = pcall(function()
    return thingType:getMarketData()
  end)
  if not okMarketData or type(marketData) ~= 'table' then
    return thingType, nil
  end
  return thingType, marketData
end

local function findAllMarketableThingTypes()
  if g_things == nil then
    return {}
  end

  -- This is Astra's native ThingType query and avoids the incompatible
  -- ItemType objects returned by findItemTypesByString.
  if g_things.findThingTypeByAttr ~= nil then
    local ok, thingTypes = pcall(function()
      return g_things.findThingTypeByAttr(ThingAttrMarket or 33, ThingCategoryItem or 0)
    end)
    if ok and type(thingTypes) == 'table' then
      return thingTypes
    end
  end

  -- Defensive fallback for clients that expose the OTB search but not the
  -- direct ThingType attribute query. Convert every ItemType through clientId.
  if g_things.findItemTypesByString == nil then
    return {}
  end

  local ok, itemTypes = pcall(function()
    return g_things.findItemTypesByString('')
  end)
  if not ok or type(itemTypes) ~= 'table' then
    return {}
  end

  local result = {}
  local seen = {}
  for _, candidate in ipairs(itemTypes) do
    local thingType, marketData = getMarketData(candidate)
    if thingType ~= nil and marketData ~= nil then
      local okId, id = pcall(function()
        return thingType:getId()
      end)
      local key = okId and tonumber(id) or nil
      if key == nil or not seen[key] then
        table.insert(result, thingType)
        if key ~= nil then
          seen[key] = true
        end
      end
    end
  end
  return result
end

local function findMarketableItemTypesByString(text)
  local result = {}
  local needle = tostring(text or ''):lower()
  for _, candidate in ipairs(findAllMarketableThingTypes()) do
    local thingType, marketData = getMarketData(candidate)
    local name = marketData and tostring(marketData.name or '') or ''
    if thingType ~= nil and marketData ~= nil and name:lower():find(needle, 1, true) then
      table.insert(result, thingType)
    end
  end
  return result
end

local function findItemTypeByMarketCategory(category)
  local result = {}
  category = tonumber(category)
  if category == nil then
    return result
  end

  for _, candidate in ipairs(findAllMarketableThingTypes()) do
    local thingType, marketData = getMarketData(candidate)
    if thingType ~= nil and marketData ~= nil and tonumber(marketData.category) == category then
      table.insert(result, thingType)
    end
  end
  return result
end

local function installThingAdapters()
  if thingAdaptersInstalled or g_things == nil then
    return
  end

  previous.findMarketableItemTypesByString = g_things.findMarketableItemTypesByString
  previous.findItemTypeByMarketCategory = g_things.findItemTypeByMarketCategory
  if g_things.findMarketableItemTypesByString == nil then
    g_things.findMarketableItemTypesByString = findMarketableItemTypesByString
  end
  if g_things.findItemTypeByMarketCategory == nil then
    g_things.findItemTypeByMarketCategory = findItemTypeByMarketCategory
  end
  thingAdaptersInstalled = true
end

local function restoreThingAdapters()
  if not thingAdaptersInstalled then
    return
  end

  if g_things ~= nil then
    g_things.findMarketableItemTypesByString = previous.findMarketableItemTypesByString
    g_things.findItemTypeByMarketCategory = previous.findItemTypeByMarketCategory
  end
  previous.findMarketableItemTypesByString = nil
  previous.findItemTypeByMarketCategory = nil
  thingAdaptersInstalled = false
end

local function canSpellCast(spell)
  if type(spell) ~= 'table' then
    return false
  end
  local player = g_game.getLocalPlayer()
  if player == nil or type(spell.vocations) ~= 'table' or #spell.vocations == 0 then
    return player ~= nil
  end

  local vocation = player:getVocation()
  local vocationName = VocationNames and VocationNames[vocation] or tostring(vocation)
  for _, allowed in ipairs(spell.vocations) do
    if allowed == vocation or tostring(allowed):lower() == tostring(vocationName):lower() then
      return true
    end
  end
  return false
end

local function installActionbarAdapter()
  local actionbar = modules and modules.game_actionbar
  if actionbar == nil then
    return
  end
  previous.canSpellCast = actionbar.canSpellCast
  if actionbar.canSpellCast == nil then
    actionbar.canSpellCast = canSpellCast
  end
end

local function restoreActionbarAdapter()
  local actionbar = modules and modules.game_actionbar
  if actionbar ~= nil then
    actionbar.canSpellCast = previous.canSpellCast
  end
end

local function getGeneralHotkeyCombo(name)
  if type(name) ~= 'string' or name == '' then
    return nil
  end

  local activeProfile = Options and Options.currentHotkeySet
  local chatType = Options and Options.isChatOnEnabled and 'chatOn' or 'chatOff'
  local mappings = type(activeProfile) == 'table' and activeProfile[chatType] or nil
  if type(mappings) == 'table' then
    for _, mapping in pairs(mappings) do
      local actionSetting = type(mapping) == 'table' and mapping.actionsetting or nil
      if type(actionSetting) == 'table' and actionSetting.action == name and not mapping.secondary then
        local combo = mapping.keysequence
        return type(combo) == 'string' and combo ~= '' and combo or nil
      end
    end
  end

  if KeyBinds and KeyBinds.getHotkeyByName then
    local ok, combo = pcall(function()
      return KeyBinds:getHotkeyByName(name)
    end)
    if ok and type(combo) == 'string' and combo ~= '' then
      return combo
    end
  end
  return nil
end

local function installClientOptionsAdapter()
  local clientOptions = modules and modules.client_options
  if clientOptions == nil then
    warn('client_options module is unavailable')
    return
  end
  previous.getGeneralHotkeyCombo = clientOptions.getGeneralHotkeyCombo
  if clientOptions.getGeneralHotkeyCombo == nil then
    clientOptions.getGeneralHotkeyCombo = getGeneralHotkeyCombo
  end
end

local function restoreClientOptionsAdapter()
  local clientOptions = modules and modules.client_options
  if clientOptions ~= nil then
    clientOptions.getGeneralHotkeyCombo = previous.getGeneralHotkeyCombo
  end
end

local function focusChat()
  local consoleModule = modules and modules.game_console
  if consoleModule == nil or type(consoleModule.getConsole) ~= 'function' then
    return false
  end

  local ok, console = pcall(consoleModule.getConsole)
  if not ok or not widgetAlive(console) or type(console.isEnabled) ~= 'function' or type(console.focus) ~= 'function' then
    return false
  end

  local enabledOk, enabled = pcall(function()
    return console:isEnabled()
  end)
  if not enabledOk or not enabled then
    return false
  end

  local focusOk, err = pcall(function()
    console:focus()
  end)
  if not focusOk then
    warn('failed to focus chat: ' .. tostring(err))
  end
  return focusOk
end

local function installConsoleAdapter()
  local consoleModule = modules and modules.game_console
  if consoleModule == nil then
    warn('game_console module is unavailable')
    return
  end
  previous.focusChat = consoleModule.focusChat
  if consoleModule.focusChat == nil then
    consoleModule.focusChat = focusChat
  end
  consoleAdapterInstalled = true
end

local function restoreConsoleAdapter()
  if not consoleAdapterInstalled then
    return
  end
  local consoleModule = modules and modules.game_console
  if consoleModule ~= nil then
    consoleModule.focusChat = previous.focusChat
  end
  consoleAdapterInstalled = false
end

local function readLocalResource(resourceType, fallback)
  local player = g_game.getLocalPlayer()
  if player == nil or player.getResourceValue == nil then
    return fallback
  end

  local ok, value = pcall(function()
    return player:getResourceValue(resourceType)
  end)
  if not ok then
    warn('unable to read local resource ' .. tostring(resourceType) .. ': ' .. tostring(value))
    return fallback
  end
  if not finiteInteger(value, 0, MAX_SAFE_INTEGER) then
    return fallback
  end
  return value
end

local function emitResource(resourceType, value)
  signalcall(g_game.onResourceBalance, resourceType, value)
end

local function currentBalances()
  state.bankBalance = readLocalResource(ResourceBank or 0, state.bankBalance)
  state.inventoryBalance = readLocalResource(ResourceInventary or ResourceInventory or 1, state.inventoryBalance)
  return state.bankBalance, state.inventoryBalance
end

local function sendRequest(payload)
  if not g_game.isOnline() then
    return false
  end
  local protocol = g_game.getProtocolGame()
  if protocol == nil then
    return false
  end

  local ok, err = pcall(function()
    protocol:sendExtendedJSONOpcode(OPCODE, payload)
  end)
  if not ok then
    warn('failed to send opcode ' .. OPCODE .. ': ' .. tostring(err))
    return false
  end
  return true
end

local function resourceRequest(_)
  if not g_game.isOnline() or g_game.getLocalPlayer() == nil then
    return false
  end
  local bank, inventory = currentBalances()
  emitResource(ResourceBank or 0, bank)
  emitResource(ResourceInventary or ResourceInventory or 1, inventory)
  return sendRequest({
    v = 1,
    action = 'query',
    bankBalance = bank,
    inventoryBalance = inventory
  })
end

local function afkPause(action)
  action = tonumber(action)
  if action == 0 then
    local bank, inventory = currentBalances()
    return sendRequest({
      v = 1,
      action = 'query',
      bankBalance = bank,
      inventoryBalance = inventory
    })
  elseif action == 1 then
    return sendRequest({ v = 1, action = 'pause', enabled = true })
  elseif action == 2 then
    return sendRequest({ v = 1, action = 'task', enabled = true })
  elseif action == 3 then
    return sendRequest({ v = 1, action = 'task', enabled = false })
  elseif action == 4 then
    return sendRequest({ v = 1, action = 'renew' })
  end

  warn('rejected unknown afkPause action: ' .. tostring(action))
  return false
end

local function validateState(data)
  if type(data) ~= 'table' or data.v ~= 1 or data.action ~= 'state' then
    return nil, 'invalid envelope'
  end
  if type(data.enabled) ~= 'boolean' or type(data.task) ~= 'boolean' then
    return nil, 'enabled/task must be booleans'
  end
  if data.botCheckActive ~= nil and type(data.botCheckActive) ~= 'boolean' then
    return nil, 'botCheckActive must be a boolean'
  end

  local numeric = {
    timeLeft = { 0, MAX_DURATION },
    total = { 1, MAX_DURATION },
    renewPrice = { 0, MAX_SAFE_INTEGER },
    bannedUntil = { 0, MAX_TIMESTAMP },
    afkPauseUntil = { 0, MAX_TIMESTAMP },
    afkAvailableAt = { 0, MAX_TIMESTAMP },
    bankBalance = { 0, MAX_SAFE_INTEGER },
    inventoryBalance = { 0, MAX_SAFE_INTEGER }
  }
  for field, limits in pairs(numeric) do
    if not finiteInteger(data[field], limits[1], limits[2]) then
      return nil, 'invalid numeric field: ' .. field
    end
  end
  if data.timeLeft > data.total then
    return nil, 'timeLeft exceeds total'
  end
  if data.error ~= nil and type(data.error) ~= 'string' then
    return nil, 'invalid error field'
  end

  return {
    enabled = data.enabled,
    timeLeft = data.timeLeft,
    total = data.total,
    task = data.task,
    renewPrice = data.renewPrice,
    bannedUntil = data.bannedUntil,
    afkPauseUntil = data.afkPauseUntil,
    afkAvailableAt = data.afkAvailableAt,
    botCheckActive = data.botCheckActive == true,
    bankBalance = data.bankBalance,
    inventoryBalance = data.inventoryBalance,
    error = data.error and data.error:sub(1, 256) or nil
  }
end

local function applyState(nextState)
  local hadAuthoritativeState = stateReceivedAt > 0
  local authoritativeWasEnabled = hadAuthoritativeState and state.enabled == true
  local runtimeWasEnabled = false
  if not nextState.enabled and g_minibot ~= nil and type(g_minibot.isModuleToggle) == 'function' then
    local ok, enabled = pcall(g_minibot.isModuleToggle, 5)
    runtimeWasEnabled = ok and enabled == true
  end
  local authoritativeError = type(nextState.error) == 'string' and nextState.error ~= ''
  local shouldSynchronizeDisabled = not nextState.enabled and
      (authoritativeWasEnabled or runtimeWasEnabled or authoritativeError)

  if nextState.botCheckActive and not botCheckActive then
    startBotCheckAlarm()
  elseif not nextState.botCheckActive and botCheckActive then
    stopBotCheckAlarm()
  end

  for key, value in pairs(nextState) do
    state[key] = value
  end
  state.error = nextState.error
  stateReceivedAt = os.time()

  if state.error and state.error ~= '' then
    warn('server state: ' .. state.error)
  end

  local function applyRuntimeState()
    local apply = g_minibot and g_minibot.applyServerCavebotState
    if apply == nil and MiniBotRuntime then
      apply = MiniBotRuntime.applyServerCavebotState
    end
    if apply then
      local ok, err = pcall(apply, state.enabled)
      if not ok then
        warn('failed to apply authoritative cavebot state: ' .. tostring(err))
      end
    end
  end

  applyRuntimeState()
  if shouldSynchronizeDisabled then
    -- Runtime application above is deliberately opcode-silent. Persist and
    -- mirror only a real transition, pending-runtime rejection or explicit
    -- server error. A normal initial OFF snapshot must not erase the saved
    -- Recorder preference before the profile has been reloaded.
    synchronizeAuthoritativeCavebotDisabled()
  end

  emitResource(ResourceBank or 0, state.bankBalance)
  emitResource(ResourceInventary or ResourceInventory or 1, state.inventoryBalance)
  signalcall(g_game.onMinibotCavebotTimer, state.timeLeft, state.total, state.task, state.renewPrice)

  local player = g_game.getLocalPlayer()
  if player ~= nil then
    signalcall(LocalPlayer.onCaveBotTimestamp, player, state.bannedUntil)
    signalcall(LocalPlayer.onAFKPauseChange, player, state.afkAvailableAt)
  end
end

local function onExtendedState(_, _, data)
  local nextState, err = validateState(data)
  if nextState == nil then
    warn('rejected opcode ' .. OPCODE .. ' state: ' .. tostring(err))
    return
  end
  applyState(nextState)
end

local function installOriginApis()
  previous.resourceRequest = g_game.resourceRequest
  previous.afkPause = g_game.afkPause
  previous.getCaveBotTimestamp = LocalPlayer.getCaveBotTimestamp
  previous.getCaveBotTimeLeft = LocalPlayer.getCaveBotTimeLeft
  previous.getCaveBotTotalTimeLeft = LocalPlayer.getCaveBotTotalTimeLeft
  previous.getCaveBotRenewPrice = LocalPlayer.getCaveBotRenewPrice
  previous.isCaveBotTask = LocalPlayer.isCaveBotTask
  previous.getAFKPauseTimestamp = LocalPlayer.getAFKPauseTimestamp

  g_game.resourceRequest = resourceRequest
  g_game.afkPause = afkPause

  function LocalPlayer:getCaveBotTimestamp()
    return state.bannedUntil
  end

  function LocalPlayer:getCaveBotTimeLeft()
    if state.enabled and not state.task and stateReceivedAt > 0 then
      return math.max(0, state.timeLeft - math.max(0, os.time() - stateReceivedAt))
    end
    return state.timeLeft
  end

  function LocalPlayer:getCaveBotTotalTimeLeft()
    return state.total
  end

  function LocalPlayer:getCaveBotRenewPrice()
    return state.renewPrice
  end

  function LocalPlayer:isCaveBotTask()
    return state.task
  end

  function LocalPlayer:getAFKPauseTimestamp()
    return state.afkAvailableAt
  end
end

local function restoreOriginApis()
  g_game.resourceRequest = previous.resourceRequest
  g_game.afkPause = previous.afkPause
  LocalPlayer.getCaveBotTimestamp = previous.getCaveBotTimestamp
  LocalPlayer.getCaveBotTimeLeft = previous.getCaveBotTimeLeft
  LocalPlayer.getCaveBotTotalTimeLeft = previous.getCaveBotTotalTimeLeft
  LocalPlayer.getCaveBotRenewPrice = previous.getCaveBotRenewPrice
  LocalPlayer.isCaveBotTask = previous.isCaveBotTask
  LocalPlayer.getAFKPauseTimestamp = previous.getAFKPauseTimestamp
end

function MiniBotCompat.init()
  if initialized then
    return
  end

  installStoreButtonAdapter()
  installSpellAdapter()
  installItemNameAdapter()
  installThingTypeNameAdapter()
  installThingAdapters()
  installActionbarAdapter()
  installClientOptionsAdapter()
  installConsoleAdapter()
  installSoundAdapter()
  installOriginApis()
  ProtocolGame.registerExtendedJSONOpcode(OPCODE, onExtendedState)
  opcodeRegistered = true
  registerBotCheckOpcode()
  initialized = true
end

function MiniBotCompat.onGameStart()
  if initialized then
    resourceRequest(ResourceBank or 0)
  end
end

function MiniBotCompat.onGameEnd()
  stopBotCheckAlarm()
  state.enabled = false
  state.timeLeft = 0
  state.total = 0
  state.task = false
  state.renewPrice = 0
  state.bannedUntil = 0
  state.afkPauseUntil = 0
  state.afkAvailableAt = 0
  state.botCheckActive = false
  state.bankBalance = 0
  state.inventoryBalance = 0
  state.error = nil
  stateReceivedAt = 0
end

function MiniBotCompat.terminate()
  if not initialized then
    unregisterBotCheckOpcode()
    restoreLocalWidgetBindings()
    restoreThingAdapters()
    restoreThingTypeNameAdapter()
    restoreItemNameAdapter()
    return
  end

  unregisterBotCheckOpcode()
  if opcodeRegistered then
    ProtocolGame.unregisterExtendedJSONOpcode(OPCODE)
    opcodeRegistered = false
  end
  MiniBotCompat.onGameEnd()
  restoreOriginApis()
  restoreConsoleAdapter()
  restoreClientOptionsAdapter()
  restoreActionbarAdapter()
  restoreThingAdapters()
  restoreThingTypeNameAdapter()
  restoreItemNameAdapter()
  restoreSpellAdapter()
  restoreStoreButtonAdapter()
  restoreSoundAdapter()
  restoreLocalWidgetBindings()
  initialized = false
end

if table.obscure == nil then
  function table.obscure(value)
    local seen = {}
    local entries = 0

    local function writeUint16(number)
      return string.char(number % 256, math.floor(number / 256) % 256)
    end

    local function writeUint32(number)
      return string.char(number % 256, math.floor(number / 256) % 256,
          math.floor(number / 65536) % 256, math.floor(number / 16777216) % 256)
    end

    local function encodeDouble(number)
      if string.pack then
        return string.pack('<d', number)
      end
      if number ~= number then
        return string.char(0, 0, 0, 0, 0, 0, 0xF8, 0x7F)
      end
      if number == math.huge then
        return string.char(0, 0, 0, 0, 0, 0, 0xF0, 0x7F)
      end
      if number == -math.huge then
        return string.char(0, 0, 0, 0, 0, 0, 0xF0, 0xFF)
      end

      local sign = 0
      if number < 0 or (number == 0 and 1 / number < 0) then
        sign = 1
        number = -number
      end
      if number == 0 then
        return string.char(0, 0, 0, 0, 0, 0, 0, sign == 1 and 0x80 or 0)
      end

      local exponent = math.floor(math.log(number) / math.log(2)) + 1
      local mantissa = number / 2 ^ (exponent - 1)
      mantissa = mantissa - 1
      exponent = exponent - 1 + 1023
      local mantissaInteger = math.floor(mantissa * 2 ^ 52 + 0.5)
      local b7 = sign * 0x80 + math.floor(exponent / 16)
      local b6 = (exponent % 16) * 16 + math.floor(mantissaInteger / 2 ^ 48) % 16
      return string.char(
          mantissaInteger % 256,
          math.floor(mantissaInteger / 2 ^ 8) % 256,
          math.floor(mantissaInteger / 2 ^ 16) % 256,
          math.floor(mantissaInteger / 2 ^ 24) % 256,
          math.floor(mantissaInteger / 2 ^ 32) % 256,
          math.floor(mantissaInteger / 2 ^ 40) % 256,
          b6, b7)
    end

    local function serialize(item, output, depth)
      if depth > 64 then
        error('obscure nesting limit exceeded')
      end
      local itemType = type(item)
      if item == nil then
        output[#output + 1] = string.char(0x01)
      elseif itemType == 'boolean' then
        output[#output + 1] = string.char(item and 0x03 or 0x02)
      elseif itemType == 'number' then
        output[#output + 1] = string.char(0x05) .. encodeDouble(item)
      elseif itemType == 'string' then
        if #item > MAX_OBSCURED_BYTES then
          error('obscure string limit exceeded')
        elseif #item <= 0xFFFF then
          output[#output + 1] = string.char(0x06) .. writeUint16(#item) .. item
        else
          output[#output + 1] = string.char(0x07) .. writeUint32(#item) .. item
        end
      elseif itemType == 'table' then
        if seen[item] then
          error('circular table passed to obscure')
        end
        seen[item] = true
        output[#output + 1] = string.char(0x08)
        for key, child in pairs(item) do
          entries = entries + 1
          if entries > 100000 then
            error('obscure entry limit exceeded')
          end
          serialize(key, output, depth + 1)
          serialize(child, output, depth + 1)
        end
        output[#output + 1] = string.char(0x00)
        seen[item] = nil
      else
        error('unsupported obscure type: ' .. itemType)
      end
    end

    local output = {}
    serialize(value, output, 0)
    local raw = table.concat(output)
    if #raw > MAX_OBSCURED_BYTES then
      error('obscure payload limit exceeded')
    end

    local shifted = {}
    for index = 1, #raw do
      shifted[index] = string.format('%02X', (raw:byte(index) + index * 7 + 13) % 256)
    end
    return 'O1' .. table.concat(shifted)
  end
end

if table.unobscure == nil then
  function table.unobscure(encoded)
    if type(encoded) ~= 'string' or not encoded:find('^O1') then
      return nil
    end
    if #encoded > MAX_OBSCURED_BYTES * 2 + 2 then
      warn('rejected oversized obscured payload')
      return nil
    end

    local hex = encoded:sub(3)
    if #hex % 2 ~= 0 then
      return nil
    end

    local bytes = {}
    for zeroIndex = 0, #hex / 2 - 1 do
      local byte = tonumber(hex:sub(zeroIndex * 2 + 1, zeroIndex * 2 + 2), 16)
      if byte == nil then
        return nil
      end
      local index = zeroIndex + 1
      bytes[index] = string.char((byte - (index * 7 + 13)) % 256)
    end

    local data = table.concat(bytes)
    local position = 1
    local entries = 0

    local function read(count)
      local chunk = data:sub(position, position + count - 1)
      if #chunk ~= count then
        error('truncated obscure payload')
      end
      position = position + count
      return chunk
    end

    local function readUint16()
      local chunk = read(2)
      return chunk:byte(1) + chunk:byte(2) * 256
    end

    local function readUint32()
      local chunk = read(4)
      return chunk:byte(1) + chunk:byte(2) * 256 + chunk:byte(3) * 65536 + chunk:byte(4) * 16777216
    end

    local function decodeDouble(chunk)
      if string.unpack then
        return string.unpack('<d', chunk)
      end
      local b0, b1, b2, b3, b4, b5, b6, b7 = chunk:byte(1, 8)
      local sign = math.floor(b7 / 0x80)
      local exponent = (b7 % 0x80) * 16 + math.floor(b6 / 16)
      local mantissa = b6 % 16
      mantissa = mantissa * 256 + b5
      mantissa = mantissa * 256 + b4
      mantissa = mantissa * 256 + b3
      mantissa = mantissa * 256 + b2
      mantissa = mantissa * 256 + b1
      mantissa = mantissa * 256 + b0
      if exponent == 0x7FF then
        if mantissa == 0 then
          return sign == 1 and -math.huge or math.huge
        end
        return 0 / 0
      end
      local value
      if exponent == 0 then
        value = mantissa == 0 and 0 or (mantissa / 2 ^ 52) * 2 ^ -1022
      else
        value = (1 + mantissa / 2 ^ 52) * 2 ^ (exponent - 1023)
      end
      return sign == 1 and -value or value
    end

    local parse
    parse = function(depth)
      if depth > 64 then
        error('obscure nesting limit exceeded')
      end
      local tag = data:byte(position)
      position = position + 1
      if tag == nil then
        error('unexpected end of obscure payload')
      elseif tag == 0x01 then
        return nil
      elseif tag == 0x02 then
        return false
      elseif tag == 0x03 then
        return true
      elseif tag == 0x04 then
        local chunk = read(8)
        local number, multiplier = 0, 1
        for index = 1, 8 do
          number = number + chunk:byte(index) * multiplier
          multiplier = multiplier * 256
        end
        return number >= 2 ^ 63 and number - 2 ^ 64 or number
      elseif tag == 0x05 then
        return decodeDouble(read(8))
      elseif tag == 0x06 then
        return read(readUint16())
      elseif tag == 0x07 then
        return read(readUint32())
      elseif tag == 0x08 then
        local result = {}
        while data:byte(position) ~= 0x00 do
          if data:byte(position) == nil then
            error('unterminated obscure table')
          end
          entries = entries + 1
          if entries > 100000 then
            error('obscure entry limit exceeded')
          end
          local key = parse(depth + 1)
          local value = parse(depth + 1)
          result[key] = value
        end
        position = position + 1
        return result
      end
      error('unknown obscure tag: ' .. tostring(tag))
    end

    local ok, result = pcall(parse, 0)
    if not ok then
      warn('failed to decode obscured payload: ' .. tostring(result))
      return nil
    end
    if position <= #data then
      warn('rejected obscured payload with trailing data')
      return nil
    end
    return result
  end
end
