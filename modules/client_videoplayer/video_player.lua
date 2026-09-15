g_videoPlayer = {
  players = {}
}

local function checkMouseMoved(player)
  local mousePos = g_window.getMousePosition()
  local oldMousePos = player.mousePos

  if mousePos.x == oldMousePos.x and mousePos.y == oldMousePos.y then
    g_effects.fadeOut(player.timeline, 250)
    g_mouse.pushCursor("hidden")
  end

  player.mousePos = mousePos

  player.mouseCheckEvent = scheduleEvent(function()
    checkMouseMoved(player)
  end, 3000)
end

local function onMouseMove(player, mousePos, mouseMoved)
  if mouseMoved.x ~= 0 or mouseMoved.y ~= 0 then
    if player.mouseCheckEvent then
      removeEvent(player.mouseCheckEvent)
      player.mouseCheckEvent = nil
    end

    player.timeline:setOpacity(1.0)
    g_mouse.popCursor("hidden")

    player.mousePos = mousePos
    player.mouseCheckEvent = scheduleEvent(function()
      checkMouseMoved(player)
    end, 2000)
  end

  return true
end

local function onPlayerHovered(player, hovered)
  if player.mouseCheckEvent then
    removeEvent(player.mouseCheckEvent)
    player.mouseCheckEvent = nil
  end

  if hovered then
    if player.fadeEvent then
      removeEvent(player.fadeEvent)
      player.fadeEvent = nil
    end

    player.timeline:setOpacity(1.0)

    player.mousePos = g_window.getMousePosition()
    player.mouseCheckEvent = scheduleEvent(function()
      checkMouseMoved(player)
    end, 2000)
  else
    if not player.fadeEvent then
      player.fadeEvent = scheduleEvent(function()
        g_effects.fadeOut(player.timeline, 250)
        player.fadeEvent = nil
      end, 1000)
    end
  end
end

local function play(player)
  player.video:play()
  player.timeline.playPause:setOn(true)
end

local function pause(player)
  player.video:pause()
  player.timeline.playPause:setOn(false)
end

local function playPause(player)
  if player.timeline.playPause:isOn() then
    player.video:pause()
  else
    player.video:play()
  end
  player.timeline.playPause:setOn(not player.timeline.playPause:isOn())
end

local wasFullscreen = false

local function fullscreen(player)
  local isPaused = player.video:isPaused()
  pause(player)

  if player.timeline.fullscreen:isOn() then
    if not wasFullscreen then
      g_window.setFullscreen(false)
    end

    player.resizeRight:show()
    player.resizeBottom:show()

    player:setSize(player.size)
  else
    wasFullscreen = g_window.isFullscreen()

    if not wasFullscreen then
      g_window.setFullscreen(true)
    end

    player.resizeRight:hide()
    player.resizeBottom:hide()

    scheduleEvent(function()
      player.size = player:getSize()
      player:setSize(g_window.getSize())
    end, 100)
  end
  player.timeline.fullscreen:setOn(not player.timeline.fullscreen:isOn())

  if not isPaused then
    play(player)
  end
end

local function onDragEnter(widget, mousePos)
  local player = widget:getParent():getParent()
  pause(player)
  return true
end

local function onDragLeave(widget)
  local player = widget:getParent():getParent()
  player.video:seek(widget.seek, true)
  return true
end

local lastSeek = nil
local function onDragMove(widget, mousePos, mouseMoved)
  if mouseMoved.x ~= 0 then
    local player = widget:getParent():getParent()
    if not lastSeek then
      lastSeek = scheduleEvent(function()
        mousePos = g_window.getMousePosition()
        local pos = widget:getPosition().x
        local width = math.max(0, math.min(player.timeline.bar:getWidth(), mousePos.x - pos))

        local video = player.video
        local frameIndex = math.floor(width / player.timeline.bar:getWidth() * video:getTotalFrames())
        widget.seek = frameIndex
        video:seek(widget.seek, true)
        lastSeek = nil
      end, 100)
    end
  end
end

local function onTimelineClick(widget)
  local player = widget:getParent():getParent()
  local mousePos = g_window.getMousePosition()
  local pos = widget:getPosition().x
  local width = math.max(0, math.min(player.timeline.bar:getWidth(), mousePos.x - pos))

  local video = player.video
  local frameIndex = math.floor(width / player.timeline.bar:getWidth() * video:getTotalFrames())
  video:seek(frameIndex, video:isPaused())
end

local function onVolumeDragEnter(widget, mousePos)
  return true
end

local function onVolumeDragLeave(widget)
  return true
end

local function onVolumeDragMove(widget, mousePos, mouseMoved)
  if mouseMoved.x ~= 0 then
    local player = widget:getParent():getParent()
    mousePos = g_window.getMousePosition()
    local pos = widget:getPosition().x
    local width = math.max(0, math.min(player.timeline.volume:getWidth(), mousePos.x - pos))

    local video = player.video
    local volume = math.floor(width / player.timeline.volume:getWidth() * 100)
    volume = math.min(100, volume)
    volume = math.max(0, volume)
    video:setVolume(volume / 100)

    player.timeline.volumeFill:setWidth(player.timeline.volume:getWidth() * (volume / 100))
  end
