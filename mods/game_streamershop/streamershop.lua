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
  <product> = { id, name, description, cost, itemId, count, outfit, offers }
            offers = { { count, cost }, ... } -> multi-tier quantity selector (top-right of the card)
]]

-- ============================================================================
-- state
-- ============================================================================
local window
local balanceLabel, currencyTitle, earnHint, productList, statusLabel
local sidebar
-- Sidebar category buttons, keyed by tab key (built in ensureWindow from TABS).
local tabButtons = {}
local redeemButton
local confirmWindow
local detailsWindow
local lastCatalog
local openHandler, updateHandler
local stateTimeout, buyTimeout, redeemTimeout
local stateLoaded = false
local buyPending = false
local redeemPending = false

-- Which tab's products are shown. Products carry a matching `tab` field from the server;
-- renderProducts() filters the grid by this.
local currentTab = 'general'

-- Remembers the quantity tier picked per product id, so a re-render (after a buy or a server push)
-- restores the player's selection instead of snapping the selector back to x1. Survives the whole
-- session (cards are destroyed/recreated on every render; this table is not).
local selectedOffers = {}

-- Sidebar categories, in order. Keys MUST match the `tab` the server tags products with:
-- addons/mounts MIRROR the GameStore's outfits/mounts (priced in Streamer Coins); general/items/
-- magicwall/preycharm/bossboost/house are the streamer shop's own curated products.
local TABS = {
  { key = 'general',   label = 'General' },
  { key = 'addons',    label = 'Addons' },
  { key = 'mounts',    label = 'Mounts' },
  { key = 'items',     label = 'Items' },
  { key = 'magicwall', label = 'Magic Wall' },
  { key = 'preycharm', label = 'Prey & Charm' },
  { key = 'bossboost', label = 'Boss & Boost' },
  { key = 'house',     label = 'House' },
}

-- Client-side "don't ask again" preference (persisted via g_settings).
local SKIP_BUY = 'streamershop.skipBuyConfirm'

