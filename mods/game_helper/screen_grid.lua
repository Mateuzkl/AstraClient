-- Screen Walkability / Sight Matrix
--
-- Builds a matrix of the viewport around the player (default ±7x, ±5y) and
-- exposes:
--   - per-tile flag lookups (walkable, sight-block, creatures, PZ, floor change)
--   - flood-fill reachability from the player (two flavors: monsters passable,
--     monsters blocking)
--   - Bresenham line-of-sight using the sight-block flag
--   - A* pathfinding on the matrix with configurable straight/diagonal cost
--
-- Refresh cadence is controlled by `config.interval` (default 100ms). The
-- intent is a single build per tick shared by every consumer (CreatureCache,
-- cavebot lure, walking).

ScreenGrid = {}

-- =============================================================================
-- Config (runtime-tunable via ScreenGrid.configure)
-- =============================================================================

local config = {
    rangeX = 7,           -- ±7 tiles on X → 15 columns
    rangeY = 5,           -- ±5 tiles on Y → 11 rows
    interval = 100,       -- ms between automatic builds
    straightCost = 1,     -- A* cost for N/E/S/W
    diagonalCost = 3,     -- A* cost for diagonals (Tibia time-correct)
    pathMaxNodes = 400,   -- A* expansion cap (grid-wide exploration budget)
}

ScreenGrid.Flags = {
    BLOCKED_MAP   = 0x01, -- walls, unwalkable items, non-traversable tile
    BLOCKED_SIGHT = 0x02, -- has item with blockProjectile (unSight asset flag)
    HAS_MONSTER   = 0x04,
    HAS_PLAYER    = 0x08,
    HAS_NPC       = 0x10,
    IN_PZ         = 0x20,
    FLOOR_CHANGE  = 0x40,
    OUT_OF_GRID   = 0x80, -- tile outside cached viewport (or same-floor miss)
}

local F = ScreenGrid.Flags

-- =============================================================================
-- State
-- =============================================================================

-- Cells/reachable/reachableStrict are flat row-major arrays (Lua 1-based),
-- size = gridW() * gridH(). Index helper: `gy * w + gx + 1`. The C++ side
-- (Map::computeViewportReachability) returns them already in this layout;
-- the Lua-only fallback path mirrors it.
local state = {
    cells = nil,
    reachable = nil,
    reachableStrict = nil,
    lastBuildMs = 0,
    buildDurationMs = 0,
    playerPos = nil,        -- snapshot at last build
    dirty = true,
    timerEvent = nil,
    stats = {
        builds = 0,
        pathsRequested = 0,
        pathsFound = 0,
        pathsFailed = 0,
        lastBuildUs = 0,
    },
}

-- =============================================================================
-- Coordinate helpers
-- =============================================================================

local function gridW() return config.rangeX * 2 + 1 end
local function gridH() return config.rangeY * 2 + 1 end

-- Convert world pos → grid (gx, gy) 0-indexed; returns nil if outside or
-- on a different floor than the last-build player pos.
local function worldToGrid(pos)
    if not pos or not state.playerPos then return nil end
    if pos.z ~= state.playerPos.z then return nil end
    local gx = pos.x - state.playerPos.x + config.rangeX
    local gy = pos.y - state.playerPos.y + config.rangeY
    if gx < 0 or gx >= gridW() or gy < 0 or gy >= gridH() then
        return nil
    end
    return gx, gy
end

local function gridToWorld(gx, gy)
    local pp = state.playerPos
    if not pp then return nil end
    return {
        x = gx + pp.x - config.rangeX,
        y = gy + pp.y - config.rangeY,
        z = pp.z,
    }
end

-- =============================================================================
-- Build
-- =============================================================================

local THING_ATTR_FLOOR_CHANGE = 252

