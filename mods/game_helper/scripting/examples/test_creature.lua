--[[============================================================================
  test_creature.lua  --  read-only smoke test for the `Creature` class.
  ============================================================================
  WHAT IT TESTS
    Construction (`Creature(cid)` and `Creature.new(cid)`) and every instance
    GETTER (getId/getType/getName/getHealthPercent/getGuildEmblem/getPartyIcon/
    getVocation/getDirection/getPosition/getSpeed/getOutfit/getSkull/getIcon/
    getIcons). To have real creatures to inspect it uses Map.getCreatureIds()
    and wraps the first few ids; if nothing is on screen it still verifies the
    "gone creature returns nil" contract with a junk id. Pure reads only.

  HOW TO READ THE OUTPUT
    "[PASS] <name> = <value>" / "[FAIL] <name>". Methods on a LIVE creature
    return real values; methods on a non-existent id return nil BY DESIGN, and
    a check that asserts "nil-or-<type>" PASSES on nil. So when you are offline
    / no creatures visible, you'll still see PASSes for the nil contract.
    Summary at the end: "--- creature: N passed, M failed ---".

  SAFE TO RUN ON THE LIVE CLIENT: only reads (no attack/follow/move here).
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

local function isNumOrNil(v) return v == nil or type(v) == 'number' end
local function isStrOrNil(v) return v == nil or type(v) == 'string' end
local function isTblOrNil(v) return v == nil or type(v) == 'table' end

--==========================================================================
-- Construction (does NOT validate existence -- ZB parity)
--==========================================================================
local h1 = Creature(123456)        -- via __call
local h2 = Creature.new(123456)    -- explicit constructor
check('Creature(cid) builds a handle', type(h1) == 'table')
check('Creature.new(cid) builds a handle', type(h2) == 'table')
check('handle:getId() echoes the cid (no engine hit)', h1:getId() == 123456, h1:getId())

--==========================================================================
-- A guaranteed-dead id: every resolving getter must return nil.
--==========================================================================
local ghost = Creature(0x7FFFFFF0) -- almost certainly not a live creature
check('ghost:getName() is nil', ghost:getName() == nil)
check('ghost:getType() is nil', ghost:getType() == nil)
check('ghost:getHealthPercent() is nil', ghost:getHealthPercent() == nil)
check('ghost:getPosition() is nil', ghost:getPosition() == nil)
check('ghost:getOutfit() is nil', ghost:getOutfit() == nil)
check('ghost:getSkull() is nil', ghost:getSkull() == nil)

--==========================================================================
-- Real creatures on screen (if any). Inspect up to 5.
--==========================================================================
local ids = Map.getCreatureIds(false, false) -- all floors, all creatures
if type(ids) == 'table' and #ids > 0 then
  print(('Found %d creature(s) on screen; inspecting up to 5.'):format(#ids))
  local limit = math.min(5, #ids)
  for i = 1, limit do
    local cid = ids[i]
    local c = Creature(cid)
    local tag = 'cid#' .. tostring(cid)

    check(tag .. ' getId matches', c:getId() == cid, c:getId())
    check(tag .. ' getName string-or-nil', isStrOrNil(c:getName()), c:getName())

    local hp = c:getHealthPercent()
    check(tag .. ' getHealthPercent 0..100-or-nil',
          hp == nil or (type(hp) == 'number' and hp >= 0 and hp <= 100), hp)

    -- Typed getters must come back as numbers (already translated to ZB enums) or nil.
    check(tag .. ' getType num-or-nil', isNumOrNil(c:getType()), c:getType())
    check(tag .. ' getGuildEmblem num-or-nil', isNumOrNil(c:getGuildEmblem()), c:getGuildEmblem())
    check(tag .. ' getPartyIcon num-or-nil', isNumOrNil(c:getPartyIcon()), c:getPartyIcon())
    check(tag .. ' getVocation num-or-nil', isNumOrNil(c:getVocation()), c:getVocation())
    check(tag .. ' getSkull num-or-nil', isNumOrNil(c:getSkull()), c:getSkull())
    check(tag .. ' getSpeed num-or-nil', isNumOrNil(c:getSpeed()), c:getSpeed())
    check(tag .. ' getIcon num-or-nil', isNumOrNil(c:getIcon()), c:getIcon())

    -- Direction, if present, must be a valid ZB Directions value (0..7).
    local dir = c:getDirection()
    check(tag .. ' getDirection 0..7-or-nil',
          dir == nil or (type(dir) == 'number' and dir >= 0 and dir <= 7), dir)

    -- Position shape.
    local pos = c:getPosition()
    check(tag .. ' getPosition is {x,y,z}-or-nil', isTblOrNil(pos))
    if type(pos) == 'table' then
      check(tag .. '   pos has numeric x,y,z',
            type(pos.x) == 'number' and type(pos.y) == 'number' and type(pos.z) == 'number',
            ('%s,%s,%s'):format(tostring(pos.x), tostring(pos.y), tostring(pos.z)))
    end

    -- Outfit shape (ZB field set).
    local o = c:getOutfit()
    check(tag .. ' getOutfit is table-or-nil', isTblOrNil(o))
    if type(o) == 'table' then
      check(tag .. '   outfit.type is number', type(o.type) == 'number', o.type)
      check(tag .. '   outfit.addons is number', type(o.addons) == 'number', o.addons)
      check(tag .. '   outfit.mountId is number', type(o.mountId) == 'number', o.mountId)
    end

    -- getIcons: a live creature yields a table (often empty -- attached-icons
    -- feature is a Lua shim), or nil if gone.
    local icons = c:getIcons()
    check(tag .. ' getIcons is table-or-nil', isTblOrNil(icons))
  end

  --========================================================================
  -- Cross-check with Map.getPlayerOnScreen using the local player's own name,
  -- if available -- exercises Map->Creature handle return.
  --========================================================================
  local myName = Player.getName()
  if myName then
    local me = Map.getPlayerOnScreen(myName)
    -- We may or may not be classified as "on screen" by getSpectators; both are
    -- fine. If found, it must be a Creature handle resolving to our name.
    if me then
      check('getPlayerOnScreen(self) returns a handle', type(me) == 'table')
      check('  handle:getName() == my name', me:getName() == myName, me:getName())
    else
      print('[info] getPlayerOnScreen(self) returned nil (self not in spectator list) -- OK')
    end
  end
else
  print('[info] No creatures on screen (offline or empty) -- only the ghost/nil-contract checks ran.')
end

print(('--- creature: %d passed, %d failed ---'):format(pass, fail))