-- Store offer icons (PNG) for delegated GameStore offers that ship no item sprite -- keyed by
-- the product name the server sends. Files live in data/images/store/offers/ (copied from the
-- site's store assets). Without this the server's fallback sprite (a coin) would show instead.
local OFFER_IMAGE_DIR = '/images/store/offers/'
local OFFER_IMAGE = {
  ['XP Boost']            = 'XP_Boost.png',
  ['Automatic Boss']      = 'Automatic_Boss.png',
  ['Prey Wildcard']       = 'Prey_Bonus_Reroll.png',
  ['Permanent Prey Slot'] = 'Permanent_Prey_Slot.png',
  ['Charm Expansion']     = 'Charm_Expansion_Offer.png',
  ['Task Enhancement']    = 'Task_Enhancement.png',
  ['Gem Extender']        = 'Gem_Extender.png',
}

-- ============================================================================
-- rendering
-- ============================================================================
-- Show the right icon on a card/dialog: a store PNG for delegated offers with no item sprite,
-- else the outfit/mount creature preview, else the item sprite. Same logic for card and dialog
-- (they just pass their own child ids). One of the three child widgets is shown, the rest hidden.
function applyProductIcon(container, itemId, creatureId, imageId, p)
  local iconItem = container:recursiveGetChildById(itemId)
  local iconCreature = container:recursiveGetChildById(creatureId)
  local iconImage = container:recursiveGetChildById(imageId)
  -- Only the GameStore-mirrored tabs use the store PNGs; the General tab keeps its item sprites
  -- (e.g. the starter "Prey Wildcard", item 60101, which shares a name with the store offer).
  local imgName = ((p.tab or 'general') ~= 'general') and OFFER_IMAGE[p.name or ''] or nil
  local outfit = p.outfit
  if imgName then
    if iconImage then iconImage:setImageSource(OFFER_IMAGE_DIR .. imgName) iconImage:show() end
    if iconItem then iconItem:hide() end
    if iconCreature then iconCreature:hide() end
  elseif type(outfit) == 'table' and ((outfit.type or outfit.lookType or 0) > 0) then
    -- Server sends a ready-to-render outfit table: `type` (+ `addons`) for an outfit, or the
    -- mount's client appearance id as `type` for a mount. (lookType kept as a legacy fallback.)
    outfit.type = outfit.type or outfit.lookType
    if iconCreature then iconCreature:setOutfit(outfit) iconCreature:show() end
    if iconItem then iconItem:hide() end
    if iconImage then iconImage:hide() end
  else
    if iconItem then iconItem:setItemId(p.itemId or 0) iconItem:show() end
    if iconCreature then iconCreature:hide() end
    if iconImage then iconImage:hide() end
  end
end
-- Clear the product grid and show a status message (loading / error / empty).
function setEmpty(text)
  if productList then productList:destroyChildren() end
  if statusLabel then
    statusLabel:setText(text or '')
    statusLabel:setVisible((text or '') ~= '')
  end
end

-- Currently selected offer variant of a card, or nil for a single-price product (use p.cost/p.count).
-- Multi-offer products carry p.offers = { {count,cost}, ... }; card.selectedOffer is the picked index.
function cardVariant(card)
  local p = card.product
  if type(p) ~= 'table' then return nil end
  local offers = p.offers
  if type(offers) == 'table' and #offers > 0 then
    local i = card.selectedOffer or 1
    if i < 1 or i > #offers then i = 1 end
    return offers[i]
  end
  return nil
end

-- Streamer-Coin price of the card's current selection (variant price, else the flat product price).
function cardCost(card)
  local v = cardVariant(card)
  if v then return v.cost or 0 end
  return (card.product and card.product.cost) or 0
end

-- Refresh the price label + Buy affordability/handlers for the card's current offer selection. Called
-- once on fill and again whenever the quantity selector changes.
function updateCardOffer(card)
  local p = card.product
  if type(p) ~= 'table' then return end
  local balance = (lastCatalog and lastCatalog.balance) or 0
  local cost = cardCost(card)

  local costLabel = card:recursiveGetChildById('costLabel')
  if costLabel then costLabel:setText('$' .. comma_value(cost)) end

  -- Details button opens the dialog with the full description (bonuses etc.), same offer selection.
  local detailsButton = card:recursiveGetChildById('detailsButton')
  if detailsButton then
    detailsButton.onClick = function() showDetails(p, card.selectedOffer) end
  end

  local buyButton = card:recursiveGetChildById('buyButton')
  if buyButton then
    if p.owned then
      -- Cosmetic the character already has: grey it out, no purchase (server rejects too).
      buyButton:setText(tr('Owned'))
      buyButton:setEnabled(false)
      buyButton:setTooltip(tr('You already own this.'))
      buyButton.onClick = nil
    else
      buyButton:setText(tr('Buy'))
      local afford = balance >= cost
      buyButton:setEnabled(afford)
      if afford then
        buyButton:setTooltip(tr('Buy %s', p.name or ''))
      else
        buyButton:setTooltip(tr('Not enough %s', (lastCatalog and lastCatalog.currencyName) or 'coins'))
      end
      buyButton.onClick = function() requestBuy(p, card.selectedOffer) end
    end
  end
end

function fillCard(card, p)
  card.product = p
  -- Restore the tier this product was last set to (survives re-render); default x1. Clamped below
  -- once we know how many tiers this product currently has.
  card.selectedOffer = selectedOffers[p.id] or 1

  -- Icon: store PNG (delegated offers w/o sprite), else outfit/mount creature, else item sprite.
  applyProductIcon(card, 'item', 'creature', 'image', p)

  local nameLabel = card:recursiveGetChildById('nameLabel')
  if nameLabel then nameLabel:setText(p.name or '') end

  -- Quantity selector (top-right corner): shown ONLY for multi-offer products. Each option is a tier
  -- ("x1"/"x10"...) whose data is the tier's 1-based index; picking one updates the price and the index
  -- sent to the server on buy, and is remembered so the next render keeps it. Single-price products
  -- hide the selector entirely.
  local offerSelect = card:recursiveGetChildById('offerSelect')
  if offerSelect then
    offerSelect:clearOptions()
    local offers = p.offers
    if type(offers) == 'table' and #offers > 1 then
      if card.selectedOffer < 1 or card.selectedOffer > #offers then card.selectedOffer = 1 end
      for i, v in ipairs(offers) do
        offerSelect:addOption(tr('x%d', v.count or 1), i, true)
      end
      offerSelect:setCurrentIndex(card.selectedOffer, true)
      offerSelect.onOptionChange = function(widget, text, data)
        card.selectedOffer = tonumber(data) or 1
        selectedOffers[p.id] = card.selectedOffer
        updateCardOffer(card)
      end
      offerSelect:show()
    else
      offerSelect.onOptionChange = nil
      offerSelect:hide()
    end
  end

  updateCardOffer(card)
end

-- Count catalog products in a given tab (products default to 'general').
function tabCount(tab)
  local n = 0
  local all = (lastCatalog and lastCatalog.products) or {}
  for _, p in ipairs(all) do
    if (p.tab or 'general') == tab then n = n + 1 end
  end
  return n
end

function updateTabChecks()
  for key, btn in pairs(tabButtons) do
    btn:setChecked(key == currentTab)
  end
end

-- Refresh the sidebar labels with per-tab counts (e.g. "Mounts (52)").
function updateTabLabels()
  for _, t in ipairs(TABS) do
    local btn = tabButtons[t.key]
    if btn then btn:setText(string.format('%s (%d)', tr(t.label), tabCount(t.key))) end
  end
end

function selectTab(tab)
  if currentTab == tab then return end
  currentTab = tab
  updateTabChecks()
  renderProducts()
end

function renderProducts()
  if not productList then return end
  productList:destroyChildren()
  -- Only the products of the active tab.
  local products = {}
  for _, p in ipairs((lastCatalog and lastCatalog.products) or {}) do
    if (p.tab or 'general') == currentTab then products[#products + 1] = p end
  end
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
  updateTabLabels()
  renderProducts()
  updateRedeemButton()
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
  if yes and opts.confirmLabel then yes:setText(opts.confirmLabel) end
  if yes then yes.onClick = function() finish(true) end end
  if no then no.onClick = function() finish(false) end end
  confirmWindow.onEscape = function() finish(false) end

  confirmWindow:raise()
  confirmWindow:focus()
end

-- ============================================================================
-- details dialog (full outfit/mount description + bonuses)
-- ============================================================================
function closeDetails()
  if detailsWindow then detailsWindow:destroy() detailsWindow = nil end
end

-- Show the full product description (kept out of the compact card so it never clips).
function showDetails(p, offerIndex)
  if type(p) ~= 'table' then return end
  local idx = tonumber(offerIndex) or 1
  local cost, count = p.cost or 0, p.count or 1
  if type(p.offers) == 'table' and #p.offers > 0 then
    if idx < 1 or idx > #p.offers then idx = 1 end
    cost = p.offers[idx].cost or 0
    count = p.offers[idx].count or 1
  end
  closeDetails()
  detailsWindow = g_ui.createWidget('StreamerShopDetails', g_ui.getRootWidget())
  if not detailsWindow then return end
  detailsWindow:setText(p.name or tr('Details'))

  -- Big preview: same rule as the card (store PNG / creature / item).
  applyProductIcon(detailsWindow, 'detailItem', 'detailCreature', 'detailImage', p)

  local amountPrefix = (count and count > 1) and (count .. 'x ') or ''
  local dName = detailsWindow:recursiveGetChildById('detailName')
  if dName then dName:setText(amountPrefix .. (p.name or '')) end
  local dCost = detailsWindow:recursiveGetChildById('detailCost')
  if dCost then
    local currencyName = (lastCatalog and lastCatalog.currencyName) or tr('Streamer Coins')
    dCost:setText('$' .. comma_value(cost) .. ' ' .. currencyName)
  end
  local dDesc = detailsWindow:recursiveGetChildById('detailDesc')
  if dDesc then dDesc:setText(p.description or tr('No further details.')) end

  -- Buy straight from the dialog (goes through the normal confirm/skip flow, same offer selection).
  local dBuy = detailsWindow:recursiveGetChildById('detailBuy')
  if dBuy then
    if p.owned then
      dBuy:setText(tr('Owned'))
      dBuy:setEnabled(false)
      dBuy.onClick = nil
    else
      dBuy:setText(tr('Buy'))
      local balance = (lastCatalog and lastCatalog.balance) or 0
      dBuy:setEnabled(balance >= cost)
      dBuy.onClick = function() closeDetails() requestBuy(p, idx) end
    end
  end
  local dClose = detailsWindow:recursiveGetChildById('detailClose')
  if dClose then dClose.onClick = function() closeDetails() end end
  detailsWindow.onEscape = function() closeDetails() end

  detailsWindow:raise()
  detailsWindow:focus()
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
function requestBuy(p, offerIndex)
  if type(p) ~= 'table' or not p.id or buyPending then return end
  local idx = tonumber(offerIndex) or 1
  local cost, count = p.cost or 0, p.count or 1
  if type(p.offers) == 'table' and #p.offers > 0 then
    if idx < 1 or idx > #p.offers then idx = 1 end
    cost = p.offers[idx].cost or 0
    count = p.offers[idx].count or 1
  end
  local balance = (lastCatalog and lastCatalog.balance) or 0
  if cost > balance then return end
  local currencyName = (lastCatalog and lastCatalog.currencyName) or tr('Streamer Coins')
  local label = (count and count > 1) and (count .. 'x ' .. (p.name or p.id)) or (p.name or p.id)
  showConfirm({
    title = tr('Confirm Purchase'),
    message = tr('Buy %s for %s %s?', label, comma_value(cost), currencyName),
    skipKey = SKIP_BUY,
    onConfirm = function() doBuy(p.id, idx) end,
  })
end

function doBuy(id, offerIndex)
  if not id or buyPending then return end
  if not CommandBridge or not CommandBridge.request then return end

  buyPending = true
  if buyTimeout then removeEvent(buyTimeout) end
  buyTimeout = scheduleEvent(function()
    buyTimeout = nil
    buyPending = false
  end, 6000)

  CommandBridge.request('streamershop.buy', { id = id, offer = tonumber(offerIndex) or 1 }, function(response)
    buyPending = false
    if buyTimeout then removeEvent(buyTimeout) buyTimeout = nil end
    if type(response) ~= 'table' then return end
    if response.type == 'error' then
      displayErrorBox(tr('Streamer Shop'), response.message or tr('Purchase failed.'))
      return
    end
    -- Server returns the authoritative new balance; re-render so affordability updates.
    local data = response.data or response
    if type(data) == 'table' and lastCatalog then
      if data.balance ~= nil then lastCatalog.balance = data.balance end
      -- Grey the just-bought cosmetic right away (owned ~= nil marks it a one-time cosmetic;
      -- consumable General products have no `owned` field and stay buyable).
      for _, p in ipairs(lastCatalog.products or {}) do
        if p.id == id and p.owned ~= nil then p.owned = true break end
      end
      render()
    end
  end)
end

-- ============================================================================
-- one-time streamer package redeem (free Gold monthly pack)
-- ============================================================================
-- Reflect the server's authoritative packageRedeem block on the footer button: hidden for a viewer
-- with no wallet / no package, "Package Redeemed" (disabled) once claimed, otherwise a live
-- "Redeem Streamer Package" button. The server re-validates every redeem, so this is UX only.
function updateRedeemButton()
  if not redeemButton then return end
  local info = lastCatalog and lastCatalog.packageRedeem
  if type(info) ~= 'table' or (not info.available and not info.redeemed) then
    redeemButton:hide()
    return
  end
  redeemButton:show()
  if info.redeemed then
    redeemButton:setText(tr('Package Redeemed'))
    redeemButton:setEnabled(false)
    redeemButton:setTooltip(tr('You have already redeemed your streamer package.'))
    redeemButton.onClick = nil
  else
    redeemButton:setText(tr('Redeem Streamer Package'))
    redeemButton:setEnabled(true)
    redeemButton:setTooltip(tr('Redeem your one-time %s for free (once per account).', info.name or tr('streamer package')))
    redeemButton.onClick = function() requestRedeem() end
  end
end

-- Always confirm (this is a one-time action), then redeem.
function requestRedeem()
  local info = lastCatalog and lastCatalog.packageRedeem
  if type(info) ~= 'table' or not info.available or info.redeemed or redeemPending then return end
  showConfirm({
    title = tr('Redeem Streamer Package'),
    message = tr('Redeem your one-time streamer package (%s)? This can only be done once per account.', info.name or tr('Gold Pack')),
    confirmLabel = tr('Redeem'),
    onConfirm = function() doRedeem() end,
  })
end

function doRedeem()
  if redeemPending then return end
  if not CommandBridge or not CommandBridge.request then return end

  redeemPending = true
  if redeemTimeout then removeEvent(redeemTimeout) end
  redeemTimeout = scheduleEvent(function()
    redeemTimeout = nil
    redeemPending = false
  end, 8000)

  CommandBridge.request('streamershop.redeemPackage', {}, function(response)
    redeemPending = false
    if redeemTimeout then removeEvent(redeemTimeout) redeemTimeout = nil end
    if type(response) ~= 'table' then return end
    if response.type == 'error' then
      displayErrorBox(tr('Streamer Shop'), response.message or tr('Redeem failed.'))
      -- Re-pull authoritative state (e.g. another character on the account already redeemed it).
      requestState()
      return
    end
    -- Success: the button becomes "Package Redeemed" forever (server is the source of truth).
    if lastCatalog and lastCatalog.packageRedeem then
      lastCatalog.packageRedeem.redeemed = true
    end
    render()
    local data = response.data or response
    local msg = (type(data) == 'table' and data.message) or tr('Your streamer package was delivered to your Store Inbox!')
    if displayInfoBox then displayInfoBox(tr('Streamer Shop'), msg) end
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
  -- Build one sidebar button per category (data-driven from TABS); they stack via verticalBox.
  sidebar = window:recursiveGetChildById('sidebar')
  tabButtons = {}
  if sidebar then
    for _, t in ipairs(TABS) do
      local btn = g_ui.createWidget('StreamerShopTab', sidebar)
      btn:setText(t.label)
      btn.onClick = function() selectTab(t.key) end
      tabButtons[t.key] = btn
    end
  end
  redeemButton  = window:recursiveGetChildById('redeemPackageButton')
  if redeemButton then redeemButton.onClick = function() requestRedeem() end end
  updateTabChecks()
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
  closeDetails()
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
  if redeemTimeout then removeEvent(redeemTimeout) redeemTimeout = nil end
  closeConfirm()
  closeDetails()
  if window then window:destroy() window = nil end
end
