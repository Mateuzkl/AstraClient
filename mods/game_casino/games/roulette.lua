--[[
  Roulette game for the casino window. Parameterized by currency so the SAME
  code backs both "roulette_coin" and "roulette_kkk" (Phase 2) - the two are just
  two registrations with different ids; all per-game data (currency, packages,
  prize pool, reel size) arrives from the server catalog via onCatalog.

  The draw is server-authoritative: play() asks the server, which rolls, persists
  and delivers the prize, then answers with the reel strip(s) to animate. This
  file only presents that result (Reel drives the sliding sprites).
]]

local RouletteGame = {}
RouletteGame.__index = RouletteGame

local DEFAULT_VISIBLE = 11
local DEFAULT_CELL    = 40

-- moldura.png geometry: transparent hole is ~67.2% of the image, image is 1500x1558
-- (slightly taller than wide). We size the payline frame so its hole matches the
-- cell (the decorated border then sits a bit larger around the sprite).
local MOLDURA_HOLE_RATIO = 0.672
local MOLDURA_ASPECT     = 1558 / 1500

-- ── construction / UI ───────────────────────────────────────────────────────

function RouletteGame:build(parent)
  local panel = g_ui.createWidget('Panel', parent)
  panel:addAnchor(AnchorTop, 'parent', AnchorTop)
  panel:addAnchor(AnchorBottom, 'parent', AnchorBottom)
  panel:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  panel:addAnchor(AnchorRight, 'parent', AnchorRight)
  self.uiPanel = panel

  -- milestone progress bar (spins -> mounts/outfit), at the very top
  local progWrap = g_ui.createWidget('Panel', panel)
  progWrap:setId('progressWrap')
  progWrap:addAnchor(AnchorTop, 'parent', AnchorTop)
  progWrap:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  progWrap:addAnchor(AnchorRight, 'parent', AnchorRight)
  progWrap:setMarginTop(4)
  progWrap:setHeight(64) -- caption + reward previews + track
  self.progressWrap = progWrap

  -- reel frame: the roulette "machine" that visually frames the running lane
  local frame = g_ui.createWidget('CasinoReelFrame', panel)
  frame:setId('reelFrame')
  frame:addAnchor(AnchorTop, 'progressWrap', AnchorBottom)
  frame:addAnchor(AnchorHorizontalCenter, 'parent', AnchorHorizontalCenter)
  frame:setMarginTop(10)
  self.reelFrame = frame

  -- reel host inside the frame; the Reel viewport is created here lazily. Anchored
  -- left + explicit equal margin (not HorizontalCenter, which was leaving all the
  -- padding on the right side -> asymmetric lane).
  local reelBox = g_ui.createWidget('UIWidget', frame)
  reelBox:setId('reelBox')
  reelBox:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  reelBox:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  reelBox:setPhantom(true)
  self.reelBox = reelBox

  -- balance (anchored to the reel FRAME, a sibling under panel -- not reelBox,
  -- which lives inside the frame and is not a sibling here)
  local balance = g_ui.createWidget('CasinoCenterLabel', panel)
  balance:setId('balanceLabel')
  balance:addAnchor(AnchorTop, 'reelFrame', AnchorBottom)
  balance:addAnchor(AnchorHorizontalCenter, 'parent', AnchorHorizontalCenter)
  balance:setMarginTop(14)
  self.balanceLabel = balance

  -- packages row (buttons built from the catalog, anchored left-to-right)
  local packages = g_ui.createWidget('Panel', panel)
  packages:setId('packagesPanel')
  packages:addAnchor(AnchorTop, 'balanceLabel', AnchorBottom)
  packages:addAnchor(AnchorHorizontalCenter, 'parent', AnchorHorizontalCenter)
  packages:setMarginTop(12)
  packages:setHeight(54)
  self.packagesPanel = packages

  -- status / result line
  local status = g_ui.createWidget('CasinoStatusLabel', panel)
  status:setId('statusLabel')
  status:addAnchor(AnchorTop, 'packagesPanel', AnchorBottom)
  status:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  status:addAnchor(AnchorRight, 'parent', AnchorRight)
  status:setMarginTop(12)
  self.statusLabel = status

  -- possible rewards: title + compact grid (filled from the catalog)
  local rewardsTitle = g_ui.createWidget('CasinoCenterLabel', panel)
  rewardsTitle:setId('rewardsTitle')
  rewardsTitle:setText(tr('Possible Rewards'))
  rewardsTitle:addAnchor(AnchorTop, 'statusLabel', AnchorBottom)
  rewardsTitle:addAnchor(AnchorHorizontalCenter, 'parent', AnchorHorizontalCenter)
  rewardsTitle:setMarginTop(10)

  local rewards = g_ui.createWidget('CasinoRewardsBox', panel) -- scrollable boxed grid
  rewards:setId('rewardsBox')
  rewards:addAnchor(AnchorTop, 'rewardsTitle', AnchorBottom)
  rewards:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  rewards:addAnchor(AnchorRight, 'parent', AnchorRight)
  rewards:addAnchor(AnchorBottom, 'parent', AnchorBottom)
  rewards:setMarginTop(6)
  self.rewardsList = rewards:recursiveGetChildById('list')

  self.spinning = false
  return panel
