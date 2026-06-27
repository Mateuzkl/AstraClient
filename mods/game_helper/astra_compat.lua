--[[============================================================================
  astra_compat.lua — Amon -> Astra engine-compatibility shim
  ============================================================================

  Loaded FIRST in helper.otmod's `scripts:` list so every later script (and the
  dofile chains they trigger) inherits the shimmed sandbox globals.

  Design rules:
    * IDEMPOTENT: every global is guarded with `X = X or ...`, so reloads and
      any future native bindings never clobber real Astra API.
    * NEVER redefine what Astra already provides (cycleEvent, tr, json,
      g_settings, g_tooltip, HTTP, Services, resolvepath, ProtocolGame.*,
      doThing, equipItemId, updateLootContainer, PlayerStates, ResourceTypes,
      PathFindResults, PathFindFlags, SpellAreas, Spells.* except loadWorldSpells,
      Directions/North.., Creature:isKnight/isDruid/...). The `or` guards make
      this safe even if a name only appears later.
    * DELIBERATELY OMIT the guarded g_map.* helpers (see big note below): the
      Amon scripts already ship pure-Lua fallbacks behind `if g_map.X then`
      guards, so defining a stub would FORCE the broken/empty native path. We
      leave them nil so the working Lua fallbacks run.

  Path resolution note: Astra's ResourceManager::resolvePath prepends
  {/mods,/data,/modules} to a leading-slash path that does not exist, so Amon's
  `/game_helper/...` dofiles and `/images/...` otui refs auto-resolve to
  `/mods/game_helper/...` and `/data/images/...`. (The 12 `/modules/game_helper/`
  literals were rewritten to `/mods/game_helper/` since those would resolve to a
  non-existent `/mods/modules/game_helper/...`.)
============================================================================]]

-- ===========================================================================
-- 1. macro(intervalMs, fn) -> { setOn, setOff, setInterval, isOn }
--    Amon's macro() takes (interval, fn); Astra's cycleEvent() takes
--    (fn, interval). Only real consumer: cavebots/core.lua:436
--      cavebotMacro = macro(20, mainLoop); cavebotMacro.setOff()  -- dot access
--    so .setOff must be immediately callable. We keep an `enabled` flag and the
--    cycle callback early-returns while disabled (cheaper than churning the
--    dispatcher event on/off, and avoids races with the 20ms tick).
-- ===========================================================================
if not macro then
    function macro(intervalMs, fn)
        local m = {
            interval = intervalMs or 20,
            enabled = false,
            event = nil,
            callback = fn,
        }

        local function tick()
            if m.enabled and m.callback then
                m.callback()
            end
        end

        function m.setOn()
            m.enabled = true
            if not m.event then
                m.event = cycleEvent(tick, m.interval)
            end
        end

        function m.setOff()
            m.enabled = false
            if m.event then
                m.event:cancel()
                m.event = nil
            end
        end

        function m.setInterval(ms)
            m.interval = ms
            if m.event then
                -- restart the cycle so the new interval takes effect
                m.event:cancel()
                m.event = cycleEvent(tick, m.interval)
            end
        end

        function m.isOn()
            return m.enabled
        end

        return m
    end
end

-- ===========================================================================
-- 2. g_map.findPathJPS — Astra has no JPS variant. g_map.findPath has the same
--    4-arg signature (start, goal, maxComplexity, flags) and returns the same
--    (directions, PathFindResult) tuple, verified against src/client/map.cpp.
-- ===========================================================================
if g_map then
    g_map.findPathJPS = g_map.findPathJPS or g_map.findPath
end

--[[
  --- DELIBERATELY NOT SHIMMED (do NOT add stubs here) -----------------------
  g_map.collectMonstersForCache          (creature_cache.lua, lure.lua)
  g_map.countReachableMonstersInRange    (lure.lua)
  g_map.getReachableMonstersInRange      (lure.lua)
  g_map.countCreaturesInSpellArea        (helper.lua AoE)
  g_map.findBestSpellTarget              (helper.lua AoE)
  g_map.computeViewportReachability      (screen_grid.lua)
  g_map.findViewportPath                 (screen_grid.lua)

  Each call site is wrapped in `if g_map.X then <native> else <Lua fallback> end`
  (the fallbacks are labelled "Fallback for clients that predate the native
  binding" and use g_map.getSpectators + g_map.isSightClear/findPath — all
  present in Astra). Leaving these nil makes the guard select the working Lua
  path. Defining a stub that returns {}/0 would instead force the empty native
  branch and silently break luring / AoE targeting / grid reachability.
  ---------------------------------------------------------------------------
]]

