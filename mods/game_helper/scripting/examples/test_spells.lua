--[[============================================================================
  test_spells.lua — spell lookup + cooldown queries (Zerobot dialect).
  ============================================================================
  Exercises the Spells.* surface (scripting/api/spells.lua):
    * Lookup (table-returning, engine DB names):
        Spells.getSpellByWords(words) -> spell table | nil
        Spells.getSpellByName(name)   -> spell table | nil
    * Lookup (ZB numeric id, or -1):
        Spells.getIdByWords(words) / Spells.getIdByName(name)
    * Cooldown queries (ledger fed by engine cooldown events):
        Spells.isInCooldown(id)               / getLeftCooldownTime(id)
        Spells.groupIsInCooldown(groupId)     / getLeftGroupCooldownTime(groupId)

  ALL READ-ONLY — no spell is cast, no state changes, so no RUN_MUTATIONS gate.
  Spell DB contents are server-specific; this script discovers a real spell from
  the live DB (when present) and round-trips it, rather than hard-coding words
  that may not exist. Safe to load any time.
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

print('=== Spells: lookup function existence ===')
for _, fnName in ipairs({
  'getSpellByWords', 'getSpellByName', 'getIdByWords', 'getIdByName',
  'isInCooldown', 'getLeftCooldownTime', 'groupIsInCooldown', 'getLeftGroupCooldownTime',
}) do
  check('Spells.' .. fnName .. ' exists', type(Spells[fnName]) == 'function')
end

print('=== Spells: bad-input guards (no crash on non-string) ===')
-- The engine DB functions crash on a non-string; the wrapper must guard them.
check('getSpellByWords(nil) -> nil', Spells.getSpellByWords(nil) == nil)
check('getSpellByWords("") -> nil', Spells.getSpellByWords('') == nil)
check('getSpellByName(nil) -> nil', Spells.getSpellByName(nil) == nil)
check('getIdByWords(nil) -> -1', Spells.getIdByWords(nil) == -1)
check('getIdByName("") -> -1', Spells.getIdByName('') == -1)
-- A clearly-nonexistent spell must miss cleanly.
check('getSpellByWords(bogus) -> nil', Spells.getSpellByWords('zzznotaspell') == nil)
check('getIdByName(bogus) -> -1', Spells.getIdByName('Definitely Not A Spell') == -1)

print('=== Spells: discover a real spell from the live DB ===')
-- Try a handful of very common incantations; use whichever the server actually
-- defines. We assert the SHAPE only when found (DB is server-specific).
local CANDIDATES = { 'exura', 'exori', 'utani hur', 'exevo vis hur', 'utura' }
local foundWords, foundSpell = nil, nil
for _, words in ipairs(CANDIDATES) do
  local spell = Spells.getSpellByWords(words)
  if type(spell) == 'table' then
    foundWords, foundSpell = words, spell
    break
  end
end

if foundSpell then
  print('   found spell by words: "' .. foundWords .. '"')
  check('found spell has numeric id', type(foundSpell.id) == 'number', foundSpell.id)

  -- getIdByWords must agree with the table's id.
  local idByWords = Spells.getIdByWords(foundWords)
  check('getIdByWords matches spell.id', idByWords == foundSpell.id, idByWords)

  -- If the spell carries a display name, round-trip by name too.
  if type(foundSpell.name) == 'string' and foundSpell.name ~= '' then
    local byName = Spells.getSpellByName(foundSpell.name)
    check('getSpellByName(name) returns a table', type(byName) == 'table', foundSpell.name)
    local idByName = Spells.getIdByName(foundSpell.name)
    check('getIdByName matches spell.id', idByName == foundSpell.id, idByName)
  end

  -- Cooldown queries for that real spell id: clean types, no crash. We do NOT
  -- assert in/out of cooldown (depends on whether it was just cast).
  local left = Spells.getLeftCooldownTime(foundSpell.id)
  check('getLeftCooldownTime(id) is number', type(left) == 'number', left)
  check('isInCooldown(id) is boolean', type(Spells.isInCooldown(foundSpell.id)) == 'boolean',
    Spells.isInCooldown(foundSpell.id))
  -- A spell not on cooldown reports -1 (ZB) and isInCooldown false.
  check('cooldown ledger consistent (id)',
    (left > 0) == Spells.isInCooldown(foundSpell.id))
else
  print('   (no common spell found in DB — running with offline/empty spell DB)')
  -- Even with no DB the cooldown getters must return clean values for any id.
  check('getLeftCooldownTime on arbitrary id is number',
    type(Spells.getLeftCooldownTime(1)) == 'number', Spells.getLeftCooldownTime(1))
  check('isInCooldown on arbitrary id is boolean',
    type(Spells.isInCooldown(1)) == 'boolean')
end

print('=== Spells: group cooldown queries ===')
-- Group cooldown for the ATTACK group: number remaining (-1 when idle) + boolean.
local attackGroup = Enums.SpellGroups.SPELLGROUP_ATTACK
local gleft = Spells.getLeftGroupCooldownTime(attackGroup)
check('getLeftGroupCooldownTime(ATTACK) is number', type(gleft) == 'number', gleft)
check('groupIsInCooldown(ATTACK) is boolean',
  type(Spells.groupIsInCooldown(attackGroup)) == 'boolean', Spells.groupIsInCooldown(attackGroup))
check('group cooldown ledger consistent',
  (gleft > 0) == Spells.groupIsInCooldown(attackGroup))
-- Bad-type group id is handled (-1 / false).
check('getLeftGroupCooldownTime(nil) -> -1', Spells.getLeftGroupCooldownTime(nil) == -1)
check('groupIsInCooldown(nil) -> false', Spells.groupIsInCooldown(nil) == false)

print(('--- Spells: %d passed, %d failed ---'):format(pass, fail))
