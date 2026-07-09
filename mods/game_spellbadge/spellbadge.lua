--[[
  game_spellbadge - Spell Badge window (collection + upgrade) over CommandBridge (opcode 211).

  A visual browser for the server-side spell badge system. Runs IN PARALLEL with the
  legacy paths (using a badge item -> upgrade modal, and the !spellbadge talkaction);
  all three read the same server KV, and every mutation pushes a fresh snapshot
  (spellbadge.update) so this window stays in sync no matter which path was used.

  SERVER-AUTHORITATIVE: this window renders the snapshot the server computes and asks
  the server to upgrade/discover. It never does game logic or trusts client numbers.

  This is the ONLY spell badge UI: it replaced the legacy badge-item upgrade modal and
  the !spellbadge talkaction. Badges are inert items, consumed only here.

  Protocol (CommandBridge, spellbadge.* actions - disjoint from casino.*/craft.*):
    client -> server  { action="spellbadge.state",    data={} }              -> <snapshot>
    client -> server  { action="spellbadge.upgrade",  data={ spell } }        -> <snapshot> | error
    client -> server  { action="spellbadge.discover", data={} }               -> { discovered, snapshot } | error
    server -> client  { event="spellbadge.open",   data=<snapshot> }   (push)
    server -> client  { event="spellbadge.update", data=<snapshot> }   (push)
]]

-- ============================================================================
-- state
-- ============================================================================
local spellBadgeWindow
local goldLabel, goldIcon, mysteriousLabel, mysteriousIcon, discoverButton
local badgeList, badgeStrip, statusLabel
local discoverFx, discoverFxItem
local confirmWindow
local lastSnapshot
local badgeRows = {}       -- row widgets parallel to lastSnapshot.badges, updated in place
local listSig              -- list-structure signature; a change forces a full rebuild
local openHandler, updateHandler
local stateTimeout, upgradeTimeout, discoverTimeout
local stateLoaded = false
local upgradePending = false
local discoverPending = false

-- The server rate-limits spellbadge.* to ~1 request / 250ms per player and SILENTLY DROPS
-- anything faster (see server spellbadge_otc_bridge.lua). A dropped request gets no reply,
-- so a pending flag would stay stuck until the watchdog (~6s) and the button felt frozen on
-- fast clicks. Space our own sends a little wider than the server window so every request we
-- send gets a reply; rapid clicks are coalesced instead of being eaten then locking the UI.
-- Shared across upgrade/discover/state because the server limit is global per player.
local ACTION_MIN_INTERVAL_MS = 400
local lastActionSentAt = 0

-- The list shows EVERY badge the vocation can use (no type filter); a header per kind
-- just labels the sections.
local KIND_TITLE = { attack = 'Attack Badges', heal = 'Heal Badges', support = 'Support Badges' }

-- Client-side "don't show this confirmation again" preferences (persisted via g_settings).
local SKIP_UPGRADE = 'spellbadge.skipUpgradeConfirm'
local SKIP_DISCOVER = 'spellbadge.skipDiscoverConfirm'

-- Compact charge count for the horizontal strip: full number up to 999, then
-- abbreviated with 'k' past 1000 (1500 -> "1k", 12000 -> "12k") so it never spills
-- into the neighbouring badge cell.
local function formatCharges(n)
  n = math.floor(tonumber(n) or 0)
  if n >= 1000000 then return math.floor(n / 1000000) .. 'kk' end
  if n >= 1000 then return math.floor(n / 1000) .. 'k' end
  return tostring(n)
end

-- ============================================================================
-- rendering
-- ============================================================================
function setEmpty(text)
  if badgeList then badgeList:destroyChildren() end
  badgeRows = {}; listSig = nil -- children were just wiped; force a full rebuild next render
  if statusLabel then
    statusLabel:setText(text or '')
    statusLabel:setVisible((text or '') ~= '')
  end
end

