--[[============================================================================
  test_player.lua  --  read-only smoke test for the `Player` namespace.
  ============================================================================
  WHAT IT TESTS
    Every QUERY function on the sandbox `Player` table (getHealth/getMana/
    getLevel/getPosition-via-vitals, getSkills, getInventorySlot, getState,
    getContainers, resources, premium/monk getters...). It NEVER mutates game
    state: the party/leave functions are only described, never called (they are
    guarded behind RUN_MUTATIONS, default OFF).

  HOW TO READ THE OUTPUT
    Each line is "[PASS] <name> = <value>" or "[FAIL] <name>". A PASS means the
    function returned a value of the EXPECTED SHAPE for the current situation
    (e.g. a number for getHealth, nil-or-table for getInventorySlot). When you
    are OFFLINE most getters return the documented "offline" value (0 / nil /
    false) and those PASS too -- that is correct Zerobot semantics, not a bug.
    The final "--- player: N passed, M failed ---" line is the summary.

  SAFE TO RUN ON THE LIVE CLIENT: only reads.
============================================================================]]

-- Mutations are OFF by default. The only Player mutators are party actions
-- (join/invite/leave/shared-exp/leadership); flipping this true would still
-- only PRINT what would be called -- it never actually sends them here.
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

-- Small predicates so the intent of each check reads clearly.
local function isNum(v) return type(v) == 'number' end
local function isNumOrNil(v) return v == nil or type(v) == 'number' end
local function isStrOrNil(v) return v == nil or type(v) == 'string' end
local function isBool(v) return type(v) == 'boolean' end
local function isTblOrNil(v) return v == nil or type(v) == 'table' end

local online = Player.getId() ~= 0
print('Player online? ' .. tostring(online) .. ' (offline getters return 0/nil/false -- that is correct)')

--==========================================================================
-- Identity / vitals
--==========================================================================
check('getId is number', isNum(Player.getId()), Player.getId())
check('getName is string-or-nil', isStrOrNil(Player.getName()), Player.getName())
check('getHealth is number', isNum(Player.getHealth()), Player.getHealth())
check('getMana is number', isNum(Player.getMana()), Player.getMana())

local hpPct = Player.getHealthPercent()
check('getHealthPercent in 0..100', isNum(hpPct) and hpPct >= 0 and hpPct <= 100, hpPct)
local mpPct = Player.getManaPercent()
check('getManaPercent in 0..100', isNum(mpPct) and mpPct >= 0 and mpPct <= 100, mpPct)

check('getMagicShield is number', isNum(Player.getMagicShield()), Player.getMagicShield())
check('getMaxMagicShield is number', isNum(Player.getMaxMagicShield()), Player.getMaxMagicShield())
check('getCapacity is number', isNum(Player.getCapacity()), Player.getCapacity())
check('getSoulPoints is number', isNum(Player.getSoulPoints()), Player.getSoulPoints())
check('getStamina is number (minutes)', isNum(Player.getStamina()), Player.getStamina())

--==========================================================================
-- Level / experience
--==========================================================================
check('getLevel is number', isNum(Player.getLevel()), Player.getLevel())
local lvlPct = Player.getLevelPercent()
check('getLevelPercent in 0..100', isNum(lvlPct) and lvlPct >= 0 and lvlPct <= 100, lvlPct)
check('getExperience is number', isNum(Player.getExperience()), Player.getExperience())
check('getXpBoostTime is number (seconds)', isNum(Player.getXpBoostTime()), Player.getXpBoostTime())

--==========================================================================
-- Skills (table with the full ZB field set, or nil offline)
--==========================================================================
local skills = Player.getSkills()
check('getSkills is table-or-nil', isTblOrNil(skills))
if type(skills) == 'table' then
  -- spot-check the documented fields exist and are numeric
  check('  skills.magic is number', isNum(skills.magic), skills.magic)
  check('  skills.sword is number', isNum(skills.sword), skills.sword)
  check('  skills.distance is number', isNum(skills.distance), skills.distance)
  check('  skills.shield is number', isNum(skills.shield), skills.shield)
  check('  skills.criticalChance is number', isNum(skills.criticalChance), skills.criticalChance)
  check('  skills.lifeLeechChance is number', isNum(skills.lifeLeechChance), skills.lifeLeechChance)
  check('  skills.fishingPercent in 0..100',
        isNum(skills.fishingPercent) and skills.fishingPercent >= 0 and skills.fishingPercent <= 100,
        skills.fishingPercent)
else
  print('  (getSkills nil -- offline or basic data not received yet; OK)')
