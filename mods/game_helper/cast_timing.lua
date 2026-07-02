-- CastTiming: reactive + predictive cast timing engine ("smart timers").
--
-- Instead of blindly polling every 50-100ms and casting whenever a local
-- timestamp looks expired, this engine:
--   1. Mirrors the server-authoritative cooldowns (0xA4 spell / 0xA5 group /
--      0xA6 multi-use) with their arrival time.
--   2. Predicts: a cast may be SENT while the local cooldown still has up to
--      lead() ms remaining, so the packet reaches the server right when the
--      real cooldown expires (the local expiry is ~1/2 RTT late by nature and
--      the outgoing packet takes another ~1/2 RTT — lead() covers both).
--   3. Reacts: every server cooldown arms a scheduleEvent wake at
--      readyAt - lead(), which re-runs the helper checks at exactly the right
--      moment instead of waiting for the next 100ms tick.
--   4. Locks: an explicit inflight lock per spell/group/multi-use prevents
--      double-casting during the window between sending a cast and receiving
--      its server cooldown echo. The lock is released early by the real echo
--      or expires after ~2x RTT (failed/ignored cast -> quick retry).
--
-- IMPORTANT: this registry is fed ONLY by real server packets. init() connects
-- its own g_game handlers, so the helper's local optimistic echoes (e.g.
-- onSpellCooldown(spell.id, 1) called right after a cast) never reach it and
-- can't release an inflight lock prematurely.
--
-- helper.lua integration surface:
--   CastTiming.isActive()                 -- master switch (helper config)
--   CastTiming.isSpellBlocked(spell)      -- predictive replacement for isSpellOnCooldown
--   CastTiming.isGroupBlocked(groupId)    -- predictive gate for a single group
--   CastTiming.isMultiUseBlocked()        -- predictive gate for rune/potion exhaust
--   CastTiming.noteSpellCastSent(spell)   -- call right after g_game.talk(spell.words)
--   CastTiming.noteRuneCastSent(runeSpell)-- call right after g_game.useInventoryItemWith
--   CastTiming.notePotionUsed()           -- call right after g_game.useInventoryItem
--   castTimingWakeDispatch()              -- defined by helper.lua; called on wakes

CastTiming = {}

local cfg = { enabled = true, leadPct = 90 }

local PING_ALPHA = 0.25       -- EWMA weight of a new RTT sample
local LEAD_CAP_MS = 150       -- hard cap on how early a cast may be sent
local INFLIGHT_MIN_MS = 120   -- minimum lock while a cast awaits its server echo
local INFLIGHT_CAP_MS = 1000
local WAKE_DEDUPE_MS = 8      -- wakes closer than this are merged
local MAX_PENDING_WAKES = 8

local pingEwma = nil          -- smoothed RTT (ms)
local pingJitter = 0          -- smoothed |sample - ewma|

local spellReadyAt = {}       -- [spellId] = g_clock.millis() when server CD expires (locally)
local groupReadyAt = {}       -- [groupId] = same
local multiUseReadyAt = 0
local multiUseSeen = false    -- true once a REAL 0xA6 arrived this session (callers
                              -- keep their legacy potion floors until then)
local shortestCdSeen = nil    -- shortest real spell CD observed (lead safety clamp)

local spellInflight = {}      -- [spellId] = lock expiry ms
local groupInflight = {}      -- [groupId] = lock expiry ms
local multiUseInflight = 0

local pendingWakes = {}       -- [seq] = { at = ms, ev = scheduledEvent }
local wakeSeq = 0

CAST_TIMING_DEBUG = CAST_TIMING_DEBUG or false
local dbgLastEcho = {}        -- [spellId] = ms of previous real 0xA4 (gap metric)
local dbgStats = { echoes = 0, wastedMs = 0, wakes = 0, locksExpired = 0 }

local function dbg(fmt, ...)
    if CAST_TIMING_DEBUG then
        print(string.format("[CastTiming] " .. fmt, ...))
    end
end

-- ============================================================================
-- Ping model
-- ============================================================================

local function onPingBack(ping)
    if not ping or ping < 0 then
        return
    end
    if pingEwma then
        pingJitter = pingJitter * (1 - PING_ALPHA) + math.abs(ping - pingEwma) * PING_ALPHA
        pingEwma = pingEwma * (1 - PING_ALPHA) + ping * PING_ALPHA
    else
        pingEwma = ping
        pingJitter = 0
    end
end

-- How many ms before the LOCAL cooldown expiry a cast may be sent.
function CastTiming.lead()
    if not cfg.enabled then
        return 0
    end
    local rtt = pingEwma or 0
    local lead = rtt * (cfg.leadPct / 100)
    if lead > LEAD_CAP_MS then
        lead = LEAD_CAP_MS
    end
    -- Never predict more than half of the shortest real cooldown seen this
    -- session: on tiny cooldowns an over-eager lead would arrive early and
    -- waste the retry round-trip instead of saving one.
    if shortestCdSeen and lead > shortestCdSeen * 0.5 then
        lead = shortestCdSeen * 0.5
    end
    return lead
