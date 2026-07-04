--[[============================================================================
  scripting/api/game.lua — Zerobot-compatible `Game` namespace: world
  actions/queries + the EVENT SYSTEM.
  ============================================================================

  Builder module (see scripting/CONTRACT.md and the header of scripting.lua).
  Returns `function(api, ctx) ... return Game end` and is injected into every
  sandboxed script as the global `Game`.

  This is the most central module of the scripting API. It has TWO halves:

  A) ACTIONS / QUERIES (spec section 1.2): thin wrappers over the engine's
     `g_game.*` bindings, normalising Zerobot ergonomics (separate x,y,z args,
     `Enums.*` values, true/false/nil return semantics). Server-feature calls
     whose engine binding is a no-op stub (corelib/globals.lua gameNoops) or
     whose protocol is not ported in Phase 1 keep a wrapper present but return
     false/nil and log "<fn> not supported in Phase 1".

  B) EVENT SYSTEM (spec sections 1.1/1.3/1.4): `Game.Events` (the 22 event-type
     ids), `Game.registerEvent/unregisterEvent/executeEvents`, plus the
     ref-counted bridge that connects to the real engine signals (g_game's
     onTalk/onTextMessage/onModalDialog) only while at least one callback of a
     given type is registered, and disconnects when the count returns to zero.

  CONTRACT NOTES honoured here:
    * No globals: only locals + the returned table.
    * Cross-namespace refs are LAZY (api.Enums.* / api.Creature(...) inside fns).
    * Runs OUTSIDE the sandbox: full access to g_game/g_map/connect/disconnect.
    * Return semantics: true = sent; false = not sent/validation failed;
      nil = referenced entity/tile/slot does not exist.
    * Deferred callbacks (event dispatch) are stored AS `ctx.wrap(fn)` and
      tracked per-script; the script's `ctx.onCleanup` removes its callbacks and
      disconnects the engine signal when the per-type count hits 0.
============================================================================]]

