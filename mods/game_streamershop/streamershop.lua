--[[
  game_streamershop - Streamer Shop window over CommandBridge (opcode 211).

  The in-game store for the Streamer Coin economy. Streamer Coin is a VIRTUAL,
  account-scoped currency earned by manual staff delivery (the /streamercoin talkaction)
  and, next step, by the Twitch-affiliate crediter. This window lets the player browse
  the catalog, see their balance and buy products with those coins.

  SERVER-AUTHORITATIVE: this window renders the catalog the server sends and asks the
  server to buy. It never does game logic or trusts client-side numbers -- the balance
  and every purchase are owned and validated server-side (streamershop_otc_bridge.lua).

  Opened from the game_sidebuttons "streamerShopDialog" side button (registered there),
  which calls toggle()/close().

  Protocol (CommandBridge, streamershop.* actions - disjoint from casino.*/task.*/etc.):
    client -> server  { action="streamershop.state", data={} }              -> <catalog>
    client -> server  { action="streamershop.buy",   data={ id } }           -> <buyResult> | error
    server -> client  { event="streamershop.open",   data=<catalog> }  (push)
    server -> client  { event="streamershop.update", data=<catalog> }  (push, after a grant)

  <catalog> = { balance, currencyName, currencyIcon, earnHint, products = { <product>, ... } }
  <product> = { id, name, description, cost, itemId, count, outfit }
]]

-- ============================================================================
-- state
-- ============================================================================
local window
local balanceLabel, currencyTitle, earnHint, productList, statusLabel
local confirmWindow
local lastCatalog
local openHandler, updateHandler
local stateTimeout, buyTimeout
local stateLoaded = false
local buyPending = false

-- Client-side "don't ask again" preference (persisted via g_settings).
local SKIP_BUY = 'streamershop.skipBuyConfirm'

-- ============================================================================
-- rendering
-- ============================================================================
-- Clear the product grid and show a status message (loading / error / empty).
function setEmpty(text)
  if productList then productList:destroyChildren() end
  if statusLabel then
    statusLabel:setText(text or '')
    statusLabel:setVisible((text or '') ~= '')
  end
end

function fillCard(card, p)
  local balance = (lastCatalog and lastCatalog.balance) or 0

  -- Sprite: an outfit preview (UICreature) if the product ships one, else the item sprite.
  local iconItem = card:recursiveGetChildById('item')
  local iconCreature = card:recursiveGetChildById('creature')
  local outfit = p.outfit
  if type(outfit) == 'table' and ((outfit.type or outfit.lookType or 0) > 0) then
    -- setOutfit reads the `type` key (client-wide convention); the server sends `lookType`.
    outfit.type = outfit.type or outfit.lookType
    if iconCreature then iconCreature:setOutfit(outfit) iconCreature:show() end
    if iconItem then iconItem:hide() end
  else
    if iconItem then iconItem:setItemId(p.itemId or 0) iconItem:show() end
    if iconCreature then iconCreature:hide() end
  end

  local nameLabel = card:recursiveGetChildById('nameLabel')
  if nameLabel then nameLabel:setText(p.name or '') end

  local descLabel = card:recursiveGetChildById('descLabel')
  if descLabel then
    descLabel:setText(p.description or '')
    descLabel:setTooltip(p.description or '')
  end

  local costLabel = card:recursiveGetChildById('costLabel')
  if costLabel then costLabel:setText('$' .. comma_value(p.cost or 0)) end

  local buyButton = card:recursiveGetChildById('buyButton')
  if buyButton then
    local afford = balance >= (p.cost or 0)
    buyButton:setEnabled(afford)
    if afford then
      buyButton:setTooltip(tr('Buy %s', p.name or ''))
    else
      buyButton:setTooltip(tr('Not enough %s', (lastCatalog and lastCatalog.currencyName) or 'coins'))
    end
    buyButton.onClick = function() requestBuy(p) end
  end
end

function renderProducts()
  if not productList then return end
  productList:destroyChildren()
  local products = (lastCatalog and lastCatalog.products) or {}
  if #products == 0 then
    if statusLabel then
      statusLabel:setText(tr('No products available right now.'))
      statusLabel:setVisible(true)
    end
    return
  end
  if statusLabel then statusLabel:setVisible(false) end
  for _, p in ipairs(products) do
    local card = g_ui.createWidget('StreamerShopCard', productList)
    fillCard(card, p)
  end
