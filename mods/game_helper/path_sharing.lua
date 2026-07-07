-- Path Sharing (FOLLOWER side only)
--
-- The SERVER is now the source of truth for the leader's path. It tracks every leader
-- and streams the leader's authoritative position (+facing) to the subscribed
-- followers via extended opcode 220 (see the server bridge
-- data-koliseu/scripts/custom/pathfollow_otc_bridge.lua). This client only:
--   * SUBSCRIBES to a leader (asks the server to stream that leader to us), and
--   * CONSUMES the stream: an ordered trail (for transit / catch-up through
--     teleports/stairs) plus the latest leader state (pos + facing).
--
-- The old LEADER role (detecting our own movement and broadcasting it) was removed --
-- that client-side detection is exactly what missed teleports. A leader is now tracked
-- server-side and doesn't even need this module (could be a CIP client).

local PathSharing = {}

local OPCODE = 220
-- Bound the pending trail. In normal play the follower consumes far faster than the
-- ~stream rate, so this never trims; it only caps memory if we fall badly behind.
local MAX_TRAIL = 100

local state = {
    isFollowing = false,
    leaderName = nil,
    trail = {},        -- ordered { {x,y,z}, ... } the leader passed (oldest first)
    leaderPos = nil,   -- latest leader position (authoritative)
    leaderDir = nil,   -- latest leader facing (0-7)
    opcodeRegistered = false,
}

-- Callbacks assigned by auto_follow: onSubscribed(leaderName), onUnsubscribed(),
-- onPathReceived(pos). PathSharing.onX = function ... end

local DEBUG_LOG = false
local function log(msg) g_logger.info("[PathSharing] " .. msg) end
local function debug(msg) if DEBUG_LOG then g_logger.info("[PathSharing:DEBUG] " .. msg) end end

local function getLocalPlayerName()
    local p = g_game.getLocalPlayer()
    return p and p:getName() or nil
end

local function sendToServer(data)
    local protocol = g_game.getProtocolGame()
    if not protocol then return false end
    protocol:sendExtendedOpcode(OPCODE, json.encode(data))
    return true
end

local function samePos(a, b)
    return a and b and a.x == b.x and a.y == b.y and a.z == b.z
end

-- ============================================================================
-- RECEIVE (server -> follower)
-- ============================================================================

local function handleSubscribed(data)
    state.isFollowing = true
    state.leaderName = data.leaderName or state.leaderName
    log("Subscribed to leader: " .. tostring(state.leaderName))
    if PathSharing.onSubscribed then PathSharing.onSubscribed(state.leaderName) end
end

local function handlePath(data)
    if not state.isFollowing then return end
    if not data.pos or not data.pos.x then return end
    local pos = { x = data.pos.x, y = data.pos.y, z = data.pos.z }
    state.leaderPos = pos
    state.leaderDir = data.dir
    -- Append to the trail, deduping consecutive identical tiles.
    local last = state.trail[#state.trail]
    if not samePos(last, pos) then
        table.insert(state.trail, pos)
        while #state.trail > MAX_TRAIL do table.remove(state.trail, 1) end
        debug(string.format("<<< (%d,%d,%d) dir=%s [trail:%d]",
            pos.x, pos.y, pos.z, tostring(data.dir), #state.trail))
    end
    if PathSharing.onPathReceived then PathSharing.onPathReceived(pos) end
end

local function handleUnsubscribed(data)
    log("Unsubscribed from leader")
    state.isFollowing = false
    state.leaderName = nil
    state.trail = {}
    state.leaderPos = nil
    state.leaderDir = nil
    if PathSharing.onUnsubscribed then PathSharing.onUnsubscribed() end
end

local function onExtendedOpcode(protocol, opcode, buffer)
    if opcode ~= OPCODE then return end
    local ok, data = pcall(json.decode, buffer)
    if not ok or type(data) ~= "table" then return end
    local action = data.action
    if action == "path" then
        handlePath(data)
    elseif action == "subscribed" then
        handleSubscribed(data)
    elseif action == "unsubscribed" then
        handleUnsubscribed(data)
    end
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

function PathSharing.subscribe(leaderName)
    if not leaderName then return false end
    if state.isFollowing then PathSharing.unsubscribe() end
    state.leaderName = leaderName
    state.trail = {}
    log("Subscribing to leader: " .. leaderName)
    return sendToServer({
        targetPlayer = leaderName,
        data = { action = "subscribe", followerName = getLocalPlayerName() }
    })
end

function PathSharing.unsubscribe()
    if not state.leaderName then return false end
    log("Unsubscribing from leader: " .. state.leaderName)
    sendToServer({
        targetPlayer = state.leaderName,
        data = { action = "unsubscribe", followerName = getLocalPlayerName() }
    })
    state.isFollowing = false
    state.leaderName = nil
    state.trail = {}
    state.leaderPos = nil
    state.leaderDir = nil
    return true
end

function PathSharing.isFollowing() return state.isFollowing end
function PathSharing.getLeaderName() return state.leaderName end

-- Latest authoritative leader position + facing (for off-screen formation / catch-up).
function PathSharing.getLeaderState() return state.leaderPos, state.leaderDir end

-- Trail access (ordered, oldest first).
function PathSharing.getQueueSize() return #state.trail end
function PathSharing.peek(i) return state.trail[i or 1] end
function PathSharing.peekNextDestination() return state.trail[1] end
function PathSharing.pop()
    if #state.trail == 0 then return nil end
    return table.remove(state.trail, 1)
end
function PathSharing.getNextDestination() return PathSharing.pop() end
function PathSharing.clearQueue() state.trail = {} end

function PathSharing.init()
    -- Register (or re-register) the opcode 220 receiver. Safe every login.
    pcall(function() ProtocolGame.unregisterExtendedOpcode(OPCODE) end)
    ProtocolGame.registerExtendedOpcode(OPCODE, onExtendedOpcode)
    state.opcodeRegistered = true
    log("Initialized (follower)")
end

function PathSharing.terminate()
    if state.isFollowing then PathSharing.unsubscribe() end
    if state.opcodeRegistered then
        ProtocolGame.unregisterExtendedOpcode(OPCODE)
        state.opcodeRegistered = false
    end
    state = {
        isFollowing = false, leaderName = nil, trail = {},
        leaderPos = nil, leaderDir = nil, opcodeRegistered = false,
    }
    log("Terminated")
end

return PathSharing
