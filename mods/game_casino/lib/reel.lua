--[[
  Reel - the casino window's sliding-sprite strip (the animation engine).

  Mirrors exactly how the server animates the roulette on the map SQMs today: an
  item is drawn as a creature via lookTypeEx -> here, a UICreature with outfit
  { type = 0, auxType = <itemId> } (luavaluecasts marks auxType>0 as an item
  sprite). But it runs entirely client-side and is VIRTUALIZED: only
  (visibleCells + 1) UICreature widgets ever exist and they NEVER move (no layout
  per frame). Each frame we only:
    * change a cell's outfit (item id) when it crosses into a new logical slot, and
    * set a shared sub-cell draw offset (setDrawOffset), derived from g_clock.millis().
  Sprite textures are cached by the engine after first use, so a spin costs a
  handful of setDrawOffset calls per frame with ZERO layout - the lightest path
  possible in pure Lua. Speed is time-based (read from the clock), so it stays
  constant even if a scheduler tick is late.

  Centering: we use the engine's CENTER path (setCenter + non-oldScaling). That
  scales the sprite by dest/(2*spriteSize) and centers ANY item (square or not) in
  its draw rect, so nothing drifts into a corner. To draw the sprite at
  `spriteFill` of the cell we set scale = 2*spriteFill (dest = cellSize*scale) and
  add a constant base draw offset that re-centers that oversized dest onto the cell.

  Public API:
    Reel.new{ parent, orientation = "horizontal"|"vertical", visibleCells, cellSize, spacing, spriteFill }
    reel:setStatic(items)                          -- show a still strip (idle)
    reel:spin(strip, stopIndex, opts, onFinish)    -- land stopIndex on the center cell
    reel:isSpinning() / reel:stop() / reel:destroy()

  strip     = array of item ids (the server's buildAnimationItems payload)
  stopIndex = 1-based index into strip that must land on the center (payline) cell
  opts      = { duration = ms, loops = extra full passes before landing }
]]

Reel = Reel or {}
Reel.__index = Reel

local FRAME_MS         = 16     -- ~60 fps scheduler tick
local DEFAULT_DURATION = 3600   -- one spin, full length (ms)
local DEFAULT_LOOPS    = 4      -- extra full strip passes before landing (spin feel)

-- DEBUG: draw a red border around each cell (green on the center/payline cell) so we
-- can see sprite-vs-cell and cell-vs-moldura alignment. Set false for production.
local DEBUG_CELL_BORDERS = false

local function easeOutCubic(t)
  local inv = 1 - t
  return 1 - inv * inv * inv
end

function Reel.new(opts)
  opts = opts or {}
  local self = setmetatable({}, Reel)

  self.horizontal = (opts.orientation ~= "vertical")
  self.visible    = math.max(1, opts.visibleCells or 11)
  self.cellSize   = opts.cellSize or 40
  self.spacing    = opts.spacing or 0
  self.stride     = self.cellSize + self.spacing
  -- animate each item's own phases over time (like items in a backpack / on a SQM)
  self.animate     = (opts.animate ~= false)
  self.centerCell  = math.floor(self.visible / 2)
  self.K           = self.visible + 1
  self.strip       = {}
  self.spinning    = false
  self.event       = nil

  -- viewport: clips the cells sliding past the window edges
  local vp = g_ui.createWidget('UIWidget', opts.parent)
  vp:setClipping(true)
  vp:setPhantom(true)
  vp:addAnchor(AnchorTop, 'parent', AnchorTop)
  vp:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  local span = self.visible * self.stride - self.spacing
  self.span = span -- reel length along the movement axis (exactly `visible` cells)
  if self.horizontal then
    vp:setWidth(span); vp:setHeight(self.cellSize)
  else
    vp:setWidth(self.cellSize); vp:setHeight(span)
  end
  self.viewport = vp

  -- K fixed cells in a row (or column); ids let each anchor to the previous one.
  self.cells = {}
  for i = 0, self.K - 1 do
    local c = g_ui.createWidget('CasinoReelCell', vp) -- UICreature + a card/slot box
    c:setId('reelcell_' .. i)
    c:setWidth(self.cellSize)
    c:setHeight(self.cellSize)
    c:setCenter(true)          -- engine centers any item in the cell; sprite = cellSize/2
    c:setAnimate(self.animate) -- cycle the item's animation phases (backpack-style)
    c:setPhantom(true)
    if DEBUG_CELL_BORDERS then
      c:setBorderWidth(1)
      c:setBorderColor((i == self.centerCell) and '#00ff00' or '#ff0000')
    end
    -- +1: AnchorRight/Bottom is the previous cell's LAST pixel (x+w-1), so without
    -- this adjacent cells overlap by 1px and N cells fall short of N*cellSize (the
    -- viewport width), leaving a gap on the far edge.
    if self.horizontal then
      c:addAnchor(AnchorTop, 'parent', AnchorTop)
      if i == 0 then
        c:addAnchor(AnchorLeft, 'parent', AnchorLeft)
      else
        c:addAnchor(AnchorLeft, 'reelcell_' .. (i - 1), AnchorRight)
        c:setMarginLeft(1 + self.spacing)
      end
    else
      c:addAnchor(AnchorLeft, 'parent', AnchorLeft)
      if i == 0 then
        c:addAnchor(AnchorTop, 'parent', AnchorTop)
      else
        c:addAnchor(AnchorTop, 'reelcell_' .. (i - 1), AnchorBottom)
        c:setMarginTop(1 + self.spacing)
      end
    end
    c.lastId = -1
    self.cells[i] = c
  end

  return self
end

-- Paint the K cells for a given scroll position (px). base = whole cells scrolled,
-- off = sub-cell slide. baseOffset keeps the (oversized) draw rect centered on the cell.
function Reel:render(scrollPx)
  local n = #self.strip
  if n == 0 then return end
  local base = math.floor(scrollPx / self.stride)
  local off  = math.floor((scrollPx - base * self.stride) + 0.5)
  for i = 0, self.K - 1 do
    local c = self.cells[i]
    -- where this cell's sprite is drawn along the movement axis (fixed cell pos +
    -- the shared slide). Hide any cell whose draw fully leaves the viewport, so the
    -- extra (slide) cell never shows past the edge when the reel is stopped.
    local pos = i * self.stride - off
    if pos + self.cellSize <= 0 or pos >= self.span then
      c:setVisible(false)
    else
      c:setVisible(true)
      local id = self.strip[((base + i) % n) + 1] or 0
      if type(id) ~= "number" or id < 0 then id = 0 end
      if c.lastId ~= id then
        c:setOutfit({ type = 0, auxType = id })
        c:setCenter(true) -- setOutfit builds a fresh outfit (center=false); re-apply
        c.lastId = id
      end
      if self.horizontal then
        c:setDrawOffset(-off, 0)
      else
        c:setDrawOffset(0, -off)
      end
    end
  end
