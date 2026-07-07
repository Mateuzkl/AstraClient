tradeWindow = nil

function init()
  g_ui.importStyle('tradewindow')

  connect(g_game, { onOwnTrade = onGameOwnTrade,
                    onCounterTrade = onGameCounterTrade,
                    onCloseTrade = onGameCloseTrade,
                    onGameEnd = onGameCloseTrade })
end

function terminate()
  disconnect(g_game, { onOwnTrade = onGameOwnTrade,
                       onCounterTrade = onGameCounterTrade,
                       onCloseTrade = onGameCloseTrade,
                       onGameEnd = onGameCloseTrade })

  if tradeWindow then
    tradeWindow:destroy()
  end
end

function createTrade()
  tradeWindow = g_ui.createWidget('TradeWindow', m_interface.getRightPanel())
  -- The 'TradeWindow' style carries no id, so the panel-placement special cases
  -- (m_interface.addToPanels / recalculateWidgetOnPanel and the drag block list)
  -- never recognised it. Tag it so it is treated as a proper trade window.
  tradeWindow:setId('tradeWindow')
  tradeWindow:setup()

  -- Place it like every other mini window: look across the side panels for room
  -- and, for the trade window specifically, free a backpack slot as a last
  -- resort. Without this the window stayed pinned to the full main panel and
  -- rendered cut off past the screen edge instead of finding/making space.
  if not m_interface.addToPanels(tradeWindow) then
    tradeWindow:destroy()
    tradeWindow = nil
    return false
  end

  -- Set onClose after addToPanels, since configureWidgetOnPanel installs its own
  -- onClose handler that would otherwise clobber the trade-reject behaviour.
  tradeWindow.onClose = function()
    g_game.rejectTrade()
    tradeWindow:hide()
  end

  -- Escape rejects the trade (same as the Cancel/Reject button); Enter accepts, but only
  -- once the Accept button is actually shown and still enabled (a counter-offer arrived
  -- and it hasn't been accepted yet).
  tradeWindow.onEscape = function()
    g_game.rejectTrade()
  end
  tradeWindow.onEnter = function()
    local acceptButton = tradeWindow:recursiveGetChildById('acceptButton')
    if acceptButton and acceptButton:isVisible() and acceptButton:isEnabled() then
      g_game.acceptTrade()
    end
  end

  return true
end

function fillTrade(name, items, counter)
  if not tradeWindow then
    if not createTrade() then
      return
    end
  end

  local tradeContainer
  local label
  if counter then
    tradeContainer = tradeWindow:recursiveGetChildById('counterTradeContainer')
    label = tradeWindow:recursiveGetChildById('counterTradeLabel')
    tradeWindow:recursiveGetChildById('acceptButton'):show()
    tradeWindow:recursiveGetChildById('waitForCounter'):hide()
    tradeWindow:recursiveGetChildById('rejectButton'):setText("Reject")
  else
    tradeContainer = tradeWindow:recursiveGetChildById('ownTradeContainer')
    label = tradeWindow:recursiveGetChildById('ownTradeLabel')
  end
  label:setText(short_text(string.capitalize(name), 12))
  label:setTooltip(name)

  tradeWindow:setContentMinimumHeight(76)

  for index,item in ipairs(items) do
    local itemWidget = g_ui.createWidget('Item', tradeContainer)
    itemWidget:setItem(item)
    itemWidget:setVirtual(true)
    itemWidget:setMargin(0)
    itemWidget.onClick = function()
      g_game.inspectTrade(counter, index-1)
    end
  end
end

function onGameOwnTrade(name, items)
  fillTrade(name, items, false)
end

function onGameCounterTrade(name, items)
  fillTrade(name, items, true)
end

function onGameCloseTrade()
  if tradeWindow then
    tradeWindow:destroy()
    tradeWindow = nil
  end
end
