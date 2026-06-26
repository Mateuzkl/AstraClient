-- Network Diagnostics Module
-- Monitors connection health and reports anomalies to Discord webhook.
-- Rate-limited to avoid log spam and performance impact.
-- Discord reports only sent if Services.discordNetDiag is configured.

NetDiag = {}

local CHECK_INTERVAL = 5000        -- check every 5 seconds
local LOG_COOLDOWN = 10000         -- max 1 local log per 10 seconds
local DISCORD_COOLDOWN = 30000     -- max 1 discord report per 30 seconds
local DISCONNECT_GRACE = 2000      -- ignore brief disconnects during login

-- Anomaly thresholds
local PING_THRESHOLD = 500         -- ms
local JITTER_THRESHOLD = 200       -- ms
local PKT_PER_SEC_THRESHOLD = 100  -- packets/sec
local PACKET_LOSS_THRESHOLD = 5    -- percent

-- State
local checkEvent = nil
local lastLogTime = 0
local lastDiscordTime = 0
local lastPktSent = 0
local lastPktRecv = 0
local lastCheckTime = 0
local prevTimeouts = 0
local sessionStartTime = 0
local lastMetrics = {}
local disconnectHooked = false

local function getCharName()
    local ok, name = pcall(function()
        return g_game.getCharacterName()
    end)
    return (ok and name and name ~= "") and name or "unknown"
end

local function getMachineId()
    local ok, id = pcall(function()
        return g_crypt.getMachineUUID()
    end)
    if ok and id and #id > 12 then
        return id:sub(1, 12) .. "..."
    end
    return (ok and id) and id or "N/A"
end

local function formatUptime(ms)
    local secs = math.floor(ms / 1000)
    local mins = math.floor(secs / 60)
    local hours = math.floor(mins / 60)
    if hours > 0 then
        return string.format("%dh%02dm", hours, mins % 60)
    end
    return string.format("%dm%02ds", mins, secs % 60)
end

local function sendToDiscord(payload)
    if not Services or not Services.discordNetDiag or Services.discordNetDiag == "" then
        return
    end
    if not HTTP or not HTTP.post then
        return
    end
    local ok, err = pcall(function()
        HTTP.post(Services.discordNetDiag, payload, function() end)
    end)
    if not ok then
        pwarning("[NetDiag] Discord send failed: " .. tostring(err))
    end
end

local function sendAnomalyReport(metrics)
    local now = g_clock.millis()
    if now - lastDiscordTime < DISCORD_COOLDOWN then return end
    lastDiscordTime = now

    local charName = getCharName()
    local uptime = formatUptime(now - sessionStartTime)

    local payload = {
        embeds = {{
            title = "Network Anomaly - " .. charName,
            color = 16744448, -- orange
            fields = {
                { name = "Ping", value = tostring(metrics.ping) .. "ms", inline = true },
                { name = "Jitter", value = string.format("%.0f", metrics.jitter) .. "ms", inline = true },
                { name = "Pkt/s Out", value = tostring(metrics.pktPerSecOut), inline = true },
                { name = "Pkt/s In", value = tostring(metrics.pktPerSecIn), inline = true },
                { name = "Timeouts", value = tostring(metrics.timeouts), inline = true },
                { name = "Packet Loss", value = string.format("%.1f%%", metrics.packetLoss), inline = true },
                { name = "Total Sent", value = tostring(metrics.totalSent), inline = true },
                { name = "Total Recv", value = tostring(metrics.totalRecv), inline = true },
                { name = "Uptime", value = uptime, inline = true },
            },
            footer = { text = "Machine: " .. getMachineId() },
            timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
        }}
    }

    sendToDiscord(payload)
end

local function sendDisconnectReport(errorMsg, errorCode, metrics)
    local charName = getCharName()
    local uptime = formatUptime(g_clock.millis() - sessionStartTime)

    local fields = {
        { name = "Error Code", value = "`" .. tostring(errorCode) .. "`", inline = true },
        { name = "Error", value = "`" .. tostring(errorMsg):sub(1, 200) .. "`", inline = false },
        { name = "Last Ping", value = tostring(metrics.ping or 0) .. "ms", inline = true },
        { name = "Last Jitter", value = string.format("%.0f", metrics.jitter or 0) .. "ms", inline = true },
        { name = "Pkt/s Out", value = tostring(metrics.pktPerSecOut or 0), inline = true },
        { name = "Pkt/s In", value = tostring(metrics.pktPerSecIn or 0), inline = true },
        { name = "Timeouts", value = tostring(metrics.timeouts or 0), inline = true },
        { name = "Packet Loss", value = string.format("%.1f%%", metrics.packetLoss or 0), inline = true },
        { name = "Total Sent", value = tostring(metrics.totalSent or 0), inline = true },
        { name = "Total Recv", value = tostring(metrics.totalRecv or 0), inline = true },
        { name = "Uptime", value = uptime, inline = true },
    }

    local payload = {
        embeds = {{
            title = "Disconnect - " .. charName,
            color = 16711680, -- red
            fields = fields,
            footer = { text = "Machine: " .. getMachineId() },
            timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
        }}
    }

    sendToDiscord(payload)
