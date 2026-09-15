-- @docclass
g_videoTooltip = {}

-- private variables
local videoToolTip
local videoPlayer
local lastDisplayTime = 0 -- Para debounce

-- private functions
local function moveVideoToolTip(first)
  if not first and (not videoToolTip:isVisible() or videoToolTip:getOpacity() < 0.1) then return end

  local pos = g_window.getMousePosition()
  local windowSize = g_window.getSize()
  local labelSize = videoToolTip:getSize()

  pos.x = pos.x + 1
  pos.y = pos.y + 1

  if windowSize.width - (pos.x + labelSize.width) < 10 then
    pos.x = pos.x - labelSize.width - 3
  else
    pos.x = pos.x + 10
  end

  if windowSize.height - (pos.y + labelSize.height) < 10 then
    pos.y = pos.y - labelSize.height - 3
  else
    pos.y = pos.y + 10
  end

  videoToolTip:setPosition(pos)
end

function g_videoTooltip.display(widget)
  local now = os.time()
  if now - lastDisplayTime < 0.5 then return end -- Debounce de 500ms
  if type(widget.videoTooltip) ~= 'string' or widget.videoTooltip:len() == 0 then return end
  if not videoToolTip then return end

  -- Limpa vídeo anterior
  if videoPlayer then
    g_videoPlayer.destroy(videoPlayer)
    videoPlayer = nil
  end

  -- Desconecta eventos pendentes antes de criar um novo
  disconnect(rootWidget, { onMouseMove = moveVideoToolTip })

  -- Parseia o caminho e o tamanho (formato: "path|width|height")
  local videoData = widget.videoTooltip
  local videoPath, width, height = videoData:match("([^|]+)|(%d+)|(%d+)")
  if not videoPath then
    videoPath = videoData
    width = 320
    height = 240
  else
    width = tonumber(width) or 320
    height = tonumber(height) or 240
  end

  videoToolTip:setSize({width = width, height = height})
  videoPlayer = g_videoPlayer.create("Video Tooltip", videoPath, width, height)
  videoPlayer:setParent(videoToolTip)

  videoToolTip:show()
  videoToolTip:raise()
  videoToolTip:enable()
  g_effects.fadeIn(videoToolTip, 100)
  moveVideoToolTip(true)

  connect(rootWidget, { onMouseMove = moveVideoToolTip })
  lastDisplayTime = now
end

function g_videoTooltip.hide()
  if videoToolTip then
    g_effects.fadeOut(videoToolTip, 100)
    videoToolTip:hide()
    if videoPlayer then
      g_videoPlayer.destroy(videoPlayer)
      videoPlayer = nil
    end
    disconnect(rootWidget, { onMouseMove = moveVideoToolTip })
  end
end

-- public functions
function g_videoTooltip.init()
  addEvent(function()
    videoToolTip = g_ui.createWidget('UIWidget', rootWidget)
    videoToolTip:setId('videoToolTip')
    videoToolTip:setBackgroundColor('#111111cc')
    videoToolTip:hide()
  end)
end

function g_videoTooltip.terminate()
  if videoPlayer then
    g_videoPlayer.destroy(videoPlayer)
    videoPlayer = nil
  end
  if videoToolTip then
    videoToolTip:destroy()
    videoToolTip = nil
  end
  disconnect(rootWidget, { onMouseMove = moveVideoToolTip })

  g_videoTooltip = nil
end

-- UIWidget extensions for video tooltips
function UIWidget:setVideoTooltip(videoData)
  self.videoTooltip = videoData
  self.onHoverChange = function(widget, hovered)
    if hovered then
      if widget.videoTooltip and not g_mouse.isPressed() then
        g_videoTooltip.display(widget)
      end
    else
      g_videoTooltip.hide()
    end
  end
end

function UIWidget:removeVideoTooltip()
  self.videoTooltip = nil
  self.onHoverChange = nil
end

function UIWidget:getVideoTooltip()
  return self.videoTooltip
end

g_videoTooltip.init()
connect(g_app, { onTerminate = g_videoTooltip.terminate })