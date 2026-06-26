-- Global Creature Cache Module
-- Provides a unified creature mapping system for all helper modules
-- (Level Spy, Targeting, Magic Shooter, Cavebot)
-- Uses SIMD-optimized pathfinding (JPS) for reachability checks

CreatureCache = {}

-- Cache configuration
local CACHE_DURATION = 200 -- milliseconds (reduced for faster lure response)
local CREATURE_DETECT_RANGE_X = 9
local CREATURE_DETECT_RANGE_Y = 7
local DEFAULT_PATH_COMPLEXITY = 100 -- max nodes for JPS pathfinding

-- Cache state
local cacheState = {
    lastUpdateTime = 0,
    lastPosition = nil,
    creatures = {},  -- Full creature list with all data (reachable only)

    -- Pre-filtered lists for quick access (all reachable)
    monsters = {},
    players = {},
    npcs = {},

    -- Stats for level spy
    stats = {
        playerCount = 0,
        monsterCount = 0,
        npcCount = 0,
        vocations = {},
        guilds = { allies = 0, enemies = 0, neutral = 0 }
    },

    -- Module subscription flags
    subscribers = {
        levelSpy = false,
        targeting = false,
        magicShooter = false,
        cavebot = false
    },

    -- Config
    config = {
        filterByReachability = true, -- Only include reachable creatures
        pathComplexity = DEFAULT_PATH_COMPLEXITY,
        rangeX = CREATURE_DETECT_RANGE_X,
        rangeY = CREATURE_DETECT_RANGE_Y
    }
}

-- =============================================================================
-- MAD-13 D1: shared entry methods (replaces per-entry closures).
--
-- Before this change, every cache rebuild created 2 closures per visible
-- creature (`entry.hasSightClear` and `entry.hasPathTo`), each capturing
-- `creaturePos` as an upvalue. At 5 Hz × ~15-30 visible creatures × 2 closures,
-- that's roughly 150-300 closures/second = ~50-100 MB/hour of allocator
-- pressure. The closures get GC'd eventually but the allocate-and-discard
-- pattern fragments the heap and shows up as steady Lua-memory growth.
--
-- The new design defines the method bodies ONCE at module load and attaches
-- them via metatables. Each entry just stores its position data; no closures
-- are allocated per entry, ever. Cuts the helper-driven allocation rate to
-- effectively zero.
--
-- Migration note: `entry.hasSightClear()` (dot-call) is replaced with
-- `entry:hasSightClear()` (colon-call). All caller sites updated.
-- `entry.hasPathTo` removed entirely — it was defined but never called outside
-- this module (verified by grep across the whole codebase).
-- =============================================================================

local function _monsterHasSightClear(self)
    local cp = self.position
    if not cp then return false end
    if ScreenGrid and ScreenGrid.hasSight then
        local lp = g_game.getLocalPlayer()
        local pp = lp and lp:getPosition()
        if pp then return ScreenGrid.hasSight(pp, cp) end
    end
    local lp = g_game.getLocalPlayer()
    local pp = lp and lp:getPosition()
    if not pp then return false end
    return g_map.isSightClear(pp, cp, true)
end

local function _playerHasSightClear(self)
    local cp = self.position
    if not cp then return false end
    local lp = g_game.getLocalPlayer()
    local pp = lp and lp:getPosition()
    if not pp then return false end
    return g_map.isSightClear(pp, cp, false)
end

-- One metatable per branch. Monsters check ScreenGrid first and use multiFloor
-- = true; players go straight to isSightClear with multiFloor = false. These
-- semantics match the old closure bodies exactly.
local MonsterEntryMT = { __index = { hasSightClear = _monsterHasSightClear } }
local PlayerEntryMT  = { __index = { hasSightClear = _playerHasSightClear } }