end

--==========================================================================
-- Targeting / following  (ids, 0 when none)
--==========================================================================
check('getTargetId is number', isNum(Player.getTargetId()), Player.getTargetId())
check('getFollowId is number', isNum(Player.getFollowId()), Player.getFollowId())

--==========================================================================
-- Inventory / state / containers
--==========================================================================
-- Backpack slot via the Enums.InventorySlot constant (no hardcoded numbers).
local bpSlot = Enums.InventorySlot.CONST_SLOT_BACKPACK
local bp = Player.getInventorySlot(bpSlot)
check('getInventorySlot(BACKPACK) is table-or-nil', isTblOrNil(bp))
if type(bp) == 'table' then
  check('  slot.id is number', isNum(bp.id), bp.id)
  check('  slot.count is number', isNum(bp.count), bp.count)
  check('  slot.tier is number', isNum(bp.tier), bp.tier)
  check('  slot.holdingCount is number', isNum(bp.holdingCount), bp.holdingCount)
end

-- getState returns bool (in-game) or nil (offline). Use a real state index.
local rooted = Player.getState(Enums.States.STATE_ROOTED)
check('getState(STATE_ROOTED) is bool-or-nil', rooted == nil or isBool(rooted), rooted)
local poison = Player.getState(Enums.States.STATE_POISON)
check('getState(STATE_POISON) is bool-or-nil', poison == nil or isBool(poison), poison)

local conts = Player.getContainers()
check('getContainers is table-or-nil', isTblOrNil(conts))
if type(conts) == 'table' then
  check('  containers list length is number', isNum(#conts), #conts)
end

--==========================================================================
-- Resources (forge dust / gold)
--==========================================================================
check('getDusts is number', isNum(Player.getDusts()), Player.getDusts())
check('getDustsMaximum is number', isNum(Player.getDustsMaximum()), Player.getDustsMaximum())
check('getTotalGoldBalance is number', isNum(Player.getTotalGoldBalance()), Player.getTotalGoldBalance())

--==========================================================================
-- Premium / blessings / monk / serene
--==========================================================================
check('isPremium is bool', isBool(Player.isPremium()), Player.isPremium())
check('hasReceivedBasicData is bool', isBool(Player.hasReceivedBasicData()), Player.hasReceivedBasicData())

-- Blessing state must be one of the Enums.BlessingState values.
local bless = Player.getBlessingState()
local B = Enums.BlessingState
check('getBlessingState is a BlessingState value',
      bless == B.UNDEFINED or bless == B.NONE or bless == B.NORMAL or bless == B.FULL, bless)

check('isSerene is bool', isBool(Player.isSerene()), Player.isSerene())
check('getHarmony is number', isNum(Player.getHarmony()), Player.getHarmony())
check('getMonkPassiveType is number', isNum(Player.getMonkPassiveType()), Player.getMonkPassiveType())
check('isHungry is bool', isBool(Player.isHungry()), Player.isHungry())

--==========================================================================
-- Server-pushed data wrappers (Fase-2 stubs return zero-filled tables/0)
--==========================================================================
local uj = Player.getUnjustifiedData()
check('getUnjustifiedData is table', type(uj) == 'table')
if type(uj) == 'table' then
  check('  uj.skullDuration is number', isNum(uj.skullDuration), uj.skullDuration)
  check('  uj.dayProgress is number', isNum(uj.dayProgress), uj.dayProgress)
end

local htp = Player.getHuntingTaskPrices()
check('getHuntingTaskPrices is table', type(htp) == 'table')
if type(htp) == 'table' then
  check('  htp.rerollPrice is number', isNum(htp.rerollPrice), htp.rerollPrice)
end
check('getHuntingPoints is number', isNum(Player.getHuntingPoints()), Player.getHuntingPoints())
check('getPreyWildcards is number', isNum(Player.getPreyWildcards()), Player.getPreyWildcards())

--==========================================================================
-- Mutations (party) -- OFF by default; describe only, never send.
--==========================================================================
if RUN_MUTATIONS then
  -- Even when enabled, we DON'T actually act on real players here; just show
  -- the calls a real script would make. Uncomment to actually run on yourself.
  print('[MUT] would call Player.leaveParty()')
  -- Player.leaveParty()
  print('[MUT] would call Player.enableSharedExpParty(true)')
  -- Player.enableSharedExpParty(true)
else
  print('[skip] party mutations OFF (set RUN_MUTATIONS=true to print would-call lines)')
end

print(('--- player: %d passed, %d failed ---'):format(pass, fail))
