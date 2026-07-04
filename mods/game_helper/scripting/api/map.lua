--[[============================================================================
  scripting/api/map.lua — Zerobot-compatible `Map` namespace.
  ============================================================================

  Builder module (see scripting/scripting.lua header + scripting/CONTRACT.md).
  Returns `function(api, ctx) ... return Map end` and is injected into every
  sandboxed script as the global `Map`.

  Mirrors the Zerobot core `Map` table (Scripts/core/map.lua, 21 functions). The
  Zerobot dialect passes positions as SEPARATE x, y, z arguments and RETURNS
  position tables `{x=,y=,z=}`; this module converts to/from the engine's
  Position tables (`g_map`/`g_game` all take a single `{x,y,z}` table).

  Return-value semantics preserved EXACTLY (do not collapse):
    * nil   = no tile / no map data at that position (or entity gone).
    * false = a tile/item/creature exists but the action was NOT sent
              (validation failed: nothing movable/usable there, etc.).
    * true  = request was sent to the server.
  Pure-query getters return nil when there is no tile/map data, a value
  otherwise (matching ZB, where "no map information available" => nil).

  Cross-namespace refs are LAZY (`api.Creature`, `api.Enums` inside fns) per the
  contract — never captured at module top. This module runs OUTSIDE the sandbox,
  so it uses the real engine globals (g_game, g_map) directly.

  Engine bindings used (all verified REAL, none in corelib/globals.lua gameNoops):
    g_map.getSpectators(pos, multiFloor) / getSpectatorsInRange(pos, mf, xr, yr)
    g_map.getTile(pos) / getTiles(floor) / getCentralPosition() / findItemsById(id, max)
    g_map.isWalkable(pos, ignoreCreatures)   -- bool flag, NOT an options table:
        the granular ZB options (block-path / magic-field / floor-change / monsters
        / npcs) are evaluated here by inspecting the Tile.
    g_game.move(thing, toPos, count) / look(thing) / use(thing)
    g_game.useWith(item, toThing, subType) / useInventoryItemWith(id, toThing, subType)
    g_game.browseField(pos)
    LocalPlayer:autoWalk(destPos)   -- native Tibia map-click pathfinder.
    Tile:getThings / getTopThing / getTopUseThing / getTopCreature / getGround /
        getCreatures / getThingCount / isWalkable / isPathable / isBlocking
    Thing:isItem / isCreature / isPlayer / getId / getPosition
    Item:getId / getCount / getCountOrSubType / getTier

  Destination-position encodings (verified src/client/game.cpp:384 and
  src/client/container.h:41):
    inventory slot  -> {x=0xFFFF, y=slot,              z=0}
    container slot  -> {x=0xFFFF, y=containerId|0x40,  z=slot}
============================================================================]]

