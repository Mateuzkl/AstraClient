--[[
  Monthly Packages - client-side shop window over CommandBridge (extended opcode 211).

  The server (data-koliseu/scripts/custom/packages_otc_bridge.lua) owns the data and the
  transaction:
    - answers packages.list  -> { packages = { <package>, ... }, coins, coinsType }
    - answers packages.buy   -> { ok = true, tier, coins }  or  { type = "error", message }

  <package> = { tier, name, outfit?{lookType,addons,name}, mounts?[{lookType,name}],
                items[{id,count}], price, coinType }
  (the server resolves the outfit lookType to the viewing player's sex before sending.)

  This module only renders the catalog and relays the two requests. Coins are debited and
  items are delivered to the player's Store Inbox 100% server-side. No C++ rebuild. The
  cosmetic previews mirror the task-window card look (mods/game_tasks). Adapted from the
  mods/game_craft bridge-consumer pattern.
]]

packagesWindow = nil

local TIERS = { "bronze", "silver", "gold" }
local TIER_SLOT = { bronze = "slot1", silver = "slot2", gold = "slot3" }
-- Per-tier accent color used on the header label and (as a tint) on the rail frame.
local TIER_COLOR = { bronze = "#cd7f32", silver = "#c8c8c8", gold = "#ffd700" }

local OK_COLOR = "#7dd37d"
local ERR_COLOR = "#d37d7d"

local slotRefs = {}          -- tier -> { panel, title, cosmetics, items, buy }
local packagesByTier = {}    -- tier -> package data from the current catalog
local coinsBalance = 0
local coinsType = 1          -- 0 = normal, 1 = transferable (default)
local buyPending = false
local buyPendingEvent = nil
local listTimeoutEvent = nil
local catalogLoaded = false
local confirmBox = nil
local openHandler = nil

-- ============================================================================
-- helpers
-- ============================================================================

local function initCap(s)
  if type(s) ~= "string" or #s == 0 then return s or "" end
  return s:sub(1, 1):upper() .. s:sub(2)
end

local function formatCoins(n)
  n = tonumber(n) or 0
  if comma_value then
    local ok, res = pcall(comma_value, n)
    if ok and res then return res end
  end
  return tostring(n)
end

-- The coin icon is the real tradeable tibia coin item sprite (id 64212), not a UI png.
local COIN_ITEM_ID = 64212

local function setStatus(text, color)
  if not packagesWindow then return end
  local lbl = packagesWindow:recursiveGetChildById("statusLabel")
  if not lbl then return end
  lbl:setText(text or "")
  lbl:setColor(color or "$var-text-cip-color")
end

local function updateBalance()
  if not packagesWindow then return end
  local lbl = packagesWindow:recursiveGetChildById("balanceLabel")
  if lbl then lbl:setText(formatCoins(coinsBalance)) end
  local icon = packagesWindow:recursiveGetChildById("balanceIcon")
  if icon then icon:setItemId(COIN_ITEM_ID) end
end

-- Oversized (4x4) mount sprites anchor at their top-left tile, so a plain preview looks
-- clipped/"outside" the widget. Shift it by the mount's configured draw offset, falling
-- back to one tile for offset-less 4x4 mounts. Mirrors Offers.setupMountPreview.
local function setupMountPreview(widget, mountLookType)
  if not widget then return end
  if widget.setCenter then widget:setCenter(true) end
  if not widget.setDrawOffset then return end

  local thingType = g_things.getThingType(tonumber(mountLookType) or 0, ThingCategoryCreature)
  if thingType then
    local off = thingType.getDrawOffset and thingType:getDrawOffset()
    if off and ((off.x or 0) ~= 0 or (off.y or 0) ~= 0) then
      widget:setDrawOffset(off.x, off.y)
      return
    end
    if thingType:getWidth() == 4 and thingType:getHeight() == 4 then
      widget:setDrawOffset(32, 32)
      return
    end
  end
  widget:setDrawOffset(0, 0)
end

-- ============================================================================
-- rendering
-- ============================================================================

-- Build a package's exclusive cosmetics (outfit first, then each mount) and lay them out as
-- task-window-style cards inside the rail's cosmetics panel. The panel is sized so grid
-- `flow` centers the cards: 1 cosmetic -> one column, 2+ -> two columns.
function renderCosmetics(refs, pkg)
  local panel = refs.cosmetics
  if not panel then return end
  panel:destroyChildren()

  local list = {}
  if pkg.outfit and (tonumber(pkg.outfit.lookType) or 0) > 0 then
    list[#list + 1] = { kind = tr("OUTFIT"), name = pkg.outfit.name or tr("Outfit"), outfit = pkg.outfit }
  end
  for _, m in ipairs(pkg.mounts or {}) do
    if (tonumber(m.lookType) or 0) > 0 then
      list[#list + 1] = { kind = tr("MOUNT"), name = m.name or tr("Mount"), mount = m }
    end
  end

  for _, c in ipairs(list) do
    local card = g_ui.createWidget("CosmeticCard", panel)
    local kind = card:getChildById("kind")
    if kind then kind:setText(c.kind) end
    local nm = card:getChildById("name")
    if nm then nm:setText(c.name) end
    local creature = card:getChildById("creature")
    if creature then
      if c.outfit then
        creature:setDrawOffset(0, 0)
        pcall(function()
          creature:setOutfit({ type = c.outfit.lookType, addons = c.outfit.addons or 3 })
        end)
      elseif c.mount then
        pcall(function() creature:setOutfit({ type = c.mount.lookType }) end)
        setupMountPreview(creature, c.mount.lookType)
      end
    end
  end

  local n = #list
  local cols = (n >= 2) and 2 or 1
  local rows = math.max(1, math.ceil(math.max(n, 1) / cols))
  panel:setWidth(cols * 106 + (cols - 1) * 6)
  panel:setHeight(rows * 118 + (rows - 1) * 6)
end

function clearSlot(tier)
  local refs = slotRefs[tier]
  if not refs then return end
  refs.title:setText(initCap(tier) .. " " .. tr("Pack"))
  refs.title:setColor(TIER_COLOR[tier] or "#909090")
  if refs.cosmetics then refs.cosmetics:destroyChildren() end
  if refs.items then refs.items:destroyChildren() end
  if refs.buy then
    refs.buy:setEnabled(false)
    local price = refs.buy:getChildById("price")
    if price then price:setText("-") end
    refs.buy.onClick = nil
  end
end

function renderPackage(tier, pkg)
  local refs = slotRefs[tier]
  if not refs or type(pkg) ~= "table" then return end

  refs.title:setText(pkg.name or (initCap(tier) .. " Pack"))
  refs.title:setColor(TIER_COLOR[tier] or "#909090")

  renderCosmetics(refs, pkg)

  if refs.items then
    refs.items:destroyChildren()
    for _, it in ipairs(pkg.items or {}) do
      if it and it.id then
        local cell = g_ui.createWidget("PackageItemBox", refs.items)
        local ui = cell:getChildById("item")
        if ui then
          local count = tonumber(it.count) or 1
          ui:setItemId(it.id)
          ui:setItemCount(count)
          ui:setShowCount(true)
          -- Non-stackable items report count 1, so force the badge for a real amount.
          if count > 1 and ui.setShowCountAlways then ui:setShowCountAlways(true) end
        end
        local qty = tonumber(it.count) or 1
        cell:setTooltip(qty .. "x " .. (it.name or ("item " .. tostring(it.id))))
      end
    end
  end

  if refs.buy then
    local price = tonumber(pkg.price) or 0
    local priceLabel = refs.buy:getChildById("price")
    if priceLabel then
      priceLabel:setText(formatCoins(price))
      priceLabel:setColor((price > (coinsBalance or 0)) and ERR_COLOR or "$var-text-cip-color")
    end
    local icon = refs.buy:getChildById("coinIcon")
    if icon then icon:setItemId(COIN_ITEM_ID) end
    refs.buy:setEnabled(true)
    refs.buy.onClick = function() onBuyClick(tier) end
  end
end

-- ============================================================================
-- catalog + purchase (CommandBridge)
-- ============================================================================

function onCatalog(response)
  catalogLoaded = true
  if listTimeoutEvent then removeEvent(listTimeoutEvent) listTimeoutEvent = nil end
  if type(response) ~= "table" then return end
  if response.type == "error" then
    setStatus(response.message or tr("Failed to load packages."), ERR_COLOR)
    return
  end

  local data = response.data or response
  if type(data) ~= "table" then return end

  coinsBalance = tonumber(data.coins) or coinsBalance
  coinsType = tonumber(data.coinsType) or coinsType
  updateBalance()

  packagesByTier = {}
  for _, pkg in ipairs(data.packages or {}) do
    if type(pkg) == "table" and pkg.tier then
      packagesByTier[pkg.tier] = pkg
    end
  end

  for _, tier in ipairs(TIERS) do
    if packagesByTier[tier] then
      renderPackage(tier, packagesByTier[tier])
    else
      clearSlot(tier)
    end
  end
  setStatus("", "$var-text-cip-color")
end

function requestCatalog()
  if not g_game.isOnline() then return end
  if not CommandBridge or not CommandBridge.request then
    setStatus(tr("Command bridge unavailable. Please relog."), ERR_COLOR)
    return
  end
  catalogLoaded = false
  setStatus(tr("Loading packages..."), "$var-text-cip-color")
  if listTimeoutEvent then removeEvent(listTimeoutEvent) end
  -- If the server never answers (e.g. the bridge only attaches on login, so a first-load
  -- player must relog), don't leave the window silently blank -- tell them what to do.
  listTimeoutEvent = scheduleEvent(function()
    listTimeoutEvent = nil
    if not catalogLoaded then
      setStatus(tr("Could not load packages. Reopen the window or relog."), ERR_COLOR)
    end
  end, 4000)
  local ok = pcall(function() CommandBridge.request("packages.list", {}, onCatalog) end)
  if not ok then
    setStatus(tr("Failed to request packages."), ERR_COLOR)
  end
end

function doBuy(tier)
  if buyPending then return end
  if not CommandBridge or not CommandBridge.request then
    setStatus(tr("Command bridge unavailable. Please relog."), ERR_COLOR)
    return
  end

  buyPending = true
  setStatus(tr("Purchasing..."), "$var-text-cip-color")
  if buyPendingEvent then removeEvent(buyPendingEvent) end
  -- Safety: clear the lock AND the stale "Purchasing..." if no response ever arrives, so
  -- buying never gets stuck (e.g. a dropped request).
  buyPendingEvent = scheduleEvent(function()
    buyPending = false
    buyPendingEvent = nil
    setStatus(tr("Purchase timed out. Please try again."), ERR_COLOR)
  end, 8000)

  local ok = pcall(function()
    CommandBridge.request("packages.buy", { tier = tier }, onBuyResponse)
  end)
  if not ok then
    buyPending = false
    if buyPendingEvent then removeEvent(buyPendingEvent) buyPendingEvent = nil end
    setStatus(tr("Failed to send purchase."), ERR_COLOR)
  end
end

function onBuyClick(tier)
  if buyPending or confirmBox then return end
  local pkg = packagesByTier[tier]
  if not pkg then return end

  local msg = tr("Buy %s for %s tibia coins?\nItems are delivered to your Store Inbox.",
    pkg.name or initCap(tier), formatCoins(pkg.price or 0))

  -- displayGeneralBox saves the currently locked widget (this window) and restores the lock
  -- when the box is destroyed (uimessagebox onDestroy), so no manual lock juggling is needed.
  -- Buttons only fire their callback (no auto-close), so the callbacks destroy the box.
  local onYes = function()
    if confirmBox then confirmBox:destroy() confirmBox = nil end
    doBuy(tier)
  end
  local onNo = function()
    if confirmBox then confirmBox:destroy() confirmBox = nil end
  end
  confirmBox = displayGeneralBox(tr("Confirm Purchase"), msg,
    { { text = tr("Yes"), callback = onYes }, { text = tr("No"), callback = onNo } },
    onYes, onNo)
end

function onBuyResponse(response)
  buyPending = false
  if buyPendingEvent then removeEvent(buyPendingEvent) buyPendingEvent = nil end
  if type(response) ~= "table" then return end

  if response.type == "error" then
    local message = response.message or tr("Could not complete the purchase.")
    displayErrorBox(tr("Purchase Failed"), message)
    setStatus(message, ERR_COLOR)
    return
  end

  local data = response.data or response
  if type(data) == "table" and data.coins ~= nil then
    coinsBalance = tonumber(data.coins) or coinsBalance
    updateBalance()
  end
  setStatus(tr("Package delivered to your Store Inbox."), OK_COLOR)
  -- Refresh so balances / affordability colors reflect the new coin total.
  requestCatalog()
end

-- ============================================================================
-- window lifecycle
-- ============================================================================

function show()
  if not packagesWindow then return end
  packagesWindow:show(true)
  packagesWindow:raise()
  packagesWindow:focus()
  g_client.setInputLockWidget(packagesWindow)
  setStatus("", "$var-text-cip-color")
  requestCatalog()
end

function hide()
  if not packagesWindow then return end
  if confirmBox then confirmBox:destroy() confirmBox = nil end
  if listTimeoutEvent then removeEvent(listTimeoutEvent) listTimeoutEvent = nil end
  packagesWindow:hide()
  g_client.setInputLockWidget(nil)
end

function toggle()
  if not packagesWindow then return end
  if packagesWindow:isVisible() then
    hide()
  else
    show()
  end
end

-- Optional server push: open the window (which requests its own fresh catalog).
function onOpenEvent()
  show()
end

-- ============================================================================
-- init / terminate
-- ============================================================================

function onGameStart()
  if CommandBridge and CommandBridge.on then
    openHandler = onOpenEvent
    CommandBridge.on("packages.open", openHandler)
  end
end

function onGameEnd()
  if openHandler and CommandBridge and CommandBridge.off then
    CommandBridge.off("packages.open", openHandler)
    openHandler = nil
  end
  hide()
end

function init()
  packagesWindow = g_ui.displayUI("monthlypackages")
  packagesWindow:hide()

  -- Show the tradeable tibia coin sprite in the balance box from the start.
  local balanceIcon = packagesWindow:recursiveGetChildById("balanceIcon")
  if balanceIcon then balanceIcon:setItemId(COIN_ITEM_ID) end

  for _, tier in ipairs(TIERS) do
    local slot = packagesWindow:recursiveGetChildById(TIER_SLOT[tier])
    if slot then
      slotRefs[tier] = {
        panel = slot,
        title = slot:recursiveGetChildById("title"),
        cosmetics = slot:recursiveGetChildById("cosmetics"),
        items = slot:recursiveGetChildById("items"),
        buy = slot:recursiveGetChildById("buyButton"),
      }
      clearSlot(tier)
    end
  end

  connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })

  if openHandler and CommandBridge and CommandBridge.off then
    CommandBridge.off("packages.open", openHandler)
    openHandler = nil
  end
  if confirmBox then confirmBox:destroy() confirmBox = nil end
  if buyPendingEvent then removeEvent(buyPendingEvent) buyPendingEvent = nil end
  if listTimeoutEvent then removeEvent(listTimeoutEvent) listTimeoutEvent = nil end
  if packagesWindow then
    packagesWindow:destroy()
    packagesWindow = nil
  end
end
