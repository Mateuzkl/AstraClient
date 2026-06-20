-- @docclass
g_tooltip = {}

-- private variables
local toolTipLabel
local currentHoveredWidget
local delayedTooltipEvent

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
  if not widget.tooltip then
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

  cycleEvent(function() checkTooltip() end, 100)
end

function g_tooltip.terminate()
  disconnect(UIWidget, { onStyleApply = onWidgetStyleApply,
                         onHoverChange = onWidgetHoverChange })

  currentHoveredWidget = nil
  toolTipLabel:destroy()
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

  connect(rootWidget, {
    onMouseMove = moveToolTip,
  })
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

  connect(rootWidget, {
    onMouseMove = moveToolTip,
  })
end

function g_tooltip.hide()
  removeEvent(delayedTooltipEvent)
  delayedTooltipEvent = nil
  g_effects.fadeOut(toolTipLabel, 100)
  toolTipLabel:hide()
  disconnect(rootWidget, {
    onMouseMove = moveToolTip,
  })
end

-- @docclass UIWidget @{

-- UIWidget extensions
function UIWidget:setTooltip(text)
  self.tooltip = text
end

function UIWidget:setTooltipFont(font)
  self.tooltipFont = font
end

function UIWidget:removeTooltip()
  self.tooltip = nil
end

function UIWidget:getTooltip()
  return self.tooltip
end

-- @}

g_tooltip.init()
connect(g_app, { onTerminate = g_tooltip.terminate })
