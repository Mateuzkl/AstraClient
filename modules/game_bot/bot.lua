botWindow = nil
botButton = nil
contentsPanel = nil
editWindow = nil

local checkEvent = nil
local refreshEvent = nil
local saveEvent = nil
local pendingSettings = nil
local callbacksConnected = false
local callbackConnections = nil
local nextMessageCleanup = 0

local botStorage = {}
local botStorageFile = nil
local botWebSockets = {}
local botMessages = nil
local botTabs = nil
local botExecutor = nil

local configList = nil
local enableButton = nil
local statusLabel = nil

local configManagerUrl = "http://otclient.ovh/configs.php"

local analyzerCompatibilityLine = "analyzerButton = modules.game_buttons.buttonsWindow.contentsPanel and modules.game_buttons.buttonsWindow.contentsPanel.buttons.botAnalyzersButton"
local analyzerCompatibilityReplacement = [[local gameButtonsWindow = modules.game_buttons and modules.game_buttons.buttonsWindow
local gameButtonsPanel = gameButtonsWindow and gameButtonsWindow.contentsPanel
local gameButtons = gameButtonsPanel and gameButtonsPanel.buttons
analyzerButton = gameButtons and gameButtons.botAnalyzersButton]]
local targetBotWarningLine = [[return warn("[vBot] Please create a new TargetBot config and reset bot")]]
local targetBotWarningReplacement = [[if not CaveBot.missingTargetBotConfigWarned then
            warn("[vBot] Please create a new TargetBot config and reset bot")
            CaveBot.missingTargetBotConfigWarned = true
        end
        return nil]]
local targetBotItemsLine = [[local t = CaveBotConfigParse() and CaveBotConfigParse()["items"] or nil]]
local targetBotItemsReplacement = [[local config = CaveBotConfigParse()
    local t = config and config.items or nil]]
local targetBotContainersLine = [[local t = CaveBotConfigParse() and CaveBotConfigParse()["containers"] or nil]]
local targetBotContainersReplacement = [[local config = CaveBotConfigParse()
    local t = config and config.containers or nil]]
local targetBotHasLootFunction = [[function CaveBot.HasLootItems()
    for _, container in pairs(getContainers()) do
        local name = container:getName():lower()
        if not name:find("depot") and not name:find("your inbox") then
            for _, item in pairs(container:getItems()) do
                local id = item:getId()
                if table.find(CaveBot.GetLootItems(), id) then
                    return true
                end
            end
        end
    end
end]]
local targetBotHasLootReplacement = [[function CaveBot.HasLootItems()
    local lootItems = {}
    for _, itemId in ipairs(CaveBot.GetLootItems()) do
        lootItems[itemId] = true
    end
    for _, container in pairs(getContainers()) do
        local name = container:getName():lower()
        if not name:find("depot") and not name:find("your inbox") then
            for _, item in pairs(container:getItems()) do
                local id = item:getId()
                if lootItems[id] then
                    return true
                end
            end
        end
    end
end]]

local botFonts = {
  ["verdana-11px-antialised"] = "vbot-verdana-11px-antialised",
  ["verdana-11px-rounded"] = "vbot-verdana-11px-rounded"
}

local function applyBotFonts(widget)
  if not widget then return end

  local font = botFonts[widget:getFont()]
  if font and g_fonts.fontExists(font) then
    widget:setFont(font)
  end

  for _, child in ipairs(widget:getChildren()) do
    applyBotFonts(child)
  end
end

local function applyPendingSettings()
  if not pendingSettings then return end

  g_settings.setNode('bot', pendingSettings)
  pendingSettings = nil
end

local function queueRefresh(settings, delay)
  pendingSettings = settings or pendingSettings
  removeEvent(refreshEvent)
  refreshEvent = scheduleEvent(function()
    refreshEvent = nil
    applyPendingSettings()
    refresh()
  end, delay or 1)
end