-- The horizontal "your badge charges" strip: every vocation badge, sprite + owned
-- count, dimmed when you own zero, name shown on sprite hover.
function renderStrip()
  if not badgeStrip then return end
  badgeStrip:destroyChildren()
  if not lastSnapshot or type(lastSnapshot.badges) ~= 'table' then return end
  for _, b in ipairs(lastSnapshot.badges) do
    local cell = g_ui.createWidget('SpellBadgeStripCell', badgeStrip)
    local sprite = cell:recursiveGetChildById('stripItem')
    if sprite then
      sprite:setItemId(b.id or 0)
      -- setItemId clears the item's tooltip, so set the name AFTER it.
      sprite:setTooltip(b.display or b.spell or '')
    end
    local cnt = cell:recursiveGetChildById('stripCount')
    if cnt then cnt:setText('x' .. formatCharges(b.charges)) end
    cell:setOpacity(((b.charges or 0) > 0) and 1.0 or 0.5)
  end
end

function fillRow(row, b)
  local item = row:recursiveGetChildById('item')
  if item then item:setItemId(b.id or 0) end

  local nameLabel = row:recursiveGetChildById('nameLabel')
  if nameLabel then nameLabel:setText(b.display or b.spell or '') end

  local bonusLabel = row:recursiveGetChildById('bonusLabel')
  if bonusLabel then bonusLabel:setText(string.format('Lv %d  %s', b.level or 0, b.bonusText or '')) end

  -- what each upgrade grants (per-level gain), e.g. "+1.0% damage per level"
  local perLevelLabel = row:recursiveGetChildById('perLevelLabel')
  if perLevelLabel then perLevelLabel:setText(b.perLevelText or '') end

  local start = b.awakenedStart or 10
  if start <= 0 then start = 10 end -- 0 is truthy in Lua; guard the `/ start` divide below
  local awakenedLabel = row:recursiveGetChildById('awakenedLabel')
  if awakenedLabel then
    if (b.level or 0) >= start then
      awakenedLabel:setText(string.format('Awakened %.1f%%', b.awakenedChance or 0))
    else
      awakenedLabel:setText(string.format('Awakened at Lv %d', start))
    end
  end

  -- info "i": explains awakened generally + what it does for THIS spell.
  local infoIcon = row:recursiveGetChildById('infoIcon')
  if infoIcon then
    local info = tr("Awakened: from level %d, each cast has a chance to awaken and DOUBLE this spell's effect for that cast. Higher levels raise the chance.", start)
    if b.footer and b.footer ~= '' then
      info = info .. '\n\n' .. b.footer
    end
    infoIcon:setTooltip(info)
  end

  -- progress bar: level toward the awakened unlock
  local bg = row:recursiveGetChildById('progressBg')
  local fill = row:recursiveGetChildById('progressFill')
  if bg and fill then
    local pct = math.min(b.level or 0, start) / start
    local inner = bg:getWidth() - 2
    fill:setWidth(math.max(0, math.floor(inner * pct)))
  end

  local costLabel = row:recursiveGetChildById('costLabel')
  if costLabel then costLabel:setText(tr('Cost: %s', b.costLabel or '?')) end

  local chargesLabel = row:recursiveGetChildById('chargesLabel')
  if chargesLabel then chargesLabel:setText(tr('Charges: %d', b.charges or 0)) end

  local btn = row:recursiveGetChildById('upgradeButton')
  if btn then
    btn:setEnabled(b.canAfford == true)
    if b.canAfford then
      btn:setTooltip(tr('Upgrade to level %d', b.nextLevel or ((b.level or 0) + 1)))
    elseif (b.charges or 0) < 1 then
      btn:setTooltip(tr('Requires 1 badge charge'))
    else
      btn:setTooltip(tr('Not enough gold (need %s)', b.costLabel or '?'))
    end
    btn.onClick = function() requestUpgrade(b) end
  end

  -- Tooltip lives ONLY on the info "i" (set above); the card itself is not clickable.
end

