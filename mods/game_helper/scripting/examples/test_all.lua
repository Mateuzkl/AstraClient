--[[============================================================================
  test_all.lua  --  combined cross-namespace smoke test (Player+Map+Creature+
                    Enums+JSON working together).
  ============================================================================
  WHAT IT TESTS
    A realistic read-only "world snapshot" flow that touches every namespace in
    ONE script, the way a real bot script would:
      1. read the local player's vitals/identity (Player + Enums),
      2. scan creatures on screen (Map.getCreatureIds + Creature(cid)) and bucket
         them by type using Enums.CreatureTypes,
      3. read the camera + the tile under it (Map),
      4. serialise the whole snapshot with JSON.encode (pretty) and round-trip it
         back with JSON.decode to prove it survives.
    It is the integration counterpart to the per-namespace test_*.lua files.

  HOW TO READ THE OUTPUT
    "[PASS] <name> = <value>" / "[FAIL] <name>", then a human-readable snapshot
    dump, then the summary. Offline / empty screen still PASSES (the snapshot
    just has 0 creatures and nil-ish vitals) -- that is the correct contract.

  SAFE TO RUN ON THE LIVE CLIENT: only reads; no mutations anywhere.
============================================================================]]

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

--==========================================================================
-- 1. Player snapshot (Player + Enums)
--==========================================================================
local snapshot = {}

snapshot.player = {
  id        = Player.getId(),
  name      = Player.getName(),        -- may be nil offline
  level     = Player.getLevel(),
  hp        = Player.getHealth(),
  hpPercent = Player.getHealthPercent(),
  mana      = Player.getMana(),
  cap       = Player.getCapacity(),
  online    = Player.getId() ~= 0,
}
check('player.id is number', type(snapshot.player.id) == 'number', snapshot.player.id)
check('player.level is number', type(snapshot.player.level) == 'number', snapshot.player.level)
check('player.hpPercent in 0..100',
      snapshot.player.hpPercent >= 0 and snapshot.player.hpPercent <= 100, snapshot.player.hpPercent)

-- Classify the local player's vocation through the Enums table, just to exercise
-- it (NONE when offline). We read it off our own on-screen creature if visible.
local vocName = 'unknown'
do
  -- reverse-lookup the Vocations enum name from its value, for the dump
  local myVocValue = Enums.Vocations.NONE
  local me = snapshot.player.name and Map.getPlayerOnScreen(snapshot.player.name) or nil
  if me then
    local v = me:getVocation()
    if v then myVocValue = v end
  end
  for k, val in pairs(Enums.Vocations) do
    if val == myVocValue then vocName = k end
  end
end
snapshot.player.vocation = vocName
check('resolved a vocation enum name', type(vocName) == 'string', vocName)

--==========================================================================
-- 2. Creature scan (Map + Creature + Enums.CreatureTypes)
--==========================================================================
local counts = { players = 0, monsters = 0, npcs = 0, other = 0, total = 0 }
local sample = {}  -- a few {name, type, hp} entries for the dump

local ids = Map.getCreatureIds(false, false)
if type(ids) == 'table' then
  counts.total = #ids
  for _, cid in ipairs(ids) do
    local c = Creature(cid)
    local t = c:getType()
    if t == Enums.CreatureTypes.CREATURETYPE_PLAYER then
      counts.players = counts.players + 1
    elseif t == Enums.CreatureTypes.CREATURETYPE_MONSTER then
      counts.monsters = counts.monsters + 1
    elseif t == Enums.CreatureTypes.CREATURETYPE_NPC then
      counts.npcs = counts.npcs + 1
    else
      counts.other = counts.other + 1
    end
    if #sample < 5 then
      sample[#sample + 1] = {
        name = c:getName() or '?',
        type = t,                       -- a ZB CreatureTypes value or nil
        hp   = c:getHealthPercent(),    -- 0..100 or nil
      }
    end
  end
