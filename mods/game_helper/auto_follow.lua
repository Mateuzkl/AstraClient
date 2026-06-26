-- Auto Follow Module
-- Follows a player by memorizing and replicating their exact path
-- Enhanced with PathSharing for cross-floor/teleport following between OTC clients

local AutoFollow = {}

-- Path Sharing Module (for cross-floor following)
local PathSharing = nil

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
    targetLost = false,       -- True when target disappeared from screen
    targetLostPos = nil,      -- Last known position when target was lost
    usePathSharing = true,    -- Enable cross-floor following via opcode 220
    pathSharingConnected = false, -- True when connected to leader via PathSharing
    updatingUI = false,           -- Guard flag to prevent cascade from checkbox onChange

    -- Auto-cancel countdown (5-10 min lifetime, resettable by boss presence)
    countdownEndTime = 0,         -- g_clock.seconds() when follow will auto-cancel
    countdownTickEvent = nil,     -- Repeating 1s event driving the UI tick + reset check
    lastResetCheckTime = 0        -- Last time we evaluated the boss-reset condition
}

-- Configuration
local CONFIG = {
    MONITOR_INTERVAL = 25,    -- ms - how often to check target position (fast!)
    STEP_INTERVAL = 50,       -- ms - time between our steps
    MAX_QUEUE_SIZE = 20,      -- Max positions to remember
    KEEP_DISTANCE = 1,        -- Always stay 1 position behind target
    PATH_SHARING_PRIORITY = true, -- Prioritize paths from PathSharing over visual monitoring

    -- Auto-cancel countdown
    COUNTDOWN_MIN = 5 * 60,       -- seconds (5 min lower bound)
    COUNTDOWN_MAX = 10 * 60,      -- seconds (10 min upper bound)
    RESET_CHECK_INTERVAL = 30,    -- seconds between boss-reset eligibility checks
    COUNTDOWN_TICK_MS = 1000      -- ms between ticks
}


-- Check if auto follow should be blocked (expedition or PVP battle)
local function isAutoFollowBlocked()
    -- Check if player is in a fight (PVP/battle situation).
    -- Astra's PlayerStates table (gamelib/player.lua) has no RedSwords field; it
    -- exposes Swords=128 (the in-fight battle-sign icon), the closest equivalent
    -- to Amon's RedSwords PVP indicator. The astra_compat shim aliases
    -- PlayerStates.RedSwords -> Swords, but guard the flag with `or 0` here too so
    -- a nil flag never reaches bit.band: Astra's bit32.band (lbitlib
    -- luaL_checkunsigned) RAISES 'number expected, got nil' on a nil arg, which
    -- would abort this follow-loop tick before it reschedules and silently kill
    -- auto-follow regardless of shim load order.
    local player = g_game.getLocalPlayer()
    if player and player.getStates and PlayerStates then
        local states = player:getStates()
        local swordsFlag = PlayerStates.RedSwords or PlayerStates.Swords or 0
        if states and bit.band(states, swordsFlag) ~= 0 then
            return true, "PVP battle"
        end
    end

    -- Check if inside expedition
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

