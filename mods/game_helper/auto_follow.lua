-- Auto Follow Module
-- Follows a player by memorizing and replicating their exact path
-- Enhanced with PathSharing for cross-floor/teleport following between OTC clients

local AutoFollow = {}

-- Path Sharing Module (for cross-floor following)
local PathSharing = nil

-- Persisted settings keys (g_settings). Read at load, written by the setters so
-- the UI comboboxes (@onSetup reads the same keys) and the running module agree.
local SETTINGS_DISTANCE = 'autoFollow.distance'
local SETTINGS_STYLE = 'autoFollow.style'

-- Valid follow styles. Behind/Front/Left/Right are relative to the LEADER's
-- facing; Normal is the legacy behaviour (stop at `distance`); Wave forces the
-- follower onto a straight line to the leader in its current relative direction.
local VALID_STYLES = {
    Normal = true, Behind = true, Front = true, Left = true, Right = true, Wave = true
}

local function loadFollowDistance()
    local d = g_settings.getNumber(SETTINGS_DISTANCE)
    if type(d) ~= "number" or d < 1 or d > 5 then return 1 end
    return math.floor(d)
end

local function loadFollowStyle()
    local s = g_settings.getString(SETTINGS_STYLE)
    if type(s) ~= "string" or not VALID_STYLES[s] then return "Normal" end
    return s
end

-- State
local autoFollowState = {
    enabled = false,
    targetName = nil,
    targetId = nil,
    lastTargetPos = nil,
    pathQueue = {},           -- Queue of positions the target walked
    followEvent = nil,
    monitorEvent = nil,
    isMoving = false,
    lastStepTime = 0,
    walkPending = false,      -- a non-pre-walked step is in flight (see followWalk/doStep)
    walkPendingAt = 0,        -- g_clock.millis() when it was sent (for the timeout)
    walkPendingPos = nil,     -- our position when it was sent (cleared once we move)
    navDest = nil,            -- last destination navStep aimed at (stuck-timer reset key)
    navLastPos = nil,         -- our position at the last navStep (to detect progress)
    navProgressAt = 0,        -- g_clock.millis() of our last progress toward navDest
    targetLost = false,       -- True when target disappeared from screen
    targetLostPos = nil,      -- Last known position when target was lost
    usePathSharing = true,    -- Enable cross-floor following via opcode 220
    pathSharingConnected = false, -- True when connected to leader via PathSharing
    updatingUI = false,           -- Guard flag to prevent cascade from checkbox onChange

    -- Positioning: how far (1-5 SQM) and in which style to keep from the leader.
    followDistance = loadFollowDistance(),
    followStyle = loadFollowStyle()
}

-- Configuration
local CONFIG = {
    MONITOR_INTERVAL = 20,    -- ms - how often to check/record target position (fast!)
    STEP_INTERVAL = 20,       -- ms - re-evaluate/step this often (was 50). Closes the
                              -- gap between finishing a step and issuing the next one,
                              -- so the follow keeps up far better with a fast target.
    MAX_QUEUE_SIZE = 40,      -- Max positions to remember (longer breadcrumb trail so a
                              -- target that briefly runs off-screen can still be retraced)
    KEEP_DISTANCE = 1,        -- Always stay 1 position behind target
    PATH_SHARING_PRIORITY = true, -- Prioritize paths from PathSharing over visual monitoring
    -- Max time to wait for a non-pre-walked step (paralyzed/diagonal/server-walking)
    -- to be confirmed before allowing a retry. Bounds both how long follow pauses on a
    -- silently-rejected step and the worst-case wasted re-sends (~1 every this many ms).
    WALK_PENDING_TIMEOUT = 400, -- ms
    -- Pathfinding FALLBACK (see navStep). The fast path stays greedy single-step; only
    -- when we make no progress toward a STABLE destination for this long (a wall or a
    -- mob wedged in a 1-wide lane the greedy keeps butting into) do we ask g_map.findPath
    -- to route around it. Kept well above WALK_PENDING_TIMEOUT so an ordinary in-flight
    -- step gets to resolve first and we don't pathfind on every transient block.
    NAV_STUCK_MS = 500,         -- ms with zero progress before the pathfinder kicks in
    NAV_MAX_COMPLEXITY = 60,    -- A* node budget (covers ~7-8 SQM radius, stays cheap)
    -- Transit use-transition (ladder): after issuing a `use` on the leader's departure
    -- tile, wait this long for our floor to change before giving up on that tile (a rope
    -- spot / non-usable would otherwise never resolve). Also bounds `use` spam.
    USE_COOLDOWN = 600          -- ms
}

-- Rope item ids (same set the cavebot uses). For a rope-spot transition the follower
-- does g_game.useInventoryItemWith(ropeId, tile) -- reproducing the leader roping up.
local ROPE_IDS = {3003, 9596, 9598, 9594}


-- Check if auto follow should be blocked.
-- NOTE: the old in-fight block was REMOVED. It tested the "Swords" battle-sign
-- flag (PlayerStates.Swords = 128) as a stand-in for Amon's RedSwords PVP flag,
-- because Astra has no PVP-specific state and the astra_compat shim aliases
-- RedSwords -> Swords. But Swords is set during ORDINARY PvE combat too, so the
-- block made the Enable checkbox refuse to turn on (AutoFollow.toggle bailed ->
-- the checkbox reverted) AND made doStep auto-disable follow the moment any fight
-- started -- exactly when you want to follow a hunting partner. With no PVP-only
-- flag available, we drop the in-fight block entirely and only gate genuine
-- no-follow contexts.
local function isAutoFollowBlocked()
    -- Inside an expedition. CommandBridge is absent in Astra today, so this is
    -- currently inert; kept for when/if that context gets ported.
    if CommandBridge and CommandBridge.getState then
        local state = CommandBridge.getState()
        if state and state.expedition and state.expedition.inside then
            return true, "expedition"
        end
    end

    return false, nil
end

-- Floor change / Teleport IDs
local floorChangeOrTeleports = {}

-- Helper to add range of IDs
local function addRange(from, to)
    for id = from, to do
        floorChangeOrTeleports[id] = true
    end
end

-- Helper to add single ID
local function addId(id)
    floorChangeOrTeleports[id] = true
end

