local consolePanel

SayModes = {
  [1] = { messageType = MessageModes.Whisper, icon = '/images/game/console/whisper' },
  [2] = { messageType = MessageModes.Say, icon = '/images/game/console/say' },
  [3] = { messageType = MessageModes.Yell, icon = '/images/game/console/yell' }
}

ChannelEventFormats = {
  [ChannelEvent.Join] = '%s joined the channel.',
  [ChannelEvent.Leave] = '%s left the channel.',
  [ChannelEvent.Invite] = '%s has been invited to the channel.',
  [ChannelEvent.Exclude] = '%s has been removed from the channel.',
}

local chatEnabled = true
local currentTextMessage = ''
local chatToggleActive
local consoleToggleChat
local chatToggleLocked
local gameChannelInitEvent
local temporaryChatEnableEvent

GameChannelInialized = false

g_chat = nil
g_channel = nil

MAX_LINES = 200
MAX_MESSAGE_PER_SECOND = 20
MAX_HISTORY = 500

if not ChannelConfig then
  ChannelConfig = {}
end

function init()
  consolePanel = g_ui.loadUI('console', m_interface.getBottomPanel())

  local consoleTextEdit = consolePanel:recursiveGetChildById('consoleTextEdit')
  local consoleContentPanel = consolePanel:recursiveGetChildById('consoleContentPanel')
  local consoleTabBar = consolePanel:recursiveGetChildById('consoleTabBar')
  consoleTabBar:setContentWidget(consoleContentPanel)

  -- create default channels
  g_chat = Chat.new(consolePanel, MAX_LINES)
  g_channel = Channel.new()

  consoleTabBar.onIndexChange = function(oldIndex, newIndex)
    Options.swapChannel(oldIndex, newIndex)
  end

  load()

  consolePanel.onKeyPress = function(self, keyCode, keyboardModifiers)
    if not (keyboardModifiers == KeyboardCtrlModifier and keyCode == KeyC) then return false end

    local selection = g_chat:getBuffer().selectionText
    if not selection then
      selection = g_chat:getReadOnlyBuffer().selectionText
      if not selection then
        return false
      end
    end

    self:onCopyText(selection)
    return true
  end

  g_keyboard.bindKeyPress('Shift+Up', function() navigateMessageHistory(1) end, consolePanel)
  g_keyboard.bindKeyPress('Shift+Down', function() navigateMessageHistory(-1) end, consolePanel)
  g_keyboard.bindKeyDown('Escape', function() toggle() end, consolePanel)

  -- apply buttom functions after loaded
  consoleTabBar:setNavigation(consolePanel:getChildById('prevChannelButton'), consolePanel:getChildById('nextChannelButton'))

  consoleToggleChat = consolePanel:recursiveGetChildById('toggleChat')

  connect(g_game, {
    onTalk = onTalk,
    onTextMessage = onTextMessage,

    onChannelList = onChannelList,
    onOpenChannel = onOpenChannel,
    onCloseChannel = onCloseChannel,
    onChannelEvent = onChannelEvent,
    onOpenPrivateChannel = onOpenPrivateChannel,
    onOpenOwnPrivateChannel = onOpenOwnPrivateChannel,

    onGameStart = onGameStart,
    onGameEnd = onGameEnd,
  })

  if g_game.isOnline() then
    onGameStart()
  end
end

function terminate()
  removeEvent(gameChannelInitEvent)
  removeEvent(temporaryChatEnableEvent)
  gameChannelInitEvent = nil
  temporaryChatEnableEvent = nil
  save()
  disconnect(g_game, {
    onTalk = onTalk,
    onTextMessage = onTextMessage,

    onChannelList = onChannelList,
    onOpenChannel = onOpenChannel,
    onCloseChannel = onCloseChannel,
    onChannelEvent = onChannelEvent,
    onOpenPrivateChannel = onOpenPrivateChannel,
    onOpenOwnPrivateChannel = onOpenOwnPrivateChannel,

    onGameStart = onGameStart,
    onGameEnd = onGameEnd,
  })

  g_chat:terminate()

  Communication:saveSettings()
end

function save()
  local settings = {}
  settings.messageHistory = g_chat:getMessageHistory()
  g_settings.setNode('game_console', settings)
end

function getConsole()
  return consolePanel:recursiveGetChildById('consoleTextEdit')
end