end

local function collectMetrics(elapsed)
    local ok, metrics = pcall(function()
        local pktSent = g_game.getNetPacketsSent()
        local pktRecv = g_game.getNetPacketsReceived()
        local elapsedSec = math.max(1, elapsed / 1000)

        local m = {
            ping = g_game.getPing(),
            jitter = g_game.getNetJitter(),
            timeouts = g_game.getPingTimeouts(),
            packetLoss = g_game.getNetPacketLoss(),
            totalSent = pktSent,
            totalRecv = pktRecv,
            pktPerSecOut = math.floor((pktSent - lastPktSent) / elapsedSec),
            pktPerSecIn = math.floor((pktRecv - lastPktRecv) / elapsedSec),
        }

        lastPktSent = pktSent
        lastPktRecv = pktRecv

        return m
    end)

    if ok then return metrics end
    return nil
end

local function isAnomaly(m)
    if not m then return false end
    if m.ping > PING_THRESHOLD then return true end
    if m.jitter > JITTER_THRESHOLD then return true end
    if m.pktPerSecOut > PKT_PER_SEC_THRESHOLD then return true end
    if m.packetLoss > PACKET_LOSS_THRESHOLD then return true end
    if m.timeouts > prevTimeouts then return true end
    return false
end

local function netDiagCheck()
    if not g_game.isOnline() then return end

    local now = g_clock.millis()
    local elapsed = now - lastCheckTime
    if elapsed < 1000 then return end -- safety guard
    lastCheckTime = now

    local metrics = collectMetrics(elapsed)
    if not metrics then return end

    lastMetrics = metrics

    if isAnomaly(metrics) then
        -- Local log (rate-limited)
        if now - lastLogTime >= LOG_COOLDOWN then
            lastLogTime = now
            pwarning(string.format(
                "[NetDiag] ping=%dms jitter=%.0fms out=%d/s in=%d/s timeouts=%d loss=%.1f%% sent=%d recv=%d",
                metrics.ping, metrics.jitter,
                metrics.pktPerSecOut, metrics.pktPerSecIn,
                metrics.timeouts, metrics.packetLoss,
                metrics.totalSent, metrics.totalRecv))
        end

        -- Discord report (rate-limited)
        sendAnomalyReport(metrics)
    end

    prevTimeouts = metrics.timeouts
end

function NetDiag.onDisconnect(errorMsg, errorCode)
    local now = g_clock.millis()
    -- Skip during login phase
    if now - sessionStartTime < DISCONNECT_GRACE then return end

    pwarning(string.format(
        "[NetDiag] DISCONNECT code=%s msg=%s ping=%dms out=%d/s timeouts=%d loss=%.1f%%",
        tostring(errorCode), tostring(errorMsg):sub(1, 100),
        lastMetrics.ping or 0, lastMetrics.pktPerSecOut or 0,
        lastMetrics.timeouts or 0, lastMetrics.packetLoss or 0))

    if Services and Services.discordNetDiag and Services.discordNetDiag ~= "" then
        sendDisconnectReport(errorMsg, errorCode, lastMetrics)
    end
end

function NetDiag.start()
    if checkEvent then return end -- already running

    sessionStartTime = g_clock.millis()
    lastCheckTime = sessionStartTime
    lastLogTime = 0
    lastDiscordTime = 0
    lastPktSent = 0
    lastPktRecv = 0
    prevTimeouts = 0
    lastMetrics = {}

    -- Initialize packet counters
    pcall(function()
        lastPktSent = g_game.getNetPacketsSent()
        lastPktRecv = g_game.getNetPacketsReceived()
    end)

    checkEvent = cycleEvent(netDiagCheck, CHECK_INTERVAL)

    -- Hook disconnect callback (once)
    if not disconnectHooked then
        connect(g_game, {
            onConnectionError = function(msg, code)
                pcall(NetDiag.onDisconnect, msg, code)
            end
        })
        disconnectHooked = true
    end
end

function NetDiag.stop()
    if checkEvent then
        removeEvent(checkEvent)
        checkEvent = nil
    end
end