local function queueSave()
  removeEvent(saveEvent)
  saveEvent = scheduleEvent(function()
    saveEvent = nil
    save()
  end, 50)
end

local function replaceCompatibilityText(path, replacements)
  if not g_resources.fileExists(path) then return end

  local contents = g_resources.readFileContents(path)
  local changed = false
  for _, replacement in ipairs(replacements) do
    local first, last = contents:find(replacement[1], 1, true)
    if first then
      contents = contents:sub(1, first - 1) .. replacement[2] .. contents:sub(last + 1)
      changed = true
    end
  end

  if changed then
    g_resources.writeFileContents(path, contents)
  end
end

local function migrateBuiltInConfig(configName)
  local configPath = "/bot/" .. configName .. "/vBot/"
  replaceCompatibilityText(configPath .. "analyzer.lua", {
    {analyzerCompatibilityLine, analyzerCompatibilityReplacement}
  })
  replaceCompatibilityText(configPath .. "new_cavebot_lib.lua", {
    {targetBotWarningLine, targetBotWarningReplacement},
    {targetBotItemsLine, targetBotItemsReplacement},
    {targetBotContainersLine, targetBotContainersReplacement},
    {targetBotHasLootFunction, targetBotHasLootReplacement}
  })
end

local function setButtonState(open)
  if botButton then
    botButton:setOn(open)
  end
  if modules.game_sidebuttons then
    modules.game_sidebuttons.setButtonVisible("bot", open)
  end
end

function init()
  dofile("executor")

  g_ui.importStyle("ui/basic.otui")
  g_ui.importStyle("ui/panels.otui")
  g_ui.importStyle("ui/config.otui")
  g_ui.importStyle("ui/icons.otui")
  g_ui.importStyle("ui/container.otui")

  connect(g_game, {
    onGameStart = online,
    onGameEnd = offline,
  })

  botButton = modules.client_topmenu.addRightGameToggleButton('botButton', tr('Bot'), '/images/topbuttons/bot', toggle, false, 99999)
  botButton:setOn(false)
  botButton:hide()

  botWindow = g_ui.loadUI('bot', modules.game_interface.getLeftPanel())
  botWindow:setup()
  applyBotFonts(botWindow)

  contentsPanel = botWindow.contentsPanel
  configList = contentsPanel.config
  enableButton = contentsPanel.enableButton
  statusLabel = contentsPanel.statusLabel
  botMessages = contentsPanel.messages
  botTabs = contentsPanel.botTabs
  botTabs:setContentWidget(contentsPanel.botPanel)

  editWindow = g_ui.displayUI('edit')
  editWindow:hide()
  applyBotFonts(editWindow)

  if g_game.isOnline() then
    clear()
    online()
  end
end

function terminate()
  removeEvent(refreshEvent)
  refreshEvent = nil
  applyPendingSettings()

  save()
  clear()

  disconnect(g_game, {
    onGameStart = online,
    onGameEnd = offline,
  })

  if editWindow then
    editWindow:destroy()
    editWindow = nil
  end

  if botWindow then
    botWindow:destroy()
    botWindow = nil
  end

  if botButton then
    botButton:destroy()
    botButton = nil
  end
end

