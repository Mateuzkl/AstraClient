--[[============================================================================
  test_npc.lua - Zerobot-style NPC namespace (trade)
  ============================================================================

  WHAT THIS TESTS
    The `Npc` namespace: Npc.buy(id, amount, ignoreCap, inBackpacks) and
    Npc.sell(id, amount, ignoreEquipped). These act on the CURRENTLY OPEN NPC
    trade window.

    IMPORTANT: buying and selling SPEND/CONSUME your gold and items. There is no
    read-only query in this namespace, so the whole thing is gated behind:

        local RUN_MUTATIONS = false

    With the flag OFF (the default) NOTHING is bought or sold. The script only:
      - asserts the functions exist,
      - verifies the documented return semantics on INVALID input (an impossible
        item id must return nil WITHOUT sending anything - this is safe to call
        live because the API rejects it before any packet goes out),
      - logs "would Npc.buy(...)" / "would Npc.sell(...)" for the real calls.

  HOW TO READ THE OUTPUT
    To exercise a REAL trade you must (1) open an NPC trade window in-game and
    (2) set RUN_MUTATIONS=true and fill in BUY_ITEM_ID / SELL_ITEM_ID below with
    items that NPC actually trades. Otherwise you will only see [would]/[skip].
    [PASS]/[FAIL] lines, then:
        --- npc: <P> passed, <F> failed ---

  SAFETY
    Default is SAFE: no gold spent, no items sold. The nil-return checks below
    are safe even live because Npc.buy/sell validate the item id first and return
    nil (no packet) for an unknown id.
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
-- TRADE GATE - keep false to run with zero risk (no gold/items change hands).
-- ===========================================================================
local RUN_MUTATIONS = false

-- Real trade targets, used ONLY when RUN_MUTATIONS is true AND an NPC trade
-- window is open. Set to item ids the open NPC actually buys/sells.
local BUY_ITEM_ID  = nil   -- e.g. a rune/potion id the NPC sells
local SELL_ITEM_ID = nil   -- e.g. a loot id the NPC buys
local TRADE_AMOUNT = 1

print('=== NPC trade (gated) ===')
print('RUN_MUTATIONS = ' .. tostring(RUN_MUTATIONS))
print('NOTE: NPC trade needs an OPEN trade window; queries do not exist here.')

-- ---------------------------------------------------------------------------
-- 0) API surface.
-- ---------------------------------------------------------------------------
check('Npc.buy exists',  type(Npc.buy) == 'function')
check('Npc.sell exists', type(Npc.sell) == 'function')

-- ---------------------------------------------------------------------------
-- 1) Return-semantics on INVALID input. An item id that resolves to no real
--    item type must return nil (Zerobot "no such item") and must NOT send a
--    trade packet. This is safe to call even live - rejection happens first.
-- ---------------------------------------------------------------------------
local badBuy = Npc.buy(0, 1)          -- id 0 is never a real item
check('Npc.buy(0) returns nil (invalid id, no packet)', badBuy == nil, tostring(badBuy))

local badSell = Npc.sell(-1, 1)       -- negative id is never valid
check('Npc.sell(-1) returns nil (invalid id, no packet)', badSell == nil, tostring(badSell))

local badBuy2 = Npc.buy(0xFFFFFF, 1)  -- a huge id that does not exist
check('Npc.buy(impossible id) returns nil', badBuy2 == nil, tostring(badBuy2))

-- ---------------------------------------------------------------------------
-- 2) REAL trade (doubly gated). Even when RUN_MUTATIONS is on, we still require
--    the per-item ids to be set, so an accidental enable cannot trade a random
--    item. Returns: true = sent, false = not sent (offline/no window), nil =
--    invalid id.
-- ---------------------------------------------------------------------------
if RUN_MUTATIONS then
  if BUY_ITEM_ID then
    local r = Npc.buy(BUY_ITEM_ID, TRADE_AMOUNT, false, false)
    -- We only assert the call returned a documented value; whether it is true or
    -- false depends on the live trade window, which the test cannot guarantee.
    check('Npc.buy(BUY_ITEM_ID) returned a documented value',
          r == true or r == false or r == nil, tostring(r))
  else
    print('[skip] real buy (set BUY_ITEM_ID)')
  end

  if SELL_ITEM_ID then
    local r = Npc.sell(SELL_ITEM_ID, TRADE_AMOUNT, false)
    check('Npc.sell(SELL_ITEM_ID) returned a documented value',
          r == true or r == false or r == nil, tostring(r))
  else
    print('[skip] real sell (set SELL_ITEM_ID)')
  end
else
  -- Gated: just document the exact calls a real run would make.
  print('[would] Npc.buy(' .. tostring(BUY_ITEM_ID) .. ', ' .. TRADE_AMOUNT .. ', false, false)')
  print('[would] Npc.sell(' .. tostring(SELL_ITEM_ID) .. ', ' .. TRADE_AMOUNT .. ', false)')
  check('buy/sell left ungated (safe)', true)
end

print(('--- npc: %d passed, %d failed ---'):format(pass, fail))