return function(api, ctx)
  local Map = {}

  -- ------------------------------------------------------------------------
  -- small local helpers (no globals created)
  -- ------------------------------------------------------------------------
  local floor = math.floor
  local abs   = math.abs

  local function pos(x, y, z) return { x = x, y = y, z = z } end

  -- Local player (live handle, nil when offline). Many ZB Map fns are
  -- screen-relative / floor-relative to the player.
  local function lp() return g_game.getLocalPlayer() end

  -- Tile at a ZB (x,y,z); nil if no tile / no map data there (ZB nil case).
  local function tileAt(x, y, z)
    if x == nil or y == nil or z == nil then return nil end
    return g_map.getTile(pos(x, y, z))
  end

  -- Build a ZB item descriptor {id, count, tier} from an engine Item/Thing.
  -- count uses getCountOrSubType (stack size OR fluid/charge subtype, matching
  -- the {id,count,tier} shape ZB hands back for ground items). tier defaults 0.
  local function itemDescriptor(thing)
    if not thing then return nil end
    local id = thing.getId and thing:getId() or 0
    local count = 1
    if thing.getCountOrSubType then
      count = thing:getCountOrSubType() or 1
    elseif thing.getCount then
      count = thing:getCount() or 1
    end
    local tier = 0
    if thing.getTier then tier = thing:getTier() or 0 end
    return { id = id, count = count, tier = tier }
  end

  -- Generic descriptor for ANY thing on a tile (item OR creature), used by
  -- getThings: items become {id,count,tier}; creatures are surfaced with their
  -- id + a creature marker so a script can tell them apart from items.
  local function thingDescriptor(thing)
    if not thing then return nil end
    if thing.isItem and thing:isItem() then
      return itemDescriptor(thing)
    end
    if thing.isCreature and thing:isCreature() then
      return { id = thing:getId(), count = 1, tier = 0, isCreature = true }
    end
    -- effects / missiles / unknown: surface the id so the list length matches.
    local id = thing.getId and thing:getId() or 0
    return { id = id, count = 1, tier = 0 }
  end

  -- The "top item" of a tile per ZB = the topmost USE thing if it is an item,
  -- else nil. (getTopUseThing returns the same thing the client would act on.)
  local function topItem(tile)
    if not tile then return nil end
    local th = tile:getTopUseThing()
    if th and th.isItem and th:isItem() then return th end
    -- Fallback: scan from top of stack for the first item (covers tiles whose
    -- top use-thing is a creature but that still hold ground/stacked items).
    local things = tile:getThings()
    if things then
      for i = #things, 1, -1 do
        local t = things[i]
        if t and t.isItem and t:isItem() then return t end
      end
    end
    return nil
  end

  -- ========================================================================
  -- 1. getCreatureIds(sameFloor, onlyPlayer) -> {cid, ...} | nil
  --    Creature ids on screen around the player. sameFloor true => only the
  --    player's floor (single-floor spectators); onlyPlayer true => players
  --    only. nil when offline / no creatures (ZB returns nil for "none").
  -- ========================================================================
  function Map.getCreatureIds(sameFloor, onlyPlayer)
    local p = lp()
    if not p then return nil end
    -- multiFloor = NOT sameFloor (ZB sameFloor=true means restrict to our floor).
    local multiFloor = not sameFloor
    local list = g_map.getSpectators(p:getPosition(), multiFloor)
    if not list then return nil end
    local out, n = {}, 0
    for _, c in ipairs(list) do
      if c then
        if not onlyPlayer or (c.isPlayer and c:isPlayer()) then
          n = n + 1
          out[n] = c:getId()
        end
      end
    end
    if n == 0 then return nil end
    return out
  end

  -- ========================================================================
  -- 2. getTiles() -> { {x,y,z, things={desc,...}}, ... }
  --    Every on-screen tile of the player's current floor, each with its
  --    position fields and a list of thing descriptors. (Adapts the engine
  --    g_map.getTiles(floor), which returns a flat list of Tile objects.)
  -- ========================================================================
  function Map.getTiles()
    local p = lp()
    if not p then return {} end
    local z = p:getPosition().z
    local tiles = g_map.getTiles(z)
    if not tiles then return {} end
    local out, n = {}, 0
    for _, tile in ipairs(tiles) do
      if tile then
        local tp = tile:getPosition()
        local things = tile:getThings() or {}
        local descs, m = {}, 0
        for _, th in ipairs(things) do
          local d = thingDescriptor(th)
          if d then m = m + 1; descs[m] = d end
        end
        n = n + 1
        out[n] = { x = tp.x, y = tp.y, z = tp.z, things = descs }
      end
    end
    return out
  end

  -- ========================================================================
  -- 3. getThings(x, y, z) -> {desc, ...} | nil
  --    Descriptors for every thing on the tile; nil if no tile / no map data.
  -- ========================================================================
  function Map.getThings(x, y, z)
    local tile = tileAt(x, y, z)
    if not tile then return nil end
    local things = tile:getThings()
    if not things then return {} end
    local out, n = {}, 0
    for _, th in ipairs(things) do
      local d = thingDescriptor(th)
      if d then n = n + 1; out[n] = d end
    end
    return out
  end

  -- ========================================================================
  -- 4. getThingsCount(x, y, z) -> number | nil
  --    Count of things on the tile; nil if no tile / no map data.
  -- ========================================================================
  function Map.getThingsCount(x, y, z)
    local tile = tileAt(x, y, z)
    if not tile then return nil end
    if tile.getThingCount then return tile:getThingCount() end
    local things = tile:getThings()
    return things and #things or 0
  end

  -- ========================================================================
  -- 5. moveItemToInventory(x, y, z, count, slot) -> true | false | nil
  --    Move the tile's top item to an inventory slot.
  --      nil   = no tile / no top item.
  --      false = bad slot.
  --      true  = move request sent.
  -- ========================================================================
  function Map.moveItemToInventory(x, y, z, count, slot)
    local tile = tileAt(x, y, z)
    if not tile then return nil end
    local item = topItem(tile)
    if not item then return nil end
    slot = api.Enums.translate.inventorySlotToEngine(slot)
    if type(slot) ~= "number" then return false end
    count = tonumber(count) or item:getCount() or 1
    g_game.move(item, pos(0xFFFF, slot, 0), count)
    return true
  end

  -- ========================================================================
  -- 6. moveItemToContainer(x, y, z, count, index, slot) -> true | false | nil
  --    Move the tile's top item to (container `index`, slot `slot`).
  --      nil   = no tile / no top item.
  --      false = the container index isn't open.
  --      true  = move request sent.
  -- ========================================================================
  function Map.moveItemToContainer(x, y, z, count, index, slot)
    local tile = tileAt(x, y, z)
    if not tile then return nil end
    local item = topItem(tile)
    if not item then return nil end
    index = tonumber(index); slot = tonumber(slot) or 0
    if not index then return false end
    local container = g_game.getContainer(index)
    if not container then return false end
    count = tonumber(count) or item:getCount() or 1
    -- container slot destination: {0xFFFF, containerId|0x40, slot}
    g_game.move(item, pos(0xFFFF, bit.bor(container:getId(), 0x40), slot), count)
    return true
  end

  -- ========================================================================
  -- 7. moveItemToGround(x, y, z, count, toX, toY, toZ) -> true | false | nil
  --    Move the tile's top item to another ground position.
  --      nil   = no source tile / no top item.
  --      false = bad destination position.
  --      true  = move request sent.
  -- ========================================================================
  function Map.moveItemToGround(x, y, z, count, toX, toY, toZ)
    local tile = tileAt(x, y, z)
    if not tile then return nil end
    local item = topItem(tile)
    if not item then return nil end
    if toX == nil or toY == nil or toZ == nil then return false end
    count = tonumber(count) or item:getCount() or 1
    g_game.move(item, pos(toX, toY, toZ), count)
    return true
  end

  -- ========================================================================
  -- 8. moveCreatureToGround(x, y, z, toX, toY, toZ) -> true | false | nil
  --    Push the tile's top creature to another ground position.
  --      nil   = no source tile / no creature there.
  --      false = bad destination position.
  --      true  = move request sent.
  -- ========================================================================
  function Map.moveCreatureToGround(x, y, z, toX, toY, toZ)
    local tile = tileAt(x, y, z)
    if not tile then return nil end
    local creature = tile:getTopCreature()
    if not creature then return nil end
    if toX == nil or toY == nil or toZ == nil then return false end
    -- creatures move as a unit (count 1).
    g_game.move(creature, pos(toX, toY, toZ), 1)
    return true
  end

  -- ========================================================================
  -- 9. goTo(x, y, z) -> void
  --    Native Tibia auto-walk (map-click pathfinder) to a position.
  -- ========================================================================
  function Map.goTo(x, y, z)
    local p = lp()
    if not p then return end
    if x == nil or y == nil or z == nil then return end
    p:autoWalk(pos(x, y, z))
  end

  -- ========================================================================
  -- 9b. stopAutoWalk() -> void
  --     Cancel an in-progress goTo()/auto-walk. Clears the client-side auto-walk
  --     route (LocalPlayer:stopAutoWalk) AND notifies the server (g_game.stop), so
  --     the character halts now instead of finishing the queued path.
  -- ========================================================================
  function Map.stopAutoWalk()
    local p = lp()
    if p and type(p.stopAutoWalk) == "function" then
      pcall(function() p:stopAutoWalk() end)
    end
    if type(g_game.stop) == "function" then
      pcall(function() g_game.stop() end)
    end
  end

  -- ========================================================================
  -- 10. browseField(x, y, z) -> void
  --     Open the "Browse Field" view of a tile.
  -- ========================================================================
  function Map.browseField(x, y, z)
    if x == nil or y == nil or z == nil then return end
    g_game.browseField(pos(x, y, z))
  end

  -- ========================================================================
  -- 11. canWalk(x, y, z, ignoreBlockPath, ignoreMagicField, ignoreMonsters,
  --             ignoreNpcs) -> bool        [DEPRECATED — use isTileWalkable]
  --     Faithful port of the Zerobot wrapper, INCLUDING its `or true` quirk:
  --     `ignoreBlockPath or true` / `ignoreMagicField or true` can never be
  --     false through this path, and ignoreFloorChange is forced true. Kept for
  --     bug-compatibility with ported scripts; new code should call
  --     isTileWalkable directly.
  -- ========================================================================
  function Map.canWalk(x, y, z, ignoreBlockPath, ignoreMagicField, ignoreMonsters, ignoreNpcs)
    local options = {
      ignoreBlockPath = ignoreBlockPath or true,
      ignoreMagicField = ignoreMagicField or true,
      ignoreFloorChange = true,
      ignoreMonsters = ignoreMonsters or false,
      ignoreNpcs = ignoreNpcs or false,
    }
    return Map.isTileWalkable(x, y, z, options)
  end

  -- ========================================================================
  -- 12. isTileWalkable(x, y, z, options) -> bool
  --     options (defaults): ignoreBlockPath=true, ignoreMagicField=true,
  --     ignoreFloorChange=true, ignoreMonsters=false, ignoreNpcs=false.
  --
  --     The engine's g_map.isWalkable(pos, ignoreCreatures) only takes a single
  --     ignore-creatures bool, so the granular ZB semantics are evaluated here
  --     by inspecting the Tile's things. Returns a plain bool (ZB never returns
  --     nil from this; an absent/empty tile is "not walkable" => false).
  -- ========================================================================
  function Map.isTileWalkable(x, y, z, options)
    options = options or {}
    if options.ignoreBlockPath   == nil then options.ignoreBlockPath   = true  end
    if options.ignoreMagicField  == nil then options.ignoreMagicField  = true  end
    if options.ignoreFloorChange == nil then options.ignoreFloorChange = true  end
    if options.ignoreMonsters    == nil then options.ignoreMonsters    = false end
    if options.ignoreNpcs        == nil then options.ignoreNpcs        = false end

    local tile = tileAt(x, y, z)
    if not tile then
      -- No tile object: fall back to the native walkability probe (which itself
      -- consults the minimap "not pathable" flag for un-cached tiles).
      return g_map.isWalkable(pos(x, y, z), true)
    end

    -- Terrain walkability. tile:isWalkable(true) ignores creatures and reports
    -- whether the GROUND/items themselves are walkable (no ground, or any
    -- isNotWalkable thing => false). A hard non-walkable tile (e.g. a wall) is
    -- NOT relaxed by ignoreBlockPath, which only concerns block-PATH (pathable)
    -- obstacles — so this is the floor of the decision.
    if not tile:isWalkable(true) then return false end

    -- Block-path: when NOT ignoring it, the tile must also be pathable (no
    -- isNotPathable thing). ignoreBlockPath=true (the default) skips this, so a
    -- block-path-only obstacle is treated as walkable. (Matches the ZB intent:
    -- "consider block path tiles as walkable".)
    if not options.ignoreBlockPath then
      if not tile:isPathable() then return false end
    end

    -- Magic field: PARTIAL. There is no Tile:hasMagicField / Item:isMagicField
    -- binding to key off, so a field that is itself walkable terrain cannot be
    -- distinguished here. We honor the flag only for fields that ALSO make the
    -- tile block-path (the common fire/energy/poison field case is caught by the
    -- isPathable check above when ignoreBlockPath is false). When
    -- ignoreMagicField is false but ignoreBlockPath is true, a walkable field is
    -- (conservatively) allowed. See report note.

    -- Creatures on the tile. Mirror the engine's own rule: the LOCAL player never
    -- blocks (standing on your own tile is walkable), and a passable/unseen
    -- creature never blocks. Otherwise a monster blocks unless ignoreMonsters, an
    -- npc unless ignoreNpcs, and another player always blocks (ZB exposes no
    -- ignore-players option).
    local creatures = tile:getCreatures()
    if creatures then
      for _, c in ipairs(creatures) do
        if c and not (c.isLocalPlayer and c:isLocalPlayer()) then
          local passable = (c.isPassable and c:isPassable())
          if not passable then
            if c.isNpc and c:isNpc() then
              if not options.ignoreNpcs then return false end
            elseif c.isMonster and c:isMonster() then
              if not options.ignoreMonsters then return false end
            else
              -- another player (or unclassified creature): blocks.
              return false
            end
          end
        end
      end
    end

    return true
  end

  -- ========================================================================
  -- 13. useItemWithInventory(x, y, z, slot) -> true | false | nil
  --     Use the tile's top (use) item ON an inventory-slot item.
  --       nil   = no tile / no usable item.
  --       false = bad slot / no item in that slot.
  --       true  = use request sent.
  -- ========================================================================
  function Map.useItemWithInventory(x, y, z, slot)
    local tile = tileAt(x, y, z)
    if not tile then return nil end
    local from = tile:getTopUseThing()
    if not from then return nil end
    slot = api.Enums.translate.inventorySlotToEngine(slot)
    if type(slot) ~= "number" then return false end
    local p = lp()
    local target = p and p:getInventoryItem(slot)
    if not target then return false end
    g_game.useWith(from, target, 0)
    return true
  end

  -- ========================================================================
  -- 14. useItemWithContainer(x, y, z, index, slot) -> true | false | nil
  --     Use the tile's top (use) item ON a container-slot item.
  --       nil   = no tile / no usable item.
  --       false = container/slot item not found.
  --       true  = use request sent.
  -- ========================================================================
  function Map.useItemWithContainer(x, y, z, index, slot)
    local tile = tileAt(x, y, z)
    if not tile then return nil end
    local from = tile:getTopUseThing()
    if not from then return nil end
    index = tonumber(index); slot = tonumber(slot)
    if not index or not slot then return false end
    local container = g_game.getContainer(index)
    if not container then return false end
    local target = container:getItem(slot)
    if not target then return false end
    g_game.useWith(from, target, 0)
    return true
  end

  -- ========================================================================
  -- 15. lookAt(x, y, z) -> true | nil
  --     Look at the tile's top look-thing.
  --       nil  = no tile / nothing to look at.
  --       true = look request sent.
  -- ========================================================================
  function Map.lookAt(x, y, z)
    local tile = tileAt(x, y, z)
    if not tile then return nil end
    local th = tile:getTopLookThing()
    if not th then return nil end
    g_game.look(th)
    return true
  end

  -- ========================================================================
  -- 16. getTopItemId(x, y, z) -> number | nil
  --     Top item id; nil if no tile / no map data / top thing isn't an item.
  -- ========================================================================
  function Map.getTopItemId(x, y, z)
    local tile = tileAt(x, y, z)
    if not tile then return nil end
    local th = tile:getTopThing()
    if not th or not (th.isItem and th:isItem()) then return nil end
    return th:getId()
  end

  -- ========================================================================
  -- 17. getTopCreatureId(x, y, z) -> number | nil
  --     Top creature id; nil if no tile / no creature on it.
  -- ========================================================================
  function Map.getTopCreatureId(x, y, z)
    local tile = tileAt(x, y, z)
    if not tile then return nil end
    local creature = tile:getTopCreature()
    if not creature then return nil end
    return creature:getId()
  end

  -- ========================================================================
  -- 18. getAllPositionsWithTopItemId(itemId, sameFloor) -> {{x,y,z}, ...} | nil
  --     Every position whose TOP item == itemId. Uses g_map.findItemsById
  --     (returns a {[Position]=Item} map of candidate tiles) and then confirms
  --     each candidate's TOP item really is itemId (findItemsById matches any
  --     occurrence in the stack, ZB wants the top one). sameFloor restricts to
  --     the player's floor. nil when none found / no map data.
  -- ========================================================================
  function Map.getAllPositionsWithTopItemId(itemId, sameFloor)
    itemId = tonumber(itemId)
    if not itemId then return nil end
    local p = lp()
    local myZ = p and p:getPosition().z or nil
    local found = g_map.findItemsById(itemId, 0) -- 0 = no cap
    if not found then return nil end
    local out, n = {}, 0
    for position, _ in pairs(found) do
      if position then
        if (not sameFloor) or (myZ ~= nil and position.z == myZ) then
          local top = Map.getTopItemId(position.x, position.y, position.z)
          if top == itemId then
            n = n + 1
            out[n] = pos(position.x, position.y, position.z)
          end
        end
      end
    end
    if n == 0 then return nil end
    return out
  end

  -- ========================================================================
  -- 19. collectRewardChest(x, y, z) -> true | false | nil
  --     Collect a reward chest (ONLY item id 19250).
  --       nil   = no tile / no top item.
  --       false = the top item isn't the reward chest (id 19250).
  --       true  = use request sent (opens the reward-chest collection window).
  -- ========================================================================
  local REWARD_CHEST_ID = 19250
  function Map.collectRewardChest(x, y, z)
    local tile = tileAt(x, y, z)
    if not tile then return nil end
    local item = topItem(tile)
    if not item then return nil end
    if item:getId() ~= REWARD_CHEST_ID then return false end
    g_game.use(item)
    return true
  end

  -- ========================================================================
  -- 20. getCameraPosition() -> {x,y,z} | nil
  --     Real-time camera/world position (best for pathfinding — the player
  --     position lags one server tick). Prefers the live map-widget camera
  --     (astra_compat g_mapView), falls back to g_map.getCentralPosition().
  -- ========================================================================
  function Map.getCameraPosition()
    if g_mapView and g_mapView.getCameraPosition then
      local ok, cam = pcall(g_mapView.getCameraPosition)
      if ok and cam and cam.x then return pos(cam.x, cam.y, cam.z) end
    end
    if g_map.getCentralPosition then
      local c = g_map.getCentralPosition()
      if c and c.x then return pos(c.x, c.y, c.z) end
    end
    return nil
  end

  -- ========================================================================
  -- 21. getPlayerOnScreen(var) -> Creature | nil
  --     Find an on-screen PLAYER by id (number) or name (string). Returns an
  --     api.Creature handle (ZB returns a Creature object), nil if not found.
  --     (The Zerobot original compared a lowercased name against a non-lowercased
  --     creature name — a latent bug; here both sides are lowercased so a
  --     name lookup is correctly case-insensitive.)
  -- ========================================================================
  function Map.getPlayerOnScreen(var)
    local playerId, playerName
    if type(var) == "number" then
      playerId = var
    elseif type(var) == "string" then
      playerName = var:lower()
    else
      return nil
    end

    local creatures = Map.getCreatureIds(true, true) -- sameFloor, onlyPlayer
    if not creatures then return nil end

    for _, cid in ipairs(creatures) do
      if playerId then
        if playerId == cid then return api.Creature(cid) end
      else
        -- resolve the name from the live engine creature, then compare.
        local c = g_map.getCreatureById(cid)
        local name = c and c.getName and c:getName()
        if name and name:lower() == playerName then
          return api.Creature(cid)
        end
      end
    end
    return nil
  end

  return Map
end