return function(api, ctx)
  local Game = {}

  -- Module-level state shared across the action wrappers and the event bridge.
  --   lastEditTextId: id of the last server text window opened (onEditText), so
  --     Game.writeTextWindow (which carries no id, ZB-style) can target it.
  --   stashOpened: set true once an OPEN_STASH was observed; one of the two gates
  --     for stashRetrieve (the other is Player:isInStash(), the real depot gate).
  --   channelsHistory: session list of opened channels ({id,name}) backing
  --     Game.getChannelsHistory, filled from the onOpenChannel* signals below.
  local lastEditTextId = nil
  local stashOpened = false
  local channelsHistory = {}

  --==========================================================================
  -- Small shared helpers
  --==========================================================================

  -- Build a {x=,y=,z=} position table from separate coords (the engine's
  -- Position params accept this shape). Returns nil if any coord is missing.
  local function pos(x, y, z)
    if x == nil or y == nil or z == nil then return nil end
    return { x = x, y = y, z = z }
  end

  -- Are we able to perform a game action right now? Every engine action is
  -- gated by canPerformGameAction() in C++ (it silently drops otherwise), so we
  -- mirror that gate to return an honest `false` instead of a misleading `true`.
  local function canAct()
    return g_game.isOnline() and g_game.getLocalPlayer() ~= nil
  end

  -- Resolve a creature id to the engine Creature object (nil if gone).
  local function creatureById(cid)
    if type(cid) ~= 'number' then return nil end
    return g_map.getCreatureById(cid)
  end

  -- Log a Phase-1-unsupported call once per invocation (honest no-op).
  local function unsupported(name)
    ctx.logColor('#ffaa55', name .. ': not supported in Phase 1')
  end

  --==========================================================================
  -- A) ACTIONS / QUERIES  (spec 1.2)
  --==========================================================================

  ---------------------------------------------------------------------------
  -- Movement / direction
  ---------------------------------------------------------------------------

  -- Turn the player to a ZB direction (Enums.Directions). Diagonals are
  -- remapped via the translator. Returns true if a turn was issued.
  function Game.turn(direction)
    local eng = api.Enums.translate.directionToEngine(direction)
    if eng == nil then return false end
    if not canAct() then return false end
    g_game.turn(eng)
    return true
  end

  -- Step one tile in a ZB direction. NOTE: g_game.walk requires BOTH args
  -- (dir, withPreWalk) with no defaults (memory: walk-autowalk-arity-contract);
  -- we always pass withPreWalk=true to match interactive walking.
  function Game.walk(direction)
    local eng = api.Enums.translate.directionToEngine(direction)
    if eng == nil then return false end
    if not canAct() then return false end
    g_game.walk(eng, true)
    return true
  end

  ---------------------------------------------------------------------------
  -- Chat / channels
  ---------------------------------------------------------------------------

  -- Say / whisper / yell / talk-to-NPC. `type` is an Enums.TalkTypes value
  -- (default SAY). SAY routes through g_game.talk(); every other mode routes
  -- through talkChannel(mode, 0, msg) which is how the engine sends a non-say
  -- public message (whisper/yell/npc) without a specific channel.
  function Game.talk(message, type)
    if type == nil then type = 1 end -- TALKTYPE_SAY
    if not canAct() or message == nil or message == '' then return false end
    if type == 1 then
      g_game.talk(message)
    else
      local mode = api.Enums.translate.talkTypeToEngine(type)
      g_game.talkChannel(mode, 0, message)
    end
    return true
  end

  -- Send a message to a specific channel id. A normal channel message uses
  -- MessageModes.Channel (7), NOT Say -- this is how the console sends it
  -- (Chat.lua: g_game.talkChannel(MessageModes.Channel, channel, message)).
  function Game.talkChannel(message, channelId)
    if not canAct() or message == nil or message == '' or channelId == nil then return false end
    g_game.talkChannel(MessageModes.Channel, channelId, message)
    return true
  end

  -- Private message to a player by name (PrivateTo mode, as the console uses).
  function Game.talkPrivate(message, receiver)
    if not canAct() or message == nil or message == '' or receiver == nil or receiver == '' then return false end
    g_game.talkPrivate(MessageModes.PrivateTo, receiver, message)
    return true
  end

  -- Open / join a channel by id.
  function Game.openChannel(channelId)
    if not canAct() or channelId == nil then return false end
    g_game.joinChannel(channelId)
    return true
  end

  -- History of opened channels for the session. The engine keeps no queryable
  -- channel list, so we cache them from the same signals the console consumes
  -- (onOpenChannel / onOpenPrivateChannel, wired at the bottom of this module).
  -- Each entry is {id=<number|nil>, name=<string>}; private channels have id=nil.
  -- Returns a fresh copy so callers cannot mutate the internal buffer.
  function Game.getChannelsHistory()
    local out = {}
    for i = 1, #channelsHistory do
      local e = channelsHistory[i]
      out[i] = { id = e.id, name = e.name }
    end
    return out
  end

  ---------------------------------------------------------------------------
  -- Combat / targeting
  ---------------------------------------------------------------------------

  -- Attack a creature by id. Returns true if the attack was issued, nil if the
  -- creature id is not on the map (ZB nil = entity does not exist).
  function Game.attack(creatureId)
    local c = creatureById(creatureId)
    if not c then return nil end
    if not canAct() then return false end
    g_game.attack(c)
    return true
  end

  -- Follow a creature by id (nil if the creature does not exist).
  function Game.follow(creatureId)
    local c = creatureById(creatureId)
    if not c then return nil end
    if not canAct() then return false end
    g_game.follow(c)
    return true
  end

  ---------------------------------------------------------------------------
  -- Inventory queries
  ---------------------------------------------------------------------------

  -- Count of an item by id across the whole inventory (covers CLOSED backpacks
  -- via the 0xF5 packet — memory inventory-count-0xf5). The optional `itemTier`
  -- is accepted for ZB signature compatibility but the engine count is not
  -- tier-segmented, so a non-zero tier falls back to the untiered total.
  function Game.getItemCount(itemId, itemTier)
    local p = g_game.getLocalPlayer()
    if not p then return 0 end
    return p:getInventoryCount(itemId) or 0
  end

  -- All equipped inventory items as {id,count,tier}. Iterates the 10 equip
  -- slots (HEAD..AMMO). Items inside containers are not enumerated here (ZB's
  -- gameGetInventoryItems is the equipped set).
  function Game.getInventoryItems()
    local out = {}
    local p = g_game.getLocalPlayer()
    if not p then return out end
    for slot = 1, 10 do -- InventorySlotHead..InventorySlotAmmo
      local item = p:getInventoryItem(slot)
      if item then
        out[#out + 1] = {
          id = item:getId(),
          count = item:getCountOrSubType(),
          tier = (item.getTier and item:getTier()) or 0,
        }
      end
    end
    return out
  end

  ---------------------------------------------------------------------------
  -- Item use (ground / inventory / creature)
  ---------------------------------------------------------------------------

  -- Use an item by id from the inventory/backpacks, no target.
  function Game.useItem(itemId)
    if not canAct() or itemId == nil then return false end
    g_game.useInventoryItem(itemId)
    return true
  end

  -- Use item `itemId` (from inventory) targeting a ground position. The engine
  -- binding expects a ThingPtr, NOT a Tile (Tile and Thing are separate
  -- LuaObject branches, so a Tile dynamic-casts to a null ThingPtr and the C++
  -- call silently drops). Resolve the tile's top use-thing (falls back to the
  -- ground item) and target that, matching useItemFromGround below.
  function Game.useItemOnGround(itemId, x, y, z)
    local p = pos(x, y, z)
    if not p then return nil end
    local tile = g_map.getTile(p)
    if not tile then return nil end -- no map data / tile does not exist
    if not canAct() or itemId == nil then return false end
    local target = tile:getTopUseThing() or tile:getTopThing()
    if not target then return nil end -- empty tile, nothing to target
    g_game.useInventoryItemWith(itemId, target)
    return true
  end

  -- Use item `itemId` (from inventory) on an inventory slot. The engine has no
  -- "use item id on a slot" primitive; resolve the slot to its Item and use the
  -- source item on it.
  function Game.useItemOnInventory(itemId, inventorySlot)
    local p = g_game.getLocalPlayer()
    if not p then return nil end
    local engSlot = api.Enums.translate.inventorySlotToEngine(inventorySlot)
    local target = p:getInventoryItem(engSlot)
    if not target then return nil end
    if not canAct() or itemId == nil then return false end
    g_game.useInventoryItemWith(itemId, target)
    return true
  end

  -- Use the item that is sitting at a ground position (its top use-thing).
  function Game.useItemFromGround(x, y, z)
    local p = pos(x, y, z)
    if not p then return nil end
    local tile = g_map.getTile(p)
    if not tile then return nil end
    local thing = tile:getTopUseThing() or tile:getTopThing()
    if not thing then return nil end
    if not canAct() then return false end
    g_game.use(thing)
    return true
  end

  -- Use item `id` (from inventory) on a creature by id.
  function Game.useItemWithCreature(id, creatureId)
    local c = creatureById(creatureId)
    if not c then return nil end
    if not canAct() or id == nil then return false end
    g_game.useInventoryItemWith(id, c)
    return true
  end

  -- Equip (or de-equip) an item by id + tier.
  function Game.equipItem(itemId, tier)
    if not canAct() or itemId == nil then return false end
    g_game.equipItemId(itemId, tier or 0)
    return true
  end

  -- Loot a corpse at a position via the Quick Loot action (loot all corpses on
  -- the tile). Returns true if the request was sent, nil if the tile is absent.
  function Game.lootCorpse(x, y, z)
    local p = pos(x, y, z)
    if not p then return nil end
    if not g_map.getTile(p) then return nil end
    if not canAct() then return false end
    g_game.quickLoot(p, 0, 0, true)
    return true
  end

  ---------------------------------------------------------------------------
  -- Modal window / text window
  ---------------------------------------------------------------------------

  -- Answer a server modal window. `closeAfterAnswer` is part of the ZB
  -- signature but the engine always closes on answer, so it is accepted and
  -- ignored.
  function Game.modalWindowAnswer(id, button, choice, closeAfterAnswer)
    if not canAct() or id == nil then return false end
    g_game.answerModalDialog(id, button or 0, choice or 0)
    return true
  end

  -- Write text into an open server text window. The engine's editText(id, text)
  -- needs the window id. ZB's writeTextWindow(text) carries none, so an optional
  -- id is accepted: when given, that window is targeted; otherwise we fall back to
  -- the id of the last server text window the engine opened (tracked via
  -- onEditText, see the EDIT-TEXT id tracker further down). With neither an
  -- explicit id nor a window opened this session there is nothing to target ->
  -- honest false.
  function Game.writeTextWindow(text, id)
    if not canAct() or text == nil then return false end
    local wid = id or lastEditTextId
    if wid == nil then return false end
    g_game.editText(wid, text)
    return true
  end

  ---------------------------------------------------------------------------
  -- Forge (engine: g_game.sendForgeConverter(action))
  --   action 2 = dust -> slivers, 3 = slivers -> cores, 4 = increase dust limit
  --   (matches the forge UI buttons; the server validates them).
  ---------------------------------------------------------------------------
  -- Forge actions via g_game.sendForgeConverter(action): 2=dust->slivers,
  -- 3=slivers->cores, 4=increase dust limit (matches conversion.otui's buttons).
  -- sendForgeConverter is a corelib no-op (gameNoops, installed as `x = x or noop`)
  -- UNLESS the game_forge mod re-binds it to the real sender (forge.lua:400). It does
  -- that on load and ForgeClient is module-local, so we gate on game_forge being
  -- loaded -- otherwise the no-op would fake success. The server still validates that
  -- the forge window is open.
  local function forgeModLoaded()
    local m = g_modules and g_modules.getModule and g_modules.getModule('game_forge')
    return m ~= nil and m:isLoaded()
  end
  local function forgeConverter(action, name)
    if not canAct() then return false end
    if not forgeModLoaded() then unsupported(name); return false end
    g_game.sendForgeConverter(action)
    return true
  end
  function Game.forgeConvertDust()    return forgeConverter(2, 'Game.forgeConvertDust') end
  function Game.forgeConvertSlivers() return forgeConverter(3, 'Game.forgeConvertSlivers') end
  function Game.forgeIncreaseLimit()  return forgeConverter(4, 'Game.forgeIncreaseLimit') end

  ---------------------------------------------------------------------------
  -- Imbuement (engine bindings exist natively)
  ---------------------------------------------------------------------------

  -- Apply an imbuement to an open item's slot (slot is 0-based, as in ZB).
  -- NOTE: `isProtected` (protection charm) has NO EFFECT on this server. The client
  -- sends the byte, but the crystalserver parseApplyImbuement discards it and its
  -- imbuement flow (playerApplyImbuement -> onApplyImbuement) has no fail/protection
  -- concept (imbuing always succeeds paying gold+materials). Kept for ZB signature
  -- parity; the imbuement is still applied, just never "protected".
  function Game.applyImbuement(slot, imbuementId, isProtected)
    if not canAct() or slot == nil or imbuementId == nil then return false end
    g_game.applyImbuement(slot, imbuementId, isProtected and true or false)
    return true
  end

  -- Apply an imbuement onto an Imbue Scroll. The scroll window must already be
  -- open (the user/script selected the scroll). In that window the engine applies
  -- via applyImbuement(0, imbuementId) -- slot 0, never protected -- exactly as
  -- the game_tibia_imbui scroll UI does (imbuementscroll.lua: applyImbuement(0,
  -- imbuement.id)). We also call selectImbuementScroll() first as a best-effort
  -- to (re)select the scroll as the target, mirroring onSelectScroll. If no scroll
  -- window is open the server simply ignores the apply (engine drops it).
  function Game.applyImbuementOnScroll(imbuementId)
    if not canAct() or imbuementId == nil then return false end
    if type(g_game.selectImbuementScroll) == 'function' then
      g_game.selectImbuementScroll()
    end
    g_game.applyImbuement(0, imbuementId, false)
    return true
  end

  -- Clear the imbuement at a slot (0-based).
  function Game.clearImbuement(slot)
    if not canAct() or slot == nil then return false end
    g_game.clearImbuement(slot)
    return true
  end

  -- Close the imbuement window.
  function Game.closeImbuementWindow()
    if not canAct() then return false end
    g_game.closeImbuingWindow()
    return true
  end

  ---------------------------------------------------------------------------
  -- Auto Loot. ZB's autoLoot is client-side walk-to-corpse automation; KoliseuOT
  -- instead has SERVER-SIDE native auto loot (Player::checkAutoLoot, kv
  -- features.autoloot: 0=off, 1=on/bosses-excluded, 2=on/bosses-included) with no
  -- client opcode to toggle it. We drive it through the '!autoloot' talkaction
  -- (server: data/scripts/talkactions/player/autoloot.lua) which, with no argument,
  -- toggles the state OFF<->ON. Sent via g_game.talk like any command; returns true
  -- once the say is issued (ZB 'true = sent'). If the talkaction is absent the
  -- server just treats it as normal chat -- harmless.
  ---------------------------------------------------------------------------
  function Game.autoLoot()
    if not canAct() then return false end
    g_game.talk('!autoloot')
    return true
  end

  ---------------------------------------------------------------------------
  -- Quest log (engine: requestQuestLog / requestQuestLine are REAL)
  ---------------------------------------------------------------------------

  -- Request the quest log; the QUEST_LOG event fires with the data (the event
  -- source onQuestLog is now wired in the event bridge below, closing the loop).
  function Game.requestQuestLog()
    if not canAct() then return false end
    g_game.requestQuestLog()
    return true
  end

  -- Request the lines/missions of a quest by id (QUEST_LINES event fires; its
  -- onQuestLine source is wired in the event bridge below).
  function Game.requestQuestLines(questId)
    if not canAct() or questId == nil then return false end
    g_game.requestQuestLine(questId)
    return true
  end

  ---------------------------------------------------------------------------
  -- Stash retrieve. The corelib lists stashWithdraw in gameNoops, but the
  -- game_stash mod RE-BINDS g_game.stashWithdraw(itemId, tier, count) at init to
  -- a real packet sender (sendSupplyStashRequest, 0x28/ACTION_WITHDRAW). We map
  -- ZB's stashRetrieve(itemId, itemCount) -> stashWithdraw(itemId, 0, itemCount).
  --
  -- Gate: game_stash loaded (so stashWithdraw is the REAL sender, not the corelib
  -- noop of the same name -- a bare type()=='function' can't tell them apart) AND
  -- the stash being available. The server's actual gate for a withdraw is depot
  -- proximity (isStashMenuAvailable), mirrored client-side by Player:isInStash()
  -- (set from the 0x2A special-container packet, stash.lua). We accept isInStash()
  -- OR the legacy stashOpened flag, so a script no longer has to observe an
  -- OPEN_STASH first; far from a depot isInStash() is false and the server would
  -- drop it anyway.
  ---------------------------------------------------------------------------
  local function stashModLoaded()
    local m = g_modules and g_modules.getModule and g_modules.getModule('game_stash')
    return m ~= nil and m:isLoaded()
  end
  function Game.stashRetrieve(itemId, itemCount)
    if not canAct() or itemId == nil then return false end
    if not stashModLoaded() then return false end
    local p = g_game.getLocalPlayer()
    local inStash = p and p.isInStash and p:isInStash()
    if not inStash and not stashOpened then return false end
    g_game.stashWithdraw(itemId, 0, itemCount or 1)
    return true
  end

  ---------------------------------------------------------------------------
  -- Game store (engine bindings exist natively)
  ---------------------------------------------------------------------------

  -- Buy a store offer. offerType is an Enums.GameStoreOfferType value, passed
  -- through to the engine as the product type. The engine call also wants a
  -- name string (empty here; the offer id identifies the product).
  -- Game store is DISABLED on this server: the 0xFA/0xFB/0xFC client opcodes are
  -- commented out server-side (no parseStore* handler), so sending them only makes the
  -- server log "unknown packet header". We therefore DO NOT send and report not-sent
  -- (false), instead of silently desyncing. If the store is re-enabled server-side,
  -- restore the g_game.buyStoreOffer/openStore/requestStoreOffers calls below.
  function Game.storeBuyOffer(offerId, offerType)
    unsupported('storeBuyOffer (game store disabled on this server)')
    return false
  end

  -- Open the game store window. (Disabled server-side -- see storeBuyOffer.)
  function Game.storeOpen()
    unsupported('storeOpen (game store disabled on this server)')
    return false
  end

  -- Request offers for a store category by name. (Disabled server-side.)
  function Game.storeRequestOffers(categoryName)
    unsupported('storeRequestOffers (game store disabled on this server)')
    return false
  end

  -- Current Tibia coins balance (cached engine value).
  function Game.storeGetTibiaCoinsBalance()
    return g_game.getTibiaCoins() or 0
  end

  -- Current transferable coins balance (cached engine value).
  function Game.storeGetTransferableCoinsBalance()
    return g_game.getTransferableTibiaCoins() or 0
  end

  ---------------------------------------------------------------------------
  -- Daily reward. The game_dailyreward mod re-binds real senders over the corelib
  -- noops at init (dailyrewardprotocol.lua): g_game.openDailyReward() -> 0xD8
  -- (open the wall) and g_game.dailyRewardConfirm(target, items) -> 0xDA (collect).
  -- Because the corelib installs NO-OP functions of the SAME names (gameNoops),
  -- type(g_game.openDailyReward)=='function' is TRUE whether the real sender or the
  -- noop is bound -- indistinguishable -- so we gate on the mod being loaded
  -- (dailyRewardModLoaded), exactly like forgeModLoaded, otherwise the noop would
  -- fake success.
  ---------------------------------------------------------------------------
  local function dailyRewardModLoaded()
    local m = g_modules and g_modules.getModule and g_modules.getModule('game_dailyreward')
    return m ~= nil and m:isLoaded()
  end

  -- Normalise ZB's itemsToPick into the {[itemId]=count} map dailyRewardConfirm
  -- wants. Accepts a {[itemId]=count} map, an array of {itemId=,count=} (also
  -- {id=,count=} or {itemId,count}) records, or nil/empty for prey & xp-boost days
  -- (which carry no columns). Bad/non-table entries are skipped; counts default to
  -- 1 and are summed if an id repeats. The sender clamps each count to a byte.
  local function normalizePickItems(itemsToPick)
    local out = {}
    if type(itemsToPick) ~= 'table' then return out end
    for k, v in pairs(itemsToPick) do
      local id, count
      if type(v) == 'table' then
        id    = tonumber(v.itemId or v.id or v[1])
        count = tonumber(v.count or v.amount or v[2]) or 1
      else
        id    = tonumber(k)      -- map form: [itemId] = count
        count = tonumber(v) or 1
      end
      if id and id > 0 then
        out[id] = (out[id] or 0) + count
      end
    end
    return out
  end

  -- Collect the daily reward. dailyRewardConfirm(panel, items): panel truthy ->
  -- target byte 1 (tibia panel, consumes a collection token), else 0 (shrine), so
  -- ZB's isFromShrine maps to `not isFromShrine` (matching dailyreward.lua's
  -- onClickConfirm: dailyRewardConfirm(not gameFromShrine, items)). One opcode per
  -- message, so on prey/xp-boost days the empty column list is simply not read by
  -- the server (no desync); invalid picks on an item day are refused server-side.
  function Game.collectDailyReward(isFromShrine, itemsToPick)
    if not canAct() then return false end
    if not dailyRewardModLoaded() then unsupported('Game.collectDailyReward'); return false end
    g_game.dailyRewardConfirm(not isFromShrine, normalizePickItems(itemsToPick))
    return true
  end

  -- Open the reward wall (0xD8). The 0xE2 response drives game_dailyreward's
  -- onOpenRewardWall, which shows + focuses the wall window, so the raw sender is
  -- enough to open it on screen.
  function Game.openDailyReward()
    if not canAct() then return false end
    if not dailyRewardModLoaded() then unsupported('Game.openDailyReward'); return false end
    g_game.openDailyReward()
    return true
  end

  ---------------------------------------------------------------------------
  -- Hunting task — server feature disabled on KoliseuOT (TASK_HUNTING_ENABLED
  -- off; game_prey_hunting removed). All Phase 2 / not applicable. Wrappers are
  -- present for ZB script compatibility and return false honestly.
  ---------------------------------------------------------------------------
  function Game.huntingTaskRerollList(slot)        unsupported('Game.huntingTaskRerollList');        return false end
  function Game.huntingTaskRerollRewards(slot)     unsupported('Game.huntingTaskRerollRewards');     return false end
  function Game.huntingTaskListAllMonsters(slot)   unsupported('Game.huntingTaskListAllMonsters');   return false end
  function Game.huntingTaskSelectMonster(slot, raceId, selectMaximumAmount)
    unsupported('Game.huntingTaskSelectMonster'); return false
  end
  function Game.huntingTaskCancel(slot)            unsupported('Game.huntingTaskCancel');            return false end
  function Game.huntingTaskClaim(slot)             unsupported('Game.huntingTaskClaim');             return false end

  --==========================================================================
  -- B) EVENT SYSTEM  (spec 1.1 / 1.3 / 1.4)
  --==========================================================================

  ---------------------------------------------------------------------------
  -- 1.1 Event-type enum (EXACT Zerobot values).
  ---------------------------------------------------------------------------
  Game.Events = {
    TALK = 0,
    MAGIC_EFFECT = 1,
    HUD_CLICK = 2,
    HOTKEY_SHORTCUT_PRESS = 3,
    TEXT_MESSAGE = 4,
    MODAL_WINDOW = 5,
    CUSTOM_MODAL_WINDOW_BUTTON_CLICK = 6,
    IMBUEMENT_DATA = 7,
    IMBUEMENT_OPEN_WINDOW = 8,
    QUEST_LOG = 9,
    QUEST_LINES = 10,
    DISTANCE_SHOOT_EFFECT = 11,
    PARTY_HUNT = 12,
    LABEL = 13,
    OPEN_STASH = 14,
    HUD_DRAG = 15,
    STORE_CATEGORIES = 16,
    STORE_OFFERS = 17,
    OPEN_DAILY_REWARD = 18,
    DAILY_REWARD_DAYS_DATA = 19,
    ALARM = 20,
    TASK_HUNTING_DATA = 21,
  }

  ---------------------------------------------------------------------------
  -- Internal event registry, mirroring Zerobot's ref-counted model.
  --   registered[type] = ordered list of WRAPPED callbacks (ctx.wrap'd).
  --   registered[type][i].wrapped  -- the wrapper actually invoked
  --   registered[type][i].raw      -- the user's fn (identity for unregister)
  --   registered[type][i].owner    -- the script record that registered it
  --   counts[type] = #callbacks for that type (drives connect/disconnect).
  ---------------------------------------------------------------------------
  local registered = {}
  local counts = {}

  -- Forward decls for the per-type engine (dis)connect bridge.
  local enableSource, disableSource

  -- Public dispatcher. Called by the engine bridge below AND by other modules
  -- (e.g. hud.lua does `Game.executeEvents(Game.Events.HUD_CLICK, id)`).
  -- Iterates a SNAPSHOT so a handler may register/unregister during dispatch.
  function Game.executeEvents(hookType, ...)
    local list = registered[hookType]
    if not list or #list == 0 then return end
    local snapshot = {}
    for i = 1, #list do snapshot[i] = list[i] end
    for i = 1, #snapshot do
      local cb = snapshot[i].wrapped
      if cb then cb(...) end -- wrapper handles pcall + error accounting + no-op-if-disabled
    end
  end

  -- Register a callback for a Game.Events.* type. Stores ctx.wrap(fn) (so the
  -- deferred call runs in the registering script's context with error
  -- accounting), tracks the owner for cleanup, and enables the engine source on
  -- the 0->1 transition. Returns the ORIGINAL fn (ZB contract: handy for
  -- unregister). Also schedules removal on the owning script's cleanup.
  function Game.registerEvent(eventType, fn)
    if eventType == nil then error('Game.registerEvent(type, fn): type is nil', 2) end
    if type(fn) ~= 'function' then error('Game.registerEvent(type, fn): fn must be a function', 2) end

    local wrapped = ctx.wrap(fn)             -- captures the current script NOW
    local owner = ctx.runningScript()
    local list = registered[eventType]
    if not list then list = {}; registered[eventType] = list end

    local entry = { wrapped = wrapped, raw = fn, owner = owner }
    list[#list + 1] = entry
    counts[eventType] = (counts[eventType] or 0) + 1
    if counts[eventType] == 1 then enableSource(eventType) end

    -- Auto-remove this callback when the owning script unloads/errors/relogs, so
    -- a script never leaks an engine connection. Mirrors ZB unregister but keyed
    -- to the script lifecycle. The handle is fire-once.
    if owner then
      local removed = false
      ctx.onCleanup(function()
        if removed then return end
        removed = true
        Game.unregisterEvent(eventType, fn)
      end)
    end

    return fn
  end

  -- Remove a previously registered callback (matched by the ORIGINAL fn). On the
  -- 1->0 transition the engine source for that type is disconnected.
  function Game.unregisterEvent(eventType, fn)
    local list = registered[eventType]
    if not list then return end
    for i = 1, #list do
      if list[i].raw == fn then
        table.remove(list, i)
        counts[eventType] = (counts[eventType] or 1) - 1
        if counts[eventType] <= 0 then
          counts[eventType] = 0
          disableSource(eventType)
        end
        return
      end
    end
  end

  --==========================================================================
  -- Engine bridge: connect a Game.Events.* type to the real engine signal and
  -- translate the engine payload into the Zerobot callback shape (spec 1.4).
  --
  -- Only the sources with a clear Phase-1 origin are wired (TALK, TEXT_MESSAGE,
  -- MODAL_WINDOW). The rest accept registration and dispatch (so HUD_CLICK/
  -- HUD_DRAG/CUSTOM_MODAL_WINDOW_BUTTON_CLICK work when fired by other modules
  -- via Game.executeEvents), but have NO engine source attached in Phase 1.
  --==========================================================================

  -- Translator closures, created once. Each forwards into Game.executeEvents
  -- with the ZB-shaped arguments. These are the handler tables we connect()/
  -- disconnect() on g_game; we keep stable references so disconnect matches.
  local sourceHandlers = {}   -- [eventType] = { connectTarget, handlerTable }
  local sourceConnected = {}  -- [eventType] = true while connected

  -- TALK: engine onTalk(name, level, mode, text, channelId, pos)
  --   -> ZB (authorName, authorLevel, type, x, y, z, text, channelId)
  local function onEngineTalk(name, level, mode, text, channelId, p)
    local zbType = api.Enums.translate.talkTypeFromEngine(mode)
    local x, y, z
    if p then x, y, z = p.x, p.y, p.z end
    Game.executeEvents(Game.Events.TALK, name, level, zbType, x, y, z, text, channelId)
  end

  -- TEXT_MESSAGE: engine onTextMessage(mode, text) -> ZB (messageData).
  --   The engine only delivers mode + text; the richer numeric/colour/position
  --   fields are not available here, so they are left nil. messageType is the
  --   translated ZB MessageTypes value (nil if no clean counterpart).
  local function onEngineTextMessage(mode, text)
    local messageData = {
      channelId = nil,
      messagePrimaryValue = nil,
      messagePrimaryColor = nil,
      messageSecondaryValue = nil,
      messageSecondaryColor = nil,
      x = nil, y = nil, z = nil,
      text = text,
      messageType = api.Enums.translate.messageTypeFromEngine(mode),
    }
    Game.executeEvents(Game.Events.TEXT_MESSAGE, messageData)
  end

  -- MODAL_WINDOW: engine onModalDialog(id, title, message, buttonList,
  --   enterButton, escapeButton, choiceList, priority) -> ZB (modalWindowData).
  --   buttonList/choiceList are arrays of {idValue, textValue} tuples.
  local function onEngineModalDialog(id, title, message, buttonList, enterButton, escapeButton, choiceList, priority)
    local buttons = {}
    if buttonList then
      for i = 1, #buttonList do
        buttons[i] = { id = buttonList[i][1], text = buttonList[i][2] }
      end
    end
    local choices = {}
    if choiceList then
      for i = 1, #choiceList do
        choices[i] = { id = choiceList[i][1], text = choiceList[i][2] }
      end
    end
    local modalWindowData = {
      defaultEscapeButton = escapeButton,
      defaultEnterButton = enterButton,
      priority = priority,
      title = title,
      message = message,
      id = id,
      buttons = buttons,
      choices = choices,
    }
    Game.executeEvents(Game.Events.MODAL_WINDOW, modalWindowData)
  end

  -- DISTANCE_SHOOT_EFFECT: engine g_map.onMissle(missile) -> ZB
  --   (type, fromX,fromY,fromZ, toX,toY,toZ). The Missile object (bound:
  --   getId/getSource/getDestination) gives the shot id and two Positions
  --   ({x,y,z} tables, or nil if invalid). Fires for both legacy 0x85 and the
  --   modern 0x83 distance branch (both go through Map::addThing -> onMissle).
  local function onEngineMissle(missile)
    if not missile then return end
    local from = missile:getSource()
    local to = missile:getDestination()
    local fx, fy, fz, tx, ty, tz
    if from then fx, fy, fz = from.x, from.y, from.z end
    if to then tx, ty, tz = to.x, to.y, to.z end
    Game.executeEvents(Game.Events.DISTANCE_SHOOT_EFFECT, missile:getId(), fx, fy, fz, tx, ty, tz)
  end

  -- MAGIC_EFFECT: engine g_map.onEffect(effectId, pos) -> ZB (type, x, y, z),
  --   where `type` is the effect id and (x,y,z) is the tile it played on. The C++
  --   side (Map::addThing) emits this for BOTH the legacy single-effect 0x83 branch
  --   and the modern MAGIC_EFFECTS_CREATE_EFFECT loop (both reach addThing), mirroring
  --   how onMissle is emitted. HIGH FREQUENCY in hunts: keep this cheap -- just unpack
  --   the position table and dispatch, no allocation/scan per effect.
  local function onEngineEffect(effectId, p)
    local x, y, z
    if p then x, y, z = p.x, p.y, p.z end
    Game.executeEvents(Game.Events.MAGIC_EFFECT, effectId, x, y, z)
  end

  -- QUEST_LOG: engine onQuestLog(questList) where questList is an array of
  --   {idValue, nameValue, completedBool} tuples -> ZB (quests) =
  --   {quests=[{id, name, state}]}. state: ZB QuestState (0=pending,1=completed),
  --   derived from the completed bool.
  local function onEngineQuestLog(questList)
    local quests = {}
    if questList then
      for i = 1, #questList do
        local q = questList[i]
        quests[i] = { id = q[1], name = q[2], state = (q[3] and 1 or 0) }
      end
    end
    Game.executeEvents(Game.Events.QUEST_LOG, { quests = quests })
  end

  -- QUEST_LINES: engine onQuestLine(questId, questMissions) where each mission is
  --   a {nameValue, descriptionValue, missionIdValue} tuple -> ZB
  --   (questId, missions) with missions = {missions=[{name, missionId, description}]}.
  local function onEngineQuestLine(questId, questMissions)
    local missions = {}
    if questMissions then
      for i = 1, #questMissions do
        local m = questMissions[i]
        missions[i] = { name = m[1], description = m[2], missionId = m[3] }
      end
    end
    Game.executeEvents(Game.Events.QUEST_LINES, questId, { missions = missions })
  end

  -- STORE_CATEGORIES: engine onStoreCategories(categories) -> ZB
  --   (storeCategoriesData). The ZB payload is opaque ("store categories data");
  --   pass the engine categories table straight through.
  local function onEngineStoreCategories(categories)
    Game.executeEvents(Game.Events.STORE_CATEGORIES, categories)
  end

  -- STORE_OFFERS: engine onStoreOffers(categoryName, offers, redirect,
  --   sortingType, filters, currentFilter, reasons) -> ZB (storeOffersData).
  --   ZB's payload is opaque; assemble a table preserving the engine fields.
  local function onEngineStoreOffers(categoryName, offers, redirect, sortingType, filters, currentFilter, reasons)
    Game.executeEvents(Game.Events.STORE_OFFERS, {
      categoryName = categoryName,
      offers = offers,
      redirect = redirect,
      sortingType = sortingType,
      filters = filters,
      currentFilter = currentFilter,
      reasons = reasons,
    })
  end

  -- OPEN_DAILY_REWARD: engine onOpenRewardWall(fromShrine, nextRewardTime,
  --   dayStreakDay, message, state, jokers, serverSave, streakLevel) [crystalserver
  --   dailyrewardprotocol.lua] -> ZB (dailyRewardData). ZB's payload is opaque;
  --   assemble a table of the engine fields.
  local function onEngineOpenRewardWall(fromShrine, nextRewardTime, dayStreakDay, message, state, jokers, serverSave, streakLevel)
    Game.executeEvents(Game.Events.OPEN_DAILY_REWARD, {
      fromShrine = fromShrine,
      nextRewardTime = nextRewardTime,
      dayStreakDay = dayStreakDay,
      message = message,
      state = state,
      jokers = jokers,
      serverSave = serverSave,
      streakLevel = streakLevel,
    })
  end

  -- DAILY_REWARD_DAYS_DATA: engine onDailyReward(freeRewards, premiumRewards,
  --   descriptions) (0xE4) -> ZB (dailyRewardDaysData). Opaque ZB payload;
  --   assemble a table of the engine fields.
  local function onEngineDailyReward(freeRewards, premiumRewards, descriptions)
    Game.executeEvents(Game.Events.DAILY_REWARD_DAYS_DATA, {
      freeRewards = freeRewards,
      premiumRewards = premiumRewards,
      descriptions = descriptions,
    })
  end

  -- IMBUEMENT_OPEN_WINDOW: engine onOpenImbuementWindow(itemId) (modern CHOICE
  --   branch) -> ZB () (the ZB callback takes no args). We drop the itemId.
  local function onEngineOpenImbuementWindow(_itemId)
    Game.executeEvents(Game.Events.IMBUEMENT_OPEN_WINDOW)
  end

  -- IMBUEMENT_DATA: engine onImbuementItem(itemId, tier, slots, activeSlots,
  --   imbuements, neededItems, itemName) -> ZB (imbuementData). Reshape:
  --     availableImbuements <- imbuements (each Imbuement table has id/name/tier/
  --       description/sources=[{item=ItemObj, description}]/cost/...). ZB wants
  --       {imbuementId, imbuementName, imbuementLevel, imbuementDescription,
  --        items=[{itemId,count}]}; map imbuementLevel<-tier and items from sources.
  --     slotImbuements <- activeSlots, a SPARSE map keyed by 0-based slot index,
  --       each value a tuple {[1]=Imbuement, [2]=duration, [3]=removalCost}. ZB
  --       wants {imbuementId, imbuementName, imbuementLevel, imbuementDescription,
  --        clearPrice, imbuementPrice, timeRemaining, empty} per slot (0..slots-1).
  --   Fields the engine does not provide are left nil (documented).
  local function reshapeImbuement(imb)
    if not imb then return nil end
    local items = {}
    if imb.sources then
      for i = 1, #imb.sources do
        local src = imb.sources[i]
        local it = src and src.item
        if it then
          items[#items + 1] = {
            itemId = it:getId(),
            count = (it.getCount and it:getCount()) or 1,
          }
        end
      end
    end
    return {
      imbuementId = imb.id,
      imbuementName = imb.name,
      imbuementLevel = imb.tier,            -- ZB "level" ~ engine imbuement tier
      imbuementDescription = imb.description,
      imbuementPrice = imb.cost,            -- carried through for slotImbuements use
      items = items,
    }
  end

  local function onEngineImbuementItem(itemId, _tier, slots, activeSlots, imbuements, _neededItems, _itemName)
    local availableImbuements = {}
    if imbuements then
      for i = 1, #imbuements do
        availableImbuements[i] = reshapeImbuement(imbuements[i])
      end
    end

    local slotImbuements = {}
    slots = slots or 0
    for i = 0, slots - 1 do
      local entry = activeSlots and activeSlots[i]
      local base = entry and entry[1] and reshapeImbuement(entry[1])
      if base then
        slotImbuements[i + 1] = {
          imbuementId = base.imbuementId,
          imbuementName = base.imbuementName,
          imbuementLevel = base.imbuementLevel,
          imbuementDescription = base.imbuementDescription,
          clearPrice = entry[3],            -- removalCost
          imbuementPrice = base.imbuementPrice, -- cost
          timeRemaining = entry[2],         -- duration left (seconds)
          empty = false,
        }
      else
        slotImbuements[i + 1] = { empty = true }
      end
    end

    Game.executeEvents(Game.Events.IMBUEMENT_DATA, {
      itemId = itemId,
      slots = slots,
      availableImbuements = availableImbuements,
      slotImbuements = slotImbuements,
    })
  end

  -- PARTY_HUNT: engine onPartyAnalyzer(startTime, leaderId, priceType,
  --   membersData, membersName) -> ZB (output). ZB's payload is opaque "output";
  --   assemble a table preserving the engine fields (game_analyser maps
  --   membersData[*] columns: [1]=loot,[2]=supply,[3]=damage,[4]=healing).
  local function onEnginePartyAnalyzer(startTime, leaderId, priceType, membersData, membersName)
    Game.executeEvents(Game.Events.PARTY_HUNT, {
      startTime = startTime,
      leaderId = leaderId,
      priceType = priceType,
      membersData = membersData,
      membersName = membersName,
    })
  end

  -- Map each wired event type to (a) the engine object to connect on and (b) the
  -- signal-name -> handler table. Lazy: built on first enable so g_game/g_map are
  -- ready. The handler table is connect()'d on the target; corelib connect chains
  -- onto any existing handler (the UI mods already connect their own onStoreOffers
  -- etc.), so ours coexists. We keep stable closure refs so disconnect matches.
  local function buildSourceSpec(eventType)
    local E = Game.Events
    if eventType == E.TALK then
      return g_game, { onTalk = onEngineTalk }
    elseif eventType == E.TEXT_MESSAGE then
      return g_game, { onTextMessage = onEngineTextMessage }
    elseif eventType == E.MODAL_WINDOW then
      return g_game, { onModalDialog = onEngineModalDialog }
    elseif eventType == E.DISTANCE_SHOOT_EFFECT then
      return g_map, { onMissle = onEngineMissle }
    elseif eventType == E.MAGIC_EFFECT then
      return g_map, { onEffect = onEngineEffect }
    elseif eventType == E.QUEST_LOG then
      return g_game, { onQuestLog = onEngineQuestLog }
    elseif eventType == E.QUEST_LINES then
      return g_game, { onQuestLine = onEngineQuestLine }
    elseif eventType == E.STORE_CATEGORIES then
      return g_game, { onStoreCategories = onEngineStoreCategories }
    elseif eventType == E.STORE_OFFERS then
      return g_game, { onStoreOffers = onEngineStoreOffers }
    elseif eventType == E.OPEN_DAILY_REWARD then
      return g_game, { onOpenRewardWall = onEngineOpenRewardWall }
    elseif eventType == E.DAILY_REWARD_DAYS_DATA then
      return g_game, { onDailyReward = onEngineDailyReward }
    elseif eventType == E.IMBUEMENT_OPEN_WINDOW then
      return g_game, { onOpenImbuementWindow = onEngineOpenImbuementWindow }
    elseif eventType == E.IMBUEMENT_DATA then
      return g_game, { onImbuementItem = onEngineImbuementItem }
    elseif eventType == E.PARTY_HUNT then
      return g_game, { onPartyAnalyzer = onEnginePartyAnalyzer }
    end
    -- ----------------------------------------------------------------------
    -- OPEN_STASH is handled specially in enableSource/disableSource (it hooks the
    -- game_stash global showStash, not a connect() signal), so it returns nil here.
    --
    -- Genuinely INACTIVE (declared, registrable, dispatchable via
    -- Game.executeEvents, but NO engine source — see the analysis):
    --   HOTKEY_SHORTCUT_PRESS — needs C++ (no native signal for the in-game
    --     hotkey-slot system; g_keyboard is only an approximation of raw keys).
    --   HUD_CLICK / HUD_DRAG / CUSTOM_MODAL_WINDOW_BUTTON_CLICK — client-internal,
    --     fired by other modules (hud.lua) via Game.executeEvents; never connect.
    --   LABEL — cavebot-internal; fired by the cavebot waypoint executor.
    --   ALARM — no server source (ZB-internal alarm subsystem only).
    --   TASK_HUNTING_DATA — server feature removed (TASK_HUNTING_ENABLED off).
    -- ----------------------------------------------------------------------
    return nil, nil
  end

  --------------------------------------------------------------------------
  -- OPEN_STASH special source: hook the game_stash global showStash.
  --
  -- The stash mod parses 0x29 itself and calls the GLOBAL showStash(items,
  -- maxSlots) directly (no g_game.onX signal), so there is nothing to connect().
  -- We install a wrapper over showStash that (1) emits OPEN_STASH with the ZB
  -- shape {stashItems=[{itemId,count}], freeSlots} and (2) calls the ORIGINAL so
  -- the stash UI keeps working. Items from buildStashItem carry {itemId,itemCount}
  -- (older parse rows used {itemId,amount}); we read whichever is present. The
  -- server sends no freeSlots, so maxSlots (the 2nd arg) is used (0 in practice).
  -- Idempotent (the `stashHookInstalled` flag) and restored on disable. Hooking a
  -- mod global is the sanctioned mechanism here; we never create a NEW global.
  local stashHookInstalled = false
  local stashOriginalShowStash = nil
  local stashWrapper = nil  -- the exact wrapper we installed (for safe restore)

  local function emitOpenStash(items, maxSlots)
    stashOpened = true
    local stashItems = {}
    if items then
      for _, it in pairs(items) do
        if type(it) == 'table' then
          local count = it.itemCount or it.amount or it.count
          stashItems[#stashItems + 1] = { itemId = it.itemId, count = count }
        end
      end
    end
    Game.executeEvents(Game.Events.OPEN_STASH, {
      stashItems = stashItems,
      freeSlots = maxSlots or 0,
    })
  end

  local function installStashHook()
    if stashHookInstalled then return end
    -- showStash is a function global defined by the game_stash mod; absent if the
    -- mod is not loaded. Resolve via _G WITHOUT creating a new global.
    local current = rawget(_G, 'showStash')
    if type(current) ~= 'function' then return end -- mod not loaded: silently skip
    stashOriginalShowStash = current
    stashWrapper = function(items, maxSlots, ...)
      -- Emit first (best-effort, isolated), then ALWAYS run the original so a
      -- handler error can never break the stash UI.
      pcall(emitOpenStash, items, maxSlots)
      return stashOriginalShowStash(items, maxSlots, ...)
    end
    rawset(_G, 'showStash', stashWrapper)
    stashHookInstalled = true
  end

  local function removeStashHook()
    if not stashHookInstalled then return end
    -- Only restore if OUR wrapper is still the installed one: comparing identity
    -- avoids clobbering a later re-definition by the mod (e.g. across a reload).
    if rawget(_G, 'showStash') == stashWrapper and stashOriginalShowStash ~= nil then
      rawset(_G, 'showStash', stashOriginalShowStash)
    end
    stashOriginalShowStash = nil
    stashWrapper = nil
    stashHookInstalled = false
  end

  -- Enable the engine source for an event type (0->1 transition). No-op for the
  -- truly inactive types (they still dispatch via Game.executeEvents from
  -- elsewhere). OPEN_STASH uses the showStash hook instead of a connect().
  enableSource = function(eventType)
    if sourceConnected[eventType] then return end
    if eventType == Game.Events.OPEN_STASH then
      installStashHook()
      sourceConnected[eventType] = true
      return
    end
    local target, handlers = buildSourceSpec(eventType)
    if not target or not handlers then return end -- inactive (no engine source)
    sourceHandlers[eventType] = { target = target, handlers = handlers }
    connect(target, handlers)
    sourceConnected[eventType] = true
  end

  -- Disable the engine source for an event type (1->0 transition).
  disableSource = function(eventType)
    if not sourceConnected[eventType] then return end
    if eventType == Game.Events.OPEN_STASH then
      removeStashHook()
      sourceConnected[eventType] = nil
      return
    end
    local spec = sourceHandlers[eventType]
    if spec then disconnect(spec.target, spec.handlers) end
    sourceHandlers[eventType] = nil
    sourceConnected[eventType] = nil
  end

  --------------------------------------------------------------------------
  -- EDIT-TEXT id tracker (module-level, NOT a ZB event). Caches the id of the
  -- last server text window the engine opened, so Game.writeTextWindow (which is
  -- id-less in the ZB signature) can target it. This is a persistent listener for
  -- the module's lifetime (any script may call writeTextWindow at any time), so it
  -- is intentionally outside the ref-counted per-event bridge. Connected lazily on
  -- module build, when g_game is ready.
  local function onEngineEditText(id) -- engine: onEditText(id,itemId,maxLength,text,writer,date)
    lastEditTextId = id
  end
  connect(g_game, { onEditText = onEngineEditText })

  --------------------------------------------------------------------------
  -- CHANNELS-HISTORY tracker (module-level, NOT a ZB event). The engine caches
  -- no list of opened channels, so we mirror the console: cache them from the same
  -- engine signals it consumes -- onOpenChannel(id, name[, participants]) and
  -- onOpenPrivateChannel(name), both emitted on g_game. Entries are
  -- {id=<number|nil>, name=<string>} (private channels carry id=nil), deduped (by
  -- id for public, by name for private) and cleared on logout. Persistent for the
  -- module lifetime (any script may call getChannelsHistory), like onEditText.
  local function channelKnown(id, name)
    for i = 1, #channelsHistory do
      local e = channelsHistory[i]
      if id ~= nil then
        if e.id == id then return true end
      elseif e.id == nil and e.name == name then
        return true
      end
    end
    return false
  end
  local function onEngineOpenChannel(channelId, channelName)
    if channelKnown(channelId, channelName) then return end
    channelsHistory[#channelsHistory + 1] = { id = channelId, name = channelName }
  end
  local function onEngineOpenPrivateChannel(name)
    if channelKnown(nil, name) then return end
    channelsHistory[#channelsHistory + 1] = { id = nil, name = name }
  end
  local function onEngineChannelsGameEnd()
    for i = #channelsHistory, 1, -1 do channelsHistory[i] = nil end
  end
  connect(g_game, {
    onOpenChannel = onEngineOpenChannel,
    onOpenPrivateChannel = onEngineOpenPrivateChannel,
    onGameEnd = onEngineChannelsGameEnd,
  })

  return Game
end
