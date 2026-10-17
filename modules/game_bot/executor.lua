function executeBot(config, storage, tabs, msgCallback, saveConfigCallback, reloadCallback, websockets, applyBotFontsCallback, options)
  options = options or {}
  local function compileInContext(source, name, environment)
    local chunk, compileError = loadstring(source, name)
    if chunk then
      setfenv(chunk, environment)
    end
    return chunk, compileError
  end

  -- load lua and otui files
  local configFiles = options.standalone and {} or g_resources.listDirectoryFiles("/bot/" .. config, true, false)
  local luaFiles = {}
  local uiFiles = {}
  for i, file in ipairs(configFiles) do
    local ext = file:split(".")
    if ext[#ext]:lower() == "lua" then
      table.insert(luaFiles, file)
    end
    if ext[#ext]:lower() == "ui" or ext[#ext]:lower() == "otui" then
      table.insert(uiFiles, file)
    end
  end

  if #luaFiles == 0 and not options.standalone then
    return error("Config (/bot/" .. config .. ") doesn't have lua files")
  end

  -- init bot variables
  local context = {}
  context.standalone = options.standalone
  context.configDir = options.standalone and "/elfbot" or "/bot/".. config
  context.tabs = tabs
  if options.standalone then
    context.mainTab = g_ui.createWidget('UIWidget')
    context.mainTab:hide()
  else
    context.mainTab = context.tabs:addTab("Main", g_ui.createWidget('BotPanel')).tabPanel.content
  end
  context.panel = context.mainTab
  context.saveConfig = saveConfigCallback
  context.reload = reloadCallback
  context.applyBotFonts = applyBotFontsCallback or function() end

  context.storage = storage
  if context.storage._macros == nil then
    context.storage._macros = {} -- active macros
  end

  -- websockets, macros, hotkeys, scheduler, icons, callbacks
  context._websockets = websockets
  context._macros = {}
  context._hotkeys = {}
  context._scheduler = {}
  context._callbacks = {
    onKeyDown = {},
    onKeyUp = {},
    onKeyPress = {},
    onTalk = {},
    onTextMessage = {},
    onLoginAdvice = {},
    onAddThing = {},
    onRemoveThing = {},
    onCreatureAppear = {},
    onCreatureDisappear = {},
    onCreaturePositionChange = {},
    onCreatureHealthPercentChange = {},
    onUse = {},
    onUseWith = {},
    onContainerOpen = {},
    onContainerClose = {},
    onContainerUpdateItem = {},
    onMissle = {},
    onAnimatedText = {},
    onStaticText = {},
    onChannelList = {},
    onOpenChannel = {},
    onCloseChannel = {},
    onChannelEvent = {},
    onTurn = {},
    onWalk = {},
    onImbuementWindow = {},
    onModalDialog = {},
    onAttackingCreatureChange = {},
    onManaChange = {},
    onStatesChange = {},
    onAddItem = {},
    onGameEditText = {},
    onGroupSpellCooldown = {},
    onSpellCooldown = {},
    onRemoveItem = {},
    onInventoryChange = {}
  }
  context.updateTileCallbacks = function()
    setTileCallbacksOwner(context, not context._disposed and
      (#context._callbacks.onAddThing > 0 or #context._callbacks.onRemoveThing > 0))
  end

  -- basic functions & classes
  context.print = print
  context.bit32 = bit32
  context.bit = bit
  context.pairs = pairs
  context.ipairs = ipairs
  context.tostring = tostring
  context.math = math
  context.table = table
  context.setmetatable = setmetatable
  context.string = string
  context.tonumber = tonumber
  context.type = type
  context.pcall = pcall
  context.os = {
    time = os.time,
    difftime = os.difftime,
    date = os.date,
    clock = os.clock
  }
  context.load = function(str, name) return assert(compileInContext(str, name, context)) end
  context.loadstring = context.load
  context.assert = assert
  context.dofile = function(file) context.load(g_resources.readFileContents(context.configDir .. "/" .. file), file)() end
  context.gcinfo = gcinfo
  context.tr = tr
  context.json = json
  context.base64 = base64
  context.regexMatch = regexMatch
  context.getDistanceBetween = function(p1, p2)
    return math.max(math.abs(p1.x - p2.x), math.abs(p1.y - p2.y))
  end
  context.isMobile = g_app.isMobile
  context.getVersion = g_app.getVersion

  -- classes
  context.g_resources = g_resources
  context.g_game = g_game
  context.g_map = g_map
  context.g_ui = g_ui
  context.g_sounds = g_sounds
  context.g_window = g_window
  context.g_mouse = g_mouse
  context.g_keyboard = g_keyboard
  context.g_things = g_things
  context.g_settings = g_settings
  context.g_platform = {
    openUrl = g_platform.openUrl,
    openDir = g_platform.openDir,
  }

  context.Item = Item
  context.Creature = Creature
  context.ThingType = ThingType
  context.Effect = Effect
  context.Missile = Missile
  context.Player = Player
  context.Monster = Monster
  context.StaticText = StaticText
  context.HTTP = HTTP
  context.OutputMessage = OutputMessage
  context.modules = modules
  context.Directions = Directions

  -- log functions
  context.info = function(text) return msgCallback("info", tostring(text)) end
  context.warn = function(text) return msgCallback("warn", tostring(text)) end
  context.error = function(text) return msgCallback("error", tostring(text)) end
  context.warning = context.warn

  -- init context
  context.now = g_clock.millis()
  context.time = g_clock.millis()
  context.player = g_game.getLocalPlayer()

  -- init functions
  local previousContext = G.botContext
  G.botContext = context
  local initialized, initError = pcall(function()
    dofiles("functions")
    context.Panels = {}
    dofiles("panels")
  end)
  G.botContext = previousContext
  if not initialized then
    context._disposed = true
    context.updateTileCallbacks()
    if options.standalone then context.mainTab:destroy() end
    error(initError)
  end

  local attached, extension = pcall(function()
    if options.prepare then options.prepare(context) end
    for _, file in ipairs(uiFiles) do g_ui.importStyle(file) end
    for _, file in ipairs(luaFiles) do
      context.load(g_resources.readFileContents(file), file)()
      context.panel = context.mainTab -- reset default tab
    end
    return options.attach and options.attach(context)
  end)
  if not attached then
    context._disposed = true
    context.updateTileCallbacks()
    for id, socket in pairs(context._websockets) do g_http.cancel(socket);context._websockets[id] = nil end
    error(extension)
  end
  local function dispatchCallbacks(name, ...)
    if context._disposed then return end
    local pending = {}
    for _, callback in ipairs(context._callbacks[name]) do pending[#pending + 1] = callback end
    for _, callback in ipairs(pending) do callback(...) end
  end
  return {
    context = context,
    ui = extension,
    dispose = function()
      if context._disposed then return end
      context._disposed = true
      context.updateTileCallbacks()
      context._scheduler = {}
      for id, socket in pairs(context._websockets) do g_http.cancel(socket);context._websockets[id] = nil end
      local ok, err = true, nil
      if extension then ok, err = pcall(extension.dispose) end
      if options.standalone then context.mainTab:destroy() end
      if not ok then context.warning(tostring(err)) end
    end,
    script = function()
      if context._disposed then return end
      local now = g_clock.millis()
      context.now = now
      context.time = now

      for i, macro in ipairs(context._macros) do
        if macro.lastExecution + macro.timeout <= context.now and macro.enabled then
          local status, result = pcall(macro.callback, macro)
          context._currentExecution = nil
          if not status then
            context.error("Macro: " .. macro.name .. " execution error: " .. result)
          elseif result then
            macro.lastExecution = context.now
          end
        end
      end

      if extension then extension.tick() end

      while #context._scheduler > 0 and context._scheduler[1].execution <= g_clock.millis() do
        local task = table.remove(context._scheduler, 1)
        local status, result = pcall(task.callback)
        context._currentExecution = nil
        if not status then
          context.error("Schedule execution error: " .. result)
        end
      end
    end,
    resetCurrentExecution = function()
      context._currentExecution = nil
    end,
    callbacks = {
      onKeyDown = function(keyCode, keyboardModifiers)
        local keyDesc = determineKeyComboDesc(keyCode, keyboardModifiers)
        if extension and extension.keyDown(keyDesc) then return true end
        for i, macro in ipairs(context._macros) do
          if macro.switch and macro.hotkey == keyDesc then
            macro.switch:onClick()
          end
        end
        local hotkey = context._hotkeys[keyDesc]
        if hotkey then
          if hotkey.single then
            if hotkey.callback() then
              hotkey.lastExecution = context.now
            end
          end
          if hotkey.switch then
            hotkey.switch:setOn(true)
          end
        end
        dispatchCallbacks("onKeyDown", keyDesc)
      end,
      onKeyUp = function(keyCode, keyboardModifiers)
        local keyDesc = determineKeyComboDesc(keyCode, keyboardModifiers)
        local hotkey = context._hotkeys[keyDesc]
        if hotkey then
          if hotkey.switch then
            hotkey.switch:setOn(false)
          end
        end
        dispatchCallbacks("onKeyUp", keyDesc)
      end,
      onKeyPress = function(keyCode, keyboardModifiers, autoRepeatTicks)
        local keyDesc = determineKeyComboDesc(keyCode, keyboardModifiers)
        if extension and extension.keyPress(keyDesc) then return true end
        local hotkey = context._hotkeys[keyDesc]
        if hotkey and not hotkey.single then
          if hotkey.callback() then
            hotkey.lastExecution = context.now
          end
        end
        dispatchCallbacks("onKeyPress", keyDesc, autoRepeatTicks)
      end,
      onTalk = function(name, level, mode, text, channelId, pos)
        dispatchCallbacks("onTalk", name, level, mode, text, channelId, pos)
      end,
      onImbuementWindow = function(itemId, slots, activeSlots, imbuements, needItems)
        dispatchCallbacks("onImbuementWindow", itemId, slots, activeSlots, imbuements, needItems)
      end,
      onTextMessage = function(mode, text)
        dispatchCallbacks("onTextMessage", mode, text)
      end,
      onLoginAdvice = function(message)
        dispatchCallbacks("onLoginAdvice", message)
      end,
      onAddThing = function(tile, thing)
        dispatchCallbacks("onAddThing", tile, thing)
      end,
      onRemoveThing = function(tile, thing)
        dispatchCallbacks("onRemoveThing", tile, thing)
      end,
      onCreatureAppear = function(creature)
        dispatchCallbacks("onCreatureAppear", creature)
      end,
      onCreatureDisappear = function(creature)
        dispatchCallbacks("onCreatureDisappear", creature)
      end,
      onCreaturePositionChange = function(creature, newPos, oldPos)
        dispatchCallbacks("onCreaturePositionChange", creature, newPos, oldPos)
      end,
      onCreatureHealthPercentChange = function(creature, healthPercent)
        dispatchCallbacks("onCreatureHealthPercentChange", creature, healthPercent)
      end,
      onUse = function(pos, itemId, stackPos, subType)
        dispatchCallbacks("onUse", pos, itemId, stackPos, subType)
      end,
      onUseWith = function(pos, itemId, target, subType)
        dispatchCallbacks("onUseWith", pos, itemId, target, subType)
      end,
      onContainerOpen = function(container, previousContainer)
        dispatchCallbacks("onContainerOpen", container, previousContainer)
      end,
      onContainerClose = function(container)
        dispatchCallbacks("onContainerClose", container)
      end,
      onContainerUpdateItem = function(container, slot, item, oldItem)
        dispatchCallbacks("onContainerUpdateItem", container, slot, item, oldItem)
      end,
      onMissle = function(missle)
        dispatchCallbacks("onMissle", missle)
      end,
      onAnimatedText = function(thing, text)
        dispatchCallbacks("onAnimatedText", thing, text)
      end,
      onStaticText = function(thing, text)
        dispatchCallbacks("onStaticText", thing, text)
      end,
      onChannelList = function(channels)
        dispatchCallbacks("onChannelList", channels)
      end,
      onOpenChannel = function(channelId, channelName)
        dispatchCallbacks("onOpenChannel", channelId, channelName)
      end,
      onCloseChannel = function(channelId)
        dispatchCallbacks("onCloseChannel", channelId)
      end,
      onChannelEvent = function(channelId, name, event)
        dispatchCallbacks("onChannelEvent", channelId, name, event)
      end,
      onTurn = function(creature, direction)
        dispatchCallbacks("onTurn", creature, direction)
      end,
      onWalk = function(creature, oldPos, newPos)
        dispatchCallbacks("onWalk", creature, oldPos, newPos)
      end,
      onModalDialog = function(id, title, message, buttons, enterButton, escapeButton, choices, priority)
        dispatchCallbacks("onModalDialog", id, title, message, buttons, enterButton, escapeButton, choices, priority)
      end,
      onGameEditText = function(id, itemId, maxLength, text, writer, time)
        dispatchCallbacks("onGameEditText", id, itemId, maxLength, text, writer, time)
      end,
      onAttackingCreatureChange = function(creature, oldCreature)
        dispatchCallbacks("onAttackingCreatureChange", creature, oldCreature)
      end,
      onManaChange = function(player, mana, maxMana, oldMana, oldMaxMana)
        dispatchCallbacks("onManaChange", player, mana, maxMana, oldMana, oldMaxMana)
      end,
      onAddItem = function(container, slot, item)
        dispatchCallbacks("onAddItem", container, slot, item)
      end,
      onRemoveItem = function(container, slot, item)
        dispatchCallbacks("onRemoveItem", container, slot, item)
      end,
      onStatesChange = function(player, states, oldStates)
        dispatchCallbacks("onStatesChange", player, states, oldStates)
      end,
      onGroupSpellCooldown = function(iconId, duration)
        dispatchCallbacks("onGroupSpellCooldown", iconId, duration)
      end,
      onSpellCooldown = function(iconId, duration)
        dispatchCallbacks("onSpellCooldown", iconId, duration)
      end,
      onInventoryChange = function(player, slot, item, oldItem)
        dispatchCallbacks("onInventoryChange", player, slot, item, oldItem)
      end
    }
  }
end