end

-- Show a still strip (idle state), first item on the leftmost/top cell.
function Reel:setStatic(items)
  self:stop()
  self.strip = items or {}
  self:render(0)
end

function Reel:isSpinning()
  return self.spinning
end

function Reel:stop()
  if self.event then
    removeEvent(self.event)
    self.event = nil
  end
  self.spinning = false
end

-- Animate: spin fast, ease out, land so strip[stopIndex] rests on the center cell.
function Reel:spin(strip, stopIndex, opts, onFinish)
  self:stop()
  opts = opts or {}
  self.strip = strip or {}
  local n = #self.strip
  if n == 0 then
    if onFinish then pcall(onFinish) end
    return
  end

  local loops    = opts.loops or DEFAULT_LOOPS
  local duration = opts.duration or DEFAULT_DURATION
  if duration < 200 then duration = 200 end

  -- Land the (1-based) prize on the center cell with off == 0 (exact alignment).
  -- finalScroll is an exact multiple of stride so the strip stops cell-aligned.
  local stop0      = ((stopIndex or 1) - 1) % n
  local targetBase = loops * n + stop0 - self.centerCell
  if targetBase < 1 then targetBase = stop0 + n end -- guard tiny strips / negative
  local finalScroll = targetBase * self.stride

  local startMs = g_clock.millis()
  self.spinning = true

  local function frame()
    local t = (g_clock.millis() - startMs) / duration
    if t >= 1 then
      self:render(finalScroll) -- exact landing (off == 0, prize centered)
      self.spinning = false
      self.event = nil
      if onFinish then pcall(onFinish) end
      return
    end
    self:render(easeOutCubic(t) * finalScroll)
    self.event = scheduleEvent(frame, FRAME_MS)
  end
  frame()
end

function Reel:destroy()
  self:stop()
  if self.viewport then
    self.viewport:destroy()
    self.viewport = nil
  end
  self.cells = {}
  self.strip = {}
end