end
snapshot.creatures = { counts = counts, sample = sample }

check('creature counts sum to total',
      counts.players + counts.monsters + counts.npcs + counts.other == counts.total,
      ('%d+%d+%d+%d == %d'):format(counts.players, counts.monsters, counts.npcs, counts.other, counts.total))
check('sample size <= 5', #sample <= 5, #sample)

--==========================================================================
-- 3. Camera + tile under it (Map)
--==========================================================================
local cam = Map.getCameraPosition()
if type(cam) == 'table' then
  snapshot.camera = { x = cam.x, y = cam.y, z = cam.z }
  snapshot.cameraTile = {
    topItemId   = Map.getTopItemId(cam.x, cam.y, cam.z),     -- number or nil
    topCreature = Map.getTopCreatureId(cam.x, cam.y, cam.z), -- number or nil
    walkable    = Map.isTileWalkable(cam.x, cam.y, cam.z),   -- bool
    thingsCount = Map.getThingsCount(cam.x, cam.y, cam.z),   -- number or nil
  }
  check('camera tile walkable is bool', type(snapshot.cameraTile.walkable) == 'boolean',
        snapshot.cameraTile.walkable)
else
  snapshot.camera = false
  print('[info] no camera/map data (offline) -- snapshot.camera = false')
end

--==========================================================================
-- 4. Serialise the snapshot (JSON) and round-trip it back.
--    JSON can't encode a nil/sentinel cleanly, so normalise nils to false
--    before encoding (rxi drops nils inside tables anyway; we keep it simple).
--==========================================================================
local function nilsafe(tbl)
  -- shallow copy turning nil-prone scalar leaves into false so the round-trip
  -- comparison is total; nested tables are copied recursively.
  local out = {}
  for k, v in pairs(tbl) do
    if type(v) == 'table' then
      out[k] = nilsafe(v)
    else
      out[k] = v
    end
  end
  return out
end

local safe = nilsafe(snapshot)
local encoded = JSON.encode(safe, 2)
check('snapshot encodes to a string', type(encoded) == 'string')
check('  encoded is pretty (has newline)', type(encoded) == 'string' and encoded:find('\n') ~= nil)

local back = JSON.decode(encoded)
check('snapshot decodes back to a table', type(back) == 'table')
check('  round-trip kept player.id', back.player and back.player.id == snapshot.player.id,
      back.player and back.player.id)
check('  round-trip kept player.level', back.player and back.player.level == snapshot.player.level,
      back.player and back.player.level)
check('  round-trip kept creature total', back.creatures and back.creatures.counts and
      back.creatures.counts.total == counts.total, back.creatures and back.creatures.counts and
      back.creatures.counts.total)
check('  round-trip kept vocation name', back.player and back.player.vocation == vocName,
      back.player and back.player.vocation)

--==========================================================================
-- Human-readable dump (so running it in the console is informative).
--==========================================================================
print('---------------- WORLD SNAPSHOT ----------------')
print(('player : %s  lvl %d  hp %d%%  voc %s  online=%s'):format(
  tostring(snapshot.player.name), snapshot.player.level, snapshot.player.hpPercent,
  vocName, tostring(snapshot.player.online)))
print(('on-screen: total=%d players=%d monsters=%d npcs=%d other=%d'):format(
  counts.total, counts.players, counts.monsters, counts.npcs, counts.other))
for i, s in ipairs(sample) do
  print(('  [%d] %-20s type=%s hp=%s'):format(i, s.name, tostring(s.type), tostring(s.hp)))
end
if type(cam) == 'table' then
  print(('camera : %d,%d,%d  walkable=%s  topItem=%s'):format(
    cam.x, cam.y, cam.z, tostring(snapshot.cameraTile.walkable),
    tostring(snapshot.cameraTile.topItemId)))
end
print('------------------------------------------------')

print(('--- combined: %d passed, %d failed ---'):format(pass, fail))