end

local function inflightDuration()
    local rtt = pingEwma or 50
    local dur = rtt * 2
    if dur < INFLIGHT_MIN_MS then
        dur = INFLIGHT_MIN_MS
    end
    if dur > INFLIGHT_CAP_MS then
        dur = INFLIGHT_CAP_MS
    end
    return dur
end

-- ============================================================================
-- Configuration
-- ============================================================================

function CastTiming.configure(options)
    if type(options) ~= "table" then
        return
    end
    if options.enabled ~= nil then
        cfg.enabled = options.enabled == true
    end
    local pct = tonumber(options.leadPct)
    if pct then
        if pct < 0 then pct = 0 end
        if pct > 100 then pct = 100 end
        cfg.leadPct = pct
    end
    dbg("configure: enabled=%s leadPct=%d", tostring(cfg.enabled), cfg.leadPct)
end

function CastTiming.isActive()
    return cfg.enabled
end

function CastTiming.getConfig()
    return { enabled = cfg.enabled, leadPct = cfg.leadPct }
end

-- ============================================================================
-- Wake scheduler
-- ============================================================================

local function firePendingWake(seq)
    pendingWakes[seq] = nil
    dbgStats.wakes = dbgStats.wakes + 1
    -- castTimingWakeDispatch is defined later by helper.lua (same module env);
    -- it re-runs the timing-sensitive checks with all their own guards.
    if castTimingWakeDispatch then
        local ok, err = pcall(castTimingWakeDispatch)
        if not ok then
            dbg("wake dispatch error: %s", tostring(err))
        end
    end
end

local function armWake(atMs)
    if not cfg.enabled then
        return
    end
    local now = g_clock.millis()
    if atMs < now then
        atMs = now
    end
    local count = 0
    for _, wake in pairs(pendingWakes) do
        if math.abs(wake.at - atMs) <= WAKE_DEDUPE_MS then
            return
        end
        count = count + 1
    end
    if count >= MAX_PENDING_WAKES then
        return
    end
    wakeSeq = wakeSeq + 1
    local seq = wakeSeq
    local ev = scheduleEvent(function()
        firePendingWake(seq)
    end, atMs - now)
    pendingWakes[seq] = { at = atMs, ev = ev }
end

local function clearWakes()
    for _, wake in pairs(pendingWakes) do
        removeEvent(wake.ev)
    end
    pendingWakes = {}
end

-- ============================================================================
-- Server cooldown handlers (real packets only — see header)
-- ============================================================================

local function onServerSpellCooldown(spellId, delay)
    delay = tonumber(delay) or 0
    local now = g_clock.millis()
    spellReadyAt[spellId] = now + delay
    -- The echo confirms the cast reached the server: release the lock early.
    spellInflight[spellId] = nil

    -- Same confirmation clears the shooter's 2s no-area retry backoff (module
    -- env global from helper_init.lua): the authoritative cooldown governs
    -- from here on. Only real packets reach this handler, so the shooter's
    -- own optimistic onSpellCooldown(id, 2000) echo can't wipe it.
    if cfg.enabled and noAreaSpellAttempts and noAreaSpellAttempts[spellId] then
        noAreaSpellAttempts[spellId] = nil
    end

    -- Track the shortest real cooldown for the lead clamp. Sub-100ms values
    -- would make lead() useless and are not real spell cooldowns anyway.
    if delay >= 100 and (not shortestCdSeen or delay < shortestCdSeen) then
        shortestCdSeen = delay
    end

    if CAST_TIMING_DEBUG then
        local last = dbgLastEcho[spellId]
        if last then
            local gap = now - last
            dbgStats.echoes = dbgStats.echoes + 1
            if delay > 0 and gap > delay then
                dbgStats.wastedMs = dbgStats.wastedMs + (gap - delay)
                dbg("spell %s: gap %dms vs cd %dms (wasted %dms) ping=%.0f lead=%.0f",
                    tostring(spellId), gap, delay, gap - delay, pingEwma or -1, CastTiming.lead())
            end
        end
        dbgLastEcho[spellId] = now
    end

    armWake(now + delay - CastTiming.lead())
end

local function onServerGroupCooldown(groupId, delay)
    delay = tonumber(delay) or 0
    local now = g_clock.millis()
    groupReadyAt[groupId] = now + delay
    groupInflight[groupId] = nil
    armWake(now + delay - CastTiming.lead())
end

