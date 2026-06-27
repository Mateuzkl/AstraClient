--[[============================================================================
  scripting/api/inventory.lua — Zerobot-compatible `Inventory` namespace.
  ============================================================================

  Builder module (see scripting/scripting.lua header + scripting/CONTRACT.md).
  Returns `function(api, ctx) ... return Inventory end` and is injected into
  every sandboxed script as the global `Inventory`.

  Plain namespace (NOT a class). Operates on the local player's equipment slots
  (Enums.InventorySlot: HEAD=1 .. STORE_INBOX=11). Slots are translated to the
  engine's CONST_SLOT_* via api.Enums.translate.inventorySlotToEngine (identity
  for 1..11, but routed through the translator per CONTRACT so the mapping lives
  in one place).

  Zerobot return semantics: nil = slot empty / no such item; false = action not
  sent / validation failed; true = request sent to server.

  Engine mapping (verified — see analysis/engine-capabilities.md §2, §5):
    * g_game.getLocalPlayer():getInventoryItem(engSlot) -> ItemPtr | nil
      (the returned ItemPtr already carries an inventory position, so
      g_game.move/look/use operate on it directly)
    * g_game.move(thing, toPos, count)   (slot -> ground / container)
    * g_game.use(item)                   (use the item in a slot)
    * g_game.look(item)                  (look at the item in a slot)

  PARTIAL (engine stub `gameNoops` / no protocol yet — wrapper present, logs a
  "Fase 2" notice and returns false): stowContainer, pickItemImbuement.

  RULES (CONTRACT): no globals; cross-namespace refs are lazy (api.Enums.* read
  inside functions); runs OUTSIDE the sandbox (full g_game access).
============================================================================]]

return function(api, ctx)
  local Inventory = {}

  -- Inventory-position sentinel: a ground move target inside the player's own
  -- inventory uses Position(0xFFFF, 0, slot). For ground/container destinations
  -- we build {x=,y=,z=} from the caller's flat coords.
  local INVENTORY_POS_X = 0xFFFF

  -- Resolve the live item occupying an inventory slot (nil if empty/offline).
  -- Returns the engine ItemPtr; it already has its inventory position set.
  local function slotItem(inventorySlot)
    local player = g_game.getLocalPlayer()
    if not player then return nil end
    local engSlot = api.Enums.translate.inventorySlotToEngine(inventorySlot)
    if not engSlot then return nil end
    return player:getInventoryItem(engSlot)
  end

  local function pos(x, y, z)
    return { x = x, y = y, z = z }
  end

  ---------------------------------------------------------------------------
  -- moves
  ---------------------------------------------------------------------------

  -- Inventory.moveItemToGround(inventorySlot, inventoryCount, toX, toY, toZ) -> bool | nil
  function Inventory.moveItemToGround(inventorySlot, inventoryCount, toX, toY, toZ)
    local item = slotItem(inventorySlot)
    if not item then return nil end
    g_game.move(item, pos(toX, toY, toZ), inventoryCount or 1)
    return true
  end

  -- Inventory.moveItemToContainer(inventorySlot, inventoryCount, containerIndex, containerSlot) -> bool | nil
  function Inventory.moveItemToContainer(inventorySlot, inventoryCount, containerIndex, containerSlot)
    local item = slotItem(inventorySlot)
    if not item then return nil end
    local toC = g_game.getContainer(containerIndex)
    if not toC then return false end
    g_game.move(item, toC:getSlotPosition(containerSlot or 0), inventoryCount or 1)
    return true
  end

  ---------------------------------------------------------------------------
  -- use / look
  ---------------------------------------------------------------------------

  -- Inventory.useItem(inventorySlot) -> bool | nil : use the item in a slot.
  function Inventory.useItem(inventorySlot)
    local item = slotItem(inventorySlot)
    if not item then return nil end
    g_game.use(item)
    return true
  end

  -- Inventory.lookAt(inventorySlot) -> bool | nil : look at the item in a slot.
  function Inventory.lookAt(inventorySlot)
    local item = slotItem(inventorySlot)
    if not item then return nil end
    g_game.look(item)
    return true
  end

  ---------------------------------------------------------------------------
  -- PARTIAL — engine stubs / protocol not ported (Fase 2)
  ---------------------------------------------------------------------------

  -- Inventory.stowContainer(inventorySlot) -> false (Fase 2).
  -- "Stow container's content" relies on g_game.stowItem*, which is a no-op stub
  -- (corelib/globals.lua gameNoops). nil if the slot is empty (ZB semantics).
  function Inventory.stowContainer(inventorySlot)
    if slotItem(inventorySlot) == nil then return nil end
    ctx.log("[Inventory.stowContainer] indisponivel (stub do engine) - Fase 2")
    return false
  end

  -- Inventory.pickItemImbuement(inventorySlot) -> false (Fase 2).
  -- No imbuement-pick-from-inventory protocol wired yet.
  function Inventory.pickItemImbuement(inventorySlot)
    if slotItem(inventorySlot) == nil then return nil end
    ctx.log("[Inventory.pickItemImbuement] indisponivel (protocolo nao portado) - Fase 2")
    return false
  end

  return Inventory
end
