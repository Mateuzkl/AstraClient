-- StallDiagnostics
-- Samples network state in memory and uploads a snapshot to the server
-- after every recovered stall. The server logs it via createLog so we can
-- analyze post-mortem. Zero impact during normal play (1 sample/second,
-- in-memory ring buffer; disk I/O is server-side only).
--
-- v2 additions:
--   * Background external connectivity prober (HTTP to Google/Cloudflare)
--   * `external_checks` field on every payload — lets us classify each
--     event as "their internet is down" vs "path to our server is bad".
--   * New `connection_quality_warning` reason: best-effort emit at peak
--     level 3 while still online.
--   * New `disconnected` reason: persisted to disk on game end, replayed
--     via the same opcode on next successful login.

StallDiagnostics = {}

local NETDIAG_OPCODE = 0xCE             -- client -> server diagnostic upload
local NETDIAG_REQUEST_OPCODE = 0xCD      -- server -> client "please upload now"
local SCHEMA_VERSION = 2
local RING_SIZE = 60                      -- 60 seconds of history
local SAMPLE_INTERVAL = 1000              -- 1Hz sampling
local UPLOAD_MIN_DURATION_MS = 3000       -- only upload stalls >= 3s
local UPLOAD_MAX_BYTES = 8000             -- cap payload size before send
local UPLOAD_GRACE_MS = 500               -- wait briefly after recovery before sending

-- External connectivity prober.
-- Endpoints must satisfy three constraints for OTC's Boost.Beast HTTP client:
--   1. Plain HTTP, not HTTPS — avoids TLS stream-truncation errors logged
--      by the C++ HttpSession that we cannot suppress from Lua.
--   2. Real response body with Content-Length — 204 No Content responses
--      (e.g. google.com/generate_204) trigger "stream truncated" in Beast.
--   3. Hostname, not raw IP — SNI / cert path quirks in some builds.
-- detectportal.firefox.com and msftconnecttest.com are designed for exactly
-- this connectivity-check use case (they're what OS captive-portal probes
-- use) so they're stable, low-latency, and globally reachable.
local PROBE_INTERVAL_MS = 60000           -- run probes every 60s
local PROBE_FRESHNESS_MS = 180000         -- max age of result we'll attach
local PROBE_INFLIGHT_WARN_MS = 5000       -- mark in_flight if no callback after 5s
local PROBE_ENDPOINTS = {
    { name = "firefox",   url = "http://detectportal.firefox.com/success.txt" },
    { name = "microsoft", url = "http://www.msftconnecttest.com/connecttest.txt" },
}

-- Persistence (disconnect events queued for replay on next login)
local PENDING_FILE = "/diag_pending.json"
local PENDING_MAX_BYTES = 32 * 1024
local PENDING_REPLAY_DELAY_MS = 4000      -- wait after login before draining

local samples = {}
local writeIdx = 1
local lastSent, lastRecv = 0, 0
local sampleEvent = nil
local probeEvent = nil
local stallStartMs = nil
local stallPeakLevel = 0
local quality3Emitted = false
local probeResults = {}                   -- keyed by endpoint name
local probeInFlight = {}                  -- keyed by endpoint name -> startedAt

-- Forward declarations: persistence helpers are referenced by uploadDiagnostics
-- but defined further down (they live in the persistence section for
-- readability). Declaring them here keeps them as locals so the references
-- resolve correctly at runtime.
local persistPending
local prunePendingByUid
local makeUid

local function safeJsonEncode(t)
    if not (json and json.encode) then return nil end
    local ok, encoded = pcall(json.encode, t)
    if not ok or type(encoded) ~= "string" then return nil end
    return encoded
end

local function safeJsonDecode(s)
    if not (json and json.decode) then return nil end
    local ok, decoded = pcall(json.decode, s)
    if not ok then return nil end
    return decoded
end

local function wallTime()
    local ok, t = pcall(function() return os.time() end)
    return (ok and t) or 0
end

local function snapshotRing()
    local out = {}
    -- Walk oldest to newest
    for i = 0, RING_SIZE - 1 do
        local idx = ((writeIdx + i - 1) % RING_SIZE) + 1
        local s = samples[idx]
        if s then table.insert(out, s) end
    end
    return out
end

