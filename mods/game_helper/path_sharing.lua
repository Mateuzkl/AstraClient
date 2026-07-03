-- Path Sharing Module
-- Enables cross-floor auto-follow between OTClient users via opcode 220
-- Uses same logic as CaveBot recorder for smart waypoint detection:
-- - Teleport/stairs: Records EXACT position (where to use)
-- - Normal walk: Records every N tiles (follower can walk near)

local PathSharing = {}

-- Constants
local OPCODE_PATH_SHARING = 220
local MAX_HISTORY_SIZE = 50

-- State
local state = {
    -- Leader state (when others follow us)
    isLeader = false,
    followers = {},
    lastPosition = nil,
    lastRecordedPos = nil,    -- Last position we actually recorded (like cavebot)
    positionHistory = {},
    monitorEvent = nil,
    
    -- Follower state (when we follow someone)
    isFollowing = false,
    leaderName = nil,
    receivedPaths = {},
    
    -- Events
    opcodeRegistered = false
}

-- Configuration
local CONFIG = {
    MONITOR_INTERVAL = 50,    -- ms - how often to check position
    NODE_DISTANCE = 5,        -- tiles - how far to walk before recording (same as cavebot)
}

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

local function copyPosition(pos)
    if not pos then return nil end
    return {x = pos.x, y = pos.y, z = pos.z}
end

local function isSamePosition(pos1, pos2)
    if not pos1 or not pos2 then return false end
    return pos1.x == pos2.x and pos1.y == pos2.y and pos1.z == pos2.z
end

local function getDistance(pos1, pos2)
    if not pos1 or not pos2 then return 999 end
    return math.max(math.abs(pos1.x - pos2.x), math.abs(pos1.y - pos2.y))
end

local function getLocalPlayerName()
    local player = g_game.getLocalPlayer()
    return player and player:getName() or nil
end

local function sendToServer(data)
    local protocol = g_game.getProtocolGame()
    if not protocol then 
        return false 
    end
    
    local jsonData = json.encode(data)
    protocol:sendExtendedOpcode(OPCODE_PATH_SHARING, jsonData)
    return true
end

-- Logging - set to true to enable detailed debug logs
local DEBUG_LOG = true

local function log(msg)
    g_logger.info("[PathSharing] " .. msg)
end

local function debug(msg)
    if DEBUG_LOG then
        g_logger.info("[PathSharing:DEBUG] " .. msg)
    end
end

-- ============================================================================
-- POSITION HISTORY MANAGEMENT
-- ============================================================================

-- Add position to history with type info
-- type: "node" = must walk exactly there (teleport/stairs)
--       "walk" = can walk near (normal walking)
local function addToHistory(pos, posType)
    if not pos then return end
    
    local entry = {
        x = pos.x,
        y = pos.y,
        z = pos.z,
        type = posType or "walk"
    }
    
    table.insert(state.positionHistory, entry)
    
    -- Trim if too large
    while #state.positionHistory > MAX_HISTORY_SIZE do
        table.remove(state.positionHistory, 1)
    end
    
    return entry
end

local function getHistory()
    return state.positionHistory
end

local function clearHistory()
    state.positionHistory = {}
end

-- ============================================================================
-- LEADER FUNCTIONS - SMART DETECTION (like cavebot recorder)
-- ============================================================================

local function broadcastToFollowers(data)
    if not state.isLeader or not next(state.followers) then return end
    
    data.leaderName = getLocalPlayerName()
    
    for followerName, _ in pairs(state.followers) do
        local payload = {
            targetPlayer = followerName,
            data = data
        }
        sendToServer(payload)
    end
end

-- Smart position detection - ONLY record teleports and floor changes (NODEs)
-- Normal walking is handled by direct following when target is visible
local function processPositionChange(newPos, oldPos)
    if not newPos or not oldPos then return end
    if isSamePosition(newPos, oldPos) then return end
    
    local recorded = false
    local entry = nil
    
    -- Case 1: Floor change (stairs, rope, ladder, hole)
    if newPos.z ~= oldPos.z then
        -- Record the OLD position - this is WHERE to use the stairs/rope
        entry = addToHistory(oldPos, "node")
        state.lastRecordedPos = copyPosition(newPos)
        recorded = true
        log(string.format(">>> FLOOR CHANGE: (%d,%d,%d) z:%d->%d", 
            oldPos.x, oldPos.y, oldPos.z, oldPos.z, newPos.z))
    
    -- Case 2: Teleport (moved more than 1 tile horizontally on same floor)
    elseif math.abs(oldPos.x - newPos.x) > 1 or math.abs(oldPos.y - newPos.y) > 1 then
        -- Record the OLD position - this is WHERE to step on/use the teleport
        entry = addToHistory(oldPos, "node")
        state.lastRecordedPos = copyPosition(newPos)
        recorded = true
        log(string.format(">>> TELEPORT: (%d,%d,%d) -> (%d,%d,%d)", 
            oldPos.x, oldPos.y, oldPos.z, newPos.x, newPos.y, newPos.z))
    end
    
    -- Note: We DON'T record normal walking - follower handles that when target is visible
    
    -- Broadcast to followers if we recorded a NODE
    if recorded and entry then
        local followerCount = 0
        for _ in pairs(state.followers) do followerCount = followerCount + 1 end
        log(string.format(">>> SENDING to %d followers: (%d,%d,%d)", 
            followerCount, entry.x, entry.y, entry.z))
        broadcastToFollowers({
            action = "path",
            pos = entry
        })
    end