function sendCurrentMessage(defaultKeybind)
  local consoleTextEdit = consolePanel:recursiveGetChildById('consoleTextEdit')
  local message = consoleTextEdit:getText()
  if #message == 0 then
    if defaultKeybind and chatEnabled then
      sendTemporaryMessage()
    end
    return
  end

  -- hot fix
  if not chatToggleActive and #consoleTextEdit:getText() == 0 then
    return
  end

  g_chat:sendCurrentMessage()
end

function addText(text, speaktype, tabName, creatureName, level, statement)
  g_chat:addText(text, speaktype, tabName, creatureName, level, statement)
end

function switchMode(newView)
  if newView then
    consolePanel:setImageColor('#ffffff88')
  else
    consolePanel:setImageColor('white')
  end
end

function isChatEnabled()
  return chatEnabled
end

function sendMessage(message)
  g_chat:sendMessage(message)
end

function sendNpcMessage(message)
  if not g_chat or not message or message == '' then
    return false
  end

  local npcTab = g_chat:getTabByName(NPC_NAME_CHAT) or g_chat:addTabMessages(NPC_NAME_CHAT, true)
  if not npcTab then
    return false
  end

  g_chat:sendMessage(message, npcTab)
  return true
end

function enableChat(temporarily)
  if g_app.isMobile() then return end
  if chatToggleLocked then return end

  if consoleToggleChat:isChecked() then
    return consoleToggleChat:setChecked(false)
  end

  local consoleTextEdit = consolePanel:recursiveGetChildById('consoleTextEdit')
  consoleTextEdit:enable()
  consoleTextEdit:setText(currentTextMessage)
  currentTextMessage = ''
  consoleTextEdit:setCursorPos(-1)
  consoleTextEdit:focus()

  modules.game_walking.disableWSAD()

  consoleToggleChat:setTooltip(tr("Enable/disable chat"))
end

function disableChat()
  if g_app.isMobile() then return end
  if chatToggleLocked then return end
  if not consoleToggleChat:isChecked() then
    return consoleToggleChat:setChecked(true)
  end

  currentTextMessage = consoleTextEdit:getText()
  consoleTextEdit:setText("")
  consoleTextEdit:disable()

  modules.game_walking.enableWSAD()

  consoleToggleChat:setTooltip(tr("Enable/disable chat"))
end

function setChatState(active)
	local toggleChatButton = consolePanel:recursiveGetChildById('toggleChat')
  local consoleTextEdit = consolePanel:recursiveGetChildById('consoleTextEdit')
	toggleChatButton:setText(tr('Chat %s', active and "On" or "Off"))
    consoleTextEdit:setEnabled(active)
    chatToggleActive = active
	if active then
    chatEnabled = true
	  if modules.game_walking then modules.game_walking.disableWSAD() end
	else
    chatEnabled = false
	  if modules.game_walking then modules.game_walking.enableWSAD() end
	end
end

function toggleChat()
  if modules.game_interface.isInternalLocked() then
    return
  end

  local invisibleClick = consolePanel.parentPanel:recursiveGetChildById('invisibleClick')
  if invisibleClick then
    invisibleClick:destroy()
  end

  local toggleChatButton = consolePanel:recursiveGetChildById('toggleChat')
  local consoleTextEdit = consolePanel:recursiveGetChildById('consoleTextEdit')
  if chatToggleActive then
    toggleChatButton:setText(tr('Chat Off'))
    consoleTextEdit:setEnabled(false)
    local invisibleClick = g_ui.createWidget('ClickConsole', consolePanel.parentPanel)
    invisibleClick.onClick = toggleChat
    chatToggleActive = false
    modules.game_actionbar.switchChatMode(false)
    modules.game_walking.enableWSAD()
    chatEnabled = false
  else
    toggleChatButton:setText(tr('Chat On'))
    consoleTextEdit:setEnabled(true)
    consoleTextEdit:focus()
    chatToggleActive = true
    modules.game_walking.disableWSAD()
	  modules.game_actionbar.switchChatMode(true)
    chatEnabled = true
  end
end

function sendTemporaryMessage()
  local toggleChatButton = consolePanel:recursiveGetChildById('toggleChat')
  if toggleChatButton:getText() == 'Chat On*' then
    local consoleTextEdit = consolePanel:recursiveGetChildById('consoleTextEdit')
    local message = consoleTextEdit:getText()
    if #message > 0 then
      modules.game_console.sendCurrentMessage()
    end
    chatEnabled = false
    modules.game_actionbar.switchChatMode(false)
    modules.game_walking.enableWSAD()
    toggleChatButton:setText(tr('Chat Off'))
    consoleTextEdit:setEnabled(false)
  end