end

local function onVolumeClick(widget)
  local player = widget:getParent():getParent()
  local mousePos = g_window.getMousePosition()
  local pos = widget:getPosition().x
  local width = math.max(0, math.min(player.timeline.volume:getWidth(), mousePos.x - pos))

  local video = player.video
  local volume = math.floor(width / player.timeline.volume:getWidth() * 100)
  volume = math.min(100, volume)
  volume = math.max(0, volume)
  video:setVolume(volume / 100)

  player.timeline.volumeFill:setWidth(player.timeline.volume:getWidth() * (volume / 100))
end

local function formatTime(seconds)
  local minutes = math.floor(seconds / 60)
  seconds = seconds % 60
  return string.format("%d:%02d", minutes, seconds)
end

local function onNewFrame(video)
  local player = video:getParent()

  local elapsed = video:getElapsed()
  local duration = video:getDuration()

  local elapsedFormatted = formatTime(elapsed)
  local durationFormatted = formatTime(duration)

  local timeString = string.format("%s / %s", elapsedFormatted, durationFormatted)
  
  player.timeline.time:setText(timeString)
  player.timeline.fill:setWidth(player.timeline.bar:getWidth() * (video:getCurrentFrame() / video:getTotalFrames()))
end

local function onLoaded(video)
  local player = video:getParent()
  local elapsed = video:getElapsed()
  local duration = video:getDuration()

  local elapsedFormatted = formatTime(elapsed)
  local durationFormatted = formatTime(duration)
  
  local timeString = string.format("%s / %s", elapsedFormatted, durationFormatted)
  
  player.timeline.time:setText(string.format("%s / %s", durationFormatted, durationFormatted))
  player.timeline.time:setWidth(player.timeline.time:getTextSize().width)
  onNewFrame(video)
end

local function onVideoEnd(video)
  local player = video:getParent()

  onNewFrame(video)
  player.timeline.playPause:setOn(false)
end

function g_videoPlayer.create(title, path, width, height)
  local player = g_videoPlayer.players[path]
  if player then
    g_videoPlayer.destroy(player)
  end

  g_videoPlayer.players[path] = g_ui.displayUI("video_player")
  player = g_videoPlayer.players[path]
  player:setSize({ width = width, height = height })
  player.size = player:getSize()

  player.timeline.title:setText(title)
  player.timeline.bar.onDragEnter = onDragEnter
  player.timeline.bar.onDragLeave = onDragLeave
  player.timeline.bar.onDragMove = onDragMove
  player.timeline.bar.onClick = onTimelineClick

  connect(player.video, { onLoaded = onLoaded, onNewFrame = onNewFrame, onVideoEnd = onVideoEnd })
  player.video:setVideoSource(path)

  onPlayerHovered(player, false)
  player.onHoverChange = function(widget, hovered) onPlayerHovered(player, hovered) end
  player.onMouseMove = onMouseMove
  player.timeline.bar.onHoverChange = function(widget, hovered) onPlayerHovered(player, hovered) end
  player.timeline.playPause.onHoverChange = function(widget, hovered) onPlayerHovered(player, hovered) end
  player.timeline.fullscreen.onHoverChange = function(widget, hovered) onPlayerHovered(player, hovered) end
  player.onClick = function() playPause(player) end
  player.timeline.playPause.onClick = function() playPause(player) end
  player.timeline.fullscreen.onClick = function() fullscreen(player) end

  player.onKeyPress = function(widget, key)
    if key == KeyEscape then
      if player.timeline.fullscreen:isOn() then fullscreen(player) end
    end
    return true
  end

  player.timeline.volume.onDragEnter = onVolumeDragEnter
  player.timeline.volume.onDragLeave = onVolumeDragLeave
  player.timeline.volume.onDragMove = onVolumeDragMove
  player.timeline.volume.onClick = onVolumeClick
  player.timeline.volumeFill:setWidth(player.timeline.volume:getWidth() * (player.video:getVolume() / 1.0))

  play(player) -- Reprodução automática

  return player
end

function g_videoPlayer.destroy(player)
  if type(player) == "string" then
    player = g_videoPlayer.players[player]
  end
  if not player or not player:isVisible() then return end

  disconnect(player.video, { onLoaded = onLoaded, onNewFrame = onNewFrame, onVideoEnd = onVideoEnd })
  for path, p in pairs(g_videoPlayer.players) do
    if p == player then
      g_videoPlayer.players[path] = nil
      break
    end
  end
  player:destroy()
end

function g_videoPlayer.terminate()
  for path, player in pairs(g_videoPlayer.players) do
    g_videoPlayer.destroy(player)
  end
  g_videoPlayer.players = {}
end
