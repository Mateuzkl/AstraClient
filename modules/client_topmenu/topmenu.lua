-- private variables
local topMenu
local fpsUpdateEvent = nil
local statusUpdateEvent = nil
local startupEvent = nil
local pingVisibilityEvent = nil
local statusGeneration = 0
local statusOperations = {}

local function cancelStatusRequests()
  statusGeneration = statusGeneration + 1
  removeEvent(statusUpdateEvent)
  statusUpdateEvent = nil
  for operation in pairs(statusOperations) do
    HTTP.cancel(operation)
  end
  statusOperations = {}
end

-- private functions
local function addButton(id, description, icon, callback, panel, toggle, front, index)
  local class
  if toggle then
    class = 'TopToggleButton'
  else
    class = 'TopButton'
  end

  if topMenu.reverseButtons then
    front = not front
  end

  local button = panel:getChildById(id)
  if not button then
    button = g_ui.createWidget(class)
    if front then
      panel:insertChild(1, button)
    else
      panel:addChild(button)
    end
  end
  button:setId(id)
  button:setTooltip(description)
  button:setIcon(resolvepath(icon, 3))
  button.onMouseRelease = function(widget, mousePos, mouseButton)
    if widget:containsPoint(mousePos) and mouseButton ~= MouseMidButton and mouseButton ~= MouseTouch then
      callback()
      return true
    end
  end
  button.onTouchRelease = button.onMouseRelease
  if not button.index and type(index) == 'number' then
    button.index = index
  end
  return button
end

-- public functions
function init()
  connect(g_game, { onGameStart = online,
                    onGameEnd = offline,
                    onPingBack = updatePing })

  topMenu = g_ui.createWidget('TopMenu', g_ui.getRootWidget())

  if g_game.isOnline() then
    startupEvent = scheduleEvent(function()
      startupEvent = nil
      online()
    end, 10)
  end

  updateFps()
  updateStatus()
end

function terminate()
  disconnect(g_game, { onGameStart = online,
                       onGameEnd = offline,
                       onPingBack = updatePing })
  removeEvent(fpsUpdateEvent)
  fpsUpdateEvent = nil
  removeEvent(startupEvent)
  startupEvent = nil
  removeEvent(pingVisibilityEvent)
  pingVisibilityEvent = nil
  cancelStatusRequests()

  topMenu:destroy()
  topMenu = nil
end

function online()
  cancelStatusRequests()
  local benchmark = g_clock.millis()
  if topMenu.hideIngame then
    hide()
  else
    m_interface.getRootPanel():addAnchor(AnchorTop, 'topMenu', AnchorBottom)
  end
  if topMenu.onlineLabel then
    topMenu.onlineLabel:hide()
  end

  showGameButtons()

  if topMenu.pingLabel then
    removeEvent(pingVisibilityEvent)
    pingVisibilityEvent = addEvent(function()
      pingVisibilityEvent = nil
      if m_settings.getOption('showPing') and (g_game.getFeature(GameClientPing) or g_game.getFeature(GameExtendedClientPing)) then
        topMenu.pingLabel:show()
      else
        topMenu.pingLabel:hide()
      end
    end)
  end

  consoleln("TopMenu loaded in " .. (g_clock.millis() - benchmark) / 1000 .. " seconds.")
end

function offline()
  if topMenu.hideIngame then
    show()
  end
  if topMenu.onlineLabel then
    topMenu.onlineLabel:show()
  end

  hideGameButtons()
  if topMenu.pingLabel then
    topMenu.pingLabel:hide()
  end
  updateStatus()
end

function updateFps()
  if not topMenu.fpsLabel then return end
  fpsUpdateEvent = scheduleEvent(updateFps, 500)
  local text = 'FPS: ' .. g_app.getFps()
  topMenu.fpsLabel:setText(text)
end

function updatePing(ping)
  if not topMenu.pingLabel then return end
  if g_proxy and g_proxy.getPing() > 0 then
    ping = g_proxy.getPing()
  end

  local text = 'Ping: '
  local color
  if ping < 0 then
    text = text .. "??"
    color = 'yellow'
  else
    text = text .. ping .. ' ms'
    if ping >= 500 then
      color = 'red'
    elseif ping >= 250 then
      color = 'yellow'
    else
      color = 'green'
    end
  end
  topMenu.pingLabel:setColor(color)
  topMenu.pingLabel:setText(text)
end

function setPingVisible(enable)
  if not topMenu.pingLabel then return end
  topMenu.pingLabel:setVisible(enable)
end

function setFpsVisible(enable)
  if not topMenu.fpsLabel then return end
  topMenu.fpsLabel:setVisible(enable)
end

function addLeftButton(id, description, icon, callback, front, index)
  return addButton(id, description, icon, callback, topMenu.leftButtonsPanel, false, front, index)
end

function addLeftToggleButton(id, description, icon, callback, front, index)
  return addButton(id, description, icon, callback, topMenu.leftButtonsPanel, true, front, index)
end

function addRightButton(id, description, icon, callback, front, index)
  return addButton(id, description, icon, callback, topMenu.rightButtonsPanel, false, front, index)
end

function addRightToggleButton(id, description, icon, callback, front, index)
  return addButton(id, description, icon, callback, topMenu.rightButtonsPanel, true, front, index)
