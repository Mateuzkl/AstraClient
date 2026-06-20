
DEFAULT_CHANNEL_ID = 0x0000
LOOT_CHANNEL_ID = 0xFFF0
OWNER_CHANNEL_ID = 0xFFFF
GUILD_CHANNEL_ID = 0x2710

local CHANNEL_TAB_COLOR = "#f0cb64"
local CHANNEL_TABS_COLORED = {
    ["World Chat"] = true,
    ["Help"] = true,
    ["NPCs"] = true,
}
local function isChannelTabColored(name)
    return CHANNEL_TABS_COLORED[name] == true
end


TabMessages = {}
function TabMessages.new(name, content)
    local obj = {
        name = name,
        id = 0,
        messages = {},
        tabBar = content,
        widget = nil,
        activeLabels = 0,

        messagesPerSecond = 0,
        lastMessageTime = 0,
        event = nil,
        ownerPrivateChannel = false,
        privateChannel = false,
        muted = false,
        readOnlyFixed = false,

        inviteNameWindow = nil,
        excludeNameWindow = nil,
    }

    setmetatable(obj, { __index = TabMessages })

    obj:setup()
    return obj
end

function TabMessages:setup()
    self.displayName = self.name
    if #self.displayName > 11 then
        self.displayName = self.displayName:sub(1, 9) .. "..."
    end
    self.widget = self.tabBar:addTab(self.displayName, nil, function(widget, mousePos, mouseButton)
        self:processChannelTabMenu(widget, mousePos, mouseButton)
    end)
    self.widget.fullName = self.name
    if isChannelTabColored(self.name) then
        self.widget:setImageColor(CHANNEL_TAB_COLOR)
    end

    if self.name ~= self.displayName then
        self.widget:setTooltip(self.name)
    elseif self.name == SPELL_CHANNEL_NAME then
        self.widget:setTooltip("Displays only the spells cast by players during gameplay.\nThis tab can be enabled or disabled in the Options menu.")
    end

    for _ = 1, MAX_LINES do
        table.insert(self.messages, Message.new())
    end

    self.tabBar:updateNavigation()
end

function TabMessages:setReadOnlyFixed(fixed)
    self.readOnlyFixed = fixed
    if fixed then
        self:updateLabels()
    end
end

function TabMessages:isFixed()
    return self.readOnlyFixed
end

function TabMessages:setCurrent(current)
    self.current = current
end

function TabMessages:isCurrent()
    return self.current
end

function TabMessages:setMuted(v)
    self.muted = v
end

function TabMessages:isMuted()
    return self.muted
end

function TabMessages:destroy()
    self:stopSlowMode()
    self.tabBar:removeTab(self.widget)
end

function TabMessages:select()
    self.tabBar:selectTab(self.widget)
end

function TabMessages:getActiveLabels()
    return self.activeLabels
end

function TabMessages:blink(v)
    self.tabBar:blinkTab(self.widget, v)
end

function TabMessages:clearMessages()
    for _, message in ipairs(self.messages) do
        message:clear()
    end
    self.activeLabels = 0
    self:updateLabels()
end

function TabMessages:offline()
    self:stopSlowMode()
    self:clearMessages()
    if not self:isLocalChat() and not self:isServerLogChat() and not self:isSpellChannel() then
        g_chat:removeTabByName(self:getName())
    end
end

function TabMessages:setId(id)
    self.id = id
    self.widget.channelId = id
end

function TabMessages:getId()
    return self.id
end

function TabMessages:getName()
    return self.name
end

function TabMessages:isLocalChat()
    return self.name == LOCAL_CHAT_NAME
end

function TabMessages:isServerLogChat()
    return self.name == SERVER_LOG_NAME
end

function TabMessages:isLootChannel()
    return self.id == LOOT_CHANNEL_ID
end

function TabMessages:isSpellChannel()
    return self.id == SPELL_CHANNEL_ID
end

function TabMessages:isNpcChat()
    return self.name == NPC_NAME_CHAT
end

function TabMessages:getMessagesPerSecond()
    return self.messagesPerSecond
end

function TabMessages:getLastMessageTime()
    return self.lastMessageTime
end

function TabMessages:isInSlowMode()
    return self.event ~= nil
end

function TabMessages:isOwnerPrivate()
    return self.ownerPrivateChannel
end

function TabMessages:isPrivate()
    return self.privateChannel
end

function TabMessages:isGuildChannel()
    return self.id == GUILD_CHANNEL_ID
end

function TabMessages:setPrivate(v)
    self.privateChannel = v

    if v then
        for i, channel in ipairs(ChannelConfig) do
            if channel.channel == self.id then
                table.remove(ChannelConfig, i)
                break
            end
        end
    end
end

function TabMessages:setOwnerPrivate(v)
    self.ownerPrivateChannel = v
    g_chat:setOwnPrivateChat(v)

    if v then
        for i, channel in ipairs(ChannelConfig) do
            if channel.channel == self.id then
                table.remove(ChannelConfig, i)
                break
            end
        end
    end
end

