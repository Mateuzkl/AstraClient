--[[============================================================================
  test_game_queries.lua - Zerobot-style GAME namespace: QUERIES (read-only)
  ============================================================================

  WHAT THIS TESTS
    The non-mutating half of the `Game` namespace: inventory queries
    (Game.getItemCount / Game.getInventoryItems) and the cached store/coin
    balances. These never change game state, so they are SAFE to run live.

  HOW TO READ THE OUTPUT
    Open the Scripting tab's debug console (the "Open Debug" button). Each
    assertion prints one line:
        [PASS] <name>            -> the check held (with the value when useful)
        [FAIL] <name>            -> the check did not hold; investigate
    The final line is a summary:
        --- game queries: <P> passed, <F> failed ---
    Run this while OFFLINE first (everything should still PASS with zeros/empty
    tables - the API returns safe defaults), then again while in-game to see
    real values.

  SAFETY
    Read-only. No flag needed. Nothing here sends a packet to the server.
============================================================================]]

-- ---------------------------------------------------------------------------
-- Assertion helper (shared pattern across all example scripts)
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

print('=== Game queries (read-only) ===')

-- ---------------------------------------------------------------------------
-- 1) Game.getInventoryItems() -> array of {id,count,tier}
--    Always a table (empty when offline / nothing equipped).
-- ---------------------------------------------------------------------------
local items = Game.getInventoryItems()
check('getInventoryItems returns a table', type(items) == 'table')

local equippedCount = #items
check('getInventoryItems count is a number', type(equippedCount) == 'number', equippedCount)

-- Every entry must have the documented {id,count,tier} shape.
local shapeOk = true
local firstId = nil
for _, it in ipairs(items) do
  if type(it) ~= 'table'
     or type(it.id) ~= 'number'
     or type(it.count) ~= 'number'
     or type(it.tier) ~= 'number' then
    shapeOk = false
    break
  end
  firstId = firstId or it.id
end
check('each inventory item has {id,count,tier}', shapeOk)
if firstId then
  print('       first equipped item id = ' .. tostring(firstId))
end

-- ---------------------------------------------------------------------------
-- 2) Game.getItemCount(itemId [, tier]) -> number (0 when none / offline)
--    Cross-checked against the equipped set: counting the first equipped
--    item's id must be >= the number of times it appears equipped.
-- ---------------------------------------------------------------------------
local cntUnknown = Game.getItemCount(0xFFFFFF) -- id that cannot exist
check('getItemCount(impossible id) is a number', type(cntUnknown) == 'number', cntUnknown)
check('getItemCount(impossible id) == 0', cntUnknown == 0)

if firstId then
  local equippedOfFirst = 0
  for _, it in ipairs(items) do
    if it.id == firstId then equippedOfFirst = equippedOfFirst + (it.count or 1) end
  end
  local total = Game.getItemCount(firstId)
  check('getItemCount(firstId) is a number', type(total) == 'number', total)
  -- The whole-inventory count must cover at least the equipped copies.
  check('getItemCount(firstId) >= equipped copies', total >= equippedOfFirst,
        total .. ' >= ' .. equippedOfFirst)

  -- The optional tier arg must not error and stays a number (the engine count
  -- is not tier-segmented, so it falls back to the untiered total).
  local tieredTotal = Game.getItemCount(firstId, 1)
  check('getItemCount(firstId, tier) is a number', type(tieredTotal) == 'number', tieredTotal)
end

-- ---------------------------------------------------------------------------
-- 3) Store / coin balances - cached engine values, always numbers.
-- ---------------------------------------------------------------------------
local tc = Game.storeGetTibiaCoinsBalance()
check('storeGetTibiaCoinsBalance is a number', type(tc) == 'number', tc)

local ttc = Game.storeGetTransferableCoinsBalance()
check('storeGetTransferableCoinsBalance is a number', type(ttc) == 'number', ttc)
-- Transferable coins are a subset of total coins, never more.
check('transferable <= total tibia coins', ttc <= tc, ttc .. ' <= ' .. tc)

-- ---------------------------------------------------------------------------
-- 4) Game.getChannelsHistory() - honest empty result in Phase 1.
-- ---------------------------------------------------------------------------
local hist = Game.getChannelsHistory()
check('getChannelsHistory returns a table', type(hist) == 'table', #hist)

print(('--- game queries: %d passed, %d failed ---'):format(pass, fail))
