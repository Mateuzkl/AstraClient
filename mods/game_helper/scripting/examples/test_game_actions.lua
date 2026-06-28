--[[============================================================================
  test_game_actions.lua - Zerobot-style GAME namespace: ACTIONS (mutating)
  ============================================================================

  WHAT THIS TESTS
    The mutating half of the `Game` namespace - the calls that actually send a
    packet to the server: turn, walk, talk/talkChannel/talkPrivate, attack,
    follow, useItem*, equipItem, lootCorpse, openChannel.

    Because these CHANGE THE GAME, they are ALL gated behind a single flag:

        local RUN_MUTATIONS = false

    With the flag OFF (the default) the script does NOT touch the game: every
    action is replaced by a "would call X(args)" print, and where it is safe we
    still assert the call exists and is callable. Flip the flag to true ONLY if
    you actually want these to run against the live server.

  HOW TO READ THE OUTPUT
    [PASS]/[FAIL] lines, then a summary:
        --- game actions: <P> passed, <F> failed ---
    With RUN_MUTATIONS=false you will also see "[would]" lines documenting the
    exact call each action maps to.

  SAFETY
    Default is SAFE (no packets). The only thing that talks to the server is the
    optional chat smoke-test, which is itself gated behind RUN_MUTATIONS AND a
    second TEST_CHANNEL_ID you must set to a real, harmless channel.
============================================================================]]

-- ---------------------------------------------------------------------------
-- Assertion helper
-- ---------------------------------------------------------------------------
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

-- ===========================================================================
-- MUTATION GATE - keep false to run with zero risk.
-- ===========================================================================
local RUN_MUTATIONS = false

-- Optional REAL chat test (only used when RUN_MUTATIONS is also true). Set this
-- to a channel id you have open and that is harmless to post a line into; leave
-- nil to skip the real chat test entirely.
local TEST_CHANNEL_ID = nil

print('=== Game actions (mutating, gated) ===')
print('RUN_MUTATIONS = ' .. tostring(RUN_MUTATIONS))

-- would(name, fn) : when mutations are off, just log the intended call and count
-- it as a PASS (we verified the function is present & callable). When on, run it
-- and report the engine's true/false/nil result.
local function would(name, fn)
  if not RUN_MUTATIONS then
    print('[would] ' .. name)
    check(name .. ' (callable, gated)', type(fn) == 'function')
    return
  end
  local ok, res = pcall(fn)
  check(name .. ' executed (no error)', ok, ok and tostring(res) or res)
end

-- ---------------------------------------------------------------------------
-- 0) Presence check: every action wrapper must exist on the Game namespace
--    even when offline. This is a pure read of the API surface (safe).
-- ---------------------------------------------------------------------------
local actionNames = {
  'turn', 'walk', 'talk', 'talkChannel', 'talkPrivate', 'openChannel',
  'attack', 'follow', 'useItem', 'useItemOnGround', 'useItemOnInventory',
  'useItemFromGround', 'useItemWithCreature', 'equipItem', 'lootCorpse',
}
for _, n in ipairs(actionNames) do
  check('Game.' .. n .. ' exists', type(Game[n]) == 'function')
end

-- ---------------------------------------------------------------------------
-- 1) Movement: turn / walk. Direction values come from Enums.Directions.
-- ---------------------------------------------------------------------------
would('Game.turn(NORTH)', function() return Game.turn(Enums.Directions.NORTH) end)
would('Game.walk(EAST)',  function() return Game.walk(Enums.Directions.EAST) end)

-- ---------------------------------------------------------------------------
-- 2) Chat: talk / talkChannel / talkPrivate.
--    SAY-type talk to the default channel is the least intrusive.
-- ---------------------------------------------------------------------------
would('Game.talk("test", SAY)', function()
  return Game.talk('scripting api test', Enums.TalkTypes.TALKTYPE_SAY)
end)
would('Game.talkPrivate("hi", "Self")', function()
  -- A private message to yourself is the safest demo target.
  return Game.talkPrivate('scripting api self-test', Player.getName() or 'NoName')
end)

-- ---------------------------------------------------------------------------
-- 3) Combat: attack / follow your current target (if any). Uses your own
--    Player.getTargetId(), so it never invents a creature id.
-- ---------------------------------------------------------------------------
local myTarget = Player.getTargetId()
print('       current target id = ' .. tostring(myTarget))
would('Game.attack(currentTarget)', function() return Game.attack(myTarget) end)
would('Game.follow(currentTarget)', function() return Game.follow(myTarget) end)

-- ---------------------------------------------------------------------------
-- 4) Item use / equip. We DO NOT pick a random item id; we reuse whatever is
--    already in the first equipped slot so the "would" line is meaningful.
-- ---------------------------------------------------------------------------
local inv = Game.getInventoryItems()
local sampleId = (inv[1] and inv[1].id) or nil
print('       sample equipped item id = ' .. tostring(sampleId))
if sampleId then
  would('Game.useItem(sampleId)',   function() return Game.useItem(sampleId) end)
  would('Game.equipItem(sampleId)', function() return Game.equipItem(sampleId, 0) end)
else
  print('[skip] no equipped item to demo useItem/equipItem')
end

-- ---------------------------------------------------------------------------
-- 5) Positional actions. Coords here are illustrative placeholders - the engine
--    returns nil for absent tiles, so an un-gated run is still well-behaved.
--    (A real script would source coords from Map.* / a Creature handle.)
-- ---------------------------------------------------------------------------
would('Game.useItemFromGround(x,y,z)', function()
  return Game.useItemFromGround(100, 100, 7)
end)
would('Game.lootCorpse(x,y,z)', function()
  return Game.lootCorpse(100, 100, 7)
end)

-- ---------------------------------------------------------------------------
-- 6) Channels
-- ---------------------------------------------------------------------------
would('Game.openChannel(0)', function() return Game.openChannel(0) end)

-- ---------------------------------------------------------------------------
-- 7) OPTIONAL real chat smoke-test - the ONE call here that can actually post
--    to a live server. Doubly gated: RUN_MUTATIONS must be true AND you must
--    set TEST_CHANNEL_ID above to a real channel.
-- ---------------------------------------------------------------------------
if RUN_MUTATIONS and TEST_CHANNEL_ID ~= nil then
  local sent = Game.talkChannel('[scripting api] hello from example 02', TEST_CHANNEL_ID)
  check('real Game.talkChannel sent', sent == true, tostring(sent))
else
  print('[skip] real chat test (set RUN_MUTATIONS=true and TEST_CHANNEL_ID)')
end

print(('--- game actions: %d passed, %d failed ---'):format(pass, fail))