function TabMessages:addMessage(name, level, mode, text, statement, groupId)
    if self:isMuted() then
        return
    end

    -- check format text
    local mt = MessageTypes[mode]
    if mt and mt.consoleOption and not m_settings.getOption(mt.consoleOption) then
        return
    end

    if self.lastMessageTime - g_clock.millis() < 1000 then
        self.messagesPerSecond = self.messagesPerSecond + 1
    else
        self.messagesPerSecond = 0
    end

    self.lastMessageTime = g_clock.millis()

    local firstObject = self.messages[1]
    table.remove(self.messages, 1)
    table.insert(self.messages, firstObject)

    self.activeLabels = math.min(MAX_LINES, self.activeLabels + 1)
    local lastMessage = self.messages[MAX_LINES]

    -- check format text
    if mt and mt.colored then
        text = text:tocolored()
    end

    lastMessage:setup(name, level, mode, text, statement, groupId)

    -- show
    if self:isCurrent() or self:isFixed() then
        if self:getMessagesPerSecond() < MAX_MESSAGE_PER_SECOND then
            self:stopSlowMode()
            self:updateLastLabel()
        else
            self:startSlowMode()
        end
    end
end

function TabMessages:addPrivateMessage(text, mode, name, isPrivateCommand, creatureName, noBlink, level, statement)
    local firstObject = self.messages[1]
    table.remove(self.messages, 1)
    table.insert(self.messages, firstObject)

    self.activeLabels = math.min(MAX_LINES, self.activeLabels + 1)
    local lastMessage = self.messages[MAX_LINES]
    lastMessage:setup(name, level, mode, text, statement)

    -- show
    if self:getName() == g_chat:getCurrentTab():getName() then
        if self:getMessagesPerSecond() < MAX_MESSAGE_PER_SECOND then
            self:stopSlowMode()
            self:updateLastLabel()
        else
            self:startSlowMode()
        end
    end
end

function TabMessages:clear()
    self.activeLabels = 0
    self:updateLabels()
end

function TabMessages:updateLastLabel()
    if self:isFixed() then
        self:internalUpdateLastLabel(g_chat:getReadOnlyLabels(), g_chat:getReadOnlyBuffer())
    end
    if self:isCurrent() then
        self:internalUpdateLastLabel(g_chat:getLabels(), g_chat:getBuffer())
    end
end

function TabMessages:internalUpdateLastLabel(labels, buffer)
    local firstLabel = labels[1]
    table.remove(labels, 1)
    table.insert(labels, firstLabel)

    local lastMessage = self.messages[MAX_LINES]
    if lastMessage then
        lastMessage:updateLabel(firstLabel, self)
        firstLabel:show()

        firstLabel.message = lastMessage
        buffer:moveChildToIndex(firstLabel, MAX_LINES)

        if lastMessage.groupId ~= nil then
            firstLabel:setImageShader(lastMessage.groupId >= 4 and "text_light_red" or "")
        end
    end
end

function TabMessages:updateLabels()
    if not g_chat then
        return
    end
    if self:isFixed() then
        self:internalUpdateLabels(g_chat:getReadOnlyLabels())
    end
    if self:isCurrent() then
        self:internalUpdateLabels(g_chat:getLabels())
    end
end

function TabMessages:internalUpdateLabels(labels)
    for i = 1, #self.messages do
        local messageIndex = MAX_LINES - i + 1
        local message = self.messages[messageIndex]
        local label = labels[messageIndex]
        label.index = messageIndex

        if message.groupId ~= nil then
            label:setImageShader(message.groupId >= 4 and "text_light_red" or "")
        end

        if i <= self.activeLabels then
            label.message = message
            label:show()
            message:updateLabel(label, self)
        else
            label.message = nil
            label:hide()
        end
    end

    table.sort(labels, function(a, b) return a.index < b.index end)
    g_chat:reorderChildren()
end

function TabMessages:startSlowMode()
    if self:isInSlowMode() or not g_game.isOnline() then
        return
    end

    if self.name == NPC_NAME_CHAT then
        self:updateLabels()
        return
    end

    self:stopSlowMode()
    self.event = cycleEvent(function()
        if self:getMessagesPerSecond() < MAX_MESSAGE_PER_SECOND or (self:getLastMessageTime() - g_clock.millis()) >= 1000 then
            self:stopSlowMode()
            return
        end

        self:updateLabels()
    end, 300)
end

function TabMessages:stopSlowMode()
    if not self:isInSlowMode() then
        return
    end

    if self.event then
        self:updateLabels()
        removeEvent(self.event)
        self.event = nil
        self.messagesPerSecond = 0
    end
end

