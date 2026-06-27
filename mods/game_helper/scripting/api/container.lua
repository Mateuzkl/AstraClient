--[[============================================================================
  scripting/api/container.lua — Zerobot-compatible `Container` CLASS.
  ============================================================================

  Builder module (see scripting/scripting.lua header + scripting/CONTRACT.md).
  Returns `function(api, ctx) ... return Container end` and is injected into
  every sandboxed script as the global `Container`.

  `Container(index)` (via __call) == `Container.new(index)`; the instance wraps
  `self.cid` = the container INDEX (the id the server/engine assigns to an open
  container, the key in g_game.getContainers()). Every method re-resolves the
  live engine container with `g_game.getContainer(self.cid)` ON EACH CALL and
  returns `nil` when that container no longer exists (Zerobot semantics:
  nil = entity gone; false = action not sent; true = request sent).

  Engine mapping (verified — see analysis/engine-capabilities.md §5):
    * g_game.getContainer(id)        -> ContainerPtr | nil
    * g_game.getContainers()         -> { [id]=ContainerPtr } (static useItemOnAnotherItem)
    * Container:getName/getCapacity/getSize/getItemsCount/hasParent/hasPages
    * Container:getItem(slot)        -> ItemPtr | nil  (slot is 0-based into the
                                        CURRENT PAGE's loaded items; the ItemPtr
                                        already carries its container position via
                                        getSlotPosition(slot)=Pos(0xffff,id|0x40,slot),
                                        so g_game.move/useWith work directly on it)
    * Container:getItems()           -> { ItemPtr, ... } (current page)
    * Container:getFirstIndex()      -> first absolute index of the current page
    * g_game.move(thing, toPos, count)         (ground/inventory/container moves)
    * g_game.use(thing) / g_game.open(item, prev)
    * g_game.useWith(item, toThing, subType)   (item-on-item)
    * g_game.openParent(container) / g_game.close(container)
    * g_game.seekInContainer(cid, index)       (paging -> goToPage)

  PARTIAL (engine stub `gameNoops` / no protocol yet — wrapper present, logs a
  "Fase 2" notice and returns false): stowItem, stowAllItems, pickItemImbuement.

  RULES (CONTRACT): no globals (the engine already exposes the C++ class
  `Container`; this local shadows it only inside this module's closure and is
  returned, never assigned to _G); cross-namespace refs are lazy (api.Enums.* is
  read inside functions). Runs OUTSIDE the sandbox (full g_game access).
============================================================================]]