-- ===========================================================================
-- 3. g_game telemetry / misc stubs.
--    net_diagnostics.lua calls these UNGUARDED (getNet*/getPing*); stall_/
--    hunting_recorder call them guarded. Returning 0 keeps net_diagnostics from
--    erroring. They feed a Discord webhook that only fires if
--    Services.discordNetDiag is set -> inert on this server.
--    sendResourceBalance/sendForgeAction are already guarded at call sites;
--    updateInventoryItems is invoked by the engine via callGlobalField and is a
--    no-op consumer hook here. All no-ops so nothing breaks.
-- ===========================================================================
if g_game then
    g_game.getNetJitter           = g_game.getNetJitter           or function() return 0 end
    g_game.getNetPacketLoss       = g_game.getNetPacketLoss       or function() return 0 end
    g_game.getNetPacketsSent      = g_game.getNetPacketsSent      or function() return 0 end
    g_game.getNetPacketsReceived  = g_game.getNetPacketsReceived  or function() return 0 end
    g_game.getPingTimeouts        = g_game.getPingTimeouts        or function() return 0 end

    g_game.sendResourceBalance    = g_game.sendResourceBalance    or function() end
    g_game.sendForgeAction        = g_game.sendForgeAction        or function() end
    g_game.updateInventoryItems   = g_game.updateInventoryItems   or function() end
end

-- ===========================================================================
-- 3b. bit -> bit32 alias.
--     Amon runs on a LuaJIT-lineage VM where the global `bit` library exists;
--     Astra's Lua state instead loads Lua 5.2's `bit32` (luainterface.cpp:742
--     luaopen_bit32) and exposes NO `bit` global. The game_helper tree calls
--     `bit.band(states, FLAG)` in ~30 sites (helper.lua, auto_follow.lua,
--     hunting_recorder.lua, cavebots/utils.lua, cavebots/extensions/lure.lua);
--     each is a truthiness test (`> 0` / `~= 0` / `== 0`), so bit32's unsigned
--     result is equivalent. Aliasing the whole table (band/bor/bxor/lshift/
--     rshift/bnot/arshift/... all present in lbitlib.cpp) fixes them at once.
--     Guarded so a future native `bit` is never clobbered.
-- ===========================================================================
if not bit and bit32 then
    bit = bit32
    -- Also publish into the REAL global env, not just this module's sandbox.
    -- Files dofile'd at RUNTIME (after the module finished loading) — notably
    -- auto_follow.lua (helper.lua:initAutoFollow) and path_sharing.lua — execute
    -- with the THREAD fenv reset to _G (Module::load calls resetGlobalEnvironment
    -- after the script/onLoad phase), so a bare `bit` written only into the
    -- sandbox table is invisible to them. auto_follow.lua:55/1290 call
    -- `bit.band(states, ...)` and would hit `attempt to index nil ('bit')`.
    -- bit32 itself is a real _G global (lbitlib registers LUA_BIT32LIBNAME), so
    -- this is safe and stays guarded/idempotent.
    if _G then _G.bit = _G.bit or bit32 end
end

