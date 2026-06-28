--[[============================================================================
  test_map.lua  --  read-only smoke test for the `Map` namespace.
  ============================================================================
  WHAT IT TESTS
    The QUERY half of Map: getCreatureIds, getTiles, getThings/getThingsCount,
    getTopItemId/getTopCreatureId, getCameraPosition, getPlayerOnScreen,
    isTileWalkable/canWalk, getAllPositionsWithTopItemId. It derives a real
    on-screen position from the camera so the per-tile getters have something to
    look at. ALL move/use/goTo/browseField/collectRewardChest calls are
    MUTATIONS and stay behind RUN_MUTATIONS (default OFF) -- when off they only
    print "would call X", they never touch the server.

  HOW TO READ THE OUTPUT
    "[PASS] <name> = <value>" / "[FAIL] <name>". Remember the Map return
    contract: nil = no tile / no map data there; a value = data present. So
    OFFLINE (no map) most getters return nil and the "nil-or-<type>" checks
    PASS -- that is correct, not a failure. Summary line at the end.

  SAFE TO RUN ON THE LIVE CLIENT: only reads (mutations gated OFF).
============================================================================]]

-- Map has many MUTATORS (moveItem*, moveCreature*, useItem*, goTo, browseField,
-- collectRewardChest). Keep them OFF. When true, this script still only PRINTS
-- the call it would make (it does not uncomment the real send).
local RUN_MUTATIONS = false

local pass, fail = 0, 0
local function check(name, cond, extra)
  if cond then
    pass = pass + 1
    print('[PASS] ' .. name .. (extra ~= nil and (' = ' .. tostring(extra)) or ''))
  else
    fail = fail + 1
    print('[FAIL] ' .. name)
  end
end

local function isNumOrNil(v) return v == nil or type(v) == 'number' end
local function isTblOrNil(v) return v == nil or type(v) == 'table' end

--==========================================================================
-- Camera position -- our anchor for the per-tile getters below.
--==========================================================================
local cam = Map.getCameraPosition()
check('getCameraPosition is {x,y,z}-or-nil', isTblOrNil(cam))
if type(cam) == 'table' then
  check('  cam has numeric x,y,z',
        type(cam.x) == 'number' and type(cam.y) == 'number' and type(cam.z) == 'number',
        ('%d,%d,%d'):format(cam.x or -1, cam.y or -1, cam.z or -1))
end

