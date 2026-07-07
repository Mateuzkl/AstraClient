--[[
  Scripting tab for KoliseuClient (game_helper, Amon engine).
  ============================================================================
  A place for players to drop their own Lua scripts written in the *Zerobot
  dialect* (Game.*, Player.*, Creature(cid), Container(idx), Map.*, Inventory.*,
  Npc.*, Timer(...), HUD(...), Enums.*, JSON.*). Scripts are plain .lua FILES in
  the bot scripts folder (the "Open Scripts Folder" button opens it). Each file's
  body runs ONCE when the script is ENABLED ("loaded"); recurring work is done via
  Timer(...) and reactions via Game.registerEvent(...). A body (or any callback /
  cavebot waypoint script) may also call wait(ms) to pause a sequence or pace a
  `while true` loop -- it runs inside a coroutine, so wait() never freezes the client
  (see the wait() driver below). Everything runs inside a CLOSED sandbox.

  This file is the ENGINE: load/unload, compile (loadstring+setfenv), the sandbox
  (makeEnv / SANDBOX_GLOBALS), per-script error accounting with auto-disable,
  folder-watch, per-character persistence, the debug console, AND the loader that
  builds the ZB_API namespaces from scripting/api/*.lua.

  The namespaces themselves (Game/Player/Creature/...) live in scripting/api/*.lua;
  this engine only loads them and injects them into every script's environment.

  ----------------------------------------------------------------------------
  CONTRACT for scripting/api/*.lua modules (the OTHER agents follow this)
  ----------------------------------------------------------------------------
  Each api/<name>.lua RETURNS A BUILDER:

      return function(api, ctx)
        local NS = {}
        -- ... define methods, using api.X / api.Enums.Y LAZILY (inside fns) ...
        return NS
      end

  * `api`  -- the shared table; AFTER load it holds every namespace:
            api.Game, api.Player, api.Creature, api.Map, api.Container,
            api.Inventory, api.Npc, api.Enums, api.Timer, api.HUD, api.JSON,
            api.CaveBot, api.Engine.
            Cross-namespace refs MUST be lazy (`api.Creature(cid)` inside a fn),
            never `local C = api.Creature` at module top (load order not guaranteed).

  * `ctx`  -- runtime utilities provided by THIS engine:
      ctx.log(...)             -> write to the current script's debug console
                                  (same destination as the sandbox `print`). Lines
                                  are prefixed with the running script's name.
      ctx.logColor(color,...)  -> like ctx.log but with an explicit hex color
                                  (e.g. '#ff6666' for errors). [engine extension]
      ctx.onCleanup(fn)        -> register `fn` to run when the CURRENT script
                                  unloads / errors-out / relogs. Use it to
                                  disconnect events and stop timers/HUDs. Returns a
                                  handle { cancel = function() end } that removes the
                                  cleanup early (call it from your own :stop()).
      ctx.runningScript()      -> the script record currently loading/executing, or
                                  nil. Treat as opaque; useful as a key/identity.
                                  Fields of interest: `.name`, `.enabled`. [extension]
      ctx.wrap(fn)             -> THE key primitive for deferred callbacks. Captures
                                  the CURRENT script NOW and returns a wrapper that,
                                  when called LATER (timer tick / event dispatch / HUD
                                  click -- after the load body returned and
                                  runningScript is nil), runs `fn` in that captured
                                  script's context with pcall + error accounting
                                  (auto-disable keeps working) and no-ops once the
                                  script is disabled. api/timer.lua, api/hud.lua and
                                  the event dispatcher MUST wrap any callback they
                                  store and invoke later. Returns fn's return value.
                                  [extension]
      ctx.guard(fn, ...)       -> run fn(...) IMMEDIATELY in the CURRENT script's
                                  run-context + pcall + error accounting. Use when you
                                  already hold the context (inside a load body or an
                                  already-wrapped callback). Returns ok, ret. For
                                  callbacks invoked later, use ctx.wrap instead. [extension]
      ctx.isOnline()           -> g_game.isOnline() and a LocalPlayer exists. [extension]
      ctx.resolvePath(rel)     -> a module-root-relative virtual path for `rel`
                                  (e.g. "/game_helper/scripting/<rel>"), the form
                                  g_resources.fileExists / dofile accept here.

  * Modules run OUTSIDE the sandbox: full access to g_game, g_map, g_clock,
    g_things, connect/disconnect, scheduleEvent/cycleEvent/addEvent, etc. Use them
    freely BUT never create new globals (no `Game = ...`; the engine already has
    C++ globals `Creature`/`Container` and polluting `_G` breaks the whole helper).

  * Return-value semantics (Zerobot): true = sent to server; false = not sent /
    validation failed; nil = entity/tile/slot does not exist. Keep them distinct.

  ----------------------------------------------------------------------------
  makeEnv(extra)
  ----------------------------------------------------------------------------
  Builds a fresh per-script environment. It is a CLOSED table (its __index is the
  frozen SANDBOX_GLOBALS, which does NOT chain to the real _G). It injects:
    * safe stdlib: math, string (no string.dump), table, select/pairs/ipairs/next/
      type/tostring/tonumber/unpack/_VERSION, pcall/xpcall/error/assert,
      rawget/rawset/rawequal, setmetatable/getmetatable, and a restricted
      os = { time, date, clock, difftime }.
    * the 13 ZB_API namespaces: Game, Player, Creature, Map, Container, Inventory,
      Npc, Enums, Timer, HUD, JSON, CaveBot, Engine.
    * `print` -> ctx.log; the global `wait(ms)` (cooperative pause -- yields the
      script coroutine, never blocks); `destroyTimer(name)` (stop a Timer by name);
      and anything in `extra`.
  It BLOCKS: io, full os (execute/remove/rename/exit/getenv/tmpname), loadstring/
  load/dofile/loadfile/require, package/module/modules, debug, coroutine,
  networking, _G, g_resources, g_ui, g_window, g_settings, g_logger, g_platform.

  Scripts folder: <writeDir>/bot_scripts (shared by all characters). Which files
  are running is persisted per character at /characterdata/<id>/scripts.json.
]]

Scripting = {}

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------
local panel         = nil
local disabledListW = nil   -- "Available" list (enabled == false)
local enabledListW  = nil   -- "Running" list (enabled == true)
local statusLabel   = nil
local autoReloadW   = nil   -- "Auto-reload last session scripts" checkbox

local debugWindow  = nil    -- transient debug console window
local debugListW   = nil    -- the debug console's row list (nil while closed)
local debugScrollW = nil    -- its scrollbar (for auto-scroll)
local debugSelectW = nil    -- invisible selectable text overlay (drag-select + copy)

local rescanEvent = nil    -- folder-watch timer (auto-pick-up of dropped files)
local lastFolderSig = nil  -- last seen folder file-set (skip rebuilds when unchanged)
local scripts    = {}      -- name -> { name, code, enabled, fn, cleanups, errors, storage }
local order      = {}      -- display/run order of names
local selName    = nil     -- selected script (in either list)
local runningScript = nil  -- the script currently executing (for cleanup registration / log context)
-- Synthetic per-waypoint script records for the cavebot "script" waypoint (see
-- Scripting.runSnippet). Keyed by waypoint identity so retries/laps REUSE the same
-- record instead of leaking a fresh one each pass; each record owns that waypoint's
-- storage + deferred cleanups (Timers/HUDs/event connections). STRONG refs: torn
-- down explicitly by Scripting.stopSnippets() (cavebot stop / logout / unload),
-- never by GC. Kept separate from `scripts` (the Scripting-tab list) on purpose.
local snippetRecords = {}
local MAX_ERRORS = 5       -- auto-disable a script after this many runtime errors
local initialized = false  -- guards a double init()/importStyle

-- Per-character "auto-reload last session scripts on login" toggle.
local autoReload    = true
local autoLoadList  = {}
local suppressAutoReloadSave = false  -- guards setChecked() during load() from re-saving

local debugLines = {}      -- ring buffer of { text, color } for the debug console
local DEBUG_MAX  = 300

-- ---------------------------------------------------------------------------
-- Debug console buffer (errors + script print()/ctx.log). Survives the window
-- being closed; opening it replays the buffer.
-- ---------------------------------------------------------------------------
local function refreshDebugSelection()
  if not debugSelectW then return end
  local parts = {}
  for i = 1, #debugLines do parts[i] = debugLines[i].text end
  debugSelectW:setText(table.concat(parts, '\n'))
end

local function debugAppend(text, color)
  text = '[' .. os.date('%H:%M:%S') .. '] ' .. tostring(text)
  color = color or '#cfcfcf'
  debugLines[#debugLines + 1] = { text = text, color = color }
  if #debugLines > DEBUG_MAX then table.remove(debugLines, 1) end
  if debugListW then
    local row = g_ui.createWidget('ScriptDebugRow', debugListW)
    row:setText(text)
    row:setColor(color)
    local kids = debugListW:getChildren()
    if #kids > DEBUG_MAX then
      local first = debugListW:getChildByIndex(1)
      if first then first:destroy() end
    end
    refreshDebugSelection()
    pcall(function() if debugScrollW then debugScrollW:setValue(debugScrollW:getMaximum()) end end)
  end
end

-- ---------------------------------------------------------------------------
-- Persistence
-- ---------------------------------------------------------------------------
local SCRIPTS_DIR = '/bot_scripts'   -- virtual path (mounted under the write dir)

local function ensureDir()
  if not g_resources.directoryExists(SCRIPTS_DIR) then
    pcall(function() g_resources.makeDir(SCRIPTS_DIR) end)
  end
end

-- Real OS path of the scripts folder (for g_platform.openDir).
local function scriptsRealDir()
  local wd = g_resources.getWriteDir() or ''
  wd = wd:gsub('[\\/]+$', '')
  -- Backslashes only: explorer.exe treats a '/' in the path as a command-line switch.
  return (wd .. SCRIPTS_DIR):gsub('/', '\\')
end

local function listScripts()
  ensureDir()
  local files = {}
  local ok, list = pcall(function() return g_resources.listDirectoryFiles(SCRIPTS_DIR) end)
  if ok and type(list) == 'table' then
    for _, name in ipairs(list) do
      if type(name) == 'string' and name:lower():match('%.lua$') then
        files[#files + 1] = name
      end
    end
  end
  table.sort(files, function(a, b) return a:lower() < b:lower() end)
  return files
end

local function readScriptCode(s)
  local vp = SCRIPTS_DIR .. '/' .. s.name
  if not g_resources.fileExists(vp) then return nil, 'file not found' end
  local ok, content = pcall(function() return g_resources.readFileContents(vp) end)
  if not ok then return nil, tostring(content) end
  return content or ''
end

local function configPath()
  if not LoadedPlayer or not LoadedPlayer:isLoaded() then return nil end
  return '/characterdata/' .. LoadedPlayer:getId() .. '/scripts.json'
end

local function refreshAutoLoadList()
  autoLoadList = {}
  for _, name in ipairs(order) do
    if scripts[name] and scripts[name].enabled then autoLoadList[#autoLoadList + 1] = name end
  end
end

local function save()
  local p = configPath()
  if not p then return end
  local out = { enabled = autoLoadList, selected = selName, autoReload = autoReload }
  local ok, res = pcall(function() return json.encode(out, 2) end)
  if ok and res then g_resources.writeFileContents(p, res) end
end

-- ---------------------------------------------------------------------------
-- Crash-loop guard
--   A player script that HARD-crashes the client while its body runs (e.g. a C++
--   binding that throws -> g_logger.fatal, which a pcall does NOT catch) would leave
--   the player stuck in an open-login-crash loop, because the offending script is
--   re-enabled automatically on every login. So, during the login auto-reload, we
--   write the name of the script whose body is about to run into a marker file on
--   disk BEFORE running it, and delete the marker once it survives. If a marker is
--   still present on the next login, that script killed the client last time: we skip
--   it (poison) and drop it from the auto-load list, so the player is never trapped.
--   Covers the SYNCHRONOUS body crash (the observed case). A crash AFTER a wait()
--   escapes it (the body already returned and the marker was cleared), but by then the
--   login auto-reload is no longer in flight.
-- ---------------------------------------------------------------------------
local function loadGuardPath()
  if not LoadedPlayer or not LoadedPlayer:isLoaded() then return nil end
  return '/characterdata/' .. LoadedPlayer:getId() .. '/scripts_loading.txt'
end

local function readLoadGuardName()
  local p = loadGuardPath()
  if not p or not g_resources.fileExists(p) then return nil end
  local ok, c = pcall(function() return g_resources.readFileContents(p) end)
  if not ok or type(c) ~= 'string' then return nil end
  c = c:gsub('%s+$', '')
  return (#c > 0) and c or nil
end

local function setLoadGuard(name)
  local p = loadGuardPath()
  if p then pcall(function() g_resources.writeFileContents(p, name) end) end
end

local function clearLoadGuard()
  local p = loadGuardPath()
  if p and g_resources.fileExists(p) then pcall(function() g_resources.deleteFile(p) end) end
end

local function setStatus(text, color)
  if not statusLabel then return end
  statusLabel:setText(text or '')
  if color then statusLabel:setColor(color) end
end

-- ---------------------------------------------------------------------------
-- Per-script cleanup + error accounting (generalized runningScript mechanism)
--   Each script owns a list of cleanup fns (timers/events/HUDs register here via
--   ctx.onCleanup). When a script unloads / errors-out / relogs, every cleanup
--   runs (newest first) and the list is reset.
-- ---------------------------------------------------------------------------
local onScriptError  -- fwd decl

-- Run every cleanup the script registered (Timers, event disconnects, HUD destroys).
local function stopScript(s)
  -- Cancel any wait() resumes still queued for this script (a body/callback parked on
  -- wait), so an unload / reload / relog kills them cleanly instead of firing later.
  if s.scheduled then
    for ev in pairs(s.scheduled) do pcall(removeEvent, ev) end
    s.scheduled = {}
  end
  if s.cleanups then
    -- newest-first so e.g. an event registered after a timer is torn down first
    for i = #s.cleanups, 1, -1 do
      local fn = s.cleanups[i]
      s.cleanups[i] = nil
      if type(fn) == 'function' then pcall(fn) end
    end
  end
  s.cleanups = {}
end

-- Count a runtime error against a script; auto-disable after MAX_ERRORS (which also
-- runs its cleanups, so a broken script can't keep firing).
onScriptError = function(s, err)
  s.errors = (s.errors or 0) + 1
  debugAppend((s.name or '?') .. ' runtime error: ' .. tostring(err), '#ff6666')
  -- Snippet (cavebot waypoint) records only LOG a callback error: they never
  -- auto-disable (the cavebot owns their lifecycle via Scripting.stopSnippets) and
  -- are not in the Scripting-tab lists, so refreshLists()/save() don't apply.
  if s.isSnippet then return end
  if s.errors >= MAX_ERRORS then
    s.enabled = false
    stopScript(s)
    debugAppend(s.name .. ' disabled after ' .. MAX_ERRORS .. ' errors', '#ffaa55')
    Scripting.refreshLists()
    save()
  end
end

-- Run `fn(...)` in the run-context of script `s` (pcall + error accounting).
-- Restores the previous runningScript so nested calls are safe.
local function runInScript(s, fn, ...)
  if not s or not s.enabled then return false end
  local prev = runningScript
  runningScript = s
  local ok, ret = pcall(fn, ...)
  runningScript = prev
  if not ok then onScriptError(s, ret) end
  return ok, ret
end

-- ---------------------------------------------------------------------------
-- Cooperative wait() -- coroutine driver (Zerobot parity)
--   Zerobot scripts call wait(ms) to pause a sequence ("do X; wait(1000); do Y")
--   or to pace a `while true` loop. Zerobot runs each script on its own thread, so
--   wait() there just sleeps that thread. The OTClient runs EVERYTHING on one thread
--   (the dispatcher), so a blocking wait would freeze the whole client. We emulate it
--   cooperatively: every user body / callback / snippet runs inside a Lua coroutine;
--   wait(ms) YIELDS it and we reschedule the resume `ms` later via scheduleEvent, so
--   the main thread stays free the whole time.
--
--   Safe across C-call boundaries: the resume ALWAYS happens here in Lua (never from
--   C++), so a yield unwinds only up to our resume -- LuaJIT even lets it cross the
--   pcall inside a script. Pending resumes are tracked in s.scheduled and cancelled by
--   stopScript(), so a wait in flight never outlives an unload / reload / relog.
-- ---------------------------------------------------------------------------
local driveScriptCo  -- fwd decl (mutually recursive with scheduleResume)

-- ---------------------------------------------------------------------------
-- Runtime watchdog
--   A script coroutine that runs too long WITHOUT yielding (a `while true do end` with
--   no wait(), a runaway loop) would freeze the single dispatcher thread. Before every
--   resume we arm a debug count-hook on the coroutine that checks the wall clock every
--   WATCHDOG_CHECK instructions and error()s out once THIS slice has run past
--   WATCHDOG_MS. The error propagates out of resume like any script error ->
--   onScriptError (auto-disable) / the snippet's 'runtime:' path.
--
--   CRUCIAL LuaJIT detail: count hooks do NOT fire inside compiled traces, and a hot
--   loop like `while true do end` is exactly what LuaJIT compiles to a trace -- so the
--   hook would never run and the client would hang. We therefore turn the JIT OFF
--   around the resume, forcing the script to run interpreted where the hook does fire.
--   The client is single-threaded and cooperative (nothing else runs during this
--   slice), so dropping the JIT here slows only the SCRIPT, not the rest of the client.
--
--   LIMIT: a user pcall wrapping the hot loop can swallow the abort (it re-fires every
--   WATCHDOG_CHECK instructions, but a determined `while true do pcall() end` isn't
--   fully stoppable from pure Lua); this covers the accidental freeze, not abuse.
-- ---------------------------------------------------------------------------
-- DISABLED (2026-07): arming debug.sethook on the script coroutine crashes the client
-- with "C++ call failed | fatal error" the moment the body calls ANY client binding
-- (loading even a print-only script dies). The count-hook + client bindings + LuaJIT's
-- external unwinding + the per-binding catch(...) in luaCppFunctionCallback interact
-- badly in-process (it never reproduces in the standalone LuaJIT, which has no such
-- bindings). Kept behind this flag so the mechanism can be re-attempted later, most
-- likely in C++ (a time budget checked inside luaCppFunctionCallback, no Lua hook). With
-- it off, resumeWatched is a plain coroutine.resume -- scripts load again; the trade-off
-- is that a `while true` with no wait() can once more freeze the dispatcher (the linter
-- still warns about it). All the OTHER defenses (crash-loop guard, pcall/xpcall
-- hardening, linter, C++ catch) are independent of this and stay on.
local WATCHDOG_ENABLED = false
local WATCHDOG_MS    = 1000      -- max wall-clock one resume may run without yielding
local WATCHDOG_CHECK = 2000000   -- instructions between deadline checks (~a few ms of work)
local watchdogDeadline = 0
local jitOffDepth = 0            -- nested resumes re-enable the JIT only back at depth 0

-- The watchdog abort is raised as this UNIQUE sentinel object (not a string). The
-- sandbox's pcall/xpcall (below) re-throw it instead of letting a script swallow it, so
-- a `while true do pcall(...) end` can't defeat the watchdog. Scripts never get a
-- reference to it (module local) and have no other error-capture primitive
-- (coroutine/raw pcall aren't exposed), so they can neither intercept nor forge it. Its
-- __tostring gives onScriptError/reports a readable line.
local WATCHDOG_ERR = setmetatable({}, {
  __tostring = function() return 'travou >' .. WATCHDOG_MS .. 'ms sem wait()/retorno (loop sem wait()?)' end,
})

local function watchdogHook()
  if g_clock.millis() >= watchdogDeadline then
    error(WATCHDOG_ERR)
  end
end

-- Resume `co` under the watchdog; same (ok, y) contract as coroutine.resume. Nesting
-- safe: the deadline is saved/restored and the JIT toggle is depth-counted, so a resume
-- that itself drives another coroutine restores both when it returns.
--   DEFENSIVE: if debug.sethook is missing in some embedding, degrade to a plain resume
--   instead of erroring on EVERY script load -- the watchdog must never be the thing that
--   breaks script loading. jit.off/on are pcall'd for the same reason (a JIT-disabled
--   build makes jit.on raise "permanently disabled"). luaL_openlibs provides both here.
local hasSethook = type(debug) == 'table' and type(debug.sethook) == 'function'

local function resumeWatched(co)
  if not WATCHDOG_ENABLED or not hasSethook then return coroutine.resume(co) end  -- watchdog off: plain resume
  local prevDeadline = watchdogDeadline
  watchdogDeadline = g_clock.millis() + WATCHDOG_MS
  if jit then jitOffDepth = jitOffDepth + 1; if jitOffDepth == 1 then pcall(jit.off) end end
  debug.sethook(co, watchdogHook, '', WATCHDOG_CHECK)
  local ok, y = coroutine.resume(co)
  pcall(debug.sethook, co)   -- clear the hook (safe no-op if co is now dead)
  if jit then jitOffDepth = jitOffDepth - 1; if jitOffDepth == 0 then pcall(jit.on) end end
  watchdogDeadline = prevDeadline
  return ok, y
end

-- Direct-run watchdog: the loop guard for the NO-coroutine path (COROUTINE_SAFE = false).
-- Same mechanism as resumeWatched but arms the count hook on the MAIN thread around a
-- plain pcall(thunk), so a `while true` with no wait() is aborted instead of freezing the
-- dispatcher. This is SAFE (unlike the coroutine watchdog): the body runs on the main
-- thread, so client bindings use the right stack. The sandbox pcall/xpcall still re-throw
-- WATCHDOG_ERR, so `while true do pcall() end` is caught too. Returns (ok, y) like pcall.
-- Residual risk: if the hook fires while a client binding is >WATCHDOG_MS deep in a Lua
-- callback (rare), the error can unwind through it -- flip DIRECT_WATCHDOG off if that
-- ever bites; the pure-Lua loop (the common case) is fine.
local DIRECT_WATCHDOG = true

local function pcallWatched(thunk)
  if not (DIRECT_WATCHDOG and hasSethook) then return pcall(thunk) end
  watchdogDeadline = g_clock.millis() + WATCHDOG_MS
  if jit then pcall(jit.off) end
  debug.sethook(watchdogHook, '', WATCHDOG_CHECK)
  local ok, y = pcall(thunk)
  pcall(debug.sethook)   -- clear the main-thread hook
  if jit then pcall(jit.on) end
  return ok, y
end

-- ---------------------------------------------------------------------------
-- Watchdog-proof pcall / xpcall for the sandbox
--   These replace the native pcall/xpcall in SANDBOX_GLOBALS. They behave EXACTLY like
--   the natives for every normal error -- so legitimate error handling is untouched --
--   but RE-THROW the WATCHDOG_ERR sentinel so a script cannot catch and ignore a
--   watchdog abort (the `while true do pcall(loop) end` escape). rawpcall is the native
--   pcall captured here; scripts don't get it. pack()/n keep multi-value returns with
--   embedded nils exact.
-- ---------------------------------------------------------------------------
local rawpcall = pcall
local function pack(...) return { n = select('#', ...), ... } end

local function sandboxPcall(f, ...)
  local r = pack(rawpcall(f, ...))
  if r[1] == false and r[2] == WATCHDOG_ERR then error(WATCHDOG_ERR) end
  return unpack(r, 1, r.n)
end

-- Reimplemented on top of pcall so WATCHDOG_ERR is intercepted BEFORE the user's handler
-- runs; as a compatible bonus it forwards extra args to f like 5.2's xpcall.
local function sandboxXpcall(f, handler, ...)
  local a = pack(...)
  local r = pack(rawpcall(function() return f(unpack(a, 1, a.n)) end))
  if r[1] then return unpack(r, 1, r.n) end
  if r[2] == WATCHDOG_ERR then error(WATCHDOG_ERR) end
  return false, (handler and handler(r[2]))
end

-- Queue the next resume of `co` (script `s`) `ms` from now. Tracked in s.scheduled
-- so stopScript() can cancel it if the script is torn down mid-wait.
local function scheduleResume(s, co, ms)
  ms = tonumber(ms) or 0
  if ms < 0 then ms = 0 end
  s.scheduled = s.scheduled or {}
  local ev
  ev = scheduleEvent(function()
    if s.scheduled then s.scheduled[ev] = nil end
    driveScriptCo(s, co)
  end, ms)
  s.scheduled[ev] = true
end

-- Resume a parked coroutine; if it wait()s again, reschedule; abandon it silently if
-- the script was disabled during the wait.
driveScriptCo = function(s, co)
  if not s.enabled then return end
  local prev = runningScript
  runningScript = s
  local ok, y = resumeWatched(co)
  runningScript = prev
  if coroutine.status(co) == 'dead' then
    if not ok then onScriptError(s, y) end
    return
  end
  scheduleResume(s, co, y)
end

-- The client's LuaInterface is NOT coroutine-safe: g_lua always drives the MAIN
-- lua_State, never the running coroutine's thread (L is set once in createLuaState and
-- never synced -- luainterface.cpp), so a client binding called from INSIDE a script
-- coroutine reads the main thread's stack instead of the coroutine's and hard-crashes
-- ("C++ call failed | fatal error"). That is why any script that touches an API dies
-- while a print-only script survives. Until the C++ side syncs g_lua.L to the calling
-- thread in luaCppFunctionCallback, run bodies/callbacks DIRECTLY on the main thread.
-- Trade-off: wait() has no coroutine to yield into, so it no-ops (a `while true ...
-- wait()` loop would spin -- the linter warns about the no-wait case). Flip COROUTINE_SAFE
-- to true once the C++ patch is built, which restores wait() with bindings working.
local COROUTINE_SAFE = false

-- Start `thunk` in script `s`. Returns (true, retval) when it finishes synchronously
-- (the common case), (false, nil) when it parked on wait() (coroutine path only).
local function startScriptCo(s, thunk)
  if not COROUTINE_SAFE then
    -- Direct run on the main thread: client bindings operate on the right stack; wait()
    -- no-ops (no coroutine to yield). pcallWatched adds the main-thread loop guard so a
    -- `while true` with no wait() aborts instead of freezing the client.
    local prev = runningScript
    runningScript = s
    local ok, y = pcallWatched(thunk)
    runningScript = prev
    if not ok then onScriptError(s, y) end
    return true, (ok and y or nil)
  end
  local co = coroutine.create(thunk)
  local prev = runningScript
  runningScript = s
  local ok, y = resumeWatched(co)
  runningScript = prev
  if coroutine.status(co) == 'dead' then
    if not ok then onScriptError(s, y) end
    return true, (ok and y or nil)
  end
  scheduleResume(s, co, y)
  return false, nil
end

-- The sandbox `wait(ms)`: yields the running script coroutine so the driver resumes it
-- `ms` later. On the main thread (not inside a driven coroutine) it CANNOT yield without
-- freezing the client, so it no-ops with a one-time hint instead of raising.
local waitWarned = false
local function sandboxWait(ms)
  if coroutine.running() == nil then
    if not waitWarned then
      waitWarned = true
      debugAppend('wait(): so funciona no corpo do script, num callback (Timer/evento/HUD) ou num waypoint script; fora disso e ignorado -- use Timer(...) para repeticao.', '#ffaa55')
    end
    return
  end
  return coroutine.yield(tonumber(ms) or 0)
end

-- ---------------------------------------------------------------------------
-- ctx -- runtime utilities handed to every api/*.lua builder. See header.
-- ---------------------------------------------------------------------------
-- Module-root-relative virtual path (matches the rest of game_helper, e.g.
-- dofile("/game_helper/cavebots/init.lua")). g_resources auto-mounts /mods.
local MODULE_DIR = '/game_helper/scripting/'

-- Seed the bundled example/test scripts (Zerobot dialect) shipped in the mod
-- (scripting/examples/*.lua) into the writable /bot_scripts folder, so they show
-- up in the Available list. Runs ONCE -- a marker file guards re-seeding, so
-- deleting an example does NOT make it reappear -- and only writes files that are
-- missing, so a user's same-named edits are never clobbered. Best-effort: if the
-- mod's examples dir can't be listed yet, it just retries on the next start.
local function seedExamples()
  local marker = SCRIPTS_DIR .. '/.examples_seeded'
  if g_resources.fileExists(marker) then return 0 end
  local srcDir = MODULE_DIR .. 'examples'
  local ok, list = pcall(function() return g_resources.listDirectoryFiles(srcDir) end)
  if not (ok and type(list) == 'table') then return 0 end
  local copied = 0
  for _, name in ipairs(list) do
    if type(name) == 'string' and name:lower():match('%.lua$') then
      local dst = SCRIPTS_DIR .. '/' .. name
      if not g_resources.fileExists(dst) then
        local rok, content = pcall(function() return g_resources.readFileContents(srcDir .. '/' .. name) end)
        if rok and content and #content > 0 then
          if pcall(function() g_resources.writeFileContents(dst, content) end) then copied = copied + 1 end
        end
      end
    end
  end
  pcall(function() g_resources.writeFileContents(marker, 'seeded\n') end)
  return copied
end

local ctx = {}

function ctx.log(...)
  local parts = {}
  for i = 1, select('#', ...) do parts[i] = tostring(select(i, ...)) end
  debugAppend((runningScript and (runningScript.name .. ': ') or '') .. table.concat(parts, ' '), '#cfe0ff')
end

function ctx.logColor(color, ...)
  local parts = {}
  for i = 1, select('#', ...) do parts[i] = tostring(select(i, ...)) end
  debugAppend((runningScript and (runningScript.name .. ': ') or '') .. table.concat(parts, ' '), color)
end

-- Register a cleanup against the CURRENT script. Returns a handle whose :cancel()
-- (or .cancel()) removes it early. Safe to call only while a script is loading or
-- inside one of its callbacks (runningScript must be set).
function ctx.onCleanup(fn)
  local s = runningScript
  if not s then
    error('onCleanup() can only be called while a script is running', 2)
  end
  if type(fn) ~= 'function' then
    error('onCleanup(fn): fn must be a function', 2)
  end
  s.cleanups = s.cleanups or {}
  s.cleanups[#s.cleanups + 1] = fn
  local removed = false
  local function cancel()
    if removed then return end
    removed = true
    if s.cleanups then
      for i = 1, #s.cleanups do
        if s.cleanups[i] == fn then table.remove(s.cleanups, i); break end
      end
    end
  end
  return { cancel = cancel }
end

-- The script currently loading/executing (opaque identity), or nil.
function ctx.runningScript() return runningScript end

-- Run fn(...) IMMEDIATELY in the CURRENT script's context (pcall + error
-- accounting). Use when you already hold the script context (you're inside a load
-- body or an already-wrapped callback). Returns ok, ret.
function ctx.guard(fn, ...)
  local s = runningScript
  if not s then
    -- No script context (shouldn't happen for api use): still pcall to stay safe.
    return pcall(fn, ...)
  end
  return runInScript(s, fn, ...)
end

-- Wrap `fn` so it can be invoked LATER (timer tick / event dispatch / HUD click),
-- after the load body has returned and runningScript is nil. The CURRENT script is
-- captured NOW (at wrap time), so the deferred call still runs in that script's
-- context with pcall + error accounting (auto-disable keeps working). The wrapper
-- no-ops once the script is disabled. THIS is what api/timer.lua, api/hud.lua and
-- the event dispatcher should use for any callback they store and call later.
-- Returns the wrapper; it forwards the callback's return values (after ok).
function ctx.wrap(fn)
  local s = runningScript
  if not s then
    error('wrap() must be called while a script is running', 2)
  end
  if type(fn) ~= 'function' then
    error('wrap(fn): fn must be a function', 2)
  end
  return function(...)
    if not s.enabled then return end
    -- Run the callback inside a coroutine so it may wait(). Common case (no wait):
    -- it finishes on the first resume and its value is returned synchronously,
    -- exactly like the old runInScript path; if it wait()s, the driver carries the
    -- rest in the background and we return nil now.
    local n = select('#', ...)
    local a = { ... }
    local _, ret = startScriptCo(s, function() return fn(unpack(a, 1, n)) end)
    return ret
  end
end

function ctx.isOnline()
  return g_game.isOnline() and g_game.getLocalPlayer() ~= nil
end

function ctx.resolvePath(rel)
  rel = tostring(rel or ''):gsub('^/', '')
  return MODULE_DIR .. rel
end

-- ---------------------------------------------------------------------------
-- Sandbox globals: a CLOSED table that does NOT chain to the real _G.
-- ---------------------------------------------------------------------------
local SAFE_STRING = {}
for k, v in pairs(string) do if k ~= 'dump' then SAFE_STRING[k] = v end end
local SANDBOX_GLOBALS = {
  math = math, string = SAFE_STRING, table = table,
  select = select, pairs = pairs, ipairs = ipairs, next = next, type = type,
  tostring = tostring, tonumber = tonumber, unpack = unpack, _VERSION = _VERSION,
  pcall = sandboxPcall, xpcall = sandboxXpcall, error = error, assert = assert,
  rawget = rawget, rawset = rawset, rawequal = rawequal,
  setmetatable = setmetatable, getmetatable = getmetatable,
  os = { time = os.time, date = os.date, clock = os.clock, difftime = os.difftime },
  -- LuaJIT BitOp: pure bitwise math (band/bor/bxor/bnot/lshift/rshift/...). No I/O,
  -- safe to expose, and Zerobot scripts rely on it for flag/bitmask handling.
  bit = bit,
  -- Zerobot cooperative wait(ms): pause a sequence / pace a loop without freezing
  -- the client (yields the script coroutine; see sandboxWait / driveScriptCo).
  wait = sandboxWait,
}

-- ---------------------------------------------------------------------------
-- API loader: build ZB_API from scripting/api/*.lua (each returns a builder).
--   Load every builder first (tolerant of missing files), THEN construct every
--   namespace, so lazy cross-refs (api.X) always resolve after construction.
-- ---------------------------------------------------------------------------
local API_MODULES = { 'json', 'enums', 'creature', 'player', 'map', 'container',
                      'inventory', 'npc', 'game', 'timer', 'hud', 'cavebot', 'engine',
                      'client', 'spells', 'sound', 'hotkeymanager', 'custommodalwindow' }
local NS_NAME = { json = 'JSON', enums = 'Enums', creature = 'Creature', player = 'Player',
                  map = 'Map', container = 'Container', inventory = 'Inventory', npc = 'Npc',
                  game = 'Game', timer = 'Timer', hud = 'HUD',
                  cavebot = 'CaveBot', engine = 'Engine',
                  client = 'Client', spells = 'Spells', sound = 'Sound',
                  hotkeymanager = 'HotkeyManager', custommodalwindow = 'CustomModalWindow' }

local ZB_API = {}
local apiLoaded = false

-- Build ZB_API once (idempotent). The namespaces are thin, STATELESS wrappers
-- (they call g_game/g_map fresh each invocation), so they survive relog untouched;
-- per-session state (event connections) is owned by the event-framework namespace,
-- which reacts to login/logout itself rather than being rebuilt here.
local function loadApi()
  if apiLoaded then return end
  apiLoaded = true
  local builders = {}
  for _, m in ipairs(API_MODULES) do
    local path = MODULE_DIR .. 'api/' .. m .. '.lua'
    if g_resources.fileExists(path) then
      local ok, b = pcall(dofile, path)
      if ok and type(b) == 'function' then
        builders[m] = b
      else
        debugAppend('[scripting] api/' .. m .. ' failed to load: ' .. tostring(b), '#ff6666')
        if g_logger then pcall(function() g_logger.error('[scripting] api/' .. m .. ': ' .. tostring(b)) end) end
      end
    else
      -- Tolerant: a namespace not yet implemented just stays absent (other agents
      -- fill these in). Note it once so the gap is visible in the console.
      debugAppend('[scripting] api/' .. m .. '.lua not present yet (namespace ' .. (NS_NAME[m] or m) .. ' unavailable)', '#ffaa55')
    end
  end
  for _, m in ipairs(API_MODULES) do
    if builders[m] then
      local ok, ns = pcall(builders[m], ZB_API, ctx)
      if ok then
        ZB_API[NS_NAME[m]] = ns
      else
        debugAppend('[scripting] building ' .. (NS_NAME[m] or m) .. ' failed: ' .. tostring(ns), '#ff6666')
        if g_logger then pcall(function() g_logger.error('[scripting] build ' .. (NS_NAME[m] or m) .. ': ' .. tostring(ns)) end) end
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- makeEnv: fresh per-chunk env. Closed (reads fall through to SANDBOX_GLOBALS),
-- injecting every ZB_API namespace (Game/Player/Map/Creature/Container/Inventory/Npc/
-- Enums/Timer/HUD/JSON/CaveBot/Engine) + print. See header for the full contract.
-- ---------------------------------------------------------------------------
function Scripting.makeEnv(extra)
  local t = {}
  -- Inject the Zerobot-dialect namespaces. They live only inside the sandbox env,
  -- never in _G, so they cannot shadow the engine's C++ `Creature`/`Container`.
  for _, m in ipairs(API_MODULES) do
    local nsName = NS_NAME[m]
    if ZB_API[nsName] ~= nil then t[nsName] = ZB_API[nsName] end
  end
  -- Zerobot GLOBAL destroyTimer(name): stop+drop the running script's same-named
  -- Timer. Injected here (not in the frozen SANDBOX_GLOBALS) because it needs the
  -- built ZB_API.Timer namespace, which is constructed after that table.
  local T = ZB_API.Timer
  if T and type(T.destroyNamed) == 'function' then t.destroyTimer = T.destroyNamed end
  if extra then for k, v in pairs(extra) do t[k] = v end end
  return setmetatable(t, { __index = SANDBOX_GLOBALS })
end

-- Get (or lazily create) the synthetic script record for a cavebot "script"
-- waypoint, identified by `key` (the waypoint index, or the chunk name as a
-- fallback). Reusing one record per waypoint makes re-runs (retry / cavebot lap)
-- IDEMPOTENT: a Timer of the same name is replaced rather than duplicated, and the
-- record's `storage` lets a script guard create-once HUD/Event/Modal side-effects.
-- The record mirrors a Scripting-tab script's shape (name/enabled/cleanups/storage/
-- errors) so ctx.wrap/ctx.onCleanup and api/timer|hud|game|custommodalwindow treat
-- it exactly like a normal running script. `isSnippet` marks it for the error path
-- (never auto-disabled) and the teardown (Scripting.stopSnippets).
local function getSnippetRecord(key)
  local rec = snippetRecords[key]
  if not rec then
    rec = { name = 'cavebot:wp' .. tostring(key), enabled = true,
            cleanups = {}, storage = {}, errors = 0, isSnippet = true }
    snippetRecords[key] = rec
  end
  return rec
end

-- ---------------------------------------------------------------------------
-- runSnippet: run a one-shot Lua chunk in the SAME sandbox as user scripts
-- (makeEnv). Used by the cavebot "script" waypoint so its scripting surface is
-- identical to the Scripting tab (Player/Map/Game/CaveBot/Enums/JSON/...).
-- The chunk runs once and its return value is handed to the caller (the cavebot uses
-- it as the action result: true/false/"retry"). It runs inside a coroutine so it may
-- wait(ms): a chunk with no wait() completes in one call (synchronous, as before); one
-- that wait()s is parked and resumed across cavebot re-polls (see resumeSnippet).
--
-- Unlike a bare pcall, the chunk runs with `runningScript` set to a synthetic
-- per-waypoint record (see getSnippetRecord). THIS is what makes Timer()/HUD()/
-- Game.registerEvent()/CustomModalWindow()/CaveBot.pause(ms>0) work inside a
-- waypoint script: they all defer through ctx.wrap/ctx.onCleanup, which require a
-- running script (otherwise they raise, the pcall swallows it, and pause(ms) would
-- even freeze the cavebot). The record's Timers/HUDs/events live until
-- Scripting.stopSnippets tears them down (cavebot stop / logout / unload).
--   code  : Lua source string ('' / whitespace => no-op, returns ok=true).
--   extra : table merged into the env on top of the ZB namespaces (e.g.
--           retries/prev/delay/print). Optional. `storage` is injected from the
--           record unless `extra` already carries one.
--   chunk : chunk name for error messages (default '@cavebot_script').
--   key   : waypoint identity for the record (defaults to `chunk`). Same key ->
--           same record -> idempotent re-runs across retries and laps.
-- Returns ok(boolean), result-or-error. On failure the 2nd value is a
-- 'compile: '/'runtime: ' prefixed message. Compiled fresh each call (waypoints
-- are not a hot path); no g_* singletons reach the chunk.
-- ---------------------------------------------------------------------------
-- Resume a cavebot snippet coroutine (see Scripting.runSnippet). Returns (ok, result)
-- shaped for the waypoint handler:
--   completed -> (true, <script return>)  -- true/false/"retry"/nil drive the cavebot
--   wait(ms)  -> (true, "retry") and park until now+ms; the cavebot re-polls this
--                waypoint meanwhile and we resume the SAME coroutine once it elapses
--   error     -> (false, "runtime: ...")
local function resumeSnippet(s)
  local prev = runningScript
  runningScript = s
  local ok, y = resumeWatched(s.co)
  runningScript = prev
  if coroutine.status(s.co) == 'dead' then
    s.co = nil
    s.wakeAt = nil
    if not ok then return false, 'runtime: ' .. tostring(y) end
    return true, y
  end
  -- yielded on wait(ms): park until wakeAt; keep the cavebot polling with "retry"
  local ms = tonumber(y) or 0
  if ms < 0 then ms = 0 end
  s.wakeAt = g_clock.millis() + ms
  return true, 'retry'
end

function Scripting.runSnippet(code, extra, chunk, key)
  if type(code) ~= 'string' or code:match('^%s*$') then return true end
  loadApi()
  local s = getSnippetRecord(key or chunk or '@cavebot_script')

  -- Resume path: a previous call parked this snippet on wait(ms). Don't recompile --
  -- resume the same coroutine once its wait elapses; until then answer "retry" so the
  -- cavebot re-polls this waypoint without advancing.
  if s.co then
    if s.wakeAt and g_clock.millis() < s.wakeAt then return true, 'retry' end
    return resumeSnippet(s)
  end

  local fn, err = loadstring(code, chunk or '@cavebot_script')
  if not fn then return false, 'compile: ' .. tostring(err) end
  if setfenv then
    -- Inject the waypoint's persistent storage (unless the caller supplied one),
    -- so scripts can do `if not storage.x then storage.x = HUD(...) end`.
    local env = { storage = s.storage }
    if extra then for k, v in pairs(extra) do env[k] = v end end
    setfenv(fn, Scripting.makeEnv(env))
  end
  -- Client isn't coroutine-safe (see startScriptCo): run the snippet body DIRECTLY on
  -- the main thread so its API calls don't crash. wait() no-ops (no coroutine to park
  -- into); a snippet that wanted to wait just runs to completion. Restores to the
  -- coroutine path when COROUTINE_SAFE flips true.
  if not COROUTINE_SAFE then
    local prev = runningScript
    runningScript = s
    local ok, y = pcallWatched(fn)
    runningScript = prev
    if not ok then return false, 'runtime: ' .. tostring(y) end
    return true, y
  end
  -- Body runs inside a coroutine (in the record's context so Timer/HUD/registerEvent/
  -- onCleanup attach to `s`) so it may wait(). No wait() -> completes on the first
  -- resume (synchronous, as before); wait() -> parked and resumed across re-polls.
  s.co = coroutine.create(fn)
  return resumeSnippet(s)
end

-- Tear down every waypoint snippet record: run each record's cleanups (Timers
-- stopped, HUDs destroyed, event connections dropped) and drop the record. This is
-- the cavebot-session teardown for script waypoints -- CALL IT when the cavebot
-- STOPS or the character logs out/relogs, so a waypoint's side-effects never leak
-- past the run that created them. Wired here from Scripting.offline()/terminate();
-- the cavebot engine also calls it from CaveBot.setOff (cavebots/core.lua) so a
-- manual stop / profile switch tears snippets down immediately.
function Scripting.stopSnippets()
  for k, s in pairs(snippetRecords) do
    s.enabled = false        -- any already-queued wrapped callback now no-ops
    stopScript(s)            -- run its cleanups newest-first
    snippetRecords[k] = nil
  end
end

-- Bridge for code OUTSIDE the sandbox (e.g. the cavebot engine) to fire a scripting
-- Game.Events.* into the registered listeners. Resolves the already-built Game
-- namespace and dispatches; a pure no-op (guarded) if the API isn't built yet or no
-- script registered that event type. cavebots/core.lua calls this on a LABEL
-- waypoint: Scripting.emitGameEvent(Game.Events.LABEL (== 13), labelName).
function Scripting.emitGameEvent(eventType, ...)
  if eventType == nil then return end
  if not apiLoaded then loadApi() end
  local Game = ZB_API and ZB_API.Game
  if type(Game) ~= 'table' or type(Game.executeEvents) ~= 'function' then return end
  pcall(Game.executeEvents, eventType, ...)
end

-- ---------------------------------------------------------------------------
-- Compile / run
-- ---------------------------------------------------------------------------
local function runScriptOnce(s)
  if not s.fn then return end
  stopScript(s)            -- clear any cleanups left from a previous run
  -- Run the body inside a coroutine so it may wait(): a plain body finishes on the
  -- first resume (identical to the old pcall path); a body that wait()s -- including
  -- a `while true ... wait()` loop -- is driven the rest of the way by driveScriptCo
  -- without ever blocking the dispatcher.
  startScriptCo(s, s.fn)
end

-- ---------------------------------------------------------------------------
-- Heuristic linter (advisory only)
--   Runs on enable, AFTER the syntax check passes. Emits yellow warnings to the Debug
--   console for common footguns; it NEVER blocks loading and is deliberately simple (a
--   textual scan, not a parser), so expect the odd false positive/negative. It cannot
--   prove a script is safe (halting problem) -- the real protection is runtime
--   containment (closed sandbox + watchdog + error auto-disable). This just catches the
--   obvious mistakes early and points the user at them.
-- ---------------------------------------------------------------------------
local SANDBOX_BLOCKED = {  -- names the sandbox does NOT provide -> nil index at runtime
  'io', 'require', 'dofile', 'loadfile', 'loadstring', 'load', 'coroutine', 'debug',
  'package', 'module', 'g_game', 'g_map', 'g_clock', 'g_things', 'g_resources', 'g_ui',
  'g_window', 'g_settings', 'g_logger', 'g_platform', 'connect', 'disconnect',
  'scheduleEvent', 'cycleEvent', 'addEvent', 'modules',
}

-- Blank out comments and string literals so the checks below don't fire on their text.
-- (Lua patterns: '.' matches newlines too, so '.-' spans multi-line comments/strings.)
local function stripNonCode(code)
  code = code:gsub('%-%-%[%[.-%]%]', ' ')  -- block comments  --[[ ... ]]
  code = code:gsub('%-%-[^\n]*', ' ')       -- line comments   -- ...
  code = code:gsub('%[%[.-%]%]', ' ')       -- long strings    [[ ... ]]
  code = code:gsub('"[^"\n]*"', '""')       -- "double" strings
  code = code:gsub("'[^'\n]*'", "''")       -- 'single' strings
  return code
end

local function lintScript(name, code)
  local src = stripNonCode(code)
  local function warn(msg) debugAppend(name .. ': aviso -- ' .. msg, '#ffcc66') end

  -- 1) Endless loop with no cooperative yield -> would freeze the dispatcher. The
  --    watchdog aborts it, but flag it so the user adds a wait() (the intended fix).
  if (src:match('while%s+true%s+do') or src:match('while%s+1%s+do')
        or src:match('for%s+[%w_]+%s*=.-,%s*math%.huge'))
      and not src:match('wait%s*%(')
      and not src:match('%f[%w_]break%f[%W]')
      and not src:match('%f[%w_]return%f[%W]') then
    warn('loop infinito sem wait()/break/return -- pode congelar; use wait(ms) para pausar cada volta')
  end

  -- 2) Very large numeric literal -> dangerous if it reaches an allocating API (OOM).
  local big = src:match('%d%d%d%d%d%d%d%d+') or src:match('%d[eE]%+?%d%d+')
  if big then
    warn('numero muito grande (' .. big .. ') -- se usado como tamanho/repeticao pode estourar memoria')
  end

  -- 3) Identifiers the sandbox blocks -> nil index at runtime.
  for _, n in ipairs(SANDBOX_BLOCKED) do
    if src:match('%f[%w_]' .. n .. '%f[%W]') then
      warn("'" .. n .. "' nao esta disponivel no sandbox -- vai falhar em runtime")
    end
  end
end

local function compile(s)
  s.fn = nil
  local code, rerr = readScriptCode(s)
  if not code then
    debugAppend(s.name .. ' read error: ' .. tostring(rerr), '#ff6666')
    return false, rerr
  end
  s.code = code
  if #code == 0 then return true end
  local fn, err = loadstring(code, '@' .. s.name)
  if not fn then
    debugAppend(s.name .. ' compile error: ' .. tostring(err), '#ff6666')
    return false, err
  end
  pcall(lintScript, s.name, code)   -- advisory warnings only; never blocks the load
  -- Sandbox: inject the ZB_API namespaces + `print`=ctx.log + the per-script
  -- `storage` table on top of the CLOSED SANDBOX_GLOBALS. No g_* singletons reach the
  -- script. `storage` is a memory-only scratch table owned by the script record, so it
  -- survives across ticks and reloads within a session (never written to disk); it is
  -- gone when the script record is dropped (relog / fresh discovery).
  s.storage = s.storage or {}
  if setfenv then
    setfenv(fn, Scripting.makeEnv({ print = ctx.log, storage = s.storage }))
  end
  s.fn = fn
  return true
end

-- ---------------------------------------------------------------------------
-- Enable / disable (= load / unload)
-- ---------------------------------------------------------------------------
local function setEnabled(s, on)
  on = on and true or false
  if on then
    s.errors = 0
    local ok = compile(s)
    if not ok then
      if modules.game_textmessage then
        modules.game_textmessage.displayFailureMessage(htr('Script has a syntax error; see Debug. Not loaded.'))
      end
      return false
    end
    s.enabled = true        -- set before the body runs so its Timers see it enabled
    runScriptOnce(s)        -- run the file body exactly once; it registers Timers/events
  else
    s.enabled = false
    stopScript(s)
  end
  refreshAutoLoadList()
  save()
  return true
end

-- ---------------------------------------------------------------------------
-- The two lists
-- ---------------------------------------------------------------------------
local function makeRow(listW, name, running)
  if not listW then return end
  local row = g_ui.createWidget('ScriptListRow', listW)
  row:setText(name)
  row:setColor(running and '#9fe08a' or '#cccccc')
  row:setOn(name == selName)
  row.scriptName = name
  -- Select on PRESS, not on release (onClick): inside the helper MainWindow the
  -- release-time onClick is unreliable, so left-clicking a row would silently fail.
  row.onMousePress = function(_, mp, btn)
    if btn == MouseRightButton then Scripting.scriptMenu(name, mp); return true end
    if btn == MouseLeftButton then Scripting.selectScript(name); return true end
    return false
  end
  row.onDoubleClick = function()
    local s = scripts[name]
    if s then setEnabled(s, not s.enabled); Scripting.refreshLists() end
  end
end

function Scripting.refreshLists()
  if disabledListW then disabledListW:destroyChildren() end
  if enabledListW then enabledListW:destroyChildren() end
  for _, name in ipairs(order) do
    local s = scripts[name]
    if s then
      if s.enabled then makeRow(enabledListW, name, true)
      else makeRow(disabledListW, name, false) end
    end
  end
end

function Scripting.selectScript(name)
  if not scripts[name] then return end
  selName = name
  for _, listW in ipairs({ disabledListW, enabledListW }) do
    if listW then
      for _, c in ipairs(listW:getChildren()) do c:setOn(c.scriptName == name) end
    end
  end
  save()
end

-- Query helpers (used by Engine.loadScript/isScriptLoaded). hasScript: a script with
-- this name exists in the list; isLoaded: it exists AND is currently running.
function Scripting.hasScript(name) return name ~= nil and scripts[name] ~= nil end
function Scripting.isLoaded(name)
  local s = name and scripts[name]
  return (s and s.enabled) and true or false
end

-- ---------------------------------------------------------------------------
-- Load / unload (move between the boxes)
-- ---------------------------------------------------------------------------
function Scripting.loadSelected()
  local s = selName and scripts[selName]
  if not s then setStatus(htr('Select a script first.'), '#cc4444'); return end
  if s.enabled then return end
  if setEnabled(s, true) then
    Scripting.refreshLists()
    setStatus(htr('Loaded "%s"', selName), '#44ad25')
  else
    setStatus(htr('Syntax error - see Debug.'), '#cc4444')
  end
end

function Scripting.unloadSelected()
  local s = selName and scripts[selName]
  if not s then setStatus(htr('Select a script first.'), '#cc4444'); return end
  if not s.enabled then return end
  setEnabled(s, false)
  Scripting.refreshLists()
  setStatus(htr('Unloaded "%s"', selName), '#c0c0c0')
end

-- Reload = stop + start the selected RUNNING script. compile() re-reads the file, so
-- this picks up edits to the .lua without having to Unload then Load again: the
-- script's timers/events/HUDs are torn down and its body runs once more.
function Scripting.reloadSelected()
  local s = selName and scripts[selName]
  if not s then setStatus(htr('Select a script first.'), '#cc4444'); return end
  if not s.enabled then setStatus(htr('"%s" is not running.', selName), '#cc4444'); return end
  setEnabled(s, false)          -- stop the script's timers/events/HUDs
  if setEnabled(s, true) then   -- recompile from file + run the body again
    Scripting.refreshLists()
    setStatus(htr('Reloaded "%s"', selName), '#44ad25')
  else
    Scripting.refreshLists()    -- failed compile leaves it disabled; show it moved
    setStatus(htr('Reload failed (syntax error) - see Debug.'), '#cc4444')
  end
end

-- ---------------------------------------------------------------------------
-- Scripts folder
-- ---------------------------------------------------------------------------
function Scripting.openFolder()
  ensureDir()
  local real = scriptsRealDir()
  local ok = pcall(function() g_platform.openDir(real) end)
  if not ok then
    setStatus(htr('Could not open: %s', real), '#cc4444')
  end
  scheduleEvent(function() Scripting.rescan() end, 1500)
end

function Scripting.scriptMenu(name, mousePos)
  local menu = g_ui.createWidget('PopupMenu')
  menu:setGameMenu(true)
  local s = scripts[name]
  menu:addOption((s and s.enabled) and htr('Unload') or htr('Load'), function()
    Scripting.selectScript(name)
    if s and s.enabled then Scripting.unloadSelected() else Scripting.loadSelected() end
  end)
  if s and s.enabled then
    menu:addOption(htr('Reload'), function()
      Scripting.selectScript(name)
      Scripting.reloadSelected()
    end)
  end
  menu:addOption(htr('Open Scripts Folder'), function() Scripting.openFolder() end)
  menu:display(mousePos)
end

-- ---------------------------------------------------------------------------
-- Debug console window
-- ---------------------------------------------------------------------------
function Scripting.openDebug()
  if debugWindow then debugWindow:raise(); debugWindow:focus(); return end
  local w = g_ui.createWidget('ScriptDebugWindow', g_ui.getRootWidget())
  debugWindow = w
  debugListW   = w:recursiveGetChildById('debugList')
  debugScrollW = w:recursiveGetChildById('debugScroll')
  debugSelectW = w:recursiveGetChildById('debugSelectText')

  if debugSelectW and debugListW then
    debugListW.onScrollChange = function(_, offset) debugSelectW:setTextVirtualOffset(offset) end
    debugSelectW.onMouseWheel = function(_, mousePos, dir) return debugListW:onMouseWheel(mousePos, dir) end
  end

  if debugListW then
    for _, line in ipairs(debugLines) do
      local row = g_ui.createWidget('ScriptDebugRow', debugListW)
      row:setText(line.text); row:setColor(line.color)
    end
  end
  refreshDebugSelection()
  pcall(function() if debugScrollW then debugScrollW:setValue(debugScrollW:getMaximum()) end end)

  local function close()
    debugListW = nil; debugScrollW = nil; debugSelectW = nil
    if debugWindow then debugWindow:destroy(); debugWindow = nil end
  end
  w.onEscape = close
  w.onEnter = close
  w:recursiveGetChildById('closeBtn').onClick = close
  w:recursiveGetChildById('clearBtn').onClick = function()
    debugLines = {}
    if debugListW then debugListW:destroyChildren() end
    if debugSelectW then debugSelectW:setText('') end
  end
  w:recursiveGetChildById('copyAllBtn').onClick = function()
    local parts = {}
    for i = 1, #debugLines do parts[i] = debugLines[i].text end
    g_window.setClipboardText(table.concat(parts, '\n'))
  end
end

-- ---------------------------------------------------------------------------
-- Load
-- ---------------------------------------------------------------------------
local function load()
  scripts, order, selName = {}, {}, nil
  local enabledSet = {}
  autoLoadList = {}
  autoReload = true
  local p = configPath()
  if p and g_resources.fileExists(p) then
    local ok, res = pcall(function() return json.decode(g_resources.readFileContents(p)) end)
    if ok and type(res) == 'table' then
      for _, name in ipairs(res.enabled or {}) do enabledSet[name] = true; autoLoadList[#autoLoadList + 1] = name end
      selName = res.selected
      autoReload = (res.autoReload ~= false)  -- default ON
    end
  end
  ensureDir()
  seedExamples()   -- copy the bundled example/test scripts into /bot_scripts (once)
  local files = listScripts()
  -- Fallback: only if seeding found nothing AND the folder is still empty, drop a
  -- minimal starter script so a fresh install never shows an empty list.
  if #files == 0 then
    pcall(function()
      g_resources.writeFileContents(SCRIPTS_DIR .. '/example.lua',
        '-- Example script (Zerobot dialect). The file body runs ONCE on load.\n' ..
        '-- For recurring work register a Timer; for reactions use Game.registerEvent.\n' ..
        '-- See the scripting docs (wiki) and the bundled test_*.lua examples.\n\n' ..
        'print("script loaded, HP " .. Player.getHealthPercent() .. "%")\n\n' ..
        'Timer("tick", function()\n' ..
        '  print("HP " .. Player.getHealthPercent() .. "%")\n' ..
        'end, 5000, true)\n')
    end)
    files = listScripts()
  end
  for _, name in ipairs(files) do
    scripts[name] = { name = name, enabled = false, storage = {}, errors = 0, cleanups = {} }
    order[#order + 1] = name
  end
  if autoReload then
    -- Crash-loop guard (see helpers above): if a script killed the client while loading
    -- last session, its name is still in the marker file -> don't re-enable it (poison).
    local poison = readLoadGuardName()
    if poison and enabledSet[poison] then
      enabledSet[poison] = nil
      debugAppend(poison .. ': travou o cliente ao carregar na sessao passada; desativado do ' ..
                  'auto-reload. Revise o script e reative manualmente.', '#ff6666')
    end
    for _, name in ipairs(order) do
      if enabledSet[name] then
        setLoadGuard(name)               -- persist the marker BEFORE the body runs (sync)
        setEnabled(scripts[name], true)  -- if it hard-crashes here, the marker points at `name`
      end
    end
    clearLoadGuard()                     -- everyone survived: drop the marker
    -- Persist the auto-load list without the poisoned script (covers the case where it
    -- was the ONLY enabled script, so no setEnabled ran to re-save it out).
    refreshAutoLoadList()
    save()
  end
  if not selName or not scripts[selName] then selName = order[1] end
  if autoReloadW then
    suppressAutoReloadSave = true
    autoReloadW:setChecked(autoReload)
    suppressAutoReloadSave = false
  end
end

function Scripting.rescan()
  if not panel then return end
  ensureDir()
  local files = listScripts()
  local present = {}
  for _, name in ipairs(files) do present[name] = true end
  for name, s in pairs(scripts) do
    if not present[name] then stopScript(s); s.enabled = false; scripts[name] = nil end
  end
  for _, name in ipairs(files) do
    if not scripts[name] then
      scripts[name] = { name = name, enabled = false, storage = {}, errors = 0, cleanups = {} }
    end
  end
  order = {}
  for _, name in ipairs(files) do order[#order + 1] = name end
  if not selName or not scripts[selName] then selName = order[1] end
  lastFolderSig = table.concat(files, '|')
  Scripting.refreshLists()
  save()
end

function Scripting.autoRescan()
  if not panel or not panel:isVisible() or not g_game.isOnline() then return end
  local sig = table.concat(listScripts(), '|')
  if sig ~= lastFolderSig then Scripting.rescan() end
end

local function onAutoReloadChange(_, checked)
  if suppressAutoReloadSave then return end
  autoReload = checked and true or false
  save()
end

-- ---------------------------------------------------------------------------
-- UI mounting -- the ScriptingPanel is a child of mainContent (Amon arch). The
-- panel widget is created by helper.lua and passed to Scripting.init(); we just
-- wire up its children here.
-- ---------------------------------------------------------------------------
local function wireUI(p)
  panel = p
  panel:setId('scriptingPanel')
  panel:hide()

  disabledListW = panel:recursiveGetChildById('disabledList')
  enabledListW  = panel:recursiveGetChildById('enabledList')
  statusLabel   = panel:recursiveGetChildById('scriptingStatus')
  autoReloadW   = panel:recursiveGetChildById('autoReloadCheck')
  if autoReloadW then
    autoReloadW:setChecked(autoReload)
    autoReloadW.onCheckChange = onAutoReloadChange
  end
  return true
end

-- ---------------------------------------------------------------------------
-- Lifecycle (called by helper.lua)
--   Scripting.init(panelWidget)  -- wire the ScriptingPanel (already in mainContent)
--   Scripting.online()           -- on login: build the API, load saved scripts
--   Scripting.offline()          -- on logout: stop everything, save
--   Scripting.terminate()        -- on module unload
--   Scripting.showPanel()/hidePanel() -- from loadMenu
-- ---------------------------------------------------------------------------
function Scripting.init(container)
  if not container then return end
  if not initialized then
    initialized = true
    -- Import styles HERE, not at chunk load: the panel's buttons derive from
    -- HelperButton, which only exists once helper.otui has been displayed. helper.lua
    -- calls Scripting.init() AFTER its displayUI, so HelperButton is defined by now.
    -- Absolute path so it resolves regardless of the calling module's directory.
    g_ui.importStyle('/game_helper/scripting/styles/scripting')
  end
  -- Create the panel programmatically. helper.otui no longer declares ScriptingPanel,
  -- which avoids a circular style dependency (scripting.otui needs HelperButton, which
  -- lives in helper.otui). wireUI() assigns its id ('scriptingPanel') and hides it.
  if panel then return end  -- already created; don't duplicate on a re-init
  local p = g_ui.createWidget('ScriptingPanel', container)
  wireUI(p)
end

function Scripting.online()
  loadApi()  -- build the ZB_API namespaces once (idempotent across relogs)
  load()  -- re-enables the scripts that were running last session (runs each body once)
  lastFolderSig = table.concat(order, '|')
  Scripting.refreshLists()
  setStatus(htr('Ready'), '#c0c0c0')
  if rescanEvent then removeEvent(rescanEvent) end
  rescanEvent = cycleEvent(Scripting.autoRescan, 2000) -- folder watch (only while tab visible)
end

function Scripting.offline()
  for _, s in pairs(scripts) do stopScript(s) end  -- cancel every script's timers/events/HUDs
  Scripting.stopSnippets()  -- and every cavebot waypoint snippet's (separate registry)
  if rescanEvent then removeEvent(rescanEvent); rescanEvent = nil end
  save()
end

function Scripting.terminate()
  for _, s in pairs(scripts) do stopScript(s) end
  Scripting.stopSnippets()
  if rescanEvent then removeEvent(rescanEvent); rescanEvent = nil end
  if debugWindow then debugWindow:destroy(); debugWindow = nil end
  debugListW, debugScrollW, debugSelectW = nil, nil, nil
  panel = nil
end

function Scripting.showPanel()
  if not panel then return end
  panel:show()
  if g_game.isOnline() then Scripting.rescan() end
end

function Scripting.hidePanel() if panel then panel:hide() end end

-- NOTE: styles are imported and the panel is created in Scripting.init() (called by
-- helper.lua after its displayUI), NOT at chunk load -- the panel's HelperButton-based
-- buttons require helper.otui to have been displayed (HelperButton defined) first.
