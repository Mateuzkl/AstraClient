--[[============================================================================
  test_cavebot.lua — CaveBot waypoint/status surface (Zerobot dialect).
  ============================================================================
  Exercises the CaveBot.* surface (scripting/api/cavebot.lua):
    * QUERIES (always safe):
        CaveBot.getWaypointsCount()        -> number
        CaveBot.getWaypoints()             -> array of { x, y, z, type, data }
        CaveBot.getSelectedWaypointId()    -> index, or -1
        CaveBot.getWaypointTypeById(id)    -> ZB type, or -1
        CaveBot.getWaypointDataById(id)    -> { x, y, z, type, data } | nil
        CaveBot.isDebugEnabled()           -> bool
        CaveBot.getCoreTeleportIds()       -> table
        CaveBot.getLureSettings() / getSafetyLureSettings() -> tables
        CaveBot.getRefillList()            -> string
    * MUTATIONS (gated): GoTo / addWaypoint / setWalkMode / pause / clearWaypoints
      drive the LIVE cavebot (movement, waypoint list). All behind RUN_MUTATIONS
      (default false -> only print "would call X"). Flip to true with care: these
      MOVE your character / edit the active route.

  Read-only by default. Safe to load on a running character.
============================================================================]]

local RUN_MUTATIONS = false   -- keep false: GoTo/addWaypoint/etc. drive the cavebot.

local pass, fail = 0, 0
local function check(name, cond, extra)
  if cond then
    pass = pass + 1
    print('[PASS] ' .. name .. (extra and (' = ' .. tostring(extra)) or ''))
  else
    fail = fail + 1
    print('[FAIL] ' .. name)
  end
end

local function mutate(label, fn)
  if RUN_MUTATIONS then
    fn()
    print('[MUTATE] ' .. label)
  else
    print('[SKIP] would call ' .. label .. ' (RUN_MUTATIONS=false)')
  end
end

print('=== CaveBot: status / waypoint queries ===')

-- Waypoint count: a number (0 when no route / engine not loaded).
local count = CaveBot.getWaypointsCount()
check('CaveBot.getWaypointsCount returns number', type(count) == 'number', count)

-- Selected waypoint id: a number; -1 when nothing selected.
local sel = CaveBot.getSelectedWaypointId()
check('CaveBot.getSelectedWaypointId returns number', type(sel) == 'number', sel)

-- Full waypoint list: an array. Sample at most the first 2 entries so a long
-- route does not flood the console.
local wps = CaveBot.getWaypoints()
check('CaveBot.getWaypoints returns table', type(wps) == 'table')
if type(wps) == 'table' then
  check('CaveBot.getWaypoints length matches count', #wps == count, #wps)
  local sample = math.min(#wps, 2)
  for i = 1, sample do
    local wp = wps[i]
    check('waypoint[' .. i .. '] is a record', type(wp) == 'table')
    if type(wp) == 'table' then
      check('waypoint[' .. i .. '].type is number', type(wp.type) == 'number', wp.type)
      print(('   wp[%d]: type=%s pos=%s,%s,%s data=%s'):format(
        i, tostring(wp.type), tostring(wp.x), tostring(wp.y), tostring(wp.z),
        tostring(wp.data)))
    end
  end
end

-- Type/data lookup by id: id 1 is the first slot when a route exists; otherwise
-- the getters return -1 / nil cleanly.
if count >= 1 then
  local t = CaveBot.getWaypointTypeById(1)
  check('CaveBot.getWaypointTypeById(1) is number', type(t) == 'number', t)
  local d = CaveBot.getWaypointDataById(1)
  check('CaveBot.getWaypointDataById(1) is table/nil', d == nil or type(d) == 'table')
else
  check('CaveBot.getWaypointTypeById on empty route is -1', CaveBot.getWaypointTypeById(1) == -1)
  check('CaveBot.getWaypointDataById on empty route is nil', CaveBot.getWaypointDataById(1) == nil)
end

print('=== CaveBot: config queries ===')

check('CaveBot.isDebugEnabled returns boolean', type(CaveBot.isDebugEnabled()) == 'boolean',
  CaveBot.isDebugEnabled())
check('CaveBot.getCoreTeleportIds returns table', type(CaveBot.getCoreTeleportIds()) == 'table')

local lure = CaveBot.getLureSettings()
check('CaveBot.getLureSettings returns table', type(lure) == 'table')
if type(lure) == 'table' then
  check('lure.dynamicLure is boolean', type(lure.dynamicLure) == 'boolean', lure.dynamicLure)
end

local safety = CaveBot.getSafetyLureSettings()
check('CaveBot.getSafetyLureSettings returns table', type(safety) == 'table')

check('CaveBot.getRefillList returns string', type(CaveBot.getRefillList()) == 'string')

print('=== CaveBot: navigation / CRUD (gated) ===')

-- Existence of the action-side surface (callable regardless of the gate).
for _, fnName in ipairs({ 'GoTo', 'addWaypoint', 'setWalkMode', 'pause', 'clearWaypoints' }) do
  check('CaveBot.' .. fnName .. ' exists', type(CaveBot[fnName]) == 'function')
end

-- pause(0) means RESUME in ZB semantics — the least invasive mutation, so we use
-- it as the gated demo. With the gate off it only prints intent.
mutate('CaveBot.pause(0) [resume]', function() CaveBot.pause(0) end)

-- A genuinely state-changing call shown but never run unless RUN_MUTATIONS:
mutate('CaveBot.setWalkMode(MAP_CLICK)',
  function() CaveBot.setWalkMode(Enums.WalkMode.MAP_CLICK) end)

-- We do NOT add/clear waypoints in a read-only smoke test; just announce.
print('[SKIP] addWaypoint/clearWaypoints intentionally not invoked (route-editing)')

print(('--- CaveBot: %d passed, %d failed ---'):format(pass, fail))