--==========================================================================
-- Creatures on screen.
--==========================================================================
local all = Map.getCreatureIds(false, false)
check('getCreatureIds(false,false) table-or-nil', isTblOrNil(all))
local players = Map.getCreatureIds(true, true) -- same floor, players only
check('getCreatureIds(true,true) table-or-nil', isTblOrNil(players))
-- Players-only set can never be larger than the full set.
if type(all) == 'table' and type(players) == 'table' then
  check('  players-only count <= all count', #players <= #all,
        ('%d <= %d'):format(#players, #all))
end

--==========================================================================
-- All on-screen tiles (getTiles always returns a TABLE, possibly empty).
--==========================================================================
local tiles = Map.getTiles()
check('getTiles is a table (never nil)', type(tiles) == 'table', tiles and #tiles)
if type(tiles) == 'table' and #tiles > 0 then
  local t = tiles[1]
  check('  tile[1] has numeric x,y,z',
        type(t.x) == 'number' and type(t.y) == 'number' and type(t.z) == 'number')
  check('  tile[1].things is a table', type(t.things) == 'table', #t.things)
end

--==========================================================================
-- Per-tile getters anchored at the camera (only meaningful with map data).
--==========================================================================
if type(cam) == 'table' and type(cam.x) == 'number' then
  local x, y, z = cam.x, cam.y, cam.z

  local things = Map.getThings(x, y, z)
  check('getThings(cam) table-or-nil', isTblOrNil(things), things and #things)

  local cnt = Map.getThingsCount(x, y, z)
  check('getThingsCount(cam) number-or-nil', isNumOrNil(cnt), cnt)

  -- If both are present they should agree on the count.
  if type(things) == 'table' and type(cnt) == 'number' then
    check('  getThingsCount matches #getThings', cnt == #things,
          ('%d == %d'):format(cnt, #things))
  end

  check('getTopItemId(cam) number-or-nil', isNumOrNil(Map.getTopItemId(x, y, z)), Map.getTopItemId(x, y, z))
  check('getTopCreatureId(cam) number-or-nil', isNumOrNil(Map.getTopCreatureId(x, y, z)), Map.getTopCreatureId(x, y, z))

  -- isTileWalkable always returns a plain bool (never nil per the contract).
  local w = Map.isTileWalkable(x, y, z)
  check('isTileWalkable(cam) is bool', type(w) == 'boolean', w)
  -- with explicit options
  local w2 = Map.isTileWalkable(x, y, z, { ignoreMonsters = true, ignoreNpcs = true })
  check('isTileWalkable(cam, opts) is bool', type(w2) == 'boolean', w2)
  -- deprecated canWalk wrapper -> still a bool
  local w3 = Map.canWalk(x, y, z)
  check('canWalk(cam) is bool (deprecated path)', type(w3) == 'boolean', w3)
else
  print('[info] No camera/map data -- skipping per-tile getters (offline). nil contract still verified above.')
end

--==========================================================================
-- A position with definitely no map data: every getter must return nil.
--==========================================================================
local fx, fy, fz = 1, 1, 0 -- corner of the map; no tile cached here
check('getThings(faraway) is nil', Map.getThings(fx, fy, fz) == nil)
check('getThingsCount(faraway) is nil', Map.getThingsCount(fx, fy, fz) == nil)
check('getTopItemId(faraway) is nil', Map.getTopItemId(fx, fy, fz) == nil)
check('getTopCreatureId(faraway) is nil', Map.getTopCreatureId(fx, fy, fz) == nil)

--==========================================================================
-- getAllPositionsWithTopItemId: gold coin (id 3031) is a common ground item.
-- Returns a list of {x,y,z} or nil if none on screen -- both are valid.
--==========================================================================
local goldPositions = Map.getAllPositionsWithTopItemId(3031, true)
check('getAllPositionsWithTopItemId(gold) table-or-nil', isTblOrNil(goldPositions),
      type(goldPositions) == 'table' and #goldPositions or 'nil')
if type(goldPositions) == 'table' and #goldPositions > 0 then
  local p = goldPositions[1]
  check('  result[1] is {x,y,z}',
        type(p.x) == 'number' and type(p.y) == 'number' and type(p.z) == 'number')
end

--==========================================================================
-- getPlayerOnScreen by a name that won't exist -> nil; by self name -> handle.
--==========================================================================
check('getPlayerOnScreen(bogus name) is nil',
      Map.getPlayerOnScreen('___no_such_player_zzz___') == nil)
check('getPlayerOnScreen(non-string/number junk) is nil',
      Map.getPlayerOnScreen(true) == nil)

--==========================================================================
-- Mutations -- OFF by default. Describe only; never send.
--==========================================================================
if RUN_MUTATIONS then
  local x, y, z = 0, 0, 0
  if type(cam) == 'table' then x, y, z = cam.x, cam.y, cam.z end
  print(('[MUT] would call Map.goTo(%d,%d,%d)'):format(x, y, z))
  -- Map.goTo(x, y, z)
  print(('[MUT] would call Map.browseField(%d,%d,%d)'):format(x, y, z))
  -- Map.browseField(x, y, z)
  print('[MUT] would call Map.moveItemToInventory(...) / moveItemToGround(...) -- NOT sent')
else
  print('[skip] map mutations OFF (set RUN_MUTATIONS=true to print would-call lines)')
end

print(('--- map: %d passed, %d failed ---'):format(pass, fail))