local function sample()
    -- Defensive: if game ended mid-cycle, abort
    if not g_game.isOnline() then return end

    local now = g_clock.millis()
    local sent = g_game.getNetPacketsSent() or 0
    local recv = g_game.getNetPacketsReceived() or 0

    samples[writeIdx] = {
        t = now,
        ping = g_game.getPing() or 0,
        loss = (g_game.getNetPacketLoss() or 0) / 100,
        jitter = g_game.getNetJitter() or 0,
        sent_rate = sent - lastSent,
        recv_rate = recv - lastRecv,
    }

    lastSent = sent
    lastRecv = recv
    writeIdx = (writeIdx % RING_SIZE) + 1
end

-- ---------------------------------------------------------------------------
-- External connectivity prober
-- ---------------------------------------------------------------------------

local function fireProbe(epName, epUrl)
    if probeInFlight[epName] then
        -- Previous probe still pending; let it finish (network may be slow/down)
        return
    end
    probeInFlight[epName] = g_clock.millis()
    local startedAt = g_clock.millis()
    local ok, err = pcall(function()
        HTTP.get(epUrl, function(_, httpErr)
            probeInFlight[epName] = nil
            local rtt = g_clock.millis() - startedAt
            probeResults[epName] = {
                result = httpErr and "fail" or "ok",
                rtt_ms = rtt,
                measured_at = g_clock.millis(),
                err = httpErr,
            }
        end)
    end)
    if not ok then
        probeInFlight[epName] = nil
        probeResults[epName] = {
            result = "skip",
            rtt_ms = nil,
            measured_at = g_clock.millis(),
            err = tostring(err),
        }
    end
end

local function runProbe()
    if not (HTTP and HTTP.get and g_http and g_http.get) then return end
    for _, ep in ipairs(PROBE_ENDPOINTS) do
        fireProbe(ep.name, ep.url)
    end
end

local function externalSnapshot()
    local now = g_clock.millis()
    local snap = {}
    for _, ep in ipairs(PROBE_ENDPOINTS) do
        local r = probeResults[ep.name]
        local inFlight = probeInFlight[ep.name]
        local entry
        if r and (now - r.measured_at) <= PROBE_FRESHNESS_MS then
            entry = {
                result = r.result,
                rtt_ms = r.rtt_ms,
                age_ms = now - r.measured_at,
            }
            if r.err then entry.err = tostring(r.err) end
        end
        if inFlight and (now - inFlight) >= PROBE_INFLIGHT_WARN_MS then
            entry = entry or {}
            entry.in_flight_ms = now - inFlight
        end
        if entry then snap[ep.name] = entry end
    end
    -- Server-side health proxy: how long since we received anything from server
    local ok, age = pcall(function()
        local protocolGame = g_game.isOnline() and g_game.getProtocolGame() or nil
        if protocolGame and protocolGame.getElapsedTicksSinceLastRead then
            return protocolGame:getElapsedTicksSinceLastRead()
        end
        return nil
    end)
    if ok and age then
        snap.server_last_read_age_ms = age
    end
    return snap
end

-- ---------------------------------------------------------------------------
-- Payload construction & upload
-- ---------------------------------------------------------------------------

local function buildPayload(reason, durationMs, extras)
    local payload = {
        v = SCHEMA_VERSION,
        reason = reason,
        stall_duration_ms = durationMs or 0,
        peak_level = stallPeakLevel,
        client_time_ms = g_clock.millis(),
        wall_time = wallTime(),
        samples = snapshotRing(),
        external_checks = externalSnapshot(),
    }
    if extras then
        for k, v in pairs(extras) do payload[k] = v end
    end
    return payload
end

local function sendOpcode(encoded)
    if not g_game.isOnline() then return false end
    local protocolGame = g_game.getProtocolGame()
    if not protocolGame then return false end
    local ok, err = pcall(function()
        protocolGame:sendExtendedOpcode(NETDIAG_OPCODE, encoded)
    end)
    if not ok then
        pwarning("[StallDiagnostics] upload failed: " .. tostring(err))
        return false
    end
    return true
end

local function encodeWithCap(payload)
    local encoded = safeJsonEncode(payload)
    if not encoded then return nil end
    if #encoded > UPLOAD_MAX_BYTES then
        payload.samples = {}
        encoded = safeJsonEncode(payload)
    end
    return encoded
end

-- Sends the diagnostic. If `persist` is true, the payload is queued to disk
-- BEFORE attempting the live send and removed only if the send succeeds.
-- This guarantees an at-risk emission (during stall / on uplink trouble)
-- is never lost: either the live send works, or it gets replayed on next
-- successful login.
local function uploadDiagnostics(reason, durationMs, extras, persist)
    local payload = buildPayload(reason, durationMs, extras)
    if persist then
        payload._uid = makeUid(payload, reason)
        persistPending(payload)
    end
    local encoded = encodeWithCap(payload)
    if not encoded then return end
    local sent = sendOpcode(encoded)
    if sent and persist then
        prunePendingByUid(payload._uid)
    end
