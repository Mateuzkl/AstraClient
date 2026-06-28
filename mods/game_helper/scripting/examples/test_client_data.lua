--[[============================================================================
  test_client_data.lua — Client static data dumps (Zerobot dialect).
  ============================================================================
  Exercises the read-only client data surface (scripting/api/client.lua):
    * Client.getAllItems()           -> array of { id, flags, ... } (LARGE)
    * Client.getAllMonsters()        -> array of { raceId, name, outfit, isBoss }
    * Client.getMonsterByRaceId(id)  -> one record, or nil
    * Client.getVersion()/getWorldName()/isConnected() -> misc client info

  ALL READ-ONLY — no mutations, so no RUN_MUTATIONS gate is needed. The item and
  monster tables can be HUGE; this script only checks the COUNT and samples 1-2
  entries (it never prints thousands of rows). Safe to load any time.
============================================================================]]

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

-- The sandbox does NOT expose a bit library (no `bit`/`bit32`), so test a single
-- bit (a power-of-two flag) in a bitmask with pure arithmetic instead.
local function hasFlag(mask, flag)
  return type(mask) == 'number' and math.floor(mask / flag) % 2 == 1
end

print('=== Client: connection / version ===')
check('Client.isConnected returns boolean', type(Client.isConnected()) == 'boolean',
  Client.isConnected())
-- getVersion is a string or nil (nil when not yet connected/unknown).
local ver = Client.getVersion()
check('Client.getVersion is string/nil', ver == nil or type(ver) == 'string', ver)
check('Client.getWorldName returns string', type(Client.getWorldName()) == 'string',
  Client.getWorldName())

print('=== Client: item appearances (count + sample only) ===')
local items = Client.getAllItems()
check('Client.getAllItems returns table', type(items) == 'table')
if type(items) == 'table' then
  print('   item appearance count: ' .. #items)
  -- Sample at most the first 2 records; assert each has id + numeric flags.
  local sample = math.min(#items, 2)
  for i = 1, sample do
    local it = items[i]
    check('item[' .. i .. '] is record', type(it) == 'table')
    if type(it) == 'table' then
      check('item[' .. i .. '].id is number', type(it.id) == 'number', it.id)
      check('item[' .. i .. '].flags is number', type(it.flags) == 'number', it.flags)
    end
  end
  -- Cross-check a flag bit using the shared Enums.ThingFlagAttr (single-bit test).
  if sample >= 1 and type(items[1]) == 'table' and type(items[1].flags) == 'number' then
    local isStackable = hasFlag(items[1].flags, Enums.ThingFlagAttr.Stackable)
    check('item[1] stackable flag readable via Enums.ThingFlagAttr',
      type(isStackable) == 'boolean', isStackable)
  end
end

print('=== Client: monster static data (count + sample only) ===')
local monsters = Client.getAllMonsters()
check('Client.getAllMonsters returns table', type(monsters) == 'table')
local firstRace = nil
if type(monsters) == 'table' then
  print('   monster count: ' .. #monsters)
  local sample = math.min(#monsters, 2)
  for i = 1, sample do
    local m = monsters[i]
    check('monster[' .. i .. '] is record', type(m) == 'table')
    if type(m) == 'table' then
      check('monster[' .. i .. '].raceId is number', type(m.raceId) == 'number', m.raceId)
      check('monster[' .. i .. '].name is string', type(m.name) == 'string', m.name)
      check('monster[' .. i .. '].outfit is table', type(m.outfit) == 'table')
      check('monster[' .. i .. '].isBoss is boolean', type(m.isBoss) == 'boolean', m.isBoss)
      if i == 1 then firstRace = m.raceId end
    end
  end
end

print('=== Client: getMonsterByRaceId ===')
-- Look up the first race we saw (round-trips through the same static data).
if firstRace then
  local one = Client.getMonsterByRaceId(firstRace)
  check('Client.getMonsterByRaceId(known) returns record', type(one) == 'table')
  if type(one) == 'table' then
    check('round-tripped raceId matches', one.raceId == firstRace, one.raceId)
    check('round-tripped record has name', type(one.name) == 'string', one.name)
  end
else
  print('   (no monsters loaded; skipping known-race lookup)')
end
-- An impossible raceId must return nil (ZB "entity does not exist").
check('Client.getMonsterByRaceId(bogus) returns nil',
  Client.getMonsterByRaceId(0x7FFFFFFF) == nil)

print(('--- Client data: %d passed, %d failed ---'):format(pass, fail))