-- Populate the table. Generated from the server's data/items/items.xml (every
-- item with type=teleport or a floorchange attribute), unioned with the manual
-- IDs that are NOT in items.xml because they are script-defined server-side
-- (e.g. the Heroic Dimension portals 60619-60638). To regenerate: re-extract
-- from items.xml and UNION with the manual IDs so existing coverage isn't lost.
addRange(166, 167) addRange(293, 294) addRange(369, 370) addId(385) addId(394) addRange(411, 414)
addId(428) addRange(432, 434) addRange(437, 438) addId(469) addId(476) addRange(482, 485)
addId(516) addRange(566, 567) addRange(594, 595) addRange(600, 601) addRange(604, 605) addId(607)
addRange(609, 610) addId(615) addId(628) addId(775) addRange(855, 856) addId(859)
addId(868) addId(874) addRange(877, 878) addRange(1066, 1067) addId(1080) addId(1156)
addRange(1756, 1758) addRange(1761, 1763) addId(1947) addRange(1949, 1950) addId(1952) addId(1954)
addId(1956) addRange(1958, 1960) addId(1962) addId(1964) addId(1966) addId(1969)
addId(1971) addId(1973) addId(1975) addRange(1977, 1978) addId(2192) addId(2194)
addId(2196) addId(2198) addRange(4823, 4826) addRange(5022, 5023) addId(5033) addId(5035)
addId(5037) addId(5039) addId(5081) addRange(5257, 5259) addId(5544) addId(5691)
addId(5731) addId(5756) addId(5763) addRange(6127, 6130) addRange(6172, 6173) addRange(6754, 6756)
addId(6909) addId(6911) addId(6913) addId(6915) addRange(6917, 6924) addId(7053)
addRange(7181, 7182) addRange(7476, 7479) addRange(7515, 7522) addId(7542) addId(7544) addId(7546)
addId(7548) addRange(7729, 7737) addId(7755) addRange(7767, 7768) addId(7881) addRange(7887, 7888)
addId(8144) addId(8193) addRange(8657, 8658) addId(8690) addId(8709) addRange(8830, 8831)
addId(8932) addId(10206) addId(11365) addRange(11552, 11554) addId(11707) addId(11709)
addId(12203) addId(12236) addId(12796) addId(12799) addId(12961) addRange(13341, 13342)
addId(13559) addId(13561) addId(13564) addId(13567) addId(13570) addId(13573)
addId(13576) addId(13579) addId(13582) addId(13585) addId(13588) addId(13591)
addId(13716) addId(13718) addId(13720) addId(13722) addRange(14133, 14135) addId(14932)
addId(14934) addId(14936) addId(14938) addId(15108) addId(15110) addId(15112)
addId(15114) addRange(15144, 15146) addId(15320) addRange(16265, 16272) addId(16680) addId(16682)
addId(16684) addId(16686) addId(16688) addId(16690) addId(16692) addId(16694)
addRange(16696, 16703) addRange(16785, 16792) addId(17230) addId(17239) addRange(17394, 17395) addRange(18642, 18656)
addId(19143) addId(19220) addId(19243) addRange(19590, 19591) addId(20124) addRange(20142, 20143)
addRange(20224, 20225) addRange(20253, 20256) addRange(20259, 20263) addRange(20328, 20336) addId(20344) addRange(20469, 20473)
addRange(20488, 20496) addRange(20750, 20751) addId(20753) addId(20755) addId(21034) addId(21342)
addId(21344) addId(21564) addId(21566) addId(21568) addId(21570) addRange(21739, 21741)
addId(21743) addRange(21971, 21973) addId(22106) addRange(22156, 22157) addId(22517) addRange(22565, 22566)
addRange(22747, 22749) addId(22761) addId(23154) addId(23364) addRange(23482, 23484) addId(23858)
addId(23860) addId(23862) addId(23864) addId(24806) addId(24808) addId(24810)
addId(24812) addId(25016) addId(25018) addId(25020) addId(25022) addRange(25047, 25058)
addRange(27589, 27590) addRange(27628, 27629) addId(27658) addId(28357) addId(28359) addId(28361)
addId(28363) addId(28655) addRange(28672, 28673) addId(29109) addId(29111) addId(29113)
addId(29115) addId(29137) addId(29139) addId(29141) addId(29143) addRange(29979, 29980)
addRange(30452, 30453) addId(30757) addId(30759) addId(30761) addId(30763) addId(30820)
addId(30822) addId(30824) addId(30826) addId(30904) addId(30906) addId(30908)
addId(30910) addId(30912) addId(30914) addId(30916) addId(30918) addRange(31129, 31130)
addId(31168) addId(31907) addId(32020) addId(32979) addRange(33004, 33007) addId(33175)
addId(33177) addId(33179) addId(33181) addId(33204) addId(33206) addId(33208)
addId(33210) addId(33233) addId(33235) addId(33237) addId(33239) addId(33256)
addId(33258) addId(33260) addId(33262) addId(33709) addId(34111) addRange(34165, 34166)
addId(34255) addId(35502) addId(36444) addId(36446) addId(36448) addId(36450)
addId(36973) addRange(37000, 37001) addId(37065) addId(37964) addId(37966) addId(37968)
addId(37970) addRange(38831, 38832) addRange(39721, 39722) addId(39919) addId(39921) addId(39923)
addId(39925) addRange(40262, 40263) addId(40279) addId(40281) addId(40296) addId(40298)
addId(40302) addId(40428) addId(40430) addId(40432) addId(40434) addId(42391)
addId(42393) addId(42395) addId(42397) addId(42619) addId(42621) addId(42623)
addId(42632) addId(42965) addId(42967) addId(42969) addId(42971) addId(43130)
addId(43132) addId(43134) addId(43372) addId(44027) addId(44896) addId(44898)
addId(44900) addId(44902) addRange(44942, 44943) addId(44946) addId(44948) addId(45154)
addId(45156) addId(45158) addId(45160) addId(45395) addId(45397) addId(45399)
addId(45401) addId(49161) addId(49657) addId(49659) addId(49661) addId(49663)
addRange(49776, 49783) addId(49937) addId(49939) addId(49941) addId(49943) addRange(50069, 50072)
addRange(50082, 50085) addId(50121) addId(50547) addId(50551) addId(50553) addId(50555)
addId(50613) addId(51313) addId(51366) addId(56485) addId(56487) addId(56489)
addId(56491) addRange(57189, 57203) addId(60123) addId(60236) addRange(60253, 60256) addRange(60378, 60387)
addRange(60459, 60461) addRange(60619, 60638)

-- ============================================================================
-- PATH SHARING INTEGRATION
-- ============================================================================

local function initPathSharing()
    if PathSharing then return PathSharing end
    
    local success, result = pcall(dofile, "/game_helper/path_sharing.lua")
    if success then
        PathSharing = result
        PathSharing.init()
        
        -- Set up callbacks
        PathSharing.onSubscribed = function(leaderName, config)
            autoFollowState.pathSharingConnected = true
            -- g_logger.info("[AutoFollow] Connected to leader via PathSharing: " .. leaderName)
        end
        
        PathSharing.onUnsubscribed = function()
            autoFollowState.pathSharingConnected = false
            -- g_logger.info("[AutoFollow] Disconnected from PathSharing")
        end
        
        -- The trail now lives inside PathSharing (fed by the server stream); the transit
        -- regime in doStep reads it directly via PathSharing.peek/getNextDestination. No
        -- local queue mirroring needed, so this is just a hook point (kept for symmetry).
        PathSharing.onPathReceived = function(destPos)
        end
        
        return PathSharing
    else
        -- g_logger.warning("[AutoFollow] Failed to load PathSharing: " .. tostring(result))
        return nil
    end
end

local function connectToLeader(targetName)
    if not autoFollowState.usePathSharing then return false end
    
    local ps = initPathSharing()
    if not ps then return false end
    
    ps.subscribe(targetName)
    return true
end

local function disconnectFromLeader()
    if PathSharing and PathSharing.isFollowing() then
        PathSharing.unsubscribe()
    end
    autoFollowState.pathSharingConnected = false
end

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

local function getDistance(pos1, pos2)
    if not pos1 or not pos2 then return 999 end
    return math.max(math.abs(pos1.x - pos2.x), math.abs(pos1.y - pos2.y))
end

local function getDistance3D(pos1, pos2)
    if not pos1 or not pos2 then return 999 end
    return math.max(math.abs(pos1.x - pos2.x), math.abs(pos1.y - pos2.y), math.abs(pos1.z - pos2.z) * 10)
end

local function isSamePosition(pos1, pos2)
    if not pos1 or not pos2 then return false end
    return pos1.x == pos2.x and pos1.y == pos2.y and pos1.z == pos2.z
end

local function copyPosition(pos)
    if not pos then return nil end
    return {x = pos.x, y = pos.y, z = pos.z}
end

-- Throttle for the spectator-scan FALLBACK only (the cache lookup below always
-- runs). When the target is genuinely off-screen, the 20ms monitor/step loops
-- would otherwise re-scan the whole spectator list every tick; the cache can't
-- help (the player isn't in it), so we cap the raw scan to ~100ms. This never
-- delays re-acquisition of a target inside the cache's range (that path is hit
-- every tick), and 100ms is well under perceptible follow latency. The first
-- attempt after each gap is never throttled.
local NAME_FALLBACK_SCAN_INTERVAL = 100  -- ms
local lastNameFallbackScan = 0

local function getCreatureByName(name)
    if not name then return nil end
    local player = g_game.getLocalPlayer()
    if not player then return nil end

    -- PERF: the monitor (20ms) and step (20ms) loops only fall here when the
    -- id-based lookup misses, but the old code then re-scanned the entire
    -- spectator list on EVERY such tick. Consult the shared CreatureCache first
    -- (200ms TTL, already refreshed by the other helper modules each tick), so
    -- the common case is a cheap cache read instead of a fresh scan. The cache
    -- only holds players within its detect range (9x7, same floor); to keep
    -- acquisition reach IDENTICAL we fall back to the original full-viewport
    -- spectator scan on a cache miss (e.g. a target at the very screen edge).
    if CreatureCache and CreatureCache.getPlayers then
        local players = CreatureCache.getPlayers()
        if players then
            for _, entry in ipairs(players) do
                if entry.name == name and entry.creature then
                    return entry.creature
                end
            end
        end
    end

    -- Cache miss: fall back to the full spectator scan, but throttled so a
    -- truly-lost target doesn't trigger a fresh scan on every 20ms tick.
    local now = g_clock.millis()
    if (now - lastNameFallbackScan) < NAME_FALLBACK_SCAN_INTERVAL then
        return nil
    end
    lastNameFallbackScan = now

    local spectators = g_map.getSpectators(player:getPosition(), false)
    for _, creature in ipairs(spectators) do
        if creature:getName() == name and creature:isPlayer() then
            return creature
        end
    end
    return nil
end

local function getCreatureById(id)
    if not id then return nil end
    return g_map.getCreatureById(id)
end