end

-- ---------------------------------------------------------------------------
-- Server-triggered diagnostic request
-- ---------------------------------------------------------------------------
-- The server detects asymmetric stalls (client uplink dead but downlink fine)
-- via Player::isClientStalled. When that fires, the server sends opcode 0xCD
-- to the client carrying the silent_ms it observed. We immediately upload the
-- current diagnostic so the CLIENT_DIAG log gets an entry matching the
-- DAMAGE_BLOCKED / stall events that would otherwise have no client-side data.

local function onServerStallRequest(protocol, opcode, buffer)
    local serverSilentMs = 0
    if buffer and #buffer >= 4 then
        local b1 = buffer:byte(1) or 0
        local b2 = buffer:byte(2) or 0
        local b3 = buffer:byte(3) or 0
        local b4 = buffer:byte(4) or 0
        serverSilentMs = b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
    end
    -- At-risk emission: persist first so we don't lose it if the uplink
    -- is broken and the live send never reaches the server.
    uploadDiagnostics("server_requested_stall_check", serverSilentMs, {
        server_silent_ms = serverSilentMs,
    }, true)
end

-- ---------------------------------------------------------------------------
-- Persistence (queue disconnect events for next-login replay)
-- ---------------------------------------------------------------------------

local function readPendingList()
    if not (g_resources and g_resources.fileExists and g_resources.readFileContents) then
        return {}
    end
    local exists = false
    pcall(function() exists = g_resources.fileExists(PENDING_FILE) end)
    if not exists then return {} end
    local raw
    pcall(function() raw = g_resources.readFileContents(PENDING_FILE) end)
    if not raw or #raw == 0 then return {} end
    local decoded = safeJsonDecode(raw)
    if type(decoded) ~= "table" then return {} end
    return decoded
end

local function writePendingList(list)
    if not (g_resources and g_resources.writeFileContents) then return end
    local encoded = safeJsonEncode(list)
    if not encoded then return end
    -- Cap by dropping oldest entries
    while #encoded > PENDING_MAX_BYTES and #list > 0 do
        table.remove(list, 1)
        encoded = safeJsonEncode(list) or ""
    end
    pcall(function() g_resources.writeFileContents(PENDING_FILE, encoded) end)
end

local function deletePendingFile()
    if not (g_resources and g_resources.deleteFile) then return end
    pcall(function() g_resources.deleteFile(PENDING_FILE) end)
end

function persistPending(payload)
    local list = readPendingList()
    table.insert(list, payload)
    writePendingList(list)
end

function prunePendingByUid(uid)
    if not uid then return end
    local list = readPendingList()
    if #list == 0 then return end
    local kept = {}
    local removed = false
    for _, entry in ipairs(list) do
        if type(entry) == "table" and entry._uid == uid then
            removed = true
        else
            table.insert(kept, entry)
        end
    end
    if not removed then return end
    if #kept == 0 then
        deletePendingFile()
    else
        writePendingList(kept)
    end
end

function makeUid(payload, reason)
    return string.format("%d-%d-%d-%s",
        payload.wall_time or 0,
        payload.client_time_ms or 0,
        math.random(1, 99999),
        reason or "")
end

local function drainPending()
    local list = readPendingList()
    if #list == 0 then
        deletePendingFile()
        return
    end
    if not g_game.isOnline() then return end
    local sentCount = 0
    for _, entry in ipairs(list) do
        if type(entry) == "table" then
            entry.replayed = true
            local enc = encodeWithCap(entry)
            if enc and sendOpcode(enc) then
                sentCount = sentCount + 1
            end
        end
    end
    deletePendingFile()
    if sentCount > 0 then
        pinfo("[StallDiagnostics] replayed " .. sentCount .. " queued diagnostic(s)")
    end
end

-- ---------------------------------------------------------------------------
-- Triggers
-- ---------------------------------------------------------------------------