local function onServerMultiUseCooldown(delay)
    delay = tonumber(delay) or 0
    local now = g_clock.millis()
    multiUseReadyAt = now + delay
    multiUseInflight = 0
    multiUseSeen = true
    armWake(now + delay - CastTiming.lead())
end

-- ============================================================================
-- Gates (predictive replacements for the polling-mode checks)
-- ============================================================================

-- Shared logic: blocked while inflight; otherwise ready once the remaining
-- cooldown is within lead() (the packet travel time we want to hide).
local function isBlocked(readyAt, inflightUntil, now, horizon)
    if inflightUntil and now < inflightUntil then
        return true
    end
    return readyAt ~= nil and readyAt > horizon
end

function CastTiming.isSpellBlocked(spell)
    local now = g_clock.millis()
    local horizon = now + CastTiming.lead()
    if isBlocked(spellReadyAt[spell.id], spellInflight[spell.id], now, horizon) then
        return true
    end
    if type(spell.group) == "table" then
        for groupId in pairs(spell.group) do
            if isBlocked(groupReadyAt[groupId], groupInflight[groupId], now, horizon) then
                return true
            end
        end
    elseif spell.group then
        if isBlocked(groupReadyAt[spell.group], groupInflight[spell.group], now, horizon) then
            return true
        end
    end
    return false
end

function CastTiming.isGroupBlocked(groupId)
    local now = g_clock.millis()
    return isBlocked(groupReadyAt[groupId], groupInflight[groupId], now, now + CastTiming.lead())
end

function CastTiming.isMultiUseBlocked()
    local now = g_clock.millis()
    return isBlocked(multiUseReadyAt, multiUseInflight, now, now + CastTiming.lead())
end

-- Whether this server sends the 0xA6 multi-use delay at all. Potion/rune-item
-- callers must keep their legacy local exhaust floors until the first real
-- echo proves the packet exists, or a blind predictive gate would spam-drink.
function CastTiming.hasMultiUseEcho()
    return multiUseSeen
end

-- ============================================================================
-- Cast notifications (arm the inflight locks)
-- ============================================================================

function CastTiming.noteSpellCastSent(spell)
    if not cfg.enabled or not spell then
        return
    end
    local until_ = g_clock.millis() + inflightDuration()
    if spell.id and spell.id ~= -1 then
        spellInflight[spell.id] = until_
    end
    if type(spell.group) == "table" then
        for groupId in pairs(spell.group) do
            groupInflight[groupId] = until_
        end
    elseif spell.group then
        groupInflight[spell.group] = until_
    end
end

function CastTiming.noteRuneCastSent(runeSpell)
    if not cfg.enabled then
        return
    end
    local until_ = g_clock.millis() + inflightDuration()
    multiUseInflight = until_
    if runeSpell then
        if runeSpell.id then
            spellInflight[runeSpell.id] = until_
        end
        if type(runeSpell.group) == "table" then
            for groupId in pairs(runeSpell.group) do
                groupInflight[groupId] = until_
            end
        elseif runeSpell.group then
            groupInflight[runeSpell.group] = until_
        end
    end
end

function CastTiming.notePotionUsed()
    if not cfg.enabled then
        return
    end
    multiUseInflight = g_clock.millis() + inflightDuration()
end

-- ============================================================================
-- Introspection / debug
-- ============================================================================

function CastTiming.getPing()
    return pingEwma, pingJitter
end

function CastTiming.debugStats()
    return {
        ping = pingEwma,
        jitter = pingJitter,
        lead = CastTiming.lead(),
        shortestCd = shortestCdSeen,
        echoes = dbgStats.echoes,
        wastedMs = dbgStats.wastedMs,
        wakes = dbgStats.wakes,
    }
end

-- ============================================================================
-- Lifecycle
-- ============================================================================

local function reset()
    spellReadyAt = {}
    groupReadyAt = {}
    multiUseReadyAt = 0
    multiUseSeen = false
    spellInflight = {}
    groupInflight = {}
    multiUseInflight = 0
    shortestCdSeen = nil
    dbgLastEcho = {}
    dbgStats = { echoes = 0, wastedMs = 0, wakes = 0, locksExpired = 0 }
    clearWakes()
end

CastTiming.reset = reset

function CastTiming.init()
    connect(g_game, {
        onPingBack = onPingBack,
        onSpellCooldown = onServerSpellCooldown,
        onSpellGroupCooldown = onServerGroupCooldown,
        onMultiUseCooldown = onServerMultiUseCooldown,
        onGameEnd = reset,
    })
end

function CastTiming.terminate()
    disconnect(g_game, {
        onPingBack = onPingBack,
        onSpellCooldown = onServerSpellCooldown,
        onSpellGroupCooldown = onServerGroupCooldown,
        onMultiUseCooldown = onServerMultiUseCooldown,
        onGameEnd = reset,
    })
    reset()
end
