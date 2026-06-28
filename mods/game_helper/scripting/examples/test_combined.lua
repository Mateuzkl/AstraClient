--[[============================================================================
  test_combined.lua - GAME + CONTAINER + INVENTORY together (read-only)
  ============================================================================

  WHAT THIS TESTS
    A realistic, cross-namespace workflow that a real bot script would run, kept
    entirely READ-ONLY by default:
      1. Snapshot the equipped set (Game.getInventoryItems).
      2. Snapshot every OPEN container (Container(idx):getItems) via
         Player.getContainers().
      3. Pick a "target item" (the most common id seen anywhere) and reconcile
         THREE independent counts of it:
            a) Game.getItemCount(id)                      (whole-inventory total)
            b) sum of Container(idx):getItemCountById(id) (containers, all pages
               currently loaded)
            c) our own manual tally from the snapshots
         and report how they relate (they will not always be equal - see notes).

    One optional CONSOLIDATION step (moving all loose copies of the target item
    into the first open container) is shown behind:

        local RUN_MUTATIONS = false

    With the flag OFF (default) it only logs the moves it WOULD perform.

  HOW TO READ THE OUTPUT
    Best run in-game with a backpack open. [PASS]/[FAIL] lines, a per-source
    count breakdown for the target item, then:
        --- combined: <P> passed, <F> failed ---

  COUNT-RECONCILIATION NOTES (why numbers can differ - all expected)
    * Game.getItemCount(id) covers the FULL inventory incl. CLOSED backpacks
      (0xF5 packet), so it can be >= the containers-only sum.
    * Container:getItemCountById only sees the CURRENT PAGE's loaded items, so a
      paged container under-counts vs the engine total.
    The script therefore asserts the SAFE relationship (whole >= visible), not
    strict equality.

  SAFETY
    Read-only by default. The consolidation mutation is gated and, when enabled,
    only moves the target item id (never blindly empties a container).
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

print('=== Combined workflow (Game + Container + Inventory) ===')

-- ---------------------------------------------------------------------------
-- 1) Equipped snapshot + a running tally of id -> count across everything.
-- ---------------------------------------------------------------------------
local tally = {}  -- [itemId] = total count seen in snapshots
local function addTally(id, count)
  if not id then return end
  tally[id] = (tally[id] or 0) + (count or 1)
end

local equipped = Game.getInventoryItems()
check('Game.getInventoryItems is a table', type(equipped) == 'table', #equipped)
for _, it in ipairs(equipped) do addTally(it.id, it.count) end

-- ---------------------------------------------------------------------------
-- 2) Open-container snapshot.
-- ---------------------------------------------------------------------------
local openIdx = Player.getContainers()
local nOpen = openIdx and #openIdx or 0
print('       open containers = ' .. nOpen)

for _, idx in ipairs(openIdx or {}) do
  local c = Container(idx)
  local items = c:getItems()
  if type(items) == 'table' then
    for _, it in ipairs(items) do addTally(it.id, it.count) end
  end
end

-- ---------------------------------------------------------------------------
-- 3) Choose the target item = the id with the largest manual tally.
-- ---------------------------------------------------------------------------
local targetId, targetTally = nil, 0
for id, n in pairs(tally) do
  if n > targetTally then targetId, targetTally = id, n end
end

if not targetId then
  print('[skip] nothing equipped and no open container items - log in / open a bag')
  print(('--- combined: %d passed, %d failed ---'):format(pass, fail))
  return
end

print(('       target item id = %d (manual tally = %d)'):format(targetId, targetTally))

-- ---------------------------------------------------------------------------
-- 4) Reconcile the three independent counts.
-- ---------------------------------------------------------------------------
-- a) Whole-inventory total from the engine (covers closed backpacks too).
local engineTotal = Game.getItemCount(targetId)
check('Game.getItemCount(target) is a number', type(engineTotal) == 'number', engineTotal)

-- b) Sum over open containers' getItemCountById (current pages only).
local containersVisible = 0
for _, idx in ipairs(openIdx or {}) do
  local c = Container(idx)
  containersVisible = containersVisible + (c:getItemCountById(targetId) or 0)
end
print('       containers-visible count = ' .. containersVisible)

-- c) Our manual tally already in targetTally (equipped + visible container items).

-- Relationship 1: the whole-inventory engine total must cover what we can SEE.
check('engineTotal >= containers-visible', engineTotal >= containersVisible,
      engineTotal .. ' >= ' .. containersVisible)

-- Relationship 2: the engine total must also cover the manual tally we built
-- purely from visible snapshots (equipped + open-container items).
check('engineTotal >= manual tally', engineTotal >= targetTally,
      engineTotal .. ' >= ' .. targetTally)

-- ---------------------------------------------------------------------------
-- 5) OPTIONAL consolidation (gated): move every loose copy of the target item
--    from open containers into the FIRST open container's slot 0. We compute the
--    concrete (container, slot) pairs but only execute when RUN_MUTATIONS=true.
-- ---------------------------------------------------------------------------
local destIdx = openIdx and openIdx[1] or nil
if destIdx then
  local moves = {}
  for _, idx in ipairs(openIdx) do
    local c = Container(idx)
    for slot, it in ipairs(c:getItems() or {}) do
      -- container slots are 0-based; ipairs is 1-based.
      if it.id == targetId and not (idx == destIdx) then
        moves[#moves + 1] = { from = idx, slot = slot - 1, count = it.count }
      end
    end
  end
  print(('       consolidation: %d source stack(s) -> container %d'):format(#moves, destIdx))
  for _, m in ipairs(moves) do
    would(('Container(%d):moveItemToContainer(slot %d -> container %d slot 0)')
            :format(m.from, m.slot, destIdx), function()
      return Container(m.from):moveItemToContainer(m.slot, m.count, destIdx, 0)
    end)
  end
  if #moves == 0 then
    print('[skip] nothing to consolidate (target only in dest / equipped)')
  end
else
  print('[skip] no open container to consolidate into')
end

print(('--- combined: %d passed, %d failed ---'):format(pass, fail))