-- Populate the table
addId(166) addId(167) addId(293) addId(294)
addRange(369, 370) addId(385) addId(394)
addRange(411, 414) addId(428) addId(432) addId(433) addId(434)
addRange(437, 438) addId(469) addId(476)
addRange(482, 485) addId(516)
addRange(566, 567) addId(594) addId(595)
addRange(600, 601) addRange(604, 605) addId(607) addId(609) addId(610) addId(615) addId(628)
addId(775) addId(855) addId(856) addId(859) addId(868) addId(874) addId(877) addId(878)
addId(1066) addId(1067) addId(1080) addId(1156)
addRange(1756, 1758) addRange(1761, 1763)
addId(1947) addId(1949) addId(1950) addId(1952) addId(1954) addId(1956)
addId(1958) addId(1959) addId(1960) addId(1962) addId(1964) addId(1966)
addId(1969) addId(1971) addId(1973) addId(1975) addId(1977) addId(1978)
addId(2192) addId(2194) addId(2196) addId(2198)
addRange(4823, 4826) addRange(5022, 5023)
addId(5033) addId(5035) addId(5037) addId(5039) addId(5081)
addId(5257) addId(5258) addId(5259) addId(5544) addId(5691) addId(5731) addId(5756) addId(5763)
addRange(6127, 6130) addRange(6172, 6173) addRange(6754, 6756)
addId(6909) addId(6911) addId(6913) addId(6915) addRange(6917, 6924)
addId(7053) addRange(7181, 7182) addRange(7476, 7479) addRange(7515, 7522)
addId(7542) addId(7544) addId(7546) addId(7548)
addRange(7729, 7737) addId(7755) addRange(7767, 7768)
addId(7881) addId(7887) addId(7888) addId(8144) addId(8193)
addId(8657) addId(8658) addId(8690) addId(8709) addId(8830) addId(8831) addId(8932)
addId(10206) addId(11365) addId(11552) addRange(11553, 11554) addId(11707) addId(11709)
addId(12203) addId(12236) addId(12796) addId(12799) addId(12961)
addId(13341) addId(13342)
addId(13559) addId(13561) addId(13564) addId(13567) addId(13570) addId(13573)
addId(13576) addId(13579) addId(13582) addId(13585) addId(13588) addId(13591)
addId(13716) addId(13718) addId(13720) addId(13722)
addRange(14133, 14135)
addId(14932) addId(14934) addId(14936) addId(14938)
addId(15108) addId(15110) addId(15112) addId(15114) addId(15144) addRange(15145, 15146) addId(15320)
addRange(16265, 16272)
addId(16680) addId(16682) addId(16684) addId(16686) addId(16688) addId(16690) addId(16692) addId(16694)
addRange(16696, 16703) addRange(16785, 16792)
addId(17230) addId(17239) addId(17394) addId(17395)
addRange(18642, 18656)
addId(19143) addId(19220) addId(19243) addId(19590) addId(19591)
addId(20124) addRange(20142, 20143) addId(20224) addId(20225)
addRange(20253, 20256) addRange(20259, 20263) addRange(20328, 20336) addId(20344)
addRange(20469, 20473) addRange(20488, 20496)
addId(20750) addId(20751) addId(20753) addId(20755)
addId(21034) addId(21342) addId(21344)
addId(21564) addId(21566) addId(21568) addId(21570)
addId(21739) addId(21740) addId(21741) addId(21743)
addId(21971) addId(21972) addId(21973) addId(22106) addId(22156) addId(22157)
addId(22517) addId(22565) addId(22566) addId(22747) addId(22748) addId(22749) addId(22761)
addId(23364) addRange(23482, 23484)
addId(23858) addId(23860) addId(23862) addId(23864)
addId(24806) addId(24808) addId(24810) addId(24812)
addId(25016) addId(25018) addId(25020) addId(25022)
addRange(25047, 25058)
addRange(27589, 27590) addId(27628) addId(27629) addId(27658)
addId(28357) addId(28359) addId(28361) addId(28363) addId(28655) addRange(28672, 28673)
addId(29109) addId(29111) addId(29113) addId(29115)
addId(29137) addId(29139) addId(29141) addId(29143) addId(29979) addId(29980)
addRange(30452, 30453)
addId(30757) addId(30759) addId(30761) addId(30763)
addId(30820) addId(30822) addId(30824) addId(30826)
addId(30904) addId(30906) addId(30908) addId(30910) addId(30912) addId(30914) addId(30916) addId(30918)
addId(31129) addId(31130) addId(31168) addId(31907) addId(32020) addId(32979)
addRange(33004, 33007)
addId(33175) addId(33177) addId(33179) addId(33181)
addId(33204) addId(33206) addId(33208) addId(33210)
addId(33233) addId(33235) addId(33237) addId(33239)
addId(33256) addId(33258) addId(33260) addId(33262)
addId(33709) addId(34111) addId(34165) addId(34166) addId(34255) addId(35502)
addId(36444) addId(36446) addId(36448) addId(36450) addId(36973) addId(37000) addId(37001) addId(37065)
addId(37964) addId(37966) addId(37968) addId(37970)
addRange(38831, 38832)
addId(39721) addId(39722) addId(39919) addId(39921) addId(39923) addId(39925)
addId(40262) addId(40263) addId(40279) addId(40281) addId(40296) addId(40298) addId(40302)
addId(40428) addId(40430) addId(40432) addId(40434)
addId(42391) addId(42393) addId(42395) addId(42397)
addId(42619) addId(42621) addId(42623) addId(42632)
addId(42965) addId(42967) addId(42969) addId(42971)
addId(43130) addId(43132) addId(43134) addId(43372)
addId(44896) addId(44898) addId(44900) addId(44902)
addId(44942) addId(44943) addId(44946) addId(44948)
addId(45154) addId(45156) addId(45158) addId(45160)
addId(45395) addId(45397) addId(45399) addId(45401)
addId(49161) addId(49657) addId(49659) addId(49661) addId(49663)
addRange(49776, 49783) addId(49937) addId(49939) addId(49941) addId(49943)
addRange(50069, 50072) addRange(50082, 50085) addId(50121)
addId(50547) addId(50551) addId(50553) addId(50555) addId(50613) addId(51313) addId(51366)
addRange(60619, 60638)

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
        
        PathSharing.onPathReceived = function(destPos)
            -- Add destination to queue with type info
            if destPos then
                local pos = {x = destPos.x, y = destPos.y, z = destPos.z}
                pos._fromPathSharing = true
                pos._type = destPos.type or "walk"  -- "node" for teleport/stairs, "walk" for normal
                addToQueue(pos)
                -- g_logger.info(string.format("[AutoFollow] Received via PathSharing: (%d,%d,%d) type=%s", 
                --     pos.x, pos.y, pos.z, pos._type))
            end
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

