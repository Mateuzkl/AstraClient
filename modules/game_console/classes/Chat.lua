Chat = {}
function Chat.new(consolePanel, maxMessages)
    local obj = {
        textEdit = consolePanel:recursiveGetChildById('consoleTextEdit'),
        contentPanel = consolePanel:recursiveGetChildById('consoleContentPanel'),
        tabBar = consolePanel:recursiveGetChildById('consoleTabBar'),
        buffer = consolePanel:recursiveGetChildById('consoleBuffer'),
        sayButton = consolePanel:recursiveGetChildById('sayModeButton'),
        closeChannelButton = consolePanel:recursiveGetChildById('closeChannelButton'),
        readOnly = consolePanel:recursiveGetChildById('readOnly'),
        readOnlyPanel = consolePanel:recursiveGetChildById('consoleReadyOnlyPanel'),
        readOnlyBuffer = consolePanel:recursiveGetChildById('consoleReadyOnlyBuffer'),
        readOnlyLabels = {},
        tabs = {},
        tabsById = {},
        tabsByName = {},
        tabsServerLog = {},
        labels = {},
        currentTab = '',
        maxMessages = maxMessages,
        messageHistory = {},
        currentMessageIndex = 0,
        ownPrivateTab = false,
        loadeddefaultchannel = false,
    }
    setmetatable(obj, { __index = Chat })
    obj:setup()

    return obj
end

function Chat:terminate()
    for _, tab in ipairs(self.tabs) do
        tab:stopSlowMode()
    end
end

function Chat:setOwnPrivateChat(v)
    self.ownPrivateTab = v
end

function Chat:hasOwnPrivateTab(v)
    return self.ownPrivateTab
end

function Chat:onTabChange(tab)
    self:clearSelection()
    local lastTabMessage = self:getTabByName(self.currentTab)
    if lastTabMessage then
        lastTabMessage:stopSlowMode()
        lastTabMessage:setCurrent(false)
    end


    local tabMessage = self:getTabByName(tab.fullName)
    if tabMessage then
        self.currentTab = tabMessage:getName()
        tabMessage:setCurrent(true)

        if tabMessage:isServerLogChat() or tabMessage:isLocalChat() or tabMessage:isSpellChannel() then
            self.closeChannelButton:hide()
        else
            self.closeChannelButton:show()
        end

        if tabMessage:isLocalChat() then
            self.textEdit:setColor("#dfdfdf")
        else
            self.textEdit:setColor("#9f9ffe")
        end

        tabMessage:updateLabels()
        self:onSelectTab()
    end
end

function Chat:setupLabel(label, buffer)
    label.onMouseRelease = function(widget, mousePos, mouseButton)
        if label.message then
            label.message:handleMouseRelease(widget, mousePos, mouseButton)
        end
    end

    label.onMousePress = function(widget, mousePos, button)
        if button == MouseLeftButton then
            self:clearSelection(buffer)
        end
    end
    label.onDragEnter = function(widget, mousePos)
        self:clearSelection(buffer)
        return true
    end
    label.onDragLeave = function(widget, droppedWidget, mousePos)
        if label.message then
            label.message:handleDragLeave(widget)
        end
        return true
    end
    label.onDragMove = function(widget, mousePos, mouseMoved)
        if label.message then
            label.message:handleDragMove(widget, mousePos)
        end
        return true
    end

    label.onDoubleClick = function(widget, mousePos)
        if label.message then
            label.message:selectWordFromPos(widget, buffer)
        end
        return true
    end
end