end

-- Fill the possible-rewards scrollable grid (sorted by chance desc by the server).
function RouletteGame:rebuildRewards()
  local list = self.rewardsList
  if not list then return end
  list:destroyChildren()
  for _, p in ipairs(self.prizes or {}) do
    local cell = g_ui.createWidget('CasinoRewardCell', list)
    if cell.item then
      cell.item:setItemId(p.id)
      local count = p.count or 1
      if count > 1 then
        cell.item:setItemCount(count)
        cell.item:setShowCountAlways(true)
      end
    end
    if cell.chance then
      cell.chance:setText(string.format("%.2f%%", p.chance or 0))
    end
    if p.name then cell:setTooltip(p.name) end
  end
end

-- Milestone progress bar: a gold fill up to spinCount over a track, a thin grey
-- stripe at each milestone, and the reward's mount/outfit sprite previewed just above
-- its stripe (dimmed until reached; reward name as the sprite's hover tooltip).
function RouletteGame:rebuildProgress()
  local wrap = self.progressWrap
  if not wrap then return end
  if self.progEvent then removeEvent(self.progEvent); self.progEvent = nil end
  wrap:destroyChildren()
  local prog = self.progress or {}
  local spinCount = prog.spinCount or 0
  local milestones = prog.milestones or {}
  if #milestones == 0 then return end
  local maxCount = tonumber(milestones[#milestones].count)
  if not maxCount or maxCount <= 0 then return end

  -- caption top-left; the track sits at the BOTTOM of the wrap with the reward
  -- previews stacked in the space above it.
  local caption = g_ui.createWidget('CasinoCheckpointLabel', wrap)
  caption:setText(string.format("Roulette progress: %d spins", spinCount))
  caption:addAnchor(AnchorTop, 'parent', AnchorTop)
  caption:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  caption:setMarginLeft(4)

  local trackPad = 20 -- track inset from the wrap edges (px)
  local track = g_ui.createWidget('CasinoProgressTrack', wrap)
  track:setId('progressTrack')
  track:addAnchor(AnchorBottom, 'parent', AnchorBottom)
  track:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  track:addAnchor(AnchorRight, 'parent', AnchorRight)
  track:setMarginLeft(trackPad)
  track:setMarginRight(trackPad)

  local fill = g_ui.createWidget('CasinoProgressFill', track)
  fill:addAnchor(AnchorTop, 'parent', AnchorTop)
  fill:addAnchor(AnchorBottom, 'parent', AnchorBottom)
  fill:addAnchor(AnchorLeft, 'parent', AnchorLeft)

  local cps = {}
  for _, m in ipairs(milestones) do
    -- grey stripe crossing the track at the milestone position
    local stripe = g_ui.createWidget('CasinoCheckpointStripe', track)
    stripe:addAnchor(AnchorTop, 'parent', AnchorTop)
    stripe:addAnchor(AnchorBottom, 'parent', AnchorBottom)
    stripe:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    -- reward preview (mount/outfit looktype) just above the stripe
    local prev = g_ui.createWidget('CasinoMilestonePreview', wrap)
    prev:addAnchor(AnchorBottom, 'progressTrack', AnchorTop)
    prev:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    prev:setMarginBottom(2)
    if m.look and m.look > 0 then
      prev:setOutfit({ type = m.look, addons = 3 })
      prev:setCenter(true)
    end
    local mcount = tonumber(m.count) or 0
    prev:setTooltip(string.format("%s  (%d spins)", m.label or "reward", mcount))
    cps[#cps + 1] = { stripe = stripe, preview = prev, count = mcount, pct = mcount / maxCount }
  end

  -- Keep refs so advanceProgress()/refreshProgress() can update the bar per spin
  -- without rebuilding the whole widget tree each time.
  self.progCaption = caption
  self.progTrack   = track
  self.progFill    = fill
  self.progMax     = maxCount
  self.progPad     = trackPad
  self.progCps     = cps

  -- Position stripes + previews by percent once the track has a real (post-layout)
  -- width, then paint the fill/dimming. Retry a few frames if layout hasn't settled
  -- yet (the panel was just built) so the bar never silently stays empty.
  local function layoutProgress(attempt)
    local ok, w = pcall(function() return track:getWidth() end)
    if not ok or type(w) ~= "number" or w <= 1 then
      if attempt < 8 then
        self.progEvent = scheduleEvent(function() layoutProgress(attempt + 1) end, 60)
      end
      return
    end
    for _, c in ipairs(cps) do
      local x = math.floor(c.pct * w)
      c.stripe:setMarginLeft(math.max(0, math.min(w - 3, x - 1)))
      -- preview is a child of the wrap, so add the track inset to align it over x
      c.preview:setMarginLeft(math.max(0, math.min(wrap:getWidth() - 32, trackPad + x - 16)))
    end
    self:refreshProgress()
  end
  layoutProgress(1)
end

-- Lightweight per-spin update: resize the gold fill and dim/undim the reward previews
-- for the current spinCount, without recreating widgets (rebuildProgress does the full
-- build). No-op until the track has been laid out.
function RouletteGame:refreshProgress()
  local prog = self.progress or {}
  local spinCount = prog.spinCount or 0
  if self.progCaption then
    self.progCaption:setText(string.format("Roulette progress: %d spins", spinCount))
  end
  local max = self.progMax
  if self.progFill and self.progTrack and max and max > 0 then
    local ok, w = pcall(function() return self.progTrack:getWidth() end)
    if ok and type(w) == "number" and w > 1 then
      self.progFill:setWidth(math.max(0, math.floor(w * math.min(1, spinCount / max))))
    end
  end
  for _, c in ipairs(self.progCps or {}) do
    if c.preview then c.preview:setOpacity(spinCount >= c.count and 1.0 or 0.35) end
  end
end

-- Advance the bar by `delta` spins locally. The server already counted every spin at
-- play time (authoritative + disconnect-proof); this only animates the bar up in step
-- with the reels. The real total re-syncs from the catalog on the next open.
function RouletteGame:advanceProgress(delta)
  if not self.progress or self.progress.spinCount == nil then return end
  self.progress.spinCount = self.progress.spinCount + (delta or 1)
  self:refreshProgress()
end

-- (Re)create the Reel + payline marker for a given size.
function RouletteGame:ensureReel(visible, cell)
  visible = visible or DEFAULT_VISIBLE
  cell = cell or DEFAULT_CELL
  if self.reel and self.reelVisible == visible and self.reelCell == cell then
    return
  end
  if self.reel then self.reel:destroy(); self.reel = nil end
  if self.marker then self.marker:destroy(); self.marker = nil end

  self.reelVisible = visible
  self.reelCell = cell

  -- The lane is EXACTLY `visible` cells wide (span), plus sidePad of grey on each
  -- side. reelBox is anchored left with an equal margin so both sides match; the
  -- frame is centered in the game area, keeping the whole lane symmetric.
  local span = visible * cell
  local framePad = 6 -- vertical grey padding
  local sidePad = 5  -- horizontal grey padding on each side
  self.reelFrame:setWidth(span + sidePad * 2)
  self.reelFrame:setHeight(cell + framePad * 2)
  self.reelBox:setWidth(span)
  self.reelBox:setHeight(cell)
  self.reelBox:setMarginLeft(sidePad)

  self.reel = Reel.new({
    parent = self.reelBox,
    orientation = "horizontal",
    visibleCells = visible,
    cellSize = cell,
  })

  -- payline frame (moldura) over the center cell, a bit larger than the cell so the
  -- decorated border overlaps the neighbours slightly (the roulette "window"). Nudged
  -- 3px left to sit visually centered.
  local centerCell = math.floor(visible / 2)
  local frameW = math.floor(cell * 1.3 + 0.5)
  local frameH = math.floor(frameW * MOLDURA_ASPECT + 0.5)
  local marker = g_ui.createWidget('CasinoPayline', self.reelBox)
  marker:setId('paylineMarker')
  marker:setWidth(frameW)
  marker:setHeight(frameH)
  marker:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  marker:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  marker:setMarginLeft(centerCell * cell + math.floor((cell - frameW) / 2 + 0.5) - 3)
  marker:raise()
  self.marker = marker
end

-- ── catalog / balance ───────────────────────────────────────────────────────

function RouletteGame:onCatalog(entry)
  entry = entry or {}
  self.currencyId = entry.currencyId or (self.currency and self.currency.id)
  self.currencyName = entry.currencyName or "coins"
  self.packages = entry.packages or {}
  self.balance = entry.balance or 0
  self.prizeSample = entry.sample
  self.prizes = entry.prizes or {}
  self.progress = entry.progress or {}
  self.locked = entry.locked and true or false -- casino frozen for an imminent server save

  self:ensureReel(entry.visibleCells, entry.cellSize)
  self.reel:setStatic(self.prizeSample or {})
  self:rebuildProgress()
  self:rebuildPackages()
  self:rebuildRewards()
  self:updateBalanceLabel()
  self:setStatus("", "#dfdfdf")
  self:updatePzState()
end

function RouletteGame:updateBalanceLabel()
  if not self.balanceLabel then return end
  self.balanceLabel:setText(string.format("%s: %d", self.currencyName or "Coins", self.balance or 0))
end

function RouletteGame:rebuildPackages()
  local panel = self.packagesPanel
  if not panel then return end
  panel:destroyChildren()
  self.packageButtons = {}
  local n = #self.packages
  local btnW, gap = 150, 10
  panel:setWidth(math.max(1, n * btnW + math.max(0, n - 1) * gap))
  local prevId
  for index, pkg in ipairs(self.packages) do
    local btn = g_ui.createWidget('CasinoSpinButton', panel)
    local bid = 'pkg_' .. index
    btn:setId(bid)
    btn:setWidth(btnW)
    btn:addAnchor(AnchorTop, 'parent', AnchorTop)
    if prevId then
      btn:addAnchor(AnchorLeft, prevId, AnchorRight)
      btn:setMarginLeft(gap)
    else
      btn:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    end
    local rolls = pkg.rolls or pkg.cost or 1
    local cost = pkg.cost or rolls
    local bonus = rolls - cost
    if self.currencyId and btn.coin then btn.coin:setItemId(self.currencyId) end
    if btn.label then
      local text = string.format("%dx Spin%s", cost, cost == 1 and "" or "s")
      if bonus > 0 then text = text .. string.format("\n(+%d bonus)", bonus) end
      btn.label:setText(text)
    end
    btn.onClick = function() self:play(index) end
    self.packageButtons[index] = btn
    prevId = bid
  end
end

-- ── play flow ───────────────────────────────────────────────────────────────

-- Enable a package button only when `enabled` (in PZ, not spinning, not locked) AND the
-- player can afford that package (has enough roulette coins for its cost), so a player
-- with no/too-few coins sees the spin buttons greyed out.
function RouletteGame:setPackagesEnabled(enabled)
  if not self.packageButtons then return end
  local balance = self.balance or 0
  for index, btn in ipairs(self.packageButtons) do
    local pkg = self.packages and self.packages[index]
    local affordable = pkg ~= nil and balance >= (pkg.cost or 1)
    btn:setEnabled(enabled and affordable or false)
  end
end

-- True if the player can afford at least the cheapest package.
function RouletteGame:canAffordAny()
  local balance = self.balance or 0
  for _, pkg in ipairs(self.packages or {}) do
    if balance >= (pkg.cost or 1) then return true end
  end
  return false
end

function RouletteGame:setStatus(text, color)
  if not self.statusLabel then return end
  self.statusLabel:setText(text or "")
  self.statusLabel:setColor(color or "#dfdfdf")
end

-- The window refuses to close while this is true (see Casino close guard), so once a
-- spin starts the player must let the reels finish.
function RouletteGame:isBusy()
  return self.spinning == true
end

-- Clear the spinning state: unlock the Close button and re-enable packages (via PZ).
function RouletteGame:endSpin()
  self.spinning = false
  Casino.lockClose(false)
  self:updatePzState()
end

function RouletteGame:play(index)
  if self.spinning then return end
  if self.locked then
    self:setStatus("The casino is closing for the server save. Try again later.", "#ffcc66")
    return
  end
  if not Casino.isInPz() then
    self:setStatus("You must be inside a Protection Zone to play.", "#ff6666")
    return
  end
  self.spinning = true
  self:setPackagesEnabled(false)
  Casino.lockClose(true) -- can't close the window until the reels stop
  self:setStatus("Spinning...", "#dfdfdf")
  -- Watchdog: CommandBridge.request has no timeout. If the casino.play reply is lost while
  -- still online, onResult/onError never fire and the window stays LOCKED open ("Spinning..."
  -- forever, close button + Esc both trapped). Release the trap if the house doesn't answer.
  if self.playWatchdog then removeEvent(self.playWatchdog) end
  self.playWatchdog = scheduleEvent(function()
    self.playWatchdog = nil
    if self.spinning then
      self:setStatus("The house didn't respond. Try again.", "#ff6666")
      self:endSpin()
    end
  end, 8000)
  Casino.requestPlay(self.id, index)
end

-- server answered casino.play: { plays = { {strip, stop, id, count, name, rare}, ... },
--                                balance, spinCount }
function RouletteGame:onResult(data)
  -- Server answered: stop the no-reply watchdog (the reel animation below may exceed it).
  if self.playWatchdog then removeEvent(self.playWatchdog); self.playWatchdog = nil end
  if type(data) ~= "table" then self:endSpin(); return end
  if data.balance ~= nil then self.balance = data.balance; self:updateBalanceLabel() end
  local plays = data.plays
  if type(plays) ~= "table" or #plays == 0 then
    self:endSpin()
    return
  end
  -- Multi-spin packages: shorten each spin so the whole batch stays snappy.
  self.spinDuration = math.max(700, math.floor(3600 / math.sqrt(#plays)))
  self:playSequence(plays, 1)
end

function RouletteGame:playSequence(plays, i)
  local play = plays[i]
  if not play then
    self:endSpin()
    return
  end
  self.reel:spin(play.strip, play.stop, { duration = self.spinDuration }, function()
    self:announcePrize(play)
    -- Collect THIS spin's prize now that its reel has stopped (the server rolled and
    -- already counted it on play, but withheld delivery until now).
    if play.uuid then Casino.claim(play.uuid) end
    -- Tick the progress bar one spin, in step with the reels. The authoritative total
    -- re-syncs from the catalog on the next open.
    self:advanceProgress(1)
    if i < #plays then
      self.seqEvent = scheduleEvent(function() self:playSequence(plays, i + 1) end, 400)
    else
      self:endSpin()
    end
  end)
end

function RouletteGame:announcePrize(play)
  local name = play.name or ("item " .. tostring(play.id))
  local count = play.count or 1
  local color = play.rare and "#ffd700" or "#6fce6f"
  self:setStatus(string.format("You won %dx %s!", count, name), color)
end

function RouletteGame:onError(msg)
  if self.playWatchdog then removeEvent(self.playWatchdog); self.playWatchdog = nil end
  self:setStatus(msg or "The house declined your bet.", "#ff6666")
  self:endSpin()
end

-- ── PZ gate ─────────────────────────────────────────────────────────────────

function RouletteGame:updatePzState()
  local inPz = Casino.isInPz()
  -- buttons enabled only in PZ, not mid-spin, and not while the casino is frozen for
  -- the server save.
  self:setPackagesEnabled(inPz and not self.spinning and not self.locked)
  if self.locked and not self.spinning then
    self:setStatus("The casino is closing for the server save. Try again later.", "#ffcc66")
  elseif not inPz and not self.spinning then
    self:setStatus("You must be inside a Protection Zone to play.", "#ffcc66")
  elseif not self.spinning and not self:canAffordAny() then
    self:setStatus(string.format("You don't have enough %s to spin.", self.currencyName or "roulette coins"), "#ffcc66")
  end
end

function RouletteGame:onPzChange(inPz)
  self:updatePzState()
end

-- ── lifecycle ───────────────────────────────────────────────────────────────

function RouletteGame:onShow()
  self:updatePzState()
end

function RouletteGame:onClosed()
  -- Called from Casino.close() AFTER window:destroy() already freed the widgets, so
  -- only stop the frame loop here (destroying the reel again would double-free it).
  if self.seqEvent then removeEvent(self.seqEvent); self.seqEvent = nil end
  if self.progEvent then removeEvent(self.progEvent); self.progEvent = nil end
  if self.playWatchdog then removeEvent(self.playWatchdog); self.playWatchdog = nil end
  if self.reel then self.reel:stop() end
  self.reel = nil
  self.reelVisible = nil
  self.reelCell = nil
  self.marker = nil
  self.spinning = false
end

-- ── registration (expansible: one call per currency) ────────────────────────

local function makeRouletteGame(cfg)
  return setmetatable({
    id = cfg.id,
    title = cfg.title,
    icon = cfg.icon,
    currency = cfg.currency,
    kind = "roulette",
  }, RouletteGame)
end

Casino.registerGame(makeRouletteGame({ id = "roulette_coin", title = tr("Roulette") }))