end

function addLeftGameButton(id, description, icon, callback, front, index)
  local button = addButton(id, description, icon, callback, topMenu.leftGameButtonsPanel, false, front, index)
  if modules.game_buttons then
    modules.game_buttons.takeButton(button)
  end
  return button
end

function addLeftGameToggleButton(id, description, icon, callback, front, index)
  local button = addButton(id, description, icon, callback, topMenu.leftGameButtonsPanel, true, front, index)
  if modules.game_buttons then
    modules.game_buttons.takeButton(button)
  end
  return button
end

function addRightGameButton(id, description, icon, callback, front, index)
  local button = addButton(id, description, icon, callback, topMenu.rightGameButtonsPanel, false, front, index)
  if modules.game_buttons then
    modules.game_buttons.takeButton(button)
  end
  return button
end

function addRightGameToggleButton(id, description, icon, callback, front, index)
  local button = addButton(id, description, icon, callback, topMenu.rightGameButtonsPanel, true, front, index)
  if modules.game_buttons then
    modules.game_buttons.takeButton(button)
  end
  return button
end

function showGameButtons()
  topMenu.leftGameButtonsPanel:show()
  topMenu.rightGameButtonsPanel:show()
  if modules.game_buttons then
    modules.game_buttons.takeButtons(topMenu.leftGameButtonsPanel:getChildren())
    modules.game_buttons.takeButtons(topMenu.rightGameButtonsPanel:getChildren())
  end
end

function hideGameButtons()
  topMenu.leftGameButtonsPanel:hide()
  topMenu.rightGameButtonsPanel:hide()
end

function getButton(id)
  return topMenu:recursiveGetChildById(id)
end

function getTopMenu()
  return topMenu
end

function toggle()
  if not topMenu then
    return
  end

  if topMenu:isVisible() then
    hide()
  else
    show()
  end
end

function hide()
  topMenu:hide()
  if not topMenu.hideIngame then
    m_interface.getRootPanel():addAnchor(AnchorTop, 'parent', AnchorTop)
  end
  if modules.game_stats then
    modules.game_stats.show()
  end
end

function show()
  topMenu:show()
  if not topMenu.hideIngame then
    m_interface.getRootPanel():addAnchor(AnchorTop, 'topMenu', AnchorBottom)
  end
  if modules.game_stats then
    modules.game_stats.hide()
  end
end

function updateStatus()
  cancelStatusRequests()
  local urls = Services and Services.status
  if type(urls) == 'string' then urls = urls ~= '' and {urls} or {} end
  if type(urls) ~= 'table' or #urls == 0 then return end
  if not topMenu or not topMenu.onlineLabel then return end
  if g_game.isOnline() then return end
  local generation = statusGeneration
  local playersOnline = 0
  local onlineLabel = ''
  local discordLink = ''
  local discordOnline = ''
  local pending = #urls
  local failed = false
  local successes = 0
  for index = 1, #urls do
    local url = urls[index]
    local completed = false
    local operation
    operation = HTTP.postJSON(url, {type="cacheinfo"}, function(data, err)
      completed = true
      if generation ~= statusGeneration or not topMenu then return end
      if operation then statusOperations[operation] = nil end
      pending = pending - 1
      if err then
        failed = true
        g_logger.warning("HTTP error for " .. url .. ": " .. tostring(err))
      elseif type(data) == 'table' then
        successes = successes + 1
        if data and data.online then
          onlineLabel = tostring(data.online)
        elseif data.playersonline then
          playersOnline = playersOnline + (tonumber(data.playersonline) or 0)
        end
        if data.discord_online then discordOnline = tostring(data.discord_online) end
        if data.discord_link then discordLink = tostring(data.discord_link) end
      end

      if pending == 0 then
        if failed then
          statusUpdateEvent = scheduleEvent(function()
            statusUpdateEvent = nil
            if generation == statusGeneration then updateStatus() end
          end, 60000)
        end
        if successes == 0 then return end
        if discordLink ~= '' then
          local discordOnClick = function()
            g_platform.openUrl(discordLink)
          end
          if topMenu.discordLabel then topMenu.discordLabel.onClick = discordOnClick end
          if topMenu.discord then topMenu.discord.onClick = discordOnClick end
        end
        if discordOnline ~= '' and topMenu.discordLabel then
          topMenu.discordLabel:setText(discordOnline)
        end
        local topOnlineLabel = topMenu:recursiveGetChildById('onlineLabel')
        if topOnlineLabel then
          topOnlineLabel:setText(onlineLabel ~= '' and onlineLabel or (playersOnline .. " players online"))
          topOnlineLabel:setFont(tovar("$var-cip-font"))
          topOnlineLabel:setColor(tovar("$var-text-cip-color"))
        end
      end
    end)
    if not completed and generation == statusGeneration then
      statusOperations[operation] = true
    end
  end
end



function getRightGameToggleButtons()
  local buttons = {}
  local panel = topMenu:getChildById('rightGameButtonsPanel')
  for _, child in pairs(panel:getChildren()) do
    if child:getClassName() == 'UIButton' then
      table.insert(buttons, child)
    end
  end
  return buttons
end