-- ===========================================================================
-- 3c. PlayerStates.RedSwords -> Swords alias.
--     Amon's PlayerStates had a RedSwords PVP-indicator flag; Astra's table
--     (modules/gamelib/player.lua) has only Swords=128 (the in-fight battle-
--     sign icon), the closest equivalent. auto_follow.lua:55 reads
--     PlayerStates.RedSwords; nil there makes bit32.band raise 'number
--     expected, got nil' (lbitlib luaL_checkunsigned), and the call-site guard
--     only checks `states`, not the flag — so isAutoFollowBlocked() throws on
--     every follow tick/activation and silently kills auto-follow. PlayerStates
--     is populated by gamelib (loaded before this /mods shim), so it is in
--     scope here. Guarded + idempotent; falls back to Swords, then 0 (defensive
--     so even an absent Swords keeps band valid instead of re-introducing nil;
--     Swords=128 is present today, so the effective value is 128).
-- ===========================================================================
if PlayerStates then
    PlayerStates.RedSwords = PlayerStates.RedSwords or PlayerStates.Swords or 0
    -- NewManaShield: Amon flag name; Astra exposes NewMagicShield=67108864.
    -- nil here is non-fatal (hasState guards nil) but the utamo / new-mana-shield
    -- state would never be detected; alias to the real Astra flag for accuracy.
    PlayerStates.NewManaShield = PlayerStates.NewManaShield or PlayerStates.NewMagicShield
end

-- ===========================================================================
-- 3d. Directions.Invalid -> None alias. Amon used Directions.Invalid as the
--     "no direction" sentinel; Astra's Directions (gamelib/const.lua) exposes
--     only None/Flip. Callers truthiness-check so nil is tolerated, but make the
--     sentinel a real value so cavebots/utils.lua getDirection() stays consistent.
--     Guarded + idempotent.
-- ===========================================================================
if Directions then
    Directions.Invalid = Directions.Invalid or Directions.None
end

-- ===========================================================================
-- 4. View / config / client singletons that Astra does not expose to Lua under
--    these names. screen_grid + a couple of helper paths probe them; provide
--    safe getters (32px sprite/tile is the OT default). getCameraPosition tries
--    the real game map widget when one is reachable, else falls back to the
--    local player position.
-- ===========================================================================
g_mapView = g_mapView or {
    getCameraPosition = function()
        local gi = modules and modules.game_interface
        local mapWidget = gi and gi.getMapPanel and gi.getMapPanel()
        if mapWidget and mapWidget.getCameraPosition then
            local ok, pos = pcall(function() return mapWidget:getCameraPosition() end)
            if ok and pos then return pos end
        end
        local p = g_game and g_game.getLocalPlayer and g_game.getLocalPlayer()
        if p and p.getPosition then return p:getPosition() end
        return nil
    end,
    getTileSize = function() return 32 end,
}

g_gameConfig = g_gameConfig or {
    getSpriteSize = function() return 32 end,
}

g_client = g_client or {}
g_client.setInputLockWidget = g_client.setInputLockWidget
    or (g_ui and g_ui.setInputLockWidget)
    or function() end

-- ===========================================================================
-- 5. g_platform file dialogs — zerobot import/export. Astra has no binding;
--    no-op stubs degrade import/export gracefully (no crash).
-- ===========================================================================
g_platform = g_platform or {}
g_platform.showOpenFileDialog      = g_platform.showOpenFileDialog      or function() end
g_platform.showOpenFileDialogAsync = g_platform.showOpenFileDialogAsync or function() end

-- ===========================================================================
-- 5b. modules.game_npctrade.getBuyItems — Amon's npctrade module exposed this
--     accessor (returns tradeItems[BUY]); Astra's npctrade.lua keeps the SAME
--     sandbox globals (tradeItems table, BUY=1, identical {ptr,name,weight,
--     price} entry shape) but never defined the getter. Cavebot supply buying
--     reads it (cavebots/extensions/supplies.lua, cavebots/actions.lua) behind
--     an `if modules.game_npctrade.getBuyItems then` guard, so without it supply
--     restock silently no-ops. game_npctrade lives under /modules and loads
--     before this /mods shim (discoverModules lists /modules first), so the
--     sandbox env table exists here; we attach the getter and resolve the BUY
--     list lazily at call time so it tracks the live trade window.
-- ===========================================================================
if modules and modules.game_npctrade and not modules.game_npctrade.getBuyItems then
    local npctrade = modules.game_npctrade
    npctrade.getBuyItems = function()
        local buyType = npctrade.BUY or 1
        return (npctrade.tradeItems and npctrade.tradeItems[buyType]) or {}
    end
