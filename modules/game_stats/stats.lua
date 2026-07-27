ui = nil
local updateEvent = nil
local moduleActive = false

local keybindShowPing = KeyBind:getKeyBind("UI", "Show/hide FPS / Lag indicator")

function init()
  moduleActive = true
  ui = g_ui.loadUI('stats', m_interface.getMapPanel())
  if not ui then return end

  local rootPanel = m_interface.getRootPanel()
  keybindShowPing:active(rootPanel)

  if not m_settings.getOption("showPing") then
    if ui.fps then ui.fps:hide() end
  end
  if not m_settings.getOption("showFps") then
    if ui.ping then ui.ping:hide() end
  end

  updateEvent = scheduleEvent(update, 200)
end

function terminate()
  moduleActive = false
  keybindShowPing:deactive()
  if updateEvent then removeEvent(updateEvent); updateEvent = nil end
  if ui then
    if ui.destroy then ui:destroy() end
    ui = nil
  end
end

function update()
  if not moduleActive then return end
  updateEvent = scheduleEvent(update, 500)
  if not ui or ui:isHidden() then return end

  local text = g_app.getFps() .. ' fps'
  if ui.fps then ui.fps:setText(text) end

  local ping = math.round(g_game.getPing() * 0.7)
  if g_proxy and g_proxy.getPing() > 0 then
    ping = g_proxy.getPing()
  end

  if ui.worldName then ui.worldName:setText(g_game.getWorldName()) end

  local text = 'Ping: '
  if ping < 0 then
    text = "??"
    if ui.imagePing then ui.imagePing:setImageSource('/images/latency/latency-medium') end
  else
    if ping >= 500 then
      text = "High lag (".. ping .." ms)"
      if ui.imagePing then ui.imagePing:setImageSource('/images/latency/latency-high') end
    elseif ping >= 250 then
      text = "Medium lag (".. ping .." ms)"
      if ui.imagePing then ui.imagePing:setImageSource('/images/latency/latency-medium') end
    else
      text = "Low lag (".. ping .." ms)"
      if ui.imagePing then ui.imagePing:setImageSource('/images/latency/latency-low') end
    end
  end

  local player = g_game.getLocalPlayer()
  if player and player:getGroupType() >= 4 and player:getGroupType() <= 6 then
    local spectators = g_map.getSpectators(player:getPosition(), false)
    local playerCount = 0
    local monsterCount = 0
    local npcCount = 0
    for _, spec in pairs(spectators) do
      if spec:isPlayer() and spec ~= player then
        playerCount = playerCount + 1
      elseif spec:isMonster() and spec ~= player then
        monsterCount = monsterCount + 1
      elseif spec:isNpc() and spec ~= player then
        npcCount = npcCount + 1
      end
    end

    text = tr("%s\nPlayers: %s", text, playerCount)
    text = tr("%s\nMonsters: %s", text, monsterCount)
    text = tr("%s\nNPcs: %s", text, npcCount)
  end

  if g_game.isRecord() then
    if g_game.getCamViewerSpeed() == 0 then
      text = tr("%s\nRecord Speed: Paused", text)
    else
      text = tr("%s\nRecord Speed: %s%%", text, 100 + (100 - (100 * g_game.getCamViewerSpeed())))
    end

    local duration = math.floor(g_game.getRecordDuration() / 1000)
    local hours = math.floor(duration / 3600)
    local minutes = math.floor((duration % 3600) / 60)
    local seconds = duration % 60

    local currentDuration = math.floor(g_game.getRecordCurrentFrame() / 1000)
    local currentHours = math.floor(currentDuration / 3600)
    local currentMinutes = math.floor((currentDuration % 3600) / 60)
    local currentSeconds = currentDuration % 60

    text = tr("%s\n%02d:%02d:%02d/%02d:%02d:%02d", text, currentHours, currentMinutes, currentSeconds, hours, minutes, seconds)
  end

  if ui.ping then ui.ping:setText(text) end
end

function show()
  if not ui then return end
  if ui:isHidden() then
    ui:setVisible(true)
  else
    ui:setVisible(false)
  end
end

function hide()
  if not ui then return end
  ui:setVisible(false)
end