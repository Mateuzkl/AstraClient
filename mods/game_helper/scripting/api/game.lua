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

  -- History of opened channels for the session — server-pushed, not retained as
  -- a queryable list in this engine (Phase 2).
  function Game.getChannelsHistory()
    unsupported('Game.getChannelsHistory')
    return {}
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

  -- Use item `itemId` (from inventory) targeting a ground position.
  function Game.useItemOnGround(itemId, x, y, z)
    local p = pos(x, y, z)
    if not p then return nil end
    local tile = g_map.getTile(p)
    if not tile then return nil end -- no map data / tile does not exist
    if not canAct() or itemId == nil then return false end
    g_game.useInventoryItemWith(itemId, tile)
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
  -- needs the window id; ZB's writeTextWindow(text) does not carry one, so we
  -- cannot target a specific window reliably in Phase 1. Declared, honest no-op.
  function Game.writeTextWindow(text)
    unsupported('Game.writeTextWindow')
    return false
  end

  ---------------------------------------------------------------------------
  -- Forge (engine: g_game.sendForgeConverter(action))
  --   action 2 = dust -> slivers, 3 = slivers -> cores, 4 = increase dust limit
  --   (matches the forge UI buttons; the server validates them).
  ---------------------------------------------------------------------------
  -- Forge actions (would be g_game.sendForgeConverter(action): 2=dust->slivers,
  -- 3=slivers->cores, 4=increase dust limit) are Fase 2: sendForgeConverter is a
  -- corelib no-op (gameNoops, globals.lua:645), NOT natively bound, so calling it
  -- would silently fake success (return true without sending a packet). Report it
  -- honestly as unsupported until a real bridge exists.
  local function forgeConverter(name)
    unsupported(name)
    return false
  end
  function Game.forgeConvertDust()    return forgeConverter('Game.forgeConvertDust') end
  function Game.forgeConvertSlivers() return forgeConverter('Game.forgeConvertSlivers') end
  function Game.forgeIncreaseLimit()  return forgeConverter('Game.forgeIncreaseLimit') end

  ---------------------------------------------------------------------------
  -- Imbuement (engine bindings exist natively)
  ---------------------------------------------------------------------------

  -- Apply an imbuement to an open item's slot (slot is 0-based, as in ZB).
  function Game.applyImbuement(slot, imbuementId, isProtected)
    if not canAct() or slot == nil or imbuementId == nil then return false end
    g_game.applyImbuement(slot, imbuementId, isProtected and true or false)
    return true
  end

  -- Apply an imbuement onto an Imbue Scroll. The engine has selectImbuementScroll
  -- (selects the scroll as the imbuement target) but no single call that also
  -- carries the imbuementId for the scroll path in Phase 1. Honest no-op.
  function Game.applyImbuementOnScroll(imbuementId)
    unsupported('Game.applyImbuementOnScroll')
    return false
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
  -- Auto Loot (ZB's native Tools->Auto Loot) — no equivalent toggle in Phase 1.
  ---------------------------------------------------------------------------
  function Game.autoLoot()
    unsupported('Game.autoLoot')
    return false
  end

  ---------------------------------------------------------------------------
  -- Quest log (engine: requestQuestLog / requestQuestLine are REAL)
  ---------------------------------------------------------------------------

  -- Request the quest log; the QUEST_LOG event fires with the data. NOTE: that
  -- event source is not wired in Phase 1 (no clear Lua signal), but the request
  -- itself is a real packet, so we send it and return true.
  function Game.requestQuestLog()
    if not canAct() then return false end
    g_game.requestQuestLog()
    return true
  end

  -- Request the lines/missions of a quest by id (QUEST_LINES event fires).
  function Game.requestQuestLines(questId)
    if not canAct() or questId == nil then return false end
    g_game.requestQuestLine(questId)
    return true
  end

  ---------------------------------------------------------------------------
  -- Stash retrieve — engine stashWithdraw is a no-op stub (gameNoops). Phase 2.
  ---------------------------------------------------------------------------
  function Game.stashRetrieve(itemId, itemCount)
    unsupported('Game.stashRetrieve')
    return false
  end

  ---------------------------------------------------------------------------
  -- Game store (engine bindings exist natively)
  ---------------------------------------------------------------------------

  -- Buy a store offer. offerType is an Enums.GameStoreOfferType value, passed
  -- through to the engine as the product type. The engine call also wants a
  -- name string (empty here; the offer id identifies the product).
  function Game.storeBuyOffer(offerId, offerType)
    if not canAct() or offerId == nil then return false end
    g_game.buyStoreOffer(offerId, offerType or 0, '')
    return true
  end

  -- Open the game store window.
  function Game.storeOpen()
    if not canAct() then return false end
    g_game.openStore(0)
    return true
  end

  -- Request offers for a store category by name.
  function Game.storeRequestOffers(categoryName)
    if not canAct() or categoryName == nil then return false end
    g_game.requestStoreOffers(categoryName, 0)
    return true
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
  -- Daily reward — engine dailyReward* / openDailyReward are no-op stubs. Phase 2.
  ---------------------------------------------------------------------------
  function Game.collectDailyReward(isFromShrine, itemsToPick)
    unsupported('Game.collectDailyReward')
    return false
  end
  function Game.openDailyReward()
    unsupported('Game.openDailyReward')
    return false
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

  -- Map each wired event type to (a) the engine object to connect on and (b) the
  -- signal-name -> handler table. Lazy: built on first enable so g_game is ready.
  local function buildSourceSpec(eventType)
    local E = Game.Events
    if eventType == E.TALK then
      return g_game, { onTalk = onEngineTalk }
    elseif eventType == E.TEXT_MESSAGE then
      return g_game, { onTextMessage = onEngineTextMessage }
    elseif eventType == E.MODAL_WINDOW then
      return g_game, { onModalDialog = onEngineModalDialog }
    end
    -- ----------------------------------------------------------------------
    -- INACTIVE in Phase 1 (declared, registrable, dispatchable, but no engine
    -- source attached):
    --   MAGIC_EFFECT / DISTANCE_SHOOT_EFFECT — engine effect hooks exist
    --     (g_map.onMissle / animated text) but there is no clean, stable
    --     "effect spawned at pos" signal carrying (type,x,y,z) without heavy
    --     per-frame cost; left for Phase 2.
    --   HUD_CLICK / HUD_DRAG / CUSTOM_MODAL_WINDOW_BUTTON_CLICK — fired by
    --     other modules (hud.lua) via Game.executeEvents; never connect here.
    --   HOTKEY_SHORTCUT_PRESS, IMBUEMENT_DATA, IMBUEMENT_OPEN_WINDOW, QUEST_LOG,
    --     QUEST_LINES, PARTY_HUNT, LABEL, OPEN_STASH, STORE_CATEGORIES,
    --     STORE_OFFERS, OPEN_DAILY_REWARD, DAILY_REWARD_DAYS_DATA, ALARM,
    --     TASK_HUNTING_DATA — Phase 2 (no wired source).
    -- ----------------------------------------------------------------------
    return nil, nil
  end

  -- Enable the engine source for an event type (0->1 transition). No-op for the
  -- inactive types (they still dispatch via Game.executeEvents from elsewhere).
  enableSource = function(eventType)
    if sourceConnected[eventType] then return end
    local target, handlers = buildSourceSpec(eventType)
    if not target or not handlers then return end -- inactive in Phase 1
    sourceHandlers[eventType] = { target = target, handlers = handlers }
    connect(target, handlers)
    sourceConnected[eventType] = true
  end

  -- Disable the engine source for an event type (1->0 transition).
  disableSource = function(eventType)
    if not sourceConnected[eventType] then return end
    local spec = sourceHandlers[eventType]
    if spec then disconnect(spec.target, spec.handlers) end
    sourceHandlers[eventType] = nil
    sourceConnected[eventType] = nil
  end

  return Game
end
