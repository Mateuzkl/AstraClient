-- ApproachTracker
-- Heuristics shared by lure mode and stop-to-kill to decide whether a
-- monster is actively threatening the player. Two signals (OR):
--   A) facing direction roughly points to the player (instant)
--   B) Chebyshev distance to player decreased between two samples (robust)
-- Plus a stuck-position cache used by callers that want to time out mobs
-- that don't move at all.

CaveBot = CaveBot or {}
CaveBot.Extensions = CaveBot.Extensions or {}
CaveBot.Extensions.approach_tracker = {}

local ApproachTracker = CaveBot.Extensions.approach_tracker

local APPROACH_INTERVAL_MIN = 500
local APPROACH_INTERVAL_MAX = 5000
local APPROACH_INTERVAL_DEFAULT = 1500

-- Per-creature distance/time history: { x, y, z, dist, time }
local approachCache = {}
-- Per-creature first-seen position to detect stuck mobs.
local stuckCache = {}

local function getApproachInterval()
    local v = CaveBot and CaveBot.Config and CaveBot.Config.get("lureApproachInterval")
    v = tonumber(v) or APPROACH_INTERVAL_DEFAULT
    if v < APPROACH_INTERVAL_MIN then v = APPROACH_INTERVAL_MIN end
    if v > APPROACH_INTERVAL_MAX then v = APPROACH_INTERVAL_MAX end
    return v
end
ApproachTracker.getApproachInterval = getApproachInterval

-- True if `creatureDir` (Otc.Direction) roughly points toward the player.
-- dx, dy = playerPos - creaturePos. Tolerance is ±1 octant.
local function directionFacesPlayer(creatureDir, dx, dy)
    if creatureDir == nil then return false end
    if dx == 0 and dy == 0 then return true end

    local sx = (dx > 0) and 1 or (dx < 0 and -1 or 0)
    local sy = (dy > 0) and 1 or (dy < 0 and -1 or 0)

    local primary
    if sx == 0 and sy == -1 then primary = 0
    elseif sx == 1 and sy == 0 then primary = 1
    elseif sx == 0 and sy == 1 then primary = 2
    elseif sx == -1 and sy == 0 then primary = 3
    elseif sx == 1 and sy == -1 then primary = 4
    elseif sx == 1 and sy == 1 then primary = 5
    elseif sx == -1 and sy == 1 then primary = 6
    elseif sx == -1 and sy == -1 then primary = 7
    end
    if primary == nil then return false end

    local ring = { [0]=0, [4]=1, [1]=2, [5]=3, [2]=4, [6]=5, [3]=6, [7]=7 }
    local pIdx = ring[primary]
    local cIdx = ring[creatureDir]
    if pIdx == nil or cIdx == nil then return false end

    local diff = (cIdx - pIdx) % 8
    return diff == 0 or diff == 1 or diff == 7
end
ApproachTracker.directionFacesPlayer = directionFacesPlayer

-- True if a monster looks like it's approaching the player. When neither
-- signal is conclusive (first sample, no step info yet) returns true —
-- defensive: better wait than skip a real chaser.
function ApproachTracker.isApproaching(creature, creaturePos, playerPos, now)
    if not creature or not creaturePos or not playerPos then return true end

    local dx = playerPos.x - creaturePos.x
    local dy = playerPos.y - creaturePos.y
    local dist = math.max(math.abs(dx), math.abs(dy))

    local facing = false
    local ok, dir = pcall(function() return creature:getDirection() end)
    if ok and dir ~= nil then
        facing = directionFacesPlayer(dir, dx, dy)
    end

    local approachingByDelta = false
    local cid = creature:getId()
    local prev = approachCache[cid]
    local interval = getApproachInterval()
    if prev and (now - prev.time) >= interval then
        if dist < prev.dist then
            approachingByDelta = true
        end
        approachCache[cid] = { x = creaturePos.x, y = creaturePos.y, z = creaturePos.z, dist = dist, time = now }
    elseif not prev then
        approachCache[cid] = { x = creaturePos.x, y = creaturePos.y, z = creaturePos.z, dist = dist, time = now }
    end

    if facing or approachingByDelta then return true end

    if prev and (now - prev.time) >= interval then
        return false
    end
    return true
end

-- Returns 'fresh' | 'moved' | 'stuck' for the given creature this tick.
-- `timeout` (ms) = how long the creature must stay on the same tile to
-- be classified as 'stuck'. Caller decides what to do with each verdict.
function ApproachTracker.classifyStuck(creatureId, cpos, now, timeout)
    timeout = timeout or 3000
    local cached = stuckCache[creatureId]
    if not cached then
        stuckCache[creatureId] = { x = cpos.x, y = cpos.y, z = cpos.z, firstSeen = now }
        return 'fresh'
    end
    if cached.x ~= cpos.x or cached.y ~= cpos.y or cached.z ~= cpos.z then
        stuckCache[creatureId] = { x = cpos.x, y = cpos.y, z = cpos.z, firstSeen = now }
        return 'moved'
    end
    if (now - cached.firstSeen) >= timeout then
        return 'stuck'
    end
    return 'fresh'
end

-- Time-based GC. Drop entries whose last sample is older than `staleAfter`
-- ms. Time-based (not seen-set based) so multiple callers — lure, stop-to-
-- kill, debug HUD — don't wipe each other's history.
function ApproachTracker.cleanup(now, staleAfter)
    staleAfter = staleAfter or 8000
    local cutoff = now - staleAfter
    for id, entry in pairs(approachCache) do
        if entry.time < cutoff then approachCache[id] = nil end
    end
    for id, entry in pairs(stuckCache) do
        if entry.firstSeen < cutoff then stuckCache[id] = nil end
    end
end

-- Wipe everything — used when the feature is disabled or cavebot stops.
function ApproachTracker.reset()
    approachCache = {}
    stuckCache = {}
end

return ApproachTracker
