--[[
  KillPerf -- temporary profiler for the frame in which a creature dies.

  Disabled by default: with KillPerf.enabled == false every helper is a direct passthrough
  with no clock read, so leaving this mod installed costs nothing.

  Turn it on from the console:

      KillPerf.start()            -- log anything >= 0.5 ms
      KillPerf.start(1000)        -- log anything >= 1.0 ms
      KillPerf.stop()
      KillPerf.report()           -- totals per system since start()

  Output looks like:

      [KillPerf] kill #1258 Demon
      [KillPerf]   onKillTracker            2.140 ms
      [KillPerf]   BestiaryTracker.render   3.870 ms

  A system appearing twice under the same kill id means it is registered twice.
]]

KillPerf = KillPerf or {}

KillPerf.enabled = false
KillPerf.thresholdUs = 500
KillPerf.killSeq = 0

local stats = {}
local currentKill = nil

local function record(label, elapsedUs)
  local entry = stats[label]
  if not entry then
    entry = { count = 0, totalUs = 0, maxUs = 0, perKill = 0 }
    stats[label] = entry
  end
  entry.count = entry.count + 1
  entry.totalUs = entry.totalUs + elapsedUs
  if elapsedUs > entry.maxUs then
    entry.maxUs = elapsedUs
  end
end

-- Opens a new kill scope. Call this where the death first becomes visible to the client.
function KillPerf.newKill(name)
  if not KillPerf.enabled then
    return
  end
  KillPerf.killSeq = KillPerf.killSeq + 1
  currentKill = KillPerf.killSeq
  for _, entry in pairs(stats) do
    entry.perKill = 0
  end
  g_logger.info(string.format("[KillPerf] kill #%d %s", currentKill, tostring(name or "?")))
end

-- Times fn(...) under `label` and returns its results untouched.
function KillPerf.measure(label, fn, ...)
  if not KillPerf.enabled then
    return fn(...)
  end

  local startedAt = g_clock.realMicros()
  local a, b, c, d = fn(...)
  local elapsedUs = g_clock.realMicros() - startedAt

  record(label, elapsedUs)
  local entry = stats[label]
  entry.perKill = entry.perKill + 1

  if elapsedUs >= KillPerf.thresholdUs then
    local duplicate = entry.perKill > 1 and "  <-- SECOND CALL IN THE SAME KILL" or ""
    g_logger.info(string.format("[KillPerf]   %-28s %7.3f ms%s",
      label, elapsedUs / 1000, duplicate))
  elseif entry.perKill > 1 then
    g_logger.info(string.format("[KillPerf]   %-28s duplicate call in kill #%s",
      label, tostring(currentKill)))
  end

  return a, b, c, d
end

-- Wraps a function once, so it reports under `label` every time it is called.
function KillPerf.wrap(label, fn)
  if type(fn) ~= "function" then
    return fn
  end
  return function(...)
    return KillPerf.measure(label, fn, ...)
  end
end

function KillPerf.start(thresholdUs)
  KillPerf.thresholdUs = tonumber(thresholdUs) or 500
  KillPerf.enabled = true
  stats = {}
  KillPerf.killSeq = 0
  g_logger.info(string.format("[KillPerf] enabled, threshold %.3f ms", KillPerf.thresholdUs / 1000))
end

function KillPerf.stop()
  KillPerf.enabled = false
  g_logger.info("[KillPerf] disabled")
end

function KillPerf.report()
  local rows = {}
  for label, entry in pairs(stats) do
    rows[#rows + 1] = { label = label, entry = entry }
  end
  table.sort(rows, function(a, b) return a.entry.totalUs > b.entry.totalUs end)

  g_logger.info(string.format("[KillPerf] report over %d kill(s)", KillPerf.killSeq))
  g_logger.info(string.format("[KillPerf] %-28s %8s %10s %10s %10s",
    "system", "calls", "total ms", "avg ms", "max ms"))
  for _, row in ipairs(rows) do
    local e = row.entry
    g_logger.info(string.format("[KillPerf] %-28s %8d %10.3f %10.3f %10.3f",
      row.label, e.count, e.totalUs / 1000, (e.totalUs / e.count) / 1000, e.maxUs / 1000))
  end
end

function init()
end

function terminate()
  KillPerf.enabled = false
  stats = {}
end