return function(api, ctx)
  -- Local class table. NOTE: this intentionally shadows the engine's C++ global
  -- `Container` *within this closure only*; it is returned to the loader and
  -- never written to _G, so the C++ Container class is untouched elsewhere.
  local Container = {}
  Container.__index = Container

  -- Inventory-position sentinel used by the engine to mean "an inventory slot".
  -- toPos for inventory moves is Position(0xFFFF, 0, slot).
  local INVENTORY_POS_X = 0xFFFF

  ---------------------------------------------------------------------------
  -- internals
  ---------------------------------------------------------------------------

  -- Resolve the live engine container for this handle (nil if it's gone/closed).
  local function resolve(self)
    if not self or self.cid == nil then return nil end
    return g_game.getContainer(self.cid)
  end

  -- Resolve a single item at a page-relative slot (nil if no container/slot).
  local function itemAt(c, slot)
    if not c then return nil end
    return c:getItem(slot)
  end

  -- Build a {x=,y=,z=} table from separate coords (Zerobot passes flat coords).
  local function pos(x, y, z)
    return { x = x, y = y, z = z }
  end

  ---------------------------------------------------------------------------
  -- constructor
  ---------------------------------------------------------------------------

  -- Container.new(containerIndex) -> Container handle (never validates; like ZB).
  function Container.new(containerIndex)
    return setmetatable({ cid = containerIndex }, Container)
  end

  ---------------------------------------------------------------------------
  -- queries
  ---------------------------------------------------------------------------

  -- getIndex() -> number : the container index (local, always available).
  function Container:getIndex()
    return self.cid
  end

  -- getName() -> string | nil
  function Container:getName()
    local c = resolve(self)
    if not c then return nil end
    return c:getName()
  end

  -- getItems() -> { {id,count,tier}, ... } | nil  (current page)
  function Container:getItems()
    local c = resolve(self)
    if not c then return nil end
    local out = {}
    for _, item in ipairs(c:getItems() or {}) do
      out[#out + 1] = {
        id    = item:getId(),
        count = item:getCountOrSubType(),
        tier  = item:getTier(),
      }
    end
    return out
  end

  -- getCapacity() -> number | nil  (total slots of the container)
  function Container:getCapacity()
    local c = resolve(self)
    if not c then return nil end
    return c:getCapacity()
  end

  -- getItemCount() -> number | nil : number of items currently loaded (this page).
  function Container:getItemCount()
    local c = resolve(self)
    if not c then return nil end
    return c:getItemsCount()
  end

  -- getItemCountById(itemId) -> number | nil : summed count of itemId on this page.
  function Container:getItemCountById(itemId)
    local c = resolve(self)
    if not c then return nil end
    local total = 0
    for _, item in ipairs(c:getItems() or {}) do
      if item:getId() == itemId then
        total = total + (item:getCountOrSubType() or 1)
      end
    end
    return total
  end

  -- getCurrentPage() -> number | nil : 1-based current page.
  -- Engine paging is by absolute firstIndex; page = floor(firstIndex/cap)+1.
  function Container:getCurrentPage()
    local c = resolve(self)
    if not c then return nil end
    local cap = c:getCapacity() or 0
    if cap <= 0 then return 1 end
    return math.floor((c:getFirstIndex() or 0) / cap) + 1
  end

  -- getTotalPages() -> number | nil : total pages (Zerobot: 0 when unpaged).
  function Container:getTotalPages()
    local c = resolve(self)
    if not c then return nil end
    if not c:hasPages() then return 0 end
    local cap = c:getCapacity() or 0
    if cap <= 0 then return 0 end
    return math.ceil((c:getSize() or 0) / cap)
  end

  ---------------------------------------------------------------------------
  -- navigation / lifecycle
  ---------------------------------------------------------------------------

  -- goToPage(page) -> bool | nil : seek to a 1-based page via seekInContainer.
  function Container:goToPage(page)
    local c = resolve(self)
    if not c then return nil end
    if not c:hasPages() then return false end
    local cap = c:getCapacity() or 0
    if cap <= 0 or type(page) ~= "number" or page < 1 then return false end
    -- seek wants the absolute first index of the target page (0-based).
    g_game.seekInContainer(self.cid, (page - 1) * cap)
    return true
  end

  -- close() -> bool | nil
  function Container:close()
    local c = resolve(self)
    if not c then return nil end
    g_game.close(c)
    return true
  end

  -- moveUp() -> bool | nil : show the parent/higher container.
  function Container:moveUp()
    local c = resolve(self)
    if not c then return nil end
    if not c:hasParent() then return false end
    g_game.openParent(c)
    return true
  end

  -- lookAt(containerSlot) -> bool | nil
  function Container:lookAt(containerSlot)
    local c = resolve(self)
    if not c then return nil end
    local item = itemAt(c, containerSlot)
    if not item then return false end
    g_game.look(item)
    return true
  end

  ---------------------------------------------------------------------------
  -- moves
  ---------------------------------------------------------------------------

  -- moveItemToInventory(containerSlot, inventorySlot, itemCount) -> bool | nil
  function Container:moveItemToInventory(containerSlot, inventorySlot, itemCount)
    local c = resolve(self)
    if not c then return nil end
    local item = itemAt(c, containerSlot)
    if not item then return false end
    local engSlot = api.Enums.translate.inventorySlotToEngine(inventorySlot)
    if not engSlot then return false end
    -- Inventory destination is Position(0xFFFF, slot, 0): the slot goes in `y`,
    -- not `z` (see thing.cpp / inventory.otui; map.lua encodes it the same way).
    g_game.move(item, pos(INVENTORY_POS_X, engSlot, 0), itemCount or 1)
    return true
  end

  -- moveItemToGround(containerSlot, itemCount, toX, toY, toZ) -> bool | nil
  function Container:moveItemToGround(containerSlot, itemCount, toX, toY, toZ)
    local c = resolve(self)
    if not c then return nil end
    local item = itemAt(c, containerSlot)
    if not item then return false end
    g_game.move(item, pos(toX, toY, toZ), itemCount or 1)
    return true
  end

  -- moveItemToContainer(containerSlot, itemCount, toContainerIndex, toContainerSlot) -> bool | nil
  function Container:moveItemToContainer(containerSlot, itemCount, toContainerIndex, toContainerSlot)
    local c = resolve(self)
    if not c then return nil end
    local item = itemAt(c, containerSlot)
    if not item then return false end
    local toC = g_game.getContainer(toContainerIndex)
    if not toC then return false end
    -- Destination position inside the target container: Pos(0xffff, id|0x40, slot).
    g_game.move(item, toC:getSlotPosition(toContainerSlot or 0), itemCount or 1)
    return true
  end

  ---------------------------------------------------------------------------
  -- use
  ---------------------------------------------------------------------------

  -- useItem(containerSlot, openNewWindow=false) -> bool | nil
  -- Uses the item at the slot; for a container item, open in a new window when
  -- openNewWindow is true (g_game.open(item, prev) chains into the same window
  -- when a previous container is given, opens fresh otherwise).
  function Container:useItem(containerSlot, openNewWindow)
    local c = resolve(self)
    if not c then return nil end
    local item = itemAt(c, containerSlot)
    if not item then return false end
    if item:isContainer() then
      -- prev = nil -> new window; prev = this container -> reuse same window.
      g_game.open(item, openNewWindow and nil or c)
    else
      g_game.use(item)
    end
    return true
  end

  -- useItemWithContainerItem(spotFrom, contTo, spotTo) -> bool | nil
  -- Use the item at this container's `spotFrom` ON the item at (contTo, spotTo).
  function Container:useItemWithContainerItem(spotFrom, contTo, spotTo)
    local c = resolve(self)
    if not c then return nil end
    local fromItem = itemAt(c, spotFrom)
    if not fromItem then return false end
    local toC = g_game.getContainer(contTo)
    if not toC then return false end
    local toItem = itemAt(toC, spotTo)
    if not toItem then return false end
    g_game.useWith(fromItem, toItem)
    return true
  end

  ---------------------------------------------------------------------------
  -- PARTIAL — engine stubs / protocol not ported (Fase 2)
  ---------------------------------------------------------------------------

  -- stowItem(containerSlot, itemCount) -> false (Fase 2)
  -- g_game.stowItem is a no-op stub (corelib/globals.lua gameNoops); needs a
  -- dedicated stow protocol the engine doesn't send yet.
  function Container:stowItem(containerSlot, itemCount)
    if resolve(self) == nil then return nil end
    ctx.log("[Container:stowItem] indisponivel (stub do engine) - Fase 2")
    return false
  end

  -- stowAllItems(containerSlot) -> false (Fase 2). Same reason as stowItem.
  function Container:stowAllItems(containerSlot)
    if resolve(self) == nil then return nil end
    ctx.log("[Container:stowAllItems] indisponivel (stub do engine) - Fase 2")
    return false
  end

  -- pickItemImbuement(containerSlot) -> false (Fase 2). No imbuement-pick
  -- protocol wired from the container side yet.
  function Container:pickItemImbuement(containerSlot)
    if resolve(self) == nil then return nil end
    ctx.log("[Container:pickItemImbuement] indisponivel (protocolo nao portado) - Fase 2")
    return false
  end

  ---------------------------------------------------------------------------
  -- static
  ---------------------------------------------------------------------------

  -- Container.useItemOnAnotherItem(itemId, otherId) -> bool | nil
  -- Scan every OPEN container; use the first item whose id == itemId on the
  -- first item whose id == otherId (Zerobot's auto cross-container use). Returns
  -- nil if no container is open, false if either item isn't found.
  function Container.useItemOnAnotherItem(itemId, otherId)
    local containers = g_game.getContainers()
    if not containers then return nil end
    local fromItem, toItem
    local any = false
    for _, c in pairs(containers) do
      any = true
      for _, item in ipairs(c:getItems() or {}) do
        local id = item:getId()
        if not fromItem and id == itemId then fromItem = item end
        if not toItem and id == otherId then toItem = item end
      end
      if fromItem and toItem then break end
    end
    if not any then return nil end
    if not fromItem or not toItem then return false end
    g_game.useWith(fromItem, toItem)
    return true
  end

  -- Make Container(index) call Container.new(index).
  setmetatable(Container, { __call = function(_, containerIndex)
    return Container.new(containerIndex)
  end })

  return Container
end