function Chat:setup()
    for i = 1, self.maxMessages do
        local widget = g_ui.createWidget('ConsoleLabel', self.buffer)
        widget:hide()
        widget:setId('Label_'..i)
        widget.readOnly = false

        self:setupLabel(widget, self.buffer)
        table.insert(self.labels, widget)

        widget = g_ui.createWidget('ConsoleLabel', self.readOnlyBuffer)
        widget:hide()
        widget:setId('ReadOnlyLabel_'..i)
        widget.readOnly = true

        self:setupLabel(widget, self.readOnlyBuffer)
        table.insert(self.readOnlyLabels, widget)
    end

    self.tabBar.onTabChange = function(widget, tab)
        self:onTabChange(tab)
    end

    self.readOnly.onMouseRelease = function(widget, mousePos, mouseButton)
        if mouseButton ~= MouseRightButton then
            return
        end

        if not self.readOnlyTabMessage or not self.readOnlyTabMessage:isFixed() then
            self:displayReadOnlyOptions()
            return
        end

        self:setupReadOnlyButton()
    end

    self.readOnly.onHoverChange = function(widget, hovered)
      if hovered and g_ui.getDraggingWidget() then
        widget:setBorderColor("white")
        widget:setBorderWidth(2)
      else
        widget:setBorderColor("alpha")
        widget:setBorderWidth(0)
      end
    end

    self.tabBar.onTabDrop = function(tabBar, tab, droppedTab, pos)
        self:setupReadOnly(tab.fullName)
    end

    if m_settings.getOption('showSpellChat') then
        self:addTabMessages(SPELL_CHANNEL_NAME)
    else
        self:removeTabByName(SPELL_CHANNEL_NAME)
    end
    self:addTabMessages(SERVER_LOG_NAME)
    local tab = self:addTabMessages(LOCAL_CHAT_NAME)
    self.currentTab = LOCAL_CHAT_NAME
    tab:setCurrent(true)

    self:addChannelConfig(LOCAL_CHAT_NAME, 0)
    self:addChannelConfig(SERVER_LOG_NAME, 0)
    self:addChannelConfig(SPELL_CHANNEL_NAME, SPELL_CHANNEL_ID)
end

function Chat:isReadOnlyActive()
    return self.contentPanel:isOn()
end

function Chat:showReadOnly()
    self.contentPanel:setOn(true)
    self.readOnlyPanel:show()
end

function Chat:hideReadOnly()
    self.contentPanel:setOn(false)
    self.readOnlyPanel:hide()
end

function Chat:online()
    for _, tab in ipairs(self.tabs) do
        tab:clearMessages()
    end
    local localChat = self:getTabByName(LOCAL_CHAT_NAME)
    if localChat then
        localChat:select()
    end
end

function Chat:getTabs()
    return self.tabs
end

function Chat:getTabsName()
    return self.tabsByName
end

function Chat:offline()
    for _, tab in ipairs(self.tabs) do
        tab:offline()
        tab:clearMessages()
    end

    self:closeReadOnly()

    self.loadeddefaultchannel = false
    modules.game_console.save()
end

function Chat:getReadOnlyLabels()
    return self.readOnlyLabels
end

function Chat:getReadOnlyBuffer()
    return self.readOnlyBuffer
end

function Chat:getReadOnlyTabMessages()
    return self.readOnlyTabMessage
end

function Chat:getLabels()
    return self.labels
end

function Chat:getMessageHistory()
    return self.messageHistory
end

function Chat:getCurrentMessageIndex()
    return self.currentMessageIndex
end

function Chat:setMessageHistory(history)
    self.messageHistory = {}

    local entries = {}
    for a, message in pairs(history) do
        local index = tonumber(a)
        if index and message then
            table.insert(entries, { index = index, message = message })
        end
    end

    table.sort(entries, function(a, b) return a.index < b.index end)
    for _, entry in ipairs(entries) do
        self:addMessageHistory(entry.message)
    end
    self.currentMessageIndex = 0
end

function Chat:getCurrentTab()
    return self.tabsByName[self.currentTab]
end

function Chat:getCurrentTabName()
    return self.currentTab
end

function Chat:getBuffer()
    return self.buffer
end

function Chat:reorderChildren()
    self.buffer:reorderChildren(self.labels)
end

function Chat:addTabMessages(name, focus)
    local tab = self:getTabByName(name)
    if tab then
        focus = true
    else
        tab = TabMessages.new(name, self.tabBar)
        table.insert(self.tabs, tab)
        self.tabsByName[name] = tab
    end

    if name == NPC_NAME_CHAT then
        focus = true
    end

    if focus or name == LOCAL_CHAT_NAME then
        tab:select()
    end
    return tab
end

function Chat:getTabById(id)
    for i, tab in ipairs(self.tabs) do
        if tab:getId() == id then
            return tab
        end
    end
end

function Chat:getTabByName(name)
    return self.tabsByName[name]
end

