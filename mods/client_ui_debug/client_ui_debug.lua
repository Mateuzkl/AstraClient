local clientUiDebug
local clientUiDebugLabel
local clientUiDebugHighlightWidget
local clientUiDebugActivateButton
local clientUiDrawActivateButton
local clientUiConsoleActivateButton
local enabled = true
local enabledDraw = true

function onClientUiDebuggerMouseMove(mouseBindWidget, mousePos, mouseMove)
    if not DEVELOPERMODE then
        return
    end

    local widgets = rootWidget:recursiveGetChildrenByPos(mousePos)

    local smallestWidget
    for _, widget in pairs(widgets) do
        if (widget:getId() ~= 'highlightWidget' and widget:getId() ~= 'toolTip') then
            if (not smallestWidget or
                    (widget:getSize().width <= smallestWidget:getSize().width and widget:getSize().height <= smallestWidget:getSize().height)
            ) then
                smallestWidget = widget
            end
        end
    end
    if smallestWidget then
        clientUiDebugHighlightWidget:setPosition(smallestWidget:getPosition())
        clientUiDebugHighlightWidget:setSize(smallestWidget:getSize())
        clientUiDebugHighlightWidget:raise()
    end

    local widgetNames = {}
    for wi = #widgets, 1, -1 do
        local widget = widgets[wi]
        if (widget:getId() ~= 'highlightWidget') then
            table.insert(widgetNames, widget:getClassName() .. '#' .. widget:getId() .. (widget.instance and ' (' .. widget.instance .. ')' or ''))
        end
    end
    clientUiDebugLabel:setText(table.concat(widgetNames, " -> "))
end

function activate()
  enabled = not enabled
  if enabled then
    clientUiDebugLabel:setVisible(true)
    clientUiDebug:setPhantom(false)
    clientUiDebugActivateButton:setColor('#FF0000')
    connect(rootWidget, {
        onMouseMove = onClientUiDebuggerMouseMove,
    })
  else
    clientUiDebugLabel:setVisible(false)
    clientUiDebug:setPhantom(true)
    clientUiDebugActivateButton:setColor('#00FF00')
    clientUiDebugHighlightWidget:setSize({0, 0})
    --clientUiDebugLabel:setText("")
    disconnect(rootWidget, {
        onMouseMove = onClientUiDebuggerMouseMove,
    })
  end
end

function activateDraw()
  enabledDraw = not enabledDraw
  if enabledDraw then
    clientUiDrawActivateButton:setColor('#FF0000')
  else
    clientUiDrawActivateButton:setColor('#00FF00')
  end
  g_ui.setDebugBoxesDrawing(not g_ui.isDrawingDebugBoxes())
end

-- Opens/closes the dev terminal ("PumpkinBot console"). It now boots hidden, so this
-- button (and Ctrl+T) is how devs bring it up. Red = open, green = closed, matching
-- the Draw/Debug buttons.
function toggleConsole()
  if not modules.client_terminal then
    return
  end
  modules.client_terminal.toggle()
  if clientUiConsoleActivateButton then
    clientUiConsoleActivateButton:setColor(modules.client_terminal.isVisible() and '#FF0000' or '#00FF00')
  end
end

function init()
    connect(rootWidget, {
        onMouseMove = onClientUiDebuggerMouseMove,
    })
    if not DEVELOPERMODE then
        return
    end
    clientUiDebug = g_ui.displayUI('client_ui_debug')
    clientUiDebugLabel = clientUiDebug:getChildById('clientUiDebugLabel')
    clientUiDebugHighlightWidget = g_ui.createWidget('HighlightWidget', rootWidget)
    clientUiDebugActivateButton = clientUiDebug:getChildById('activateButton')
    clientUiDrawActivateButton = clientUiDebug:getChildById('activateDrawButton')
    clientUiConsoleActivateButton = clientUiDebug:getChildById('activateConsoleButton')
    clientUiConsoleActivateButton:setColor('#00FF00') -- terminal boots hidden
    activate()
end

function terminate()
    disconnect(rootWidget, {
        onMouseMove = onClientUiDebuggerMouseMove,
    })
    if not DEVELOPERMODE then
        return
    end
    clientUiDebug:destroy()
    clientUiDebugHighlightWidget:destroy()
end

function toggleVisible()
    if not g_app.isDevMode() then
        clientUiDebug:setVisible(false)
    else
        clientUiDebug:setVisible(true)
    end
end