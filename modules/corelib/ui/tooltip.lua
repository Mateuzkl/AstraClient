-- @docclass
g_tooltip = {}

-- private variables
local toolTipLabel
local currentHoveredWidget
local tooltipCheckEvent
local delayedTooltipEvent
local mouseMoveConnected = false

function checkTooltip()
  if currentHoveredWidget and toolTipLabel then
    if not toolTipLabel:getColoredText() then
      toolTipLabel:setText(currentHoveredWidget:getTooltip())
    end
  end
end

-- private functions
local function moveToolTip(first)
  if not first and (not toolTipLabel:isVisible() or toolTipLabel:getOpacity() < 0.1) then return end

  local pos = g_window.getMousePosition()
  local windowSize = g_window.getSize()
  local labelSize = toolTipLabel:getSize()

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

  toolTipLabel:setPosition(pos)
end

local function connectMouseMove()
  if mouseMoveConnected then
    return
  end

  connect(rootWidget, { onMouseMove = moveToolTip })
  mouseMoveConnected = true
end

local function disconnectMouseMove()
  if not mouseMoveConnected then
    return
  end

  disconnect(rootWidget, { onMouseMove = moveToolTip })
  mouseMoveConnected = false
end

function displayScheduledTooltip(widget)
  if not currentHoveredWidget or currentHoveredWidget ~= widget then
    return
  end

  if toolTipLabel and toolTipLabel:isVisible() then
    return
  end

  g_tooltip.display(widget)
end

local function onWidgetHoverChange(widget, hovered)
  if hovered then
    if widget.tooltip and not g_mouse.isPressed() then
      if widget.tooltipDelayed then
        removeEvent(delayedTooltipEvent)
        delayedTooltipEvent = scheduleEvent(function()
          delayedTooltipEvent = nil
          displayScheduledTooltip(widget)
        end, 700)
      else
        removeEvent(delayedTooltipEvent)
        delayedTooltipEvent = nil
        g_tooltip.display(widget)
      end
      currentHoveredWidget = widget
    elseif widget.parseColoreDisplay and not g_mouse.isPressed() then
      removeEvent(delayedTooltipEvent)
      delayedTooltipEvent = nil
      g_tooltip.parseColoreDisplay(widget.parseColoreDisplay)
      currentHoveredWidget = widget
    end
  else
    if widget == currentHoveredWidget then
      removeEvent(delayedTooltipEvent)
      delayedTooltipEvent = nil
      g_tooltip.hide()
      currentHoveredWidget = nil
    end
  end

  -- Hotfix
  if not widget.tooltip and not widget.parseColoreDisplay then
    g_tooltip.hide()
    currentHoveredWidget = nil
  end
end

local function onWidgetStyleApply(widget, styleName, styleNode)
  if styleNode.tooltip then
    widget.tooltip = styleNode.tooltip
  end

  if styleNode["tooltip-font"] then
    widget.tooltipFont = styleNode["tooltip-font"]
  elseif styleNode["tooltip-delayed"] then
    widget.tooltipDelayed = styleNode["tooltip-delayed"]
  end

  local tooltipWidget = widget:getChildById('toolTipWidget')
  if widget:getId() == 'toolTipWidget' then
    tooltipWidget = widget
    widget = widget:getParent()
  end
  if tooltipWidget then
    if widget.tooltip then
      tooltipWidget.tooltip = widget.tooltip
      widget.tooltip = nil
    end
    if widget.parseColoreDisplay then
      tooltipWidget.parseColoreDisplay = widget.parseColoreDisplay
      widget.parseColoreDisplay = nil
    end
    if tooltipWidget.tooltip or tooltipWidget.parseColoreDisplay then
      tooltipWidget:setOpacity(1)
    else
      tooltipWidget:setOpacity(0.4)
    end
  end
end

function g_tooltip.onWidgetStyleApply(widget, styleName, styleNode)
  onWidgetStyleApply(widget, styleName, styleNode)
end

function g_tooltip.onWidgetHoverChange(widget, hovered)
  onWidgetHoverChange(widget, hovered)
end

-- public functions
function g_tooltip.init()
  connect(UIWidget, {  onStyleApply = onWidgetStyleApply,
                       onHoverChange = onWidgetHoverChange})

  addEvent(function()
    toolTipLabel = g_ui.createWidget('UILabel', rootWidget)
    toolTipLabel:setId('toolTip')
    toolTipLabel:setBackgroundColor('#111111cc')
    toolTipLabel:setTextAlign(AlignNone)
    toolTipLabel:setTextOffset(topoint(3 .. " " .. 2))
    toolTipLabel:hide()
  end)

  tooltipCheckEvent = cycleEvent(function() checkTooltip() end, 100)