function Chat:addChannelConfig(name, id)
    local find = false
    for i, channel in ipairs(ChannelConfig) do
        if channel.name == name then
            find = true
            break
        end
    end

    if not find then
        ChannelConfig[#ChannelConfig + 1] = {name = name, channel = id}
    end
end

function Chat:removeTabById(id)
    local tab = self:getTabById(id)
    local isOwnerPrivate = tab and tab:isOwnerPrivate()
    if tab then
        self.tabsServerLog[tab:getName()] = nil
        self.tabsByName[tab:getName()] = nil
        tab:destroy()
    end
    self.tabsById[id] = nil

    for i, channel in ipairs(ChannelConfig) do
        if channel.channel == id then
            table.remove(ChannelConfig, i)
            break
        end
    end

    for i, tab in ipairs(self.tabs) do
        if tab:getId() == id then
            table.remove(self.tabs, i)
            Options.removeChannel(tab:getId())
            break
        end
    end

    if isOwnerPrivate then
        self.ownPrivateTab = false
    end
end

function Chat:reopenChannels()
     g_game.doThing(false)
     for i, tab in ipairs(self.tabs) do
        local isOwnerPrivate = tab and tab:isOwnerPrivate()
        if not isOwnerPrivate and tab:getName() ~= LOCAL_CHAT_NAME and tab:getName() ~= SERVER_LOG_NAME and tab:getName() ~= SPELL_CHANNEL_NAME then
            if tab:getId() > 0 and tab:getId() < SPELL_CHANNEL_ID then
                g_game.joinChannel(tab:getId())
            end
        end
    end
    g_game.doThing(true)
end

function Chat:removeTabByName(name)
    local tab = self:getTabByName(name)
    local isOwnerPrivate = tab and tab:isOwnerPrivate()

    if tab then
        tab:destroy()
    end
    self.tabsByName[name] = nil
    self.tabsServerLog[name] = nil

    for i, channel in ipairs(ChannelConfig) do
        if channel.name == name then
            table.remove(ChannelConfig, i)
            break
        end
    end

    for i, tab in ipairs(self.tabs) do
        if tab:getName() == name then
            table.remove(self.tabs, i)

            if g_game.isOnline() then
                Options.removeChannel(tab:getId())
            end
            break
        end
    end

    if isOwnerPrivate then
        self.ownPrivateTab = false
    end
end

function Chat:removeCurrentTab()
    local currentTab = self.currentTab
    if self.currentTab ~= LOCAL_CHAT_NAME and self.currentTab ~= SERVER_LOG_NAME and self.currentTab ~= SPELL_CHANNEL_NAME then
        local tabMessage = self:getTabByName(currentTab)
        if tabMessage and tabMessage:getId() > 0 and tabMessage:getId() < SPELL_CHANNEL_ID then
            g_game.leaveChannel(tabMessage:getId())
        end
        self:selectPrevTab()
        self:removeTabByName(currentTab)
    end
end

function Chat:addTabActiveServerLog(tab)
    self.tabsServerLog[tab:getName()] = tab
end

function Chat:removeTabActiveServerLog(tab)
    self.tabsServerLog[tab:getName()] = nil
end

function Chat:getTabActiveServerLog()
    return self.tabsServerLog
end

function Chat:isServerTab(tab)
    return self.tabsServerLog[tab:getName()] and true or false
end

function Chat:selectDefaultChannel()
    local tab = self:getTabByName(LOCAL_CHAT_NAME)
    if tab then
        tab:select()
        self.loadeddefaultchannel = true
    end
end

function Chat:selectServerChannel()
    local tab = self:getTabByName(SERVER_LOG_NAME)
    if tab then
        tab:select()
    end
end

function Chat:selectNextTab()
    self.tabBar:selectNextTab()
end

function Chat:selectPrevTab()
    self.tabBar:selectPrevTab()
end

function Chat:getChannelTabByMode(mode, chatName)
    if mode <= 3 then
        return self:getTabByName(LOCAL_CHAT_NAME), LOCAL_CHAT_NAME
    end

    if mode == MessageModes.PrivateFrom then
        local chat = self:getTabByName(chatName)
        if chat then
            return chat, chatName
        end

        local openPrivateMessageInNewTab = m_settings.getOption('openPrivateMessageInNewTab')
        if openPrivateMessageInNewTab then
            return g_channel:onOpenPrivateChannel(chatName, false), chatName
        end

        local showMessageInConsole = m_settings.getOption('showPrivateMessagesInConsole')
        if not showMessageInConsole then
            return nil, nil
        end

        return self:getTabByName(LOCAL_CHAT_NAME), LOCAL_CHAT_NAME
    end

    local messageType = MessageTypes[mode]
    if not messageType then
        return nil
    end

    if messageType.npcChat then
        return self:addTabMessages(NPC_NAME_CHAT, true), NPC_NAME_CHAT
    end

    if messageType.consoleTab then
        local consoleTab = messageType.consoleTab
        if consoleTab == 'Loot' then
            local tab = self:getTabByName(consoleTab)
            if tab then
                return tab, consoleTab
            end

            consoleTab = SERVER_LOG_NAME
        elseif consoleTab == 'Local Chat' and mode == MessageModes.Spell and m_settings.getOption('showSpellChat') then
            consoleTab = SPELL_CHANNEL_NAME
        end

        return self:getTabByName(consoleTab), consoleTab
    end

    return nil, nil
end

function Chat:getChannelTabById(id)
    local tab = self:getTabById(id)
    if tab then
        return tab, tab:getName()
    end

    return nil, nil
end

function Chat:sayModeChange(sayMode)
    local buttom = self.sayButton
    if sayMode == nil then
      sayMode = buttom.sayMode + 1
    end

    if sayMode > #SayModes then sayMode = 1 end

    buttom:setIcon(SayModes[sayMode].icon)
    buttom.sayMode = sayMode
  end

function Chat:ignoreMessage(mode, name)
    local isNpcMode = (mode == MessageModes.NpcFromStartBlock or mode == MessageModes.NpcFrom)
    local localPlayer = g_game.getLocalPlayer()
    if name ~= g_game.getCharacterName()
        and Communication:isUsingIgnoreList()
        and not(Communication:isUsingWhiteList())
        or (Communication:isUsingWhiteList() and not(Communication:isWhitelisted(name)) and not(Communication:isAllowingVIPs() and localPlayer:hasVip(name))) then

        local speaktype = MessageTypes[mode]
        if mode == MessageModes.Yell and Communication:isIgnoringYelling() then
            return false
        elseif speaktype and speaktype.private and Communication:isIgnoringPrivate() and not isNpcMode then
            return false
        elseif Communication:isIgnored(name) and not isNpcMode then
            return false
        end
    end

    if mode == MessageModes.Potion and not m_settings.getOption("potionSoundEffect") then
        return false
    end

    return true
end

function Chat:getDisplayTab(mode, channelId, chatName)
    local tab, name = self:getChannelTabByMode(mode, chatName)
    if tab then
        return tab, name
    end

    if mode == MessageModes.PrivateFrom then
        return nil, nil
    end

    tab, name = self:getChannelTabById(channelId)
    return tab, name
end

function Chat:addMessage(tab, displayName, name, level, mode, text, statement, groupId)
    tab:addMessage(name, level, mode, text, statement, groupId)
    if displayName ~= self.currentTab and not tab:isFixed() and not tab:isSpellChannel() then
        tab:blink(false)
    end

    local showPrivateMessagesOnScreen = m_settings.getOption('showPrivateMessagesOnScreen')
    if showPrivateMessagesOnScreen and mode == MessageModes.PrivateFrom then
        modules.game_textmessage.displayPrivateMessage(name .. ":\n" .. text)
    end
end

function Chat:onTalk(name, level, mode, text, channelId, pos, statement, groupId)
    -- message broadcasted by gamemaster
    if mode == MessageModes.GamemasterBroadcast then
        modules.game_textmessage.displayBroadcastMessage(name .. ': ' .. text)
        return
    end

    if not self:ignoreMessage(mode, name) then
        return
    end

    self:sendMapText(mode, pos, name, text)
    local messageType = MessageTypes[mode]
    if not messageType or messageType.hideInConsole then
        return
    end

    if mode == MessageModes.Spell and m_settings.getOption('showSpellChat') then
        channelId = SPELL_CHANNEL_ID
    end

    local tab, displayName = self:getDisplayTab(mode, channelId, name)
    if not tab then
        return
    end

    self:addMessage(tab, displayName, name, level, mode, text, statement, groupId)
    if displayName == SERVER_LOG_NAME then
        for _, tab in pairs(self.tabsServerLog) do
            self:addMessage(tab, tab:getName(), name, level, mode, text, statement, groupId)
        end
    end
end

function Chat:onTextMessage(mode, text)
    local messageType = MessageTypes[mode]
    if not messageType or messageType.hideInConsole or not messageType.consoleTab or mode == MessageModes.Market then
        return
    end

    local channelId = 0
    if mode == MessageModes.Spell and m_settings.getOption('showSpellChat') then
        channelId = SPELL_CHANNEL_ID
    end

    local tab, displayName = self:getDisplayTab(mode, channelId, '')
    if not tab then
        return
    end
    self:addMessage(tab, displayName, '', 0, mode, text, 0)
    if displayName == SERVER_LOG_NAME then
        for _, tab in pairs(self.tabsServerLog) do
            self:addMessage(tab, tab:getName(), '', 0, mode, text, 0)
        end
    end
end

function Chat:splitHighlightedWords(text)
    -- This is a way hack to index npc's strings
    -- Source side and lua need to return the same index
    -- I know, this is ugly, but if works... dont touch it !

    local words = {}
    local temp = ""
    local inside_braces = false

    local function add_words_from_string(str, highlighted)
        for word in str:gmatch("%S+") do 
            local cleaned_word = word:gsub("[,%.%?%!]", "")
            if cleaned_word ~= "" then
                table.insert(words, {cleaned_word, highlighted})
            end
        end
    end

    local i = 1
    while i <= #text do
        local char = text:sub(i, i)
    
        if char == "{" then
            inside_braces = true
            temp = ""
        elseif char == "}" then
            inside_braces = false
    
            local nextChar = text:sub(i + 1, i + 1)
            if nextChar:match("[%w]") then
                add_words_from_string(temp, true)
                i = i + 1
            else
                add_words_from_string(temp, true)
            end
    
            temp = ""
        elseif char == " " and not inside_braces then
            if temp ~= "" then
                add_words_from_string(temp, false)
                temp = ""
            end
        else
            temp = temp .. char
        end
    
        i = i + 1
    end

    if temp ~= "" then
        add_words_from_string(temp, false)
    end
    return words
end

function Chat:getNewHighlightedText(text, color, highlightColor, label)
    local tmpData = {}

    if not label.worlds then
      label.worlds = {}
    end

    for i, part in ipairs(text:split("{")) do
      if i == 1 then
        table.insert(tmpData, part)
        table.insert(tmpData, color)
      else
        for j, part2 in ipairs(part:split("}")) do
          if j == 1 then
            table.insert(tmpData, part2)
            table.insert(tmpData, highlightColor)
            label.worlds[#label.worlds+1] = part2
          else
            table.insert(tmpData, part2)
            table.insert(tmpData, color)
          end
        end
      end
    end

    return tmpData
end

function Chat:sendMapText(mode, creaturePos, name, message)
    if (mode == MessageModes.Say or mode == MessageModes.Whisper or mode == MessageModes.Yell or
        mode == MessageModes.Spell or mode == MessageModes.MonsterSay or mode == MessageModes.MonsterYell or
        mode == MessageModes.NpcFrom or mode == MessageModes.BarkLow or mode == MessageModes.BarkLoud or mode == MessageModes.Potion or
        mode == MessageModes.NpcFromStartBlock) and creaturePos then
        local staticText = StaticText.create()
        -- Remove curly braces from screen message
        local staticMessage = message
        local isNpcMode = (mode == MessageModes.NpcFromStartBlock or mode == MessageModes.NpcFrom)
        if isNpcMode then
            local highlightData = self:getNewHighlightedText(staticMessage, TextColors.lightblue, TextColors.darkblue, staticText)
            if #highlightData > 2 then
                staticText:addColoredMessage(name, mode, highlightData)
            else
                staticText:addMessage(name, mode, staticMessage)
            end
            staticText:setColor(TextColors.lightblue)
        else
            if mode == MessageModes.Spell then
                if name ~= g_game.getCharacterName() and not m_settings.getOption("spellsOthers") then
                    return
                end

                if name == g_game.getCharacterName() and not m_settings.getOption("showSpells") then
                    return
                end
            end

            staticText:addMessage(name, mode, staticMessage)
        end
        g_map.addThing(staticText, creaturePos, -1)
    end
end

function Chat:sendCurrentMessage()
    local message = self.textEdit:getText()
    self.textEdit:clearText()
    self:sendMessage(message)
    sendTemporaryMessage()
end

function Chat:setTextEditText(text)
    self.textEdit:setText(text)
    self.textEdit:setCursorPos(-1)
end

local commands = {
    ["^%#[y|Y] (.*)"] = { messageMode = MessageModes.Yell, channel = 0},
    ["^%#[w|W] (.*)"] = { messageMode = MessageModes.Whisper, channel = 0},
    ["^%#[s|S] (.*)"] = { messageMode = MessageModes.Say, channel = 0},
    ["^%#[c|C] (.*)"] = { messageMode = MessageModes.GamemasterChannel},
    ["^%#[b|B] (.*)"] = { messageMode = MessageModes.GamemasterBroadcast, channel = 0},
}

function Chat:getCommandMessage(message)
    for pattern, command in pairs(commands) do
        local match = message:match(pattern)
        if match then
            return match, command
        end
    end
    return message, nil
end

function Chat:addMessageHistory(message)
    self.currentMessageIndex = 0

    for i = #self.messageHistory, 1, -1 do
      if self.messageHistory[i] == message then
        table.remove(self.messageHistory, i)
      end
    end

    table.insert(self.messageHistory, message)
    if #self.messageHistory > MAX_HISTORY then
      table.remove(self.messageHistory, 1)
    end
end

function Chat:sendInDefaultChannel(tab, channel, command, messageMode, message)
    local messageModeDesc
    if tab:isLocalChat() or tab:isLootChannel() or tab:isSpellChannel() then
        local consoleMessageMode = SayModes[self.sayButton.sayMode].messageType
        messageModeDesc = command and command.messageMode or consoleMessageMode
        if messageMode ~= 2 then
            self:sayModeChange(2)
        end
    else
        messageModeDesc = command and command.messageMode or MessageModes.Channel
    end

    if channel == LOOT_CHANNEL_ID or channel == SPELL_CHANNEL_ID then
        channel = DEFAULT_CHANNEL_ID
    end

    g_game.talkChannel(messageModeDesc, channel, message)
end

function Chat:sendPrivateMessage(tab, chatCommandPrivateReady, chatCommandPrivate, message)
    local name = tab:getName()

    local messageType

    if chatCommandPrivateReady and not tab:isNpcChat() then
        messageType = MessageModes.PrivateTo
        name = chatCommandPrivate
    elseif tab:isNpcChat() then
        messageType = MessageModes.NpcTo
    else
        messageType = MessageModes.PrivateTo
    end

    if messageType ~= nil then
        g_game.talkPrivate(messageType, name, message)
    end

    local player = g_game.getLocalPlayer()
    if player then
        tab:addMessage(g_game.getCharacterName(), player:getLevel(), messageType, message)
    end
end

function Chat:sendMessage(message, tab)
    local tab = tab or self:getCurrentTab()
    if not tab then
        return
    end

    -- when talking on server log, the message goes to default channel
    if tab:getName() == SERVER_LOG_NAME then
      tab = self:getTabByName(LOCAL_CHAT_NAME)
    end

    local find_hashtag = string.sub(message, 1, 3)
    if find_hashtag == "#s " then
        message = string.sub(message, 4)
        tab = self:getTabByName(LOCAL_CHAT_NAME)
    end

    local channel = tab:getId()
    local messageMode = MessageModes.Say
    local command
    local originalMessage = message

    message, command = self:getCommandMessage(message)
    if command then
        if command.channel then
            channel = command.channel
        end
        if command.messageMode then
            messageMode = command.messageMode
        end
    end

    local chatCommandPrivateReady = false
    local findIni, _, chatCommandInitial, chatCommandPrivate, chatCommandEnd, chatCommandMessage = message:find("([%*%@])(.+)([%*%@])(.*)")
    if findIni ~= nil and findIni == 1 then -- player used private chat command
      if chatCommandInitial == chatCommandEnd then
        if chatCommandInitial == "*" then
            self:setTextEditText('*'.. chatCommandPrivate .. '* ')
        end
        message = chatCommandMessage:trim()
        chatCommandPrivateReady = true
      end
    end

    if tab:isNpcChat() or tab:isPrivate() then
        chatCommandPrivateReady = true
        if tab:isPrivate() then
            chatCommandPrivate = tab:getName()
        end
    end

    message = message:gsub("^(%s*)(.*)","%2") -- remove space characters from message init
    if #message == 0 then return end

    -- add new command to history
    self:addMessageHistory(originalMessage)

    if (channel or tab:isLocalChat()) and not chatCommandPrivateReady then
        return self:sendInDefaultChannel(tab, channel, command, messageMode, message)
    end

    return self:sendPrivateMessage(tab, chatCommandPrivateReady, chatCommandPrivate, message)
end

function Chat:addText(text, mode, tabName, creatureName, level, statement)
    if not creatureName then
        creatureName = ''
    end
    if not level then
        level = 0
    end
    if not statement then
        statement = 0
    end

    local tab = self:getTabByName(tabName)
    if not tab then
        return
    end
    tab:addMessage(creatureName, level, mode, text, statement)
end

function Chat:navigateMessageHistory(step)
  if not isChatEnabled() then
    return
  end

  local numCommands = #self.messageHistory
  if numCommands > 0 then
    self.currentMessageIndex = math.min(math.max(self.currentMessageIndex + step, 0), numCommands)
    if self.currentMessageIndex > 0 then
      local command = self.messageHistory[numCommands - self.currentMessageIndex + 1]
      self:setTextEditText(command)
    else
      self.textEdit:clearText()
    end
  end
  local player = g_game.getLocalPlayer()
  if player then
    player:lockWalk(200) -- lock walk for 200 ms to avoid walk during release of shift
  end
end

function Chat:selectAll(buffer)
    if not buffer then
        buffer = self.buffer
    end

    self:clearSelection(buffer)
    if buffer:getChildCount() > 0 then
        local text = {}
        for _,label in pairs(buffer:getChildren()) do
            if label:getText() ~= '' and label:isVisible() then
                label:selectAll()
                table.insert(text, label:getSelection())
            end
        end
        buffer.selectionText = table.concat(text, '\n')
        buffer.selection = { first = buffer:getChildIndex(buffer:getFirstChild()), last = buffer:getChildIndex(buffer:getLastChild()) }
    end
end

function Chat:clearSelection(buffer)
    if not buffer then
        buffer = self.buffer
    end

    for _,label in pairs(buffer:getChildren()) do
      label:clearSelection()
    end
    buffer.selectionText = nil
    buffer.selection = nil
end

function Chat:updateCurrent()
    local currentTab = self:getCurrentTab()
    if currentTab then
        currentTab:updateLabels()
    end
end

function Chat:displayReadOnlyOptions()
    local menu = g_ui.createWidget('PopupMenu')
    menu:setGameMenu(true)

    for name, tab in pairs(self.tabsByName) do
        menu:addOption("Show " .. name, function()
            self:setupReadOnly(name)
        end)
    end

    menu:display(g_window.getMousePosition())
end

function Chat:setupReadOnly(name)
    local lastTabMessage = self:getTabByName(name)
    if self.readOnly and lastTabMessage then
        self.readOnly:setText(lastTabMessage:getName())
        self.readOnly:setFont("verdana-11px-rounded")
        self.readOnly:setImageSource("/images/ui/chat_channel_selected")
        self.readOnly:setSize("96 16")
        self.readOnly:setImageClip("0 0 96 16")
        self.readOnly:setOn(false)
        self.readOnly.tab = lastTabMessage
    end

    if self.readOnlyTabMessage then
        self.readOnlyTabMessage:setReadOnlyFixed(false)
    end

    local tabMessages = self.tabsByName[name]
    if not tabMessages then
        return
    end

    self.readOnlyTabMessage = tabMessages
    tabMessages:setReadOnlyFixed(true)

    self:showReadOnly()
    Options.setReadOnlyChannel(name)
end

function Chat:closeReadOnly(name)
    if self.readOnlyTabMessage then
        self.readOnlyTabMessage:setReadOnlyFixed(false)
    end

    self.readOnly:setText('')
    self.readOnly:setImageSource("/images/ui/console")
    self.readOnly:setImageClip("64 0 96 16")
    self.readOnly:setSize("96 16")
    self.readOnly:setOn(true)
    self.readOnly:setImageBorder(0)

    self:hideReadOnly()
end

function Chat:setupReadOnlyButton()
    if self.readOnlyTabMessage then
        self.readOnlyTabMessage:processChannelTabMenu(_, g_window.getMousePosition(), _)
    end
end

function Chat:getTabBar()
    return self.tabBar
end

function Chat:onSelectTab()
    if not self.buffer or self.buffer:getChildCount() == 0 then
        return
    end

   self.buffer:ensureChildVisible(self.buffer:getLastChild())
end
