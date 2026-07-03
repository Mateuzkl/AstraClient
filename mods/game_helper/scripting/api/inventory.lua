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

  STOW / IMBUEMENT (wired, not stubs): stowContainer goes through the REAL
  g_game.stowItemContainerStack override game_stash installs at init (supply-stash
  opcode 0x28), gated on that module being loaded and the player standing next to a
  depot (isInStash). pickItemImbuement calls the real C++ binding
  g_game.selectImbuementItem (the imbuing window must already be open).

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

  -- Stow gate: true only when game_stash is loaded (so g_game.stowItemContainerStack
  -- is the REAL override it installs in init(), not the corelib no-op) AND the local
  -- player is next to a depot. isInStash mirrors the server's isStashMenuAvailable
  -- check; far from a depot the server drops the stow regardless, so we honestly
  -- report false instead of sending a dead packet.
  local function stowAvailable()
    local mod = g_modules.getModule('game_stash')
    if not mod or not mod:isLoaded() then return false end
    local player = g_game.getLocalPlayer()
    return player ~= nil and player:isInStash()
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
  -- stow (game_stash sender) / imbuement pick (selectImbuementItem)
  ---------------------------------------------------------------------------

  -- Inventory.stowContainer(inventorySlot) -> bool | nil : "Stow container's content"
  -- (SUPPLY_STASH_ACTION_STOW_CONTAINER) for the container worn in an inventory slot,
  -- via game_stash's g_game.stowItemContainerStack override (stash.lua:220) — NOT the
  -- no-op the old comment claimed. Sent DIRECTLY, not via modules.game_stash.
  -- stowContainerContent (that pops a confirmation modal a script never wants). false
  -- when the stash isn't available (see stowAvailable); nil when the slot is empty.
  function Inventory.stowContainer(inventorySlot)
    local item = slotItem(inventorySlot)
    if not item then return nil end
    if not stowAvailable() then return false end
    g_game.stowItemContainerStack(SUPPLY_STASH_ACTION_STOW_CONTAINER, item:getPosition(), item:getId(), item:getStackPos())
    return true
  end

  -- Inventory.pickItemImbuement(inventorySlot) -> bool | nil : pick the item worn in
  -- an inventory slot into the OPEN imbuing window via the real C++ binding
  -- g_game.selectImbuementItem (same call as imbuementselection.lua:55). Precondition:
  -- the imbuing window must already be open; the server ignores the packet otherwise.
  -- nil when the slot is empty.
  function Inventory.pickItemImbuement(inventorySlot)
    local item = slotItem(inventorySlot)
    if not item then return nil end
    g_game.selectImbuementItem(item:getId(), item:getPosition(), item:getStackPos())
    return true
  end

  return Inventory
end
