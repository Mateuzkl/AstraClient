--[[============================================================================
  test_container.lua - Zerobot-style CONTAINER class
  ============================================================================

  WHAT THIS TESTS
    The `Container(index)` handle: enumerating every OPEN container and reading
    its contents (getName / getCapacity / getItemCount / getItems /
    getItemCountById / getCurrentPage / getTotalPages / getIndex). These are all
    read-only and SAFE.

    The mutating methods (move*/useItem*/close/moveUp/goToPage and the static
    useItemOnAnotherItem) are demonstrated behind a flag:

        local RUN_MUTATIONS = false

    With the flag OFF (default) they only log "would call ..." and assert the
    method exists; nothing is moved or used.

  HOW TO READ THE OUTPUT
    Open at least ONE container in-game (a backpack) before enabling this script,
    otherwise Player.getContainers() is nil and the read section logs "[skip] no
    open container" (that is still a PASS for the offline-safe path).
    [PASS]/[FAIL] lines, then:
        --- container: <P> passed, <F> failed ---

  SAFETY
    Read-only by default. Mutations gated. Even un-gated, the demo move targets
    the SAME slot it reads, so it is a no-op-ish "move to where it already is"
    rather than dumping items on the floor.
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

print('=== Container inspection ===')

-- ---------------------------------------------------------------------------
-- 0) Constructor sanity: Container(idx) builds a handle even for a closed index
--    (Zerobot never validates on construction). getIndex() is local-backed and
--    always returns what we passed; the live getters return nil when gone.
-- ---------------------------------------------------------------------------
local ghost = Container(9999) -- almost certainly not an open container
check('Container(idx) returns a handle', type(ghost) == 'table')
check('handle:getIndex() echoes the index', ghost:getIndex() == 9999, ghost:getIndex())
check('closed handle:getName() is nil (entity gone)', ghost:getName() == nil)
check('closed handle:getItems() is nil', ghost:getItems() == nil)

-- ---------------------------------------------------------------------------
-- 1) Enumerate every OPEN container via Player.getContainers() (array of
--    indexes, or nil if none are open).
-- ---------------------------------------------------------------------------
local openIdx = Player.getContainers()
if not openIdx then
  print('[skip] no open container - open a backpack to exercise the read path')
  print(('--- container: %d passed, %d failed ---'):format(pass, fail))
  return
end

check('Player.getContainers() is a table', type(openIdx) == 'table', #openIdx)

-- Walk each open container and read it fully (all queries are safe).
local firstHandle, firstSlotWithItem
for _, idx in ipairs(openIdx) do
  local c = Container(idx)
  firstHandle = firstHandle or c

  local name = c:getName()
  check('container[' .. idx .. ']:getName() is a string', type(name) == 'string', name)

  local cap = c:getCapacity()
  check('container[' .. idx .. ']:getCapacity() is a number', type(cap) == 'number', cap)

  local cnt = c:getItemCount()
  check('container[' .. idx .. ']:getItemCount() is a number', type(cnt) == 'number', cnt)
  -- Loaded item count can never exceed the container capacity.
  if type(cap) == 'number' and type(cnt) == 'number' then
    check('container[' .. idx .. '] itemCount <= capacity', cnt <= cap, cnt .. ' <= ' .. cap)
  end

  -- getItems() -> array of {id,count,tier}; verify the shape and tally a total.
  local items = c:getItems()
  check('container[' .. idx .. ']:getItems() is a table', type(items) == 'table')
  local shapeOk, tally = true, 0
  for slot, it in ipairs(items or {}) do
    if type(it.id) ~= 'number' or type(it.count) ~= 'number' or type(it.tier) ~= 'number' then
      shapeOk = false
    else
      tally = tally + 1
      -- Remember the first concrete (container, slot, id) we can demo moves on.
      -- ipairs is 1-based but container slots are 0-based, so slot-1 is the
      -- engine slot index.
      if not firstSlotWithItem then
        firstSlotWithItem = { cont = idx, slot = slot - 1, id = it.id, count = it.count }
      end
    end
  end
  check('container[' .. idx .. '] items have {id,count,tier}', shapeOk)
  -- The number of {id,...} rows must match the reported loaded count.
  check('container[' .. idx .. '] #items == getItemCount', tally == cnt, tally .. ' == ' .. tostring(cnt))

  -- Paging info: current page is 1-based and within total (total 0 = unpaged).
  local page = c:getCurrentPage()
  local total = c:getTotalPages()
  check('container[' .. idx .. ']:getCurrentPage() is a number', type(page) == 'number', page)
  check('container[' .. idx .. ']:getTotalPages() is a number', type(total) == 'number', total)
  if type(total) == 'number' and total > 0 then
    check('container[' .. idx .. '] page within total', page >= 1 and page <= total,
          page .. '/' .. total)
  end

  -- getItemCountById against a real id present in this container.
  if firstSlotWithItem and firstSlotWithItem.cont == idx then
    local byId = c:getItemCountById(firstSlotWithItem.id)
    check('container[' .. idx .. ']:getItemCountById(presentId) >= 1', (byId or 0) >= 1, byId)
  end
end

-- ---------------------------------------------------------------------------
-- 2) MUTATIONS (gated). Demonstrate the move/use surface against the first
--    real item we found, without actually relocating it when gated.
-- ---------------------------------------------------------------------------
if firstSlotWithItem then
  local f = firstSlotWithItem
  print(('       demo item: container=%d slot=%d id=%d count=%d')
        :format(f.cont, f.slot, f.id, f.count))
  local c = Container(f.cont)

  -- lookAt is read-ish (sends a "look" but does not move anything); still gate.
  would('container:lookAt(slot)', function() return c:lookAt(f.slot) end)

  -- Move it INTO THE SAME slot of the SAME container: a deliberate no-op target
  -- so an accidental un-gated run cannot scatter loot.
  would('container:moveItemToContainer(slot -> same slot)', function()
    return c:moveItemToContainer(f.slot, f.count, f.cont, f.slot)
  end)

  would('container:moveItemToInventory(slot, BACKPACK)', function()
    return c:moveItemToInventory(f.slot, Enums.InventorySlot.CONST_SLOT_BACKPACK, 1)
  end)

  would('container:useItem(slot)', function() return c:useItem(f.slot, false) end)

  -- Static cross-container helper: use the item on ITSELF (id, id) so, gated or
  -- not, it is the most harmless pairing to demonstrate the signature.
  would('Container.useItemOnAnotherItem(id, id)', function()
    return Container.useItemOnAnotherItem(f.id, f.id)
  end)
else
  print('[skip] no item found in any open container to demo moves')
end

-- Navigation methods (always gated; closing/paging changes UI state).
if firstHandle then
  would('container:goToPage(1)', function() return firstHandle:goToPage(1) end)
  would('container:moveUp()',    function() return firstHandle:moveUp() end)
  would('container:close()',     function() return firstHandle:close() end)
end

print(('--- container: %d passed, %d failed ---'):format(pass, fail))