local function getDirectionTo(from, to)
    if not from or not to then return nil end

    local dx = to.x - from.x
    local dy = to.y - from.y

    -- Clamp to -1, 0, 1
    if dx > 0 then dx = 1 elseif dx < 0 then dx = -1 end
    if dy > 0 then dy = 1 elseif dy < 0 then dy = -1 end

    if dx == 0 and dy == -1 then return Directions.North end
    if dx == 1 and dy == -1 then return Directions.NorthEast end
    if dx == 1 and dy == 0 then return Directions.East end
    if dx == 1 and dy == 1 then return Directions.SouthEast end
    if dx == 0 and dy == 1 then return Directions.South end
    if dx == -1 and dy == 1 then return Directions.SouthWest end
    if dx == -1 and dy == 0 then return Directions.West end
    if dx == -1 and dy == -1 then return Directions.NorthWest end

    return nil
end

-- Check if a tile has a teleport/floor change item
local function getTeleportOnTile(pos)
    local tile = g_map.getTile(pos)
    if not tile then return nil end

    -- Check all items on the tile
    local items = tile:getItems()
    if items then
        for _, item in ipairs(items) do
            local id = item:getId()
            if floorChangeOrTeleports[id] then
                return item, pos
            end
        end
    end

    -- Also check ground
    local ground = tile:getGround()
    if ground then
        local id = ground:getId()
        if floorChangeOrTeleports[id] then
            return ground, pos
        end
    end

    -- Check top use thing
    local topUse = tile:getTopUseThing()
    if topUse and not topUse:isCreature() then
        local id = topUse:getId()
        if floorChangeOrTeleports[id] then
            return topUse, pos
        end
    end

    return nil
end

-- Find nearest teleport around player position
local function findNearestTeleport(centerPos, maxRadius)
    maxRadius = maxRadius or 7

    -- Search in expanding squares
    for radius = 1, maxRadius do
        for dx = -radius, radius do
            for dy = -radius, radius do
                -- Only check the perimeter of this radius
                if math.abs(dx) == radius or math.abs(dy) == radius then
                    local checkPos = {x = centerPos.x + dx, y = centerPos.y + dy, z = centerPos.z}
                    local teleport, pos = getTeleportOnTile(checkPos)
                    if teleport then
                        return teleport, pos
                    end
                end
            end
        end
    end

    return nil
end

-- ============================================================================
-- PATH QUEUE MANAGEMENT
-- ============================================================================