local function getCreatureByName(name)
    if not name then return nil end
    local player = g_game.getLocalPlayer()
    if not player then return nil end
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
-- WALKING HELPER - Same method as CaveBot
-- ============================================================================

local function walkTo(dest)
    if not dest then return false end
    if type(dest.x) ~= "number" or type(dest.y) ~= "number" or type(dest.z) ~= "number" then
        return false
    end
    
    local player = g_game.getLocalPlayer()
    if not player then return false end
    
    -- Use player:autoWalk if available (preferred)
    if player.autoWalk then
        player:autoWalk(dest)
        return true
    end
    
    -- Fallback to g_game.autoWalk
    if g_game.autoWalk then
        g_game.autoWalk(dest)
        return true
    end
    
    return false
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

-- Check if position is walkable
local function isWalkable(pos)
    if not pos or not pos.x or not pos.y or not pos.z then return false end
    local tile = g_map.getTile(pos)
    if not tile then return false end
    return tile:isWalkable()
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

local function doStep()
    if not autoFollowState.enabled then return end
    
    -- Force disable if in expedition or PVP battle
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
    if not autoFollowState.targetName then return end

    local player = g_game.getLocalPlayer()
    if not player then return end

    -- Don't interrupt if already walking
    if player:isWalking() then return end

    local playerPos = player:getPosition()
    if not playerPos or not playerPos.x then return end

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
            -- Target is visible and on same floor!
            autoFollowState.targetLost = false
            
            -- Clear PathSharing queue - we don't need it when target is visible
            if PathSharing and PathSharing.clearQueue then
                PathSharing.clearQueue()
            end
            clearQueue()
            
            local dist = getDistance(playerPos, targetPos)
            
            if dist <= 1 then
                -- Already adjacent, we're good
                return
            end
            
            -- Find best position around target (prefer behind)
            local destPos = getBestPositionAroundTarget(target, playerPos)
            if destPos then
                if dist <= 2 then
                    -- Close - walk directly
                    local dir = getDirectionTo(playerPos, destPos)
                    if dir then
                        g_game.walk(dir)
                        autoFollowState.lastStepTime = g_clock.millis()
                    end
                else
                    -- Far - use walkTo
                    if walkTo(destPos) then
                        autoFollowState.lastStepTime = g_clock.millis()
                    end
                end
                return
            end
            
            -- Fallback: walk towards target position directly
            if walkTo(targetPos) then
                autoFollowState.lastStepTime = g_clock.millis()
            end
            return
        end
    end
    
    -- ========================================================================
    -- PRIORITY 2: Target NOT visible - use PathSharing to find them
    -- ========================================================================
    autoFollowState.targetLost = true
    autoFollowState.targetLostPos = autoFollowState.lastTargetPos
    
    -- Check PathSharing queue for nodes (teleports/stairs to use)
    if PathSharing and PathSharing.getQueueSize and PathSharing.getQueueSize() > 0 then
        local nextDest = PathSharing.peekNextDestination()
        if nextDest and nextDest.x and nextDest.y and nextDest.z then
            local dest = {x = nextDest.x, y = nextDest.y, z = nextDest.z}
            local posType = nextDest.type or "node"
            local dist = getDistance(playerPos, dest)
            
            -- g_logger.info(string.format("[AutoFollow] Target lost! Using PathSharing: (%d,%d,%d) type=%s", 
            --     dest.x, dest.y, dest.z, posType))
            
            -- NODE: Must go exactly there and USE
            if posType == "node" then
                if playerPos.z == dest.z then
                    if dist == 0 then
                        -- At position - USE the item
                        local tile = g_map.getTile(playerPos)
                        if tile then
                            local topUse = tile:getTopUseThing()
                            if topUse and not topUse:isCreature() then
                                -- g_logger.info("[AutoFollow] Using floor change item")
                                g_game.use(topUse)
                                autoFollowState.lastStepTime = g_clock.millis()
                                PathSharing.getNextDestination()  -- Remove from queue
                                return
                            end
                        end
                        PathSharing.getNextDestination()  -- Nothing to use, skip
                        return
                    else
                        -- Walk to node position
                        if walkTo(dest) then
                            autoFollowState.lastStepTime = g_clock.millis()
                        end
                        return
                    end
                else
                    -- Different floor - walk to x,y on our floor
                    local sameLevelDest = {x = dest.x, y = dest.y, z = playerPos.z}
                    if getDistance(playerPos, sameLevelDest) > 0 then
                        if walkTo(sameLevelDest) then
                            autoFollowState.lastStepTime = g_clock.millis()
                        end
                    else
                        -- At x,y, use floor change
                        local tile = g_map.getTile(playerPos)
                        if tile then
                            local topUse = tile:getTopUseThing()
                            if topUse and not topUse:isCreature() then
                                g_game.use(topUse)
                                autoFollowState.lastStepTime = g_clock.millis()
                                PathSharing.getNextDestination()
                            else
                                -- No item to use, skip this node
                                PathSharing.getNextDestination()
                            end
                        else
                            PathSharing.getNextDestination()
                        end
                    end
                    return
                end
            
            -- WALK: Just go near there (shouldn't happen anymore, but handle it)
            else
                PathSharing.getNextDestination()  -- Skip WALK types
                return
            end
        else
            -- Invalid destination, remove it
            if PathSharing.getNextDestination then
                PathSharing.getNextDestination()
            end
        end
    end
    
    -- ========================================================================
    -- PRIORITY 3: No PathSharing data - use old queue logic
    -- ========================================================================
    
    -- Optimize queue based on current position
    optimizeQueue(playerPos)

    -- Get next position from queue
    local nextPos = getNextFromQueue()

    -- If queue is empty and target is lost, search for teleport around TARGET's last position
    if not nextPos and autoFollowState.targetLost and autoFollowState.targetLostPos then
        -- Search around the target's last known position, not around the player
        local searchPos = autoFollowState.targetLostPos
        
        -- Make sure searchPos is valid
        if not searchPos or not searchPos.x or not searchPos.y or not searchPos.z then
            return
        end

        -- Only search on the same floor as the target was
        if searchPos.z == playerPos.z then
            local teleport, teleportPos = findNearestTeleport(searchPos, 5)
            if teleport and teleportPos then
                local dist = getDistance(playerPos, teleportPos)

                if dist == 0 then
                    -- We're on the teleport, use it
                    g_game.use(teleport)
                    autoFollowState.lastStepTime = g_clock.millis()
                    return
                elseif dist == 1 then
                    -- Adjacent to teleport, walk onto it (for walk-on teleports)
                    local dir = getDirectionTo(playerPos, teleportPos)
                    if dir then
                        g_game.walk(dir)
                        autoFollowState.lastStepTime = g_clock.millis()
                    end
                    return
                else
                    -- Walk towards the teleport position
                    local dir = getDirectionTo(playerPos, teleportPos)
                    if dir then
                        g_game.walk(dir)
                        autoFollowState.lastStepTime = g_clock.millis()
                    end
                    return
                end
            end
        else
            -- Target was on a different floor, we need to find floor change on OUR floor
            -- that leads to where the target went
            local targetTilePos = {x = searchPos.x, y = searchPos.y, z = playerPos.z}
            local dist = getDistance(playerPos, targetTilePos)

            if dist == 0 then
                -- We're at the target's x,y, try to use whatever is here
                local tile = g_map.getTile(playerPos)
                if tile then
                    local topUseThing = tile:getTopUseThing()
                    if topUseThing and not topUseThing:isCreature() then
                        g_game.use(topUseThing)
                        autoFollowState.lastStepTime = g_clock.millis()
                    end
                end
                return
            else
                -- Walk towards where the target was (x,y on our floor)
                local dir = getDirectionTo(playerPos, targetTilePos)
                if dir then
                    g_game.walk(dir)
                    autoFollowState.lastStepTime = g_clock.millis()
                end
                return
            end
        end
        return
    end

    if not nextPos then return end

    -- Check if we're already at this position
    if isSamePosition(playerPos, nextPos) then
        removeFromQueue()
        return
    end

    -- ========================================================================
    -- PATHSHARING HANDLING
    -- type="node": Must walk EXACTLY there (teleport/stairs position)
    -- type="walk": Can walk near (normal walking)
    -- ========================================================================
    if nextPos._fromPathSharing then
        local dest = {x = nextPos.x, y = nextPos.y, z = nextPos.z}
        local posType = nextPos._type or "walk"
        local dist = getDistance(playerPos, dest)
        
        g_logger.info(string.format("[AutoFollow:PS] Processing: dest=(%d,%d,%d) type=%s dist=%d myPos=(%d,%d,%d) queue=%d",
            dest.x, dest.y, dest.z, posType, dist, playerPos.x, playerPos.y, playerPos.z, #autoFollowState.pathQueue))
        
        -- NODE type: Must reach exact position (for teleports/stairs)
        if posType == "node" then
            if playerPos.z == dest.z then
                -- Same floor
                if dist == 0 then
                    -- We're at the exact position - USE the item here
                    g_logger.info("[AutoFollow:PS] NODE: At position, trying to USE item")
                    local tile = g_map.getTile(playerPos)
                    if tile then
                        -- Try items first
                        local items = tile:getItems()
                        if items then
                            for _, item in ipairs(items) do
                                local id = item:getId()
                                if floorChangeOrTeleports[id] then
                                    g_logger.info(string.format("[AutoFollow:PS] NODE: Using floor change item id=%d", id))
                                    g_game.use(item)
                                    autoFollowState.lastStepTime = g_clock.millis()
                                    removeFromQueue()
                                    return
                                end
                            end
                        end
                        -- Try ground
                        local ground = tile:getGround()
                        if ground and floorChangeOrTeleports[ground:getId()] then
                            g_logger.info(string.format("[AutoFollow:PS] NODE: Using ground id=%d", ground:getId()))
                            g_game.use(ground)
                            autoFollowState.lastStepTime = g_clock.millis()
                            removeFromQueue()
                            return
                        end
                        -- Try topUseThing
                        local topUse = tile:getTopUseThing()
                        if topUse and not topUse:isCreature() then
                            local useId = topUse.getId and topUse:getId() or 0
                            g_logger.info(string.format("[AutoFollow:PS] NODE: Using topUseThing id=%d", useId))
                            g_game.use(topUse)
                            autoFollowState.lastStepTime = g_clock.millis()
                            removeFromQueue()
                            return
                        end
                        g_logger.info("[AutoFollow:PS] NODE: No usable item found at position!")
                    end
                    -- Nothing to use, move on
                    removeFromQueue()
                    return
                elseif dist == 1 then
                    -- Adjacent - walk directly onto it
                    g_logger.info("[AutoFollow:PS] NODE: Adjacent, walking onto it")
                    local dir = getDirectionTo(playerPos, dest)
                    if dir then
                        g_game.walk(dir)
                        autoFollowState.lastStepTime = g_clock.millis()
                    end
                    return
                else
                    -- Far away - use walkTo
                    g_logger.info(string.format("[AutoFollow:PS] NODE: Far away (dist=%d), walkTo", dist))
                    if walkTo(dest) then
                        autoFollowState.lastStepTime = g_clock.millis()
                    end
                    return
                end
            else
                -- Different floor - need to go to that x,y on our floor first
                local sameLevelDest = {x = dest.x, y = dest.y, z = playerPos.z}
                local distToXY = getDistance(playerPos, sameLevelDest)
                
                g_logger.info(string.format("[AutoFollow:PS] NODE: Different floor! dest.z=%d my.z=%d distToXY=%d", 
                    dest.z, playerPos.z, distToXY))
                
                if distToXY > 0 then
                    g_logger.info("[AutoFollow:PS] NODE: Walking to x,y on my floor first")
                    if walkTo(sameLevelDest) then
                        autoFollowState.lastStepTime = g_clock.millis()
                    end
                    return
                else
                    -- At x,y, use floor change
                    g_logger.info("[AutoFollow:PS] NODE: At x,y, trying floor change")
                    local tile = g_map.getTile(playerPos)
                    if tile then
                        local topUse = tile:getTopUseThing()
                        if topUse and not topUse:isCreature() then
                            g_logger.info("[AutoFollow:PS] NODE: Using topUseThing for floor change")
                            g_game.use(topUse)
                            autoFollowState.lastStepTime = g_clock.millis()
                            removeFromQueue()
                            return
                        else
                            g_logger.info("[AutoFollow:PS] NODE: No topUseThing for floor change!")
                        end
                    end
                    removeFromQueue()
                    return
                end
            end
        
        -- WALK type: Can walk near (normal navigation)
        else
            if playerPos.z == dest.z then
                -- Same floor - look ahead for NODE or better destination
                
                -- Find the best destination to walk to (skip intermediate WALKs)
                local bestDest = dest
                local skipped = 0
                for i = 2, #autoFollowState.pathQueue do
                    local nextPos = autoFollowState.pathQueue[i]
                    if not nextPos._fromPathSharing then break end
                    if nextPos.z ~= playerPos.z then break end  -- Different floor
                    if nextPos._type == "node" then
                        -- Walk to the NODE instead
                        bestDest = {x = nextPos.x, y = nextPos.y, z = nextPos.z}
                        break
                    end
                    -- It's another WALK on same floor - skip current and target this one
                    bestDest = {x = nextPos.x, y = nextPos.y, z = nextPos.z}
                    skipped = i - 1
                end
                
                -- Remove skipped WALKs
                if skipped > 0 then
                    g_logger.info(string.format("[AutoFollow:PS] WALK: Skipping %d intermediate WALKs", skipped))
                    for _ = 1, skipped do
                        table.remove(autoFollowState.pathQueue, 1)
                    end
                end
                
                local distToBest = getDistance(playerPos, bestDest)
                if distToBest <= 1 then
                    g_logger.info("[AutoFollow:PS] WALK: Close enough, next waypoint")
                    removeFromQueue()
                    return
                end
                
                g_logger.info(string.format("[AutoFollow:PS] WALK: walkTo (%d,%d,%d) dist=%d", 
                    bestDest.x, bestDest.y, bestDest.z, distToBest))
                if walkTo(bestDest) then
                    autoFollowState.lastStepTime = g_clock.millis()
                end
                removeFromQueue()
                return
            else
                -- Different floor - shouldn't happen for walk type, but handle it
                removeFromQueue()
                return
            end
        end
    end

    -- Same floor - walk towards it
    if playerPos.z == nextPos.z then
        local dist = getDistance(playerPos, nextPos)

        if dist == 0 then
            -- We're at the exact position, but target might have teleported FROM here
            -- Check if this tile has a teleport and we should use it (target is on different floor now or lost)
            if autoFollowState.targetLost then
                local tile = g_map.getTile(playerPos)
                if tile then
                    -- Try to find and use any teleport/floor change item
                    local items = tile:getItems()
                    if items then
                        for _, item in ipairs(items) do
                            local id = item:getId()
                            if floorChangeOrTeleports[id] then
                                g_game.use(item)
                                autoFollowState.lastStepTime = g_clock.millis()
                                removeFromQueue()
                                return
                            end
                        end
                    end
                    -- Try ground
                    local ground = tile:getGround()
                    if ground and floorChangeOrTeleports[ground:getId()] then
                        g_game.use(ground)
                        autoFollowState.lastStepTime = g_clock.millis()
                        removeFromQueue()
                        return
                    end
                    -- Try topUseThing
                    local topUse = tile:getTopUseThing()
                    if topUse and not topUse:isCreature() then
                        g_game.use(topUse)
                        autoFollowState.lastStepTime = g_clock.millis()
                    end
                end
            end
            removeFromQueue()

        elseif dist == 1 then
            -- Adjacent tile - walk directly
            local dir = getDirectionTo(playerPos, nextPos)
            if dir then
                g_game.walk(dir)
                removeFromQueue()
                autoFollowState.lastStepTime = g_clock.millis()
            end
        elseif dist > 1 then
            -- Not adjacent - walk towards it step by step
            local dir = getDirectionTo(playerPos, nextPos)
            if dir then
                g_game.walk(dir)
                autoFollowState.lastStepTime = g_clock.millis()
            end
        end
    else
        -- Different floor - the target used stairs/teleport/wagon
        -- Walk to the x,y position on our floor
        local targetTilePos = {x = nextPos.x, y = nextPos.y, z = playerPos.z}
        local dist = getDistance(playerPos, targetTilePos)

        if dist == 0 then
            -- We're on the tile but wrong floor
            -- Try to use floor change items aggressively
            local tile = g_map.getTile(playerPos)
            if tile then
                -- First try items from our floorChangeOrTeleports list
                local items = tile:getItems()
                if items then
                    for _, item in ipairs(items) do
                        local id = item:getId()
                        if floorChangeOrTeleports[id] then
                            g_game.use(item)
                            autoFollowState.lastStepTime = g_clock.millis()
                            return -- DON'T remove from queue yet - wait for floor change
                        end
                    end
                end
                -- Try ground
                local ground = tile:getGround()
                if ground and floorChangeOrTeleports[ground:getId()] then
                    g_game.use(ground)
                    autoFollowState.lastStepTime = g_clock.millis()
                    return
                end
                -- Try topUseThing as fallback
                local topUseThing = tile:getTopUseThing()
                if topUseThing and not topUseThing:isCreature() then
                    g_game.use(topUseThing)
                    autoFollowState.lastStepTime = g_clock.millis()
                    return
                end
            end
            -- If we couldn't use anything, remove from queue to avoid stuck
            removeFromQueue()

        elseif dist == 1 then
            -- Adjacent to the floor change tile
            -- WALK onto it (for walk-on teleports/stairs)
            local dir = getDirectionTo(playerPos, targetTilePos)
            if dir then
                g_game.walk(dir)
                autoFollowState.lastStepTime = g_clock.millis()
            end
            -- Don't remove - we'll check next cycle if floor changed

        else
            -- Walk towards the x,y position
            local dir = getDirectionTo(playerPos, targetTilePos)
            if dir then
                g_game.walk(dir)
                autoFollowState.lastStepTime = g_clock.millis()
            end
        end
    end
end

local function startFollow()
    if autoFollowState.followEvent then
        removeEvent(autoFollowState.followEvent)
    end

    local function loop()
        if not autoFollowState.enabled then return end

        doStep()

        autoFollowState.followEvent = scheduleEvent(loop, CONFIG.STEP_INTERVAL)
    end

    loop()
end

local function stopFollow()
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

    -- Update UI
    AutoFollow.updateUI()

    return true
end

function AutoFollow.clearTarget()
    autoFollowState.targetName = nil
    autoFollowState.targetId = nil
    autoFollowState.lastTargetPos = nil
    clearQueue()

    -- Update UI
    AutoFollow.updateUI()
end

-- ============================================================================
-- AUTO-CANCEL COUNTDOWN
-- Lifetime: 5-10 min (random). The countdown is reset by the same 5-10 min
-- random value every 30s if the player is out of PZ and the boss bar is
-- currently visible (i.e. a boss from the boss list is on screen and out of PZ).
-- ============================================================================
local function randomCountdownDuration()
    local range = CONFIG.COUNTDOWN_MAX - CONFIG.COUNTDOWN_MIN
    return CONFIG.COUNTDOWN_MIN + math.random(0, range)
end

local function canResetCountdown()
    local player = g_game.getLocalPlayer()
    if not player then return false end
    if player.getStates and PlayerStates then
        local states = player:getStates()
        if states and bit.band(states, PlayerStates.Pz) ~= 0 then
            return false
        end
    end
    local bossbar = modules.game_bossbar
    if not bossbar or not bossbar.isShowingBoss then return false end
    return bossbar.isShowingBoss() == true
end

local function getCountdownEndTime()
    return autoFollowState.countdownEndTime
end

local function stopCountdown()
    if autoFollowState.countdownTickEvent then
        removeEvent(autoFollowState.countdownTickEvent)
        autoFollowState.countdownTickEvent = nil
    end
    autoFollowState.countdownEndTime = 0
    autoFollowState.lastResetCheckTime = 0

    if modules.game_textmessage and modules.game_textmessage.hideTimerNotification then
        modules.game_textmessage.hideTimerNotification()
    end
end

local function countdownTick()
    autoFollowState.countdownTickEvent = nil

    if not autoFollowState.enabled then
        stopCountdown()
        return
    end

    local now = g_clock.seconds()

    -- Reset-eligibility check every RESET_CHECK_INTERVAL seconds
    if now - autoFollowState.lastResetCheckTime >= CONFIG.RESET_CHECK_INTERVAL then
        autoFollowState.lastResetCheckTime = now
        if canResetCountdown() then
            autoFollowState.countdownEndTime = now + randomCountdownDuration()
        end
    end

    -- Expired - force disable auto follow and clear target
    if now >= autoFollowState.countdownEndTime then
        if modules.game_textmessage then
            modules.game_textmessage.displayGameMessage("Auto Follow auto-cancelled (timer expired)")
        end
        AutoFollow.toggle(false)
        AutoFollow.clearTarget()
        return
    end

    autoFollowState.countdownTickEvent = scheduleEvent(countdownTick, CONFIG.COUNTDOWN_TICK_MS)
end

local function startCountdown()
    stopCountdown()

    autoFollowState.countdownEndTime = g_clock.seconds() + randomCountdownDuration()
    autoFollowState.lastResetCheckTime = g_clock.seconds()

    if modules.game_textmessage and modules.game_textmessage.showTimerNotification then
        local title = "Auto Follow"
        if autoFollowState.targetName then
            title = "Auto Follow: " .. autoFollowState.targetName
        end
        modules.game_textmessage.showTimerNotification(title, nil, getCountdownEndTime)
    end

    countdownTick()
end

function AutoFollow.toggle(enabled)
    -- Block enabling if in expedition or PVP battle
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
            startCountdown()
        end
    else
        -- Disconnect from PathSharing
        disconnectFromLeader()

        stopMonitor()
        stopFollow()
        stopCountdown()
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
    -- Disconnect from PathSharing
    disconnectFromLeader()

    -- Terminate PathSharing module
    if PathSharing then
        PathSharing.terminate()
        PathSharing = nil
    end

    stopMonitor()
    stopFollow()
    stopCountdown()
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
        targetLost = false,
        targetLostPos = nil,
        usePathSharing = true,
        pathSharingConnected = false,
        updatingUI = false,
        countdownEndTime = 0,
        countdownTickEvent = nil,
        lastResetCheckTime = 0
    }
end

return AutoFollow