-- Lists EVERY badge the vocation can use, no type filter. Badges arrive sorted by
-- kind then name (server buildSnapshot), so a header per kind labels the sections.
function renderList()
  if not badgeList then return end
  if not lastSnapshot then return end -- keep the loading/empty message until data arrives

  local badges = type(lastSnapshot.badges) == 'table' and lastSnapshot.badges or {}

  -- The list always shows EVERY badge the vocation can use, so upgrading/discovering a badge
  -- changes only its VALUES, not the set of rows. In that case update the existing rows IN
  -- PLACE: rebuilding (destroyChildren) reset the ScrollablePanel to the top and threw away
  -- the player's scroll position on every upgrade. Only tear down + rebuild when the list
  -- STRUCTURE actually changes (first open, empty state, vocation switch).
  local parts = {}
  for i, b in ipairs(badges) do parts[i] = (b.kind or '') .. '/' .. tostring(b.spell or b.id or i) end
  local sig = #badges .. '|' .. table.concat(parts, ',')

  if sig == listSig and #badgeRows == #badges then
    for i, b in ipairs(badges) do
      local row = badgeRows[i]
      if row and not row:isDestroyed() then fillRow(row, b) end
    end
    return
  end

  badgeList:destroyChildren()
  badgeRows = {}
  local lastGroup
  for i, b in ipairs(badges) do
    if b.kind ~= lastGroup then
      lastGroup = b.kind
      local hdr = g_ui.createWidget('SpellBadgeGroupHeader', badgeList)
      hdr:setText(KIND_TITLE[b.kind] or b.kind)
    end
    local row = g_ui.createWidget('SpellBadgeRow', badgeList)
    fillRow(row, b)
    badgeRows[i] = row
  end
  listSig = sig

  if #badges == 0 then
    setEmpty(tr('No badges available for your vocation.'))
  elseif statusLabel then
    statusLabel:setVisible(false)
  end
end

function render()
  if not spellBadgeWindow or not lastSnapshot then return end
  local snap = lastSnapshot

  if goldLabel then goldLabel:setText(snap.goldLabel or tostring(snap.gold or 0)) end
  if goldIcon then goldIcon:setItemId(snap.goldIconId or 3031) end -- gold coin

  local m = snap.mysterious or {}
  if mysteriousIcon and m.id then mysteriousIcon:setItemId(m.id) end
  if mysteriousLabel then mysteriousLabel:setText('x' .. tostring(m.count or 0)) end
  if discoverButton then
    discoverButton:setEnabled(m.canAfford == true)
    if m.canAfford then
      discoverButton:setTooltip(tr('Reveal a random badge for %s gold', m.costLabel or '?'))
    else
      discoverButton:setTooltip(tr('Requires 1 mysterious badge and %s gold', m.costLabel or '?'))
    end
  end

  renderStrip()
  renderList()
end

function applySnapshot(snap)
  if type(snap) ~= 'table' then return end
  lastSnapshot = snap
  render()
end

-- ============================================================================
-- confirm dialog (reused by upgrade + discover) with "don't show again"
-- ============================================================================
function closeConfirm()
  if confirmWindow then confirmWindow:destroy() confirmWindow = nil end
end

-- otui @onEscape hook (bare so modules.game_spellbadge.cancelConfirm resolves).
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
  confirmWindow = g_ui.createWidget('SpellBadgeConfirm', g_ui.getRootWidget())
  if not confirmWindow then
    if opts.onConfirm then opts.onConfirm() end
    return
  end

  confirmWindow:setText(opts.title or tr('Confirm'))
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
  setEmpty(tr('Loading spell badges...'))
  if stateTimeout then removeEvent(stateTimeout) end
  stateTimeout = scheduleEvent(function()
    stateTimeout = nil
    if not stateLoaded then
      setEmpty(tr('Could not load spell badges. Reopen the window or relog.'))
    end
  end, 4000)

  lastActionSentAt = g_clock.millis() -- count state toward the shared spellbadge.* send spacing
  CommandBridge.request('spellbadge.state', {}, function(response)
    stateLoaded = true
    if stateTimeout then removeEvent(stateTimeout) stateTimeout = nil end
    if type(response) ~= 'table' then return end
    if response.type == 'error' then
      setEmpty(response.message or tr('Failed to load spell badges.'))
      return
    end
    applySnapshot(response.data or response)
  end)
