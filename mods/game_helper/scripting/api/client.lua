--[[============================================================================
  scripting/api/client.lua  ->  namespace `Client`
  ============================================================================

  Builder module (see scripting/scripting.lua CONTRACT). Returns
      function(api, ctx) ... return Client end
  and is injected into every sandboxed script as the global `Client`.

  Zerobot-dialect `Client.*` surface: OS/window/client-UI operations, client-side
  data dumps (items / monsters from the appearance + static-data tables), key
  polling, login/logout, and the Tools->PvP toggles.

  In Zerobot every `clientXxx` is a C++ binding into the bot's own Lua state. Here
  there is NO single native binding; instead this module runs OUTSIDE the sandbox
  (CONTRACT §3) and reaches the real engine globals directly:
      g_things   -> item appearance table (getThingTypes) + monster static data
                    (getMonsterList), ThingType is*/get* flag predicates.
      g_keyboard / g_window -> key polling + modifiers + window focus/flash.
      g_game     -> login/logout, online state, client version, world name.
      g_app      -> app version (for getVersion fallback).
      modules.game_textmessage.displayGameMessage -> centered on-screen message
                    (a MODULE-GLOBAL of the sandboxed game_textmessage module, so it
                    lives in that module's env, NOT in _G; reach it via modules.<name>).
  The PvP toggles read/write the helper's `helperConfig` table + saveSettings,
  exactly like scripting/api/engine.lua (we mirror its `flag` / setFlagPersisted /
  `unsupported` helpers so behaviour is consistent across the two modules).

  Status of each function:
    VIABLE  -> real, functional equivalent.
    PARTIAL -> best-effort with a documented adaptation.
    STUB    -> no engine backing; returns a benign default and logs ONCE via ctx.log.

  ENGINE FACTS verified for this module:
    * g_things.getThingTypes(ThingCategoryItem=0) -> ThingTypeList
      (std::vector<ThingTypePtr>, 1-indexed in Lua; index 1 is id 0 / the null
      type). Source of truth for getAllItems. src/client/thingtypemanager.cpp:680,
      src/client/thingtype.h:53 (ThingCategoryItem=0). Each entry is a ThingType
      with the full is*/get* predicate set (luafunctions_client.cpp:695-770).
    * g_things.getMonsterList() ->
      map<raceId, tuple{name, lookType, lookTypeEx, head, body, legs, feet, addons}>
      (src/client/creatures.cpp:175-201). Lua 1-indexes the tuple: t[1]=name,
      t[2]=lookType, ... t[8]=addons. There is NO isBoss field in the tuple, so
      Client monster shapes report isBoss=false (PARTIAL — boss-ness is not in the
      static monster list here).
    * Qt keycodes (Zerobot, via HotkeyManager) != engine Fw::Key enum. ZB letters
      use ASCII 65-90 (which happen to equal KeyA..KeyZ), but F-keys/arrows/etc.
      diverge wildly (ZB F1=16777264 vs engine KeyF1=128). We translate via an
      explicit Qt->Fw::Key table (QT_TO_FW below) before g_window.isKeyPressed.
============================================================================]]

return function(api, ctx)
  local Client = {}

  -- -------------------------------------------------------------------------
  -- small utilities (mirrors scripting/api/engine.lua for consistency)
  -- -------------------------------------------------------------------------
  local function bool(v) return v == true end

  -- one-time "not supported" logging so stubs don't spam the console per call.
  local warned = {}
  local function unsupported(name, retval)
    if not warned[name] then
      warned[name] = true
      if ctx and ctx.log then
        ctx.log(string.format("[Client.%s] nao suportado neste engine", name))
      end
    end
    return retval
  end

  -- read a boolean feature flag straight off helperConfig (same as engine.lua).
  local function flag(field)
    local cfg = _G.helperConfig
    return (type(cfg) == "table" and cfg[field]) == true
  end

  -- write a boolean feature flag + persist (same as engine.lua).
  local function setFlagPersisted(field, value)
    local cfg = _G.helperConfig
    if type(cfg) ~= "table" then return false end
    cfg[field] = bool(value)
    if type(_G.saveSettings) == "function" then
      pcall(_G.saveSettings)
    end
    return true
  end

  --==========================================================================
  -- Connection / window / on-screen
  --==========================================================================

  -- VIABLE: connected == in game with an active session.
  function Client.isConnected()
    return g_game.isOnline() == true
  end

  -- VIABLE: centered on-screen message. displayGameMessage is a MODULE-GLOBAL of the
  -- sandboxed game_textmessage module (lives in its env, never in _G), so reach it via
  -- modules.<name> (== package.loaded), like helper.lua does. Returns nothing (ZB
  -- clientShowMessage has no return).
  function Client.showMessage(message)
    local m = modules and modules.game_textmessage
    if m and type(m.displayGameMessage) == "function" then
      pcall(m.displayGameMessage, tostring(message or ""))
      return
    end
    return unsupported("showMessage")
  end

  -- VIABLE: focus the client window (raise + bring to front).
  function Client.focus()
    if g_window and type(g_window.bringToFront) == "function" then
      pcall(function() g_window.bringToFront() end)
      return
    end
    return unsupported("focus")
  end

  -- VIABLE: flash the taskbar/window entry (alarm-style attention grabber).
  function Client.flashWindow()
    if g_window and type(g_window.flash) == "function" then
      pcall(function() g_window.flash() end)
      return
    end
    return unsupported("flashWindow")
  end

  -- VIABLE (extra, harmless): is the client window currently focused?
  -- (Not in the strict ZB list but several scripts probe it; cheap to expose.)
  function Client.hasFocus()
    if g_window and type(g_window.hasFocus) == "function" then
      local ok, v = pcall(function() return g_window.hasFocus() end)
      if ok then return v == true end
    end
    return unsupported("hasFocus", false)
  end

  --==========================================================================
  -- Client version / world
  --==========================================================================

  -- VIABLE: Tibia protocol/client version as a string (g_game.getClientVersion
  -- is numeric; stringify to match ZB's string return), or nil if unavailable.
  function Client.getVersion()
    if type(g_game.getClientVersion) == "function" then
      local ok, v = pcall(function() return g_game.getClientVersion() end)
      if ok and v and v ~= 0 then return tostring(v) end
    end
    return nil
  end

  -- VIABLE: OT world name, or "" when not in game (ZB marks this experimental).
  function Client.getWorldName()
    if type(g_game.getWorldName) == "function" then
      local ok, v = pcall(function() return g_game.getWorldName() end)
      if ok and v then return tostring(v) end
    end
    return ""
  end

  --==========================================================================
  -- Input polling — keys / modifiers
  --==========================================================================
  -- ZB passes NUMERIC Qt keycodes (from HotkeyManager.parseKeyCombination). The
  -- engine's g_window.isKeyPressed wants Fw::Key codes. Build a Qt->Fw map from
  -- the engine's real Key* globals (available here, OUTSIDE the sandbox). Letters
  -- and digits already coincide (ASCII), but we still list everything explicitly
  -- so F-keys/arrows/numpad/punctuation resolve correctly.

  -- Resolve an engine Key* global by name, defaulting to nil if absent (keeps the
  -- table robust across const.lua revisions).
  local function K(name)
    local v = rawget(_G, name)
    return (type(v) == "number") and v or nil
  end

  -- Qt keycode (Zerobot HotkeyManager.keyMapping values) -> engine Fw::Key.
  -- Mirrors modules/corelib/const.lua Key* and Zerobot core/hotkeymanager.lua.
  local QT_TO_FW = {
    -- control / editing keys
    [16777216] = K("KeyEscape"),
    [16777217] = K("KeyTab"),
    [16777219] = K("KeyBackspace"),
    [16777220] = K("KeyEnter"),
    [16777221] = K("KeyEnter"),      -- Qt Return (keypad enter alias)
    [16777222] = K("KeyInsert"),
    [16777223] = K("KeyDelete"),
    [16777224] = K("KeyPause"),
    [16777232] = K("KeyHome"),
    [16777233] = K("KeyEnd"),
    [16777234] = K("KeyLeft"),
    [16777235] = K("KeyUp"),
    [16777236] = K("KeyRight"),
    [16777237] = K("KeyDown"),
    [16777238] = K("KeyPageUp"),     -- ZB "pgup"
    [16777239] = K("KeyPageDown"),   -- ZB "pgdown"
    [34]       = K("KeyPageDown"),   -- ZB also maps "pagedown" -> 34 (ASCII '"')
    [16777248] = K("KeyShift"),
    [16777249] = K("KeyCtrl"),
    [16777251] = K("KeyAlt"),
    [16777252] = K("KeyCapsLock"),
    [16777253] = K("KeyNumLock"),
    [16777254] = K("KeyScrollLock"),
    -- function keys
    [16777264] = K("KeyF1"),  [16777265] = K("KeyF2"),  [16777266] = K("KeyF3"),
    [16777267] = K("KeyF4"),  [16777268] = K("KeyF5"),  [16777269] = K("KeyF6"),
    [16777270] = K("KeyF7"),  [16777271] = K("KeyF8"),  [16777272] = K("KeyF9"),
    [16777273] = K("KeyF10"), [16777274] = K("KeyF11"), [16777275] = K("KeyF12"),
    -- space + punctuation (Qt ASCII codes; engine has named Key* for these)
    [32]  = K("KeySpace"),
    [33]  = K("KeyExclamation"),
    [35]  = K("KeyNumberSign"),
    [36]  = K("KeyDollar"),
    [37]  = K("KeyPercent"),
    [38]  = K("KeyAmpersand"),
    [39]  = K("KeyApostrophe"),
    [40]  = K("KeyLeftParen"),
    [41]  = K("KeyRightParen"),
    [42]  = K("KeyAsterisk"),
    [43]  = K("KeyPlus"),
    [44]  = K("KeyComma"),
    [45]  = K("KeyMinus"),
    [46]  = K("KeyPeriod"),
    [47]  = K("KeySlash"),
    [59]  = K("KeySemicolon"),
    [60]  = K("KeyLess"),
    [61]  = K("KeyEqual"),
    [62]  = K("KeyGreater"),
    [63]  = K("KeyQuestion"),
    [64]  = K("KeyAtSign"),
    [91]  = K("KeyLeftBracket"),
    [92]  = K("KeyBackSlash"),
    [93]  = K("KeyRightBracket"),
    [94]  = K("KeyCaret"),
    [95]  = K("KeyUnderscore"),
    [96]  = K("KeyGrave"),
    [123] = K("KeyLeftCurly"),
    [124] = K("KeyBar"),
    [125] = K("KeyRightCurly"),
    [126] = K("KeyTilde"),
  }
  -- digits 0-9: Qt 48-57 -> engine Key0..Key9 (ASCII-aligned in both).
  for d = 0, 9 do QT_TO_FW[48 + d] = K("Key" .. d) end
  -- letters a-z: Qt 65-90 (uppercase) -> engine KeyA..KeyZ.
  for c = 0, 25 do
    QT_TO_FW[65 + c] = K("Key" .. string.char(65 + c))
  end

  -- Translate a ZB key value to an engine Fw::Key code.
  --   * number that is a known Qt code -> mapped Fw::Key
  --   * number already in Fw::Key range (no Qt mapping) -> passed through
  --   * string -> resolved by the engine's getKeyCode (KeyCodeDescs names)
  local function toFwKey(key)
    if type(key) == "string" then
      if type(_G.getKeyCode) == "function" then
        local ok, code = pcall(_G.getKeyCode, key)
        if ok then return code end
      end
      return nil
    end
    if type(key) ~= "number" then return nil end
    local mapped = QT_TO_FW[key]
    if mapped ~= nil then return mapped end
    return key -- assume already an Fw::Key code
  end
  -- expose for sibling reuse / debugging without leaking a global.
  Client._toFwKey = toFwKey

  -- VIABLE: is a key currently held down? `flags` (ZB FlagModifiers) is accepted
  -- for signature parity; when given, the current modifier set must match too.
  -- Returns true/false (never nil — ZB returns a bool).
  function Client.isKeyPressed(key, flags)
    local fw = toFwKey(key)
    if fw == nil then return false end
    local down = false
    if g_window and type(g_window.isKeyPressed) == "function" then
      local ok, v = pcall(function() return g_window.isKeyPressed(fw) end)
      down = ok and v == true
    elseif g_keyboard and type(g_keyboard.isKeyPressed) == "function" then
      local ok, v = pcall(function() return g_keyboard.isKeyPressed(fw) end)
      down = ok and v == true
    end
    if not down then return false end
    -- optional modifier gate (ZB FlagModifiers -> engine combined modifier value)
    if type(flags) == "number" and flags ~= 0 then
      local want = api.Enums.translate.flagModifiersToEngine(flags)
      local cur = 0
      if g_keyboard and type(g_keyboard.getModifiers) == "function" then
        local ok, m = pcall(function() return g_keyboard.getModifiers() end)
        if ok and type(m) == "number" then cur = m end
      end
      local bitlib = bit or bit32
      if bitlib.band(cur, want) ~= want then return false end -- AND-mask, like ZB
    end
    return true
  end

  -- PARTIAL: ZB clientSendHotkey injects a synthetic key press. This engine has
  -- NO key/mouse INJECTION binding (engine-capabilities §8: "no g_window.sendKey
  -- /fakeClick"; bot input is performed by calling g_game.* directly). There is
  -- no way to synthesize an OS-level key event from Lua here, so this is a stub.
  -- (To trigger an in-game hotkey, drive the underlying action via Game.* /
  -- Spells.* instead.)
  function Client.sendHotkey(_, _)
    return unsupported("sendHotkey")
  end

  --==========================================================================
  -- Login / logout
  --==========================================================================

  -- VIABLE: send a graceful logout to the server. ZB returns a bool ("sent").
  -- Prefer safeLogout (server-acknowledged), falling back to forceLogout.
  function Client.logout()
    if not g_game.isOnline() then return false end
    if type(g_game.safeLogout) == "function" then
      local ok = pcall(function() g_game.safeLogout() end)
      if ok then return true end
    end
    if type(g_game.forceLogout) == "function" then
      local ok = pcall(function() g_game.forceLogout() end)
      return ok and true or false
    end
    return false
  end

  -- VIABLE alias: ZB's Client.XLog() disconnects via the native "X-Log" (the
  -- emergency logout). Map to forceLogout (immediate), not safeLogout.
  function Client.XLog()
    if type(g_game.forceLogout) == "function" then
      pcall(function() g_game.forceLogout() end)
      return
    end
    return unsupported("XLog")
  end

  -- PARTIAL: programmatic login. The engine CAN log into a world
  -- (g_game.loginWorld), but it needs the full session tuple the entergame
  -- module assembles after talking to the login web service: account, password,
  -- worldName, worldHost, worldPort, characterName, and an auth token. ZB's
  -- (email, password, characterIndex) does not carry the world host/port or the
  -- resolved character NAME, and this module has no access to the login-service
  -- client (g_http / EnterGame are outside the sandbox-safe surface). A correct
  -- by-credentials login belongs in the entergame flow, not here. Stub honestly
  -- rather than half-call loginWorld with missing args (which would desync).
  function Client.login(_, _, _)
    return unsupported("login")
  end

  --==========================================================================
  -- Client item appearances  -> Client.getAllItems()
  --==========================================================================
  -- Iterate the appearance table (ThingCategoryItem) and emit, per item, the ZB
  -- shape: { id = <clientId>, flags = <bitmask of Enums.ThingFlagAttr> } plus a
  -- few commonly-used type-specific extras. The flags bitmask is rebuilt from the
  -- ThingType is*/get* predicates using THIS engine's Enums.ThingFlagAttr values
  -- (so a ported ZB script comparing `band(item.flags, Enums.ThingFlagAttr.X)`
  -- gets the right answer).

  local ITEM_CATEGORY = (type(_G.ThingCategoryItem) == "number") and _G.ThingCategoryItem or 0

  -- Map: ThingFlagAttr field name -> ThingType predicate method name. Only the
  -- predicates this engine actually binds (luafunctions_client.cpp:718-767) are
  -- listed; anything without a real predicate is simply never set (it cannot be
  -- known) rather than guessed.
  local FLAG_PREDICATES = {
    { "Ground",          "isGround" },
    { "GroundBorder",    "isGroundBorder" },
    { "OnBottom",        "isOnBottom" },
    { "OnTop",           "isOnTop" },
    { "Container",       "isContainer" },
    { "Stackable",       "isStackable" },
    { "ForceUse",        "isForceUse" },
    { "MultiUse",        "isMultiUse" },
    { "Writable",        "isWritable" },
    { "Chargeable",      "isChargeable" },
    { "WritableOnce",    "isWritableOnce" },
    { "FluidContainer",  "isFluidContainer" },
    { "Splash",          "isSplash" },
    { "NotWalkable",     "isNotWalkable" },
    { "NotMoveable",     "isNotMoveable" },
    { "BlockProjectile", "blockProjectile" },
    { "NotPathable",     "isNotPathable" },
    { "Pickupable",      "isPickupable" },
    { "Hangable",        "isHangable" },
    { "HookSouth",       "isHookSouth" },
    { "HookEast",        "isHookEast" },
    { "Rotateable",      "isRotateable" },
    { "Light",           "hasLight" },
    { "DontHide",        "isDontHide" },
    { "Translucent",     "isTranslucent" },
    { "Displacement",    "hasDisplacement" },
    { "Elevation",       "hasElevation" },
    { "LyingCorpse",     "isLyingCorpse" },
    { "AnimateAlways",   "isAnimateAlways" },
    { "MinimapColor",    "hasMiniMapColor" },
    { "LensHelp",        "hasLensHelp" },
    { "FullGround",      "isFullGround" },
    { "Look",            "isIgnoreLook" }, -- ZB "Look" flag == has the Look attr;
                                            -- engine exposes isIgnoreLook (inverse
                                            -- sense) only, see note below.
    { "Cloth",           "isCloth" },
    { "Market",          "isMarketable" },
    { "Usable",          "isUsable" },
    { "Wrapable",        "isWrapable" },
    { "Unwrapable",      "isUnwrapable" },
    -- WearOut/Podium intentionally omitted: those attrs live on Item, not ThingType
    -- (no hasWearout/isPodium on ThingType), so they can't be read from this dump.
    { "TopEffect",       "isTopEffect" },
  }
  -- NOTE on "Look": the engine binds isIgnoreLook (the IgnoreLook attr), which is
  -- the OPPOSITE of ZB's "Look" (has-a-description) flag. To avoid emitting a
  -- wrong bit we DROP the Look mapping at runtime if the predicate name is the
  -- inverse. Done once below.
  for i = #FLAG_PREDICATES, 1, -1 do
    if FLAG_PREDICATES[i][1] == "Look" then
      table.remove(FLAG_PREDICATES, i) -- omit rather than report inverted truth
    end
  end

  -- Build the flags bitmask for one ThingType.
  local function thingTypeFlags(tt)
    local FA = api.Enums.ThingFlagAttr
    local bitlib = bit or bit32
    local mask = 0
    for _, pair in ipairs(FLAG_PREDICATES) do
      local fname, method = pair[1], pair[2]
      local flagVal = FA[fname]
      if flagVal and flagVal ~= 0 and type(tt[method]) == "function" then
        local ok, v = pcall(tt[method], tt)
        if ok and v == true then
          mask = bitlib.bor(mask, flagVal)
        end
      end
    end
    return mask
  end

  -- Emit the per-item record (id + flags + light extras). Kept small: ZB's full
  -- dump is large; the load-bearing fields are id + flags. We add a couple of
  -- cheap, frequently-used type attrs (marketData name/category, classification).
  local function itemRecord(tt)
    local id = tt:getId()
    local rec = { id = id, flags = thingTypeFlags(tt) }
    -- upgrade classification (tier gate) — ThingType:getClassification is the
    -- appearance upgrade class (NOT a weapon type); cheap and useful for scripts.
    if type(tt.getClassification) == "function" then
      local ok, v = pcall(tt.getClassification, tt)
      if ok and v and v ~= 0 then rec.classification = v end
    end
    -- market data (name/category) when the item is on the market.
    if type(tt.isMarketable) == "function" then
      local okm, marketable = pcall(tt.isMarketable, tt)
      if okm and marketable and type(tt.getMarketData) == "function" then
        local okd, md = pcall(tt.getMarketData, tt)
        if okd and type(md) == "table" then
          rec.name = md.name
          rec.marketCategory = md.category
        end
      end
    end
    return rec
  end

  -- VIABLE: dump every client item appearance. Iterates the ThingCategoryItem
  -- appearance vector via g_things.getThingTypes (the real iteration source).
  -- Skips the null/id-0 slot. Returns an array of { id, flags, ... }.
  function Client.getAllItems()
    if not (g_things and type(g_things.getThingTypes) == "function") then
      return unsupported("getAllItems", {})
    end
    local ok, list = pcall(function() return g_things.getThingTypes(ITEM_CATEGORY) end)
    if not ok or type(list) ~= "table" then
      return unsupported("getAllItems", {})
    end
    local out = {}
    for i = 1, #list do
      local tt = list[i]
      if tt and type(tt.getId) == "function" then
        local okid, id = pcall(tt.getId, tt)
        if okid and type(id) == "number" and id > 0 then
          out[#out + 1] = itemRecord(tt)
        end
      end
    end
    return out
  end

  --==========================================================================
  -- Monster static data  -> Client.getAllMonsters() / getMonsterByRaceId()
  --==========================================================================
  -- g_things.getMonsterList() -> { [raceId] = { name, lookType, lookTypeEx,
  -- head, body, legs, feet, addons } } (Lua-1-indexed tuple). Build the ZB shape:
  --   { raceId = <id>, name = <string>, outfit = {type,typeEx,head,body,legs,
  --     feet,addons,...}, isBoss = false }
  -- PARTIAL: the static list carries no boss flag, so isBoss is always false.

  -- Turn a (raceId, tuple) pair into the ZB monster record.
  local function monsterRecord(raceId, tuple)
    if type(tuple) ~= "table" then return nil end
    local outfit = {
      type      = tuple[2] or 0, -- lookType
      typeEx    = tuple[3] or 0, -- lookTypeEx (item-look monsters)
      head      = tuple[4] or 0,
      body      = tuple[5] or 0,
      legs      = tuple[6] or 0,
      feet      = tuple[7] or 0,
      addons    = tuple[8] or 0,
      mountId   = 0,
      mountHead = 0,
      mountLegs = 0,
      mountFeet = 0,
    }
    return {
      raceId = raceId,
      name   = tuple[1] or "",
      outfit = outfit,
      isBoss = false, -- PARTIAL: not present in the static monster list
    }
  end

  -- Fetch + cache nothing (matches ZB: re-reads static data each call). Returns
  -- the raw map, or nil on failure.
  local function rawMonsterList()
    if not (g_things and type(g_things.getMonsterList) == "function") then
      return nil
    end
    local ok, list = pcall(function() return g_things.getMonsterList() end)
    if not ok or type(list) ~= "table" then return nil end
    return list
  end

  -- VIABLE: all known monsters from the loaded static data. Array of records.
  function Client.getAllMonsters()
    local list = rawMonsterList()
    if not list then return unsupported("getAllMonsters", {}) end
    local out = {}
    for raceId, tuple in pairs(list) do
      local rec = monsterRecord(raceId, tuple)
      if rec then out[#out + 1] = rec end
    end
    return out
  end

  -- VIABLE: one monster by raceId, or nil if no such race in the static data
  -- (ZB nil semantics: entity does not exist).
  function Client.getMonsterByRaceId(raceId)
    local list = rawMonsterList()
    if not list then return unsupported("getMonsterByRaceId", nil) end
    local tuple = list[raceId]
    if type(tuple) ~= "table" then return nil end
    return monsterRecord(raceId, tuple)
  end

  --==========================================================================
  -- PvP tools  (Tools->PvP)
  --==========================================================================
  -- Mirrors scripting/api/engine.lua. Auto SSA / Auto Might Ring drive the helper's
  -- Tank Mode accessory auto-swap; Hold Target -> Hold Attack and Auto Reconnect ->
  -- the entergame engine (both real). Anti-Push / Rune Max have NO Amon backing.

  -- --- Tank Mode wiring (Auto SSA + Auto Might Ring) -----------------------
  -- The old helperConfig.autoSSA / mightRingEnabled flags are DEAD (no worker reads
  -- them). The real worker is checkTankMode() in helper.lua, gated by
  -- helperConfig.tankModeEnabled and, per accessory, tankModeAmuletEnabled /
  -- tankModeRingEnabled (~= false) re-equipping tankModeAmuletId (default 3081=SSA,
  -- 3082 its charged pair) / tankModeRingId (default 3048=Might Ring). We drive
  -- those fields + the master via modules.game_helper.onEnableTankMode (which ticks
  -- the checkbox + icon stats but does NOT save, so we saveSettings ourselves).
  local TANK_ACCESSORY = {
    amulet = { id = "tankModeAmuletId", en = "tankModeAmuletEnabled",
               sibling = "tankModeRingEnabled", default = 3081,
               valid = { [3081] = true, [3082] = true } },
    ring   = { id = "tankModeRingId", en = "tankModeRingEnabled",
               sibling = "tankModeAmuletEnabled", default = 3048,
               valid = { [3048] = true } },
  }
  -- Is this tank accessory's auto-swap effectively ON? Mirrors checkTankMode's
  -- gates: master on + this half not disabled + the effective id is the tank one.
  local function tankIsEnabled(kind)
    local cfg = _G.helperConfig
    local t = TANK_ACCESSORY[kind]
    if type(cfg) ~= "table" or not t then return false end
    if cfg.tankModeEnabled ~= true then return false end
    if cfg[t.en] == false then return false end
    local id = tonumber(cfg[t.id]) or t.default -- default mirrors "id or 3081/3048"
    return t.valid[id] == true
  end
  -- Enable forces the canonical id + turns the master on (leaving the sibling half
  -- off unless already set). Disable clears this half and only tears the master
  -- down if the sibling isn't wanted. true when applied, false if no helperConfig.
  local function tankEnable(kind, enable)
    local cfg = _G.helperConfig
    local t = TANK_ACCESSORY[kind]
    if type(cfg) ~= "table" or not t then return false end
    local gh = modules and modules.game_helper
    if bool(enable) then
      cfg[t.id] = t.default
      cfg[t.en] = true
      if cfg[t.sibling] == nil then cfg[t.sibling] = false end
      if gh and type(gh.onEnableTankMode) == "function" then
        pcall(gh.onEnableTankMode, true)
      else
        cfg.tankModeEnabled = true
      end
    else
      cfg[t.en] = false
      if cfg[t.sibling] ~= true then
        if gh and type(gh.onEnableTankMode) == "function" then
          pcall(gh.onEnableTankMode, false)
        else
          cfg.tankModeEnabled = false
        end
      end
    end
    if type(_G.saveSettings) == "function" then pcall(_G.saveSettings) end
    return true
  end

  -- VIABLE: Auto SSA == Tank Mode amulet auto-swap (default SSA 3081).
  function Client.isAutoSSAEnabled()      return tankIsEnabled("amulet") end
  function Client.autoSSAEnable(enable)    return tankEnable("amulet", enable) end

  -- VIABLE: Auto Might Ring == Tank Mode ring auto-swap (default 3048).
  function Client.isAutoMightRingEnabled() return tankIsEnabled("ring") end
  function Client.autoMightRingEnable(e)   return tankEnable("ring", e) end

  -- ---- Hold Target -> the helper's Hold Attack (VIABLE) ----
  -- Hold Attack IS the ZB hold-target: helperConfig.holdAttack + checkHoldAttack
  -- (helper.lua) re-attacks the locked target. Two nuances vs ZB: (a) mutually
  -- EXCLUSIVE with autoTarget (checkHoldAttack bails while autoTargetEnabled is on,
  -- so hold stays inert by design); (b) only ESC clears the lock (no per-call unlock).
  function Client.isHoldTargetEnabled() return flag("holdAttack") end
  function Client.holdTargetEnable(enable)
    local gh = modules and modules.game_helper
    if gh and type(gh.toggleHoldAttack) == "function" then
      gh.toggleHoldAttack(bool(enable))
      return
    end
    return setFlagPersisted("holdAttack", enable)
  end

  -- ---- Anti-Push / Rune Max: no Amon backing (STUB) ----
  function Client.isAntiPushEnabled()   return unsupported("isAntiPushEnabled", false) end
  function Client.antiPushEnable(_)      return unsupported("antiPushEnable") end

  function Client.isRuneMaxEnabled()    return unsupported("isRuneMaxEnabled", false) end
  function Client.runeMaxEnable(_)       return unsupported("runeMaxEnable") end

  -- ---- Auto Reconnect -> the entergame reconnect engine (VIABLE) ----
  -- Per-character CLIENT preference owned by client_entergame/characterlist.lua
  -- (the global g_settings 'autoReconnect' flag + the per-char 'autoReconnectSettings'
  -- node). The helper's own "Auto Reconnect" checkbox uses this same setter:
  -- toggleAutoReconnect(bool), which drives BOTH sources the engine reads.
  function Client.isReconnectEnabled()
    if g_game.isOnline() and type(_G.getAutoReconnect) == "function"
        and type(g_game.getCharacterName) == "function" then
      local ok, v = pcall(_G.getAutoReconnect, g_game.getCharacterName())
      if ok then return v == true end
    end
    if g_settings and type(g_settings.getBoolean) == "function" then
      return g_settings.getBoolean("autoReconnect", false) == true
    end
    return false
  end
  function Client.reconnectEnable(enable)
    local gh = modules and modules.game_helper
    if gh and type(gh.toggleAutoReconnect) == "function" then
      gh.toggleAutoReconnect(bool(enable))
      return
    end
    return unsupported("reconnectEnable")
  end

  --==========================================================================
  -- Identity (ZB Engine surface; mirrored here for scripts that look on Client)
  --==========================================================================

  -- STUB: no hashed-email user identity in this engine. Delegate to Engine when
  -- present (keeps a single source of truth), else stub like engine.lua does.
  function Client.getUserId(lowerCase)
    if api.Engine and type(api.Engine.getUserId) == "function" then
      return api.Engine.getUserId(lowerCase)
    end
    return unsupported("getUserId", "")
  end

  -- STUB: no license system. Delegate to Engine when present.
  function Client.getLicenseTime()
    if api.Engine and type(api.Engine.getLicenseTime) == "function" then
      return api.Engine.getLicenseTime()
    end
    return unsupported("getLicenseTime", nil)
  end

  return Client
end