end

function g_tooltip.terminate()
  disconnect(UIWidget, { onStyleApply = onWidgetStyleApply,
                         onHoverChange = onWidgetHoverChange })

  currentHoveredWidget = nil
  disconnectMouseMove()
  removeEvent(delayedTooltipEvent)
  delayedTooltipEvent = nil
  removeEvent(tooltipCheckEvent)
  tooltipCheckEvent = nil
  if toolTipLabel then
    g_effects.cancelFade(toolTipLabel)
    toolTipLabel:destroy()
  end
  toolTipLabel = nil

  g_tooltip = nil
end

function g_tooltip.display(widget)
  local text = widget.tooltip
  if (type(text) == 'string' and text:len() == 0) or (type(text) == 'table' and #text == 0) then return end
  if not toolTipLabel then return end

  if type(text) == 'string' then
    toolTipLabel:setText(text)
  elseif type(text) == 'table' then
    toolTipLabel:setColoredText(text)
  end
  toolTipLabel:setFont((widget.tooltipFont and widget.tooltipFont or "Verdana Bold-11px"))
  toolTipLabel:resizeToText()
  toolTipLabel:resize(toolTipLabel:getWidth() + 8, toolTipLabel:getHeight() + 4)
  toolTipLabel:setBackgroundColor("#c0c0c0")
  toolTipLabel:setColor("#3f3f3f")
  toolTipLabel:setBorderWidth(1)
  toolTipLabel:setBorderColor("#000000")
  toolTipLabel:show()
  toolTipLabel:raise()
  toolTipLabel:enable()
  g_effects.fadeIn(toolTipLabel, 100)
  moveToolTip(true)

  connectMouseMove()
end

function g_tooltip.displayText(text)
  if (type(text) == 'string' and text:len() == 0) or (type(text) == 'table' and #text == 0) then return end
  if not toolTipLabel then return end

  if type(text) == 'string' then
    toolTipLabel:setText(text)
  elseif type(text) == 'table' then
    toolTipLabel:setColoredText(text)
  end
  toolTipLabel:setFont("Verdana Bold-11px")
  toolTipLabel:resizeToText()
  toolTipLabel:resize(toolTipLabel:getWidth() + 8, toolTipLabel:getHeight() + 4)
  toolTipLabel:setBackgroundColor("#c0c0c0")
  toolTipLabel:setColor("#3f3f3f")
  toolTipLabel:setBorderWidth(1)
  toolTipLabel:setBorderColor("#000000")
  toolTipLabel:show()
  toolTipLabel:raise()
  toolTipLabel:enable()
  g_effects.fadeIn(toolTipLabel, 100)
  moveToolTip(true)

  connectMouseMove()
end

function g_tooltip.parseColoreDisplay(text)
  if not text or text:len() == 0 then return end
  if not toolTipLabel then return end

  toolTipLabel:setColorText(text)
  toolTipLabel:setFont("Verdana Bold-11px")
  toolTipLabel:resizeToText()
  toolTipLabel:resize(toolTipLabel:getWidth() + 8, toolTipLabel:getHeight() + 4)
  toolTipLabel:setBackgroundColor("#c0c0c0")
  toolTipLabel:setColor("#3f3f3f")
  toolTipLabel:setBorderWidth(1)
  toolTipLabel:setBorderColor("#000000")
  toolTipLabel:show()
  toolTipLabel:raise()
  toolTipLabel:enable()
  g_effects.fadeIn(toolTipLabel, 100)
  moveToolTip(true)

  connectMouseMove()
end

function g_tooltip.hide()
  if not toolTipLabel then
    return
  end

  removeEvent(delayedTooltipEvent)
  delayedTooltipEvent = nil
  g_effects.cancelFade(toolTipLabel)
  toolTipLabel:hide()
  disconnectMouseMove()
end

-- @docclass UIWidget @{

-- UIWidget extensions
function UIWidget:setTooltip(text)
  local tooltipWidget = self:getChildById('toolTipWidget')
  if tooltipWidget then
    tooltipWidget.tooltip = text
  else
    self.tooltip = text
  end
end

function UIWidget:setTooltipFont(font)
  self.tooltipFont = font
end

function UIWidget:parseColoreDisplayToolTip(text)
  local tooltipWidget = self:getChildById('toolTipWidget')
  if tooltipWidget then
    tooltipWidget.parseColoreDisplay = text
  else
    self.parseColoreDisplay = text
  end
end

function UIWidget:removeTooltip()
  self.tooltip = nil
  self.parseColoreDisplay = nil
end

function UIWidget:getTooltip()
  return self.tooltip
end

-- @}

g_tooltip.init()
connect(g_app, { onTerminate = g_tooltip.terminate })