end

-- Asks for confirmation (unless suppressed), then performs the upgrade.
function requestUpgrade(b)
  if type(b) ~= 'table' or not b.spell or upgradePending then return end
  if not b.canAfford then return end
  showConfirm({
    title = tr('Upgrade Spell Badge'),
    message = tr('Upgrade %s to level %d for %s gold?\nThis consumes 1 badge charge.',
      b.display or b.spell, b.nextLevel or ((b.level or 0) + 1), b.costLabel or '?'),
    skipKey = SKIP_UPGRADE,
    onConfirm = function() doUpgrade(b.spell) end,
  })
end

function doUpgrade(spell)
  if not spell or upgradePending then return end
  if not CommandBridge or not CommandBridge.request then return end
  local now = g_clock.millis()
  if now - lastActionSentAt < ACTION_MIN_INTERVAL_MS then return end -- coalesce; server drops <250ms
  lastActionSentAt = now

  upgradePending = true
  if upgradeTimeout then removeEvent(upgradeTimeout) end
  upgradeTimeout = scheduleEvent(function()
    upgradeTimeout = nil
    upgradePending = false
  end, 6000)

  CommandBridge.request('spellbadge.upgrade', { spell = spell }, function(response)
    upgradePending = false
    if upgradeTimeout then removeEvent(upgradeTimeout) upgradeTimeout = nil end
    if type(response) ~= 'table' then return end
    if response.type == 'error' then
      displayErrorBox(tr('Spell Badge'), response.message or tr('Upgrade failed.'))
      return
    end
    -- response.data is a fresh snapshot (the spellbadge.update push also arrives).
    applySnapshot(response.data or response)
  end)
end

-- Asks for confirmation (unless suppressed), then discovers a random badge.
function requestDiscover()
  local m = lastSnapshot and lastSnapshot.mysterious
  if not m or not m.canAfford or discoverPending then return end
  showConfirm({
    title = tr('Discover Spell Badge'),
    message = tr('Consume 1 mysterious badge and %s gold to reveal a random spell badge?', m.costLabel or '?'),
    skipKey = SKIP_DISCOVER,
    onConfirm = function() doDiscover() end,
  })
end

-- Floating "+1" with the obtained badge sprite, popped to the LEFT of the mysterious-badge
-- count on a successful Discover, then faded to transparent over 2s. Purely cosmetic
-- (phantom widgets); restarts cleanly if the player discovers again mid-fade.
function playDiscoverFx(itemId)
  if not discoverFx or not itemId or itemId == 0 then return end
  if discoverFxItem then discoverFxItem:setItemId(itemId) end
  g_effects.cancelFade(discoverFx)
  discoverFx:setOpacity(1)
  discoverFx:show()
  g_effects.fadeOut(discoverFx, 2000, 0, true)
end

function doDiscover()
  if discoverPending then return end
  if not CommandBridge or not CommandBridge.request then return end
  local now = g_clock.millis()
  if now - lastActionSentAt < ACTION_MIN_INTERVAL_MS then return end -- coalesce; server drops <250ms
  lastActionSentAt = now
  discoverPending = true
  -- CommandBridge has no timeout: a lost/errored reply would strand discoverPending=true
  -- and kill the Discover action until relog (mirrors the doUpgrade/requestState guards).
  if discoverTimeout then removeEvent(discoverTimeout) end
  discoverTimeout = scheduleEvent(function()
    discoverTimeout = nil
    discoverPending = false
  end, 6000)

  CommandBridge.request('spellbadge.discover', {}, function(response)
    discoverPending = false
    if discoverTimeout then removeEvent(discoverTimeout) discoverTimeout = nil end
    if type(response) ~= 'table' then return end
    if response.type == 'error' then
      displayErrorBox(tr('Discover Spell Badge'), response.message or tr('Discovery failed.'))
      return
    end
    local data = response.data or response
    if type(data) == 'table' then
      applySnapshot(data.snapshot or data)
      -- The reveal is announced by a green on-screen message from the server
      -- (MESSAGE_LOOK) plus this floating "+1" badge sprite, not a modal.
      if data.discovered and data.discovered.id then
        playDiscoverFx(data.discovered.id)
      end
    end
  end)
