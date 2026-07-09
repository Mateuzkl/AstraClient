-- CaveBot Lure Extension
-- Handles lure mode and avoid trap functionality

CaveBot = CaveBot or {}
CaveBot.Extensions = CaveBot.Extensions or {}
CaveBot.Extensions.lure = {}

local lure = CaveBot.Extensions.lure

-- Detection range (server view range)
local CREATURE_DETECT_RANGE_X = 7
local CREATURE_DETECT_RANGE_Y = 5

-- State tracking for creature stop/walk hysteresis
-- When true, cavebot is stopped due to creatures and waiting for creaturesToWalk threshold
local isStoppedForCreatures = false
local bypassCreaturesToStopUntil = 0

-- Cache for trap detection
local trappedCache = {
    lastPos = nil,
    lastResult = false,
    lastObstacles = 0,
    lastTime = 0,
    cacheTimeout = 100  -- Cache valid for 100ms
}

-- Cache for tracking creatures outside lure area
-- Key: creature ID, Value: { x, y, z, firstSeen = timestamp }
-- stuckCreaturesCache: tracks position to detect stuck (not moving) creatures
-- lureWaitCache: tracks total time outside lure area regardless of movement
local stuckCreaturesCache = {}
local STUCK_TIMEOUT = 3000  -- 3 seconds: ignore if not moving at all
local lureWaitCache = {}
local LURE_AREA_TIMEOUT = 10000  -- 10 seconds: ignore if still outside lure area even if moving

-- Approach detection lives in CaveBot.Extensions.approach_tracker (shared
-- with stop-to-kill). Local alias kept short for readability.
local ApproachTracker = CaveBot.Extensions.approach_tracker

local SPECIAL_CACHE_TIMEOUT = 200
local specialPosCache = {
    keys = {},
    updatedAt = 0
}

local function copyPos(pos)
    if not pos then return nil end
    return {x = pos.x, y = pos.y, z = pos.z}
end

local function posKey(pos)
    if not pos then return nil end
    return string.format("%d,%d,%d", pos.x, pos.y, pos.z)
end

local function samePos(a, b)
    return a and b and a.x == b.x and a.y == b.y and a.z == b.z
end

local function parseActionPosition(value)
    if type(value) ~= "string" then return nil end
    local x, y, z = value:match("(%-?%d+)%s*,%s*(%-?%d+)%s*,%s*(%-?%d+)")
    if not x then return nil end
    return {x = tonumber(x), y = tonumber(y), z = tonumber(z)}
end

local function rebuildSpecialPosCache()
    local currentTime = g_clock.millis()
    if specialPosCache.updatedAt > 0 and (currentTime - specialPosCache.updatedAt) < SPECIAL_CACHE_TIMEOUT then
        return
    end

    local keys = {}

    local specialAreas = CaveBot.Config.get("specialAreas") or {}
    for _, area in ipairs(specialAreas) do
        local areaPos = area and area.position
        if areaPos and areaPos.x and areaPos.y and areaPos.z then
            keys[posKey(areaPos)] = true
        end
    end

    if CaveBot and CaveBot.getActions then
        for _, action in ipairs(CaveBot.getActions() or {}) do
            if action and action.action and action.action:lower() == "special" then
                local actionPos = parseActionPosition(action.value)
                if actionPos then
                    keys[posKey(actionPos)] = true
                end
            end
        end
    end

    specialPosCache.keys = keys
    specialPosCache.updatedAt = currentTime
end

local function isSpecialArea(pos)
    if not pos then return false end
    rebuildSpecialPosCache()
    return specialPosCache.keys[posKey(pos)] == true
end

-- Check if a tile has a floor change item. Delega ao canonico CaveBot.isFloorChangeTile
-- (verdade do item: teleport OU attr 252), sem tabela de ids nem cor de minimap.
-- Prevents avoid/lure from stepping on stairs, holes, teleporters etc.
local function hasFloorChangeItem(pos)
    if not pos then return false end
    if CaveBot.isFloorChangeTile then return CaveBot.isFloorChangeTile(pos) end
    return false
end

-- How many future waypoints to consider when filtering creatures that will be
-- naturally engaged as the cavebot progresses. Fixed window (not viewport-
-- gated) because the route often spans beyond the screen — we want to include
-- waypoints the bot will reach soon even if they're currently off-view.
-- Override via `CaveBot.Config.set("lureWaypointLookAhead", N)`.
local DEFAULT_WAYPOINT_LOOKAHEAD = 10

