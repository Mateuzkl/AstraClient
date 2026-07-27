Channel = {}
Channel.__index = Channel

local DEFAULT_CHANNEL_COLOR = "$var-text-cip-color"
local CHANNEL_COLOR = "#f6a623"

local function getChannelListColor(channelName)
  if channelName:find("World Chat") or channelName:find("Help") then
    return CHANNEL_COLOR
  end

  return DEFAULT_CHANNEL_COLOR
end

function Channel.new()
    local obj = {
        window = nil,
        ignoredChannels = {},
    }

    setmetatable(obj, Channel)
    return obj
end

function Channel:setChannelWindow(window)
    if self.window then
        self.window:destroy()
    end

    self.window = window
end

function Channel:doChannelListSubmit()
    local channelListPanel = self.window.contentPanel:getChildById('channelList')
    local openPrivateChannelWith = self.window.contentPanel:getChildById('openPrivateChannelWith'):getText()
    if openPrivateChannelWith ~= '' then
      if openPrivateChannelWith:lower() ~= g_game.getCharacterName():lower() then
        g_game.openPrivateChannel(openPrivateChannelWith)
      else
        modules.game_textmessage.displayFailureMessage('You cannot create a private chat channel with yourself.')
      end
    else
      local selectedChannelLabel = channelListPanel:getFocusedChild()
      if not selectedChannelLabel then return end

      Options.addChannel(selectedChannelLabel.channelId, false)
      if selectedChannelLabel:getText() == "NPCs" then
        g_chat:addTabMessages('NPCs', true)
        g_chat:addChannelConfig('NPCs', selectedChannelLabel.channelId)
      elseif selectedChannelLabel.channelId == OWNER_CHANNEL_ID then
        g_game.openOwnChannel()
      elseif selectedChannelLabel.channelId == LOOT_CHANNEL_ID then
        self:onOpenChannel(selectedChannelLabel.channelId, selectedChannelLabel:getText())
        g_chat:addChannelConfig(selectedChannelLabel:getText(), selectedChannelLabel.channelId)
      else
        g_chat:addChannelConfig(selectedChannelLabel:getText(), selectedChannelLabel.channelId)
        g_game.joinChannel(selectedChannelLabel.channelId)
      end
    end

    g_client.setInputLockWidget(nil)
    self.window:destroy()
end

function Channel:onChannelListFocusChange(list, selected, lastSelected)
  if not selected then
    return
  end

  if lastSelected then
    local index = lastSelected:getActionId()
    lastSelected:setBackgroundColor((index % 2 == 0) and '#484848' or '#414141')
    lastSelected:setColor(lastSelected.channelColor or DEFAULT_CHANNEL_COLOR)
  end

  selected:setBackgroundColor('#585858')
  selected:setColor("$var-text-cip-color-highlight")
end

function Channel:onChannelList(channelList)
    table.insert(channelList, {0, "NPCs"})

    doCreateChannelWindow()
    g_client.setInputLockWidget(self.window)

    local channelListPanel = self.window.contentPanel:getChildById('channelList')
    self.window:insertLuaCall("onEnter")
    self.window.onEnter = function() self:doChannelListSubmit() end
    self.window:insertLuaCall("onDestroy")
    self.window.onDestroy = function() g_client.setInputLockWidget(nil) self.window = nil m_interface.getRootPanel():focus() end

    local count = 0
    for k, v in pairs(channelList) do
        local channelId = v[1]
        local channelName = v[2]

        if #channelName > 0 then
            local label = g_ui.createWidget('ChannelListLabel', channelListPanel)
            label.channelId = channelId
            label:setText(channelName)
            label.channelColor = getChannelListColor(channelName)
            label:setColor(label.channelColor)
            label:setHeight(16)
            local backgroundColor = (count % 2 == 0) and '#484848' or '#414141'
            label:setBackgroundColor(backgroundColor)
            label:setActionId(count)
            label:setPhantom(false)
            label.onDoubleClick = function() self:doChannelListSubmit() end
            label.channelData = v
        end

        count = count + 1
    end

    channelListPanel.onChildFocusChange = function(list, selected, lastSelected) Channel:onChannelListFocusChange(list, selected, lastSelected) end
    channelListPanel:focusChild(channelListPanel:getFirstChild())
end

function Channel:onOpenChannel(channelId, channelName, participants)
  local focus = not table.find(self.ignoredChannels, channelId)
  local tab = g_chat:addTabMessages(channelName, false)
  tab:setId(channelId)

  -- g_chat:getTabBar
  if GameChannelInitialized then
    local index = Options.getChannelIndex(channelId)
    if index then
      local tabb = tab:getWidget()
      g_chat:getTabBar():moveTab(tabb, index)
    end
  end

  g_chat:addChannelConfig(channelName, channelId)

  if channelId == HELP_CHANNEL then
    tab:addMessage('', 0, MessageModes.ChannelManagement, tr('Welcome to the help channel! Feel free to ask questions concerning client controls, general game play, use of accounts and the official homepage. In-depth questions about the content of the game will not be answered. Experienced players will be glad to help you to the best of theirknowledge. Keep in mind that this is not a chat channel for general conversations. Therefore please limit your statements to relevant questions and answers.'), 0)
  end

  if participants and #participants > 0 then
      local str = "Channel participants: "
      for i, v in pairs(participants) do
          str = str .. v
          if i < #participants then
              str = str .. ", "
          else
              str = str .. "."
          end
      end

      tab:addMessage('', 0, MessageModes.ChannelManagement, str, 0)
    end
    return tab
end

function Channel:onCloseChannel(channelId)
  g_chat:removeTabById(channelId)
  Options.removeChannel(channelId)
end

function Channel:onOpenPrivateChannel(name, focus)
  if focus == nil then
    focus = true
  end
  local tab = g_chat:addTabMessages(name, focus)
  tab:setPrivate(true)
  return tab
end

function Channel:onOpenOwnPrivateChannel(channelId, name)
  local tab = g_chat:addTabMessages(name, true)
  tab:setId(channelId)
  tab:setOwnerPrivate(true)
end

function Channel:onChannelEvent(channelId, name, type)
  local fmt = ChannelEventFormats[type]
  if not fmt then
    print(('Unknown channel event type (%d).'):format(type))
    return
  end

  local tab = g_chat:getTabById(channelId)
  if tab then
    tab:addMessage('', 0, MessageModes.ChannelManagement, fmt:format(name), 0)
  end
end