end

-- ============================================================================
-- window lifecycle
-- ============================================================================
function show()
  if not spellBadgeWindow then return end
  spellBadgeWindow:show()
  spellBadgeWindow:raise()
  spellBadgeWindow:focus()
end

function close()
  if not spellBadgeWindow then return end
  closeConfirm()
  spellBadgeWindow:hide()
end

function toggle()
  if not spellBadgeWindow then return end
  if spellBadgeWindow:isVisible() then
    close()
  else
    show()
    requestState()
  end
end

-- server push: force the window open (dev opener / future item-use migration)
function onOpenEvent(data)
  local snap = data and (data.data or data)
  show()
  if type(snap) == 'table' then applySnapshot(snap) end
end

-- server push: any mutation from any path (item modal, window, mysterious badge)
function onUpdateEvent(data)
  local snap = data and (data.data or data)
  if type(snap) == 'table' and spellBadgeWindow and spellBadgeWindow:isVisible() then
    applySnapshot(snap)
  end
end

-- ============================================================================
-- init / terminate
-- ============================================================================
function onGameStart()
  if CommandBridge and CommandBridge.on then
    openHandler = onOpenEvent
    updateHandler = onUpdateEvent
    CommandBridge.on('spellbadge.open', openHandler)
    CommandBridge.on('spellbadge.update', updateHandler)
  end
end

function onGameEnd()
  if CommandBridge and CommandBridge.off then
    if openHandler then CommandBridge.off('spellbadge.open', openHandler) openHandler = nil end
    if updateHandler then CommandBridge.off('spellbadge.update', updateHandler) updateHandler = nil end
  end
  close()
end

function init()
  if g_logger then g_logger.info('[spellbadge] client module loaded') end

  g_settings.setDefault(SKIP_UPGRADE, false)
  g_settings.setDefault(SKIP_DISCOVER, false)

  spellBadgeWindow = g_ui.displayUI('spellbadge')
  spellBadgeWindow:hide()

  goldLabel       = spellBadgeWindow:recursiveGetChildById('goldLabel')
  goldIcon        = spellBadgeWindow:recursiveGetChildById('goldIcon')
  mysteriousLabel = spellBadgeWindow:recursiveGetChildById('mysteriousLabel')
  mysteriousIcon  = spellBadgeWindow:recursiveGetChildById('mysteriousIcon')
  discoverButton  = spellBadgeWindow:recursiveGetChildById('discoverButton')
  badgeList       = spellBadgeWindow:recursiveGetChildById('badgeList')
  badgeStrip      = spellBadgeWindow:recursiveGetChildById('badgeStrip')
  statusLabel     = spellBadgeWindow:recursiveGetChildById('statusLabel')
  discoverFx      = spellBadgeWindow:recursiveGetChildById('discoverFx')
  discoverFxItem  = spellBadgeWindow:recursiveGetChildById('discoverFxItem')

  if statusLabel then statusLabel:setVisible(false) end
  if discoverFx then discoverFx:hide() end

  if discoverButton then discoverButton.onClick = function() requestDiscover() end end

  -- The window is opened from the game_sidebuttons "spellBadgeDialog" side button
  -- (registered there), which calls toggle()/close().

  connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  onGameEnd()

  if stateTimeout then removeEvent(stateTimeout) stateTimeout = nil end
  if upgradeTimeout then removeEvent(upgradeTimeout) upgradeTimeout = nil end
  closeConfirm()
  if spellBadgeWindow then spellBadgeWindow:destroy() spellBadgeWindow = nil end
end
