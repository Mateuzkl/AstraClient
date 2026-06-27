--[[============================================================================
  scripting/api/npc.lua — Zerobot-compatible `Npc` namespace (NPC trade).
  ============================================================================

  Builder module (see scripting/scripting.lua header + scripting/CONTRACT.md).
  Returns `function(api, ctx) ... return Npc end` and is injected into every
  sandboxed script as the global `Npc`.

  Plain namespace (NOT a class). Normal quantity buy/sell against the currently
  open NPC trade window. (Bulk "Sell All" is a separate path via extended opcode
  203 — NOT handled here; this is per-quantity trade like Zerobot's Npc.buy/sell.)

  Zerobot return semantics here: true = request sent; false = not sent /
  invalid; nil = item id does not resolve to a real item type.

  Engine mapping (verified — see analysis/engine-capabilities.md §1 + game.cpp):
    * g_game.buyItem(item, amount, ignoreCapacity, buyWithBackpack)
        -> sends ClientBuyItem with (item:getId(), item:getCountOrSubType(),
           amount, ignoreCapacity, buyWithBackpack). NOTE the amount is U16 on
           modern protocol (this fork's fix — memory npc-buy-amount-u16), so the
           caller's amount is passed straight through.
    * g_game.sellItem(item, amount, ignoreEquipped)
        -> sends ClientSellItem with (item:getId(), item:getCountOrSubType(),
           amount, ignoreEquipped).
    Both take an ItemPtr (not a raw id). We build one with Item.create(id); the
    server identifies the shop offer by (itemId, subType), and getId() on the
    created item returns the client id we passed.

  ignoreCap NOTE (task + memory): the client UI removed the ignore-capacity
  option (buys always respect cap to avoid spilling on the floor). The engine
  protocol field still exists, so we forward the caller's flag (default false)
  rather than erroring — a script that explicitly opts in still works, and the
  common case (nil/false) matches the client's normal behavior.

  RULES (CONTRACT): no globals; cross-namespace refs are lazy; runs OUTSIDE the
  sandbox (full g_game / g_things / Item access).
============================================================================]]

return function(api, ctx)
  local Npc = {}

  -- Resolve an item id to a fresh ItemPtr suitable for the trade packet, or nil
  -- if the id is not a real item type. g_things.getItemType(id) returns a
  -- null-ish ItemType (server id 0) for unknown ids; guard on that so we return
  -- nil (ZB "no such item") instead of sending a bogus buy/sell.
  local function tradeItem(id)
    if type(id) ~= "number" or id <= 0 then return nil end
    local itemType = g_things.getItemType(id)
    if not itemType or itemType:getServerId() == 0 then return nil end
    return Item.create(id)
  end

  -- Npc.buy(id, amount, ignoreCap, inBackpacks) -> bool | nil
  -- Buy `amount` of item `id` from the open NPC trade window. `inBackpacks`
  -- requests delivery into shopping bags. Returns nil if the id is invalid,
  -- false if nothing was sent (offline / no trade), true if the request went out.
  function Npc.buy(id, amount, ignoreCap, inBackpacks)
    local item = tradeItem(id)
    if not item then return nil end
    if not g_game.isOnline() then return false end
    amount = tonumber(amount) or 1
    if amount < 1 then return false end
    g_game.buyItem(item, amount, ignoreCap and true or false, inBackpacks and true or false)
    return true
  end

  -- Npc.sell(id, amount, ignoreEquipped) -> bool | nil
  -- Sell `amount` of item `id` to the open NPC trade window. `ignoreEquipped`
  -- skips currently-equipped items. Same return semantics as Npc.buy.
  function Npc.sell(id, amount, ignoreEquipped)
    local item = tradeItem(id)
    if not item then return nil end
    if not g_game.isOnline() then return false end
    amount = tonumber(amount) or 1
    if amount < 1 then return false end
    g_game.sellItem(item, amount, ignoreEquipped and true or false)
    return true
  end

  return Npc
end