function clear()
  terminateCallbacks()
  botExecutor = nil
  removeEvent(checkEvent)
  checkEvent = nil
  removeEvent(saveEvent)
  saveEvent = nil
  nextMessageCleanup = 0

  -- optimization, callback is not used when not needed
  g_game.enableTileThingLuaCallback(false)

  if botTabs then
    botTabs:clearTabs()
    botTabs:setOn(false)
  end

  if botMessages then
    botMessages:destroyChildren()
    botMessages:updateLayout()
  end

  for i, socket in pairs(botWebSockets) do
    g_http.cancel(socket)
    botWebSockets[i] = nil
  end

  for i, widget in pairs(g_ui.getRootWidget():getChildren()) do
    if widget.botWidget then
      widget:destroy()
    end
  end
  if modules.game_interface.gameMapPanel then
    for i, widget in pairs(modules.game_interface.gameMapPanel:getChildren()) do
      if widget.botWidget then
        widget:destroy()
      end
    end
  end
  local rightPanel = modules.game_interface.getRightPanel()
  local leftPanel = modules.game_interface.getLeftPanel()
  for _, widget in pairs({rightPanel, leftPanel}) do
    if widget then
      for i, child in pairs(widget:getChildren()) do
        if child.botWidget then
          child:destroy()
        end
      end
    end
  end

  local gameMapPanel = modules.game_interface.getMapPanel()
  if gameMapPanel then
    gameMapPanel:unlockVisibleFloor()
  end

  if g_sounds then
    local channel = g_sounds.getChannel(SoundChannels.Bot)
    if channel then
      channel:stop()
    end
  end
end


function refresh()
  if not g_game.isOnline() then return end
  save()
  clear()

  -- create bot dir
  if not g_resources.directoryExists("/bot") then
    g_resources.makeDir("/bot")
    if not g_resources.directoryExists("/bot") then
      return onError("Can't create bot directory in " .. g_resources.getWriteDir())
    end
  end

  -- get list of configs
  createDefaultConfigs()
  local configs = g_resources.listDirectoryFiles("/bot", false, false)

  -- clean
  configList.onOptionChange = nil
  enableButton.onClick = nil
  configList:clearOptions()

  -- select active config based on settings
  local settings = g_settings.getNode('bot') or {}
  local index = g_game.getCharacterName() .. "_" .. g_game.getClientVersion()
  if settings[index] == nil then
    settings[index] = {
      enabled=false,
      config=""
    }
  end

  -- init list and buttons
  for i=1,#configs do
    configList:addOption(configs[i])
  end
  configList:setCurrentOption(settings[index].config)
  local currentOption = configList:getCurrentOption()
  if currentOption and currentOption.text ~= settings[index].config then
    settings[index].config = currentOption.text
    settings[index].enabled = false
  end

  enableButton:setOn(settings[index].enabled)

  configList.onOptionChange = function(widget)
    settings[index].config = widget:getCurrentOption().text
    queueRefresh(settings)
  end

  enableButton.onClick = function(widget)
    settings[index].enabled = not settings[index].enabled
    queueRefresh(settings)
  end

  if not g_game.isOnline() or not settings[index].enabled then
    statusLabel:setOn(true)
    statusLabel:setText("Status: disabled\nPress off button to enable")
    return
  end

  local configName = settings[index].config
  migrateBuiltInConfig(configName)

  -- storage
  botStorage = {}

  local path = "/bot/" .. configName .. "/storage/"
  if not g_resources.directoryExists(path) then
    g_resources.makeDir(path)
  end

  botStorageFile = path.."profile_" .. g_settings.getNumber('profile') .. ".json"
  if g_resources.fileExists(botStorageFile) then
    local status, result = pcall(function()
      return json.decode(g_resources.readFileContents(botStorageFile))
    end)
    if not status then
      return onError("Error while reading storage (" .. botStorageFile .. "). To fix this problem you can delete storage.json. Details: " .. result)
    end
    botStorage = result
  end

  -- run script
  local status, result = pcall(function()
    return executeBot(configName, botStorage, botTabs, message, queueSave, queueRefresh, botWebSockets, applyBotFonts) end
  )
  if not status then
    clear()
    return onError(result)
  end

  statusLabel:setOn(false)
  botExecutor = result
  applyBotFonts(botWindow)
  initCallbacks()
  check()
end

