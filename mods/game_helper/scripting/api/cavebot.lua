--[[============================================================================
  scripting/api/cavebot.lua — Zerobot-compatible `CaveBot` namespace.
  ============================================================================

  Builder module (see scripting/scripting.lua CONTRACT). Returns
      function(api, ctx) ... return CaveBot end
  and is injected into every sandboxed script as the global `CaveBot`.

  ---------------------------------------------------------------------------
  ⚠️  CRITICAL: the Amon engine ALREADY defines a global `CaveBot` (the cavebot
  execution engine, mods/game_helper/cavebots/*.lua), a global `cavebotWalker`
  (the compat shim), and a global `hunting_recorderModule` (the orchestrator /
  data owner). This wrapper has the SAME public name (`CaveBot`) as the engine
  but is a DIFFERENT, LOCAL table that we RETURN — it must NEVER be assigned to
  `_G`, and it must NEVER redefine the engine. We reach the three engine layers
  through `_G.CaveBot` / `_G.cavebotWalker` / `_G.hunting_recorderModule`,
  resolved LAZILY at call time (the cavebot engine may load after this builder
  runs), and only ever READ/CALL them — never `CaveBot.X = ...` on the global.

  The Amon cavebot is THREE layers (mapping: analysis/amon-cavebot-surface.md):
    1. engine `_G.CaveBot.*`         (cavebots/core.lua) — runtime: on/off,
       pause/resume, gotoLabel/gotoIndex, getCurrentIndex/getActionCount,
       add/remove/clear/getActions, walkTo, Config.get/set.
    2. compat `_G.cavebotWalker.*`   (core.lua) — start/stop/updateConfig.
    3. orchestrator `_G.hunting_recorderModule.*` (hunting_recorder.lua) — owns
       `cavebotData` (waypoints + config + supplies + specialAreas + name), the
       Cavebots Manager (the "tabs"), save/load per file, special-area CRUD.

  ZB↔Amon impedance (see surface §5): the ZB surface is FLAT with a single
  native binding per function and a STABLE waypoint id; Amon has no stable id
  (uses a 1-based index into the action list), a different waypoint-type enum,
  no sell list, no parametric end-lure, and a boolean `pause()`/`resume()` (not
  the timed `pause(ms)` of ZB). Each ZB function below is one of:
    * VIÁVEL  — direct/trivial engine equivalent.
    * PARCIAL — emulated with documented semantics (id==index, type translation,
                Config-backed lure settings, supplies-backed refill, timed pause).
    * FALTA   — no Amon counterpart: honest stub (false/nil/default) that logs
                ONCE via a per-function flag, so scripts importing the symbol do
                not break but the gap is visible.

  GAP — Game.Events.LABEL is NOT emitted (documented, not faked). In ZB the
  cavebot fires LABEL and PAUSES when it *reaches a label waypoint during normal
  traversal*, and the script resumes with `CaveBot.pause(0)`. In Amon the `label`
  action handler is a no-op `return true` (actions.lua:520) and the main loop
  advances into it by INDEX increment — it never routes through
  `engine.gotoLabel` (only the explicit `gotolabel` action and `CaveBot.GoTo`
  do). So monkey-patching `gotoLabel` to emit LABEL would fire ONLY on explicit
  jumps, not on normal arrivals — the wrong semantics. Emitting it correctly
  needs arrival-edge detection inside the `label` action handler (per-tick path),
  which is out of scope here. `CaveBot.pause(0)`/`pause(ms)` IS fully implemented
  and ready for when LABEL is wired later.

  RULES (CONTRACT):
    * No globals. Only locals + the returned `CaveBot` table.
    * Cross-namespace refs are LAZY: `api.Enums.X` / `api.Game.executeEvents`
      INSIDE a function, never `local Enums = api.Enums` at module top.
    * Runs OUTSIDE the sandbox: direct access to engine globals is allowed.
    * Return-value semantics preserved (true/false/nil distinct where it matters).
============================================================================]]

return function(api, ctx)
  local CaveBot = {}   -- the ZB wrapper, RETURNED — never assigned to _G.

  --==========================================================================
  -- Engine handles (resolved LAZILY: the cavebot engine may load after this
  -- builder runs). Never mutate these globals — only read/call them.
  --==========================================================================

  -- The Amon cavebot EXECUTION engine (layer 1). _G read so a stale upvalue is
  -- impossible if the engine reloads.
  local function engine()
    return _G.CaveBot
  end

  -- The compat walker shim (layer 2) — used to push runtime config (special
  -- areas) into the live walk loop.
  local function walker()
    return _G.cavebotWalker
  end

  -- The orchestrator / data owner (layer 3) — owns `cavebotData`, the tabs,
  -- supplies, special-area CRUD, per-file save/load.
  local function hr()
    return _G.hunting_recorderModule
  end

  -- The live cavebotData table (waypoints/config/supplies/specialAreas/name),
  -- or nil when the orchestrator is not initialised.
  local function cavebotData()
    local m = hr()
    if not m or not m.getCurrentCavebotData then return nil end
    return m.getCurrentCavebotData()
  end

  -- Lazy Config getter/setter that never throws (engine Config.get errors on an
  -- unknown id; we swallow so a missing key behaves like ZB "not set").
  local function cfgGet(id)
    local e = engine()
    if not e or not e.Config or not e.Config.get then return nil end
    local ok, v = pcall(e.Config.get, id)
    if ok then return v end
    return nil
  end
  local function cfgSet(id, value)
    local e = engine()
    if not e or not e.Config or not e.Config.set then return false end
    local ok = pcall(e.Config.set, id, value)
    return ok and true or false
  end

  --==========================================================================
  -- "FALTA" stub helper — logs once per function, then stays quiet.
  --==========================================================================
  local stubLogged = {}
  local function stub(fnName, msg)
    if not stubLogged[fnName] then
      stubLogged[fnName] = true
      ctx.log("[CaveBot." .. fnName .. "] " .. (msg or "indisponivel no engine Amon (sem equivalente) - no-op"))
    end
  end

  --==========================================================================
  -- Waypoint-type translation (ZB Enums.WaypointType <-> Amon action name).
  --
  -- Amon stores each waypoint as { action=string, value=string }. The ZB enum
  -- has 18 numeric types; the Amon action set is string-based and richer in
  -- some places, poorer in others. Map bidirectionally with safe fallbacks
  -- (surface §2.1 / §5):
  --   * ZB types with no Amon peer are approximated:
  --       LADDER -> "use", SCRIPT -> "function", MACHETE -> "usewith",
  --       TELEPORT -> "use", DYNAMIC_*_LURE -> "start_lure"/"stop_lure".
  --   * Amon-only string actions (deposit/bank/travel/door/levitate/...) have
  --     no ZB number; getWaypointTypeById() reports them as STAND (0), the ZB
  --     fallback, while getWaypointDataById keeps the real action in `.data`.
  --==========================================================================

  -- Built lazily (needs api.Enums). Cached after first build.
  local _zbToAction, _actionToZb
  local function buildTypeMaps()
    if _zbToAction then return end
    local W = api.Enums.WaypointType
    -- ZB type number -> Amon action name.
    _zbToAction = {
      [W.WAYPOINT_TYPE_STAND]             = "stand",
      [W.WAYPOINT_TYPE_NODE]              = "node",
      [W.WAYPOINT_TYPE_START_LURE]        = "start_lure",
      [W.WAYPOINT_TYPE_END_LURE]          = "stop_lure",
      [W.WAYPOINT_TYPE_ROPE]              = "rope",
      [W.WAYPOINT_TYPE_LADDER]            = "use",        -- no ladder action; use
      [W.WAYPOINT_TYPE_HOLE]              = "hole",
      [W.WAYPOINT_TYPE_USE]               = "use",
      [W.WAYPOINT_TYPE_TELEPORT]          = "use",        -- no teleport action; use
      [W.WAYPOINT_TYPE_LABEL]             = "label",
      [W.WAYPOINT_TYPE_GOTO]              = "goto",
      [W.WAYPOINT_TYPE_SCRIPT]            = "function",   -- inline Lua chunk
      [W.WAYPOINT_TYPE_DYNAMIC_START_LURE] = "start_lure",
      [W.WAYPOINT_TYPE_DYNAMIC_END_LURE]   = "stop_lure",
      [W.WAYPOINT_TYPE_DOOR]             = "door",
      [W.WAYPOINT_TYPE_HUR_UP]           = "levitate",
      [W.WAYPOINT_TYPE_HUR_DOWN]         = "levitate",
      [W.WAYPOINT_TYPE_MACHETE]          = "usewith",
    }
    -- Amon action name -> ZB type number (first/canonical peer only).
    _actionToZb = {
      stand      = W.WAYPOINT_TYPE_STAND,
      node       = W.WAYPOINT_TYPE_NODE,
      start_lure = W.WAYPOINT_TYPE_START_LURE,
      stop_lure  = W.WAYPOINT_TYPE_END_LURE,
      rope       = W.WAYPOINT_TYPE_ROPE,
      hole       = W.WAYPOINT_TYPE_HOLE,
      use        = W.WAYPOINT_TYPE_USE,
      usewith    = W.WAYPOINT_TYPE_MACHETE,
      label      = W.WAYPOINT_TYPE_LABEL,
      ["goto"]   = W.WAYPOINT_TYPE_GOTO,
      ["function"] = W.WAYPOINT_TYPE_SCRIPT,
      door       = W.WAYPOINT_TYPE_DOOR,
      levitate   = W.WAYPOINT_TYPE_HUR_UP,
      -- Amon-only actions (no ZB peer): collapse to STAND for type queries.
      lever      = W.WAYPOINT_TYPE_STAND,
      say        = W.WAYPOINT_TYPE_STAND,
      delay      = W.WAYPOINT_TYPE_STAND,
      stop_to_kill = W.WAYPOINT_TYPE_STAND,
      wait_lure  = W.WAYPOINT_TYPE_STAND,
      wait_delay = W.WAYPOINT_TYPE_STAND,
      stop_cavebot = W.WAYPOINT_TYPE_STAND,
      special    = W.WAYPOINT_TYPE_STAND,
      deposit    = W.WAYPOINT_TYPE_STAND,
      bank       = W.WAYPOINT_TYPE_STAND,
      travel     = W.WAYPOINT_TYPE_STAND,
    }
  end

  -- ZB type number -> Amon action name (fallback "stand").
  local function actionFromZbType(zbType)
    buildTypeMaps()
    return _zbToAction[zbType] or "stand"
  end

  -- Amon action name -> ZB type number (fallback STAND=0).
  local function zbTypeFromAction(action)
    buildTypeMaps()
    if not action then return api.Enums.WaypointType.WAYPOINT_TYPE_STAND end
    return _actionToZb[action:lower()] or api.Enums.WaypointType.WAYPOINT_TYPE_STAND
  end

  -- Format the Amon `value` string for an action from (x,y,z,extraData). Most
  -- actions are positional ("x,y,z"); label/goto/script carry text; hur up/down
  -- carry a direction in extraData; usewith/machete is "itemId,x,y,z".
  local function valueFromZb(action, x, y, z, extraData, zbType)
    if action == "label" or action == "goto" or action == "function" then
      -- text-carrying actions: prefer extraData, else stringified position.
      if extraData ~= nil and extraData ~= "" then return tostring(extraData) end
      if x then return string.format("%d,%d,%d", x, y, z) end
      return ""
    elseif action == "usewith" then
      -- "itemId,x,y,z" — extraData is the itemId.
      return string.format("%s,%d,%d,%d", tostring(extraData or ""), x or 0, y or 0, z or 0)
    elseif action == "levitate" then
      -- Amon requires EXACTLY "x,y,z|mode|dir" (cavebots/actions.lua errors otherwise).
      -- mode ("up"/"down") comes from the ZB type (HUR_UP vs HUR_DOWN); dir (0-3 =
      -- N/E/S/W) from extraData (default 0).
      local mode = (zbType == api.Enums.WaypointType.WAYPOINT_TYPE_HUR_DOWN) and "down" or "up"
      local dir = tonumber(extraData) or 0
      return string.format("%d,%d,%d|%s|%d", x or 0, y or 0, z or 0, mode, dir)
    else
      -- positional actions.
      if x then return string.format("%d,%d,%d", x, y, z) end
      return tostring(extraData or "")
    end
  end

  -- Parse an Amon `value` string into { x, y, z } when it looks like a position,
  -- else nil. Accepts trailing "|..." or ",precision" suffixes.
  local function parsePosition(value)
    if type(value) ~= "string" then return nil end
    local x, y, z = value:match("^(%-?%d+)%s*,%s*(%-?%d+)%s*,%s*(%-?%d+)")
    if not x then return nil end
    return { x = tonumber(x), y = tonumber(y), z = tonumber(z) }
  end

  -- Translate one Amon action {action,value} into the ZB waypoint shape
  -- { x, y, z, type, data }. Position fields are nil for non-positional actions.
  local function actionToZbWaypoint(act)
    if not act then return nil end
    local pos = parsePosition(act.value)
    local zbType = zbTypeFromAction(act.action)
    -- levitate collapses HUR_UP/HUR_DOWN to one action; recover up vs down from the
    -- "|mode|" segment of the value so the round-trip keeps the direction.
    if act.action and act.action:lower() == "levitate" then
      local mode = tostring(act.value or ""):match("|(%a+)|")
      zbType = (mode == "down") and api.Enums.WaypointType.WAYPOINT_TYPE_HUR_DOWN
                                or api.Enums.WaypointType.WAYPOINT_TYPE_HUR_UP
    end
    return {
      x = pos and pos.x or nil,
      y = pos and pos.y or nil,
      z = pos and pos.z or nil,
      type = zbType,
      data = act.value,   -- raw Amon value preserved for round-tripping.
    }
  end

  --==========================================================================
  -- Navigation / control
  --==========================================================================

  -- VIÁVEL — jump to a label waypoint. ZB applies next tick and kills the
  -- current waypoint-script; Amon applies immediately and has no waypoint-script
  -- to kill. Returns whatever the engine returns (true if the label was found).
  function CaveBot.GoTo(labelName)
    local e = engine()
    if not e or not e.gotoLabel then return false end
    return e.gotoLabel(labelName) and true or false
  end

  -- PARCIAL — "select" a waypoint == move the execution cursor. ZB takes a
  -- stable wpId; Amon uses a 1-based index, so id == index here.
  function CaveBot.selectWaypoint(wpId)
    local e = engine()
    if not e or not e.gotoIndex then return false end
    return e.gotoIndex(tonumber(wpId) or 0) and true or false
  end

  -- PARCIAL — selected waypoint id. Amon returns a 1-based index; ZB returns -1
  -- when nothing is selected. We report the current index, or -1 when the engine
  -- is absent / the action list is empty.
  function CaveBot.getSelectedWaypointId()
    local e = engine()
    if not e or not e.getCurrentIndex or not e.getActionCount then return -1 end
    if (e.getActionCount() or 0) < 1 then return -1 end
    local idx = e.getCurrentIndex()
    if not idx or idx < 1 then return -1 end
    return idx
  end

  -- PARCIAL — timed pause. ZB `pause(ms)` (0 = resume, used to resume after a
  -- LABEL event); Amon is a boolean pause()/resume(). Emulate:
  --   ms == 0  -> resume() immediately.
  --   ms  > 0  -> pause() now, schedule resume() after `ms`.
  --   ms == nil-> pause() indefinitely (closest to ZB pause with no timer).
  -- The scheduled resume is wrapped via ctx.wrap so it inherits the owning
  -- script's error accounting and no-ops if the script unloaded.
  function CaveBot.pause(milliseconds)
    local e = engine()
    if not e then return end
    local ms = tonumber(milliseconds)
    if ms == 0 then
      if e.resume then e.resume() end
      return
    end
    if e.pause then e.pause() end
    if ms and ms > 0 then
      local resume = ctx.wrap(function()
        local e2 = engine()
        if e2 and e2.resume then e2.resume() end
      end)
      scheduleEvent(resume, ms)
    end
  end

  --==========================================================================
  -- Waypoint CRUD (runtime action list — surface §2.1/§3)
  --
  -- These operate on the engine's live action list (CaveBot.getActions()) AND
  -- best-effort mirror the change onto the persisted cavebotData.waypoints so a
  -- later CaveBot.saveFile(name) captures it (persisting still REQUIRES an
  -- explicit saveFile call — the mirror only keeps the in-memory model current).
  -- "wpId" is treated as a 1-based index (Amon has no stable id).
  --==========================================================================

  --------------------------------------------------------------------------
  -- Persistence mirror for the CRUD wrappers (surface §3 / plan Fase 2, Opção B).
  --
  -- The runtime CRUD edits ONLY the engine's live action list; saveFile()
  -- persists cavebotData.waypoints (the recorder's model), a DIFFERENT table.
  -- Each wrapper below also mirrors its structural change into
  -- cavebotData.waypoints in the recorder's shape. The mirror is BEST-EFFORT and
  -- ADDITIVE: it is applied only when the orchestrator is up AND the persisted
  -- list is aligned 1:1 with the engine action list; otherwise it no-ops and the
  -- runtime CRUD is left exactly as before (never broken). This keeps the two
  -- models from drifting so a `clearWaypoints(); addWaypoint(...); saveFile(n)`
  -- flow round-trips through loadFile.
  --------------------------------------------------------------------------

  -- ZB waypoint type -> persisted cavebotData `type` string. Mirrors the
  -- vocabulary CaveBot.loadFromWaypoints understands (core.lua) and the recorder
  -- writes (hunting_recorder typeSet). Diverges from _zbToAction for two types:
  --   SCRIPT  -> "script"  (inline Lua kept in `label`; runtime action is "function").
  --   MACHETE -> "use"     (no persisted "usewith"; the itemId is lost on reload).
  -- Also lossy: persisted "goto" reloads as the "gotolabel" action (a label jump,
  -- core.lua typeToAction), NOT the runtime "goto" walk-to-position action, so a
  -- POSITIONAL GOTO added via CRUD loses its position on save+reload. Prefer
  -- NODE/STAND for positional waypoints (and the GoTo()/label pair for jumps).
  local _zbToPersistedType
  local function buildPersistedTypeMap()
    if _zbToPersistedType then return end
    local W = api.Enums.WaypointType
    _zbToPersistedType = {
      [W.WAYPOINT_TYPE_STAND]              = "stand",
      [W.WAYPOINT_TYPE_NODE]               = "node",
      [W.WAYPOINT_TYPE_START_LURE]         = "start_lure",
      [W.WAYPOINT_TYPE_END_LURE]           = "stop_lure",
      [W.WAYPOINT_TYPE_ROPE]               = "rope",
      [W.WAYPOINT_TYPE_LADDER]             = "use",
      [W.WAYPOINT_TYPE_HOLE]               = "hole",
      [W.WAYPOINT_TYPE_USE]                = "use",
      [W.WAYPOINT_TYPE_TELEPORT]           = "use",
      [W.WAYPOINT_TYPE_LABEL]              = "label",
      [W.WAYPOINT_TYPE_GOTO]               = "goto",
      [W.WAYPOINT_TYPE_SCRIPT]             = "script",
      [W.WAYPOINT_TYPE_DYNAMIC_START_LURE] = "start_lure",
      [W.WAYPOINT_TYPE_DYNAMIC_END_LURE]   = "stop_lure",
      [W.WAYPOINT_TYPE_DOOR]               = "door",
      [W.WAYPOINT_TYPE_HUR_UP]             = "levitate",
      [W.WAYPOINT_TYPE_HUR_DOWN]           = "levitate",
      [W.WAYPOINT_TYPE_MACHETE]            = "use",
    }
  end

  -- Build a persisted waypoint (recorder shape) from ZB args. `index` is the
  -- 1-based slot. Positional types carry `position`; label/goto/script carry the
  -- text in `label`; goto adds condition/stamina; levitate adds mode/dir. Mirrors
  -- hunting_recorder.createWaypointAtPosition* and CaveBot.loadFromWaypoints.
  local function zbToCavebotWaypoint(index, waypointType, x, y, z, extraData)
    buildPersistedTypeMap()
    local W = api.Enums.WaypointType
    -- Fallback "stand" matches actionFromZbType's unknown-type fallback, so the
    -- runtime action and its persisted mirror agree for an unrecognised ZB type.
    local ptype = _zbToPersistedType[waypointType] or "stand"
    local wp = { index = index, type = ptype, teleport = false }
    if x ~= nil and y ~= nil and z ~= nil then
      wp.position = { x = tonumber(x) or 0, y = tonumber(y) or 0, z = tonumber(z) or 0 }
    end
    if ptype == "label" or ptype == "script" then
      wp.label = tostring(extraData or "")
    elseif ptype == "goto" then
      wp.label = tostring(extraData or "")
      wp.gotoCondition = "none"
      wp.gotoStamina = 0
    elseif ptype == "levitate" then
      wp.levitateMode = (waypointType == W.WAYPOINT_TYPE_HUR_DOWN) and "down" or "up"
      local dir = tonumber(extraData) or 0
      if dir < 0 or dir > 3 then dir = 0 end
      wp.levitateDir = dir
    end
    return wp
  end

  -- Return (data, waypoints) ONLY when it is safe to mirror a CRUD op onto the
  -- persisted list: the orchestrator is up AND cavebotData.waypoints is aligned
  -- 1:1 with the engine action list (its length == expectedCount, the engine's
  -- pre-op action count). Returns nil to skip the mirror (runtime op stands).
  local function persistTarget(expectedCount)
    if expectedCount == nil then return nil end
    local data = cavebotData()
    if not data then return nil end
    local list = data.waypoints
    if list == nil then list = {}; data.waypoints = list end
    if type(list) ~= "table" then return nil end
    if #list ~= expectedCount then return nil end  -- drift: skip persist, keep runtime
    return data, list
  end

  -- Commit a mutated cavebotData back to the orchestrator (mirrors the recorder).
  local function persistCommit(data)
    local m = hr()
    if m and m.setCurrentCavebotData then m.setCurrentCavebotData(data) end
  end

  -- Re-number the persisted waypoints 1..N (mirrors the hunting_recorder reindex).
  local function reindexWaypoints(list)
    for i = 1, #list do
      if list[i] then list[i].index = i end
    end
  end

  -- PARCIAL — append a waypoint. Translates ZB type -> Amon action and formats
  -- the value string. addAction validates the action name and returns the new
  -- entry (truthy) or errors on an unknown action; we pcall so a bad type is a
  -- soft failure rather than a script-killing error.
  function CaveBot.addWaypoint(waypointType, x, y, z, extraData)
    local e = engine()
    if not e or not e.addAction then return false end
    local action = actionFromZbType(waypointType)
    local value = valueFromZb(action, x, y, z, extraData, waypointType)
    local preCount = e.getActionCount and (e.getActionCount() or 0) or nil
    local ok, res = pcall(e.addAction, action, value)
    if not (ok and res) then return false end
    -- Mirror onto the persisted list (append) so saveFile captures it.
    local data, list = persistTarget(preCount)
    if data and list then
      local newIndex = #list + 1
      list[newIndex] = zbToCavebotWaypoint(newIndex, waypointType, x, y, z, extraData)
      persistCommit(data)
    end
    return true
  end

  -- PARCIAL — insert a waypoint before a given index. No engine insertAction, so
  -- mutate the live action list directly (it is a live reference) and re-point
  -- the cursor if needed via setActions.
  function CaveBot.insertWaypoint(wpId, waypointType, x, y, z, extraData)
    local e = engine()
    if not e or not e.getActions or not e.setActions then return false end
    local list = e.getActions()
    if type(list) ~= "table" then return false end
    local preCount = #list
    local idx = tonumber(wpId) or (#list + 1)
    if idx < 1 then idx = 1 end
    if idx > #list + 1 then idx = #list + 1 end
    local action = actionFromZbType(waypointType)
    table.insert(list, idx, { action = action, value = valueFromZb(action, x, y, z, extraData, waypointType) })
    e.setActions(list)
    -- Mirror onto the persisted list (insert at the same slot + reindex).
    local data, plist = persistTarget(preCount)
    if data and plist then
      table.insert(plist, idx, zbToCavebotWaypoint(idx, waypointType, x, y, z, extraData))
      reindexWaypoints(plist)
      persistCommit(data)
    end
    return true
  end

  -- PARCIAL — replace a waypoint by index (in-place edit of the live list).
  function CaveBot.replaceWaypoint(wpId, waypointType, x, y, z, extraData)
    local e = engine()
    if not e or not e.getActions then return false end
    local list = e.getActions()
    if type(list) ~= "table" then return false end
    local idx = tonumber(wpId) or 0
    if idx < 1 or idx > #list then return false end
    local preCount = #list
    local action = actionFromZbType(waypointType)
    list[idx] = { action = action, value = valueFromZb(action, x, y, z, extraData, waypointType) }
    -- Mirror onto the persisted list (in-place replace; count unchanged).
    local data, plist = persistTarget(preCount)
    if data and plist and plist[idx] then
      plist[idx] = zbToCavebotWaypoint(idx, waypointType, x, y, z, extraData)
      persistCommit(data)
    end
    return true
  end

  -- PARCIAL — delete a waypoint by index.
  function CaveBot.deleteWaypoint(wpId)
    local e = engine()
    if not e or not e.removeAction then return false end
    local idx = tonumber(wpId) or 0
    local preCount = e.getActionCount and (e.getActionCount() or 0) or nil
    if not e.removeAction(idx) then return false end
    -- Mirror onto the persisted list (remove at the same slot + reindex).
    local data, plist = persistTarget(preCount)
    if data and plist and plist[idx] then
      table.remove(plist, idx)
      reindexWaypoints(plist)
      persistCommit(data)
    end
    return true
  end

  -- VIÁVEL — remove all waypoints (runtime action list).
  function CaveBot.clearWaypoints()
    local e = engine()
    if not e or not e.clearActions then return false end
    e.clearActions()
    -- Mirror: clear the persisted list too (clearing to empty is always aligned).
    local data = cavebotData()
    if data then
      data.waypoints = {}
      persistCommit(data)
    end
    return true
  end

  -- PARCIAL — waypoint type by index. Returns the ZB type number, or -1 if the
  -- index is out of range (ZB getWaypointTypeById returns -1 on miss).
  function CaveBot.getWaypointTypeById(id)
    local e = engine()
    if not e or not e.getActions then return -1 end
    local list = e.getActions()
    local idx = tonumber(id) or 0
    local act = type(list) == "table" and list[idx] or nil
    if not act then return -1 end
    return zbTypeFromAction(act.action)
  end

  -- PARCIAL — waypoint data by index, in ZB shape { x, y, z, type, data }, or
  -- nil if the index is out of range.
  function CaveBot.getWaypointDataById(id)
    local e = engine()
    if not e or not e.getActions then return nil end
    local list = e.getActions()
    local idx = tonumber(id) or 0
    local act = type(list) == "table" and list[idx] or nil
    if not act then return nil end
    return actionToZbWaypoint(act)
  end

  -- PARCIAL — all waypoints as an array of ZB-shaped { x, y, z, type, data }.
  function CaveBot.getWaypoints()
    local e = engine()
    if not e or not e.getActions then return {} end
    local list = e.getActions()
    local out = {}
    if type(list) == "table" then
      for i = 1, #list do
        out[i] = actionToZbWaypoint(list[i])
      end
    end
    return out
  end

  -- VIÁVEL — waypoint count.
  function CaveBot.getWaypointsCount()
    local e = engine()
    if not e or not e.getActionCount then return 0 end
    return e.getActionCount() or 0
  end

  --==========================================================================
  -- Debug / misc queries
  --==========================================================================

  -- PARCIAL — there is no global "cavebot debug" flag in Amon; the nearest is
  -- the lure debug Config flag.
  function CaveBot.isDebugEnabled()
    return cfgGet("lureDebug") and true or false
  end

  -- PARCIAL — "core teleport ids". Amon has no configurable teleport-id list, and the
  -- cavebot no longer uses an id table: floor-change is now item-truth
  -- (getTeleportDestination OR .dat attr 252). Nothing fixed to expose -> {}.
  function CaveBot.getCoreTeleportIds()
    return {}
  end

  --==========================================================================
  -- Lure settings (Config-backed — surface §1.3/§4)
  --
  -- Amon does not separate "safety / normal / end" lure the way ZB does; it has
  -- a flat set of Config keys. Map the ZB getters/setters onto the closest keys
  -- and document the approximation. Unmapped ZB fields are accepted (setters)
  -- and reported as defaults (getters).
  --==========================================================================

  -- VIÁVEL — creature names to ignore for luring == Config "ignoredCreatures".
  function CaveBot.setLureIgnoreList(list)
    return cfgSet("ignoredCreatures", type(list) == "table" and list or {})
  end

  -- PARCIAL — safety-lure ~ avoid-trap config. nearCreatureDistance->trapDistance,
  -- nearCreatureCount->creaturesToAvoid, avoidStuckTrapCount->avoidTrap(>0).
  function CaveBot.setSafetyLureSettings(nearCreatureDistance, nearCreatureCount, avoidStuckTrapCount)
    if nearCreatureDistance ~= nil then cfgSet("trapDistance", tonumber(nearCreatureDistance) or 1) end
    if nearCreatureCount ~= nil then cfgSet("creaturesToAvoid", tonumber(nearCreatureCount) or 7) end
    if avoidStuckTrapCount ~= nil then cfgSet("avoidTrap", (tonumber(avoidStuckTrapCount) or 0) > 0) end
    return true
  end

  -- PARCIAL — read the safety-lure approximation back from Config.
  function CaveBot.getSafetyLureSettings()
    return {
      nearCreatureDistance = cfgGet("trapDistance") or 1,
      nearCreatureCount = cfgGet("creaturesToAvoid") or 7,
      avoidStuckTrapCount = (cfgGet("avoidTrap") and 1 or 0),
    }
  end

  -- PARCIAL — lure settings. creaturesToRun->creaturesToStop, dynamicLure->lureMode.
  -- skipUnreachableCreatures has no 1:1 Amon key (lure uses a waypoint-corridor
  -- filter); accepted but not stored.
  function CaveBot.setLureSettings(creaturesToRun, dynamicLure, skipUnreachableCreatures)
    if creaturesToRun ~= nil then cfgSet("creaturesToStop", tonumber(creaturesToRun) or 99) end
    if dynamicLure ~= nil then cfgSet("lureMode", dynamicLure and true or false) end
    -- skipUnreachableCreatures: no Amon equivalent (documented gap).
    return true
  end

  -- PARCIAL — read lure settings back from Config.
  function CaveBot.getLureSettings()
    return {
      creaturesToRun = cfgGet("creaturesToStop") or 99,
      dynamicLure = cfgGet("lureMode") and true or false,
      skipUnreachableCreatures = false,  -- no Amon source.
    }
  end

  -- FALTA — Amon has no parametric "end-lure" (stop_lure is a binary waypoint).
  function CaveBot.setEndLureSettings(...)
    stub("setEndLureSettings", "Amon nao tem end-lure parametrico (stop_lure e binario) - no-op")
    return false
  end

  -- FALTA — return safe defaults for the 9 ZB end-lure fields.
  function CaveBot.getEndLureSettings()
    stub("getEndLureSettings", "Amon nao tem end-lure parametrico - retornando defaults")
    return {
      creaturesToStop = 0, creaturesToLeave = 0, tryWalkToCenter = false,
      creaturesToLeaveByHp = 0, creaturesToLeaveByHpValue = 0, creaturesToLeaveByHpCount = 0,
      dontLeaveIfHp = 0, dontLeaveIfHpValue = 0, dontLeaveIfHpCount = 0,
    }
  end

  --==========================================================================
  -- Sell list — FALTA (Amon cavebot does not sell loot; "Loot Seller" is a
  -- separate helper feature, not per-cavebot).
  --==========================================================================

  function CaveBot.getSellList()
    stub("getSellList", "Amon cavebot nao tem sell list (use o Loot Seller do helper) - retornando vazio")
    return {}
  end

  function CaveBot.setSellList(list)
    stub("setSellList", "Amon cavebot nao tem sell list (use o Loot Seller do helper) - no-op")
    return false
  end

  --==========================================================================
  -- Refill list (supplies-backed — surface §4/§5).
  --
  -- ZB refill is a single settings-window text blob; Amon stores 10 supply
  -- slots as cavebotData.supplies[i] = itemId (number) plus
  -- cavebotData.supplySettings[i] = { minSupply, buySupply }. Serialize to / from
  -- a stable line format "itemId,minSupply,buySupply" (one slot per line) so the
  -- ZB string round-trips deterministically.
  --==========================================================================

  -- PARCIAL — serialize the live supplies to a multi-line "id,min,buy" string.
  function CaveBot.getRefillList()
    local data = cavebotData()
    if not data then return "" end
    local supplies = data.supplies or {}
    local settings = data.supplySettings or {}
    local lines = {}
    for i = 1, 10 do
      local id = tonumber(supplies[i]) or 0
      if id > 0 then
        local s = settings[i] or {}
        lines[#lines + 1] = string.format("%d,%d,%d",
          id, tonumber(s.minSupply) or 0, tonumber(s.buySupply) or 1)
      end
    end
    return table.concat(lines, "\n")
  end

  -- PARCIAL — parse "id,min,buy" lines into the 10 supply slots and write them
  -- back onto cavebotData (the source supplies.lua reads). Slots beyond what the
  -- string provides are cleared (id 0).
  function CaveBot.setRefillList(list)
    local data = cavebotData()
    if not data then return false end
    if type(list) ~= "string" then return false end
    local supplies, settings = {}, {}
    local i = 0
    for line in (list .. "\n"):gmatch("([^\n]*)\n") do
      line = line:match("^%s*(.-)%s*$")
      if line ~= "" and i < 10 then
        local id, mn, by = line:match("^(%d+)%s*,%s*(%d+)%s*,%s*(%d+)")
        if not id then id = line:match("^(%d+)") end
        if id then
          i = i + 1
          supplies[i] = tonumber(id) or 0
          settings[i] = {
            minSupply = tonumber(mn) or 0,
            buySupply = tonumber(by) or 1,
          }
        end
      end
    end
    for j = i + 1, 10 do
      supplies[j] = 0
      settings[j] = { minSupply = 0, buySupply = 1 }
    end
    data.supplies = supplies
    data.supplySettings = settings
    local m = hr()
    if m and m.setCurrentCavebotData then m.setCurrentCavebotData(data) end
    return true
  end

  --==========================================================================
  -- Recorder / node / walk settings
  --==========================================================================

  -- PARCIAL — Amon's recorder is interactive and always records `goto`; the ZB
  -- "type" (0=Stand/1=Node) has no parameter. nodeDistance IS settable.
  function CaveBot.setAutoRecorderSettings(nodeDistance, _type)
    if nodeDistance ~= nil then cfgSet("nodeDistance", tonumber(nodeDistance) or 2) end
    -- `type` (Stand/Node) has no Amon equivalent (always records goto).
    return true
  end

  -- VIÁVEL — node distance.
  function CaveBot.setNodeSettings(nodeDistance)
    return cfgSet("nodeDistance", tonumber(nodeDistance) or 2)
  end

  -- PARCIAL — debug HUD settings. Amon has a waypoint HUD + lureDebug, but not
  -- these 3 flags 1:1; map debugHUD onto lureDebug and accept the rest.
  function CaveBot.setDebugHUDSettings(debugHUD, _showPath, _showSkippedLureCreatures)
    if debugHUD ~= nil then cfgSet("lureDebug", debugHUD and true or false) end
    return true
  end

  -- VIÁVEL — walk mode. ZB WalkMode.MAP_CLICK(0) -> Amon "click",
  -- ARROW_KEYS(1) -> "walk". Also mirror the boolean `mapClick` Config key.
  function CaveBot.setWalkMode(mode)
    local W = api.Enums.WalkMode
    local isClick = (mode == W.MAP_CLICK)
    cfgSet("walkMode", isClick and "click" or "walk")
    cfgSet("mapClick", isClick)
    return true
  end

  -- VIÁVEL — walk delay (arrow-keys mode).
  function CaveBot.setWalkDelay(delayMs)
    return cfgSet("walkDelay", tonumber(delayMs) or 20)
  end

  -- VIÁVEL — enable/disable the (interactive) auto recorder.
  function CaveBot.enableAutoRecorder(enabled)
    local e = engine()
    if not e or not e.Recorder then return false end
    if enabled then
      if e.Recorder.enable then e.Recorder.enable() end
    else
      if e.Recorder.disable then e.Recorder.disable() end
    end
    return true
  end

  -- VIÁVEL — "start from nearest waypoint" lives on cavebotData.config.
  function CaveBot.setStartFromNearestWaypoint(value)
    local data = cavebotData()
    if not data then return false end
    if not data.config then data.config = {} end
    data.config.startFromNearest = value and true or false
    local m = hr()
    if m and m.setCurrentCavebotData then m.setCurrentCavebotData(data) end
    return true
  end

  --==========================================================================
  -- Special areas (cavebotData-backed — surface §4/§5 gotcha 7).
  --
  -- Amon special areas are SINGLE-TILE { id, position={x,y,z}, type=90 } with no
  -- width/height/area-type/wp-range. The ZB extra params (type/width/height/
  -- fromWp/toWp) are accepted but DROPPED. We keep cavebotData.specialAreas and
  -- the live walker config in sync (the engine reads it via Config.specialAreas
  -- pushed by cavebotWalker.updateConfig).
  --==========================================================================

  -- Push the special-area list into the live walk loop + refresh the UI list,
  -- both guarded (UI widgets may not exist).
  local function syncSpecialAreas(data)
    local w = walker()
    if w and w.updateConfig then
      pcall(w.updateConfig, { specialAreas = data.specialAreas })
    end
    local m = hr()
    if m then
      if m.reloadSpecialAreasList then pcall(m.reloadSpecialAreasList) end
      if m.updateDebugPos then pcall(m.updateDebugPos) end
    end
  end

  -- Next free integer id for a new special area.
  local function nextSpecialAreaId(areas)
    local maxId = 0
    for _, a in ipairs(areas) do
      if a.id and a.id > maxId then maxId = a.id end
    end
    return maxId + 1
  end

  -- PARCIAL — add a single-tile special area. type/width/height/fromWp/toWp are
  -- ignored (Amon special areas are 1 tile). Returns the new id, or false.
  function CaveBot.addSpecialArea(x, y, z, _type, _width, _height, _fromWp, _toWp)
    local data = cavebotData()
    if not data then return false end
    if not data.specialAreas then data.specialAreas = {} end
    local pos = { x = tonumber(x) or 0, y = tonumber(y) or 0, z = tonumber(z) or 0 }
    -- reject duplicate tile (mirrors createSpecialAreaAtPosition).
    for _, a in ipairs(data.specialAreas) do
      if a.position and a.position.x == pos.x and a.position.y == pos.y and a.position.z == pos.z then
        return false
      end
    end
    local id = nextSpecialAreaId(data.specialAreas)
    table.insert(data.specialAreas, { id = id, position = pos, type = 90 })
    local m = hr()
    if m and m.setCurrentCavebotData then m.setCurrentCavebotData(data) end
    syncSpecialAreas(data)
    return id
  end

  -- PARCIAL — delete a special area by id.
  function CaveBot.deleteSpecialArea(id)
    local data = cavebotData()
    if not data or not data.specialAreas then return false end
    id = tonumber(id)
    for i = #data.specialAreas, 1, -1 do
      if data.specialAreas[i].id == id then
        table.remove(data.specialAreas, i)
        local m = hr()
        if m and m.setCurrentCavebotData then m.setCurrentCavebotData(data) end
        syncSpecialAreas(data)
        return true
      end
    end
    return false
  end

  -- PARCIAL — clear all special areas.
  function CaveBot.clearSpecialAreas()
    local data = cavebotData()
    if not data then return false end
    data.specialAreas = {}
    local m = hr()
    if m and m.setCurrentCavebotData then m.setCurrentCavebotData(data) end
    syncSpecialAreas(data)
    return true
  end

  --==========================================================================
  -- FALTA — features with no Amon cavebot counterpart.
  --==========================================================================

  -- No waypoint-script (SCRIPT) execution model in Amon, so nothing to stop.
  function CaveBot.stopCurrentScript()
    stub("stopCurrentScript", "Amon nao tem waypoint-script (SCRIPT) em execucao - no-op")
    return false
  end

  -- No player-walkthrough toggle on the Amon cavebot.
  function CaveBot.disablePlayerWalkthrough(_disabled)
    stub("disablePlayerWalkthrough", "sem equivalente no cavebot Amon - no-op")
    return false
  end

  -- Floor-change no longer uses an id list (now item-truth); nothing to set.
  function CaveBot.setCoreTeleportIds(_ids)
    stub("setCoreTeleportIds", "cavebot nao usa lista de ids (floor-change = verdade do item) - no-op")
    return false
  end

  --==========================================================================
  -- Persistence (per-file — surface §3/§4).
  --==========================================================================

  -- PARCIAL — save the CURRENT cavebot profile (rich cavebotData, not just the
  -- action list) to /helper/cavebots/<name>.json via the orchestrator's
  -- saveCavebotToFile(name, data, force=true). The saver is a file-local in
  -- hunting_recorder.lua published on the module table (hr().saveCavebotToFile);
  -- force=true is mandatory (it early-returns false otherwise). ZB saves under
  -- Documents/ZeroBot; path semantics differ. Returns true on a successful write.
  function CaveBot.saveFile(fileName)
    if not fileName then return false end
    local data = cavebotData()
    if not data then return false end
    local m = hr()
    local saver = m and m.saveCavebotToFile
    if type(saver) ~= "function" then return false end
    local ok, res = pcall(saver, tostring(fileName), data, true)
    if not (ok and res) then return false end
    -- Cosmetic: refresh the Cavebots Manager list so a newly written file shows up.
    if m.refreshMainCavebotsList then pcall(m.refreshMainCavebotsList) end
    return true
  end

  -- PARCIAL — load a cavebot profile by name. NOTE: this swaps the ENTIRE active
  -- profile (waypoints + config + supplies + special areas) AND stops/disables
  -- the running cavebot (loadCavebotByName -> stopWalk + unchecks Enable), unlike
  -- ZB's "load waypoints into the current cavebot". Returns true if the file
  -- exists (loadCavebotByName itself returns nil on both paths).
  function CaveBot.loadFile(fileName)
    if not fileName then return false end
    local m = hr()
    if not m or not m.loadCavebotByName then return false end
    -- Probe existence so we can return a meaningful bool (the loader is void).
    if g_resources and g_resources.fileExists then
      if not g_resources.fileExists("/helper/cavebots/" .. tostring(fileName) .. ".json") then
        return false
      end
    end
    local ok = pcall(m.loadCavebotByName, tostring(fileName))
    return ok and true or false
  end

  return CaveBot
end