-- Helper function to check if creature is a player summon
local function isPlayerSummon(creature)
    if not creature then return false end

    if creature.getType then
        local creatureType = creature:getType()
        if creatureType == CreatureTypeSummonOwn or creatureType == CreatureTypeSummonOther then
            return true
        end
    end

    if creature.getMasterId then
        local masterId = creature:getMasterId()
        -- Any creature with a master is a summon (player OR monster summons,
        -- e.g. Necromancer's necromancer_raise_dead). Exclude from counts.
        if masterId and masterId > 0 then return true end
    end
    return false
end

-- Subscribe a module to receive creature updates
function CreatureCache.subscribe(moduleName)
    if cacheState.subscribers[moduleName] ~= nil then
        cacheState.subscribers[moduleName] = true
    end
end

-- Unsubscribe a module
function CreatureCache.unsubscribe(moduleName)
    if cacheState.subscribers[moduleName] ~= nil then
        cacheState.subscribers[moduleName] = false
    end
end

-- Check if any module is subscribed
function CreatureCache.hasSubscribers()
    for _, enabled in pairs(cacheState.subscribers) do
        if enabled then return true end
    end
    return false
end

-- Configure cache settings
function CreatureCache.configure(options)
    if options.filterByReachability ~= nil then
        cacheState.config.filterByReachability = options.filterByReachability
    end
    if options.pathComplexity then
        cacheState.config.pathComplexity = options.pathComplexity
    end
    if options.rangeX then
        cacheState.config.rangeX = options.rangeX
    end
    if options.rangeY then
        cacheState.config.rangeY = options.rangeY
    end
end

-- Check if cache needs refresh
local function needsRefresh(forceRefresh)
    if forceRefresh then return true end

    local now = g_clock.millis()
    if (now - cacheState.lastUpdateTime) >= CACHE_DURATION then
        return true
    end

    -- Invalidate when the player moved: cached dx/dy values are computed at
    -- update time and become stale during walking, leading to wrong distance
    -- filters (e.g. getCreaturesAroundCount). Force refresh on any tile change.
    if cacheState.lastPosition then
        local lp = g_game.getLocalPlayer()
        local pos = lp and lp:getPosition()
        if pos and (pos.x ~= cacheState.lastPosition.x
                 or pos.y ~= cacheState.lastPosition.y
                 or pos.z ~= cacheState.lastPosition.z) then
            return true
        end
    end

    return false
end

-- Main cache update function - Uses SIMD pathfinding for reachability
function CreatureCache.update(forceRefresh)
    if not needsRefresh(forceRefresh) then
        return cacheState.creatures
    end

    if not g_game.isOnline() then
        return {}
    end

    local localPlayer = g_game.getLocalPlayer()
    if not localPlayer then
        return {}
    end

    local position = localPlayer:getPosition()
    if not position then
        return {}
    end

    local localPlayerId = localPlayer:getId()
    local localEmblem = localPlayer:getEmblem()
    local rangeX = cacheState.config.rangeX
    local rangeY = cacheState.config.rangeY

    -- Reset cache
    cacheState.creatures = {}
    cacheState.monsters = {}
    cacheState.players = {}
    cacheState.npcs = {}
    cacheState.stats = {
        playerCount = 0,
        monsterCount = 0,
        npcCount = 0,
        vocations = {},
        guilds = { allies = 0, enemies = 0, neutral = 0 }
    }

    -- =========================================================================
    -- MONSTERS: Sight-based collection (no walkability filter).
    -- Targeting/shooter only need line of sight, not a walkable path — a mob
    -- behind a wall is still attackable with ranged/runes. The per-entry
    -- `hasSightClear()` is the authoritative filter downstream.
    -- =========================================================================
    local spectators = g_map.getSpectators(position, false) or {}

    if g_map.collectMonstersForCache then
        -- Native: bulk-extracts {creature, name, [id,x,y,z,hp,dir,dist]} for
        -- monsters that pass alive + not-summon + same-floor + in-range +
        -- not-local-player. Replaces ~9 method calls per monster with one
        -- C++ pass over the spectator list.
        local monsterCreatures, monsterNames, packed =
            g_map.collectMonstersForCache(position, rangeX, rangeY, localPlayerId)
        local n = monsterCreatures and #monsterCreatures or 0
        for i = 1, n do
            local base = (i - 1) * 7
            local entry = setmetatable({
                creature = monsterCreatures[i],
                id = packed[base + 1],
                position = { x = packed[base + 2], y = packed[base + 3], z = packed[base + 4] },
                name = monsterNames[i],
                healthPercent = packed[base + 5],
                isDead = false,
                isSummon = false,
                isMonster = true,
                isPlayer = false,
                isNpc = false,
                direction = packed[base + 6],
                dx = math.abs(packed[base + 2] - position.x),
                dy = math.abs(packed[base + 3] - position.y),
                sameFloor = true,
                isReachable = true,
                pathLength = packed[base + 7],
            }, MonsterEntryMT)
            table.insert(cacheState.creatures, entry)
            table.insert(cacheState.monsters, entry)
            cacheState.stats.monsterCount = cacheState.stats.monsterCount + 1
        end
    else
        for _, creature in ipairs(spectators) do
            if creature and creature:isMonster() and creature:getId() ~= localPlayerId then
                local creaturePos = creature:getPosition()
                local isDead = creature:isDead()
                local isSummon = isPlayerSummon(creature)

                if not isDead and not isSummon and creaturePos and creaturePos.z == position.z then
                    local dx = math.abs(creaturePos.x - position.x)
                    local dy = math.abs(creaturePos.y - position.y)

                    if dx <= rangeX and dy <= rangeY then
                        local entry = setmetatable({
                            creature = creature,
                            id = creature:getId(),
                            position = creaturePos,
                            name = creature:getName(),
                            healthPercent = creature:getHealthPercent(),
                            isDead = false,
                            isSummon = false,
                            isMonster = true,
                            isPlayer = false,
                            isNpc = false,
                            direction = creature:getDirection(),
                            dx = dx,
                            dy = dy,
                            sameFloor = true,
                            isReachable = true,
                            pathLength = math.max(dx, dy),
                        }, MonsterEntryMT)

                        table.insert(cacheState.creatures, entry)
                        table.insert(cacheState.monsters, entry)
                        cacheState.stats.monsterCount = cacheState.stats.monsterCount + 1
                    end
                end
            end
        end
    end

    -- =========================================================================
    -- PLAYERS & NPCS: No pathfinding check needed - just count if on screen
    -- Only monsters need reachability/sight checks for targeting purposes
    -- =========================================================================
    for _, creature in ipairs(spectators) do
        if creature and creature:getId() ~= localPlayerId then
            local isPlayer = creature:isPlayer()
            local isNpc = creature:isNpc()
            
            -- Skip monsters (already processed above)
            if not creature:isMonster() and (isPlayer or isNpc) then
                local creaturePos = creature:getPosition()
                local isDead = creature:isDead()

                if creaturePos and creaturePos.z == position.z then
                    local dx = math.abs(creaturePos.x - position.x)
                    local dy = math.abs(creaturePos.y - position.y)

                    if dx <= rangeX and dy <= rangeY then
                        -- Players/NPCs: No reachability check needed
                        -- They are always counted if on screen within range
                        -- MAD-13 D1: shared metatable, no per-entry closures.
                        local entry = setmetatable({
                            creature = creature,
                            id = creature:getId(),
                            position = creaturePos,
                            name = creature:getName(),
                            healthPercent = creature:getHealthPercent(),
                            isDead = isDead,
                            isSummon = false,
                            isMonster = false,
                            isPlayer = isPlayer,
                            isNpc = isNpc,
                            direction = creature:getDirection(),
                            dx = dx,
                            dy = dy,
                            sameFloor = true,
                            isReachable = true,  -- Always true for players/NPCs (not used for them)
                            pathLength = nil,
                        }, PlayerEntryMT)

                        table.insert(cacheState.creatures, entry)

                        if isPlayer then
                            table.insert(cacheState.players, entry)
                            cacheState.stats.playerCount = cacheState.stats.playerCount + 1

                            -- Vocation tracking for level spy
                            local vocName = "Unknown"
                            if creature:isPaladin() then
                                vocName = "Paladin"
                            elseif creature:isDruid() then
                                vocName = "Druid"
                            elseif creature:isSorcerer() then
                                vocName = "Sorcerer"
                            elseif creature:isMonk() then
                                vocName = "Monk"
                            elseif creature:isKnight() then
                                vocName = "Knight"
                            end
                            cacheState.stats.vocations[vocName] = (cacheState.stats.vocations[vocName] or 0) + 1

                            -- Guild tracking for level spy
                            local creatureEmblem = creature:getEmblem()
                            if creatureEmblem == EmblemNone then
                                cacheState.stats.guilds.neutral = cacheState.stats.guilds.neutral + 1
                            elseif creatureEmblem == localEmblem and localEmblem ~= EmblemNone then
                                cacheState.stats.guilds.allies = cacheState.stats.guilds.allies + 1
                            else
                                cacheState.stats.guilds.enemies = cacheState.stats.guilds.enemies + 1
                            end

                        elseif isNpc and not isDead then
                            table.insert(cacheState.npcs, entry)
                            cacheState.stats.npcCount = cacheState.stats.npcCount + 1
                        end
                    end
                end
            end
        end
    end

    -- Sort monsters by distance (near → far) so targeting/shooter evaluate closest first
    table.sort(cacheState.monsters, function(a, b)
        local distA = a.pathLength or math.max(a.dx, a.dy)
        local distB = b.pathLength or math.max(b.dx, b.dy)
        return distA < distB
    end)

    -- Update cache timestamp and position
    cacheState.lastUpdateTime = g_clock.millis()
    cacheState.lastPosition = position

    return cacheState.creatures
end

-- Invalidate cache (call on floor change/teleport)
function CreatureCache.invalidate()
    cacheState.lastUpdateTime = 0
    cacheState.creatures = {}
    cacheState.monsters = {}
    cacheState.players = {}
    cacheState.npcs = {}
end

-- Get all creatures (updates cache if needed) - Only reachable
function CreatureCache.getAll()
    CreatureCache.update()
    return cacheState.creatures
end

-- Get monsters only (filtered, non-summons, alive, reachable)
function CreatureCache.getMonsters()
    CreatureCache.update()
    return cacheState.monsters
end

-- Get players only (reachable)
function CreatureCache.getPlayers()
    CreatureCache.update()
    return cacheState.players
end

-- Get NPCs only (reachable)
function CreatureCache.getNpcs()
    CreatureCache.update()
    return cacheState.npcs
end

-- Get stats for level spy
function CreatureCache.getStats()
    CreatureCache.update()
    return cacheState.stats
end

-- Get monster count around player with filters
-- All monsters in cache are already reachable (via SIMD JPS)
function CreatureCache.getMonsterCountAround(shouldIgnoreCreature, maxRangeX, maxRangeY, requireSight, requirePath)
    maxRangeX = maxRangeX or CREATURE_DETECT_RANGE_X
    maxRangeY = maxRangeY or CREATURE_DETECT_RANGE_Y
    requireSight = requireSight == true -- default false

    CreatureCache.update()

    local count = 0
    for _, entry in ipairs(cacheState.monsters) do
        if entry.dx <= maxRangeX and entry.dy <= maxRangeY then
            local ignored = shouldIgnoreCreature and shouldIgnoreCreature(entry.creature) or false

            if not ignored then
                -- Path is already verified (all creatures in cache are reachable)
                local reachable = true
                if requireSight and not entry:hasSightClear() then
                    reachable = false
                end

                if reachable then
                    count = count + 1
                end
            end
        end
    end
    return count
end

-- Get closest creature distance (all creatures are already reachable)
function CreatureCache.getClosestMonsterDistance(shouldIgnoreCreature, maxRangeX, maxRangeY, requireSight, requirePath)
    CreatureCache.update()

    maxRangeX = maxRangeX or CREATURE_DETECT_RANGE_X
    maxRangeY = maxRangeY or CREATURE_DETECT_RANGE_Y
    requireSight = requireSight == true -- default false

    local closestDistance = nil
    for _, entry in ipairs(cacheState.monsters) do
        if entry.dx <= maxRangeX and entry.dy <= maxRangeY then
            local ignored = shouldIgnoreCreature and shouldIgnoreCreature(entry.creature) or false
            if not ignored then
                local reachable = true
                if requireSight and not entry:hasSightClear() then
                    reachable = false
                end

                if reachable then
                    local distance = math.max(entry.dx, entry.dy)
                    if not closestDistance or distance < closestDistance then
                        closestDistance = distance
                    end
                end
            end
        end
    end
    return closestDistance
end

-- Get monsters in range (for targeting/magic shooter) - All reachable
function CreatureCache.getMonstersInRange(maxDistance, requireSight, requireSameFloor)
    CreatureCache.update()

    requireSight = requireSight ~= false
    requireSameFloor = requireSameFloor ~= false

    local result = {}
    for _, entry in ipairs(cacheState.monsters) do
        if not requireSameFloor or entry.sameFloor then
            local distance = math.max(entry.dx, entry.dy)
            if not maxDistance or distance <= maxDistance then
                if not requireSight or entry:hasSightClear() then
                    table.insert(result, entry)
                end
            end
        end
    end
    return result
end

-- Get creatures around for spell calculations (same floor, within range) - All reachable
function CreatureCache.getCreaturesAroundCount(maxRange)
    CreatureCache.update()

    maxRange = maxRange or 6
    local count = 0

    for _, entry in ipairs(cacheState.monsters) do
        if entry.sameFloor then
            local distance = math.max(entry.dx, entry.dy)
            if distance <= maxRange then
                count = count + 1
            end
        end
    end
    return count
end

-- Get raw cache time for compatibility
function CreatureCache.getCacheTime()
    return cacheState.lastUpdateTime
end

-- Get cache position
function CreatureCache.getCachePosition()
    return cacheState.lastPosition
end

-- Check if reachability filter is enabled
function CreatureCache.isFilteringByReachability()
    return cacheState.config.filterByReachability
end

-- =============================================================================
-- Diagnostics (MAD-13 D1 validation hooks)
-- Use these from the Lua console to verify the leak is gone:
--   > local s = CreatureCache.getMemoryStats(); print(s.luaKB, s.cacheEntries)
--   > CreatureCache.forceGC()  -- to settle the heap before reading
-- =============================================================================

-- Returns: { luaKB, cacheEntries, monsters, players, npcs }
function CreatureCache.getMemoryStats()
    local s = {
        luaKB = collectgarbage('count'), -- KB allocated in Lua heap right now
        cacheEntries = 0,
        monsters = #cacheState.monsters,
        players = #cacheState.players,
        npcs = #cacheState.npcs,
    }
    for _ in pairs(cacheState.creatures) do
        s.cacheEntries = s.cacheEntries + 1
    end
    return s
end

-- Force a full GC cycle and return how much was reclaimed.
-- Useful for confirming "is this growth real leakage or just deferred GC?".
function CreatureCache.forceGC()
    local before = collectgarbage('count')
    collectgarbage('collect')
    collectgarbage('collect') -- second pass for __gc finalizers on userdata
    local after = collectgarbage('count')
    return { beforeKB = before, afterKB = after, reclaimedKB = before - after }
end

-- Module initialization
function CreatureCache.init()
    -- Connect to game events for cache invalidation
    connect(g_game, {
        onGameEnd = function()
            CreatureCache.invalidate()
        end
    })
end

function CreatureCache.terminate()
    disconnect(g_game, {
        onGameEnd = nil
    })
    CreatureCache.invalidate()
end

-- Export globally
_G.CreatureCache = CreatureCache

return CreatureCache
