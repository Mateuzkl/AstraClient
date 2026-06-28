--[[============================================================================
  test_inventory.lua - Zerobot-style INVENTORY namespace
  ============================================================================

  WHAT THIS TESTS
    The `Inventory` namespace, which operates on the player's 11 EQUIPMENT slots
    (Enums.InventorySlot: HEAD=1 .. STORE_INBOX=11). The namespace itself only
    exposes ACTIONS (move/use/look), so the read part of this test reads the
    slots through Player.getInventorySlot(slot) (the correct query for slots) and
    cross-checks against Game.getInventoryItems().

    All Inventory.* actions mutate game state, so they are gated:

        local RUN_MUTATIONS = false

    With the flag OFF (default) they only log "would call ..." and assert the
    function exists.

  HOW TO READ THE OUTPUT
    [PASS]/[FAIL] lines listing each slot's contents, then:
        --- inventory: <P> passed, <F> failed ---
    Run offline (all slots nil, still PASS) and in-game (real items).

  SAFETY
    Read-only by default. The only un-gated calls are Inventory.lookAt (sends a
    "look", harmless) which is ALSO gated here for consistency. No item leaves a
    slot unless you flip RUN_MUTATIONS.
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

local RUN_MUTATIONS = false

local function would(name, fn)
  if not RUN_MUTATIONS then
    print('[would] ' .. name)
    check(name .. ' (callable, gated)', type(fn) == 'function')
    return
  end
  local ok, res = pcall(fn)
  check(name .. ' executed (no error)', ok, ok and tostring(res) or res)
end

print('=== Inventory slots ===')

-- ---------------------------------------------------------------------------
-- 0) API surface: the documented Inventory action functions must all exist.
-- ---------------------------------------------------------------------------
for _, n in ipairs({ 'moveItemToGround', 'moveItemToContainer', 'useItem', 'lookAt' }) do
  check('Inventory.' .. n .. ' exists', type(Inventory[n]) == 'function')
end

-- ---------------------------------------------------------------------------
-- 1) Read every equipment slot by name. Player.getInventorySlot(slot) returns
--    {id,count,tier,holdingCount} or nil when the slot is empty/offline.
-- ---------------------------------------------------------------------------
-- Iterate the named slots in their numeric order for a tidy report.
local SLOTS = {
  { 'HEAD',     Enums.InventorySlot.CONST_SLOT_HEAD },
  { 'NECKLACE', Enums.InventorySlot.CONST_SLOT_NECKLACE },
  { 'BACKPACK', Enums.InventorySlot.CONST_SLOT_BACKPACK },
  { 'ARMOR',    Enums.InventorySlot.CONST_SLOT_ARMOR },
  { 'RIGHT',    Enums.InventorySlot.CONST_SLOT_RIGHT },
  { 'LEFT',     Enums.InventorySlot.CONST_SLOT_LEFT },
  { 'LEGS',     Enums.InventorySlot.CONST_SLOT_LEGS },
  { 'FEET',     Enums.InventorySlot.CONST_SLOT_FEET },
  { 'RING',     Enums.InventorySlot.CONST_SLOT_RING },
  { 'AMMO',     Enums.InventorySlot.CONST_SLOT_AMMO },
}

local occupied = 0          -- how many slots have an item
local firstFilled = nil     -- {name, slot, id, count} of the first filled slot
for _, entry in ipairs(SLOTS) do
  local label, slot = entry[1], entry[2]
  local data = Player.getInventorySlot(slot)
  if data == nil then
    -- Empty slot is a valid, expected result - count it as a PASS.
    check('slot ' .. label .. ' empty/readable', true, 'empty')
  else
    occupied = occupied + 1
    local ok = type(data.id) == 'number'
           and type(data.count) == 'number'
           and type(data.tier) == 'number'
           and type(data.holdingCount) == 'number'
    check('slot ' .. label .. ' has {id,count,tier,holdingCount}', ok,
          ok and ('id=' .. data.id .. ' x' .. data.count) or nil)
    if ok and not firstFilled then
      firstFilled = { name = label, slot = slot, id = data.id, count = data.count }
    end
  end
end
print('       occupied slots = ' .. occupied)

-- ---------------------------------------------------------------------------
-- 2) Cross-check: the count of filled slots here should equal the length of
--    Game.getInventoryItems() (both enumerate the equipped set).
-- ---------------------------------------------------------------------------
local equipped = Game.getInventoryItems()
check('Player slots filled == #Game.getInventoryItems()',
      occupied == #equipped, occupied .. ' == ' .. #equipped)

-- ---------------------------------------------------------------------------
-- 3) MUTATIONS (gated). Demo against the first filled slot we found.
-- ---------------------------------------------------------------------------
if firstFilled then
  local f = firstFilled
  print(('       demo slot: %s (slot=%d id=%d)'):format(f.name, f.slot, f.id))

  -- lookAt: harmless "look" packet, still gated for consistency.
  would('Inventory.lookAt(' .. f.name .. ')', function()
    return Inventory.lookAt(f.slot)
  end)

  -- useItem: e.g. eating food / using a ring; gated.
  would('Inventory.useItem(' .. f.name .. ')', function()
    return Inventory.useItem(f.slot)
  end)

  -- moveItemToContainer: move 1 into the first OPEN container (if any). Picking a
  -- real open container index keeps the demo meaningful; still gated.
  local conts = Player.getContainers()
  local destIdx = conts and conts[1] or nil
  would('Inventory.moveItemToContainer(' .. f.name .. ' -> container ' .. tostring(destIdx) .. ')', function()
    if not destIdx then return false end
    return Inventory.moveItemToContainer(f.slot, 1, destIdx, 0)
  end)

  -- moveItemToGround: illustrative coords; engine validates the tile. Gated so
  -- nothing is ever dropped by accident.
  would('Inventory.moveItemToGround(' .. f.name .. ' -> x,y,z)', function()
    return Inventory.moveItemToGround(f.slot, 1, 100, 100, 7)
  end)
else
  print('[skip] no filled equipment slot to demo moves/use')
end

print(('--- inventory: %d passed, %d failed ---'):format(pass, fail))