function save()
  if not botExecutor then
    return
  end

  local settings = g_settings.getNode('bot') or {}
  local index = g_game.getCharacterName() .. "_" .. g_game.getClientVersion()
  if settings[index] == nil then
    return
  end

  local status, result = pcall(function()
    return json.encode(botStorage, 2)
  end)
  if not status then
    return onError("Error while saving bot storage. Storage won't be saved. Details: " .. result)
  end

  if result:len() > 100 * 1024 * 1024 then
    return onError("Storage file is too big, above 100MB, it won't be saved")
  end

  g_resources.writeFileContents(botStorageFile, result)
end

function onMiniWindowClose()
  setButtonState(false)
end

function toggle()
  if botButton:isOn() then
    botWindow:close()
    botButton:setOn(false)
  else
    botWindow:open()
    botButton:setOn(true)
  end
end

function online()
  botButton:show()
  setButtonState(botWindow:isVisible())
  local profiles = modules.client_profiles
  if not profiles or not profiles.ChangedProfile then
    queueRefresh(nil, 20)
  end
end

function offline()
  removeEvent(refreshEvent)
  refreshEvent = nil
  applyPendingSettings()

  save()
  clear()
  botButton:hide()
  setButtonState(false)
  editWindow:hide()
end

function onError(message)
  statusLabel:setOn(true)
  statusLabel:setText("Error:\n" .. message)
  g_logger.error("[BOT] " .. message)
end

function edit()
  local configs = g_resources.listDirectoryFiles("/bot", false, false)
  editWindow.manager.upload.config:clearOptions()
  for i=1,#configs do
    editWindow.manager.upload.config:addOption(configs[i])
  end
  editWindow.manager.download.config:setText("")

  editWindow:show()
  editWindow:focus()
  editWindow:raise()
end