end

-- ===========================================================================
-- 6. Spells.loadWorldSpells — Amon-only init-time call. Astra's gamelib/spells
--    is a superset of everything else the helper uses (getSpellByClientId,
--    getImageClip, getRuneSpellByItem, ...), so just neutralise this one entry.
-- ===========================================================================
if Spells then
    Spells.loadWorldSpells = Spells.loadWorldSpells or function() end
end

-- ===========================================================================
-- 7. Otc namespace. Astra defines Directions / North.. and PathFindResults /
--    PathFindFlags globally, but no `Otc` table. Populate it (values copied
--    from Amon gamelib/const.lua) so Otc.Direction.* and the PathFind flag
--    constants the cavebot/move code reads resolve.
-- ===========================================================================
Otc = Otc or {}

Otc.Direction = Otc.Direction or {
    North     = 0,
    East      = 1,
    South     = 2,
    West      = 3,
    NorthEast = 4,
    SouthEast = 5,
    SouthWest = 6,
    NorthWest = 7,
}

-- PathFindFlags — values verified against Astra src/client/const.h
-- (enum PathFindFlags) so they line up with what g_map.findPath actually
-- masks. The Amon scripts pass these as raw int literals (0, 16, 20) anyway —
-- lure.lua:371 uses 16 = IgnoreCreatures, lure.lua:536 uses 20 =
-- IgnoreCreatures(16)|AllowNonPathable(4) — so these named constants are
-- defensive (no Amon site reads Otc.PathFind* symbolically today). Astra:
--   PathFindAllowNotSeenTiles = 1   (Lua const.lua exposes bit 1 as AllowNullTiles)
--   PathFindAllowCreatures    = 2
--   PathFindAllowNonPathable  = 4
--   PathFindAllowNonWalkable  = 8
--   PathFindIgnoreCreatures   = 16
Otc.PathFindAllowNotSeenTiles   = Otc.PathFindAllowNotSeenTiles   or 1
Otc.PathFindAllowNullTiles      = Otc.PathFindAllowNullTiles      or 1  -- Lua-side alias of bit 1
Otc.PathFindAllowCreatures      = Otc.PathFindAllowCreatures      or 2
Otc.PathFindAllowNonPathable    = Otc.PathFindAllowNonPathable    or 4
Otc.PathFindAllowNonWalkable    = Otc.PathFindAllowNonWalkable    or 8
Otc.PathFindIgnoreCreatures     = Otc.PathFindIgnoreCreatures     or 16

-- ===========================================================================
-- PORTED LUA LIBS — dofile small Amon support files copied into compat/.
-- Absolute `/game_helper/compat/...` paths auto-resolve to
-- `/mods/game_helper/compat/...` via the resolvePath /mods fallback, matching
-- how the rest of Amon references module files.
-- ===========================================================================

-- 8. TablePool / ObjectPool (corelib/objectpool.lua) — pure Lua, no engine deps.
if not TablePool then
    dofile("/game_helper/compat/objectpool.lua")
end

-- 9. Keybind (corelib/keybind.lua) — procedural Keybind global (lowercase 'b').
--    Astra's own KeyBind/KeyBinds (capital 'B') is a DIFFERENT, incompatible
--    OOP design; the names don't collide. Amon's corelib.otmod normally runs
--    Keybind.init() at load; we replicate that here (it only touches
--    g_settings/g_resources/g_configs and connects g_game callbacks — safe to
--    call at module load, no game session required).
if not Keybind or not CHAT_MODE then
    dofile("/game_helper/compat/keybind.lua")
end
if Keybind and Keybind.init and not Keybind._initialized then
    local ok, err = pcall(Keybind.init)
    if ok then
        Keybind._initialized = true
    else
        g_logger.error("[astra_compat] Keybind.init failed: " .. tostring(err))
    end
end

-- 10. VocationsClient (data table extract; Astra already has the Creature
--     vocation predicate methods).
if not VocationsClient then
    dofile("/game_helper/compat/vocations.lua")
end

g_logger.info("[astra_compat] Amon->Astra compatibility shim loaded")
