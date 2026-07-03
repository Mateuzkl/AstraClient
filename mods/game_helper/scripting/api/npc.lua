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
    Both take an ItemPtr (not a raw id). tradeItem(id, kind) resolves one in two
    layers (see below): the exact ItemPtr from the open trade window when the id
    is on that side of the shop (carries the right subType, incl. fluids), else a
    fresh Item.create(id, 0) validated against the appearances. The server
    identifies the shop offer by (itemId, subType); getId() returns the client id.

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

  -- NPC trade sides (matches game_npctrade BUY/SELL and the wire trade-type).
  local NPC_BUY, NPC_SELL = 1, 2

  -- Resolve an item id to an ItemPtr suitable for the trade packet, or nil if the
  -- id is not a real item type. No OTB/serverId gate: boot loads only appearances
  -- (never the OTB), so every getItemType(id):getServerId() is 0 here -- the old
  -- gate rejected every id and spammed "invalid thing type". Two layers instead:
  --   (a) the exact ItemPtr from the open trade window for this `kind`, via
  --       modules.game_npctrade.getTradeItemData(id, kind). It carries the correct
  --       subType (incl. fluid containers), so the offer matches on the wire.
  --   (b) fallback: Item.create(id, 0) validated against the appearances.
  --       Item::setId zeroes the client id of a non-existent appearance, so
  --       getId()==0 means "no such item" -> nil (ZB "no such item").
  local function tradeItem(id, kind)
    if type(id) ~= "number" or id <= 0 then return nil end
    local m = modules and modules.game_npctrade
    if m and type(m.getTradeItemData) == "function"
        and (kind == NPC_BUY or kind == NPC_SELL) then
      local ok, data = pcall(m.getTradeItemData, id, kind)
      if ok and type(data) == "table" and data.ptr then
        return data.ptr
      end
    end
    local item = Item.create(id, 0)
    if not item or item:getId() == 0 then return nil end
    return item
  end

  -- Npc.buy(id, amount, ignoreCap, inBackpacks) -> bool | nil
  -- Buy `amount` of item `id` from the open NPC trade window. `inBackpacks`
  -- requests delivery into shopping bags. Returns nil if the id is invalid,
  -- false if nothing was sent (offline / no trade), true if the request went out.
  function Npc.buy(id, amount, ignoreCap, inBackpacks)
    local item = tradeItem(id, NPC_BUY)
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
    local item = tradeItem(id, NPC_SELL)
    if not item then return nil end
    if not g_game.isOnline() then return false end
    amount = tonumber(amount) or 1
    if amount < 1 then return false end
    g_game.sellItem(item, amount, ignoreEquipped and true or false)
    return true
  end

  -- ------------------------------------------------------------------------
  -- Read-helpers (Koliseu extension; no exact ZB equivalents). They only READ the
  -- live trade window from the game_npctrade module and never send, so they are
  -- outside the buy/sell true/false/nil send contract: getBuyPrice/getSellPrice
  -- return a number or nil (NPC does not trade it / no window), getTradeItems an
  -- array. game_npctrade is a sandboxed module, so its globals (npcWindow,
  -- tradeItems, ...) live on modules.game_npctrade (== package.loaded); reach them
  -- lazily and type-checked, the same way astra_compat.lua / cavebots do.
  -- ------------------------------------------------------------------------

  local function npctradeMod()
    return modules and modules.game_npctrade or nil
  end

  -- Find the trade entry { ptr, name, weight, price } for `id` on side `kind`
  -- (NPC_BUY/NPC_SELL) in the live window data, or nil. `price` on the BUY list is
  -- the buy price, on the SELL list the sell price (see npctrade.onOpenNpcTrade).
  local function findTradeEntry(id, kind)
    if type(id) ~= "number" then return nil end
    local m = npctradeMod()
    local lists = m and m.tradeItems
    if type(lists) ~= "table" then return nil end
    local list = lists[kind]
    if type(list) ~= "table" then return nil end
    for _, entry in ipairs(list) do
      if type(entry) == "table" and entry.ptr and entry.ptr:getId() == id then
        return entry
      end
    end
    return nil
  end

  -- Npc.isTradeOpen() -> bool. True while the NPC trade window is on screen
  -- (game_npctrade shows it on 0x7A and hides it on close / logout).
  function Npc.isTradeOpen()
    local m = npctradeMod()
    local w = m and m.npcWindow
    if not w or type(w.isVisible) ~= "function" then return false end
    local ok, vis = pcall(w.isVisible, w)
    return (ok and vis) and true or false
  end

  -- Npc.getBuyPrice(id) / Npc.getSellPrice(id) -> number | nil. Unit price the
  -- open NPC buys `id` for / sells `id` for, or nil if the NPC does not trade it
  -- on that side (or no window is open).
  function Npc.getBuyPrice(id)
    local entry = findTradeEntry(id, NPC_BUY)
    return entry and entry.price or nil
  end
  function Npc.getSellPrice(id)
    local entry = findTradeEntry(id, NPC_SELL)
    return entry and entry.price or nil
  end

  -- Npc.getTradeItems([kind]) -> array of { id, name, price, weight }. Snapshot of
  -- one side of the open trade window (kind: NPC_BUY=1 default = what the NPC sells
  -- to you, NPC_SELL=2 = what it buys). Empty array when nothing is offered / no
  -- window is open. Returns plain data (not the module's ItemPtr) so a script can
  -- read the offers without holding a handle to the trade window's items.
  function Npc.getTradeItems(kind)
    if kind ~= NPC_BUY and kind ~= NPC_SELL then kind = NPC_BUY end
    local out = {}
    local m = npctradeMod()
    local lists = m and m.tradeItems
    if type(lists) ~= "table" then return out end
    local list = lists[kind]
    if type(list) ~= "table" then return out end
    for _, entry in ipairs(list) do
      if type(entry) == "table" and entry.ptr then
        out[#out + 1] = {
          id = entry.ptr:getId(),
          name = entry.name,
          price = entry.price,
          weight = entry.weight,
        }
      end
    end
    return out
  end

  return Npc
end