-- Compute flag byte for a single tile. `tile` may be nil (tile not seen).
local function computeTileFlags(tile, localPlayerId)
    if not tile then
        return F.BLOCKED_MAP  -- unseen tile = treat as impassable
    end

    local flags = 0

    -- Walkability check (ignores creatures — their contribution is tracked below)
    if tile.isWalkable and not tile:isWalkable(true) then
        flags = flags + F.BLOCKED_MAP
    end

    -- Protection zone
    if tile.isProtectionZone and tile:isProtectionZone() then
        flags = flags + F.IN_PZ
    end

    -- Scan items for blockProjectile (unSight) and floor-change attributes
    local sightBlocked = false
    local isFloorChange = false
    local ground = tile.getGround and tile:getGround()
    if ground and ground.blockProjectile and ground:blockProjectile() then
        sightBlocked = true
    end
    local items = tile.getItems and tile:getItems()
    if items then
        for _, item in ipairs(items) do
            if item then
                if not sightBlocked and item.blockProjectile and item:blockProjectile() then
                    sightBlocked = true
                end
                if not isFloorChange and item.getId and g_things and g_things.getThingType then
                    local itemType = g_things.getThingType(item:getId(), ThingCategoryItem)
                    if itemType then
                        if itemType.hasAttribute and itemType:hasAttribute(THING_ATTR_FLOOR_CHANGE) then
                            isFloorChange = true
                        elseif itemType.hasElevation and itemType:hasElevation() then
                            isFloorChange = true
                        end
                    end
                end
            end
        end
    end
    if sightBlocked then flags = flags + F.BLOCKED_SIGHT end
    if isFloorChange then flags = flags + F.FLOOR_CHANGE end

    -- Creature type (top creature only — tiles rarely stack in Tibia)
    local top = tile.getTopCreature and tile:getTopCreature()
    if top and not top:isDead() and top:getId() ~= localPlayerId then
        if top:isMonster() then
            flags = flags + F.HAS_MONSTER
        elseif top:isPlayer() then
            flags = flags + F.HAS_PLAYER
        elseif top:isNpc() then
            flags = flags + F.HAS_NPC
        end
    end

    return flags
end

-- Is a cell traversable? Monsters are passable by default (cavebot fights
-- through them); call with `strict=true` to block on monsters too. Players
-- inside a PZ do not block (they cannot PK the bot).
local function isCellWalkable(flags, strict)
    if flags >= F.OUT_OF_GRID then return false end
    if (flags % (F.BLOCKED_MAP * 2)) >= F.BLOCKED_MAP then return false end

    local hasPlayer = math.floor(flags / F.HAS_PLAYER) % 2 == 1
    local hasNpc    = math.floor(flags / F.HAS_NPC) % 2 == 1
    local hasMonster = math.floor(flags / F.HAS_MONSTER) % 2 == 1
    local inPz      = math.floor(flags / F.IN_PZ) % 2 == 1
    local isFloor   = math.floor(flags / F.FLOOR_CHANGE) % 2 == 1

    if hasPlayer and not inPz then return false end
    if hasNpc then return false end
    if isFloor then return false end
    if strict and hasMonster then return false end
    return true
end
ScreenGrid._isCellWalkable = isCellWalkable  -- exposed for tests

local NEIGHBORS_8 = {
    { dx = 0,  dy = -1, diag = false },
    { dx = 1,  dy = 0,  diag = false },
    { dx = 0,  dy = 1,  diag = false },
    { dx = -1, dy = 0,  diag = false },
    { dx = 1,  dy = -1, diag = true },
    { dx = 1,  dy = 1,  diag = true },
    { dx = -1, dy = 1,  diag = true },
    { dx = -1, dy = -1, diag = true },
}