-- Chebyshev radius around each future waypoint. Cresatures within this range
-- of any considered waypoint are treated as "natural pickup" and don't gate
-- the cavebot into lure wait. Override via
-- `CaveBot.Config.set("lureWaypointRadius", N)`.
local DEFAULT_WAYPOINT_RADIUS = 7

-- Collect the next N future waypoints from the cavebot action list. Iterates
-- forward from the current index, wrapping once (cavebots loop). Skips
-- non-positional actions (hotkeys, delays, deposits, etc.) and keeps going
-- until `count` positions have been gathered or the list has been traversed
-- once without collecting that many.
local function getNextFutureWaypoints(count)
    count = count
        or (CaveBot.Config and CaveBot.Config.get("lureWaypointLookAhead"))
        or DEFAULT_WAYPOINT_LOOKAHEAD

    local positions = {}
    if not CaveBot or not CaveBot.getActions or not CaveBot.getCurrentIndex then
        return positions
    end
    local actions = CaveBot.getActions()
    if not actions or #actions == 0 then return positions end
    local total = #actions

    local i = CaveBot.getCurrentIndex() or 1
    for _ = 1, total do
        if #positions >= count then break end
        local action = actions[i]
        if action and action.value then
            local pos = parseActionPosition(action.value)
            if pos then positions[#positions + 1] = pos end
        end
        i = i + 1
        if i > total then i = 1 end
    end
    return positions
end

-- Back-compat shim: callers pre-dating the fixed-window design still receive
-- the same list the modern code uses.
local function getNextWaypointPositions(count)
    return getNextFutureWaypoints(count)
end

-- Is the creature close enough to ANY of the next future waypoints that the
-- cavebot will naturally walk past it? Chebyshev distance (matches Tibia's
-- 8-direction movement). Same floor required — a waypoint on a different Z
-- tells us nothing about creatures on the player's floor.
local function isCreatureInWaypointDirection(_playerPos, creaturePos, waypointPositions, radius)
    radius = radius
        or (CaveBot.Config and CaveBot.Config.get("lureWaypointRadius"))
        or DEFAULT_WAYPOINT_RADIUS
    if not creaturePos or not waypointPositions or #waypointPositions == 0 then
        return false
    end
    for _, wp in ipairs(waypointPositions) do
        if wp.z == creaturePos.z then
            local dx = math.abs(wp.x - creaturePos.x)
            local dy = math.abs(wp.y - creaturePos.y)
            if dx <= radius and dy <= radius then
                return true
            end
        end
    end
    return false
end

-- Exposed for consumers that need to classify creatures (e.g. lure debug HUD).
lure.getNextFutureWaypoints = getNextFutureWaypoints
lure.isCreatureInWaypointDirection = isCreatureInWaypointDirection
lure.getWaypointDefaults = function()
    return {
        lookAhead = DEFAULT_WAYPOINT_LOOKAHEAD,
        radius = DEFAULT_WAYPOINT_RADIUS,
    }
end

-- How many creatures are currently being waited on (have entered the wait
-- loop and haven't timed out). Counts entries in lureWaitCache whose
-- firstSeen is newer than LURE_AREA_TIMEOUT. Per-tick count seen by the HUD
-- and debug info.
lure.getWaitingCreatureCount = function()
    local now = g_clock.millis()
    local count = 0
    for _, firstSeen in pairs(lureWaitCache) do
        if now - firstSeen < LURE_AREA_TIMEOUT then
            count = count + 1
        end
    end
    return count
end

-- Full snapshot of waiting creatures and how long each has been waiting.
-- Useful for debug dumps or future HUD expansion.
lure.getWaitingCreatureInfo = function()
    local now = g_clock.millis()
    local out = {}
    for id, firstSeen in pairs(lureWaitCache) do
        local elapsed = now - firstSeen
        out[id] = {
            waitingForMs = elapsed,
            timedOut = elapsed >= LURE_AREA_TIMEOUT,
        }
    end
    return out
end

-- Get player
local function getPlayer()
    return g_game.getLocalPlayer()
end

-- Get player position
local function getPlayerPos()
    local player = getPlayer()
    return player and player:getPosition()
end

-- Check if in protection zone (same method as helper.lua)
local function isInProtectionZone()
    local player = getPlayer()
    if not player then return false end

    -- Use PlayerStates.Pz like the helper does (PlayerStates.Pz = 16384)
    local states = player:getStates()
    local inPz = bit.band(states, 16384) > 0
    
    return inPz
end

-- Debug PZ detection for player (call once to diagnose)
local playerPzDebugDone = false
local function debugPlayerPz()
    if playerPzDebugDone then return end

    local player = getPlayer()
    if not player then return end

    local lureDebug = CaveBot.Config.get("lureDebug") or false
    if not lureDebug then return end

    playerPzDebugDone = true

    local hasGetStates = player.getStates ~= nil
    local hasGetIcons = player.getIcons ~= nil
    local hasHasIcon = player.hasIcon ~= nil

    local statesResult = "N/A"
    if hasGetStates then
        local states = player:getStates()
        statesResult = tostring(states)
    end

    local iconsResult = "N/A"
    if hasGetIcons then
        local icons = player:getIcons()
        if icons then
            if type(icons) == "number" then
                iconsResult = "num:" .. tostring(icons)
            elseif type(icons) == "table" then
                iconsResult = "{"
                for k, v in pairs(icons) do
                    iconsResult = iconsResult .. tostring(k) .. "=" .. tostring(v) .. ","
                end
                iconsResult = iconsResult .. "}"
            else
                iconsResult = "type:" .. type(icons)
            end
        else
            iconsResult = "nil"
        end
    end

    local hasIconResult = "N/A"
    if hasHasIcon then
        hasIconResult = tostring(player:hasIcon(1))
    end

    print(string.format("[Lure PZ Debug] Player: states=%s | icons=%s | hasIcon(1)=%s",
        statesResult, iconsResult, hasIconResult))

    print("[Lure PZ Debug] isInProtectionZone() = " .. tostring(isInProtectionZone()))
end

-- Check if a specific tile is in protection zone
local function isTileInProtectionZone(pos)
    if not pos then return false end
    local tile = g_map.getTile(pos)
    if not tile then return false end

    -- Try isProtectionZone method first
    if tile.isProtectionZone then
        local isPz = tile:isProtectionZone()
        if isPz then return true end
    end

    -- Try hasFlag with common PZ flag values
    if tile.hasFlag then
        -- Try different possible PZ flags
        -- TileFlag_ProtectionZone = 0x01 (1)
        -- Some implementations use different values
        if tile:hasFlag(1) then return true end
        if tile:hasFlag(0x01) then return true end
    end

    -- Try getFlags and check for PZ bit
    if tile.getFlags then
        local flags = tile:getFlags()
        -- PZ is typically bit 0 (value 1)
        if flags then
            local band = bit32 and bit32.band or bit and bit.band
            if band and band(flags, 1) ~= 0 then
                return true
            end
            -- Fallback: direct comparison
            if flags % 2 == 1 then
                return true
            end
        end
    end

    return false
end

-- Debug flag for PZ (controls one-time debug output)
local pzDebugDone = false

-- Check if creature has line of sight to player
local function hasLineOfSight(playerPos, creaturePos)
    if not playerPos or not creaturePos then return false end
    if playerPos.z ~= creaturePos.z then return false end
    return g_map.isSightClear(playerPos, creaturePos)
end

-- Check if there is a path to creature position
local function hasPathTo(playerPos, creaturePos)
    if not playerPos or not creaturePos then return false end
    if playerPos.z ~= creaturePos.z then return false end
    -- Usar pathfinding JPS para verificar se há caminho
    -- Otc.PathFindIgnoreCreatures = 16 (para não considerar outras criaturas como bloqueio)
    local path, result = g_map.findPathJPS(playerPos, creaturePos, 100, 16)
    return (path and #path > 0) or false
end

-- Create ignore creature function from config
local function createIgnoreFunction()
    local ignoredList = CaveBot.Config.get("ignoredCreatures") or {}

    return function(creature)
        if not creature then return false end
        local name = creature:getName():lower()
        for _, ignored in ipairs(ignoredList) do
            if name == ignored:lower() then return true end
        end
        return false
    end
end

-- Check if a specific position is blocked (by creature, object, or not walkable)
local function isPositionBlocked(pos, shouldIgnore)
    if not pos then return true end

    local tile = g_map.getTile(pos)
    if not tile then return true end

    -- Respect special waypoints/areas: don't walk over them while avoiding.
    -- Exception: if player is already on this tile, allow evaluation to escape from it.
    local playerPos = getPlayerPos()
    if isSpecialArea(pos) and not samePos(pos, playerPos) then
        return true
    end

    -- Check if tile is walkable (considers static blocking objects)
    if not tile:isWalkable(false) then return true end

    -- Never step on floor change tiles (stairs, holes, teleporters)
    if hasFloorChangeItem(pos) then return true end

    -- Check for creatures
    local topCreature = tile:getTopCreature()
    if topCreature and not topCreature:isDead() then
        if topCreature:isMonster() then
            if shouldIgnore and shouldIgnore(topCreature) then
                return false  -- Ignored creature, not blocked
            end
            return true
        elseif topCreature:isPlayer() then
            local player = getPlayer()
            if player and topCreature ~= player then
                return true
            end
        elseif topCreature:isNpc() then
            return true
        end
    end

    return false
end

-- Count creatures around player
-- Usa função C++ SIMD se disponível, senão usa pathfinding Lua
-- Criaturas na direção dos próximos waypoints (±2 tiles) não são contadas para "wait"
lure.getCreatureCount = function(rangeX, rangeY, shouldIgnore, filterWaypointDirection)
    rangeX = rangeX or CREATURE_DETECT_RANGE_X
    rangeY = rangeY or CREATURE_DETECT_RANGE_Y
    
    -- Por padrão, filtra criaturas na direção dos waypoints
    if filterWaypointDirection == nil then
        filterWaypointDirection = true
    end

    if isInProtectionZone() then return 0 end

    local player = getPlayer()
    if not player then return 0 end

    local pos = getPlayerPos()
    if not pos then return 0 end

    -- Obter próximos waypoints para filtrar direção
    local nextWaypoints = nil
    if filterWaypointDirection then
        nextWaypoints = getNextWaypointPositions(3)
    end

    -- Obter lista de ignorados da config
    local ignoredList = CaveBot.Config.get("ignoredCreatures") or {}
    local hasIgnoreList = #ignoredList > 0
    
    -- Se há filtro de waypoint, não podemos usar C++ puro (precisa filtrar em Lua)
    -- Se não há lista de ignore e função C++ existe e não precisa filtrar waypoints, usar SIMD
    if not hasIgnoreList and not shouldIgnore and not filterWaypointDirection and g_map.countReachableMonstersInRange then
        local ok, result = pcall(function()
            -- PathFindIgnoreCreatures(16) | PathFindAllowNonPathable(4) = 20
            -- AllowNonPathable evita corpses no train invalidarem o path.
            return g_map.countReachableMonstersInRange(pos, rangeX, rangeY, 100, 20)
        end)
        if ok and result then
            return result
        end
    end

    -- Usar C++ para pegar lista de monstros alcançáveis, depois filtrar em Lua
    if g_map.getReachableMonstersInRange then
        local ok, monsters = pcall(function()
            return g_map.getReachableMonstersInRange(pos, rangeX, rangeY, 100, 20)
        end)
        
        if ok and monsters then
            shouldIgnore = shouldIgnore or createIgnoreFunction()
            local count = 0
            
            for _, monsterData in ipairs(monsters) do
                local creature = monsterData[1]
                local creaturePos = monsterData[2]
                
                if creature and not shouldIgnore(creature) then
                    -- Filtrar criaturas na direção dos waypoints
                    local inWaypointDir = false
                    if filterWaypointDirection and nextWaypoints and #nextWaypoints > 0 then
                        inWaypointDir = isCreatureInWaypointDirection(pos, creaturePos, nextWaypoints)
                    end
                    
                    if not inWaypointDir then
                        count = count + 1
                    end
                end
            end
            
            return count
        end
    end

    -- Fallback completo: usar verificação Lua com pathfinding
    shouldIgnore = shouldIgnore or createIgnoreFunction()

    local count = 0
    local spectators = g_map.getSpectators(pos, false)
    
    for _, creature in ipairs(spectators or {}) do
        if creature:isMonster() and not creature:isDead() then
            local cpos = creature:getPosition()
            if cpos and cpos.z == pos.z then
                local dx = math.abs(cpos.x - pos.x)
                local dy = math.abs(cpos.y - pos.y)
                if dx <= rangeX and dy <= rangeY then
                    if not shouldIgnore(creature) then
                        -- Verificar se criatura está fora do PZ
                        if not isTileInProtectionZone(cpos) then
                            -- Filtrar criaturas na direção dos waypoints
                            local inWaypointDir = false
                            if filterWaypointDirection and nextWaypoints and #nextWaypoints > 0 then
                                inWaypointDir = isCreatureInWaypointDirection(pos, cpos, nextWaypoints, 2)
                            end
                            
                            if not inWaypointDir then
                                -- Prefer the viewport matrix (monsters passable,
                                -- players/npcs/walls block). Falls back to JPS
                                -- when the target is outside the grid.
                                local reachable
                                if ScreenGrid and ScreenGrid.isReachable then
                                    reachable = ScreenGrid.isReachable(cpos, false)
                                end
                                if reachable == nil then
                                    -- 20 = IgnoreCreatures(16) | AllowNonPathable(4)
                                    local path = g_map.findPathJPS(pos, cpos, 100, 20)
                                    reachable = path and #path > 0 or false
                                end
                                if reachable then
                                    count = count + 1
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return count
end

-- Check if player is trapped (surrounded by creatures/obstacles)
-- Returns: trapped (bool), obstacleCount (number), freeTiles (table of free positions)
lure.isPlayerTrapped = function()
    if not CaveBot.Config.get("avoidTrap") then return false, 0, {} end

    local player = getPlayer()
    if not player then return false, 0, {} end

    local pos = getPlayerPos()
    if not pos then return false, 0, {} end

    -- Check cache (but don't cache free tiles for escape)
    local currentTime = g_clock.millis()
    if trappedCache.lastPos and
       trappedCache.lastPos.x == pos.x and
       trappedCache.lastPos.y == pos.y and
       trappedCache.lastPos.z == pos.z and
       (currentTime - trappedCache.lastTime) < trappedCache.cacheTimeout then
        -- Cache hit - but recalculate if trapped to get fresh free tiles
        if not trappedCache.lastResult then
            return trappedCache.lastResult, trappedCache.lastObstacles, {}
        end
    end

    local trapDistance = CaveBot.Config.get("trapDistance") or 1
    local creaturesToAvoid = CaveBot.Config.get("creaturesToAvoid") or 7
    local shouldIgnore = createIgnoreFunction()
    local nearbyObstacles = 0
    local freeTiles = {}

    for offsetX = -trapDistance, trapDistance do
        for offsetY = -trapDistance, trapDistance do
            if offsetX ~= 0 or offsetY ~= 0 then
                local checkPos = {x = pos.x + offsetX, y = pos.y + offsetY, z = pos.z}
                local isBlocked = isPositionBlocked(checkPos, shouldIgnore)

                if isBlocked then
                    nearbyObstacles = nearbyObstacles + 1
                else
                    -- This tile is free - potential escape route
                    table.insert(freeTiles, checkPos)
                end
            end
        end
    end

    local isTrapped = nearbyObstacles >= creaturesToAvoid

    -- Update cache
    trappedCache.lastPos = {x = pos.x, y = pos.y, z = pos.z}
    trappedCache.lastResult = isTrapped
    trappedCache.lastObstacles = nearbyObstacles
    trappedCache.lastTime = currentTime

    return isTrapped, nearbyObstacles, freeTiles
end

-- Reachable mobs on screen, WITHOUT the waypoint-corridor filter. The
-- stop/walk thresholds should count every mob the player actually has around
-- — the waypoint filter exists for `shouldWaitLure` (don't stall on mobs the
-- bot will engage on the route) and must not leak into these decisions, or
-- luring sucks in more and more mobs and `creaturesToStop` is never reached.
local function getStopDecisionCount(precomputedCount)
    if precomputedCount ~= nil then return precomputedCount end
    return lure.getCreatureCount(nil, nil, nil, false)
end

-- Check if lure mode should stop walking (waiting for creatures to follow)
lure.shouldWaitForCreatures = function()
    if not CaveBot.Config.get("lureMode") then return false end

    local creaturesToStop = CaveBot.Config.get("creaturesToStop") or 99
    local creatureCount = getStopDecisionCount()

    -- If we have enough creatures following, continue walking
    -- If creatures count dropped, wait for them to catch up
    return creatureCount < creaturesToStop
end

-- Check if cavebot should stop due to too many creatures
-- Uses hysteresis: stops at creaturesToStop, only resumes at creaturesToWalk
lure.shouldStopForCreatures = function(precomputedCount)
    -- stop_to_kill timeout bypass: ignore creature gate briefly so the bot can
    -- actually leave the WP after waiting the full stopToKillMaxWait.
    if bypassCreaturesToStopUntil > 0 then
        if g_clock.millis() < bypassCreaturesToStopUntil then
            isStoppedForCreatures = false
            return false
        end
        bypassCreaturesToStopUntil = 0
    end

    local creaturesToStop = CaveBot.Config.get("creaturesToStop") or 99
    local creaturesToWalk = CaveBot.Config.get("creaturesToWalk") or 99
    local creatureCount = getStopDecisionCount(precomputedCount)

    -- If we reached the stop threshold, enter stopped state
    if creatureCount >= creaturesToStop then
        isStoppedForCreatures = true
    end

    -- If we're in stopped state, check if we can resume
    if isStoppedForCreatures then
        -- Only resume when creatures drop to creaturesToWalk or below
        if creatureCount <= creaturesToWalk then
            -- Finish-kill HP gate: hold if there are still X weak mobs around
            if CaveBot.shouldHoldForFinishKill and CaveBot.shouldHoldForFinishKill() then
                return true
            end
            isStoppedForCreatures = false
            return false  -- Can walk now
        end
        return true  -- Still waiting for creatures to drop
    end

    return false  -- Not stopped, can walk
end

-- Check if cavebot should walk (creatures below threshold)
lure.shouldWalk = function()
    local creaturesToWalk = CaveBot.Config.get("creaturesToWalk") or 99
    local creatureCount = getStopDecisionCount()

    -- If in stopped state, only walk when below creaturesToWalk
    if isStoppedForCreatures then
        if creatureCount > creaturesToWalk then return false end
        if CaveBot.shouldHoldForFinishKill and CaveBot.shouldHoldForFinishKill() then return false end
        return true
    end

    if creatureCount > creaturesToWalk then return false end
    if CaveBot.shouldHoldForFinishKill and CaveBot.shouldHoldForFinishKill() then return false end
    return true
end

-- Check if cavebot is currently in stopped-for-creatures state
lure.isStoppedForCreatures = function()
    return isStoppedForCreatures
end

-- Reset the stopped state (call when cavebot is manually stopped/started)
lure.resetStoppedState = function()
    isStoppedForCreatures = false
    bypassCreaturesToStopUntil = 0
end

-- Arm a temporary bypass of the creaturesToStop gate. Used by stop_to_kill
-- when its maxWait timer fires so the bot can actually take steps to leave
-- the WP even with hostile mobs still on screen. Duration in ms.
lure.armCreaturesToStopBypass = function(durationMs)
    bypassCreaturesToStopUntil = g_clock.millis() + (durationMs or 3000)
    isStoppedForCreatures = false
end

-- Approach detection extracted to ApproachTracker (shared with stop-to-kill).
local isApproachingPlayer = ApproachTracker.isApproaching

-- Check if lure mode should wait for creatures to catch up
-- Used by wait_lure action and core loop
-- targetPos = optional destination position to check if creatures are ahead
lure.shouldWaitLure = function(targetPos)
    if not CaveBot.Config.get("lureMode") then return false end

    local player = getPlayer()
    if not player then return false end

    local playerPos = getPlayerPos()
    if not playerPos then return false end

    -- If player is in PZ, don't wait for any creatures
    if isInProtectionZone() then
        return false
    end

    local checkX = math.min(6, CaveBot.Config.get("lureCheckRangeX") or 6)
    local checkY = math.min(4, CaveBot.Config.get("lureCheckRangeY") or 4)
    local shouldIgnore = createIgnoreFunction()

    -- Check if ANY reachable monster is outside the lure area
    -- PRIORITY: If any reachable monster is outside, we must wait
    -- But skip creatures that have been stuck (not moving) for STUCK_TIMEOUT
    local hasMonsterOutsideLureArea = false
    local now = g_clock.millis()
    local activeCreatureIds = {}

    -- Same future-waypoint horizon used by getCreatureCount: a monster that
    -- the cavebot will naturally walk past shouldn't gate the wait loop
    -- either (keeps WAIT/ON_PATH labels truthful and avoids waiting for a
    -- mob that would be engaged on the next waypoints).
    local wpLookAhead = CaveBot.Config.get("lureWaypointLookAhead") or 10
    local wpRadius = CaveBot.Config.get("lureWaypointRadius") or 4
    local futureWaypoints = getNextFutureWaypoints(wpLookAhead)

    -- Detection window matches the viewport (what the player actually sees).
    -- Anything further than that isn't even visible and shouldn't gate lure.
    local viewportX, viewportY = 7, 5
    if ScreenGrid and ScreenGrid.getConfig then
        local cfg = ScreenGrid.getConfig()
        viewportX, viewportY = cfg.rangeX or viewportX, cfg.rangeY or viewportY
    end

    -- Native: pre-filtered list of alive non-summon monsters within the
    -- viewport, with position and chebyshev distance already extracted.
    -- Cuts ~5 Lua↔C++ method calls per spectator. The lure-specific filters
    -- (shouldIgnore, lureArea, futureWaypoints, reachability, approach,
    -- stuck/wait caches) stay in Lua because they read user-configurable
    -- state.
    local localPlayer = getPlayer()
    local localPlayerId = (localPlayer and localPlayer:getId()) or 0

    if g_map.collectMonstersForCache then
        local monsters, _names, packed =
            g_map.collectMonstersForCache(playerPos, viewportX, viewportY, localPlayerId)
        local n = monsters and #monsters or 0
        for i = 1, n do
            local creature = monsters[i]
            if creature and not shouldIgnore(creature) then
                local base = (i - 1) * 7
                local cposX = packed[base + 2]
                local cposY = packed[base + 3]
                local cposZ = packed[base + 4]
                local dx = math.abs(cposX - playerPos.x)
                local dy = math.abs(cposY - playerPos.y)
                local cpos = { x = cposX, y = cposY, z = cposZ }
                local onFuturePath = isCreatureInWaypointDirection(playerPos, cpos, futureWaypoints, wpRadius)
                if (dx > checkX or dy > checkY) and not onFuturePath then
                    local reachable
                    if ScreenGrid and ScreenGrid.isReachable then
                        reachable = ScreenGrid.isReachable(cpos, false)
                    end
                    if reachable == nil then
                        reachable = g_map.isSightClear(playerPos, cpos, true)
                    end
                    if reachable then
                        local creatureId = packed[base + 1]
                        if isApproachingPlayer(creature, cpos, playerPos, now) then
                            activeCreatureIds[creatureId] = true
                            if not lureWaitCache[creatureId] then
                                lureWaitCache[creatureId] = now
                            end
                            local waitingFor = now - lureWaitCache[creatureId]
                            if waitingFor < LURE_AREA_TIMEOUT then
                                local cached = stuckCreaturesCache[creatureId]
                                if not cached then
                                    stuckCreaturesCache[creatureId] = { x = cposX, y = cposY, z = cposZ, firstSeen = now }
                                    hasMonsterOutsideLureArea = true
                                else
                                    if cached.x ~= cposX or cached.y ~= cposY or cached.z ~= cposZ then
                                        stuckCreaturesCache[creatureId] = { x = cposX, y = cposY, z = cposZ, firstSeen = now }
                                        hasMonsterOutsideLureArea = true
                                    elseif (now - cached.firstSeen) < STUCK_TIMEOUT then
                                        hasMonsterOutsideLureArea = true
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    else
        -- Fallback for clients that predate the native binding.
        local spectators = g_map.getSpectators(playerPos, false)
        for _, creature in ipairs(spectators or {}) do
            if creature:isMonster() and not creature:isDead() and not shouldIgnore(creature) then
                local cpos = creature:getPosition()
                if cpos and cpos.z == playerPos.z then
                    local dx = math.abs(cpos.x - playerPos.x)
                    local dy = math.abs(cpos.y - playerPos.y)
                    if dx <= viewportX and dy <= viewportY then
                        local onFuturePath = isCreatureInWaypointDirection(playerPos, cpos, futureWaypoints, wpRadius)
                        if (dx > checkX or dy > checkY) and not onFuturePath then
                            local reachable
                            if ScreenGrid and ScreenGrid.isReachable then
                                reachable = ScreenGrid.isReachable(cpos, false)
                            end
                            if reachable == nil then
                                reachable = g_map.isSightClear(playerPos, cpos, true)
                            end
                            if reachable then
                                local creatureId = creature:getId()
                                if isApproachingPlayer(creature, cpos, playerPos, now) then
                                    activeCreatureIds[creatureId] = true
                                    if not lureWaitCache[creatureId] then
                                        lureWaitCache[creatureId] = now
                                    end
                                    local waitingFor = now - lureWaitCache[creatureId]
                                    if waitingFor < LURE_AREA_TIMEOUT then
                                        local cached = stuckCreaturesCache[creatureId]
                                        if not cached then
                                            stuckCreaturesCache[creatureId] = { x = cpos.x, y = cpos.y, z = cpos.z, firstSeen = now }
                                            hasMonsterOutsideLureArea = true
                                        else
                                            if cached.x ~= cpos.x or cached.y ~= cpos.y or cached.z ~= cpos.z then
                                                stuckCreaturesCache[creatureId] = { x = cpos.x, y = cpos.y, z = cpos.z, firstSeen = now }
                                                hasMonsterOutsideLureArea = true
                                            elseif (now - cached.firstSeen) < STUCK_TIMEOUT then
                                                hasMonsterOutsideLureArea = true
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- Clean up caches: remove creatures no longer outside lure area (entered or despawned)
    for id, _ in pairs(stuckCreaturesCache) do
        if not activeCreatureIds[id] then
            stuckCreaturesCache[id] = nil
        end
    end
    for id, _ in pairs(lureWaitCache) do
        if not activeCreatureIds[id] then
            lureWaitCache[id] = nil  -- Reset: creature entered lure area or gone
        end
    end
    -- Approach/stuck history is managed by ApproachTracker (time-based GC).
    ApproachTracker.cleanup(now, 8000)

    -- PRIORITY: If ANY reachable non-stuck monster is outside lure area, wait for it
    return hasMonsterOutsideLureArea
end

-- Returns true if this creature matches the exact criteria that make
-- `shouldWaitLure` include it in the wait decision right now. Used by the
-- debug HUD so the WAIT label is 1:1 with actual gating behavior. Doesn't
-- apply the stuck/timeout caches — those are "gave up waiting", not "would
-- wait". A mob that was timed out still deserves a WAIT label so the user
-- sees the classification, not an invisible gap.
lure.wouldWaitFor = function(playerPos, creaturePos)
    if not playerPos or not creaturePos then return false end
    if creaturePos.z ~= playerPos.z then return false end
    if not CaveBot or not CaveBot.Config then return false end
    if not CaveBot.Config.get("lureMode") then return false end
    if isInProtectionZone() then return false end

    local dx = math.abs(creaturePos.x - playerPos.x)
    local dy = math.abs(creaturePos.y - playerPos.y)

    -- Off-screen creatures are not considered (viewport cap)
    local viewportX, viewportY = 7, 5
    if ScreenGrid and ScreenGrid.getConfig then
        local cfg = ScreenGrid.getConfig()
        viewportX, viewportY = cfg.rangeX or viewportX, cfg.rangeY or viewportY
    end
    if dx > viewportX or dy > viewportY then return false end

    local checkX = math.min(6, CaveBot.Config.get("lureCheckRangeX") or 6)
    local checkY = math.min(4, CaveBot.Config.get("lureCheckRangeY") or 4)
    -- Inside the lure area: the cavebot fights through them, no waiting.
    if dx <= checkX and dy <= checkY then return false end

    -- On the future-waypoint corridor: the cavebot will walk past them.
    local wpLookAhead = CaveBot.Config.get("lureWaypointLookAhead") or DEFAULT_WAYPOINT_LOOKAHEAD
    local wpRadius = CaveBot.Config.get("lureWaypointRadius") or DEFAULT_WAYPOINT_RADIUS
    local futureWaypoints = getNextFutureWaypoints(wpLookAhead)
    if isCreatureInWaypointDirection(playerPos, creaturePos, futureWaypoints, wpRadius) then
        return false
    end

    -- Reachability: grid flood-fill is authoritative; off-grid falls back to
    -- sight (same contract as shouldWaitLure).
    local reachable
    if ScreenGrid and ScreenGrid.isReachable then
        reachable = ScreenGrid.isReachable(creaturePos, false)
    end
    if reachable == nil then
        reachable = g_map.isSightClear(playerPos, creaturePos, true)
    end
    if not reachable then return false end

    -- Approach gate (mirrors shouldWaitLure): the HUD should never say WAIT
    -- for a mob that the actual gate is ignoring. Resolve the Creature object
    -- via tile spectators so we can read direction + feed the same cache.
    local tile = g_map.getTile(creaturePos)
    local creatureOnTile = nil
    if tile then
        for _, c in ipairs(tile:getCreatures() or {}) do
            if c and c:isMonster() and not c:isDead() then
                creatureOnTile = c
                break
            end
        end
    end
    if creatureOnTile and not isApproachingPlayer(creatureOnTile, creaturePos, playerPos, g_clock.millis()) then
        return false
    end

    return true
end

-- Reset trap cache (call when position changes significantly)
lure.resetCache = function()
    trappedCache.lastPos = nil
    trappedCache.lastResult = false
    trappedCache.lastObstacles = 0
    trappedCache.lastTime = 0
    specialPosCache.keys = {}
    specialPosCache.updatedAt = 0
    -- Also clear stuck creatures and lure wait caches
    stuckCreaturesCache = {}
    lureWaitCache = {}
    ApproachTracker.reset()
    -- Reset stopped-for-creatures state
    isStoppedForCreatures = false
end

-- Get current lure status for display
lure.getStatus = function()
    return {
        lureModeActive = CaveBot.Config.get("lureMode") or false,
        avoidTrapActive = CaveBot.Config.get("avoidTrap") or false,
        creatureCount = getStopDecisionCount(),
        creaturesToStop = CaveBot.Config.get("creaturesToStop") or 99,
        creaturesToWalk = CaveBot.Config.get("creaturesToWalk") or 99,
        trapped = lure.isPlayerTrapped(),
        stoppedForCreatures = isStoppedForCreatures
    }
end

return lure