local function addToQueue(pos)
    if not pos then return end

    -- Don't add duplicates
    local lastInQueue = autoFollowState.pathQueue[#autoFollowState.pathQueue]
    if lastInQueue and isSamePosition(lastInQueue, pos) then
        return
    end

    table.insert(autoFollowState.pathQueue, copyPosition(pos))

    -- Trim queue if too large
    while #autoFollowState.pathQueue > CONFIG.MAX_QUEUE_SIZE do
        table.remove(autoFollowState.pathQueue, 1)
    end
end

local function getNextFromQueue()
    -- Keep KEEP_DISTANCE positions behind target
    -- BUT if target is lost, process all remaining positions
    if autoFollowState.targetLost then
        -- Target lost - process all remaining queue items
        if #autoFollowState.pathQueue == 0 then return nil end
        return autoFollowState.pathQueue[1]
    else
        -- Target visible - keep distance
        if #autoFollowState.pathQueue <= CONFIG.KEEP_DISTANCE then return nil end
        return autoFollowState.pathQueue[1]
    end
end

local function removeFromQueue()
    if #autoFollowState.pathQueue > 0 then
        table.remove(autoFollowState.pathQueue, 1)
    end
end

local function clearQueue()
    autoFollowState.pathQueue = {}
end

-- Skip positions in queue to catch up (if player is closer to a later position)
local function optimizeQueue(playerPos)
    if #autoFollowState.pathQueue < 2 then return end

    local firstPos = autoFollowState.pathQueue[1]
    
    -- For PathSharing: Skip WALK waypoints if we're closer to a later position
    -- But NEVER skip NODE waypoints (teleports/stairs)
    if firstPos._fromPathSharing then
        -- If first is a NODE, don't skip it
        if firstPos._type == "node" then
            return
        end
        
        -- First is WALK type - check if we can skip to a closer waypoint
        local skipTo = 0
        for i = 2, math.min(#autoFollowState.pathQueue, 10) do
            local pos = autoFollowState.pathQueue[i]
            if not pos._fromPathSharing then break end
            
            -- If we hit a NODE, stop - we can skip WALK waypoints up to the one before NODE
            if pos._type == "node" then
                -- Check if we're on same floor as the NODE
                if playerPos.z == pos.z then
                    -- Skip all WALKs before this NODE
                    skipTo = i - 1
                end
                break
            end
            
            -- Check if we're closer to this WALK than current
            local distToCurrent = getDistance(playerPos, firstPos)
            local distToThis = getDistance(playerPos, pos)
            if distToThis < distToCurrent and playerPos.z == pos.z then
                skipTo = i - 1
            end
        end
        
        if skipTo > 0 then
            -- g_logger.info(string.format("[AutoFollow] Skipping %d WALK waypoints", skipTo))
            for _ = 1, skipTo do
                table.remove(autoFollowState.pathQueue, 1)
            end
        end
        return
    end

    -- Non-PathSharing: original logic
    local closestIdx = 1
    local closestDist = getDistance3D(playerPos, autoFollowState.pathQueue[1])

    for i = 2, math.min(#autoFollowState.pathQueue, 10) do
        local pos = autoFollowState.pathQueue[i]
        if pos._fromPathSharing then break end
        
        local dist = getDistance3D(playerPos, pos)
        if dist < closestDist then
            closestDist = dist
            closestIdx = i
        end
    end

    if closestIdx > 1 then
        for _ = 1, closestIdx - 1 do
            table.remove(autoFollowState.pathQueue, 1)
        end
    end
end

-- ============================================================================
-- MONITOR TARGET POSITION
-- ============================================================================

local function monitorTarget()
    if not autoFollowState.enabled then return end

    -- Find target
    local target = getCreatureById(autoFollowState.targetId)
    if not target then
        target = getCreatureByName(autoFollowState.targetName)
        if target then
            autoFollowState.targetId = target:getId()
        end
    end

    if not target then
        -- Target not visible! Mark as lost
        if autoFollowState.lastTargetPos and not autoFollowState.targetLost then
            autoFollowState.targetLost = true
            autoFollowState.targetLostPos = copyPosition(autoFollowState.lastTargetPos)
            
            -- If using PathSharing, we might still get path updates
            if autoFollowState.pathSharingConnected then
                -- g_logger.info("[AutoFollow] Target lost visually, but PathSharing still connected")
            end
        end
        return
    end

    -- Target found again
    if autoFollowState.targetLost then
        -- g_logger.info("[AutoFollow] Target found again: " .. autoFollowState.targetName)
    end
    autoFollowState.targetLost = false
    autoFollowState.targetLostPos = nil

    local targetPos = target:getPosition()
    if not targetPos then return end

    -- Check if target moved
    if not autoFollowState.lastTargetPos or not isSamePosition(autoFollowState.lastTargetPos, targetPos) then
        -- If we're connected via PathSharing and have path sharing priority,
        -- don't add visual positions (PathSharing will provide accurate paths)
        if CONFIG.PATH_SHARING_PRIORITY and autoFollowState.pathSharingConnected then
            -- Only update lastTargetPos for reference, don't add to queue
            autoFollowState.lastTargetPos = copyPosition(targetPos)
        else
            -- Target moved! Add new position to queue
            addToQueue(targetPos)
            autoFollowState.lastTargetPos = copyPosition(targetPos)
        end
    end
end

local function startMonitor()
    if autoFollowState.monitorEvent then
        removeEvent(autoFollowState.monitorEvent)
    end

    local function loop()
        if not autoFollowState.enabled then return end

        monitorTarget()

        autoFollowState.monitorEvent = scheduleEvent(loop, CONFIG.MONITOR_INTERVAL)
    end

    loop()
end

local function stopMonitor()
    if autoFollowState.monitorEvent then
        removeEvent(autoFollowState.monitorEvent)
        autoFollowState.monitorEvent = nil
    end
end

-- ============================================================================
-- FOLLOW LOGIC
-- ============================================================================

-- ============================================================================
-- WALKING HELPER - single-step, orthogonal-preferred (NO autoWalk/pathfinder)
-- ============================================================================

-- Forward declaration: walkTo (below) calls navStep -> stepDirTowards/followWalk, which
-- are only defined further down (they depend on isWalkable, defined after walkTo).
-- Declaring the locals here lets walkTo capture them as upvalues; bodies assigned later.
local stepDirTowards, followWalk, navStep

local function walkTo(dest)
    if not dest then return false end
    if type(dest.x) ~= "number" or type(dest.y) ~= "number" or type(dest.z) ~= "number" then
        return false
    end

    local player = g_game.getLocalPlayer()
    if not player then return false end

    local playerPos = player:getPosition()
    if not playerPos then return false end

    -- Auto Follow NEVER uses autoWalk (the client pathfinder): it has higher response
    -- latency and traces diagonals, which stall the char (~3x the cost of a straight
    -- step) and make it lose the target. Instead we take a single orthogonal-preferred
    -- step toward dest (navStep), falling back to g_map.findPath ONLY when that greedy
    -- step is wedged against an obstacle -- lower latency, no needless diagonal, and it
    -- no longer gets stuck on a wall/mob it can route around. See navStep.
    return navStep(playerPos, dest)
end

-- Get position behind target (opposite of their facing direction)
local function getPositionBehind(target)
    if not target then return nil end
    
    local pos = target:getPosition()
    if not pos or not pos.x or not pos.y or not pos.z then return nil end
    
    local dir = target:getDirection()
    if not dir then return nil end
    
    local behind = {x = pos.x, y = pos.y, z = pos.z}
    
    -- Get position behind based on direction they're facing
    if dir == Directions.North then
        behind.y = behind.y + 1  -- Behind is south
    elseif dir == Directions.South then
        behind.y = behind.y - 1  -- Behind is north
    elseif dir == Directions.East then
        behind.x = behind.x - 1  -- Behind is west
    elseif dir == Directions.West then
        behind.x = behind.x + 1  -- Behind is east
    elseif dir == Directions.NorthEast then
        behind.x = behind.x - 1
        behind.y = behind.y + 1
    elseif dir == Directions.NorthWest then
        behind.x = behind.x + 1
        behind.y = behind.y + 1
    elseif dir == Directions.SouthEast then
        behind.x = behind.x - 1
        behind.y = behind.y - 1
    elseif dir == Directions.SouthWest then
        behind.x = behind.x + 1
        behind.y = behind.y - 1
    else
        -- Unknown direction, return position behind (south)
        behind.y = behind.y + 1
    end
    
    return behind
end

-- Set true by doStep during the FORMATION regime (leader on our floor). While it's on,
-- floor-change / teleport tiles (holes, stairs, ramps, teleports, ladders -- anything in
-- floorChangeOrTeleports) count as BLOCKED, so both the desired-spot math AND the stepping
-- treat them as walls: the follower routes AROUND them and never falls off its floor while
-- the leader is on the same one. Reset to false in transit, where we DELIBERATELY step onto
-- such a tile to change floor and chase the leader.
local avoidFloorChange = false

-- Check if position is walkable. Floor-change-aware in formation (see avoidFloorChange):
-- a hole/stairs/teleport tile is treated as NOT walkable so we don't stand on / step into
-- it and get dragged off our floor.
local function isWalkable(pos)
    if not pos or not pos.x or not pos.y or not pos.z then return false end
    local tile = g_map.getTile(pos)
    if not tile then return false end
    if not tile:isWalkable() then return false end
    if avoidFloorChange and getTeleportOnTile(pos) then return false end
    return true
end

-- Find best position around target (prefer behind, then sides, then front)
local function getBestPositionAroundTarget(target, playerPos)
    if not target then return nil end
    
    local targetPos = target:getPosition()
    if not targetPos or not targetPos.x or not targetPos.y or not targetPos.z then 
        return nil 
    end
    
    if not playerPos or not playerPos.x then return nil end
    
    -- Already adjacent? Stay put
    if getDistance(playerPos, targetPos) <= 1 then
        return nil
    end
    
    -- Try behind first
    local behind = getPositionBehind(target)
    if behind and behind.x and isWalkable(behind) then
        return behind
    end
    
    -- Try all adjacent positions, prefer closest to player
    local positions = {
        {x = targetPos.x, y = targetPos.y - 1, z = targetPos.z},  -- North
        {x = targetPos.x + 1, y = targetPos.y, z = targetPos.z},  -- East
        {x = targetPos.x, y = targetPos.y + 1, z = targetPos.z},  -- South
        {x = targetPos.x - 1, y = targetPos.y, z = targetPos.z},  -- West
        {x = targetPos.x + 1, y = targetPos.y - 1, z = targetPos.z},  -- NE
        {x = targetPos.x + 1, y = targetPos.y + 1, z = targetPos.z},  -- SE
        {x = targetPos.x - 1, y = targetPos.y + 1, z = targetPos.z},  -- SW
        {x = targetPos.x - 1, y = targetPos.y - 1, z = targetPos.z},  -- NW
    }
    
    local best = nil
    local bestDist = 999
    
    for _, pos in ipairs(positions) do
        if isWalkable(pos) then
            local dist = getDistance(playerPos, pos)
            if dist < bestDist then
                bestDist = dist
                best = pos
            end
        end
    end

    return best
end

-- Step toward `dest` preferring ORTHOGONAL movement. A diagonal in Tibia costs
-- ~2-3x a straight step and a human only walks diagonally while holding Ctrl; the
-- old chase (getDirectionTo directly) cut corners diagonally, which shows up as
-- "walking diagonally for no reason" when following someone moving in a straight
-- line. Here we take the orthogonal step that gets closest to dest and only fall
-- back to the diagonal when BOTH orthogonal steps are blocked (the diagonal is
-- then the only way around the obstacle).
-- (assigned to the local forward-declared above walkTo, which calls this)
stepDirTowards = function(playerPos, dest)
    if not playerPos or not dest then return nil end

    local dx = dest.x - playerPos.x
    local dy = dest.y - playerPos.y
    local sx = (dx > 0) and 1 or (dx < 0 and -1 or 0)
    local sy = (dy > 0) and 1 or (dy < 0 and -1 or 0)
    if sx == 0 and sy == 0 then return nil end

    -- Candidate step tiles toward dest, in preference order. isWalkable is floor-change
    -- aware in formation, so a hole/stairs/teleport on the direct line reads as BLOCKED
    -- and we pick a go-around instead of stepping into it (the reported bug: walking
    -- straight into a hole that sits between us and the desired spot).
    local cands
    if sx ~= 0 and sy ~= 0 then
        -- Diagonal target: orthogonal-preferred (a diagonal costs ~3x a straight step),
        -- greater-remaining axis first (avoids overshoot), then the diagonal detour.
        local h = {x = playerPos.x + sx, y = playerPos.y,      z = playerPos.z}
        local v = {x = playerPos.x,      y = playerPos.y + sy, z = playerPos.z}
        local dg = {x = playerPos.x + sx, y = playerPos.y + sy, z = playerPos.z}
        if math.abs(dx) >= math.abs(dy) then cands = {h, v, dg} else cands = {v, h, dg} end
    else
        -- Orthogonal target: the direct tile first, then go-around alternatives -- the two
        -- diagonals that still make progress, then the pure perpendiculars -- so a blocked
        -- or dangerous direct tile routes us AROUND it instead of stalling / falling in.
        local direct = {x = playerPos.x + sx, y = playerPos.y + sy, z = playerPos.z}
        if sx ~= 0 then
            cands = {direct,
                {x = playerPos.x + sx, y = playerPos.y - 1, z = playerPos.z},
                {x = playerPos.x + sx, y = playerPos.y + 1, z = playerPos.z},
                {x = playerPos.x,      y = playerPos.y - 1, z = playerPos.z},
                {x = playerPos.x,      y = playerPos.y + 1, z = playerPos.z}}
        else
            cands = {direct,
                {x = playerPos.x - 1, y = playerPos.y + sy, z = playerPos.z},
                {x = playerPos.x + 1, y = playerPos.y + sy, z = playerPos.z},
                {x = playerPos.x - 1, y = playerPos.y,      z = playerPos.z},
                {x = playerPos.x + 1, y = playerPos.y,      z = playerPos.z}}
        end
    end

    for _, c in ipairs(cands) do
        if isWalkable(c) then
            return getDirectionTo(playerPos, c)
        end
    end

    -- Everything blocked. Avoiding floor changes (formation): do NOT force a step -- the
    -- only tiles left are the hole/stairs/teleport we're dodging, so stay put (nil).
    -- Otherwise (transit) fall back to the direct direction to still push toward / onto
    -- the transition tile.
    if avoidFloorChange then return nil end
    return getDirectionTo(playerPos, dest)
end

-- Direction -> {dx, dy} tile delta, used to find the destination tile of a step.
local DIR_DELTA = {
    [Directions.North]     = { 0, -1}, [Directions.East]      = { 1,  0},
    [Directions.South]     = { 0,  1}, [Directions.West]      = {-1,  0},
    [Directions.NorthEast] = { 1, -1}, [Directions.SouthEast] = { 1,  1},
    [Directions.SouthWest] = {-1,  1}, [Directions.NorthWest] = {-1, -1},
}

-- Emit one step with OPTIMISTIC pre-walk when it is safe: the char moves immediately
-- instead of waiting for the server round-trip, cutting ~1 ping of latency per step
-- (the single biggest response-time win for follow). Pre-walk is only safe for an
-- ORTHOGONAL step (a diagonal pre-walk becomes a double-step) onto a walkable tile,
-- and not while server-walking / paralyzed / pre-walk-locked -- the same guards the
-- native game_walking uses. Otherwise we send a plain walk. Since the follow now
-- prefers orthogonal steps (stepDirTowards), the common case gets the fast path.
followWalk = function(dir)
    if not dir then return false end
    local player = g_game.getLocalPlayer()
    if not player then return false end

    local prewalked = false
    local delta = DIR_DELTA[dir]
    local diagonal = delta and delta[1] ~= 0 and delta[2] ~= 0
    if delta and not diagonal and player.preWalk
        and not (player.isServerWalking and player:isServerWalking())
        and not (player.isParalyzed and player:isParalyzed())
        and (not player.getPreWalkLockedDelay or player:getPreWalkLockedDelay() < g_clock.millis()) then
        local pos = (player.getPrewalkingPosition and player:getPrewalkingPosition(true)) or player:getPosition()
        if pos then
            local toTile = g_map.getTile({x = pos.x + delta[1], y = pos.y + delta[2], z = pos.z})
            if toTile and toTile:isWalkable() then
                player:preWalk(dir)
                prewalked = true
            end
        end
    end

    g_game.walk(dir, prewalked)

    -- Without pre-walk the client does NOT move locally until the server confirms
    -- (~1 ping later), so player:isWalking() stays false and the 20ms follow loop
    -- would re-send this exact step 2-5x. Mark it in-flight so doStep holds off until
    -- it resolves. Pre-walked steps already flip isWalking() true, so clear the flag.
    if prewalked then
        autoFollowState.walkPending = false
    else
        autoFollowState.walkPending = true
        autoFollowState.walkPendingAt = g_clock.millis()
        autoFollowState.walkPendingPos = player:getPosition()
    end

    return true
end

-- Pathfinder flag passes for the stuck fallback, tried in order:
--   0  = respect creatures  -> a route that walks around walls AND mobs (ideal).
--   16 = IgnoreCreatures     -> if the first finds NoWay (goal momentarily occupied,
--        or a mob fully walls the only 1-tile lane) we still head the right way and
--        push at the blocker, like a human holding the arrow key.
-- Raw literals on purpose (matches how the rest of the helper passes PathFind flags;
-- see astra_compat notes). Walls are NEVER ignored, so we only ever route around them.
local NAV_PATHFIND_FLAGS = { 0, 16 }

-- One navigation step toward `dest`, single-step so pre-walk / low latency are kept.
-- PRIMARY: the fast greedy orthogonal step (stepDirTowards). FALLBACK: when we've made
-- no progress toward a STABLE dest for NAV_STUCK_MS, the greedy step is wedged behind a
-- wall (or a mob in a 1-wide lane) it can't corner around, so we ask g_map.findPath for
-- the first step of a real route and take that instead. The stuck timer only counts a
-- genuinely-stuck chase: it resets whenever we move OR the destination changes (a moving
-- leader hands us a fresh dest every step, so ordinary following never trips it).
-- findPath is same-floor only (it bails across z); cross-floor is the NODE path in doStep.
navStep = function(playerPos, dest)
    if not playerPos or not dest then return false end

    local now = g_clock.millis()
    local destChanged = not autoFollowState.navDest or not isSamePosition(autoFollowState.navDest, dest)
    local moved = not autoFollowState.navLastPos or not isSamePosition(playerPos, autoFollowState.navLastPos)
    if destChanged or moved then
        autoFollowState.navProgressAt = now
    end
    autoFollowState.navDest = copyPosition(dest)
    autoFollowState.navLastPos = copyPosition(playerPos)
    local stuck = (now - (autoFollowState.navProgressAt or now)) >= CONFIG.NAV_STUCK_MS

    local dir = nil
    if stuck and playerPos.z == dest.z and g_map.findPath then
        -- pcall: findPath is C++ and can throw on odd inputs; a failure just means we
        -- fall through to the greedy step (never let the fallback break the follow).
        for _, flags in ipairs(NAV_PATHFIND_FLAGS) do
            local ok, dirs = pcall(g_map.findPath, playerPos, dest, CONFIG.NAV_MAX_COMPLEXITY, flags)
            if ok and type(dirs) == "table" and dirs[1] ~= nil then
                dir = dirs[1]
                break
            end
        end
        -- findPath treats holes/stairs/teleports as walkable and may route THROUGH one.
        -- In formation we must not step onto such a tile -> drop it and let the greedy
        -- floor-change-aware step route around (or stay put) instead.
        if dir and avoidFloorChange then
            local delta = DIR_DELTA[dir]
            if delta and getTeleportOnTile({x = playerPos.x + delta[1], y = playerPos.y + delta[2], z = playerPos.z}) then
                dir = nil
            end
        end
    end
    if not dir then
        dir = stepDirTowards(playerPos, dest)
    end
    if dir then
        followWalk(dir)
        return true
    end
    return false
end

-- TEMP DIAGNOSTICS (remove after debugging "char doesn't walk"). Throttled so the
-- 50ms follow loop doesn't flood the log: emits the decision path of ONE tick per
-- ~700ms. Grep the client log (repo root KoliseuClient.log) for "[AutoFollow]".
local _afLastDbg = 0
local _afDbgOn = false
local function afdbg(msg)
    if _afDbgOn then g_logger.info("[AutoFollow] " .. tostring(msg)) end
end

-- PathSharing step tracing. The [AutoFollow:PS] logs below fire on every follow
-- step (up to ~50 Hz) and each builds a formatted string; gate them so they cost
-- nothing in normal play. Flip to true only when debugging cross-floor follow.
local DEBUG_PATHSHARING = false

-- ============================================================================
-- FOLLOW STYLE POSITIONING
-- Given the leader (visible, same floor), compute the tile the follower wants to
-- stand on for the current style/distance. Returns nil when we're already at the
-- desired spot (stay put). All math is on the SAME floor; cross-floor / lost
-- re-acquisition is handled by the PRIORITY 2/3 paths, unchanged.
-- ============================================================================

-- Unit vector of each facing direction (screen coords: +x east, +y south).
local DIR_UNIT = {
    [Directions.North]     = {x =  0, y = -1}, [Directions.South]     = {x =  0, y =  1},
    [Directions.East]      = {x =  1, y =  0}, [Directions.West]      = {x = -1, y =  0},
    [Directions.NorthEast] = {x =  1, y = -1}, [Directions.NorthWest] = {x = -1, y = -1},
    [Directions.SouthEast] = {x =  1, y =  1}, [Directions.SouthWest] = {x = -1, y =  1},
}

-- Facing unit vector of the leader; defaults to South if the direction is unknown.
local function facingUnit(target)
    local dir = target and target.getDirection and target:getDirection()
    return DIR_UNIT[dir] or {x = 0, y = 1}
end

-- Pick the reachable tile at `distance` along (ux,uy) from the leader, backing off
-- one SQM at a time if the ideal tile is blocked; if the whole ray is blocked,
-- return the leader tile so the caller just approaches (never stalls).
local function tileAlong(leaderPos, ux, uy, distance, playerPos)
    for d = distance, 1, -1 do
        local cand = {x = leaderPos.x + ux * d, y = leaderPos.y + uy * d, z = leaderPos.z}
        if isSamePosition(cand, playerPos) or isWalkable(cand) then
            return cand
        end
    end
    return {x = leaderPos.x, y = leaderPos.y, z = leaderPos.z}
end

-- Nearest tile on the Chebyshev ring of radius `distance` around the leader, along
-- the follower's CURRENT bearing. This is what "keep EXACTLY `distance`" means for
-- Normal: project OUTWARD when the follower is closer than `distance`, INWARD when
-- farther, so the follower actively backs off instead of hugging the leader. Backs
-- off toward the leader only if the ideal tile is blocked (wall), never stalls.
local function nearestRingTile(leaderPos, distance, playerPos)
    local dx = playerPos.x - leaderPos.x
    local dy = playerPos.y - leaderPos.y
    if dx == 0 and dy == 0 then dy = 1 end             -- degenerate: pick any bearing
    local adx, ady = math.abs(dx), math.abs(dy)
    -- Scale the bearing so the DOMINANT axis lands on +/-distance (= on the ring);
    -- the minor axis stays proportional (may be a corner of the square, which Normal
    -- allows -- Wave is the strict-straight-line style).
    local ux, uy
    if adx >= ady then
        ux, uy = (dx >= 0) and 1 or -1, (adx == 0) and 0 or dy / adx
    else
        ux, uy = (ady == 0) and 0 or dx / ady, (dy >= 0) and 1 or -1
    end
    for d = distance, 1, -1 do
        local cand = {
            x = leaderPos.x + math.floor(ux * d + 0.5),
            y = leaderPos.y + math.floor(uy * d + 0.5),
            z = leaderPos.z
        }
        if isSamePosition(cand, playerPos) or isWalkable(cand) then
            return cand
        end
    end
    return {x = leaderPos.x, y = leaderPos.y, z = leaderPos.z}
end

-- Returns the desired stand-on tile, or nil to stay put.
local function computeStyleDestination(target, playerPos, style, distance)
    local leaderPos = target:getPosition()
    if not leaderPos then return nil end
    distance = distance or 1
    if distance < 1 then distance = 1 elseif distance > 5 then distance = 5 end

    local dist = getDistance(playerPos, leaderPos)

    if style == "Normal" then
        if distance <= 1 then
            -- distance 1 keeps the legacy adjacent behaviour (prefer a tile behind the
            -- leader); getBestPositionAroundTarget returns nil when already adjacent, so
            -- we correctly stay put at 1 SQM and only close in when farther.
            if dist <= 1 then return nil end
            return getBestPositionAroundTarget(target, playerPos) or leaderPos
        end
        -- Keep EXACTLY `distance` SQM: sit on the Chebyshev ring of that radius, backing
        -- OFF when too close (not just stopping). Nearest ring tile to our bearing.
        local ringTile = nearestRingTile(leaderPos, distance, playerPos)
        if isSamePosition(playerPos, ringTile) then return nil end
        return ringTile
    end

    local ux, uy
    if style == "Wave" then
        -- Strictly ORTHOGONAL straight line to the leader (N/S/E/W only, never a
        -- diagonal): collapse the follower's current bearing onto its dominant axis.
        local rx = playerPos.x - leaderPos.x
        local ry = playerPos.y - leaderPos.y
        if math.abs(rx) >= math.abs(ry) then
            ux, uy = (rx > 0) and 1 or (rx < 0 and -1 or 0), 0
        else
            ux, uy = 0, (ry > 0) and 1 or (ry < 0 and -1 or 0)
        end
        if ux == 0 and uy == 0 then
            uy = 1  -- degenerate (same tile as leader): pick south, still orthogonal
        end
    else
        -- Behind/Front/Left/Right are relative to the leader's facing.
        local f = facingUnit(target)
        if style == "Front" then
            ux, uy = f.x, f.y
        elseif style == "Left" then
            ux, uy = f.y, -f.x          -- 90deg to the leader's left
        elseif style == "Right" then
            ux, uy = -f.y, f.x          -- 90deg to the leader's right
        else -- "Behind" (and any unknown style)
            ux, uy = -f.x, -f.y
        end
    end

    local destPos = tileAlong(leaderPos, ux, uy, distance, playerPos)
    if isSamePosition(playerPos, destPos) then return nil end
    return destPos
end

local function doStep()
    if not autoFollowState.enabled then return end

    -- Default: allow floor-change tiles (transit steps onto them). Formation turns this
    -- ON below so it dodges holes/stairs/teleports while the leader is on our floor.
    avoidFloorChange = false

    _afDbgOn = (g_clock.millis() - _afLastDbg) >= 700
    if _afDbgOn then _afLastDbg = g_clock.millis() end

    -- Force disable only in a hard no-follow context (e.g. expedition)
    local blocked, reason = isAutoFollowBlocked()
    if blocked then
        AutoFollow.toggle(false)
        AutoFollow.updateUI()
        if modules.game_textmessage then
            modules.game_textmessage.displayGameMessage("Auto Follow disabled: " .. (reason or "blocked"))
        end
        return
    end

    -- Must have a target name set
    if not autoFollowState.targetName then afdbg("STOP: no targetName"); return end

    local player = g_game.getLocalPlayer()
    if not player then afdbg("STOP: no localPlayer"); return end

    -- Don't interrupt if already walking
    if player:isWalking() then afdbg("STOP: player:isWalking()=true (waiting)"); return end

    local playerPos = player:getPosition()
    if not playerPos or not playerPos.x then afdbg("STOP: no playerPos"); return end

    -- A non-pre-walked step (paralyzed/diagonal/server-walking) is not reflected in
    -- isWalking() until the server confirms (~1 ping), so the 20ms loop would flood
    -- duplicate walks. Hold off until the step resolves: our position changed (it
    -- landed, or we were pushed/teleported) or it timed out (silent reject).
    if autoFollowState.walkPending then
        local moved = autoFollowState.walkPendingPos
            and not isSamePosition(playerPos, autoFollowState.walkPendingPos)
        local timedOut = (g_clock.millis() - (autoFollowState.walkPendingAt or 0)) >= CONFIG.WALK_PENDING_TIMEOUT
        if moved or timedOut then
            autoFollowState.walkPending = false
        else
            afdbg("STOP: walkPending (step in flight)")
            return
        end
    end

    -- ========================================================================
    -- PRIORITY 1: If target is VISIBLE, just walk near/behind them
    -- ========================================================================
    local target = nil
    
    -- Try to find by ID first
    if autoFollowState.targetId then
        target = getCreatureById(autoFollowState.targetId)
    end
    
    -- If not found by ID, try by name
    if not target and autoFollowState.targetName then
        target = getCreatureByName(autoFollowState.targetName)
        if target then
            autoFollowState.targetId = target:getId()
        end
    end
    
    if target then
        local targetPos = target:getPosition()
        if targetPos and targetPos.x and targetPos.y and targetPos.z and targetPos.z == playerPos.z then
            -- Target is visible and on same floor! FORMATION regime: dodge floor-change
            -- tiles so the desired-spot math AND the stepping never drop us off our floor
            -- (a Behind spot that lands on a teleport, or a hole between us and the spot).
            avoidFloorChange = true
            autoFollowState.targetLost = false

            -- Do NOT clear the trail here. Formation uses the on-screen leader, but the
            -- server keeps streaming the leader's positions into the trail; we let it
            -- ACCUMULATE (capped in PathSharing) so that the instant the leader vanishes
            -- through a teleport, the transit regime can still find the exact tile where
            -- the leader left our floor. Clearing on visible would race that away.

            local dist = getDistance(playerPos, targetPos)
            afdbg(string.format("VISIBLE name=%s dist=%d my=(%d,%d,%d) tgt=(%d,%d,%d)",
                tostring(autoFollowState.targetName), dist,
                playerPos.x, playerPos.y, playerPos.z, targetPos.x, targetPos.y, targetPos.z))

            -- Desired stand-on tile for the current style + distance (1-5 SQM).
            -- nil means "already at the desired spot" -> stay put.
            local style = autoFollowState.followStyle or "Normal"
            local distance = autoFollowState.followDistance or 1
            local destPos = computeStyleDestination(target, playerPos, style, distance)

            if not destPos or isSamePosition(playerPos, destPos) then
                afdbg(string.format("at desired spot (style=%s dist=%d) -> staying put", style, distance))
                return
            end

            -- Single orthogonal-preferred step, re-evaluated every tick: tracks a
            -- fast/moving target far more tightly than committing to a whole path
            -- toward where the target WAS (what lets a runner slip away). navStep adds
            -- a findPath fallback so an obstacle between us and the style spot (a wall
            -- corner, a mob in the lane) no longer wedges the chase. No autoWalk.
            afdbg(string.format("step: style=%s dest=(%d,%d,%d) -> navStep",
                style, destPos.x, destPos.y, destPos.z))
            if navStep(playerPos, destPos) then
                autoFollowState.lastStepTime = g_clock.millis()
            end
            return
        else
            afdbg(string.format("target found but NOT usable: hasPos=%s tgt.z=%s my.z=%d (different floor?)",
                tostring(targetPos ~= nil), tostring(targetPos and targetPos.z), playerPos.z))
        end
    else
        afdbg(string.format("target NOT found by id/name (id=%s name=%s) -> PRIORITY2 lost-target path",
            tostring(autoFollowState.targetId), tostring(autoFollowState.targetName)))
    end
    
    -- ========================================================================
    -- TRANSIT REGIME: leader not visible (teleport / stairs / off-screen / far).
    -- Formation is impossible here, so we CATCH UP. Two authoritative signals from
    -- the SERVER drive this (never the leader's client):
    --   * getLeaderState() -> the leader's exact current position. Same floor => just
    --     step/pathfind straight to it.
    --   * the trail -> only to find the exact tile where the leader LEFT our floor (a
    --     teleport/stairs/ladder). We walk there and STEP (walk-on) or `use` (ladder).
    -- The follower NEVER gets teleported by the system -- it only walks and steps/uses,
    -- reproducing the leader.
    -- ========================================================================
    autoFollowState.targetLost = true
    autoFollowState.targetLostPos = autoFollowState.lastTargetPos

    local leaderPos = PathSharing and PathSharing.getLeaderState()
    if not leaderPos then
        autoFollowState.useTile = nil
        afdbg("transit: no leader state -> on-hold (waiting for stream)")
        return
    end

    -- Same floor: the leader is just off-screen / ahead -> catch up straight to it.
    if leaderPos.z == playerPos.z then
        autoFollowState.useTile = nil
        afdbg(string.format("transit: same-floor catch-up -> (%d,%d,%d)", leaderPos.x, leaderPos.y, leaderPos.z))
        if navStep(playerPos, leaderPos) then
            autoFollowState.lastStepTime = g_clock.millis()
        end
        return
    end

    -- Leader is on a DIFFERENT floor: find the tile where it LEFT our floor -- the
    -- NEWEST trail entry with our z -- and go change floor there.
    local tt, ttIndex = nil, nil
    if PathSharing then
        for i = PathSharing.getQueueSize(), 1, -1 do
            local e = PathSharing.peek(i)
            if e and e.z == playerPos.z then
                tt = e
                ttIndex = i
                break
            end
        end
    end
    if not tt then
        autoFollowState.useTile = nil
        afdbg("transit: leader on floor " .. tostring(leaderPos.z) .. ", no transition tile on our floor -> on-hold")
        return
    end
    -- The leader's ARRIVAL tile (first trail entry after it left our floor). A use item
    -- (ladder/rope) sits directly UNDER the arrival -- which can be a tile ADJACENT to
    -- where the leader stood (you can use a ladder from the side), so we must use it
    -- THERE, not necessarily under our own feet.
    local arr = ttIndex and PathSharing.peek(ttIndex + 1) or nil

    local d = getDistance(playerPos, tt)
    if d == 0 then
        -- USE transition (we reached the leader's departure tile without auto-changing
        -- floor => not walk-on). The transition item (ladder / rope spot) sits directly
        -- UNDER the arrival tile, which may be an ADJACENT SQM -- you can use a ladder
        -- from the side -- so target THAT tile, not necessarily the one under our feet.
        -- We're within use range of it (the leader was too). Escalate USE -> ROPE so
        -- both ladders and rope spots work without any server-side classification.
        local usePos = arr and { x = arr.x, y = arr.y, z = playerPos.z } or playerPos
        local function topThingAt(p)
            local tl = g_map.getTile(p)
            local th = tl and tl:getTopUseThing()
            if th and not th:isCreature() then return th end
            return nil
        end
        local thing = topThingAt(usePos) or topThingAt(playerPos)
        if not thing then
            autoFollowState.useTile = nil
            PathSharing.getNextDestination() -- nothing usable here (stale) -> drop it
            return
        end

        local now = g_clock.millis()
        if autoFollowState.useTile and isSamePosition(autoFollowState.useTile, playerPos) then
            -- Already acting on this tile: wait out the cooldown, then escalate use->rope,
            -- then give up (release the tile so we retry / eventually re-acquire on sight).
            if (now - (autoFollowState.useAt or 0)) < CONFIG.USE_COOLDOWN then
                return -- waiting for our floor to change
            end
            if autoFollowState.useStage == "use" then
                autoFollowState.useStage = "rope"
                autoFollowState.useAt = now
                for _, ropeId in ipairs(ROPE_IDS) do
                    if g_game.findPlayerItem(ropeId, -1) then
                        g_game.useInventoryItemWith(ropeId, thing)
                        return
                    end
                end
                afdbg("transit: use failed and no rope in inventory")
                return
            end
            autoFollowState.useTile = nil -- rope also failed -> release
            return
        end

        -- First contact: try USE (ladder). Escalates to rope next cooldown if no change.
        g_game.use(thing)
        autoFollowState.useTile = copyPosition(playerPos)
        autoFollowState.useAt = now
        autoFollowState.useStage = "use"
        autoFollowState.lastStepTime = now
        return
    end

    -- Walk toward the transition tile. If it's a walk-on teleport/stairs, stepping onto
    -- it changes our floor automatically (server-side); a ladder is `use`d on arrival.
    autoFollowState.useTile = nil
    if navStep(playerPos, tt) then
        autoFollowState.lastStepTime = g_clock.millis()
    end
    return
end

-- Event-driven re-step: the instant the char finishes a step, run doStep so the NEXT
-- step is issued right away instead of waiting up to STEP_INTERVAL for the next poll.
-- This closes the per-step polling gap; combined with pre-walk, follow keeps pace with
-- a moving target far more tightly. The polling loop stays as a fallback (re-acquires
-- when the target moves while we're standing adjacent, and drives the lost-target path).
local function onLocalWalkFinish()
    -- The step landed: clear the in-flight guard so the next one can be issued.
    autoFollowState.walkPending = false
    if not autoFollowState.enabled then return end
    doStep()
end

-- ============================================================================
-- ESC TO STOP
-- Follow is persistent: losing the target on screen no longer disables it (it
-- re-acquires when the target reappears). The ONLY way to stop, besides the
-- Enable checkbox, is pressing Esc. We bind Esc on the game root panel once the
-- first follow starts and keep it bound until terminate() -- the handler is a
-- no-op while disabled, so re-enabling reuses the same bind and we never
-- unbind from inside the key callback (which would mutate the list mid-dispatch).
-- The bind is additive: game_interface / helper Esc handlers keep working.
-- ============================================================================
local escBound = false
local deathHooked = false

local function onEscapeKey()
    if not autoFollowState.enabled then return end
    AutoFollow.toggle(false)
    AutoFollow.updateUI()
    if modules.game_textmessage then
        modules.game_textmessage.displayGameMessage("Auto Follow disabled (Esc)")
    end
end

-- Anti-exploit: dying MUST drop the follow, and unlike the Magic Shooter / Auto Target
-- toggles (which the player owns and we deliberately leave on through death, see
-- game_playerdeath), we do NOT re-enable it on respawn. A dead follower that kept its
-- follow armed would auto-rejoin the leader straight out of the temple with zero
-- effort -- exactly the exploit we're closing. Staying off until the player turns it
-- back on by hand is the point. Fires on g_game.onDeath (Game::processDeath), hooked
-- once in AutoFollow.init() and unhooked in AutoFollow.terminate().
local function onPlayerDeath()
    if not autoFollowState.enabled then return end
    AutoFollow.toggle(false)
    AutoFollow.updateUI()
    if modules.game_textmessage then
        modules.game_textmessage.displayGameMessage("Auto Follow disabled (you died)")
    end
end

local function ensureEscBound()
    if escBound then return end
    local rootPanel = modules.game_interface and modules.game_interface.getRootPanel and
        modules.game_interface.getRootPanel()
    if not rootPanel then return end
    g_keyboard.bindKeyDown("Escape", onEscapeKey, rootPanel)
    escBound = true
end

local function unbindEsc()
    if not escBound then return end
    local rootPanel = modules.game_interface and modules.game_interface.getRootPanel and
        modules.game_interface.getRootPanel()
    if rootPanel then
        g_keyboard.unbindKeyDown("Escape", rootPanel, onEscapeKey)
    end
    escBound = false
end

local function startFollow()
    if autoFollowState.followEvent then
        removeEvent(autoFollowState.followEvent)
    end

    -- Esc disables the (now persistent) follow; bind lazily on first start.
    ensureEscBound()

    -- Chain steps on walk completion. disconnect-first keeps it single even if
    -- startFollow runs twice; connect is additive, so game_walking's own onWalkFinish
    -- handler keeps working alongside ours.
    disconnect(LocalPlayer, { onWalkFinish = onLocalWalkFinish })
    connect(LocalPlayer, { onWalkFinish = onLocalWalkFinish })

    local function loop()
        if not autoFollowState.enabled then return end

        doStep()

        autoFollowState.followEvent = scheduleEvent(loop, CONFIG.STEP_INTERVAL)
    end

    loop()
end

local function stopFollow()
    disconnect(LocalPlayer, { onWalkFinish = onLocalWalkFinish })
    if autoFollowState.followEvent then
        removeEvent(autoFollowState.followEvent)
        autoFollowState.followEvent = nil
    end
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

function AutoFollow.setTarget(creature)
    if not creature or creature:isLocalPlayer() then return false end

    autoFollowState.targetName = creature:getName()
    autoFollowState.targetId = creature:getId()
    autoFollowState.lastTargetPos = copyPosition(creature:getPosition())
    clearQueue()

    g_logger.info(string.format("[AutoFollow] setTarget name=%s id=%s STATE=%s enabled=%s",
        tostring(autoFollowState.targetName), tostring(autoFollowState.targetId),
        tostring(autoFollowState), tostring(autoFollowState.enabled)))

    -- Update UI (label + checkbox sync)
    AutoFollow.updateUI()

    -- If Auto Follow is ALREADY enabled but wasn't actually following, start now.
    -- This happens when the Enable checkbox is "on" before a target exists -- e.g.
    -- it gets restored checked on login, firing toggle(true) with targetName=nil
    -- (which sets enabled=true but starts no loops). The checkbox then stays checked,
    -- so toggle never fires again; picking a target here must kick off the follow.
    -- Re-running toggle(true) starts monitor/follow (start* removeEvent first, so
    -- re-calling while already following is safe on target change).
    if autoFollowState.enabled then
        g_logger.info("[AutoFollow] setTarget: already enabled -> starting follow via toggle(true)")
        AutoFollow.toggle(true)
    end

    return true
end

function AutoFollow.clearTarget()
    g_logger.info(string.format("[AutoFollow] clearTarget() CALLED STATE=%s (was name=%s)",
        tostring(autoFollowState), tostring(autoFollowState.targetName)))
    autoFollowState.targetName = nil
    autoFollowState.targetId = nil
    autoFollowState.lastTargetPos = nil
    clearQueue()

    -- Update UI
    AutoFollow.updateUI()
end

function AutoFollow.toggle(enabled)
    g_logger.info(string.format("[AutoFollow] toggle(%s) ENTRY: targetName=%s STATE=%s",
        tostring(enabled), tostring(autoFollowState.targetName), tostring(autoFollowState)))
    -- Block enabling only in a hard no-follow context (e.g. expedition)
    if enabled then
        local blocked, reason = isAutoFollowBlocked()
        if blocked then
            autoFollowState.enabled = false
            if modules.game_textmessage then
                modules.game_textmessage.displayGameMessage("Auto Follow blocked: " .. (reason or "blocked"))
            end
            return
        end
    end

    autoFollowState.enabled = enabled

    if enabled then
        if autoFollowState.targetName then
            -- Initialize last position
            local target = getCreatureByName(autoFollowState.targetName)
            if target then
                autoFollowState.targetId = target:getId()
                autoFollowState.lastTargetPos = copyPosition(target:getPosition())
            end

            -- Try to connect via PathSharing for cross-floor following
            if autoFollowState.usePathSharing then
                connectToLeader(autoFollowState.targetName)
            end

            startMonitor()
            startFollow()
            g_logger.info(string.format("[AutoFollow] ENABLED: targetName=%s targetId=%s foundOnScreen=%s -> monitor+follow started",
                tostring(autoFollowState.targetName), tostring(autoFollowState.targetId), tostring(target ~= nil)))
        else
            g_logger.info("[AutoFollow] toggle(true) but NO targetName set -> nothing to follow")
        end
    else
        -- Disconnect from PathSharing
        disconnectFromLeader()

        stopMonitor()
        stopFollow()
        clearQueue()
    end
end

function AutoFollow.isEnabled()
    return autoFollowState.enabled
end

function AutoFollow.isUpdatingUI()
    return autoFollowState.updatingUI
end

function AutoFollow.getTargetName()
    return autoFollowState.targetName
end

function AutoFollow.getQueueSize()
    return #autoFollowState.pathQueue
end

-- Positioning settings. Both persist to g_settings so they survive a relog and
-- match the UI comboboxes (whose @onSetup reads the same keys). Changes take
-- effect on the next doStep -- no need for an active target.
function AutoFollow.getDistance()
    return autoFollowState.followDistance or 1
end

function AutoFollow.setDistance(distance)
    distance = tonumber(distance)
    if not distance then return end
    distance = math.floor(distance)
    if distance < 1 then distance = 1 elseif distance > 5 then distance = 5 end
    autoFollowState.followDistance = distance
    g_settings.set(SETTINGS_DISTANCE, distance)
    g_settings.save()
end

function AutoFollow.getStyle()
    return autoFollowState.followStyle or "Normal"
end

function AutoFollow.setStyle(style)
    if type(style) ~= "string" or not VALID_STYLES[style] then return end
    autoFollowState.followStyle = style
    g_settings.set(SETTINGS_STYLE, style)
    g_settings.save()
end

function AutoFollow.isPathSharingEnabled()
    return autoFollowState.usePathSharing
end

function AutoFollow.setPathSharingEnabled(enabled)
    autoFollowState.usePathSharing = enabled
    
    if not enabled and autoFollowState.pathSharingConnected then
        disconnectFromLeader()
    elseif enabled and autoFollowState.enabled and autoFollowState.targetName then
        connectToLeader(autoFollowState.targetName)
    end
end

function AutoFollow.isPathSharingConnected()
    return autoFollowState.pathSharingConnected
end

-- Get PathSharing module for direct access
function AutoFollow.getPathSharing()
    return initPathSharing()
end

-- One-time wiring (called by the helper right after the module is dofile'd). Hooks the
-- death event so follow drops on death. Idempotent: the guard keeps a single live
-- connection even if init runs twice, and terminate() unhooks it.
function AutoFollow.init()
    if not deathHooked then
        connect(g_game, { onDeath = onPlayerDeath })
        deathHooked = true
    end
end

function AutoFollow.updateUI()
    if not modules.game_helper or not modules.game_helper.getToolsPanel then return end

    local tPanel = modules.game_helper.getToolsPanel()
    if not tPanel then return end

    -- Find autoFollowContent in the new structure (SpyFollowPanel > AutoFollowPanel > autoFollowContent)
    local targetNameLabel = nil
    local enableCheckbox = nil

    -- Try to find recursively from parent
    local parent = tPanel:getParent()
    if parent then
        targetNameLabel = parent:recursiveGetChildById("autoFollowTargetName")
        enableCheckbox = parent:recursiveGetChildById("enableAutoFollow")
    end

    if not targetNameLabel then
        targetNameLabel = tPanel:recursiveGetChildById("autoFollowTargetName")
    end
    if not enableCheckbox then
        enableCheckbox = tPanel:recursiveGetChildById("enableAutoFollow")
    end

    if targetNameLabel then
        if autoFollowState.targetName then
            targetNameLabel:setText(autoFollowState.targetName)
            targetNameLabel:setColor("#00ff00")
        else
            targetNameLabel:setText("None")
            targetNameLabel:setColor("#ff6666")
        end
    end

    -- Sync checkbox with actual state (guard to prevent cascade from onCheckChange)
    if enableCheckbox then
        autoFollowState.updatingUI = true
        enableCheckbox:setChecked(autoFollowState.enabled)
        autoFollowState.updatingUI = false
    end
end

function AutoFollow.terminate()
    g_logger.info("[AutoFollow] terminate() CALLED STATE=" .. tostring(autoFollowState))
    -- Disconnect from PathSharing
    disconnectFromLeader()

    -- Terminate PathSharing module
    if PathSharing then
        PathSharing.terminate()
        PathSharing = nil
    end

    stopMonitor()
    stopFollow()
    unbindEsc()

    -- Unhook the death event (mirrors AutoFollow.init); keeps hot-reload clean.
    if deathHooked then
        disconnect(g_game, { onDeath = onPlayerDeath })
        deathHooked = false
    end

    autoFollowState = {
        enabled = false,
        targetName = nil,
        targetId = nil,
        lastTargetPos = nil,
        pathQueue = {},
        followEvent = nil,
        monitorEvent = nil,
        isMoving = false,
        lastStepTime = 0,
        walkPending = false,
        walkPendingAt = 0,
        walkPendingPos = nil,
        navDest = nil,
        navLastPos = nil,
        navProgressAt = 0,
        targetLost = false,
        targetLostPos = nil,
        usePathSharing = true,
        pathSharingConnected = false,
        updatingUI = false,
        followDistance = loadFollowDistance(),
        followStyle = loadFollowStyle()
    }
end

return AutoFollow