end

function onEnterPressed()
  local toggleChatButton = consolePanel:recursiveGetChildById('toggleChat')
  local invisibleClick = consolePanel.parentPanel:recursiveGetChildById('invisibleClick')
  if invisibleClick then
    invisibleClick:destroy()
  end

  if not m_interface.getRootPanel():isFocused() then return end

  modules.game_walking.stopSmartWalk()

  if not chatToggleActive then
    removeEvent(temporaryChatEnableEvent)
    temporaryChatEnableEvent = nil
    local consoleTextEdit = consolePanel:recursiveGetChildById('consoleTextEdit')
    if chatEnabled then
      toggleChatButton:setText(tr('Chat Off'))
      consoleTextEdit:setEnabled(false)
      local invisibleClick = g_ui.createWidget('ClickConsole', consolePanel.parentPanel)
      invisibleClick.onClick = toggleChat
      chatEnabled = false
      modules.game_actionbar.switchChatMode(false)
      modules.game_walking.enableWSAD()
    else
      toggleChatButton:setText(tr('Chat On*'))
      consoleTextEdit:setEnabled(true)
      consoleTextEdit:focus()
      modules.game_walking.disableWSAD()
      modules.game_actionbar.switchChatMode(true)
      temporaryChatEnableEvent = scheduleEvent(function()
        temporaryChatEnableEvent = nil
        if g_game.isOnline() and consoleTextEdit:isEnabled() and not chatToggleActive then
          chatEnabled = true
        end
      end, 10)
    end
  end
end

function removeCurrentTab()
  g_chat:removeCurrentTab()
end

function clearOrSelectText()
  local consoleTextEdit = consolePanel:recursiveGetChildById('consoleTextEdit')
  if string.len(consoleTextEdit:getText()) == 0 then
    g_chat:selectAll()
  else
    consoleTextEdit:clearText()
  end
end

function hasOwnPrivateTab()
  return g_chat:hasOwnPrivateTab()
end

function sayModeChange(mode)
  g_chat:sayModeChange(mode)
end

function load()
  local settings = g_settings.getNode('game_console')
  if settings then
    g_chat:setMessageHistory(settings.messageHistory or {})
  end
  Communication:loadSettings()
end

function doCreateChannelWindow()
  local window = g_ui.displayUI('channelswindow')
  g_channel:setChannelWindow(window)
end

function doCreateCommunicationWindow()
  local window = g_ui.displayUI('communicationwindow')
  Communication:setWindow(window)
end

function navigateMessageHistory(step)
  g_chat:navigateMessageHistory(step)
end

function nextChannel()
  g_chat:selectNextTab()
end

function getTabByName(name)
	return g_chat:getTabByName(name)
end

function prevChannel()
  g_chat:selectPrevTab()
end

function selectDefault()
  g_chat:selectDefaultChannel()
end

function openHelp()
  g_game.joinChannel(HELP_CHANNEL)
end

function openLootChannel()
  g_channel:onOpenChannel(LOOT_CHANNEL_ID, "Loot")
  g_chat:addChannelConfig("Loot", LOOT_CHANNEL_ID)
end

function openSpellChannel()
  g_channel:onOpenChannel(SPELL_CHANNEL_ID, SPELL_CHANNEL_NAME)
  g_chat:addChannelConfig(SPELL_CHANNEL_NAME, SPELL_CHANNEL_ID)
end

function syncSpellChannelVisibility(visible)
  if visible == nil then
    visible = m_settings.getOption('showSpellChat')
  end

  local tab = g_chat:getTabByName(SPELL_CHANNEL_NAME)
  if visible and not tab then
    openSpellChannel()
  elseif not visible and tab then
    closeSpellChannel()
  end
end

function closeSpellChannel()
  if g_chat:getCurrentTabName() == SPELL_CHANNEL_NAME then
    selectDefault()
  end
  g_chat:removeTabByName(SPELL_CHANNEL_NAME)
end

function openNPCChannel()
  g_chat:addTabMessages('NPCs', true)
  g_chat:addChannelConfig('NPCs', 0)
end

function openServerChannel()
   g_chat:selectServerChannel()
end

function getChatLocked() -- ??
  return not chatToggleActive
end

function lockChat()
  if chatToggleLocked then return end
  chatToggleLocked = true
  consoleToggleChat:disable()
  if not consoleToggleChat:isChecked() then
    local consoleTextEdit = consolePanel:recursiveGetChildById('consoleTextEdit')
    currentTextMessage = consoleTextEdit:getText()
    consoleTextEdit:setText("")
    consoleTextEdit:disable()
  end