function createDefaultConfigs()
  local defaultConfigFiles = g_resources.listDirectoryFiles("default_configs", false, false)
  for i, config_name in ipairs(defaultConfigFiles) do
    if not g_resources.directoryExists("/bot/" .. config_name) then
      g_resources.makeDir("/bot/" .. config_name)
      if not g_resources.directoryExists("/bot/" .. config_name) then
        return onError("Can't create /bot/" .. config_name .. " directory in " .. g_resources.getWriteDir())
      end

      local defaultConfigFiles = g_resources.listDirectoryFiles("default_configs/" .. config_name, true, false)
      for i, file in ipairs(defaultConfigFiles) do
        local baseName = file:split("/")
        baseName = baseName[#baseName]
        if g_resources.directoryExists(file) then
          g_resources.makeDir("/bot/" .. config_name .. "/" .. baseName)
          if not g_resources.directoryExists("/bot/" .. config_name .. "/" .. baseName) then
            return onError("Can't create /bot/" .. config_name  .. "/" .. baseName .. " directory in " .. g_resources.getWriteDir())
          end
          local defaultConfigFiles2 = g_resources.listDirectoryFiles("default_configs/" .. config_name .. "/" .. baseName, true, false)
          for i, file in ipairs(defaultConfigFiles2) do
            local baseName2 = file:split("/")
            baseName2 = baseName2[#baseName2]
            local contents = g_resources.fileExists(file) and g_resources.readFileContents(file) or ""
            if contents:len() > 0 then
              g_resources.writeFileContents("/bot/" .. config_name .. "/" .. baseName .. "/" .. baseName2, contents)
            end
          end
        else
          local contents = g_resources.fileExists(file) and g_resources.readFileContents(file) or ""
          if contents:len() > 0 then
            g_resources.writeFileContents("/bot/" .. config_name .. "/" .. baseName, contents)
          end
        end
      end
    end
  end
end

function uploadConfig()
  local config = editWindow.manager.upload.config:getCurrentOption().text
  local archive = compressConfig(config)
  if not archive then
      return displayErrorBox(tr("Config upload failed"), tr("Config %s is invalid (can't be compressed)", config))
  end
  if archive:len() > 1024 * 1024 then
      return displayErrorBox(tr("Config upload failed"), tr("Config %s is too big, maximum size is 1024KB. Now it has %s KB.", config, math.floor(archive:len() / 1024)))
  end

  local infoBox = displayInfoBox(tr("Uploading config"), tr("Uploading config %s. Please wait.", config))

  HTTP.postJSON(configManagerUrl .. "?config=" .. config:gsub("%s+", "_"), archive, function(data, err)
    if infoBox then
      infoBox:destroy()
    end
    if err or data["error"] then
      return displayErrorBox(tr("Config upload failed"), tr("Error while upload config %s:\n%s", config, err or data["error"]))
    end
    displayInfoBox(tr("Succesful config upload"), tr("Config %s has been uploaded.\n%s", config, data["message"]))
  end)
end

function downloadConfig()
  local hash = editWindow.manager.download.config:getText()
  if hash:len() == 0 then
      return displayErrorBox(tr("Config download error"), tr("Enter correct config hash"))
  end
  local infoBox = displayInfoBox(tr("Downloading config"), tr("Downloading config with hash %s. Please wait.", hash))
  HTTP.download(configManagerUrl .. "?hash=" .. hash, hash .. ".zip", function(path, checksum, err)
    if infoBox then
      infoBox:destroy()
    end
    if err then
      return displayErrorBox(tr("Config download error"), tr("Config with hash %s cannot be downloaded", hash))
    end
    modules.client_textedit.show("", {
      title="Enter name for downloaded config",
      description="Config with hash " .. hash .. " has been downloaded. Enter name for new config.\nWarning: if config with same name already exist, it will be overwritten!",
      width=500
    }, function(configName)
      decompressConfig(configName, "/downloads/" .. path)
      refresh()
      edit()
    end)
  end)
end

function compressConfig(configName)
  if not g_resources.directoryExists("/bot/" .. configName) then
    return onError("Config " .. configName .. " doesn't exist")
  end
  local forArchive = {}
  for _, file in ipairs(g_resources.listDirectoryFiles("/bot/" .. configName)) do
    local fullPath = "/bot/" .. configName .. "/" .. file
    if g_resources.fileExists(fullPath) then -- regular file
        forArchive[file] = g_resources.readFileContents(fullPath)
    else -- dir
      for __, file2 in ipairs(g_resources.listDirectoryFiles(fullPath)) do
        local fullPath2 = fullPath .. "/" .. file2
        if g_resources.fileExists(fullPath2) then -- regular file
            forArchive[file .. "/" .. file2] = g_resources.readFileContents(fullPath2)
        end
      end
    end
  end
  return g_resources.createArchive(forArchive)
end

function decompressConfig(configName, archive)
  if g_resources.directoryExists("/bot/" .. configName) then
    g_resources.deleteFile("/bot/" .. configName) -- also delete dirs
  end
  local files = g_resources.decompressArchive(archive)
  g_resources.makeDir("/bot/" .. configName)
  if not g_resources.directoryExists("/bot/" .. configName) then
    return onError("Can't create /bot/" .. configName .. " directory in " .. g_resources.getWriteDir())
  end

  for file, contents in pairs(files) do
    local split = file:split("/")
    split[#split] = nil -- remove file name
    local dirPath = "/bot/" .. configName
    for _, s in ipairs(split) do
      dirPath = dirPath .. "/" .. s
      if not g_resources.directoryExists(dirPath) then
        g_resources.makeDir(dirPath)
        if not g_resources.directoryExists(dirPath) then
          return onError("Can't create " .. dirPath .. " directory in " .. g_resources.getWriteDir())
        end
      end
    end
    g_resources.writeFileContents("/bot/" .. configName .. "/" .. file, contents)
  end
end

-- Executor
function message(category, msg)
  local widget = g_ui.createWidget('BotLabel', botMessages)
  applyBotFonts(widget)
  widget.added = g_clock.millis()
  if category == 'error' then
    widget:setText(msg)
    widget:setColor("red")
    g_logger.error("[BOT] " .. msg)
  elseif category == 'warn' then
    widget:setText(msg)
    widget:setColor("yellow")
    g_logger.warning("[BOT] " .. msg)
  elseif category == 'info' then
    widget:setText(msg)
    widget:setColor("white")
    g_logger.info("[BOT] " .. msg)
  end

  if botMessages:getChildCount() > 5 then
    botMessages:getFirstChild():destroy()
  end
end

function check()
  removeEvent(checkEvent)
  checkEvent = nil
  if not botExecutor then
    return
  end

  checkEvent = scheduleEvent(check, 10)

  local status, result = pcall(function()
    return botExecutor.script()
  end)
  if not status then
    removeEvent(checkEvent)
    checkEvent = nil
    terminateCallbacks()
    g_game.enableTileThingLuaCallback(false)
    botExecutor = nil -- critical
    return onError(result)
  end

  local now = g_clock.millis()
  if now >= nextMessageCleanup then
    nextMessageCleanup = now + 250
    local widget = botMessages:getFirstChild()
    if widget and widget.added + 5000 < now then
      widget:destroy()
    end
  end
end

-- Callbacks
local function getCallbackConnections()
  if callbackConnections then return callbackConnections end

  callbackConnections = {
    {rootWidget, {
      onKeyDown = botKeyDown,
      onKeyUp = botKeyUp,
      onKeyPress = botKeyPress
    }},
    {g_game, {
      onTalk = botOnTalk,
      onTextMessage = botOnTextMessage,
      onLoginAdvice = botOnLoginAdvice,
      onUse = botOnUse,
      onUseWith = botOnUseWith,
      onChannelList = botChannelList,
      onOpenChannel = botOpenChannel,
      onCloseChannel = botCloseChannel,
      onChannelEvent = botChannelEvent,
      onImbuementWindow = botImbuementWindow,
      onModalDialog = botModalDialog,
      onAttackingCreatureChange = botAttackingCreatureChange,
      onGameEditText = botGameEditText,
      onSpellCooldown = botSpellCooldown,
      onSpellGroupCooldown = botGroupSpellCooldown
    }},
    {Tile, {
      onAddThing = botAddThing,
      onRemoveThing = botRemoveThing
    }},
    {Creature, {
      onAppear = botCreatureAppear,
      onDisappear = botCreatureDisappear,
      onPositionChange = botCreaturePositionChange,
      onHealthPercentChange = botCraetureHealthPercentChange,
      onTurn = botCreatureTurn,
      onWalk = botCreatureWalk
    }},
    {LocalPlayer, {
      onManaChange = botManaChange,
      onStatesChange = botStatesChange,
      onInventoryChange = botInventoryChange
    }},
    {Container, {
      onOpen = botContainerOpen,
      onClose = botContainerClose,
      onUpdateItem = botContainerUpdateItem,
      onAddItem = botContainerAddItem,
      onRemoveItem = botContainerRemoveItem
    }},
    {g_map, {
      onMissle = botOnMissle,
      onAnimatedText = botOnAnimatedText,
      onStaticText = botOnStaticText
    }}
  }
  return callbackConnections
end

function initCallbacks()
  if callbacksConnected then return end

  for _, connection in ipairs(getCallbackConnections()) do
    connect(connection[1], connection[2])
  end
  callbacksConnected = true
end

function terminateCallbacks()
  if not callbacksConnected then return end

  for _, connection in ipairs(getCallbackConnections()) do
    disconnect(connection[1], connection[2])
  end
  callbacksConnected = false
end

function safeBotCall(func, ...)
  local status, result = pcall(func, ...)
  if not status then
    if botExecutor then
      botExecutor.resetCurrentExecution()
    end
    onError(result)
  end
end

local function dispatchBotCallback(callbackName, ...)
  local executor = botExecutor
  if not executor then return false end
  safeBotCall(executor.callbacks[callbackName], ...)
end

function botKeyDown(widget, keyCode, keyboardModifiers)
  if keyCode == KeyUnknown then return end
  return dispatchBotCallback("onKeyDown", keyCode, keyboardModifiers)
end

function botKeyUp(widget, keyCode, keyboardModifiers)
  if keyCode == KeyUnknown then return end
  return dispatchBotCallback("onKeyUp", keyCode, keyboardModifiers)
end

function botKeyPress(widget, keyCode, keyboardModifiers, autoRepeatTicks)
  if keyCode == KeyUnknown then return end
  return dispatchBotCallback("onKeyPress", keyCode, keyboardModifiers, autoRepeatTicks)
end

function botOnTalk(...)
  return dispatchBotCallback("onTalk", ...)
end

function botOnTextMessage(...)
  return dispatchBotCallback("onTextMessage", ...)
end

function botOnLoginAdvice(...)
  return dispatchBotCallback("onLoginAdvice", ...)
end

function botAddThing(...)
  return dispatchBotCallback("onAddThing", ...)
end

function botRemoveThing(...)
  return dispatchBotCallback("onRemoveThing", ...)
end

function botCreatureAppear(...)
  return dispatchBotCallback("onCreatureAppear", ...)
end

function botCreatureDisappear(...)
  return dispatchBotCallback("onCreatureDisappear", ...)
end

function botCreaturePositionChange(...)
  return dispatchBotCallback("onCreaturePositionChange", ...)
end

function botCraetureHealthPercentChange(...)
  return dispatchBotCallback("onCreatureHealthPercentChange", ...)
end

function botOnUse(...)
  return dispatchBotCallback("onUse", ...)
end

function botOnUseWith(...)
  return dispatchBotCallback("onUseWith", ...)
end

function botContainerOpen(...)
  return dispatchBotCallback("onContainerOpen", ...)
end

function botContainerClose(...)
  return dispatchBotCallback("onContainerClose", ...)
end

function botContainerUpdateItem(...)
  return dispatchBotCallback("onContainerUpdateItem", ...)
end

function botOnMissle(...)
  return dispatchBotCallback("onMissle", ...)
end

function botOnAnimatedText(...)
  return dispatchBotCallback("onAnimatedText", ...)
end

function botOnStaticText(...)
  return dispatchBotCallback("onStaticText", ...)
end

function botChannelList(...)
  return dispatchBotCallback("onChannelList", ...)
end

function botOpenChannel(...)
  return dispatchBotCallback("onOpenChannel", ...)
end

function botCloseChannel(...)
  return dispatchBotCallback("onCloseChannel", ...)
end

function botChannelEvent(...)
  return dispatchBotCallback("onChannelEvent", ...)
end

function botCreatureTurn(...)
  return dispatchBotCallback("onTurn", ...)
end

function botCreatureWalk(...)
  return dispatchBotCallback("onWalk", ...)
end

function botImbuementWindow(...)
  return dispatchBotCallback("onImbuementWindow", ...)
end

function botModalDialog(...)
  return dispatchBotCallback("onModalDialog", ...)
end

function botGameEditText(...)
  return dispatchBotCallback("onGameEditText", ...)
end

function botAttackingCreatureChange(...)
  return dispatchBotCallback("onAttackingCreatureChange", ...)
end

function botManaChange(...)
  return dispatchBotCallback("onManaChange", ...)
end

function botStatesChange(...)
  return dispatchBotCallback("onStatesChange", ...)
end

function botContainerAddItem(...)
  return dispatchBotCallback("onAddItem", ...)
end

function botContainerRemoveItem(...)
  return dispatchBotCallback("onRemoveItem", ...)
end

function botSpellCooldown(...)
  return dispatchBotCallback("onSpellCooldown", ...)
end

function botGroupSpellCooldown(...)
  return dispatchBotCallback("onGroupSpellCooldown", ...)
end

function botInventoryChange(...)
  return dispatchBotCallback("onInventoryChange", ...)
end