function TabMessages:processChannelTabMenu(widget, mousePos, mouseButton)
    local menu = g_ui.createWidget('PopupMenu')
    menu:setGameMenu(true)
    self:select()

    local worldName = g_game.getWorldName()
    local characterName = g_game.getCharacterName()

    if self:isOwnerPrivate() and not self:isGuildChannel() then
        menu:addOption(tr('Invite player'), function()
            if not self.inviteNameWindow then
                self.inviteNameWindow = g_ui.createWidget('InviteNameWindow', rootWidget)
            end

            self.inviteNameWindow:show()


            g_client.setInputLockWidget(self.inviteNameWindow)
            local textUI = self.inviteNameWindow.contentPanel.characterName
            local cancelButton = self.inviteNameWindow.contentPanel.cancel
            cancelButton.onClick = function()
                textUI:setText('', false)
                self.inviteNameWindow:hide()
                g_client.setInputLockWidget(nil)
            end
            local okButton = self.inviteNameWindow.contentPanel.ok
            okButton.onClick = function()
                local text = textUI:getText()
                g_game.inviteToOwnChannel(text)
                textUI:setText('', false)
                self.inviteNameWindow:hide()
                g_client.setInputLockWidget(nil)
            end

            self.inviteNameWindow.onEnter = function()
                okButton.onClick()
            end
            self.inviteNameWindow.onEscape = function()
                cancelButton.onClick()
            end
        end)
        menu:addOption(tr('Exclude player'), function()
            if not self.excludeNameWindow then
                self.excludeNameWindow = g_ui.createWidget('ExcludeNameWindow', rootWidget)
            end

            self.excludeNameWindow:show()


            g_client.setInputLockWidget(self.excludeNameWindow)
            local textUI = self.excludeNameWindow.contentPanel.characterName
            local cancelButton = self.excludeNameWindow.contentPanel.cancel
            cancelButton.onClick = function()
                textUI:setText('', false)
                self.excludeNameWindow:hide()
                g_client.setInputLockWidget(nil)
            end
            local okButton = self.excludeNameWindow.contentPanel.ok
            okButton.onClick = function()
                local text = textUI:getText()
                g_game.excludeFromOwnChannel(text)
                textUI:setText('', false)
                self.excludeNameWindow:hide()
                g_client.setInputLockWidget(nil)
            end

            self.excludeNameWindow.onEnter = function()
                okButton.onClick()
            end
            self.excludeNameWindow.onEscape = function()
                cancelButton.onClick()
            end
        end)
        menu:addSeparator()
    end
    if self:isGuildChannel() then
        menu:addOption(tr('Invite player'), function()
        end)
        menu:addOption(tr('Exclude player'), function()
        end)
        menu:addSeparator()
        menu:addOption(tr('Edit guild message'), function()
        end)
        menu:addOption(tr('Hide enter and leave messages'), function()
        end)
        menu:addSeparator()
    end

    if not self:isLocalChat() and not self:isServerLogChat() and not self:isSpellChannel() then
        menu:addOption(tr('Close'), function()
            if self:isFixed() then
                g_chat:closeReadOnly(self:getName())
                Options.setReadOnlyChannel(nil)
            end
            g_chat:selectPrevTab()
            g_chat:removeTabByName(self:getName())

            if self.id > 0 and self.id < SPELL_CHANNEL_ID then
                g_game.leaveChannel(self.id)
            end
        end)
        menu:addOption(tr('%s', g_chat:isServerTab(self) and 'Hide Server Messages' or 'Show Server Messages'), function()
            if g_chat:isServerTab(self) then
                g_chat:removeTabActiveServerLog(self)
            else
                g_chat:addTabActiveServerLog(self)
            end
        end)
        menu:addSeparator()
    end

    if not self:isFixed() then
        menu:addOption(tr('Show in Ready-Only Tab'), function() g_chat:setupReadOnly(self:getName()) end)
    else
        menu:addOption(tr('Close Ready-Only Tab'), function()
          g_chat:closeReadOnly(self:getName())
          Options.setReadOnlyChannel(nil)
        end)
    end
    menu:addSeparator()

    if not self:isServerLogChat() and not self:isSpellChannel() then
      menu:addOption(tr('%s', self:isMuted() and "Unmute" or "Mute"), function() self:setMuted(not self:isMuted()) end)
      menu:addSeparator()
    end

    if g_chat and g_chat:getCurrentTab() and g_chat:getCurrentTab():getName() == self:getName() then
      menu:addOption(tr('Clear Messages'), function() self:clearMessages() end)
      menu:addOption(tr('Save Messages'), function()
        local lines = {}
        for _,label in pairs(g_chat:getBuffer():getChildren()) do
            if label:getText() ~= '' and label:isVisible() then
                table.insert(lines, label:getText())
            end
        end

        local filename = worldName .. ' - ' .. characterName .. ' - ' .. self:getName() .. '.txt'
        local filepath = filename

        -- extra information at the beginning
        table.insert(lines, 1, os.date('\nChannel saved at %a %b %d %H:%M:%S %Y'))

        if g_resources.fileExists(filepath) then
          table.insert(lines, 1, protectedcall(g_resources.readFileContents, filepath) or '')
        end

        g_resources.writeFileContents(filepath, table.concat(lines, '\n'))
        modules.game_textmessage.displayStatusMessage(tr('Channel appended to %s', filename))
      end)
    end

    menu:display(mousePos)
  end

function TabMessages:getWidget()
    return self.widget
end