end

function unlockChat()
  if not chatToggleLocked then return end
  chatToggleLocked = false
  consoleToggleChat:enable()
  if not consoleToggleChat:isChecked() then
    local consoleTextEdit = consolePanel:recursiveGetChildById('consoleTextEdit')
    consoleTextEdit:enable()
    consoleTextEdit:setText(currentTextMessage)
    currentTextMessage = ''
    consoleTextEdit:setCursorPos(-1)
  end
end

-------- Events
function onGameStart()
  local benchmark = g_clock.millis()
  removeEvent(gameChannelInitEvent)
  removeEvent(temporaryChatEnableEvent)
  gameChannelInitEvent = nil
  temporaryChatEnableEvent = nil
  g_chat:online()
  setChatState(Options.isChatOnEnabled)

  gameChannelInitEvent = scheduleEvent(function()
    gameChannelInitEvent = nil
    if g_game.isOnline() then
      GameChannelInialized = true
    end
  end, 2000)

  for _, id in pairs(Options.getSavedChannels()) do
    g_game.joinChannel(tonumber(id))
    if tonumber(id) == LOOT_CHANNEL_ID then
      g_channel:onOpenChannel(tonumber(id), "Loot")
    end
  end

  syncSpellChannelVisibility()
  
  consoleln("Console loaded in " .. (g_clock.millis() - benchmark) / 1000 .. " seconds.")
end

function onGameEnd()
  removeEvent(gameChannelInitEvent)
  removeEvent(temporaryChatEnableEvent)
  gameChannelInitEvent = nil
  temporaryChatEnableEvent = nil
  GameChannelInialized = false
  for k, v in pairs(g_chat:getTabsName()) do
    if not v:isLocalChat() and not v:isServerLogChat() and not v:isSpellChannel() then
      g_chat:removeTabByName(k)
    end
  end

  g_chat:offline()
end

function onTalk(name, level, mode, text, channelId, pos, statement, groupId)
  g_chat:onTalk(name, level, mode, text, channelId, pos, statement, groupId)
end

function onTextMessage(mode, text)
  g_chat:onTextMessage(mode, text)
end

function onChannelList(channelList)
  g_channel:onChannelList(channelList)
end

function onOpenChannel(channelId, channelName, participants)
  g_channel:onOpenChannel(channelId, channelName, participants)
end

function onCloseChannel(channelId)
  g_channel:onCloseChannel(channelId)
end

function onOpenPrivateChannel(name)
  g_channel:onOpenPrivateChannel(name)
end

function onOpenOwnPrivateChannel(channelId, name)
  g_channel:onOpenOwnPrivateChannel(channelId, name)
end

function onChannelEvent(channelId, name, type)
  g_channel:onChannelEvent(channelId, name, type)
end

function updateCurrentTab()
  g_chat:updateCurrent()
end

function toggle()
  if (g_settings.getBoolean('escWasdToggle') or g_settings.getBoolean('enterWasdToggle')) and not chatToggleLocked then
    if not consoleToggleChat:isChecked() then
      disableChat()
    else
      enableChat()
    end
  end
end

function onPlayerUnload()
  local option = {
		[1] = {name = LOCAL_CHAT_NAME, channel = 0},
		[2] = {name = SERVER_LOG_NAME, channel = 0},
    [3] = {name = SPELL_CHANNEL_NAME, channel = SPELL_CHANNEL_ID},
  }

  local tabBar = consolePanel:recursiveGetChildById('consoleTabBar')
  for i = 1, #tabBar:getChildren() do
    local channel = tabBar:getChildren()[i]
    local find = false
    for _, c in ipairs(option) do
        if c.name == channel.fullName then
            find = true
            break
        end
    end

    if not find then
      option[#option + 1] = {
        name = channel.fullName,
        channel = channel.channelId or 0
      }
    end

  end

  modules.game_sidebars.setChannelOptions(option)
end

function onPlayerLoad(channelsOpen)
  if Options.getReadOnlyChannel() then
    g_chat:setupReadOnly(Options.getReadOnlyChannel())
  end

  -- if channelsOpen then
  --   for i, channel in ipairs(channelsOpen) do
  --     local tab = g_chat:getTabByName(channel.name)
  --     if tab then
  --       local widget = tab:getWidget()
  --       if widget then
  --         widget:getParent():moveTab(widget, #widget:getParent():getChildren())
  --       end
  --     end
  --   end
  -- end
end