end

function render()
  if not window or not lastCatalog then return end
  local cat = lastCatalog
  if balanceLabel then setMoneyAutoFit(balanceLabel, cat.balance or 0) end
  if currencyTitle then currencyTitle:setText(cat.currencyName or tr('Streamer Coins')) end
  if earnHint then earnHint:setText(cat.earnHint or '') end
  renderProducts()
end

function applyCatalog(cat)
  if type(cat) ~= 'table' then return end
  lastCatalog = cat
  render()
end

-- ============================================================================
-- confirm dialog (Buy) with "don't ask again"
-- ============================================================================
function closeConfirm()
  if confirmWindow then confirmWindow:destroy() confirmWindow = nil end
end

-- otui @onEscape hook (bare so modules.game_streamershop.cancelConfirm resolves).
function cancelConfirm()
  closeConfirm()
end

-- opts = { title, message, skipKey, onConfirm }
function showConfirm(opts)
  if opts.skipKey and g_settings.getBoolean(opts.skipKey) then
    if opts.onConfirm then opts.onConfirm() end
    return
  end

  closeConfirm()
  confirmWindow = g_ui.createWidget('StreamerShopConfirm', g_ui.getRootWidget())
  if not confirmWindow then
    if opts.onConfirm then opts.onConfirm() end
    return
  end

  confirmWindow:setText(opts.title or tr('Confirm Purchase'))
  local msg = confirmWindow:recursiveGetChildById('confirmMessage')
  if msg then msg:setText(opts.message or '') end
  local skip = confirmWindow:recursiveGetChildById('confirmSkip')
  if skip then skip:setChecked(false) end

  local finish = function(confirmed)
    if confirmed and opts.skipKey and skip and skip:isChecked() then
      g_settings.set(opts.skipKey, true)
      g_settings.save()
    end
    closeConfirm()
    if confirmed and opts.onConfirm then opts.onConfirm() end
  end

  local yes = confirmWindow:recursiveGetChildById('confirmYes')
  local no = confirmWindow:recursiveGetChildById('confirmNo')
  if yes then yes.onClick = function() finish(true) end end
  if no then no.onClick = function() finish(false) end end
  confirmWindow.onEscape = function() finish(false) end

  confirmWindow:raise()
  confirmWindow:focus()
end

-- ============================================================================
-- server requests
-- ============================================================================
function requestState()
  if not g_game.isOnline() then return end
  if not CommandBridge or not CommandBridge.request then
    setEmpty(tr('Command bridge unavailable. Please relog.'))
    return
  end

  stateLoaded = false
  setEmpty(tr('Loading the Streamer Shop...'))
  if stateTimeout then removeEvent(stateTimeout) end
  stateTimeout = scheduleEvent(function()
    stateTimeout = nil
    if not stateLoaded then
      setEmpty(tr('Could not load the shop. Reopen the window or relog.'))
    end
  end, 4000)

  CommandBridge.request('streamershop.state', {}, function(response)
    stateLoaded = true
    if stateTimeout then removeEvent(stateTimeout) stateTimeout = nil end
    if type(response) ~= 'table' then return end
    if response.type == 'error' then
      setEmpty(response.message or tr('Failed to load the shop.'))
      return
    end
    applyCatalog(response.data or response)
  end)
end

-- Ask the server whether this account is a partnered streamer, then show/hide the Streamer Shop side
-- button accordingly. Server-authoritative: the shop's state/buy are gated the same way server-side,
-- so hiding the icon is UX only. Pull (not push) so it can never race the client's login readiness.
function requestEnabled()
  if not CommandBridge or not CommandBridge.request then return end
  CommandBridge.request('streamershop.enabled', {}, function(response)
    local enabled = false
    if type(response) == 'table' then
      local data = response.data or response
      enabled = type(data) == 'table' and data.enabled == true
    end
    local sb = modules.game_sidebuttons
    if sb and sb.setStreamerShopEnabled then
      sb.setStreamerShopEnabled(enabled)
    end
  end)
end

