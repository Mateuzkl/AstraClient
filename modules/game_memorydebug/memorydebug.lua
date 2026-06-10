-- modules/game_memorydebug/memorydebug.lua
-- Memory debug module: logs memory usage stats periodically and on demand
-- Usage: in Lua console type: dumpMemoryStats()

local memoryDebugEvent = nil
local LOG_INTERVAL = 30000 -- 30 seconds
local enabled = false

local function collectStats()
  local stats = {
    mapTiles = 0,
    ram = collectgarbage("count"),
    textures = 0,
    creatures = 0,
  }

  pcall(function()
    for z = 0, 15 do
      stats.mapTiles = stats.mapTiles + #g_map.getTiles(z)
    end
    local localPlayer = g_game.getLocalPlayer()
    if localPlayer then
      stats.creatures = #g_map.getSpectators(localPlayer:getPosition(), true)
    end
  end)

  return stats
end

local function logStats()
  local stats = collectStats()
  print(string.format("[MEM] RAM(Lua): %.1f MB | Tiles: %d | Creatures: %d",
    stats.ram / 1024, stats.mapTiles, stats.creatures))
end

function init()
end

function terminate()
  if memoryDebugEvent then
    removeEvent(memoryDebugEvent)
    memoryDebugEvent = nil
  end
  enabled = false
end

function dumpMemoryStats()
  local stats = collectStats()
  g_logger.info(string.format("=== Memory Debug Dump ==="))
  g_logger.info(string.format("  Lua RAM: %.1f MB", stats.ram / 1024))
  g_logger.info(string.format("  Map Tiles: %d", stats.mapTiles))
  g_logger.info(string.format("  Known Creatures: %d", stats.creatures))
  g_logger.info(string.format("=========================="))
  print(string.format("[MEM] Lua: %.1f MB | Tiles: %d | Creatures: %d",
    stats.ram / 1024, stats.mapTiles, stats.creatures))
end

function startPeriodicLog()
  if enabled then return end
  enabled = true
  local function loop()
    if not enabled then return end
    logStats()
    memoryDebugEvent = scheduleEvent(loop, LOG_INTERVAL)
  end
  loop()
end

function stopPeriodicLog()
  enabled = false
  if memoryDebugEvent then
    removeEvent(memoryDebugEvent)
    memoryDebugEvent = nil
  end
end

-- expose to console
_dumpMemoryStats = dumpMemoryStats
_startMemLog = startPeriodicLog
_stopMemLog = stopPeriodicLog