-- BFS flood-fill from player cell over 8 directions, working on flat
-- row-major cell arrays (idx = gy * w + gx + 1, Lua 1-based). Diagonals
-- require BOTH adjacent straight cells to be walkable (anti-corner-cut).
-- Used as the Lua fallback when g_map.computeViewportReachability is not
-- available; otherwise the C++ native runs both passes in one call.
local function floodFillFlat(cells, startGx, startGy, strict)
    local w, h = gridW(), gridH()
    local total = w * h
    local reach = {}
    for i = 1, total do reach[i] = 0 end

    local startIdx = startGy * w + startGx + 1
    reach[startIdx] = 1
    local queue = { startIdx }
    local qi = 1
    while qi <= #queue do
        local idx = queue[qi]
        qi = qi + 1
        local cx = (idx - 1) % w
        local cy = math.floor((idx - 1) / w)
        for _, n in ipairs(NEIGHBORS_8) do
            local nx, ny = cx + n.dx, cy + n.dy
            if nx >= 0 and nx < w and ny >= 0 and ny < h then
                local nidx = ny * w + nx + 1
                if reach[nidx] == 0 and isCellWalkable(cells[nidx], strict) then
                    local ok = true
                    if n.diag then
                        local sideA = cells[cy * w + (cx + n.dx) + 1]
                        local sideB = cells[(cy + n.dy) * w + cx + 1]
                        if not isCellWalkable(sideA, strict) or not isCellWalkable(sideB, strict) then
                            ok = false
                        end
                    end
                    if ok then
                        reach[nidx] = 1
                        queue[#queue + 1] = nidx
                    end
                end
            end
        end
    end
    return reach
end

local function nowMs()
    return g_clock.millis()
end

function ScreenGrid.build(force)
    local now = nowMs()
    if not force and not state.dirty and (now - state.lastBuildMs) < config.interval then
        return false
    end
    local t0 = g_clock.micros and g_clock.micros() or 0

    local lp = g_game.getLocalPlayer()
    if not lp then
        state.cells, state.reachable, state.reachableStrict, state.playerPos = nil, nil, nil, nil
        state.dirty = true
        return false
    end
    local pp = lp:getPosition()
    if not pp then return false end

    state.playerPos = { x = pp.x, y = pp.y, z = pp.z }

    if g_map.computeViewportReachability then
        -- Native: per-tile flag computation + both flood-fills in one C++ call.
        -- ~2-3× faster than the Lua path (eliminates ~165 getTile + 330 BFS
        -- visits per build, all in C++ over already-resident tile data).
        local cells, reach, reachStrict = g_map.computeViewportReachability(pp, config.rangeX, config.rangeY)
        state.cells = cells
        state.reachable = reach
        state.reachableStrict = reachStrict
    else
        -- Fallback: per-tile compute in Lua + dual flood-fill (legacy path).
        local lpId = lp:getId()
        local w, h = gridW(), gridH()
        local total = w * h
        local cells = {}
        for i = 1, total do cells[i] = 0 end
        local baseX, baseY, z = pp.x - config.rangeX, pp.y - config.rangeY, pp.z
        local getTile = g_map.getTile
        for gy = 0, h - 1 do
            local wy = baseY + gy
            for gx = 0, w - 1 do
                local wx = baseX + gx
                local tile = getTile({ x = wx, y = wy, z = z })
                cells[gy * w + gx + 1] = computeTileFlags(tile, lpId)
            end
        end
        state.cells = cells
        state.reachable = floodFillFlat(cells, config.rangeX, config.rangeY, false)
        state.reachableStrict = floodFillFlat(cells, config.rangeX, config.rangeY, true)
    end

    state.lastBuildMs = now
    state.dirty = false
    state.stats.builds = state.stats.builds + 1
    if g_clock.micros then
        state.stats.lastBuildUs = g_clock.micros() - t0
    end
    state.buildDurationMs = nowMs() - now
    return true
end

-- =============================================================================
-- Public queries
-- =============================================================================

function ScreenGrid.configure(opts)
    if type(opts) ~= "table" then return end
    local structural = false
    if opts.rangeX and opts.rangeX ~= config.rangeX then
        config.rangeX = opts.rangeX; structural = true
    end
    if opts.rangeY and opts.rangeY ~= config.rangeY then
        config.rangeY = opts.rangeY; structural = true
    end
    if opts.interval then config.interval = opts.interval end
    if opts.straightCost then config.straightCost = opts.straightCost end
    if opts.diagonalCost then config.diagonalCost = opts.diagonalCost end
    if opts.pathMaxNodes then config.pathMaxNodes = opts.pathMaxNodes end
    if structural then ScreenGrid.invalidate() end
end

function ScreenGrid.getConfig()
    return { rangeX = config.rangeX, rangeY = config.rangeY, interval = config.interval,
             straightCost = config.straightCost, diagonalCost = config.diagonalCost,
             pathMaxNodes = config.pathMaxNodes }
end

function ScreenGrid.invalidate()
    state.dirty = true
end

function ScreenGrid.getFlags(pos)
    ScreenGrid.build(false)
    if not state.cells then return F.OUT_OF_GRID end
    local gx, gy = worldToGrid(pos)
    if not gx then return F.OUT_OF_GRID end
    return state.cells[gy * gridW() + gx + 1] or F.OUT_OF_GRID
end

function ScreenGrid.hasFlag(pos, flag)
    local f = ScreenGrid.getFlags(pos)
    return math.floor(f / flag) % 2 == 1
end

-- Returns true/false when the target is inside the cached viewport, or nil
-- when the grid hasn't been built or the target is outside the grid range.
-- Callers should treat nil as "I don't know" and fall back to a native
-- check (e.g. findPathJPS / isSightClear) rather than assuming unreachable.
function ScreenGrid.isReachable(pos, strict)
    ScreenGrid.build(false)
    if not state.cells then return nil end
    local gx, gy = worldToGrid(pos)
    if not gx then return nil end
    local reach = strict and state.reachableStrict or state.reachable
    if not reach then return nil end
    local v = reach[gy * gridW() + gx + 1]
    return v == true or v == 1
end

-- Bresenham line walk. Both positions must be inside the grid — otherwise
-- falls back to `g_map.isSightClear(from, to, true)` which handles long
-- distances natively.
function ScreenGrid.hasSight(fromPos, toPos)
    ScreenGrid.build(false)
    if not state.cells or not fromPos or not toPos then
        if fromPos and toPos then
            return g_map.isSightClear(fromPos, toPos, true)
        end
        return false
    end
    if fromPos.z ~= toPos.z then return false end
    local gx0, gy0 = worldToGrid(fromPos)
    local gx1, gy1 = worldToGrid(toPos)
    if not gx0 or not gx1 then
        return g_map.isSightClear(fromPos, toPos, true)
    end

    local dx = math.abs(gx1 - gx0)
    local dy = math.abs(gy1 - gy0)
    local sx = gx0 < gx1 and 1 or -1
    local sy = gy0 < gy1 and 1 or -1
    local err = dx - dy

    local w = gridW()
    local x, y = gx0, gy0
    while true do
        if not (x == gx0 and y == gy0) and not (x == gx1 and y == gy1) then
            local f = state.cells[y * w + x + 1]
            if f and math.floor(f / F.BLOCKED_SIGHT) % 2 == 1 then
                return false
            end
        end
        if x == gx1 and y == gy1 then break end
        local e2 = err * 2
        if e2 > -dy then err = err - dy; x = x + sx end
        if e2 < dx then err = err + dx; y = y + sy end
    end
    return true
end

-- =============================================================================
-- A* pathfinding on the matrix with configurable cost
-- =============================================================================

local DIR_FROM_DELTA = {
    [ 0]  = { [-1] = Directions.North,   [1] = Directions.South },
    [-1]  = { [ 0] = Directions.West,   [-1] = Directions.NorthWest, [1] = Directions.SouthWest },
    [ 1]  = { [ 0] = Directions.East,   [-1] = Directions.NorthEast, [1] = Directions.SouthEast },
}

local function deltaToDir(dx, dy)
    local row = DIR_FROM_DELTA[dx]
    return row and row[dy] or nil
end

-- Simple binary-heap priority queue
local function heapNew() return { n = 0 } end
local function heapPush(h, node)
    h.n = h.n + 1
    h[h.n] = node
    local i = h.n
    while i > 1 do
        local p = math.floor(i / 2)
        if h[p].f > h[i].f then h[p], h[i] = h[i], h[p]; i = p else break end
    end
end
local function heapPop(h)
    if h.n == 0 then return nil end
    local top = h[1]
    h[1] = h[h.n]
    h[h.n] = nil
    h.n = h.n - 1
    local i = 1
    while true do
        local l, r = i * 2, i * 2 + 1
        local s = i
        if l <= h.n and h[l].f < h[s].f then s = l end
        if r <= h.n and h[r].f < h[s].f then s = r end
        if s == i then break end
        h[s], h[i] = h[i], h[s]
        i = s
    end
    return top
end

-- A* heuristic. With cost 1 straight / 3 diagonal, the optimal path is pure
-- L-shape (Manhattan), so h = (dx + dy) * straightCost is admissible and tight.
local function heuristic(x, y, gx, gy)
    return (math.abs(gx - x) + math.abs(gy - y)) * config.straightCost
end

-- Find a path on the matrix from the player cell to `toPos`. Returns
-- (directions, result) where result is one of:
--   "ok"          → path found
--   "out_of_grid" → target outside viewport
--   "no_path"     → no reachable path under current walkability
--   "too_far"     → expansion budget exceeded
-- Directions are compatible with CavebotUtils.translatePosition.
function ScreenGrid.findPath(toPos, opts)
    opts = opts or {}
    ScreenGrid.build(false)
    state.stats.pathsRequested = state.stats.pathsRequested + 1
    if not state.cells then return nil, "not_built" end

    local gx1, gy1 = worldToGrid(toPos)
    if not gx1 then
        state.stats.pathsFailed = state.stats.pathsFailed + 1
        return nil, "out_of_grid"
    end
    local gx0, gy0 = config.rangeX, config.rangeY
    if gx0 == gx1 and gy0 == gy1 then return {}, "ok" end

    local w, h = gridW(), gridH()
    local cells = state.cells
    local strict = opts.strict == true
    if not isCellWalkable(cells[gy1 * w + gx1 + 1], strict) and not opts.allowGoalBlocked then
        state.stats.pathsFailed = state.stats.pathsFailed + 1
        return nil, "no_path"
    end

    local straightCost = config.straightCost
    local diagonalCost = config.diagonalCost
    local maxNodes = opts.maxNodes or config.pathMaxNodes

    if g_map.findViewportPath then
        -- Native: same A* + anti-corner-cut + lazy-delete priority queue, but
        -- without Lua heap allocations / table-per-node overhead. ~5-10× faster
        -- on long paths.
        local dirs, code = g_map.findViewportPath(
            cells, w, h, gx0, gy0, gx1, gy1,
            straightCost, diagonalCost, maxNodes,
            strict, opts.allowGoalBlocked == true)
        if code == 0 then
            state.stats.pathsFound = state.stats.pathsFound + 1
            return dirs, "ok"
        elseif code == 3 then
            state.stats.pathsFailed = state.stats.pathsFailed + 1
            return nil, "too_far"
        elseif code == 1 then
            state.stats.pathsFailed = state.stats.pathsFailed + 1
            return nil, "out_of_grid"
        else
            state.stats.pathsFailed = state.stats.pathsFailed + 1
            return nil, "no_path"
        end
    end

    local key = function(x, y) return y * w + x end
    local gScore = { [key(gx0, gy0)] = 0 }
    local parent = {}
    local open = heapNew()
    heapPush(open, { f = heuristic(gx0, gy0, gx1, gy1), g = 0, x = gx0, y = gy0 })

    local expanded = 0
    while open.n > 0 and expanded < maxNodes do
        local cur = heapPop(open)
        expanded = expanded + 1
        if cur.x == gx1 and cur.y == gy1 then
            -- Reconstruct
            local path = {}
            local cx, cy = gx1, gy1
            while cx ~= gx0 or cy ~= gy0 do
                local p = parent[key(cx, cy)]
                if not p then
                    state.stats.pathsFailed = state.stats.pathsFailed + 1
                    return nil, "no_path"
                end
                path[#path + 1] = deltaToDir(cx - p.x, cy - p.y)
                cx, cy = p.x, p.y
            end
            -- reverse in place
            for i = 1, math.floor(#path / 2) do
                path[i], path[#path - i + 1] = path[#path - i + 1], path[i]
            end
            state.stats.pathsFound = state.stats.pathsFound + 1
            return path, "ok"
        end

        local curKey = key(cur.x, cur.y)
        if gScore[curKey] == cur.g then
            for _, n in ipairs(NEIGHBORS_8) do
                local nx, ny = cur.x + n.dx, cur.y + n.dy
                if nx >= 0 and nx < w and ny >= 0 and ny < h
                   and isCellWalkable(cells[ny * w + nx + 1], strict) then
                    -- Anti-corner-cut for diagonals
                    local pass = true
                    if n.diag then
                        if not isCellWalkable(cells[cur.y * w + (cur.x + n.dx) + 1], strict)
                           or not isCellWalkable(cells[(cur.y + n.dy) * w + cur.x + 1], strict) then
                            pass = false
                        end
                    end
                    if pass then
                        local stepCost = n.diag and diagonalCost or straightCost
                        local tentative = cur.g + stepCost
                        local nKey = key(nx, ny)
                        if not gScore[nKey] or tentative < gScore[nKey] then
                            gScore[nKey] = tentative
                            parent[nKey] = { x = cur.x, y = cur.y }
                            heapPush(open, {
                                f = tentative + heuristic(nx, ny, gx1, gy1),
                                g = tentative, x = nx, y = ny,
                            })
                        end
                    end
                end
            end
        end
    end

    state.stats.pathsFailed = state.stats.pathsFailed + 1
    if expanded >= maxNodes then return nil, "too_far" end
    return nil, "no_path"
end

-- =============================================================================
-- Debug
-- =============================================================================

function ScreenGrid.getDebugInfo()
    return {
        cols = gridW(),
        rows = gridH(),
        interval = config.interval,
        straightCost = config.straightCost,
        diagonalCost = config.diagonalCost,
        lastBuildMs = state.lastBuildMs,
        buildDurationMs = state.buildDurationMs,
        builds = state.stats.builds,
        pathsRequested = state.stats.pathsRequested,
        pathsFound = state.stats.pathsFound,
        pathsFailed = state.stats.pathsFailed,
        lastBuildUs = state.stats.lastBuildUs,
        playerPos = state.playerPos,
        dirty = state.dirty,
    }
end

-- Human-readable ASCII dump of the grid for console inspection.
function ScreenGrid.dump()
    ScreenGrid.build(false)
    if not state.cells then return "(no grid)" end
    local w = gridW()
    local lines = {}
    for gy = 0, gridH() - 1 do
        local parts = {}
        for gx = 0, w - 1 do
            local f = state.cells[gy * w + gx + 1] or F.OUT_OF_GRID
            local c
            if gx == config.rangeX and gy == config.rangeY then
                c = "@"
            elseif math.floor(f / F.BLOCKED_MAP) % 2 == 1 then
                c = "#"
            elseif math.floor(f / F.HAS_PLAYER) % 2 == 1 then
                c = "P"
            elseif math.floor(f / F.HAS_NPC) % 2 == 1 then
                c = "N"
            elseif math.floor(f / F.HAS_MONSTER) % 2 == 1 then
                c = "m"
            elseif math.floor(f / F.FLOOR_CHANGE) % 2 == 1 then
                c = ">"
            elseif math.floor(f / F.BLOCKED_SIGHT) % 2 == 1 then
                c = "s"
            else
                c = "."
            end
            parts[#parts + 1] = c
        end
        lines[#lines + 1] = table.concat(parts)
    end
    return table.concat(lines, "\n")
end

-- =============================================================================
-- Lifecycle — fully lazy (build-on-query), mirrors CreatureCache. A single
-- g_game hook invalidates on logout so login into a different world doesn't
-- serve stale data.
-- =============================================================================

local hooked = false
local function ensureHooks()
    if hooked then return end
    hooked = true
    connect(g_game, {
        onGameEnd = function()
            state.cells, state.reachable, state.reachableStrict, state.playerPos = nil, nil, nil, nil
            state.dirty = true
        end,
    })
end
ensureHooks()

_G.ScreenGrid = ScreenGrid
return ScreenGrid