-- Asks for confirmation (unless suppressed), then buys.
function requestBuy(p)
  if type(p) ~= 'table' or not p.id or buyPending then return end
  local balance = (lastCatalog and lastCatalog.balance) or 0
  if (p.cost or 0) > balance then return end
  local currencyName = (lastCatalog and lastCatalog.currencyName) or tr('Streamer Coins')
  showConfirm({
    title = tr('Confirm Purchase'),
    message = tr('Buy %s for %s %s?', p.name or p.id, comma_value(p.cost or 0), currencyName),
    skipKey = SKIP_BUY,
    onConfirm = function() doBuy(p.id) end,
  })
end

function doBuy(id)
  if not id or buyPending then return end
  if not CommandBridge or not CommandBridge.request then return end

  buyPending = true
  if buyTimeout then removeEvent(buyTimeout) end
  buyTimeout = scheduleEvent(function()
    buyTimeout = nil
    buyPending = false
  end, 6000)

  CommandBridge.request('streamershop.buy', { id = id }, function(response)
    buyPending = false
    if buyTimeout then removeEvent(buyTimeout) buyTimeout = nil end
    if type(response) ~= 'table' then return end
    if response.type == 'error' then
      displayErrorBox(tr('Streamer Shop'), response.message or tr('Purchase failed.'))
      return
    end
    -- Server returns the authoritative new balance; re-render so affordability updates.
    local data = response.data or response
    if type(data) == 'table' and data.balance ~= nil and lastCatalog then
      lastCatalog.balance = data.balance
      render()
    end
  end)
end

-- ============================================================================
-- window lifecycle
-- ============================================================================
-- Create the window once (lazily, on first open) so every style/token is loaded and we
-- never build UI at client boot. Resolves the child refs used by render().
local function ensureWindow()
  if window then return true end
  window = g_ui.createWidget('StreamerShopWindow', g_ui.getRootWidget())
  if not window then return false end
  window:hide()
  balanceLabel  = window:recursiveGetChildById('balanceLabel')
  currencyTitle = window:recursiveGetChildById('currencyTitle')
  earnHint      = window:recursiveGetChildById('earnHint')
  productList   = window:recursiveGetChildById('productList')
  statusLabel   = window:recursiveGetChildById('statusLabel')
  if statusLabel then statusLabel:setVisible(false) end
  return true
end

function show()
  if not ensureWindow() then return end
  window:show()
  window:raise()
  window:focus()
end

function close()
  if not window then return end
  closeConfirm()
  window:hide()
end

function toggle()
  if not ensureWindow() then return end
  if window:isVisible() then
    close()
  else
    show()
    requestState()
  end
end

-- server push: force the window open (optional server-side opener)
function onOpenEvent(data)
  local cat = data and (data.data or data)
  show()
  if type(cat) == 'table' then applyCatalog(cat) end
end

-- server push: balance/catalog changed (manual grant, external change) while open
function onUpdateEvent(data)
  local cat = data and (data.data or data)
  if type(cat) == 'table' and window and window:isVisible() then
    applyCatalog(cat)
  end
end

-- ============================================================================
-- init / terminate
-- ============================================================================
function onGameStart()
  if CommandBridge and CommandBridge.on then
    openHandler = onOpenEvent
    updateHandler = onUpdateEvent
    CommandBridge.on('streamershop.open', openHandler)
    CommandBridge.on('streamershop.update', updateHandler)
  end
  -- Resolve the side-button entitlement for this login (streamer accounts only).
  requestEnabled()
end

function onGameEnd()
  if CommandBridge and CommandBridge.off then
    if openHandler then CommandBridge.off('streamershop.open', openHandler) openHandler = nil end
    if updateHandler then CommandBridge.off('streamershop.update', updateHandler) updateHandler = nil end
  end
  -- Hide the icon again so a stale streamer entitlement can't carry into the next login on this client.
  local sb = modules.game_sidebuttons
  if sb and sb.setStreamerShopEnabled then
    sb.setStreamerShopEnabled(false)
  end
  close()
end

function init()
  if g_logger then g_logger.info('[streamershop] client module loaded') end

  g_settings.setDefault(SKIP_BUY, false)

  -- Register styles now; the window itself is created lazily on first open (ensureWindow).
  g_ui.importStyle(resolvepath('streamershop'))

  connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  onGameEnd()

  if stateTimeout then removeEvent(stateTimeout) stateTimeout = nil end
  if buyTimeout then removeEvent(buyTimeout) buyTimeout = nil end
  closeConfirm()
  if window then window:destroy() window = nil end
end