function StallDiagnostics.onConnectionStall(level, readAge)
    if level == nil then return end

    if level >= 1 then
        if not stallStartMs then
            stallStartMs = g_clock.millis()
            stallPeakLevel = level
            quality3Emitted = false
            -- Fire an on-demand probe at stall onset. The HTTP request runs in
            -- parallel with the stall; by the time recovery happens 3-5s later
            -- and the snapshot is built, the probe result has updated. This
            -- gives us "during the stall" external_checks data instead of the
            -- 30s-stale background poll. runProbe() guards against double-fire
            -- via probeInFlight, so this is cheap if a probe is already running.
            runProbe()
        elseif level > stallPeakLevel then
            stallPeakLevel = level
        end
        -- Best-effort warning at level 3, while connection might still be alive.
        if level >= 3 and not quality3Emitted then
            quality3Emitted = true
            local since = g_clock.millis() - stallStartMs
            -- At-risk emission: connection might already be broken at level 3.
            -- Persist first so it survives even if the live send is dropped.
            uploadDiagnostics("connection_quality_warning", since, {
                read_age_ms = readAge,
            }, true)
        end
    elseif level == 0 and stallStartMs then
        local duration = g_clock.millis() - stallStartMs
        local peak = stallPeakLevel
        stallStartMs = nil
        stallPeakLevel = 0
        quality3Emitted = false

        if duration >= UPLOAD_MIN_DURATION_MS then
            -- Wait briefly so the recovered connection is fully ready
            scheduleEvent(function()
                stallPeakLevel = peak  -- restore for the upload, then clear after
                uploadDiagnostics("recovered_after_stall", duration)
                stallPeakLevel = 0
            end, UPLOAD_GRACE_MS)
        end
    end
end

local function captureDisconnectIfStalled()
    -- Only capture if we ended while in a stall — clean logouts are noise.
    if not stallStartMs then return end
    local duration = g_clock.millis() - stallStartMs
    -- Build payload manually so we don't depend on the protocol still being attached
    local payload = {
        v = SCHEMA_VERSION,
        reason = "disconnected",
        stall_duration_ms = duration,
        peak_level = stallPeakLevel,
        client_time_ms = g_clock.millis(),
        wall_time = wallTime(),
        samples = snapshotRing(),
        external_checks = externalSnapshot(),
        captured_on = "game_end",
    }
    persistPending(payload)
end

function StallDiagnostics.start()
    if sampleEvent then return end
    samples = {}
    writeIdx = 1
    stallStartMs = nil
    stallPeakLevel = 0
    quality3Emitted = false
    probeResults = {}
    probeInFlight = {}
    -- Initialize counters defensively
    local okSent, sent = pcall(g_game.getNetPacketsSent)
    local okRecv, recv = pcall(g_game.getNetPacketsReceived)
    lastSent = (okSent and sent) or 0
    lastRecv = (okRecv and recv) or 0
    sampleEvent = cycleEvent(sample, SAMPLE_INTERVAL)
    probeEvent = cycleEvent(runProbe, PROBE_INTERVAL_MS)
    connect(g_game, { onConnectionStall = StallDiagnostics.onConnectionStall })
    -- Listen for server-triggered diagnostic requests (asymmetric stall case)
    if ProtocolGame and ProtocolGame.registerExtendedOpcode then
        pcall(function()
            ProtocolGame.registerExtendedOpcode(NETDIAG_REQUEST_OPCODE, onServerStallRequest)
        end)
    end
    -- Fire one probe immediately so we have data soon
    runProbe()
    -- Drain any pending diagnostics from a previous session, after a brief delay
    -- so login traffic settles first.
    scheduleEvent(drainPending, PENDING_REPLAY_DELAY_MS)
end

function StallDiagnostics.stop()
    -- Capture a disconnected snapshot if we ended mid-stall — must happen before
    -- we tear down samples/probe state.
    captureDisconnectIfStalled()
    if sampleEvent then
        removeEvent(sampleEvent)
        sampleEvent = nil
    end
    if probeEvent then
        removeEvent(probeEvent)
        probeEvent = nil
    end
    disconnect(g_game, { onConnectionStall = StallDiagnostics.onConnectionStall })
    if ProtocolGame and ProtocolGame.unregisterExtendedOpcode then
        pcall(function()
            ProtocolGame.unregisterExtendedOpcode(NETDIAG_REQUEST_OPCODE)
        end)
    end
    samples = {}
    stallStartMs = nil
    stallPeakLevel = 0
    quality3Emitted = false
    probeResults = {}
    probeInFlight = {}
end

function StallDiagnostics.init()
    connect(g_game, {
        onGameStart = StallDiagnostics.start,
        onGameEnd = StallDiagnostics.stop,
    })
    -- If game is already running when this loads, start immediately
    if g_game.isOnline() then
        StallDiagnostics.start()
    end
end

function StallDiagnostics.terminate()
    StallDiagnostics.stop()
    disconnect(g_game, {
        onGameStart = StallDiagnostics.start,
        onGameEnd = StallDiagnostics.stop,
    })
end

StallDiagnostics.init()