end

-- Monitor leader position using polling
local function monitorLeaderPosition()
    if not state.isLeader then return end
    
    local player = g_game.getLocalPlayer()
    if not player then return end
    
    local currentPos = player:getPosition()
    if not currentPos then return end
    
    -- Check if position changed
    if state.lastPosition and not isSamePosition(state.lastPosition, currentPos) then
        processPositionChange(currentPos, state.lastPosition)
    end
    
    state.lastPosition = copyPosition(currentPos)
end

local function startLeaderMonitor()
    if state.monitorEvent then
        removeEvent(state.monitorEvent)
    end
    
    local function loop()
        if not state.isLeader then return end
        
        monitorLeaderPosition()
        
        state.monitorEvent = scheduleEvent(loop, CONFIG.MONITOR_INTERVAL)
    end
    
    -- Initialize positions
    local player = g_game.getLocalPlayer()
    if player then
        local pos = player:getPosition()
        state.lastPosition = copyPosition(pos)
        state.lastRecordedPos = copyPosition(pos)
        addToHistory(pos, "walk")
    end
    
    loop()
    log("Leader monitor started")
end

local function stopLeaderMonitor()
    if state.monitorEvent then
        removeEvent(state.monitorEvent)
        state.monitorEvent = nil
    end
end

local function handleSubscribeRequest(followerName)
    if not followerName then return end
    
    local player = g_game.getLocalPlayer()
    if not player then return end
    
    log("Received subscribe request from: " .. followerName)
    
    -- Add to followers list
    state.followers[followerName] = true
    state.isLeader = true
    
    -- Start monitoring if first follower
    if not state.monitorEvent then
        startLeaderMonitor()
    end
    
    -- Send confirmation with position history
    local response = {
        targetPlayer = followerName,
        data = {
            action = "subscribed",
            leaderName = getLocalPlayerName(),
            currentPos = copyPosition(player:getPosition()),
            history = getHistory()
        }
    }
    sendToServer(response)
    
    log(string.format("Accepted follower: %s (sent %d positions)", followerName, #state.positionHistory))
    
    if PathSharing.onFollowerAdded then
        PathSharing.onFollowerAdded(followerName)
    end
end

local function handleUnsubscribeRequest(followerName)
    if not followerName then return end
    
    state.followers[followerName] = nil
    log("Follower unsubscribed: " .. followerName)
    
    if not next(state.followers) then
        state.isLeader = false
        stopLeaderMonitor()
    end
    
    if PathSharing.onFollowerRemoved then
        PathSharing.onFollowerRemoved(followerName)
    end
end

-- ============================================================================
-- FOLLOWER FUNCTIONS
-- ============================================================================

local function handleSubscribedResponse(data)
    if not data.leaderName then return end
    
    state.leaderName = data.leaderName
    state.isFollowing = true
    
    log("Subscribed to leader: " .. data.leaderName)
    
    -- Add NODE history (teleports/stairs between us and leader)
    if data.history and #data.history > 0 then
        for _, pos in ipairs(data.history) do
            if pos.type == "node" then
                table.insert(state.receivedPaths, {
                    x = pos.x,
                    y = pos.y,
                    z = pos.z,
                    type = "node"
                })
            end
        end
        log(string.format("Received %d teleport/stair positions", #state.receivedPaths))
    end
    
    if PathSharing.onSubscribed then
        PathSharing.onSubscribed(data.leaderName)
    end
end

local function handlePathUpdate(data)
    debug("handlePathUpdate called")
    
    if not state.isFollowing then 
        debug("Not following, ignoring")
        return 
    end
    if data.leaderName ~= state.leaderName then 
        debug(string.format("Wrong leader: got %s, expected %s", tostring(data.leaderName), tostring(state.leaderName)))
        return 
    end
    
    if data.pos then
        local entry = {
            x = data.pos.x,
            y = data.pos.y,
            z = data.pos.z,
            type = data.pos.type or "walk"
        }
        table.insert(state.receivedPaths, entry)
        
        log(string.format("<<< RECEIVED: (%d,%d,%d) type=%s [queue: %d]", 
            entry.x, entry.y, entry.z, entry.type, #state.receivedPaths))
        
        if PathSharing.onPathReceived then
            PathSharing.onPathReceived(data.pos)
        end
    else
        debug("No pos in data")
    end
end

local function handleUnsubscribedResponse(data)
    log("Unsubscribed from leader")
    state.isFollowing = false
    state.leaderName = nil
    state.receivedPaths = {}
    
    if PathSharing.onUnsubscribed then
        PathSharing.onUnsubscribed()
    end
end

-- ============================================================================
-- OPCODE HANDLER
-- ============================================================================

local function onExtendedOpcode(protocol, opcode, buffer)
    if opcode ~= OPCODE_PATH_SHARING then return end
    
    local success, data = pcall(json.decode, buffer)
    if not success or not data then return end
    
    local action = data.action
    if not action then return end
    
    if action == "subscribe" then
        handleSubscribeRequest(data.followerName)
    elseif action == "unsubscribe" then
        handleUnsubscribeRequest(data.followerName)
    elseif action == "subscribed" then
        handleSubscribedResponse(data)
    elseif action == "unsubscribed" then
        handleUnsubscribedResponse(data)
    elseif action == "path" then
        handlePathUpdate(data)
    end
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

function PathSharing.subscribe(leaderName)
    if not leaderName then return false end
    
    if state.isFollowing then
        PathSharing.unsubscribe()
    end
    
    log("Subscribing to leader: " .. leaderName)
    
    local payload = {
        targetPlayer = leaderName,
        data = {
            action = "subscribe",
            followerName = getLocalPlayerName()
        }
    }
    
    state.leaderName = leaderName
    return sendToServer(payload)
end

function PathSharing.unsubscribe()
    if not state.isFollowing or not state.leaderName then return false end
    
    log("Unsubscribing from leader: " .. state.leaderName)
    
    local payload = {
        targetPlayer = state.leaderName,
        data = {
            action = "unsubscribe",
            followerName = getLocalPlayerName()
        }
    }
    sendToServer(payload)
    
    state.isFollowing = false
    state.leaderName = nil
    state.receivedPaths = {}
    
    return true
end

-- Get next destination from queue (includes type info)
function PathSharing.getNextDestination()
    if #state.receivedPaths == 0 then return nil end
    return table.remove(state.receivedPaths, 1)
end

function PathSharing.peekNextDestination()
    return state.receivedPaths[1]
end

function PathSharing.getQueueSize()
    return #state.receivedPaths
end

function PathSharing.clearQueue()
    state.receivedPaths = {}
end

function PathSharing.isFollowing()
    return state.isFollowing
end

function PathSharing.getLeaderName()
    return state.leaderName
end

function PathSharing.isLeader()
    return state.isLeader
end

function PathSharing.getPositionHistory()
    return state.positionHistory
end

function PathSharing.getHistorySize()
    return #state.positionHistory
end

function PathSharing.getFollowers()
    local list = {}
    for name, _ in pairs(state.followers) do
        table.insert(list, name)
    end
    return list
end

function PathSharing.getFollowerCount()
    local count = 0
    for _ in pairs(state.followers) do
        count = count + 1
    end
    return count
end

function PathSharing.kickFollower(followerName)
    if not state.followers[followerName] then return false end
    
    local payload = {
        targetPlayer = followerName,
        data = {
            action = "unsubscribed",
            leaderName = getLocalPlayerName()
        }
    }
    sendToServer(payload)
    
    state.followers[followerName] = nil
    
    if not next(state.followers) then
        state.isLeader = false
        stopLeaderMonitor()
    end
    
    return true
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

function PathSharing.init()
    -- Register (or re-register) the opcode 220 handler. Safe to call on EVERY login:
    -- unregister-then-register guarantees exactly one live handler even if the client
    -- clears extended-opcode callbacks between game sessions or init() runs twice.
    -- This is what lets a player be FOLLOWED (become a leader) without having opened
    -- Auto Follow themselves -- the helper calls it eagerly in online().
    pcall(function() ProtocolGame.unregisterExtendedOpcode(OPCODE_PATH_SHARING) end)
    ProtocolGame.registerExtendedOpcode(OPCODE_PATH_SHARING, onExtendedOpcode)
    state.opcodeRegistered = true

    log("Initialized")
end

function PathSharing.terminate()
    if state.isFollowing then
        PathSharing.unsubscribe()
    end
    
    if state.isLeader then
        for followerName, _ in pairs(state.followers) do
            PathSharing.kickFollower(followerName)
        end
    end
    
    stopLeaderMonitor()
    clearHistory()
    
    if state.opcodeRegistered then
        ProtocolGame.unregisterExtendedOpcode(OPCODE_PATH_SHARING)
        state.opcodeRegistered = false
    end
    
    state = {
        isLeader = false,
        followers = {},
        lastPosition = nil,
        lastRecordedPos = nil,
        positionHistory = {},
        monitorEvent = nil,
        isFollowing = false,
        leaderName = nil,
        receivedPaths = {},
        opcodeRegistered = false
    }
    
    log("Terminated")
end

return PathSharing
